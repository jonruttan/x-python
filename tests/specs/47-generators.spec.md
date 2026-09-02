Generators (`python/types.x`, `python/runtime.x`, `python/parse.x`): a
generator is two re-entrant continuations -- the engine's call/cc copies
the C stack -- so `yield` suspends the body and next()/send()/throw()
resume it; a for loop pulls one value at a time, so a body's prints
interleave with the loop's; return values ride StopIteration; close() is a
thrown GeneratorExit; `yield from` delegates send and throw and answers
the sub-generator's return value; generator expressions are a comprehension
whose action is a yield.  Also next()/iter()/sum() and `is`/`is not`.
Every expectation is a real CPython output.

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
