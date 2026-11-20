# x-python card

## Run

```sh
x -l python
x -l python -f PROGRAM.py
x -l python -f tests/card/fact.py -> 2432902008176640000
```

```python
def fact(n):
    return 1 if n <= 1 else n * fact(n - 1)

print(fact(20))                         # -> 2432902008176640000
```

| Run                         | Is                                        |
|-----------------------------|-------------------------------------------|
| `x -l python`               | the `>>>` prompt, or a program on stdin   |
| `x -l python -f FILE`       | a program in a file                       |
| `lang("x")` at the prompt   | the x-lang prompt, on the same values     |

## Values

| Type      | Written                                               |
|-----------|-------------------------------------------------------|
| `int`     | `42` `1_000` `0x1f` `0o17` `0b101`: any size          |
| `float`   | `3.14` `1e-3` `float("inf")`                          |
| `complex` | `2j` `1 + 2j`                                         |
| `bool`    | `True` `False`                                        |
| `None`    | `None`                                                |
| `str`     | `'a'` `"a"` `"""lines"""` `r"raw\n"` `f"{x}"`         |
| `bytes`   | `b"abc"`                                              |
| `list`    | `[1, 2, 3]`: can change                               |
| `tuple`   | `(1, 2)` `(1,)` `()`: cannot                          |
| `dict`    | `{"a": 1}`: keys in the order they were added         |
| `set`     | `{1, 2}` `set()`                                      |

```python
print(2 ** 100)                 # -> 1267650600228229401496703205376
print(7 / 2, 7 // 2, 7 % 2)     # -> 3.5 3 1
print(-7 // 2, -7 % 2)          # -> -4 1
print(0.1 + 0.2)                # -> 0.30000000000000004
print((1 + 2j) * 2j)            # -> (-4+2j)
print(0x1f, 0o17, 0b101, 1_000) # -> 31 15 5 1000
print(type(1), type(1.0))       # -> <class 'int'> <class 'float'>
print(int("42") + 1, float("2.5"), str(3) + "x")    # -> 43 2.5 3x
print(bool(0), bool(""), bool([0]))     # -> False False True
print(None is None, 1 == 1.0)   # -> True True
```

## Operators

| Operators                     | Do                                        |
|-------------------------------|-------------------------------------------|
| `+ - * / // % **`             | arithmetic; `/` is a float, `//` rounds down |
| `== != < <= > >=`             | compare; they chain: `1 < x <= 5`         |
| `and` `or` `not`              | logic; `and`, `or` give one operand       |
| `in` `not in`                 | membership                                |
| `is` `is not`                 | the same object                           |
| `& \| ^ ~ << >>`               | bits                                      |
| `A if C else B`               | A when C is true, else B                  |
| `+= -= *= /= //= %= **=`      | change a name in place                    |

```python
x = 5
print(1 < x <= 5, x != 5)       # -> True False
print(x > 3 and "big" or "small")       # -> big
print("odd" if x % 2 else "even")       # -> odd
print(3 in [1, 2, 3], "a" not in "abc") # -> True False
print(6 & 3, 6 | 3, 6 ^ 3, ~6, 1 << 4)  # -> 2 7 5 -7 16
x += 2
x *= 3
print(x)                        # -> 21
print(divmod(17, 5), abs(-3), pow(2, 10))       # -> (3, 2) 3 1024
print(round(2.567, 2), round(7.5), int(-2.9))   # -> 2.57 8 -2
```

## Strings

| Form                         | Gives                                      |
|------------------------------|--------------------------------------------|
| `s[i]` `s[-1]`               | one character; from the end                |
| `s[a:b]` `s[a:b:step]`       | a slice: from a up to, not including, b    |
| `len(s)` `s + t` `s * 3`     | length, joined, repeated                   |
| `s.upper()` `s.lower()`      | a changed copy: a `str` never changes      |
| `s.strip()` `s.split(sep)`   | trimmed; a list of the parts               |
| `sep.join(list)`             | the parts joined with sep                  |
| `s.find(t)` `s.replace(a, b)` | where t is, or -1; every a made b         |
| `s.startswith(t)` `t in s`   | tests                                      |

