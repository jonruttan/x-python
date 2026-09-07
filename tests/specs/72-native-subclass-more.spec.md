# subclassing tuple, str, dict, bytes and an exception

### a tuple subclass compares both ways

```python
(python-run "class mytuple(tuple):\n    pass\nt = mytuple((1, 2, 3))\nprint(t)\nprint(t == (1, 2, 3))\nprint((1, 2, 3) == t)\nprint(t < (1, 2, 3), t < (1, 2, 4))\nprint((1, 2, 3) <= t, (1, 2, 4) < t)\nprint(len(t), t[0], t[-1])")
```
---
```output
(1, 2, 3)
True
True
False True
True False
3 1 3
```

### a str subclass compares both ways

```python
(python-run "class S(str):\n    pass\ns = S('hello')\nprint(s == 'hello')\nprint('hello' == s)\nprint(s == 'Hello')\nprint('Hello' == s)\nprint(len(s), s[0], s + '!')")
```
---
```output
True
True
False
False
5 h hello!
```

### containment on subclasses of native types

```python
(python-run "class mylist(list):\n    pass\nclass mydict(dict):\n    pass\nclass mybytes(bytes):\n    pass\nl = mylist([1, 2, 3])\nprint(0 in l, 1 in l)\nd = mydict({1: 1, 2: 2})\nprint(0 in d, 1 in d)\nb = mybytes(b'1234')\nprint(b'0' in b, b'1' in b)")
```
---
```output
False True
False True
False True
```

### a native exception subclass carries its arguments

```python
(python-run "class MyExc(Exception):\n    pass\ne = MyExc(100, \"Some error\")\nprint(e)\nprint(repr(e))\nprint(e.args)\ntry:\n    raise MyExc(\"Some error\", 1)\nexcept MyExc as e:\n    print(\"Caught exception:\", repr(e))\ntry:\n    raise MyExc(\"Some error2\", 2)\nexcept Exception as e:\n    print(\"Caught exception:\", repr(e))\nprint(str(MyExc('one')), '|', str(MyExc()))")
```
---
```output
(100, 'Some error')
MyExc(100, 'Some error')
(100, 'Some error')
Caught exception: MyExc('Some error', 1)
Caught exception: MyExc('Some error2', 2)
one | 
```
