Python's line structure: NEWLINE, INDENT and DEDENT, produced by
`python/indent.x` driving `x/reader/indent`'s stack (x-lang#520).

The stack is not here. This file owns only what `Indent` is deliberately silent
about: bracket depth suppressing newlines, and blank or comment-only lines
being transparent.

## lines flat

### a single line has no line structure at all

A module's first logical line is at column 0 and opens nothing.

```python
(%seq (write (python-lex "a")) (newline))
```
---
    (('tok-name "a"))

### two lines at the same level

```python
(%seq (write (python-lex "a\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-name "b"))

## lines indentation

### an indented line opens a block

```python
(%seq (write (python-lex "a\n  b")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-indent) ('tok-name "b") ('tok-dedent))

### returning to the outer column closes it

```python
(%seq (write (python-lex "a\n  b\nc")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-indent) ('tok-name "b") ('tok-newline) ('tok-dedent) ('tok-name "c"))

### end of input closes what is still open

A block left open at end of input is closed by a DEDENT, as CPython does.

```python
(%seq (write (python-lex "a\n  b")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-indent) ('tok-name "b") ('tok-dedent))

### one dedent can close several levels

```python
(%seq (write (python-lex "a\n  b\n    c\nd")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-indent) ('tok-name "b") ('tok-newline) ('tok-indent) ('tok-name "c") ('tok-newline) ('tok-dedent) ('tok-dedent) ('tok-name "d"))

## lines blank and comment

### a blank line is transparent

```python
(%seq (write (python-lex "a\n\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-name "b"))

### a comment-only line is transparent

Comments are discarded by the tokenizer, so this arrives as two adjacent
newlines — indistinguishable from a blank line, which is exactly how Python
treats it.

```python
(%seq (write (python-lex "a\n# note\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-name "b"))

### a blank line does not close a block

```python
(%seq (write (python-lex "a\n  b\n\n  c")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-indent) ('tok-name "b") ('tok-newline) ('tok-name "c") ('tok-dedent))

### leading blank lines contribute nothing

```python
(%seq (write (python-lex "\n\na")) (newline))
```
---
    (('tok-name "a"))

## lines brackets

A newline inside brackets is not line structure — it is whitespace. This pass
used to carry a bracket DEPTH COUNTER to know when it was inside them.

It does not any more. python/tokens.x reads a bracketed run through the engine's
own reader loop, so it arrives as ONE token with its contents nested inside, and
a newline within it never reaches this pass at all. These cases are the same
cases; what changed is that the nesting is now the shape rather than something
rediscovered by counting.

### a newline inside parens is not line structure

```python
(%seq (write (python-lex "f(\n  1\n)")) (newline))
```
---
    (('tok-name "f") ('tok-group "(" (('tok-number "1"))))

### a continuation line opens no block

The column of a continuation line means nothing to the grammar, so nothing
reaches the indenter.

```python
(%seq (write (python-lex "a = [\n      1,\n  2]\nb")) (newline))
```
---
    (('tok-name "a") ('tok-op "=") ('tok-group "[" (('tok-number "1") ('tok-op ",") ('tok-number "2"))) ('tok-newline) ('tok-name "b"))

### line structure resumes after the brackets close

```python
(%seq (write (python-lex "f(\n1)\n  x")) (newline))
```
---
    (('tok-name "f") ('tok-group "(" (('tok-number "1"))) ('tok-newline) ('tok-indent) ('tok-name "x") ('tok-dedent))

## lines errors

### a dedent matching no open level raises

Python's `IndentationError`. Logo opens a block at the odd column and x-sweet
unwinds past it; this is the one place the three surfaces genuinely disagree,
and `(Indent make)`'s default is Python's answer.

```python
(%seq (write (python-lex "a\n    b\n  c")) (newline))
```
---
    Error: #<err:indent unindent does not match any outer indentation level>

## lines together

### a def with a body

```python
(%seq (write (python-lex "def f():\n    return 1\nf()")) (newline))
```
---
    (('tok-name "def") ('tok-name "f") ('tok-group "(" ()) ('tok-op ":") ('tok-newline) ('tok-indent) ('tok-name "return") ('tok-number "1") ('tok-newline) ('tok-dedent) ('tok-name "f") ('tok-group "(" ()))
