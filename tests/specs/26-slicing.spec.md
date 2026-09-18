Slicing, for the three sequences.

A subscript group with a top-level `:` is a slice — a flat scan, since a nested
group is one token, so `d[{'a': 1}]`'s inner colon cannot mislead it. The rules
are stated once and used by str, list and tuple:

- a missing step is 1, and step 0 is a ValueError
- negative indices count from the end, after which anything still out of range
  **clamps** rather than raising — the deliberate difference between slicing
  and indexing
- a negative step defaults start to the last element and stop to before the
  first, which is how `[::-1]` reverses

## lists

### the basic forms

```python
(python-run "x = [0, 1, 2, 3, 4]\nprint(x[1:3])\nprint(x[:2])\nprint(x[2:])\nprint(x[:])")
```
---
```output
[1, 2]
[0, 1]
[2, 3, 4]
[0, 1, 2, 3, 4]
```

### steps, including the reversal

```python
(python-run "x = [0, 1, 2, 3, 4]\nprint(x[::2])\nprint(x[1::2])\nprint(x[::-1])")
```
---
```output
[0, 2, 4]
[1, 3]
[4, 3, 2, 1, 0]
```

### negative indices, and out-of-range clamps

`x[1:100]` answers what is there, and `x[10:20]` answers nothing — neither
raises, which is slicing's contract and not indexing's.

```python
(python-run "x = [0, 1, 2, 3, 4]\nprint(x[-2:])\nprint(x[:-1])\nprint(x[1:100])\nprint(x[10:20])")
```
---
```output
[3, 4]
[0, 1, 2, 3]
[1, 2, 3, 4]
[]
```

### a negative step walks its own bounds

```python
(python-run "x = [0, 1, 2, 3, 4]\nprint(x[4:1:-1])\nprint(x[3::-2])")
```
---
```output
[4, 3, 2]
[3, 1]
```

### the full slice is a copy, and the copy is independent

`lst[:]` is how Python spells a shallow copy, and the reason the result must be
a NEW list rather than the same instance.

```python
(python-run "a = [1, 2]\nb = a[:]\nb.append(3)\nprint(a)\nprint(b)")
```
---
```output
[1, 2]
[1, 2, 3]
```

## strings and tuples

### a string slice is a string

```python
(python-run "s = 'hello'\nprint(s[1:3])\nprint(s[::-1])\nprint(s[:2] + s[2:])")
```
---
```output
el
olleh
hello
```

### a tuple slice is a tuple

```python
(python-run "t = (1, 2, 3)\nprint(t[1:])\nprint(t[::-1])")
```
---
```output
(2, 3)
(3, 2, 1)
```

## refusals

### step zero raises

```python
(python-run "print([1][::0])")
```
---
    Error: #<err:value slice step cannot be zero>

### a dict does not slice: the slice is a key, and usually a missing one

Python 3.12 made a slice hashable, so this is a KeyError naming the key rather
than the TypeError older Pythons raised; 3.14 is what the corpus is generated
against.

```python
(python-run "d = {'a': 1}\ntry:\n    d[1:2]\nexcept KeyError as e:\n    print('KeyError', e.args)\nd[1:2] = 5\nprint(list(d.items()), d[1:2])")
```
---
```output
KeyError (slice(1, 2, None),)
[('a', 1), (slice(1, 2, None), 5)] 5
```

### a slice is an object, with attributes and indices()

```python
(python-run "class A:\n    def __getitem__(self, idx):\n        return idx\n\n    def __setitem__(self, idx, value):\n        print('set', idx, value)\n\n    def __delitem__(self, idx):\n        print('del', idx)\n\n\ns = A()[1:2:3]\nprint(s, type(s) is slice, s.start, s.stop, s.step)\nprint(A()[1:2], A()[:], A()[::-1], A()[5:])\nA()[4:5:6] = 7\ndel A()[7:8:9]\nprint(slice(3), slice(1, 5), slice(1, 5, 2))\nprint(slice(1, 2) == slice(1, 2), slice(1, 2) == slice(1, 3), slice(1, 2) == 5)\nprint(A()[:].indices(10), A()[2:].indices(10), A()[:7].indices(10))\nprint(A()[2:7:2].indices(10), A()[2:7:-2].indices(10), A()[7:2:2].indices(10))\nprint(A()[2:7:2].indices(5), A()[2:7:-2].indices(5), A()[7:2:-2].indices(5))\n\n\ndef err(f):\n    try:\n        f()\n    except (TypeError, ValueError, AttributeError) as e:\n        print(type(e).__name__)\n\n\nerr(lambda: A()[::].indices(None))\nerr(lambda: A()[::].indices(-1))\nerr(lambda: A()[::0].indices(5))\nerr(lambda: slice())\nerr(lambda: slice(1, 2, 3, 4))\nerr(lambda: A()[:].__setattr__('start', 0))")
```
---
```output
slice(1, 2, 3) True 1 2 3
slice(1, 2, None) slice(None, None, None) slice(None, None, -1) slice(5, None, None)
set slice(4, 5, 6) 7
del slice(7, 8, 9)
slice(None, 3, None) slice(1, 5, None) slice(1, 5, 2)
True False False
(0, 10, 1) (2, 10, 1) (0, 7, 1)
(2, 7, 2) (2, 7, -2) (7, 2, 2)
(2, 5, 2) (2, 4, -2) (4, 2, -2)
TypeError
ValueError
ValueError
TypeError
TypeError
AttributeError
```

