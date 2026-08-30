Both containers register an `iter` handler, so anything in the process that
iterates — not just Python's own `for` — can walk a Python list or dict.

The first version of those handlers was wrong, and wrong in a way nothing would
have caught: it returned bare values and treated a nil return as exhaustion.
Python's `None` **is** nil here, so `[None]` would have stopped at the first
element. Nothing consumed the slot, so no test failed.

The real contract is `(value . next-state)`, and only a nil **pair** ends the
walk — exhaustion rides the state, not the value. A nil value is an ordinary
element. These cases exist so the slot is exercised rather than merely present.

## the iterator protocol

### a Python list, including a None

```python
(%seq (write (Iter ->list (Iter new (%py-list-new (list 1 () 2))))) (newline))
```
---
    (1 () 2)

### a None at the end, where a value-terminated stepper would have been right by luck

```python
(%seq (write (Iter ->list (Iter new (%py-list-new (list 1 ()))))) (newline))
```
---
    (1 ())

### a list of nothing but None

```python
(%seq (write (Iter ->list (Iter new (%py-list-new (list ()))))) (newline))
```
---
    (())

### an empty list iterates to nothing

The empty case and the all-None case are the two that a value-terminated
stepper cannot tell apart. They differ here.

```python
(%seq (write (Iter ->list (Iter new (%py-list-new ())))) (newline))
```
---
    ()

### a dict yields its keys

```python
(%seq (write (Iter ->list (Iter new (%py-dict-new (list (pair "a" 1) (pair "b" 2)))))) (newline))
```
---
    ("a" "b")

## for

### for walks a list containing None

Python's `for` takes the element list directly rather than going through the
iterator, so this was always right — but it is the behaviour the slot has to
agree with, and nothing was pinning it.

```python
(python-run "for x in [None, 1]:\n    print(x)")
```
---
```output
None
1
```

### and one that is only None

```python
(python-run "for x in [None]:\n    print(x)")
```
---
    None
