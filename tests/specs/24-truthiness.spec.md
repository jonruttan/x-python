Python's truth in conditions, and the operators defined by it.

`if []:` must not run its body: an empty list is falsy in Python, and a PY-LIST
instance is a non-nil value to x — so the bare value in an x `if` was **silently
wrong**, the failure mode this bundle keeps finding. `bool()` stated the rule
once in `%py-truthy` (the empties and the zeros are false); conditions now ask
it.

`and`, `or` and `not` arrive in the same change because Python defines them BY
truthiness — and they **return an operand, not a boolean**: `[] or 5` is `5`,
`0 and x` is `0`. Each emits a `let` binding the left side once (it must not
evaluate twice) and an `if` over the truth test choosing between the bound value
and the right side — which gives short-circuit for free, because the right side
sits in a branch that may never run.

## conditions

### the empties are falsy

```python
(python-run "if []:\n    print('no')\nelse:\n    print('empty list falsy')\nif '':\n    print('no')\nelse:\n    print('empty str falsy')\nif {}:\n    print('no')\nelse:\n    print('empty dict falsy')")
```
---
```output
empty list falsy
empty str falsy
empty dict falsy
```

### the zeros and None are falsy

```python
(python-run "if 0:\n    print('no')\nelse:\n    print('zero falsy')\nif None:\n    print('no')\nelse:\n    print('none falsy')")
```
---
```output
zero falsy
none falsy
```

### non-empty is truthy, zero element and all

```python
(python-run "if [0]:\n    print('list truthy')\nif 'a':\n    print('str truthy')")
```
---
```output
list truthy
str truthy
```

### elif asks the same question

```python
(python-run "x = []\nif x:\n    print('a')\nelif [1]:\n    print('b')\nelse:\n    print('c')")
```
---
    b

### while stops when the list empties

The loop that motivated the fix: draining a list is ordinary Python, and under
x's truthiness it never terminated.

```python
(python-run "x = [1, 2]\nwhile x:\n    print(x.pop())")
```
---
```output
2
1
```

## or, and, not

### or returns the first truthy operand

```python
(python-run "print([] or 5)\nprint(0 or 'x')\nprint(1 or 2)")
```
---
```output
5
x
1
```

### and returns the deciding operand

```python
(python-run "print(1 and 2)\nprint([] and 5)\nprint(0 and 5)")
```
---
```output
2
[]
0
```

### the right side may never run

The proof is a side effect that does not happen.

```python
(python-run "def f():\n    print('ran')\n    return True\nx = False and f()\ny = True or f()\nprint(x)\nprint(y)")
```
---
```output
False
True
```

### not is Python's, and answers a real boolean

```python
(python-run "print(not [])\nprint(not 3)\nprint(not '')\nprint(not None)")
```
---
```output
True
False
True
True
```

### and binds tighter than or, not tighter than both

`1 or 0 and 5` is `1 or (0 and 5)`; `not 0 and 5` is `(not 0) and 5`, which is
`5` — an operand again, because `and` returned it.

```python
(python-run "print(1 or 0 and 5)\nprint(0 or 0 and 5)\nprint(not 0 and 5)")
```
---
```output
1
0
5
```

### not over a comparison

```python
(python-run "print(not 1 == 2)")
```
---
    True

### composed in a condition

```python
(python-run "a = 1\nb = []\nif a and not b:\n    print('both')")
```
---
    both
