# break and continue

### break stops the loop

```python
(python-run "for i in range(5):\n    print(i)\n    if i == 2:\n        break\nprint(\"after\", i)")
```
---
```output
0
1
2
after 2
```

### continue skips the rest of the iteration

```python
(python-run "for i in range(6):\n    if i % 2 == 0:\n        continue\n    print(i)\nprint(\"done\")")
```
---
```output
1
3
5
done
```

### break in a while loop

```python
(python-run "n = 0\nwhile True:\n    n = n + 1\n    if n == 4:\n        break\nprint(\"n =\", n)")
```
---
```output
n = 4
```

### continue in a while loop

```python
(python-run "n = 0\ntotal = 0\nwhile n < 6:\n    n = n + 1\n    if n == 3:\n        continue\n    total = total + n\nprint(total)")
```
---
```output
18
```

### break leaves only the inner loop

```python
(python-run "for i in range(3):\n    for j in range(3):\n        if j == 1:\n            break\n        print(i, j)\n    print(\"outer\", i)")
```
---
```output
0 0
outer 0
1 0
outer 1
2 0
outer 2
```

### continue belongs to the nearest loop

```python
(python-run "for i in range(3):\n    for j in range(3):\n        if j == 1:\n            continue\n        print(i, j)")
```
---
```output
0 0
0 2
1 0
1 2
2 0
2 2
```

### a break deep in a body

```python
(python-run "for w in [\"a\", \"bb\", \"ccc\", \"dddd\"]:\n    if len(w) > 1:\n        if w[0] == \"c\":\n            print(\"found\", w)\n            break\n    print(\"saw\", w)")
```
---
```output
saw a
saw bb
found ccc
```

### a loop with no break is untouched

```python
(python-run "for i in range(3):\n    print(i)\nfor j in range(3):\n    if j == 1:\n        break\n    print(\"j\", j)")
```
---
```output
0
1
2
j 0
```

### break on the header line

```python
(python-run "while True: break\nprint(\"out\")")
```
---
```output
out
```

### continue on the header line

```python
(python-run "for i in range(4):\n    if i == 2: continue\n    print(i)")
```
---
```output
0
1
3
```

### break inside try/except

```python
(python-run "for i in range(5):\n    try:\n        if i == 2:\n            raise ValueError(\"v\")\n        print(\"ok\", i)\n    except ValueError:\n        print(\"caught\")\n        break\nprint(\"after\")")
```
---
```output
ok 0
ok 1
caught
after
```

### break inside try/finally

`break` invokes an escape continuation, and that continuation used to jump
straight past the `guard` a `finally` compiles to, so the cleanup for the
iteration that breaks never ran.  It runs now: the block registers its cleanup
on a wind stack and the escape settles what it is about to skip before it jumps
(python/runtime.x, "Unwinding on the way out"), so `finally 1` prints before
`after`.

```python
(python-run "for i in range(4):\n    try:\n        if i == 1:\n            break\n        print(\"body\", i)\n    finally:\n        print(\"finally\", i)\nprint(\"after\")")
```
---
```output
body 0
finally 0
finally 1
after
```

### continue inside try/finally

`continue` leaves the block too, and pays the same debt -- once per iteration,
including the iterations it skips the rest of.

```python
(python-run "for i in range(3):\n    try:\n        if i == 1:\n            continue\n        print(\"body\", i)\n    finally:\n        print(\"fin\", i)\nprint(\"after\")")
```
---
```output
body 0
fin 0
fin 1
body 2
fin 2
after
```

### break inside with

`__exit__` runs off the normal and the exceptional paths, and a continuation
escape is neither -- so the escape carries it, as the normal exit it is:
`__exit__(None, None, None)`, and a third `exit` on the way out.

```python
(python-run "class C:\n    def __enter__(self):\n        print(\"enter\")\n        return self\n    def __exit__(self, a, b, c):\n        print(\"exit\")\nfor i in range(3):\n    with C():\n        print(\"body\", i)\n        if i == 1:\n            break\nprint(\"after\")")
```
---
```output
enter
body 0
exit
enter
body 1
exit
after
```

### break in a generator

```python
(python-run "def upto(n):\n    for i in range(n):\n        if i == 3:\n            break\n        yield i\nprint(list(upto(10)))")
```
---
```output
[0, 1, 2]
```

### continue in a generator

```python
(python-run "def odds(n):\n    for i in range(n):\n        if i % 2 == 0:\n            continue\n        yield i\nprint(list(odds(8)))")
```
---
```output
[1, 3, 5, 7]
```

### break out of a loop over a string

```python
(python-run "for ch in \"hello\":\n    if ch == \"l\":\n        break\n    print(ch)")
```
---
```output
h
e
```

### break out of a loop over a dict

```python
(python-run "d = {\"a\": 1, \"b\": 2, \"c\": 3}\nfor k in d:\n    if d[k] == 2:\n        print(\"stop at\", k)\n        break\n    print(k)")
```
---
```output
a
stop at b
```

### continue with a counter in a while

```python
(python-run "i = 0\nseen = []\nwhile i < 8:\n    i = i + 1\n    if i % 3 != 0:\n        continue\n    seen.append(i)\nprint(seen)")
```
---
```output
[3, 6]
```

### a break in a method

```python
(python-run "class C:\n    def first_even(self, xs):\n        for x in xs:\n            if x % 2 == 0:\n                return x\n        return None\n    def upto_zero(self, xs):\n        out = []\n        for x in xs:\n            if x == 0:\n                break\n            out.append(x)\n        return out\nc = C()\nprint(c.first_even([1, 3, 6, 8]), c.upto_zero([4, 5, 0, 9]))")
```
---
```output
6 [4, 5]
```

### break inside a comprehension's loop is not the comprehension's

```python
(python-run "for n in range(4):\n    xs = [x for x in range(n)]\n    if len(xs) == 2:\n        print(\"stop\", xs)\n        break\n    print(n, xs)")
```
---
```output
0 []
1 [0]
stop [0, 1]
```
## outside a loop

Python refuses these while COMPILING, before the module runs a line; so does
this, from `python-parse`, and for the same reason -- the escape is bound by a
loop, so a `break` still free in a whole scope is outside every loop.  The
words differ (Python says `SyntaxError: 'break' outside loop`, and points at
the line); the refusal, and its timing, do not.

### break at module level

```python
(python-run "break")
```
---
```output
Error: #<err:syntax 'break' outside loop>
```

### continue at module level

```python
(python-run "continue")
```
---
```output
Error: #<err:syntax 'continue' not properly in loop>
```

### the refusal comes before the module runs

```python
(python-run "print(\"first\")\nbreak")
```
---
```output
Error: #<err:syntax 'break' outside loop>
```

### a break in a def inside a loop belongs to no loop

The def is its own scope: the loop around it is not around the `break`.

```python
(python-run "for i in range(3):\n    def g():\n        break\n    g()")
```
---
```output
Error: #<err:syntax 'break' outside loop>
```

### a continue under an if, still outside a loop

```python
(python-run "x = 1\nif x:\n    continue")
```
---
```output
Error: #<err:syntax 'continue' not properly in loop>
```
