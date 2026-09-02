; # x-python -- Python on x-lang
;
; ## python/format.x -- the % string-formatting operator
;
; @description "%.2e" % x and friends: the printf-family conversions, built
;   on the float repr's exact-digit machinery so every rendering is
;   bit-faithful to the value rather than to a lossy intermediate.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; THE DIGITS ARE EXACT, SO THE ROUNDING IS HONEST.  A float is m*2^e; the
; repr machinery in runtime.x (%py-f-exact) renders every decimal digit of
; that integer product, so %.5e, %.40f and %.0g are all the same operation --
; keep k digits of a fully known expansion, round half to even against a
; fully known tail -- rather than printf reinterpreting a lossy double.
; This is what makes the MicroPython corpus's nastiest cases (digit-value-10
; rendering as ':', %.12e of 1e-r rendering as 0.999...e-r) structurally
; impossible here instead of carefully avoided.
;
; ONE NAMESPACE NOTE: this file leans on runtime.x's globals (%py-str,
; %py-f-round, %py-f-exact ...) resolved at CALL time, so it loads before
; them without ceremony; nothing here runs until a program formats.

(provide python/format %py-format)

; --- Spec grammar ------------------------------------------------------------
; %[flags][width][.precision]conversion, with flags in {- + space 0 #}.
; No %(name)s mapping form and no * width/precision: both refuse loudly
; rather than mis-consume arguments.

(def %py-fmt-code (fn (_ s i) (%py-char-code (%str-ref s i))))
(def %py-fmt-digit? (fn (_ c) (if (>= c 48) (<= c 57) #f)))

(def %py-fmt-zeros
  (fn (self k) (if (<= k 0) "" (Str8 append "0" (self (- k 1))))))
(def %py-fmt-spaces
  (fn (self k) (if (<= k 0) "" (Str8 append " " (self (- k 1))))))

; --- Padding and signs -------------------------------------------------------
; The sign travels separately from the magnitude so zero-padding lands
; BETWEEN them: %08.2f of -1.5 is -0001.50, never 000-1.50.
(def %py-fmt-pad
  (fn (_ sgn body width left zero)
    (def total (+ (Str8 length sgn) (Str8 length body)))
    (if (>= total width)
      (Str8 append sgn body)
      (if left
        (Str8 append (Str8 append sgn body) (%py-fmt-spaces (- width total)))
        (if zero
          (Str8 append sgn
            (Str8 append (%py-fmt-zeros (- width total)) body))
          (Str8 append (%py-fmt-spaces (- width total))
            (Str8 append sgn body)))))))

(def %py-fmt-sign
  (fn (_ neg plus space)
    (if neg "-" (if plus "+" (if space " " "")))))

; --- Integer magnitudes ------------------------------------------------------
; The decimal spelling of the integer part of any numeric operand: ints and
; bigints by their own printer, bools as 1/0, floats TRUNCATED through the
; exact digits (never through a lossy int64 door).
(def %py-fmt-int-mag
  (fn (_ v)
    ; -> (pair neg? magnitude-string)
    (if (eq? v #t)
      (pair #f "1")
      (if (eq? v #f)
        (pair #f "0")
        (if (%py-float-is v)
          (do
            (def ex (%py-f-exact v))
            (def kind (first ex))
            (if (not (eq? kind (lit num)))
              (Err raise (lit value) "cannot convert float infinity or nan to integer" ())
              (do
                (def D (first (rest (rest ex))))
                (def x10 (first (rest (rest (rest ex)))))
                (def neg (Str8 =? (first (rest ex)) "-"))
                ; truncation toward zero can leave nothing: %d of -0.5 is
                ; 0, not -0
                (if (< x10 0)
                  (pair #f "0")
                  (do
                    (def keep (+ x10 1))
                    (def got (Str8 length D))
                    (def mag
                      (if (>= got keep)
                        (Str8 sub 0 keep D)
                        (Str8 append D (%py-fmt-zeros (- keep got)))))
                    (pair (if (Str8 =? mag "0") #f neg) mag))))))
          (let ((s (%py-str v)))
            (if (Str8 =? (Str8 sub 0 1 s) "-")
              (pair #t (Str8 sub 1 (- (Str8 length s) 1) s))
              (pair #f s))))))))

; Base conversion for %o %x %X, bigint-capable through the tower ops.
(def %py-fmt-base
  (fn (_ v base tbl)
    (def m (%py-fmt-int-mag v))
    (def dig ())
    (set! dig
      (fn (_ n acc)
        (if (eq? n 0)
          acc
          (dig (%py-floordiv n base)
            (Str8 append (Str8 sub (%py-mod n base) 1 tbl) acc)))))
    ; back through the decimal spelling so bigints work without a cell walk
    (def n (%py-int-of-str (rest m)))
    (pair (first m) (if (eq? n 0) "0" (dig n "")))))

; --- Float digit machinery ---------------------------------------------------
; Everything below speaks (D x10): every digit, and the power of ten of the
; first one, from %py-f-exact.  Rounding to k POSITIONS of a digit string is
; %py-f-round (half to even, exact tail); a carry lengthens the string and
; the caller reads the length.

; Fixed-point: value rounded at 10^-prec, as (pair int-part frac-part).
(def %py-fmt-fixed
  (fn (_ D x10 prec)
    (def keep (+ (+ x10 1) prec))
    ; Pad leading zeros so the round position is always inside the string.
    (def z (if (<= keep 0) (+ 1 (- 0 keep)) 0))
    (def Dp (Str8 append (%py-fmt-zeros z) D))
    (def k (+ keep z))
    (def R0 (%py-f-round Dp k))
    ; Right-pad to exactly k digits (an exact short expansion is zeros).
    (def R
      (if (< (Str8 length R0) k)
        (Str8 append R0 (%py-fmt-zeros (- k (Str8 length R0))))
        R0))
    (def total (Str8 length R))
    (def intd (- total prec))
    (if (> intd 0)
      (pair (Str8 sub 0 intd R) (Str8 sub intd (- total intd) R))
      (pair "0" (Str8 append (%py-fmt-zeros (- 0 intd)) R)))))

; Scientific: prec digits after the point -> (list mant-int mant-frac exp10).
(def %py-fmt-sci
  (fn (_ D x10 prec)
    (def sig (+ prec 1))
    (def R0 (%py-f-round D sig))
    (def kept (if (< (Str8 length D) sig) (Str8 length D) sig))
    (def xa (+ x10 (- (Str8 length R0) kept)))
    (def R
      (if (< (Str8 length R0) sig)
        (Str8 append R0 (%py-fmt-zeros (- sig (Str8 length R0))))
        (if (> (Str8 length R0) sig) (Str8 sub 0 sig R0) R0)))
    (list (Str8 sub 0 1 R) (Str8 sub 1 (- (Str8 length R) 1) R) xa)))

(def %py-fmt-exp-str
  (fn (_ x upper)
    (def mag (if (< x 0) (- 0 x) x))
    (def ds (%py-write-to-str mag))
    (Str8 append (if upper "E" "e")
      (Str8 append (if (< x 0) "-" "+")
        (if (< mag 10) (Str8 append "0" ds) ds)))))

(def %py-fmt-strip0
  (fn (self s)
    (def L (Str8 length s))
    (if (= L 0)
      s
      (if (= (%py-fmt-code s (- L 1)) 48)
        (self (Str8 sub 0 (- L 1) s))
        s))))

; --- The conversions ---------------------------------------------------------
; Each returns the magnitude body; the caller adds sign and padding.
; Non-finite floats short-circuit before any of these.

(def %py-fmt-f
  (fn (_ D x10 prec)
    (let ((p (%py-fmt-fixed D x10 prec)))
      (if (= prec 0)
        (first p)
        (Str8 append (first p) (Str8 append "." (rest p)))))))

(def %py-fmt-e
  (fn (_ D x10 prec upper)
    (let ((s (%py-fmt-sci D x10 prec)))
      (Str8 append
        (if (= prec 0)
          (first s)
          (Str8 append (first s) (Str8 append "." (first (rest s)))))
        (%py-fmt-exp-str (first (rest (rest s))) upper)))))

(def %py-fmt-g
  (fn (_ D x10 prec0 upper alt)
    (def prec (if (= prec0 0) 1 prec0))
    ; Round to prec significant digits FIRST; the fixed/scientific decision
    ; reads the rounded exponent (99.9 at %.2g is 1e+02, not 100).
    (def s (%py-fmt-sci D x10 (- prec 1)))
    (def xa (first (rest (rest s))))
    (def digits (Str8 append (first s) (first (rest s))))
    (if (if (>= xa (- 0 4)) (< xa prec) #f)
      ; fixed, prec-1-xa places after the point, trailing zeros stripped
      (do
        (def intd (+ xa 1))
        (def ip (if (> intd 0) (Str8 sub 0 intd digits) "0"))
        (def fp0
          (if (> intd 0)
            (Str8 sub intd (- (Str8 length digits) intd) digits)
            (Str8 append (%py-fmt-zeros (- 0 intd)) digits)))
        (def fp (if alt fp0 (%py-fmt-strip0 fp0)))
        (if (= (Str8 length fp) 0)
          ip
          (Str8 append ip (Str8 append "." fp))))
      ; scientific, trailing zeros stripped from the mantissa
      (do
        (def fp (if alt (first (rest s)) (%py-fmt-strip0 (first (rest s)))))
        (Str8 append
          (if (= (Str8 length fp) 0)
            (first s)
            (Str8 append (first s) (Str8 append "." fp)))
          (%py-fmt-exp-str xa upper))))))

; A numeric operand for the float conversions, through the tower so 10**val
; formats the same as its float twin.
; %d on an object asks __int__, as int() would
(def %py-fmt-int-of
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__int__")))
        (if (null? m)
          (Err raise (lit type) "%d format: a real number is required, not object" ())
          (m)))
      v)))
(def %py-fmt-float-of
  (fn (_ v)
    (if (%py-float-is v) v (* 1.0 (if (eq? v #t) 1 (if (eq? v #f) 0 v))))))

; --- The operator ------------------------------------------------------------

(def %py-fmt-take!
  (fn (_ cell)
    (if (null? (first cell))
      (Err raise (lit type) "not enough arguments for format string" ())
      (let ((v (first (first cell))))
        (%set-first! cell (rest (first cell)))
        v))))

; One parsed conversion, fully rendered and padded.  A separate global
; rather than a frame-local of %py-format: a closure sees only the frame
; locals that exist when it is BUILT, so the walker below forward-declares
; nothing it can define first.
(def %py-fmt-one
  (fn (_ conv v left plus space zero alt width prec bad)
    ; s and r: text, precision truncates, zero pads with spaces; c is the
    ; character of a code point, or a one-character string as itself
    (if (if (= conv 115) #t (if (= conv 114) #t (= conv 99)))
      (do
        (def s0
          (if (= conv 99)
            (if (str? v)
              (if (= (%py-len v) 1) v
                (Err raise (lit type) "%c requires an int or a unicode char, not a string of length other than 1" ()))
              (%py-chr v))
            (if (= conv 115) (%py-str v) (%py-repr-of v))))
        (def s (if (if (>= prec 0) (> (Str8 length s0) prec) #f)
          (Str8 sub 0 prec s0) s0))
        (%py-fmt-pad "" s width left #f))
      ; d i u
      (if (if (= conv 100) #t (if (= conv 105) #t (= conv 117)))
        (do
          (def m (%py-fmt-int-mag (%py-fmt-int-of v)))
          (def body
            (if (if (>= prec 0) (< (Str8 length (rest m)) prec) #f)
              (Str8 append (%py-fmt-zeros (- prec (Str8 length (rest m)))) (rest m))
              (rest m)))
          (%py-fmt-pad (%py-fmt-sign (first m) plus space)
            body width left (if left #f zero)))
        ; o x X
        (if (if (= conv 111) #t (if (= conv 120) #t (= conv 88)))
          (do
            (def b (if (= conv 111) 8 16))
            (def tbl (if (= conv 88) "0123456789ABCDEF" "0123456789abcdef"))
            (def m (%py-fmt-base v b tbl))
            (def pfx
              (if alt
                (if (= conv 111) "0o" (if (= conv 88) "0X" "0x"))
                ""))
            (%py-fmt-pad (Str8 append (%py-fmt-sign (first m) plus space) pfx)
              (rest m) width left (if left #f zero)))
          ; e E f F g G
          (if (if (= conv 101) #t (if (= conv 69) #t
              (if (= conv 102) #t (if (= conv 70) #t
              (if (= conv 103) #t (= conv 71))))))
            (do
              (def upper
                (if (= conv 69) #t (if (= conv 70) #t (= conv 71))))
              (def p (if (>= prec 0) prec 6))
              (def fv (%py-fmt-float-of v))
              (def ex (%py-f-exact fv))
              (def kind (first ex))
              (def neg (Str8 =? (first (rest ex)) "-"))
              (if (not (eq? kind (lit num)))
                ; inf and nan zero-pad like any number under %-formatting
                ; ('%06e' % inf is 000inf -- measured, not assumed); nan
                ; never carries the value's sign, only a flag's
                (do
                  (def body0 (if (eq? kind (lit inf)) "inf" "nan"))
                  (def body (if upper (if (eq? kind (lit inf)) "INF" "NAN") body0))
                  (%py-fmt-pad
                    (%py-fmt-sign (if (eq? kind (lit nan)) #f neg) plus space)
                    body width left (if left #f zero)))
                (do
                  (def D (first (rest (rest ex))))
                  (def x10 (first (rest (rest (rest ex)))))
                  (def body
                    (if (if (= conv 101) #t (= conv 69))
                      (%py-fmt-e D x10 p upper)
                      (if (if (= conv 102) #t (= conv 70))
                        (%py-fmt-f D x10 p)
                        (%py-fmt-g D x10 p upper alt))))
                  (%py-fmt-pad (%py-fmt-sign neg plus space)
                    body width left (if left #f zero)))))
            (bad)))))))

(def %py-format
  (fn (_ fmt arg)
    (def args (if (%py-tuple-is arg) (%py-tuple-elems arg) (list arg)))
    (def cell (pair args ()))
    ; A DICT IS A MAPPING: %(key)s looks the key up, and the looked-up value
    ; becomes the ONE positional argument left (CPython's own rule -- a %s
    ; after a keyed spec is "not enough arguments"), and a mapping never
    ; trips the not-all-converted check.
    (def mapping (if (%py-dict-is arg) arg ()))
    (def n (Str8 length fmt))
    ; * takes the width or precision from the arguments
    (def star!
      (fn (_)
        (let ((v (%py-fmt-take! cell)))
          (if (eq? (%py-num-kind v) (lit int)) v
            (Err raise (lit type) "* wants int" ())))))
    (def spec-err
      (fn (_ i)
        (Err raise (lit value)
          (Str8 append "unsupported format character '"
            (Str8 append (if (< i n) (Str8 sub i 1 fmt) "") "'"))
          ())))
    ; DEFINE-BEFORE-USE, WITH A FORWARD CELL FOR THE MUTUAL RECURSION: a
    ; closure sees only the frame locals that exist when it is built, so
    ; the plain walker gets a cell the spec parser can hand back to --
    ; the tokenizer's own idiom.
    (def go ())
    (def self-spec
      (fn (_ j0 acc)
        ; flags
        (def flags
          (fn (self j left plus space zero alt)
            (let ((c (if (< j n) (%py-fmt-code fmt j) 0)))
              (if (= c 45) (self (+ j 1) #t plus space zero alt)
              (if (= c 43) (self (+ j 1) left #t space zero alt)
              (if (= c 32) (self (+ j 1) left plus #t zero alt)
              (if (= c 48) (self (+ j 1) left plus space #t alt)
              (if (= c 35) (self (+ j 1) left plus space zero #t)
                (list j left plus space zero alt)))))))))
        (def keyed
          (if (if (< j0 n) (= (%py-fmt-code fmt j0) 40) #f)
            (let ((close (Str8 index-of ")" (Str8 sub j0 (- n j0) fmt))))
              (if (null? close)
                (Err raise (lit value) "incomplete format key" ())
                (pair (+ j0 close 1) (Str8 sub (+ j0 1) (- close 1) fmt))))
            ()))
        (if (null? keyed) ()
          (if (null? mapping)
            (Err raise (lit type) "format requires a mapping" ())
            (%set-first! cell (list (%py-dget mapping (rest keyed))))))
        (def fl (flags (if (null? keyed) j0 (first keyed)) #f #f #f #f #f))
        (def j1 (first fl))
        (def left (first (rest fl)))
        (def plus (first (rest (rest fl))))
        (def space (first (rest (rest (rest fl)))))
        (def zero (first (rest (rest (rest (rest fl))))))
        (def alt (first (rest (rest (rest (rest (rest fl)))))))
        ; width
        (def num
          (fn (self j acc2)
            (if (if (< j n) (%py-fmt-digit? (%py-fmt-code fmt j)) #f)
              (self (+ j 1) (+ (* acc2 10) (- (%py-fmt-code fmt j) 48)))
              (pair j acc2))))
        (def w
          (if (if (< j1 n) (= (%py-fmt-code fmt j1) 42) #f)
            (pair (+ j1 1) (star!))
            (num j1 0)))
        (def j2 (first w))
        (def width (rest w))
        ; precision: a dot with no digits is precision 0
        (def pr
          (if (if (< j2 n) (= (%py-fmt-code fmt j2) 46) #f)
            (if (if (< (+ j2 1) n) (= (%py-fmt-code fmt (+ j2 1)) 42) #f)
              (pair (+ j2 2) (star!))
              (num (+ j2 1) 0))
            (pair j2 (- 0 1))))
        (def j3 (first pr))
        (def prec (rest pr))
        (if (>= j3 n)
          (Err raise (lit value) "incomplete format" ())
          (do
            (def conv (%py-fmt-code fmt j3))
            (def out
              ; %% consumes no argument
              (if (= conv 37)
                "%"
                (%py-fmt-one conv (%py-fmt-take! cell)
                  left plus space zero alt width prec
                  (fn (_) (spec-err j3)))))
            (go (+ j3 1) (Str8 append acc out))))))
    (set! go
      (fn (_ i acc)
        (if (>= i n)
          acc
          (let ((c (%py-fmt-code fmt i)))
            (if (not (= c 37))
              (go (+ i 1) (Str8 append acc (Str8 sub i 1 fmt)))
              (if (>= (+ i 1) n)
                (Err raise (lit value) "incomplete format" ())
                (self-spec (+ i 1) acc)))))))
    (let ((out (go 0 "")))
      (if (if (null? (first cell)) #t (not (null? mapping)))
        out
        (Err raise (lit type)
          "not all arguments converted during string formatting" ())))))
