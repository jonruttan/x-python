; # x-python -- Python on x-lang
;
; ## python/struct.x -- the struct module
;
; @description pack, unpack and calcsize over a format string, on the same
;   integer encoder int.to_bytes and array use.  Integer codes, the float codes
;   and the two that take no value: b B h H i I l L q Q, e f d, s and x.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; TWO SIZINGS, AND THE PREFIX PICKS ONE.  With a byte-order prefix the sizes
; are the standard ones and nothing is padded; with @ or no prefix they are
; the machine's and every field is aligned to its own width.  The only code
; that differs between them is l and L, four bytes standard and eight native,
; which is what makes `calcsize("<l")` 4 and `calcsize("@l")` 8.
;
; The float codes e, f and d write a float's IEEE bits, through the encoder in
; python/array.x, at the same width in both sizings.

(module python/struct)
(import python/array %py-ieee-bits %py-ieee-double %py-ieee-half %py-ieee-one
  %py-ieee-sign %py-ieee-single %py-ieee-top %py-ieee-value %py-take-n)

; (typecode standard-size native-size signed?), where a float code's last field
; is its IEEE format rather than a sign
(def %py-st-codes
  (list
    (list "b" 1 1 #t) (list "B" 1 1 #f)
    (list "h" 2 2 #t) (list "H" 2 2 #f)
    (list "i" 4 4 #t) (list "I" 4 4 #f)
    (list "l" 4 8 #t) (list "L" 4 8 #f)
    (list "q" 8 8 #t) (list "Q" 8 8 #f)
    (list "e" 2 2 %py-ieee-half) (list "f" 4 4 %py-ieee-single)
    (list "d" 8 8 %py-ieee-double)))

(def %py-st-find
  (fn (self tc rows)
    (if (null? rows) ()
      (if (Str8 =? tc (first (first rows))) (first rows) (self tc (rest rows))))))

(def %py-st-code (fn (_ tc) (%py-st-find tc %py-st-codes)))
(def %py-st-width (fn (_ e align) (if align (List ref 2 e) (List ref 1 e))))
(def %py-st-signed? (fn (_ e) (List ref 3 e)))

(def %py-st-bad!
  (fn (_ msg) (Err raise (lit value) msg ())))

; --- the format ---------------------------------------------------------------

(def %py-st-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))
(def %py-st-at (fn (_ s i) (%py-char-code (%str-ref s i))))

; (order align? first-index) -- the byte order a code is written in, whether
; fields are padded to their width, and where the codes start.
(def %py-st-mode
  (fn (_ s n)
    (if (= n 0)
      (list "little" #t 0)
      (match
        ((= (%py-st-at s 0) 60) (list "little" #f 1))
        ((= (%py-st-at s 0) 62) (list "big" #f 1))
        ((= (%py-st-at s 0) 33) (list "big" #f 1))
        ((= (%py-st-at s 0) 61) (list "little" #f 1))
        ((= (%py-st-at s 0) 64) (list "little" #t 1))
        (#t (list "little" #t 0))))))

(def %py-st-count
  (fn (self s n i acc)
    (if (>= i n)
      (pair acc i)
      (let ((c (%py-st-at s i)))
        (if (%py-st-digit? c) (self s n (+ i 1) (+ (* acc 10) (- c 48))) (pair acc i))))))

; The codes as (count . typecode) pairs.  A count with no code after it is
; the error Python raises rather than a silent nothing.
(def %py-st-items
  (fn (self s n i acc)
    (if (>= i n)
      (%py-reverse acc)
      (if (%py-st-digit? (%py-st-at s i))
        (let ((r (%py-st-count s n i 0)))
          (if (>= (rest r) n)
            (%py-st-bad! "repeat count given without format specifier")
            (self s n (+ (rest r) 1) (pair (pair (first r) (Str8 sub (rest r) 1 s)) acc))))
        (self s n (+ i 1) (pair (pair 1 (Str8 sub i 1 s)) acc))))))

; The format is a str, and anything else is Python's TypeError rather than
; whatever reading a non-string as one would do.
(def %py-st-fmt
  (fn (_ fmt)
    (match
      ((%py-str-is fmt) (%ps->x (%py-str-cps fmt)))
      ((str? fmt) fmt)
      (#t (Err raise (lit type) "struct format must be a str" ())))))

(def %py-st-read
  (fn (_ fmt)
    (let ((s (%py-st-fmt fmt)))
      (let ((n (%py-byte-len s)))
        (let ((m (%py-st-mode s n)))
          (list (first m) (List ref 1 m) (%py-st-items s n (List ref 2 m) ())))))))

; Native fields sit at a multiple of their own width.
(def %py-st-pad
  (fn (_ off w) (let ((r (Num modulo off w))) (if (= r 0) 0 (- w r)))))

; --- the size -----------------------------------------------------------------

(def %py-st-size
  (fn (self items align off)
    (if (null? items)
      off
      (let ((cnt (first (first items))) (tc (rest (first items))))
        (match
          ((Str8 =? tc "s") (self (rest items) align (+ off cnt)))
          ((Str8 =? tc "x") (self (rest items) align (+ off cnt)))
          (#t
            (let ((e (%py-st-code tc)))
              (if (null? e)
                (%py-st-bad! "bad char in struct format")
                (let ((w (%py-st-width e align)))
                  (self (rest items) align
                    (+ (if align (+ off (%py-st-pad off w)) off) (* cnt w))))))))))))

(def %py-st-calcsize
  (fn (_ fmt)
    (let ((f (%py-st-read fmt))) (%py-st-size (List ref 2 f) (List ref 1 f) 0))))

; --- pack ----------------------------------------------------------------------

(def %py-st-zeros
  (fn (self k acc) (if (= k 0) acc (self (- k 1) (pair 0 acc)))))

; Exactly k bytes of a bytes-like value: cut long, NUL-filled short.
(def %py-st-sbytes
  (fn (_ v k)
    (let ((bs (if (%py-bytes-is v) (%py-bytes-list v) (%py-st-bad! "argument for 's' must be bytes"))))
      (let ((have (%py-length bs)))
        (if (>= have k)
          (%py-take-n bs k ())
          (%py-list-cat bs (%py-st-zeros (- k have) ())))))))

; A float code's value is a real number, and a finite one too large for e or f
; is Python's OverflowError rather than the infinity's bits.
(def %py-st-float-bits
  (fn (_ v f tc)
    (let ((x (if (if (%py-num? v) #t (if (%py-obj-is v) (not (null? (%py-dunder v "__float__"))) #f))
               (%py-mfloat v)
               (%py-st-bad! "required argument is not a float"))))
      (let ((n (%py-ieee-bits x f)) (inf (* (%py-ieee-top f) (%py-ieee-one f))))
        (if (if (Float finite? x) (= (if (< n (%py-ieee-sign f)) n (- n (%py-ieee-sign f))) inf) #f)
          (Err raise (lit overflow)
            (Str8 append "float too large to pack with " (Str8 append tc " format")) ())
          n)))))

; e is (typecode width signed?), a float code's signed? being its IEEE format.
(def %py-st-ints
  (fn (self e cnt order vals acc)
    (if (= cnt 0)
      (pair vals acc)
      (if (null? vals)
        (%py-st-bad! "not enough arguments for the format")
        (self e (- cnt 1) order (rest vals)
          (%py-list-cat acc
            (let ((kind (first (rest (rest e)))))
              (if (pair? kind)
                (%py-int-encode (%py-st-float-bits (first vals) kind (first e))
                  (List ref 1 e) order #f)
                (%py-int-encode (%py-boolnorm (first vals)) (List ref 1 e) order kind)))))))))

; (bytes . unused-values)
(def %py-st-emit
  (fn (self items align order vals acc)
    (if (null? items)
      (pair acc vals)
      (let ((cnt (first (first items))) (tc (rest (first items))))
        (match
          ((Str8 =? tc "x")
            (self (rest items) align order vals (%py-list-cat acc (%py-st-zeros cnt ()))))
          ((Str8 =? tc "s")
            (if (null? vals)
              (%py-st-bad! "not enough arguments for the format")
              (self (rest items) align order (rest vals)
                (%py-list-cat acc (%py-st-sbytes (first vals) cnt)))))
          (#t
            (let ((e0 (%py-st-code tc)))
              (if (null? e0)
                (%py-st-bad! "bad char in struct format")
                (let ((w (%py-st-width e0 align)))
                  (let ((padded
                          (if align
                            (%py-list-cat acc (%py-st-zeros (%py-st-pad (%py-length acc) w) ()))
                            acc)))
                    (let ((r (%py-st-ints (list tc w (%py-st-signed? e0)) cnt order vals padded)))
                      (self (rest items) align order (first r) (rest r)))))))))))))

(def %py-st-pack
  (fn (_ fmt . vals)
    (let ((f (%py-st-read fmt)))
      (%py-bytes-new
        (first (%py-st-emit (List ref 2 f) (List ref 1 f) (first f) vals ()))))))

; --- unpack --------------------------------------------------------------------

(def %py-st-decode
  (fn (_ bs w signed order)
    (let ((big (if (Str8 =? order "little") (List reverse bs) bs)))
      (match
        ((pair? signed) (%py-ieee-value (%py-int-join big) signed))
        ((if signed (>= (first big) 128) #f)
          (- (- 0 (%py-int-join (%py-int-invert big ()))) 1))
        (#t (%py-int-join big))))))

(def %py-st-take
  (fn (self e cnt order bs acc)
    (if (= cnt 0)
      (pair bs acc)
      (let ((w (List ref 1 e)))
        (if (< (%py-length bs) w)
          (%py-st-bad! "buffer too small for the format")
          (self e (- cnt 1) order (%py-drop bs w)
            (pair (%py-st-decode (%py-take-n bs w ()) w (List ref 2 e) order) acc)))))))

(def %py-st-read-items
  (fn (self items align order bs off acc)
    (if (null? items)
      (%py-reverse acc)
      (let ((cnt (first (first items))) (tc (rest (first items))))
        (match
          ((Str8 =? tc "x")
            (if (< (%py-length bs) cnt)
              (%py-st-bad! "buffer too small for the format")
              (self (rest items) align order (%py-drop bs cnt) (+ off cnt) acc)))
          ((Str8 =? tc "s")
            (if (< (%py-length bs) cnt)
              (%py-st-bad! "buffer too small for the format")
              (self (rest items) align order (%py-drop bs cnt) (+ off cnt)
                (pair (%py-bytes-new (%py-take-n bs cnt ())) acc))))
          (#t
            (let ((e0 (%py-st-code tc)))
              (if (null? e0)
                (%py-st-bad! "bad char in struct format")
                (let ((w (%py-st-width e0 align)))
                  (let ((skip (if align (%py-st-pad off w) 0)))
                    (if (< (%py-length bs) skip)
                      (%py-st-bad! "buffer too small for the format")
                      (let ((r (%py-st-take (list tc w (%py-st-signed? e0)) cnt order
                                 (%py-drop bs skip) acc)))
                        (self (rest items) align order (first r)
                          (+ (+ off skip) (* cnt w)) (rest r))))))))))))))

(def %py-st-bytes-of
  (fn (_ v)
    (if (%py-bytes-is v) (%py-bytes-list v) (%py-st-bad! "a buffer is required"))))

(def %py-st-unpack
  (fn (_ fmt buf)
    (let ((f (%py-st-read fmt)) (bs (%py-st-bytes-of buf)))
      (let ((want (%py-st-size (List ref 2 f) (List ref 1 f) 0)))
        (if (not (= (%py-length bs) want))
          (%py-st-bad! "buffer size does not match the format")
          (%py-tuple-of-list
            (%py-st-read-items (List ref 2 f) (List ref 1 f) (first f) bs 0 ())))))))

; A negative offset counts from the end, as Python's does.
(def %py-st-offset
  (fn (_ off n)
    (let ((k (if (< (%py-boolnorm off) 0) (+ n (%py-boolnorm off)) (%py-boolnorm off))))
      (if (if (< k 0) #t (> k n)) (%py-st-bad! "offset out of range") k))))

(def %py-st-unpack-from
  (fn (_ fmt buf . more)
    (let ((f (%py-st-read fmt)) (bs (%py-st-bytes-of buf)))
      (let ((k (%py-st-offset (%py-opt more 0 0) (%py-length bs))))
        (let ((want (%py-st-size (List ref 2 f) (List ref 1 f) 0)))
          (let ((tail (%py-drop bs k)))
            (if (< (%py-length tail) want)
              (%py-st-bad! "buffer too small for the format")
              (%py-tuple-of-list
                (%py-st-read-items (List ref 2 f) (List ref 1 f) (first f)
                  (%py-take-n tail want ()) 0 ())))))))))

; pack_into writes THROUGH the bytearray, which is the point of it.
(def %py-st-splice
  (fn (self bs k new acc)
    (match
      ((null? bs) (%py-reverse acc))
      ((> k 0) (self (rest bs) (- k 1) new (pair (first bs) acc)))
      ((null? new) (self (rest bs) 0 () (pair (first bs) acc)))
      (#t (self (rest bs) 0 (rest new) (pair (first new) acc))))))

(def %py-st-pack-into
  (fn (_ fmt buf off . vals)
    (if (not (%py-barr-is buf))
      (%py-st-bad! "pack_into() wants a bytearray")
      (let ((bs (%py-bytes-list buf)))
        (let ((k (%py-st-offset off (%py-length bs)))
              (f (%py-st-read fmt)))
          (let ((body (first (%py-st-emit (List ref 2 f) (List ref 1 f) (first f) vals ()))))
            (if (> (+ k (%py-length body)) (%py-length bs))
              (%py-st-bad! "buffer too small for the format")
              (%seq (%py-barr-set! buf (%py-st-splice bs k body ())) ()))))))))

; --- the module ------------------------------------------------------------------

(def %py-struct-module
  (fn (_)
    (%py-module-new "struct"
      (list
        (pair "calcsize" %py-st-calcsize)
        (pair "pack" %py-st-pack)
        (pair "unpack" %py-st-unpack)
        (pair "pack_into" %py-st-pack-into)
        (pair "unpack_from" %py-st-unpack-from)))))

(provide python/struct %py-struct-module)
