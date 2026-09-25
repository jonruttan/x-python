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

### a class body reads what it has bound, in order, and the scope around it after

```python
(python-run "class N73:\n    a = 1\n    b = a + 1\n    a = 10\n    c = a * 2\n    \"a bare expression runs too\"\n    n = 0\n    n = n + 1\nprint(N73.a, N73.b, N73.c, N73.n, [k for k in N73.__dict__ if not k.startswith(\"__\")])\nx73 = \"global\"\n\n\nclass M73:\n    y = x73\n    x73 = \"class\"\n    z = x73\n\n\ndef outer73():\n    w = \"closure\"\n\n    class Inner:\n        v = w\n        w2 = v + \"!\"\n    return Inner.v, Inner.w2\n\n\nprint(M73.y, M73.z, x73, outer73())")
```
---
```output
10 2 20 1 ['a', 'b', 'c', 'n']
global class global ('closure', 'closure!')
```

### a class body's functions and lambdas do not see its names; its decorators and a comprehension's source do

```python
(python-run "y74 = \"global\"\n\n\nclass P74:\n    y74 = \"class\"\n\n    def f(self):\n        return y74\n\n    g = lambda self: y74\n\n    def deco(f):\n        return lambda self: \"deco:\" + f(self)\n\n    @deco\n    def m(self):\n        return \"m\"\n\n    len = 5\n    k = len\n    xs = [1, 2]\n    ys = [v * 2 for v in xs]\n    print(\"in body\", deco.__name__)\nprint(P74().f(), P74().g(), P74().m(), P74.k, len(\"ab\"), P74.ys)")
```
---
```output
in body deco
global global deco:m 5 2 [2, 4]
```
