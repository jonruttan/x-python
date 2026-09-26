; # x-python -- Python on x-lang
;
; ## python/memoryview.x -- memoryview
;
; @description A view over the elements of a bytes, bytearray or array: the
;   target itself, the element positions it covers, and the typecode naming
;   their width.  Nothing is copied, and a store reaches the target's own
;   storage -- which is the whole point of the type, and what makes `m[0] = 1`
;   show in the bytearray the program still holds.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; THE ELEMENTS ARE THE TARGET'S OWN VALUES, not its bytes.  An array here holds
; the values its typecode names (python/array.x), so a view over array('h')
; yields those values, as Python's does, and one over bytes yields ints under
; the code B.  Only bytes is read-only: a bytearray and an array are written
; through.

(module python/memoryview)
(import python/array %py-arr-buffer %py-arr-el %py-arr-info %py-arr-is
  %py-arr-item %py-arr-set! %py-arr-size %py-arr-tc %py-take-n)

(def %py-mv ())
(def %py-mv-new
  (fn (_ t start stop code) (%make-instance %py-mv (list t start stop code))))
(def %py-mv-is (fn (_ v) (%type? v %py-mv)))
(def %py-mv-target (fn (_ v) (first (first v))))
(def %py-mv-start (fn (_ v) (first (rest (first v)))))
(def %py-mv-stop (fn (_ v) (first (rest (rest (first v))))))
(def %py-mv-code (fn (_ v) (first (rest (rest (rest (first v)))))))

; The target's elements, and the store that puts them back.
(def %py-mv-all
  (fn (_ t) (if (%py-arr-is t) (%py-arr-el t) (%py-bytes-list t))))
(def %py-mv-store!
  (fn (_ t l) (if (%py-arr-is t) (%py-arr-set! t l) (%py-barr-set! t l))))
(def %py-mv-readonly? (fn (_ v) (%py-bytes-only? (%py-mv-target v))))
(def %py-mv-len (fn (_ v) (- (%py-mv-stop v) (%py-mv-start v))))
(def %py-mv-elems
  (fn (_ v)
    (%py-take-n (%py-drop (%py-mv-all (%py-mv-target v)) (%py-mv-start v))
      (%py-mv-len v) ())))

(def %py-mv-readonly!
  (fn (_) (Err raise (lit type) "cannot modify read-only memory" ())))

; One element, as the target would check it: an array's typecode does the
; range, and a byte is the 0-255 bytes() takes.
(def %py-mv-item
  (fn (_ t x)
    (if (%py-arr-is t)
      (%py-arr-item (%py-arr-info (%py-arr-tc t)) x)
      (first (%py-bytes-of-codes (list x) ())))))

