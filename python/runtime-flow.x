; # x-python -- Python on x-lang
;
; ## python/runtime-flow.x -- modules, with, tuples and generators
;
; @description Control that leaves a frame and comes back: imports, the with
;   statement's context managers, tuples, and generators over the
;   engine's re-entrant call/cc.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A FRAGMENT OF python/runtime.x, NOT A MODULE.  It carries no provide
; and is include-once'd by runtime.x in load order; the %py-* names are
; shared across the whole rather than exported.  runtime.x was one
; 6,062-line file, which the platform's linter could not analyse -- it
; ran 91 seconds and the engine died with no diagnostic at all.

; --- Modules -----------------------------------------------------------------
;
; A MODULE IS AN OBJECT of one class, and importing is looking a name up in a
; table.  There is no file system search here: this runtime runs one program,
; and the modules it can offer are the ones written below.  Everything else
; raises ImportError, which is not a limitation so much as the truth -- and it
; is what the corpus's own feature probes expect, since they wrap an import in
; a try and print SKIP when it fails.
; --- del NAME ----------------------------------------------------------------
; The engine defines a global and never removes one, so a deleted name is
; rebound to this value instead, and a name the program never binds starts out
; bound to it.  Only reads of those names go through the check.
(def %py-deleted (pair (lit %py-deleted) ()))

(def %py-name-missing!
  (fn (_ name)
    (Err raise (lit name)
      (Str8 append (Str8 append "name '" name) "' is not defined") ())))

; The value of a name that a `del` mentions.
(def %py-name-live
  (fn (_ name v) (if (same? v %py-deleted) (%py-name-missing! name) v)))

; What `del NAME` rebinds the name to: deleting a name that is already gone
; is the same NameError as reading one.
(def %py-name-gone
  (fn (_ name v) (if (same? v %py-deleted) (%py-name-missing! name) %py-deleted)))

; A module's __dict__ is its attributes as a dict: a copy, as a class's is, so
; reading it answers and writing to it does not reach the module.
(def %py-cls-module
  (%py-class-new "module" %py-cls-object
    (list
      (pair "__dict__"
        (%py-desc-new (lit property)
          (fn (_ m) (%py-dict-new (%py-attr-entries (%py-obj-attrs m)))))))
    "module"))

(def %py-module-new
  (fn (_ name rows)
    (let ((m (%py-obj-new %py-cls-module)))
      (%seq (%py-obj-set-attrs! m (pair (pair "__name__" (%py-str-of-x name)) rows)) m))))

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

; --- the math module ------------------------------------------------------
;
; Python's math is libm's surface with Python's edges: an argument may be an
; int and comes back a float, a domain error is a ValueError rather than a
; NaN, and floor/ceil/trunc answer INTS.  The platform's Float class already
; carries the libm calls, so this is the translation layer and not an
; implementation of anything numeric.
;
; The entries float.x does not bind -- erf, the hyperbolics, gamma among them --
; are bound below through its own %libm-fn, so every function here is libm's.

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
;
; A stream is the one value here that carries the protocol without being an
; instance, so it is asked through the attribute door instead of the class.
(def %py-ctx-method
  (fn (_ m name)
    (match
      ((%py-io-is m) (%py-getattr m name))
      ((not (%py-obj-is m)) (%py-ctx-error m))
      (#t
        (let ((f (%py-dunder m name)))
          (if (null? f) (%py-ctx-error m) f))))))

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

; --- async ---------------------------------------------------------------------
; A coroutine IS a generator here: `async def` compiles to a generator
; function whether or not its body yields, and `await` compiles to the same
; delegation `yield from` does.  That is what Python does too, and it is why
; a coroutine that never suspends finishes on its first send.
;
; These take the generator as an argument because delegating is something the
; GENERATOR does, not the x call stack: %py-yield-from is handed the object
; the yields talk to, so a helper can delegate on the body's behalf.

(def %py-aenter
  (fn (_ g m) (%py-yield-from g ((%py-ctx-method m "__aenter__")))))

(def %py-awith-normal
  (fn (_ g m) (%seq (%py-yield-from g ((%py-ctx-method m "__aexit__") () () ())) ())))

