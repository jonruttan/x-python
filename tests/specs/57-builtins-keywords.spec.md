Builtins (`python/runtime.x`, `python/parse.x`): bin/hex/oct over the
format engine's base conversion, divmod, three-argument pow, round of an
int to a negative digit (half to even); lazy enumerate/filter/map over
several iterables, reversed through __reversed__ or length+getitem,
sorted and min/max with key; callable, id, getattr with a default,
setattr, delattr, issubclass; class attributes and one-line class bodies.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## builtin keywords

### sorted and minmax

```python
(python-run "print(sorted(set(range(10))))\nprint(sorted(set(range(10)), key=lambda x: x + 100*(x % 2)))\nprint(sorted([3, 1, 2], reverse=True))\ntry:\n    sorted([], None)\nexcept TypeError:\n    print('TypeError')\nlst = [2, 1, 3, 4]\nprint(min(0, 1), max(0, 1), min(lst), max(lst))\nprint(min(lst, key=lambda x: -x), max(lst, key=lambda x: -x), min(1, 2, 3, 4, key=lambda x: -x))\nprint(min([], default=9), max([], default=-9))\ntry:\n    min([])\nexcept ValueError:\n    print('ValueError')\n")
```
---
```output
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
[0, 2, 4, 6, 8, 1, 3, 5, 7, 9]
[3, 2, 1]
TypeError
0 1 1 4
4 1 4
9 -9
ValueError
```

### rounding

```python
(python-run "for t in ((1, False), (1, True), (124, -1), (125, -1), (126, -1), (5, -1), (15, -1), (25, -1), (12345, 0), (12345, -1), (-1234, -1)):\n    print(round(t[0], t[1]))\n")
```
---
```output
1
1
120
120
130
0
20
20
12345
12340
-1230
```

### print keywords and super

```python
(python-run "print()\nprint(None)\nprint(1, 2)\nprint(sep='')\nprint(sep='x')\nprint(end='x\\n')\nprint(1, sep='', end='')\nprint(1, 2, sep='')\nprint([{1: 2}])\ntry:\n    super(str, 0)\nexcept TypeError:\n    print('TypeError')\ntry:\n    super(0, int)\nexcept TypeError:\n    print('TypeError')\n")
```
---
```output

None
1 2


x
112
[{1: 2}]
TypeError
TypeError
```
