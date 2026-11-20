# The prompt through the line editor: paint, marks, completion, the switch
# @weight 2

With a terminal, the platform's line editor reads the line and asks the
session's lang what it means, how it is coloured and what Tab offers.
`python/line.x` answers the last three for Python and `python/repl.x` the
first; `python-repl-install!` registers the four as the lang `"python"` in the
platform's registry, `x/repl/lang`. Without a terminal the session keeps the
byte loop. The cases below check the bundle's own answers, and one touches the
registry.

## painting

### a name is classified lexically: keyword, bool, builtin, class, name

```python
(%seq
  (do
    (import python/line %py-paint-label)
    (write (List map (fn (_ n) (%py-paint-label n)) (list "def" "True" "print" "Foo" "x"))))
  (newline))
```
---
    ('keyword 'bool 'builtin 'class 'name)

### the lexer cuts a line into classed tokens, a bracket or an operator one byte

```python
(%seq
  (do
    (import python/line %py-paint-tokens)
    (write (%py-paint-tokens "if x: print(\"hi\") # c")))
  (newline))
```
---
    (('keyword . "if") ('blank . " ") ('name . "x") ('plain . ":") ('blank . " ") ('builtin . "print") ('plain . "(") ('string . "\"hi\"") ('plain . ")") ('blank . " ") ('comment . "# c"))

### string prefixes and triple quotes are one string; numbers keep their layout

```python
(%seq
  (do
    (import python/line %py-paint-tokens)
    (write (%py-paint-tokens "f\"a{b}\" + rb\"\"\"x\"\"\" + 1_000 + 0x1f + 1.5e-3 + .5")))
  (newline))
```
---
    (('string . "f\"a{b}\"") ('blank . " ") ('plain . "+") ('blank . " ") ('string . "rb\"\"\"x\"\"\"") ('blank . " ") ('plain . "+") ('blank . " ") ('number . "1_000") ('blank . " ") ('plain . "+") ('blank . " ") ('number . "0x1f") ('blank . " ") ('plain . "+") ('blank . " ") ('number . "1.5e-3") ('blank . " ") ('plain . "+") ('blank . " ") ('number . ".5"))

### a decorator is one token, and an unterminated string runs to the end

```python
(%seq
  (do
    (import python/line %py-paint-tokens)
    (write (list (%py-paint-tokens "@property") (%py-paint-tokens "s = 'abc"))))
  (newline))
```
---
    ((('decorator . "@property")) (('name . "s") ('blank . " ") ('plain . "=") ('blank . " ") ('string . "'abc")))

### with colour off the painter answers its argument

```python
(%seq
  (do
    (import python/line python-paint)
    (write (if (Ansi enabled?) #t (Str8 =? (python-paint "def f(): pass") "def f(): pass"))))
  (newline))
```
---
    #t

## bracket marks

### every bracket gets its depth, and the pair beside the cursor is focused

```python
(%seq
  (do
    (import python/line python-marks)
    (write (python-marks "f([1, {2}])" 1)))
  (newline))
```
---
    ((1 0 #t) (2 1 #f) (6 2 #f) (8 2 #f) (9 1 #f) (10 0 #t))

### a close with nothing to close is -1

```python
(%seq
  (do
    (import python/line python-marks)
    (write (python-marks "f(x))" 5)))
  (newline))
```
---
    ((1 0 #f) (3 0 #f) (4 -1 #t))

### brackets inside strings and comments are not brackets

```python
(%seq
  (do
    (import python/line python-marks)
    (write (python-marks "f(\")\") # )" 0)))
  (newline))
```
---
    ((1 0 #f) (5 0 #f))

## completion

The completer reads the buffer through one method, `before`, the text to the
left of the cursor, so a stand-in with that method serves here as it does in
`09-line.spec.md`, and the case runs on a platform without the editor.

### Tab offers keywords and builtins by prefix, and nothing for an empty word

```python
(%seq
  (do
    (import python/line python-complete)
    (def-class %spec-edit () text
      (method before (self) (field (lit text))))
    (write (list (python-complete (new %spec-edit text "x = pri"))
                 (python-complete (new %spec-edit text "x = ")))))
  (newline))
```
---
    (("pri" "print") (""))

## the entry and the line

### a block is read to the blank line through whatever reads the next line

```python
(%seq
  (do
    (let ((q (list "    return 1" "" "unreached")))
      (write (%py-read-entry "def f():"
               (fn (_) (let ((l (first q))) (set! q (rest q)) l))))))
  (newline))
```
---
    "def f():\n    return 1"

### 'cancel from the reader abandons the entry; 'eof closes it

```python
(%seq
  (do
    (write (list (%py-read-entry "def f():" (fn (_) (lit cancel)))
                 (%py-read-entry "def f():" (fn (_) (lit eof))))))
  (newline))
```
---
    ('cancel "def f():")

### a finished line evaluates and echoes as the loop would

```python
(do
  (%py-eval-line "3 * 7")
  (%py-eval-line "z = 2")
  (%py-eval-line "z + 1")
  (%py-eval-line ""))
```
---
```output
21
3
```

### an error on the line is reported, not raised

```python
(do
  (%py-eval-line "1 +")
  (display "still here") (newline))
```
---
```output
  File "<stdin>", line 1
    1 +
    ^^^
Error: syntax: unexpected end of input in expression
still here
```

## where an entry failed

An error is reported against the entry that raised it: the line the entry
began on, its text, and a caret under each character of it. The entry is the
whole of what is known, so a block is shown by its header and carries no
carets.

### an error raised while the line runs is marked the same way

```python
(do
  (%py-eval-line "q91 = [1, 2][7]")
  (display "still here") (newline))
```
---
```output
  File "<stdin>", line 1
    q91 = [1, 2][7]
    ^^^^^^^^^^^^^^^
Error: index: list index out of range
still here
```

### indentation and trailing blanks are not marked, and a character is one caret

```python
(%py-entry-run "é91 = 1 +  " (fn (_) (lit eof)))
```
---
```output
  File "<stdin>", line 1
    é91 = 1 +
    ^^^^^^^^^
Error: syntax: unexpected end of input in expression
```

### a block is shown by its header, with no carets

```python
(do
  (def %more91 (pair (list "    1 +" "") ()))
  (%py-entry-run "for i91 in [1]:"
    (fn (_)
      (let ((l (first (first %more91))))
        (do (%set-first! %more91 (rest (first %more91))) l)))))
```
---
```output
  File "<stdin>", line 1
    for i91 in [1]:
Error: syntax: unexpected end of input in expression
```

### a program on standard input is reported by its own line

The byte loop counts the lines it reads, and an entry begins on the line it
read last.

```python
(do
  (%set-first! %py-lines-read 6)
  (%py-entry-run "1 +" (fn (_) (lit eof)))
  (%set-first! %py-lines-read 0)
  ())
```
---
```output
  File "<stdin>", line 6
    1 +
    ^^^
Error: syntax: unexpected end of input in expression
```

## the registry

### install registers "python" in the platform's registry

```python
(%seq
  (do
    (python-repl-install!)
    (write (let ((r (list (Lang current) (Assoc get '%repl-prompt (Lang get "python"))
                          (same? (Assoc get '%repl-eval-line (Lang get "python")) %py-eval-line))))
             (Lang use! "x")
             (set! %repl-print python-repl-print)
             r)))
  (newline))
```
---
    ("python" ">>> " #t)
