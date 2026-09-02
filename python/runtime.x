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

(import python/types)
(import python/format)

(provide python/runtime
  %py-add %py-sub %py-mul %py-div %py-floordiv %py-mod %py-pow %py-neg
  %py-eq %py-ne %py-lt %py-gt %py-le %py-ge
  %py-print %py-display
  %py-mklist %py-index %py-len %py-list? %py-write %py-getattr %py-setindex
  %py-range %py-iter-elems %py-callcc
  %py-raise %py-exc-match %py-exc-match-any
  %py-mkclass %py-setattr %py-super
  %py-str %py-repr-of %py-mklist-of %py-hasattr
  %py-cls-type %py-cls-int %py-cls-float %py-cls-bool %py-cls-str
  %py-cls-list %py-cls-dict %py-cls-tuple %py-cls-NoneType
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

(def %py-add
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__add__" "__radd__" "+")
    (if (str? a)
      (if (str? b)
        (Str8 append a b)
        (Err raise (lit type) "can only concatenate str to str" ()))
      (if (str? b)
        ; `1 + "a"` is a TypeError in Python, not a coercion.  Without this it
        ; reached x's `+` with a string operand and answered a number.
        (Err raise (lit type) "unsupported operand type(s) for +" ())
        ; Lists concatenate through PY-LIST's own `+` op, which the engine
        ; dispatches from here.  Bools are ints here too: 1j + True.
        (if (if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
          (%py-cx-arith a b "+" 0)
          (+ (if (eq? a #t) 1 (if (eq? a #f) 0 a))
             (if (eq? b #t) 1 (if (eq? b #f) 0 b)))))))))

(def %py-sub
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__sub__" "__rsub__" "-")
    (if (if (eq? (%py-typeof-prim a) %py-th-complex) #t
          (eq? (%py-typeof-prim b) %py-th-complex))
      (%py-cx-arith a b "-" 1)
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
        (if (= code 0) (+ x y)
        (if (= code 1) (- x y)
        (if (= code 2) (* x y)
          (/ x y))))))))

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
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__mul__" "__rmul__" "*")
    (if (str? a)
      (if (str? b)
        (Err raise (lit type) "can't multiply sequence by non-int" ())
        (%py-str-repeat a b))
      (if (str? b)
        (%py-str-repeat b a)
        (if (if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
          (%py-cx-arith a b "*" 2)
          (* (if (eq? a #t) 1 (if (eq? a #f) 0 a))
             (if (eq? b #t) 1 (if (eq? b #f) 0 b)))))))))

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
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__truediv__" "__rtruediv__" "/")
    (if (= b 0)
      (Err raise (lit zero-division) "division by zero" ())
      (if (if (eq? (%py-typeof-prim a) %py-th-complex) #t
            (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "/" 3)
        (/ (* a 1.0) b))))))

; FLOOR DIVISION OF FLOATS IS A FLOAT: 1.0 // 2 is 0.0 in Python, floor of
; the true quotient, where Num quotient wants exact operands.
(def %py-floordiv
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__floordiv__" "__rfloordiv__" "//")
    (if (= b 0)
      (Err raise (lit zero-division) "integer division or modulo by zero" ())
      (if (if (%py-complex-is a) #t (%py-complex-is b))
        (Err raise (lit type) "can't take floor of complex number." ())
      (if (if (%py-float-is a) #t (%py-float-is b))
        (Float floor (/ (* a 1.0) b))
        (Num quotient a b)))))))
; A STRING ON THE LEFT OF % IS FORMATTING, not arithmetic -- str.__mod__ --
; and the check comes before the zero test because the right operand of a
; format is a tuple as often as a number.
(def %py-mod
  (fn (_ a b)
    ; str.__mod__ answers first: "%d" % obj formats the object, it does not
    ; ask the object for __rmod__
    (if (str? a)
      (%py-format a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__mod__" "__rmod__" "%")
      (if (if (%py-complex-is a) #t (%py-complex-is b))
        (Err raise (lit type) "can't mod complex numbers." ())
      (if (= b 0)
        (Err raise (lit zero-division) "integer modulo by zero" ())
        (Num modulo a b)))))))
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
(def %py-pow
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__pow__" "__rpow__" "** or pow()")
    (if (if (%py-complex-is a) #t (%py-complex-is b))
      (%py-cpow (%py-complex-of a) (%py-complex-of b))
    ; a negative real base to a fractional power is a COMPLEX in Python 3
    (if (if (< (if (eq? a #t) 1 (if (eq? a #f) 0 a)) 0)
          (if (%py-float-is b) (not (= b (Float floor b))) #f)
          #f)
      (%py-cpow (%py-complex-of a) (%py-complex-of b))
    (if (if (%py-float-is a) #t (%py-float-is b))
      (do
        (def fa (* (%py-boolnorm a) 1.0))
        (def fb (* (%py-boolnorm b) 1.0))
        (if (if (= fa 0.0) (< fb 0.0) #f)
          (Err raise (lit zero-division)
            "0.0 cannot be raised to a negative power" ())
          (Float pow fa fb)))
      (if (< b 0)
        (/ 1.0 (Num expt a (- 0 b)))
        (Num expt a b))))))))
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
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__or__" "__ror__" "|")
      (%py-bit2 a b "|" (fn (_ x y) (if x #t y))))))
(def %py-bitxor
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__xor__" "__rxor__" "^")
      (%py-bit2 a b "^" (fn (_ x y) (if x (not y) y))))))
(def %py-bitand
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__and__" "__rand__" "&")
      (%py-bit2 a b "&" (fn (_ x y) (if x y #f))))))

; --- Membership --------------------------------------------------------------
; `a in b`: substring for strings, element walk with Python's equality for
; the containers, keys for a dict, and a TypeError for anything that cannot
; be iterated -- 1.2 in 3.4 must refuse, not loop.
(def %py-in-walk
  (fn (self a l)
    (if (null? l) #f (if (%py-eq a (first l)) #t (self a (rest l))))))

(def %py-in
  (fn (_ a b)
    (if (%py-obj-is b)
      (let ((m (%py-dunder b "__contains__")))
        (if (null? m)
          (%py-in-walk a (%py-iter-elems b))
          (%py-truthy (m a))))
    (if (str? b)
      (if (str? a)
        (Str8 includes? a b)
        (Err raise (lit type)
          "'in <string>' requires string as left operand" ()))
      (if (%py-list? b)
        (%py-in-walk a (%py-list-elems b))
        (if (%py-tuple-is b)
          (%py-in-walk a (%py-tuple-elems b))
          (if (%py-dict? b)
            (do
              (def keys
                (fn (self es acc)
                  (if (null? es) acc (self (rest es) (pair (first (first es)) acc)))))
              (%py-in-walk a (keys (%py-dict-entries b) ())))
            (Err raise (lit type) "argument is not iterable" ()))))))))

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
    (if (%py-float-is v)
      (if (< (first v) 0) (- 0.0 v) v)
      (if (%py-complex-is v)
        (Complex magnitude v)
        (if (eq? (%py-num-kind v) (lit int))
          (if (< v 0) (- 0 v) v)
          (Err raise (lit type) "bad operand type for abs()" ()))))))

(def %py-round
  (fn (_ . a)
    (def v (%py-boolnorm (first a)))
    (def nd (if (null? (rest a)) () (first (rest a))))
    (if (not (%py-float-is v))
      (if (eq? (%py-num-kind v) (lit int))
        v
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

(def %py-min
  (fn (_ . a)
    (def vs (if (null? (rest a)) (%py-iter-elems (first a)) a))
    (%py-minmax vs (fn (_ x y) (%py-lt x y)) "min")))
(def %py-max
  (fn (_ . a)
    (def vs (if (null? (rest a)) (%py-iter-elems (first a)) a))
    (%py-minmax vs (fn (_ x y) (%py-gt x y)) "max")))

; --- Bytes seams -------------------------------------------------------------
(def %py-mkbytes (fn (_ s) (%py-bytes-new s)))
(def %py-bytearray
  (fn (_ v)
    (if (%py-bytes-is v)
      v
      (Err raise (lit type) "bytearray() argument unsupported here" ()))))

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
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r (%py-cmp2 a b "__eq__" "__eq__")))
        (if (eq? r %py-NotImplemented) (eq? a b) r))
    (if (str? a) (if (str? b) (Str8 =? a b) #f)
    (if (str? b) #f
    (if (%py-class-is a) (eq? a b)
    (if (%py-class-is b) #f
      ; a BOOL, always: the tower's `=` answers nil for an unequal complex,
      ; and a nil in a printed comparison reads as None
      (if (= (if (eq? a #t) 1 (if (eq? a #f) 0 a))
             (if (eq? b #t) 1 (if (eq? b #f) 0 b)))
        #t #f))))))))
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

(def %py-lt
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r (%py-cmp2 a b "__lt__" "__gt__")))
        (if (eq? r %py-NotImplemented) (%py-ord-refuse "<") r))
    (%py-lt-num a b))))
(def %py-lt-num
  (fn (_ a b)
    (%py-cmp-refuse a b "<")
    (if (if (str? a) (str? b) #f)
      (< (%py-strcmp a b 0) 0)
      (< (if (eq? a #t) 1 (if (eq? a #f) 0 a))
         (if (eq? b #t) 1 (if (eq? b #f) 0 b))))))
(def %py-gt
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r (%py-cmp2 a b "__gt__" "__lt__")))
        (if (eq? r %py-NotImplemented) (%py-ord-refuse ">") r))
    (%py-gt-num a b))))
(def %py-gt-num
  (fn (_ a b)
    (%py-cmp-refuse a b ">")
    (if (if (str? a) (str? b) #f)
      (> (%py-strcmp a b 0) 0)
      (> (if (eq? a #t) 1 (if (eq? a #f) 0 a))
         (if (eq? b #t) 1 (if (eq? b #f) 0 b))))))
(def %py-le
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r (%py-cmp2 a b "__le__" "__ge__")))
        (if (eq? r %py-NotImplemented) (%py-ord-refuse "<=") r))
    (if (if (str? a) (str? b) #f)
      (<= (%py-strcmp a b 0) 0)
      (if (%py-lt a b) #t (%py-eq a b))))))
(def %py-ge
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r (%py-cmp2 a b "__ge__" "__le__")))
        (if (eq? r %py-NotImplemented) (%py-ord-refuse ">=") r))
    (if (if (str? a) (str? b) #f)
      (>= (%py-strcmp a b 0) 0)
      (if (%py-gt a b) #t (%py-eq a b))))))

; --- Lists ------------------------------------------------------------------
;
; TAGGED, not a bare x list.  An empty Python list and None are different
; values, and a bare x list would make both of them nil -- so `print([])` would
; print None.  A list is (py-list . elements): the tag distinguishes it from
; every other value this runtime produces, and from nil.
(def %py-mklist (fn (_ . elems) (%py-list-new elems)))

(def %py-list? (fn (_ v) (%py-list-is v)))

(def %py-len
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__len__")))
        (if (null? m) (Err raise (lit type) "object of this type has no len()" ()) (m)))
    (if (%py-dict? v)
      (List length (%py-dict-entries v))
    (if (%py-tuple-is v)
      (List length (%py-tuple-elems v))
    (if (%py-list? v)
      (List length (%py-list-elems v))
      (if (str? v)
        ; CODE POINTS, not bytes: len('\xff') is 1
        (Str length v)
        (Err raise (lit type) "object of this type has no len()" ()))))))))

; NEGATIVE INDICES COUNT FROM THE END, which is Python and not x.  -1 is the
; last element, and an index past either end raises IndexError rather than
; returning nil -- a silent nil would propagate into arithmetic and surface far
; from the subscript that produced it.
(def %py-index
  (fn (_ v i)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__getitem__")))
        (if (null? m) (Err raise (lit type) "object is not subscriptable" ()) (m i)))
    (if (str? v)
      ; A string index yields a one-character STRING, as in Python -- there is
      ; no character type at this surface -- and it counts CODE POINTS: a
      ; two-byte character is one index.
      (let ((n (Str length v)))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "string index out of range" ())
            (Str sub k 1 v))))
    ; Subscripting a tuple and a dict are calls too -- see the list branch.
    (if (%py-tuple-is v)
      (v i)
    (if (%py-dict? v)
      (v i)
    (if (not (%py-list? v))
      (Err raise (lit type) "object is not subscriptable" ())
      ; SUBSCRIPTING A LIST IS A CALL.  x dispatches `(v i)` through the type's
      ; `call` handler, so negative indices and IndexError are stated once in
      ; python/types.x rather than copied here.
      (v i))))))))

; Store into a list at an index.  Rebuilds the element list and hangs it back on
; the SAME tag pair, so every reference sees the store -- the identity argument
; that made append work.
(def %py-set-nth
  (fn (self lst k v)
    (if (= k 0)
      (pair v (rest lst))
      (pair (first lst) (self (rest lst) (- k 1) v)))))

(def %py-setindex
  (fn (_ obj i v)
    (if (%py-obj-is obj)
      (let ((m (%py-dunder obj "__setitem__")))
        (if (null? m)
          (Err raise (lit type) "object does not support item assignment" ())
          (m i v)))
    (if (%py-dict? obj)
      (%py-dset obj i v)
    (if (not (%py-list? obj))
      (Err raise (lit type) "object does not support item assignment" ())
      (let ((n (List length (%py-list-elems obj))))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "list assignment index out of range" ())
            (%py-list-set! obj (%py-set-nth (%py-list-elems obj) k v))))))))))

; The escape continuation a `return` invokes.  Fetched rather than assumed
; global, the way every other prim in this bundle is reached.
(def %py-callcc (prim-ref (lit ctrl) (lit call/cc)))

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
                        (List reverse acc)
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
                      (List reverse acc)
                      (self (+ i 1) (pair r acc))))))
              (go 0 ()))))))))

(def %py-iter-elems
  (fn (_ v)
    (if (%py-obj-is v)
      (%py-obj-elems v)
    ; Iterating a dict yields its KEYS, as in Python.
    (if (%py-dict? v)
      (%py-dkeys (%py-dict-entries v))
    (if (%py-tuple-is v)
      (%py-tuple-elems v)
    (if (%py-list? v)
      (%py-list-elems v)
      (if (str? v)
        (%py-str-chars v 0 (Str8 length v))
        (Err raise (lit type) "object is not iterable" ()))))))))

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
      (List reverse acc)
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

(def %py-mkdict (fn (_ . entries) (%py-dict-new entries)))

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
        (Err raise (lit key) "key not found" ())
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

(def %py-dict-attr
  (fn (_ d name)
    (if (Str8 =? name "keys")   (fn (_) (%py-list-new (%py-dkeys (%py-dict-entries d))))
    (if (Str8 =? name "values") (fn (_) (%py-list-new (%py-dvals (%py-dict-entries d))))
    (if (Str8 =? name "get")
      ; get returns a default instead of raising -- that is the whole reason it
      ; exists next to subscripting.
      (fn (_ k . dflt)
        (let ((e (%py-dfind k (%py-dict-entries d))))
          (if (null? e) (if (null? dflt) () (first dflt)) (rest e))))
    (Err raise (lit attribute)
      (Str8 append (Str8 append "'dict' object has no attribute '" name) "'")
      ()))))))

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
    (if (%py-list? obj)
      (if (Str8 =? name "append")
        (fn (_ v) (%py-list-set! obj (%py-append-elem (%py-list-elems obj) v)))
        (if (Str8 =? name "pop")
          (fn (_ . a)
            (let ((n (List length (%py-list-elems obj))))
              (if (= n 0)
                (Err raise (lit index) "pop from empty list" ())
                (let ((v (List ref (- n 1) (%py-list-elems obj))))
                  (%seq (%py-list-set! obj (%py-drop-last (%py-list-elems obj))) v)))))
          (Err raise (lit attribute)
            (Str8 append (Str8 append "'list' object has no attribute '" name) "'")
            ())))
      (if (%py-dict? obj)
        (%py-dict-attr obj name)
      (if (str? obj)
        (%py-str-attr obj name)
      (if (%py-obj-is obj)
        (%py-obj-attr obj name)
      (if (%py-super-is obj)
        (%py-super-attr obj name)
      (if (%py-class-is obj)
        (%py-class-attr obj name)
      (if (%py-complex-is obj)
        (if (Str8 =? name "real") (%py-cre obj)
        (if (Str8 =? name "imag") (%py-cim obj)
        (if (Str8 =? name "conjugate")
          (fn (_) (Complex make (%py-cre obj) (- 0.0 (%py-cim obj))))
          (Err raise (lit attribute)
            (Str8 append (Str8 append "'complex' object has no attribute '" name) "'") ()))))
        (Err raise (lit attribute)
          (Str8 append (Str8 append "object has no attribute '" name) "'")()))))))))))

; str.upper is the method as a function of its receiver -- str.upper("abc")
; -- and a user class's attribute is its function, unbound, callable with an
; explicit self.  A builtin class other than str has no such surface yet.
(def %py-class-attr
  (fn (_ cls name)
    (if (eq? cls %py-cls-str)
      ; validate the name NOW, so str.nosuch raises at access, not at call
      (do (%py-str-attr "" name)
          (fn (_ recv . args) (apply (%py-str-attr recv name) args)))
      (let ((m (%py-method-find cls name)))
        (if (null? m)
          (Err raise (lit attribute)
            (Str8 append (Str8 append "type object '" (%py-class-name cls))
              (Str8 append "' has no attribute '" (Str8 append name "'"))) ())
          m)))))

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
  (fn (_ c) (if (= c 32) #t (if (= c 9) #t (if (= c 10) #t (if (= c 13) #t (if (= c 11) #t (= c 12))))))))
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
            (List reverse acc)
            (if (if (>= maxsplit 0) (>= k maxsplit) #f)
              ; the remainder is kept verbatim, trailing whitespace and all
              (List reverse (pair (Str8 sub st (- n st) s) acc))
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
            (List reverse (pair (Str8 sub i (- n i) s) acc))
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
          (List reverse (if (> i st) (pair (Str8 sub st (- i st) s) acc) acc))
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

(def %py-s-arg (fn (_ a i) (if (> (List length a) i) (List ref i a) ())))

(def %py-s-subs
  (fn (_ v) (if (%py-tuple-is v) (%py-tuple-elems v) (list v))))

(def %py-str-attr
  (fn (_ s name)
    (def n (Str8 length s))
    (if (Str8 =? name "upper")   (fn (_) (Str8 upcase s))
    (if (Str8 =? name "lower")   (fn (_) (Str8 downcase s))
    (if (Str8 =? name "strip")   (fn (_ . a) (%py-s-strip s (%py-s-arg a 0) #t #t))
    (if (Str8 =? name "lstrip")  (fn (_ . a) (%py-s-strip s (%py-s-arg a 0) #t #f))
    (if (Str8 =? name "rstrip")  (fn (_ . a) (%py-s-strip s (%py-s-arg a 0) #f #t))
    (if (Str8 =? name "split")
      (fn (_ . a)
        (let ((sep (%py-s-arg a 0)) (mx (let ((m (%py-s-arg a 1))) (if (null? m) (- 0 1) m))))
          (%py-list-new (if (null? sep) (%py-s-wsplit s mx) (%py-s-sepsplit s sep mx)))))
    (if (Str8 =? name "rsplit")
      (fn (_ . a)
        (let ((sep (%py-s-arg a 0)) (mx (let ((m (%py-s-arg a 1))) (if (null? m) (- 0 1) m))))
          (%py-list-new (if (null? sep) (%py-s-rwsplit s mx) (%py-s-rsepsplit s sep mx)))))
    (if (Str8 =? name "splitlines")
      (fn (_ . a) (%py-list-new (%py-s-splitlines s (if (null? a) #f (%py-truthy (first a))))))
    (if (Str8 =? name "join")
      ; any iterable of strings; anything else is Python's TypeError, with
      ; its message, before the walk (spec 12 pins it)
      (fn (_ it)
        (if (not (if (%py-list? it) #t (if (%py-tuple-is it) #t (if (str? it) #t (if (%py-dict? it) #t (%py-obj-is it))))))
          (Err raise (lit type) "can only join an iterable of str" ())
          (let ((es (%py-iter-elems it)))
            (def all-str (fn (self l) (if (null? l) #t (if (str? (first l)) (self (rest l)) #f))))
            (if (all-str es)
              (Str8 join s es)
              (Err raise (lit type) "can only join an iterable of str" ())))))
    (if (Str8 =? name "replace")
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
              (go 0 0 "")))))
    (if (if (Str8 =? name "startswith") #t (Str8 =? name "endswith"))
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
          (any (%py-s-subs sub))))
    (if (if (Str8 =? name "find") #t (Str8 =? name "index"))
      (fn (_ sub . a)
        (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
          (let ((k (if (%py-s-start-past? n (%py-s-arg a 0)) (- 0 1) (%py-s-find s sub (first r) (rest r)))))
            (if (if (< k 0) (Str8 =? name "index") #f)
              (Err raise (lit value) "substring not found" ())
              k))))
    (if (if (Str8 =? name "rfind") #t (Str8 =? name "rindex"))
      (fn (_ sub . a)
        (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
          (let ((k (if (%py-s-start-past? n (%py-s-arg a 0)) (- 0 1) (%py-s-rfind s sub (first r) (rest r)))))
            (if (if (< k 0) (Str8 =? name "rindex") #f)
              (Err raise (lit value) "substring not found" ())
              k))))
    (if (Str8 =? name "count")
      (fn (_ sub . a)
        (let ((r (%py-s-range n (%py-s-arg a 0) (%py-s-arg a 1))))
          (if (%py-s-start-past? n (%py-s-arg a 0)) 0 (%py-s-count s sub (first r) (rest r)))))
    (if (if (Str8 =? name "partition") #t (Str8 =? name "rpartition"))
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
              (Str8 sub (+ k (Str8 length sep)) (- n (+ k (Str8 length sep))) s))))))
    (if (if (Str8 =? name "center") #t (if (Str8 =? name "ljust") #t (Str8 =? name "rjust")))
      (fn (_ width . a)
        (let ((f (let ((x (%py-s-arg a 0))) (if (null? x) " " x))))
          (if (Str8 =? name "center") (%py-s-center s width f)
            (if (<= width n) s
              (if (Str8 =? name "ljust")
                (Str8 append s (%py-s-rep f (- width n)))
                (Str8 append (%py-s-rep f (- width n)) s))))))
    (if (Str8 =? name "isspace") (fn (_) (%py-s-all? s %py-s-ws?))
    (if (Str8 =? name "isalpha") (fn (_) (%py-s-all? s %py-s-alpha?))
    (if (Str8 =? name "isdigit") (fn (_) (%py-s-all? s %py-s-digit?))
    (if (Str8 =? name "isalnum") (fn (_) (%py-s-all? s (fn (_ c) (if (%py-s-alpha? c) #t (%py-s-digit? c)))))
    (if (Str8 =? name "isupper")
      (fn (_) (if (%py-s-any? s %py-s-upper?) (not (%py-s-any? s %py-s-lower?)) #f))
    (if (Str8 =? name "islower")
      (fn (_) (if (%py-s-any? s %py-s-lower?) (not (%py-s-any? s %py-s-upper?)) #f))
    (if (Str8 =? name "swapcase")
      (fn (_) (%py-s-map s (fn (_ c i) (if (%py-s-upper? c) (+ c 32) (if (%py-s-lower? c) (- c 32) c)))))
    (if (Str8 =? name "capitalize")
      (fn (_) (%py-s-map s (fn (_ c i) (if (= i 0) (if (%py-s-lower? c) (- c 32) c) (if (%py-s-upper? c) (+ c 32) c)))))
    (if (Str8 =? name "title")
      (fn (_)
        (%py-s-map s
          (fn (_ c i)
            (let ((prev-alpha (if (= i 0) #f (%py-s-alpha? (%py-s-code s (- i 1))))))
              (if prev-alpha
                (if (%py-s-upper? c) (+ c 32) c)
                (if (%py-s-lower? c) (- c 32) c))))))
    (if (Str8 =? name "format")
      (fn (_ . args) (%py-strformat s args))
      (Err raise (lit attribute)
        (Str8 append (Str8 append "'str' object has no attribute '" name) "'")
        ())))))))))))))))))))))))))))))

; chr() and ord(): the engine's int->char door and the char->int one, with
; the one-character string built the way the tokenizer builds strings.
(def %py-int->char (prim-ref (lit int) (lit ->char)))
(def %py-chr
  (fn (_ n)
    (if (eq? (%py-num-kind (if (eq? n #t) 1 (if (eq? n #f) 0 n))) (lit int))
      (%py-list->string (list (%py-int->char (if (eq? n #t) 1 (if (eq? n #f) 0 n)))))
      (Err raise (lit type) "an integer is required" ()))))
; ord() counts CODE POINTS, not bytes: chr(955) is a two-byte string that
; is one character, so the utf-8-aware Str class measures and indexes it.
(def %py-ord
  (fn (_ s)
    (if (if (str? s) (= (Str length s) 1) #f)
      (%py-char-code (Str ref 0 s))
      (Err raise (lit type) "ord() expected a character" ()))))

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
    (def align? (fn (_ c) (if (= c 60) #t (if (= c 62) #t (if (= c 94) #t (= c 61))))))
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
        (if (Str8 =? a "<") (Str8 append (Str8 append sgn s) (rep padn))
        (if (Str8 =? a ">") (Str8 append (rep padn) (Str8 append sgn s))
        (if (Str8 =? a "=") (Str8 append sgn (Str8 append (rep padn) s))
          ; ^ centres, the extra space on the right
          (let ((l (Num quotient padn 2)))
            (Str8 append (rep l) (Str8 append (Str8 append sgn s) (rep (- padn l))))))))))))

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
        (if (if (str? v) #t (if (= tc 115) #t (if (%py-obj-is v) #t (if (null? v) #t (if (%py-list? v) #t (%py-tuple-is v))))))
          ; strings (and anything shown as its str): s or empty type only
          (if (if (not (= tc 0)) (not (= tc 115)) #f)
            (Err raise (lit value)
              (Str8 append "Unknown format code '" (Str8 append type "' for object of type 'str'")) ())
          (if (if (= tc 115) (not (null? (%py-num-kind v))) #f)
            (Err raise (lit value)
              (Str8 append "Unknown format code 's' for object of type '"
                (Str8 append (if (eq? (%py-num-kind v) (lit float)) "float" "int") "'")) ())
          (if (if (null? sign) #f (not (Str8 =? sign "")))
            (Err raise (lit value) "Sign not allowed in string format specifier" ())
          (if (if (not (null? align)) (Str8 =? align "=") #f)
            (Err raise (lit value) "'=' alignment not allowed in string format specifier" ())
            (let ((s0 (%py-str v)))
              (let ((s (if (if (not (null? prec)) (> (Str8 length s0) prec) #f) (Str8 sub 0 prec s0) s0)))
                ; the 0 flag on text fills with zeros on the RIGHT ('{:06s}'
                ; of ab is ab0000 -- measured)
                (%py-spec-pad s width (if (if zero (Str8 =? fill " ") #f) "0" fill) align "<" "")))))))
          (do
            (def w (if (eq? v #t) 1 (if (eq? v #f) 0 v)))
            (def kind (%py-num-kind w))
            (if (null? kind)
              (Err raise (lit type) "unsupported format string passed to object.__format__" ())
              ())
            ; integers with an integer or empty type
            (if (if (eq? kind (lit int)) (= tc 99) #f)
              ; c: the character with that code point, as text
              (if (if (null? sign) #f (not (Str8 =? sign "")))
                (Err raise (lit value) "Sign not allowed with integer format specifier 'c'" ())
                (%py-spec-pad (%py-chr w) width fill align ">" ""))
            (if (if (eq? kind (lit int))
                  (if (= tc 0) #t (if (= tc 100) #t (if (= tc 120) #t (if (= tc 88) #t (if (= tc 111) #t (if (= tc 98) #t (= tc 110)))))))
                  #f)
              (do
                (if (not (null? prec))
                  (Err raise (lit value) "Precision not allowed in integer format specifier" ())
                  ())
                (def m
                  (if (if (= tc 120) #t (= tc 88))
                    (%py-fmt-base w 16 (if (= tc 88) "0123456789ABCDEF" "0123456789abcdef"))
                    (if (= tc 111) (%py-fmt-base w 8 "01234567")
                      (if (= tc 98) (%py-fmt-base w 2 "01")
                        (%py-fmt-int-mag w)))))
                ; _ groups binary, octal and hex digits by four
                (def grp
                  (fn (_ ds)
                    (if (eq? comma #t) (%py-group3 ds)
                      (if (eq? comma (lit under))
                        (%py-group-sep ds
                          (if (if (= tc 120) #t (if (= tc 88) #t (if (= tc 111) #t (= tc 98)))) 4 3)
                          "_")
                        ds))))
                (def pfx (if alt (if (= tc 120) "0x" (if (= tc 88) "0X" (if (= tc 111) "0o" (if (= tc 98) "0b" "")))) ""))
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
                (%py-spec-pad digits width fill2 align2 ">" sgn))
              ; floats -- and ints asked for a float type
              (if (if (= tc 0) #t (if (= tc 101) #t (if (= tc 69) #t (if (= tc 102) #t (if (= tc 70) #t (if (= tc 103) #t (if (= tc 71) #t (if (= tc 110) #t (= tc 37)))))))))
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
                        (if (if (= tc 101) #t (= tc 69)) (%py-fmt-e D x10 p upper)
                        (if (if (= tc 102) #t (= tc 70)) (%py-fmt-f D x10 p)
                        (if (if (= tc 103) #t (if (= tc 71) #t (= tc 110))) (%py-fmt-g D x10 p upper alt)
                        (if (= tc 37)
                          ; percent: value * 100 in f notation, then %
                          (let ((ex2 (%py-f-exact (* fv 100.0))))
                            (Str8 append (%py-fmt-f (first (rest (rest ex2))) (first (rest (rest (rest ex2)))) p) "%"))
                          ; the empty type: repr without precision; with
                          ; precision like g, but a fixed result keeps at
                          ; least one digit after the point
                          (if (null? prec)
                            (let ((r (%py-frepr fv))) (if neg (Str8 sub 1 (- (Str8 length r) 1) r) r))
                            ; like g, but scientific already when the
                            ; exponent reaches p-1 (format(0.0, '.1') is
                            ; 0e+00), and fixed keeps one digit past the point
                            (let ((sc (%py-fmt-sci D x10 (- p 1))))
                              (let ((xa (first (rest (rest sc)))))
                                (if (if (>= xa (- 0 4)) (< xa (- p 1)) #f)
                                  (let ((g (%py-fmt-g D x10 p #f #f)))
                                    (if (null? (Str8 index-of "." g)) (Str8 append g ".0") g))
                                  (let ((fp (%py-fmt-strip0 (first (rest sc)))))
                                    (Str8 append
                                      (if (= (Str8 length fp) 0) (first sc)
                                        (Str8 append (first sc) (Str8 append "." fp)))
                                      (%py-fmt-exp-str xa #f))))))))))))
                      (def body2 (if comma (%py-comma-float body (if (eq? comma #t) "," "_")) body))
                      (%py-spec-pad body2 width fill2 align2 ">" sgn))))
                (Err raise (lit value)
                  (Str8 append "Unknown format code '"
                    (Str8 append type
                      (Str8 append "' for object of type '"
                        (Str8 append (if (eq? kind (lit int)) "int" "float") "'")))) ()))))))))))

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
    (let ((cv (if (Str8 =? conv "r") (%py-repr-of v)
              (if (Str8 =? conv "s") (%py-str v)
              (if (Str8 =? conv "a") (%py-repr-of v)
              (if (Str8 =? conv "") v
                (Err raise (lit value) "Unknown conversion specifier" ())))))))
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
    (def argn (List length args))
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
    (def argn (List length args))
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
          (if (> c 53) #t
            (if (< c 53) #f
              (if (%py-f-nonzero-from? D (+ p 1)) #t
                (= (%py-mod (- (%py-f-code h (- p 1)) 48) 2) 1)))))
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
          (if (str? x)
            (%py-cparse x)
          ; __complex__ first, and its answer must BE a complex; then
          ; __float__, whose answer becomes the real part
          (if (%py-obj-is x)
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
                    (%py-complex-of (f))))))
            (if (null? (%py-num-kind (if (eq? x #t) 1 (if (eq? x #f) 0 x))))
              (Err raise (lit type)
                "complex() first argument must be a string or a number" ())
              (%py-complex-of x))))
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
(def %py-hash
  (fn (_ v)
    (if (eq? v #t) 1
    (if (eq? v #f) 0
    (if (%py-float-is v)
      (if (= v (Float floor v)) (Float ->int v) (first v))
    (if (%py-complex-is v)
      (+ (%py-hash (%py-cre v)) (* 1000003 (%py-hash (%py-cim v))))
    (if (eq? (%py-num-kind v) (lit int))
      v
    (if (str? v)
      (Hash fnv-1a v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__hash__"))) (if (null? m) 0 (m)))
      (Err raise (lit type) "unhashable type" ()))))))))))

; Is v a machine float?  The type-handle compare %py-num-kind uses, taken
; directly so the writer below can ask cheaply.
(def %py-float-is
  (fn (_ v) (eq? (%py-typeof-prim v) %py-th-float)))

(def %py-write ())
(set! %py-write
  (fn (_ v)
    (if (%py-float-is v)
      (display (%py-frepr v))
    (if (%py-complex-is v)
      (display (%py-crepr v))
    (if (str? v)
      ; A string inside a container shows its repr; on its own it does not.
      (display (%py-str-repr v))
      (if (eq? v #t)
        (display "True")
        (if (eq? v #f)
          (display "False")
          (if (null? v)
            (display "None")
            (if (%py-tuple-is v)
              (write v)
            (if (%py-list? v)
              ; The type's `write` handler renders it, calling back here per element.
              (write v)
              (if (%py-dict? v)
                (write v)
                ; str(e) in Python is the MESSAGE, not the repr -- `print(e)`
                ; inside an except block shows "division by zero", not
                ; "#<err:zero-division division by zero>".
                (if (Err err? v)
                  (display (v msg))
                ; An exception INSTANCE prints as its message too -- print(e)
                ; has to read the same whether the raise came from Python source
                ; or from this runtime.
                (if (%py-obj-is v)
                  (display (%py-obj-repr v))
                (if (eq? v %py-NotImplemented)
                  (display "NotImplemented")
                  (display v)))))))))))))))

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

(def %py-exc-Exception
  (%py-class-new "Exception" ()
    ; Every exception gets a message, and this is where it is stored.  A user
    ; class that defines its own __init__ overrides this and gets no message
    ; unless it sets one -- Python would have it call super().__init__, which
    ; does not exist here.
    (list
      (pair "__init__"
        (fn (_ self . args)
          (%py-setattr self "__msg__" (if (null? args) "" (first args))))))
    "Exception"))

; Exceptions print <class 'ValueError'> in Python, not <class '__main__....'>
; -- the builtins live in no module the program wrote, so the qualname is the
; bare name.  This fixes a recorded divergence in 19-exception-classes.
(def %py-exc-new (fn (_ name base) (%py-class-new name base () name)))

(def %py-exc-ArithmeticError (%py-exc-new "ArithmeticError" %py-exc-Exception))
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
(def %py-exc-SystemExit      (%py-exc-new "SystemExit"      %py-exc-Exception))
(def %py-exc-RuntimeError    (%py-exc-new "RuntimeError"    %py-exc-Exception))
(def %py-exc-SyntaxError     (%py-exc-new "SyntaxError"     %py-exc-Exception))

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
    (pair (lit state)         %py-exc-RuntimeError)))

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
      (if (eq? c target) #t (self (%py-class-base c) target)))))

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
    (if (%py-subclass? (%py-obj-class o) %py-exc-Exception)
      (display (%py-class-name (%py-obj-class o)) ": " (%py-exc-msg o))
      (display "<" (%py-class-qualname (%py-obj-class o)) " object>"))))

; The message an exception carries, for print(e) and str(e).
(def %py-exc-msg
  (fn (_ e)
    (let ((a (%py-alist-find "__msg__" (%py-obj-attrs e))))
      (if (null? a) "" (rest a)))))

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
  (fn (self cls name)
    (if (null? cls)
      ()
      (let ((e (%py-alist-find name (%py-class-methods cls))))
        (if (null? e)
          (self (%py-class-base cls) name)
          (rest e))))))

; A BOUND METHOD IS JUST A CLOSURE OVER THE OBJECT.  A method compiles to
; (fn (_ py-self ...) ...) -- the leading _ absorbs x's self-binding -- so
; calling it with the object as the first argument is all "bound" means.
(def %py-bind-method
  (fn (_ m obj) (fn (_ . args) (apply m (pair obj args)))))

(def %py-obj-attr
  (fn (_ obj name)
    (let ((e (%py-alist-find name (%py-obj-attrs obj))))
      (if (not (null? e))
        (rest e)
        (let ((m (%py-method-find (%py-obj-class obj) name)))
          (if (null? m)
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
                (ga obj name)))
            (%py-bind-method m obj)))))))

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
    (if (not (%py-obj-is obj))
      (Err raise (lit attribute) "object does not support attribute assignment" ())
      (%py-obj-set-attrs! obj (%py-attr-put (%py-obj-attrs obj) name v)))))

(def %py-mkclass
  (fn (_ name base methods)
    (%py-class-new name base methods (Str8 append "__main__." name))))

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
        (let ((o (%py-obj-new cls)))
          (let ((init (%py-method-find cls "__init__")))
            (if (null? init)
              o
              (%seq (apply init (pair o args)) o))))))))

; --- Tuples ------------------------------------------------------------------

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
(def %py-sigs (pair () ()))
(def %py-sig!
  (fn (_ f name names nreq has-rest)
    (%set-first! %py-sigs (pair (pair f (list name names nreq has-rest)) (first %py-sigs)))
    f))
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
  (fn (_ sig)
    (list (first sig) (rest (List ref 1 sig)) (- (List ref 2 sig) 1) (List ref 3 sig))))
(def %py-dflt (list (lit %py-default)))
(def %py-opt
  (fn (_ more i dflt)
    (if (>= i (List length more)) dflt
      (let ((v (List ref i more))) (if (same? v %py-dflt) dflt v)))))
(def %py-drop
  (fn (self l k) (if (= k 0) l (if (null? l) () (self (rest l) (- k 1))))))
(def %py-list-cat
  (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b)))))
; f() takes from NREQ to N positional arguments but M were given
(def %py-arity!
  (fn (_ fname more nreq ndflts)
    (if (> (List length more) ndflts)
      (Err raise (lit type)
        (Str8 append
          (Str8 append
            (Str8 append (Str8 append fname "() takes from ") (%py-str nreq))
            (Str8 append " to " (%py-str (+ nreq ndflts))))
          (Str8 append
            (Str8 append " positional arguments but " (%py-str (+ nreq (List length more))))
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
    (def n (List length names))
    (def npos (List length pos))
    (def known?
      (fn (self k ns)
        (if (null? ns) #f (if (Str8 =? k (first ns)) #t (self k (rest ns))))))
    (def check
      (fn (self ks)
        (if (null? ks) ()
          (if (known? (first (first ks)) names)
            (self (rest ks))
            (%py-kw-error fname
              (Str8 append (Str8 append "got an unexpected keyword argument '" (first (first ks))) "'"))))))
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
        (if (>= i n) (List reverse acc) (self (+ i 1) (pair (slot i) acc)))))
    (check kws)
    (if (if (> npos n) (not has-rest) #f)
      (%py-kw-error fname
        (Str8 append
          (Str8 append (Str8 append "takes " (%py-str n)) " positional arguments but ")
          (Str8 append (%py-str npos) " were given")))
      (%py-list-cat (build 0 ()) (%py-drop pos n)))))
(def %py-kwcall
  (fn (_ f pos kws)
    (if (same? f %py-print)
      (%py-print-kw pos kws)
      (if (%py-class-is f)
        (let ((init (%py-method-find f "__init__")))
          (let ((sig (if (null? init) () (%py-sig-of init))))
            (if (null? sig)
              (Err raise (lit type)
                (Str8 append (%py-class-name f) "() takes no keyword arguments") ())
              ; the class's own call door, not apply: apply wants a closure
              (%py-instantiate f (%py-kw-args (%py-sig-shift sig) pos kws)))))
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
    (if (str? obj)
      (if (Str8 =? name "format")
        (%py-strformat-kw obj pos kws)
        (let ((names (%py-str-kw-names name)))
          (if (null? names)
            (Err raise (lit type)
              (Str8 append (Str8 append "str." name) "() takes no keyword arguments") ())
            (apply (%py-str-attr obj name)
              (%py-none-holes
                (%py-kw-args (list (Str8 append "str." name) names 0 #f) pos kws))))))
      (if (%py-obj-is obj)
        (let ((m (%py-method-find (%py-obj-class obj) name)))
          (let ((sig (if (null? m) () (%py-sig-of m))))
            (if (null? sig)
              (%py-kwcall (%py-getattr obj name) pos kws)
              (apply m (pair obj (%py-kw-args (%py-sig-shift sig) pos kws))))))
        (%py-kwcall (%py-getattr obj name) pos kws)))))
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
      (List length (%py-tuple-elems v))
      (if (%py-list? v)
        (List length (%py-list-elems v))
        (Err raise (lit type) "cannot unpack non-sequence" ())))))

(def %py-unpack
  (fn (_ v n)
    (let ((got (%py-unpack-count v)))
      (if (< got n)
        (Err raise (lit value) "not enough values to unpack" ())
        (if (> got n)
          (Err raise (lit value) "too many values to unpack" ())
          (if (%py-tuple-is v) (%py-tuple-elems v) (%py-list-elems v)))))))

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
          (if (null? m)
            (Err raise (lit attribute)
              (Str8 append
                (Str8 append "'super' object has no attribute '" name) "'")
              ())
            (%py-bind-method m (%py-super-self sup))))))))

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
    (if (str? v)
      v
      (if (null? v) "None"
      (if (eq? v #t) "True"
      (if (eq? v #f) "False"
      (if (%py-float-is v)
        (%py-frepr v)
      (if (%py-complex-is v)
        (%py-crepr v)
        ; str(e) is the MESSAGE, the same rule %py-write states for print(e)
        (if (Err err? v)
          (v msg)
          (if (%py-obj-is v)
            (%py-obj-str v)
            (%py-write-to-str v)))))))))))

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
                (if (= c 92) "\\\\"
                (if (= c q) (Str8 append "\\" (Str8 sub i 1 s))
                (if (= c 10) "\\n"
                (if (= c 13) "\\r"
                (if (= c 9) "\\t"
                (if (if (< c 32) #t (= c 127)) (Str8 append "\\x" (%py-hex2 c))
                  (Str8 sub i 1 s)))))))))))))
    (let ((qs (Str8 sub (if (= q 34) 1 0) 1 "'\"")))
      (Str8 append qs (Str8 append (go 0 "") qs)))))

(def %py-repr-of
  (fn (_ v)
    (if (null? v) "None"
    (if (eq? v #t) "True"
    (if (eq? v #f) "False"
    (if (str? v)
      (%py-str-repr v)
      (if (%py-float-is v) (%py-frepr v)
        (if (%py-complex-is v) (%py-crepr v)
          (if (%py-obj-is v) (%py-obj-repr v) (%py-write-to-str v))))))))))

; str(o) and repr(o) for an object: __str__ (falling back to __repr__) and
; __repr__, each answering a string; an exception instance's str is its
; message; the default is the <qualname object> form.
(def %py-obj-default-repr
  (fn (_ o)
    (if (%py-subclass? (%py-obj-class o) %py-exc-Exception)
      (Str8 append (%py-class-name (%py-obj-class o))
        (Str8 append ": " (%py-exc-msg o)))
      (Str8 append "<" (Str8 append (%py-class-qualname (%py-obj-class o)) " object>")))))
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
(def %py-mklist-of
  (fn (_ v) (%py-list-new (%py-iter-elems v))))

; `hasattr` is defined in terms of getattr in Python too: it is "does this
; raise?", not a separate lookup, so anything reachable by attribute access is
; reachable here and the two can never disagree.
(def %py-hasattr
  (fn (_ o name) (guard (_ #f) (%seq (%py-getattr o name) #t))))

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
        (if (if (>= c 48) (<= c 57) #f) (- c 48)
          (if (if (>= c 97) (<= c 122) #f) (- c 87)
            (if (if (>= c 65) (<= c 90) #f) (- c 55) 99)))))
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
    (def n (Str8 length s))
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
            (if (if (>= c 48) (<= c 57) #f)
              (self (+ i 1) #t seen-dot seen-e)
              (if (= c 46)
                (if (if seen-dot #t seen-e) #f (self (+ i 1) seen-digit #t seen-e))
                (if (if (= c 101) #t (= c 69))
                  (if seen-e #f
                    (if (not seen-digit) #f
                      (let ((j (if (< (+ i 1) n)
                                 (if (if (= (code (+ i 1)) 43) #t (= (code (+ i 1)) 45))
                                   (+ i 2) (+ i 1))
                                 (+ i 1))))
                        (self j #f seen-dot #t))))
                  #f)))))))
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
    (def ws? (fn (_ c) (if (= c 32) #t (if (= c 9) #t (if (= c 10) #t (= c 13))))))
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
      (if (eq? h %py-th-int) (lit int)
      (if (eq? h %py-th-big) (lit int)
      (if (eq? h %py-th-float) (lit float)
      (if (eq? h %py-th-complex) (lit complex)
        ())))))))

(def %py-int-ctor
  (fn (_ . a)
    (if (null? a)
      0
      (let ((v (first a)))
        (if (eq? v #t) 1
        (if (eq? v #f) 0
        (if (str? v) (%py-int-of-str v)
        (if (%py-obj-is v)
          (let ((m (%py-dunder v "__int__")))
            (if (null? m)
              (Err raise (lit type) "int() argument must be a number or string" ())
              (m)))
          (let ((k (%py-num-kind v)))
            (if (eq? k (lit int)) v
            (if (eq? k (lit float))
              ; toward zero through the EXACT DIGITS, so int(1e19) and
              ; int(2.0 ** 100) answer bigints instead of a wrapped int64
              (let ((m (%py-fmt-int-mag v)))
                (let ((n (%py-int-of-str (rest m))))
                  (if (first m) (- 0 n) n)))
              (Err raise (lit type) "int() argument must be a number or string" ()))))))))))))

(def %py-float-ctor
  (fn (_ . a)
    (if (null? a)
      0.0
      (let ((v (first a)))
        (if (eq? v #t) 1.0
        (if (eq? v #f) 0.0
        (if (str? v) (%py-float-of-str v)
        (if (%py-obj-is v)
          (let ((m (%py-dunder v "__float__")))
            (if (null? m)
              (Err raise (lit type) "float() argument must be a number or string" ())
              (m)))
        (if (%py-bytes-is v) (%py-float-of-str (%py-bytes-str v))
          (let ((k (%py-num-kind v)))
            (if (eq? k (lit float)) v
            (if (eq? k (lit int)) (* v 1.0)
              (Err raise (lit type) "float() argument must be a number or string" ())))))))))))))

; Python's truthiness, stated once: the empties and the zeros are false and
; everything else is true.  Objects and classes are unconditionally true.
(def %py-truthy
  (fn (_ v)
    (if (eq? v #f) #f
    (if (eq? v #t) #t
    (if (null? v) #f
    (if (str? v) (> (Str8 length v) 0)
    (if (%py-list-is v) (not (null? (%py-list-elems v)))
    (if (%py-dict-is v) (not (null? (%py-dict-entries v)))
    (if (%py-tuple-is v) (not (null? (%py-tuple-elems v)))
    (if (%py-obj-is v)
      (let ((b (%py-dunder v "__bool__")))
        (if (not (null? b))
          (%py-truthy (b))
          (let ((l (%py-dunder v "__len__")))
            (if (null? l) #t (not (= (l) 0))))))
    (if (%py-class-is v) #t
      (not (= v 0)))))))))))))

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
        (Err raise (lit type) "dict() takes a dict here" ())))))

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
  (%py-class-new "int" () (list (pair "%ctor" %py-int-ctor)) "int"))
(def %py-cls-bool
  (%py-class-new "bool" %py-cls-int (list (pair "%ctor" %py-bool-ctor)) "bool"))
(def %py-cls-float
  (%py-class-new "float" () (list (pair "%ctor" %py-float-ctor)) "float"))
(def %py-cls-complex
  (%py-class-new "complex" () (list (pair "%ctor" %py-complex-ctor)) "complex"))
(def %py-cls-str
  (%py-class-new "str" () (list (pair "%ctor" %py-str-ctor)) "str"))
(def %py-cls-list
  (%py-class-new "list" () (list (pair "%ctor" %py-list-ctor)) "list"))
(def %py-cls-dict
  (%py-class-new "dict" () (list (pair "%ctor" %py-dict-ctor)) "dict"))
(def %py-cls-tuple
  (%py-class-new "tuple" () (list (pair "%ctor" %py-tuple-ctor)) "tuple"))
(def %py-cls-type
  (%py-class-new "type" () (list (pair "%ctor" %py-type-ctor)) "type"))
(def %py-cls-NoneType
  (%py-class-new "NoneType" () () "NoneType"))

(def %py-type-of
  (fn (_ v)
    (if (eq? v #t) %py-cls-bool
    (if (eq? v #f) %py-cls-bool
    (if (null? v) %py-cls-NoneType
    (if (str? v) %py-cls-str
    (if (%py-list-is v) %py-cls-list
    (if (%py-dict-is v) %py-cls-dict
    (if (%py-tuple-is v) %py-cls-tuple
    (if (%py-obj-is v) (%py-obj-class v)
    (if (%py-class-is v) %py-cls-type
      (let ((k (%py-num-kind v)))
        (if (eq? k (lit int)) %py-cls-int
        (if (eq? k (lit float)) %py-cls-float
        (if (eq? k (lit complex)) %py-cls-complex
          (Err raise (lit type) "type: unsupported value" ()))))))))))))))))

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
      (List reverse acc)
      (self (+ i step) stop step (pair i acc)))))

(def %py-slice-idxs
  (fn (_ len start stop step)
    (let ((b (%py-sl-bounds len start stop step)))
      (%py-sl-idxs (first b) (rest b) step ()))))

(def %py-sl-pick
  (fn (self elems idxs acc)
    (if (null? idxs)
      (List reverse acc)
      (self elems (rest idxs) (pair (List ref (first idxs) elems) acc)))))

(def %py-sl-chars
  (fn (self str idxs acc)
    (if (null? idxs)
      (List reverse acc)
      (self str (rest idxs) (pair (Str sub (first idxs) 1 str) acc)))))

(def %py-slice
  (fn (_ obj start stop step)
    (let ((st (if (null? step) 1 step)))
      (if (= st 0)
        (Err raise (lit value) "slice step cannot be zero" ())
        (if (str? obj)
          ; code points, like len and indexing
          (Str8 join ""
            (%py-sl-chars obj
              (%py-slice-idxs (Str length obj) start stop st) ()))
          (if (%py-list-is obj)
            (%py-list-new
              (%py-sl-pick (%py-list-elems obj)
                (%py-slice-idxs (List length (%py-list-elems obj)) start stop st) ()))
            (if (%py-tuple-is obj)
              (%py-tuple-new
                (%py-sl-pick (%py-tuple-elems obj)
                  (%py-slice-idxs (List length (%py-tuple-elems obj)) start stop st) ()))
              ; a dict gets Python's own complaint: a slice is not a key
              (Err raise (lit type) "unhashable type: 'slice'" ()))))))))

; --- def, whatever the frame depth -------------------------------------------
;
; The REPL's conditional hoists run inside a guard HANDLER, where a plain def
; binds in the handler's frame and vanishes with it.  base/def-global is the
; engine door that defines for the CALLER at any depth; the symbol comes
; quoted, the value evaluated.
(def %py-defg-prim (prim-ref (lit base) (lit def-global)))
(def %py-defg (fn (_ sym v) (%py-defg-prim sym v)))
