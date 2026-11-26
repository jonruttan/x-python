# heapq: a binary heap in a list

`stdlib/heapq.py`. Each expected output is a python3.14 run of the same
program.

### push and pop keep a min-heap, laid out as CPython lays it out

```python
(python-run "import heapq\nh = []\nfor v in [5, 3, 8, 1, 9, 2, 7, 1, 6]:\n    heapq.heappush(h, v)\nprint(h)\nprint([heapq.heappop(h) for _ in range(4)], h)\nx = [9, 8, 7, 6, 5, 4, 3, 2, 1, 0]\nheapq.heapify(x)\nprint(x)\nprint(heapq.heapreplace(x, 10), x)\nprint(heapq.heappushpop(x, -1), heapq.heappushpop(x, 4), x)\nprint(heapq.heappushpop([], 3), heapq.heappop([7]))\nprint([heapq.heappop(x) for _ in range(len(x))], x)\nt = []\nfor item in [(2, 'b'), (1, 'z'), (2, 'a'), (1, 'y')]:\n    heapq.heappush(t, item)\nprint([heapq.heappop(t) for _ in range(4)])\nclass L(list):\n    pass\ns = L([3, 1, 2])\nheapq.heapify(s)\nprint(s, type(s).__name__)\nprint(heapq.__all__)\n")
```
---
```output
[1, 1, 2, 3, 9, 8, 7, 5, 6]
[1, 1, 2, 3] [5, 7, 6, 8, 9]
[0, 1, 3, 2, 5, 4, 7, 9, 6, 8]
0 [1, 2, 3, 6, 5, 4, 7, 9, 10, 8]
-1 1 [2, 4, 3, 6, 5, 4, 7, 9, 10, 8]
3 7
[2, 3, 4, 4, 5, 6, 7, 8, 9, 10] []
[(1, 'y'), (1, 'z'), (2, 'a'), (2, 'b')]
[1, 3, 2] L
['heappush', 'heappop', 'heapify', 'heapreplace', 'heappushpop', 'heappush_max', 'heappop_max', 'heapify_max', 'heapreplace_max', 'heappushpop_max', 'nlargest', 'nsmallest', 'merge']
```

### the max-heap functions keep the mirror image

```python
(python-run "import heapq\nh = []\nfor v in [5, 3, 8, 1, 9, 2, 7, 1, 6]:\n    heapq.heappush_max(h, v)\nprint(h)\nprint([heapq.heappop_max(h) for _ in range(4)], h)\nx = list(range(10))\nheapq.heapify_max(x)\nprint(x)\nprint(heapq.heapreplace_max(x, -5), x)\nprint(heapq.heappushpop_max(x, 100), heapq.heappushpop_max(x, 3), x)\nprint(heapq.heappushpop_max([], 3), heapq.heappop_max([7]))\nout = []\nwhile x:\n    out.append(heapq.heappop_max(x))\nprint(out)\n")
```
---
```output
[9, 8, 7, 6, 3, 2, 5, 1, 1]
[9, 8, 7, 6] [5, 3, 2, 1, 1]
[9, 8, 6, 7, 4, 5, 2, 0, 3, 1]
9 [8, 7, 6, 3, 4, 5, 2, 0, -5, 1]
100 8 [7, 4, 6, 3, 3, 5, 2, 0, -5, 1]
3 7
[7, 6, 5, 4, 3, 3, 2, 1, 0, -5]
```

### merge interleaves sorted inputs lazily, with key and reverse

```python
(python-run "import heapq\nprint(list(heapq.merge([1, 3, 5, 7], [0, 2, 4, 8], [5, 10, 15, 20], [], [25])))\nprint(list(heapq.merge(['dog', 'horse'], ['cat', 'fish', 'kangaroo'], key=len)))\nprint(list(heapq.merge([9, 5, 1], [8, 5, 2], reverse=True)))\nprint(list(heapq.merge([(1, 'a'), (2, 'a')], [(1, 'b'), (2, 'b')], key=lambda p: p[0])))\nprint(list(heapq.merge([(2, 'a'), (1, 'a')], [(2, 'b'), (1, 'b')], key=lambda p: p[0], reverse=True)))\nprint(list(heapq.merge()), list(heapq.merge([], [])), list(heapq.merge('ace', 'bd')))\nseen = []\ndef src(name, items):\n    for i in items:\n        seen.append(name + str(i))\n        yield i\nm = heapq.merge(src('a', [1, 4]), src('b', [2, 3]))\nprint(type(m).__name__, seen)\nprint(next(m), seen)\nprint(list(m), seen)\n")
```
---
```output
[0, 1, 2, 3, 4, 5, 5, 7, 8, 10, 15, 20, 25]
['dog', 'cat', 'fish', 'horse', 'kangaroo']
[9, 8, 5, 5, 2, 1]
[(1, 'a'), (1, 'b'), (2, 'a'), (2, 'b')]
[(2, 'a'), (2, 'b'), (1, 'a'), (1, 'b')]
[] [] ['a', 'b', 'c', 'd', 'e']
generator []
1 ['a1', 'b2']
[2, 3, 4] ['a1', 'b2', 'a4', 'b3']
```

### nsmallest and nlargest, with key, ties and every size of n

