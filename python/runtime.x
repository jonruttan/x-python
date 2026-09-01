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
  %py-mktuple %py-tuple? %py-unpack)

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
      (if (str? b)
        ; `1 + "a"` is a TypeError in Python, not a coercion.  Without this it
        ; reached x's `+` with a string operand and answered a number.
        (Err raise (lit type) "unsupported operand type(s) for +" ())
        ; Lists concatenate through PY-LIST's own `+` op, which the engine
        ; dispatches from here.
        (+ a b)))))

(def %py-sub (fn (_ a b) (- a b)))
; STRING REPETITION IS HANDLED HERE, NOT ON THE TYPE.  A type's ops fire when
; either operand carries the type, so pushing `*` onto x's str type would change
; what `*` means for every string in the process, the platform's included.  The
; containers can have ops because they are types this bundle invented; str is
; not, so its Python rules stay behind a `str?` test.
(def %py-str-repeat
  (fn (self s n) (if (<= n 0) "" (Str8 append s (self s (- n 1))))))

(def %py-mul
  (fn (_ a b)
    (if (str? a)
      (if (str? b)
        (Err raise (lit type) "can't multiply sequence by non-int" ())
        (%py-str-repeat a b))
      (if (str? b)
        (%py-str-repeat b a)
        (* a b)))))

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
  (fn (_ a b)
    (if (= b 0)
      (Err raise (lit zero-division) "division by zero" ())
      (/ (* a 1.0) b))))

(def %py-floordiv
  (fn (_ a b)
    (if (= b 0)
      (Err raise (lit zero-division) "integer division or modulo by zero" ())
      (Num quotient a b))))
; A STRING ON THE LEFT OF % IS FORMATTING, not arithmetic -- str.__mod__ --
; and the check comes before the zero test because the right operand of a
; format is a tuple as often as a number.
(def %py-mod
  (fn (_ a b)
    (if (str? a)
      (%py-format a b)
      (if (= b 0)
        (Err raise (lit zero-division) "integer modulo by zero" ())
        (Num modulo a b)))))
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
; Class equality is IDENTITY: the builtin type objects are singletons, so
; `type(1) == type(2)` is eq? on the same object, and two distinct classes are
; never equal whatever their names.  And a string never equals a non-string --
; `1 == 'a'` is False in Python, where handing the pair to x's `=` was an error.
(def %py-eq
  (fn (_ a b)
    (if (str? a) (if (str? b) (Str8 =? a b) #f)
    (if (str? b) #f
    (if (%py-class-is a) (eq? a b)
    (if (%py-class-is b) #f
      (= a b)))))))
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
(def %py-mklist (fn (_ . elems) (%py-list-new elems)))

(def %py-list? (fn (_ v) (%py-list-is v)))

(def %py-len
  (fn (_ v)
    (if (%py-dict? v)
      (List length (%py-dict-entries v))
    (if (%py-tuple-is v)
      (List length (%py-tuple-elems v))
    (if (%py-list? v)
      (List length (%py-list-elems v))
      (if (str? v)
        (Str8 length v)
        (Err raise (lit type) "object of this type has no len()" ())))))))

; NEGATIVE INDICES COUNT FROM THE END, which is Python and not x.  -1 is the
; last element, and an index past either end raises IndexError rather than
; returning nil -- a silent nil would propagate into arithmetic and surface far
; from the subscript that produced it.
(def %py-index
  (fn (_ v i)
    (if (str? v)
      ; A string index yields a one-character STRING, as in Python -- there is
      ; no character type at this surface.
      (let ((n (Str8 length v)))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "string index out of range" ())
            (Str8 sub k 1 v))))
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
      (v i)))))))

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
    (if (%py-dict? obj)
      (%py-dset obj i v)
    (if (not (%py-list? obj))
      (Err raise (lit type) "object does not support item assignment" ())
      (let ((n (List length (%py-list-elems obj))))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "list assignment index out of range" ())
            (%py-list-set! obj (%py-set-nth (%py-list-elems obj) k v)))))))))

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

(def %py-iter-elems
  (fn (_ v)
    ; Iterating a dict yields its KEYS, as in Python.
    (if (%py-dict? v)
      (%py-dkeys (%py-dict-entries v))
    (if (%py-tuple-is v)
      (%py-tuple-elems v)
    (if (%py-list? v)
      (%py-list-elems v)
      (if (str? v)
        (%py-str-chars v 0 (Str8 length v))
        (Err raise (lit type) "object is not iterable" ())))))))

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
        (Err raise (lit attribute)
          (Str8 append (Str8 append "object has no attribute '" name) "'")()))))))))

