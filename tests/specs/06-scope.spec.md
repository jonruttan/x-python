Function bodies have their own scope. Before this, every assignment target in a
program hoisted to one module-level `def`, so a name assigned inside a function
and a name assigned outside it were the same name — wrong for Python, and wrong
silently.

The module-level scan now skips from a `def` to the DEDENT that closes it, and
each function hoists its own targets inside its own frame, where x's `def` binds
locally because the frame is the function's.

## scope locals

### a local does not clobber a module name

The case the old hoisting got wrong: both `x`es were one binding, so calling `f`
changed the module's `x`.

```python
(python-run "x = 'module'\ndef f():\n    x = 'local'\n    return x\nprint(f())\nprint(x)")
```
---
```output
local
module
```

### a module name is still visible inside a function

Python resolves a name not assigned in the function to the enclosing scope.

```python
(python-run "g = 10\ndef f():\n    return g + 1\nprint(f())")
```
---
    11

### two functions may use the same local name

```python
(python-run "def a():\n    n = 1\n    return n\ndef b():\n    n = 2\n    return n\nprint(a())\nprint(b())")
```
---
```output
1
2
```

### a parameter is not shadowed by the hoist

Parameters are already bound; re-declaring them would overwrite every argument
with nil on entry.

```python
(python-run "def f(a):\n    return a\nprint(f(5))")
```
---
    5

### a parameter may be assigned in the body

```python
(python-run "def f(a):\n    a = a + 1\n    return a\nprint(f(1))")
```
---
    2

### a local survives a loop inside the function

```python
(python-run "def f():\n    total = 0\n    i = 0\n    while i < 4:\n        total = total + i\n        i = i + 1\n    return total\nprint(f())")
```
---
    6

### a function's loop counter does not leak

```python
(python-run "i = 'outer'\ndef f():\n    i = 0\n    while i < 2:\n        i = i + 1\n    return i\nprint(f())\nprint(i)")
```
---
```output
2
outer
```

## scope unbound

A def's names start out unbound, and a read that may find one unbound is
checked: its own names raise UnboundLocalError, and a def's names read from a
nested def, lambda or class body raise NameError.  Where a name is bound for
certain -- a parameter, a for loop's names in its body, a name an earlier
statement of the block assigned, or every branch of an if that falls through
-- the read is the bare name.

### a local read before anything binds it is UnboundLocalError

```python
(python-run "def show(f):\n    try:\n        f()\n    except NameError as e:\n        print(type(e).__name__, e)\n\ndef early():\n    print(x)\n    x = 1\n\ndef empty_loop():\n    for i in range(0):\n        pass\n    return i\n\ndef branch_not_taken():\n    if False:\n        n = 1\n    n += 1\n\ndef deleted():\n    v = 1\n    del v\n    return v\n\ndef deleted_unbound():\n    del w\n    w = 1\n\ndef in_comprehension():\n    r = [y for _ in range(1)]\n    y = 1\n\nshow(early)\nshow(empty_loop)\nshow(branch_not_taken)\nshow(deleted)\nshow(deleted_unbound)\nshow(in_comprehension)\nprint(issubclass(UnboundLocalError, NameError))")
```
---
```output
UnboundLocalError cannot access local variable 'x' where it is not associated with a value
UnboundLocalError cannot access local variable 'i' where it is not associated with a value
UnboundLocalError cannot access local variable 'n' where it is not associated with a value
UnboundLocalError cannot access local variable 'v' where it is not associated with a value
UnboundLocalError cannot access local variable 'w' where it is not associated with a value
UnboundLocalError cannot access local variable 'y' where it is not associated with a value
True
```

### a def's name read from a nested scope is a NameError while it is unbound

```python
(python-run "def show(f):\n    try:\n        print(f())\n    except NameError as e:\n        print(type(e).__name__, e)\n\ndef closure_early():\n    def g():\n        return late\n    r = g()\n    late = 1\n\ndef closure_late():\n    def g():\n        return late\n    late = 2\n    return g()\n\ndef nonlocal_deleted():\n    x = 0\n    def g():\n        nonlocal x\n        del x\n        return x\n    return g()\n\ndef class_body():\n    class C:\n        y = z\n    z = 3\n\ndef lambda_early():\n    f = lambda: w\n    r = f()\n    w = 4\n\nshow(closure_early)\nshow(closure_late)\nshow(nonlocal_deleted)\nshow(class_body)\nshow(lambda_early)")
```
---
```output
NameError cannot access free variable 'late' where it is not associated with a value in enclosing scope
2
NameError cannot access free variable 'x' where it is not associated with a value in enclosing scope
NameError cannot access free variable 'z' where it is not associated with a value in enclosing scope
NameError cannot access free variable 'w' where it is not associated with a value in enclosing scope
```

### a name only some branches of an if bind may be unbound after it

```python
(python-run "def show(f, *a):\n    try:\n        print(f(*a))\n    except NameError as e:\n        print(type(e).__name__, e)\n\ndef chain(x):\n    if x == 1:\n        k = \"one\"\n    elif x == 2:\n        pass\n    else:\n        k = \"many\"\n    return k\n\ndef leaves(x):\n    if x:\n        k = x\n    else:\n        return \"none\"\n    return k\n\ndef nested(x, y):\n    if x:\n        if y:\n            k = 1\n    else:\n        k = 3\n    return k\n\nshow(chain, 1); show(chain, 2)\nshow(leaves, 0); show(leaves, 5)\nshow(nested, 1, 1); show(nested, 1, 0); show(nested, 0, 0)")
```
---
```output
one
UnboundLocalError cannot access local variable 'k' where it is not associated with a value
none
5
1
UnboundLocalError cannot access local variable 'k' where it is not associated with a value
3
```

### every binding form binds, and a with statement's name stays bound after it

```python
(python-run "class CM:\n    def __enter__(self):\n        return \"entered\"\n    def __exit__(self, *a):\n        return False\n\ndef f(n, *rest, k=1):\n    a, (b, *c) = n, (1, 2, 3)\n    a += k\n    with CM() as got:\n        inside = got\n    for i in range(2):\n        last = i\n    xs = [i * a for i in range(3)]\n    if (w := n) > 0:\n        pos = w\n    class K:\n        v = a\n    def g():\n        return a + late\n    late = 10\n    return a, b, c, inside, got, last, xs, pos, K.v, g()\n\nprint(f(3))\nwith CM() as top:\n    pass\nprint(top)")
```
---
```output
(4, 1, [2, 3], 'entered', 'entered', 1, [0, 4, 8], 3, 4, 14)
entered
```
