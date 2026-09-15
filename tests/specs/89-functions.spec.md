# function signatures and calls

### annotations are parsed and have no effect

```python
(python-run "def foo(x: int, y: list) -> dict:\n    return {x: y}\nprint(foo(1, [2, 3]))\ndef bar(a: \"text\" = \"x\", *rest: int, **kw: str) -> None:\n    return a, rest, kw\nprint(bar())\nprint(bar(1, 2, k=3))")
```
---
```output
{1: [2, 3]}
('x', (), {})
(1, (2,), {'k': 3})
```

### keyword-only parameters

```python
(python-run "def f(*, a):\n    print(a)\nf(a=1)\ndef g(a, *, b=2, c):\n    print(a, b, c)\ng(1, c=3)\ng(1, b=5, c=3)\ng(c=3, a=0)\ndef h(*args, k=1):\n    print(args, k)\nh(1, 2)\nh(1, k=9)\ndef both(a, *rest, b, **kw):\n    print(a, rest, b, sorted(kw.items()))\nboth(1, 2, 3, b=4, z=5)")
```
---
```output
1
1 2 3
1 5 3
0 2 3
(1, 2) 1
(1,) 9
1 (2, 3) 4 [('z', 5)]
```

### keyword-only refusals

```python
(python-run "def f(*, a):\n    pass\ntry:\n    f(1)\nexcept TypeError as e:\n    print(e)\ndef g(a, *, b, c):\n    pass\ntry:\n    g(1)\nexcept TypeError as e:\n    print(e)\ntry:\n    g(1, b=2)\nexcept TypeError as e:\n    print(e)\ntry:\n    g(1, 2, 3)\nexcept TypeError as e:\n    print(e)")
```
---
```output
f() takes 0 positional arguments but 1 was given
g() missing 2 required keyword-only arguments: 'b' and 'c'
g() missing 1 required keyword-only argument: 'c'
g() takes 1 positional argument but 3 were given
```

### a call with too few or too many positional arguments

```python
(python-run "def fun2(p1, p2=100, p3=\"foo\"):\n    print(p1, p2, p3)\nfun2(1)\nfun2(1, None)\nfun2(0, \"bar\", 200)\ntry:\n    fun2()\nexcept TypeError as e:\n    print(e)\ntry:\n    fun2(1, 2, 3, 4)\nexcept TypeError as e:\n    print(e)\ndef g(a, b):\n    print(a, b)\ntry:\n    g()\nexcept TypeError as e:\n    print(e)\ntry:\n    g(1)\nexcept TypeError as e:\n    print(e)\ntry:\n    g(1, 2, 3)\nexcept TypeError as e:\n    print(e)")
```
---
```output
1 100 foo
1 None foo
0 bar 200
fun2() missing 1 required positional argument: 'p1'
fun2() takes from 1 to 3 positional arguments but 4 were given
g() missing 2 required positional arguments: 'a' and 'b'
g() missing 1 required positional argument: 'b'
g() takes 2 positional arguments but 3 were given
```

### a default of None is a default

```python
(python-run "def f(a, b=None, c=None):\n    print(a, b, c)\nf(1)\nf(1, 2)\nf(**{\"a\": 1}, **{\"b\": 2})\nf(**{\"a\": 1}, b=2, **{\"c\": 3})\nprint((lambda x, y=None: (x, y))(1))")
```
---
```output
1 None None
1 2 None
1 2 None
1 2 3
(1, None)
```

### a generator binds its parameters when called

```python
(python-run "def gen(n=3):\n    for i in range(n):\n        yield i\nprint(list(gen()))\nprint(list(gen(2)))\ntry:\n    gen(1, 2)\nexcept TypeError as e:\n    print(e)")
```
---
```output
[0, 1, 2]
[0, 1]
gen() takes from 0 to 1 positional arguments but 2 were given
```

### builtin arity

```python
(python-run "try:\n    round()\nexcept TypeError as e:\n    print(e)\ntry:\n    round(1, 2, 3)\nexcept TypeError as e:\n    print(e)\ntry:\n    enumerate()\nexcept TypeError as e:\n    print(e)\ntry:\n    [].append(1, 2)\nexcept TypeError as e:\n    print(e)\ntry:\n    [].sort(1)\nexcept TypeError as e:\n    print(e)\ntry:\n    [].sort(noexist=1)\nexcept TypeError as e:\n    print(e)\nprint(round(2.5), round(1.234, 2))\nl = [3, 1]\nl.sort()\nprint(l)\nl.sort(reverse=True)\nprint(l)")
```
---
```output
round() missing required argument 'number' (pos 1)
round() takes at most 2 arguments (3 given)
enumerate() missing required argument 'iterable'
list.append() takes exactly one argument (2 given)
sort() takes no positional arguments
sort() got an unexpected keyword argument 'noexist'
2 1.23
[1, 3]
[3, 1]
```

### a ** argument may be any mapping

```python
(python-run "def kw(**k):\n    print(sorted(k.items()))\nclass M:\n    def keys(self):\n        return [\"x\", \"y\"]\n    def __getitem__(self, k):\n        return 1 if k == \"x\" else 2\nkw(**M())\nkw(**{\"a\": 1}, **{\"b\": 2})\ntry:\n    kw(**{len: 2})\nexcept TypeError as e:\n    print(e)")
```
---
```output
[('x', 1), ('y', 2)]
[('a', 1), ('b', 2)]
keywords must be strings
```

### a name given twice across ** arguments

The message differs from CPython's by its prefix: `got multiple values for
keyword argument 'b'` here, `f1() got multiple values ...` there. The spread
dicts are merged before the callee is looked up, so the name is not to hand.

```python
(python-run "def f1(**kwargs):\n    print(kwargs)\ntry:\n    f1(**{\"a\": 1, \"b\": 2}, **{\"b\": 3, \"c\": 4})\nexcept TypeError:\n    print(\"TypeError\")\ndef f(a, b=None, c=None):\n    print(a, b, c)\ntry:\n    f(1, **{\"b\": 2}, **{\"b\": 3})\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
TypeError
TypeError
```

### iterable unpacking after keyword unpacking

The except clause prints the name itself: `type(e)` has no arm for an error
raised by the parser, so `type(e).__name__` is not yet an option here.

```python
(python-run "def f(a, b, c, d):\n    print(a, b, c, d)\nf(*(1, 2), **{\"c\": 3, \"d\": 4})\ntry:\n    eval(\"f(**{'a': 1}, *(2, 3, 4))\")\nexcept SyntaxError:\n    print(\"SyntaxError\")")
```
---
```output
1 2 3 4
SyntaxError
```

### a function's repr and name

```python
(python-run "def f():\n    pass\nprint(str(f)[:12], repr(f)[:12])\nprint(f.__name__, (lambda: 0).__name__)\ndef outer():\n    def inner():\n        pass\n    return inner\nprint(outer.__name__, outer().__name__)")
```
---
```output
<function f  <function f 
f <lambda>
outer inner
```
