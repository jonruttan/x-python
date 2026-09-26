; # x-python -- Python on x-lang
;
; ## python/deque.x -- collections.deque
;
; @description A double-ended queue with an optional bound: appending past
;   maxlen drops an element from the other end.  A deque is a value of its
;   own type and not a list -- isinstance(d, list) is False in Python too --
;   so the sequence doors each carry an arm for it, as they do for array.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; The value itself -- a bound and a cell of elements -- is declared in
; python/types.x with the other values the dispatchers test for.  Both ends are
; reached through the element list, which makes the right-hand end a walk; that
; is a cost, not a difference in what a program sees.

(module python/deque)
(import python/array %py-take-n)

; deque([1, 2]), and deque([1, 2], maxlen=3) when there is a bound; a subclass
; prints under its own name in place of deque.
(def %py-dq-named-repr
  (fn (_ name v)
    (Str8 append name
      (Str8 append "("
        (Str8 append (%py-repr-of (%py-list-new (%py-dq-el v)))
          (if (null? (%py-dq-max v))
            ")"
            (Str8 append ", maxlen=" (Str8 append (%py-str (%py-dq-max v)) ")"))))))))

(def %py-dq-repr (fn (_ v) (%py-dq-named-repr "deque" v)))

; --- the ends ----------------------------------------------------------------------

