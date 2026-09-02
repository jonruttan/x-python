String formatting proper: `str.format()` and f-strings (`python/parse.x`
expands an f-string at parse time into a join of literal parts and
(%py-fmtfield EXPR conv SPEC) forms, re-tokenizing each field's expression in
place; `python/runtime.x` walks a `.format` template at run time), on one
shared format-spec engine -- [[fill]align][sign][#][0][width][,][.precision]
[type] -- whose float bodies are the %-operator's exact-digit ones. Star
parameters and call spread ride along because the corpus's format tests are
written with `def test(fmt, *args)` and `fmt.format(*args)`. Every
expectation is a real CPython output; two of them corrected assumptions
(specials zero-fill under format() too; the empty type goes scientific at
exponent p-1).

## star parameters and call spread

### a *rest parameter is a tuple; *xs spreads at a call, anywhere in the list

```python
(python-run "def f(a, *rest):\n    return (a, rest, len(rest))\nprint(f(1))\nprint(f(1, 2, 3))\nxs = [4, 5]\nprint(f(0, *xs))\nprint(f(*xs))\nprint(f(*xs, 9))\ndef g(*a):\n    return a\nprint(g(), g(1), g(*[1, 2], *(3, 4)))")
```
---
```output
(1, (), 0)
(1, (2, 3), 2)
(0, (4, 5), 2)
(4, (5,), 1)
(4, (5, 9), 2)
() (1,) (1, 2, 3, 4)
```

## str.format

### auto-numbering, indexes, conversions, escapes, string precision

```python
(python-run "print('{} {} {}'.format(1, 'two', 3.0))\nprint('{0} {1} {0}'.format('a', 'b'))\nprint('{!r} {!s}'.format('q', 'q'))\nprint('{{literal}} {}'.format(0))\nprint('{:.3}'.format('abcdef'), '{:5.3}|'.format('abcdef'))\nprint('{}'.format(None), '{}'.format([1, 2]), '{}'.format((1,)))")
```
---
```output
1 two 3.0
a b a
'q' q
{literal} 0
abc abc  |
None [1, 2] (1,)
```

### fill, alignment, sign, zero, grouping, bases

```python
(python-run "print('{:>8}|{:<8}|{:^8}|{:*^9}|{:08.3f}|{:+d}|{: d}|{:,}'.format('r', 'l', 'c', 'mid', 3.14159, 5, 5, 1234567))\nprint('{:x} {:X} {:o} {:b} {:#x} {:#o}'.format(255, 255, 8, 5, 255, 8))")
```
---
```output
       r|l       |   c    |***mid***|0003.142|+5| 5|1,234,567
ff FF 10 101 0xff 0o10
```

### field tails: attributes and items

```python
(python-run "class P:\n    def __init__(self):\n        self.real = 7\n        self.d = {'k': 'v'}\nprint('{0.real} {0.d[k]} {1[1]}'.format(P(), [9, 8]))")
```
---
    7 v 8

### nested fields take their width and precision from the following args

```python
(python-run "print('{:{}}|{:{}.{}}'.format('ab', 5, 3.14159, 8, 3))")
```
---
    ab   |    3.14

## the float presentation types

### MicroPython's string_format walk, first half

```python
(python-run "def test(fmt, *args):\n    print('{:8s}'.format(fmt) + '>' + fmt.format(*args) + '<')\ntest('{:10.4}', 123.456)\ntest('{:10.4e}', 123.456)\ntest('{:10.4e}', -123.456)\ntest('{:10.4f}', 123.456)\ntest('{:10.4f}', -123.456)\ntest('{:10.4g}', 123.456)\ntest('{:10.4g}', -123.456)\ntest('{:10.4n}', 123.456)\ntest('{:e}', 100)\ntest('{:f}', 200)\ntest('{:g}', 300)")
```
---
```output
{:10.4} >     123.5<
{:10.4e}>1.2346e+02<
{:10.4e}>-1.2346e+02<
{:10.4f}>  123.4560<
{:10.4f}> -123.4560<
{:10.4g}>     123.5<
{:10.4g}>    -123.5<
{:10.4n}>     123.5<
{:e}    >1.000000e+02<
{:f}    >200.000000<
{:g}    >300<
```

### second half: upper types, specials zero-fill, bools, a refused type

```python
(python-run "def test(fmt, *args):\n    print('{:8s}'.format(fmt) + '>' + fmt.format(*args) + '<')\ntest('{:10.4E}', 123.456)\ntest('{:10.4E}', -123.456)\ntest('{:10.4F}', 123.456)\ntest('{:10.4F}', -123.456)\ntest('{:10.4G}', 123.456)\ntest('{:10.4G}', -123.456)\ntest('{:06e}', float('inf'))\ntest('{:06e}', float('-inf'))\ntest('{:06e}', float('nan'))\ntest('{:f}', False)\ntest('{:f}', True)\ntry:\n    '{:10.1b}'.format(0.0)\nexcept ValueError:\n    print('ValueError')")
```
---
```output
{:10.4E}>1.2346E+02<
{:10.4E}>-1.2346E+02<
{:10.4F}>  123.4560<
{:10.4F}> -123.4560<
{:10.4G}>     123.5<
{:10.4G}>    -123.5<
{:06e}  >000inf<
{:06e}  >-00inf<
{:06e}  >000nan<
{:f}    >0.000000<
{:f}    >1.000000<
ValueError
```

### percent, and g at the corpus's precisions

```python
(python-run "for num in (0.1, 0.58, 0.99, -0.1, -0.58, -0.99):\n    print('{:.1%}'.format(num))\nprint('{:.1%} {:.2%}'.format(0.58, 1))\nprint('{:.7g} {:.7g} {:.12e}'.format(1e10, 123456789.0, 1e200))")
```
---
```output
10.0%
58.0%
99.0%
-10.0%
-58.0%
-99.0%
58.0% 100.00%
1e+10 1.234568e+08 1.000000000000e+200
```

### the empty type: repr without precision, g-like with, one digit kept, 0.0 at .1 is 0e+00

```python
(python-run "print('{:10.4} {:.4} {:.4} {:.1}'.format(100.0, 1.0, 1e20, 0.0))")
```
---
         100.0 1.0 1e+20 0e+00

## f-strings

### expressions, conversions, specs, escaped braces

```python
(python-run "x = 42\nname = 'w'\nprint(f'x={x} {name!r} {x:04d} {x*2} {{x}} {x:>6}|')\nprint(f'{1+1}{\"s\"}')")
```
---
```output
x=42 'w' 0042 84 {x}     42|
2s
```

### nested replacement fields in the spec

```python
(python-run "space = 5\nprec = 2\nprint(f'{3.14:{space}.{prec}}')\nspace_prec = '5.2'\nprint(f'{3.14:{space_prec}}')")
```
---
```output
  3.1
  3.1
```

## characters

### the c type, chr and ord, code points not bytes

```python
(python-run "print(('{:c}'.format(65), '{:c}{:c}'.format(104, 105), chr(97), ord('A'), ord(chr(955)), '{:>3c}|'.format(66)))")
```
---
    ('A', 'hi', 'a', 65, 955, '  B|')
