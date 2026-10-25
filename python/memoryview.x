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
(import python/core
  make-instance make-type pb-len python-barr-set! python-boolnorm python-bytes-hex
  python-bytes-is python-bytes-list python-bytes-new python-bytes-of-codes python-bytes-only?
  python-bytes-str python-class-name python-class-new python-class-row-attr python-cls-object
  python-desc-new python-drop python-eq python-in python-iter-elems python-length python-list-cat
  python-list-new python-native-of python-reverse python-set-nth python-slice-span python-str-of-x
  python-take python-type-of type?)
(import python/array
  python-arr-buffer python-arr-el python-arr-info python-arr-is python-arr-item python-arr-set!
  python-arr-size python-arr-tc python-take-n)

(def %py-mv ())
(def %py-mv-new
  (fn (_ t start stop code) (make-instance %py-mv (list t start stop code))))
(def python-mv-is (fn (_ v) (type? v %py-mv)))
(def %py-mv-target (fn (_ v) (first (first v))))
(def %py-mv-start (fn (_ v) (first (rest (first v)))))
(def %py-mv-stop (fn (_ v) (first (rest (rest (first v))))))
(def %py-mv-code (fn (_ v) (first (rest (rest (rest (first v)))))))

; The target's elements, and the store that puts them back.
(def %py-mv-all
  (fn (_ t) (if (python-arr-is t) (python-arr-el t) (python-bytes-list t))))
(def %py-mv-store!
  (fn (_ t l) (if (python-arr-is t) (python-arr-set! t l) (python-barr-set! t l))))
(def %py-mv-readonly? (fn (_ v) (python-bytes-only? (%py-mv-target v))))
(def python-mv-len (fn (_ v) (- (%py-mv-stop v) (%py-mv-start v))))
(def python-mv-elems
  (fn (_ v)
    (python-take-n (python-drop (%py-mv-all (%py-mv-target v)) (%py-mv-start v))
      (python-mv-len v) ())))

(def %py-mv-readonly!
  (fn (_) (Err raise (lit type) "cannot modify read-only memory" ())))

; One element, as the target would check it: an array's typecode does the
; range, and a byte is the 0-255 bytes() takes.
(def %py-mv-item
  (fn (_ t x)
    (if (python-arr-is t)
      (python-arr-item (python-arr-info (python-arr-tc t)) x)
      (first (python-bytes-of-codes (list x) ())))))

