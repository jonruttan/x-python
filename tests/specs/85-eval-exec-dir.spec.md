# eval, exec, compile, dir and Ellipsis

### Ellipsis is a value, and ... is how it is written

```python
(python-run "print(...)\nprint(Ellipsis)\nprint(... == Ellipsis)\nprint(... is Ellipsis)\nprint(type(hash(Ellipsis)))")
```
---
```output
Ellipsis
Ellipsis
True
True
<class 'int'>
```

### Ellipsis travels like any other value

```python
(python-run "def f(x):\n    return x\nprint(f(...))\nxs = [..., 1, ...]\nprint(xs)\nprint(xs.count(...))\nd = {...: \"here\"}\nprint(d[...])")
```
---
```output
Ellipsis
[Ellipsis, 1, Ellipsis]
2
here
```

### pow with a None modulus is two-argument pow

```python
(python-run "print(pow(0, 1, None))\nprint(pow(1, 0, None))\nprint(pow(-2, 3, None))\nprint(pow(3, 8, None))\nprint(pow(4, 5, 3))")
```
---
```output
0
1
-8
6561
1
```

### eval answers an expression

```python
(python-run "print(eval(\"1 + 1\"))\nx = 7\nprint(eval(\"x * 2\"))\nprint(eval(\"[1, 2, 3][1:]\"))\nprint(eval(\"'a' + 'b'\"))")
```
---
```output
2
14
[2, 3]
ab
```

### eval sees what the program defined

```python
(python-run "def double(n):\n    return n * 2\nprint(eval(\"double(21)\"))\nclass C:\n    def __init__(self):\n        self.v = 9\nprint(eval(\"C().v\"))")
```
---
```output
42
9
```

### a doubled comma is a SyntaxError

```python
(python-run "try:\n    print(eval(\"[1,,]\"))\nexcept SyntaxError:\n    print(\"SyntaxError\")")
```
---
```output
SyntaxError
```

### exec runs statements and answers None

```python
(python-run "print(exec(\"def foo(): return 42\"))\nprint(foo())\nexec(\"y = 5\")\nprint(y)\nexec(\"for i in range(3):\\n    print(i)\")")
```
---
```output
None
42
5
0
1
2
```

### exec defines a class, and the class outlives the call

A class reaches the evaluator as a `set!` of what `__build_class__` makes
(`%py-class-of`), and through `exec` that `set!` is reached from inside a
builtin rather than from the top of a program.  The case is here because that
path had no spec — the def, the assignment and the loop above did, and a class
is the one shape none of them covers.
Two execs, so that the SECOND one can name the class the FIRST one bound: a
class that did not really land in the one namespace would fail as a base.

```python
(python-run "exec(\"class D:\\n    def hi(self):\\n        return 'hi'\")\nd = D()\nprint(d.hi())\nexec(\"class E(D):\\n    pass\")\nprint(E().hi())\nprint(isinstance(E(), D))\nexec(\"class F: pass\")\nprint(F().__class__ is F)")
```
---
```output
hi
hi
True
True
```

### compile, and the three modes

```python
(python-run "c = compile(\"10 + 3\", \"f\", \"eval\")\nprint(eval(c))\nexec(compile(\"print(99)\", \"f\", \"exec\"))\nexec(compile(\"print(7)\", \"f\", \"single\"))\ntry:\n    compile(\"1\", \"f\", \"\")\nexcept ValueError:\n    print(\"ValueError\")")
```
---
```output
13
99
7
ValueError
```

### a doubled comma is refused wherever it appears

```python
(python-run "for src in [\"[1,,]\", \"[,1]\", \"f(1,,2)\", \"{1:2,,}\", \"(1,,)\"]:\n    try:\n        eval(src)\n        print(\"accepted\", src)\n    except SyntaxError:\n        print(\"SyntaxError\", src)")
```
---
```output
SyntaxError [1,,]
SyntaxError [,1]
SyntaxError f(1,,2)
SyntaxError {1:2,,}
SyntaxError (1,,)
```

### a trailing comma is still fine

```python
(python-run "print([1,])\nprint((1,))\nprint({1: 2,})\nprint([])\ndef g(a, b=2):\n    return a + b\nprint(g(1,))")
```
---
```output
[1]
(1,)
{1: 2}
[]
3
```

### dir of a class walks the bases

