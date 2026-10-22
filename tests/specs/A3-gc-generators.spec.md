# gc beside a generator

A suspended generator holds objects only its captured frames reach.  Its
continuations are captured through (Cont capture f), which marks what those
frames hold while it waits; with bare call/cc every collect below segfaulted
(x-lang#283).  Each case collects where only a waiting generator holds the
objects it reads next.

## gc

### a generator's locals survive a collect while it is suspended

```python
(python-run "import gc\ndef g():\n    xs = [i * i for i in range(50)]\n    s = \"pre\" + str(len(xs))\n    yield sum(xs)\n    yield s\n    yield xs[7]\nit = g()\nprint(next(it))\ngc.collect()\nprint(next(it))\ngc.collect()\nprint(next(it))")
```
---
```output
40425
pre50
49
```

### many suspended generators, each collected around

```python
(python-run "import gc\ndef g(k):\n    d = {\"k\": k, \"sq\": [k * j for j in range(10)]}\n    yield d[\"k\"]\n    yield sum(d[\"sq\"])\ngs = [g(k) for k in range(20)]\nfirst = [next(x) for x in gs]\ngc.collect()\nsecond = [next(x) for x in gs]\ngc.collect()\nprint(sum(first), sum(second))")
```
---
```output
190 8550
```

### a collect inside the generator body

```python
(python-run "import gc\ndef g():\n    acc = []\n    for i in range(5):\n        acc.append(str(i) * 3)\n        gc.collect()\n        yield len(acc)\n    yield \",\".join(acc)\nprint(list(g()))")
```
---
```output
[1, 2, 3, 4, 5, '000,111,222,333,444']
```

### nested generators, yield from, a collect between every step

```python
(python-run "import gc\ndef inner(n):\n    for i in range(n):\n        yield [i] * i\ndef outer():\n    yield from inner(4)\n    yield \"end\"\nout = []\nfor v in outer():\n    gc.collect()\n    out.append(v)\nprint(out)")
```
---
```output
[[], [1], [2, 2], [3, 3, 3], 'end']
```

### send and a try/finally across a collect

```python
(python-run "import gc\ndef g():\n    total = 0\n    try:\n        while True:\n            x = yield total\n            total += x\n    finally:\n        print(\"closed\", total)\nit = g()\nnext(it)\nfor k in range(1, 6):\n    gc.collect()\n    it.send(k)\nit.close()")
```
---
```output
closed 15
```

### a collect in a deep call chain and inside a comprehension

```python
(python-run "import gc\ndef f(n):\n    if n == 0:\n        gc.collect()\n        return [\"x\"]\n    return f(n - 1) + [str(n)]\nprint(\"\".join(f(30)))\nprint(sum([len(str(gc.collect())) + i for i in range(10)]))")
```
---
```output
x123456789101112131415161718192021222324252627282930
55
```

### an exception raised and caught across a collect

```python
(python-run "import gc\ndef g():\n    yield 1\n    raise ValueError(\"boom \" + \"x\" * 3)\nit = g()\nnext(it)\ngc.collect()\ntry:\n    next(it)\nexcept ValueError as e:\n    gc.collect()\n    print(type(e).__name__, e)")
```
---
```output
ValueError boom xxx
```

### a long-running loop collecting every iteration

```python
(python-run "import gc\ndef gen():\n    i = 0\n    while True:\n        yield {\"i\": i, \"s\": str(i) * 4}\n        i += 1\nt = 0\nit = gen()\nfor _ in range(30):\n    d = next(it)\n    t += len(d[\"s\"])\n    gc.collect()\nprint(t)")
```
---
```output
200
```

