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
; internals (an attribute name, an error message).  %ps-of-x, %ps-write and
; %ps->x are those doors.
;
; Two of them cannot carry a zero byte and say so: %ps->x REFUSES rather than
; truncating -- the same rule python/bytes.x's %pb->str follows, and for the
; same reason -- because what it returns IS a platform string, and an attribute
; name or an error message that stopped early would be worse than an error.
;
; The WRITER is the one that can, because writing is the one direction where a
; LENGTH can travel beside the bytes.  See "the writer" below.

(import python/bytes)
; (File write) -- the only door out of here that takes a length, and so the
; only one a NUL can leave through.  See "the writer".
(import x/sys/file)

(provide python/str
  %ps-of-x %ps->x %ps-write %ps-write-bytes-to %ps-nul? %ps-encode %ps-enc1 %ps-decode
  %ps-decode-as %ps-encode-as
  %ps-repr %ps-upper %ps-lower %ps-swapcase %ps-capitalize %ps-title
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

; --- Python's codecs ---------------------------------------------------------
;
; The decoder above is the READER'S door and not a codec: it takes what the
; platform handed us, which the reader has already accepted, and a byte that
; starts nothing as itself.  bytes.decode and str(b, encoding) ask the other
; question -- is this valid utf-8, or valid ascii? -- and answer it three ways.
;
; strict raises, ignore drops, replace answers U+FFFD, one per MAXIMAL SUBPART:
; the longest prefix of a sequence that was still valid.  So a truncated
; three-byte start before a space is ONE replacement and three truncated starts
; in a row are three, which is the count CPython reports.
;
; The message names a byte and a position, and the formatters for both are the
; Python layer's -- this file has no number to text of its own, and a second
; one is not worth the two it would save.

(def %ps-repl 65533)
(def %ps-qmark 63)

; The codecs a program here can name, under the spellings it names them by.
(def %ps-codec
  (fn (_ name)
    (match
      ((Str8 =? name "utf-8") (lit utf-8))
      ((Str8 =? name "utf8") (lit utf-8))
      ((Str8 =? name "UTF-8") (lit utf-8))
      ((Str8 =? name "ascii") (lit ascii))
      ((Str8 =? name "us-ascii") (lit ascii))
      (#t (Err raise (lit lookup) (Str8 append "unknown encoding: " name) ())))))

; What a lead byte promises: how many continuations follow, the range the FIRST
; of them may be in, and the payload it carries.  The narrow first ranges are
; what refuse an overlong form, a surrogate and a code point past U+10FFFF;
; nil is a byte that can start nothing.
(def %ps-lead
  (fn (_ b)
    (match
      ((< b 128) (list 0 0 0 b))
      ((< b 194) ())
      ((< b 224) (list 1 128 191 (- b 192)))
      ((= b 224) (list 2 160 191 0))
      ((= b 237) (list 2 128 159 13))
      ((< b 240) (list 2 128 191 (- b 224)))
      ((= b 240) (list 3 144 191 0))
      ((< b 244) (list 3 128 191 (- b 240)))
      ((= b 244) (list 3 128 143 4))
      (#t ()))))

; One sequence: its code point and what follows it, or nil and the bytes past
; the maximal subpart -- the lead and the continuations that were still valid.
(def %ps-utf8
  (fn (_ bs)
    (let ((l (%ps-lead (first bs))))
      (if (null? l)
        (pair () (rest bs))
        (%ps-utf8-tail (rest bs) (first l) (first (rest l))
          (first (rest (rest l))) (first (rest (rest (rest l)))))))))

(def %ps-utf8-tail
  (fn (self bs need lo hi cp)
    (if (= need 0)
      (pair cp bs)
      (if (null? bs)
        (pair () bs)
        (let ((b (first bs)))
          (if (if (>= b lo) (<= b hi) #f)
            (self (rest bs) (- need 1) 128 191 (+ (* cp 64) (- b 128)))
            (pair () bs)))))))

; ascii is the same walk over a one-byte alphabet.
(def %ps-ascii
  (fn (_ bs)
    (if (< (first bs) 128) (pair (first bs) (rest bs)) (pair () (rest bs)))))

; The walk: a code point onto the answer, and `bad` says what a failure leaves
; there -- nothing, a replacement, or an error.
(def %ps-walk
  (fn (self step bad bs acc)
    (if (null? bs)
      (List reverse acc)
      (let ((r (step bs)))
        (if (null? (first r))
          (self step bad (rest r) (bad acc bs))
          (self step bad (rest r) (pair (first r) acc)))))))

(def %ps-handler!
  (fn (_ errors)
    (Err raise (lit lookup)
      (Str8 append "unknown error handler name '" (Str8 append errors "'")) ())))

(def %ps-dec-errors
  (fn (_ errors name n)
    (match
      ((Str8 =? errors "strict")
        (fn (_ acc bs)
          (Err raise (lit unicode-decode)
            (Str8 append "'"
              (Str8 append name
                (Str8 append "' codec can't decode byte 0x"
                  (Str8 append (%py-hex2 (first bs))
                    (Str8 append " in position " (%py-str (- n (%pb-len bs))))))))
            ())))
      ((Str8 =? errors "ignore") (fn (_ acc bs) acc))
      ((Str8 =? errors "replace") (fn (_ acc bs) (pair %ps-repl acc)))
      ; a name nothing here knows is an error only where it would have been
      ; used, which is where CPython looks one up
      (#t (fn (_ acc bs) (%ps-handler! errors))))))

(def %ps-decode-as
  (fn (_ bs name errors)
    (%ps-walk (if (eq? (%ps-codec name) (lit ascii)) %ps-ascii %ps-utf8)
      (%ps-dec-errors errors name (%pb-len bs)) bs ())))

; The other direction, where only ascii can refuse: utf-8 takes every code
; point there is.  Python's replacement on the way out is a question mark.
(def %ps-enc-errors
  (fn (_ errors name n)
    (match
      ((Str8 =? errors "strict")
        (fn (_ acc cps)
          (Err raise (lit unicode-encode)
            (Str8 append "'"
              (Str8 append name
                (Str8 append "' codec can't encode character in position "
                  (Str8 append (%py-str (- n (%pb-len cps)))
                    ": ordinal not in range(128)"))))
            ())))
      ((Str8 =? errors "ignore") (fn (_ acc cps) acc))
      ((Str8 =? errors "replace") (fn (_ acc cps) (pair %ps-qmark acc)))
      (#t (fn (_ acc cps) (%ps-handler! errors))))))

(def %ps-enc-ascii
  (fn (self cps bad acc)
    (if (null? cps)
      (List reverse acc)
      (if (< (first cps) 128)
        (self (rest cps) bad (pair (first cps) acc))
        (self (rest cps) bad (bad acc cps))))))

(def %ps-encode-as
  (fn (_ cps name errors)
    (if (eq? (%ps-codec name) (lit ascii))
      (%ps-enc-ascii cps (%ps-enc-errors errors name (%pb-len cps)) ())
      (%ps-encode cps ()))))

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

; --- the writer --------------------------------------------------------------
;
; A NUL-BEARING str PRINTS, and this is the door that lets it.
;
; Every other way out stops at the zero byte, because every other way out hands
; the platform a C string: `display` of a string stops there, %ps->x refuses
; rather than reach it, and a CHARACTER is no escape either -- (display (int
; ->char 0)) writes nothing at all, measured, not assumed.
;
; The way out is the platform's own, the one x/codec/zlib.x takes for binary:
; copy the bytes into a (str make) region and hand the kernel the LENGTH.  That
; is the whole trick -- a length is the one thing that can travel beside a
; NUL-blind buffer, which is why (File write) asks for one.  The region's own
; `str byte-len` would answer 1 here, so the length is carried and never read
; back.
;
; `display` and `File write` interleave in program order -- checked, because if
; the engine buffered one and not the other a print would come out shuffled --
; so a string taking this path still lands between the sep and end around it.
;
; THE FAST PATH IS STILL display.  A str with no zero byte -- which is every
; str in almost every program -- is written exactly as it was before: no
; region, no syscall, nothing new to pay for.
(def %ps-write
  (fn (_ l)
    (if (%ps-nul? l)
      (%ps-write-bytes (%ps-encode l ()))
      (display (%pb->str (%ps-encode l ()))))))

; The region is GC-owned and dies with the call.  An empty list writes nothing:
; (str make 0) is not a buffer, and there is nothing to put in it.  The fd is
; the caller's: print's is 1, and sys.stderr's is 2.
(def %ps-write-bytes-to
  (fn (_ fd bs)
    (let ((n (List length bs)))
      (unless (= n 0)
        (let ((region (%ps-make n)))
          (%seq (%ps-fill (%ps->ptr region) bs 0)
                (File write fd region n)))))))

(def %ps-write-bytes (fn (_ bs) (%ps-write-bytes-to 1 bs)))

(def %ps-fill
  (fn (self p bs i)
    (unless (null? bs)
      (%seq (%ps-pset p i (first bs) 1)
            (self p (rest bs) (+ i 1))))))

(def %ps-make (prim-ref (lit str) (lit make)))
(def %ps->ptr (prim-ref (lit str) (lit ->ptr)))
(def %ps-pset (prim-ref (lit ptr) (lit set!)))
