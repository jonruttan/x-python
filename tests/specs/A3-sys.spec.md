# the sys module

### the standard streams: what they are called, and where a write goes

```python
(python-run "import sys\nfor s in (sys.stdout, sys.stderr, sys.stdin):\n    print(repr(s), type(s).__name__, str(type(s)))\n    print(repr(s.buffer), type(s.buffer).__name__)\n    print(s.name, s.mode, s.encoding, s.fileno(), s.buffer.name, s.buffer.mode, s.buffer.fileno())\nprint(sys.stdout.write(\"written\\n\"))\nn = sys.stderr.write(\"to stderr\\n\")\nprint(n)\nprint(\"printed to stdout\", file=sys.stdout)\nprint(\"printed to stderr\", file=sys.stderr)\nsys.stdout.flush()\n")
```
---
```output
<_io.TextIOWrapper name='<stdout>' mode='w' encoding='utf-8'> TextIOWrapper <class '_io.TextIOWrapper'>
<_io.BufferedWriter name='<stdout>'> BufferedWriter
<stdout> w utf-8 1 <stdout> wb 1
<_io.TextIOWrapper name='<stderr>' mode='w' encoding='utf-8'> TextIOWrapper <class '_io.TextIOWrapper'>
<_io.BufferedWriter name='<stderr>'> BufferedWriter
<stderr> w utf-8 2 <stderr> wb 2
<_io.TextIOWrapper name='<stdin>' mode='r' encoding='utf-8'> TextIOWrapper <class '_io.TextIOWrapper'>
<_io.BufferedReader name='<stdin>'> BufferedReader
<stdin> r utf-8 0 <stdin> rb 0
written
8
10
printed to stdout
```

### the wrong kind of value, and a write to the stream that reads

```python
(python-run "import sys, io\ntry:\n    sys.stdout.write(5)\nexcept TypeError as e:\n    print(\"TypeError\", e)\ntry:\n    sys.stdout.buffer.write(\"text\")\nexcept TypeError as e:\n    print(\"TypeError\", e)\ntry:\n    sys.stdin.write(\"x\")\nexcept OSError as e:\n    print(type(e).__name__, e, isinstance(e, ValueError), isinstance(e, io.UnsupportedOperation))\n")
```
---
```output
TypeError write() argument must be str, not int
TypeError a bytes-like object is required, not 'str'
UnsupportedOperation not writable True True
```

### bytes through a stream's buffer

```python
(python-run "import sys\nprint(\"text first\")\nsys.stdout.flush()\nsys.stdout.buffer.write(b\"bytes after\\n\")\n")
```
---
```output
text first
bytes after
```

### version_info and hexversion

```python
(python-run "import sys\nv = sys.version_info\nprint(repr(v)[:24], type(v).__name__, str(type(v)))\nprint(v.major, v.minor >= 0, v.releaselevel, v.serial, len(v), v[0] == v.major)\nprint(v >= (3, 0), v < (4,), v[:2] == (v.major, v.minor), tuple(v)[3:])\nprint(sys.version.startswith(\"%d.%d.\" % v[:2]), sys.version[:2])\nprint(hex(sys.hexversion)[:4], sys.hexversion >> 24 == v.major, sys.hexversion >> 16 & 255 == v.minor)\n")
```
---
```output
sys.version_info(major=3 version_info <class 'sys.version_info'>
3 True final 0 5 True
True True True ('final', 0)
True 3.
0x30 True True
```

### sys.implementation is a namespace, with a version of its own

```python
(python-run "import sys, types\nimpl = sys.implementation\nprint(type(impl) is types.SimpleNamespace, type(impl.name).__name__, hasattr(impl, \"cache_tag\"))\nprint(str(impl).startswith(\"namespace(name=\"), \"version=\" in str(impl), \"hexversion=\" in repr(impl))\nprint(type(impl.version) is type(sys.version_info), len(impl.version), type(impl.version.major).__name__)\nprint(type(impl.hexversion).__name__, impl.hexversion >> 24 == impl.version.major)\n")
```
---
```output
True str True
True True True
True 5 int
int True
```

### types.SimpleNamespace

```python
(python-run "import types\nns = types.SimpleNamespace(a=1, b=\"two\")\nprint(ns, repr(ns), ns.a, ns.b)\nns.c = [3]\ndel ns.a\nprint(ns)\nprint(types.SimpleNamespace() == types.SimpleNamespace(), types.SimpleNamespace(x=1) == types.SimpleNamespace(x=1), types.SimpleNamespace(x=1) == types.SimpleNamespace(x=2))\nprint(types.SimpleNamespace(x=1, y=2) == types.SimpleNamespace(y=2, x=1), types.SimpleNamespace(x=1) != types.SimpleNamespace(x=1))\nclass Sub(types.SimpleNamespace):\n    pass\nprint(Sub(q=1), isinstance(Sub(), types.SimpleNamespace))\nprint(types.SimpleNamespace({\"k\": 5}, j=6))\nprint(types.SimpleNamespace({\"k\": 5}), types.SimpleNamespace())\ntry:\n    ns.zz\nexcept AttributeError:\n    print(\"AttributeError\")\n")
```
---
```output
namespace(a=1, b='two') namespace(a=1, b='two') 1 two
namespace(b='two', c=[3])
True True False
True False
Sub(q=1) True
namespace(k=5, j=6)
namespace(k=5) namespace()
AttributeError
```

### a module's __dict__

```python
(python-run "import sys, types\nd = sys.__dict__\nprint(type(d).__name__, d[\"__name__\"], \"version\" in d, d[\"maxsize\"] == sys.maxsize)\nprint(types.__dict__[\"SimpleNamespace\"] is types.SimpleNamespace, hasattr(sys, \"__dict__\"))\n")
```
---
```output
dict sys True True
True True
```

### getsizeof

```python
(python-run "import sys\nprint(sys.getsizeof([1, 2]) >= 2, sys.getsizeof({1: 2}) >= 2, sys.getsizeof(0) > 0)\nprint(sys.getsizeof([1, 2, 3]) > sys.getsizeof([1]), sys.getsizeof(\"abcdef\") > sys.getsizeof(\"a\"))\nprint(type(sys.getsizeof(None)).__name__, sys.getsizeof(1, -1) > 0)\nclass A:\n    pass\nprint(sys.getsizeof(A()) > 0)\n")
```
---
```output
True True True
True True
int True
True
```

### a subclass of list or tuple slices as the builtin does

```python
(python-run "class L(list):\n    pass\nclass T(tuple):\n    pass\nl = L([1, 2, 3, 4])\nt = T((1, 2, 3))\nprint(l[1:3], type(l[1:3]).__name__, t[::-1], type(t[:1]).__name__)\nprint(l[:], l[::2], t[5:], t[-2:])\n")
```
---
```output
[2, 3] list (3, 2, 1) tuple
[1, 2, 3, 4] [1, 3] () (2, 3)
```
