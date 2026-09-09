# the math module: tolerances, domains and whole numbers

### a domain error is a ValueError

```python
(python-run "import math\ndef check(name, f):\n    try:\n        f()\n        print(name, \"no error\")\n    except ValueError:\n        print(name, \"ValueError\")\ncheck(\"sqrt(-1)\", lambda: math.sqrt(-1))\ncheck(\"log(0)\", lambda: math.log(0))\ncheck(\"log(-1)\", lambda: math.log(-1))\ncheck(\"asin(2)\", lambda: math.asin(2))\ncheck(\"acos(2)\", lambda: math.acos(2))\ncheck(\"factorial(-1)\", lambda: math.factorial(-1))")
```
---
```output
sqrt(-1) ValueError
log(0) ValueError
log(-1) ValueError
asin(2) ValueError
acos(2) ValueError
factorial(-1) ValueError
```

### isclose

```python
(python-run "import math\nprint(math.isclose(1.0, 1.0), math.isclose(1.0, 1.0000000001))\nprint(math.isclose(1.0, 1.1), math.isclose(0.0, 0.0))")
```
---
```output
True True
False True
```

### isclose takes its tolerances

```python
(python-run "import math\nprint(math.isclose(1.0, 1.001), math.isclose(1.0, 1.001, rel_tol=0.01))\nprint(math.isclose(0.0, 0.0001, abs_tol=0.001), math.isclose(0.0, 0.01, abs_tol=0.001))\nprint(math.isclose(100.0, 101.0, rel_tol=0.02), math.isclose(100.0, 105.0, rel_tol=0.02))")
```
---
```output
False True
True False
True False
```

### an infinity or a NaN has no integer

```python
(python-run "import math\ndef check(name, f):\n    try:\n        print(name, f())\n    except OverflowError:\n        print(name, \"OverflowError\")\n    except ValueError:\n        print(name, \"ValueError\")\ncheck(\"floor(inf)\", lambda: math.floor(math.inf))\ncheck(\"ceil(nan)\", lambda: math.ceil(math.nan))\ncheck(\"trunc(inf)\", lambda: math.trunc(math.inf))\ncheck(\"floor(2.5)\", lambda: math.floor(2.5))")
```
---
```output
floor(inf) OverflowError
ceil(nan) ValueError
trunc(inf) OverflowError
floor(2.5) 2
```

### expm1 and log1p

```python
(python-run "import math\nprint(round(math.expm1(0), 10), round(math.expm1(1), 10))\nprint(round(math.log1p(0), 10), round(math.log1p(math.e - 1), 10))")
```
---
```output
0.0 1.7182818285
0.0 1.0
```

### a whole number stays exact

```python
(python-run "import math\nbig = 10 ** 25\nprint(math.floor(big), math.ceil(big), math.trunc(big))\nprint(math.floor(0), math.ceil(0), math.trunc(0))\nprint(math.floor(-7), math.ceil(-7), math.trunc(-7))\nprint(math.floor(2), math.floor(2.0))")
```
---
```output
10000000000000000000000000 10000000000000000000000000 10000000000000000000000000
0 0 0
-7 -7 -7
2 2
```
