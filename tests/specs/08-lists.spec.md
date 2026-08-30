Python lists. A list is tagged `(py-list . elements)` rather than a bare x list,
because an empty list and `None` are different values and a bare x list would
make both of them nil — `print([])` would print `None`.

## lists literals

### a list of numbers

```python
(python-run "print([1, 2, 3])")
```
---
    [1, 2, 3]

### an empty list is not None

```python
(python-run "print([])")
```
---
    []

### a list of strings shows their quotes

At top level a string prints bare; inside a container it prints as its repr.

```python
(python-run "print(['a', 'b'])")
```
---
    ['a', 'b']

### a single element

```python
(python-run "print([42])")
```
---
    [42]

### elements are expressions

```python
(python-run "print([1 + 1, 2 * 3])")
```
---
    [2, 6]

### a trailing comma is legal

```python
(python-run "print([1, 2,])")
```
---
    [1, 2]

### nested

```python
(python-run "print([1, [2, 3]])")
```
---
    [1, [2, 3]]

## lists subscript

### by index

```python
(python-run "a = [10, 20, 30]\nprint(a[0])")
```
---
    10

### the last element

```python
(python-run "a = [10, 20, 30]\nprint(a[2])")
```
---
    30

### a negative index counts from the end

```python
(python-run "a = [10, 20, 30]\nprint(a[-1])")
```
---
    30

### negative, further in

```python
(python-run "a = [10, 20, 30]\nprint(a[-3])")
```
---
    10

### out of range raises

A silent nil would propagate into arithmetic and surface far from the subscript
that produced it.

```python
(python-run "a = [1]\nprint(a[5])")
```
---
    Error: #<err:index list index out of range>

### the index may be an expression

```python
(python-run "a = [10, 20, 30]\ni = 1\nprint(a[i + 1])")
```
---
    30

### subscripting a non-list raises

```python
(python-run "print((1)[0])")
```
---
    Error: #<err:type object is not subscriptable>

## lists len

### of a list

```python
(python-run "print(len([1, 2, 3]))")
```
---
    3

### of an empty list

```python
(python-run "print(len([]))")
```
---
    0

### of a string

```python
(python-run "print(len('hello'))")
```
---
    5

## lists together

### a list in a loop

```python
(python-run "a = [3, 5, 7]\ni = 0\nwhile i < len(a):\n    print(a[i])\n    i = i + 1")
```
---
```output
3
5
7
```

### a list returned from a function

```python
(python-run "def f():\n    return [1, 2]\nprint(f())")
```
---
    [1, 2]
