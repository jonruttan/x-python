Builtins (`python/runtime.x`, `python/parse.x`): bin/hex/oct over the
format engine's base conversion, divmod, three-argument pow, round of an
int to a negative digit (half to even); lazy enumerate/filter/map over
several iterables, reversed through __reversed__ or length+getitem,
sorted and min/max with key; callable, id, getattr with a default,
setattr, delattr, issubclass; class attributes and one-line class bodies.
Every expectation is a real CPython output.

Split across files because the batch runner never collects.


## more builtins

### enumerate filter reversed

```python
(python-run "print(list(enumerate([])), list(enumerate([1, 2, 3])), list(enumerate([1, 2, 3], 5)), list(enumerate([1, 2, 3], -5)))\nprint(list(enumerate([1, 2, 3], start=1)), list(enumerate(iterable=[1, 2, 3])), list(enumerate(iterable=[1, 2, 3], start=1)))\nfor i, v in enumerate('ab', 1):\n    print(i, v)\nprint(list(filter(lambda x: x & 1, range(-3, 4))), list(filter(None, range(-3, 4))))\nprint(list(reversed([])), list(reversed([1])), list(reversed([1, 2, 3])), list(reversed((1, 2, 3))))\nfor c in reversed('ab'):\n    print(c)\nfor i in reversed(range(3)):\n    print(i)\nclass R:\n    def __len__(self):\n        return 3\n    def __getitem__(self, i):\n        return i + 1\nprint(list(reversed(R())))\n")
```
---
```output
[] [(0, 1), (1, 2), (2, 3)] [(5, 1), (6, 2), (7, 3)] [(-5, 1), (-4, 2), (-3, 3)]
[(1, 1), (2, 2), (3, 3)] [(0, 1), (1, 2), (2, 3)] [(1, 1), (2, 2), (3, 3)]
1 a
2 b
[-3, -1, 1, 3] [-3, -2, -1, 1, 2, 3]
[] [1] [3, 2, 1] [3, 2, 1]
b
a
2
1
0
[3, 2, 1]
```

### chr ord map

```python
(python-run "print(chr(65))\ntry:\n    chr(0x110000)\nexcept ValueError:\n    print('ValueError')\nprint(ord('a'))\ntry:\n    ord('')\nexcept TypeError:\n    print('TypeError')\nprint(ord(b'a'), ord(b'\\x7f'), ord(b'\\x80'), ord(b'\\xff'))\nprint(list(map(lambda x: x & 1, range(-3, 4))), list(map(abs, range(-3, 4))))\nprint(list(map(tuple, [[i] for i in range(-3, 4)])), list(map(pow, range(4), range(4))))\n")
```
---
```output
A
ValueError
97
TypeError
97 127 128 255
[1, 0, 1, 0, 1, 0, 1] [3, 2, 1, 0, 1, 2, 3]
[(-3,), (-2,), (-1,), (0,), (1,), (2,), (3,)] [1, 1, 4, 27]
```

### hashing and pow

```python
(python-run "def gen():\n    yield\nprint(type(hash(gen)), type(hash(gen())), type(hash(())))\nprint(hash(False), hash(True))\nprint({(): 1}, {(1,): 1})\nprint(hash in {hash: 1})\nprint(pow(3, 4, 7), pow(1, 1, 1), pow(0, 1, 1), pow(1, 0, 2), pow(0, 0, 5), pow(3, 4))\n")
```
---
```output
<class 'int'> <class 'int'> <class 'int'>
0 1
{(): 1} {(1,): 1}
True
4 0 0 1 1 81
```

### hash: super and the descriptors by identity, None, bytes and slices, and a __hash__ that must answer an int

