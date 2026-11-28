# weakref: weak references and finalizers

`stdlib/weakref.py`, on the weak cell in `lib/python/_weakref.x`. Each expected
output is a python3.15 run of the same program, its stdout: a callback that
raises reports on stderr.

### ref answers its object until a collect takes it, then None, and calls its callback with itself

```python
(python-run "import weakref, gc\nclass A:\n    def __str__(self):\n        return \"<A>\"\nfor v in (None, True, 0, 1.5, \"s\", b\"b\", (), [], {}):\n    try:\n        weakref.ref(v)\n    except TypeError as e:\n        print(type(v).__name__, e)\ndef cb(r):\n    print(\"callback\", r(), type(r).__name__)\ndef test():\n    a = A()\n    r = weakref.ref(a, cb)\n    print(r(), r() is a, r.__callback__ is cb, weakref.getweakrefcount(a), weakref.getweakrefs(a) == [r])\n    a = None\n    gc.collect()\n    print(r())\n    b = A()\n    r2 = weakref.ref(b, cb)\n    r2 = None\n    gc.collect()\n    b = None\n    gc.collect()\n    print(\"no callback for a ref that died first\")\ntest()\nprint(weakref.ReferenceType is weakref.ref, isinstance(weakref.ref(A()), weakref.ref))\n")
```
---
```output
NoneType cannot create weak reference to 'NoneType' object
bool cannot create weak reference to 'bool' object
int cannot create weak reference to 'int' object
float cannot create weak reference to 'float' object
str cannot create weak reference to 'str' object
bytes cannot create weak reference to 'bytes' object
tuple cannot create weak reference to 'tuple' object
list cannot create weak reference to 'list' object
dict cannot create weak reference to 'dict' object
<A> True True 1 True
callback None ReferenceType
None
no callback for a ref that died first
True True
```

### refs and finalizers on one object are called newest first

```python
(python-run "import weakref, gc\nclass A:\n    pass\ndef test():\n    a = A()\n    r1 = weakref.ref(a, lambda r: print(\"ref1\", r()))\n    f1 = weakref.finalize(a, lambda: print(\"finalize1\"))\n    r2 = weakref.ref(a, lambda r: print(\"ref2\", r()))\n    f2 = weakref.finalize(a, print, \"finalize2\", \"with\", \"args\")\n    print(r1() is a, f1.alive, r2() is a, f2.alive)\n    a = None\n    gc.collect()\n    print(r1(), f1.alive, r2(), f2.alive)\ntest()\n")
```
---
```output
True True True True
finalize2 with args
ref2 None
finalize1
ref1 None
None False None False
```

### finalize: alive, peek, detach and call, and a callback that raises

```python
(python-run "import weakref, gc\nclass A:\n    pass\ndef show(t):\n    return None if t is None else (type(t[0]).__name__, t[2], t[3])\na = A()\nf = weakref.finalize(a, lambda *args, **kwargs: (args, kwargs), 1, 2, k=3)\nprint(f.alive, show(f.peek()))\nprint(f(), f.alive, f.peek(), f(), f.detach())\ng = weakref.finalize(a, print, \"never\")\nprint(show(g.detach()), g.alive, g())\ndef test():\n    b = A()\n    weakref.finalize(b, lambda: 1 / 0)\n    weakref.finalize(b, print, \"finalized\")\n    b = None\n    gc.collect()\n    print(\"collect done\")\ntest()\nprint((lambda a, *r, b=1, **kw: (a, r, b, kw))(1, 2, b=3, c=4), (lambda **kw: kw)(x=1))\n")
```
---
```output
True ('A', (1, 2), {'k': 3})
((1, 2), {'k': 3}) False None None None
('A', ('never',), {}) False None
finalized
collect done
(1, (2,), 3, {'c': 4}) {'x': 1}
```
