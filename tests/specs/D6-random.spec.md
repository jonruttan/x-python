# random: CPython's Mersenne Twister and its distributions

`stdlib/random.py`, drawing from the generator in `lib/python/_random.x`.
Each expected output is a python3.14 run of the same program: an int seed
draws the numbers CPython draws.

### the seeded stream is CPython's

```python
(python-run "import random\nrandom.seed(42)\nprint(random.random(), random.random())\nprint(random.getrandbits(8), random.getrandbits(32), random.getrandbits(70))\nprint(random.randint(1, 6), random.randrange(10), random.randrange(0, 100, 7), random.randrange(10, 0, -3))\nprint(random.choice(\"abcdef\"), random.uniform(1.0, 2.0))\nprint(random.randbytes(5))")
```
---
```output
0.6394267984578837 0.025010755222666936
70 1051802512 869570991858821387998
1 8 7 1
a 1.0297972194380702
b'\x8b\xa8\xf87;'
```

### sequences: shuffle, sample and choices

```python
(python-run "import random\nrandom.seed(7)\nxs = list(range(10))\nrandom.shuffle(xs)\nprint(xs)\nprint(random.sample(range(100), 5), random.sample(\"abcdefg\", 3))\nprint(random.sample([\"red\", \"blue\"], counts=[2, 3], k=4))\nprint(random.choices(\"abc\", k=5))\nprint(random.choices(\"abc\", weights=[1, 0, 5], k=5), random.choices(\"ab\", cum_weights=[1, 3], k=4))")
```
---
```output
[8, 3, 1, 4, 7, 0, 9, 6, 2, 5]
[64, 27, 4, 11, 55] ['d', 'a', 'b']
['red', 'blue', 'blue', 'blue']
['c', 'b', 'b', 'a', 'b']
['a', 'c', 'c', 'a', 'c'] ['b', 'b', 'b', 'b']
```

### the real-valued distributions

```python
(python-run "import random\nrandom.seed(3)\nprint(random.gauss(), random.gauss(10, 2))\nprint(random.normalvariate(0, 1), random.expovariate(2.0))\nprint(random.triangular(), random.triangular(0, 10, 2))")
```
---
```output
0.09470803828730423 12.5000487621671
-0.5632587983771494 0.49137595554479707
0.18100947384020138 0.5131859615163715
```

### a Random of its own, and its state

```python
(python-run "import random\nr = random.Random(2 ** 70)\nprint(r.random())\ns = r.getstate()\na = [r.random() for i in range(3)]\nr.setstate(s)\nprint(a == [r.random() for i in range(3)], s[0], len(s[1]))\nprint(random.Random(12345).randint(0, 10 ** 30))\nprint(random.Random(-5).random() == random.Random(5).random())\nrandom.seed(1)\nx = random.random()\nrandom.seed(1)\nprint(x == random.random(), isinstance(random.Random(), random.Random))")
```
---
```output
0.2327882718301838
True 3 625
332256083118531044858259323495
True
True True
```

### the errors

```python
(python-run "import random\nfor f in (lambda: random.choice([]), lambda: random.randrange(0), lambda: random.randrange(1, 5, 0),\n          lambda: random.sample([1, 2], 3), lambda: random.getrandbits(-1), lambda: random.randrange(5, 1)):\n    try:\n        f()\n    except (ValueError, IndexError) as e:\n        print(type(e).__name__, e)")
```
---
```output
IndexError Cannot choose from an empty sequence
ValueError empty range for randrange()
ValueError zero step for randrange()
ValueError Sample larger than population or is negative
ValueError Cannot convert negative int
ValueError empty range in randrange(5, 1)
```
