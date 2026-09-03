Floor division and base conversion across magnitudes (`python/runtime.x`,
`python/format.x`).  Python FLOORS where the engine's quotient truncates,
and the fix must not change the REPRESENTATION callers get: an earlier
form subtracted a modulo and handed back a bigint zero under the lane
where ints promote, where format.x's digit loop -- which tested its
counter with eq? -- never terminated and took a CI host down.
Every expectation is a real CPython output.

## f

### floors across magnitudes

```python
(python-run "print(-7 // 2, 7 // -2, -8 // 2, 8 // -2, 7 // 2, -7 % 2, 7 % -2)\nprint(divmod(-7, 2), divmod(7, -2), divmod(-8, 2))\nb = 1180591620717411303424\nprint(b // 10, -b // 10, b // -10, hex(b), oct(b), bin(b)[:20])\nprint((-b) // 7, (-b) % 7, hex(-b))\nprint('%x %o %d' % (b, b, -b))\nprint('{:x} {:_x} {:,d}'.format(b, b, -b))\nprint(round(b, -1), round(-b, -1))\n")
```
---
```output
-4 -4 -4 -4 3 1 -1
(-4, 1) (-4, -1) (-4, 0)
118059162071741130342 -118059162071741130343 -118059162071741130343 0x400000000000000000 0o200000000000000000000000 0b100000000000000000
-168655945816773043347 5 -0x400000000000000000
400000000000000000 200000000000000000000000 -1180591620717411303424
400000000000000000 40_0000_0000_0000_0000 -1,180,591,620,717,411,303,424
1180591620717411303420 -1180591620717411303420
```
