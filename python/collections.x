; # x-python -- Python on x-lang
;
; ## python/collections.x -- the collections module
;
; @description namedtuple and OrderedDict, as ordinary classes over the tuple
;   and the dict this runtime already has: a namedtuple instance carries a
;   tuple and an OrderedDict instance a dict, so both inherit their whole
;   sequence and mapping surface from the builtin type object they derive
;   from.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A dict here keeps insertion order already: a new key goes on the end of the
; entry list and popitem takes the last one.  OrderedDict therefore adds only
; what the ordinary dict does not promise -- an equality that counts order,
; and its own repr.

(module python/collections)
(import python/core
  ps->x python-byte-len python-char-code python-class-methods-set! python-class-name
  python-class-new python-cls-dict python-cls-tuple python-desc-new python-dict-entries
  python-dict-new python-eq python-length python-list-cat python-list-elems python-list?
  python-module-new python-mul python-native-of python-obj-class python-obj-is python-obj-native
  python-obj-native! python-obj-new python-repr-of python-reverse python-sig! python-str python-str-cps
  python-str-is python-str-of-x python-subclass? python-sweep! python-text->x python-tuple-elems
  python-tuple-is python-tuple-new)
(import python/deque python-cls-deque)

; --- namedtuple --------------------------------------------------------------

