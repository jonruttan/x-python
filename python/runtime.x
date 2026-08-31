; # x-python -- Python on x-lang
;
; ## python/runtime.x -- what Python's operators actually mean
;
; @description The functions the parser emits calls to. Python's operators are
;   not x's, so they get their own names rather than a mapping.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; ## WHY NOT JUST EMIT x's `+`
;
; Because `+` is not the same function. Python's is overloaded across numbers,
; strings, lists and tuples and refuses to mix them -- `1 + "a"` is a TypeError,
; not a coercion -- and `/` always produces a float where x's produces an exact
; rational. A parser that emitted x's operators would be writing a language that
; looks like Python and computes differently, which is the failure mode the lang
; contract calls "a different language wearing the same clothes".
;
; So the parser emits calls to these, and every one of them is a place where a
; Python rule can be stated. Today most of them are thin; that is the point --
; they are named seams, not indirection for its own sake.

(import python/types)

(provide python/runtime
  %py-add %py-sub %py-mul %py-div %py-floordiv %py-mod %py-pow %py-neg
  %py-eq %py-ne %py-lt %py-gt %py-le %py-ge
  %py-print %py-display
  %py-mklist %py-index %py-len %py-list? %py-write %py-getattr %py-setindex
  %py-range %py-iter-elems %py-callcc
  %py-raise %py-exc-match
  %py-mkclass %py-setattr
  %py-exc-Exception %py-exc-ArithmeticError %py-exc-LookupError
  %py-exc-ZeroDivisionError %py-exc-IndexError %py-exc-KeyError
  %py-exc-AttributeError %py-exc-NameError %py-exc-TypeError
  %py-exc-ValueError %py-exc-RuntimeError %py-exc-SyntaxError
  %py-mkdict %py-dict? %py-dget %py-dset)

; --- Arithmetic --------------------------------------------------------------
; `+` dispatches on the operands, and the string case is not an extra: Python
; spells concatenation with it, and every conformance program that builds a
; message uses it.
(def %py-add
  (fn (_ a b)
    (if (str? a)
      (if (str? b)
        (Str8 append a b)
        (Err raise (lit type) "can only concatenate str to str" ()))
      (if (str? b)
        ; `1 + "a"` is a TypeError in Python, not a coercion.  Without this it
        ; reached x's `+` with a string operand and answered a number.
        (Err raise (lit type) "unsupported operand type(s) for +" ())
        ; Lists concatenate through PY-LIST's own `+` op, which the engine
        ; dispatches from here.
        (+ a b)))))

(def %py-sub (fn (_ a b) (- a b)))
; STRING REPETITION IS HANDLED HERE, NOT ON THE TYPE.  A type's ops fire when
; either operand carries the type, so pushing `*` onto x's str type would change
; what `*` means for every string in the process, the platform's included.  The
; containers can have ops because they are types this bundle invented; str is
; not, so its Python rules stay behind a `str?` test.
(def %py-str-repeat
  (fn (self s n) (if (<= n 0) "" (Str8 append s (self s (- n 1))))))

(def %py-mul
  (fn (_ a b)
    (if (str? a)
      (if (str? b)
        (Err raise (lit type) "can't multiply sequence by non-int" ())
        (%py-str-repeat a b))
      (if (str? b)
        (%py-str-repeat b a)
        (* a b)))))

; TRUE DIVISION ALWAYS PRODUCES A FLOAT.  `1 / 2` is 0.5 in Python 3 and an
; exact 1/2 in x, and that difference is the reason this bundle declares xenon
; -- float is reachable from the first arithmetic a beginner types.
; DIVISION BY ZERO RAISES.  It answered `inf` for `1 / 0`, `0` for `1 // 0`
; and None for `1 % 0` -- three more silent wrong answers, and the three
; Python spells ZeroDivisionError.  The messages are Python's own, which
; differ between true and floor division.
;
; These raise an Err rather than building an instance, like every other raise
; this runtime makes.  The kind is what `except ZeroDivisionError` matches on;
; see the exception section for why both shapes are caught the same way.
(def %py-div
  (fn (_ a b)
    (if (= b 0)
      (Err raise (lit zero-division) "division by zero" ())
      (/ (* a 1.0) b))))

