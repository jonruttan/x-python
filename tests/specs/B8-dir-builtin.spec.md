# dir() of a builtin type

A builtin type's methods are reached by type, not stored on its class, so
dir() lists them from CPython's names for the type -- the ones this runtime
answers.  A value is listed as its type is, a subclass adds its own names to
the type's, and the runtime's own %-rows are never listed.  The expectations
are CPython 3.14's.

## dir

### a type, a value, a subclass

```python
(python-run "print('append' in dir(list), 'append' in dir([1]), 'keys' in dir({}), 'upper' in dir(\"s\"))\nprint([n for n in dir(list) if not n.startswith(\"_\")] == [n for n in dir([]) if not n.startswith(\"_\")])\nprint([n for n in dir(tuple) if not n.startswith(\"_\")])\nclass L(list):\n    def extra(self):\n        pass\nl = L()\nl.tag = 1\nprint([n for n in dir(l) if not n.startswith(\"_\")])\nprint(any(n.startswith(\"%\") for n in dir(list) + dir(l) + dir(3)))\nprint(dir(list) == sorted(set(dir(list))), \"to_bytes\" in dir(5), \"conjugate\" in dir(1j), \"nope\" in dir(list))")
```
---
```output
True True True True
True
['count', 'index']
['append', 'clear', 'copy', 'count', 'extend', 'extra', 'index', 'insert', 'pop', 'remove', 'reverse', 'sort', 'tag']
False
True True True False
```
