; # x-python -- Python on x-lang
;
; ## python/base.x -- the language, assembled
;
; @description Python 3: an indentation-delimited, statement-oriented surface
;   over x-lang's evaluator, with a conformance scoreboard behind it.
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
; The internal seams have since appeared -- a tokenizer, an INDENT/DEDENT layer,
; a parser -- and each carries its own specs under tests/specs/.  They do not
; get to be the only thing measured: the conformance suite still presses on
; python-run, because that is the seam a Python program presses on.
;
; ## THE SCOREBOARD CAME FIRST, AND THIS FILE CAME SECOND
;
; `tools/conformance/` turns 682 MicroPython test programs into .spec.md files
; whose expected output is a real CPython 3.14 run, so before a line of
; tokenizer existed there was a sorted list of what Python actually asks for.
; That ordering is why the layers below are the layers they are: the ranked
; groups named the reader as the thing nothing else was reachable without.
;
; This file no longer stubs anything.  `python-run` lexes, parses and evaluates
; -- tokens.x, indent.x, types.x, runtime.x and parse.x, in that order -- and
; what it cannot do it fails at rather than answering uniformly.  The suite
; measures the difference; `make score` ranks what is still red.

(import python/tokens)
(import python/indent)
(import python/types)
(import python/runtime)
(import python/parse)

(provide python/base python-version python-run python-tokenize python-lex python-parse python-parse-expr %python-repl-print)

(def python-version "0.0.1")

; (python-run SRC) -- run a Python program held in a string.
;
; Lex, parse, evaluate.  Returns nil: a Python statement has no value to show
; and `print` writes to stdout itself, so the REPL printer has nothing to say
; about a program that ran.  An expression typed at the prompt is a different
; question, and %python-repl-print below is where it gets answered.
(def python-run
  (fn (_ src)
    (def %go
      (fn (self forms)
        (if (null? forms)
          ()
          (%seq (eval! (first forms)) (self (rest forms))))))
    (%go (python-parse src))))

(def %python-repl-print
  (fn (_ result)
    (unless (null? result) (%seq (write result) (newline)))))
