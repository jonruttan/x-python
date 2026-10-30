# an exception class with its own __new__

A class whose `__new__` answers another exception raises that one, and one
whose `__new__` answers anything else is a TypeError, as raising a
non-exception is -- worded as CPython words it for a raise and for a
generator's throw().  An error the runtime raised is an instance in its
handler, with its args, and a `**` that spreads nothing is a plain call.
The expectations are CPython 3.14's.

## exception __new__

### __new__ answering another exception, or a number

```python
(python-run "class Dummy(BaseException):\n    pass\nd = Dummy(\"m\")\nprint(type(d).__name__, d.args)\nclass G(BaseException):\n    def __new__(cls, *args, **kwargs):\n        return Dummy(*args, **kwargs)\ng = G(\"x\")\nprint(type(g).__name__, g.args)\ntry:\n    raise G(\"y\")\nexcept BaseException as e:\n    print(type(e).__name__, e.args)\nclass H(Exception):\n    def __new__(cls, *args):\n        o = super().__new__(cls, *args)\n        o.extra = 1\n        return o\nh = H(\"z\", 2)\nprint(h.args, h.extra)\nclass B(BaseException):\n    def __new__(cls, *args):\n        return 1\ntry:\n    raise B(\"bad\")\nexcept Exception as e:\n    print(type(e).__name__, e.args)")
```
---
```output
Dummy ('m',)
Dummy ('x',)
Dummy ('y',)
('z', 2) 1
TypeError ('exceptions must derive from BaseException',)
```

### raising what is not an exception, and throwing it

```python
(python-run "class B(BaseException):\n    def __new__(cls, *args):\n        return 1\ntry:\n    raise 1\nexcept Exception as e:\n    print(type(e).__name__, e.args)\nb = B(\"bad\")\nprint(b)\ntry:\n    raise b\nexcept Exception as e:\n    print(type(e).__name__)\n    print(e.args)\ntry:\n    raise B(\"bad\")\nexcept Exception as e:\n    print(type(e).__name__)\n    print(e.args)\ntry:\n    raise B\nexcept Exception as e:\n    print(type(e).__name__)\n    print(e.args)\ndef gen():\n    yield\ntry:\n    gen().throw(B)\nexcept Exception as e:\n    print(type(e).__name__)\n    print(e.args)\ntry:\n    gen().throw(ValueError)\nexcept ValueError as e:\n    print(type(e).__name__, e.args)")
```
---
```output
TypeError ('exceptions must derive from BaseException',)
1
TypeError
('exceptions must derive from BaseException',)
TypeError
('exceptions must derive from BaseException',)
TypeError
("calling <class '__main__.B'> should have returned an instance of BaseException, not <class 'int'>",)
TypeError
("calling <class '__main__.B'> should have returned an instance of BaseException, not int",)
ValueError ()
```

### a runtime error caught by name, and an empty **

```python
(python-run "try:\n    [][1]\nexcept IndexError as e:\n    print(type(e).__name__, e.args, str(e), isinstance(e, LookupError))\ntry:\n    1 + \"a\"\nexcept TypeError as e:\n    print(type(e).__name__, len(e.args), type(e.args[0]).__name__)\ndef f(*a, **k):\n    return a, k\nprint(f(*(1, 2), **{}), int(*(\"7\",), **{}), \"ab\".upper(**{}))")
```
---
```output
IndexError ('list index out of range',) list index out of range True
TypeError 1 str
((1, 2), {}) 7 AB
```
