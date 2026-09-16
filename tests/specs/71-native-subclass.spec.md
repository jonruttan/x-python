# subclassing a builtin

### a list subclass is a list

```python
(python-run "class mylist(list):\n    pass\na = mylist([1, 2, 5])\na.attr = \"something\"\nprint(a)\nprint(a.attr)\nprint(a[-1])\na[0] = -1\nprint(a)\nprint(len(a))\nprint(a + [20, 30, 40])")
```
---
```output
[1, 2, 5]
something
5
[-1, 2, 5]
3
[-1, 2, 5, 20, 30, 40]
```

### it iterates, contains and compares as a list

```python
(python-run "class mylist(list):\n    pass\na = mylist([1, 2, 3])\nprint([x * 2 for x in a])\nprint(2 in a, 9 in a)\nprint(a == [1, 2, 3])\ntotal = 0\nfor x in a:\n    total += x\nprint(total)")
```
---
```output
[2, 4, 6]
True False
True
6
```

### its own methods sit beside the list's

```python
(python-run "class mylist(list):\n    def total(self):\n        return sum(self)\n    def __init__(self, xs):\n        list.__init__(self, xs)\n        self.tag = \"t\"\nm = mylist([1, 2, 3])\nprint(m.total(), m.tag)\nm.append(4)\nprint(m, m.total(), len(m))")
```
---
```output
6 t
[1, 2, 3, 4] 10 4
```

### a subclass that adds nothing still constructs empty

```python
(python-run "class mylist(list):\n    pass\ne = mylist()\nprint(e, len(e))\ne.append(1)\nprint(e)")
```
---
```output
[] 0
[1]
```

### a method read off a subclass is its builtin base's

```python
(python-run "class L(list):\n    pass\nclass LL(L):\n    pass\nclass Base:\n    pass\nclass M(Base, list):\n    pass\nl = L()\nL.append(l, 1)\nprint(l)\nplain = []\nLL.append(plain, 2)\nprint(plain)\nm = M()\nM.append(m, 3)\nprint(m)\nclass S(str):\n    pass\nprint(S.upper(S(\"ab\")), S.upper(\"cd\"))\ntry:\n    L.append(1, 2)\nexcept TypeError as e:\n    print(e)\ntry:\n    L.nosuch\nexcept AttributeError as e:\n    print(e)\ntry:\n    list.nosuch\nexcept AttributeError as e:\n    print(e)")
```
---
```output
[1]
[2]
[3]
AB CD
descriptor 'append' for 'list' objects doesn't apply to a 'int' object
type object 'L' has no attribute 'nosuch'
type object 'list' has no attribute 'nosuch'
```

### a set subclass iterates, contains and compares as a set

```python
(python-run "class T(set):\n    pass\nt = T([1, 2])\nprint(sorted(t), len(t), 1 in t, 5 in t, bool(T()))\nprint([x * 10 for x in t])\nprint(t == {1, 2}, {1, 2} == t, t != {1}, isinstance(t, set))\nprint(t < {1, 2, 3}, {1} < t, t <= T([1, 2]), t >= {1}, t > {1})\nt.add(3)\nprint(t, T(), repr(T([5])))")
```
---
```output
[1, 2] 2 True False False
[10, 20]
True True True True
True True True True True
T({1, 2, 3}) T() T({5})
```

### a set subclass's operators answer a set, and in place keep the subclass

```python
(python-run "class T(set):\n    pass\nt = T([1, 2])\nu = t | {3}\nprint(type(u).__name__, sorted(u))\nprint(sorted({3} | t), sorted(t & {2, 5}), sorted(t - {1}), sorted({1, 2, 3} - t), sorted(t ^ {2, 3}))\nprint(sorted(t | T([4])), type(t | T([4])).__name__)\nt |= {9}\nt -= {1}\nprint(type(t).__name__, sorted(t))")
```
---
```output
set [1, 2, 3]
[1, 2, 3] [2] [2] [3] [1, 3]
[1, 2, 4] set
T [2, 9]
```

### a frozenset subclass hashes as one and prints under its own name

```python
(python-run "class F(frozenset):\n    pass\nf = F([1])\nprint(f, F(), hash(f) == hash(frozenset([1])), f == frozenset([1]))\nprint({f: \"x\"}[frozenset([1])])\ng = f | {2}\nprint(type(g).__name__, sorted(g))\nf |= {3}\nprint(type(f).__name__, sorted(f))\nprint(sorted(frozenset(F([4, 5]))))")
```
---
```output
F({1}) F() True True
x
frozenset [1, 2]
frozenset [1, 3]
[4, 5]
```

### dict.__init__ and set.__init__ fill an instance, through super() or read off the class

