Python's exception types are x's error TAGS.

`Err` already carries a tag symbol, a message and a data alist, and every raise
in this runtime already picked a tag — `(lit index)` for a bad subscript,
`(lit key)` for a missing dict key, `(lit type)` for a bad operand. Those tags
were chosen long before there was any way to catch them, and they turn out to be
exactly the discrimination `except` needs. So every error this runtime had ever
raised became catchable the moment `try` could parse.

The builtin exceptions are now real classes in Python's own shape, and matching
walks the base chain — see 19-exception-classes. A tag names the class it would
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

### raise takes an expression: a class, an instance, or a refusal

```python
(python-run "def t(label, f):\n    try:\n        f()\n        print(label, \"no error\")\n    except TypeError as e:\n        print(label, \"TypeError\", e)\n    except NameError as e:\n        print(label, \"NameError\", e)\n    except Exception as e:\n        print(label, type(e).__name__, repr(e))\n\n\ndef r1():\n    raise 1\n\n\ndef r2():\n    raise int\n\n\ndef r3():\n    raise ValueError\n\n\ndef r4():\n    raise ValueError(\"x\")\n\n\ndef r5():\n    try:\n        raise KeyError(\"k\")\n    except KeyError as e:\n        raise e\n\n\nclass A:\n    pass\n\n\ndef r6():\n    raise A()\n\n\ndef r7():\n    raise A\n\n\ndef r8():\n    raise (ValueError)(\"p\")\n\n\ndef r9():\n    raise ValueError(\"a\") if True else KeyError(\"b\")\n\n\ndef r10():\n    raise Nope\n\n\ndef r11():\n    try:\n        raise ValueError(\"inner\")\n    except ValueError:\n        raise\n\n\nexc = [ValueError, KeyError]\n\n\ndef r12():\n    raise exc[1](\"from a list\")\n\n\nfor f in (r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12):\n    t(f.__name__, f)")
```
---
```output
r1 TypeError exceptions must derive from BaseException
r2 TypeError exceptions must derive from BaseException
r3 ValueError ValueError()
r4 ValueError ValueError('x')
r5 KeyError KeyError('k')
r6 TypeError exceptions must derive from BaseException
r7 TypeError exceptions must derive from BaseException
r8 ValueError ValueError('p')
r9 ValueError ValueError('a')
r10 NameError name 'Nope' is not defined
r11 ValueError ValueError('inner')
r12 KeyError KeyError('from a list')
```

### a bare raise raises again inside a handler, and is a RuntimeError outside one

```python
(python-run "def f():\n    try:\n        raise ValueError(\"val\", 3)\n    except:\n        raise\n\n\ntry:\n    f()\nexcept ValueError as e:\n    print(repr(e))\ntry:\n    raise\nexcept RuntimeError as e:\n    print(type(e).__name__, e)")
```
---
```output
ValueError('val', 3)
RuntimeError No active exception to reraise
```

### raise from records the cause

```python
(python-run "try:\n    raise Exception from None\nexcept Exception as e:\n    print(\"caught\", repr(e), e.__cause__)\ntry:\n    try:\n        raise ValueError(\"Value\")\n    except Exception as exc:\n        raise RuntimeError(\"Runtime\") from exc\nexcept Exception as ex2:\n    print(\"caught\", ex2, \"from\", repr(ex2.__cause__))\ntry:\n    raise ValueError(\"x\") from 1\nexcept TypeError as e:\n    print(e)")
```
---
```output
caught Exception() None
caught Runtime from ValueError('Value')
exception causes must derive from BaseException
```

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
    Error: KeyError: 'k'

### a try that does not raise runs no handler

```python
(python-run "try:\n    print('fine')\nexcept ValueError:\n    print('no')")
```
---
    fine

### except takes an expression: a class, a tuple of them, or a refusal when the exception arrives

