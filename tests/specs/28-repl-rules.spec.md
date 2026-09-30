The REPL's own rules — the pure halves, since the loop itself reads a terminal.

The platform REPL reads sexps and no prompt string changes what a reader is; a
Python banner over an x reader answered `Unbound SYMBOL 'print` and evaluated
`1 + 2` as three forms across three prompts. `python/repl.x` replaces the loop.
What can be pinned here: which parsed forms echo, how definitions survive from
line to line, and when a line opens a block.

## what echoes

CPython echoes an expression statement's repr and nothing else. The emitted
form's structure says which is which — with one refinement: `let` heads both
tuple-unpacking STATEMENTS (binding `%py-unpacked`) and EXPRESSIONS
(comprehensions bind `%py-acc`, and/or bind `%py-lhs`), and the expression variant
must echo.

### statements are silent

```python
(%seq
  (do
    (import python/repl)
    (write (list
      (%py-stmt-form? (lit (set! py-x 5)))
      (%py-stmt-form? (lit (def py-f ())))
      (%py-stmt-form? (lit (%py-hoist py-f ())))
      (%py-stmt-form? (lit (let ((%py-unpacked (%py-unpack v 2))) (do))))
      (%py-stmt-form? (lit (if (%py-truthy c) a b))))))
  (newline))
```
---
    (#t #t #t #t #t)

### expressions echo

```python
(%seq
  (do
    (import python/repl)
    (write (list
      (%py-stmt-form? (lit (%py-add 1 2)))
      (%py-stmt-form? (lit py-x))
      (%py-stmt-form? (lit (let ((%py-acc (pair () ()))) (%seq a b))))
      (%py-stmt-form? (lit (let ((%py-lhs 1)) (if (%py-truthy %py-lhs) 2 %py-lhs))))
      (%py-stmt-form? "bare"))))
  (newline))
```
---
    (#f #f #f #f #f)

## definitions survive the loop

A line's forms are evaluated in the root, so a top-level `(def SYM V)` binds
there: `def f(): ...` on one line is `f` on the next, and at x's prompt too.

### a def on one line is called on the next

```python
(do
  (import python/repl)
  (%py-repl-eval "def f(n):\n    return n + 1")
  (%py-repl-eval "f(41)"))
```
---
    42

### and x's prompt calls it by its prefixed name

```python
(%seq
  (do
    (import python/repl)
    (%py-repl-eval "def sq(n):\n    return n * n")
    (write (py-sq 12)))
  (newline))
```
---
    144

## blocks

### a line ending with a colon opens one

```python
(%seq
  (do
    (import python/repl)
    (write (list
      (%py-opens-block? "def f():")
      (%py-opens-block? "if x:")
      (%py-opens-block? "x = 5")
      (%py-opens-block? ""))))
  (newline))
```
---
    (#t #t #f #f)

## the session-hoist contract

Each interactive line is its own parse, so hoists and shims must not clobber
earlier lines' bindings. The emissions are conditional: `%py-hoist` binds a
name only where the environment does not have it already.

### a second parse does not reset a bound name

```python
(%seq
  (do
    (import python/repl)
    (%py-repl-eval "x = 5")
    (%py-repl-eval "x = x + 1")
    (%py-repl-eval "print(x)"))
  ())
```
---
    6
