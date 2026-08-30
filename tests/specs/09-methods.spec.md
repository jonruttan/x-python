Attribute access and method calls.

`x.append` is a **value**, not merely part of a call form: Python binds the
receiver at attribute-access time, so `f = x.append; f(4)` appends to `x`. So
getattr returns a closure over the object, and a following `(` simply applies
it.

Mutation is in place. A list is `(py-list . elements)`, and `%set-rest!`
replaces the elements on *that* pair — so every reference to the list sees the
change. Rebuilding and returning a new list would make `x.append(5)` silently do
nothing to `x`.

## methods append

### append adds to the end

```python
(python-run "x = [1, 2]\nx.append(3)\nprint(x)")
```
---
    [1, 2, 3]

### append to an empty list

```python
(python-run "x = []\nx.append('a')\nprint(x)")
```
---
    ['a']

### append twice

```python
(python-run "x = []\nx.append(1)\nx.append(2)\nprint(x)")
```
---
    [1, 2]

### the mutation is visible through another name

Two names for one list are one list. If append rebuilt instead of mutating, this
would print `[1]`.

```python
(python-run "x = [1]\ny = x\nx.append(2)\nprint(y)")
```
---
    [1, 2]

### len sees the appended element

```python
(python-run "x = [1]\nx.append(2)\nprint(len(x))")
```
---
    2

## methods bound

### a bound method is a value

```python
(python-run "x = [1]\nf = x.append\nf(9)\nprint(x)")
```
---
    [1, 9]

### a bound method keeps its receiver

```python
(python-run "a = [1]\nb = [2]\nf = a.append\nf(3)\nprint(a)\nprint(b)")
```
---
```output
[1, 3]
[2]
```

## methods pop

### pop removes and returns the last element

```python
(python-run "x = [1, 2, 3]\nprint(x.pop())\nprint(x)")
```
---
```output
3
[1, 2]
```

### pop from empty raises

```python
(python-run "x = []\nprint(x.pop())")
```
---
    Error: #<err:index pop from empty list>

## methods errors

### an unknown attribute names itself

```python
(python-run "x = [1]\nx.nosuch(1)")
```
---
    Error: #<err:attribute 'list' object has no attribute 'nosuch'>

### attribute access on a non-object raises

```python
(python-run "x = 1\nprint(x.bit_length())")
```
---
    Error: #<err:attribute object has no attribute 'bit_length'>

### a name is required after the dot

```python
(python-run "x = [1]\nprint(x.)")
```
---
    Error: #<err:syntax expected a name after .>
