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
## what these three will not do

### a globals or locals mapping is refused

DIVERGENCE, and a deliberate one.  Python's `eval` and `exec` take mappings and
run the source *in* them; a Python name here is an x global, so there is no
dictionary standing for a scope and nothing to swap one for.  Ignoring the
argument would run the code in the wrong scope and answer with confidence, so
it is refused instead.  `None` means "the one you are in" -- the only one there
is -- and passes.  CPython prints `3` for the first line and `11` for the
second; this prints neither.

```python
(python-run "foo = 11\nexec('print(foo)', None)\nexec('print(foo)', None, None)\ntry:\n    exec('print(foo)', {'foo': 3})\nexcept TypeError as e:\n    print('TypeError')")
```
---
```output
11
11
TypeError
```

### dir() with no argument is refused

DIVERGENCE, for the same reason: Python's bare `dir()` answers with the current
namespace, and there is no namespace object here to ask.  `dir(x)` is the whole
of what this can answer truthfully.

```python
(python-run "try:\n    dir()\nexcept TypeError:\n    print('TypeError')\nprint(len(dir(1)) >= 0)")
```
---
```output
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
