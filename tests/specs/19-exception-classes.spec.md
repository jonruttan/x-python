Exceptions are classes, and the hierarchy is the point.

The first version of this mapped exception NAMES to error KINDS with a string
table, and `Exception` matched everything by a special case written into the
matcher. That worked and could not grow: `except LookupError` catching both
IndexError and KeyError is not a special case — it is what deriving from a
common base MEANS, and a flat table has no way to say it.

So the builtins are real class values in Python's own shape, `Exception` is no
longer special, and a user-defined exception is caught by exactly the same code.

Two kinds of raised value arrive at a handler. A `raise` in Python source makes
an instance; everything this runtime raises itself makes an `Err` carrying a
kind, because those raises predate classes by a long way. A kind names the class
it would have been, and from there both match identically.

## the builtin hierarchy

### a base class catches its derived ones

```python
(python-run "try:\n    print([1][5])\nexcept LookupError:\n    print('lookup')")
```
---
    lookup

### and the other one that derives from it

```python
(python-run "try:\n    print({}['a'])\nexcept LookupError:\n    print('lookup')")
```
---
    lookup

### ZeroDivisionError derives from ArithmeticError

```python
(python-run "try:\n    print(1 / 0)\nexcept ArithmeticError as e:\n    print(e)")
```
---
    division by zero

### a sibling does not catch

IndexError and KeyError share a base; neither derives from the other.

The uncaught line here is the `Err` form rather than `KeyError: a`, and that is
a real inconsistency rather than an accident of this case: a raise from Python
source makes an instance and prints `Name: message`, while a raise from this
runtime stays an `Err` and prints the platform's `#<err:kind msg>`. Both are
CAUGHT identically — that is what the kind table is for — but they still print
differently when nothing catches them. Python shows one form for both.

```python
(python-run "try:\n    print({}['a'])\nexcept IndexError:\n    print('wrong')")
```
---
    Error: #<err:key key not found>

### Exception is no longer a special case, just the root

```python
(python-run "try:\n    print(1 / 0)\nexcept Exception:\n    print('caught')")
```
---
    caught

### an exception class is a value like any other

The qualname is the bare name: CPython prints `<class 'ValueError'>` — the
builtins live in no module the program wrote. This case asserted
`<class '__main__.ValueError'>` when it was written, a recorded divergence the
qualname slot in 23-types fixed.

```python
(python-run "print(ValueError)")
```
---
    <class 'ValueError'>

## user-defined exceptions

### deriving from Exception, raised and caught by name

```python
(python-run "class MyError(Exception):\n    pass\ntry:\n    raise MyError('mine')\nexcept MyError as e:\n    print(e)")
```
---
    mine

### and caught by its base

This is the thing the string table could not do.

```python
(python-run "class MyError(Exception):\n    pass\ntry:\n    raise MyError('mine')\nexcept Exception:\n    print('by base')")
```
---
    by base

### a user exception does not catch an unrelated one

```python
(python-run "class MyError(Exception):\n    pass\ntry:\n    raise ValueError('v')\nexcept MyError:\n    print('wrong')")
```
---
    Error: ValueError: v

### two levels of user class

```python
(python-run "class AppError(Exception):\n    pass\nclass DbError(AppError):\n    pass\ntry:\n    raise DbError('db')\nexcept AppError as e:\n    print(e)")
```
---
    db

### a user exception derives from a builtin

```python
(python-run "class BadInput(ValueError):\n    pass\ntry:\n    raise BadInput('nope')\nexcept ValueError as e:\n    print(e)")
```
---
    nope

### uncaught, it prints Name: message

Python's traceback ends in exactly this line. Without it an uncaught instance
printed `<__main__.MyError object>` — the right form for an ordinary object and
useless for the one case a human is reading it, because the program just died.

```python
(python-run "class MyError(Exception):\n    pass\nraise MyError('boom')")
```
---
    Error: MyError: boom

## raise is a call

### which is why an undefined name is a NameError

`raise X(...)` evaluates `X(...)` and raises the result, exactly as Python does.
An undefined name is bound to a shim that raises when called, so this needs no
special case anywhere.

```python
(python-run "raise Frobnicate('x')")
```
---
    Error: #<err:name name 'Frobnicate' is not defined>

### raising a non-exception is a TypeError

```python
(python-run "class NotAnError:\n    pass\nraise NotAnError()")
```
---
    Error: #<err:type exceptions must derive from BaseException>
