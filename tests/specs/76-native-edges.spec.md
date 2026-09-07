# a layout conflict, a builtin beside a user base, and more exceptions

### two builtin bases are a layout conflict

```python
(python-run "try:\n    class A(type, tuple):\n        None\nexcept TypeError:\n    print('TypeError')\nclass B(tuple):\n    pass\nprint(len(B([1, 2])))")
```
---
```output
TypeError
2
```

### a user base beside a builtin one

```python
(python-run "class Base1:\n    def __init__(self, *args):\n        print(\"Base1.__init__\", args)\nclass Ctuple1(Base1, tuple):\n    pass\na = Ctuple1()\nprint(len(a))\na = Ctuple1([1, 2, 3])\nprint(len(a))\nclass Ctuple2(tuple, Base1):\n    pass\nb = Ctuple2([1, 2, 3])\nprint(len(b))\nprint(tuple([1, 2, 3]) == b)")
```
---
```output
Base1.__init__ ()
0
Base1.__init__ ([1, 2, 3],)
3
Base1.__init__ ([1, 2, 3],)
3
True
```

### OSError carries errno

```python
(python-run "class MyOSError(OSError):\n    pass\nprint(MyOSError().errno)\nprint(MyOSError(1, \"msg\").errno)\nprint(IOError is OSError)\ntry:\n    raise OSError(2, \"no such file\")\nexcept OSError as e:\n    print(e.errno, e.args)")
```
---
```output
None
1
True
2 (2, 'no such file')
```

### the exception names a program expects to exist

```python
(python-run "print(EOFError.__name__, KeyboardInterrupt.__name__, UnicodeError.__name__)\nprint(issubclass(IndentationError, SyntaxError), issubclass(UnicodeError, ValueError))\nprint(issubclass(KeyboardInterrupt, BaseException), issubclass(KeyboardInterrupt, Exception))")
```
---
```output
EOFError KeyboardInterrupt UnicodeError
True True
True False
```
