; # x-python -- Python on x-lang
;
; ## python/runtime.x -- what Python's operators actually mean
;
; @description The functions the parser emits calls to. Python's operators are
;   not x's, so they get their own names rather than a mapping.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY NOT JUST EMIT x's `+`
;
; Because `+` is not the same function. Python's is overloaded across numbers,
; strings, lists and tuples and refuses to mix them -- `1 + "a"` is a TypeError,
; not a coercion -- and `/` always produces a float where x's produces an exact
; rational. A parser that emitted x's operators would be writing a language that
; looks like Python and computes differently, which is the failure mode the lang
; contract calls "a different language wearing the same clothes".
;
; So the parser emits calls to these, and every one of them is a place where a
; Python rule can be stated. Today most of them are thin; that is the point --
; they are named seams, not indirection for its own sake.

(import python/util)
(import python/types)
(import python/format)
(import python/bytes)
(import python/str)

(provide python/runtime
  %py-add %py-sub %py-mul %py-div %py-floordiv %py-mod %py-pow %py-neg
  %py-eq %py-ne %py-lt %py-gt %py-le %py-ge
  %py-print %py-display
  %py-mklist %py-index %py-len %py-list? %py-write %py-getattr %py-setindex
  %py-range %py-iter-elems %py-callcc
  %py-escape %py-wind-push! %py-wind-drop!
  %py-Ellipsis %py-dir %py-cls-bytearray
  %py-raise %py-exc-match %py-exc-match-any
  %py-mkclass %py-setattr %py-super
  %py-str %py-repr-of %py-mklist-of %py-hasattr
  %py-cls-type %py-cls-int %py-cls-float %py-cls-bool %py-cls-str
  %py-cls-list %py-cls-dict %py-cls-tuple %py-cls-NoneType %py-cls-set %py-cls-frozenset
  %py-type-of %py-isinstance %py-truthy %py-slice %py-defg
  %py-exc-Exception %py-exc-ArithmeticError %py-exc-LookupError
  %py-exc-ZeroDivisionError %py-exc-IndexError %py-exc-KeyError
  %py-exc-AttributeError %py-exc-NameError %py-exc-TypeError
  %py-exc-ValueError %py-exc-RuntimeError %py-exc-SyntaxError
  %py-mkdict %py-dict? %py-dget %py-dset
  %py-mktuple %py-tuple? %py-unpack
  %py-pos %py-invert %py-in %py-bitor %py-bitxor %py-bitand
  %py-abs %py-round %py-min %py-max %py-bytearray %py-mkbytes
  %py-cls-complex %py-hash %py-lshift %py-rshift
  %py-NotImplemented %py-exc-StopIteration %py-exc-SystemExit
  %py-splat %py-tuple-of-list %py-fjoin %py-fmtfield %py-format-spec %py-strformat
  %py-chr %py-ord)

; --- Arithmetic --------------------------------------------------------------
; `+` dispatches on the operands, and the string case is not an extra: Python
; spells concatenation with it, and every conformance program that builds a
; message uses it.
; --- The operator protocol ---------------------------------------------------
;
; A USER CLASS TAKES PART IN EVERY OPERATOR through its dunders, and the
; seams below ask for them the way Python does: the left operand's __op__
; first, then the right operand's reflected __rop__, and NotImplemented from
; either means "try the other side".  The check that opens every seam is a
; single %type? call -- no frame, no allocation -- so the common numeric path
; pays nothing for the protocol's existence.
;
; NotImplemented is one unique value; identity is the test, as in Python.
(def %py-NotImplemented (pair (lit %py-NotImplemented) ()))

; ELLIPSIS IS THE OTHER SINGLETON PYTHON SPELLS AS A LITERAL, `...`, and it
; takes the same shape for the same reason: one unique pair, identity the
; test.  Nothing here reads it -- it exists so that a program that passes it
; around, hashes it, or compares it gets the answer Python gives.
(def %py-Ellipsis (pair (lit %py-Ellipsis) ()))

; The bound dunder, or nil.  A method compiles to (fn (_ py-self ...) ...),
; so binding is closing over the object -- the same shape %py-obj-attr uses.
(def %py-dunder
  (fn (_ obj name)
    (let ((m (%py-method-find (%py-obj-class obj) name)))
      (if (null? m) () (%py-bind-method m obj)))))

; One side of a binary dispatch: the dunder's answer, or NotImplemented when
; the operand is not an object or has no such method.
(def %py-side
  (fn (_ x y name)
    (if (%py-obj-is x)
      (let ((m (%py-dunder x name)))
        (if (null? m) %py-NotImplemented (m y)))
      %py-NotImplemented)))

(def %py-binop
  (fn (_ a b name rname opname)
    (let ((r1 (%py-side a b name)))
      (if (not (eq? r1 %py-NotImplemented))
        r1
        (let ((r2 (%py-side b a rname)))
          (if (not (eq? r2 %py-NotImplemented))
            r2
            (Err raise (lit type)
              (Str8 append "unsupported operand type(s) for " opname) ())))))))

; augmented + on a list is list.extend, which takes any iterable -- while
; plain + demands a list.  Python draws that line and the corpus tests it.
; AUGMENTED ASSIGNMENT IS ITS OWN DUNDER FIRST.  Python tries __iop__, which
; may mutate the object and answer itself, and falls back to the ordinary
; binary op -- `a += b` is `a = a.__add__(b)` only when there is no __iadd__.
; One helper takes the name and the fallback, so every op= gets the same rule
; rather than += alone having it.
(def %py-inplace
  (fn (_ name binop a b)
    (if (%py-obj-is a)
      (let ((m (%py-dunder a name)))
        (if (null? m) (binop a b) (m b)))
      (binop a b))))

(def %py-iadd
  (fn (_ a b)
    ; a list grows in place from ANY iterable, which is list.extend's rule
    (if (%py-list? a)
      (%seq (%py-list-set! a (%py-list-cat (%py-list-elems a) (%py-iter-elems b))) a)
      (%py-inplace "__iadd__" %py-add a b))))

(def %py-isub    (fn (_ a b) (%py-inplace "__isub__" %py-sub a b)))
(def %py-imul    (fn (_ a b) (%py-inplace "__imul__" %py-mul a b)))
(def %py-idiv    (fn (_ a b) (%py-inplace "__itruediv__" %py-div a b)))
(def %py-imod    (fn (_ a b) (%py-inplace "__imod__" %py-mod a b)))
(def %py-ibitor  (fn (_ a b) (%py-inplace "__ior__" %py-bitor a b)))
(def %py-ibitand (fn (_ a b) (%py-inplace "__iand__" %py-bitand a b)))
(def %py-ibitxor (fn (_ a b) (%py-inplace "__ixor__" %py-bitxor a b)))
; The three-character forms, once the tokenizer could read them: `//=` `**=`
; `>>=` `<<=` are the same rule, and Python names their dunders after the
; binary op the same way.
(def %py-ifloordiv (fn (_ a b) (%py-inplace "__ifloordiv__" %py-floordiv a b)))
(def %py-ipow      (fn (_ a b) (%py-inplace "__ipow__" %py-pow a b)))
(def %py-ilshift   (fn (_ a b) (%py-inplace "__ilshift__" %py-lshift a b)))
(def %py-irshift   (fn (_ a b) (%py-inplace "__irshift__" %py-rshift a b)))

(def %py-add
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__add__" "__radd__" "+"))
      ((match
         ((%py-view-is a) #t)
         ((%py-view-is b) #t)
         ((%py-dict? a) #t)
         (#t (%py-dict? b)))
        (Err raise (lit type) "unsupported operand type(s) for +" ()))
      ((%py-list? a)
        (if (%py-list? b)
          (%py-list-new (%py-list-cat (%py-list-elems a) (%py-list-elems b)))
          (Err raise (lit type) "can only concatenate list to list" ())))
      ((%py-list? b)
        (Err raise (lit type) "unsupported operand type(s) for +" ()))
      ; THE LEFT OPERAND DECIDES: bytearray + bytes is a bytearray and bytes +
      ; bytearray is a bytes, as in Python -- the buffers concatenate either
      ; way, and only the answer's type is in question.
      ((%py-bytes-is a)
        (if (%py-bytes-is b)
          ((if (%py-barr-is a) %py-barr-new %py-bytes-new)
            (%pb-cat (%py-bytes-list a) (%py-bytes-list b)))
          (Err raise (lit type) "can't concat to bytes" ())))
      ((%py-bytes-is b)
        (Err raise (lit type) "can't concat bytes to non-bytes" ()))
      ((str? a)
        (if (str? b)
          (Str8 append a b)
          (Err raise (lit type) "can only concatenate str to str" ())))
      ((str? b)
        (Err raise (lit type) "unsupported operand type(s) for +" ()))
      ; Lists concatenate through PY-LIST's own `+` op, which the engine
      ; dispatches from here.  Bools are ints here too: 1j + True.
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "+" 0))
      (#t
        (+ (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b)))))))

(def %py-sub
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__sub__" "__rsub__" "-"))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-sub a b))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
          (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "-" 1))
      (#t
        (- (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b)))))))

; THE TYPE HANDLES, EARLY: the arithmetic seams below consult them, and
; %py-f-2p64 is computed through %py-mul at LOAD time -- so these must be
; bound before the first seam runs, not where the constructors that also
; use them happen to live.
(def %py-typeof-prim (prim-ref (lit type) (lit of)))
(def %py-th-int (%py-typeof-prim 1))
(def %py-th-big (%py-typeof-prim 99999999999999999999))
(def %py-th-float (%py-typeof-prim 1.5))
(def %py-th-complex (%py-typeof-prim (Complex make 0.0 1.0)))
(def %py-complex-is
  (fn (_ v) (eq? (%py-typeof-prim v) %py-th-complex)))

