; # x-python -- Python on x-lang
;
; ## python/parse.x -- tokens to forms
;
; @description Precedence-climbing over the token stream, emitting calls to
;   python/runtime rather than to x's operators.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## THE SHAPE: (form . rest)
;
; Every parse function takes a token list and returns a pair of the form it
; built and the tokens it did not consume. No mutable cursor, no index
; arithmetic, and a parser that backtracks by simply not using its result.
;
; ## PRECEDENCE IS A LADDER, NOT A TABLE
;
; One function per level, each calling the next tighter one. It is more lines
; than a table-driven climb and it is what makes the grammar readable as
; grammar: `comparison` is written in terms of `sum`, which is written in terms
; of `product`. Python's own reference reads the same way.
;
;   comparison   ==  !=  <  >  <=  >=      left
;   sum          +  -                      left
;   product      *  /  //  %               left
;   unary        -                         prefix
;   power        **                        RIGHT -- 2**3**2 is 2**(3**2)
;   postfix      f(...)                    left
;   atom         number  string  name  ( ) 
;
; ## NUMBERS ARE READ BY x's OWN READER
;
; A literal's text goes through the sexp reader on a default base, which is what
; lib/x/repl/ansi.x does to turn a code string into forms. That hands back the
; whole numeric tower for free -- and Python 3's int being arbitrary-precision
; makes that not a convenience but a requirement.
;
; It is also where the spellings diverge: `1_000` and `0x10` are Python numbers
; that x's reader does not spell the same way, and they will need handling here
; rather than a different reader.

(import python/tokens)
(import python/indent)
(import python/runtime)

(provide python/parse python-parse python-parse-expr)

(def %py-read-str (prim-ref (lit tok) (lit read-str)))
; ONE default base, built once.  It carries the sexp types, which is exactly
; what is wanted here and exactly what is not wanted for Python's own source.
(def %py-sexp-base (Base make))

(def %py-char->int (prim-ref (lit char) (lit ->int)))

; A FLOAT LITERAL CANNOT BE READ IN %py-sexp-base.  That base is a `(Base make)`
; child, and float is a LIBRARY type registered on whichever base loaded it -- a
; child base has none of the tower.  The int type there then accepts the "1"
; prefix of "1.5" and the fraction is dropped SILENTLY: `print(2 * 1.5)` answered
; 2.  `Float from` reads it in the ambient base, which has the tower.
;
; This is the same constraint that decided python/types.x, in a smaller place:
; work in the base that already has what you need.
; UNDERSCORES ARE SPELLING, NOT VALUE.  The tokenizer accepts `1_000.1_8`
; loosely and this is the strip that makes the pair honest: everything the
; lexer let through is removed before either number path parses.
(def %py-num-strip
  (fn (_ s)
    (if (null? (Str8 index-of "_" s))
      s
      (do
        (def n (Str8 length s))
        (def go
          (fn (self i acc)
            (if (>= i n)
              acc
              (let ((c (Str8 sub i 1 s)))
                (self (+ i 1)
                  (if (Str8 =? c "_") acc (Str8 append acc c)))))))
        (go 0 "")))))

