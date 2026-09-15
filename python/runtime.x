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
(import x/num/tower)
(import x/type/dict)
(import python/util)
(import python/types)
(import python/format)
(import python/bytes)
(import python/str)

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
(include-once "./runtime-seq.x")
(include-once "./runtime-str.x")
(include-once "./runtime-obj.x")
(include-once "./runtime-flow.x")
(include-once "./runtime-call.x")
(include-once "./runtime-type.x")
; the class objects it builds on are in runtime-type.x, so it comes after
(include-once "./collections.x")
