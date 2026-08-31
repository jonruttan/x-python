`type()`, the builtin type objects, their constructors, and `isinstance`.

The builtin types are real class objects — ordinary PY-CLASS values, so
`type(1) == int` is the same identity compare user classes already get, and
`print(int)` goes through the same write handler. Two additions carried it: a
QUALNAME slot (a user class prints `<class '__main__.Foo'>`, a builtin prints
`<class 'int'>` — the prefix is a fact about where the class came from, which
the constructor's caller knows and the class cannot compute), and a `%ctor`
entry in the methods alist, a key no Python identifier can spell, so `int('5')`
converts instead of allocating an instance.

Two x types are one Python type: a small integer and a bigint are different
types to x's tower and both are `int` here. And `bool` derives from `int`,
which is Python's own arrangement.

## type

### of each builtin

```python
(python-run "print(type(1))\nprint(type('a'))\nprint(type([1]))\nprint(type({}))\nprint(type((1,)))\nprint(type(1.5))\nprint(type(True))\nprint(type(None))")
```
---
```output
<class 'int'>
<class 'str'>
<class 'list'>
<class 'dict'>
<class 'tuple'>
<class 'float'>
<class 'bool'>
<class 'NoneType'>
```

### type equality is identity

```python
(python-run "print(type(1) == type(2))\nprint(type(1) == type('a'))\nprint(type(1) == int)\nprint(type('a') == str)")
```
---
```output
True
False
True
True
```

### a bigint is an int

The tower holds them as different types; Python has one integer that goes all
the way up, so both handles map to the one class.

```python
(python-run "print(type(99999999999999999999) == int)")
```
---
    True

### of an instance, and of a class

```python
(python-run "class Foo:\n    pass\nprint(type(Foo()) == Foo)\nprint(type(Foo))")
```
---
```output
True
<class 'type'>
```

## constructors

### int, from the shapes Python accepts

`int('abc')` is walked BY HAND: the reader-base shortcut accepts prefixes
("12ab" would answer 12) — a silent wrong number, so it is not trusted with
input the program supplied. Truncation is toward zero, which is Python's.

```python
(python-run "print(int('5'))\nprint(int('-42'))\nprint(int(3.7))\nprint(int(-3.7))\nprint(int(True))\nprint(int())")
```
---
```output
5
-42
3
-3
1
0
```

### int of garbage raises, with Python's message

```python
(python-run "print(int('abc'))")
```
---
    Error: #<err:value invalid literal for int() with base 10: 'abc'>

### float

```python
(python-run "print(float('1.5'))\nprint(float(2))\nprint(float('-2e3'))")
```
---
```output
1.5
2.0
-2000.0
```

### float of garbage raises rather than answering 0.0

`Float from "abc"` answers 0.0 — measured — so the string is shape-checked
first. Stricter than CPython (no inf/nan, no surrounding spaces), and the
strictness fails loudly where the alternative was silent.

```python
(python-run "print(float('abc'))")
```
---
    Error: #<err:value could not convert string to float: 'abc'>

### bool is Python's truthiness

The empties and the zeros are false; everything else is true.

```python
(python-run "print(bool(0), bool(1), bool(''), bool('a'), bool([]), bool([1]), bool(None))")
```
---
    False True False True False True False

### str and list still convert

They were plain functions before they were classes; the %ctor entry is those
same functions, so nothing a program could observe changed.

```python
(python-run "print(str(42))\nprint(list('ab'))")
```
---
```output
42
['a', 'b']
```

### dict copies, and the copy is independent

Fresh entry pairs — sharing them would make a store into one dict visible in
the other, since a store mutates the entry pair in place.

```python
(python-run "d = {'a': 1}\ne = dict(d)\ne['b'] = 2\nprint(d)\nprint(e)")
```
---
```output
{'a': 1}
{'a': 1, 'b': 2}
```

### tuple from a list

```python
(python-run "print(tuple([1, 2]))")
```
---
    (1, 2)

## isinstance

One definition: the same base-chain walk the exception matcher uses, so user
classes, user exceptions and builtins all answer alike.

### the builtins

```python
(python-run "print(isinstance(1, int))\nprint(isinstance('a', str))\nprint(isinstance(1, str))")
```
---
```output
True
True
False
```

### bool derives from int, and not the other way

```python
(python-run "print(isinstance(True, int))\nprint(isinstance(1, bool))")
```
---
```output
True
False
```

### user classes walk their chain

```python
(python-run "class A:\n    pass\nclass B(A):\n    pass\nprint(isinstance(B(), A))\nprint(isinstance(A(), B))")
```
---
```output
True
False
```

### the tuple form is any-of

```python
(python-run "print(isinstance(1, (str, int)))\nprint(isinstance(1.5, (str, int)))")
```
---
```output
True
False
```
