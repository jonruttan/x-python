# the collections module

### a namedtuple is a tuple with names

```python
(python-run "from collections import namedtuple\nT = namedtuple(\"Tup\", [\"foo\", \"bar\"])\nt = T(1, 2)\nprint(t)\nprint(t[0], t[1], t.foo, t.bar, len(t))\nprint(t + t, t * 2, [f for f in t], isinstance(t, tuple))\nprint(\"(%d, %d)\" % t, t == (1, 2), (1, 2) == t)\nprint(T(3, bar=4), T(bar=5, foo=6))\nprint(T(\"a b\", \"c\"))\n")
```
---
```output
Tup(foo=1, bar=2)
1 2 1 2 2
(1, 2, 1, 2) (1, 2, 1, 2) [1, 2] True
(1, 2) True True
Tup(foo=3, bar=4) Tup(foo=6, bar=5)
Tup(foo='a b', bar='c')
```

### a namedtuple refuses a bad call and a store

```python
(python-run "from collections import namedtuple\nT = namedtuple(\"Tup\", [\"foo\", \"bar\"])\nt = T(1, 2)\nfor f in (lambda: t.__setattr__(\"bar\", 9), lambda: T(1), lambda: T(1, 2, 3), lambda: T(foo=1), lambda: T(1, foo=1), lambda: T(1, baz=3), lambda: namedtuple(\"T\", 1)):\n    try:\n        f()\n    except (TypeError, AttributeError) as e:\n        print(type(e).__name__)\nprint(namedtuple(\"S\", \"foo bar\")(1, 2), namedtuple(\"S\", (\"a\", \"b\"))(3, 4), namedtuple(\"E\", [])())\nprint(T(\"x\", \"y\")._asdict(), T(1, 2)._fields)\n")
```
---
```output
AttributeError
TypeError
TypeError
TypeError
TypeError
TypeError
TypeError
S(foo=1, bar=2) S(a=3, b=4) E()
{'foo': 'x', 'bar': 'y'} ('foo', 'bar')
```

### an OrderedDict keeps its order

```python
(python-run "from collections import OrderedDict\nd = OrderedDict([(10, 20), (\"b\", 100), (1, 2)])\nprint(d, len(d), list(d.keys()), list(d.values()))\ndel d[\"b\"]\nprint(d, d[10], d[1])\nd[\"abc\"] = 123\nprint(d, d.popitem(), d)\nprint(OrderedDict(), OrderedDict(a=1, b=2))\nprint(list(OrderedDict(a=1, b=2).items()))\n")
```
---
```output
OrderedDict({10: 20, 'b': 100, 1: 2}) 3 [10, 'b', 1] [20, 100, 2]
OrderedDict({10: 20, 1: 2}) 20 2
OrderedDict({10: 20, 1: 2}) ('abc', 123) OrderedDict({10: 20, 1: 2})
OrderedDict() OrderedDict({'a': 1, 'b': 2})
[('a', 1), ('b', 2)]
```

### OrderedDict equality counts order

```python
(python-run "from collections import OrderedDict\nx = OrderedDict()\ny = OrderedDict()\nx['a'] = 1; x['b'] = 2\ny['a'] = 1; y['b'] = 2\nz = OrderedDict()\nz['b'] = 2; z['a'] = 1\nprint(x == y, y == z, z == z)\nprint(x == {'a': 1, 'b': 2})\nprint(isinstance(x, dict), 'a' in x, len(x))\nfor k in x:\n    print(k, x[k])\n")
```
---
```output
True False True
True
True True 2
a 1
b 2
```

### an OrderedDict subclass takes keywords and prints under its own name

```python
(python-run "from collections import OrderedDict\nclass O(OrderedDict):\n    pass\nprint(O(a=1), O({'b': 2}), O(), OrderedDict(a=1), OrderedDict([('c', 3)], d=4))\no = O(x=1)\no['y'] = 2\nprint(o, type(o).__name__, isinstance(o, OrderedDict), o == OrderedDict(x=1, y=2), o == OrderedDict(y=2, x=1))\nprint(O.fromkeys(\"pq\", 0))\ntry:\n    OrderedDict(5)\nexcept TypeError:\n    print(\"TypeError\")\n")
```
---
```output
O({'a': 1}) O({'b': 2}) O() OrderedDict({'a': 1}) OrderedDict({'c': 3, 'd': 4})
O({'x': 1, 'y': 2}) O True True False
O({'p': 0, 'q': 0})
TypeError
```

