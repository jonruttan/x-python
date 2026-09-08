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
