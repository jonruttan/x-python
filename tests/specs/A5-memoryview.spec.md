# memoryview

### a view over bytes, a bytearray and an array

```python
(python-run "from array import array\nb = bytearray(b\"1234\")\nm = memoryview(b)\nprint(len(m), m[0], m[-1], list(m), m.itemsize, m.nbytes, m.readonly, m.format)\nm[0] = 65\nprint(b, list(m[1:]), list(m[1:-1]), len(m[2:2]))\nr = memoryview(b\"abc\")\nprint(r.readonly, list(r), r == b\"abc\", r == b\"xyz\", r == 5, b\"abc\" == r)\na = array(\"i\", [1, 2, 3, 4])\nma = memoryview(a)\nprint(list(ma), ma.itemsize, ma.nbytes, ma.format)\nma[1:3] = memoryview(array(\"i\", [7, 8]))\nprint(a)\ndef err(f):\n    try:\n        f()\n    except (TypeError, ValueError, AttributeError, IndexError) as e:\n        print(type(e).__name__, e)\ndef store_read_only():\n    r[0] = 1\ndef store_read_only_slice():\n    r[0:2] = b\"00\"\ndef index_past_end():\n    m[9]\ndef other_format():\n    ma[1:3] = memoryview(bytearray(2))\ndef other_length():\n    ma[0:2] = b\"1234\"\nerr(store_read_only)\nerr(store_read_only_slice)\nerr(index_past_end)\nerr(lambda: memoryview(b\"a\").noexist)\nerr(lambda: memoryview(5))\nerr(other_format)\nerr(other_length)\nmv = memoryview(bytearray(range(6)))\nmv[1:] = mv[:-1]\nprint(list(mv), list(memoryview(mv)[2:4]))")
```
---
```output
4 49 52 [49, 50, 51, 52] 1 4 False B
bytearray(b'A234') [50, 51, 52] [50, 51] 0
True [97, 98, 99] True False False True
[1, 2, 3, 4] 4 16 i
array('i', [1, 7, 8, 4])
TypeError cannot modify read-only memory
TypeError cannot modify read-only memory
IndexError index out of bounds on dimension 1
AttributeError 'memoryview' object has no attribute 'noexist'
TypeError memoryview: a bytes-like object is required, not 'int'
ValueError memoryview assignment: lvalue and rvalue have different structures
ValueError memoryview assignment: lvalue and rvalue have different structures
[0, 0, 1, 2, 3, 4] [1, 2]
```
