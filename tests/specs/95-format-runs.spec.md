# the format walkers at a literal run's edges

### a literal run, alone and between fields

```python
(python-run "print(\"a long stretch of ordinary text with no fields at all\".format())\nprint(\"{} then a long stretch of ordinary text and then {}\".format(1, 2))\nprint(\"{}{}{}\".format(1, 2, 3))\nprint(\"\".format(), \"|\", \"{}\".format(\"\"))\n")
```
---
```output
a long stretch of ordinary text with no fields at all
1 then a long stretch of ordinary text and then 2
123
 | 
```

### escaped braces bound a run on either side

```python
(python-run "print(\"{{literal}} between {} and {{more}} text\".format(7))\nprint(\"}}{{\".format(), \"|\", \"{{}}\".format())\nprint(\"trailing braces {}{{}}\".format(1))\n")
```
---
```output
{literal} between 7 and {more} text
}{ | {}
trailing braces 1{}
```

### a brace that opens or closes nothing

```python
(python-run "for t in (\"{\", \"}\", \"a {\", \"} b\", \"{} }\"):\n    try:\n        print(t.format(1))\n    except ValueError as e:\n        print(\"ValueError\", e)\n")
```
---
```output
ValueError Single '{' encountered in format string
ValueError Single '}' encountered in format string
ValueError Single '{' encountered in format string
ValueError Single '}' encountered in format string
ValueError Single '}' encountered in format string
```

### the percent walker, a run and a lone percent

```python
(python-run "print(\"a long stretch of ordinary text with no conversions\" % ())\nprint(\"%s then a long stretch of ordinary text and then %s\" % (1, 2))\nprint(\"100%% sure\" % ())\ntry:\n    print(\"ends with %\" % ())\nexcept ValueError as e:\n    print(\"ValueError\", e)\n")
```
---
```output
a long stretch of ordinary text with no conversions
1 then a long stretch of ordinary text and then 2
100% sure
ValueError incomplete format
```

