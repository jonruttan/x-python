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
; 'print" and `1 + 2` evaluated as three forms across three prompts.  This file
; replaces the LOOP: read a line (a block, when it opens one), python-parse,
; eval, echo.
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

(import python/base)
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
        (if (null? acc) "" (%py-repl-cvt (List reverse acc) %py-repl-str-t))))
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
        (if (eq? h (lit set!)) #t
        (if (eq? h (lit def)) #t
        (if (eq? h (lit %py-defg)) #t
        (if (eq? h (lit let)) (%py-stmt-let? form)
        (if (eq? h (lit guard)) #t
        (if (eq? h (lit if)) #t
        (if (eq? h (lit error)) #t
          ; the while/for emission: a call whose head is an (fn ...) form
          (if (pair? h) (eq? (first h) (lit fn)) #f))))))))))))

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
            (list (lit %py-defg)
              (list (lit lit) (first (rest f)))
              (first (rest (rest f))))
            f))
        (self (rest forms))))))

; --- block accumulation ------------------------------------------------------
(def %py-opens-block?
  (fn (_ line)
    (let ((n (Str8 length line)))
      (if (= n 0) #f (Str8 =? (Str8 sub (- n 1) 1 line) ":")))))

(def %py-read-entry
  (fn (_ first-line)
    (def more
      (fn (self acc)
        (display "... ")
        (let ((line (%py-repl-line)))
          (if (eq? line (lit eof))
            (List reverse acc)
            (if (= (Str8 length line) 0)
              (List reverse acc)
              (self (pair line acc)))))))
    (if (%py-opens-block? first-line)
      (Str8 join "\n" (more (list first-line)))
      first-line)))

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
    (display ">>> ")
    (let ((line (%py-repl-line)))
      (if (eq? line (lit eof))
        (%seq (newline) (Sys exit 0))
        (if (= (Str8 length line) 0)
          (%python-repl-loop)
          (if (if (Str8 =? line "quit()") #t (Str8 =? line "exit()"))
            (Sys exit 0)
            (%seq
              (guard (%py-err
                  (%seq
                    (display "Error: ")
                    (%seq
                      (display (if (str? %py-err) %py-err (Io write-to-str %py-err)))
                      (newline))))
                (%py-repl-eval (%py-read-entry line)))
              (%python-repl-loop))))))))

(provide python/repl %python-repl %python-banner)
