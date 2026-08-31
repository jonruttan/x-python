Python's exception types are x's error KINDS.

`Err` already carries a kind symbol, a message and a data alist, and every raise
in this runtime already picked a kind — `(lit index)` for a bad subscript,
`(lit key)` for a missing dict key, `(lit type)` for a bad operand. Those kinds
were chosen long before there was any way to catch them, and they turn out to be
exactly the discrimination `except` needs. So every error this runtime had ever
raised became catchable the moment `try` could parse.

The builtin exceptions are now real classes in Python's own shape, and matching
walks the base chain — see 19-exception-classes. A kind names the class it would
have been, and from there a raise from Python source and a raise from this
runtime are matched identically.

`try` compiles to x's `guard`, and a clause that matches nothing re-raises with
`(error e)` — an exception no clause names has to keep travelling.

## raise

### raise and catch

```python
(python-run "try:\n    raise ValueError('bad thing')\nexcept ValueError as e:\n    print(e)")
```
---
    bad thing

### raise without a message

```python
(python-run "try:\n    raise ValueError\nexcept ValueError:\n    print('bare')")
```
---
    bare

### an unknown exception name is a NameError

`raise Foo` where `Foo` was never defined does not raise `Foo` in Python either.

```python
(python-run "try:\n    raise Frobnicate('x')\nexcept NameError as e:\n    print(e)")
```
---
    name 'Frobnicate' is not defined

### a bare raise re-raises what was caught

```python
(python-run "try:\n    try:\n        raise ValueError('v')\n    except ValueError:\n        raise\nexcept ValueError:\n    print('outer')")
```
---
    outer

## except

### as binds the exception, and str(e) is the message

Not the repr: `print(e)` shows `division by zero`, not
`#<err:zero-division division by zero>`.

```python
(python-run "try:\n    print(1 / 0)\nexcept ZeroDivisionError as e:\n    print(e)")
```
---
    division by zero

### the first matching clause wins

```python
(python-run "try:\n    raise KeyError('k')\nexcept ValueError:\n    print('no')\nexcept KeyError:\n    print('yes')")
```
---
    yes

### Exception catches anything

There is no class hierarchy here to derive that from, so it is stated rather
than computed. When classes arrive, this is the entry that grows a parent link.

```python
(python-run "try:\n    raise IndexError('i')\nexcept Exception:\n    print('base')")
```
---
    base

### a bare except catches anything too

```python
(python-run "try:\n    raise TypeError('t')\nexcept:\n    print('any')")
```
---
    any

### an unmatched clause lets it through

```python
(python-run "try:\n    raise KeyError('k')\nexcept ValueError:\n    print('wrong')")
```
---
    Error: KeyError: k

### a try that does not raise runs no handler

```python
(python-run "try:\n    print('fine')\nexcept ValueError:\n    print('no')")
```
---
    fine

## the errors the runtime already raised

### a bad subscript

```python
(python-run "try:\n    print([1][5])\nexcept IndexError as e:\n    print(e)")
```
---
    list index out of range

### a missing key

```python
(python-run "try:\n    print({}['a'])\nexcept KeyError:\n    print('kerr')")
```
---
    kerr

### a bad operand

```python
(python-run "try:\n    print(1 + 'a')\nexcept TypeError:\n    print('terr')")
```
---
    terr

## division by zero

Three more silent wrong answers: `1 / 0` answered `inf`, `1 // 0` answered `0`,
and `1 % 0` answered None. Python spells all three ZeroDivisionError, with two
different messages.

### true division

```python
(python-run "try:\n    print(1 / 0)\nexcept ZeroDivisionError as e:\n    print(e)")
```
---
    division by zero

### floor division

```python
(python-run "try:\n    print(1 // 0)\nexcept ZeroDivisionError as e:\n    print(e)")
```
---
    integer division or modulo by zero

### modulo

```python
(python-run "try:\n    print(1 % 0)\nexcept ZeroDivisionError as e:\n    print(e)")
```
---
    integer modulo by zero

## finally

### it runs when the body succeeds

```python
(python-run "try:\n    print('body')\nfinally:\n    print('cleanup')")
```
---
```output
body
cleanup
```

### and after a handler

```python
(python-run "try:\n    raise ValueError('v')\nexcept ValueError:\n    print('handled')\nfinally:\n    print('cleanup')")
```
---
```output
handled
cleanup
```

### it runs before an exception it does not handle

```python
(python-run "try:\n    raise ValueError('v')\nfinally:\n    print('cleanup')")
```
---
```output
cleanup
Error: ValueError: v
```

### a return inside try skips it

PENDING, and a real divergence rather than an oversight. `return` invokes an
escape continuation (see 13-return), and that continuation jumps straight past
the `finally` — Python runs it on the way out and prints `cleanup` before `1`.
Fixing it means the escape has to unwind through the guard, which is a change to
how `return` works, not to how `finally` works.

```python
(python-run "def f():\n    try:\n        return 1\n    finally:\n        print('cleanup')\nprint(f())")
```
