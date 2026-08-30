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
  %py-list %py-list-new %py-list-is %py-list-elems %py-list-set! %py-repr)

; Fetch the type prims from the catalog (ns `type` is de-registered, R5).
(def %make-type (prim-ref (lit type) (lit make)))
(def %make-instance (prim-ref (lit type) (lit make-instance)))
(def %type? (prim-ref (lit type) (lit ?)))

; Forward declaration, the way x/num/rational.x forward-declares its reader.
; runtime.x owns Python's repr -- a string prints as 'a' inside a list and as a
; here at the top level -- and this file is loaded first, so the write handler
; reaches it through a hook rather than a load-order assumption.
(def %py-repr ())

(def %py-list ())

; --- The element cell --------------------------------------------------------

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
          (def k (if (< i 0) (+ n i) i))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "list index out of range" ())
            (List ref k l))))
      ; A stepper that answers nil when exhausted, as x/type/vector.x does.
      ; NIL TERMINATES, so a list containing None cannot be walked through this
      ; slot -- Python's None is nil here.  `for` therefore still walks the
      ; element list directly; this is registered for everything else that
      ; iterates, and the caveat is the reason it is not the loop's source.
      (pair
        (lit iter)
        (fn (_ self)
          (def l (rest (first self)))
          (fn (_)
            (if (null? l) ()
              (let ((v (first l)))
                (set! l (rest l))
                v))))))))
