# copy: shallow and deep copying

`stdlib/copy.py`. Each expected output is a python3.14 run of the same
program.

### atoms come back as they are; containers are copied, shallow or deep

```python
(python-run "import copy\nfor v in (None, 1, 2.5, \"s\", b\"b\", (1, 2), frozenset({1}), range(3), len, copy.copy, int):\n    print(type(v).__name__, copy.copy(v) is v, copy.deepcopy(v) is v)\na = [1, [2, 3], {\"k\": [4]}]\ns = copy.copy(a)\nd = copy.deepcopy(a)\nprint(s == a, s is a, s[1] is a[1], d == a, d[1] is a[1], d[2][\"k\"] is a[2][\"k\"])\nfor v in ({1: [2]}, {1, 2}, bytearray(b\"xy\")):\n    c = copy.copy(v)\n    print(type(c).__name__, c == v, c is v)\nt = (1, [2])\nprint(copy.deepcopy(t) is t, copy.deepcopy(t) == t, copy.deepcopy((1, \"a\")) is not None)\nprint(copy.deepcopy((1, \"a\", (2,))) == (1, \"a\", (2,)))\n")
```
---
```output
NoneType True True
int True True
float True True
str True True
bytes True True
tuple True True
frozenset True False
range True True
builtin_function_or_method True True
function True True
type True True
True False True True False False
dict True False
set True False
bytearray True False
False True True
True
```

### deepcopy copies a shared object once, and a cycle as a cycle

```python
(python-run "import copy\na = [1]\na.append(a)\nb = copy.deepcopy(a)\nprint(b[1] is b, b is not a, len(b))\nshared = [0]\npair = [shared, shared]\nc = copy.deepcopy(pair)\nprint(c[0] is c[1], c[0] is not shared)\nd = {}\nd[\"self\"] = d\ne = copy.deepcopy(d)\nprint(e[\"self\"] is e)\nmemo = {}\nx = [1, 2]\ny = copy.deepcopy(x, memo)\nprint(memo[id(x)] is y, copy.deepcopy(x, memo) is y, id(memo) in memo)\n")
```
---
```output
True True 2
True True
True
True True True
```

### instances, and the methods a class controls its copies with

```python
(python-run "import copy\nclass P:\n    def __init__(self, x, items):\n        self.x = x\n        self.items = items\np = P(1, [1, 2])\ns = copy.copy(p)\nd = copy.deepcopy(p)\nprint(type(s).__name__, s is p, s.x, s.items is p.items, d.items == p.items, d.items is p.items)\nclass Q:\n    pass\nprint(copy.copy(Q()).__dict__, type(copy.deepcopy(Q())).__name__)\nclass C:\n    def __init__(self): self.log = []\n    def __copy__(self):\n        self.log.append(\"copy\"); return \"shallow\"\n    def __deepcopy__(self, memo):\n        self.log.append(\"deep \" + str(type(memo).__name__)); return \"deep\"\nc = C()\nprint(copy.copy(c), copy.deepcopy(c), c.log)\nclass St:\n    def __init__(self): self.a = 1; self.b = 2\n    def __getstate__(self): return {\"a\": self.a}\n    def __setstate__(self, state):\n        self.__dict__.update(state); self.restored = True\ns2 = copy.copy(St())\nprint(sorted(vars(s2).items()))\nclass NA:\n    def __new__(cls, n):\n        o = object.__new__(cls); o.n = n; return o\n    def __getnewargs__(self): return (self.n * 10,)\nprint(copy.copy(NA(4)).n, copy.deepcopy(NA(5)).n)\nclass R:\n    def __init__(self, v): self.v = v\n    def __reduce__(self): return (R, (self.v + 1,))\nprint(copy.copy(R(1)).v, copy.deepcopy(R([1])).v if False else copy.deepcopy(R(2)).v)\nclass G:\n    def __reduce__(self): return \"G\"\ng = G()\nprint(copy.copy(g) is g, copy.deepcopy(g) is g)\n")
```
---
```output
P False 1 True True False
{} Q
shallow deep ['copy', 'deep dict']
[('a', 1), ('restored', True)]
4 5
2 3
True True
```

