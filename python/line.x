; # x-python -- Python on x-lang
;
; ## python/line.x -- the line editor's seams, filled with Python's own knowledge
;
; @description The painter, the bracket marks and the completer the line
;   editor asks for at a Python prompt, and one reader for the loop.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; The platform's line editor reads a line with editing, history and Tab and
; carries no grammar of its own: it asks %repl-paint how to display the
; line, %repl-marks which brackets pair, and %repl-complete what a word could
; become.  This file answers the three for Python, and gives the loop one
; reader that uses the editor when there is a terminal to drive and the byte
; reader otherwise.
;
; The platform painter (x/repl/paint) asks the x reader what an atom is.
; Python's tokenizer is a second base: it answers tokens, not spans, and it
; stops at an unterminated string, which is the normal state of a line
; being typed.  So this file colours a line by the tokens of a Lexer
; (x/reader/lexer) of its own whose rules read every byte, through the
; platform's (Paint lexer): comments, strings with their prefixes and triple
; quotes, numbers, names, decorators, and every other byte as itself.  The
; bracket marks are read from the same tokens.  A name is classified
; lexically: the keyword list the tokenizer reads, the builtin table the
; parser reads, True/False/None, a leading capital.  The answer for a name
; is memoised.
;
; The colours are repl/ansi.x's, in the labels the platform painter uses
; for the same things, so a keyword, a literal and a class look the same
; being typed in either language.  A colourless terminal short-circuits the
; paint, and the last line painted is kept by the platform painter, since a
; redraw whose text has not changed asks for the same bytes again.
;
; The lexer is made on its first use, a prompt's redraw: a script, a pipe or
; an image write never pays for it.  The Lexer remakes its own states after
; an image load.
;
; A module of its own: its names are its own, and only what the provide list
; at the end names leaves it, for an importer to take by name.
(module python/line)
(import python/core
  python-builtins python-repl-line python-sweep!)
(import python/tokens python-keywords)

(import x/type/dict)
(import x/type/str)
(import x/type/list)
(import x/reader/lexer)
(import x/repl/ansi)
(import x/repl/paint)
; The editor.  Imported here rather than left to the launcher so that its
; Line class exists when the completer is installed below.
(import x/repl/line)

