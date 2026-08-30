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
  mk-tok-name mk-tok-number mk-tok-string mk-tok-op mk-tok-newline)

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
; A newline carries the column of the line it opens.
(def mk-tok-newline (fn (_ col) (list (lit tok-newline) col)))

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

(def %py-nl-ws ())
(set! %py-nl-ws
  (fn (_ buffer score chr)
    (if (if (= chr #\space) #t (= chr #\tab))
      %py-nl-ws
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(Base make-type %py-base "PY-NL"
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr #\newline) %py-nl-ws ())))
    (pair (lit read)
      (fn (_ . args)
        ; Index 1 skips the newline itself; scan hands back the column and the
        ; end index from one walk, and the column is the half wanted here.
        (mk-tok-newline
          (first (%py-indent-scan (%buffer-token (first args)) 1 8)))))))

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
        (if (= c 33) #t (if (= c 40) #t (if (= c 41) #t (if (= c 91) #t
          (if (= c 93) #t (if (= c 123) #t (if (= c 125) #t
            (if (= c 44) #t (if (= c 58) #t (if (= c 46) #t
              (= c 59)))))))))))))))))))))

; Which pairs extend: == != <= >= // **
(def %py-op-pair?
  (fn (_ a b)
    (if (= b 61)
      (if (= a 61) #t (if (= a 33) #t (if (= a 60) #t (= a 62))))
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
(def %py-op-pairable?
  (fn (_ c)
    (if (= c 61) #t (if (= c 33) #t (if (= c 60) #t (if (= c 62) #t
      (if (= c 47) #t (= c 42))))))))

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
(def python-tokenize
  (fn (_ input)
    (%py-token-read-string (Base raw-of %py-base) (Str8 append input " "))))
