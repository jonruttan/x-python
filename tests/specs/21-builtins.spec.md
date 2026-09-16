The builtins the corpus actually reaches for.

Chosen by counting, not by guessing: across the 112 conformance files, `type`
appears in 28, `str` in 22, `list` and `repr` in 18 each, `hasattr` in 17. The
conformance score is low because the library SURFACE is thin, not because the
language is — a single case like `dict1.py` is a sixty-line program, and one
missing builtin scores the whole thing zero.

## str and repr

`str` and `repr` need a value **as a string**, and `%py-write` only emits — the
comment above it says so, and says why: rendering a number would need a
number-to-string conversion that layer does not have.

It does not need one. `(prim-ref 'io 'write-to-str)` runs the writer with its
sink redirected into a string, so a container's write handler — and the callback
into Python's repr it makes per element — lands in the string instead of on
stdout. Nested containers come out right for free, because the same handlers do
the same work.

### str of a number

```python
(python-run "print(str(42))")
```
---
    42

### str of a string has no quotes, repr has them

That difference is the whole distinction between the two builtins. x writes a
string with double quotes; Python's repr uses single, and its str uses none.

```python
(python-run "print(str('hi'))\nprint(repr('hi'))")
```
---
```output
hi
'hi'
```

### a container renders through its own write handler

```python
(python-run "print(str([1, 'a']))\nprint(str({'a': 1}))\nprint(str((1,)))")
```
---
```output
[1, 'a']
{'a': 1}
(1,)
```

### nested containers need no extra rule

```python
(python-run "print(str(['a', [1], {'k': (2,)}]))")
```
---
    ['a', [1], {'k': (2,)}]

### a float

```python
(python-run "print(str(1.5))")
```
---
    1.5

### the use that made it worth doing

Building a message is the commonest thing `str` is for, and it is why a program
that never mentions dicts still fails a dict case without it.

```python
(python-run "print('n=' + str(3))")
```
---
    n=3

### and the line from dict1.py that named it

```python
(python-run "d = {1: 0, 3: 3}\nprint(str(d) == '{1: 0, 3: 3}')")
```
---
    True

## list

`list(x)` takes anything iterable — which is exactly what `for` already asks
for, so it is that same function wrapped rather than a second notion of
iterability that could drift from it.

### of a string

```python
(python-run "print(list('abc'))")
```
---
    ['a', 'b', 'c']

### of a tuple

```python
(python-run "print(list((1, 2)))")
```
---
    [1, 2]

### of a dict, which gives its keys

```python
(python-run "print(list({'a': 1, 'b': 2}))")
```
---
    ['a', 'b']

### of a range

```python
(python-run "print(list(range(3)))")
```
---
    [0, 1, 2]

## hasattr

Defined in terms of `getattr`, as Python defines it: "does this raise?", not a
separate lookup. So anything reachable by attribute access is reachable here,
and the two cannot disagree.

### on a builtin's method

```python
(python-run "print(hasattr([], 'append'))\nprint(hasattr([], 'nope'))")
```
---
```output
True
False
```

### on an instance, for a field and a missing one

```python
(python-run "class C:\n    def __init__(self):\n        self.x = 1\nprint(hasattr(C(), 'x'), hasattr(C(), 'y'))")
```
---
    True False

## constructor arguments

A constructor that takes one iterable refuses a second argument; bytearray and
deque refuse more arguments than they name.

### refuse more arguments than they take

```python
(python-run "from collections import deque\ndef err(f):\n    try:\n        f()\n    except TypeError as e:\n        print(e)\nerr(lambda: list([1], [2]))\nerr(lambda: tuple([1], [2]))\nerr(lambda: set([1], [2]))\nerr(lambda: frozenset([1], [2]))\nerr(lambda: dict({}, {}))\nerr(lambda: bytearray(b\"a\", \"utf-8\", \"strict\", 4))\nerr(lambda: deque([], 1, 2))\nprint(list([1]), tuple(), set(), dict({\"a\": 1}), bytearray(b\"a\"), deque([1], 2))")
```
---
```output
list expected at most 1 argument, got 2
tuple expected at most 1 argument, got 2
set expected at most 1 argument, got 2
frozenset expected at most 1 argument, got 2
dict expected at most 1 argument, got 2
bytearray() takes at most 3 arguments (4 given)
deque() takes at most 2 arguments (3 given)
[1] () set() {'a': 1} bytearray(b'a') deque([1], maxlen=2)
```
