# a namedtuple subclass

A class over a namedtuple is a tuple of the same fields: it iterates,
unpacks and indexes as one, reads its fields by name, and takes the methods
of a second base beside it.  A class stored on another and called from
there constructs, not binds.  The expectations are CPython 3.14's.

## namedtuple subclass

### iteration, fields, a mixin, a stored class

```python
(python-run "from collections import namedtuple\nB = namedtuple('B', ['foo', 'bar'])\nclass P(B):\n    def total(self):\n        return self.foo + self.bar\np = P(1, 2)\nprint(list(p), [x for x in p], len(p), p[1], p.foo, p.bar, p.total())\nprint(tuple(p), sum(p), 2 in p, isinstance(p, B), isinstance(p, tuple))\na, b = p\nprint(a, b)\nclass M(object):\n    def doubled(self):\n        return self._other(*(x * 2 for x in self))\nclass Q(B, M):\n    pass\nclass R(B, M):\n    pass\nQ._other = R\nR._other = Q\nr = Q(3, 4).doubled()\nprint(type(r).__name__, list(r), r.foo)\nprint(list(B(5, 6)), B(5, 6).bar)")
```
---
```output
[1, 2] [1, 2] 2 2 1 2 3
(1, 2) 3 True True True
1 2
R [6, 8] 6
[5, 6] 6
```
