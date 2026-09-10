# A NUL byte is refused, not carried

> **SUPERSEDED for bytes, 2026-09-10.** The claim below that the platform
> cannot carry a NUL is **wrong**, and this note is kept because the reasoning
> that was wrong is worth reading. What is true is narrower and is about a
> CLASS: **`Str8` cannot**, because every one of its doors takes a C string.
> The platform has carried NULs the whole time -- `x/codec/zlib.x` copies a
> byte list into a `(str make)` region through the pointer door, and
> `x/codec/sha256-jit.x` builds `"A\0B\0C"` and says so in a comment.
>
> Measured on the same engine: a region written that way answers `#\A`,
> `#\null`, `#\B` to `str byte-ref`. `str byte-len` answers **1**, which is
> the real constraint -- the length cannot be read back and must be carried,
> which is why zlib.x passes `n` alongside every buffer.
>
> `bytes` and `bytearray` now carry a **byte list**, and `python/bytes.x` is
> the string library written once more against one. The section below headed
> "Why bytes was not fixed alone" priced that at "the whole string algorithm
> library, twice" and declined it; that price was correct and has now been
> paid, once, in one file.
>
> **What survives** is the second objection, and it is why `str` is a separate
> arc: a NUL-bearing `bytes` has nowhere to `.decode()` to while `str` is the
> platform's string. So `'\x00'`, `chr(0)`, `'%c' % 0` and an f-string body
> still refuse, with this note's own sentence. The seam moved to where it is
> actually true instead of standing in front of every constructor that could
> name a zero.


**Status:** **decided and built.** Every spelling that names a NUL byte —
`chr(0)`, `'\x00'`, `b'\x00'`, `'%c' % 0`, `bytes([0])`, `bytes(n)` for a
positive `n` — raises `ValueError: a NUL byte is not representable here`.
None of them silently answers a shorter value, which is what all but the
last two did before.

## What was wrong

Both columns are runs, not recollections: CPython 3.14.7 on one side, and
on the other the tree at x-python#46 answering the same line.

| | CPython | x-python, before |
|---|---:|---:|
| `len(chr(0))` | 1 | 0 |
| `len(b'\x00')` | 1 | 0 |
| `len('a' + chr(0) + 'b')` | 3 | 2 |
| `repr(b'\x00')` | `b'\x00'` | `b''` |

A NUL did not raise and did not round-trip. It **vanished**, and took the rest
of the value's length with it. That is the worst of the three possible
answers: a program that asks for eight bytes of header and gets six has no
symptom at the point of the mistake.

It was never a bytes problem. `bytes` is a wrapper over a string here, so a
bytes literal empties for the same reason `chr(0)` does — the string layer
underneath both.

## Why the string layer cannot be fixed

Not "has not been fixed". **Cannot**, from this bundle or from the platform,
because a NUL-terminated string is a promise x-lang makes on purpose.

`docs/engine-contract.md` lists it among the guarantees — the behaviours no
manifest can show and the library's correctness rests on anyway:

> `str/nul-terminated` — a string value is a C string; bytes past the NUL are
> unobservable.

The engine holds a string as a bare `char *`. There is no length word to read:

```c
/* engine/include/x-type/str.h */
#define x_strval(X)   x_firststr((X))
#define x_strlen(X)   x_lib_strlen(x_strval((X)))
```

So `Str8 length`, `Str8 append`, `Str8 sub`, `Str8 =?` and `Str8 index-of` all
stop at the first NUL, and there is no argument to pass that changes it.