```python
s = "Hello, World"
print(len(s), s[0], s[-1])      # -> 12 H d
print(s[7:], s[:5], s[::-1])    # -> World Hello dlroW ,olleH
print(s.upper(), s.lower())     # -> HELLO, WORLD hello, world
print(s.replace("World", "x"))  # -> Hello, x
print(s.split(", "))            # -> ['Hello', 'World']
print("-".join(["a", "b", "c"]))        # -> a-b-c
print(" pad ".strip(), s.find("W"), s.startswith("He")) # -> pad 7 True
print("ab" * 3, "a" + "b", r"a\nb")     # -> ababab ab a\nb
print(repr("it's"), str(1.0), "é".encode())     # -> "it's" 1.0 b'\xc3\xa9'
```

### Formatting

| Form                  | Gives                                             |
|-----------------------|---------------------------------------------------|
| `f"{x}"`              | x in the text; any expression                     |
| `f"{x!r}"`            | its `repr`                                        |
| `f"{x:.2f}"`          | two decimals                                      |
| `f"{x:5d}"` `f"{x:<5}"` `f"{x:05}"` | padded right, left, with zeros       |
| `f"{x:x}"` `f"{x:b}"` `f"{x:,}"` | hexadecimal, binary, thousands         |
| `"%s %d %.1f" % (a, b, c)` | the older form                               |
| `"{} {}".format(a, b)` | the method                                       |

```python
name, n, pi = "Ada", 42, 3.14159
print(f"{name} is {n}")         # -> Ada is 42
print(f"{pi:.2f}|{n:5d}|{n:<5}|{n:05}") # -> 3.14|   42|42   |00042
print(f"{n:x} {n:b} {1234567:,}")       # -> 2a 101010 1,234,567
print(f"{name!r} {n + 1}")      # -> 'Ada' 43
print("%s has %d, %.1f" % (name, n, pi))        # -> Ada has 42, 3.1
print("{} and {}".format(1, 2), "{0}{0}".format("a"))   # -> 1 and 2 aa
```

## Collections

### Lists

```python
a = [3, 1, 2]
a.append(4)
a.insert(0, 9)
print(a, len(a))                # -> [9, 3, 1, 2, 4] 5
print(a[1:3], a[-1], a[::2])    # -> [3, 1] 4 [9, 1, 4]
print(sorted(a), a.pop(), a)    # -> [1, 2, 3, 4, 9] 4 [9, 3, 1, 2]
a.sort(reverse=True)
print(a, a.index(3), sum(a), min(a), max(a))    # -> [9, 3, 2, 1] 1 15 1 9
print([x * x for x in range(5) if x % 2 == 0])  # -> [0, 4, 16]
b = a[:]
b[0] = 0
print(a[0], b[0], a + [7], [0] * 3)     # -> 9 0 [9, 3, 2, 1, 7] [0, 0, 0]
```

### Tuples and unpacking

```python
t = (1, "two", 3.0)
x, y, z = t
print(y, t[0], len(t))          # -> two 1 3
first, *rest = [1, 2, 3, 4]
print(first, rest)              # -> 1 [2, 3, 4]
a, b = 1, 2
a, b = b, a
print(a, b)                     # -> 2 1
for i, ch in enumerate("ab"):
    print(i, ch)                # -> 0 a
                                # -> 1 b
print(list(zip([1, 2], "xy")))  # -> [(1, 'x'), (2, 'y')]
```

### Dicts

```python
d = {"a": 1, "b": 2}
d["c"] = 3
print(d["a"], d.get("z", 0), "b" in d, len(d))  # -> 1 0 True 3
print(list(d.keys()), list(d.values())) # -> ['a', 'b', 'c'] [1, 2, 3]
print([k + str(v) for k, v in d.items()])       # -> ['a1', 'b2', 'c3']
del d["a"]
print(d.pop("b"))               # -> 2
print(d)                        # -> {'c': 3}
d.update(x=1)
d.setdefault("y", []).append(5)
print(d)                        # -> {'c': 3, 'x': 1, 'y': [5]}
print({n: n * n for n in range(3)})     # -> {0: 0, 1: 1, 2: 4}
```

### Sets

```python
s = {1, 2, 3}
t = set([3, 4])
print(s | t, s & t, s - t, s ^ t)       # -> {1, 2, 3, 4} {3} {1, 2} {1, 2, 4}
s.add(9)
s.discard(1)
print(sorted(s), 2 in s, len(s))        # -> [2, 3, 9] True 3
print(sorted({c for c in "hello"}))     # -> ['e', 'h', 'l', 'o']
```

## Control

