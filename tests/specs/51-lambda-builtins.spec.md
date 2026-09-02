Lambda and the iteration builtins (`python/parse.x`, `python/runtime.x`):
`lambda params: expr` with defaults and a *rest through the def machinery,
whose parameter commas are not tuple or argument separators; map() as a
lazy generator, zip, all, any, sorted (a stable merge sort on <); a
function's __name__ from its signature; exceptions repr as Name(args) and
carry .args; raise with several constructor arguments.
Every expectation is a real CPython output.

## lambda and builtins

### lambda

```python
(python-run "f = lambda x: x + 1\nprint(f(1), (lambda: 7)(), (lambda a, b=2: a * b)(3), (lambda a, b=2: a * b)(3, 4), (lambda *a: a)(1, 2))\nprint(list(map(lambda x: x * x, range(4))), sorted([3, 1, 2]), sorted(['b', 'a']), list(zip([1, 2], 'ab')), all([1, 2]), all([1, 0]), any([0, 1]), any([]))\ng = lambda x: x if x > 0 else -x\nprint(g(-3), g(3))\ndef Fun():\n    yield\nprint(Fun.__name__)\ntry:\n    raise ValueError('a', 0)\nexcept ValueError as e:\n    print(repr(e), e.args)\ntry:\n    raise GeneratorExit(123)\nexcept GeneratorExit as e:\n    print('GeneratorExit', e.args)\n")
```
---
```output
2 7 6 12 (1, 2)
[0, 1, 4, 9] [1, 2, 3] ['a', 'b'] [(1, 'a'), (2, 'b')] True False True False
3 3
Fun
ValueError('a', 0) ('a', 0)
GeneratorExit (123,)
```
