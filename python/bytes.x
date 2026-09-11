; # x-python -- Python on x-lang
;
; ## python/bytes.x -- the byte sequence, and the algorithms over it
;
; @description Python's bytes and bytearray carry a BYTE LIST; this file is
;   the string library written once more, against one.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY A bytes IS NOT A STRING HERE
;
; A string on this platform is a C string by an engine guarantee --
; `str/nul-terminated` in docs/engine-contract.md -- so it ends at its first
; NUL.  A `bytes` whose job is to carry binary meets a zero byte in the first
; header, digest or length-prefixed frame it is handed.
;
; docs/nul-and-the-string-layer.md used to say the PLATFORM could not carry
; one.  That was wrong, and the platform's own code is the proof:
; `x/codec/zlib.x` copies a byte list into a `(str make)` region through the
; pointer door, and `x/codec/sha256-jit.x` builds "A\0B\0C" the same way --
; its comment reads "NULs INSIDE, so Str8 length reports 1 and the region is
; 5".  Measured here on the same engine: a region written that way answers
; `#\A`, `#\null`, `#\B` to `str byte-ref`.
;
; The true statement is narrower, and it is about a CLASS rather than a
; platform: **Str8 cannot**, because every one of its doors takes a C string.
; Nor can the length of such a region be read back -- `str byte-len` answered
; 1 for the five-byte region above -- so a carrier has to hold its own count,
; which is why zlib.x passes `n` alongside every buffer it makes.
;
; So the carrier is the BYTE LIST: the platform's own answer wherever a
; payload may hold a NUL (`hex encode-bytes`, `base64 encode-bytes`, `socket
; recv-bytes` and `struct pack` all take one).  It carries its own length,
; holds a zero like any other int, and needs no pointer door.
;
; And the price is this file.  Every bytes method used to BE the str method
; on the underlying string, so moving the payload moved all of them here.
; That is the trade the old note declined: ONE implementation over ints,
; rather than a second one that agrees with the first only until a byte is
; zero.
;
; ## SHAPE
;
; Every walk here accumulates and reverses rather than building on the way
; back out.  x has no depth limit on non-tail calls and a bytes is data --
; a 16K frame is an ordinary size for one and a fatal recursion depth for
; the other shape (docs and the spec-crash signatures both say so).

; ONLY tokens, and only for %py-list->string.  Nothing here knows what a
; Python value is -- these are algorithms over ints, and python/types.x
; reaches for them rather than the other way round.
(import python/tokens)

(provide python/bytes
  %pb-of-str %pb->str %pb-nul? %pb-len %pb-ref %pb-sub %pb-cat %pb-repeat
  %pb-eq? %pb-cmp %pb-find %pb-rfind %pb-count %pb-drop %pb-take %pb-starts? %pb-ends? %pb-in?
  %pb-split %pb-rsplit %pb-splitlines %pb-join %pb-replace %pb-strip
  %pb-partition %pb-rpartition %pb-center %pb-ljust %pb-rjust
  %pb-upper %pb-lower %pb-swapcase %pb-capitalize %pb-title
  %pb-isspace %pb-isalpha %pb-isdigit %pb-isalnum %pb-isupper %pb-islower)

(def %pb-code (prim-ref (lit char) (lit ->int)))
(def %pb-char (prim-ref (lit int) (lit ->char)))
(def %pb-bref (prim-ref (lit str) (lit byte-ref)))
(def %pb-blen (prim-ref (lit str) (lit byte-len)))

; --- the two conversions -----------------------------------------------------
;
; A STRING BECOMES BYTES BY ITS BYTES, not by its characters: the source is
; already the platform's byte string, so this reads it with `str byte-ref`
; and never asks the utf-8 layer what a character is.
(def %pb-of-str
  (fn (self s)
    (%pb-of-str-go s (- (%pb-blen s) 1) ())))
(def %pb-of-str-go
  (fn (self s i acc)
    (if (< i 0) acc (self s (- i 1) (pair (%pb-code (%pb-bref s i)) acc)))))

