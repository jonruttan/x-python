; # x-python -- Python on x-lang
;
; ## python/runtime.x -- what Python's operators actually mean
;
; @description The functions the parser emits calls to. Python's operators are
;   not x's, so they get their own names rather than a mapping.  This file
;   is the module: the provide, the imports, and the fragments that carry
;   the definitions.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## ONE MODULE, SEVEN FILES
;
; The definitions were one 6,062-line file, and nothing could analyse it.
; The platform's linter ran 91 seconds on it and the engine died with an
; empty stderr and no verdict -- the analysis-memory limit x-lang#624/#629
; hit on pin.x, reached here first because this was the largest file in
; any bundle.  So a bundle that could not be linted grew its own checker
; instead, which is the duplication the lang kit exists to end.
;
; The split is by SECTION, on the boundaries the file already had, and it
; is a pure move: the fragments concatenated in include order are
; byte-identical to what was here.  Order is load order and is not
; cosmetic -- a forward declaration and its set! can live in different
; fragments, and some defs evaluate as they load.
;
; ## WHY NOT JUST EMIT x's `+`
;
; Because `+` is not the same function. Python's is overloaded across numbers,
; strings, lists and tuples and refuses to mix them -- `1 + "a"` is a TypeError,
; not a coercion -- and `/` always produces a float where x's produces an exact
; rational. A parser that emitted x's operators would be writing a language that
; looks like Python and computes differently, which is the failure mode the lang
; contract calls "a different language wearing the same clothes".
;
; So the parser emits calls to these, and every one of them is a place where a
; Python rule can be stated. Today most of them are thin; that is the point --
; they are named seams, not indirection for its own sake.

; THE LIBRARIES THIS BUNDLE NEEDS, named rather than inherited from a
; dialect.  Python's data model asks for three things helium does not
; carry: ONE arbitrary-precision integer type (2 ** 200 is not an error
; and not a float), true division that always lands on float, and dict
; as syntax.  x/num/tower brings bigint, rational, float and complex;
; x/type/dict is the container.  Declaring them here rather than taking
; the xenon dialect keeps the boot to what this bundle actually uses --
; and keeps the modules loadable one at a time, which is what the
; platform's linter does.
(import python/util)
; the tokenizer's character conversions, which runtime-num.x and
; runtime-call.x read
(import python/tokens %py-hexval %py-int->char %py-list->string)
; A sweep after each load; see python/util.x.  The tower's parts one at a
; time, each swept: imported as one, x/num/tower is the largest load
; between two sweeps by a distance (7.3 GB on x86-64 under x-lang 0.14.0,
; against 1 GB for helium itself).  x/num/tower then finds its parts
; loaded and adds its own generics.
(import x/num/bigint)
(%py-sweep!)
(import x/num/float)
(%py-sweep!)
(import x/num/rational)
(%py-sweep!)
(import x/num/complex)
(%py-sweep!)
(import x/num/decimal)
(%py-sweep!)
(import x/type/generic)
(%py-sweep!)
(import x/num/tower)
(%py-sweep!)
(import x/type/dict)
(%py-sweep!)
(import python/types)
(%py-sweep!)
(import python/format)
(%py-sweep!)
(import python/bytes)
(%py-sweep!)
(import python/str)
(%py-sweep!)

(provide python/runtime
  %py-add %py-sub %py-mul %py-div %py-floordiv %py-mod %py-pow %py-neg
  %py-eq %py-ne %py-lt %py-gt %py-le %py-ge
  %py-print %py-display
  %py-mklist %py-index %py-len %py-list? %py-write %py-getattr %py-setindex
  %py-range %py-iter-elems %py-callcc
  %py-escape %py-wind-push! %py-wind-drop!
  %py-Ellipsis %py-dir %py-cls-bytearray
  %py-raise %py-exc-match %py-exc-match-any
  %py-mkclass %py-setattr %py-super
  %py-str %py-repr-of %py-repr-builtin %py-mklist-of %py-hasattr
  %py-cls-type %py-cls-int %py-cls-float %py-cls-bool %py-cls-str
  %py-cls-list %py-cls-dict %py-cls-tuple %py-cls-NoneType %py-cls-set %py-cls-frozenset
  %py-type-of %py-isinstance %py-truthy %py-slice %py-defg
  %py-exc-Exception %py-exc-ArithmeticError %py-exc-LookupError
  %py-exc-ZeroDivisionError %py-exc-IndexError %py-exc-KeyError
  %py-exc-AttributeError %py-exc-NameError %py-exc-TypeError
  %py-exc-ValueError %py-exc-RuntimeError %py-exc-SyntaxError
  %py-mkdict %py-dict? %py-dget %py-dset
  %py-mktuple %py-tuple? %py-unpack
  %py-pos %py-invert %py-in %py-bitor %py-bitxor %py-bitand
  %py-abs %py-round %py-min %py-max %py-bytearray %py-mkbytes
  %py-cls-complex %py-hash %py-lshift %py-rshift
  %py-NotImplemented %py-exc-StopIteration %py-exc-SystemExit
  %py-splat %py-tuple-of-list %py-fjoin %py-fmtfield %py-format-spec %py-strformat
  %py-chr %py-ord)

; THE FRAGMENTS, in load order.  Order is not cosmetic: forward
; declarations and their set! live in different ones, and some defs
; evaluate at load ((Complex make 0.0 1.0) for one).
(include-once "./runtime-num.x")
(%py-sweep!)
(include-once "./runtime-seq.x")
(%py-sweep!)
(include-once "./runtime-str.x")
(%py-sweep!)
(include-once "./runtime-obj.x")
(%py-sweep!)
(include-once "./runtime-flow.x")
(%py-sweep!)
(include-once "./runtime-call.x")
(%py-sweep!)
(include-once "./runtime-type.x")
(%py-sweep!)
; The standard modules, after runtime-type.x, whose classes they build on.
; Each is a module of its own; the names the runtime's files read of one are
; bound here in the root by a selective import, where those files read them.
(import python/collections %py-collections-module)
(%py-sweep!)
(import python/deque
  %py-cls-deque %py-dq-at %py-dq-attr %py-dq-cat %py-dq-del! %py-dq-eq
  %py-dq-extend! %py-dq-put! %py-dq-repeat %py-dq-repr)
(%py-sweep!)
(import python/array
  %py-arr-at %py-arr-attr %py-arr-buffer %py-arr-cat %py-arr-el %py-arr-is
  %py-arr-put! %py-array-module %py-cls-array %py-ieee-2p63 %py-ieee-raw
  %py-take-n)
(%py-sweep!)
(import python/memoryview
  %py-buffer-bytes %py-buffer-text %py-buffer? %py-cls-memoryview %py-mv-at
  %py-mv-attr %py-mv-elems %py-mv-in %py-mv-is %py-mv-len %py-mv-put!
  %py-mv-setslice! %py-mv-slice)
(%py-sweep!)
(import python/struct %py-struct-module)
(%py-sweep!)
(import python/io
  %py-cls-BytesIO %py-cls-StringIO %py-io-attr %py-io-drain! %py-io-is
  %py-io-module %py-io-text?)
(%py-sweep!)
(import python/sys %py-implementation-version %py-sys-module)
(%py-sweep!)