(def %py-mv-slot
  (fn (_ v i)
    (let ((n (python-mv-len v)))
      (let ((k (if (< (python-boolnorm i) 0) (+ n (python-boolnorm i)) (python-boolnorm i))))
        (if (if (< k 0) #t (>= k n))
          (Err raise (lit index) "index out of bounds on dimension 1" ())
          (+ (%py-mv-start v) k))))))

(def python-mv-at
  (fn (_ v i) (List ref (%py-mv-slot v i) (%py-mv-all (%py-mv-target v)))))

(def python-mv-put!
  (fn (_ v i x)
    (if (%py-mv-readonly? v)
      (%py-mv-readonly!)
      (let ((t (%py-mv-target v)))
        (%py-mv-store! t
          (python-set-nth (%py-mv-all t) (%py-mv-slot v i) (%py-mv-item t x)))))))

; A view of a view shares the target, so a store still reaches it.
(def python-mv-slice
  (fn (_ v start stop step)
    (let ((sp (python-slice-span (python-mv-len v) start stop step)))
      (%py-mv-new (%py-mv-target v) (+ (%py-mv-start v) (first sp))
        (+ (%py-mv-start v) (rest sp)) (%py-mv-code v)))))

; A buffer: bytes, a bytearray, an array, or a view of one.  An array reaches a
; program wrapped in its instance, so the question is asked of what a value
; carries -- here rather than at each of the places that ask it.
(def python-buffer?
  (fn (_ v0)
    (let ((v (python-native-of v0)))
      (match ((python-mv-is v) #t) ((python-bytes-is v) #t) (#t (python-arr-is v))))))

; The BYTES a buffer offers, which is not always its elements: a view of an
; array covers its span of the array's own byte layout.  str(), int(), bytes()
; and eval() read a buffer through here, so each of them takes every one.
(def %py-mv-bytes
  (fn (_ v)
    (let ((t (%py-mv-target v)))
      (if (python-arr-is t)
        (let ((w (%py-mv-itemsize v)))
          (python-take-n (python-drop (python-arr-buffer t) (* (%py-mv-start v) w))
            (* (python-mv-len v) w) ()))
        (python-mv-elems v)))))
(def python-buffer-bytes
  (fn (_ v0)
    (let ((v (python-native-of v0)))
      (match
        ((python-mv-is v) (%py-mv-bytes v))
        ((python-bytes-is v) (python-bytes-list v))
        ((python-arr-is v) (python-arr-buffer v))
        (#t ())))))
(def python-buffer-text
  (fn (_ v) (python-bytes-str (python-bytes-new (python-buffer-bytes v)))))

; The elements a value offers a view: what a slice assignment stores, and what
; an equality compares against.
(def python-mv-in
  (fn (_ new)
    (match
      ((python-mv-is new) (python-mv-elems new))
      ((python-bytes-is new) (python-bytes-list new))
      ((python-arr-is new) (python-arr-el new))
      (#t (python-iter-elems new)))))

; The typecode a source's elements carry: a view has one, a bytes and a
; bytearray are bytes under B, and an array's is its own.
(def %py-mv-code-of
  (fn (_ v)
    (match
      ((python-mv-is v) (%py-mv-code v))
      ((python-bytes-is v) "B")
      ((python-arr-is v) (python-arr-tc v))
      (#t ()))))

; A slice takes exactly as many elements as it holds, of exactly its own width:
; a view cannot grow the storage it is a view of, and Python calls a source of
; another format a different structure even when the count matches.  The source
; is read before the store, so an overlapping shift copies rather than smears.
(def python-mv-setslice!
  (fn (_ v start stop step new)
    (if (%py-mv-readonly? v)
      (%py-mv-readonly!)
      (let ((sp (python-slice-span (python-mv-len v) start stop step)) (t (%py-mv-target v)))
        (let ((lo (+ (%py-mv-start v) (first sp))) (hi (+ (%py-mv-start v) (rest sp)))
              (code (%py-mv-code-of new)))
          (if (null? code)
            (Err raise (lit type)
              (Str8 append "a bytes-like object is required, not '"
                (Str8 append (python-class-name (python-type-of new)) "'")) ())
            (let ((src (python-mv-in new)))
              (if (if (Str8 =? code (%py-mv-code v)) (= (python-length src) (- hi lo)) #f)
                (%py-mv-store! t
                  (python-list-cat (python-take lo (%py-mv-all t))
                    (python-list-cat (%py-mv-items t src ())
                      (python-drop (%py-mv-all t) hi))))
                (Err raise (lit value)
                  "memoryview assignment: lvalue and rvalue have different structures" ())))))))))
(def %py-mv-items
  (fn (self t src acc)
    (if (null? src)
      (python-reverse acc)
      (self t (rest src) (pair (%py-mv-item t (first src)) acc)))))

; memoryview(v) over bytes, a bytearray, an array, or another view.
(def %py-memoryview-ctor
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type) "memoryview() missing required argument 'object'" ())
      (let ((v (python-native-of (first a))))
        (match
          ((python-mv-is v)
            (%py-mv-new (%py-mv-target v) (%py-mv-start v) (%py-mv-stop v) (%py-mv-code v)))
          ((python-bytes-is v) (%py-mv-new v 0 (pb-len (python-bytes-list v)) "B"))
          ((python-arr-is v) (%py-mv-new v 0 (python-length (python-arr-el v)) (python-arr-tc v)))
          (#t
            (Err raise (lit type)
              (Str8 append "memoryview: a bytes-like object is required, not '"
                (Str8 append (python-class-name (python-type-of (first a))) "'")) ())))))))

; itemsize is the width its typecode names; a store to it is Python's
; AttributeError, since a view's shape is not a program's to set.
(def %py-mv-itemsize
  (fn (_ v)
    (if (Str8 =? (%py-mv-code v) "B") 1 (python-arr-size (python-arr-info (%py-mv-code v))))))

(def python-mv-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "itemsize") (%py-mv-itemsize v))
      ((Str8 =? name "nbytes") (* (python-mv-len v) (%py-mv-itemsize v)))
      ((Str8 =? name "readonly") (%py-mv-readonly? v))
      ((Str8 =? name "format") (python-str-of-x (%py-mv-code v)))
      (#t (python-class-row-attr python-cls-memoryview v name "memoryview")))))

(set! %py-mv
  (make-type
    "PY-MEMORYVIEW"
    (list
      (pair (lit write) (fn (_ self) (display "<memory>")))
      (pair (lit length) (fn (_ self) (python-mv-len self))))))

(def %py-mv-methods
  (list
    (pair "%ctor" %py-memoryview-ctor)
    (pair "__len__" (fn (_ o) (python-mv-len (python-native-of o))))
    (pair "__getitem__" (fn (_ o i) (python-mv-at (python-native-of o) i)))
    (pair "__setitem__" (fn (_ o i x) (python-mv-put! (python-native-of o) i x)))
    (pair "__iter__" (fn (_ o) (python-list-new (python-mv-elems (python-native-of o)))))
    ; the bytes it covers, as bytes.hex writes them
    (pair "hex" (fn (_ o . a) (python-bytes-hex (%py-mv-bytes (python-native-of o)) a)))
    (pair "__contains__"
      (fn (_ o x) (python-in x (python-list-new (python-mv-elems (python-native-of o))))))
    (pair "__eq__"
      (fn (_ o other)
        (python-eq (python-list-new (python-mv-elems (python-native-of o)))
          (python-list-new (python-mv-in (python-native-of other))))))
    (pair "itemsize"
      (python-desc-new (lit property) (fn (_ o) (%py-mv-itemsize (python-native-of o)))))
    (pair "nbytes"
      (python-desc-new (lit property)
        (fn (_ o)
          (let ((v (python-native-of o))) (* (python-mv-len v) (%py-mv-itemsize v))))))
    (pair "readonly"
      (python-desc-new (lit property) (fn (_ o) (%py-mv-readonly? (python-native-of o)))))
    (pair "format"
      (python-desc-new (lit property)
        (fn (_ o) (python-str-of-x (%py-mv-code (python-native-of o))))))))

(def python-cls-memoryview
  (python-class-new "memoryview" python-cls-object %py-mv-methods "memoryview"))

(provide python/memoryview
  python-buffer-bytes python-buffer-text python-buffer? python-cls-memoryview
  python-mv-at python-mv-attr python-mv-elems python-mv-in python-mv-is python-mv-len
  python-mv-put! python-mv-setslice! python-mv-slice)
