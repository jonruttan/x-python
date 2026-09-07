# the item protocol's remaining edges

### empty parens is the same as no parens

```python
(python-run "class C():\n    def f(self): return 1\nclass D():\n    pass\nprint(C().f(), C.__bases__[0].__name__, D.__bases__[0].__name__)")
```
---
```output
1 object object
```

### the three item methods

```python
(python-run "class C:\n    def __getitem__(self, item):\n        print('get', item)\n        return 'item'\n    def __setitem__(self, item, value):\n        print('set', item, value)\n    def __delitem__(self, item):\n        print('del', item)\nc = C()\nprint(c[1])\nc[1] = 2\ndel c[3]")
```
---
```output
get 1
item
set 1 2
del 3
```

### a class without __delitem__ says so

```python
(python-run "class A:\n    pass\na = A()\ntry:\n    del a[1]\nexcept TypeError:\n    print('TypeError')\ntry:\n    a[1] = 2\nexcept TypeError:\n    print('TypeError')")
```
---
```output
TypeError
TypeError
```

### __init__ must answer None

```python
(python-run "class C3:\n    def __init__(self):\n        return 10\ntry:\n    C3()\nexcept TypeError as e:\n    print('TypeError')\nclass Ok:\n    def __init__(self):\n        self.x = 1\nprint(Ok().x)")
```
---
```output
TypeError
1
```

### NotImplemented can be hashed

```python
(python-run "print(type(hash(NotImplemented)))\nd = {NotImplemented: 'yes'}\nprint(d[NotImplemented])")
```
---
```output
<class 'int'>
yes
```
