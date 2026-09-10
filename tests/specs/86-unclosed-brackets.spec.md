# unclosed brackets

The reader takes a bracket's contents by recursing through the engine's own
reader loop, so a group arrives already nested and there is no closing bracket
for the parser to scan for.  What that leaves is a group which never MET its
closer: one that ran out at EOF, and one ended by the wrong bracket.  Neither
is an error to the lexer, which only nests.  Both are errors here.

The group token carries how it ended -- the closer it met, or nil for EOF --
and `%py-groups-ok` walks the token tree before anything else reads it.

### an unterminated group

```python
(python-run "try:\n    eval('(')\nexcept SyntaxError:\n    print('SyntaxError')\nprint('done')")
```
---
```output
SyntaxError
done
```

### every bracket says which one was never closed

CPython names the opener, and so does this.

```python
(python-run "for s in ['(', '[1', '{1: 2', 'f(1']:\n    try:\n        eval(s)\n        print(repr(s), 'NO ERROR')\n    except SyntaxError as e:\n        print(repr(s), '->', e)")
```
---
```output
'(' -> '(' was never closed
'[1' -> '[' was never closed
'{1: 2' -> '{' was never closed
'f(1' -> '(' was never closed
```

### a closer that does not match its opener

`([1)` is the INNER bracket going wrong: `[` meets `)`.  The outer `(` does run
out at EOF afterwards, but the mismatch is what happened first, and reporting
the contents before the group they sit in is what keeps the two in that order.

```python
(python-run "for s in ['([1)', '(]']:\n    try:\n        eval(s)\n        print(repr(s), 'NO ERROR')\n    except SyntaxError as e:\n        print(repr(s), '->', e)")
```
---
```output
'([1)' -> closing parenthesis ')' does not match opening parenthesis '['
'(]' -> closing parenthesis ']' does not match opening parenthesis '('
```

### a closer with nothing open

The group reader eats the bracket that ends a group, so a close token only
survives into a token list by having had no group to end.

```python
(python-run "try:\n    eval('1)')\nexcept SyntaxError as e:\n    print('->', e)")
```
---
```output
-> unmatched ')'
```

### a statement, not just eval

`eval` comes in through python-parse-expr and a program through python-parse;
both doors check.

```python
(python-run "try:\n    exec('print(1')\nexcept SyntaxError as e:\n    print('->', e)")
```
---
```output
-> '(' was never closed
```

### a group may still span newlines

THE POINT OF THE WHOLE ARRANGEMENT.  A newline inside brackets is not line
structure, it is whitespace -- which is why python/indent.x carries no bracket
depth counter.  These are the cases that must keep working.

```python
(python-run "x = (1 +\n2)\nprint(x)\nxs = [\n 1,\n 2,\n]\nprint(xs)\nd = {\n 'a': 1,\n}\nprint(d)")
```
---
```output
3
[1, 2]
{'a': 1}
```

### a call and a def spanning lines

```python
(python-run "def f(a,\n      b):\n    return a + b\nprint(f(1,\n        2))")
```
---
```output
3
```

### a group inside an indented block still closes

The walk descends into blocks as well as groups, so an unclosed bracket in a
body is found too -- and a closed one there is left alone.

```python
(python-run "def g():\n    return (1 +\n            2)\nprint(g())\ntry:\n    exec('def h():\\n    return (1\\n')\nexcept SyntaxError as e:\n    print('->', e)")
```
---
```output
3
-> '(' was never closed
```

### an f-string field is a door of its own

A field is lexed on its own and goes straight to the expression parser, so it
reaches neither `python-parse` nor `python-parse-expr`; `f"{(1}"` used to come
out as `1`.

`}` IS BOTH A BRACKET AND THE END OF A FIELD.  Which one it is depends on what
is open: in `f"{ {1:2} }"` it closes the dict, and in `f"{(1}"` it is a closer
answering the wrong opener.  A depth count cannot tell those apart -- holding
the openers themselves can, which is what `%py-fs-close` does, and it is why
the wording here is CPython's own rather than "was never closed".

```python
(python-run "for s in ['f\"{(1}\"', 'f\"{[1}\"', 'f\"{(}\"']:\n    try:\n        print(repr(s), '->', repr(eval(s)))\n    except SyntaxError as e:\n        print(repr(s), '->', e)")
```
---
```output
'f"{(1}"' -> closing parenthesis '}' does not match opening parenthesis '('
'f"{[1}"' -> closing parenthesis '}' does not match opening parenthesis '['
'f"{(}"' -> closing parenthesis '}' does not match opening parenthesis '('
```

### a mismatch inside a field, and a closer with nothing open

The mismatch reads exactly as it does outside an f-string -- one wording, one
place it is written.  `unmatched` is the one CPython prefixes with `f-string:`,
and this follows it.

```python
(python-run "for s in ['f\"{(1]}\"', 'f\"{[1)}\"', 'f\"{([1)}\"', 'f\"{1)}\"']:\n    try:\n        print(repr(s), '->', repr(eval(s)))\n    except SyntaxError as e:\n        print(repr(s), '->', e)")
```
---
```output
'f"{(1]}"' -> closing parenthesis ']' does not match opening parenthesis '('
'f"{[1)}"' -> closing parenthesis ')' does not match opening parenthesis '['
'f"{([1)}"' -> closing parenthesis ')' does not match opening parenthesis '['
'f"{1)}"' -> f-string: unmatched ')'
```

### a field that simply runs out still wants its brace

```python
(python-run "for s in ['f\"{(1\"', 'f\"{\"']:\n    try:\n        print(repr(s), '->', repr(eval(s)))\n    except SyntaxError as e:\n        print(repr(s), '->', e)")
```
---
```output
'f"{(1"' -> f-string: expecting '}'
'f"{"' -> f-string: expecting '}'
```

### a bracket inside a string is not a bracket

THE REASON THE SCANNER HAS TO KNOW STRINGS.  Counting brackets without reading
string literals would make `f"{'('}"` -- a field whose value is a parenthesis
-- into an unclosed group, and a `}` inside a literal end the field early.

```python
(python-run "d = {']': 'bracket', '}': 'brace'}
print(f\"{'('}\", f\"{')'}\", f\"{'}'}\", f\"{'[' + ']'}\", f\"{d[']']}\", f\"{d['}']}\")")
```
---
```output
( ) } [] bracket brace
```

### a format spec still finds its colon, and str.format is untouched

The scanner that splits `!conv` and `:spec` off a field is SHARED with
str.format, where a quote is an ordinary character -- the fill in `{0:'>5}`,
part of the key in `{a[it's]}`.  So it counts and does not read strings, which
is why `f"{'a:b'}"` is still refused here where CPython answers `a:b`.  Giving
f-strings that too means a second scanner for the other template as well, and
this change already carries one.

```python
(python-run "print(f\"{1:>{3}}\", f\"{'x'!r}\", \"{0:'>5}\".format(1), \"{a[it's]:>5}\".format(a={\"it's\": 7}))")
```
---
```output
  1 'x' ''''1     7
```

### a closed bracket in a field is left alone

```python
(python-run "print(f\"{(1)}\", f\"{[1, 2]}\", f\"{ {'a': 1}['a'] }\")")
```
---
```output
1 [1, 2] 1
```
