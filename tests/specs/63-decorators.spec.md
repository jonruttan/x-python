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
