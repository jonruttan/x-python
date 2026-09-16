# the io module

### a text stream: written over, read back, closed by `with`

```python
(python-run "import io\na = io.StringIO()\nprint('io.StringIO' in repr(a), a.tell(), repr(a.getvalue()), repr(a.read()))\na = io.StringIO(\"foobar\")\nprint(a.getvalue(), a.read(), repr(a.read()), a.tell())\na = io.StringIO(\"foobar\")\nprint(a.read(3), a.read(2), a.tell())\na = io.StringIO(\"foo\")\na.write(\"12\")\nprint(a.getvalue(), a.tell())\na = io.StringIO(\"foo\")\na.write(\"1234\")\nprint(a.getvalue(), a.tell())\na = io.StringIO()\na.write(\"foo\")\nprint(repr(a.read()), a.tell(), a.seek(0), a.read())\nwith io.StringIO() as b:\n    b.write(\"foo\")\n    print(b.getvalue())\n")
```
---
```output
True 0 '' ''
foobar foobar '' 6
foo ba 5
12o 2
1234 4
'' 3 0 foo
foo
```

### a byte stream: seeking past the end, reading into a bytearray

```python
(python-run "import io\na = io.BytesIO(b\"foobar\")\na.seek(10)\nprint(a.read(10))\na = io.BytesIO()\nprint(a.seek(8))\na.write(b\"123\")\nprint(a.getvalue())\nprint(a.seek(0, 1), a.seek(-1, 2))\na.write(b\"0\")\nprint(a.getvalue())\na.flush()\na.seek(0)\narr = bytearray(10)\nprint(a.readinto(arr), arr)\nb = b\"foobar\"\nc = io.BytesIO(b)\nc.write(b\"1\")\nprint(b, c.getvalue())\nd = bytearray(b\"foobar\")\ne = io.BytesIO(d)\ne.write(b\"1\")\nprint(d, e.getvalue())\n")
```
---
```output
b''
8
b'\x00\x00\x00\x00\x00\x00\x00\x00123'
11 10
b'\x00\x00\x00\x00\x00\x00\x00\x00120'
10 bytearray(b'\x00\x00\x00\x00\x00\x00\x00\x0012')
b'foobar' b'1oobar'
bytearray(b'foobar') b'1oobar'
```

### lines, one at a time and by iteration, on a stream and on a subclass

```python
(python-run "import io\na = io.StringIO()\na.write(\"hello\\nworld\\ntail\")\na.seek(0)\nprint(repr(a.readline()), repr(a.readline()))\nfor line in a:\n    print(repr(line))\nprint(a.tell())\n\nclass X(io.StringIO):\n    pass\n\nb = X()\nb.write(\"one\\ntwo\\n\")\nb.seek(0)\nfor line in b:\n    print(repr(line))\nprint(b.getvalue() == \"one\\ntwo\\n\", b.tell())\n")
```
---
```output
'hello\n' 'world\n'
'tail'
16
'one\n'
'two\n'
True 8
```

### print(..., file=x) writes one piece at a time

```python
(python-run "import io\n\nclass MyIO(io.IOBase):\n    def write(self, buf):\n        print('write', len(buf))\n        return len(buf)\n\nprint('test', file=MyIO())\nprint('a', 'b', sep='-', end='!\\n', file=MyIO())\ns = io.StringIO()\nprint('one', 2, file=s)\nprint('two', file=s, end='')\nprint(repr(s.getvalue()))\nprint('flushed', flush=True)\nprint('none', file=None)\n")
```
---
```output
write 4
write 1
write 1
write 1
write 1
write 2
'one 2\ntwo'
flushed
none
```

### a closed stream, the wrong kind of value, and what the module names

```python
(python-run "import io\na = io.StringIO()\na.close()\nfor f in [a.read, a.getvalue, lambda: a.write(\"\")]:\n    try:\n        f()\n        print(\"no error\")\n    except ValueError as e:\n        print('ValueError', e)\nb = io.BytesIO()\ntry:\n    b.write(\"text\")\nexcept TypeError:\n    print('TypeError')\nc = io.StringIO()\ntry:\n    c.write(b\"bytes\")\nexcept TypeError:\n    print('TypeError')\nprint(type(io.StringIO()).__name__, type(io.BytesIO()).__name__)\nprint(io.StringIO.__name__, io.BytesIO.__name__, io.IOBase.__name__)\nprint(isinstance(io.StringIO(), io.IOBase), issubclass(io.BytesIO, io.IOBase))\n")
```
---
```output
ValueError I/O operation on closed file
ValueError I/O operation on closed file
ValueError I/O operation on closed file
TypeError
TypeError
StringIO BytesIO
StringIO BytesIO IOBase
True True
```
