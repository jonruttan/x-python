The exact-integer cases, split from 32-float-odds-ends for a resource
reason worth recording: these walk 20-to-31-digit magnitudes through the
promoting hand parser, and on the pinned v0.9.0 platform -- whose bigint
ops predate a year of allocation work -- the combined file's batch crossed
the 300M object ceiling and died mid-batch, deterministically, while
current main fit comfortably.  A file that fails by ceiling on one
platform reads as a regression that is not one.  Same contract, its own
process.

## int of float is exact

### through the digits, bigints included

```python
(python-run "print((int(1e19), int(2.0**100), int(1418774543.0), int(-2.7)))")
```
---
    (10000000000000000000, 1267650600228229401496703205376, 1418774543, -2)

## big integer literals

### past two to the sixty-three, no wrap

```python
(python-run "print((99999999999999999999, -99999999999999999999))")
```
---
    (99999999999999999999, -99999999999999999999)
