Floats: the lexical spellings Python has and x's reader does not, the
constructor's full grammar, and repr as SHORTEST ROUND-TRIP — the decimal
string Python prints is the shortest one that parses back to exactly the same
double, where the engine's own writer is %.15g and loses a digit
(x-lang#577). The repr here is computed from the float's exact bits: bigint
digits, round half to even, verify through strtod, so every case in this file
is bit-for-bit CPython.

## the lexer's float spellings

### an exponent is one token

```python
(%seq (write (python-tokenize "x = 1e10")) (newline))
```
---
    (('tok-name "x") ('tok-op "=") ('tok-number "1e10"))

### signed exponents, either case

```python
(%seq (write (python-tokenize "y = 1.5E-3 + 2e+4")) (newline))
```
---
    (('tok-name "y") ('tok-op "=") ('tok-number "1.5E-3") ('tok-op "+") ('tok-number "2e+4"))

### a leading dot starts a float

```python
(%seq (write (python-tokenize "print(.1)")) (newline))
```
---
    (('tok-name "print") ('tok-group "(" (('tok-number ".1"))))

### a bare dot is still the attribute operator

```python
(%seq (write (python-tokenize "q = x.attr")) (newline))
```
---
    (('tok-name "q") ('tok-op "=") ('tok-name "x") ('tok-op ".") ('tok-name "attr"))

### underscores continue a number

```python
(%seq (write (python-tokenize "z = 1_000.1_8")) (newline))
```
---
    (('tok-name "z") ('tok-op "=") ('tok-number "1_000.1_8"))

## the values behind the spellings

### exponents and dots evaluate as floats, underscores as spelling

```python
(python-run "print((1e10, .5 + .5, 1_000, 1_000.5))")
```
---
    (10000000000.0, 1.0, 1000, 1000.5)

## repr is shortest round-trip

### the two digits %.15g loses

A third needs sixteen significant digits and this value needs seventeen;
the engine's writer stops at fifteen and both print wrong there.

```python
(python-run "print((1/3, 123456789.123456789, 0.1 + 0.2))")
```
---
    (0.3333333333333333, 123456789.12345679, 0.30000000000000004)

### Python's fixed/scientific thresholds

Fixed from 1e-4 up to but not including 1e16, scientific outside, ".0" kept
on integral floats, two-digit signed exponents.

```python
(python-run "print((1e16, 1e15, 0.0001, 1e-05, 100.0, 2.0))")
```
---
    (1e+16, 1000000000000000.0, 0.0001, 1e-05, 100.0, 2.0)

### the edges of the format

The smallest subnormal, the largest double, negative zero, the specials.

```python
(python-run "print((5e-324, 1.7976931348623157e+308, -0.0, -0.5, float('inf'), float('-inf'), float('nan')))")
```
---
    (5e-324, 1.7976931348623157e+308, -0.0, -0.5, inf, -inf, nan)

## the constructors' grammar

### inf, infinity and nan in any case, signed, trimmed

```python
(python-run "print((float('inf'), float('-Infinity'), float('NAN'), float(' 1.5 ')))")
```
---
    (inf, -inf, nan, 1.5)

### underscores in both constructors

```python
(python-run "print((float('1_2_3.4'), int('1_2_3')))")
```
---
    (123.4, 123)

### garbage still refuses loudly

```python
(python-run "try:\n    float('poodle')\nexcept ValueError:\n    print('ValueError')")
```
---
    ValueError

## a float is not an index

### list subscripts refuse floats with Python's message

```python
(python-run "try:\n    [1, 2][1.0]\nexcept TypeError as e:\n    print(e)")
```
---
    list indices must be integers or slices, not float