```python
(python-run "class A:\n    def a(self):\n        pass\nclass B(A):\n    def b(self):\n        pass\nclass C2(A):\n    def c(self):\n        pass\nclass D2(B, C2):\n    def d(self):\n        pass\nnames = dir(D2())\nprint(names.count(\"a\"), names.count(\"b\"), names.count(\"c\"), names.count(\"d\"))")
```
---
```output
1 1 1 1
```

### dir of an instance includes what it was given

```python
(python-run "class E:\n    def __init__(self):\n        self.x = 1\n    def m(self):\n        pass\ne = E()\nprint(\"x\" in dir(e), \"m\" in dir(e))\nprint(dir(e) == sorted(dir(e)))")
```
---
```output
True True
True
```
### exec and eval run in the names a mapping stands for

A module's namespace dict stands for the module itself.  Any other dict stands
for an environment made from its entries, whose names are written back to it
once the source has run: a dict here is not a namespace, as it is in CPython,
so its names are copied in and out.  A locals mapping is an environment inside
the globals'.

```python
(python-run "foo = 11\nexec('print(foo)', None)\nexec('print(foo)', {'foo': 3})\nexec('print(foo)', None, {'foo': 5})\nd = {}\nexec(\"def bar():\\n    return 84\\nx = 5\", d)\nprint(d[\"bar\"](), d[\"x\"])\nprint(eval(\"x * 2\", {\"x\": 21}), eval(\"foo + y\", None, {\"y\": 1}))\nexec(\"baz = 'module'\", globals())\nprint(baz)\ntry:\n    exec('print(1)', 'nope')\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
11
3
5
84 5
42 12
module
TypeError
```

## what these three will not do

### dir() with no argument is the names where it is called, and only so

Python's bare `dir()` answers with the names of the scope it is called in, and
the parser hands a bare call the environment it is evaluated in.  DIVERGENCE:
called by another name, `d = dir; d()`, it cannot see where it was called from,
and refuses rather than answer wrongly.

```python
(python-run "foo = 1\nprint(\"foo\" in dir())\nd = dir\ntry:\n    d()\nexcept TypeError:\n    print('TypeError')\nprint(len(dir(1)) >= 0)")
```
---
```output
True
TypeError
True
```

### a builtin type answers only the names its class object carries

DIVERGENCE.  `dir(list)` does not list `append`: a list's methods are reached
by type at the attribute seam rather than hung off the class object, so they
are not there to be found.  Whatever a class DOES carry is reported, which is
why `dir` of a Python class above is complete and this one is not.

```python
(python-run "print('append' in dir(list))\nclass F:\n    def append(self):\n        pass\nprint('append' in dir(F))")
```
---
```output
False
True
```

### eval takes one expression and nothing after it

```python
(python-run "x = 0\nfor s in ['1 2', '1;2', '1\\n2', 'x = 1', '  1', '1 # c', '1\\n', '(1,\\n2)', '1 if 1 else 2', '[x for x in (1, 2)]', '']:\n    try:\n        print(repr(s), '->', repr(eval(s)))\n    except SyntaxError as e:\n        print(repr(s), '-> SyntaxError')\nc = compile('3 4', '<s>', 'exec') if False else None\ntry:\n    compile('3 4', '<s>', 'eval')\nexcept SyntaxError:\n    print('compile SyntaxError')\nprint(eval(compile('5', '<s>', 'eval')))")
```
---
```output
'1 2' -> SyntaxError
'1;2' -> SyntaxError
'1\n2' -> SyntaxError
'x = 1' -> SyntaxError
'  1' -> 1
'1 # c' -> 1
'1\n' -> 1
'(1,\n2)' -> (1, 2)
'1 if 1 else 2' -> 1
'[x for x in (1, 2)]' -> [1, 2]
'' -> SyntaxError
compile SyntaxError
5
```

### dir() asks an object's class for __dir__, and lists a class by the walk

```python
(python-run "class Cud:\n    def __dir__(self):\n        return [\"c\", \"a\", \"b\"]\n\n\nclass Plain:\n    def __init__(self):\n        self.z = 1\n        self.y = 2\n\n\nprint(dir(Cud()), \"a\" in dir(Cud), [n for n in dir(Plain()) if not n.startswith(\"_\")])")
```
---
```output
['a', 'b', 'c'] False ['y', 'z']
```
