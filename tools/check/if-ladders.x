; if-ladders.x -- report every nested `if` ladder that should be a `match`
;
;   sh x.sh --no-pin -q -f tools/check/if-ladders.x -- FILE...
;
; Prints one "FILE NAME LENGTH" line per MAXIMAL ladder at or above the
; threshold, for tools/check/if-ladders.sh to check against the manifest in
; tools/contract/if-ladders.txt.
;
; WHY THIS IS A CHECK AT ALL.  `match` is an engine PRIMITIVE and the flat way
; to write a decision with more than a couple of arms; a chain of `if`s nested
; through their else branches says the same thing one indent deeper per arm,
; and reads worse the longer it gets.  Every arm after the third is a reason to
; use the primitive that exists for this.
;
; STRUCTURAL, not a grep: an `if` ladder is a shape, and the shape is only
; knowable by reading the file as s-expressions.  The file is parsed, never
; evaluated.  Symbol comparison is by NAME -- symbols intern per base, so a
; symbol read here is not eq? to one written here.

(do
  (import x/sys/posix)
  (import x/sys/file)
  (import x/codec/xon)
  (import x/tool/contract)

  ; THE GUARD STAYS ON, and the walker is written to fit under it.  Removing
  ; it to stop a truncated report only moved the failure: with no ceiling this
  ; walk took a 7GB CI runner down, and the job came back "canceled" with no
  ; error of its own.  What made it hungry was allocating a CLOSURE PER NODE
  ; (a lambda handed to a list walker) in a runtime with no automatic GC --
  ; so the walk below allocates none, and each top-level form is swept before
  ; the next.
  (Contract alloc-guard!)

  ; A ladder of this many arms or more is reported.  Three arms is an
  ; ordinary two-way decision with a fallback; four is a table.
  (def %il-threshold 4)

  (def %il-argv (Contract argv))
  (when (null? %il-argv)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/check/if-ladders.x -- FILE...\n")
        (Sys exit 1)))

  (def %il-name (fn (_ x) (if (symbol? x) (symbol->str x) "")))
  (def %il-is? (fn (_ x s) (str=? (%il-name x) s)))

  ; (if TEST THEN ELSE) -- the three-armed form is the one that chains
  (def %il-if?
    (fn (_ f)
      (if (pair? f)
        (if (%il-is? (first f) "if") (= (List length f) 4) #f)
        #f)))

  ; how many arms this ladder has, following the else branch down
  (def %il-arms
    (fn (self f n)
      (if (%il-if? f) (self (List ref 3 f) (+ n 1)) n)))

  (def %il-walk ())
  ; the branches of every link, and whatever the last else is -- walked
  ; WITHOUT reporting the links themselves, which are this ladder
  (def %il-inside
    (fn (self f file top)
      (if (%il-if? f)
        (do (%il-walk (List ref 1 f) file top)
            (%il-walk (List ref 2 f) file top)
            (self (List ref 3 f) file top))
        (%il-walk f file top))))

  ; NO LAMBDA PER NODE: the two walkers call each other by name, so a tree of
  ; a hundred thousand pairs allocates nothing but the walk itself.  The list
  ; walk also survives an IMPROPER tail -- a parameter list is (a b . rest),
  ; and List for-each would die on the dot.
  (def %il-walk-list ())

  (set! %il-walk
    (fn (self form file top)
      (when (pair? form)
        (if (%il-if? form)
          (do
            (let ((n (%il-arms form 0)))
              (when (>= n %il-threshold)
                (do (display file) (display " ") (display top) (display " ")
                    (display n) (newline))))
            (%il-inside form file top))
          (%il-walk-list form file top)))))

  (set! %il-walk-list
    (fn (self form file top)
      (when (pair? form)
        (do (%il-walk (first form) file top)
            (self (rest form) file top)))))

  ; THREE BINDERS, BECAUSE THIS CHECKER IS ONE FILE IN THREE PLACES.  Every
  ; module here says `def` or `set!`, and on this corpus the third binder is
  ; dead code.  It is carried anyway: x-r5rs and x-r7rs run the same checker,
  ; and seven of x-r7rs's ten modules are `include-once`d after the Scheme
  ; vocabulary exists and say `define`, in the plain and the curried spelling
  ; both.  Three copies that drift are how the spec-gate trap bug came to need
  ; the same fix in three repositories on the same day.
  ;
  ; A match, not a chain -- this file should be able to pass itself.
  (def %il-binder?
    (fn (_ x)
      (let ((s (%il-name x)))
        (match ((str=? s "def")    #t)
               ((str=? s "set!")   #t)
               ((str=? s "define") #t)
               (#t                 #f)))))

  ; (def NAME ...) and (define NAME ...) name a symbol; Scheme's curried
  ; (define (NAME . args) body) names the head of a list.
  (def %il-bound-name
    (fn (_ x)
      (match ((pair? x) (%il-name (first x)))
             (#t        (%il-name x)))))

  ; A ladder that sits in no binder is named for the CALL IT SITS IN, and only
  ; falls back to a bare placeholder when there is no head to name it after.
  ;
  ; A placeholder alone was the first fix and it was too coarse.  It stopped
  ; the blank field that slid the depth into the name, but every call site in
  ; a file collapsed onto one key: x-python has 29 such chains, 25 of them in
  ; python/types.x, which would have been ONE manifest row saying nothing
  ; about which registration held the ladder.  The ratchet still caught
  ; growth; a reader still had to go and find it.
  ;
  ; PARENTHESISED, so a call site can never collide with a definition.
  ; `(%type-push-op)` is a ladder inside a call to %type-push-op; %type-push-op
  ; is the function of that name.  A file may legitimately hold both.  No space
  ; goes in either, so the row stays three fields.
  (def %il-head-name
    (fn (_ form)
      (let ((h (%il-name (first form))))
        (match ((str=? h "") "(top-level)")
               (#t           (Str8 append "(" (Str8 append h ")")))))))

  ; (def NAME ...) / (set! NAME ...) / (define NAME ...) and the curried
  ; (define (NAME . args) body) -- a form that BINDS, and has something to bind.
  (def %il-binding-form?
    (fn (_ form)
      (match ((not (pair? form))        #f)
             ((not (pair? (rest form))) #f)
             (#t (%il-binder? (first form))))))

  ; The name a ladder is reported under: what the top-level form binds, else
  ; what it calls, else the placeholder.
  (def %il-top-name
    (fn (_ form)
      (match ((%il-binding-form? form) (%il-bound-name (first (rest form))))
             ((pair? form)             (%il-head-name form))
             (#t                       "(top-level)"))))

  ; A SWEEP BETWEEN TOP-LEVEL FORMS.  Nothing here collects on its own, and a
  ; module of ten thousand lines is one long walk; without this the guard
  ; fires part way through the largest file and the report is a lie.
  (def %il-file
    (fn (self forms file)
      (when (pair? forms)
        (do (%il-walk (first forms) file (%il-top-name (first forms)))
            (Heap collect)
            (self (rest forms) file)))))

  (List for-each
    (fn (_ file) (%il-file (Xon parse (File read-all file)) file))
    %il-argv))
