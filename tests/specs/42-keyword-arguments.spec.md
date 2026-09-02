Keyword arguments and defaults (`python/parse.x`, `python/runtime.x`):
a def registers its parameter names (%py-sig!) and a keyword call arranges
its arguments into positional slots; defaults evaluate once at def time;
print(sep=, end=), str.format(name=) and the str methods with keywords;
try/except/else; %c, %(key)s mapping and * width under the % operator;
signed based literals; f-string {x=} debug fields and tuple fields.
Every expectation is a real CPython output.

## keyword calls

### defaults and rest

```python
(python-run "def f(a, b=2, *rest):\n    return (a, b, rest)\nprint(f(1))\nprint(f(1, 3))\nprint(f(1, 3, 4, 5))\nprint(f(b=5, a=1))\nprint(f(1, b=7))\ndef g(x, y=[1]):\n    y.append(x)\n    return y\nprint(g(1))\nprint(g(2))\ndef h(a=1, b=2, c=3):\n    return a * 100 + b * 10 + c\nprint(h(), h(c=9), h(5, c=9), h(b=0))\n")
```
---
```output
(1, 2, ())
(1, 3, ())
(1, 3, (4, 5))
(1, 5, ())
(1, 7, ())
[1, 1]
[1, 1, 2]
123 129 529 103
```

### methods and classes

```python
(python-run "class A:\n    def __init__(self, n, tag=\"t\"):\n        self.n = n\n        self.tag = tag\n    def show(self, sep=\":\"):\n        return str(self.n) + sep + self.tag\na = A(3, tag=\"q\")\nprint(a.show(sep=\"-\"))\nprint(A(n=4).show())\nprint(A(5).show())\n")
```
---
```output
3-q
4:t
5:t
```

### format and print keywords

```python
(python-run "print(\"{name} {0} {x}\".format(9, name=\"N\", x=1.5))\nprint(\"{a:>4}|{b!r}\".format(a=1, b=\"s\"))\nprint(1, 2, sep=\", \", end=\"!\\n\")\nprint(\"a\", \"b\", sep=None, end=None)\ntry:\n    \"{k}\".format(z=1)\nexcept KeyError:\n    print(\"KeyError\")\n")
```
---
```output
N 9 1.5
   1|'s'
1, 2!
a b
KeyError
```

### signed based and %d __int__

```python
(python-run "print(-0x10, -0o17, +0b11, 5-0x10, 5 - -0x1)\nclass B:\n    def __int__(self):\n        return 123\nprint(\"%d\" % B())\nprint(\"asdf\".count('s', True), \"asdf\".count('a', False), \"asdf\".count('a', 1 == 2))\n")
```
---
```output
-16 -15 3 -11 6
123
1 1 1
```

### f-string debug and tuples

```python
(python-run "x = 7\nprint(f\"{x=} {x = } {x=:3} {x=!s} {x, x+1} {x!=1} {x==7}\")\n")
```
---
```output
x=7 x = 7 x=  7 x=7 (7, 8) True True
```

### keyword errors

```python
(python-run "def f(a, b=2):\n    return a\ntry:\n    f(1, c=2)\nexcept TypeError:\n    print(\"TypeError 1\")\ntry:\n    f(b=2)\nexcept TypeError:\n    print(\"TypeError 2\")\ntry:\n    f(1, a=2)\nexcept TypeError:\n    print(\"TypeError 3\")\ntry:\n    f(1, 2, 3)\nexcept TypeError:\n    print(\"TypeError 4\")\n")
```
---
```output
TypeError 1
TypeError 2
TypeError 3
TypeError 4
```

### try else

```python
(python-run "try:\n    x = 1\nexcept ValueError:\n    print(\"no\")\nelse:\n    print(\"else ran\")\ntry:\n    raise ValueError\nexcept ValueError:\n    print(\"caught\")\nelse:\n    print(\"not\")\ntry:\n    print(\"hello world\".index(\"ll\", 1, 1))\nexcept ValueError:\n    print(\"Raised ValueError\")\nelse:\n    print(\"Did not raise ValueError\")\n")
```
---
```output
else ran
caught
Raised ValueError
```

### percent c mapping star

```python
(python-run "print(\"%c|%c|%-3c|\" % (48, 'a', 'b'))\nprint('%s' % {})\nprint('%s' % ({},))\nprint('foo' % {})\nprint(\"%(foo)s %(baz)r\" % {\"foo\": \"bar\", \"baz\": False})\nprint(\"%s %(foo)s %(foo)s\" % {\"foo\": 1})\ntry:\n    print(\"%(foo)s %s %(foo)s\" % {\"foo\": 1})\nexcept TypeError:\n    print(\"TypeError\")\nprint(\"%*d|%-*d|%.*f\" % (5, 42, 4, 7, 2, 3.14159))\ntry:\n    print(\"%*s\" % 5)\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    print(\"%*.*s\" % (1, 15))\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    print(\"%(foo)s\" % {})\nexcept KeyError:\n    print(\"KeyError\")\n")
```
---
```output
0|a|b  |
{}
{}
foo
bar False
{'foo': 1} 1 1
TypeError
   42|7   |3.14
TypeError
TypeError
KeyError
```

### replace empty and c align

```python
(python-run "print(\"A\".replace(\"\", \"1\"), \"\".replace(\"\", \"1\"), \"AB\".replace(\"\", \"12\"), \"AB\".replace(\"\", \"1\", 1))\nprint(\"{:4c}|{:<4c}\".format(48, 49))\ntry:\n    '{!s :}'.format(2)\nexcept ValueError:\n    print('ValueError')\ntry:\n    '{ 0 :*^10}'.format(12)\nexcept KeyError:\n    print('KeyError')\n")
```
---
```output
1A1 1 12A12B12 1AB
   0|1   
ValueError
KeyError
```

### str keywords

```python
(python-run "print(\"foo\\rbar\\r\\r\".splitlines(keepends=True))\nprint(\"a b c\".split(maxsplit=1))\nprint(\"a,b,c\".split(sep=\",\", maxsplit=1))\nprint(\"a b  c\".rsplit(None, maxsplit=1))\n")
```
---
```output
['foo\r', 'bar\r', '\r']
['a', 'b c']
['a', 'b,c']
['a b', 'c']
```
