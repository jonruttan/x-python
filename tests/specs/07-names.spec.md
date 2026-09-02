Python's namespace is kept separate from x's, because a Python name that x also
binds would otherwise resolve to x's — `int` is bound in x, so `int(1)` called
it with arguments it never expected and the interpreter died.

Identifiers are prefixed internally. That prefix is a mechanism and must never
reach the programmer: an error naming `py-int` sends them looking for something
they never wrote. So a name that is mentioned but never bound gets a shim that
raises Python's own message with Python's own spelling.

## names undefined

### an undefined name raises with the name the programmer wrote

This case's original example was `int` — chosen when `int` was deliberately
unbound, to pin that the interpreter said `int` and not `py-int`. Then #18 made
`int` a real builtin and the example stopped being an example: `int(1)` answers
1. The point of the case is the SPELLING of the error, so it keeps making that
point with a name that has not graduated.

```python
(python-run "print(frob(1))")
```
---
    Error: #<err:name name 'frob' is not defined>

### int graduated from this file

The old expected output of the case above, kept as its own case because the
change of answer IS the feature: the name stopped raising because it now works.

```python
(python-run "print(int(1))")
```
---
    1

### and a different one names itself

```python
(python-run "print(frobnicate(1))")
```
---
    Error: #<err:name name 'frobnicate' is not defined>

### a bare reference does NOT raise yet

Pending, and the limitation is the shim's shape: an undefined name is bound to a
function that raises when CALLED, so mentioning it without calling hands back
the function instead. Catching that wants name resolution at parse time against
the bound set, rather than a runtime stand-in.

```python
(python-run "print(undefined_thing)")
```

## names bound

### an assigned name is not undefined

```python
(python-run "value = 3\nprint(value)")
```
---
    3

### a def name is not undefined

```python
(python-run "def helper():\n    return 1\nprint(helper())")
```
---
    1

### a parameter is not undefined

A parameter is bound by the call, not by an assignment, so the scan has to read
it out of the def's parentheses.

```python
(python-run "def f(param):\n    return param\nprint(f(9))")
```
---
    9

### a keyword is grammar, not a name

`if` and `while` reach the tokenizer as names. Without knowing them the scan
would emit a NameError shim for the grammar itself.

```python
(python-run "if 1 == 1:\n    print('ok')")
```
---
    ok

## names constants

### True

```python
(python-run "print(True)")
```
---
    True

### False

```python
(python-run "print(False)")
```
---
    False

### None prints nothing of its own

```python
(python-run "print(None)\nprint('after')")
```
---
```output
None
after
```
