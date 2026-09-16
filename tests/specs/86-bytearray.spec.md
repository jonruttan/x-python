# bytearray, and methods off a builtin class

### bytearray is its own type, and says so

```python
(python-run "print(bytearray(b'123'))\nprint(bytearray('1234', 'utf-8'))\nprint(bytearray('12345', 'utf-8', 'strict'))\nprint(bytearray((1, 2)))\nprint(bytearray([1, 2]))\nprint(bytearray())\nprint(type(bytearray(b'a')))\ntry:\n    print(bytearray('1234'))\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
bytearray(b'123')
bytearray(b'1234')
bytearray(b'12345')
bytearray(b'\x01\x02')
bytearray(b'\x01\x02')
bytearray(b'')
<class 'bytearray'>
TypeError
```

### its methods answer bytearrays

```python
(python-run "print(bytearray(b\"aaaa\").count(b\"a\"))\nprint(bytearray(b\"foo\").center(6))\nprint(type(bytearray(b\"foo\").center(6)))\nprint(bytearray(b\"asdsf\").partition(b\"s\"))\nprint(bytearray(b\"asdsf\").rpartition(b\"s\"))\nprint(bytearray(b\"  x  \").strip())\nprint(bytearray(b\"a,b\").split(b\",\"))\nprint(bytearray(b\"ab\").upper())")
```
---
```output
4
bytearray(b' foo  ')
<class 'bytearray'>
(bytearray(b'a'), bytearray(b's'), bytearray(b'dsf'))
(bytearray(b'asd'), bytearray(b's'), bytearray(b'f'))
bytearray(b'x')
[bytearray(b'a'), bytearray(b'b')]
bytearray(b'AB')
```

### bytes and bytearray are compared by content

```python
(python-run "print(b\"123\" == bytearray(b\"123\"))\nprint(b'123' < bytearray(b\"124\"))\nprint(b'123' > bytearray(b\"122\"))\nprint(bytearray(b\"23\") in b\"1234\")\nprint(bytearray(b\"a\") == bytearray(b\"a\"))\nprint(bytearray(b\"a\") != bytearray(b\"b\"))\nprint(b\"a\" <= bytearray(b\"a\"))\nprint(bytearray(b\"b\") >= b\"a\")")
```
---
```output
True
True
True
True
True
True
True
True
```

### it is a sequence of bytes, like bytes

```python
(python-run "b = bytearray(b\"abcd\")\nprint(len(b))\nprint(b[1])\nprint(b[1:3])\nprint(type(b[1:3]))\nprint(list(b))\nprint(b\"c\" in b)\nfor x in bytearray(b\"ab\"):\n    print(x)")
```
---
```output
4
98
bytearray(b'bc')
<class 'bytearray'>
[97, 98, 99, 100]
True
97
98
```

### it mutates, and every name bound to it sees that

```python
(python-run "b = bytearray(b\"ab\")\nb.append(99)\nprint(b)\nb.extend(b\"de\")\nprint(b)\nc = b\nc.append(102)\nprint(b)\nprint(b is c)")
```
---
```output
bytearray(b'abc')
bytearray(b'abcde')
bytearray(b'abcdef')
True
```

### concatenation keeps the left operand's type

```python
(python-run "print(bytearray(b\"a\") + b\"b\")\nprint(type(bytearray(b\"a\") + b\"b\"))\nprint(b\"a\" + bytearray(b\"b\"))\nprint(type(b\"a\" + bytearray(b\"b\")))\nprint(bytearray(b\"ab\") * 2)\nprint(type(bytearray(b\"ab\") * 2))")
```
---
```output
bytearray(b'ab')
<class 'bytearray'>
b'ab'
<class 'bytes'>
bytearray(b'abab')
<class 'bytearray'>
```

### bytes() of a bytearray is a bytes