```python
(python-run "def f57(x):\n    def g():\n        return x\n    return g\n\n\nclass A57:\n    def __hash__(self):\n        return 123\n\n    def __repr__(self):\n        return \"a instance\"\n\n\nclass B57:\n    pass\n\n\nclass C57:\n    def __eq__(self, another):\n        return True\n\n\nclass D57:\n    def __hash__(self):\n        return None\n\n\nclass E57:\n    def __hash__(self):\n        return True\n\n\nfor label, th in ((\"super\", lambda: super(object, object)), (\"classmethod\", lambda: classmethod(hash)),\n                  (\"staticmethod\", lambda: staticmethod(hash)), (\"property\", lambda: property(len)),\n                  (\"iter\", lambda: iter(\"\")), (\"closure\", lambda: f57(1)), (\"object\", lambda: object()),\n                  (\"None\", lambda: None), (\"bytes\", lambda: b\"ab\"), (\"slice\", lambda: slice(1, 2)),\n                  (\"list\", lambda: []), (\"bytearray\", lambda: bytearray()), (\"A\", lambda: A57()),\n                  (\"B\", lambda: B57()), (\"C\", lambda: C57()), (\"D\", lambda: D57()), (\"E\", lambda: E57())):\n    try:\n        h = hash(th())\n        print(label, type(h).__name__, h if label in (\"A\", \"E\") else \"\")\n    except TypeError as e:\n        print(label, \"TypeError\", e)\nprint({A57(): 1}, hash(b\"ab\") == hash(\"ab\"), hash(slice(1, 2)) == hash(slice(1, 2)))")
```
---
```output
super int 
classmethod int 
staticmethod int 
property int 
iter int 
closure int 
object int 
None int 
bytes int 
slice int 
list TypeError unhashable type: 'list'
bytearray TypeError unhashable type: 'bytearray'
A int 123
B int 
C TypeError unhashable type: 'C57'
D TypeError __hash__ method should return an integer
E int 1
{a instance: 1} True True
```

### a subclass hashes as its builtin, __eq__ alone makes a class unhashable, and set and dict refuse by name

```python
(python-run "from collections import namedtuple\n\n\nclass MyStr58(str):\n    pass\n\n\nclass MyList58(list):\n    pass\n\n\nclass MyInt58(int):\n    pass\n\n\nclass MySet58(set):\n    pass\n\n\nclass MyFrozen58(frozenset):\n    pass\n\n\nclass NoHash58:\n    __hash__ = None\n\n\nclass Base58:\n    def __hash__(self):\n        return 7\n\n\nclass EqChild58(Base58):\n    def __eq__(self, o):\n        return True\n\n\nclass HashChild58(EqChild58):\n    def __hash__(self):\n        return 9\n\n\nclass IntEq58(int):\n    def __eq__(self, o):\n        return True\n\n\nP58 = namedtuple(\"P58\", \"x y\")\nfor label, th in ((\"MyStr\", lambda: MyStr58(\"ab\")), (\"MyList\", lambda: MyList58()), (\"MyInt\", lambda: MyInt58(5)),\n                  (\"MySet\", lambda: MySet58()), (\"MyFrozen\", lambda: MyFrozen58([1])),\n                  (\"NoHash\", lambda: NoHash58()), (\"EqChild\", lambda: EqChild58()),\n                  (\"HashChild\", lambda: HashChild58()), (\"IntEq\", lambda: IntEq58(3)), (\"P\", lambda: P58(1, 2))):\n    try:\n        print(label, type(hash(th())).__name__)\n    except TypeError as e:\n        print(label, \"TypeError\", e)\nprint(hash(MyStr58(\"ab\")) == hash(\"ab\"), hash(MyInt58(5)) == 5, hash(P58(1, 2)) == hash((1, 2)),\n      hash(MyFrozen58([1])) == hash(frozenset([1])), hash(HashChild58()))\nfor label, th in ((\"set\", lambda: {NoHash58()}), (\"set()\", lambda: set([MyList58()])),\n                  (\"dict\", lambda: {EqChild58(): 1}), (\"dict list\", lambda: {[1]: 2}),\n                  (\"set of str\", lambda: {MyStr58(\"q\"), Base58(), Base58()})):\n    try:\n        print(label, len(th()))\n    except TypeError as e:\n        print(label, \"TypeError\", e)")
```
---
```output
MyStr int
MyList TypeError unhashable type: 'MyList58'
MyInt int
MySet TypeError unhashable type: 'MySet58'
MyFrozen int
NoHash TypeError unhashable type: 'NoHash58'
EqChild TypeError unhashable type: 'EqChild58'
HashChild int
IntEq TypeError unhashable type: 'IntEq58'
P int
True True True True 9
set TypeError cannot use 'NoHash58' as a set element (unhashable type: 'NoHash58')
set() TypeError cannot use 'MyList58' as a set element (unhashable type: 'MyList58')
dict TypeError cannot use 'EqChild58' as a dict key (unhashable type: 'EqChild58')
dict list TypeError cannot use 'list' as a dict key (unhashable type: 'list')
set of str 3
```

### any and all read only as far as the answer

```python
(python-run "def seen_d(v):\n    print(\"read\", v)\n    return v\n\n\nprint(any(seen_d(v) for v in [0, 2, 3]))\nprint(all(seen_d(v) for v in [1, 0, 5]))\nprint(any([]), all([]), any(x > 1 for x in [0, 1]), all(\"ab\"))\ntry:\n    any(5)\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
read 0
read 2
True
read 1
read 0
False
False True False True
TypeError 'int' object is not iterable
```
