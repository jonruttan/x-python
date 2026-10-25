; # x-python -- Python on x-lang
;
; ## python/sys.x -- the sys module
;
; @description What the interpreter says about itself and the process it runs
;   in: the language version it implements, its own name and version, the
;   platform, the standard streams, and how large a value is.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; TWO VERSIONS, AND THEY ARE NOT THE SAME NUMBER.  sys.version and
; sys.version_info are the Python language this runtime implements;
; sys.implementation.version is this runtime's own, the number the REPL banner
; prints.  The implementation is named x-python and not CPython, so a program
; that branches on it sees what is actually running.

(module python/sys)
(import python/core
  python-byte-len python-bytes-is python-bytes-list python-char-code python-cls-SimpleNamespace
  python-dict-entries python-dict? python-exc-SystemExit python-implementation-version
  python-instantiate python-length python-list-elems python-list-new python-list? python-module-new
  python-modules-now python-obj-attrs python-obj-is python-obj-new python-obj-set-attrs!
  python-path-now python-raise python-reverse python-set-elems python-set-is python-sig! python-str-cps
  python-str-is python-str-of-x python-tuple-elems python-tuple-is)
(import python/collections python-namedtuple-class)
(import python/io python-io-std)

; --- versions -------------------------------------------------------------------

(def %py-sys-version "3.14.7")

; "3.14.7" -> (3 14 7): the digits between the dots.
(def %py-version-nums
  (fn (self s n i cur acc)
    (match
      ((>= i n) (python-reverse (pair cur acc)))
      ((= (python-char-code (%str-ref s i)) 46) (self s n (+ i 1) 0 (pair cur acc)))
      (#t (self s n (+ i 1) (+ (* cur 10) (- (python-char-code (%str-ref s i)) 48)) acc)))))

; A version as sys.version_info holds one: major, minor, micro, the release
; level and the serial -- a final release, serial 0.
(def %py-version-info
  (fn (_ cls s)
    (let ((ns (%py-version-nums s (python-byte-len s) 0 0 ())))
      (python-instantiate cls
        (list (List ref 0 ns) (List ref 1 ns) (List ref 2 ns) (python-str-of-x "final") 0)))))

; The same version as one int, a byte a field: 3.14.7 final is 0x030e07f0.
(def %py-hexversion
  (fn (_ s)
    (let ((ns (%py-version-nums s (python-byte-len s) 0 0 ())))
      (+ (* (List ref 0 ns) 16777216)
         (+ (* (List ref 1 ns) 65536) (+ (* (List ref 2 ns) 256) 240))))))

; --- the platform ---------------------------------------------------------------
; Read off x-machine, the build triple the platform layer keys its syscalls
; from, e.g. "arm64-apple-darwin23.6.0" or "x86_64-linux-gnu".  The triples and
; Python's name for each are a table; a triple naming none of them answers
; itself rather than a guess, which at least says truthfully where it ran.
(def %py-platform-names
  (list
    (pair "darwin"  "darwin")
    (pair "linux"   "linux")
    (pair "mingw"   "win32")
    (pair "cygwin"  "win32")
    (pair "windows" "win32")))

(def %py-platform-of
  (fn (self triple rows)
    (match
      ((null? rows) triple)
      ((not (null? (Str8 index-of (first (first rows)) triple))) (rest (first rows)))
      (#t (self triple (rest rows))))))

; sys.implementation is a SimpleNamespace, as CPython's is.  cache_tag is None:
; nothing here is compiled to a file a tag would name.
(def %py-sys-implementation
  (fn (_ version)
    (let ((o (python-obj-new python-cls-SimpleNamespace)))
      (%seq
        (python-obj-set-attrs! o
          (list
            (pair "name" (python-str-of-x "x-python"))
            (pair "cache_tag" ())
            (pair "version" version)
            (pair "hexversion" (%py-hexversion python-implementation-version))
            (pair "_machine" (python-str-of-x x-machine))))
        o))))

; --- getsizeof ------------------------------------------------------------------
; The bytes of the cells holding the value's own structure: one for the value,
; one for each element it holds directly, two for each dict entry and each
; attribute, every cell the size of a pair.  What those elements hold in turn
; is not counted, which is CPython's rule as well.
(def %py-cell-bytes (+ %data-offset (* 2 %word-size)))

(def %py-sizeof-cells
  (fn (_ v)
    (match
      ((python-obj-is v) (+ 1 (* 2 (python-length (python-obj-attrs v)))))
      ((python-str-is v) (+ 1 (python-length (python-str-cps v))))
      ((python-bytes-is v) (+ 1 (python-length (python-bytes-list v))))
      ((python-dict? v) (+ 1 (* 2 (python-length (python-dict-entries v)))))
      ((python-list? v) (+ 1 (python-length (python-list-elems v))))
      ((python-tuple-is v) (+ 1 (python-length (python-tuple-elems v))))
      ((python-set-is v) (+ 1 (python-length (python-set-elems v))))
      (#t 1))))

(def %py-getsizeof
  (fn (_ v . default) (* (%py-sizeof-cells v) %py-cell-bytes)))

; --- the module -----------------------------------------------------------------
; Text attributes are strs.  The version_info class is made with the module,
; so sys.version_info and sys.implementation.version share one.
(def python-sys-module
  (fn (_)
    (let ((vi (python-namedtuple-class "version_info" "sys.version_info"
                (list "major" "minor" "micro" "releaselevel" "serial"))))
      (python-module-new "sys"
        (list
          (pair "version" (python-str-of-x %py-sys-version))
          (pair "version_info" (%py-version-info vi %py-sys-version))
          (pair "hexversion" (%py-hexversion %py-sys-version))
          (pair "implementation"
            (%py-sys-implementation (%py-version-info vi python-implementation-version)))
          (pair "platform" (python-str-of-x (%py-platform-of x-machine %py-platform-names)))
          ; every architecture this platform builds for is little-endian; a
          ; big-endian port would have to say so here
          (pair "byteorder" (python-str-of-x "little"))
          ; the largest int a CPython machine word holds; this runtime has
          ; bigints and no such limit, and the number is what programs test
          (pair "maxsize" 9223372036854775807)
          ; the running program's own, which the importer reads (runtime-flow.x)
          (pair "path" (python-path-now))
          (pair "argv" (python-list-new ()))
          (pair "modules" (python-modules-now))
          (pair "stdin" (python-io-std 0 "<stdin>" #f))
          (pair "stdout" (python-io-std 1 "<stdout>" #t))
          (pair "stderr" (python-io-std 2 "<stderr>" #t))
          (pair "getsizeof"
            (python-sig! %py-getsizeof "getsizeof" (list "object" "default") 1 #f))
          (pair "exit"
            (fn (_ . a)
              (python-raise
                (python-instantiate python-exc-SystemExit
                  (if (null? a) () (list (first a))))))))))))

(provide python/sys python-implementation-version python-sys-module)
