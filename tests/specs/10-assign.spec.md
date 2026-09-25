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

### an augmented value is an expression list

```python
(python-run "x = [1]\nx += 2, 3\nt = ()\nt += 4, 5\nprint(x, t)")
```
---
    [1, 2, 3] (4, 5)

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

### a literal or a constant name is not assignable

```python
(python-run "for src in (\"1 = 2\", \"1.5 = x\", \"None += 1\"):\n    try:\n        exec(src)\n    except SyntaxError:\n        print(\"SyntaxError\")\nfor src in (\"None = 1\", \"True = 1\", \"__debug__ = 1\", \"a, None = 1, 2\", \"del None\",\n            \"del a, False\", \"for None in []: pass\", \"[x for True in [1]]\"):\n    try:\n        exec(src)\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])")
```
---
```output
SyntaxError
SyntaxError
SyntaxError
SyntaxError cannot assign to None
SyntaxError cannot assign to True
SyntaxError cannot assign to __debug__
SyntaxError cannot assign to None
SyntaxError cannot delete None
SyntaxError cannot delete False
SyntaxError cannot assign to None
SyntaxError cannot assign to True
```

## assign together

### building a list in a loop

```python
(python-run "out = []\ni = 0\nwhile i < 3:\n    out.append(i * i)\n    i += 1\nprint(out)")
```
---
    [0, 1, 4]

## assignment expressions

### `NAME := value` stores the value and answers it: bracketed, in a call, a subscript, an if and a while

```python
(python-run "(wa := 4)\nprint(wa)\nif wa := 2:\n    print(True)\nprint(wa, [wb := 3, wb * 2], (wc := 1) + 1, wc)\nprint(4, wa := 5, wa)\nwd = [10, 20, 30]\nprint(wd[(we := 1)], we)\nit_a = iter([3, 2, 1, 0, 9])\nwhile (item_a := next(it_a)) != 0:\n    print(\"item\", item_a)\n\n\ndef count_a():\n    la = [0, 1]\n    while local_a := len(la):\n        print(local_a, la.pop())\n\n\ncount_a()")
```
---
```output
4
True
2 [3, 6] 2 1
4 5 5
20 1
item 3
item 2
item 1
2 1
1 0
```

### `:=` in a comprehension binds in the scope around it, as global and nonlocal say

```python
(python-run "def hit_b():\n    print(any((hitb := i) % 5 == 3 and hitb % 2 == 0 for i in range(10)))\n    return hitb\n\n\nhitb = 123\nprint(hit_b(), hitb)\nprint([((mb := k + 1), k * mb) for k in range(4)], mb)\n\n\ndef glob_b():\n    global gb\n    (gb := 5)\n\n\nglob_b()\nprint(gb)\n\n\ndef outer_b():\n    vb = 0\n\n    def inner_b():\n        nonlocal vb\n        (vb := 3)\n\n    inner_b()\n    return vb\n\n\nprint(outer_b(), [yb for v in range(5) if (yb := v % 3) == 1], yb)")
```
---
```output
True
8 123
[(1, 0), (2, 2), (3, 6), (4, 12)] 4
5
3 [1, 1] 1
```

### `:=` stands in brackets and takes a name; anything else is refused in CPython's words

```python
(python-run "for src in (\"xc := 5\", \"yc = xc := 5\", \"ac, xc := 5\", \"(ac.b := 1)\", \"(f() := 1)\", \"(1 := 2)\",\n            \"('s' := 1)\", \"((ac, bc) := 1)\", \"(ac[1:2] := 1)\", \"(-xc := 1)\", \"(True := 1)\",\n            \"def fc(a=xc:=1):\\n    return a\", \"dict(k=xc:=2)\", \"{1: xc := 3}\", \"gc = lambda: xc := 4\"):\n    try:\n        exec(src)\n        print(\"ok\", src)\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])\nprint({(xd := 1): (xd := 2)}, xd, dict(k=(xd := 3)), xd, (lambda: (xd := 4))(), xd)")
```
---
```output
SyntaxError invalid syntax
SyntaxError invalid syntax
SyntaxError invalid syntax
SyntaxError cannot use assignment expressions with attribute
SyntaxError cannot use assignment expressions with function call
SyntaxError cannot use assignment expressions with literal
SyntaxError cannot use assignment expressions with literal
SyntaxError cannot use assignment expressions with tuple
SyntaxError cannot use assignment expressions with subscript
SyntaxError cannot use assignment expressions with expression
SyntaxError cannot use assignment expressions with True
SyntaxError invalid syntax
SyntaxError invalid syntax
SyntaxError invalid syntax
SyntaxError invalid syntax
{1: 2} 2 {'k': 3} 3 4 3
```

### `:=` may not rebind a comprehension's iteration name, and eval binds its names in the module

```python
(python-run "for src in (\"x := 1\", \"((x, y) := 1)\", \"([i := i + 1 for i in range(4)])\", \"([i := -1 for i, j in [(1, 2)]])\",\n            \"([[(i := j) for i in range(2)] for j in range(2)])\", \"([[(j := i) for i in range(2)] for j in range(2)])\",\n            \"[i for i in range(3) if (i := 1)]\", \"[lambda: (i := 1) for i in range(3)][0]()\",\n            \"[ye for x in [1] if (ye := x)]\", \"ye\", \"[[(k := 1) for i in range(2)] for j in range(2)]\"):\n    try:\n        print(eval(src))\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])")
```
---
```output
SyntaxError invalid syntax
SyntaxError cannot use assignment expressions with tuple
SyntaxError assignment expression cannot rebind comprehension iteration variable 'i'
SyntaxError assignment expression cannot rebind comprehension iteration variable 'i'
SyntaxError assignment expression cannot rebind comprehension iteration variable 'i'
SyntaxError assignment expression cannot rebind comprehension iteration variable 'j'
SyntaxError assignment expression cannot rebind comprehension iteration variable 'i'
1
[1]
1
[[1, 1], [1, 1]]
```

### a lambda's `:=` binds the lambda's own name

```python
(python-run "xl = 3\nprint((lambda: (xl := 4))(), xl)\nprint((lambda xl: ((xl := xl + 1), xl))(10), xl)\nfl = lambda n: [(yl := i * n) for i in range(3)] + [yl]\nprint(fl(2))\ntry:\n    print(yl)\nexcept NameError as e:\n    print(\"NameError\", e)\ngl = lambda: (lambda: (zl := 1))()\nprint(gl(), sorted([3, 1, 2], key=lambda v: (kl := -v)), [(ml := 1), lambda: (nl := 2)][0], ml)")
```
---
```output
4 3
(11, 11) 3
[0, 2, 4, 4]
NameError name 'yl' is not defined
1 [3, 2, 1] 1 1
```
