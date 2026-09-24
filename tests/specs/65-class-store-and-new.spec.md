# a class takes a store, and __new__ makes the instance

### a store on the class is seen by every instance

```python
(python-run "class C:\n    pass\nc = C()\nc.x = 1\nprint(c.x)\nC.x = 2\nC.y = 3\nprint(c.x, c.y)\nprint(C.x, C.y)\nprint(C().x, C().y)\nc = C()\nprint(c.x)\nc.x = 4\nprint(c.x)")
```
---
```output
1
1 3
2 3
2 3
2
4
```

### a class attribute reaches a subclass

```python
(python-run "class A:\n    pass\nclass B(A):\n    pass\nA.tag = \"from A\"\nprint(B.tag, B().tag)\nB.tag = \"from B\"\nprint(A.tag, B.tag)")
```
---
```output
from A from A
from A from B
```

### a method can be added after the class is made

```python
(python-run "class C:\n    pass\ndef greet(self):\n    return \"hi\"\nC.greet = greet\nprint(C().greet())")
```
---
```output
hi
```

### __new__ runs before __init__

```python
(python-run "class C:\n    def __new__(cls):\n        print(\"new\")\n        return super().__new__(cls)\n    def __init__(self):\n        print(\"init\")\n        self.made = True\nc = C()\nprint(c.made)")
```
---
```output
new
init
True
```

### __new__ can answer something else, and then __init__ is skipped

```python
(python-run "class C:\n    def __new__(cls):\n        return \"not an instance\"\n    def __init__(self):\n        print(\"init should not run\")\nprint(C())")
```
---
```output
not an instance
```

### __new__ sees the arguments too

```python
(python-run "class Point:\n    def __new__(cls, x, y):\n        print(\"new\", x, y)\n        return super().__new__(cls)\n    def __init__(self, x, y):\n        self.x = x\n        self.y = y\n    def __repr__(self):\n        return f\"Point({self.x}, {self.y})\"\nprint(Point(1, 2))")
```
---
```output
new 1 2
Point(1, 2)
```

### a subclass inherits __new__

```python
(python-run "class Base:\n    def __new__(cls):\n        print(\"Base.__new__ for\", cls.__name__)\n        return super().__new__(cls)\nclass Sub(Base):\n    pass\ns = Sub()\nprint(type(s).__name__)")
```
---
```output
Base.__new__ for Sub
Sub
```

### object.__new__ refuses a non-class and a builtin class

```python
(python-run "class Foo65:\n    def __new__(cls):\n        print(\"in __new__\")\n        raise RuntimeError\n\n    def __init__(self):\n        self.attr = \"something\"\n\n\no65 = object.__new__(Foo65)\nprint(hasattr(o65, \"attr\"), isinstance(o65, Foo65))\no65.__init__()\nprint(o65.attr, type(object.__new__(object)).__name__)\n\n\nclass BadInit65:\n    def __init__(self):\n        return 10\n\n\nfor label, th in ((\"1\", lambda: object.__new__(1)), (\"None\", lambda: object.__new__(None)),\n                  (\"int\", lambda: object.__new__(int)), (\"list\", lambda: object.__new__(list)),\n                  (\"empty\", lambda: object.__new__()), (\"init\", lambda: BadInit65())):\n    try:\n        print(label, th())\n    except TypeError as e:\n        print(label, \"TypeError\", e)")
```
---
```output
False True
something object
1 TypeError object.__new__(X): X is not a type object (int)
None TypeError object.__new__(X): X is not a type object (NoneType)
int TypeError object.__new__(int) is not safe, use int.__new__()
list TypeError object.__new__(list) is not safe, use list.__new__()
empty TypeError object.__new__(): not enough arguments
init TypeError __init__() should return None, not 'int'
```
