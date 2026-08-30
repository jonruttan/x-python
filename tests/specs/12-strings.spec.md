String methods map onto `Str8`, which already has them. The work is the *shape*,
not the algorithm: `Str8` takes its subject last, Python takes it first as the
receiver, and `split`/`join` cross the list boundary so their results are tagged
or untagged on the way through.

## strings case

### upper

```python
(python-run "print('hello'.upper())")
```
---
    HELLO

### lower

```python
(python-run "print('HELLO'.lower())")
```
---
    hello

### on a variable

```python
(python-run "s = 'abc'\nprint(s.upper())")
```
---
    ABC

## strings trim

### strip

```python
(python-run "print('  hi  '.strip())")
```
---
    hi

### strip leaves the inside alone

```python
(python-run "print('  a b  '.strip())")
```
---
    a b

## strings split and join

### split on a separator returns a list

```python
(python-run "print('a,b,c'.split(','))")
```
---
    ['a', 'b', 'c']

### split with no separator splits on spaces

```python
(python-run "print('a b c'.split())")
```
---
    ['a', 'b', 'c']

### the result is a real list

```python
(python-run "parts = 'a,b'.split(',')\nprint(len(parts))\nprint(parts[0])")
```
---
```output
2
a
```

### join puts the separator between

```python
(python-run "print('-'.join(['a', 'b', 'c']))")
```
---
    a-b-c

### join of an empty list

```python
(python-run "print(','.join([]))")
```
---


### join of a non-list raises

```python
(python-run "print(','.join(5))")
```
---
    Error: #<err:type can only join an iterable of str>

### split then join round-trips

```python
(python-run "print('.'.join('a.b.c'.split('.')))")
```
---
    a.b.c

## strings search

### replace

```python
(python-run "print('banana'.replace('a', 'o'))")
```
---
    bonono

### startswith

```python
(python-run "print('hello'.startswith('he'))")
```
---
    True

### startswith, false

```python
(python-run "print('hello'.startswith('x'))")
```
---
    False

### endswith

```python
(python-run "print('hello'.endswith('lo'))")
```
---
    True

### find returns an index

```python
(python-run "print('hello'.find('l'))")
```
---
    2

### find returns -1 when absent

Python's contract, and the reason this is `find` rather than `index` — that one
raises, and it is not implemented.

```python
(python-run "print('hello'.find('z'))")
```
---
    -1

## strings index

### by index yields a one-character string

There is no character type at this surface, so `s[0]` is a string of length one,
as in Python.

```python
(python-run "print('abc'[0])")
```
---
    a

### a negative index

```python
(python-run "print('abc'[-1])")
```
---
    c

### out of range raises

```python
(python-run "print('abc'[9])")
```
---
    Error: #<err:index string index out of range>

### len of a string

```python
(python-run "print(len('abc'))")
```
---
    3

## strings errors

### an unknown method names itself

```python
(python-run "print('a'.nosuch())")
```
---
    Error: #<err:attribute 'str' object has no attribute 'nosuch'>

## strings together

### iterate the result of a split

```python
(python-run "for w in 'one two'.split():\n    print(w.upper())")
```
---
```output
ONE
TWO
```
