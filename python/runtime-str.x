; # x-python -- Python on x-lang
;
; ## python/runtime-str.x -- attributes, str's methods, and the format-spec language
;
; @description The attribute and method surface, Python's str methods over code
;   points, and the { } mini-language shared by f-strings and
;   str.format.
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

; --- Attributes and methods --------------------------------------------------
;
; `x.append` is a VALUE, not just a call form.  Python binds the receiver at
; attribute-access time -- `f = x.append; f(4)` appends to x -- so getattr
; returns a closure over the object rather than the parser emitting a
; three-argument call. That costs one closure per access and buys the bound
; method for free.
;
; MUTATION IS IN PLACE, and the tag pair is what makes it possible. A list is
; (py-list . elements); %set-rest! replaces the elements on THAT pair, so every
; reference to the list sees the change. Rebuilding and returning a new list
; would make `x.append(5)` silently do nothing to x, which is the bug this
; representation was chosen to avoid.
(def %py-append-elem
  (fn (self lst v)
    (if (null? lst) (list v) (pair (first lst) (self (rest lst) v)))))

(def %py-getattr
  (fn (_ obj name)
    ; AN INSTANCE IS ASKED FIRST.  It used to be asked after the builtin
    ; types, which was harmless while no instance could BE one -- a subclass
    ; of list would have gone to the list surface and lost its own methods
    ; and its own attributes.
    (match
      ((%py-obj-is obj) (%py-obj-attr obj name))
      ; every value has a __class__; an instance answered its own above
      ((Str8 =? name "__class__") (%py-type-of obj))
      ((%py-io-is obj) (%py-io-attr obj name))
      ((%py-arr-is obj) (%py-arr-attr obj name))
      ((%py-mv-is obj) (%py-mv-attr obj name))
      ((%py-sl-is obj) (%py-sl-attr obj name))
      ((%py-dq-is obj) (%py-dq-attr obj name))
      ((%py-list? obj) (%py-list-attr obj name))
      ((%py-dict? obj) (%py-dict-attr obj name))
      ((%py-str-is obj) (%py-str-method obj name))
      ((%py-barr-is obj) (%py-barr-attr obj name))
      ((%py-bytes-is obj) (%py-bytes-attr obj name))
      ((%py-set-is obj) (%py-set-attr obj name))
      ((%py-tuple-is obj) (%py-tuple-attr obj name))
      ((%py-gen-is obj) (%py-gen-attr obj name))
      ((%py-it-is obj) (%py-it-attr obj name))
      ((%py-bound-is obj) (%py-bound-attr obj name))
      ((%py-super-is obj) (%py-super-attr obj name))
      ((%py-class-is obj) (%py-class-attr obj name))
      ((%py-complex-is obj)
        (match
          ((Str8 =? name "real") (%py-cre obj))
          ((Str8 =? name "imag") (%py-cim obj))
          ((Str8 =? name "conjugate")
            (fn (_) (Complex make (%py-cre obj) (- 0.0 (%py-cim obj)))))
          (#t
            (Err raise (lit attribute)
              (Str8 append (Str8 append "'complex' object has no attribute '" name) "'") ()))))
      ; an int's methods live on the int class
      ((eq? (%py-num-kind (%py-boolnorm obj)) (lit int)) (%py-int-attr obj name))
      (#t
        (let ((sig (%py-sig-of obj)))
          (if (if (null? sig) #f (Str8 =? name "__name__"))
            (%py-str-of-x (first sig))
            (Err raise (lit attribute)
              (Str8 append (Str8 append "object has no attribute '" name) "'")())))))))

; str.upper is the method as a function of its receiver -- str.upper("abc")
; -- and a user class's attribute is its function, unbound, callable with an
; explicit self.  A builtin class other than str has no such surface yet.

; A class's own alist, as dict rows -- minus the "%ctor" and "%final" keys,
; which are this runtime's own and which no Python identifier can spell.
(def %py-class-rows
  (fn (self cls)
    ((fn (go rows)
       (if (null? rows) ()
         (if (if (Str8 =? (first (first rows)) "%ctor") #t
               (Str8 =? (first (first rows)) "%final"))
           (go (rest rows))
           ; __dict__ IS A DICT, so the names cross over: they are the
           ; platform's strings in the method table and strs once they are
           ; keys a Python program can look up.
           (pair (pair (%py-str-of-x (first (first rows))) (rest (first rows)))
                 (go (rest rows))))))
     (%py-class-methods cls))))

; AN UNBOUND METHOD IS THE ATTRIBUTE ASKED OF A RECEIVER, with the receiver
; given as the first argument instead of standing to the left of the dot --
; `bytes.count(b"aa", b"a")` is `b"aa".count(b"a")`.
;
; The EMPTY receiver is what makes `bytes.nosuch` an AttributeError here
; rather than at the eventual call: every %py-*-attr raises while looking the
; name up, so looking it up once against a value of the right kind asks the
; question without needing one of the caller's.  It is also what a `try:
; bytes.count / except AttributeError` guard is asking, and five conformance
; programs open with exactly that.
;
; The receiver is checked before a %py-*-attr reads it, since each one reads its
; receiver as a value of its own class.  The check is isinstance, as in Python: a
; missing receiver or one of another type is a TypeError, and a subclass instance
; is asked through the value it carries.
(def %py-unbound
  (fn (_ cls attr empty name)
    (do (attr empty name)
        (fn (_ . args)
          (match
            ((null? args)
              (Err raise (lit type)
                (Str8 append (Str8 append "unbound method " (%py-class-name cls))
                  (Str8 append "." (Str8 append name "() needs an argument"))) ()))
            ((%py-isinstance (first args) cls)
              (apply (attr (%py-native-of (first args)) name) (rest args)))
            (#t
              (Err raise (lit type)
                (Str8 append (Str8 append "descriptor '" name)
                  (Str8 append (Str8 append "' for '" (%py-class-name cls))
                    (Str8 append "' objects doesn't apply to a '"
                      (Str8 append (%py-class-name (%py-type-of (first args)))
                        "' object"))))
                ())))))))

(def %py-class-attr
  (fn (_ cls name)
    ; The three a class answers about itself come first: the class walk ends at
    ; a builtin's instance surface, which has no __name__, __bases__ or
    ; __dict__ to give.
    (match
      ; __name__ IS A str, like every other text a program can get at.  It
      ; is the platform's string in the class record, and `type(x).__name__ ==
      ; "Foo"` compared it against a str and answered False -- a wrong answer,
      ; not an error, which is why it took a decorator spec and a descriptor
      ; spec to notice.
      ((Str8 =? name "__name__") (%py-str-of-x (%py-class-name cls)))
      ((Str8 =? name "__bases__") (%py-tuple-of-list (%py-class-bases cls)))
      ((Str8 =? name "__dict__") (%py-dict-new (%py-class-rows cls)))
      (#t (%py-class-walk cls name)))))

; THE CLASS'S OWN METHODS ARE ASKED FIRST, and the builtin instance surface
; only afterwards.  Both halves matter.  A builtin type object really does
; carry methods -- `%py-bytes-methods` and friends give list, bytes and the
; rest their __len__, __getitem__ and __init__ -- and those are what a
; subclass inherits, so an arm that answered from the instance surface first
; SHADOWED them: `list.__init__` stopped being the class's and started being
; the AttributeError `%py-list-attr` raises for a name no list instance has.
; Measured as a regression in 71-native-subclass, which is the file that
; exists to notice exactly this.
(def %py-class-walk
  (fn (_ cls name)
    (let ((m (%py-method-find cls name)))
      (if (null? m)
          (%py-class-unbound cls name)
            ; FROM THE CLASS there is no instance to bind: a staticmethod
            ; is its function, a classmethod binds THIS class -- which is
            ; what makes `cls` the child in `Sub.method()` -- and a
            ; property stays the descriptor, since `C.v` in Python is the
            ; property object, not a value it has no instance to compute.
            (if (%py-desc-is m)
              (let ((f (%py-desc-fn m)) (k (%py-desc-kind m)))
                (if (eq? k (lit static))
                  f
                  (if (eq? k (lit classmethod))
                    (%py-bound-new f cls)
                    m)))
              m)))))

; What a builtin type offers beyond the methods on its class object: the
; whole instance surface, unbound.  A subclass reaches its builtin base's row
; through the base walk and answers the base's method, so `L.append` is
; `list.append` and takes any list as its receiver.  A class with no builtin
; base, or a name the surface does not have, is an AttributeError naming the
; class that was asked.
(def %py-class-unbound
  (fn (_ cls name)
    (let ((m (guard (e (if (%py-exc-match e %py-exc-AttributeError) () (error e)))
               (match
                 ((%py-subclass? cls %py-cls-str)
                   (%py-unbound %py-cls-str %py-str-attr (%py-str-new ()) name))
                 ((%py-subclass? cls %py-cls-bytes)
                   (%py-unbound %py-cls-bytes %py-bytes-attr (%py-bytes-new ()) name))
                 ((%py-subclass? cls %py-cls-bytearray)
                   (%py-unbound %py-cls-bytearray %py-barr-attr (%py-barr-new ()) name))
                 ((%py-subclass? cls %py-cls-list)
                   (%py-unbound %py-cls-list %py-list-attr (%py-list-new ()) name))
                 ((%py-subclass? cls %py-cls-dict)
                   (%py-unbound %py-cls-dict %py-dict-attr (%py-dict-new ()) name))
                 ((%py-subclass? cls %py-cls-set)
                   (%py-unbound %py-cls-set %py-set-attr (%py-set-new #f ()) name))
                 ((%py-subclass? cls %py-cls-frozenset)
                   (%py-unbound %py-cls-frozenset %py-set-attr (%py-set-new #t ()) name))
                 ((%py-subclass? cls %py-cls-tuple)
                   (%py-unbound %py-cls-tuple %py-tuple-attr (%py-tuple-new ()) name))
                 (#t ())))))
      (if (null? m)
        (Err raise (lit attribute)
          (Str8 append (Str8 append "type object '" (%py-class-name cls))
            (Str8 append "' has no attribute '" (Str8 append name "'"))) ())
        m))))

; STRING METHODS MAP ONTO Str8, WHICH ALREADY HAS THEM -- upcase, downcase,
; trim, split, join, replace, starts?, ends?, index-of. The work here is the
; SHAPE, not the algorithm: Str8 takes its subject LAST, Python takes it first
; as the receiver, and split/join cross the list boundary so their results have
; to be tagged or untagged on the way through.
;
; find() returns -1 when absent, which is Python's contract and the reason it is
; not index() -- that one raises. Only find is here.
; --- Python's str methods ----------------------------------------------------
;
; Byte-indexed on Str8, which is right for the ASCII the corpus speaks and
; wrong for a multibyte character under a ranged method -- stated, not hidden.
; Ranges follow Python's slice clamping (None, negatives, past-the-end);
; index/rindex raise ValueError where find/rfind answer -1.

; --- str, over code points ---------------------------------------------------
;
; THIS USED TO BE 331 LINES, and 24 helpers, every one of them a string
; algorithm over Str8.  python/bytes.x wrote all of them again over lists of
; ints for `bytes`, and a str is a list of ints too -- code points rather than
; bytes -- so the second copy is the only copy now and this is the table onto
; it.
;
; It is not just deduplication.  The old helpers ran on BYTES while len, [],
; ord and slicing reached for the code-point-aware Str: for ASCII the two
; agree and nothing showed, and for anything else `find` counted one unit
; while `len` counted another.  One carrier, one unit, one answer.
;
; An argument arrives as a str and leaves as its code points; anything else is
; Python's TypeError, said where the argument is taken rather than deep in a
; walk.
(def %py-s-cps
  (fn (_ v who)
    (if (%py-str-is v)
      (%py-str-cps v)
      (Err raise (lit type)
        (Str8 append who " argument must be str") ()))))

; __str__ AND __repr__ ANSWER EITHER KIND OF TEXT, so the four places that take
; their answer need not ask which.  A user's dunder returns a str; the fallbacks
; beside it -- an exception's message, the default repr -- are the platform's
; strings, and both are text that must print as itself.  `display` of a PY-TEXT
; writes its code points as raw values, which is how an object whose __str__
; returned "as str" printed as mojibake.
;
; The display door goes through %ps-write, so an object whose __str__ answers a
; NUL-bearing str prints the byte like any other str does.
(def %py-text->x
  (fn (_ s) (if (%py-str-is s) (%ps->x (%py-str-cps s)) s)))
(def %py-text-display
  (fn (_ s) (if (%py-str-is s) (%ps-write (%py-str-cps s)) (display s))))

; A REQUIRED SEPARATOR THAT MAY NOT BE EMPTY.  `"asdf".partition("")` is a
; ValueError in CPython; the degenerate triple ('', '', 'asdf') came back
; instead.  Unlike split's separator this one is never absent, so there is
; nothing for an empty one to be confused with -- see %py-s-sep for that case.
(def %py-s-cps1
  (fn (_ v who)
    (let ((l (%py-s-cps v who)))
      (if (null? l) (Err raise (lit value) "empty separator" ()) l))))

; startswith AND endswith TAKE A TUPLE OF CANDIDATES and answer true if any one
; of them matches -- `"foobar".startswith(("x", "foo"))` is True in CPython.  A
; plain str is the one-candidate case, so both spellings go through here rather
; than the test being written twice.
(def %py-s-any?
  (fn (_ v who test)
    (if (%py-tuple-is v)
      (%py-s-any-of (%py-tuple-elems v) who test)
      (test (%py-s-cps v who)))))
(def %py-s-any-of
  (fn (self els who test)
    (if (null? els)
      #f
      (if (test (%py-s-cps (first els) who))
        #t
        (self (rest els) who test)))))
(def %py-s-arg (fn (_ a i) (if (> (%py-length a) i) (List ref i a) ())))
(def %py-s-opt
  (fn (_ a i d) (let ((v (%py-s-arg a i))) (if (null? v) d v))))
; a separator or strip set: absent or None means "not given"
(def %py-s-set
  (fn (_ a i who)
    (let ((v (%py-s-arg a i))) (if (null? v) () (%py-s-cps v who)))))
; A SEPARATOR FOR split/rsplit, WHERE EMPTY IS AN ERROR AND ABSENT IS NOT.
; The two cannot be told apart once the value is code points -- `""` and None
; both arrive as () -- so the RAW argument decides: absent or None means split
; on whitespace, and a str that happens to be empty is the ValueError CPython
; raises.  %py-s-set is still right for strip() and friends, where an empty set
; is simply an empty set.
(def %py-s-sep
  (fn (_ a i who)
    (let ((raw (%py-s-arg a i)))
      (if (null? raw)
        ()
        (let ((v (%py-s-cps raw who)))
          (if (null? v)
            (Err raise (lit value) "empty separator" ())
            v))))))

(def %py-s-start (fn (_ l a i) (%py-b-clamp (%py-s-opt a i 0) (%pb-len l))))
(def %py-s-end (fn (_ l a i) (%py-b-clamp (%py-s-opt a i (%pb-len l)) (%pb-len l))))
; A START PAST THE END FINDS NOTHING -- not even the empty needle, which
; matches everywhere else.  The clamp pulls 6 back to 5, so "hello".find("", 6)
; answered 5 where CPython answers -1; only a start actually within the string
; can match.  A NEGATIVE start counts from the end, so it is normalised first
; and never trips this.  A non-empty needle was already right: its window is
; empty there and the search fails on its own.
(def %py-s-search
  (fn (_ l a rev)
    (let ((len (%pb-len l)))
      (let ((raw (%py-boolnorm (%py-s-opt a 1 0))))
        (if (> (if (< raw 0) (+ len raw) raw) len)
          (- 0 1)
          (let ((s (%py-s-start l a 1)))
            (let ((e (%py-s-end l a 2)))
              (let ((w (%pb-sub l s (- e s))) (n (%py-s-cps (first a) "sub")))
                (let ((r (if rev (%pb-rfind w n) (%pb-find w n))))
                  (if (< r 0) r (+ r s)))))))))))
(def %py-s-index
  (fn (_ i) (if (< i 0) (Err raise (lit value) "substring not found" ()) i)))

; the parts of a split, each a str again
(def %py-s-parts
  (fn (self ps acc)
    (if (null? ps) (%py-list-new (List reverse acc))
      (self (rest ps) (pair (%py-str-new (first ps)) acc)))))
(def %py-s-join-seq
  (fn (self l acc)
    (if (null? l) (List reverse acc)
      (self (rest l) (pair (%py-s-cps (first l) "join") acc)))))
(def %py-s-fill
  (fn (_ a i) (let ((c (%py-s-opt a i ()))) (if (null? c) 32 (first (%py-s-cps c "fill"))))))

(def %py-str-attr
  (fn (_ v name) (%py-s-attr (%py-str-cps v) name v)))

; A name the str surface does not have, answered from str's class rows.  Every
; caller of the surface applies what it answers, so a method comes back as a
; closure over the value rather than as a bound method.
(def %py-str-row-attr
  (fn (_ v name)
    (let ((m (%py-class-row-attr %py-cls-str v name "str")))
      (if (%py-bound-is m) (%py-bind-method (%py-bound-fn m) v) m))))

; startswith and endswith: the needle, or any of a tuple of them, against the
; window from start to end.  An end before the start is a window nothing fits,
; the empty string included -- CPython's rule -- though the needle is still
; checked for its type.
(def %py-s-affix
  (fn (_ l a who test)
    (let ((s (%py-s-start l a 1)) (e (%py-s-end l a 2)))
      (let ((w (if (< e s) () (%pb-sub l s (- e s)))))
        (%py-s-any? (first a) who (fn (_ n) (if (< e s) #f (test w n))))))))

; A str a strip left whole IS the answer -- `s.strip() is s` -- as it is for
; bytes (%py-b-kept) and in CPython.
(def %py-s-kept
  (fn (_ v l r) (if (= (%pb-len r) (%pb-len l)) v (%py-str-new r))))

; l is the code points of the str v.
(def %py-s-attr
  (fn (_ l name v)
    (match
      ((Str8 =? name "upper")      (fn (_ . a) (%py-str-new (%pb-upper l))))
      ((Str8 =? name "lower")      (fn (_ . a) (%py-str-new (%pb-lower l))))
      ((Str8 =? name "swapcase")   (fn (_ . a) (%py-str-new (%pb-swapcase l))))
      ((Str8 =? name "capitalize") (fn (_ . a) (%py-str-new (%pb-capitalize l))))
      ((Str8 =? name "title")      (fn (_ . a) (%py-str-new (%pb-title l))))
      ((Str8 =? name "strip")
        (fn (_ . a) (%py-s-kept v l (%pb-strip l (%py-s-set a 0 "strip") #t #t))))
      ((Str8 =? name "lstrip")
        (fn (_ . a) (%py-s-kept v l (%pb-strip l (%py-s-set a 0 "lstrip") #t #f))))
      ((Str8 =? name "rstrip")
        (fn (_ . a) (%py-s-kept v l (%pb-strip l (%py-s-set a 0 "rstrip") #f #t))))
      ((Str8 =? name "split")
        (fn (_ . a) (%py-s-parts (%pb-split l (%py-s-sep a 0 "split") (%py-s-opt a 1 (- 0 1))) ())))
      ((Str8 =? name "rsplit")
        (fn (_ . a) (%py-s-parts (%pb-rsplit l (%py-s-sep a 0 "rsplit") (%py-s-opt a 1 (- 0 1))) ())))
      ((Str8 =? name "splitlines")
        (fn (_ . a) (%py-s-parts (%pb-splitlines l (%py-truthy (%py-s-opt a 0 #f))) ())))
      ((Str8 =? name "join")
        (fn (_ it)
          (%py-str-new
            (%pb-join l
              (%py-s-join-seq
                (%py-iter-elems it "can only join an iterable of str") ())))))
      ((Str8 =? name "replace")
        (fn (_ old new . a)
          (%py-str-new
            (%pb-replace l (%py-s-cps old "replace()") (%py-s-cps new "replace()")
              (%py-s-opt a 0 (- 0 1))))))
      ((Str8 =? name "find")   (fn (_ . a) (%py-s-search l a #f)))
      ((Str8 =? name "rfind")  (fn (_ . a) (%py-s-search l a #t)))
      ((Str8 =? name "index")  (fn (_ . a) (%py-s-index (%py-s-search l a #f))))
      ((Str8 =? name "rindex") (fn (_ . a) (%py-s-index (%py-s-search l a #t))))
      ((Str8 =? name "count")
        (fn (_ . a)
          (let ((s (%py-s-start l a 1)))
            (%pb-count (%pb-sub l s (- (%py-s-end l a 2) s)) (%py-s-cps (first a) "count") 0))))
      ((Str8 =? name "startswith") (fn (_ . a) (%py-s-affix l a "startswith" %pb-starts?)))
      ((Str8 =? name "endswith") (fn (_ . a) (%py-s-affix l a "endswith" %pb-ends?)))
      ((Str8 =? name "partition")
        (fn (_ . a) (%py-s-triple (%pb-partition l (%py-s-cps1 (first a) "partition")))))
      ((Str8 =? name "rpartition")
        (fn (_ . a) (%py-s-triple (%pb-rpartition l (%py-s-cps1 (first a) "rpartition")))))
      ((Str8 =? name "center")
        (fn (_ . a) (%py-str-new (%pb-center l (first a) (%py-s-fill a 1)))))
      ((Str8 =? name "ljust")
        (fn (_ . a) (%py-str-new (%pb-ljust l (first a) (%py-s-fill a 1)))))
      ((Str8 =? name "rjust")
        (fn (_ . a) (%py-str-new (%pb-rjust l (first a) (%py-s-fill a 1)))))
      ((Str8 =? name "isspace") (fn (_ . a) (%pb-isspace l)))
      ((Str8 =? name "isalpha") (fn (_ . a) (%pb-isalpha l)))
      ((Str8 =? name "isdigit") (fn (_ . a) (%pb-isdigit l)))
      ((Str8 =? name "isalnum") (fn (_ . a) (%pb-isalnum l)))
      ((Str8 =? name "isupper") (fn (_ . a) (%pb-isupper l)))
      ((Str8 =? name "islower") (fn (_ . a) (%pb-islower l)))
      ; ENCODE IS THE CODEC, and the one place str and bytes meet by design.
      ((Str8 =? name "encode")
        (fn (_ . a)
          (%py-bytes-new
            (%ps-encode-as l (%py-codec-arg a 0 "utf-8")
              (%py-codec-arg a 1 "strict")))))
      ; str.format is the BRACE engine (%py-strformat), not the percent one:
      ; `"{}".format(x)` and `"%s" % x` are different grammars that happen to
      ; share a spec scanner.  Its template is a platform string and its args
      ; are a plain list, so only the template crosses over.
      ((Str8 =? name "format")
        (fn (_ . a) (%py-str-of-x (%py-strformat (%ps->x l) a))))
      (#t (%py-str-row-attr v name)))))

(def %py-s-triple
  (fn (_ t)
    (%py-tuple-new
      (list (%py-str-new (first t)) (%py-str-new (first (rest t)))
            (%py-str-new (first (rest (rest t))))))))

(def %py-int->char (prim-ref (lit int) (lit ->char)))
; %c and {:c}: the character a code point names, refused past U+10FFFF as the
; OverflowError both formats raise, in their own words -- where chr() says
; ValueError about the same number.
(def %py-fmt-char
  (fn (_ v)
    (let ((n (%py-boolnorm v)))
      (if (if (eq? (%py-num-kind n) (lit int)) (if (< n 0) #t (> n 1114111)) #f)
        (Err raise (lit overflow) "%c arg not in range(0x110000)" ())
        (%py-chr v)))))

(def %py-chr
  (fn (_ n0)
    (def n (%py-boolnorm n0))
    (match
      ((not (eq? (%py-num-kind n) (lit int)))
        (Err raise (lit type) "an integer is required" ()))
      ((if (< n 0) #t (> n 1114111))
        (Err raise (lit value) "chr() arg not in range(0x110000)" ()))
      ; A CODE POINT IS THE INTEGER.  Nothing is encoded here and no character
      ; is made: the carrier is a list of code points, so chr() is the list of
      ; one.  That is also why zero needs no case of its own -- it is a code
      ; point like any other, and the refusal that used to stand here went out
      ; with the platform string this used to build.
      (#t (%py-str-new (list n))))))
; ord() COUNTS CODE POINTS, and now it simply reads one: the carrier IS a list
; of them, so there is nothing to measure and nothing to decode.  This used to
; index with the utf-8-aware `Str` class, which a PY-TEXT is not -- it answered
; 144 for '\xff' rather than 255, a wrong number rather than an error.
(def %py-ord
  (fn (_ s)
    (if (if (%py-str-is s) (= (%pb-len (%py-str-cps s)) 1) #f)
      (first (%py-str-cps s))
      ; a one-byte bytes answers that BYTE's value, so ord(b'\xff') is 255
      (if (if (%py-bytes-is s) (= (%pb-len (%py-bytes-list s)) 1) #f)
        (%pb-ref (%py-bytes-list s) 0)
        (Err raise (lit type) "ord() expected a character" ())))))

; --- The format-spec mini-language -------------------------------------------
;
; [[fill]align][sign][#][0][width][,][.precision][type], shared by str.format
; and f-strings.  The numeric bodies are the %-operator's, on the exact
; digits (python/format.x); what differs here is the framing -- fill and
; alignment, = for sign-aware padding, thousands grouping, the % type, and
; the empty type's rules.  Every unknown type is Python's ValueError.
(def %py-spec-code (fn (_ s i) (%py-char-code (%str-ref s i))))

; The parsed spec, as a list: (fill align sign alt zero width comma prec type)
(def %py-spec-parse
  (fn (_ spec)
    (def n (Str8 length spec))
    (def align? (fn (_ c) (match
                            ((= c 60) #t)
                            ((= c 62) #t)
                            ((= c 94) #t)
                            (#t (= c 61)))))
    ; fill+align if the SECOND char is an align char, else align alone
    (def i0 0)
    (def fill " ")
    (def align ())
    (if (if (>= n 2) (align? (%py-spec-code spec 1)) #f)
      (do (set! fill (Str8 sub 0 1 spec))
          (set! align (Str8 sub 1 1 spec))
          (set! i0 2))
      (if (if (>= n 1) (align? (%py-spec-code spec 0)) #f)
        (do (set! align (Str8 sub 0 1 spec)) (set! i0 1))
        ()))
    (def i i0)
    (def sign "")
    (if (if (< i n) (let ((c (%py-spec-code spec i))) (if (= c 43) #t (if (= c 45) #t (= c 32)))) #f)
      (do (set! sign (Str8 sub i 1 spec)) (set! i (+ i 1))) ())
    (def alt #f)
    (if (if (< i n) (= (%py-spec-code spec i) 35) #f)
      (do (set! alt #t) (set! i (+ i 1))) ())
    (def zero #f)
    (if (if (< i n) (= (%py-spec-code spec i) 48) #f)
      (do (set! zero #t) (set! i (+ i 1))) ())
    (def num
      (fn (self j acc)
        (if (if (< j n) (%py-fmt-digit? (%py-spec-code spec j)) #f)
          (self (+ j 1) (+ (* acc 10) (- (%py-spec-code spec j) 48)))
          (pair j acc))))
    (def w (num i 0))
    (def width (if (= (first w) i) () (rest w)))
    (set! i (first w))
    (def comma #f)
    (if (if (< i n) (= (%py-spec-code spec i) 44) #f)
      (do (set! comma #t) (set! i (+ i 1)))
      (if (if (< i n) (= (%py-spec-code spec i) 95) #f)
        (do (set! comma (lit under)) (set! i (+ i 1)))
        ()))
    (if (if (< i n) (if (= (%py-spec-code spec i) 44) #t (= (%py-spec-code spec i) 95)) #f)
      (Err raise (lit value) "Cannot specify both ',' and '_'." ())
      ())
    (def prec ())
    (if (if (< i n) (= (%py-spec-code spec i) 46) #f)
      (let ((p (num (+ i 1) 0)))
        (if (= (first p) (+ i 1))
          (Err raise (lit value) "Format specifier missing precision" ())
          (do (set! prec (rest p)) (set! i (first p)))))
      ())
    (def type (if (< i n) (Str8 sub i 1 spec) ""))
    (if (< (+ i 1) n)
      (Err raise (lit value) "Invalid format specifier" ())
      (list fill align sign alt zero width comma prec type))))

(def %py-spec-pad
  (fn (_ s width fill align default-align sgn)
    ; sgn is a sign already split off for = alignment; s is the body
    (def total (+ (Str8 length sgn) (Str8 length s)))
    (def a (if (null? align) default-align align))
    (def rep (fn (self k) (if (<= k 0) "" (Str8 append fill (self (- k 1))))))
    (if (if (null? width) #t (>= total width))
      (Str8 append sgn s)
      (let ((padn (- width total)))
        (match
          ((Str8 =? a "<") (Str8 append (Str8 append sgn s) (rep padn)))
          ((Str8 =? a ">") (Str8 append (rep padn) (Str8 append sgn s)))
          ((Str8 =? a "=") (Str8 append sgn (Str8 append (rep padn) s)))
          ; ^ centres, the extra space on the right
          (#t
            (let ((l (Num quotient padn 2)))
              (Str8 append (rep l) (Str8 append (Str8 append sgn s) (rep (- padn l)))))))))))

; Thousands grouping on a digit string.
(def %py-group3
  (fn (_ ds)
    (def n (Str8 length ds))
    (def go
      (fn (self i acc)
        (if (<= i 0)
          acc
          (let ((start (if (< (- i 3) 0) 0 (- i 3))))
            (self start
              (if (Str8 =? acc "")
                (Str8 sub start (- i start) ds)
                (Str8 append (Str8 sub start (- i start) ds) (Str8 append "," acc))))))))
    (go n "")))

(def %py-format-spec
  (fn (_ v spec)
    (if (Str8 =? spec "")
      (%py-str v)
      (do
        (def ps (%py-spec-parse spec))
        (def fill (List ref 0 ps))
        (def align (List ref 1 ps))
        (def sign (List ref 2 ps))
        (def alt (List ref 3 ps))
        (def zero (List ref 4 ps))
        (def width (List ref 5 ps))
        (def comma (List ref 6 ps))
        (def prec (List ref 7 ps))
        (def type (List ref 8 ps))
        (def tc (if (Str8 =? type "") 0 (%py-spec-code type 0)))
        ; the 0 flag is fill 0 with = alignment, for numbers
        (def fill2 (if (if zero (Str8 =? fill " ") #f) "0" fill))
        (def align2 (if (if zero (null? align) #f) "=" align))
        (if (match
              ((%py-str-is v) #t)
              ; ALREADY TEXT, AND ALREADY THE PLATFORM'S.  A conversion ran
              ; ahead of this -- !r and !s in %py-fmtfield hand their answer on
              ; as a platform string -- and without this arm it falls through to
              ; the numeric branch below, where %py-num-kind is nil and the
              ; complaint is "unsupported format string passed to
              ; object.__format__" about a string.  `f'{x!r:>8}'` and
              ; `'{!r:>8}'.format(x)` both land here.
              ((str? v) #t)
              ((= tc 115) #t)
              ((%py-obj-is v) #t)
              ((null? v) #t)
              ((%py-list? v) #t)
              (#t (%py-tuple-is v)))
          ; strings (and anything shown as its str): s or empty type only
          (match
            ((if (not (= tc 0)) (not (= tc 115)) #f)
              (Err raise (lit value)
                (Str8 append "Unknown format code '" (Str8 append type "' for object of type 'str'")) ()))
            ((if (= tc 115) (not (null? (%py-num-kind v))) #f)
              (Err raise (lit value)
                (Str8 append "Unknown format code 's' for object of type '"
                  (Str8 append (if (eq? (%py-num-kind v) (lit float)) "float" "int") "'")) ()))
            ((if (null? sign) #f (not (Str8 =? sign "")))
              (Err raise (lit value) "Sign not allowed in string format specifier" ()))
            ((if (not (null? align)) (Str8 =? align "=") #f)
              (Err raise (lit value) "'=' alignment not allowed in string format specifier" ()))
            (#t
              (let ((s0 (%py-str v)))
                (let ((s (if (if (not (null? prec)) (> (Str8 length s0) prec) #f) (Str8 sub 0 prec s0) s0)))
                  ; the 0 flag on text fills with zeros on the RIGHT ('{:06s}'
                  ; of ab is ab0000 -- measured)
                  (%py-spec-pad s width (if (if zero (Str8 =? fill " ") #f) "0" fill) align "<" "")))))
          (do
            (def w (if (eq? v #t) 1 (if (eq? v #f) 0 v)))
            (def kind (%py-num-kind w))
            (if (null? kind)
              (Err raise (lit type) "unsupported format string passed to object.__format__" ())
              ())
            ; integers with an integer or empty type
            (match
              ((if (eq? kind (lit int)) (= tc 99) #f)
                (if (if (null? sign) #f (not (Str8 =? sign "")))
                  (Err raise (lit value) "Sign not allowed with integer format specifier 'c'" ())
                  ; chr() answers a str and the padding below is Str8's, so the
                  ; character crosses over -- which also means '{:c}'.format(0)
                  ; refuses, like every other crossing into a platform string.
                  (%py-spec-pad (%ps->x (%py-str-cps (%py-fmt-char w)))
                    width fill align ">" "")))
              ((if (eq? kind (lit int))
                  (match
                    ((= tc 0) #t)
                    ((= tc 100) #t)
                    ((= tc 120) #t)
                    ((= tc 88) #t)
                    ((= tc 111) #t)
                    ((= tc 98) #t)
                    (#t (= tc 110)))
                  #f)
                (do
                  (if (not (null? prec))
                    (Err raise (lit value) "Precision not allowed in integer format specifier" ())
                    ())
                  (def m
                    (match
                      ((if (= tc 120) #t (= tc 88)) (%py-fmt-base w 16 (= tc 88)))
                      ((= tc 111) (%py-fmt-base w 8 #f))
                      ((= tc 98) (%py-fmt-base w 2 #f))
                      (#t (%py-fmt-int-mag w))))
                  ; _ groups binary, octal and hex digits by four
                  (def grp
                    (fn (_ ds)
                      (if (eq? comma #t) (%py-group3 ds)
                        (if (eq? comma (lit under))
                          (%py-group-sep ds
                            (if (match
                                  ((= tc 120) #t)
                                  ((= tc 88) #t)
                                  ((= tc 111) #t)
                                  (#t (= tc 98))) 4 3)
                            "_")
                          ds))))
                  (def pfx (if alt (match
                                     ((= tc 120) "0x")
                                     ((= tc 88) "0X")
                                     ((= tc 111) "0o")
                                     ((= tc 98) "0b")
                                     (#t "")) ""))
                  (def sgn (Str8 append (%py-fmt-sign (first m) (Str8 =? sign "+") (Str8 =? sign " ")) pfx))
                  ; THE 0 FLAG WITH GROUPING GROUPS THE PADDING TOO: '{:05,d}'
                  ; of 0 is 0,000 -- the fewest leading zeros whose grouped
                  ; form fills the width, overshooting when a separator lands
                  (def digits
                    (if (if (Str8 =? fill2 "0") (if (Str8 =? align2 "=") (if comma (not (null? width)) #f) #f) #f)
                      (do
                        (def target (- width (Str8 length sgn)))
                        (def grow
                          (fn (self k)
                            (let ((g (grp (Str8 append (%py-fmt-zeros k) (rest m)))))
                              (if (>= (Str8 length g) target) g (self (+ k 1))))))
                        (grow 0))
                      (grp (rest m))))
                  (%py-spec-pad digits width fill2 align2 ">" sgn)))
              ; floats -- and ints asked for a float type
              ((match
                 ((= tc 0) #t)
                 ((= tc 101) #t)
                 ((= tc 69) #t)
                 ((= tc 102) #t)
                 ((= tc 70) #t)
                 ((= tc 103) #t)
                 ((= tc 71) #t)
                 ((= tc 110) #t)
                 (#t (= tc 37)))
                (do
                  (def fv (%py-fmt-float-of w))
                  (def ex (%py-f-exact fv))
                  (def ekind (first ex))
                  (def neg (Str8 =? (first (rest ex)) "-"))
                  (def upper (if (= tc 69) #t (if (= tc 70) #t (= tc 71))))
                  (def sgn (%py-fmt-sign neg (Str8 =? sign "+") (Str8 =? sign " ")))
                  (if (not (eq? ekind (lit num)))
                    ; inf and nan pad like any number -- '{:06e}' of inf is
                    ; 000inf (measured, not assumed)
                    (let ((body0 (if (eq? ekind (lit inf)) "inf" "nan")))
                      (let ((body (Str8 append (if upper (Str8 upcase body0) body0) (if (= tc 37) "%" ""))))
                        (%py-spec-pad body width fill2 align2 ">" sgn)))
                    (do
                      (def D (first (rest (rest ex))))
                      (def x10 (first (rest (rest (rest ex)))))
                      (def p (if (null? prec) 6 prec))
                      (def body
                        (match
                          ((if (= tc 101) #t (= tc 69))
                            (%py-fmt-e D x10 p upper))
                          ((if (= tc 102) #t (= tc 70)) (%py-fmt-f D x10 p))
                          ((if (= tc 103) #t (if (= tc 71) #t (= tc 110)))
                            (%py-fmt-g D x10 p upper alt))
                          ((= tc 37)
                            (let ((ex2 (%py-f-exact (* fv 100.0))))
                              (Str8 append (%py-fmt-f (first (rest (rest ex2))) (first (rest (rest (rest ex2)))) p) "%")))
                          ; the empty type: repr without precision; with
                          ; precision like g, but a fixed result keeps at
                          ; least one digit after the point
                          ((null? prec)
                            (let ((r (%py-frepr fv))) (if neg (Str8 sub 1 (- (Str8 length r) 1) r) r)))
                          ; like g, but scientific already when the
                          ; exponent reaches p-1 (format(0.0, '.1') is
                          ; 0e+00), and fixed keeps one digit past the point
                          (#t
                            (let ((sc (%py-fmt-sci D x10 (- p 1))))
                              (let ((xa (first (rest (rest sc)))))
                                (if (if (>= xa (- 0 4)) (< xa (- p 1)) #f)
                                  (let ((g (%py-fmt-g D x10 p #f #f)))
                                    (if (null? (Str8 index-of "." g)) (Str8 append g ".0") g))
                                  (let ((fp (%py-fmt-strip0 (first (rest sc)))))
                                    (Str8 append
                                      (if (= (Str8 length fp) 0) (first sc)
                                        (Str8 append (first sc) (Str8 append "." fp)))
                                      (%py-fmt-exp-str xa #f)))))))))
                      (def body2 (if comma (%py-comma-float body (if (eq? comma #t) "," "_")) body))
                      (%py-spec-pad body2 width fill2 align2 ">" sgn)))))
              (#t
                (Err raise (lit value)
                  (Str8 append "Unknown format code '"
                    (Str8 append type
                      (Str8 append "' for object of type '"
                        (Str8 append (if (eq? kind (lit int)) "int" "float") "'")))) ())))))))))

; Digits grouped by k from the right with sep.
(def %py-group-sep
  (fn (_ digits k sep)
    (def n (Str8 length digits))
    (def go
      (fn (self i acc)
        (if (<= i 0) acc
          (let ((lo (if (< (- i k) 0) 0 (- i k))))
            (self lo
              (if (Str8 =? acc "") (Str8 sub lo (- i lo) digits)
                (Str8 append (Str8 sub lo (- i lo) digits) (Str8 append sep acc))))))))
    (go n "")))

; Grouping on a float body: only the integer digits before the point.
(def %py-comma-float
  (fn (_ body sep)
    (let ((dot (Str8 index-of "." body)))
      (if (null? dot)
        (%py-group-sep body 3 sep)
        (Str8 append (%py-group-sep (Str8 sub 0 dot body) 3 sep)
          (Str8 sub dot (- (Str8 length body) dot) body))))))

; One field of an f-string or a .format template: conversion then spec.
(def %py-fmtfield
  (fn (_ v conv spec)
    (let ((cv (match
                ; no conversion is the common field, so it is asked first
                ((Str8 =? conv "") v)
                ((Str8 =? conv "r") (%py-repr-of v))
                ((Str8 =? conv "s") (%py-str v))
                ((Str8 =? conv "a") (%py-repr-of v))
                (#t
                  (Err raise (lit value) "Unknown conversion specifier" ())))))
      (%py-format-spec cv spec))))

(def %py-fjoin
  (fn (_ parts)
    (def go (fn (self ps acc) (if (null? ps) acc (self (rest ps) (Str8 append acc (first ps))))))
    (go parts "")))

; The end of the run of ordinary characters starting at j: the index of the
; next brace, or the end of the template.  The walkers below append a run in
; one piece.  A character at a time cost two guarded string-class calls each
; and recopied the accumulator, which made a template's literal text by far
; the largest part of a format: ~43,000 objects per character against ~2,000
; for the same text crossing the str boundary.
; The byte comes through the primitives rather than %py-spec-code: that is
; an interpreted call, and this scan would pay one per character.
(def %py-fmt-run
  (fn (self tpl n j)
    (if (>= j n)
      j
      (let ((c (%py-char-code (%str-ref tpl j))))
        (if (if (= c 123) #t (= c 125)) j (self tpl n (+ j 1)))))))

; str.format: the same template grammar as an f-string, walked at RUNTIME
; against positional arguments -- {} auto-numbers, {2} indexes, and a field's
; .attr / [key] tail is followed.  A spec may itself contain fields
; ({:{}} takes its width from the next argument).  Keyword fields wait on
; keyword arguments.
(def %py-strformat-kw
  (fn (_ tpl args kws)
    (def n (Str8 length tpl))
    (def auto (pair 0 ()))
    ; () until the first field, then auto or manual: mixing is a ValueError
    (def mode (pair () ()))
    (def argn (%py-length args))
    (def arg-at
      (fn (_ i)
        (if (>= i argn)
          (Err raise (lit index) "Replacement index out of range for positional args tuple" ())
          (List ref i args))))
    (def resolve
      (fn (_ name)
        ; name: "" | digits | identifier, followed by .attr / [key] tails
        (def nn (Str8 length name))
        (def head-end
          (fn (self j)
            (if (>= j nn) j
              (let ((c (%py-spec-code name j)))
                (if (if (= c 46) #t (= c 91)) j (self (+ j 1)))))))
        (def he (head-end 0))
        ; an empty head is the auto-numbered field, and no head to cut: the
        ; string comes out only when there is one
        (def base
          (if (= he 0)
            (do
              (if (eq? (first mode) (lit manual))
                (Err raise (lit value) "cannot switch from manual field specification to automatic field numbering" ())
                (%set-first! mode (lit auto)))
              (let ((i (first auto))) (%set-first! auto (+ i 1)) (arg-at i)))
            (let ((head (Str8 sub 0 he name)))
              (if (%py-fmt-digit? (%py-spec-code head 0))
                (do
                  (if (eq? (first mode) (lit auto))
                    (Err raise (lit value) "cannot switch from automatic field numbering to manual field specification" ())
                    (%set-first! mode (lit manual)))
                  (arg-at (%py-int-of-str head)))
                (let ((kw (%py-alist-find head kws)))
                  (if (null? kw)
                    (Err raise (lit key) (Str8 append (Str8 append "'" head) "'") ())
                    (rest kw)))))))
        (def head-end-from
          (fn (_ j)
            (def go (fn (self k) (if (>= k nn) k (let ((c (%py-spec-code name k))) (if (if (= c 46) #t (= c 91)) k (self (+ k 1)))))))
            (go j)))
        (def tail
          (fn (self j v)
            (if (>= j nn) v
              (let ((c (%py-spec-code name j)))
                (if (= c 46)
                  (let ((e (head-end-from (+ j 1))))
                    (self e (%py-getattr v (Str8 sub (+ j 1) (- e (+ j 1)) name))))
                  (let ((close (Str8 index-of "]" (Str8 sub j (- nn j) name))))
                    (if (null? close)
                      (Err raise (lit value) "Missing ']' in format string" ())
                      (let ((key (Str8 sub (+ j 1) (- close 1) name)))
                        (self (+ j close 1)
                          ; {0[k]} INDEXES A PYTHON CONTAINER, so a string key
                          ; crosses over first: the key is cut out of the
                          ; template with Str8, and a dict's keys are strs --
                          ; the platform string would match none of them and
                          ; the lookup would raise KeyError on a key that is
                          ; plainly there.  (An attribute tail, just above,
                          ; wants the platform string and keeps it.)
                          (%py-index v
                            (if (%py-fmt-digit? (%py-spec-code key 0))
                              (%py-int-of-str key)
                              (%py-str-of-x key))))))))))))
        (tail he base)))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-spec-code tpl i)))
            (if (= c 123)
              (if (if (< (+ i 1) n) (= (%py-spec-code tpl (+ i 1)) 123) #f)
                (self (+ i 2) (Str8 append acc "{"))
                (let ((close (guard (_ (Err raise (lit value) "Single '{' encountered in format string" ()))
                               (%py-fs-close tpl (+ i 1) 0))))
                  ; {} has nothing to split: no name, no conversion, no spec.
                  ; It is the commonest field there is, and parsing it anyway
                  ; cost eleven guarded string calls.
                  (if (= close (+ i 1))
                    (self (+ close 1) (Str8 append acc (%py-fmtfield (resolve "") "" "")))
                    (let ((field (Str8 sub (+ i 1) (- close (+ i 1)) tpl)))
                      (def fn0 (Str8 length field))
                      (def at (%py-fs-split field 0 0))
                      (def name (if (null? at) field (Str8 sub 0 at field)))
                      (def tl (if (null? at) "" (Str8 sub at (- fn0 at) field)))
                      (def conv
                        (if (if (> (Str8 length tl) 1) (= (%py-spec-code tl 0) 33) #f)
                          (Str8 sub 1 1 tl) ""))
                      (def after (if (Str8 =? conv "") tl (Str8 sub 2 (- (Str8 length tl) 2) tl)))
                      (if (if (> (Str8 length after) 0) (not (= (%py-spec-code after 0) 58)) #f)
                        (Err raise (lit value) "expected ':' after conversion specifier" ())
                        ())
                      (def spec0
                        (if (if (> (Str8 length after) 0) (= (%py-spec-code after 0) 58) #f)
                          (Str8 sub 1 (- (Str8 length after) 1) after) ""))
                      ; the VALUE takes its auto-number before a nested spec
                      ; draws width or precision from the args that follow it
                      (def v (resolve name))
                      (def spec (if (null? (Str8 index-of "{" spec0)) spec0 (%py-strformat-sub spec0 args auto kws)))
                      (self (+ close 1) (Str8 append acc (%py-fmtfield v conv spec)))))))
              (if (= c 125)
                (if (if (< (+ i 1) n) (= (%py-spec-code tpl (+ i 1)) 125) #f)
                  (self (+ i 2) (Str8 append acc "}"))
                  (Err raise (lit value) "Single '}' encountered in format string" ()))
                (let ((e (%py-fmt-run tpl n (+ i 1))))
                  (self e (Str8 append acc (Str8 sub i (- e i) tpl))))))))))
    (go 0 "")))

(def %py-strformat (fn (_ tpl args) (%py-strformat-kw tpl args ())))

; A nested spec shares the caller's auto-counter: {:{}} consumes the next
; positional argument for its width.
(def %py-strformat-sub
  (fn (_ tpl args auto kws)
    (def n (Str8 length tpl))
    (def argn (%py-length args))
    (def go
      (fn (self i acc)
        (if (>= i n)
          acc
          (let ((c (%py-spec-code tpl i)))
            (if (= c 123)
              (let ((close (%py-fs-close tpl (+ i 1) 0)))
                (let ((name (Str8 sub (+ i 1) (- close (+ i 1)) tpl)))
                  (let ((v (if (Str8 =? name "")
                             (let ((k (first auto))) (%set-first! auto (+ k 1))
                               (if (>= k argn) (Err raise (lit index) "Replacement index out of range" ()) (List ref k args)))
                             (if (%py-fmt-digit? (%py-spec-code name 0))
                               (List ref (%py-int-of-str name) args)
                               (let ((kw (%py-alist-find name kws)))
                                 (if (null? kw)
                                   (Err raise (lit key) (Str8 append (Str8 append "'" name) "'") ())
                                   (rest kw)))))))
                    (self (+ close 1) (Str8 append acc (%py-str v))))))
              (let ((e (%py-fmt-run tpl n (+ i 1))))
                (self e (Str8 append acc (Str8 sub i (- e i) tpl)))))))))
    (go 0 "")))


(def %py-drop-last
  (fn (self lst)
    (if (null? (rest lst)) () (pair (first lst) (self (rest lst))))))

