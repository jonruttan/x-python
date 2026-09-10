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

(provide python/base python-version python-run python-tokenize python-lex python-parse python-parse-expr %python-repl-print
  %py-eval %py-exec %py-compile)

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
    ; raise SystemExit ends the program QUIETLY; anything else uncaught
    ; travels on to whoever ran the program
    (guard (e (if (%py-exc-match e %py-exc-SystemExit) () (error e)))
      (%go (python-parse src)))))

; --- eval, exec, compile -----------------------------------------------------
;
; The language re-entering itself.  All three are the two steps python-run
; already takes -- parse, then eval! -- so they live HERE, where both halves
; are in scope; python/runtime.x cannot see the parser, and nothing else can
; see both.
;
; ONE NAMESPACE, AND IT SAYS SO.  Python's eval and exec take globals and
; locals mappings and run the source in them.  A Python name here is an x
; global: there is no dictionary standing for a scope and nothing to swap one
; for, so a mapping argument is REFUSED rather than ignored -- ignoring it
; would run the code in the wrong scope and answer with confidence.  `None`
; means "the one you are in", which is the only one there is, so it passes.
(def %py-ns-refuse
  (fn (self ns who)
    (if (null? ns)
      ()
      (if (null? (first ns))
        (self (rest ns) who)
        (Err raise (lit type)
          (Str8 append who "() with a globals or locals mapping is not supported here")
          ())))))

; A CODE OBJECT is what compile() answers and what eval and exec take beside a
; string: the forms, already parsed, and the mode they were parsed in.
(def %py-code-new  (fn (_ mode forms) (list (lit %py-code) mode forms)))
(def %py-code-is   (fn (_ v) (if (pair? v) (eq? (first v) (lit %py-code)) #f)))
(def %py-code-forms (fn (_ c) (first (rest (rest c)))))

; Source to forms.  `eval` mode is ONE EXPRESSION -- python-parse-expr answers
; (form . rest) and the rest is the newline that ended it.
(def %py-code-of
  (fn (_ src mode)
    (match
      ((%py-code-is src) (%py-code-forms src))
      ((not (str? src))
        (Err raise (lit type) "eval()/exec() wants a string or a code object" ()))
      ((Str8 =? mode "eval") (list (first (python-parse-expr (python-lex src)))))
      (#t (python-parse src)))))

(def %py-code-run
  (fn (self forms last)
    (if (null? forms)
      last
      (self (rest forms) (eval! (first forms))))))

(def %py-eval
  (%py-sig!
    (fn (_ src . ns)
      (%seq (%py-ns-refuse ns "eval")
        (%py-code-run (%py-code-of src "eval") ())))
    "eval" (list "source" "globals" "locals") 1 #f))

; exec ANSWERS None however much the source evaluated to, which is why the
; value is dropped here rather than never taken.
(def %py-exec
  (%py-sig!
    (fn (_ src . ns)
      (%seq (%py-ns-refuse ns "exec")
        (%seq (%py-code-run (%py-code-of src "exec") ()) ())))
    "exec" (list "source" "globals" "locals") 1 #f))

; `single` is `exec` here: the mode is about echoing a value at a prompt, and
; this compiles rather than prompts.  A mode that is none of the three is a
; ValueError, as it is in Python.
(def %py-compile
  (%py-sig!
    (fn (_ src file mode)
      (if (if (Str8 =? mode "exec") #t (if (Str8 =? mode "eval") #t (Str8 =? mode "single")))
        (%py-code-new mode (%py-code-of src mode))
        (Err raise (lit value)
          "compile() mode must be 'exec', 'eval' or 'single'" ())))
    "compile" (list "source" "filename" "mode") 3 #f))

(def %python-repl-print
  (fn (_ result)
    (unless (null? result) (%seq (write result) (newline)))))
