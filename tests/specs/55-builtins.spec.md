Builtins (`python/runtime.x`, `python/parse.x`): bin/hex/oct over the
format engine's base conversion, divmod, three-argument pow, round of an
int to a negative digit (half to even); lazy enumerate/filter/map over
several iterables, reversed through __reversed__ or length+getitem,
sorted and min/max with key; callable, id, getattr with a default,
setattr, delattr, issubclass; class attributes and one-line class bodies.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## builtins

### bases and divmod

```python
(python-run "print(bin(1), bin(-1), bin(15), bin(-15), bin(12345), bin(0b10101))\nprint(hex(1), hex(-1), hex(15), hex(-15), hex(12345))\nprint(oct(1), oct(-1), oct(15), oct(-15), oct(12345))\nprint(divmod(0, 2), divmod(3, 4), divmod(20, 3), divmod(-7, 2))\ntry:\n    divmod(1, 0)\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')\ntry:\n    divmod('a', 'b')\nexcept TypeError:\n    print('TypeError')\nprint(-7 // 2, 7 // -2, -7 % 2, 7 % -2, divmod(7, -2), -7.0 // 2, 7 // 2)\n")
```
---
```output
0b1 -0b1 0b1111 -0b1111 0b11000000111001 0b10101
0x1 -0x1 0xf -0xf 0x3039
0o1 -0o1 0o17 -0o17 0o30071
(0, 0) (0, 3) (6, 2) (-4, 1)
ZeroDivisionError
TypeError
-4 -4 1 -1 (-4, -1) -4.0 3
```

### callable and id

```python
(python-run "print(callable(None), callable(1), callable([]), callable('dfsd'), callable(callable))\nprint(callable(lambda: None))\ndef f():\n    pass\nprint(callable(f))\nclass A:\n    def f(self):\n        pass\nprint(callable(A), callable(A()), callable(A().f))\nclass B:\n    def __call__(self):\n        pass\nprint(callable(B()))\nprint(id(1) == id(2), id(None) == id(None))\nl = [1, 2]\nprint(id(l) == id(l))\ng = lambda: None\nprint(id(g) == id(g))\n")
```
---
```output
False False False False True
True
True
True False True
True
False True
True
True
```

### attributes and class bodies

```python
(python-run "class A:\n    var = 132\n    def __init__(self):\n        self.var2 = 34\n    def meth(self, i):\n        return 42 + i\na = A()\nprint(getattr(a, 'var'), getattr(a, 'var2'), getattr(a, 'meth')(5))\nprint(getattr(a, '_none_such', 123), getattr(a, 'var2', 456))\ntry:\n    getattr(a, b'var')\nexcept TypeError:\n    print('TypeError')\nsetattr(a, 'var', 123)\nsetattr(a, 'var2', 56)\nprint(a.var, a.var2)\nprint(hasattr(a, 'var'), hasattr(a, '_none_such'))\nclass C: pass\nc = C()\nc.x = 1\nprint(c.x)\ndelattr(c, 'x')\ntry:\n    c.x\nexcept AttributeError:\n    print('AttributeError')\nprint(issubclass(A, A), issubclass(A, (A,)))\ntry:\n    issubclass(A, 1)\nexcept TypeError:\n    print('TypeError')\n")
```
---
```output
132 34 47
123 34
TypeError
123 56
True False
1
AttributeError
True True
TypeError
```
