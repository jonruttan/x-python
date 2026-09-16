; # x-python -- Python on x-lang
;
; ## python/repl.x -- the interactive session, reading PYTHON
;
; @description The >>> prompt.  Reads lines, parses them as Python, evaluates,
;   and echoes expression values the way CPython's REPL does.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; THE PLATFORM REPL READS SEXPS, AND NO PROMPT BANNER CHANGES THAT.  Its loop
; customizes prompt and print only; the read is the ambient reader.  So with
; run.x setting nothing but those, `print('hi')` answered "Unbound SYMBOL
; 'print" and `1 + 2` evaluated as three forms across three prompts.  What
; reads Python is here: a line (a block, when it opens one), python-parse,
; eval, echo.
;
; Two ways in.  With a terminal, the platform's line editor reads the line
; and hands it to %repl-eval-line; %py-eval-line is that seam's Python
; answer, and with the painter, the marks and the completer of python/line
; it is registered as the lang "python" (x/repl/lang), so the editor's
; history, keys and colour are Python's for free and a session can switch
; between this prompt and x-lang's.  Otherwise %python-repl replaces the
; loop and reads for itself, through the editor when there is one to drive
; and the byte reader when there is not.  On a platform older than
; x/repl/lang only the second way exists.
;
; WHAT ECHOES.  CPython echoes the repr of an EXPRESSION statement's value and
; nothing else -- an assignment is silent even though our emitted set! has a
; value.  The parse result's shape says which is which: statement emissions
; lead with set!/def/let/guard/if or a loop-call, and everything else is an
; expression.  That inspection lives here because it is a REPL rule, not a
; language rule.
;
; BLOCKS END ON A BLANK LINE, CPython's own interactive convention: a line
; ending with `:` switches to "... " prompts and accumulates until an empty
; line closes the entry.

(import python/util)
(import python/base)
(import python/line)
(import x/sys/posix)
; Catalog fetches, once at load.
(def %py-repl-cvt (prim-ref (lit convert) (lit to)))
(def %py-repl-ch->int (prim-ref (lit char) (lit ->int)))
(def %py-repl-str-t ((prim-ref (lit type) (lit of)) "s"))

; --- one line from stdin, or 'eof --------------------------------------------
(def %py-repl-line ())
(set! %py-repl-line
  (fn (_)
    ; Chars accumulate as CHARS and convert to a string in ONE cvt at the end
    ; -- the list-to-string conversion python/tokens.x already relies on.  A
    ; per-char char-to-string cvt answered nil silently, and every line read
    ; as empty: two prompts per line and nothing evaluated, ever.
    (def %line-of
      (fn (_ acc)
        (if (null? acc) "" (%py-repl-cvt (%py-reverse acc) %py-repl-str-t))))
    (def go
      (fn (self acc)
        (let ((c (Io read-char)))
          (if (null? c)
            (if (null? acc) (lit eof) (%line-of acc))
            (if (= (%py-repl-ch->int c) 10)
              (%line-of acc)
              (self (pair c acc)))))))
    (go ())))

