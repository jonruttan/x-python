# the descriptor protocol

### the whole descriptor protocol

```python
(python-run "class Descriptor:\n    def __get__(self, obj, cls):\n        print(\"get\")\n        print(type(obj) is Main)\n        print(cls is Main)\n        return \"result\"\n    def __set__(self, obj, val):\n        print(\"set\")\n        print(type(obj) is Main)\n        print(val)\n    def __delete__(self, obj):\n        print(\"delete\")\n        print(type(obj) is Main)\n    def __set_name__(self, owner, name):\n        print(\"set_name\", name)\n        print(owner.__name__ == \"Main\")\n\nclass Main:\n    Forward = Descriptor()\n\nm = Main()\nprint(m.Forward)\nm.Forward = \"a\"\ndel m.Forward")
```
---
```output
set_name Forward
True
get
True
True
result
set
True
a
delete
True
```

### __class__ answers the instance's class

```python
(python-run "class C:\n    pass\nc = C()\nprint(c.__class__ is C, c.__class__.__name__)\nclass Sub(C):\n    pass\nprint(Sub().__class__.__name__, Sub().__class__ is Sub)")
```
---
```output
True C
Sub True
```

### a plain class attribute is not a descriptor

```python
(python-run "class C:\n    x = 5\n    def m(self): return 1\nc = C()\nprint(c.x, c.m())\nc.x = 6\nprint(c.x, C.x)")
```
---
```output
5 1
6 5
```

### __set_name__ sees the owner it is written in

```python
(python-run "class Named:\n    def __set_name__(self, owner, name):\n        self.owner_name = owner.__name__\n        self.my_name = name\nclass Holder:\n    first = Named()\n    second = Named()\nprint(Holder.first.my_name, Holder.first.owner_name)\nprint(Holder.second.my_name, Holder.second.owner_name)")
```
---
```output
first Holder
second Holder
```
