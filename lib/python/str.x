; # x-python -- Python on x-lang
;
; ## lib/python/str.x -- the code point sequence, and the codec under it
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
; ps->x are those doors.
;
; Two of them cannot carry a zero byte and say so: ps->x REFUSES rather than
; truncating -- the same rule python/bytes.x's pb->str follows, and for the
; same reason -- because what it returns IS a platform string, and an attribute
; name or an error message that stopped early would be worse than an error.
;
; The WRITER is the one that can, because writing is the one direction where a
; LENGTH can travel beside the bytes.  See "the writer" below.

; (File write) -- the only door out of here that takes a length, and so the
; only one a NUL can leave through.  See "the writer".
(module python/core)
(import x/sys/file)

; --- the utf-8 codec ---------------------------------------------------------
;
; Arithmetic rather than shifts, because the quotient and the remainder say
; what is meant here and need no assumption about which bitwise prims this
; dialect carries.
(def ps-enc1
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

(def ps-encode
  (fn (self cps acc)
    (if (null? cps) (List reverse acc)
      (self (rest cps) (%ps-enc-onto (ps-enc1 (first cps)) acc)))))
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
; question -- is this valid in the encoding named? -- and answer it in the
; ways the error handler names.
;
; strict raises, ignore drops, replace answers U+FFFD, and surrogatepass lets
; a lone surrogate through in the codec's own form of one, where a utf-8,
; utf-16 or utf-32 codec would otherwise refuse it.  A failure covers one
; MAXIMAL SUBPART in utf-8 -- the longest prefix of a sequence that was still
; valid -- so a truncated three-byte start before a space is ONE replacement
; and three truncated starts in a row are three, which is the count CPython
; reports.  In utf-16 it is a code unit, and in utf-32 four bytes.
;
; The message names the bytes, their position and why, in CPython's words.
; The formatters for numbers are the Python layer's -- this file has no
; number to text of its own, and a second one is not worth the two it would
; save.

(def %ps-repl 65533)
(def %ps-qmark 63)

; --- naming a codec ----------------------------------------------------------
;
; A name is looked up the way CPython's encodings package looks it up: in
; lower case, with each run of characters that are neither a letter, a digit
; nor a dot turned into one underscore, and none at either end.  So UTF-16,
; utf_16 and "utf 16" are one name, and utf16le is not one at all.
(def %ps-name-ch?
  (fn (_ b)
    (match
      ((= b 46) #t)
      ((python-fx< b 48) #f)
      ((python-fx< b 58) #t)
      ((python-fx< b 97) #f)
      ((python-fx< b 123) #t)
      (#t #f))))

(def %ps-lower1 (fn (_ b) (if (python-fx< b 65) b (if (python-fx< b 91) (+ b 32) b))))

(def %ps-norm-go
  (fn (self bs gap? acc)
    (if (null? bs)
      (List reverse acc)
      (let ((b (%ps-lower1 (first bs))))
        (if (%ps-name-ch? b)
          (self (rest bs) #f (pair b (if (if gap? (not (null? acc)) #f) (pair 95 acc) acc)))
          (self (rest bs) #t acc))))))

(def %ps-norm (fn (_ name) (pb->str (%ps-norm-go (pb-of-str name) #f ()))))

(def %ps-codecs
  (list
    (pair "utf_8" (lit utf-8)) (pair "utf8" (lit utf-8)) (pair "u8" (lit utf-8))
    (pair "utf" (lit utf-8)) (pair "utf8_ucs2" (lit utf-8))
    (pair "utf8_ucs4" (lit utf-8)) (pair "cp65001" (lit utf-8))
    (pair "utf_8_sig" (lit utf-8-sig))
    (pair "ascii" (lit ascii)) (pair "us_ascii" (lit ascii)) (pair "us" (lit ascii))
    (pair "646" (lit ascii)) (pair "cp367" (lit ascii)) (pair "csascii" (lit ascii))
    (pair "ibm367" (lit ascii)) (pair "iso646_us" (lit ascii))
    (pair "iso_646.irv_1991" (lit ascii)) (pair "iso_ir_6" (lit ascii))
    (pair "ansi_x3.4_1968" (lit ascii)) (pair "ansi_x3_4_1968" (lit ascii))
    (pair "ansi_x3.4_1986" (lit ascii))
    (pair "utf_16" (lit utf-16)) (pair "utf16" (lit utf-16)) (pair "u16" (lit utf-16))
    (pair "utf_16_le" (lit utf-16-le)) (pair "utf_16le" (lit utf-16-le))
    (pair "unicodelittleunmarked" (lit utf-16-le))
    (pair "utf_16_be" (lit utf-16-be)) (pair "utf_16be" (lit utf-16-be))
    (pair "unicodebigunmarked" (lit utf-16-be))
    (pair "utf_32" (lit utf-32)) (pair "utf32" (lit utf-32)) (pair "u32" (lit utf-32))
    (pair "utf_32_le" (lit utf-32-le)) (pair "utf_32le" (lit utf-32-le))
    (pair "utf_32_be" (lit utf-32-be)) (pair "utf_32be" (lit utf-32-be))))

(def %ps-codec-find
  (fn (self n l)
    (match
      ((null? l) ())
      ((Str8 =? n (first (first l))) (rest (first l)))
      (#t (self n (rest l))))))

; The codecs a program here can name, as the symbol each is known by inside.
(def ps-codec
  (fn (_ name)
    (let ((c (%ps-codec-find (%ps-norm name) %ps-codecs)))
      (if (null? c)
        (Err raise (lit lookup) (Str8 append "unknown encoding: " name) ())
        c))))

; A file reads and writes in pieces, and only utf-8 and ascii are codecs a
; piece can be decoded in without the rest: utf-16's code units and its BOM
; would need the stream to carry them across.  io asks this one.
(def ps-stream-codec
  (fn (_ name)
    (let ((c (ps-codec name)))
      (if (if (eq? c (lit utf-8)) #t (eq? c (lit ascii)))
        c
        (Err raise (lit lookup)
          (Str8 append "a file can't be read or written as " (Str8 append name " here")) ())))))

; --- the steps ---------------------------------------------------------------
;
; A step reads one code point from the front of the bytes and answers it and
; what follows, or -1, why not, and how many bytes the failure covers.

; What a lead byte promises: how many continuations follow, the range the FIRST
; of them may be in, and the payload it carries.  The narrow first ranges are
; what refuse an overlong form, a surrogate and a code point past U+10FFFF;
; nil is a byte that can start nothing.  A byte is 0..255 and a code point
; under 2^21, so the comparisons and the arithmetic in these four are on the
; integer doors (python/util.x).
(def %ps-lead
  (fn (_ b)
    (match
      ((python-fx< b 128) (list 0 0 0 b))
      ((python-fx< b 194) ())
      ((python-fx< b 224) (list 1 128 191 (python-fx- b 192)))
      ((= b 224) (list 2 160 191 0))
      ((= b 237) (list 2 128 159 13))
      ((python-fx< b 240) (list 2 128 191 (python-fx- b 224)))
      ((= b 240) (list 3 144 191 0))
      ((python-fx< b 244) (list 3 128 191 (python-fx- b 240)))
      ((= b 244) (list 3 128 143 4))
      (#t ()))))

; One sequence: its code point and what follows it, or the failure over the
; maximal subpart -- the lead and the continuations that were still valid.
; Running out of bytes is "unexpected end of data"; a byte out of the range is
; "invalid continuation byte" even when it is the first that follows.
(def %ps-utf8
  (fn (_ bs)
    (if (python-fx< (first bs) 128)
      (pair (first bs) (rest bs))
      (let ((l (%ps-lead (first bs))))
        (if (null? l)
          (list -1 "invalid start byte" 1)
          (%ps-utf8-tail (rest bs) (first l) (first (rest l))
            (first (rest (rest l))) (first (rest (rest (rest l)))) 1))))))

(def %ps-utf8-tail
  (fn (self bs need lo hi cp k)
    (if (= need 0)
      (pair cp bs)
      (if (null? bs)
        (list -1 "unexpected end of data" k)
        (let ((b (first bs)))
          (if (python-fx< b lo)
            (list -1 "invalid continuation byte" k)
            (if (python-fx< hi b)
              (list -1 "invalid continuation byte" k)
              (self (rest bs) (python-fx- need 1) 128 191
                (%py-fx+ (%py-fx* cp 64) (python-fx- b 128)) (%py-fx+ k 1)))))))))

; ascii is the same walk over a one-byte alphabet.
(def %ps-ascii
  (fn (_ bs)
    (if (python-fx< (first bs) 128)
      (pair (first bs) (rest bs))
      (list -1 "ordinal not in range(128)" 1))))

; A code unit, two bytes in the byte order named; utf-32's is four.
(def %ps-u16
  (fn (_ le? bs)
    (if le?
      (%py-fx+ (first bs) (%py-fx* 256 (first (rest bs))))
      (%py-fx+ (%py-fx* 256 (first bs)) (first (rest bs))))))

(def %ps-u32
  (fn (_ le? bs)
    (let ((a (first bs)) (b (first (rest bs)))
          (c (first (rest (rest bs)))) (d (first (rest (rest (rest bs))))))
      (if le?
        (+ a (* 256 (+ b (* 256 (+ c (* 256 d))))))
        (+ d (* 256 (+ c (* 256 (+ b (* 256 a))))))))))

(def %ps-surrogate? (fn (_ c) (if (python-fx< c 55296) #f (python-fx< c 57344))))
(def %ps-high? (fn (_ c) (if (python-fx< c 55296) #f (python-fx< c 56320))))
(def %ps-low? (fn (_ c) (if (python-fx< c 56320) #f (python-fx< c 57344))))

; A HIGH SURROGATE AND A LOW ONE ARE ONE CODE POINT, and anything else a
; surrogate is in is a failure over the unit -- or over what is left, when the
; bytes end inside the pair.  The unit after a high surrogate that is not a
; low one is read again for itself.
(def %ps-utf16
  (fn (_ le?)
    (fn (_ bs)
      (if (null? (rest bs))
        (list -1 "truncated data" 1)
        (let ((u (%ps-u16 le? bs)) (more (rest (rest bs))))
          (match
            ((not (%ps-surrogate? u)) (pair u more))
            ((%ps-low? u) (list -1 "illegal encoding" 2))
            ((null? more) (list -1 "unexpected end of data" 2))
            ((null? (rest more)) (list -1 "unexpected end of data" 3))
            (#t
              (let ((v (%ps-u16 le? more)))
                (if (%ps-low? v)
                  (pair (+ 65536 (+ (* 1024 (- u 55296)) (- v 56320)))
                    (rest (rest more)))
                  (list -1 "illegal UTF-16 surrogate" 2))))))))))

(def %ps-utf32
  (fn (_ le?)
    (fn (_ bs)
      (let ((n (%ps-at-most 4 bs 0)))
        (if (python-fx< n 4)
          (list -1 "truncated data" n)
          (let ((c (%ps-u32 le? bs)))
            (match
              ((%ps-surrogate? c)
                (list -1 "code point in surrogate code point range(0xd800, 0xe000)" 4))
              ((< c 1114112) (pair c (%pb-drop 4 bs)))
              (#t (list -1 "code point not in range(0x110000)" 4)))))))))

; How many bytes there are, counting no further than k.
(def %ps-at-most
  (fn (self k bs n)
    (if (if (null? bs) #t (= n k)) n (self k (rest bs) (%py-fx+ n 1)))))

; --- surrogatepass, coming in ------------------------------------------------
;
; The surrogate at the front of the bytes in the codec's form of one, and what
; follows it, or nil when what is there is not one -- and then the failure is
; raised as strict would have raised it.
(def %ps-pass8
  (fn (_ bs)
    (if (= (first bs) 237)
      (let ((tl (rest bs)))
        (if (null? tl) ()
          (if (null? (rest tl)) ()
            (let ((b1 (first tl)) (b2 (first (rest tl))))
              (if (if (python-fx< b1 160) #t (python-fx< 191 b1)) ()
                (if (if (python-fx< b2 128) #t (python-fx< 191 b2)) ()
                  (pair (+ 53248 (+ (* 64 (- b1 128)) (- b2 128)))
                    (rest (rest tl)))))))))
      ())))

(def %ps-pass16
  (fn (_ le?)
    (fn (_ bs)
      (if (python-fx< (%ps-at-most 2 bs 0) 2) ()
        (let ((u (%ps-u16 le? bs)))
          (if (%ps-surrogate? u) (pair u (rest (rest bs))) ()))))))

(def %ps-pass32
  (fn (_ le?)
    (fn (_ bs)
      (if (python-fx< (%ps-at-most 4 bs 0) 4) ()
        (let ((c (%ps-u32 le? bs)))
          (if (%ps-surrogate? c) (pair c (%pb-drop 4 bs)) ()))))))

(def %ps-pass-none (fn (_ bs) ()))

; --- decoding ----------------------------------------------------------------
;
; The walk: a code point onto the answer, and `bad` says what a failure leaves
; there and where the walk picks up again.  An ascii byte is the same code
; point under utf-8 and ascii, so with `fast` it goes onto the answer without
; the step.
(def %ps-walk
  (fn (self step bad fast bs acc)
    (if (null? bs)
      (python-reverse acc)
      (if (if fast (python-fx< (first bs) 128) #f)
        (self step bad fast (rest bs) (pair (first bs) acc))
        (let ((r (step bs)))
          (if (python-fx< (first r) 0)
            (let ((b (bad acc bs r)))
              (self step bad fast (rest b) (first b)))
            (self step bad fast (rest r) (pair (first r) acc))))))))

(def %ps-handler!
  (fn (_ errors)
    (Err raise (lit lookup)
      (Str8 append "unknown error handler name '" (Str8 append errors "'")) ())))

; 'utf-16-le' codec can't decode bytes in position 0-1: illegal encoding
(def %ps-dec-raise
  (fn (_ name all bs r)
    (let ((at (- (pb-len all) (pb-len bs))) (k (first (rest (rest r)))))
      (Err raise (lit unicode-decode)
        (Str8 append "'"
          (Str8 append name
            (Str8 append "' codec can't decode "
              (Str8 append
                (if (= k 1)
                  (Str8 append "byte 0x"
                    (Str8 append (%py-hex2 (first bs))
                      (Str8 append " in position " (python-str at))))
                  (Str8 append "bytes in position "
                    (Str8 append (python-str at)
                      (Str8 append "-" (python-str (+ at (- k 1)))))))
                (Str8 append ": " (first (rest r)))))))
        ()))))

(def %ps-dec-errors
  (fn (_ errors name all pass)
    (match
      ((Str8 =? errors "strict") (fn (_ acc bs r) (%ps-dec-raise name all bs r)))
      ((Str8 =? errors "ignore")
        (fn (_ acc bs r) (pair acc (%pb-drop (first (rest (rest r))) bs))))
      ((Str8 =? errors "replace")
        (fn (_ acc bs r) (pair (pair %ps-repl acc) (%pb-drop (first (rest (rest r))) bs))))
      ((Str8 =? errors "surrogatepass")
        (fn (_ acc bs r)
          (let ((s (pass bs)))
            (if (null? s)
              (%ps-dec-raise name all bs r)
              (pair (pair (first s) acc) (rest s))))))
      ; a name nothing here knows is an error only where it would have been
      ; used, which is where CPython looks one up
      (#t (fn (_ acc bs r) (%ps-handler! errors))))))

(def %ps-dec
  (fn (_ all bs step pass fast name errors)
    (%ps-walk step (%ps-dec-errors errors name all pass) fast bs ())))

(def %ps-starts?
  (fn (self pre bs)
    (match
      ((null? pre) #t)
      ((null? bs) #f)
      ((= (first pre) (first bs)) (self (rest pre) (rest bs)))
      (#t #f))))

(def %ps-bom8 (list 239 187 191))
(def %ps-bom16le (list 255 254))
(def %ps-bom16be (list 254 255))
(def %ps-bom32le (list 255 254 0 0))
(def %ps-bom32be (list 0 0 254 255))

(def %ps-dec16
  (fn (_ all bs le? errors)
    (%ps-dec all bs (%ps-utf16 le?) (%ps-pass16 le?) #f
      (if le? "utf-16-le" "utf-16-be") errors)))

(def %ps-dec32
  (fn (_ all bs le? errors)
    (%ps-dec all bs (%ps-utf32 le?) (%ps-pass32 le?) #f
      (if le? "utf-32-le" "utf-32-be") errors)))

; utf-16 and utf-32 read their byte order from a BOM and drop it, and take
; little-endian when there is none; a position in a message still counts the
; BOM's bytes.  utf-8-sig drops one utf-8 BOM and is utf-8 after it, so there
; a position counts from past the BOM, as CPython's does.
(def ps-decode-as
  (fn (_ bs name errors)
    (let ((c (ps-codec name)))
      (match
        ((eq? c (lit utf-8)) (%ps-dec bs bs %ps-utf8 %ps-pass8 #t "utf-8" errors))
        ((eq? c (lit ascii)) (%ps-dec bs bs %ps-ascii %ps-pass-none #t "ascii" errors))
        ((eq? c (lit utf-8-sig))
          (let ((t8 (if (%ps-starts? %ps-bom8 bs) (%pb-drop 3 bs) bs)))
            (%ps-dec t8 t8 %ps-utf8 %ps-pass8 #t "utf-8" errors)))
        ((eq? c (lit utf-16-le)) (%ps-dec16 bs bs #t errors))
        ((eq? c (lit utf-16-be)) (%ps-dec16 bs bs #f errors))
        ((eq? c (lit utf-16))
          (match
            ((%ps-starts? %ps-bom16le bs) (%ps-dec16 bs (%pb-drop 2 bs) #t errors))
            ((%ps-starts? %ps-bom16be bs) (%ps-dec16 bs (%pb-drop 2 bs) #f errors))
            (#t (%ps-dec16 bs bs #t errors))))
        ((eq? c (lit utf-32-le)) (%ps-dec32 bs bs #t errors))
        ((eq? c (lit utf-32-be)) (%ps-dec32 bs bs #f errors))
        (#t
          (match
            ((%ps-starts? %ps-bom32le bs) (%ps-dec32 bs (%pb-drop 4 bs) #t errors))
            ((%ps-starts? %ps-bom32be bs) (%ps-dec32 bs (%pb-drop 4 bs) #f errors))
            (#t (%ps-dec32 bs bs #t errors))))))))

; --- encoding ----------------------------------------------------------------
;
; The other direction, where ascii refuses past U+007F and the utf codecs
; refuse a lone surrogate, which no utf encodes.  A code point's bytes come
; from `put`; surrogatepass writes a surrogate through `put` as well, since
; each of these codecs has a form for one and only its strictness refuses it.
; Python's replacement on the way out is a question mark, in the codec.
;
; utf-8 and ascii report a RUN of refused characters as one failure, as
; CPython's do; utf-16 and utf-32 report each.

(def %ps-u16-bytes
  (fn (_ le? u)
    (let ((hi (Num quotient u 256)) (lo (% u 256)))
      (if le? (list lo hi) (list hi lo)))))

(def %ps-put16
  (fn (_ le?)
    (fn (_ c)
      (if (python-fx< c 65536)
        (%ps-u16-bytes le? c)
        (let ((v (- c 65536)))
          (python-list-cat
            (%ps-u16-bytes le? (+ 55296 (Num quotient v 1024)))
            (%ps-u16-bytes le? (+ 56320 (% v 1024)))))))))

(def %ps-put32
  (fn (_ le?)
    (fn (_ c)
      (let ((l (list (% c 256) (% (Num quotient c 256) 256)
                     (% (Num quotient c 65536) 256) (Num quotient c 16777216))))
        (if le? l (List reverse l))))))

(def %ps-put8 (fn (_ c) (ps-enc1 c)))
(def %ps-put-ascii (fn (_ c) (list c)))

(def %ps-not-surrogate? (fn (_ c) (not (%ps-surrogate? c))))
(def %ps-ascii? (fn (_ c) (python-fx< c 128)))

; '\xe9', '\ud800' or '\U0001f600': how a message shows the character.
(def %ps-hex4
  (fn (_ n) (Str8 append (%py-hex2 (Num quotient n 256)) (%py-hex2 (% n 256)))))
(def %ps-esc
  (fn (_ c)
    (match
      ((python-fx< c 256) (Str8 append "\\x" (%py-hex2 c)))
      ((python-fx< c 65536) (Str8 append "\\u" (%ps-hex4 c)))
      (#t (Str8 append "\\U"
            (Str8 append (%ps-hex4 (Num quotient c 65536)) (%ps-hex4 (% c 65536))))))))

(def %ps-enc-raise
  (fn (_ name reason n cps k)
    (let ((at (- n (pb-len cps))))
      (Err raise (lit unicode-encode)
        (Str8 append "'"
          (Str8 append name
            (Str8 append "' codec can't encode "
              (Str8 append
                (if (= k 1)
                  (Str8 append "character '"
                    (Str8 append (%ps-esc (first cps))
                      (Str8 append "' in position " (python-str at))))
                  (Str8 append "characters in position "
                    (Str8 append (python-str at)
                      (Str8 append "-" (python-str (+ at (- k 1)))))))
                (Str8 append ": " reason)))))
        ()))))

(def %ps-run
  (fn (self ok? cps k)
    (if (if (null? cps) #t (ok? (first cps))) k (self ok? (rest cps) (%py-fx+ k 1)))))

; k code points, each through `put` -- or each as `put` writes a ?
(def %ps-put-k
  (fn (self put k q cps acc)
    (if (= k 0)
      (pair acc cps)
      (self put (python-fx- k 1) q (rest cps)
        (%ps-enc-onto (put (if q %ps-qmark (first cps))) acc)))))

(def %ps-enc-errors
  (fn (_ errors name reason n ok? put run? pass?)
    (fn (_ acc cps)
      (let ((k (if run? (%ps-run ok? cps 0) 1)))
        (match
          ((Str8 =? errors "strict") (%ps-enc-raise name reason n cps k))
          ((Str8 =? errors "ignore") (pair acc (%pb-drop k cps)))
          ((Str8 =? errors "replace") (%ps-put-k put k #t cps acc))
          ((Str8 =? errors "surrogatepass")
            (if pass? (%ps-put-k put k #f cps acc) (%ps-enc-raise name reason n cps k)))
          (#t (%ps-handler! errors)))))))

(def %ps-enc-walk
  (fn (self cps ok? put bad acc)
    (if (null? cps)
      (List reverse acc)
      (if (ok? (first cps))
        (self (rest cps) ok? put bad (%ps-enc-onto (put (first cps)) acc))
        (let ((b (bad acc cps)))
          (self (rest b) ok? put bad (first b)))))))

(def %ps-enc
  (fn (_ cps ok? put run? pass? name reason errors)
    (%ps-enc-walk cps ok? put
      (%ps-enc-errors errors name reason (pb-len cps) ok? put run? pass?) ())))

(def %ps-any-surrogate?
  (fn (self cps)
    (if (null? cps) #f (if (%ps-surrogate? (first cps)) #t (self (rest cps))))))

; utf-8 with no surrogate in it is the reader's own encoder, which is most of
; every encode.
(def %ps-enc8
  (fn (_ cps errors)
    (if (%ps-any-surrogate? cps)
      (%ps-enc cps %ps-not-surrogate? %ps-put8 #t #t "utf-8" "surrogates not allowed" errors)
      (ps-encode cps ()))))

(def %ps-enc16
  (fn (_ cps le? name errors)
    (%ps-enc cps %ps-not-surrogate? (%ps-put16 le?) #f #t name "surrogates not allowed" errors)))

(def %ps-enc32
  (fn (_ cps le? name errors)
    (%ps-enc cps %ps-not-surrogate? (%ps-put32 le?) #f #t name "surrogates not allowed" errors)))

; utf-16, utf-32 and utf-8-sig write their BOM first, even before nothing;
; utf-16 and utf-32 are little-endian after it.
(def ps-encode-as
  (fn (_ cps name errors)
    (let ((c (ps-codec name)))
      (match
        ((eq? c (lit utf-8)) (%ps-enc8 cps errors))
        ((eq? c (lit ascii))
          (%ps-enc cps %ps-ascii? %ps-put-ascii #t #f "ascii" "ordinal not in range(128)" errors))
        ((eq? c (lit utf-8-sig)) (python-list-cat %ps-bom8 (%ps-enc8 cps errors)))
        ((eq? c (lit utf-16-le)) (%ps-enc16 cps #t "utf-16-le" errors))
        ((eq? c (lit utf-16-be)) (%ps-enc16 cps #f "utf-16-be" errors))
        ((eq? c (lit utf-16)) (python-list-cat %ps-bom16le (%ps-enc16 cps #t "utf-16" errors)))
        ((eq? c (lit utf-32-le)) (%ps-enc32 cps #t "utf-32-le" errors))
        ((eq? c (lit utf-32-be)) (%ps-enc32 cps #f "utf-32-be" errors))
        (#t (python-list-cat %ps-bom32le (%ps-enc32 cps #t "utf-32" errors)))))))

; --- the boundary ------------------------------------------------------------
(def %ps-of-x (fn (_ s) (%ps-decode (pb-of-str s) ())))
(def %ps-nul? (fn (_ l) (%pb-nul? l)))

; REFUSES rather than truncates: a platform string cannot hold a zero, and a
; caller asking for one wants a value the str layer will keep whole.
(def ps->x
  (fn (_ l)
    (if (%ps-nul? l)
      (Err raise (lit value) "a NUL byte is not representable here" ())
      (pb->str (ps-encode l ())))))

; --- the writer --------------------------------------------------------------
;
; A NUL-BEARING str PRINTS, and this is the door that lets it.
;
; Every other way out stops at the zero byte, because every other way out hands
; the platform a C string: `display` of a string stops there, ps->x refuses
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
      (%ps-write-bytes (ps-encode l ()))
      (display (pb->str (ps-encode l ()))))))

; The region is GC-owned and dies with the call.  An empty list writes nothing:
; (str make 0) is not a buffer, and there is nothing to put in it.  The fd is
; the caller's: print's is 1, and sys.stderr's is 2.
(def ps-write-bytes-to
  (fn (_ fd bs)
    (let ((n (List length bs)))
      (unless (= n 0)
        (let ((region (str-make n)))
          (%seq (%ps-fill (str->ptr region) bs 0)
                (File write fd region n)))))))

(def %ps-write-bytes (fn (_ bs) (ps-write-bytes-to 1 bs)))

(def %ps-fill
  (fn (self p bs i)
    (unless (null? bs)
      (%seq (ptr-set! p i (first bs) 1)
            (self p (rest bs) (+ i 1))))))

(import x/core/doors str-make str->ptr ptr-set!)
