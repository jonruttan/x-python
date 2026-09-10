# the with statement

### enter binds, exit follows

```python
(python-run "class C:\n    def __enter__(self):\n        print(\"enter\")\n        return self\n    def __exit__(self, a, b, c):\n        print(\"exit\", repr(a), repr(b))\nwith C() as x:\n    print(isinstance(x, C))")
```
---
```output
enter
True
exit None None
```

### what exit is told about an exception

DIVERGENCE, in the third argument.  Python hands __exit__ the exception's
class, the instance, and a TRACEBACK object; this runtime has no traceback
objects at all, so the third argument is None and `c is None` answers True
where CPython answers False.  The first two -- which is what a context manager
actually reads -- are the same.


```python
(python-run "class C:\n    def __enter__(self):\n        return self\n    def __exit__(self, a, b, c):\n        print(\"exit\", repr(a), repr(b), c is None)\ntry:\n    with C():\n        raise ValueError(\"v\")\nexcept ValueError:\n    print(\"propagated\")")
```
---
```output
exit <class 'ValueError'> ValueError('v') True
propagated
```

### a truthy exit swallows the exception

```python
(python-run "class Swallow:\n    def __enter__(self):\n        return 5\n    def __exit__(self, a, b, c):\n        print(\"swallow\", repr(a))\n        return True\nwith Swallow() as v:\n    print(\"v =\", v)\n    raise KeyError(\"k\")\nprint(\"after\")")
```
---
```output
v = 5
swallow <class 'KeyError'>
after
```

### several managers nest

```python
(python-run "class M:\n    def __init__(self, n):\n        self.n = n\n    def __enter__(self):\n        print(\"enter\", self.n)\n        return self.n\n    def __exit__(self, a, b, c):\n        print(\"exit\", self.n)\nwith M(1) as a, M(2) as b:\n    print(\"body\", a, b)")
```
---
```output
enter 1
enter 2
body 1 2
exit 2
exit 1
```

### a raise inside enter, and inside exit

```python
(python-run "class BadEnter:\n    def __enter__(self):\n        raise RuntimeError(\"in enter\")\n    def __exit__(self, a, b, c):\n        print(\"exit should not run\")\ntry:\n    with BadEnter():\n        print(\"body should not run\")\nexcept RuntimeError as e:\n    print(\"enter raised:\", e)\nclass BadExit:\n    def __enter__(self):\n        return self\n    def __exit__(self, a, b, c):\n        raise RuntimeError(\"in exit\")\ntry:\n    with BadExit():\n        print(\"body ran\")\nexcept RuntimeError as e:\n    print(\"exit raised:\", e)")
```
---
```output
enter raised: in enter
body ran
exit raised: in exit
```

### an object without the protocol

```python
(python-run "try:\n    with 42:\n        print(\"no\")\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
TypeError
```

### the exception from the runtime, not from source

```python
(python-run "class C:\n    def __enter__(self):\n        return self\n    def __exit__(self, a, b, c):\n        print(\"exit\", a.__name__)\n        return True\nwith C():\n    d = {}\n    d[\"missing\"]\nprint(\"after\")")
```
---
```output
exit KeyError
after
```
