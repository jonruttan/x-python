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
(module python/core)
(python-sweep!)
; --- Arithmetic --------------------------------------------------------------
; `+` dispatches on the operands, and the string case is not an extra: Python
; spells concatenation with it, and every conformance program that builds a
; message uses it.
(python-sweep!)
; --- The operator protocol ---------------------------------------------------
;
; A USER CLASS TAKES PART IN EVERY OPERATOR through its dunders, and the
; seams below ask for them the way Python does: the left operand's __op__
; first, then the right operand's reflected __rop__, and NotImplemented from
; either means "try the other side".  The check that opens every seam is a
; single type? call -- no frame, no allocation -- so the common numeric path
; pays nothing for the protocol's existence.
;
; NotImplemented is one unique value; identity is the test, as in Python.
(def %py-NotImplemented (pair (lit %py-NotImplemented) ()))

; ELLIPSIS IS THE OTHER SINGLETON PYTHON SPELLS AS A LITERAL, `...`, and it
; takes the same layout for the same reason: one unique pair, identity the
; test.  Nothing here reads it -- it exists so that a program that passes it
; around, hashes it, or compares it gets the answer Python gives.
(def %py-Ellipsis (pair (lit %py-Ellipsis) ()))

; The bound dunder, or nil.  A method compiles to (fn (_ py-self ...) ...),
; so binding is closing over the object -- the same technique %py-obj-attr uses.
(def python-dunder
  (fn (_ obj name)
    (let ((m (%py-method-find (python-obj-class obj) name)))
      (match
        ((null? m) ())
        ; the three built-in descriptors keep their meaning as dunders too
        ((%py-desc-is m)
          (let ((f (%py-desc-fn m)) (k (%py-desc-py-type m)))
            (if (eq? k (lit static)) f
              (if (eq? k (lit classmethod)) (%py-bind-method f (python-obj-class obj))
                (%py-bind-method m obj)))))
        (#t (%py-bind-method m obj))))))

; One side of a binary dispatch: the dunder's answer, or NotImplemented when
; the operand is not an object or has no such method.
(def %py-side
  (fn (_ x y name)
    (if (python-obj-is x)
      (let ((m (python-dunder x name)))
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
    (if (python-obj-is a)
      (let ((m (python-dunder a name)))
        (if (null? m) (binop a b) (m b)))
      (binop a b))))

(def %py-iadd
  (fn (_ a b)
    (match
      ; a list grows in place from ANY iterable, which is list.extend's rule
      ((python-list? a)
        (%seq (%py-list-set! a (python-list-cat (python-list-elems a) (python-iter-elems b))) a))
      ; and a deque by its own extend, which keeps its bound
      ((python-dq-is a) (%seq (python-dq-extend! a b) a))
      (#t (%py-inplace "__iadd__" python-add a b)))))

(def %py-isub    (fn (_ a b) (%py-inplace "__isub__" python-sub a b)))
(def %py-imul    (fn (_ a b) (%py-inplace "__imul__" python-mul a b)))
(def %py-imatmul (fn (_ a b) (%py-inplace "__imatmul__" %py-matmul a b)))
(def %py-idiv    (fn (_ a b) (%py-inplace "__itruediv__" python-div a b)))
(def %py-imod    (fn (_ a b) (%py-inplace "__imod__" python-mod a b)))
(def %py-ibitor  (fn (_ a b) (%py-inplace "__ior__" %py-bitor a b)))
(def %py-ibitand (fn (_ a b) (%py-inplace "__iand__" %py-bitand a b)))
(def %py-ibitxor (fn (_ a b) (%py-inplace "__ixor__" %py-bitxor a b)))
; The three-character forms, once the tokenizer could read them: `//=` `**=`
; `>>=` `<<=` are the same rule, and Python names their dunders after the
; binary op the same way.
(def %py-ifloordiv (fn (_ a b) (%py-inplace "__ifloordiv__" python-floordiv a b)))
(def %py-ipow      (fn (_ a b) (%py-inplace "__ipow__" %py-pow a b)))
(def %py-ilshift   (fn (_ a b) (%py-inplace "__ilshift__" %py-lshift a b)))
(def %py-irshift   (fn (_ a b) (%py-inplace "__irshift__" %py-rshift a b)))

(def python-add
  (fn (_ a b)
    (match
      ((%py-plain-nums? a b) (+ a b))
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__add__" "__radd__" "+"))
      ((python-arr-is a) (python-arr-cat a b))
      ((python-dq-is a) (python-dq-cat a b))
      ((match
         ((%py-view-is a) #t)
         ((%py-view-is b) #t)
         ((python-dict? a) #t)
         (#t (python-dict? b)))
        (%py-op-refuse "+" a b))
      ((python-list? a)
        (if (python-list? b)
          (python-list-new (python-list-cat (python-list-elems a) (python-list-elems b)))
          (%py-concat-refuse "list" b)))
      ; a tuple concatenates by the + its type carries (python/types.x)
      ((python-tuple-is a) (if (python-tuple-is b) (+ a b) (%py-concat-refuse "tuple" b)))
      ((python-list? b) (%py-op-refuse "+" a b))
      ; THE LEFT OPERAND DECIDES: bytearray + bytes is a bytearray and bytes +
      ; bytearray is a bytes, as in Python -- the buffers concatenate either
      ; way, and only the answer's type is in question.
      ((python-bytes-is a)
        (match
          ((python-bytes-is b)
            ((if (python-barr-is a) %py-barr-new python-bytes-new)
              (%pb-cat (python-bytes-list a) (python-bytes-list b))))
          ; an array is a buffer, and a buffer concatenates onto bytes
          ((python-arr-is b)
            ((if (python-barr-is a) %py-barr-new python-bytes-new)
              (%pb-cat (python-bytes-list a) (python-arr-buffer b))))
          (#t (Err raise (lit type) "can't concat to bytes" ()))))
      ((python-bytes-is b)
        (Err raise (lit type) "can't concat bytes to non-bytes" ()))
      ((python-str-is a)
        (if (python-str-is b)
          (python-str-new (%pb-cat (python-str-cps a) (python-str-cps b)))
          (%py-concat-refuse "str" b)))
      ((python-str-is b) (%py-op-refuse "+" a b))
      ; Bools are ints here too: 1j + True.
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
              (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "+" 0))
      ((%py-nums? a b)
        (+ (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b))))
      (#t (%py-op-refuse "+" a b)))))

(def python-sub
  (fn (_ a b)
    (match
      ((%py-plain-nums? a b) (- a b))
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__sub__" "__rsub__" "-"))
      ((if (python-set-is a) #t (python-set-is b)) (%py-set-sub a b))
      ((if (eq? (%py-typeof-prim a) %py-th-complex) #t
          (eq? (%py-typeof-prim b) %py-th-complex))
        (%py-cx-arith a b "-" 1))
      ((%py-nums? a b)
        (- (if (eq? a #t) 1 (if (eq? a #f) 0 a))
           (if (eq? b #t) 1 (if (eq? b #f) 0 b))))
      (#t (%py-op-refuse "-" a b)))))

; THE TYPE HANDLES, EARLY: the arithmetic seams below consult them, and
; python-f-2p64 is computed through python-mul at LOAD time -- so these must be
; bound before the first seam runs, not where the constructors that also
; use them happen to live.
(def %py-typeof-prim (prim-ref (lit type) (lit of)))
(def %py-th-int (%py-typeof-prim 1))
(def %py-th-big (%py-typeof-prim 99999999999999999999))
(def python-th-float (%py-typeof-prim 1.5))
(def %py-th-complex (%py-typeof-prim (Complex make 0.0 1.0)))
(def python-complex-is
  (fn (_ v) (eq? (%py-typeof-prim v) %py-th-complex)))
(def python-num-py-type
  (fn (_ v)
    (let ((h (%py-typeof-prim v)))
      (match
        ((eq? h %py-th-int) (lit int))
        ((eq? h %py-th-big) (lit int))
        ((eq? h python-th-float) (lit float))
        ((eq? h %py-th-complex) (lit complex))
        (#t ())))))
; a bool is the int it is
(def python-num?
  (fn (_ v)
    (match
      ((eq? (%py-typeof-prim v) %py-th-int) #t)
      ((eq? (%py-typeof-prim v) python-th-float) #t)
      ((eq? (%py-typeof-prim v) %py-th-big) #t)
      ((eq? (%py-typeof-prim v) %py-th-complex) #t)
      ((eq? v #t) #t)
      (#t (eq? v #f)))))

; A number on each side, or Python's TypeError.  Past the numbers the platform's
; operators do not refuse: they answer a word (1 + memoryview(b"")), raise under
; a label no except clause maps, or crash (1 / None).  So each seam asks before its
; numeric arm, and the refusal names both types as CPython does.
(def %py-nums? (fn (_ a b) (if (python-num? a) (python-num? b) #f)))
; A machine int or a float on each side needs none of a seam's other questions,
; and that is most of what a program adds, subtracts, multiplies and orders.
(def %py-plain-nums?
  (fn (_ a b)
    (if (if (eq? (%py-typeof-prim a) %py-th-int) #t
          (eq? (%py-typeof-prim a) python-th-float))
      (if (eq? (%py-typeof-prim b) %py-th-int) #t
        (eq? (%py-typeof-prim b) python-th-float))
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
    (Str8 append (Str8 append "'" (python-class-name (python-type-of a)))
      (Str8 append "' and '" (Str8 append (python-class-name (python-type-of b)) "'")))))
; can only concatenate list (not "int") to list
(def %py-concat-refuse
  (fn (_ what b)
    (Err raise (lit type)
      (Str8 append (Str8 append "can only concatenate " what)
        (Str8 append (Str8 append " (not \"" (python-class-name (python-type-of b)))
          (Str8 append "\") to " what)))
      ())))
; A sequence repeats by an int, a bool being one; any other count is refused in
; CPython's words.
(def %py-repeat-count
  (fn (_ k)
    (let ((n (python-boolnorm k)))
      (if (eq? (python-num-py-type n) (lit int))
        n
        (Err raise (lit type)
          (Str8 append "can't multiply sequence by non-int of type '"
            (Str8 append (python-class-name (python-type-of k)) "'"))
          ())))))

(python-sweep!)
; THE COMPLEX BRANCH OF THE FOUR SEAMS.  A complex beside a non-number is a
; TypeError here, not the tower's promotion error -- that one is x's
; teaching raise (#584) and its label is not `type`, so `except TypeError`
; never saw it and 1j + [] killed the program.  And a bigint beside a
; complex is FLOATED first, as Python does, because the tower declares no
; COMPLEX x BIGINT promotion.  Only the complex case pays: the seams reach
; here after two handle compares, and refuse any other non-number themselves.
(def %py-cx-arith
  (fn (_ a0 b0 op code)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (null? (python-num-py-type a)) #t (null? (python-num-py-type b)))
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
    (if (if (python-obj-is a0) #t (python-obj-is b0))
      (%py-binop a0 b0 "__lshift__" "__rlshift__" "<<")
    (%py-lshift-num a0 b0))))
(def %py-lshift-num
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (eq? (python-num-py-type a) (lit int)) (eq? (python-num-py-type b) (lit int)) #f)
      (if (< b 0)
        (Err raise (lit value) "negative shift count" ())
        (* a (Num expt 2 b)))
      (%py-op-refuse "<<" a0 b0))))
(def %py-rshift
  (fn (_ a0 b0)
    (if (if (python-obj-is a0) #t (python-obj-is b0))
      (%py-binop a0 b0 "__rshift__" "__rrshift__" ">>")
    (%py-rshift-num a0 b0))))
(def %py-rshift-num
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (if (if (eq? (python-num-py-type a) (lit int)) (eq? (python-num-py-type b) (lit int)) #f)
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
  (fn (_ s n) (python-str-new (%pb-repeat (python-str-cps s) n ()))))

(python-sweep!)
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
(def python-str-display (fn (_ l) (%ps-write l)))

; ONE CHARACTER IS A str OF ONE CODE POINT, which is what iterating a str
; yields -- not an int, the way iterating a bytes does.
(def %py-str-chars-of
  (fn (self l acc)
    (if (null? l) (List reverse acc)
      (self (rest l) (pair (python-str-new (list (first l))) acc)))))

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
  (fn (_ a b) (python-str-of-x (%py-format (ps->x (python-str-cps a)) b))))

; b"..." % args: the same engine over the template's bytes, answering the type
; the template was -- a bytearray formats to a bytearray.
(def %py-format-bytes
  (fn (_ a b)
    ((if (python-barr-is a) %py-barr-new python-bytes-new)
      (pb-of-str (%py-format (pb->str (python-bytes-list a)) b #t)))))

; `a @ b` means nothing here except to an object with __matmul__.
(def %py-matmul
  (fn (_ a b)
    (if (if (python-obj-is a) #t (python-obj-is b))
      (%py-binop a b "__matmul__" "__rmatmul__" "@")
      (%py-op-refuse "@" a b))))

(def python-mul
  (fn (_ a b)
    (match
      ((%py-plain-nums? a b) (* a b))
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__mul__" "__rmul__" "*"))
      ((python-dq-is a) (python-dq-repeat a b))
      ((python-dq-is b) (python-dq-repeat b a))
      ((python-list? a)
        (python-list-new (python-els-repeat (python-list-elems a) (%py-repeat-count b) ())))
      ((python-list? b)
        (python-list-new (python-els-repeat (python-list-elems b) (%py-repeat-count a) ())))
      ; a tuple repeats like every other sequence, and a namedtuple's own
      ; __mul__ answers through this arm
      ((python-tuple-is a)
        (python-tuple-new (python-els-repeat (python-tuple-elems a) (%py-repeat-count b) ())))
      ((python-tuple-is b)
        (python-tuple-new (python-els-repeat (python-tuple-elems b) (%py-repeat-count a) ())))
      ((python-bytes-is a)
        ((if (python-barr-is a) %py-barr-new python-bytes-new)
          (%pb-repeat (python-bytes-list a) (%py-repeat-count b) ())))
      ((python-bytes-is b)
        ((if (python-barr-is b) %py-barr-new python-bytes-new)
          (%pb-repeat (python-bytes-list b) (%py-repeat-count a) ())))
      ((python-str-is a) (%py-str-repeat a (%py-repeat-count b)))
      ((python-str-is b) (%py-str-repeat b (%py-repeat-count a)))
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
; this runtime makes.  The label is what `except ZeroDivisionError` matches on;
; see the exception section for why both layouts are caught the same way.
(def python-div
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (python-obj-is a) #t (python-obj-is b))
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
; The eighth field, a def's or a lambda's, is the environment the definition
; ran in, which is where its __globals__ comes from, and the ninth a box of
; what its __code__ is made of (runtime-str.x).
(def python-sig!
  (fn (_ f name names nreq has-rest . kw)
    (%set-first! %py-sigs
      (pair (pair f (list name names nreq has-rest
                      (%py-nth-or kw 0 ())
                      (%py-nth-or kw 1 ())
                      (%py-nth-or kw 2 ())
                      (%py-nth-or kw 3 ())
                      (if (null? (%py-nth-or kw 4 ())) () (list (%py-nth-or kw 4 ())))))
        (first %py-sigs)))
    f))
; A def or a lambda binds as a method when read from an instance; a builtin
; registered by hand does not, as in Python.  The seventh field says which.
(def %py-user-fn?
  (fn (_ f)
    (let ((sig (%py-sig-of f)))
      (if (null? sig) #f (if (> (python-length sig) 6) (List ref 6 sig) #f)))))

; **kwargs ARRIVES IN A BOX, and it has to: a plain call reaches a function by
; apply, with no keyword machinery in the way, so a dict at the end of the
; argument list would be indistinguishable from an ordinary positional one.
; The box is a pair whose head is this one unique value, which no program can
; produce, so the tail can be read without ambiguity.
(def %py-kwbox-label (list (lit %py-kwbox)))
(def %py-kwbox (fn (_ d) (pair %py-kwbox-label d)))
(def %py-kwbox? (fn (_ v) (if (pair? v) (same? (first v) %py-kwbox-label) #f)))

; The dict a call sent, or an empty one when it sent none -- which is what a
; plain call always looks like.
(def %py-kwargs-of
  (fn (self more)
    (if (null? more)
      (python-dict-new ())
      (if (null? (rest more))
        (if (%py-kwbox? (first more)) (rest (first more)) (python-dict-new ()))
        (self (rest more))))))

; The same tail without the box, which is what the positional binders read.
(def %py-args-strip-kw
  (fn (self more)
    (if (null? more)
      ()
      (if (null? (rest more))
        (if (%py-kwbox? (first more)) () more)
        (pair (first more) (self (rest more)))))))
(def python-dflt (list (lit %py-default)))
(def python-opt
  (fn (_ more i dflt)
    (if (>= i (python-length more)) dflt
      (let ((v (List ref i more))) (if (same? v python-dflt) dflt v)))))

; f() missing N required positional argument(s): 'a' and 'b' -- raised when
; the tail is shorter than the required names, naming the ones not given.
(def %py-need!
  (fn (_ fname more names)
    (let ((given (python-length (%py-args-strip-kw more))))
      (if (>= given (python-length names))
        ()
        (%py-missing! fname "positional" (%py-drop-n names given))))))
; f() missing N required keyword-only argument(s): 'b' and 'c'
(def %py-kw-req!
  (fn (_ fname more names)
    (let ((absent (%py-absent-keys names (%py-kwargs-of more) ())))
      (if (null? absent) () (%py-missing! fname "keyword-only" absent)))))
(def %py-missing!
  (fn (_ fname label names)
    (let ((n (python-length names)))
      (Err raise (lit type)
        (Str8 append fname
          (Str8 append "() missing "
            (Str8 append (python-str n)
              (Str8 append (if (= n 1) " required " " required ")
                (Str8 append label
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
    (if (null? names) (python-reverse acc)
      (self (rest names) d
        (if (null? (%py-dfind (python-str-of-x (first names)) (python-dict-entries d))) (pair (first names) acc) acc)))))
; A kw-only name's code points, converted once.  The name is read on every
; call of its function, and converting it to a str each time cost more
; objects than the lookup it served.
(def %py-kw-cps-memo (pair () ()))
(def %py-kw-cps
  (fn (_ name)
    (let ((e (python-alist-find name (first %py-kw-cps-memo))))
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
          (if (if (python-str-is (first (first es)))
                (%pb-eq? (python-str-cps (first (first es))) cps) #f)
            (rest (first es))
            (self (rest es) cps)))))
    (let ((es (python-dict-entries (%py-kwargs-of more))))
      (if (null? es) dflt (go es (%py-kw-cps name))))))
; The **kwargs dict without the keyword-only names, which were bound by name.
(def %py-kwargs-minus
  (fn (_ d names)
    (python-dict-new (%py-rows-minus (python-dict-entries d) names ()))))
(def %py-rows-minus
  (fn (self rows names acc)
    (if (null? rows) (python-reverse acc)
      (self (rest rows) names
        (if (%py-name-in? (first (first rows)) names) acc (pair (first rows) acc))))))
(def %py-name-in?
  (fn (self k names)
    (if (null? names) #f
      (if (%pb-eq? (python-str-cps k) (%ps-of-x (first names))) #t (self k (rest names))))))
(def python-floordiv
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__floordiv__" "__rfloordiv__" "//"))
      ((not (%py-nums? a b)) (%py-op-refuse "//" a0 b0))
      ((= b 0)
        (Err raise (lit zero-division) "division by zero" ()))
      ((if (python-complex-is a) #t (python-complex-is b))
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
(def python-mod
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    ; str.__mod__ answers first: "%d" % obj formats the object, it does not
    ; ask the object for __rmod__
    (match
      ((python-str-is a) (%py-format-str a b0))
      ((python-bytes-is a) (%py-format-bytes a b0))
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__mod__" "__rmod__" "%"))
      ((not (%py-nums? a b)) (%py-op-refuse "%" a0 b0))
      ((if (python-complex-is a) #t (python-complex-is b))
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
      (if (if (python-num? a) (if (python-num? b) (python-num? (first m)) #f) #f)
        (%py-powmod (python-boolnorm a) (python-boolnorm b) (python-boolnorm (first m)))
        (Err raise (lit type) "pow() requires integers" ())))))

(python-sweep!)
(def %py-pow
  (fn (_ a0 b0)
    (def a (if (eq? a0 #t) 1 (if (eq? a0 #f) 0 a0)))
    (def b (if (eq? b0 #t) 1 (if (eq? b0 #f) 0 b0)))
    (match
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__pow__" "__rpow__" "** or pow()"))
      ((not (%py-nums? a b)) (%py-op-refuse "** or pow()" a0 b0))
      ((if (python-complex-is a) #t (python-complex-is b))
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
          (def fa (* (python-boolnorm a) 1.0))
          (def fb (* (python-boolnorm b) 1.0))
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
        (let ((x (python-boolnorm a)) (e (python-boolnorm b)))
          (match
            ((= x 1) 1)
            ((= x 0) (if (= e 0) 1 0))
            (#t (if (= (Num modulo e 2) 0) 1 (- 0 1))))))
      (#t (Num expt a b)))))
(def %py-pow-unit?
  (fn (_ v)
    (let ((x (python-boolnorm v)))
      (if (eq? (python-num-py-type x) (lit int))
        (if (= x 0) #t (if (= x 1) #t (= x (- 0 1))))
        #f))))
; A bool negates as the int it is, and a value that is no number is refused, as
; unary + and ~ below already had it.
(def %py-neg
  (fn (_ a)
    (if (python-obj-is a)
      (let ((m (python-dunder a "__neg__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary -" ()) (m)))
      (let ((w (python-boolnorm a)))
        (if (null? (python-num-py-type w))
          (Err raise (lit type) "bad operand type for unary -" ())
          (- 0 w))))))

; Unary + is a no-op on numbers and a TypeError on everything else; unary ~
; is exact two's complement on integers and a TypeError on floats -- both
; measured refusals in the conformance corpus, not decorations.
(def %py-pos
  (fn (_ v)
    (if (python-obj-is v)
      (let ((m (python-dunder v "__pos__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary +" ()) (m)))
    (let ((w (python-boolnorm v)))
      (if (null? (python-num-py-type w))
        (Err raise (lit type) "bad operand type for unary +" ())
        w)))))

(def %py-invert
  (fn (_ v)
    (if (python-obj-is v)
      (let ((m (python-dunder v "__invert__")))
        (if (null? m) (Err raise (lit type) "bad operand type for unary ~" ()) (m)))
    (let ((w (python-boolnorm v)))
      (if (eq? (python-num-py-type w) (lit int))
        (- (- 0 w) 1)
        (Err raise (lit type) "bad operand type for unary ~" ()))))))

; True is 1 and False is 0 wherever a number is wanted: comparisons,
; arithmetic seams, formatting.  Python's bool IS an int; x's is not.
(def python-boolnorm
  (fn (_ v) (if (eq? v #t) 1 (if (eq? v #f) 0 v))))

(python-sweep!)
; --- Bitwise, exact two's complement -----------------------------------------
; Two fixnums go straight to the integer door: a machine word is already two's
; complement, and &, | and ^ of two words is a word.  A bigint operand is cut
; into 24-bit chunks, least significant first, beside a tail -- 0, or the
; mask for the infinite ones a negative number stands for -- and the chunks
; combine through the same door.  A chunk comes from the bigint's decimal
; limbs by short division on the doors (r * base + limb stays under 2^55);
; a negative operand is cut as its complement, -1 - v, with each chunk
; flipped.  Only the final value is rebuilt through the tower.
(import x/num/bigint big-limbs bigint-base)
(def %py-bit-and (prim-ref (lit int) (lit &)))
(def %py-bit-or (prim-ref (lit int) (lit |)))
(def %py-bit-xor (prim-ref (lit int) (lit ^)))
(def %py-bit-not (prim-ref (lit int) (lit ~)))
(def %py-bit-shr (prim-ref (lit int) (lit >>)))
(def %py-bit-mask 16777215)
(def %py-bit-width 16777216)

; The chunks of a non-negative fixnum.
(def %py-bit-fix
  (fn (self v acc)
    (if (= v 0) (python-reverse acc)
      (self (%py-bit-shr v 24) (pair (%py-bit-and v %py-bit-mask) acc)))))

; Limbs, most significant first, divided by 2^24: (remainder . quotient), the
; quotient's limbs most significant first with no leading zero.
(def %py-bit-sdiv
  (fn (self ls r q)
    (if (null? ls) (pair r (python-reverse q))
      (let ((t (%py-fx+ (%py-fx* r bigint-base) (first ls))))
        (let ((d (%py-bit-shr t 24)))
          (self (rest ls) (%py-bit-and t %py-bit-mask)
            (if (if (= d 0) (null? q) #f) q (pair d q))))))))
(def %py-bit-limbs
  (fn (self ls acc)
    (if (null? ls) (python-reverse acc)
      (let ((s (%py-bit-sdiv ls 0 ())))
        (self (rest s) (pair (first s) acc))))))

; The chunks of a non-negative integer.
(def %py-bit-mag
  (fn (_ v)
    (if (eq? (%py-typeof-prim v) %py-th-big)
      (%py-bit-limbs (python-reverse (big-limbs v)) ())
      (%py-bit-fix v ()))))

(def %py-bit-flip
  (fn (self cs acc)
    (if (null? cs) (python-reverse acc)
      (self (rest cs) (pair (python-fx- %py-bit-mask (first cs)) acc)))))

; (tail . chunks) of an integer.
(def %py-bit-chunks
  (fn (_ v)
    (if (< v 0)
      (pair %py-bit-mask
        (%py-bit-flip
          (%py-bit-mag (if (eq? (%py-typeof-prim v) %py-th-big) (- (- 0 1) v) (%py-bit-not v)))
          ()))
      (pair 0 (%py-bit-mag v)))))

; Chunk by chunk, a list past its end standing in its tail.
(def %py-bit-zip
  (fn (self op as ta bs tb acc)
    (if (if (null? as) (null? bs) #f)
      (python-reverse acc)
      (self op (if (null? as) () (rest as)) ta (if (null? bs) () (rest bs)) tb
        (pair (op (if (null? as) ta (first as)) (if (null? bs) tb (first bs))) acc)))))

; The value of chunks given most significant first.
(def %py-bit-value
  (fn (self cs acc)
    (if (null? cs) acc (self (rest cs) (+ (* acc %py-bit-width) (first cs))))))

(def %py-bit-int
  (fn (_ op a b)
    (if (if (eq? (%py-typeof-prim a) %py-th-int) (eq? (%py-typeof-prim b) %py-th-int) #f)
      (op a b)
      (let ((ca (%py-bit-chunks a)) (cb (%py-bit-chunks b)))
        (let ((cs (%py-bit-zip op (rest ca) (first ca) (rest cb) (first cb) ())))
          (if (= (op (first ca) (first cb)) 0)
            (%py-bit-value (python-reverse cs) 0)
            (- (- 0 1) (%py-bit-value (python-reverse (%py-bit-flip cs ())) 0))))))))

(def %py-bit2
  (fn (_ a0 b0 opname op)
    (def a (python-boolnorm a0))
    (def b (python-boolnorm b0))
    (if (if (eq? (python-num-py-type a) (lit int)) (eq? (python-num-py-type b) (lit int)) #f)
      ; two bools answer a bool, as in Python
      (let ((r (%py-bit-int op a b)))
        (if (if (if (eq? a0 #t) #t (eq? a0 #f)) (if (eq? b0 #t) #t (eq? b0 #f)) #f)
          (= r 1)
          r))
      (%py-op-refuse opname a0 b0))))

(def %py-bitor
  (fn (_ a b)
    (match
      ((if (python-dict? a) (python-dict? b) #f)
        (let ((d (python-dict-new (%py-dict-copy (python-dict-entries a)))))
          (%seq (%py-dict-merge! d b) d)))
      ; an instance before a set, so a set subclass instance beside a set is
      ; asked through its class
      ((if (python-obj-is a) #t (python-obj-is b))
        (%py-binop a b "__or__" "__ror__" "|"))
      ((if (python-set-is a) #t (python-set-is b)) (%py-set-or a b))
      (#t (%py-bit2 a b "|" %py-bit-or)))))
(def %py-bitxor
  (fn (_ a b)
    (if (if (python-obj-is a) #t (python-obj-is b))
      (%py-binop a b "__xor__" "__rxor__" "^")
    (if (if (python-set-is a) #t (python-set-is b))
      (%py-set-xor a b)
      (%py-bit2 a b "^" %py-bit-xor)))))
(def %py-bitand
  (fn (_ a b)
    (if (if (python-obj-is a) #t (python-obj-is b))
      (%py-binop a b "__and__" "__rand__" "&")
    (if (if (python-set-is a) #t (python-set-is b))
      (%py-set-and a b)
      (%py-bit2 a b "&" %py-bit-and)))))

(python-sweep!)
; --- Membership --------------------------------------------------------------
; `a in b`: substring for strings, element walk with Python's equality for
; the containers, keys for a dict, and a TypeError for anything that cannot
; be iterated -- 1.2 in 3.4 must refuse, not loop.
(def python-in-walk
  (fn (self a l)
    (if (null? l) #f (if (python-eq a (first l)) #t (self a (rest l))))))

; An iterator is read up to the first equal item and no further, as in
; CPython: `2 in gen` leaves the rest of gen unread.
(def %py-in-pull
  (fn (self a src)
    (def v (%py-iter-pull! src))
    (match
      ((same? v %py-gen-done) #f)
      ((python-eq a v) #t)
      (#t (self a src)))))

; argument of type 'int' is not a container or iterable
(def %py-in-refusal
  (fn (_ v)
    (Str8 append "argument of type '"
      (Str8 append (%py-type-name v) "' is not a container or iterable"))))

(def python-in
  (fn (_ a b)
    (match
      ((python-obj-is b)
        (let ((m (python-dunder b "__contains__")))
          (if (null? m)
            (%py-in-pull a (%py-iter-open b (%py-in-refusal b)))
            (%py-truthy (m a)))))
      ((python-arr-is b) (python-in-walk a (python-arr-el b)))
      ((python-dq-is b) (python-in-walk a (python-dq-el b)))
      ((python-bytes-is b)
        (if (python-bytes-is a)
          (%pb-in? (python-bytes-list a) (python-bytes-list b))
          ; AN INT IN A BYTES IS A BYTE VALUE, not a type error: bytes are a
          ; sequence OF ints in Python, so `0 in b"1234"` asks whether any byte
          ; is zero and answers False rather than refusing.
          (if (eq? (python-num-py-type (python-boolnorm a)) (lit int))
            (python-in-walk (python-boolnorm a) (python-bytes-list b))
            (if (python-arr-is a)
              (%pb-in? (python-arr-buffer a) (python-bytes-list b))
              (Err raise (lit type)
                (Str8 append "a bytes-like object is required, not '"
                  (Str8 append (%py-type-name a) "'")) ())))))
      ((python-str-is b)
        (if (python-str-is a)
          (%pb-in? (python-str-cps a) (python-str-cps b))
          (Err raise (lit type)
            (Str8 append "'in <string>' requires string as left operand, not "
              (%py-type-name a)) ())))
      ((python-set-is b) (%py-set-has? a (python-set-elems b)))
      ((python-list? b) (python-in-walk a (python-list-elems b)))
      ((python-tuple-is b) (python-in-walk a (python-tuple-elems b)))
      ((python-dict? b)
        (do
          (def keys
            (fn (self es acc)
              (if (null? es) acc (self (rest es) (pair (first (first es)) acc)))))
          (python-in-walk a (keys (python-dict-entries b) ()))))
      ((%py-range-is b) (%py-range-has? b a))
      ((if (%py-gen-is b) #t (%py-it-is b)) (%py-in-pull a b))
      ((%py-view-is b) (python-in-walk a (%py-view-elems b)))
      (#t (%py-in-pull a (%py-iter-open b (%py-in-refusal b)))))))

(python-sweep!)
; --- Numeric builtins --------------------------------------------------------
; abs clears the SIGN BIT for floats (the arithmetic spelling turns -0.0
; into itself); round is the exact-digit machinery at a decimal place, half
; to even, int result without ndigits and float with.
(def %py-abs
  (fn (_ v0)
    (if (python-obj-is v0)
      (let ((m (python-dunder v0 "__abs__")))
        (if (null? m) (Err raise (lit type) "bad operand type for abs()" ()) (m)))
    (%py-abs-num v0))))
(def %py-abs-num
  (fn (_ v0)
    (def v (python-boolnorm v0))
    (match
      ((%py-float-is v) (if (< (first v) 0) (- 0.0 v) v))
      ((python-complex-is v) (Complex magnitude v))
      ((eq? (python-num-py-type v) (lit int)) (if (< v 0) (- 0 v) v))
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
    (if (> (python-length a) 2)
      (Err raise (lit type)
        (Str8 append "round() takes at most 2 arguments ("
          (Str8 append (python-str (python-length a)) " given)")) ())
      ())
    (def v (python-boolnorm (first a)))
    (def nd (if (null? (rest a)) () (first (rest a))))
    (if (not (%py-float-is v))
      (if (eq? (python-num-py-type v) (lit int))
        (if (if (null? nd) #f (< (python-boolnorm nd) 0))
          (%py-round-int v (python-boolnorm nd))
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
; %py-kw-args pads its slots with the python-dflt sentinel, which no user
; value can be.
(def %py-has-dflt?
  (fn (self l) (if (null? l) #f (if (same? (first l) python-dflt) #t (self (rest l))))))
(def %py-minmax-call
  (fn (_ a which pick)
    (def key ())
    (def dflt python-dflt)
    (def vs (if (null? (rest a)) (python-iter-elems (first a)) a))
    (if (null? vs)
      (if (same? dflt python-dflt)
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
(def %py-min (fn (_ . a) (%py-minmax-call a "min" (fn (_ x y) (python-lt x y)))))
(def %py-max (fn (_ . a) (%py-minmax-call a "max" (fn (_ x y) (python-gt x y)))))
; the keyword form: every positional is a VALUE (or the one iterable), and
; key=/default= come from the keywords
(def %py-minmax-kw
  (fn (_ f pos kws)
    (def which (if (same? f %py-min) "min" "max"))
    (def pick (if (same? f %py-min) (fn (_ x y) (python-lt x y)) (fn (_ x y) (python-gt x y))))
    (def key (let ((e (python-alist-find "key" kws))) (if (null? e) () (rest e))))
    (def dflt (let ((e (python-alist-find "default" kws))) (if (null? e) python-dflt (rest e))))
    (def vs (if (null? (rest pos)) (python-iter-elems (first pos)) pos))
    (if (null? vs)
      (if (same? dflt python-dflt)
        (Err raise (lit value) (Str8 append which "() arg is an empty sequence") ())
        dflt)
      (%py-minmax-by vs pick (if (null? key) %py-ident key)))))

(python-sweep!)
; --- Bytes seams -------------------------------------------------------------
(def %py-mkbytes (fn (_ s) (%py-bytes-of-str s)))

; b'...' with Python's escapes: the quote rule of str's repr, \n \r \t by
; name, and every byte outside printable ASCII as \xhh -- which is how a NUL
; shows itself now that one can be here at all: b'\x00'.
(def %py-bytes-repr
  (fn (_ l)
    (let ((q (if (if (%pb-in? (list 39) l) (not (%pb-in? (list 34) l)) #f) 34 39)))
      (Str8 append "b"
        (let ((qs (python-list->string (list (%py-int->char q)))))
          (Str8 append qs (Str8 append (%py-bytes-repr-go l q "") qs)))))))
(def %py-bytes-repr-go
  (fn (self l q acc)
    (if (null? l) acc
      (let ((c (first l)))
        (self (rest l) q
          (Str8 append acc
            (match
              ((= c 92) "\\\\")
              ((= c q) (Str8 append "\\" (python-list->string (list (%py-int->char c)))))
              ((= c 10) "\\n")
              ((= c 13) "\\r")
              ((= c 9) "\\t")
              ((if (< c 32) #t (>= c 127)) (Str8 append "\\x" (%py-hex2 c)))
              (#t (python-list->string (list (%py-int->char c)))))))))))

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
      ((python-bytes-is a) (python-bytes-list a))
      ((python-str-is a) (Err raise (lit type) "a bytes-like object is required, not 'str'" ()))
      (#t (Err raise (lit type) "a bytes-like object is required" ())))))

; A NEEDLE MAY BE ONE BYTE WRITTEN AS AN INT.  `b"abc".find(ord("b"))` is
; Python, and only the searching methods take it -- replace and partition
; want a bytes-like and say so.  Reaching %pb-at? with a bare int used to
; walk `first` into a non-pair, which on this engine is a SEGFAULT and took
; the whole spec file with it rather than one case.
(def %py-b-needle
  (fn (_ v)
    (if (python-num? v)
      (let ((n (python-boolnorm v)))
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
    (let ((i (python-boolnorm i0)))
      (let ((k (if (< i 0) (+ n i) i)))
        (if (< k 0) 0 (if (> k n) n k))))))
(def %py-b-start
  (fn (_ l a i)
    (let ((v (%py-b-opt a i ()))) (if (null? v) 0 (%py-b-clamp v (pb-len l))))))
(def %py-b-end
  (fn (_ l a i)
    (let ((v (%py-b-opt a i ()))) (if (null? v) (pb-len l) (%py-b-clamp v (pb-len l))))))

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
    (if (null? ps) (python-list-new (List reverse acc))
      (self mk (rest ps) (pair (mk (first ps)) acc)))))
(def %py-b-triple
  (fn (_ mk t) (python-tuple-new (list (mk (first t)) (mk (first (rest t))) (mk (first (rest (rest t))))))))

; ONE TABLE, and `mk` is the only thing bytes and bytearray disagree about:
; which of the two a method's answer is made into.
;
; EACH ARM ANSWERS A CLOSURE, so the NAME is resolved when it is asked for
; and not when it is called.  That is what makes `bytes.nosuch` an
; AttributeError at the dot -- which is the technique %py-str-attr already had,
; and which five conformance programs probe with a bare `bytes.count`.
; An encoding or errors argument: the platform string the codec names it by.
; A call that left it out, or a constructor carrying python-dflt for it, takes the
; default instead.
(def %py-codec-name
  (fn (_ v dflt)
    (match
      ((null? v) dflt)
      ((same? v python-dflt) dflt)
      (#t
        (let ((s (python-native-of v)))
          (if (python-str-is s)
            (ps->x (python-str-cps s))
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
    (if (if (python-barr-is v) #f (= (pb-len r) (pb-len l))) v (mk r))))

(python-sweep!)
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
      (let ((s (python-native-of (first a))))
        (let ((cs (match
                    ((python-str-is s) (python-str-cps s))
                    ((python-bytes-is s) (python-bytes-list s))
                    (#t (%py-no-len s)))))
          (match
            ((not (= (python-length cs) 1))
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

(def python-bytes-hex
  (fn (_ l a)
    (python-str-new (%py-hex-walk l 0 (pb-len l) (%py-b-opt a 1 1) (%py-hex-sep a) ()))))

; bytes.fromhex(s): a pair of digits a byte, with whitespace allowed BETWEEN
; pairs and nowhere else.  CPython names the position of the first character
; that is not a digit where one was due, and says so differently when the
; string simply ran out in the middle of a pair.
(def %py-fromhex-bad!
  (fn (_ i)
    (Err raise (lit value)
      (Str8 append "non-hexadecimal number found in fromhex() arg at position " (python-str i))
      ())))

(def %py-fromhex-walk
  (fn (self cs i acc)
    (match
      ((null? cs) (List reverse acc))
      ((%pb-space? (first cs)) (self (rest cs) (+ i 1) acc))
      ((null? (python-hexval (first cs))) (%py-fromhex-bad! i))
      ((null? (rest cs))
        (Err raise (lit value)
          "fromhex() arg must contain an even number of hexadecimal digits" ()))
      ((null? (python-hexval (first (rest cs)))) (%py-fromhex-bad! (+ i 1)))
      (#t
        (self (rest (rest cs)) (+ i 2)
          (pair (+ (* (python-hexval (first cs)) 16) (python-hexval (first (rest cs)))) acc))))))

; A classmethod on both classes: the class says which to answer, and a subclass
; is called with the bytes.  The argument is a str or, as of 3.14, any buffer.
(def %py-bytes-fromhex
  (fn (_ cls s)
    (let ((v (python-native-of s)))
      (let ((l (%py-fromhex-walk
                 (match
                   ((python-str-is v) (python-str-cps v))
                   ((python-buffer? v) (python-buffer-bytes v))
                   (#t (Err raise (lit type)
                         (Str8 append "fromhex() argument must be str or bytes-like, not "
                           (python-class-name (python-type-of v))) ())))
                 0 ())))
        (match
          ((same? cls %py-cls-bytes) (python-bytes-new l))
          ((same? cls %py-cls-bytearray) (%py-barr-new l))
          (#t (python-instantiate cls (list (python-bytes-new l)))))))))

(def %py-b-attr
  (fn (_ l mk name v)
    (match
      ((Str8 =? name "decode")
        (fn (_ . a)
          (python-str-new
            (ps-decode-as l (%py-codec-arg a 0 "utf-8")
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
      ((Str8 =? name "hex") (fn (_ . a) (python-bytes-hex l a)))
      (#t
        (if (python-barr-is v)
          (python-class-row-attr %py-cls-bytearray v name "bytearray")
          (python-class-row-attr %py-cls-bytes v name "bytes"))))))

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
    (%py-b-seq-go (python-iter-elems v) ())))
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
  (fn (_ b name) (%py-b-attr (python-bytes-list b) python-bytes-new name b)))

; A bytearray also MUTATES, and those two are its own: the payload is
; replaced in the cell, so every name bound to this bytearray sees it.
(def %py-barr-attr
  (fn (_ b name)
    (match
      ((Str8 =? name "append")
        (fn (_ v)
          (python-barr-set! b
            (%pb-cat (python-bytes-list b) (python-bytes-of-codes (list v) ())))))
      ((Str8 =? name "extend")
        (fn (_ v)
          (python-barr-set! b (%pb-cat (python-bytes-list b) (%py-barr-bytes-of v)))))
      (#t (%py-b-attr (python-bytes-list b) %py-barr-new name b)))))

; The source a bytes or bytearray call gives, from its source, encoding and
; errors arguments, of which there is at least one.  A keyword call leaves
; python-dflt in a slot it did not fill, which reads as not given, and so is the
; answer when no source is.  The slots are read by position rather than through
; python-opt, which would count the list for each of them.
(def %py-bytes-source
  (fn (_ cname args)
    (let ((more (rest args)))
      (match
        ((null? more) (%py-bytes-source-check (first args) python-dflt python-dflt))
        ((null? (rest more)) (%py-bytes-source-check (first args) (first more) python-dflt))
        (#t
          (%seq (python-takes-at-most! cname 3 (python-length args))
            (%py-bytes-source-check (first args) (first more) (first (rest more)))))))))

(python-sweep!)
; Checked as CPython checks them: a str, or a str subclass instance, needs an
; encoding and answers its encoded bytes, and any other source takes neither.
(def %py-bytes-source-check
  (fn (_ v enc errs)
    (match
      ((python-str-is (python-native-of v))
        (if (same? enc python-dflt)
          (Err raise (lit type) "string argument without an encoding" ())
          (python-bytes-new
            (ps-encode-as (python-str-cps (python-native-of v))
              (%py-codec-name enc "utf-8") (%py-codec-name errs "strict")))))
      ((not (same? enc python-dflt))
        (Err raise (lit type) "encoding without a string argument" ()))
      ((not (same? errs python-dflt))
        (Err raise (lit type) "errors without a string argument" ()))
      (#t v))))

; A COUNT IS AN INTEGER, and a float is not one: bytes(5.5) asked for five and
; a half zero bytes and got five, where CPython refuses the value outright.
(def %py-bytes-count? (fn (_ v) (eq? (python-num-py-type (python-boolnorm v)) (lit int))))

; CPython's words for a value neither constructor can take.
(def %py-bytes-refusal
  (fn (_ v name)
    (Str8 append "cannot convert '"
      (Str8 append (python-class-name (python-type-of v))
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
          ((same? v python-dflt) (%py-barr-new ()))
          ((python-bytes-is v) (%py-barr-new (python-bytes-list v)))
          ((python-list? v) (%py-barr-new (python-bytes-of-codes (python-list-elems v) ())))
          ((python-tuple-is v) (%py-barr-new (python-bytes-of-codes (python-tuple-elems v) ())))
          ((python-buffer? v) (%py-barr-new (python-buffer-bytes v)))
          ((%py-bytes-count? v) (%py-barr-new (%py-bytes-zeros v ())))
          (#t
            (%py-barr-new
              (python-bytes-of-codes
                (python-iter-elems v (%py-bytes-refusal v "bytearray")) ()))))))))

(def %py-barr-bytes-of
  (fn (_ v)
    (match
      ((python-bytes-is v) (python-bytes-list v))
      ((python-list? v) (python-bytes-of-codes (python-list-elems v) ()))
      ((python-tuple-is v) (python-bytes-of-codes (python-tuple-elems v) ()))
      (#t (python-bytes-of-codes (python-iter-elems v) ())))))

(def %py-any-bytes?
  (fn (self l) (if (null? l) #f (if (python-bytes-is (first l)) #t (self (rest l))))))
(def %py-str-method
  (fn (_ s name)
    (let ((m (%py-str-attr s name)))
      (fn (_ . args)
        (if (%py-any-bytes? args)
          (Err raise (lit type) "must be str, not bytes" ())
          (apply m args))))))
