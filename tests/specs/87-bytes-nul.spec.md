# a bytes carries a NUL

### a zero byte is a byte

```python
(python-run "b = b\"00\\x0000\"\nprint(len(b), b)\nprint(b.find(b\"\\x00\"), b.index(b\"\\x00\"), b.count(b\"0\"))\nprint(b[2], b[1:4], list(b))\nprint(b == b\"00\\x0000\", b < b\"00\\x0001\")")
```
---
```output
5 b'00\x0000'
2 2 4
0 b'0\x000' [48, 48, 0, 48, 48]
True True
```

### every constructor can name one

```python
(python-run "print(bytes(3), bytes([0]), bytes([0, 1, 0]))\nprint(bytearray(2), bytearray(range(4)))\nprint(ord(b\"\\x00\"), b\"\\0\", b\"\\000\")\nprint(len(b\"\\x00\\x01\\x00\"))")
```
---
```output
b'\x00\x00\x00' b'\x00' b'\x00\x01\x00'
bytearray(b'\x00\x00') bytearray(b'\x00\x01\x02\x03')
0 b'\x00' b'\x00'
3
```

### a needle may be an int

```python
(python-run "print(b\"hello world\".find(ord(b\"l\")))\nprint(bytearray(b\"hello\\x00world\").rfind(b\"l\"))\nprint(b\"abc\".count(ord(\"b\")))\nprint(b\"00\\x0000\".index(0, 0))\ntry:\n    b\"00\\x0000\".index(0, 3)\nexcept ValueError:\n    print(\"ValueError\")")
```
---
```output
2
9
1
2
ValueError
```

### find, index and count take a window

```python
(python-run "b = b\"00\\x0000\"\nprint(b.index(b\"0\", 0), b.index(b\"0\", 3))\nprint(b.rindex(b\"0\", 0), b.rindex(b\"0\", 3))\nprint(b\"aaaa\".count(b\"a\", 1), b\"aaaa\".count(b\"a\", 1, 3))\nprint(b\"1foo\".startswith(b\"foo\", 1))\nprint(b\"abcabc\".find(b\"a\", 1))\nprint(b\"abc\".find(b\"z\", 0, 2))")
```
---
```output
0 3
4 4
3 2
True
3
-1
```

### a separator that is None, empty, or absent

```python
(python-run "print(b\"a b\".split())\nprint(b\"   a   b    \".split(None))\nprint(b\"   a   b    \".split(None, 1))\nprint(b\"   a   b  c  \".split(None, 1))\nprint(b\"   a   b  c  \".split(None, 0))\ntry:\n    b\"abc\".split(b\"\")\nexcept ValueError:\n    print(\"ValueError\")\ntry:\n    b\"asdf\".partition(b\"\")\nexcept ValueError:\n    print(\"ValueError\")")
```
---
```output
[b'a', b'b']
[b'a', b'b']
[b'a', b'b    ']
[b'a', b'b  c  ']
[b'a   b  c  ']
ValueError
ValueError
```

### splitlines keeps its ends when asked

```python
(python-run "print(b\"foo\\r\\nbar\\r\\n\\r\\n\".splitlines())\nprint(b\"foo\\r\\nbar\\r\\n\\r\\n\".splitlines(True))\nprint(b\"a\\nb\".splitlines(), b\"a\\nb\".splitlines(True))")
```
---
```output
[b'foo', b'bar', b'']
[b'foo\r\n', b'bar\r\n', b'\r\n']
[b'a', b'b'] [b'a\n', b'b']
```

### the surface, on bytes that hold a zero

```python
(python-run "b = b\"a\\x00b\\x00c\"\nprint(b.split(b\"\\x00\"))\nprint(b.partition(b\"\\x00\"))\nprint(b.replace(b\"\\x00\", b\"-\"))\nprint(b.upper(), b.strip(b\"c\"))\nprint(b\"\\x00\".join([b\"a\", b\"b\"]))\nprint(b.startswith(b\"a\\x00\"), b.endswith(b\"\\x00c\"))")
```
---
```output
[b'a', b'b', b'c']
(b'a', b'\x00', b'b\x00c')
b'a-b-c'
b'A\x00B\x00C' b'a\x00b\x00'
b'a\x00b'
True True
```
