The REPL's own rules — the pure halves, since the loop itself reads a terminal.

The platform REPL reads sexps and no prompt string changes what a reader is; a
Python banner over an x reader answered `Unbound SYMBOL 'print` and evaluated
`1 + 2` as three forms across three prompts. `python/repl.x` replaces the loop.
What can be pinned here: which parsed forms echo, how definitions survive the
loop's depth, and when a line opens a block.

## what echoes

CPython echoes an expression statement's repr and nothing else. The emitted
form's shape says which is which — with one refinement: `let` heads both
tuple-unpacking STATEMENTS (binding `%py-unpacked`) and EXPRESSIONS
(comprehensions bind `%py-acc`, and/or bind `%py-lhs`), and the expression kind
must echo.

### statements are silent

```python
(%seq
  (do
    (import python/repl)
    (write (list
      (%py-stmt-form? (lit (set! py-x 5)))
      (%py-stmt-form? (lit (def py-f ())))
      (%py-stmt-form? (lit (%py-defg (lit py-f) ())))
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

A top-level `(def SYM V)` in a parsed line binds at the loop's frame depth and
vanishes — `def f(): ...` then `f(41)` answered NameError. The lift rewrites it
through base/def-global, the engine door that defines for the caller at any
depth.

### the lift rewrites def and only def

```python
(%seq
  (do
    (import python/repl)
    (write (%py-repl-lift
      (lit ((def py-f (fn (_) 1)) (set! py-x 5) (%py-add 1 2))))))
  (newline))
```
---
    (('%py-defg ('lit 'py-f) ('fn ('_) 1)) ('set! 'py-x 5) ('%py-add 1 2))

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
earlier lines' bindings. The emissions are conditional — the guard evaluates
the name, a bound name answers itself, an unbound one raises into a handler
that defines through def-global. Pinned in batch, where two parses of one
process model two REPL lines:

### a second parse does not reset a bound name

```python
(%seq
  (do
    (python-run "x = 5")
    (python-run "x = x + 1")
    (python-run "print(x)"))
  ())
```
---
    6
