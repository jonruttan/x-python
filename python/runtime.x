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

(provide python/runtime
  %py-add %py-sub %py-mul %py-div %py-floordiv %py-mod %py-pow %py-neg
  %py-eq %py-ne %py-lt %py-gt %py-le %py-ge
  %py-print %py-display)

; --- Arithmetic --------------------------------------------------------------
; `+` dispatches on the operands, and the string case is not an extra: Python
; spells concatenation with it, and every conformance program that builds a
; message uses it.
(def %py-add
  (fn (_ a b)
    (if (str? a)
      (if (str? b)
        (Str8 append a b)
        (Err raise (lit type) "can only concatenate str to str" ()))
      (+ a b))))

(def %py-sub (fn (_ a b) (- a b)))
(def %py-mul (fn (_ a b) (* a b)))

; TRUE DIVISION ALWAYS PRODUCES A FLOAT.  `1 / 2` is 0.5 in Python 3 and an
; exact 1/2 in x, and that difference is the reason this bundle declares xenon
; -- float is reachable from the first arithmetic a beginner types.
(def %py-div (fn (_ a b) (/ (* a 1.0) b)))

(def %py-floordiv (fn (_ a b) (Num quotient a b)))
(def %py-mod (fn (_ a b) (Num modulo a b)))
(def %py-pow (fn (_ a b) (Num expt a b)))
(def %py-neg (fn (_ a) (- 0 a)))

; --- Comparison --------------------------------------------------------------
(def %py-eq (fn (_ a b) (if (str? a) (if (str? b) (Str8 =? a b) #f) (= a b))))
(def %py-ne (fn (_ a b) (not (%py-eq a b))))
(def %py-lt (fn (_ a b) (< a b)))
(def %py-gt (fn (_ a b) (> a b)))
(def %py-le (fn (_ a b) (if (< a b) #t (= a b))))
(def %py-ge (fn (_ a b) (if (> a b) #t (= a b))))

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
(def %py-display
  (fn (_ v)
    (if (eq? v #t)
      (display "True")
      (if (eq? v #f)
        (display "False")
        (display v)))))

(def %py-print
  (fn (_ . args)
    (def %go
      (fn (self vs first?)
        (if (null? vs)
          ()
          (%seq
            (if first? () (display " "))
            (%seq (%py-display (first vs))
              (self (rest vs) #f))))))
    (%seq (%go args #t) (newline))))
