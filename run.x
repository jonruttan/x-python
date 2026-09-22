; # x-python -- Python on x-lang
;
; ## run.x -- THE entry
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
; THIS FILE KNOWS NO PATHS.  x.sh boots the dialect lang.xon declares, arms
; this bundle's root with import-path!, cats this file, and appends the
; launcher when no -f was given.  So `import python/base` resolves against the
; bundle wherever it happens to sit.  That is the whole of the arrangement,
; and it is the part the 2024 generation did not have.
(import python/base)
; A sweep after each load; see python/util.x.
(%py-sweep!)
(import python/repl)
(%py-sweep!)
(import python/line)
(%py-sweep!)

; The launcher runs (%banner) then (repl).  The banner is replaced.  The loop
; is kept where there is a terminal: the platform's line editor reads the
; line, and python/repl.x registers what the line means, how it is coloured
; and what Tab offers as the lang "python" (x/repl/lang), so the session
; has editing and history, and can switch to x-lang's prompt and back.
; Without a terminal the platform loop would read sexps through the ambient
; reader -- no prompt string changes what a reader is -- so python/repl.x's
; own loop replaces it.  On a platform older than x/repl/lang that loop is
; the only loop, and reads through the editor itself when there is one.
; Which of the two is a fact of the process, so the choice is remade after
; a state image loads; see %py-repl-choose! in python/repl.x.
;
; All of that only when this bundle leads.  `-l` is repeatable, and named
; second (`x -l xe -l python`) this bundle is a library to the lang that
; owns the prompt: it registers "python" so (lang python) can switch to it,
; and touches neither the banner nor the loop.
(if (%py-leads?)
  (do
    (set! %banner %python-banner)
    (%py-repl-install!)
    (%py-repl-choose!))
  (%py-repl-register!))
