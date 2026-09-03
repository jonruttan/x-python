Python's classes are values built at run time, and `Foo()` is an ordinary call.

That second fact is the whole design. x dispatches a call on a value through its
type's `call` handler, so construction needs no special form in the parser and no
check at any call site — `Foo()` takes the same path as every other call and
arrives at PY-CLASS's handler.

These are **not** x classes (`x/type/class.x`). That layer is for types written
in x and resolved when the file loads; Python's are built from a parsed body at
run time, and their method lookup follows Python's rules. Same reasoning that put
Python's lists on the type system rather than the class system: one level lower
is the level that fits.

## classes and instances

### a class is a value

```python
(python-run "class Foo:\n    pass\nprint(Foo)")
```
---
    <class '__main__.Foo'>

### calling it constructs an instance

Python prints `<__main__.Foo object at 0x7f...>`. The address is the object's
identity, different on every run, so reproducing it would make every spec that
prints an object unassertable. The name is kept and the address dropped.

```python
(python-run "class Foo:\n    pass\nprint(Foo())")
```
---
    <__main__.Foo object>

### __init__ runs on construction

```python
(python-run "class P:\n    def __init__(self, n):\n        self.n = n\nprint(P(3).n)")
```
---
    3

### instances do not share their attributes

```python
(python-run "class P:\n    def __init__(self, n):\n        self.n = n\na = P(1)\nb = P(2)\nprint(a.n)\nprint(b.n)")
```
---
```output
1
2
```

### an attribute can be set from outside

`self.x = 1` is how a Python object gets its fields at all, so an attribute is
an assignable target exactly as a subscript is — and nothing makes the inside of
a method special.

```python
(python-run "class B:\n    pass\nb = B()\nb.x = 7\nprint(b.x)")
```
---
    7

### a missing attribute raises

```python
(python-run "class C:\n    pass\nprint(C().nope)")
```
---
    Error: #<err:attribute 'C' object has no attribute 'nope'>

## methods

### a method reaches its own instance

```python
(python-run "class P:\n    def __init__(self, n):\n        self.n = n\n    def double(self):\n        return self.n * 2\nprint(P(4).double())")
```
---
    8

### methods take arguments

A method compiles to `(fn (_ py-self ...))` — the leading `_` absorbs x's
self-binding — so calling it with the object as the first argument is all
"bound" means.

```python
(python-run "class A:\n    def add(self, a, b):\n        return a + b\nprint(A().add(2, 3))")
```
---
    5

### a method can call another through self

```python
(python-run "class A:\n    def one(self):\n        return 1\n    def two(self):\n        return self.one() + 1\nprint(A().two())")
```
---
    2

### a bound method is a value

```python
(python-run "class A:\n    def hi(self):\n        return 'hi'\nf = A().hi\nprint(f())")
```
---
    hi

## inheritance

### a derived class finds the base's methods

```python
(python-run "class Animal:\n    def speak(self):\n        return 'generic'\nclass Dog(Animal):\n    pass\nprint(Dog().speak())")
```
---
    generic

### and overrides them

Lookup walks the chain derived-first, which is the one piece of the object model
a flat table cannot fake.

```python
(python-run "class Animal:\n    def speak(self):\n        return 'generic'\nclass Dog(Animal):\n    def speak(self):\n        return 'woof'\nprint(Dog().speak())")
```
---
    woof

### the base's __init__ is inherited

```python
(python-run "class Base:\n    def __init__(self, n):\n        self.n = n\nclass Sub(Base):\n    def show(self):\n        return self.n\nprint(Sub(9).show())")
```
---
    9

### two levels deep

```python
(python-run "class A:\n    def who(self):\n        return 'A'\nclass B(A):\n    pass\nclass C(B):\n    pass\nprint(C().who())")
```
---
    A

## what a class body accepts

### defs, assignments and pass

A class attribute — `count = 0` in the body — belongs to the CLASS, and an
instance reads it through the class until it shadows it.

```python
(python-run "class C:\n    count = 0\nc = C()\nprint(C.count, c.count)\nc.count = 5\nprint(C.count, c.count)")
```
---
```output
0 0
0 5
```

### and nothing else

Anything that is not a def, an assignment or `pass` is refused rather than
silently ignored.

```python
(python-run "class C:\n    if 1:\n        pass\nprint(C())")
```
---
    Error: #<err:syntax a class body takes defs, assignments and pass only>