(def %py-awith-exc
  (fn (_ g m e)
    (let ((r (%py-yield-from g
               ((%py-ctx-method m "__aexit__")
                 (%py-exc-class-of e) (%py-exc-instance-of e) ()))))
      (if (%py-truthy r) () (error e)))))

; `async for` asks __aiter__ for the iterator and awaits each __anext__ until
; it raises StopAsyncIteration.
(def %py-aiter
  (fn (_ v)
    (if (not (%py-obj-is v))
      (Err raise (lit type) "async for requires an object with __aiter__" ())
      (let ((f (%py-dunder v "__aiter__")))
        (if (null? f) (Err raise (lit type) "async for requires an object with __aiter__" ()) (f))))))

(def %py-anext-co
  (fn (_ it)
    (let ((f (%py-dunder it "__anext__")))
      (if (null? f)
        (Err raise (lit type) "async for requires an object with __anext__" ())
        (f)))))

; the body raised: __exit__(type, value, None), and a truthy answer swallows it
(def %py-with-exc
  (fn (_ m e)
    (let ((r ((%py-exit-fn m)
               (%py-exc-class-of e) (%py-exc-instance-of e) ())))
      (if (%py-truthy r) () (error e)))))

; the exception as Python hands it to __exit__: an instance, whether it was
; raised from Python source (already one) or by this runtime (an Err, whose
; tag names the class it would have been -- the same bridge the except
; matcher walks, and Err carries its text as the SUBJECT).
(def %py-exc-instance-of
  (fn (_ e)
    (if (%py-obj-is e)
      e
      (%py-instantiate (%py-exc-class-of e) (list (Err subject-of e))))))

