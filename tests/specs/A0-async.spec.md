# async def, await, async for and async with

### a coroutine is driven by send, and await takes its value

```python
(python-run "def dec(f):\n    print('decorator')\n    return f\n\n@dec\nasync def foo():\n    print('foo')\n\ncoro = foo()\ntry:\n    coro.send(None)\nexcept StopIteration:\n    print('StopIteration')\n\nasync def abinary(n):\n    if n <= 0:\n        return 1\n    l = await abinary(n - 1)\n    r = await abinary(n - 1)\n    return l + 1 + r\n\no = abinary(3)\ntry:\n    while True:\n        o.send(None)\nexcept StopIteration as e:\n    print('finished', e.value)\n")
```
---
```output
decorator
foo
StopIteration
finished 15
```

### async for, over an object that answers __aiter__

```python
(python-run "class AW:\n    def __init__(self, obj):\n        self._obj = obj\n    def __aiter__(self):\n        print(\"aiter\")\n        return AWIt(self._obj)\n\nclass AWIt:\n    def __init__(self, obj):\n        self._it = iter(obj)\n    async def __anext__(self):\n        try:\n            value = next(self._it)\n        except StopIteration:\n            raise StopAsyncIteration\n        return value\n\ndef run(c):\n    print(\"== start ==\")\n    try:\n        c.send(None)\n    except StopIteration:\n        print(\"== finish ==\")\n\nasync def coro0():\n    async for letter in AW(\"abc\"):\n        print(letter)\n\nrun(coro0())\n\nasync def coro1(a):\n    async for letter in a:\n        print(letter)\n    print(\"done\")\n\nrun(coro1(AW(\"de\")))\n")
```
---
```output
== start ==
aiter
a
b
c
== finish ==
== start ==
aiter
d
e
done
== finish ==
```

### async with, on the way out and on the way through

```python
(python-run "class AContext:\n    async def __aenter__(self):\n        print('enter')\n        return 1\n    async def __aexit__(self, exc_type, exc, tb):\n        print('exit', exc_type, exc)\n\nasync def f():\n    async with AContext():\n        print('body')\n\no = f()\ntry:\n    o.send(None)\nexcept StopIteration:\n    print('finished')\n\nasync def g():\n    async with AContext() as ac:\n        print(ac)\n        raise ValueError('error')\n\no = g()\ntry:\n    o.send(None)\nexcept ValueError:\n    print('ValueError')\n\nasync def h():\n    for i in range(3):\n        async with AContext():\n            if i == 1:\n                break\n    return 'after'\n\no = h()\ntry:\n    o.send(None)\nexcept StopIteration as e:\n    print('returned', e.value)\n")
```
---
```output
enter
body
exit None None
finished
enter
1
exit <class 'ValueError'> error
ValueError
enter
exit None None
enter
exit None None
returned after
```

