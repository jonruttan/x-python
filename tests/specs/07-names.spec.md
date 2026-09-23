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

### a comprehension's first iterable is read in the enclosing scope

```python
(python-run "def err(f):\n    try:\n        f()\n    except NameError as e:\n        print(e)\nerr(lambda: [a for a in a])\nerr(lambda: {b for b in b})\nerr(lambda: {c: 1 for c in c})\nerr(lambda: list(d for d in d))\ndef f():\n    return [z for z in z]\nerr(f)\nx = [1, 2]\ndef g(w):\n    return [w for w in w]\nprint([x for x in x], [y for x in [[3]] for y in x], g([4]))")
```
---
```output
name 'a' is not defined
name 'b' is not defined
name 'c' is not defined
name 'd' is not defined
name 'z' is not defined
[1, 2] [3] [4]
```

### an attribute, a def read ahead of it, and a lambda's parameter bind no name here

```python
(python-run "class C:\n    counted = 1\n\n\ndef err(name):\n    print(\"NameError\", name)\n\n\nC.only_attr = 2\nC.counted += 1\ntry:\n    print(only_attr)\nexcept NameError as e:\n    err(e)\ntry:\n    print(counted)\nexcept NameError as e:\n    err(e)\ntry:\n    print(late_def)\nexcept NameError as e:\n    err(e)\n\n\ndef late_def():\n    return \"late_def\"\n\n\ng = lambda lam_arg=1: lam_arg\ntry:\n    print(lam_arg)\nexcept NameError as e:\n    err(e)\nprint(late_def(), g(), C.counted, C.only_attr)")
```
---
```output
NameError name 'only_attr' is not defined
NameError name 'counted' is not defined
NameError name 'late_def' is not defined
NameError name 'lam_arg' is not defined
late_def 1 2 2
```

### a store to an attribute in a method leaves the global of that name alone

```python
(python-run "count = 10\n\n\nclass K:\n    def __init__(self):\n        self.count = 0\n\n    def bump(self):\n        self.count += 1\n        key = lambda count=5: count\n        return count, self.count, key()\n\n\nprint(K().bump())")
```
---
    (10, 1, 5)

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

### __debug__ is True

```python
(python-run "print(__debug__, type(__debug__))\nif __debug__:\n    print(\"debug\")")
```
---
```output
True <class 'bool'>
debug
```

### a name may hold characters past ASCII

```python
(python-run "α = 1\nαβγ = 2\nbβ = 3\nβb = 4\nprint(α, αβγ, bβ, βb)\n\n\ndef f(β, γ):\n    δ = β + γ\n    return δ\n\n\nclass φ:\n    def δ(self, ϵ):\n        return ϵ * 2\n\n\nprint(f(1, 2), f(β=3, γ=4), φ().δ(ϵ=5), hasattr(φ(), \"δ\"), getattr(φ(), \"δ\")(6))\nprint(\"{α}\".format(α=7), \"{0}{α}\".format(8, α=9))\nnaïve = \"x\"\nforα = 10\nprint(naïve, forα, [k for k in (\"é\", \"a\")], type(φ()).__name__)")
```
---
```output
1 2 3 4
3 7 10 True 12
7 89
x 10 ['é', 'a'] φ
```
