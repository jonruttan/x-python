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

