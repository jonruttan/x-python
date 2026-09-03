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
