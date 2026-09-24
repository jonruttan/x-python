; # x-python -- Python on x-lang
;
; ## python/runtime-obj.x -- print, float repr, complex, exceptions and classes
;
; @description Rendering a value and raising over one: the shortest round-trip float
;   repr, complex, the exception hierarchy, and user classes.
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
            ((%py-str-is x) (%py-cparse (%ps->x (%py-str-cps x))))
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
          (if (%py-str-is x)
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
  ; What a value hashes to, one arm per kind, so a match.
  (fn (_ v)
    (match
      ((eq? v #t) 1)
      ((eq? v #f) 0)
      ; None hashes to the constant CPython gives it
      ((null? v) 4238894112)
      ; NotImplemented is a singleton, and Python lets it be hashed.  It
      ; reaches here as an ordinary pair that nothing else claims, so it used
      ; to fall through to "unhashable type".
      ((eq? v %py-NotImplemented) (%py-id v))
      ((eq? v %py-Ellipsis) (%py-id v))
      ((%py-float-is v) (if (= v (Float floor v)) (Float ->int v) (first v)))
      ((%py-complex-is v)
        (+ (%py-hash (%py-cre v)) (* 1000003 (%py-hash (%py-cim v)))))
      ((eq? (%py-num-kind v) (lit int)) v)
      ((%py-str-is v) (%py-cp-hash (%py-str-cps v) 0))
      ; bytes hash as the str of the same characters does, as in CPython; a
      ; bytearray is unhashable
      ((%py-barr-is v) (%py-unhashable v))
      ((%py-bytes-is v) (%py-cp-hash (%py-bytes-list v) 0))
      ((%py-sl-is v) (%py-set-hash (list (%py-sl-start v) (%py-sl-stop v) (%py-sl-step v)) 0))
      ((%py-range-is v) (%py-range-hash v))
      ; an object hashes by identity unless its class says otherwise, so two
      ; instances are two keys
      ((%py-obj-is v) (%py-obj-hash v))
      ; a frozenset hashes on its elements; a set is unhashable
      ((%py-set-is v)
        (if (%py-set-frozen? v)
          (%py-set-hash (%py-set-elems v) 0)
          (%py-unhashable v)))
      ; a function, generator or class hashes by identity, as in Python
      ((%py-fn-is v) (%py-id v))
      ; a bound method hashes by its function and its receiver, so the two
      ; records `a.f` makes on two reads hash alike, as in Python
      ((%py-bound-is v) (+ (%py-id (%py-bound-fn v)) (%py-hash (%py-bound-self v))))
      ((%py-gen-is v) (%py-id v))
      ((%py-it-is v) (%py-id v))
      ((%py-class-is v) (%py-id v))
      ; super(), classmethod(f), staticmethod(f) and property(f) too
      ((%py-super-is v) (%py-id v))
      ((%py-desc-is v) (%py-id v))
      ((%py-view-is v)
        (if (Str8 =? (%py-view-kind v) "dict_values")
          (%py-set-hash (%py-view-elems v) 0)
          (Err raise (lit type)
            (Str8 append (Str8 append "unhashable type: '" (%py-view-kind v)) "'") ())))
      ((%py-tuple-is v) (%py-set-hash (%py-tuple-elems v) 0))
      (#t (%py-unhashable v)))))

; An instance hashes as its class decides (%py-hash-rule): by its __hash__,
; by the builtin value it carries, not at all, or by identity when nothing
; decides.
(def %py-obj-hash
  (fn (_ v)
    (def rule (%py-hash-rule (%py-obj-class v)))
    (match
      ((null? rule) (%py-id v))
      ((eq? rule (lit own)) (%py-hash-answer ((%py-dunder v "__hash__"))))
      ((eq? rule (lit native))
        (if (%py-hashable? (%py-native-of v)) (%py-hash (%py-native-of v)) (%py-unhashable v)))
      (#t (%py-unhashable v)))))

; What an instance's hash is decided by, read down its class and bases in
; lookup order, to the first class that has a say: one carrying a builtin's
; value (native), one defining __hash__ (own, or none when it is None), or one
; defining __eq__ alone (none) -- CPython makes __hash__ None in such a class.
; Nil when nothing decides.
(def %py-hash-rule
  (fn (_ cls)
    (if (if (null? cls) #t (same? cls %py-cls-object))
      ()
      (%py-hash-rule-rows (%py-class-methods cls) (%py-class-bases cls)))))
(def %py-hash-rule-rows
  (fn (_ rows bs)
    (def h (%py-alist-find "__hash__" rows))
    (match
      ((not (null? (%py-alist-find "%ctor" rows))) (lit native))
      ((not (null? h)) (if (null? (rest h)) (lit none) (lit own)))
      ((not (null? (%py-alist-find "__eq__" rows))) (lit none))
      (#t (%py-hash-rule-bases bs)))))
(def %py-hash-rule-bases
  (fn (self bs)
    (if (null? bs)
      ()
      (let ((r (%py-hash-rule (first bs))))
        (if (null? r) (self (rest bs)) r)))))

; What a __hash__ answered, as hash() answers it: a bool is its int, and
; anything but an int is refused.
(def %py-hash-answer
  (fn (_ h)
    (match
      ((eq? h #t) 1)
      ((eq? h #f) 0)
      ((eq? (%py-num-kind h) (lit int)) h)
      (#t (Err raise (lit type) "__hash__ method should return an integer" ())))))

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
      ((%py-str-is v) (display (%py-str-repr v)))
      ((%py-fn-is v) (display (%py-fn-repr v)))
      ((%py-bound-is v) (display (%py-bound-repr v)))
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
      ((%py-obj-is v) (%py-text-display (%py-obj-repr v)))
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
    (if (%py-str-is v)
      (%py-str-display (%py-str-cps v))
      (if (%py-obj-is v)
        (%py-text-display (%py-obj-str v))
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

; `print(..., file=x)` asks x for `write` and calls it once per piece: every
; value, every separator, and the end -- including an empty one, which is a
; write of the empty string and not a call skipped.
(def %py-print-to
  (fn (_ file sep end args)
    (let ((w (%py-getattr file "write")))
      (def %go
        (fn (self vs first?)
          (if (null? vs)
            ()
            (%seq
              (if first? () (w (%py-str-ctor sep)))
              (%seq (w (%py-str-ctor (first vs)))
                (self (rest vs) #f))))))
      (%seq (%go args #t) (w (%py-str-ctor end))))))

; print(..., sep=, end=, file=, flush=): None means the default, as in Python
(def %py-print-kw
  (fn (_ args kws)
    (def check
      (fn (self ks)
        (if (null? ks) ()
          (let ((k (first (first ks))))
            (match
              ((Str8 =? k "sep") (self (rest ks)))
              ((Str8 =? k "end") (self (rest ks)))
              ((Str8 =? k "file") (self (rest ks)))
              ; nothing here buffers, so flush= is accepted and has no work
              ((Str8 =? k "flush") (self (rest ks)))
              (#t
                (Err raise (lit type)
                  (Str8 append (Str8 append "'" k)
                    "' is an invalid keyword argument for print()")
                  ())))))))
    (def pick
      (fn (_ k dflt)
        (let ((e (%py-alist-find k kws)))
          (if (null? e) dflt (if (null? (rest e)) dflt (rest e))))))
    (check kws)
    (let ((sep (pick "sep" " ")) (end (pick "end" "\n")) (file (pick "file" ())))
      (if (null? file)
        (%py-print-with sep end args)
        (%py-print-to file sep end args)))))

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
; TWO SHAPES OF RAISED VALUE ARRIVE HERE.  A `raise` in Python source produces a
; PY-OBJ instance.  Everything this runtime raises itself -- a bad subscript, a
; missing key -- produces an Err carrying a tag symbol, because those raises
; predate classes by a long way and rewriting them would gain nothing.  The
; tag table below is the bridge: an Err's tag names the class it would have
; been, and from there both shapes of value match identically.

; EVERY CLASS DESCENDS FROM object, and until now nothing here said so:
; `class C(object)` named an unbound global, which this runtime binds to a
; shim that raises when CALLED -- so the shim arrived as a BASE, method
; lookup walked into a closure as though it were a class record, and the
; interpreter died rather than saying anything.  A root class costs one
; record and makes the ordinary path ordinary: it terminates the base chain
; the way () did, `isinstance(x, object)` is the walk it already does, and
; the guard in %py-mkclass turns any other non-class base into the TypeError
; Python raises instead of a crash.
; The default store and drop, reachable from a class's own __setattr__ and
; __delattr__ hooks -- the only way such a hook can finish its work without
; recursing into itself.  They are named because they are also the test: a
; class supplies a hook when what the walk finds is not one of these two.
(def %py-object-setattr
  (fn (_ self n v)
    (let ((name (%py-attr-name! n)))
      (%seq (%py-obj-set-attrs! self (%py-attr-put (%py-obj-attrs self) name v)) ()))))
(def %py-object-delattr
  (fn (_ self n) (%py-obj-drop-attr! self (%py-attr-name! n))))

; object.__new__(cls) allocates an instance of cls.  A builtin class is
; refused, as CPython refuses it: it carries its own constructor (%ctor), and
; an instance without the value it builds would be no int or list at all.
(def %py-object-new
  (fn (_ . args)
    (match
      ((null? args)
        (Err raise (lit type) "object.__new__(): not enough arguments" ()))
      ((not (%py-class-is (first args)))
        (Err raise (lit type)
          (Str8 append "object.__new__(X): X is not a type object ("
            (Str8 append (%py-type-name (first args)) ")")) ()))
      ((not (null? (%py-alist-find "%ctor" (%py-class-methods (first args)))))
        (Err raise (lit type)
          (Str8 append "object.__new__("
            (Str8 append (%py-class-name (first args))
              (Str8 append ") is not safe, use "
                (Str8 append (%py-class-name (first args)) ".__new__()")))) ()))
      (#t (%py-obj-new (first args))))))

(def %py-cls-object
  ; object.__new__ allocates, and having it here is what makes a user
  ; __new__ able to call super().__new__(cls), which reaches it unbound, as
  ; CPython's static __new__ is reached.
  ;
  ; object.__init__ ACCEPTS AND DOES NOTHING, which is what `super().__init__()`
  ; reaches from a class whose base is object -- the commonest line in Python
  ; that this runtime could not run, because the walk ended at a class with no
  ; methods at all.  It answers None, as every __init__ must.
  (%py-class-new "object" ()
    (list
      (pair "__new__" %py-object-new)
      (pair "__init__" (fn (_ self . args) ()))
      (pair "__setattr__" %py-object-setattr)
      (pair "__delattr__" %py-object-delattr))
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
(def %py-exc-AssertionError  (%py-exc-new "AssertionError"  %py-exc-Exception))
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
(def %py-exc-UnicodeDecodeError
  (%py-exc-new "UnicodeDecodeError" %py-exc-UnicodeError))
(def %py-exc-UnicodeEncodeError
  (%py-exc-new "UnicodeEncodeError" %py-exc-UnicodeError))

; An Err's tag names the class it would have been.  A tag with no row -- one
; raised by the platform rather than by this runtime -- answers Exception, so
; `except Exception` still catches it rather than letting it through a handler
; that looks like it should have caught it.
(def %py-tag-classes
  (list
    (pair (lit type)          %py-exc-TypeError)
    (pair (lit value)         %py-exc-ValueError)
    (pair (lit index)         %py-exc-IndexError)
    (pair (lit key)           %py-exc-KeyError)
    (pair (lit name)          %py-exc-NameError)
    (pair (lit attribute)     %py-exc-AttributeError)
    (pair (lit zero-division) %py-exc-ZeroDivisionError)
    (pair (lit overflow)      %py-exc-OverflowError)
    (pair (lit syntax)        %py-exc-SyntaxError)
    (pair (lit indent)        %py-exc-IndentationError)
    (pair (lit state)         %py-exc-RuntimeError)
    (pair (lit import)        %py-exc-ImportError)
    (pair (lit unicode-decode) %py-exc-UnicodeDecodeError)
    (pair (lit unicode-encode) %py-exc-UnicodeEncodeError)
    (pair (lit lookup)        %py-exc-LookupError)))

(def %py-tag-class
  (fn (self k rows)
    (if (null? rows)
      %py-exc-Exception
      (if (eq? k (first (first rows)))
        (rest (first rows))
        (self k (rest rows))))))

; The platform's door to an error's tag.  This straddled two spellings while
; the pin sat at v0.13.0, which said (Err kind-of e), and x-lang main had
; already moved to (Err tag e) -- the probe is gone now that the pin declares
; v0.14.0, which is the release that renamed it.  That was the instruction the
; probe left for whoever moved the pin.
(def %py-err-tag (fn (_ e) (Err tag e)))

; The class of whatever was raised, whichever of the two shapes it is.
(def %py-exc-class-of
  (fn (_ e)
    (if (%py-obj-is e)
      (%py-obj-class e)
      (%py-tag-class (%py-err-tag e) %py-tag-classes))))

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

; `except X:` -- X is an exception class, or a tuple of them, which Python
; spells as "or"; anything else is Python's TypeError, raised when an
; exception reaches the clause.
(def %py-exc-match
  (fn (_ e cls)
    (match
      ((%py-class-is cls)
        (if (%py-subclass? cls %py-exc-BaseException)
          (%py-subclass? (%py-exc-class-of e) cls)
          (%py-exc-match-refuse)))
      ((%py-tuple-is cls) (%py-exc-match-any e (%py-tuple-elems cls)))
      (#t (%py-exc-match-refuse)))))
(def %py-exc-match-refuse
  (fn (_)
    (Err raise (lit type)
      "catching classes that do not inherit from BaseException is not allowed" ())))
(def %py-exc-match-any
  (fn (self e clss)
    (if (null? clss)
      #f
      (if (%py-exc-match e (first clss)) #t (self e (rest clss))))))

; Raising an instance the runtime built: assert, and the math and array
; refusals.  A raise statement goes through %py-raise-any (python/runtime-flow.x),
; which also takes a class.
(def %py-raise
  (fn (_ inst)
    ; BaseException, not Exception: the root is raisable itself, and so are
    ; the few that sit beside Exception under it
    (if (if (%py-obj-is inst)
          (%py-subclass? (%py-obj-class inst) %py-exc-BaseException)
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

; The class whose own rows answer a name, by the walk %py-method-find takes:
; depth first and left to right below object, then object.
(def %py-method-owner
  (fn (_ cls name)
    (let ((c (%py-method-owner-below cls name)))
      (match
        ((not (null? c)) c)
        ((null? (%py-alist-find name (%py-class-methods %py-cls-object))) ())
        (#t %py-cls-object)))))
(def %py-method-owner-below
  (fn (self cls name)
    (match
      ((null? cls) ())
      ((same? cls %py-cls-object) ())
      ((not (null? (%py-alist-find name (%py-class-methods cls)))) cls)
      (#t (%py-method-owner-bases (%py-class-bases cls) name)))))
(def %py-method-owner-bases
  (fn (self bs name)
    (if (null? bs)
      ()
      (let ((c (%py-method-owner-below (first bs) name)))
        (if (null? c) (self (rest bs) name) c)))))

; A name a builtin value's own attribute table does not have, answered from its
; class's rows: a classmethod binds the class, and a method binds the value, so
; `[1].__init__([2])` and `{}.fromkeys(ks)` work as they do read off the class.
; object's rows are left out, since they read an instance's attributes and a
; builtin value has none.  A name no row has is the AttributeError, with tname
; as the type's name.
(def %py-class-row-attr
  (fn (_ cls v name tname)
    (let ((m (%py-method-find-below cls name)))
      (match
        ((null? m)
          (Err raise (lit attribute)
            (Str8 append (Str8 append "'" tname)
              (Str8 append "' object has no attribute '" (Str8 append name "'")))
            ()))
        ((%py-desc-is m)
          (if (eq? (%py-desc-kind m) (lit classmethod))
            (%py-bound-new (%py-desc-fn m) cls)
            (%py-desc-fn m)))
        ((not (%py-fn-is m)) m)
        (#t (%py-bound-new m v))))))

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
                      (%py-bound-new f (%py-obj-class obj))
                      (f obj)))))
              ; A USER DESCRIPTOR answers through its own __get__, which takes
              ; the instance and the class -- the same protocol property is a
              ; special case of.
              ((%py-desc-get? m)
                ((%py-dunder m "__get__") obj (%py-obj-class obj)))
              ((if (null? m) #f (not (%py-fn-is m))) m)
              ((Str8 =? name "__new__") m)
              ; A builtin function binds when a class this runtime provides
              ; carries it, since those are the type's methods, as
              ; `ValueError("x").__str__` is; one a program's class carries,
              ; as with `f = len`, does not.
              ((if (null? m) #f (not (%py-user-fn? m)))
                (if (%py-class-program? (%py-method-owner (%py-obj-class obj) name))
                  m
                  (%py-bound-new m obj)))
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
                        ; __getattr__ is Python code and takes a str, not the
                        ; platform string the attribute tables are keyed by.
                        (ga obj (%py-str-of-x name)))))))
              (#t (%py-bound-new m obj)))))))))

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

; The rows a program can name, as a dict's entries: keys cross over to strs,
; and the runtime's own rows stay behind -- "%native" and the like, keyed with
; a % that no identifier can begin with.
(def %py-attr-entries
  (fn (self rows)
    (match
      ((null? rows) ())
      ((= (%py-char-code (%str-ref (first (first rows)) 0)) 37) (self (rest rows)))
      (#t
        (pair (pair (%py-str-of-x (first (first rows))) (rest (first rows)))
          (self (rest rows)))))))

; Dropping an attribute the instance does not carry is an AttributeError,
; the same one whether `del obj.x` takes the plain path below or a class's
; own hook finishes through object.__delattr__.
(def %py-obj-drop-attr!
  (fn (_ obj name)
    (let ((as (%py-obj-attrs obj)))
      (if (null? (%py-alist-find name as))
        (Err raise (lit attribute)
          (Str8 append
            (Str8 append (Str8 append "'" (%py-class-name (%py-obj-class obj)))
              "' object has no attribute '")
            (Str8 append name "'"))
          ())
        (%seq (%py-obj-set-attrs! obj (%py-attr-drop as name)) ())))))

; A builtin type's qualname is its bare name; a class the program wrote is
; qualified by its module, `__main__.Foo`.  Python refuses a store or a
; delete on a builtin type, and this is the test for one.
(def %py-class-builtin?
  (fn (_ c) (Str8 =? (%py-class-qualname c) (%py-class-name c))))
; A class a class statement made, which %py-mkclass qualifies as __main__.Foo.
; The runtime's own classes, collections.deque and namedtuple's among them, are
; qualified otherwise.
(def %py-class-program?
  (fn (_ c) (Str8 starts? "__main__." (%py-class-qualname c))))
(def %py-immutable-type!
  (fn (_ verb cls name)
    (Err raise (lit type)
      (Str8 append (Str8 append "cannot " verb)
        (Str8 append (Str8 append " '" name)
          (Str8 append "' attribute of immutable type '"
            (Str8 append (%py-class-name cls) "'"))))
      ())))

(def %py-setattr
  (fn (_ obj name v)
    ; A CLASS TAKES A STORE TOO.  `C.x = 2` puts the row in the same alist the
    ; class body wrote, so instances see it through the lookup that already
    ; walks the class chain, and an instance attribute of the same name still
    ; shadows it -- %py-obj-attr reads the instance first.
    (if (%py-class-is obj)
      (if (%py-class-builtin? obj)
        (%py-immutable-type! "set" obj name)
        (%py-class-methods-set! obj (%py-attr-put (%py-class-methods obj) name v)))
      (if (not (%py-obj-is obj))
        (Err raise (lit attribute) "object does not support attribute assignment" ())
        ; __setattr__ INTERCEPTS EVERY STORE, which is the point of it: a class
        ; that defines one decides what `self.x = v` means, and gets no default
        ; store unless it makes one itself.  __getattr__ was already a hook on
        ; the read; this is the same rule on the write.  object carries a
        ; __setattr__ as well, so the lookup always finds one: a class
        ; supplies a hook when what the walk finds is not object's default,
        ; and the default is the plain store below.
        (let ((h (%py-method-find (%py-obj-class obj) "__setattr__")))
          (if (if (null? h) #f (not (same? h %py-object-setattr)))
            ; the hook is PYTHON code and takes the name as a str, not as the
            ; platform string the attribute tables below are keyed by -- the
            ; same crossing __getattr__ needs
            (%seq ((%py-bind-method h obj) (%py-str-of-x name) v) ())
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

