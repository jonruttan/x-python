# for targets

A `for` target, a comprehension's or a statement's, is an assignment target:
a tuple, `for a, b in pairs`, a nested or starred one, `for (a, b), *c in
rows`, or a subscript.  Its commas are the target's, not the separators of
the list, call or dict a comprehension sits in: `f(x for a, b in y)` is one
argument.  The expectations are CPython 3.14's.

## tuple targets

### in a bare generator argument, a named one, and each display

```python
(python-run "pairs = [(1, 2), (3, 4), (5, 6)]\nprint(sum(a * b for a, b in pairs))\nprint(all(b == a + 1 for a, b in pairs), any(a > b for a, b in pairs))\nprint(list(b for a, b in pairs), sorted((b, a) for a, b in pairs))\nprint(max(a + b for a, b in pairs if a > 1))\nprint(dict((b, a) for a, b in pairs))\nprint({b: a for a, b in pairs}, [a for a, b in pairs], sorted({a + b for a, b in pairs}))\nprint([x + y for x, y in pairs for _ in range(2)])\ng = (a - b for a, b in pairs)\nprint(next(g), list(g))\nprint(tuple(k for k, v in {\"p\": 1, \"q\": 2}.items()), \"-\".join(k * v for k, v in {\"p\": 1, \"q\": 2}.items()))")
```
---
```output
44
True False
[2, 4, 6] [(2, 1), (4, 3), (6, 5)]
11
{2: 1, 4: 3, 6: 5}
{2: 1, 4: 3, 6: 5} [1, 3, 5] [3, 7, 11]
[3, 3, 7, 7, 11, 11]
-1 [-1, -1]
('p', 'q') p-qq
```

## nested and starred targets

A target may be any assignment target: parenthesized, nested, starred, or a
subscript.  A comprehension binds its names in its own scope, a `for`
statement in the enclosing one, where they outlive the loop.

### in comprehensions

```python
(python-run "pairs = [(1, 2), (3, 4), (5, 6)]\nprint(list((a, b, c) for (a, b), c in zip(pairs, \"xyz\")))\nprint([a for (a, b) in pairs], [b for [a, b] in pairs], [a for (a) in [7, 8]])\nprint({c: a + b for (a, b), c in zip(pairs, \"xyz\")})\nprint([(h, t) for h, *t in [(1, 2, 3), (4,), (5, 6)]])\nprint([m for *_, m in pairs], sorted({x for (x, _), _ in zip(pairs, pairs)}))\nprint([x * y for (x, y) in pairs if x > 1 for _ in range(2)])")
```
---
```output
[(1, 2, 'x'), (3, 4, 'y'), (5, 6, 'z')]
[1, 3, 5] [2, 4, 6] [7, 8]
{'x': 3, 'y': 7, 'z': 11}
[(1, [2, 3]), (4, []), (5, [6])]
[2, 4, 6] [1, 3, 5]
[12, 12, 30, 30]
```

### in a for statement

```python
(python-run "for (a, b), c in zip([(1, 2), (3, 4)], \"xy\"):\n    print(a, b, c)\nfor [p, q] in [[5, 6]]:\n    print(p + q)\nfor h, *t in [(1, 2, 3), (4,)]:\n    print(h, t)\nd = {}\nfor d[\"k\"] in [1, 2]:\n    pass\nprint(d, a, b, c, h, t)\ndef f(rows):\n    total = 0\n    for (x, y), z in rows:\n        total += x * y + z\n    return total, x, y, z\nprint(f([((1, 2), 3), ((4, 5), 6)]))\ntry:\n    for (a, b) in [(1, 2, 3)]:\n        pass\nexcept ValueError as e:\n    print(e)")
```
---
```output
1 2 x
3 4 y
11
1 [2, 3]
4 []
{'k': 2} 3 4 y 4 []
(31, 4, 5, 6)
too many values to unpack (expected 2, got 3)
```
