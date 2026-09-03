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

## generator delegation

### exceptions across yield and yield from

```python
(python-run "def gen():\n    try:\n        yield 1\n        raise ValueError\n    except ValueError:\n        print('Caught')\n    yield 2\nfor i in gen():\n    print(i)\ndef gen2():\n    yield 1\n    raise ValueError\n    yield 2\ng = gen2()\nprint(next(g))\ntry:\n    print(next(g))\nexcept ValueError:\n    print('ValueError')\ntry:\n    print(next(g))\nexcept StopIteration:\n    print('StopIteration')\ndef sub():\n    yield 1\n    yield 2\n    return 3\ndef outer():\n    print('here1')\n    print((yield from sub()))\n    print('here2')\n    yield from [10, 20]\nprint(list(outer()))\ndef sub2():\n    x = yield 1\n    print('got', x)\n    yield 2\ndef outer2():\n    yield from sub2()\ng = outer2()\nprint(next(g))\nprint(g.send('S'))\n")
```
---
```output
1
Caught
2
1
ValueError
StopIteration
here1
3
here2
[1, 2, 10, 20]
1
got S
2
```

### generator expressions

```python
(python-run "print(','.join('abc' for i in range(3)))\nprint(list(x * x for x in range(4)), sum(x for x in range(5) if x % 2), tuple(c for c in 'ab'))\ng = (i for i in range(2))\nprint(next(g), next(g))\ntry:\n    next(g)\nexcept StopIteration:\n    print('done')\nprint(iter(g) is g)\n")
```
---
```output
abc,abc,abc
[0, 1, 4, 9] 4 ('a', 'b')
0 1
done
True
```

## comprehension shapes

