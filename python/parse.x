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
; Process state, like the tokenizer base: its own chain, so the image writer
; carries it as nil and the recache hook makes it again after a load.
(set! %image-transients (pair (lit %py-sexp-base) %image-transients))
(set! %image-recache-hooks
  (pair (fn (_) (set! %py-sexp-base (Base make))) %image-recache-hooks))

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
          (match
            ((if (= c 120) #t (= c 88)) 16)
            ((if (= c 111) #t (= c 79)) 8)
            ((if (= c 98) #t (= c 66)) 2)
            (#t ())))))))

(def %py-num
  (fn (self text)
    (let ((t (%py-num-strip text)))
      ; a signed based literal (-0x10 alone) is the sign applied to the rest
      (match
        ((if (if (= (%py-char->int (Str8 ref 0 t)) 45) #t (= (%py-char->int (Str8 ref 0 t)) 43))
            (not (null? (%py-num-base-of (Str8 sub 1 (- (Str8 length t) 1) t))))
            #f)
          (let ((v (self (Str8 sub 1 (- (Str8 length t) 1) t))))
            (if (= (%py-char->int (Str8 ref 0 t)) 45) (%py-neg v) v)))
        ((not (null? (%py-num-base-of t)))
          (%py-int-of-based (Str8 sub 2 (- (Str8 length t) 2) t) (%py-num-base-of t)))
        ((%py-num-imag? t)
          (Complex make 0.0 (Float from (Str8 sub 0 (- (Str8 length t) 1) t))))
        ((%py-num-float-text? t) (Float from t))
        ; THE HAND PARSER, NOT THE CHILD BASE: %py-sexp-base is a (Base make)
        ; child and bigint is a library type it does not carry, so a literal
        ; past 2^63 WRAPPED silently.  %py-int-of-str promotes through the
        ; tower.
        (#t (%py-int-of-str t))))))

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
; EVERY op= GETS ITS OWN DUNDER, not just +=.  Each of these tries __iop__
; on an object first and falls back to the binary op, which is Python's rule
; (runtime.x, %py-inplace); for everything that is not an object they ARE the
; binary op.
(def %py-aug-ops
  (list (list "+=" (lit %py-iadd)) (list "-=" (lit %py-isub))
        (list "*=" (lit %py-imul)) (list "/=" (lit %py-idiv))
        (list "%=" (lit %py-imod))
        (list "|=" (lit %py-ibitor)) (list "&=" (lit %py-ibitand))
        (list "^=" (lit %py-ibitxor))
        ; the three-character forms; the tokenizer reads a third `=` after
        ; the doubled operators, which is what these need (tokens.x,
        ; %py-op-triple?)
        (list "//=" (lit %py-ifloordiv)) (list "**=" (lit %py-ipow))
        (list "<<=" (lit %py-ilshift))   (list ">>=" (lit %py-irshift))))

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
      (match
        ((%py-name-is? (if (null? more) () (first more)) "in")
          (let ((rhs (%py-left (rest more) %py-cmp-ops %py-bor)))
            (pair (list (lit %py-in) (first r) (first rhs)) (rest rhs))))
        ((if (%py-name-is? (if (null? more) () (first more)) "not")
              (%py-name-is? (if (null? (rest more)) () (first (rest more))) "in")
              #f)
          (let ((rhs (%py-left (rest (rest more)) %py-cmp-ops %py-bor)))
            (pair (list (lit not) (list (lit %py-in) (first r) (first rhs)))
              (rest rhs))))
        ; `is` and `is not`: identity (python/runtime.x %py-is)
        ((%py-name-is? (if (null? more) () (first more)) "is")
          (if (%py-name-is? (if (null? (rest more)) () (first (rest more))) "not")
            (let ((rhs (%py-left (rest (rest more)) %py-cmp-ops %py-bor)))
              (pair (list (lit not) (list (lit %py-is) (first r) (first rhs))) (rest rhs)))
            (let ((rhs (%py-left (rest more) %py-cmp-ops %py-bor)))
              (pair (list (lit %py-is) (first r) (first rhs)) (rest rhs)))))
        (#t r)))))
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
    (match
      ((%py-op-is? t "-")
        (let ((r (%py-unary (rest toks))))
          (pair (list (lit %py-neg) (first r)) (rest r))))
      ((%py-op-is? t "+")
        (let ((r (%py-unary (rest toks))))
          (pair (list (lit %py-pos) (first r)) (rest r))))
      ((%py-op-is? t "~")
        (let ((r (%py-unary (rest toks))))
          (pair (list (lit %py-invert) (first r)) (rest r))))
      (#t (%py-power toks)))))

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
; (joined-text . rest): the literal plus every literal of the same kind that
; follows it directly.
(def %py-adjacent
  (fn (self tag acc toks)
    (if (if (null? toks) #f (eq? (%py-tag (first toks)) tag))
      (self tag (Str8 append acc (%py-val (first toks))) (rest toks))
      (pair acc toks))))

(set! %py-postfix
  (fn (_ toks)
    (def %a (%py-atom toks))
    (def %go
      (fn (self acc more)
        (match
          ((%py-group? (if (null? more) () (first more)) "(")
            (self (%py-call-form acc (%py-group-of (first more)))
                  (rest more)))
          ; Attribute access binds like a call, and yields a VALUE -- the
          ; bound method -- so `f = x.append` works and a following `(` simply
          ; applies it.
          ((%py-op-is? (if (null? more) () (first more)) ".")
            (let ((n (if (null? (rest more)) () (first (rest more)))))
              (if (not (eq? (%py-tag n) (lit tok-name)))
                (Err raise (lit syntax) "expected a name after ." ())
                (self (list (lit %py-getattr) acc (%py-val n))
                      (rest (rest more))))))
          ; Subscript binds like a call: left-associative, same level.
          ((%py-group? (if (null? more) () (first more)) "[")
            (self
              (if (%py-slice-group? (%py-group-of (first more)))
                (%py-slice-form acc (%py-group-of (first more)))
                (list (lit %py-index) acc
                  (%py-expr-of (%py-group-of (first more)))))
              (rest more)))
          (#t (pair acc more)))))
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

; A LAMBDA'S PARAMETER COMMAS ARE NOT SEPARATORS: `(lambda a, b: a)` is one
; lambda, not a tuple.  Both scanners copy a lambda's tokens through its
; colon; its body is a %py-test and stops at a comma on its own.
(def %py-lambda-head
  (fn (self toks acc)
    (if (null? toks) (pair (List reverse acc) ())
      (if (%py-op-is? (first toks) ":")
        (pair (List reverse (pair (first toks) acc)) (rest toks))
        (self (rest toks) (pair (first toks) acc))))))
(def %py-comma-split
  (fn (self toks cur acc)
    (match
      ((null? toks)
        (List reverse (if (null? cur) acc (pair (List reverse cur) acc))))
      ; AN EMPTY PART IS ONLY EVER THE LAST ONE.  `[1,]` is a trailing comma
      ; and ends at the arm above; a comma reached with nothing gathered is
      ; `[1,,]` or `[,1]`, which Python refuses in every one of the four
      ; places this splits -- a list, a call, a dict, a parameter list.  It
      ; used to be DROPPED, in silence: eval("[1,,]") answered [1].
      ((%py-op-is? (first toks) ",")
        (if (null? cur)
          (Err raise (lit syntax) "expected an expression before ','" (first toks))
          (self (rest toks) () (pair (List reverse cur) acc))))
      ((%py-name-is? (first toks) "lambda")
        (let ((h (%py-lambda-head toks ())))
          (self (rest h) (%py-append (List reverse (first h)) cur) acc)))
      (#t (self (rest toks) (pair (first toks) cur) acc)))))

(def %py-has-comma?
  (fn (self toks)
    (match
      ((null? toks) #f)
      ((%py-op-is? (first toks) ",") #t)
      ((%py-name-is? (first toks) "lambda")
        (self (rest (%py-lambda-head toks ()))))
      (#t (self (rest toks))))))

; A CONDITIONAL EXPRESSION sits above `or`: `a if c else b`, right-
; associative, the value chosen by %py-truthy like every condition.  This is
; the entry for a full expression; a comprehension's iterable and a for
; loop's stay on %py-or-e, because there `if` opens a clause -- Python's own
; grammar draws the line in the same place.
; `yield`, `yield v`, `yield a, b`, `yield from it`: an expression whose
; value is what send() passes back in.  %py-gen is the enclosing generator
; body's own parameter (see %py-def).
(def %py-yield-expr
  (fn (_ toks)
    (let ((after (rest toks)))
      (if (%py-name-is? (if (null? after) () (first after)) "from")
        (let ((r (%py-test (rest after))))
          (pair (list (lit %py-yield-from) (lit %py-gen) (first r)) (rest r)))
        (if (match
              ((null? after) #t)
              ((eq? (%py-tag (first after)) (lit tok-newline)) #t)
              ((%py-op-is? (first after) ")") #t)
              ((%py-op-is? (first after) "=") #t)
              (#t (%py-op-is? (first after) ",")))
          (pair (list (lit %py-yield) (lit %py-gen) ()) after)
          (let ((r (%py-exprlist after)))
            (pair (list (lit %py-yield) (lit %py-gen) (first r)) (rest r))))))))

; lambda params: expr -- the def emission's parameter machinery (defaults
; let-bound once, optionals on a dotted tail, a registered signature) with
; an expression body.  The parameters end at the first top-level colon.
(def %py-lambda-expr
  (fn (_ toks)
    (def split
      (fn (self ts acc)
        (if (null? ts) (Err raise (lit syntax) "expected : after lambda parameters" ())
          (if (%py-op-is? (first ts) ":") (pair (List reverse acc) (rest ts))
            (self (rest ts) (pair (first ts) acc))))))
    (let ((sp (split (rest toks) ())))
      (let ((sig (%py-params-of (first sp))) (b (%py-test (rest sp))))
        (def names (first sig))
        (def syms (%py-strs->syms names))
        (def dflts (first (rest sig)))
        (def rest-name (first (rest (rest sig))))
        (def rest-sym (if (null? rest-name) () (%py-name->sym rest-name)))
        (def nreq (- (List length names) (List length dflts)))
        (def body
          (if (null? dflts)
            (if (null? rest-sym) (first b)
              (list (lit let) (list (list rest-sym (list (lit %py-tuple-of-list) rest-sym))) (first b)))
            (if (null? rest-sym)
              (list (lit %seq)
                (list (lit %py-arity!) "<lambda>" (lit %py-more) nreq (List length dflts))
                (list (lit let) (%py-opt-lets dflts 0 ()) (first b)))
              (list (lit let) (%py-opt-lets dflts 0 rest-sym) (first b)))))
        (def params
          (if (null? dflts)
            (if (null? rest-sym) syms (%py-dotted-params syms rest-sym))
            (%py-dotted-params (%py-take nreq syms) (lit %py-more))))
        (def sig-form
          (list (lit %py-sig!) (list (lit fn) (pair (lit _) params) body)
            "<lambda>" (pair (lit list) names) nreq (not (null? rest-sym))))
        (pair (if (null? dflts) sig-form (list (lit let) (%py-dflt-lets dflts 0) sig-form))
          (rest b))))))

(def %py-test
  (fn (self toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "lambda")
      (%py-lambda-expr toks)
    (if (%py-name-is? (if (null? toks) () (first toks)) "yield")
      (%py-yield-expr toks)
    (let ((r (%py-or-e toks)))
      (if (%py-name-is? (if (null? (rest r)) () (first (rest r))) "if")
        (let ((c (%py-or-e (rest (rest r)))))
          (if (not (%py-name-is? (if (null? (rest c)) () (first (rest c))) "else"))
            (Err raise (lit syntax) "expected else after a conditional expression" ())
            (let ((e (self (rest (rest c)))))
              (pair (list (lit if) (list (lit %py-truthy) (first c)) (first r) (first e))
                (rest e)))))
        r))))))

; One complete expression from a complete token list -- anything left over is a
; syntax error HERE, where the bracket that bounded it is known.
; A GENERATOR EXPRESSION is a comprehension whose action is a yield, wrapped
; as a generator body: `(x for x in y)` and the bare `f(x for x in y)`.
(def %py-top-for?
  (fn (self toks)
    (if (null? toks) #f (if (%py-name-is? (first toks) "for") #t (self (rest toks))))))
(def %py-genexp
  (fn (_ elems)
    (let ((r (%py-test elems)))
      (if (not (%py-name-is? (if (null? (rest r)) () (first (rest r))) "for"))
        (Err raise (lit syntax) "expected for in generator expression" ())
        (let ((cls (%py-comp-clauses (rest r) ())))
          (list (lit %py-gen-new)
            (list (lit fn) (list (lit _) (lit %py-gen))
              (list (lit %py-escape)
                (list (lit fn) (list (lit _) (lit %py-return))
                  (list (lit %seq)
                    (%py-comp-fold cls (list (lit %py-yield) (lit %py-gen) (first r)))
                    ()))))
            "<genexpr>"))))))

(def %py-expr-of
  (fn (_ toks)
    (if (null? toks)
      (Err raise (lit syntax) "expected an expression" ())
    (if (%py-top-for? toks)
      (%py-genexp toks)
      (let ((r (%py-test toks)))
        (if (null? (rest r))
          (first r)
          (Err raise (lit syntax) "unexpected token after an expression" ())))))))

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
    (match
      ((null? part) #f)
      ((null? (rest part)) #f)
      ((eq? (%py-tag (first part)) (lit tok-name))
        (%py-op-is? (first (rest part)) "="))
      (#t #f))))

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
; A `**d` ARGUMENT IS A KEYWORD SPREAD: the dict's entries become keyword
; arguments, in the order the dict holds them, alongside any written by name.
(def %py-kwspread-part?
  (fn (_ part) (if (null? part) #f (%py-op-is? (first part) "**"))))

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
    (def spreads
      (fn (self ps)
        (if (null? ps) ()
          (if (%py-kwspread-part? (first ps))
            (pair (%py-expr-of (rest (first ps))) (self (rest ps)))
            (self (rest ps))))))
    (def poss
      (fn (self ps)
        (match
          ((null? ps) ())
          ((%py-kw-part? (first ps)) (self (rest ps)))
          ((%py-kwspread-part? (first ps)) (self (rest ps)))
          (#t (pair (first ps) (self (rest ps)))))))
    (def kw-forms (kws parts))
    (def kw-spreads (spreads parts))
    ; the keyword list, with every spread dict merged onto the written ones
    (def kw-all
      (if (null? kw-spreads)
        (pair (lit list) kw-forms)
        (list (lit %py-kw-spread) (pair (lit list) kw-forms)
          (pair (lit list) kw-spreads))))
    (if (if (null? kw-forms) (null? kw-spreads) #f)
      (let ((a (%py-args-form parts)))
        (if (eq? (first a) (lit list)) (pair f (rest a)) (list (lit apply) f a)))
      (let ((pos (%py-args-form (poss parts))))
        (if (if (pair? f) (eq? (first f) (lit %py-getattr)) #f)
          (list (lit %py-kwcall-attr) (first (rest f)) (first (rest (rest f)))
            pos kw-all)
          (list (lit %py-kwcall) f pos kw-all))))))

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

(def %py-top-colon?
  (fn (self toks)
    (match
      ((null? toks) #f)
      ((%py-name-is? (first toks) "lambda")
        (self (rest (%py-lambda-head toks ()))))
      ((%py-op-is? (first toks) ":") #t)
      (#t (self (rest toks))))))

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
    (match
      ((null? toks) (List reverse acc))
      ((%py-name-is? (first toks) "for")
        (let ((n (%py-for-names (rest toks) ())))
          (let ((it (%py-or-e (rest n))))
            (self (rest it)
              (pair (list (lit for) (%py-syms-of (first n) ()) (first it)) acc)))))
      ((%py-name-is? (first toks) "if")
        (let ((c (%py-or-e (rest toks))))
          (self (rest c) (pair (list (lit if) (first c)) acc))))
      (#t
        (Err raise (lit syntax) "unexpected token in comprehension" (first toks))))))

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
    (let ((r (%py-test elems)))
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

(def %py-setcomp
  (fn (_ elems)
    (let ((r (%py-test elems)))
      (if (not (%py-name-is? (if (null? (rest r)) () (first (rest r))) "for"))
        (Err raise (lit syntax) "expected for in comprehension" ())
        (let ((cls (%py-comp-clauses (rest r) ())))
          (list (lit let)
            (list (list (lit %py-acc) (list (lit pair) () ())))
            (list (lit %seq)
              (%py-comp-fold cls
                (list (lit %set-first!) (lit %py-acc)
                  (list (lit %py-set-put) (list (lit first) (lit %py-acc)) (first r))))
              (list (lit %py-set-new) #f (list (lit first) (lit %py-acc))))))))))

(def %py-dictcomp
  (fn (_ elems)
    (let ((k (%py-test elems)))
      (if (not (%py-op-is? (if (null? (rest k)) () (first (rest k))) ":"))
        (Err raise (lit syntax) "expected : in dict comprehension" ())
        (let ((v (%py-test (rest (rest k)))))
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
      (let ((r (%py-test toks)))
        (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ",")
          (self (rest (rest r)) (pair (first r) acc))
          (pair (List reverse (pair (first r) acc)) (rest r)))))))

(def %py-exprlist
  (fn (_ toks)
    (let ((r (%py-test toks)))
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
        (match
          ((eq? (%py-tag t) (lit tok-number))
            (pair (%py-num (%py-val t)) (rest toks)))
          ((eq? (%py-tag t) (lit tok-string))
            (%py-adjacent (lit tok-string) (%py-val t) (rest toks)))
          ((eq? (%py-tag t) (lit tok-bytes))
            (let ((r (%py-adjacent (lit tok-bytes) (%py-val t) (rest toks))))
              (pair (list (lit %py-mkbytes) (first r)) (rest r))))
          ((eq? (%py-tag t) (lit tok-fstring))
            (pair (%py-fstring-form (%py-val t)) (rest toks)))
          ((%py-super-call? toks)
            (match
              ((not (null? (%py-group-of (first (rest toks)))))
                (pair (list (lit %py-super-args)) (rest (rest toks))))
              ((null? (first %py-current-class))
                (Err raise (lit syntax) "super() outside a class" ()))
              ((null? (first %py-current-self))
                (Err raise (lit syntax) "super() outside a method" ()))
              (#t
                (pair
                  (list (lit %py-super)
                    (first %py-current-class) (first %py-current-self))
                  (rest (rest toks))))))
          ((eq? (%py-tag t) (lit tok-name))
            (pair (%py-name->sym (%py-val t)) (rest toks)))
          ((%py-group? t "{")
            (let ((g (%py-group-of t)))
              (if (%py-comp? g)
                (pair (if (%py-top-colon? g) (%py-dictcomp g) (%py-setcomp g)) (rest toks))
                (if (if (null? g) #t (%py-top-colon? g))
                  (pair
                    (pair (lit %py-mkdict) (%py-entries-of (%py-comma-split g () ()) ()))
                    (rest toks))
                  (pair (pair (lit %py-mkset) (%py-group-exprs g)) (rest toks))))))
          ((%py-group? t "[")
            (if (%py-comp? (%py-group-of t))
              (pair (%py-listcomp (%py-group-of t)) (rest toks))
              (pair
                (pair (lit %py-mklist) (%py-group-exprs (%py-group-of t)))
                (rest toks))))
          ((%py-group? t "(")
            (let ((elems (%py-group-of t)))
              (if (null? elems)
                (pair (list (lit %py-mktuple)) (rest toks))
                (if (%py-has-comma? elems)
                  (pair
                    (pair (lit %py-mktuple) (%py-group-exprs elems))
                    (rest toks))
                  (pair (%py-expr-of elems) (rest toks))))))
          ; `...` -- three `.` operators where a primary belongs.  The
          ; tokenizer pairs nothing on `.` and a pair rule there would have
          ; to be told apart from `1.` and `.5` first; here a `.` cannot
          ; mean attribute access, so the three read unambiguously.
          ((%py-ellipsis? toks) (pair (lit %py-Ellipsis) (rest (rest (rest toks)))))
          (#t (Err raise (lit syntax) "unexpected token in expression" t)))))))

(def %py-ellipsis?
  (fn (_ toks)
    (if (%py-op-is? (if (null? toks) () (first toks)) ".")
      (let ((r (rest toks)))
        (if (%py-op-is? (if (null? r) () (first r)) ".")
          (%py-op-is? (if (null? (rest r)) () (first (rest r))) ".")
          #f))
      #f)))

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
        (match
          ((if (= c 40) #t (if (= c 91) #t (= c 123)))
            (self s (+ i 1) (+ depth 1)))
          ((if (= c 41) #t (if (= c 93) #t (= c 125)))
            (self s (+ i 1) (- depth 1)))
          ((if (= depth 0)
                  (if (= c 58) #t
                    ; `!` opens a conversion only when `=` does not follow:
                    ; {a!=b} is a comparison
                    (if (= c 33)
                      (if (< (+ i 1) (Str8 length s)) (not (= (%py-fs-code s (+ i 1)) 61)) #t)
                      #f))
                  #f)
            i)
          (#t (self s (+ i 1) depth)))))))

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
      (match
        ((null? i) ())
        ((not (= (%py-fs-code s i) 61)) ())
        ((= i 0) ())
        (#t
          (let ((p (%py-fs-code s (- i 1))))
            (if (match
                  ((= p 61) #t)
                  ((= p 33) #t)
                  ((= p 60) #t)
                  (#t (= p 62))) () i)))))))

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
        (list "range" (lit %py-cls-range))
        ; str and list are now the CLASS OBJECTS -- calling one still converts,
        ; through the %ctor entry, and `type(x) == str` is an identity compare.
        (list "str"     (lit %py-cls-str))
        (list "repr"    (lit %py-repr-of))
        (list "list"    (lit %py-cls-list))
        (list "hasattr" (lit %py-hasattr))
        (list "object"  (lit %py-cls-object))
        ; the three that make a decorated def mean something
        (list "bytes"        (lit %py-cls-bytes))
        (list "staticmethod" (lit %py-staticmethod))
        (list "classmethod"  (lit %py-classmethod))
        (list "property"     (lit %py-property))
        (list "type"    (lit %py-cls-type))
        (list "int"     (lit %py-cls-int))
        (list "float"   (lit %py-cls-float))
        (list "bool"    (lit %py-cls-bool))
        (list "dict"    (lit %py-cls-dict))
        (list "tuple"   (lit %py-cls-tuple))
        (list "isinstance" (lit %py-isinstance))
        (list "pow"       (lit %py-pow3))
        (list "abs"       (lit %py-abs))
        (list "round"     (lit %py-round))
        (list "min"       (lit %py-min))
        (list "max"       (lit %py-max))
        (list "bytearray" (lit %py-cls-bytearray))
        (list "complex"   (lit %py-cls-complex))
        (list "hash"      (lit %py-hash))
        (list "NotImplemented" (lit %py-NotImplemented))
        (list "Ellipsis"       (lit %py-Ellipsis))
        (list "eval"           (lit %py-eval))
        (list "exec"           (lit %py-exec))
        (list "compile"        (lit %py-compile))
        (list "dir"            (lit %py-dir))
        (list "chr"       (lit %py-chr))
        (list "ord"       (lit %py-ord))
        (list "StopIteration"  (lit %py-exc-StopIteration))
        (list "GeneratorExit"  (lit %py-exc-GeneratorExit))
        (list "next"           (lit %py-next))
        (list "sum"            (lit %py-builtin-sum))
        (list "map"            (lit %py-cls-map))
        (list "zip"            (lit %py-cls-zip))
        (list "all"            (lit %py-all))
        (list "any"            (lit %py-any))
        (list "sorted"         (lit %py-sorted))
        (list "iter"           (lit %py-iter))
        (list "set"            (lit %py-cls-set))
        (list "frozenset"      (lit %py-cls-frozenset))
        (list "bin"            (lit %py-bin))
        (list "hex"            (lit %py-hex))
        (list "oct"            (lit %py-oct))
        (list "divmod"         (lit %py-divmod))
        (list "callable"       (lit %py-callable))
        (list "__import__"     (lit %py-import-call))
        (list "id"             (lit %py-id))
        (list "getattr"        (lit %py-getattr3))
        (list "setattr"        (lit %py-setattr3))
        (list "delattr"        (lit %py-delattr))
        (list "issubclass"     (lit %py-issubclass))
        (list "enumerate"      (lit %py-cls-enumerate))
        (list "filter"         (lit %py-cls-filter))
        (list "reversed"       (lit %py-cls-reversed))
        (list "SystemExit"     (lit %py-exc-SystemExit))
        ; The builtin exceptions are ordinary names bound to ordinary class
        ; values, so `except ValueError` and `except MyError` take one path.
        (list "BaseException"     (lit %py-exc-BaseException))
        (list "Exception"         (lit %py-exc-Exception))
        (list "ImportError"       (lit %py-exc-ImportError))
        (list "OSError"           (lit %py-exc-OSError))
        (list "IOError"           (lit %py-exc-OSError))
        (list "EOFError"          (lit %py-exc-EOFError))
        (list "KeyboardInterrupt" (lit %py-exc-KeyboardInterrupt))
        (list "IndentationError"  (lit %py-exc-IndentationError))
        (list "UnicodeError"      (lit %py-exc-UnicodeError))
        (list "MemoryError"       (lit %py-exc-MemoryError))
        (list "OverflowError"     (lit %py-exc-OverflowError))
        (list "NotImplementedError" (lit %py-exc-NotImplementedError))
        (list "StopAsyncIteration"  (lit %py-exc-StopAsyncIteration))
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

(def python-parse-expr (fn (_ toks) (%py-test toks)))

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
      ; A SIMPLE STATEMENT ON THE HEADER LINE -- `for x in y: print(x)` --
      ; is the block: its tokens up to the newline, parsed as statements.
      (if (if (null? (rest toks)) #f
            (if (eq? (%py-tag (first (rest toks))) (lit tok-newline)) #f
              (not (%py-block? (first (rest toks))))))
        (let ((sp (%py-line-of (rest toks) ())))
          (pair
            (%py-seq-of (first (%py-stmts (%py-semi->nl (first sp)) ())))
            (rest sp)))
      (let ((t (%py-skip-nl (rest toks))))
        (if (not (%py-block? (if (null? t) () (first t))))
          (Err raise (lit syntax) "expected an indented block" ())
          (pair
            (%py-seq-of (first (%py-stmts (%py-semi->nl (%py-block-toks (first t))) ())))
            (rest t))))))))

; (line-tokens . rest-from-the-newline)
(def %py-line-of
  (fn (self toks acc)
    (if (if (null? toks) #t
          (if (eq? (%py-tag (first toks)) (lit tok-newline)) (null? (rest (first toks))) #f))
      (pair (List reverse acc) toks)
      (self (rest toks) (pair (first toks) acc)))))

; Statements until the token list runs out.  A block IS its token list now, so
; running out is the only end there is.
; `a = 1; b = 2`: a top-level ; is a statement boundary, so it becomes the
; newline token the statement parser already stops at.  Shallow on
; purpose: a block's contents are their own list and get their own pass.
(def %py-semi->nl
  (fn (self toks)
    (if (null? toks) ()
      ; MARKED: (tok-newline semi), so a header line's one-line body --
      ; `for x in y: a; b` -- still runs to the real newline
      (pair (if (%py-op-is? (first toks) ";") (list (lit tok-newline) (lit semi)) (first toks))
        (self (rest toks))))))

(set! %py-stmts
  (fn (self toks acc)
    (let ((t (%py-skip-nl toks)))
      (if (null? t)
        (pair (List reverse acc) t)
        (let ((r (%py-stmt t)))
          (self (rest r) (pair (first r) acc)))))))

; --- import ------------------------------------------------------------------
;
; `import a`, `import a as b`, `from a import x, y`, `from a import x as z`
; and `from a import *`.  A DOTTED name is read whole and handed to the
; importer, which has no file system to search and answers ImportError for
; everything it does not itself provide -- which is what lets a program whose
; import fails take its own fallback path, the way the corpus writes a probe.
(def %py-dotted-name
  (fn (self toks acc)
    (if (null? toks)
      (pair acc toks)
      (if (%py-op-is? (first toks) ".")
        (if (null? (rest toks))
          (pair acc toks)
          (self (rest (rest toks))
            (Str8 append acc (Str8 append "." (%py-val (first (rest toks)))))))
        (pair acc toks)))))

(def %py-import-name
  (fn (_ toks)
    (if (not (eq? (%py-tag (if (null? toks) () (first toks))) (lit tok-name)))
      (Err raise (lit syntax) "expected a module name after import" ())
      (%py-dotted-name (rest toks) (%py-val (first toks))))))

; the name a module is bound under: `import a.b` binds `a`, `as` renames
; the name a module is bound under: `import a.b` binds `a`, `as` renames.
; Str8 index-of answers NIL when the substring is absent, not -1.
(def %py-import-head
  (fn (_ name)
    (let ((i (Str8 index-of "." name)))
      (if (null? i) name (Str8 sub 0 i name)))))

; `from a import x, y as z` -- each name bound, `as` renaming it
; `from a import *` binds every PUBLIC name the module has, at run time --
; the parser cannot know them, so this reads the module's own attributes and
; defines each.  It lives in this file because turning a Python name into a
; symbol is the parser's own reader.
(def %py-import-star
  (fn (_ name)
    (let ((m (%py-import name)))
      (%py-import-star-bind (%py-obj-attrs m)))))

(def %py-import-star-bind
  (fn (self rows)
    (if (null? rows)
      ()
      (do
        (if (Str8 =? (Str8 sub 0 1 (first (first rows))) "_")
          ()
          (%py-defg (%py-name->sym (first (first rows))) (rest (first rows))))
        (self (rest rows))))))

; `import a, b as c` -- a comma-separated list, each binding its own name
(def %py-import-list
  (fn (self toks acc)
    (let ((r (%py-import-name toks)))
      (let ((name (first r)) (after (rest r)))
        (let ((bound
                (if (%py-name-is? (if (null? after) () (first after)) "as")
                  (let ((n (if (null? (rest after)) () (first (rest after)))))
                    (if (not (eq? (%py-tag n) (lit tok-name)))
                      (Err raise (lit syntax) "expected a name after as" ())
                      (list (%py-name->sym (%py-val n)) (rest (rest after)))))
                  ; `import a.b` binds the head name, as Python does
                  (list (%py-name->sym (%py-import-head name)) after))))
          (let ((acc2 (pair (list (lit def) (first bound)
                              (list (lit %py-import) name)) acc))
                (rest-toks (first (rest bound))))
            (if (%py-op-is? (if (null? rest-toks) () (first rest-toks)) ",")
              (self (rest rest-toks) acc2)
              (pair (pair (lit do) (List reverse acc2)) rest-toks))))))))

(def %py-from-imports
  (fn (self name toks acc)
    (match
      ((null? toks) (pair (pair (lit do) (List reverse acc)) toks))
      ((%py-op-is? (first toks) ",") (self name (rest toks) acc))
      ((eq? (%py-tag (first toks)) (lit tok-newline))
        (pair (pair (lit do) (List reverse acc)) toks))
      ((not (eq? (%py-tag (first toks)) (lit tok-name)))
        (Err raise (lit syntax) "expected a name after import" ()))
      (#t
        (let ((attr (%py-val (first toks))))
          (if (%py-name-is? (if (null? (rest toks)) () (first (rest toks))) "as")
            (let ((n (if (null? (rest (rest toks))) () (first (rest (rest toks))))))
              (if (not (eq? (%py-tag n) (lit tok-name)))
                (Err raise (lit syntax) "expected a name after as" ())
                (self name (rest (rest (rest toks)))
                  (pair (list (lit def) (%py-name->sym (%py-val n))
                          (list (lit %py-import-from) name attr)) acc))))
            (self name (rest toks)
              (pair (list (lit def) (%py-name->sym attr)
                      (list (lit %py-import-from) name attr)) acc))))))))

; --- with --------------------------------------------------------------------
;
; `with EXPR as NAME:` binds what __enter__ answers and runs the body inside a
; guard, so an exception reaches __exit__ and a normal finish reaches it too.
; The body is emitted INLINE rather than as a closure: `break`, `continue` and
; `return` are lexical here, and wrapping the body in a lambda would put them
; out of reach of the loop or function they belong to.
;
; Several items NEST, left to right, which is what `with A() as a, B() as b:`
; means -- and it is why B's __exit__ runs before A's.
(def %py-with-body ())
(set! %py-with-body
  (fn (self items body)
    (if (null? items)
      body
      (let ((it (first items)))
        (let ((mgr (first it)) (name (rest it)))
          (list (lit let) (list (list (lit %py-mgr) mgr))
            (list (lit let)
              (list (list (if (null? name) (lit %py-unused) name)
                      (list (lit %py-enter) (lit %py-mgr))))
              ; a cell, so the normal exit is taken only when the body ran to
              ; the end: a handler that swallowed an exception has already
              ; called __exit__ and must not call it twice
              (list (lit let) (list (list (lit %py-wok) (list (lit pair) #f ())))
                ; AN ESCAPE OUT OF THE BODY IS A NORMAL EXIT, and Python calls
                ; __exit__(None, None, None) on the way past.  The wind entry
                ; is what a `return`, `break` or `continue` finds and runs
                ; (python/runtime.x, "Unwinding on the way out"); the two paths
                ; that leave here on their own feet drop it first.  Nested
                ; items push outermost first, so the unwind calls the inner
                ; __exit__ before the outer one -- the order `with A(), B():`
                ; already has.
                (list (lit let) (list (list (lit %py-ww)
                                            (list (lit %py-wind-push!)
                                              (list (lit fn) (list (lit _))
                                                (list (lit %py-with-normal) (lit %py-mgr))))))
                  (list (lit %seq)
                    (list (lit guard)
                      (list (lit %py-we)
                        (list (lit %seq) (list (lit %py-wind-drop!) (lit %py-ww))
                          (list (lit %py-with-exc) (lit %py-mgr) (lit %py-we))))
                      (list (lit %seq)
                        (self (rest items) body)
                        (list (lit %set-first!) (lit %py-wok) #t)))
                    (list (lit %seq) (list (lit %py-wind-drop!) (lit %py-ww))
                      (list (lit if) (list (lit first) (lit %py-wok))
                        (list (lit %py-with-normal) (lit %py-mgr))
                        ()))))))))))))

; ITEM, ITEM, ... : each is an expression with an optional `as NAME`
(def %py-with-items
  (fn (self toks acc)
    (let ((e (%py-test toks)))
      (let ((after (rest e)))
        (if (%py-name-is? (if (null? after) () (first after)) "as")
          (let ((n (if (null? (rest after)) () (first (rest after)))))
            (if (not (eq? (%py-tag n) (lit tok-name)))
              (Err raise (lit syntax) "expected a name after as" ())
              (let ((acc2 (pair (pair (first e) (%py-name->sym (%py-val n))) acc))
                    (more (rest (rest after))))
                (if (%py-op-is? (if (null? more) () (first more)) ",")
                  (self (rest more) acc2)
                  (pair (List reverse acc2) more)))))
          (let ((acc2 (pair (pair (first e) ()) acc)))
            (if (%py-op-is? (if (null? after) () (first after)) ",")
              (self (rest after) acc2)
              (pair (List reverse acc2) after))))))))

(set! %py-stmt
  (fn (_ toks)
    (let ((t (first toks)))
      ; if / while / def are decided by the leading NAME.  They are keywords to
      ; the parser and plain names to the tokenizer, which is where that
      ; distinction belongs.
      (match
        ((%py-name-is? t "class") (%py-class-stmt (rest toks)))
        ((if (%py-name-is? t "global") #t (%py-name-is? t "nonlocal"))
          (let ((sp (%py-line-of (rest toks) ()))) (pair () (rest sp))))
        ((%py-name-is? t "with")
          (let ((items (%py-with-items (rest toks) ())))
            (let ((blk (%py-block (rest items))))
              (pair (%py-with-body (first items) (first blk)) (rest blk)))))
        ((%py-name-is? t "import") (%py-import-list (rest toks) ()))
        ((%py-name-is? t "from")
          (let ((r (%py-import-name (rest toks))))
            (let ((name (first r)) (after (rest r)))
              (if (not (%py-name-is? (if (null? after) () (first after)) "import"))
                (Err raise (lit syntax) "expected import after a from" ())
                (let ((what (rest after)))
                  (if (%py-op-is? (if (null? what) () (first what)) "*")
                    ; `from a import *` binds every public name the module has
                    (pair (list (lit %py-import-star) name) (rest what))
                    (%py-from-imports name what ())))))))
        ; `del NAME[k]`, `del NAME[a:b]`: the subscript form decides which
        ((%py-name-is? t "del")
          (let ((r (%py-postfix (rest toks))))
            (let ((tgt (first r)))
              (match
                ((not (pair? tgt))
                  (Err raise (lit syntax) "cannot delete this target" ()))
                ((eq? (first tgt) (lit %py-index))
                  (pair (pair (lit %py-delindex) (rest tgt)) (rest r)))
                ((eq? (first tgt) (lit %py-slice))
                  (pair (pair (lit %py-delslice) (rest tgt)) (rest r)))
                ; `del obj.attr` -- the runtime already had %py-delattr for
                ; the builtin of that name; only the statement was missing,
                ; and the attribute node carries exactly its two arguments.
                ((eq? (first tgt) (lit %py-getattr))
                  (pair (pair (lit %py-delattr) (rest tgt)) (rest r)))
                (#t (Err raise (lit syntax) "cannot delete this target" ()))))))
        ((%py-name-is? t "try") (%py-try (rest toks)))
        ((%py-name-is? t "raise") (%py-raise-stmt (rest toks)))
        ; THE CONDITION IS PYTHON'S TRUTH, NOT x's.  `if []:` must not run its
        ; body: an empty list is falsy in Python and a PY-LIST instance is a
        ; non-nil value to x, so the bare value in an x `if` was silently wrong.
        ; bool() stated the rule once in %py-truthy; conditions now ask it.
        ((%py-name-is? t "if")
          (let ((c (%py-test (rest toks))))
            (let ((b (%py-block (rest c))))
              (let ((e (%py-else (rest b))))
                (pair
                  (list (lit if) (list (lit %py-truthy) (first c))
                    (first b) (first e))
                  (rest e))))))
        ((%py-name-is? t "for") (%py-for (rest toks)))
        ((%py-name-is? t "while")
          (let ((c (%py-test (rest toks))))
            (let ((b (%py-block (rest c))))
              (let ((e (%py-loop-else (rest b))))
                (pair
                  (%py-loop-tail
                    (list
                      (list (lit fn) (list (lit self))
                        (list (lit if) (list (lit %py-truthy) (first c))
                          (list (lit %seq) (%py-wrap-escape (first b) (lit %py-continue))
                            (list (lit self)))
                          ())))
                    (first e))
                  (rest e))))))
        ((%py-op-is? t "@")
          (let ((ds (%py-decos-of toks ())))
            (let ((t2 (rest ds)))
              (if (not (%py-name-is? (if (null? t2) () (first t2)) "def"))
                (Err raise (lit syntax) "a decorator must be followed by a def" ())
                (let ((r (%py-def (rest t2))))
                  (pair
                    (list (lit def) (first (rest (first r)))
                      (%py-wrap-decos (first ds) (first (rest (rest (first r))))))
                    (rest r)))))))
        ((%py-name-is? t "def") (%py-def (rest toks)))
        ((%py-name-is? t "return")
          (let ((nxt (if (null? (rest toks)) () (first (rest toks)))))
            (if (if (null? nxt) #t
                  (if (eq? (%py-tag nxt) (lit tok-newline)) #t
                    (%py-block? nxt)))
              (pair (list (lit %py-return) ()) (rest toks))
              (let ((r (%py-exprlist (rest toks))))
                (pair (list (lit %py-return) (first r)) (rest r))))))
        ((%py-name-is? t "pass") (pair () (rest toks)))
        ((%py-name-is? t "break") (pair (list (lit %py-break) ()) (rest toks)))
        ((%py-name-is? t "continue") (pair (list (lit %py-continue) ()) (rest toks)))
        ((%py-unpack-stmt? toks) (%py-unpack-stmt toks))
        ; A statement can BEGIN with a unary operator (`~x`, `-x` as an
        ; expression statement); the postfix-target probe below would
        ; refuse the op token, so these go straight to the expression
        ; parser.
        ((if (%py-op-is? t "-") #t
                    (if (%py-op-is? t "+") #t (%py-op-is? t "~")))
          (%py-test toks))
        ; ASSIGNMENT IS DECIDED BY WHAT FOLLOWS A TARGET, not by the
        ; shape of the first token.  Parse a postfix expression -- a
        ; name, a subscript, an attribute, a call -- and then look.
        ; If it is not an assignment the tokens are re-parsed as a full
        ; expression from the start, which costs a second pass over one
        ; statement and keeps the two cases from having to agree about
        ; precedence.
        (#t
          (let ((tgt (%py-postfix toks)))
            (let ((nxt (if (null? (rest tgt)) () (first (rest tgt)))))
              (if (%py-op-is? nxt "=")
                (let ((r (%py-exprlist (rest (rest tgt)))))
                  (pair (%py-store (first tgt) (first r)) (rest r)))
                (let ((aug (%py-op-sym nxt %py-aug-ops)))
                  (if (null? aug)
                    (%py-test toks)
                    ; `t op= v` is `t = t op v`.  The target is evaluated
                    ; twice for a subscript, which is wrong for an
                    ; expression with side effects and right for every
                    ; case this handles today.
                    (let ((r (%py-test (rest (rest tgt)))))
                      (pair
                        (%py-store (first tgt)
                          (list aug (first tgt) (first r)))
                        (rest r)))))))))))))

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
      (match
        ((%py-name-is? t "in") (pair (List reverse acc) (rest toks)))
        ((%py-op-is? t ",") (self (rest toks) acc))
        ((eq? (%py-tag t) (lit tok-name))
          (self (rest toks) (pair (%py-val t) acc)))
        (#t (Err raise (lit syntax) "expected in after a for target" ()))))))

(def %py-syms-of
  (fn (self names acc)
    (if (null? names)
      (List reverse acc)
      (self (rest names) (pair (%py-name->sym (first names)) acc)))))

(def %py-for-bind
  (fn (_ syms)
    (if (null? (rest syms))
      (list (lit set!) (first syms) (lit %py-item))
      (list (lit let)
        (list (list (lit %py-unpacked)
                (list (lit %py-unpack) (lit %py-item) (%py-count syms))))
        (pair (lit do) (%py-unpack-sets syms 0 ()))))))

; --- break and continue ------------------------------------------------------
;
; Both are ESCAPES -- the shape `return` already uses: the loop binds a
; continuation, the statement invokes it.  `break` needs one per LOOP,
; `continue` one per ITERATION, and a stack copy per iteration is not a price
; an ordinary loop should pay, so a loop binds only what its body reaches for.
;
; The question is asked of the COMPILED body rather than of the tokens, and
; that is what makes nesting come out right: by the time an outer loop asks,
; an inner loop has already bound its own %py-break, so an occurrence still
; FREE here is one that belongs to THIS loop.  The same reading decides the
; error case -- a `break` still free in a whole function body is outside every
; loop, which is a SyntaxError before anything runs.

(def %py-sym-in?
  (fn (self syms sym)
    (if (not (pair? syms)) #f
      (if (eq? (first syms) sym) #t (self (rest syms) sym)))))

; A form that BINDS the name -- the only `fn` this ever meets with the name in
; its parameters is a nested loop's own wrapper, and that is precisely the
; occurrence this loop must not claim.
(def %py-shadows?
  (fn (_ form sym)
    (if (eq? (first form) (lit fn))
      (if (pair? (rest form)) (%py-sym-in? (first (rest form)) sym) #f)
      #f)))

(def %py-free-ref?
  (fn (self form sym)
    (match
      ((not (pair? form)) (eq? form sym))
      ((%py-shadows? form sym) #f)
      (#t (if (self (first form) sym) #t (self (rest form) sym))))))

; %py-escape, not the raw call/cc: an escape must run the cleanup it is about
; to jump over (python/runtime.x, "Unwinding on the way out").
(def %py-wrap-escape
  (fn (_ form sym)
    (if (%py-free-ref? form sym)
      (list (lit %py-escape) (list (lit fn) (list (lit _) sym) form))
      form)))

; A scope boundary: every loop inside has had its turn, so anything left is
; outside one.  CPython words the two cases differently; so does this.
(def %py-check-escapes
  (fn (_ body)
    (if (%py-free-ref? body (lit %py-break))
      (Err raise (lit syntax) "'break' outside loop" ())
      (if (%py-free-ref? body (lit %py-continue))
        (Err raise (lit syntax) "'continue' not properly in loop" ())
        body))))

; `for ... else:` / `while ... else:` -- the clause that runs when the loop RAN
; OUT.  Not %py-else: that one also takes `elif`, which Python does not allow
; after a loop and which is left to be the syntax error it is.
(def %py-loop-else
  (fn (_ toks)
    (let ((t (%py-skip-nl toks)))
      (if (null? t)
        (pair () t)
        (if (%py-name-is? (first t) "else")
          (let ((b (%py-block (rest t))))
            (pair (first b) (rest b)))
          (pair () t))))))

; THE ELSE IS GUARDED ON WHICH WAY THE LOOP LEFT, and it sits OUTSIDE the
; escape the loop binds.  Both halves are the semantics:
;
;   outside, because a `break` written in an else belongs to the ENCLOSING
;   loop -- `for i: (for j: pass else: break)` breaks the OUTER one -- so the
;   else must not be inside this loop's binding, which also leaves a break
;   with no loop around it free for %py-check-escapes to refuse;
;
;   guarded, because the escape answers what it was passed when `break` jumped
;   -- () -- and the body's own value when the loop ran out.  That value is 1
;   here, chosen for nothing but being something () is not.
;
; %py-escape, not the raw call/cc: this binds a `break` like any other loop
; does, so it owes the same unwinding (python/runtime.x, "Unwinding on the way
; out").  The raw one skips the `finally` of the iteration that breaks, which
; is the whole of what %py-escape exists to stop.  It answers exactly what
; call/cc answers, so the guard above reads the same either way.
;
; A loop with no `break` in it always runs its else, and pays no continuation
; to find that out.
(def %py-loop-tail
  (fn (_ loop els)
    (match
      ((null? els) (%py-wrap-escape loop (lit %py-break)))
      ((not (%py-free-ref? loop (lit %py-break))) (list (lit %seq) loop els))
      (#t
        (list (lit if)
          (list (lit null?)
            (list (lit %py-escape)
              (list (lit fn) (list (lit _) (lit %py-break))
                (list (lit %seq) loop 1))))
          ()
          els)))))

(def %py-for
  (fn (_ toks)
    (if (not (eq? (%py-tag (if (null? toks) () (first toks))) (lit tok-name)))
      (Err raise (lit syntax) "expected a name after for" ())
      (let ((n (%py-for-names toks ())))
        (let ((syms (%py-syms-of (first n) ())))
          (let ((it (%py-exprlist (rest n))))
            (let ((b (%py-block (rest it))))
              ; THE LOOP PULLS ONE ITEM AT A TIME from %py-iter-open's source:
              ; a generator yields lazily (its prints interleave with the
              ; body's), anything else is its materialized element list.
              (let ((e (%py-loop-else (rest b))))
                (pair
                  (%py-loop-tail
                    (list
                      (list (lit fn) (list (lit self) (lit %py-src))
                        (list (lit let) (list (list (lit %py-item) (list (lit %py-iter-pull!) (lit %py-src))))
                          (list (lit if) (list (lit same?) (lit %py-item) (lit %py-gen-done))
                            ()
                            (list (lit %seq)
                              (%py-for-bind syms)
                              (list (lit %seq) (%py-wrap-escape (first b) (lit %py-continue))
                                (list (lit self) (lit %py-src)))))))
                      (list (lit %py-iter-open) (first it)))
                    (first e))
                  (rest e))))))))))

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
        (match
          ((%py-op-is? t ",") (self (rest toks) acc))
          ((%py-op-is? t "**")
            (let ((n (if (null? (rest toks)) () (first (rest toks)))))
              (if (not (eq? (%py-tag n) (lit tok-name)))
                (Err raise (lit syntax) "expected a name after **" t)
                (self (rest (rest toks)) (pair (%py-name->sym (%py-val n)) acc)))))
          ((%py-op-is? t "*")
            (let ((n (if (null? (rest toks)) () (first (rest toks)))))
              (if (not (eq? (%py-tag n) (lit tok-name)))
                (Err raise (lit syntax) "expected a name after *" t)
                (do
                  (%set-first! %py-rest-param (%py-name->sym (%py-val n)))
                  (self (rest (rest toks)) (pair (%py-name->sym (%py-val n)) acc))))))
          ((eq? (%py-tag t) (lit tok-name))
            (self (rest toks) (pair (%py-name->sym (%py-val t)) acc)))
          (#t (Err raise (lit syntax) "expected a name" t)))))))

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
; (names defaults rest-name kw-name): names are strings in declaration order,
; required first; defaults is ((sym . EXPR) ...) for the optional tail;
; rest-name is the *name string or nil; kw-name is the **name or nil.
(def %py-params-of
  (fn (_ toks)
    (def go
      (fn (self parts names dflts rest-name kw-name)
        (if (null? parts)
          (list (List reverse names) (List reverse dflts) rest-name kw-name)
          (let ((p (first parts)))
            (let ((t (first p)))
              (match
                ((%py-op-is? t "**")
                  (let ((n (if (null? (rest p)) () (first (rest p)))))
                    (if (not (eq? (%py-tag n) (lit tok-name)))
                      (Err raise (lit syntax) "expected a name after **" t)
                      (self (rest parts) names dflts rest-name (%py-val n)))))
                ((%py-op-is? t "*")
                  (let ((n (if (null? (rest p)) () (first (rest p)))))
                    (if (not (eq? (%py-tag n) (lit tok-name)))
                      (Err raise (lit syntax) "expected a name after *" t)
                      (self (rest parts) names dflts (%py-val n) kw-name))))
                ((not (eq? (%py-tag t) (lit tok-name)))
                  (Err raise (lit syntax) "expected a parameter name" t))
                ((null? (rest p))
                  (if (null? dflts)
                    (self (rest parts) (pair (%py-val t) names) dflts rest-name kw-name)
                    (Err raise (lit syntax) "non-default argument follows default argument" t)))
                ((not (%py-op-is? (first (rest p)) "="))
                  (Err raise (lit syntax) "expected , or = after a parameter name" t))
                (#t
                  (self (rest parts) (pair (%py-val t) names)
                    (pair (pair (%py-name->sym (%py-val t)) (%py-expr-of (rest (rest p)))) dflts)
                    rest-name kw-name))))))))
    (go (%py-comma-split toks () ()) () () () ())))

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
(def %py-strs->syms
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
                  ; FINALLY RUNS ON ALL THREE PATHS.  The body is emitted ONCE,
                  ; as a thunk, and reached three ways: after the guarded form
                  ; when it finished, from a handler that then re-raises, and
                  ; -- for a `return`, `break` or `continue` out of the try --
                  ; from the wind stack, which %py-escape walks before it jumps
                  ; (python/runtime.x, "Unwinding on the way out").
                  ;
                  ; The first two DROP the entry before running the thunk, so
                  ; it runs exactly once whichever way the block is left, and a
                  ; handler that re-raises does not leave the entry stranded.
                  (list (lit let) (list (list (lit %py-fin-th)
                                              (list (lit fn) (list (lit _)) (first f))))
                    (list (lit let) (list (list (lit %py-fin-w)
                                                (list (lit %py-wind-push!) (lit %py-fin-th))))
                      (list (lit guard)
                        (list (lit %py-fin)
                          (list (lit %seq) (list (lit %py-wind-drop!) (lit %py-fin-w))
                            (list (lit %seq) (list (lit %py-fin-th))
                              (list (lit error) (lit %py-fin)))))
                        (list (lit %seq) guarded
                          (list (lit %seq) (list (lit %py-wind-drop!) (lit %py-fin-w))
                            (list (lit %py-fin-th))))))))
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
                    ; every argument: raise ValueError('a', 0)
                    (pair (%py-name->sym (%py-val n)) (%py-group-exprs g))))
                (rest (rest toks))))
            ; `raise X` with no parens: a class instantiates, an instance
            ; (from `except X as e`) raises as itself
            (pair
              (list (lit %py-raise) (list (lit %py-exc-instance) (%py-name->sym (%py-val n)) ()))
              (rest toks))))))))

; --- decorators --------------------------------------------------------------
;
; `@deco` before a def is a CALL: Python's rule is f = deco(f), applied bottom
; up, so @a @b def f leaves a(b(f)).  Nothing here needs to know which
; decorator it is -- staticmethod, classmethod and property are ordinary
; builtins that answer descriptors, and a user-written decorator is a function
; like any other.

(def %py-decos-of ())
(set! %py-decos-of
  ; answers (DECORATOR-EXPRS . TOKENS-AFTER), source order, at the def
  (fn (self toks acc)
    (let ((t (%py-skip-nl toks)))
      (if (if (null? t) #f (%py-op-is? (first t) "@"))
        (let ((d (%py-exprlist (rest t))))
          (self (rest d) (pair (first d) acc)))
        (pair (List reverse acc) t)))))

(def %py-wrap-decos ())
(set! %py-wrap-decos
  ; (a b) over F is (a (b F)) -- the decorator nearest the def runs first
  (fn (self ds f)
    (if (null? ds) f (list (first ds) (self (rest ds) f)))))

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
      (match
        ((null? t) (pair (List reverse acc) t))
        ; A DECORATED METHOD is the same entry with a call around its function:
        ; the decorators are collected, the def is parsed as it always was, and
        ; what goes in the alist is deco(fn) rather than fn.
        ((%py-op-is? (first t) "@")
          (let ((ds (%py-decos-of t ())))
            (let ((t2 (rest ds)))
              (if (not (%py-name-is? (if (null? t2) () (first t2)) "def"))
                (Err raise (lit syntax) "a decorator must be followed by a def" ())
                (let ((nm (if (null? (rest t2)) () (first (rest t2)))))
                  (if (not (eq? (%py-tag nm) (lit tok-name)))
                    (Err raise (lit syntax) "expected a method name after def" ())
                    (let ((r (%py-def (rest t2))))
                      (self (rest r)
                        (pair
                          (list (lit pair) (%py-val nm)
                            (%py-wrap-decos (first ds)
                              (first (rest (rest (first r))))))
                          acc)))))))))
        ((%py-name-is? (first t) "pass") (self (rest t) acc))
        ((not (%py-name-is? (first t) "def"))
          (if (if (eq? (%py-tag (first t)) (lit tok-name))
                (%py-op-is? (if (null? (rest t)) () (first (rest t))) "=")
                #f)
            (let ((v (%py-exprlist (rest (rest t)))))
              (self (rest v)
                (pair (list (lit pair) (%py-val (first t)) (first v)) acc)))
            ; A BARE EXPRESSION IN A CLASS BODY is evaluated and dropped,
            ; which is how Python spells a class DOCSTRING -- the string
            ; is the first statement of the body and nothing reads it
            ; here.  Refusing it meant no class in this runtime could
            ; carry documentation at all.
            (let ((v (%py-exprlist t)))
              (self (rest v) acc))))
        (#t
          (let ((nm (if (null? (rest t)) () (first (rest t)))))
            (if (not (eq? (%py-tag nm) (lit tok-name)))
              (Err raise (lit syntax) "expected a method name after def" ())
              (let ((r (%py-def (rest t))))
                (self (rest r)
                  (pair
                    (list (lit pair) (%py-val nm)
                      (first (rest (rest (first r)))))
                    acc))))))))))

(def %py-class-block
  (fn (_ toks)
    (if (not (%py-op-is? (if (null? toks) () (first toks)) ":"))
      (Err raise (lit syntax) "expected : after a class header" ())
      ; `class A: pass` on the header line is a body too
      (if (if (null? (rest toks)) #f
            (if (eq? (%py-tag (first (rest toks))) (lit tok-newline)) #f
              (not (%py-block? (first (rest toks))))))
        (let ((sp (%py-line-of (rest toks) ())))
          (pair (first (%py-class-methods-of (first sp) ())) (rest sp)))
      (let ((t (%py-skip-nl (rest toks))))
        (if (not (%py-block? (if (null? t) () (first t))))
          (Err raise (lit syntax) "expected an indented class body" ())
          (pair
            (first (%py-class-methods-of (%py-block-toks (first t)) ()))
            (rest t))))))))

; The body of every class header, whatever spelled its base: bind the current
; class (so `super()` inside a method knows where it stands), parse the block,
; and emit the one (set! NAME (%py-mkclass ...)).  It was written out three
; times before, which is what made adding a fourth spelling a paren exercise.
(def %py-class-of
  (fn (_ n toks base)
    (let ((outer (first %py-current-class)))
      (%set-first! %py-current-class (%py-name->sym (%py-val n)))
      (let ((r (%py-class-block toks)))
        (%set-first! %py-current-class outer)
        (pair
          (list (lit set!) (%py-name->sym (%py-val n))
            (list (lit %py-mkclass) (%py-val n) base
              (pair (lit list) (first r))))
          (rest r))))))

(def %py-class-stmt
  (fn (_ toks)
    ; positioned just after the `class` keyword
    (let ((n (if (null? toks) () (first toks))))
      (if (not (eq? (%py-tag n) (lit tok-name)))
        (Err raise (lit syntax) "expected a class name after class" ())
        (let ((after (rest toks)))
          (if (%py-group? (if (null? after) () (first after)) "(")
            ; EVERY base, as expressions: `class Sub(A, B)` is ordinary Python,
            ; and reading the group the way a call's arguments are read means a
            ; base can be any expression -- which is what Python says too.  One
            ; that turns out not to be a class is caught at %py-mkclass, where
            ; the message can say so.
            (let ((es (%py-group-exprs (%py-group-of (first after)))))
              (if (null? es)
                ; `class C():` IS `class C:` -- empty parens are legal Python
                ; and the corpus writes them; the base is object either way.
                (%py-class-of n (rest after) (list (lit list) (lit %py-cls-object)))
                (%py-class-of n (rest after) (pair (lit list) es))))
            (%py-class-of n after (list (lit list) (lit %py-cls-object)))))))))

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
        (match
          ((eq? (%py-tag t) (lit tok-newline)) #f)
          ((%py-op-is? t "=") comma)
          ((%py-op-is? t ",") (self (rest toks) #t))
          ((eq? (%py-tag t) (lit tok-name)) (self (rest toks) comma))
          (#t #f))))))

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
      (match
        ((eq? (first target) (lit %py-index))
          (list (lit %py-setindex) (first (rest target))
                (first (rest (rest target))) value))
        ; `self.x = 1` is how a Python object gets its fields at all, so an
        ; attribute is an assignable target exactly as a subscript is.
        ((eq? (first target) (lit %py-getattr))
          (list (lit %py-setattr) (first (rest target))
                (first (rest (rest target))) value))
        ; `l[1:3] = xs` replaces that span, and may change the length
        ((eq? (first target) (lit %py-slice))
          (pair (lit %py-setslice) (%py-append (rest target) (list value))))
        (#t (Err raise (lit syntax) "cannot assign to this target" ())))
      (list (lit set!) target value))))

(def %py-else
  (fn (_ toks)
    (let ((t (%py-skip-nl toks)))
      (match
        ((null? t) (pair () t))
        ((%py-name-is? (first t) "else")
          (let ((b (%py-block (rest t))))
            (pair (first b) (rest b))))
        ((%py-name-is? (first t) "elif")
          (let ((c (%py-test (rest t))))
            (let ((b (%py-block (rest c))))
              (let ((e (%py-else (rest b))))
                (pair
                  (list (lit if) (list (lit %py-truthy) (first c))
                    (first b) (first e))
                  (rest e))))))
        (#t (pair () t))))))

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
            (def syms (%py-strs->syms names))
            (def dflts (first (rest sig)))
            (def rest-name (first (rest (rest sig))))
            (def rest-sym (if (null? rest-name) () (%py-name->sym rest-name)))
            (def kw-name (List ref 3 sig))
            (def kw-sym (if (null? kw-name) () (%py-name->sym kw-name)))
            (def nreq (- (List length names) (List length dflts)))
            (def all-syms
              (let ((withrest (if (null? rest-sym) syms (%py-append syms (list rest-sym)))))
                (if (null? kw-sym) withrest (%py-append withrest (list kw-sym)))))
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
                                (%py-append (%py-global-names (%py-block-contents after) ()) all-syms))))
                  (def body0
                    (if (null? locals) (first b) (list (lit let) (%py-lets locals ()) (first b))))
                  ; the rest arrives as an x list; Python hands the function a
                  ; TUPLE.  With defaults the prelude is the %py-opt let.
                  ; **kwargs IS BOUND FROM THE BOX at the end of the tail, and
                  ; the tail is then read WITHOUT it, so the optional binders
                  ; and *rest see only real positional arguments.  A plain call
                  ; carries no box, and %py-kwargs-of answers an empty dict --
                  ; which is exactly what Python gives such a call.
                  (def body-kw
                    (fn (_ inner)
                      (if (null? kw-sym)
                        inner
                        (list (lit let)
                          (list (list kw-sym (list (lit %py-kwargs-of) (lit %py-more))))
                          (list (lit let)
                            (list (list (lit %py-more)
                                    (list (lit %py-args-strip-kw) (lit %py-more))))
                            inner)))))
                  (def body
                    (body-kw
                      (if (null? dflts)
                        (if (null? rest-sym)
                          body0
                          ; with **kwargs the fn is variadic for the box, so
                          ; *rest is bound from the tail rather than being the
                          ; dotted parameter itself
                          (if (null? kw-sym)
                            (list (lit %seq)
                              (list (lit set!) rest-sym (list (lit %py-tuple-of-list) rest-sym))
                              body0)
                            (list (lit let)
                              (list (list rest-sym
                                      (list (lit %py-tuple-of-list) (lit %py-more))))
                              body0)))
                        ; without a *rest, more optionals than declared is a
                        ; TypeError -- the dotted tail would swallow them
                        (if (null? rest-sym)
                          (list (lit %seq)
                            (list (lit %py-arity!) (%py-val name) (lit %py-more)
                              nreq (List length dflts))
                            (list (lit let) (%py-opt-lets dflts 0 ()) body0))
                          (list (lit let) (%py-opt-lets dflts 0 rest-sym) body0)))))
                  (def params
                    (if (not (null? kw-sym))
                      ; the box arrives in the tail, so the fn must have one
                      (%py-dotted-params (%py-take nreq syms) (lit %py-more))
                      (if (null? dflts)
                        (if (null? rest-sym) syms (%py-dotted-params syms rest-sym))
                        (%py-dotted-params (%py-take nreq syms) (lit %py-more)))))
                  ; The body runs inside call/cc so `return` has somewhere to
                  ; jump to, and ends in () so a function that falls off the
                  ; end answers None.  %seq TAKES TWO FORMS -- a third arm is
                  ; silently dropped.
                  ; A BODY WITH A yield IS A GENERATOR FUNCTION: calling it
                  ; binds the parameters and answers a generator whose body
                  ; closure -- taking the generator as %py-gen, the object
                  ; its yields talk to -- runs on the first next().
                  (def fn-form
                    (if (%py-has-yield? (%py-block-contents after) #f)
                      (list (lit fn) (pair (lit _) params)
                        (list (lit %py-gen-new)
                          (list (lit fn) (list (lit _) (lit %py-gen))
                            (list (lit %py-escape)
                              (list (lit fn) (list (lit _) (lit %py-return))
                                (list (lit %seq) (%py-check-escapes body) ()))))
                          (%py-val name)))
                      (list (lit fn) (pair (lit _) params)
                        (list (lit %py-escape)
                          (list (lit fn) (list (lit _) (lit %py-return))
                            (list (lit %seq) (%py-check-escapes body) ()))))))
                  ; %py-sig! records the parameter names for keyword calls and
                  ; answers the closure, so this is still the def's value form
                  ; -- a class body reads it as the method.
                  (def sig-form
                    (list (lit %py-sig!) fn-form (%py-val name)
                      (pair (lit list) names) nreq (not (null? rest-sym))
                      (if (null? kw-name) () kw-name)))
                  (%set-first! %py-current-self outer-self)
                  (pair
                    (list (lit def) (%py-name->sym (%py-val name))
                      (if (null? dflts)
                        sig-form
                        (list (lit let) (%py-dflt-lets dflts 0) sig-form)))
                    (rest b)))))))))))

; Is there a `yield` in this body?  Groups and blocks are searched, except
; the block of a nested def or class, whose yields are its own.
; The names declared global (or nonlocal) anywhere in a body, as symbols.
(def %py-global-names
  (fn (self toks acc)
    (if (null? toks) acc
      (let ((t (first toks)))
        (if (if (%py-name-is? t "global") #t (%py-name-is? t "nonlocal"))
          (let ((sp (%py-line-of (rest toks) ())))
            (def names
              (fn (self ts a)
                (if (null? ts) a
                  (if (eq? (%py-tag (first ts)) (lit tok-name))
                    (self (rest ts) (pair (%py-name->sym (%py-val (first ts))) a))
                    (self (rest ts) a)))))
            (self (rest sp) (names (first sp) acc)))
          (if (%py-block? t)
            (self (rest toks) (self (%py-block-toks t) acc))
            (self (rest toks) acc)))))))

(def %py-has-yield?
  (fn (self toks skip-block)
    (if (null? toks) #f
      (let ((t (first toks)))
        (match
          ((%py-name-is? t "yield") #t)
          ((if (%py-name-is? t "def") #t (%py-name-is? t "class"))
            (self (rest toks) #t))
          ((eq? (%py-tag t) (lit tok-group))
            (if (self (%py-group-of t) #f) #t (self (rest toks) skip-block)))
          ((%py-block? t)
            (if (if skip-block #f (self (%py-block-toks t) #f)) #t (self (rest toks) #f)))
          (#t (self (rest toks) skip-block)))))))

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
        (match
          ((eq? (%py-tag t) (lit tok-name))
            (self (rest toks) (pair (%py-val t) acc)))
          ((eq? (%py-tag t) (lit tok-group))
            (self (rest toks) (%py-append (List reverse (self (%py-group-of t) ())) acc)))
          ((%py-block? t)
            (self (rest toks) (%py-append (List reverse (self (%py-block-toks t) ())) acc)))
          (#t (self (rest toks) acc)))))))

; Every name the program BINDS: assignment targets, def names, parameters.
(def %py-bound-names
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (match
          ((%py-for-target? toks)
            (let ((u (%py-for-names (rest toks) ())))
              (self (rest u) (%py-append (List reverse (first u)) acc))))
          ((%py-name-is? t "as")
            (let ((n (if (null? (rest toks)) () (first (rest toks)))))
              (self (rest (rest toks))
                (if (eq? (%py-tag n) (lit tok-name)) (pair (%py-val n) acc) acc))))
          ((%py-name-is? t "def")
            (let ((n (if (null? (rest toks)) () (first (rest toks)))))
              (self (rest (rest toks))
                (if (eq? (%py-tag n) (lit tok-name)) (pair (%py-val n) acc) acc))))
          ((if (eq? (%py-tag t) (lit tok-name))
                (%py-assign-op? (if (null? (rest toks)) () (first (rest toks))))
                #f)
            (self (rest toks) (pair (%py-val t) acc)))
          (#t (self (rest toks) acc)))))))

(def %py-assign-targets
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        ; DESCEND INTO BLOCKS.  `if x:` then `y = 1` binds y at MODULE level in
        ; Python, and the body is a nested token now -- a scan that stayed at
        ; the top level would hoist nothing from any compound statement.  Def
        ; bodies are still skipped below: those targets are the function's own.
        (match
          ((%py-block? t)
            (self (rest toks) (%py-append (List reverse (self (%py-block-toks t) ())) acc)))
          ((%py-for-target? toks)
            (let ((u (%py-for-names (rest toks) ())))
              (self (rest u) (%py-append (List reverse (%py-syms-of (first u) ())) acc))))
          ((%py-block? t)
            (self (rest toks) (%py-append (List reverse (self (%py-block-toks t) ())) acc)))
          ((%py-unpack-stmt? toks)
            (let ((u (%py-unpack-names toks ())))
              (self (rest u) (%py-append (List reverse (first u)) acc))))
          ((%py-name-is? t "class")
            (let ((n (if (null? (rest toks)) () (first (rest toks)))))
              (self (rest (rest toks))
                (if (eq? (%py-tag n) (lit tok-name))
                  (pair (%py-name->sym (%py-val n)) acc) acc))))
          ((%py-as-target? toks)
            (self (rest (rest toks))
              (pair (%py-name->sym (%py-val (first (rest toks)))) acc)))
          ((%py-name-is? t "def") (self (%py-skip-def (rest toks) 0) acc))
          ((if (eq? (%py-tag t) (lit tok-name))
                (%py-assign-op? (if (null? (rest toks)) () (first (rest toks))))
                #f)
            (self (rest toks) (pair (%py-name->sym (%py-val t)) acc)))
          (#t (self (rest toks) acc)))))))

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
    (def %body (%py-check-escapes (first (%py-stmts (%py-semi->nl %toks) ()))))
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
