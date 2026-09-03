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

## characters

### the c type, chr and ord, code points not bytes

```python
(python-run "print(('{:c}'.format(65), '{:c}{:c}'.format(104, 105), chr(97), ord('A'), ord(chr(955)), '{:>3c}|'.format(66)))")
```
---
    ('A', 'hi', 'a', 65, 955, '  B|')
