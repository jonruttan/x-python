# map and its family are classes

### subclassing map

```python
(python-run "class mymap(map):\n    pass\nm = mymap(lambda x: x + 10, range(4))\nprint(list(m))")
```
---
```output
[10, 11, 12, 13]
```

### the lazy builtins still behave as they did

```python
(python-run "print(list(map(lambda x: x * 2, [1, 2, 3])))\nprint(list(filter(lambda x: x > 1, [1, 2, 3])))\nprint(list(zip([1, 2], \"ab\")))\nprint(list(enumerate(\"ab\")))\nprint(list(reversed([1, 2, 3])))\nprint(list(range(3)), list(range(1, 4)), list(range(0, 6, 2)))")
```
---
```output
[2, 4, 6]
[2, 3]
[(1, 'a'), (2, 'b')]
[(0, 'a'), (1, 'b')]
[3, 2, 1]
[0, 1, 2] [1, 2, 3] [0, 2, 4]
```

### subclassing the others

```python
(python-run "class myfilter(filter):\n    pass\nclass myenum(enumerate):\n    pass\nprint(list(myfilter(lambda x: x % 2, [1, 2, 3, 4, 5])))\nprint(list(myenum(\"ab\")))")
```
---
```output
[1, 3, 5]
[(0, 'a'), (1, 'b')]
```

### range and bool refuse to be bases

```python
(python-run "for base in (range, bool):\n    try:\n        class X(base):\n            pass\n        print(\"subclassed\", base.__name__)\n    except TypeError as e:\n        print(\"TypeError\", base.__name__)")
```
---
```output
TypeError range
TypeError bool
```

### they are names a program can test against

```python
(python-run "print(map.__name__, filter.__name__, range.__name__)\nclass mymap(map):\n    pass\nprint(mymap.__name__, mymap.__bases__[0].__name__)")
```
---
```output
map filter range
mymap map
```

### next() still pulls from one

```python
(python-run "it = map(lambda x: x + 1, [1, 2])\nprint(next(it), next(it))\nfor x in map(lambda x: x, [7]):\n    print(x)")
```
---
```output
2 3
7
```

### they are iterators: iter() answers each itself, and next() reads it

```python
(python-run "z17 = zip([1, 2], \"ab\")\nprint(type(z17).__name__, isinstance(z17, zip), iter(z17) is z17)\nprint(next(z17), list(z17), list(z17))\nm17 = map(lambda a, b: a + b, [1, 2], [10, 20, 30])\nprint(type(m17).__name__, list(m17), list(m17), list(zip()), list(zip([1, 2, 3], [4, 5])))\ne17 = enumerate(\"ab\", 5)\nprint(type(e17).__name__, next(e17), e17.__next__(), next(e17, \"end\"))\nf17 = filter(None, [0, 1, \"\", \"x\"])\nprint(type(f17).__name__, list(f17), bool(zip([])), type(hash(map(None, []))).__name__)\nit17 = iter(map(str, [1]))\nprint(it17.__iter__() is it17, list(it17))")
```
---
```output
zip True True
(1, 'a') [(2, 'b')] []
map [11, 22] [] [] [(1, 4), (2, 5)]
enumerate (5, 'a') (6, 'b') end
filter [1, 'x'] True int
True ['1']
```

### they read their sources a step at a time, in step with the loop body

```python
(python-run "def counting18(n):\n    for k in range(n):\n        print(\"pull\", k)\n        yield k\n\n\nfor v in map(lambda k: k * 10, counting18(2)):\n    print(\"map\", v)\nfor i, v in enumerate(counting18(2)):\n    print(\"enumerate\", i, v)\nfor ab in zip(counting18(2), \"xy\"):\n    print(\"zip\", ab)")
```
---
```output
pull 0
map 0
pull 1
map 10
pull 0
enumerate 0 0
pull 1
enumerate 1 1
pull 0
zip (0, 'x')
pull 1
zip (1, 'y')
```

### a subclass, yield from, dict and sorted read them; len and next refuse by name

```python
(python-run "class Z19(zip):\n    pass\n\n\ndef g19():\n    yield from zip(\"ab\", \"cd\")\n\n\nprint(list(Z19([1], [2])), type(Z19([1], [2])).__name__, list(g19()))\nprint(dict(zip(\"ab\", [1, 2])), sorted(zip([2, 1], \"ba\")))\nfor src in (\"len(zip([]))\", \"len(5)\", \"next([1])\", \"map(len)\", \"zip(5)\", \"enumerate(None)\"):\n    try:\n        eval(src)\n    except TypeError as e:\n        print(\"TypeError\", e)")
```
---
```output
[(1, 2)] Z19 [('a', 'c'), ('b', 'd')]
{'a': 1, 'b': 2} [(1, 'a'), (2, 'b')]
TypeError object of type 'zip' has no len()
TypeError object of type 'int' has no len()
TypeError 'list' object is not an iterator
TypeError map() must have at least two arguments.
TypeError 'int' object is not iterable
TypeError 'NoneType' object is not iterable
```

### yield from reads one a step at a time, and its StopIteration value is the result

```python
(python-run "def half21(x):\n    if x < 3:\n        return x\n    raise StopIteration(444)\n\n\ndef outer21():\n    print(\"result\", (yield from map(half21, range(10))))\n\n\nprint(list(outer21()), [v for v in map(half21, range(10))])")
```
---
```output
result 444
[0, 1, 2] [0, 1, 2]
```