### bound methods, and a class with slots

```python
(python-run "import copy\nclass Obj:\n    def __init__(self): self.v = 3\n    def get(self): return self.v\no = Obj()\nbm = copy.deepcopy(o.get)\no.v = 4\nprint(bm(), o.get(), copy.copy(o.get)())\nholder = Obj()\nholder.cb = holder.get\nh2 = copy.deepcopy(holder)\nholder.v = 5\nprint(h2.cb(), h2.cb.__self__ is h2)\nclass Slots:\n    __slots__ = (\"x\", \"y\")\n    def __init__(self): self.x = 1\nsl = copy.copy(Slots())\nprint(sl.x, hasattr(sl, \"y\"))\n")
```
---
```output
3 4 4
3 True
1 False
```

### replace, and what can't be copied

```python
(python-run "import copy\nfrom collections import namedtuple\nPt = namedtuple(\"Pt\", \"x y\")\nprint(copy.replace(Pt(1, 2), y=5))\nclass V:\n    def __init__(self, a, b): self.a = a; self.b = b\n    def __replace__(self, **ch):\n        return V(ch.get(\"a\", self.a), ch.get(\"b\", self.b))\nv = copy.replace(V(1, 2), b=9)\nprint(v.a, v.b)\nfor args in ((), (1,), (1, 2)):\n    try:\n        copy.replace(*args)\n    except TypeError as e:\n        print(\"TypeError\", e)\ndef gen():\n    yield 1\ntry:\n    copy.copy(gen())\nexcept TypeError as e:\n    print(\"TypeError\", e)\nprint(issubclass(copy.Error, Exception), copy.error is copy.Error, sorted(copy.__all__))\n")
```
---
```output
Pt(x=1, y=5)
1 9
TypeError replace() missing 1 required positional argument: 'obj'
TypeError replace() does not support int objects
TypeError replace() takes 1 positional argument but 2 were given
TypeError cannot pickle 'generator' object
True True ['Error', 'copy', 'deepcopy', 'replace']
```

### subclasses of list, dict and tuple

```python
(python-run "import copy\nclass L(list):\n    pass\nl = L([1, [2]]); l.tag = \"t\"\nm = copy.copy(l)\nn = copy.deepcopy(l)\nprint(type(m).__name__, m, m.tag, m[1] is l[1], type(n).__name__, n, n[1] is l[1], n.tag)\nclass D(dict):\n    pass\ndd = D(a=[1])\ne = copy.copy(dd)\nf = copy.deepcopy(dd)\nprint(type(e).__name__, e, e[\"a\"] is dd[\"a\"], type(f).__name__, f[\"a\"] is dd[\"a\"])\nclass T(tuple):\n    pass\nt = copy.deepcopy(T((1, [2])))\nprint(type(t).__name__, t)\n")
```
---
```output
L [1, [2]] t True L [1, [2]] False t
D {'a': [1]} True D False
T (1, [2])
```

### __new__ makes a builtin subclass's instance, value and all

```python
(python-run "class L(list):\n    def __init__(self, *a):\n        raise AssertionError(\"__new__ alone runs no __init__\")\nm = L.__new__(L)\nm.extend([1, 2])\nprint(type(m).__name__, m, isinstance(m, list))\nclass D(dict):\n    pass\nd = D.__new__(D)\nd[\"k\"] = 1\nprint(type(d).__name__, d)\nclass T(tuple):\n    pass\nprint(type(T.__new__(T, (1, 2))).__name__, T.__new__(T, (1, 2)), T.__new__(T))\nclass Twice(tuple):\n    def __new__(cls, x):\n        return super().__new__(cls, (x, x))\nprint(Twice(3))\nprint(T(c for c in \"ab\"), L.__new__(L) == [])\n")
```
---
```output
L [1, 2] True
D {'k': 1}
T (1, 2) ()
(3, 3)
('a', 'b') True
```
