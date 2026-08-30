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
(def %py-num
  (fn (_ text)
    (if (null? (Str8 index-of "." text))
      (first (%py-read-str (Base raw-of %py-sexp-base) (Str8 append text " ")))
      (Float from text))))

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
(def %py-product-ops
  (list (list "*" (lit %py-mul)) (list "/" (lit %py-div))
        (list "//" (lit %py-floordiv)) (list "%" (lit %py-mod))))

; --- The ladder --------------------------------------------------------------
(def %py-comparison ())
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

(set! %py-comparison (fn (_ toks) (%py-left toks %py-cmp-ops %py-sum)))
(set! %py-sum        (fn (_ toks) (%py-left toks %py-sum-ops %py-product)))
(set! %py-product    (fn (_ toks) (%py-left toks %py-product-ops %py-unary)))

(set! %py-unary
  (fn (_ toks)
    (if (%py-op-is? (if (null? toks) () (first toks)) "-")
      (let ((r (%py-unary (rest toks))))
        (pair (list (lit %py-neg) (first r)) (rest r)))
      (%py-power toks))))

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
        (if (%py-op-is? (if (null? more) () (first more)) "(")
          (let ((r (%py-args (rest more) ())))
            (self (pair acc (first r)) (rest r)))
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
          (if (%py-op-is? (if (null? more) () (first more)) "[")
            (let ((r (%py-comparison (rest more))))
              (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) "]")
                (self (list (lit %py-index) acc (first r)) (rest (rest r)))
                (Err raise (lit syntax) "expected ] after a subscript" ())))
            (pair acc more))))))
    (%go (first %a) (rest %a))))

; Arguments up to the closing paren.  A trailing comma is legal Python and costs
; one branch to accept.
(def %py-args
  (fn (self toks acc)
    (if (%py-op-is? (if (null? toks) () (first toks)) ")")
      (pair (List reverse acc) (rest toks))
      (let ((r (%py-comparison toks)))
        (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ",")
          (self (rest (rest r)) (pair (first r) acc))
          (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ")")
            (pair (List reverse (pair (first r) acc)) (rest (rest r)))
            (Err raise (lit syntax) "expected , or ) in argument list" ())))))))

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
            (if (eq? (%py-tag t) (lit tok-name))
              (pair (%py-name->sym (%py-val t)) (rest toks))
              (if (%py-op-is? t "{")
                (let ((r (%py-entries (rest toks) ())))
                  (pair (pair (lit %py-mkdict) (first r)) (rest r)))
              (if (%py-op-is? t "[")
                (let ((r (%py-elems (rest toks) ())))
                  (pair (pair (lit %py-mklist) (first r)) (rest r)))
              (if (%py-op-is? t "(")
                (let ((r (%py-comparison (rest toks))))
                  (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ")")
                    (pair (first r) (rest (rest r)))
                    (Err raise (lit syntax) "expected )" ())))
                (Err raise (lit syntax) "unexpected token in expression" t)))))))))))

; Entries of a dict literal: KEY : VALUE, up to the closing brace. Each entry
; becomes (pair KEY VALUE) so the runtime holds an association list in insertion
; order -- which is the printed order, and therefore part of the answer.
;
; `{}` is an empty DICT, not an empty set. Python spells the empty set as set(),
; which is not implemented, so there is no ambiguity to resolve here.
(def %py-entries
  (fn (self toks acc)
    (if (%py-op-is? (if (null? toks) () (first toks)) "}")
      (pair (List reverse acc) (rest toks))
      (let ((k (%py-comparison toks)))
        (if (not (%py-op-is? (if (null? (rest k)) () (first (rest k))) ":"))
          (Err raise (lit syntax) "expected : after a dict key" ())
          (let ((v (%py-comparison (rest (rest k)))))
            (let ((e (list (lit pair) (first k) (first v))))
              (if (%py-op-is? (if (null? (rest v)) () (first (rest v))) ",")
                (self (rest (rest v)) (pair e acc))
                (if (%py-op-is? (if (null? (rest v)) () (first (rest v))) "}")
                  (pair (List reverse (pair e acc)) (rest (rest v)))
                  (Err raise (lit syntax) "expected , or } in dict literal" ()))))))))))

