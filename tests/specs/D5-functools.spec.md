# functools: tools for functions

`stdlib/functools.py`. Each expected output is a python3.14 run of the same
program.

### reduce folds left, with or without an initial value

```python
(python-run "from functools import reduce\nimport operator\nprint(reduce(lambda a, b: a + b, [1, 2, 3, 4]))\nprint(reduce(operator.mul, range(1, 6), 10))\nprint(reduce(lambda a, b: a + b, [], \"empty\"))\nprint(reduce(max, [3, 9, 2]))\ntry:\n    reduce(lambda a, b: a, [])\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
10
1200
empty
9
TypeError reduce() of empty iterable with no initial value
```

### partial fixes arguments, and flattens a partial of a partial

```python
(python-run "from functools import partial\ndef power(base, exp, *, mod=None):\n    r = base ** exp\n    return r if mod is None else r % mod\nsquare = partial(power, exp=2)\nprint(square(7), square(3, mod=5))\ncube_of_two = partial(power, 2)\nprint(cube_of_two(3), cube_of_two.args, cube_of_two.keywords, cube_of_two.func is power)\np2 = partial(partial(power, 3), mod=4)\nprint(p2(2), p2.args, p2.keywords, p2.func is power)\nbasetwo = partial(int, base=2)\nprint(basetwo(\"10010\"))\nr = repr(partial(power, 2, mod=3))\nprint(r.startswith(\"functools.partial(\"), r.endswith(\", 2, mod=3)\"))")
```
---
```output
49 4
8 (2,) {} True
1 (3,) {'mod': 4} True
18
True True
```

### wraps and update_wrapper copy the wrapped function's names

```python
(python-run "import functools\ndef logged(func):\n    @functools.wraps(func)\n    def wrapper(*args, **kwargs):\n        print(\"calling\", func.__name__)\n        return func(*args, **kwargs)\n    return wrapper\n@logged\ndef add(a, b):\n    \"\"\"Add two numbers.\"\"\"\n    return a + b\nprint(add(2, 3))\nprint(add.__name__, add.__doc__, add.__wrapped__(1, 1))\ndef plain():\n    pass\ndef other():\n    \"doc\"\nfunctools.update_wrapper(plain, other)\nprint(plain.__name__, plain.__doc__, plain.__wrapped__ is other)\nprint(functools.WRAPPER_UPDATES)")
```
---
```output
calling add
5
add Add two numbers. 2
other doc True
('__dict__',)
```

### lru_cache and cache remember results, and count hits and misses

```python
(python-run "import functools\n@functools.lru_cache(maxsize=None)\ndef fib(n):\n    return n if n < 2 else fib(n - 1) + fib(n - 2)\nprint(fib(80))\nprint(fib.cache_info())\nfib.cache_clear()\nprint(fib.cache_info())\ncalls = []\n@functools.lru_cache(maxsize=2)\ndef sq(x):\n    calls.append(x)\n    return x * x\nfor x in [1, 2, 1, 3, 2, 1]:\n    sq(x)\nprint(calls, sq.cache_info().hits, sq.cache_info().misses, sq.cache_info().currsize)\n@functools.lru_cache\ndef ident(x):\n    return x\nprint(ident(5), ident(5), ident.cache_info())\n@functools.cache\ndef count(n):\n    calls.append(n)\n    return n\ncount(9); count(9)\nprint(calls[-1], count.cache_info().hits, count.__name__)\nprint(sq.cache_parameters())")
```
---
```output
23416728348467685
CacheInfo(hits=78, misses=81, maxsize=None, currsize=81)
CacheInfo(hits=0, misses=0, maxsize=None, currsize=0)
[1, 2, 3, 2, 1] 1 5 2
5 5 CacheInfo(hits=1, misses=1, maxsize=128, currsize=1)
9 1 count
{'maxsize': 2, 'typed': False}
```

### cmp_to_key turns a comparison into a sort key

```python
(python-run "import functools\ndef by_length_then_alpha(a, b):\n    if len(a) != len(b):\n        return len(a) - len(b)\n    return (a > b) - (a < b)\nwords = [\"pear\", \"fig\", \"apple\", \"kiwi\", \"date\"]\nprint(sorted(words, key=functools.cmp_to_key(by_length_then_alpha)))\nprint(sorted([3, 1, 2], key=functools.cmp_to_key(lambda a, b: b - a)))\nK = functools.cmp_to_key(lambda a, b: a - b)\nprint(K(1) < K(2), K(2) == K(2), K(3) >= K(4))")
```
---
```output
['fig', 'date', 'kiwi', 'pear', 'apple']
[3, 2, 1]
True True False
```

### total_ordering fills in the other comparisons

```python
(python-run "import functools\n@functools.total_ordering\nclass Version:\n    def __init__(self, major, minor):\n        self.major, self.minor = major, minor\n    def __eq__(self, other):\n        return (self.major, self.minor) == (other.major, other.minor)\n    def __lt__(self, other):\n        return (self.major, self.minor) < (other.major, other.minor)\n    def __repr__(self):\n        return \"Version(%d, %d)\" % (self.major, self.minor)\na, b = Version(1, 2), Version(1, 10)\nprint(a < b, a <= b, a > b, a >= b, a == b, b >= a)\nprint(max([Version(2, 0), Version(1, 9), Version(2, 1)]))\nprint(sorted([b, a]))\ntry:\n    @functools.total_ordering\n    class Nothing:\n        pass\nexcept ValueError as e:\n    print(\"ValueError\", e)")
```
---
```output
True True False False False True
Version(2, 1)
[Version(1, 2), Version(1, 10)]
ValueError must define at least one ordering operation: < > <= >=
```

### cached_property computes once per instance

```python
(python-run "import functools\nclass Circle:\n    computed = 0\n    def __init__(self, r):\n        self.r = r\n    @functools.cached_property\n    def area(self):\n        Circle.computed += 1\n        return 3 * self.r * self.r\nc = Circle(2)\nprint(c.area, c.area, Circle.computed)\nprint(\"area\" in c.__dict__)\ndel c.area\nprint(c.area, Circle.computed)\nprint(type(Circle.area).__name__)")
```
---
```output
12 12 1
True
12 2
cached_property
```

### an instance with a __call__ takes keyword arguments, as partial's does

```python
(python-run "class Greeter:\n    def __call__(self, name, *, punct=\"!\"):\n        return \"hi \" + name + punct\ng = Greeter()\nprint(g(\"ann\"), g(\"bo\", punct=\"?\"), g(name=\"cy\"))\nclass Plain:\n    pass\ntry:\n    Plain()(x=1)\nexcept TypeError as e:\n    print(\"TypeError\", e)\n")
```
---
```output
hi ann! hi bo? hi cy!
TypeError 'Plain' object is not callable
```
