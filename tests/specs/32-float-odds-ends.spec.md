The float family's odds and ends: the small semantics float1.py and its
neighbours turn out to lean on. Bytes literals exist exactly far enough to
reach float(); unary + and ~ join -; floor division floors floats; bools
are ints wherever numbers compare; membership and the bitwise family are
real operators with Python's refusals. Every expectation is a real CPython
output. The big-literal case pins a fix for a silent wrap: integer literals
used to read through a child base with no bigint type.

## bytes literals reach float

### both quote spellings, through bytearray too

```python
(python-run "print((float(b'1.2'), float(bytearray(b'3.4'))))")
```
---
    (1.2, 3.4)

### a bytes value prints as its literal

```python
(python-run "print(b'ab')")
```
---
    b'ab'

### a bare b is still a name

```python
(python-run "b = 5\nprint(b)")
```
---
    5

## unary operators

### plus is a numeric no-op, minus negates, tilde inverts

```python
(python-run "print((+(1.2), -(1.2), ~5, ~0, ~-1))")
```
---
    (1.2, -1.2, -6, -1, 0)

### tilde refuses floats

```python
(python-run "try:\n    ~1.2\nexcept TypeError:\n    print('TypeError')")
```
---
    TypeError

### an expression statement can begin with an operator

```python
(python-run "x = 3\n-x\n~x\nprint(x)")
```
---
    3

## floor division of floats

### floats floor to floats

```python
(python-run "print((1.0 // 2, 2.0 // 2, 7.0 // 2.5, -7.0 // 2))")
```
---
    (0.0, 1.0, 2.0, -4.0)

## bools are ints in comparisons

### equality both ways round

```python
(python-run "print((0.0 == False, 1.0 == True, False == 0.0, True == 1.0))")
```
---
    (True, True, True, True)

### ordering too

```python
(python-run "print((True < 2, False < 0.5, True >= 1))")
```
---
    (True, True, True)

## nan compares false

### even to itself

```python
(python-run "nan = float('nan')\nprint((nan == 1.2, nan == nan))")
```
---
    (False, False)

## zero to a negative power

### raises where C's pow answers inf

```python
(python-run "try:\n    0.0**-1\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')")
```
---
    ZeroDivisionError

## float pow

### libm, not integer squaring

```python
(python-run "print((2.0 ** 0.5, 2 ** 0.5, pow(2.0, 10), pow(float('inf'), 2)))")
```
---
    (1.4142135623730951, 1.4142135623730951, 1024.0, inf)

## membership

### strings, lists, tuples, dict keys, and not in

```python
(python-run "print(('b' in 'abc', 'z' in 'abc', 2 in [1, 2], 5 in (1, 2), 1 in {1: 'a'}, 3 not in [1, 2]))")
```
---
    (True, False, True, False, True, True)

### a float is not iterable

```python
(python-run "try:\n    1.2 in 3.4\nexcept TypeError:\n    print('TypeError')")
```
---
    TypeError

## bitwise, exact twos complement

### positives and negatives, all three ops

```python
(python-run "print((3 | 5, 3 & 5, 3 ^ 5, -1 | 2, -3 & 7, -3 ^ 7, 6 | -9))")
```
---
    (7, 1, 6, -1, 5, -6, -9)

### a float operand refuses

```python
(python-run "try:\n    print(1 | 1.0)\nexcept TypeError:\n    print('TypeError')")
```
---
    TypeError

## numeric builtins

### abs clears the sign bit, bigints included

```python
(python-run "print((abs(-1.5), abs(-0.0), abs(5), abs(-99999999999999999999)))")
```
---
    (1.5, 0.0, 5, 99999999999999999999)

### round is half to even, int without ndigits

```python
(python-run "print((round(2.5), round(3.5), round(2.675, 2), round(1.5), round(7)))")
```
---
    (2, 4, 2.67, 2, 7)

### min and max, variadic and iterable, strings ordered

```python
(python-run "print((min(3, 1, 2), max([4, 9, 2]), min('ba', 'ab'), max('ba', 'ab')))")
```
---
    (1, 9, 'ab', 'ba')

## int of float is exact

### through the digits, bigints included

```python
(python-run "print((int(1e19), int(2.0**100), int(1418774543.0), int(-2.7)))")
```
---
    (10000000000000000000, 1267650600228229401496703205376, 1418774543, -2)

## big integer literals

### past two to the sixty-three, no wrap

```python
(python-run "print((99999999999999999999, -99999999999999999999))")
```
---
    (99999999999999999999, -99999999999999999999)
