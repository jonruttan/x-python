; # x-python -- Python on x-lang
;
; ## lib/python/_sre.x -- the _sre module
;
; @description The regular-expression matcher that stdlib/re.py compiles
;   for: a backtracking engine over the code points of a str, or the bytes of
;   a bytes, run on a program of nested tuples.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; CPYTHON SPLITS re THE SAME WAY: the parser is Python and the engine is the
; C module _sre.  re.py's parser settles every flag as it reads -- a literal
; under IGNORECASE is already op 13, a ^ under MULTILINE is already kind 1 --
; so the engine reads no flags at all.
;
; ## THE PROGRAM
;
; A node is a tuple whose first item is its op:
;
;     (0 c)               the code point c
;     (1)                 any but a newline        (2)  any at all
;     (3 neg items)       a class: items are flat triples, (0 lo hi) a range,
;                         (1 cat neg) a category; neg inverts the whole class
;     (4 nodes)           a sequence               (5 nodes)  alternatives
;     (6 min max mode n)  a repeat: max -1 is no bound; mode 1 greedy,
;                         0 lazy, 2 possessive
;     (7 g n)             group g around n         (8 g)  a backreference
;     (9 kind)            an assertion at a point: 0 \A or ^, 1 ^ in
;                         MULTILINE, 2 $, 3 $ in MULTILINE, 4 \Z, 5 \b, 6 \B,
;                         7 and 8 \b and \B under ASCII
;     (10 behind neg w n) a lookaround; w is a lookbehind's fixed width
;     (11 n)              an atomic group          (12 g yes no)  (?(g)yes|no)
;     (13 c)              c under IGNORECASE, c folded
;     (14 neg items)      a class under IGNORECASE
;
; A category is 0 \d, 1 \w, 2 \s, and 3 to 5 the same under ASCII.
;
; ## THE ENGINE
;
; Continuation passing: (%sre-m node i k) matches node at i and calls k with
; the position after it, answering k's answer or #f.  A repeat of one
; code point -- a literal, a class, a dot -- counts its run in a loop and backs
; off from the end, so [a-z]+ over a long text costs no depth.  Anything else
; deepens the C stack, and past %sre-depth-max the match raises rather than
; let the stack run out.
;
; The marks are a Vector: slot 1 lastindex, then group g's start and end in
; slots 2g+2 and 2g+3 (-1 unset).  A group sets its marks when it closes and restores them if what
; follows fails, so a failed branch leaves no capture behind.

(module python/_sre)
(import python/modules PyModule)
(import python/core
  python-bytes-is python-bytes-list python-module-new python-str-cps python-str-is
  python-tuple-elems python-tuple-is python-tuple-new)
(import x/core/doors int+ int- int* int< int= obj-ref obj-set!)
(import x/type/vector)

; --- the program, from re.py's tuples --------------------------------------

(def %sre-cvt
  (fn (self v)
    (if (python-tuple-is v) (List map (fn (_ e) (self e)) (python-tuple-elems v)) v)))

; --- code points: case and the categories ------------------------------------
;
; The case rules are ASCII, Latin-1 and the basic Greek and Cyrillic blocks:
; enough for the letters a program is likely to fold, and no tables.

