# x-python — Python on x-lang

A Python 3 surface for [x-lang](https://github.com/jonruttan/x-lang):
indentation is grouping, statements are not expressions, and there is one
integer type that goes all the way up.

## Status

**Nothing is implemented.** `python-run` prints `#<python: not implemented>` and
returns nil. That is the honest state, and it is not the interesting number.

The interesting number is this one:

```
$ make score
GROUP                        PASS     OF   RATE
basics/builtin                  0     58     0.0%
basics/string                   0     49     0.0%
basics/class                    0     36     0.0%
basics/int                      0     34     0.0%
basics/bytes                    0     28     0.0%
...
TOTAL                           0    657     0.0%
```

657 whole Python programs, each compared on its whole stdout against a real
CPython 3.14 run, ranked by how much of it is red. The scoreboard was built
before the language on purpose: it turns "what should a Python implementation
do first" from a taste question into a sorted list.

## The suite, and why it is this one

**Python has no test262.** There is no vendor-neutral conformance suite. The
de-facto standard is CPython's `Lib/test`, and it is unusable to a young
implementation: unittest-based, so `unittest`, `io` and a slab of stdlib must
work before the first assertion runs; dense with `@cpython_only` and
`impl_detail`; and PSF-licensed rather than MIT.
(`MalloyPower/python-compliance` surfaces in searches and is a research corpus
for an ESEM 2017 paper, with no tests in it.)

**MicroPython's `tests/` was written by people implementing a subset**, which
is this bundle's position exactly. Measured against v1.29.0 rather than
assumed:

| suite | `.py` files | run under CPython 3.14 unmodified |
|---|---:|---:|
| `basics/` | 576 | 562 |
| `float/` | 69 | 69 |
| `import/` | 30 | 30 |
| `unicode/` | 25 | 21 |
| | | **682** |

The files are tiny, import nothing, and assert by printing — one program, one
stdout blob, which is the same shape a `.spec.md` case is. Only 65 of the 576
in `basics/` carry a `.exp` file; the rest are *differential*, meaning upstream
generates the expectation by running CPython. So does this bundle.

**CPython is the oracle, not MicroPython.** Where CPython refuses a file — 15
of them, `builtin_help`, `memoryerror`, the `*_micropython` ones — upstream's
`.exp` records MicroPython's own deviation, and x-python has no business chasing
that. Those are excluded and counted, never silently adopted. Upstream's
`cpydiff/` is the same idea from the other side: 82 documented, sanctioned
places a subset is allowed to differ.

682 programs have an oracle; 657 became spec cases. The 43 that did not are
listed by name and reason in `tests/conformance/SKIPPED.md`, because a score's
denominator is only honest if the exclusions are auditable.

## Running it

```bash
make test          # the bundle's own suite -- the pipeline, not the language
make gen           # fetch the pinned corpus, generate tests/conformance/
make score         # pass/total per group, worst first
make conformance   # the same run, case by case
```

`make gen` takes about a minute: it runs CPython twice over every program in
the corpus — once at `PYTHONHASHSEED=0` and once at `1`, so anything whose
output is not reproducible is caught and excluded rather than becoming a test
nothing could ever pass.

Nothing generated is committed. `deps/` is the fetched corpus, verified against
the digest in `tools/conformance/upstream.pin.xon`; `tests/conformance/` is
derived from it and from whichever CPython was the oracle. `make clean` drops
both.

## Layout

```
lang.xon                     name, dialect, release pairing
run.x                        THE entry -- and it knows no paths at all
python/base.x                    the language (today: a stub, and a loud one)
tests/spec-runner.sh         sources the platform's shared runner
tests/gen-harness.sh         writes tests/lib/harness.gen.x (generated)
tests/specs/                 the bundle's own suite -- the pipeline
tools/conformance/
  upstream.pin.xon           the corpus: commit, digest, licence, suites
  fetch.sh                   fetch, verify, unpack into deps/
  gen-specs.py               corpus -> .spec.md, with CPython as oracle
  score.sh                   the ranked table
```

## Why xenon

Derived from Python's data model, not from convenience:

- Python 3 has **one** integer type and it is arbitrary-precision. `2 ** 200`
  is not an error and not a float. That is `x/num/bigint.x`.
- `1 / 2` is `0.5`. True division always produces a float, so float is
  reachable from the first arithmetic expression anyone types.
- `dict` is syntax, and `x/type/dict.x` loads by default in the tower dialects
  and in neither light one.

The cost is real: xenon's boot runs eight runtime `cc` compilations for the
numeric analysers, so `x -l python` starts slower than `x -l krn`. Declaring `he`
would buy that back by making `2 ** 200` wrong, which is not a trade.

Not radon. ash needs `rn` for fork/exec/dup2; a Python whose library is `print`
and `len` reaches nothing raw. When `os` and `socket` arrive that gets
revisited — as a decision, which is why it is written down in `lang.xon`.

## What is next, and the one thing worth deciding early

The scoreboard says `basics/builtin` (58), `basics/string` (49),
`basics/class` (36) and `basics/int` (34) are the big blocks. None of them is
reachable without a reader, so the reader is first regardless of the ranking:

- **a tokenizer on its own base.** `(Base make-tok)` / `(Base make-type)`, the
  way `ash/prims.x` does it, so Python's `#` is a comment and its `'` opens a
  string without competing with the sexp reader's types by score.
- **INDENT/DEDENT.** Settled ahead of the reader: x-lang#520 is closed and
  `lib/x/reader/indent.x` holds the stack discipline that Logo and x-sweet each
  used to own a copy of. x-python does not write a third one — it constructs an
  `Indent` and drives it.

  Its policy is the module's default, because the defaults were chosen to be
  SRFI-110's, and Python agrees with SRFI-110 on both questions: a tab advances
  to the next multiple of 8, and a dedent matching no open level raises rather
  than opening a block there. `(Indent make)` is already a Python indenter.

  What is still x-python's own is everything above the stack: explicit and implicit
  line joining, brackets suppressing indentation entirely, and the tabs-versus-
  spaces ambiguity check that turns into `TabError`. Those are surface facts,
  and the module is deliberately silent about them.

## Licence

MIT No Attribution (MIT-0). See [LICENSE](LICENSE).

The MicroPython corpus this bundle scores against is MIT and is **not** vendored
here — it is fetched and verified from the pin in
`tools/conformance/upstream.pin.xon`.
