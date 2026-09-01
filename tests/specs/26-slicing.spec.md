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

### a dict does not slice, with Python's own complaint

```python
(python-run "print({'a': 1}[1:2])")
```
---
    Error: #<err:type unhashable type: 'slice'>
