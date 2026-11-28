Repetition and joining at a size (`python/bytes.x`, `python/runtime-seq.x`):
str, bytes, bytearray, list and tuple times a count, str.join and bytes.join,
and the padding methods, which repeat their fill.  Each copy used to go on the
END of what was built, copying it again, so `'a' * 8000` took 32 million pairs
and passed the guard.  Every expectation is a real CPython output.

## string repeat

### a long repeat, a long join and a wide pad, each built in one pass

```python
(python-run "s = 'ab' * 10000\nprint(len(s), s[:5], s[-3:])\nt = 'x' * 0 + 'y' * -3 + 3 * 'z'\nprint(repr(t), 'q' * 1)\nb = b'\\x00\\xff' * 8000\nprint(len(b), b[:4], b[-1])\nl = [1, [2]] * 6000\nprint(len(l), l[:3], l[-1] is l[1])\nprint(len((0, 1, 2) * 6000), len(bytearray(b'ab') * 4000))\nj = ','.join(['ab'] * 4000)\nprint(len(j), j[:8], j[-4:])\nprint(len(b'-'.join([b'xyz'] * 4000)), '-'.join(['a', 'b', 'c']), ''.join([]), '/'.join(['only']))\nprint(len(' '.center(12000)), len('x'.ljust(12000, '.')), 'x'.rjust(5, '*'))\n")
```
---
```output
20000 ababa bab
'zzz' q
16000 b'\x00\xff\x00\xff' 255
12000 [1, [2], 1] True
18000 8000
11999 ab,ab,ab b,ab
15999 a-b-c  only
12000 12000 ****x
```
