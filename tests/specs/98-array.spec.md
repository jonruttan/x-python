# the array module

### typecodes, construction and the byte layout

```python
(python-run "from array import array\na = array('B', [1, 2, 3])\nprint(a, len(a), a[0], a[-1])\nprint(array('h'), array('i', [1, 2]))\nprint(bool(array('i')), bool(array('i', [1])))\nprint(array('h', b'22'), array('i', bytearray(4)))\nprint(array('H', array('b', [1, 2])), array('b', array('I', [1, 2])))\nprint(array('l', [-2**31, 0, 2**31-1]))\nprint(array('q', [-2**63, -1, 0, 2**63-1]), array('Q', [0, 2**64-1]))\nprint(bytes(array('q', [-1])), bytes(array('Q', [2**64-1])), bytes(array('b', [0x61, 0x62, 0x63])))\n")
```
---
```output
array('B', [1, 2, 3]) 3 1 3
array('h') array('i', [1, 2])
False True
array('h', [12850]) array('i', [0])
array('H', [1, 2]) array('b', [1, 2])
array('l', [-2147483648, 0, 2147483647])
array('q', [-9223372036854775808, -1, 0, 9223372036854775807]) array('Q', [0, 18446744073709551615])
b'\xff\xff\xff\xff\xff\xff\xff\xff' b'\xff\xff\xff\xff\xff\xff\xff\xff' b'abc'
```

### comparison, containment and a generator source

```python
(python-run "from array import array\nprint(array('b', [1, 2]) == array('B', [1, 2]), array('b', [1, 2]) == array('h', [1, 2]))\nprint(array('b', [1, 2]) == b'\\x01\\x02', b'\\x01\\x02' == array('b', [1, 2]))\nprint(array('b', [1, 2]) != array('b', [1, 2]), array('b', [1, 2]) == array('b', [1, 3]))\na = array('B', [1, 1])\nprint(a < a, a <= a, a > a, a >= a)\nprint(a < array('B', [1, 2]), a > array('B', [1, 0]))\nprint('12' in array('B', b'12'), 1 in array('B', [1, 2]))\nprint(array('i', (i for i in range(5))))\n")
```
---
```output
True True
False False
False False
False True False True
True True
False True
array('i', [0, 1, 2, 3, 4])
```

### growing an array, and storing into one

```python
(python-run "from array import array\na1 = array('I', [1])\nprint(a1 + array('I', [2]))\na1 += array('I', [3, 4])\nprint(a1)\na1.extend(array('I', [5]))\na1.extend([6, 7])\na1.extend(i for i in (8, 9))\nprint(a1)\na1.append(10)\nprint(a1, a1.itemsize, a1.typecode)\nb = array('b', [1, 2, 3])\nb[0] = -5\nb[-1] = 7\nprint(b)\n")
```
---
```output
array('I', [1, 2])
array('I', [1, 3, 4])
array('I', [1, 3, 4, 5, 6, 7, 8, 9])
array('I', [1, 3, 4, 5, 6, 7, 8, 9, 10]) 4 I
array('b', [-5, 2, 7])
```

### the refusals

```python
(python-run "from array import array\nfor f in (lambda: array('X'), lambda: array('b', [200]), lambda: array('B', [-1]),\n          lambda: array('q', [2**63]), lambda: array('i', [1])[9],\n          lambda: array('b', [1, 2]).append(999)):\n    try:\n        f()\n    except (ValueError, OverflowError, IndexError) as e:\n        print(type(e).__name__)\na = array('Q', [1, 2])\ntry:\n    a[0] = -1\nexcept OverflowError:\n    print(\"OverflowError\", a[0])\nclass X(array):\n    pass\nprint(bytes(X('b', [0x61, 0x62])) == b'ab', X('b', [1]) == array('b', [1]))\n")
```
---
```output
ValueError
OverflowError
OverflowError
OverflowError
IndexError
OverflowError
OverflowError 1
True True
```


### the float typecodes f and d

```python
(python-run "import struct, array\nclass F:\n    def __float__(self):\n        return 2.5\ndef show(label, f):\n    try:\n        print(label, repr(f()))\n    except Exception as e:\n        print(label, type(e).__name__, e)\nnan = float(\"nan\")\nshow(\"array f 1e300\", lambda: array.array(\"f\", [1e300]))\nshow(\"array f str\", lambda: array.array(\"f\", [\"a\"]))\nshow(\"array d int\", lambda: array.array(\"d\", [1, True, F()]))\nshow(\"array f 1.2\", lambda: array.array(\"f\", [1.2]))\nshow(\"array f bytes\", lambda: array.array(\"f\", b\"\\x00\\x00\\x80?\"))\nshow(\"attrs\", lambda: (array.array(\"f\").itemsize, array.array(\"d\").itemsize, array.array(\"d\", [1.5]).typecode))\nshow(\"eq add\", lambda: (array.array(\"f\", [1.0]) == array.array(\"d\", [1.0]), array.array(\"d\", [1.0]) + array.array(\"d\", [2.5])))\nshow(\"bytes\", lambda: (bytes(array.array(\"d\", [1.0, -2.0])), bytes(array.array(\"f\", [0.1]))))\nshow(\"d from bytes\", lambda: array.array(\"d\", bytes(array.array(\"d\", [1e-310, 1.7976931348623157e308]))))")
```
---
```output
array f 1e300 array('f', [inf])
array f str TypeError must be real number, not str
array d int array('d', [1.0, 1.0, 2.5])
array f 1.2 array('f', [1.2000000476837158])
array f bytes array('f', [1.0])
attrs (4, 8, 'd')
eq add (True, array('d', [1.0, 2.5]))
bytes (b'\x00\x00\x00\x00\x00\x00\xf0?\x00\x00\x00\x00\x00\x00\x00\xc0', b'\xcd\xcc\xcc=')
d from bytes array('d', [1e-310, 1.7976931348623157e+308])
```
