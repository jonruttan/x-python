; # x-python -- Python on x-lang
;
; ## python/indent.x -- there is no indentation pass any more
;
; @description Kept as the module that names python-lex, which is now what the
;   reader already produced.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; THIS FILE USED TO BE A PASS.  It walked the flat token stream, drove an
; `Indent` stack with each line's column, and spliced INDENT/DEDENT/NEWLINE
; tokens into the result.  It also carried a bracket depth counter, because a
; newline inside brackets is not line structure, and a `pending` column,
; because a blank line has a column too and must not open a block.
;
; None of that is here now, and none of it moved -- it stopped being needed.
; python/tokens.x reads a bracketed run and an indented run through the
; engine's own reader loop, so both arrive already nested, and a blank or
; comment-only line is refused by an analyser that can see the character after
; the indentation.  What is left is a name.

(import python/tokens)

(provide python/indent python-lex)

; The reader has already done it.
(def python-lex (fn (_ src) (python-tokenize src)))
