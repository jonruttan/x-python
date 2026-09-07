# **kwargs: a function that takes the rest

### a function collects its keyword arguments

```python
(python-run "def f(a, **kw):\n    return a, kw\nprint(f(1))\nprint(f(1, x=2, y=3))\nprint(f(a=9, z=1))")
```
---
```output
(1, {})
(1, {'x': 2, 'y': 3})
(9, {'z': 1})
```

### kwargs alone

```python
(python-run "def g(**kw):\n    return kw\nprint(g())\nprint(g(one=1, two=2))")
```
---
```output
{}
{'one': 1, 'two': 2}
```

### kwargs beside a default and a star

```python
(python-run "def h(a, b=2, *rest, **kw):\n    return a, b, rest, kw\nprint(h(1))\nprint(h(1, 5))\nprint(h(1, 5, 6, 7))\nprint(h(1, 5, 6, k=9))")
```
---
```output
(1, 2, (), {})
(1, 5, (), {})
(1, 5, (6, 7), {})
(1, 5, (6,), {'k': 9})
```

### a method takes them too

```python
(python-run "class C:\n    def __init__(self, a, **kw):\n        self.a = a\n        self.kw = kw\nc = C(1, colour=\"red\")\nprint(c.a, c.kw)")
```
---
```output
1 {'colour': 'red'}
```
