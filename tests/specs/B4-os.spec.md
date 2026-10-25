# os

The operating system as Python names it, each function one of the platform's
`Sys` doors.  What a host answers differs, so the checks are of shape and
agreement: uname() is a five-field named tuple of strs printed as
`posix.uname_result(...)`, the working directory is absolute, the process id
an int.  The expectations are CPython 3.14's.

## the module

### the path spellings, uname, getcwd, getpid, cpu_count and getenv

```python
(python-run "import os\nprint(os.name, os.sep, os.curdir, os.pardir, os.extsep, os.pathsep, repr(os.linesep), os.devnull, os.altsep)\nu = os.uname()\nprint(type(u).__name__, len(u))\nprint(str(u).startswith(\"posix.uname_result(sysname=\"), u.sysname == u[0], u.machine == u[4])\nprint(all(isinstance(v, str) for v in u))\nprint(os.getcwd() == os.getcwd(), os.getcwd().startswith(\"/\"))\nprint(type(os.getpid()).__name__, os.getpid() > 0, os.cpu_count() >= 1)\nprint(os.getenv(\"X_PYTHON_NO_SUCH_VARIABLE\"), os.getenv(\"X_PYTHON_NO_SUCH_VARIABLE\", \"dflt\"))\nprint(type(os.getenv(\"PATH\")).__name__)")
```
---
```output
posix / . .. . : '\n' /dev/null None
uname_result 5
True True True
True
True True
int True True
None dflt
str
```
