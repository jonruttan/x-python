# the parser's refusals

What the parser refuses, as CPython's SyntaxError or IndentationError, in CPython's
words wherever the words match.  Each source runs through `exec`, so the error is
caught where the program can see it.

### indentation: an indented first line, an indent nothing opens, a header with no block

```python
(python-run "def check(src, words=True):\n    try:\n        exec(src)\n        print(\"ok\")\n    except IndentationError as e:\n        if words:\n            print(\"IndentationError\", str(e).split(\" (\")[0])\n        else:\n            print(\"IndentationError\")\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])\n\n\ncheck(\" a1 = 1\\n\")\ncheck(\"a2 = 1\\n  b2 = 2\\n\")\ncheck(\"if 1:\\npass\\n\", False)\ncheck(\"  # a comment\\n\\nc3 = 1\\n\")\ncheck(\"\\n  \\nc4 = 1\\n\")\ntry:\n    exec(\"def f():\\n  a\\n a\\n\")\nexcept SyntaxError as e:\n    print(type(e).__name__, isinstance(e, SyntaxError))")
```
---
```output
IndentationError unexpected indent
IndentationError unexpected indent
IndentationError
ok
ok
IndentationError True
```

### a number run into a name is one bad literal, and into a keyword two tokens

```python
(python-run "for src in (\"123z\", \"1_a\", \"1.real\", \"1jz\", \"0x1fz\", \"0o7z\", \"0b1z\"):\n    try:\n        exec(\"n5 = \" + src)\n        print(\"ok\")\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])\nn6 = 1if 1 else 2\nn7 = [1for i in [0]]\nprint(n6, n7)")
```
---
```output
SyntaxError invalid decimal literal
SyntaxError invalid decimal literal
SyntaxError invalid decimal literal
SyntaxError invalid imaginary literal
SyntaxError invalid hexadecimal literal
SyntaxError invalid octal literal
SyntaxError invalid binary literal
1 [1]
```

### a str and a bytes literal do not join

```python
(python-run "for src in (\"'abc' b'def'\", \"b'a' 'b'\", \"'a' f'{1}' b'c'\"):\n    try:\n        exec(src)\n        print(\"ok\")\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])\nprint('a' 'b', b'a' b'b')")
```
---
```output
SyntaxError cannot mix bytes and nonbytes literals
SyntaxError cannot mix bytes and nonbytes literals
SyntaxError cannot mix bytes and nonbytes literals
ab b'ab'
```

### yield outside a function, await outside an async one

```python
(python-run "for src in (\"yield\", \"class C8:\\n    x = (yield)\", \"await 1\", \"def f8():\\n    await 1\",\n            \"g8 = lambda: (yield)\"):\n    try:\n        exec(src)\n        print(\"ok\")\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])")
```
---
```output
SyntaxError 'yield' outside function
SyntaxError 'yield' outside function
SyntaxError 'await' outside function
SyntaxError 'await' outside async function
ok
```

### nonlocal and global: at module level, with no binding, and against a parameter or each other

```python
(python-run "for src in (\"nonlocal a9\", \"def f9():\\n    def g9():\\n        nonlocal a9\",\n            \"def f9(x9):\\n    global x9\", \"def f9(x9):\\n    nonlocal x9\",\n            \"def f9():\\n    nonlocal x9\\n    global x9\"):\n    try:\n        exec(src)\n        print(\"ok\")\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])\n\n\ndef outer9():\n    v9 = 1\n    def inner9():\n        nonlocal v9\n        v9 = 2\n    inner9()\n    return v9\n\n\nprint(outer9())\ntry:\n    print(v9)\nexcept NameError as e:\n    print(\"NameError\", e)")
```
---
```output
SyntaxError nonlocal declaration not allowed at module level
SyntaxError no binding for nonlocal 'a9' found
SyntaxError name 'x9' is parameter and global
SyntaxError name 'x9' is parameter and nonlocal
SyntaxError name 'x9' is nonlocal and global
2
NameError name 'v9' is not defined
```

### a parameter list names each parameter once, one star, nothing after **

```python
(python-run "for src in (\"def f(a, a): pass\", \"lambda a, a: 1\", \"def f(a, *, a): pass\", \"def f(*a, *b): pass\",\n            \"def f(x, *a, *): pass\", \"def f(**kw, a): pass\", \"lambda **kw, a: 1\", \"def f(*): pass\",\n            \"def f(a=1, b): pass\"):\n    try:\n        exec(src)\n        print(\"ok\")\n    except SyntaxError as e:\n        print(\"SyntaxError\", str(e).split(\" (\")[0])\n\n\ndef f10(a, *rest, k, **kw):\n    return a, rest, k, kw\n\n\nprint(f10(1, 2, k=3, z=4))")
```
---
```output
SyntaxError duplicate argument 'a' in function definition
SyntaxError duplicate argument 'a' in function definition
SyntaxError duplicate argument 'a' in function definition
SyntaxError * argument may appear only once
SyntaxError invalid syntax
SyntaxError arguments cannot follow var-keyword argument
SyntaxError arguments cannot follow var-keyword argument
SyntaxError named arguments must follow bare *
SyntaxError parameter without a default follows parameter with a default
(1, (2,), 3, {'z': 4})
```

### a bare except must be the last clause

```python
(python-run "try:\n    exec(\"try:\\n    a\\nexcept:\\n    pass\\nexcept:\\n    pass\")\nexcept SyntaxError as e:\n    print(\"SyntaxError\", str(e).split(\" (\")[0])\ntry:\n    raise KeyError(1)\nexcept ValueError:\n    print(\"no\")\nexcept:\n    print(\"bare last\")")
```
---
```output
SyntaxError default 'except:' must be last
bare last
```

### a def written on one line keeps its body to itself

```python
(python-run "def gen11(c):\n    def one(): pass\n    if c:\n        yield 1\n\n\nprint(type(gen11(True)).__name__, list(gen11(True)))\n\n\ndef glob11():\n    def one(): pass\n    if True:\n        global g11\n    g11 = 3\n\n\nglob11()\nprint(g11)")
```
---
```output
generator [1]
3
```
