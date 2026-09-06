Containers (`python/types.x`, `python/runtime.x`, `python/parse.x`): dict
views as a named snapshot (dict_keys([...])), the dict method surface,
dict.fromkeys, dict(...) from pairs and from keywords, `|` and `|=`; the
list method surface, slice assignment and `del`, list concatenation and
repetition, and lexicographic ordering for lists and tuples.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## dict construction

### construction and union

```python
(python-run "print(dict(), dict({'a': 1}), dict([(1, 'foo')]), dict(a=1), dict({'a': 1}, b=2))\nd = {1: 2}\nd.update({3: 4})\nd.update([(5, 6)])\nprint(sorted(d.items()))\nd |= {7: 8}\nprint(sorted(d.items()))\nprint({1: 1} | {2: 2}, {1: 1} | {1: 9})\nprint(dict.fromkeys([1, 2]), dict.fromkeys([1, 2], 42))\ntry:\n    dict(((1,),))\nexcept ValueError:\n    print('ValueError')\n")
```
---
```output
{} {'a': 1} {1: 'foo'} {'a': 1} {'a': 1, 'b': 2}
[(1, 2), (3, 4), (5, 6)]
[(1, 2), (3, 4), (5, 6), (7, 8)]
{1: 1, 2: 2} {1: 9}
{1: None, 2: None} {1: 42, 2: 42}
ValueError
```

### identity and errors

```python
(python-run "d = {}\nd[False] = 'false'\nd[0] = 'zero'\nprint(d)\nprint({} == {1:1}, {1:1} == {1:1}, {1:1} == {2:1})\ntry:\n    {}[0]\nexcept KeyError as er:\n    print('KeyError', er, er.args)\ntry:\n    {} + {}\nexcept TypeError:\n    print('TypeError')\ndel d[False]\nprint(d)\ntry:\n    del d[9]\nexcept KeyError:\n    print('KeyError')\n")
```
---
```output
{False: 'zero'}
False True False
KeyError 0 (0,)
TypeError
{}
KeyError
```
