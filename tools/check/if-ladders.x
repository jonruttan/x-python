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

  ; NO alloc-guard! HERE.  The guard is sized for a tool that walks a library
  ; surface; this one walks every form of every function body, and on this
  ; bundle's largest file it tripped mid-report -- which is worse than slow,
  ; because a truncated report makes the manifest below it a lie.  The .sh
  ; feeds one file per process, which is the bound that matters.

  ; A ladder of this many arms or more is reported.  Three arms is an
  ; ordinary two-way decision with a fallback; four is a table.
  (def %il-threshold 4)

  (def %il-argv (Contract argv))
  (when (null? %il-argv)
    (do (%stderr "Usage: x.sh --no-pin -q -f tools/check/if-ladders.x -- FILE...\n")
        (Sys exit 1)))

  (def %il-name (fn (_ x) (if (symbol? x) (symbol->str x) "")))
  (def %il-is? (fn (_ x s) (str=? (%il-name x) s)))

  ; A LIST WALK THAT SURVIVES AN IMPROPER TAIL: a parameter list is
  ; (a b . rest), so walking with List for-each would die on the dot.
  (def %il-each
    (fn (self f g)
      (when (pair? f)
        (do (g (first f)) (self (rest f) g)))))

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
          (%il-each form (fn (_ sub) (self sub file top)))))))

  ; the name a ladder is reported under: the top-level def or set! it sits in
  (def %il-top-name
    (fn (_ form)
      (if (pair? form)
        (if (if (%il-is? (first form) "def") #t (%il-is? (first form) "set!"))
          (%il-name (first (rest form)))
          "")
        "")))

  (List for-each
    (fn (_ file)
      (List for-each
        (fn (_ form) (%il-walk form file (%il-top-name form)))
        (Xon parse (File read-all file))))
    %il-argv))
