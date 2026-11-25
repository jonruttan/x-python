# textwrap: wrapping and filling text

`stdlib/textwrap.py`. Each expected output is a python3.14 run of the same
program.

### wrap and fill break at spaces and hyphens, as their options say

```python
(python-run "import textwrap\ntext = (\"The quick brown fox jumps over the lazy dog. A well-known \"\n        \"e-mail from a co-op went out.  Supercalifragilisticexpialidocious!\")\nfor line in textwrap.wrap(text, width=24):\n    print(\"|\" + line + \"|\")\nprint(textwrap.fill(text, width=30, initial_indent=\"* \", subsequent_indent=\"  \"))\nprint(textwrap.wrap(\"anti-dis-establish-ment\", width=10))\nprint(textwrap.wrap(\"anti-dis-establish-ment\", width=10, break_on_hyphens=False))\nprint(textwrap.wrap(\"abcdefghijkl mn\", width=5, break_long_words=False))\nprint(textwrap.wrap(\"one\\ttwo\\nthree\", width=40, tabsize=4))\nprint(textwrap.wrap(\"Hi. There. ok\", width=40, fix_sentence_endings=True))\n")
```
---
```output
|The quick brown fox|
|jumps over the lazy dog.|
|A well-known e-mail from|
|a co-op went out.  Super|
|califragilisticexpialido|
|cious!|
* The quick brown fox jumps
  over the lazy dog. A well-
  known e-mail from a co-op
  went out.  Supercalifragilis
  ticexpialidocious!
['anti-dis-', 'establish-', 'ment']
['anti-dis-e', 'stablish-m', 'ent']
['abcdefghijkl', 'mn']
['one two three']
['Hi.  There.  ok']
```

### shorten and max_lines end a cut text with the placeholder

```python
(python-run "import textwrap\nprint(textwrap.shorten(\"Hello  world!   How are you?\", width=12))\nprint(textwrap.shorten(\"Hello world\", width=11))\nprint(textwrap.shorten(\"Hello world, how are you\", width=15, placeholder=\"...\"))\nw = textwrap.TextWrapper(width=20, max_lines=2, placeholder=\" (more)\")\nprint(w.wrap(\"one two three four five six seven eight nine ten\"))\nw.width = 12\nprint(w.fill(\"one two three four five six\"))\ntry:\n    textwrap.wrap(\"x\", width=0)\nexcept ValueError as e:\n    print(\"ValueError\", e)\ntry:\n    textwrap.shorten(\"some words here\", width=3)\nexcept ValueError as e:\n    print(\"ValueError\", e)\n")
```
---
```output
Hello [...]
Hello world
Hello world,...
['one two three four', 'five six (more)']
one two
three (more)
ValueError invalid width 0 (must be > 0)
ValueError placeholder too large for max width
```

### dedent and indent

```python
(python-run "import textwrap\ndoc = \"\"\"\n    def f():\n        return 1\n\n      odd\n    \"\"\"\nprint(repr(textwrap.dedent(doc)))\nprint(repr(textwrap.dedent(\"  a\\n\\tb\")), repr(textwrap.dedent(\"   \\n  x\\n  y\")))\nprint(textwrap.indent(\"one\\n\\ntwo\\n\", \": \"), end=\"\")\nprint(textwrap.indent(\"one\\n\\ntwo\\n\", \"+ \", lambda line: True), end=\"\")\nprint(repr(textwrap.indent(\"a\\r\\nb\", \"-\")))\ntry:\n    textwrap.dedent(5)\nexcept TypeError as e:\n    print(\"TypeError\", e)\n")
```
---
```output
'\ndef f():\n    return 1\n\n  odd\n'
'  a\n\tb' '\nx\ny'
: one

: two
+ one
+ 
+ two
'-a\r\n-b'
TypeError expected str object, not 'int'
```

### str.expandtabs and str.isdecimal, which TextWrapper calls

```python
(python-run "print(repr(\"a\\tbc\\tdef\\tg\".expandtabs()), repr(\"a\\tb\".expandtabs(4)))\nprint(repr(\"ab\\n\\tc\\r\\td\".expandtabs(tabsize=2)), repr(\"x\\ty\".expandtabs(0)))\nprint(\"2024\".isdecimal(), \"\".isdecimal(), \"1a\".isdecimal(), \"_\".isdecimal())\n")
```
---
```output
'a       bc      def     g' 'a   b'
'ab\n  c\r  d' 'xy'
True False False False
```

### a def takes more than 8 defaults, as TextWrapper's does

```python
(python-run "def many(a, b=1, c=2, d=3, e=4, f=5, g=6, h=7, i=8, j=9, *, k=10, m=11, n=12):\n    return [a, b, c, d, e, f, g, h, i, j, k, m, n]\nprint(many(0))\nprint(many(0, 9, j=99, n=-1))\n")
```
---
```output
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
[0, 9, 2, 3, 4, 5, 6, 7, 8, 99, 10, 11, -1]
```
