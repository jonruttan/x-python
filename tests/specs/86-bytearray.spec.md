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