```python
(python-run "import heapq\ndata = [5, 1, 8, 3, 9, 2, 8, 1]\nfor n in (-1, 0, 1, 2, 3, 7, 8, 20):\n    print(n, heapq.nsmallest(n, data), heapq.nlargest(n, data))\nprint(heapq.nsmallest(3, iter(data)), heapq.nlargest(3, iter(data)))\nprint(heapq.nsmallest(1, []), heapq.nlargest(1, iter([])), heapq.nsmallest(2, []))\nwords = ['bb', 'a', 'ccc', 'dd', 'e', 'fff']\nprint(heapq.nsmallest(3, words, key=len), heapq.nlargest(3, words, key=len))\nprint(heapq.nsmallest(2, iter(words), key=len), heapq.nlargest(4, iter(words), key=len))\nprint(heapq.nlargest(1, words, key=len), heapq.nsmallest(1, iter(words), key=len))\nrows = [{'n': 'x', 'p': 3}, {'n': 'y', 'p': 1}, {'n': 'z', 'p': 3}, {'n': 'w', 'p': 2}]\nprint([r['n'] for r in heapq.nlargest(2, rows, key=lambda r: r['p'])])\nprint([r['n'] for r in heapq.nsmallest(3, iter(rows), key=lambda r: r['p'])])\n")
```
---
```output
-1 [] []
0 [] []
1 [1] [9]
2 [1, 1] [9, 8]
3 [1, 1, 2] [9, 8, 8]
7 [1, 1, 2, 3, 5, 8, 8] [9, 8, 8, 5, 3, 2, 1]
8 [1, 1, 2, 3, 5, 8, 8, 9] [9, 8, 8, 5, 3, 2, 1, 1]
20 [1, 1, 2, 3, 5, 8, 8, 9] [9, 8, 8, 5, 3, 2, 1, 1]
[1, 1, 2] [9, 8, 8]
[] [] []
['a', 'e', 'bb'] ['ccc', 'fff', 'bb']
['a', 'e'] ['ccc', 'fff', 'bb', 'dd']
['ccc'] ['a']
['x', 'z']
['y', 'w', 'x']
```

### what a heap function refuses

```python
(python-run "import heapq\ndef show(f, *args):\n    try:\n        print(f(*args))\n    except Exception as e:\n        print(type(e).__name__, e)\nshow(heapq.heappush, (), 1)\nshow(heapq.heappush, None, 1)\nshow(heapq.heapify, 'abc')\nshow(heapq.heapify_max, 1)\nshow(heapq.heappushpop, 5, 1)\nshow(heapq.heapreplace, [], 1)\nshow(heapq.heappop, [])\nshow(heapq.heappop_max, [])\nshow(heapq.heapreplace_max, [], 1)\nshow(heapq.heappush, [1], 'a')\nshow(heapq.nlargest, None, [1])\nshow(heapq.nsmallest, 1.5, [1])\nshow(heapq.nsmallest, 1.5, [1, 2, 3])\nshow(heapq.nlargest, 2, 5)\n")
```
---
```output
TypeError heappush() argument 1 must be list, not tuple
TypeError heappush() argument 1 must be list, not None
TypeError heapify() argument must be list, not str
TypeError heapify_max() argument must be list, not int
TypeError heappushpop() argument 1 must be list, not int
IndexError index out of range
IndexError index out of range
IndexError index out of range
IndexError index out of range
TypeError '<' not supported between instances of 'str' and 'int'
TypeError '>=' not supported between instances of 'NoneType' and 'int'
TypeError slice indices must be integers or None or have an __index__ method
TypeError 'float' object cannot be interpreted as an integer
TypeError 'int' object is not iterable
```

### <= and >= refuse under their own names, and a slice bound is an int or None

```python
(python-run "def show(src):\n    try:\n        print(src, eval(src))\n    except Exception as e:\n        print(src, type(e).__name__, e)\nfor src in ['None >= 1', '1 <= None', '\"a\" <= 1', '[1] >= (1,)',\n            '[1, 2] <= [1, 2]', '(1, 3) >= (1, 2, 9)', '[1] <= [1, 0]', 'True >= 1', '2.5 <= 2',\n            '[1, 2][:1.5]', '\"abc\"[0.5:]', '(1, 2)[::2.0]', 'b\"ab\"[\"x\":]', 'range(5)[:1.5]',\n            '[1, 2, 3][:True]', '[1, 2, 3][None:None:-1]', '{slice(1.5, None): 7}[1.5:]']:\n    show(src)\n")
```
---
```output
None >= 1 TypeError '>=' not supported between instances of 'NoneType' and 'int'
1 <= None TypeError '<=' not supported between instances of 'int' and 'NoneType'
"a" <= 1 TypeError '<=' not supported between instances of 'str' and 'int'
[1] >= (1,) TypeError '>=' not supported between instances of 'list' and 'tuple'
[1, 2] <= [1, 2] True
(1, 3) >= (1, 2, 9) True
[1] <= [1, 0] True
True >= 1 True
2.5 <= 2 False
[1, 2][:1.5] TypeError slice indices must be integers or None or have an __index__ method
"abc"[0.5:] TypeError slice indices must be integers or None or have an __index__ method
(1, 2)[::2.0] TypeError slice indices must be integers or None or have an __index__ method
b"ab"["x":] TypeError slice indices must be integers or None or have an __index__ method
range(5)[:1.5] TypeError slice indices must be integers or None or have an __index__ method
[1, 2, 3][:True] [1]
[1, 2, 3][None:None:-1] [3, 2, 1]
{slice(1.5, None): 7}[1.5:] 7
```
