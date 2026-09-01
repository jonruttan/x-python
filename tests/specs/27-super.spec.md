The `super` half of what was one classes file. It moved out for a reason worth
recording: with both halves in one file the batch reached **61 seconds against
the runner's 60-second unit timeout** on CI's slower v0.9.0 runner — the first
directly observed instance of the timeout graze that had previously only been a
hypothesis for the suite's rare "interpreter died mid-batch" flakes. A file's
cases share one process, so a file that grows past the margin fails from the
tail backward, and the failure names innocent cases.

## super

`super()` starts from **the class the method was written in**, not from the
instance's class. That is Python's rule and it is not a detail: in
`class Dog(Animal)` with an overriding `speak`, the instance is a Dog, so
looking `speak` up from the instance's class finds Dog's own override and calls
it again — forever. Starting from Dog and searching its base finds Animal's.

The parser supplies the class, because zero-argument `super()` is **lexical**:
it means the class whose body the call is written in, and the object bound to
the enclosing method's first parameter. Nothing about the value at run time can
tell you either, which is why CPython gives methods a `__class__` cell rather
than deriving it from `self`.

### calling the base implementation of an override

```python
(python-run "class A:\n    def speak(self):\n        return 'A'\nclass B(A):\n    def speak(self):\n        return super().speak() + '+B'\nprint(B().speak())")
```
---
    A+B

### super().__init__

```python
(python-run "class A:\n    def __init__(self, n):\n        self.n = n\nclass B(A):\n    def __init__(self, n):\n        super().__init__(n * 2)\nprint(B(3).n)")
```
---
    6

### each level's super finds the next one down

```python
(python-run "class A:\n    def who(self):\n        return 'A'\nclass B(A):\n    def who(self):\n        return 'B' + super().who()\nclass C(B):\n    def who(self):\n        return 'C' + super().who()\nprint(C().who())")
```
---
    CBA

### the first parameter need not be called self

Python binds `super()` to the first positional parameter whatever it is named,
so this tracks the parameter rather than assuming the convention.

```python
(python-run "class A:\n    def hi(self):\n        return 'A'\nclass B(A):\n    def hi(this):\n        return super().hi()\nprint(B().hi())")
```
---
    A

### a class with no base has nothing to defer to

```python
(python-run "class A:\n    def hi(self):\n        return super().hi()\nprint(A().hi())")
```
---
    Error: #<err:attribute 'super' object has no attribute 'hi'>

### super() outside a class is refused at parse time

The lexical rule makes this decidable where it is written, rather than a
run-time failure somewhere else.

```python
(python-run "print(super())")
```
---
    Error: #<err:syntax super() outside a class>
