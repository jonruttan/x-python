`return` invokes an escape continuation. It used to compile to its expression,
and x returns a body's *last* value — so a `return` anywhere but the tail
computed its value and discarded it. `if x < 0: return 0` fell through and
answered the wrong number, with no error anywhere.

The body now runs inside `call/cc`, and ends in `()` so a function that falls
off the end answers `None`, which is Python's rule.

## return early

### a guard clause returns before the rest

The case that was silently wrong: this used to answer 1, because the `return 0`
computed 0 and threw it away.

```python
(python-run "def f(x):\n    if x < 0:\n        return 0\n    return x + 1\nprint(f(-5))")
```
---
    0

### and the other branch still works

```python
(python-run "def f(x):\n    if x < 0:\n        return 0\n    return x + 1\nprint(f(1))")
```
---
    2

### a return inside a while stops the function

```python
(python-run "def first_big(a):\n    i = 0\n    while i < len(a):\n        if a[i] > 2:\n            return a[i]\n        i += 1\n    return -1\nprint(first_big([1, 2, 5, 7]))")
```
---
    5

### a return inside a for

```python
(python-run "def find(a, t):\n    for v in a:\n        if v == t:\n            return 'yes'\n    return 'no'\nprint(find([1, 2], 2))\nprint(find([1, 2], 9))")
```
---
```output
yes
no
```

### statements after a return do not run

```python
(python-run "def f():\n    return 1\n    print('unreachable')\nprint(f())")
```
---
    1

## return none

### a bare return yields None

```python
(python-run "def f():\n    return\nprint(f())")
```
---
    None

### falling off the end yields None

Python's rule, and the reason the body ends in a nil: without it the body's last
expression would leak out as the return value.

```python
(python-run "def f():\n    x = 1\nprint(f())")
```
---
    None

### a bare return still stops the function

```python
(python-run "def f():\n    print('a')\n    return\n    print('b')\nf()")
```
---
    a

## return nested

### an inner function's return does not escape the outer one

Each def binds its own escape continuation, so the inner shadows the outer.

```python
(python-run "def outer():\n    def inner():\n        return 'inner'\n    v = inner()\n    return v + '/outer'\nprint(outer())")
```
---
    inner/outer

### a returned value can be a list

```python
(python-run "def f():\n    for i in range(3):\n        if i == 1:\n            return [i, i]\n    return []\nprint(f())")
```
---
    [1, 1]

## return outside a function

### return at module level is refused

Python raises SyntaxError; here the escape continuation is simply not bound.
Different words, same refusal.

```python
(python-run "return 1")
```
---
    Error: Unbound SYMBOL '%py-return'
