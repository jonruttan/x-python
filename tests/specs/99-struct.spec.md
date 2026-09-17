# the struct module

### sizes, the byte-order prefixes and the plain codes

```python
(python-run "import struct\nprint(struct.calcsize(\"<bI\"), struct.calcsize(\">bI\"), struct.calcsize(\"BHBI\"))\nprint(struct.calcsize(\"<l\"), struct.calcsize(\"@l\"), struct.calcsize(\"=l\"), struct.calcsize(\"!l\"))\nprint(struct.calcsize(\"100sI\"), struct.calcsize(\"97sI\"), struct.calcsize(\"7xx\"), struct.calcsize(\">bxI3xH\"))\nprint(struct.pack(\"<l\", 1), struct.pack(\">l\", 1), struct.pack(\"<h\", 1), struct.pack(\">b\", 1))\nprint(struct.pack(\"<bI\", -128, 256), struct.pack(\">bI\", -128, 256))\nprint(struct.pack(\"!i\", 123), struct.pack(\"<x\"))\nprint(struct.unpack(\"<bI\", b\"\\x80\\0\\0\\x01\\0\"), struct.unpack(\">bI\", b\"\\x80\\0\\0\\x01\\0\"))\n")
```
---
```output
5 5 12
4 8 4 4
104 104 8 11
b'\x01\x00\x00\x00' b'\x00\x00\x00\x01' b'\x01\x00' b'\x01'
b'\x80\x00\x01\x00\x00' b'\x80\x00\x00\x01\x00'
b'\x00\x00\x00{' b'\x00'
(-128, 65536) (-128, 256)
```

### counts, bytes fields, padding and native alignment

```python
(python-run "import struct\nprint(struct.unpack(\"<6sH\", b\"foo\\0\\0\\0\\x12\\x34\"), struct.pack(\"<6sH\", b\"foo\", 10000))\nprint(struct.pack(\">bxI3xH\", 1, 2, 3))\nprint(struct.unpack(\">bxI3xH\", b\"\\x01\\0\\0\\0\\0\\x02\\0\\0\\0\\0\\x03\"))\ns = struct.pack(\"BHBI\", 10, 100, 200, 300)\nprint(s, struct.unpack(\"BHBI\", s) == (10, 100, 200, 300))\nprint(struct.calcsize('0s'), struct.unpack('0s', b''), struct.pack('0s', b'123'))\nprint(struct.calcsize('2s'), struct.unpack('2s', b'12'), struct.pack('2s', b'123'))\nprint(struct.calcsize('2H'), struct.unpack('<2H', b'1234'), struct.pack('<2H', 258, 515))\nprint(struct.calcsize('0s1s0H2H'), struct.calcsize('<0s1s0H2H'))\nprint(struct.unpack('<0s1s0H2H', b'01234'), struct.pack('<0s1s0H2H', b'abc', b'abc', 258, 515))\n")
```
---
```output
(b'foo\x00\x00\x00', 13330) b"foo\x00\x00\x00\x10'"
b'\x01\x00\x00\x00\x00\x02\x00\x00\x00\x00\x03'
(1, 2, 3)
b'\n\x00d\x00\xc8\x00\x00\x00,\x01\x00\x00' True
0 (b'',) b''
2 (b'12',) b'12'
4 (12849, 13363) b'\x02\x01\x03\x02'
6 5
(b'', b'0', 12849, 13363) b'a\x02\x01\x03\x02'
```

### the wide codes, offsets, writing in place and the refusals

```python
(python-run "import struct\nprint(struct.pack('<q', -2**63), struct.pack('<Q', 2**64-1))\nprint(struct.unpack('<q', b'\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff'), struct.unpack('<Q', b'\\xff\\xff\\xff\\xff\\xff\\xff\\xff\\xff'))\nbuf = b'0123456789'\nprint(struct.unpack_from('<b', buf, 4), struct.unpack_from('<b', buf, -4))\nb2 = bytearray(b'>----<<<<<<<')\nstruct.pack_into('<i', b2, 1, 0x30313233)\nprint(b2)\nfor f in (lambda: struct.unpack('2H', b'\\x00\\x00'), lambda: struct.pack_into('2I', bytearray(4), 0, 0),\n          lambda: struct.unpack('z', b'1'), lambda: struct.calcsize('0z'), lambda: struct.calcsize('1'),\n          lambda: struct.pack('1'), lambda: struct.unpack_from('<b', buf, 10)):\n    try:\n        f()\n        print('no error')\n    except Exception:\n        print('Exception')\n")
```
---
```output
b'\x00\x00\x00\x00\x00\x00\x00\x80' b'\xff\xff\xff\xff\xff\xff\xff\xff'
(-1,) (18446744073709551615,)
(52,) (54,)
bytearray(b'>3210<<<<<<<')
Exception
Exception
Exception
Exception
Exception
Exception
Exception
```


