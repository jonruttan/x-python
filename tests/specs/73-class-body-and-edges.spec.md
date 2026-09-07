# a class body's other statements, and two small edges

### a class carries a docstring

```python
(python-run "class C:\n    \"a docstring\"\n    def f(self):\n        \"so does a method\"\n        return 1\nprint(C().f())\nclass D:\n    None\n    x = 1\nprint(D.x)")
```
---
```output
1
1
```

### an int in a bytes is a byte value

```python
(python-run "print(0 in b'1234', 49 in b'1234')\nprint(b'1' in b'1234', b'9' in b'1234')\nclass mybytes(bytes):\n    pass\nb = mybytes(b'1234')\nprint(0 in b, b'1' in b)")
```
---
```output
False True
True False
False True
```

### StopIteration carries a value

```python
(python-run "print(StopIteration().value)\nprint(StopIteration(\"x\").value)\nclass MyStop(StopIteration):\n    pass\nprint(MyStop().value, MyStop(\"y\").value)")
```
---
```output
None
x
None y
```
