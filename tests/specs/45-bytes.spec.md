Bytes (`python/types.x`, `python/runtime.x`, `python/tokens.x`): the bytes
methods are the str methods on the underlying byte string, arguments
unwrapped and every string in the answer wrapped back; str/bytes mixing is
a TypeError; indexing yields ints, slicing bytes, iteration ints; Python's
b'...' repr with \xhh for anything outside printable ASCII; \xhh in a bytes
literal is one raw byte.  Adjacent string literals concatenate.
Every expectation is a real CPython output.

## bytes

### bytes methods

```python
(python-run "print(b'mississippi'.rstrip(b'ipz'), b'  x '.strip(), b'abcabc'.split(b'bc', 2), b'abcabc'.rsplit(b'bc', 2), b'a b'.split())\nprint(b'abba'.partition(b'b'), b'abba'.rpartition(b'b'))\nprint(b'foo\\nbar'.splitlines(), b'foo\\nbar\\n'.splitlines(), b'foo\\r\\nbar\\r\\n\\r\\n'.splitlines(True))\nprint(b','.join([b'abc', b'123']), b'abc'.upper(), b'aXb'.replace(b'X', b'yy'), b'abc'.find(b'c'), b'abc'.startswith(b'ab'), b'abc'.count(b'b'))\n")
```
---
```output
b'mississ' b'x' [b'a', b'a', b''] [b'a', b'a', b''] [b'a', b'b']
(b'a', b'b', b'ba') (b'ab', b'b', b'a')
[b'foo', b'bar'] [b'foo', b'bar'] [b'foo\r\n', b'bar\r\n', b'\r\n']
b'abc,123' b'ABC' b'ayyb' 2 True 1
```

### bytes type errors

```python
(python-run "try:\n    print(b'mississippi'.rstrip('ipz'))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print('mississippi'.rstrip(b'ipz'))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(b\"abba\".partition('b'))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(\"abba\".partition(b'b'))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(b','.join(['abc', b'123']))\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(','.join([b'abc', b'123']))\nexcept TypeError:\n    print('TypeError')\n")
```
---
```output
TypeError
TypeError
TypeError
TypeError
TypeError
TypeError
```

### every source bytes and bytearray take

```python
(python-run "print(bytes(iter([128, 255])), bytearray(iter([1, 2])))\nprint(bytes(x for x in [1, 2]), bytes({3, 4}), bytes({1: 2}), bytes(range(3)))\nprint(bytes(5), bytes(True), bytearray(3))\n\n\ndef err(f):\n    try:\n        f()\n    except (TypeError, ValueError) as e:\n        print(type(e).__name__, e)\n\n\nerr(lambda: bytes(5.5))\nerr(lambda: bytearray(5.5))\nerr(lambda: bytes(None))\nerr(lambda: bytearray(None))\nerr(lambda: bytes([1, 2, 300]))\nerr(lambda: bytes(-1))\nerr(lambda: bytearray(-1))\nerr(lambda: bytes(\"abc\"))")
```
---
```output
b'\x80\xff' bytearray(b'\x01\x02')
b'\x01\x02' b'\x03\x04' b'\x01' b'\x00\x01\x02'
b'\x00\x00\x00\x00\x00' b'\x00' bytearray(b'\x00\x00\x00')
TypeError cannot convert 'float' object to bytes
TypeError cannot convert 'float' object to bytearray
TypeError cannot convert 'NoneType' object to bytes
TypeError cannot convert 'NoneType' object to bytearray
ValueError bytes must be in range(0, 256)
ValueError negative count
ValueError negative count
TypeError string argument without an encoding
```

### hex and fromhex, with separators and in both directions

```python
(python-run "print(b\"\".hex(), b\"\\x00\\x7f\\x80\\xff\".hex(), bytearray(b\"AB\").hex(), memoryview(b\"ab\").hex())\nprint(b\"\\x00\\x01\\x02\".hex(\":\"), b\"\\x00\\x01\\x02\".hex(\":\", 2), b\"\\x00\\x01\\x02\".hex(\":\", -2))\nprint(b\"\\x00\\x01\\x02\".hex(b\"-\"), b\"\\x00\\x01\\x02\".hex(\":\", 0), memoryview(b\"\\x01\\x02\").hex(\".\"))\nprint(bytes.fromhex(\"0001 7f\\tff\\n\"), bytearray.fromhex(\"ab cd\"), bytes.fromhex(b\"41\"))\nprint(b\"\".fromhex(\"01\"), bytes.fromhex(\"\"), bytes.fromhex(\" ab cd ef \"))\n\n\nclass B(bytes):\n    pass\n\n\nprint(repr(B.fromhex(\"41\")), type(B.fromhex(\"41\")).__name__)\n\n\ndef err(f):\n    try:\n        f()\n    except (TypeError, ValueError) as e:\n        print(type(e).__name__, e)\n\n\nerr(lambda: b\"x\".hex(\"ab\"))\nerr(lambda: b\"x\".hex(\"\"))\nerr(lambda: b\"x\".hex(chr(233)))\nerr(lambda: b\"x\".hex(5))\nerr(lambda: bytes.fromhex(5))\nerr(lambda: bytes.fromhex(\"abcde\"))\nerr(lambda: bytes.fromhex(\"a b\"))\nerr(lambda: bytes.fromhex(\"abga\"))\nerr(lambda: bytes.fromhex(\"ab cd e f \"))")
```
---
```output
 007f80ff 4142 6162
00:01:02 00:0102 0001:02
00-01-02 000102 01.02
b'\x00\x01\x7f\xff' bytearray(b'\xab\xcd') b'A'
b'\x01' b'' b'\xab\xcd\xef'
b'A' B
ValueError sep must be length 1.
ValueError sep must be length 1.
ValueError sep must be ASCII.
TypeError object of type 'int' has no len()
TypeError fromhex() argument must be str or bytes-like, not int
ValueError fromhex() arg must contain an even number of hexadecimal digits
ValueError non-hexadecimal number found in fromhex() arg at position 1
ValueError non-hexadecimal number found in fromhex() arg at position 2
ValueError non-hexadecimal number found in fromhex() arg at position 7
```