; TRUE WHEN A ZERO IS IN THERE -- the one question the string layer cannot be
; asked politely.
(def %pb-nul?
  (fn (self l) (if (null? l) #f (if (= (first l) 0) #t (self (rest l))))))

; BYTES BACK TO A STRING, and it REFUSES rather than truncates.  Every caller
; wants a value the str layer will hold -- a decode, a float to read, a name
; to compare -- and a silent stop at the first zero is the failure this file
; exists to end.
(def %pb->str
  (fn (self l)
    (if (%pb-nul? l)
      ; THE SAME SENTENCE AS EVERY OTHER CROSSING.  The limit is stated once
      ; wherever it is reached (docs/nul-and-the-string-layer.md), and this was
      ; the one door saying it differently -- so a spec asserting the refusal
      ; matched three crossings and missed this one.
      (Err raise (lit value) "a NUL byte is not representable here" ())
      (%pb->str-go l ""))))
(def %pb->str-go
  (fn (self l acc)
    (if (null? l) acc
      (self (rest l) (Str8 append acc (%py-list->string (list (%pb-char (first l)))))))))

; --- the sequence ------------------------------------------------------------
(def %pb-len (fn (_ l) (List length l)))
(def %pb-ref (fn (_ l i) (List ref i l)))

(def %pb-drop
  (fn (self k l) (if (if (<= k 0) #t (null? l)) l (self (- k 1) (rest l)))))
(def %pb-take
  (fn (self k l acc)
    (if (if (<= k 0) #t (null? l)) (List reverse acc)
      (self (- k 1) (rest l) (pair (first l) acc)))))
(def %pb-sub (fn (_ l i n) (%pb-take n (%pb-drop i l) ())))

; PUSH EACH BYTE OF `l` ONTO `b`, which reverses l against b.  Both callers
; want that: %pb-cat hands it a reversed a, and the accumulating walks hand
; it a forward `new` to land in order once their accumulator is reversed.
(def %pb-onto
  (fn (self l b) (if (null? l) b (self (rest l) (pair (first l) b)))))
(def %pb-cat (fn (_ a b) (%pb-onto (List reverse a) b)))

(def %pb-repeat
  (fn (self l n acc)
    (if (<= n 0) acc (self l (- n 1) (%pb-cat acc l)))))

(def %pb-eq?
  (fn (self a b)
    (if (null? a) (null? b)
      (if (null? b) #f
        (if (= (first a) (first b)) (self (rest a) (rest b)) #f)))))

; -1, 0 or 1, by byte and then by length -- Python's order for bytes.
(def %pb-cmp
  (fn (self a b)
    (match
      ((null? a) (if (null? b) 0 (- 0 1)))
      ((null? b) 1)
      ((= (first a) (first b)) (self (rest a) (rest b)))
      ((< (first a) (first b)) (- 0 1))
      (#t 1))))

; --- search ------------------------------------------------------------------
(def %pb-at?
  (fn (self hay ndl)
    (if (null? ndl) #t
      (if (null? hay) #f
        (if (= (first hay) (first ndl)) (self (rest hay) (rest ndl)) #f)))))

(def %pb-find-go
  (fn (self hay ndl i)
    (if (%pb-at? hay ndl) i
      (if (null? hay) (- 0 1) (self (rest hay) ndl (+ i 1))))))
(def %pb-find (fn (_ hay ndl) (%pb-find-go hay ndl 0)))

(def %pb-rfind-go
  (fn (self hay ndl i best)
    (if (null? hay) best
      (self (rest hay) ndl (+ i 1) (if (%pb-at? hay ndl) i best)))))
(def %pb-rfind (fn (_ hay ndl) (%pb-rfind-go hay ndl 0 (- 0 1))))

; NON-OVERLAPPING, as Python counts: b"aaa".count(b"aa") is 1.  An EMPTY
; needle is found between every pair of bytes and at both ends, which is
; len+1 -- Python says so and every other answer here is a special case
; waiting to be found by a test.
(def %pb-count
  (fn (self hay ndl acc)
    (if (null? ndl) (+ (List length hay) 1)
      (if (null? hay) acc
        (if (%pb-at? hay ndl)
          (self (%pb-drop (List length ndl) hay) ndl (+ acc 1))
          (self (rest hay) ndl acc))))))

(def %pb-starts? (fn (_ l p) (%pb-at? l p)))
(def %pb-ends?
  (fn (_ l p)
    (let ((n (List length l)) (m (List length p)))
      (if (> m n) #f (%pb-at? (%pb-drop (- n m) l) p)))))
(def %pb-in? (fn (_ ndl hay) (>= (%pb-find hay ndl) 0)))

; --- the byte classes --------------------------------------------------------
; ASCII, and only ASCII: a byte is not a character, so `upper` on a byte over
; 127 is that byte.  Python agrees -- bytes.upper() is ASCII-only by
; definition, which is one of the places bytes and str genuinely differ.
(def %pb-upper? (fn (_ c) (if (>= c 65) (<= c 90) #f)))
(def %pb-lower? (fn (_ c) (if (>= c 97) (<= c 122) #f)))
(def %pb-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))
(def %pb-alpha? (fn (_ c) (if (%pb-upper? c) #t (%pb-lower? c))))
(def %pb-space?
  (fn (_ c)
    (match
      ((= c 32) #t)
      ((= c 9) #t)
      ((= c 10) #t)
      ((= c 13) #t)
      ((= c 11) #t)
      (#t (= c 12)))))

(def %pb-map
  (fn (self f l acc)
    (if (null? l) (List reverse acc) (self f (rest l) (pair (f (first l)) acc)))))

(def %pb-up-b (fn (_ c) (if (%pb-lower? c) (- c 32) c)))
(def %pb-down-b (fn (_ c) (if (%pb-upper? c) (+ c 32) c)))
(def %pb-swap-b
  (fn (_ c) (if (%pb-lower? c) (- c 32) (if (%pb-upper? c) (+ c 32) c))))

(def %pb-upper (fn (_ l) (%pb-map %pb-up-b l ())))
(def %pb-lower (fn (_ l) (%pb-map %pb-down-b l ())))
(def %pb-swapcase (fn (_ l) (%pb-map %pb-swap-b l ())))

(def %pb-capitalize
  (fn (_ l)
    (if (null? l) l
      (pair (%pb-up-b (first l)) (%pb-lower (rest l))))))

; A WORD STARTS WHERE A NON-LETTER ENDED, which is Python's rule for title
; and the reason `b"a1b".title()` is `b"A1B"` rather than `b"A1b"`.
(def %pb-title-go
  (fn (self l start acc)
    (if (null? l) (List reverse acc)
      (self (rest l) (not (%pb-alpha? (first l)))
        (pair (if start (%pb-up-b (first l)) (%pb-down-b (first l))) acc)))))
(def %pb-title (fn (_ l) (%pb-title-go l #t ())))

(def %pb-all?
  (fn (self f l) (if (null? l) #t (if (f (first l)) (self f (rest l)) #f))))
(def %pb-any?
  (fn (self f l) (if (null? l) #f (if (f (first l)) #t (self f (rest l))))))

; EMPTY IS FALSE for every one of these, as in Python.
(def %pb-isspace (fn (_ l) (if (null? l) #f (%pb-all? %pb-space? l))))
(def %pb-isalpha (fn (_ l) (if (null? l) #f (%pb-all? %pb-alpha? l))))
(def %pb-isdigit (fn (_ l) (if (null? l) #f (%pb-all? %pb-digit? l))))
(def %pb-alnum? (fn (_ c) (if (%pb-alpha? c) #t (%pb-digit? c))))
(def %pb-isalnum (fn (_ l) (if (null? l) #f (%pb-all? %pb-alnum? l))))
; ISUPPER ASKS TWO THINGS: no lowercase, and at least one letter that IS
; cased.  b"123".isupper() is False in Python for the second reason.
(def %pb-isupper
  (fn (_ l) (if (%pb-any? %pb-upper? l) (not (%pb-any? %pb-lower? l)) #f)))
(def %pb-islower
  (fn (_ l) (if (%pb-any? %pb-lower? l) (not (%pb-any? %pb-upper? l)) #f)))

; --- strip -------------------------------------------------------------------
; A nil `chars` means whitespace; otherwise any byte in the set goes.
(def %pb-inset?
  (fn (self c set) (if (null? set) (%pb-space? c) (%pb-mem? c set))))
(def %pb-mem?
  (fn (self c set)
    (if (null? set) #f (if (= c (first set)) #t (self c (rest set))))))

(def %pb-lstrip-go
  (fn (self l set)
    (if (null? l) l (if (%pb-inset? (first l) set) (self (rest l) set) l))))
(def %pb-strip
  (fn (_ l set left right)
    (let ((a (if left (%pb-lstrip-go l set) l)))
      (if right
        (List reverse (%pb-lstrip-go (List reverse a) set))
        a))))

; --- pad ---------------------------------------------------------------------
; The EXTRA byte goes on the right, which is what Python does and the only
; part of center anyone gets wrong.
(def %pb-fill (fn (_ n c) (%pb-repeat (list c) n ())))
(def %pb-center
  (fn (_ l w c)
    (let ((n (List length l)))
      (if (<= w n) l
        (let ((left (Num quotient (- w n) 2)))
          (%pb-cat (%pb-fill left c) (%pb-cat l (%pb-fill (- (- w n) left) c))))))))
(def %pb-ljust
  (fn (_ l w c)
    (let ((n (List length l))) (if (<= w n) l (%pb-cat l (%pb-fill (- w n) c))))))
(def %pb-rjust
  (fn (_ l w c)
    (let ((n (List length l))) (if (<= w n) l (%pb-cat (%pb-fill (- w n) c) l)))))

; --- split, join, replace ----------------------------------------------------
;
; A nil separator splits on RUNS of whitespace and drops the empties, which
; is a different function from splitting on a byte and is why Python spells
; both `split`.
; A WHITESPACE SPLIT SKIPS RUNS and drops the empties -- and maxsplit counts
; the SPLITS, so once it is spent the REST of the value is one field, trailing
; spaces and all: b"   a   b    ".split(None, 1) is [b'a', b'b    '].  That is
; why it cannot be the separator walk with a counter bolted on; the tail is
; not a field, it is what is left.
(def %pb-ws-skip
  (fn (self l) (if (null? l) l (if (%pb-space? (first l)) (self (rest l)) l))))
(def %pb-ws-field
  (fn (self l acc)
    (if (null? l) (pair (List reverse acc) l)
      (if (%pb-space? (first l)) (pair (List reverse acc) l)
        (self (rest l) (pair (first l) acc))))))
(def %pb-ws-split
  (fn (self l n acc)
    (let ((r (%pb-ws-skip l)))
      (if (null? r)
        (List reverse acc)
        (if (= n 0)
          (List reverse (pair r acc))
          (let ((f (%pb-ws-field r ())))
            (self (rest f) (- n 1) (pair (first f) acc))))))))

(def %pb-sep-split
  (fn (self l sep n cur acc)
    (if (null? l)
      (List reverse (pair (List reverse cur) acc))
      (if (if (= n 0) #f (%pb-at? l sep))
        (self (%pb-drop (List length sep) l) sep (- n 1) () (pair (List reverse cur) acc))
        (self (rest l) sep n (pair (first l) cur) acc)))))

(def %pb-split
  (fn (_ l sep n)
    (if (null? sep) (%pb-ws-split l n ()) (%pb-sep-split l sep n () ()))))

; rsplit is split from the other end, and reversing three times is cheaper to
; READ than a second walk written backwards -- the bytes, each part, and the
; order of the parts.
(def %pb-rsplit
  (fn (_ l sep n)
    (if (null? sep)
      (%pb-ws-split l n ())
      (List reverse (%pb-map-rev (%pb-sep-split (List reverse l) (List reverse sep) n () ()) ())))))
(def %pb-map-rev
  (fn (self ps acc)
    (if (null? ps) (List reverse acc) (self (rest ps) (pair (List reverse (first ps)) acc)))))

; \n, \r and \r\n all end a line, and a trailing one does NOT make an empty
; last part.
; keepends leaves the terminator ON the line it ended, which is the only
; thing the flag changes -- and \r\n counts as one terminator either way.
(def %pb-splitlines-go
  (fn (self l keep cur acc)
    (if (null? l)
      (List reverse (if (null? cur) acc (pair (List reverse cur) acc)))
      (if (= (first l) 13)
        (let ((crlf (%pb-at? (rest l) (list 10))))
          (self (if crlf (rest (rest l)) (rest l)) keep ()
            (pair (List reverse (if keep (if crlf (pair 10 (pair 13 cur)) (pair 13 cur)) cur)) acc)))
        (if (= (first l) 10)
          (self (rest l) keep () (pair (List reverse (if keep (pair 10 cur) cur)) acc))
          (self (rest l) keep (pair (first l) cur) acc))))))
(def %pb-splitlines (fn (_ l keep) (%pb-splitlines-go l keep () ())))

(def %pb-join-go
  (fn (self sep ps acc first?)
    (if (null? ps) acc
      (self sep (rest ps)
        (if first? (first ps) (%pb-cat acc (%pb-cat sep (first ps))))
        #f))))
(def %pb-join (fn (_ sep ps) (%pb-join-go sep ps () #t)))

(def %pb-partition
  (fn (_ l sep)
    (let ((i (%pb-find l sep)))
      (if (< i 0)
        (list l () ())
        (list (%pb-sub l 0 i) sep (%pb-drop (+ i (List length sep)) l))))))
(def %pb-rpartition
  (fn (_ l sep)
    (let ((i (%pb-rfind l sep)))
      (if (< i 0)
        (list () () l)
        (list (%pb-sub l 0 i) sep (%pb-drop (+ i (List length sep)) l))))))

; An EMPTY old is Python's insert-between-every-byte, and at both ends.
(def %pb-replace-go
  (fn (self l old new n acc)
    (if (null? l)
      (List reverse acc)
      (if (if (= n 0) #f (%pb-at? l old))
        (self (%pb-drop (List length old) l) old new (- n 1)
          (%pb-onto new acc))
        (self (rest l) old new n (pair (first l) acc))))))
(def %pb-replace
  (fn (_ l old new n)
    (if (null? old)
      (%pb-cat new (%pb-join-every l new ()))
      (%pb-replace-go l old new n ()))))
(def %pb-join-every
  (fn (self l new acc)
    (if (null? l) (List reverse acc)
      (self (rest l) new (%pb-onto new (pair (first l) acc))))))
