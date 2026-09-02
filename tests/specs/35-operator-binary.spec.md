The operator protocol (`python/runtime.x`): a user class takes part in
every operator through its dunders, and the seams ask the way Python does --
the left operand's `__op__`, then the right operand's reflected `__rop__`,
with NotImplemented from either meaning "try the other side". Comparison
dunders answer raw values (an `__eq__` returning 123 prints 123); the default
`__ne__` inverts `__eq__`; print shows `__str__` while a container shows
`__repr__`; `__iter__`/`__next__` run until StopIteration and `__getitem__`
until IndexError. The check that opens every seam is one type test, so the
numeric path pays nothing. Every expectation is a real CPython output.


Split three ways for CI visibility: both CI lanes' hosts died during the
combined file with no case-level failure and no flushed progress, while
both local trees pass it -- the file boundaries are what the log shows,
so each group runs in its own process until the culprit is known.

## binary operators dispatch to the class

### __add__ on the left

```python
(python-run "class A:\n    def __add__(self, x):\n        print('__add__')\n        return 1\nprint(A() + 1j)\nprint(A() + 2)")
```
---
```output
__add__
1
__add__
1
```

### __radd__ on the right, after the left declines

```python
(python-run "class A:\n    def __radd__(self, x):\n        print('__radd__')\n        return 2\nprint(1j + A())\nprint(3 + A())")
```
---
```output
__radd__
2
__radd__
2
```

### a vector class, with repr inside a list

```python
(python-run "class V:\n    def __init__(self, x):\n        self.x = x\n    def __add__(self, o):\n        return V(self.x + o.x)\n    def __sub__(self, o):\n        return V(self.x - o.x)\n    def __mul__(self, k):\n        return V(self.x * k)\n    def __rmul__(self, k):\n        return V(k * self.x)\n    def __neg__(self):\n        return V(-self.x)\n    def __repr__(self):\n        return 'V(%d)' % self.x\nprint(V(1) + V(2), V(5) - V(2), V(3) * 4, 5 * V(3), -V(7), [V(1), V(2)])")
```
---
    V(3) V(3) V(12) V(15) V(-7) [V(1), V(2)]

### NotImplemented hands over, and both declining is a TypeError

```python
(python-run "class N:\n    def __add__(self, o):\n        return NotImplemented\n    def __radd__(self, o):\n        return 'radd'\nclass M:\n    def __add__(self, o):\n        return NotImplemented\nprint(M() + N())\ntry:\n    M() + M()\nexcept TypeError:\n    print('TypeError')\nprint(NotImplemented)")
```
---
```output
radd
TypeError
NotImplemented
```

### the rest of the family

```python
(python-run "class B:\n    def __or__(self, o):\n        return 'or'\n    def __rand__(self, o):\n        return 'rand'\n    def __lshift__(self, o):\n        return 'lsh'\n    def __rshift__(self, o):\n        return 'rsh'\n    def __pow__(self, o):\n        return 'pow'\n    def __mod__(self, o):\n        return 'mod'\n    def __floordiv__(self, o):\n        return 'fdiv'\n    def __truediv__(self, o):\n        return 'div'\nb = B()\nprint((b | 1, 1 & b, b << 1, b >> 1, b ** 2, b % 2, b // 2, b / 2))")
```
---
    ('or', 'rand', 'lsh', 'rsh', 'pow', 'mod', 'fdiv', 'div')

