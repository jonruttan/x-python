`for` walks an iterable's elements, binding the target each time. Recursion in
tail position, the same shape `while` uses and for the same reason: there is no
loop construct, and a non-tail call has no depth limit behind it.

`range` is **eager** — it builds the whole list. Python 3's is lazy, so
`range(10000000)` is free there and ten million elements here. Every conformance
program that uses range walks all of it, so the difference is memory rather than
answers.

## for lists

### over a list

```python
(python-run "for x in [1, 2, 3]:\n    print(x)")
```
---
```output
1
2
3
```

### over an empty list runs nothing

```python
(python-run "for x in []:\n    print(x)\nprint('done')")
```
---
    done

### the target outlives the loop, as in Python

```python
(python-run "for x in [1, 2, 3]:\n    pass\nprint(x)")
```
---
    3

### a body of several statements

```python
(python-run "total = 0\nfor n in [1, 2, 3]:\n    total += n\n    print(total)")
```
---
```output
1
3
6
```

### over a list built at runtime

```python
(python-run "a = []\na.append(5)\na.append(6)\nfor v in a:\n    print(v)")
```
---
```output
5
6
```

## for range

### range with one argument

```python
(python-run "for i in range(3):\n    print(i)")
```
---
```output
0
1
2
```

### range with a start

```python
(python-run "for i in range(2, 5):\n    print(i)")
```
---
```output
2
3
4
```

### range with a step

```python
(python-run "for i in range(0, 6, 2):\n    print(i)")
```
---
```output
0
2
4
```

### a negative step counts down

```python
(python-run "for i in range(3, 0, -1):\n    print(i)")
```
---
```output
3
2
1
```

### an empty range runs nothing

```python
(python-run "for i in range(0):\n    print(i)\nprint('done')")
```
---
    done

### range is a list

```python
(python-run "print(range(4))")
```
---
    [0, 1, 2, 3]

### a zero step raises rather than looping forever

There is no depth limit on non-tail calls here, so an unbounded loop is an OOM
rather than an error.

```python
(python-run "print(range(0, 5, 0))")
```
---
    Error: #<err:value range() arg 3 must not be zero>

## for strings

### a string iterates by character

```python
(python-run "for c in 'abc':\n    print(c)")
```
---
```output
a
b
c
```

## for errors

### a number is not iterable

```python
(python-run "for x in 5:\n    print(x)")
```
---
    Error: #<err:type object is not iterable>

### a name is required after for

```python
(python-run "for 5 in [1]:\n    print(1)")
```
---
    Error: #<err:syntax expected a name after for>

## for together

### nested loops

```python
(python-run "for i in range(2):\n    for j in range(2):\n        print(i * 10 + j)")
```
---
```output
0
1
10
11
```

### building a list

```python
(python-run "out = []\nfor i in range(4):\n    if i % 2 == 0:\n        out.append(i)\nprint(out)")
```
---
    [0, 2]
