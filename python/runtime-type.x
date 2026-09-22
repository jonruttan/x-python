; # x-python -- Python on x-lang
;
; ## python/runtime-type.x -- type objects, constructors, slicing and def
;
; @description The type objects themselves, the constructors behind int() and
;   friends, slicing, and def at whatever frame depth it appears.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A FRAGMENT OF python/runtime.x, NOT A MODULE.  It carries no provide
; and is include-once'd by runtime.x in load order; the %py-* names are
; shared across the whole rather than exported.  runtime.x was one
; 6,062-line file, which the platform's linter could not analyse -- it
; ran 91 seconds and the engine died with no diagnostic at all.

; A sweep before each section (84M objects under x-lang 0.14.0 on
; x86-64 as one load); a section boundary is a quiet point.  See
; python/util.x.
(%py-sweep!)
; --- Type objects ------------------------------------------------------------
;
; `type(x)` answers a CLASS, and the builtin types get real class objects --
; ordinary PY-CLASS values, so `type(1) == int` is the same identity compare
; user classes already get, and print(int) goes through the same write handler.
;
; TWO x TYPES ARE ONE PYTHON TYPE.  A small integer and a bigint are different
; types to x's tower and both are `int` to Python, so the dispatch below maps
; both handles to one class -- measured with eq? on the handles, which is how
; the handles compare.  bool's base is int, which is Python's own arrangement
; and the reason isinstance(True, int) is True while isinstance(1, bool) is not.

(def %py-char-code (prim-ref (lit char) (lit ->int)))

(%py-sweep!)
; --- constructors ------------------------------------------------------------
; int('abc') is a ValueError with Python's own message, and the parse is walked
; BY HAND: the reader-base shortcut accepts prefixes ("12ab" would answer 12),
; and `Float from` answers 0.0 for garbage -- both silent wrong numbers, the
; failure mode this bundle keeps finding, so neither is trusted with input the
; program supplied.

