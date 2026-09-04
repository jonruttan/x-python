Containers (`python/types.x`, `python/runtime.x`, `python/parse.x`): dict
views as a named snapshot (dict_keys([...])), the dict method surface,
dict.fromkeys, dict(...) from pairs and from keywords, `|` and `|=`; the
list method surface, slice assignment and `del`, list concatenation and
repetition, and lexicographic ordering for lists and tuples.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## dict methods

### views

```python
(python-run "d = {1: 2}\nfor m in d.items, d.values, d.keys:\n    print(m())\n    print(list(m()))\nprint({1:1, 2:1}.values())\nfor e in ({}, {1: 2}, {1: 2, 3: 4}):\n    for op in (bool, len):\n        print(op(e.keys()), op(e.values()), op(e.items()))\ntry:\n    hash({}.keys())\nexcept TypeError:\n    print('TypeError')\nprint(type(hash({}.values())))\ntry:\n    {1:1}.values() + 1\nexcept TypeError:\n    print('TypeError')\n")
```
---
```output
dict_items([(1, 2)])
[(1, 2)]
dict_values([2])
[2]
dict_keys([1])
[1]
dict_values([1, 1])
False False False
0 0 0
True True True
1 1 1
True True True
2 2 2
TypeError
<class 'int'>
TypeError
```

### methods

```python
(python-run "d = {1: 2, 3: 4}\nprint(d.get(1), d.get(9), d.get(9, 'z'), d.setdefault(1, 'q'), d.setdefault(5, 'w'), sorted(d.items()))\nprint(d.pop(5), d.pop(9, 'none'))\ntry:\n    d.pop(9)\nexcept KeyError:\n    print('KeyError')\nels = []\ne = {1:2, 3:4}\nels.append(e.popitem())\nels.append(e.popitem())\nprint(len(e), sorted(els))\ntry:\n    e.popitem()\nexcept KeyError:\n    print('Raised KeyError')\n")
```
---
```output
2 None z 2 w [(1, 2), (3, 4), (5, 'w')]
w none
KeyError
0 [(1, 2), (3, 4)]
Raised KeyError
```
