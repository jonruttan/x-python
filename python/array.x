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
(def %py-ieee-half (%py-ieee-format 2 5 10))
(def %py-ieee-single (%py-ieee-format 4 8 23))
(def %py-ieee-double (%py-ieee-format 8 11 52))
(def %py-ieee-fbits (fn (_ f) (first (rest (rest f)))))
(def %py-ieee-bias (fn (_ f) (first (rest (rest (rest f))))))
(def %py-ieee-top (fn (_ f) (first (rest (rest (rest (rest f)))))))
(def %py-ieee-one (fn (_ f) (first (rest (rest (rest (rest (rest f))))))))
(def %py-ieee-sign (fn (_ f) (first (rest (rest (rest (rest (rest (rest f)))))))))

(def %py-ieee-2p63 (%py-floordiv %py-f-2p64 2))

; The double's pattern as an unsigned integer, and the float a pattern stands
; for -- the sign bit makes the stored pattern negative as a machine int.
;
; -0.0 IS THE ONE PATTERN THE TOWER CANNOT ADD TO: it is INT64_MIN, and
; (- 0 INT64_MIN) and (+ INT64_MIN 2**64) both answer a corrupt bigint (one
; that prints as -9-223372036-854775808).  Both zeros are answered from their
; sign instead, which needs no arithmetic at all.
(def %py-ieee-neg-zero (%py-fcopysign 0.0 (- 0.0 1.0)))
(def %py-ieee-raw
  (fn (_ x)
    (if (= x 0.0)
      (if (< (%py-fcopysign 1.0 x) 0.0) %py-ieee-2p63 0)
      (let ((b (first x))) (if (< b 0) (%py-add b %py-f-2p64) b)))))