### bytes values

```python
(python-run "print(b\"123\"[0:2], b\"123\"[-1:], b\"abc\"[0], b\"abc\"[-1], len(b\"abc\"))\nprint(b'foo\\nbar\\t\\x01\\x7f\\xff\\'\"\\\\')\nprint(repr(b\"it's\"), str(b'x'), b'a' + b'b', b'ab' * 2, b'a' == b'a', b'a' == b'b', b'a' != b'b', b'b' in b'abc', b'zz' in b'abc')\nprint(list(b'ab'), [c for c in b'xy'])\nfor c in b'hi': print(c)\n")
```
---
```output
b'12' b'3' 97 99 3
b'foo\nbar\t\x01\x7f\xff\'"\\'
b"it's" b'x' b'ab' b'abab' True False True True False
[97, 98] [120, 121]
104
105
```

### adjacent string literals

```python
(python-run "print(\"a\" \"b\")\nprint(\"a\" '''b''')\nprint(\"a\"\n    \"b\")\nx = (\"a\"\n     \"b\"\n     'c')\nprint(x)\nprint(b'a' b'b')\n")
```
---
```output
ab
ab
ab
abc
b'ab'
```

### str() with an encoding decodes a bytes-like value

```python
(python-run "import array\nprint(str(b\"abc\", \"utf-8\"))\nprint([ord(c) for c in str(bytearray(b\"caf\\xc3\\xa9\"), \"utf-8\")])\nprint(repr(str(b\"\", \"utf-8\")), len(str(b\"x\\xf0\\x9f\\x90\\x8dy\", \"utf-8\")))\nprint(str(array.array(\"B\", [104, 105]), \"utf-8\"))\nprint(str(b\"abc\", \"utf-8\", \"ignore\"))\ntry:\n    str(b\"abc\", \"utf-8\", \"strict\", \"extra\")\nexcept TypeError as e:\n    print(e)\ntry:\n    str(\"abc\", \"utf-8\")\nexcept TypeError as e:\n    print(e)\ntry:\n    str(1, \"utf-8\")\nexcept TypeError as e:\n    print(e)\ntry:\n    str([1], \"utf-8\")\nexcept TypeError as e:\n    print(e)")
```
---
```output
abc
[99, 97, 102, 233]
'' 3
hi
abc
str expected at most 3 arguments, got 4
decoding str is not supported
decoding to str: need a bytes-like object, int found
decoding to str: need a bytes-like object, list found
```

### bytes encodes a str given an encoding, takes its arguments by keyword, and checks them

```python
(python-run "class S(str):\n    pass\nclass B(bytes):\n    pass\nprint(bytes(\"é\", \"utf-8\"), bytes(\"ab\", \"ascii\", \"strict\"), bytes(S(\"é\"), \"utf-8\"), B(\"é\", \"utf-8\"))\nprint(bytes(source=b\"x\"), bytes(source=\"é\", encoding=\"utf-8\"), bytes(source=[65]))\ndef err(f):\n    try:\n        f()\n    except TypeError as e:\n        print(e)\nerr(lambda: bytes(\"ab\"))\nerr(lambda: bytes(\"ab\", errors=\"strict\"))\nerr(lambda: bytes(encoding=\"utf-8\"))\nerr(lambda: bytes(b\"x\", \"utf-8\"))\nerr(lambda: bytes([1], errors=\"x\"))\nerr(lambda: bytes(nope=1))\nerr(lambda: bytes(1, 2, 3, 4))")
```
---
```output
b'\xc3\xa9' b'ab' b'\xc3\xa9' b'\xc3\xa9'
b'x' b'\xc3\xa9' b'A'
string argument without an encoding
string argument without an encoding
encoding without a string argument
encoding without a string argument
errors without a string argument
bytes() got an unexpected keyword argument 'nope'
bytes() takes at most 3 arguments (4 given)
```
