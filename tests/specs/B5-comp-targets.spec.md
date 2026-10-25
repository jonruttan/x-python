# comprehension targets

A comprehension's `for` target may be a tuple, `for a, b in pairs`, and its
commas are the target's, not the separators of the list, call or dict the
comprehension sits in: `f(x for a, b in y)` is one argument.  The
expectations are CPython 3.14's.

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
