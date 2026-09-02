Strings, the rest of the surface (`python/tokens.x`, `python/runtime.x`):
splitting, stripping, joining, padding, replacing; str.method on the
class; SystemExit ending a program quietly; hex, octal and binary literals.
Every expectation is a real CPython output.  Split across files because a
string-heavy batch accumulates past the object ceiling in one process.

## string build

### strip family

```python
(python-run "print(repr(\"\".strip()), repr(\" \\t\\n\\r\\v\\f\".strip()), repr(\" T E S T\".strip()), \"abcabc\".strip(\"ce\"), \"aaa\".strip(\"b\"), \"abc  efg \".strip(\"g a\"))\nprint(repr('   spacious   '.lstrip()), 'www.example.com'.lstrip('cmowz.'), repr('   spacious   '.rstrip()), 'mississippi'.rstrip('ipz'))")
```
---
```output
'' '' 'T E S T' abcab aaa bc  ef
'spacious   ' example.com '   spacious' mississ
```

### split and rsplit, the remainder verbatim

```python
(python-run "print(\"a b\".split(), \"   a   b    \".split(None), \"   a   b    \".split(None, 1), \"   a   b  c  \".split(None, 1), \"   a   b  c  \".split(None, 0), \"   a   b  c  \".split(None, -1))\nprint(\"foo\\n\\t\\x07\\v\\nbar\".split(), \"foo\\nbar\\n\".split(), \"a,b,,c\".split(\",\"), \"a,b,,c\".split(\",\", 1), \"a b c d\".rsplit(None, 1), \"a,b,c\".rsplit(\",\", 1))\ntry:\n    \"abc\".split(\"\")\nexcept ValueError:\n    print(\"ValueError\")")
```
---
```output
['a', 'b'] ['a', 'b'] ['a', 'b    '] ['a', 'b  c  '] ['a   b  c  '] ['a', 'b', 'c']
['foo', '\x07', 'bar'] ['foo', 'bar'] ['a', 'b', '', 'c'] ['a', 'b,,c'] ['a b c', 'd'] ['a,b', 'c']
ValueError
```

### partition, center, replace, join, splitlines

```python
(python-run "print(\"asdf\".partition(\"g\"), \"asdf\".partition(\"a\"), \"asdf\".partition(\"s\"), \"asdf\".partition(\"asdf\"), \"asdf\".rpartition(\"s\"), \"asdf\".rpartition(\"z\"))\nprint(repr(\"foo\".center(0)), repr(\"foo\".center(4)), repr(\"foo\".center(6)), repr(\"foo\".ljust(5)), repr(\"foo\".rjust(5)), repr(\"foo\".center(5, \"*\")))\nprint(\"aaa\".replace(\"a\", \"b\", 2), \"aaa\".replace(\"a\", \"b\"), \"-\".join([\"a\", \"b\"]), \"x\".join([]), \"a\\nb\\r\\nc\".splitlines(), \"a\\nb\".splitlines(True))")
```
---
```output
('asdf', '', '') ('', 'a', 'sdf') ('a', 's', 'df') ('', 'asdf', '') ('a', 's', 'df') ('', '', 'asdf')
'foo' 'foo ' ' foo  ' 'foo  ' '  foo' '*foo*'
bba bbb a-b  ['a', 'b', 'c'] ['a\n', 'b']
```

### str.method on the class, and a missing one

```python
(python-run "print(str.upper(\"abc\"), str.count(\"aaa\", \"a\"))\ntry:\n    str.nosuch\nexcept AttributeError:\n    print(\"AttributeError\")")
```
---
```output
ABC 3
AttributeError
```

### hex, octal, binary literals

```python
(python-run "print(0x80, 0xff, 0o17, 0b101, 0x1_F, 0, 00)")
```
---
    128 255 15 5 31 0 0

### SystemExit ends the program quietly

```python
(python-run "print(\"before\")\nraise SystemExit\nprint(\"after\")")
```
---
    before
