; core.x -- the Python core: one module in several files.
;
; The reader's helpers, the types, the runtime and the parser share a
; vocabulary of private names; this file includes them into one module, so
; the names stay private to it.  The libraries (python/array, python/io, ...)
; are imported after the provide: each takes the core names it reads by name,
; and so the core must have provided them when a library loads.  A sweep
; between files, as before, since a load allocates more than a collect's
; worth.

(module python/core)
(include-once "./util.x")
(include-once "./types.x")
(python-sweep!)
(include-once "./str.x")
(python-sweep!)
(include-once "./bytes.x")
(python-sweep!)
(include-once "./format.x")
(python-sweep!)
; The platform the runtime stands on, loaded as runtime.x loaded it, a sweep
; after each.
(import x/boot/tower-compiled)
(python-sweep!)
(import x/num/bigint)
(python-sweep!)
(import x/num/float)
(python-sweep!)
(import x/num/rational)
(python-sweep!)
(import x/num/complex)
(python-sweep!)
(import x/num/decimal)
(python-sweep!)
(import x/type/generic)
(python-sweep!)
(import x/num/tower)
(python-sweep!)
(import x/type/dict)
(python-sweep!)
(import x/sys/cont)
(python-sweep!)
(include-once "./runtime-num.x")
(python-sweep!)
(include-once "./runtime-seq.x")
(python-sweep!)
(include-once "./runtime-str.x")
(python-sweep!)
(include-once "./runtime-obj.x")
(python-sweep!)
(include-once "./runtime-flow.x")
(python-sweep!)
(include-once "./runtime-call.x")
(python-sweep!)
(include-once "./runtime-py-type.x")
(python-sweep!)
(include-once "./indent.x")
(python-sweep!)
(include-once "./parse.x")
(python-sweep!)
(include-once "./base.x")
(python-sweep!)
(include-once "./repl.x")
(python-sweep!)

; python-run is the seam a Python program presses on: a program file of
; (python-run ...) forms calls it bare, so it is the root's.
(provide python/core
  python-f-2p52
  make-instance make-type pb->str pb-len pb-of-str ps->x ps-codec
  ps-decode-as ps-enc1 ps-encode ps-encode-as ps-write-bytes-to python-add
  python-alist-find python-barr-is python-barr-set! python-boolnorm python-builtins python-byte-len
  python-bytes-hex python-bytes-is python-bytes-list python-bytes-new python-bytes-of-codes
  python-bytes-only? python-bytes-str python-char-code python-cim python-class-methods-set!
  python-class-name python-class-new python-class-qualname python-class-row-attr
  python-cls-SimpleNamespace python-cls-dict python-cls-object python-cls-tuple
  python-complex-is python-cre python-desc-new python-dflt python-dict-entries python-dict-new
  python-dict? python-div python-dq-el python-dq-is python-dq-max python-dq-new python-dq-set!
  python-dq-set-max! python-drop python-drop-last python-dunder python-els-count python-els-drop-at
  python-els-index python-els-insert-at python-els-repeat python-els-set-at python-eq
  python-exc-FileExistsError python-exc-FileNotFoundError python-exc-IsADirectoryError
  python-exc-OSError python-exc-PermissionError python-exc-SystemExit python-exc-ValueError
  python-f-2p64 python-f-pow python-fasinh python-fcopysign python-fcosh python-float-of-str
  python-flog1p python-floordiv python-fsinh python-ftanh python-fx- python-fx< python-ge python-gt
  python-implementation-version python-in python-in-walk python-init-receiver!
  python-instantiate python-int-encode python-int-invert python-int-join python-iter-elems
  py-lang python-le python-leads? python-length python-list-cat python-list-clamp python-list-elems
  python-list-new python-list? python-lt python-mdomain python-mfloat python-mod python-module-new
  python-modules-now python-mrange-error python-mul python-native-of python-num-py-type python-num?
  python-obj-attrs python-obj-class python-obj-is python-obj-native python-obj-native!
  python-obj-new python-obj-set-attrs! python-opt python-path-now python-raise python-raise-stop
  python-repl-choose! python-repl-install! python-repl-line python-repl-register!
  python-repr-of python-rev-onto python-reverse python-set-elems python-set-is python-set-nth
  python-sig! python-slice-span python-str python-str-cps python-str-display python-str-is
  python-str-new python-str-of-x python-sub python-subclass? python-sweep! python-take
  python-takes-at-most! python-text->x python-th-float python-tuple-elems python-tuple-is
  python-tuple-new python-tuple-of-list python-type-of python-banner python-lex
  python-parse python-parse-expr python-parse-single python-repl-print
  (global python-run) python-version type?)

(import python/tokens
  %py-int->char mk-tok-number mk-tok-op python-code-at python-hexval
  python-list->string python-tokenize)
(import python/array
  python-arr-at python-arr-attr python-arr-buffer python-arr-cat python-arr-el python-arr-is
  python-arr-put! python-array-module python-cls-array python-ieee-2p63 python-ieee-raw
  python-take-n)
(import python/cmath
  python-cmath-module)
(import python/collections
  python-collections-module)
(import python/deque
  python-cls-deque python-dq-at python-dq-attr python-dq-cat python-dq-del! python-dq-eq
  python-dq-extend! python-dq-put! python-dq-repeat python-dq-repr)
(import python/io
  python-io-attr python-io-class python-io-drain! python-io-is python-io-line! python-io-module
  python-open)
(import python/memoryview
  python-buffer-bytes python-buffer-text python-buffer? python-cls-memoryview python-mv-at
  python-mv-attr python-mv-elems python-mv-in python-mv-is python-mv-len python-mv-put!
  python-mv-setslice! python-mv-slice)
(import python/struct
  python-struct-module)
(import python/sys
  python-sys-module)
(import python/line
  python-complete python-marks python-paint python-read python-session-name!)
