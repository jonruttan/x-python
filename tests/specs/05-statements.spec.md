Compound statements, compiled onto x's control vocabulary — `if`, `let`, `when`,
`unless`, `cond`, `case`. There is no loop construct, so `while` becomes
self-recursion in tail position, where x's TCO makes it a loop rather than a
stack that grows with the iteration count.

## statements if

### a true branch runs

```python
(python-run "if 1 == 1:\n    print('yes')")
```
---
    yes

### a false branch does not

```python
(python-run "if 1 == 2:\n    print('no')\nprint('after')")
```
---
    after

### else

```python
(python-run "if 1 == 2:\n    print('a')\nelse:\n    print('b')")
```
---
    b

### elif is else-if, which is what Python's grammar says it is

```python
(python-run "x = 2\nif x == 1:\n    print('one')\nelif x == 2:\n    print('two')\nelse:\n    print('other')")
```
---
    two

### a body of several statements

```python
(python-run "if 1 == 1:\n    print('a')\n    print('b')")
```
---
```output
a
b
```

## statements while

### a counting loop

The assignment inside the body has to reach the outer name. x's `def` binds by
frame depth, so a `def` here would make a fresh local each iteration and the
loop would never terminate — which is why targets are hoisted and assignment
compiles to `set!`.

```python
(python-run "i = 0\nwhile i < 3:\n    print(i)\n    i = i + 1")
```
---
```output
0
1
2
```

### a loop whose condition is false at entry never runs

```python
(python-run "i = 5\nwhile i < 3:\n    print(i)\nprint('done')")
```
---
    done

### an accumulator

```python
(python-run "n = 1\ntotal = 0\nwhile n < 5:\n    total = total + n\n    n = n + 1\nprint(total)")
```
---
    10

## statements def

### a function with no arguments

```python
(python-run "def f():\n    return 7\nprint(f())")
```
---
    7

### a function with one argument

```python
(python-run "def double(x):\n    return x * 2\nprint(double(21))")
```
---
    42

### a function with two arguments

```python
(python-run "def add(a, b):\n    return a + b\nprint(add(2, 3))")
```
---
    5

### a negative argument

The case left pending in the signed-literal spec, now reachable.

```python
(python-run "def f(x):\n    return x\nprint(f(-1))")
```
---
    -1

### a function body with more than one statement

```python
(python-run "def f(x):\n    print('called')\n    return x + 1\nprint(f(1))")
```
---
```output
called
2
```

## statements pass

### pass does nothing

```python
(python-run "if 1 == 1:\n    pass\nprint('after')")
```
---
    after

## statements nesting

### an if inside a while

```python
(python-run "i = 0\nwhile i < 4:\n    if i == 2:\n        print('two')\n    i = i + 1\nprint('done')")
```
---
```output
two
done
```