```python
(python-run "class D(dict):\n    def __init__(self, *args, **kwargs):\n        super().__init__(*args, **kwargs)\nprint(D(), D([('a', 1)]), D([('a', 1)], a=2, b=3), D(a=2, b=3))\nclass E(dict):\n    def __init__(self):\n        super().__init__([], a=1)\nprint(E())\nd = {}\ndict.__init__(d, [('x', 1)], y=2)\nprint(d)\nclass T(set):\n    def __init__(self, a, b):\n        super().__init__([a, b])\nprint(T(1, 2))\ns = {9}\nset.__init__(s, [1])\nprint(s)\ntry:\n    dict.__init__([], a=1)\nexcept TypeError as e:\n    print(e)\ntry:\n    set.__init__(frozenset(), [1])\nexcept TypeError as e:\n    print(e)")
```
---
```output
{} {'a': 1} {'a': 2, 'b': 3} {'a': 2, 'b': 3}
{'a': 1}
{'x': 1, 'y': 2}
T({1, 2})
{1}
descriptor '__init__' requires a 'dict' object but received a 'list'
descriptor '__init__' requires a 'set' object but received a 'frozenset'
```

### frozenset methods read off a class, and a frozenset has no mutating methods

```python
(python-run "class F(frozenset):\n    pass\nprint(frozenset.union(frozenset([1]), [2]), F.union(F([1]), [3]))\nprint(hasattr(frozenset, \"add\"), hasattr(frozenset(), \"add\"), hasattr(F([1]), \"discard\"), hasattr(frozenset, \"union\"))\ntry:\n    frozenset().add(1)\nexcept AttributeError as e:\n    print(e)\ntry:\n    frozenset.add\nexcept AttributeError as e:\n    print(e)\ntry:\n    frozenset.union({1}, [2])\nexcept TypeError as e:\n    print(e)")
```
---
```output
frozenset({1, 2}) frozenset({1, 3})
False False False True
'frozenset' object has no attribute 'add'
type object 'frozenset' has no attribute 'add'
descriptor 'union' for 'frozenset' objects doesn't apply to a 'set' object
```

### a list subclass built from a generator reads it once

```python
(python-run "class L(list):\n    pass\nprint(L(x for x in range(3)), L(iter([4, 5])))\ntry:\n    L(5)\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
[0, 1, 2] [4, 5]
TypeError
```

### the list, set and dict __init__ rows check their arguments, and list.__init__() empties the list

```python
(python-run "def err(f):\n    try:\n        f()\n        print(\"no error\")\n    except TypeError as e:\n        print(e)\nl = [1, 2]\nlist.__init__(l)\nprint(l)\nlist.__init__(l, (3, 4))\nprint(l)\nerr(lambda: list.__init__(l, x=1))\nerr(lambda: list.__init__(l, [1], [2]))\nerr(lambda: list.__init__(5))\ns = {1, 2}\nset.__init__(s)\nprint(s)\nerr(lambda: set.__init__(s, x=1))\nerr(lambda: set.__init__(s, [1], [2]))\nerr(lambda: dict.__init__({}, [], []))\nclass L(list):\n    pass\nclass T(set):\n    pass\nerr(lambda: L(x=1))\nerr(lambda: T(x=1))\nerr(lambda: L([1], [2]))\nerr(lambda: list(x=1))")
```
---
```output
[]
[3, 4]
list() takes no keyword arguments
list expected at most 1 argument, got 2
descriptor '__init__' requires a 'list' object but received a 'int'
set()
set() takes no keyword arguments
set expected at most 1 argument, got 2
dict expected at most 1 argument, got 2
list() takes no keyword arguments
set() takes no keyword arguments
list expected at most 1 argument, got 2
list() takes no keyword arguments
```

### super().__init__(*args, **kwargs) reaches list and set with an empty keyword dict

```python
(python-run "class L(list):\n    def __init__(self, *a, **k):\n        super().__init__(*a, **k)\nclass T(set):\n    def __init__(self, *a, **k):\n        super().__init__(*a, **k)\nprint(L([1]), L(), T([2]), T())\nl = L([5])\nl.__init__()\nprint(l)\nl.__init__([6, 7])\nprint(l)\ntry:\n    L(x=1)\nexcept TypeError as e:\n    print(e)")
```
---
```output
[1] [] T({2}) T()
[]
[6, 7]
list() takes no keyword arguments
```

### a subclass whose own __init__ never calls the base's starts empty

```python
(python-run "class S(list):\n    def __init__(self, xs):\n        pass\nclass E(list):\n    def __init__(self, xs):\n        self.extend(xs)\nclass D(dict):\n    def __init__(self, m):\n        self.seen = len(m)\nclass T(set):\n    def __init__(self, xs):\n        pass\nclass U(dict):\n    def __init__(self, m):\n        for k in m:\n            self[k] = m[k] * 2\nprint(S([1, 2]), E([1, 2]), D({\"a\": 1}), D({\"a\": 1}).seen, T([1]), U({\"a\": 1}))\nclass P(list):\n    def __init__(self, xs):\n        self.n = len(xs)\n        super().__init__(xs)\np = P([3, 4])\nprint(p, p.n)")
```
---
```output
[] [1, 2] {} 1 T() {'a': 2}
[3, 4] 2
```
