# The prompt through the line editor: paint, marks, completion, the switch
# @weight 2

With a terminal, the platform's line editor reads the line and asks the
session's lang what it means, how it is coloured and what Tab offers.
`python/line.x` answers the last three for Python and `python/repl.x` the
first; `%py-repl-install!` registers the four as the lang `"python"` in the
platform's registry, `x/repl/lang`. Without a terminal the session keeps the
byte loop. The cases below check the bundle's own answers, and one touches the
registry.

## painting

### a name is classified lexically: keyword, bool, builtin, class, name

```python
(%seq
  (do
    (import python/line)
    (write (List map (fn (_ n) (%py-paint-class n)) (list "def" "True" "print" "Foo" "x"))))
  (newline))
```
---
    ('keyword 'bool 'builtin 'class 'name)

### the scan cuts a line into classed spans, brackets on their own

```python
(%seq
  (do
    (import python/line)
    (write (%py-paint-tokens "if x: print(\"hi\") # c")))
  (newline))
```
---
    (('keyword . "if") ('plain . " ") ('name . "x") ('plain . ": ") ('builtin . "print") ('bracket . "(") ('string . "\"hi\"") ('bracket . ")") ('plain . " ") ('comment . "# c"))

### string prefixes and triple quotes are one string; numbers keep their shape

```python
(%seq
  (do
    (import python/line)
    (write (%py-paint-tokens "f\"a{b}\" + rb\"\"\"x\"\"\" + 1_000 + 0x1f + 1.5e-3 + .5")))
  (newline))
```
---
    (('string . "f\"a{b}\"") ('plain . " + ") ('string . "rb\"\"\"x\"\"\"") ('plain . " + ") ('number . "1_000") ('plain . " + ") ('number . "0x1f") ('plain . " + ") ('number . "1.5e-3") ('plain . " + ") ('number . ".5"))

### a decorator is one span, and an unterminated string runs to the end

```python
(%seq
  (do
    (import python/line)
    (write (list (%py-paint-tokens "@property") (%py-paint-tokens "s = 'abc"))))
  (newline))
```
---
    ((('decorator . "@property")) (('name . "s") ('plain . " = ") ('string . "'abc")))

### with colour off the painter answers its argument

```python
(%seq
  (do
    (import python/line)
    (write (if (Ansi enabled?) #t (Str8 =? (%py-paint "def f(): pass") "def f(): pass"))))
  (newline))
```
---
    #t

## bracket marks

### every bracket gets its depth, and the pair beside the cursor is focused

```python
(%seq
  (do
    (import python/line)
    (write (%py-marks "f([1, {2}])" 1)))
  (newline))
```
---
    ((1 0 #t) (2 1 #f) (6 2 #f) (8 2 #f) (9 1 #f) (10 0 #t))

### a close with nothing to close is -1

```python
(%seq
  (do
    (import python/line)
    (write (%py-marks "f(x))" 5)))
  (newline))
```
---
    ((1 0 #f) (3 0 #f) (4 -1 #t))

### brackets inside strings and comments are not brackets

```python
(%seq
  (do
    (import python/line)
    (write (%py-marks "f(\")\") # )" 0)))
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
    (import python/line)
    (def-class %spec-edit () text (method before (self) (member (lit text))))
    (write (list (%py-complete (new %spec-edit text "x = pri"))
                 (%py-complete (new %spec-edit text "x = ")))))
  (newline))
```
---
    (("pri" "print") (""))

## the entry and the line

### a block is read to the blank line through whatever reads the next line

```python
(%seq
  (do
    (import python/repl)
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
    (import python/repl)
    (write (list (%py-read-entry "def f():" (fn (_) (lit cancel)))
                 (%py-read-entry "def f():" (fn (_) (lit eof))))))
  (newline))
```
---
    ('cancel "def f():")

### a finished line evaluates and echoes as the loop would

```python
(do
  (import python/repl)
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
  (import python/repl)
  (%py-eval-line "1 +")
  (display "still here") (newline))
```
---
```output
Error: #<err:syntax unexpected end of input in expression>
still here
```

## the registry

### install registers "python" in the platform's registry

```python
(%seq
  (do
    (import python/repl)
    (%py-repl-install!)
    (write (let ((r (list (Lang current) (Assoc get '%repl-prompt (Lang get "python"))
                          (same? (Assoc get '%repl-eval-line (Lang get "python")) %py-eval-line))))
             (Lang use! "x")
             (set! %repl-print %python-repl-print)
             r)))
  (newline))
```
---
    ("python" ">>> " #t)
