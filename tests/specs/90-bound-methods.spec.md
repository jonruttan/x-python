# bound methods

### a bound method is a value

The reprs are pinned short of the function's qualified name: CPython writes
`<function A.f at ...>` and `A.f() takes ...`, this runtime `<function f at
...>` and `f() takes ...`. A function knows its own name, not the class it was
defined in.

```python
(python-run "class A:\n    def f(self, x=0, k=1):\n        return x + k\n    def Fun(self):\n        pass\na = A()\nb = A()\nprint(repr(a.f)[:22])\nprint(str(a.f)[:22])\nprint(a.f.__name__, a.f.__self__ is a, a.f.__func__ is A.f)\nprint(a.f == a.f, a.f == b.f, a.f == a.Fun)\nprint(a.f is a.f)\nprint(hash(a.f) == hash(a.f))\nprint(repr(A.f)[:10], A.f.__name__)\nprint(bool(a.f), callable(a.f))")
```
---
```output
<bound method A.f of <
<bound method A.f of <
f True True
True False False
False
True
<function  f
True True
```

### it is called every way a function is

```python
(python-run "class A:\n    def f(self, x=0, k=1):\n        return x + k\na = A()\nprint(list(map(a.f, [1, 2])))\nprint(sorted([3, 1, 2], key=a.f))\nprint(a.f(*(5,)), a.f(**{\"x\": 5, \"k\": 2}), a.f(x=1))\nm = a.f\nprint(m(1), m(1, 2))\ntry:\n    a.f(1, 2, 3)\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
[2, 3]
[1, 2, 3]
6 7 2
2 3
TypeError
```

### classmethods, staticmethods and nested functions keep their names

```python
(python-run "class A:\n    def __init__(self):\n        pass\n    def Fun(self):\n        pass\n    @classmethod\n    def cm(cls):\n        return cls.__name__\n    @staticmethod\n    def sm():\n        return \"sm\"\na = A()\nprint(a.cm(), a.cm.__name__, A.cm.__name__)\nprint(a.sm(), a.sm.__name__)\nprint(A().Fun.__name__, A.__init__.__name__, A.Fun.__name__)\ndef outer():\n    def inner():\n        pass\n    return inner\nprint(outer.__name__, outer().__name__)")
```
---
```output
A cm cm
sm sm
Fun __init__ Fun
outer inner
```

### the operators still reach their dunders

```python
(python-run "class V:\n    def __init__(self, n):\n        self.n = n\n    def __eq__(self, o):\n        return self.n == o.n\n    def __len__(self):\n        return self.n\n    def __iter__(self):\n        return iter(range(self.n))\n    def __call__(self, k):\n        return self.n * k\n    def __add__(self, o):\n        return V(self.n + o.n)\nv = V(3)\nprint(v == V(3), len(v), list(v), v(2), (v + V(1)).n)\nprint(v.__eq__(V(3)), v.__len__())\nclass S:\n    def __init__(self, x):\n        self.x = x\n    def m(self):\n        return self.x\nprint([s.m() for s in [S(1), S(2)]])\nprint(sorted([S(2), S(1)], key=S.m)[0].x)")
```
---
```output
True 3 [0, 1, 2] 6 4
True 3
[1, 2]
1
```

### super's methods are bound the same way

```python
(python-run "class B:\n    def who(self):\n        return \"B\"\nclass C(B):\n    def who(self):\n        return \"C+\" + super().who()\n    def hand(self):\n        return super().who\nc = C()\nprint(c.who(), c.hand()(), c.hand().__name__)")
```
---
```output
C+B B who
```
