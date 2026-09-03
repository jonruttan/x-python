Sets (`python/types.x`, `python/runtime.x`, `python/parse.x`): PY-SET is a
list of distinct elements in insertion order behind a cell, with a frozen
bit for frozenset.  Membership is Python's equality, so {False, 0} is one
element; braces are a dict only with a colon or when empty; the methods,
the operators, hashability (a frozenset hashes, a set does not) and
iteration are here.  Also `for i in s, t:` over a bare tuple, and
list.sort()/reverse().  Every expectation is a real CPython output.

Split across files because a set program rebuilds whole element lists and
the batch runner never collects.

## sets

### literals and basics

```python
(python-run "s = {1}\nprint(s)\nprint(sorted({3, 4, 3, 1}))\nprint({1 + len(s)})\nprint(len({False, True, 0, 1, 2}))\ntry:\n    {s: 1}\nexcept TypeError:\n    print('TypeError')\nprint(set(), sorted(set('abc')), len(set('abc')), bool(set()), bool(set('abc')))\nprint({a for a in range(5)})\nprint(sorted({c for c in 'hello'}))\nprint(set)\nprint(type(set()) == set, type({None}) == set)\n")
```
---
```output
{1}
[1, 3, 4]
{2}
3
TypeError
set() ['a', 'b', 'c'] 3 False True
{0, 1, 2, 3, 4}
['e', 'h', 'l', 'o']
<class 'set'>
True True
```

### methods

```python
(python-run "s = {1, 2}\nprint(s.__contains__(1), s.__contains__(3), 1 in s, 3 in s, 3 not in s)\nprint(sorted({1}.union({2})), sorted({1, 2, 3}.intersection({2, 3, 4})), sorted({1, 2, 3}.difference({2})))\nprint(sorted({1, 2}.symmetric_difference({2, 3})), {1}.isdisjoint({2}), {1}.isdisjoint({1}))\nprint({1}.issubset({1, 2}), {1, 2}.issuperset({1}), sorted({1, 2}.copy()))\nt = {1, 2}\nt.add(3)\nt.discard(9)\nt.remove(1)\nprint(sorted(t))\ntry:\n    t.remove(99)\nexcept KeyError:\n    print('KeyError')\nu = {1}\nu.update({2, 3}, [4])\nprint(sorted(u))\nu.difference_update({4})\nu.intersection_update({1, 2, 3})\nu.symmetric_difference_update({3, 5})\nprint(sorted(u))\nu.clear()\nprint(u, len(u))\n")
```
---
```output
True False True False True
[1, 2] [2, 3] [1, 3]
[1, 3] True False
True True [1, 2]
[2, 3]
KeyError
[1, 2, 3, 4]
[1, 2, 5]
set() 0
```

### pop and iteration

```python
(python-run "s = {1}\nprint(s.pop())\ntry:\n    print(s.pop(), '!!!')\nexcept KeyError:\n    pass\nelse:\n    print('Failed to raise KeyError')\nN = 11\ns = set(range(N))\nwhile s:\n    print(s.pop())\nfor i in range(N):\n    s.add(i)\nprint(sorted(s))\ni = iter(iter({1, 2, 3}))\nprint(sorted(i))\nprint(sorted([x for x in {1, 2, 3}]))\n")
```
---
```output
1
0
1
2
3
4
5
6
7
8
9
10
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
[1, 2, 3]
[1, 2, 3]
```

