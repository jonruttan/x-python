# the standard library: where a module comes from

`import NAME` asks three places, in order: the program's `sys.modules`, the
modules this runtime builds itself (a row each in the class `PyModule`,
python/modules.x), and then the files: each directory on `sys.path`, and after
them the bundle's own `stdlib/`, which holds the library's pure-Python modules.

Where a case's output is what CPython 3.14 prints for the same program, it was
taken from a `python3.14` run; the cases about where a file was found are this
runtime's own.

## a pure-Python module

### keyword is a file under stdlib/

```python
(python-run "import keyword\nprint(len(keyword.kwlist), keyword.kwlist[:3], keyword.kwlist[-1])\nprint(keyword.iskeyword(\"for\"), keyword.iskeyword(\"print\"), keyword.iskeyword(\"match\"))\nprint(keyword.issoftkeyword(\"match\"), keyword.issoftkeyword(\"for\"))\nprint(keyword.softkwlist)\nfrom keyword import iskeyword as k\nprint(k(\"lambda\"), k(\"\"), sorted(keyword.__all__))\nprint([w for w in \"if x is not None and y else z\".split() if keyword.iskeyword(w)])")
```
---
```output
35 ['False', 'None', 'True'] yield
True False False
True False
['_', 'case', 'match', 'type']
True False ['iskeyword', 'issoftkeyword', 'kwlist', 'softkwlist']
['if', 'is', 'not', 'None', 'and', 'else']
```

### it is imported once, and remembered in sys.modules

```python
(python-run "import sys\nimport keyword\nprint(keyword is sys.modules[\"keyword\"], keyword.__name__, type(keyword).__name__)\nimport keyword as again\nprint(again is keyword)")
```
---
```output
True keyword module
True
```

### it was found in the bundle's stdlib/, not on sys.path

```python
(python-run "import sys, keyword\nprint(keyword.__file__.endswith(\"/stdlib/keyword.py\"))\nprint(any(p.endswith(\"stdlib\") for p in sys.path))")
```
---
```output
True
False
```

### a program's own module of that name comes first

A directory the program puts at the front of `sys.path` holds its own
`keyword.py`, and that is the one imported, as in CPython.

```python
(python-run "import sys\nsys.path.insert(0, sys.path[0] + \"/shadow\")\nimport keyword\nprint(keyword.kwlist)" "tests/modules/main.py")
```
---
```output
['shadowed']
```

## a module the runtime builds

### a built-in module has no file

```python
(python-run "import sys, math\nprint(sys)\nprint(math)\nprint(hasattr(sys, \"__file__\"), hasattr(math, \"__file__\"))")
```
---
```output
<module 'sys' (built-in)>
<module 'math' (built-in)>
False False
```

### a built-in module wins over a file of the same name

`tests/modules/shadow/` has a `gc.py`, but the built-in table is asked before
any directory, so even a front-of-path directory cannot replace `gc` -- as in
CPython, where `gc` is built in too.

```python
(python-run "import sys\nsys.path.insert(0, sys.path[0] + \"/shadow\")\nimport gc\nprint(hasattr(gc, \"shadowed\"), hasattr(gc, \"collect\"))" "tests/modules/main.py")
```
---
```output
False True
```

### a row in PyModule is all a new module needs

A static method of `PyModule`, named for the module, that builds it.  This
one answers the module the `math` row builds, under another name.

```python
(%seq
  (PyModule def-static! (lit probe_alias)
    (fn (_ cls) ((python-module-builder "math") cls)))
  (python-run "import probe_alias\nprint(probe_alias.floor(7.5))"))
```
---
```output
7
```

### a name with no row and no file is still not found

```python
(python-run "try:\n    import no_such_stdlib_module\nexcept ModuleNotFoundError as e:\n    print(type(e).__name__, e)")
```
---
```output
ModuleNotFoundError No module named 'no_such_stdlib_module'
```
