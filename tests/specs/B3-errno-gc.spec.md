# errno and gc

`errno` names the host's error numbers, read from the platform's own table,
and `errorcode` maps each back to its name.  The numbers checked here are the
ones Darwin and Linux share.  `gc` has a flag `enable()` and `disable()` turn
and `isenabled()` reads; there is no automatic collector for it to stop.
The expectations are CPython 3.14's.

## errno

### the constants, errorcode, and an OSError's errno

```python
(python-run "import errno\nprint(errno.ENOENT, errno.EIO, errno.EACCES, errno.EEXIST, errno.EINVAL)\nprint(errno.errorcode[errno.ENOENT], errno.errorcode[errno.EIO])\nok = True\nfor c, n in errno.errorcode.items():\n    ok = ok and getattr(errno, n) == c\nprint(type(errno.errorcode).__name__, ok)\ntry:\n    open(\"/no/such/file\")\nexcept OSError as e:\n    print(e.errno == errno.ENOENT, errno.errorcode[e.errno])\nprint(errno.__name__)")
```
---
```output
2 5 13 17 22
ENOENT EIO
dict True
True ENOENT
errno
```

## gc

### enable, disable and isenabled

```python
(python-run "import gc\nprint(gc.isenabled())\nprint(gc.disable())\nprint(gc.isenabled())\nprint(gc.enable())\nprint(gc.isenabled())\nprint(gc.collect() >= 0)")
```
---
```output
True
None
False
None
True
True
```