(def %sre-lower
  (fn (_ c)
    (match
      ((int< c 65) c)
      ((int< c 91) (int+ c 32))
      ((int< c 192) c)
      ((int< c 223) (if (int= c 215) c (int+ c 32)))
      ((int< c 913) c)
      ((int< c 938) (if (int= c 930) c (int+ c 32)))
      ((int< c 1024) c)
      ((int< c 1040) (int+ c 80))
      ((int< c 1072) (int+ c 32))
      (#t c))))
(def %sre-upper
  (fn (_ c)
    (match
      ((int< c 97) c)
      ((int< c 123) (int- c 32))
      ((int< c 224) c)
      ((int< c 255) (if (int= c 247) c (int- c 32)))
      ((int< c 945) c)
      ((int< c 970) (if (int= c 962) c (int- c 32)))
      ((int< c 1072) c)
      ((int< c 1104) (int- c 32))
      ((int< c 1120) (int- c 80))
      (#t c))))

(def %sre-ascii-digit? (fn (_ c) (if (int< 47 c) (int< c 58) #f)))
(def %sre-ascii-word?
  (fn (_ c)
    (match
      ((int< c 48) #f) ((int< c 58) #t)
      ((int< c 65) #f) ((int< c 91) #t)
      ((int= c 95) #t)
      ((int< c 97) #f) ((int< c 123) #t)
      (#t #f))))
(def %sre-ascii-space?
  (fn (_ c) (if (int= c 32) #t (if (int< 8 c) (int< c 14) #f))))

; Beyond ASCII a letter is one of the blocks the case rules know, or CJK.
(def %sre-word?
  (fn (_ c)
    (match
      ((int< c 128) (%sre-ascii-word? c))
      ((int< c 192) (match ((int= c 170) #t) ((int= c 181) #t) ((int= c 186) #t) (#t #f)))
      ((int< c 256) (match ((int= c 215) #f) ((int= c 247) #f) (#t #t)))
      ((int< c 880) (int< c 592))
      ((int< c 1328) (if (int= c 894) #f (if (int= c 903) #f #t)))
      ((int< c 19968) #f)
      ((int< c 40960) #t)
      ((int< c 44032) #f)
      ((int< c 55204) #t)
      (#t #f))))
(def %sre-space?
  (fn (_ c)
    (match
      ((int< c 128) (if (%sre-ascii-space? c) #t (if (int< 27 c) (int< c 32) #f)))
      ((int= c 133) #t) ((int= c 160) #t) ((int= c 5760) #t)
      ((int< c 8192) #f) ((int< c 8203) #t)
      ((int= c 8232) #t) ((int= c 8233) #t) ((int= c 8239) #t) ((int= c 8287) #t)
      ((int= c 12288) #t)
      (#t #f))))

(def %sre-cat?
  (fn (_ cat c)
    (match
      ((int= cat 0) (%sre-ascii-digit? c))
      ((int= cat 1) (%sre-word? c))
      ((int= cat 2) (%sre-space? c))
      ((int= cat 3) (%sre-ascii-digit? c))
      ((int= cat 4) (%sre-ascii-word? c))
      (#t (%sre-ascii-space? c)))))

; a class's items against c: any one matching is a match
(def %sre-in?
  (fn (self items c)
    (if (null? items) #f
      (let ((kind (first items)) (a (first (rest items))) (b (first (rest (rest items)))))
        (if (if (int= kind 0)
              (if (int< c a) #f (if (int< b c) #f #t))
              (if (%sre-cat? a c) (int= b 0) (int= b 1)))
          #t
          (self (rest (rest (rest items))) c))))))
(def %sre-class?
  (fn (_ neg items c)
    (if (%sre-in? items c) (int= neg 0) (int= neg 1))))
(def %sre-classi?
  (fn (_ neg items c)
    (if (if (%sre-in? items c) #t
          (if (%sre-in? items (%sre-lower c)) #t (%sre-in? items (%sre-upper c))))
      (int= neg 0) (int= neg 1))))

; --- one code point ----------------------------------------------------------

; does the one-code-point NODE take c?
(def %sre-one?
  (fn (_ node c)
    (let ((op (first node)))
      (match
        ((int= op 0) (int= c (first (rest node))))
        ((int= op 1) (if (int= c 10) #f #t))
        ((int= op 2) #t)
        ((int= op 3) (%sre-class? (first (rest node)) (first (rest (rest node))) c))
        ((int= op 13) (int= (%sre-lower c) (first (rest node))))
        (#t (%sre-classi? (first (rest node)) (first (rest (rest node))) c))))))
(def %sre-single?
  (fn (_ node)
    (let ((op (first node)))
      (if (int< op 4) #t (if (int= op 13) #t (int= op 14))))))

; --- the state ---------------------------------------------------------------
;
; One match's state, a Vector: 1 the subject, 2 its end, 3 the marks, 4 the
; depth.  The subject is a Vector of code points.

(def %sre-depth-max 2500)
(def %sre-s (fn (_ st) (obj-ref st 1)))
(def %sre-end (fn (_ st) (obj-ref st 2)))
(def %sre-marks (fn (_ st) (obj-ref st 3)))
(def %sre-ch (fn (_ st i) (obj-ref (obj-ref st 1) (int+ i 1))))
(def %sre-len (fn (_ st) (obj-ref (obj-ref st 1) 0)))

(def %sre-deeper!
  (fn (_ st)
    (let ((d (int+ (obj-ref st 4) 1)))
      (if (int< %sre-depth-max d)
        (Err raise (lit overflow) "regular expression too deeply nested for this runtime" ())
        (obj-set! st 4 d)))))
(def %sre-shallower! (fn (_ st) (obj-set! st 4 (int- (obj-ref st 4) 1))))

; the marks, copied and put back, for what must undo whatever ran inside it
(def %sre-snap
  (fn (_ st)
    (let ((mk (%sre-marks st)))
      (def go (fn (self i acc) (if (int< i 1) acc (self (int- i 1) (pair (obj-ref mk i) acc)))))
      (go (obj-ref mk 0) ()))))
(def %sre-restore!
  (fn (_ st snap)
    (let ((mk (%sre-marks st)))
      (def go (fn (self i l) (if (null? l) () (do (obj-set! mk i (first l)) (self (int+ i 1) (rest l))))))
      (go 1 snap))))

; --- the assertions ----------------------------------------------------------

(def %sre-wordat?
  (fn (_ st i ascii)
    (if (if (int< i 0) #t (if (int< i (%sre-end st)) #f #t)) #f
      (if ascii (%sre-ascii-word? (%sre-ch st i)) (%sre-word? (%sre-ch st i))))))
(def %sre-at?
  (fn (_ st kind i)
    (let ((end (%sre-end st)))
      (match
        ((int= kind 0) (int= i 0))
        ((int= kind 1) (if (int= i 0) #t (int= (%sre-ch st (int- i 1)) 10)))
        ((int= kind 2)
          (if (int= i end) #t
            (if (int= i (int- end 1)) (int= (%sre-ch st i) 10) #f)))
        ((int= kind 3) (if (int= i end) #t (int= (%sre-ch st i) 10)))
        ((int= kind 4) (int= i end))
        (#t
          (let ((ascii (if (int< 6 kind) #t #f)))
            (let ((b (if (%sre-wordat? st (int- i 1) ascii)
                       (if (%sre-wordat? st i ascii) #f #t)
                       (%sre-wordat? st i ascii))))
              (if (if (int= kind 5) #t (int= kind 7)) b (if b #f #t)))))))))

; --- the matcher -------------------------------------------------------------

(def %sre-m ())

; the nodes of a sequence, each continuing into the next
(def %sre-seq
  (fn (self st ns i k)
    (if (null? ns) (k i)
      (%sre-m st (first ns) i (fn (_ j) (self st (rest ns) j k))))))
(def %sre-alt
  (fn (self st ns i k)
    (if (null? ns) #f
      (let ((r (%sre-m st (first ns) i k)))
        (if (eq? r #f) (self st (rest ns) i k) r)))))

; how many of the one-code-point NODE run from i, at most MAX (-1 no bound)
(def %sre-run
  (fn (_ st node i max)
    (let ((end (%sre-end st)))
      (def go
        (fn (self j)
          (if (if (int< j end) (if (int< max 0) #t (int< (int- j i) max)) #f)
            (if (%sre-one? node (%sre-ch st j)) (self (int+ j 1)) j)
            j)))
      (int- (go i) i))))
(def %sre-rep1
  (fn (_ st min max mode node i k)
    (let ((n (%sre-run st node i max)))
      (if (int< n min) #f
        (match
          ((int= mode 2) (k (int+ i n)))
          ((int= mode 1)
            (let ((back (fn (self c)
                          (if (int< c min) #f
                            (let ((r (k (int+ i c))))
                              (if (eq? r #f) (self (int- c 1)) r))))))
              (back n)))
          (#t
            (let ((fwd (fn (self c)
                         (if (int< n c) #f
                           (let ((r (k (int+ i c))))
                             (if (eq? r #f) (self (int+ c 1)) r))))))
              (fwd min))))))))

; the general repeat: COUNT done so far.  An iteration that matched nothing
; once the minimum is met ends the repeat, so x* of an empty x cannot loop.
(def %sre-rep
  (fn (self st min max mode node count i k)
    (let ((more (if (int< max 0) #t (int< count max))))
      (let ((again
              (fn (_)
                (if more
                  (do
                    (%sre-deeper! st)
                    (let ((r (%sre-m st node i
                               (fn (_ j)
                                 (if (if (int= j i) (if (int< count min) #f #t) #f) #f
                                   (self st min max mode node (int+ count 1) j k))))))
                      (%sre-shallower! st)
                      r))
                  #f))))
        (if (int< count min) (again)
          (if (int= mode 0)
            (let ((r (k i))) (if (eq? r #f) (again) r))
            (let ((r (again))) (if (eq? r #f) (k i) r))))))))

(def %sre-group
  (fn (_ st g node i k)
    (%sre-m st node i
      (fn (_ j)
        (let ((mk (%sre-marks st)) (s (int+ (int* 2 g) 2)))
          (let ((os (obj-ref mk s)) (oe (obj-ref mk (int+ s 1))) (ol (obj-ref mk 1)))
            (obj-set! mk s i)
            (obj-set! mk (int+ s 1) j)
            (obj-set! mk 1 g)
            (let ((r (k j)))
              (if (eq? r #f)
                (do (obj-set! mk s os) (obj-set! mk (int+ s 1) oe) (obj-set! mk 1 ol) #f)
                r))))))))

(def %sre-backref
  (fn (_ st g i k fold)
    (let ((mk (%sre-marks st)))
      (let ((s (obj-ref mk (int+ (int* 2 g) 2))) (e (obj-ref mk (int+ (int* 2 g) 3))))
        (if (int< s 0) #f
          (let ((n (int- e s)))
            (if (int< (%sre-end st) (int+ i n)) #f
              (let ((same (fn (self d)
                            (if (int= d n) #t
                              (if (if fold
                                    (int= (%sre-lower (%sre-ch st (int+ s d)))
                                          (%sre-lower (%sre-ch st (int+ i d))))
                                    (int= (%sre-ch st (int+ s d)) (%sre-ch st (int+ i d))))
                                (self (int+ d 1)) #f)))))
                (if (same 0) (k (int+ i n)) #f)))))))))

(def %sre-id (fn (_ j) j))

; a lookaround, and an atomic group: what ran inside is kept only if the
; whole succeeds
(def %sre-look
  (fn (_ st behind neg w node i k)
    (let ((snap (%sre-snap st)))
      (let ((r (if (int= behind 0)
                 (%sre-m st node i %sre-id)
                 (if (int< i w) #f
                   (%sre-m st node (int- i w) (fn (_ j) (if (int= j i) j #f)))))))
        (if (int= neg 1)
          (do (%sre-restore! st snap) (if (eq? r #f) (k i) #f))
          (if (eq? r #f) #f
            (let ((r2 (k i))) (if (eq? r2 #f) (do (%sre-restore! st snap) #f) r2))))))))
(def %sre-atomic
  (fn (_ st node i k)
    (let ((snap (%sre-snap st)))
      (let ((j (%sre-m st node i %sre-id)))
        (if (eq? j #f) #f
          (let ((r (k j))) (if (eq? r #f) (do (%sre-restore! st snap) #f) r)))))))

(set! %sre-m
  (fn (_ st node i k)
    (let ((op (first node)) (a (rest node)))
      (match
        ((%sre-single? node)
          (if (int< i (%sre-end st))
            (if (%sre-one? node (%sre-ch st i)) (k (int+ i 1)) #f)
            #f))
        ((int= op 4) (%sre-seq st (first a) i k))
        ((int= op 5) (%sre-alt st (first a) i k))
        ((int= op 6)
          (let ((min (first a)) (max (first (rest a))) (mode (first (rest (rest a))))
                (n (first (rest (rest (rest a))))))
            (if (%sre-single? n)
              (%sre-rep1 st min max mode n i k)
              (if (int= mode 2)
                (%sre-atomic st (list 6 min max 1 n) i k)
                (%sre-rep st min max mode n 0 i k)))))
        ((int= op 7) (%sre-group st (first a) (first (rest a)) i k))
        ((int= op 8) (%sre-backref st (first a) i k #f))
        ((int= op 15) (%sre-backref st (first a) i k #t))
        ((int= op 9) (if (%sre-at? st (first a) i) (k i) #f))
        ((int= op 10)
          (%sre-look st (first a) (first (rest a)) (first (rest (rest a)))
            (first (rest (rest (rest a)))) i k))
        ((int= op 11) (%sre-atomic st (first a) i k))
        ((int= op 12)
          (let ((mk (%sre-marks st)))
            (%sre-m st
              (if (int< (obj-ref mk (int+ (int* 2 (first a)) 2)) 0)
                (first (rest (rest a))) (first (rest a)))
              i k)))
        (#t (Err raise (lit value) "internal error in regular expression engine" ()))))))

; --- a match -----------------------------------------------------------------

; the code points of a str, or the bytes of a bytes or bytearray
(def %sre-subject
  (fn (_ v)
    (if (python-str-is v) (python-str-cps v)
      (if (python-bytes-is v) (python-bytes-list v)
        (Err raise (lit type) "expected string or bytes-like object" ())))))

(def %sre-fill
  (fn (_ n x)
    (def go (fn (self k acc) (if (int< k 1) acc (self (int- k 1) (pair x acc)))))
    (go n ())))

; MODE 0 match, 1 fullmatch, 2 search.  An empty match at FORBID is refused
; (-1 refuses none): finditer and sub ask for the next match after an empty
; one this way.  The answer is None or a tuple: lastindex, then the start and
; end of the whole match and of each group, -1 where a group did not take part.
(def %sre-match
  (fn (_ prog ngroups subj pos endpos mode forbid)
    (let ((s (Vector from-list (%sre-subject subj))))
      (let ((len (obj-ref s 0)))
        (let ((end (if (int< endpos len) (if (int< endpos 0) 0 endpos) len))
              (start0 (if (int< pos 0) 0 pos))
              (mk (Vector from-list (%sre-fill (int+ 1 (int* 2 (int+ ngroups 1))) -1))))
          (let ((st (Vector from-list (list s end mk 0))))
            (def try
              (fn (_ i)
                (%sre-m st prog i
                  (fn (_ j)
                    (if (if (int= mode 1) (if (int= j end) #f #t) #f) #f
                      (if (if (int= j i) (int= i forbid) #f) #f j))))))
            (def scan
              (fn (self i)
                (if (int< end i) #f
                  (let ((j (try i)))
                    (if (eq? j #f)
                      (if (int= mode 2) (self (int+ i 1)) #f)
                      (pair i j))))))
            (let ((r (if (int< end start0) #f (scan start0))))
              (if (eq? r #f) ()
                (do
                  (obj-set! mk 2 (first r))
                  (obj-set! mk 3 (rest r))
                  (python-tuple-new
                    (let ((go (fn (self k acc)
                                (if (int< k 1) acc (self (int- k 1) (pair (obj-ref mk k) acc))))))
                      (go (obj-ref mk 0) ()))))))))))))

(def python-_sre-module
  (fn (_)
    (python-module-new "_sre"
      (list
        (pair "compile" (fn (_ code) (%sre-cvt code)))
        (pair "lower" (fn (_ c) (%sre-lower c)))
        (pair "match"
          (fn (_ prog ngroups subj pos endpos mode forbid)
            (%sre-match prog ngroups subj pos endpos mode forbid)))))))

; The row in the table of built-in modules (python/modules).
(PyModule def-static! (lit _sre) (fn (_ cls) (python-_sre-module)))

(provide python/_sre python-_sre-module)
