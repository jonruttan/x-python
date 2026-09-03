Builtins (`python/runtime.x`, `python/parse.x`): bin/hex/oct over the
format engine's base conversion, divmod, three-argument pow, round of an
int to a negative digit (half to even); lazy enumerate/filter/map over
several iterables, reversed through __reversed__ or length+getitem,
sorted and min/max with key; callable, id, getattr with a default,
setattr, delattr, issubclass; class attributes and one-line class bodies.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## more builtins

### enumerate filter reversed

```python
(python-run "print(list(enumerate([])), list(enumerate([1, 2, 3])), list(enumerate([1, 2, 3], 5)), list(enumerate([1, 2, 3], -5)))\nprint(list(enumerate([1, 2, 3], start=1)), list(enumerate(iterable=[1, 2, 3])), list(enumerate(iterable=[1, 2, 3], start=1)))\nfor i, v in enumerate('ab', 1):\n    print(i, v)\nprint(list(filter(lambda x: x & 1, range(-3, 4))), list(filter(None, range(-3, 4))))\nprint(list(reversed([])), list(reversed([1])), list(reversed([1, 2, 3])), list(reversed((1, 2, 3))))\nfor c in reversed('ab'):\n    print(c)\nfor i in reversed(range(3)):\n    print(i)\nclass R:\n    def __len__(self):\n        return 3\n    def __getitem__(self, i):\n        return i + 1\nprint(list(reversed(R())))\n")
```
---
```output
[] [(0, 1), (1, 2), (2, 3)] [(5, 1), (6, 2), (7, 3)] [(-5, 1), (-4, 2), (-3, 3)]
[(1, 1), (2, 2), (3, 3)] [(0, 1), (1, 2), (2, 3)] [(1, 1), (2, 2), (3, 3)]
1 a
2 b
[-3, -1, 1, 3] [-3, -2, -1, 1, 2, 3]
[] [1] [3, 2, 1] [3, 2, 1]
b
a
2
1
0
[3, 2, 1]
```

### chr ord map

```python
(python-run "print(chr(65))\ntry:\n    chr(0x110000)\nexcept ValueError:\n    print('ValueError')\nprint(ord('a'))\ntry:\n    ord('')\nexcept TypeError:\n    print('TypeError')\nprint(ord(b'a'), ord(b'\\x7f'), ord(b'\\x80'), ord(b'\\xff'))\nprint(list(map(lambda x: x & 1, range(-3, 4))), list(map(abs, range(-3, 4))))\nprint(list(map(tuple, [[i] for i in range(-3, 4)])), list(map(pow, range(4), range(4))))\n")
```
---
```output
A
ValueError
97
TypeError
97 127 128 255
[1, 0, 1, 0, 1, 0, 1] [3, 2, 1, 0, 1, 2, 3]
[(-3,), (-2,), (-1,), (0,), (1,), (2,), (3,)] [1, 1, 4, 27]
```

### hashing and pow

```python
(python-run "def gen():\n    yield\nprint(type(hash(gen)), type(hash(gen())), type(hash(())))\nprint(hash(False), hash(True))\nprint({(): 1}, {(1,): 1})\nprint(hash in {hash: 1})\nprint(pow(3, 4, 7), pow(1, 1, 1), pow(0, 1, 1), pow(1, 0, 2), pow(0, 0, 5), pow(3, 4))\n")
```
---
```output
<class 'int'> <class 'int'> <class 'int'>
0 1
{(): 1} {(1,): 1}
True
4 0 0 1 1 81
```
