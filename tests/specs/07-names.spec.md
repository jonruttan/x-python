Python's namespace is kept separate from x's, because a Python name that x also
binds would otherwise resolve to x's — `int` is bound in x, so `int(1)` called
it with arguments it never expected and the interpreter died.

Identifiers are prefixed internally. That prefix is a mechanism and must never
reach the programmer: an error naming `py-int` sends them looking for something
they never wrote. So a name that is mentioned but never bound gets a shim that
raises Python's own message with Python's own spelling.

## names undefined

### an undefined name raises with the name the programmer wrote

This case's original example was `int` — chosen when `int` was deliberately
unbound, to pin that the interpreter said `int` and not `py-int`. Then #18 made
`int` a real builtin and the example stopped being an example: `int(1)` answers
1. The point of the case is the SPELLING of the error, so it keeps making that
point with a name that has not graduated.

```python
(python-run "print(frob(1))")
```
---
    Error: #<err:name name 'frob' is not defined>

### int graduated from this file

The old expected output of the case above, kept as its own case because the
change of answer IS the feature: the name stopped raising because it now works.

```python
(python-run "print(int(1))")
```
---
    1

### and a different one names itself

```python
(python-run "print(frobnicate(1))")
```
---
    Error: #<err:name name 'frobnicate' is not defined>

### a bare reference raises too

A read of a name the program never binds is checked whether or not it is
called, so a bare mention raises the same error.

```python
(python-run "print(undefined_thing)")
```
---
    Error: #<err:name name 'undefined_thing' is not defined>

### in an expression, a raise, an except clause and a class base

```python
(python-run "def err(f):\n    try:\n        print(f())\n    except NameError as e:\n        print(\"NameError\", e)\nerr(lambda: zz)\nerr(lambda: zz + 1)\nerr(lambda: [zz])\ndef g():\n    y = 1\n    return y\ng()\nerr(lambda: y)\ntry:\n    raise Nope\nexcept NameError as e:\n    print(\"raise:\", e)\ntry:\n    raise Nope2(\"x\")\nexcept NameError as e:\n    print(\"raise call:\", e)\ntry:\n    try:\n        1 / 0\n    except Missing:\n        pass\nexcept NameError as e:\n    print(\"except:\", e)\ntry:\n    try:\n        1 / 0\n    except (ZeroDivisionError, Missing2):\n        print(\"caught\")\nexcept NameError as e:\n    print(\"except tuple:\", e)\ntry:\n    class K(NoBase):\n        pass\nexcept NameError as e:\n    print(\"base:\", e)")
```
---
```output
NameError name 'zz' is not defined
NameError name 'zz' is not defined
NameError name 'zz' is not defined
NameError name 'y' is not defined
raise: name 'Nope' is not defined
raise call: name 'Nope2' is not defined
except: name 'Missing' is not defined
except tuple: name 'Missing2' is not defined
base: name 'NoBase' is not defined
```

## names bound

### an assigned name is not undefined

```python
(python-run "value = 3\nprint(value)")
```
---
    3

### a def name is not undefined

```python
(python-run "def helper():\n    return 1\nprint(helper())")
```
---
    1

### a parameter is not undefined

A parameter is bound by the call, not by an assignment, so the scan has to read
it out of the def's parentheses.

```python
(python-run "def f(param):\n    return param\nprint(f(9))")
```
---
    9

### a keyword is grammar, not a name

`if` and `while` reach the tokenizer as names. Without knowing them the scan
would emit a NameError shim for the grammar itself.

```python
(python-run "if 1 == 1:\n    print('ok')")
```
---
    ok

### the names a function, lambda or comprehension binds are its own

A read inside a function, lambda or comprehension that binds the name finds that
binding, and a global a function sets reads as the value it set.

```python
(python-run "def f(a, *rest, k=1, **kw):\n    b = a + 1\n    for i in range(2):\n        b += i\n    g = lambda x, *xs: x + len(xs) + b\n    sq = [v * v for v in range(3) if v]\n    d = {p: q for p, q in [(1, 2)]}\n    s = {m for m in \"ab\"}\n    gen = sum(n for n in range(4))\n    def inner(c):\n        nonlocal b\n        b += c\n        return b\n    inner(10)\n    return a, rest, k, kw, b, g(1, 2), sq, d, sorted(s), gen\nprint(f(1, 2, 3, k=4, z=5))\ntotal = 0\nfor i in range(5):\n    acc = i * 2\n    total += acc\nprint(total, acc)\ndef h():\n    global counter\n    counter = 7\nh()\nprint(counter)\nclass C:\n    x = 1\n    def m(self):\n        return self.x\nprint(C().m())\nimport math\nprint(math.floor(2.5))\nfrom math import sqrt\nprint(sqrt(16))\ntry:\n    del counter\n    print(counter)\nexcept NameError as e:\n    print(e)")
```
---
```output
(1, (2, 3), 4, {'z': 5}, 13, 15, [1, 4], {1: 2}, ['a', 'b'], 6)
20 8
7
1
2
4.0
name 'counter' is not defined
```

## names constants

### True

```python
(python-run "print(True)")
```
---
    True

### False

```python
(python-run "print(False)")
```
---
    False

### None prints nothing of its own

```python
(python-run "print(None)\nprint('after')")
```
---
```output
None
after
```