; THE COMPLEX BRANCH OF THE FOUR SEAMS.  A complex beside a non-number is a
; TypeError here, not the tower's promotion error -- that one is x's
; teaching raise (#584) and its kind is not `type`, so `except TypeError`
; never saw it and 1j + [] killed the program.  And a bigint beside a
; complex is FLOATED first, as Python does, because the tower declares no
; COMPLEX x BIGINT promotion.  Only the complex case pays: the seams reach
; here after two handle compares, and every other pairing the tower already
; refuses in a kind Python recognises.
(def %py-cx-arith
  (fn (_ a0 b0 op code)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (null? (%py-num-kind a)) #t (null? (%py-num-kind b)))
      (Err raise (lit type)
        (Str8 append "unsupported operand type(s) for " op) ())
      (do
        (def x (if (eq? (%py-typeof-prim a) %py-th-big) (* 1.0 a) a))
        (def y (if (eq? (%py-typeof-prim b) %py-th-big) (* 1.0 b) b))
        (match
          ((= code 0) (+ x y))
          ((= code 1) (- x y))
          ((= code 2) (* x y))
          (#t (/ x y)))))))

; The shifts: ints only, and >> FLOORS for a negative left operand the way
; Python does -- Num quotient truncates, so the floor is stated.
(def %py-lshift
  (fn (_ a0 b0)
    (if (if (%py-obj-is a0) #t (%py-obj-is b0))
      (%py-binop a0 b0 "__lshift__" "__rlshift__" "<<")
    (%py-lshift-num a0 b0))))
(def %py-lshift-num
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
      (if (< b 0)
        (Err raise (lit value) "negative shift count" ())
        (* a (Num expt 2 b)))
      (Err raise (lit type) "unsupported operand type(s) for <<" ()))))
(def %py-rshift
  (fn (_ a0 b0)
    (if (if (%py-obj-is a0) #t (%py-obj-is b0))
      (%py-binop a0 b0 "__rshift__" "__rrshift__" ">>")
    (%py-rshift-num a0 b0))))
(def %py-rshift-num
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
      (if (< b 0)
        (Err raise (lit value) "negative shift count" ())
        (let ((p (Num expt 2 b)))
          (let ((q (Num quotient a p)))
            (if (if (< a 0) (not (= (* q p) a)) #f) (- q 1) q))))
      (Err raise (lit type) "unsupported operand type(s) for >>" ()))))
; STRING REPETITION IS HANDLED HERE, NOT ON THE TYPE.  A type's ops fire when
; either operand carries the type, so pushing `*` onto x's str type would change
; what `*` means for every string in the process, the platform's included.  The
; containers can have ops because they are types this bundle invented; str is
; not, so its Python rules stay behind a `str?` test.
(def %py-str-repeat
  (fn (self s n) (if (<= n 0) "" (Str8 append s (self s (- n 1))))))

(def %py-mul
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__mul__" "__rmul__" "*"))
      ((if (%py-list? a) #t (%py-list? b))
        (let ((l (if (%py-list? a) a b)))
          (let ((k (if (%py-list? a) b a)))
            (if (not (eq? (%py-num-kind (%py-boolnorm k)) (lit int)))
              (Err raise (lit type) "can't multiply sequence by non-int" ())
              (%py-list-new (%py-els-repeat (%py-list-elems l) (%py-boolnorm k) ()))))))
      ((%py-bytes-is a)
        ((if (%py-barr-is a) %py-barr-new %py-bytes-new) (%pb-repeat (%py-bytes-list a) b ())))
      ((%py-bytes-is b)
        ((if (%py-barr-is b) %py-barr-new %py-bytes-new) (%pb-repeat (%py-bytes-list b) a ())))
      ((str? a)
        (if (str? b)
          (Err raise (lit type) "can't multiply sequence by non-int" ())
          (%py-str-repeat a b)))
      ((str? b) (%py-str-repeat b a))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "*" 2))
      (#t
        (* (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b)))))))

; TRUE DIVISION ALWAYS PRODUCES A FLOAT.  `1 / 2` is 0.5 in Python 3 and an
; exact 1/2 in x, and that difference is the reason this bundle declares xenon
; -- float is reachable from the first arithmetic a beginner types.
; DIVISION BY ZERO RAISES.  It answered `inf` for `1 / 0`, `0` for `1 // 0`
; and None for `1 % 0` -- three more silent wrong answers, and the three
; Python spells ZeroDivisionError.  The messages are Python's own, which
; differ between true and floor division.
;
; These raise an Err rather than building an instance, like every other raise
; this runtime makes.  The kind is what `except ZeroDivisionError` matches on;
; see the exception section for why both shapes are caught the same way.
(def %py-div
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__truediv__" "__rtruediv__" "/"))
      ((= b 0) (Err raise (lit zero-division) "division by zero" ()))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
            (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "/" 3))
      (#t (/ (* a 1.0) b)))))

; FLOOR DIVISION OF FLOATS IS A FLOAT: 1.0 // 2 is 0.0 in Python, floor of
; the true quotient, where Num quotient wants exact operands.
; THE SIGNATURE REGISTRY, EARLY: a builtin registers its parameter names
; at LOAD time (min, max, sorted, enumerate), so these four must be
; defined above the first of them, not with the rest of the keyword
; machinery further down.
(def %py-sigs (pair () ()))
(def %py-sig!
  ; The kw name is OPTIONAL so that every existing caller -- the builtins that
  ; register signatures by hand -- keeps working unchanged.
  (fn (_ f name names nreq has-rest . kw)
    (%set-first! %py-sigs
      (pair (pair f (list name names nreq has-rest (if (null? kw) () (first kw))))
        (first %py-sigs)))
    f))

; **kwargs ARRIVES IN A BOX, and it has to: a plain call reaches a function by
; apply, with no keyword machinery in the way, so a dict at the end of the
; argument list would be indistinguishable from an ordinary positional one.
; The box is a pair whose head is this one unique value, which no program can
; produce, so the tail can be read without ambiguity.
(def %py-kwbox-tag (list (lit %py-kwbox)))
(def %py-kwbox (fn (_ d) (pair %py-kwbox-tag d)))
(def %py-kwbox? (fn (_ v) (if (pair? v) (same? (first v) %py-kwbox-tag) #f)))

; The dict a call sent, or an empty one when it sent none -- which is what a
; plain call always looks like.
(def %py-kwargs-of
  (fn (self more)
    (if (null? more)
      (%py-dict-new ())
      (if (null? (rest more))
        (if (%py-kwbox? (first more)) (rest (first more)) (%py-dict-new ()))
        (self (rest more))))))

; The same tail without the box, which is what the positional binders read.
(def %py-args-strip-kw
  (fn (self more)
    (if (null? more)
      ()
      (if (null? (rest more))
        (if (%py-kwbox? (first more)) () more)
        (pair (first more) (self (rest more)))))))
(def %py-dflt (list (lit %py-default)))
(def %py-opt
  (fn (_ more i dflt)
    (if (>= i (%py-length more)) dflt
      (let ((v (List ref i more))) (if (same? v %py-dflt) dflt v)))))
(def %py-floordiv
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__floordiv__" "__rfloordiv__" "//"))
      ((= b 0)
        (Err raise (lit zero-division) "integer division or modulo by zero" ()))
      ((if (%py-complex-is a) #t (%py-complex-is b))
        (Err raise (lit type) "can't take floor of complex number." ()))
      ((if (%py-float-is a) #t (%py-float-is b))
        (Float floor (/ (* a 1.0) b)))
      ; PYTHON FLOORS, `Num quotient` TRUNCATES: -7 // 2 is -4, not -3.
      ; TRUNCATE THEN ADJUST, rather than subtracting a modulo: for a
      ; non-negative numerator this is EXACTLY `Num quotient`, the value
      ; and the representation callers had before floors were fixed.  The
      ; subtracting form handed back a bigint zero under the promoting
      ; lane, and python/format.x's digit loop tests its counter with
      ; eq?, so base conversion span forever and took the CI host with it.
      (#t
        (let ((q (Num quotient a b)))
          (if (if (not (= (- a (* q b)) 0))
                (if (< (- a (* q b)) 0) (> b 0) (< b 0))
                #f)
            (- q 1)
            q))))))
; A STRING ON THE LEFT OF % IS FORMATTING, not arithmetic -- str.__mod__ --
; and the check comes before the zero test because the right operand of a
; format is a tuple as often as a number.
(def %py-mod
  (fn (_ a b)
    ; str.__mod__ answers first: "%d" % obj formats the object, it does not
    ; ask the object for __rmod__
    (match
      ((str? a) (%py-format a b))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__mod__" "__rmod__" "%"))
      ((if (%py-complex-is a) #t (%py-complex-is b))
        (Err raise (lit type) "can't mod complex numbers." ()))
      ((= b 0) (Err raise (lit zero-division) "integer modulo by zero" ()))
      (#t (Num modulo a b)))))
; NEVER HAND Num expt A NEGATIVE EXPONENT.  Its parameter is documented
; "Non-negative integer exponent" and nothing enforces it: with exp < 0 the
; recursion never reaches 0 and SQUARES THE BASE on every even step, so it
; allocates exponentially growing bignums until the machine dies.  Not a hang --
; an unbounded-allocation bomb, and `2 ** -1` is ordinary Python.
;
; Python's answer is a float: 2 ** -1 is 0.5.
; A FLOAT ANYWHERE MAKES IT libm's pow: Num expt squares its way through
; integer exponents and has no answer for 2 ** 0.5, inf or nan.  Python's
; one refusal on this path is 0.0 to a negative power.
; pow(a, b, m): modular exponentiation by squaring, with Python's sign rule
; (the result takes the modulus's sign).
(def %py-powmod
  (fn (_ a b m)
    (if (= m 0)
      (Err raise (lit value) "pow() 3rd argument cannot be 0" ())
      (if (< b 0)
        (Err raise (lit value) "base is not invertible for the given modulus" ())
        (do
          (def go
            (fn (self base e acc)
              (if (= e 0) acc
                (self (Num modulo (* base base) m) (Num quotient e 2)
                  (if (= (Num modulo e 2) 1) (Num modulo (* acc base) m) acc)))))
          (go (Num modulo a m) b (Num modulo 1 m)))))))
(def %py-pow3
  (fn (_ a b . m)
    ; `pow(x, y, None)` IS `pow(x, y)` -- Python says so, and the modulus
    ; arrives here as () either way, so an absent one and an explicit None
    ; are the same question.
    (if (if (null? m) #t (null? (first m)))
      (%py-pow a b)
      (if (if (%py-num? a) (if (%py-num? b) (%py-num? (first m)) #f) #f)
        (%py-powmod (%py-boolnorm a) (%py-boolnorm b) (%py-boolnorm (first m)))
        (Err raise (lit type) "pow() requires integers" ())))))

(def %py-pow
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__pow__" "__rpow__" "** or pow()"))
      ((if (%py-complex-is a) #t (%py-complex-is b))
        (%py-cpow (%py-complex-of a) (%py-complex-of b)))
      ; a negative real base to a fractional power is a COMPLEX in Python 3
      ((if (< (if (eq? a #t) 1 (if (eq? a #f) 0 a)) 0)
          (if (%py-float-is b) (not (= b (Float floor b))) #f)
          #f)
        (%py-cpow (%py-complex-of a) (%py-complex-of b)))
      ((if (%py-float-is a) #t (%py-float-is b))
        (do
          (def fa (* (%py-boolnorm a) 1.0))
          (def fb (* (%py-boolnorm b) 1.0))
          (if (if (= fa 0.0) (< fb 0.0) #f)
            (Err raise (lit zero-division)
              "0.0 cannot be raised to a negative power" ())
            (Float pow fa fb))))
      ((< b 0) (/ 1.0 (Num expt a (- 0 b))))
      (#t (Num expt a b)))))
(def %py-neg
  (fn (_ a)
    (if (%py-obj-is a)
      (let ((m (%py-dunder a "__neg__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary -" ()) (m)))
      (- 0 a))))

; Unary + is a no-op on numbers and a TypeError on everything else; unary ~
; is exact two's complement on integers and a TypeError on floats -- both
; measured refusals in the conformance corpus, not decorations.
(def %py-pos
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__pos__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary +" ()) (m)))
    (let ((w (%py-boolnorm v)))
      (if (null? (%py-num-kind w))
        (Err raise (lit type) "bad operand type for unary +" ())
        w)))))

(def %py-invert
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__invert__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary ~" ()) (m)))
    (let ((w (%py-boolnorm v)))
      (if (eq? (%py-num-kind w) (lit int))
        (- (- 0 w) 1)
        (Err raise (lit type) "bad operand type for unary ~" ()))))))

; True is 1 and False is 0 wherever a number is wanted: comparisons,
; arithmetic seams, formatting.  Python's bool IS an int; x's is not.
(def %py-boolnorm
  (fn (_ v) (if (eq? v #t) 1 (if (eq? v #f) 0 v))))

; --- Bitwise, exact two's complement -----------------------------------------
; The loop walks both operands a bit at a time with FLOOR halving, so a
; negative integer presents its two's-complement bits naturally and
; terminates at the all-zeros or all-ones tail; the tail's contribution is
; -2^k when its bit is set, which is exactly what two's complement says.
; Bigints ride the tower ops.
(def %py-half
  (fn (_ v) (Num quotient (if (< v 0) (- v 1) v) 2)))

(def %py-bit2
  (fn (_ a0 b0 opname fbit)
    (def a (%py-boolnorm a0))
    (def b (%py-boolnorm b0))
    (if (if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
      (do
        (def go
          (fn (self a b pow acc)
            (if (if (if (= a 0) #t (= a (- 0 1))) (if (= b 0) #t (= b (- 0 1))) #f)
              (if (fbit (= a (- 0 1)) (= b (- 0 1))) (- acc pow) acc)
              (self (%py-half a) (%py-half b) (* pow 2)
                (if (fbit (= (- a (* 2 (%py-half a))) 1)
                          (= (- b (* 2 (%py-half b))) 1))
                  (+ acc pow)
                  acc)))))
        (go a b 1 0))
      (Err raise (lit type)
        (Str8 append "unsupported operand type(s) for " opname) ()))))

(def %py-bitor
  (fn (_ a b)
    (match
      ((if (%py-dict? a) (%py-dict? b) #f)
        (let ((d (%py-dict-new (%py-dict-copy (%py-dict-entries a)))))
          (%seq (%py-dict-merge! d b) d)))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-or a b))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__or__" "__ror__" "|"))
      (#t (%py-bit2 a b "|" (fn (_ x y) (if x #t y)))))))
(def %py-bitxor
  (fn (_ a b)
    (if (if (%py-set-is a) #t (%py-set-is b))
      (%py-set-xor a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__xor__" "__rxor__" "^")
      (%py-bit2 a b "^" (fn (_ x y) (if x (not y) y)))))))
(def %py-bitand
  (fn (_ a b)
    (if (if (%py-set-is a) #t (%py-set-is b))
      (%py-set-and a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__and__" "__rand__" "&")
      (%py-bit2 a b "&" (fn (_ x y) (if x y #f)))))))

; --- Membership --------------------------------------------------------------
; `a in b`: substring for strings, element walk with Python's equality for
; the containers, keys for a dict, and a TypeError for anything that cannot
; be iterated -- 1.2 in 3.4 must refuse, not loop.
(def %py-in-walk
  (fn (self a l)
    (if (null? l) #f (if (%py-eq a (first l)) #t (self a (rest l))))))

(def %py-in
  (fn (_ a b)
    (match
      ((%py-obj-is b)
        (let ((m (%py-dunder b "__contains__")))
          (if (null? m)
            (%py-in-walk a (%py-iter-elems b))
            (%py-truthy (m a)))))
      ((%py-bytes-is b)
        (if (%py-bytes-is a)
          (%pb-in? (%py-bytes-list a) (%py-bytes-list b))
          ; AN INT IN A BYTES IS A BYTE VALUE, not a type error: bytes are a
          ; sequence OF ints in Python, so `0 in b"1234"` asks whether any byte
          ; is zero and answers False rather than refusing.
          (if (eq? (%py-num-kind (%py-boolnorm a)) (lit int))
            (%py-in-walk (%py-boolnorm a) (%py-bytes-list b))
            (Err raise (lit type) "a bytes-like object is required" ()))))
      ((str? b)
        (if (str? a)
          (Str8 includes? a b)
          (Err raise (lit type)
            "'in <string>' requires string as left operand" ())))
      ((%py-set-is b) (%py-set-has? a (%py-set-elems b)))
      ((%py-list? b) (%py-in-walk a (%py-list-elems b)))
      ((%py-tuple-is b) (%py-in-walk a (%py-tuple-elems b)))
      ((%py-dict? b)
        (do
          (def keys
            (fn (self es acc)
              (if (null? es) acc (self (rest es) (pair (first (first es)) acc)))))
          (%py-in-walk a (keys (%py-dict-entries b) ()))))
      (#t (Err raise (lit type) "argument is not iterable" ())))))

; --- Numeric builtins --------------------------------------------------------
; abs clears the SIGN BIT for floats (the arithmetic spelling turns -0.0
; into itself); round is the exact-digit machinery at a decimal place, half
; to even, int result without ndigits and float with.
(def %py-abs
  (fn (_ v0)
    (if (%py-obj-is v0)
      (let ((m (%py-dunder v0 "__abs__")))
        (if (null? m) (Err raise (lit type) "bad operand type for abs()" ()) (m)))
    (%py-abs-num v0))))
(def %py-abs-num
  (fn (_ v0)
    (def v (%py-boolnorm v0))
    (match
      ((%py-float-is v) (if (< (first v) 0) (- 0.0 v) v))
      ((%py-complex-is v) (Complex magnitude v))
      ((eq? (%py-num-kind v) (lit int)) (if (< v 0) (- 0 v) v))
      (#t (Err raise (lit type) "bad operand type for abs()" ())))))

; rounding an int to a negative number of digits: half goes to EVEN, so
; round(125, -1) is 120 and round(15, -1) is 20
(def %py-round-int
  (fn (_ v nd)
    (def p (%py-ipow10 (- 0 nd) 1))
    (def q (Num quotient (- v (Num modulo v p)) p))
    (def rr (Num modulo v p))
    (match
      ((> (* rr 2) p) (* (+ q 1) p))
      ((< (* rr 2) p) (* q p))
      ((= (Num modulo q 2) 0) (* q p))
      (#t (* (+ q 1) p)))))
(def %py-ipow10
  (fn (self n acc) (if (= n 0) acc (self (- n 1) (* acc 10)))))

(def %py-round
  (fn (_ . a)
    (def v (%py-boolnorm (first a)))
    (def nd (if (null? (rest a)) () (first (rest a))))
    (if (not (%py-float-is v))
      (if (eq? (%py-num-kind v) (lit int))
        (if (if (null? nd) #f (< (%py-boolnorm nd) 0))
          (%py-round-int v (%py-boolnorm nd))
          v)
        (Err raise (lit type) "type cannot be rounded" ()))
      (do
        (def ex (%py-f-exact v))
        (if (not (eq? (first ex) (lit num)))
          (Err raise (lit value) "cannot round a special float" ())
          (do
            (def sgn (first (rest ex)))
            (def D (first (rest (rest ex))))
            (def x10 (first (rest (rest (rest ex)))))
            (def p (if (null? nd) 0 nd))
            (if (< p 0)
              (Err raise (lit value) "negative round ndigits unsupported" ())
              (let ((f (%py-fmt-fixed D x10 p)))
                (if (null? nd)
                  (let ((n (%py-int-of-str (first f))))
                    (if (Str8 =? sgn "-") (- 0 n) n)
                  )
                  (Float from
                    (Str8 append sgn
                      (if (= p 0)
                        (first f)
                        (Str8 append (first f)
                          (Str8 append "." (rest f)))))))))))))))

(def %py-minmax
  (fn (_ vs pick which)
    (if (null? vs)
      (Err raise (lit value)
        (Str8 append which "() arg is an empty sequence") ())
      (do
        (def go
          (fn (self best l)
            (if (null? l)
              best
              (self (if (pick (first l) best) (first l) best) (rest l)))))
        (go (first vs) (rest vs))))))

; min/max take either several values or one iterable, plus key= and
; default= as keywords -- and a keyword call is recognisable because
; %py-kw-args pads its slots with the %py-dflt sentinel, which no user
; value can be.
(def %py-has-dflt?
  (fn (self l) (if (null? l) #f (if (same? (first l) %py-dflt) #t (self (rest l))))))
(def %py-minmax-call
  (fn (_ a which pick)
    (def key ())
    (def dflt %py-dflt)
    (def vs (if (null? (rest a)) (%py-iter-elems (first a)) a))
    (if (null? vs)
      (if (same? dflt %py-dflt)
        (Err raise (lit value) (Str8 append which "() arg is an empty sequence") ())
        dflt)
      (let ((k (if (null? key) %py-ident key)))
        (%py-minmax-by vs pick k)))))
(def %py-minmax-by
  (fn (_ vs pick key)
    (def go
      (fn (self best bk l)
        (if (null? l) best
          (let ((v (first l)))
            (let ((vk (key v)))
              (if (%py-truthy (pick vk bk)) (self v vk (rest l)) (self best bk (rest l))))))))
    (go (first vs) (key (first vs)) (rest vs))))
(def %py-min (fn (_ . a) (%py-minmax-call a "min" (fn (_ x y) (%py-lt x y)))))
(def %py-max (fn (_ . a) (%py-minmax-call a "max" (fn (_ x y) (%py-gt x y)))))
; the keyword form: every positional is a VALUE (or the one iterable), and
; key=/default= come from the keywords
(def %py-minmax-kw
  (fn (_ f pos kws)
    (def which (if (same? f %py-min) "min" "max"))
    (def pick (if (same? f %py-min) (fn (_ x y) (%py-lt x y)) (fn (_ x y) (%py-gt x y))))
    (def key (let ((e (%py-alist-find "key" kws))) (if (null? e) () (rest e))))
    (def dflt (let ((e (%py-alist-find "default" kws))) (if (null? e) %py-dflt (rest e))))
    (def vs (if (null? (rest pos)) (%py-iter-elems (first pos)) pos))
    (if (null? vs)
      (if (same? dflt %py-dflt)
        (Err raise (lit value) (Str8 append which "() arg is an empty sequence") ())
        dflt)
      (%py-minmax-by vs pick (if (null? key) %py-ident key)))))

; --- Bytes seams -------------------------------------------------------------
(def %py-mkbytes (fn (_ s) (%py-bytes-of-str s)))

; b'...' with Python's escapes: the quote rule of str's repr, \n \r \t by
; name, and every byte outside printable ASCII as \xhh -- which is how a NUL
; shows itself now that one can be here at all: b'\x00'.
(def %py-bytes-repr
  (fn (_ l)
    (let ((q (if (if (%pb-in? (list 39) l) (not (%pb-in? (list 34) l)) #f) 34 39)))
      (Str8 append "b"
        (let ((qs (%py-list->string (list (%py-int->char q)))))
          (Str8 append qs (Str8 append (%py-bytes-repr-go l q "") qs)))))))
(def %py-bytes-repr-go
  (fn (self l q acc)
    (if (null? l) acc
      (let ((c (first l)))
        (self (rest l) q
          (Str8 append acc
            (match
              ((= c 92) "\\\\")
              ((= c q) (Str8 append "\\" (%py-list->string (list (%py-int->char c)))))
              ((= c 10) "\\n")
              ((= c 13) "\\r")
              ((= c 9) "\\t")
              ((if (< c 32) #t (>= c 127)) (Str8 append "\\x" (%py-hex2 c)))
              (#t (%py-list->string (list (%py-int->char c)))))))))))

; BYTES METHODS ARE THE BYTE ALGORITHMS, in python/bytes.x.  They used to be
; the str methods on the underlying string, which is what made a NUL fatal:
; the payload had to be something Str8 would hold.  Now the payload is a byte
; list and these are the doors onto it.
;
; An argument is taken as BYTES whichever way it was written -- bytes or
; bytearray -- and a str argument is Python's TypeError, as it was.
(def %py-b-arg
  (fn (_ a)
    (match
      ((%py-bytes-is a) (%py-bytes-list a))
      ((str? a) (Err raise (lit type) "a bytes-like object is required, not 'str'" ()))
      (#t (Err raise (lit type) "a bytes-like object is required" ())))))

; A NEEDLE MAY BE ONE BYTE WRITTEN AS AN INT.  `b"abc".find(ord("b"))` is
; Python, and only the searching methods take it -- replace and partition
; want a bytes-like and say so.  Reaching %pb-at? with a bare int used to
; walk `first` into a non-pair, which on this engine is a SEGFAULT and took
; the whole spec file with it rather than one case.
(def %py-b-needle
  (fn (_ v)
    (if (%py-num? v)
      (let ((n (%py-boolnorm v)))
        (if (if (< n 0) #t (> n 255))
          (Err raise (lit value) "byte must be in range(0, 256)" ())
          (list n)))
      (%py-b-arg v))))

; start and end, counted from the end when negative and clamped to the value
; -- the slice rules, which is what Python's find/index/count take.
; True is 1 as an index, as it is everywhere else in Python -- and reaching
; `<` with a bare bool is a type error on this engine rather than a coercion.
(def %py-b-clamp
  (fn (_ i0 n)
    (let ((i (%py-boolnorm i0)))
      (let ((k (if (< i 0) (+ n i) i)))
        (if (< k 0) 0 (if (> k n) n k))))))
(def %py-b-start
  (fn (_ l a i)
    (let ((v (%py-b-opt a i ()))) (if (null? v) 0 (%py-b-clamp v (%pb-len l))))))
(def %py-b-end
  (fn (_ l a i)
    (let ((v (%py-b-opt a i ()))) (if (null? v) (%pb-len l) (%py-b-clamp v (%pb-len l))))))

; A SEARCH IS A SEARCH OF THE WINDOW, and the answer is an index into the
; whole -- so the window's start goes back on before it is returned.
(def %py-b-search
  (fn (_ l a rev)
    (let ((s (%py-b-start l a 1)))
      (let ((e (%py-b-end l a 2)))
        (let ((w (%pb-sub l s (- e s))) (n (%py-b-needle (first a))))
          (let ((r (if rev (%pb-rfind w n) (%pb-find w n))))
            (if (< r 0) r (+ r s))))))))
(def %py-b-args
  (fn (self args) (if (null? args) () (pair (%py-b-arg (first args)) (self (rest args))))))
(def %py-b-opt
  (fn (_ args i d)
    (let ((v (%py-nth-or args i ()))) (if (null? v) d v))))
(def %py-nth-or
  (fn (self l i d)
    (if (null? l) d (if (= i 0) (first l) (self (rest l) (- i 1) d)))))

; The parts of a split, wrapped back into the caller's own type.
(def %py-b-parts
  (fn (self mk ps acc)
    (if (null? ps) (%py-list-new (List reverse acc))
      (self mk (rest ps) (pair (mk (first ps)) acc)))))
(def %py-b-triple
  (fn (_ mk t) (%py-tuple-new (list (mk (first t)) (mk (first (rest t))) (mk (first (rest (rest t))))))))

; ONE TABLE, and `mk` is the only thing bytes and bytearray disagree about:
; which of the two a method's answer is made into.
;
; EACH ARM ANSWERS A CLOSURE, so the NAME is resolved when it is asked for
; and not when it is called.  That is what makes `bytes.nosuch` an
; AttributeError at the dot -- which is the shape %py-str-attr already had,
; and which five conformance programs probe with a bare `bytes.count`.
(def %py-b-attr
  (fn (_ l mk name)
    (match
      ((Str8 =? name "decode")   (fn (_ . a) (%pb->str l)))
      ((Str8 =? name "find")     (fn (_ . a) (%py-b-search l a #f)))
      ((Str8 =? name "rfind")    (fn (_ . a) (%py-b-search l a #t)))
      ((Str8 =? name "index")    (fn (_ . a) (%py-b-index (%py-b-search l a #f))))
      ((Str8 =? name "rindex")   (fn (_ . a) (%py-b-index (%py-b-search l a #t))))
      ((Str8 =? name "count")
        (fn (_ . a)
          (let ((s (%py-b-start l a 1)))
            (%pb-count (%pb-sub l s (- (%py-b-end l a 2) s)) (%py-b-needle (first a)) 0))))
      ((Str8 =? name "startswith")
        (fn (_ . a) (%pb-starts? (%pb-drop (%py-b-start l a 1) l) (%py-b-arg (first a)))))
      ((Str8 =? name "endswith")
        (fn (_ . a)
          (let ((s (%py-b-start l a 1)))
            (%pb-ends? (%pb-sub l s (- (%py-b-end l a 2) s)) (%py-b-arg (first a))))))
      ((Str8 =? name "upper")      (fn (_ . a) (mk (%pb-upper l))))
      ((Str8 =? name "lower")      (fn (_ . a) (mk (%pb-lower l))))
      ((Str8 =? name "swapcase")   (fn (_ . a) (mk (%pb-swapcase l))))
      ((Str8 =? name "capitalize") (fn (_ . a) (mk (%pb-capitalize l))))
      ((Str8 =? name "title")      (fn (_ . a) (mk (%pb-title l))))
      ((Str8 =? name "strip")  (fn (_ . a) (mk (%pb-strip l (%py-b-set a) #t #t))))
      ((Str8 =? name "lstrip") (fn (_ . a) (mk (%pb-strip l (%py-b-set a) #t #f))))
      ((Str8 =? name "rstrip") (fn (_ . a) (mk (%pb-strip l (%py-b-set a) #f #t))))
      ((Str8 =? name "split")
        (fn (_ . a) (%py-b-parts mk (%pb-split l (%py-b-split-sep a) (%py-b-opt a 1 (- 0 1))) ())))
      ((Str8 =? name "rsplit")
        (fn (_ . a) (%py-b-parts mk (%pb-rsplit l (%py-b-split-sep a) (%py-b-opt a 1 (- 0 1))) ())))
      ((Str8 =? name "splitlines")
        (fn (_ . a) (%py-b-parts mk (%pb-splitlines l (%py-truthy (%py-b-opt a 0 #f))) ())))
      ((Str8 =? name "join")    (fn (_ . a) (mk (%pb-join l (%py-b-seq (first a))))))
      ((Str8 =? name "replace")
        (fn (_ . a)
          (mk (%pb-replace l (%py-b-arg (first a)) (%py-b-arg (first (rest a)))
                (%py-b-opt a 2 (- 0 1))))))
      ((Str8 =? name "partition")
        (fn (_ . a) (%py-b-triple mk (%pb-partition l (%py-b-sep (first a))))))
      ((Str8 =? name "rpartition")
        (fn (_ . a) (%py-b-triple mk (%pb-rpartition l (%py-b-sep (first a))))))
      ((Str8 =? name "center") (fn (_ . a) (mk (%pb-center l (first a) (%py-b-fill a)))))
      ((Str8 =? name "ljust")  (fn (_ . a) (mk (%pb-ljust l (first a) (%py-b-fill a)))))
      ((Str8 =? name "rjust")  (fn (_ . a) (mk (%pb-rjust l (first a) (%py-b-fill a)))))
      ((Str8 =? name "isspace") (fn (_ . a) (%pb-isspace l)))
      ((Str8 =? name "isalpha") (fn (_ . a) (%pb-isalpha l)))
      ((Str8 =? name "isdigit") (fn (_ . a) (%pb-isdigit l)))
      ((Str8 =? name "isalnum") (fn (_ . a) (%pb-isalnum l)))
      ((Str8 =? name "isupper") (fn (_ . a) (%pb-isupper l)))
      ((Str8 =? name "islower") (fn (_ . a) (%pb-islower l)))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'bytes' object has no attribute '" name) "'") ())))))

; index is find that RAISES, which is the whole difference between them.
(def %py-b-index
  (fn (_ i) (if (< i 0) (Err raise (lit value) "subsection not found" ()) i)))
; a strip set or a separator -- nil for "none given", and an explicit None
; means the same thing: `b"a b".split(None)` splits on whitespace.
(def %py-b-set
  (fn (_ args)
    (if (null? args) ()
      (if (null? (first args)) () (%py-b-arg (first args))))))

; AN EMPTY SEPARATOR IS A ValueError, for split and for partition both --
; there is no sensible place to cut.  An empty NEEDLE is a different question,
; and count answers that one with len+1.
(def %py-b-sep
  (fn (_ v)
    (let ((l (%py-b-arg v)))
      (if (null? l) (Err raise (lit value) "empty separator" ()) l))))

; a split separator: absent or None is whitespace, an empty bytes is the
; ValueError above.
(def %py-b-split-sep
  (fn (_ a)
    (if (null? a) ()
      (if (null? (first a)) () (%py-b-sep (first a))))))
; the pad byte, space unless one was given
(def %py-b-fill
  (fn (_ args)
    (let ((c (%py-b-opt args 1 ()))) (if (null? c) 32 (first c)))))
; the sequence a join walks
(def %py-b-seq
  (fn (self v)
    (%py-b-seq-go (%py-iter-elems v) ())))
(def %py-b-seq-go
  (fn (self l acc)
    (if (null? l) (List reverse acc) (self (rest l) (pair (%py-b-arg (first l)) acc)))))

; bytearray's repr is bytes' repr, said out loud: bytearray(b'foo').
(def %py-barr-repr
  (fn (_ l) (Str8 append "bytearray(" (Str8 append (%py-bytes-repr l) ")"))))

; THE TWO ATTRIBUTE SURFACES, and `mk` is the only thing they disagree about:
; a bytes method answers bytes, a bytearray method answers bytearrays.  Both
; read the same payload and run the same algorithms.
(def %py-bytes-attr
  (fn (_ b name) (%py-b-attr (%py-bytes-list b) %py-bytes-new name)))

; A bytearray also MUTATES, and those two are its own: the payload is
; replaced in the cell, so every name bound to this bytearray sees it.
(def %py-barr-attr
  (fn (_ b name)
    (match
      ((Str8 =? name "append")
        (fn (_ v)
          (%py-barr-set! b
            (%pb-cat (%py-bytes-list b) (%py-bytes-of-codes (list v) ())))))
      ((Str8 =? name "extend")
        (fn (_ v)
          (%py-barr-set! b (%pb-cat (%py-bytes-list b) (%py-barr-bytes-of v)))))
      (#t (%py-b-attr (%py-bytes-list b) %py-barr-new name)))))

; The bytes an argument stands for, whichever way it was written.
; bytearray(), bytearray(b'..'), bytearray('..', 'utf-8'), bytearray([..]),
; bytearray(n).  A str WITHOUT an encoding is Python's TypeError; with one it
; is the string's own bytes.  A count asks for that many zero bytes and now
; gets them.
(def %py-bytearray-ctor
  (fn (_ . args)
    (if (null? args)
      (%py-barr-new ())
      (let ((v (first args)))
        (match
          ((%py-bytes-is v) (%py-barr-new (%py-bytes-list v)))
          ((str? v)
            (if (null? (rest args))
              (Err raise (lit type) "string argument without an encoding" ())
              (%py-barr-of-str v)))
          ((%py-list? v) (%py-barr-new (%py-bytes-of-codes (%py-list-elems v) ())))
          ((%py-tuple-is v) (%py-barr-new (%py-bytes-of-codes (%py-tuple-elems v) ())))
          ((%py-num? v) (%py-barr-new (%py-bytes-zeros v ())))
          (#t (%py-barr-new (%py-bytes-of-codes (%py-iter-elems v) ()))))))))

(def %py-barr-bytes-of
  (fn (_ v)
    (match
      ((%py-bytes-is v) (%py-bytes-list v))
      ((%py-list? v) (%py-bytes-of-codes (%py-list-elems v) ()))
      ((%py-tuple-is v) (%py-bytes-of-codes (%py-tuple-elems v) ()))
      (#t (%py-bytes-of-codes (%py-iter-elems v) ())))))

(def %py-any-bytes?
  (fn (self l) (if (null? l) #f (if (%py-bytes-is (first l)) #t (self (rest l))))))
(def %py-str-method
  (fn (_ s name)
    (let ((m (%py-str-attr s name)))
      (fn (_ . args)
        (if (%py-any-bytes? args)
          (Err raise (lit type) "must be str, not bytes" ())
          (apply m args))))))
; --- Comparison --------------------------------------------------------------
; Class equality is IDENTITY: the builtin type objects are singletons, so
; `type(1) == type(2)` is eq? on the same object, and two distinct classes are
; never equal whatever their names.  And a string never equals a non-string --
; `1 == 'a'` is False in Python, where handing the pair to x's `=` was an error.
; Bools are ints in every comparison: 0.0 == False and True == 1.0 are both
; True in Python, so bool operands normalize before the numeric compare --
; INLINE, with no helper call and no frame: these run once per dict entry
; on every subscript's linear walk, and a per-call allocation here is a
; batch-memory multiplier the CI host measured the hard way.
; COMPARISON DUNDERS ANSWER RAW VALUES, as Python's do -- an __eq__ that
; returns 123 prints 123.  __eq__ reflects onto __eq__ and falls back to
; identity; the default __ne__ is __eq__ inverted unless that answered
; NotImplemented; < > <= >= reflect onto their mirrors and then refuse.
(def %py-cmp2
  (fn (_ a b name rname)
    (let ((r1 (%py-side a b name)))
      (if (not (eq? r1 %py-NotImplemented))
        r1
        (%py-side b a rname)))))

(def %py-ne-side
  (fn (_ x y)
    (if (%py-obj-is x)
      (let ((m (%py-dunder x "__ne__")))
        (if (not (null? m))
          (m y)
          (let ((e (%py-dunder x "__eq__")))
            (if (null? e)
              %py-NotImplemented
              (let ((r (e y)))
                (if (eq? r %py-NotImplemented) r (not (%py-truthy r))))))))
      %py-NotImplemented)))

(def %py-eq
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__eq__" "__eq__")))
          (if (eq? r %py-NotImplemented) (eq? a b) r)))
      ((str? a) (if (str? b) (Str8 =? a b) #f))
      ((str? b) #f)
      ((%py-bytes-is a)
        (if (%py-bytes-is b) (%pb-eq? (%py-bytes-list a) (%py-bytes-list b)) #f))
      ((%py-bytes-is b) #f)
      ((if (%py-fn-is a) #t (%py-fn-is b)) (same? a b))
      ((%py-dict? a)
        (if (%py-dict? b) (%py-dict-eq? (%py-dict-entries a) (%py-dict-entries b)) #f))
      ((%py-dict? b) #f)
      ((%py-set-is a)
        (if (%py-set-is b) (%py-set-eq? (%py-set-elems a) (%py-set-elems b)) #f))
      ((%py-set-is b) #f)
      ((%py-class-is a) (eq? a b))
      ((%py-class-is b) #f)
      ; a BOOL, always: the tower's `=` answers nil for an unequal complex,
      ; and a nil in a printed comparison reads as None
      ((= (if (eq? a #t) 1 (if (eq? a #f) 0 a))
             (if (eq? b #t) 1 (if (eq? b #f) 0 b)))
        #t)
      (#t #f))))
(def %py-ne
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r1 (%py-ne-side a b)))
        (if (not (eq? r1 %py-NotImplemented))
          r1
          (let ((r2 (%py-ne-side b a)))
            (if (not (eq? r2 %py-NotImplemented)) r2 (not (eq? a b))))))
      (not (%py-eq a b)))))

(def %py-ord-refuse
  (fn (_ op)
    (Err raise (lit type)
      (Str8 append (Str8 append "'" op) "' not supported between these instances") ())))

; Strings order lexicographically by code point; the engine's numeric `<`
; has no answer for them.  Self-recursive at top level -- no closure built
; per comparison.
(def %py-strcmp
  (fn (self a b i)
    (if (>= i (Str8 length a))
      (if (>= i (Str8 length b)) 0 (- 0 1))
      (if (>= i (Str8 length b))
        1
        (let ((ca (%py-char-code (%str-ref a i)))
              (cb (%py-char-code (%str-ref b i))))
          (if (< ca cb) (- 0 1) (if (> ca cb) 1 (self a b (+ i 1)))))))))

; Complex has no ordering, and the tower's `<` answers #f for it without a
; word -- so the refusal is stated here, on the handle compare that costs
; nothing per call.
(def %py-cmp-refuse
  (fn (_ a b op)
    (if (if (eq? (%py-typeof-prim a) %py-th-complex) #t
          (eq? (%py-typeof-prim b) %py-th-complex))
      (Err raise (lit type)
        (Str8 append (Str8 append "'" op) "' not supported between complex instances") ())
      ())))

; Lists and tuples order LEXICOGRAPHICALLY, element by element, and a prefix
; is less than what extends it -- Python's rule, and the reason sorting a
; list of tuples works at all.
(def %py-seq-of
  (fn (_ v)
    (if (%py-list? v) (%py-list-elems v)
      (if (%py-tuple-is v) (%py-tuple-elems v) ()))))
(def %py-seq? (fn (_ v) (if (%py-list? v) #t (%py-tuple-is v))))
(def %py-seq-cmp
  (fn (self a b)
    (match
      ((null? a) (if (null? b) 0 (- 0 1)))
      ((null? b) 1)
      ((%py-truthy (%py-eq (first a) (first b))) (self (rest a) (rest b)))
      ((%py-truthy (%py-lt (first a) (first b))) (- 0 1))
      (#t 1))))

(def %py-lt
  (fn (_ a b)
    (match
      ((if (%py-seq? a) (%py-seq? b) #f)
        (< (%py-seq-cmp (%py-seq-of a) (%py-seq-of b)) 0))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b "<"))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (< (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__lt__" "__gt__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse "<") r)))
      (#t (%py-lt-num a b)))))
(def %py-lt-num
  (fn (_ a b)
    (%py-cmp-refuse a b "<")
    (if (if (str? a) (str? b) #f)
      (< (%py-strcmp a b 0) 0)
      (< (if (eq? a #t) 1 (if (eq? a #f) 0 a))
         (if (eq? b #t) 1 (if (eq? b #f) 0 b))))))
(def %py-gt
  (fn (_ a b)
    (match
      ((if (%py-seq? a) (%py-seq? b) #f)
        (> (%py-seq-cmp (%py-seq-of a) (%py-seq-of b)) 0))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b ">"))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (> (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__gt__" "__lt__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse ">") r)))
      (#t (%py-gt-num a b)))))
(def %py-gt-num
  (fn (_ a b)
    (%py-cmp-refuse a b ">")
    (if (if (str? a) (str? b) #f)
      (> (%py-strcmp a b 0) 0)
      (> (if (eq? a #t) 1 (if (eq? a #f) 0 a))
         (if (eq? b #t) 1 (if (eq? b #f) 0 b))))))
(def %py-le
  (fn (_ a b)
    (match
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b "<="))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (<= (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__le__" "__ge__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse "<=") r)))
      ((if (str? a) (str? b) #f) (<= (%py-strcmp a b 0) 0))
      ((%py-lt a b) #t)
      (#t (%py-eq a b)))))
(def %py-ge
  (fn (_ a b)
    (match
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b ">="))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (>= (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__ge__" "__le__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse ">=") r)))
      ((if (str? a) (str? b) #f) (>= (%py-strcmp a b 0) 0))
      ((%py-gt a b) #t)
      (#t (%py-eq a b)))))

; --- Lists ------------------------------------------------------------------
;
; TAGGED, not a bare x list.  An empty Python list and None are different
; values, and a bare x list would make both of them nil -- so `print([])` would
; print None.  A list is (py-list . elements): the tag distinguishes it from
; every other value this runtime produces, and from nil.
(def %py-mklist (fn (_ . elems) (%py-list-new elems)))

; A SUBCLASS OF list IS A list wherever the runtime asks.  The question every
; list operation asks is this one, so teaching it about the wrapper is what
; makes `class mylist(list)` index, slice, grow, compare and print -- the
; accessors in types.x read through to the value the instance carries.
(def %py-list?
  (fn (_ v)
    (if (%py-list-is v)
      #t
      (if (%py-obj-is v) (%py-list-is (%py-obj-native v)) #f))))

(def %py-len
  (fn (_ v)
    (match
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__len__")))
          (if (null? m) (Err raise (lit type) "object of this type has no len()" ()) (m))))
      ((%py-dict? v) (%py-length (%py-dict-entries v)))
      ((%py-tuple-is v) (%py-length (%py-tuple-elems v)))
      ((%py-list? v) (%py-length (%py-list-elems v)))
      ((%py-set-is v) (%py-length (%py-set-elems v)))
      ((%py-view-is v) (%py-length (%py-view-elems v)))
      ((str? v) (Str length v))
      ((%py-bytes-is v) (%pb-len (%py-bytes-list v)))
      (#t (Err raise (lit type) "object of this type has no len()" ())))))

; NEGATIVE INDICES COUNT FROM THE END, which is Python and not x.  -1 is the
; last element, and an index past either end raises IndexError rather than
; returning nil -- a silent nil would propagate into arithmetic and surface far
; from the subscript that produced it.
(def %py-index
  (fn (_ v i)
    (match
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__getitem__")))
          (if (null? m) (Err raise (lit type) "object is not subscriptable" ()) (m i))))
      ((str? v)
        (let ((n (Str length v)))
          (let ((k (if (< i 0) (+ n i) i)))
            (if (if (< k 0) #t (>= k n))
              (Err raise (lit index) "string index out of range" ())
              (Str sub k 1 v)))))
      ; a bytes index is the byte's value, an int
      ((%py-bytes-is v)
        (let ((l (%py-bytes-list v)))
          (let ((n (%pb-len l)))
            (let ((k (if (< i 0) (+ n i) i)))
              (if (if (< k 0) #t (>= k n))
                (Err raise (lit index) "index out of range" ())
                (%pb-ref l k))))))
      ; Subscripting a tuple and a dict are calls too -- see the list branch.
      ((%py-tuple-is v) (v i))
      ((%py-dict? v) (v i))
      ((not (%py-list? v))
        (Err raise (lit type) "object is not subscriptable" ()))
      ; SUBSCRIPTING A LIST IS A CALL.  x dispatches `(v i)` through the type's
      ; `call` handler, so negative indices and IndexError are stated once in
      ; python/types.x rather than copied here.
      (#t (v i)))))

; Store into a list at an index.  Rebuilds the element list and hangs it back on
; the SAME tag pair, so every reference sees the store -- the identity argument
; that made append work.
(def %py-set-nth
  (fn (self lst k v)
    (if (= k 0)
      (pair v (rest lst))
      (pair (first lst) (self (rest lst) (- k 1) v)))))

; --- del and slice assignment ------------------------------------------------
(def %py-delindex
  (fn (_ v i)
    ; __delitem__ was the one of the three item methods nothing dispatched:
    ; __getitem__ and __setitem__ were already here, so `del c[k]` on a class
    ; that defines it raised as though the class had said nothing.
    (match
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__delitem__")))
          (if (null? m)
            (Err raise (lit type) "object does not support item deletion" ())
            (m i))))
      ((%py-dict? v) (%py-ddel v i))
      ((%py-list? v) ((%py-list-attr v "__delitem__") i))
      (#t (Err raise (lit type) "object does not support item deletion" ())))))
; the indices a slice selects, as (lo . hi) on a step of 1
(def %py-slice-span
  (fn (_ n start stop step)
    (if (if (null? step) #f (not (= (%py-boolnorm step) 1)))
      (Err raise (lit value) "only a step of 1 is supported here" ())
      (pair (%py-list-clamp n start 0) (%py-list-clamp n stop n)))))
(def %py-setslice
  (fn (_ v start stop step new)
    (if (not (%py-list? v))
      (Err raise (lit type) "object does not support slice assignment" ())
      (let ((els (%py-list-elems v)))
        (let ((sp (%py-slice-span (%py-length els) start stop step)))
          (let ((lo (first sp)))
            (let ((hi (if (< (rest sp) lo) lo (rest sp))))
              (%py-list-set! v
                (%py-list-cat (%py-take lo els)
                  (%py-list-cat (%py-iter-elems new) (%py-drop els hi)))))))))))
(def %py-delslice
  (fn (_ v start stop step)
    (%py-setslice v start stop step (%py-list-new ()))))

(def %py-setindex
  (fn (_ obj i v)
    (match
      ((%py-obj-is obj)
        (let ((m (%py-dunder obj "__setitem__")))
          (if (null? m)
            (Err raise (lit type) "object does not support item assignment" ())
            (m i v))))
      ((%py-dict? obj) (%py-dset obj i v))
      ((not (%py-list? obj))
        (Err raise (lit type) "object does not support item assignment" ()))
      (#t
        (let ((n (%py-length (%py-list-elems obj))))
          (let ((k (if (< i 0) (+ n i) i)))
            (if (if (< k 0) #t (>= k n))
              (Err raise (lit index) "list assignment index out of range" ())
              (%py-list-set! obj (%py-set-nth (%py-list-elems obj) k v)))))))))

; The escape continuation a `return` invokes.  Fetched rather than assumed
; global, the way every other prim in this bundle is reached.
(def %py-callcc (prim-ref (lit ctrl) (lit call/cc)))

; --- Unwinding on the way out ------------------------------------------------
;
; `return`, `break` and `continue` escape through that continuation, and the
; engine's call/cc restores the C stack straight past any `guard` standing
; between the jump and its binder.  So a `finally` -- and a `with`'s __exit__ --
; between the two never ran: the cleanup was owed and the escape walked out
; without paying it.
;
; A WIND STACK settles the debt.  A block that owes cleanup pushes a thunk for
; the duration of its body and drops it again on the way out; an escape runs
; everything the jump is about to skip, innermost first, before it jumps.
;
; The shape is x-r5rs's dynamic-wind (r5rs/scm/control.scm) over this same
; stack-copying call/cc, with the two differences Python asks for:
;
;   * ESCAPES ONLY TRAVEL OUTWARD.  `return`, `break` and `continue` are
;     one-shot and never re-entered, so the stack an escape was captured with
;     is always a tail of the one it is invoked with -- there is an exit walk
;     and no matching enter walk.
;
;   * A `yield` IS A SUSPENSION, NOT AN EXIT.  Python does not run a finally
;     when a generator yields through one; it runs it when the body is resumed
;     and leaves the block for good.  So generators keep the RAW call/cc and
;     swap the whole stack at the boundary (%py-gen-resume), which leaves a
;     suspended body's cleanup owed rather than paying it early.
;
; The stack is a cell holding a list of thunks, innermost first.  It is O(the
; nesting depth of blocks owing cleanup), never O(iterations): a loop pushes
; and drops the same one entry each time round.
(def %py-winds (pair () ()))

; The pushed node IS the token to drop it by -- dropping restores exactly what
; was underneath, so an unbalanced push in between cannot strand the stack.
(def %py-wind-push!
  (fn (_ after)
    (%seq (%set-first! %py-winds (pair after (first %py-winds)))
      (first %py-winds))))

(def %py-wind-drop! (fn (_ node) (%seq (%set-first! %py-winds (rest node)) ())))

; Run what the jump would skip, back down to the stack the escape was captured
; with.  Each entry is dropped BEFORE its thunk runs, so a cleanup that escapes
; again -- a `return` inside a `finally` -- cannot meet itself coming back.
(def %py-wind-unwind!
  (fn (self target)
    (let ((cur (first %py-winds)))
      (match
        ((same? cur target) ())
        ; the target is not below us: nothing sane left to run, so restore the
        ; stack rather than paying debts that are not ours
        ((null? cur) (%seq (%set-first! %py-winds target) ()))
        (#t
          (%seq (%set-first! %py-winds (rest cur))
            (%seq ((first cur)) (self target))))))))

; call/cc for an escape: the continuation it hands the body settles the wind
; stack back to what it was here before it jumps.
(def %py-escape
  (fn (_ body)
    (let ((saved (first %py-winds)))
      (%py-callcc
        (fn (_ k)
          (body (fn (_ v) (%seq (%py-wind-unwind! saved) (k v)))))))))

; --- Iteration ---------------------------------------------------------------
;
; The elements a `for` walks.  A list gives its own; a string gives its
; characters, because Python iterates a string by character and several
; conformance programs depend on it.
(def %py-str-chars
  (fn (self v i n)
    (if (>= i n) () (pair (Str8 sub i 1 v) (self v (+ i 1) n)))))

; AN OBJECT ITERATES BY ITS PROTOCOL: __iter__ hands back an iterator whose
; __next__ is called until it raises StopIteration -- materialized here into
; the element list every consumer already walks.  Without __iter__, the old
; sequence protocol: __getitem__ from 0 until IndexError.
(def %py-obj-elems
  (fn (_ v)
    (let ((it-m (%py-dunder v "__iter__")))
      (if (not (null? it-m))
        (let ((it (it-m)))
          (let ((nx (if (%py-obj-is it) (%py-dunder it "__next__") ())))
            (if (null? nx)
              (if (%py-obj-is it)
                (Err raise (lit type) "iter() returned non-iterator" ())
                (%py-iter-elems it))
              (do
                (def go
                  (fn (self acc)
                    (let ((r (guard (e (if (%py-exc-match e %py-exc-StopIteration)
                                            %py-NotImplemented
                                            (error e)))
                                (nx))))
                      (if (eq? r %py-NotImplemented)
                        (%py-reverse acc)
                        (self (pair r acc))))))
                (go ())))))
        (let ((gi (%py-dunder v "__getitem__")))
          (if (null? gi)
            (Err raise (lit type) "object is not iterable" ())
            (do
              (def go
                (fn (self i acc)
                  (let ((r (guard (e (if (%py-exc-match e %py-exc-IndexError)
                                          %py-NotImplemented
                                          (error e)))
                              (gi i))))
                    (if (eq? r %py-NotImplemented)
                      (%py-reverse acc)
                      (self (+ i 1) (pair r acc))))))
              (go 0 ()))))))))

(def %py-iter-elems
  (fn (_ v)
    (match
      ((%py-obj-is v) (%py-obj-elems v))
      ; Iterating a dict yields its KEYS, as in Python.
      ((%py-dict? v) (%py-dkeys (%py-dict-entries v)))
      ((%py-tuple-is v) (%py-tuple-elems v))
      ((%py-list? v) (%py-list-elems v))
      ((%py-set-is v) (%py-set-elems v))
      ((%py-view-is v) (%py-view-elems v))
      ((str? v) (%py-str-chars v 0 (Str8 length v)))
      ; iterating bytes yields ints
      ((%py-bytes-is v)
        (%py-bytes-list v))
      ; a generator runs to its end; every consumer here wants the whole list
      ((%py-gen-is v) (%py-gen-drain v ()))
      (#t (Err raise (lit type) "object is not iterable" ())))))

; range(stop) / range(start, stop) / range(start, stop, step)
;
; EAGER, and that is a simplification with a known cost: Python 3's range is
; lazy, so `range(10000000)` is free there and a ten-million element list here.
; Every conformance program that uses range walks all of it, so the difference
; is memory rather than answers -- but it is a difference, and it is written
; down rather than discovered.
;
; A zero step raises rather than looping forever.  There is no depth limit on
; non-tail calls here (x-lang#56), so an unbounded loop is an OOM.
(def %py-range-build
  (fn (self i stop step acc)
    (if (if (> step 0) (>= i stop) (<= i stop))
      (%py-reverse acc)
      (self (+ i step) stop step (pair i acc)))))

(def %py-range
  (fn (_ . args)
    (if (null? args)
      (Err raise (lit type) "range expected at least 1 argument" ())
      (let ((start (if (null? (rest args)) 0 (first args)))
            (stop  (if (null? (rest args)) (first args) (first (rest args))))
            (step  (if (null? (rest args)) 1
                     (if (null? (rest (rest args))) 1
                       (first (rest (rest args)))))))
        (if (= step 0)
          (Err raise (lit value) "range() arg 3 must not be zero" ())
          (%py-list-new (%py-range-build start stop step ())))))))

; --- Dicts -------------------------------------------------------------------
;
; ENTRIES IN INSERTION ORDER, not a hash table. x/type/dict.x is a content-hashed
; mutable table and would be faster, but Python 3.7+ preserves insertion order
; and the conformance suite compares PRINTED output -- so the order is part of
; the answer, not an implementation detail. An association list keeps it for
; free; lookup is O(n), which is the right trade at this size.
;
; The representation is python/types.x's PY-DICT; what is here is what the
; parser calls and what Python's rules say.
(def %py-dict? (fn (_ v) (%py-dict-is v)))

(def %py-mkdict
  (fn (_ . entries)
    (def check (fn (self es) (if (null? es) () (%seq (%py-check-hashable! (first (first es))) (self (rest es))))))
    (check entries)
    (%py-dict-new entries)))

(def %py-dfind
  (fn (self k entries)
    (if (null? entries)
      ()
      (if (%py-eq k (first (first entries)))
        (first entries)
        (self k (rest entries))))))

(def %py-dget
  (fn (_ d k)
    (let ((e (%py-dfind k (%py-dict-entries d))))
      (if (null? e)
        ; a real instance, so `except KeyError as e: e.args` works
        (error (%py-instantiate %py-exc-KeyError (list k)))
        (rest e)))))

(def %py-dappend
  (fn (self entries e)
    (if (null? entries) (list e) (pair (first entries) (self (rest entries) e)))))

(def %py-dset
  (fn (_ d k v)
    (let ((e (%py-dfind k (%py-dict-entries d))))
      (if (null? e)
        ; A new key goes on the END: insertion order is the printed order.
        (%py-dict-set! d (%py-dappend (%py-dict-entries d) (pair k v)))
        (%seq (%set-rest! e v) ())))))

(def %py-dkeys (fn (self entries) (if (null? entries) () (pair (first (first entries)) (self (rest entries))))))
(def %py-dvals (fn (self entries) (if (null? entries) () (pair (rest (first entries)) (self (rest entries))))))

; --- The list method surface -------------------------------------------------
(def %py-els-repeat
  (fn (self l k acc) (if (<= k 0) acc (self l (- k 1) (%py-list-cat acc l)))))
(def %py-els-drop-at
  (fn (self l i) (if (null? l) () (if (= i 0) (rest l) (pair (first l) (self (rest l) (- i 1)))))))
(def %py-els-insert-at
  (fn (self l i v) (if (= i 0) (pair v l) (if (null? l) (list v) (pair (first l) (self (rest l) (- i 1) v))))))
(def %py-els-set-at
  (fn (self l i v) (if (null? l) () (if (= i 0) (pair v (rest l)) (pair (first l) (self (rest l) (- i 1) v))))))
(def %py-els-index
  (fn (self l i stop v)
    (match
      ((null? l) (- 0 1))
      ((>= i stop) (- 0 1))
      ((%py-truthy (%py-eq v (first l))) i)
      (#t (self (rest l) (+ i 1) stop v)))))
(def %py-els-count
  (fn (self l v acc)
    (if (null? l) acc (self (rest l) v (if (%py-truthy (%py-eq v (first l))) (+ acc 1) acc)))))
(def %py-list-kw-names
  (fn (_ name) (if (Str8 =? name "sort") (list "key" "reverse") ())))
(def %py-list-norm-i
  (fn (_ n i) (let ((k (%py-boolnorm i))) (if (< k 0) (+ n k) k))))
(def %py-list-clamp
  (fn (_ n v dflt)
    (let ((x (if (null? v) dflt (%py-boolnorm v))))
      (if (< x 0) (let ((w (+ n x))) (if (< w 0) 0 w)) (if (> x n) n x)))))

(def %py-list-attr
  (fn (_ obj name)
    (let ((els (%py-list-elems obj)))
      (let ((n (%py-length els)))
        (match
          ((Str8 =? name "append")
            (fn (_ v) (%py-list-set! obj (%py-append-elem (%py-list-elems obj) v))))
          ((Str8 =? name "extend")
            (fn (_ it) (%py-list-set! obj (%py-list-cat (%py-list-elems obj) (%py-iter-elems it)))))
          ((Str8 =? name "insert")
            (fn (_ i v) (%py-list-set! obj (%py-els-insert-at (%py-list-elems obj) (%py-list-clamp n i 0) v))))
          ((Str8 =? name "sort")
            (fn (_ . a)
              (let ((key (%py-opt a 0 ())))
                (let ((rev (%py-opt a 1 #f)))
                  (let ((l (%py-msort-by (%py-list-elems obj) (if (null? key) %py-ident key))))
                    (%py-list-set! obj (if (%py-truthy rev) (%py-reverse l) l)))))))
          ((Str8 =? name "reverse")
            (fn (_) (%py-list-set! obj (%py-reverse (%py-list-elems obj)))))
          ((Str8 =? name "clear") (fn (_) (%py-list-set! obj ())))
          ((Str8 =? name "copy")
            (fn (_) (%py-list-new (%py-list-elems obj))))
          ((Str8 =? name "count")
            (fn (_ v) (%py-els-count (%py-list-elems obj) v 0)))
          ((Str8 =? name "index")
            (fn (_ v . a)
              (let ((lo (%py-list-clamp n (%py-s-arg a 0) 0)))
                (let ((hi (%py-list-clamp n (%py-s-arg a 1) n)))
                  (let ((i (%py-els-index (%py-drop els lo) lo hi v)))
                    (if (< i 0)
                      (error (%py-instantiate %py-exc-ValueError (list (Str8 append (%py-repr-of v) " is not in list"))))
                      i))))))
          ((Str8 =? name "remove")
            (fn (_ v)
              (let ((i (%py-els-index (%py-list-elems obj) 0 n v)))
                (if (< i 0)
                  (error (%py-instantiate %py-exc-ValueError (list "list.remove(x): x not in list")))
                  (%py-list-set! obj (%py-els-drop-at (%py-list-elems obj) i))))))
          ((Str8 =? name "pop")
            (fn (_ . a)
              (if (= n 0)
                (Err raise (lit index) "pop from empty list" ())
                (let ((i (if (null? a) (- n 1) (%py-list-norm-i n (first a)))))
                  (if (if (< i 0) #t (>= i n))
                    (Err raise (lit index) "pop index out of range" ())
                    (let ((v (List ref i (%py-list-elems obj))))
                      (%seq (%py-list-set! obj (%py-els-drop-at (%py-list-elems obj) i)) v)))))))
          ((Str8 =? name "__getitem__") (fn (_ i) (%py-index obj i)))
          ((Str8 =? name "__setitem__")
            (fn (_ i v) (%py-list-set! obj (%py-els-set-at (%py-list-elems obj) (%py-list-norm-i n i) v))))
          ((Str8 =? name "__delitem__")
            (fn (_ i) (%py-list-set! obj (%py-els-drop-at (%py-list-elems obj) (%py-list-norm-i n i)))))
          (#t
            (Err raise (lit attribute)
              (Str8 append (Str8 append "'list' object has no attribute '" name) "'") ())))))))

; --- Dict helpers ------------------------------------------------------------
(def %py-ditems
  (fn (self es)
    (if (null? es) () (pair (%py-tuple-new (list (first (first es)) (rest (first es)))) (self (rest es))))))
(def %py-dict-drop
  (fn (self es k)
    (if (null? es) ()
      (if (%py-truthy (%py-eq k (first (first es))))
        (self (rest es) k)
        (pair (first es) (self (rest es) k))))))
(def %py-pairs-of
  (fn (self vs acc)
    (if (null? vs) (%py-reverse acc)
      (let ((kv (%py-iter-elems (first vs))))
        (if (not (= (%py-length kv) 2))
          (error (%py-instantiate %py-exc-ValueError
            (list (Str8 append
                    (Str8 append "dictionary update sequence element has length "
                      (%py-str (%py-length kv)))
                    "; 2 is required"))))
          (self (rest vs) (pair (pair (first kv) (first (rest kv))) acc)))))))
(def %py-dict-merge!
  (fn (_ d o)
    (let ((rows (if (%py-dict? o) (%py-dict-copy (%py-dict-entries o)) (%py-pairs-of (%py-iter-elems o) ()))))
      (let ((put (fn (self l) (if (null? l) () (%seq (%py-dset d (first (first l)) (rest (first l))) (self (rest l)))))))
        (put rows)))))
(def %py-ddel
  (fn (_ d k)
    (if (null? (%py-dfind k (%py-dict-entries d)))
      (error (%py-instantiate %py-exc-KeyError (list k)))
      (%py-dict-set! d (%py-dict-drop (%py-dict-entries d) k)))))
(def %py-dict-fromkeys
  (fn (_ it . v)
    (let ((val (if (null? v) () (first v))))
      (let ((go (fn (self ks acc) (if (null? ks) (%py-reverse acc) (self (rest ks) (pair (pair (first ks) val) acc))))))
        (%py-dict-new (go (%py-iter-elems it) ()))))))

(def %py-dict-attr
  (fn (_ d name)
    (match
      ((Str8 =? name "keys")
        (fn (_) (%py-view-new "dict_keys" (%py-dkeys (%py-dict-entries d)))))
      ((Str8 =? name "values")
        (fn (_) (%py-view-new "dict_values" (%py-dvals (%py-dict-entries d)))))
      ((Str8 =? name "items")
        (fn (_) (%py-view-new "dict_items" (%py-ditems (%py-dict-entries d)))))
      ((Str8 =? name "get")
        (fn (_ k . dflt)
          (let ((e (%py-dfind k (%py-dict-entries d))))
            (if (null? e) (if (null? dflt) () (first dflt)) (rest e)))))
      ((Str8 =? name "setdefault")
        (fn (_ k . dflt)
          (let ((e (%py-dfind k (%py-dict-entries d))))
            (if (not (null? e))
              (rest e)
              (let ((v (if (null? dflt) () (first dflt))))
                (%seq (%py-dset d k v) v))))))
      ((Str8 =? name "pop")
        (fn (_ k . dflt)
          (let ((e (%py-dfind k (%py-dict-entries d))))
            (if (null? e)
              (if (null? dflt) (error (%py-instantiate %py-exc-KeyError (list k))) (first dflt))
              (%seq (%py-dict-set! d (%py-dict-drop (%py-dict-entries d) k)) (rest e))))))
      ((Str8 =? name "popitem")
        (fn (_)
          (let ((rows (%py-dict-entries d)))
            (if (null? rows)
              (error (%py-instantiate %py-exc-KeyError (list "popitem(): dictionary is empty")))
              (let ((last (List ref (- (%py-length rows) 1) rows)))
                (%seq (%py-dict-set! d (%py-drop-last rows))
                  (%py-tuple-new (list (first last) (rest last)))))))))
      ((Str8 =? name "update")
        (fn (_ . a) (if (null? a) () (%py-dict-merge! d (first a)))))
      ((Str8 =? name "clear") (fn (_) (%py-dict-set! d ())))
      ((Str8 =? name "copy")
        (fn (_) (%py-dict-new (%py-dict-copy (%py-dict-entries d)))))
      ((Str8 =? name "__contains__")
        (fn (_ k) (not (null? (%py-dfind k (%py-dict-entries d))))))
      ((Str8 =? name "__getitem__") (fn (_ k) (%py-dget d k)))
      ((Str8 =? name "__setitem__") (fn (_ k v) (%py-dset d k v)))
      ((Str8 =? name "__delitem__") (fn (_ k) (%py-ddel d k)))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'dict' object has no attribute '" name) "'")
          ())))))

; --- Attributes and methods --------------------------------------------------
;
; `x.append` is a VALUE, not just a call form.  Python binds the receiver at
; attribute-access time -- `f = x.append; f(4)` appends to x -- so getattr
; returns a closure over the object rather than the parser emitting a
; three-argument call. That costs one closure per access and buys the bound
; method for free.
;
; MUTATION IS IN PLACE, and the tag pair is what makes it possible. A list is
; (py-list . elements); %set-rest! replaces the elements on THAT pair, so every
; reference to the list sees the change. Rebuilding and returning a new list
; would make `x.append(5)` silently do nothing to x, which is the bug this
; representation was chosen to avoid.
(def %py-append-elem
  (fn (self lst v)
    (if (null? lst) (list v) (pair (first lst) (self (rest lst) v)))))

(def %py-getattr
  (fn (_ obj name)
    ; AN INSTANCE IS ASKED FIRST.  It used to be asked after the builtin
    ; types, which was harmless while no instance could BE one -- a subclass
    ; of list would have gone to the list surface and lost its own methods
    ; and its own attributes.
    (match
      ((%py-obj-is obj) (%py-obj-attr obj name))
      ((%py-list? obj) (%py-list-attr obj name))
      ((%py-dict? obj) (%py-dict-attr obj name))
      ((str? obj) (%py-str-method obj name))
      ((%py-barr-is obj) (%py-barr-attr obj name))
      ((%py-bytes-is obj) (%py-bytes-attr obj name))
      ((%py-set-is obj) (%py-set-attr obj name))
      ((%py-gen-is obj) (%py-gen-attr obj name))
      ((%py-super-is obj) (%py-super-attr obj name))
      ((%py-class-is obj) (%py-class-attr obj name))
      ((%py-complex-is obj)
        (match
          ((Str8 =? name "real") (%py-cre obj))
          ((Str8 =? name "imag") (%py-cim obj))
          ((Str8 =? name "conjugate")
            (fn (_) (Complex make (%py-cre obj) (- 0.0 (%py-cim obj)))))
          (#t
            (Err raise (lit attribute)
              (Str8 append (Str8 append "'complex' object has no attribute '" name) "'") ()))))
      (#t
        (let ((sig (%py-sig-of obj)))
          (if (if (null? sig) #f (Str8 =? name "__name__"))
            (first sig)
            (Err raise (lit attribute)
              (Str8 append (Str8 append "object has no attribute '" name) "'")())))))))

; str.upper is the method as a function of its receiver -- str.upper("abc")
; -- and a user class's attribute is its function, unbound, callable with an
; explicit self.  A builtin class other than str has no such surface yet.

; A class's own alist, as dict rows -- minus the "%ctor" key, which is this
; runtime's own and which no Python identifier can spell.
(def %py-class-rows
  (fn (self cls)
    ((fn (go rows)
       (if (null? rows) ()
         (if (Str8 =? (first (first rows)) "%ctor")
           (go (rest rows))
           (pair (pair (first (first rows)) (rest (first rows))) (go (rest rows))))))
     (%py-class-methods cls))))

; AN UNBOUND METHOD IS THE ATTRIBUTE ASKED OF A RECEIVER, with the receiver
; given as the first argument instead of standing to the left of the dot --
; `bytes.count(b"aa", b"a")` is `b"aa".count(b"a")`.
;
; The EMPTY receiver is what makes `bytes.nosuch` an AttributeError here
; rather than at the eventual call: every %py-*-attr raises while looking the
; name up, so looking it up once against a value of the right kind asks the
; question without needing one of the caller's.  It is also what a `try:
; bytes.count / except AttributeError` guard is asking, and five conformance
; programs open with exactly that.
(def %py-unbound
  (fn (_ attr empty name)
    (do (attr empty name)
        (fn (_ recv . args) (apply (attr recv name) args)))))

(def %py-class-attr
  (fn (_ cls name)
    ; THE THREE A CLASS ANSWERS ABOUT ITSELF COME FIRST, and they have to:
    ; the dict and str branches below answer for their INSTANCES' surface, so
    ; asking either for __name__ used to reach `str.nosuch` and report that a
    ; 'str' object has no attribute __name__ -- when what was asked was the
    ; name of the class itself, which `type(x).__name__` asks constantly.
    (match
      ((Str8 =? name "__name__") (%py-class-name cls))
      ((Str8 =? name "__bases__") (%py-tuple-of-list (%py-class-bases cls)))
      ((Str8 =? name "__dict__") (%py-dict-new (%py-class-rows cls)))
      ; dict.fromkeys is a CLASSMETHOD: it answers a new dict, so it hangs
      ; off the class rather than an instance
      ((eq? cls %py-cls-dict)
        (if (Str8 =? name "fromkeys")
          %py-dict-fromkeys
          (%py-class-walk cls name)))
      (#t (%py-class-walk cls name)))))

; THE CLASS'S OWN METHODS ARE ASKED FIRST, and the builtin instance surface
; only afterwards.  Both halves matter.  A builtin type object really does
; carry methods -- `%py-bytes-methods` and friends give list, bytes and the
; rest their __len__, __getitem__ and __init__ -- and those are what a
; subclass inherits, so an arm that answered from the instance surface first
; SHADOWED them: `list.__init__` stopped being the class's and started being
; the AttributeError `%py-list-attr` raises for a name no list instance has.
; Measured as a regression in 71-native-subclass, which is the file that
; exists to notice exactly this.
(def %py-class-walk
  (fn (_ cls name)
    (let ((m (%py-method-find cls name)))
      (if (null? m)
          (%py-class-unbound cls name)
            ; FROM THE CLASS there is no instance to bind: a staticmethod
            ; is its function, a classmethod binds THIS class -- which is
            ; what makes `cls` the child in `Sub.method()` -- and a
            ; property stays the descriptor, since `C.v` in Python is the
            ; property object, not a value it has no instance to compute.
            (if (%py-desc-is m)
              (let ((f (%py-desc-fn m)) (k (%py-desc-kind m)))
                (if (eq? k (lit static))
                  f
                  (if (eq? k (lit classmethod))
                    (%py-bind-method f cls)
                    m)))
              m)))))

; What a builtin type offers beyond the methods on its class object: the
; whole instance surface, unbound.  A class this does not know, or a name
; none of them has, is the AttributeError it always was.
(def %py-class-unbound
  (fn (_ cls name)
    (match
      ((eq? cls %py-cls-str)       (%py-unbound %py-str-attr "" name))
      ((eq? cls %py-cls-bytes)     (%py-unbound %py-bytes-attr (%py-bytes-new ()) name))
      ((eq? cls %py-cls-bytearray) (%py-unbound %py-barr-attr (%py-barr-new ()) name))
      ((eq? cls %py-cls-list)      (%py-unbound %py-list-attr (%py-list-new ()) name))
      ((eq? cls %py-cls-dict)      (%py-unbound %py-dict-attr (%py-dict-new ()) name))
      ((eq? cls %py-cls-set)       (%py-unbound %py-set-attr (%py-set-new #f ()) name))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "type object '" (%py-class-name cls))
            (Str8 append "' has no attribute '" (Str8 append name "'"))) ())))))

; STRING METHODS MAP ONTO Str8, WHICH ALREADY HAS THEM -- upcase, downcase,
; trim, split, join, replace, starts?, ends?, index-of. The work here is the
; SHAPE, not the algorithm: Str8 takes its subject LAST, Python takes it first
; as the receiver, and split/join cross the list boundary so their results have
; to be tagged or untagged on the way through.
;
; find() returns -1 when absent, which is Python's contract and the reason it is
; not index() -- that one raises. Only find is here.
; --- Python's str methods ----------------------------------------------------
;
; Byte-indexed on Str8, which is right for the ASCII the corpus speaks and
; wrong for a multibyte character under a ranged method -- stated, not hidden.
; Ranges follow Python's slice clamping (None, negatives, past-the-end);
; index/rindex raise ValueError where find/rfind answer -1.

(def %py-s-ws?
  (fn (_ c) (match
              ((= c 32) #t)
              ((= c 9) #t)
              ((= c 10) #t)
              ((= c 13) #t)
              ((= c 11) #t)
              (#t (= c 12)))))
(def %py-s-code (fn (_ s i) (%py-char-code (%str-ref s i))))

; (lo . hi) for a start/end pair the way a slice clamps them.
(def %py-s-range
  (fn (_ n start end)
    (def clamp
      (fn (_ v0 dflt)
        (def v (if (eq? v0 #t) 1 (if (eq? v0 #f) 0 v0)))
        (if (null? v) dflt
          (let ((w (if (< v 0) (+ n v) v)))
            (if (< w 0) 0 (if (> w n) n w))))))
    (pair (clamp start 0) (clamp end n))))
; A start past the end finds nothing, even an empty substring -- Python
; answers -1 there where a clamped start would answer len.
(def %py-s-start-past?
  (fn (_ n start0)
    (def start (if (eq? start0 #t) 1 (if (eq? start0 #f) 0 start0)))
    (if (null? start) #f
      (let ((w (if (< start 0) (+ n start) start))) (> w n)))))

; First index of sub in s within [lo, hi), or -1.
(def %py-s-find
  (fn (_ s sub lo hi)
    (def m (Str8 length sub))
    (def go
      (fn (self i)
        (if (> (+ i m) hi) (- 0 1)
          (if (Str8 =? (Str8 sub i m s) sub) i (self (+ i 1))))))
    (if (> lo hi) (- 0 1) (go lo))))
(def %py-s-rfind
  (fn (_ s sub lo hi)
    (def m (Str8 length sub))
    (def go
      (fn (self i)
        (if (< i lo) (- 0 1)
          (if (Str8 =? (Str8 sub i m s) sub) i (self (- i 1))))))
    (if (> lo hi) (- 0 1) (go (- hi m)))))

(def %py-s-count
  (fn (_ s sub lo hi)
    (def m (Str8 length sub))
    (if (= m 0)
      (if (> lo hi) 0 (+ (- hi lo) 1))
      (do
        (def go
          (fn (self i acc)
            (let ((k (%py-s-find s sub i hi)))
              (if (< k 0) acc (self (+ k m) (+ acc 1))))))
        (go lo 0)))))

(def %py-s-strip
  (fn (_ s chars left right)
    (def n (Str8 length s))
    (def in?
      (fn (_ c)
        (if (null? chars)
          (%py-s-ws? c)
          (Str8 includes? (%py-cp->str c) chars))))
    (def lo (if left (do (def go (fn (self i) (if (if (< i n) (in? (%py-s-code s i)) #f) (self (+ i 1)) i))) (go 0)) 0))
    (def hi (if right (do (def go (fn (self i) (if (if (> i lo) (in? (%py-s-code s (- i 1))) #f) (self (- i 1)) i))) (go n)) n))
    (Str8 sub lo (- hi lo) s)))

; Whitespace split: runs of whitespace separate, none kept, maxsplit honoured.
(def %py-s-wsplit
  (fn (_ s maxsplit)
    (def n (Str8 length s))
    (def skip (fn (self i) (if (if (< i n) (%py-s-ws? (%py-s-code s i)) #f) (self (+ i 1)) i)))
    (def word (fn (self i) (if (if (< i n) (not (%py-s-ws? (%py-s-code s i))) #f) (self (+ i 1)) i)))
    (def go
      (fn (self i k acc)
        (let ((st (skip i)))
          (if (>= st n)
            (%py-reverse acc)
            (if (if (>= maxsplit 0) (>= k maxsplit) #f)
              ; the remainder is kept verbatim, trailing whitespace and all
              (%py-reverse (pair (Str8 sub st (- n st) s) acc))
              (let ((e (word st)))
                (self e (+ k 1) (pair (Str8 sub st (- e st) s) acc))))))))
    (go 0 0 ())))

(def %py-s-sepsplit
  (fn (_ s sep maxsplit)
    (def n (Str8 length s))
    (def m (Str8 length sep))
    (def go
      (fn (self i k acc)
        (let ((j (if (if (>= maxsplit 0) (>= k maxsplit) #f) (- 0 1) (%py-s-find s sep i n))))
          (if (< j 0)
            (%py-reverse (pair (Str8 sub i (- n i) s) acc))
            (self (+ j m) (+ k 1) (pair (Str8 sub i (- j i) s) acc))))))
    (if (= m 0) (Err raise (lit value) "empty separator" ()) (go 0 0 ()))))

; rsplit: split from the right; without a separator, whitespace from the right.
(def %py-s-rsepsplit
  (fn (_ s sep maxsplit)
    (def n (Str8 length s))
    (def m (Str8 length sep))
    (def go
      (fn (self hi k acc)
        (let ((j (if (if (>= maxsplit 0) (>= k maxsplit) #f) (- 0 1) (%py-s-rfind s sep 0 hi))))
          (if (< j 0)
            (pair (Str8 sub 0 hi s) acc)
            (self j (+ k 1) (pair (Str8 sub (+ j m) (- hi (+ j m)) s) acc))))))
    (if (= m 0) (Err raise (lit value) "empty separator" ()) (go n 0 ()))))
(def %py-s-rwsplit
  (fn (_ s maxsplit)
    (def n (Str8 length s))
    (def back (fn (self i) (if (if (> i 0) (%py-s-ws? (%py-s-code s (- i 1))) #f) (self (- i 1)) i)))
    (def wordb (fn (self i) (if (if (> i 0) (not (%py-s-ws? (%py-s-code s (- i 1)))) #f) (self (- i 1)) i)))
    (def go
      (fn (self hi k acc)
        (let ((e (back hi)))
          (if (<= e 0)
            acc
            (if (if (>= maxsplit 0) (>= k maxsplit) #f)
              (pair (Str8 sub 0 e s) acc)
              (let ((st (wordb e)))
                (self st (+ k 1) (pair (Str8 sub st (- e st) s) acc))))))))
    (go n 0 ())))

(def %py-s-splitlines
  (fn (_ s keep)
    (def n (Str8 length s))
    (def go
      (fn (self i st acc)
        (if (>= i n)
          (%py-reverse (if (> i st) (pair (Str8 sub st (- i st) s) acc) acc))
          (let ((c (%py-s-code s i)))
            (if (if (= c 10) #t (= c 13))
              (let ((w (if (if (= c 13) (if (< (+ i 1) n) (= (%py-s-code s (+ i 1)) 10) #f) #f) 2 1)))
                (self (+ i w) (+ i w)
                  (pair (Str8 sub st (- (+ i (if keep w 0)) st) s) acc)))
              (self (+ i 1) st acc))))))
    (go 0 0 ())))

(def %py-s-all?
  (fn (_ s pred)
    (def n (Str8 length s))
    (def go (fn (self i) (if (>= i n) #t (if (pred (%py-s-code s i)) (self (+ i 1)) #f))))
    (if (= n 0) #f (go 0))))
(def %py-s-upper? (fn (_ c) (if (>= c 65) (<= c 90) #f)))
(def %py-s-lower? (fn (_ c) (if (>= c 97) (<= c 122) #f)))
(def %py-s-alpha? (fn (_ c) (if (%py-s-upper? c) #t (%py-s-lower? c))))
(def %py-s-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))
(def %py-s-any? (fn (_ s pred) (not (%py-s-all? s (fn (_ c) (not (pred c)))))))

(def %py-s-map
  (fn (_ s f)
    (def n (Str8 length s))
    (def go (fn (self i acc) (if (>= i n) acc (self (+ i 1) (Str8 append acc (%py-cp->str (f (%py-s-code s i) i)))))))
    (go 0 "")))

; CPython's centring: the extra character goes on the RIGHT when width is
; odd relative to the string, which the marg & width & 1 term encodes.
(def %py-s-center
  (fn (_ s width fill)
    (def n (Str8 length s))
    (if (<= width n) s
      (let ((marg (- width n)))
        (let ((left (+ (Num quotient marg 2) (%py-bitand marg (%py-bitand width 1)))))
          (Str8 append (%py-s-rep fill left) (Str8 append s (%py-s-rep fill (- marg left)))))))))
(def %py-s-rep (fn (self f k) (if (<= k 0) "" (Str8 append f (self f (- k 1))))))

(def %py-s-arg (fn (_ a i) (if (> (%py-length a) i) (List ref i a) ())))

(def %py-s-subs
  (fn (_ v) (if (%py-tuple-is v) (%py-tuple-elems v) (list v))))

(def %py-str-attr
  (fn (_ s name)
    (def n (Str8 length s))
    (match
      ((Str8 =? name "upper") (fn (_) (Str8 upcase s)))
      ((Str8 =? name "lower") (fn (_) (Str8 downcase s)))
      ((Str8 =? name "strip")
        (fn (_ . a) (%py-s-strip s (%py-s-arg a 0) #t #t)))
      ((Str8 =? name "lstrip")
        (fn (_ . a) (%py-s-strip s (%py-s-arg a 0) #t #f)))
      ((Str8 =? name "rstrip")
        (fn (_ . a) (%py-s-strip s (%py-s-arg a 0) #f #t)))
      ((Str8 =? name "split")
        (fn (_ . a)
          (let ((sep (%py-s-arg a 0)) (mx (let ((m (%py-s-arg a 1))) (if (null? m) (- 0 1) m))))
            (%py-list-new (if (null? sep) (%py-s-wsplit s mx) (%py-s-sepsplit s sep mx))))))
      ((Str8 =? name "rsplit")
        (fn (_ . a)
          (let ((sep (%py-s-arg a 0)) (mx (let ((m (%py-s-arg a 1))) (if (null? m) (- 0 1) m))))
            (%py-list-new (if (null? sep) (%py-s-rwsplit s mx) (%py-s-rsepsplit s sep mx))))))
      ((Str8 =? name "splitlines")
        (fn (_ . a) (%py-list-new (%py-s-splitlines s (if (null? a) #f (%py-truthy (first a)))))))
      ((Str8 =? name "join")
        (fn (_ it)
          (if (not (match
                     ((%py-list? it) #t)
                     ((%py-tuple-is it) #t)
                     ((str? it) #t)
                     ((%py-dict? it) #t)
                     ((%py-obj-is it) #t)
                     (#t (%py-gen-is it))))
            (Err raise (lit type) "can only join an iterable of str" ())
            (let ((es (%py-iter-elems it)))
              (def all-str (fn (self l) (if (null? l) #t (if (str? (first l)) (self (rest l)) #f))))
              (if (all-str es)
                (Str8 join s es)
                (Err raise (lit type) "can only join an iterable of str" ()))))))
      ((Str8 =? name "replace")
        (fn (_ old new . a)
          (if (not (str? old))
            (Err raise (lit type) "replace() argument 1 must be str" ())
            (if (not (str? new))
              (Err raise (lit type) "replace() argument 2 must be str" ())
              ()))
          (let ((cnt (let ((c (%py-s-arg a 0))) (if (null? c) (- 0 1) c))))
            (if (= (Str8 length old) 0)
              ; empty old: new before every character and after the last, count
              ; permitting -- "A".replace("", "1") is 1A1 and "" gives one
              (do
                (def go
                  (fn (self cs k acc)
                    (let ((ins (if (if (>= cnt 0) (>= k cnt) #f) "" new)))
                      (if (null? cs)
                        (Str8 append acc ins)
                        (self (rest cs) (+ k 1) (Str8 append (Str8 append acc ins) (first cs)))))))
                (go (%py-str-chars s 0 n) 0 ""))
              (do
                (def go
                  (fn (self i k acc)
                    (let ((j (if (if (>= cnt 0) (>= k cnt) #f) (- 0 1) (%py-s-find s old i n))))
                      (if (< j 0)
                        (Str8 append acc (Str8 sub i (- n i) s))
                        (self (+ j (Str8 length old)) (+ k 1)
                          (Str8 append acc (Str8 append (Str8 sub i (- j i) s) new)))))))
                (go 0 0 ""))))))
      ((if (Str8 =? name "startswith") #t (Str8 =? name "endswith"))
        (fn (_ sub . a)
          (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
            (def lo (first r))
            (def hi (rest r))
            (def one
              (fn (_ p)
                (let ((m (Str8 length p)))
                  (if (> (+ lo m) hi) #f
                    (if (Str8 =? name "startswith")
                      (Str8 =? (Str8 sub lo m s) p)
                      (Str8 =? (Str8 sub (- hi m) m s) p))))))
            (def any (fn (self ps) (if (null? ps) #f (if (one (first ps)) #t (self (rest ps))))))
            (any (%py-s-subs sub)))))
      ((if (Str8 =? name "find") #t (Str8 =? name "index"))
        (fn (_ sub . a)
          (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
            (let ((k (if (%py-s-start-past? n (%py-s-arg a 0)) (- 0 1) (%py-s-find s sub (first r) (rest r)))))
              (if (if (< k 0) (Str8 =? name "index") #f)
                (Err raise (lit value) "substring not found" ())
                k)))))
      ((if (Str8 =? name "rfind") #t (Str8 =? name "rindex"))
        (fn (_ sub . a)
          (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
            (let ((k (if (%py-s-start-past? n (%py-s-arg a 0)) (- 0 1) (%py-s-rfind s sub (first r) (rest r)))))
              (if (if (< k 0) (Str8 =? name "rindex") #f)
                (Err raise (lit value) "substring not found" ())
                k)))))
      ((Str8 =? name "count")
        (fn (_ sub . a)
          (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
            (if (%py-s-start-past? n (%py-s-arg a 0)) 0 (%py-s-count s sub (first r) (rest r))))))
      ((if (Str8 =? name "partition") #t (Str8 =? name "rpartition"))
        (fn (_ sep)
          (if (not (str? sep))
            (Err raise (lit type) "must be str, not int" ())
            (if (= (Str8 length sep) 0)
              (Err raise (lit value) "empty separator" ())
              ()))
          (let ((k (if (Str8 =? name "partition") (%py-s-find s sep 0 n) (%py-s-rfind s sep 0 n))))
            (if (< k 0)
              (if (Str8 =? name "partition") (%py-tuple-new (list s "" "")) (%py-tuple-new (list "" "" s)))
              (%py-tuple-new (list (Str8 sub 0 k s) sep
                (Str8 sub (+ k (Str8 length sep)) (- n (+ k (Str8 length sep))) s)))))))
      ((if (Str8 =? name "center") #t (if (Str8 =? name "ljust") #t (Str8 =? name "rjust")))
        (fn (_ width . a)
          (let ((f (let ((x (%py-s-arg a 0))) (if (null? x) " " x))))
            (match
              ((Str8 =? name "center") (%py-s-center s width f))
              ((<= width n) s)
              ((Str8 =? name "ljust")
                (Str8 append s (%py-s-rep f (- width n))))
              (#t (Str8 append (%py-s-rep f (- width n)) s))))))
      ((Str8 =? name "isspace") (fn (_) (%py-s-all? s %py-s-ws?)))
      ((Str8 =? name "isalpha") (fn (_) (%py-s-all? s %py-s-alpha?)))
      ((Str8 =? name "isdigit") (fn (_) (%py-s-all? s %py-s-digit?)))
      ((Str8 =? name "isalnum")
        (fn (_) (%py-s-all? s (fn (_ c) (if (%py-s-alpha? c) #t (%py-s-digit? c))))))
      ((Str8 =? name "isupper")
        (fn (_) (if (%py-s-any? s %py-s-upper?) (not (%py-s-any? s %py-s-lower?)) #f)))
      ((Str8 =? name "islower")
        (fn (_) (if (%py-s-any? s %py-s-lower?) (not (%py-s-any? s %py-s-upper?)) #f)))
      ((Str8 =? name "swapcase")
        (fn (_) (%py-s-map s (fn (_ c i) (if (%py-s-upper? c) (+ c 32) (if (%py-s-lower? c) (- c 32) c))))))
      ((Str8 =? name "capitalize")
        (fn (_) (%py-s-map s (fn (_ c i) (if (= i 0) (if (%py-s-lower? c) (- c 32) c) (if (%py-s-upper? c) (+ c 32) c))))))
      ((Str8 =? name "title")
        (fn (_)
          (%py-s-map s
            (fn (_ c i)
              (let ((prev-alpha (if (= i 0) #f (%py-s-alpha? (%py-s-code s (- i 1))))))
                (if prev-alpha
                  (if (%py-s-upper? c) (+ c 32) c)
                  (if (%py-s-lower? c) (- c 32) c)))))))
      ((Str8 =? name "format") (fn (_ . args) (%py-strformat s args)))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'str' object has no attribute '" name) "'")
          ())))))

; chr() and ord(): the engine's int->char door and the char->int one, with
; the one-character string built the way the tokenizer builds strings.
;
; chr(0) REFUSES, and so does every other spelling of a NUL -- the literals in
; python/tokens.x, and bytes() below.  A string here is a C string by an engine
; guarantee, so the one-character string chr(0) would answer measures zero and
; disappears into the next append: 'a' + chr(0) + 'b' was 'ab' with nothing
; said.  docs/nul-and-the-string-layer.md is the reason this is where
; it stops rather than where a fix starts.  %c goes through here too
; (python/format.x), and so does an f-string's {chr(0)}.
(def %py-int->char (prim-ref (lit int) (lit ->char)))
(def %py-chr
  (fn (_ n0)
    (def n (%py-boolnorm n0))
    (match
      ((not (eq? (%py-num-kind n) (lit int)))
        (Err raise (lit type) "an integer is required" ()))
      ((if (< n 0) #t (> n 1114111))
        (Err raise (lit value) "chr() arg not in range(0x110000)" ()))
      ((= n 0)
        (Err raise (lit value) "a NUL byte is not representable here" ()))
      (#t (%py-list->string (list (%py-int->char n)))))))
; ord() counts CODE POINTS, not bytes: chr(955) is a two-byte string that
; is one character, so the utf-8-aware Str class measures and indexes it.
(def %py-ord
  (fn (_ s)
    (if (if (str? s) (= (Str length s) 1) #f)
      (%py-char-code (Str ref 0 s))
      ; a one-byte bytes answers that BYTE's value, so ord(b'\xff') is 255
      (if (if (%py-bytes-is s) (= (%pb-len (%py-bytes-list s)) 1) #f)
        (%pb-ref (%py-bytes-list s) 0)
        (Err raise (lit type) "ord() expected a character" ())))))

; --- The format-spec mini-language -------------------------------------------
;
; [[fill]align][sign][#][0][width][,][.precision][type], shared by str.format
; and f-strings.  The numeric bodies are the %-operator's, on the exact
; digits (python/format.x); what differs here is the framing -- fill and
; alignment, = for sign-aware padding, thousands grouping, the % type, and
; the empty type's rules.  Every unknown type is Python's ValueError.
(def %py-spec-code (fn (_ s i) (%py-char-code (%str-ref s i))))

; The parsed spec, as a list: (fill align sign alt zero width comma prec type)
(def %py-spec-parse
  (fn (_ spec)
    (def n (Str8 length spec))
    (def align? (fn (_ c) (match
                            ((= c 60) #t)
                            ((= c 62) #t)
                            ((= c 94) #t)
                            (#t (= c 61)))))
    ; fill+align if the SECOND char is an align char, else align alone
    (def i0 0)
    (def fill " ")
    (def align ())
    (if (if (>= n 2) (align? (%py-spec-code spec 1)) #f)
      (do (set! fill (Str8 sub 0 1 spec))
          (set! align (Str8 sub 1 1 spec))
          (set! i0 2))
      (if (if (>= n 1) (align? (%py-spec-code spec 0)) #f)
        (do (set! align (Str8 sub 0 1 spec)) (set! i0 1))
        ()))
    (def i i0)
    (def sign "")
    (if (if (< i n) (let ((c (%py-spec-code spec i))) (if (= c 43) #t (if (= c 45) #t (= c 32)))) #f)
      (do (set! sign (Str8 sub i 1 spec)) (set! i (+ i 1))) ())
    (def alt #f)
    (if (if (< i n) (= (%py-spec-code spec i) 35) #f)
      (do (set! alt #t) (set! i (+ i 1))) ())
    (def zero #f)
    (if (if (< i n) (= (%py-spec-code spec i) 48) #f)
      (do (set! zero #t) (set! i (+ i 1))) ())
    (def num
      (fn (self j acc)
        (if (if (< j n) (%py-fmt-digit? (%py-spec-code spec j)) #f)
          (self (+ j 1) (+ (* acc 10) (- (%py-spec-code spec j) 48)))
          (pair j acc))))
    (def w (num i 0))
    (def width (if (= (first w) i) () (rest w)))
    (set! i (first w))
    (def comma #f)
    (if (if (< i n) (= (%py-spec-code spec i) 44) #f)
      (do (set! comma #t) (set! i (+ i 1)))
      (if (if (< i n) (= (%py-spec-code spec i) 95) #f)
        (do (set! comma (lit under)) (set! i (+ i 1)))
        ()))
    (if (if (< i n) (if (= (%py-spec-code spec i) 44) #t (= (%py-spec-code spec i) 95)) #f)
      (Err raise (lit value) "Cannot specify both ',' and '_'." ())
      ())
    (def prec ())
    (if (if (< i n) (= (%py-spec-code spec i) 46) #f)
      (let ((p (num (+ i 1) 0)))
        (if (= (first p) (+ i 1))
          (Err raise (lit value) "Format specifier missing precision" ())
          (do (set! prec (rest p)) (set! i (first p)))))
      ())
    (def type (if (< i n) (Str8 sub i 1 spec) ""))
    (if (< (+ i 1) n)
      (Err raise (lit value) "Invalid format specifier" ())
      (list fill align sign alt zero width comma prec type))))

(def %py-spec-pad
  (fn (_ s width fill align default-align sgn)
    ; sgn is a sign already split off for = alignment; s is the body
    (def total (+ (Str8 length sgn) (Str8 length s)))
    (def a (if (null? align) default-align align))
    (def rep (fn (self k) (if (<= k 0) "" (Str8 append fill (self (- k 1))))))
    (if (if (null? width) #t (>= total width))
      (Str8 append sgn s)
      (let ((padn (- width total)))
        (match
          ((Str8 =? a "<") (Str8 append (Str8 append sgn s) (rep padn)))
          ((Str8 =? a ">") (Str8 append (rep padn) (Str8 append sgn s)))
          ((Str8 =? a "=") (Str8 append sgn (Str8 append (rep padn) s)))
          ; ^ centres, the extra space on the right
          (#t
            (let ((l (Num quotient padn 2)))
              (Str8 append (rep l) (Str8 append (Str8 append sgn s) (rep (- padn l)))))))))))

; Thousands grouping on a digit string.
(def %py-group3
  (fn (_ ds)
    (def n (Str8 length ds))
    (def go
      (fn (self i acc)
        (if (<= i 0)
          acc
          (let ((start (if (< (- i 3) 0) 0 (- i 3))))
            (self start
              (if (Str8 =? acc "")
                (Str8 sub start (- i start) ds)
                (Str8 append (Str8 sub start (- i start) ds) (Str8 append "," acc))))))))
    (go n "")))

(def %py-format-spec
  (fn (_ v spec)
    (if (Str8 =? spec "")
      (%py-str v)
      (do
        (def ps (%py-spec-parse spec))
        (def fill (List ref 0 ps))
        (def align (List ref 1 ps))
        (def sign (List ref 2 ps))
        (def alt (List ref 3 ps))
        (def zero (List ref 4 ps))
        (def width (List ref 5 ps))
        (def comma (List ref 6 ps))
        (def prec (List ref 7 ps))
        (def type (List ref 8 ps))
        (def tc (if (Str8 =? type "") 0 (%py-spec-code type 0)))
        ; the 0 flag is fill 0 with = alignment, for numbers
        (def fill2 (if (if zero (Str8 =? fill " ") #f) "0" fill))
        (def align2 (if (if zero (null? align) #f) "=" align))
        (if (match
              ((str? v) #t)
              ((= tc 115) #t)
              ((%py-obj-is v) #t)
              ((null? v) #t)
              ((%py-list? v) #t)
              (#t (%py-tuple-is v)))
          ; strings (and anything shown as its str): s or empty type only
          (match
            ((if (not (= tc 0)) (not (= tc 115)) #f)
              (Err raise (lit value)
                (Str8 append "Unknown format code '" (Str8 append type "' for object of type 'str'")) ()))
            ((if (= tc 115) (not (null? (%py-num-kind v))) #f)
              (Err raise (lit value)
                (Str8 append "Unknown format code 's' for object of type '"
                  (Str8 append (if (eq? (%py-num-kind v) (lit float)) "float" "int") "'")) ()))
            ((if (null? sign) #f (not (Str8 =? sign "")))
              (Err raise (lit value) "Sign not allowed in string format specifier" ()))
            ((if (not (null? align)) (Str8 =? align "=") #f)
              (Err raise (lit value) "'=' alignment not allowed in string format specifier" ()))
            (#t
              (let ((s0 (%py-str v)))
                (let ((s (if (if (not (null? prec)) (> (Str8 length s0) prec) #f) (Str8 sub 0 prec s0) s0)))
                  ; the 0 flag on text fills with zeros on the RIGHT ('{:06s}'
                  ; of ab is ab0000 -- measured)
                  (%py-spec-pad s width (if (if zero (Str8 =? fill " ") #f) "0" fill) align "<" "")))))
          (do
            (def w (if (eq? v #t) 1 (if (eq? v #f) 0 v)))
            (def kind (%py-num-kind w))
            (if (null? kind)
              (Err raise (lit type) "unsupported format string passed to object.__format__" ())
              ())
            ; integers with an integer or empty type
            (match
              ((if (eq? kind (lit int)) (= tc 99) #f)
                (if (if (null? sign) #f (not (Str8 =? sign "")))
                  (Err raise (lit value) "Sign not allowed with integer format specifier 'c'" ())
                  (%py-spec-pad (%py-chr w) width fill align ">" "")))
              ((if (eq? kind (lit int))
                  (match
                    ((= tc 0) #t)
                    ((= tc 100) #t)
                    ((= tc 120) #t)
                    ((= tc 88) #t)
                    ((= tc 111) #t)
                    ((= tc 98) #t)
                    (#t (= tc 110)))
                  #f)
                (do
                  (if (not (null? prec))
                    (Err raise (lit value) "Precision not allowed in integer format specifier" ())
                    ())
                  (def m
                    (match
                      ((if (= tc 120) #t (= tc 88))
                        (%py-fmt-base w 16 (if (= tc 88) "0123456789ABCDEF" "0123456789abcdef")))
                      ((= tc 111) (%py-fmt-base w 8 "01234567"))
                      ((= tc 98) (%py-fmt-base w 2 "01"))
                      (#t (%py-fmt-int-mag w))))
                  ; _ groups binary, octal and hex digits by four
                  (def grp
                    (fn (_ ds)
                      (if (eq? comma #t) (%py-group3 ds)
                        (if (eq? comma (lit under))
                          (%py-group-sep ds
                            (if (match
                                  ((= tc 120) #t)
                                  ((= tc 88) #t)
                                  ((= tc 111) #t)
                                  (#t (= tc 98))) 4 3)
                            "_")
                          ds))))
                  (def pfx (if alt (match
                                     ((= tc 120) "0x")
                                     ((= tc 88) "0X")
                                     ((= tc 111) "0o")
                                     ((= tc 98) "0b")
                                     (#t "")) ""))
                  (def sgn (Str8 append (%py-fmt-sign (first m) (Str8 =? sign "+") (Str8 =? sign " ")) pfx))
                  ; THE 0 FLAG WITH GROUPING GROUPS THE PADDING TOO: '{:05,d}'
                  ; of 0 is 0,000 -- the fewest leading zeros whose grouped
                  ; form fills the width, overshooting when a separator lands
                  (def digits
                    (if (if (Str8 =? fill2 "0") (if (Str8 =? align2 "=") (if comma (not (null? width)) #f) #f) #f)
                      (do
                        (def target (- width (Str8 length sgn)))
                        (def grow
                          (fn (self k)
                            (let ((g (grp (Str8 append (%py-fmt-zeros k) (rest m)))))
                              (if (>= (Str8 length g) target) g (self (+ k 1))))))
                        (grow 0))
                      (grp (rest m))))
                  (%py-spec-pad digits width fill2 align2 ">" sgn)))
              ; floats -- and ints asked for a float type
              ((match
                 ((= tc 0) #t)
                 ((= tc 101) #t)
                 ((= tc 69) #t)
                 ((= tc 102) #t)
                 ((= tc 70) #t)
                 ((= tc 103) #t)
                 ((= tc 71) #t)
                 ((= tc 110) #t)
                 (#t (= tc 37)))
                (do
                  (def fv (%py-fmt-float-of w))
                  (def ex (%py-f-exact fv))
                  (def ekind (first ex))
                  (def neg (Str8 =? (first (rest ex)) "-"))
                  (def upper (if (= tc 69) #t (if (= tc 70) #t (= tc 71))))
                  (def sgn (%py-fmt-sign neg (Str8 =? sign "+") (Str8 =? sign " ")))
                  (if (not (eq? ekind (lit num)))
                    ; inf and nan pad like any number -- '{:06e}' of inf is
                    ; 000inf (measured, not assumed)
                    (let ((body0 (if (eq? ekind (lit inf)) "inf" "nan")))
                      (let ((body (Str8 append (if upper (Str8 upcase body0) body0) (if (= tc 37) "%" ""))))
                        (%py-spec-pad body width fill2 align2 ">" sgn)))
                    (do
                      (def D (first (rest (rest ex))))
                      (def x10 (first (rest (rest (rest ex)))))
                      (def p (if (null? prec) 6 prec))
                      (def body
                        (match
                          ((if (= tc 101) #t (= tc 69))
                            (%py-fmt-e D x10 p upper))
                          ((if (= tc 102) #t (= tc 70)) (%py-fmt-f D x10 p))
                          ((if (= tc 103) #t (if (= tc 71) #t (= tc 110)))
                            (%py-fmt-g D x10 p upper alt))
                          ((= tc 37)
                            (let ((ex2 (%py-f-exact (* fv 100.0))))
                              (Str8 append (%py-fmt-f (first (rest (rest ex2))) (first (rest (rest (rest ex2)))) p) "%")))
                          ; the empty type: repr without precision; with
                          ; precision like g, but a fixed result keeps at
                          ; least one digit after the point
                          ((null? prec)
                            (let ((r (%py-frepr fv))) (if neg (Str8 sub 1 (- (Str8 length r) 1) r) r)))
                          ; like g, but scientific already when the
                          ; exponent reaches p-1 (format(0.0, '.1') is
                          ; 0e+00), and fixed keeps one digit past the point
                          (#t
                            (let ((sc (%py-fmt-sci D x10 (- p 1))))
                              (let ((xa (first (rest (rest sc)))))
                                (if (if (>= xa (- 0 4)) (< xa (- p 1)) #f)
                                  (let ((g (%py-fmt-g D x10 p #f #f)))
                                    (if (null? (Str8 index-of "." g)) (Str8 append g ".0") g))
                                  (let ((fp (%py-fmt-strip0 (first (rest sc)))))
                                    (Str8 append
                                      (if (= (Str8 length fp) 0) (first sc)
                                        (Str8 append (first sc) (Str8 append "." fp)))
                                      (%py-fmt-exp-str xa #f)))))))))
                      (def body2 (if comma (%py-comma-float body (if (eq? comma #t) "," "_")) body))
                      (%py-spec-pad body2 width fill2 align2 ">" sgn)))))
              (#t
                (Err raise (lit value)
                  (Str8 append "Unknown format code '"
                    (Str8 append type
                      (Str8 append "' for object of type '"
                        (Str8 append (if (eq? kind (lit int)) "int" "float") "'")))) ())))))))))

; Digits grouped by k from the right with sep.
(def %py-group-sep
  (fn (_ digits k sep)
    (def n (Str8 length digits))
    (def go
      (fn (self i acc)
        (if (<= i 0) acc
          (let ((lo (if (< (- i k) 0) 0 (- i k))))
            (self lo
              (if (Str8 =? acc "") (Str8 sub lo (- i lo) digits)
                (Str8 append (Str8 sub lo (- i lo) digits) (Str8 append sep acc))))))))
    (go n "")))

; Grouping on a float body: only the integer digits before the point.
(def %py-comma-float
  (fn (_ body sep)
    (let ((dot (Str8 index-of "." body)))
      (if (null? dot)
        (%py-group-sep body 3 sep)
        (Str8 append (%py-group-sep (Str8 sub 0 dot body) 3 sep)
          (Str8 sub dot (- (Str8 length body) dot) body))))))

; One field of an f-string or a .format template: conversion then spec.
(def %py-fmtfield
  (fn (_ v conv spec)
    (let ((cv (match
                ((Str8 =? conv "r") (%py-repr-of v))
                ((Str8 =? conv "s") (%py-str v))
                ((Str8 =? conv "a") (%py-repr-of v))
                ((Str8 =? conv "") v)
                (#t
                  (Err raise (lit value) "Unknown conversion specifier" ())))))
      (%py-format-spec cv spec))))

(def %py-fjoin
  (fn (_ parts)
    (def go (fn (self ps acc) (if (null? ps) acc (self (rest ps) (Str8 append acc (first ps))))))
    (go parts "")))

; str.format: the same template grammar as an f-string, walked at RUNTIME
; against positional arguments -- {} auto-numbers, {2} indexes, and a field's
; .attr / [key] tail is followed.  A spec may itself contain fields
; ({:{}} takes its width from the next argument).  Keyword fields wait on
; keyword arguments.
(def %py-strformat-kw
  (fn (_ tpl args kws)
    (def n (Str8 length tpl))
    (def auto (pair 0 ()))
    ; () until the first field, then auto or manual: mixing is a ValueError
    (def mode (pair () ()))
    (def argn (%py-length args))
    (def arg-at
      (fn (_ i)
        (if (>= i argn)
          (Err raise (lit index) "Replacement index out of range for positional args tuple" ())
          (List ref i args))))
    (def resolve
      (fn (_ name)
        ; name: "" | digits | identifier, followed by .attr / [key] tails
        (def nn (Str8 length name))
        (def head-end
          (fn (self j)
            (if (>= j nn) j
              (let ((c (%py-spec-code name j)))
                (if (if (= c 46) #t (= c 91)) j (self (+ j 1)))))))
        (def he (head-end 0))
        (def head (Str8 sub 0 he name))
        (def base
          (if (Str8 =? head "")
            (do
              (if (eq? (first mode) (lit manual))
                (Err raise (lit value) "cannot switch from manual field specification to automatic field numbering" ())
                (%set-first! mode (lit auto)))
              (let ((i (first auto))) (%set-first! auto (+ i 1)) (arg-at i)))
            (if (%py-fmt-digit? (%py-spec-code head 0))
              (do
                (if (eq? (first mode) (lit auto))
                  (Err raise (lit value) "cannot switch from automatic field numbering to manual field specification" ())
                  (%set-first! mode (lit manual)))
                (arg-at (%py-int-of-str head)))
              (let ((kw (%py-alist-find head kws)))
                (if (null? kw)
                  (Err raise (lit key) (Str8 append (Str8 append "'" head) "'") ())
                  (rest kw))))))
        (def head-end-from
          (fn (_ j)
            (def go (fn (self k) (if (>= k nn) k (let ((c (%py-spec-code name k))) (if (if (= c 46) #t (= c 91)) k (self (+ k 1)))))))
            (go j)))
        (def tail
          (fn (self j v)
            (if (>= j nn) v
              (let ((c (%py-spec-code name j)))
                (if (= c 46)
                  (let ((e (head-end-from (+ j 1))))
                    (self e (%py-getattr v (Str8 sub (+ j 1) (- e (+ j 1)) name))))
                  (let ((close (Str8 index-of "]" (Str8 sub j (- nn j) name))))
                    (if (null? close)
                      (Err raise (lit value) "Missing ']' in format string" ())
                      (let ((key (Str8 sub (+ j 1) (- close 1) name)))
                        (self (+ j close 1)
                          (%py-index v
                            (if (%py-fmt-digit? (%py-spec-code key 0)) (%py-int-of-str key) key)))))))))))
        (tail he base)))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-spec-code tpl i)))
            (if (= c 123)
              (if (if (< (+ i 1) n) (= (%py-spec-code tpl (+ i 1)) 123) #f)
                (self (+ i 2) (Str8 append acc "{"))
                (let ((close (guard (_ (Err raise (lit value) "Single '{' encountered in format string" ()))
                               (%py-fs-close tpl (+ i 1) 0))))
                  (let ((field (Str8 sub (+ i 1) (- close (+ i 1)) tpl)))
                    (def fn0 (Str8 length field))
                    (def at (%py-fs-split field 0 0))
                    (def name (if (null? at) field (Str8 sub 0 at field)))
                    (def tl (if (null? at) "" (Str8 sub at (- fn0 at) field)))
                    (def conv
                      (if (if (> (Str8 length tl) 1) (= (%py-spec-code tl 0) 33) #f)
                        (Str8 sub 1 1 tl) ""))
                    (def after (if (Str8 =? conv "") tl (Str8 sub 2 (- (Str8 length tl) 2) tl)))
                    (if (if (> (Str8 length after) 0) (not (= (%py-spec-code after 0) 58)) #f)
                      (Err raise (lit value) "expected ':' after conversion specifier" ())
                      ())
                    (def spec0
                      (if (if (> (Str8 length after) 0) (= (%py-spec-code after 0) 58) #f)
                        (Str8 sub 1 (- (Str8 length after) 1) after) ""))
                    ; the VALUE takes its auto-number before a nested spec
                    ; draws width or precision from the args that follow it
                    (def v (resolve name))
                    (def spec (if (null? (Str8 index-of "{" spec0)) spec0 (%py-strformat-sub spec0 args auto kws)))
                    (self (+ close 1) (Str8 append acc (%py-fmtfield v conv spec))))))
              (if (= c 125)
                (if (if (< (+ i 1) n) (= (%py-spec-code tpl (+ i 1)) 125) #f)
                  (self (+ i 2) (Str8 append acc "}"))
                  (Err raise (lit value) "Single '}' encountered in format string" ()))
                (self (+ i 1) (Str8 append acc (Str8 sub i 1 tpl)))))))))
    (go 0 "")))

(def %py-strformat (fn (_ tpl args) (%py-strformat-kw tpl args ())))

; A nested spec shares the caller's auto-counter: {:{}} consumes the next
; positional argument for its width.
(def %py-strformat-sub
  (fn (_ tpl args auto kws)
    (def n (Str8 length tpl))
    (def argn (%py-length args))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-spec-code tpl i)))
            (if (= c 123)
              (let ((close (%py-fs-close tpl (+ i 1) 0)))
                (let ((name (Str8 sub (+ i 1) (- close (+ i 1)) tpl)))
                  (let ((v (if (Str8 =? name "")
                             (let ((k (first auto))) (%set-first! auto (+ k 1))
                               (if (>= k argn) (Err raise (lit index) "Replacement index out of range" ()) (List ref k args)))
                             (if (%py-fmt-digit? (%py-spec-code name 0))
                               (List ref (%py-int-of-str name) args)
                               (let ((kw (%py-alist-find name kws)))
                                 (if (null? kw)
                                   (Err raise (lit key) (Str8 append (Str8 append "'" name) "'") ())
                                   (rest kw)))))))
                    (self (+ close 1) (Str8 append acc (%py-str v))))))
              (self (+ i 1) (Str8 append acc (Str8 sub i 1 tpl))))))))
    (go 0 "")))


(def %py-drop-last
  (fn (self lst)
    (if (null? (rest lst)) () (pair (first lst) (self (rest lst))))))

; --- print -------------------------------------------------------------------
; Python's `print` is not `display`: arguments are separated by a single space,
; a newline follows, and a string prints WITHOUT its quotes while everything
; else prints as its repr. The conformance suite asserts on stdout, so this is
; the single most load-bearing function in the bundle.
; Python prints True/False; x displays #t/#f. That is a rendering difference,
; not a value difference, and it belongs here rather than in the parser --
; every conformance program that prints a comparison depends on it.
;
; `display` is otherwise already right: it writes a string WITHOUT quotes and a
; number as a number, which is what print wants. `write` would quote the string.
; REPR WRITES, IT DOES NOT BUILD A STRING.  Rendering a number into a string
; would need a number->string conversion this layer does not have; writing it
; needs only `display`, which already knows how.  So repr is a procedure that
; emits, and the container cases emit their punctuation around it.
; --- Float repr: shortest round-trip -----------------------------------------
;
; THE ENGINE'S WRITER IS %.15g AND PYTHON'S IS SHORTEST-ROUND-TRIP, and the
; difference is not cosmetic: 1/3 prints 0.333333333333333 there and
; 0.3333333333333333 in Python -- fifteen digits is one too few for a third
; (x-lang#577).  Python's rule: the shortest decimal string that parses back
; to exactly the same double.
;
; THE EXACT DIGITS ARE FREE, so the search is honest rather than heuristic.  A
; float IS m * 2^e for integers m, e; for e >= 0 that is the integer m << e,
; and for e < 0 it is (m * 5^-e) / 10^-e -- an integer over a power of ten.
; Bigint renders the integer's every digit, and rounding to p significant
; digits is then string work against a tail that is exactly known (round half
; to even, Python's rule).  Each candidate is parsed back through strtod
; ((Float str->bits), correctly rounded) and compared BIT FOR BIT; the first
; precision that survives is the answer.  Seventeen always survives, so the
; loop terminates.
;
; A float value's payload IS its IEEE 754 bit pattern -- (first v), the
; representation lib/x/num/float.x states -- and the sign, exponent and
; mantissa fields come out with div/mod against powers of two, through the
; tower ops so nothing wraps (the sign bit makes the raw pattern negative as
; a machine int).
(def %py-f-2p52 4503599627370496)
(def %py-f-2p64 (%py-mul (%py-mul 4503599627370496 2048) 2))

(def %py-f-pow
  (fn (self b k)
    (if (= k 0)
      1
      (let ((h (self b (%py-floordiv k 2))))
        (let ((hh (%py-mul h h)))
          (if (= (%py-mod k 2) 0) hh (%py-mul hh b)))))))

(def %py-f-zeros
  (fn (self k) (if (<= k 0) "" (Str8 append "0" (self (- k 1))))))

(def %py-f-code
  (fn (_ s i) (%py-char-code (%str-ref s i))))

; Any nonzero digit at or after index i?
(def %py-f-nonzero-from?
  (fn (self t i)
    (if (>= i (Str8 length t))
      #f
      (if (= (%py-f-code t i) 48) (self t (+ i 1)) #t))))

; Increment a decimal digit string by one, with carry; "999" -> "1000".
(def %py-f-inc
  (fn (_ h)
    (def go
      (fn (self i)
        (if (< i 0)
          "carry"
          (let ((c (%py-f-code h i)))
            (if (= c 57)
              (self (- i 1))
              (Str8 append
                (Str8 append (Str8 sub 0 i h)
                  (Str8 sub (+ (- c 48) 1) 1 "0123456789"))
                (%py-f-zeros (- (- (Str8 length h) i) 1))))))))
    (let ((r (go (- (Str8 length h) 1))))
      (if (Str8 =? r "carry")
        (Str8 append "1" (%py-f-zeros (Str8 length h)))
        r))))

; Round the exact digit string D to p significant digits, half to even.
; Returns the rounded digits; a carry that grows the string ("99" -> "100")
; grows the decimal exponent by the length difference, which the caller reads.
(def %py-f-round
  (fn (_ D p)
    (def n (Str8 length D))
    (if (<= n p)
      D
      (do
        (def h (Str8 sub 0 p D))
        (def c (%py-f-code D p))
        (def up
          (match
            ((> c 53) #t)
            ((< c 53) #f)
            ((%py-f-nonzero-from? D (+ p 1)) #t)
            (#t (= (%py-mod (- (%py-f-code h (- p 1)) 48) 2) 1))))
        (if up (%py-f-inc h) h)))))

(def %py-f-strip0
  (fn (self h)
    (def L (Str8 length h))
    (if (<= L 1)
      h
      (if (= (%py-f-code h (- L 1)) 48)
        (self (Str8 sub 0 (- L 1) h))
        h))))

(def %py-f-2d
  (fn (_ k)
    (let ((s (%py-write-to-str k)))
      (if (< k 10) (Str8 append "0" s) s))))

; Python's own spelling: fixed for -4 <= x < 16, scientific outside, ".0" kept
; on integral fixed floats, exponents signed and two digits wide.
(def %py-f-format
  (fn (_ digits xa sgn)
    (def h (%py-f-strip0 digits))
    (def L (Str8 length h))
    (Str8 append sgn
      (if (if (>= xa (- 0 4)) (< xa 16) #f)
        (if (>= xa (- L 1))
          (Str8 append (Str8 append h (%py-f-zeros (- xa (- L 1)))) ".0")
          (if (>= xa 0)
            (Str8 append (Str8 append (Str8 sub 0 (+ xa 1) h) ".")
              (Str8 sub (+ xa 1) (- L (+ xa 1)) h))
            (Str8 append (Str8 append "0." (%py-f-zeros (- 0 (+ xa 1)))) h)))
        (Str8 append
          (if (= L 1)
            h
            (Str8 append (Str8 append (Str8 sub 0 1 h) ".")
              (Str8 sub 1 (- L 1) h)))
          (Str8 append (if (< xa 0) "e-" "e+")
            (%py-f-2d (if (< xa 0) (- 0 xa) xa))))))))

; The exact decimal expansion, shared with %-formatting (python/format.x):
; (kind sign digits exp10) where kind is 'num / 'inf / 'nan, digits is every
; digit of m*2^e (no leading zeros; "0" for zero), and the value is
; digits[0].digits[1:] * 10^exp10.
(def %py-f-exact
  (fn (_ v)
    (def bits (first v))
    (def u (if (< bits 0) (%py-add bits %py-f-2p64) bits))
    (def hi (%py-floordiv u %py-f-2p52))
    (def E (%py-mod hi 2048))
    (def M (%py-mod u %py-f-2p52))
    (def sgn (if (< bits 0) "-" ""))
    (if (= E 2047)
      (if (= M 0) (list (lit inf) sgn "" 0) (list (lit nan) "" "" 0))
      (if (if (= E 0) (= M 0) #f)
        (list (lit num) sgn "0" 0)
        (do
          (def m (if (= E 0) M (%py-add M %py-f-2p52)))
          (def e (if (= E 0) (- 0 1074) (- E 1075)))
          (def N
            (if (>= e 0)
              (%py-mul m (%py-f-pow 2 e))
              (%py-mul m (%py-f-pow 5 (- 0 e)))))
          (def D (%py-write-to-str N))
          (list (lit num) sgn D
            (if (>= e 0)
              (- (Str8 length D) 1)
              (- (- (Str8 length D) 1) (- 0 e)))))))))

(def %py-frepr
  (fn (_ v)
    (def bits (first v))
    (def ex (%py-f-exact v))
    (def sgn (first (rest ex)))
    (def D (first (rest (rest ex))))
    (def x10 (first (rest (rest (rest ex)))))
    (if (eq? (first ex) (lit inf))
      (Str8 append sgn "inf")
      (if (eq? (first ex) (lit nan))
        "nan"
        (do
          (def try
            (fn (self p)
              (if (> p 17)
                ()
                (do
                  (def digits (%py-f-round D p))
                  (def cand
                    (%py-f-format digits
                      (%py-add x10 (- (Str8 length digits)
                                      (if (< (Str8 length D) p)
                                        (Str8 length D) p)))
                      sgn))
                  (if (= (Float str->bits cand) bits)
                    cand
                    (self (+ p 1)))))))
          (let ((r (try 1)))
            (if (null? r) (Str8 append sgn (%py-write-to-str v)) r)))))))

; --- Complex -----------------------------------------------------------------
;
; THE VALUE IS THE PLATFORM'S: x/num/complex.x's instance, a (re . im) pair of
; floats, with the tower doing + - * / and = across ints, floats and bools.
; What Python adds is spelling and refusal: the repr, the constructor's string
; grammar, ordering as a TypeError, floor and modulo as TypeErrors, and powers
; through the polar form.  Parts are ALWAYS floats -- the platform keeps ints
; where it is given ints, so every door here floats them on the way in.
(def %py-cre (fn (_ z) (let ((r (first (first z)))) (if (%py-float-is r) r (* 1.0 r)))))
(def %py-cim (fn (_ z) (let ((i (rest (first z)))) (if (%py-float-is i) i (* 1.0 i)))))

(def %py-complex-of
  (fn (_ v)
    (if (%py-complex-is v)
      v
      (Complex make (* 1.0 (if (eq? v #t) 1 (if (eq? v #f) 0 v))) 0.0))))

; A part prints as its float repr with a trailing .0 dropped: (1+2j), not
; (1.0+2.0j); 1.5 and 1e+20 and nan keep their spelling.
(def %py-cpart
  (fn (_ f)
    (let ((s (%py-frepr f)))
      (let ((n (Str8 length s)))
        (if (if (> n 2) (Str8 =? (Str8 sub (- n 2) 2 s) ".0") #f)
          (Str8 sub 0 (- n 2) s)
          s)))))

; Python's rule: the real part is omitted, and the parens with it, only when
; it is EXACTLY +0.0 (a -0.0 real prints as (-0+1j)); the imaginary sign is
; the sign BIT, so -0.0 imag prints as -0j.
(def %py-crepr
  (fn (_ z)
    (def re (%py-cre z))
    (def im (%py-cim z))
    (def ineg (< (first im) 0))
    (def imag (%py-cpart (if ineg (- 0.0 im) im)))
    (if (= (first re) 0)
      (Str8 append (if ineg "-" "") (Str8 append imag "j"))
      (Str8 append "("
        (Str8 append (%py-cpart re)
          (Str8 append (if ineg "-" "+")
            (Str8 append imag "j)")))))))

; complex("...") -- Python's grammar: optional parens, [real][(+|-)imag]j,
; each part a float spelling (inf and nan included), a bare sign or nothing
; before the j meaning one.  No internal whitespace.  Everything malformed
; is a ValueError, and the float parser raises it for us on every garbage
; part; the split is at the LAST sign that does not follow an exponent's e.
(def %py-cparse
  (fn (_ s0)
    (def s1 (%py-f-trim s0))
    (def n1 (Str8 length s1))
    (def bad
      (fn (_)
        (Err raise (lit value) "complex() arg is a malformed string" ())))
    (def s
      (if (if (>= n1 2)
            (if (= (%py-f-code s1 0) 40) (= (%py-f-code s1 (- n1 1)) 41) #f)
            #f)
        (Str8 sub 1 (- n1 2) s1)
        s1))
    (def n (Str8 length s))
    (if (= n 0)
      (bad)
      (if (not (null? (Str8 index-of " " s)))
        (bad)
        (let ((last (%py-f-code s (- n 1))))
          (if (if (= last 106) #t (= last 74))
            (do
              (def body (Str8 sub 0 (- n 1) s))
              (def bn (Str8 length body))
              (def split
                (fn (self i)
                  (if (< i 1)
                    ()
                    (let ((c (%py-f-code body i)))
                      (if (if (if (= c 43) #t (= c 45))
                            (let ((pc (%py-f-code body (- i 1))))
                              (not (if (= pc 101) #t (= pc 69))))
                            #f)
                        i
                        (self (- i 1)))))))
              (def at (split (- bn 1)))
              (def re-s (if (null? at) "" (Str8 sub 0 at body)))
              (def im-s (if (null? at) body (Str8 sub at (- bn at) body)))
              (def im
                (if (if (Str8 =? im-s "") #t (Str8 =? im-s "+"))
                  1.0
                  (if (Str8 =? im-s "-")
                    (- 0.0 1.0)
                    (%py-float-of-str im-s))))
              (def re (if (Str8 =? re-s "") 0.0 (%py-float-of-str re-s)))
              (Complex make re im))
            (Complex make (%py-float-of-str s) 0.0)))))))

(def %py-complex-ctor
  (fn (_ . a)
    (if (null? a)
      (Complex make 0.0 0.0)
      (let ((x (first a)))
        (if (null? (rest a))
          (match
            ((str? x) (%py-cparse x))
            ; __complex__ first, and its answer must BE a complex; then
            ; __float__, whose answer becomes the real part
            ((%py-obj-is x)
              (let ((m (%py-dunder x "__complex__")))
                (if (not (null? m))
                  (let ((r (m)))
                    (if (%py-complex-is r)
                      r
                      (Err raise (lit type) "__complex__ returned non-complex" ())))
                  (let ((f (%py-dunder x "__float__")))
                    (if (null? f)
                      (Err raise (lit type)
                        "complex() first argument must be a string or a number" ())
                      (%py-complex-of (f)))))))
            ((null? (%py-num-kind (if (eq? x #t) 1 (if (eq? x #f) 0 x))))
              (Err raise (lit type)
                "complex() first argument must be a string or a number" ()))
            (#t (%py-complex-of x)))
          ; complex(a, b) with two REALS builds the parts directly -- through
          ; the tower, -0.0 + 0.0 is +0.0 and the signed zero Python keeps
          ; ((-0+1j), (1-0j)) would be lost; with a complex on either side it
          ; is a + b*1j, which is where Python puts the parts too
          (if (str? x)
            (Err raise (lit type) "complex() can't take second arg if first is a string" ())
            (let ((y (first (rest a))))
              (if (if (%py-complex-is x) #t (%py-complex-is y))
                (+ (%py-complex-of x) (* (%py-complex-of y) (Complex make 0.0 1.0)))
                (Complex make
                  (* 1.0 (if (eq? x #t) 1 (if (eq? x #f) 0 x)))
                  (* 1.0 (if (eq? y #t) 1 (if (eq? y #f) 0 y))))))))))))

; z ** w.  An integer w multiplies exactly (1j ** 2 is exactly -1+0j);
; anything else goes through the polar form, exp(w * log z).  Zero to a
; negative or complex power is Python's ZeroDivisionError.
(def %py-cpow
  (fn (_ z w)
    (def wr (%py-cre w))
    (def wi (%py-cim w))
    (def zr (%py-cre z))
    (def zi (%py-cim z))
    (if (if (= zr 0.0) (= zi 0.0) #f)
      (if (if (= wr 0.0) (= wi 0.0) #f)
        (Complex make 1.0 0.0)
        (if (if (< wr 0.0) #t (not (= wi 0.0)))
          (Err raise (lit zero-division)
            "0.0 to a negative or complex power" ())
          (Complex make 0.0 0.0)))
      (if (if (= wi 0.0) (if (= wr (Float floor wr)) (< (%py-abs wr) 1024.0) #f) #f)
        (do
          (def n (Float ->int wr))
          (def mul
            (fn (self k acc) (if (= k 0) acc (self (- k 1) (* acc z)))))
          (if (< n 0)
            (/ (Complex make 1.0 0.0) (mul (- 0 n) (Complex make 1.0 0.0)))
            (mul n (Complex make 1.0 0.0))))
        (do
          (def lr (Float log (Complex magnitude z)))
          (def th (Float atan2 zi zr))
          (def er (- (* wr lr) (* wi th)))
          (def ei (+ (* wr th) (* wi lr)))
          (Complex from-polar (Float exp er) ei))))))

; hash(): ints are their own hash (Python folds them modulo 2^61-1, which
; only shows past 2^61), bools 0 and 1, integral floats their int, other
; floats their bit pattern, complex CPython's real + 1000003 * imag.
; order must not matter, so the element hashes are summed
(def %py-set-hash
  (fn (self es acc)
    (if (null? es) acc (self (rest es) (+ acc (%py-hash (first es)))))))
(def %py-hash
  ; TWELVE ARMS, so a match: what a value hashes to, one arm per kind.
  (fn (_ v)
    (match
      ((eq? v #t) 1)
      ((eq? v #f) 0)
      ; NotImplemented is a singleton, and Python lets it be hashed.  It
      ; reaches here as an ordinary pair that nothing else claims, so it used
      ; to fall through to "unhashable type".
      ((eq? v %py-NotImplemented) (%py-id v))
      ((eq? v %py-Ellipsis) (%py-id v))
      ((%py-float-is v) (if (= v (Float floor v)) (Float ->int v) (first v)))
      ((%py-complex-is v)
        (+ (%py-hash (%py-cre v)) (* 1000003 (%py-hash (%py-cim v)))))
      ((eq? (%py-num-kind v) (lit int)) v)
      ((str? v) (Hash fnv-1a v))
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__hash__"))) (if (null? m) 0 (m))))
      ; a frozenset hashes on its elements; a set is unhashable
      ((%py-set-is v)
        (if (%py-set-frozen? v)
          (%py-set-hash (%py-set-elems v) 0)
          (Err raise (lit type) "unhashable type: 'set'" ())))
      ; a function, generator or class hashes by identity, as in Python
      ((%py-fn-is v) (%py-id v))
      ((%py-gen-is v) (%py-id v))
      ((%py-class-is v) (%py-id v))
      ((%py-view-is v)
        (if (Str8 =? (%py-view-kind v) "dict_values")
          (%py-set-hash (%py-view-elems v) 0)
          (Err raise (lit type)
            (Str8 append (Str8 append "unhashable type: '" (%py-view-kind v)) "'") ())))
      ((%py-tuple-is v) (%py-set-hash (%py-tuple-elems v) 0))
      (#t (Err raise (lit type) "unhashable type" ())))))

; Is v a machine float?  The type-handle compare %py-num-kind uses, taken
; directly so the writer below can ask cheaply.
(def %py-float-is
  (fn (_ v) (eq? (%py-typeof-prim v) %py-th-float)))

(def %py-write ())
(set! %py-write
  (fn (_ v)
    (match
      ((%py-float-is v) (display (%py-frepr v)))
      ((%py-complex-is v) (display (%py-crepr v)))
      ((str? v) (display (%py-str-repr v)))
      ((eq? v #t) (display "True"))
      ((eq? v #f) (display "False"))
      ((null? v) (display "None"))
      ((%py-tuple-is v) (write v))
      ((%py-list? v) (write v))
      ((%py-dict? v) (write v))
      ; str(e) in Python is the MESSAGE, not the repr -- `print(e)`
      ; inside an except block shows "division by zero", not
      ; "#<err:zero-division division by zero>".
      ((Err err? v) (display (v msg)))
      ; An exception INSTANCE prints as its message too -- print(e)
      ; has to read the same whether the raise came from Python source
      ; or from this runtime.
      ((%py-obj-is v) (display (%py-obj-repr v)))
      ((eq? v %py-NotImplemented) (display "NotImplemented"))
      ((eq? v %py-Ellipsis) (display "Ellipsis"))
      (#t (display v)))))

; Close the loop: python/types.x forward-declares %py-repr and its PY-LIST write
; handler calls it per element, so that a string inside a list shows its quotes.
; The hook is set HERE because repr is Python's rule, not the container's.
(set! %py-repr %py-write)

; and the PY-DICT `call` handler reaches Python's equality the same way.
(set! %py-dict-get %py-dget)

; and the container equality ops compare their elements with Python's rule,
; which is what makes nested containers come out right.
(set! %py-equal %py-eq)


; display and write differ in exactly ONE way: a string prints BARE at top level
; and quoted inside a container. Everything else -- True/False/None, lists,
; dicts, numbers -- is identical, so this defers rather than restating the
; cases. Restating them is how dicts came to print as raw pairs: the dict branch
; was added to write and not to its copy here.
; print() shows an object's str; a container shows its elements' repr --
; the one place the two writers part ways.
(def %py-display
  (fn (_ v)
    (if (str? v)
      (display v)
      (if (%py-obj-is v)
        (display (%py-obj-str v))
        (%py-write v)))))

(def %py-print-with
  (fn (_ sep end args)
    (def %go
      (fn (self vs first?)
        (if (null? vs)
          ()
          (%seq
            (if first? () (display sep))
            (%seq (%py-display (first vs))
              (self (rest vs) #f))))))
    (%seq (%go args #t) (display end))))
(def %py-print (fn (_ . args) (%py-print-with " " "\n" args)))
; print(..., sep=, end=): None means the default, as in Python
(def %py-print-kw
  (fn (_ args kws)
    (def check
      (fn (self ks)
        (if (null? ks) ()
          (if (if (Str8 =? (first (first ks)) "sep") #t (Str8 =? (first (first ks)) "end"))
            (self (rest ks))
            (Err raise (lit type)
              (Str8 append (Str8 append "'" (first (first ks)))
                "' is an invalid keyword argument for print()")
              ())))))
    (def pick
      (fn (_ k dflt)
        (let ((e (%py-alist-find k kws)))
          (if (null? e) dflt (if (null? (rest e)) dflt (rest e))))))
    (check kws)
    (%py-print-with (pick "sep" " ") (pick "end" "\n") args)))

; --- Exceptions --------------------------------------------------------------
;
; PYTHON'S EXCEPTION TYPES ARE CLASSES, AND THE HIERARCHY IS THE POINT.
;
; The first version of this file mapped exception NAMES to x error KINDS with a
; string table, and `Exception` matched everything by a special case written
; into the matcher.  That worked and could not grow: `except LookupError`
; catching both IndexError and KeyError is not a special case, it is what
; deriving from a common base MEANS, and a flat table has no way to say it.
;
; So the builtin exceptions are real PY-CLASS values, in Python's own shape, and
; matching walks the base chain.  `Exception` is no longer special -- it is just
; the root every other one reaches.
;
; TWO KINDS OF RAISED VALUE ARRIVE HERE.  A `raise` in Python source produces a
; PY-OBJ instance.  Everything this runtime raises itself -- a bad subscript, a
; missing key -- produces an Err carrying a kind symbol, because those raises
; predate classes by a long way and rewriting them would gain nothing.  The
; kind table below is the bridge: an Err's kind names the class it would have
; been, and from there both kinds of value match identically.

; EVERY CLASS DESCENDS FROM object, and until now nothing here said so:
; `class C(object)` named an unbound global, which this runtime binds to a
; shim that raises when CALLED -- so the shim arrived as a BASE, method
; lookup walked into a closure as though it were a class record, and the
; interpreter died rather than saying anything.  A root class costs one
; record and makes the ordinary path ordinary: it terminates the base chain
; the way () did, `isinstance(x, object)` is the walk it already does, and
; the guard in %py-mkclass turns any other non-class base into the TypeError
; Python raises instead of a crash.
(def %py-cls-object
  ; object.__new__ ALLOCATES, and having it here is what makes a user
  ; __new__ able to call super().__new__(cls) -- the bound self is the class,
  ; and the explicit cls argument arrives after it, so the extra is absorbed.
  ;
  ; object.__init__ ACCEPTS AND DOES NOTHING, which is what `super().__init__()`
  ; reaches from a class whose base is object -- the commonest line in Python
  ; that this runtime could not run, because the walk ended at a class with no
  ; methods at all.  It answers None, as every __init__ must.
  (%py-class-new "object" ()
    (list
      (pair "__new__" (fn (_ cls . args) (%py-obj-new cls)))
      (pair "__init__" (fn (_ self . args) ())))
    "object"))

(def %py-exc-BaseException
  ; THE ROOT IS BaseException, as Python has it, and it is where the message
  ; machinery lives -- Exception inherits every bit of this and adds nothing,
  ; which is exactly what Python's own hierarchy says.  `except` is defined
  ; against this class, which is what the message about catching a class that
  ; does not inherit from BaseException always claimed while the check asked
  ; about Exception.
  (%py-class-new "BaseException" %py-cls-object
    ; Every exception gets a message, and this is where it is stored.  A user
    ; class that defines its own __init__ overrides this and gets no message
    ; unless it sets one -- Python would have it call super().__init__, which
    ; does not exist here.
    (list
      (pair "__init__"
        (fn (_ self . args)
          (%py-setattr self "args" (%py-tuple-of-list args))
          (%py-setattr self "__msg__" (if (null? args) "" (first args)))))
      ; str(e) is the message; repr(e) is Name(arg, ...) with each arg's repr
      (pair "__str__" (fn (_ self) (%py-exc-msg self)))
      (pair "__repr__"
        (fn (_ self)
          (let ((a (%py-alist-find "args" (%py-obj-attrs self))))
            (def rs
              (fn (self l) (if (null? l) () (pair (%py-repr-of (first l)) (self (rest l))))))
            (Str8 append (%py-class-name (%py-obj-class self))
              (Str8 append "(" (Str8 append (Str8 join ", " (if (null? a) () (rs (%py-tuple-elems (rest a))))) ")")))))))
    "BaseException"))

; Exceptions print <class 'ValueError'> in Python, not <class '__main__....'>
; -- the builtins live in no module the program wrote, so the qualname is the
; bare name.  This fixes a recorded divergence in 19-exception-classes.
(def %py-exc-new (fn (_ name base) (%py-class-new name base () name)))

(def %py-exc-Exception       (%py-exc-new "Exception"       %py-exc-BaseException))
(def %py-exc-ArithmeticError (%py-exc-new "ArithmeticError" %py-exc-Exception))
; ImportError is the corpus's own feature probe, seventy times over: a test
; that needs a module it may not have wraps the import and prints SKIP.  Left
; undefined, every one of those raised "catching classes that do not inherit
; from BaseException" from the except clause itself.
(def %py-exc-ImportError     (%py-exc-new "ImportError"     %py-exc-Exception))
(def %py-exc-MemoryError     (%py-exc-new "MemoryError"     %py-exc-Exception))
(def %py-exc-OverflowError   (%py-exc-new "OverflowError"   %py-exc-ArithmeticError))
(def %py-exc-StopAsyncIteration
  (%py-exc-new "StopAsyncIteration" %py-exc-Exception))
(def %py-exc-LookupError     (%py-exc-new "LookupError"     %py-exc-Exception))
(def %py-exc-ZeroDivisionError
  (%py-exc-new "ZeroDivisionError" %py-exc-ArithmeticError))
(def %py-exc-IndexError      (%py-exc-new "IndexError"      %py-exc-LookupError))
(def %py-exc-KeyError        (%py-exc-new "KeyError"        %py-exc-LookupError))
(def %py-exc-AttributeError  (%py-exc-new "AttributeError"  %py-exc-Exception))
(def %py-exc-NameError       (%py-exc-new "NameError"       %py-exc-Exception))
(def %py-exc-TypeError       (%py-exc-new "TypeError"       %py-exc-Exception))
(def %py-exc-ValueError      (%py-exc-new "ValueError"      %py-exc-Exception))
(def %py-exc-StopIteration   (%py-exc-new "StopIteration"   %py-exc-Exception))
(def %py-exc-GeneratorExit   (%py-exc-new "GeneratorExit"   %py-exc-Exception))
(def %py-exc-SystemExit      (%py-exc-new "SystemExit"      %py-exc-Exception))
(def %py-exc-RuntimeError    (%py-exc-new "RuntimeError"    %py-exc-Exception))
(def %py-exc-SyntaxError     (%py-exc-new "SyntaxError"     %py-exc-Exception))
(def %py-exc-NotImplementedError
  (%py-exc-new "NotImplementedError" %py-exc-RuntimeError))
(def %py-exc-OSError         (%py-exc-new "OSError"         %py-exc-Exception))
(def %py-exc-EOFError        (%py-exc-new "EOFError"        %py-exc-Exception))
(def %py-exc-KeyboardInterrupt
  (%py-exc-new "KeyboardInterrupt" %py-exc-BaseException))
(def %py-exc-IndentationError (%py-exc-new "IndentationError" %py-exc-SyntaxError))
(def %py-exc-UnicodeError    (%py-exc-new "UnicodeError"    %py-exc-ValueError))

; An Err's kind names the class it would have been.  A kind with no row -- one
; raised by the platform rather than by this runtime -- answers Exception, so
; `except Exception` still catches it rather than letting it through a handler
; that looks like it should have caught it.
(def %py-kind-classes
  (list
    (pair (lit type)          %py-exc-TypeError)
    (pair (lit value)         %py-exc-ValueError)
    (pair (lit index)         %py-exc-IndexError)
    (pair (lit key)           %py-exc-KeyError)
    (pair (lit name)          %py-exc-NameError)
    (pair (lit attribute)     %py-exc-AttributeError)
    (pair (lit zero-division) %py-exc-ZeroDivisionError)
    (pair (lit syntax)        %py-exc-SyntaxError)
    (pair (lit state)         %py-exc-RuntimeError)
    (pair (lit import)        %py-exc-ImportError)))

(def %py-kind-class
  (fn (self k rows)
    (if (null? rows)
      %py-exc-Exception
      (if (eq? k (first (first rows)))
        (rest (first rows))
        (self k (rest rows))))))

; The class of whatever was raised, whichever of the two shapes it is.
(def %py-exc-class-of
  (fn (_ e)
    (if (%py-obj-is e)
      (%py-obj-class e)
      (%py-kind-class (Err kind-of e) %py-kind-classes))))

(def %py-subclass?
  (fn (self c target)
    (if (null? c)
      #f
      (if (eq? c target) #t (%py-subclass-any? (%py-class-bases c) target)))))

(def %py-subclass-any?
  (fn (self bs target)
    (if (null? bs)
      #f
      (if (%py-subclass? (first bs) target) #t (self (rest bs) target)))))

(def %py-exc-match
  (fn (_ e cls)
    (if (not (%py-class-is cls))
      (Err raise (lit type)
        "catching classes that do not inherit from BaseException is not allowed"
        ())
      (%py-subclass? (%py-exc-class-of e) cls))))

; `except (A, B):` -- any of a tuple of classes.  Python spells this with a
; tuple and means "or"; nothing about it needs the tuple TYPE, only the list of
; classes the parser already has.
(def %py-exc-match-any
  (fn (self e clss)
    (if (null? clss)
      #f
      (if (%py-exc-match e (first clss)) #t (self e (rest clss))))))

; `raise X(...)` CALLS X and raises the result, which is what Python does -- and
; is why an undefined name answers NameError here without any special case: the
; parser emits a call, and an undefined name is bound to a shim that raises when
; called.
(def %py-raise
  (fn (_ inst)
    (if (if (%py-obj-is inst)
          (%py-subclass? (%py-obj-class inst) %py-exc-Exception)
          #f)
      (error inst)
      ; An ordinary object is not raisable, and neither is a number or a string.
      (Err raise (lit type) "exceptions must derive from BaseException" ()))))

; UNCAUGHT, AN INSTANCE RENDERS AS `Name: message`.  Without this it printed
; `<__main__.KeyError object>` -- the object form is right for an ordinary
; object and useless for the one case where a human is reading it because the
; program just died.  Python's traceback ends in exactly this line.
(set! %py-obj-write
  (fn (_ o)
    (if (%py-subclass? (%py-obj-class o) %py-exc-BaseException)
      (display (%py-class-name (%py-obj-class o)) ": " (%py-exc-msg o))
      ; A SUBCLASS OF A BUILTIN PRINTS AS THE BUILTIN: `print(mylist([1,2]))`
      ; is [1, 2], not <__main__.mylist object>, because that is what the
      ; value IS -- a class that wants otherwise writes __str__ or __repr__.
      (let ((n (%py-obj-native o)))
        (if (null? n)
          (display "<" (%py-class-qualname (%py-obj-class o)) " object>")
          (display (%py-repr-of n)))))))

; The message an exception carries, for print(e) and str(e).  A KeyError
; with ONE argument answers that argument's REPR -- Python prints a missing
; string key as `KeyError: 'z'` so the reader can tell the key from prose --
; and everything else answers the str of its first argument.
(def %py-exc-msg
  ; WHAT str(e) IS, and Python decides it by the NUMBER of arguments: none is
  ; the empty string, one is that argument, and more than one is the whole
  ; args TUPLE -- `MyExc(100, "Some error")` prints (100, 'Some error').  A
  ; KeyError with a single argument answers its REPR instead, so that a
  ; missing string key reads as KeyError: 'z' the way it does in Python.
  (fn (_ e)
    (let ((args (%py-alist-find "args" (%py-obj-attrs e))))
      (let ((els (if (null? args) () (%py-tuple-elems (rest args)))))
        (if (null? els)
          ""
          (if (null? (rest els))
            (if (%py-subclass? (%py-obj-class e) %py-exc-KeyError)
              (%py-repr-of (first els))
              (%py-str (first els)))
            (%py-repr-of (%py-tuple-of-list els))))))))

; --- Classes -----------------------------------------------------------------
;
; Method lookup walks the base chain, which is the ONE piece of Python's object
; model that cannot be faked by a flat alist: `class Dog(Animal)` means a Dog
; finds Animal's methods, and `super`-less overriding means the derived class is
; searched first.  Attributes do not walk -- they live on the instance.

(def %py-alist-find
  (fn (self k rows)
    (if (null? rows)
      ()
      (if (Str8 =? k (first (first rows)))
        (first rows)
        (self k (rest rows))))))

; Derived first, then the base, then the base's base.
(def %py-method-find
  ; OBJECT IS CONSULTED LAST, which is where every MRO puts it.  The walk is
  ; otherwise depth first, left to right -- but depth first reaches a base's
  ; ANCESTORS before the next base, and since every class now roots at object,
  ; `class C(tuple, Base)` found object.__init__ through tuple and never asked
  ; Base at all.  Skipping object during the walk and asking it at the end is
  ; the same answer C3 gives for every shape a program without diamonds
  ; writes, at a fraction of the machinery.
  (fn (self cls name)
    (let ((m (%py-method-find-below cls name)))
      (if (null? m)
        (let ((e (%py-alist-find name (%py-class-methods %py-cls-object))))
          (if (null? e) () (rest e)))
        m))))

(def %py-method-find-below
  (fn (self cls name)
    (if (null? cls)
      ()
      (if (same? cls %py-cls-object)
        ()
        (let ((e (%py-alist-find name (%py-class-methods cls))))
          (if (null? e)
            ; DEPTH FIRST, LEFT TO RIGHT across every base: `class Sub(A, B)`
            ; finds A's method before B's, and A's own bases before B at all,
            ; which is the order Python's MRO gives for the shapes a program
            ; without diamonds writes.
            (%py-method-find-bases (%py-class-bases cls) name)
            (rest e)))))))

(def %py-method-find-bases
  (fn (self bs name)
    (if (null? bs)
      ()
      (let ((m (%py-method-find-below (first bs) name)))
        (if (null? m) (self (rest bs) name) m)))))

; A BOUND METHOD IS JUST A CLOSURE OVER THE OBJECT.  A method compiles to
; (fn (_ py-self ...) ...) -- the leading _ absorbs x's self-binding -- so
; calling it with the object as the first argument is all "bound" means.
(def %py-bind-method
  (fn (_ m obj) (fn (_ . args) (apply m (pair obj args)))))

; A USER DESCRIPTOR is any object whose class defines the hook -- Python has
; no marker interface here, only the method.  staticmethod, classmethod and
; property are this same idea with the runtime's own PY-DESC standing in for
; the object; these three predicates are what lets a program write its own.
(def %py-desc-get?
  (fn (_ v) (if (%py-obj-is v) (not (null? (%py-method-find (%py-obj-class v) "__get__"))) #f)))
(def %py-desc-set?
  (fn (_ v) (if (%py-obj-is v) (not (null? (%py-method-find (%py-obj-class v) "__set__"))) #f)))
(def %py-desc-delete?
  (fn (_ v) (if (%py-obj-is v) (not (null? (%py-method-find (%py-obj-class v) "__delete__"))) #f)))

(def %py-obj-attr
  (fn (_ obj name)
    ; __class__ is the instance's own class, which two of the corpus's
    ; descriptor tests probe before they will run at all.
    (if (Str8 =? name "__class__")
      (%py-obj-class obj)
      (let ((e (%py-alist-find name (%py-obj-attrs obj))))
        (if (not (null? e))
          (rest e)
          (let ((m (%py-method-find (%py-obj-class obj) name)))
            (match
              ((%py-desc-is m)
                (let ((f (%py-desc-fn m)) (k (%py-desc-kind m)))
                  (if (eq? k (lit static))
                    f
                    (if (eq? k (lit classmethod))
                      (%py-bind-method f (%py-obj-class obj))
                      (f obj)))))
              ; A USER DESCRIPTOR answers through its own __get__, which takes
              ; the instance and the class -- the same protocol property is a
              ; special case of.
              ((%py-desc-get? m)
                ((%py-dunder m "__get__") obj (%py-obj-class obj)))
              ((if (null? m) #f (not (%py-fn-is m))) m)
              ((null? m)
                (let ((n (%py-obj-native obj)))
                  (if (not (null? n))
                    (%py-getattr n name)
                    ; the last resort is the class's own __getattr__, as in Python
                    (let ((ga (%py-method-find (%py-obj-class obj) "__getattr__")))
                      (if (null? ga)
                        (Err raise (lit attribute)
                          (Str8 append
                            (Str8 append
                              (Str8 append "'" (%py-class-name (%py-obj-class obj)))
                              "' object has no attribute '")
                            (Str8 append name "'"))
                          ())
                        (ga obj name))))))
              (#t (%py-bind-method m obj)))))))))

; obj(...) is __call__, through the PY-OBJ type's call handler.
(set! %py-obj-call
  (fn (_ obj args)
    (let ((m (%py-dunder obj "__call__")))
      (if (null? m)
        (Err raise (lit type)
          (Str8 append (Str8 append "'" (%py-class-name (%py-obj-class obj)))
            "' object is not callable") ())
        (apply m args)))))

; Setting an attribute REPLACES the entry or appends one, and hangs the result
; back on the instance's cell so every reference sees it -- the same identity
; argument the containers needed.
(def %py-attr-put
  (fn (self rows k v)
    (if (null? rows)
      (list (pair k v))
      (if (Str8 =? k (first (first rows)))
        (pair (pair k v) (rest rows))
        (pair (first rows) (self (rest rows) k v))))))

(def %py-setattr
  (fn (_ obj name v)
    ; A CLASS TAKES A STORE TOO.  `C.x = 2` puts the row in the same alist the
    ; class body wrote, so instances see it through the lookup that already
    ; walks the class chain, and an instance attribute of the same name still
    ; shadows it -- %py-obj-attr reads the instance first.
    (if (%py-class-is obj)
      (%py-class-methods-set! obj (%py-attr-put (%py-class-methods obj) name v))
      (if (not (%py-obj-is obj))
        (Err raise (lit attribute) "object does not support attribute assignment" ())
        ; __setattr__ INTERCEPTS EVERY STORE, which is the point of it: a class
        ; that defines one decides what `self.x = v` means, and gets no default
        ; store unless it makes one itself.  __getattr__ was already a hook on
        ; the read; this is the same rule on the write.
        (let ((m (%py-dunder obj "__setattr__")))
          (if (not (null? m))
            (%seq (m name v) ())
            ; and a DESCRIPTOR on the class takes the store before the
            ; instance does, which is what makes a data descriptor data
            (let ((d (%py-method-find (%py-obj-class obj) name)))
              (if (%py-desc-set? d)
                (%seq ((%py-dunder d "__set__") obj v) ())
                (%py-obj-set-attrs! obj (%py-attr-put (%py-obj-attrs obj) name v))))))))))

; staticmethod, classmethod and property are FUNCTIONS in Python -- applying
; a decorator IS calling it -- so they are ordinary builtins here, and
; `@staticmethod` is the call the parser emits.  A user-written decorator then
; needs nothing special: it is called the same way, and whatever it answers is
; what the name becomes.
(def %py-staticmethod (fn (_ f) (%py-desc-new (lit static) f)))
(def %py-classmethod  (fn (_ f) (%py-desc-new (lit classmethod) f)))
(def %py-property     (fn (_ f) (%py-desc-new (lit property) f)))

; StopIteration CARRIES A VALUE -- what a generator returned -- and Python
; spells it as an attribute: StopIteration("x").value is "x", and with no
; argument it is None.  A property is the honest shape for something read off
; the arguments rather than stored.
; OSError's FIRST ARGUMENT IS ITS errno, read off the arguments the same way
; StopIteration reads its value; with no arguments it is None.
(%py-class-methods-set! %py-exc-OSError
  (list
    (pair "errno"
      (%py-property
        (fn (_ self)
          (let ((a (%py-alist-find "args" (%py-obj-attrs self))))
            (if (null? a)
              ()
              (let ((els (%py-tuple-elems (rest a))))
                (if (null? els) () (first els))))))))))

(%py-class-methods-set! %py-exc-StopIteration
  (list
    (pair "value"
      (%py-property
        (fn (_ self)
          (let ((a (%py-alist-find "args" (%py-obj-attrs self))))
            (if (null? a)
              ()
              (let ((els (%py-tuple-elems (rest a))))
                (if (null? els) () (first els))))))))))

; --- Modules -----------------------------------------------------------------
;
; A MODULE IS AN OBJECT of one class, and importing is looking a name up in a
; table.  There is no file system search here: this runtime runs one program,
; and the modules it can offer are the ones written below.  Everything else
; raises ImportError, which is not a limitation so much as the truth -- and it
; is what the corpus's own feature probes expect, since they wrap an import in
; a try and print SKIP when it fails.
(def %py-cls-module (%py-class-new "module" %py-cls-object () "module"))

(def %py-module-new
  (fn (_ name rows)
    (let ((m (%py-obj-new %py-cls-module)))
      (%seq (%py-obj-set-attrs! m (pair (pair "__name__" name) rows)) m))))

; The modules this runtime has, built once and remembered, so that `sys.modules`
; and repeated imports answer the same object.
(def %py-modules (list ()))

(def %py-module-find
  (fn (self name rows)
    (if (null? rows)
      ()
      (if (Str8 =? name (first (first rows)))
        (rest (first rows))
        (self name (rest rows))))))

(def %py-module-put!
  (fn (_ name m)
    (%seq (%set-first! %py-modules (pair (pair name m) (first %py-modules))) m)))

; WHAT THIS RUNTIME OFFERS, built on first import and remembered after.  sys
; is the one the corpus reaches for most: its feature probes read
; sys.implementation and sys.modules before deciding what to test.
; WHAT PLATFORM THIS IS, read off x-machine -- the build triple the platform
; layer already keys its syscalls from, e.g. "arm64-apple-darwin23.6.0" or
; "x86_64-linux-gnu".  Python's own spellings are darwin, linux and win32; a
; triple naming none of them answers ITSELF rather than a guess, which at
; least says truthfully where it ran.
; WHAT PLATFORM THIS IS, read off x-machine -- the build triple the platform
; layer already keys its syscalls from, e.g. "arm64-apple-darwin23.6.0" or
; "x86_64-linux-gnu".  The triples and Python's name for each are a TABLE, not
; a chain of near-identical tests; a triple naming none of them answers ITSELF
; rather than a guess, which at least says truthfully where it ran.
(def %py-platform-names
  (list
    (pair "darwin"  "darwin")
    (pair "linux"   "linux")
    (pair "mingw"   "win32")
    (pair "cygwin"  "win32")
    (pair "windows" "win32")))

(def %py-platform-of
  (fn (self triple rows)
    (match
      ((null? rows) triple)
      ((not (null? (Str8 index-of (first (first rows)) triple))) (rest (first rows)))
      (#t (self triple (rest rows))))))

; sys.implementation names the runtime a program is actually running on, and
; this one is not CPython.  A test that branches on it should see the truth.
(def %py-sys-implementation
  (fn (_)
    (%py-module-new "implementation"
      (list
        (pair "name" "x-python")
        (pair "_machine" x-machine)))))

; --- the math module ------------------------------------------------------
;
; Python's math is libm's surface with Python's edges: an argument may be an
; int and comes back a float, a domain error is a ValueError rather than a
; NaN, and floor/ceil/trunc answer INTS.  The platform's Float class already
; carries the libm calls, so this is the translation layer and not an
; implementation of anything numeric.
;
; NOT OFFERED: erf, erfc, gamma and lgamma.  The platform binds no libm entry
; for them, and an approximation written here would answer digits CPython does
; not -- which is worse than an AttributeError saying plainly that they are
; missing.

; --- with ------------------------------------------------------------------
;
; A CONTEXT MANAGER IS TWO METHODS.  `with X() as a:` calls __enter__ and
; binds what it answers, runs the body, and calls __exit__ afterwards -- with
; (None, None, None) when the body finished, and with the exception's class
; and instance when it did not.  An __exit__ that answers something truthy
; SWALLOWS the exception; anything else re-raises it.
;
; WHAT IS NOT MODELLED, and the same hole `finally` has (see %py-try): a
; `return`, `break` or `continue` inside the body escapes through call/cc, and
; nothing runs on the way out, so __exit__ is skipped.  The platform has no
; dynamic-wind to hang cleanup on, and inventing one here would be a second
; mechanism for something the whole runtime needs once.

; THE RECEIVER IS CHECKED BEFORE IT IS ASKED.  %py-dunder reads the class out
; of an instance, so handing it an int walks a number as though it were one --
; `with 42:` SEGFAULTED before this guard, the same shape as a shim arriving
; as a class base.
(def %py-ctx-method
  (fn (_ m name)
    (if (not (%py-obj-is m))
      (%py-ctx-error m)
      (let ((f (%py-dunder m name)))
        (if (null? f) (%py-ctx-error m) f)))))

(def %py-ctx-error
  (fn (_ m)
    (Err raise (lit type)
      (Str8 append (Str8 append "'" (%py-type-name m))
        "' object does not support the context manager protocol") ())))

(def %py-enter (fn (_ m) ((%py-ctx-method m "__enter__"))))

(def %py-exit-fn (fn (_ m) (%py-ctx-method m "__exit__")))

; the body finished: __exit__(None, None, None), and its answer is discarded
(def %py-with-normal
  (fn (_ m) (%seq ((%py-exit-fn m) () () ()) ())))

; the body raised: __exit__(type, value, None), and a truthy answer swallows it
(def %py-with-exc
  (fn (_ m e)
    (let ((r ((%py-exit-fn m)
               (%py-exc-class-of e) (%py-exc-instance-of e) ())))
      (if (%py-truthy r) () (error e)))))

; the exception as Python hands it to __exit__: an instance, whether it was
; raised from Python source (already one) or by this runtime (an Err, whose
; kind names the class it would have been -- the same bridge the except
; matcher walks, and Err carries its text as the SUBJECT).
(def %py-exc-instance-of
  (fn (_ e)
    (if (%py-obj-is e)
      e
      (%py-instantiate (%py-exc-class-of e) (list (Err subject-of e))))))

(def %py-mfloat (fn (_ x) (Float from (%py-boolnorm x))))

; a domain error is Python's, not a NaN
(def %py-mdomain
  (fn (_) (%py-raise (%py-instantiate %py-exc-ValueError (list "math domain error")))))

(def %py-mcheck
  (fn (_ v) (if (Float nan? v) (%py-mdomain) v)))

; A LOGARITHM'S DOMAIN IS THE ARGUMENT, not the answer: log(0) is -inf rather
; than NaN, so checking what came back lets it through where Python raises.
(def %py-mfinite
  (fn (_ v)
    (if (Float nan? v)
      (%py-mdomain)
      (if (Float inf? v)
        (%py-raise (%py-instantiate %py-exc-OverflowError
          (list "cannot convert float infinity to integer")))
        v))))

; AN INT IS ALREADY WHOLE, and answering it unchanged is not an optimisation
; but the only correct answer: routing 10**25 through a double loses it to
; 9.22e+18, and Python keeps the exact integer.  Everything else converts,
; refuses an infinity or a NaN, and comes back an int.
(def %py-mwhole
  (fn (_ x k)
    (let ((n (%py-boolnorm x)))
      (if (eq? (%py-num-kind n) (lit int))
        n
        (let ((v (%py-mfinite (%py-mfloat n))))
          (Float ->int
            (match
              ((eq? k (lit floor)) (Float floor v))
              ((eq? k (lit ceil)) (Float ceil v))
              (#t (Float trunc v)))))))))

(def %py-mlog-arg
  (fn (_ v)
    (if (Float < (%py-mfloat 0) v) v (%py-mdomain))))

; sinh/cosh/tanh and their inverses are not bound in the platform, and each is
; one line of the exponential that is.
(def %py-msinh
  (fn (_ x) (Float / (Float - (Float exp x) (Float exp (Float - (%py-mfloat 0) x))) (%py-mfloat 2))))
(def %py-mcosh
  (fn (_ x) (Float / (Float + (Float exp x) (Float exp (Float - (%py-mfloat 0) x))) (%py-mfloat 2))))

(def %py-mfactorial
  (fn (self n acc)
    (if (< n 2) acc (self (- n 1) (* acc n)))))

; fmod keeps the DIVIDEND's sign, which is C's rule and not Python's %
(def %py-mfmod
  (fn (_ a b)
    (if (Float = b (%py-mfloat 0))
      (%py-mdomain)
      (Float - a (Float * b (Float trunc (Float / a b)))))))

(def %py-mcopysign
  (fn (_ a b)
    (let ((m (Float abs a)))
      (if (Float < b (%py-mfloat 0)) (Float - (%py-mfloat 0) m) m))))

(def %py-mldexp
  (fn (self x n)
    (if (= n 0)
      x
      (if (> n 0)
        (self (Float * x (%py-mfloat 2)) (- n 1))
        (self (Float / x (%py-mfloat 2)) (+ n 1))))))

; isclose is Python's own formula, keywords and all
(def %py-misclose
  (fn (_ a b . kw)
    ; Python's default rel_tol, written as a division because the reader does
    ; not take 1e-9 here
    (let ((rel (%py-opt kw 0 (Float / (%py-mfloat 1) (%py-mfloat 1000000000))))
          (abs- (%py-opt kw 1 (%py-mfloat 0))))
      ; Python's rule is abs(a-b) <= max(rel_tol * max(|a|, |b|), abs_tol), and
      ; the <= is load-bearing: isclose(0.0, 0.0) is True on the equality, not
      ; on any tolerance.
      (let ((d (Float abs (Float - a b))))
        (let ((ma (Float abs a)) (mb (Float abs b)))
          (let ((t (Float * rel (if (Float < ma mb) mb ma))))
            (let ((lim (if (Float < t abs-) abs- t)))
              (if (Float < d lim) #t (Float = d lim)))))))))

(def %py-math-module
  (fn (_)
    (%py-module-new "math"
      (list
        (pair "pi" (Float pi))
        (pair "e" (Float e))
        (pair "tau" (Float tau))
        (pair "inf" (%py-float-ctor "inf"))
        (pair "nan" (%py-float-ctor "nan"))
        (pair "sqrt" (fn (_ x) (%py-mcheck (Float sqrt (%py-mfloat x)))))
        (pair "exp" (fn (_ x) (Float exp (%py-mfloat x))))
        (pair "log"
          (fn (_ x . b)
            (let ((v (Float log (%py-mlog-arg (%py-mfloat x)))))
              (if (null? b) v (Float / v (Float log (%py-mfloat (first b))))))))
        (pair "log2" (fn (_ x) (Float log2 (%py-mlog-arg (%py-mfloat x)))))
        (pair "log10" (fn (_ x) (Float log10 (%py-mlog-arg (%py-mfloat x)))))
        (pair "sin" (fn (_ x) (Float sin (%py-mfloat x))))
        (pair "cos" (fn (_ x) (Float cos (%py-mfloat x))))
        (pair "tan" (fn (_ x) (Float tan (%py-mfloat x))))
        (pair "asin" (fn (_ x) (%py-mcheck (Float asin (%py-mfloat x)))))
        (pair "acos" (fn (_ x) (%py-mcheck (Float acos (%py-mfloat x)))))
        (pair "atan" (fn (_ x) (Float atan (%py-mfloat x))))
        (pair "atan2" (fn (_ y x) (Float atan2 (%py-mfloat y) (%py-mfloat x))))
        (pair "hypot" (fn (_ a b) (Float hypot (%py-mfloat a) (%py-mfloat b))))
        (pair "pow" (fn (_ a b) (Float pow (%py-mfloat a) (%py-mfloat b))))
        (pair "fabs" (fn (_ x) (Float abs (%py-mfloat x))))
        (pair "fmod" (fn (_ a b) (%py-mfmod (%py-mfloat a) (%py-mfloat b))))
        (pair "copysign" (fn (_ a b) (%py-mcopysign (%py-mfloat a) (%py-mfloat b))))
        (pair "ldexp" (fn (_ x n) (%py-mldexp (%py-mfloat x) (%py-boolnorm n))))
        (pair "sinh" (fn (_ x) (%py-msinh (%py-mfloat x))))
        (pair "cosh" (fn (_ x) (%py-mcosh (%py-mfloat x))))
        (pair "tanh"
          (fn (_ x)
            (let ((v (%py-mfloat x)))
              (Float / (%py-msinh v) (%py-mcosh v)))))
        (pair "asinh"
          (fn (_ x)
            (let ((v (%py-mfloat x)))
              (Float log (Float + v (Float sqrt (Float + (Float * v v) (%py-mfloat 1))))))))
        (pair "acosh"
          (fn (_ x)
            (let ((v (%py-mfloat x)))
              (%py-mcheck
                (Float log (Float + v (Float sqrt (Float - (Float * v v) (%py-mfloat 1)))))))))
        (pair "atanh"
          (fn (_ x)
            (let ((v (%py-mfloat x)))
              (%py-mcheck
                (Float / (Float log (Float / (Float + (%py-mfloat 1) v)
                                             (Float - (%py-mfloat 1) v)))
                         (%py-mfloat 2))))))
        (pair "degrees"
          (fn (_ x) (Float / (Float * (%py-mfloat x) (%py-mfloat 180)) (Float pi))))
        (pair "radians"
          (fn (_ x) (Float / (Float * (%py-mfloat x) (Float pi)) (%py-mfloat 180))))
        ; floor, ceil and trunc answer INTS in Python, unlike libm's -- and an
        ; infinity has no integer to answer with (OverflowError), a NaN no
        ; value at all (ValueError)
        (pair "floor" (fn (_ x) (%py-mwhole x (lit floor))))
        (pair "ceil" (fn (_ x) (%py-mwhole x (lit ceil))))
        (pair "trunc" (fn (_ x) (%py-mwhole x (lit trunc))))
        (pair "factorial"
          (fn (_ n)
            (let ((k (%py-boolnorm n)))
              (if (< k 0) (%py-mdomain) (%py-mfactorial k 1)))))
        (pair "isnan" (fn (_ x) (Float nan? (%py-mfloat x))))
        (pair "isinf" (fn (_ x) (Float inf? (%py-mfloat x))))
        (pair "isfinite" (fn (_ x) (Float finite? (%py-mfloat x))))
        ; the keywords have to be HANDED ON: the signature declares rel_tol and
        ; abs_tol, and a wrapper that ignores them makes every tolerance the
        ; default while looking as though it took one
        (pair "isclose"
          (%py-sig! (fn (_ a b . kw) (apply %py-misclose (pair (%py-mfloat a) (pair (%py-mfloat b) kw))))
            "isclose" (list "a" "b" "rel_tol" "abs_tol") 2 #f))
        (pair "expm1" (fn (_ x) (Float - (Float exp (%py-mfloat x)) (%py-mfloat 1))))
        (pair "log1p"
          (fn (_ x) (Float log (%py-mlog-arg (Float + (%py-mfloat 1) (%py-mfloat x))))))))))

(def %py-module-build
  (fn (_ name)
    (match
      ((Str8 =? name "sys")
        (%py-module-new "sys"
                (list
                  (pair "version" "3.14.7")
                  (pair "platform" (%py-platform-of x-machine %py-platform-names))
                  ; every architecture this platform builds for is little-endian;
                  ; a big-endian port would have to say so here
                  (pair "byteorder" "little")
                  (pair "implementation" (%py-sys-implementation))
                  ; the largest int a CPython machine word holds; this runtime has
                  ; bigints and no such limit, and the number is what programs test
                  (pair "maxsize" 9223372036854775807)
                  (pair "path" (%py-list-new ()))
                  (pair "argv" (%py-list-new ()))
                  (pair "modules" (%py-dict-new ()))
                  (pair "exit"
                    (fn (_ . a)
                      (%py-raise (%py-instantiate %py-exc-SystemExit
                        (if (null? a) () (list (first a))))))))))
      ((Str8 =? name "math") (%py-math-module))
      ((Str8 =? name "builtins") (%py-module-new "builtins" ()))
      (#t ()))))

(def %py-import
  (fn (_ name)
    (if (not (str? name))
      (Err raise (lit type) "module name must be a string" ())
      (if (= (Str8 length name) 0)
        (Err raise (lit value) "empty module name" ())
        (let ((have (%py-module-find name (first %py-modules))))
          (if (not (null? have))
            have
            (let ((built (%py-module-build name)))
              (if (null? built)
                (Err raise (lit import)
                  (Str8 append (Str8 append "No module named '" name) "'") ())
                (%py-module-put! name built)))))))))

; `from X import a, b` and `from X import *` both read attributes off the
; module the same way an ordinary program would.
(def %py-import-call
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type)
        "__import__() missing required argument 'name'" ())
      (%py-import (first a)))))

(def %py-import-from
  (fn (_ name attr)
    (let ((m (%py-import name)))
      (let ((e (%py-alist-find attr (%py-obj-attrs m))))
        (if (null? e)
          (Err raise (lit import)
            (Str8 append
              (Str8 append (Str8 append "cannot import name '" attr) "' from '")
              (Str8 append name "'")) ())
          (rest e))))))

; every public name a module has, for `from X import *`
(def %py-import-star-names
  (fn (self rows acc)
    (if (null? rows)
      (%py-reverse acc)
      (let ((k (first (first rows))))
        (self (rest rows)
          (if (Str8 =? (Str8 sub 0 1 k) "_") acc (pair k acc)))))))

(def %py-mkclass
  (fn (_ name bases methods)
    ; A BASE THAT IS NOT A CLASS IS A TypeError, not a crash.  An undefined
    ; name is bound to a shim that raises when called, and a shim reaching
    ; method lookup as a base record is a walk into a closure's guts.  Every
    ; base is checked, since `class C(A, nosuch)` is the same mistake.
    (if (not (%py-all-classes? bases))
      (Err raise (lit type) "a class base must be a class" ())
      (let ((fin (%py-final-base bases)))
        (if (not (null? fin))
          (Err raise (lit type)
            (Str8 append (Str8 append "type '" (%py-class-name fin))
              "' is not an acceptable base type") ())
          ; TWO BUILTIN BASES CANNOT BE COMBINED: an instance carries ONE
          ; native value, so `class A(type, tuple)` has no answer to what it
          ; would be.  Python calls this a layout conflict and refuses it too.
          (if (> (%py-ctor-count bases 0) 1)
            (Err raise (lit type)
              "multiple bases have instance lay-out conflict" ())
            (let ((cls (%py-class-new name bases methods (Str8 append "__main__." name))))
              ; __set_name__ IS CALLED AS THE CLASS IS MADE, once per attribute
              ; that wants it, with the owner and the name it was written
              ; under -- the only moment a descriptor can learn its name.
              (%seq (%py-set-names cls methods) cls))))))))

; The first base that refuses to be one, or nil.
(def %py-final-base
  (fn (self bs)
    (if (null? bs)
      ()
      (if (null? (%py-alist-find "%final" (%py-class-methods (first bs))))
        (self (rest bs))
        (first bs)))))

; How many of these bases bring a native value with them.
(def %py-ctor-count
  (fn (self bs n)
    (if (null? bs)
      n
      (self (rest bs)
        (if (null? (%py-inherited-ctor (first bs))) n (+ n 1))))))

(def %py-set-names
  (fn (self cls rows)
    (if (null? rows)
      ()
      (let ((v (rest (first rows))))
        (%seq
          (if (%py-obj-is v)
            (let ((m (%py-dunder v "__set_name__")))
              (if (null? m) () (m cls (first (first rows)))))
            ())
          (self cls (rest rows)))))))

(def %py-all-classes?
  (fn (self bs)
    (if (null? bs)
      #t
      (if (%py-class-is (first bs)) (self (rest bs)) #f))))

; Construction: make the instance, then run __init__ if the class chain has one.
; Its return value is discarded -- Python returns the INSTANCE from a call to a
; class, whatever __init__ answers.
; A CLASS WITH A %ctor ENTRY IS ITS OWN CONSTRUCTOR.  `int('5')` must convert,
; not allocate an instance -- so the builtin type objects carry a constructor
; function under the key "%ctor", which no Python identifier can spell (method
; names come from tok-name, and % is not a name character), so a class body can
; never shadow it by accident.
(set! %py-instantiate
  (fn (_ cls args)
    (let ((ctor (%py-alist-find "%ctor" (%py-class-methods cls))))
      (if (not (null? ctor))
        (apply (rest ctor) args)
        ; __new__ MAKES the instance and __init__ fills it in.  Every class
        ; reaches object.__new__, so this path is always taken; a class that
        ; writes its own gets to answer something else entirely, and Python's
        ; rule is that __init__ runs only when what came back IS an instance
        ; of the class being called.
        (let ((nw (%py-method-find cls "__new__")))
          (let ((o (apply nw (pair cls args))))
            (if (if (%py-obj-is o) (%py-subclass? (%py-obj-class o) cls) #f)
              (%seq
                ; A SUBCLASS OF A BUILTIN carries one: the %ctor INHERITED from
                ; the builtin base builds the value from the same arguments,
                ; and the instance keeps it.  `class mylist(list)` then holds a
                ; real list, and a class whose own __init__ takes other
                ; arguments still gets an empty one to start from.
                (let ((bc (%py-inherited-ctor cls)))
                  (if (null? bc)
                    ()
                    ; THE ARGUMENTS GO TO THE CONSTRUCTOR, which is what
                    ; Python does: __new__ receives them whether or not an
                    ; __init__ exists, and that is the only way an IMMUTABLE
                    ; builtin can be built at all -- a tuple or str cannot be
                    ; filled in afterwards.  A class whose own __init__ takes
                    ; DIFFERENT arguments would make that call raise, and then
                    ; the empty value is right: its __init__ fills the
                    ; instance itself, the way list.__init__(self, xs) does.
                    (%py-obj-native! o
                      (guard (e (bc)) (apply bc args)))))
                (let ((init (%py-method-find cls "__init__")))
                  (if (null? init)
                    o
                    ; __init__ ANSWERS None, and Python raises when it does not
                    ; -- the value is not merely discarded.  A Python function
                    ; with no return already answers None here, so this catches
                    ; the written `return 10` and nothing else.
                    (let ((r (apply init (pair o args))))
                      (if (null? r)
                        o
                        (Err raise (lit type)
                          (Str8 append "__init__() should return None, not '"
                            (Str8 append (%py-type-name r) "'")) ()))))))
              o)))))))

; The %ctor a class INHERITS, if any -- the builtin base's constructor, found
; by the same base walk everything else uses.  A class of its own has none.
(def %py-inherited-ctor
  (fn (self cls)
    (if (null? cls)
      ()
      (let ((e (%py-alist-find "%ctor" (%py-class-methods cls))))
        (if (null? e)
          (%py-inherited-ctor-bases (%py-class-bases cls))
          (rest e))))))

; Does a class BELOW the builtin write its own __init__?  The walk stops at
; the class carrying the %ctor: that one and everything above it is the
; builtin's own machinery, not the program's.
(def %py-init-below-ctor?
  (fn (self cls)
    (match
      ((null? cls) #f)
      ((not (null? (%py-alist-find "%ctor" (%py-class-methods cls)))) #f)
      ((not (null? (%py-alist-find "__init__" (%py-class-methods cls)))) #t)
      (#t (%py-init-below-ctor-bases? (%py-class-bases cls))))))
(def %py-init-below-ctor-bases?
  (fn (self bs)
    (if (null? bs)
      #f
      (if (%py-init-below-ctor? (first bs)) #t (self (rest bs))))))
(def %py-inherited-ctor-bases
  (fn (self bs)
    (if (null? bs)
      ()
      (let ((c (%py-inherited-ctor (first bs))))
        (if (null? c) (self (rest bs)) c)))))

; --- Tuples ------------------------------------------------------------------

; --- Generators --------------------------------------------------------------
;
; A GENERATOR IS TWO CONTINUATIONS.  The engine's call/cc copies the C stack
; and restores it on invocation, so a continuation can be re-entered after
; the frame that captured it has gone -- and that is all a generator needs:
; `yield` captures the body's continuation (k-gen) and jumps to the
; caller's (k-caller) with the value; next()/send() capture the caller's
; continuation and jump into k-gen with what was sent.  Messages up are
; (yield v) | (return v) | (raise e); messages down are (send v) |
; (throw e).  The body runs inside ONE guard, installed on the first
; resume and part of the body's own captured stack, so an exception raised
; after any resumption is forwarded to whoever the current caller is --
; never to the stale handler of the first caller.
(def %py-gen-body   (fn (_ g) (List ref 0 (%py-gen-state g))))
(def %py-gen-name   (fn (_ g) (List ref 1 (%py-gen-state g))))
(def %py-gen-gk     (fn (_ g) (List ref 2 (%py-gen-state g))))
(def %py-gen-ck     (fn (_ g) (List ref 3 (%py-gen-state g))))
(def %py-gen-status (fn (_ g) (List ref 4 (%py-gen-state g))))
; A SUSPENDED BODY KEEPS ITS OWN WIND STACK.  The cleanup a half-run body owes
; belongs to the body, not to whoever is driving it, so it rides in the state
; across the suspension instead of sitting on the caller's stack.
(def %py-gen-winds  (fn (_ g) (List ref 5 (%py-gen-state g))))
(def %py-gen-set-gk!     (fn (_ g k) (%set-first! (rest (rest (%py-gen-state g))) k)))
(def %py-gen-set-ck!     (fn (_ g k) (%set-first! (rest (rest (rest (%py-gen-state g)))) k)))
(def %py-gen-set-status! (fn (_ g s) (%set-first! (rest (rest (rest (rest (%py-gen-state g))))) s)))
(def %py-gen-set-winds!
  (fn (_ g w) (%set-first! (rest (rest (rest (rest (rest (%py-gen-state g)))))) w)))
(def %py-gen-done (list (lit %py-gen-done)))

; a class raises as a fresh instance, an instance as itself
; throw(type, value): a value that is already an instance of the type is
; the exception itself, not a constructor argument
(def %py-exc-instance
  (fn (_ e args)
    (if (%py-class-is e)
      (if (if (null? args) #f
            (if (null? (rest args))
              (if (%py-obj-is (first args)) (%py-subclass? (%py-obj-class (first args)) e) #f)
              #f))
        (first args)
        (%py-instantiate e args))
      e)))
; raising what was thrown: a class instantiates, an instance is itself,
; anything else is Python's TypeError
(def %py-raise-any
  (fn (_ e)
    (if (if (%py-class-is e) #t (if (%py-obj-is e) (%py-subclass? (%py-obj-class e) %py-exc-Exception) #f))
      (error (%py-exc-instance e ()))
      (Err raise (lit type) "exceptions must derive from BaseException" ()))))
; is a thrown value (class or instance) of this exception class?
(def %py-thrown-is?
  (fn (_ e cls)
    (if (%py-class-is e) (%py-subclass? e cls)
      (if (%py-obj-is e) (%py-exc-match e cls) #f))))
; the body's side of a delegating yield: the raw message, (send v) | (throw e)
(def %py-yield-raw
  (fn (_ g v)
    (%py-callcc
      (fn (_ k)
        (%py-gen-set-gk! g k)
        (%py-gen-set-status! g (lit suspended))
        ((%py-gen-ck g) (list (lit yield) v))))))
; StopIteration carrying the generator's return value (none for None)
(def %py-raise-stop
  (fn (_ rv)
    (error (%py-instantiate %py-exc-StopIteration (if (null? rv) () (list rv))))))
(def %py-stop-value
  (fn (_ e)
    (if (%py-obj-is e)
      (let ((a (%py-alist-find "args" (%py-obj-attrs e))))
        (if (null? a) ()
          (let ((es (%py-tuple-elems (rest a)))) (if (null? es) () (first es)))))
      ())))

; The body's side: hand v up, wait for what comes down.
(def %py-yield
  (fn (_ g v)
    (let ((msg (%py-callcc
                 (fn (_ k)
                   (%py-gen-set-gk! g k)
                   (%py-gen-set-status! g (lit suspended))
                   ((%py-gen-ck g) (list (lit yield) v))))))
      (if (eq? (first msg) (lit throw))
        (%py-raise-any (first (rest msg)))
        (first (rest msg))))))

; First entry: run the body to its end under the forwarding guard.
(def %py-gen-run
  (fn (_ g)
    (guard (e
             (%py-gen-set-status! g (lit done))
             ((%py-gen-ck g) (list (lit raise) e)))
      (let ((rv ((%py-gen-body g) g)))
        (%py-gen-set-status! g (lit done))
        ((%py-gen-ck g) (list (lit return) rv))))))

; The caller's side: mode is send or throw; answers the yielded value, or
; raises StopIteration (with the return value) or the body's exception.
(def %py-gen-resume
  (fn (_ g mode v)
    (def st (%py-gen-status g))
    (if (eq? st (lit done))
      (if (eq? mode (lit throw)) (%py-raise-any v) (%py-raise-stop ()))
    (if (eq? st (lit running))
      (Err raise (lit value) "generator already executing" ())
      (do
        (if (if (eq? st (lit created)) (if (eq? mode (lit send)) (not (null? v)) #f) #f)
          (Err raise (lit type) "can't send non-None value to a just-started generator" ())
          ())
        (if (if (eq? st (lit created)) (eq? mode (lit throw)) #f)
          (do (%py-gen-set-status! g (lit done)) (%py-raise-any v))
          ; ACROSS THE BOUNDARY THE WIND STACK IS SWAPPED, not shared: the body
          ; runs owing what the body owes, and hands it back unpaid when it
          ; suspends.  Without this a `yield` out of a try/finally would leave
          ; the body's cleanup sitting on the CALLER's stack, where the
          ; caller's next escape would run it -- early, and in the wrong frame.
          (let ((winds (first %py-winds)))
            (let ((r (%py-callcc
                       (fn (_ k)
                         (%py-gen-set-ck! g k)
                         (%py-gen-set-status! g (lit running))
                         (%set-first! %py-winds (%py-gen-winds g))
                         (if (eq? st (lit created))
                           (%py-gen-run g)
                           ((%py-gen-gk g) (list mode v)))))))
              (do
                ; control is back on this side, so what the global holds now is
                ; whatever the body left owing
                (%py-gen-set-winds! g (first %py-winds))
                (%set-first! %py-winds winds)
                (if (eq? (first r) (lit yield))
                  (first (rest r))
                  (if (eq? (first r) (lit return))
                    (%py-raise-stop (first (rest r)))
                    (error (first (rest r))))))))))))))

; next(g) with the StopIteration turned into the done sentinel
(def %py-gen-pull
  (fn (_ g)
    (if (eq? (%py-gen-status g) (lit done))
      %py-gen-done
      (guard (e (if (%py-exc-match e %py-exc-StopIteration) %py-gen-done (error e)))
        (%py-gen-resume g (lit send) ())))))
(def %py-gen-drain
  (fn (self g acc)
    (let ((v (%py-gen-pull g)))
      (if (same? v %py-gen-done) (%py-reverse acc) (self g (pair v acc))))))

; close(): throw GeneratorExit in; a body that swallows it and yields again
; is the RuntimeError, one that ends (either way) is fine
(def %py-gen-close
  (fn (_ g)
    (let ((st (%py-gen-status g)))
      (if (if (eq? st (lit created)) #t (eq? st (lit done)))
        (%seq (%py-gen-set-status! g (lit done)) ())
        (guard (e (if (if (%py-exc-match e %py-exc-GeneratorExit) #t
                          (%py-exc-match e %py-exc-StopIteration))
                    ()
                    (error e)))
          (%py-gen-resume g (lit throw) (%py-instantiate %py-exc-GeneratorExit ()))
          (error (%py-instantiate %py-exc-RuntimeError (list "generator ignored GeneratorExit"))))))))

(def %py-gen-attr
  (fn (_ g name)
    (match
      ((Str8 =? name "__next__") (fn (_) (%py-gen-resume g (lit send) ())))
      ((Str8 =? name "send") (fn (_ v) (%py-gen-resume g (lit send) v)))
      ((Str8 =? name "throw")
        (fn (_ e . a)
          (%py-gen-resume g (lit throw)
            (if (if (null? a) #t (if (null? (rest a)) (null? (first a)) #f)) e (%py-exc-instance e a)))))
      ((Str8 =? name "close") (fn (_) (%py-gen-close g)))
      ((Str8 =? name "__iter__") (fn (_) g))
      ((Str8 =? name "__name__") (%py-gen-name g))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'generator' object has no attribute '" name) "'") ())))))

; yield from: a generator is driven send/throw for send/throw, and its
; return value is the expression's value; any other iterable is yielded
; through element by element.
(def %py-yield-from
  (fn (_ g it)
    (if (not (%py-gen-is it))
      (let ((nx (if (%py-obj-is it) (%py-dunder it "__next__") ())))
        (if (null? nx)
          (do
            (def go (fn (self es) (if (null? es) () (%seq (%py-yield g (first es)) (self (rest es))))))
            (go (%py-iter-elems it))
            ())
          ; PEP 380 on a duck-typed iterator: __next__ for None, send() for a
          ; value when it has one, throw() when it has one, StopIteration's
          ; value is the result
          (do
            (def snd (%py-dunder it "send"))
            (def thr (%py-dunder it "throw"))
            (def cls (%py-dunder it "close"))
            (def step
              (fn (self mode v)
                (let ((r (guard (e (if (%py-exc-match e %py-exc-StopIteration)
                                     (list (lit stop) (%py-stop-value e))
                                     (error e)))
                           (list (lit got)
                             (if (eq? mode (lit throw))
                               (if (null? thr) (%py-raise-any v) (thr v))
                               (if (if (null? v) #t (null? snd)) (nx) (snd v)))))))
                  (if (eq? (first r) (lit stop))
                    (first (rest r))
                    (let ((down (%py-yield-raw g (first (rest r)))))
                      (if (if (eq? (first down) (lit throw))
                            (%py-thrown-is? (first (rest down)) %py-exc-GeneratorExit) #f)
                        (%seq (if (null? cls) () (cls)) (%py-raise-any (first (rest down))))
                        (self (first down) (first (rest down)))))))))
            (step (lit send) ()))))
      (do
        (def step
          (fn (self mode v)
            (let ((r (guard (e (if (%py-exc-match e %py-exc-StopIteration)
                                 (list (lit stop) (%py-stop-value e))
                                 (error e)))
                       (list (lit got) (%py-gen-resume it mode v)))))
              (if (eq? (first r) (lit stop))
                (first (rest r))
                (let ((down (%py-yield-raw g (first (rest r)))))
                  ; PEP 380: a GeneratorExit thrown into the delegator closes
                  ; the sub-generator and is raised in the delegator itself
                  (if (if (eq? (first down) (lit throw))
                        (%py-thrown-is? (first (rest down)) %py-exc-GeneratorExit) #f)
                    (%seq (%py-gen-close it) (%py-raise-any (first (rest down))))
                    (self (first down) (first (rest down)))))))))
        (step (lit send) ())))))

; `is`: identity, with the cases Python's caching makes look like identity --
; None, True and False are singletons, small ints and interned strings
; compare equal -- stated as equality for ints and strings.
(def %py-is
  (fn (_ a b)
    (match
      ((same? a b) #t)
      ((null? a) (null? b))
      ((if (eq? a #t) #t (eq? a #f)) (eq? a b))
      ((if (null? b) #t (if (eq? b #t) #t (eq? b #f))) #f)
      ((if (str? a) (str? b) #f) (Str8 =? a b))
      ((if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
        (= a b))
      (#t #f))))

; sum(iterable[, start]) -- NOT %py-sum, which is the parser's arithmetic level
(def %py-builtin-sum
  (fn (_ it . st)
    (def go (fn (self es acc) (if (null? es) acc (self (rest es) (%py-add acc (first es))))))
    (go (%py-iter-elems it) (if (null? st) 0 (first st)))))

; map(f, it) is LAZY -- a generator pulling from its source -- so a
; StopIteration raised by f ends it where a yield from expects
; APPLY WANTS A CLOSURE: a class is called through its own door, so
; map(tuple, ...) and sorted(key=SomeClass) work like any other callable.
(def %py-apply-any
  (fn (_ f args)
    (if (%py-class-is f)
      (%py-instantiate f args)
      (if (%py-obj-is f)
        (let ((m (%py-dunder f "__call__")))
          (if (null? m) (Err raise (lit type) "object is not callable" ()) (apply m args)))
        (apply f args)))))

; map(f, a, b, ...) walks the sources in step and stops with the shortest
(def %py-pull-all
  (fn (self srcs acc)
    (if (null? srcs) (%py-reverse acc)
      (let ((v (%py-iter-pull! (first srcs))))
        (if (same? v %py-gen-done) %py-gen-done (self (rest srcs) (pair v acc)))))))
(def %py-map
  (fn (_ f . its)
    (%py-gen-new
      (fn (_ g)
        (def srcs (%py-open-all its ()))
        (def go
          (fn (self)
            (let ((vs (%py-pull-all srcs ())))
              (if (same? vs %py-gen-done) ()
                (%seq (%py-yield g (%py-apply-any f vs)) (self))))))
        (go))
      "map")))
(def %py-open-all
  (fn (self its acc)
    (if (null? its) (%py-reverse acc) (self (rest its) (pair (%py-iter-open (first its)) acc)))))
(def %py-zip
  (fn (_ . its)
    (def lists (fn (self l) (if (null? l) () (pair (%py-iter-elems (first l)) (self (rest l))))))
    (def go
      (fn (self ls acc)
        (if (if (null? ls) #t (%py-any-null? ls))
          (%py-list-new (%py-reverse acc))
          (self (%py-rests ls) (pair (%py-tuple-new (%py-firsts ls)) acc)))))
    (go (lists its) ())))
(def %py-any-null? (fn (self ls) (if (null? ls) #f (if (null? (first ls)) #t (self (rest ls))))))
(def %py-firsts (fn (self ls) (if (null? ls) () (pair (first (first ls)) (self (rest ls))))))
(def %py-rests (fn (self ls) (if (null? ls) () (pair (rest (first ls)) (self (rest ls))))))
(def %py-all
  (fn (_ it)
    (def go (fn (self es) (if (null? es) #t (if (%py-truthy (first es)) (self (rest es)) #f))))
    (go (%py-iter-elems it))))
(def %py-any
  (fn (_ it)
    (def go (fn (self es) (if (null? es) #f (if (%py-truthy (first es)) #t (self (rest es))))))
    (go (%py-iter-elems it))))
; sorted(it): a stable merge sort on %py-lt
(def %py-msort
  (fn (self l)
    (if (if (null? l) #t (null? (rest l))) l
      (let ((h (%py-split-half l (%py-length l))))
        (%py-merge (self (first h)) (self (rest h)))))))
(def %py-split-half
  (fn (_ l n)
    (def go (fn (self k xs acc) (if (= k 0) (pair (%py-reverse acc) xs) (self (- k 1) (rest xs) (pair (first xs) acc)))))
    (go (Num quotient n 2) l ())))
(def %py-merge
  (fn (self a b)
    (match
      ((null? a) b)
      ((null? b) a)
      ((%py-truthy (%py-lt (first b) (first a)))
        (pair (first b) (self a (rest b))))
      (#t (pair (first a) (self (rest a) b))))))
(def %py-msort-by
  (fn (self l key)
    (if (if (null? l) #t (null? (rest l))) l
      (let ((h (%py-split-half l (%py-length l))))
        (%py-merge-by (self (first h) key) (self (rest h) key) key)))))
(def %py-merge-by
  (fn (self a b key)
    (match
      ((null? a) b)
      ((null? b) a)
      ((%py-truthy (%py-lt (key (first b)) (key (first a))))
        (pair (first b) (self a (rest b) key)))
      (#t (pair (first a) (self (rest a) b key))))))
(def %py-ident (fn (_ v) v))
(def %py-sorted
  (%py-sig!
    (fn (_ it . a)
      (if (= (%py-length a) 1)
        (Err raise (lit type) "sorted expected 1 argument, got 2" ())
        (let ((key (%py-opt a 0 ())) (rev (%py-opt a 1 #f)))
          (let ((l (%py-msort-by (%py-iter-elems it) (if (null? key) %py-ident key))))
            (%py-list-new (if (%py-truthy rev) (%py-reverse l) l))))))
    "sorted" (list "iterable" "key" "reverse") 1 #f))

; next(it[, default]) and iter(x)
(def %py-next
  (fn (_ it . d)
    (def pull
      (fn (_)
        (if (%py-gen-is it)
          (%py-gen-resume it (lit send) ())
          (if (%py-obj-is it)
            (let ((m (%py-dunder it "__next__")))
              (if (null? m) (Err raise (lit type) "object is not an iterator" ()) (m)))
            (Err raise (lit type) "object is not an iterator" ())))))
    (if (null? d)
      (pull)
      (guard (e (if (%py-exc-match e %py-exc-StopIteration) (first d) (error e)))
        (pull)))))
(def %py-iter
  (fn (_ v)
    (if (%py-gen-is v) v
      (if (%py-obj-is v)
        (let ((m (%py-dunder v "__iter__")))
          (if (null? m) (Err raise (lit type) "object is not iterable" ()) (m)))
        (%py-gen-new (fn (_ g) (%py-yield-from g v)) "iterator")))))

; A for loop PULLS: a generator one value per iteration (its prints
; interleave with the body's, and it may be infinite), anything else from
; its materialized element list.
(def %py-iter-open
  (fn (_ v)
    (if (%py-gen-is v) v
      (if (%py-obj-is v)
        ; an object with __iter__ whose iterator has __next__ is pulled a
        ; step at a time too, so a __next__ that prints or raises does so
        ; in step with the loop body
        (let ((it-m (%py-dunder v "__iter__")))
          (if (null? it-m)
            (pair (%py-iter-elems v) ())
            (let ((it (it-m)))
              (let ((nx (if (%py-obj-is it) (%py-dunder it "__next__") ())))
                (if (null? nx)
                  (pair (%py-iter-elems v) ())
                  (list (lit %py-cursor) nx))))))
        (pair (%py-iter-elems v) ())))))
(def %py-iter-pull!
  (fn (_ src)
    (match
      ((%py-gen-is src) (%py-gen-pull src))
      ((eq? (first src) (lit %py-cursor))
        (guard (e (if (%py-exc-match e %py-exc-StopIteration) %py-gen-done (error e)))
          ((first (rest src)))))
      ((null? (first src)) %py-gen-done)
      (#t
        (let ((v (first (first src)))) (%set-first! src (rest (first src))) v)))))

(def %py-mktuple (fn (_ . elems) (%py-tuple-new elems)))
; A *rest parameter arrives as an x list and becomes the tuple Python hands
; the function; a *spread at a call site concatenates argument segments.
(def %py-tuple-of-list (fn (_ l) (%py-tuple-new l)))

; --- Keyword calls -----------------------------------------------------------
;
; A PYTHON FUNCTION IS A PLAIN x CLOSURE, and a closure does not know its
; parameter names.  So every def registers its signature here, keyed by the
; closure itself -- (name names nreq has-rest) -- and a keyword call looks it
; up, arranges the keywords into positional slots, and applies.  A slot left
; empty between given arguments carries %py-dflt, which the callee's %py-opt
; prelude reads as "take the default".
(def %py-sig-of
  (fn (_ f)
    (def go
      (fn (self rows)
        (if (null? rows) ()
          ; same?, NOT eq?: eq? compares the value slot, and every closure's
          ; is the same, so eq? calls any two functions equal
          (if (same? (first (first rows)) f) (rest (first rows)) (self (rest rows))))))
    (go (first %py-sigs))))
; a method's signature seen from its object: self is already supplied
(def %py-sig-shift
  ; A METHOD'S SIGNATURE WITHOUT ITS self, for a call through the class.  The
  ; **name travels with it: dropping the field here is how `C(1, k=2)` came
  ; back saying __init__ got an unexpected keyword argument it had declared.
  (fn (_ sig)
    (list (first sig) (rest (List ref 1 sig)) (- (List ref 2 sig) 1)
      (List ref 3 sig)
      (if (> (%py-length sig) 4) (List ref 4 sig) ()))))
(def %py-drop
  (fn (self l k) (if (= k 0) l (if (null? l) () (self (rest l) (- k 1))))))
(def %py-list-cat
  (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b)))))
; f() takes from NREQ to N positional arguments but M were given
(def %py-arity!
  (fn (_ fname more nreq ndflts)
    (if (> (%py-length more) ndflts)
      (Err raise (lit type)
        (Str8 append
          (Str8 append
            (Str8 append (Str8 append fname "() takes from ") (%py-str nreq))
            (Str8 append " to " (%py-str (+ nreq ndflts))))
          (Str8 append
            (Str8 append " positional arguments but " (%py-str (+ nreq (%py-length more))))
            " were given"))
        ())
      ())))
(def %py-kw-error
  (fn (_ fname msg)
    (Err raise (lit type) (Str8 append (Str8 append fname "() ") msg) ())))
(def %py-kw-args
  (fn (_ sig pos kws)
    (def fname (first sig))
    (def names (List ref 1 sig))
    (def nreq (List ref 2 sig))
    (def has-rest (List ref 3 sig))
    ; the **name this function declares, if it declares one
    (def kwname (if (> (%py-length sig) 4) (List ref 4 sig) ()))
    (def n (%py-length names))
    (def npos (%py-length pos))
    (def known?
      (fn (self k ns)
        (if (null? ns) #f (if (Str8 =? k (first ns)) #t (self k (rest ns))))))
    (def check
      (fn (self ks)
        (match
          ((null? ks) ())
          ((known? (first (first ks)) names) (self (rest ks)))
          ; A FUNCTION THAT DECLARES **kwargs TAKES THE REST rather than
          ; refusing them, which is the whole point of declaring it.
          ((null? kwname)
            (%py-kw-error fname
              (Str8 append (Str8 append "got an unexpected keyword argument '" (first (first ks))) "'")))
          (#t (self (rest ks))))))
    ; the keywords no parameter claimed, as dict rows
    (def spare
      (fn (self ks acc)
        (if (null? ks)
          (%py-reverse acc)
          (if (known? (first (first ks)) names)
            (self (rest ks) acc)
            (self (rest ks) (pair (pair (first (first ks)) (rest (first ks))) acc))))))
    (def slot
      (fn (_ i)
        (let ((nm (List ref i names)))
          (let ((kw (%py-alist-find nm kws)))
            (if (null? kw)
              (if (< i npos)
                (List ref i pos)
                (if (< i nreq)
                  (%py-kw-error fname
                    (Str8 append (Str8 append "missing 1 required positional argument: '" nm) "'"))
                  %py-dflt))
              (if (< i npos)
                (%py-kw-error fname
                  (Str8 append (Str8 append "got multiple values for argument '" nm) "'"))
                (rest kw)))))))
    (def build
      (fn (self i acc)
        (if (>= i n) (%py-reverse acc) (self (+ i 1) (pair (slot i) acc)))))
    (check kws)
    (if (if (> npos n) (not has-rest) #f)
      (%py-kw-error fname
        (Str8 append
          (Str8 append (Str8 append "takes " (%py-str n)) " positional arguments but ")
          (Str8 append (%py-str npos) " were given")))
      (let ((base (%py-list-cat (build 0 ()) (%py-drop pos n))))
        (if (null? kwname)
          base
          ; the box goes LAST, where the binder reads it
          (%py-list-cat base (list (%py-kwbox (%py-dict-new (spare kws ()))))))))))
; The keyword list a call sends, with every `**d` merged onto what was written
; by name.  A later spelling wins, which is what Python does when a name is
; given twice by different spellings.
(def %py-kw-spread
  (fn (_ written dicts)
    (%py-kw-spread-go written dicts)))
(def %py-kw-spread-go
  (fn (self acc dicts)
    (if (null? dicts)
      acc
      (self (%py-kw-put-rows acc (%py-dict-entries (first dicts))) (rest dicts)))))
(def %py-kw-put-rows
  (fn (self acc rows)
    (if (null? rows)
      acc
      (let ((k (first (first rows))))
        (if (not (str? k))
          (Err raise (lit type) "keywords must be strings" ())
          (self (%py-attr-put acc k (rest (first rows))) (rest rows)))))))

(def %py-kwcall
  (fn (_ f pos kws)
    (match
      ((same? f %py-print) (%py-print-kw pos kws))
      ((if (same? f %py-min) #t (same? f %py-max)) (%py-minmax-kw f pos kws))
      ; dict(a=1): the keywords are the entries
      ((same? f %py-cls-dict)
        (let ((d (if (null? pos) (%py-dict-new ()) (%py-dict-ctor (first pos)))))
          (%seq (%py-dict-merge! d (%py-dict-new (%py-dict-kwargs kws))) d)))
      ((%py-class-is f)
        (let ((ctor (%py-alist-find "%ctor" (%py-class-methods f))))
          (let ((csig (if (null? ctor) () (%py-sig-of (rest ctor)))))
            (if (not (null? csig))
              (apply (rest ctor) (%py-kw-args csig pos kws))
              (let ((init (%py-method-find f "__init__")))
                (let ((sig (if (null? init) () (%py-sig-of init))))
                  (if (null? sig)
                    (Err raise (lit type)
                      (Str8 append (%py-class-name f) "() takes no keyword arguments") ())
                    ; the class's own call door, not apply: apply wants a closure
                    (%py-instantiate f (%py-kw-args (%py-sig-shift sig) pos kws)))))))))
      (#t
        (let ((sig (%py-sig-of f)))
          (if (null? sig)
            (Err raise (lit type) "this callable takes no keyword arguments" ())
            (apply f (%py-kw-args sig pos kws))))))))
; the str methods that take keywords, and their parameter names; a slot a
; keyword call leaves empty is None, which is every one of these defaults
(def %py-str-kw-names
  (fn (_ name)
    (if (if (Str8 =? name "split") #t (Str8 =? name "rsplit")) (list "sep" "maxsplit")
      (if (Str8 =? name "splitlines") (list "keepends")
        ()))))
(def %py-none-holes
  (fn (self l)
    (if (null? l) () (pair (if (same? (first l) %py-dflt) () (first l)) (self (rest l))))))
(def %py-kwcall-attr
  (fn (_ obj name pos kws)
    ; d.update(a=1) merges the keywords
    (match
      ((if (%py-dict? obj) (Str8 =? name "update") #f)
        (let ((d obj))
          (%seq (if (null? pos) () (%py-dict-merge! d (first pos)))
            (%py-dict-merge! d (%py-dict-new (%py-dict-kwargs kws))))))
      ((%py-list? obj)
        (let ((names (%py-list-kw-names name)))
          (if (null? names)
            (Err raise (lit type)
              (Str8 append (Str8 append "list." name) "() takes no keyword arguments") ())
            (apply (%py-list-attr obj name)
              (%py-none-holes (%py-kw-args (list (Str8 append "list." name) names 0 #f) pos kws))))))
      ((str? obj)
        (if (Str8 =? name "format")
          (%py-strformat-kw obj pos kws)
          (let ((names (%py-str-kw-names name)))
            (if (null? names)
              (Err raise (lit type)
                (Str8 append (Str8 append "str." name) "() takes no keyword arguments") ())
              (apply (%py-str-attr obj name)
                (%py-none-holes
                  (%py-kw-args (list (Str8 append "str." name) names 0 #f) pos kws)))))))
      ((%py-obj-is obj)
        (let ((m (%py-method-find (%py-obj-class obj) name)))
          (let ((sig (if (null? m) () (%py-sig-of m))))
            (if (null? sig)
              (%py-kwcall (%py-getattr obj name) pos kws)
              (apply m (pair obj (%py-kw-args (%py-sig-shift sig) pos kws)))))))
      ; SUPER HAS TO BE ASKED THE SAME WAY.  Reaching it through %py-getattr
      ; answers a BOUND method, and a bound method is a new closure with no
      ; signature of its own -- so `super().__init__(**kw)` came back saying
      ; the callable takes no keyword arguments, which it plainly did.
      ((%py-super-is obj)
        (let ((m (%py-method-find (%py-class-base (%py-super-from obj)) name)))
          (let ((sig (if (null? m) () (%py-sig-of m))))
            (if (null? sig)
              (%py-kwcall (%py-getattr obj name) pos kws)
              (apply m
                (pair (%py-super-self obj)
                  (%py-kw-args (%py-sig-shift sig) pos kws)))))))
      (#t (%py-kwcall (%py-getattr obj name) pos kws)))))
(def %py-splat
  (fn (_ . segs)
    (def cat
      (fn (self ss)
        (if (null? ss) ()
          (if (null? (first ss)) (self (rest ss))
            (pair (first (first ss)) (self (pair (rest (first ss)) (rest ss))))))))
    (cat segs)))
(def %py-tuple? (fn (_ v) (%py-tuple-is v)))

; UNPACKING IS A LENGTH CHECK AND A WALK.  `a, b = f()` is the reason tuples
; earn their keep -- it is how a Python function returns two things -- and
; Python is strict about the count, because a silent short walk would bind a
; name to None and fail somewhere else entirely.
(def %py-unpack-count
  (fn (self v)
    (if (%py-tuple-is v)
      (%py-length (%py-tuple-elems v))
      (if (%py-list? v)
        (%py-length (%py-list-elems v))
        (Err raise (lit type) "cannot unpack non-sequence" ())))))

(def %py-unpack
  (fn (_ v n)
    (let ((got (%py-unpack-count v)))
      (match
        ((< got n) (Err raise (lit value) "not enough values to unpack" ()))
        ((> got n) (Err raise (lit value) "too many values to unpack" ()))
        ((%py-tuple-is v) (%py-tuple-elems v))
        (#t (%py-list-elems v))))))

; --- super() -----------------------------------------------------------------
;
; `super()` STARTS FROM THE CLASS THE METHOD WAS WRITTEN IN, not from the
; instance's class.  That is Python's rule and it is not a detail: in
;
;   class Dog(Animal):
;       def speak(self): return super().speak()
;
; the instance is a Dog, so looking up `speak` from the instance's class finds
; Dog's own override and calls it again -- forever.  Starting from Dog and
; searching its BASE finds Animal's.
;
; The parser supplies the class, because Python's zero-argument `super()` is
; LEXICAL: it means the class whose body the call is written in.  Nothing about
; the object at run time can tell you that, which is why CPython gives methods a
; `__class__` cell rather than working it out from `self`.
(def %py-super
  (fn (_ cls obj)
    (if (not (%py-class-is cls))
      (Err raise (lit type) "super(): no class" ())
      (%py-super-new cls obj))))

(def %py-super-attr
  (fn (_ sup name)
    (let ((base (%py-class-base (%py-super-from sup))))
      (if (null? base)
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'super' object has no attribute '" name) "'")
          ())
        (let ((m (%py-method-find base name)))
          (match
            ((null? m)
              (Err raise (lit attribute)
                (Str8 append
                  (Str8 append "'super' object has no attribute '" name) "'")
                ()))
            ; WHAT COMES BACK THROUGH super IS WHAT COMES BACK THROUGH THE
            ; INSTANCE: a class ATTRIBUTE is its value, not a method to bind --
            ; `super().bar` where bar = 123 answered #<fn> before, because
            ; everything found was bound.  The three built-in descriptors keep
            ; their meanings here too.
            ((%py-desc-is m)
              (let ((f (%py-desc-fn m)) (k (%py-desc-kind m)))
                (if (eq? k (lit static))
                  f
                  (if (eq? k (lit classmethod))
                    (%py-bind-method f (%py-obj-class (%py-super-self sup)))
                    (f (%py-super-self sup))))))
            ((%py-desc-get? m)
              ((%py-dunder m "__get__")
                (%py-super-self sup) (%py-obj-class (%py-super-self sup))))
            ((not (%py-fn-is m)) m)
            (#t (%py-bind-method m (%py-super-self sup)))))))))

; --- Builtins that render ----------------------------------------------------
;
; `str` and `repr` need a value AS A STRING, and %py-write only emits -- the
; comment above it says so, and says why: rendering a number would need a
; number-to-string conversion this layer does not have.
;
; It does not need one.  `(prim-ref 'io 'write-to-str)` runs the writer with its
; sink redirected into a string, so a container's write handler -- and the
; callback into %py-write it makes for each element -- lands in the string
; instead of on stdout.  Nested containers come out right for free, because the
; same handlers do the same work.
;
; STRINGS ARE THE EXCEPTION, both ways.  x writes a string with double quotes;
; Python's repr uses single, and its str uses none at all.  That difference is
; the whole distinction between the two builtins, so it is stated here rather
; than pushed into the writer.
(def %py-write-to-str (prim-ref (lit io) (lit write-to-str)))

(def %py-str
  (fn (_ v)
    (match
      ((str? v) v)
      ((null? v) "None")
      ((eq? v #t) "True")
      ((eq? v #f) "False")
      ((%py-float-is v) (%py-frepr v))
      ((%py-complex-is v) (%py-crepr v))
      ; str(e) is the MESSAGE, the same rule %py-write states for print(e)
      ((Err err? v) (v msg))
      ((%py-obj-is v) (%py-obj-str v))
      (#t (%py-write-to-str v)))))

; A STRING'S repr IS PYTHON'S: single quotes unless the text holds a single
; quote and no double, backslash and the chosen quote escaped, \n \r \t by
; name, any other control character (and DEL) as \xhh, everything else as
; itself -- non-ASCII bytes pass through untouched, which is Python 3's
; choice for printable text.
(def %py-hex2
  (fn (_ n) (Str8 append (Str8 sub (Num quotient n 16) 1 "0123456789abcdef") (Str8 sub (Num modulo n 16) 1 "0123456789abcdef"))))
(def %py-str-repr
  (fn (_ s)
    (def n (Str8 length s))
    (def q (if (if (not (null? (Str8 index-of "'" s))) (null? (Str8 index-of "\"" s)) #f) 34 39))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-char-code (%str-ref s i))))
            (self (+ i 1)
              (Str8 append acc
                (match
                  ((= c 92) "\\\\")
                  ((= c q) (Str8 append "\\" (Str8 sub i 1 s)))
                  ((= c 10) "\\n")
                  ((= c 13) "\\r")
                  ((= c 9) "\\t")
                  ((if (< c 32) #t (= c 127))
                    (Str8 append "\\x" (%py-hex2 c)))
                  (#t (Str8 sub i 1 s)))))))))
    (let ((qs (Str8 sub (if (= q 34) 1 0) 1 "'\"")))
      (Str8 append qs (Str8 append (go 0 "") qs)))))

(def %py-repr-of
  (fn (_ v)
    (match
      ((null? v) "None")
      ((eq? v #t) "True")
      ((eq? v #f) "False")
      ((str? v) (%py-str-repr v))
      ((%py-float-is v) (%py-frepr v))
      ((%py-complex-is v) (%py-crepr v))
      ((%py-obj-is v) (%py-obj-repr v))
      ((eq? v %py-Ellipsis) "Ellipsis")
      (#t (%py-write-to-str v)))))

; str(o) and repr(o) for an object: __str__ (falling back to __repr__) and
; __repr__, each answering a string; an exception instance's str is its
; message; the default is the <qualname object> form.
(def %py-obj-default-repr
  (fn (_ o)
    (if (%py-subclass? (%py-obj-class o) %py-exc-BaseException)
      (Str8 append (%py-class-name (%py-obj-class o))
        (Str8 append ": " (%py-exc-msg o)))
      (let ((n (%py-obj-native o)))
        (if (null? n)
          (Str8 append "<" (Str8 append (%py-class-qualname (%py-obj-class o)) " object>"))
          (%py-repr-of n))))))
(def %py-obj-repr
  (fn (_ o)
    (let ((m (%py-dunder o "__repr__")))
      (if (null? m) (%py-obj-default-repr o) (m)))))
(def %py-obj-str
  (fn (_ o)
    (let ((m (%py-dunder o "__str__")))
      (if (not (null? m))
        (m)
        (let ((r (%py-dunder o "__repr__")))
          (if (not (null? r))
            (r)
            (if (%py-subclass? (%py-obj-class o) %py-exc-Exception)
              (%py-exc-msg o)
              (%py-obj-default-repr o))))))))

; `list(x)` takes anything iterable, which is exactly what `for` already asks
; for -- so it is the same function, wrapped.
; --- More builtins -----------------------------------------------------------
;
; bin/hex/oct share the format engine's base conversion, so the digits and
; the bigint path are stated once.  The SIGN GOES BEFORE THE PREFIX:
; bin(-15) is -0b1111, not 0b-1111.
(def %py-based-str
  (fn (_ v base tbl pfx)
    (if (not (eq? (%py-num-kind (%py-boolnorm v)) (lit int)))
      (Err raise (lit type) "an integer is required" ())
      (let ((m (%py-fmt-base (%py-boolnorm v) base tbl)))
        (Str8 append (if (first m) "-" "") (Str8 append pfx (rest m)))))))
(def %py-bin (fn (_ v) (%py-based-str v 2 "01" "0b")))
(def %py-hex (fn (_ v) (%py-based-str v 16 "0123456789abcdef" "0x")))
(def %py-oct (fn (_ v) (%py-based-str v 8 "01234567" "0o")))

(def %py-num? (fn (_ v) (not (null? (%py-num-kind (%py-boolnorm v))))))
(def %py-divmod
  (fn (_ a b)
    (if (if (%py-num? a) (%py-num? b) #f)
      (%py-tuple-new (list (%py-floordiv a b) (%py-mod a b)))
      (Err raise (lit type) "unsupported operand type(s) for divmod()" ()))))

; A CLOSURE HAS NO PREDICATE, so its type handle is taken from one built
; here and compared -- the same trick the arithmetic seams use for float.
(def %py-th-fn (%py-typeof-prim (fn (_) ())))
(def %py-fn-is (fn (_ v) (eq? (%py-typeof-prim v) %py-th-fn)))
(def %py-callable
  (fn (_ v)
    (match
      ((%py-fn-is v) #t)
      ((%py-class-is v) #t)
      ((%py-obj-is v) (not (null? (%py-dunder v "__call__"))))
      (#t #f))))

; id() is an IDENTITY TABLE, not an address: the engine hands out no
; addresses, and what Python promises is only that the number is unique and
; stable while the object lives.  Values are compared with same?, so two
; equal lists get two ids and one list gets one.
(def %py-ids (pair () ()))
(def %py-id
  (fn (_ v)
    (def go
      (fn (self rows)
        (if (null? rows) ()
          (if (same? (first (first rows)) v) (rest (first rows)) (self (rest rows))))))
    (let ((found (go (first %py-ids))))
      (if (not (null? found))
        found
        (let ((n (+ 4300000000 (* 16 (%py-length (first %py-ids))))))
          (%seq (%set-first! %py-ids (pair (pair v n) (first %py-ids))) n))))))

; getattr's default catches ONLY AttributeError, as in Python
(def %py-attr-name!
  (fn (_ n)
    (if (str? n) n (Err raise (lit type) "attribute name must be string" ()))))
(def %py-getattr3
  (fn (_ o n . d)
    (%py-attr-name! n)
    (if (null? d)
      (%py-getattr o n)
      (guard (e (if (%py-exc-match e %py-exc-AttributeError) (first d) (error e)))
        (%py-getattr o n)))))
(def %py-setattr3
  (fn (_ o n v)
    (%py-attr-name! n)
    (if (%py-obj-is o)
      (%py-setattr o n v)
      (Err raise (lit attribute) "object has no settable attributes" ()))))
(def %py-delattr
  (fn (_ o n)
    (%py-attr-name! n)
    (if (not (%py-obj-is o))
      (Err raise (lit attribute) "object has no deletable attributes" ())
      ; __delattr__ is the same hook on `del obj.x`
      (let ((m (%py-dunder o "__delattr__")))
        (if (not (null? m))
          (%seq (m n) ())
          (let ((d (%py-method-find (%py-obj-class o) n)))
            (if (%py-desc-delete? d)
              (%seq ((%py-dunder d "__delete__") o) ())
              (let ((as (%py-obj-attrs o)))
                (if (null? (%py-alist-find n as))
                  (Err raise (lit attribute)
                    (Str8 append (Str8 append "'" n) "'") ())
                  (%py-obj-set-attrs! o (%py-attr-drop as n)))))))))))
(def %py-attr-drop
  (fn (self as n)
    (if (null? as) ()
      (if (Str8 =? (first (first as)) n)
        (self (rest as) n)
        (pair (first as) (self (rest as) n))))))

; the explicit super(type, obj) form: unimplemented, and every argument
; shape the corpus passes is one Python itself rejects
(def %py-super-args
  (fn (_ . a)
    (Err raise (lit type) "super() argument 1 must be a type" ())))

(def %py-issubclass
  (fn (_ c b)
    (match
      ((not (%py-class-is c))
        (Err raise (lit type) "issubclass() arg 1 must be a class" ()))
      ((%py-tuple-is b) (%py-any-subclass? c (%py-tuple-elems b)))
      ((%py-class-is b) (%py-subclass? c b))
      (#t
        (Err raise (lit type)
          "issubclass() arg 2 must be a class or tuple of classes" ())))))
(def %py-any-subclass?
  (fn (self c bs)
    (match
      ((null? bs) #f)
      ((not (%py-class-is (first bs)))
        (Err raise (lit type) "issubclass() arg 2 must be a class or tuple of classes" ()))
      ((%py-subclass? c (first bs)) #t)
      (#t (self c (rest bs))))))

; enumerate and filter are LAZY, like map: a generator pulling its source.
(def %py-enumerate
  (%py-sig!
    (fn (_ . a)
      (let ((it (%py-opt a 0 ())) (st (%py-opt a 1 0)))
        (%py-gen-new
          (fn (_ g)
            (def src (%py-iter-open it))
            (def go
              (fn (self i)
                (let ((v (%py-iter-pull! src)))
                  (if (same? v %py-gen-done) ()
                    (%seq (%py-yield g (%py-tuple-new (list i v))) (self (+ i 1)))))))
            (go st))
          "enumerate")))
    "enumerate" (list "iterable" "start") 1 #f))
; filter(None, it) keeps the truthy elements
(def %py-filter
  (fn (_ f it)
    (%py-gen-new
      (fn (_ g)
        (def src (%py-iter-open it))
        (def go
          (fn (self)
            (let ((v (%py-iter-pull! src)))
              (if (same? v %py-gen-done) ()
                (%seq
                  (if (%py-truthy (if (null? f) v (f v))) (%py-yield g v) ())
                  (self))))))
        (go))
      "filter")))

; reversed(): __reversed__ first, then the length/getitem protocol, then
; anything materialisable
(def %py-rev-index
  (fn (self g i acc)
    (if (< i 0) (%py-reverse acc) (self g (- i 1) (pair (g i) acc)))))
(def %py-reversed
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__reversed__")))
        (if (not (null? m))
          (m)
          (let ((l (%py-dunder v "__len__")))
            (let ((g (%py-dunder v "__getitem__")))
              (if (if (null? l) #t (null? g))
                (Err raise (lit type) "object is not reversible" ())
                ; %py-rev-index already walks from the end
                (%py-list-new (%py-rev-index g (- (l) 1) ())))))))
      (%py-list-new (%py-reverse (%py-iter-elems v))))))

; --- Sets --------------------------------------------------------------------
;
; Membership is Python's equality, so `{False, True, 0, 1, 2}` holds three
; elements and the FIRST of an equal pair is the one kept -- which is why
; every builder folds through %py-set-put rather than filtering afterwards.
(def %py-set-has?
  (fn (self v es)
    (if (null? es) #f (if (%py-truthy (%py-eq v (first es))) #t (self v (rest es))))))
; a set, list or dict cannot be a set element or a dict key; a frozenset can
(def %py-hashable?
  (fn (_ v)
    (match
      ((%py-list-is v) #f)
      ((%py-dict-is v) #f)
      ((%py-set-is v) (%py-set-frozen? v))
      (#t #t))))
(def %py-check-hashable!
  (fn (_ v)
    (if (%py-hashable? v) ()
      (Err raise (lit type)
        (Str8 append (Str8 append "unhashable type: '" (%py-type-name v)) "'") ()))))
(def %py-type-name
  (fn (_ v)
    (match
      ((%py-list-is v) "list")
      ((%py-dict-is v) "dict")
      ((%py-set-is v) "set")
      (#t "object"))))
; append v unless an equal element is already there
(def %py-set-put
  (fn (_ es v)
    (%py-check-hashable! v)
    (if (%py-set-has? v es) es (%py-append-elem es v))))
(def %py-set-fold
  (fn (self es vs)
    (if (null? vs) es (self (%py-set-put es (first vs)) (rest vs)))))
(def %py-set-of (fn (_ frozen vs) (%py-set-new frozen (%py-set-fold () vs))))
(def %py-mkset (fn (_ . vs) (%py-set-of #f vs)))
; set(x) / frozenset(x): from any iterable, or empty
(def %py-set-ctor
  (fn (_ . a) (%py-set-of #f (if (null? a) () (%py-iter-elems (first a))))))
(def %py-frozenset-ctor
  (fn (_ . a) (%py-set-of #t (if (null? a) () (%py-iter-elems (first a))))))
; the elements of any iterable, as a plain list
(def %py-set-args
  (fn (self as acc)
    (if (null? as) acc (self (rest as) (%py-append acc (%py-iter-elems (first as)))))))
(def %py-set-minus
  (fn (self es drop)
    (if (null? es) ()
      (if (%py-set-has? (first es) drop)
        (self (rest es) drop)
        (pair (first es) (self (rest es) drop))))))
(def %py-set-keep
  (fn (self es keep)
    (if (null? es) ()
      (if (%py-set-has? (first es) keep)
        (pair (first es) (self (rest es) keep))
        (self (rest es) keep)))))
(def %py-set-subset?
  (fn (self es other)
    (if (null? es) #t
      (if (%py-set-has? (first es) other) (self (rest es) other) #f))))
(def %py-dict-eq?
  (fn (_ ea eb)
    (def same
      (fn (self l)
        (if (null? l) #t
          (let ((e (%py-dfind (first (first l)) eb)))
            (if (null? e) #f
              (if (%py-truthy (%py-eq (rest (first l)) (rest e))) (self (rest l)) #f))))))
    (if (= (%py-length ea) (%py-length eb)) (same ea) #f)))

(def %py-set-eq?
  (fn (_ a b)
    (if (= (%py-length a) (%py-length b)) (%py-set-subset? a b) #f)))
; a mutating method on a frozenset is simply absent, as in Python
(def %py-set-mutate!
  (fn (_ s name new)
    (if (%py-set-frozen? s)
      (Err raise (lit attribute)
        (Str8 append (Str8 append "'frozenset' object has no attribute '" name) "'") ())
      (%py-set-set! s new))))

; The operators, which Python spells for sets only -- `{1} | [2]` is a
; TypeError there, so the mixed cases refuse rather than convert.  The
; result takes the LEFT operand's frozen bit, as in Python.
(def %py-set-binop
  (fn (_ a b op body)
    (if (if (%py-set-is a) (%py-set-is b) #f)
      (%py-set-new (%py-set-frozen? a) (body (%py-set-elems a) (%py-set-elems b)))
      (Err raise (lit type)
        (Str8 append (Str8 append "unsupported operand type(s) for " op) ": set") ()))))
(def %py-set-or  (fn (_ a b) (%py-set-binop a b "|" (fn (_ x y) (%py-set-fold x y)))))
(def %py-set-and (fn (_ a b) (%py-set-binop a b "&" (fn (_ x y) (%py-set-keep x y)))))
(def %py-set-sub (fn (_ a b) (%py-set-binop a b "-" (fn (_ x y) (%py-set-minus x y)))))
(def %py-set-xor
  (fn (_ a b)
    (%py-set-binop a b "^"
      (fn (_ x y) (%py-set-fold (%py-set-minus x y) (%py-set-minus y x))))))
; <= is subset, < is proper subset (and the mirror for >= and >
(def %py-set-cmp
  (fn (_ a b op)
    (if (if (%py-set-is a) (%py-set-is b) #f)
      (let ((x (%py-set-elems a)) (y (%py-set-elems b)))
        (match
          ((Str8 =? op "<=") (%py-set-subset? x y))
          ((Str8 =? op "<")
            (if (%py-set-subset? x y) (< (%py-length x) (%py-length y)) #f))
          ((Str8 =? op ">=") (%py-set-subset? y x))
          ((%py-set-subset? y x) (> (%py-length x) (%py-length y)))
          (#t #f)))
      (%py-ord-refuse op))))

(def %py-set-attr
  (fn (_ s name)
    (def es (fn (_) (%py-set-elems s)))
    (def frozen (%py-set-frozen? s))
    (def like (fn (_ l) (%py-set-new frozen l)))
    (match
      ((Str8 =? name "add")
        (fn (_ v) (%py-set-mutate! s "add" (%py-set-put (es) v))))
      ((Str8 =? name "discard")
        (fn (_ v) (%py-set-mutate! s "discard" (%py-set-minus (es) (list v)))))
      ((Str8 =? name "remove")
        (fn (_ v)
          (if (not (%py-set-has? v (es)))
            (error (%py-instantiate %py-exc-KeyError (list v)))
            (%py-set-mutate! s "remove" (%py-set-minus (es) (list v))))))
      ((Str8 =? name "pop")
        (fn (_)
          (if (null? (es))
            (error (%py-instantiate %py-exc-KeyError (list "pop from an empty set")))
            (let ((v (first (es))))
              (%seq (%py-set-mutate! s "pop" (rest (es))) v)))))
      ((Str8 =? name "clear") (fn (_) (%py-set-mutate! s "clear" ())))
      ((Str8 =? name "copy") (fn (_) (like (es))))
      ((Str8 =? name "union")
        (fn (_ . a) (%py-set-new frozen (%py-set-fold (es) (%py-set-args a ())))))
      ((Str8 =? name "intersection")
        (fn (_ . a) (like (%py-set-keep (es) (%py-set-args a ())))))
      ((Str8 =? name "difference")
        (fn (_ . a) (like (%py-set-minus (es) (%py-set-args a ())))))
      ((Str8 =? name "symmetric_difference")
        (fn (_ o)
          (let ((os (%py-iter-elems o)))
            (like (%py-set-fold (%py-set-minus (es) os) (%py-set-minus os (es)))))))
      ((Str8 =? name "update")
        (fn (_ . a) (%py-set-mutate! s "update" (%py-set-fold (es) (%py-set-args a ())))))
      ((Str8 =? name "intersection_update")
        (fn (_ . a) (%py-set-mutate! s "intersection_update" (%py-set-keep (es) (%py-set-args a ())))))
      ((Str8 =? name "difference_update")
        (fn (_ . a) (%py-set-mutate! s "difference_update" (%py-set-minus (es) (%py-set-args a ())))))
      ((Str8 =? name "symmetric_difference_update")
        (fn (_ o)
          (let ((os (%py-iter-elems o)))
            (%py-set-mutate! s "symmetric_difference_update"
              (%py-set-fold (%py-set-minus (es) os) (%py-set-minus os (es)))))))
      ((Str8 =? name "issubset")
        (fn (_ o) (%py-set-subset? (es) (%py-iter-elems o))))
      ((Str8 =? name "issuperset")
        (fn (_ o) (%py-set-subset? (%py-iter-elems o) (es))))
      ((Str8 =? name "isdisjoint")
        (fn (_ o) (null? (%py-set-keep (es) (%py-iter-elems o)))))
      ((Str8 =? name "__contains__") (fn (_ v) (%py-set-has? v (es))))
      (#t
        (Err raise (lit attribute)
          (Str8 append
            (Str8 append (Str8 append "'" (if frozen "frozenset" "set")) "' object has no attribute '")
            (Str8 append name "'"))
          ())))))

(def %py-mklist-of
  (fn (_ v) (%py-list-new (%py-iter-elems v))))

; --- dir ---------------------------------------------------------------------
;
; The names a thing answers to: its own, then its class's, then the bases' --
; sorted, and each name once however many ancestors offer it.
;
; NO BARE dir().  Python's answers with the current local namespace; here a
; Python name is an x global and no dictionary stands for the module, so there
; is nothing truthful to answer.  Refused rather than answered wrongly, which
; is the same call `globals()` and `locals()` are still waiting on.
;
; A BUILTIN TYPE ANSWERS ITS OWN NAMES ONLY.  `dir(list)` does not list
; `append`: this runtime reaches a list's methods by type at the seam rather
; than hanging them off the class object, so they are not there to be found.
; Whatever a class DOES carry is reported.
(def %py-dir-keys
  (fn (self rows acc)
    (if (null? rows)
      acc
      (self (rest rows) (pair (first (first rows)) acc)))))

(def %py-dir-class
  (fn (self c acc)
    (if (null? c)
      acc
      (%py-dir-bases (%py-class-bases c) (%py-dir-keys (%py-class-methods c) acc)))))

(def %py-dir-bases
  (fn (self bs acc)
    (if (null? bs)
      acc
      (self (rest bs) (%py-dir-class (first bs) acc)))))

(def %py-dir-of
  (fn (_ v)
    (match
      ((%py-class-is v) (%py-dir-class v ()))
      ((%py-obj-is v) (%py-dir-class (%py-obj-class v) (%py-dir-keys (%py-obj-attrs v) ())))
      (#t ()))))

(def %py-dir-seen?
  (fn (self n seen)
    (if (null? seen) #f
      (if (Str8 =? n (first seen)) #t (self n (rest seen))))))

(def %py-dir-uniq
  (fn (self names acc)
    (if (null? names)
      acc
      (self (rest names)
        (if (%py-dir-seen? (first names) acc) acc (pair (first names) acc))))))

(def %py-dir
  (%py-sig!
    (fn (_ . a)
      (if (null? a)
        (Err raise (lit type)
          "dir() with no arguments needs a namespace this runtime does not keep" ())
        (%py-list-new (%py-msort-by (%py-dir-uniq (%py-dir-of (first a)) ()) %py-ident))))
    "dir" (list "object") 0 #f))

; `hasattr` is defined in terms of getattr in Python too: it is "does this
; raise?", not a separate lookup, so anything reachable by attribute access is
; reachable here and the two can never disagree.
(def %py-hasattr
  (fn (_ o name)
    (%py-attr-name! name)
    (guard (e (if (%py-exc-match e %py-exc-AttributeError) #f (error e)))
      (%seq (%py-getattr o name) #t))))

; --- Type objects ------------------------------------------------------------
;
; `type(x)` answers a CLASS, and the builtin types get real class objects --
; ordinary PY-CLASS values, so `type(1) == int` is the same identity compare
; user classes already get, and print(int) goes through the same write handler.
;
; TWO x TYPES ARE ONE PYTHON TYPE.  A small integer and a bigint are different
; types to x's tower and both are `int` to Python, so the dispatch below maps
; both handles to one class -- measured with eq? on the handles, which is how
; the handles compare.  bool's base is int, which is Python's own arrangement
; and the reason isinstance(True, int) is True while isinstance(1, bool) is not.

(def %py-char-code (prim-ref (lit char) (lit ->int)))

; --- constructors ------------------------------------------------------------
; int('abc') is a ValueError with Python's own message, and the parse is walked
; BY HAND: the reader-base shortcut accepts prefixes ("12ab" would answer 12),
; and `Float from` answers 0.0 for garbage -- both silent wrong numbers, the
; failure mode this bundle keeps finding, so neither is trusted with input the
; program supplied.

; Digits in a base (2, 8, 16), promoting through the tower like the
; decimal parser; used by the 0x/0o/0b literals.
(def %py-int-of-based
  (fn (_ s base)
    (def n (Str8 length s))
    (def val
      (fn (_ c)
        (match
          ((if (>= c 48) (<= c 57) #f) (- c 48))
          ((if (>= c 97) (<= c 122) #f) (- c 87))
          ((if (>= c 65) (<= c 90) #f) (- c 55))
          (#t 99))))
    (def go
      (fn (self i acc)
        (if (>= i n) acc
          (let ((c (%py-char-code (%str-ref s i))))
            (if (= c 95) (self (+ i 1) acc)
              (let ((v (val c)))
                (if (>= v base)
                  (Err raise (lit value) (Str8 append "invalid literal for int() with base: " s) ())
                  (self (+ i 1) (+ (* acc base) v)))))))))
    (if (= n 0) (Err raise (lit value) "invalid literal for int()" ()) (go 0 0))))

(def %py-int-of-str
  (fn (_ s)
    (def n (%py-byte-len s))
    (def bad
      (fn (_)
        (Err raise (lit value)
          (Str8 append
            (Str8 append "invalid literal for int() with base 10: '" s) "'")
          ())))
    (def code (fn (_ i) (%py-char-code (%str-ref s i))))
    (def digits
      (fn (self i acc seen)
        (if (>= i n)
          (if seen acc (bad))
          (let ((c (code i)))
            (if (if (>= c 48) (<= c 57) #f)
              (self (+ i 1) (+ (* acc 10) (- c 48)) #t)
              ; underscores are spelling (`1_2_3`), skipped the way the
              ; float path strips them
              (if (= c 95)
                (self (+ i 1) acc seen)
                (bad)))))))
    (if (= n 0)
      (bad)
      (let ((c0 (code 0)))
        (if (= c0 45)
          (- 0 (digits 1 0 #f))
          (if (= c0 43)
            (digits 1 0 #f)
            (digits 0 0 #f)))))))

; float('...') is shape-checked before Float from sees it: sign, digits, one
; dot, one exponent.  Stricter than CPython (no inf/nan, no surrounding
; spaces), and strictness fails LOUDLY where the alternative answered 0.0.
(def %py-float-str-ok?
  (fn (_ s)
    (def n (Str8 length s))
    (def code (fn (_ i) (%py-char-code (%str-ref s i))))
    (def walk
      (fn (self i seen-digit seen-dot seen-e)
        (if (>= i n)
          seen-digit
          (let ((c (code i)))
            (match
              ((if (>= c 48) (<= c 57) #f) (self (+ i 1) #t seen-dot seen-e))
              ((= c 46)
                (if (if seen-dot #t seen-e) #f (self (+ i 1) seen-digit #t seen-e)))
              ((if (= c 101) #t (= c 69))
                (if seen-e #f
                  (if (not seen-digit) #f
                    (let ((j (if (< (+ i 1) n)
                               (if (if (= (code (+ i 1)) 43) #t (= (code (+ i 1)) 45))
                                 (+ i 2) (+ i 1))
                               (+ i 1))))
                      (self j #f seen-dot #t)))))
              (#t #f))))))
    (if (= n 0)
      #f
      (let ((c0 (code 0)))
        (if (if (= c0 45) #t (= c0 43))
          (if (= n 1) #f (walk 1 #f #f #f))
          (walk 0 #f #f #f))))))

; Python's float() also takes "inf", "infinity" and "nan" in any case, with an
; optional sign and surrounding whitespace, and underscores between digits.
; The specials are matched HERE and handed to strtod by their canonical
; spelling; everything else is underscore-stripped and shape-checked as before.
(def %py-f-trim
  (fn (_ s)
    (def n (Str8 length s))
    (def ws? (fn (_ c) (match
                         ((= c 32) #t)
                         ((= c 9) #t)
                         ((= c 10) #t)
                         (#t (= c 13)))))
    (def a
      (fn (self i)
        (if (>= i n) i (if (ws? (%py-f-code s i)) (self (+ i 1)) i))))
    (def b
      (fn (self i)
        (if (< i 0) i (if (ws? (%py-f-code s i)) (self (- i 1)) i))))
    (let ((lo (a 0)))
      (let ((hi (b (- n 1))))
        (if (> lo hi) "" (Str8 sub lo (+ (- hi lo) 1) s))))))

(def %py-f-lower
  (fn (_ s)
    (def n (Str8 length s))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-f-code s i)))
            (self (+ i 1)
              (Str8 append acc
                (if (if (>= c 65) (<= c 90) #f)
                  (Str8 sub (- c 65) 1 "abcdefghijklmnopqrstuvwxyz")
                  (Str8 sub i 1 s))))))))
    (go 0 "")))

(def %py-f-strip-us
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

(def %py-float-of-str
  (fn (_ s0)
    (def s (%py-f-trim s0))
    (def bad
      (fn (_)
        (Err raise (lit value)
          (Str8 append
            (Str8 append "could not convert string to float: '" s0) "'")
          ())))
    (def signed
      (fn (_)
        (if (= (Str8 length s) 0)
          (pair "" "")
          (let ((c (%py-f-code s 0)))
            (if (= c 45) (pair "-" (Str8 sub 1 (- (Str8 length s) 1) s))
              (if (= c 43) (pair "" (Str8 sub 1 (- (Str8 length s) 1) s))
                (pair "" s)))))))
    (let ((sp (signed)))
      (let ((low (%py-f-lower (rest sp))))
        (if (if (Str8 =? low "inf") #t (Str8 =? low "infinity"))
          (Float from (Str8 append (first sp) "inf"))
          (if (Str8 =? low "nan")
            (Float from "nan")
            (let ((t (%py-f-strip-us s)))
              (if (%py-float-str-ok? t)
                (Float from t)
                (bad)))))))))

(def %py-num-kind
  (fn (_ v)
    (let ((h (%py-typeof-prim v)))
      (match
        ((eq? h %py-th-int) (lit int))
        ((eq? h %py-th-big) (lit int))
        ((eq? h %py-th-float) (lit float))
        ((eq? h %py-th-complex) (lit complex))
        (#t ())))))

(def %py-int-ctor
  (fn (_ . a)
    (if (null? a)
      0
      (let ((v (first a)))
        (match
          ((eq? v #t) 1)
          ((eq? v #f) 0)
          ((str? v) (%py-int-of-str v))
          ((%py-obj-is v)
            (let ((m (%py-dunder v "__int__")))
              (if (null? m)
                (Err raise (lit type) "int() argument must be a number or string" ())
                (m))))
          (#t
            (let ((k (%py-num-kind v)))
              (if (eq? k (lit int)) v
              (if (eq? k (lit float))
                ; toward zero through the EXACT DIGITS, so int(1e19) and
                ; int(2.0 ** 100) answer bigints instead of a wrapped int64
                (let ((m (%py-fmt-int-mag v)))
                  (let ((n (%py-int-of-str (rest m))))
                    (if (first m) (- 0 n) n)))
                (Err raise (lit type) "int() argument must be a number or string" ()))))))))))

(def %py-float-ctor
  (fn (_ . a)
    (if (null? a)
      0.0
      (let ((v (first a)))
        (match
          ((eq? v #t) 1.0)
          ((eq? v #f) 0.0)
          ((str? v) (%py-float-of-str v))
          ((%py-obj-is v)
            (let ((m (%py-dunder v "__float__")))
              (if (null? m)
                (Err raise (lit type) "float() argument must be a number or string" ())
                (m))))
          ((%py-bytes-is v) (%py-float-of-str (%py-bytes-str v)))
          (#t
            (let ((k (%py-num-kind v)))
              (if (eq? k (lit float)) v
              (if (eq? k (lit int)) (* v 1.0)
                (Err raise (lit type) "float() argument must be a number or string" ()))))))))))

; Python's truthiness, stated once: the empties and the zeros are false and
; everything else is true.  Objects and classes are unconditionally true.
(def %py-truthy
  (fn (_ v)
    (match
      ((eq? v #f) #f)
      ((eq? v #t) #t)
      ((null? v) #f)
      ((str? v) (> (Str8 length v) 0))
      ((%py-list-is v) (not (null? (%py-list-elems v))))
      ((%py-set-is v) (not (null? (%py-set-elems v))))
      ((%py-view-is v) (not (null? (%py-view-elems v))))
      ((%py-dict-is v) (not (null? (%py-dict-entries v))))
      ((%py-tuple-is v) (not (null? (%py-tuple-elems v))))
      ((%py-obj-is v)
        (let ((b (%py-dunder v "__bool__")))
          (if (not (null? b))
            (%py-truthy (b))
            (let ((l (%py-dunder v "__len__")))
              (if (null? l) #t (not (= (l) 0)))))))
      ((%py-class-is v) #t)
      (#t (not (= v 0))))))

(def %py-bool-ctor
  (fn (_ . a) (if (null? a) #f (%py-truthy (first a)))))

(def %py-str-ctor
  (fn (_ . a) (if (null? a) "" (%py-str (first a)))))

(def %py-list-ctor
  (fn (_ . a) (if (null? a) (%py-list-new ()) (%py-mklist-of (first a)))))

(def %py-dict-copy
  (fn (self es)
    (if (null? es)
      ()
      (pair (pair (first (first es)) (rest (first es))) (self (rest es))))))

(def %py-dict-ctor
  (fn (_ . a)
    (if (null? a)
      (%py-dict-new ())
      (if (%py-dict-is (first a))
        ; a COPY, with fresh entry pairs: dict(d) in Python is a new dict, and
        ; sharing the pairs would make a store into one visible in the other
        (%py-dict-new (%py-dict-copy (%py-dict-entries (first a))))
        ; any other iterable is a sequence of (key, value) pairs
        (%py-dict-new (%py-pairs-of (%py-iter-elems (first a)) ()))))))
; dict(a=1) and d.update(a=1): the keywords ARE the entries
(def %py-dict-kwargs
  (fn (_ kws)
    (def go (fn (self l acc) (if (null? l) (%py-reverse acc) (self (rest l) (pair (pair (first (first l)) (rest (first l))) acc)))))
    (go kws ())))

(def %py-tuple-ctor
  (fn (_ . a)
    (if (null? a) (%py-tuple-new ()) (%py-tuple-new (%py-iter-elems (first a))))))

(def %py-type-ctor
  (fn (_ . a)
    (if (if (null? a) #t (not (null? (rest a))))
      (Err raise (lit type) "type() takes 1 argument here" ())
      (%py-type-of (first a)))))

; --- the class objects -------------------------------------------------------
; int before bool, because bool derives from it.

(def %py-cls-int
  (%py-class-new "int" %py-cls-object (list (pair "%ctor" %py-int-ctor)) "int"))
(def %py-cls-bool
  (%py-class-new "bool" %py-cls-int
    (list (pair "%final" #t) (pair "%ctor" %py-bool-ctor)) "bool"))
(def %py-cls-float
  (%py-class-new "float" %py-cls-object (list (pair "%ctor" %py-float-ctor)) "float"))
(def %py-cls-complex
  (%py-class-new "complex" %py-cls-object (list (pair "%ctor" %py-complex-ctor)) "complex"))
(def %py-str-methods
  (list
    (pair "%ctor" %py-str-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-str
  (%py-class-new "str" %py-cls-object %py-str-methods "str"))
; THE BUILTIN TYPE OBJECT CARRIES THE PROTOCOL, which is what makes
; `class mylist(list)` work without teaching seventy dispatch sites about
; wrappers: a subclass inherits these through the base walk that was already
; there, so every `(%py-dunder obj "__len__")` in this file finds one.  Each
; reads through %py-native-of, which is the instance's value for a subclass
; and the value itself for a plain list.
(def %py-list-methods
  (list
    (pair "%ctor" %py-list-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__setitem__"  (fn (_ self i v) (%py-setindex (%py-native-of self) i v)))
    (pair "__delitem__"  (fn (_ self i) (%py-delindex (%py-native-of self) i)))
    ; __iter__ answers the list itself; %py-obj-elems takes a non-iterator
    ; answer and iterates it, which is exactly what is wanted here.
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    ; `list.__init__(self, xs)` FILLS the instance, which is how a subclass
    ; that writes its own __init__ passes the arguments down.
    (pair "__init__"
      (fn (_ self . args)
        (%seq
          (if (null? args)
            ()
            (%py-list-set! self (%py-iter-elems (first args))))
          ())))))

; THE LAZY BUILTINS ARE CLASSES IN PYTHON, not functions -- `class mymap(map)`
; is ordinary code, and the corpus writes it.  Each keeps the function it
; always was as its %ctor, so `map(f, xs)` answers exactly what it did; what is
; new is that the name is a CLASS, so it can be named as a base and a subclass
; inherits an iterator's surface: __iter__ answers the value the instance
; carries, and __next__ pulls from it.
(def %py-lazy-methods
  (fn (_ ctor)
    (list
      (pair "%ctor" ctor)
      (pair "__iter__" (fn (_ self) (%py-native-of self)))
      (pair "__next__" (fn (_ self) (%py-next (%py-native-of self)))))))

(def %py-cls-list
  (%py-class-new "list" %py-cls-object %py-list-methods "list"))
(def %py-cls-set
  (%py-class-new "set" %py-cls-object (list (pair "%ctor" %py-set-ctor)) "set"))
(def %py-cls-frozenset
  (%py-class-new "frozenset" %py-cls-object (list (pair "%ctor" %py-frozenset-ctor)) "frozenset"))
(def %py-dict-methods
  (list
    (pair "%ctor" %py-dict-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__setitem__"  (fn (_ self i v) (%py-setindex (%py-native-of self) i v)))
    (pair "__delitem__"  (fn (_ self i) (%py-delindex (%py-native-of self) i)))))

(def %py-cls-dict
  (%py-class-new "dict" %py-cls-object %py-dict-methods "dict"))
(def %py-tuple-methods
  (list
    (pair "%ctor" %py-tuple-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-tuple
  (%py-class-new "tuple" %py-cls-object %py-tuple-methods "tuple"))
(def %py-cls-type
  (%py-class-new "type" %py-cls-object (list (pair "%ctor" %py-type-ctor)) "type"))
(def %py-cls-NoneType
  (%py-class-new "NoneType" %py-cls-object () "NoneType"))

; bytes(...) -- from a list of ints, from a count (that many zero bytes), or
; from something already bytes.  The type object makes `bytes` a name and
; gives type(b'a') something to answer.
(def %py-bytes-ctor
  (fn (_ . args)
    (if (null? args)
      (%py-bytes-new ())
      (let ((v (first args)))
        (match
          ; bytes(bytearray(b'x')) is a bytes, and a bytes of its own -- this
          ; is one of the two places the strict test earns its keep.
          ((%py-bytes-only? v) v)
          ((%py-bytes-is v) (%py-bytes-new (%py-bytes-list v)))
          ((%py-list? v)
            (%py-bytes-new (%py-bytes-of-codes (%py-list-elems v) ())))
          ((%py-tuple-is v)
            (%py-bytes-new (%py-bytes-of-codes (%py-tuple-elems v) ())))
          ((str? v)
            (Err raise (lit type) "string argument without an encoding" ()))
          (#t (%py-bytes-new (%py-bytes-zeros v ()))))))))

; A NUL BYTE CANNOT BE CARRIED HERE, and saying so is better than answering a
; short bytes.  A string on this platform is a C STRING BY AN ENGINE GUARANTEE
; -- `str/nul-terminated`, in docs/engine-contract.md -- so it ends at its
; first NUL and there is no argument that changes that.  The limit is the
; string layer's, not this constructor's; what this constructor does is refuse
; to hide it.
;
; EVERY SPELLING REFUSES, with this sentence: the literals `'\x00'` and
; `b'\x00'` in python/tokens.x, chr(0) and so `'%c' % 0` in %py-chr, and both
; arms here.  docs/nul-and-the-string-layer.md is the decision and its cost --
; including why carrying a NUL in bytes ALONE would move the silent loss to
; .decode() rather than remove it.
; A ZERO IS A BYTE LIKE ANY OTHER NOW.  This used to refuse it -- and so did
; bytes(n), chr(0) and every literal -- because the payload was a string that
; would have ended there.  The payload is a byte list; the only rule left is
; Python's own, that a byte is in range(0, 256).
(def %py-bytes-of-codes
  (fn (self codes acc)
    (if (null? codes)
      (List reverse acc)
      (let ((c (%py-boolnorm (first codes))))
        (if (if (< c 0) #t (> c 255))
          (Err raise (lit value) "bytes must be in range(0, 256)" ())
          (self (rest codes) (pair c acc)))))))

; THE COUNT IS VALIDATED BEFORE THE BYTES ARE BUILT, and negative is its own
; answer rather than a share of zero's.  Measured, CPython 3.14.7: bytes(0) is
; b'', bytes(-1) is ValueError("negative count").  A positive count asks for
; that many NUL bytes, and now gets them.
(def %py-bytes-zeros
  (fn (self n acc)
    (if (< n 0)
      (Err raise (lit value) "negative count" ())
      (if (= n 0) acc (self (- n 1) (pair 0 acc))))))

(def %py-bytes-methods
  (list
    (pair "%ctor" %py-bytes-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-bytes
  (%py-class-new "bytes" %py-cls-object %py-bytes-methods "bytes"))

(def %py-bytearray-methods
  (list
    (pair "%ctor" %py-bytearray-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-bytearray
  (%py-class-new "bytearray" %py-cls-object %py-bytearray-methods "bytearray"))

(def %py-type-of
  ; ELEVEN ARMS, so a match: the class a value answers to, asked once per
  ; kind.  bool is checked before int because True is an int in this runtime
  ; as it is in Python, and the numeric kinds are read from one place at the
  ; end rather than re-asked per arm.
  (fn (_ v)
    (match
      ((eq? v #t) %py-cls-bool)
      ((eq? v #f) %py-cls-bool)
      ((null? v) %py-cls-NoneType)
      ((%py-barr-is v) %py-cls-bytearray)
      ((%py-bytes-is v) %py-cls-bytes)
      ((str? v) %py-cls-str)
      ((%py-list-is v) %py-cls-list)
      ((%py-set-is v) (if (%py-set-frozen? v) %py-cls-frozenset %py-cls-set))
      ((%py-dict-is v) %py-cls-dict)
      ((%py-tuple-is v) %py-cls-tuple)
      ((%py-obj-is v) (%py-obj-class v))
      ((%py-class-is v) %py-cls-type)
      (#t
        (let ((k (%py-num-kind v)))
          (match
            ((eq? k (lit int)) %py-cls-int)
            ((eq? k (lit float)) %py-cls-float)
            ((eq? k (lit complex)) %py-cls-complex)
            (#t (Err raise (lit type) "type: unsupported value"))))))))

; isinstance walks the base chain with the same %py-subclass? the exception
; matcher uses, so user classes, user exceptions and builtins all answer from
; one definition.  The tuple form is Python's "any of these".
(def %py-isinstance-any ())
(set! %py-isinstance-any
  (fn (self v clss)
    (if (null? clss)
      #f
      (if (%py-isinstance v (first clss)) #t (self v (rest clss))))))

(def %py-isinstance
  (fn (_ v cls)
    (if (%py-tuple-is cls)
      (%py-isinstance-any v (%py-tuple-elems cls))
      (if (not (%py-class-is cls))
        (Err raise (lit type)
          "isinstance() arg 2 must be a type or tuple of types" ())
        (%py-subclass? (%py-type-of v) cls)))))

; --- Slicing -----------------------------------------------------------------
;
; Python's slice rules, stated once and used by str, list and tuple:
;
;   - a missing step is 1, and step 0 is a ValueError
;   - negative indices count from the end, AFTER which anything still out of
;     range CLAMPS rather than raising -- `lst[1:100]` answers what is there,
;     which is the deliberate difference between slicing and indexing
;   - a negative step defaults start to the last element and stop to "before
;     the first", which is how 'hello'[::-1] reverses
;
; The walk collects INDICES, then each type maps them its own way: a sequence
; through List ref over its element list, a string through one-character subs
; joined at the end.

(def %py-sl-adj
  (fn (_ v len step lo hi)
    (let ((a (if (< v 0) (+ v len) v)))
      (if (< a lo) lo (if (> a hi) hi a)))))

(def %py-sl-bounds
  (fn (_ len start stop step)
    (if (> step 0)
      (pair
        (if (null? start) 0 (%py-sl-adj start len step 0 len))
        (if (null? stop) len (%py-sl-adj stop len step 0 len)))
      (pair
        (if (null? start) (- len 1) (%py-sl-adj start len step (- 0 1) (- len 1)))
        (if (null? stop) (- 0 1) (%py-sl-adj stop len step (- 0 1) (- len 1)))))))

(def %py-sl-idxs
  (fn (self i stop step acc)
    (if (if (> step 0) (>= i stop) (<= i stop))
      (%py-reverse acc)
      (self (+ i step) stop step (pair i acc)))))

(def %py-slice-idxs
  (fn (_ len start stop step)
    (let ((b (%py-sl-bounds len start stop step)))
      (%py-sl-idxs (first b) (rest b) step ()))))

(def %py-sl-pick
  (fn (self elems idxs acc)
    (if (null? idxs)
      (%py-reverse acc)
      (self elems (rest idxs) (pair (List ref (first idxs) elems) acc)))))

(def %py-sl-chars
  (fn (self str idxs acc)
    (if (null? idxs)
      (%py-reverse acc)
      (self str (rest idxs) (pair (Str sub (first idxs) 1 str) acc)))))

(def %py-slice
  (fn (_ obj start stop step)
    (let ((st (if (null? step) 1 step)))
      (match
        ((= st 0) (Err raise (lit value) "slice step cannot be zero" ()))
        ((str? obj)
          (Str8 join ""
            (%py-sl-chars obj
              (%py-slice-idxs (Str length obj) start stop st) ())))
        ((%py-bytes-is obj)
          (let ((l (%py-bytes-list obj)))
            ((if (%py-barr-is obj) %py-barr-new %py-bytes-new)
              (%py-sl-pick l (%py-slice-idxs (%pb-len l) start stop st) ()))))
        ((%py-list-is obj)
          (%py-list-new
            (%py-sl-pick (%py-list-elems obj)
              (%py-slice-idxs (%py-length (%py-list-elems obj)) start stop st) ())))
        ((%py-tuple-is obj)
          (%py-tuple-new
            (%py-sl-pick (%py-tuple-elems obj)
              (%py-slice-idxs (%py-length (%py-tuple-elems obj)) start stop st) ())))
        ; a dict gets Python's own complaint: a slice is not a key
        (#t (Err raise (lit type) "unhashable type: 'slice'" ()))))))

; --- def, whatever the frame depth -------------------------------------------
;
; The REPL's conditional hoists run inside a guard HANDLER, where a plain def
; binds in the handler's frame and vanishes with it.  base/def-global is the
; engine door that defines for the CALLER at any depth; the symbol comes
; quoted, the value evaluated.
(def %py-defg-prim (prim-ref (lit base) (lit def-global)))
(def %py-defg (fn (_ sym v) (%py-defg-prim sym v)))

; Each of these was a bare function until the corpus asked to subclass one.
(def %py-cls-map       (%py-class-new "map"       %py-cls-object (%py-lazy-methods %py-map)       "map"))
(def %py-cls-filter    (%py-class-new "filter"    %py-cls-object (%py-lazy-methods %py-filter)    "filter"))
(def %py-cls-zip       (%py-class-new "zip"       %py-cls-object (%py-lazy-methods %py-zip)       "zip"))
(def %py-cls-enumerate (%py-class-new "enumerate" %py-cls-object (%py-lazy-methods %py-enumerate) "enumerate"))
(def %py-cls-reversed  (%py-class-new "reversed"  %py-cls-object (%py-lazy-methods %py-reversed)  "reversed"))
; NOT EVERY BUILTIN IS AN ACCEPTABLE BASE.  CPython refuses `class X(range)`
; and `class X(bool)` outright -- "type 'range' is not an acceptable base
; type" -- so the marker below says so, under a key no Python name can spell.
(def %py-cls-range
  (%py-class-new "range" %py-cls-object
    (pair (pair "%final" #t) (%py-lazy-methods %py-range)) "range"))
