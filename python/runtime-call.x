; # x-python -- Python on x-lang
;
; ## python/runtime-call.x -- keyword calls, super, sets, and the rendering builtins
;
; @description Calling with keywords against a signature registry, super()'s MRO
;   walk, the set surface, and the builtins that render or inspect.
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

; --- Keyword calls -----------------------------------------------------------
;
; A PYTHON FUNCTION IS A PLAIN x CLOSURE, and a closure does not know its
; parameter names.  So every def registers its signature here, keyed by the
; closure itself -- (name names nreq has-rest) -- and a keyword call looks it
; up, arranges the keywords into positional slots, and applies.  A slot left
; empty between given arguments carries %py-dflt, which the callee's %py-opt
; prelude reads as "take the default".
(def %py-sig-of
  (fn (_ f)
    (def go
      (fn (self rows)
        (if (null? rows) ()
          ; same?, NOT eq?: eq? compares the value slot, and every closure's
          ; is the same, so eq? calls any two functions equal
          (if (same? (first (first rows)) f) (rest (first rows)) (self (rest rows))))))
    (go (first %py-sigs))))
; a method's signature seen from its object: self is already supplied
(def %py-sig-shift
  ; A METHOD'S SIGNATURE WITHOUT ITS self, for a call through the class.  The
  ; **name travels with it: dropping the field here is how `C(1, k=2)` came
  ; back saying __init__ got an unexpected keyword argument it had declared.
  (fn (_ sig)
    (list (first sig) (rest (List ref 1 sig)) (- (List ref 2 sig) 1)
      (List ref 3 sig)
      (if (> (%py-length sig) 4) (List ref 4 sig) ())
      (if (> (%py-length sig) 5) (List ref 5 sig) ())
      (if (> (%py-length sig) 6) (List ref 6 sig) ()))))
(def %py-drop
  (fn (self l k) (if (= k 0) l (if (null? l) () (self (rest l) (- k 1))))))
(def %py-list-cat
  (fn (self a b) (if (null? a) b (pair (first a) (self (rest a) b)))))
; f() takes from NREQ to N positional arguments but M were given -- or, with
; no defaults, f() takes N positional arguments but M were given.  `more` is
; the tail past the required names, without the keyword box.
(def %py-arity!
  (fn (_ fname more0 nreq ndflts)
    (let ((more (%py-args-strip-kw (%py-drop more0 nreq))))
      (if (> (%py-length more) ndflts)
        (Err raise (lit type)
          (Str8 append fname
            (Str8 append (%py-takes-text nreq ndflts)
              (%py-given-text (+ nreq (%py-length more)))))
          ())
        ()))))
(def %py-takes-text
  (fn (_ nreq ndflts)
    (if (= ndflts 0)
      (Str8 append "() takes "
        (Str8 append (%py-str nreq)
          (if (= nreq 1) " positional argument but " " positional arguments but ")))
      (Str8 append "() takes from "
        (Str8 append (%py-str nreq)
          (Str8 append " to "
            (Str8 append (%py-str (+ nreq ndflts)) " positional arguments but ")))))))
(def %py-given-text
  (fn (_ n) (Str8 append (%py-str n) (if (= n 1) " was given" " were given"))))
(def %py-kw-error
  (fn (_ fname msg)
    (Err raise (lit type) (Str8 append (Str8 append fname "() ") msg) ())))
