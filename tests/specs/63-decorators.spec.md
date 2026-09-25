# decorators: a def wrapped by a call

### staticmethod, from the class and from an instance

```python
(python-run "class C:\n    @staticmethod\n    def s(x):\n        return x + 1\nprint(C.s(1), C().s(2))")
```
---
```output
2 3
```

### classmethod binds the class

```python
(python-run "class C:\n    @classmethod\n    def who(cls):\n        return cls.__name__\nprint(C.who(), C().who())")
```
---
```output
C C
```

### a classmethod called on a subclass gets the subclass

```python
(python-run "class Base:\n    @classmethod\n    def who(cls):\n        return cls.__name__\nclass Sub(Base):\n    pass\nprint(Base.who(), Sub.who(), Sub().who())")
```
---
```output
Base Sub Sub
```

### property is computed on access

```python
(python-run "class C:\n    def __init__(self):\n        self._v = 3\n    @property\n    def v(self):\n        return self._v * 2\nc = C()\nprint(c.v)\nc._v = 10\nprint(c.v)")
```
---
```output
6
20
```

### a plain method still binds self

```python
(python-run "class C:\n    def __init__(self):\n        self.n = 5\n    def get(self):\n        return self.n\n    @staticmethod\n    def plain():\n        return \"no self\"\nc = C()\nprint(c.get(), c.plain(), C.plain())")
```
---
```output
5 no self no self
```

### a user-written decorator is just a call

```python
(python-run "def twice(f):\n    def wrapper(x):\n        return f(f(x))\n    return wrapper\n\n@twice\ndef inc(n):\n    return n + 1\n\nprint(inc(0), inc(10))")
```
---
```output
2 12
```

### decorators stack bottom up

```python
(python-run "def add(n):\n    def deco(f):\n        def w(x):\n            return f(x) + n\n        return w\n    return deco\n\n@add(100)\n@add(10)\ndef f(x):\n    return x\n\nprint(f(1))")
```
---
```output
111
```

### a class-body decorator on a method that takes arguments

```python
(python-run "class Adder:\n    @classmethod\n    def of(cls, a, b):\n        return (cls.__name__, a + b)\n    @staticmethod\n    def raw(a, b):\n        return a * b\nprint(Adder.of(1, 2), Adder.raw(3, 4), Adder().raw(5, 6))")
```
---
```output
('Adder', 3) 12 30
```

### a class decorator is called with the class, and its answer is bound

```python
(python-run "def dec(c):\n    print(\"dec\", c.__name__)\n    return c\n\n\ndef tag(t):\n    def d(c):\n        c.tag = t\n        return c\n    return d\n\n\n@dec\nclass A:\n    pass\n\n\n@tag(\"t1\")\n@dec\nclass B:\n    x = 1\n\n\nprint(A.__name__, B.tag, B.x, B().x)\n\n\n@lambda c: 42\nclass C:\n    pass\n\n\nprint(C)\n\n\ndef g():\n    @tag(\"inner\")\n    class D:\n        pass\n    return D.tag\n\n\nprint(g())")
```
---
```output
dec A
dec B
A t1 1 1
42
inner
```

### a decorator before anything but a def or a class is refused

```python
(python-run "try:\n    exec(\"@staticmethod\\nx = 1\")\nexcept SyntaxError:\n    print(\"SyntaxError\")")
```
---
```output
SyntaxError
```

### a property's setter and deleter, from @x.setter and @x.deleter or passed to property(); none refuses in CPython's words

```python
(python-run "class C63:\n    def __init__(self):\n        self._v = 0\n\n    @property\n    def v(self):\n        return self._v\n\n    @v.setter\n    def v(self, value):\n        print(\"set\", value)\n        self._v = value\n\n    @v.deleter\n    def v(self):\n        print(\"del\")\n\n\nclass B63:\n    def __init__(self):\n        self._w = 3\n\n    def getw(self):\n        return self._w\n\n    def setw(self, value):\n        self._w = value\n\n    w = property(getw, setw)\n\n\nc63 = C63()\nc63.v = 5\nprint(c63.v)\ndel c63.v\nb63 = B63()\nb63.w = 4\nprint(b63.w, property(fget=len, doc=\"doc\").__doc__)\n\n\nclass D63:\n    ro = property(lambda self: \"ro\")\n    none = property()\n\n\nd63 = D63()\nfor label, th in ((\"set\", lambda: setattr(d63, \"ro\", 1)), (\"del\", lambda: delattr(d63, \"ro\")),\n                  (\"get\", lambda: d63.none)):\n    try:\n        th()\n    except AttributeError as e:\n        print(label, \"AttributeError\", e)\nprint(d63.ro)")
```
---
```output
set 5
5
del
4 doc
set AttributeError property 'ro' of 'D63' object has no setter
del AttributeError property 'ro' of 'D63' object has no deleter
get AttributeError property 'none' of 'D63' object has no getter
ro
```

### property, staticmethod and classmethod are classes; a property answers its parts, and setter makes a copy

```python
(python-run "class P64:\n    @property\n    def v(self):\n        return 1\n\n\np64 = P64.v\nq64 = p64.setter(len)\nprint(type(p64).__name__, isinstance(p64, property), p64.fget.__name__, p64.fset, q64.fset is len, q64 is p64)\nprint(type(staticmethod(len)).__name__, type(classmethod(len)).__name__, staticmethod(len).__func__ is len)\ntry:\n    property(1, 2, 3, 4, 5)\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
property True v None True False
staticmethod classmethod True
TypeError property() takes at most 4 arguments (5 given)
```
