Python's operators on Python's containers. These were not missing before this
file existed — they were **wrong, silently**. `[1] + [2]` printed
`64690751520`, `[1] * 3` printed `96291346800` and `'ab' * 2` printed
`77630078720`: the instance pointer read as an integer, no error anywhere. And
`[1, 2] == [1, 2]` was `False`, because the comparison that ran was identity.

The fix is `%type-push-op` on PY-LIST and PY-DICT — Python's own types, which
nothing else in the process can hold. Strings are deliberately NOT done that
way: a type's ops fire when *either* operand carries the type, so putting `*` on
x's str type would change what `*` means for every string in the process, the
platform's included. `'ab' * 2` is handled in the runtime behind a `str?` test.

## concatenation

### two lists

```python
(python-run "print([1] + [2])")
```
---
    [1, 2]

### empty ones

```python
(python-run "print([] + [])")
```
---
    []

### a list and a non-list is a TypeError

```python
(python-run "print([1] + 1)")
```
---
    Error: #<err:type can only concatenate list to list>

### and so is a number and a string

`1 + "a"` reached x's `+` with a string operand and answered a number. Python
raises, and so does this now.

```python
(python-run "print(1 + 'a')")
```
---
    Error: #<err:type unsupported operand type(s) for +>

## repetition

### a list by a count

```python
(python-run "print([1] * 3)")
```
---
    [1, 1, 1]

### the count may be on the left

A type's ops are consulted when either operand carries the type, so this needs
no separate rule — but it does need a test, because the handler has to work out
which operand is the sequence.

```python
(python-run "print(2 * [1, 2])")
```
---
    [1, 2, 1, 2]

### repeating by zero gives an empty list

```python
(python-run "print([1] * 0)")
```
---
    []

### a string by a count

```python
(python-run "print('ab' * 2)")
```
---
    abab

## equality

### lists compare by value, not identity

```python
(python-run "print([1, 2] == [1, 2])")
```
---
    True

### nested lists too

The elementwise compare uses Python's equality rather than x's, which is what
makes this recurse correctly.

```python
(python-run "print([[1], [2]] == [[1], [2]])")
```
---
    True

### a list is never equal to a non-list, and does not raise

```python
(python-run "print([1] == 1)")
```
---
    False

### dicts compare by value

```python
(python-run "print({'a': 1} == {'a': 1})")
```
---
    True

### dict equality ignores order, though printing does not

Insertion order is part of a dict's *printed* form and not part of its identity.
Both halves of that are Python, and they pull in opposite directions, so the
comparison looks each key up rather than walking the two entry lists in step.

```python
(python-run "print({'a': 1, 'b': 2} == {'b': 2, 'a': 1})")
```
---
    True

### a dict holding a list

```python
(python-run "print({'a': [1]} == {'a': [1]})")
```
---
    True

## ordering

### lists compare lexicographically

```python
(python-run "print([1, 2] < [1, 3])")
```
---
    True

### a proper prefix is the smaller

```python
(python-run "print([1] < [1, 2])")
```
---
    True

### and the other way

```python
(python-run "print([2] > [1])")
```
---
    True
