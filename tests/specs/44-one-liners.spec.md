Statement one-liners (`python/parse.x`): a simple statement on a compound
header line, and `;` as a statement boundary.  Every expectation is a real
CPython output.

## one-liners

### for inline

```python
(python-run "for v in (0, 0x10, -0x1000):\n    for sz in range(1, 4): print((\"{:0%d,d}\" % sz).format(v))\n")
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
```

### if else inline

```python
(python-run "if 1 > 0: print('yes')\nelse: print('no')\n")
```
---
```output
yes
```

### while inline

```python
(python-run "while False: print('never')\nx = 0\nwhile x < 3: x = x + 1\nprint(x)\n")
```
---
```output
3
```

### semicolon

```python
(python-run "for i in range(2): print(i); print(i * 2)\n")
```
---
```output
0
0
1
2
```

### float grouping

```python
(python-run "print('{:_.2f}|{:,.1f}|{:_}'.format(1234567.891, 1234.5, 1234567))\n")
```
---
```output
1_234_567.89|1,234.5|1_234_567
```
