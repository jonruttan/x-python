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
