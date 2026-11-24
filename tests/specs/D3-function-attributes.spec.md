# function attributes: what a function carries, and what a program stores on it

A def records its name, its docstring and the module it ran in; a program
may store any other attribute on a function, or replace those, and read it
back through `__dict__`. Each expected output is a python3.14 run of the
same program.

### a function stores, reads and deletes attributes, through __dict__ too

```python
(python-run "def f():\n    pass\nf.calls = 0\nf.calls += 1\nprint(f.calls, f.__dict__)\nf.__dict__[\"tag\"] = \"x\"\nprint(f.tag, sorted(f.__dict__))\ndel f.calls\nprint(hasattr(f, \"calls\"), f.__dict__, f.__dict__ is f.__dict__)\ntry:\n    f.missing\nexcept AttributeError as e:\n    print(\"AttributeError\", e)\ntry:\n    del f.missing\nexcept AttributeError as e:\n    print(\"AttributeError\", e)\ng = lambda: 0\ng.label = \"lam\"\nprint(g.label, g.__name__, getattr(g, \"nope\", \"default\"))")
```
---
```output
1 {'calls': 1}
x ['calls', 'tag']
False {'tag': 'x'} True
AttributeError 'function' object has no attribute 'missing'
AttributeError 'function' object has no attribute 'missing'
lam <lambda> default
```

### __doc__ is the def's docstring, and __name__ and __doc__ can be replaced

```python
(python-run "def documented(a):\n    \"\"\"Return a.\"\"\"\n    return a\ndef bare():\n    return 1\ndef fdoc():\n    f\"not {1} a docstring\"\ndef joined():\n    \"one\" \" two\"\ndef oneline(): \"short\"\nprint(documented.__doc__, bare.__doc__, fdoc.__doc__, joined.__doc__, oneline.__doc__)\nprint(documented.__name__, documented.__module__)\ndocumented.__name__ = \"renamed\"\ndocumented.__doc__ = \"changed\"\nprint(documented.__name__, documented.__doc__, documented(7))\nprint((lambda: 0).__doc__)")
```
---
```output
Return a. None None one two short
documented __main__
renamed changed 7
None
```

### a method forwards to its function, and a wrapper carries what it wraps

```python
(python-run "class C:\n    def m(self):\n        \"method doc\"\n        return 1\nC.m.tag = 5\nc = C()\nprint(c.m.__doc__, c.m.tag, c.m.__name__, C.m.__doc__)\ndef deco(fn):\n    def wrapper(*a):\n        return fn(*a)\n    wrapper.__wrapped__ = fn\n    wrapper.__name__ = fn.__name__\n    wrapper.__doc__ = fn.__doc__\n    return wrapper\n@deco\ndef area(w, h):\n    \"Area of a rectangle.\"\n    return w * h\nprint(area(2, 3), area.__name__, area.__doc__, area.__wrapped__(4, 5))\ndef counter():\n    counter.n = getattr(counter, \"n\", 0) + 1\n    return counter.n\ncounter(); counter()\nprint(counter())")
```
---
```output
method doc 5 m method doc
6 area Area of a rectangle. 20
3
```

### __globals__, __closure__ and __builtins__ are read-only, and setattr() sets the rest

```python
(python-run "def f():\n    return 1\nprint(f.__globals__ is globals())\nfor name in (\"__globals__\", \"__closure__\", \"__builtins__\"):\n    try:\n        setattr(f, name, None)\n    except AttributeError as e:\n        print(\"set\", name, e)\n    try:\n        delattr(f, name)\n    except AttributeError as e:\n        print(\"del\", name, e)\nsetattr(f, \"tag\", 7)\nprint(f.tag, getattr(f, \"tag\"), f())\n")
```
---
```output
True
set __globals__ readonly attribute
del __globals__ readonly attribute
set __closure__ readonly attribute
del __closure__ readonly attribute
set __builtins__ readonly attribute
del __builtins__ readonly attribute
7 7 1
```
