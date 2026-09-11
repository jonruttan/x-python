# in-place operators, and bytes as a name

### __iadd__ mutates and returns self

```python
(python-run "class A:\n    def __init__(self, v): self.v = v\n    def __iadd__(self, o):\n        self.v += o\n        return self\n    def __repr__(self): return f\"A({self.v})\"\na = A(1)\nb = a\na += 7\nprint(a, b, a is b)")
```
---
```output
A(8) A(8) True
```

### without __iadd__ the binary op is the fallback

```python
(python-run "class A:\n    def __init__(self, v): self.v = v\n    def __add__(self, o): return A(self.v + o)\n    def __repr__(self): return f\"A({self.v})\"\na = A(1)\nb = a\na += 7\nprint(a, b, a is b)")
```
---
```output
A(8) A(1) False
```

### every op= has its own dunder

```python
(python-run "class N:\n    def __init__(self, v): self.v = v\n    def __isub__(self, o): return N(self.v - o)\n    def __imul__(self, o): return N(self.v * o)\n    def __imod__(self, o): return N(self.v % o)\n    def __repr__(self): return f\"N({self.v})\"\nn = N(10)\nn -= 3\nprint(n)\nn *= 4\nprint(n)\nn %= 5\nprint(n)")
```
---
```output
N(7)
N(28)
N(3)
```

### in-place bitwise on a class

```python
(python-run "class B:\n    def __init__(self, v): self.v = v\n    def __ior__(self, o): return B(self.v | o)\n    def __iand__(self, o): return B(self.v & o)\n    def __ixor__(self, o): return B(self.v ^ o)\n    def __repr__(self): return f\"B({self.v})\"\nb = B(0b1100)\nb |= 0b0011\nprint(b)\nb &= 0b0110\nprint(b)\nb ^= 0b1111\nprint(b)")
```
---
```output
B(15)
B(6)
B(9)
```

### the three-character op= forms

```python
(python-run "n = 7\nn //= 2\nprint(n)\nn **= 3\nprint(n)\nn <<= 4\nprint(n)\nn >>= 2\nprint(n)")
```
---
```output
3
27
432
108
```

### each of those has its own dunder too

```python
(python-run "class N:\n    def __init__(self, v): self.v = v\n    def __ifloordiv__(self, o): return N(self.v // o)\n    def __ipow__(self, o): return N(self.v ** o)\n    def __ilshift__(self, o): return N(self.v << o)\n    def __irshift__(self, o): return N(self.v >> o)\n    def __repr__(self): return f\"N({self.v})\"\nn = N(17)\nn //= 5\nprint(n)\nn **= 4\nprint(n)\nn <<= 3\nprint(n)\nn >>= 2\nprint(n)")
```
---
```output
N(3)
N(81)
N(648)
N(162)
```

### and falls back to the binary op when there is none

```python
(python-run "class F:\n    def __init__(self, v): self.v = v\n    def __floordiv__(self, o): return F(self.v // o)\n    def __repr__(self): return f\"F({self.v})\"\na = F(9)\nb = a\na //= 2\nprint(a, b, a is b)")
```
---
```output
F(4) F(9) False
```

### the shorter operators still end where they did

```python
(python-run "a = 7\nprint(a // 2, a ** 2, a << 2, a >> 1)\nprint(a / 2, a <= 7, a >= 7, a == 7, a != 7)\nprint(2**3**2)\nn=7\nn//=2\nn<<=3\nn>>=1\nn**=2\nprint(n)")
```
---
```output
3 49 28 3
3.5 True True True False
512
144
```

### numbers and lists are unchanged by all this

```python
(python-run "n = 1\nn += 2\nn -= 1\nn *= 10\nn %= 7\nprint(n)\nl = [1]\nl += [2, 3]\nprint(l)\ns = \"a\"\ns += \"b\"\nprint(s)")
```
---
```output
6
[1, 2, 3]
ab
```

### bytes is a name

```python
(python-run "print(bytes([65, 66]), bytes(), bytes(b'hi'))\nprint(type(b'a') is bytes, isinstance(b'a', bytes))")
```
---
```output
b'AB' b'' b'hi'
True True
```

### bytes rejects what Python rejects

