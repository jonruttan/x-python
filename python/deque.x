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
(import python/core
  python-boolnorm python-class-name python-class-new python-class-row-attr python-cls-object
  python-dflt python-dq-el python-dq-is python-dq-max python-dq-new python-dq-set! python-dq-set-max!
  python-drop python-drop-last python-els-count python-els-drop-at python-els-index
  python-els-insert-at python-els-repeat python-els-set-at python-eq python-in-walk
  python-init-receiver! python-iter-elems python-length python-list-cat python-list-clamp
  python-list-new python-native-of python-num-py-type python-opt python-repr-of python-reverse
  python-sig! python-str python-sweep! python-takes-at-most! python-type-of)
(import python/array python-take-n)

; deque([1, 2]), and deque([1, 2], maxlen=3) when there is a bound; a subclass
; prints under its own name in place of deque.
(def %py-dq-named-repr
  (fn (_ name v)
    (Str8 append name
      (Str8 append "("
        (Str8 append (python-repr-of (python-list-new (python-dq-el v)))
          (if (null? (python-dq-max v))
            ")"
            (Str8 append ", maxlen=" (Str8 append (python-str (python-dq-max v)) ")"))))))))

(def python-dq-repr (fn (_ v) (%py-dq-named-repr "deque" v)))

; --- the ends ----------------------------------------------------------------------

