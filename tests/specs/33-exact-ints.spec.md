The exact-integer cases, split from 32-float-odds-ends for a resource
reason worth recording: these walk 20-to-31-digit magnitudes through the
promoting hand parser, and on the pinned v0.9.0 platform -- whose bigint
ops predate a year of allocation work -- the combined file's batch crossed
the 300M object ceiling and died mid-batch, deterministically, while
current main fit comfortably.  A file that fails by ceiling on one
platform reads as a regression that is not one.  Same contract, its own
process.

## int of float is exact

### bigints included

```python
(python-run "print((int(1e19), int(2.0**100), int(1418774543.0), int(-2.7)))")
```
---
    (10000000000000000000, 1267650600228229401496703205376, 1418774543, -2)

### int, trunc, floor, ceil and %d share one conversion, and its refusals

```python
(python-run "import math\n\nfor v in (0.5, -0.5, -1.9, 2.0 ** 53 + 2, 2.0 ** 62, -(2.0 ** 62), -(2.0 ** 63), 1e19, -1e19):\n    print(int(v), math.trunc(v), math.floor(v), math.ceil(v), \"%d\" % v)\nprint(int(2.0 ** 1023) == 2 ** 1023, int(-1.7976931348623157e308) == -(2 ** 53 - 1) * 2 ** 971)\nprint(-(2 ** 63) == int(-(2.0 ** 63)), {-(2 ** 63): \"k\"}[int(-(2.0 ** 63))])\n\n\ndef err(f):\n    try:\n        f()\n    except (OverflowError, ValueError) as e:\n        print(type(e).__name__, e)\n\n\nfor x in (float(\"inf\"), float(\"-inf\"), float(\"nan\")):\n    err(lambda: int(x))\n    err(lambda: \"%d\" % x)")
```
---
```output
0 0 0 1 0
0 0 -1 0 0
-1 -1 -2 -1 -1
9007199254740994 9007199254740994 9007199254740994 9007199254740994 9007199254740994
4611686018427387904 4611686018427387904 4611686018427387904 4611686018427387904 4611686018427387904
-4611686018427387904 -4611686018427387904 -4611686018427387904 -4611686018427387904 -4611686018427387904
-9223372036854775808 -9223372036854775808 -9223372036854775808 -9223372036854775808 -9223372036854775808
10000000000000000000 10000000000000000000 10000000000000000000 10000000000000000000 10000000000000000000
-10000000000000000000 -10000000000000000000 -10000000000000000000 -10000000000000000000 -10000000000000000000
True True
True k
OverflowError cannot convert float infinity to integer
OverflowError cannot convert float infinity to integer
OverflowError cannot convert float infinity to integer
OverflowError cannot convert float infinity to integer
ValueError cannot convert float NaN to integer
ValueError cannot convert float NaN to integer
```

## big integer literals

### past two to the sixty-three, no wrap

```python
(python-run "print((99999999999999999999, -99999999999999999999))")
```
---
    (99999999999999999999, -99999999999999999999)
