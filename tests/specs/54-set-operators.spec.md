Sets (`python/types.x`, `python/runtime.x`, `python/parse.x`): PY-SET is a
list of distinct elements in insertion order behind a cell, with a frozen
bit for frozenset.  Membership is Python's equality, so {False, 0} is one
element; braces are a dict only with a colon or when empty; the methods,
the operators, hashability (a frozenset hashes, a set does not) and
iteration are here.  Also `for i in s, t:` over a bare tuple, and
list.sort()/reverse().  Every expectation is a real CPython output.

Split across files because a set program rebuilds whole element lists and
the batch runner never collects.

## set operators

### frozenset

```python
(python-run "s = frozenset()\nprint(s)\nprint(frozenset({1}))\nprint(sorted(frozenset({3, 4, 3, 1})))\nprint({frozenset('1'): 2})\ntry:\n    hash(set('abc'))\nexcept TypeError:\n    print('TypeError')\nprint(hash(frozenset()) == hash(frozenset()))\nf = frozenset({1})\ntry:\n    f.add(2)\nexcept AttributeError:\n    print('AttributeError')\nprint(sorted(f.union({2})), f == frozenset({1}), {1} == {1}, {1} == {2}, {1} != {2})\n")
```
---
```output
frozenset()
frozenset({1})
[1, 3, 4]
{frozenset({'1'}): 2}
TypeError
True
AttributeError
[1, 2] True True False True
```
### operators

```python
(python-run "a = {1, 2, 3}\nb = {2, 3, 4}\nprint(sorted(a | b), sorted(a & b), sorted(a - b), sorted(a ^ b))\nprint({1} <= {1, 2}, {1, 2} <= {1}, {1} < {1}, {1} < {1, 2}, {1, 2} >= {1}, {1, 2} > {1, 2})\nf = frozenset({1})\nprint(type(f | {2}) == frozenset, type({2} | f) == set)\ntry:\n    {1} | [2]\nexcept TypeError:\n    print('TypeError')\nprint(sorted({1, 2} - {2}), len({1} | {1}))\n")
```
---
```output
[1, 2, 3, 4] [2, 3] [1] [1, 4]
True False False True True False
True True
TypeError
[1] 1
```

### for over a bare tuple and list sort

```python
(python-run "s = {1, 2}\nt = s.copy()\ns.add(5)\nfor i in s, t:\n    print(sorted(i))\nl = list({4, 1, 3})\nl.sort()\nprint(l)\nl.reverse()\nprint(l)\nfor a, b in (1, 2), (3, 4):\n    print(a, b)\n")
```
---
```output
[1, 2, 5]
[1, 2]
[1, 3, 4]
[4, 3, 1]
1 2
3 4
```
