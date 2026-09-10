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

## generators

### interleaving and next

```python
(python-run "def f(x):\n    print('a')\n    y = x\n    print('b')\n    while y > 0:\n        print('c')\n        y -= 1\n        print('d')\n        yield y\n        print('e')\n    print('f')\n    return None\nfor val in f(2):\n    print(val)\nprint(repr(f(0))[0:17])\ng = f(1)\nprint(next(g))\ntry:\n    next(g)\nexcept StopIteration:\n    print('StopIteration')\nprint(next(g, 'dflt'))\nprint(list(f(2)), sum(f(3)), [v * 2 for v in f(2)])\n")
```
---
```output
a
b
c
d
1
e
c
d
0
e
f
<generator object
a
b
c
d
0
e
f
StopIteration
dflt
a
b
c
d
e
c
d
e
f
a
b
c
d
e
c
d
e
c
d
e
f
a
b
c
d
e
c
d
e
f
[1, 0] 3 [2, 0]
```

### send

```python
(python-run "def f():\n    n = 0\n    while True:\n        n = yield n + 1\n        print(n)\ng = f()\ntry:\n    g.send(1)\nexcept TypeError:\n    print('caught')\nprint(g.send(None))\nprint(g.send(100))\nprint(g.send(200))\n")
```
---
```output
caught
1
100
101
200
201
```


## a suspended body's cleanup is its own

A generator yields through a `try/finally` all the time, and a `yield` is a
SUSPENSION rather than an exit: Python does not run the `finally` when control
leaves at the yield, it runs it when the body is resumed and leaves the block
for good. So the cleanup a half-run body owes rides in the generator across the
suspension (python/types.x, the state's `winds`) instead of being left on the
stack of whoever is driving it — where the driver's next `break` or `return`
would have run it, early and in the wrong frame.

### a finally around a yield waits for the resume

```python
(python-run "def g():\n    for i in range(3):\n        try:\n            yield i\n        finally:\n            print('fin', i)\nfor v in g():\n    print('got', v)\nprint('after')")
```
---
```output
got 0
fin 0
got 1
fin 1
got 2
fin 2
after
```
