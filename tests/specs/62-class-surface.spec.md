# the class surface: what a class says about itself

### a class knows its own name

```python
(python-run "class C: pass\nclass Sub(C): pass\nprint(C.__name__, Sub.__name__)")
```
---
```output
C Sub
```

### __bases__ is a tuple

```python
(python-run "class A: pass\nclass B(A): pass\nprint(B.__bases__[0].__name__, len(B.__bases__), A.__bases__ == () or A.__bases__[0].__name__)")
```
---
```output
A 1 object
```

### object is a class and a base

```python
(python-run "class C(object):\n    def f(self): return 1\nc = C()\nprint(c.f(), C.__name__, C.__bases__[0].__name__)")
```
---
```output
1 C object
```

### everything is an instance of object

```python
(python-run "class C: pass\nprint(isinstance(C(), object), isinstance(1, object), isinstance(\"a\", object), isinstance([], object))")
```
---
```output
True True True True
```

### a subclass of a subclass still reaches object

```python
(python-run "class A(object): pass\nclass B(A): pass\nprint(issubclass(B, A), issubclass(B, object), issubclass(A, object))")
```
---
```output
True True True
```

### __dict__ holds the class body

```python
(python-run "class C:\n    x = 1\n    def f(self): return 2\nprint('x' in C.__dict__, 'f' in C.__dict__, 'nope' in C.__dict__, C.__dict__['x'])")
```
---
```output
True True False 1
```

### a base that is not a class raises, and does not crash

Before this, an undefined base took the interpreter down: an undefined name is
bound to a SHIM that raises when it is CALLED -- a deferred NameError, which is
this runtime's design -- and a shim arriving as a base sent method lookup
walking into a closure as though it were a class record.  The guard in
%py-mkclass makes it a TypeError instead.

DIVERGENCE, and it follows from that design: CPython evaluates the base
expression first and so raises NameError here, while this runtime only learns
the name was undefined when something calls the shim, which a base never does.
Both raise, and the case catches either, which is what a program that cares
would write.

```python
(python-run "try:\n    class C(nosuch):\n        pass\nexcept NameError:\n    print(\"NameError\")\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
TypeError
```

### del removes an instance attribute

```python
(python-run "class C: pass\nc = C()\nc.x = 1\nprint(hasattr(c, 'x'), c.x)\ndel c.x\nprint(hasattr(c, 'x'))")
```
---
```output
True 1
False
```

### del on a missing attribute raises

```python
(python-run "class C: pass\nc = C()\ntry:\n    del c.nope\nexcept AttributeError:\n    print(\"AttributeError\")")
```
---
```output
AttributeError
```

### the class name travels with the instance

```python
(python-run "class Animal: pass\nclass Dog(Animal): pass\nd = Dog()\nprint(type(d).__name__, type(d).__bases__[0].__name__)")
```
---
```output
Dog Animal
```
