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

### adjacent literals join, and one f-string makes the run one

```python
(python-run "x, y = 1, 2\nprint(f\"\" f\"\")\nprint(f\"a\" f\"b\")\nprint(f\"{x}\" f\"{y}\")\nprint(\"a\" f\"{x}\" \"b\")\nprint(f\"{x}\" \"a{}b\" f\"{y}\")\nprint(\n    f\"a{x}b-\"\n    f\"cd-\"\n    f\"e{y}f\"\n)\nprint(f\"a\" \"b\" f\"c\" '''d''' rf\"\\n\" \"e\")\nprint(\"plain\" \"join\")\nprint(f\"{x}{{}}\" \"{}\")\ntry:\n    eval(\"f'{{}'\")\nexcept (ValueError, SyntaxError):\n    print(\"SyntaxError\")\ntry:\n    eval('f\"}\"')\nexcept (ValueError, SyntaxError):\n    print(\"SyntaxError\")\nprint(f\"{x=}\", f\"{'q'!r:>5}\")")
```
---
```output

ab
12
a1b
1a{}b2
a1b-cd-e2f
abcd\ne
plainjoin
1{}{}
SyntaxError
SyntaxError
x=1   'q'
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

