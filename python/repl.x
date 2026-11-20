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
; and the byte reader when there is not.
;
; WHAT ECHOES.  CPython echoes the repr of an EXPRESSION statement's value and
; nothing else -- an assignment is silent even though our emitted set! has a
; value.  The parse result's structure says which is which: statement emissions
; lead with set!/def/let/guard/if or a loop-call, and everything else is an
; expression.  That inspection lives here because it is a REPL rule, not a
; language rule.
;
; BLOCKS END ON A BLANK LINE, CPython's own interactive convention: a line
; ending with `:` switches to "... " prompts and accumulates until an empty
; line closes the entry.

(module python/core)
(import x/sys/posix)
; Catalog fetches, once at load.
(def %py-repl-cvt (prim-ref (lit convert) (lit to)))
(import x/core/doors char->int)
(def %py-repl-str-t ((prim-ref (lit type) (lit of)) "s"))

; --- one line from stdin, or 'eof --------------------------------------------
(def python-repl-line ())
(set! python-repl-line
  (fn (_)
    ; Chars accumulate as CHARS and convert to a string in ONE cvt at the end
    ; -- the list-to-string conversion python/tokens.x already relies on.  A
    ; per-char char-to-string cvt answered nil silently, and every line read
    ; as empty: two prompts per line and nothing evaluated, ever.
    (def %line-of
      (fn (_ acc)
        (if (null? acc) "" (%py-repl-cvt (python-reverse acc) %py-repl-str-t))))
    (def go
      (fn (self acc)
        (let ((c (Io read-char)))
          (if (null? c)
            (if (null? acc) (lit eof) (%line-of acc))
            (if (= (char->int c) 10)
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

(def python-banner
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
; %py-acc, and/or bind %py-lhs -- and the expression variant MUST echo:
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
          ((eq? h (lit %py-hoist)) #t)
          ((eq? h (lit let)) (%py-stmt-let? form))
          ((eq? h (lit guard)) #t)
          ((eq? h (lit if)) #t)
          ((eq? h (lit error)) #t)
          ; the while/for emission: a call whose head is an (fn ...) form
          ((pair? h) (eq? (first h) (lit fn)))
          (#t #f))))))

; A line's forms are evaluated in the root, as a program's are in its own
; environment (python/base.x): a name one line binds is there for the next,
; and at x's prompt too, which is what lets one session hold both.
; The prompt's lines are evaluated in an environment of their own that hangs
; from the core's, so the forms the parser builds, which name the core's
; helpers, resolve there; a name a line binds is then published in the root,
; so x's prompt calls it by its prefixed name, as it always could.
(def %py-prompt-env (pair () %py-base-env))
(def %py-publish-prompt-names!
  (fn (self forms)
    (unless (null? forms)
      (%seq
        (let ((f (first forms)))
          (if (if (pair? f)
                (match ((eq? (first f) (lit set!)) #t) ((eq? (first f) (lit def)) #t)
                       (#t (eq? (first f) (lit %py-hoist))))
                #f)
            (let ((sym (first (rest f))))
              (if (if (symbol? sym) (%py-env-has? %py-prompt-env sym) #f)
                (%py-env-def! (%py-root %py-prompt-env) sym (eval sym %py-prompt-env))
                ()))
            ()))
        (self (rest forms))))))
(def %py-repl-eval
  (fn (_ src)
    (def go
      (fn (self forms last)
        (if (null? forms)
          last
          (let ((v (eval (first forms) %py-prompt-env)))
            (self (rest forms)
              (if (%py-stmt-form? (first forms)) () v))))))
    (def forms (python-parse src))
    (%py-repl-names! forms)
    (let ((v (go forms ())))
      (%py-publish-prompt-names! forms)
      (unless (null? v) (%seq (%py-write v) (newline))))))

; Remembered for Tab: a name a line binds at its top level, a (set! SYM V) --
; which a def is too (python/parse.x, %py-stmt-binds) -- or a (def SYM V),
; completes on the next.
(def %py-repl-names!
  (fn (self forms)
    (if (null? forms)
      ()
      (%seq
        (let ((f (first forms)))
          (if (if (pair? f) (match ((eq? (first f) (lit set!)) #t) (#t (eq? (first f) (lit def)))) #f)
            (guard (_ ()) (python-session-name! (symbol->str (first (rest f)))))
            ()))
        (self (rest forms))))))

(python-sweep!)
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
            ((eq? line (lit eof)) (python-reverse acc))
            ((= (Str8 length line) 0) (python-reverse acc))
            (#t (self (pair line acc)))))))
    (if (%py-opens-block? first-line)
      (let ((lines (go (list first-line))))
        (if (eq? lines (lit cancel)) lines (Str8 join "\n" lines)))
      first-line)))

; --- where an entry failed ---------------------------------------------------
;
; An error is reported against the entry that raised it, in the layout of a
; CPython traceback's last frame: the line the entry began on, its text, and
; a caret under each character of it, ahead of the error's own line.  The
; entry is the whole of what is known: a token carries no position and an
; emitted form no line.  So an entry of one line is marked, and a block is
; shown by its header with no carets, since they would point at a line that
; may not be the one that failed.
;
; Lines are counted where they are read with no editor -- a program on
; standard input -- so the number is the program's own.  An entry typed at
; the editor is line 1, as each is at CPython's prompt.
(def %py-lines-read (pair 0 ()))
(def %py-entry-line (pair 1 ()))
(def %py-entry-now (pair "" ()))

(def %py-read-counted
  (fn (_ prompt)
    (let ((line (python-read prompt)))
      (if (if (symbol? line) #f (not (guard (_ #f) (Line available?))))
        (%set-first! %py-lines-read (+ (first %py-lines-read) 1))
        ())
      line)))

; An entry begins: its first line, and the line it is on.
(def %py-entry-begin!
  (fn (_ line)
    (%set-first! %py-entry-now line)
    (%set-first! %py-entry-line
      (if (= (first %py-lines-read) 0) 1 (first %py-lines-read)))))

; Past the last byte of S's first N that is not a blank or a carriage return.
(def %py-text-end
  (fn (self s n)
    (if (> n 0)
      (let ((b (python-code-at s (- n 1))))
        (if (match ((= b 32) #t) ((= b 9) #t) (#t (= b 13))) (self s (- n 1)) n))
      0)))

; The characters in bytes I to N of S: every byte but a UTF-8 continuation.
(def %py-chars
  (fn (self s i n acc)
    (if (>= i n)
      acc
      (let ((b (python-code-at s i)))
        (self s (+ i 1) n (if (if (>= b 128) (< b 192) #f) acc (+ acc 1)))))))

(def %py-carets
  (fn (self n acc) (if (> n 0) (self (- n 1) (Str8 append acc "^")) acc)))

(def %py-entry-report
  (fn (_ entry)
    (let ((nl (Str8 index-of "\n" entry)))
      (let ((text (if (null? nl) entry (Str8 sub 0 nl entry))))
        (let ((n (%py-text-end text (python-byte-len text))))
          (let ((i (%py-past-blanks text 0 n)))
            (do
              (display "  File \"<stdin>\", line ")
              (display (first %py-entry-line))
              (newline)
              (display "    ")
              (display (Str8 sub i (- n i) text))
              (newline)
              (if (null? nl)
                (do
                  (display "    ")
                  (display (%py-carets (%py-chars text i n 0) ""))
                  (newline))
                ()))))))))

; What both loops print for an error: where, then what.  A report that
; cannot be drawn does not take the error's own line with it.
(def %py-entry-error
  (fn (_ err)
    (do
      (guard (_ ()) (%py-entry-report (first %py-entry-now)))
      (display "Error: ")
      (display err)
      (newline))))

; One entry, from its first line: the rest of it read, then evaluated, and
; an error from either reported where the entry is (%py-entry-error).
(def %py-entry-run
  (fn (_ line more)
    (do
      (%py-entry-begin! line)
      (guard (%py-err (%py-entry-error %py-err))
        (let ((entry (%py-read-entry line more)))
          (unless (eq? entry (lit cancel))
            (do
              (%set-first! %py-entry-now entry)
              (%py-repl-eval entry))))))))

; The loop's own way to the next line: the editor when there is a terminal,
; the byte reader otherwise (python/line.x), the prompt drawn either way.
(def %py-more-from-loop
  (fn (_) (%py-read-counted "... ")))

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
    (let ((line (%py-read-counted ">>> ")))
      (match
        ((eq? line (lit eof)) (%seq (newline) (Sys exit 0)))
        ; ctrl-c abandons the line being typed.
        ((eq? line (lit cancel)) (%python-repl-loop))
        ((= (Str8 length line) 0) (%python-repl-loop))
        ((if (Str8 =? line "quit()") #t (Str8 =? line "exit()"))
          (Sys exit 0))
        (#t
          (%seq
            (%py-entry-run line %py-more-from-loop)
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
      (#t (%py-entry-run line %py-more-from-editor)))))

; Python's own spelling of the switch: lang("x").  The name arrives as a
; Python str, code points, and Lang wants bytes.
(def py-lang
  (fn (_ name)
    (Lang use! (if (python-str-is name) (ps->x (python-str-cps name)) name))
    ()))

; Register "python": what the line means, how it is coloured, what Tab
; offers.  Registration is the whole of what the editor needs to switch to
; it; the seams themselves are set by use!, and nothing reads them in a batch.
(def python-repl-register!
  (fn (_)
    (Lang register! "python"
      (list (pair (lit %repl-prompt) ">>> ")
            (pair (lit %repl-prompt-more) "... ")
            (pair (lit %repl-print) python-repl-print)
            (pair (lit %repl-paint) python-paint)
            (pair (lit %repl-marks) python-marks)
            (pair (lit %repl-complete) python-complete)
            (pair (lit %repl-eval-line) %py-eval-line)))))

; Register, and make it the session's lang.
(def python-repl-install!
  (fn (_)
    (python-repl-register!)
    (Lang use! "python")))

; Whether this bundle owns the prompt.  `-l` is repeatable, and a bundle
; named by a second or later -l is loaded beside the first lang: the wrapper
; emits %lang-lead, the first name, and a bundle whose name it is not
; registers itself and leaves the prompt alone.  A wrapper older than the
; seam binds nothing, and then this bundle leads, as it always did.
(def python-leads?
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
(def python-repl-choose!
  (fn (_)
    (when (python-leads?)
      (unless (guard (_ #f) %image-writing)
        (unless (if (Sys isatty 0) #t (Sys isatty 3))
          (set! repl %python-repl))))))
(set! %image-recache-hooks (pair (fn (_) (python-repl-choose!)) %image-recache-hooks))