; Digits in a base (2, 8, 16), promoting through the tower like the
; decimal parser; used by the 0x/0o/0b literals.
(def %py-int-of-based
  (fn (_ s base)
    (def n (Str8 length s))
    (def val
      (fn (_ c)
        (match
          ((if (>= c 48) (<= c 57) #f) (- c 48))
          ((if (>= c 97) (<= c 122) #f) (- c 87))
          ((if (>= c 65) (<= c 90) #f) (- c 55))
          (#t 99))))
    (def go
      (fn (self i acc)
        (if (>= i n) acc
          (let ((c (%py-char-code (%str-ref s i))))
            (if (= c 95) (self (+ i 1) acc)
              (let ((v (val c)))
                (if (>= v base)
                  (Err raise (lit value) (Str8 append "invalid literal for int() with base: " s) ())
                  (self (+ i 1) (+ (* acc base) v)))))))))
    (if (= n 0) (Err raise (lit value) "invalid literal for int()" ()) (go 0 0))))

(def %py-int-of-str
  (fn (_ s)
    (def n (%py-byte-len s))
    (def bad
      (fn (_)
        (Err raise (lit value)
          (Str8 append
            (Str8 append "invalid literal for int() with base 10: '" s) "'")
          ())))
    (def code (fn (_ i) (%py-char-code (%str-ref s i))))
    (def digits
      (fn (self i acc seen)
        (if (>= i n)
          (if seen acc (bad))
          (let ((c (code i)))
            (if (if (>= c 48) (<= c 57) #f)
              (self (+ i 1) (+ (* acc 10) (- c 48)) #t)
              ; underscores are spelling (`1_2_3`), skipped the way the
              ; float path strips them
              (if (= c 95)
                (self (+ i 1) acc seen)
                (bad)))))))
    (if (= n 0)
      (bad)
      (let ((c0 (code 0)))
        (if (= c0 45)
          (- 0 (digits 1 0 #f))
          (if (= c0 43)
            (digits 1 0 #f)
            (digits 0 0 #f)))))))

; float('...') is shape-checked before Float from sees it: sign, digits, one
; dot, one exponent.  Stricter than CPython (no inf/nan, no surrounding
; spaces), and strictness fails LOUDLY where the alternative answered 0.0.
(def %py-float-str-ok?
  (fn (_ s)
    (def n (Str8 length s))
    (def code (fn (_ i) (%py-char-code (%str-ref s i))))
    (def walk
      (fn (self i seen-digit seen-dot seen-e)
        (if (>= i n)
          seen-digit
          (let ((c (code i)))
            (match
              ((if (>= c 48) (<= c 57) #f) (self (+ i 1) #t seen-dot seen-e))
              ((= c 46)
                (if (if seen-dot #t seen-e) #f (self (+ i 1) seen-digit #t seen-e)))
              ((if (= c 101) #t (= c 69))
                (if seen-e #f
                  (if (not seen-digit) #f
                    (let ((j (if (< (+ i 1) n)
                               (if (if (= (code (+ i 1)) 43) #t (= (code (+ i 1)) 45))
                                 (+ i 2) (+ i 1))
                               (+ i 1))))
                      (self j #f seen-dot #t)))))
              (#t #f))))))
    (if (= n 0)
      #f
      (let ((c0 (code 0)))
        (if (if (= c0 45) #t (= c0 43))
          (if (= n 1) #f (walk 1 #f #f #f))
          (walk 0 #f #f #f))))))

; Python's float() also takes "inf", "infinity" and "nan" in any case, with an
; optional sign and surrounding whitespace, and underscores between digits.
; The specials are matched HERE and handed to strtod by their canonical
; spelling; everything else is underscore-stripped and shape-checked as before.
(def %py-f-trim
  (fn (_ s)
    (def n (Str8 length s))
    (def ws? (fn (_ c) (match
                         ((= c 32) #t)
                         ((= c 9) #t)
                         ((= c 10) #t)
                         (#t (= c 13)))))
    (def a
      (fn (self i)
        (if (>= i n) i (if (ws? (%py-f-code s i)) (self (+ i 1)) i))))
    (def b
      (fn (self i)
        (if (< i 0) i (if (ws? (%py-f-code s i)) (self (- i 1)) i))))
    (let ((lo (a 0)))
      (let ((hi (b (- n 1))))
        (if (> lo hi) "" (Str8 sub lo (+ (- hi lo) 1) s))))))

(def %py-f-lower
  (fn (_ s)
    (def n (Str8 length s))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-f-code s i)))
            (self (+ i 1)
              (Str8 append acc
                (if (if (>= c 65) (<= c 90) #f)
                  (Str8 sub (- c 65) 1 "abcdefghijklmnopqrstuvwxyz")
                  (Str8 sub i 1 s))))))))
    (go 0 "")))

(def %py-f-strip-us
  (fn (_ s)
    (if (null? (Str8 index-of "_" s))
      s
      (do
        (def n (Str8 length s))
        (def go
          (fn (self i acc)
            (if (>= i n)
              acc
              (let ((c (Str8 sub i 1 s)))
                (self (+ i 1)
                  (if (Str8 =? c "_") acc (Str8 append acc c)))))))
        (go 0 "")))))

(def %py-float-of-str
  (fn (_ s0)
    (def s (%py-f-trim s0))
    (def bad
      (fn (_)
        (Err raise (lit value)
          (Str8 append
            (Str8 append "could not convert string to float: '" s0) "'")
          ())))
    (def signed
      (fn (_)
        (if (= (Str8 length s) 0)
          (pair "" "")
          (let ((c (%py-f-code s 0)))
            (if (= c 45) (pair "-" (Str8 sub 1 (- (Str8 length s) 1) s))
              (if (= c 43) (pair "" (Str8 sub 1 (- (Str8 length s) 1) s))
                (pair "" s)))))))
    (let ((sp (signed)))
      (let ((low (%py-f-lower (rest sp))))
        (if (if (Str8 =? low "inf") #t (Str8 =? low "infinity"))
          (Float from (Str8 append (first sp) "inf"))
          (if (Str8 =? low "nan")
            (Float from "nan")
            (let ((t (%py-f-strip-us s)))
              (if (%py-float-str-ok? t)
                (Float from t)
                (bad)))))))))

(def %py-num-kind
  (fn (_ v)
    (let ((h (%py-typeof-prim v)))
      (match
        ((eq? h %py-th-int) (lit int))
        ((eq? h %py-th-big) (lit int))
        ((eq? h %py-th-float) (lit float))
        ((eq? h %py-th-complex) (lit complex))
        (#t ())))))

(%py-sweep!)
; --- int(text, base) ---------------------------------------------------------
; Surrounding whitespace, a sign, the 0x/0o/0b prefix the base allows (any of
; them when the base is 0), then digits with underscores between; a bytes-like
; argument is its text.  Python's message names the base and the whole text.
(def %py-int-ws?
  (fn (_ c)
    (match ((= c 32) #t) ((= c 9) #t) ((= c 10) #t) ((= c 13) #t) ((= c 11) #t) ((= c 12) #t) (#t #f))))

(def %py-int-text-bad
  (fn (_ s base)
    (Err raise (lit value)
      (Str8 append "invalid literal for int() with base "
        (Str8 append (%py-str base) (Str8 append ": '" (Str8 append s "'"))))
      ())))

; (base . start): where the digits begin past a prefix the base allows, and
; the base a prefix decides when it was 0
(def %py-int-prefix
  (fn (_ code i j base)
    (let ((c (if (< (+ i 1) j) (if (= (code i) 48) (code (+ i 1)) 0) 0)))
      (match
        ((if (if (= c 120) #t (= c 88)) (if (= base 0) #t (= base 16)) #f) (pair 16 (+ i 2)))
        ((if (if (= c 111) #t (= c 79)) (if (= base 0) #t (= base 8)) #f) (pair 8 (+ i 2)))
        ((if (if (= c 98) #t (= c 66)) (if (= base 0) #t (= base 2)) #f) (pair 2 (+ i 2)))
        (#t (pair (if (= base 0) 10 base) i))))))

(def %py-int-of-text
  (fn (_ s base)
    (def n (%py-byte-len s))
    (def code (fn (_ i) (%py-char-code (%str-ref s i))))
    (def skip (fn (self i) (if (if (< i n) (%py-int-ws? (code i)) #f) (self (+ i 1)) i)))
    (def back (fn (self j) (if (if (> j 0) (%py-int-ws? (code (- j 1))) #f) (self (- j 1)) j)))
    (let ((i (skip 0)) (j (back n)))
      (if (>= i j)
        (%py-int-text-bad s base)
        (let ((c0 (code i)))
          (let ((p (%py-int-prefix code (if (if (= c0 45) #t (= c0 43)) (+ i 1) i) j base)))
            (if (>= (rest p) j)
              (%py-int-text-bad s base)
              (let ((v (guard (e (%py-int-text-bad s base))
                         (%py-int-of-based (Str8 sub (rest p) (- j (rest p)) s) (first p)))))
                ; with base 0 and no prefix, a leading zero may only spell zero
                (if (if (= base 0) (if (= (first p) 10) (if (= (code (rest p)) 48) (not (= v 0)) #f) #f) #f)
                  (%py-int-text-bad s base)
                  (if (= c0 45) (- 0 v) v))))))))))

(def %py-int-ctor
  (%py-sig!
    (fn (_ . a)
      (match
        ((null? a) 0)
        ; an explicit base takes text only
        ((not (null? (rest a)))
          (let ((v (first a)) (base (%py-boolnorm (first (rest a)))))
            (match
              ((not (eq? (%py-num-kind base) (lit int)))
                (Err raise (lit type) "'base' must be an integer" ()))
              ((if (= base 0) #f (if (< base 2) #t (> base 36)))
                (Err raise (lit value) "int() base must be >= 2 and <= 36, or 0" ()))
              ((%py-str-is v) (%py-int-of-text (%ps->x (%py-str-cps v)) base))
              ((%py-bytes-is v) (%py-int-of-text (%py-bytes-str v) base))
              (#t (Err raise (lit type) "int() can't convert non-string with explicit base" ())))))
        (#t
          (let ((v (first a)))
            (match
              ((eq? v #t) 1)
              ((eq? v #f) 0)
              ((%py-str-is v) (%py-int-of-text (%ps->x (%py-str-cps v)) 10))
              ; any buffer's text, which int() reads without a base; with one it
              ; takes bytes and a bytearray only, as the arm above does
              ((%py-buffer? v) (%py-int-of-text (%py-buffer-text v) 10))
              ((%py-obj-is v)
                (let ((m (%py-dunder v "__int__")))
                  (if (null? m)
                    (Err raise (lit type) "int() argument must be a number or string" ())
                    (m))))
              (#t
                (let ((k (%py-num-kind v)))
                  (if (eq? k (lit int)) v
                  (if (eq? k (lit float))
                    ; toward zero through the EXACT DIGITS, so int(1e19) and
                    ; int(2.0 ** 100) answer bigints instead of a wrapped int64
                    (let ((m (%py-fmt-int-mag v)))
                      (let ((n (%py-int-of-str (rest m))))
                        (if (first m) (- 0 n) n)))
                    (Err raise (lit type) "int() argument must be a number or string" ()))))))))))
    "int" (list "x" "base") 0 #f))

(def %py-float-ctor
  (fn (_ . a)
    (if (null? a)
      0.0
      (let ((v (first a)))
        (match
          ((eq? v #t) 1.0)
          ((eq? v #f) 0.0)
          ((%py-str-is v) (%py-float-of-str (%ps->x (%py-str-cps v))))
          ; a buffer's own text, as int() reads one
          ((%py-buffer? v) (%py-float-of-str (%py-buffer-text v)))
          ((%py-obj-is v)
            (let ((m (%py-dunder v "__float__")))
              (if (null? m)
                (Err raise (lit type) "float() argument must be a number or string" ())
                (m))))
          (#t
            (let ((k (%py-num-kind v)))
              (if (eq? k (lit float)) v
              (if (eq? k (lit int)) (* v 1.0)
                (Err raise (lit type) "float() argument must be a number or string" ()))))))))))

; Python's truthiness, stated once: the empties and the zeros are false and
; everything else is true.  Objects and classes are unconditionally true.
(def %py-truthy
  (fn (_ v)
    (match
      ((eq? v #f) #f)
      ((eq? v #t) #t)
      ((null? v) #f)
      ((%py-str-is v) (> (%pb-len (%py-str-cps v)) 0))
      ((%py-list-is v) (not (null? (%py-list-elems v))))
      ((%py-set-is v) (not (null? (%py-set-elems v))))
      ((%py-view-is v) (not (null? (%py-view-elems v))))
      ((%py-dict-is v) (not (null? (%py-dict-entries v))))
      ((%py-tuple-is v) (not (null? (%py-tuple-elems v))))
      ((%py-arr-is v) (not (null? (%py-arr-el v))))
      ((%py-mv-is v) (< 0 (%py-mv-len v)))
      ((%py-dq-is v) (not (null? (%py-dq-el v))))
      ((%py-obj-is v)
        (let ((b (%py-dunder v "__bool__")))
          (if (not (null? b))
            (%py-truthy (b))
            (let ((l (%py-dunder v "__len__")))
              (if (null? l) #t (not (= (l) 0)))))))
      ((%py-class-is v) #t)
      (#t (not (= v 0))))))

(def %py-bool-ctor
  (fn (_ . a) (if (null? a) #f (%py-truthy (first a)))))

; str() IS THE PYTHON-FACING DOOR and answers a str; %py-str under it is the
; INTERNAL one and answers a platform string, which is what its nineteen other
; callers want (they are building error messages with `Str8 append`).  Only
; this door crosses back.
;
; A str ARGUMENT IS RETURNED AS IT CAME, never round-tripped: str(s) on a
; NUL-bearing s would otherwise go out through a platform string and refuse.
(def %py-str-ctor
  (fn (_ . a)
    (match
      ((null? a) (%py-str-new ()))
      ((null? (rest a))
        (let ((v (first a)))
          (if (%py-str-is v) v (%py-str-of-x (%py-str v)))))
      (#t (%py-str-decode a)))))

; str(b, encoding[, errors]) decodes a buffer -- bytes, a bytearray, an array
; or a view of one -- through the same codec bytes.decode reads, with the same
; two arguments and the same three error handlers.
(def %py-str-decode
  (fn (_ a)
    (let ((v (%py-native-of (first a))))
      (match
        ((> (%py-length a) 3)
          (Err raise (lit type)
            (Str8 append "str expected at most 3 arguments, got " (%py-str (%py-length a)))
            ()))
        ((%py-str-is v) (Err raise (lit type) "decoding str is not supported" ()))
        ((%py-buffer? v)
          (%py-str-new
            (%ps-decode-as (%py-buffer-bytes v) (%py-codec-arg (rest a) 0 "utf-8")
              (%py-codec-arg (rest a) 1 "strict"))))
        (#t
          (Err raise (lit type)
            (Str8 append "decoding to str: need a bytes-like object, "
              (Str8 append (%py-class-name (%py-type-of v)) " found"))
            ()))))))

; A constructor or __init__ that takes at most one argument refuses a second, in
; CPython's words.
(def %py-at-most-one!
  (fn (_ cname args)
    (if (if (null? args) #t (null? (rest args)))
      ()
      (Err raise (lit type)
        (Str8 append cname
          (Str8 append " expected at most 1 argument, got " (%py-str (%py-length args))))
        ()))))

; bytearray and deque say it their own way: bytearray() takes at most 3 arguments
; (4 given).
(def %py-takes-at-most!
  (fn (_ cname limit n)
    (if (> n limit)
      (Err raise (lit type)
        (Str8 append cname
          (Str8 append "() takes at most "
            (Str8 append (%py-str limit)
              (Str8 append " arguments (" (Str8 append (%py-str n) " given)")))))
        ())
      ())))

(def %py-list-ctor
  (fn (_ . a)
    (%seq (%py-at-most-one! "list" a)
      (if (null? a) (%py-list-new ()) (%py-mklist-of (first a))))))

(def %py-dict-copy
  (fn (self es)
    (if (null? es)
      ()
      (pair (pair (first (first es)) (rest (first es))) (self (rest es))))))

(def %py-dict-ctor
  (fn (_ . a)
    (if (null? a)
      (%py-dict-new ())
      (let ((m (%seq (%py-at-most-one! "dict" a) (%py-dict-arg (first a)))))
        (if (%py-dict-is m)
          ; a COPY, with fresh entry pairs: dict(d) in Python is a new dict, and
          ; sharing the pairs would make a store into one visible in the other
          (%py-dict-new (%py-dict-copy (%py-dict-entries m)))
          ; any other iterable is a sequence of (key, value) pairs
          (%py-dict-new (%py-pairs-of (%py-iter-elems m) ())))))))
; dict(a=1) and d.update(a=1): the keywords ARE the entries
; dict(a=1) MAKES A str KEY.  A keyword name is the platform's string -- it
; came off the call syntax -- and a dict's keys are Python values, so it
; crosses over here.  Left bare the entry was still findable by another bare
; one, which is why this showed up as a repr (`{colour: 'red'}`, the key with
; no quotes) rather than as a lookup failure.
(def %py-dict-kwargs
  (fn (_ kws)
    (def go
      (fn (self l acc)
        (if (null? l) (%py-reverse acc)
          (self (rest l)
            (pair (pair (%py-str-of-x (first (first l))) (rest (first l))) acc)))))
    (go kws ())))

(def %py-tuple-ctor
  (fn (_ . a)
    (%seq (%py-at-most-one! "tuple" a)
      (if (null? a) (%py-tuple-new ()) (%py-tuple-new (%py-iter-elems (first a)))))))

(def %py-type-ctor
  (fn (_ . a)
    (if (if (null? a) #t (not (null? (rest a))))
      (Err raise (lit type) "type() takes 1 argument here" ())
      (%py-type-of (first a)))))

(%py-sweep!)
; --- the class objects -------------------------------------------------------
; int before bool, because bool derives from it.

(%py-sweep!)
; --- int.to_bytes and int.from_bytes ------------------------------------------
; Both take byteorder as "big" or "little" and a keyword-only signed flag;
; since 3.11 to_bytes defaults to one big-endian byte and from_bytes to big.
; The arithmetic is the tower's, so a value past the machine word is an
; ordinary int here as it is in Python.

; The two byteorder spellings as code points, built once.  The argument is
; compared as code points rather than converted to a platform string: the
; conversion costs more objects than the whole conversion below does.
(def %py-int-cps-little (%ps-of-x "little"))
(def %py-int-cps-big (%ps-of-x "big"))

; The platform string "big" or "little", or the ValueError Python raises.
(def %py-int-byteorder
  (fn (_ v)
    (match
      ((str? v) v)
      ((not (%py-str-is v)) (Err raise (lit type) "byteorder must be str" ()))
      ((%pb-eq? (%py-str-cps v) %py-int-cps-little) "little")
      ((%pb-eq? (%py-str-cps v) %py-int-cps-big) "big")
      (#t (Err raise (lit value) "byteorder must be either 'little' or 'big'" ())))))

(def %py-int-overflow
  (fn (_ msg) (Err raise (lit overflow) msg ())))

; Six bytes per division.  A division of a value past the machine word runs
; in the tower's bigint code and allocates tens of thousands of objects, so
; the value is divided by 2^48 at a time and the remainder, a fixnum, gives
; up its bytes with fixnum arithmetic; nothing here raises 2 to a power.
(def %py-int-pow256
  (list 1 256 65536 16777216 4294967296 1099511627776 281474976710656))

; w bytes of the fixnum r, in front of acc: big-endian, since each byte
; peeled is less significant than the one placed before it.
(def %py-int-fix-bytes
  (fn (self r w acc)
    (if (eq? w 0) acc
      (self (Num quotient r 256) (- w 1) (pair (% r 256) acc)))))

; (leftover . bytes): the nb low bytes of a non-negative v, big-endian, and
; what remains of v above them -- zero when they hold it.
(def %py-int-split
  (fn (_ v nb)
    (def go
      (fn (self v k acc)
        (if (eq? k 0)
          (pair v acc)
          (let ((w (if (< k 6) k 6)))
            (let ((d (List ref w %py-int-pow256)))
              (self (Num quotient v d) (- k w) (%py-int-fix-bytes (% v d) w acc)))))))
    (go v nb ())))

(def %py-int-invert
  (fn (self bs acc)
    (if (null? bs) (List reverse acc) (self (rest bs) (pair (- 255 (first bs)) acc)))))

; The nb bytes of n in the given order, or the OverflowError Python raises
; when they cannot hold it.  A negative value goes through its one's
; complement: -n - 1 is non-negative, and inverting every byte of it gives
; the two's complement bytes without a power of two to compute.
(def %py-int-encode
  (fn (_ n nb order signed)
    (match
      ((if signed #f (< n 0))
        (%py-int-overflow "can't convert negative int to unsigned"))
      ((if (= nb 0) (not (= n 0)) #f)
        (%py-int-overflow "int too big to convert"))
      (#t
        (let ((neg (< n 0)))
          (let ((sp (%py-int-split (if neg (- (- 0 n) 1) n) nb)))
            ; a signed value also keeps its top bit clear
            (if (if (not (= (first sp) 0)) #t
                  (if (if signed (> nb 0) #f) (>= (first (rest sp)) 128) #f))
              (%py-int-overflow "int too big to convert")
              (let ((big (if neg (%py-int-invert (rest sp) ()) (rest sp))))
                (if (Str8 =? order "little") (List reverse big) big)))))))))

(def %py-int-length
  (fn (_ v)
    (let ((n (%py-boolnorm v)))
      (if (not (eq? (%py-num-kind n) (lit int)))
        (Err raise (lit type) "'length' must be an integer" ())
        (if (< n 0)
          (Err raise (lit value) "length argument must be non-negative" ())
          n)))))

(def %py-int-to-bytes
  (%py-sig!
    (fn (_ self . more)
      (let ((n (%py-boolnorm (%py-native-of self)))
            (nb (%py-int-length (%py-opt more 0 1)))
            (order (%py-int-byteorder (%py-opt more 1 "big")))
            (signed (%py-truthy (%py-kwonly more "signed" #f))))
        (%py-bytes-new (%py-int-encode n nb order signed))))
    "to_bytes" (list "self" "length" "byteorder") 1 #f () (list "signed")))

; A bytes-like value's bytes, or any iterable of ints in range, as
; from_bytes takes them.
(def %py-int-bytes-arg
  (fn (_ v)
    (if (%py-bytes-is v)
      (%py-bytes-list v)
      (%py-bytes-of-codes (%py-iter-elems v) ()))))

(def %py-int-mod6 (fn (self k) (if (< k 6) k (self (- k 6)))))

; k big-endian bytes into the fixnum v.
(def %py-int-fix-join
  (fn (self bs k v)
    (if (eq? k 0) v (self (rest bs) (- k 1) (+ (* v 256) (first bs))))))

; The value of big-endian bytes: a first chunk of the odd few, then one
; multiply and one add per six.
(def %py-int-join
  (fn (_ bs)
    (def go
      (fn (self bs acc)
        (if (null? bs) acc
          (self (%py-drop bs 6) (+ (* acc 281474976710656) (%py-int-fix-join bs 6 0))))))
    (let ((w (%py-int-mod6 (List length bs))))
      (if (eq? w 0) (go bs 0) (go (%py-drop bs w) (%py-int-fix-join bs w 0))))))

(def %py-int-from-bytes
  (%py-sig!
    (fn (_ cls bs . more)
      (let ((codes (%py-int-bytes-arg bs))
            (order (%py-int-byteorder (%py-opt more 0 "big")))
            (signed (%py-truthy (%py-kwonly more "signed" #f))))
        (let ((big (if (Str8 =? order "little") (List reverse codes) codes)))
          (if (if signed (if (null? big) #f (>= (first big) 128)) #f)
            ; a set top bit is a negative: the inverted bytes are its one's
            ; complement, and the value is one less than that, negated
            (- (- 0 (%py-int-join (%py-int-invert big ()))) 1)
            (%py-int-join big)))))
    "from_bytes" (list "cls" "bytes" "byteorder") 2 #f () (list "signed")))

(def %py-cls-int
  (%py-class-new "int" %py-cls-object
    (list (pair "%ctor" %py-int-ctor)
          (pair "to_bytes" %py-int-to-bytes)
          ; a classmethod, as in Python: int.from_bytes and (5).from_bytes
          ; both bind the class
          (pair "from_bytes" (%py-desc-new (lit classmethod) %py-int-from-bytes)))
    "int"))

; An int's attribute is a method of the int class bound to the value -- a
; classmethod binds the class -- or Python's AttributeError.
(def %py-int-attr
  (fn (_ v name)
    (let ((m (%py-method-find %py-cls-int name)))
      (match
        ((null? m)
          (Err raise (lit attribute)
            (Str8 append "'int' object has no attribute '" (Str8 append name "'")) ()))
        ((%py-desc-is m)
          (if (eq? (%py-desc-kind m) (lit classmethod))
            (%py-bound-new (%py-desc-fn m) %py-cls-int)
            (%py-desc-fn m)))
        (#t (%py-bound-new m v))))))
(def %py-cls-bool
  (%py-class-new "bool" %py-cls-int
    (list (pair "%final" #t) (pair "%ctor" %py-bool-ctor)) "bool"))
(def %py-cls-float
  (%py-class-new "float" %py-cls-object (list (pair "%ctor" %py-float-ctor)) "float"))
(def %py-cls-complex
  (%py-class-new "complex" %py-cls-object (list (pair "%ctor" %py-complex-ctor)) "complex"))
(def %py-str-methods
  (list
    (pair "%ctor" %py-str-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-str
  (%py-class-new "str" %py-cls-object %py-str-methods "str"))

(%py-sweep!)
; --- the __init__ rows of list, set and dict -----------------------------------
; Each fills the value an instance carries from the arguments, and each carries
; a signature, so `super().__init__(*args, **kwargs)` reaches it.

; The TypeError an __init__ read off a builtin class raises for a receiver of
; another type, in CPython's words.
(def %py-init-receiver!
  (fn (_ cname self)
    (Err raise (lit type)
      (Str8 append (Str8 append "descriptor '__init__' requires a '" cname)
        (Str8 append "' object but received a '"
          (Str8 append (%py-class-name (%py-type-of self)) "'")))
      ())))

; The positional arguments an __init__ row was given, checked as CPython checks
; them: keywords are refused unless the builtin takes them, then more than one
; positional argument is.
(def %py-init-pos!
  (fn (_ cname more keywords?)
    (let ((pos (%py-args-strip-kw more)))
      (if (if keywords? #f (not (null? (%py-dict-entries (%py-kwargs-of more)))))
        (Err raise (lit type) (Str8 append cname "() takes no keyword arguments") ())
        (%seq (%py-at-most-one! cname pos) pos)))))

; list.__init__ replaces the contents with an iterable's, or empties the list.
(def %py-list-init
  (%py-sig!
    (fn (_ self . more)
      (if (not (%py-list-is (%py-native-of self)))
        (%py-init-receiver! "list" self)
        (let ((pos (%py-init-pos! "list" more #f)))
          (%seq (%py-list-set! self (if (null? pos) () (%py-iter-elems (first pos)))) ()))))
    "__init__" (list "self") 1 #t "kwargs" () #t))

; set.__init__ replaces the carried set's contents in the same way.
(def %py-set-init
  (%py-sig!
    (fn (_ self . more)
      (let ((s (%py-native-of self)))
        (if (if (%py-set-is s) (%py-set-frozen? s) #t)
          (%py-init-receiver! "set" self)
          (let ((pos (%py-init-pos! "set" more #f)))
            (%seq (%py-set-set! s (%py-set-elems (apply %py-set-ctor pos))) ())))))
    "__init__" (list "self") 1 #t "kwargs" () #t))

; THE BUILTIN TYPE OBJECT CARRIES THE PROTOCOL, which is what makes
; `class mylist(list)` work without teaching seventy dispatch sites about
; wrappers: a subclass inherits these through the base walk that was already
; there, so every `(%py-dunder obj "__len__")` in this file finds one.  Each
; reads through %py-native-of, which is the instance's value for a subclass
; and the value itself for a plain list.
(def %py-list-methods
  (list
    (pair "%ctor" %py-list-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__setitem__"  (fn (_ self i v) (%py-setindex (%py-native-of self) i v)))
    (pair "__delitem__"  (fn (_ self i) (%py-delindex (%py-native-of self) i)))
    ; __iter__ answers the list itself; %py-obj-elems takes a non-iterator
    ; answer and iterates it, which is exactly what is wanted here.
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__init__"     %py-list-init)))

; THE LAZY BUILTINS ARE CLASSES IN PYTHON, not functions -- `class mymap(map)`
; is ordinary code, and the corpus writes it.  Each keeps the function it
; always was as its %ctor, so `map(f, xs)` answers exactly what it did; what is
; new is that the name is a CLASS, so it can be named as a base and a subclass
; inherits an iterator's surface: __iter__ answers the value the instance
; carries, and __next__ pulls from it.
(def %py-lazy-methods
  (fn (_ ctor)
    (list
      (pair "%ctor" ctor)
      (pair "__iter__" (fn (_ self) (%py-native-of self)))
      (pair "__next__" (fn (_ self) (%py-next (%py-native-of self)))))))

(def %py-cls-list
  (%py-class-new "list" %py-cls-object %py-list-methods "list"))

; A subclass prints under its own name, T({1, 2}) or T() when empty; set and
; frozenset themselves print as the value does.
(def %py-set-class-repr
  (fn (_ self)
    (let ((s (%py-native-of self)) (cls (%py-type-of self)))
      (match
        ((if (same? cls %py-cls-set) #t (same? cls %py-cls-frozenset)) (%py-repr-of s))
        ((null? (%py-set-elems s)) (Str8 append (%py-class-name cls) "()"))
        (#t
          (Str8 append (%py-class-name cls)
            (Str8 append "("
              (Str8 append (%py-repr-of (%py-set-new #f (%py-set-elems s))) ")"))))))))

; The rows set and frozenset share, read through %py-native-of as the list and
; dict rows are.  An operator answers a plain set or frozenset, as in Python.
; There is no __str__, so print reaches __repr__, a subclass's own included.
(def %py-set-methods
  (fn (_ ctor)
    (list
      (pair "%ctor" ctor)
      (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
      (pair "__iter__"     (fn (_ self) (%py-native-of self)))
      (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
      (pair "__hash__"     (fn (_ self) (%py-hash (%py-native-of self))))
      (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
      (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
      (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
      (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
      (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
      (pair "__or__"       (fn (_ self o) (%py-bitor (%py-native-of self) (%py-native-of o))))
      (pair "__ror__"      (fn (_ self o) (%py-bitor (%py-native-of o) (%py-native-of self))))
      (pair "__and__"      (fn (_ self o) (%py-bitand (%py-native-of self) (%py-native-of o))))
      (pair "__rand__"     (fn (_ self o) (%py-bitand (%py-native-of o) (%py-native-of self))))
      (pair "__sub__"      (fn (_ self o) (%py-sub (%py-native-of self) (%py-native-of o))))
      (pair "__rsub__"     (fn (_ self o) (%py-sub (%py-native-of o) (%py-native-of self))))
      (pair "__xor__"      (fn (_ self o) (%py-bitxor (%py-native-of self) (%py-native-of o))))
      (pair "__rxor__"     (fn (_ self o) (%py-bitxor (%py-native-of o) (%py-native-of self))))
      (pair "__repr__"     %py-set-class-repr))))

; The rows only set carries, since they change the carried set: __init__, and
; the in-place operators, which store their result into it and answer the
; instance, so `t |= s` keeps a subclass instance.  frozenset has none: its `|=`
; answers a new frozenset, as in Python.
(def %py-set-update!
  (fn (_ self s) (%seq (%py-set-set! (%py-native-of self) (%py-set-elems s)) self)))
(def %py-set-mutating-methods
  (list
    (pair "__init__" %py-set-init)
    (pair "__ior__"  (fn (_ self o) (%py-set-update! self (%py-bitor (%py-native-of self) (%py-native-of o)))))
    (pair "__iand__" (fn (_ self o) (%py-set-update! self (%py-bitand (%py-native-of self) (%py-native-of o)))))
    (pair "__isub__" (fn (_ self o) (%py-set-update! self (%py-sub (%py-native-of self) (%py-native-of o)))))
    (pair "__ixor__" (fn (_ self o) (%py-set-update! self (%py-bitxor (%py-native-of self) (%py-native-of o)))))))

(def %py-cls-set
  (%py-class-new "set" %py-cls-object
    (%py-list-cat (%py-set-methods %py-set-ctor) %py-set-mutating-methods) "set"))
(def %py-cls-frozenset
  (%py-class-new "frozenset" %py-cls-object (%py-set-methods %py-frozenset-ctor) "frozenset"))

; dict.__init__ merges a mapping or an iterable of pairs, then the keywords, into
; the dict an instance carries, as in Python; what is there already stays.
(def %py-dict-init
  (%py-sig!
    (fn (_ self . more)
      (let ((d (%py-native-of self)))
        (if (not (%py-dict-is d))
          (%py-init-receiver! "dict" self)
          (let ((pos (%py-init-pos! "dict" more #t)))
            (%seq
              (if (null? pos) () (%py-dict-merge! d (first pos)))
              (%seq (%py-dict-merge! d (%py-kwargs-of more)) ()))))))
    "__init__" (list "self") 1 #t "kwargs" () #t))

(def %py-dict-methods
  (list
    (pair "%ctor" %py-dict-ctor)
    (pair "__init__"     %py-dict-init)
    (pair "fromkeys"     (%py-desc-new (lit classmethod) %py-dict-fromkeys))
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__setitem__"  (fn (_ self i v) (%py-setindex (%py-native-of self) i v)))
    (pair "__delitem__"  (fn (_ self i) (%py-delindex (%py-native-of self) i)))))

(def %py-cls-dict
  (%py-class-new "dict" %py-cls-object %py-dict-methods "dict"))
(def %py-tuple-methods
  (list
    (pair "%ctor" %py-tuple-ctor)
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-tuple
  (%py-class-new "tuple" %py-cls-object %py-tuple-methods "tuple"))
(def %py-cls-type
  (%py-class-new "type" %py-cls-object (list (pair "%ctor" %py-type-ctor)) "type"))

; The types a callable, a generator and a bound method answer to.  CPython
; separates a def from a builtin, and the seventh signature field is what
; tells them apart here: a def or a lambda records one, a builtin does not.
(def %py-cls-function (%py-class-new "function" %py-cls-object () "function"))
(def %py-cls-builtin-function
  (%py-class-new "builtin_function_or_method" %py-cls-object ()
    "builtin_function_or_method"))
(def %py-cls-generator (%py-class-new "generator" %py-cls-object () "generator"))
(def %py-cls-method (%py-class-new "method" %py-cls-object () "method"))
(def %py-cls-NoneType
  (%py-class-new "NoneType" %py-cls-object () "NoneType"))

; types.SimpleNamespace: an object that is only its attributes.  A mapping
; given first sets them, then the keywords do; it prints them in the order they
; were set, as namespace(a=1, b=2) -- a subclass under its own name -- and two
; are equal when they hold the same names with equal values, in any order.
(def %py-cls-SimpleNamespace ())

(def %py-ns-fill
  (fn (self o rows)
    (if (null? rows)
      ()
      (if (%py-str-is (first (first rows)))
        (%seq
          (%py-obj-set-attrs! o
            (%py-attr-put (%py-obj-attrs o) (%py-text->x (first (first rows)))
              (rest (first rows))))
          (self o (rest rows)))
        (Err raise (lit type) "keywords must be strings" ())))))

(def %py-ns-init
  (fn (_ o . more)
    (let ((pos (%py-args-strip-kw more)))
      (%seq
        (if (null? pos) () (%py-ns-fill o (%py-dict-entries (%py-dict-ctor (first pos)))))
        (%seq (%py-ns-fill o (%py-dict-entries (%py-kwargs-of more))) ())))))

(def %py-ns-body
  (fn (self rows lead acc)
    (if (null? rows)
      acc
      (self (rest rows) ", "
        (Str8 append acc
          (Str8 append lead
            (Str8 append (%py-text->x (first (first rows)))
              (Str8 append "=" (%py-repr-of (rest (first rows)))))))))))

(def %py-ns-repr
  (fn (_ o)
    (let ((cls (%py-obj-class o)))
      (Str8 append (if (same? cls %py-cls-SimpleNamespace) "namespace" (%py-class-name cls))
        (Str8 append "("
          (Str8 append (%py-ns-body (%py-attr-entries (%py-obj-attrs o)) "" "") ")"))))))

(def %py-ns-eq
  (fn (_ o other)
    (if (if (%py-obj-is other) (%py-subclass? (%py-obj-class other) %py-cls-SimpleNamespace) #f)
      (%py-eq (%py-dict-new (%py-attr-entries (%py-obj-attrs o)))
              (%py-dict-new (%py-attr-entries (%py-obj-attrs other))))
      #f)))

(set! %py-cls-SimpleNamespace
  (%py-class-new "SimpleNamespace" %py-cls-object
    (list
      (pair "__init__" (%py-sig! %py-ns-init "__init__" (list "self") 1 #t "kwargs" () #t))
      (pair "__repr__" %py-ns-repr)
      (pair "__str__" %py-ns-repr)
      (pair "__eq__" %py-ns-eq))
    "types.SimpleNamespace"))

; bytes(...) -- from a str and its encoding, from a list of ints, from a count
; (that many zero bytes), or from something already bytes.  The type object
; makes `bytes` a name and gives type(b'a') something to answer.
(def %py-bytes-ctor
  (fn (_ . args)
    (if (null? args)
      (%py-bytes-new ())
      (let ((v (%py-bytes-source "bytes" args)))
        (match
          ((same? v %py-dflt) (%py-bytes-new ()))
          ; bytes(bytearray(b'x')) is a bytes, and a bytes of its own -- this
          ; is one of the two places the strict test earns its keep.
          ((%py-bytes-only? v) v)
          ((%py-bytes-is v) (%py-bytes-new (%py-bytes-list v)))
          ((%py-list? v)
            (%py-bytes-new (%py-bytes-of-codes (%py-list-elems v) ())))
          ((%py-tuple-is v)
            (%py-bytes-new (%py-bytes-of-codes (%py-tuple-elems v) ())))
          ; an array or a view hands over its bytes, which is what it is
          ((%py-buffer? v) (%py-bytes-new (%py-buffer-bytes v)))
          ((%py-bytes-count? v) (%py-bytes-new (%py-bytes-zeros v ())))
          ; a subclass instance converts as the value it carries
          ((if (%py-obj-is v) (not (null? (%py-obj-native v))) #f)
            (%py-bytes-ctor (%py-obj-native v)))
          ; any other iterable of ints, which is what bytearray already took;
          ; a value that is not one refuses in CPython's words
          (#t
            (%py-bytes-new
              (%py-bytes-of-codes
                (%py-iter-elems v (%py-bytes-refusal v "bytes")) ()))))))))

; A NUL BYTE CANNOT BE CARRIED HERE, and saying so is better than answering a
; short bytes.  A string on this platform is a C STRING BY AN ENGINE GUARANTEE
; -- `str/nul-terminated`, in docs/engine-contract.md -- so it ends at its
; first NUL and there is no argument that changes that.  The limit is the
; string layer's, not this constructor's; what this constructor does is refuse
; to hide it.
;
; EVERY SPELLING REFUSES, with this sentence: the literals `'\x00'` and
; `b'\x00'` in python/tokens.x, chr(0) and so `'%c' % 0` in %py-chr, and both
; arms here.  docs/nul-and-the-string-layer.md is the decision and its cost --
; including why carrying a NUL in bytes ALONE would move the silent loss to
; .decode() rather than remove it.
; A ZERO IS A BYTE LIKE ANY OTHER NOW.  This used to refuse it -- and so did
; bytes(n), chr(0) and every literal -- because the payload was a string that
; would have ended there.  The payload is a byte list; the only rule left is
; Python's own, that a byte is in range(0, 256).
;
; Anything but an int is the TypeError Python gives, raised before it reaches a
; comparison that has no answer for it.
(def %py-bytes-of-codes
  (fn (self codes acc)
    (if (null? codes)
      (List reverse acc)
      (let ((c (%py-boolnorm (first codes))))
        (match
          ((not (eq? (%py-num-kind c) (lit int)))
            (Err raise (lit type)
              (Str8 append (Str8 append "'" (%py-class-name (%py-type-of c)))
                "' object cannot be interpreted as an integer") ()))
          ((if (< c 0) #t (> c 255))
            (Err raise (lit value) "bytes must be in range(0, 256)" ()))
          (#t (self (rest codes) (pair c acc))))))))

; THE COUNT IS VALIDATED BEFORE THE BYTES ARE BUILT, and negative is its own
; answer rather than a share of zero's.  Measured, CPython 3.14.7: bytes(0) is
; b'', bytes(-1) is ValueError("negative count").  A positive count asks for
; that many NUL bytes, and now gets them.
; A count past the machine word is Python's OverflowError, said before a
; single zero is built.
(def %py-index-max (- (Num expt 2 63) 1))
(def %py-bytes-zeros
  (fn (_ n0 acc)
    (def go (fn (self k acc) (if (= k 0) acc (self (- k 1) (pair 0 acc)))))
    (let ((n (%py-boolnorm n0)))
      (match
        ((< n 0) (Err raise (lit value) "negative count" ()))
        ((> n %py-index-max)
          (Err raise (lit overflow) "cannot fit 'int' into an index-sized integer" ()))
        (#t (go n acc))))))

(def %py-bytes-methods
  (list
    (pair "%ctor" (%py-sig! %py-bytes-ctor "bytes" (list "source" "encoding" "errors") 0 #f))
    (pair "fromhex"      (%py-desc-new (lit classmethod) %py-bytes-fromhex))
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      (fn (_ self) (%py-str (%py-native-of self))))
    (pair "__repr__"     (fn (_ self) (%py-repr-of (%py-native-of self))))
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-bytes
  (%py-class-new "bytes" %py-cls-object %py-bytes-methods "bytes"))

; A subclass prints under its own name, BA(b'xy'), as CPython's bytearray repr
; does; bytearray itself prints as the value does.
(def %py-bytearray-class-repr
  (fn (_ self)
    (let ((cls (%py-type-of self)))
      (if (same? cls %py-cls-bytearray)
        (%py-repr-of (%py-native-of self))
        (Str8 append (%py-class-name cls)
          (Str8 append "("
            (Str8 append (%py-bytes-repr (%py-bytes-list (%py-native-of self))) ")")))))))

; bytearray.__init__(source, encoding, errors) replaces the contents with what
; bytearray() builds from the same arguments.  Its signature names the three, so
; they can be given by keyword and pass through super().
(def %py-bytearray-init
  (%py-sig!
    (fn (_ self . more)
      (let ((b (%py-native-of self)))
        (if (not (%py-barr-is b))
          (%py-init-receiver! "bytearray" self)
          (%seq (%py-barr-set! b (%py-bytes-list (apply %py-bytearray-ctor more))) ()))))
    "__init__" (list "self" "source" "encoding" "errors") 1 #f () () #t))

(def %py-bytearray-methods
  (list
    (pair "%ctor"
      (%py-sig! %py-bytearray-ctor "bytearray" (list "source" "encoding" "errors") 0 #f))
    (pair "__init__"     %py-bytearray-init)
    (pair "fromhex"      (%py-desc-new (lit classmethod) %py-bytes-fromhex))
    (pair "__len__"      (fn (_ self) (%py-len (%py-native-of self))))
    (pair "__getitem__"  (fn (_ self i) (%py-index (%py-native-of self) i)))
    (pair "__iter__"     (fn (_ self) (%py-native-of self)))
    (pair "__contains__" (fn (_ self x) (%py-in x (%py-native-of self))))
    (pair "__eq__"       (fn (_ self o) (%py-eq (%py-native-of self) (%py-native-of o))))
    (pair "__lt__"       (fn (_ self o) (%py-lt (%py-native-of self) (%py-native-of o))))
    (pair "__gt__"       (fn (_ self o) (%py-gt (%py-native-of self) (%py-native-of o))))
    (pair "__le__"       (fn (_ self o) (%py-le (%py-native-of self) (%py-native-of o))))
    (pair "__ge__"       (fn (_ self o) (%py-ge (%py-native-of self) (%py-native-of o))))
    (pair "__str__"      %py-bytearray-class-repr)
    (pair "__repr__"     %py-bytearray-class-repr)
    (pair "__add__"      (fn (_ self o) (%py-add (%py-native-of self) (%py-native-of o))))))

(def %py-cls-bytearray
  (%py-class-new "bytearray" %py-cls-object %py-bytearray-methods "bytearray"))

(def %py-type-of
  ; ELEVEN ARMS, so a match: the class a value answers to, asked once per
  ; kind.  bool is checked before int because True is an int in this runtime
  ; as it is in Python, and the numeric kinds are read from one place at the
  ; end rather than re-asked per arm.
  (fn (_ v)
    (match
      ((eq? v #t) %py-cls-bool)
      ((eq? v #f) %py-cls-bool)
      ((null? v) %py-cls-NoneType)
      ((%py-barr-is v) %py-cls-bytearray)
      ((%py-bytes-is v) %py-cls-bytes)
      ((%py-str-is v) %py-cls-str)
      ((%py-list-is v) %py-cls-list)
      ((%py-set-is v) (if (%py-set-frozen? v) %py-cls-frozenset %py-cls-set))
      ((%py-dict-is v) %py-cls-dict)
      ((%py-tuple-is v) %py-cls-tuple)
      ((%py-io-is v) (if (%py-io-text? v) %py-cls-StringIO %py-cls-BytesIO))
      ((%py-arr-is v) %py-cls-array)
      ((%py-mv-is v) %py-cls-memoryview)
      ((%py-sl-is v) %py-cls-slice)
      ((%py-dq-is v) %py-cls-deque)
      ((%py-obj-is v) (%py-obj-class v))
      ((%py-class-is v) %py-cls-type)
      ((%py-gen-is v) %py-cls-generator)
      ((%py-bound-is v) %py-cls-method)
      ((%py-fn-is v) (if (%py-user-fn? v) %py-cls-function %py-cls-builtin-function))
      ; an error the runtime raised by tag is an instance of the class the
      ; tag names, as far as type() can tell
      ((Err err? v) (%py-exc-class-of v))
      (#t
        (let ((k (%py-num-kind v)))
          (match
            ((eq? k (lit int)) %py-cls-int)
            ((eq? k (lit float)) %py-cls-float)
            ((eq? k (lit complex)) %py-cls-complex)
            (#t (Err raise (lit type) "type: unsupported value"))))))))

; isinstance walks the base chain with the same %py-subclass? the exception
; matcher uses, so user classes, user exceptions and builtins all answer from
; one definition.  The tuple form is Python's "any of these".
(def %py-isinstance-any ())
(set! %py-isinstance-any
  (fn (self v clss)
    (if (null? clss)
      #f
      (if (%py-isinstance v (first clss)) #t (self v (rest clss))))))

(def %py-isinstance
  (fn (_ v cls)
    (if (%py-tuple-is cls)
      (%py-isinstance-any v (%py-tuple-elems cls))
      (if (not (%py-class-is cls))
        (Err raise (lit type)
          "isinstance() arg 2 must be a type or tuple of types" ())
        (%py-subclass? (%py-type-of v) cls)))))

(%py-sweep!)
; --- Slicing -----------------------------------------------------------------
;
; Python's slice rules, stated once and used by str, list and tuple:
;
;   - a missing step is 1, and step 0 is a ValueError
;   - negative indices count from the end, AFTER which anything still out of
;     range CLAMPS rather than raising -- `lst[1:100]` answers what is there,
;     which is the deliberate difference between slicing and indexing
;   - a negative step defaults start to the last element and stop to "before
;     the first", which is how 'hello'[::-1] reverses
;
; The walk collects INDICES, then each type maps them its own way: a sequence
; through List ref over its element list, a string through one-character subs
; joined at the end.

(def %py-sl-adj
  (fn (_ v len step lo hi)
    (let ((a (if (< v 0) (+ v len) v)))
      (if (< a lo) lo (if (> a hi) hi a)))))

(def %py-sl-bounds
  (fn (_ len start stop step)
    (if (> step 0)
      (pair
        (if (null? start) 0 (%py-sl-adj start len step 0 len))
        (if (null? stop) len (%py-sl-adj stop len step 0 len)))
      (pair
        (if (null? start) (- len 1) (%py-sl-adj start len step (- 0 1) (- len 1)))
        (if (null? stop) (- 0 1) (%py-sl-adj stop len step (- 0 1) (- len 1)))))))

(def %py-sl-idxs
  (fn (self i stop step acc)
    (if (if (> step 0) (>= i stop) (<= i stop))
      (%py-reverse acc)
      (self (+ i step) stop step (pair i acc)))))

(def %py-slice-idxs
  (fn (_ len start stop step)
    (let ((b (%py-sl-bounds len start stop step)))
      (%py-sl-idxs (first b) (rest b) step ()))))

(def %py-sl-pick
  (fn (self elems idxs acc)
    (if (null? idxs)
      (%py-reverse acc)
      (self elems (rest idxs) (pair (List ref (first idxs) elems) acc)))))

(def %py-sl-chars
  (fn (self str idxs acc)
    (if (null? idxs)
      (%py-reverse acc)
      (self str (rest idxs) (pair (Str sub (first idxs) 1 str) acc)))))

(%py-sweep!)
; --- slice, the object a program can hold ------------------------------------
;
; Three values and nothing else: start, stop and step, each None where the
; subscript left it out.  A sequence never needs one -- the parser hands the
; three parts straight to %py-slice above -- but a CLASS does: `a[1:2:3]` on an
; object with a __getitem__ is a call with one argument, and that argument is
; this.  A program can build one itself, and ask it what it means for a length.
(def %py-sl ())
(def %py-sl-new
  (fn (_ start stop step) (%make-instance %py-sl (list start stop step))))
(def %py-sl-is (fn (_ v) (%type? v %py-sl)))
(def %py-sl-start (fn (_ v) (first (first v))))
(def %py-sl-stop (fn (_ v) (first (rest (first v)))))
(def %py-sl-step (fn (_ v) (first (rest (rest (first v))))))

(set! %py-sl
  (%make-type
    "PY-SLICE"
    (list
      (pair (lit write)
        (fn (_ self)
          (display "slice(")
          (%py-repr (%py-sl-start self))
          (display ", ")
          (%py-repr (%py-sl-stop self))
          (display ", ")
          (%py-repr (%py-sl-step self))
          (display ")"))))))

; slice(stop), slice(start, stop), slice(start, stop, step) -- the arguments
; are not checked, since Python does not check them either: slice("a", None)
; is a slice, and only using it complains.
(def %py-slice-ctor
  (fn (_ . a)
    (match
      ((null? a)
        (Err raise (lit type) "slice expected at least 1 argument, got 0" ()))
      ((null? (rest a)) (%py-sl-new () (first a) ()))
      ((null? (rest (rest a))) (%py-sl-new (first a) (first (rest a)) ()))
      ((null? (rest (rest (rest a))))
        (%py-sl-new (first a) (first (rest a)) (first (rest (rest a)))))
      (#t
        (Err raise (lit type)
          (Str8 append "slice expected at most 3 arguments, got "
            (%py-str (%py-length a))) ())))))

; s.indices(len) resolves the slice against a length: the same clamping the
; sequences get, answered as the triple rather than walked.
(def %py-sl-indices
  (fn (_ v n)
    (match
      ((not (eq? (%py-num-kind (%py-boolnorm n)) (lit int)))
        (Err raise (lit type)
          (Str8 append "'" (Str8 append (%py-class-name (%py-type-of n))
            "' object cannot be interpreted as an integer")) ()))
      ((< n 0) (Err raise (lit value) "length should not be negative" ()))
      (#t
        (let ((st (if (null? (%py-sl-step v)) 1 (%py-sl-step v))))
          (if (= st 0)
            (Err raise (lit value) "slice step cannot be zero" ())
            (let ((b (%py-sl-bounds n (%py-sl-start v) (%py-sl-stop v) st)))
              (%py-tuple-new (list (first b) (rest b) st)))))))))

(def %py-sl-eq
  (fn (_ a b)
    (if (%py-sl-is b)
      (if (%py-truthy (%py-eq (%py-sl-start a) (%py-sl-start b)))
        (if (%py-truthy (%py-eq (%py-sl-stop a) (%py-sl-stop b)))
          (%py-truthy (%py-eq (%py-sl-step a) (%py-sl-step b)))
          #f)
        #f)
      #f)))

(def %py-sl-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "start") (%py-sl-start v))
      ((Str8 =? name "stop") (%py-sl-stop v))
      ((Str8 =? name "step") (%py-sl-step v))
      (#t (%py-class-row-attr %py-cls-slice v name "slice")))))

(def %py-sl-methods
  (list
    (pair "%ctor" %py-slice-ctor)
    (pair "indices" (fn (_ o n) (%py-sl-indices (%py-native-of o) n)))
    (pair "__eq__"
      (fn (_ o other) (%py-sl-eq (%py-native-of o) (%py-native-of other))))
    (pair "start"
      (%py-desc-new (lit property) (fn (_ o) (%py-sl-start (%py-native-of o)))))
    (pair "stop"
      (%py-desc-new (lit property) (fn (_ o) (%py-sl-stop (%py-native-of o)))))
    (pair "step"
      (%py-desc-new (lit property) (fn (_ o) (%py-sl-step (%py-native-of o)))))))

(def %py-cls-slice
  (%py-class-new "slice" %py-cls-object %py-sl-methods "slice"))

(def %py-slice
  (fn (_ obj start stop step)
    (let ((st (if (null? step) 1 step)))
      (match
        ; A CLASS TAKES THE SLICE ITSELF.  Its __getitem__ is a one-argument
        ; call, and the argument is the object above -- which is why the object
        ; exists.
        ((if (%py-obj-is obj)
           (%py-user-fn? (%py-method-find (%py-obj-class obj) "__getitem__"))
           #f)
          ((%py-dunder obj "__getitem__") (%py-sl-new start stop step)))
        ; a deque is indexed but never sliced
        ((%py-dq-is obj)
          (Err raise (lit type) "sequence index must be integer, not 'slice'" ()))
        ((= st 0) (Err raise (lit value) "slice step cannot be zero" ()))
        ((%py-str-is obj)
          (let ((l (%py-str-cps obj)))
            (%py-str-new (%py-sl-pick l (%py-slice-idxs (%pb-len l) start stop st) ()))))
        ((%py-bytes-is obj)
          (let ((l (%py-bytes-list obj)))
            ((if (%py-barr-is obj) %py-barr-new %py-bytes-new)
              (%py-sl-pick l (%py-slice-idxs (%pb-len l) start stop st) ()))))
        ((%py-mv-is obj) (%py-mv-slice obj start stop step))
        ((%py-list-is obj)
          (%py-list-new
            (%py-sl-pick (%py-list-elems obj)
              (%py-slice-idxs (%py-length (%py-list-elems obj)) start stop st) ())))
        ((%py-tuple-is obj)
          (%py-tuple-new
            (%py-sl-pick (%py-tuple-elems obj)
              (%py-slice-idxs (%py-length (%py-tuple-elems obj)) start stop st) ())))
        ; A builtin's subclass slices the value it carries and answers the
        ; builtin's type -- sys.version_info[:2] is a plain tuple -- unless its
        ; class writes a __getitem__ of its own.
        ((if (%py-obj-is obj)
           (if (null? (%py-obj-native obj))
             #f
             (not (%py-user-fn? (%py-method-find (%py-obj-class obj) "__getitem__"))))
           #f)
          (%py-slice (%py-obj-native obj) start stop step))
        ; A DICT IS NOT A SEQUENCE: its subscript is a key lookup, so a slice
        ; there is a key like any other -- and one that is usually missing.
        ((%py-dict? obj) (%py-dget obj (%py-sl-new start stop step)))
        (#t (Err raise (lit type) "unhashable type: 'slice'" ()))))))

(%py-sweep!)
; --- def, whatever the frame depth -------------------------------------------
;
; The REPL's conditional hoists run inside a guard HANDLER, where a plain def
; binds in the handler's frame and vanishes with it.  base/def-global is the
; engine door that defines for the CALLER at any depth; the symbol comes
; quoted, the value evaluated.
(def %py-defg-prim (prim-ref (lit base) (lit def-global)))
(def %py-defg (fn (_ sym v) (%py-defg-prim sym v)))

; Each of these was a bare function until the corpus asked to subclass one.
(def %py-cls-map       (%py-class-new "map"       %py-cls-object (%py-lazy-methods %py-map)       "map"))
(def %py-cls-filter    (%py-class-new "filter"    %py-cls-object (%py-lazy-methods %py-filter)    "filter"))
(def %py-cls-zip       (%py-class-new "zip"       %py-cls-object (%py-lazy-methods %py-zip)       "zip"))
(def %py-cls-enumerate (%py-class-new "enumerate" %py-cls-object (%py-lazy-methods %py-enumerate) "enumerate"))
(def %py-cls-reversed  (%py-class-new "reversed"  %py-cls-object (%py-lazy-methods %py-reversed)  "reversed"))
; NOT EVERY BUILTIN IS AN ACCEPTABLE BASE.  CPython refuses `class X(range)`
; and `class X(bool)` outright -- "type 'range' is not an acceptable base
; type" -- so the marker below says so, under a key no Python name can spell.
(def %py-cls-range
  (%py-class-new "range" %py-cls-object
    (pair (pair "%final" #t) (%py-lazy-methods %py-range)) "range"))
