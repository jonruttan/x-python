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

## files

`open` opens a file to read and reads nothing: what is asked of the file is
read from its descriptor a chunk of 8192 bytes at a time -- the text the bytes
decode to, with `\r\n` and a lone `\r` read as `\n`, or with a `b` in the
mode the bytes themselves.  A relative path is the working directory's, which
is the bundle's root here.

### a text file reads as the text its bytes decode to, each line ending \n

```python
(python-run "f = open(\"tests/modules/data/text.txt\", encoding=\"utf-8\")\nprint(repr(f.readline()))\nprint(repr(f.read(3)))\nprint(repr(f.read()))\nf.close()\nprint(f.closed)")
```
---
```output
'first line\n'
'sec'
'ond été π\nthird\n'
True
```

### with, iteration, readlines and the binary mode

```python
(python-run "with open(\"tests/modules/data/text.txt\", \"rb\") as f:\n    data = f.read()\nprint(data[:7], len(data))\nwith open(\"tests/modules/data/text.txt\") as f:\n    print([len(line) for line in f])\nwith open(\"tests/modules/data/text.txt\", mode=\"rt\") as f:\n    print(f.readlines()[-1])")
```
---
```output
b'first l' 34
[11, 13, 6]
third

```

### a file names what it was opened as, and refuses what it cannot do

```python
(python-run "f = open(\"tests/modules/data/text.txt\", encoding=\"utf-8\")\nprint(f.name, f.mode, f.encoding, type(f).__name__, f.readable(), f.writable())\ntry:\n    f.write(\"x\")\nexcept OSError as e:\n    print(type(e).__name__, e)\ntry:\n    open(\"tests/modules/data/none.txt\")\nexcept FileNotFoundError as e:\n    print(type(e).__name__, e.errno, e)\ntry:\n    open(\"tests/modules/data/bad.txt\").read()\nexcept UnicodeError as e:\n    print(type(e).__name__)\nfor mode in (\"rbt\", \"q\"):\n    try:\n        open(\"tests/modules/data/text.txt\", mode)\n    except ValueError as e:\n        print(\"ValueError\", e)")
```
---
```output
tests/modules/data/text.txt r utf-8 TextIOWrapper True False
UnsupportedOperation not writable
FileNotFoundError 2 [Errno 2] No such file or directory: 'tests/modules/data/none.txt'
UnicodeDecodeError
ValueError can't have text and binary mode at once
ValueError invalid mode: 'q'
```

### a read that spans chunks, a sequence and a line ending split between them

```python
(python-run "f = open(\"tests/modules/data/long.txt\", encoding=\"utf-8\")\ns = f.read()\nprint(len(s), s[8190:8193], repr(s[-6:]), f.tell() > 0)\nf.close()\nwith open(\"tests/modules/data/long.txt\") as f:\n    print([len(line) for line in f])\nwith open(\"tests/modules/data/long.txt\", \"rb\") as f:\n    print(f.read(3), f.seek(8190), f.read(4), f.seek(-5, 2), f.read(), f.tell())")
```
---
```output
16387 aéb 'b\nend\n' True
[16383, 4]
b'aaa' 8190 b'a\xc3\xa9b' 16384 b'\nend\n' 16389
```

### a file is read as far as it is asked, a line at a time in a loop

```python
(python-run "f = open(\"/dev/zero\", \"rb\")\nprint(f.read(4), f.closed)\nf.close()\nprint(f.closed)\nf = open(\"tests/modules/data/text.txt\", encoding=\"utf-8\")\nfor line in f:\n    print(repr(line))\n    break\nprint(repr(next(f)), iter(f) is f, isinstance(f.fileno(), int))\nprint(repr(f.readline()), repr(f.readline()), repr(next(f, \"done\")))\nf.close()\nfor op in (f.read, f.readline, f.fileno, lambda: next(f)):\n    try:\n        op()\n    except ValueError as e:\n        print(\"ValueError\", e)")
```
---
```output
b'\x00\x00\x00\x00' False
True
'first line\n'
'second été π\n' True True
'third\n' '' 'done'
ValueError I/O operation on closed file.
ValueError I/O operation on closed file.
ValueError I/O operation on closed file
ValueError I/O operation on closed file.
```

### seeking, a directory, an unknown encoding

```python
(python-run "f = open(\"tests/modules/data/text.txt\", encoding=\"utf-8\")\nprint(repr(f.read(5)), f.seekable())\nprint(f.seek(0), repr(f.read(5)))\nf.close()\ntry:\n    open(\"tests/modules\")\nexcept IsADirectoryError as e:\n    print(type(e).__name__, e.errno, e)\ntry:\n    open(\"tests/modules/data/text.txt\", encoding=\"klingon\")\nexcept LookupError as e:\n    print(type(e).__name__, e)\nprint(issubclass(PermissionError, OSError), hasattr(f, \"getvalue\"))")
```
---
```output
'first' True
0 'first'
IsADirectoryError 21 [Errno 21] Is a directory: 'tests/modules'
LookupError unknown encoding: klingon
True False
```

### a mode that would write is refused

DIVERGENCE: CPython opens the file for writing; writing a file is not offered
here, and the refusal is an `io.UnsupportedOperation`, an `OSError`.

```python
(python-run "try:\n    open(\"tests/modules/data/out.txt\", \"w\")\nexcept OSError as e:\n    print(type(e).__name__)")
```
---
```output
UnsupportedOperation
```
