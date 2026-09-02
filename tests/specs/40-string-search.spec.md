Strings, the rest of the surface (`python/tokens.x`, `python/runtime.x`):
searching and testing: endswith/startswith with ranges and tuples,
the find family, count, the is-predicates.
Every expectation is a real CPython output.  Split across files because a
string-heavy batch accumulates past the object ceiling in one process.

## string search

### endswith and startswith with ranges

```python
(python-run "print(\"foobar\".endswith(\"bar\"), \"foobar\".endswith(\"baR\"), \"foobar\".endswith(\"bar1\"), \"foobar\".endswith(\"foobar\"), \"foobar\".endswith(\"\"), \"foobar\".endswith(\"foobarbaz\"))\nprint(\"foobar\".endswith(\"bar\", 3), \"foobar\".endswith(\"bar\", 4), \"foobar\".endswith(\"foo\", 0, 3), \"foobar\".endswith(\"foo\", 0, 4), \"foobar\".endswith(\"bar\", 3, 6))\nprint(\"foobar\".startswith(\"foo\"), \"foobar\".startswith(\"foo\", 1), \"foobar\".startswith(\"oob\", 1), \"foobar\".startswith(\"bar\", 3), \"foobar\".startswith(\"bar\", -3), \"foobar\".startswith((\"x\", \"foo\")))")
```
---
```output
True False False True True False
True False True False True
True False True True True True
```

### find family with ranges, a start past the end

```python
(python-run "print(\"hello\".find(\"l\"), \"hello\".find(\"l\", 3), \"hello\".find(\"z\"), \"hello\".rfind(\"l\"), \"hello\".index(\"e\"), \"hello\".rindex(\"l\"), \"hello\".find(\"l\", 0, 2), \"hello\".find(\"\", 5), \"hello\".find(\"\", 6))\ntry:\n    \"hello\".index(\"z\")\nexcept ValueError:\n    print(\"ValueError\")")
```
---
```output
2 3 -1 3 1 3 -1 5 -1
ValueError
```

### count, including the empty needle

```python
(python-run "print(\"\".count(\"\"), \"\".count(\"a\"), \"a\".count(\"\"), \"aaa\".count(\"aa\"), \"aaa\".count(\"aaaa\"), \"aaaa\".count(\"aa\"), \"abcabc\".count(\"b\", 2))")
```
---
    1 0 2 1 0 2 1

### is predicates and case

```python
(python-run "print(\"\".isspace(), \" \\t\\n\\r\\v\\f\".isspace(), \"a\".isspace(), \"\".isalpha(), \"abcXYZ\".isalpha(), \"ab1\".isalpha(), \"\".isdigit(), \"0123\".isdigit(), \"12a\".isdigit(), \"abc\".isupper(), \"ABC\".isupper(), \"aBc\".islower(), \"abc\".islower(), \"a1\".isalnum(), \"a!\".isalnum())\nprint(\"aBc\".upper(), \"aBc\".lower(), \"hello world\".title(), \"Hello\".swapcase(), \"abc\".capitalize())")
```
---
```output
False True False False True False False True False False True False True True False
ABC abc Hello World hELLO Abc
```
