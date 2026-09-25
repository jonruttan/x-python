; # x-python -- Python on x-lang
;
; ## python/runtime-num.x -- arithmetic, the operator protocol, and the numeric builtins
;
; @description Python's operators are not x's, so they get their own names rather
;   than a mapping: the dunder dispatch, the str seams that are not the
;   method table, bitwise over exact two's complement, and membership.
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

; A sweep before each section: this file's load is the second largest
; between two sweeps (117M objects under x-lang 0.14.0 on x86-64), and
; a section boundary is a quiet point.  See python/util.x.
(%py-sweep!)
; --- Arithmetic --------------------------------------------------------------
; `+` dispatches on the operands, and the string case is not an extra: Python
; spells concatenation with it, and every conformance program that builds a
; message uses it.
(%py-sweep!)
; --- The operator protocol ---------------------------------------------------
;
; A USER CLASS TAKES PART IN EVERY OPERATOR through its dunders, and the
; seams below ask for them the way Python does: the left operand's __op__
; first, then the right operand's reflected __rop__, and NotImplemented from
; either means "try the other side".  The check that opens every seam is a
; single %type? call -- no frame, no allocation -- so the common numeric path
; pays nothing for the protocol's existence.
;
; NotImplemented is one unique value; identity is the test, as in Python.
(def %py-NotImplemented (pair (lit %py-NotImplemented) ()))

; ELLIPSIS IS THE OTHER SINGLETON PYTHON SPELLS AS A LITERAL, `...`, and it
; takes the same shape for the same reason: one unique pair, identity the
; test.  Nothing here reads it -- it exists so that a program that passes it
; around, hashes it, or compares it gets the answer Python gives.
(def %py-Ellipsis (pair (lit %py-Ellipsis) ()))

