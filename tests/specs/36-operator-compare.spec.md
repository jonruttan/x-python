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

### a chain binds each middle operand once, stops at the first comparison that is not true, and answers it

```python
(python-run "print(1 < 2 < 3, 1 < 2 < 3 < 4, 1 > 2 < 3, 1 < 2 > 3, 3 > 2 > 1, 1 == 1 == 1, 1 == 1 != 2)\ncalls = []\n\n\ndef v(x):\n    calls.append(x)\n    return x\n\n\nprint(v(1) < v(2) < v(3), calls)\ncalls.clear()\nprint(v(3) < v(2) < v(1), calls)\nx = 5\nprint(0 <= x < 10, 0 <= x < 3, \"a\" < \"b\" < \"c\", 2 < x < 10 > 7)\nprint(1 in [1, 2] in [[1, 2]], 5 not in [1] == True, None is None is not 3, 1 < 2 in [True])\n\n\nclass L:\n    def __init__(self, v):\n        self.v = v\n\n    def __lt__(self, o):\n        return self.v * 10\n\n    def __gt__(self, o):\n        return 0\n\n\nprint(L(1) < L(2) < L(3), L(1) > L(2) < L(3), (L(1) < L(2)) < L(3))\nprint([1, 2] == [1, 2] == [1, 2], (1, 2) < (1, 3) <= (1, 3))")
```
---
```output
True True False False True True True
True [1, 2, 3]
False [3, 2]
True False True True
True False True False
20 0 0
True True
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

