Complex numbers (`python/runtime.x`, on x/num/complex.x's value). The
platform supplies the value -- a pair of floats with the tower doing the
arithmetic and equality across ints, floats and bools -- and Python
supplies the spelling and the refusals: the repr with its signed-zero and
omitted-real rules, the constructor's string grammar, ordering and floor and
modulo as TypeErrors, and powers through the polar form. Every expectation
is a real CPython output.

## literals and construction

### imaginary literals and the constructor's numeric forms

```python
(python-run "print((1j, 2.5j, 1+2j, complex(1), complex(1.2), complex(1, 2), complex()))")
```
---
    (1j, 2.5j, (1+2j), (1+0j), (1.2+0j), (1+2j), 0j)

### the string grammar, minimal forms

```python
(python-run "print((complex('j'), complex('J'), complex('1'), complex('1.2'), complex('1.2j'), complex('1+j')))")
```
---
    (1j, 1j, (1+0j), (1.2+0j), 1.2j, (1+1j))

### the string grammar, signed, padded, parenthesised

```python
(python-run "print((complex('1+2j'), complex('-1-2j'), complex('+1-2j'), complex(' -1+2j '), complex('(1+2j)')))")
```
---
    ((1+2j), (-1-2j), (1-2j), (-1+2j), (1+2j))

### specials in parts

```python
(python-run "print((complex('nanj'), complex('nan-infj'), float('nan') * 1j, float('inf') * (1 + 1j)))")
```
---
    (nanj, (nan-infj), (nan+nanj), (inf+infj))

### signed zeros survive construction

```python
(python-run "print((complex(-0.0, 1), complex(0, -1), complex(1, -0.0), complex(1e20, 1), complex(0.1, 0.2)))")
```
---
    ((-0+1j), -1j, (1-0j), (1e+20+1j), (0.1+0.2j))

### malformed strings refuse

```python
(python-run "for test in ('1+2', '1j+2', '1+2j+3', '1+2+3j', '1 + 2j'):\n    try:\n        complex(test)\n    except ValueError:\n        print('ValueError', test)")
```
---
```output
ValueError 1+2
ValueError 1j+2
ValueError 1+2j+3
ValueError 1+2+3j
ValueError 1 + 2j
```

## arithmetic

### unary

```python
(python-run "print((bool(1j), bool(0j), +(1j), -(1 + 2j)))")
```
---
    (True, False, 1j, (-1-2j))

### binary with bools, ints, floats and complex

```python
(python-run "print((1j + False, 1j + True, 1j + 2, 1j + 2j, 1j - 2, 1j - 2j, 1j * 2, 1j * 2j, 1j / 2))")
```
---
    (1j, (1+1j), (2+1j), 3j, (-2+1j), -1j, 2j, (-2+0j), 0.5j)

### division, float on the left, and a product

```python
(python-run "print(((1j / 2j).real, 1j / (1 + 2j), 1.2 + 3j, (1+2j) * (3-4j)))")
```
---
    (0.5, (0.4+0.2j), (1.2+3j), (11+2j))

### integer powers multiply exactly

```python
(python-run "print((1j**2, (1+1j)**3, 0j**0))")
```
---
    ((-1+0j), (-2+2j), (1+0j))

### fractional and complex powers go polar

```python
(python-run "ans = 1j**2.5\nprint('%.5g %.5g' % (ans.real, ans.imag))\nans = 1j**2.5j\nprint('%.5g %.5g' % (ans.real, ans.imag))")
```
---
```output
-0.70711 -0.70711
0.019703 0
```

### a negative real base to a fractional power is complex

```python
(python-run "ans = (-1) ** 2.3\nprint('%.5g %.5g' % (ans.real, ans.imag))\nans = (-1.2) ** -3.4\nprint('%.5g %.5g' % (ans.real, ans.imag))")
```
---
```output
0.58779 0.80902
-0.16625 0.51167
```

## equality, and the refusals

### equality across the tower, bools included

```python
(python-run "print((1j == 1, 1j == 1j, 0 + 0j == False, 1 + 0j == True, False == 0 + 0j, True == 1 + 0j))")
```
---
    (False, True, True, True, True, True)

### nan is never equal

```python
(python-run "nan = float('nan') * 1j\nprint((nan == 1j, nan == nan))")
```
---
    (False, False)

### no ordering, no floor, no bitwise, no invert

```python
(python-run "try:\n    1j < 2j\nexcept TypeError:\n    print('TypeError')\ntry:\n    1j // 2\nexcept TypeError:\n    print('TypeError')\ntry:\n    print(1 | 1j)\nexcept TypeError:\n    print('TypeError')\ntry:\n    ~(1j)\nexcept TypeError:\n    print('TypeError')")
```
---
```output
TypeError
TypeError
TypeError
TypeError
```

### zero divisions, plain and through powers

```python
(python-run "try:\n    1j / 0\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')\ntry:\n    0j**-1\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')\ntry:\n    0j**1j\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')")
```
---
```output
ZeroDivisionError
ZeroDivisionError
ZeroDivisionError
```

### attributes are read-only

```python
(python-run "try:\n    (1j).imag = 0\nexcept AttributeError:\n    print('AttributeError')")
```
---
    AttributeError

## builtins and the type

### abs, hash, conjugate

```python
(python-run "print((abs(1j), '%.5g' % abs(1j + 2), hash(1 + 0j), type(hash(1j)), (1+2j).conjugate()))")
```
---
    (1.0, '2.2361', 1, <class 'int'>, (1-2j))

### truthiness, the class object, and type identity

```python
(python-run "if not 0 + 0j:\n    print('complex 0')\nprint(complex)\nprint(type(complex()) == complex, type(1j) == complex)\nd = dict()\nd[float] = complex\nd[complex] = float\nprint(len(d))")
```
---
```output
complex 0
<class 'complex'>
True True
2
```

## shifts

### left and right, bigint results, floor on negatives

```python
(python-run "print((1 << 70, 1 << 3, 256 >> 4, -7 >> 1, -8 >> 1, 5 << 0))")
```
---
    (1180591620717411303424, 8, 16, -4, -4, 5)

### precedence: between & and +

```python
(python-run "print((1 << 2 << 1, (1 << 2) + 1, 2 + 1 << 3, 1 & 3 << 1))")
```
---
    (8, 5, 24, 0)

### floats refuse

```python
(python-run "try:\n    1.5 << 1\nexcept TypeError:\n    print('TypeError')")
```
---
    TypeError

## complex beside the rest of the tower

### a bigint floats first, as Python does

```python
(python-run "ans = 1j + (1 << 70)\nprint('%.5g %.5g' % (ans.real, ans.imag))")
```
---
    1.1806e+21 1

### a non-number is a TypeError, not the tower's teaching raise

```python
(python-run "try:\n    1j + []\nexcept TypeError:\n    print('TypeError')\ntry:\n    [] * 1j\nexcept TypeError:\n    print('TypeError')")
```
---
```output
TypeError
TypeError
```