(def %py-kw-args
  (fn (_ sig pos kws)
    (def fname (first sig))
    (def names (List ref 1 sig))
    (def nreq (List ref 2 sig))
    (def has-rest (List ref 3 sig))
    ; the **name this function declares, if it declares one
    (def kwname (if (> (%py-length sig) 4) (List ref 4 sig) ()))
    ; the keyword-only names: never filled by position, and read from the
    ; box by the callee's prelude
    (def kwonly (if (> (%py-length sig) 5) (List ref 5 sig) ()))
    (def n (%py-length names))
    (def npos (%py-length pos))
    (def known?
      (fn (self k ns)
        (if (null? ns) #f (if (Str8 =? k (first ns)) #t (self k (rest ns))))))
    (def check
      (fn (self ks)
        (match
          ((null? ks) ())
          ((known? (first (first ks)) names) (self (rest ks)))
          ((known? (first (first ks)) kwonly) (self (rest ks)))
          ; A FUNCTION THAT DECLARES **kwargs TAKES THE REST rather than
          ; refusing them, which is the whole point of declaring it.
          ((null? kwname)
            (%py-kw-error fname
              (Str8 append (Str8 append "got an unexpected keyword argument '" (first (first ks))) "'")))
          (#t (self (rest ks))))))
    ; the keywords no parameter claimed, as dict rows
    (def spare
      (fn (self ks acc)
        (if (null? ks)
          (%py-reverse acc)
          (if (known? (first (first ks)) names)
            (self (rest ks) acc)
            ; the name crosses over: these rows become the **kwargs DICT, and
            ; a dict's keys are strs (see %py-dict-kwargs)
            (self (rest ks)
              (pair (pair (%py-str-of-x (first (first ks))) (rest (first ks))) acc))))))
    (def slot
      (fn (_ i)
        (let ((nm (List ref i names)))
          (let ((kw (%py-alist-find nm kws)))
            (if (null? kw)
              (if (< i npos)
                (List ref i pos)
                (if (< i nreq)
                  (%py-kw-error fname
                    (Str8 append (Str8 append "missing 1 required positional argument: '" nm) "'"))
                  %py-dflt))
              (if (< i npos)
                (%py-kw-error fname
                  (Str8 append (Str8 append "got multiple values for argument '" nm) "'"))
                (rest kw)))))))
    (def build
      (fn (self i acc)
        (if (>= i n) (%py-reverse acc) (self (+ i 1) (pair (slot i) acc)))))
    (check kws)
    (if (if (> npos n) (not has-rest) #f)
      (Err raise (lit type)
        (Str8 append fname
          (Str8 append (%py-takes-text n 0) (%py-given-text npos)))
        ())
      (let ((base (%py-list-cat (build 0 ()) (%py-drop pos n))))
        (if (if (null? kwname) (null? kwonly) #f)
          base
          ; the box goes last, where the prelude reads it
          (%py-list-cat base (list (%py-kwbox (%py-dict-new (spare kws ()))))))))))
; The keyword list a call sends, with every `**d` merged onto what was written
; by name.  A later spelling wins, which is what Python does when a name is
; given twice by different spellings.
(def %py-kw-spread
  (fn (_ written dicts)
    (%py-kw-spread-go written dicts)))
(def %py-kw-spread-go
  (fn (self acc dicts)
    (if (null? dicts)
      acc
      (self (%py-kw-put-rows acc (%py-mapping-rows (first dicts))) (rest dicts)))))
; The rows of a `**` argument: a dict's entries, or for any other object the
; mapping protocol -- each key from keys(), its value by subscript.
(def %py-mapping-rows
  (fn (_ d)
    (if (%py-dict? d)
      (%py-dict-entries d)
      (%py-rows-by-key d (%py-iter-elems ((%py-getattr d "keys"))) ()))))
(def %py-rows-by-key
  (fn (self d keys acc)
    (if (null? keys) (%py-reverse acc)
      (self d (rest keys) (pair (pair (first keys) (%py-index d (first keys))) acc)))))
; A `**dict` key is a str and a keyword name is the platform's string, so the
; key crosses over on the way in.  A name already given -- by an earlier `**`
; or written out -- is a TypeError, as in Python.
(def %py-kw-put-rows
  (fn (self acc rows)
    (if (null? rows)
      acc
      (let ((k (first (first rows))))
        (if (not (%py-str-is k))
          (Err raise (lit type) "keywords must be strings" ())
          (let ((name (%ps->x (%py-str-cps k))))
            (if (not (null? (%py-alist-find name acc)))
              (Err raise (lit type)
                (Str8 append "got multiple values for keyword argument '"
                  (Str8 append name "'")) ())
              (self (%py-attr-put acc name (rest (first rows))) (rest rows)))))))))

(def %py-kwcall
  (fn (_ f pos kws)
    (match
      ((same? f %py-print) (%py-print-kw pos kws))
      ((if (same? f %py-min) #t (same? f %py-max)) (%py-minmax-kw f pos kws))
      ; dict(a=1): the keywords are the entries.  A subclass whose constructor
      ; is dict's and that writes no __init__ is built from that dict, the way
      ; D({"a": 1}) is.
      ((if (%py-class-is f)
         (if (same? (%py-inherited-ctor f) %py-dict-ctor) (not (%py-init-below-ctor? f)) #f)
         #f)
        (let ((d (if (null? pos) (%py-dict-new ()) (%py-dict-ctor (first pos)))))
          (%seq (%py-dict-merge! d (%py-dict-new (%py-dict-kwargs kws)))
            (if (same? f %py-cls-dict) d (%py-instantiate f (list d))))))
      ((%py-class-is f)
        (let ((ctor (%py-alist-find "%ctor" (%py-class-methods f))))
          (let ((csig (if (null? ctor) () (%py-sig-of (rest ctor)))))
            (if (not (null? csig))
              (apply (rest ctor) (%py-kw-args csig pos kws))
              (let ((init (%py-method-find f "__init__")))
                (let ((sig (if (null? init) () (%py-sig-of init))))
                  (if (null? sig)
                    (Err raise (lit type)
                      (Str8 append (%py-class-name f) "() takes no keyword arguments") ())
                    ; the class's own call door, not apply: apply wants a closure
                    (%py-instantiate f (%py-kw-args (%py-sig-shift sig) pos kws)))))))))
      ; a bound method: its function's signature, with self already supplied
      ((%py-bound-is f)
        (let ((sig (%py-sig-of (%py-bound-fn f))))
          (if (null? sig)
            (Err raise (lit type) "this callable takes no keyword arguments" ())
            (apply (%py-bound-fn f)
              (pair (%py-bound-self f) (%py-kw-args (%py-sig-shift sig) pos kws))))))
      (#t
        (let ((sig (%py-sig-of f)))
          (if (null? sig)
            (Err raise (lit type) "this callable takes no keyword arguments" ())
            (apply f (%py-kw-args sig pos kws))))))))
; the str methods that take keywords, and their parameter names; a slot a
; keyword call leaves empty is None, which is every one of these defaults
(def %py-str-kw-names
  (fn (_ name)
    (if (if (Str8 =? name "split") #t (Str8 =? name "rsplit")) (list "sep" "maxsplit")
      (if (Str8 =? name "splitlines") (list "keepends")
        ()))))
(def %py-none-holes
  (fn (self l)
    (if (null? l) () (pair (if (same? (first l) %py-dflt) () (first l)) (self (rest l))))))
(def %py-kwcall-attr
  (fn (_ obj name pos kws)
    ; d.update(a=1) merges the keywords
    (match
      ((if (%py-dict? obj) (Str8 =? name "update") #f)
        (let ((d obj))
          (%seq (if (null? pos) () (%py-dict-merge! d (first pos)))
            (%py-dict-merge! d (%py-dict-new (%py-dict-kwargs kws))))))
      ((%py-list? obj)
        (let ((names (%py-list-kw-names name)))
          (if (null? names)
            (Err raise (lit type)
              (Str8 append (Str8 append "list." name) "() takes no keyword arguments") ())
            (apply (%py-list-attr obj name)
              (%py-none-holes (%py-kw-args (list name names 0 #f) pos kws))))))
      ((%py-str-is obj)
        (if (Str8 =? name "format")
          ; the template crosses over and the result crosses back -- the brace
          ; engine works in platform strings from end to end
          (%py-str-of-x (%py-strformat-kw (%ps->x (%py-str-cps obj)) pos kws))
          (let ((names (%py-str-kw-names name)))
            (if (null? names)
              (Err raise (lit type)
                (Str8 append (Str8 append "str." name) "() takes no keyword arguments") ())
              (apply (%py-str-attr obj name)
                (%py-none-holes
                  (%py-kw-args (list (Str8 append "str." name) names 0 #f) pos kws)))))))
      ((%py-obj-is obj)
        (let ((m (%py-method-find (%py-obj-class obj) name)))
          (let ((sig (if (null? m) () (%py-sig-of m))))
            (if (null? sig)
              (%py-kwcall (%py-getattr obj name) pos kws)
              (apply m (pair obj (%py-kw-args (%py-sig-shift sig) pos kws)))))))
      ; SUPER HAS TO BE ASKED THE SAME WAY.  Reaching it through %py-getattr
      ; answers a BOUND method, and a bound method is a new closure with no
      ; signature of its own -- so `super().__init__(**kw)` came back saying
      ; the callable takes no keyword arguments, which it plainly did.
      ((%py-super-is obj)
        (let ((m (%py-method-find (%py-class-base (%py-super-from obj)) name)))
          (let ((sig (if (null? m) () (%py-sig-of m))))
            (if (null? sig)
              (%py-kwcall (%py-getattr obj name) pos kws)
              (apply m
                (pair (%py-super-self obj)
                  (%py-kw-args (%py-sig-shift sig) pos kws)))))))
      (#t (%py-kwcall (%py-getattr obj name) pos kws)))))
(def %py-splat
  (fn (_ . segs)
    (def cat
      (fn (self ss)
        (if (null? ss) ()
          (if (null? (first ss)) (self (rest ss))
            (pair (first (first ss)) (self (pair (rest (first ss)) (rest ss))))))))
    (cat segs)))
(def %py-tuple? (fn (_ v) (%py-tuple-is v)))

; UNPACKING IS A LENGTH CHECK AND A WALK.  `a, b = f()` is the reason tuples
; earn their keep -- it is how a Python function returns two things -- and
; Python is strict about the count, because a silent short walk would bind a
; name to None and fail somewhere else entirely.
(def %py-unpack-count
  (fn (self v)
    (if (%py-tuple-is v)
      (%py-length (%py-tuple-elems v))
      (if (%py-list? v)
        (%py-length (%py-list-elems v))
        (Err raise (lit type) "cannot unpack non-sequence" ())))))

(def %py-unpack
  (fn (_ v n)
    (let ((got (%py-unpack-count v)))
      (match
        ((< got n) (Err raise (lit value) "not enough values to unpack" ()))
        ((> got n) (Err raise (lit value) "too many values to unpack" ()))
        ((%py-tuple-is v) (%py-tuple-elems v))
        (#t (%py-list-elems v))))))

; --- super() -----------------------------------------------------------------
;
; `super()` STARTS FROM THE CLASS THE METHOD WAS WRITTEN IN, not from the
; instance's class.  That is Python's rule and it is not a detail: in
;
;   class Dog(Animal):
;       def speak(self): return super().speak()
;
; the instance is a Dog, so looking up `speak` from the instance's class finds
; Dog's own override and calls it again -- forever.  Starting from Dog and
; searching its BASE finds Animal's.
;
; The parser supplies the class, because Python's zero-argument `super()` is
; LEXICAL: it means the class whose body the call is written in.  Nothing about
; the object at run time can tell you that, which is why CPython gives methods a
; `__class__` cell rather than working it out from `self`.
(def %py-super
  (fn (_ cls obj)
    (if (not (%py-class-is cls))
      (Err raise (lit type) "super(): no class" ())
      (%py-super-new cls obj))))

(def %py-super-attr
  (fn (_ sup name)
    (let ((base (%py-class-base (%py-super-from sup))))
      (if (null? base)
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'super' object has no attribute '" name) "'")
          ())
        (let ((m (%py-method-find base name)))
          (match
            ((null? m)
              (Err raise (lit attribute)
                (Str8 append
                  (Str8 append "'super' object has no attribute '" name) "'")
                ()))
            ; WHAT COMES BACK THROUGH super IS WHAT COMES BACK THROUGH THE
            ; INSTANCE: a class ATTRIBUTE is its value, not a method to bind --
            ; `super().bar` where bar = 123 answered #<fn> before, because
            ; everything found was bound.  The three built-in descriptors keep
            ; their meanings here too.
            ((%py-desc-is m)
              (let ((f (%py-desc-fn m)) (k (%py-desc-kind m)))
                (if (eq? k (lit static))
                  f
                  (if (eq? k (lit classmethod))
                    (%py-bound-new f (%py-obj-class (%py-super-self sup)))
                    (f (%py-super-self sup))))))
            ((%py-desc-get? m)
              ((%py-dunder m "__get__")
                (%py-super-self sup) (%py-obj-class (%py-super-self sup))))
            ((not (%py-fn-is m)) m)
            (#t (%py-bound-new m (%py-super-self sup)))))))))

; --- Builtins that render ----------------------------------------------------
;
; `str` and `repr` need a value AS A STRING, and %py-write only emits -- the
; comment above it says so, and says why: rendering a number would need a
; number-to-string conversion this layer does not have.
;
; It does not need one.  `(prim-ref 'io 'write-to-str)` runs the writer with its
; sink redirected into a string, so a container's write handler -- and the
; callback into %py-write it makes for each element -- lands in the string
; instead of on stdout.  Nested containers come out right for free, because the
; same handlers do the same work.
;
; STRINGS ARE THE EXCEPTION, both ways.  x writes a string with double quotes;
; Python's repr uses single, and its str uses none at all.  That difference is
; the whole distinction between the two builtins, so it is stated here rather
; than pushed into the writer.
(def %py-write-to-str (prim-ref (lit io) (lit write-to-str)))

; THE INTERNAL str, AND IT ALWAYS ANSWERS A PLATFORM STRING.  Every caller is
; measuring or appending with Str8 -- an error message, a format field's
; padding and precision -- so answering the str UNCHANGED for a str argument
; (which this did) handed `Str8 length` a PY-TEXT and died with "not a string"
; in the middle of str.format.  str() the builtin is %py-str-ctor, and THAT is
; where a str argument comes back untouched, NUL and all.
;
; So a NUL-bearing str raises here, like at every other crossing: a format
; field is built as a platform string and cannot carry one.
(def %py-str
  (fn (_ v)
    (match
      ((%py-str-is v) (%ps->x (%py-str-cps v)))
      ((%py-fn-is v) (%py-fn-repr v))
      ((%py-bound-is v) (%py-bound-repr v))
      ; ALREADY TEXT, AND ALREADY THE PLATFORM'S.  A conversion has run ahead
      ; of this in the format path -- %py-fmtfield's !r and !s hand their
      ; answer on as a platform string -- and the last branch would `write` it,
      ; which QUOTES it: `f'{x=}'` came out as `x="7"`.  On main this branch
      ; did not need to exist, because a str WAS one of these.
      ((str? v) v)
      ((null? v) "None")
      ((eq? v #t) "True")
      ((eq? v #f) "False")
      ((%py-float-is v) (%py-frepr v))
      ((%py-complex-is v) (%py-crepr v))
      ; str(e) is the MESSAGE, the same rule %py-write states for print(e)
      ((Err err? v) (v msg))
      ((%py-obj-is v) (%py-text->x (%py-obj-str v)))
      (#t (%py-write-to-str v)))))

; A STRING'S repr IS PYTHON'S: single quotes unless the text holds a single
; quote and no double, backslash and the chosen quote escaped, \n \r \t by
; name, any other control character (and DEL) as \xhh, everything else as
; itself -- non-ASCII bytes pass through untouched, which is Python 3's
; choice for printable text.
(def %py-hex2
  (fn (_ n) (Str8 append (Str8 sub (Num quotient n 16) 1 "0123456789abcdef") (Str8 sub (Num modulo n 16) 1 "0123456789abcdef"))))
(def %py-str-repr
  (fn (_ v)
    (let ((l (%py-str-cps v)))
      (let ((q (if (if (%pb-in? (list 39) l) (not (%pb-in? (list 34) l)) #f) 34 39)))
        (let ((qs (%py-list->string (list (%py-int->char q)))))
          (Str8 append qs (Str8 append (%py-str-repr-go l q "") qs)))))))

; A CODE POINT SHOWS AS ITSELF unless it cannot: the quote in use, a
; backslash, the three named controls, and anything below space as \xhh --
; which is how a NUL shows, now that one can be here.  Everything from space
; up goes out as its utf-8, so a repr keeps its accents and its emoji.
(def %py-str-repr-go
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
              ; DEL IS A CONTROL CHARACTER TOO, and the note above this function
              ; always said so ("any other control character (and DEL) as
              ; \xhh") -- the test just read `< 32` and let 0x7f through as
              ; itself, which prints as nothing at all.
              ((if (< c 32) #t (= c 127)) (Str8 append "\\x" (%py-hex2 c)))
              (#t (%pb->str (%ps-enc1 c))))))))))

; <function NAME at 0xADDR>: the name is the signature's, the address is the
; identity every function already has for hashing.
(def %py-fn-repr
  (fn (_ v)
    (let ((sig (%py-sig-of v)))
      (Str8 append "<function "
        (Str8 append (if (null? sig) "?" (first sig))
          (Str8 append " at "
            (Str8 append (%py-str (%py-hex (%py-id v))) ">")))))))

; <bound method CLASS.NAME of REPR>: the class is the receiver's, or the
; receiver itself when a classmethod was bound to a class.
(def %py-bound-repr
  (fn (_ v)
    (let ((m (%py-bound-fn v)) (self (%py-bound-self v)))
      (let ((sig (%py-sig-of m)))
        (Str8 append "<bound method "
          (Str8 append
            (if (%py-class-is self) (%py-class-name self)
              (if (%py-obj-is self) (%py-class-name (%py-obj-class self)) "?"))
            (Str8 append "."
              (Str8 append (if (null? sig) "?" (first sig))
                (Str8 append " of " (Str8 append (%py-repr-of self) ">"))))))))))

; The attributes a bound method answers for: its name, its receiver, and the
; function underneath.
(def %py-bound-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "__self__") (%py-bound-self v))
      ((Str8 =? name "__func__") (%py-bound-fn v))
      ((Str8 =? name "__name__")
        (let ((sig (%py-sig-of (%py-bound-fn v))))
          (if (null? sig)
            (Err raise (lit attribute) "'method' object has no attribute '__name__'" ())
            (%py-str-of-x (first sig)))))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'method' object has no attribute '" name) "'") ())))))

(def %py-repr-of
  (fn (_ v)
    (match
      ((null? v) "None")
      ((eq? v #t) "True")
      ((eq? v #f) "False")
      ((%py-str-is v) (%py-str-repr v))
      ((%py-fn-is v) (%py-fn-repr v))
      ((%py-bound-is v) (%py-bound-repr v))
      ((%py-float-is v) (%py-frepr v))
      ((%py-complex-is v) (%py-crepr v))
      ((%py-obj-is v) (%py-text->x (%py-obj-repr v)))
      ((eq? v %py-Ellipsis) "Ellipsis")
      (#t (%py-write-to-str v)))))

; repr() the BUILTIN, against %py-repr-of the internal one -- the same split
; str() makes just above, and for the same reason: every other caller of
; %py-repr-of is appending its answer to a platform string.  A repr never
; carries a NUL out (%py-str-repr writes one as \x00), so this crossing is
; always safe.
(def %py-repr-builtin (fn (_ v) (%py-str-of-x (%py-repr-of v))))

; str(o) and repr(o) for an object: __str__ (falling back to __repr__) and
; __repr__, each answering a string; an exception instance's str is its
; message; the default is the <qualname object> form.
(def %py-obj-default-repr
  (fn (_ o)
    (if (%py-subclass? (%py-obj-class o) %py-exc-BaseException)
      (Str8 append (%py-class-name (%py-obj-class o))
        (Str8 append ": " (%py-exc-msg o)))
      (let ((n (%py-obj-native o)))
        (if (null? n)
          (Str8 append "<" (Str8 append (%py-class-qualname (%py-obj-class o)) " object>"))
          (%py-repr-of n))))))
(def %py-obj-repr
  (fn (_ o)
    (let ((m (%py-dunder o "__repr__")))
      (if (null? m) (%py-obj-default-repr o) (m)))))
(def %py-obj-str
  (fn (_ o)
    (let ((m (%py-dunder o "__str__")))
      (if (not (null? m))
        (m)
        (let ((r (%py-dunder o "__repr__")))
          (if (not (null? r))
            (r)
            (if (%py-subclass? (%py-obj-class o) %py-exc-Exception)
              (%py-exc-msg o)
              (%py-obj-default-repr o))))))))

; `list(x)` takes anything iterable, which is exactly what `for` already asks
; for -- so it is the same function, wrapped.
; --- More builtins -----------------------------------------------------------
;
; bin/hex/oct share the format engine's base conversion, so the digits and
; the bigint path are stated once.  The SIGN GOES BEFORE THE PREFIX:
; bin(-15) is -0b1111, not 0b-1111.
(def %py-based-str
  (fn (_ v base tbl pfx)
    (if (not (eq? (%py-num-kind (%py-boolnorm v)) (lit int)))
      (Err raise (lit type) "an integer is required" ())
      (let ((m (%py-fmt-base (%py-boolnorm v) base tbl)))
        ; bin/hex/oct ARE PYTHON-FACING and answer strs -- its only three
        ; callers are those builtins.  `bin(b)[:20]` slices the result, and a
        ; platform string is not a str, so the subscript fell past the string
        ; arm into the mapping one and complained "unhashable type: 'slice'"
        ; about a perfectly ordinary slice.
        (%py-str-of-x
          (Str8 append (if (first m) "-" "") (Str8 append pfx (rest m))))))))
(def %py-bin (fn (_ v) (%py-based-str v 2 "01" "0b")))
(def %py-hex (fn (_ v) (%py-based-str v 16 "0123456789abcdef" "0x")))
(def %py-oct (fn (_ v) (%py-based-str v 8 "01234567" "0o")))

(def %py-num? (fn (_ v) (not (null? (%py-num-kind (%py-boolnorm v))))))
(def %py-divmod
  (fn (_ a b)
    (if (if (%py-num? a) (%py-num? b) #f)
      (%py-tuple-new (list (%py-floordiv a b) (%py-mod a b)))
      (Err raise (lit type) "unsupported operand type(s) for divmod()" ()))))

; A CLOSURE HAS NO PREDICATE, so its type handle is taken from one built
; here and compared -- the same trick the arithmetic seams use for float.
(def %py-th-fn (%py-typeof-prim (fn (_) ())))
(def %py-fn-is (fn (_ v) (eq? (%py-typeof-prim v) %py-th-fn)))
(def %py-callable
  (fn (_ v)
    (match
      ((%py-fn-is v) #t)
      ((%py-bound-is v) #t)
      ((%py-class-is v) #t)
      ((%py-obj-is v) (not (null? (%py-dunder v "__call__"))))
      (#t #f))))

; id() is an IDENTITY TABLE, not an address: the engine hands out no
; addresses, and what Python promises is only that the number is unique and
; stable while the object lives.  Values are compared with same?, so two
; equal lists get two ids and one list gets one.
(def %py-ids (pair () ()))
(def %py-id
  (fn (_ v)
    (def go
      (fn (self rows)
        (if (null? rows) ()
          (if (same? (first (first rows)) v) (rest (first rows)) (self (rest rows))))))
    (let ((found (go (first %py-ids))))
      (if (not (null? found))
        found
        (let ((n (+ 4300000000 (* 16 (%py-length (first %py-ids))))))
          (%seq (%set-first! %py-ids (pair (pair v n) (first %py-ids))) n))))))

; getattr's default catches ONLY AttributeError, as in Python
;
; AN ATTRIBUTE NAME IS A PLATFORM STRING INSIDE, a Python str outside.  The
; attribute tables are keyed by the platform's strings and compared with
; `Str8 =?`, so a name arriving from Python code has to cross over -- which is
; what this returns.  Its callers must USE that return: it reads like a pure
; assertion (the `!`), and it was one before str became a code point list, but
; passing the ORIGINAL value on from here hands `Str8 =?` a PY-TEXT and the
; lookup dies with "not a string" instead of answering.
(def %py-attr-name!
  (fn (_ n)
    (match
      ((%py-str-is n) (%ps->x (%py-str-cps n)))
      ; ALREADY THE PLATFORM'S, AND SO ALREADY DONE.  These doors have two kinds
      ; of caller: getattr/setattr/delattr/hasattr, where the name is a str the
      ; program computed, and the PARSER, where `del obj.x` read the name out of
      ; the source and never had a str to begin with.  Refusing the second kind
      ; made `del obj.x` raise "attribute name must be string" about a name that
      ; is right there in the statement.
      ((str? n) n)
      (#t (Err raise (lit type) "attribute name must be string" ())))))
(def %py-getattr3
  (fn (_ o n0 . d)
    (def n (%py-attr-name! n0))
    (if (null? d)
      (%py-getattr o n)
      (guard (e (if (%py-exc-match e %py-exc-AttributeError) (first d) (error e)))
        (%py-getattr o n)))))
(def %py-setattr3
  (fn (_ o n0 v)
    (def n (%py-attr-name! n0))
    (if (if (%py-obj-is o) #t (%py-class-is o))
      (%py-setattr o n v)
      (Err raise (lit attribute) "object has no settable attributes" ()))))
(def %py-delattr
  (fn (_ o n0)
    (def n (%py-attr-name! n0))
    (if (%py-class-is o)
      ; `del C.x`: the row leaves the class's own table; a builtin type
      ; refuses, as in Python
      (match
        ((%py-class-builtin? o) (%py-immutable-type! "delete" o n))
        ((null? (%py-alist-find n (%py-class-methods o)))
          (Err raise (lit attribute)
            (Str8 append (Str8 append "type object '" (%py-class-name o))
              (Str8 append "' has no attribute '" (Str8 append n "'"))) ()))
        (#t (%seq (%py-class-methods-set! o (%py-attr-drop (%py-class-methods o) n)) ())))
    (if (not (%py-obj-is o))
      (Err raise (lit attribute) "object has no deletable attributes" ())
      ; __delattr__ is the same hook on `del obj.x`, and it is PYTHON code: it
      ; takes the name as a str, not as the platform string the tables below are
      ; keyed by.  Built from the CROSSED name rather than from the argument,
      ; because the argument is a str from delattr() and a platform string from
      ; the parser -- only one of those is a value to hand to a Python method.
      ; object carries a __delattr__ as well, so the lookup always finds one:
      ; a class supplies a hook when what the walk finds is not object's
      ; default, and the default is the drop below.
      (let ((h (%py-method-find (%py-obj-class o) "__delattr__")))
        (if (if (null? h) #f (not (same? h %py-object-delattr)))
          (%seq ((%py-bind-method h o) (%py-str-of-x n)) ())
          (let ((d (%py-method-find (%py-obj-class o) n)))
            (if (%py-desc-delete? d)
              (%seq ((%py-dunder d "__delete__") o) ())
              (%py-obj-drop-attr! o n)))))))))
(def %py-attr-drop
  (fn (self as n)
    (if (null? as) ()
      (if (Str8 =? (first (first as)) n)
        (self (rest as) n)
        (pair (first as) (self (rest as) n))))))

; the explicit super(type, obj) form: unimplemented, and every argument
; shape the corpus passes is one Python itself rejects
; super(type, obj): the explicit form, the same record the zero-argument
; form builds from the class the parser supplies.  obj may be an instance
; of type or a subclass of it.
(def %py-super-args
  (fn (_ . a)
    (match
      ((if (null? a) #t (not (%py-class-is (first a))))
        (Err raise (lit type) "super() argument 1 must be a type" ()))
      ((null? (rest a))
        (Err raise (lit type) "super() argument 2 is required here" ()))
      (#t
        (let ((cls (first a)) (obj (first (rest a))))
          (if (if (%py-obj-is obj) (%py-subclass? (%py-obj-class obj) cls)
                (if (%py-class-is obj) (%py-subclass? obj cls) #f))
            (%py-super-new cls obj)
            (Err raise (lit type)
              "super(type, obj): obj must be an instance or subtype of type" ())))))))

(def %py-issubclass
  (fn (_ c b)
    (match
      ((not (%py-class-is c))
        (Err raise (lit type) "issubclass() arg 1 must be a class" ()))
      ((%py-tuple-is b) (%py-any-subclass? c (%py-tuple-elems b)))
      ((%py-class-is b) (%py-subclass? c b))
      (#t
        (Err raise (lit type)
          "issubclass() arg 2 must be a class or tuple of classes" ())))))
(def %py-any-subclass?
  (fn (self c bs)
    (match
      ((null? bs) #f)
      ((not (%py-class-is (first bs)))
        (Err raise (lit type) "issubclass() arg 2 must be a class or tuple of classes" ()))
      ((%py-subclass? c (first bs)) #t)
      (#t (self c (rest bs))))))

; enumerate and filter are LAZY, like map: a generator pulling its source.
(def %py-enumerate
  (%py-sig!
    (fn (_ . a)
      (if (null? a)
        (Err raise (lit type) "enumerate() missing required argument 'iterable'" ())
        ())
      (let ((it (%py-opt a 0 ())) (st (%py-opt a 1 0)))
        (%py-gen-new
          (fn (_ g)
            (def src (%py-iter-open it))
            (def go
              (fn (self i)
                (let ((v (%py-iter-pull! src)))
                  (if (same? v %py-gen-done) ()
                    (%seq (%py-yield g (%py-tuple-new (list i v))) (self (+ i 1)))))))
            (go st))
          "enumerate")))
    "enumerate" (list "iterable" "start") 1 #f))
; filter(None, it) keeps the truthy elements
(def %py-filter
  (fn (_ f it)
    (%py-gen-new
      (fn (_ g)
        (def src (%py-iter-open it))
        (def go
          (fn (self)
            (let ((v (%py-iter-pull! src)))
              (if (same? v %py-gen-done) ()
                (%seq
                  (if (%py-truthy (if (null? f) v (f v))) (%py-yield g v) ())
                  (self))))))
        (go))
      "filter")))

; reversed(): __reversed__ first, then the length/getitem protocol, then
; anything materialisable
(def %py-rev-index
  (fn (self g i acc)
    (if (< i 0) (%py-reverse acc) (self g (- i 1) (pair (g i) acc)))))
(def %py-reversed
  (fn (_ v)
    (if (%py-obj-is v)
      (let ((m (%py-dunder v "__reversed__")))
        (if (not (null? m))
          (m)
          (let ((l (%py-dunder v "__len__")))
            (let ((g (%py-dunder v "__getitem__")))
              (if (if (null? l) #t (null? g))
                (Err raise (lit type) "object is not reversible" ())
                ; %py-rev-index already walks from the end
                (%py-list-new (%py-rev-index g (- (l) 1) ())))))))
      (%py-list-new (%py-reverse (%py-iter-elems v))))))

; --- Sets --------------------------------------------------------------------
;
; Membership is Python's equality, so `{False, True, 0, 1, 2}` holds three
; elements and the FIRST of an equal pair is the one kept -- which is why
; every builder folds through %py-set-put rather than filtering afterwards.
(def %py-set-has?
  (fn (self v es)
    (if (null? es) #f (if (%py-truthy (%py-eq v (first es))) #t (self v (rest es))))))
; a set, list or dict cannot be a set element or a dict key; a frozenset can
(def %py-hashable?
  (fn (_ v)
    (match
      ((%py-list-is v) #f)
      ((%py-dict-is v) #f)
      ((%py-set-is v) (%py-set-frozen? v))
      ((%py-dq-is v) #f)
      (#t #t))))
(def %py-check-hashable!
  (fn (_ v)
    (if (%py-hashable? v) ()
      (Err raise (lit type)
        (Str8 append (Str8 append "unhashable type: '" (%py-type-name v)) "'") ()))))
(def %py-type-name
  (fn (_ v)
    (match
      ((%py-list-is v) "list")
      ((%py-dict-is v) "dict")
      ((%py-set-is v) "set")
      (#t "object"))))
; append v unless an equal element is already there
(def %py-set-put
  (fn (_ es v)
    (%py-check-hashable! v)
    (if (%py-set-has? v es) es (%py-append-elem es v))))
(def %py-set-fold
  (fn (self es vs)
    (if (null? vs) es (self (%py-set-put es (first vs)) (rest vs)))))
(def %py-set-of (fn (_ frozen vs) (%py-set-new frozen (%py-set-fold () vs))))
(def %py-mkset (fn (_ . vs) (%py-set-of #f vs)))
; set(x) / frozenset(x): from any iterable, or empty
(def %py-set-ctor
  (fn (_ . a) (%py-set-of #f (if (null? a) () (%py-iter-elems (first a))))))
(def %py-frozenset-ctor
  (fn (_ . a) (%py-set-of #t (if (null? a) () (%py-iter-elems (first a))))))
; the elements of any iterable, as a plain list
(def %py-set-args
  (fn (self as acc)
    (if (null? as) acc (self (rest as) (%py-append acc (%py-iter-elems (first as)))))))
(def %py-set-minus
  (fn (self es drop)
    (if (null? es) ()
      (if (%py-set-has? (first es) drop)
        (self (rest es) drop)
        (pair (first es) (self (rest es) drop))))))
(def %py-set-keep
  (fn (self es keep)
    (if (null? es) ()
      (if (%py-set-has? (first es) keep)
        (pair (first es) (self (rest es) keep))
        (self (rest es) keep)))))
(def %py-set-subset?
  (fn (self es other)
    (if (null? es) #t
      (if (%py-set-has? (first es) other) (self (rest es) other) #f))))
(def %py-dict-eq?
  (fn (_ ea eb)
    (def same
      (fn (self l)
        (if (null? l) #t
          (let ((e (%py-dfind (first (first l)) eb)))
            (if (null? e) #f
              (if (%py-truthy (%py-eq (rest (first l)) (rest e))) (self (rest l)) #f))))))
    (if (= (%py-length ea) (%py-length eb)) (same ea) #f)))

(def %py-set-eq?
  (fn (_ a b)
    (if (= (%py-length a) (%py-length b)) (%py-set-subset? a b) #f)))
; a mutating method on a frozenset is simply absent, as in Python
(def %py-set-mutate!
  (fn (_ s name new)
    (if (%py-set-frozen? s)
      (Err raise (lit attribute)
        (Str8 append (Str8 append "'frozenset' object has no attribute '" name) "'") ())
      (%py-set-set! s new))))

; The operators, which Python spells for sets only -- `{1} | [2]` is a
; TypeError there, so the mixed cases refuse rather than convert.  The
; result takes the LEFT operand's frozen bit, as in Python.
(def %py-set-binop
  (fn (_ a b op body)
    (if (if (%py-set-is a) (%py-set-is b) #f)
      (%py-set-new (%py-set-frozen? a) (body (%py-set-elems a) (%py-set-elems b)))
      (Err raise (lit type)
        (Str8 append (Str8 append "unsupported operand type(s) for " op) ": set") ()))))
(def %py-set-or  (fn (_ a b) (%py-set-binop a b "|" (fn (_ x y) (%py-set-fold x y)))))
(def %py-set-and (fn (_ a b) (%py-set-binop a b "&" (fn (_ x y) (%py-set-keep x y)))))
(def %py-set-sub (fn (_ a b) (%py-set-binop a b "-" (fn (_ x y) (%py-set-minus x y)))))
(def %py-set-xor
  (fn (_ a b)
    (%py-set-binop a b "^"
      (fn (_ x y) (%py-set-fold (%py-set-minus x y) (%py-set-minus y x))))))
; <= is subset, < is proper subset (and the mirror for >= and >
(def %py-set-cmp
  (fn (_ a b op)
    (if (if (%py-set-is a) (%py-set-is b) #f)
      (let ((x (%py-set-elems a)) (y (%py-set-elems b)))
        (match
          ((Str8 =? op "<=") (%py-set-subset? x y))
          ((Str8 =? op "<")
            (if (%py-set-subset? x y) (< (%py-length x) (%py-length y)) #f))
          ((Str8 =? op ">=") (%py-set-subset? y x))
          ((%py-set-subset? y x) (> (%py-length x) (%py-length y)))
          (#t #f)))
      (%py-ord-refuse op))))

(def %py-set-attr
  (fn (_ s name)
    (def es (fn (_) (%py-set-elems s)))
    (def frozen (%py-set-frozen? s))
    (def like (fn (_ l) (%py-set-new frozen l)))
    (match
      ((Str8 =? name "add")
        (fn (_ v) (%py-set-mutate! s "add" (%py-set-put (es) v))))
      ((Str8 =? name "discard")
        (fn (_ v) (%py-set-mutate! s "discard" (%py-set-minus (es) (list v)))))
      ((Str8 =? name "remove")
        (fn (_ v)
          (if (not (%py-set-has? v (es)))
            (error (%py-instantiate %py-exc-KeyError (list v)))
            (%py-set-mutate! s "remove" (%py-set-minus (es) (list v))))))
      ((Str8 =? name "pop")
        (fn (_)
          (if (null? (es))
            (error (%py-instantiate %py-exc-KeyError (list "pop from an empty set")))
            (let ((v (first (es))))
              (%seq (%py-set-mutate! s "pop" (rest (es))) v)))))
      ((Str8 =? name "clear") (fn (_) (%py-set-mutate! s "clear" ())))
      ((Str8 =? name "copy") (fn (_) (like (es))))
      ((Str8 =? name "union")
        (fn (_ . a) (%py-set-new frozen (%py-set-fold (es) (%py-set-args a ())))))
      ((Str8 =? name "intersection")
        (fn (_ . a) (like (%py-set-keep (es) (%py-set-args a ())))))
      ((Str8 =? name "difference")
        (fn (_ . a) (like (%py-set-minus (es) (%py-set-args a ())))))
      ((Str8 =? name "symmetric_difference")
        (fn (_ o)
          (let ((os (%py-iter-elems o)))
            (like (%py-set-fold (%py-set-minus (es) os) (%py-set-minus os (es)))))))
      ((Str8 =? name "update")
        (fn (_ . a) (%py-set-mutate! s "update" (%py-set-fold (es) (%py-set-args a ())))))
      ((Str8 =? name "intersection_update")
        (fn (_ . a) (%py-set-mutate! s "intersection_update" (%py-set-keep (es) (%py-set-args a ())))))
      ((Str8 =? name "difference_update")
        (fn (_ . a) (%py-set-mutate! s "difference_update" (%py-set-minus (es) (%py-set-args a ())))))
      ((Str8 =? name "symmetric_difference_update")
        (fn (_ o)
          (let ((os (%py-iter-elems o)))
            (%py-set-mutate! s "symmetric_difference_update"
              (%py-set-fold (%py-set-minus (es) os) (%py-set-minus os (es)))))))
      ((Str8 =? name "issubset")
        (fn (_ o) (%py-set-subset? (es) (%py-iter-elems o))))
      ((Str8 =? name "issuperset")
        (fn (_ o) (%py-set-subset? (%py-iter-elems o) (es))))
      ((Str8 =? name "isdisjoint")
        (fn (_ o) (null? (%py-set-keep (es) (%py-iter-elems o)))))
      ((Str8 =? name "__contains__") (fn (_ v) (%py-set-has? v (es))))
      (#t
        (Err raise (lit attribute)
          (Str8 append
            (Str8 append (Str8 append "'" (if frozen "frozenset" "set")) "' object has no attribute '")
            (Str8 append name "'"))
          ())))))

(def %py-mklist-of
  (fn (_ v) (%py-list-new (%py-iter-elems v))))

; --- dir ---------------------------------------------------------------------
;
; The names a thing answers to: its own, then its class's, then the bases' --
; sorted, and each name once however many ancestors offer it.
;
; NO BARE dir().  Python's answers with the current local namespace; here a
; Python name is an x global and no dictionary stands for the module, so there
; is nothing truthful to answer.  Refused rather than answered wrongly, which
; is the same call `globals()` and `locals()` are still waiting on.
;
; A BUILTIN TYPE ANSWERS ITS OWN NAMES ONLY.  `dir(list)` does not list
; `append`: this runtime reaches a list's methods by type at the seam rather
; than hanging them off the class object, so they are not there to be found.
; Whatever a class DOES carry is reported.
(def %py-dir-keys
  (fn (self rows acc)
    (if (null? rows)
      acc
      (self (rest rows) (pair (first (first rows)) acc)))))

(def %py-dir-class
  (fn (self c acc)
    (if (null? c)
      acc
      (%py-dir-bases (%py-class-bases c) (%py-dir-keys (%py-class-methods c) acc)))))

(def %py-dir-bases
  (fn (self bs acc)
    (if (null? bs)
      acc
      (self (rest bs) (%py-dir-class (first bs) acc)))))

(def %py-dir-of
  (fn (_ v)
    (match
      ((%py-class-is v) (%py-dir-class v ()))
      ((%py-obj-is v) (%py-dir-class (%py-obj-class v) (%py-dir-keys (%py-obj-attrs v) ())))
      (#t ()))))

(def %py-dir-seen?
  (fn (self n seen)
    (if (null? seen) #f
      (if (Str8 =? n (first seen)) #t (self n (rest seen))))))

(def %py-dir-uniq
  (fn (self names acc)
    (if (null? names)
      acc
      (self (rest names)
        (if (%py-dir-seen? (first names) acc) acc (pair (first names) acc))))))

; THE NAMES CROSS BACK BEFORE THEY ARE SORTED.  They come off the attribute
; tables as the platform's strings, and what dir() answers is a list of strs --
; so they are wrapped here, ahead of the sort, because the sort is Python's `<`
; and the numeric one underneath it has no answer for a platform string ("no <
; for STRING").  Wrapping after the sort would leave the order to that error.
(def %py-dir-strs
  (fn (self l acc)
    (if (null? l) acc
      (self (rest l) (pair (%py-str-of-x (first l)) acc)))))

(def %py-dir
  (%py-sig!
    (fn (_ . a)
      (if (null? a)
        (Err raise (lit type)
          "dir() with no arguments needs a namespace this runtime does not keep" ())
        (%py-list-new
          (%py-msort-by
            (%py-dir-strs (%py-dir-uniq (%py-dir-of (first a)) ()) ())
            %py-ident))))
    "dir" (list "object") 0 #f))

; `hasattr` is defined in terms of getattr in Python too: it is "does this
; raise?", not a separate lookup, so anything reachable by attribute access is
; reachable here and the two can never disagree.
(def %py-hasattr
  (fn (_ o name0)
    (def name (%py-attr-name! name0))
    (guard (e (if (%py-exc-match e %py-exc-AttributeError) #f (error e)))
      (%seq (%py-getattr o name) #t))))