; STRING METHODS MAP ONTO Str8, WHICH ALREADY HAS THEM -- upcase, downcase,
; trim, split, join, replace, starts?, ends?, index-of. The work here is the
; SHAPE, not the algorithm: Str8 takes its subject LAST, Python takes it first
; as the receiver, and split/join cross the list boundary so their results have
; to be tagged or untagged on the way through.
;
; find() returns -1 when absent, which is Python's contract and the reason it is
; not index() -- that one raises. Only find is here.
(def %py-str-attr
  (fn (_ s name)
    (if (Str8 =? name "upper")   (fn (_) (Str8 upcase s))
    (if (Str8 =? name "lower")   (fn (_) (Str8 downcase s))
    (if (Str8 =? name "strip")   (fn (_) (Str8 trim s))
    (if (Str8 =? name "split")
      ; Python's split returns a LIST, so the result is tagged on the way out.
      (fn (_ . a)
        (%py-list-new (Str8 split (if (null? a) " " (first a)) s)))
    (if (Str8 =? name "join")
      ; and join takes one, so it is untagged on the way in.
      (fn (_ lst)
        (if (not (%py-list? lst))
          (Err raise (lit type) "can only join an iterable of str" ())
          (Str8 join s (%py-list-elems lst))))
    (if (Str8 =? name "replace")
      (fn (_ old new) (Str8 replace old new s))
    (if (Str8 =? name "startswith") (fn (_ p) (Str8 starts? p s))
    (if (Str8 =? name "endswith")   (fn (_ p) (Str8 ends? p s))
    ; Str8 index-of answers nil for absent; Python's find answers -1. Passing
    ; the nil through would print None and, worse, compare equal to nothing --
    ; `if s.find(x) == -1` would silently never fire.
    (if (Str8 =? name "find")
      (fn (_ sub)
        (let ((i (Str8 index-of sub s)))
          (if (null? i) (- 0 1) i)))
      (Err raise (lit attribute)
        (Str8 append (Str8 append "'str' object has no attribute '" name) "'")
        ()))))))))))))

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

; Is v a machine float?  The type-handle compare %py-num-kind uses, taken
; directly so the writer below can ask cheaply.
(def %py-float-is
  (fn (_ v) (eq? (%py-typeof-prim v) %py-th-float)))

(def %py-write ())
(set! %py-write
  (fn (_ v)
    (if (%py-float-is v)
      (display (%py-frepr v))
    (if (str? v)
      ; A string inside a container shows its quotes; on its own it does not.
      (%seq (display "'") (%seq (display v) (display "'")))
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
                  (if (%py-subclass? (%py-obj-class v) %py-exc-Exception)
                    (display (%py-exc-msg v))
                    (display v))
                  (display v)))))))))))))

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
(def %py-display
  (fn (_ v)
    (if (str? v) (display v) (%py-write v))))

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
            (Err raise (lit attribute)
              (Str8 append
                (Str8 append
                  (Str8 append "'" (%py-class-name (%py-obj-class obj)))
                  "' object has no attribute '")
                (Str8 append name "'"))
              ())
            (%py-bind-method m obj)))))))

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
      (if (%py-float-is v)
        (%py-frepr v)
        ; str(e) is the MESSAGE, the same rule %py-write states for print(e)
        (if (Err err? v)
          (v msg)
          (if (if (%py-obj-is v)
                (%py-subclass? (%py-obj-class v) %py-exc-Exception)
                #f)
            (%py-exc-msg v)
            (%py-write-to-str v)))))))

(def %py-repr-of
  (fn (_ v)
    (if (str? v)
      (Str8 append (Str8 append "'" v) "'")
      (if (%py-float-is v) (%py-frepr v) (%py-write-to-str v)))))

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

(def %py-typeof-prim (prim-ref (lit type) (lit of)))
(def %py-th-int (%py-typeof-prim 1))
(def %py-th-big (%py-typeof-prim 99999999999999999999))
(def %py-th-float (%py-typeof-prim 1.5))
(def %py-char-code (prim-ref (lit char) (lit ->int)))

; --- constructors ------------------------------------------------------------
; int('abc') is a ValueError with Python's own message, and the parse is walked
; BY HAND: the reader-base shortcut accepts prefixes ("12ab" would answer 12),
; and `Float from` answers 0.0 for garbage -- both silent wrong numbers, the
; failure mode this bundle keeps finding, so neither is trusted with input the
; program supplied.

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
        ()))))))

(def %py-int-ctor
  (fn (_ . a)
    (if (null? a)
      0
      (let ((v (first a)))
        (if (eq? v #t) 1
        (if (eq? v #f) 0
        (if (str? v) (%py-int-of-str v)
          (let ((k (%py-num-kind v)))
            (if (eq? k (lit int)) v
            (if (eq? k (lit float))
              ; toward zero, which is Python's int() and what Float ->int does
              (Float ->int v)
              (Err raise (lit type) "int() argument must be a number or string" ())))))))))))

(def %py-float-ctor
  (fn (_ . a)
    (if (null? a)
      0.0
      (let ((v (first a)))
        (if (eq? v #t) 1.0
        (if (eq? v #f) 0.0
        (if (str? v) (%py-float-of-str v)
          (let ((k (%py-num-kind v)))
            (if (eq? k (lit float)) v
            (if (eq? k (lit int)) (* v 1.0)
              (Err raise (lit type) "float() argument must be a number or string" ())))))))))))

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
    (if (%py-obj-is v) #t
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
          (Err raise (lit type) "type: unsupported value" ())))))))))))))))

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
      (self str (rest idxs) (pair (Str8 sub (first idxs) 1 str) acc)))))

(def %py-slice
  (fn (_ obj start stop step)
    (let ((st (if (null? step) 1 step)))
      (if (= st 0)
        (Err raise (lit value) "slice step cannot be zero" ())
        (if (str? obj)
          (Str8 join ""
            (%py-sl-chars obj
              (%py-slice-idxs (Str8 length obj) start stop st) ()))
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
