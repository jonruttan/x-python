; # x-python -- Python on x-lang
;
; ## python/cmath.x -- the cmath module
;
; @description The functions of a complex argument, each computed from the
;   real functions the float type and libm have, by the formula CPython's
;   cmath computes it with.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; The platform's complex type has the arithmetic and the polar form, and no
; function of a complex argument.  libm has them, and takes a complex by
; value, which the platform's door to libm does not pass.  So each is written
; here over the real functions.
;
; WHAT IS NOT HERE.  CPython answers an infinity or a NaN in the argument from
; a table per function, C99's, and rescales an argument whose intermediate
; products would overflow.  Here the formula answers both: an argument past
; about 1e154 in a part may overflow where CPython's does not, and the special
; values are what the real functions make of them.

(module python/cmath)
(import python/core
  python-cim python-complex-is python-cre python-div python-dunder python-fasinh python-fcopysign
  python-fcosh python-float-of-str python-flog1p python-fsinh python-ftanh python-mdomain python-mfloat
  python-module-new python-mrange-error python-obj-is python-opt python-sig! python-sweep!
  python-tuple-new)

; Negation is a product: 0.0 less 0.0 is 0.0, and the zero a cut is read by
; is the negative one.
(def %py-cm-minus-one (- 0.0 1.0))
(def %py-cm-minus-two (- 0.0 2.0))
(def %py-cm-neg (fn (_ v) (* %py-cm-minus-one v)))

(def %py-cm-re (fn (_ z) (python-cre z)))
(def %py-cm-im (fn (_ z) (python-cim z)))
(def %py-cm-make (fn (_ re im) (Complex make re im)))

