Format details and statement one-liners (`python/parse.x`, `python/runtime.x`):
empty-separator partition, replace argument types, automatic-versus-manual
field numbering, `_` grouping, one-line compound statements.  Split from
42 because a batch past ten cases crosses the allocation ceiling.
Every expectation is a real CPython output.

## format details

### partition and replace errors

```python
(python-run "try:\n    print(\"asdf\".partition(''))\nexcept ValueError:\n    print(\"Raised ValueError\")\nelse:\n    print(\"Did not raise ValueError\")\ntry:\n    print(\"asdf\".partition(1))\nexcept TypeError:\n    print(\"Raised TypeError\")\ntry:\n    'abc'.replace(1, 2)\nexcept TypeError:\n    print('TypeError')\ntry:\n    'abc'.replace('1', 2)\nexcept TypeError:\n    print('TypeError')\nprint('abc'.replace('b', 'x'))\n")
```
---
```output
Raised ValueError
Raised TypeError
TypeError
TypeError
axc
```

### numbering switch and grouping

```python
(python-run "try:\n    '{}{0}'.format(1, 2)\nexcept ValueError:\n    print('ValueError')\ntry:\n    '{0}{}'.format(1, 2)\nexcept ValueError:\n    print('ValueError')\nprint('{0}{0}{1}'.format(1, 2), '{}{}'.format(3, 4))\nprint('{:4_d}|{:4_o}|{:4_b}|{:4_x}|'.format(1, 1, 1, 1))\nprint('{:_d}|{:_o}|{:_b}|{:_x}|{:,d}|'.format(12345678, 12345678, 12345678, 12345678, 12345678))\nprint('{:_.2f}|{:,.1f}'.format(1234567.891, 1234.5))\ntry:\n    '{:,_d}'.format(1)\nexcept ValueError:\n    print('ValueError')\n")
```
---
```output
ValueError
ValueError
112 34
   1|   1|   1|   1|
12_345_678|5706_0516|1011_1100_0110_0001_0100_1110|bc_614e|12,345,678|
1_234_567.89|1,234.5
ValueError
```

### one-line compound statements

```python
(python-run "for v in (0, 0x10, -0x1000):\n    for sz in range(1, 4): print((\"{:0%d,d}\" % sz).format(v))\nif 1 > 0: print('yes')\nelse: print('no')\nwhile False: print('never')\nx = 0\nwhile x < 3: x = x + 1\nprint(x)\nfor i in range(2): print(i); print(i * 2)\n")
```
---
```output
0
00
000
16
16
016
-4,096
-4,096
-4,096
yes
3
0
0
1
2
```
