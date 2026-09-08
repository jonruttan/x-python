# sys.platform, from the platform

### sys.platform names a real platform

```python
(python-run "import sys\nprint(sys.platform in (\"darwin\", \"linux\", \"win32\"))\nprint(type(sys.platform).__name__)\nprint(sys.platform == sys.platform)")
```
---
```output
True
str
True
```

### sys.implementation says what is running

```python
(python-run "import sys\nprint(type(sys.implementation.name).__name__)\nprint(len(sys.implementation.name) > 0)")
```
---
```output
str
True
```

### the other attributes a probe reads

```python
(python-run "import sys\nprint(sys.byteorder in (\"little\", \"big\"))\nprint(type(sys.maxsize).__name__, sys.maxsize > 0)\nprint(type(sys.path).__name__, type(sys.modules).__name__)")
```
---
```output
True
int True
list dict
```
