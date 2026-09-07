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
