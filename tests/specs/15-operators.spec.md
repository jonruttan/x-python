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
    Error: #<err:type can only concatenate list (not "int") to list>

### and so is a number and a string

`1 + "a"` reached x's `+` with a string operand and answered a number. Python
raises, and so does this now.

```python
(python-run "print(1 + 'a')")
```
---
    Error: #<err:type unsupported operand type(s) for +: 'int' and 'str'>

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

## refusals, and bools as ints

A number beside a non-number is a TypeError naming both types; the platform's
operators would answer a word for it, raise under a tag no except clause maps,
or crash (`1 / None`). A bool is the int it is on either side of every seam.

### a non-number beside a number is refused, in CPython's words

```python
(python-run "def err(f):\n    try:\n        print(\"no error\", repr(f()))\n    except TypeError as e:\n        print(e)\n\n\nerr(lambda: 1 + None)\nerr(lambda: 1 / None)\nerr(lambda: 1 * {})\nerr(lambda: bytearray() // 2)\nerr(lambda: memoryview(b\"\") + memoryview(b\"\"))\nerr(lambda: 1 - [1])\nerr(lambda: 2 ** \"a\")\nerr(lambda: 5 % None)\nerr(lambda: 1 < None)\nerr(lambda: \"a\" > 1)\nerr(lambda: [1] < (1,))\nerr(lambda: (1,) + [1])\nerr(lambda: \"a\" + 1)\nerr(lambda: 1.5 * \"a\")\nerr(lambda: None * [1])\nerr(lambda: divmod(1, \"a\"))\nerr(lambda: {1} | [1])\nerr(lambda: 1 << 1.5)")
```
---
```output
unsupported operand type(s) for +: 'int' and 'NoneType'
unsupported operand type(s) for /: 'int' and 'NoneType'
unsupported operand type(s) for *: 'int' and 'dict'
unsupported operand type(s) for //: 'bytearray' and 'int'
unsupported operand type(s) for +: 'memoryview' and 'memoryview'
unsupported operand type(s) for -: 'int' and 'list'
unsupported operand type(s) for ** or pow(): 'int' and 'str'
unsupported operand type(s) for %: 'int' and 'NoneType'
'<' not supported between instances of 'int' and 'NoneType'
'>' not supported between instances of 'str' and 'int'
'<' not supported between instances of 'list' and 'tuple'
can only concatenate tuple (not "list") to tuple
can only concatenate str (not "int") to str
can't multiply sequence by non-int of type 'float'
can't multiply sequence by non-int of type 'NoneType'
unsupported operand type(s) for divmod(): 'int' and 'str'
unsupported operand type(s) for |: 'set' and 'list'
unsupported operand type(s) for <<: 'int' and 'float'
```

### a bool is the int it is, in every seam

```python
(python-run "print(1 // True, 1 % True, 2 ** True, True ** True, 1.5 // True, True // 1)\nprint(True + 1, True - 2, True * 3, True < 2, 2.5 > True, False <= 0)\nprint(True * \"ab\", \"ab\" * True, b\"ab\" * True, [1] * True, (1,) * True, False * [1])\nprint((1,) + (2,), (1, 2) < (1, 3), [1, 2] <= [1, 2])")
```
---
```output
1 0 2 1 1.0 1
2 -1 3 True True True
ab ab b'ab' [1] (1,) []
(1, 2) True True
```
