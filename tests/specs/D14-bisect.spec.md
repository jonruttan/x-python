# bisect: finding where an item belongs

`stdlib/bisect.py`. Each expected output is a python3.14 run of the same
program.

### bisect_left and bisect_right find either end of a run of equal items

```python
(python-run "import bisect\na = [1, 2, 2, 2, 3, 5, 8]\nfor x in (0, 1, 2, 3, 4, 5, 8, 9):\n    print(x, bisect.bisect_left(a, x), bisect.bisect_right(a, x), bisect.bisect(a, x))\nprint(bisect.bisect_left([], 1), bisect.bisect_right([], 1))\nprint(bisect.bisect_right('abcd', 'c'), bisect.bisect_left(('a', 'b', 'b'), 'b'))\nprint(bisect.bisect_right(range(10), 4.5), bisect.bisect_left(range(0, 20, 2), 7))\ndef grade(score, cuts=[60, 70, 80, 90], letters='FDCBA'):\n    return letters[bisect.bisect(cuts, score)]\nprint([grade(s) for s in [33, 99, 77, 70, 89, 90, 100]])\nprint(bisect.bisect is bisect.bisect_right, bisect.insort is bisect.insort_right)\nprint(sorted(n for n in dir(bisect) if not n.startswith('_')))\n")
```
---
```output
0 0 0 0
1 0 1 1
2 1 4 4
3 4 5 5
4 5 5 5
5 5 6 6
8 6 7 7
9 7 7 7
0 0
3 1
5 4
['F', 'A', 'C', 'C', 'B', 'A', 'A']
True True
['bisect', 'bisect_left', 'bisect_right', 'insort', 'insort_left', 'insort_right']
```

### lo, hi and key narrow and reshape the search

```python
(python-run "import bisect\na = [1, 2, 2, 2, 3, 5, 8]\nprint(bisect.bisect_left(a, 2, 2), bisect.bisect_right(a, 2, 0, 3), bisect.bisect_left(a, 9, 1, 4))\nprint(bisect.bisect_left(a, 2, lo=5), bisect.bisect_right(a, 2, hi=2), bisect.bisect_left(a, 2, 3, None))\nprint(bisect.bisect_left(a, 9, 0, -1), bisect.bisect_left(a, 9, 0, -2), bisect.bisect_left(a, 9, 20))\nprint(bisect.bisect_left(a, 2, True, False), bisect.bisect_right(a, 2, False, True))\nclass Ix:\n    def __init__(self, n):\n        self.n = n\n    def __index__(self):\n        return self.n\nprint(bisect.bisect_left(a, 3, Ix(1), Ix(6)), bisect.bisect_right(a, 3, hi=Ix(-1)))\nrows = [('ann', 1), ('bob', 3), ('cy', 3), ('di', 7)]\nseen = []\ndef score(row):\n    seen.append(row[0])\n    return row[1]\nprint(bisect.bisect_left(rows, 3, key=score), bisect.bisect_right(rows, 3, key=score), seen)\nprint(bisect.bisect_right(rows, 0, key=score), bisect.bisect_left(rows, 8, key=lambda r: r[1]))\n")
```
---
```output
2 3 4
5 2 3
7 0 20
1 1
4 5
1 3 ['cy', 'bob', 'ann', 'cy', 'di']
0 4
```

### insort keeps a list sorted, and keeps equal items in order

```python
(python-run "import bisect\na = []\nfor v in [5, 1, 4, 1, 5, 9, 2, 6]:\n    bisect.insort(a, v)\nprint(a)\nclass T:\n    def __init__(self, v, tag):\n        self.v, self.tag = v, tag\n    def __lt__(self, other):\n        return self.v < other.v\n    def __repr__(self):\n        return '%s%s' % (self.v, self.tag)\nb = [T(1, 'a'), T(2, 'a'), T(3, 'a')]\nbisect.insort_left(b, T(2, 'L'))\nbisect.insort_right(b, T(2, 'R'))\nbisect.insort(b, T(2, 'r'))\nprint(b)\nrows = [('ann', 1), ('di', 7)]\nbisect.insort(rows, ('bob', 3), key=lambda r: r[1])\nbisect.insort_left(rows, ('cy', 3), key=lambda r: r[1])\nbisect.insort_right(rows, ('ed', 3), key=lambda r: r[1])\nprint(rows)\nc = [1, 2, 3, 4]\nbisect.insort(c, 0, 2)\nbisect.insort_left(c, 9, 0, 1)\nprint(c)\nclass Tracked(list):\n    def insert(self, i, x):\n        print('insert', i, x)\n        list.insert(self, i, x)\nt = Tracked([1, 3])\nbisect.insort(t, 2)\nprint(t)\n")
```
---
```output
[1, 1, 2, 4, 5, 5, 6, 9]
[1a, 2L, 2a, 2R, 2r, 3a]
[('ann', 1), ('cy', 3), ('bob', 3), ('ed', 3), ('di', 7)]
[1, 9, 2, 0, 3, 4]
insert 1 2
[1, 2, 3]
```

### what a bisect function refuses, in the order CPython checks

```python
(python-run "import bisect\ndef show(f, *args, **kw):\n    try:\n        print(f(*args, **kw))\n    except Exception as e:\n        print(type(e).__name__, e)\nshow(bisect.bisect_left, [1, 2], 1, -1)\nshow(bisect.bisect_left, None, 1, -1)\nshow(bisect.bisect_left, [1, 2], 1, 1.5)\nshow(bisect.bisect_left, [1, 2], 1, None)\nshow(bisect.bisect_left, [1, 2], 1, 0, 1.5)\nshow(bisect.bisect_right, None, 1, -2, 1.5)\nshow(bisect.bisect, None, 1)\nshow(bisect.bisect, 5, 1)\nshow(bisect.bisect, None, 1, 0, 3)\nshow(bisect.bisect_right, 5, 1, 4, 2)\nshow(bisect.bisect_left, {0: 1}, 1, 0, 1)\nshow(bisect.bisect_left, [1, 2], 1, 0, 5)\nshow(bisect.bisect_left, [1, 'a'], 2)\nshow(bisect.insort, (1, 2), 1)\nshow(bisect.insort, (1, 2), 0, 5, 6)\nshow(bisect.insort, 'ab', 3)\nshow(bisect.insort, [1], 2, None, key=len)\n")
```
---
```output
ValueError lo must be non-negative
ValueError lo must be non-negative
TypeError 'float' object cannot be interpreted as an integer
TypeError 'NoneType' object cannot be interpreted as an integer
TypeError argument should be integer or None, not 'float'
TypeError argument should be integer or None, not 'float'
TypeError object of type 'NoneType' has no len()
TypeError object of type 'int' has no len()
TypeError 'NoneType' object does not support indexing
TypeError 'int' object does not support indexing
TypeError dict is not a sequence
IndexError list index out of range
TypeError '<' not supported between instances of 'str' and 'int'
AttributeError 'tuple' object has no attribute 'insert'
IndexError tuple index out of range
TypeError '<' not supported between instances of 'int' and 'str'
TypeError 'NoneType' object cannot be interpreted as an integer
```
