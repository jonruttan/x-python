# itertools: iterator building blocks

`stdlib/itertools.py`. Each expected output is a python3.14 run of the same
program.

### the infinite iterators: count, cycle and repeat

```python
(python-run "from itertools import count, cycle, repeat, islice\nprint(list(islice(count(), 5)), list(islice(count(10, 5), 3)), list(islice(count(1.5, 0.5), 3)))\nc = count(3)\nnext(c); next(c)\nprint(c, count(2, 3), repeat(\"x\", 2), repeat(7))\nprint(list(islice(cycle(\"ab\"), 5)), list(cycle([])))\nprint(list(repeat(\"x\", 3)), list(repeat(1, 0)), list(map(pow, range(4), repeat(2))))")
```
---
```output
[0, 1, 2, 3, 4] [10, 15, 20] [1.5, 2.0, 2.5]
count(5) count(2, 3) repeat('x', 2) repeat(7)
['a', 'b', 'a', 'b', 'a'] []
['x', 'x', 'x'] [] [0, 1, 4, 9]
```

### the iterators that end with their shortest input

```python
(python-run "from itertools import accumulate, batched, chain, compress, dropwhile, filterfalse, pairwise, starmap, takewhile, zip_longest\nimport operator\nprint(list(accumulate([1, 2, 3, 4])), list(accumulate([3, 1, 4, 1, 5], max)), list(accumulate([1, 2], initial=100)))\nprint(list(accumulate([1, 2, 3, 4], operator.mul)), list(accumulate([])))\nprint(list(batched(\"abcdefg\", 3)), list(batched(range(4), 2)))\ntry:\n    list(batched(\"abc\", 2, strict=True))\nexcept ValueError as e:\n    print(\"ValueError\", e)\nprint(list(chain(\"ab\", [1, 2], ())), list(chain.from_iterable([\"xy\", \"z\"])))\nprint(list(compress(\"abcdef\", [1, 0, 1, 0, 1, 1])))\nprint(list(dropwhile(lambda x: x < 3, [1, 2, 3, 1, 4])), list(takewhile(lambda x: x < 3, [1, 2, 3, 1])))\nprint(list(filterfalse(lambda x: x % 2, range(8))), list(filterfalse(None, [0, 1, \"\", \"a\"])))\nprint(list(pairwise(\"abcd\")), list(pairwise(\"a\")))\nprint(list(starmap(pow, [(2, 3), (3, 2)])))\nprint(list(zip_longest(\"abc\", \"x\")), list(zip_longest(\"ab\", [1, 2, 3], fillvalue=\"-\")))")
```
---
```output
[1, 3, 6, 10] [3, 3, 4, 4, 5] [100, 101, 103]
[1, 2, 6, 24] []
[('a', 'b', 'c'), ('d', 'e', 'f'), ('g',)] [(0, 1), (2, 3)]
ValueError batched(): incomplete batch
['a', 'b', 1, 2] ['x', 'y', 'z']
['a', 'c', 'e', 'f']
[3, 1, 4] [1, 2]
[0, 2, 4, 6] [0, '']
[('a', 'b'), ('b', 'c'), ('c', 'd')] []
[8, 9]
[('a', 'x'), ('b', None), ('c', None)] [('a', 1), ('b', 2), ('-', 3)]
```

### groupby, islice and tee

```python
(python-run "from itertools import groupby, islice, tee\ndata = \"aaabbcaa\"\nprint([(k, list(g)) for k, g in groupby(data)])\nprint([k for k, g in groupby(data)])\nwords = [\"apple\", \"avocado\", \"banana\", \"blueberry\", \"cherry\"]\nprint([(k, len(list(g))) for k, g in groupby(words, key=lambda w: w[0])])\ngroups = list(groupby([1, 1, 2]))\nprint([(k, list(g)) for k, g in groups])\nprint(list(islice(\"abcdefg\", 2)), list(islice(\"abcdefg\", 2, 4)), list(islice(\"abcdefg\", 2, None)), list(islice(\"abcdefg\", 0, None, 2)))\nit = iter(range(10))\nprint(list(islice(it, 3)), next(it))\ntry:\n    islice(\"abc\", -1)\nexcept ValueError as e:\n    print(\"ValueError\", e)\na, b = tee(iter([1, 2, 3]))\nprint(next(a), list(b), list(a), len(tee(\"xy\", 3)))")
```
---
```output
[('a', ['a', 'a', 'a']), ('b', ['b', 'b']), ('c', ['c']), ('a', ['a', 'a'])]
['a', 'b', 'c', 'a']
[('a', 2), ('b', 2), ('c', 1)]
[(1, []), (2, [])]
['a', 'b'] ['c', 'd'] ['c', 'd', 'e', 'f', 'g'] ['a', 'c', 'e', 'g']
[0, 1, 2] 3
ValueError Stop argument for islice() must be None or an integer: 0 <= x <= sys.maxsize.
1 [1, 2, 3] [2, 3] 3
```

### the combinatoric iterators

```python
(python-run "from itertools import product, permutations, combinations, combinations_with_replacement\nprint(list(product(\"ab\", [0, 1])))\nprint(list(product([1, 2], repeat=2)), list(product()))\nprint(list(permutations(\"abc\", 2)))\nprint(len(list(permutations(range(4)))), list(permutations([1, 2], 3)))\nprint(list(combinations(\"abcd\", 2)), list(combinations(range(3), 0)))\nprint(list(combinations_with_replacement(\"abc\", 2)))\nprint(sum(1 for _ in combinations(range(10), 3)))")
```
---
```output
[('a', 0), ('a', 1), ('b', 0), ('b', 1)]
[(1, 1), (1, 2), (2, 1), (2, 2)] [()]
[('a', 'b'), ('a', 'c'), ('b', 'a'), ('b', 'c'), ('c', 'a'), ('c', 'b')]
24 []
[('a', 'b'), ('a', 'c'), ('a', 'd'), ('b', 'c'), ('b', 'd'), ('c', 'd')] [()]
[('a', 'a'), ('a', 'b'), ('a', 'c'), ('b', 'b'), ('b', 'c'), ('c', 'c')]
120
```
