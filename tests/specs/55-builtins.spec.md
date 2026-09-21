Builtins (`python/runtime.x`, `python/parse.x`): bin/hex/oct over the
format engine's base conversion, divmod, three-argument pow, round of an
int to a negative digit (half to even); lazy enumerate/filter/map over
several iterables, reversed through __reversed__ or length+getitem,
sorted and min/max with key; callable, id, getattr with a default,
setattr, delattr, issubclass; class attributes and one-line class bodies.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## builtins

### bases and divmod

```python
(python-run "print(bin(1), bin(-1), bin(15), bin(-15), bin(12345), bin(0b10101))\nprint(hex(1), hex(-1), hex(15), hex(-15), hex(12345))\nprint(oct(1), oct(-1), oct(15), oct(-15), oct(12345))\nprint(divmod(0, 2), divmod(3, 4), divmod(20, 3), divmod(-7, 2))\ntry:\n    divmod(1, 0)\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')\ntry:\n    divmod('a', 'b')\nexcept TypeError:\n    print('TypeError')\nprint(-7 // 2, 7 // -2, -7 % 2, 7 % -2, divmod(7, -2), -7.0 // 2, 7 // 2)\n")
```
---
```output
0b1 -0b1 0b1111 -0b1111 0b11000000111001 0b10101
0x1 -0x1 0xf -0xf 0x3039
0o1 -0o1 0o17 -0o17 0o30071
(0, 0) (0, 3) (6, 2) (-4, 1)
ZeroDivisionError
TypeError
-4 -4 1 -1 (-4, -1) -4.0 3
```

### bases past the machine word, and the format specs that share them

```python
(python-run "for n in (0, 7, -255, 2 ** 29 - 1, 2 ** 29, 10 ** 9, 2 ** 63 - 1, -(2 ** 63), 2 ** 64, 3 ** 40, True):\n    print(bin(n), oct(n), hex(n))\n    print(\"%x %X %o %#x %#o\" % (n, n, n, n, n), f\"{n:b} {n:X} {n:#_x} {n:08x}\")\nbig = 2 ** 200 + 12345\nprint(hex(big), oct(-big))\nprint(bin(big).count(\"1\"), len(bin(big)), [len(bin(2 ** i)) - 3 for i in (28, 29, 30, 58, 63, 64, 88)])")
```
---
```output
0b0 0o0 0x0
0 0 0 0x0 0o0 0 0 0x0 00000000
0b111 0o7 0x7
7 7 7 0x7 0o7 111 7 0x7 00000007
-0b11111111 -0o377 -0xff
-ff -FF -377 -0xff -0o377 -11111111 -FF -0xff -00000ff
0b11111111111111111111111111111 0o3777777777 0x1fffffff
1fffffff 1FFFFFFF 3777777777 0x1fffffff 0o3777777777 11111111111111111111111111111 1FFFFFFF 0x1fff_ffff 1fffffff
0b100000000000000000000000000000 0o4000000000 0x20000000
20000000 20000000 4000000000 0x20000000 0o4000000000 100000000000000000000000000000 20000000 0x2000_0000 20000000
0b111011100110101100101000000000 0o7346545000 0x3b9aca00
3b9aca00 3B9ACA00 7346545000 0x3b9aca00 0o7346545000 111011100110101100101000000000 3B9ACA00 0x3b9a_ca00 3b9aca00
0b111111111111111111111111111111111111111111111111111111111111111 0o777777777777777777777 0x7fffffffffffffff
7fffffffffffffff 7FFFFFFFFFFFFFFF 777777777777777777777 0x7fffffffffffffff 0o777777777777777777777 111111111111111111111111111111111111111111111111111111111111111 7FFFFFFFFFFFFFFF 0x7fff_ffff_ffff_ffff 7fffffffffffffff
-0b1000000000000000000000000000000000000000000000000000000000000000 -0o1000000000000000000000 -0x8000000000000000
-8000000000000000 -8000000000000000 -1000000000000000000000 -0x8000000000000000 -0o1000000000000000000000 -1000000000000000000000000000000000000000000000000000000000000000 -8000000000000000 -0x8000_0000_0000_0000 -8000000000000000
0b10000000000000000000000000000000000000000000000000000000000000000 0o2000000000000000000000 0x10000000000000000
10000000000000000 10000000000000000 2000000000000000000000 0x10000000000000000 0o2000000000000000000000 10000000000000000000000000000000000000000000000000000000000000000 10000000000000000 0x1_0000_0000_0000_0000 10000000000000000
0b1010100010111000101101000101001000101001000111111110100000100001 0o1242705505105107764041 0xa8b8b452291fe821
a8b8b452291fe821 A8B8B452291FE821 1242705505105107764041 0xa8b8b452291fe821 0o1242705505105107764041 1010100010111000101101000101001000101001000111111110100000100001 A8B8B452291FE821 0xa8b8_b452_291f_e821 a8b8b452291fe821
0b1 0o1 0x1
1 1 1 0x1 0o1 1 1 0x1 00000001
0x100000000000000000000000000000000000000000000003039 -0o4000000000000000000000000000000000000000000000000000000000000030071
7 203 [28, 29, 30, 58, 63, 64, 88]
```

### callable and id

```python
(python-run "print(callable(None), callable(1), callable([]), callable('dfsd'), callable(callable))\nprint(callable(lambda: None))\ndef f():\n    pass\nprint(callable(f))\nclass A:\n    def f(self):\n        pass\nprint(callable(A), callable(A()), callable(A().f))\nclass B:\n    def __call__(self):\n        pass\nprint(callable(B()))\nprint(id(1) == id(2), id(None) == id(None))\nl = [1, 2]\nprint(id(l) == id(l))\ng = lambda: None\nprint(id(g) == id(g))\n")
```
---
```output
False False False False True
True
True
True False True
True
False True
True
True
```

### attributes and class bodies

```python
(python-run "class A:\n    var = 132\n    def __init__(self):\n        self.var2 = 34\n    def meth(self, i):\n        return 42 + i\na = A()\nprint(getattr(a, 'var'), getattr(a, 'var2'), getattr(a, 'meth')(5))\nprint(getattr(a, '_none_such', 123), getattr(a, 'var2', 456))\ntry:\n    getattr(a, b'var')\nexcept TypeError:\n    print('TypeError')\nsetattr(a, 'var', 123)\nsetattr(a, 'var2', 56)\nprint(a.var, a.var2)\nprint(hasattr(a, 'var'), hasattr(a, '_none_such'))\nclass C: pass\nc = C()\nc.x = 1\nprint(c.x)\ndelattr(c, 'x')\ntry:\n    c.x\nexcept AttributeError:\n    print('AttributeError')\nprint(issubclass(A, A), issubclass(A, (A,)))\ntry:\n    issubclass(A, 1)\nexcept TypeError:\n    print('TypeError')\n")
```
---
```output
132 34 47
123 34
TypeError
123 56
True False
1
AttributeError
True True
TypeError
```
