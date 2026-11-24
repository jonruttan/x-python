# string: common string operations

`stdlib/string.py`. Each expected output is a python3.14 run of the same
program.

### the constants, and capwords

```python
(python-run "import string\nprint(string.ascii_letters)\nprint(string.digits, string.hexdigits, string.octdigits)\nprint(string.punctuation)\nprint(repr(string.whitespace), len(string.printable))\nprint(string.capwords(\"hello   big  world\"), string.capwords(\"a-b--c\", \"-\"))\nprint(\"x\" in string.ascii_lowercase, \"Q\" in string.ascii_uppercase)\n")
```
---
```output
abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ
0123456789 0123456789abcdefABCDEF 01234567
!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
' \t\n\r\x0b\x0c' 100
Hello Big World A-B--C
True True
```

### Template substitutes $name and ${name}, and says what is wrong

```python
(python-run "from string import Template\nt = Template(\"$who likes ${what}; costs $$${amt}\")\nprint(t.substitute(who=\"tim\", what=\"kung pao\", amt=5))\nprint(t.substitute({\"who\": \"ann\", \"what\": \"tea\", \"amt\": 2}, who=\"bo\"))\nprint(Template(\"$who and $missing\").safe_substitute(who=\"cy\"))\nprint(t.get_identifiers(), t.is_valid(), Template(\"bad $ here\").is_valid())\ntry:\n    Template(\"$who and $missing\").substitute(who=\"cy\")\nexcept KeyError as e:\n    print(\"KeyError\", e)\ntry:\n    Template(\"line one\\n  oops $!\").substitute()\nexcept ValueError as e:\n    print(\"ValueError\", e)\nclass Percent(Template):\n    delimiter = \"%\"\nprint(Percent(\"%name has %% left, not $x\").substitute(name=\"dee\"))\nprint(t.template)\n")
```
---
```output
tim likes kung pao; costs $5
bo likes tea; costs $2
cy and $missing
['who', 'what', 'amt'] True False
KeyError 'missing'
ValueError Invalid placeholder in string: line 2, col 8
dee has % left, not $x
$who likes ${what}; costs $$${amt}
```

### Formatter formats as str.format does, and a subclass can change its pieces

```python
(python-run "from string import Formatter\nf = Formatter()\nprint(f.format(\"{} + {} = {:>5}\", 2, 3, 5))\nprint(f.format(\"{0[1]} {p.real} {name!r:^8}|\", [7, 8], p=3+4j, name=\"nm\"))\nprint(f.format(\"{0:{1}{2}}\", 3.14159, \".\", \"2f\"))\nprint(list(f.parse(\"a{{b}}c {0!r:>4} {name}\")))\nclass Defaulting(Formatter):\n    def get_value(self, key, args, kwargs):\n        if isinstance(key, str):\n            return kwargs.get(key, \"<\" + key + \">\")\n        return super().get_value(key, args, kwargs)\n    def format_field(self, value, spec):\n        return super().format_field(value, spec).upper()\nprint(Defaulting().format(\"{greet}, {who}! {0}\", \"x\", greet=\"hi\"))\nfor bad in [\"{\", \"}\", \"{0!}\", \"{0:{\", \"{} {0}\", \"{0} {}\"]:\n    try:\n        f.format(bad, 1, 2)\n    except ValueError as e:\n        print(\"ValueError\", e)\n")
```
---
```output
2 + 3 =     5
8 3.0   'nm'  |
3.14
[('a{', None, None, None), ('b}', None, None, None), ('c ', '0', '>4', 'r'), (' ', 'name', '', None)]
HI, <WHO>! X
ValueError Single '{' encountered in format string
ValueError Single '}' encountered in format string
ValueError unmatched '{' in format spec
ValueError unmatched '{' in format spec
ValueError cannot switch from automatic field numbering to manual field specification
ValueError cannot switch from manual field specification to automatic field numbering
```

### format() and ascii(), the builtins Formatter calls

```python
(python-run "print(format(3.14159, \".2f\"), format(42), format(\"ab\", \">5\") + \"|\", format(255, \"#x\"))\nprint(ascii(\"h\u00e9llo\"), ascii([1, \"\u00fc\"]), ascii(\"plain\"))\nclass Money:\n    def __format__(self, spec):\n        return \"$\" + format(12.5, spec or \".2f\")\nprint(format(Money()), format(Money(), \".1f\"))\ntry:\n    format(1, 2)\nexcept TypeError as e:\n    print(\"TypeError\", e)\n")
```
---
```output
3.14 42    ab| 0xff
'h\xe9llo' [1, '\xfc'] 'plain'
$12.50 $12.5
TypeError format() argument 2 must be str, not int
```
