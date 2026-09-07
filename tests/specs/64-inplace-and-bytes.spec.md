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

## what this runtime cannot do here

### a NUL byte is not representable

A string on this platform ends at its first NUL, so `chr(0)` is already the
empty string and `b"\x00"` is already empty -- a limit of the string layer,
not of bytes.  The constructor REFUSES rather than answering a short bytes,
because a silently shorter value is the worse of the two failures.

```python
(python-run "try:\n    bytes([0])\nexcept ValueError as e:\n    print(e)\nprint(len(b'\\x00'), len(chr(0)))")
```
---
```output
a NUL byte is not representable here
0 0
```
