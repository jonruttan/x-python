; # x-python -- Python on x-lang
;
; ## python/indent.x -- line structure: NEWLINE, INDENT, DEDENT
;
; @description Turns the tokenizer's column-carrying newlines into Python's
;   line-structure tokens, driving x/reader/indent for the stack.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## THE STACK IS NOT HERE, AND THAT IS THE POINT
;
; x-lang#520 pulled the grouping stack out of Logo and x-sweet into
; x/reader/indent, so this file constructs an `Indent` and feeds it columns.
; What it does NOT do is decide what deeper, equal or shallower mean, or count
; how many levels a dedent crossed -- `feed` answers with zero or more `close`
; events followed by exactly one `open` or `same`, and this is a fold over that.
;
; The policy defaults are already Python's, which is why `(Indent make)` takes
; no arguments here: a tab advances to the next multiple of 8, and a dedent
; matching no open level RAISES rather than opening a block there.  That last
; one is Python's `IndentationError: unindent does not match any outer
; indentation level`, and it is the one place the three surfaces genuinely
; disagreed -- Logo opens, x-sweet unwinds, Python refuses.
;
; ## WHAT IS THIS FILE'S OWN, BECAUSE Indent IS SILENT ABOUT IT
;
; Three rules, all of them facts about Python rather than about indentation:
;
;   IMPLICIT LINE JOINING.  Inside (), [] or {} a newline is not line structure
;   at all -- it is whitespace.  So bracket depth is tracked here and newlines
;   are dropped while it is non-zero.  Nothing reaches the indenter, so no
;   INDENT can be opened by a continuation line, which is correct: the column of
;   a continuation line means nothing to the grammar.
;
;   BLANK AND COMMENT-ONLY LINES ARE TRANSPARENT.  A line with no tokens on it
;   produces neither NEWLINE nor INDENT/DEDENT.  Comments are already discarded
;   by the tokenizer, so a comment-only line arrives here as two adjacent
;   newlines and is indistinguishable from a blank one -- which is exactly
;   right, because Python treats them identically.
;
;   LEADING BLANK LINES.  The same rule handles a file that opens with them: no
;   tokens, no line.
;
; The module's own header says blank lines are the caller's business precisely
; because what counts as an empty line is a fact about a surface's comment
; syntax.  This is that caller.

(import x/reader/indent)
(import python/tokens)

(provide python/indent python-lex mk-tok-indent mk-tok-dedent)

(def mk-tok-indent (fn (_) (list (lit tok-indent))))
(def mk-tok-dedent (fn (_) (list (lit tok-dedent))))

; NEVER `first` A NON-PAIR.  x-engine-c#16: (first 2) does not raise, it
; SEGFAULTS -- x_prim_first has no pair check and walks the immediate as a
; pointer. The tokenizer can still hand back a bare value for input its types do
; not fully claim (`0x` reads as the integer 0), and this pass then asked that
; value for its first element and took the interpreter with it.
;
; A non-pair has no token tag, so it gets nil and is treated as a token this
; pass does not recognise -- which is a wrong answer rather than a dead process,
; and a wrong answer is something a spec can catch.
(def %py-tok-type (fn (_ t) (if (pair? t) (first t) ())))

; NO BRACKET DEPTH.  There used to be a counter here, because a newline inside
; brackets is not line structure and this pass had to know when it was inside
; them.  python/tokens.x now reads a bracketed run through the engine's own
; reader loop, so it arrives as ONE token with its contents nested inside -- a
; newline within it never reaches this pass at all, and the counter that had to
; rediscover the nesting is gone.

; feed's events, as tokens.  `same` adds nothing: the line simply continues the
; block already open.
(def %py-events->toks
  (fn (self evs acc)
    (if (null? evs)
      acc
      (self (rest evs)
        (if (eq? (first evs) (lit close))
          (pair (mk-tok-dedent) acc)
          (if (eq? (first evs) (lit open))
            (pair (mk-tok-indent) acc)
            acc))))))

; (python-lex SRC) -- the token stream the parser will read.
;
; Two passes and they are not foldable into one: the decision about a newline
; depends on whether the line it opens turns out to have any tokens on it, which
; is not known until the next newline is seen.  So: walk, buffering the pending
; line's column, and emit only when something lands on the line.
(def python-lex
  (fn (_ src)
    (def ind (Indent make))
    ; pending: the column of a line that has opened but produced no token yet,
    ; or nil when the current line already has content.
    (def %go
      (fn (self toks pending acc)
        (if (null? toks)
          ; End of input.  Any trailing dedents close what is still open; a
          ; pending blank line at the end contributes nothing.
          (List reverse (%py-events->toks (ind close-all) acc))
          (let ((t (first toks)))
            (if (eq? (%py-tok-type t) (lit tok-newline))
              ; A new line opens at this column.  Whether the line that just
              ; ENDED gets a NEWLINE token was already decided when its first
              ; token arrived; a line that never got one was blank.
              (self (rest toks) (first (rest t)) acc)
              ; An ordinary token.  If a line is pending, this is the token that
              ; makes it real: emit its NEWLINE and its INDENT/DEDENTs first.
              (do
                (if (null? pending)
                  (self (rest toks) () (pair t acc))
                  (self (rest toks) ()
                    (pair t
                      (%py-events->toks (ind feed pending)
                        ; NO NEWLINE BEFORE THE FIRST TOKEN.  A file may open
                        ; with blank or comment-only lines, and the line they
                        ; precede is still the module's FIRST logical line --
                        ; nothing ended before it, so there is nothing to
                        ; terminate.  Emitting one here put a stray NEWLINE at
                        ; the head of every file that began with a blank line.
                        (if (null? acc) acc (pair (list (lit tok-newline)) acc))))))))))))
    ; The first line is not preceded by a newline, so it is never pending and
    ; opens no NEWLINE of its own -- which is what Python does: a module's first
    ; logical line is at column 0 and starts no block.
    (%go (python-tokenize src) () ())))
