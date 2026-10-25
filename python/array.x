; # x-python -- Python on x-lang
;
; ## python/array.x -- the array module
;
; @description array.array, a sequence of integers or floats of one declared
;   width.  The values are kept as values; the byte layout is computed at the
;   two seams that ask for it -- bytes(a), and construction from a buffer --
;   through the same encoder int.to_bytes uses, with a float's IEEE bits.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; The integer typecodes b B h H i I l L q Q, at the widths CPython uses on a
; 64-bit machine (l and L are eight bytes), and the float typecodes f and d.

(module python/array)
(import python/core
  python-f-2p52
  make-instance make-type python-add python-boolnorm python-bytes-is python-bytes-list
  python-class-new python-cls-object python-desc-new python-drop python-els-set-at python-eq
  python-f-2p64 python-f-pow python-floordiv python-ge python-gt python-in python-int-encode
  python-int-invert python-int-join python-iter-elems python-le python-length python-list-cat
  python-list-new python-lt python-mfloat python-mod python-module-new python-mul python-native-of
  python-num-py-type python-obj-is python-repr-of python-reverse python-sig! python-str-of-x python-sub
  python-sweep! python-text->x python-th-float type?)

; Doubling rather than Num expt: a power costs tens of thousands of objects
; and this table is built at load.
(def %py-arr-pow
  (fn (self n acc) (if (= n 0) acc (self (- n 1) (* acc 2)))))

; --- IEEE 754 -----------------------------------------------------------------
; A float IS its IEEE 754 double bit pattern here -- lib/x/num/float.x stores it
; that way, and python/runtime-obj.x's repr already reads the sign, exponent and
; mantissa out of it with div/mod against powers of two.  So d is that pattern,
; and f and e are the same fields narrowed and widened, rounded half to even.
; Nothing below computes a float.
;
; A finite value past the narrower range comes back as the infinity's pattern,
; which struct refuses and array('f') keeps, as CPython's cast does.

; (size exponent-bits fraction-bits bias top one sign): top is the all-ones
; exponent, one is 2**fraction-bits, and sign is the sign bit.
(def %py-ieee-format
  (fn (_ size ebits fbits)
    (list size ebits fbits (- (%py-arr-pow (- ebits 1) 1) 1) (- (%py-arr-pow ebits 1) 1)
      (%py-arr-pow fbits 1) (%py-arr-pow (+ ebits fbits) 1))))
(def python-ieee-half (%py-ieee-format 2 5 10))
(def python-ieee-single (%py-ieee-format 4 8 23))
(def python-ieee-double (%py-ieee-format 8 11 52))
(def %py-ieee-fbits (fn (_ f) (first (rest (rest f)))))
(def %py-ieee-bias (fn (_ f) (first (rest (rest (rest f))))))
(def python-ieee-top (fn (_ f) (first (rest (rest (rest (rest f)))))))
(def python-ieee-one (fn (_ f) (first (rest (rest (rest (rest (rest f))))))))
(def python-ieee-sign (fn (_ f) (first (rest (rest (rest (rest (rest (rest f)))))))))

(def python-ieee-2p63 (python-floordiv python-f-2p64 2))

; The double's pattern as an unsigned integer, and the float a pattern stands
; for -- the sign bit makes the stored pattern negative as a machine int, and
; 2**64 moves a pattern between the two readings.  -0.0's pattern is INT64_MIN,
; which has no positive counterpart in the word; the tower's + and - promote
; it like any other.
(def python-ieee-raw
  (fn (_ x)
    (let ((b (first x))) (if (< b 0) (python-add b python-f-2p64) b))))
