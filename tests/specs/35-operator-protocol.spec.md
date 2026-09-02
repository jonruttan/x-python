The operator protocol (`python/runtime.x`): a user class takes part in
every operator through its dunders, and the seams ask the way Python does --
the left operand's `__op__`, then the right operand's reflected `__rop__`,
with NotImplemented from either meaning "try the other side". Comparison
dunders answer raw values (an `__eq__` returning 123 prints 123); the default
`__ne__` inverts `__eq__`; print shows `__str__` while a container shows
`__repr__`; `__iter__`/`__next__` run until StopIteration and `__getitem__`
until IndexError. The check that opens every seam is one type test, so the
numeric path pays nothing. Every expectation is a real CPython output.

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

## comparisons answer raw values

### __eq__ returning 123, the default __ne__ inverting it, the reflected walk

```python
(python-run "class E:\n    def __repr__(self):\n        return 'E'\n    def __eq__(self, other):\n        print('E eq', other)\n        return 123\nclass F:\n    def __repr__(self):\n        return 'F'\n    def __ne__(self, other):\n        print('F ne', other)\n        return -456\nprint(E() != F())\nprint(F() != E())\nfor val in (None, 0, 1, 'a'):\n    print('==== testing', val)\n    print(E() == val)\n    print(val == E())\n    print(E() != val)\n    print(val != E())\n    print(F() == val)\n    print(val == F())\n    print(F() != val)\n    print(val != F())")
```
---
```output
E eq F
False
F ne E
-456
==== testing None
E eq None
123
E eq None
123
E eq None
False
E eq None
False
False
False
F ne None
-456
F ne None
-456
==== testing 0
E eq 0
123
E eq 0
123
E eq 0
False
E eq 0
False
False
False
F ne 0
-456
F ne 0
-456
==== testing 1
E eq 1
123
E eq 1
123
E eq 1
False
E eq 1
False
False
False
F ne 1
-456
F ne 1
-456
==== testing a
E eq a
123
E eq a
123
E eq a
False
E eq a
False
False
False
F ne a
-456
F ne a
-456
```

### ordering reflects onto mirrors; identity and refusal by default

```python
(python-run "class P:\n    def __init__(self, v):\n        self.v = v\n    def __lt__(self, o):\n        return self.v < o.v\n    def __le__(self, o):\n        return self.v <= o.v\n    def __eq__(self, o):\n        return self.v == o.v\nprint((P(1) < P(2), P(2) < P(1), P(1) <= P(1), P(3) > P(2), P(2) >= P(2), P(1) == P(1), P(1) != P(2)))\nclass Q:\n    pass\ntry:\n    Q() < Q()\nexcept TypeError:\n    print('TypeError')\nq = Q()\nprint((q == q, q == Q(), q != q))")
```
---
```output
(True, False, True, True, True, True, True)
TypeError
(True, False, False)
```

## str and repr part ways at print

### print shows __str__; a container shows __repr__

```python
(python-run "class S:\n    def __str__(self):\n        return 'as str'\n    def __repr__(self):\n        return 'as repr'\ns = S()\nprint(s)\nprint(str(s), repr(s))\nprint([s])\nclass R:\n    def __repr__(self):\n        return 'only repr'\nprint(R(), [R()], str(R()))")
```
---
```output
as str
as str as repr
[as repr]
only repr [only repr] only repr
```

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
