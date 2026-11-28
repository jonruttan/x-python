# re: regular expressions

`stdlib/re.py`, on the matcher in `lib/python/_sre.x`. Each expected output
is a python3.15 run of the same program.

### match, search, findall, sub and split, with spans and empty matches

```python
(python-run "import re\nprint(re.match(\"a\", \"abc\"))\nprint(re.search(r\"\\d+\", \"ab 123 cd\"))\nm = re.match(r\"([0-9]*)(([a-z]*)([0-9]*))\", \"1234❤567\")\nprint(m.span(0), m.span(1), m.span(2), m.span(3), m.span(4))\nprint(re.findall(r\"\\w+\", \"hello, wide world\"))\nprint(re.sub(r\"(\\w+)@(\\w+)\", r\"\\2 at \\1\", \"jon@home and amy@work\"))\nprint(re.split(r\"[,;]\\s*\", \"a, b;c,  d\"))\nprint(re.fullmatch(r\"[A-Z][A-Z][A-Z][A-Z][A-Z]\", \"ABCDE\"), re.compile(r\"[A-Z]{5}\").match(\"ABCD\"))\n")
```
---
```output
<re.Match object; span=(0, 1), match='a'>
<re.Match object; span=(3, 6), match='123'>
(0, 4) (0, 4) (4, 4) (4, 4) (4, 4)
['hello', 'wide', 'world']
home at jon and work at amy
['a', 'b', 'c', 'd']
<re.Match object; span=(0, 5), match='ABCDE'> None
```

### groups by name and number, lookaround, conditionals, possessive and atomic repeats, backreferences

```python
(python-run "import re\nprint(re.findall(\"a*?\", \"aa\"), re.sub(\"x*\", \"-\", \"abxd\"), re.split(\"x*\", \"axbc\"))\np = re.compile(r\"(?P<key>\\w+)=(?P<val>\\d+)\", re.I)\nprint(p, p.groups, p.groupindex)\nm = p.search(\"  Width=640 \")\nprint(m.groupdict(), m.lastgroup, m.lastindex, m[\"key\"], m.group(1, 2), m.regs)\nprint(re.match(r\"(?i)hello\", \"HeLLo\"), re.findall(r\"^\\w\", \"ab\\ncd\", re.M))\nprint(re.match(r\"(a|ab)(c|bcd)(d*)\", \"abcd\").groups())\nprint(re.match(r\"(?<=a)b\", \"ab\"), re.search(r\"(?<=a)b\", \"ab\"), re.search(r\"(?<!a)b\", \"ab cb\"))\nprint(re.match(r\"(a)?(?(1)b|c)\", \"c\"), re.match(r\"(a)?(?(1)b|c)\", \"ab\"))\nprint(re.match(r\"(?>a+)a\", \"aaa\"), re.match(r\"a++a\", \"aaa\"), re.match(r\"a+a\", \"aaa\"))\nprint(re.match(r\"(\\w)\\1\", \"aa\"), re.match(r\"(?P<x>\\w)(?P=x)\", \"bb\"), re.match(r\"(?i)(a)\\1\", \"aA\"))\n")
```
---
```output
['', 'a', '', 'a', ''] -a-b--d- ['', 'a', '', 'b', 'c', '']
re.compile('(?P<key>\\w+)=(?P<val>\\d+)', re.IGNORECASE) 2 {'key': 1, 'val': 2}
{'key': 'Width', 'val': '640'} val 2 Width ('Width', '640') ((2, 11), (2, 7), (8, 11))
<re.Match object; span=(0, 5), match='HeLLo'> ['a', 'c']
('a', 'bcd', '')
None <re.Match object; span=(1, 2), match='b'> <re.Match object; span=(4, 5), match='b'>
<re.Match object; span=(0, 1), match='c'> <re.Match object; span=(0, 2), match='ab'>
None None <re.Match object; span=(0, 3), match='aaa'>
<re.Match object; span=(0, 2), match='aa'> <re.Match object; span=(0, 2), match='bb'> <re.Match object; span=(0, 2), match='aA'>
```

### escape, bytes patterns, flags, compile errors, callable replacements, repeats, anchors, classes and verbose mode

```python
(python-run "import re\nprint(re.escape(\"a.b*c?\"), re.sub(r\"\\s+\", \" \", \"a  b\\t\\nc\"), re.subn(\"a\", \"b\", \"aaa\", count=2))\nprint(re.findall(rb\"\\d+\", b\"a1b22\"), re.sub(b\"a\", b\"b\", b\"aaa\"))\nprint(re.compile(\"a\", re.I | re.M), re.I | re.M, re.compile(b\"x\"))\nfor bad in [\"(\", \")\", \"[a\", \"*\", \"a**\", r\"\\q\", \"(?P<1>a)\", \"a{3,2}\"]:\n    try:\n        re.compile(bad)\n    except re.error as e:\n        print(\"error:\", e)\nprint(re.sub(r\"(\\d)\", lambda m: str(int(m.group(1)) * 2), \"a1b2c3\"))\nprint(list(m.span() for m in re.finditer(r\"\\b\\w\", \"one two  three\")))\nprint(re.match(r\"(ab)*\", \"ababab\").group(0, 1), re.match(r\"(?:a|b)*c\", \"abbac\"))\nprint(re.match(r\"x{2,3}\", \"xxxx\"), re.match(r\"x{2,}?\", \"xxxx\"), re.match(r\"a{,2}\", \"aaa\"), re.match(r\"a{x\", \"a{x\"))\nprint(re.search(r\"$\", \"ab\\n\").span(), re.search(r\"\\Z\", \"ab\\n\").span(), re.match(r\".*\", \"a\\nb\"), re.match(r\"(?s).*\", \"a\\nb\"))\nprint(re.search(r\"[^a-c]+\", \"abcdef\"), re.search(r\"[\\d.]+\", \"v1.25x\"), re.search(r\"[]a]+\", \"x]a]\"))\nprint(re.match(r\"(?x) a  b # comment\\n c\", \"abc\"), re.match(\"(?i)[a-z]+\", \"ABC\"))\n")
```
---
```output
a\.b\*c\? a b c ('bba', 2)
[b'1', b'22'] b'bbb'
re.compile('a', re.IGNORECASE|re.MULTILINE) re.IGNORECASE|re.MULTILINE re.compile(b'x')
error: missing ), unterminated subpattern at position 0
error: unbalanced parenthesis at position 0
error: unterminated character set at position 0
error: nothing to repeat at position 0
error: multiple repeat at position 2
error: bad escape \q at position 0
error: bad character in group name '1' at position 4
error: min repeat greater than max repeat at position 2
a2b4c6
[(0, 1), (4, 5), (9, 10)]
('ababab', 'ab') <re.Match object; span=(0, 5), match='abbac'>
<re.Match object; span=(0, 3), match='xxx'> <re.Match object; span=(0, 2), match='xx'> <re.Match object; span=(0, 2), match='aa'> <re.Match object; span=(0, 3), match='a{x'>
(2, 2) (3, 3) <re.Match object; span=(0, 1), match='a'> <re.Match object; span=(0, 3), match='a\nb'>
<re.Match object; span=(3, 6), match='def'> <re.Match object; span=(1, 5), match='1.25'> <re.Match object; span=(1, 4), match=']a]'>
<re.Match object; span=(0, 2), match='ab'> <re.Match object; span=(0, 3), match='ABC'>
```
