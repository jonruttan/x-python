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
