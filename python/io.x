; # x-python -- Python on x-lang
;
; ## python/io.x -- the io module
;
; @description StringIO and BytesIO, two names for one stream: a list of
;   elements, a position in it, and a closed flag.  The elements are code
;   points for the text one and bytes for the binary one, which is the only
;   difference between them -- what read and getvalue hand back, and what
;   write takes apart.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A stream constructed from a buffer COPIES it: writing into the stream must
; not reach the bytes it was built from, which is what io_bytesio_cow asks.

(def %py-io ())
(def %py-io-new
  (fn (_ text? buf) (%make-instance %py-io (list text? (list buf) (list 0) (list #f)))))
(def %py-io-is (fn (_ v) (%type? v %py-io)))
(def %py-io-text? (fn (_ v) (first (first v))))
(def %py-io-buf (fn (_ v) (first (List ref 1 (first v)))))
(def %py-io-buf! (fn (_ v b) (%seq (%set-first! (List ref 1 (first v)) b) ())))
(def %py-io-pos (fn (_ v) (first (List ref 2 (first v)))))
(def %py-io-pos! (fn (_ v p) (%seq (%set-first! (List ref 2 (first v)) p) ())))
(def %py-io-closed? (fn (_ v) (first (List ref 3 (first v)))))

(def %py-io-name (fn (_ v) (if (%py-io-text? v) "io.StringIO" "io.BytesIO")))

(def %py-io-shut!
  (fn (_ v)
    (if (%py-io-closed? v)
      (Err raise (lit value) "I/O operation on closed file" ())
      ())))

; A stream prints as its class and nothing about its contents, which is the
; shape every object here prints in.
(set! %py-io
  (%make-type
    "PY-IO"
    (list
      (pair (lit write)
        (fn (_ self) (display (Str8 append "<" (Str8 append (%py-io-name self) " object>"))))))))

; --- the elements ---------------------------------------------------------------
; One list either way: code points for a text stream, bytes for a binary one.

(def %py-io-elems-of
  (fn (_ v x)
    (if (%py-io-text? v)
      (if (%py-str-is x) (%py-str-cps x) (Err raise (lit type) "a str is required" ()))
      (if (%py-bytes-is x) (%py-bytes-list x) (Err raise (lit type) "a bytes-like object is required" ())))))

(def %py-io-value-of
  (fn (_ v el) (if (%py-io-text? v) (%py-str-new el) (%py-bytes-new el))))

(def %py-io-zeros
  (fn (self k acc) (if (<= k 0) acc (self (- k 1) (pair 0 acc)))))

; The buffer with `new` laid over it at `at`, the gap NUL-filled when the
; position is past the end -- which is what seeking beyond it and writing
; leaves behind.
(def %py-io-lay
  (fn (self buf at new)
    (match
      ((null? new) buf)
      ((= at 0) (pair (first new) (self (if (null? buf) () (rest buf)) 0 (rest new))))
      ((null? buf) (pair 0 (self () (- at 1) new)))
      (#t (pair (first buf) (self (rest buf) (- at 1) new))))))

(def %py-io-take
  (fn (self l k acc)
    (if (= k 0) (%py-reverse acc)
      (if (null? l) (%py-reverse acc) (self (rest l) (- k 1) (pair (first l) acc))))))

; --- the operations ---------------------------------------------------------------

(def %py-io-write!
  (fn (_ v x)
    (%seq (%py-io-shut! v)
      (let ((new (%py-io-elems-of v x)))
        (%seq
          (%py-io-buf! v (%py-io-lay (%py-io-buf v) (%py-io-pos v) new))
          (%seq (%py-io-pos! v (+ (%py-io-pos v) (%py-length new)))
            (%py-length new)))))))

(def %py-io-read
  (fn (_ v . more)
    (%seq (%py-io-shut! v)
      (let ((rest- (%py-drop (%py-io-buf v) (%py-io-pos v))))
        (let ((n (if (null? more) (%py-length rest-)
                   (if (null? (first more)) (%py-length rest-) (%py-boolnorm (first more))))))
          (let ((got (%py-io-take rest- (if (< n 0) (%py-length rest-) n) ())))
            (%seq (%py-io-pos! v (+ (%py-io-pos v) (%py-length got)))
              (%py-io-value-of v got))))))))

(def %py-io-getvalue
  (fn (_ v) (%seq (%py-io-shut! v) (%py-io-value-of v (%py-io-buf v)))))

; seek(n), seek(n, 0|1|2): from the start, from here, from the end.  A
; position past the end is allowed; it is the write that fills the gap.
(def %py-io-seek!
  (fn (_ v n . more)
    (%seq (%py-io-shut! v)
      (let ((whence (if (null? more) 0 (%py-boolnorm (first more)))))
        (let ((base (match
                      ((= whence 1) (%py-io-pos v))
                      ((= whence 2) (%py-length (%py-io-buf v)))
                      (#t 0))))
          (let ((p (+ base (%py-boolnorm n))))
            (if (< p 0)
              (Err raise (lit value) "negative seek value" ())
              (%seq (%py-io-pos! v p) p))))))))

(def %py-io-readinto!
  (fn (_ v arr)
    (%seq (%py-io-shut! v)
      (if (not (%py-barr-is arr))
        (Err raise (lit type) "readinto() wants a bytearray" ())
        (let ((room (%py-length (%py-bytes-list arr))))
          (let ((got (%py-io-take (%py-drop (%py-io-buf v) (%py-io-pos v)) room ())))
            (%seq (%py-barr-set! arr (%py-io-lay (%py-bytes-list arr) 0 got))
              (%seq (%py-io-pos! v (+ (%py-io-pos v) (%py-length got)))
                (%py-length got)))))))))

; Iterating a stream answers its remaining LINES, each keeping its newline.
(def %py-io-lines
  (fn (self v el acc cur)
    (if (null? el)
      (%py-reverse (if (null? cur) acc (pair (%py-io-value-of v (%py-reverse cur)) acc)))
      (if (= (first el) 10)
        (self v (rest el) (pair (%py-io-value-of v (%py-reverse (pair 10 cur))) acc) ())
        (self v (rest el) acc (pair (first el) cur))))))

(def %py-io-elems
  (fn (_ v) (%py-io-lines v (%py-drop (%py-io-buf v) (%py-io-pos v)) () ())))

; Iteration READS: the lines come out in one go, as everything iterable here
; is materialized, so the position lands where the last of them ended.
(def %py-io-drain!
  (fn (_ v)
    (let ((ls (%py-io-elems v)))
      (%seq (%py-io-pos! v (%py-length (%py-io-buf v))) ls))))

(def %py-io-iter! (fn (_ v) (%py-list-new (%py-io-drain! v))))

; --- the surfaces -----------------------------------------------------------------

(def %py-io-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "write") (fn (_ x) (%py-io-write! v x)))
      ((Str8 =? name "read") (fn (_ . a) (apply %py-io-read (pair v a))))
      ((Str8 =? name "getvalue") (fn (_) (%py-io-getvalue v)))
      ((Str8 =? name "tell") (fn (_) (%py-io-pos v)))
      ((Str8 =? name "seek") (fn (_ n . a) (apply %py-io-seek! (pair v (pair n a)))))
      ((Str8 =? name "readinto") (fn (_ arr) (%py-io-readinto! v arr)))
      ((Str8 =? name "readline") (fn (_) (%py-io-readline v)))
      ((Str8 =? name "flush") (fn (_) ()))
      ((Str8 =? name "close") (fn (_) (%seq (%set-first! (List ref 3 (first v)) #t) ())))
      ((Str8 =? name "__enter__") (fn (_) v))
      ((Str8 =? name "__exit__") (fn (_ . a) (%seq (%set-first! (List ref 3 (first v)) #t) ())))
      ((Str8 =? name "__iter__") (fn (_) (%py-io-iter! v)))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'" (%py-io-name v))
            (Str8 append "' object has no attribute '" (Str8 append name "'"))) ())))))

(def %py-io-readline
  (fn (_ v)
    (let ((ls (%py-io-elems v)))
      (if (null? ls)
        (%py-io-value-of v ())
        (let ((one (first ls)))
          (%seq (%py-io-pos! v (+ (%py-io-pos v) (%py-length (%py-io-elems-of v one)))) one))))))

(def %py-io-methods
  (fn (_ text?)
    (list
      (pair "%ctor"
        (fn (_ . a)
          (%py-io-new text?
            (if (null? a) ()
              (if (null? (first a)) ()
                (%py-io-elems-of (%py-io-new text? ()) (first a)))))))
      (pair "write" (%py-sig! (fn (_ o x) (%py-io-write! (%py-native-of o) x))
                      "write" (list "self" "s") 2 #f () () #t))
      (pair "read" (%py-sig! (fn (_ o . a) (apply %py-io-read (pair (%py-native-of o) a)))
                     "read" (list "self") 1 #t () () #t))
      (pair "getvalue" (%py-sig! (fn (_ o) (%py-io-getvalue (%py-native-of o)))
                         "getvalue" (list "self") 1 #f () () #t))
      (pair "tell" (%py-sig! (fn (_ o) (%py-io-pos (%py-native-of o)))
                     "tell" (list "self") 1 #f () () #t))
      (pair "seek" (%py-sig! (fn (_ o n . a) (apply %py-io-seek! (pair (%py-native-of o) (pair n a))))
                     "seek" (list "self" "pos") 2 #t () () #t))
      (pair "readinto" (%py-sig! (fn (_ o arr) (%py-io-readinto! (%py-native-of o) arr))
                         "readinto" (list "self" "buf") 2 #f () () #t))
      (pair "readline" (%py-sig! (fn (_ o) (%py-io-readline (%py-native-of o)))
                         "readline" (list "self") 1 #f () () #t))
      (pair "flush" (%py-sig! (fn (_ o) ()) "flush" (list "self") 1 #f () () #t))
      (pair "close"
        (%py-sig! (fn (_ o) (%seq (%set-first! (List ref 3 (first (%py-native-of o))) #t) ()))
          "close" (list "self") 1 #f () () #t))
      (pair "__enter__" (fn (_ o) o))
      (pair "__exit__"
        (fn (_ o . a) (%seq (%set-first! (List ref 3 (first (%py-native-of o))) #t) ())))
      (pair "__iter__" (fn (_ o) (%py-io-iter! (%py-native-of o))))
      (pair "__repr__" (fn (_ o) (Str8 append "<" (Str8 append (%py-io-name (%py-native-of o)) " object>"))))
      (pair "__str__" (fn (_ o) (Str8 append "<" (Str8 append (%py-io-name (%py-native-of o)) " object>")))))))

; IOBase carries no behaviour of its own: it is the base a program writes its
; own stream against, and `print(..., file=x)` asks that object for write.
(def %py-cls-IOBase (%py-class-new "IOBase" %py-cls-object () "io.IOBase"))
(def %py-cls-StringIO
  (%py-class-new "StringIO" %py-cls-IOBase (%py-io-methods #t) "io.StringIO"))
(def %py-cls-BytesIO
  (%py-class-new "BytesIO" %py-cls-IOBase (%py-io-methods #f) "io.BytesIO"))

(def %py-io-module
  (fn (_)
    (%py-module-new "io"
      (list
        (pair "StringIO" %py-cls-StringIO)
        (pair "BytesIO" %py-cls-BytesIO)
        (pair "IOBase" %py-cls-IOBase)))))
