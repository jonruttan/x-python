# attribute hooks, and the exceptions the corpus catches

### the exception names the corpus catches

```python
(python-run "print(ImportError.__name__, MemoryError.__name__, OverflowError.__name__)\nprint(NotImplementedError.__name__, StopAsyncIteration.__name__, BaseException.__name__)\ntry:\n    raise ImportError(\"no module\")\nexcept ImportError as e:\n    print(\"ImportError\", e)\ntry:\n    raise NotImplementedError(\"later\")\nexcept RuntimeError:\n    print(\"caught as RuntimeError\")\ntry:\n    raise OverflowError(\"big\")\nexcept ArithmeticError:\n    print(\"caught as ArithmeticError\")")
```
---
```output
ImportError MemoryError OverflowError
NotImplementedError StopAsyncIteration BaseException
ImportError no module
caught as RuntimeError
caught as ArithmeticError
```

### every exception is a BaseException

```python
(python-run "try:\n    raise ValueError(\"v\")\nexcept BaseException as e:\n    print(\"BaseException caught\", type(e).__name__)\nprint(issubclass(Exception, BaseException), issubclass(ValueError, BaseException))")
```
---
```output
BaseException caught ValueError
True True
```

### __setattr__ intercepts every store

```python
(python-run "class A:\n    def __getattr__(self, attr):\n        print('get', attr)\n        return 1\n    def __setattr__(self, attr, val):\n        print('set', attr, val)\n    def __delattr__(self, attr):\n        print('del', attr)\na = A()\nprint(a.foo)\na.bar = 2\ndel a.baz")
```
---
```output
get foo
1
set bar 2
del baz
```

### without the hooks a store is a store

```python
(python-run "class B:\n    pass\nb = B()\nb.x = 1\nprint(b.x)\ndel b.x\nprint(hasattr(b, 'x'))")
```
---
```output
1
False
```