; Elements of a list literal, up to the closing bracket.  A trailing comma is
; legal Python and costs one branch.
(def %py-elems
  (fn (self toks acc)
    (if (%py-op-is? (if (null? toks) () (first toks)) "]")
      (pair (List reverse acc) (rest toks))
      (let ((r (%py-comparison toks)))
        (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ",")
          (self (rest (rest r)) (pair (first r) acc))
          (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) "]")
            (pair (List reverse (pair (first r) acc)) (rest (rest r)))
            (Err raise (lit syntax) "expected , or ] in list literal" ())))))))

; A Python name becomes an x symbol, EXCEPT the builtins that have a runtime
; function -- `print` is the only one so far.  A name table rather than a
; rewrite in the parser, so the list is one place.
(def %py-builtins
  (list (list "print" (lit %py-print))
        (list "True"  #t)
        (list "False" #f)
        (list "None"  ())
        (list "len"   (lit %py-len))
        (list "range" (lit %py-range))))

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

(def python-parse-expr (fn (_ toks) (%py-comparison toks)))

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

; `: NEWLINE INDENT stmts DEDENT` -- the suite after a compound header.
(def %py-block
  (fn (_ toks)
    (if (not (%py-op-is? (if (null? toks) () (first toks)) ":"))
      (Err raise (lit syntax) "expected : after a compound statement header" ())
      (let ((t (%py-skip-nl (rest toks))))
        (if (not (eq? (%py-tag (if (null? t) () (first t))) (lit tok-indent)))
          (Err raise (lit syntax) "expected an indented block" ())
          (let ((r (%py-stmts (rest t) ())))
            (pair (%py-seq-of (first r)) (rest r))))))))

; Statements until DEDENT (which is consumed) or end of input.
(set! %py-stmts
  (fn (self toks acc)
    (let ((t (%py-skip-nl toks)))
      (if (null? t)
        (pair (List reverse acc) t)
        (if (eq? (%py-tag (first t)) (lit tok-dedent))
          (pair (List reverse acc) (rest t))
          (let ((r (%py-stmt t)))
            (self (rest r) (pair (first r) acc))))))))

(set! %py-stmt
  (fn (_ toks)
    (let ((t (first toks)))
      ; if / while / def are decided by the leading NAME.  They are keywords to
      ; the parser and plain names to the tokenizer, which is where that
      ; distinction belongs.
      (if (%py-name-is? t "if")
        (let ((c (%py-comparison (rest toks))))
          (let ((b (%py-block (rest c))))
            (let ((e (%py-else (rest b))))
              (pair (list (lit if) (first c) (first b) (first e)) (rest e)))))
        (if (%py-name-is? t "for")
          (%py-for (rest toks))
        (if (%py-name-is? t "while")
          (let ((c (%py-comparison (rest toks))))
            (let ((b (%py-block (rest c))))
              (pair
                (list
                  (list (lit fn) (list (lit self))
                    (list (lit if) (first c)
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
                        (eq? (%py-tag nxt) (lit tok-dedent))))
                  (pair (list (lit %py-return) ()) (rest toks))
                  (let ((r (%py-comparison (rest toks))))
                    (pair (list (lit %py-return) (first r)) (rest r)))))
              (if (%py-name-is? t "pass")
                (pair () (rest toks))
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
                      (let ((r (%py-comparison (rest (rest tgt)))))
                        (pair (%py-store (first tgt) (first r)) (rest r)))
                      (let ((aug (%py-op-sym nxt %py-aug-ops)))
                        (if (null? aug)
                          (%py-comparison toks)
                          ; `t op= v` is `t = t op v`.  The target is evaluated
                          ; twice for a subscript, which is wrong for an
                          ; expression with side effects and right for every
                          ; case this handles today.
                          (let ((r (%py-comparison (rest (rest tgt)))))
                            (pair
                              (%py-store (first tgt)
                                (list aug (first tgt) (first r)))
                              (rest r)))))))))))))))))

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
(def %py-for
  (fn (_ toks)
    (let ((v (if (null? toks) () (first toks))))
      (if (not (eq? (%py-tag v) (lit tok-name)))
        (Err raise (lit syntax) "expected a name after for" ())
        (if (not (%py-name-is? (if (null? (rest toks)) () (first (rest toks))) "in"))
          (Err raise (lit syntax) "expected in after a for target" ())
          (let ((it (%py-comparison (rest (rest toks)))))
            (let ((b (%py-block (rest it))))
              (pair
                (list
                  (list (lit fn) (list (lit self) (lit %py-items))
                    (list (lit if) (list (lit null?) (lit %py-items))
                      ()
                      (list (lit %seq)
                        (list (lit set!) (%py-name->sym (%py-val v))
                          (list (lit first) (lit %py-items)))
                        (list (lit %seq) (first b)
                          (list (lit self) (list (lit rest) (lit %py-items)))))))
                  (list (lit %py-iter-elems) (first it)))
                (rest b)))))))))

