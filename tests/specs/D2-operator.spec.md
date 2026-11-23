# operator: the operators as functions

`stdlib/operator.py`. Each expected output is a python3.14 run of the same
program.

### the arithmetic, bitwise, comparison and logic functions

```python
(python-run "import operator\nprint(operator.add(2, 3), operator.sub(9, 4), operator.mul(3, 4), operator.truediv(7, 2))\nprint(operator.floordiv(7, 2), operator.mod(7, 3), operator.pow(2, 10), operator.neg(5), operator.pos(-5))\nprint(operator.abs(-3), operator.and_(12, 10), operator.or_(12, 10), operator.xor(12, 10), operator.invert(5))\nprint(operator.lshift(1, 4), operator.rshift(256, 2), operator.index(7))\nprint(operator.lt(1, 2), operator.le(2, 2), operator.eq(1, 1), operator.ne(1, 1), operator.gt(1, 2), operator.ge(3, 2))\nprint(operator.not_(0), operator.truth([]), operator.is_(None, None), operator.is_not(1, None))\nprint(operator.is_none(None), operator.is_not_none(0))\nprint(operator.concat([1], [2]), operator.contains(\"hello\", \"ell\"), operator.countOf([1, 2, 1], 1), operator.indexOf(\"abc\", \"c\"))\nprint(operator.call(max, 3, 8), operator.length_hint([1, 2, 3]))")
```
---
```output
5 5 12 3.5
3 1 1024 -5 -5
3 8 14 6 -6
16 64 7
True True True False False True
True False True True
True True
[1, 2] True 2 2
8 3
```

### itemgetter, attrgetter and methodcaller

```python
(python-run "from operator import itemgetter, attrgetter, methodcaller\nrows = [(\"bob\", 30), (\"amy\", 25), (\"cat\", 30)]\nprint(sorted(rows, key=itemgetter(1, 0)))\nprint(list(map(itemgetter(0), rows)))\nprint(itemgetter(1)(\"abc\"), itemgetter(slice(1, 3))(\"abcd\"), itemgetter(\"k\")({\"k\": 9}))\nclass P:\n    def __init__(self, name, inner=None):\n        self.name = name\n        self.inner = inner\np = P(\"outer\", P(\"inner\"))\nprint(attrgetter(\"name\")(p), attrgetter(\"inner.name\")(p), attrgetter(\"name\", \"inner.name\")(p))\nprint(methodcaller(\"upper\")(\"abc\"), methodcaller(\"split\", \",\")(\"a,b\"), methodcaller(\"replace\", \"a\", \"o\", 1)(\"banana\"))\nprint(methodcaller(\"count\", \"a\", 2)(\"banana\"))\nprint(itemgetter(1, 0), attrgetter(\"x\", \"y.z\"), methodcaller(\"split\", \",\", maxsplit=1))")
```
---
```output
[('amy', 25), ('bob', 30), ('cat', 30)]
['bob', 'amy', 'cat']
b bc 9
outer inner ('outer', 'inner')
ABC ['a', 'b'] bonana
2
operator.itemgetter(1, 0) operator.attrgetter('x', 'y.z') operator.methodcaller('split', ',', maxsplit=1)
```

### the in-place functions, item assignment, and their errors

```python
(python-run "import operator\nx = [1, 2]\ny = operator.iadd(x, [3])\nprint(x, y is x)\nprint(operator.iadd(5, 2), operator.isub(5, 2), operator.imul(\"ab\", 2), operator.ifloordiv(9, 2))\nd = {}\noperator.setitem(d, \"a\", 1)\noperator.setitem(d, \"b\", 2)\noperator.delitem(d, \"a\")\nprint(d, operator.getitem(d, \"b\"))\ntry:\n    operator.indexOf([1, 2], 5)\nexcept ValueError as e:\n    print(\"ValueError\", e)\ntry:\n    operator.concat(1, 2)\nexcept TypeError as e:\n    print(\"TypeError\", e)\nprint(operator.__add__ is operator.add, operator.invert is operator.inv)")
```
---
```output
[1, 2, 3] True
7 3 abab 4
{'b': 2} 2
ValueError sequence.index(x): x not in sequence
TypeError 'int' object can't be concatenated
True False
```

### index takes an int or an object with __index__

```python
(python-run "import operator\nclass Idx:\n    def __index__(self):\n        return 3\nprint(operator.index(True), operator.index(Idx()), [10, 20, 30, 40][operator.index(Idx())])\ntry:\n    operator.index(1.5)\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
1 3 40
TypeError 'float' object cannot be interpreted as an integer
```