### a subscript with a comma is a tuple, and its colons make slices

```python
(python-run "d = {(1, 2): \"x\", (1,): \"y\"}\nprint(d[1, 2], d[1,])\nd[3, 4] = \"z\"\nprint(d[(3, 4)], (3, 4) in d)\ndel d[3, 4]\nprint((3, 4) in d)\n\n\nclass A:\n    def __getitem__(self, i):\n        print(\"get\", i)\n        return i\n\n    def __setitem__(self, i, v):\n        print(\"set\", i, v)\n\n    def __delitem__(self, i):\n        print(\"del\", i)\n\n\na = A()\na[1, 2]\na[1:2, 4:5, 7:8]\na[1, 4:5, 7:8, 2]\na[1:2, a[3:4], 5:6]\na[::2, 1] = 9\ndel a[1:, :2]\nprint(A()[1 : A()[A()[2:3:4] : 5]])\nprint([1, 2, 3][1:], \"abc\"[::-1], [1, 2, 3][1])")
```
---
```output
x y
z True
False
get (1, 2)
get (slice(1, 2, None), slice(4, 5, None), slice(7, 8, None))
get (1, slice(4, 5, None), slice(7, 8, None), 2)
get slice(3, 4, None)
get (slice(1, 2, None), slice(3, 4, None), slice(5, 6, None))
set (slice(None, None, 2), 1) 9
del (slice(1, None, None), slice(None, 2, None))
get slice(2, 3, 4)
get slice(slice(2, 3, 4), 5, None)
get slice(1, slice(slice(2, 3, 4), 5, None), None)
slice(1, slice(slice(2, 3, 4), 5, None), None)
[2, 3] cba 2
```

### an index is an integer, and a bool is one

```python
(python-run "t = ((30, 63, 127), (62, 63, 127))\nprint(t[True][False], [1, 2][True], \"ab\"[True], b\"ab\"[True], bytearray(b\"ab\")[True], t[-True])\nl = [1, 2, 3]\nl[True] = 9\ndel l[False]\nprint(l)\nba = bytearray(b\"abc\")\nba[True] = 66\ndel ba[False]\nprint(ba)\n\n\ndef err(f):\n    try:\n        f()\n    except (TypeError, IndexError) as e:\n        print(type(e).__name__, e)\n\n\nerr(lambda: [1][1.5])\nerr(lambda: (1,)[\"a\"])\nerr(lambda: \"a\"[1.5])\nerr(lambda: \"\"[\"\"])\nerr(lambda: b\"a\"[1.5])\nerr(lambda: bytearray(b\"a\")[None])\nerr(lambda: [1][None])\nerr(lambda: [1][5])\nerr(lambda: \"ab\"[2])\n\n\ndef store():\n    l[1.5] = 0\n\n\ndef drop():\n    del l[None]\n\n\nerr(store)\nerr(drop)\nprint({True: \"t\"}[1], {1: \"one\"}[True])")
```
---
```output
62 2 b 98 98 (62, 63, 127)
[9, 3]
bytearray(b'Bc')
TypeError list indices must be integers or slices, not float
TypeError tuple indices must be integers or slices, not str
TypeError string indices must be integers, not 'float'
TypeError string indices must be integers, not 'str'
TypeError byte indices must be integers or slices, not float
TypeError bytearray indices must be integers or slices, not NoneType
TypeError list indices must be integers or slices, not NoneType
IndexError list index out of range
IndexError string index out of range
TypeError list indices must be integers or slices, not float
TypeError list indices must be integers or slices, not NoneType
t one
```
