Containers (`python/types.x`, `python/runtime.x`, `python/parse.x`): dict
views as a named snapshot (dict_keys([...])), the dict method surface,
dict.fromkeys, dict(...) from pairs and from keywords, `|` and `|=`; the
list method surface, slice assignment and `del`, list concatenation and
repetition, and lexicographic ordering for lists and tuples.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## list methods

### methods

```python
(python-run "a = [1, 2, 3]\nprint(a.index(1), a.index(3), a.index(3, 2), a.index(1, -100), a.index(1, False))\ntry:\n    a.index(1, True)\nexcept ValueError:\n    print('Raised ValueError')\nb = [1, 2, 3]\nb.extend([4, 5])\nb.insert(0, 0)\nb.insert(100, 9)\nprint(b, b.count(1), len(b))\nb.remove(9)\nprint(b, b.pop(), b.pop(0), b)\nc = b.copy()\nb.clear()\nprint(b, c)\nl = [1, 3, 2, 5]\nl.sort()\nprint(l)\nl.sort(key=lambda x: -x)\nprint(l)\nl.sort(reverse=True)\nprint(l)\n")
```
---
```output
0 2 2 0 0
Raised ValueError
[0, 1, 2, 3, 4, 5, 9] 1 7
[1, 2, 3, 4] 5 0 [1, 2, 3, 4]
[] [1, 2, 3, 4]
[1, 2, 3, 5]
[5, 3, 2, 1]
[5, 3, 2, 1]
```

### slices, del, concat and repeat

```python
(python-run "x = list(range(10))\nl = list(x)\nl[1:3] = [10, 20]\nprint(l)\nl = list(x)\nl[1:3] = []\nprint(l)\nl = list(x)\ndel l[1:3]\nprint(l)\nl = [1, 2, 3]\ndel l[0]\nprint(l)\nprint([1, 2] + [3], [0] * 3, 3 * [0], [1, 2] * 0, [1, 2] * -1)\nl = [1, 2]\nl += range(3, 5)\nl += 'ab'\nprint(l)\ntry:\n    [1] + (2,)\nexcept TypeError:\n    print('TypeError')\ntry:\n    [1] * 'a'\nexcept TypeError:\n    print('TypeError')\nprint([1, 2] < [1, 3], [1] < [1, 0], (1, 2) < (1, 3), sorted([(2, 'b'), (1, 'a')]))\n")
```
---
```output
[0, 10, 20, 3, 4, 5, 6, 7, 8, 9]
[0, 3, 4, 5, 6, 7, 8, 9]
[0, 3, 4, 5, 6, 7, 8, 9]
[2, 3]
[1, 2, 3] [0, 0, 0] [0, 0, 0] [] []
[1, 2, 3, 4, 'a', 'b']
TypeError
TypeError
True True True [(1, 'a'), (2, 'b')]
```