(def %py-floordiv
  (fn (_ a b)
    (if (= b 0)
      (Err raise (lit zero-division) "integer division or modulo by zero" ())
      (Num quotient a b))))
(def %py-mod
  (fn (_ a b)
    (if (= b 0)
      (Err raise (lit zero-division) "integer modulo by zero" ())
      (Num modulo a b))))
; NEVER HAND Num expt A NEGATIVE EXPONENT.  Its parameter is documented
; "Non-negative integer exponent" and nothing enforces it: with exp < 0 the
; recursion never reaches 0 and SQUARES THE BASE on every even step, so it
; allocates exponentially growing bignums until the machine dies.  Not a hang --
; an unbounded-allocation bomb, and `2 ** -1` is ordinary Python.
;
; Python's answer is a float: 2 ** -1 is 0.5.
(def %py-pow
  (fn (_ a b)
    (if (< b 0)
      (/ 1.0 (Num expt a (- 0 b)))
      (Num expt a b))))
(def %py-neg (fn (_ a) (- 0 a)))

; --- Comparison --------------------------------------------------------------
(def %py-eq (fn (_ a b) (if (str? a) (if (str? b) (Str8 =? a b) #f) (= a b))))
(def %py-ne (fn (_ a b) (not (%py-eq a b))))
(def %py-lt (fn (_ a b) (< a b)))
(def %py-gt (fn (_ a b) (> a b)))
(def %py-le (fn (_ a b) (if (< a b) #t (= a b))))
(def %py-ge (fn (_ a b) (if (> a b) #t (= a b))))

; --- Lists ------------------------------------------------------------------
;
; TAGGED, not a bare x list.  An empty Python list and None are different
; values, and a bare x list would make both of them nil -- so `print([])` would
; print None.  A list is (py-list . elements): the tag distinguishes it from
; every other value this runtime produces, and from nil.
(def %py-mklist (fn (_ . elems) (%py-list-new elems)))

(def %py-list? (fn (_ v) (%py-list-is v)))

(def %py-len
  (fn (_ v)
    (if (%py-dict? v)
      (List length (%py-dict-entries v))
    (if (%py-list? v)
      (List length (%py-list-elems v))
      (if (str? v)
        (Str8 length v)
        (Err raise (lit type) "object of this type has no len()" ()))))))

; NEGATIVE INDICES COUNT FROM THE END, which is Python and not x.  -1 is the
; last element, and an index past either end raises IndexError rather than
; returning nil -- a silent nil would propagate into arithmetic and surface far
; from the subscript that produced it.
(def %py-index
  (fn (_ v i)
    (if (str? v)
      ; A string index yields a one-character STRING, as in Python -- there is
      ; no character type at this surface.
      (let ((n (Str8 length v)))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "string index out of range" ())
            (Str8 sub k 1 v))))
    ; Subscripting a dict is a call too -- see the list branch below.
    (if (%py-dict? v)
      (v i)
    (if (not (%py-list? v))
      (Err raise (lit type) "object is not subscriptable" ())
      ; SUBSCRIPTING A LIST IS A CALL.  x dispatches `(v i)` through the type's
      ; `call` handler, so negative indices and IndexError are stated once in
      ; python/types.x rather than copied here.
      (v i))))))

; Store into a list at an index.  Rebuilds the element list and hangs it back on
; the SAME tag pair, so every reference sees the store -- the identity argument
; that made append work.
(def %py-set-nth
  (fn (self lst k v)
    (if (= k 0)
      (pair v (rest lst))
      (pair (first lst) (self (rest lst) (- k 1) v)))))

(def %py-setindex
  (fn (_ obj i v)
    (if (%py-dict? obj)
      (%py-dset obj i v)
    (if (not (%py-list? obj))
      (Err raise (lit type) "object does not support item assignment" ())
      (let ((n (List length (%py-list-elems obj))))
        (let ((k (if (< i 0) (+ n i) i)))
          (if (if (< k 0) #t (>= k n))
            (Err raise (lit index) "list assignment index out of range" ())
            (%py-list-set! obj (%py-set-nth (%py-list-elems obj) k v)))))))))

; The escape continuation a `return` invokes.  Fetched rather than assumed
; global, the way every other prim in this bundle is reached.
(def %py-callcc (prim-ref (lit ctrl) (lit call/cc)))

; --- Iteration ---------------------------------------------------------------
;
; The elements a `for` walks.  A list gives its own; a string gives its
; characters, because Python iterates a string by character and several
; conformance programs depend on it.
(def %py-str-chars
  (fn (self v i n)
    (if (>= i n) () (pair (Str8 sub i 1 v) (self v (+ i 1) n)))))

(def %py-iter-elems
  (fn (_ v)
    ; Iterating a dict yields its KEYS, as in Python.
    (if (%py-dict? v)
      (%py-dkeys (%py-dict-entries v))
    (if (%py-list? v)
      (%py-list-elems v)
      (if (str? v)
        (%py-str-chars v 0 (Str8 length v))
        (Err raise (lit type) "object is not iterable" ()))))))

; range(stop) / range(start, stop) / range(start, stop, step)
;
; EAGER, and that is a simplification with a known cost: Python 3's range is
; lazy, so `range(10000000)` is free there and a ten-million element list here.
; Every conformance program that uses range walks all of it, so the difference
; is memory rather than answers -- but it is a difference, and it is written
; down rather than discovered.
;
; A zero step raises rather than looping forever.  There is no depth limit on
; non-tail calls here (x-lang#56), so an unbounded loop is an OOM.
(def %py-range-build
  (fn (self i stop step acc)
    (if (if (> step 0) (>= i stop) (<= i stop))
      (List reverse acc)
      (self (+ i step) stop step (pair i acc)))))

(def %py-range
  (fn (_ . args)
    (if (null? args)
      (Err raise (lit type) "range expected at least 1 argument" ())
      (let ((start (if (null? (rest args)) 0 (first args)))
            (stop  (if (null? (rest args)) (first args) (first (rest args))))
            (step  (if (null? (rest args)) 1
                     (if (null? (rest (rest args))) 1
                       (first (rest (rest args)))))))
        (if (= step 0)
          (Err raise (lit value) "range() arg 3 must not be zero" ())
          (%py-list-new (%py-range-build start stop step ())))))))

; --- Dicts -------------------------------------------------------------------
;
; ENTRIES IN INSERTION ORDER, not a hash table. x/type/dict.x is a content-hashed
; mutable table and would be faster, but Python 3.7+ preserves insertion order
; and the conformance suite compares PRINTED output -- so the order is part of
; the answer, not an implementation detail. An association list keeps it for
; free; lookup is O(n), which is the right trade at this size.
;
; The representation is python/types.x's PY-DICT; what is here is what the
; parser calls and what Python's rules say.
(def %py-dict? (fn (_ v) (%py-dict-is v)))

(def %py-mkdict (fn (_ . entries) (%py-dict-new entries)))

(def %py-dfind
  (fn (self k entries)
    (if (null? entries)
      ()
      (if (%py-eq k (first (first entries)))
        (first entries)
        (self k (rest entries))))))

(def %py-dget
  (fn (_ d k)
    (let ((e (%py-dfind k (%py-dict-entries d))))
      (if (null? e)
        (Err raise (lit key) "key not found" ())
        (rest e)))))

(def %py-dappend
  (fn (self entries e)
    (if (null? entries) (list e) (pair (first entries) (self (rest entries) e)))))

(def %py-dset
  (fn (_ d k v)
    (let ((e (%py-dfind k (%py-dict-entries d))))
      (if (null? e)
        ; A new key goes on the END: insertion order is the printed order.
        (%py-dict-set! d (%py-dappend (%py-dict-entries d) (pair k v)))
        (%seq (%set-rest! e v) ())))))

(def %py-dkeys (fn (self entries) (if (null? entries) () (pair (first (first entries)) (self (rest entries))))))
(def %py-dvals (fn (self entries) (if (null? entries) () (pair (rest (first entries)) (self (rest entries))))))

(def %py-dict-attr
  (fn (_ d name)
    (if (Str8 =? name "keys")   (fn (_) (%py-list-new (%py-dkeys (%py-dict-entries d))))
    (if (Str8 =? name "values") (fn (_) (%py-list-new (%py-dvals (%py-dict-entries d))))
    (if (Str8 =? name "get")
      ; get returns a default instead of raising -- that is the whole reason it
      ; exists next to subscripting.
      (fn (_ k . dflt)
        (let ((e (%py-dfind k (%py-dict-entries d))))
          (if (null? e) (if (null? dflt) () (first dflt)) (rest e))))
    (Err raise (lit attribute)
      (Str8 append (Str8 append "'dict' object has no attribute '" name) "'")
      ()))))))

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
    (if (%py-list? obj)
      (if (Str8 =? name "append")
        (fn (_ v) (%py-list-set! obj (%py-append-elem (%py-list-elems obj) v)))
        (if (Str8 =? name "pop")
          (fn (_ . a)
            (let ((n (List length (%py-list-elems obj))))
              (if (= n 0)
                (Err raise (lit index) "pop from empty list" ())
                (let ((v (List ref (- n 1) (%py-list-elems obj))))
                  (%seq (%py-list-set! obj (%py-drop-last (%py-list-elems obj))) v)))))
          (Err raise (lit attribute)
            (Str8 append (Str8 append "'list' object has no attribute '" name) "'")
            ())))
      (if (%py-dict? obj)
        (%py-dict-attr obj name)
      (if (str? obj)
        (%py-str-attr obj name)
      (if (%py-obj-is obj)
        (%py-obj-attr obj name)
        (Err raise (lit attribute)
          (Str8 append (Str8 append "object has no attribute '" name) "'")())))))))

; STRING METHODS MAP ONTO Str8, WHICH ALREADY HAS THEM -- upcase, downcase,
; trim, split, join, replace, starts?, ends?, index-of. The work here is the
; SHAPE, not the algorithm: Str8 takes its subject LAST, Python takes it first
; as the receiver, and split/join cross the list boundary so their results have
; to be tagged or untagged on the way through.
;
; find() returns -1 when absent, which is Python's contract and the reason it is
; not index() -- that one raises. Only find is here.
(def %py-str-attr
  (fn (_ s name)
    (if (Str8 =? name "upper")   (fn (_) (Str8 upcase s))
    (if (Str8 =? name "lower")   (fn (_) (Str8 downcase s))
    (if (Str8 =? name "strip")   (fn (_) (Str8 trim s))
    (if (Str8 =? name "split")
      ; Python's split returns a LIST, so the result is tagged on the way out.
      (fn (_ . a)
        (%py-list-new (Str8 split (if (null? a) " " (first a)) s)))
    (if (Str8 =? name "join")
      ; and join takes one, so it is untagged on the way in.
      (fn (_ lst)
        (if (not (%py-list? lst))
          (Err raise (lit type) "can only join an iterable of str" ())
          (Str8 join s (%py-list-elems lst))))
    (if (Str8 =? name "replace")
      (fn (_ old new) (Str8 replace old new s))
    (if (Str8 =? name "startswith") (fn (_ p) (Str8 starts? p s))
    (if (Str8 =? name "endswith")   (fn (_ p) (Str8 ends? p s))
    ; Str8 index-of answers nil for absent; Python's find answers -1. Passing
    ; the nil through would print None and, worse, compare equal to nothing --
    ; `if s.find(x) == -1` would silently never fire.
    (if (Str8 =? name "find")
      (fn (_ sub)
        (let ((i (Str8 index-of sub s)))
          (if (null? i) (- 0 1) i)))
      (Err raise (lit attribute)
        (Str8 append (Str8 append "'str' object has no attribute '" name) "'")
        ()))))))))))))

(def %py-drop-last
  (fn (self lst)
    (if (null? (rest lst)) () (pair (first lst) (self (rest lst))))))

; --- print -------------------------------------------------------------------
; Python's `print` is not `display`: arguments are separated by a single space,
; a newline follows, and a string prints WITHOUT its quotes while everything
; else prints as its repr. The conformance suite asserts on stdout, so this is
; the single most load-bearing function in the bundle.
; Python prints True/False; x displays #t/#f. That is a rendering difference,
; not a value difference, and it belongs here rather than in the parser --
; every conformance program that prints a comparison depends on it.
;
; `display` is otherwise already right: it writes a string WITHOUT quotes and a
; number as a number, which is what print wants. `write` would quote the string.
; REPR WRITES, IT DOES NOT BUILD A STRING.  Rendering a number into a string
; would need a number->string conversion this layer does not have; writing it
; needs only `display`, which already knows how.  So repr is a procedure that
; emits, and the container cases emit their punctuation around it.
(def %py-write ())
(set! %py-write
  (fn (_ v)
    (if (str? v)
      ; A string inside a container shows its quotes; on its own it does not.
      (%seq (display "'") (%seq (display v) (display "'")))
      (if (eq? v #t)
        (display "True")
        (if (eq? v #f)
          (display "False")
          (if (null? v)
            (display "None")
            (if (%py-list? v)
              ; The type's `write` handler renders it, calling back here per element.
              (write v)
              (if (%py-dict? v)
                (write v)
                ; str(e) in Python is the MESSAGE, not the repr -- `print(e)`
                ; inside an except block shows "division by zero", not
                ; "#<err:zero-division division by zero>".
                (if (Err err? v)
                  (display (v msg))
                ; An exception INSTANCE prints as its message too -- print(e)
                ; has to read the same whether the raise came from Python source
                ; or from this runtime.
                (if (%py-obj-is v)
                  (if (%py-subclass? (%py-obj-class v) %py-exc-Exception)
                    (display (%py-exc-msg v))
                    (display v))
                  (display v)))))))))))

; Close the loop: python/types.x forward-declares %py-repr and its PY-LIST write
; handler calls it per element, so that a string inside a list shows its quotes.
; The hook is set HERE because repr is Python's rule, not the container's.
(set! %py-repr %py-write)

; and the PY-DICT `call` handler reaches Python's equality the same way.
(set! %py-dict-get %py-dget)

; and the container equality ops compare their elements with Python's rule,
; which is what makes nested containers come out right.
(set! %py-equal %py-eq)


; display and write differ in exactly ONE way: a string prints BARE at top level
; and quoted inside a container. Everything else -- True/False/None, lists,
; dicts, numbers -- is identical, so this defers rather than restating the
; cases. Restating them is how dicts came to print as raw pairs: the dict branch
; was added to write and not to its copy here.
(def %py-display
  (fn (_ v)
    (if (str? v) (display v) (%py-write v))))

(def %py-print
  (fn (_ . args)
    (def %go
      (fn (self vs first?)
        (if (null? vs)
          ()
          (%seq
            (if first? () (display " "))
            (%seq (%py-display (first vs))
              (self (rest vs) #f))))))
    (%seq (%go args #t) (newline))))

; --- Exceptions --------------------------------------------------------------
;
; PYTHON'S EXCEPTION TYPES ARE CLASSES, AND THE HIERARCHY IS THE POINT.
;
; The first version of this file mapped exception NAMES to x error KINDS with a
; string table, and `Exception` matched everything by a special case written
; into the matcher.  That worked and could not grow: `except LookupError`
; catching both IndexError and KeyError is not a special case, it is what
; deriving from a common base MEANS, and a flat table has no way to say it.
;
; So the builtin exceptions are real PY-CLASS values, in Python's own shape, and
; matching walks the base chain.  `Exception` is no longer special -- it is just
; the root every other one reaches.
;
; TWO KINDS OF RAISED VALUE ARRIVE HERE.  A `raise` in Python source produces a
; PY-OBJ instance.  Everything this runtime raises itself -- a bad subscript, a
; missing key -- produces an Err carrying a kind symbol, because those raises
; predate classes by a long way and rewriting them would gain nothing.  The
; kind table below is the bridge: an Err's kind names the class it would have
; been, and from there both kinds of value match identically.

(def %py-exc-Exception
  (%py-class-new "Exception" ()
    ; Every exception gets a message, and this is where it is stored.  A user
    ; class that defines its own __init__ overrides this and gets no message
    ; unless it sets one -- Python would have it call super().__init__, which
    ; does not exist here.
    (list
      (pair "__init__"
        (fn (_ self . args)
          (%py-setattr self "__msg__" (if (null? args) "" (first args))))))))

(def %py-exc-new (fn (_ name base) (%py-class-new name base ())))

(def %py-exc-ArithmeticError (%py-exc-new "ArithmeticError" %py-exc-Exception))
(def %py-exc-LookupError     (%py-exc-new "LookupError"     %py-exc-Exception))
(def %py-exc-ZeroDivisionError
  (%py-exc-new "ZeroDivisionError" %py-exc-ArithmeticError))
(def %py-exc-IndexError      (%py-exc-new "IndexError"      %py-exc-LookupError))
(def %py-exc-KeyError        (%py-exc-new "KeyError"        %py-exc-LookupError))
(def %py-exc-AttributeError  (%py-exc-new "AttributeError"  %py-exc-Exception))
(def %py-exc-NameError       (%py-exc-new "NameError"       %py-exc-Exception))
(def %py-exc-TypeError       (%py-exc-new "TypeError"       %py-exc-Exception))
(def %py-exc-ValueError      (%py-exc-new "ValueError"      %py-exc-Exception))
(def %py-exc-RuntimeError    (%py-exc-new "RuntimeError"    %py-exc-Exception))
(def %py-exc-SyntaxError     (%py-exc-new "SyntaxError"     %py-exc-Exception))

; An Err's kind names the class it would have been.  A kind with no row -- one
; raised by the platform rather than by this runtime -- answers Exception, so
; `except Exception` still catches it rather than letting it through a handler
; that looks like it should have caught it.
(def %py-kind-classes
  (list
    (pair (lit type)          %py-exc-TypeError)
    (pair (lit value)         %py-exc-ValueError)
    (pair (lit index)         %py-exc-IndexError)
    (pair (lit key)           %py-exc-KeyError)
    (pair (lit name)          %py-exc-NameError)
    (pair (lit attribute)     %py-exc-AttributeError)
    (pair (lit zero-division) %py-exc-ZeroDivisionError)
    (pair (lit syntax)        %py-exc-SyntaxError)
    (pair (lit state)         %py-exc-RuntimeError)))

(def %py-kind-class
  (fn (self k rows)
    (if (null? rows)
      %py-exc-Exception
      (if (eq? k (first (first rows)))
        (rest (first rows))
        (self k (rest rows))))))

; The class of whatever was raised, whichever of the two shapes it is.
(def %py-exc-class-of
  (fn (_ e)
    (if (%py-obj-is e)
      (%py-obj-class e)
      (%py-kind-class (Err kind-of e) %py-kind-classes))))

(def %py-subclass?
  (fn (self c target)
    (if (null? c)
      #f
      (if (eq? c target) #t (self (%py-class-base c) target)))))

(def %py-exc-match
  (fn (_ e cls)
    (if (not (%py-class-is cls))
      (Err raise (lit type)
        "catching classes that do not inherit from BaseException is not allowed"
        ())
      (%py-subclass? (%py-exc-class-of e) cls))))

; `raise X(...)` CALLS X and raises the result, which is what Python does -- and
; is why an undefined name answers NameError here without any special case: the
; parser emits a call, and an undefined name is bound to a shim that raises when
; called.
(def %py-raise
  (fn (_ inst)
    (if (if (%py-obj-is inst)
          (%py-subclass? (%py-obj-class inst) %py-exc-Exception)
          #f)
      (error inst)
      ; An ordinary object is not raisable, and neither is a number or a string.
      (Err raise (lit type) "exceptions must derive from BaseException" ()))))

; UNCAUGHT, AN INSTANCE RENDERS AS `Name: message`.  Without this it printed
; `<__main__.KeyError object>` -- the object form is right for an ordinary
; object and useless for the one case where a human is reading it because the
; program just died.  Python's traceback ends in exactly this line.
(set! %py-obj-write
  (fn (_ o)
    (if (%py-subclass? (%py-obj-class o) %py-exc-Exception)
      (display (%py-class-name (%py-obj-class o)) ": " (%py-exc-msg o))
      (display "<__main__." (%py-class-name (%py-obj-class o)) " object>"))))

; The message an exception carries, for print(e) and str(e).
(def %py-exc-msg
  (fn (_ e)
    (let ((a (%py-alist-find "__msg__" (%py-obj-attrs e))))
      (if (null? a) "" (rest a)))))

; --- Classes -----------------------------------------------------------------
;
; Method lookup walks the base chain, which is the ONE piece of Python's object
; model that cannot be faked by a flat alist: `class Dog(Animal)` means a Dog
; finds Animal's methods, and `super`-less overriding means the derived class is
; searched first.  Attributes do not walk -- they live on the instance.

(def %py-alist-find
  (fn (self k rows)
    (if (null? rows)
      ()
      (if (Str8 =? k (first (first rows)))
        (first rows)
        (self k (rest rows))))))

; Derived first, then the base, then the base's base.
(def %py-method-find
  (fn (self cls name)
    (if (null? cls)
      ()
      (let ((e (%py-alist-find name (%py-class-methods cls))))
        (if (null? e)
          (self (%py-class-base cls) name)
          (rest e))))))

; A BOUND METHOD IS JUST A CLOSURE OVER THE OBJECT.  A method compiles to
; (fn (_ py-self ...) ...) -- the leading _ absorbs x's self-binding -- so
; calling it with the object as the first argument is all "bound" means.
(def %py-bind-method
  (fn (_ m obj) (fn (_ . args) (apply m (pair obj args)))))

(def %py-obj-attr
  (fn (_ obj name)
    (let ((e (%py-alist-find name (%py-obj-attrs obj))))
      (if (not (null? e))
        (rest e)
        (let ((m (%py-method-find (%py-obj-class obj) name)))
          (if (null? m)
            (Err raise (lit attribute)
              (Str8 append
                (Str8 append
                  (Str8 append "'" (%py-class-name (%py-obj-class obj)))
                  "' object has no attribute '")
                (Str8 append name "'"))
              ())
            (%py-bind-method m obj)))))))

; Setting an attribute REPLACES the entry or appends one, and hangs the result
; back on the instance's cell so every reference sees it -- the same identity
; argument the containers needed.
(def %py-attr-put
  (fn (self rows k v)
    (if (null? rows)
      (list (pair k v))
      (if (Str8 =? k (first (first rows)))
        (pair (pair k v) (rest rows))
        (pair (first rows) (self (rest rows) k v))))))

(def %py-setattr
  (fn (_ obj name v)
    (if (not (%py-obj-is obj))
      (Err raise (lit attribute) "object does not support attribute assignment" ())
      (%py-obj-set-attrs! obj (%py-attr-put (%py-obj-attrs obj) name v)))))

(def %py-mkclass
  (fn (_ name base methods) (%py-class-new name base methods)))

; Construction: make the instance, then run __init__ if the class chain has one.
; Its return value is discarded -- Python returns the INSTANCE from a call to a
; class, whatever __init__ answers.
(set! %py-instantiate
  (fn (_ cls args)
    (let ((o (%py-obj-new cls)))
      (let ((init (%py-method-find cls "__init__")))
        (if (null? init)
          o
          (%seq (apply init (pair o args)) o))))))
