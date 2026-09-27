# import: what this runtime offers, and what it refuses

### import binds the module

```python
(python-run "import sys\nprint(type(sys).__name__)\nprint(sys.byteorder, sys.maxsize)\nimport sys as system\nprint(system.byteorder)")
```
---
```output
module
little 9223372036854775807
little
```

### a module this runtime does not have

```python
(python-run "try:\n    import nosuchmodule\nexcept ImportError as e:\n    print(\"ImportError\")\ntry:\n    from nosuchmodule import thing\nexcept ImportError:\n    print(\"ImportError\")")
```
---
```output
ImportError
ImportError
```

### the feature probe the corpus writes

```python
(python-run "try:\n    import uos, utime\nexcept ImportError:\n    print(\"SKIP\")\nelse:\n    print(\"have them\")")
```
---
```output
SKIP
```

### from import, with and without as

```python
(python-run "from sys import byteorder\nprint(byteorder)\nfrom sys import byteorder as bo, maxsize\nprint(bo, maxsize)\ntry:\n    from sys import nosuchattr\nexcept ImportError:\n    print(\"ImportError\")")
```
---
```output
little
little 9223372036854775807
ImportError
```

### __import__ checks its argument

```python
(python-run "try:\n    __import__(1)\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    __import__(\"\")\nexcept ValueError:\n    print(\"ValueError\")\nm = __import__(\"sys\")\nprint(m.byteorder)")
```
---
```output
TypeError
ValueError
little
```

### a relative import has no package to be relative to

```python
(python-run "for src in (\"from . import foo\", \"from .a import b\", \"from .. import c\", \"from .a.b import *\"):\n    try:\n        exec(src)\n    except ImportError as e:\n        print(\"ImportError\", e)")
```
---
```output
ImportError attempted relative import with no known parent package
ImportError attempted relative import with no known parent package
ImportError attempted relative import with no known parent package
ImportError attempted relative import with no known parent package
```

### import * only at module level

```python
(python-run "try:\n    exec(\"def foo():\\n    from math import *\")\nexcept SyntaxError as e:\n    print(\"SyntaxError\", str(e).split(\" (\")[0])\ntry:\n    exec(\"class C:\\n    from math import *\")\nexcept SyntaxError:\n    print(\"SyntaxError\")\nfrom math import *\nprint(floor(2.5))")
```
---
```output
SyntaxError import * only allowed at module level
SyntaxError
2
```

## a module is its environment

A module's names are an environment of its own, and the module a program holds
is that environment: an attribute is a binding the module's code sees too. The
program itself is the module `__main__`, in a `sys.modules` table of its own.

### the program is the module __main__

```python
(python-run "if __name__ == \"__main__\":\n    print(\"main\")\nimport __main__\nprint(repr(__main__).startswith(\"<module '__main__'\"))\nx = 1\nprint(__main__.x)\n__main__.y = 2\nprint(y)\ndel __main__.x\nprint(\"x\" in globals())")
```
---
```output
main
True
1
2
False
```

### sys.modules is the program's own table, any value a module

```python
(do
  (python-run "import sys\nprint(\"sys\" in sys.modules, \"__main__\" in sys.modules)\nclass A:\n    def __init__(self, v):\n        self.v = v\n    def get(self):\n        return self.v\nsys.modules[\"mod\"] = A(1)\nimport mod\nprint(mod.get())\nfrom mod import get\nprint(get())")
  (python-run "import sys\nprint(\"mod\" in sys.modules)"))
```
---
```output
True True
1
1
False
```

### a module's attributes are its names

```python
(python-run "import math\nprint(type(math).__name__, math.__name__)\nprint(\"floor\" in dir(math), \"pi\" in math.__dict__)\nmath.tau2 = 2 * math.pi\nprint(math.tau2 > 6)\ndel math.tau2\ntry:\n    math.tau2\nexcept AttributeError as e:\n    print(\"AttributeError\", e)")
```
---
```output
module math
True True
True
AttributeError module 'math' has no attribute 'tau2'
```

### import * takes __all__, and a module's __getattr__ answers what it lacks