### the float codes e, f and d

```python
(python-run "import struct, array\nclass F:\n    def __float__(self):\n        return 2.5\ndef show(label, f):\n    try:\n        print(label, repr(f()))\n    except Exception as e:\n        print(label, type(e).__name__, e)\nnan = float(\"nan\")\nshow(\"pack f 1e300\", lambda: struct.pack(\"<f\", 1e300))\nshow(\"pack e 65520\", lambda: struct.pack(\"<e\", 65520.0))\nshow(\"pack e 65519\", lambda: struct.pack(\"<e\", 65519.0))\nshow(\"pack f past max\", lambda: struct.pack(\"<f\", 3.4028235677973366e38))\nshow(\"pack f max\", lambda: struct.pack(\"<f\", 3.4028234663852886e38))\nshow(\"pack f int\", lambda: struct.pack(\"<f\", 3))\nshow(\"pack nans\", lambda: (struct.pack(\"<d\", nan), struct.pack(\"<f\", nan), struct.pack(\">e\", nan)))\nshow(\"pack zeros\", lambda: (struct.pack(\"<e\", -0.0), struct.pack(\">d\", -0.0), struct.pack(\"<f\", 0.0)))\nshow(\"pack tiny\", lambda: (struct.pack(\"<f\", 1e-46), struct.pack(\"<e\", 1e-7), struct.pack(\"<d\", 5e-324), struct.pack(\"<f\", 1e-40)))\nshow(\"unpack\", lambda: (struct.unpack(\"<f\", b\"\\x00\\x00\\x80\\x7f\"), struct.unpack(\"<d\", b\"\\x01\\x00\\x00\\x00\\x00\\x00\\x00\\x00\"), struct.unpack(\">e\", b\"\\xfc\\x00\"), struct.unpack(\"<f\", b\"\\x01\\x00\\x00\\x00\")))\nshow(\"calcsize\", lambda: (struct.calcsize(\"e\"), struct.calcsize(\"f\"), struct.calcsize(\"d\"), struct.calcsize(\"bd\"), struct.calcsize(\"<bd\")))\nshow(\"pack obj\", lambda: struct.pack(\"<f\", F()))\nshow(\"round trip f\", lambda: [struct.unpack(\"<f\", struct.pack(\"<f\", v))[0] for v in (0.1, 1 / 3, 16777217.0, -2.5e-38)])\nshow(\"round trip e\", lambda: [struct.unpack(\"<e\", struct.pack(\"<e\", v))[0] for v in (1.1, 65504.0, 0.000123, -3.14159)])")
```
---
```output
pack f 1e300 OverflowError float too large to pack with f format
pack e 65520 OverflowError float too large to pack with e format
pack e 65519 b'\xff{'
pack f past max OverflowError float too large to pack with f format
pack f max b'\xff\xff\x7f\x7f'
pack f int b'\x00\x00@@'
pack nans (b'\x00\x00\x00\x00\x00\x00\xf8\x7f', b'\x00\x00\xc0\x7f', b'~\x00')
pack zeros (b'\x00\x80', b'\x80\x00\x00\x00\x00\x00\x00\x00', b'\x00\x00\x00\x00')
pack tiny (b'\x00\x00\x00\x00', b'\x02\x00', b'\x01\x00\x00\x00\x00\x00\x00\x00', b'\xc2\x16\x01\x00')
unpack ((inf,), (5e-324,), (-inf,), (1.401298464324817e-45,))
calcsize (2, 4, 8, 16, 9)
pack obj b'\x00\x00 @'
round trip f [0.10000000149011612, 0.3333333432674408, 16777216.0, -2.4999999777439474e-38]
round trip e [1.099609375, 65504.0, 0.00012302398681640625, -3.140625]
```
