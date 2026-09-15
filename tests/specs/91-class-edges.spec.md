# class edges

### bytes of a plain object is a TypeError

```python
(python-run "class C:\n    pass\ntry:\n    bytes(C())\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
TypeError
```

### assert

```python
(python-run "assert 1 == 1\ntry:\n    assert 1 == 2\nexcept AssertionError:\n    print(\"AssertionError\")\ntry:\n    assert 0, \"zero\"\nexcept AssertionError as e:\n    print(\"AssertionError\", e)")
```
---
```output
AssertionError
AssertionError zero
```

### the matrix-multiply operators

```python
(python-run "class M:\n    def __matmul__(self, o):\n        return \"mm\"\n    def __rmatmul__(self, o):\n        return \"rmm\"\n    def __imatmul__(self, o):\n        print(\"__imatmul__\")\n        return self\nm = M()\nprint(m @ 1)\nprint(1 @ m)\nm @= 2\ntry:\n    1 @ 2\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
mm
rmm
__imatmul__
TypeError
```

### every value has a __class__

```python
(python-run "class C1:\n    pass\nc = C1()\nprint(\"C1 object\" in repr(c))\nprint(None.__class__, \"x\".__class__, (1).__class__, [].__class__)\nprint(c.__class__ is C1, type(c) is C1)")
```
---
```output
True
<class 'NoneType'> <class 'str'> <class 'int'> <class 'list'>
True True
```

### an instance binds a def, not a stored builtin or value

```python
(python-run "class A:\n    def __init__(self, arg):\n        self.val = arg\n    def __str__(self):\n        return \"A.__str__ \" + str(self.val)\n    def __call__(self, arg):\n        return \"A.__call__\", arg\n    def foo(self, arg):\n        return \"A.foo\", self.val, arg\nclass C:\n    def f1(self, arg):\n        return \"C.f1\", self is c, arg\n    f2 = lambda self, arg: (\"C.f2\", self is c, arg)\n    f5 = int\n    f6 = abs\n    f7 = A\n    f8 = A(8)\n    f9 = A(9).foo\nc = C()\nprint(c.f1(1))\nprint(c.f2(2))\nprint(c.f5(5))\nprint(c.f6(-6))\nprint(c.f7(7))\nprint(c.f8(8))\nprint(c.f9(9))")
```
---
```output
('C.f1', True, 1)
('C.f2', True, 2)
5
6
A.__str__ 7
('A.__call__', 8)
('A.foo', 9, 9)
```

### staticmethod and classmethod as dunders

```python
(python-run "class C:\n    @staticmethod\n    def f(rhs):\n        print(\"f\", rhs)\n    @classmethod\n    def g(self, rhs):\n        print(\"g\", rhs)\n    @staticmethod\n    def __sub__(rhs):\n        print(\"sub\", rhs)\n    @classmethod\n    def __add__(self, rhs):\n        print(\"add\", rhs)\n    @staticmethod\n    def __getitem__(item):\n        print(\"static get\", item)\n        return \"item\"\n    @staticmethod\n    def __setitem__(item, value):\n        print(\"static set\", item, value)\n    @staticmethod\n    def __delitem__(item):\n        print(\"static del\", item)\nc = C()\nc.f(0)\nc.g(0)\nc - 1\nc + 2\nprint(c[1])\nc[1] = 2\ndel c[3]")
```
---
```output
f 0
g 0
sub 1
add 2
static get 1
item
static set 1 2
static del 3
```

### a class's __setattr__ and __delattr__ reach object's defaults

```python
(python-run "class B:\n    def __setattr__(self, attr, value):\n        print(\"set\", attr)\n        object.__setattr__(self, attr, value)\n    def __delattr__(self, attr):\n        print(\"del\", attr)\n        object.__delattr__(self, attr)\nb = B()\nb.x = 1\nprint(b.x)\ndel b.x\nprint(hasattr(b, \"x\"))")
```
---
```output
set x
1
del x
False
```

### a class attribute can be deleted, and __set_name__ can set a sibling

```python
(python-run "class K:\n    a = 1\n    b = 2\ndel K.a\ndelattr(K, \"b\")\nprint(hasattr(K, \"a\"), hasattr(K, \"b\"))\ntry:\n    del K.zz\nexcept AttributeError:\n    print(\"AttributeError\")\nclass S:\n    def __set_name__(self, owner, name):\n        setattr(owner, name + \"_sib\", 121)\nclass T:\n    desc = S()\nprint(T().desc_sib)")
```
---
```output
False False
AttributeError
121
```

### __new__, and two-argument super inside it

```python
(python-run "class A:\n    def __new__(cls):\n        print(\"A.__new__\")\n        return super(cls, A).__new__(cls)\n    def __init__(self):\n        print(\"A.__init__\")\n    def meth(self):\n        print(\"A.meth\")\na = A()\na.meth()\na = A.__new__(A)\na.meth()\nclass B:\n    def __new__(self, v1, v2):\n        print(\"B.__new__\", v1, v2)\n    def __init__(self, v1, v2):\n        print(\"B.__init__\", v1, v2)\nprint(\"B inst:\", B(1, 2))\nclass Dummy:\n    pass\nclass C:\n    def __new__(cls):\n        print(\"C.__new__\")\n        return Dummy()\n    def __init__(self):\n        print(\"C.__init__\")\nprint(isinstance(C(), Dummy))\ntry:\n    super(1, 1)\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
A.__new__
A.__init__
A.meth
A.__new__
A.meth
B.__new__ 1 2
B inst: None
C.__new__
True
TypeError
```

### the class body's own __str__ and __repr__

```python
(python-run "class C1:\n    def __init__(self, value):\n        self.value = value\n    def __str__(self):\n        return \"str<C1 {}>\".format(self.value)\nclass C2:\n    def __init__(self, value):\n        self.value = value\n    def __repr__(self):\n        return \"repr<C2 {}>\".format(self.value)\nc1 = C1(1)\nprint(c1)\nprint(str(c1))\nprint(\"C1 object\" in repr(c1))\nc2 = C2(2)\nprint(c2, str(c2), repr(c2))")
```
---
```output
str<C1 1>
str<C1 1>
True
repr<C2 2> repr<C2 2> repr<C2 2>
```
