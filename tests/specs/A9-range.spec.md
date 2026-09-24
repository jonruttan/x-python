# range

A range is its start, stop and step.  Its length, an item, a slice and
membership are arithmetic on the three, so `range(1 << 32)` costs what
`range(3)` does, and a loop reads one a step at a time.  Every expectation is
a real CPython output.

### a range prints as itself, and its length is arithmetic

```python
(python-run "r1 = range(1, 10, 3)\nprint(r1, range(4), range(0), range(5, 0, -1), str(range(2)), [range(2)])\nprint(len(r1), len(range(4, 1, -2)), len(range(1, 4, -1)), bool(range(0)), bool(r1))\ntry:\n    len(range(10**20))\nexcept OverflowError as e:\n    print(\"OverflowError\", e)\nprint(bool(range(10**20)), type(r1).__name__, isinstance(r1, range))")
```
---
```output
range(1, 10, 3) range(0, 4) range(0, 0) range(5, 0, -1) range(0, 2) [range(0, 2)]
3 2 0 False True
OverflowError Python int too large to convert to C ssize_t
True range True
```

### an item and a slice are computed from start and step

```python
(python-run "r2 = range(1, 100, 5)\nprint(r2[0], r2[-1], r2[3], range(10**20)[-1], range(0, 1 << 32)[-1])\nprint(r2[5:15:3], r2[15:5:-3], r2[::-1], range(4)[1:-2:2], range(4, 1)[:], range(7, -2, -4)[:])\nprint(list(range(7, -2, -4)[2:-2:]), r2[slice(2, 4)], range(4)[::-1])\nfor label, th in ((\"past the end\", lambda: range(4)[5]), (\"a str\", lambda: range(4)[\"a\"]),\n                  (\"zero step\", lambda: range(4)[::0])):\n    try:\n        th()\n    except (IndexError, TypeError, ValueError) as e:\n        print(label, type(e).__name__, e)")
```
---
```output
1 96 16 99999999999999999999 4294967295
range(26, 76, 15) range(76, 26, -15) range(96, -4, -5) range(1, 2, 2) range(4, 4) range(7, -5, -4)
[] range(11, 21, 5) range(3, -1, -1)
past the end IndexError range object index out of range
a str TypeError range indices must be integers or slices, not str
zero step ValueError slice step cannot be zero
```

### membership places an int by arithmetic and compares anything else

```python
(python-run "r3 = range(1, 10, 3)\nprint(4 in r3, 5 in r3, 10 in r3, 7 not in r3, True in range(3), 2.0 in range(3), \"a\" in range(3))\nprint(10**19 in range(10**20), 10**19 + 1 in range(0, 10**20, 2), -4 in range(0, -10, -2))\nprint(r3.count(4), r3.count(5), range(3).count(1.0), r3.index(7), range(3).index(2.0))\nfor label, th in ((\"int\", lambda: r3.index(5)), (\"float\", lambda: range(3).index(2.5))):\n    try:\n        th()\n    except ValueError as e:\n        print(label, \"ValueError\", e)")
```
---
```output
True False False False True True False
True False True
1 0 1 2 2
int ValueError range.index(x): x not in range
float ValueError sequence.index(x): x not in sequence
```

### ranges are equal when their items are, and then hash alike

```python
(python-run "print(range(0) == range(2, 1), range(0, 3, 2) == range(0, 4, 2), range(1, 2, 5) == range(1, 3, 9))\nprint(range(3) == range(3), range(3) != range(0, 3, 1), range(3) == [0, 1, 2], range(3) == (0, 1, 2))\nprint(hash(range(0)) == hash(range(5, 5)), hash(range(0, 3, 2)) == hash(range(0, 4, 2)))\nprint({range(3): \"a\"}[range(0, 3)], range(2) in {range(0, 2)})")
```
---
```output
True True True
True False False False
True True
a True
```

### a range is read a step at a time

```python
(python-run "it5 = iter(range(3))\nprint(type(it5).__name__, next(it5), next(it5), list(it5), list(it5))\nprint(list(reversed(range(1, 10, 3))), list(reversed(range(0))), type(reversed(range(3))).__name__)\nprint(list(range(3)), tuple(range(3, 0, -1)), sum(range(101)), max(range(7)), sorted(range(3, 0, -1)))\nprint(list(enumerate(range(2))), list(zip(range(3), \"ab\")), list(map(abs, range(-2, 1))))\na5, *b5 = range(4)\nprint(a5, b5)\nfor i5 in range(10**20):\n    if i5 == 2:\n        break\nprint(\"stopped at\", i5)\n\n\ndef g5():\n    yield from range(3)\n\n\nprint(list(g5()), [x * x for x in range(4)])\ntry:\n    next(range(3))\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
range_iterator 0 1 [2] []
[7, 4, 1] [] range_iterator
[0, 1, 2] (3, 2, 1) 5050 6 [1, 2, 3]
[(0, 0), (1, 1)] [(0, 'a'), (1, 'b')] [2, 1, 0]
0 [1, 2, 3]
stopped at 2
[0, 1, 2] [0, 1, 4, 9]
TypeError 'range' object is not an iterator
```

### start, stop and step, and what a range refuses

```python
(python-run "r6 = range(1, 2, 3)\nprint(r6.start, r6.stop, r6.step, range(5).start, range(5).step)\n\n\ndef store():\n    range(4).start = 0\n\n\ndef setitem():\n    range(1)[0] = 1\n\n\ndef delitem():\n    del range(3)[0]\n\n\nfor label, th in ((\"store\", store), (\"setitem\", setitem), (\"delitem\", delitem), (\"neg\", lambda: -range(1))):\n    try:\n        th()\n    except (AttributeError, TypeError) as e:\n        print(label, type(e).__name__)\nfor label, th in ((\"float\", lambda: range(1.5)), (\"zero step\", lambda: range(1, 2, 0)),\n                  (\"lt\", lambda: range(1) < range(2)), (\"add\", lambda: range(1) + range(2)),\n                  (\"no args\", lambda: range()), (\"four\", lambda: range(1, 2, 3, 4))):\n    try:\n        th()\n    except (TypeError, ValueError) as e:\n        print(label, type(e).__name__, e)")
```
---
```output
1 2 3 0 1
store AttributeError
setitem TypeError
delitem TypeError
neg TypeError
float TypeError 'float' object cannot be interpreted as an integer
zero step ValueError range() arg 3 must not be zero
lt TypeError '<' not supported between instances of 'range' and 'range'
add TypeError unsupported operand type(s) for +: 'range' and 'range'
no args TypeError range expected at least 1 argument, got 0
four TypeError range expected at most 3 arguments, got 4
```
