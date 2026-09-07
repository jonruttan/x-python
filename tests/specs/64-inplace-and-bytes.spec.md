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

## what this runtime cannot do here

### a three-character op= is not tokenized

`//=`, `**=`, `>>=` and `<<=` are three characters, and the tokenizer PAIRS:
it reads two-character operators and stops.  The binary forms all work --
`a = a // b` is fine -- so the gap is the assignment spelling alone.

```python
(python-run "n = 7\nn //= 2\nprint(n)")
```
---
    Error: #<err:syntax unexpected token in expression>

### a NUL byte is refused in a literal, while the program is read

A string on this platform is a C STRING, by an engine guarantee rather than an
accident -- `str/nul-terminated`, in x-lang's `docs/engine-contract.md` -- so
it ends at its first NUL and nothing this bundle can pass changes that.  There
is no fix available here, only a choice of failure, and every spelling now
makes the same one.  What they did instead, measured against CPython 3.14.7:

| | CPython | here, before |
|---|---:|---:|
| `len(chr(0))` | 1 | 0 |
| `len(b'\x00')` | 1 | 0 |
| `len('a' + chr(0) + 'b')` | 3 | 2 |
| `repr(b'\x00')` | `b'\x00'` | `b''` |

The value did not raise and did not survive -- it SHORTENED, silently, which
is the worst of the three answers a runtime can give.
`docs/nul-and-the-string-layer.md` is the decision, including why carrying a
NUL in `bytes` alone was rejected: `bytes` is a wrapper and could have held a
byte list, but a NUL-bearing `bytes` in a runtime whose `str` cannot hold one
has nowhere to `.decode()` to, so the silent loss moves to the seam rather
than going away.

A literal is refused while the program is being READ, so it takes the whole
program with it and no `try` in that program catches it -- the shape CPython
gives a `SyntaxError`.  CPython prints `1` here.

```python
(python-run "print(len(b'\\x00'))")
```
---
    Error: #<err:value a NUL byte is not representable here>

### a str literal's NUL is refused the same way

CPython prints `3`.

```python
(python-run "print(len('a\\x00b'))")
```
---
    Error: #<err:value a NUL byte is not representable here>

### octal names a NUL too

`\0` and `\000` are the same byte by another spelling, in either kind of
literal.  CPython prints `b'\x00' b'\x00'`.

```python
(python-run "print(b'\\0', b'\\000')")
```
---
    Error: #<err:value a NUL byte is not representable here>

### an f-string body is read like any other literal

CPython prints the three-character string `x\x00y`.

```python
(python-run "print(f'x\\x00y')")
```
---
    Error: #<err:value a NUL byte is not representable here>

### at runtime it is a ValueError carrying the same sentence

`chr(0)` is the one every other runtime path goes through -- `%c` and an
f-string's `{chr(0)}` included -- and the two `bytes()` arms answer for
themselves.  One sentence, five spellings, and `except ValueError` catches
every one.  CPython raises none of them.

```python
(python-run "try:\n    chr(0)\nexcept ValueError as e:\n    print('chr', e)\ntry:\n    bytes([0])\nexcept ValueError as e:\n    print('list', e)\ntry:\n    bytes(3)\nexcept ValueError as e:\n    print('count', e)\ntry:\n    '%c' % 0\nexcept ValueError as e:\n    print('pct', e)\ntry:\n    f'{chr(0)}'\nexcept ValueError as e:\n    print('fstr', e)")
```
---
```output
chr a NUL byte is not representable here
list a NUL byte is not representable here
count a NUL byte is not representable here
pct a NUL byte is not representable here
fstr a NUL byte is not representable here
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
