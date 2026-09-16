; # x-python -- Python on x-lang
;
; ## python/array.x -- the array module
;
; @description array.array, a sequence of integers of one declared width.
;   The values are kept as values; the byte layout is computed at the two
;   seams that ask for it -- bytes(a), and construction from a buffer --
;   through the same encoder int.to_bytes uses.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; Only the integer typecodes are here: b B h H i I l L q Q, at the widths
; CPython uses on a 64-bit machine (l and L are eight bytes).  The float
; codes f and d would need an IEEE encoder, which nothing else in this
; runtime has yet, and `array('f')` says so rather than pretending.

; Doubling rather than Num expt: a power costs tens of thousands of objects
; and this table is built at load.
(def %py-arr-pow
  (fn (self n acc) (if (= n 0) acc (self (- n 1) (* acc 2)))))

; (typecode size signed? low high)
(def %py-arr-entry
  (fn (_ tc size signed)
    (let ((span (%py-arr-pow (* 8 size) 1)))
      (if signed
        (let ((half (Num quotient span 2)))
          (list tc size #t (- 0 half) (- half 1)))
        (list tc size #f 0 (- span 1))))))

(def %py-arr-codes
  (list
    (%py-arr-entry "b" 1 #t) (%py-arr-entry "B" 1 #f)
    (%py-arr-entry "h" 2 #t) (%py-arr-entry "H" 2 #f)
    (%py-arr-entry "i" 4 #t) (%py-arr-entry "I" 4 #f)
    (%py-arr-entry "l" 8 #t) (%py-arr-entry "L" 8 #f)
    (%py-arr-entry "q" 8 #t) (%py-arr-entry "Q" 8 #f)))

(def %py-arr-find
  (fn (self tc rows)
    (if (null? rows) ()
      (if (Str8 =? tc (first (first rows))) (first rows) (self tc (rest rows))))))

(def %py-arr-info (fn (_ tc) (%py-arr-find tc %py-arr-codes)))
(def %py-arr-size (fn (_ e) (List ref 1 e)))
(def %py-arr-signed? (fn (_ e) (List ref 2 e)))
(def %py-arr-low (fn (_ e) (List ref 3 e)))
(def %py-arr-high (fn (_ e) (List ref 4 e)))

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

(def %py-arr-item
  (fn (_ e v)
    (let ((n (%py-boolnorm v)))
      (match
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
; uses and what the corpus's to_bytes comparisons assume.

(def %py-arr-bytes
  (fn (self e el acc)
    (if (null? el)
      acc
      (self e (rest el)
        (%py-list-cat acc
          (%py-int-encode (first el) (%py-arr-size e) "little" (%py-arr-signed? e)))))))

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
            (if (if (%py-arr-signed? e) (>= (first big) 128) #f)
              (- (- 0 (%py-int-join (%py-int-invert big ()))) 1)
              (%py-int-join big))
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
              "bad typecode (must be b, B, h, H, i, I, l, L, q or Q)" ())
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
