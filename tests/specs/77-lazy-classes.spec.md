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
