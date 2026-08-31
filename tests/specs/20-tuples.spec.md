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
    Error: #<err:value not enough values to unpack>

### and not exceed

```python
(python-run "a, b = 1, 2, 3")
```
---
    Error: #<err:value too many values to unpack>

### a non-sequence does not unpack

```python
(python-run "a, b = 5")
```
---
    Error: #<err:type cannot unpack non-sequence>

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

## except takes a tuple of classes

Python spells "any of these" with a tuple.

### the first matches

```python
(python-run "try:\n    raise ValueError('v')\nexcept (ValueError, KeyError) as e:\n    print(e)")
```
---
    v

### the second matches

```python
(python-run "try:\n    raise KeyError('k')\nexcept (ValueError, KeyError):\n    print('caught')")
```
---
    caught

### neither matches, so it travels

```python
(python-run "try:\n    raise TypeError('t')\nexcept (ValueError, KeyError):\n    print('no')")
```
---
    Error: TypeError: t
