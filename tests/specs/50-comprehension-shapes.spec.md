Generators (`python/types.x`, `python/runtime.x`, `python/parse.x`): a
generator is two re-entrant continuations -- the engine's call/cc copies
the C stack -- so `yield` suspends the body and next()/send()/throw()
resume it; a for loop pulls one value at a time, so a body's prints
interleave with the loop's; return values ride StopIteration; close() is a
thrown GeneratorExit; `yield from` delegates send and throw and answers
the sub-generator's return value; generator expressions are a comprehension
whose action is a yield.  Also next()/iter()/sum() and `is`/`is not`.
Every expectation is a real CPython output.
Split into small files ON PURPOSE: every yield copies the C stack, the
batch runner never collects, and a dozen generator cases in one process
cross the allocation ceiling.

## comprehension shapes

### listcomp with operator element

```python
(python-run "print([v * 2 for v in range(3)])\n")
```
---
```output
[0, 2, 4]
```

### genexp with operator element in list()

```python
(python-run "print(list(x * x for x in range(4)))\n")
```
---
```output
[0, 1, 4, 9]
```

### genexp with if clause in sum()

```python
(python-run "print(sum(x for x in range(5) if x % 2))\n")
```
---
```output
4
```

### genexp over a string in tuple()

```python
(python-run "print(tuple(c for c in 'ab'))\n")
```
---
```output
('a', 'b')
```

### two args one a generator

```python
(python-run "def f(n):\n    yield n\nprint(list(f(2)), 1)\n")
```
---
```output
[2] 1
```

### listcomp over a generator

```python
(python-run "def f(n):\n    yield n\n    yield n + 1\nprint([v * 2 for v in f(2)])\n")
```
---
```output
[4, 6]
```

### sum of range

```python
(python-run "print(sum(range(3)), sum([1, 2], 10))\n")
```
---
```output
3 13
```

### a comprehension reads a generator or an iterator a step at a time, its prints in step

```python
(python-run "def src50():\n    for i in range(3):\n        print(\"yield\", i)\n        yield i\n\n\ndef f50(x):\n    print(\"f\", x)\n    return x * 10\n\n\nprint([f50(x) for x in src50()])\nprint(sum(f50(x) for x in src50()))\nprint({x % 3 for x in src50()}, {x: x * x for x in src50()})\n\n\nclass It50:\n    def __init__(self):\n        self.n = 0\n\n    def __iter__(self):\n        return self\n\n    def __next__(self):\n        self.n += 1\n        print(\"next\", self.n)\n        if self.n > 2:\n            raise StopIteration\n        return self.n\n\n\nprint([v * 2 for v in It50()])\nit50 = iter([1, 2, 3, 4])\nprint([v for v in it50 if v < 3], list(it50))")
```
---
```output
yield 0
f 0
yield 1
f 1
yield 2
f 2
[0, 10, 20]
yield 0
f 0
yield 1
f 1
yield 2
f 2
30
yield 0
yield 1
yield 2
yield 0
yield 1
yield 2
{0, 1, 2} {0: 0, 1: 1, 2: 4}
next 1
next 2
next 3
[2, 4]
[1, 2] []
```

### a generator expression over range(10**20) ends where its consumer stops

```python
(python-run "g51 = (x * 2 for x in range(10**20))\nprint(next(g51), next(g51), any(x > 2 for x in range(10**20)), all(x < 2 for x in range(10**20)))\nprint([(a, b) for a, b in zip(range(10**20), \"ab\")], [a + b for a, b in [(1, 2), (4, 5)]])\nprint([(i, j) for i in range(3) for j in range(i)], [y for x in [[1, 2], [3]] for y in x if y != 2])\nprint([c for c in \"ab\"], [k for k in {\"x\": 1, \"y\": 2}], [b for b in b\"hi\"], [r for r in range(5, 0, -2)])")
```
---
```output
0 2 True False
[(0, 'a'), (1, 'b')] [3, 9]
[(1, 0), (2, 0), (2, 1)] [1, 3]
['a', 'b'] ['x', 'y'] [104, 105] [5, 3, 1]
```
