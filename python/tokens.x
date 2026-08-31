; # x-python -- Python on x-lang
;
; ## python/tokens.x -- Python's lexical layer, on its own tokenizer base
;
; @description Names, numbers, strings, operators and line structure, read on
;   a base isolated from the sexp reader's types.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY AN ISOLATED BASE
;
; Python and x disagree about nearly every punctuation character that matters.
; `#` is a comment here and a dispatch character there.  `'` opens a string
; here and is quote there.  `[` is a subscript here.  A type registered on the
; SHARED base would compete with the sexp types by score, and the loser is
; whichever the platform happened to weight higher -- x-ash documents that exact
; failure ("`a b` tokenizes as a bare symbol followed by a word").
;
; `(Base make-tok)` is the bare base with no types registered at all, and
; `(Base make-type TARGET ...)` registers onto it.  Both were dead in the
; engine until x-lang#528; ash proved they work.
;
; ## THE SCORING PROTOCOL, SINCE IT IS NOT OBVIOUS
;
; An `analyse` function is called once per character and returns one of three
; things: another state function to keep consuming, a SCORE to accept, or nil to
; reject.  `(%score-set score 1 buffer)` accepts INCLUDING the current
; character; `(%buffer-unread buffer)` before it accepts EXCLUDING it, which is
; how a token that ends at a delimiter gives the delimiter back.  A negative
; score is a match that produces nothing -- whitespace and comments.
;
; ## STRINGS ARE READ FROM THE BUFFER, NOT ACCUMULATED
;
; ash's string types build the value in a module-level global during `analyse`
; and read it back in `read`.  That is the bug its own README describes -- `''`
; works and `'a'` loses its accumulator -- and it allocates a fresh closure per
; character inside a reader callback, which is the one place allocation is a
; hazard.  Here `analyse` only finds the closing quote; `read` slices
; `%buffer-token` and unescapes.  No shared state, no per-character allocation.

(provide python/tokens
  python-tokenize %py-base
  mk-tok-name mk-tok-number mk-tok-string mk-tok-op mk-tok-newline
  mk-tok-group mk-tok-block)

; (Base make-tok) is the isolated, type-free base -- 2024's make-token-base.
(import x/reader/indent)

(def %py-base (Base make-tok))

; The platform owns the tokenizer intrinsics (lib/x/reader/intrinsics.x); these
; run per character, so they are the platform's own tested versions rather than
; a second copy of the same contract.
(def %py-token-read-string (prim-ref (lit tok) (lit read-str)))
; %buffer-len / %buffer-unread / %score-set are globals from
; lib/x/reader/intrinsics.x; the token accessor is not, and every module that
; wants it fetches it the same way (num/bigint.x, num/complex.x).
(def %buffer-token (prim-ref (lit buf) (lit tok)))
(def %py-char->int (prim-ref (lit char) (lit ->int)))
; The list->string spelling ash arrived at: %cvt to the string type, with the
; empty list special-cased because a conversion of nothing has no type to go on.
(def %py-list->string (fn (_ l) (if (null? l) "" (%cvt l %string))))

; --- Token values ------------------------------------------------------------
; Plain lists, the shape ash settled on: readable in a spec without a printer.
(def mk-tok-name    (fn (_ s) (list (lit tok-name) s)))
(def mk-tok-number  (fn (_ s) (list (lit tok-number) s)))
(def mk-tok-string  (fn (_ s) (list (lit tok-string) s)))
(def mk-tok-op      (fn (_ s) (list (lit tok-op) s)))
; A bracketed run, already nested by the reader: (tok-group "[" (tok ...)).
(def mk-tok-group   (fn (_ open elems) (list (lit tok-group) open elems)))
; An indented run, already nested by the reader: (tok-block (tok ...)).
(def mk-tok-block   (fn (_ elems) (list (lit tok-block) elems)))
; A newline carries the column of the line it opens.
(def mk-tok-newline (fn (_) (list (lit tok-newline))))

