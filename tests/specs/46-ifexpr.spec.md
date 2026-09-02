Conditional expressions (`python/parse.x`): `a if c else b` above `or`,
right-associative, only the chosen branch evaluated; a comprehension's
iterable and clause conditions stay one level down, where `if` opens a
clause.  Every expectation is a real CPython output.

## ifexpr

### conditional expressions

```python
(python-run "def fact(n):\n    return 1 if n <= 1 else n * fact(n - 1)\nprint(fact(5), fact(0))\nx = 3\nprint(1 if x > 2 else 2, 'a' if x else 'b', x if 0 else -x)\ny = 'small' if x < 2 else 'medium' if x < 5 else 'large'\nprint(y)\nprint([v if v % 2 else -v for v in range(5)])\nprint([v for v in range(6) if v > 3])\nprint({k: (1 if k else 0) for k in (0, 1)})\n")
```
---
```output
120 1
1 a -3
medium
[0, 1, -2, 3, -4]
[4, 5]
{0: 0, 1: 1}
```

### only the truthy branch evaluates

```python
(python-run "def boom():\n    raise ValueError\nprint(1 if True else boom())\nprint(boom() if False else 2)\nprint(0 if [] else 'empty', 0 if [0] else 'empty')\nz = 5\nz += 1 if z else 100\nprint(z)\n")
```
---
```output
1
2
empty 0
6
```
