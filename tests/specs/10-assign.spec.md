Assignment is decided by what follows a *target*, not by the shape of the first
token. The parser reads a list of targets from the tokens (names, subscripts,
attributes, and `( )` or `[ ]` lists of targets, at most one of them starred)
and then looks for `=`; `a = b = v` has two target lists. A postfix expression
followed by an augmented operator is an augmented assignment. If neither
follows, the statement is re-parsed as an expression from the start.

A store depends on the target's shape: a name is a `set!`, a subscript is an
item assignment, and a list of targets unpacks the value into each in turn.

## assign subscript

### store by index

```python
(python-run "x = [1, 2, 3]\nx[0] = 9\nprint(x)")
```
---
    [9, 2, 3]

### store at the end

```python
(python-run "x = [1, 2, 3]\nx[2] = 9\nprint(x)")
```
---
    [1, 2, 9]

### a negative index stores from the end

```python
(python-run "x = [1, 2, 3]\nx[-1] = 9\nprint(x)")
```
---
    [1, 2, 9]

### the store is visible through another name

```python
(python-run "x = [1]\ny = x\nx[0] = 5\nprint(y)")
```
---
    [5]

### out of range raises

```python
(python-run "x = [1]\nx[5] = 0")
```
---
    Error: #<err:index list assignment index out of range>

### the index may be an expression

```python
(python-run "x = [1, 2, 3]\ni = 1\nx[i + 1] = 8\nprint(x)")
```
---
    [1, 2, 8]

## assign augmented

### plus-equals on a name

```python
(python-run "n = 1\nn += 2\nprint(n)")
```
---
    3

### minus-equals

```python
(python-run "n = 10\nn -= 3\nprint(n)")
```
---
    7

### times-equals

```python
(python-run "n = 3\nn *= 4\nprint(n)")
```
---
    12

### plus-equals concatenates strings

```python
(python-run "s = 'a'\ns += 'b'\nprint(s)")
```
---
    ab

### plus-equals on a subscript

```python
(python-run "x = [1, 2]\nx[0] += 10\nprint(x)")
```
---
    [11, 2]

### augmented with a negative literal

The tokenizer glues the sign to the literal, so this is the case where that has
to come apart correctly on the right of an augmented operator.

```python
(python-run "x = [5]\nx[0] += -4\nprint(x)")
```
---
    [1]

### a loop counter with plus-equals

```python
(python-run "i = 0\nwhile i < 3:\n    i += 1\nprint(i)")
```
---
    3

## assign target lists

### a parenthesized or bracketed list of targets, and `(e)` is the name e

```python
(python-run "(a, b) = 1, 2\n[c, d] = [3, 4]\n(e) = 5\n(f,) = [6]\n() = []\n[] = ()\nprint(a, b, c, d, e, f)")
```
---
    1 2 3 4 5 6

### target lists nest

```python
(python-run "a, (b, [c, d]) = 1, (2, [3, 4])\n[(e, f), g] = [(5, 6), 7]\nprint(a, b, c, d, e, f, g)")
```
---
    1 2 3 4 5 6 7

### a starred target takes what the others leave, as a list

```python
(python-run "a, *b = 1, 2, 3\n*c, d = \"xyz\"\ne, *f, g = [1, 2]\n(h, *i), j = (1, 2, 3), 4\nfirst, *rest = range(4)\n*k, = [1, 2]\nprint(a, b, c, d, e, f, g, h, i, j, first, rest, k)")
```
---
    1 [2, 3] ['x', 'y'] z 1 [] 2 1 [2, 3] 4 0 [1, 2, 3] [1, 2]

### chained assignment stores the one value in each target

```python
(python-run "a = b = 1\nc = d = e = [1]\nx = [0]\nx[0] = y = 5\np, q = r = 1, 2\nprint(a, b, c is e, d, x, y, p, q, r)")
```
---
    1 1 True [1] [5] 5 1 2 (1, 2)

### subscripts and attributes in a target list