; A dot OR an exponent makes it a float: `1e10` has no dot and is not an int,
; and the sexp reader would silently answer 1 for it (the reader drops
; exponents, x-lang#577) -- so the routing must look for both spellings.
(def %py-num-float-text?
  (fn (_ t)
    (if (not (null? (Str8 index-of "." t))) #t
      (if (not (null? (Str8 index-of "e" t))) #t
        (not (null? (Str8 index-of "E" t)))))))

; An imaginary literal is its magnitude as a float on the imaginary axis;
; complex parts are always floats in Python, so `2j` is 0.0+2.0j.
(def %py-num-imag?
  (fn (_ t)
    (let ((c (%py-char->int (Str8 ref (- (Str8 length t) 1) t))))
      (if (= c 106) #t (= c 74)))))

; 0x 0o 0b literals: the base from the second character, digits after it.
(def %py-num-base-of
  (fn (_ t)
    (if (< (Str8 length t) 3) ()
      (if (not (= (%py-char->int (Str8 ref 0 t)) 48)) ()
        (let ((c (%py-char->int (Str8 ref 1 t))))
          (if (if (= c 120) #t (= c 88)) 16
            (if (if (= c 111) #t (= c 79)) 8
              (if (if (= c 98) #t (= c 66)) 2 ()))))))))

(def %py-num
  (fn (self text)
    (let ((t (%py-num-strip text)))
      ; a signed based literal (-0x10 alone) is the sign applied to the rest
      (if (if (if (= (%py-char->int (Str8 ref 0 t)) 45) #t (= (%py-char->int (Str8 ref 0 t)) 43))
            (not (null? (%py-num-base-of (Str8 sub 1 (- (Str8 length t) 1) t))))
            #f)
        (let ((v (self (Str8 sub 1 (- (Str8 length t) 1) t))))
          (if (= (%py-char->int (Str8 ref 0 t)) 45) (%py-neg v) v))
      (if (not (null? (%py-num-base-of t)))
        (%py-int-of-based (Str8 sub 2 (- (Str8 length t) 2) t) (%py-num-base-of t))
      (if (%py-num-imag? t)
        (Complex make 0.0 (Float from (Str8 sub 0 (- (Str8 length t) 1) t)))
      (if (%py-num-float-text? t)
        (Float from t)
        ; THE HAND PARSER, NOT THE CHILD BASE: %py-sexp-base is a (Base make)
        ; child and bigint is a library type it does not carry, so a literal
        ; past 2^63 WRAPPED silently.  %py-int-of-str promotes through the
        ; tower.
        (%py-int-of-str t))))))))

; --- Token helpers -----------------------------------------------------------
; Guarded for the same reason as python/indent.x's %py-tok-type: (first 2)
; segfaults rather than raising (x-engine-c#16), and a bare value can still
; reach here from the tokenizer.
(def %py-tag (fn (_ t) (if (pair? t) (first t) ())))
(def %py-val (fn (_ t) (first (rest t))))

(def %py-op-is?
  (fn (_ t s)
    (if (null? t) #f
      (if (eq? (%py-tag t) (lit tok-op)) (Str8 =? (%py-val t) s) #f))))

(def %py-name-is?
  (fn (_ t s)
    (if (null? t) #f
      (if (eq? (%py-tag t) (lit tok-name)) (Str8 =? (%py-val t) s) #f))))

; The operator at the head, as one of a set -- returns the runtime function's
; symbol or nil.  A table rather than a chain of ifs at each level, because the
; levels differ only in which operators they accept.
(def %py-op-sym
  (fn (_ t table)
    (if (null? t) ()
      (if (eq? (%py-tag t) (lit tok-op))
        (let ((v (%py-val t)))
          (def %look
            (fn (self rows)
              (if (null? rows) ()
                (if (Str8 =? v (first (first rows)))
                  (first (rest (first rows)))
                  (self (rest rows))))))
          (%look table))
        ()))))

; --- Signed numbers in operator position ------------------------------------
; The tokenizer claims `+2` and `-3` as number tokens, because that is the only
; way to outscore the sexp integer type (see python/tokens.x).  Here is where
; the sign comes back off: with a left operand already parsed, a signed number
; IS an operator followed by a literal.  `1-2` is a subtraction; `-2` alone,
; with nothing to its left, is the literal it looks like.
(def %py-signed?
  (fn (_ t)
    (if (null? t) #f
      (if (eq? (%py-tag t) (lit tok-number))
        (let ((v (%py-val t)))
          (if (> (Str8 length v) 1)
            (let ((c (%py-char->int (Str8 ref 0 v))))
              (if (= c 43) #t (= c 45)))
            #f))
        #f))))

(def %py-signed-op   (fn (_ t) (Str8 sub 0 1 (%py-val t))))
(def %py-signed-num
  (fn (_ t)
    (let ((v (%py-val t)))
      (mk-tok-number (Str8 sub 1 (- (Str8 length v) 1) v)))))

; Augmented assignment: the operator that folds the old value with the new.
(def %py-aug-ops
  (list (list "+=" (lit %py-add)) (list "-=" (lit %py-sub))
        (list "*=" (lit %py-mul)) (list "/=" (lit %py-div))
        (list "%=" (lit %py-mod))))

(def %py-cmp-ops
  (list (list "==" (lit %py-eq)) (list "!=" (lit %py-ne))
        (list "<"  (lit %py-lt)) (list ">"  (lit %py-gt))
        (list "<=" (lit %py-le)) (list ">=" (lit %py-ge))))
(def %py-sum-ops
  (list (list "+" (lit %py-add)) (list "-" (lit %py-sub))))
; The bitwise levels sit between comparison and arithmetic, loosest first:
; | then ^ then &, Python's own order.
(def %py-bor-ops  (list (list "|" (lit %py-bitor))))
(def %py-bxor-ops (list (list "^" (lit %py-bitxor))))
(def %py-band-ops (list (list "&" (lit %py-bitand))))
(def %py-shift-ops
  (list (list "<<" (lit %py-lshift)) (list ">>" (lit %py-rshift))))
(def %py-product-ops
  (list (list "*" (lit %py-mul)) (list "/" (lit %py-div))
        (list "//" (lit %py-floordiv)) (list "%" (lit %py-mod))))

; --- The ladder --------------------------------------------------------------
(def %py-comparison ())
(def %py-bor ())
(def %py-bxor ())
(def %py-band ())
(def %py-shift ())
(def %py-sum ())
(def %py-product ())
(def %py-unary ())
(def %py-power ())
(def %py-postfix ())
(def %py-atom ())

; A left-associative level: parse the tighter thing, then fold while the head is
; one of ours.  Written once and shared by all three, because the only thing
; that differs is the operator table and the next level down.
(def %py-left
  (fn (_ toks table next)
    (def %first (next toks))
    ; `more`, NOT `rest`: naming a parameter `rest` shadows the builtin, so
    ; (rest more) inside the loop called a LIST as a function.  Every expression
    ; failed with "unexpected end of input" because the tail never advanced.
    (def %go
      (fn (self acc more)
        (def %head (if (null? more) () (first more)))
        (def %sym (%py-op-sym %head table))
        (if (null? %sym)
          ; Not a bare operator.  A SIGNED NUMBER here is one: we have a left
          ; operand, so the sign binds as an operator and the digits are its
          ; right-hand side.
          (if (%py-signed? %head)
            (let ((opsym (%py-op-sym (mk-tok-op (%py-signed-op %head)) table)))
              (if (null? opsym)
                (pair acc more)
                (let ((r (next (pair (%py-signed-num %head) (rest more)))))
                  (self (list opsym acc (first r)) (rest r)))))
            (pair acc more))
          (let ((r (next (rest more))))
            (self (list %sym acc (first r)) (rest r))))))
    (%go (first %first) (rest %first))))

; `in` and `not in` are comparison-level operators spelled as NAMES, so the
; table walk cannot see them; a wrapper reads them after the ordinary
; comparison parse.  The for-statement and comprehension `in`s are consumed
; POSITIONALLY by their own parsers before any expression parse begins, so
; this never collides with them.
(set! %py-comparison
  (fn (_ toks)
    (let ((r (%py-left toks %py-cmp-ops %py-bor)))
      (def more (rest r))
      (if (%py-name-is? (if (null? more) () (first more)) "in")
        (let ((rhs (%py-left (rest more) %py-cmp-ops %py-bor)))
          (pair (list (lit %py-in) (first r) (first rhs)) (rest rhs)))
        (if (if (%py-name-is? (if (null? more) () (first more)) "not")
              (%py-name-is? (if (null? (rest more)) () (first (rest more))) "in")
              #f)
          (let ((rhs (%py-left (rest (rest more)) %py-cmp-ops %py-bor)))
            (pair (list (lit not) (list (lit %py-in) (first r) (first rhs)))
              (rest rhs)))
          r)))))
(set! %py-bor  (fn (_ toks) (%py-left toks %py-bor-ops %py-bxor)))
(set! %py-bxor (fn (_ toks) (%py-left toks %py-bxor-ops %py-band)))
(set! %py-band (fn (_ toks) (%py-left toks %py-band-ops %py-shift)))
(set! %py-shift (fn (_ toks) (%py-left toks %py-shift-ops %py-sum)))

; --- or / and / not ----------------------------------------------------------
;
; PYTHON'S and/or RETURN AN OPERAND, NOT A BOOLEAN.  `[] or 5` is 5 and
; `0 and x` is 0 -- the truth TEST picks which operand, and the operand itself
; is the answer.  So each emits a let binding the left side once (it must not
; evaluate twice) and an if over (%py-truthy ...) choosing between the bound
; value and the right side -- which also gives short-circuit for free, because
; the right side sits in an if branch that may never run.
;
; The temp is %py-lhs, which cannot collide: every Python name is emitted with
; a py- prefix, and nesting shadows it correctly because the inner form's only
; reference to it is within the inner let.
;
; Precedence, loosest first: or, then and, then not, then comparison -- so
; `not a == b` is not(a == b), Python's reading.

(def %py-not-e ())
(def %py-and-e ())
(def %py-or-e ())

(set! %py-not-e
  (fn (_ toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "not")
      (let ((r (%py-not-e (rest toks))))
        (pair (list (lit not) (list (lit %py-truthy) (first r))) (rest r)))
      (%py-comparison toks))))

(def %py-bool-fold
  (fn (self kw emit next toks)
    (def %go
      (fn (go2 acc more)
        (if (%py-name-is? (if (null? more) () (first more)) kw)
          (let ((r (next (rest more))))
            (go2 (emit acc (first r)) (rest r)))
          (pair acc more))))
    (let ((f (next toks)))
      (%go (first f) (rest f)))))

(def %py-emit-and
  (fn (_ l r)
    (list (lit let) (list (list (lit %py-lhs) l))
      (list (lit if) (list (lit %py-truthy) (lit %py-lhs)) r (lit %py-lhs)))))

(def %py-emit-or
  (fn (_ l r)
    (list (lit let) (list (list (lit %py-lhs) l))
      (list (lit if) (list (lit %py-truthy) (lit %py-lhs)) (lit %py-lhs) r))))

(set! %py-and-e
  (fn (_ toks) (%py-bool-fold "and" %py-emit-and %py-not-e toks)))
(set! %py-or-e
  (fn (_ toks) (%py-bool-fold "or" %py-emit-or %py-and-e toks)))
(set! %py-sum        (fn (_ toks) (%py-left toks %py-sum-ops %py-product)))
(set! %py-product    (fn (_ toks) (%py-left toks %py-product-ops %py-unary)))

(set! %py-unary
  (fn (_ toks)
    (def t (if (null? toks) () (first toks)))
    (if (%py-op-is? t "-")
      (let ((r (%py-unary (rest toks))))
        (pair (list (lit %py-neg) (first r)) (rest r)))
      (if (%py-op-is? t "+")
        (let ((r (%py-unary (rest toks))))
          (pair (list (lit %py-pos) (first r)) (rest r)))
        (if (%py-op-is? t "~")
          (let ((r (%py-unary (rest toks))))
            (pair (list (lit %py-invert) (first r)) (rest r)))
          (%py-power toks))))))

; RIGHT-ASSOCIATIVE, and it matters: 2**3**2 is 2**(3**2) = 512, not 64.  The
; recursion goes back to `unary` rather than to `power`, which is also how
; Python binds a unary minus tighter on the right of ** than on the left.
(set! %py-power
  (fn (_ toks)
    (def %head (if (null? toks) () (first toks)))
    ; `-2 ** 2` IS `-(2 ** 2)`, which is -4, not `(-2) ** 2` = 4.  Unary minus
    ; binds LOOSER than **, and the tokenizer has already glued the sign to the
    ; literal -- so a signed literal standing in front of ** has to give its
    ; sign back before the power is taken.  Getting this wrong produces a
    ; different number rather than an error, which is the whole hazard of
    ; claiming signed literals in the tokenizer.
    (if (if (%py-signed? %head)
          (%py-op-is? (if (null? (rest toks)) () (first (rest toks))) "**")
          #f)
      (let ((r (%py-power (pair (%py-signed-num %head) (rest toks)))))
        (if (= (%py-char->int (Str8 ref 0 (%py-val %head))) 45)
          (pair (list (lit %py-neg) (first r)) (rest r))
          r))
      (%py-power-tail toks))))

(def %py-power-tail
  (fn (_ toks)
    (def %base (%py-postfix toks))
    (if (%py-op-is? (if (null? (rest %base)) () (first (rest %base))) "**")
      (let ((r (%py-unary (rest (rest %base)))))
        (pair (list (lit %py-pow) (first %base) (first r)) (rest r)))
      %base)))

; Calls, left-associative so f(1)(2) works when there is something to return a
; callable.  Subscripts and attributes belong here too and are not here yet.
(set! %py-postfix
  (fn (_ toks)
    (def %a (%py-atom toks))
    (def %go
      (fn (self acc more)
        (if (%py-group? (if (null? more) () (first more)) "(")
          (self (%py-call-form acc (%py-group-of (first more)))
                (rest more))
          ; Attribute access binds like a call, and yields a VALUE -- the
          ; bound method -- so `f = x.append` works and a following `(` simply
          ; applies it.
          (if (%py-op-is? (if (null? more) () (first more)) ".")
            (let ((n (if (null? (rest more)) () (first (rest more)))))
              (if (not (eq? (%py-tag n) (lit tok-name)))
                (Err raise (lit syntax) "expected a name after ." ())
                (self (list (lit %py-getattr) acc (%py-val n))
                      (rest (rest more)))))
          ; Subscript binds like a call: left-associative, same level.
          (if (%py-group? (if (null? more) () (first more)) "[")
            (self
              (if (%py-slice-group? (%py-group-of (first more)))
                (%py-slice-form acc (%py-group-of (first more)))
                (list (lit %py-index) acc
                  (%py-expr-of (%py-group-of (first more)))))
              (rest more))
            (pair acc more))))))
    (%go (first %a) (rest %a))))

; --- Groups ------------------------------------------------------------------
;
; A BRACKETED RUN ARRIVES ALREADY NESTED.  python/tokens.x reads it through the
; engine's own reader loop, so it is one token -- (tok-group "[" (tok ...)) --
; whose contents are a complete token list ending exactly where the bracket did.
;
; Everything below is smaller because of that.  There is no closing bracket to
; find, so no "expected , or ] in list literal" scan.  And splitting on commas
; needs NO DEPTH COUNT, because an inner group is a single token at this level:
; the nesting the old scanners had to rediscover is already the shape.

(def %py-super-call?
  (fn (_ toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "super")
      (%py-group? (if (null? (rest toks)) () (first (rest toks))) "(")
      #f)))

(def %py-group?
  (fn (_ t o)
    (if (pair? t)
      (if (eq? (first t) (lit tok-group)) (Str8 =? (first (rest t)) o) #f)
      #f)))

(def %py-group-of (fn (_ t) (first (rest (rest t)))))

(def %py-comma-split
  (fn (self toks cur acc)
    (if (null? toks)
      (List reverse (if (null? cur) acc (pair (List reverse cur) acc)))
      (if (%py-op-is? (first toks) ",")
        (self (rest toks) () (if (null? cur) acc (pair (List reverse cur) acc)))
        (self (rest toks) (pair (first toks) cur) acc)))))

(def %py-has-comma?
  (fn (self toks)
    (if (null? toks)
      #f
      (if (%py-op-is? (first toks) ",") #t (self (rest toks))))))

; One complete expression from a complete token list -- anything left over is a
; syntax error HERE, where the bracket that bounded it is known.
(def %py-expr-of
  (fn (_ toks)
    (if (null? toks)
      (Err raise (lit syntax) "expected an expression" ())
      (let ((r (%py-or-e toks)))
        (if (null? (rest r))
          (first r)
          (Err raise (lit syntax) "unexpected token after an expression" ()))))))

(def %py-exprs-of
  (fn (self parts acc)
    (if (null? parts)
      (List reverse acc)
      (self (rest parts) (pair (%py-expr-of (first parts)) acc)))))

(def %py-group-exprs
  (fn (_ elems) (%py-exprs-of (%py-comma-split elems () ()) ())))

; A CALL WITH A *spread BECOMES apply: the argument parts are gathered into
; segments -- (list e1 e2) for plain arguments, (%py-iter-elems s) for a
; spread -- and %py-splat concatenates them into the one argument list.
; Without a spread the call is the plain form it always was.
(def %py-spread-part?
  (fn (_ part) (if (null? part) #f (%py-op-is? (first part) "*"))))

; A keyword argument is NAME = EXPR as one comma-part.
(def %py-kw-part?
  (fn (_ part)
    (if (null? part) #f
      (if (null? (rest part)) #f
        (if (eq? (%py-tag (first part)) (lit tok-name))
          (%py-op-is? (first (rest part)) "=")
          #f)))))

; The positional arguments as one form: (list e1 e2) without a spread, or
; (%py-splat ...) when there is one.
(def %py-args-form
  (fn (_ parts)
    (def any-spread
      (fn (self ps)
        (if (null? ps) #f (if (%py-spread-part? (first ps)) #t (self (rest ps))))))
    (if (not (any-spread parts))
      (pair (lit list) (%py-exprs-of parts ()))
      (do
        (def segs
          (fn (self ps run acc)
            (if (null? ps)
              (List reverse (if (null? run) acc (pair (pair (lit list) (List reverse run)) acc)))
              (if (%py-spread-part? (first ps))
                (self (rest ps) ()
                  (pair (list (lit %py-iter-elems) (%py-expr-of (rest (first ps))))
                    (if (null? run) acc (pair (pair (lit list) (List reverse run)) acc))))
                (self (rest ps) (pair (%py-expr-of (first ps)) run) acc)))))
        (pair (lit %py-splat) (segs parts () ()))))))

; A CALL WITH KEYWORDS GOES THROUGH %py-kwcall, which needs the callee's
; parameter names; a method call keeps the object and the name apart
; (%py-kwcall-attr) so the method's own signature is reachable without the
; bound closure in between.
(def %py-call-form
  (fn (_ f elems)
    (def parts (%py-comma-split elems () ()))
    (def kws
      (fn (self ps)
        (if (null? ps) ()
          (if (%py-kw-part? (first ps))
            (pair (list (lit pair) (%py-val (first (first ps)))
                    (%py-expr-of (rest (rest (first ps)))))
              (self (rest ps)))
            (self (rest ps))))))
    (def poss
      (fn (self ps)
        (if (null? ps) ()
          (if (%py-kw-part? (first ps)) (self (rest ps)) (pair (first ps) (self (rest ps)))))))
    (def kw-forms (kws parts))
    (if (null? kw-forms)
      (let ((a (%py-args-form parts)))
        (if (eq? (first a) (lit list)) (pair f (rest a)) (list (lit apply) f a)))
      (let ((pos (%py-args-form (poss parts))))
        (if (if (pair? f) (eq? (first f) (lit %py-getattr)) #f)
          (list (lit %py-kwcall-attr) (first (rest f)) (first (rest (rest f)))
            pos (pair (lit list) kw-forms))
          (list (lit %py-kwcall) f pos (pair (lit list) kw-forms)))))))

; A dict entry: KEY : VALUE, split at the first colon of one comma-part.
(def %py-colon-split
  (fn (self toks acc)
    (if (null? toks)
      (Err raise (lit syntax) "expected : after a dict key" ())
      (if (%py-op-is? (first toks) ":")
        (pair (List reverse acc) (rest toks))
        (self (rest toks) (pair (first toks) acc))))))

(def %py-entries-of
  (fn (self parts acc)
    (if (null? parts)
      (List reverse acc)
      (let ((kv (%py-colon-split (first parts) ())))
        (self (rest parts)
          (pair
            (list (lit pair) (%py-expr-of (first kv)) (%py-expr-of (rest kv)))
            acc))))))

; --- Comprehensions ----------------------------------------------------------
;
; A comprehension is a bracket group whose contents contain a top-level `for` --
; and since a nested group is ONE token here, "top-level" is a flat scan, not a
; depth count.
;
; THE VARIABLE IS A let, NOT A HOISTED set!.  Python 3 gives a comprehension
; its own scope: `x = 5` then `[x for x in [9]]` leaves x at 5.  A let binds in
; the frame and vanishes with it, which is exactly that rule -- the hoisting
; the statement-level `for` needs is precisely what this must NOT do.
;
; Each `for` clause becomes the same self-recursive loop the statement emits;
; each `if` clause asks %py-truthy, as every condition now does.  A list
; accumulates through a cell and reverses once at the end.  A dict builds
; through %py-dset, so a duplicate key OVERWRITES -- Python's rule, and it
; falls out of the store function rather than needing a dedup pass.

; A subscript group with a top-level `:` is a SLICE -- flat scan, since a
; nested group is one token, so `d[{'a': 1}]`'s inner colon cannot mislead it.
(def %py-slice-group?
  (fn (self toks)
    (if (null? toks)
      #f
      (if (%py-op-is? (first toks) ":") #t (self (rest toks))))))

; Split on top-level colons into up to three segments, empties kept: `[::2]` is
; (() () (2)).  A fourth segment is a syntax error, as it is in Python.
(def %py-slice-segs ())
(set! %py-slice-segs
  (fn (self toks cur acc)
    (if (null? toks)
      (List reverse (pair (List reverse cur) acc))
      (if (%py-op-is? (first toks) ":")
        (if (>= (%py-count acc) 2)
          (Err raise (lit syntax) "too many colons in a subscript" ())
          (self (rest toks) () (pair (List reverse cur) acc)))
        (self (rest toks) (pair (first toks) cur) acc)))))

; An empty segment is the default, spelled () in the emission; a present one is
; a full expression.
(def %py-slice-part
  (fn (_ seg) (if (null? seg) () (%py-expr-of seg))))

(def %py-slice-form
  (fn (_ acc elems)
    (let ((segs (%py-slice-segs elems () ())))
      (list (lit %py-slice) acc
        (%py-slice-part (first segs))
        (%py-slice-part (if (null? (rest segs)) () (first (rest segs))))
        (%py-slice-part
          (if (null? (rest segs)) ()
            (if (null? (rest (rest segs))) ()
              (first (rest (rest segs))))))))))

(def %py-comp?
  (fn (self toks)
    (if (null? toks)
      #f
      (if (%py-name-is? (first toks) "for") #t (self (rest toks))))))

; ((sym (List ref N %py-unpacked)) ...) for a tuple target's inner let
(def %py-comp-refs
  (fn (self syms i acc)
    (if (null? syms)
      (List reverse acc)
      (self (rest syms) (+ i 1)
        (pair
          (list (first syms)
            (list (lit List) (lit ref) i (lit %py-unpacked)))
          acc)))))

(def %py-comp-bind
  (fn (_ syms inner)
    (if (null? (rest syms))
      (list (lit let)
        (list (list (first syms) (list (lit first) (lit %py-items))))
        inner)
      (list (lit let)
        (list (list (lit %py-unpacked)
                (list (lit %py-unpack) (list (lit first) (lit %py-items))
                      (%py-count syms))))
        (list (lit let) (%py-comp-refs syms 0 ()) inner)))))

(def %py-comp-loop
  (fn (_ syms iter inner)
    (list
      (list (lit fn) (list (lit self) (lit %py-items))
        (list (lit if) (list (lit null?) (lit %py-items))
          ()
          (list (lit %seq)
            (%py-comp-bind syms inner)
            (list (lit self) (list (lit rest) (lit %py-items))))))
      (list (lit %py-iter-elems) iter))))

; (for SYMS ITER-FORM) and (if COND-FORM), in source order
(def %py-comp-clauses ())
(set! %py-comp-clauses
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (if (%py-name-is? (first toks) "for")
        (let ((n (%py-for-names (rest toks) ())))
          (let ((it (%py-or-e (rest n))))
            (self (rest it)
              (pair (list (lit for) (%py-syms-of (first n) ()) (first it)) acc))))
        (if (%py-name-is? (first toks) "if")
          (let ((c (%py-or-e (rest toks))))
            (self (rest c) (pair (list (lit if) (first c)) acc)))
          (Err raise (lit syntax) "unexpected token in comprehension" (first toks)))))))

; First clause outermost: front recursion nests them the way they read.
(def %py-comp-fold ())
(set! %py-comp-fold
  (fn (self clauses inner)
    (if (null? clauses)
      inner
      (let ((c (first clauses)))
        (if (eq? (first c) (lit for))
          (%py-comp-loop (first (rest c)) (first (rest (rest c)))
            (self (rest clauses) inner))
          (list (lit if)
            (list (lit %py-truthy) (first (rest c)))
            (self (rest clauses) inner)
            ()))))))

(def %py-listcomp
  (fn (_ elems)
    (let ((r (%py-or-e elems)))
      (if (not (%py-name-is? (if (null? (rest r)) () (first (rest r))) "for"))
        (Err raise (lit syntax) "expected for in comprehension" ())
        (let ((cls (%py-comp-clauses (rest r) ())))
          (list (lit let)
            (list (list (lit %py-acc) (list (lit pair) () ())))
            (list (lit %seq)
              (%py-comp-fold cls
                (list (lit %set-first!) (lit %py-acc)
                  (list (lit pair) (first r)
                    (list (lit first) (lit %py-acc)))))
              (list (lit %py-list-new)
                (list (lit List) (lit reverse)
                  (list (lit first) (lit %py-acc)))))))))))

(def %py-dictcomp
  (fn (_ elems)
    (let ((k (%py-or-e elems)))
      (if (not (%py-op-is? (if (null? (rest k)) () (first (rest k))) ":"))
        (Err raise (lit syntax) "expected : in dict comprehension" ())
        (let ((v (%py-or-e (rest (rest k)))))
          (if (not (%py-name-is? (if (null? (rest v)) () (first (rest v))) "for"))
            (Err raise (lit syntax) "expected for in comprehension" ())
            (let ((cls (%py-comp-clauses (rest v) ())))
              (list (lit let)
                (list (list (lit %py-acc) (list (lit %py-mkdict))))
                (list (lit %seq)
                  (%py-comp-fold cls
                    (list (lit %py-dset) (lit %py-acc) (first k) (first v)))
                  (lit %py-acc))))))))))

; AN EXPRESSION LIST IS A BARE TUPLE.  `x = 1, 2` and `return 1, 2` need no
; parens in Python, and this is the rule that says so -- one comparison, and if
; a comma follows, everything up to the end of the line becomes a tuple.
(def %py-exprlist-rest ())
(set! %py-exprlist-rest
  (fn (self toks acc)
    (if (if (null? toks) #t
          (if (eq? (%py-tag (first toks)) (lit tok-newline)) #t
            (%py-block? (first toks))))
      (pair (List reverse acc) toks)
      (let ((r (%py-or-e toks)))
        (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ",")
          (self (rest (rest r)) (pair (first r) acc))
          (pair (List reverse (pair (first r) acc)) (rest r)))))))

(def %py-exprlist
  (fn (_ toks)
    (let ((r (%py-or-e toks)))
      (if (not (%py-op-is? (if (null? (rest r)) () (first (rest r))) ","))
        r
        (let ((m (%py-exprlist-rest (rest (rest r)) (list (first r)))))
          (pair (pair (lit %py-mktuple) (first m)) (rest m)))))))

; Arguments up to the closing paren.  A trailing comma is legal Python and costs
; one branch to accept.


(set! %py-atom
  (fn (_ toks)
    (if (null? toks)
      (Err raise (lit syntax) "unexpected end of input in expression" ())
      (let ((t (first toks)))
        (if (eq? (%py-tag t) (lit tok-number))
          (pair (%py-num (%py-val t)) (rest toks))
          (if (eq? (%py-tag t) (lit tok-string))
            ; QUOTED, because the form is evaluated: a bare string literal is
            ; self-evaluating in x, but a form built here is handed to eval!,
            ; and an unquoted string in head position would be called.
            (pair (%py-val t) (rest toks))
          (if (eq? (%py-tag t) (lit tok-bytes))
            (pair (list (lit %py-mkbytes) (%py-val t)) (rest toks))
          (if (eq? (%py-tag t) (lit tok-fstring))
            (pair (%py-fstring-form (%py-val t)) (rest toks))
            (if (%py-super-call? toks)
              ; `super()` -- the group is consumed with the name
              (if (null? (first %py-current-class))
                (Err raise (lit syntax) "super() outside a class" ())
                (if (null? (first %py-current-self))
                  (Err raise (lit syntax) "super() outside a method" ())
                  (pair
                    (list (lit %py-super)
                      (first %py-current-class) (first %py-current-self))
                    (rest (rest toks)))))
            (if (eq? (%py-tag t) (lit tok-name))
              (pair (%py-name->sym (%py-val t)) (rest toks))
              (if (%py-group? t "{")
                (if (%py-comp? (%py-group-of t))
                  (pair (%py-dictcomp (%py-group-of t)) (rest toks))
                  (pair
                    (pair (lit %py-mkdict)
                      (%py-entries-of (%py-comma-split (%py-group-of t) () ()) ()))
                    (rest toks)))
              (if (%py-group? t "[")
                (if (%py-comp? (%py-group-of t))
                  (pair (%py-listcomp (%py-group-of t)) (rest toks))
                  (pair
                    (pair (lit %py-mklist) (%py-group-exprs (%py-group-of t)))
                    (rest toks)))
              (if (%py-group? t "(")
                ; THE COMMA MAKES A TUPLE, NOT THE PARENS.  `(x)` is just x in
                ; Python, so a one-element tuple is spelled `(x,)` and the
                ; trailing comma is load-bearing rather than decorative -- which
                ; is why this asks whether a comma was PRESENT, not how many
                ; parts the split produced.
                (let ((elems (%py-group-of t)))
                  (if (null? elems)
                    (pair (list (lit %py-mktuple)) (rest toks))
                    (if (%py-has-comma? elems)
                      (pair
                        (pair (lit %py-mktuple) (%py-group-exprs elems))
                        (rest toks))
                      (pair (%py-expr-of elems) (rest toks)))))
                (Err raise (lit syntax) "unexpected token in expression" t))))))))))))))

; --- f-strings ---------------------------------------------------------------
;
; AN f-STRING IS A JOIN OF PARTS, expanded at parse time: literal text between
; fields, and for each {expr!conv:spec} a (%py-fmtfield EXPR "conv" SPEC)
; form whose EXPR is the field's source re-tokenized and parsed right here,
; and whose SPEC is a plain string or -- when it holds fields of its own, the
; nested-replacement case -- another expansion.  {{ and }} are literal braces.
(def %py-fs-code (fn (_ s i) (%py-char->int (Str8 ref i s))))

; The index of the } that closes the field opened at i (which is just past
; the {), counting nested braces.
(def %py-fs-close
  (fn (self s i depth)
    (if (>= i (Str8 length s))
      (Err raise (lit syntax) "f-string: expecting '}'" ())
      (let ((c (%py-fs-code s i)))
        (if (= c 123) (self s (+ i 1) (+ depth 1))
          (if (= c 125)
            (if (= depth 0) i (self s (+ i 1) (- depth 1)))
            (self s (+ i 1) depth)))))))

; The first ! or : at nesting depth zero inside a field, or nil.
(def %py-fs-split
  (fn (self s i depth)
    (if (>= i (Str8 length s))
      ()
      (let ((c (%py-fs-code s i)))
        (if (if (= c 40) #t (if (= c 91) #t (= c 123))) (self s (+ i 1) (+ depth 1))
          (if (if (= c 41) #t (if (= c 93) #t (= c 125))) (self s (+ i 1) (- depth 1))
            (if (if (= depth 0)
                  (if (= c 58) #t
                    ; `!` opens a conversion only when `=` does not follow:
                    ; {a!=b} is a comparison
                    (if (= c 33)
                      (if (< (+ i 1) (Str8 length s)) (not (= (%py-fs-code s (+ i 1)) 61)) #t)
                      #f))
                  #f)
              i
              (self s (+ i 1) depth))))))))

; {x=} DEBUG FIELDS: an expression ending in `=` (not ==, !=, <=, >=) prints
; its own text, `=` and any whitespace included, before its value -- and that
; value is the repr unless a conversion or a spec says otherwise.  The index
; of that `=`, or nil.
(def %py-fs-debug-at
  (fn (_ s)
    (def last-non-ws
      (fn (self i)
        (if (< i 0) ()
          (let ((c (%py-fs-code s i)))
            (if (if (= c 32) #t (if (= c 9) #t (= c 10))) (self (- i 1)) i)))))
    (let ((i (last-non-ws (- (Str8 length s) 1))))
      (if (null? i) ()
        (if (not (= (%py-fs-code s i) 61)) ()
          (if (= i 0) ()
            (let ((p (%py-fs-code s (- i 1))))
              (if (if (= p 61) #t (if (= p 33) #t (if (= p 60) #t (= p 62)))) () i))))))))

; A field holds an expression LIST: {x, y} is a tuple.
(def %py-fs-expr-of
  (fn (_ toks)
    (let ((r (%py-exprlist toks)))
      (if (null? (rest r))
        (first r)
        (Err raise (lit syntax) "f-string: unexpected token after an expression" ())))))

(def %py-fstring-field
  (fn (_ field)
    (def n (Str8 length field))
    (def at (%py-fs-split field 0 0))
    (def expr-s0 (if (null? at) field (Str8 sub 0 at field)))
    (def dbg (%py-fs-debug-at expr-s0))
    (def expr-s (if (null? dbg) expr-s0 (Str8 sub 0 dbg expr-s0)))
    (def tail (if (null? at) "" (Str8 sub at (- n at) field)))
    ; !conv comes first if present, then :spec
    (def conv0
      (if (if (> (Str8 length tail) 1) (= (%py-fs-code tail 0) 33) #f)
        (Str8 sub 1 1 tail)
        ""))
    (def after-conv
      (if (Str8 =? conv0 "") tail (Str8 sub 2 (- (Str8 length tail) 2) tail)))
    (def spec
      (if (if (> (Str8 length after-conv) 0) (= (%py-fs-code after-conv 0) 58) #f)
        (Str8 sub 1 (- (Str8 length after-conv) 1) after-conv)
        ""))
    (def conv
      (if (if (Str8 =? conv0 "") (if (null? dbg) #f (Str8 =? spec "")) #f) "r" conv0))
    (if (= (Str8 length (Str8 trim expr-s)) 0)
      (Err raise (lit syntax) "f-string: empty expression not allowed" ())
      (let ((form (list (lit %py-fmtfield)
                    (%py-fs-expr-of (python-tokenize expr-s))
                    conv
                    (if (null? (Str8 index-of "{" spec)) spec (%py-fstring-form spec)))))
        (if (null? dbg)
          form
          (list (lit %py-fjoin) (list (lit list) expr-s0 form)))))))

(def %py-fstring-form
  (fn (_ s)
    (def n (Str8 length s))
    (def go
      (fn (self i lit acc)
        (def flush (fn (_) (if (Str8 =? lit "") acc (pair lit acc))))
        (if (>= i n)
          (List reverse (flush))
          (let ((c (%py-fs-code s i)))
            (if (= c 123)
              (if (if (< (+ i 1) n) (= (%py-fs-code s (+ i 1)) 123) #f)
                (self (+ i 2) (Str8 append lit "{") acc)
                (let ((close (%py-fs-close s (+ i 1) 0)))
                  (self (+ close 1) ""
                    (pair (%py-fstring-field (Str8 sub (+ i 1) (- close (+ i 1)) s))
                      (flush)))))
              (if (= c 125)
                (if (if (< (+ i 1) n) (= (%py-fs-code s (+ i 1)) 125) #f)
                  (self (+ i 2) (Str8 append lit "}") acc)
                  (Err raise (lit syntax) "f-string: single '}' is not allowed" ()))
                (self (+ i 1) (Str8 append lit (Str8 sub i 1 s)) acc)))))))
    (list (lit %py-fjoin) (pair (lit list) (go 0 "" ())))))

; A Python name becomes an x symbol, EXCEPT the builtins that have a runtime
; function -- `print` is the only one so far.  A name table rather than a
; rewrite in the parser, so the list is one place.
(def %py-builtins
  (list (list "print" (lit %py-print))
        (list "True"  #t)
        (list "False" #f)
        (list "None"  ())
        (list "len"   (lit %py-len))
        (list "range" (lit %py-range))
        ; str and list are now the CLASS OBJECTS -- calling one still converts,
        ; through the %ctor entry, and `type(x) == str` is an identity compare.
        (list "str"     (lit %py-cls-str))
        (list "repr"    (lit %py-repr-of))
        (list "list"    (lit %py-cls-list))
        (list "hasattr" (lit %py-hasattr))
        (list "type"    (lit %py-cls-type))
        (list "int"     (lit %py-cls-int))
        (list "float"   (lit %py-cls-float))
        (list "bool"    (lit %py-cls-bool))
        (list "dict"    (lit %py-cls-dict))
        (list "tuple"   (lit %py-cls-tuple))
        (list "isinstance" (lit %py-isinstance))
        (list "pow"       (lit %py-pow))
        (list "abs"       (lit %py-abs))
        (list "round"     (lit %py-round))
        (list "min"       (lit %py-min))
        (list "max"       (lit %py-max))
        (list "bytearray" (lit %py-bytearray))
        (list "complex"   (lit %py-cls-complex))
        (list "hash"      (lit %py-hash))
        (list "NotImplemented" (lit %py-NotImplemented))
        (list "chr"       (lit %py-chr))
        (list "ord"       (lit %py-ord))
        (list "StopIteration"  (lit %py-exc-StopIteration))
        (list "SystemExit"     (lit %py-exc-SystemExit))
        ; The builtin exceptions are ordinary names bound to ordinary class
        ; values, so `except ValueError` and `except MyError` take one path.
        (list "Exception"         (lit %py-exc-Exception))
        (list "ArithmeticError"   (lit %py-exc-ArithmeticError))
        (list "LookupError"       (lit %py-exc-LookupError))
        (list "ZeroDivisionError" (lit %py-exc-ZeroDivisionError))
        (list "IndexError"        (lit %py-exc-IndexError))
        (list "KeyError"          (lit %py-exc-KeyError))
        (list "AttributeError"    (lit %py-exc-AttributeError))
        (list "NameError"         (lit %py-exc-NameError))
        (list "TypeError"         (lit %py-exc-TypeError))
        (list "ValueError"        (lit %py-exc-ValueError))
        (list "RuntimeError"      (lit %py-exc-RuntimeError))
        (list "SyntaxError"       (lit %py-exc-SyntaxError))))

; PYTHON'S NAMESPACE IS NOT x's, AND KEEPING THEM APART IS NOT TIDINESS.
;
; A Python name used to become the x symbol of the same spelling, so any name
; this bundle does not define resolved to whatever x happens to have bound.
; `int` is bound in x. `print(int(False))` therefore did not raise NameError --
; it CALLED x's int with arguments it never expected, and the interpreter died.
; In a spec batch that kills every case after it too: all 34 of basics/int
; reported "no result" because the first one crashed.
;
; So every Python identifier is prefixed. A Python identifier is [A-Za-z0-9_],
; so a `-` in the symbol cannot collide with one -- and an undefined name now
; fails as `Unbound SYMBOL 'py-int`, which is a diagnosable error in ONE case
; rather than a crash that takes the file.
;
; Builtins are the exception, and they are an explicit list rather than a
; fallthrough: a name is a builtin because it appears here, never because x
; happened to have it.
; ZERO-ARGUMENT `super()` IS LEXICAL.  It means the class whose body the call is
; written in, and the object bound to the enclosing method's FIRST parameter --
; neither of which any run-time value can tell you, which is why CPython gives
; methods a `__class__` cell instead of deriving it from self.  So the parser
; carries both, and both are saved and restored rather than assigned, so a class
; nested in a method or a def nested in a method does not leak its neighbour's.
(def %py-current-class (pair () ()))
(def %py-current-self (pair () ()))

(def %py-name->sym
  (fn (_ s)
    (def %look
      (fn (self rows)
        (if (null? rows)
          (%py-read-str (Base raw-of %py-sexp-base)
            (Str8 append (Str8 append "py-" s) " "))
          (if (Str8 =? s (first (first rows)))
            (first (rest (first rows)))
            (self (rest rows))))))
    (let ((r (%look %py-builtins)))
      (if (pair? r) (first r) r))))

(def python-parse-expr (fn (_ toks) (%py-or-e toks)))

; --- Statements --------------------------------------------------------------
;
; A Python statement is not an expression, and the shapes it compiles to say so:
;
;   x = e            (def x e)
;   if c: B          (if c B ())
;   if c: B else: C  (if c B C)
;   while c: B       ((fn (self) (if c (%seq B (self)) ())))
;   def f(a): B      (def f (fn (_ a) B))
;
; WHILE IS RECURSION, because x has no loop construct -- `if`, `let`, `when`,
; `unless`, `cond` and `case` are the whole of the control vocabulary.  The
; self-call sits in TAIL position, so x's TCO makes it a loop rather than a
; stack that grows with the iteration count.  Written any other way it would
; blow the stack on the first program that counts to a thousand, and x has no
; depth limit on non-tail calls to catch it (x-lang#56).

; A body is a chain of %seq, because %seq takes two.  One statement is itself.
(def %py-seq-of
  (fn (self forms)
    (if (null? forms)
      ()
      (if (null? (rest forms))
        (first forms)
        (list (lit %seq) (first forms) (self (rest forms)))))))

(def %py-skip-nl
  (fn (self toks)
    (if (null? toks)
      toks
      (if (eq? (%py-tag (first toks)) (lit tok-newline))
        (self (rest toks))
        toks))))

(def %py-stmts ())
(def %py-stmt ())

; `: BLOCK` -- the suite after a compound header.  The block arrives from the
; reader ALREADY NESTED, as (tok-block (tok ...)), so there is no INDENT to
; check for and no DEDENT to scan to: the block's contents are a complete token
; list that ends where the block ended.
; The contents of the block that follows a header, for the scans that need to
; look inside one.
(def %py-block-contents
  (fn (self toks)
    (if (null? toks)
      ()
      (if (%py-block? (first toks))
        (first (rest (first toks)))
        (self (rest toks))))))

(def %py-block? (fn (_ t) (if (pair? t) (eq? (first t) (lit tok-block)) #f)))
(def %py-block-toks (fn (_ t) (first (rest t))))

(def %py-block
  (fn (_ toks)
    (if (not (%py-op-is? (if (null? toks) () (first toks)) ":"))
      (Err raise (lit syntax) "expected : after a compound statement header" ())
      (let ((t (%py-skip-nl (rest toks))))
        (if (not (%py-block? (if (null? t) () (first t))))
          (Err raise (lit syntax) "expected an indented block" ())
          (pair
            (%py-seq-of (first (%py-stmts (%py-block-toks (first t)) ())))
            (rest t)))))))

; Statements until the token list runs out.  A block IS its token list now, so
; running out is the only end there is.
(set! %py-stmts
  (fn (self toks acc)
    (let ((t (%py-skip-nl toks)))
      (if (null? t)
        (pair (List reverse acc) t)
        (let ((r (%py-stmt t)))
          (self (rest r) (pair (first r) acc)))))))

(set! %py-stmt
  (fn (_ toks)
    (let ((t (first toks)))
      ; if / while / def are decided by the leading NAME.  They are keywords to
      ; the parser and plain names to the tokenizer, which is where that
      ; distinction belongs.
      (if (%py-name-is? t "class")
        (%py-class-stmt (rest toks))
      (if (%py-name-is? t "try")
        (%py-try (rest toks))
      (if (%py-name-is? t "raise")
        (%py-raise-stmt (rest toks))
      ; THE CONDITION IS PYTHON'S TRUTH, NOT x's.  `if []:` must not run its
      ; body: an empty list is falsy in Python and a PY-LIST instance is a
      ; non-nil value to x, so the bare value in an x `if` was silently wrong.
      ; bool() stated the rule once in %py-truthy; conditions now ask it.
      (if (%py-name-is? t "if")
        (let ((c (%py-or-e (rest toks))))
          (let ((b (%py-block (rest c))))
            (let ((e (%py-else (rest b))))
              (pair
                (list (lit if) (list (lit %py-truthy) (first c))
                  (first b) (first e))
                (rest e)))))
        (if (%py-name-is? t "for")
          (%py-for (rest toks))
        (if (%py-name-is? t "while")
          (let ((c (%py-or-e (rest toks))))
            (let ((b (%py-block (rest c))))
              (pair
                (list
                  (list (lit fn) (list (lit self))
                    (list (lit if) (list (lit %py-truthy) (first c))
                      (list (lit %seq) (first b) (list (lit self)))
                      ())))
                (rest b))))
          (if (%py-name-is? t "def")
            (%py-def (rest toks))
            (if (%py-name-is? t "return")
              ; RETURN INVOKES AN ESCAPE CONTINUATION.  It used to compile to
              ; its expression, and x returns a body's LAST value -- so a return
              ; anywhere but the tail computed and discarded. `if x < 0: return
              ; 0` fell through and answered the wrong number with no error.
              ;
              ; %py-return is bound by the enclosing def (see %py-def). A return
              ; outside a function leaves it unbound, which is an error where
              ; Python raises SyntaxError -- different words, same refusal.
              ;
              ; A bare `return` yields None.
              (let ((nxt (if (null? (rest toks)) () (first (rest toks)))))
                (if (if (null? nxt) #t
                      (if (eq? (%py-tag nxt) (lit tok-newline)) #t
                        (%py-block? nxt)))
                  (pair (list (lit %py-return) ()) (rest toks))
                  (let ((r (%py-exprlist (rest toks))))
                    (pair (list (lit %py-return) (first r)) (rest r)))))
              (if (%py-name-is? t "pass")
                (pair () (rest toks))
              (if (%py-unpack-stmt? toks)
                (%py-unpack-stmt toks)
              ; A statement can BEGIN with a unary operator (`~x`, `-x` as an
              ; expression statement); the postfix-target probe below would
              ; refuse the op token, so these go straight to the expression
              ; parser.
              (if (if (%py-op-is? t "-") #t
                    (if (%py-op-is? t "+") #t (%py-op-is? t "~")))
                (%py-or-e toks)
                ; ASSIGNMENT IS DECIDED BY WHAT FOLLOWS A TARGET, not by the
                ; shape of the first token.  Parse a postfix expression -- a
                ; name, a subscript, an attribute, a call -- and then look.
                ; If it is not an assignment the tokens are re-parsed as a full
                ; expression from the start, which costs a second pass over one
                ; statement and keeps the two cases from having to agree about
                ; precedence.
                (let ((tgt (%py-postfix toks)))
                  (let ((nxt (if (null? (rest tgt)) () (first (rest tgt)))))
                    (if (%py-op-is? nxt "=")
                      (let ((r (%py-exprlist (rest (rest tgt)))))
                        (pair (%py-store (first tgt) (first r)) (rest r)))
                      (let ((aug (%py-op-sym nxt %py-aug-ops)))
                        (if (null? aug)
                          (%py-or-e toks)
                          ; `t op= v` is `t = t op v`.  The target is evaluated
                          ; twice for a subscript, which is wrong for an
                          ; expression with side effects and right for every
                          ; case this handles today.
                          (let ((r (%py-or-e (rest (rest tgt)))))
                            (pair
                              (%py-store (first tgt)
                                (list aug (first tgt) (first r)))
                              (rest r))))))))))))))))))))))

; `else:` after an if.  `elif` is `else: if ...`, which is what Python's own
; grammar says it is, so it needs no separate shape.
; A store depends on the target's SHAPE: a name is a set!, a subscript is an
; item assignment. Anything else is not assignable, and saying so here is better
; than emitting a form that fails obscurely at run time.
; `for NAME in ITER: BODY` walks the iterable's elements, binding NAME each
; time. Recursion in tail position, the same shape `while` uses and for the same
; reason: there is no loop construct, and a non-tail call has no depth limit
; behind it.
;
; The item variable is a plain assignment, so it lives in whatever scope the
; hoist put it in -- which is Python's rule too: a for target outlives its loop.
; `for a, b in pairs:` unpacks each item -- the same rule as `a, b = x` applied
; once per iteration, so it reuses %py-unpack and gets its length checking free.
(def %py-for-names
  (fn (self toks acc)
    (let ((t (if (null? toks) () (first toks))))
      (if (%py-name-is? t "in")
        (pair (List reverse acc) (rest toks))
        (if (%py-op-is? t ",")
          (self (rest toks) acc)
          (if (eq? (%py-tag t) (lit tok-name))
            (self (rest toks) (pair (%py-val t) acc))
            (Err raise (lit syntax) "expected in after a for target" ())))))))

(def %py-syms-of
  (fn (self names acc)
    (if (null? names)
      (List reverse acc)
      (self (rest names) (pair (%py-name->sym (first names)) acc)))))

(def %py-for-bind
  (fn (_ syms)
    (if (null? (rest syms))
      (list (lit set!) (first syms) (list (lit first) (lit %py-items)))
      (list (lit let)
        (list (list (lit %py-unpacked)
                (list (lit %py-unpack) (list (lit first) (lit %py-items))
                      (%py-count syms))))
        (pair (lit do) (%py-unpack-sets syms 0 ()))))))

(def %py-for
  (fn (_ toks)
    (if (not (eq? (%py-tag (if (null? toks) () (first toks))) (lit tok-name)))
      (Err raise (lit syntax) "expected a name after for" ())
      (let ((n (%py-for-names toks ())))
        (let ((syms (%py-syms-of (first n) ())))
          (let ((it (%py-or-e (rest n))))
            (let ((b (%py-block (rest it))))
              (pair
                (list
                  (list (lit fn) (list (lit self) (lit %py-items))
                    (list (lit if) (list (lit null?) (lit %py-items))
                      ()
                      (list (lit %seq)
                        (%py-for-bind syms)
                        (list (lit %seq) (first b)
                          (list (lit self) (list (lit rest) (lit %py-items)))))))
                  (list (lit %py-iter-elems) (first it)))
                (rest b)))))))))

; --- try / except / finally --------------------------------------------------
;
; `try` compiles to x's `guard`, which binds the raised value and runs a handler
; -- and `(error e)` inside that handler re-raises it.  So the except clauses
; become an if-chain over %py-exc-match, and the fallthrough is a re-raise:
; an exception no clause names must keep travelling, not be swallowed.
;
; %py-exc is the guard's variable.  It cannot collide with a Python name
; because every Python name is emitted with a `py-` prefix.

; A clause carries its own MATCH EXPRESSION rather than a name, which is what
; lets `except X`, `except (A, B)` and bare `except` share one chain builder.
(def %py-except-tail
  (fn (_ matcher toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "as")
      (let ((v (if (null? (rest toks)) () (first (rest toks)))))
        (if (not (eq? (%py-tag v) (lit tok-name)))
          (Err raise (lit syntax) "expected a name after as" ())
          (let ((b (%py-block (rest (rest toks)))))
            (pair (list matcher (%py-val v) (first b)) (rest b)))))
      (let ((b (%py-block toks)))
        (pair (list matcher () (first b)) (rest b))))))

; The names inside a group, commas ignored -- shared by `except (A, B)` and a
; def's parameter list, which are the same shape once the bracket is a group.
; `*rest` IS THE LAST PARAMETER: its name joins the list like any other (so
; the locals hoist skips it) and the def reads the cell to build a dotted
; parameter list.  `**kw` is refused by name until keyword arguments exist.
(def %py-rest-param (pair () ()))

(def %py-group-names
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (if (%py-op-is? t ",")
          (self (rest toks) acc)
          (if (%py-op-is? t "**")
            (Err raise (lit syntax) "**kwargs parameters are not supported yet" t)
          (if (%py-op-is? t "*")
            (let ((n (if (null? (rest toks)) () (first (rest toks)))))
              (if (not (eq? (%py-tag n) (lit tok-name)))
                (Err raise (lit syntax) "expected a name after *" t)
                (do
                  (%set-first! %py-rest-param (%py-name->sym (%py-val n)))
                  (self (rest (rest toks)) (pair (%py-name->sym (%py-val n)) acc)))))
          (if (eq? (%py-tag t) (lit tok-name))
            (self (rest toks) (pair (%py-name->sym (%py-val t)) acc))
            (Err raise (lit syntax) "expected a name" t)))))))))

; (a b . rest) -- the parameter list with the rest name as the dotted tail.
(def %py-dotted-params
  (fn (self names rest-sym)
    (if (null? names)
      rest-sym
      (if (if (null? (rest names)) (eq? (first names) rest-sym) #f)
        rest-sym
        (pair (first names) (self (rest names) rest-sym))))))

; --- Parameters with defaults and a *rest ------------------------------------
; (names defaults rest-name): names are strings in declaration order, required
; first; defaults is ((sym . EXPR) ...) for the optional tail; rest-name is the
; *name string or nil.
(def %py-params-of
  (fn (_ toks)
    (def go
      (fn (self parts names dflts rest-name)
        (if (null? parts)
          (list (List reverse names) (List reverse dflts) rest-name)
          (let ((p (first parts)))
            (let ((t (first p)))
              (if (%py-op-is? t "**")
                (Err raise (lit syntax) "**kwargs parameters are not supported yet" t)
              (if (%py-op-is? t "*")
                (let ((n (if (null? (rest p)) () (first (rest p)))))
                  (if (not (eq? (%py-tag n) (lit tok-name)))
                    (Err raise (lit syntax) "expected a name after *" t)
                    (self (rest parts) names dflts (%py-val n))))
              (if (not (eq? (%py-tag t) (lit tok-name)))
                (Err raise (lit syntax) "expected a parameter name" t)
              (if (null? (rest p))
                (if (null? dflts)
                  (self (rest parts) (pair (%py-val t) names) dflts rest-name)
                  (Err raise (lit syntax) "non-default argument follows default argument" t))
              (if (not (%py-op-is? (first (rest p)) "="))
                (Err raise (lit syntax) "expected , or = after a parameter name" t)
                (self (rest parts) (pair (%py-val t) names)
                  (pair (pair (%py-name->sym (%py-val t)) (%py-expr-of (rest (rest p)))) dflts)
                  rest-name)))))))))))
    (go (%py-comma-split toks () ()) () () ())))

; A DEFAULT IS EVALUATED ONCE, AT def TIME, into a let around the fn --
; Python's rule, and the one the mutable-default idiom depends on.  The fn
; takes the required parameters fixed and everything after them as a dotted
; %py-more tail, which a prelude unpacks: each optional through %py-opt (a
; missing or %py-dflt slot takes the default), the rest as a tuple of what is
; left.  A keyword call (python/runtime.x %py-kwcall) arranges its arguments
; into that same positional shape, so the callee never sees a keyword.
(def %py-dflt-syms
  (list (lit %py-d0) (lit %py-d1) (lit %py-d2) (lit %py-d3)
        (lit %py-d4) (lit %py-d5) (lit %py-d6) (lit %py-d7)))
(def %py-dflt-sym
  (fn (_ i)
    (if (>= i 8)
      (Err raise (lit syntax) "at most 8 default parameters are supported" ())
      (List ref i %py-dflt-syms))))
(def %py-dflt-lets
  (fn (self dflts i)
    (if (null? dflts) ()
      (pair (list (%py-dflt-sym i) (rest (first dflts)))
        (self (rest dflts) (+ i 1))))))
(def %py-opt-lets
  (fn (self dflts i rest-sym)
    (if (null? dflts)
      (if (null? rest-sym) ()
        (list (list rest-sym
                (list (lit %py-tuple-of-list) (list (lit %py-drop) (lit %py-more) i)))))
      (pair (list (first (first dflts)) (list (lit %py-opt) (lit %py-more) i (%py-dflt-sym i)))
        (self (rest dflts) (+ i 1) rest-sym)))))
(def %py-syms-of
  (fn (self names)
    (if (null? names) () (pair (%py-name->sym (first names)) (self (rest names))))))

(def %py-except-clause
  (fn (_ toks)
    ; positioned just after the `except` keyword
    (if (%py-op-is? (if (null? toks) () (first toks)) ":")
      ; a bare `except:` catches everything
      (let ((b (%py-block toks)))
        (pair (list () () (first b)) (rest b)))
      (if (%py-group? (if (null? toks) () (first toks)) "(")
        ; `except (A, B):` -- a tuple of classes, any of which matches
        (%py-except-tail
          (list (lit %py-exc-match-any) (lit %py-exc)
            (pair (lit list) (%py-group-names (%py-group-of (first toks)) ())))
          (rest toks))
        (let ((n (first toks)))
          (if (not (eq? (%py-tag n) (lit tok-name)))
            (Err raise (lit syntax) "expected an exception name after except" ())
            (%py-except-tail
              (list (lit %py-exc-match) (lit %py-exc)
                (%py-name->sym (%py-val n)))
              (rest toks))))))))

(def %py-except-clauses ())
(set! %py-except-clauses
  (fn (self toks acc)
    (let ((t (%py-skip-nl toks)))
      (if (not (%py-name-is? (if (null? t) () (first t)) "except"))
        (pair (List reverse acc) t)
        (let ((r (%py-except-clause (rest t))))
          (self (rest r) (pair (first r) acc)))))))

(def %py-except-chain ())
(set! %py-except-chain
  (fn (self clauses)
    (if (null? clauses)
      ; NOTHING MATCHED, SO RE-RAISE.  A guard catches everything x can raise;
      ; without this an `except ValueError` would also swallow a KeyError.
      (list (lit error) (lit %py-exc))
      (let ((c (first clauses)))
        (let ((matcher (first c))
              (var (first (rest c)))
              (body (first (rest (rest c)))))
          (let ((handler
                  (if (null? var)
                    body
                    (list (lit %seq)
                      (list (lit set!) (%py-name->sym var) (lit %py-exc))
                      body))))
            (if (null? matcher)
              handler
              (list (lit if) matcher handler (self (rest clauses))))))))))

(def %py-finally
  (fn (_ toks)
    (let ((t (%py-skip-nl toks)))
      (if (%py-name-is? (if (null? t) () (first t)) "finally")
        (let ((b (%py-block (rest t))))
          (pair (first b) (rest b)))
        (pair () t)))))

; try ... except ... else: the else body runs only when the try body
; finished without raising -- a flag the guarded body sets last.
(def %py-try-else
  (fn (_ toks)
    (let ((t (%py-skip-nl toks)))
      (if (%py-name-is? (if (null? t) () (first t)) "else")
        (let ((b (%py-block (rest t))))
          (pair (first b) (rest b)))
        (pair () t)))))

(def %py-try
  (fn (_ toks)
    ; positioned just after the `try` keyword
    (let ((b (%py-block toks)))
      (let ((cs (%py-except-clauses (rest b) ())))
       (let ((e (%py-try-else (rest cs))))
        (let ((f (%py-finally (rest e))))
          (if (if (null? (first cs)) (null? (first f)) #f)
            (Err raise (lit syntax) "try needs an except or a finally" ())
            (let ((guarded
                    (if (null? (first cs))
                      (first b)
                      (if (null? (first e))
                        (list (lit guard)
                          (list (lit %py-exc) (%py-except-chain (first cs)))
                          (first b))
                        (list (lit let) (list (list (lit %py-ok) (list (lit pair) #f ())))
                          (list (lit %seq)
                            (list (lit guard)
                              (list (lit %py-exc) (%py-except-chain (first cs)))
                              (list (lit %seq) (first b)
                                (list (lit %set-first!) (lit %py-ok) #t)))
                            (list (lit if) (list (lit first) (lit %py-ok)) (first e) ())))))))
              (pair
                (if (null? (first f))
                  guarded
                  ; FINALLY RUNS ON BOTH PATHS: once in the body after the
                  ; guarded form, once in a handler that re-raises.  A `return`
                  ; inside try escapes through call/cc and skips it -- Python
                  ; runs it there too, and that is not modelled.
                  (list (lit guard)
                    (list (lit %py-fin)
                      (list (lit %seq) (first f) (list (lit error) (lit %py-fin))))
                    (list (lit %seq) guarded (first f))))
                (rest f))))))))))

(def %py-raise-stmt
  (fn (_ toks)
    ; positioned just after the `raise` keyword
    (if (if (null? toks) #t (eq? (%py-tag (first toks)) (lit tok-newline)))
      ; a bare `raise` re-raises what the enclosing except caught
      (pair (list (lit error) (lit %py-exc)) toks)
      (let ((n (first toks)))
        (if (not (eq? (%py-tag n) (lit tok-name)))
          (Err raise (lit syntax) "expected an exception name after raise" ())
          ; `raise X(...)` CALLS X and raises the result, which is what Python
          ; does -- and is why an undefined name still answers NameError with no
          ; special case: it is bound to a shim that raises when called.
          ; `raise X` with no parens instantiates it too, as Python does.
          (if (%py-group? (if (null? (rest toks)) () (first (rest toks))) "(")
            (let ((g (%py-group-of (first (rest toks)))))
              (pair
                (list (lit %py-raise)
                  (if (null? g)
                    ; `raise X()` -- no argument
                    (list (%py-name->sym (%py-val n)))
                    (list (%py-name->sym (%py-val n)) (%py-expr-of g))))
                (rest (rest toks))))
            (pair
              (list (lit %py-raise) (list (%py-name->sym (%py-val n))))
              (rest toks))))))))

; --- class -------------------------------------------------------------------
;
; A class body is a run of `def`s.  Each one is parsed by %py-def, which emits
; (def SYM FN); the FN is lifted out and paired with the method's NAME STRING,
; because Python looks methods up by name at call time and the symbol is only
; how x would have bound it.
;
; Only defs and `pass` are accepted.  A class attribute -- `count = 0` in the
; body -- is real Python and is NOT supported: it belongs to the class rather
; than the instance, and nothing here has a place to put it yet.  Saying so is
; better than binding it somewhere surprising.

(def %py-class-methods-of ())
(set! %py-class-methods-of
  (fn (self toks acc)
    (let ((t (%py-skip-nl toks)))
      (if (null? t)
        (pair (List reverse acc) t)
        (if #f
          ()
          (if (%py-name-is? (first t) "pass")
            (self (rest t) acc)
            (if (not (%py-name-is? (first t) "def"))
              (Err raise (lit syntax) "a class body takes defs and pass only" ())
              (let ((nm (if (null? (rest t)) () (first (rest t)))))
                (if (not (eq? (%py-tag nm) (lit tok-name)))
                  (Err raise (lit syntax) "expected a method name after def" ())
                  (let ((r (%py-def (rest t))))
                    (self (rest r)
                      (pair
                        (list (lit pair) (%py-val nm)
                          (first (rest (rest (first r)))))
                        acc))))))))))))

(def %py-class-block
  (fn (_ toks)
    (if (not (%py-op-is? (if (null? toks) () (first toks)) ":"))
      (Err raise (lit syntax) "expected : after a class header" ())
      (let ((t (%py-skip-nl (rest toks))))
        (if (not (%py-block? (if (null? t) () (first t))))
          (Err raise (lit syntax) "expected an indented class body" ())
          (pair
            (first (%py-class-methods-of (%py-block-toks (first t)) ()))
            (rest t)))))))

(def %py-class-stmt
  (fn (_ toks)
    ; positioned just after the `class` keyword
    (let ((n (if (null? toks) () (first toks))))
      (if (not (eq? (%py-tag n) (lit tok-name)))
        (Err raise (lit syntax) "expected a class name after class" ())
        (let ((after (rest toks)))
          (if (%py-group? (if (null? after) () (first after)) "(")
            ; single inheritance: `class Dog(Animal):`
            (let ((b (let ((g (%py-group-of (first after))))
                       (if (null? g) () (first g)))))
              (if (not (eq? (%py-tag b) (lit tok-name)))
                (Err raise (lit syntax) "expected a base class name" ())
                (if #f
                  ()
                  (let ((outer (first %py-current-class)))
                    (%set-first! %py-current-class (%py-name->sym (%py-val n)))
                    (let ((r (%py-class-block (rest after))))
                      (%set-first! %py-current-class outer)
                      (pair
                        (list (lit set!) (%py-name->sym (%py-val n))
                          (list (lit %py-mkclass) (%py-val n)
                            (%py-name->sym (%py-val b))
                            (pair (lit list) (first r))))
                        (rest r)))))))
            (let ((outer (first %py-current-class)))
              (%set-first! %py-current-class (%py-name->sym (%py-val n)))
              (let ((r (%py-class-block after)))
                (%set-first! %py-current-class outer)
                (pair
                  (list (lit set!) (%py-name->sym (%py-val n))
                    (list (lit %py-mkclass) (%py-val n) ()
                      (pair (lit list) (first r))))
                  (rest r))))))))))

; --- tuple unpacking ---------------------------------------------------------
;
; `a, b = f()` is the reason tuples earn their keep -- it is how a Python
; function returns two things.  It is decided by a scan rather than by the first
; token: NAME (, NAME)+ = ... and nothing else, so `a[0], b = ...` is NOT
; unpacked here.  Only plain names, which is the case that matters and the one
; that can be hoisted.

(def %py-unpack-scan
  (fn (self toks comma)
    (if (null? toks)
      #f
      (let ((t (first toks)))
        (if (eq? (%py-tag t) (lit tok-newline))
          #f
          (if (%py-op-is? t "=")
            comma
            (if (%py-op-is? t ",")
              (self (rest toks) #t)
              (if (eq? (%py-tag t) (lit tok-name))
                (self (rest toks) comma)
                #f))))))))

(def %py-unpack-stmt? (fn (_ toks) (%py-unpack-scan toks #f)))

(def %py-unpack-names
  (fn (self toks acc)
    (let ((t (first toks)))
      (if (%py-op-is? t "=")
        (pair (List reverse acc) (rest toks))
        (if (%py-op-is? t ",")
          (self (rest toks) acc)
          (self (rest toks) (pair (%py-name->sym (%py-val t)) acc)))))))

(def %py-unpack-sets
  (fn (self syms i acc)
    (if (null? syms)
      (List reverse acc)
      (self (rest syms) (+ i 1)
        (pair
          (list (lit set!) (first syms)
            (list (lit List) (lit ref) i (lit %py-unpacked)))
          acc)))))

(def %py-unpack-stmt
  (fn (_ toks)
    (let ((n (%py-unpack-names toks ())))
      (let ((r (%py-exprlist (rest n))))
        (pair
          ; `let`, not `def`: the temporary binds in the frame, so an unpack
          ; inside a function called during another unpack cannot clobber it.
          (list (lit let)
            (list (list (lit %py-unpacked)
                    (list (lit %py-unpack) (first r) (%py-count (first n)))))
            (pair (lit do) (%py-unpack-sets (first n) 0 ())))
          (rest r))))))

(def %py-store
  (fn (_ target value)
    (if (pair? target)
      (if (eq? (first target) (lit %py-index))
        (list (lit %py-setindex) (first (rest target))
              (first (rest (rest target))) value)
      ; `self.x = 1` is how a Python object gets its fields at all, so an
      ; attribute is an assignable target exactly as a subscript is.
      (if (eq? (first target) (lit %py-getattr))
        (list (lit %py-setattr) (first (rest target))
              (first (rest (rest target))) value)
        (Err raise (lit syntax) "cannot assign to this target" ())))
      (list (lit set!) target value))))

(def %py-else
  (fn (_ toks)
    (let ((t (%py-skip-nl toks)))
      (if (null? t)
        (pair () t)
        (if (%py-name-is? (first t) "else")
          (let ((b (%py-block (rest t))))
            (pair (first b) (rest b)))
          (if (%py-name-is? (first t) "elif")
            (let ((c (%py-or-e (rest t))))
              (let ((b (%py-block (rest c))))
                (let ((e (%py-else (rest b))))
                  (pair
                    (list (lit if) (list (lit %py-truthy) (first c))
                      (first b) (first e))
                    (rest e)))))
            (pair () t)))))))

; `def NAME ( params ) : BLOCK`


(def %py-def
  (fn (_ toks)
    (let ((name (first toks)))
      (if (not (eq? (%py-tag name) (lit tok-name)))
        (Err raise (lit syntax) "expected a function name after def" name)
        (if (not (%py-group? (if (null? (rest toks)) () (first (rest toks))) "("))
          (Err raise (lit syntax) "expected ( after a function name" ())
          (let ((sig (%py-params-of (%py-group-of (first (rest toks))))))
            (def names (first sig))
            (def syms (%py-syms-of names))
            (def dflts (first (rest sig)))
            (def rest-name (first (rest (rest sig))))
            (def rest-sym (if (null? rest-name) () (%py-name->sym rest-name)))
            (def nreq (- (List length names) (List length dflts)))
            (def all-syms (if (null? rest-sym) syms (%py-append syms (list rest-sym))))
            (def after (rest (rest toks)))
            (let ((outer-self (first %py-current-self)))
              (%set-first! %py-current-self (if (null? syms) () (first syms)))
              (let ((b (%py-block after)))
                ; A FUNCTION'S ASSIGNMENTS ARE ITS OWN.  The module-level scan
                ; skips def bodies, so their targets are hoisted HERE instead,
                ; as a `let` (NOT `def`: x's `def` decides global-versus-local
                ; by save-stack depth, and under TCO that stack can be empty,
                ; so a body `def` clobbered the module's name with nil).
                ; Parameters are already bound and are not re-declared.
                (let ((locals (%py-minus
                                (%py-dedupe () (%py-assign-targets (%py-block-contents after) ()) ())
                                all-syms)))
                  (def body0
                    (if (null? locals) (first b) (list (lit let) (%py-lets locals ()) (first b))))
                  ; the rest arrives as an x list; Python hands the function a
                  ; TUPLE.  With defaults the prelude is the %py-opt let.
                  (def body
                    (if (null? dflts)
                      (if (null? rest-sym)
                        body0
                        (list (lit %seq)
                          (list (lit set!) rest-sym (list (lit %py-tuple-of-list) rest-sym))
                          body0))
                      ; without a *rest, more optionals than declared is a
                      ; TypeError -- the dotted tail would swallow them
                      (if (null? rest-sym)
                        (list (lit %seq)
                          (list (lit %py-arity!) (%py-val name) (lit %py-more)
                            nreq (List length dflts))
                          (list (lit let) (%py-opt-lets dflts 0 ()) body0))
                        (list (lit let) (%py-opt-lets dflts 0 rest-sym) body0))))
                  (def params
                    (if (null? dflts)
                      (if (null? rest-sym) syms (%py-dotted-params syms rest-sym))
                      (%py-dotted-params (%py-take nreq syms) (lit %py-more))))
                  ; The body runs inside call/cc so `return` has somewhere to
                  ; jump to, and ends in () so a function that falls off the
                  ; end answers None.  %seq TAKES TWO FORMS -- a third arm is
                  ; silently dropped.
                  (def fn-form
                    (list (lit fn) (pair (lit _) params)
                      (list (lit %py-callcc)
                        (list (lit fn) (list (lit _) (lit %py-return))
                          (list (lit %seq) body ())))))
                  ; %py-sig! records the parameter names for keyword calls and
                  ; answers the closure, so this is still the def's value form
                  ; -- a class body reads it as the method.
                  (def sig-form
                    (list (lit %py-sig!) fn-form (%py-val name)
                      (pair (lit list) names) nreq (not (null? rest-sym))))
                  (%set-first! %py-current-self outer-self)
                  (pair
                    (list (lit def) (%py-name->sym (%py-val name))
                      (if (null? dflts)
                        sig-form
                        (list (lit let) (%py-dflt-lets dflts 0) sig-form)))
                    (rest b)))))))))))

(def %py-lets
  (fn (self syms acc)
    (if (null? syms)
      (List reverse acc)
      (self (rest syms) (pair (list (first syms) ()) acc)))))

(def %py-minus
  (fn (self syms drop)
    (if (null? syms)
      ()
      (if (%py-seen? (first syms) drop)
        (self (rest syms) drop)
        (pair (first syms) (self (rest syms) drop))))))

; ASSIGNMENT IS set!, AND EVERY TARGET IS HOISTED TO A def FIRST.
;
; x's `def` decides global-versus-local by save-stack depth, so a `def` inside
; the function a while-loop compiles to would bind a fresh LOCAL every
; iteration. `i = i + 1` in a loop body would then never advance the outer `i`
; and the loop would never terminate -- an infinite loop with no depth limit
; behind it (x-lang#56), which on this platform means an OOM rather than a
; stack overflow.
;
; So: scan the token stream for assignment targets, emit `(def name ())` for
; each before the body, and compile every assignment to `set!`. That also
; matches Python's module semantics more closely than per-statement `def` does
; -- a name assigned anywhere in a module scope is that scope's name throughout.
;
; Function-local scoping is NOT modelled yet: a `def` body's assignments hoist
; to the same module scope. That is wrong for Python and is the next thing this
; wants, but it is wrong in a way that produces a visible name clash rather
; than a loop that never ends.
; Skip from a `def` to the DEDENT that closes it: names assigned inside a
; function body are that function's, not the module's.  Depth is tracked because
; a def body can contain further indented blocks, and only the dedent that
; returns to the def's own level ends it.
; A def's body is ONE token now, so skipping past it is finding that token
; rather than counting INDENT/DEDENT pairs.
(def %py-skip-def
  (fn (self toks depth)
    (if (null? toks)
      toks
      (if (%py-block? (first toks))
        (rest toks)
        (self (rest toks) depth)))))

; Names the grammar owns.  They reach the tokenizer as tok-name -- `if` is a
; name there and a keyword to the parser -- so the undefined-name scan has to
; know them, or it would emit a NameError shim for `while`.
(def %py-keywords
  (list "if" "elif" "else" "while" "def" "return" "pass" "and" "or" "not"
        "in" "is" "for" "break" "continue" "class" "import" "from" "as"
        "try" "except" "finally" "raise" "with" "lambda" "global" "nonlocal"
        "assert" "del" "yield" "async" "await"))

(def %py-str-seen?
  (fn (self x lst)
    (if (null? lst) #f
      (if (Str8 =? x (first lst)) #t (self x (rest lst))))))

(def %py-builtin-name?
  (fn (self s rows)
    (if (null? rows) #f
      (if (Str8 =? s (first (first rows))) #t (self s (rest rows))))))

; Every name the program MENTIONS, as text.
; DESCENDS INTO GROUPS.  A bracketed run is one token now, so a scan that only
; walked the top level would never see `x` in `f(x)` -- and the undefined-name
; check would shim a name the program plainly uses.
(def %py-mentioned
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (if (eq? (%py-tag t) (lit tok-name))
          (self (rest toks) (pair (%py-val t) acc))
          (if (eq? (%py-tag t) (lit tok-group))
            (self (rest toks) (%py-append (List reverse (self (%py-group-of t) ())) acc))
          (if (%py-block? t)
            (self (rest toks) (%py-append (List reverse (self (%py-block-toks t) ())) acc))
            (self (rest toks) acc))))))))

; Every name the program BINDS: assignment targets, def names, parameters.
(def %py-bound-names
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (if (%py-for-target? toks)
          (let ((u (%py-for-names (rest toks) ())))
            (self (rest u) (%py-append (List reverse (first u)) acc)))
        (if (%py-name-is? t "as")
          ; `except ValueError as e` binds e, and the hoisting scan is what
          ; turns that into a def -- without this the set! below has nothing
          ; to store into.
          (let ((n (if (null? (rest toks)) () (first (rest toks)))))
            (self (rest (rest toks))
              (if (eq? (%py-tag n) (lit tok-name)) (pair (%py-val n) acc) acc)))
        (if (%py-name-is? t "def")
          ; the def name, then its parameters up to the closing paren
          (let ((n (if (null? (rest toks)) () (first (rest toks)))))
            (self (rest (rest toks))
              (if (eq? (%py-tag n) (lit tok-name)) (pair (%py-val n) acc) acc)))
          (if (if (eq? (%py-tag t) (lit tok-name))
                (%py-assign-op? (if (null? (rest toks)) () (first (rest toks))))
                #f)
            (self (rest toks) (pair (%py-val t) acc))
            (self (rest toks) acc)))))))))

(def %py-assign-targets
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        ; DESCEND INTO BLOCKS.  `if x:` then `y = 1` binds y at MODULE level in
        ; Python, and the body is a nested token now -- a scan that stayed at
        ; the top level would hoist nothing from any compound statement.  Def
        ; bodies are still skipped below: those targets are the function's own.
        (if (%py-block? t)
          (self (rest toks) (%py-append (List reverse (self (%py-block-toks t) ())) acc))
        (if (%py-for-target? toks)
          (let ((u (%py-for-names (rest toks) ())))
            (self (rest u) (%py-append (List reverse (%py-syms-of (first u) ())) acc)))
        (if (%py-block? t)
          (self (rest toks) (%py-append (List reverse (self (%py-block-toks t) ())) acc))
        (if (%py-unpack-stmt? toks)
          ; every name on the left of `a, b = ...` is bound by it
          (let ((u (%py-unpack-names toks ())))
            (self (rest u) (%py-append (List reverse (first u)) acc)))
        (if (%py-name-is? t "class")
          ; `class Foo:` binds Foo, and this scan is what hoists it.
          (let ((n (if (null? (rest toks)) () (first (rest toks)))))
            (self (rest (rest toks))
              (if (eq? (%py-tag n) (lit tok-name))
                (pair (%py-name->sym (%py-val n)) acc) acc)))
        (if (%py-as-target? toks)
          ; `except ValueError as e` binds e as surely as an assignment does,
          ; and this is the scan that emits the hoisted defs -- the other one
          ; only keeps the undefined-name check from shimming it.
          (self (rest (rest toks))
            (pair (%py-name->sym (%py-val (first (rest toks)))) acc))
        (if (%py-name-is? t "def")
          (self (%py-skip-def (rest toks) 0) acc)
          (if (if (eq? (%py-tag t) (lit tok-name))
                (%py-assign-op? (if (null? (rest toks)) () (first (rest toks))))
                #f)
            (self (rest toks) (pair (%py-name->sym (%py-val t)) acc))
            (self (rest toks) acc)))))))))))))

; The name after `as` in an except clause.
(def %py-as-target?
  (fn (_ toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "as")
      (if (eq? (%py-tag (if (null? (rest toks)) () (first (rest toks)))) (lit tok-name))
        #t #f)
      #f)))

; A `for` target binds its name as surely as an assignment does.
(def %py-for-target?
  (fn (_ toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "for")
      (if (eq? (%py-tag (if (null? (rest toks)) () (first (rest toks)))) (lit tok-name))
        #t #f)
      #f)))

; `=` or any augmented form: all of them bind the name.
(def %py-assign-op?
  (fn (_ t)
    (if (%py-op-is? t "=") #t
      (if (null? (%py-op-sym t %py-aug-ops)) #f #t))))

; Hand-rolled rather than reaching for List: `member?` is not a static there,
; and a wrong method name fails at RUN time in a form this file generates,
; which is a long way from where it would be read.
; %py-count, NOT %py-len: python/runtime.x defines %py-len as Python's `len`,
; and two definitions of one name in the same module namespace means the last
; loaded wins.  It cost `len([])` returning 1 and `len('hello')` returning 119 --
; wrong numbers, no error.
(def %py-count (fn (self l) (if (null? l) 0 (+ 1 (self (rest l))))))
(def %py-take
  (fn (self n l)
    (if (= n 0) () (if (null? l) () (pair (first l) (self (- n 1) (rest l)))))))

(def %py-seen?
  (fn (self x lst)
    (if (null? lst) #f
      (if (eq? x (first lst)) #t (self x (rest lst))))))

(def %py-dedupe
  (fn (self seen syms acc)
    (if (null? syms)
      (List reverse acc)
      (if (%py-seen? (first syms) seen)
        (self seen (rest syms) acc)
        (self (pair (first syms) seen) (rest syms) (pair (first syms) acc))))))

; A name mentioned but never bound gets a shim that raises PYTHON's error.
;
; Without this the program dies on `Unbound SYMBOL 'py-int` -- and `py-int` is
; not in anyone's source. The prefix exists so Python's names cannot resolve to
; x's, which it must; it has no business appearing in a diagnostic. The shim
; puts the programmer's own spelling back.
(def %py-undefined
  (fn (self names bound acc)
    (if (null? names)
      (List reverse acc)
      (let ((n (first names)))
        (if (if (%py-str-seen? n bound) #t
              (if (%py-str-seen? n %py-keywords) #t
                (%py-builtin-name? n %py-builtins)))
          (self (rest names) bound acc)
          (if (%py-str-seen? n (%py-names-of acc))
            (self (rest names) bound acc)
            (self (rest names) bound (pair n acc))))))))

(def %py-names-of
  (fn (self acc) (if (null? acc) () (pair (first acc) (self (rest acc))))))

; CONDITIONAL, and the REPL is why.  Each interactive line is its own parse,
; so an unconditional shim for a name this LINE does not bind would clobber a
; binding an EARLIER line made -- `x = 5` then `x` re-shimmed py-x and the
; session forgot everything.  The guard evaluates the name: bound answers
; itself and the def never runs; unbound raises into the guard, which defs the
; shim.  Batch semantics are unchanged -- a truly unbound name still shims.
; The handler defines through the base/def-global door, because a plain def
; inside a guard HANDLER binds in the handler's frame -- measured in the REPL:
; the hoist "succeeded" and the very next form found the name unbound.
(def %py-shims
  (fn (self names acc)
    (if (null? names)
      (List reverse acc)
      (self (rest names)
        (pair
          (list (lit guard)
            (list (lit %py-e)
              (list (lit %py-defg) (list (lit lit) (%py-name->sym (first names)))
                (list (lit fn) (list (lit _))
                  (list (lit Err) (lit raise) (list (lit lit) (lit name))
                    (Str8 append (Str8 append "name '" (first names))
                      "' is not defined")
                    ()))))
            (%py-name->sym (first names)))
          acc)))))

(def python-parse
  (fn (_ src)
    ; PER-RUN STATE, RESET HERE.  The lexical cells are saved and restored around
    ; each body, but a parse that RAISES -- a bad class body, a syntax error --
    ; skips its restore and leaves the cell set for whatever parses next in the
    ; same process.  Measured: a spec asserting `super() outside a class`
    ; reported `outside a method`, because an earlier case in the file had died
    ; inside a class body and left the class behind.
    (%set-first! %py-current-class ())
    (%set-first! %py-current-self ())
    (def %toks (python-lex src))
    (def %targets (%py-dedupe () (%py-assign-targets %toks ()) ()))
    (def %body (first (%py-stmts %toks ())))
    (def %undef
      (%py-undefined (%py-mentioned %toks ())
                     (%py-append (%py-bound-names %toks ()) (%py-param-names %toks ()))
                     ()))
    (%py-append (%py-shims %undef ())
      (%py-append (%py-decls %targets ()) %body))))

; Parameter names: any name between a def's parens.
(def %py-param-names
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (if (%py-name-is? (first toks) "def")
        (let ((r (%py-param-span (rest (rest toks)) ())))
          (self (first r) (%py-append (rest r) acc)))
        (self (rest toks) acc)))))

(def %py-param-span
  (fn (self toks acc)
    (if (null? toks)
      (pair toks acc)
      (if (eq? (%py-tag (first toks)) (lit tok-group))
        (pair (rest toks) (%py-append (%py-raw-names (%py-group-of (first toks)) ()) acc))
        (self (rest toks) acc)))))

(def %py-raw-names
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (if (eq? (%py-tag (first toks)) (lit tok-name))
        (self (rest toks) (pair (%py-val (first toks)) acc))
        (self (rest toks) acc)))))

; Conditional for the same REPL reason as %py-shims: an unconditional
; (def py-x ()) at the head of every line's program would reset x each line,
; so `x = 5` then `x = x + 1` computed from nil.
(def %py-decls
  (fn (self syms acc)
    (if (null? syms)
      (List reverse acc)
      (self (rest syms)
        (pair
          (list (lit guard)
            (list (lit %py-e) (list (lit %py-defg) (list (lit lit) (first syms)) ()))
          (first syms))
          acc)))))

(def %py-append
  (fn (self a b)
    (if (null? a) b (pair (first a) (self (rest a) b)))))