; The bound dunder, or nil.  A method compiles to (fn (_ py-self ...) ...),
; so binding is closing over the object -- the same shape %py-obj-attr uses.
(def %py-dunder
  (fn (_ obj name)
    (let ((m (%py-method-find (%py-obj-class obj) name)))
      (match
        ((null? m) ())
        ; the three built-in descriptors keep their meaning as dunders too
        ((%py-desc-is m)
          (let ((f (%py-desc-fn m)) (k (%py-desc-kind m)))
            (if (eq? k (lit static)) f
              (if (eq? k (lit classmethod)) (%py-bind-method f (%py-obj-class obj))
                (%py-bind-method m obj)))))
        (#t (%py-bind-method m obj))))))

; One side of a binary dispatch: the dunder's answer, or NotImplemented when
; the operand is not an object or has no such method.
(def %py-side
  (fn (_ x y name)
    (if (%py-obj-is x)
      (let ((m (%py-dunder x name)))
        (if (null? m) %py-NotImplemented (m y)))
      %py-NotImplemented)))

(def %py-binop
  (fn (_ a b name rname opname)
    (let ((r1 (%py-side a b name)))
      (if (not (eq? r1 %py-NotImplemented))
        r1
        (let ((r2 (%py-side b a rname)))
          (if (not (eq? r2 %py-NotImplemented))
            r2
            (%py-op-refuse opname a b)))))))

; augmented + on a list is list.extend, which takes any iterable -- while
; plain + demands a list.  Python draws that line and the corpus tests it.
; AUGMENTED ASSIGNMENT IS ITS OWN DUNDER FIRST.  Python tries __iop__, which
; may mutate the object and answer itself, and falls back to the ordinary
; binary op -- `a += b` is `a = a.__add__(b)` only when there is no __iadd__.
; One helper takes the name and the fallback, so every op= gets the same rule
; rather than += alone having it.
(def %py-inplace
  (fn (_ name binop a b)
    (if (%py-obj-is a)
      (let ((m (%py-dunder a name)))
        (if (null? m) (binop a b) (m b)))
      (binop a b))))

(def %py-iadd
  (fn (_ a b)
    (match
      ; a list grows in place from ANY iterable, which is list.extend's rule
      ((%py-list? a)
        (%seq (%py-list-set! a (%py-list-cat (%py-list-elems a) (%py-iter-elems b))) a))
      ; and a deque by its own extend, which keeps its bound
      ((%py-dq-is a) (%seq (%py-dq-extend! a b) a))
      (#t (%py-inplace "__iadd__" %py-add a b)))))

(def %py-isub    (fn (_ a b) (%py-inplace "__isub__" %py-sub a b)))
(def %py-imul    (fn (_ a b) (%py-inplace "__imul__" %py-mul a b)))
(def %py-imatmul (fn (_ a b) (%py-inplace "__imatmul__" %py-matmul a b)))
(def %py-idiv    (fn (_ a b) (%py-inplace "__itruediv__" %py-div a b)))
(def %py-imod    (fn (_ a b) (%py-inplace "__imod__" %py-mod a b)))
(def %py-ibitor  (fn (_ a b) (%py-inplace "__ior__" %py-bitor a b)))
(def %py-ibitand (fn (_ a b) (%py-inplace "__iand__" %py-bitand a b)))
(def %py-ibitxor (fn (_ a b) (%py-inplace "__ixor__" %py-bitxor a b)))
; The three-character forms, once the tokenizer could read them: `//=` `**=`
; `>>=` `<<=` are the same rule, and Python names their dunders after the
; binary op the same way.
(def %py-ifloordiv (fn (_ a b) (%py-inplace "__ifloordiv__" %py-floordiv a b)))
(def %py-ipow      (fn (_ a b) (%py-inplace "__ipow__" %py-pow a b)))
(def %py-ilshift   (fn (_ a b) (%py-inplace "__ilshift__" %py-lshift a b)))
(def %py-irshift   (fn (_ a b) (%py-inplace "__irshift__" %py-rshift a b)))

(def %py-add
  (fn (_ a b)
    (match
      ((%py-plain-nums? a b) (+ a b))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__add__" "__radd__" "+"))
      ((%py-arr-is a) (%py-arr-cat a b))
      ((%py-dq-is a) (%py-dq-cat a b))
      ((match
         ((%py-view-is a) #t)
         ((%py-view-is b) #t)
         ((%py-dict? a) #t)
         (#t (%py-dict? b)))
        (%py-op-refuse "+" a b))
      ((%py-list? a)
        (if (%py-list? b)
          (%py-list-new (%py-list-cat (%py-list-elems a) (%py-list-elems b)))
          (%py-concat-refuse "list" b)))
      ; a tuple concatenates by the + its type carries (python/types.x)
      ((%py-tuple-is a) (if (%py-tuple-is b) (+ a b) (%py-concat-refuse "tuple" b)))
      ((%py-list? b) (%py-op-refuse "+" a b))
      ; THE LEFT OPERAND DECIDES: bytearray + bytes is a bytearray and bytes +
      ; bytearray is a bytes, as in Python -- the buffers concatenate either
      ; way, and only the answer's type is in question.
      ((%py-bytes-is a)
        (match
          ((%py-bytes-is b)
            ((if (%py-barr-is a) %py-barr-new %py-bytes-new)
              (%pb-cat (%py-bytes-list a) (%py-bytes-list b))))
          ; an array is a buffer, and a buffer concatenates onto bytes
          ((%py-arr-is b)
            ((if (%py-barr-is a) %py-barr-new %py-bytes-new)
              (%pb-cat (%py-bytes-list a) (%py-arr-buffer b))))
          (#t (Err raise (lit type) "can't concat to bytes" ()))))
      ((%py-bytes-is b)
        (Err raise (lit type) "can't concat bytes to non-bytes" ()))
      ((%py-str-is a)
        (if (%py-str-is b)
          (%py-str-new (%pb-cat (%py-str-cps a) (%py-str-cps b)))
          (%py-concat-refuse "str" b)))
      ((%py-str-is b) (%py-op-refuse "+" a b))
      ; Bools are ints here too: 1j + True.
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "+" 0))
      ((%py-nums? a b)
        (+ (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b))))
      (#t (%py-op-refuse "+" a b)))))

(def %py-sub
  (fn (_ a b)
    (match
      ((%py-plain-nums? a b) (- a b))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__sub__" "__rsub__" "-"))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-sub a b))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
          (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "-" 1))
      ((%py-nums? a b)
        (- (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b))))
      (#t (%py-op-refuse "-" a b)))))

; THE TYPE HANDLES, EARLY: the arithmetic seams below consult them, and
; %py-f-2p64 is computed through %py-mul at LOAD time -- so these must be
; bound before the first seam runs, not where the constructors that also
; use them happen to live.
(def %py-typeof-prim (prim-ref (lit type) (lit of)))
(def %py-th-int (%py-typeof-prim 1))
(def %py-th-big (%py-typeof-prim 99999999999999999999))
(def %py-th-float (%py-typeof-prim 1.5))
(def %py-th-complex (%py-typeof-prim (Complex make 0.0 1.0)))
(def %py-complex-is
  (fn (_ v) (eq? (%py-typeof-prim v) %py-th-complex)))
(def %py-num-kind
  (fn (_ v)
    (let ((h (%py-typeof-prim v)))
      (match
        ((eq? h %py-th-int) (lit int))
        ((eq? h %py-th-big) (lit int))
        ((eq? h %py-th-float) (lit float))
        ((eq? h %py-th-complex) (lit complex))
        (#t ())))))
; a bool is the int it is
(def %py-num?
  (fn (_ v)
    (match
      ((eq? (%py-typeof-prim v) %py-th-int) #t)
      ((eq? (%py-typeof-prim v) %py-th-float) #t)
      ((eq? (%py-typeof-prim v) %py-th-big) #t)
      ((eq? (%py-typeof-prim v) %py-th-complex) #t)
      ((eq? v #t) #t)
      (#t (eq? v #f)))))

; A number on each side, or Python's TypeError.  Past the numbers the platform's
; operators do not refuse: they answer a word (1 + memoryview(b"")), raise under
; a tag no except clause maps, or crash (1 / None).  So each seam asks before its
; numeric arm, and the refusal names both types as CPython does.
(def %py-nums? (fn (_ a b) (if (%py-num? a) (%py-num? b) #f)))
; A machine int or a float on each side needs none of a seam's other questions,
; and that is most of what a program adds, subtracts, multiplies and orders.
(def %py-plain-nums?
  (fn (_ a b)
    (if (if (eq? (%py-typeof-prim a) %py-th-int) #t
          (eq? (%py-typeof-prim a) %py-th-float))
      (if (eq? (%py-typeof-prim b) %py-th-int) #t
        (eq? (%py-typeof-prim b) %py-th-float))
      #f)))
(def %py-op-refuse
  (fn (_ op a b)
    (Err raise (lit type)
      (Str8 append (Str8 append "unsupported operand type(s) for " op)
        (Str8 append ": " (%py-type-pair a b)))
      ())))
; 'int' and 'NoneType'
(def %py-type-pair
  (fn (_ a b)
    (Str8 append (Str8 append "'" (%py-class-name (%py-type-of a)))
      (Str8 append "' and '" (Str8 append (%py-class-name (%py-type-of b)) "'")))))
; can only concatenate list (not "int") to list
(def %py-concat-refuse
  (fn (_ what b)
    (Err raise (lit type)
      (Str8 append (Str8 append "can only concatenate " what)
        (Str8 append (Str8 append " (not \"" (%py-class-name (%py-type-of b)))
          (Str8 append "\") to " what)))
      ())))
; A sequence repeats by an int, a bool being one; any other count is refused in
; CPython's words.
(def %py-repeat-count
  (fn (_ k)
    (let ((n (%py-boolnorm k)))
      (if (eq? (%py-num-kind n) (lit int))
        n
        (Err raise (lit type)
          (Str8 append "can't multiply sequence by non-int of type '"
            (Str8 append (%py-class-name (%py-type-of k)) "'"))
          ())))))

; THE COMPLEX BRANCH OF THE FOUR SEAMS.  A complex beside a non-number is a
; TypeError here, not the tower's promotion error -- that one is x's
; teaching raise (#584) and its tag is not `type`, so `except TypeError`
; never saw it and 1j + [] killed the program.  And a bigint beside a
; complex is FLOATED first, as Python does, because the tower declares no
; COMPLEX x BIGINT promotion.  Only the complex case pays: the seams reach
; here after two handle compares, and refuse any other non-number themselves.
(def %py-cx-arith
  (fn (_ a0 b0 op code)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (null? (%py-num-kind a)) #t (null? (%py-num-kind b)))
      (%py-op-refuse op a0 b0)
      (do
        (def x (if (eq? (%py-typeof-prim a) %py-th-big) (* 1.0 a) a))
        (def y (if (eq? (%py-typeof-prim b) %py-th-big) (* 1.0 b) b))
        (match
          ((= code 0) (+ x y))
          ((= code 1) (- x y))
          ((= code 2) (* x y))
          (#t (/ x y)))))))

; The shifts: ints only, and >> FLOORS for a negative left operand the way
; Python does -- Num quotient truncates, so the floor is stated.
(def %py-lshift
  (fn (_ a0 b0)
    (if (if (%py-obj-is a0) #t (%py-obj-is b0))
      (%py-binop a0 b0 "__lshift__" "__rlshift__" "<<")
    (%py-lshift-num a0 b0))))
(def %py-lshift-num
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
      (if (< b 0)
        (Err raise (lit value) "negative shift count" ())
        (* a (Num expt 2 b)))
      (%py-op-refuse "<<" a0 b0))))
(def %py-rshift
  (fn (_ a0 b0)
    (if (if (%py-obj-is a0) #t (%py-obj-is b0))
      (%py-binop a0 b0 "__rshift__" "__rrshift__" ">>")
    (%py-rshift-num a0 b0))))
(def %py-rshift-num
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
      (if (< b 0)
        (Err raise (lit value) "negative shift count" ())
        (let ((p (Num expt 2 b)))
          (let ((q (Num quotient a p)))
            (if (if (< a 0) (not (= (* q p) a)) #f) (- q 1) q))))
      (%py-op-refuse ">>" a0 b0))))
; STRING REPETITION IS HANDLED HERE, NOT ON THE TYPE.  A type's ops fire when
; either operand carries the type, so pushing `*` onto x's str type would change
; what `*` means for every string in the process, the platform's included.  The
; containers can have ops because they are types this bundle invented; str is
; not, so its Python rules stay behind a `str?` test.
(def %py-str-repeat
  (fn (_ s n) (%py-str-new (%pb-repeat (%py-str-cps s) n ()))))

(%py-sweep!)
; --- the str seams that are not the method table -----------------------------
;
; PRINTING A NUL WORKS, and the refusal that used to stand here is worth
; remembering rather than just deleting.  The value always carried the byte --
; len, indexing, slicing, comparison and repr all answered for it -- but the
; shared spec harness truncated captured stdout at the first zero byte, so a
; `print` that emitted one could not be pinned by any test, and shipping
; behaviour no spec can hold was the worse of the two trades.
;
; The harness was the fix, and it landed: a captured NUL now reaches the
; comparison as the literal text `<<NUL>>`, so the behaviour is assertable and
; 88-str-nul.spec.md asserts it.  %ps-write is the door -- see "the writer" in
; python/str.x for why print cannot simply `display` a string like everything
; else does.
(def %py-str-display (fn (_ l) (%ps-write l)))

; ONE CHARACTER IS A str OF ONE CODE POINT, which is what iterating a str
; yields -- not an int, the way iterating a bytes does.
(def %py-str-chars-of
  (fn (self l acc)
    (if (null? l) (List reverse acc)
      (self (rest l) (pair (%py-str-new (list (first l))) acc)))))

; A POLYNOMIAL OVER THE CODE POINTS.  The platform's Hash takes a string and
; a str can no longer be handed to it -- and a NUL-bearing key has to hash
; like any other, which is the whole point.  Multiply-and-add rather than
; FNV, because xor would be a bit walk per character here and this is asked
; once per dict subscript.
(def %py-cp-hash
  (fn (self l h)
    (if (null? l) h
      (self (rest l) (% (+ (* h 31) (first l)) 4294967296)))))

; `s % args` -- the formatter still speaks the platform's string, so this is
; its door.  A NUL in the FORMAT would stop it, and says so.
(def %py-format-str
  (fn (_ a b) (%py-str-of-x (%py-format (%ps->x (%py-str-cps a)) b))))

; b"..." % args: the same engine over the template's bytes, answering the type
; the template was -- a bytearray formats to a bytearray.
(def %py-format-bytes
  (fn (_ a b)
    ((if (%py-barr-is a) %py-barr-new %py-bytes-new)
      (%pb-of-str (%py-format (%pb->str (%py-bytes-list a)) b #t)))))

; `a @ b` means nothing here except to an object with __matmul__.
(def %py-matmul
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__matmul__" "__rmatmul__" "@")
      (%py-op-refuse "@" a b))))

(def %py-mul
  (fn (_ a b)
    (match
      ((%py-plain-nums? a b) (* a b))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__mul__" "__rmul__" "*"))
      ((%py-dq-is a) (%py-dq-repeat a b))
      ((%py-dq-is b) (%py-dq-repeat b a))
      ((%py-list? a)
        (%py-list-new (%py-els-repeat (%py-list-elems a) (%py-repeat-count b) ())))
      ((%py-list? b)
        (%py-list-new (%py-els-repeat (%py-list-elems b) (%py-repeat-count a) ())))
      ; a tuple repeats like every other sequence, and a namedtuple's own
      ; __mul__ answers through this arm
      ((%py-tuple-is a)
        (%py-tuple-new (%py-els-repeat (%py-tuple-elems a) (%py-repeat-count b) ())))
      ((%py-tuple-is b)
        (%py-tuple-new (%py-els-repeat (%py-tuple-elems b) (%py-repeat-count a) ())))
      ((%py-bytes-is a)
        ((if (%py-barr-is a) %py-barr-new %py-bytes-new)
          (%pb-repeat (%py-bytes-list a) (%py-repeat-count b) ())))
      ((%py-bytes-is b)
        ((if (%py-barr-is b) %py-barr-new %py-bytes-new)
          (%pb-repeat (%py-bytes-list b) (%py-repeat-count a) ())))
      ((%py-str-is a) (%py-str-repeat a (%py-repeat-count b)))
      ((%py-str-is b) (%py-str-repeat b (%py-repeat-count a)))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "*" 2))
      ((%py-nums? a b)
        (* (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b))))
      (#t (%py-op-refuse "*" a b)))))

; TRUE DIVISION ALWAYS PRODUCES A FLOAT.  `1 / 2` is 0.5 in Python 3 and an
; exact 1/2 in x, and that difference is the reason this bundle declares xenon
; -- float is reachable from the first arithmetic a beginner types.
; DIVISION BY ZERO RAISES.  It answered `inf` for `1 / 0`, `0` for `1 // 0`
; and None for `1 % 0` -- three more silent wrong answers, and the three
; Python spells ZeroDivisionError.  The message is Python's own, the same for
; true and floor division and for modulo.
;
; These raise an Err rather than building an instance, like every other raise
; this runtime makes.  The tag is what `except ZeroDivisionError` matches on;
; see the exception section for why both shapes are caught the same way.
(def %py-div
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__truediv__" "__rtruediv__" "/"))
      ((not (%py-nums? a b)) (%py-op-refuse "/" a0 b0))
      ((= b 0) (Err raise (lit zero-division) "division by zero" ()))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
            (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "/" 3))
      (#t (/ (* a 1.0) b)))))

; FLOOR DIVISION OF FLOATS IS A FLOAT: 1.0 // 2 is 0.0 in Python, floor of
; the true quotient, where Num quotient wants exact operands.
; THE SIGNATURE REGISTRY, EARLY: a builtin registers its parameter names
; at LOAD time (min, max, sorted, enumerate), so these four must be
; defined above the first of them, not with the rest of the keyword
; machinery further down.
(def %py-sigs (pair () ()))
; The record is (name names nreq has-rest kwname kwonly); the last two are
; optional so the builtins that register by hand pass only what they have.
(def %py-sig!
  (fn (_ f name names nreq has-rest . kw)
    (%set-first! %py-sigs
      (pair (pair f (list name names nreq has-rest
                      (%py-nth-or kw 0 ())
                      (%py-nth-or kw 1 ())
                      (%py-nth-or kw 2 ())))
        (first %py-sigs)))
    f))
; A def or a lambda binds as a method when read from an instance; a builtin
; registered by hand does not, as in Python.  The seventh field says which.
(def %py-user-fn?
  (fn (_ f)
    (let ((sig (%py-sig-of f)))
      (if (null? sig) #f (if (> (%py-length sig) 6) (List ref 6 sig) #f)))))

; **kwargs ARRIVES IN A BOX, and it has to: a plain call reaches a function by
; apply, with no keyword machinery in the way, so a dict at the end of the
; argument list would be indistinguishable from an ordinary positional one.
; The box is a pair whose head is this one unique value, which no program can
; produce, so the tail can be read without ambiguity.
(def %py-kwbox-tag (list (lit %py-kwbox)))
(def %py-kwbox (fn (_ d) (pair %py-kwbox-tag d)))
(def %py-kwbox? (fn (_ v) (if (pair? v) (same? (first v) %py-kwbox-tag) #f)))

; The dict a call sent, or an empty one when it sent none -- which is what a
; plain call always looks like.
(def %py-kwargs-of
  (fn (self more)
    (if (null? more)
      (%py-dict-new ())
      (if (null? (rest more))
        (if (%py-kwbox? (first more)) (rest (first more)) (%py-dict-new ()))
        (self (rest more))))))

; The same tail without the box, which is what the positional binders read.
(def %py-args-strip-kw
  (fn (self more)
    (if (null? more)
      ()
      (if (null? (rest more))
        (if (%py-kwbox? (first more)) () more)
        (pair (first more) (self (rest more)))))))
(def %py-dflt (list (lit %py-default)))
(def %py-opt
  (fn (_ more i dflt)
    (if (>= i (%py-length more)) dflt
      (let ((v (List ref i more))) (if (same? v %py-dflt) dflt v)))))

; f() missing N required positional argument(s): 'a' and 'b' -- raised when
; the tail is shorter than the required names, naming the ones not given.
(def %py-need!
  (fn (_ fname more names)
    (let ((given (%py-length (%py-args-strip-kw more))))
      (if (>= given (%py-length names))
        ()
        (%py-missing! fname "positional" (%py-drop-n names given))))))
; f() missing N required keyword-only argument(s): 'b' and 'c'
(def %py-kw-req!
  (fn (_ fname more names)
    (let ((absent (%py-absent-keys names (%py-kwargs-of more) ())))
      (if (null? absent) () (%py-missing! fname "keyword-only" absent)))))
(def %py-missing!
  (fn (_ fname kind names)
    (let ((n (%py-length names)))
      (Err raise (lit type)
        (Str8 append fname
          (Str8 append "() missing "
            (Str8 append (%py-str n)
              (Str8 append (if (= n 1) " required " " required ")
                (Str8 append kind
                  (Str8 append (if (= n 1) " argument: " " arguments: ")
                    (%py-quoted-names names)))))))
        ()))))
; 'a', 'b' and 'c' -- the last joined with "and", as CPython writes them
(def %py-quoted-names
  (fn (self names)
    (let ((q (Str8 append "'" (Str8 append (first names) "'"))))
      (match
        ((null? (rest names)) q)
        ((null? (rest (rest names))) (Str8 append q (Str8 append " and " (self (rest names)))))
        (#t (Str8 append q (Str8 append ", " (self (rest names)))))))))
(def %py-drop-n
  (fn (self l k) (if (= k 0) l (if (null? l) () (self (rest l) (- k 1))))))
(def %py-absent-keys
  (fn (self names d acc)
    (if (null? names) (%py-reverse acc)
      (self (rest names) d
        (if (null? (%py-dfind (%py-str-of-x (first names)) (%py-dict-entries d))) (pair (first names) acc) acc)))))
; A kw-only name's code points, converted once.  The name is read on every
; call of its function, and converting it to a str each time cost more
; objects than the lookup it served.
(def %py-kw-cps-memo (pair () ()))
(def %py-kw-cps
  (fn (_ name)
    (let ((e (%py-alist-find name (first %py-kw-cps-memo))))
      (if (null? e)
        (let ((cps (%ps-of-x name)))
          (%seq (%set-first! %py-kw-cps-memo (pair (pair name cps) (first %py-kw-cps-memo)))
            cps))
        (rest e)))))
; A keyword-only parameter's value, from the box, or its default when the
; call did not name it.  The box's keys are strs; a call that sent no
; keywords is answered before the name is looked at.
(def %py-kwonly
  (fn (_ more name dflt)
    (def go
      (fn (self es cps)
        (if (null? es) dflt
          (if (if (%py-str-is (first (first es)))
                (%pb-eq? (%py-str-cps (first (first es))) cps) #f)
            (rest (first es))
            (self (rest es) cps)))))
    (let ((es (%py-dict-entries (%py-kwargs-of more))))
      (if (null? es) dflt (go es (%py-kw-cps name))))))
; The **kwargs dict without the keyword-only names, which were bound by name.
(def %py-kwargs-minus
  (fn (_ d names)
    (%py-dict-new (%py-rows-minus (%py-dict-entries d) names ()))))
(def %py-rows-minus
  (fn (self rows names acc)
    (if (null? rows) (%py-reverse acc)
      (self (rest rows) names
        (if (%py-name-in? (first (first rows)) names) acc (pair (first rows) acc))))))
(def %py-name-in?
  (fn (self k names)
    (if (null? names) #f
      (if (%pb-eq? (%py-str-cps k) (%ps-of-x (first names))) #t (self k (rest names))))))
(def %py-floordiv
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__floordiv__" "__rfloordiv__" "//"))
      ((not (%py-nums? a b)) (%py-op-refuse "//" a0 b0))
      ((= b 0)
        (Err raise (lit zero-division) "division by zero" ()))
      ((if (%py-complex-is a) #t (%py-complex-is b))
        (Err raise (lit type) "can't take floor of complex number." ()))
      ((if (%py-float-is a) #t (%py-float-is b))
        (Float floor (/ (* a 1.0) b)))
      ; PYTHON FLOORS, `Num quotient` TRUNCATES: -7 // 2 is -4, not -3.
      ; TRUNCATE THEN ADJUST, rather than subtracting a modulo: for a
      ; non-negative numerator this is EXACTLY `Num quotient`, the value
      ; and the representation callers had before floors were fixed.  The
      ; subtracting form handed back a bigint zero under the promoting
      ; lane, and python/format.x's digit loop tests its counter with
      ; eq?, so base conversion span forever and took the CI host with it.
      (#t
        (let ((q (Num quotient a b)))
          (if (if (not (= (- a (* q b)) 0))
                (if (< (- a (* q b)) 0) (> b 0) (< b 0))
                #f)
            (- q 1)
            q))))))
; A STRING ON THE LEFT OF % IS FORMATTING, not arithmetic -- str.__mod__ --
; and the check comes before the zero test because the right operand of a
; format is a tuple as often as a number.
(def %py-mod
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    ; str.__mod__ answers first: "%d" % obj formats the object, it does not
    ; ask the object for __rmod__
    (match
      ((%py-str-is a) (%py-format-str a b0))
      ((%py-bytes-is a) (%py-format-bytes a b0))
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__mod__" "__rmod__" "%"))
      ((not (%py-nums? a b)) (%py-op-refuse "%" a0 b0))
      ((if (%py-complex-is a) #t (%py-complex-is b))
        (Err raise (lit type) "can't mod complex numbers." ()))
      ((= b 0) (Err raise (lit zero-division) "division by zero" ()))
      (#t (Num modulo a b)))))
; NEVER HAND Num expt A NEGATIVE EXPONENT.  Its parameter is documented
; "Non-negative integer exponent" and nothing enforces it: with exp < 0 the
; recursion never reaches 0 and SQUARES THE BASE on every even step, so it
; allocates exponentially growing bignums until the machine dies.  Not a hang --
; an unbounded-allocation bomb, and `2 ** -1` is ordinary Python.
;
; Python's answer is a float: 2 ** -1 is 0.5.
; A FLOAT ANYWHERE MAKES IT libm's pow: Num expt squares its way through
; integer exponents and has no answer for 2 ** 0.5, inf or nan.  Python's
; one refusal on this path is 0.0 to a negative power.
; pow(a, b, m): modular exponentiation by squaring, with Python's sign rule
; (the result takes the modulus's sign).
(def %py-powmod
  (fn (_ a b m)
    (if (= m 0)
      (Err raise (lit value) "pow() 3rd argument cannot be 0" ())
      (if (< b 0)
        (Err raise (lit value) "base is not invertible for the given modulus" ())
        (do
          (def go
            (fn (self base e acc)
              (if (= e 0) acc
                (self (Num modulo (* base base) m) (Num quotient e 2)
                  (if (= (Num modulo e 2) 1) (Num modulo (* acc base) m) acc)))))
          (go (Num modulo a m) b (Num modulo 1 m)))))))
(def %py-pow3
  (fn (_ a b . m)
    ; `pow(x, y, None)` IS `pow(x, y)` -- Python says so, and the modulus
    ; arrives here as () either way, so an absent one and an explicit None
    ; are the same question.
    (if (if (null? m) #t (null? (first m)))
      (%py-pow a b)
      (if (if (%py-num? a) (if (%py-num? b) (%py-num? (first m)) #f) #f)
        (%py-powmod (%py-boolnorm a) (%py-boolnorm b) (%py-boolnorm (first m)))
        (Err raise (lit type) "pow() requires integers" ())))))

(def %py-pow
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__pow__" "__rpow__" "** or pow()"))
      ((not (%py-nums? a b)) (%py-op-refuse "** or pow()" a0 b0))
      ((if (%py-complex-is a) #t (%py-complex-is b))
        (%py-cpow (%py-complex-of a) (%py-complex-of b)))
      ; a negative real base to a fractional power is a COMPLEX in Python 3;
      ; an infinite or NaN exponent is libm's, below
      ((if (< (if (eq? a #t) 1 (if (eq? a #f) 0 a)) 0)
          (if (%py-float-is b)
            (if (Float finite? b) (not (= b (Float floor b))) #f)
            #f)
          #f)
        (%py-cpow (%py-complex-of a) (%py-complex-of b)))
      ((if (%py-float-is a) #t (%py-float-is b))
        (do
          (def fa (* (%py-boolnorm a) 1.0))
          (def fb (* (%py-boolnorm b) 1.0))
          ; zero to -inf is inf, which libm answers
          (if (if (= fa 0.0) (if (< fb 0.0) (Float finite? fb) #f) #f)
            (Err raise (lit zero-division) "zero to a negative power" ())
            (Float pow fa fb))))
      ((< b 0)
        (if (= a 0)
          (Err raise (lit zero-division) "zero to a negative power" ())
          (/ 1.0 (Num expt a (- 0 b)))))
      ; a base of 0, 1 or -1 is answered without raising it to anything,
      ; which is what lets 0 ** (1 << 65) finish
      ((%py-pow-unit? a)
        (let ((x (%py-boolnorm a)) (e (%py-boolnorm b)))
          (match
            ((= x 1) 1)
            ((= x 0) (if (= e 0) 1 0))
            (#t (if (= (Num modulo e 2) 0) 1 (- 0 1))))))
      (#t (Num expt a b)))))
(def %py-pow-unit?
  (fn (_ v)
    (let ((x (%py-boolnorm v)))
      (if (eq? (%py-num-kind x) (lit int))
        (if (= x 0) #t (if (= x 1) #t (= x (- 0 1))))
        #f))))
; A bool negates as the int it is, and a value that is no number is refused, as
; unary + and ~ below already had it.
(def %py-neg
  (fn (_ a)
    (if (%py-obj-is a)
      (let ((m (%py-dunder a "__neg__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary -" ()) (m)))
      (let ((w (%py-boolnorm a)))
        (if (null? (%py-num-kind w))
          (Err raise (lit type) "bad operand type for unary -" ())
          (- 0 w))))))

; Unary + is a no-op on numbers and a TypeError on everything else; unary ~
; is exact two's complement on integers and a TypeError on floats -- both
; measured refusals in the conformance corpus, not decorations.
(def %py-pos
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__pos__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary +" ()) (m)))
    (let ((w (%py-boolnorm v)))
      (if (null? (%py-num-kind w))
        (Err raise (lit type) "bad operand type for unary +" ())
        w)))))

(def %py-invert
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__invert__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary ~" ()) (m)))
    (let ((w (%py-boolnorm v)))
      (if (eq? (%py-num-kind w) (lit int))
        (- (- 0 w) 1)
        (Err raise (lit type) "bad operand type for unary ~" ()))))))

; True is 1 and False is 0 wherever a number is wanted: comparisons,
; arithmetic seams, formatting.  Python's bool IS an int; x's is not.
(def %py-boolnorm
  (fn (_ v) (if (eq? v #t) 1 (if (eq? v #f) 0 v))))

(%py-sweep!)
; --- Bitwise, exact two's complement -----------------------------------------
; Forty-eight bits at a time.  An operand's low chunk is its floor remainder
; by 2^48 -- for a negative operand, its two's complement low bits -- and the
; operand then shifts down by an exact division, so a negative one settles
; on -1 and a non-negative one on 0.  The walk stops when both have; the
; infinite tail of ones a -1 stands for contributes -2^k when the operator
; keeps its bit.  Two chunks combine a nibble at a time through a 256-entry
; table built once, with fixnum arithmetic throughout; a bit at a time on
; the bigints themselves cost some 200,000 objects per bit.
(def %py-chunk 281474976710656)

; The four bits of each nibble value, least significant first.
(def %py-nib-bits
  (fn (_ v)
    (list (= (% v 2) 1) (= (% (Num quotient v 2) 2) 1)
          (= (% (Num quotient v 4) 2) 1) (= (% (Num quotient v 8) 2) 1))))
(def %py-nib-bit-lists
  (fn (self i acc) (if (< i 0) acc (self (- i 1) (pair (%py-nib-bits i) acc)))))
(def %py-nibs (%py-nib-bit-lists 15 ()))

; The 256-entry table of an operator over two nibbles, entry a*16+b.
(def %py-nib-table
  (fn (_ fbit)
    (def entry
      (fn (_ ba bb)
        (+ (if (fbit (List ref 0 ba) (List ref 0 bb)) 1 0)
          (+ (if (fbit (List ref 1 ba) (List ref 1 bb)) 2 0)
            (+ (if (fbit (List ref 2 ba) (List ref 2 bb)) 4 0)
              (if (fbit (List ref 3 ba) (List ref 3 bb)) 8 0))))))
    (def go
      (fn (self i acc)
        (if (< i 0) acc
          (self (- i 1)
            (pair (entry (List ref (Num quotient i 16) %py-nibs) (List ref (% i 16) %py-nibs))
              acc)))))
    (go 255 ())))
(def %py-nib-and (%py-nib-table (fn (_ x y) (if x y #f))))
(def %py-nib-or  (%py-nib-table (fn (_ x y) (if x #t y))))
(def %py-nib-xor (%py-nib-table (fn (_ x y) (if x (not y) y))))

; Two 48-bit chunks through the table, a nibble at a time.
(def %py-nib-combine
  (fn (_ tbl x y)
    (def go
      (fn (self x y k pow acc)
        (if (eq? k 0) acc
          (self (Num quotient x 16) (Num quotient y 16) (- k 1) (* pow 16)
            (+ acc (* pow (List ref (+ (* (% x 16) 16) (% y 16)) tbl)))))))
    (go x y 12 1 0)))

; The low chunk and the rest of v: (low . rest), through the truncating
; quotient and a sign fix, so a negative v never reaches a modulo.
(def %py-bit-split
  (fn (_ v)
    (let ((q (Num quotient v %py-chunk)))
      (let ((r (- v (* q %py-chunk))))
        (if (< r 0) (pair (+ r %py-chunk) (- q 1)) (pair r q))))))

(def %py-bit2
  (fn (_ a0 b0 opname tbl fbit)
    (def a (%py-boolnorm a0))
    (def b (%py-boolnorm b0))
    (if (if (eq? (%py-num-kind a) (lit int)) (eq? (%py-num-kind b) (lit int)) #f)
      (do
        (def tail? (fn (_ v) (if (= v 0) #t (= v (- 0 1)))))
        (def go
          (fn (self a b pow acc)
            (if (if (tail? a) (tail? b) #f)
              (if (fbit (< a 0) (< b 0)) (- acc pow) acc)
              (let ((sa (%py-bit-split a)) (sb (%py-bit-split b)))
                (self (rest sa) (rest sb) (* pow %py-chunk)
                  (+ acc (* pow (%py-nib-combine tbl (first sa) (first sb)))))))))
        ; two bools answer a bool, as in Python
        (let ((r (go a b 1 0)))
          (if (if (if (eq? a0 #t) #t (eq? a0 #f)) (if (eq? b0 #t) #t (eq? b0 #f)) #f)
            (= r 1)
            r)))
      (%py-op-refuse opname a0 b0))))

(def %py-bitor
  (fn (_ a b)
    (match
      ((if (%py-dict? a) (%py-dict? b) #f)
        (let ((d (%py-dict-new (%py-dict-copy (%py-dict-entries a)))))
          (%seq (%py-dict-merge! d b) d)))
      ; an instance before a set, so a set subclass instance beside a set is
      ; asked through its class
      ((if (%py-obj-is a) #t (%py-obj-is b))
        (%py-binop a b "__or__" "__ror__" "|"))
      ((if (%py-set-is a) #t (%py-set-is b)) (%py-set-or a b))
      (#t (%py-bit2 a b "|" %py-nib-or (fn (_ x y) (if x #t y)))))))
(def %py-bitxor
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__xor__" "__rxor__" "^")
    (if (if (%py-set-is a) #t (%py-set-is b))
      (%py-set-xor a b)
      (%py-bit2 a b "^" %py-nib-xor (fn (_ x y) (if x (not y) y)))))))
(def %py-bitand
  (fn (_ a b)
    (if (if (%py-obj-is a) #t (%py-obj-is b))
      (%py-binop a b "__and__" "__rand__" "&")
    (if (if (%py-set-is a) #t (%py-set-is b))
      (%py-set-and a b)
      (%py-bit2 a b "&" %py-nib-and (fn (_ x y) (if x y #f)))))))

(%py-sweep!)
; --- Membership --------------------------------------------------------------
; `a in b`: substring for strings, element walk with Python's equality for
; the containers, keys for a dict, and a TypeError for anything that cannot
; be iterated -- 1.2 in 3.4 must refuse, not loop.
(def %py-in-walk
  (fn (self a l)
    (if (null? l) #f (if (%py-eq a (first l)) #t (self a (rest l))))))

; An iterator is read up to the first equal item and no further, as in
; CPython: `2 in gen` leaves the rest of gen unread.
(def %py-in-pull
  (fn (self a src)
    (def v (%py-iter-pull! src))
    (match
      ((same? v %py-gen-done) #f)
      ((%py-eq a v) #t)
      (#t (self a src)))))

; argument of type 'int' is not a container or iterable
(def %py-in-refusal
  (fn (_ v)
    (Str8 append "argument of type '"
      (Str8 append (%py-type-name v) "' is not a container or iterable"))))

(def %py-in
  (fn (_ a b)
    (match
      ((%py-obj-is b)
        (let ((m (%py-dunder b "__contains__")))
          (if (null? m)
            (%py-in-pull a (%py-iter-open b (%py-in-refusal b)))
            (%py-truthy (m a)))))
      ((%py-arr-is b) (%py-in-walk a (%py-arr-el b)))
      ((%py-dq-is b) (%py-in-walk a (%py-dq-el b)))
      ((%py-bytes-is b)
        (if (%py-bytes-is a)
          (%pb-in? (%py-bytes-list a) (%py-bytes-list b))
          ; AN INT IN A BYTES IS A BYTE VALUE, not a type error: bytes are a
          ; sequence OF ints in Python, so `0 in b"1234"` asks whether any byte
          ; is zero and answers False rather than refusing.
          (if (eq? (%py-num-kind (%py-boolnorm a)) (lit int))
            (%py-in-walk (%py-boolnorm a) (%py-bytes-list b))
            (if (%py-arr-is a)
              (%pb-in? (%py-arr-buffer a) (%py-bytes-list b))
              (Err raise (lit type)
                (Str8 append "a bytes-like object is required, not '"
                  (Str8 append (%py-type-name a) "'")) ())))))
      ((%py-str-is b)
        (if (%py-str-is a)
          (%pb-in? (%py-str-cps a) (%py-str-cps b))
          (Err raise (lit type)
            (Str8 append "'in <string>' requires string as left operand, not "
              (%py-type-name a)) ())))
      ((%py-set-is b) (%py-set-has? a (%py-set-elems b)))
      ((%py-list? b) (%py-in-walk a (%py-list-elems b)))
      ((%py-tuple-is b) (%py-in-walk a (%py-tuple-elems b)))
      ((%py-dict? b)
        (do
          (def keys
            (fn (self es acc)
              (if (null? es) acc (self (rest es) (pair (first (first es)) acc)))))
          (%py-in-walk a (keys (%py-dict-entries b) ()))))
      ((%py-range-is b) (%py-range-has? b a))
      ((if (%py-gen-is b) #t (%py-it-is b)) (%py-in-pull a b))
      ((%py-view-is b) (%py-in-walk a (%py-view-elems b)))
      (#t (%py-in-pull a (%py-iter-open b (%py-in-refusal b)))))))

(%py-sweep!)
; --- Numeric builtins --------------------------------------------------------
; abs clears the SIGN BIT for floats (the arithmetic spelling turns -0.0
; into itself); round is the exact-digit machinery at a decimal place, half
; to even, int result without ndigits and float with.
(def %py-abs
  (fn (_ v0)
    (if (%py-obj-is v0)
      (let ((m (%py-dunder v0 "__abs__")))
        (if (null? m) (Err raise (lit type) "bad operand type for abs()" ()) (m)))
    (%py-abs-num v0))))
(def %py-abs-num
  (fn (_ v0)
    (def v (%py-boolnorm v0))
    (match
      ((%py-float-is v) (if (< (first v) 0) (- 0.0 v) v))
      ((%py-complex-is v) (Complex magnitude v))
      ((eq? (%py-num-kind v) (lit int)) (if (< v 0) (- 0 v) v))
      (#t (Err raise (lit type) "bad operand type for abs()" ())))))

; rounding an int to a negative number of digits: half goes to EVEN, so
; round(125, -1) is 120 and round(15, -1) is 20
(def %py-round-int
  (fn (_ v nd)
    (def p (%py-ipow10 (- 0 nd) 1))
    (def q (Num quotient (- v (Num modulo v p)) p))
    (def rr (Num modulo v p))
    (match
      ((> (* rr 2) p) (* (+ q 1) p))
      ((< (* rr 2) p) (* q p))
      ((= (Num modulo q 2) 0) (* q p))
      (#t (* (+ q 1) p)))))
(def %py-ipow10
  (fn (self n acc) (if (= n 0) acc (self (- n 1) (* acc 10)))))

; A float to a negative number of places, P: its exact digits D (the first
; one at 10^X10) rounded half to even at the 10^-P place, zeros after --
; round(1234.56, -2) is 1200.0, round(150.0, -2) 200.0, round(50.0, -2) 0.0.
; A value whose first digit is at that place rounds against a leading zero;
; one wholly below it is a zero of its sign, however far the place.
(def %py-round-places
  (fn (_ sgn D x10 p)
    (def keep (+ (+ x10 1) p))
    (if (< keep 0)
      (Float from (Str8 append sgn "0"))
      (do
        (def z (if (= keep 0) 1 0))
        (def k (+ keep z))
        (def R0 (%py-f-round (Str8 append (%py-fmt-zeros z) D) k))
        (def R
          (if (< (Str8 length R0) k) (Str8 append R0 (%py-fmt-zeros (- k (Str8 length R0)))) R0))
        (Float from (Str8 append sgn (Str8 append R (%py-fmt-zeros (- 0 p)))))))))

; round() of an infinity or a NaN: to an int it is refused as CPython refuses
; the conversion, and to places it is the value itself
(def %py-round-special
  (fn (_ v ex nd)
    (match
      ((not (null? nd)) v)
      ((eq? (first ex) (lit inf))
        (Err raise (lit overflow) "cannot convert float infinity to integer" ()))
      (#t (Err raise (lit value) "cannot convert float NaN to integer" ())))))

(def %py-round
  (fn (_ . a)
    (if (null? a)
      (Err raise (lit type) "round() missing required argument 'number' (pos 1)" ())
      ())
    (if (> (%py-length a) 2)
      (Err raise (lit type)
        (Str8 append "round() takes at most 2 arguments ("
          (Str8 append (%py-str (%py-length a)) " given)")) ())
      ())
    (def v (%py-boolnorm (first a)))
    (def nd (if (null? (rest a)) () (first (rest a))))
    (if (not (%py-float-is v))
      (if (eq? (%py-num-kind v) (lit int))
        (if (if (null? nd) #f (< (%py-boolnorm nd) 0))
          (%py-round-int v (%py-boolnorm nd))
          v)
        (Err raise (lit type) "type cannot be rounded" ()))
      (do
        (def ex (%py-f-exact v))
        (if (not (eq? (first ex) (lit num)))
          (%py-round-special v ex nd)
          (do
            (def sgn (first (rest ex)))
            (def D (first (rest (rest ex))))
            (def x10 (first (rest (rest (rest ex)))))
            (def p (if (null? nd) 0 nd))
            (if (< p 0)
              (%py-round-places sgn D x10 p)
              (let ((f (%py-fmt-fixed D x10 p)))
                (if (null? nd)
                  (let ((n (%py-int-of-str (first f))))
                    (if (Str8 =? sgn "-") (- 0 n) n)
                  )
                  (Float from
                    (Str8 append sgn
                      (if (= p 0)
                        (first f)
                        (Str8 append (first f)
                          (Str8 append "." (rest f)))))))))))))))

(def %py-minmax
  (fn (_ vs pick which)
    (if (null? vs)
      (Err raise (lit value)
        (Str8 append which "() arg is an empty sequence") ())
      (do
        (def go
          (fn (self best l)
            (if (null? l)
              best
              (self (if (pick (first l) best) (first l) best) (rest l)))))
        (go (first vs) (rest vs))))))

; min/max take either several values or one iterable, plus key= and
; default= as keywords -- and a keyword call is recognisable because
; %py-kw-args pads its slots with the %py-dflt sentinel, which no user
; value can be.
(def %py-has-dflt?
  (fn (self l) (if (null? l) #f (if (same? (first l) %py-dflt) #t (self (rest l))))))
(def %py-minmax-call
  (fn (_ a which pick)
    (def key ())
    (def dflt %py-dflt)
    (def vs (if (null? (rest a)) (%py-iter-elems (first a)) a))
    (if (null? vs)
      (if (same? dflt %py-dflt)
        (Err raise (lit value) (Str8 append which "() arg is an empty sequence") ())
        dflt)
      (let ((k (if (null? key) %py-ident key)))
        (%py-minmax-by vs pick k)))))
(def %py-minmax-by
  (fn (_ vs pick key)
    (def go
      (fn (self best bk l)
        (if (null? l) best
          (let ((v (first l)))
            (let ((vk (key v)))
              (if (%py-truthy (pick vk bk)) (self v vk (rest l)) (self best bk (rest l))))))))
    (go (first vs) (key (first vs)) (rest vs))))
(def %py-min (fn (_ . a) (%py-minmax-call a "min" (fn (_ x y) (%py-lt x y)))))
(def %py-max (fn (_ . a) (%py-minmax-call a "max" (fn (_ x y) (%py-gt x y)))))
; the keyword form: every positional is a VALUE (or the one iterable), and
; key=/default= come from the keywords
(def %py-minmax-kw
  (fn (_ f pos kws)
    (def which (if (same? f %py-min) "min" "max"))
    (def pick (if (same? f %py-min) (fn (_ x y) (%py-lt x y)) (fn (_ x y) (%py-gt x y))))
    (def key (let ((e (%py-alist-find "key" kws))) (if (null? e) () (rest e))))
    (def dflt (let ((e (%py-alist-find "default" kws))) (if (null? e) %py-dflt (rest e))))
    (def vs (if (null? (rest pos)) (%py-iter-elems (first pos)) pos))
    (if (null? vs)
      (if (same? dflt %py-dflt)
        (Err raise (lit value) (Str8 append which "() arg is an empty sequence") ())
        dflt)
      (%py-minmax-by vs pick (if (null? key) %py-ident key)))))

(%py-sweep!)
; --- Bytes seams -------------------------------------------------------------
(def %py-mkbytes (fn (_ s) (%py-bytes-of-str s)))

; b'...' with Python's escapes: the quote rule of str's repr, \n \r \t by
; name, and every byte outside printable ASCII as \xhh -- which is how a NUL
; shows itself now that one can be here at all: b'\x00'.
(def %py-bytes-repr
  (fn (_ l)
    (let ((q (if (if (%pb-in? (list 39) l) (not (%pb-in? (list 34) l)) #f) 34 39)))
      (Str8 append "b"
        (let ((qs (%py-list->string (list (%py-int->char q)))))
          (Str8 append qs (Str8 append (%py-bytes-repr-go l q "") qs)))))))
(def %py-bytes-repr-go
  (fn (self l q acc)
    (if (null? l) acc
      (let ((c (first l)))
        (self (rest l) q
          (Str8 append acc
            (match
              ((= c 92) "\\\\")
              ((= c q) (Str8 append "\\" (%py-list->string (list (%py-int->char c)))))
              ((= c 10) "\\n")
              ((= c 13) "\\r")
              ((= c 9) "\\t")
              ((if (< c 32) #t (>= c 127)) (Str8 append "\\x" (%py-hex2 c)))
              (#t (%py-list->string (list (%py-int->char c)))))))))))

; BYTES METHODS ARE THE BYTE ALGORITHMS, in python/bytes.x.  They used to be
; the str methods on the underlying string, which is what made a NUL fatal:
; the payload had to be something Str8 would hold.  Now the payload is a byte
; list and these are the doors onto it.
;
; An argument is taken as BYTES whichever way it was written -- bytes or
; bytearray -- and a str argument is Python's TypeError, as it was.
(def %py-b-arg
  (fn (_ a)
    (match
      ((%py-bytes-is a) (%py-bytes-list a))
      ((%py-str-is a) (Err raise (lit type) "a bytes-like object is required, not 'str'" ()))
      (#t (Err raise (lit type) "a bytes-like object is required" ())))))

; A NEEDLE MAY BE ONE BYTE WRITTEN AS AN INT.  `b"abc".find(ord("b"))` is
; Python, and only the searching methods take it -- replace and partition
; want a bytes-like and say so.  Reaching %pb-at? with a bare int used to
; walk `first` into a non-pair, which on this engine is a SEGFAULT and took
; the whole spec file with it rather than one case.
(def %py-b-needle
  (fn (_ v)
    (if (%py-num? v)
      (let ((n (%py-boolnorm v)))
        (if (if (< n 0) #t (> n 255))
          (Err raise (lit value) "byte must be in range(0, 256)" ())
          (list n)))
      (%py-b-arg v))))

; start and end, counted from the end when negative and clamped to the value
; -- the slice rules, which is what Python's find/index/count take.
; True is 1 as an index, as it is everywhere else in Python -- and reaching
; `<` with a bare bool is a type error on this engine rather than a coercion.
(def %py-b-clamp
  (fn (_ i0 n)
    (let ((i (%py-boolnorm i0)))
      (let ((k (if (< i 0) (+ n i) i)))
        (if (< k 0) 0 (if (> k n) n k))))))
(def %py-b-start
  (fn (_ l a i)
    (let ((v (%py-b-opt a i ()))) (if (null? v) 0 (%py-b-clamp v (%pb-len l))))))
(def %py-b-end
  (fn (_ l a i)
    (let ((v (%py-b-opt a i ()))) (if (null? v) (%pb-len l) (%py-b-clamp v (%pb-len l))))))

; A SEARCH IS A SEARCH OF THE WINDOW, and the answer is an index into the
; whole -- so the window's start goes back on before it is returned.
(def %py-b-search
  (fn (_ l a rev)
    (let ((s (%py-b-start l a 1)))
      (let ((e (%py-b-end l a 2)))
        (let ((w (%pb-sub l s (- e s))) (n (%py-b-needle (first a))))
          (let ((r (if rev (%pb-rfind w n) (%pb-find w n))))
            (if (< r 0) r (+ r s))))))))
(def %py-b-args
  (fn (self args) (if (null? args) () (pair (%py-b-arg (first args)) (self (rest args))))))
(def %py-b-opt
  (fn (_ args i d)
    (let ((v (%py-nth-or args i ()))) (if (null? v) d v))))
(def %py-nth-or
  (fn (self l i d)
    (if (null? l) d (if (= i 0) (first l) (self (rest l) (- i 1) d)))))

; The parts of a split, wrapped back into the caller's own type.
(def %py-b-parts
  (fn (self mk ps acc)
    (if (null? ps) (%py-list-new (List reverse acc))
      (self mk (rest ps) (pair (mk (first ps)) acc)))))
(def %py-b-triple
  (fn (_ mk t) (%py-tuple-new (list (mk (first t)) (mk (first (rest t))) (mk (first (rest (rest t))))))))

; ONE TABLE, and `mk` is the only thing bytes and bytearray disagree about:
; which of the two a method's answer is made into.
;
; EACH ARM ANSWERS A CLOSURE, so the NAME is resolved when it is asked for
; and not when it is called.  That is what makes `bytes.nosuch` an
; AttributeError at the dot -- which is the shape %py-str-attr already had,
; and which five conformance programs probe with a bare `bytes.count`.
; An encoding or errors argument: the platform string the codec names it by.
; A call that left it out, or a constructor carrying %py-dflt for it, takes the
; default instead.
(def %py-codec-name
  (fn (_ v dflt)
    (match
      ((null? v) dflt)
      ((same? v %py-dflt) dflt)
      (#t
        (let ((s (%py-native-of v)))
          (if (%py-str-is s)
            (%ps->x (%py-str-cps s))
            (Err raise (lit type) "encoding and errors must be str" ())))))))

(def %py-codec-arg
  (fn (self a i dflt)
    (match
      ((null? a) dflt)
      ((> i 0) (self (rest a) (- i 1) dflt))
      (#t (%py-codec-name (first a) dflt)))))

; startswith and endswith over the window from start to end, which nothing fits
; when the end is before the start -- the rule %py-s-affix states for str.
(def %py-b-affix
  (fn (_ l a test)
    (let ((s (%py-b-start l a 1)) (e (%py-b-end l a 2)))
      (let ((n (%py-b-arg (first a))))
        (if (< e s) #f (test (%pb-sub l s (- e s)) n))))))

; A bytes a strip left whole IS the answer, as CPython has it -- `s.strip() is s`
; -- since nothing can tell a copy from it but its identity; a bytearray is
; mutable, so it always answers a new one.
(def %py-b-kept
  (fn (_ v mk l r)
    (if (if (%py-barr-is v) #f (= (%pb-len r) (%pb-len l))) v (mk r))))

(%py-sweep!)
; --- hex and fromhex ---------------------------------------------------------
;
; x.hex(sep, bytes_per_sep): two digits a byte, and one separator character
; between groups of that many bytes -- counted from the right, or from the left
; when the count is negative, and not at all when it is zero, which is CPython's
; rule.  The answer is built as code points, so it never becomes a platform
; string on the way.
(def %py-hex-code (fn (_ d) (if (< d 10) (+ 48 d) (+ 87 d))))

(def %py-hex-sep
  (fn (_ a)
    (if (if (null? a) #t (null? (first a)))
      ()
      (let ((s (%py-native-of (first a))))
        (let ((cs (match
                    ((%py-str-is s) (%py-str-cps s))
                    ((%py-bytes-is s) (%py-bytes-list s))
                    (#t (%py-no-len s)))))
          (match
            ((not (= (%py-length cs) 1))
              (Err raise (lit value) "sep must be length 1." ()))
            ((> (first cs) 127) (Err raise (lit value) "sep must be ASCII." ()))
            (#t (first cs))))))))

; Does the separator go before byte i of n, in groups of k?
(def %py-hex-cut?
  (fn (_ i n k)
    (match
      ((= i 0) #f)
      ((= k 0) #f)
      ((> k 0) (= 0 (% (- n i) k)))
      (#t (= 0 (% i (- 0 k)))))))

(def %py-hex-walk
  (fn (self l i n k sep acc)
    (if (null? l)
      (List reverse acc)
      (let ((acc2 (if (if (null? sep) #f (%py-hex-cut? i n k)) (pair sep acc) acc)))
        (self (rest l) (+ i 1) n k sep
          (pair (%py-hex-code (% (first l) 16))
            (pair (%py-hex-code (Num quotient (first l) 16)) acc2)))))))

(def %py-bytes-hex
  (fn (_ l a)
    (%py-str-new (%py-hex-walk l 0 (%pb-len l) (%py-b-opt a 1 1) (%py-hex-sep a) ()))))

; bytes.fromhex(s): a pair of digits a byte, with whitespace allowed BETWEEN
; pairs and nowhere else.  CPython names the position of the first character
; that is not a digit where one was due, and says so differently when the
; string simply ran out in the middle of a pair.
(def %py-hex-space?
  (fn (_ c)
    (match ((= c 32) #t) ((= c 9) #t) ((= c 10) #t) ((= c 13) #t) ((= c 11) #t) (#t (= c 12)))))

(def %py-fromhex-bad!
  (fn (_ i)
    (Err raise (lit value)
      (Str8 append "non-hexadecimal number found in fromhex() arg at position " (%py-str i))
      ())))

(def %py-fromhex-walk
  (fn (self cs i acc)
    (match
      ((null? cs) (List reverse acc))
      ((%py-hex-space? (first cs)) (self (rest cs) (+ i 1) acc))
      ((null? (%py-hexval (first cs))) (%py-fromhex-bad! i))
      ((null? (rest cs))
        (Err raise (lit value)
          "fromhex() arg must contain an even number of hexadecimal digits" ()))
      ((null? (%py-hexval (first (rest cs)))) (%py-fromhex-bad! (+ i 1)))
      (#t
        (self (rest (rest cs)) (+ i 2)
          (pair (+ (* (%py-hexval (first cs)) 16) (%py-hexval (first (rest cs)))) acc))))))

; A classmethod on both classes: the class says which to answer, and a subclass
; is called with the bytes.  The argument is a str or, as of 3.14, any buffer.
(def %py-bytes-fromhex
  (fn (_ cls s)
    (let ((v (%py-native-of s)))
      (let ((l (%py-fromhex-walk
                 (match
                   ((%py-str-is v) (%py-str-cps v))
                   ((%py-buffer? v) (%py-buffer-bytes v))
                   (#t (Err raise (lit type)
                         (Str8 append "fromhex() argument must be str or bytes-like, not "
                           (%py-class-name (%py-type-of v))) ())))
                 0 ())))
        (match
          ((same? cls %py-cls-bytes) (%py-bytes-new l))
          ((same? cls %py-cls-bytearray) (%py-barr-new l))
          (#t (%py-instantiate cls (list (%py-bytes-new l)))))))))

(def %py-b-attr
  (fn (_ l mk name v)
    (match
      ((Str8 =? name "decode")
        (fn (_ . a)
          (%py-str-new
            (%ps-decode-as l (%py-codec-arg a 0 "utf-8")
              (%py-codec-arg a 1 "strict")))))
      ((Str8 =? name "find")     (fn (_ . a) (%py-b-search l a #f)))
      ((Str8 =? name "rfind")    (fn (_ . a) (%py-b-search l a #t)))
      ((Str8 =? name "index")    (fn (_ . a) (%py-b-index (%py-b-search l a #f))))
      ((Str8 =? name "rindex")   (fn (_ . a) (%py-b-index (%py-b-search l a #t))))
      ((Str8 =? name "count")
        (fn (_ . a)
          (let ((s (%py-b-start l a 1)))
            (%pb-count (%pb-sub l s (- (%py-b-end l a 2) s)) (%py-b-needle (first a)) 0))))
      ((Str8 =? name "startswith") (fn (_ . a) (%py-b-affix l a %pb-starts?)))
      ((Str8 =? name "endswith") (fn (_ . a) (%py-b-affix l a %pb-ends?)))
      ((Str8 =? name "upper")      (fn (_ . a) (mk (%pb-upper l))))
      ((Str8 =? name "lower")      (fn (_ . a) (mk (%pb-lower l))))
      ((Str8 =? name "swapcase")   (fn (_ . a) (mk (%pb-swapcase l))))
      ((Str8 =? name "capitalize") (fn (_ . a) (mk (%pb-capitalize l))))
      ((Str8 =? name "title")      (fn (_ . a) (mk (%pb-title l))))
      ((Str8 =? name "strip")
        (fn (_ . a) (%py-b-kept v mk l (%pb-strip l (%py-b-set a) #t #t))))
      ((Str8 =? name "lstrip")
        (fn (_ . a) (%py-b-kept v mk l (%pb-strip l (%py-b-set a) #t #f))))
      ((Str8 =? name "rstrip")
        (fn (_ . a) (%py-b-kept v mk l (%pb-strip l (%py-b-set a) #f #t))))
      ((Str8 =? name "split")
        (fn (_ . a) (%py-b-parts mk (%pb-split l (%py-b-split-sep a) (%py-b-opt a 1 (- 0 1))) ())))
      ((Str8 =? name "rsplit")
        (fn (_ . a) (%py-b-parts mk (%pb-rsplit l (%py-b-split-sep a) (%py-b-opt a 1 (- 0 1))) ())))
      ((Str8 =? name "splitlines")
        (fn (_ . a) (%py-b-parts mk (%pb-splitlines l (%py-truthy (%py-b-opt a 0 #f))) ())))
      ((Str8 =? name "join")    (fn (_ . a) (mk (%pb-join l (%py-b-seq (first a))))))
      ((Str8 =? name "replace")
        (fn (_ . a)
          (mk (%pb-replace l (%py-b-arg (first a)) (%py-b-arg (first (rest a)))
                (%py-b-opt a 2 (- 0 1))))))
      ((Str8 =? name "partition")
        (fn (_ . a) (%py-b-triple mk (%pb-partition l (%py-b-sep (first a))))))
      ((Str8 =? name "rpartition")
        (fn (_ . a) (%py-b-triple mk (%pb-rpartition l (%py-b-sep (first a))))))
      ((Str8 =? name "center") (fn (_ . a) (mk (%pb-center l (first a) (%py-b-fill a)))))
      ((Str8 =? name "ljust")  (fn (_ . a) (mk (%pb-ljust l (first a) (%py-b-fill a)))))
      ((Str8 =? name "rjust")  (fn (_ . a) (mk (%pb-rjust l (first a) (%py-b-fill a)))))
      ((Str8 =? name "isspace") (fn (_ . a) (%pb-isspace l)))
      ((Str8 =? name "isalpha") (fn (_ . a) (%pb-isalpha l)))
      ((Str8 =? name "isdigit") (fn (_ . a) (%pb-isdigit l)))
      ((Str8 =? name "isalnum") (fn (_ . a) (%pb-isalnum l)))
      ((Str8 =? name "isupper") (fn (_ . a) (%pb-isupper l)))
      ((Str8 =? name "islower") (fn (_ . a) (%pb-islower l)))
      ((Str8 =? name "hex") (fn (_ . a) (%py-bytes-hex l a)))
      (#t
        (if (%py-barr-is v)
          (%py-class-row-attr %py-cls-bytearray v name "bytearray")
          (%py-class-row-attr %py-cls-bytes v name "bytes"))))))

; index is find that RAISES, which is the whole difference between them.
(def %py-b-index
  (fn (_ i) (if (< i 0) (Err raise (lit value) "subsection not found" ()) i)))
; a strip set or a separator -- nil for "none given", and an explicit None
; means the same thing: `b"a b".split(None)` splits on whitespace.
(def %py-b-set
  (fn (_ args)
    (if (null? args) ()
      (if (null? (first args)) () (%py-b-arg (first args))))))

; AN EMPTY SEPARATOR IS A ValueError, for split and for partition both --
; there is no sensible place to cut.  An empty NEEDLE is a different question,
; and count answers that one with len+1.
(def %py-b-sep
  (fn (_ v)
    (let ((l (%py-b-arg v)))
      (if (null? l) (Err raise (lit value) "empty separator" ()) l))))

; a split separator: absent or None is whitespace, an empty bytes is the
; ValueError above.
(def %py-b-split-sep
  (fn (_ a)
    (if (null? a) ()
      (if (null? (first a)) () (%py-b-sep (first a))))))
; the pad byte, space unless one was given
(def %py-b-fill
  (fn (_ args)
    (let ((c (%py-b-opt args 1 ()))) (if (null? c) 32 (first c)))))
; the sequence a join walks
(def %py-b-seq
  (fn (self v)
    (%py-b-seq-go (%py-iter-elems v) ())))
(def %py-b-seq-go
  (fn (self l acc)
    (if (null? l) (List reverse acc) (self (rest l) (pair (%py-b-arg (first l)) acc)))))

; bytearray's repr is bytes' repr, said out loud: bytearray(b'foo').
(def %py-barr-repr
  (fn (_ l) (Str8 append "bytearray(" (Str8 append (%py-bytes-repr l) ")"))))

; THE TWO ATTRIBUTE SURFACES, and `mk` is the only thing they disagree about:
; a bytes method answers bytes, a bytearray method answers bytearrays.  Both
; read the same payload and run the same algorithms.
(def %py-bytes-attr
  (fn (_ b name) (%py-b-attr (%py-bytes-list b) %py-bytes-new name b)))

; A bytearray also MUTATES, and those two are its own: the payload is
; replaced in the cell, so every name bound to this bytearray sees it.
(def %py-barr-attr
  (fn (_ b name)
    (match
      ((Str8 =? name "append")
        (fn (_ v)
          (%py-barr-set! b
            (%pb-cat (%py-bytes-list b) (%py-bytes-of-codes (list v) ())))))
      ((Str8 =? name "extend")
        (fn (_ v)
          (%py-barr-set! b (%pb-cat (%py-bytes-list b) (%py-barr-bytes-of v)))))
      (#t (%py-b-attr (%py-bytes-list b) %py-barr-new name b)))))

; The source a bytes or bytearray call gives, from its source, encoding and
; errors arguments, of which there is at least one.  A keyword call leaves
; %py-dflt in a slot it did not fill, which reads as not given, and so is the
; answer when no source is.  The slots are read by position rather than through
; %py-opt, which would count the list for each of them.
(def %py-bytes-source
  (fn (_ cname args)
    (let ((more (rest args)))
      (match
        ((null? more) (%py-bytes-source-check (first args) %py-dflt %py-dflt))
        ((null? (rest more)) (%py-bytes-source-check (first args) (first more) %py-dflt))
        (#t
          (%seq (%py-takes-at-most! cname 3 (%py-length args))
            (%py-bytes-source-check (first args) (first more) (first (rest more)))))))))

; Checked as CPython checks them: a str, or a str subclass instance, needs an
; encoding and answers its encoded bytes, and any other source takes neither.
(def %py-bytes-source-check
  (fn (_ v enc errs)
    (match
      ((%py-str-is (%py-native-of v))
        (if (same? enc %py-dflt)
          (Err raise (lit type) "string argument without an encoding" ())
          (%py-bytes-new
            (%ps-encode-as (%py-str-cps (%py-native-of v))
              (%py-codec-name enc "utf-8") (%py-codec-name errs "strict")))))
      ((not (same? enc %py-dflt))
        (Err raise (lit type) "encoding without a string argument" ()))
      ((not (same? errs %py-dflt))
        (Err raise (lit type) "errors without a string argument" ()))
      (#t v))))

; A COUNT IS AN INTEGER, and a float is not one: bytes(5.5) asked for five and
; a half zero bytes and got five, where CPython refuses the value outright.
(def %py-bytes-count? (fn (_ v) (eq? (%py-num-kind (%py-boolnorm v)) (lit int))))

; CPython's words for a value neither constructor can take.
(def %py-bytes-refusal
  (fn (_ v name)
    (Str8 append "cannot convert '"
      (Str8 append (%py-class-name (%py-type-of v))
        (Str8 append "' object to " name)))))

; The bytes an argument stands for, whichever way it was written.
; bytearray(), bytearray(b'..'), bytearray('..', 'utf-8'), bytearray([..]),
; bytearray(n).  A count asks for that many zero bytes and now gets them.
(def %py-bytearray-ctor
  (fn (_ . args)
    (if (null? args)
      (%py-barr-new ())
      (let ((v (%py-bytes-source "bytearray" args)))
        (match
          ((same? v %py-dflt) (%py-barr-new ()))
          ((%py-bytes-is v) (%py-barr-new (%py-bytes-list v)))
          ((%py-list? v) (%py-barr-new (%py-bytes-of-codes (%py-list-elems v) ())))
          ((%py-tuple-is v) (%py-barr-new (%py-bytes-of-codes (%py-tuple-elems v) ())))
          ((%py-buffer? v) (%py-barr-new (%py-buffer-bytes v)))
          ((%py-bytes-count? v) (%py-barr-new (%py-bytes-zeros v ())))
          (#t
            (%py-barr-new
              (%py-bytes-of-codes
                (%py-iter-elems v (%py-bytes-refusal v "bytearray")) ()))))))))

(def %py-barr-bytes-of
  (fn (_ v)
    (match
      ((%py-bytes-is v) (%py-bytes-list v))
      ((%py-list? v) (%py-bytes-of-codes (%py-list-elems v) ()))
      ((%py-tuple-is v) (%py-bytes-of-codes (%py-tuple-elems v) ()))
      (#t (%py-bytes-of-codes (%py-iter-elems v) ())))))

(def %py-any-bytes?
  (fn (self l) (if (null? l) #f (if (%py-bytes-is (first l)) #t (self (rest l))))))
(def %py-str-method
  (fn (_ s name)
    (let ((m (%py-str-attr s name)))
      (fn (_ . args)
        (if (%py-any-bytes? args)
          (Err raise (lit type) "must be str, not bytes" ())
          (apply m args))))))
