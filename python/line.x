; python/line.x -- the line editor's seams, filled with Python's own knowledge.
;
; The platform's line editor reads a line with editing, history and Tab and
; carries no grammar of its own: it asks %repl-paint how to display the line
; and (Line completer) what a word could become.  This file answers both for
; Python, and gives the loop one reader that uses the editor when there is a
; terminal to drive and the byte reader otherwise.
;
; Colour comes from Python's own tokenizer: python-tokenize decides what is a
; keyword, a name, a number, an operator or a string, and this file only
; locates each token's bytes in the line so the display keeps the author's
; spacing.  The one thing it scans for itself is the extent of a string
; literal, since the tokenizer answers a string's decoded contents rather than
; its span, and answers nothing at all for a line whose string is not closed
; yet, which is the state of a line while its string is being typed.

(import x/type/class)
(import x/type/str)
(import x/type/list)
(import python/tokens)
; The editor, when the platform has one.  Imported here rather than left to
; the launcher so that its Line class exists when the completer is installed
; below; a platform without it leaves the guard to answer.
(guard (_ ()) (import x/repl/line))

; --- reading one line ---------------------------------------------------------
;
; Answers the line as a string, 'eof at end of input, and 'cancel for ctrl-c,
; which abandons the entry being typed.  Without a terminal, or on a platform
; without the editor, the prompt is displayed and the byte reader is used.
(def %py-editor?
  (fn (_) (guard (_ #f) (Line available?))))

(def %py-read
  (fn (_ prompt)
    (if (%py-editor?)
      (Line read prompt)
      (do (display prompt) (%py-repl-line)))))

; --- colour -------------------------------------------------------------------

; The codes, read from the Ansi statics once per install rather than once per
; token: whether there is a terminal is a fact of the process, so the install
; runs again after a state image is loaded.
(def %py-c-keyword "")
(def %py-c-builtin "")
(def %py-c-constant "")
(def %py-c-name "")
(def %py-c-number "")
(def %py-c-string "")
(def %py-c-comment "")
(def %py-c-reset "")

(def %py-paint-install!
  (fn (_)
    (guard (_ ())
      (set! %py-c-keyword (Str8 append (Ansi bold) (Ansi magenta)))
      (set! %py-c-builtin (Ansi cyan))
      (set! %py-c-constant (Ansi bold-red))
      (set! %py-c-name (Ansi blue))
      (set! %py-c-number (Ansi yellow))
      (set! %py-c-string (Ansi green))
      (set! %py-c-comment (Ansi dim))
      (set! %py-c-reset (Ansi reset)))))

(def %py-builtin-names
  (fn (_) (List map first %py-builtins)))

(def %py-constant?
  (fn (_ text)
    (if (Str8 =? text "True") #t (if (Str8 =? text "False") #t (Str8 =? text "None")))))

; One coloured piece onto the reversed segment list; an empty code pushes the
; bare text, so nothing emits a stray reset.
(def %py-seg
  (fn (_ segs code text)
    (if (= 0 (Str8 length text)) segs
      (if (= 0 (Str8 length code)) (pair text segs)
        (pair %py-c-reset (pair text (pair code segs)))))))

(def %py-gap
  (fn (_ s from to segs)
    (if (>= from to) segs (pair (Str8 sub from (- to from) s) segs))))

; Where `text` next occurs at or after `from`, or nil.
(def %py-find
  (fn (_ s text from n)
    (if (>= from n) ()
      (let ((i (Str8 index-of text (Str8 sub from (- n from) s))))
        (if (null? i) () (+ from i))))))

(def %py-quote?
  (fn (_ c) (if (eq? c #\") #t (eq? c #\'))))

; The first quote character at or after `from`, or nil.
(def %py-quote-from
  (fn (self s from n)
    (if (>= from n) ()
      (if (%py-quote? (Str8 ref from s)) from (self s (+ from 1) n)))))

; Whether the three bytes at `i` are the same quote character.
(def %py-triple-at?
  (fn (_ s i n)
    (if (> (+ i 3) n) #f
      (let ((c (Str8 ref i s)))
        (if (eq? c (Str8 ref (+ i 1) s)) (eq? c (Str8 ref (+ i 2) s)) #f)))))

; The offset just past the string opened by the quote at `q`, or n when it is
; not closed.  A backslash escapes the next byte; a triple quote closes only
; on the same triple.
(def %py-quote-end
  (fn (_ s q n)
    (let ((open (Str8 ref q s))
          (triple (%py-triple-at? s q n)))
      (let ((go (fn (self i)
                  (if (>= i n) n
                    (let ((c (Str8 ref i s)))
                      (match
                        ((eq? c #\\) (self (+ i 2)))
                        ((if (eq? c open) (if triple (%py-triple-at? s i n) #t) #f)
                          (+ i (if triple 3 1)))
                        (#t (self (+ i 1)))))))))
        (go (+ q (if triple 3 1)))))))

; A string literal's prefix letters -- r, b, f, u, alone or paired -- sit
; between the previous token and the quote; the span starts at the first of
; them rather than at the quote.
(def %py-prefix-start
  (fn (self s q from)
    (if (<= q from) q
      (let ((c (Str8 ref (- q 1) s)))
        (if (List includes? c (list #\r #\b #\f #\u #\R #\B #\F #\U))
          (if (> (- q from) 2) (- q 1) (self s (- q 1) from))
          q)))))

; The tokenizer answers groups as nested lists; the painter wants tokens in
; source order, with a group's brackets as operators.  A close that is still
; nil, the group being open, contributes nothing.
(def %py-flatten
  (fn (self toks acc)
    (if (null? toks) acc
      (let ((t (first toks)))
        (if (if (pair? t) (eq? (first t) (lit tok-group)) #f)
          (let ((open (first (rest t)))
                (inner (first (rest (rest t))))
                (close (first (rest (rest (rest t))))))
            (self (rest toks)
              (let ((acc2 (self inner (pair (list (lit tok-op) open) acc))))
                (if (null? close) acc2 (pair (list (lit tok-op) close) acc2)))))
          (self (rest toks) (pair t acc)))))))

(def %py-string-kind?
  (fn (_ kind)
    (if (eq? kind (lit tok-string)) #t
      (if (eq? kind (lit tok-fstring)) #t (eq? kind (lit tok-bytes))))))

(def %py-token-code
  (fn (_ kind text)
    (match
      ((eq? kind (lit tok-kw)) %py-c-keyword)
      ((eq? kind (lit tok-number)) %py-c-number)
      ((eq? kind (lit tok-name))
        (if (%py-constant? text) %py-c-constant
          (if (List includes? text (%py-builtin-names)) %py-c-builtin %py-c-name)))
      (#t ""))))

; What is left after the last token: a comment from its `#`, an unclosed
; string from its quote, or plain bytes.
(def %py-paint-tail
  (fn (_ s from n segs)
    (if (>= from n) segs
      (let ((hash (%py-find s "#" from n))
            (q (%py-quote-from s from n)))
        (match
          ((if (null? hash) #f (if (null? q) #t (< hash q)))
            (%py-seg (%py-gap s from hash segs) %py-c-comment (Str8 sub hash (- n hash) s)))
          ((not (null? q))
            (%py-seg (%py-gap s from q segs) %py-c-string (Str8 sub q (- n q) s)))
          (#t (%py-gap s from n segs)))))))

; The tokens of s in source order, or nil when the tokenizer declines the
; line -- which it does for a string that is not closed yet.
(def %py-tokens-of
  (fn (_ s) (guard (_ ()) (List reverse (%py-flatten (python-tokenize s) ())))))

(def %py-paint-tokens
  (fn (self s toks at n segs)
    (if (null? toks) (%py-paint-tail s at n segs)
      (let ((kind (first (first toks)))
            (text (if (null? (rest (first toks))) "" (first (rest (first toks))))))
        (match
          ((%py-string-kind? kind)
            (let ((q (%py-quote-from s at n)))
              (if (null? q) (%py-paint-tail s at n segs)
                (let ((b (%py-prefix-start s q at))
                      (e (%py-quote-end s q n)))
                  (self s (rest toks) e n
                        (%py-seg (%py-gap s at b segs) %py-c-string (Str8 sub b (- e b) s)))))))
          ((not (str? text)) (self s (rest toks) at n segs))
          (#t
            (let ((p (%py-find s text at n)))
              (if (null? p) (%py-paint-tail s at n segs)
                (let ((e (+ p (Str8 length text))))
                  (self s (rest toks) e n
                        (%py-seg (%py-gap s at p segs) (%py-token-code kind text)
                                 (Str8 sub p (- e p) s))))))))))))

(def %py-paint
  (fn (_ s)
    (if (not (guard (_ #f) (Ansi enabled?))) s
      (guard (_ s)
        (let ((n (Str8 length s)))
          (let ((toks (%py-tokens-of s)))
            (if (if (null? toks) (> n 0) #f)
              ; Nothing tokenized: paint the bytes before the first quote by
              ; their own tokens and the rest as the string it is.
              (let ((q (%py-quote-from s 0 n)))
                (if (null? q) s
                  (Str8 join "" (List reverse
                    (%py-seg (%py-paint-tokens s (%py-tokens-of (Str8 sub 0 q s)) 0 q ())
                             %py-c-string (Str8 sub q (- n q) s))))))
              (Str8 join "" (List reverse (%py-paint-tokens s toks 0 n ()))))))))))

; --- completion ---------------------------------------------------------------

; Names defined at the prompt, recorded by the loop as each definition is
; lifted, so that a function defined on one line completes on the next.
(def %py-session-names ())

; The identifier being typed: the letters, digits and underscores before the
; cursor.
(def %py-word-at
  (fn (_ ed)
    (let ((before (ed before)))
      (let ((n (Str8 length before)))
        (let ((go (fn (self i)
                    (if (<= i 0) 0
                      (let ((c (Str8 ref (- i 1) before)))
                        (if (if (Char alphabetic? c) #t (if (Char numeric? c) #t (eq? c #\_)))
                          (self (- i 1)) i))))))
          (Str8 sub (go n) (- n (go n)) before))))))

(def %py-complete
  (fn (_ ed)
    (let ((word (%py-word-at ed)))
      (pair word
        (if (= 0 (Str8 length word)) ()
          (List sort (fn (_ a b) (Str8 <? a b))
            (List distinct
              (List filter (fn (_ name) (Str8 starts? word name))
                (List append %py-keywords
                  (List append (%py-builtin-names) %py-session-names))))))))))

; --- installation -------------------------------------------------------------

(def %py-line-install!
  (fn (_)
    (%py-paint-install!)
    (guard (_ ()) (set! %repl-paint %py-paint))
    (guard (_ ()) (Line completer %py-complete))))

(%py-line-install!)
(guard (_ ())
  (set! %image-recache-hooks (pair (fn (_) (%py-line-install!)) %image-recache-hooks)))

(provide python/line %py-read %py-paint %py-complete %py-word-at %py-session-names)
