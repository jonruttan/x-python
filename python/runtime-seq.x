; # x-python -- Python on x-lang
;
; ## python/runtime-seq.x -- comparison, lists, dicts and iteration
;
; @description Ordering and equality, the list and dict surfaces, slice assignment
;   and del, the unwinding an escape does on the way out, and the
;   iteration protocol the for loop pulls on.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A FRAGMENT OF python/runtime.x, NOT A MODULE.  It carries no provide
; and is include-once'd by runtime.x in load order; the %py-* names are
; shared across the whole rather than exported.  runtime.x was one
; 6,062-line file, which the platform's linter could not analyse -- it
; ran 91 seconds and the engine died with no diagnostic at all.

; --- Comparison --------------------------------------------------------------
; Class equality is IDENTITY: the builtin type objects are singletons, so
; `type(1) == type(2)` is eq? on the same object, and two distinct classes are
; never equal whatever their names.  And a string never equals a non-string --
; `1 == 'a'` is False in Python, where handing the pair to x's `=` was an error.
; Bools are ints in every comparison: 0.0 == False and True == 1.0 are both
; True in Python, so bool operands normalize before the numeric compare --
; INLINE, with no helper call and no frame: these run once per dict entry
; on every subscript's linear walk, and a per-call allocation here is a
; batch-memory multiplier the CI host measured the hard way.
; COMPARISON DUNDERS ANSWER RAW VALUES, as Python's do -- an __eq__ that
; returns 123 prints 123.  __eq__ reflects onto __eq__ and falls back to
; identity; the default __ne__ is __eq__ inverted unless that answered
; NotImplemented; < > <= >= reflect onto their mirrors and then refuse.
(def %py-cmp2
  (fn (_ a b name rname)
    (let ((r1 (%py-side a b name)))
      (if (not (eq? r1 %py-NotImplemented))
        r1
        (%py-side b a rname)))))

(def %py-ne-side
  (fn (_ x y)
    (if (%py-obj-is x)
      (let ((m (%py-dunder x "__ne__")))
        (if (not (null? m))
          (m y)
          (let ((e (%py-dunder x "__eq__")))
            (if (null? e)
              %py-NotImplemented
              (let ((r (e y)))
                (if (eq? r %py-NotImplemented) r (not (%py-truthy r))))))))
      %py-NotImplemented)))

