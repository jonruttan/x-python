Assignment is decided by what follows a *target*, not by the shape of the first
token. The parser reads a postfix expression — a name, a subscript, an
attribute, a call — and then looks for `=` or an augmented operator. If neither
follows, the statement is re-parsed as an expression from the start.

A store depends on the target's shape: a name is a `set!`, a subscript is an
item assignment.

## assign subscript

### store by index

```python
(python-run "x = [1, 2, 3]\nx[0] = 9\nprint(x)")
```
---
    [9, 2, 3]

### store at the end

```python
(python-run "x = [1, 2, 3]\nx[2] = 9\nprint(x)")
```
---
    [1, 2, 9]

### a negative index stores from the end

```python
(python-run "x = [1, 2, 3]\nx[-1] = 9\nprint(x)")
```
---
    [1, 2, 9]

### the store is visible through another name

```python
(python-run "x = [1]\ny = x\nx[0] = 5\nprint(y)")
```
---
    [5]

### out of range raises

```python
(python-run "x = [1]\nx[5] = 0")
```
---
    Error: #<err:index list assignment index out of range>

### the index may be an expression

```python
(python-run "x = [1, 2, 3]\ni = 1\nx[i + 1] = 8\nprint(x)")
```
---
    [1, 2, 8]

## assign augmented

### plus-equals on a name

```python
(python-run "n = 1\nn += 2\nprint(n)")
```
---
    3

### minus-equals

```python
(python-run "n = 10\nn -= 3\nprint(n)")
```
---
    7

### times-equals

```python
(python-run "n = 3\nn *= 4\nprint(n)")
```
---
    12

### plus-equals concatenates strings

```python
(python-run "s = 'a'\ns += 'b'\nprint(s)")
```
---
    ab

### plus-equals on a subscript

```python
(python-run "x = [1, 2]\nx[0] += 10\nprint(x)")
```
---
    [11, 2]

### augmented with a negative literal

The tokenizer glues the sign to the literal, so this is the case where that has
to come apart correctly on the right of an augmented operator.

```python
(python-run "x = [5]\nx[0] += -4\nprint(x)")
```
---
    [1]

### a loop counter with plus-equals

```python
(python-run "i = 0\nwhile i < 3:\n    i += 1\nprint(i)")
```
---
    3

## assign errors

### a call is not assignable

```python
(python-run "def f():\n    return 1\nf() = 2")
```
---
    Error: #<err:syntax cannot assign to this target>

## assign together

### building a list in a loop

```python
(python-run "out = []\ni = 0\nwhile i < 3:\n    out.append(i * i)\n    i += 1\nprint(out)")
```
---
    [0, 1, 4]
