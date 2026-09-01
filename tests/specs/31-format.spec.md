Percent formatting (`python/format.x`) — str.__mod__, dispatched from
`%py-mod` when the left operand is a string. Rendering goes through the
float repr's EXACT DIGIT machinery (%py-f-exact): %.5e, %.40f and %.0g are
all "keep k digits of a fully known expansion, round half to even against a
fully known tail", so the MicroPython corpus's classic failures (a digit
value of ten rendering as ':', %.12e of 1e-r rendering as 0.999...e-r) are
structurally impossible rather than carefully avoided. Every expectation in
this file is a real CPython output.

## text and integers

### %s %r and the integer spellings

```python
(python-run "print('%s|%r|%d|%i|%u' % (1.0, 1.0, 1.0, 1.0, 1.0))")
```
---
    1.0|1.0|1|1|1

### hex, octal and case

```python
(python-run "print('%x %X %o' % (255, 255, 8))")
```
---
    ff FF 10

### width, left-justify and zero-pad

```python
(python-run "print('%5d|%-5d|%05d' % (42, 42, 42))")
```
---
       42|42   |00042

### integer precision zero-pads digits, beating width

```python
(python-run "print('%02.3d' % 123)")
```
---
    123

## the float conversions

### all six, default precision

```python
(python-run "print('%e|%E|%f|%F|%g|%G' % (1.23456, 1.23456, 1.23456, 1.23456, 1.23456, 1.23456))")
```
---
    1.234560e+00|1.234560E+00|1.234560|1.234560|1.23456|1.23456

### e f and g at explicit precisions

```python
(python-run "print('%.5e %.3e %.1e %.0e' % (0.116, 0.116, 0.116, 0.116))")
```
---
    1.16000e-01 1.160e-01 1.2e-01 1e-01

### g strips trailing zeros and switches notation

```python
(python-run "print('%.3g %.1g %.0g' % (0.116, 0.116, 0.116))")
```
---
    0.116 0.1 0.1

### f pads trailing zeros and rounds half to even

```python
(python-run "print('%.3f %.0f' % (2.0, 2.6))")
```
---
    2.000 3

### signs: forced, spaced, and zero-flag placement

```python
(python-run "print('%+f %+f' % (1.23, -1.23))\nprint('% f % f' % (1.23, -1.23))\nprint('%8.3f|%-8.3f|%08.3f' % (-3.7, -3.7, -3.7))")
```
---
```output
+1.230000 -1.230000
 1.230000 -1.230000
  -3.700|-3.700  |-003.700
```

## the exact-digit cases

### a tiny magnitude never renders as nine-nines of the next unit

```python
(python-run "print('%.1e' % 9.99)\nprint('%.1e' % 0.999)")
```
---
```output
1.0e+01
1.0e+00
```

### g rounds before choosing notation

```python
(python-run "print('%.1g' % -9.9)\nprint('%.2g' % 99.9)")
```
---
```output
-1e+01
1e+02
```

### deep fixed precision is exact, not buffer noise

```python
(python-run "print('%f' % 1e-10)\nprint('%f' % 1e-100)")
```
---
```output
0.000000
0.000000
```

### huge magnitudes render every digit

```python
(python-run "print('%f' % 1e19)\nprint('%.2f' % 8.888e32)")
```
---
```output
10000000000000000000.000000
888800000000000060232471035248640.00
```

### fifty-one nines through e-notation

```python
(python-run "print('%.2e' % float('9' * 51 + 'e-39'))")
```
---
    1.00e+12

### forty digits of a tenth

```python
(python-run "print('%.40g' % 1e-1)")
```
---
    0.1000000000000000055511151231257827021182

## the specials

### inf and nan zero-pad like any number

```python
(python-run "print('%06e' % float('inf'))\nprint('%06e' % float('-inf'))\nprint('%06e' % float('nan'))")
```
---
```output
000inf
-00inf
000nan
```

## the contract

### percent-percent consumes nothing

```python
(python-run "print('100%% sure' % ())")
```
---
    100% sure

### too few arguments refuse

```python
(python-run "try:\n    '%d %d' % 1\nexcept TypeError:\n    print('TypeError')")
```
---
    TypeError

### too many arguments refuse

```python
(python-run "try:\n    '%d' % (1, 2)\nexcept TypeError:\n    print('TypeError')")
```
---
    TypeError

### an unknown conversion refuses

```python
(python-run "try:\n    '%y' % 1\nexcept ValueError:\n    print('ValueError')")
```
---
    ValueError
