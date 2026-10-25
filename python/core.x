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
(py-sweep!)
(include-once "./str.x")
(py-sweep!)
(include-once "./bytes.x")
(py-sweep!)
(include-once "./format.x")
(py-sweep!)
; The platform the runtime stands on, loaded as runtime.x loaded it, a sweep
; after each.
(import x/boot/tower-compiled)
(py-sweep!)
(import x/num/bigint)
(py-sweep!)
(import x/num/float)
(py-sweep!)
(import x/num/rational)
(py-sweep!)
(import x/num/complex)
(py-sweep!)
(import x/num/decimal)
(py-sweep!)
(import x/type/generic)
(py-sweep!)
(import x/num/tower)
(py-sweep!)
(import x/type/dict)
(py-sweep!)
(import x/sys/cont)
(py-sweep!)
(include-once "./runtime-num.x")
(py-sweep!)
(include-once "./runtime-seq.x")
(py-sweep!)
(include-once "./runtime-str.x")
(py-sweep!)
(include-once "./runtime-obj.x")
(py-sweep!)
(include-once "./runtime-flow.x")
(py-sweep!)
(include-once "./runtime-call.x")
(py-sweep!)
(include-once "./runtime-py-type.x")
(py-sweep!)
(include-once "./indent.x")
(py-sweep!)
(include-once "./parse.x")
(py-sweep!)
(include-once "./base.x")
(py-sweep!)
(include-once "./repl.x")
(py-sweep!)

; python-run is the seam a Python program presses on: a program file of
; (python-run ...) forms calls it bare, so it is the root's.
(provide python/core
  py-f-2p52
  make-instance make-type pb->str pb-len pb-of-str ps->x ps-codec
  ps-decode-as ps-enc1 ps-encode ps-encode-as ps-write-bytes-to py-add
  py-alist-find py-barr-is py-barr-set! py-boolnorm py-builtins py-byte-len
  py-bytes-hex py-bytes-is py-bytes-list py-bytes-new py-bytes-of-codes
  py-bytes-only? py-bytes-str py-char-code py-cim py-class-methods-set!
  py-class-name py-class-new py-class-qualname py-class-row-attr
  py-cls-SimpleNamespace py-cls-dict py-cls-object py-cls-tuple
  py-complex-is py-cre py-desc-new py-dflt py-dict-entries py-dict-new
  py-dict? py-div py-dq-el py-dq-is py-dq-max py-dq-new py-dq-set!
  py-dq-set-max! py-drop py-drop-last py-dunder py-els-count py-els-drop-at
  py-els-index py-els-insert-at py-els-repeat py-els-set-at py-eq
  py-exc-FileExistsError py-exc-FileNotFoundError py-exc-IsADirectoryError
  py-exc-OSError py-exc-PermissionError py-exc-SystemExit py-exc-ValueError
  py-f-2p64 py-f-pow py-fasinh py-fcopysign py-fcosh py-float-of-str
  py-flog1p py-floordiv py-fsinh py-ftanh py-fx- py-fx< py-ge py-gt
  py-implementation-version py-in py-in-walk py-init-receiver!
  py-instantiate py-int-encode py-int-invert py-int-join py-iter-elems
  py-lang py-le py-leads? py-length py-list-cat py-list-clamp py-list-elems
  py-list-new py-list? py-lt py-mdomain py-mfloat py-mod py-module-new
  py-modules-now py-mrange-error py-mul py-native-of py-num-py-type py-num?
  py-obj-attrs py-obj-class py-obj-is py-obj-native py-obj-native!
  py-obj-new py-obj-set-attrs! py-opt py-path-now py-raise py-raise-stop
  py-repl-choose! py-repl-install! py-repl-line py-repl-register!
  py-repr-of py-rev-onto py-reverse py-set-elems py-set-is py-set-nth
  py-sig! py-slice-span py-str py-str-cps py-str-display py-str-is
  py-str-new py-str-of-x py-sub py-subclass? py-sweep! py-take
  py-takes-at-most! py-text->x py-th-float py-tuple-elems py-tuple-is
  py-tuple-new py-tuple-of-list py-type-of python-banner python-lex
  python-parse python-parse-expr python-parse-single python-repl-print
  (global python-run) python-version type?)

(import python/tokens
  %py-int->char mk-tok-number mk-tok-op py-code-at py-hexval
  py-list->string python-tokenize)
(import python/array
  py-arr-at py-arr-attr py-arr-buffer py-arr-cat py-arr-el py-arr-is
  py-arr-put! py-array-module py-cls-array py-ieee-2p63 py-ieee-raw
  py-take-n)
(import python/cmath
  py-cmath-module)
(import python/collections
  py-collections-module)
(import python/deque
  py-cls-deque py-dq-at py-dq-attr py-dq-cat py-dq-del! py-dq-eq
  py-dq-extend! py-dq-put! py-dq-repeat py-dq-repr)
(import python/io
  py-io-attr py-io-class py-io-drain! py-io-is py-io-line! py-io-module
  py-open)
(import python/memoryview
  py-buffer-bytes py-buffer-text py-buffer? py-cls-memoryview py-mv-at
  py-mv-attr py-mv-elems py-mv-in py-mv-is py-mv-len py-mv-put!
  py-mv-setslice! py-mv-slice)
(import python/struct
  py-struct-module)
(import python/sys
  py-sys-module)
(import python/line
  py-complete py-marks py-paint py-read py-session-name!)