| Statement                          | Runs                                 |
|------------------------------------|--------------------------------------|
| `if A:` `elif B:` `else:`          | the first block whose test is true   |
| `for X in ITEMS:`                  | the block with X as each item        |
| `while A:`                         | the block while A is true            |
| `break` `continue`                 | leaves the loop; starts its next turn |
| `else:` after a loop               | when the loop ended without `break`  |
| `pass`                             | nothing                              |
| `try:` `except E as e:` `finally:` | a block, and what handles its errors |
| `raise E("text")`                  | an error                             |
| `with A as X:`                     | a block between A's enter and exit   |

```python
n = 7
if n < 5:
    print("small")
elif n < 10:
    print("medium")             # -> medium
else:
    print("large")

total = 0
for i in range(1, 5):
    if i == 3:
        continue
    total += i
print(total)                    # -> 7

while n > 0:
    n -= 3
    if n < 0:
        break
else:
    print("never")
print(n)                        # -> -2

for i in range(3):
    pass
else:
    print("done", i)            # -> done 2
```

### Errors

```python
def half(x):
    if x % 2:
        raise ValueError("odd: " + str(x))
    return x // 2

try:
    print(half(4))              # -> 2
    half(3)
except ValueError as e:
    print("caught", e)          # -> caught odd: 3
else:
    print("no error")
finally:
    print("always")             # -> always

try:
    [][1]
except (KeyError, IndexError) as e:
    print(type(e).__name__)     # -> IndexError

class Fail(Exception):
    pass

try:
    raise Fail("mine")
except Exception as e:
    print(repr(e))              # -> Fail('mine')
```

## Functions

| Form                        | Is                                         |
|-----------------------------|--------------------------------------------|
| `def f(a, b=1):`            | a function; b has a default                |
| `def f(*args, **kw):`       | any further arguments, as a tuple and a dict |
| `def f(a, *, key):`         | key is given by name only                  |
| `f(1, b=2)` `f(*list, **dict)` | calls: by place, by name, spread        |
| `return X`                  | the answer; without one, `None`            |
| `lambda x: x + 1`           | a function in one expression               |
| `nonlocal n` `global n`     | assign to an outer name                    |
| `@decorator`                | the function, passed through decorator     |
| `yield X`                   | makes the function a generator             |

```python
def area(w, h=1, *, unit="m"):
    return f"{w * h}{unit}"

print(area(2), area(2, 3), area(2, h=4, unit="cm"))     # -> 2m 6m 8cm

def total(*args, **kw):
    return sum(args) + sum(kw.values())

print(total(1, 2, a=3), total(*[1, 2], **{"b": 4}))     # -> 6 7

square = lambda x: x * x
print(list(map(square, [1, 2, 3])))     # -> [1, 4, 9]
print(list(filter(lambda x: x > 1, [1, 2, 3]))) # -> [2, 3]

def counter():
    n = 0
    def step():
        nonlocal n
        n += 1
        return n
    return step

c = counter()
print(c(), c())                 # -> 1 2
```

### Decorators and generators

```python
def twice(f):
    def wrapper(*a):
        return f(*a) * 2
    return wrapper

@twice
def add(a, b):
    return a + b

print(add(1, 2))                # -> 6

def countdown(n):
    while n > 0:
        yield n
        n -= 1

print(list(countdown(3)))       # -> [3, 2, 1]
g = (x * x for x in range(4))
print(next(g), next(g), sum(g)) # -> 0 1 13
print(any(x > 2 for x in [1, 3]), all([1, 0]))  # -> True False
```

## Classes

| Form                         | Is                                        |
|------------------------------|-------------------------------------------|
| `class C(Base):`             | a class; Base is optional, and may be several |
| `def __init__(self, x):`     | what runs when `C(x)` makes one           |
| `self.x`                     | a value kept on the object                |
| `super().method()`           | the base class's method                   |
| `__repr__` `__str__`         | how it prints                             |
| `__eq__` `__lt__` `__add__`  | what `==`, `<`, `+` do                    |
| `__len__` `__getitem__` `__iter__` `__contains__` | `len`, `[]`, `for`, `in` |
| `__call__`                   | what `obj()` does                         |
| `__enter__` `__exit__`       | what `with` calls                         |
| `@property`                  | a method read as a value                  |
| `@classmethod` `@staticmethod` | a method of the class; of no object     |