(def %py-ieee-float
  (fn (_ u)
    (match
      ((= u 0) 0.0)
      ((= u %py-ieee-2p63) %py-ieee-neg-zero)
      ((< u %py-ieee-2p63) (%make-instance %py-th-float u))
      (#t (%make-instance %py-th-float (%py-sub u %py-f-2p64))))))

; m / 2**k rounded half to even, which is how a narrower format takes the bits
; it cannot keep.
(def %py-ieee-round
  (fn (_ m k)
    (let ((p (%py-f-pow 2 k)))
      (let ((q (%py-floordiv m p)) (r (%py-mod m p)) (h (%py-f-pow 2 (- k 1))))
        (match
          ((< r h) q)
          ((< h r) (%py-add q 1))
          ((= (%py-mod q 2) 1) (%py-add q 1))
          (#t q))))))

; The double pattern u at the narrower format f.  A double subnormal is far
; below f's smallest subnormal and rounds to zero; a carry out of the fraction
; moves the exponent up by the addition, and a pattern at or past the all-ones
; exponent is the infinity's.
(def %py-ieee-narrow
  (fn (_ u f)
    (let ((sign (if (< u %py-ieee-2p63) 0 (%py-ieee-sign f)))
          (hi (%py-mod (%py-floordiv u %py-f-2p52) 2048))
          (m (%py-mod u %py-f-2p52)))
      (let ((one (%py-ieee-one f)) (fbits (%py-ieee-fbits f))
            (inf (%py-mul (%py-ieee-top f) (%py-ieee-one f))))
        (match
          ((= hi 2047)
            (%py-add sign (%py-add inf (if (= m 0) 0 (%py-floordiv one 2)))))
          ((= hi 0) sign)
          (#t
            (let ((be (%py-add (- hi 1023) (%py-ieee-bias f)))
                  (sig (%py-add m %py-f-2p52)))
              (if (< 0 be)
                (let ((n (%py-add (%py-mul be one)
                           (%py-sub (%py-ieee-round sig (- 52 fbits)) one))))
                  (%py-add sign (if (< n inf) n inf)))
                (%py-add sign
                  (%py-ieee-round sig (%py-sub (- 53 fbits) be)))))))))))

; The double pattern the narrower pattern n stands for.  A subnormal there is a
; normal double: its fraction shifts up until the leading bit is in place, and
; the exponent comes down with it.
(def %py-ieee-widen-shift
  (fn (self frac one k)
    (if (< frac one) (self (%py-mul frac 2) one (+ k 1)) (pair frac k))))
(def %py-ieee-widen
  (fn (_ n f)
    (let ((one (%py-ieee-one f)) (fbits (%py-ieee-fbits f)) (bias (%py-ieee-bias f))
          (sb (%py-ieee-sign f)))
      (let ((sign (if (< n sb) 0 %py-ieee-2p63)) (m (if (< n sb) n (%py-sub n sb))))
        (let ((be (%py-floordiv m one)) (frac (%py-mod m one))
              (wide (%py-f-pow 2 (- 52 fbits))))
          (match
            ((= be (%py-ieee-top f))
              (%py-add sign
                (%py-add (%py-mul 2047 %py-f-2p52)
                  (if (= frac 0) 0 (%py-floordiv %py-f-2p52 2)))))
            ((if (= be 0) (= frac 0) #f) sign)
            ((= be 0)
              (let ((p (%py-ieee-widen-shift frac one 0)))
                (%py-add sign
                  (%py-add (%py-mul (+ (- 1024 bias) (- 0 (rest p))) %py-f-2p52)
                    (%py-mul (%py-sub (first p) one) wide)))))
            (#t
              (%py-add sign
                (%py-add (%py-mul (%py-add (%py-sub be bias) 1023) %py-f-2p52)
                  (%py-mul frac wide))))))))))

; The unsigned bit pattern of the float x at format f, and back.
(def %py-ieee-bits
  (fn (_ x f)
    (let ((u (%py-ieee-raw x)))
      (if (same? f %py-ieee-double) u (%py-ieee-narrow u f)))))
(def %py-ieee-value
  (fn (_ n f)
    (%py-ieee-float (if (same? f %py-ieee-double) n (%py-ieee-widen n f)))))

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
    (list "f" 4 #f 0 0 %py-ieee-single) (list "d" 8 #f 0 0 %py-ieee-double)))

(def %py-arr-find
  (fn (self tc rows)
    (if (null? rows) ()
      (if (Str8 =? tc (first (first rows))) (first rows) (self tc (rest rows))))))

(def %py-arr-info (fn (_ tc) (%py-arr-find tc %py-arr-codes)))
(def %py-arr-size (fn (_ e) (List ref 1 e)))
(def %py-arr-signed? (fn (_ e) (List ref 2 e)))
(def %py-arr-low (fn (_ e) (List ref 3 e)))
(def %py-arr-high (fn (_ e) (List ref 4 e)))
; asked for every element, so read by first and rest rather than List ref, which
; is a class method call
(def %py-arr-format (fn (_ e) (first (rest (rest (rest (rest (rest e))))))))

; --- the value ---------------------------------------------------------------
; The elements sit behind a cell: an array is mutable, and every name bound
; to one has to see a store.

(def %py-arr ())
(def %py-arr-new (fn (_ tc elems) (%make-instance %py-arr (list tc elems))))
(def %py-arr-is (fn (_ v) (%type? v %py-arr)))
(def %py-arr-tc (fn (_ v) (first (first v))))
(def %py-arr-el (fn (_ v) (first (rest (first v)))))
(def %py-arr-set! (fn (_ v l) (%seq (%set-first! (rest (first v)) l) ())))

; array('b') and array('b', [1, 2]) -- the empty one prints without a list.
(def %py-arr-repr
  (fn (_ v)
    (let ((tc (%py-arr-tc v)) (el (%py-arr-el v)))
      (Str8 append "array('"
        (Str8 append tc
          (if (null? el)
            "')"
            (Str8 append "', " (Str8 append (%py-repr-of (%py-list-new el)) ")"))))))))

(set! %py-arr
  (%make-type
    "PY-ARRAY"
    (list
      (pair (lit write) (fn (_ self) (display (%py-arr-repr self))))
      (pair (lit length) (fn (_ self) (%py-length (%py-arr-el self)))))))

; --- elements ----------------------------------------------------------------

; A float element is a real number, and an f array keeps it as the single
; precision value its bits hold, so reading it back answers what was stored.
(def %py-arr-float
  (fn (_ f v)
    (let ((x (%py-mfloat v)))
      (if (same? f %py-ieee-double) x (%py-ieee-value (%py-ieee-bits x f) f)))))

(def %py-arr-item
  (fn (_ e v)
    (let ((n (%py-boolnorm v)))
      (match
        ((not (null? (%py-arr-format e))) (%py-arr-float (%py-arr-format e) v))
        ((not (eq? (%py-num-kind n) (lit int)))
          (Err raise (lit type) "array item must be an integer" ()))
        ((< n (%py-arr-low e))
          (Err raise (lit overflow) "value out of range for the array's typecode" ()))
        ((> n (%py-arr-high e))
          (Err raise (lit overflow) "value out of range for the array's typecode" ()))
        (#t n)))))

(def %py-arr-items
  (fn (self e vs acc)
    (if (null? vs)
      (%py-reverse acc)
      (self e (rest vs) (pair (%py-arr-item e (first vs)) acc)))))

; --- the byte layout ---------------------------------------------------------
; Little-endian, two's complement, which is what every machine this runs on
; uses and what the corpus's to_bytes comparisons assume.  A float is its IEEE
; bit pattern, written as an unsigned integer of the same width.

(def %py-arr-bytes
  (fn (self e el acc)
    (if (null? el)
      acc
      (self e (rest el)
        (%py-list-cat acc
          (if (null? (%py-arr-format e))
            (%py-int-encode (first el) (%py-arr-size e) "little" (%py-arr-signed? e))
            (%py-int-encode (%py-ieee-bits (first el) (%py-arr-format e))
              (%py-arr-size e) "little" #f)))))))

(def %py-take-n
  (fn (self l k acc)
    (if (= k 0) (%py-reverse acc)
      (if (null? l) (%py-reverse acc) (self (rest l) (- k 1) (pair (first l) acc))))))

(def %py-arr-of-bytes
  (fn (self e bs acc)
    (if (null? bs)
      (%py-reverse acc)
      (let ((big (List reverse (%py-take-n bs (%py-arr-size e) ()))))
        (self e (%py-drop bs (%py-arr-size e))
          (pair
            (match
              ((not (null? (%py-arr-format e)))
                (%py-ieee-value (%py-int-join big) (%py-arr-format e)))
              ((if (%py-arr-signed? e) (>= (first big) 128) #f)
                (- (- 0 (%py-int-join (%py-int-invert big ()))) 1))
              (#t (%py-int-join big)))
            acc))))))

; --- the constructor ---------------------------------------------------------

(def %py-arr-init
  (fn (_ e src)
    (match
      ((null? src) ())
      ; a buffer is copied RAW: the bytes are the array's own, reread at its
      ; width rather than converted value by value
      ((%py-bytes-is (first src))
        (let ((bs (%py-bytes-list (first src))))
          (if (not (= (Num modulo (%py-length bs) (%py-arr-size e)) 0))
            (Err raise (lit value) "bytes length not a multiple of item size" ())
            (%py-arr-of-bytes e bs ()))))
      ; another array hands over its VALUES, which are range-checked again
      ((%py-arr-is (%py-native-of (first src)))
        (%py-arr-items e (%py-arr-el (%py-native-of (first src))) ()))
      (#t (%py-arr-items e (%py-iter-elems (first src)) ())))))

(def %py-array-ctor
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type) "array() takes at least 1 argument" ())
      (let ((tc (%py-text->x (first a))))
        (let ((e (%py-arr-info tc)))
          (if (null? e)
            (Err raise (lit value)
              "bad typecode (must be b, B, h, H, i, I, l, L, q, Q, f or d)" ())
            (%py-arr-new tc (%py-arr-init e (rest a)))))))))

; --- the operations ----------------------------------------------------------

(def %py-arr-at
  (fn (_ v i)
    (let ((el (%py-arr-el v)))
      (let ((n (%py-length el)))
        (let ((k (if (< (%py-boolnorm i) 0) (+ n (%py-boolnorm i)) (%py-boolnorm i))))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "array index out of range" ())
            (List ref k el)))))))

(def %py-arr-put!
  (fn (_ v i x)
    (let ((el (%py-arr-el v)) (e (%py-arr-info (%py-arr-tc v))))
      (let ((n (%py-length el)))
        (let ((k (if (< (%py-boolnorm i) 0) (+ n (%py-boolnorm i)) (%py-boolnorm i))))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "array index out of range" ())
            ; the value is checked BEFORE the store, so a refused one leaves
            ; the element it would have replaced alone
            (let ((w (%py-arr-item e x)))
              (%py-arr-set! v (%py-els-set-at el k w)))))))))

; Two arrays compare by their VALUES whatever their typecodes, and an array
; compares equal to nothing else -- not even to the bytes it would produce.
(def %py-arr-other (fn (_ o) (if (%py-obj-is o) (%py-native-of o) o)))

(def %py-arr-eq
  (fn (_ v o)
    (let ((w (%py-arr-other o)))
      (if (%py-arr-is w)
        (%py-eq (%py-list-new (%py-arr-el v)) (%py-list-new (%py-arr-el w)))
        #f))))

(def %py-arr-cmp!
  (fn (_ v o op)
    (let ((w (%py-arr-other o)))
      (if (%py-arr-is w)
        (pair (%py-list-new (%py-arr-el v)) (%py-list-new (%py-arr-el w)))
        (Err raise (lit type)
          (Str8 append "'" (Str8 append op "' not supported between these types")) ())))))

(def %py-arr-cat
  (fn (_ v o)
    (let ((w (%py-arr-other o)))
      (if (not (%py-arr-is w))
        (Err raise (lit type) "can only append array to array" ())
        (if (not (Str8 =? (%py-arr-tc v) (%py-arr-tc w)))
          (Err raise (lit type) "bad argument type for built-in operation" ())
          (%py-arr-new (%py-arr-tc v) (%py-list-cat (%py-arr-el v) (%py-arr-el w))))))))

(def %py-arr-extend!
  (fn (_ v src)
    (let ((w (%py-arr-other src)) (e (%py-arr-info (%py-arr-tc v))))
      (%py-arr-set! v
        (%py-list-cat (%py-arr-el v)
          (if (%py-arr-is w)
            (%py-arr-items e (%py-arr-el w) ())
            (%py-arr-items e (%py-iter-elems src) ())))))))

(def %py-arr-append!
  (fn (_ v x)
    (let ((e (%py-arr-info (%py-arr-tc v))))
      (%py-arr-set! v (%py-list-cat (%py-arr-el v) (list (%py-arr-item e x)))))))

; The raw bytes of an array, for bytes(a) and bytearray(a).
(def %py-arr-buffer
  (fn (_ v) (%py-arr-bytes (%py-arr-info (%py-arr-tc v)) (%py-arr-el v) ())))

; --- the surfaces ------------------------------------------------------------
; An array's own methods, for a value that is not an instance; the class
; methods below serve a subclass, which carries the value as its native.

(def %py-arr-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "append") (fn (_ x) (%py-arr-append! v x)))
      ((Str8 =? name "extend") (fn (_ src) (%py-arr-extend! v src)))
      ((Str8 =? name "itemsize") (%py-arr-size (%py-arr-info (%py-arr-tc v))))
      ((Str8 =? name "typecode") (%py-str-of-x (%py-arr-tc v)))
      (#t
        (Err raise (lit attribute)
          (Str8 append "'array' object has no attribute '" (Str8 append name "'")) ())))))

(def %py-arr-methods
  (list
    (pair "%ctor" %py-array-ctor)
    (pair "__len__" (fn (_ o) (%py-length (%py-arr-el (%py-native-of o)))))
    (pair "__getitem__" (fn (_ o i) (%py-arr-at (%py-native-of o) i)))
    (pair "__setitem__" (fn (_ o i x) (%py-arr-put! (%py-native-of o) i x)))
    (pair "__iter__" (fn (_ o) (%py-list-new (%py-arr-el (%py-native-of o)))))
    (pair "__contains__"
      (fn (_ o x) (%py-in x (%py-list-new (%py-arr-el (%py-native-of o))))))
    (pair "__eq__" (fn (_ o other) (%py-arr-eq (%py-native-of o) other)))
    (pair "__add__" (fn (_ o other) (%py-arr-cat (%py-native-of o) other)))
    (pair "__repr__" (fn (_ o) (%py-arr-repr (%py-native-of o))))
    (pair "__str__" (fn (_ o) (%py-arr-repr (%py-native-of o))))
    (pair "__lt__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (%py-native-of o) other "<"))) (%py-lt (first p) (rest p)))))
    (pair "__le__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (%py-native-of o) other "<="))) (%py-le (first p) (rest p)))))
    (pair "__gt__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (%py-native-of o) other ">"))) (%py-gt (first p) (rest p)))))
    (pair "__ge__"
      (fn (_ o other)
        (let ((p (%py-arr-cmp! (%py-native-of o) other ">="))) (%py-ge (first p) (rest p)))))
    (pair "append"
      (%py-sig! (fn (_ o x) (%py-arr-append! (%py-native-of o) x))
        "append" (list "self" "value") 2 #f () () #t))
    (pair "extend"
      (%py-sig! (fn (_ o src) (%py-arr-extend! (%py-native-of o) src))
        "extend" (list "self" "iterable") 2 #f () () #t))
    (pair "itemsize"
      (%py-desc-new (lit property)
        (fn (_ o) (%py-arr-size (%py-arr-info (%py-arr-tc (%py-native-of o)))))))
    (pair "typecode"
      (%py-desc-new (lit property)
        (fn (_ o) (%py-str-of-x (%py-arr-tc (%py-native-of o))))))))

(def %py-cls-array
  (%py-class-new "array" %py-cls-object %py-arr-methods "array"))

; --- the module --------------------------------------------------------------

(def %py-array-module
  (fn (_) (%py-module-new "array" (list (pair "array" %py-cls-array)))))
