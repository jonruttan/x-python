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
  %py-print %py-display
  %py-mklist %py-index %py-len %py-list? %py-write)

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
; NEVER HAND Num expt A NEGATIVE EXPONENT.  Its parameter is documented
; "Non-negative integer exponent" and nothing enforces it: with exp < 0 the
; recursion never reaches 0 and SQUARES THE BASE on every even step, so it
; allocates exponentially growing bignums until the machine dies.  Not a hang --
; an unbounded-allocation bomb, and `2 ** -1` is ordinary Python.
;
; Python's answer is a float: 2 ** -1 is 0.5.
(def %py-pow
  (fn (_ a b)
    (if (< b 0)
      (/ 1.0 (Num expt a (- 0 b)))
      (Num expt a b))))
(def %py-neg (fn (_ a) (- 0 a)))

; --- Comparison --------------------------------------------------------------
(def %py-eq (fn (_ a b) (if (str? a) (if (str? b) (Str8 =? a b) #f) (= a b))))
(def %py-ne (fn (_ a b) (not (%py-eq a b))))
(def %py-lt (fn (_ a b) (< a b)))
(def %py-gt (fn (_ a b) (> a b)))
(def %py-le (fn (_ a b) (if (< a b) #t (= a b))))
(def %py-ge (fn (_ a b) (if (> a b) #t (= a b))))

; --- Lists ------------------------------------------------------------------
;
; TAGGED, not a bare x list.  An empty Python list and None are different
; values, and a bare x list would make both of them nil -- so `print([])` would
; print None.  A list is (py-list . elements): the tag distinguishes it from
; every other value this runtime produces, and from nil.
(def %py-list-tag (lit py-list))

(def %py-mklist (fn (_ . elems) (pair %py-list-tag elems)))

(def %py-list?
  (fn (_ v) (if (pair? v) (eq? (first v) %py-list-tag) #f)))

(def %py-len
  (fn (_ v)
    (if (%py-list? v)
      (List length (rest v))
      (if (str? v)
        (Str8 length v)
        (Err raise (lit type) "object of this type has no len()" ())))))

; NEGATIVE INDICES COUNT FROM THE END, which is Python and not x.  -1 is the
; last element, and an index past either end raises IndexError rather than
; returning nil -- a silent nil would propagate into arithmetic and surface far
; from the subscript that produced it.
(def %py-index
  (fn (_ v i)
    (if (not (%py-list? v))
      (Err raise (lit type) "object is not subscriptable" ())
      (let ((n (List length (rest v))))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "list index out of range" ())
            (List ref k (rest v))))))))

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
(def %py-write ())
(set! %py-write
  (fn (_ v)
    (if (str? v)
      ; A string inside a container shows its quotes; on its own it does not.
      (%seq (display "'") (%seq (display v) (display "'")))
      (if (eq? v #t)
        (display "True")
        (if (eq? v #f)
          (display "False")
          (if (null? v)
            (display "None")
            (if (%py-list? v)
              (%seq (display "[") (%seq (%py-write-elems (rest v)) (display "]")))
              (display v))))))))

(def %py-write-elems
  (fn (self elems)
    (if (null? elems)
      ()
      (%seq (%py-write (first elems))
        (if (null? (rest elems))
          ()
          (%seq (display ", ") (self (rest elems))))))))

(def %py-display
  (fn (_ v)
    (if (eq? v #t)
      (display "True")
      (if (eq? v #f)
        (display "False")
        ; Python prints None; x displays nil as nothing at all, so a program
        ; that prints a function's result would print a blank line where CPython
        ; prints None -- a difference the conformance suite compares on.
        (if (null? v)
          (display "None")
          ; A list at top level prints with its brackets, and its ELEMENTS print
          ; as reprs -- print(['a']) is ['a'], not [a].
          (if (%py-list? v)
            (%py-write v)
            (display v)))))))

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
