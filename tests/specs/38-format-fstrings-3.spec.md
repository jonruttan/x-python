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

SPLIT FOUR WAYS to localise a CI-only death: this file, and only this
file, killed the CI host with exit 143 on every run, at the same
boundary, while passing locally on a v0.10.0 tree built exactly as CI
builds it.  Smaller processes also cost less, which is the standing
reason other heavy specs here are split.

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

