The tokenizer claims `+2` and `-3` as number tokens, because that is the only
way to outscore the sexp integer type. `python/parse.x` splits the sign back off
in operator position. These are the cases where that split has to be right, and
where getting it wrong produces *different arithmetic* rather than an error.

## signed operand position

### a signed literal as the only argument

```python
(python-run "print(-1)")
```
---
    -1

### subtraction followed by a negative literal

```python
(python-run "print(1 - -2)")
```
---
    3

### a signed literal opening an expression

```python
(python-run "print(-1 + 2)")
```
---
    1

### a signed literal after a comma

```python
(python-run "print(1, -2)")
```
---
    1 -2

### a space makes it unary rather than a literal

The tokenizer cannot claim `- 2`, so this goes through the parser's unary path
instead. Both spellings must reach the same answer.

```python
(python-run "print(- 2)")
```
---
    -2

### parenthesised negation

```python
(python-run "print(-(1 + 2))")
```
---
    -3

## signed against precedence

### subtraction stays left-associative

```python
(python-run "print(3 - 1 - 1)")
```
---
    1

### a negative exponent

```python
(python-run "print(2 ** -1)")
```
---
    0.5

### unary minus binds looser than power

Python reads `-2 ** 2` as `-(2 ** 2)` = -4, not `(-2) ** 2` = 4. This is the
case the signed-literal approach is most likely to get wrong, because the
tokenizer hands the parser a single `-2` and the parser has to know not to treat
it as an operand here.

```python
(python-run "print(-2 ** 2)")
```
---
    -4

## signed, not yet reachable

### a negative subscript

Pending: no subscript support in the parser yet.

```python
(python-run "a = [1, 2, 3]\nprint(a[-1])")
```

### a negative argument to a user function

```python
(python-run "def f(x):\n    return x\nprint(f(-1))")
```
---
    -1
