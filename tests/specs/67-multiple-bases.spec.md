# more than one base

### two bases, and the leftmost method wins

```python
(python-run "class A:\n    def __init__(self, x):\n        print('A init', x)\n        self.x = x\n    def f(self):\n        print(self.x)\n    def f2(self):\n        print(self.x)\nclass B:\n    def __init__(self, x):\n        print('B init', x)\n        self.x = x\n    def f(self):\n        print(self.x)\n    def f3(self):\n        print(self.x)\nclass Sub(A, B):\n    def __init__(self):\n        A.__init__(self, 1)\n        B.__init__(self, 2)\n        print('Sub init')\n    def g(self):\n        print(self.x)\nprint(issubclass(Sub, A))\nprint(issubclass(Sub, B))\no = Sub()\nprint(o.x)\no.f()\no.f2()\no.f3()")
```
---
```output
True
True
A init 1
B init 2
Sub init
2
2
2
2
```

### __bases__ carries every base

```python
(python-run "class A: pass\nclass B(object): pass\nclass C(B): pass\nclass D(C, A): pass\nprint(len(A.__bases__), len(D.__bases__))\nprint(type(D.__bases__) == tuple)\nprint(D.__bases__[0].__name__, D.__bases__[1].__name__)\nprint(A.__bases__[0] is object, C.__bases__[0] is B)")
```
---
```output
1 2
True
C A
True True
```

### isinstance sees every base

```python
(python-run "class A: pass\nclass B: pass\nclass Sub(A, B): pass\ns = Sub()\nprint(isinstance(s, A), isinstance(s, B), isinstance(s, Sub), isinstance(s, object))\nclass Other: pass\nprint(isinstance(s, Other))")
```
---
```output
True True True True
False
```

### a bad base among good ones still raises

```python
(python-run "class A: pass\ntry:\n    class Bad(A, nosuch):\n        pass\nexcept (NameError, TypeError):\n    print(\"raised\")")
```
---
```output
raised
```
