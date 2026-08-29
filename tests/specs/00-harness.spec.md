Everything in this file is about the *pipeline*, not about Python.  It exists
so that a red conformance scoreboard can be read as "the language is not
written yet" rather than "the harness is broken" -- two states that look
identical from a failure count, and only one of which is progress.

## harness

### the bundle loads and python-run is reachable

```python
(python-run "print(1)")
```
---
    #<python: not implemented>

### python-run returns nil, so the printer stays quiet

A Python statement has no value to show.  If this ever prints a second line,
the REPL printer has started narrating over programs that write their own
output, and every conformance case gains a trailing line.

```python
(python-run "pass")
```
---
    #<python: not implemented>

### a multi-line program arrives as one string

The conformance generator emits whole programs with `\n` escapes -- indentation
included, since indentation is the grammar.  This is the shape it emits; if the
reader ever stops accepting it, 682 generated specs stop meaning anything.

```python
(python-run "def f():\n    return 1\nprint(f())\n")
```
---
    #<python: not implemented>

### the version is declared

A bare `write` leaves no newline and the runner sees the next case glued to
this one; every spec here ends its output the way `python-run` does.

```python
(%seq (write python-version) (newline))
```
---
    "0.0.1"
