Python's lexical layer, on a base isolated from the sexp reader's types
(`python/tokens.x`). A keyword is its own token kind: PY-KEYWORD, an analyser
registered ahead of PY-NAME, decides `if` per character, and the parser asks
the tag rather than comparing the name against a list.

Every case ends with `(newline)`. Without it the runner has no line boundary
between cases and attributes one case's output to another, which reads as a
tokenizer bug and is not one.

## tokenizer names

### a bare identifier

```python
(%seq (write (python-tokenize "x")) (newline))
```
---
    (('tok-name "x"))

### digits and underscores continue a name

```python
(%seq (write (python-tokenize "foo_bar2")) (newline))
```
---
    (('tok-name "foo_bar2"))

### a leading underscore starts one

```python
(%seq (write (python-tokenize "_x")) (newline))
```
---
    (('tok-name "_x"))

### a keyword is its own token kind

```python
(%seq (write (python-tokenize "if")) (newline))
```
---
    (('tok-kw "if"))

## tokenizer keywords

The analyser decides these per character, from a trie generated out of
`%py-keywords` (`python/tokens.x`). The list is CPython 3.14's `keyword.kwlist`
less `True`, `False` and `None`, which this bundle carries as builtins.

### every keyword, in the list's own order

```python
(%seq (write (python-tokenize "if elif else while def return pass and or not in is for break continue class import from as try except finally raise with lambda global nonlocal assert del yield async await")) (newline))
```
---
    (('tok-kw "if") ('tok-kw "elif") ('tok-kw "else") ('tok-kw "while") ('tok-kw "def") ('tok-kw "return") ('tok-kw "pass") ('tok-kw "and") ('tok-kw "or") ('tok-kw "not") ('tok-kw "in") ('tok-kw "is") ('tok-kw "for") ('tok-kw "break") ('tok-kw "continue") ('tok-kw "class") ('tok-kw "import") ('tok-kw "from") ('tok-kw "as") ('tok-kw "try") ('tok-kw "except") ('tok-kw "finally") ('tok-kw "raise") ('tok-kw "with") ('tok-kw "lambda") ('tok-kw "global") ('tok-kw "nonlocal") ('tok-kw "assert") ('tok-kw "del") ('tok-kw "yield") ('tok-kw "async") ('tok-kw "await"))

### a keyword followed by a name character is a name

The terminal state rejects when a name character follows, and PY-NAME's
longer match takes the token. Case matters: `If` is a name.

```python
(%seq (write (python-tokenize "ifx if_ if1 If elsewhere")) (newline))
```
---
    (('tok-name "ifx") ('tok-name "if_") ('tok-name "if1") ('tok-name "If") ('tok-name "elsewhere"))

### a keyword that prefixes another: as, assert, async

`as` is the one terminal with children; a node tries its children before it
accepts, and a prefix that is not itself a keyword is a name.

```python
(%seq (write (python-tokenize "as assert async await ass asx awai")) (newline))
```
---
    (('tok-kw "as") ('tok-kw "assert") ('tok-kw "async") ('tok-kw "await") ('tok-name "ass") ('tok-name "asx") ('tok-name "awai"))

### a keyword against punctuation and at the ends

```python
(%seq (write (python-tokenize "if(x)or not[y]")) (newline))
```
---
    (('tok-kw "if") ('tok-group "(" (('tok-name "x")) ")") ('tok-kw "or") ('tok-kw "not") ('tok-group "[" (('tok-name "y")) "]"))

### True, False and None are builtins here, not keywords

```python
(%seq (write (python-tokenize "True False None match case type _")) (newline))
```
---
    (('tok-name "True") ('tok-name "False") ('tok-name "None") ('tok-name "match") ('tok-name "case") ('tok-name "type") ('tok-name "_"))

## tokenizer whitespace and comments

### spaces separate and do not survive

```python
(%seq (write (python-tokenize "a b")) (newline))
```
---
    (('tok-name "a") ('tok-name "b"))

### a comment runs to end of line and is discarded

```python
(%seq (write (python-tokenize "a # trailing")) (newline))
```
---
    (('tok-name "a"))

### a comment does not swallow its newline

The newline is line structure; a comment sitting on a line must not eat it. It
carries the column of the line it opens, which is what python/indent.x reads.

```python
(%seq (write (python-tokenize "a # c\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-name "b"))

## tokenizer numbers

### an integer

```python
(%seq (write (python-tokenize "42")) (newline))
```
---
    (('tok-number "42" 1))

### a float

```python
(%seq (write (python-tokenize "3.5")) (newline))
```
---
    (('tok-number "3.5" 2))

### the value is source text, not a number

Python's int is arbitrary-precision and its float IEEE 754; which one a literal
denotes belongs to the evaluator, not here.

```python
(%seq (write (python-tokenize "007")) (newline))
```
---
    (('tok-number "007" 1))

## tokenizer strings

A string token's value is a list of UTF-8 BYTES, not a platform string, and
that is what these cases assert. It has to be: a platform string ends at its
first NUL, so a token holding one could not carry `'a\x00b'` -- the literal
would arrive two characters short with no error where the mistake was made.
The parser decodes the bytes to code points once, at parse time, and `str` is
that code point list (python/str.x).

### a single-quoted string

```python
(%seq (write (python-tokenize "'hi'")) (newline))
```
---
    (('tok-string (104 105)))

### a double-quoted string

```python
(%seq (write (python-tokenize "\"hi\"")) (newline))
```
---
    (('tok-string (104 105)))

### an empty string

```python
(%seq (write (python-tokenize "''")) (newline))
```
---
    (('tok-string ()))

### a one-character string

x-ash's README records this as the case its string reader loses: `''` tokenizes
and `'a'` drops the accumulator. Reading the lexeme from the buffer in `read`,
rather than accumulating during `analyse`, is why this one holds.

```python
(%seq (write (python-tokenize "'a'")) (newline))
```
---
    (('tok-string (97)))

### an escaped quote does not end the string

```python
(%seq (write (python-tokenize "'it\\'s'")) (newline))
```
---
    (('tok-string (105 116 39 115)))

### a newline escape becomes one character, not two

Asserted by length rather than by rendering, so the case does not also depend
on how the writer spells a control character.

```python
(%seq (write (List length (first (rest (first (python-tokenize "'a\\nb'")))))) (newline))
```
---
    3

## tokenizer operators

### a single-character operator

```python
(%seq (write (python-tokenize "+")) (newline))
```
---
    (('tok-op "+"))

### floor division is one token, not two divisions

The case a single-character operator type gets silently wrong: `a//b` would read
as two divisions, which is not an error — it is different arithmetic.

```python
(%seq (write (python-tokenize "//")) (newline))
```
---
    (('tok-op "//"))

### power is one token

```python
(%seq (write (python-tokenize "**")) (newline))
```
---
    (('tok-op "**"))

### equality against assignment

```python
(%seq (write (python-tokenize "==")) (newline))
```
---
    (('tok-op "=="))

### a lone equals stays lone

```python
(%seq (write (python-tokenize "=")) (newline))
```
---
    (('tok-op "="))

### an unpaired operator gives the next character back

```python
(%seq (write (python-tokenize "+x")) (newline))
```
---
    (('tok-op "+") ('tok-name "x"))

### a three-character operator is one token

`//=` `**=` `<<=` `>>=` are the augmented forms of the doubled operators, so
the match runs one character past the pair.

```python
(%seq (write (python-tokenize "//= **= <<= >>=")) (newline))
```
---
    (('tok-op "//=") ('tok-op "**=") ('tok-op "<<=") ('tok-op ">>="))

### a pair that could triple still ends without the third

The mirror of the case above it: the third character is given back the way the
second is, so `//` before a name is still floor division.

```python
(%seq (write (python-tokenize "//x")) (newline))
```
---
    (('tok-op "//") ('tok-name "x"))

### nothing but the doubled four triples

`==` is the whole operator, not the start of `===`.

```python
(%seq (write (python-tokenize "===")) (newline))
```
---
    (('tok-op "==") ('tok-op "="))

## tokenizer together

### a whole assignment

```python
(%seq (write (python-tokenize "x = 1 + 2")) (newline))
```
---
    (('tok-name "x") ('tok-op "=") ('tok-number "1" 1) ('tok-op "+") ('tok-number "2" 1))

### a call with a string argument

```python
(%seq (write (python-tokenize "print('hi')")) (newline))
```
---
    (('tok-name "print") ('tok-group "(" (('tok-string (104 105))) ")"))

### two lines

```python
(%seq (write (python-tokenize "a\nb")) (newline))
```
---
    (('tok-name "a") ('tok-newline) ('tok-name "b"))

### a def line

```python
(%seq (write (python-tokenize "def f(x):")) (newline))
```
---
    (('tok-kw "def") ('tok-name "f") ('tok-group "(" (('tok-name "x")) ")") ('tok-op ":"))

### a group records the closer it met

The fourth field of a group is the bracket that ENDED it.  The lexer only
nests -- it takes whatever closer turns up, matching or not -- and recording
which one it was is what lets the parser judge it afterwards.

```python
(%seq (write (python-tokenize "[1]")) (newline))
```
---
    (('tok-group "[" (('tok-number "1" 1)) "]"))

### the closer it met is not always the matching one

`(1]` nests exactly as `(1)` does.  Whether `]` had any business ending a `(`
is a question for the parser.

```python
(%seq (write (python-tokenize "(1]")) (newline))
```
---
    (('tok-group "(" (('tok-number "1" 1)) "]"))

### a group that ran out at EOF has no closer

Nil in that field is how an unclosed bracket reaches the parser.  Nothing is
raised here: the lexer got to the end of the input, which is a fact about the
input, not yet a complaint about it.

```python
(%seq (write (python-tokenize "(1")) (newline))
```
---
    (('tok-group "(" (('tok-number "1" 1)) ()))
