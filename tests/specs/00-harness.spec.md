Everything in this file is about the *pipeline*, not about Python. It exists so
that a red conformance scoreboard can be read as "the language is not written
yet" rather than "the harness is broken" — two states that look identical from a
failure count, and only one of which is progress.

## harness

### the bundle loads and a program runs

```python
(python-run "print(1)")
```
---
    1

### a statement with no output produces none

```python
(python-run "x = 5\nprint(x)")
```
---
    5

### a multi-line program arrives intact

The conformance generator emits whole programs with `\n` escapes — indentation
included, since indentation is the grammar. This is the shape it emits; if the
reader ever stops accepting it, 657 generated specs stop meaning anything.

```python
(python-run "a = 1\nb = 2\nprint(a + b)")
```
---
    3

### the version is declared

A bare `write` leaves no newline and the runner sees the next case glued to
this one; every spec here ends its output the way `print` does.

```python
(%seq (write python-version) (newline))
```
---
    "0.0.1"