```python
(python-run "import sys\nclass M:\n    __all__ = (\"y\",)\n    x = \"b1\"\n    y = \"b2\"\nsys.modules[\"mod\"] = M\nx = None\nfrom mod import *\nprint(x, y)\nthis = __import__(__name__)\ndef __getattr__(attr):\n    if attr == \"does_not_exist\":\n        return False\n    raise AttributeError\nprint(this.does_not_exist)\ntry:\n    this.other\nexcept AttributeError:\n    print(\"AttributeError\")")
```
---
```output
None b2
False
AttributeError
```

### globals() and dir() are the program's names

```python
(python-run "a = 1\ndef f():\n    return sorted(k for k in globals() if not k.startswith(\"__\"))\nprint(f())\nprint(\"a\" in dir(), \"f\" in dir())")
```
---
```output
['a', 'f']
True True
```

### a bare dir(), locals() or vars() is the names where it is called

```python
(python-run "g = 1\ndef f(a, b=2):\n    c = a + b\n    print(sorted(locals()), sorted(dir()))\n    print(locals()[\"c\"], vars()[\"a\"])\nf(1)\nprint([n for n in dir() if not n.startswith(\"__\")])\ndef k(a, *r, z=3, **kw):\n    q = 1\n    return sorted(locals())\nprint(k(1, 2, y=4))\ndef outer():\n    v = 1\n    def inner(w):\n        return sorted(dir())\n    return inner(2)\nprint(outer())\nprint([n for n in dir() if not n.startswith(\"__\")])")
```
---
```output
['a', 'b', 'c'] ['a', 'b', 'c']
3 1
['f', 'g']
['a', 'kw', 'q', 'r', 'z']
['w']
['f', 'g', 'k', 'outer']
```

## importing a file

`import` finds a module on the program's path, `sys.path`, whose first entry is
the directory of the file the program runs as.  These run as
`tests/modules/main.py` against the modules beside it.

### a module beside the program is found, and keeps its own names

```python
(python-run "import alpha\nprint(alpha.x, alpha.twice(4), alpha.__name__)\nprint(alpha.__file__.endswith(\"alpha.py\"))\nx = 10\nprint(alpha.read_x())\nalpha.x = 5\nprint(alpha.read_x())" "tests/modules/main.py")
```
---
```output
1 8 alpha
True
1
5
```

### from-import, as, and import *

```python
(python-run "from alpha import twice as t, x\nprint(t(x))\nfrom alpha import *\nprint(twice(3), \"_hidden\" in dir(), \"read_x\" in dir())" "tests/modules/main.py")
```
---
```output
2
6 False True
```

### a package: its __init__, its submodules, relative imports

```python
(python-run "import pack.leaf\nprint(pack.leaf.leaf_value, pack.leaf_value)\nimport pack.sub.deep as d\nprint(d.depth, d.__name__, d.__package__)\nfrom pack import sub\nprint(sub.__name__, sub is pack.sub)" "tests/modules/main.py")
```
---
```output
pack pack pack
sub pack.sub
ImportError attempted relative import beyond top-level package
leaf deep leaf deep
deep pack.sub.deep pack.sub
pack.sub True
```

### a directory with no __init__.py is a namespace package

```python
(python-run "import space.part\nprint(space.part.where, space.__name__)" "tests/modules/main.py")
```
---
```output
in a namespace package space
```

### a circular import sees what is bound so far

```python
(python-run "import circ_a\nprint(\"done\")" "tests/modules/main.py")
```
---
```output
a sees 2
done
```

### a module that raises is not kept, and runs again

```python
(python-run "import sys\nfor i in range(2):\n    try:\n        import broken\n    except ZeroDivisionError:\n        print(\"ZeroDivisionError\", \"broken\" in sys.modules)" "tests/modules/main.py")
```
---
```output
broken runs
ZeroDivisionError False
broken runs
ZeroDivisionError False
```

### sys.path is the program's own to extend, and a missing module says so

```python
(python-run "import sys\nsys.path.append(sys.path[0] + \"/extra\")\nimport plain\nprint(plain.name)\ntry:\n    import nosuchmodule\nexcept ModuleNotFoundError as e:\n    print(type(e).__name__, e)" "tests/modules/main.py")
```
---
```output
plain
ModuleNotFoundError No module named 'nosuchmodule'
```