```python
class Shape:
    count = 0

    def __init__(self, name):
        self.name = name
        Shape.count += 1

    def area(self):
        return 0

    def __repr__(self):
        return f"{self.name}({self.area()})"

class Rect(Shape):
    def __init__(self, w, h):
        super().__init__("rect")
        self.w, self.h = w, h

    def area(self):
        return self.w * self.h

    def __eq__(self, other):
        return self.area() == other.area()

    def __add__(self, other):
        return Rect(self.w + other.w, self.h)

r = Rect(2, 3)
print(r, r.area(), Shape.count) # -> rect(6) 6 1
print(r == Rect(3, 2), r + r)   # -> True rect(12)
print(isinstance(r, Shape), type(r).__name__, hasattr(r, "w"))
# -> True Rect True
```

```python
class Temp:
    def __init__(self, c):
        self.c = c

    @property
    def f(self):
        return self.c * 9 / 5 + 32

    @classmethod
    def boiling(cls):
        return cls(100)

    @staticmethod
    def unit():
        return "C"

    def __enter__(self):
        print("enter")
        return self

    def __exit__(self, kind, value, trace):
        print("exit")
        return False

print(Temp(0).f, Temp.boiling().f, Temp.unit()) # -> 32.0 212.0 C
with Temp(20) as t:             # -> enter
    print("inside", t.c)        # -> inside 20
                                # -> exit
```

## Modules

| Form                          | Does                                     |
|-------------------------------|------------------------------------------|
| `import math`                 | the module, as `math.sqrt`               |
| `import math as m`            | under another name                       |
| `from math import sqrt, pi`   | the names themselves                     |
| `import mine`                 | `mine.py`, beside the program            |

| Module        | Holds                                               |
|---------------|-----------------------------------------------------|
| `math` `cmath` | functions on floats; on complex numbers            |
| `collections` | `deque` and more                                    |
| `struct` `array` | bytes packed by a format; typed arrays           |
| `io` `os` `sys` `errno` | files and the system                      |
| `gc` `types` `builtins` | the collector, type names, the builtins   |

```python
import math
from collections import deque
import struct

print(math.sqrt(16), math.pi, math.floor(2.7))  # -> 4.0 3.141592653589793 2
q = deque([1, 2])
q.appendleft(0)
print(q.popleft(), list(q))     # -> 0 [1, 2]
print(struct.pack("<H", 258))   # -> b'\x02\x01'
```

### Builtins

| Builtins                                  | For                          |
|-------------------------------------------|------------------------------|
| `print` `input` `open` `repr`             | reading and writing          |
| `len` `range` `enumerate` `zip` `reversed` `sorted` | walking items      |
| `map` `filter` `sum` `min` `max` `any` `all` | working over items        |
| `int` `float` `str` `bool` `bytes`        | making a value               |
| `list` `tuple` `dict` `set`               | making a collection          |
| `abs` `round` `divmod` `pow`              | numbers                      |
| `chr` `ord` `hex` `bin` `oct`             | characters and digits        |
| `type` `isinstance` `callable`            | asking what a value is       |
| `hasattr` `getattr` `setattr`             | an attribute, by its name    |
| `iter` `next`                             | stepping by hand             |
| `eval` `exec`                             | running text as Python       |

```python
print(chr(65), ord("a"), hex(255), bin(5))      # -> A 97 0xff 0b101
print(list(reversed([1, 2, 3])), list(range(0, 10, 3)))
# -> [3, 2, 1] [0, 3, 6, 9]
print(bytes([104, 105]), b"hi".decode(), "hi".encode()) # -> b'hi' hi b'hi'
print(getattr("x", "upper")(), callable(len))   # -> X True
print(eval("1 + 2"))            # -> 3
it = iter([1, 2])
print(next(it), next(it), next(it, "end"))      # -> 1 2 end
```

## Differs

| Here                                        | In CPython                    |
|---------------------------------------------|-------------------------------|
| twelve modules can be imported              | the whole standard library    |
| `lang("x")` at the prompt gives x-lang's    | no such call                  |
| a name is `py-NAME` in the base x-lang sees | names are Python's alone      |
| 592 of 646 conformance programs print the same | the oracle                 |

## More

| Where                              | What                              |
|------------------------------------|-----------------------------------|
| `README.md`                        | the suites, the prompt, the layout |
| `tests/specs/`                     | one case a behaviour              |
| `docs/values-on-the-type-system.md` | how Python's values are x types  |
| `make score`                       | the conformance table             |
| `make card`                        | runs every program on this page   |
