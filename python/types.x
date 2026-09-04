; # x-python -- Python on x-lang
;
; ## python/types.x -- Python's values are x TYPES, not tagged pairs
;
; @description Registers Python's container types on the running base, so that
;   printing, indexing, length and iteration are dispatched by the engine
;   rather than by a chain of tag tests in the runtime.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY THIS IS NOT A CHILD BASE
;
; The first attempt built Python a base of its own with `(Base make)` and
; `base-make-type`, and it reached 190 of 232 specs before stopping dead: a
; child base has no numeric tower, so `(* 2 1.5)` answered 105759989792.  The
; tower's float, rational and bigint types are registered on the base that
; loaded them, and a fresh base is not that base.
;
; `make-type` -- the two-argument prim, ns `type`, member `make` -- registers
; onto the base it is CALLED in.  So Python's types go onto the same running
; base that already carries the tower, and nothing has to be rebuilt.  This is
; how x's own library types do it: x/num/rational.x and x/type/vector.x are the
; models this file follows, down to the handler arity.
;
; ## HANDLER ARITY IS (fn (_ self) ...), AND GETTING IT WRONG SEGFAULTS
;
; Every handler's first parameter is the TYPE and the second is the instance.
; Writing `(fn (self) ...)` binds the type to `self`, and `(first <a type>)` is
; a read of a non-pair -- x-engine-c#16, which is a segfault and not an error.
;
; ## THE PAYLOAD IS A CELL, SO THAT MUTATION IS SHARED
;
; `make-instance` gives an object with one data slot.  Putting the elements
; DIRECTLY in that slot would make `x.append(5)` rebuild-and-return, which is
; the bug the old tagged pair was shaped to avoid.  So the slot holds a cell --
; a pair whose rest is the element list -- and append replaces the rest of that
; cell.  Every reference to the list holds the same instance, the instance
; holds the same cell, so every reference sees the store.

(provide python/types
  %py-bytes %py-bytes-new %py-bytes-is %py-bytes-str
  %py-gen %py-gen-new %py-gen-is %py-gen-state
  %py-set %py-set-new %py-set-is %py-set-elems %py-set-set! %py-set-frozen?
  %py-view %py-view-new %py-view-is %py-view-kind %py-view-elems
  %py-list %py-list-new %py-list-is %py-list-elems %py-list-set!
  %py-dict %py-dict-new %py-dict-is %py-dict-entries %py-dict-set! %py-dict-get
  %py-repr %py-equal %py-repeat
  %py-tuple %py-tuple-new %py-tuple-is %py-tuple-elems
  %py-class %py-class-new %py-class-is %py-class-name %py-class-base
  %py-class-methods %py-class-qualname %py-instantiate %py-obj-write %py-obj-call
  %py-obj %py-obj-new %py-obj-is %py-obj-class %py-obj-attrs %py-obj-set-attrs!
  %py-super-t %py-super-new %py-super-is %py-super-from %py-super-self)

; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %type-by-atom (prim-ref (lit type) (lit by-atom)))
(def %type-push-op (prim-ref (lit type) (lit push-op)))
(def %i-make (prim-ref (lit iter) (lit make)))

; EXHAUSTION RIDES THE STATE, NOT THE VALUE.  A step answers
; (value . next-state) and only a nil PAIR ends the walk -- so a nil VALUE is an
; ordinary element.  That is what makes a list containing None iterable, and it
; is the whole reason these are shaped this way: the first version returned bare
; values and ended on nil, which would have stopped at the first None.  Nothing
; consumed the slot, so nothing caught it.
(def %py-list-step
  (fn (_ st) (if (null? st) () (pair (first st) (rest st)))))

; Iterating a dict yields its KEYS, as in Python.  The state stays the entry
; list; only the yielded value differs.
(def %py-dict-step
  (fn (_ st) (if (null? st) () (pair (first (first st)) (rest st)))))
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %type? (prim-ref (lit type) (lit ?)))

