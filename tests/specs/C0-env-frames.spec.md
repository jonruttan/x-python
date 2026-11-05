# a program's and a module's environment

A program's globals and a module's names live in an environment the runtime
makes with `pair`, and x-lang keeps a tree behind one of those (x-lang
`docs/engine-laws.md`, law 10, from v0.46.0); a call's frame keeps a list.
The runtime reads a name's own binding in either: a `global` or `nonlocal`
assignment rebinds the cell it finds, `globals()` and `locals()` list a
frame's names, and a module the runtime writes answers its attributes.
The expectations are CPython 3.14's.

## a program's frame

### a global and a nonlocal rebound, and globals() read

```python
(python-run "x = 1\ndef f():\n    global x\n    x = 2\nf()\nprint(x)\ndef g():\n    y = 1\n    def h():\n        nonlocal y\n        y = 5\n    h()\n    return y\nprint(g())\nprint('x' in globals(), globals()['x'], 'nope' in globals())")
```
---
```output
2
5
True 2 False
```

### a function's locals() and a name bound after a hoist

```python
(python-run "def f(a):\n    b = 2\n    return sorted(locals().items())\nprint(f(1))\nprint(len([1, 2]))\nlen = 3\nprint(len)")
```
---
```output
[('a', 1), ('b', 2)]
2
3
```

## a module the runtime writes

### its attributes read, one stored, and its names listed

```python
(python-run "import math\nprint(math.floor(2.5), math.__name__)\nmath.answer = 42\nprint(math.answer)\nprint('pi' in dir(math), 'answer' in dir(math))")
```
---
```output
2 math
42
True True
```
