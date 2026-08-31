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

An indented run is a region the way a bracket is, so it is READ the same way:
PY-NL measures the column, asks the shared `Indent` stack what opened or closed,
and on an open recurses through the engine's reader to collect the block. What
comes back is a nested `(tok-block (tok ...))` rather than INDENT/DEDENT markers
spliced into a flat stream afterwards.

One read returns one token, and a single dedent can close several blocks — so
the surplus is left in a counter that each enclosing block loop collects. That
counter is the whole reason this works with a protocol that cannot return two
things.

### an indented line opens a block

```python
(%seq (write (python-lex "a\n  b")) (newline))
```
---
    (('tok-name "a") ('tok-block (('tok-name "b"))))

### returning to the outer column closes it

```python
(%seq (write (python-lex "a\n  b\nc")) (newline))
```
---
    (('tok-name "a") ('tok-block (('tok-name "b"))) ('tok-name "c"))

### end of input closes what is still open

A block left open at end of input is closed by a DEDENT, as CPython does.

```python
(%seq (write (python-lex "a\n  b")) (newline))
```
---
    (('tok-name "a") ('tok-block (('tok-name "b"))))

### one dedent can close several levels

```python
(%seq (write (python-lex "a\n  b\n    c\nd")) (newline))
```
---
    (('tok-name "a") ('tok-block (('tok-name "b") ('tok-block (('tok-name "c"))))) ('tok-name "d"))

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
    (('tok-name "a") ('tok-block (('tok-name "b") ('tok-newline) ('tok-name "c"))))

### leading blank lines contribute a newline, and nothing else

The blank lines themselves are refused by the analyser and leave no trace. The
one newline is the line-start of `a` itself, which the old pass suppressed
because it emitted line structure only once a line had content. Nothing reads
it — `%py-skip-nl` steps over leading newlines before the first statement — so
what changed is the token stream, not the language.

```python
(%seq (write (python-lex "\n\na")) (newline))
```
---
    (('tok-newline) ('tok-name "a"))

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
    (('tok-name "f") ('tok-group "(" (('tok-number "1"))) ('tok-block (('tok-name "x"))))

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
    (('tok-name "def") ('tok-name "f") ('tok-group "(" ()) ('tok-op ":") ('tok-block (('tok-name "return") ('tok-number "1"))) ('tok-name "f") ('tok-group "(" ()))

## implicit line joining

**This is new behaviour, not a refactor**, and it needs saying because it
arrived on a change whose commit message is about DELETING a hand-written pass.

Python joins lines implicitly inside brackets: an expression may span lines with
no backslash, and the newlines are not line structure. The old flat token stream
emitted a newline token in the middle of a list literal, and the element scanner
rejected it. Now a bracketed run is read through the engine's reader loop as one
token and the newlines inside it never reach the line-structure pass, so this
works — for free, which is exactly why it is pinned here rather than left as
untested behaviour nobody remembers adding.

### a list literal spanning two lines

```python
(python-run "x = [1,\n 2]\nprint(x)")
```
---
    [1, 2]

### a call spanning two lines

```python
(python-run "def f(a, b):\n    return a + b\nprint(f(1,\n  2))")
```
---
    3

### a dict spanning two lines

```python
(python-run "d = {'a': 1,\n 'b': 2}\nprint(d)")
```
---
    {'a': 1, 'b': 2}

### a bracket inside a string is not a delimiter

The group reader never sees these characters as brackets: a string is read as an
ordinary token by PY-SQ/PY-DQ before the group handler asks for the next one. A
reader that scanned characters to a matching closer would need its own quote
tracking to get this right, and would have to keep it in step with the string
types forever.

```python
(python-run "print([']'])")
```
---
    [']']
