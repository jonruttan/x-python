# super: what it reaches and how it prints

### super().__init__() reaches object

```python
(python-run "class Test(object):\n    def __init__(self):\n        super().__init__()\n        print(\"Test.__init__\")\nt = Test()\nclass Test2:\n    def __init__(self):\n        super().__init__()\n        print(\"Test2.__init__\")\nt = Test2()")
```
---
```output
Test.__init__
Test2.__init__
```

### a base's __init__ through super

```python
(python-run "class Base:\n    def __init__(self):\n        self.a = 1\n    def meth(self):\n        print(\"in Base meth\", self.a)\nclass Sub(Base):\n    def __init__(self):\n        super().__init__()\n        self.b = 2\n    def meth(self):\n        print(\"in Sub meth\")\n        return super().meth()\ns = Sub()\nprint(s.a, s.b)\ns.meth()")
```
---
```output
1 2
in Sub meth
in Base meth 1
```

### super prints as Python does

```python
(python-run "class A:\n    def p(self):\n        print(str(super())[:18])\nA().p()\nclass B(A):\n    def q(self):\n        print(str(super())[:18])\nB().q()")
```
---
```output
<super: <class 'A'
<super: <class 'B'
```

### attributes through super

```python
(python-run "class A:\n    bar = 123\n    def foo(self):\n        print('A foo')\n        return [1, 2, 3]\nclass B(A):\n    def foo(self):\n        print('B foo')\n        print(super().bar)\n        return super().foo()[0]\nprint(B().foo())")
```
---
```output
B foo
123
A foo
1
```

### super() in a classmethod binds the class it was called through

```python
(python-run "class C70:\n    @classmethod\n    def f(cls):\n        print(\"C.f\", cls.__name__)\n\n    @staticmethod\n    def s():\n        print(\"C.s\")\n\n    def m(self):\n        print(\"C.m\", type(self).__name__)\n\n    @property\n    def p(self):\n        return \"C.p\"\n\n\nclass D70(C70):\n    @classmethod\n    def f(cls):\n        print(\"D.f\", cls.__name__)\n        super().f()\n\n    @classmethod\n    def g(cls):\n        super(D70, cls).f()\n        super().s()\n        print(super().m.__name__, super().p is C70.__dict__[\"p\"])\n\n    def m(self):\n        super().m()\n        super().f()\n\n    @property\n    def p(self):\n        return \"D.p+\" + super().p\n\n\nclass E70(D70):\n    pass\n\n\nD70.f()\nE70().f()\nE70.g()\nE70().m()\nprint(E70().p)\n\n\nclass N70:\n    def __new__(cls, *args):\n        print(\"N.__new__\", cls.__name__, args)\n        return super().__new__(cls)\n\n    def __init__(self, v):\n        self.v = v\n\n\nclass M70(N70):\n    def __new__(cls, *args):\n        print(\"M.__new__\", cls.__name__, args)\n        return super().__new__(cls, *args)\n\n\nprint(M70(4).v)")
```
---
```output
D.f D70
C.f D70
D.f E70
C.f E70
C.f E70
C.s
m True
C.m E70
C.f E70
D.p+C.p
M.__new__ M70 (4,)
N.__new__ M70 (4,)
4
```

### __new__ through super comes back unbound, from a class or an instance

```python
(python-run "class Q70:\n    def __new__(cls, *args):\n        print(\"Q70.__new__\", cls.__name__, args)\n        return super().__new__(cls)\n\n\nq70 = Q70()\nprint(type(super(Q70, q70).__new__(Q70)).__name__)\n\n\nclass R70(Q70):\n    pass\n\n\nprint(type(super(R70, R70()).__new__(R70)).__name__)")
```
---
```output
Q70.__new__ Q70 ()
Q70
Q70.__new__ R70 ()
Q70.__new__ R70 ()
R70
```
