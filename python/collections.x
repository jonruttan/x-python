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
(import python/deque %py-cls-deque)

; --- namedtuple --------------------------------------------------------------

; The declared field names, as the platform strings a method table is keyed
; by: a list, a tuple, or one string of names separated by spaces.
(def %py-nt-split
  (fn (self s n i start acc)
    (def cut (fn (_ acc) (if (> i start) (pair (Str8 sub start (- i start) s) acc) acc)))
    (match
      ((>= i n) (%py-reverse (cut acc)))
      ((= (%py-char-code (%str-ref s i)) 32) (self s n (+ i 1) (+ i 1) (cut acc)))
      (#t (self s n (+ i 1) start acc)))))

(def %py-nt-strs
  (fn (self vs acc)
    (if (null? vs) (%py-reverse acc) (self (rest vs) (pair (%py-text->x (first vs)) acc)))))

(def %py-nt-names
  (fn (_ v)
    (match
      ((%py-str-is v)
        (let ((s (%ps->x (%py-str-cps v)))) (%py-nt-split s (%py-byte-len s) 0 0 ())))
      ((%py-list? v) (%py-nt-strs (%py-list-elems v) ()))
      ((%py-tuple-is v) (%py-nt-strs (%py-tuple-elems v) ()))
      (#t
        (Err raise (lit type)
          "namedtuple() field names must be a string or an iterable of strings" ())))))

; A field reads its own position out of the instance's tuple, so it is a
; property: the class holds the position, the instance holds the values.
(def %py-nt-getter
  (fn (_ i) (%py-desc-new (lit property) (fn (_ o) (List ref i (%py-tuple-elems (%py-obj-native o)))))))

(def %py-nt-fields
  (fn (self names i acc)
    (if (null? names)
      (%py-reverse acc)
      (self (rest names) (+ i 1) (pair (pair (first names) (%py-nt-getter i)) acc)))))

(def %py-nt-str-elems
  (fn (self names acc)
    (if (null? names) (%py-reverse acc) (self (rest names) (pair (%py-str-of-x (first names)) acc)))))

(def %py-nt-rows
  (fn (self names vals acc)
    (if (null? names)
      (%py-reverse acc)
      (self (rest names) (rest vals)
        (pair (pair (%py-str-of-x (first names)) (first vals)) acc)))))

; Name(field=value, ...), which is what CPython prints; an empty one is Name().
(def %py-nt-repr-body
  (fn (self names vals lead acc)
    (if (null? names)
      acc
      (self (rest names) (rest vals) ", "
        (Str8 append acc
          (Str8 append lead
            (Str8 append (first names) (Str8 append "=" (%py-repr-of (first vals))))))))))

(def %py-nt-repr
  (fn (_ name names)
    (fn (_ o)
      (Str8 append name
        (Str8 append "("
          (Str8 append (%py-nt-repr-body names (%py-tuple-elems (%py-obj-native o)) "" "") ")"))))))

(def %py-nt-arity!
  (fn (_ name want got)
    (Err raise (lit type)
      (Str8 append name
        (Str8 append "() takes " (Str8 append (%py-str want)
          (Str8 append " arguments but " (Str8 append (%py-str got) " were given")))))
      ())))

; The positional door.  A keyword call arrives here too, already ordered by
; the signature registered below, which is what answers for a missing, a
; repeated or an unknown field name.
(def %py-nt-ctor
  (fn (_ cls name n)
    (fn (_ . args)
      (if (= (%py-length args) n)
        (let ((o (%py-obj-new cls)))
          (%seq (%py-obj-native! o (%py-tuple-new args)) o))
        (%py-nt-arity! name n (%py-length args))))))

(def %py-nt-methods
  (fn (_ cls name names n)
    (%py-list-cat
      (list
        (pair "%ctor" (%py-sig! (%py-nt-ctor cls name n) name names n #f))
        (pair "_fields" (%py-tuple-new (%py-nt-str-elems names ())))
        ; a def binds as a method and a builtin does not, so the ones that
        ; take the instance say which they are
        (pair "_asdict"
          (%py-sig!
            (fn (_ o) (%py-dict-new (%py-nt-rows names (%py-tuple-elems (%py-obj-native o)) ())))
            "_asdict" (list "self") 1 #f () () #t))
        ; tuple states a __str__ of its own, so a subclass that wants its
        ; name printed has to say both
        (pair "__repr__" (%py-nt-repr name names))
        (pair "__str__" (%py-nt-repr name names))
        ; tuple carries no __mul__ of its own, and a namedtuple repeats into
        ; a plain tuple as any other does
        (pair "__mul__" (fn (_ o k) (%py-mul (%py-obj-native o) k)))
        (pair "__rmul__" (fn (_ o k) (%py-mul (%py-obj-native o) k)))
        ; the fields are read-only, which is most of what makes this a tuple
        (pair "__setattr__"
          (%py-sig!
            (fn (_ o nm v)
              (Err raise (lit attribute)
                (Str8 append "can't set attribute '" (Str8 append (%py-text->x nm) "'")) ()))
            "__setattr__" (list "self" "name" "value") 3 #f () () #t)))
      (%py-nt-fields names 0 ()))))

; The class itself.  A qualified name is what it prints as; sys.version_info
; is one, named version_info and printed as sys.version_info(major=3, ...).
(def %py-namedtuple-class
  (fn (_ name qualname names)
    (let ((cls (%py-class-new name %py-cls-tuple () qualname)))
      (%seq
        (%py-class-methods-set! cls (%py-nt-methods cls qualname names (%py-length names)))
        cls))))

(def %py-namedtuple
  (fn (_ nm fields)
    (let ((name (%py-text->x nm)))
      (%py-namedtuple-class name name (%py-nt-names fields)))))

; --- OrderedDict -------------------------------------------------------------

(def %py-cls-OrderedDict ())

(def %py-od-is
  (fn (_ v) (if (%py-obj-is v) (%py-subclass? (%py-obj-class v) %py-cls-OrderedDict) #f)))

; Two OrderedDicts are equal when they carry the same pairs IN THE SAME ORDER,
; which is the one promise an ordinary dict does not make.
(def %py-od-eq-rows
  (fn (self a b)
    (match
      ((null? a) (null? b))
      ((null? b) #f)
      ((not (%py-eq (first (first a)) (first (first b)))) #f)
      ((not (%py-eq (rest (first a)) (rest (first b)))) #f)
      (#t (self (rest a) (rest b))))))

; OrderedDict({'a': 1}), or a subclass's own name in its place; an empty one
; prints as OrderedDict().
(def %py-od-repr
  (fn (_ o)
    (let ((d (%py-obj-native o)) (name (%py-class-name (%py-obj-class o))))
      (if (null? (%py-dict-entries d))
        (Str8 append name "()")
        (Str8 append name (Str8 append "(" (Str8 append (%py-repr-of d) ")")))))))

; No constructor of its own: an OrderedDict is built as any dict subclass is,
; by dict's constructor and dict's __init__, keywords included.
(def %py-od-methods
  (list
    (pair "__eq__"
      (fn (_ o other)
        (if (%py-od-is other)
          (%py-od-eq-rows (%py-dict-entries (%py-obj-native o))
                          (%py-dict-entries (%py-obj-native other)))
          (%py-eq (%py-obj-native o) (%py-native-of other)))))
    ; dict states a __str__ of its own, so the name is said in both seats
    (pair "__repr__" %py-od-repr)
    (pair "__str__" %py-od-repr)))

(set! %py-cls-OrderedDict
  (%py-class-new "OrderedDict" %py-cls-dict %py-od-methods "OrderedDict"))

; --- the module --------------------------------------------------------------

(def %py-collections-module
  (fn (_)
    (%py-module-new "collections"
      (list
        (pair "namedtuple" (%py-sig! %py-namedtuple "namedtuple" (list "typename" "field_names") 2 #f))
        (pair "OrderedDict" %py-cls-OrderedDict)
        (pair "deque" %py-cls-deque)))))

(provide python/collections %py-collections-module %py-namedtuple-class)