(def %py-ieee-float
  (fn (_ u)
    (match
      ((= u 0) 0.0)
      ((< u python-ieee-2p63) (make-instance python-th-float u))
      (#t (make-instance python-th-float (python-sub u python-f-2p64))))))

; m / 2**k rounded half to even, which is how a narrower format takes the bits
; it cannot keep.
(def %py-ieee-round
  (fn (_ m k)
    (let ((p (python-f-pow 2 k)))
      (let ((q (python-floordiv m p)) (r (python-mod m p)) (h (python-f-pow 2 (- k 1))))
        (match
          ((< r h) q)
          ((< h r) (python-add q 1))
          ((= (python-mod q 2) 1) (python-add q 1))
          (#t q))))))

; The double pattern u at the narrower format f.  A double subnormal is far
; below f's smallest subnormal and rounds to zero; a carry out of the fraction
; moves the exponent up by the addition, and a pattern at or past the all-ones
; exponent is the infinity's.
(def %py-ieee-narrow
  (fn (_ u f)
    (let ((sign (if (< u python-ieee-2p63) 0 (python-ieee-sign f)))
          (hi (python-mod (python-floordiv u python-f-2p52) 2048))
          (m (python-mod u python-f-2p52)))
      (let ((one (python-ieee-one f)) (fbits (%py-ieee-fbits f))
            (inf (python-mul (python-ieee-top f) (python-ieee-one f))))
        (match
          ((= hi 2047)
            (python-add sign (python-add inf (if (= m 0) 0 (python-floordiv one 2)))))
          ((= hi 0) sign)
          (#t
            (let ((be (python-add (- hi 1023) (%py-ieee-bias f)))
                  (sig (python-add m python-f-2p52)))
              (if (< 0 be)
                (let ((n (python-add (python-mul be one)
                           (python-sub (%py-ieee-round sig (- 52 fbits)) one))))
                  (python-add sign (if (< n inf) n inf)))
                (python-add sign
                  (%py-ieee-round sig (python-sub (- 53 fbits) be)))))))))))

; The double pattern the narrower pattern n stands for.  A subnormal there is a
; normal double: its fraction shifts up until the leading bit is in place, and
; the exponent comes down with it.
(def %py-ieee-widen-shift
  (fn (self frac one k)
    (if (< frac one) (self (python-mul frac 2) one (+ k 1)) (pair frac k))))
(def %py-ieee-widen
  (fn (_ n f)
    (let ((one (python-ieee-one f)) (fbits (%py-ieee-fbits f)) (bias (%py-ieee-bias f))
          (sb (python-ieee-sign f)))
      (let ((sign (if (< n sb) 0 python-ieee-2p63)) (m (if (< n sb) n (python-sub n sb))))
        (let ((be (python-floordiv m one)) (frac (python-mod m one))
              (wide (python-f-pow 2 (- 52 fbits))))
          (match
            ((= be (python-ieee-top f))
              (python-add sign
                (python-add (python-mul 2047 python-f-2p52)
                  (if (= frac 0) 0 (python-floordiv python-f-2p52 2)))))
            ((if (= be 0) (= frac 0) #f) sign)
            ((= be 0)
              (let ((p (%py-ieee-widen-shift frac one 0)))
                (python-add sign
                  (python-add (python-mul (+ (- 1024 bias) (- 0 (rest p))) python-f-2p52)
                    (python-mul (python-sub (first p) one) wide)))))
            (#t
              (python-add sign
                (python-add (python-mul (python-add (python-sub be bias) 1023) python-f-2p52)
                  (python-mul frac wide))))))))))

; The unsigned bit pattern of the float x at format f, and back.
(def python-ieee-bits
  (fn (_ x f)
    (let ((u (python-ieee-raw x)))
      (if (same? f python-ieee-double) u (%py-ieee-narrow u f)))))
(def python-ieee-value
  (fn (_ n f)
    (%py-ieee-float (if (same? f python-ieee-double) n (%py-ieee-widen n f)))))

; (typecode size signed? low high float-format), the format nil for an integer
(def %py-arr-entry
  (fn (_ tc size signed)
    (let ((span (%py-arr-pow (* 8 size) 1)))
      (if signed
        (let ((half (Num quotient span 2)))
          (list tc size #t (- 0 half) (- half 1) ()))
        (list tc size #f 0 (- span 1) ())))))

(def %py-arr-codes
  (list
    (%py-arr-entry "b" 1 #t) (%py-arr-entry "B" 1 #f)
    (%py-arr-entry "h" 2 #t) (%py-arr-entry "H" 2 #f)
    (%py-arr-entry "i" 4 #t) (%py-arr-entry "I" 4 #f)
    (%py-arr-entry "l" 8 #t) (%py-arr-entry "L" 8 #f)
    (%py-arr-entry "q" 8 #t) (%py-arr-entry "Q" 8 #f)
    (list "f" 4 #f 0 0 python-ieee-single) (list "d" 8 #f 0 0 python-ieee-double)))

(def %py-arr-find
  (fn (self tc rows)
    (if (null? rows) ()
      (if (Str8 =? tc (first (first rows))) (first rows) (self tc (rest rows))))))

(def python-arr-info (fn (_ tc) (%py-arr-find tc %py-arr-codes)))
(def python-arr-size (fn (_ e) (List ref 1 e)))
(def %py-arr-signed? (fn (_ e) (List ref 2 e)))
(def %py-arr-low (fn (_ e) (List ref 3 e)))
(def %py-arr-high (fn (_ e) (List ref 4 e)))
; asked for every element, so read by first and rest rather than List ref, which
; is a class method call
(def %py-arr-format (fn (_ e) (first (rest (rest (rest (rest (rest e))))))))

(python-sweep!)
; --- the value ---------------------------------------------------------------
; The elements sit behind a cell: an array is mutable, and every name bound
; to one has to see a store.

(def %py-arr ())
(def %py-arr-new (fn (_ tc elems) (make-instance %py-arr (list tc elems))))
(def python-arr-is (fn (_ v) (type? v %py-arr)))
(def python-arr-tc (fn (_ v) (first (first v))))
(def python-arr-el (fn (_ v) (first (rest (first v)))))
(def python-arr-set! (fn (_ v l) (%seq (%set-first! (rest (first v)) l) ())))

; array('b') and array('b', [1, 2]) -- the empty one prints without a list.
(def %py-arr-repr
  (fn (_ v)
    (let ((tc (python-arr-tc v)) (el (python-arr-el v)))
      (Str8 append "array('"
        (Str8 append tc
          (if (null? el)
            "')"
            (Str8 append "', " (Str8 append (python-repr-of (python-list-new el)) ")"))))))))

(set! %py-arr
  (make-type
    "PY-ARRAY"
    (list
      (pair (lit write) (fn (_ self) (display (%py-arr-repr self))))
      (pair (lit length) (fn (_ self) (python-length (python-arr-el self)))))))

; --- elements ----------------------------------------------------------------

; A float element is a real number, and an f array keeps it as the single
; precision value its bits hold, so reading it back answers what was stored.
(def %py-arr-float
  (fn (_ f v)
    (let ((x (python-mfloat v)))
      (if (same? f python-ieee-double) x (python-ieee-value (python-ieee-bits x f) f)))))

(def python-arr-item
  (fn (_ e v)
    (let ((n (python-boolnorm v)))
      (match
        ((not (null? (%py-arr-format e))) (%py-arr-float (%py-arr-format e) v))
        ((not (eq? (python-num-py-type n) (lit int)))
          (Err raise (lit type) "array item must be an integer" ()))
        ((< n (%py-arr-low e))
          (Err raise (lit overflow) "value out of range for the array's typecode" ()))
        ((> n (%py-arr-high e))
          (Err raise (lit overflow) "value out of range for the array's typecode" ()))
        (#t n)))))

(def %py-arr-items
  (fn (self e vs acc)
    (if (null? vs)
      (python-reverse acc)
      (self e (rest vs) (pair (python-arr-item e (first vs)) acc)))))

; --- the byte layout ---------------------------------------------------------
; Little-endian, two's complement, which is what every machine this runs on
; uses and what the corpus's to_bytes comparisons assume.  A float is its IEEE
; bit pattern, written as an unsigned integer of the same width.

(def %py-arr-bytes
  (fn (self e el acc)
    (if (null? el)
      acc
      (self e (rest el)
        (python-list-cat acc
          (if (null? (%py-arr-format e))
            (python-int-encode (first el) (python-arr-size e) "little" (%py-arr-signed? e))
            (python-int-encode (python-ieee-bits (first el) (%py-arr-format e))
              (python-arr-size e) "little" #f)))))))

(def python-take-n
  (fn (self l k acc)
    (if (= k 0) (python-reverse acc)
      (if (null? l) (python-reverse acc) (self (rest l) (- k 1) (pair (first l) acc))))))

(def %py-arr-of-bytes
  (fn (self e bs acc)
    (if (null? bs)
      (python-reverse acc)
      (let ((big (List reverse (python-take-n bs (python-arr-size e) ()))))
        (self e (python-drop bs (python-arr-size e))
          (pair
            (match
              ((not (null? (%py-arr-format e)))
                (python-ieee-value (python-int-join big) (%py-arr-format e)))
              ((if (%py-arr-signed? e) (>= (first big) 128) #f)
                (- (- 0 (python-int-join (python-int-invert big ()))) 1))
              (#t (python-int-join big)))
            acc))))))

; --- the constructor ---------------------------------------------------------

(def %py-arr-init
  (fn (_ e src)
    (match
      ((null? src) ())
      ; a buffer is copied RAW: the bytes are the array's own, reread at its
      ; width rather than converted value by value
      ((python-bytes-is (first src))
        (let ((bs (python-bytes-list (first src))))
          (if (not (= (Num modulo (python-length bs) (python-arr-size e)) 0))
            (Err raise (lit value) "bytes length not a multiple of item size" ())
            (%py-arr-of-bytes e bs ()))))
      ; another array hands over its VALUES, which are range-checked again
      ((python-arr-is (python-native-of (first src)))
        (%py-arr-items e (python-arr-el (python-native-of (first src))) ()))
      (#t (%py-arr-items e (python-iter-elems (first src)) ())))))

(def %py-array-ctor
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type) "array() takes at least 1 argument" ())
      (let ((tc (python-text->x (first a))))
        (let ((e (python-arr-info tc)))
          (if (null? e)
            (Err raise (lit value)
              "bad typecode (must be b, B, h, H, i, I, l, L, q, Q, f or d)" ())
            (%py-arr-new tc (%py-arr-init e (rest a)))))))))

; --- the operations ----------------------------------------------------------

(def python-arr-at
  (fn (_ v i)
    (let ((el (python-arr-el v)))
      (let ((n (python-length el)))
        (let ((k (if (< (python-boolnorm i) 0) (+ n (python-boolnorm i)) (python-boolnorm i))))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "array index out of range" ())
            (List ref k el)))))))

(def python-arr-put!
  (fn (_ v i x)
    (let ((el (python-arr-el v)) (e (python-arr-info (python-arr-tc v))))
      (let ((n (python-length el)))
        (let ((k (if (< (python-boolnorm i) 0) (+ n (python-boolnorm i)) (python-boolnorm i))))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "array index out of range" ())
            ; the value is checked BEFORE the store, so a refused one leaves
            ; the element it would have replaced alone
            (let ((w (python-arr-item e x)))
              (python-arr-set! v (python-els-set-at el k w)))))))))

; Two arrays compare by their VALUES whatever their typecodes, and an array
; compares equal to nothing else -- not even to the bytes it would produce.
(def %py-arr-other (fn (_ o) (if (python-obj-is o) (python-native-of o) o)))

(def %py-arr-eq
  (fn (_ v o)
    (let ((w (%py-arr-other o)))
      (if (python-arr-is w)
        (python-eq (python-list-new (python-arr-el v)) (python-list-new (python-arr-el w)))
        #f))))

(def %py-arr-cmp!
  (fn (_ v o op)
    (let ((w (%py-arr-other o)))
      (if (python-arr-is w)
        (pair (python-list-new (python-arr-el v)) (python-list-new (python-arr-el w)))
        (Err raise (lit type)
          (Str8 append "'" (Str8 append op "' not supported between these types")) ())))))

(def python-arr-cat
  (fn (_ v o)
    (let ((w (%py-arr-other o)))
      (if (not (python-arr-is w))
        (Err raise (lit type) "can only append array to array" ())
        (if (not (Str8 =? (python-arr-tc v) (python-arr-tc w)))
          (Err raise (lit type) "bad argument type for built-in operation" ())
          (%py-arr-new (python-arr-tc v) (python-list-cat (python-arr-el v) (python-arr-el w))))))))

(def %py-arr-extend!
  (fn (_ v src)
    (let ((w (%py-arr-other src)) (e (python-arr-info (python-arr-tc v))))
      (python-arr-set! v
        (python-list-cat (python-arr-el v)
          (if (python-arr-is w)
            (%py-arr-items e (python-arr-el w) ())
            (%py-arr-items e (python-iter-elems src) ())))))))

(def %py-arr-append!
  (fn (_ v x)
    (let ((e (python-arr-info (python-arr-tc v))))
      (python-arr-set! v (python-list-cat (python-arr-el v) (list (python-arr-item e x)))))))

; The raw bytes of an array, for bytes(a) and bytearray(a).
(def python-arr-buffer
  (fn (_ v) (%py-arr-bytes (python-arr-info (python-arr-tc v)) (python-arr-el v) ())))

(python-sweep!)
; --- the surfaces ------------------------------------------------------------
; An array's own methods, for a value that is not an instance; the class
; methods below serve a subclass, which carries the value as its native.

(def python-arr-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "append") (fn (_ x) (%py-arr-append! v x)))
      ((Str8 =? name "extend") (fn (_ src) (%py-arr-extend! v src)))
      ((Str8 =? name "itemsize") (python-arr-size (python-arr-info (python-arr-tc v))))
      ((Str8 =? name "typecode") (python-str-of-x (python-arr-tc v)))
      (#t
        (Err raise (lit attribute)
          (Str8 append "'array' object has no attribute '" (Str8 append name "'")) ())))))

(def %py-arr-methods
  (list
    (pair "%ctor" %py-array-ctor)
    (pair "__len__" (fn (_ o) (python-length (python-arr-el (python-native-of o)))))
    (pair "__getitem__" (fn (_ o i) (python-arr-at (python-native-of o) i)))
    (pair "__setitem__" (fn (_ o i x) (python-arr-put! (python-native-of o) i x)))
    (pair "__iter__" (fn (_ o) (python-list-new (python-arr-el (python-native-of o)))))
    (pair "__contains__"
      (fn (_ o x) (python-in x (python-list-new (python-arr-el (python-native-of o))))))
    (pair "__eq__" (fn (_ o other) (%py-arr-eq (python-native-of o) other)))
    (pair "__add__" (fn (_ o other) (python-arr-cat (python-native-of o) other)))
    (pair "__repr__" (fn (_ o) (%py-arr-repr (python-native-of o))))
    (pair "__str__" (fn (_ o) (%py-arr-repr (python-native-of o))))
    (pair "__lt__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (python-native-of o) other "<"))) (python-lt (first p) (rest p)))))
    (pair "__le__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (python-native-of o) other "<="))) (python-le (first p) (rest p)))))
    (pair "__gt__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (python-native-of o) other ">"))) (python-gt (first p) (rest p)))))
    (pair "__ge__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (python-native-of o) other ">="))) (python-ge (first p) (rest p)))))
    (pair "append"
      (python-sig! (fn (_ o x) (%py-arr-append! (python-native-of o) x))
        "append" (list "self" "value") 2 #f () () #t))
    (pair "extend"
      (python-sig! (fn (_ o src) (%py-arr-extend! (python-native-of o) src))
        "extend" (list "self" "iterable") 2 #f () () #t))
    (pair "itemsize"
      (python-desc-new (lit property)
        (fn (_ o) (python-arr-size (python-arr-info (python-arr-tc (python-native-of o)))))))
    (pair "typecode"
      (python-desc-new (lit property)
        (fn (_ o) (python-str-of-x (python-arr-tc (python-native-of o))))))))

(def python-cls-array
  (python-class-new "array" python-cls-object %py-arr-methods "array"))

; --- the module --------------------------------------------------------------

(def python-array-module
  (fn (_) (python-module-new "array" (list (pair "array" python-cls-array)))))

(provide python/array
  python-arr-at python-arr-attr python-arr-buffer python-arr-cat python-arr-el python-arr-info
  python-arr-is python-arr-item python-arr-put! python-arr-set! python-arr-size python-arr-tc
  python-array-module python-cls-array python-ieee-2p63 python-ieee-bits python-ieee-double
  python-ieee-half python-ieee-one python-ieee-raw python-ieee-sign python-ieee-single
  python-ieee-top python-ieee-value python-take-n)