; A bound deque keeps the maxlen elements nearest the end just written to:
; keep-right? says which end that was.
(def %py-dq-fit
  (fn (_ v l keep-right?)
    (let ((m (python-dq-max v)))
      (if (null? m)
        l
        (let ((over (- (python-length l) m)))
          (match
            ((<= over 0) l)
            (keep-right? (python-drop l over))
            (#t (python-take-n l m ()))))))))

(def %py-dq-append!
  (fn (_ v x) (python-dq-set! v (%py-dq-fit v (python-list-cat (python-dq-el v) (list x)) #t))))

(def %py-dq-appendleft!
  (fn (_ v x) (python-dq-set! v (%py-dq-fit v (pair x (python-dq-el v)) #f))))

; extend is append once per element, and extendleft appendleft, which is why
; extendleft reverses what it is given.
(def python-dq-extend!
  (fn (_ v src)
    (python-dq-set! v (%py-dq-fit v (python-list-cat (python-dq-el v) (python-iter-elems src)) #t))))

(def %py-dq-extendleft!
  (fn (_ v src)
    (python-dq-set! v
      (%py-dq-fit v (python-list-cat (python-reverse (python-iter-elems src)) (python-dq-el v)) #f))))

(def %py-dq-nonempty!
  (fn (_ v)
    (if (null? (python-dq-el v)) (Err raise (lit index) "pop from an empty deque" ()) ())))

(def %py-dq-popleft!
  (fn (_ v)
    (%seq (%py-dq-nonempty! v)
      (let ((el (python-dq-el v)))
        (%seq (python-dq-set! v (rest el)) (first el))))))

(def %py-dq-pop!
  (fn (_ v)
    (%seq (%py-dq-nonempty! v)
      (let ((el (python-dq-el v)))
        (%seq (python-dq-set! v (python-drop-last el)) (List ref (- (python-length el) 1) el))))))

; --- by position -------------------------------------------------------------------

; An index is an int, counted from the end when it is negative.
(def %py-dq-pos
  (fn (_ v i)
    (let ((k (python-boolnorm i)) (n (python-length (python-dq-el v))))
      (if (eq? (python-num-py-type k) (lit int))
        (let ((p (if (< k 0) (+ n k) k)))
          (if (if (< p 0) #t (>= p n))
            (Err raise (lit index) "deque index out of range" ())
            p))
        (Err raise (lit type)
          (Str8 append "sequence index must be integer, not '"
            (Str8 append (python-class-name (python-type-of i)) "'")) ())))))

(def python-dq-at (fn (_ v i) (List ref (%py-dq-pos v i) (python-dq-el v))))

(def python-dq-put!
  (fn (_ v i x)
    (let ((p (%py-dq-pos v i))) (python-dq-set! v (python-els-set-at (python-dq-el v) p x)))))

(def python-dq-del!
  (fn (_ v i)
    (let ((p (%py-dq-pos v i))) (python-dq-set! v (python-els-drop-at (python-dq-el v) p)))))

; A bound deque that is full has no room for an insert, and says so rather than
; dropping an element from either end.
(def %py-dq-insert!
  (fn (_ v i x)
    (let ((el (python-dq-el v)) (m (python-dq-max v)))
      (if (if (null? m) #f (>= (python-length el) m))
        (Err raise (lit index) "deque already at its maximum size" ())
        (python-dq-set! v (python-els-insert-at el (python-list-clamp (python-length el) i 0) x))))))

; index(x[, start[, stop]])
(def %py-dq-index
  (fn (_ v x . more)
    (let ((el (python-dq-el v)))
      (let ((n (python-length el)))
        (let ((lo (if (null? more) 0 (python-list-clamp n (first more) 0)))
              (hi (if (if (null? more) #t (null? (rest more)))
                    n
                    (python-list-clamp n (first (rest more)) n))))
          (let ((k (python-els-index (python-drop el lo) lo hi x)))
            (if (< k 0)
              (Err raise (lit value) "deque.index(x): x not in deque" ())
              k)))))))

(def %py-dq-remove!
  (fn (_ v x)
    (let ((el (python-dq-el v)))
      (let ((k (python-els-index el 0 (python-length el) x)))
        (if (< k 0)
          (Err raise (lit value) "deque.remove(x): x not in deque" ())
          (python-dq-set! v (python-els-drop-at el k)))))))

; rotate(n): the last n elements move to the front, and a negative n moves the
; first ones to the back.
(def %py-dq-rotate!
  (fn (_ v . more)
    (let ((el (python-dq-el v)))
      (let ((n (python-length el)))
        (if (= n 0)
          ()
          (let ((k (Num modulo (python-boolnorm (if (null? more) 1 (first more))) n)))
            (python-dq-set! v (python-list-cat (python-drop el (- n k)) (python-take-n el (- n k) ())))))))))

; --- as a whole ----------------------------------------------------------------------

; Equal when both are deques holding equal elements in the same order; the
; bound is not compared, and a deque is never equal to a list.
(def python-dq-eq
  (fn (_ a b)
    (if (if (python-dq-is a) (python-dq-is b) #f)
      (python-eq (python-list-new (python-dq-el a)) (python-list-new (python-dq-el b)))
      #f)))

; deque + deque and deque * n are new deques, bound as the left one is.
(def python-dq-cat
  (fn (_ a b)
    (if (python-dq-is b)
      (let ((v (python-dq-new (python-dq-max a) ())))
        (%seq (python-dq-set! v (%py-dq-fit v (python-list-cat (python-dq-el a) (python-dq-el b)) #t)) v))
      (Err raise (lit type)
        (Str8 append "can only concatenate deque (not \""
          (Str8 append (python-class-name (python-type-of b)) "\") to deque")) ()))))

(def python-dq-repeat
  (fn (_ a k)
    (let ((n (python-boolnorm k)))
      (if (eq? (python-num-py-type n) (lit int))
        (let ((v (python-dq-new (python-dq-max a) ())))
          (%seq (python-dq-set! v (%py-dq-fit v (python-els-repeat (python-dq-el a) n ()) #t)) v))
        (Err raise (lit type) "can't multiply sequence by non-int" ())))))

(python-sweep!)
; --- the surfaces ----------------------------------------------------------------------

(def python-dq-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "append") (fn (_ x) (%py-dq-append! v x)))
      ((Str8 =? name "appendleft") (fn (_ x) (%py-dq-appendleft! v x)))
      ((Str8 =? name "pop") (fn (_) (%py-dq-pop! v)))
      ((Str8 =? name "popleft") (fn (_) (%py-dq-popleft! v)))
      ((Str8 =? name "extend") (fn (_ src) (python-dq-extend! v src)))
      ((Str8 =? name "extendleft") (fn (_ src) (%py-dq-extendleft! v src)))
      ((Str8 =? name "insert") (fn (_ i x) (%py-dq-insert! v i x)))
      ((Str8 =? name "remove") (fn (_ x) (%py-dq-remove! v x)))
      ((Str8 =? name "index") (fn (_ x . more) (apply %py-dq-index (pair v (pair x more)))))
      ((Str8 =? name "count") (fn (_ x) (python-els-count (python-dq-el v) x 0)))
      ((Str8 =? name "rotate") (fn (_ . more) (apply %py-dq-rotate! (pair v more))))
      ((Str8 =? name "reverse") (fn (_) (python-dq-set! v (python-reverse (python-dq-el v)))))
      ((Str8 =? name "clear") (fn (_) (python-dq-set! v ())))
      ((Str8 =? name "copy") (fn (_) (python-dq-new (python-dq-max v) (python-dq-el v))))
      ((Str8 =? name "maxlen") (python-dq-max v))
      (#t (python-class-row-attr python-cls-deque v name "collections.deque")))))

; deque(iterable=(), maxlen=None).  The bound is None or an int no less than 0.
(def %py-dq-bound
  (fn (_ m)
    (let ((k (python-boolnorm m)))
      (match
        ((null? k) ())
        ((same? k python-dflt) ())
        ((not (eq? (python-num-py-type k) (lit int))) (Err raise (lit type) "an integer is required" ()))
        ((< k 0) (Err raise (lit value) "maxlen must be non-negative" ()))
        (#t k)))))

(def %py-deque-ctor
  (fn (_ . a)
    (%seq (python-takes-at-most! "deque" 2 (python-length a))
      (let ((v (python-dq-new
                 (%py-dq-bound (if (if (null? a) #t (null? (rest a))) () (first (rest a))))
                 ())))
        (%seq
          (if (if (null? a) #t (same? (first a) python-dflt)) () (python-dq-extend! v (first a)))
          v)))))

; deque.__init__(iterable, maxlen) sets the bound, empties the deque and extends
; it from the iterable, as in Python.
(def %py-deque-init
  (python-sig!
    (fn (_ o . more)
      (let ((v (python-native-of o)))
        (if (not (python-dq-is v))
          (python-init-receiver! "collections.deque" o)
          (let ((it (python-opt more 0 python-dflt)))
            (%seq (python-takes-at-most! "deque" 2 (python-length more))
              (%seq (python-dq-set-max! v (%py-dq-bound (python-opt more 1 ())))
                (%seq (python-dq-set! v ())
                  (%seq (if (same? it python-dflt) () (python-dq-extend! v it)) ()))))))))
    "__init__" (list "self" "iterable" "maxlen") 1 #f () () #t))

; A deque subclass prints under its own name.
(def %py-dq-class-repr
  (fn (_ o) (%py-dq-named-repr (python-class-name (python-type-of o)) (python-native-of o))))

; The class a subclass inherits from.  The named methods reach a subclass
; instance through the value it carries; these are the ones a dunder lookup
; asks the class for.
(def %py-dq-methods
  (list
    (pair "%ctor" (python-sig! %py-deque-ctor "deque" (list "iterable" "maxlen") 0 #f))
    (pair "__init__" %py-deque-init)
    (pair "__len__" (fn (_ o) (python-length (python-dq-el (python-native-of o)))))
    (pair "__getitem__" (fn (_ o i) (python-dq-at (python-native-of o) i)))
    (pair "__setitem__" (fn (_ o i x) (python-dq-put! (python-native-of o) i x)))
    (pair "__delitem__" (fn (_ o i) (python-dq-del! (python-native-of o) i)))
    (pair "__iter__" (fn (_ o) (python-list-new (python-dq-el (python-native-of o)))))
    (pair "__contains__" (fn (_ o x) (python-in-walk x (python-dq-el (python-native-of o)))))
    (pair "__eq__" (fn (_ o other) (python-dq-eq (python-native-of o) (python-native-of other))))
    (pair "__repr__" %py-dq-class-repr)
    (pair "__str__" %py-dq-class-repr)))

(def python-cls-deque
  (python-class-new "deque" python-cls-object %py-dq-methods "collections.deque"))

(provide python/deque
  python-cls-deque python-dq-at python-dq-attr python-dq-cat python-dq-del! python-dq-eq
  python-dq-extend! python-dq-put! python-dq-repeat python-dq-repr)
