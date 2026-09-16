# the types module

### what a callable, a generator and a bound method answer to

```python
(python-run "import types\ndef _f(): pass\ndef _g(): yield 1\nclass _C:\n    def _m(self): pass\nprint(type(_f) is types.FunctionType, type(lambda: None) is types.LambdaType)\nprint(type(_g()) is types.GeneratorType, type(_C()._m) is types.MethodType)\nprint(type(len) is types.BuiltinFunctionType, type([].append) is types.BuiltinMethodType)\nprint(str(type(_f))[:8], str(type(len))[:8])\nprint(type(_f).__name__, type(_g()).__name__, type(_C()._m).__name__, type(len).__name__)\nprint(type(types) is types.ModuleType)\n")
```
---
```output
True True
True True
True True
<class ' <class '
function generator method builtin_function_or_method
True
```

### a plain generator, awaited

```python
(python-run "import types\ncoroutine = types.coroutine\n\n@coroutine\ndef wait(value):\n    print('wait value:', value)\n    msg = yield 'message from wait({})'.format(value)\n    print('wait got back:', msg)\n    return 10\n\nasync def f():\n    x = await wait(1)**2\n    print('x =', x)\n\ncoro = f()\nprint('return from send:', coro.send(None))\ntry:\n    coro.send('message from main')\nexcept StopIteration:\n    print('got StopIteration')\n")
```
---
```output
wait value: 1
return from send: message from wait(1)
wait got back: message from main
x = 100
got StopIteration
```

