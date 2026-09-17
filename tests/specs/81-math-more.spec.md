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

### erf, erfc, gamma and lgamma

```python
(python-run "from math import erf, erfc, gamma, lgamma\nxs = [-8.0, -2.5, -1.2, -0.5, -0.0, 0.0, 0.3, 1.0, 1.4999, 1.5, 2.5, 8.0, 29.5, 31.0]\nfor x in xs:\n    print(\"%g: %.10g %.10g\" % (x, erf(x), erfc(x)))\ngs = [0.001, 0.1, 0.5, 1.0, 1.5, 3.0, 4.75, 10.0, 23.0, 24.0, 50.5, 140.5, 171.5, -0.5, -1.5, -7.25, -150.5]\nfor x in gs:\n    print(\"%g: %.10g %.10g\" % (x, gamma(x), lgamma(x)))")
```
---
```output
-8: -1 2
-2.5: -0.999593048 1.999593048
-1.2: -0.9103139782 1.910313978
-0.5: -0.5204998778 1.520499878
-0: -0 1
0: 0 1
0.3: 0.3286267595 0.6713732405
1: 0.8427007929 0.1572992071
1.4999: 0.9660932517 0.03390674834
1.5: 0.9661051465 0.03389485352
2.5: 0.999593048 0.0004069520174
8: 1 1.122429717e-29
29.5: 1 0
31: 1 0
0.001: 999.4237725 6.907178885
0.1: 9.513507699 2.252712652
0.5: 1.772453851 0.5723649429
1: 1 0
1.5: 0.8862269255 -0.1207822376
3: 2 0.6931471806
4.75: 16.58620654 2.808571419
10: 362880 12.80182748
23: 1.124000728e+21 48.47118135
24: 2.585201674e+22 51.60667557
50.5: 4.290462912e+63 146.5192555
140.5: 1.136732321e+240 552.7485801
171.5: 9.483367567e+307 709.143163
-0.5: -3.544907702 1.265512123
-1.5: 2.363271801 0.8600470154
-7.25: 0.0005303977064 -7.541883443
-150.5: -4.478447658e-264 -606.3831881
```

### their domain and range errors, and tanh far from zero

```python
(python-run "import math\ninf = float(\"inf\")\ndef show(name, f, x):\n    try:\n        print(name, x, repr(f(x)))\n    except (ValueError, OverflowError) as e:\n        print(name, x, type(e).__name__, e)\nfor x in (0.0, -0.0, -1.0, -inf, inf, 172.0, 1e-300, -200.5, -201.5):\n    show(\"gamma\", math.gamma, x)\nfor x in (0.0, -2.0, 1.0, 2.0, -inf, inf, 1e308, 1e-25):\n    show(\"lgamma\", math.lgamma, x)\nfor x in (inf, -inf, float(\"nan\")):\n    show(\"erf\", math.erf, x)\n    show(\"erfc\", math.erfc, x)\nfor x in (-1e6, -100.0, 20.5, 1e6):\n    show(\"tanh\", math.tanh, x)\nprint(math.gamma(5), \"%.12g\" % math.lgamma(3), \"%.12g\" % math.erf(True))")
```
---
```output
gamma 0.0 ValueError expected a noninteger or positive integer, got 0.0
gamma -0.0 ValueError expected a noninteger or positive integer, got -0.0
gamma -1.0 ValueError expected a noninteger or positive integer, got -1.0
gamma -inf ValueError expected a noninteger or positive integer, got -inf
gamma inf inf
gamma 172.0 OverflowError math range error
gamma 1e-300 9.999999999999999e+299
gamma -200.5 -0.0
gamma -201.5 0.0
lgamma 0.0 ValueError expected a noninteger or positive integer, got 0.0
lgamma -2.0 ValueError expected a noninteger or positive integer, got -2.0
lgamma 1.0 0.0
lgamma 2.0 0.0
lgamma -inf inf
lgamma inf inf
lgamma 1e+308 OverflowError math range error
lgamma 1e-25 57.564627324851145
erf inf 1.0
erfc inf 0.0
erf -inf -1.0
erfc -inf 2.0
erf nan nan
erfc nan nan
tanh -1000000.0 -1.0
tanh -100.0 -1.0
tanh 20.5 1.0
tanh 1000000.0 1.0
24.0 0.69314718056 0.84270079295
```