; Forward declaration, the way x/num/rational.x forward-declares its reader.
; runtime.x owns Python's repr -- a string prints as 'a' inside a list and as a
; here at the top level -- and this file is loaded first, so the write handler
; reaches it through a hook rather than a load-order assumption.
(def %py-repr ())

(def %py-list ())

; --- The element cell --------------------------------------------------------

; A float index is a TypeError, so the subscript handler needs to recognise a
; machine float; the type handle compare is the same shape runtime.x uses.
(def %py-t-typeof (prim-ref (lit type) (lit of)))
(def %py-t-th-float (%py-t-typeof 1.5))
(def %py-t-float? (fn (_ v) (eq? (%py-t-typeof v) %py-t-th-float)))

(def %py-list-elems (fn (_ v) (rest (first v))))
(def %py-list-set! (fn (_ v new) (%seq (%set-rest! (first v) new) ())))
(def %py-list-new (fn (_ elems) (%make-instance %py-list (pair () elems))))
(def %py-list-is (fn (_ v) (%type? v %py-list)))

; --- PY-LIST -----------------------------------------------------------------

(set! %py-list
  (%make-type
    "PY-LIST"
    (list
      ; repr, and str() of a list is its repr in Python -- so `display` is not
      ; registered separately and the engine falls back to this for both.
      (pair
        (lit write)
        (fn (_ self)
          (display "[")
          (def go
            (fn (recur l sep)
              (if (not (null? l))
                (do
                  (if sep (display ", "))
                  (%py-repr (first l))
                  (recur (rest l) #t)))))
          (go (rest (first self)) #f)
          (display "]")))
      ; len() reaches this through the runtime's %py-len, which still dispatches
      ; across str and dict; registering it here is what makes the type honest
      ; to anything else that asks.
      (pair (lit length) (fn (_ self) (List length (rest (first self)))))
      ; SUBSCRIPTING IS A CALL.  x dispatches `(v i)` through a type's `call`
      ; handler, so `lst[0]` needs no runtime function at all -- and negative
      ; indices and IndexError, which are Python and not x, are stated here
      ; once instead of at every subscript site.
      (pair
        (lit call)
        (fn (_ self . args)
          (def l (rest (first self)))
          (def n (List length l))
          (def i (first args))
          ; `x[1.0]` is a TypeError in Python, not an index -- and without
          ; this check the float silently truncates to a working index, the
          ; wrong-number failure mode again (conformance float/list).
          (if (%py-t-float? i)
            (Err raise (lit type)
              "list indices must be integers or slices, not float" ())
            (do
              (def k (if (< i 0) (+ n i) i))
              (if (if (< k 0) #t (>= k n))
                (Err raise (lit index) "list index out of range" ())
                (List ref k l))))))
      (pair
        (lit iter)
        (fn (_ self) (%i-make %py-list-step (rest (first self))))))))

; --- PY-DICT -----------------------------------------------------------------
;
; ENTRIES IN INSERTION ORDER, not a hash table.  x/type/dict.x is a
; content-hashed mutable table and would be faster, but Python 3.7+ preserves
; insertion order and the conformance suite compares PRINTED output -- so the
; order is part of the answer, not an implementation detail.  An association
; list keeps it for free; lookup is O(n), which is the right trade at this size.
;
; Each entry is a (key . value) pair, and updating a value mutates THAT pair --
; so the entry list itself only changes when a key is added, and the cell is
; what makes that visible to every reference.

; --- PY-SET ------------------------------------------------------------------
;
; A set is a LIST OF DISTINCT ELEMENTS in insertion order, shaped exactly like
; PY-DICT: a (flag . elements) pair behind the instance, so the cell is what
; makes a mutation visible to every reference.  The flag is the frozen bit --
; a frozenset is the same type with mutation refused and hashing allowed.
;
; INSERTION ORDER IS NOT AN IMPLEMENTATION DETAIL HERE.  CPython's iteration
; order is its hash table's, which for the small non-negative ints the corpus
; uses IS ascending -- and `set(range(N))` then pops 0, 1, 2 ... in order.
; Insertion order reproduces that, and every other case in the corpus sorts
; before printing.  Membership uses Python's equality (%py-eq in runtime.x),
; which is why construction lives there: `{False, 0}` is one element.
(def %py-set ())
(def %py-set-frozen? (fn (_ v) (first (first v))))
(def %py-set-elems (fn (_ v) (rest (first v))))
(def %py-set-set! (fn (_ v new) (%seq (%set-rest! (first v) new) ())))
(def %py-set-new (fn (_ frozen elems) (%make-instance %py-set (pair frozen elems))))
(def %py-set-is (fn (_ v) (%type? v %py-set)))
(def %py-set-step (fn (_ st) (if (null? st) () (pair (first st) (rest st)))))

(set! %py-set
  (%make-type
    "PY-SET"
    (list
      ; an empty one has no braces to print: set() and frozenset()
      (pair
        (lit write)
        (fn (_ self)
          (def frozen (first (first self)))
          (def es (rest (first self)))
          (if (null? es)
            (display (if frozen "frozenset()" "set()"))
            (do
              (display (if frozen "frozenset({" "{"))
              (def go
                (fn (recur l sep)
                  (if (not (null? l))
                    (do
                      (if sep (display ", "))
                      (%py-repr (first l))
                      (recur (rest l) #t)))))
              (go es #f)
              (display (if frozen "})" "}"))))))
      (pair (lit length) (fn (_ self) (List length (rest (first self)))))
      (pair (lit iter) (fn (_ self) (%i-make %py-set-step (rest (first self))))))))

; --- PY-VIEW -----------------------------------------------------------------
; What d.keys(), d.values() and d.items() answer: a named sequence that
; prints as dict_keys([...]), has a length and a truth, and iterates.  A
; SNAPSHOT rather than CPython's live window -- the corpus prints them and
; lists them, and a live view would need the dict to publish changes.
(def %py-view ())
(def %py-view-kind (fn (_ v) (first (first v))))
(def %py-view-elems (fn (_ v) (rest (first v))))
(def %py-view-new (fn (_ kind elems) (%make-instance %py-view (pair kind elems))))
(def %py-view-is (fn (_ v) (%type? v %py-view)))
(def %py-view-step (fn (_ st) (if (null? st) () (pair (first st) (rest st)))))
(set! %py-view
  (%make-type
    "PY-VIEW"
    (list
      (pair (lit write)
        (fn (_ self)
          (display (first (first self)) "([")
          (def go
            (fn (recur l sep)
              (if (not (null? l))
                (do
                  (if sep (display ", "))
                  (%py-repr (first l))
                  (recur (rest l) #t)))))
          (go (rest (first self)) #f)
          (display "])")))
      (pair (lit length) (fn (_ self) (List length (rest (first self)))))
      (pair (lit iter) (fn (_ self) (%i-make %py-view-step (rest (first self))))))))

(def %py-dict ())

; Subscripting a dict needs Python's equality -- `1 == 1.0` is true there and
; two different x values here -- and that lives in runtime.x with the rest of
; the operators.  So the `call` handler reaches it through a hook, the same way
; the write handlers reach repr.
(def %py-dict-get ())

(def %py-dict-entries (fn (_ v) (rest (first v))))
(def %py-dict-set! (fn (_ v new) (%seq (%set-rest! (first v) new) ())))
(def %py-dict-new (fn (_ entries) (%make-instance %py-dict (pair () entries))))
(def %py-dict-is (fn (_ v) (%type? v %py-dict)))

(set! %py-dict
  (%make-type
    "PY-DICT"
    (list
      (pair
        (lit write)
        (fn (_ self)
          (display "{")
          (def go
            (fn (recur es sep)
              (if (not (null? es))
                (do
                  (if sep (display ", "))
                  (%py-repr (first (first es)))
                  (display ": ")
                  (%py-repr (rest (first es)))
                  (recur (rest es) #t)))))
          (go (rest (first self)) #f)
          (display "}")))
      (pair (lit length) (fn (_ self) (List length (rest (first self)))))
      (pair
        (lit call)
        (fn (_ self . args) (%py-dict-get self (first args))))
      (pair
        (lit iter)
        (fn (_ self) (%i-make %py-dict-step (rest (first self))))))))

; --- Operators ---------------------------------------------------------------
;
; PUSHED ONTO PYTHON'S OWN TYPES, NEVER ONTO x's.  A type's ops are consulted
; when EITHER operand carries that type, so pushing `*` onto x's str type to
; make `'ab' * 2` work would change what `*` means for every string in the
; process -- the platform's own included.  Python's string operators therefore
; stay in runtime.x behind a `str?` test.  Only PY-LIST and PY-DICT get ops,
; because they are types this bundle invented and nothing else can hold one.
;
; WHAT WAS THERE BEFORE was not "unimplemented", it was WRONG: `[1] + [2]`
; printed 64690751520 and `[1] * 3` printed 96291346800 -- the instance pointer
; read as an integer -- while `[1, 2] == [1, 2]` was False because the compare
; was identity.  A silent wrong number is the failure mode this bundle keeps
; finding, and it is the reason each of these has a spec.

; Set to %py-eq by runtime.x: Python's equality is Python's rule, and the
; elementwise compares below have to use it so that nested containers, and
; `1 == 1.0`, come out right.
(def %py-equal ())

(def %py-list-type (%type-by-atom %py-list))
(def %py-dict-type (%type-by-atom %py-dict))

(def %py-concat
  (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b)))))

; n <= 0 gives the empty list, as in Python.
(def %py-repeat
  (fn (self l n) (if (<= n 0) () (%py-concat l (self l (- n 1))))))

(def %py-seq-eq
  (fn (self a b)
    (if (null? a)
      (null? b)
      (if (null? b)
        #f
        (if (%py-equal (first a) (first b)) (self (rest a) (rest b)) #f)))))

; Lexicographic, as Python compares sequences: the first differing element
; decides, and a proper prefix is the smaller.
(def %py-seq-lt
  (fn (self a b)
    (if (null? a)
      (not (null? b))
      (if (null? b)
        #f
        (if (%py-equal (first a) (first b))
          (self (rest a) (rest b))
          (< (first a) (first b)))))))

; Multiplying a sequence by a non-number is a TypeError in Python, and the
; guard has to name the cases rather than test for "number": the tower's ints,
; bigints and floats are all different types.
(def %py-not-a-count
  (fn (_ n)
    (if (str? n) #t (if (%py-list-is n) #t (%py-dict-is n)))))

(%type-push-op %py-list-type (lit +)
  (fn (_ a b)
    (if (if (%py-list-is a) (%py-list-is b) #f)
      (%py-list-new (%py-concat (rest (first a)) (rest (first b))))
      (Err raise (lit type) "can only concatenate list to list" ()))))

(%type-push-op %py-list-type (lit *)
  (fn (_ a b)
    (let ((l (if (%py-list-is a) a b))
          (n (if (%py-list-is a) b a)))
      (if (%py-not-a-count n)
        (Err raise (lit type) "can't multiply sequence by non-int" ())
        (%py-list-new (%py-repeat (rest (first l)) n))))))

; A list is equal only to a list -- never an error, because Python answers False
; for `[1] == 1` rather than raising.
(%type-push-op %py-list-type (lit =)
  (fn (_ a b)
    (if (if (%py-list-is a) (%py-list-is b) #f)
      (%py-seq-eq (rest (first a)) (rest (first b)))
      #f)))

(%type-push-op %py-list-type (lit <)
  (fn (_ a b)
    (if (if (%py-list-is a) (%py-list-is b) #f)
      (%py-seq-lt (rest (first a)) (rest (first b)))
      (Err raise (lit type) "unorderable types" ()))))

(%type-push-op %py-list-type (lit >)
  (fn (_ a b)
    (if (if (%py-list-is a) (%py-list-is b) #f)
      (%py-seq-lt (rest (first b)) (rest (first a)))
      (Err raise (lit type) "unorderable types" ()))))

; DICT EQUALITY IGNORES ORDER, even though the printed form does not.  Two
; dicts with the same keys and values are equal in Python whatever order they
; were built in, so this walks a's entries and looks each key up in b rather
; than comparing the entry lists pairwise.
(def %py-dfind-in
  (fn (self k es)
    (if (null? es)
      ()
      (if (%py-equal k (first (first es))) (first es) (self k (rest es))))))

(def %py-entries-eq
  (fn (self as bs)
    (if (null? as)
      #t
      (let ((e (%py-dfind-in (first (first as)) bs)))
        (if (null? e)
          #f
          (if (%py-equal (rest (first as)) (rest e)) (self (rest as) bs) #f))))))

(%type-push-op %py-dict-type (lit =)
  (fn (_ a b)
    (if (if (%py-dict-is a) (%py-dict-is b) #f)
      (let ((as (rest (first a))) (bs (rest (first b))))
        (if (= (List length as) (List length bs)) (%py-entries-eq as bs) #f))
      #f)))

; --- PY-CLASS and PY-OBJ -----------------------------------------------------
;
; A CLASS IS CALLABLE, AND THAT IS THE WHOLE TRICK.  Python spells construction
; `Foo()`, which is a call, and x dispatches a call on a value through its
; type's `call` handler.  So a class needs no special form in the parser and no
; check at every call site: `Foo()` is the ordinary call path, arriving at the
; handler below.
;
; The class itself is NOT an x class (x/type/class.x).  That layer is for types
; written in x, resolved when the file loads; Python's classes are values built
; at run time from a parsed body, and their method lookup has to follow Python's
; rules rather than x's.  This is the same reasoning that put Python's lists on
; the type system rather than the class system -- one level lower is the level
; that fits.

(def %py-class ())
(def %py-obj ())

; Set by runtime.x: constructing an instance means running __init__, and what
; that means -- bind the object, pass the arguments, ignore the result -- is
; Python's rule, so it lives with the other Python rules.
(def %py-instantiate ())

; Set by runtime.x: how an instance renders depends on whether it is an
; exception, which is a Python rule and not a property of the type.
(def %py-obj-write ())
; And __call__: an object called like a function.  runtime.x owns the
; dunder protocol, so the type's call handler reaches it through a hook.
(def %py-obj-call ())

; A class is (name base methods qualname) and never mutates, so it needs no
; cell.  The QUALNAME is the display form and nothing else: a user class prints
; <class '__main__.Foo'> and a builtin prints <class 'int'>, and that prefix is
; a fact about where the class came from -- the constructor's caller knows it,
; the class itself cannot compute it, so it travels as a slot.
(def %py-class-new
  (fn (_ name base methods qualname)
    (%make-instance %py-class (list name base methods qualname))))
(def %py-class-is (fn (_ v) (%type? v %py-class)))
(def %py-class-name (fn (_ c) (first (first c))))
(def %py-class-base (fn (_ c) (first (rest (first c)))))
(def %py-class-methods (fn (_ c) (first (rest (rest (first c))))))
(def %py-class-qualname (fn (_ c) (List ref 3 (first c))))

; An instance is a cell: first is its class, rest is its attribute alist.  The
; attributes change -- `self.x = 1` is how Python objects get their fields at
; all -- so the alist hangs off a cell that every reference shares.
(def %py-obj-new (fn (_ cls) (%make-instance %py-obj (pair cls ()))))
(def %py-obj-is (fn (_ v) (%type? v %py-obj)))
(def %py-obj-class (fn (_ o) (first (first o))))
(def %py-obj-attrs (fn (_ o) (rest (first o))))
(def %py-obj-set-attrs! (fn (_ o a) (%seq (%set-rest! (first o) a) ())))

(set! %py-class
  (%make-type
    "PY-CLASS"
    (list
      (pair (lit write)
        (fn (_ self) (display "<class '" (%py-class-qualname self) "'>")))
      (pair (lit call)
        (fn (_ self . args) (%py-instantiate self args))))))

(set! %py-obj
  (%make-type
    "PY-OBJ"
    (list
      ; DIVERGENCE, STATED: Python prints `<__main__.Foo object at 0x7f...>`.
      ; The address is the object's identity and is different on every run, so
      ; reproducing it would make every spec that prints an object unassertable.
      ; The name is kept and the address is dropped.
      ; runtime.x replaces this once it can tell an exception from an ordinary
      ; object -- that distinction is Python's, and it lives with Python's rules.
      (pair (lit write)
        (fn (_ self)
          (if (null? %py-obj-write)
            (display "<" (%py-class-qualname (first (first self))) " object>")
            (%py-obj-write self))))
      (pair (lit call)
        (fn (_ self . args)
          (if (null? %py-obj-call)
            (Err raise (lit type) "object is not callable" ())
            (%py-obj-call self args)))))))

; --- PY-TUPLE ----------------------------------------------------------------
;
; IMMUTABLE, SO NO CELL.  A list needed a cell because `append` has to be
; visible through every reference to it; a tuple has no operation that changes
; it, so the elements sit directly in the payload and the instance IS the value.
;
; An empty tuple is an instance whose payload is nil -- which is exactly why it
; is a type rather than a bare x list.  `()` and None are different values in
; Python and would be the same nil here.

(def %py-tuple ())

; --- PY-BYTES ----------------------------------------------------------------
; MINIMAL, DELIBERATELY: enough that b'1.2' is a value float() can read and
; print() can show.  The payload is the decoded string; indexing, slicing and
; the bytes methods wait until a conformance case asks for them.
(def %py-bytes ())
(def %py-bytes-new (fn (_ s) (%make-instance %py-bytes s)))
(def %py-bytes-is (fn (_ v) (%type? v %py-bytes)))
(def %py-bytes-str (fn (_ v) (first v)))
(set! %py-bytes
  (%make-type
    "PY-BYTES"
    (list
      ; runtime.x owns the escape rules (b'\n', \xhh for anything outside
      ; printable ASCII, the quote choice), the same way str's repr does
      (pair (lit write)
        (fn (_ self) (display (%py-bytes-repr (first self)))))
      (pair (lit length) (fn (_ self) (Str8 length (first self)))))))

; --- PY-GEN ------------------------------------------------------------------
; A generator is its body (a closure taking the generator itself, whose
; `yield`s call %py-yield on it), its name, the two continuations that pass
; control back and forth (runtime.x owns the protocol), and a status.
; The state is a mutable list: (body name k-gen k-caller status).
(def %py-gen ())
(def %py-gen-new (fn (_ body name) (%make-instance %py-gen (list body name () () (lit created)))))
(def %py-gen-is (fn (_ v) (%type? v %py-gen)))
(def %py-gen-state (fn (_ g) (first g)))
(set! %py-gen
  (%make-type
    "PY-GEN"
    (list
      (pair (lit write)
        (fn (_ self) (display "<generator object " (List ref 1 (first self)) ">"))))))

(def %py-tuple-new (fn (_ elems) (%make-instance %py-tuple elems)))
(def %py-tuple-is (fn (_ v) (%type? v %py-tuple)))
(def %py-tuple-elems (fn (_ v) (first v)))

(def %py-tuple-step
  (fn (_ st) (if (null? st) () (pair (first st) (rest st)))))

(set! %py-tuple
  (%make-type
    "PY-TUPLE"
    (list
      ; A ONE-ELEMENT TUPLE PRINTS ITS TRAILING COMMA.  `(1,)` is not
      ; decoration: `(1)` is the number 1 in Python, so the comma is the only
      ; thing that makes the value a tuple, and a repr without it would print
      ; something that reads back as a different value.
      (pair
        (lit write)
        (fn (_ self)
          (display "(")
          (def go
            (fn (recur l sep)
              (if (not (null? l))
                (do
                  (if sep (display ", "))
                  (%py-repr (first l))
                  (recur (rest l) #t)))))
          (go (first self) #f)
          ; The trailing comma goes on a ONE-element tuple only.  `rest` is
          ; reached only when the payload is non-nil: (rest ()) on an empty
          ; tuple is a read of a non-pair, which segfaults rather than raising
          ; (x-engine-c#16), and `()` is the commonest tuple there is.
          (if (null? (first self))
            ()
            (if (null? (rest (first self))) (display ",") ()))
          (display ")")))
      (pair (lit length) (fn (_ self) (List length (first self))))
      (pair
        (lit call)
        (fn (_ self . args)
          (def l (first self))
          (def n (List length l))
          (def i (first args))
          (def k (if (< i 0) (+ n i) i))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "tuple index out of range" ())
            (List ref k l))))
      (pair (lit iter) (fn (_ self) (%i-make %py-tuple-step (first self)))))))

(def %py-tuple-type (%type-by-atom %py-tuple))

(%type-push-op %py-tuple-type (lit +)
  (fn (_ a b)
    (if (if (%py-tuple-is a) (%py-tuple-is b) #f)
      (%py-tuple-new (%py-concat (first a) (first b)))
      (Err raise (lit type) "can only concatenate tuple to tuple" ()))))

(%type-push-op %py-tuple-type (lit *)
  (fn (_ a b)
    (let ((t (if (%py-tuple-is a) a b))
          (n (if (%py-tuple-is a) b a)))
      (if (%py-not-a-count n)
        (Err raise (lit type) "can't multiply sequence by non-int" ())
        (%py-tuple-new (%py-repeat (first t) n))))))

; A tuple is equal only to a tuple.  `(1, 2) == [1, 2]` is False in Python --
; the sequences are the same and the types are not.
(%type-push-op %py-tuple-type (lit =)
  (fn (_ a b)
    (if (if (%py-tuple-is a) (%py-tuple-is b) #f)
      (%py-seq-eq (first a) (first b))
      #f)))

(%type-push-op %py-tuple-type (lit <)
  (fn (_ a b)
    (if (if (%py-tuple-is a) (%py-tuple-is b) #f)
      (%py-seq-lt (first a) (first b))
      (Err raise (lit type) "unorderable types" ()))))

(%type-push-op %py-tuple-type (lit >)
  (fn (_ a b)
    (if (if (%py-tuple-is a) (%py-tuple-is b) #f)
      (%py-seq-lt (first b) (first a))
      (Err raise (lit type) "unorderable types" ()))))

; --- PY-SUPER ----------------------------------------------------------------
;
; `super()` is a PROXY, not a class and not an instance: it holds the class to
; start looking FROM and the object to bind to.  Attribute lookup on it skips
; the class the method was written in and begins at that class's base, which is
; the whole point -- starting from the INSTANCE's class would find the override
; again and recurse until the machine died.
;
; Immutable, so no cell.

(def %py-super-t ())

(def %py-super-new
  (fn (_ from obj) (%make-instance %py-super-t (pair from obj))))
(def %py-super-is (fn (_ v) (%type? v %py-super-t)))
(def %py-super-from (fn (_ v) (first (first v))))
(def %py-super-self (fn (_ v) (rest (first v))))

(set! %py-super-t
  (%make-type
    "PY-SUPER"
    (list
      (pair (lit write) (fn (_ self) (display "<super>"))))))
