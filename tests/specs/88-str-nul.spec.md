# a str carries a NUL, and prints one

`str` is a list of CODE POINTS (python/str.x), so a zero is a code point like
any other: it has a length, an index, a comparison and a repr. What took
longest was not carrying it but PRINTING it -- see "the writer" in
python/str.x, and `<<NUL>>` in x-lang's `tests/spec-format.md` for how a spec
asserts a byte no expected block can contain.

## the value

### chr(0) is a str of one code point

```python
(python-run "s = chr(0)\nprint(len(s), s == chr(0), repr(s))")
```
---
```output
1 True '\x00'
```

### it survives concatenation, indexing and slicing

```python
(python-run "s = 'a' + chr(0) + 'b'\nprint(len(s), repr(s[1]), repr(s[1:]), repr(s))")
```
---
```output
3 '\x00' '\x00b' 'a\x00b'
```

### a literal names one, and the rest of the string is not lost

The bug this replaces: everything from the zero byte on vanished, and the
value came back two characters short with no error at the point of the
mistake.

```python
(python-run "print(len('a\\x00b'), len('a\\0b'), len('a\\000b'))")
```
---
```output
3 3 3
```

## printing

### print emits the byte itself

```python
(python-run "print('a' + chr(0) + 'b')")
```
---
```output
a<<NUL>>b
```

### a str that is only a NUL

```python
(python-run "print(chr(0))")
```
---
```output
<<NUL>>
```

### the bytes around it are written whole

Two zeros, and the text between and after them -- the case the old truncation
turned into `x`.

```python
(python-run "print('x' + chr(0) + 'y' + chr(0) + 'z')")
```
---
```output
x<<NUL>>y<<NUL>>z
```

### repr escapes it instead, so a repr is still plain text

```python
(python-run "print(repr('a' + chr(0) + 'b'))")
```
---
```output
'a\x00b'
```

## where the limit still is

### a platform string cannot hold one, so the crossings refuse

An attribute name, a module name and the format engines are the platform's
strings, and those end at a zero byte. Each says so rather than truncating.

```python
(python-run "try:\n    '%c' % 0\nexcept ValueError as e:\n    print('pct', e)\ntry:\n    getattr(object(), chr(0))\nexcept ValueError as e:\n    print('attr', e)")
```
---
```output
pct a NUL byte is not representable here
attr a NUL byte is not representable here
```