; The declared field names, as the platform strings a method table is keyed
; by: a list, a tuple, or one string of names separated by spaces.
(def %py-nt-split
  (fn (self s n i start acc)
    (def cut (fn (_ acc) (if (> i start) (pair (Str8 sub start (- i start) s) acc) acc)))
    (match
      ((>= i n) (python-reverse (cut acc)))
      ((= (python-char-code (%str-ref s i)) 32) (self s n (+ i 1) (+ i 1) (cut acc)))
      (#t (self s n (+ i 1) start acc)))))

(def %py-nt-strs
  (fn (self vs acc)
    (if (null? vs) (python-reverse acc) (self (rest vs) (pair (python-text->x (first vs)) acc)))))

(def %py-nt-names
  (fn (_ v)
    (match
      ((python-str-is v)
        (let ((s (ps->x (python-str-cps v)))) (%py-nt-split s (python-byte-len s) 0 0 ())))
      ((python-list? v) (%py-nt-strs (python-list-elems v) ()))
      ((python-tuple-is v) (%py-nt-strs (python-tuple-elems v) ()))
      (#t
        (Err raise (lit type)
          "namedtuple() field names must be a string or an iterable of strings" ())))))

; A field reads its own position out of the instance's tuple, so it is a
; property: the class holds the position, the instance holds the values.
(def %py-nt-getter
  (fn (_ i) (python-desc-new (lit property) (fn (_ o) (List ref i (python-tuple-elems (python-obj-native o)))))))

(def %py-nt-fields
  (fn (self names i acc)
    (if (null? names)
      (python-reverse acc)
      (self (rest names) (+ i 1) (pair (pair (first names) (%py-nt-getter i)) acc)))))

(def %py-nt-str-elems
  (fn (self names acc)
    (if (null? names) (python-reverse acc) (self (rest names) (pair (python-str-of-x (first names)) acc)))))

(def %py-nt-rows
  (fn (self names vals acc)
    (if (null? names)
      (python-reverse acc)
      (self (rest names) (rest vals)
        (pair (pair (python-str-of-x (first names)) (first vals)) acc)))))

; Name(field=value, ...), which is what CPython prints; an empty one is Name().
(def %py-nt-repr-body
  (fn (self names vals lead acc)
    (if (null? names)
      acc
      (self (rest names) (rest vals) ", "
        (Str8 append acc
          (Str8 append lead
            (Str8 append (first names) (Str8 append "=" (python-repr-of (first vals))))))))))

(def %py-nt-repr
  (fn (_ name names)
    (fn (_ o)
      (Str8 append name
        (Str8 append "("
          (Str8 append (%py-nt-repr-body names (python-tuple-elems (python-obj-native o)) "" "") ")"))))))

(def %py-nt-arity!
  (fn (_ name want got)
    (Err raise (lit type)
      (Str8 append name
        (Str8 append "() takes " (Str8 append (python-str want)
          (Str8 append " arguments but " (Str8 append (python-str got) " were given")))))
      ())))

; The positional door.  A keyword call arrives here too, already ordered by
; the signature registered below, which is what answers for a missing, a
; repeated or an unknown field name.
(def %py-nt-ctor
  (fn (_ cls name n)
    (fn (_ . args)
      (if (= (python-length args) n)
        (let ((o (python-obj-new cls)))
          (%seq (python-obj-native! o (python-tuple-new args)) o))
        (%py-nt-arity! name n (python-length args))))))

(def %py-nt-methods
  (fn (_ cls name names n)
    (python-list-cat
      (list
        (pair "%ctor" (python-sig! (%py-nt-ctor cls name n) name names n #f))
        (pair "_fields" (python-tuple-new (%py-nt-str-elems names ())))
        ; a def binds as a method and a builtin does not, so the ones that
        ; take the instance say which they are
        (pair "_asdict"
          (python-sig!
            (fn (_ o) (python-dict-new (%py-nt-rows names (python-tuple-elems (python-obj-native o)) ())))
            "_asdict" (list "self") 1 #f () () #t))
        ; tuple states a __str__ of its own, so a subclass that wants its
        ; name printed has to say both
        (pair "__repr__" (%py-nt-repr name names))
        (pair "__str__" (%py-nt-repr name names))
        ; tuple carries no __mul__ of its own, and a namedtuple repeats into
        ; a plain tuple as any other does
        (pair "__mul__" (fn (_ o k) (python-mul (python-obj-native o) k)))
        (pair "__rmul__" (fn (_ o k) (python-mul (python-obj-native o) k)))
        ; the fields are read-only, which is most of what makes this a tuple
        (pair "__setattr__"
          (python-sig!
            (fn (_ o nm v)
              (Err raise (lit attribute)
                (Str8 append "can't set attribute '" (Str8 append (python-text->x nm) "'")) ()))
            "__setattr__" (list "self" "name" "value") 3 #f () () #t)))
      (%py-nt-fields names 0 ()))))

; The class itself.  A qualified name is what it prints as; sys.version_info
; is one, named version_info and printed as sys.version_info(major=3, ...).
(def python-namedtuple-class
  (fn (_ name qualname names)
    (let ((cls (python-class-new name python-cls-tuple () qualname)))
      (%seq
        (python-class-methods-set! cls (%py-nt-methods cls qualname names (python-length names)))
        cls))))

(def %py-namedtuple
  (fn (_ nm fields)
    (let ((name (python-text->x nm)))
      (python-namedtuple-class name name (%py-nt-names fields)))))

; --- OrderedDict -------------------------------------------------------------

(def %py-cls-OrderedDict ())

(def %py-od-is
  (fn (_ v) (if (python-obj-is v) (python-subclass? (python-obj-class v) %py-cls-OrderedDict) #f)))

; Two OrderedDicts are equal when they carry the same pairs IN THE SAME ORDER,
; which is the one promise an ordinary dict does not make.
(def %py-od-eq-rows
  (fn (self a b)
    (match
      ((null? a) (null? b))
      ((null? b) #f)
      ((not (python-eq (first (first a)) (first (first b)))) #f)
      ((not (python-eq (rest (first a)) (rest (first b)))) #f)
      (#t (self (rest a) (rest b))))))

; OrderedDict({'a': 1}), or a subclass's own name in its place; an empty one
; prints as OrderedDict().
(def %py-od-repr
  (fn (_ o)
    (let ((d (python-obj-native o)) (name (python-class-name (python-obj-class o))))
      (if (null? (python-dict-entries d))
        (Str8 append name "()")
        (Str8 append name (Str8 append "(" (Str8 append (python-repr-of d) ")")))))))

; No constructor of its own: an OrderedDict is built as any dict subclass is,
; by dict's constructor and dict's __init__, keywords included.
(def %py-od-methods
  (list
    (pair "__eq__"
      (fn (_ o other)
        (if (%py-od-is other)
          (%py-od-eq-rows (python-dict-entries (python-obj-native o))
                          (python-dict-entries (python-obj-native other)))
          (python-eq (python-obj-native o) (python-native-of other)))))
    ; dict states a __str__ of its own, so the name is said in both seats
    (pair "__repr__" %py-od-repr)
    (pair "__str__" %py-od-repr)))

(set! %py-cls-OrderedDict
  (python-class-new "OrderedDict" python-cls-dict %py-od-methods "OrderedDict"))

(python-sweep!)
; --- the module --------------------------------------------------------------

(def python-collections-module
  (fn (_)
    (python-module-new "collections"
      (list
        (pair "namedtuple" (python-sig! %py-namedtuple "namedtuple" (list "typename" "field_names") 2 #f))
        (pair "OrderedDict" %py-cls-OrderedDict)
        (pair "deque" python-cls-deque)))))

(provide python/collections python-collections-module python-namedtuple-class)