```python
(python-run "print(bytes(bytearray(b\"xy\")))\nprint(type(bytes(bytearray(b\"xy\"))))\nprint(bytearray(bytearray(b\"xy\")))\nprint(bytes(b\"xy\") == bytearray(b\"xy\"))")
```
---
```output
b'xy'
<class 'bytes'>
bytearray(b'xy')
True
```

### a method read off the class takes its receiver first

```python
(python-run "print(bytes.count(b\"aaaa\", b\"a\"))\nprint(bytes.center(b\"foo\", 6))\nprint(bytearray.count(bytearray(b\"aa\"), b\"a\"))\nprint(bytearray.center(bytearray(b\"foo\"), 6))\nprint(str.upper(\"ab\"))\nprint(list.pop([1, 2, 3]))\nprint(dict.get({\"a\": 1}, \"a\"))\nprint(set.union({1}, {2}))\nprint(dict.fromkeys([\"a\", \"b\"], 0))")
```
---
```output
4
b' foo  '
2
bytearray(b' foo  ')
AB
3
1
{1, 2}
{'a': 0, 'b': 0}
```

### and a name the class does not have is an AttributeError

```python
(python-run "for probe in (\"count\", \"nosuch\"):\n    try:\n        getattr(bytes, probe)\n        print(\"has\", probe)\n    except AttributeError:\n        print(\"AttributeError\", probe)\ntry:\n    list.nosuch\nexcept AttributeError:\n    print(\"AttributeError list\")\ntry:\n    bytearray.nosuch\nexcept AttributeError:\n    print(\"AttributeError bytearray\")")
```
---
```output
has count
AttributeError nosuch
AttributeError list
AttributeError bytearray
```

### a missing receiver, or one of another type, is a TypeError

```python
(python-run "try:\n    list.append()\nexcept TypeError as e:\n    print(e)\ntry:\n    list.append(1, 2)\nexcept TypeError as e:\n    print(e)\ntry:\n    getattr(list, \"append\")(None, 2)\nexcept TypeError as e:\n    print(e)\ntry:\n    str.upper(1)\nexcept TypeError as e:\n    print(e)\ntry:\n    bytes.count(bytearray(b\"aa\"), b\"a\")\nexcept TypeError as e:\n    print(e)\ntry:\n    bytearray.append(b\"x\", 1)\nexcept TypeError as e:\n    print(e)\ntry:\n    dict.keys([])\nexcept TypeError as e:\n    print(e)\ntry:\n    set.add(frozenset(), 1)\nexcept TypeError as e:\n    print(e)\nl = []\nlist.append(l, 2)\nprint(l)")
```
---
```output
unbound method list.append() needs an argument
descriptor 'append' for 'list' objects doesn't apply to a 'int' object
descriptor 'append' for 'list' objects doesn't apply to a 'NoneType' object
descriptor 'upper' for 'str' objects doesn't apply to a 'int' object
descriptor 'count' for 'bytes' objects doesn't apply to a 'bytearray' object
descriptor 'append' for 'bytearray' objects doesn't apply to a 'bytes' object
descriptor 'keys' for 'dict' objects doesn't apply to a 'list' object
descriptor 'add' for 'set' objects doesn't apply to a 'frozenset' object
[2]
```

### a subclass instance is a receiver for its base class's methods

```python
(python-run "class L(list):\n    pass\nclass S(str):\n    pass\nclass D(dict):\n    pass\nclass T(set):\n    pass\nclass B(bytes):\n    pass\nclass BA(bytearray):\n    pass\nl = L()\nlist.append(l, 3)\nprint(l)\nprint(str.upper(S(\"ab\")))\nprint(list(dict.keys(D({\"a\": 1}))))\nt = T([1])\nset.add(t, 2)\nprint(set.copy(t))\nprint(bytes.count(B(b\"aa\"), b\"a\"))\nba = BA(b\"x\")\nbytearray.append(ba, 121)\nprint(bytearray.count(ba, b\"y\"))")
```
---
```output
[3]
AB
['a']
{1, 2}
2
1
```