```python
(python-run "try:\n    bytes([300])\nexcept ValueError:\n    print(\"ValueError\")\ntry:\n    bytes(\"abc\")\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
ValueError
TypeError
```

### a negative count is a ValueError, and zero is still the empty bytes

`bytes(n)` counts, so it has a floor rather than a range, and the two answers
either side of that floor are different: CPython gives `b''` for 0 and
`ValueError("negative count")` for anything below.  One guard used to answer
for both, so a negative count came back as the empty bytes -- the answer that
belongs to 0.  A real CPython 3.14.7 output.

```python
(python-run "try:\n    bytes(-1)\nexcept ValueError as e:\n    print(e)\ntry:\n    bytes(-5)\nexcept ValueError as e:\n    print(e)\nprint(bytes(0), len(bytes(0)))")
```
---
```output
negative count
negative count
b'' 0
```

## a NUL byte, and where the limit actually is

### bytes carries one

A string on this platform is a C STRING, by an engine guarantee rather than an
accident -- `str/nul-terminated`, in x-lang's `docs/engine-contract.md` -- so
it ends at its first NUL.  While `bytes` was a wrapper over one, every
spelling of a zero byte was refused, and `docs/nul-and-the-string-layer.md`
said the platform could not carry one at all.

That was wrong, and the platform's own code said so: `x/codec/zlib.x` copies a
byte list into a `(str make)` region through the pointer door, and
`x/codec/sha256-jit.x` builds `"A\0B\0C"` the same way.  The true statement is
narrower and it is about a CLASS: **Str8** cannot, because every one of its
doors takes a C string.  So `bytes` carries a byte list now (python/bytes.x),
and this is CPython's answer rather than a refusal.

```python
(python-run "print(len(b'\\x00'))")
```
---
```output
1
```

### and every operation reads through it

```python
(python-run "b = b'\\x00\\x01\\x00'\nprint(b, len(b), b.count(b'\\x00'), b.find(b'\\x01'), b[0], list(b))\nprint(bytes(3), bytes([0]), bytearray(2))")
```
---
```output
b'\x00\x01\x00' 3 2 1 0 [0, 1, 0]
b'\x00\x00\x00' b'\x00' bytearray(b'\x00\x00')
```

### octal names a NUL too

`\0` and `\000` are the same byte by another spelling.

```python
(python-run "print(b'\\0', b'\\000')")
```
---
```output
b'\x00' b'\x00'
```

### a str literal's NUL is carried, not refused

SUPERSEDED.  This case used to assert the refusal, and the note under it said
giving `str` the same treatment as `bytes` was "its own arc".  That arc
landed: `str` is a list of CODE POINTS now (python/str.x), so a literal keeps
its zero byte and the length is CPython's.  The str side is pinned in
88-str-nul.spec.md; what stays here is the bytes side.

```python
(python-run "print(len('a\\x00b'))")
```
---
    3

### an f-string body is read like any other str literal

CPython prints the three-character string `x\x00y`.

```python
(python-run "print(f'x\\x00y')")
```
---
    Error: #<err:value a NUL byte is not representable here>

### at runtime the crossings raise and the carriers do not

`chr(0)` has left this list too -- it answers a str of one code point now.
What still refuses is every crossing INTO a platform string: `%c` builds its
answer with Str8, and so does an f-string, so both end at a zero byte and say
so rather than truncating.

```python
(python-run "print('chr', len(chr(0)))\nprint('list', bytes([0]))\nprint('count', bytes(3))\ntry:\n    '%c' % 0\nexcept ValueError as e:\n    print('pct', e)")
```
---
```output
chr 1
list b'\x00'
count b'\x00\x00\x00'
pct a NUL byte is not representable here
```

### nothing that stops short of a NUL is touched

`bytes(0)` is the empty bytes rather than a refusal, a raw string decodes no
escape at all so `r'\x00'` is the four characters CPython says it is, and
every other byte still round-trips.  A real CPython output.

```python
(python-run "print(bytes(0), bytes([65]), chr(65), b'\\x01\\xff', '\\x41')\nprint(repr(r'\\x00'), len(r'\\x00'))")
```
---
```output
b'' b'A' A b'\x01\xff' A
'\\x00' 4
```