; --- reading one line ---------------------------------------------------------
;
; Answers the line as a string, 'eof at end of input, and 'cancel for ctrl-c,
; which abandons the entry being typed.  Without a terminal the prompt is
; displayed and the byte reader is used.
(def %py-editor?
  (fn (_) (guard (_ #f) (Line available?))))

(def python-read
  (fn (_ prompt)
    (if (%py-editor?)
      (Line read prompt)
      (do (display prompt) (python-repl-line)))))

; --- cached prims ------------------------------------------------------------
(def %pp-bref   (prim-ref (lit str)  (lit byte-ref)))
(def %pp-blen   (prim-ref (lit str)  (lit byte-len)))
(def %pp-bsub   (prim-ref (lit str)  (lit byte-sub)))
(def %pp-append (prim-ref (lit str)  (lit append)))
(def %pp-cint   (prim-ref (lit char) (lit ->int)))

; --- byte classes ------------------------------------------------------------
(def %pp-byte (fn (_ s i) (%pp-cint (%pp-bref s i))))
(def %pp-digit? (fn (_ b) (if (>= b 48) (<= b 57) #f)))
(def %pp-ident-start?
  (fn (_ b)
    (match
      ((= b 95) #t)
      ((if (>= b 65) (<= b 90) #f) #t)
      ((if (>= b 97) (<= b 122) #f) #t)
      (#t (>= b 128)))))
(def %pp-ident? (fn (_ b) (if (%pp-ident-start? b) #t (%pp-digit? b))))
(def %pp-open? (fn (_ b) (if (= b 40) #t (if (= b 91) #t (= b 123)))))
(def %pp-close? (fn (_ b) (if (= b 41) #t (if (= b 93) #t (= b 125)))))

(python-sweep!)
; --- classifying a name ------------------------------------------------------
(def %pp-kw ())        ; Dict: keyword -> #t
(def %pp-bi ())        ; Dict: builtin -> #t
(def %pp-memo ())      ; Dict: name -> label
(def %pp-kw-get ())
(def %pp-bi-get ())
(def %pp-memo-get ())
(def %pp-memo-set ())

(def %pp-label-of
  (fn (_ name)
    (match
      ((%pp-kw-get #f name) (lit keyword))
      ((if (Str8 =? name "True") #t (if (Str8 =? name "False") #t (Str8 =? name "None")))
        (lit bool))
      ((%pp-bi-get #f name) (lit builtin))
      ((let ((b0 (%pp-byte name 0))) (if (>= b0 65) (<= b0 90) #f)) (lit class))
      (#t (lit name)))))

(def %py-paint-label
  (fn (_ name)
    (let ((hit (%pp-memo-get () name)))
      (if (null? hit)
        (let ((cls (%pp-label-of name)))
          (%pp-memo-set name cls)
          cls)
        hit))))

; --- the codes ---------------------------------------------------------------
;
; Read from the Ansi statics once per install rather than once per token:
; whether there is a terminal is a fact of the process, so the install runs
; again after a state image is loaded.
(def %pp-c-keyword "")
(def %pp-c-bool "")
(def %pp-c-builtin "")
(def %pp-c-class "")
(def %pp-c-number "")
(def %pp-c-string "")
(def %pp-c-comment "")
(def %pp-c-decorator "")

; A name's code by its label; a plain name has none.
(def %pp-name-code
  (fn (_ text)
    (let ((cls (%py-paint-label text)))
      (match
        ((eq? cls (lit keyword)) %pp-c-keyword)
        ((eq? cls (lit bool)) %pp-c-bool)
        ((eq? cls (lit builtin)) %pp-c-builtin)
        ((eq? cls (lit class)) %pp-c-class)
        (#t ())))))

; --- the lexer ---------------------------------------------------------------
;
; Every byte of a line is some token's: blanks a run, a bracket or an
; operator one byte under `plain`, so the painter draws the line byte for
; byte with the author's spacing.  A string is one token with its prefix: a
; single-quoted one a nested span whose body takes a backslash escape, a
; triple-quoted one an until span, which ends at its first whole `"""` or
; `'''`.  Both run to the end of the text while unclosed, the normal state
; of a line being typed, and so does a comment.  A Lexer literal is bytes,
; so each prefix Python takes -- r, b, u, f, rb, br, fr and rf, in either
; case -- opens with a literal of its own, and a prefix with no quote after
; it is a name.
(def %pp-ident-start (list 95 (pair 65 90) (pair 97 122) (pair 128 255) (pair -128 -1)))
(def %pp-ident (list 95 (pair 48 57) (pair 65 90) (pair 97 122) (pair 128 255) (pair -128 -1)))
(def %pp-digits (list (pair 48 57)))
; a number's body: digits, letters, underscores and dots, so 0x1f, 1_000,
; 1e5j and 1.5 are each one token
(def %pp-num-body (list 46 95 (pair 48 57) (pair 65 90) (pair 97 122)))
; the body before an exponent letter, so the sign after it is read as well
(def %pp-num-mantissa (list 46 95 (pair 48 57)))

(def %pp-prefixes
  (list "" "r" "R" "b" "B" "u" "U" "f" "F"
        "rb" "rB" "Rb" "RB" "br" "bR" "Br" "BR"
        "fr" "fR" "Fr" "FR" "rf" "rF" "Rf" "RF"))

(def %pp-string-rules
  (fn (_)
    (List flat-map
      (fn (_ p)
        (List flat-map
          (fn (_ q)
            (let ((q3 (Str8 append q q q)))
              (list (Lexer until (lit string) (Str8 append p q3) q3 (lit to-end))
                    (Lexer nested (lit string) (Str8 append p q) (lit body)
                      (list (list (lit body) (%pp-byte q 0) 92 ())) (lit to-end)))))
          (list "\"" "'")))
      %pp-prefixes)))

; A number is digits, or a dot before a digit, then its body; the second
; pattern of each pair reads an exponent's sign, which the body alone would
; leave, and wins by length when there is one.
(def %pp-rules
  (fn (_)
    (List append
      (list (Lexer run (lit blank) " \t\r\n" " \t\r\n")
            (Lexer until (lit comment) "#" "\n" (lit to-end)))
      (%pp-string-rules)
      (list
        (Lexer pattern (lit number)
          (list (list %pp-digits 1 1) (list %pp-num-body 0 ())))
        (Lexer pattern (lit number)
          (list (list %pp-digits 1 1) (list %pp-num-mantissa 0 ()) (list "eE" 1 1)
                (list "+-" 1 1) (list %pp-num-body 0 ())))
        (Lexer pattern (lit number)
          (list (list "." 1 1) (list %pp-digits 1 1) (list %pp-num-body 0 ())))
        (Lexer pattern (lit number)
          (list (list "." 1 1) (list %pp-digits 1 1) (list %pp-num-mantissa 0 ()) (list "eE" 1 1)
                (list "+-" 1 1) (list %pp-num-body 0 ())))
        (Lexer run (lit name) %pp-ident-start %pp-ident)
        (Lexer pattern (lit decorator)
          (list (list "@" 1 1) (list %pp-ident-start 1 1) (list %pp-ident 0 ())))
        (Lexer any (lit plain))))))

(def %pp-lexer ())
(def %pp-lex
  (fn (_)
    (if (null? %pp-lexer) (set! %pp-lexer (Lexer make (%pp-rules))) ())
    %pp-lexer))

; Each tag's colour: the code strings above, read when a token is painted.
(def %pp-colours
  (fn (_)
    (list (pair (lit comment) (fn (_ t) %pp-c-comment))
          (pair (lit string) (fn (_ t) %pp-c-string))
          (pair (lit number) (fn (_ t) %pp-c-number))
          (pair (lit decorator) (fn (_ t) %pp-c-decorator))
          (pair (lit name) %pp-name-code))))

(def %pp-painter ())
(def %pp-paint
  (fn (_)
    (if (null? %pp-painter) (set! %pp-painter (Paint lexer (%pp-lex) (%pp-colours))) ())
    %pp-painter))

; --- bracket marks -----------------------------------------------------------
;
; A mark for every bracket: (offset depth focused), the layout x/repl/paint
; answers for parens.  Depth is the nesting level from 0, shared by the two
; halves of a pair; a close with nothing to close is -1.  Focused is true on
; the pair the cursor is beside: a close just before the cursor first, then
; an open under it, a close under it, an open before it.  A bracket is a
; `plain` token of the lexer, so one inside a string or a comment is none.
(def %pp-depths
  (fn (_ s at)
    (let ((n (%pp-blen s)))
      (let ((before (if (> at 0) (%pp-byte s (- at 1)) 0))
            (here (if (if (>= at 0) (< at n) #f) (%pp-byte s at) 0)))
        (let ((target (match
                        ((%pp-close? before) (- at 1))
                        ((%pp-open? here) at)
                        ((%pp-close? here) at)
                        ((%pp-open? before) (- at 1))
                        (#t -1))))
          (let ((flag (fn (self ms off)
                        (if (null? ms) ()
                          (if (= (first (first ms)) off)
                            (pair (list off (first (rest (first ms))) #t) (rest ms))
                            (pair (first ms) (self (rest ms) off)))))))
            (let ((go (fn (self toks i open depth acc)
                        (if (null? toks) (List reverse acc)
                          (let ((text (first (rest (first toks)))))
                            (let ((b (if (eq? (first (first toks)) (lit plain)) (%pp-byte text 0) 0))
                                  (next (+ i (%pp-blen text))))
                              (match
                                ((%pp-open? b)
                                  (self (rest toks) next (pair (pair i depth) open) (+ depth 1)
                                        (pair (list i depth #f) acc)))
                                ((%pp-close? b)
                                  (if (null? open)
                                    (self (rest toks) next () 0 (pair (list i -1 (= i target)) acc))
                                    (let ((o (first (first open))) (d (rest (first open))))
                                      (let ((hit (if (= i target) #t (= o target))))
                                        (self (rest toks) next (rest open) d
                                              (pair (list i d hit)
                                                    (if hit (flag acc o) acc)))))))
                                (#t (self (rest toks) next open depth acc)))))))))
              (go ((%pp-lex) read-str s) 0 () 0 ()))))))))

(python-sweep!)
; --- the three answers the editor asks for ----------------------------------

; The seam the editor calls: (%repl-paint window marks before).
(def python-paint
  (fn (_ s . more)
    (if (not (Ansi enabled?)) s
      ((%pp-paint) s
        (if (null? more) () (first more))
        (if (if (null? more) #t (null? (rest more))) () (first (rest more)))))))

(def python-marks (fn (_ s at) (%pp-depths s at)))

; The lexer's tokens as (class . text), a name's class its label -- what a
; spec checks, colour or no colour.
(def %py-paint-tokens
  (fn (_ s)
    (List map
      (fn (_ tok)
        (let ((tag (first tok)) (text (first (rest tok))))
          (pair (if (eq? tag (lit name)) (%py-paint-label text) tag) text)))
      ((%pp-lex) read-str s))))

; --- completion --------------------------------------------------------------
;
; The keywords, the builtins and the names defined at the prompt, by prefix,
; sorted and each once.  An empty word answers nothing rather than the whole
; table.

; Names defined at the prompt, so that a function defined on one line
; completes on the next.  The loop records each as it lifts the definition,
; through python-session-name!: the list is this module's, and an importer that
; set! the name would bind its own copy.
(def %py-session-names ())
(def python-session-name!
  (fn (_ s) (set! %py-session-names (pair s %py-session-names))))
; The keywords and the builtins, built once by the install below.
(def %pp-names ())

; The identifier being typed: the letters, digits and underscores before the
; cursor.  Read through one method, `before`, so a stand-in with that method
; is a buffer enough for a spec.
(def %py-word-at
  (fn (_ ed)
    (let ((text (ed before)))
      (let ((n (%pp-blen text)))
        (let ((go (fn (self i)
                    (if (<= i 0) 0
                      (if (%pp-ident? (%pp-byte text (- i 1))) (self (- i 1)) i)))))
          (let ((start (go n)))
            (%pp-bsub text start (- n start))))))))

(def python-complete
  (fn (_ ed)
    (let ((word (%py-word-at ed)))
      (pair word
        (if (= 0 (%pp-blen word)) ()
          (List sort (fn (_ a b) (Str8 <? a b))
            (List distinct
              (List filter (fn (_ name) (Str8 starts? word name))
                (List append %pp-names %py-session-names)))))))))

; --- installation ------------------------------------------------------------
;
; The colours are strings of this process -- a state image loaded elsewhere
; may have a terminal the writer did not -- so the codes are read by a
; function the image recache hook calls again, and the memo with it.  The
; three seams are set here as well as registered by python/repl.x, to the
; values the lang "python" carries.
(def %py-line-install!
  (fn (_)
    (set! %pp-kw (Dict make))
    (List for-each (fn (_ k) (%pp-kw set! k #t)) python-keywords)
    (set! %pp-bi (Dict make))
    (List for-each (fn (_ row) (%pp-bi set! (first row) #t)) python-builtins)
    (set! %pp-memo (Dict make))
    (set! %pp-kw-get (method-ref %pp-kw get-or))
    (set! %pp-bi-get (method-ref %pp-bi get-or))
    (set! %pp-memo-get (method-ref %pp-memo get-or))
    (set! %pp-memo-set (method-ref %pp-memo set!))
    (set! %pp-names (List append python-keywords (List map (fn (_ row) (first row)) python-builtins)))
    (set! %pp-c-keyword (%pp-append (Ansi bold) (Ansi magenta))) ; as x's constructs
    (set! %pp-c-bool (Ansi bold-red))                            ; True False None
    (set! %pp-c-builtin (Ansi blue))                             ; as x's symbols
    (set! %pp-c-class (Ansi bold-cyan))                          ; a capitalised name
    (set! %pp-c-number (Ansi yellow))
    (set! %pp-c-string (Ansi green))
    (set! %pp-c-comment (Ansi dim))
    (set! %pp-c-decorator (Ansi magenta))
    (guard (_ ()) (set! %repl-paint python-paint))
    (guard (_ ()) (set! %repl-marks python-marks))
    (guard (_ ()) (Line completer python-complete))
    ()))

(%py-line-install!)
(set! %image-recache-hooks (pair (fn (_) (%py-line-install!)) %image-recache-hooks))

(provide python/line
  %py-paint-label %py-paint-tokens %py-word-at python-complete python-marks
  python-paint python-read python-session-name!)