```python
(python-run "x = [0, 0]\nx[0], x[1] = 1, 2\nx[0], x[1] = x[1], x[0]\n\n\nclass C:\n    pass\n\n\nc = C()\nc.p, c.q = \"pq\"\nd = {}\nd[\"k\"], [c.r, x[0]] = 1, (8, 9)\nprint(x, c.p, c.q, c.r, d)")
```
---
    [9, 1] p q 8 {'k': 1}

### slices in a target list

```python
(python-run "x = [0, 1, 2, 3]\nx[0:2], y = [7, 8, 9], 5\nprint(x, y)\n[x[:1], (x[-1:], z)] = [6], ([4, 4], 1)\nprint(x, z)")
```
---
```output
[7, 8, 9, 2, 3] 5
[6, 8, 9, 2, 4, 4] 1
```

### any iterable unpacks: a str, a dict's keys, an iterator, a generator

```python
(python-run "a, b = \"xy\"\nc, d = {1: 2, 3: 4}\ne, f = iter([5, 6])\ng, h = (i * i for i in range(2, 4))\nprint(a, b, c, d, e, f, g, h)")
```
---
    x y 1 3 5 6 4 9

### an iterator is read one value past the count and no further

```python
(python-run "def gen(n):\n    for i in range(n):\n        print(\"step\", i)\n        yield i\n\n\na, b = gen(2)\nprint(a, b)\ntry:\n    a, b = gen(5)\nexcept ValueError as e:\n    print(\"ValueError\", e)")
```
---
```output
step 0
step 1
0 1
step 0
step 1
step 2
ValueError too many values to unpack (expected 2)
```

### a target list in a function binds its names there

```python
(python-run "a = b = c = d = 0\n\n\ndef f():\n    a, (b, *c) = 1, (2, 3, 4)\n    [d] = [5]\n    return a, b, c, d\n\n\nprint(f(), a, b, c, d)")
```
---
    (1, 2, [3, 4], 5) 0 0 0 0

## assign errors

### a call is not assignable

```python
(python-run "def f():\n    return 1\nf() = 2")
```
---
    Error: #<err:syntax cannot assign to this target>

### a wrong count is refused in CPython's words

```python
(python-run "def err(src):\n    try:\n        exec(src)\n    except (TypeError, ValueError) as e:\n        print(type(e).__name__, e)\n\n\nerr(\"a, b = 1\")\nerr(\"a, b = 1, 2, 3\")\nerr(\"a, b, c = 1, 2\")\nerr(\"a, b = [1, 2, 3]\")\nerr(\"a, b = (x for x in range(3))\")\nerr(\"a, b, c = (x for x in range(2))\")\nerr(\"a, *b, c = (30,)\")\nerr(\"a, *b, c = (x for x in range(1))\")\nerr(\"a, *b = 1\")")
```
---
```output
TypeError cannot unpack non-iterable int object
ValueError too many values to unpack (expected 2, got 3)
ValueError not enough values to unpack (expected 3, got 2)
ValueError too many values to unpack (expected 2, got 3)
ValueError too many values to unpack (expected 2)
ValueError not enough values to unpack (expected 3, got 2)
ValueError not enough values to unpack (expected at least 2, got 1)
ValueError not enough values to unpack (expected at least 2, got 1)
TypeError cannot unpack non-iterable int object
```

### a starred target is one to a list, and never alone

```python
(python-run "for src in (\"a, *b, *c = 1, 2, 3\", \"*a = [1, 2]\", \"[*a, *b] = [1]\"):\n    try:\n        exec(src)\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])")
```
---
```output
SyntaxError multiple starred expressions in assignment
SyntaxError starred assignment target must be in a list or tuple
SyntaxError multiple starred expressions in assignment
```

### a call or a literal in a target list is refused

```python
(python-run "for src in (\"f() = 1\", \"(1, a) = 1, 2\", \"a, f() = 1, 2\"):\n    try:\n        exec(src)\n    except SyntaxError:\n        print(\"SyntaxError\")")
```
---
```output
SyntaxError
SyntaxError
SyntaxError
```

## assign together

### building a list in a loop

```python
(python-run "out = []\ni = 0\nwhile i < 3:\n    out.append(i * i)\n    i += 1\nprint(out)")
```
---
    [0, 1, 4]
