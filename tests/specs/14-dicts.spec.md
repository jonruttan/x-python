A dict is `(py-dict . entries)`, each entry a `(key . value)` pair, held in
**insertion order**. x's `Dict` is a content-hashed table and would be faster,
but Python 3.7+ preserves insertion order and this suite compares printed
output — so the order is part of the answer, not an implementation detail.

Updating a value mutates that entry pair, so no rebuild and every reference sees
it — the same identity argument that makes list `append` work.

## dicts literals

### a dict prints its entries in insertion order

```python
(python-run "print({'a': 1, 'b': 2})")
```
---
    {'a': 1, 'b': 2}

### insertion order is not sorted order

```python
(python-run "print({'b': 1, 'a': 2})")
```
---
    {'b': 1, 'a': 2}

### an empty dict

`{}` is an empty dict, not an empty set.

```python
(python-run "print({})")
```
---
    {}

### numeric keys

```python
(python-run "print({1: 'x', 2: 'y'})")
```
---
    {1: 'x', 2: 'y'}

### values are expressions

```python
(python-run "print({'n': 1 + 1})")
```
---
    {'n': 2}

### a trailing comma is legal

```python
(python-run "print({'a': 1,})")
```
---
    {'a': 1}

### a dict may hold a list

```python
(python-run "print({'xs': [1, 2]})")
```
---
    {'xs': [1, 2]}

## dicts lookup

### by key

```python
(python-run "d = {'a': 1}\nprint(d['a'])")
```
---
    1

### a missing key raises

```python
(python-run "d = {'a': 1}\nprint(d['z'])")
```
---
    Error: #<err:key key not found>

### get returns None for a missing key

That is why `get` exists next to subscripting.

```python
(python-run "d = {'a': 1}\nprint(d.get('z'))")
```
---
    None

### get takes a default

```python
(python-run "d = {'a': 1}\nprint(d.get('z', 0))")
```
---
    0

### get finds a present key

```python
(python-run "d = {'a': 5}\nprint(d.get('a', 0))")
```
---
    5

## dicts store

### assigning an existing key replaces in place

```python
(python-run "d = {'a': 1}\nd['a'] = 9\nprint(d)")
```
---
    {'a': 9}

### a new key goes on the end

```python
(python-run "d = {'a': 1}\nd['b'] = 2\nprint(d)")
```
---
    {'a': 1, 'b': 2}

### building a dict from empty

```python
(python-run "d = {}\nd['x'] = 1\nd['y'] = 2\nprint(d)")
```
---
    {'x': 1, 'y': 2}

### the store is visible through another name

```python
(python-run "d = {}\ne = d\nd['k'] = 1\nprint(e)")
```
---
    {'k': 1}

### augmented assignment on a key

```python
(python-run "d = {'n': 1}\nd['n'] += 4\nprint(d)")
```
---
    {'n': 5}

## dicts len and iteration

### len counts entries

```python
(python-run "print(len({'a': 1, 'b': 2}))")
```
---
    2

### len of an empty dict

```python
(python-run "print(len({}))")
```
---
    0

### iterating a dict yields its keys

```python
(python-run "for k in {'a': 1, 'b': 2}:\n    print(k)")
```
---
```output
a
b
```

### keys

```python
(python-run "print({'a': 1, 'b': 2}.keys())")
```
---
    ['a', 'b']

### values

```python
(python-run "print({'a': 1, 'b': 2}.values())")
```
---
    [1, 2]

## dicts errors

### an unknown method names itself

```python
(python-run "print({}.nosuch())")
```
---
    Error: #<err:attribute 'dict' object has no attribute 'nosuch'>

### a key must be followed by a colon

```python
(python-run "print({'a' 1})")
```
---
    Error: #<err:syntax expected : after a dict key>

## dicts together

### counting with a dict

```python
(python-run "counts = {}\nfor c in 'abca':\n    if c in counts:\n        counts[c] += 1\n    else:\n        counts[c] = 1\nprint(counts)")
```
