# spreading a dict into a call

### a call spreads a dict as keywords

```python
(python-run "def f(a, b=0, **kw):\n    return a, b, kw\nd = {\"b\": 5, \"z\": 9}\nprint(f(1, **d))\nprint(f(1, b=2, **{\"y\": 3}))\nprint(f(**{\"a\": 7}))")
```
---
```output
(1, 5, {'z': 9})
(1, 2, {'y': 3})
(7, 0, {})
```

### spreading into a function without kwargs

```python
(python-run "def g(a, b):\n    return a + b\nprint(g(**{\"a\": 1, \"b\": 2}))\nprint(g(1, **{\"b\": 4}))")
```
---
```output
3
5
```

### both spreads at once

```python
(python-run "def h(*args, **kw):\n    return args, kw\nprint(h(*[1, 2], **{\"k\": 3}))\nprint(h(*[], **{}))")
```
---
```output
((1, 2), {'k': 3})
((), {})
```

### a subclass passes them down

```python
(python-run "class Base:\n    def __init__(self, *args, **kwargs):\n        self.args = args\n        self.kwargs = kwargs\nclass Sub(Base):\n    def __init__(self, *args, **kwargs):\n        super().__init__(*args, **kwargs)\ns = Sub(1, 2, colour=\"red\")\nprint(s.args, s.kwargs)")
```
---
```output
(1, 2) {'colour': 'red'}
```