### an item stores in place, and a refused value leaves the bytearray as it was

```python
(python-run "b = bytearray(b\"abc\")\nb[0] = 65\nb[-1] = True\nprint(b)\ntry:\n    b[5] = 1\nexcept IndexError as e:\n    print(e)\ntry:\n    b[-4] = 1\nexcept IndexError as e:\n    print(e)\ntry:\n    b[0] = 256\nexcept ValueError:\n    print(\"ValueError\")\ntry:\n    b[0] = -1\nexcept ValueError:\n    print(\"ValueError\")\ntry:\n    b[0] = \"a\"\nexcept TypeError as e:\n    print(e)\ntry:\n    b[0] = None\nexcept TypeError as e:\n    print(e)\ntry:\n    b[0] = 1.5\nexcept TypeError as e:\n    print(e)\ntry:\n    b[5] = \"a\"\nexcept TypeError as e:\n    print(e)\nprint(b)")
```
---
```output
bytearray(b'Ab\x01')
bytearray index out of range
bytearray index out of range
ValueError
ValueError
'str' object cannot be interpreted as an integer
'NoneType' object cannot be interpreted as an integer
'float' object cannot be interpreted as an integer
'str' object cannot be interpreted as an integer
bytearray(b'Ab\x01')
```

### a slice stores in place, and del removes an item or a slice

```python
(python-run "b = bytearray(range(10))\nb[1:3] = b\"xy\"\nprint(b)\nb[2:2] = [7, 8]\nprint(b)\nb[:3] = bytearray()\nprint(b)\nb[-2:] = (1, 2, 3)\nprint(b)\nb[4:] = b\nprint(b)\ndel b[0]\ndel b[-1]\nprint(b)\ndel b[1:3]\nprint(b)\nb[5:1] = b\"z\"\nprint(b)\ntry:\n    b[0:1] = \"ab\"\nexcept TypeError as e:\n    print(e)\ntry:\n    b[0:1] = 5\nexcept TypeError as e:\n    print(e)\ntry:\n    b[0:1] = None\nexcept TypeError as e:\n    print(e)\ntry:\n    b[0:1] = [1, 300]\nexcept ValueError:\n    print(\"ValueError\")\ntry:\n    del b[100]\nexcept IndexError as e:\n    print(e)\nprint(b)")
```
---
```output
bytearray(b'\x00xy\x03\x04\x05\x06\x07\x08\t')
bytearray(b'\x00x\x07\x08y\x03\x04\x05\x06\x07\x08\t')
bytearray(b'\x08y\x03\x04\x05\x06\x07\x08\t')
bytearray(b'\x08y\x03\x04\x05\x06\x07\x01\x02\x03')
bytearray(b'\x08y\x03\x04\x08y\x03\x04\x05\x06\x07\x01\x02\x03')
bytearray(b'y\x03\x04\x08y\x03\x04\x05\x06\x07\x01\x02')
bytearray(b'y\x08y\x03\x04\x05\x06\x07\x01\x02')
bytearray(b'y\x08y\x03\x04z\x05\x06\x07\x01\x02')
can assign only bytes, buffers, or iterables of ints in range(0, 256)
can assign only bytes, buffers, or iterables of ints in range(0, 256)
cannot convert 'NoneType' object to bytearray
ValueError
bytearray index out of range
bytearray(b'y\x08y\x03\x04z\x05\x06\x07\x01\x02')
```

### a byte that is not an int is a TypeError

```python
(python-run "a = bytearray(2)\ntry:\n    a.append(None)\nexcept TypeError as e:\n    print(e)\ntry:\n    bytes([1, None])\nexcept TypeError as e:\n    print(e)\ntry:\n    bytearray([256])\nexcept ValueError:\n    print(\"ValueError\")\nprint(a)")
```
---
```output
'NoneType' object cannot be interpreted as an integer
'NoneType' object cannot be interpreted as an integer
ValueError
bytearray(b'\x00\x00')
```