; The complex a function reads: a complex is itself, an instance answers
; through __complex__ and then __float__, and a real number is its float with
; no imaginary part.
(def %py-cm-arg
  (fn (_ x)
    (match
      ((python-complex-is x) x)
      ((if (python-obj-is x) (not (null? (python-dunder x "__complex__"))) #f)
        (let ((r ((python-dunder x "__complex__"))))
          (if (python-complex-is r)
            r
            (Err raise (lit type) "__complex__ returned non-complex" ()))))
      (#t (%py-cm-make (python-mfloat x) 0.0)))))

(def %py-cm-finite?
  (fn (_ z) (if (Float finite? (%py-cm-re z)) (Float finite? (%py-cm-im z)) #f)))
(def %py-cm-nan?
  (fn (_ z) (if (Float nan? (%py-cm-re z)) #t (Float nan? (%py-cm-im z)))))
(def %py-cm-inf?
  (fn (_ z) (if (Float inf? (%py-cm-re z)) #t (Float inf? (%py-cm-im z)))))

; What a function of a finite argument answers is read as CPython reads it:
; an infinity in either part is a range error, whatever the other part is,
; and otherwise a NaN is a domain error.
(def %py-cm-checked
  (fn (_ z r)
    (match
      ((not (%py-cm-finite? z)) r)
      ((%py-cm-inf? r) (python-mrange-error))
      ((%py-cm-nan? r) (python-mdomain))
      (#t r))))

; A function of one complex argument, as the module holds it.
(def %py-cm-1
  (fn (_ f)
    (fn (_ x)
      (let ((z (%py-cm-arg x)))
        (%py-cm-checked z (f z))))))

; --- the polar form ---------------------------------------------------------------

(def %py-cm-phase
  (fn (_ z) (Float atan2 (%py-cm-im z) (%py-cm-re z))))

(def %py-cm-abs
  (fn (_ z)
    (let ((r (Float hypot (%py-cm-re z) (%py-cm-im z))))
      (if (if (Float inf? r) (%py-cm-finite? z) #f) (python-mrange-error) r))))

(def %py-cm-rect
  (fn (_ r phi)
    (%py-cm-make (* r (Float cos phi)) (* r (Float sin phi)))))

; --- exp, log and sqrt ------------------------------------------------------------

(def %py-cm-exp
  (fn (_ z)
    (let ((m (Float exp (%py-cm-re z))))
      (%py-cm-make (* m (Float cos (%py-cm-im z))) (* m (Float sin (%py-cm-im z)))))))

; The real part is the log of the modulus.  Near a modulus of 1 that log is
; near 0 and the modulus has lost the digits that say how near, so there it
; is log1p of the modulus squared less one, with the larger part M and the
; smaller N.
(def %py-cm-log-modulus
  (fn (_ m n)
    (let ((h (Float hypot m n)))
      (if (if (< 0.71 h) (< h 1.73) #f)
        (/ (python-flog1p (+ (* (- m 1.0) (+ m 1.0)) (* n n))) 2.0)
        (Float log h)))))
(def %py-cm-log
  (fn (_ z)
    (let ((ax (Float abs (%py-cm-re z))) (ay (Float abs (%py-cm-im z))))
      (if (if (= ax 0.0) (= ay 0.0) #f)
        (python-mdomain)
        (%py-cm-make
          (if (< ax ay) (%py-cm-log-modulus ay ax) (%py-cm-log-modulus ax ay))
          (%py-cm-phase z))))))

(def %py-cm-ln10 (Float log 10.0))
(def %py-cm-log10
  (fn (_ z)
    (let ((l (%py-cm-log z)))
      (%py-cm-make (/ (%py-cm-re l) %py-cm-ln10) (/ (%py-cm-im l) %py-cm-ln10)))))

; The root in the right half plane, with the imaginary part's sign the
; argument's, so the cut is the negative real axis and continuous from above.
(def %py-cm-sqrt
  (fn (_ z)
    (let ((re (%py-cm-re z)) (im (%py-cm-im z)))
      (if (if (= re 0.0) (= im 0.0) #f)
        (%py-cm-make 0.0 im)
        (let ((ax (Float abs re)) (ay (Float abs im)))
          (let ((s (Float sqrt (/ (+ ax (Float hypot ax ay)) 2.0))))
            (let ((d (/ ay (* 2.0 s))))
              (if (< re 0.0)
                (%py-cm-make d (python-fcopysign s im))
                (%py-cm-make s (python-fcopysign d im))))))))))

; --- the hyperbolic functions, and the circular ones as their rotations -----------
; f(z) for a circular f is -i g(iz) or g(iz) for its hyperbolic g, so each
; pair shares one formula and one set of cuts.

(def %py-cm-turn (fn (_ z) (%py-cm-make (%py-cm-neg (%py-cm-im z)) (%py-cm-re z))))
(def %py-cm-turn-back (fn (_ z) (%py-cm-make (%py-cm-im z) (%py-cm-neg (%py-cm-re z)))))

(def %py-cm-cosh
  (fn (_ z)
    (let ((x (%py-cm-re z)) (y (%py-cm-im z)))
      (%py-cm-make (* (python-fcosh x) (Float cos y)) (* (python-fsinh x) (Float sin y))))))
(def %py-cm-sinh
  (fn (_ z)
    (let ((x (%py-cm-re z)) (y (%py-cm-im z)))
      (%py-cm-make (* (python-fsinh x) (Float cos y)) (* (python-fcosh x) (Float sin y))))))

; Past 354 in the real part cosh squared has overflowed and tanh is 1 to the
; last bit, with an imaginary part still worth computing.
(def %py-cm-tanh
  (fn (_ z)
    (let ((x (%py-cm-re z)) (y (%py-cm-im z)))
      (if (< 354.0 (Float abs x))
        (%py-cm-make (python-fcopysign 1.0 x)
          (* 4.0 (* (* (Float sin y) (Float cos y))
                   (Float exp (* %py-cm-minus-two (Float abs x))))))
        (let ((tx (python-ftanh x)) (ty (Float tan y)) (cx (/ 1.0 (python-fcosh x))))
          (let ((den (+ 1.0 (* (* tx ty) (* tx ty)))))
            (%py-cm-make (/ (* tx (+ 1.0 (* ty ty))) den)
              (* (* (/ ty den) cx) cx))))))))

(def %py-cm-cos (fn (_ z) (%py-cm-cosh (%py-cm-turn z))))
(def %py-cm-sin (fn (_ z) (%py-cm-turn-back (%py-cm-sinh (%py-cm-turn z)))))
(def %py-cm-tan (fn (_ z) (%py-cm-turn-back (%py-cm-tanh (%py-cm-turn z)))))

(python-sweep!)
; --- the inverses -----------------------------------------------------------------
; Each from two square roots, whose cuts are the function's.

(def %py-cm-asinh
  (fn (_ z)
    (let ((s1 (%py-cm-sqrt (%py-cm-make (+ 1.0 (%py-cm-im z)) (%py-cm-neg (%py-cm-re z)))))
          (s2 (%py-cm-sqrt (%py-cm-make (- 1.0 (%py-cm-im z)) (%py-cm-re z)))))
      (%py-cm-make
        (python-fasinh (- (* (%py-cm-re s1) (%py-cm-im s2)) (* (%py-cm-re s2) (%py-cm-im s1))))
        (Float atan2 (%py-cm-im z)
          (- (* (%py-cm-re s1) (%py-cm-re s2)) (* (%py-cm-im s1) (%py-cm-im s2))))))))

(def %py-cm-acosh
  (fn (_ z)
    (let ((s1 (%py-cm-sqrt (%py-cm-make (- (%py-cm-re z) 1.0) (%py-cm-im z))))
          (s2 (%py-cm-sqrt (%py-cm-make (+ (%py-cm-re z) 1.0) (%py-cm-im z)))))
      (%py-cm-make
        (python-fasinh (+ (* (%py-cm-re s1) (%py-cm-re s2)) (* (%py-cm-im s1) (%py-cm-im s2))))
        (* 2.0 (Float atan2 (%py-cm-im s1) (%py-cm-re s2)))))))

(def %py-cm-acos
  (fn (_ z)
    (let ((s1 (%py-cm-sqrt (%py-cm-make (- 1.0 (%py-cm-re z)) (%py-cm-neg (%py-cm-im z)))))
          (s2 (%py-cm-sqrt (%py-cm-make (+ 1.0 (%py-cm-re z)) (%py-cm-im z)))))
      (%py-cm-make
        (* 2.0 (Float atan2 (%py-cm-re s1) (%py-cm-re s2)))
        (python-fasinh (- (* (%py-cm-re s2) (%py-cm-im s1)) (* (%py-cm-im s2) (%py-cm-re s1))))))))

; atanh is odd, and computed in the right half plane.  At 1 and -1 it has no
; value.
(def %py-cm-atanh
  (fn (self z)
    (let ((x (%py-cm-re z)) (y (%py-cm-im z)))
      (match
        ((< x 0.0)
          (let ((r (self (%py-cm-make (%py-cm-neg x) (%py-cm-neg y)))))
            (%py-cm-make (%py-cm-neg (%py-cm-re r)) (%py-cm-neg (%py-cm-im r)))))
        ((if (= x 1.0) (= y 0.0) #f) (python-mdomain))
        (#t
          (let ((ay (Float abs y)))
            (%py-cm-make
              (/ (python-flog1p (/ (* 4.0 x) (+ (* (- 1.0 x) (- 1.0 x)) (* ay ay)))) 4.0)
              (/ (%py-cm-neg (Float atan2 (* %py-cm-minus-two y)
                          (- (* (- 1.0 x) (+ 1.0 x)) (* ay ay))))
                2.0))))))))

(def %py-cm-asin (fn (_ z) (%py-cm-turn-back (%py-cm-asinh (%py-cm-turn z)))))
(def %py-cm-atan (fn (_ z) (%py-cm-turn-back (%py-cm-atanh (%py-cm-turn z)))))

; --- log with a base, and isclose ---------------------------------------------------

(def %py-cm-log-of
  (fn (_ x b)
    (let ((z (%py-cm-arg x)))
      (let ((l (%py-cm-checked z (%py-cm-log z))))
        (if (null? b)
          l
          (let ((w (%py-cm-arg (first b))))
            (python-div l (%py-cm-checked w (%py-cm-log w)))))))))

; isclose is math's over the modulus of the difference: a negative tolerance
; is refused, equal values are close, any other infinity is not.
(def %py-cm-within? (fn (_ d t) (if (< d t) #t (= d t))))
(def %py-cm-isclose
  (fn (_ x y . kw)
    (let ((a (%py-cm-arg x)) (b (%py-cm-arg y))
          (rel (python-mfloat (python-opt kw 0 (/ 1.0 1000000000.0))))
          (abs- (python-mfloat (python-opt kw 1 0.0))))
      (match
        ((if (< rel 0.0) #t (< abs- 0.0))
          (Err raise (lit value) "tolerances must be non-negative" ()))
        ((if (= (%py-cm-re a) (%py-cm-re b)) (= (%py-cm-im a) (%py-cm-im b)) #f) #t)
        ((if (%py-cm-inf? a) #t (%py-cm-inf? b)) #f)
        (#t
          (let ((d (Float hypot (- (%py-cm-re a) (%py-cm-re b))
                     (- (%py-cm-im a) (%py-cm-im b)))))
            (match
              ((%py-cm-within? d (* rel (Float hypot (%py-cm-re b) (%py-cm-im b)))) #t)
              ((%py-cm-within? d (* rel (Float hypot (%py-cm-re a) (%py-cm-im a)))) #t)
              (#t (%py-cm-within? d abs-)))))))))

(def python-cmath-module
  (fn (_)
    (python-module-new "cmath"
      (list
        (pair "pi" (Float pi))
        (pair "e" (Float e))
        (pair "tau" (Float tau))
        (pair "inf" (python-float-of-str "inf"))
        (pair "nan" (python-float-of-str "nan"))
        (pair "infj" (%py-cm-make 0.0 (python-float-of-str "inf")))
        (pair "nanj" (%py-cm-make 0.0 (python-float-of-str "nan")))
        (pair "phase" (fn (_ x) (%py-cm-phase (%py-cm-arg x))))
        (pair "polar"
          (fn (_ x)
            (let ((z (%py-cm-arg x)))
              (python-tuple-new (list (%py-cm-abs z) (%py-cm-phase z))))))
        (pair "rect" (fn (_ r phi) (%py-cm-rect (python-mfloat r) (python-mfloat phi))))
        (pair "exp" (%py-cm-1 %py-cm-exp))
        (pair "log" (fn (_ x . b) (%py-cm-log-of x b)))
        (pair "log10" (%py-cm-1 %py-cm-log10))
        (pair "sqrt" (%py-cm-1 %py-cm-sqrt))
        (pair "cos" (%py-cm-1 %py-cm-cos))
        (pair "sin" (%py-cm-1 %py-cm-sin))
        (pair "tan" (%py-cm-1 %py-cm-tan))
        (pair "acos" (%py-cm-1 %py-cm-acos))
        (pair "asin" (%py-cm-1 %py-cm-asin))
        (pair "atan" (%py-cm-1 %py-cm-atan))
        (pair "cosh" (%py-cm-1 %py-cm-cosh))
        (pair "sinh" (%py-cm-1 %py-cm-sinh))
        (pair "tanh" (%py-cm-1 %py-cm-tanh))
        (pair "acosh" (%py-cm-1 %py-cm-acosh))
        (pair "asinh" (%py-cm-1 %py-cm-asinh))
        (pair "atanh" (%py-cm-1 %py-cm-atanh))
        (pair "isfinite" (fn (_ x) (%py-cm-finite? (%py-cm-arg x))))
        (pair "isinf" (fn (_ x) (%py-cm-inf? (%py-cm-arg x))))
        (pair "isnan" (fn (_ x) (%py-cm-nan? (%py-cm-arg x))))
        (pair "isclose"
          (python-sig! %py-cm-isclose "isclose" (list "a" "b" "rel_tol" "abs_tol") 2 #f))))))

(provide python/cmath python-cmath-module)
