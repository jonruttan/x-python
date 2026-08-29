; # x-python -- Python on x-lang
;
; ## python/base.x -- the language, assembled
;
; @description Python 3: an indentation-delimited, statement-oriented surface
;   over x-lang's evaluator.  Today it is a stub with a scoreboard behind it.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; No path literals and no dialect boot here: run.x owns both.  Nothing under
; py/ includes a platform module -- re-including one on a booted tower is a
; SEGFAULT with no diagnostic (x-lang#515), and it is the first thing anyone
; assembling a bundle hits.
;
; ## THE ENTRY POINT IS ONE FUNCTION, AND THAT IS ON PURPOSE
;
; `(python-run SRC)` takes a whole Python program as a string, runs it, and lets
; whatever it printed go to stdout.  Not `py-tokenize`, not `py-parse`: the
; suite this bundle is built against is 682 whole programs compared on their
; stdout, so the seam the specs press on had better be the seam the suite
; presses on.  x-ash spec'd `sh-tokenize` and can tell you its token list is
; right while `'a'` still loses its accumulator; that is a lesson, not a model.
;
; Internal seams will appear -- a tokenizer on its own base, an INDENT/DEDENT
; layer, a parser -- and they get their own specs when they exist.  They do not
; get to be the only thing measured.
;
; ## WHY THIS FILE IS A STUB
;
; The scoreboard came first, deliberately.  `tools/conformance/` turns 682
; MicroPython test programs into .spec.md files whose expected output is a real
; CPython 3.14 run, so before a line of tokenizer exists there is a sorted list
; of what Python actually asks for.  A stub that answers everything the same way
; scores 0, and 0 against a suite that runs is worth more than a green suite of
; six hand-picked cases.
;
; The stub prints rather than staying silent.  A silent stub would PASS every
; conformance case whose program prints nothing -- a handful of them do -- and a
; scoreboard that starts above zero for that reason is lying about the port
; before it has begun.

(import python/tokens)

(provide python/base python-version python-run python-tokenize %python-repl-print)

(def python-version "0.0.1")

; The marker is deliberately not valid Python output and deliberately one line:
; it shows up once per unimplemented program in a spec diff, which reads as a
; column rather than as noise.
(def %python-not-implemented "#<python: not implemented>")

; (python-run SRC) -- run a Python program held in a string.
;
; Returns nil.  A Python statement has no value to show, and `print` writes to
; stdout itself, so the REPL printer below has nothing to say about a program
; that ran.  An expression typed at the prompt is a different question and gets
; answered when there is an evaluator to answer it with.
(def python-run
  (fn (_ src)
    (%seq (display %python-not-implemented) (%seq (newline) ()))))

; Python shows `None` as nothing at the prompt and everything else with repr().
; Until there are values, the printer's whole job is to stay out of the way --
; python-run has already written what there was to write.
(def %python-repl-print
  (fn (_ result)
    (unless (null? result) (%seq (write result) (newline)))))
