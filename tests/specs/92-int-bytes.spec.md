# int.to_bytes and int.from_bytes

### to_bytes, little and big

```python
(python-run "print((10).to_bytes(1, \"little\"))\nprint((0x10000).to_bytes(3, \"little\"))\nprint((111111).to_bytes(4, \"big\"))\nprint((100).to_bytes(10, \"big\"))\nprint((0xCDEFF).to_bytes(3, \"little\"), (0xCDEFF).to_bytes(3, \"big\"))")
```
---
```output
b'\n'
b'\x00\x00\x01'
b'\x00\x01\xb2\x07'
b'\x00\x00\x00\x00\x00\x00\x00\x00\x00d'
b'\xff\xde\x0c' b'\x0c\xde\xff'
```

### signed values are two's complement

```python
(python-run "print((-10).to_bytes(1, \"little\", signed=True))\nprint((-1).to_bytes(3, \"big\", signed=True))\nprint((-128).to_bytes(1, \"big\", signed=True))\nprint((-32768).to_bytes(2, \"big\", signed=True))\nprint((-111111).to_bytes(4, \"little\", signed=True))")
```
---
```output
b'\xf6'
b'\xff\xff\xff'
b'\x80'
b'\x80\x00'
b'\xf9M\xfe\xff'
```

### the 3.11 defaults: one big-endian byte, and big

```python
(python-run "print((10).to_bytes())\nprint((100).to_bytes(10))\nprint(int.from_bytes(b\"\\x01\\x00\"))")
```
---
```output
b'\n'
b'\x00\x00\x00\x00\x00\x00\x00\x00\x00d'
256
```

### from_bytes

```python
(python-run "print(int.from_bytes(b\"\\x00\\x01\\x00\\x00\", \"little\"))\nprint(int.from_bytes(b\"\\x00\\x01\", \"big\"))\nprint(int.from_bytes(b\"\\xff\", \"big\", signed=True), int.from_bytes(b\"\\xff\", \"big\"))\nprint(int.from_bytes(b\"\", \"big\"), int.from_bytes(b\"\", \"little\", signed=True))\nprint(int.from_bytes([1, 2], \"big\"))\nprint(int.from_bytes(bytes(20), \"little\") == 0)")
```
---
```output
256
1
-1 255
0 0
258
True
```

### a value past the machine word

```python
(python-run "x = int.from_bytes(b\"\\x6f\\xab\\xcd\\x12\\x34\\x56\\x78\\xfb\", \"big\")\nprint(hex(x))\nprint(x.to_bytes(8, \"little\"))\nprint((2**64).to_bytes(9, \"little\"))\nprint((-(2**64)).to_bytes(9, \"big\", signed=True))\nprint(int.from_bytes((2**70).to_bytes(9, \"big\"), \"big\") == 2**70)")
```
---
```output
0x6fabcd12345678fb
b'\xfbxV4\x12\xcd\xabo'
b'\x00\x00\x00\x00\x00\x00\x00\x00\x01'
b'\xff\x00\x00\x00\x00\x00\x00\x00\x00'
True
```

### the errors, and the two empty answers

```python
(python-run "for f in (lambda: (1).to_bytes(-1, \"little\"), lambda: (1).to_bytes(0, \"little\"), lambda: (0x123).to_bytes(1, \"big\"), lambda: (-1).to_bytes(1, \"little\"), lambda: (-129).to_bytes(1, \"big\", signed=True), lambda: (1).to_bytes(1, \"middle\")):\n    try:\n        f()\n    except ValueError:\n        print(\"ValueError\")\n    except OverflowError:\n        print(\"OverflowError\")\nprint((0).to_bytes(0, \"big\"), (0).to_bytes(0, \"little\", signed=True))")
```
---
```output
ValueError
OverflowError
OverflowError
OverflowError
OverflowError
ValueError
b'' b''
```

### the int class carries both

```python
(python-run "print(\"from_bytes\" in int.__dict__, \"to_bytes\" in int.__dict__)\nprint(int.to_bytes(5, 1, \"big\"), (1).to_bytes.__name__)\nprint(True.to_bytes(1, \"big\"), type(5).from_bytes(b\"\\x02\", \"big\"))\ntry:\n    (5).nosuch\nexcept AttributeError as e:\n    print(e)")
```
---
```output
True True
b'\x05' to_bytes
b'\x01' 2
'int' object has no attribute 'nosuch'
```

### a builtin type refuses a store or a delete

```python
(python-run "for f in (lambda: setattr(int, \"to_bytes\", 1), lambda: delattr(int, \"to_bytes\")):\n    try:\n        f()\n    except TypeError as e:\n        print(e)\ntry:\n    int.x = 1\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    del str.upper\nexcept TypeError:\n    print(\"TypeError\")\nclass C(int):\n    pass\nC.x = 1\nprint(C.x, (5).to_bytes(1, \"big\"))")
```
---
```output
cannot set 'to_bytes' attribute of immutable type 'int'
cannot delete 'to_bytes' attribute of immutable type 'int'
TypeError
TypeError
1 b'\x05'
```
