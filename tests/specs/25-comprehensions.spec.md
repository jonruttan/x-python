List and dict comprehensions.

A comprehension is a bracket group whose contents contain a top-level `for` —
and since a nested group is one token here, "top-level" is a flat scan, not a
depth count. Every piece was already on the shelf: each `for` clause is the same
self-recursive loop the statement emits, each `if` clause asks `%py-truthy` as
every condition now does, and a tuple target is the same `%py-unpack` with the
same length check.

**The variable is a `let`, not a hoisted `set!`.** Python 3 gives a
comprehension its own scope — the hoisting the statement-level `for` needs is
precisely what this must NOT do.

## list comprehensions

### the basic shape

```python
(python-run "print([x * 2 for x in [1, 2, 3]])")
```
---
    [2, 4, 6]

### with a filter

```python
(python-run "print([x for x in range(10) if x % 3 == 0])")
```
---
    [0, 3, 6, 9]

### over a string, and over a dict's keys

```python
(python-run "print([c for c in 'abc'])\nd = {'a': 1, 'b': 2}\nprint([k for k in d])")
```
---
```output
['a', 'b', 'c']
['a', 'b']
```

### a tuple target unpacks each item

```python
(python-run "print([a + b for a, b in [(1, 2), (3, 4)]])")
```
---
    [3, 7]

### two fors nest, first outermost

```python
(python-run "print([y for x in [[1, 2], [3]] for y in x])")
```
---
    [1, 2, 3]

### clauses compose in source order

```python
(python-run "print([x + y for x in [1, 2] for y in [10, 20] if x + y > 12])")
```
---
    [21, 22]

### a comprehension may sit in the expression

```python
(python-run "print([[y for y in range(x)] for x in [2, 3]])")
```
---
    [[0, 1], [0, 1, 2]]

### or be the source

```python
(python-run "print([x for x in [i * i for i in range(4)]])")
```
---
    [0, 1, 4, 9]

### the variable neither leaks nor clobbers

Python 3's own scope rule, and the reason the binding is a `let`: the module's
`x` is untouched by the comprehension's.

```python
(python-run "x = 5\ny = [x for x in [9]]\nprint(x)\nprint(y)")
```
---
```output
5
[9]
```

### empty source, empty answer

```python
(python-run "print([x for x in []])")
```
---
    []

## dict comprehensions

### the basic shape

```python
(python-run "print({k: k * 2 for k in [1, 2]})")
```
---
    {1: 2, 2: 4}

### with a filter

```python
(python-run "print({c: 1 for c in 'aba' if c != 'b'})")
```
---
    {'a': 1}

### a duplicate key overwrites, keeping first position and last value

Building through the same store the language uses means Python's rule falls out
of `%py-dset` rather than needing a dedup pass — including the ordering half,
which a naive rebuild would get wrong.

```python
(python-run "print({c: i for i, c in [(0, 'a'), (1, 'a'), (2, 'b')]})")
```
---
    {'a': 1, 'b': 2}
