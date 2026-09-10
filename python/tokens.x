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

(import python/util)

(provide python/tokens
  python-tokenize %py-base %py-keywords
  mk-tok-name mk-tok-kw mk-tok-number mk-tok-string mk-tok-op mk-tok-newline
  mk-tok-bytes mk-tok-fstring mk-tok-group mk-tok-block)

; (Base make-tok) is the isolated, type-free base -- 2024's make-token-base.
(import x/reader/indent)

; THE TOKENIZER BASE IS PROCESS STATE.  (Base make-tok) allocates it on a
; chain of its own, so a state image cannot carry it: the writer images
; %py-base as nil and %py-tok-reset! (end of file) remakes it after a load,
; exactly as it makes it here.  Each type RECORDS itself in this table as its
; handlers are defined, and %py-tok-base-make walks the table in that order --
; the one registration list, read at load and after every image load alike.
(def %py-tok-types (pair () ()))   ; ((name . handlers) ...), newest first
(def %py-tok-type!
  (fn (_ nm hs)
    (%set-first! %py-tok-types (pair (pair nm hs) (first %py-tok-types)))))
(def %py-tok-base-make
  (fn (_)
    (let ((b (Base make-tok)))
      ((fn (self l)
         (if (null? l) ()
           (do (self (rest l))
               (Base make-type b (first (first l)) (rest (first l))))))
       (first %py-tok-types))
      b)))
(def %py-base ())

; The platform owns the tokenizer intrinsics (lib/x/reader/intrinsics.x); these
; run per character, so they are the platform's own tested versions rather than
; a second copy of the same contract.
(def %py-token-read-string (prim-ref (lit tok) (lit read-str)))
; %buffer-len / %buffer-unread / %score-set are globals from
; lib/x/reader/intrinsics.x; the token accessor is not, and every module that
; wants it fetches it the same way (num/bigint.x, num/complex.x).
(def %buffer-token (prim-ref (lit buf) (lit tok)))
(def %py-char->int (prim-ref (lit char) (lit ->int)))

