# int(text, base), a byte count past the word, and unit powers

### whitespace, sign and underscores

```python
(python-run "print(int(\" 314\"), int(\"314 \"), int(\"  \\t 314 \\t \"), int(\"+7\"), int(\"-3\"), int(\"1_000\"), int(\"  -0  \"))\n")
```
---
```output
314 314 314 7 -3 1000 0
```

### explicit bases and prefixes

```python
(python-run "print(int(\"ff\", 16), int(\"0xFF\", 16), int(\"-0x10\", 16), int(\"0o17\", 8), int(\"0b101\", 2), int(\"z\", 36), int(\"Z\", 36))\nprint(int(\"0x1f\", 0), int(\"0o17\", 0), int(\"0b11\", 0), int(\"42\", 0), int(\"-0B11\", 0))\nprint(int(\"12345678901234567890\"), int(\"1234567890abcdef\", 16), int(\"-1234567890ABCDEF\", 16))\n")
```
---
```output
255 255 -16 15 5 35 35
31 15 3 42 -3
12345678901234567890 1311768467294899695 -1311768467294899695
```

### a bytes argument is its text

```python
(python-run "print(int(b\"123\"), int(bytearray(b\" -45 \")), int(b\"ff\", 16))\n")
```
---
```output
123 -45 255
```

### the keyword base

```python
(python-run "print(int(\"ff\", base=16), int(\"777\", base=8))\n")
```
---
```output
255 511
```

### the errors name the base and the text

```python
(python-run "for f in (lambda: int(\" 3 1 \"), lambda: int(\"xyz\", 16), lambda: int(\"12\", 1), lambda: int(5, 16), lambda: int(\"\"), lambda: int(\"0x1f\", 10), lambda: int(\"-\")):\n    try:\n        print(f())\n    except (ValueError, TypeError) as e:\n        print(type(e).__name__, e)\n")
```
---
```output
ValueError invalid literal for int() with base 10: ' 3 1 '
ValueError invalid literal for int() with base 16: 'xyz'
ValueError int() base must be >= 2 and <= 36, or 0
TypeError int() can't convert non-string with explicit base
ValueError invalid literal for int() with base 10: ''
ValueError invalid literal for int() with base 10: '0x1f'
ValueError invalid literal for int() with base 10: '-'
```

### a byte count past the machine word

```python
(python-run "for f in (bytes, bytearray):\n    try:\n        f(1 << 65)\n    except OverflowError as e:\n        print(\"OverflowError\", e)\nprint(bytes(3), bytearray(2), bytes(True))\n")
```
---
```output
OverflowError cannot fit 'int' into an index-sized integer
OverflowError cannot fit 'int' into an index-sized integer
b'\x00\x00\x00' bytearray(b'\x00\x00') b'\x00'
```

### powers of 0, 1 and -1 with a huge exponent

```python
(python-run "i = 1 << 65\nprint(0 ** i, 1 ** i, (-1) ** i, (-1) ** (i + 1), i ** 0, 0 ** 0, (-1) ** 3)\n")
```
---
```output
0 1 1 -1 1 1 -1
```

### bigint arithmetic against Python

```python
(python-run "print((2**70 + 12345) & (2**70 + 54321), (2**70 + 12345) | 54321, (2**70 + 12345) ^ (2**69 + 1))\nprint((10**30 + 7) % 12345, (-(10**30) - 7) % 12345, 3**60, (2**100) >> 37, (2**100) // (3**20))\n")
```
---
```output
1180591620717411307569 1180591620717411365945 1770887431076116967480
3422 8923 42391158275216203514294433201 9223372036854775808 363558641556578823726
```

