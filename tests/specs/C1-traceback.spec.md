# tracebacks

An exception carries where it went: each frame it left, from the one that
caught it down to the one that raised it, with the line each had reached
(`python/runtime-flow.x`, "tracebacks").  The `traceback` module prints and
formats it; `sys.exc_info()` and `sys.exception()` answer the exception an
except clause is handling.  Each program strips the file name from a `File`
line and drops CPython's caret lines (`~~^^`), which this runtime does not
print; the source line under each entry is compared.

## tracebacks

### e.__traceback__, sys.exc_info, sys.exception and print_exception

```python
(python-run "import sys, traceback, io\n\ndef f0():\n    raise ValueError(\"value\")\n\ndef f1():\n    f0()\n\ntry:\n    f1()\nexcept ValueError as e:\n    tb = e.__traceback__\n    print(tb.tb_lineno, tb.tb_frame.f_code.co_name, tb.tb_next.tb_lineno, tb.tb_next.tb_frame.f_code.co_name)\n    print(sys.exc_info()[1] is e, sys.exception() is e)\n    buf = io.StringIO()\n    traceback.print_exception(e, file=buf)\n    for l in buf.getvalue().split(\"\\n\"):\n        if l.startswith(\"  File\"):\n            print(l.split('\"')[0], l.split('\"')[-1])\n        elif not l.startswith(\"    \"):\n            print(l)\nprint(sys.exc_info())\ntry:\n    1 / 0\nexcept ZeroDivisionError:\n    print(traceback.format_exc().splitlines()[-1])\ndef g():\n    try:\n        {}[\"k\"]\n    except KeyError as e:\n        return e\ne = g()\nprint(type(e).__name__, e.__traceback__.tb_lineno, e.__traceback__.tb_next)\nprint(sys.exc_info()[0])")
```
---
```output
10 <module> 7 f1
True True
Traceback (most recent call last):
  File  , line 10, in <module>
  File  , line 7, in f1
  File  , line 4, in f0
ValueError: value

(None, None, None)
ZeroDivisionError: division by zero
KeyError 29 None
None
```

### a runtime error and a method, format_exception and format_exc

```python
(python-run "import sys, traceback\n\ndef show(text):\n    for l in text.rstrip(\"\\n\").split(\"\\n\"):\n        s = l.strip()\n        if s and set(s) <= set(\"~^\"):\n            continue\n        if l.startswith(\"  File \"):\n            p = l.split('\"')\n            l = p[0] + p[2]\n        print(l)\n\ndef div(a, b):\n    return a / b\n\nclass Box:\n    def get(self, k):\n        return {\"a\": 1}[k]\n\ndef outer():\n    try:\n        div(1, 0)\n    except ZeroDivisionError as e:\n        show(\"\".join(traceback.format_exception(e)))\n    try:\n        Box().get(\"z\")\n    except KeyError:\n        show(traceback.format_exc())\n        print(sys.exc_info()[0].__name__)\n    print(sys.exc_info())\n\nouter()")
```
---
```output
Traceback (most recent call last):
  File , line 22, in outer
    div(1, 0)
  File , line 14, in div
    return a / b
ZeroDivisionError: division by zero
Traceback (most recent call last):
  File , line 26, in outer
    Box().get("z")
  File , line 18, in get
    return {"a": 1}[k]
KeyError: 'z'
KeyError
(None, None, None)
```

### recursion, a handler that does not match, limits, the tb_next chain, a cause

```python
(python-run "import traceback\n\ndef show(lines):\n    for l in \"\".join(lines).rstrip(\"\\n\").split(\"\\n\"):\n        s = l.strip()\n        if s and set(s) <= set(\"~^\"):\n            continue\n        if l.startswith(\"  File \"):\n            p = l.split('\"')\n            l = p[0] + p[2]\n        print(l)\n\ndef a(n):\n    if n == 0:\n        raise ValueError(\"bottom\")\n    a(n - 1)\n\ndef through():\n    try:\n        a(2)\n    except TypeError:\n        print(\"not this one\")\n\ntry:\n    through()\nexcept ValueError as e:\n    show(traceback.format_exception(e))\n    show(traceback.format_exception(e, limit=2))\n    show(traceback.format_exception(e, limit=-1))\n    show(traceback.format_tb(e.__traceback__, 1))\n    tb = e.__traceback__\n    n = 0\n    while tb is not None:\n        n += 1\n        last = tb\n        tb = tb.tb_next\n    print(n, last.tb_frame.f_code.co_name, last.tb_lineno)\n\ndef caused():\n    try:\n        {}[\"k\"]\n    except KeyError as k:\n        raise RuntimeError(\"wrapped\") from k\n\ntry:\n    caused()\nexcept RuntimeError as e:\n    show(traceback.format_exception(e))\n    show(traceback.format_exception_only(e))\n\ndef early():\n    try:\n        raise OSError(\"x\")\n    except OSError:\n        return 5\nprint(early(), traceback.format_exc().strip())")
```
---
```output
Traceback (most recent call last):
  File , line 25, in <module>
    through()
  File , line 20, in through
    a(2)
  File , line 16, in a
    a(n - 1)
  File , line 16, in a
    a(n - 1)
  File , line 15, in a
    raise ValueError("bottom")
ValueError: bottom
Traceback (most recent call last):
  File , line 25, in <module>
    through()
  File , line 20, in through
    a(2)
ValueError: bottom
Traceback (most recent call last):
  File , line 15, in a
    raise ValueError("bottom")
ValueError: bottom
  File , line 25, in <module>
    through()
5 a 15
Traceback (most recent call last):
  File , line 41, in caused
    {}["k"]
KeyError: 'k'

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File , line 46, in <module>
    caused()
  File , line 43, in caused
    raise RuntimeError("wrapped") from k
RuntimeError: wrapped
RuntimeError: wrapped
5 NoneType: None
```