(def %py-mv-slot
  (fn (_ v i)
    (let ((n (%py-mv-len v)))
      (let ((k (if (< (%py-boolnorm i) 0) (+ n (%py-boolnorm i)) (%py-boolnorm i))))
        (if (if (< k 0) #t (>= k n))
          (Err raise (lit index) "index out of bounds on dimension 1" ())
          (+ (%py-mv-start v) k))))))

(def %py-mv-at
  (fn (_ v i) (List ref (%py-mv-slot v i) (%py-mv-all (%py-mv-target v)))))

(def %py-mv-put!
  (fn (_ v i x)
    (if (%py-mv-readonly? v)
      (%py-mv-readonly!)
      (let ((t (%py-mv-target v)))
        (%py-mv-store! t
          (%py-set-nth (%py-mv-all t) (%py-mv-slot v i) (%py-mv-item t x)))))))

; A view of a view shares the target, so a store still reaches it.
(def %py-mv-slice
  (fn (_ v start stop step)
    (let ((sp (%py-slice-span (%py-mv-len v) start stop step)))
      (%py-mv-new (%py-mv-target v) (+ (%py-mv-start v) (first sp))
        (+ (%py-mv-start v) (rest sp)) (%py-mv-code v)))))

; A buffer: bytes, a bytearray, an array, or a view of one.  An array reaches a
; program wrapped in its instance, so the question is asked of what a value
; carries -- here rather than at each of the places that ask it.
(def %py-buffer?
  (fn (_ v0)
    (let ((v (%py-native-of v0)))
      (match ((%py-mv-is v) #t) ((%py-bytes-is v) #t) (#t (%py-arr-is v))))))

; The BYTES a buffer offers, which is not always its elements: a view of an
; array covers its span of the array's own byte layout.  str(), int(), bytes()
; and eval() read a buffer through here, so each of them takes every one.
(def %py-mv-bytes
  (fn (_ v)
    (let ((t (%py-mv-target v)))
      (if (%py-arr-is t)
        (let ((w (%py-mv-itemsize v)))
          (%py-take-n (%py-drop (%py-arr-buffer t) (* (%py-mv-start v) w))
            (* (%py-mv-len v) w) ()))
        (%py-mv-elems v)))))
(def %py-buffer-bytes
  (fn (_ v0)
    (let ((v (%py-native-of v0)))
      (match
        ((%py-mv-is v) (%py-mv-bytes v))
        ((%py-bytes-is v) (%py-bytes-list v))
        ((%py-arr-is v) (%py-arr-buffer v))
        (#t ())))))
(def %py-buffer-text
  (fn (_ v) (%py-bytes-str (%py-bytes-new (%py-buffer-bytes v)))))

; The elements a value offers a view: what a slice assignment stores, and what
; an equality compares against.
(def %py-mv-in
  (fn (_ new)
    (match
      ((%py-mv-is new) (%py-mv-elems new))
      ((%py-bytes-is new) (%py-bytes-list new))
      ((%py-arr-is new) (%py-arr-el new))
      (#t (%py-iter-elems new)))))

; The typecode a source's elements carry: a view has one, a bytes and a
; bytearray are bytes under B, and an array's is its own.
(def %py-mv-code-of
  (fn (_ v)
    (match
      ((%py-mv-is v) (%py-mv-code v))
      ((%py-bytes-is v) "B")
      ((%py-arr-is v) (%py-arr-tc v))
      (#t ()))))

; A slice takes exactly as many elements as it holds, of exactly its own width:
; a view cannot grow the storage it is a view of, and Python calls a source of
; another format a different structure even when the count matches.  The source
; is read before the store, so an overlapping shift copies rather than smears.
(def %py-mv-setslice!
  (fn (_ v start stop step new)
    (if (%py-mv-readonly? v)
      (%py-mv-readonly!)
      (let ((sp (%py-slice-span (%py-mv-len v) start stop step)) (t (%py-mv-target v)))
        (let ((lo (+ (%py-mv-start v) (first sp))) (hi (+ (%py-mv-start v) (rest sp)))
              (code (%py-mv-code-of new)))
          (if (null? code)
            (Err raise (lit type)
              (Str8 append "a bytes-like object is required, not '"
                (Str8 append (%py-class-name (%py-type-of new)) "'")) ())
            (let ((src (%py-mv-in new)))
              (if (if (Str8 =? code (%py-mv-code v)) (= (%py-length src) (- hi lo)) #f)
                (%py-mv-store! t
                  (%py-list-cat (%py-take lo (%py-mv-all t))
                    (%py-list-cat (%py-mv-items t src ())
                      (%py-drop (%py-mv-all t) hi))))
                (Err raise (lit value)
                  "memoryview assignment: lvalue and rvalue have different structures" ())))))))))
(def %py-mv-items
  (fn (self t src acc)
    (if (null? src)
      (%py-reverse acc)
      (self t (rest src) (pair (%py-mv-item t (first src)) acc)))))

; memoryview(v) over bytes, a bytearray, an array, or another view.
(def %py-memoryview-ctor
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type) "memoryview() missing required argument 'object'" ())
      (let ((v (%py-native-of (first a))))
        (match
          ((%py-mv-is v)
            (%py-mv-new (%py-mv-target v) (%py-mv-start v) (%py-mv-stop v) (%py-mv-code v)))
          ((%py-bytes-is v) (%py-mv-new v 0 (%pb-len (%py-bytes-list v)) "B"))
          ((%py-arr-is v) (%py-mv-new v 0 (%py-length (%py-arr-el v)) (%py-arr-tc v)))
          (#t
            (Err raise (lit type)
              (Str8 append "memoryview: a bytes-like object is required, not '"
                (Str8 append (%py-class-name (%py-type-of (first a))) "'")) ())))))))

; itemsize is the width its typecode names; a store to it is Python's
; AttributeError, since a view's shape is not a program's to set.
(def %py-mv-itemsize
  (fn (_ v)
    (if (Str8 =? (%py-mv-code v) "B") 1 (%py-arr-size (%py-arr-info (%py-mv-code v))))))

(def %py-mv-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "itemsize") (%py-mv-itemsize v))
      ((Str8 =? name "nbytes") (* (%py-mv-len v) (%py-mv-itemsize v)))
      ((Str8 =? name "readonly") (%py-mv-readonly? v))
      ((Str8 =? name "format") (%py-str-of-x (%py-mv-code v)))
      (#t (%py-class-row-attr %py-cls-memoryview v name "memoryview")))))

(set! %py-mv
  (%make-type
    "PY-MEMORYVIEW"
    (list
      (pair (lit write) (fn (_ self) (display "<memory>")))
      (pair (lit length) (fn (_ self) (%py-mv-len self))))))

(def %py-mv-methods
  (list
    (pair "%ctor" %py-memoryview-ctor)
    (pair "__len__" (fn (_ o) (%py-mv-len (%py-native-of o))))
    (pair "__getitem__" (fn (_ o i) (%py-mv-at (%py-native-of o) i)))
    (pair "__setitem__" (fn (_ o i x) (%py-mv-put! (%py-native-of o) i x)))
    (pair "__iter__" (fn (_ o) (%py-list-new (%py-mv-elems (%py-native-of o)))))
    ; the bytes it covers, as bytes.hex writes them
    (pair "hex" (fn (_ o . a) (%py-bytes-hex (%py-mv-bytes (%py-native-of o)) a)))
    (pair "__contains__"
      (fn (_ o x) (%py-in x (%py-list-new (%py-mv-elems (%py-native-of o))))))
    (pair "__eq__"
      (fn (_ o other)
        (%py-eq (%py-list-new (%py-mv-elems (%py-native-of o)))
          (%py-list-new (%py-mv-in (%py-native-of other))))))
    (pair "itemsize"
      (%py-desc-new (lit property) (fn (_ o) (%py-mv-itemsize (%py-native-of o)))))
    (pair "nbytes"
      (%py-desc-new (lit property)
        (fn (_ o)
          (let ((v (%py-native-of o))) (* (%py-mv-len v) (%py-mv-itemsize v))))))
    (pair "readonly"
      (%py-desc-new (lit property) (fn (_ o) (%py-mv-readonly? (%py-native-of o)))))
    (pair "format"
      (%py-desc-new (lit property)
        (fn (_ o) (%py-str-of-x (%py-mv-code (%py-native-of o))))))))

(def %py-cls-memoryview
  (%py-class-new "memoryview" %py-cls-object %py-mv-methods "memoryview"))

(provide python/memoryview
  %py-buffer-bytes %py-buffer-text %py-buffer? %py-cls-memoryview
  %py-mv-at %py-mv-attr %py-mv-elems %py-mv-in %py-mv-is %py-mv-len
  %py-mv-put! %py-mv-setslice! %py-mv-slice)
