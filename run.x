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

(set! %lang-name "Python")
(set! %lang-version python-version)
(set! %repl-prompt ">>> ")
(set! %repl-print %python-repl-print)
