# Scoping: annotations, and a class body's names

Variable annotations, and what a class body binds and reads of a function
around it.  The expectations are CPython 3.14's.

## annotations

An annotation is not kept: there is no `__annotations__` here.

### an annotated assignment assigns, and a bare annotation binds nothing but makes a function's name its own

```python
(python-run "x: int = 1\nt: tuple = 1, 2\nprint(x, t)\nclass A:\n    a: int\n    b: str = 'b'\nprint(hasattr(A, 'a'), A.b)\ndef f():\n    y: int\n    try:\n        print(y)\n    except NameError as e:\n        print(type(e).__name__)\n    y = 3\n    return y\nprint(f())\nclass P:\n    def __init__(self):\n        self.v: int = 7\np = P()\np.w: int\nprint(p.v, hasattr(p, 'w'))\nd = {}\nd['k']: int = 1\nd['m']: int\nprint(d)\nif d: q: int = 9\nprint(q)")
```
---
```output
1 (1, 2)
False b
UnboundLocalError
3
7 False
{'k': 1}
9
```

### a bare annotation does not put a name in globals

DIVERGENCE: a module's names are bound before its first statement runs, so a
name the module assigns anywhere is in `globals()` from the start; CPython
lists it once the assignment has run.

```python
(python-run "x: int\nprint('x' in globals())\nx = 1\nprint('x' in globals())")
```
---
```output
True
True
```

## a class body's names

### nonlocal in a class body binds the function's variable, and a name the class binds is read from the module before that

```python
(python-run "def t():\n    def m():\n        return 'outer'\n    class A:\n        nonlocal m\n        def m():\n            return 'inner'\n        x = 1\n    print(hasattr(A, 'm'), A.x)\n    return m()\nprint(t())\ndef u():\n    v = 1\n    class B:\n        nonlocal v\n        v = 2\n        w = v + 1\n    return v, B.w, hasattr(B, 'v')\nprint(u())\ng = 'global'\ndef test4(g):\n    class A:\n        local = g\n        g = 'class'\n    g += 1\n    return g, A.local, A.g\nprint(test4(42), g)\ndef test5():\n    h = 'local'\n    class C:\n        h = h + '!'\n    return C.h\ntry:\n    print(test5())\nexcept NameError as e:\n    print('NameError')")
```
---
```output
False 1
inner
(2, 3, False)
(43, 'global', 'class') global
NameError
```
