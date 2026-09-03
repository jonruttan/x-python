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

## generator protocol

### return value and throw

```python
(python-run "def gen():\n    yield 1\n    return 42\ng = gen()\nprint(next(g))\ntry:\n    print(next(g))\nexcept StopIteration as e:\n    print(type(e), e.args)\ntry:\n    print(next(g))\nexcept StopIteration as e:\n    print(type(e), e.args)\ndef gen2():\n    yield 123\n    yield 456\ng = gen2()\nprint(next(g))\ntry:\n    g.throw(KeyError)\nexcept KeyError:\n    print('got KeyError from downstream!')\ndef gen3():\n    try:\n        yield 1\n        yield 2\n    except:\n        pass\ng = gen3()\nprint(next(g))\ntry:\n    g.throw(ValueError)\nexcept StopIteration:\n    print('got StopIteration')\ndef gen4():\n    try:\n        yield 123\n    except GeneratorExit as e:\n        print('GeneratorExit', repr(e.args))\n    yield 456\ng = gen4()\nprint(next(g))\nprint(g.throw(GeneratorExit))\n")
```
---
```output
1
<class 'StopIteration'> (42,)
<class 'StopIteration'> ()
123
got KeyError from downstream!
1
got StopIteration
123
GeneratorExit ()
456
```

### close

```python
(python-run "def gen1():\n    yield 1\n    yield 2\ng = gen1()\nprint(g.close())\ntry:\n    next(g)\nexcept StopIteration:\n    print('StopIteration')\ng = gen1()\nprint(next(g))\nprint(g.close())\ntry:\n    next(g)\n    print('No StopIteration')\nexcept StopIteration:\n    print('StopIteration')\ng = gen1()\nprint(list(g))\nprint(g.close())\ndef gen2():\n    try:\n        yield 1\n        yield 2\n    except:\n        print('raising GeneratorExit')\n        raise GeneratorExit\ng = gen2()\nprint(next(g))\nprint(g.close())\ndef gen3():\n    try:\n        yield 1\n    except:\n        pass\n    yield 2\ng = gen3()\nprint(next(g))\ntry:\n    g.close()\nexcept RuntimeError:\n    print('RuntimeError')\n")
```
---
```output
None
StopIteration
1
None
StopIteration
[1, 2]
None
1
raising GeneratorExit
None
1
RuntimeError
```

