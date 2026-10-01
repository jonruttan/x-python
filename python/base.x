; # x-python -- Python on x-lang
;
; ## python/base.x -- the language, assembled
;
; @description Python 3: an indentation-delimited, statement-oriented surface
;   over x-lang's evaluator, with a conformance scoreboard behind it.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; No path literals and no dialect boot here: run.x owns both.  Nothing under
; py/ includes a platform module -- re-including one on a booted tower is a
; SEGFAULT with no diagnostic (x-lang#515), and it is the first thing anyone
; assembling a bundle hits.
;
; ## THE ENTRY POINT IS ONE FUNCTION, AND THAT IS ON PURPOSE
;
; `(python-run SRC)` takes a whole Python program as a string, runs it, and lets
; whatever it printed go to stdout.  Not `py-tokenize`, not `py-parse`: the
; suite this bundle is built against is 682 whole programs compared on their
; stdout, so the seam the specs press on had better be the seam the suite
; presses on.  x-ash spec'd `sh-tokenize` and can tell you its token list is
; right while `'a'` still loses its accumulator; that is a lesson, not a model.
;
; The internal seams have since appeared -- a tokenizer, an INDENT/DEDENT layer,
; a parser -- and each carries its own specs under tests/specs/.  They do not
; get to be the only thing measured: the conformance suite still presses on
; python-run, because that is the seam a Python program presses on.
;
; ## THE SCOREBOARD CAME FIRST, AND THIS FILE CAME SECOND
;
; `tools/conformance/` turns 682 MicroPython test programs into .spec.md files
; whose expected output is a real CPython 3.14 run, so before a line of
; tokenizer existed there was a sorted list of what Python actually asks for.
; That ordering is why the layers below are the layers they are: the ranked
; groups named the reader as the thing nothing else was reachable without.
;
; This file no longer stubs anything.  `python-run` lexes, parses and evaluates
; -- tokens.x, indent.x, types.x, runtime.x and parse.x, in that order -- and
; what it cannot do it fails at rather than answering uniformly.  The suite
; measures the difference; `make score` ranks what is still red.

(import python/util)
; A sweep after each load; see python/util.x.
(import python/tokens python-tokenize)
(%py-sweep!)
(import python/indent)
(%py-sweep!)
(import python/types)
(%py-sweep!)
(import python/str)
(%py-sweep!)
(import python/runtime)
(%py-sweep!)
(import python/parse)
(%py-sweep!)

(provide python/base python-version python-run python-tokenize python-lex python-parse python-parse-expr %python-repl-print
  %py-eval %py-exec %py-compile %py-module-env %py-code-run %py-function-over
  %py-code-answer)

; the one number sys.implementation.version is read from too
(def python-version %py-implementation-version)

; (python-run SRC) -- run a Python program held in a string.
; (python-run SRC FILE) -- run it as the file FILE, as CPython runs a script:
; __file__ is FILE, and FILE's directory is the first place an import looks.
;
; Lex, parse, evaluate, in an environment of the program's own
; (%py-module-env below) that is the module __main__ of a table of the
; program's own, so two runs share no names and no modules.  Without a FILE
; an import looks in the working directory first, as `python -c` does.
; Returns nil: a Python statement has no value to show and `print` writes to
; stdout itself, so the REPL printer has nothing to say about a program that
; ran.  An expression typed at the prompt is a different question, and
; %python-repl-print below is where it gets answered.
(def python-run
  (fn (_ src . file)
    (def before (first %py-program))
    (%set-first! %py-program
      (%py-program-new (if (null? file) "" (%py-parent-dir (first file)))
        (pair () (%py-root (%py-here)))))
    (def env (%py-module-env))
    (%py-env-def! env (lit py-__name__) (%py-str-of-x "__main__"))
    (if (null? file) () (%py-env-def! env (lit py-__file__) (%py-str-of-x (first file))))
    (%py-dset (%py-modules-now) (%py-str-of-x "__main__") (%py-mod-new env))
    ; raise SystemExit ends the program QUIETLY; anything else uncaught
    ; travels on to whoever ran the program, the table the caller had put back
    ; first either way
    (guard (e (%seq (%set-first! %py-program before)
                (if (%py-exc-match e %py-exc-SystemExit) () (error e))))
      (%seq (%py-code-run env (python-parse src) ())
        (%seq (%set-first! %py-program before) ())))))

; FILE's directory: everything before its last slash, or the working
; directory, '', when it has none.
(def %py-parent-dir
  (fn (_ file)
    (let ((i (%py-last-slash file (- (Str8 length file) 1))))
      (if (null? i) "" (Str8 sub 0 i file)))))
(def %py-last-slash
  (fn (self s i)
    (match
      ((< i 0) ())
      ((= (%py-code-at s i) 47) i)
      (#t (self s (- i 1))))))

; --- eval, exec, compile -----------------------------------------------------
;
; The language re-entering itself.  All three are the two steps python-run
; already takes -- parse, then evaluate -- so they live HERE, where both halves
; are in scope; python/runtime.x cannot see the parser, and nothing else can
; see both.
;
; EVAL AND EXEC ARE EACH PROGRAM'S OWN.  Python runs the source in the
; namespace of the code that calls them, and a program's names are bindings
; in its own environment, so %py-module-env binds both there, each a closure
; over that environment: the eval a program's code finds evaluates in the
; program's names.  A globals or locals mapping says where it runs instead
; (%py-code-in below).

; A CODE OBJECT is what compile() answers and what eval and exec take beside a
; string: the forms, already parsed, and the mode they were parsed in
; (python/runtime-flow.x).

; `eval` mode is ONE EXPRESSION and nothing after it but the newlines that end
; its lines.  python-parse-expr answers (form . rest), and a rest holding
; anything else is CPython's SyntaxError -- `eval("1 2")` and `eval("x = 1")`
; answered 1 and x while the rest was dropped unread.
(def %py-eval-expr
  (fn (_ toks)
    (let ((r (python-parse-expr toks)))
      (if (%py-newlines-only? (rest r))
        (first r)
        (Err raise (lit syntax) "invalid syntax" ())))))
(def %py-newlines-only?
  (fn (self toks)
    (if (null? toks)
      #t
      (if (eq? (%py-label (first toks)) (lit tok-newline)) (self (rest toks)) #f))))

; Source to forms.
; THE SOURCE ARRIVES AS A str AND THE LEXER TAKES A PLATFORM STRING, so this
; is a crossing like any other: `str?` asks the platform whether it holds one
; of ITS strings, which a Python str is no longer, so the test is %py-str-is
; and the value has to come over before python-lex sees it.
(def %py-code-of
  (fn (_ src mode)
    (match
      ((%py-code-is src) (%py-code-forms src))
      ; a buffer is source too, read as the utf-8 it holds
      ((%py-buffer? src)
        (%py-code-of
          (%py-str-new (%ps-decode-as (%py-buffer-bytes src) "utf-8" "strict")) mode))
      ((not (%py-str-is src))
        (Err raise (lit type) "eval()/exec() wants a string or a code object" ()))
      (#t
        (let ((x (%ps->x (%py-str-cps src))))
          (match
            ((Str8 =? mode "eval") (list (%py-eval-expr (python-lex x))))
            ((Str8 =? mode "single") (python-parse-single x))
            (#t (python-parse x))))))))

; The forms evaluated in ENV, one at a time, answering the last one's value.
(def %py-code-run
  (fn (self env forms last)
    (if (null? forms)
      last
      (self env (rest forms) (eval (first forms) env)))))

; The source evaluated where exec(source, globals, locals) or eval says: in
; ENV when neither mapping is given, or each is None; in a module's own
; environment when the globals is its namespace dict; and otherwise in an
; environment of the source's own made from the dict's entries, whose names go
; back into the dict once the source has run.  A dict a program makes is not
; a namespace here, as it is in CPython, so its names are copied in and out.
; A locals mapping is an environment inside the globals', copied the same way.
(def %py-code-in
  (fn (_ who env src mode ns)
    (def g (%py-opt ns 0 ()))
    (def l (%py-opt ns 1 ()))
    (if (if (null? g) #f (not (%py-dict? g)))
      (Err raise (lit type) (Str8 append who "() globals must be a dict") ())
      ())
    (if (if (null? l) #f (not (%py-dict? l)))
      (Err raise (lit type) (Str8 append who "() locals must be a mapping") ())
      ())
    (def genv (if (null? g) env (%py-dict-env g (fn (_) (%py-module-env)))))
    (def lenv (if (null? l) genv (%py-dict-env l (fn (_) (pair () genv)))))
    (def v (%py-code-run lenv (%py-code-of src mode) ()))
    (%py-dict-back! g genv)
    (%py-dict-back! l lenv)
    v))

; The environment dict D stands for: a namespace dict's module's own, or a
; fresh one from MAKE with D's str-keyed entries bound in it.
(def %py-dict-env
  (fn (_ d make)
    (let ((ns (first (first d))))
      (if (null? ns)
        (let ((env (make)))
          (%seq (%py-ns-put-all! env (%py-str-keyed (%py-dict-entries d))) env))
        ns))))
(def %py-str-keyed
  (fn (self entries)
    (match
      ((null? entries) ())
      ((%py-str-is (first (first entries))) (pair (first entries) (self (rest entries))))
      (#t (self (rest entries))))))

; A dict a program made takes back the names its environment ended with.
(def %py-dict-back!
  (fn (self d env)
    (if (if (%py-dict? d) (null? (first (first d))) #f)
      (%py-dict-back-rows! d (%py-ns-entries env))
      ())))
(def %py-dict-back-rows!
  (fn (self d rows)
    (if (null? rows)
      ()
      (%seq (%py-dset d (first (first rows)) (rest (first rows)))
        (self d (rest rows))))))

(def %py-eval-for
  (fn (_ env)
    (%py-sig!
      (fn (_ src . ns) (%py-code-in "eval" env src "eval" ns))
      "eval" (list "source" "globals" "locals") 1 #f)))

; exec ANSWERS None however much the source evaluated to, which is why the
; value is dropped here rather than never taken.
(def %py-exec-for
  (fn (_ env)
    (%py-sig!
      (fn (_ src . ns) (%seq (%py-code-in "exec" env src "exec" ns) ()))
      "exec" (list "source" "globals" "locals") 1 #f)))

; globals() is the program's namespace dict, the same one every time.
(def %py-globals-for
  (fn (_ env)
    (%py-sig! (fn (_) (%py-env-ns env)) "globals" () 0 #f)))

; A module's environment -- the program's own, or a file's it imports --
; descended from the program's builtins (%py-program) and through them the
; root.  Between the module and the builtins is a scope of the module's own
; holding the builtins that act on its names -- eval, exec and globals -- each
; a closure over its environment, and its namespace dict: the eval a module's
; code finds evaluates in the module's names, and what the module itself binds
; is its globals and nothing else.
(def %py-module-env
  (fn (_)
    (def scope (pair () (%py-builtins-now)))
    (def env (pair () scope))
    (%py-env-def! scope (lit %py-eval) (%py-eval-for env))
    (%py-env-def! scope (lit %py-exec) (%py-exec-for env))
    (%py-env-def! scope (lit %py-globals) (%py-globals-for env))
    (%py-env-def! scope (lit %py-ns) (%py-ns-new env))
    env))

; The root's own, for the prompt, whose lines are evaluated there
; (python/repl.x).  The prompt's names are x's root, which nothing here can
; list, so globals() says so, as dir() with no argument does.
(def %py-eval (%py-eval-for (%py-root (%py-here))))
(def %py-exec (%py-exec-for (%py-root (%py-here))))
(def %py-globals
  (%py-sig!
    (fn (_)
      (Err raise (lit type)
        "globals() at the prompt needs a namespace this runtime does not list" ()))
    "globals" () 0 #f))

; `single` is `exec` whose expression statements print their values, as a
; prompt's do (python/parse.x, python-parse-single).  A mode that is none of
; the three is a ValueError, as it is in Python.
(def %py-compile
  (%py-sig!
    (fn (_ src file mode0)
      ; THE MODE ARRIVES AS A str AND IS COMPARED WITH Str8, so it crosses over
      ; first -- `compile(src, "<s>", "eval")` died with "Str8 =?: not a string"
      ; before it could read its own argument.  %py-code-of takes the crossed
      ; one too: it asks the same question of it.
      (def mode (if (%py-str-is mode0) (%ps->x (%py-str-cps mode0)) mode0))
      (if (if (Str8 =? mode "exec") #t (if (Str8 =? mode "eval") #t (Str8 =? mode "single")))
        (%py-code-new mode (%py-code-of src mode)
          (if (%py-str-is file) (%py-text->x file) "<string>") "<module>" ())
        (Err raise (lit value)
          "compile() mode must be 'exec', 'eval' or 'single'" ())))
    "compile" (list "source" "filename" "mode") 3 #f))

; function(code, globals): the function CODE is of, made again with GLOBALS
; for its globals.  The fn CODE holds is evaluated in the environment the
; dict stands for -- a module's own for its namespace dict, and for a dict a
; program made one with the dict's names bound in it, as exec does
; (%py-dict-env).  The function has the code's signature and no defaults,
; which are the function's and not its code's.  Code compile() answered makes
; a function of no arguments that runs it there, answering what an `eval`
; mode's expression does and None for the other modes.
(def %py-function-over
  (fn (_ code globals)
    (match
      ((not (%py-code-is code))
        (Err raise (lit type) "function() argument 'code' must be code" ()))
      ((not (%py-dict? globals))
        (Err raise (lit type) "function() argument 'globals' must be dict" ()))
      (#t
        (eval (%py-function-form code)
          (%py-dict-env globals (fn (_) (%py-module-env))))))))
(def %py-function-form
  (fn (_ code)
    (if (Str8 =? (%py-code-mode code) "function")
      (let ((r (%py-code-record code)) (f (first (%py-code-forms code))))
        (list (lit %py-sig!) f (first r)
          (list (lit lit) (List ref 1 r))
          (List ref 2 r) (List ref 3 r)
          (list (lit lit) (List ref 4 r))
          (list (lit lit) (List ref 5 r))
          #t
          (list (lit %py-here))
          (list (lit lit) (pair f r))))
      (list (lit %py-sig!)
        (list (lit fn) (pair (lit %py-fn) (lit %py-more))
          (list (lit %py-code-answer) (list (lit lit) code) (list (lit %py-here))))
        (%py-code-name code) () 0 #f () () #t (list (lit %py-here))))))
(def %py-code-answer
  (fn (_ code env)
    (let ((v (%py-code-run env (%py-code-forms code) ())))
      (if (Str8 =? (%py-code-mode code) "eval") v ()))))

(def %python-repl-print
  (fn (_ result)
    (unless (null? result) (%seq (write result) (newline)))))