; The float a math function reads: an int converts, a float is itself, an
; instance answers through __float__, and anything else is Python's TypeError.
(def %py-mfloat
  (fn (_ x)
    (let ((n (%py-boolnorm x)))
      (let ((k (%py-num-kind n)))
        (match
          ((eq? k (lit float)) n)
          ((eq? k (lit int)) (* n 1.0))
          ((%py-obj-is n)
            (let ((m (%py-dunder n "__float__")))
              (if (null? m) (%py-mfloat-refused n) (%py-mfloat (m)))))
          (#t (%py-mfloat-refused n)))))))
(def %py-mfloat-refused
  (fn (_ v)
    (Err raise (lit type)
      (Str8 append "must be real number, not " (%py-class-name (%py-type-of v))) ())))

; a domain error is Python's, not a NaN
(def %py-mdomain
  (fn (_) (%py-raise (%py-instantiate %py-exc-ValueError (list "math domain error")))))

; A domain error naming the input the function expected and the float it got,
; in CPython's words, or math domain error for a function with no such words.
(def %py-mdomain-got
  (fn (_ expected v)
    (if (null? expected)
      (%py-mdomain)
      (%py-raise (%py-instantiate %py-exc-ValueError
        (list (Str8 append expected (Str8 append ", got " (%py-repr-of v)))))))))

; A one-argument function whose result is read as CPython's math_1 reads it: a
; NaN from an argument that was not one is a domain error, and an infinity from
; a finite argument is a range error where the function can overflow and a
; domain error where it cannot, as log(0.0) and atanh(1) are.
(def %py-math-1
  (fn (_ f can-overflow expected)
    (fn (_ x)
      (let ((v (%py-mfloat x)))
        (let ((r (f v)))
          (match
            ((Float nan? r) (if (Float nan? v) r (%py-mdomain-got expected v)))
            ((if (Float inf? r) (Float finite? v) #f)
              (if can-overflow (%py-mrange-error) (%py-mdomain-got expected v)))
            (#t r)))))))

; A NaN or an infinity has no integer for floor, ceil or trunc to answer.
(def %py-mfinite
  (fn (_ v)
    (if (Float nan? v)
      (Err raise (lit value) "cannot convert float NaN to integer" ())
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
          (let ((w (match
                     ((eq? k (lit floor)) (Float floor v))
                     ((eq? k (lit ceil)) (Float ceil v))
                     (#t (Float trunc v)))))
            ; from 2**62 up a double is already whole but past what ->int
            ; answers, so its integer is read off its bits
            (if (if (< w %py-mwhole-high) (< %py-mwhole-low w) #f)
              (Float ->int w)
              (%py-mwhole-bits w))))))))
(def %py-mwhole-high 4611686018427387904.0)
(def %py-mwhole-low (- 0.0 4611686018427387904.0))
; A double from 2**62 up is its 52-bit mantissa with the hidden bit, times two
; to what its exponent says -- at that size 2**10 or more -- so its integer is
; exact arithmetic on the pattern %py-ieee-raw reads.
(def %py-f-2p52 4503599627370496)
(def %py-mwhole-bits
  (fn (_ w)
    (let ((u (%py-ieee-raw w)))
      (let ((neg (>= u %py-ieee-2p63)))
        (let ((low (if neg (- u %py-ieee-2p63) u)))
          (let ((mag (* (+ %py-f-2p52 (% low %py-f-2p52))
                        (Num expt 2 (- (Num quotient low %py-f-2p52) 1075)))))
            (if neg (- 0 mag) mag)))))))

; log, log2 and log10.  An int argument is checked before it converts, as
; CPython checks it, so its message names no float.
(def %py-math-log
  (fn (_ f)
    (let ((g (%py-math-1 f #f "expected a positive input")))
      (fn (_ x)
        (let ((n (%py-boolnorm x)))
          (if (if (eq? (%py-num-kind n) (lit int)) (not (< 0 n)) #f)
            (%py-raise (%py-instantiate %py-exc-ValueError (list "expected a positive input")))
            (g n)))))))

; log(x), and log(x, base) as the quotient Python divides, where a base whose
; log is 0 is ZeroDivisionError.
(def %py-mlog-1 (%py-math-log (fn (_ v) (Float log v))))
(def %py-mlog
  (fn (_ x b)
    (let ((num (%py-mlog-1 x)))
      (if (null? b)
        num
        (let ((den (%py-mlog-1 (first b))))
          (if (= den 0.0)
            (%py-raise (%py-instantiate %py-exc-ZeroDivisionError (list "division by zero")))
            (/ num den)))))))

; pow of two finite floats reads libm's answer as CPython does: a NaN is a
; domain error, and an infinity is one from a zero base and a range error
; otherwise.  libm answers the special values as Python does already.
(def %py-mpow
  (fn (_ x y)
    (let ((r (Float pow x y)))
      (match
        ((not (if (Float finite? x) (Float finite? y) #f)) r)
        ((Float nan? r) (%py-mdomain))
        ((Float inf? r) (if (= x 0.0) (%py-mdomain) (%py-mrange-error)))
        (#t r)))))

; --- the libm entries lib/x/num/float.x does not bind ---------------------------
; Each is one row through that file's own %libm-fn, the way it binds sin and exp:
; the address resolves once into a cell a state image re-resolves.  Nothing here
; computes a function libm already has.

(def %py-ferf      (%libm-fn (lit %py-ferf)      "d->d"  "erf"))
(def %py-ferfc     (%libm-fn (lit %py-ferfc)     "d->d"  "erfc"))
(def %py-ftgamma   (%libm-fn (lit %py-ftgamma)   "d->d"  "tgamma"))
(def %py-flgamma   (%libm-fn (lit %py-flgamma)   "d->d"  "lgamma"))
(def %py-fsinh     (%libm-fn (lit %py-fsinh)     "d->d"  "sinh"))
(def %py-fcosh     (%libm-fn (lit %py-fcosh)     "d->d"  "cosh"))
(def %py-ftanh     (%libm-fn (lit %py-ftanh)     "d->d"  "tanh"))
(def %py-fasinh    (%libm-fn (lit %py-fasinh)    "d->d"  "asinh"))
(def %py-facosh    (%libm-fn (lit %py-facosh)    "d->d"  "acosh"))
(def %py-fatanh    (%libm-fn (lit %py-fatanh)    "d->d"  "atanh"))
(def %py-fexpm1    (%libm-fn (lit %py-fexpm1)    "d->d"  "expm1"))
(def %py-flog1p    (%libm-fn (lit %py-flog1p)    "d->d"  "log1p"))
(def %py-flogb     (%libm-fn (lit %py-flogb)     "d->d"  "logb"))
(def %py-fcopysign (%libm-fn (lit %py-fcopysign) "dd->d" "copysign"))

; A result that overflowed a finite argument is Python's OverflowError.
(def %py-mrange-error
  (fn (_) (%py-raise (%py-instantiate %py-exc-OverflowError (list "math range error")))))
(def %py-mrange-check
  (fn (_ r) (if (Float inf? r) (%py-mrange-error) r)))

; gamma and lgamma are libm's.  Python refuses zero and the negative integers
; before the call, where libm answers an infinity; lgamma takes the infinities,
; which are no integers to refuse.
(def %py-mgamma-refused?
  (fn (_ v) (if (= (Float floor v) v) (not (< 0.0 v)) #f)))
(def %py-mgamma-message "expected a noninteger or positive integer")
(def %py-mgamma-1 (%py-math-1 %py-ftgamma #t %py-mgamma-message))
(def %py-mlgamma-1 (%py-math-1 %py-flgamma #t %py-mgamma-message))
(def %py-mgamma
  (fn (_ x)
    (let ((v (%py-mfloat x)))
      (if (%py-mgamma-refused? v)
        (%py-mdomain-got %py-mgamma-message v)
        (%py-mgamma-1 v)))))
(def %py-mlgamma
  (fn (_ x)
    (let ((v (%py-mfloat x)))
      (if (if (Float finite? v) (%py-mgamma-refused? v) #f)
        (%py-mdomain-got %py-mgamma-message v)
        (%py-mlgamma-1 v)))))

(def %py-mfactorial
  (fn (self n acc)
    (if (< n 2) acc (self (- n 1) (* acc n)))))

; fmod keeps the DIVIDEND's sign, which is C's rule and not Python's %, and it
; is libm's fmod, which the float type's % is.  A finite x over an infinity is
; x, a NaN passes through, and an infinite x or a zero divisor is a domain error.
(def %py-mfmod
  (fn (_ a b)
    (match
      ((if (Float inf? b) (Float finite? a) #f) a)
      ((Float nan? a) a)
      ((Float nan? b) b)
      ((if (Float inf? a) #t (= b 0.0)) (%py-mdomain))
      (#t (% a b)))))


; ldexp doubles or halves x n times.  Past 2,200 steps either way the answer has
; overflowed or underflowed, so n is clamped there, and a finite x that overflows
; is a range error.
(def %py-mldexp-steps
  (fn (self x n)
    (match
      ((= n 0) x)
      ((> n 0) (self (* x 2.0) (- n 1)))
      (#t (self (/ x 2.0) (+ n 1))))))
(def %py-mldexp
  (fn (_ x n)
    (if (if (= x 0.0) #t (not (Float finite? x)))
      x
      (%py-mrange-check
        (%py-mldexp-steps x (if (> n 2200) 2200 (if (< n -2200) -2200 n)))))))

; frexp(x) is (m, e) with x = m * 2**e and 0.5 <= |m| < 1, from the exponent
; libm's logb answers; zero, an infinity and a NaN are (x, 0).  A subnormal is
; scaled up by 2**54 first, so the 2**-e that normalises it is a double.
(def %py-mmin-normal (Float pow 2.0 (- 0.0 1022.0)))
(def %py-mfrexp
  (fn (_ x)
    (if (if (= x 0.0) #t (not (Float finite? x)))
      (%py-tuple-new (list x 0))
      (let ((s (if (< (Float abs x) %py-mmin-normal) 54 0)))
        (let ((y (if (= s 0) x (* x 18014398509481984.0))))
          (let ((e (+ (Float ->int (%py-flogb y)) 1)))
            (%py-tuple-new
              (list (* y (Float pow 2.0 (* (- 0 e) 1.0))) (- e s)))))))))

; modf(x) is (fraction, whole part), both floats carrying x's sign.
(def %py-mmodf
  (fn (_ x)
    (if (Float inf? x)
      (%py-tuple-new (list (%py-fcopysign 0.0 x) x))
      (let ((w (Float trunc x)))
        (%py-tuple-new (list (%py-fcopysign (- x w) x) w))))))

; isclose is CPython's: a negative tolerance is refused, equal values are close,
; which is how an infinity is close to itself, any other infinity is not, and
; otherwise the difference is within rel_tol of either value or within abs_tol.
; Python's default rel_tol is written as a division because the reader does not
; take 1e-9 here.
(def %py-mwithin?
  (fn (_ d t) (if (< d t) #t (= d t))))
(def %py-misclose
  (fn (_ a b . kw)
    (let ((rel (%py-mfloat (%py-opt kw 0 (/ 1.0 1000000000.0))))
          (abs- (%py-mfloat (%py-opt kw 1 0.0))))
      (match
        ((if (< rel 0.0) #t (< abs- 0.0))
          (Err raise (lit value) "tolerances must be non-negative" ()))
        ((= a b) #t)
        ((if (Float inf? a) #t (Float inf? b)) #f)
        (#t
          (let ((d (Float abs (- b a))))
            (match
              ((%py-mwithin? d (Float abs (* rel b))) #t)
              ((%py-mwithin? d (Float abs (* rel a))) #t)
              (#t (%py-mwithin? d abs-)))))))))

(def %py-math-module
  (fn (_)
    (%py-module-new "math"
      (list
        (pair "pi" (Float pi))
        (pair "e" (Float e))
        (pair "tau" (Float tau))
        ; STRAIGHT TO THE PARSER, not through float(): these two spellings are
        ; the platform's strings, and the constructor takes a str -- it would
        ; refuse its own spelling of infinity.
        (pair "inf" (%py-float-of-str "inf"))
        (pair "nan" (%py-float-of-str "nan"))
        (pair "sqrt" (%py-math-1 (fn (_ v) (Float sqrt v)) #f "expected a nonnegative input"))
        (pair "exp" (%py-math-1 (fn (_ v) (Float exp v)) #t ()))
        (pair "log" (fn (_ x . b) (%py-mlog x b)))
        (pair "log2" (%py-math-log (fn (_ v) (Float log2 v))))
        (pair "log10" (%py-math-log (fn (_ v) (Float log10 v))))
        (pair "sin" (%py-math-1 (fn (_ v) (Float sin v)) #f "expected a finite input"))
        (pair "cos" (%py-math-1 (fn (_ v) (Float cos v)) #f "expected a finite input"))
        (pair "tan" (%py-math-1 (fn (_ v) (Float tan v)) #f "expected a finite input"))
        (pair "asin"
          (%py-math-1 (fn (_ v) (Float asin v)) #f "expected a number in range from -1 up to 1"))
        (pair "acos"
          (%py-math-1 (fn (_ v) (Float acos v)) #f "expected a number in range from -1 up to 1"))
        (pair "atan" (%py-math-1 (fn (_ v) (Float atan v)) #f ()))
        (pair "atan2" (fn (_ y x) (Float atan2 (%py-mfloat y) (%py-mfloat x))))
        (pair "hypot" (fn (_ a b) (Float hypot (%py-mfloat a) (%py-mfloat b))))
        (pair "pow" (fn (_ a b) (%py-mpow (%py-mfloat a) (%py-mfloat b))))
        (pair "fabs" (fn (_ x) (Float abs (%py-mfloat x))))
        (pair "fmod" (fn (_ a b) (%py-mfmod (%py-mfloat a) (%py-mfloat b))))
        (pair "copysign" (fn (_ a b) (%py-fcopysign (%py-mfloat a) (%py-mfloat b))))
        (pair "ldexp" (fn (_ x n) (%py-mldexp (%py-mfloat x) (%py-boolnorm n))))
        (pair "sinh" (%py-math-1 %py-fsinh #t ()))
        (pair "cosh" (%py-math-1 %py-fcosh #t ()))
        (pair "tanh" (%py-math-1 %py-ftanh #f ()))
        (pair "asinh" (%py-math-1 %py-fasinh #f ()))
        (pair "acosh" (%py-math-1 %py-facosh #f "expected argument value not less than 1"))
        (pair "atanh" (%py-math-1 %py-fatanh #f "expected a number between -1 and 1"))
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
        (pair "erf" (%py-math-1 %py-ferf #f ()))
        (pair "erfc" (%py-math-1 %py-ferfc #f ()))
        (pair "gamma" %py-mgamma)
        (pair "lgamma" %py-mlgamma)
        (pair "expm1" (%py-math-1 %py-fexpm1 #t ()))
        (pair "log1p" (%py-math-1 %py-flog1p #f "expected argument value > -1"))
        (pair "frexp" (fn (_ x) (%py-mfrexp (%py-mfloat x))))
        (pair "modf" (fn (_ x) (%py-mmodf (%py-mfloat x))))))))

; The types module: the type objects a program names rather than derives,
; and `coroutine`.  Awaiting here is the delegation `yield from` does, which
; accepts any generator already, so the decorator marks nothing and answers
; what it was given.
(def %py-types-module
  (fn (_)
    (%py-module-new "types"
      (list
        (pair "FunctionType" %py-cls-function)
        (pair "LambdaType" %py-cls-function)
        (pair "BuiltinFunctionType" %py-cls-builtin-function)
        (pair "BuiltinMethodType" %py-cls-builtin-function)
        (pair "MethodType" %py-cls-method)
        (pair "GeneratorType" %py-cls-generator)
        (pair "ModuleType" %py-cls-module)
        (pair "SimpleNamespace" %py-cls-SimpleNamespace)
        (pair "coroutine" (%py-sig! (fn (_ f) f) "coroutine" (list "func") 1 #f))))))

; gc: nothing here collects on its own, so collect() is the platform's own
; sweep, hand-placed as every other sweep in this bundle is.  It answers 0,
; the count of unreachable objects Python reports.
(def %py-gc-module
  (fn (_)
    (%py-module-new "gc"
      (list (pair "collect" (fn (_ . a) (%seq (Heap collect) 0)))))))

; The modules this runtime offers, each built on first import and remembered
; after.
(def %py-module-build
  (fn (_ name)
    (match
      ((Str8 =? name "sys") (%py-sys-module))
      ((Str8 =? name "math") (%py-math-module))
      ((Str8 =? name "collections") (%py-collections-module))
      ((Str8 =? name "array") (%py-array-module))
      ((Str8 =? name "struct") (%py-struct-module))
      ((Str8 =? name "types") (%py-types-module))
      ((Str8 =? name "io") (%py-io-module))
      ((Str8 =? name "gc") (%py-gc-module))
      ((Str8 =? name "builtins") (%py-module-new "builtins" ()))
      (#t ()))))

; THE NAME HERE IS THE PLATFORM'S STRING, not a str.  This is the INTERNAL
; door: the parser calls it with a name it read out of the source, and the
; module table is keyed the same way.  `__import__()` is the Python-facing
; door, and it is the one that crosses a str over -- putting the check here
; instead would reject every `import x` the parser ever emitted.
(def %py-import
  (fn (_ name)
    (if (= (Str8 length name) 0)
      (Err raise (lit value) "empty module name" ())
      (let ((have (%py-module-find name (first %py-modules))))
        (if (not (null? have))
          have
          (let ((built (%py-module-build name)))
            (if (null? built)
              (Err raise (lit import)
                (Str8 append (Str8 append "No module named '" name) "'") ())
              (%py-module-put! name built))))))))

; `from X import a, b` and `from X import *` both read attributes off the
; module the same way an ordinary program would.
(def %py-import-call
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type)
        "__import__() missing required argument 'name'" ())
      (let ((n (first a)))
        (if (not (%py-str-is n))
          (Err raise (lit type) "module name must be a string" ())
          (%py-import (%ps->x (%py-str-cps n))))))))

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
            ; __set_name__ is Python code and takes the name as a str
            (let ((m (%py-dunder v "__set_name__")))
              (if (null? m) () (m cls (%py-str-of-x (first (first rows))))))
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
                ; the builtin base builds the value, and the instance keeps it.
                ; `class mylist(list)` then holds a real list, and a class whose
                ; own __init__ takes other arguments still gets an empty one to
                ; start from.
                (let ((cc (%py-ctor-class cls)))
                  (if (null? cc)
                    ()
                    (%py-obj-native! o (%py-native-new cc args))))
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

; The value a new instance of a builtin's subclass carries, built by the %ctor
; of cc, the class it inherits that constructor from.
;
; A builtin that fills itself in its own __init__ -- list, dict and set -- is
; built empty, as its __new__ builds it in Python.  Whichever __init__ runs
; reads the arguments: the builtin's fills the value, and a subclass's own that
; never calls it leaves the value empty.
;
; Otherwise the arguments go to the constructor, as __new__ receives them in
; Python, and that is the only way an immutable builtin can be built at all.  A
; class whose own __init__ takes different arguments makes that call raise, and
; then the empty value is right.
(def %py-native-new
  (fn (_ cc args)
    (let ((bc (rest (%py-alist-find "%ctor" (%py-class-methods cc)))))
      (if (null? (%py-alist-find "__init__" (%py-class-methods cc)))
        (guard (e (bc)) (apply bc args))
        (bc)))))

; The class a class inherits its %ctor from -- the builtin base, found by the
; same base walk everything else uses -- or nil for a class of its own.
(def %py-ctor-class
  (fn (self cls)
    (if (null? cls)
      ()
      (if (null? (%py-alist-find "%ctor" (%py-class-methods cls)))
        (%py-ctor-class-bases (%py-class-bases cls))
        cls))))

; The %ctor a class INHERITS, if any.
(def %py-inherited-ctor
  (fn (_ cls)
    (let ((c (%py-ctor-class cls)))
      (if (null? c) () (rest (%py-alist-find "%ctor" (%py-class-methods c)))))))

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
(def %py-ctor-class-bases
  (fn (self bs)
    (if (null? bs)
      ()
      (let ((c (%py-ctor-class (first bs))))
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
; No exception is active outside a handler: the name every compiled handler
; binds to the one it caught is nil here, and a bare `raise` finds it so.
(def %py-exc ())
(def %py-reraise
  (fn (_ e)
    (if (null? e)
      (%py-raise
        (%py-instantiate %py-exc-RuntimeError (list "No active exception to reraise")))
      (error e))))
; the instance a raise statement or a generator's throw() raises: a class
; derived from BaseException instantiates, an instance of one is itself,
; anything else -- 1, int, an ordinary object -- is Python's TypeError
(def %py-exc-value
  (fn (_ e)
    (if (%py-thrown-is? e %py-exc-BaseException)
      (%py-exc-instance e ())
      (Err raise (lit type) "exceptions must derive from BaseException" ()))))
(def %py-raise-any (fn (_ e) (error (%py-exc-value e))))
; `raise X from Y` records the cause on the instance: None, or an exception
; class or instance; anything else is Python's TypeError
(def %py-raise-from
  (fn (_ e c)
    (let ((inst (%py-exc-value e)))
      (%py-setattr inst "__cause__" (%py-cause-value c))
      (error inst))))
(def %py-cause-value
  (fn (_ c)
    (match
      ((null? c) ())
      ((%py-thrown-is? c %py-exc-BaseException) (%py-exc-instance c ()))
      (#t
        (Err raise (lit type)
          "exception causes must derive from BaseException" ())))))
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
      ((Str8 =? name "__name__") (%py-str-of-x (%py-gen-name g)))
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
      ((if (%py-str-is a) (%py-str-is b) #f) (%pb-eq? (%py-str-cps a) (%py-str-cps b)))
      ((if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
        (= a b))
      (#t #f))))

; sum(iterable[, start]) -- NOT %py-sum, which is the parser's arithmetic level
(def %py-builtin-sum
  (fn (_ it . st)
    (def go (fn (self es acc) (if (null? es) acc (self (rest es) (%py-add acc (first es))))))
    (go (%py-iter-elems it) (if (null? st) 0 (first st)))))

; map(f, it) is LAZY -- a generator pulling from its source -- so a
; StopIteration raised by f ends it where a yield from expects.  f is called
; through %py-apply-any, so map(tuple, ...) works like any other callable.
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
                  (pair (%py-iter-answer it) ())
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

