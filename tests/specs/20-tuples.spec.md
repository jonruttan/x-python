Tuples, and the unpacking they exist for.

**The comma makes a tuple, not the parens.** `(x)` is just `x` in Python, so a
one-element tuple is spelled `(x,)` and that trailing comma is load-bearing — a
repr without it would print something that reads back as a different value.

A tuple is immutable, so unlike a list it needs no cell: nothing can change it,
so the elements sit directly in the payload and the instance IS the value. It is
still a type rather than a bare x list, because `()` and `None` are different
values in Python and would be the same nil here.

## literals

### a tuple

```python
(python-run "print((1, 2))")
```
---
    (1, 2)

### one element keeps its comma

```python
(python-run "print((1,))")
```
---
    (1,)

### parens alone are not a tuple

```python
(python-run "print((1))")
```
---
    1

### the empty tuple

```python
(python-run "print(())")
```
---
    ()

### and it is not None

```python
(python-run "print(len(()))")
```
---
    0

### nested

```python
(python-run "print((1, (2, 3)))")
```
---
    (1, (2, 3))

### inside other containers

```python
(python-run "print([(1, 2), (3,)])\nprint({'k': (1, 2)})")
```
---
```output
[(1, 2), (3,)]
{'k': (1, 2)}
```

### a bare tuple needs no parens

```python
(python-run "x = 1, 2\nprint(x)")
```
---
    (1, 2)

## operations

### subscript

```python
(python-run "print((10, 20)[1])")
```
---
    20

### negative subscript

```python
(python-run "print((10, 20)[-1])")
```
---
    20

### out of range

```python
(python-run "print((1,)[5])")
```
---
    Error: #<err:index tuple index out of range>

### len

```python
(python-run "print(len((1, 2, 3)))")
```
---
    3

### iteration

```python
(python-run "for x in (1, 2):\n    print(x)")
```
---
```output
1
2
```

### equality

```python
(python-run "print((1, 2) == (1, 2))")
```
---
    True

### a tuple is not a list

The sequences are the same and the types are not, which is Python's answer.

```python
(python-run "print((1, 2) == [1, 2])")
```
---
    False

### concatenation

```python
(python-run "print((1,) + (2,))")
```
---
    (1, 2)

### repetition

```python
(python-run "print((1,) * 3)")
```
---
    (1, 1, 1)

### lexicographic ordering

```python
(python-run "print((1, 2) < (1, 3))")
```
---
    True

## methods

### count and index

```python
(python-run "t = (1, 2, 3, 2)\nprint(t.count(2), t.count(9), t.index(2), t.index(2, 2), t.index(3, -2))\nb = (0, t, 0, t)\nprint(b.count(t), b.index(t))\nf = t.count\nprint(f(1))")
```
---
```output
2 0 1 3 2
2 1
1
```

### index raises for a value outside its range, and both check their arguments

```python
(python-run "t = (1, 2, 3)\ndef err(f):\n    try:\n        f()\n    except (AttributeError, TypeError, ValueError) as e:\n        print(type(e).__name__, e)\nerr(lambda: t.index(9))\nerr(lambda: t.index(3, 0, 2))\nerr(lambda: t.count())\nerr(lambda: t.index())\nerr(lambda: t.nosuch)")
```
---
```output
ValueError tuple.index(x): x not in tuple
ValueError tuple.index(x): x not in tuple
TypeError tuple.count() takes exactly one argument (0 given)
TypeError index expected at least 1 argument, got 0
AttributeError 'tuple' object has no attribute 'nosuch'
```

### count and index read off the class, a subclass and a namedtuple

```python
(python-run "from collections import namedtuple\nclass T(tuple):\n    pass\nP = namedtuple(\"P\", \"x y\")\nprint(tuple.count((1, 2, 1), 1), tuple.index((1, 2), 2), T.count(T((5, 5)), 5))\nprint(T((1, 2, 1)).count(1), T((1, 2)).index(2), P(1, 1).count(1), P(1, 2).index(2))")
```
---
```output
2 1 2
2 1 2 1
```

## unpacking

This is what tuples are for: it is how a Python function returns two things.

### two names

```python
(python-run "a, b = 1, 2\nprint(a)\nprint(b)")
```
---
```output
1
2
```

### from a function

```python
(python-run "def f():\n    return 1, 2\nx, y = f()\nprint(x)\nprint(y)")
```
---
```output
1
2
```

### a list unpacks too

```python
(python-run "a, b = [3, 4]\nprint(a)\nprint(b)")
```
---
```output
3
4
```

### swap

```python
(python-run "a = 1\nb = 2\na, b = b, a\nprint(a)\nprint(b)")
```
---
```output
2
1
```

### the count must match

Python is strict here, and it should be: a silent short walk would bind a name
to None and fail somewhere else entirely.

```python
(python-run "a, b, c = 1, 2")
```
---
    Error: #<err:value not enough values to unpack (expected 3, got 2)>

### and not exceed

```python
(python-run "a, b = 1, 2, 3")
```
---
    Error: #<err:value too many values to unpack (expected 2, got 3)>

### a non-iterable does not unpack

```python
(python-run "a, b = 5")
```
---
    Error: #<err:type cannot unpack non-iterable int object>

### for unpacks each item

The same rule applied once per iteration, so it reuses the same length check.

```python
(python-run "for a, b in [(1, 2), (3, 4)]:\n    print(a)\n    print(b)")
```
---
```output
1
2
3
4
```