(def %py-eq
  (fn (_ a b)
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__eq__" "__eq__")))
          (if (eq? r %py-NotImplemented) (eq? a b) r)))
      ((if (%py-arr-is a) #t (%py-arr-is b))
        (if (if (%py-arr-is a) (%py-arr-is b) #f)
          (%py-eq (%py-list-new (%py-arr-el a)) (%py-list-new (%py-arr-el b)))
          #f))
      ((%py-str-is a) (if (%py-str-is b) (%pb-eq? (%py-str-cps a) (%py-str-cps b)) #f))
      ((%py-str-is b) #f)
      ((%py-bytes-is a)
        (if (%py-bytes-is b) (%pb-eq? (%py-bytes-list a) (%py-bytes-list b)) #f))
      ((%py-bytes-is b) #f)
      ((if (%py-fn-is a) #t (%py-fn-is b)) (same? a b))
      ; two bound methods are equal when they bind the same function to equal
      ; receivers, which is Python's rule
      ((%py-bound-is a)
        (if (%py-bound-is b)
          (if (same? (%py-bound-fn a) (%py-bound-fn b))
            (%py-truthy (%py-eq (%py-bound-self a) (%py-bound-self b)))
            #f)
          #f))
      ((%py-bound-is b) #f)
      ((%py-dict? a)
        (if (%py-dict? b) (%py-dict-eq? (%py-dict-entries a) (%py-dict-entries b)) #f))
      ((%py-dict? b) #f)
      ((%py-set-is a)
        (if (%py-set-is b) (%py-set-eq? (%py-set-elems a) (%py-set-elems b)) #f))
      ((%py-set-is b) #f)
      ((%py-class-is a) (eq? a b))
      ((%py-class-is b) #f)
      ; a BOOL, always: the tower's `=` answers nil for an unequal complex,
      ; and a nil in a printed comparison reads as None
      ((= (if (eq? a #t) 1 (if (eq? a #f) 0 a))
             (if (eq? b #t) 1 (if (eq? b #f) 0 b)))
        #t)
      (#t #f))))
(def %py-ne
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (let ((r1 (%py-ne-side a b)))
        (if (not (eq? r1 %py-NotImplemented))
          r1
          (let ((r2 (%py-ne-side b a)))
            (if (not (eq? r2 %py-NotImplemented)) r2 (not (eq? a b))))))
      (not (%py-eq a b)))))

(def %py-ord-refuse
  (fn (_ op)
    (Err raise (lit type)
      (Str8 append (Str8 append "'" op) "' not supported between these instances") ())))

; Strings order lexicographically by code point; the engine's numeric `<`
; has no answer for them.  Self-recursive at top level -- no closure built
; per comparison.
(def %py-strcmp
  (fn (self a b i)
    (if (>= i (Str8 length a))
      (if (>= i (Str8 length b)) 0 (- 0 1))
      (if (>= i (Str8 length b))
        1
        (let ((ca (%py-char-code (%str-ref a i)))
              (cb (%py-char-code (%str-ref b i))))
          (if (< ca cb) (- 0 1) (if (> ca cb) 1 (self a b (+ i 1)))))))))

; Complex has no ordering, and the tower's `<` answers #f for it without a
; word -- so the refusal is stated here, on the handle compare that costs
; nothing per call.
(def %py-cmp-refuse
  (fn (_ a b op)
    (if (if (eq? (%py-typeof-prim a) %py-th-complex) #t
          (eq? (%py-typeof-prim b) %py-th-complex))
      (Err raise (lit type)
        (Str8 append (Str8 append "'" op) "' not supported between complex instances") ())
      ())))

; Lists and tuples order LEXICOGRAPHICALLY, element by element, and a prefix
; is less than what extends it -- Python's rule, and the reason sorting a
; list of tuples works at all.
; An array orders like the other sequences, element by element, which is
; what makes <, <=, > and >= answer for one without four arms of their own.
(def %py-seq-of
  (fn (_ v)
    (if (%py-list? v) (%py-list-elems v)
      (if (%py-tuple-is v) (%py-tuple-elems v)
        (if (%py-arr-is v) (%py-arr-el v) ())))))
(def %py-seq? (fn (_ v) (if (%py-list? v) #t (if (%py-tuple-is v) #t (%py-arr-is v)))))
(def %py-seq-cmp
  (fn (self a b)
    (match
      ((null? a) (if (null? b) 0 (- 0 1)))
      ((null? b) 1)
      ((%py-truthy (%py-eq (first a) (first b))) (self (rest a) (rest b)))
      ((%py-truthy (%py-lt (first a) (first b))) (- 0 1))
      (#t 1))))

(def %py-lt
  (fn (_ a b)
    (match
      ((if (%py-seq? a) (%py-seq? b) #f)
        (< (%py-seq-cmp (%py-seq-of a) (%py-seq-of b)) 0))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b "<"))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (< (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__lt__" "__gt__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse "<") r)))
      (#t (%py-lt-num a b)))))
(def %py-lt-num
  (fn (_ a b)
    (%py-cmp-refuse a b "<")
    (if (if (%py-str-is a) (%py-str-is b) #f)
      (< (%pb-cmp (%py-str-cps a) (%py-str-cps b)) 0)
      (< (if (eq? a #t) 1 (if (eq? a #f) 0 a))
         (if (eq? b #t) 1 (if (eq? b #f) 0 b))))))
(def %py-gt
  (fn (_ a b)
    (match
      ((if (%py-seq? a) (%py-seq? b) #f)
        (> (%py-seq-cmp (%py-seq-of a) (%py-seq-of b)) 0))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b ">"))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (> (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__gt__" "__lt__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse ">") r)))
      (#t (%py-gt-num a b)))))
(def %py-gt-num
  (fn (_ a b)
    (%py-cmp-refuse a b ">")
    (if (if (%py-str-is a) (%py-str-is b) #f)
      (> (%pb-cmp (%py-str-cps a) (%py-str-cps b)) 0)
      (> (if (eq? a #t) 1 (if (eq? a #f) 0 a))
         (if (eq? b #t) 1 (if (eq? b #f) 0 b))))))
(def %py-le
  (fn (_ a b)
    (match
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b "<="))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (<= (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__le__" "__ge__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse "<=") r)))
      ((if (%py-str-is a) (%py-str-is b) #f) (<= (%pb-cmp (%py-str-cps a) (%py-str-cps b)) 0))
      ((%py-lt a b) #t)
      (#t (%py-eq a b)))))
(def %py-ge
  (fn (_ a b)
    (match
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-cmp a b ">="))
      ; BYTES-LIKE ORDER IS BYTE ORDER, whichever of the two types is
      ; holding the buffer.  Without this arm the pair fell past every test
      ; here to the numeric one and was answered by whatever comparing two
      ; instances does -- which agreed with Python while both sides were
      ; PY-BYTES, and stopped agreeing the moment one was a bytearray.
      ((if (%py-bytes-is a) (%py-bytes-is b) #f)
        (>= (%pb-cmp (%py-bytes-list a) (%py-bytes-list b)) 0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (let ((r (%py-cmp2 a b "__ge__" "__le__")))
          (if (eq? r %py-NotImplemented) (%py-ord-refuse ">=") r)))
      ((if (%py-str-is a) (%py-str-is b) #f) (>= (%pb-cmp (%py-str-cps a) (%py-str-cps b)) 0))
      ((%py-gt a b) #t)
      (#t (%py-eq a b)))))

; --- Lists ------------------------------------------------------------------
;
; TAGGED, not a bare x list.  An empty Python list and None are different
; values, and a bare x list would make both of them nil -- so `print([])` would
; print None.  A list is (py-list . elements): the tag distinguishes it from
; every other value this runtime produces, and from nil.
(def %py-mklist (fn (_ . elems) (%py-list-new elems)))

; A SUBCLASS OF list IS A list wherever the runtime asks.  The question every
; list operation asks is this one, so teaching it about the wrapper is what
; makes `class mylist(list)` index, slice, grow, compare and print -- the
; accessors in types.x read through to the value the instance carries.
(def %py-list?
  (fn (_ v)
    (if (%py-list-is v)
      #t
      (if (%py-obj-is v) (%py-list-is (%py-obj-native v)) #f))))

(def %py-len
  (fn (_ v)
    (match
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__len__")))
          (if (null? m) (Err raise (lit type) "object of this type has no len()" ()) (m))))
      ((%py-arr-is v) (%py-length (%py-arr-el v)))
      ((%py-dict? v) (%py-length (%py-dict-entries v)))
      ((%py-tuple-is v) (%py-length (%py-tuple-elems v)))
      ((%py-list? v) (%py-length (%py-list-elems v)))
      ((%py-set-is v) (%py-length (%py-set-elems v)))
      ((%py-view-is v) (%py-length (%py-view-elems v)))
      ((%py-str-is v) (%pb-len (%py-str-cps v)))
      ((%py-bytes-is v) (%pb-len (%py-bytes-list v)))
      (#t (Err raise (lit type) "object of this type has no len()" ())))))

; NEGATIVE INDICES COUNT FROM THE END, which is Python and not x.  -1 is the
; last element, and an index past either end raises IndexError rather than
; returning nil -- a silent nil would propagate into arithmetic and surface far
; from the subscript that produced it.
(def %py-index
  (fn (_ v i)
    (match
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__getitem__")))
          (if (null? m) (Err raise (lit type) "object is not subscriptable" ()) (m i))))
      ((%py-arr-is v) (%py-arr-at v i))
      ((%py-str-is v)
        (let ((l (%py-str-cps v)))
          (let ((n (%pb-len l)))
            (let ((k (if (< i 0) (+ n i) i)))
              (if (if (< k 0) #t (>= k n))
                (Err raise (lit index) "string index out of range" ())
                (%py-str-new (list (%pb-ref l k))))))))
      ; a bytes index is the byte's value, an int
      ((%py-bytes-is v)
        (let ((l (%py-bytes-list v)))
          (let ((n (%pb-len l)))
            (let ((k (if (< i 0) (+ n i) i)))
              (if (if (< k 0) #t (>= k n))
                (Err raise (lit index) "index out of range" ())
                (%pb-ref l k))))))
      ; Subscripting a tuple and a dict are calls too -- see the list branch.
      ((%py-tuple-is v) (v i))
      ((%py-dict? v) (v i))
      ((not (%py-list? v))
        (Err raise (lit type) "object is not subscriptable" ()))
      ; SUBSCRIPTING A LIST IS A CALL.  x dispatches `(v i)` through the type's
      ; `call` handler, so negative indices and IndexError are stated once in
      ; python/types.x rather than copied here.
      (#t (v i)))))

; Store into a list at an index.  Rebuilds the element list and hangs it back on
; the SAME tag pair, so every reference sees the store -- the identity argument
; that made append work.
(def %py-set-nth
  (fn (self lst k v)
    (if (= k 0)
      (pair v (rest lst))
      (pair (first lst) (self (rest lst) (- k 1) v)))))

; --- del and slice assignment ------------------------------------------------
(def %py-delindex
  (fn (_ v i)
    ; __delitem__ was the one of the three item methods nothing dispatched:
    ; __getitem__ and __setitem__ were already here, so `del c[k]` on a class
    ; that defines it raised as though the class had said nothing.
    (match
      ((%py-obj-is v)
        (let ((m (%py-dunder v "__delitem__")))
          (if (null? m)
            (Err raise (lit type) "object does not support item deletion" ())
            (m i))))
      ((%py-dict? v) (%py-ddel v i))
      ((%py-list? v) ((%py-list-attr v "__delitem__") i))
      (#t (Err raise (lit type) "object does not support item deletion" ())))))
; the indices a slice selects, as (lo . hi) on a step of 1
(def %py-slice-span
  (fn (_ n start stop step)
    (if (if (null? step) #f (not (= (%py-boolnorm step) 1)))
      (Err raise (lit value) "only a step of 1 is supported here" ())
      (pair (%py-list-clamp n start 0) (%py-list-clamp n stop n)))))
(def %py-setslice
  (fn (_ v start stop step new)
    (if (not (%py-list? v))
      (Err raise (lit type) "object does not support slice assignment" ())
      (let ((els (%py-list-elems v)))
        (let ((sp (%py-slice-span (%py-length els) start stop step)))
          (let ((lo (first sp)))
            (let ((hi (if (< (rest sp) lo) lo (rest sp))))
              (%py-list-set! v
                (%py-list-cat (%py-take lo els)
                  (%py-list-cat (%py-iter-elems new) (%py-drop els hi)))))))))))
(def %py-delslice
  (fn (_ v start stop step)
    (%py-setslice v start stop step (%py-list-new ()))))

(def %py-setindex
  (fn (_ obj i v)
    (match
      ((%py-obj-is obj)
        (let ((m (%py-dunder obj "__setitem__")))
          (if (null? m)
            (Err raise (lit type) "object does not support item assignment" ())
            (m i v))))
      ((%py-arr-is obj) (%py-arr-put! obj i v))
      ((%py-dict? obj) (%py-dset obj i v))
      ((not (%py-list? obj))
        (Err raise (lit type) "object does not support item assignment" ()))
      (#t
        (let ((n (%py-length (%py-list-elems obj))))
          (let ((k (if (< i 0) (+ n i) i)))
            (if (if (< k 0) #t (>= k n))
              (Err raise (lit index) "list assignment index out of range" ())
              (%py-list-set! obj (%py-set-nth (%py-list-elems obj) k v)))))))))

; The escape continuation a `return` invokes.  Fetched rather than assumed
; global, the way every other prim in this bundle is reached.
(def %py-callcc (prim-ref (lit ctrl) (lit call/cc)))

; --- Unwinding on the way out ------------------------------------------------
;
; `return`, `break` and `continue` escape through that continuation, and the
; engine's call/cc restores the C stack straight past any `guard` standing
; between the jump and its binder.  So a `finally` -- and a `with`'s __exit__ --
; between the two never ran: the cleanup was owed and the escape walked out
; without paying it.
;
; A WIND STACK settles the debt.  A block that owes cleanup pushes a thunk for
; the duration of its body and drops it again on the way out; an escape runs
; everything the jump is about to skip, innermost first, before it jumps.
;
; The shape is x-r5rs's dynamic-wind (r5rs/scm/control.scm) over this same
; stack-copying call/cc, with the two differences Python asks for:
;
;   * ESCAPES ONLY TRAVEL OUTWARD.  `return`, `break` and `continue` are
;     one-shot and never re-entered, so the stack an escape was captured with
;     is always a tail of the one it is invoked with -- there is an exit walk
;     and no matching enter walk.
;
;   * A `yield` IS A SUSPENSION, NOT AN EXIT.  Python does not run a finally
;     when a generator yields through one; it runs it when the body is resumed
;     and leaves the block for good.  So generators keep the RAW call/cc and
;     swap the whole stack at the boundary (%py-gen-resume), which leaves a
;     suspended body's cleanup owed rather than paying it early.
;
; The stack is a cell holding a list of thunks, innermost first.  It is O(the
; nesting depth of blocks owing cleanup), never O(iterations): a loop pushes
; and drops the same one entry each time round.
(def %py-winds (pair () ()))

; The pushed node IS the token to drop it by -- dropping restores exactly what
; was underneath, so an unbalanced push in between cannot strand the stack.
(def %py-wind-push!
  (fn (_ after)
    (%seq (%set-first! %py-winds (pair after (first %py-winds)))
      (first %py-winds))))

(def %py-wind-drop! (fn (_ node) (%seq (%set-first! %py-winds (rest node)) ())))

; Run what the jump would skip, back down to the stack the escape was captured
; with.  Each entry is dropped BEFORE its thunk runs, so a cleanup that escapes
; again -- a `return` inside a `finally` -- cannot meet itself coming back.
(def %py-wind-unwind!
  (fn (self target)
    (let ((cur (first %py-winds)))
      (match
        ((same? cur target) ())
        ; the target is not below us: nothing sane left to run, so restore the
        ; stack rather than paying debts that are not ours
        ((null? cur) (%seq (%set-first! %py-winds target) ()))
        (#t
          (%seq (%set-first! %py-winds (rest cur))
            (%seq ((first cur)) (self target))))))))

; call/cc for an escape: the continuation it hands the body settles the wind
; stack back to what it was here before it jumps.
(def %py-escape
  (fn (_ body)
    (let ((saved (first %py-winds)))
      (%py-callcc
        (fn (_ k)
          (body (fn (_ v) (%seq (%py-wind-unwind! saved) (k v)))))))))

; --- Iteration ---------------------------------------------------------------
;
; The elements a `for` walks.  A list gives its own; a string gives its
; characters, because Python iterates a string by character and several
; conformance programs depend on it.
(def %py-str-chars
  (fn (self v i n)
    (if (>= i n) () (pair (Str8 sub i 1 v) (self v (+ i 1) n)))))

; WHAT __iter__ ANSWERED, as a list of items.  An instance that is not an
; iterator is the error Python names; anything else is iterated as it stands.
; Both iteration doors read the ANSWER through this, because asking the object
; for __iter__ a second time runs it a second time -- which for a stream is a
; second read, and for any object is a side effect the program wrote once.
(def %py-iter-answer
  (fn (_ it)
    (if (%py-obj-is it)
      (Err raise (lit type) "iter() returned non-iterator" ())
      (%py-iter-elems it))))

; AN OBJECT ITERATES BY ITS PROTOCOL: __iter__ hands back an iterator whose
; __next__ is called until it raises StopIteration -- materialized here into
; the element list every consumer already walks.  Without __iter__, the old
; sequence protocol: __getitem__ from 0 until IndexError.
(def %py-obj-elems
  (fn (_ v)
    (let ((it-m (%py-dunder v "__iter__")))
      (if (not (null? it-m))
        (let ((it (it-m)))
          (let ((nx (if (%py-obj-is it) (%py-dunder it "__next__") ())))
            (if (null? nx)
              (%py-iter-answer it)
              (do
                (def go
                  (fn (self acc)
                    (let ((r (guard (e (if (%py-exc-match e %py-exc-StopIteration)
                                            %py-NotImplemented
                                            (error e)))
                                (nx))))
                      (if (eq? r %py-NotImplemented)
                        (%py-reverse acc)
                        (self (pair r acc))))))
                (go ())))))
        (let ((gi (%py-dunder v "__getitem__")))
          (if (null? gi)
            (Err raise (lit type) "object is not iterable" ())
            (do
              (def go
                (fn (self i acc)
                  (let ((r (guard (e (if (%py-exc-match e %py-exc-IndexError)
                                          %py-NotImplemented
                                          (error e)))
                              (gi i))))
                    (if (eq? r %py-NotImplemented)
                      (%py-reverse acc)
                      (self (+ i 1) (pair r acc))))))
              (go 0 ()))))))))

(def %py-iter-elems
  (fn (_ v . who)
    (match
      ((%py-obj-is v) (%py-obj-elems v))
      ((%py-io-is v) (%py-io-drain! v))
      ((%py-arr-is v) (%py-arr-el v))
      ; Iterating a dict yields its KEYS, as in Python.
      ((%py-dict? v) (%py-dkeys (%py-dict-entries v)))
      ((%py-tuple-is v) (%py-tuple-elems v))
      ((%py-list? v) (%py-list-elems v))
      ((%py-set-is v) (%py-set-elems v))
      ((%py-view-is v) (%py-view-elems v))
      ((%py-str-is v) (%py-str-chars-of (%py-str-cps v) ()))
      ; iterating bytes yields ints
      ((%py-bytes-is v)
        (%py-bytes-list v))
      ; a generator runs to its end; every consumer here wants the whole list
      ((%py-gen-is v) (%py-gen-drain v ()))
      ; A CALLER MAY NAME ITSELF IN THE REFUSAL.  "object is not iterable" is
      ; true and says nothing about what was being attempted; `','.join(5)`
      ; wants to talk about join.  Taken as a trailing argument so that the
      ; thirty-odd existing call sites stay exactly as they are -- one
      ; implementation with a door, not a copy per caller.
      (#t (Err raise (lit type)
            (if (null? who) "object is not iterable" (first who)) ())))))

; range(stop) / range(start, stop) / range(start, stop, step)
;
; EAGER, and that is a simplification with a known cost: Python 3's range is
; lazy, so `range(10000000)` is free there and a ten-million element list here.
; Every conformance program that uses range walks all of it, so the difference
; is memory rather than answers -- but it is a difference, and it is written
; down rather than discovered.
;
; A zero step raises rather than looping forever.  There is no depth limit on
; non-tail calls here (x-lang#56), so an unbounded loop is an OOM.
(def %py-range-build
  (fn (self i stop step acc)
    (if (if (> step 0) (>= i stop) (<= i stop))
      (%py-reverse acc)
      (self (+ i step) stop step (pair i acc)))))

(def %py-range
  (fn (_ . args)
    (if (null? args)
      (Err raise (lit type) "range expected at least 1 argument" ())
      (let ((start (if (null? (rest args)) 0 (first args)))
            (stop  (if (null? (rest args)) (first args) (first (rest args))))
            (step  (if (null? (rest args)) 1
                     (if (null? (rest (rest args))) 1
                       (first (rest (rest args)))))))
        (if (= step 0)
          (Err raise (lit value) "range() arg 3 must not be zero" ())
          (%py-list-new (%py-range-build start stop step ())))))))

; --- Dicts -------------------------------------------------------------------
;
; ENTRIES IN INSERTION ORDER, not a hash table. x/type/dict.x is a content-hashed
; mutable table and would be faster, but Python 3.7+ preserves insertion order
; and the conformance suite compares PRINTED output -- so the order is part of
; the answer, not an implementation detail. An association list keeps it for
; free; lookup is O(n), which is the right trade at this size.
;
; The representation is python/types.x's PY-DICT; what is here is what the
; parser calls and what Python's rules say.
(def %py-dict? (fn (_ v) (%py-dict-is v)))

(def %py-mkdict
  (fn (_ . entries)
    (def check (fn (self es) (if (null? es) () (%seq (%py-check-hashable! (first (first es))) (self (rest es))))))
    (check entries)
    (%py-dict-new entries)))

(def %py-dfind
  (fn (self k entries)
    (if (null? entries)
      ()
      (if (%py-eq k (first (first entries)))
        (first entries)
        (self k (rest entries))))))

(def %py-dget
  (fn (_ d k)
    (let ((e (%py-dfind k (%py-dict-entries d))))
      (if (null? e)
        ; a real instance, so `except KeyError as e: e.args` works
        (error (%py-instantiate %py-exc-KeyError (list k)))
        (rest e)))))

(def %py-dappend
  (fn (self entries e)
    (if (null? entries) (list e) (pair (first entries) (self (rest entries) e)))))

(def %py-dset
  (fn (_ d k v)
    (let ((e (%py-dfind k (%py-dict-entries d))))
      (if (null? e)
        ; A new key goes on the END: insertion order is the printed order.
        (%py-dict-set! d (%py-dappend (%py-dict-entries d) (pair k v)))
        (%seq (%set-rest! e v) ())))))

(def %py-dkeys (fn (self entries) (if (null? entries) () (pair (first (first entries)) (self (rest entries))))))
(def %py-dvals (fn (self entries) (if (null? entries) () (pair (rest (first entries)) (self (rest entries))))))

; --- The list method surface -------------------------------------------------
(def %py-els-repeat
  (fn (self l k acc) (if (<= k 0) acc (self l (- k 1) (%py-list-cat acc l)))))
(def %py-els-drop-at
  (fn (self l i) (if (null? l) () (if (= i 0) (rest l) (pair (first l) (self (rest l) (- i 1)))))))
(def %py-els-insert-at
  (fn (self l i v) (if (= i 0) (pair v l) (if (null? l) (list v) (pair (first l) (self (rest l) (- i 1) v))))))
(def %py-els-set-at
  (fn (self l i v) (if (null? l) () (if (= i 0) (pair v (rest l)) (pair (first l) (self (rest l) (- i 1) v))))))
(def %py-els-index
  (fn (self l i stop v)
    (match
      ((null? l) (- 0 1))
      ((>= i stop) (- 0 1))
      ((%py-truthy (%py-eq v (first l))) i)
      (#t (self (rest l) (+ i 1) stop v)))))
(def %py-els-count
  (fn (self l v acc)
    (if (null? l) acc (self (rest l) v (if (%py-truthy (%py-eq v (first l))) (+ acc 1) acc)))))
(def %py-list-kw-names
  (fn (_ name) (if (Str8 =? name "sort") (list "key" "reverse") ())))
(def %py-list-norm-i
  (fn (_ n i) (let ((k (%py-boolnorm i))) (if (< k 0) (+ n k) k))))
(def %py-list-clamp
  (fn (_ n v dflt)
    (let ((x (if (null? v) dflt (%py-boolnorm v))))
      (if (< x 0) (let ((w (+ n x))) (if (< w 0) 0 w)) (if (> x n) n x)))))

(def %py-list-attr
  (fn (_ obj name)
    (let ((els (%py-list-elems obj)))
      (let ((n (%py-length els)))
        (match
          ((Str8 =? name "append")
            (fn (_ . a)
              (if (not (= (%py-length a) 1))
                (Err raise (lit type)
                  (Str8 append "list.append() takes exactly one argument ("
                    (Str8 append (%py-str (%py-length a)) " given)")) ())
                (%py-list-set! obj (%py-append-elem (%py-list-elems obj) (first a))))))
          ((Str8 =? name "extend")
            (fn (_ it) (%py-list-set! obj (%py-list-cat (%py-list-elems obj) (%py-iter-elems it)))))
          ((Str8 =? name "insert")
            (fn (_ i v) (%py-list-set! obj (%py-els-insert-at (%py-list-elems obj) (%py-list-clamp n i 0) v))))
          ; The keyword door hands sort exactly two slots (key, reverse); a
          ; call that arrives with any other count gave positional arguments,
          ; which sort does not take.
          ((Str8 =? name "sort")
            (fn (_ . a)
              (if (if (null? a) #f (not (= (%py-length a) 2)))
                (Err raise (lit type) "sort() takes no positional arguments" ())
                ())
              (let ((key (%py-opt a 0 ())))
                (let ((rev (%py-opt a 1 #f)))
                  (let ((l (%py-msort-by (%py-list-elems obj) (if (null? key) %py-ident key))))
                    (%py-list-set! obj (if (%py-truthy rev) (%py-reverse l) l)))))))
          ((Str8 =? name "reverse")
            (fn (_) (%py-list-set! obj (%py-reverse (%py-list-elems obj)))))
          ((Str8 =? name "clear") (fn (_) (%py-list-set! obj ())))
          ((Str8 =? name "copy")
            (fn (_) (%py-list-new (%py-list-elems obj))))
          ((Str8 =? name "count")
            (fn (_ v) (%py-els-count (%py-list-elems obj) v 0)))
          ((Str8 =? name "index")
            (fn (_ v . a)
              (let ((lo (%py-list-clamp n (%py-s-arg a 0) 0)))
                (let ((hi (%py-list-clamp n (%py-s-arg a 1) n)))
                  (let ((i (%py-els-index (%py-drop els lo) lo hi v)))
                    (if (< i 0)
                      (error (%py-instantiate %py-exc-ValueError (list (Str8 append (%py-repr-of v) " is not in list"))))
                      i))))))
          ((Str8 =? name "remove")
            (fn (_ v)
              (let ((i (%py-els-index (%py-list-elems obj) 0 n v)))
                (if (< i 0)
                  (error (%py-instantiate %py-exc-ValueError (list "list.remove(x): x not in list")))
                  (%py-list-set! obj (%py-els-drop-at (%py-list-elems obj) i))))))
          ((Str8 =? name "pop")
            (fn (_ . a)
              (if (= n 0)
                (Err raise (lit index) "pop from empty list" ())
                (let ((i (if (null? a) (- n 1) (%py-list-norm-i n (first a)))))
                  (if (if (< i 0) #t (>= i n))
                    (Err raise (lit index) "pop index out of range" ())
                    (let ((v (List ref i (%py-list-elems obj))))
                      (%seq (%py-list-set! obj (%py-els-drop-at (%py-list-elems obj) i)) v)))))))
          ((Str8 =? name "__getitem__") (fn (_ i) (%py-index obj i)))
          ((Str8 =? name "__setitem__")
            (fn (_ i v) (%py-list-set! obj (%py-els-set-at (%py-list-elems obj) (%py-list-norm-i n i) v))))
          ((Str8 =? name "__delitem__")
            (fn (_ i) (%py-list-set! obj (%py-els-drop-at (%py-list-elems obj) (%py-list-norm-i n i)))))
          (#t
            (Err raise (lit attribute)
              (Str8 append (Str8 append "'list' object has no attribute '" name) "'") ())))))))

; --- Dict helpers ------------------------------------------------------------
(def %py-ditems
  (fn (self es)
    (if (null? es) () (pair (%py-tuple-new (list (first (first es)) (rest (first es)))) (self (rest es))))))
(def %py-dict-drop
  (fn (self es k)
    (if (null? es) ()
      (if (%py-truthy (%py-eq k (first (first es))))
        (self (rest es) k)
        (pair (first es) (self (rest es) k))))))
(def %py-pairs-of
  (fn (self vs acc)
    (if (null? vs) (%py-reverse acc)
      (let ((kv (%py-iter-elems (first vs))))
        (if (not (= (%py-length kv) 2))
          (error (%py-instantiate %py-exc-ValueError
            (list (Str8 append
                    (Str8 append "dictionary update sequence element has length "
                      (%py-str (%py-length kv)))
                    "; 2 is required"))))
          (self (rest vs) (pair (pair (first kv) (first (rest kv))) acc)))))))
(def %py-dict-merge!
  (fn (_ d o)
    (let ((rows (if (%py-dict? o) (%py-dict-copy (%py-dict-entries o)) (%py-pairs-of (%py-iter-elems o) ()))))
      (let ((put (fn (self l) (if (null? l) () (%seq (%py-dset d (first (first l)) (rest (first l))) (self (rest l)))))))
        (put rows)))))
(def %py-ddel
  (fn (_ d k)
    (if (null? (%py-dfind k (%py-dict-entries d)))
      (error (%py-instantiate %py-exc-KeyError (list k)))
      (%py-dict-set! d (%py-dict-drop (%py-dict-entries d) k)))))
(def %py-dict-fromkeys
  (fn (_ it . v)
    (let ((val (if (null? v) () (first v))))
      (let ((go (fn (self ks acc) (if (null? ks) (%py-reverse acc) (self (rest ks) (pair (pair (first ks) val) acc))))))
        (%py-dict-new (go (%py-iter-elems it) ()))))))

(def %py-dict-attr
  (fn (_ d name)
    (match
      ((Str8 =? name "keys")
        (fn (_) (%py-view-new "dict_keys" (%py-dkeys (%py-dict-entries d)))))
      ((Str8 =? name "values")
        (fn (_) (%py-view-new "dict_values" (%py-dvals (%py-dict-entries d)))))
      ((Str8 =? name "items")
        (fn (_) (%py-view-new "dict_items" (%py-ditems (%py-dict-entries d)))))
      ((Str8 =? name "get")
        (fn (_ k . dflt)
          (let ((e (%py-dfind k (%py-dict-entries d))))
            (if (null? e) (if (null? dflt) () (first dflt)) (rest e)))))
      ((Str8 =? name "setdefault")
        (fn (_ k . dflt)
          (let ((e (%py-dfind k (%py-dict-entries d))))
            (if (not (null? e))
              (rest e)
              (let ((v (if (null? dflt) () (first dflt))))
                (%seq (%py-dset d k v) v))))))
      ((Str8 =? name "pop")
        (fn (_ k . dflt)
          (let ((e (%py-dfind k (%py-dict-entries d))))
            (if (null? e)
              (if (null? dflt) (error (%py-instantiate %py-exc-KeyError (list k))) (first dflt))
              (%seq (%py-dict-set! d (%py-dict-drop (%py-dict-entries d) k)) (rest e))))))
      ((Str8 =? name "popitem")
        (fn (_)
          (let ((rows (%py-dict-entries d)))
            (if (null? rows)
              (error (%py-instantiate %py-exc-KeyError (list "popitem(): dictionary is empty")))
              (let ((last (List ref (- (%py-length rows) 1) rows)))
                (%seq (%py-dict-set! d (%py-drop-last rows))
                  (%py-tuple-new (list (first last) (rest last)))))))))
      ((Str8 =? name "update")
        (fn (_ . a) (if (null? a) () (%py-dict-merge! d (first a)))))
      ((Str8 =? name "clear") (fn (_) (%py-dict-set! d ())))
      ((Str8 =? name "copy")
        (fn (_) (%py-dict-new (%py-dict-copy (%py-dict-entries d)))))
      ((Str8 =? name "__contains__")
        (fn (_ k) (not (null? (%py-dfind k (%py-dict-entries d))))))
      ((Str8 =? name "__getitem__") (fn (_ k) (%py-dget d k)))
      ((Str8 =? name "__setitem__") (fn (_ k v) (%py-dset d k v)))
      ((Str8 =? name "__delitem__") (fn (_ k) (%py-ddel d k)))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'dict' object has no attribute '" name) "'")
          ())))))

