# for-else and while-else

### the else runs when the loop runs out

```python
(python-run "for i in range(3):\n    print(i)\nelse:\n    print(\"else ran\")\nprint(\"after\")")
```
---
```output
0
1
2
else ran
after
```

### a break skips it

```python
(python-run "for i in range(5):\n    if i == 2:\n        break\n    print(i)\nelse:\n    print(\"never\")\nprint(\"after\")")
```
---
```output
0
1
after
```

### an empty sequence still runs the else

```python
(python-run "for i in []:\n    print(\"body\")\nelse:\n    print(\"else ran\")")
```
---
```output
else ran
```

### while-else, on running out

```python
(python-run "n = 0\nwhile n < 3:\n    print(n)\n    n = n + 1\nelse:\n    print(\"else ran\")")
```
---
```output
0
1
2
else ran
```

### while-else, on breaking

```python
(python-run "n = 0\nwhile True:\n    n = n + 1\n    if n == 2:\n        break\nelse:\n    print(\"never\")\nprint(\"n =\", n)")
```
---
```output
n = 2
```

### a false condition runs the else at once

```python
(python-run "while False:\n    print(\"body\")\nelse:\n    print(\"else ran\")")
```
---
```output
else ran
```

### continue does not skip the else

```python
(python-run "for i in range(4):\n    if i % 2 == 0:\n        continue\n    print(i)\nelse:\n    print(\"else ran\")")
```
---
```output
1
3
else ran
```

### a break in an inner else belongs to the outer loop

```python
(python-run "for i in range(3):\n    print(\"outer\", i)\n    for j in range(2):\n        pass\n    else:\n        print(\"inner else\")\n        break\nprint(\"done\")")
```
---
```output
outer 0
inner else
done
```

### nested loops each with an else

```python
(python-run "for i in range(2):\n    for j in range(2):\n        print(i, j)\n    else:\n        print(\"inner done\", i)\nelse:\n    print(\"outer done\")")
```
---
```output
0 0
0 1
inner done 0
1 0
1 1
inner done 1
outer done
```

### the search idiom

```python
(python-run "def find(xs, want):\n    for x in xs:\n        if x == want:\n            print(\"found\", x)\n            break\n    else:\n        print(\"missing\", want)\nfind([1, 2, 3], 2)\nfind([1, 2, 3], 9)")
```
---
```output
found 2
missing 9
```

### an else on the header line

```python
(python-run "for i in range(2): print(i)\nelse: print(\"else ran\")")
```
---
```output
0
1
else ran
```

### a return leaves before the else

```python
(python-run "def f():\n    for i in range(3):\n        if i == 1:\n            return \"early\"\n    else:\n        print(\"else ran\")\n    return \"late\"\nprint(f())")
```
---
```output
early
```

### a loop with no break at all still has its else

```python
(python-run "for ch in \"ab\":\n    print(ch)\nelse:\n    print(\"else ran\")\nfor k in {\"a\": 1}:\n    print(k)\nelse:\n    print(\"dict else\")")
```
---
```output
a
b
else ran
a
dict else
```

### the else sees the loop variable

```python
(python-run "for i in range(3):\n    pass\nelse:\n    print(\"last was\", i)")
```
---
```output
last was 2
```

### a generator-driven loop and its else

```python
(python-run "def upto(n):\n    for i in range(n):\n        yield i\nfor v in upto(3):\n    print(v)\nelse:\n    print(\"else ran\")")
```
---
```output
0
1
2
else ran
```

### an else after a loop that breaks on the last item

```python
(python-run "for i in range(3):\n    if i == 2:\n        break\nelse:\n    print(\"never\")\nprint(\"after\", i)")
```
---
```output
after 2
```
## the edges of the clause

### a break in a loop-else has no loop around it

The else is not the loop's body: a `break` in one belongs to the ENCLOSING
loop, and with no loop enclosing it there is nothing to break.  Python refuses
this while compiling, `SyntaxError: 'break' outside loop`; so does this, in its
own words and at the same moment.

```python
(python-run "for i in range(2):\n    pass\nelse:\n    break")
```
---
```output
Error: #<err:syntax 'break' outside loop>
```

### elif is not a loop clause

Python answers `SyntaxError: invalid syntax` -- there is no `elif` after a
loop, only `else`.  Here the `elif` is simply not consumed as the loop's, and
is refused as the statement it then has to be.

```python
(python-run "for i in range(2):\n    pass\nelif i:\n    pass")
```
---
```output
Error: #<err:syntax unexpected token in expression>
```

## the escape the else reads is still an escape

The clause is decided by asking a bound `break` continuation which way the loop
left, and that continuation OWES THE SAME UNWINDING every other loop's does: a
`break` out of a `try/finally` or a `with` runs the cleanup on the way past
(python/runtime.x, "Unwinding on the way out"). Reading the answer and paying
the debt are two jobs, and the escape has to do both.

### break out of a try/finally in a for-else

```python
(python-run "for i in range(4):\n    try:\n        if i == 1:\n            break\n        print('body', i)\n    finally:\n        print('fin', i)\nelse:\n    print('else ran')\nprint('after')")
```
---
```output
body 0
fin 0
fin 1
after
```

### break out of a with in a while-else

```python
(python-run "class C:\n    def __enter__(self):\n        print('enter')\n        return self\n    def __exit__(self, a, b, c):\n        print('exit')\ni = 0\nwhile i < 3:\n    with C():\n        print('body', i)\n        if i == 1:\n            break\n    i = i + 1\nelse:\n    print('else ran')\nprint('after')")
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

### a loop that runs out pays its cleanup and still runs its else

```python
(python-run "for i in range(2):\n    try:\n        print('body', i)\n    finally:\n        print('fin', i)\nelse:\n    print('else ran')\nprint('after')")
```
---
```output
body 0
fin 0
body 1
fin 1
else ran
after
```
