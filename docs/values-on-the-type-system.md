# Python values want x's type system, not tagged pairs

**Status:** the design below was **tried and does not work**. The mechanism is
real — types, handlers and instances behave as described — but the shape it
implies, running Python inside a child base, founders on the numeric tower. See
"Why running in a base does not work" at the end. Left in place because the
constraint it documents is still true and still decides any future attempt.

## What is there now

A Python list is `(py-list . elements)` and a dict is `(py-dict . entries)` —
ordinary pairs whose first element is a tag symbol. `%py-list?` sniffs the tag,
`%py-write` switches on it to print, and `%py-getattr` dispatches attributes
through **fourteen string comparisons** in an `if` chain.

That was the shortest path from nothing to working containers, and it earned its
place twice: the tag keeps `[]` distinguishable from `None`, and it gives a list
a stable identity to mutate, which is what makes `x.append(5)` visible through a
second name.

It is the wrong shape for what comes next:

- attribute dispatch is linear, and closed — a Python program cannot add to it
- there is no story for `class`, the largest remaining conformance block
- printing lives in two near-copies (`%py-write` and `%py-display`) that have
  already drifted once, which is how dicts came to print as raw pairs

## What it should be

x's **type system** — `(Base make-type)` with a handler alist, and
`%make-instance` — not the class system. Logo uses exactly this for its values:

```
(Base make-type base "LOGO-BLOCK"
  (list (pair 'write (fn (_ _) (display "[ ... ]")))
        (pair 'eval  (fn (_ self) (logo-process-tokens (first self))))))
```

A `write` handler means `display` renders the value correctly with no dispatch
of ours at all — both printers collapse. `%type?` replaces tag-sniffing with
real identity. The base config carries a length hook, so `len` can dispatch
there too. And a Python class becomes a type, which is the only story that
scales.

## The constraint that decides the shape

`x_prim_make_instance` (`src/x-prim/type.c:148`) resolves the type handle in the
**calling** base's alist:

```c
p_type = x_eval_type_alist_assoc(p_base, lookup_args);
if (x_obj_isnil(p_base, p_type)) return NULL;   /* not found -> nil */
```

`p_base` is the base executing the call, not the base the type was registered
on. Three consequences, each measured:

1. Registering `PY-LIST` on a side base and calling `%py-mklist` from ambient
   code returns **nil**. That is the `()` an early probe produced.
2. A constructor closure *defined* inside that base but *called* from ambient
   also returns nil — the closure does not carry its base.
3. Logo escapes this only because it never instantiates from ambient code:
   every `%make-instance` is inside a `read` handler, which the tokenizer
   invokes while running on `%logo-base`.

So construction cannot be sent to the types. **The program has to run where the
types are.**

## The shape that follows

Build a Python base up from `(Base make)`, add the types, bind in what generated
code needs, and evaluate every form there.

Verified available in a fresh `(Base make)`, no binding needed:

    fn   def   set!   %seq   pair   first   rest   arithmetic   match

Verified absent, and `Base bind` carries them in — proved with `if`, which binds
and works:

    if   display   list   null?

**`match` is a C primitive**, so the parser can emit `match` instead of `if` and
the conditional needs no binding at all.

Verified end to end: a type registered on a base, an instance constructed inside
it via `Base eval`, handed out, and printed in the ambient base — the `write`
handler fires. Handlers travel with instances, exactly as `make-type`'s own doc
says.

## What the work is

- `(Base make)` once, at load; register `PY-LIST` and `PY-DICT` with `write`
  handlers; `Base bind` the dozen names generated forms use
- `python-run` evaluates each form with `Base eval` on that base instead of
  `eval!`
- the parser emits `match` rather than `if`
- `%py-list?` / `%py-dict?` become `%type?`; `%py-write` and `%py-display` go
  away; `%py-getattr`'s chain becomes type dispatch
- every construction site in `runtime.x`

Roughly all 418 lines of `runtime.x`, the evaluation path in `base.x`, and the
`if` emission in `parse.x`.

## Costs, stated

Running in a child base means the environment is only what is bound into it. A
name missed is an error at run time, in generated code, which is a long way from
where it would be read. The bind list is load-bearing and wants a spec of its
own asserting each name resolves.

`Base eval` per statement is heavier than `eval!` -- measured at ~1.0 ms against
~0.027 ms, about 38x. That turned out not to matter: the statements fold into
one form with the parser's own %py-seq-of, so it is one eval per PROGRAM, about
a millisecond. Recorded because the measurement was worth having and the fold is
the right shape regardless.

## Why running in a base does not work

**A child base has no numeric tower.** Measured:

    (* 2 1.5)                    child base: 105759989792   ambient: 3.0
    (* 99999999999 99999999999)  child base: 1864711849423024129  (wrapped)

`(Base make)` registers the C built-in types — prim, operative, procedure,
symbol, list, int, str, char, whitespace, comment. Float, bigint and rational
are LIBRARY types, loaded into the ambient base by the xenon dialect's
tower-compiled block. A child base gets none of them, and a float object there
is read as the integer its pointer happens to be.

Python cannot run without them. Arbitrary-precision `int` and `1 / 2 == 0.5` are
the reason this bundle declares xenon rather than helium.

The attempt got to **190 of 232** specs before this surfaced: every failure was
an expression involving a float or a bignum. The core forms, the bind list and
the one-eval-per-program fold all worked. It was the arithmetic underneath them
that was gone.

Loading the tower into a child base would mean booting a dialect inside it,
which is a much larger thing than this note describes and may not be reachable
from lang code at all.

## What would actually unblock it

A way to register a type on the base that is ALREADY RUNNING — something like
`(prim-ref 'base 'current)` returning the running base, so

    (Base make-type (Base current) "PY-LIST" (list (pair 'write ...)))

becomes possible. Then instances resolve where the program already runs, the
tower is the ambient one, and none of the base-hopping above is needed.

That is an engine capability, not something a lang can work around: the `base`
namespace exposes `make-type`, `make-tok`, `make`, `eval` and `bind`, and none
of them yields the current base.

## Why not sooner

The tagged-pair representation was right for lists and dicts and would have been
wrong to skip — it is what made mutation work, and the identity argument behind
it is the same one the type system needs. The refactor is worth doing **before**
`class`, and before more container types accrete on the current scheme, not
because the current one is broken but because the next thing does not fit it.
