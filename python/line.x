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
; being typed.  So this file scans spans itself -- comments, strings with
; their prefixes and triple quotes, numbers, names, decorators and brackets
; -- and classifies a name lexically: the keyword list the tokenizer reads,
; the builtin table the parser reads, True/False/None, a leading capital.
; The answer for a name is memoised.
;
; The colours are repl/ansi.x's, in the classes the platform painter uses
; for the same things, so a keyword, a literal and a class look the same
; being typed in either language.  A colourless terminal short-circuits the
; scan, and the last line painted is kept by identity, since a redraw whose
; text has not changed asks for the same bytes again.
;
; The scan runs on every keystroke, so it is %-private functions over cached
; prims -- the rule x/repl/paint states -- and the palette is built once.

(import python/util)
(import python/tokens)
(import python/parse)
(import x/type/dict)
(import x/type/str)
(import x/type/list)
(import x/repl/ansi)
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

; --- cached prims ------------------------------------------------------------
(def %pp-bref   (prim-ref (lit str)  (lit byte-ref)))
(def %pp-blen   (prim-ref (lit str)  (lit byte-len)))
(def %pp-bsub   (prim-ref (lit str)  (lit byte-sub)))
(def %pp-append (prim-ref (lit str)  (lit append)))
(def %pp-cint   (prim-ref (lit char) (lit ->int)))
(def %pp-same?  (prim-ref (lit obj)  (lit same?)))

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
(def %pp-quote? (fn (_ b) (if (= b 34) #t (= b 39))))
(def %pp-open? (fn (_ b) (if (= b 40) #t (if (= b 91) #t (= b 123)))))
(def %pp-close? (fn (_ b) (if (= b 41) #t (if (= b 93) #t (= b 125)))))
(def %pp-bracket? (fn (_ b) (if (%pp-open? b) #t (%pp-close? b))))
; A byte that starts a token the scan colours; everything else joins a plain
; run.  `.` starts a number only before a digit, which the scan checks.
(def %pp-starter?
  (fn (_ b)
    (match
      ((= b 35) #t)
      ((%pp-quote? b) #t)
      ((%pp-digit? b) #t)
      ((%pp-ident-start? b) #t)
      ((= b 64) #t)
      ((= b 46) #t)
      (#t (%pp-bracket? b)))))

; --- span ends ---------------------------------------------------------------
(def %pp-to-eol
  (fn (self s i n)
    (if (>= i n) i (if (= 10 (%pp-byte s i)) i (self s (+ i 1) n)))))

; To the closing quote q, honouring backslash escapes; an unterminated string
; runs to the end of the line, the optimistic answer a half-typed line needs.
(def %pp-str-end
  (fn (self s i n q)
    (if (>= i n) n
      (let ((b (%pp-byte s i)))
        (if (= b 92) (self s (+ i 2) n q)
          (if (= b q) (+ i 1) (self s (+ i 1) n q)))))))

; To the closing triple quote, or the end of the line.
(def %pp-str3-end
  (fn (self s i n q)
    (if (>= (+ i 2) n) n
      (let ((b (%pp-byte s i)))
        (match
          ((= b 92) (self s (+ i 2) n q))
          ((if (= b q) (if (= (%pp-byte s (+ i 1)) q) (= (%pp-byte s (+ i 2)) q) #f) #f)
            (+ i 3))
          (#t (self s (+ i 1) n q)))))))

; The end of a string whose opening quote is at i: triple or single.
(def %pp-string-end
  (fn (_ s i n)
    (let ((q (%pp-byte s i)))
      (if (if (< (+ i 2) n) (if (= (%pp-byte s (+ i 1)) q) (= (%pp-byte s (+ i 2)) q) #f) #f)
        (%pp-str3-end s (+ i 3) n q)
        (%pp-str-end s (+ i 1) n q)))))

; A number's end: digits, letters, underscores and dots, plus a sign right
; after an exponent letter, so 1.5e-3 is one token.
(def %pp-num-end
  (fn (self s i n prev)
    (if (>= i n) i
      (let ((b (%pp-byte s i)))
        (match
          ((%pp-ident? b) (self s (+ i 1) n b))
          ((= b 46) (self s (+ i 1) n b))
          ((if (if (= b 43) #t (= b 45)) (if (= prev 101) #t (= prev 69)) #f)
            (self s (+ i 1) n b))
          (#t i))))))

(def %pp-ident-end
  (fn (self s i n)
    (if (>= i n) i (if (%pp-ident? (%pp-byte s i)) (self s (+ i 1) n) i))))

; To the end of a run of bytes that start no token.
(def %pp-plain-end
  (fn (self s i n)
    (if (>= i n) i
      (let ((b (%pp-byte s i)))
        (if (%pp-starter? b)
          (if (if (= b 46) (not (if (< (+ i 1) n) (%pp-digit? (%pp-byte s (+ i 1))) #f)) #f)
            (self s (+ i 1) n)
            i)
          (self s (+ i 1) n))))))

; Whether the name in [i, e) is a string prefix -- r, b, u, f, rb, br, fr, rf
; in either case -- with a quote right after it.
(def %pp-prefix?
  (fn (_ s i e n)
    (if (if (< e n) (%pp-quote? (%pp-byte s e)) #f)
      (let ((len (- e i)))
        (if (if (>= len 1) (<= len 2) #f)
          (let ((ok? (fn (_ b)
                       (let ((c (if (>= b 97) (- b 32) b)))
                         (if (= c 82) #t (if (= c 66) #t (if (= c 85) #t (= c 70))))))))
            (if (ok? (%pp-byte s i))
              (if (= len 2) (ok? (%pp-byte s (+ i 1))) #t)
              #f))
          #f))
      #f)))

; --- classifying a name ------------------------------------------------------
(def %pp-kw ())        ; Dict: keyword -> #t
(def %pp-bi ())        ; Dict: builtin -> #t
(def %pp-memo ())      ; Dict: name -> class
(def %pp-kw-get ())
(def %pp-bi-get ())
(def %pp-memo-get ())
(def %pp-memo-set ())

(def %pp-class-of
  (fn (_ name)
    (match
      ((%pp-kw-get #f name) (lit keyword))
      ((if (Str8 =? name "True") #t (if (Str8 =? name "False") #t (Str8 =? name "None")))
        (lit bool))
      ((%pp-bi-get #f name) (lit builtin))
      ((let ((b0 (%pp-byte name 0))) (if (>= b0 65) (<= b0 90) #f)) (lit class))
      (#t (lit name)))))

(def %py-paint-class
  (fn (_ name)
    (let ((hit (%pp-memo-get () name)))
      (if (null? hit)
        (let ((cls (%pp-class-of name)))
          (%pp-memo-set name cls)
          cls)
        hit))))

; --- the palette -------------------------------------------------------------
(def %pp-classes
  (list (lit keyword) (lit bool) (lit builtin) (lit class) (lit name)
        (lit number) (lit string) (lit comment) (lit decorator) (lit plain)))
(def %pp-pal ())
(def %pp-rst "")
(def %pp-depth ())
(def %pp-depth-n 3)
(def %pp-lone "")
(def %pp-focus "")
(def %pp-last-in ())
(def %pp-last-out ())
(def %pp-last-marks ())

(def %pp-code
  (fn (_ cls)
    (let ((go (fn (self names codes)
                (match
                  ((null? names) "")
                  ((eq? cls (first names)) (first codes))
                  (#t (self (rest names) (rest codes)))))))
      (go %pp-classes %pp-pal))))

(def %pp-depth-code
  (fn (_ depth focused)
    (let ((base (if (< depth 0) %pp-lone
                  (let ((go (fn (self k codes)
                              (if (null? codes) ""
                                (if (= k 0) (first codes) (self (- k 1) (rest codes)))))))
                    (go (% depth %pp-depth-n) %pp-depth)))))
      (if focused (%pp-append base %pp-focus) base))))

; The painter's answer for a token: its class's code, or a bracket's depth
; code.  The scan takes this as a function so a spec can ask for classes
; instead of codes (%py-paint-tokens).
(def %pp-painter
  (fn (_ cls depth focused)
    (if (eq? cls (lit bracket)) (%pp-depth-code depth focused) (%pp-code cls))))
(def %pp-classer (fn (_ cls depth focused) cls))

; --- bracket marks -----------------------------------------------------------
;
; A mark for every bracket: (offset depth focused), the shape x/repl/paint
; answers for parens.  Depth is the nesting level from 0, shared by the two
; halves of a pair; a close with nothing to close is -1.  Focused is true on
; the pair the cursor is beside: a close just before the cursor first, then
; an open under it, a close under it, an open before it.  Strings and
; comments are stepped over with the scan's own rules.
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
            (let ((go (fn (self i open depth acc)
                        (if (>= i n) (List reverse acc)
                          (let ((b (%pp-byte s i)))
                            (match
                              ((= b 35) (self (%pp-to-eol s i n) open depth acc))
                              ((%pp-quote? b) (self (%pp-string-end s i n) open depth acc))
                              ((%pp-open? b)
                                (self (+ i 1) (pair (pair i depth) open) (+ depth 1)
                                      (pair (list i depth #f) acc)))
                              ((%pp-close? b)
                                (if (null? open)
                                  (self (+ i 1) () 0 (pair (list i -1 (= i target)) acc))
                                  (let ((o (first (first open))) (d (rest (first open))))
                                    (let ((hit (if (= i target) #t (= o target))))
                                      (self (+ i 1) (rest open) d
                                            (pair (list i d hit)
                                                  (if hit (flag acc o) acc)))))))
                              (#t (self (+ i 1) open depth acc))))))))
              (go 0 () 0 ()))))))))

(def %pp-marks-from
  (fn (self marks i)
    (if (null? marks) ()
      (if (< (first (first marks)) i) (self (rest marks) i) marks))))

(def %pp-same-marks?
  (fn (self a b)
    (if (null? a) (null? b)
      (if (null? b) #f
        (let ((x (first a)) (y (first b)))
          (if (if (= (first x) (first y))
                (if (= (first (rest x)) (first (rest y)))
                  (eq? (first (rest (rest x))) (first (rest (rest y)))) #f) #f)
            (self (rest a) (rest b))
            #f))))))

; --- the scan ----------------------------------------------------------------
;
; Builds the segment list reversed: (code . text) pairs, where code is
; whatever `code-of` answers for the token's class.  A plain run -- spaces,
; operators, brackets nobody marked -- goes out as one segment, cut where a
; mark falls so the marked bracket gets its own.
(def %pp-scan
  (fn (self s i n segs marks code-of)
    (if (>= i n) segs
      (let ((b (%pp-byte s i)))
        (match
          ((= b 35)
            (let ((e (%pp-to-eol s i n)))
              (self s e n (pair (pair (code-of (lit comment) 0 #f) (%pp-bsub s i (- e i))) segs)
                    marks code-of)))
          ((%pp-quote? b)
            (let ((e (%pp-string-end s i n)))
              (self s e n (pair (pair (code-of (lit string) 0 #f) (%pp-bsub s i (- e i))) segs)
                    marks code-of)))
          ((if (%pp-digit? b) #t (if (= b 46) (if (< (+ i 1) n) (%pp-digit? (%pp-byte s (+ i 1))) #f) #f))
            (let ((e (%pp-num-end s (+ i 1) n b)))
              (self s e n (pair (pair (code-of (lit number) 0 #f) (%pp-bsub s i (- e i))) segs)
                    marks code-of)))
          ((%pp-ident-start? b)
            (let ((e (%pp-ident-end s (+ i 1) n)))
              (if (%pp-prefix? s i e n)
                (let ((e2 (%pp-string-end s e n)))
                  (self s e2 n (pair (pair (code-of (lit string) 0 #f) (%pp-bsub s i (- e2 i))) segs)
                        marks code-of))
                (let ((text (%pp-bsub s i (- e i))))
                  (self s e n (pair (pair (code-of (%py-paint-class text) 0 #f) text) segs)
                        marks code-of)))))
          ((if (= b 64) (if (< (+ i 1) n) (%pp-ident-start? (%pp-byte s (+ i 1))) #f) #f)
            (let ((e (%pp-ident-end s (+ i 1) n)))
              (self s e n (pair (pair (code-of (lit decorator) 0 #f) (%pp-bsub s i (- e i))) segs)
                    marks code-of)))
          (#t
            (let ((e (%pp-plain-end s (+ i 1) n))
                  (ms (%pp-marks-from marks i)))
              (if (if (null? ms) #t (>= (first (first ms)) e))
                (self s e n (pair (pair (code-of (lit plain) 0 #f) (%pp-bsub s i (- e i))) segs)
                      ms code-of)
                (let ((m (first ms)))
                  (let ((c (first m)))
                    (self s (+ c 1) n
                      (pair (pair (code-of (lit bracket) (first (rest m)) (first (rest (rest m))))
                                  (%pp-bsub s c 1))
                            (if (> c i) (pair (pair (code-of (lit plain) 0 #f) (%pp-bsub s i (- c i))) segs) segs))
                      (rest ms) code-of)))))))))))

; Segments to text: a code wraps its text and is followed by a reset; an
; empty code -- a class with no colour, or colour off -- emits bare text.
(def %pp-join
  (fn (self segs acc)
    (if (null? segs) acc
      (let ((code (first (first segs))) (text (rest (first segs))))
        (self (rest segs)
              (if (= 0 (%pp-blen code)) (%pp-append text acc)
                (%pp-append code (%pp-append text (%pp-append %pp-rst acc)))))))))

; --- the three answers the editor asks for ----------------------------------

(def %py-paint
  (fn (_ s . marks)
    (if (not (Ansi enabled?)) s
      (let ((ms (if (null? marks) () (first marks))))
        (if (if (%pp-same? s %pp-last-in) (%pp-same-marks? ms %pp-last-marks) #f)
          %pp-last-out
          (let ((out (%pp-join (%pp-scan s 0 (%pp-blen s) () ms %pp-painter) "")))
            (set! %pp-last-in s)
            (set! %pp-last-marks ms)
            (set! %pp-last-out out)
            out))))))

(def %py-marks (fn (_ s at) (%pp-depths s at)))

; The scan's tokens as (class . text), brackets marked with no cursor -- what
; a spec checks, colour or no colour.
(def %py-paint-tokens
  (fn (_ s)
    (List reverse (%pp-scan s 0 (%pp-blen s) () (%pp-depths s -1) %pp-classer))))

; --- completion --------------------------------------------------------------
;
; The keywords, the builtins and the names defined at the prompt, by prefix,
; sorted and each once.  An empty word answers nothing rather than the whole
; table.

; Names defined at the prompt, recorded by the loop as each definition is
; lifted, so that a function defined on one line completes on the next.
(def %py-session-names ())
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

(def %py-complete
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
; may have a terminal the writer did not -- so the palette is built by a
; function the image recache hook calls again, and the memo with it.  The
; three seams are set here as well as registered by python/repl.x: on a
; platform without x/repl/lang this is the whole of the install, and on one
; with it the values are the same ones the lang "python" carries.
(def %py-line-install!
  (fn (_)
    (set! %pp-kw (Dict make))
    (List for-each (fn (_ k) (%pp-kw set! k #t)) %py-keywords)
    (set! %pp-bi (Dict make))
    (List for-each (fn (_ row) (%pp-bi set! (first row) #t)) %py-builtins)
    (set! %pp-memo (Dict make))
    (set! %pp-kw-get (method-ref %pp-kw get-or))
    (set! %pp-bi-get (method-ref %pp-bi get-or))
    (set! %pp-memo-get (method-ref %pp-memo get-or))
    (set! %pp-memo-set (method-ref %pp-memo set!))
    (set! %pp-names (List append %py-keywords (List map (fn (_ row) (first row)) %py-builtins)))
    (set! %pp-rst (Ansi reset))
    (set! %pp-pal
      (list (%pp-append (Ansi bold) (Ansi magenta)) ; keyword, as x's constructs
            (Ansi bold-red)                         ; bool: True False None
            (Ansi blue)                             ; builtin, as x's symbols
            (Ansi bold-cyan)                        ; class: a capitalised name
            ""                                      ; name
            (Ansi yellow)                           ; number
            (Ansi green)                            ; string
            (Ansi dim)                              ; comment
            (Ansi magenta)                          ; decorator
            ""))                                    ; plain
    (set! %pp-depth (list (Ansi yellow) (Ansi magenta) (Ansi cyan)))
    (set! %pp-lone (Ansi bold-red))
    ; Inverse video, from the Ansi class where it carries it.  The pinned
    ; release's Ansi has no inverse, and there the platform's %sgr answers.
    (set! %pp-focus (guard (_ (%sgr "7")) (Ansi inverse)))
    (set! %pp-last-in ())
    (set! %pp-last-out ())
    (set! %pp-last-marks ())
    (guard (_ ()) (set! %repl-paint %py-paint))
    (guard (_ ()) (set! %repl-marks %py-marks))
    (guard (_ ()) (Line completer %py-complete))
    ()))

(%py-line-install!)
(set! %image-recache-hooks (pair (fn (_) (%py-line-install!)) %image-recache-hooks))

(provide python/line
  %py-read %py-paint %py-marks %py-paint-tokens %py-paint-class
  %py-complete %py-word-at %py-session-names)