(def %py-store
  (fn (_ target value)
    (if (pair? target)
      (if (eq? (first target) (lit %py-index))
        (list (lit %py-setindex) (first (rest target))
              (first (rest (rest target))) value)
        (Err raise (lit syntax) "cannot assign to this target" ()))
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
            (let ((c (%py-comparison (rest t))))
              (let ((b (%py-block (rest c))))
                (let ((e (%py-else (rest b))))
                  (pair (list (lit if) (first c) (first b) (first e)) (rest e)))))
            (pair () t)))))))

; `def NAME ( params ) : BLOCK`
(def %py-params
  (fn (self toks acc)
    (if (%py-op-is? (if (null? toks) () (first toks)) ")")
      (pair (List reverse acc) (rest toks))
      (let ((t (first toks)))
        (if (eq? (%py-tag t) (lit tok-name))
          (let ((more (rest toks)))
            (if (%py-op-is? (if (null? more) () (first more)) ",")
              (self (rest more) (pair (%py-name->sym (%py-val t)) acc))
              (self more (pair (%py-name->sym (%py-val t)) acc))))
          (Err raise (lit syntax) "expected a parameter name" t))))))

(def %py-def
  (fn (_ toks)
    (let ((name (first toks)))
      (if (not (eq? (%py-tag name) (lit tok-name)))
        (Err raise (lit syntax) "expected a function name after def" name)
        (if (not (%py-op-is? (if (null? (rest toks)) () (first (rest toks))) "("))
          (Err raise (lit syntax) "expected ( after a function name" ())
          (let ((p (%py-params (rest (rest toks)) ())))
            (let ((b (%py-block (rest p))))
              ; A FUNCTION'S ASSIGNMENTS ARE ITS OWN.  The module-level scan
              ; skips def bodies, so their targets are hoisted HERE instead --
              ; inside the fn, where x's `def` binds locally because the frame
              ; is the function's.  Parameters are already bound and are not
              ; re-declared; shadowing them with a nil would break every call.
              (let ((span (%py-take
                            (- (%py-count (rest p)) (%py-count (rest b)))
                            (rest p))))
                (let ((locals (%py-minus
                                (%py-dedupe () (%py-assign-targets span ()) ())
                                (first p))))
                  ; `let`, NOT `def`.  x's `def` decides global-versus-local by
                  ; save-stack depth, and inside a called function TCO can leave
                  ; that stack empty -- so `(def x ())` in a body binds
                  ; GLOBALLY, clobbering the module's `x` with nil on every
                  ; call.  Measured: a def merely PRESENT left the module name
                  ; alone; calling it set the name to nil.
                  ;
                  ; `let` binds in the frame unconditionally, which is what a
                  ; function-local is.  A body with no locals gets no wrapper.
                  (pair
                    ; The body runs inside call/cc so `return` has somewhere to
                    ; jump to, and ends in () so a function that falls off the
                    ; end answers None -- Python's rule. Without that trailing
                    ; nil the body's last expression would leak out as the
                    ; return value.
                    (list (lit def) (%py-name->sym (%py-val name))
                      (list (lit fn) (pair (lit _) (first p))
                        (list (lit %py-callcc)
                          (list (lit fn) (list (lit _) (lit %py-return))
                            (list (lit %seq)
                              (if (null? locals)
                                (first b)
                                (list (lit let) (%py-lets locals ()) (first b)))
                              ())))))
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
(def %py-skip-def
  (fn (self toks depth)
    (if (null? toks)
      toks
      (let ((g (%py-tag (first toks))))
        (if (eq? g (lit tok-indent))
          (self (rest toks) (+ depth 1))
          (if (eq? g (lit tok-dedent))
            (if (<= depth 1) (rest toks) (self (rest toks) (- depth 1)))
            (self (rest toks) depth)))))))

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
(def %py-mentioned
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (if (eq? (%py-tag t) (lit tok-name))
          (self (rest toks) (pair (%py-val t) acc))
          (self (rest toks) acc))))))

; Every name the program BINDS: assignment targets, def names, parameters.
(def %py-bound-names
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (if (%py-for-target? toks)
          (self (rest (rest toks)) (pair (%py-val (first (rest toks))) acc))
        (if (%py-name-is? t "def")
          ; the def name, then its parameters up to the closing paren
          (let ((n (if (null? (rest toks)) () (first (rest toks)))))
            (self (rest (rest toks))
              (if (eq? (%py-tag n) (lit tok-name)) (pair (%py-val n) acc) acc)))
          (if (if (eq? (%py-tag t) (lit tok-name))
                (%py-assign-op? (if (null? (rest toks)) () (first (rest toks))))
                #f)
            (self (rest toks) (pair (%py-val t) acc))
            (self (rest toks) acc))))))))

(def %py-assign-targets
  (fn (self toks acc)
    (if (null? toks)
      (List reverse acc)
      (let ((t (first toks)))
        (if (%py-for-target? toks)
          (self (rest (rest toks))
            (pair (%py-name->sym (%py-val (first (rest toks)))) acc))
        (if (%py-name-is? t "def")
          (self (%py-skip-def (rest toks) 0) acc)
          (if (if (eq? (%py-tag t) (lit tok-name))
                (%py-assign-op? (if (null? (rest toks)) () (first (rest toks))))
                #f)
            (self (rest toks) (pair (%py-name->sym (%py-val t)) acc))
            (self (rest toks) acc))))))))

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

(def %py-shims
  (fn (self names acc)
    (if (null? names)
      (List reverse acc)
      (self (rest names)
        (pair
          (list (lit def) (%py-name->sym (first names))
            (list (lit fn) (list (lit _))
              (list (lit Err) (lit raise) (list (lit lit) (lit name))
                (Str8 append (Str8 append "name '" (first names))
                  "' is not defined")
                ())))
          acc)))))

(def python-parse
  (fn (_ src)
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
      (if (%py-op-is? (first toks) ")")
        (pair (rest toks) acc)
        (if (eq? (%py-tag (first toks)) (lit tok-name))
          (self (rest toks) (pair (%py-val (first toks)) acc))
          (self (rest toks) acc))))))

(def %py-decls
  (fn (self syms acc)
    (if (null? syms)
      (List reverse acc)
      (self (rest syms) (pair (list (lit def) (first syms) ()) acc)))))

(def %py-append
  (fn (self a b)
    (if (null? a) b (pair (first a) (self (rest a) b)))))
