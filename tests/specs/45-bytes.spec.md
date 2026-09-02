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
