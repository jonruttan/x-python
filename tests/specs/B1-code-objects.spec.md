# Code objects

What `compile()` answers, and what a function's `__code__` is: a value of the
type `code`, which `eval` and `exec` run and `function(code, globals)` makes a
function of.  The expectations are CPython 3.14's.

## code objects

### compile answers a code object, and the mode single prints what its expression statements answer

```python
(python-run "c = compile(\"if 1:\\n    10 + 1\\n    'text'\\n    None\\n    x = 5\\n    print('printed')\\n\", \"a.py\", \"single\")\nprint(type(c).__name__, c.co_filename, c.co_name, type(hash(c)).__name__, hash(c) == hash(c))\nexec(c)\nexec(compile(\"for i in range(2):\\n    i * 2\\n\", \"a.py\", \"single\"))\nexec(compile(\"def f():\\n    1 + 1\\n    return 7\\n\", \"a.py\", \"single\"))\nexec(compile(\"f()\", \"a.py\", \"single\"))\nexec(compile(\"class K:\\n    2 + 2\\n\", \"a.py\", \"single\"))\nexec(compile(\"-f()\", \"a.py\", \"single\"))\nexec(compile(\"not f()\", \"a.py\", \"single\"))\nexec(compile(\"10 + 1\\n[n * n for n in range(3)]\\n\", \"a.py\", \"exec\"))\nprint(eval(compile(\"10 + 3\", \"a.py\", \"eval\")), eval(c), exec(c) is None)\nd = {c: 1}\nprint(d[c], c == c, isinstance(c, type(c)))\nfor mode in (\"\", \"Exec\", \"lambda\"):\n    try:\n        compile(\"1\", \"a.py\", mode)\n    except ValueError as e:\n        print(\"ValueError\", e)\ntry:\n    c.co_nothing\nexcept AttributeError as e:\n    print(\"AttributeError\", e)")
```
---
```output
code a.py <module> int True
11
'text'
printed
0
2
7
-7
False
11
'text'
printed
11
'text'
printed
13 None True
1 True True
ValueError compile() mode must be 'exec', 'eval' or 'single'
ValueError compile() mode must be 'exec', 'eval' or 'single'
ValueError compile() mode must be 'exec', 'eval' or 'single'
AttributeError 'code' object has no attribute 'co_nothing'
```

### a function's code, and the function made of it over other globals

```python
(python-run "def f(x, y=2, *rest, k=3, **kw):\n    return (a, x, y, rest, k, kw)\ncode = f.__code__\nftype = type(f)\nprint(type(code).__name__, code.co_name, code is f.__code__, ftype.__name__, (lambda: 0).__code__.co_name)\ng = ftype(code, {\"a\": \"one\"})\nprint(g(1, 5, 6, k=7, z=8), g.__name__, type(g) is ftype, g is f)\ntry:\n    g(1)\nexcept TypeError as e:\n    print(\"TypeError\", e)\ntry:\n    f(1)\nexcept NameError as e:\n    print(\"NameError\", e)\nh = ftype((lambda n: (lambda: a * n)).__code__, {\"a\": 3})\nprint(h(2)(), h(5)())\ndef gen():\n    yield a\n    yield a + 1\nprint(list(ftype(gen.__code__, {\"a\": 10})()))\nfor args in ((None, {}), (code, None), (compile(\"1\", \"a.py\", \"eval\"), {})):\n    try:\n        ftype(*args)\n    except TypeError:\n        print(\"TypeError\")\ntry:\n    len.__code__\nexcept AttributeError:\n    print(\"AttributeError\")\nm = ftype(compile(\"a + 1\", \"a.py\", \"eval\"), {\"a\": 4})\nn = ftype(compile(\"b = a\", \"a.py\", \"exec\"), {\"a\": 4})\nprint(m(), n(), m.__name__)")
```
---
```output
code f True function <lambda>
('one', 1, 5, (6,), 7, {'z': 8}) f True False
TypeError f() missing 1 required positional argument: 'y'
NameError name 'a' is not defined
6 15
[10, 11]
TypeError
TypeError
AttributeError
5 None <module>
```

### a code object has no bytecode

DIVERGENCE: CPython's code object holds the bytecode the source compiled to,
as `co_code`, and what counts in it, `co_lines()` among them.  There is no
bytecode here, so there are no such attributes.

```python
(python-run "def f():\n    pass\nfor name in ('co_code', 'co_lines', 'co_consts'):\n    print(hasattr(f.__code__, name))")
```
---
```output
False
False
False
```

### the mode single takes more than one statement

DIVERGENCE: CPython compiles one statement in the mode `single` and refuses a
second with a SyntaxError.  Here the mode takes as many as `exec` does.

```python
(python-run "exec(compile('1 + 1\\n2 + 2\\n', 'a.py', 'single'))")
```
---
```output
2
4
```