; --- the banner --------------------------------------------------------------
;
; The versions arrive as BOOT DATA, not file reads: x.sh emits %param-release
; (the engine's, from x-engine-build.xon beside the binary) and
; %platform-release (x-lang's, from the install's contract/release).  A
; checkout emits no platform release, and an older x.sh emits neither -- so
; every lookup is guarded and the banner degrades to what it knows.  The root
; line stays unconditional: WHICH tree answered is the diagnostic that solves
; the which-install-am-I-running confusion this banner exists to prevent.

(def %py-repl-global
  (fn (_ form) (guard (%py-e ()) (eval! form))))

(def %python-banner
  (fn (_)
    (display "Python v" python-version " on x-lang")
    (let ((rel (%py-repl-global (lit %platform-release))))
      (unless (null? rel) (display " " rel)))
    (let ((er (%py-repl-global (lit %param-release))))
      (unless (null? er) (display ", engine " er)))
    (newline)
    (let ((root (%py-repl-global (lit %install-root))))
      (unless (null? root) (%seq (display "root " root) (newline))))
    (display "quit() or ctrl-d to exit")
    (newline)))

; --- what echoes -------------------------------------------------------------
; `let` needs a second look: the parser emits it for BOTH tuple-unpacking
; statements (binding %py-unpacked) and for expressions -- comprehensions bind
; %py-acc, and/or bind %py-lhs -- and the expression kind MUST echo:
; `[n * n for n in range(4)]` at the prompt answers a list in CPython.
(def %py-stmt-let?
  (fn (_ form)
    (let ((b (first (rest form))))
      (if (if (pair? b) (pair? (first b)) #f)
        (eq? (first (first b)) (lit %py-unpacked))
        #f))))

(def %py-stmt-form?
  (fn (_ form)
    (if (not (pair? form))
      #f
      (let ((h (first form)))
        (match
          ((eq? h (lit set!)) #t)
          ((eq? h (lit def)) #t)
          ((eq? h (lit %py-defg)) #t)
          ((eq? h (lit let)) (%py-stmt-let? form))
          ((eq? h (lit guard)) #t)
          ((eq? h (lit if)) #t)
          ((eq? h (lit error)) #t)
          ; the while/for emission: a call whose head is an (fn ...) form
          ((pair? h) (eq? (first h) (lit fn)))
          (#t #f))))))

(def %py-repl-eval
  (fn (_ src)
    (def go
      (fn (self forms last)
        (if (null? forms)
          last
          (let ((v (eval! (first forms))))
            (self (rest forms)
              (if (%py-stmt-form? (first forms)) () v))))))
    (let ((v (go (%py-repl-lift (python-parse src)) ())))
      (unless (null? v) (%seq (%py-write v) (newline))))))

; A top-level (def SYM V) in a parsed line binds at THIS LOOP'S depth and
; vanishes -- `def f(): ...` then `f(41)` answered NameError.  Rewritten
; through the same base/def-global door the hoists use, a definition made at
; the prompt is a definition.
(def %py-repl-lift
  (fn (self forms)
    (if (null? forms)
      ()
      (pair
        (let ((f (first forms)))
          (if (if (pair? f) (eq? (first f) (lit def)) #f)
            (do
              ; Remembered for Tab: a name defined on one line completes on
              ; the next.
              (guard (_ ())
                (set! %py-session-names
                  (pair (symbol->str (first (rest f))) %py-session-names)))
              (list (lit %py-defg)
                (list (lit lit) (first (rest f)))
                (first (rest (rest f)))))
            f))
        (self (rest forms))))))

; --- block accumulation ------------------------------------------------------
(def %py-opens-block?
  (fn (_ line)
    (let ((n (Str8 length line)))
      (if (= n 0) #f (Str8 =? (Str8 sub (- n 1) 1 line) ":")))))

; The whole entry, given its first line and a way to read the next: `more`
; answers a string, 'eof to close the block with what there is, or 'cancel to
; abandon the entry, which is then this function's answer too.  The byte
; loop's `more` prints its own "... " and reads stdin; the editor's reads an
; edited line under %repl-prompt-more.
(def %py-read-entry
  (fn (_ first-line more)
    (def go
      (fn (self acc)
        (let ((line (more)))
          (match
            ; ctrl-c mid-block abandons the whole entry.
            ((eq? line (lit cancel)) (lit cancel))
            ((eq? line (lit eof)) (%py-reverse acc))
            ((= (Str8 length line) 0) (%py-reverse acc))
            (#t (self (pair line acc)))))))
    (if (%py-opens-block? first-line)
      (let ((lines (go (list first-line))))
        (if (eq? lines (lit cancel)) lines (Str8 join "\n" lines)))
      first-line)))

; The loop's own way to the next line: the editor when there is a terminal,
; the byte reader otherwise (python/line.x), the prompt drawn either way.
(def %py-more-from-loop
  (fn (_) (%py-read "... ")))

; --- the loop ----------------------------------------------------------------
(def %python-repl ())
(set! %python-repl
  (fn (_)
    ; FIRST CALL: reclaim terminal stdin from fd 3, exactly as the platform
    ; loop does.  x.sh parks the user's stdin there while the boot stream
    ; occupies fd 0 -- a loop that skips this reads the EXHAUSTED boot pipe
    ; and every line arrives as EOF.  Measured: prompts with nothing ever
    ; evaluated, twice per session.
    (guard (%py-e ()) (do (Sys dup2 3 0) (Sys close 3)))
    (%python-repl-loop)))

(def %python-repl-loop ())
(set! %python-repl-loop
  (fn (_)
    ; Through the line editor when there is a terminal (python/line.x),
    ; which draws the prompt itself; through the byte reader otherwise.
    (let ((line (%py-read ">>> ")))
      (match
        ((eq? line (lit eof)) (%seq (newline) (Sys exit 0)))
        ; ctrl-c abandons the line being typed.
        ((eq? line (lit cancel)) (%python-repl-loop))
        ((= (Str8 length line) 0) (%python-repl-loop))
        ((if (Str8 =? line "quit()") #t (Str8 =? line "exit()"))
          (Sys exit 0))
        (#t
          (%seq
            (guard (%py-err
                (%seq
                  (display "Error: ")
                  (%seq
                    (display (if (str? %py-err) %py-err (Io write-to-str %py-err)))
                    (newline))))
              (let ((entry (%py-read-entry line %py-more-from-loop)))
                (unless (eq? entry (lit cancel)) (%py-repl-eval entry))))
            (%python-repl-loop)))))))

; --- the editor's way in -----------------------------------------------------
;
; %repl-eval-line's Python answer: the editor has read one line and asks what
; it means.  A block reads its remaining lines the same way, under the "... "
; prompt; ctrl-d there closes the block with what there is and ctrl-c
; abandons the entry, the two answers they give on the first line.  Errors
; print as the byte loop prints them, so a session reads the same either way
; in.  quit() and exit() are the two spellings of ctrl-d.
(def %py-more-from-editor
  (fn (_) (Line read %repl-prompt-more)))

(def %py-eval-line
  (fn (_ line)
    (match
      ((= (Str8 length line) 0) ())
      ((if (Str8 =? line "quit()") #t (Str8 =? line "exit()")) (Sys exit 0))
      (#t
        (let ((entry (%py-read-entry line %py-more-from-editor)))
          (unless (eq? entry (lit cancel))
            (guard (%py-err
                (%seq
                  (display "Error: ")
                  (%seq
                    (display (if (str? %py-err) %py-err (Io write-to-str %py-err)))
                    (newline))))
              (%py-repl-eval entry))))))))

; Whether the platform has x/repl/lang -- the registry and the seams behind
; it arrived together, after v0.14.0.  Older platforms get the byte loop.
(def %py-lang?
  (fn (_) (guard (_ #f) (do Lang #t))))

; Python's own spelling of the switch: lang("x").  The name arrives as a
; Python str, code points, and Lang wants bytes.
(def py-lang
  (fn (_ name)
    (Lang use! (if (%py-str-is name) (%ps->x (%py-str-cps name)) name))
    ()))

; Register "python": what the line means, how it is coloured, what Tab
; offers.  Registration is the whole of what the editor needs to switch to
; it; the seams themselves are set by use!, and nothing reads them in a batch.
(def %py-repl-register!
  (fn (_)
    (when (%py-lang?)
      (Lang register! "python"
        (list (pair (lit %repl-prompt) ">>> ")
              (pair (lit %repl-prompt-more) "... ")
              (pair (lit %repl-print) %python-repl-print)
              (pair (lit %repl-paint) %py-paint)
              (pair (lit %repl-marks) %py-marks)
              (pair (lit %repl-complete) %py-complete)
              (pair (lit %repl-eval-line) %py-eval-line))))))

; Register, and make it the session's lang.
(def %py-repl-install!
  (fn (_)
    (when (%py-lang?)
      (%py-repl-register!)
      (Lang use! "python"))))

; Whether this bundle owns the prompt.  `-l` is repeatable, and a bundle
; named by a second or later -l is loaded beside the first lang: the wrapper
; emits %lang-lead, the first name, and a bundle whose name it is not
; registers itself and leaves the prompt alone.  A wrapper older than the
; seam binds nothing, and then this bundle leads, as it always did.
(def %py-leads?
  (fn (_) (guard (_ #t) (str=? %lang-lead "python"))))

; Which loop the session gets is a fact of the process -- whether there is a
; terminal -- and a state image is written by a child with a pipe for stdin,
; so a choice made in the writer would be the wrong one for a session at a
; tty and would sit in the image.  The choice is therefore a function, made
; at boot and again by the recache hook once an image has loaded, and not
; made at all while the image is being written: the writer's child leaves
; the platform loop in place, the loaded session decides for itself.  The
; terminal is on fd 3 while the boot stream occupies fd 0, which is why both
; are asked; the editor's own install asks the same two.
(def %py-repl-choose!
  (fn (_)
    (when (%py-leads?)
      (unless (guard (_ #f) %image-writing)
        (unless (if (%py-lang?) (if (Sys isatty 0) #t (Sys isatty 3)) #f)
          (set! repl %python-repl))))))
(set! %image-recache-hooks (pair (fn (_) (%py-repl-choose!)) %image-recache-hooks))

(provide python/repl %python-repl %python-banner %py-eval-line
  %py-repl-register! %py-repl-install! %py-repl-choose! %py-lang? %py-leads?)
