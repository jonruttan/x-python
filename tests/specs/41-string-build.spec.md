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

### startswith and endswith windows, strip identity, and %c past U+10FFFF

```python
(python-run "print(\"1foobar\".startswith(\"foo\", 1, 3), \"foobar\".startswith(\"foo\", None, 2), \"1foobar\".startswith(\"foo\", 1, 4))\nprint(\"1foobar\".startswith(\"o\", 5, 4), \"abc\".startswith(\"\", 3, 2), \"abc\".startswith(\"\", 1, 2), \"abc\".endswith(\"\", 3, 2))\nprint(\"foobar\".startswith((\"x\", \"fo\"), 0, 2), b\"1foobar\".startswith(b\"foo\", 1, 3), b\"1foobar\".startswith(b\"foo\", 1, 4))\ns = \"abc\"\nprint(s.strip() is s, s.lstrip(\"x\") is s, s.rstrip() is s, s.strip(\"a\") is s, s.strip(\"a\"))\nprint(\"%c\" % 0x10FFFF == chr(0x10FFFF), \"{:c}\".format(0x3BC), \"%c%c\" % (65, 0x4E00))\nfor f in (lambda: \"%c\" % 0x110000, lambda: \"{:c}\".format(0x200000), lambda: \"%c\" % -1, lambda: chr(0x110000)):\n    try:\n        f()\n    except (OverflowError, ValueError) as e:\n        print(type(e).__name__, e)\nprint(b\"abc\".startswith(b\"\", 3, 2), b\"abc\".endswith(b\"\", 3, 2), b\"abc\".endswith(b\"c\", 0, 3), b\"abc\".endswith(b\"c\", 0, 2))\ntry:\n    \"abc\".startswith(5, 3, 2)\nexcept TypeError:\n    print(\"TypeError\")")
```
---
```output
False False True
False False True False
True False True
True True True False bc
True μ A一
OverflowError %c arg not in range(0x110000)
OverflowError %c arg not in range(0x110000)
OverflowError %c arg not in range(0x110000)
ValueError chr() arg not in range(0x110000)
False False True False
TypeError
```
