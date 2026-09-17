# buffers where bytes are

### int, float, bytes, str, eval and exec take any buffer

```python
(python-run "from array import array\n\nprint(int(b\"123\"), int(bytearray(b\"123\")), int(memoryview(b\"123\")))\nprint(int(array(\"B\", b\"12\")), int(memoryview(array(\"B\", b\"45\"))))\nprint(int(b\"ff\", 16), int(bytearray(b\"ff\"), 16))\nprint(float(b\"1.5\"), float(bytearray(b\"2.5\")), float(memoryview(b\"-3.5\")))\nprint(float(array(\"B\", b\"4.5\")), float(memoryview(array(\"B\", b\"6.25\"))))\nprint(eval(bytearray(b\"1 + 1\")), eval(memoryview(b\"2 + 2\")), eval(array(\"B\", b\"3 + 3\")))\nexec(bytearray(b\"print(4)\"))\nexec(memoryview(b\"print(5)\"))\nprint(eval(compile(memoryview(b\"6 + 6\"), \"<s>\", \"eval\")))\nprint(bytes(memoryview(b\"ab\")), bytearray(memoryview(b\"cd\")))\nprint(bytes(memoryview(array(\"h\", [1, 2]))), bytearray(memoryview(array(\"h\", [3, 4]))))\nprint(bytes(memoryview(b\"abcdef\")[2:4]), bytes(memoryview(array(\"h\", [1, 2, 3]))[1:3]))\nprint(str(memoryview(bytearray(b\"hi\"))[1:], \"utf-8\"))\na = array(\"B\", b\"snap\")\ns = str(a, \"utf-8\")\nb = bytes(a)\nmv = memoryview(a)\nt = str(mv, \"utf-8\")\na[0] = ord(\"X\")\nprint(s, b, t, a)\n\n\ndef err(f):\n    try:\n        f()\n    except (TypeError, ValueError) as e:\n        print(type(e).__name__, e)\n\n\nerr(lambda: int(memoryview(b\"ff\"), 16))\nerr(lambda: str(5, \"utf-8\"))")
```
---
```output
123 123 123
12 45
255 255
1.5 2.5 -3.5
4.5 6.25
2 4 6
4
5
12
b'ab' bytearray(b'cd')
b'\x01\x00\x02\x00' bytearray(b'\x03\x00\x04\x00')
b'cd' b'\x02\x00\x03\x00'
i
snap b'snap' snap array('B', [88, 110, 97, 112])
TypeError int() can't convert non-string with explicit base
TypeError decoding to str: need a bytes-like object, int found
```
