The except-tuple cases, split from 20-tuples for the same reason 27-super
split from 18-classes: on CI's slowest lane (the pinned v0.9.0 platform,
which boots interpreted) the combined file grazed the 60-second unit
timeout, and a file that fails by wall clock reads as a regression that
is not one. Same contract, its own process.

## except takes a tuple of classes

Python spells "any of these" with a tuple.

### the first matches

```python
(python-run "try:\n    raise ValueError('v')\nexcept (ValueError, KeyError) as e:\n    print(e)")
```
---
    v

### the second matches

```python
(python-run "try:\n    raise KeyError('k')\nexcept (ValueError, KeyError):\n    print('caught')")
```
---
    caught

### neither matches, so it travels

```python
(python-run "try:\n    raise TypeError('t')\nexcept (ValueError, KeyError):\n    print('no')")
```
---
    Error: TypeError: t
