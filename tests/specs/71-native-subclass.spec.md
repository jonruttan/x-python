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
