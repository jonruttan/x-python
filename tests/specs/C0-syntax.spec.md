## python/syntax -- the Python highlighting grammar

The bundle's lang.xon declares a grammar, `python`, that x/tool/syntax
colours Python files with. Its module, `python/syntax`, imports x-lang
libraries and python/lexer only, and registers the grammar as it loads.

The cases share one process, and a registered grammar stays registered, so
the catalogue's case comes first: it finds the grammar through lang.xon,
before anything has imported the module.

### the catalogue finds python by suffix, by #! and by modeline

The langs directory holds this bundle, linked as `python`. The row comes from
lang.xon, its module not loaded until a file asks for the grammar, and the
grammar takes lang.xon's suffixes and interpreters.

```python
(do (import x/sys/posix) (import x/sys/file) (import x/tool/syntax)
    (def root (Str8 replace "/python/syntax.x" "" (%module-resolve-file "python/syntax.x")))
    (def tmp (File temp "/tmp/x-python-spec-langs-"))
    (File close (first tmp))
    (def d (rest tmp))
    (File unlink d)
    (File mkdir d)
    (File symlink root (Str8 append d "/python"))
    (def was (Sys getenv "X_LANG_DIR"))
    (Sys setenv "X_LANG_DIR" d)
    (Syntax forget!)
    (def row (List find (fn (_ r) (eq? (first r) (lit python))) (Syntax catalogue)))
    (def name (fn (_ path . text)
      (let ((g (apply Syntax (pair (lit for-file) (pair path text))))) (if (null? g) () (g name)))))
    (def seen
      (list (List ref 1 row)
            (name "x.py") (name "stubs/x.pyi")
            (name "run" "#!/usr/bin/env python3\nprint(1)\n")
            (name "run" "x = 1\n# vi: set ft=python:\n")
            (name "x.txt")
            (let ((g (Syntax named (lit python)))) (list (g files) (g interpreters)))))
    (File unlink (Str8 append d "/python"))
    (File rmdir d)
    (Sys setenv "X_LANG_DIR" (if (null? was) "" was))
    (Syntax forget!)
    seen)
```
---
    ('python/syntax 'python 'python 'python 'python () ((".py" ".pyw" ".pyi") ("python" "python3")))

### a file's spans: comments, decorators, strings, numbers and names

A keyword, True, False and None, a builtin and a capitalised name each have a
class; any other name has none.  Brackets, commas, colons and dots are
punctuation, the other plain bytes operators.

```python
(do (import x/tool/syntax) (import python/syntax)
    ((Syntax named (lit python)) spans
      "# c\n@dec\ndef f(x=1.5e-3):\n    return len(x), None, Foo, r'a\\'b' + y\n"))
```
---
    ((0 3 'comment) (4 4 'keyword) (9 3 'keyword) (14 1 'punct) (16 1 'operator) (17 6 'number) (23 1 'punct) (24 1 'punct) (30 6 'keyword) (37 3 'name) (40 1 'punct) (42 1 'punct) (43 1 'punct) (45 4 'constant) (49 1 'punct) (51 3 'class) (54 1 'punct) (56 7 'string) (64 1 'operator))

### strings with prefixes, triple quotes, and one left open

```python
(do (import x/tool/syntax) (import python/syntax)
    (List map (fn (_ s) ((Syntax named (lit python)) spans s))
      (list "b'\\x00' f\"{a}\" rb'''x'''" "s = \"\"\"doc\nmore" "t = 'open")))
```
---
    (((0 7 'string) (8 6 'string) (15 9 'string)) ((2 1 'operator) (4 11 'string)) ((2 1 'operator) (4 5 'string)))

### the grammar's words are the interpreter's keywords and builtins

```python
(do (import python/syntax python-syntax-keywords python-syntax-constants python-syntax-builtins)
    (import python/tokens python-keywords)
    (import python/core python-builtins)
    (def table (List map first python-builtins))
    (def ours (List append python-syntax-constants python-syntax-builtins))
    (list (equal? python-syntax-keywords python-keywords)
          (List filter (fn (_ n) (not (List includes? n ours))) table)
          (List filter (fn (_ n) (not (List includes? n table))) ours)))
```
---
    (#t () ())

### a window reads from the line above it at the first column

Spans walk back from a window's first line to one starting with a name, a
comment or a decorator, so a triple-quoted string opened on an indented line
above colours the window's start.

```python
(do (import x/tool/syntax) (import python/syntax)
    ((Syntax named (lit python)) spans "def f():\n    s = '''a\n    b''' + 1\n" 23 9))
```
---
    ((23 7 'string) (31 1 'operator))
