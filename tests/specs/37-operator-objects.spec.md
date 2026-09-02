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

## containers, calls, truth, attributes

### __getitem__ __setitem__ __contains__ __len__ __call__ __bool__

```python
(python-run "class C:\n    def __init__(self):\n        self.d = {}\n    def __getitem__(self, k):\n        return self.d.get(k, 'missing')\n    def __setitem__(self, k, v):\n        self.d[k] = v\n    def __contains__(self, k):\n        return k in self.d\n    def __len__(self):\n        return len(self.d)\n    def __call__(self, a, b):\n        return ('called', a, b)\n    def __bool__(self):\n        return len(self.d) > 0\nc = C()\nprint((bool(c), len(c), c['a'], 'a' in c))\nc['a'] = 1\nprint((bool(c), len(c), c['a'], 'a' in c, 'b' not in c))\nprint(c(1, 2))\nif c:\n    print('truthy')")
```
---
```output
(False, 0, 'missing', False)
(True, 1, 1, True, True)
('called', 1, 2)
truthy
```

### __len__ decides truth without __bool__; __getattr__ is the last resort

```python
(python-run "class L:\n    def __len__(self):\n        return 0\nprint(bool(L()))\nif not L():\n    print('falsy by len')\nclass G:\n    def __getattr__(self, name):\n        return 'dyn_' + name\ng = G()\ng.real = 5\nprint((g.real, g.foo, g.bar))")
```
---
```output
False
falsy by len
(5, 'dyn_foo', 'dyn_bar')
```

## iteration

### __iter__ and __next__ until StopIteration; the sequence protocol by __getitem__

```python
(python-run "class It:\n    def __init__(self, n):\n        self.n = n\n        self.i = 0\n    def __iter__(self):\n        return self\n    def __next__(self):\n        if self.i >= self.n:\n            raise StopIteration\n        self.i += 1\n        return self.i\nfor x in It(3):\n    print(x)\nprint(list(It(2)), 2 in It(3), 9 in It(3))\nclass Seq:\n    def __getitem__(self, i):\n        if i >= 3:\n            raise IndexError\n        return i * 10\nprint(list(Seq()))\nfor v in Seq():\n    print(v)")
```
---
```output
1
2
3
[1, 2] True False
[0, 10, 20]
0
10
20
```

## conversions

### complex() through __complex__ and __float__, with Python's refusals

```python
(python-run "class TestFloat:\n    def __float__(self):\n        return 1.0\nclass TestComplex:\n    def __complex__(self):\n        return 1j + 10\nclass TestStrComplex:\n    def __complex__(self):\n        return 'a'\nclass TestNonComplex:\n    def __complex__(self):\n        return 6\nclass Test:\n    pass\nprint(complex(TestFloat()))\nprint(complex(TestComplex()))\ntry:\n    print(complex(TestStrComplex()))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(complex(TestNonComplex()))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(complex(Test()))\nexcept TypeError:\n    print('TypeError')")
```
---
```output
(1+0j)
(10+1j)
TypeError
TypeError
TypeError
```

### int float abs hash invert pos

```python
(python-run "class A:\n    def __int__(self):\n        return 1 << 100\n    def __float__(self):\n        return 2.5\n    def __abs__(self):\n        return 'abs!'\n    def __hash__(self):\n        return 42\n    def __invert__(self):\n        return 'inv'\n    def __pos__(self):\n        return 'pos'\nprint((int(A()), float(A()), abs(A()), hash(A()), ~A(), +A()))")
```
---
    (1267650600228229401496703205376, 2.5, 'abs!', 42, 'inv', 'pos')
