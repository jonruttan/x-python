Both containers register an `iter` handler, so anything in the process that
iterates — not just Python's own `for` — can walk a Python list or dict.

The first version of those handlers was wrong, and wrong in a way nothing would
have caught: it returned bare values and treated a nil return as exhaustion.
Python's `None` **is** nil here, so `[None]` would have stopped at the first
element. Nothing consumed the slot, so no test failed.

The real contract is `(value . next-state)`, and only a nil **pair** ends the
walk — exhaustion rides the state, not the value. A nil value is an ordinary
element. These cases exist so the slot is exercised rather than merely present.

## the iterator protocol

### a Python list, including a None

```python
(%seq (write (Iter ->list (Iter new (%py-list-new (list 1 () 2))))) (newline))
```
---
    (1 () 2)

### a None at the end, where a value-terminated stepper would have been right by luck

```python
(%seq (write (Iter ->list (Iter new (%py-list-new (list 1 ()))))) (newline))
```
---
    (1 ())

### a list of nothing but None

```python
(%seq (write (Iter ->list (Iter new (%py-list-new (list ()))))) (newline))
```
---
    (())

### an empty list iterates to nothing

The empty case and the all-None case are the two that a value-terminated
stepper cannot tell apart. They differ here.

```python
(%seq (write (Iter ->list (Iter new (%py-list-new ())))) (newline))
```
---
    ()

### a dict yields its keys

```python
(%seq (write (Iter ->list (Iter new (%py-dict-new (list (pair "a" 1) (pair "b" 2)))))) (newline))
```
---
    ("a" "b")

## for

### for walks a list containing None

Python's `for` takes the element list directly rather than going through the
iterator, so this was always right — but it is the behaviour the slot has to
agree with, and nothing was pinning it.

```python
(python-run "for x in [None, 1]:\n    print(x)")
```
---
```output
None
1
```

### and one that is only None

```python
(python-run "for x in [None]:\n    print(x)")
```
---
    None

## the sequence protocol and StopIteration

### a class with only __getitem__ is read a step at a time, to IndexError or StopIteration

```python
(python-run "class Seq14:\n    def __getitem__(self, i):\n        print(\"get\", i)\n        if i > 1:\n            raise IndexError\n        return i * 10\n\n\nfor v in Seq14():\n    print(\"body\", v)\nit14 = iter(Seq14())\nprint(next(it14), next(it14))\ntry:\n    next(it14)\nexcept StopIteration as e:\n    print(\"StopIteration\", e.args)\nprint(list(Seq14()))\n\n\nclass Stop14:\n    def __getitem__(self, i):\n        if i == 2:\n            raise StopIteration(99)\n        return i\n\n\nprint(list(Stop14()), [x for x in Stop14()])\n\n\nclass Bad14:\n    def __getitem__(self, i):\n        raise TypeError(\"no\")\n\n\ntry:\n    for x in Bad14():\n        pass\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
get 0
body 0
get 1
body 10
get 2
get 0
get 1
0 10
get 2
StopIteration ()
get 0
get 1
get 2
[0, 10]
[0, 1] [0, 1]
TypeError no
```

### map, enumerate and filter end with the StopIteration their source raised

```python
(python-run "class Src15:\n    def __iter__(self):\n        return self\n\n    def __next__(self):\n        raise StopIteration(42)\n\n\ndef gen15(x):\n    return x\n    yield\n\n\nfor label, make in ((\"map\", lambda: map(lambda v: v, Src15())),\n                    (\"enumerate\", lambda: enumerate(Src15())),\n                    (\"filter\", lambda: filter(None, Src15())),\n                    (\"map of a generator\", lambda: map(str, gen15(7)))):\n    try:\n        next(make())\n    except StopIteration as e:\n        print(label, e.args)\nprint(list(map(lambda v: v * 2, [1, 2])), list(enumerate(\"ab\", 1)),\n      list(filter(None, [0, 1, 2])), list(map(str, gen15(7))))")
```
---
```output
map (42,)
enumerate (42,)
filter (42,)
map of a generator (7,)
[2, 4] [(1, 'a'), (2, 'b')] [1, 2] []
```

### what is not iterable is refused by name, at the call

```python
(python-run "for src in (\"iter(5)\", \"iter(None)\", \"list(3.5)\"):\n    try:\n        eval(src)\n    except TypeError as e:\n        print(\"TypeError\", e)\ntry:\n    for x in 5:\n        pass\nexcept TypeError as e:\n    print(\"TypeError\", e)")
```
---
```output
TypeError 'int' object is not iterable
TypeError 'NoneType' object is not iterable
TypeError 'float' object is not iterable
TypeError 'int' object is not iterable
```

### zip ends with the StopIteration its source raised

```python
(python-run "class Src20:\n    def __iter__(self):\n        return self\n\n    def __next__(self):\n        raise StopIteration(42)\n\n\ntry:\n    next(zip(Src20()))\nexcept StopIteration as e:\n    print(\"zip\", e.args)\ntry:\n    next(zip([1], Src20()))\nexcept StopIteration as e:\n    print(\"zip second\", e.args)\nprint(list(zip([1, 2], Src20())))")
```
---
```output
zip (42,)
zip second (42,)
[]
```

## membership

### in reads a view, an iterator only up to its first match, and refuses what is neither container nor iterable

```python
(python-run "d22 = {1: 2, 3: 4}\nprint(1 in d22.keys(), 5 in d22.keys(), 2 in d22.values(), 9 in d22.values())\nprint((1, 2) in d22.items(), (1, 3) in d22.items(), 1 not in d22.keys())\n\n\ndef gen22():\n    for i in range(5):\n        print(\"yield\", i)\n        yield i\n\n\ng22 = gen22()\nprint(2 in g22)\nprint(next(g22))\nprint(9 in g22)\nprint(3 in map(abs, [-1, -3]), 4 in map(abs, [-1, -3]), (1, 2) in zip([1], [2]))\n\n\nclass It22:\n    def __init__(self):\n        self.n = 0\n\n    def __iter__(self):\n        return self\n\n    def __next__(self):\n        self.n += 1\n        if self.n > 3:\n            raise StopIteration\n        return self.n\n\n\nclass Seq22:\n    def __getitem__(self, i):\n        if i >= 3:\n            raise IndexError\n        return i * 10\n\n\nclass Iter22:\n    def __iter__(self):\n        return iter([1, 2])\n\n\nprint(2 in It22(), 7 in It22(), 20 in Seq22(), 5 in Seq22(), 2 in Iter22(), 3 in Iter22())\n\n\nclass Nothing22:\n    pass\n\n\nfor label, th in ((\"int\", lambda: 1 in 5), (\"None\", lambda: 1 in None), (\"obj\", lambda: 1 in Nothing22()),\n                  (\"float\", lambda: 1 in 2.5), (\"int in str\", lambda: 1 in \"abc\"),\n                  (\"str in bytes\", lambda: \"a\" in b\"abc\")):\n    try:\n        print(label, th())\n    except TypeError as e:\n        print(label, \"TypeError\", e)")
```
---
```output
True False True False
True False False
yield 0
yield 1
yield 2
True
yield 3
3
yield 4
False
True False True
True False True False True False
int TypeError argument of type 'int' is not a container or iterable
None TypeError argument of type 'NoneType' is not a container or iterable
obj TypeError argument of type 'Nothing22' is not a container or iterable
float TypeError argument of type 'float' is not a container or iterable
int in str TypeError 'in <string>' requires string as left operand, not int
str in bytes TypeError a bytes-like object is required, not 'str'
```
