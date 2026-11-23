; # x-python -- the Python lang for x-lang
;
; ## python/modules -- the table of modules this runtime builds itself
;
; @description The built-in modules, as a class: each is a static method of
;   PyModule, named for the module, that builds it.  A module's own file
;   registers it, so adding one touches no shared table.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A NAME CHOSEN AT RUN TIME IS A CLASS (x-lang docs/lang-contract.md,
; "Modules, names and classes").  `import json` names a module the program
; chose, so the built-in modules are the static methods of one class, and a
; file that builds one fills its row in with
;
;   (PyModule def-static! (lit NAME) (fn (_ cls) (python-NAME-module)))
;
; at its top level -- no edit to a match in another file.  The builder runs on
; the module's first import; the importer remembers what it answers in
; sys.modules, so it runs once per program.
;
; The lookup is class-static-ref, not a call: it reads only the rows filled in
; here, never the class's own builtins, so a module named `new` would be a row
; like any other, and a name with no row answers nil rather than raising.
;
; THE PURE-PYTHON MODULES ARE NOT HERE.  They are .py files under stdlib/,
; beside lib/, which the importer searches after sys.path
; (python/runtime-flow.x, %py-stdlib-dirs).  A module goes here only when it
; needs what Python cannot reach: the platform, or the runtime's own values.
(module python/modules)
(import x/type/class)
(import x/core/doors str->sym)

(def-class PyModule ()
  (doc "The modules this runtime builds itself: (PyModule NAME) builds the module NAME, and a module's file adds its row with (PyModule def-static! (lit NAME) (fn (_ cls) ...))."
    (sample "(PyModule sys)" "<module 'sys' (built-in)>")))

(def python-module-builder
  (fn (_ name) (class-static-ref PyModule (str->sym name))))

(provide python/modules PyModule python-module-builder)
