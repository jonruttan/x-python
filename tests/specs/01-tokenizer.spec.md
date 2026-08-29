Python's lexical layer, on a base isolated from the sexp reader's types
(`python/tokens.x`). Keywords are not distinguished here — `if` is a name to the
tokenizer and a keyword to the parser, which is where the difference is used.

Every case ends with `(newline)`. Without it the runner has no line boundary
between cases and attributes one case's output to another, which reads as a
tokenizer bug and is not one.

## tokenizer names

### a bare identifier

```python
(%seq (write (python-tokenize "x")) (newline))
```
---
    (('tok-name "x"))

### digits and underscores continue a name

```python
(%seq (write (python-tokenize "foo_bar2")) (newline))
```
---
    (('tok-name "foo_bar2"))

### a leading underscore starts one

```python
(%seq (write (python-tokenize "_x")) (newline))
```
---
    (('tok-name "_x"))

### a keyword is just a name here

```python
(%seq (write (python-tokenize "if")) (newline))
```
---
    (('tok-name "if"))

## tokenizer whitespace and comments

### spaces separate and do not survive

```python
(%seq (write (python-tokenize "a b")) (newline))
```
---
    (('tok-name "a") ('tok-name "b"))

### a comment runs to end of line and is discarded

```python
(%seq (write (python-tokenize "a # trailing")) (newline))
```
---
    (('tok-name "a"))

### a comment does not swallow its newline

The newline is line structure; a comment sitting on a line must not eat it. It
carries the column of the line it opens, which is what python/indent.x reads.

```python
(%seq (write (python-tokenize "a # c\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline 0) ('tok-name "b"))

## tokenizer numbers

### an integer

```python
(%seq (write (python-tokenize "42")) (newline))
```
---
    (('tok-number "42"))

### a float

```python
(%seq (write (python-tokenize "3.5")) (newline))
```
---
    (('tok-number "3.5"))

### the value is source text, not a number

Python's int is arbitrary-precision and its float IEEE 754; which one a literal
denotes belongs to the evaluator, not here.

```python
(%seq (write (python-tokenize "007")) (newline))
```
---
    (('tok-number "007"))

## tokenizer strings

### a single-quoted string

```python
(%seq (write (python-tokenize "'hi'")) (newline))
```
---
    (('tok-string "hi"))

### a double-quoted string

```python
(%seq (write (python-tokenize "\"hi\"")) (newline))
```
---
    (('tok-string "hi"))

### an empty string

```python
(%seq (write (python-tokenize "''")) (newline))
```
---
    (('tok-string ""))

### a one-character string

x-ash's README records this as the case its string reader loses: `''` tokenizes
and `'a'` drops the accumulator. Reading the lexeme from the buffer in `read`,
rather than accumulating during `analyse`, is why this one holds.

```python
(%seq (write (python-tokenize "'a'")) (newline))
```
---
    (('tok-string "a"))

### an escaped quote does not end the string

```python
(%seq (write (python-tokenize "'it\\'s'")) (newline))
```
---
    (('tok-string "it's"))

### a newline escape becomes one character, not two

Asserted by length rather than by rendering, so the case does not also depend
on how the writer spells a control character.

```python
(%seq (write (Str8 length (first (rest (first (python-tokenize "'a\\nb'")))))) (newline))
```
---
    3

## tokenizer operators

### a single-character operator

```python
(%seq (write (python-tokenize "+")) (newline))
```
---
    (('tok-op "+"))

### floor division is one token, not two divisions

The case a single-character operator type gets silently wrong: `a//b` would read
as two divisions, which is not an error — it is different arithmetic.

```python
(%seq (write (python-tokenize "//")) (newline))
```
---
    (('tok-op "//"))

### power is one token

```python
(%seq (write (python-tokenize "**")) (newline))
```
---
    (('tok-op "**"))

### equality against assignment

```python
(%seq (write (python-tokenize "==")) (newline))
```
---
    (('tok-op "=="))

### a lone equals stays lone

```python
(%seq (write (python-tokenize "=")) (newline))
```
---
    (('tok-op "="))

### an unpaired operator gives the next character back

```python
(%seq (write (python-tokenize "+x")) (newline))
```
---
    (('tok-op "+") ('tok-name "x"))

## tokenizer together

### a whole assignment

```python
(%seq (write (python-tokenize "x = 1 + 2")) (newline))
```
---
    (('tok-name "x") ('tok-op "=") ('tok-number "1") ('tok-op "+") ('tok-number "2"))

### a call with a string argument

```python
(%seq (write (python-tokenize "print('hi')")) (newline))
```
---
    (('tok-name "print") ('tok-op "(") ('tok-string "hi") ('tok-op ")"))

### two lines

```python
(%seq (write (python-tokenize "a\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline 0) ('tok-name "b"))

### a def line

```python
(%seq (write (python-tokenize "def f(x):")) (newline))
```
---
    (('tok-name "def") ('tok-name "f") ('tok-op "(") ('tok-name "x") ('tok-op ")") ('tok-op ":"))
