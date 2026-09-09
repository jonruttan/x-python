# the math module

### the constants

```python
(python-run "import math\nprint(round(math.pi, 10), round(math.e, 10), round(math.tau, 10))\nprint(math.inf, -math.inf, math.isnan(math.nan))\nprint(math.isinf(math.inf), math.isfinite(1.0), math.isfinite(math.inf))")
```
---
```output
3.1415926536 2.7182818285 6.2831853072
inf -inf True
True True False
```

### roots, powers and logs

```python
(python-run "import math\nprint(math.sqrt(9), math.sqrt(2.25))\nprint(math.exp(0), round(math.exp(1), 10))\nprint(math.log(1), round(math.log(math.e), 10), round(math.log(8, 2), 10))\nprint(math.log2(8), math.log10(1000))\nprint(math.pow(2, 10), round(math.hypot(3, 4), 10))")
```
---
```output
3.0 1.5
1.0 2.7182818285
0.0 1.0 3.0
3.0 3.0
1024.0 5.0
```

### the trigonometric family

```python
(python-run "import math\nprint(round(math.sin(0), 10), round(math.cos(0), 10), round(math.tan(0), 10))\nprint(round(math.asin(1), 10), round(math.acos(1), 10), round(math.atan(1), 10))\nprint(round(math.atan2(1, 1), 10))\nprint(round(math.sinh(1), 10), round(math.cosh(1), 10), round(math.tanh(1), 10))\nprint(round(math.asinh(1), 10), round(math.acosh(1), 10), round(math.atanh(0.5), 10))\nprint(round(math.degrees(math.pi), 10), round(math.radians(180), 10))")
```
---
```output
0.0 1.0 0.0
1.5707963268 0.0 0.7853981634
0.7853981634
1.1752011936 1.5430806348 0.761594156
0.881373587 0.0 0.5493061443
180.0 3.1415926536
```

### the integer answers, and factorial

```python
(python-run "import math\nprint(math.floor(2.7), math.ceil(2.1), math.trunc(-2.7))\nprint(math.floor(-2.1), math.ceil(-2.9), math.trunc(2.9))\nprint(math.factorial(0), math.factorial(5), math.factorial(20))\nprint(math.factorial(25))")
```
---
```output
2 3 -2
-3 -2 2
1 120 2432902008176640000
15511210043330985984000000
```

### signs, remainders and scaling

```python
(python-run "import math\nprint(math.fabs(-3.5), math.copysign(3, -1), math.copysign(-3, 1))\nprint(math.fmod(7, 3), math.fmod(-7, 3), math.fmod(7, -3))\nprint(math.ldexp(1, 10), math.ldexp(3, -2))")
```
---
```output
3.5 -3.0 3.0
1.0 -1.0 1.0
1024.0 0.75
```

