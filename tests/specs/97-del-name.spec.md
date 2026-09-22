# del NAME

### a module-level name, gone and bound again

```python
(python-run "x = 1\nprint(x)\ndel x\ntry:\n    print(x)\nexcept NameError as e:\n    print(\"NameError\", e)\ntry:\n    del x\nexcept NameError:\n    print(\"NameError\")\nx = 5\nprint(x)\n")
```
---
```output
1
NameError name 'x' is not defined
NameError
5
```

### a local name

```python
(python-run "def f():\n    x = 1\n    y = 2\n    print(x, y)\n    del x\n    print(y)\n    try:\n        print(x)\n    except NameError:\n        print(\"NameError\")\n    try:\n        del x\n    except NameError:\n        print(\"NameError\")\nf()\n")
```
---
```output
1 2
2
NameError
NameError
```

### a global from a function, and grouped names

```python
(python-run "def do_del():\n    global g\n    del g\ng = 1\nprint(g)\ndo_del()\ntry:\n    print(g)\nexcept NameError:\n    print(\"NameError\")\na = 1\ndel (a,)\ntry:\n    print(a)\nexcept NameError:\n    print(\"NameError\")\na = 2\nb = 3\nc = 4\ndel (a, (b, c))\ntry:\n    print(a)\nexcept NameError:\n    print(\"NameError\")\ntry:\n    print(b)\nexcept NameError:\n    print(\"NameError\")\ntry:\n    print(c)\nexcept NameError:\n    print(\"NameError\")\np = 1\nq = 2\ndel p, q\ntry:\n    print(p)\nexcept NameError:\n    print(\"NameError\")\n")
```
---
```output
1
NameError
NameError
NameError
NameError
NameError
NameError
```

### a name the enclosing function owns

```python
(python-run "def f():\n    x = 1\n    y = 2\n    def h():\n        nonlocal x\n        print(y)\n        try:\n            del x\n        except NameError:\n            print(\"NameError\")\n    print(x, y)\n    del x\n    h()\nf()\n")
```
---
```output
1 2
2
NameError
```


# del a target list

### a list of targets, nested and mixed

```python
(python-run "class C:\n    pass\n\n\nc = C()\nc.p = 1\nx = [1, 2, 3]\nd = {\"k\": 1, \"j\": 2}\na = b = 1\ndel x[0], (a, [b]), c.p, d[\"k\"]\nprint(x, d, hasattr(c, \"p\"))\ntry:\n    print(a)\nexcept NameError as e:\n    print(\"NameError\", e)")
```
---
```output
[2, 3] {'j': 2} False
NameError name 'a' is not defined
```

### slices in a del list

```python
(python-run "x = [0, 1, 2, 3, 4, 5]\ny = 1\ndel x[1:3], (y, x[-2:])\nprint(x)\ntry:\n    print(y)\nexcept NameError as e:\n    print(\"NameError\", e)")
```
---
```output
[0, 3]
NameError name 'y' is not defined
```

### `del ()` deletes nothing, and a starred target is refused

```python
(python-run "del ()\ndel []\nprint(\"ok\")\ntry:\n    exec(\"a = [1]\\ndel *a,\")\nexcept SyntaxError as e:\n    print(\"SyntaxError\", str(e).split(\" (\")[0])")
```
---
```output
ok
SyntaxError cannot delete starred
```

### a star alone, two names, a literal, a call, and nothing are refused

```python
(python-run "for src in (\"del *\", \"del [*]\", \"del a b\", \"del 1\", \"del f()\", \"del\"):\n    try:\n        exec(src)\n    except SyntaxError:\n        print(\"SyntaxError\")")
```
---
```output
SyntaxError
SyntaxError
SyntaxError
SyntaxError
SyntaxError
SyntaxError
```
