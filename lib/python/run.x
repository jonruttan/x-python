; # x-python -- Python on x-lang
;
; ## lib/python/run.x -- the entry
;
; @description Python 3: indentation is grouping, statements are not
;   expressions, and one integer type goes all the way up.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; Usage:
;   x -l python                 interactive
;   x -l python -f prog.py      batch
;
; This file contains no path literals.  x.sh boots the dialect bundle.xon
; declares, arms this bundle's lib/ with import-path!, imports this module
; and calls its main, and appends the launcher when no -f was given.  So
; `import python/base` resolves against the bundle wherever it sits.
;
; Importing this module sets Python up and starts nothing; main starts it.
; A sweep after each load; see python/util.x.
;
; The launcher runs (%banner) then (repl).  The banner is replaced.  The loop
; is kept where there is a terminal: the platform's line editor reads the
; line, and python/repl.x registers what the line means, how it is coloured
; and what Tab offers as the lang "python" (x/repl/lang), so the session
; has editing and history, and can switch to x-lang's prompt and back.
; Without a terminal the platform loop would read sexps through the ambient
; reader -- no prompt string changes what a reader is -- so python/repl.x's
; own loop replaces it.
; Which of the two is a fact of the process, so the choice is remade after
; a state image loads; see python-repl-choose! in python/repl.x.
;
; All of that only when this bundle leads.  `-l` is repeatable, and named
; second (`x -l xe -l python`) this bundle is a library to the lang that
; owns the prompt: it registers "python" so (lang python) can switch to it,
; and touches neither the banner nor the loop.

(module python/run)
(import python/core python-banner python-batch python-leads? python-repl-install! python-repl-choose! python-repl-register! python-sweep!)
(python-sweep!)
(if (python-leads?)
  (do
    (set! %banner python-banner)
    (python-repl-install!)
    (python-repl-choose!))
  (python-repl-register!))

; With a file (-f), x.sh puts the program's text on the stream after the
; call of main and binds %batch?, and the platform's batch loop would read it
; as x-lang: python-batch reads it instead, runs it, and exits.  The image
; writer imports this module and never calls main, so nothing here needs to
; ask whether an image is being written.
(def main
  (fn (_)
    (when (python-leads?)
      (when (guard (_ #f) %batch?) (python-batch)))))

(provide python/run main)