```python
(python-run "exc = (KeyError, ValueError)\n\n\ndef t(f):\n    try:\n        f()\n    except TypeError as e:\n        print(\"TypeError\", e)\n\n\ndef e1():\n    try:\n        raise ValueError(\"v\")\n    except exc:\n        print(\"tuple matched\")\n\n\ndef e2():\n    try:\n        raise ValueError(\"v\")\n    except exc[1] as e:\n        print(\"subscript matched\", e)\n\n\ndef e3():\n    try:\n        raise ValueError(\"v\")\n    except 1:\n        pass\n\n\ndef e4():\n    try:\n        raise ValueError(\"v\")\n    except (1,):\n        pass\n\n\ndef e5():\n    try:\n        raise ValueError(\"v\")\n    except int:\n        pass\n\n\ndef e6():\n    try:\n        raise KeyboardInterrupt()\n    except BaseException:\n        print(\"BaseException\")\n\n\nfor f in (e1, e2, e3, e4, e5, e6):\n    t(f)")
```
---
```output
tuple matched
subscript matched v
TypeError catching classes that do not inherit from BaseException is not allowed
TypeError catching classes that do not inherit from BaseException is not allowed
TypeError catching classes that do not inherit from BaseException is not allowed
BaseException
```

### the as name is unbound when the handler ends, whichever way it ends

```python
(python-run "try:\n    raise ValueError(534)\nexcept ValueError as e:\n    print(type(e).__name__, e.args)\ntry:\n    e\nexcept NameError as err:\n    print(err)\ntry:\n    try:\n        raise KeyError(\"k\")\n    except KeyError as e:\n        raise\nexcept KeyError:\n    pass\ntry:\n    e\nexcept NameError as err:\n    print(\"after a re-raise:\", err)\n\n\ndef f():\n    try:\n        raise KeyError(\"k\")\n    except KeyError as e:\n        return 1\n\n\nf()\ntry:\n    e\nexcept NameError as err:\n    print(\"after a return:\", err)")
```
---
```output
ValueError (534,)
name 'e' is not defined
after a re-raise: name 'e' is not defined
after a return: name 'e' is not defined
```

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
and `1 % 0` answered None. Python spells all three ZeroDivisionError, with one
message.

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
    division by zero

### modulo

```python
(python-run "try:\n    print(1 % 0)\nexcept ZeroDivisionError as e:\n    print(e)")
```
---
    division by zero

### a zero to a finite negative power; an infinite or NaN exponent is libm's

```python
(python-run "for f in (lambda: 0 ** -1, lambda: 0.0 ** -1, lambda: 0 ** -1.5):\n    try:\n        f()\n    except ZeroDivisionError as e:\n        print(e)\ninf = float(\"inf\")\nprint(0.0 ** -inf, 0 ** -inf, (-2) ** float(\"nan\"), (-2.0) ** inf, (-2.0) ** -inf, (-0.5) ** inf)")
```
---
```output
zero to a negative power
zero to a negative power
zero to a negative power
inf inf nan inf 0.0 0.0
```

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

### a return inside try runs it on the way out

`return` invokes an escape continuation (see 13-return), and that continuation
used to jump straight past the `finally`. It no longer does: the block registers
its cleanup on a wind stack and the escape runs what the jump is about to skip
before it jumps, so `cleanup` prints before `1` — which is where Python puts it.

```python
(python-run "def f():\n    try:\n        return 1\n    finally:\n        print('cleanup')\nprint(f())")
```
---
```output
cleanup
1
```

### one return pays every finally it passes

The escape runs them innermost first, which is the order the blocks are left in.

```python
(python-run "def f():\n    try:\n        try:\n            return 'r'\n        finally:\n            print('inner')\n    finally:\n        print('outer')\nprint(f())")
```
---
```output
inner
outer
r
```

### a return out of a with inside a try pays both

The two owe different cleanups — `__exit__` and a `finally` — and a single
escape settles them in order.

```python
(python-run "class C:\n    def __enter__(self):\n        print('enter')\n        return self\n    def __exit__(self, a, b, c):\n        print('exit')\ndef f():\n    try:\n        with C():\n            return 'v'\n    finally:\n        print('fin')\nprint(f())")
```
---
```output
enter
exit
fin
v
```
