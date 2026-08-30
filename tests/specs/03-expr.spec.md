Expressions, parsed by `python/parse.x` and evaluated through `python/runtime.x`.

The parser emits calls to the runtime rather than to x's operators, because they
are not the same functions: Python's `+` refuses to mix a string and a number
where x's would coerce, and its `/` always produces a float where x's produces
an exact rational.

## expr arithmetic

### addition

```python
(python-run "print(1 + 2)")
```
---
    3

### precedence: product binds tighter than sum

```python
(python-run "print(1 + 2 * 3)")
```
---
    7

### parentheses override it

```python
(python-run "print((1 + 2) * 3)")
```
---
    9

### subtraction is left-associative

```python
(python-run "print(10 - 3 - 2)")
```
---
    5

### unary minus

```python
(python-run "print(-3 + 5)")
```
---
    2

### floor division

```python
(python-run "print(7 // 2)")
```
---
    3

### modulo

```python
(python-run "print(7 % 3)")
```
---
    1

### true division produces a float

`1 / 2` is `0.5` in Python 3, not the exact `1/2` x's own `/` would give. This
is the reason the bundle declares xenon.

```python
(python-run "print(1 / 2)")
```
---
    0.5

## expr power

### power

```python
(python-run "print(2 ** 10)")
```
---
    1024

### power is right-associative

`2**3**2` is `2**(3**2)` = 512, not `(2**3)**2` = 64.

```python
(python-run "print(2 ** 3 ** 2)")
```
---
    512

### an integer is arbitrary-precision

Python 3 has one integer type and it goes all the way up. The literal is read by
x's own reader, so the tower comes for free.

```python
(python-run "print(2 ** 100)")
```
---
    1267650600228229401496703205376

## expr comparison

### equality

```python
(python-run "print(1 == 1)")
```
---
    True

### less than

```python
(python-run "print(1 < 2)")
```
---
    True

### comparison binds looser than arithmetic

```python
(python-run "print(1 + 1 == 2)")
```
---
    True

## expr strings

### a string prints without its quotes

```python
(python-run "print('hi')")
```
---
    hi

### concatenation

```python
(python-run "print('a' + 'b')")
```
---
    ab

## expr print

### several arguments are space-separated

```python
(python-run "print(1, 2, 3)")
```
---
    1 2 3

### no arguments prints an empty line

```python
(python-run "print()")
```
---
```output

```

## expr statements

### assignment then use

```python
(python-run "x = 41\nprint(x + 1)")
```
---
    42

### a name resolves to its value

```python
(python-run "a = 2\nb = 3\nprint(a * b)")
```
---
    6

### several statements run in order

```python
(python-run "print(1)\nprint(2)")
```
---
```output
1
2
```

## float literals

A float literal is not read the way an integer literal is, and the difference is
not cosmetic. Integers are read in `%py-sexp-base`, a `(Base make)` child; float
is a library type registered on whichever base loaded it, so that child has no
float at all. The int type there accepted the `1` of `1.5` as a prefix and the
fraction was dropped without an error — `2 * 1.5` answered `2`. These cases exist
because that failure was silent, and a silent wrong number is the worst kind.

### a bare float literal

```python
(python-run "print(1.5)")
```
---
    1.5

### a float literal in arithmetic

```python
(python-run "print(2 * 1.5)")
```
---
    3.0

### a negative float literal

```python
(python-run "print(-0.25)")
```
---
    -0.25

### a float literal inside a list

```python
(python-run "print([1.5, 2])")
```
---
    [1.5, 2]

### integers are still exact, and still arbitrary-precision

The dot is the only thing that routes a literal to the float reader, so this one
still goes through the integer path — and Python's int does not overflow.

```python
(python-run "print(99999999999 * 99999999999)")
```
---
    9999999999800000000001
