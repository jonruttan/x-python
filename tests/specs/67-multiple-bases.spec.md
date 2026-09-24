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

### two builtin bases conflict unless one derives from the other

```python
(python-run "def attempt67(label, make):\n    try:\n        make()\n        print(label, \"ok\")\n    except TypeError as e:\n        print(label, \"TypeError\", e)\n\n\nclass L67(list):\n    pass\n\n\nclass I67(int):\n    pass\n\n\nclass T67(type):\n    pass\n\n\nattempt67(\"type, tuple\", lambda: type(\"A\", (type, tuple), {}))\nattempt67(\"int, str\", lambda: type(\"B\", (int, str), {}))\nattempt67(\"list, dict\", lambda: type(\"C\", (list, dict), {}))\nattempt67(\"int subclass, str\", lambda: type(\"D\", (I67, str), {}))\nattempt67(\"type subclass, int\", lambda: type(\"E\", (T67, int), {}))\nattempt67(\"list subclass, list\", lambda: type(\"F\", (L67, list), {}))\nattempt67(\"list, object\", lambda: type(\"G\", (list, object), {}))")
```
---
```output
type, tuple TypeError multiple bases have instance lay-out conflict
int, str TypeError multiple bases have instance lay-out conflict
list, dict TypeError multiple bases have instance lay-out conflict
int subclass, str TypeError multiple bases have instance lay-out conflict
type subclass, int TypeError multiple bases have instance lay-out conflict
list subclass, list ok
list, object ok
```
