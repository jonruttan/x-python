; # x-python -- Python on x-lang
;
; ## lib/python/_random.x -- the _random module
;
; @description The Mersenne Twister, MT19937, that random.py draws from: its
;   state, its seeding from an array of 32-bit words, and its next word.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; CPYTHON SPLITS ITS random MODULE THE SAME WAY: the generator is the C module
; _random and stdlib/random.py builds the distributions on it.  Written in
; Python the generator cost 25 s to import and some 25 ms a word; here it is the int
; doors on a Vector.
;
; The doors are 64-bit and wrap, so each step keeps its low 32 bits right
; however high a product or a difference goes, and a mask takes them.
;
; A state is a Vector of 625 slots: the 624 words, then mti, the index of the
; next word to temper.  Python holds it as an opaque value and hands it back.
; The checks a caller's arguments need -- a seed's type, getrandbits' k -- are
; random.py's; these take what it gives them.

(module python/_random)
(import python/modules PyModule)
(import python/core
  python-list-elems python-module-new python-tuple-elems python-tuple-new)
(import x/core/doors int+ int- int* int& int| int^ int<< int>> int< int= obj-ref obj-set!)
(import x/type/vector)

(def %mt-n 624)
(def %mt-mask 4294967295)

; word I of state V, and V with word I set to X (slot 0 is the length)
(def %mt-w (fn (_ v i) (obj-ref v (int+ i 1))))
(def %mt-w! (fn (_ v i x) (obj-set! v (int+ i 1) x)))
(def %mt-mti 625)

; a fresh state, every word 0 and mti past the end
(def %mt-new
  (fn (_)
    (def zeros (fn (self k acc) (if (int< k 1) acc (self (int- k 1) (pair 0 acc)))))
    (let ((v (Vector from-list (zeros 625 ()))))
      (obj-set! v %mt-mti %mt-n)
      v)))

; init_genrand: the words from one seed S
(def %mt-init-genrand
  (fn (_ v s)
    (%mt-w! v 0 (int& s %mt-mask))
    (def go
      (fn (self i)
        (if (int< i %mt-n)
          (let ((prev (%mt-w v (int- i 1))))
            (%mt-w! v i
              (int& (int+ (int* 1812433253 (int^ prev (int>> prev 30))) i) %mt-mask))
            (self (int+ i 1))))))
    (go 1)
    (obj-set! v %mt-mti %mt-n)))

; init_by_array: the words from KEY, a non-empty list of 32-bit words
(def %mt-init-by-array
  (fn (_ v key0)
    (%mt-init-genrand v 19650218)
    (def key (Vector from-list key0))
    (def n (obj-ref key 0))
    (def mix1
      (fn (self i j k)
        (if (int< 0 k)
          (let ((prev (%mt-w v (int- i 1))))
            (%mt-w! v i
              (int& (int+ (int+ (int^ (%mt-w v i)
                                      (int* (int^ prev (int>> prev 30)) 1664525))
                                (obj-ref key (int+ j 1)))
                          j)
                    %mt-mask))
            (let ((i1 (int+ i 1)) (j1 (int+ j 1)))
              (let ((i2 (if (int< i1 %mt-n) i1
                          (do (%mt-w! v 0 (%mt-w v (int- %mt-n 1))) 1))))
                (self i2 (if (int< j1 n) j1 0) (int- k 1)))))
          i)))
    (def mix2
      (fn (self i k)
        (if (int< 0 k)
          (let ((prev (%mt-w v (int- i 1))))
            (%mt-w! v i
              (int& (int- (int^ (%mt-w v i)
                                (int* (int^ prev (int>> prev 30)) 1566083941))
                          i)
                    %mt-mask))
            (let ((i1 (int+ i 1)))
              (self (if (int< i1 %mt-n) i1
                      (do (%mt-w! v 0 (%mt-w v (int- %mt-n 1))) 1))
                (int- k 1)))))))
    (mix2 (mix1 1 0 (if (int< n %mt-n) %mt-n n)) (int- %mt-n 1))
    (%mt-w! v 0 2147483648)))

; the next 624 words from these, all at once
(def %mt-step
  (fn (_ v kk next far)
    (let ((y (int| (int& (%mt-w v kk) 2147483648) (int& (%mt-w v next) 2147483647))))
      (%mt-w! v kk
        (int^ (int^ (%mt-w v far) (int>> y 1))
              (if (int= (int& y 1) 0) 0 2567483615))))))
(def %mt-twist
  (fn (_ v)
    (def go
      (fn (self kk)
        (if (int< kk (int- %mt-n 1))
          (do
            (%mt-step v kk (int+ kk 1)
              (if (int< kk 227) (int+ kk 397) (int- kk 227)))
            (self (int+ kk 1))))))
    (go 0)
    (%mt-step v (int- %mt-n 1) 0 396)
    (obj-set! v %mt-mti 0)))

; genrand_uint32: the next word, tempered
(def %mt-genrand
  (fn (_ v)
    (if (int< (obj-ref v %mt-mti) %mt-n) () (%mt-twist v))
    (let ((i (obj-ref v %mt-mti)))
      (obj-set! v %mt-mti (int+ i 1))
      (let ((y0 (%mt-w v i)))
        (let ((y1 (int^ y0 (int>> y0 11))))
          (let ((y2 (int^ y1 (int& (int<< y1 7) 2636928640))))
            (let ((y3 (int^ y2 (int& (int<< y2 15) 4022730752))))
              (int^ y3 (int>> y3 18)))))))))

; random(): 53 bits as a float in [0.0, 1.0), as CPython makes it
(def %mt-random
  (fn (_ v)
    (let ((a (int>> (%mt-genrand v) 5)))
      (let ((b (int>> (%mt-genrand v) 6)))
        (* (+ (* (+ a 0.0) 67108864.0) b) (/ 1.0 9007199254740992.0))))))

; the state as getstate() shows it, the 624 words then mti, and back
(def %mt-getstate
  (fn (_ v)
    (def go (fn (self i acc) (if (int< i 0) acc (self (int- i 1) (pair (%mt-w v i) acc)))))
    (python-tuple-new (go %mt-n ()))))
(def %mt-setstate
  (fn (_ v words)
    (def go
      (fn (self i ws)
        (if (null? ws) ()
          (do (%mt-w! v i (first ws)) (self (int+ i 1) (rest ws))))))
    (go 0 words)))

(def python-_random-module
  (fn (_)
    (python-module-new "_random"
      (list
        (pair "new" (fn (_) (%mt-new)))
        (pair "init_genrand" (fn (_ v s) (%mt-init-genrand v s) ()))
        (pair "init_by_array" (fn (_ v key) (%mt-init-by-array v (python-list-elems key)) ()))
        (pair "genrand" (fn (_ v) (%mt-genrand v)))
        (pair "getrandbits" (fn (_ v k) (int>> (%mt-genrand v) (int- 32 k))))
        (pair "random" (fn (_ v) (%mt-random v)))
        (pair "getstate" (fn (_ v) (%mt-getstate v)))
        (pair "setstate" (fn (_ v t) (%mt-setstate v (python-tuple-elems t)) ()))))))

; The row in the table of built-in modules (python/modules).
(PyModule def-static! (lit _random) (fn (_ cls) (python-_random-module)))

(provide python/_random python-_random-module)
