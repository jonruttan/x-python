; # x-python -- Python on x-lang
;
; ## lib/python/_weakref.x -- the _weakref module
;
; @description The weak cell that stdlib/weakref.py builds ref and finalize
;   on: an object held by its address, which the collector does not follow,
;   and a free hook that tells which cells the next sweep leaves dangling.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A REFERENCE THE COLLECTOR CANNOT SEE is an address: an int, which marks
; nothing.  (ptr ->obj) reads it back as the object, and the platform's heap
; does not move, so the address is the object for as long as it lives.
;
; KNOWING WHEN IT DIES is the free hook.  The engine fires each free hook
; once a collection, after the mark and before the sweep (x_heap_sweep_phase),
; so at that moment an object's MARK flag says whether the sweep keeps it.
; The hook walks the cells and flags each one whose object is unmarked: dead.
; It also reads the mark of the Python ref that owns the cell, held by
; address the same way, and flags the cell gone when the ref itself is being
; collected -- a ref that dies first calls no callback, as CPython's does not.
;
; THE HOOK WRITES NOTHING NEW.  Whatever it allocates is born after the mark,
; unmarked, and the sweep frees it; that is harmless for its own frames but
; fatal for anything it stores.  So it only sets the first of a cell that
; already exists to a symbol, which the base already holds.
;
; CALLBACKS RUN AT gc.collect().  A cell flagged dead is answered by dead(),
; newest first as CPython calls them, and weakref.py runs each callback after
; the collect returns -- never inside it, since a callback is Python, and
; Python allocates.  A collection the runtime makes on its own (the GC tick in
; util.x) flags cells as well, and their callbacks wait for the next
; gc.collect().  A ref's object reads as None from the moment it is flagged.
;
; A cell is a list, (state referent-address ref-address callback): states
; live, dead, gone.

(module python/_weakref)
(import python/modules PyModule)
(import python/core python-gc-after python-list-new python-module-new python-tuple-new)
(import x/core/doors int& int= int+ int->ptr obj->ptr ptr->int ptr->obj ptr-ref-word)

(def %wk-flags-off (* %obj-slot-flags %word-size))
(def %wk-addr (fn (_ o) (ptr->int (obj->ptr o))))
(def %wk-marked?
  (fn (_ a) (if (int= (int& (ptr-ref-word (int->ptr a) %wk-flags-off) %obj-flag-mark) 0) #f #t)))

; every cell not yet answered, newest first, and how many were made since the
; list was last pruned
(def %wk-cells (pair () ()))
(def %wk-made (pair 0 ()))
(def %wk-hooked (pair #f ()))

(def %wk-state (fn (_ c) (first c)))
(def %wk-obj (fn (_ c) (first (rest c))))
(def %wk-ref (fn (_ c) (first (rest (rest c)))))
(def %wk-callback (fn (_ c) (first (rest (rest (rest c))))))

; THE HOOK: no allocation that outlives it
(def %wk-flag!
  (fn (self cs)
    (if (null? cs) ()
      (let ((c (first cs)))
        (match
          ((eq? (%wk-state c) (lit live))
            (match
              ((%wk-marked? (%wk-ref c))
                (if (%wk-marked? (%wk-obj c)) () (%set-first! c (lit dead))))
              (#t (%set-first! c (lit gone)))))
          (#t ()))
        (self (rest cs))))))
(def %wk-hook (fn (_) (%wk-flag! (first %wk-cells))))

; the cells still live, in order
(def %wk-live
  (fn (self cs)
    (match
      ((null? cs) ())
      ((eq? (%wk-state (first cs)) (lit live)) (pair (first cs) (self (rest cs))))
      (#t (self (rest cs))))))
(def %wk-prune!
  (fn (_)
    (%set-first! %wk-cells (%wk-live (first %wk-cells)))
    (%set-first! %wk-made 0)))

(def %wk-new
  (fn (_ obj ref callback)
    (if (first %wk-hooked) ()
      (do ((prim-ref (lit heap) (lit free-hook!)) %wk-hook)
          (%set-first! %wk-hooked #t)))
    (if (int= (first %wk-made) 1024) (%wk-prune!) ())
    (%set-first! %wk-made (int+ (first %wk-made) 1))
    (let ((c (list (lit live) (%wk-addr obj) (%wk-addr ref) callback)))
      (%set-first! %wk-cells (pair c (first %wk-cells)))
      c)))

(def %wk-get
  (fn (_ c)
    (if (eq? (%wk-state c) (lit live)) (ptr->obj (int->ptr (%wk-obj c))) ())))

; (ref . callback) for each cell flagged dead whose callback is not None,
; newest first; every cell answered or gone leaves the list
(def %wk-dead
  (fn (self cs)
    (match
      ((null? cs) ())
      ((eq? (%wk-state (first cs)) (lit dead))
        (let ((c (first cs)))
          (%set-first! c (lit gone))
          (if (null? (%wk-callback c))
            (self (rest cs))
            (pair (python-tuple-new (list (ptr->obj (int->ptr (%wk-ref c))) (%wk-callback c)))
                  (self (rest cs))))))
      (#t (self (rest cs))))))

; the live cells on OBJ, newest first
(def %wk-on
  (fn (self cs a)
    (match
      ((null? cs) ())
      ((if (eq? (%wk-state (first cs)) (lit live)) (int= (%wk-obj (first cs)) a) #f)
        (pair (first cs) (self (rest cs) a)))
      (#t (self (rest cs) a)))))

(def python-_weakref-module
  (fn (_)
    (python-module-new "_weakref"
      (list
        (pair "new" (fn (_ obj ref callback) (%wk-new obj ref callback)))
        (pair "get" (fn (_ c) (%wk-get c)))
        (pair "alive" (fn (_ c) (eq? (%wk-state c) (lit live))))
        (pair "kill" (fn (_ c) (%set-first! c (lit gone)) ()))
        (pair "dead"
          (fn (_)
            (let ((out (%wk-dead (first %wk-cells))))
              (%wk-prune!)
              (python-list-new out))))
        (pair "refs"
          (fn (_ obj)
            (python-list-new
              (List map (fn (_ c) (ptr->obj (int->ptr (%wk-ref c))))
                (%wk-on (first %wk-cells) (%wk-addr obj))))))
        (pair "on_collect" (fn (_ f) (%set-first! python-gc-after f) ()))))))

; The row in the table of built-in modules (python/modules).
(PyModule def-static! (lit _weakref) (fn (_ cls) (python-_weakref-module)))

(provide python/_weakref python-_weakref-module)
