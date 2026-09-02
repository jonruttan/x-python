global declarations and duck-typed delegation (`python/parse.x`,
`python/runtime.x`): `global x` keeps x out of a function's local hoist;
`yield from` on a plain iterator object uses __next__/send/throw/close,
GeneratorExit closes it rather than throwing, a thrown class stays a class
until raised, and throwing a non-exception into a plain delegator is the
TypeError.  Every expectation is a real CPython output.

## global and delegation

### global

```python
(python-run "ret = None\ndef f():\n    global ret\n    ret = 5\n    x = 1\n    return x\nprint(f(), ret)\nclass MyIter:\n    def __iter__(self):\n        return self\n    def __next__(self):\n        raise StopIteration(42)\ndef gen4():\n    global ret\n    ret = yield from MyIter()\n    1//0\nret = None\ntry:\n    print(list(gen4()))\nexcept ZeroDivisionError:\n    print('ZeroDivisionError')\nprint(ret)\n")
```
---
```output
1 5
ZeroDivisionError
42
```

### duck throw and close

```python
(python-run "class Iter:\n    def __iter__(self):\n        return self\n    def __next__(self):\n        return 1\n    def throw(self, x):\n        print('throw', x)\n        return 456\n    def close(self):\n        print('close')\ndef gen():\n    yield from Iter()\ng = gen()\nprint(next(g))\ng.close()\ng = gen()\nprint(next(g))\nprint(g.throw(123))\ng.close()\ng = gen()\nprint(next(g))\nprint(g.throw(ZeroDivisionError))\ng.close()\ndef gen2():\n    try:\n        yield 123\n    except ValueError as e:\n        print('got ValueError from upstream!', repr(e.args))\n    yield 456\ng = gen2()\nprint(next(g))\nprint(g.throw(ValueError, None))\nclass Iter2:\n    def __iter__(self):\n        return self\n    def __next__(self):\n        return 1\ndef gen3():\n    yield from Iter2()\ng = gen3()\nprint(next(g))\ntry:\n    g.throw(123)\nexcept TypeError:\n    print('TypeError')\n")
```
---
```output
1
close
1
throw 123
456
close
1
throw <class 'ZeroDivisionError'>
456
close
123
got ValueError from upstream! ()
456
1
TypeError
```