; A bound deque keeps the maxlen elements nearest the end just written to:
; keep-right? says which end that was.
(def %py-dq-fit
  (fn (_ v l keep-right?)
    (let ((m (%py-dq-max v)))
      (if (null? m)
        l
        (let ((over (- (%py-length l) m)))
          (match
            ((<= over 0) l)
            (keep-right? (%py-drop l over))
            (#t (%py-take-n l m ()))))))))

(def %py-dq-append!
  (fn (_ v x) (%py-dq-set! v (%py-dq-fit v (%py-list-cat (%py-dq-el v) (list x)) #t))))

(def %py-dq-appendleft!
  (fn (_ v x) (%py-dq-set! v (%py-dq-fit v (pair x (%py-dq-el v)) #f))))

; extend is append once per element, and extendleft appendleft, which is why
; extendleft reverses what it is given.
(def %py-dq-extend!
  (fn (_ v src)
    (%py-dq-set! v (%py-dq-fit v (%py-list-cat (%py-dq-el v) (%py-iter-elems src)) #t))))

(def %py-dq-extendleft!
  (fn (_ v src)
    (%py-dq-set! v
      (%py-dq-fit v (%py-list-cat (%py-reverse (%py-iter-elems src)) (%py-dq-el v)) #f))))

(def %py-dq-nonempty!
  (fn (_ v)
    (if (null? (%py-dq-el v)) (Err raise (lit index) "pop from an empty deque" ()) ())))

(def %py-dq-popleft!
  (fn (_ v)
    (%seq (%py-dq-nonempty! v)
      (let ((el (%py-dq-el v)))
        (%seq (%py-dq-set! v (rest el)) (first el))))))

(def %py-dq-pop!
  (fn (_ v)
    (%seq (%py-dq-nonempty! v)
      (let ((el (%py-dq-el v)))
        (%seq (%py-dq-set! v (%py-drop-last el)) (List ref (- (%py-length el) 1) el))))))

; --- by position -------------------------------------------------------------------

; An index is an int, counted from the end when it is negative.
(def %py-dq-pos
  (fn (_ v i)
    (let ((k (%py-boolnorm i)) (n (%py-length (%py-dq-el v))))
      (if (eq? (%py-num-kind k) (lit int))
        (let ((p (if (< k 0) (+ n k) k)))
          (if (if (< p 0) #t (>= p n))
            (Err raise (lit index) "deque index out of range" ())
            p))
        (Err raise (lit type)
          (Str8 append "sequence index must be integer, not '"
            (Str8 append (%py-class-name (%py-type-of i)) "'")) ())))))

(def %py-dq-at (fn (_ v i) (List ref (%py-dq-pos v i) (%py-dq-el v))))

(def %py-dq-put!
  (fn (_ v i x)
    (let ((p (%py-dq-pos v i))) (%py-dq-set! v (%py-els-set-at (%py-dq-el v) p x)))))

(def %py-dq-del!
  (fn (_ v i)
    (let ((p (%py-dq-pos v i))) (%py-dq-set! v (%py-els-drop-at (%py-dq-el v) p)))))

; A bound deque that is full has no room for an insert, and says so rather than
; dropping an element from either end.
(def %py-dq-insert!
  (fn (_ v i x)
    (let ((el (%py-dq-el v)) (m (%py-dq-max v)))
      (if (if (null? m) #f (>= (%py-length el) m))
        (Err raise (lit index) "deque already at its maximum size" ())
        (%py-dq-set! v (%py-els-insert-at el (%py-list-clamp (%py-length el) i 0) x))))))

; index(x[, start[, stop]])
(def %py-dq-index
  (fn (_ v x . more)
    (let ((el (%py-dq-el v)))
      (let ((n (%py-length el)))
        (let ((lo (if (null? more) 0 (%py-list-clamp n (first more) 0)))
              (hi (if (if (null? more) #t (null? (rest more)))
                    n
                    (%py-list-clamp n (first (rest more)) n))))
          (let ((k (%py-els-index (%py-drop el lo) lo hi x)))
            (if (< k 0)
              (Err raise (lit value) "deque.index(x): x not in deque" ())
              k)))))))

(def %py-dq-remove!
  (fn (_ v x)
    (let ((el (%py-dq-el v)))
      (let ((k (%py-els-index el 0 (%py-length el) x)))
        (if (< k 0)
          (Err raise (lit value) "deque.remove(x): x not in deque" ())
          (%py-dq-set! v (%py-els-drop-at el k)))))))

; rotate(n): the last n elements move to the front, and a negative n moves the
; first ones to the back.
(def %py-dq-rotate!
  (fn (_ v . more)
    (let ((el (%py-dq-el v)))
      (let ((n (%py-length el)))
        (if (= n 0)
          ()
          (let ((k (Num modulo (%py-boolnorm (if (null? more) 1 (first more))) n)))
            (%py-dq-set! v (%py-list-cat (%py-drop el (- n k)) (%py-take-n el (- n k) ())))))))))

; --- as a whole ----------------------------------------------------------------------

; Equal when both are deques holding equal elements in the same order; the
; bound is not compared, and a deque is never equal to a list.
(def %py-dq-eq
  (fn (_ a b)
    (if (if (%py-dq-is a) (%py-dq-is b) #f)
      (%py-eq (%py-list-new (%py-dq-el a)) (%py-list-new (%py-dq-el b)))
      #f)))

; deque + deque and deque * n are new deques, bound as the left one is.
(def %py-dq-cat
  (fn (_ a b)
    (if (%py-dq-is b)
      (let ((v (%py-dq-new (%py-dq-max a) ())))
        (%seq (%py-dq-set! v (%py-dq-fit v (%py-list-cat (%py-dq-el a) (%py-dq-el b)) #t)) v))
      (Err raise (lit type)
        (Str8 append "can only concatenate deque (not \""
          (Str8 append (%py-class-name (%py-type-of b)) "\") to deque")) ()))))

(def %py-dq-repeat
  (fn (_ a k)
    (let ((n (%py-boolnorm k)))
      (if (eq? (%py-num-kind n) (lit int))
        (let ((v (%py-dq-new (%py-dq-max a) ())))
          (%seq (%py-dq-set! v (%py-dq-fit v (%py-els-repeat (%py-dq-el a) n ()) #t)) v))
        (Err raise (lit type) "can't multiply sequence by non-int" ())))))

; --- the surfaces ----------------------------------------------------------------------

(def %py-dq-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "append") (fn (_ x) (%py-dq-append! v x)))
      ((Str8 =? name "appendleft") (fn (_ x) (%py-dq-appendleft! v x)))
      ((Str8 =? name "pop") (fn (_) (%py-dq-pop! v)))
      ((Str8 =? name "popleft") (fn (_) (%py-dq-popleft! v)))
      ((Str8 =? name "extend") (fn (_ src) (%py-dq-extend! v src)))
      ((Str8 =? name "extendleft") (fn (_ src) (%py-dq-extendleft! v src)))
      ((Str8 =? name "insert") (fn (_ i x) (%py-dq-insert! v i x)))
      ((Str8 =? name "remove") (fn (_ x) (%py-dq-remove! v x)))
      ((Str8 =? name "index") (fn (_ x . more) (apply %py-dq-index (pair v (pair x more)))))
      ((Str8 =? name "count") (fn (_ x) (%py-els-count (%py-dq-el v) x 0)))
      ((Str8 =? name "rotate") (fn (_ . more) (apply %py-dq-rotate! (pair v more))))
      ((Str8 =? name "reverse") (fn (_) (%py-dq-set! v (%py-reverse (%py-dq-el v)))))
      ((Str8 =? name "clear") (fn (_) (%py-dq-set! v ())))
      ((Str8 =? name "copy") (fn (_) (%py-dq-new (%py-dq-max v) (%py-dq-el v))))
      ((Str8 =? name "maxlen") (%py-dq-max v))
      (#t (%py-class-row-attr %py-cls-deque v name "collections.deque")))))

; deque(iterable=(), maxlen=None).  The bound is None or an int no less than 0.
(def %py-dq-bound
  (fn (_ m)
    (let ((k (%py-boolnorm m)))
      (match
        ((null? k) ())
        ((same? k %py-dflt) ())
        ((not (eq? (%py-num-kind k) (lit int))) (Err raise (lit type) "an integer is required" ()))
        ((< k 0) (Err raise (lit value) "maxlen must be non-negative" ()))
        (#t k)))))

(def %py-deque-ctor
  (fn (_ . a)
    (%seq (%py-takes-at-most! "deque" 2 (%py-length a))
      (let ((v (%py-dq-new
                 (%py-dq-bound (if (if (null? a) #t (null? (rest a))) () (first (rest a))))
                 ())))
        (%seq
          (if (if (null? a) #t (same? (first a) %py-dflt)) () (%py-dq-extend! v (first a)))
          v)))))

; deque.__init__(iterable, maxlen) sets the bound, empties the deque and extends
; it from the iterable, as in Python.
(def %py-deque-init
  (%py-sig!
    (fn (_ o . more)
      (let ((v (%py-native-of o)))
        (if (not (%py-dq-is v))
          (%py-init-receiver! "collections.deque" o)
          (let ((it (%py-opt more 0 %py-dflt)))
            (%seq (%py-takes-at-most! "deque" 2 (%py-length more))
              (%seq (%py-dq-set-max! v (%py-dq-bound (%py-opt more 1 ())))
                (%seq (%py-dq-set! v ())
                  (%seq (if (same? it %py-dflt) () (%py-dq-extend! v it)) ()))))))))
    "__init__" (list "self" "iterable" "maxlen") 1 #f () () #t))

; A deque subclass prints under its own name.
(def %py-dq-class-repr
  (fn (_ o) (%py-dq-named-repr (%py-class-name (%py-type-of o)) (%py-native-of o))))

; The class a subclass inherits from.  The named methods reach a subclass
; instance through the value it carries; these are the ones a dunder lookup
; asks the class for.
(def %py-dq-methods
  (list
    (pair "%ctor" (%py-sig! %py-deque-ctor "deque" (list "iterable" "maxlen") 0 #f))
    (pair "__init__" %py-deque-init)
    (pair "__len__" (fn (_ o) (%py-length (%py-dq-el (%py-native-of o)))))
    (pair "__getitem__" (fn (_ o i) (%py-dq-at (%py-native-of o) i)))
    (pair "__setitem__" (fn (_ o i x) (%py-dq-put! (%py-native-of o) i x)))
    (pair "__delitem__" (fn (_ o i) (%py-dq-del! (%py-native-of o) i)))
    (pair "__iter__" (fn (_ o) (%py-list-new (%py-dq-el (%py-native-of o)))))
    (pair "__contains__" (fn (_ o x) (%py-in-walk x (%py-dq-el (%py-native-of o)))))
    (pair "__eq__" (fn (_ o other) (%py-dq-eq (%py-native-of o) (%py-native-of other))))
    (pair "__repr__" %py-dq-class-repr)
    (pair "__str__" %py-dq-class-repr)))

(def %py-cls-deque
  (%py-class-new "deque" %py-cls-object %py-dq-methods "collections.deque"))

(provide python/deque
  %py-cls-deque %py-dq-at %py-dq-attr %py-dq-cat %py-dq-del! %py-dq-eq
  %py-dq-extend! %py-dq-put! %py-dq-repeat %py-dq-repr)