; --- The variant channel --------------------------------------------------------
; A NUMBER TOKEN CARRIES ITS VARIANT, decided where it is known.  The analyser's
; states already tell an integer from a fraction from an exponent from an
; imaginary from a based literal, by which state accepts -- and used to throw
; that away, leaving %py-num to rescan the text through the Str8 class at
; ~200,000 objects a literal.  Now the accepting state declares it:
;
;   1 integer    2 float (a fraction or an exponent)    3 imaginary    4 based
;
; and the token is (tok-number "text" VARIANT).
;
; TWO DOORS, ONE FALLBACK.  On a platform with the channel (x-lang
; reader/intrinsics.x: %score-variant! at the analyser's end, %read-variant at the
; reader's; the engine hangs a variant cell off the score), the state's
; declaration reaches the read handler.  On one without, both names are
; unbound, the two doors below answer nothing, and the read handler derives
; the same variant from the text through the raw byte primitives -- so the token
; stream is identical either way, and %py-num never rescans.
(def %py-variant! (guard (e (fn (_ score variant) ())) %score-variant!))
(def %py-read-variant (guard (e (fn (_ args) ())) %read-variant))

(def %py-code-at (fn (_ s i) (%py-char->int (%str-ref s i))))

; 0x 0o 0b at i, in either case
(def %py-based-at?
  (fn (_ s i n)
    (if (< (- n i) 3) #f
      (if (not (= (%py-code-at s i) 48)) #f
        (let ((c (%py-code-at s (+ i 1))))
          (match
            ((if (= c 120) #t (= c 88)) #t)
            ((if (= c 111) #t (= c 79)) #t)
            ((if (= c 98) #t (= c 66)) #t)
            (#t #f)))))))

; a dot or an exponent marker anywhere from i
(def %py-floaty?
  (fn (self s i n)
    (if (>= i n) #f
      (let ((c (%py-code-at s i)))
        (if (match ((= c 46) #t) ((= c 101) #t) ((= c 69) #t) (#t #f))
          #t
          (self s (+ i 1) n))))))

; The fallback: the variant read off the text, in the order the analyser would
; have decided it -- based before float, so 0xe1's e is a digit; imaginary
; before float, so 2.5j is imaginary.
(def %py-variant-of-text
  (fn (_ s)
    (let ((n (%py-byte-len s)))
      (let ((i (let ((c0 (%py-code-at s 0))) (if (if (= c0 45) #t (= c0 43)) 1 0))))
        (match
          ((%py-based-at? s i n) 4)
          ((let ((cl (%py-code-at s (- n 1)))) (if (= cl 106) #t (= cl 74))) 3)
          ((%py-floaty? s i n) 2)
          (#t 1))))))
; The list->string spelling ash arrived at: %cvt to the string type, with the
; empty list special-cased because a conversion of nothing has no type to go on.
(def %py-list->string (fn (_ l) (if (null? l) "" (%cvt l %string))))

; --- Token values ------------------------------------------------------------
; Plain lists, the shape ash settled on: readable in a spec without a printer.
(def mk-tok-name    (fn (_ s) (list (lit tok-name) s)))
(def mk-tok-kw      (fn (_ s) (list (lit tok-kw) s)))
(def mk-tok-number  (fn (_ s k) (list (lit tok-number) s k)))
(def mk-tok-string  (fn (_ s) (list (lit tok-string) s)))
(def mk-tok-op      (fn (_ s) (list (lit tok-op) s)))
(def mk-tok-bytes   (fn (_ s) (list (lit tok-bytes) s)))
; An f-string keeps its RAW (unescaped) text; the parser splits the fields.
(def mk-tok-fstring (fn (_ s) (list (lit tok-fstring) s)))
; A bracketed run, already nested by the reader: (tok-group "[" (tok ...) "]").
; THE FOURTH FIELD IS HOW THE GROUP ENDED -- the closing bracket it actually
; met, or nil for a group that ran out at EOF.  The lexer only records it; the
; parser is what judges a missing or mismatched closer (python/parse.x).
(def mk-tok-group   (fn (_ open elems closer) (list (lit tok-group) open elems closer)))
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

(def %py-t-ws
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (if (= chr #\space) #t (= chr #\tab))
          (%seq (%score-set score (- 0 1) buffer) %py-ws-continue)
          ())))))
(%py-tok-type! "PY-WS" %py-t-ws)

; --- PY-COMMENT: # to end of line, discarded ---------------------------------
; The newline is given back, because it is a NEWLINE token and a comment must
; not swallow the line structure it sits on.
(def %py-comment-body ())
(set! %py-comment-body
  (fn (_ buffer score chr)
    (if (= chr #\newline)
      (%seq (%buffer-unread buffer) (%score-set score (- 0 1) buffer))
      %py-comment-body)))

(def %py-t-comment
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr 35)
          (%seq (%score-set score (- 0 1) buffer) %py-comment-body)
          ())))))
(%py-tok-type! "PY-COMMENT" %py-t-comment)

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
          (match
            ((null? v) (mk-tok-block (%py-reverse acc)))
            ((eq? v (lit %py-dedent)) (mk-tok-block (%py-reverse acc)))
            ; a nested block may have closed more levels than its own
            ((> (first %py-owed) 0)
              (%seq (%set-first! %py-owed (- (first %py-owed) 1))
                (mk-tok-block (%py-reverse (pair v acc)))))
            (#t (self (pair v acc)))))))
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

(def %py-t-blank
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (= chr #\newline) %py-blank-ws ())))))
(%py-tok-type! "PY-BLANK" %py-t-blank)

(def %py-t-nl
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
(%py-tok-type! "PY-NL" %py-t-nl)

; --- PY-KEYWORD: the keywords, decided by the analyser ------------------------
;
; A KEYWORD IS DECIDED HERE, PER CHARACTER, NOT IN THE PARSER BY STRING.  The
; analyser is the engine's own per-character path -- C driving it in the
; interpreted base, native code in the compiled one -- and it already visits
; every character of every name.  Deciding `if` there costs nothing more;
; deciding it in the parser cost a string compare at every grammar question
; that asked, 444 of them for an eight-line program, each a Str8 =? class call
; (19,347 objects on a hit).  So the token arrives classified, (tok-kw "if"),
; and the parser asks the tag.
;
; THE TRIE IS GENERATED FROM %py-keywords, once, at load: one node per
; distinct prefix (121 for these 32), each a state that dispatches on the next
; character to a child state.  A TERMINAL accepts only when the character
; after the keyword is not a name character: `ifx` is a name, and the terminal
; answering nil is what lets PY-NAME's longer match take it.  `as` is the one
; terminal with children (assert, async), so every node tries its children
; before it accepts.
;
; REGISTERED BEFORE PY-NAME, AND THE ORDER IS THE RULE.  Registration prepends
; to the base's type alist, analyse iterates it, and the C loop's >= hands a
; tie to the LATER-iterated type -- so the EARLIER-registered type wins an
; equal-length match, the same rule by which PY-NAME's `b` beats PY-PSQ's.
; `if` scores 2 for both types; PY-KEYWORD wins by being registered first.
; The compiled base registers in the same order for the same reason.
;
; True, False and None are not here: this bundle carries them as builtins, and
; keyword.kwlist's three extra rows are the whole difference.  The soft
; keywords (match, case, type, _) are names, as they are in Python.
(def %py-keywords
  (list "if" "elif" "else" "while" "def" "return" "pass" "and" "or" "not"
        "in" "is" "for" "break" "continue" "class" "import" "from" "as"
        "try" "except" "finally" "raise" "with" "lambda" "global" "nonlocal"
        "assert" "del" "yield" "async" "await"))

; A trie node is (terminal? . children), the children an alist of
; (code . node).  Insertion is immutable: the path to a keyword is rebuilt,
; everything beside it shared.
(def %py-kw-child
  (fn (self kids c)
    (if (null? kids) ()
      (if (= (first (first kids)) c) (rest (first kids)) (self (rest kids) c)))))

(def %py-kw-replace
  (fn (self kids c node)
    (if (null? kids) (list (pair c node))
      (if (= (first (first kids)) c)
        (pair (pair c node) (rest kids))
        (pair (first kids) (self (rest kids) c node))))))

(def %py-kw-insert
  (fn (self node cs)
    (if (null? cs)
      (pair #t (rest node))
      (let ((c (first cs)))
        (let ((kid (%py-kw-child (rest node) c)))
          (pair (first node)
            (%py-kw-replace (rest node) c
              (self (if (null? kid) (pair #f ()) kid) (rest cs)))))))))

(def %py-kw-codes
  (fn (self s i acc)
    (if (< i 0) acc
      (self s (- i 1) (pair (%py-char->int (Str8 ref i s)) acc)))))

(def %py-kw-trie
  ((fn (self ks node)
     (if (null? ks) node
       (self (rest ks)
         (%py-kw-insert node (%py-kw-codes (first ks) (- (Str8 length (first ks)) 1) ())))))
   %py-keywords (pair #f ())))

; The interpreted states: one closure per node, built bottom-up, each holding
; its own (code . state) table.  A state receives the NEXT character: a child
; for it is a transition; none, and a terminal accepts unless a name
; character follows (a longer identifier -- PY-NAME's match must win), a
; non-terminal rejects.  The walk per character is over that node's own
; children only: the root's sixteen first letters at a token start, one or
; two deeper in.
(def %py-kw-state
  (fn (kw-state node)
    (let ((terminal (first node))
          (kids ((fn (go ks acc)
                   (if (null? ks) acc
                     (go (rest ks) (pair (pair (first (first ks)) (kw-state (rest (first ks)))) acc))))
                 (rest node) ())))
      (fn (_ buffer score chr)
        (let ((next (%py-kw-child kids chr)))
          (if (not (null? next))
            next
            (if terminal
              (if (%py-name-rest? chr) () (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))
              ())))))))

(def %py-kw-entry (%py-kw-state %py-kw-trie))

(def %py-t-kw
  (list
    (pair (lit analyse) %py-kw-entry)
    (pair (lit read)
      (fn (_ . args) (mk-tok-kw (%buffer-token (first args)))))))
(%py-tok-type! "PY-KEYWORD" %py-t-kw)

; The compiled states: the same trie, one native state per node, generated
; as forms for compile-asm.  A node's children are its free variables, named
; from %py-kw-fvar-names in order (sixteen: the root's count).  The 31 leaves
; are ONE compiled state shared by all -- a terminal has no free variable, so
; it carries the unused `u` that forces analyser mode.  Nested ifs, not match:
; the assembler lane has no match and refuses the form, which is also why the
; number states in %py-jit-compile! are spelled that way.
(def %py-kw-namechar-form
  (lit (or (and (>= chr 97) (<= chr 122))
           (and (>= chr 65) (<= chr 90))
           (or (= chr 95) (and (>= chr 48) (<= chr 57))))))
(def %py-kw-accept-form
  (lit (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))
(def %py-kw-fvar-names (lit (a b c d e f g h i j k l m n o p)))

(def %py-kw-tail-form
  (fn (_ terminal)
    (if terminal (list (lit if) %py-kw-namechar-form () %py-kw-accept-form) ())))

; (if (= chr c1) n1 (if (= chr c2) n2 ... tail))
(def %py-kw-dispatch-form
  (fn (self kids names tail)
    (if (null? kids) tail
      (list (lit if) (list (lit =) (lit chr) (first (first kids))) (first names)
        (self (rest kids) (rest names) tail)))))

(def %py-kw-fvars
  (fn (self kids names acc)
    (if (null? kids) acc
      (self (rest kids) (rest names) (pair (pair (first names) (rest (first kids))) acc)))))

; The shared compiled leaf, made fresh by each JIT attempt (native code is
; this process's alone, like every compiled state).
(def %py-kw-leaf (pair () ()))

(def %py-kw-compile
  (fn (kw-compile node)
    (if (if (first node) (null? (rest node)) #f)
      (first %py-kw-leaf)
      (let ((kids ((fn (go ks acc)
                     (if (null? ks) acc
                       (go (rest ks) (pair (pair (first (first ks)) (kw-compile (rest (first ks)))) acc))))
                   (rest node) ())))
        (%py-jit-keep!
          (compile-asm
            (list (lit fn) (lit (_ buffer score chr))
              (%py-kw-dispatch-form kids %py-kw-fvar-names (%py-kw-tail-form (first node))))
            (%py-kw-fvars kids %py-kw-fvar-names ())))))))

; --- PY-NAME: identifiers ------------------------------------------------------
; Keywords are PY-KEYWORD's, above, and take the tie by registration order;
; what reaches here is every name that is not one.
(def %py-name-body ())
(set! %py-name-body
  (fn (_ buffer score chr)
    (if (%py-name-rest? chr)
      %py-name-body
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(def %py-t-name
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-name-start? chr) %py-name-body ())))
    (pair (lit read)
      (fn (_ . args) (mk-tok-name (%buffer-token (first args)))))))
(%py-tok-type! "PY-NAME" %py-t-name)

; --- PY-NUMBER: integers and floats ------------------------------------------
; The value is kept as its SOURCE TEXT.  Python's int is arbitrary-precision and
; its float is IEEE 754, and which one a literal denotes is a question with a
; right answer that belongs to the evaluator -- a tokenizer that converts early
; has to know the tower, and gets `1_000` and `0x10` wrong quietly.
; AN EXPONENT IS PART OF THE LITERAL.  `1e10` is one number in Python, and a
; tokenizer without an exponent state hands the parser `1` followed by the
; name `e10` -- a silent wrong number when the parser copes and a confusing
; syntax error when it does not.  The path never sets a score until a digit
; follows the `e`, so `1e`, `1e+` and `12ea` reject the WHOLE number candidacy
; -- which is Python's answer too: `1e` is a SyntaxError, not `1` and a name.
;
; UNDERSCORES CONTINUE A NUMBER (`1_000.1_8`), loosely: the lexer accepts them
; anywhere between the digits and the value parser strips them.  Python is
; stricter (`1_` is an error); the looseness costs an accepted-then-mis-parsed
; literal nothing today because the parse strips exactly what this accepted.
(def %py-number-frac ())
(def %py-number-body ())
(def %py-number-exp-digits ())

; A j OR J ENDS THE LITERAL AS AN IMAGINARY, accepted INCLUDING the suffix:
; `2j`, `1.5j`, `1e3j`.  The parse strips it and builds the complex.
(set! %py-number-exp-digits
  (fn (_ buffer score chr)
    (match
      ((%py-digit? chr) %py-number-exp-digits)
      ((= chr 95) %py-number-exp-digits)
      ((if (= chr 106) #t (= chr 74)) (%seq (%py-variant! score 3) (%score-set score 1 buffer)))
      (#t (%seq (%buffer-unread buffer) (%seq (%py-variant! score 2) (%score-set score 1 buffer)))))))

; After the `e`: an optional sign, then at least one digit.
(def %py-number-exp-first
  (fn (_ buffer score chr)
    (if (%py-digit? chr) %py-number-exp-digits ())))

(def %py-number-exp-sign
  (fn (_ buffer score chr)
    (if (%py-digit? chr)
      %py-number-exp-digits
      (if (if (= chr 43) #t (= chr 45)) %py-number-exp-first ()))))

(set! %py-number-frac
  (fn (_ buffer score chr)
    (match
      ((%py-digit? chr) %py-number-frac)
      ((= chr 95) %py-number-frac)
      ((if (= chr 101) #t (= chr 69)) %py-number-exp-sign)
      ((if (= chr 106) #t (= chr 74)) (%seq (%py-variant! score 3) (%score-set score 1 buffer)))
      (#t (%seq (%buffer-unread buffer) (%seq (%py-variant! score 2) (%score-set score 1 buffer)))))))

(set! %py-number-body
  (fn (_ buffer score chr)
    (match
      ((%py-digit? chr) %py-number-body)
      ((= chr 95) %py-number-body)
      ((= chr 46) %py-number-frac)
      ((if (= chr 101) #t (= chr 69)) %py-number-exp-sign)
      ((if (= chr 106) #t (= chr 74)) (%seq (%py-variant! score 3) (%score-set score 1 buffer)))
      (#t (%seq (%buffer-unread buffer) (%seq (%py-variant! score 1) (%score-set score 1 buffer)))))))

; 0x 0o 0b: a zero, the base letter, then that base's digits (underscores
; allowed).  The parse reads the base back off the text.
(def %py-number-based ())
(set! %py-number-based
  (fn (_ buffer score chr)
    (if (match
          ((%py-digit? chr) #t)
          ((if (>= chr 97) (<= chr 102) #f) #t)
          ((if (>= chr 65) (<= chr 70) #f) #t)
          (#t (= chr 95)))
      %py-number-based
      (%seq (%buffer-unread buffer) (%seq (%py-variant! score 4) (%score-set score 1 buffer))))))
(def %py-number-base-first
  (fn (_ buffer score chr)
    (if (match
          ((%py-digit? chr) #t)
          ((if (>= chr 97) (<= chr 102) #f) #t)
          ((>= chr 65) (<= chr 70))
          (#t #f))
      %py-number-based
      ())))
; After a leading 0: x/X o/O b/B open a based literal; otherwise the body.
(def %py-number-zero
  (fn (_ buffer score chr)
    (if (match
          ((= chr 120) #t)
          ((= chr 88) #t)
          ((= chr 111) #t)
          ((= chr 79) #t)
          ((= chr 98) #t)
          (#t (= chr 66)))
      %py-number-base-first
      (%py-number-body buffer score chr))))

; A LEADING DOT STARTS A FLOAT (`.1`), but only when a digit follows: the
; entry moves through this state without setting a score, so a bare `.` or
; `.method` rejects the number candidacy and PY-OP's one-character match wins.
(def %py-number-dot-first
  (fn (_ buffer score chr)
    (if (%py-digit? chr) %py-number-frac ())))

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
    ; a signed zero may open a based literal: -0x10
    (if (= chr 48) %py-number-zero
      (if (%py-digit? chr) %py-number-body ()))))

(def %py-t-number
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (match
          ((= chr 48) %py-number-zero)
          ((%py-digit? chr) %py-number-body)
          ((= chr 46) %py-number-dot-first)
          ((if (= chr 43) #t (= chr 45)) %py-number-signed)
          (#t ()))))
    (pair (lit read)
      (fn (_ . args)
        (let ((text (%buffer-token (first args))))
          (let ((k (%py-read-variant args)))
            (mk-tok-number text (if (null? k) (%py-variant-of-text text) k))))))))
(%py-tok-type! "PY-NUMBER" %py-t-number)

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
; THE ESCAPES PYTHON HAS: \n \t \r \\ \' \" \a \b \f \v \0, octal \ooo (one to
; three digits), hex \xhh -- each a CODE POINT, spelled back as text through
; the engine's int->char door so \xff is the two-byte character it is, not
; a stray byte.  An escape Python does not know (\z) is kept verbatim,
; backslash and all, which is Python's rule too.
(def %py-int->char (prim-ref (lit int) (lit ->char)))
; THE CONVERSION CANNOT RUN INSIDE A READ HANDLER -- (%cvt l %string) hands
; back nil there (the reason the old decoder was built on Str8 appends) --
; so the 256 one-character strings a byte-sized code point can name are
; built ONCE, here, at load time, and the decoder indexes them.  Larger code
; points (\u escapes, unsupported) fall back to the conversion.
(def %py-cp-strs
  (do
    (def go
      (fn (self n acc)
        (if (< n 0) acc
          (self (- n 1) (pair (%py-list->string (list (%py-int->char n))) acc)))))
    (go 255 ())))
(def %py-cp->str
  (fn (_ n)
    (if (< n 256)
      (List ref n %py-cp-strs)
      (%py-list->string (list (%py-int->char n))))))
(def %py-hexval
  (fn (_ c)
    (match
      ((if (>= c 48) (<= c 57) #f) (- c 48))
      ((if (>= c 97) (<= c 102) #f) (- c 87))
      ((if (>= c 65) (<= c 70) #f) (- c 55))
      (#t ()))))

; A BYTES LITERAL'S \xhh IS ONE BYTE, not a code point: b'\xff' has length
; 1.  The engine's byte packer (bytes ->str: one byte per character, low
; byte) is a prim with no x-lang dispatch, so it is safe here -- but the
; table is still built at load, like %py-cp-strs, and indexed by the decoder.
(def %py-bytes->str (prim-ref (lit bytes) (lit ->str)))
(def %py-byte-strs
  (do
    (def go
      (fn (self n acc)
        (if (< n 0) acc
          (self (- n 1) (pair (%py-bytes->str (list (%py-int->char n))) acc)))))
    (go 255 ())))
(def %py-byte->str (fn (_ n) (List ref n %py-byte-strs)))

; A NUL NAMED BY AN ESCAPE IS PARKED, NOT RAISED.  The reason is the one
; %py-note-ind-error! gives above: a raise crossing the C reader boundary
; reaches the guard with its payload gone, so a read handler cannot report
; anything itself.  The escape decodes to the empty string it always decoded
; to; what is new is the note, which python-tokenize turns into the ValueError
; bytes() already raises -- once reading is over and x is driving again.
;
; WHY REFUSE AT ALL: a string on this platform is a C string, by an engine
; GUARANTEE rather than an accident (str/nul-terminated), so `Str8 append`
; drops a NUL and everything after it in the same literal.  b'\x00\x01' was
; b'' and 'a\x00b' was 'ab', with nothing said.  docs/nul-and-the-string-layer.md
; is why that is the end of it and not the start of a fix.
(def %py-nul-error (pair () ()))
(def %py-nul-reset! (fn (_) (%set-first! %py-nul-error ())))
; Answers the empty string, so the decoder's shape is unchanged; `let` rather
; than %seq because %py-esc-at is reached from a read handler and every form
; it already uses is one the reader has proved safe.
(def %py-nul-esc (fn (_) (let ((noted (%set-first! %py-nul-error #t))) "")))
; One escape's text: the byte a bytes literal names, the code point a str
; literal names, and a note instead of either when the value is zero.
(def %py-esc-cp
  (fn (_ v raw?)
    (if (= v 0)
      (%py-nul-esc)
      (if raw? (%py-byte->str v) (%py-cp->str v)))))

; raw? decodes \xhh and octal escapes to raw bytes (bytes literals) rather
; than code points (str literals)
(def %py-unescape
  (fn (_ s raw?)
    (def len (Str8 length s))
    (def %go
      (fn (self i acc)
        (if (>= i len)
          acc
          (if (if (= (%py-char->int (Str8 ref i s)) 92) (< (+ i 1) len) #f)
            (let ((r (%py-esc-at s i len raw?)))
              (self (first r) (Str8 append acc (rest r))))
            (self (+ i 1) (Str8 append acc (Str8 sub i 1 s)))))))
    (%go 0 "")))

; One escape at index i (which holds the backslash): (next-index . text).
(def %py-esc-at
  (fn (_ s i len raw?)
    (def at (fn (_ k) (%py-char->int (Str8 ref k s))))
    (def code (at (+ i 1)))
    (def simple
      (fn (_ t) (pair (+ i 2) t)))
    (match
      ((= code 10) (pair (+ i 2) ""))
      ((= code 110) (simple "\n"))
      ((= code 116) (simple "\t"))
      ((= code 114) (simple "\r"))
      ((= code 92) (simple "\\"))
      ((= code 39) (simple "'"))
      ((= code 34) (simple "\""))
      ((= code 97) (simple (%py-cp->str 7)))
      ((= code 98) (simple (%py-cp->str 8)))
      ((= code 102) (simple (%py-cp->str 12)))
      ((= code 118) (simple (%py-cp->str 11)))
      ((= code 120)
        (let ((h1 (if (< (+ i 2) len) (%py-hexval (at (+ i 2))) ()))
              (h2 (if (< (+ i 3) len) (%py-hexval (at (+ i 3))) ())))
          (if (if (null? h1) #t (null? h2))
            (simple "\\x")
            (let ((v (+ (* h1 16) h2)))
              (pair (+ i 4) (%py-esc-cp v raw?))))))
      ((if (>= code 48) (<= code 55) #f)
        (let ((d1 (- code 48)))
          (let ((n2 (if (if (< (+ i 2) len) (if (>= (at (+ i 2)) 48) (<= (at (+ i 2)) 55) #f) #f) 1 0)))
            (let ((n3 (if (if (= n2 1) (if (< (+ i 3) len) (if (>= (at (+ i 3)) 48) (<= (at (+ i 3)) 55) #f) #f) #f) 1 0)))
              (let ((v (if (= n2 0) d1
                         (if (= n3 0) (+ (* d1 8) (- (at (+ i 2)) 48))
                           (+ (* (+ (* d1 8) (- (at (+ i 2)) 48)) 8) (- (at (+ i 3)) 48))))))
                (pair (+ i (+ 2 (+ n2 n3))) (%py-esc-cp v raw?)))))))
      ; unknown: keep the backslash and the character, Python's rule
      (#t (pair (+ i 2) (Str8 sub i 2 s))))))
(def %py-string-read
  (fn (_ . args)
    (def raw (%buffer-token (first args)))
    (def len (Str8 length raw))
    ; Drop the opening and closing quote; an unterminated string never reaches
    ; here, because its state never accepted.
    (mk-tok-string (%py-unescape (Str8 sub 1 (- len 2) raw) #f))))

(def %py-t-sq
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (= chr 39) %py-sq-body ())))
    (pair (lit read) %py-string-read)))
(%py-tok-type! "PY-SQ" %py-t-sq)

(def %py-t-dq
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (= chr 34) %py-dq-body ())))
    (pair (lit read) %py-string-read)))
(%py-tok-type! "PY-DQ" %py-t-dq)

; --- PY-PSQ / PY-PDQ: prefixed literals, r u b f in either case ---------------
; ONE type per quote for every one-letter prefix: the prefix letter and the
; quote are matched here, the BODY is the string types' own states reused
; as-is -- escapes, terminators and scoring stay one implementation -- and
; the READ handler reads the prefix back off the lexeme to decide what the
; literal is: b a bytes value, f an f-string, r a RAW string (no escape
; processing), u a plain string.  A bare letter followed by anything else
; rejects, and PY-NAME's one-character match wins: `b = 1` still parses.
; After the prefix letter, a quote opens a body -- and a SECOND quote is
; either the empty literal (f'' -- accept, giving the next character back)
; or, with a third, a triple-quoted body.
(def %py-psq-q2
  (fn (_ buffer score chr)
    (if (= chr 39) %py-tsq-body (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
(def %py-psq-q1
  (fn (_ buffer score chr) (if (= chr 39) %py-psq-q2 (%py-sq-body buffer score chr))))
(def %py-bsq-start
  (fn (_ buffer score chr) (if (= chr 39) %py-psq-q1 ())))
(def %py-pdq-q2
  (fn (_ buffer score chr)
    (if (= chr 34) %py-tdq-body (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
(def %py-pdq-q1
  (fn (_ buffer score chr) (if (= chr 34) %py-pdq-q2 (%py-dq-body buffer score chr))))
(def %py-bdq-start
  (fn (_ buffer score chr) (if (= chr 34) %py-pdq-q1 ())))

(def %py-prefix-char?
  (fn (_ c)
    (match
      ((= c 98) #t)
      ((= c 66) #t)
      ((= c 102) #t)
      ((= c 70) #t)
      ((= c 114) #t)
      ((= c 82) #t)
      ((= c 117) #t)
      (#t (= c 85)))))

(def %py-prefixed-read
  (fn (_ . args)
    (def raw (%buffer-token (first args)))
    (def len (Str8 length raw))
    (def p (%py-char->int (Str8 ref 0 raw)))
    ; one quote or three: a triple-quoted lexeme is at least seven long and
    ; opens with three of the same quote
    (def triple
      (if (>= len 7)
        (if (= (%py-char->int (Str8 ref 1 raw)) (%py-char->int (Str8 ref 2 raw)))
          (= (%py-char->int (Str8 ref 2 raw)) (%py-char->int (Str8 ref 3 raw)))
          #f)
        #f))
    (def body
      (if triple
        (%py-crlf->lf (Str8 sub 4 (- len 7) raw))
        (Str8 sub 2 (- len 3) raw)))
    (match
      ((if (= p 98) #t (= p 66)) (mk-tok-bytes (%py-unescape body #t)))
      ((if (= p 102) #t (= p 70)) (mk-tok-fstring (%py-unescape body #f)))
      ((if (= p 114) #t (= p 82)) (mk-tok-string body))
      (#t (mk-tok-string (%py-unescape body #f))))))

(def %py-t-psq
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (%py-prefix-char? chr) %py-bsq-start ())))
    (pair (lit read) %py-prefixed-read)))
(def %py-t-pdq
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (%py-prefix-char? chr) %py-bdq-start ())))
    (pair (lit read) %py-prefixed-read)))
(%py-tok-type! "PY-PSQ" %py-t-psq)
(%py-tok-type! "PY-PDQ" %py-t-pdq)

; --- PY-TSQ / PY-TDQ: triple-quoted strings ----------------------------------
; Three quotes open, three close, anything at all in between -- newlines
; included.  The single-quote type matches the same first character; when
; the second character is not a quote this type rejects and the single-quote
; type's match stands, and `''` (an empty single-quoted string) is the same
; story one character on.  A run of three or more closing quotes is Python's:
; the literal ends at the first three.
(def %py-tsq-body ())
(def %py-tsq-c1 ())
(def %py-tsq-c2 ())
(set! %py-tsq-body (fn (_ buffer score chr) (if (= chr 39) %py-tsq-c1 %py-tsq-body)))
(set! %py-tsq-c1 (fn (_ buffer score chr) (if (= chr 39) %py-tsq-c2 %py-tsq-body)))
(set! %py-tsq-c2
  (fn (_ buffer score chr) (if (= chr 39) (%score-set score 1 buffer) %py-tsq-body)))
(def %py-tsq-o3 (fn (_ buffer score chr) (if (= chr 39) %py-tsq-body ())))
(def %py-tsq-o2 (fn (_ buffer score chr) (if (= chr 39) %py-tsq-o3 ())))

(def %py-tdq-body ())
(def %py-tdq-c1 ())
(def %py-tdq-c2 ())
(set! %py-tdq-body (fn (_ buffer score chr) (if (= chr 34) %py-tdq-c1 %py-tdq-body)))
(set! %py-tdq-c1 (fn (_ buffer score chr) (if (= chr 34) %py-tdq-c2 %py-tdq-body)))
(set! %py-tdq-c2
  (fn (_ buffer score chr) (if (= chr 34) (%score-set score 1 buffer) %py-tdq-body)))
(def %py-tdq-o3 (fn (_ buffer score chr) (if (= chr 34) %py-tdq-body ())))
(def %py-tdq-o2 (fn (_ buffer score chr) (if (= chr 34) %py-tdq-o3 ())))

; A CR or CRLF inside the literal is a newline, Python's line-ending rule.
(def %py-crlf->lf
  (fn (_ s)
    (def n (Str8 length s))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-char->int (Str8 ref i s))))
            (if (= c 13)
              (self (if (if (< (+ i 1) n) (= (%py-char->int (Str8 ref (+ i 1) s)) 10) #f) (+ i 2) (+ i 1))
                (Str8 append acc "\n"))
              (self (+ i 1) (Str8 append acc (Str8 sub i 1 s))))))))
    (if (null? (Str8 index-of (%py-cp->str 13) s)) s (go 0 ""))))

(def %py-triple-read
  (fn (_ . args)
    (def raw (%buffer-token (first args)))
    (def len (Str8 length raw))
    (mk-tok-string (%py-unescape (%py-crlf->lf (Str8 sub 3 (- len 6) raw)) #f))))

(def %py-t-tsq
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (= chr 39) %py-tsq-o2 ())))
    (pair (lit read) %py-triple-read)))
(def %py-t-tdq
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr) (if (= chr 34) %py-tdq-o2 ())))
    (pair (lit read) %py-triple-read)))
(%py-tok-type! "PY-TSQ" %py-t-tsq)
(%py-tok-type! "PY-TDQ" %py-t-tdq)

; --- PY-OP: operators and delimiters -----------------------------------------
; LONGEST MATCH MATTERS AND IS EASY TO GET WRONG.  `//` is floor division and
; `/` is true division; `**` is power; `==` `!=` `<=` `>=` are comparisons and
; `=` is assignment.  A single-character-only operator type reads `a//b` as two
; divisions, which is not a syntax error -- it is silently different arithmetic.
;
; AND THE MATCH RUNS THREE CHARACTERS DEEP: `//=` `**=` `>>=` `<<=` are the
; augmented forms of the doubled operators, so a pair is not always the end.
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
    ; + - * / % = < > ! ~ | ^ & , : . ; and @, which is a decorator here
    ; (Python's other @ is matrix multiply, which this runtime has no use
    ; for).  GENERATED from the code list -- and a match, not a chain of ifs
    ; nested through their else branches: one arm per code, flat, which is
    ; what the primitive is for.  A hand-nested predicate of this shape is
    ; paren-balanced and silently wrong, which is how x-python#40 reached CI
    ; red.
    (match
      ((= c 43) #t)
      ((= c 45) #t)
      ((= c 42) #t)
      ((= c 47) #t)
      ((= c 37) #t)
      ((= c 61) #t)
      ((= c 60) #t)
      ((= c 62) #t)
      ((= c 33) #t)
      ((= c 126) #t)
      ((= c 124) #t)
      ((= c 94) #t)
      ((= c 38) #t)
      ((= c 44) #t)
      ((= c 58) #t)
      ((= c 46) #t)
      ((= c 59) #t)
      ((= c 64) #t)
      (#t #f))))

; Which pairs extend: a second `=`, or one of the four doubled operators.
(def %py-op-pair?
  (fn (_ a b)
    (match
      ((= b 61)
        (match
          ((= a 61) #t)
          ((= a 33) #t)
          ((= a 60) #t)
          ((= a 62) #t)
          ((= a 43) #t)
          ((= a 45) #t)
          ((= a 42) #t)
          ((= a 47) #t)
          ((= a 37) #t)
          ((= a 124) #t)
          ((= a 38) #t)
          (#t (= a 94))))
      ; // ** << >>
      ((if (= a 47) (= b 47) #f) #t)
      ((if (= a 42) (= b 42) #f) #t)
      ((if (= a 60) (= b 60) #f) #t)
      ((= a 62) (= b 62))
      (#t #f))))

(def %py-op-pairable?
  (fn (_ c)
    ; = ! < > / * + - %, and | & ^ for |= &= ^=; generated, as above
    (match
      ((= c 61) #t)
      ((= c 33) #t)
      ((= c 60) #t)
      ((= c 62) #t)
      ((= c 47) #t)
      ((= c 42) #t)
      ((= c 43) #t)
      ((= c 45) #t)
      ((= c 37) #t)
      ((= c 124) #t)
      ((= c 38) #t)
      ((= c 94) #t)
      (#t #f))))

; Which pairs take a THIRD character.  Only the doubled four do, and the only
; third character is `=`: `//=` `**=` `>>=` `<<=`.  Nothing else triples --
; `==` is the whole operator, not the start of `===`.  Generated from the code
; list like the two predicates above, for the reason recorded there.
(def %py-op-triple?
  (fn (_ a b)
    (if (= a b)
      (match
        ((= a 47) #t)
        ((= a 42) #t)
        ((= a 62) #t)
        (#t (= a 60)))
      #f)))

; The third character is `=` and nothing else, so this state closes over
; nothing and is an ordinary global -- the shape %py-sq-esc uses, and the one
; form of state the note above is not warning about.
(def %py-op-third
  (fn (_ buffer score chr)
    (if (= chr 61)
      (%score-set score 1 buffer)
      (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))

(def %py-op-second
  (fn (_ c1)
    (fn (_ buffer score chr)
      (if (%py-op-pair? c1 chr)
        ; a pair that can triple keeps reading; every other pair is done
        (if (%py-op-triple? c1 chr)
          (%seq (%score-set score 1 buffer) %py-op-third)
          (%score-set score 1 buffer))
        (%seq (%buffer-unread buffer) (%score-set score 1 buffer))))))

(def %py-t-op
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
(%py-tok-type! "PY-OP" %py-t-op)

; --- Compiled analysers ------------------------------------------------------
;
; THE ANALYSERS RUN PER CHARACTER and they are the whole cost of lexing: at
; every token start each registered type's entry runs, and every character of
; every token runs the winning type's body state -- each call crossing the C/x
; boundary into an interpreted closure.  x/tool/compile's assembler lane
; (compile-asm) compiles an analyser to native code -- no toolchain -- so the
; hot path stops re-entering the interpreter.
;
; ADOPTION IS LAZY AND GUARDED, lib/x/hash/sha256.x's pattern.  Compiling the
; states costs seconds, so nothing happens until %py-jit-threshold bytes of
; source have passed through python-tokenize in this process; then ONE attempt,
; under a guard.  Any refusal -- a platform whose compile-asm predates fvar
; forwarding or the self-param rule, a host without native/jit -- pins `failed`
; and the interpreted base carries on.  THE INTERPRETER IS THE CONTRACT; the
; JIT is a cache of it.
;
; THE SWAP IS A SECOND BASE, because registration is write-once: re-registering
; a type name does not replace it (measured -- the first registration keeps
; winning).  So the attempt builds a fresh base with compiled entries and
; bodies, registered in the same order as the interpreted one, sharing the
; read handlers -- read runs once per token and stays interpreted -- and
; python-tokenize reads whichever base %py-active-raw holds.  The interpreted
; base is never touched, so a raise mid-way leaves it whole.
;
; A COMPILED STATE CAN HAND OFF TO AN INTERPRETED ONE: an fvar carries any
; object, including an interpreted closure (measured).  That is how the
; compiled string entries reach the interpreted escape states, and how the
; compiled PY-NL entry reaches the interpreted indentation machinery -- the
; rare paths stay interpreted, the per-character paths do not.  Only PY-OP's
; entry stays interpreted entirely: it builds a per-token lookahead closure,
; which is not the JIT's vocabulary.
;
; COMPILED SOURCES ARE INTEGER-ONLY.  Raw codepoints (32, not #\space); LITERAL
; signs (-1, never the house-style (- 0 1)) -- a compiled %score-set sign must
; be a literal integer.  A looping state returns its own self param (me ...),
; resolved as arg slot 0; a platform too old for that also refuses the
; fvar-forwarding gate below, which is the property the gate actually tests.
; The unused fvar `u` forces analyser mode on states with no real free
; variable.
(import x/tool/compile)

(def %py-jit (pair (lit off) ()))        ; off | active | failed
(def %py-jit-bytes (pair 0 ()))
(def %py-jit-threshold (pair 51200 ()))  ; bytes of source before one attempt
(def %py-active-raw (pair () ()))         ; what python-tokenize reads; %py-tok-reset! fills it
(def %py-cbase (pair () ()))             ; roots the compiled base's wrapper
; EVERY COMPILED STATE IS ROOTED HERE, and the reason is a segfault.  A
; compiled state reaches the states it hands off to through addresses BAKED
; into its machine code (asm-compile.x: "an fvar is baked as its object's
; ADDRESS"), and the collector cannot see an address inside code.  So a body
; state -- nb, wsc, nexpd, every node of the keyword trie -- was reachable
; only while %py-jit-compile!'s frame held it, and unreachable the moment
; the frame returned; the entry states survive through the second base's
; type structs, their targets did not.  The compile itself collects (the
; assembler sweeps every %asm-gc-window nodes), so states compiled AFTER the
; trie could free its children mid-attempt; small inputs then tokenized by
; luck and a larger one reused the freed memory and died.  Measured: an
; explicit (Heap collect) after the attempt killed `q qq` -- names, the
; e-name -> nb handoff.  Native code is this process's alone, so the list
; is a transient and %py-tok-reset! empties it with the base.
(def %py-jit-states (pair () ()))
; THE COMPILED STATES DECLARE VARIANTS ONLY WHERE THE LANE CAN SPELL IT.  A
; platform whose emitter has no %score-variant! refuses the form, and the attempt
; runs under a guard that would pin `failed` for all of it -- so the attempt
; probes once and builds the number states with or without the declaration.
; The interpreted twins go through %py-variant!, a no-op on such a platform.
(def %py-jit-variants (pair #f ()))
(def %py-jit-accept
  (fn (_ k)
    (if (first %py-jit-variants)
      (list (lit %seq) (list (lit %score-variant!) (lit score) k) (lit (%score-set score 1 buffer)))
      (lit (%score-set score 1 buffer)))))
(def %py-jit-unread-accept
  (fn (_ k) (list (lit %seq) (lit (%buffer-unread buffer)) (%py-jit-accept k))))
(def %py-jit-keep!
  (fn (_ p) (%seq (%set-first! %py-jit-states (pair p (first %py-jit-states))) p)))

(def %py-hdl-of
  (fn (self hs k)
    (if (null? hs) ()
      (if (eq? (first (first hs)) k)
        (rest (first hs))
        (self (rest hs) k)))))

(def %py-jit-compile!
  (fn (_)
    ; THE GATE.  On a platform that cannot forward fvars this compile itself
    ; raises, and the guard in %py-jit-tick! pins `failed` before anything is
    ; built.  The result is never called -- a direct call to an fvar-compiled
    ; function is outside the contract.
    (compile-asm (lit (fn (_ x) (+ x k))) (list (pair (lit k) 1)))
    ; each state rooted as it is made -- see %py-jit-states
    (def jc (fn (_ form fvars) (%py-jit-keep! (compile-asm form fvars))))
    ; can this lane spell a variant?  (probed, never called -- see %py-jit-variants)
    (%set-first! %py-jit-variants
      (guard (e #f)
        (%seq (jc (lit (fn (_ buffer score chr) (%score-variant! score 1))) (list (pair (lit u) 1))) #t)))
    ; -- body states --
    (def wsc
      (jc
        (lit (fn (me buffer score chr)
          (if (or (= chr 32) (= chr 9))
            me
            (%seq (%buffer-unread buffer) (%score-set score -1 buffer)))))
        (list (pair (lit u) 1))))
    (def cb
      (jc
        (lit (fn (me buffer score chr)
          (if (= chr 10)
            (%seq (%buffer-unread buffer) (%score-set score -1 buffer))
            me)))
        (list (pair (lit u) 1))))
    (def bws
      (jc
        (lit (fn (me buffer score chr)
          (if (or (= chr 32) (= chr 9))
            me
            (if (or (= chr 10) (= chr 35))
              (%seq (%buffer-unread buffer) (%score-set score -1 buffer))
              ()))))
        (list (pair (lit u) 1))))
    (def nb
      (jc
        (lit (fn (me buffer score chr)
          (if (or (and (>= chr 97) (<= chr 122))
                  (and (>= chr 65) (<= chr 90))
                  (= chr 95)
                  (and (>= chr 48) (<= chr 57)))
            me
            (%seq (%buffer-unread buffer) (%score-set score 1 buffer)))))
        (list (pair (lit u) 1))))
    (def nexpd
      (jc
        (list (lit fn) (lit (me buffer score chr))
          (list (lit if) (lit (or (and (>= chr 48) (<= chr 57)) (= chr 95)))
            (lit me)
            (list (lit if) (lit (or (= chr 106) (= chr 74)))
              (%py-jit-accept 3)
              (%py-jit-unread-accept 2))))
        (list (pair (lit u) 1))))
    (def nexpf
      (jc
        (lit (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57)) k ())))
        (list (pair (lit k) nexpd))))
    (def nexps
      (jc
        (lit (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57))
            k
            (if (or (= chr 43) (= chr 45)) f ()))))
        (list (pair (lit k) nexpd) (pair (lit f) nexpf))))
    ; NESTED IFS, NOT MATCH, in every compiled state from here down: the
    ; assembler lane has no match and REFUSES the form ("unsupported form:
    ; match"), and this function runs under a guard that pins `failed` on any
    ; raise -- so the three states that were written with match had pinned
    ; the whole JIT off, silently, since they were written.  The
    ; "compiled equals interpreted" spec held because nothing was compiled.
    (def nfrac
      (jc
        (list (lit fn) (lit (me buffer score chr))
          (list (lit if) (lit (or (and (>= chr 48) (<= chr 57)) (= chr 95)))
            (lit me)
            (list (lit if) (lit (or (= chr 101) (= chr 69)))
              (lit es)
              (list (lit if) (lit (or (= chr 106) (= chr 74)))
                (%py-jit-accept 3)
                (%py-jit-unread-accept 2)))))
        (list (pair (lit es) nexps))))
    (def nbody
      (jc
        (list (lit fn) (lit (me buffer score chr))
          (list (lit if) (lit (or (and (>= chr 48) (<= chr 57)) (= chr 95)))
            (lit me)
            ; a fraction or exponent marker continues the literal: which
            (list (lit if) (lit (or (= chr 46) (or (= chr 101) (= chr 69))))
              (lit (if (= chr 46) frac es))
              (list (lit if) (lit (or (= chr 106) (= chr 74)))
                (%py-jit-accept 3)
                (%py-jit-unread-accept 1)))))
        (list (pair (lit frac) nfrac) (pair (lit es) nexps))))
    (def ndotf
      (jc
        (lit (fn (_ buffer score chr)
          (if (and (>= chr 48) (<= chr 57)) frac ())))
        (list (pair (lit frac) nfrac))))
    (def nsigned
      (jc
        (lit (fn (_ buffer score chr)
          (if (= chr 48)
            zero
            (if (and (>= chr 48) (<= chr 57)) body ()))))
        (list (pair (lit zero) %py-number-zero) (pair (lit body) nbody))))
    ; The escape states are interpreted and rare; each hands control back to
    ; the compiled body by evaluating its own global, which after adoption is
    ; only ever reached from here -- so the handoff is fvar out, global back.
    (def sqb
      (jc
        (lit (fn (me buffer score chr)
          (if (= chr 39)
            (%score-set score 1 buffer)
            (if (= chr 92) esc me))))
        (list (pair (lit esc) %py-sq-esc))))
    (def dqb
      (jc
        (lit (fn (me buffer score chr)
          (if (= chr 34)
            (%score-set score 1 buffer)
            (if (= chr 92) esc me))))
        (list (pair (lit esc) %py-dq-esc))))
    ; -- entry states: one per type, run at every token start --
    (def e-ws
      (jc
        (lit (fn (_ buffer score chr)
          (if (or (= chr 32) (= chr 9))
            (%seq (%score-set score -1 buffer) k)
            ())))
        (list (pair (lit k) wsc))))
    (def e-comment
      (jc
        (lit (fn (_ buffer score chr)
          (if (= chr 35)
            (%seq (%score-set score -1 buffer) k)
            ())))
        (list (pair (lit k) cb))))
    (def e-blank
      (jc
        (lit (fn (_ buffer score chr)
          (if (= chr 10) k ())))
        (list (pair (lit k) bws))))
    (def e-nl
      (jc
        (lit (fn (_ buffer score chr)
          (if (= chr 10) k ())))
        (list (pair (lit k) %py-nl-ws))))
    (def e-name
      (jc
        (lit (fn (_ buffer score chr)
          (if (or (and (>= chr 97) (<= chr 122))
                  (and (>= chr 65) (<= chr 90))
                  (= chr 95))
            k
            ())))
        (list (pair (lit k) nb))))
    (def e-number
      (jc
        (lit (fn (_ buffer score chr)
          ; a digit: the leading zero has its own state, the rest the body
          (if (and (>= chr 48) (<= chr 57))
            (if (= chr 48) zero body)
            (if (= chr 46)
              dotf
              (if (or (= chr 43) (= chr 45)) signed ())))))
        ; the leading-zero state stays interpreted: it is rare (0x, 0o, 0b
        ; and plain zeros) and hands the digit run back to the compiled body
        (list (pair (lit zero) %py-number-zero) (pair (lit body) nbody)
          (pair (lit dotf) ndotf) (pair (lit signed) nsigned))))
    (def e-sq
      (jc
        (lit (fn (_ buffer score chr)
          (if (= chr 39) k ())))
        (list (pair (lit k) sqb))))
    (def e-dq
      (jc
        (lit (fn (_ buffer score chr)
          (if (= chr 34) k ())))
        (list (pair (lit k) dqb))))
    (def e-close
      (jc
        (lit (fn (_ buffer score chr)
          (if (or (= chr 41) (= chr 93) (= chr 125))
            (%score-set score 1 buffer)
            ())))
        (list (pair (lit u) 1))))
    (def e-open
      (jc
        (lit (fn (_ buffer score chr)
          (if (or (= chr 40) (= chr 91) (= chr 123))
            (%score-set score 1 buffer)
            ())))
        (list (pair (lit u) 1))))
    ; -- the second base, same registration order as the interpreted one --
    (def b (Base make-tok))
    (def reg
      (fn (_ nm e hs)
        (let ((r (%py-hdl-of hs (lit read))))
          (Base make-type b nm
            (if (null? r)
              (list (pair (lit analyse) e))
              (list (pair (lit analyse) e) (pair (lit read) r)))))))
    (reg "PY-WS" e-ws %py-t-ws)
    (reg "PY-COMMENT" e-comment %py-t-comment)
    (reg "PY-BLANK" e-blank %py-t-blank)
    (reg "PY-NL" e-nl %py-t-nl)
    ; the keyword trie: the shared leaf first, then one native state per node
    (%set-first! %py-kw-leaf
      (jc
        (list (lit fn) (lit (_ buffer score chr)) (%py-kw-tail-form #t))
        (list (pair (lit u) 1))))
    (def e-kw (%py-kw-compile %py-kw-trie))
    (reg "PY-KEYWORD" e-kw %py-t-kw)
    (reg "PY-NAME" e-name %py-t-name)
    (reg "PY-NUMBER" e-number %py-t-number)
    (reg "PY-SQ" e-sq %py-t-sq)
    (reg "PY-DQ" e-dq %py-t-dq)
    ; bytes literals stay interpreted at entry: the b-prefix test runs once
    ; per token start and the body states are the compiled string bodies'
    ; interpreted twins, reached through the same globals either way
    (Base make-type b "PY-PSQ" %py-t-psq)
    (Base make-type b "PY-PDQ" %py-t-pdq)
    (Base make-type b "PY-TSQ" %py-t-tsq)
    (Base make-type b "PY-TDQ" %py-t-tdq)
    (Base make-type b "PY-OP" %py-t-op)
    (reg "PY-CLOSE" e-close %py-t-close)
    (reg "PY-OPEN" e-open %py-t-open)
    (%set-first! %py-cbase b)
    (%set-first! %py-active-raw (Base raw-of b))))

(def %py-jit-tick!
  (fn (_ n)
    (if (eq? (first %py-jit) (lit off))
      (do
        (%set-first! %py-jit-bytes (+ (first %py-jit-bytes) n))
        (if (>= (first %py-jit-bytes) (first %py-jit-threshold))
          (%set-first! %py-jit
            (guard (_ (lit failed))
              (%seq (%py-jit-compile!) (lit active))))
          ()))
      ())))

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
    (%py-jit-tick! (Str8 length input))
    (%py-ind-reset!)
    (%py-nul-reset!)
    (let ((toks (%py-token-read-string (first %py-active-raw)
                  (Str8 append input " "))))
      ; Reading is over and x is driving again, so this is where an indentation
      ; error can finally be raised -- and, for the same reason and out of the
      ; same kind of parked note, a NUL named by an escape.  Indentation goes
      ; first: it is a fact about the program's shape, and a file with both
      ; problems has the structural one to fix before the literal.
      (if (not (null? (first %py-ind-error)))
        (Err raise (lit indent)
          "unindent does not match any outer indentation level" ())
        (if (null? (first %py-nul-error))
          toks
          (Err raise (lit value) "a NUL byte is not representable here" ()))))))

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

(def %py-t-close
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-close? chr) (%score-set score 1 buffer) ())))
    (pair (lit read)
      (fn (_ . args) (list (lit tok-close) (%buffer-token (first args)))))))
(%py-tok-type! "PY-CLOSE" %py-t-close)

(def %py-group-close? (fn (_ t) (if (pair? t) (eq? (first t) (lit tok-close)) #f)))
; The bracket a close token is: ")" / "]" / "}".  Kept so a group can record
; the closer it met and the parser can check that it was the right one.
(def %py-close-text (fn (_ t) (first (rest t))))
(def %py-group-nl? (fn (_ t) (if (pair? t) (eq? (first t) (lit tok-newline)) #f)))

(def %py-t-open
  (list
    (pair (lit analyse)
      (fn (_ buffer score chr)
        (if (%py-open? chr) (%score-set score 1 buffer) ())))
    (pair (lit read)
      (fn (_ . args)
        (def buffer (first args))
        (def open (%buffer-token buffer))
        (%set-first! %py-in-group (+ (first %py-in-group) 1))
        ; Answers (elems . closer): the tokens, and the bracket that ended
        ; them -- nil when the run ended at EOF instead.
        (def go
          (fn (self acc)
            (let ((v (%py-token-read buffer)))
              ; EOF inside a bracket: give back what there is, with a nil
              ; closer, and let the parser say so.  A lexer that raised here
              ; would report the wrong place -- and it is the parser, not the
              ; reader, that knows a closer has to MATCH.
              (match
                ((null? v) (pair (%py-reverse acc) ()))
                ((%py-group-close? v) (pair (%py-reverse acc) (%py-close-text v)))
                ; A newline inside brackets is not line structure, it is
                ; whitespace -- which used to need a depth counter to know.
                ((%py-group-nl? v) (self acc))
                (#t (self (pair v acc)))))))
        (let ((r (go ())))
          (%set-first! %py-in-group (- (first %py-in-group) 1))
          (mk-tok-group open (first r) (rest r)))))))
(%py-tok-type! "PY-OPEN" %py-t-open)

; --- the base itself: made here, and remade after an image load -------------
; One door.  The image writer runs the transient thunk in the child (the
; base, the raw it reads through, and any compiled second base go to nil --
; a compiled base is native code in this process's pages); the recache hook
; runs this same reset once the loader is done.
(def %py-tok-reset!
  (fn (_)
    (set! %py-base (%py-tok-base-make))
    (%set-first! %py-active-raw (Base raw-of %py-base))
    (%set-first! %py-cbase ())
    (%set-first! %py-jit-states ())
    (%set-first! %py-kw-leaf ())
    (%set-first! %py-jit (lit off))
    (%set-first! %py-jit-bytes 0)))
(%py-tok-reset!)
(set! %image-transients
  (pair (fn (_)
          (set! %py-base ())
          (%set-first! %py-active-raw ())
          (%set-first! %py-cbase ())
          (%set-first! %py-jit-states ())
          (%set-first! %py-kw-leaf ()))
        %image-transients))
(set! %image-recache-hooks (pair (fn (_) (%py-tok-reset!)) %image-recache-hooks))
