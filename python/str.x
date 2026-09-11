; # x-python -- Python on x-lang
;
; ## python/str.x -- the code point sequence, and the codec under it
;
; @description Python's str carries a CODE POINT list; this file is the part
;   python/bytes.x cannot supply -- the utf-8 codec, the repr, and the case
;   rules -- with the algorithms themselves borrowed from there.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY A str IS NOT A PLATFORM STRING EITHER
;
; python/bytes.x moved `bytes` off the platform's string because a string here
; is a C string and ends at its first NUL.  `str` has the same problem for the
; same reason, and one more of its own: it also had the WRONG UNIT.
;
; A Python str is a sequence of CODE POINTS.  This runtime kept it as a
; platform string and reached for the utf-8-aware `Str` class at exactly six
; places -- len, indexing, ord, and slicing -- while `find`, `split`,
; `replace`, `strip` and the rest ran on BYTES through Str8.  For ASCII the
; two agree and nothing showed; for anything else they do not, and the
; disagreement was invisible because no two of those methods were ever asked
; the same question.
;
; So the carrier is a list of code points.  A NUL is code point 0 like any
; other, `len` is the list's length, indexing is its nth, and every method is
; the code point algorithm in python/bytes.x -- those are generic over lists of ints
; and were written once already.  What is left, and what this file is, is the
; utf-8 codec at the boundary, the repr, and the case rules.
;
; ## THE BOUNDARY
;
; Three things still speak the platform's string: the READER (a literal
; arrives as one), the WRITER (display takes one), and this runtime's own
; internals (an attribute name, an error message).  %ps-of-x and %ps->x are
; those doors, and %ps->x REFUSES a NUL rather than truncating -- the same
; rule python/bytes.x's %pb->str follows, and for the same reason.

(import python/bytes)

(provide python/str
  %ps-of-x %ps->x %ps-nul? %ps-encode %ps-enc1 %ps-decode %ps-repr
  %ps-upper %ps-lower %ps-swapcase %ps-capitalize %ps-title
  %ps-isspace %ps-isalpha %ps-isdigit %ps-isalnum %ps-isupper %ps-islower)

; --- the utf-8 codec ---------------------------------------------------------
;
; Arithmetic rather than shifts, because the quotient and the remainder say
; what is meant here and need no assumption about which bitwise prims this
; dialect carries.
(def %ps-enc1
  (fn (_ c)
    (match
      ((< c 128) (list c))
      ((< c 2048)
        (list (+ 192 (Num quotient c 64)) (+ 128 (% c 64))))
      ((< c 65536)
        (list (+ 224 (Num quotient c 4096))
              (+ 128 (% (Num quotient c 64) 64))
              (+ 128 (% c 64))))
      (#t
        (list (+ 240 (Num quotient c 262144))
              (+ 128 (% (Num quotient c 4096) 64))
              (+ 128 (% (Num quotient c 64) 64))
              (+ 128 (% c 64)))))))

(def %ps-encode
  (fn (self cps acc)
    (if (null? cps) (List reverse acc)
      (self (rest cps) (%ps-enc-onto (%ps-enc1 (first cps)) acc)))))
(def %ps-enc-onto
  (fn (self l acc) (if (null? l) acc (self (rest l) (pair (first l) acc)))))

; A CONTINUATION BYTE IS 10xxxxxx, and a lead byte says how many follow.  A
; byte that is neither -- a lone continuation, a truncated tail -- is taken as
; itself rather than raising: this decodes what the reader handed us, and the
; reader has already accepted it.
(def %ps-follow
  (fn (self bs n acc)
    (if (= n 0) (pair acc bs)
      (if (null? bs) (pair acc bs)
        (self (rest bs) (- n 1) (+ (* acc 64) (% (first bs) 64)))))))

(def %ps-dec1
  (fn (_ bs)
    (let ((b (first bs)))
      (match
        ((< b 128) (pair b (rest bs)))
        ((< b 224) (%ps-follow (rest bs) 1 (% b 32)))
        ((< b 240) (%ps-follow (rest bs) 2 (% b 16)))
        ((< b 248) (%ps-follow (rest bs) 3 (% b 8)))
        (#t (pair b (rest bs)))))))

(def %ps-decode
  (fn (self bs acc)
    (if (null? bs) (List reverse acc)
      (let ((r (%ps-dec1 bs)))
        (self (rest r) (pair (first r) acc))))))

; --- the boundary ------------------------------------------------------------
(def %ps-of-x (fn (_ s) (%ps-decode (%pb-of-str s) ())))
(def %ps-nul? (fn (_ l) (%pb-nul? l)))

; REFUSES rather than truncates: a platform string cannot hold a zero, and a
; caller asking for one wants a value the str layer will keep whole.
(def %ps->x
  (fn (_ l)
    (if (%ps-nul? l)
      (Err raise (lit value) "a NUL byte is not representable here" ())
      (%pb->str (%ps-encode l ())))))
