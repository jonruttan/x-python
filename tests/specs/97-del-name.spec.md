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

