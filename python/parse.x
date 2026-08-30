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

(def %py-num
  (fn (_ text)
    (first (%py-read-str (Base raw-of %py-sexp-base) (Str8 append text " ")))))

; --- Token helpers -----------------------------------------------------------
(def %py-tag (fn (_ t) (if (null? t) () (first t))))
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
          (pair acc more))))
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
              (if (%py-op-is? t "(")
                (let ((r (%py-comparison (rest toks))))
                  (if (%py-op-is? (if (null? (rest r)) () (first (rest r))) ")")
                    (pair (first r) (rest (rest r)))
                    (Err raise (lit syntax) "expected )" ())))
                (Err raise (lit syntax) "unexpected token in expression" t)))))))))

; A Python name becomes an x symbol, EXCEPT the builtins that have a runtime
; function -- `print` is the only one so far.  A name table rather than a
; rewrite in the parser, so the list is one place.
(def %py-builtins
  (list (list "print" (lit %py-print))))

(def %py-name->sym
  (fn (_ s)
    (def %look
      (fn (self rows)
        (if (null? rows)
          (%py-read-str (Base raw-of %py-sexp-base) (Str8 append s " "))
          (if (Str8 =? s (first (first rows)))
            (first (rest (first rows)))
            (self (rest rows))))))
    (let ((r (%look %py-builtins)))
      (if (pair? r) (first r) r))))

(def python-parse-expr (fn (_ toks) (%py-comparison toks)))

; --- Statements --------------------------------------------------------------
; One slice only: an expression statement, and assignment. Blocks come with the
; suite that needs them.
(def python-parse
  (fn (_ src)
    (def %go
      (fn (self toks acc)
        (if (null? toks)
          (List reverse acc)
          (let ((t (first toks)))
            ; NEWLINE, INDENT and DEDENT between statements are not errors --
            ; they are the structure this slice does not use yet.
            (if (eq? (%py-tag t) (lit tok-newline)) (self (rest toks) acc)
              (if (eq? (%py-tag t) (lit tok-indent)) (self (rest toks) acc)
                (if (eq? (%py-tag t) (lit tok-dedent)) (self (rest toks) acc)
                  ; NAME '=' expr, decided by looking one token ahead.  Only a
                  ; bare name is a target here; subscripts and attributes are
                  ; assignable in Python and are not yet.
                  (if (if (eq? (%py-tag t) (lit tok-name))
                        (%py-op-is? (if (null? (rest toks)) () (first (rest toks))) "=")
                        #f)
                    (let ((r (%py-comparison (rest (rest toks)))))
                      (self (rest r)
                        (pair (list (lit def) (%py-name->sym (%py-val t)) (first r)) acc)))
                    (let ((r (%py-comparison toks)))
                      (self (rest r) (pair (first r) acc)))))))))))
    (%go (python-lex src) ())))