; --- Character classes -------------------------------------------------------
; Nested if, never `or`: operatives expand per evaluation and these run per
; character of every token (#343).
(def %py-digit?
  (fn (_ c) (if (>= c 48) (<= c 57) #f)))

(def %py-name-start?
  (fn (_ c)
    (if (if (>= c 97) (<= c 122) #f) #t
      (if (if (>= c 65) (<= c 90) #f) #t
        (= c 95)))))

(def %py-name-rest?
  (fn (_ c) (if (%py-name-start? c) #t (%py-digit? c))))

; --- PY-WS: spaces and tabs WITHIN a line ------------------------------------
; Not newlines: line structure is Python's grammar, not its whitespace, so
; PY-NL owns them.  Negative score -- matched and discarded.
(def %py-ws-continue ())
(set! %py-ws-continue
  (fn (_ buffer score chr)
    (if (if (= chr #\space) #t (= chr #\tab))
      %py-ws-continue
      (%seq (%buffer-unread buffer) (%score-set score (- 0 1) buffer)))))

(Base make-type %py-base "PY-WS"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (if (= chr #\space) #t (= chr #\tab))
          (%seq (%score-set score (- 0 1) buffer) %py-ws-continue)
          ())))))

; --- PY-COMMENT: # to end of line, discarded ---------------------------------
; The newline is given back, because it is a NEWLINE token and a comment must
; not swallow the line structure it sits on.
(def %py-comment-body ())
(set! %py-comment-body
  (fn (_ buffer score chr)
    (if (= chr #\newline)
      (%seq (%buffer-unread buffer) (%score-set score (- 0 1) buffer))
      %py-comment-body)))

(Base make-type %py-base "PY-COMMENT"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 35)
          (%seq (%score-set score (- 0 1) buffer) %py-comment-body)
          ())))))

; --- PY-NL: the newline AND the indentation that follows it ------------------
;
; ONE TOKEN, NOT TWO, and that is Logo's arrangement rather than an invention:
; LOGO-INDENT matches "\n + spaces/tabs + word" for the same reason.  A column
; can only be measured while reading characters, and by the time a flat token
; stream exists the leading whitespace is gone.  So the newline carries it.
;
; The column is measured by x/reader/indent (x-lang#520) rather than counted
; here, which is what makes the tab question one answer across Logo, x-sweet and
; this bundle instead of three.  Tab stop 8: SRFI-110's answer and CPython's.
(def %py-indent-scan (prim-ref (lit indent) (lit scan)))

; --- Blocks are READ, not spliced -------------------------------------------
;
; An indented run is a region the way a bracket is, so it is read the same way:
; PY-NL measures the column, asks the shared Indent stack what opened or closed,
; and on an `open` recurses through the engine's reader to collect the block.
; The result is a nested (tok-block (tok ...)) rather than INDENT/DEDENT markers
; spliced into a flat stream by a pass afterwards.
;
; ONE READ RETURNS ONE TOKEN, and a single dedent can close several blocks.  So
; the surplus is left in %py-owed for the enclosing block loops to collect: each
; one, on finding a debt outstanding, ends too.  That counter is the whole
; reason this works with a protocol that has no way to return two things.
;
; Policy -- tab stop, and what an unmatched dedent means -- stays with Indent
; (x-lang#520), which is what keeps the answer the same across Logo, x-sweet and
; this bundle.
(def %py-ind (pair () ()))
(def %py-owed (pair 0 ()))

; A NEWLINE INSIDE BRACKETS IS NOT LINE STRUCTURE, and the indent stack must
; never see its column.  The group reader raises this while it collects, so
; PY-NL can tell the two cases apart -- the depth counter python/indent.x used
; to keep, moved to where the nesting is actually known and kept to one bit of
; state rather than a pass-wide walk.
(def %py-in-group (pair 0 ()))

; A READ HANDLER CANNOT RAISE.  The C reader loop is driving, and an error
; unwinding out of a handler through it takes the interpreter down rather than
; reaching a guard -- measured, not assumed: `(guard (e ...) (python-tokenize
; "a\n    b\n  c"))` died where the old pass raised cleanly, because the old
; pass was x code driving its own loop.
;
; So a bad dedent is CARRIED OUT AS DATA.  Indent still decides -- its default
; mode is Python's IndentationError, which is the one place Logo, x-sweet and
; this bundle genuinely disagree -- and the first error it raises is parked
; here for python-tokenize to re-raise once reading is over and x is driving
; again.  The error object is kept whole, so the kind and message are the ones
; Indent chose.
(def %py-ind-error (pair () ()))

(def %py-ind-reset!
  (fn (_)
    (%set-first! %py-ind (Indent make))
    (%set-first! %py-owed 0)
    (%set-first! %py-in-group 0)
    (%set-first! %py-ind-error ())))

; A FLAG, NOT THE ERROR OBJECT.  The caught value arrives NIL here: a raise
; crossing the C reader boundary reaches the guard, but its payload does not
; survive the trip -- traced, with the handler printing `<NOTE ()>` where the
; same guard around a direct `Err raise` prints the error.  So what is recorded
; is THAT it failed, and python-tokenize builds the error itself.
;
; The cost is stated rather than hidden: `feed`'s only documented failure is the
; unmatched dedent, so synthesising that message is right today -- but if Indent
; grows a second failure mode, this will report it as the wrong one.
(def %py-note-ind-error!
  (fn (_) (%set-first! %py-ind-error #t)))

(def %py-evs-opens?
  (fn (self evs) (if (null? evs) #f
    (if (eq? (first evs) (lit open)) #t (self (rest evs))))))

(def %py-evs-closes
  (fn (self evs n) (if (null? evs) n
    (self (rest evs) (if (eq? (first evs) (lit close)) (+ n 1) n)))))

(def %py-block-of
  (fn (_ buffer)
    (def go
      (fn (self acc)
        (let ((v (%py-token-read buffer)))
          (if (null? v)
            (mk-tok-block (List reverse acc))
            (if (eq? v (lit %py-dedent))
              (mk-tok-block (List reverse acc))
              ; a nested block may have closed more levels than its own
              (if (> (first %py-owed) 0)
                (%seq (%set-first! %py-owed (- (first %py-owed) 1))
                  (mk-tok-block (List reverse (pair v acc))))
                (self (pair v acc))))))))
    (go ())))

; A BLANK OR COMMENT-ONLY LINE IS DISCARDED HERE, where the decision is cheap.
; The character after the indentation is visible to the ANALYSER -- it is the
; one that ends the whitespace run -- so a line with nothing on it can be
; refused before it ever becomes a token.  python/indent.x used to carry a
; `pending` column for exactly this, deferring the decision until a real token
; arrived to prove the line was not blank; the reader can just look.
;
; A negative score is "matched and discarded", so the line leaves no trace and
; the indentation stack never sees a column that was not a real line.
; A BLANK OR COMMENT-ONLY LINE IS A DIFFERENT TYPE, not a discarded PY-NL.
;
; DISCARDING IS "MATCHED, WITH NO READ HANDLER" -- that is how PY-WS and
; PY-COMMENT vanish, and it is why a negative score cannot suppress PY-NL: PY-NL
; HAS a reader, so it always produces a token whatever the score says.  So the
; two cases are split into two types that cannot both match: PY-NL rejects a
; line with nothing on it, and PY-BLANK claims exactly those and has no reader.
;
; The character after the indentation is what decides, and the ANALYSER can see
; it -- it is the one that ends the whitespace run.  python/indent.x used to
; carry a `pending` column for this, deferring until a real token proved the
; line was not blank; the reader can just look.
(def %py-nl-ws ())
(set! %py-nl-ws
  (fn (_ buffer score chr)
    (if (if (= chr #\space) #t (= chr #\tab))
      %py-nl-ws
      (if (if (= chr #\newline) #t (= chr 35))
        ()
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))

(def %py-blank-ws ())
(set! %py-blank-ws
  (fn (_ buffer score chr)
    (if (if (= chr #\space) #t (= chr #\tab))
      %py-blank-ws
      (if (if (= chr #\newline) #t (= chr 35))
        (%seq (%buffer-unread buffer) (%score-set score (- 0 1) buffer))
        ()))))

(Base make-type %py-base "PY-BLANK"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr #\newline) %py-blank-ws ())))))

(Base make-type %py-base "PY-NL"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr #\newline) %py-nl-ws ())))
    (pair (lit read)
      (fn (_ . args)
        ; Index 1 skips the newline itself; scan hands back the column and the
        ; end index from one walk, and the column is the half wanted here.
        (def buffer (first args))
        (if (> (first %py-in-group) 0)
          ; inside brackets: whitespace, and the group reader drops it
          (mk-tok-newline)
          (do
        (def col (first (%py-indent-scan (%buffer-token buffer) 1 8)))
        (def evs
          (guard (_ (%seq (%py-note-ind-error!) (list (lit same))))
            ((first %py-ind) feed col)))
        (if (%py-evs-opens? evs)
          (%py-block-of buffer)
          (let ((n (%py-evs-closes evs 0)))
            (if (> n 0)
              (%seq (%set-first! %py-owed (- n 1)) (lit %py-dedent))
              ; NO COLUMN ON THE TOKEN.  It carried one for the pass that used
              ; to consume it; the block structure now says everything the
              ; column said, so emitting it would be dead data.
              (mk-tok-newline))))))))))

; --- PY-NAME: identifiers and keywords ---------------------------------------
; Keywords are NOT distinguished here.  `if` is a name to the tokenizer and a
; keyword to the parser, which is where the distinction is actually used; a
; tokenizer that knows the keyword list has to be edited every time the grammar
; grows one.
(def %py-name-body ())
(set! %py-name-body
  (fn (_ buffer score chr)
    (if (%py-name-rest? chr)
      %py-name-body
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(Base make-type %py-base "PY-NAME"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-name-start? chr) %py-name-body ())))
    (pair (lit read)
      (fn (_ . args) (mk-tok-name (%buffer-token (first args)))))))

; --- PY-NUMBER: integers and floats ------------------------------------------
; The value is kept as its SOURCE TEXT.  Python's int is arbitrary-precision and
; its float is IEEE 754, and which one a literal denotes is a question with a
; right answer that belongs to the evaluator -- a tokenizer that converts early
; has to know the tower, and gets `1_000` and `0x10` wrong quietly.
(def %py-number-frac ())
(def %py-number-body ())

(set! %py-number-frac
  (fn (_ buffer score chr)
    (if (%py-digit? chr)
      %py-number-frac
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(set! %py-number-body
  (fn (_ buffer score chr)
    (if (%py-digit? chr)
      %py-number-body
      (if (= chr 46)
        %py-number-frac
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))

; A SIGNED LITERAL IS CLAIMED HERE, AND THAT IS NOT WHAT PYTHON MEANS BY IT.
;
; The sexp integer type accepts a leading + or -, so on `a+2` it matches `+2`
; -- two characters -- and outscores PY-OP matching `+` as one.  The winning
; type's reader is the engine's, so the operator vanishes and a bare integer
; lands in the stream.  A single-character operator type cannot win that race.
;
; So this type matches the sign too, ties on length, and takes it.  The sign is
; then split back off in python/parse.x when the token appears in OPERATOR
; position -- which is where Python decides it: `a-3` is three tokens and `-3`
; alone is one, and only the grammar knows which it is looking at.  Doing it
; here would need the tokenizer to know whether an operand is pending, which is
; precisely the knowledge a tokenizer does not have.
;
; A sign NOT followed by a digit rejects, so `a + b` still reaches PY-OP.
(def %py-number-signed ())
(set! %py-number-signed
  (fn (_ buffer score chr)
    (if (%py-digit? chr) %py-number-body ())))

(Base make-type %py-base "PY-NUMBER"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-digit? chr)
          %py-number-body
          (if (if (= chr 43) #t (= chr 45)) %py-number-signed ()))))
    (pair (lit read)
      (fn (_ . args) (mk-tok-number (%buffer-token (first args)))))))

; --- PY-STRING: 'single' and "double" ----------------------------------------
; TWO FIXED STATES, one per quote, rather than one state closed over the quote
; character.  A closure per string would be built once, which is harmless; ash
; builds one per CHARACTER, which is not.  Two states cost two definitions and
; allocate nothing.
;
; A backslash escapes the next character, including the quote and including a
; backslash, so the escape state is where `\\` stops swallowing the terminator.
(def %py-sq-body ())
(def %py-sq-esc ())
(def %py-dq-body ())
(def %py-dq-esc ())

(set! %py-sq-esc (fn (_ buffer score chr) %py-sq-body))
(set! %py-sq-body
  (fn (_ buffer score chr)
    (if (= chr 39)
      (%score-set score 1 buffer)
      (if (= chr 92) %py-sq-esc %py-sq-body))))

(set! %py-dq-esc (fn (_ buffer score chr) %py-dq-body))
(set! %py-dq-body
  (fn (_ buffer score chr)
    (if (= chr 34)
      (%score-set score 1 buffer)
      (if (= chr 92) %py-dq-esc %py-dq-body))))

; The lexeme still carries its quotes and its backslashes; `read` strips the
; first and interprets the second.
; Built with Str8 appends rather than a char list and a conversion.  The
; list->string spelling ash uses (%cvt l %string) hands back nil here, and a
; string reader that silently produces nothing is worse than one that is slow:
; these are string LITERALS, so the quadratic append is over a handful of
; characters.
(def %py-unescape
  (fn (_ s)
    (def len (Str8 length s))
    (def %go
      (fn (self i acc)
        (if (>= i len)
          acc
          (if (if (= (%py-char->int (Str8 ref i s)) 92) (< (+ i 1) len) #f)
            (let ((code (%py-char->int (Str8 ref (+ i 1) s))))
              (self (+ i 2)
                (Str8 append acc
                  (if (= code 110) "\n"
                    (if (= code 116) "\t"
                      (if (= code 114) "\r" (Str8 sub (+ i 1) 1 s)))))))
            (self (+ i 1) (Str8 append acc (Str8 sub i 1 s)))))))
    (%go 0 "")))

(def %py-string-read
  (fn (_ . args)
    (def raw (%buffer-token (first args)))
    (def len (Str8 length raw))
    ; Drop the opening and closing quote; an unterminated string never reaches
    ; here, because its state never accepted.
    (mk-tok-string (%py-unescape (Str8 sub 1 (- len 2) raw)))))

(Base make-type %py-base "PY-SQ"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (= chr 39) %py-sq-body ())))
    (pair (lit read) %py-string-read)))

(Base make-type %py-base "PY-DQ"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (= chr 34) %py-dq-body ())))
    (pair (lit read) %py-string-read)))

; --- PY-OP: operators and delimiters -----------------------------------------
; LONGEST MATCH MATTERS AND IS EASY TO GET WRONG.  `//` is floor division and
; `/` is true division; `**` is power; `==` `!=` `<=` `>=` are comparisons and
; `=` is assignment.  A single-character-only operator type reads `a//b` as two
; divisions, which is not a syntax error -- it is silently different arithmetic.
;
; THE SHAPE IS ash's SH-OP, INCLUDING THE `(+ chr 0)`.  Two earlier attempts
; died here and both are worth recording:
;
;   Closing over `chr` DIRECTLY inside analyse killed the interpreter -- it
;   worked for `1 + 2` and crashed on `print(-3 + 5)`.  ash writes
;   `(%sh-op-double (+ chr 0))`, and the arithmetic is not decoration: it forces
;   a fresh immediate rather than capturing the callback's own value.
;
;   Building the pair matchers with `Analyser make-str-state` at registration
;   time crashed at LOAD, before a character was read.
;
; So: a top-level state builder, called once per operator token, capturing a
; copy.  One closure per token is what ash does and what the platform tolerates;
; one per character is not.
(def %py-op-start?
  (fn (_ c)
    (if (= c 43) #t (if (= c 45) #t (if (= c 42) #t (if (= c 47) #t
      (if (= c 37) #t (if (= c 61) #t (if (= c 60) #t (if (= c 62) #t
        (if (= c 33) #t
            (if (= c 44) #t (if (= c 58) #t (if (= c 46) #t
              (= c 59)))))))))))))))

; Which pairs extend: == != <= >= // ** and += -= *= /= %=
(def %py-op-pair?
  (fn (_ a b)
    (if (= b 61)
      (if (= a 61) #t (if (= a 33) #t (if (= a 60) #t (if (= a 62) #t
        (if (= a 43) #t (if (= a 45) #t (if (= a 42) #t
          (if (= a 47) #t (= a 37)))))))))
      (if (if (= a 47) (= b 47) #f) #t
        (if (= a 42) (= b 42) #f)))))

; ONLY THE SIX CHARACTERS THAT CAN BEGIN A TWO-CHARACTER OPERATOR look ahead.
; Everything else accepts on the spot.
;
; This is the fix for `1+2` reading as (('tok-number "1") 2) -- the `+` lost and
; the `2` unwrapped. PY-NUMBER ends `1` by giving `+` back with %buffer-unread;
; PY-OP then took `+`, entered a lookahead state, saw `2`, and unread AGAIN.
; Two rewinds around one character is one too many, and the token in between
; disappeared. `-3` at the start of input worked precisely because nothing had
; unread before it, which is what made this look like a sign-handling bug for
; three rounds of investigation.
;
; ash's SH-OP has the same split -- `(` and `)` accept immediately, the rest
; look ahead -- and this is why.
; The augmented-assignment operators put + - * % into the lookahead set too:
; `+=` must beat `+`, the same way `==` beats `=`.
(def %py-op-pairable?
  (fn (_ c)
    (if (= c 61) #t (if (= c 33) #t (if (= c 60) #t (if (= c 62) #t
      (if (= c 47) #t (if (= c 42) #t
        (if (= c 43) #t (if (= c 45) #t (= c 37))))))))))) 

(def %py-op-second
  (fn (_ c1)
    (fn (_ buffer score chr)
      (if (%py-op-pair? c1 chr)
        (%score-set score 1 buffer)
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))

(Base make-type %py-base "PY-OP"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-op-start? chr)
          (if (%py-op-pairable? chr)
            (%seq (%score-set score 1 buffer) (%py-op-second (+ chr 0)))
            (%score-set score 1 buffer))
          ())))
    (pair (lit read)
      (fn (_ . args) (mk-tok-op (%buffer-token (first args)))))))

; --- The driver --------------------------------------------------------------
; (Base raw-of ...) IS NOT OPTIONAL, and omitting it is a SEGFAULT rather than
; an error.  `make-type` takes the wrapped base object; `read-str` takes the raw
; one underneath it, and handed a wrapper it walks a pointer that is not there.
; ash/prims.x has the unwrap in `token-read-string` and it is the single line
; between a working tokenizer and a dead one.
; THE TRAILING SPACE IS LOAD-BEARING.  read-str drops an unterminated tail --
; lib/x/reader/lit-reader.x says so in as many words, "terminates its token at
; end-of-buffer (token-read-string drops an unterminated tail)" -- so a source
; ending in a name, a number or an operator loses its last token.  Both of the
; platform's own call sites append a delimiter for exactly this reason.  A
; space is safe: PY-WS discards it.
; The indentation stack is per-RUN state, so it is reset here rather than at
; load: two tokenize calls in one process must not share a stack.
(def python-tokenize
  (fn (_ input)
    (%py-ind-reset!)
    (let ((toks (%py-token-read-string (Base raw-of %py-base)
                  (Str8 append input " "))))
      ; Reading is over and x is driving again, so this is where an indentation
      ; error can finally be raised.
      (if (null? (first %py-ind-error))
        toks
        (Err raise (lit indent)
          "unindent does not match any outer indentation level" ())))))

; --- PY-OPEN / PY-CLOSE: brackets are READ AS GROUPS -------------------------
;
; THE C READER DOES THE NESTING.  `(prim-ref 'tok 'read)` reads the next
; expression from the same buffer, and a `read` handler may call it -- so an
; opening bracket collects its own contents by recursing through the engine's
; own reader loop rather than by a matching pass in x afterwards.  This is what
; x-sweet's curly reader does, and it is why none of the other bundles has a
; parser that scans for a closing bracket.
;
; Two things fall out.  Line structure inside brackets stops being a special
; case: a newline inside a group is simply inside the group, so the bracket
; DEPTH COUNTER python/indent.x used to carry is gone.  And an unclosed bracket
; ends at EOF with what it has, which the parser reports -- the lexer does not
; need to know about matching, only about nesting.

(def %py-token-read (prim-ref (lit tok) (lit read)))

(def %py-open? (fn (_ c) (if (= c 40) #t (if (= c 91) #t (= c 123)))))
(def %py-close? (fn (_ c) (if (= c 41) #t (if (= c 93) #t (= c 125)))))

(Base make-type %py-base "PY-CLOSE"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-close? chr) (%score-set score 1 buffer) ())))
    (pair (lit read)
      (fn (_ . args) (list (lit tok-close) (%buffer-token (first args)))))))

(def %py-group-close? (fn (_ t) (if (pair? t) (eq? (first t) (lit tok-close)) #f)))
(def %py-group-nl? (fn (_ t) (if (pair? t) (eq? (first t) (lit tok-newline)) #f)))

(Base make-type %py-base "PY-OPEN"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-open? chr) (%score-set score 1 buffer) ())))
    (pair (lit read)
      (fn (_ . args)
        (def buffer (first args))
        (def open (%buffer-token buffer))
        (%set-first! %py-in-group (+ (first %py-in-group) 1))
        (def go
          (fn (self acc)
            (let ((v (%py-token-read buffer)))
              ; EOF inside a bracket: give back what there is and let the parser
              ; say so.  A lexer that raised here would report the wrong place.
              (if (null? v)
                (List reverse acc)
                (if (%py-group-close? v)
                  (List reverse acc)
                  ; A newline inside brackets is not line structure, it is
                  ; whitespace -- which used to need a depth counter to know.
                  (if (%py-group-nl? v)
                    (self acc)
                    (self (pair v acc))))))))
        (let ((elems (go ())))
          (%set-first! %py-in-group (- (first %py-in-group) 1))
          (mk-tok-group open elems))))))