The platform knows this and has an answer, which is not to change strings.
Engine law 8 says `str byte-sub` **addresses** bytes rather than slicing the
NUL-bounded value, so a region *can* hold NULs and *can* be read back — by a
caller carrying the length itself. And where a payload may contain a NUL, the
library's own doors take a **byte list** instead of a string: `hex
encode-bytes`, `base64 encode-bytes`, `socket recv-bytes`, `struct pack`. The
byte list is the platform's lossless carrier. The string is not, and is not
meant to be.

## Why bytes was not fixed alone

`PY-BYTES` already wraps its payload, so it *could* have carried a byte list
and become NUL-correct on its own. Two things argued against it, and the
second is the one that decided it.

**The cost is the whole string algorithm library, twice.** Every bytes method
is the str method on the underlying string — `python/runtime.x` says so above
`%py-bytes-wrap`, and it is why `b'abcabc'.rsplit(b'bc', 2)` works at all.
That is 32 methods in `%py-str-attr` plus the `%py-s-*` helpers beneath them.
A byte-list payload forks all of it, and the fork is permanent: two
implementations of `split`, of `replace`, of `startswith`, drifting.

**And it would relocate the loss rather than remove it.** A NUL-bearing bytes
in a runtime whose str cannot hold one has nowhere to decode to.
`b'\x00'.decode()` must answer a str, and that str would drop the byte —
silently, at the seam, which is exactly the failure being fixed and in a
place with no constructor to refuse from. `'\x00'.encode()` cannot produce the
value at all. The two types would disagree about what a byte is, and the
disagreement would be invisible.

Fixing bytes without str buys a value you cannot get out again.

## What was built instead

The limit is stated once, in one sentence, wherever it is reached.

- **Literals** (`'\x00'`, `b'\x00'`, `'\0'`, `'\101\0'`, an f-string body)
  refuse at tokenize time. The escape decoder cannot raise where it sits —
  a raise crossing the C reader boundary arrives at the guard with its
  payload gone, which is why `%py-note-ind-error!` exists — so a NUL escape
  parks a note that `python-tokenize` raises once reading is over and x is
  driving again. That is the cell-and-re-raise shape `%py-ind-error` already
  uses, raised from the same place.
- **`chr(0)`** refuses in `%py-chr`, which also settles `'%c' % 0` and
  `f'{chr(0)}'`: both route through it.
- **`bytes([0])` and `bytes(n)`** already refused, in `%py-bytes-of-codes`
  and `%py-bytes-zeros`. Unchanged; the message they chose is now the one
  every path uses.
- **Raw strings do not refuse.** `r'\x00'` is four characters in CPython and
  four here — no escape is decoded, so no NUL is named.

A literal's refusal is not catchable by a `try` in the same program, because
tokenizing finishes before the first statement runs. That is the shape
CPython gives a `SyntaxError` too, and the message is the same sentence
either way, so there is one thing to learn rather than two.

## What it costs

`bytes` cannot carry binary. Not compression, not a struct, not a hash
digest, not a length-prefixed frame — anything whose bytes are not text will
hit a zero byte and stop.

Thirteen of the 700 programs in the pinned conformance corpus name a NUL, and
none of them can pass either way. In four the NUL is what the program *prints*
— `basics/builtin_ord.py` (`ord(b'\x00')`), `basics/bytes_find.py` and
`basics/bytes_index.py` (both search `b"00\x0000"`), `basics/string_strip.py`
(`"\0abc\0".strip()`, whose comment says the NUL "used to give a problem") —
so no NUL-free answer is the right one. The other nine reach first for
something this runtime does not have at all: `struct` (`struct1`, `struct2`),
`bytearray` beyond a copy (`bytearray1`, `bytearray_byte_operations`),
`int.to_bytes` (`int_bytes`, `int_bytes_optional_args_cp311`),
`bytes.fromhex` (`builtin_str_hex`) and PEP 750 t-strings
(`string_tstring_basic`, `string_tstring_basic1`).

So the score does not move. What moves is that a program naming a NUL now
stops and **says so** instead of running on with a value two bytes short of
what it asked for. That trade goes the other way for a program that names a
NUL it never uses: it used to run, and now it does not. None of the thirteen
is one — but that is the shape of the cost, not an accident that cannot recur.

The way out, if it is ever worth taking, is the platform's own: `PY-BYTES`
carries a byte list, `PY-STR` becomes a wrapper over a region and a length,
and the string algorithms are written once against that pair rather than
twice against two. That is a different bundle's worth of work, and it stops
x-python being a lang whose `str` is the platform's string. It should be
paid for by a conformance group that wants it, not by this note.
