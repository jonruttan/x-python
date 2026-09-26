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
(import python/io %py-io-std)
(import python/collections %py-namedtuple-class)

; --- versions -------------------------------------------------------------------

(def %py-sys-version "3.14.7")
(def %py-implementation-version "0.0.1")

; "3.14.7" -> (3 14 7): the digits between the dots.
(def %py-version-nums
  (fn (self s n i cur acc)
    (match
      ((>= i n) (%py-reverse (pair cur acc)))
      ((= (%py-char-code (%str-ref s i)) 46) (self s n (+ i 1) 0 (pair cur acc)))
      (#t (self s n (+ i 1) (+ (* cur 10) (- (%py-char-code (%str-ref s i)) 48)) acc)))))

; A version as sys.version_info holds one: major, minor, micro, the release
; level and the serial -- a final release, serial 0.
(def %py-version-info
  (fn (_ cls s)
    (let ((ns (%py-version-nums s (%py-byte-len s) 0 0 ())))
      (%py-instantiate cls
        (list (List ref 0 ns) (List ref 1 ns) (List ref 2 ns) (%py-str-of-x "final") 0)))))

; The same version as one int, a byte a field: 3.14.7 final is 0x030e07f0.
(def %py-hexversion
  (fn (_ s)
    (let ((ns (%py-version-nums s (%py-byte-len s) 0 0 ())))
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
    (let ((o (%py-obj-new %py-cls-SimpleNamespace)))
      (%seq
        (%py-obj-set-attrs! o
          (list
            (pair "name" (%py-str-of-x "x-python"))
            (pair "cache_tag" ())
            (pair "version" version)
            (pair "hexversion" (%py-hexversion %py-implementation-version))
            (pair "_machine" (%py-str-of-x x-machine))))
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
      ((%py-obj-is v) (+ 1 (* 2 (%py-length (%py-obj-attrs v)))))
      ((%py-str-is v) (+ 1 (%py-length (%py-str-cps v))))
      ((%py-bytes-is v) (+ 1 (%py-length (%py-bytes-list v))))
      ((%py-dict? v) (+ 1 (* 2 (%py-length (%py-dict-entries v)))))
      ((%py-list? v) (+ 1 (%py-length (%py-list-elems v))))
      ((%py-tuple-is v) (+ 1 (%py-length (%py-tuple-elems v))))
      ((%py-set-is v) (+ 1 (%py-length (%py-set-elems v))))
      (#t 1))))

(def %py-getsizeof
  (fn (_ v . default) (* (%py-sizeof-cells v) %py-cell-bytes)))

; --- the module -----------------------------------------------------------------
; Text attributes are strs.  The version_info class is made with the module,
; so sys.version_info and sys.implementation.version share one.
(def %py-sys-module
  (fn (_)
    (let ((vi (%py-namedtuple-class "version_info" "sys.version_info"
                (list "major" "minor" "micro" "releaselevel" "serial"))))
      (%py-module-new "sys"
        (list
          (pair "version" (%py-str-of-x %py-sys-version))
          (pair "version_info" (%py-version-info vi %py-sys-version))
          (pair "hexversion" (%py-hexversion %py-sys-version))
          (pair "implementation"
            (%py-sys-implementation (%py-version-info vi %py-implementation-version)))
          (pair "platform" (%py-str-of-x (%py-platform-of x-machine %py-platform-names)))
          ; every architecture this platform builds for is little-endian; a
          ; big-endian port would have to say so here
          (pair "byteorder" (%py-str-of-x "little"))
          ; the largest int a CPython machine word holds; this runtime has
          ; bigints and no such limit, and the number is what programs test
          (pair "maxsize" 9223372036854775807)
          (pair "path" (%py-list-new ()))
          (pair "argv" (%py-list-new ()))
          (pair "modules" (%py-dict-new ()))
          (pair "stdin" (%py-io-std 0 "<stdin>" #f))
          (pair "stdout" (%py-io-std 1 "<stdout>" #t))
          (pair "stderr" (%py-io-std 2 "<stderr>" #t))
          (pair "getsizeof"
            (%py-sig! %py-getsizeof "getsizeof" (list "object" "default") 1 #f))
          (pair "exit"
            (fn (_ . a)
              (%py-raise
                (%py-instantiate %py-exc-SystemExit
                  (if (null? a) () (list (first a))))))))))))

(provide python/sys %py-implementation-version %py-sys-module)
