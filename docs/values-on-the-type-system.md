# Python values want x's type system, not tagged pairs

**Status:** **done for lists**, in `python/types.x`. The first attempt at it
failed and this note recorded that failure as a property of the design; that was
wrong, and the correction is at the end under "The wrong turn, and what it cost".
The short version: a lang does not need a base of its own. `make-type` registers
onto the base it is CALLED in, so Python's types go onto the running base — the
one that already carries the numeric tower.

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

## The wrong turn, and what it cost

The first attempt gave Python a base of its own: `(Base make)`, ~34 names bound
into it, the folded program evaluated with `Base eval`. It reached **190 of 232**
specs and stopped dead. Every one of the 42 failures was an expression involving
a float or a bignum. Measured:

    (* 2 1.5)                    child base: 105759989792   ambient: 3.0
    (* 99999999999 99999999999)  child base: 1864711849423024129  (wrapped)

That much is true and worth keeping. `(Base make)` registers the C built-in
types — prim, operative, procedure, symbol, list, int, str, char, whitespace,
comment. Float, bigint and rational are LIBRARY types, and a child base gets
none of them; a float object there is read as the integer its pointer happens to
be.

**The wrong part was the conclusion.** This note went on to say the design was
unreachable, and asked for an engine capability to unblock it:

> A way to register a type on the base that is ALREADY RUNNING — something like
> `(prim-ref 'base 'current)` returning the running base.

That capability already existed, under a name I had not looked at. There are
**two** type-registering prims, not one:

| prim | catalog | arity | registers onto |
|---|---|---|---|
| `base-make-type` | `base` / `make-type` | target, name, handlers | the base you name |
| `make-type` | `type` / `make` | name, handlers | **the base it is called in** |

I had found the first, used it for the isolated tokenizer base where naming a
target is exactly what you want, and assumed it was the only door. The claim
that "the `base` namespace exposes `make-type`, `make-tok`, `make`, `eval` and
`bind`, and none of them yields the current base" was true and beside the point:
the answer was not in the `base` namespace at all.

The cost was one wrong conclusion written down as a finding — the expensive kind
of mistake, because a note that says "does not work" stops the next attempt
before it starts. It survived about a day.

**The models were in the library the whole time.** `x/num/rational.x` and
`x/type/vector.x` are value types registered on the running base with exactly
this prim. This file follows them down to the handler arity, and the tower they
depend on is the same one Python now keeps.

## Three things that bite, all learned the hard way

**The iterator step returns `(value . next-state)`, and only a nil PAIR ends the
walk.** Written the other way -- bare values, nil means exhausted -- a container
holding `None` truncates at the first one, because Python's `None` is nil here.
The first version of both `iter` handlers had exactly that bug, and nothing
consumed the slot, so nothing failed. `x/type/iter.x` states the contract on
`Iter make`: "exhaustion rides the STATE". Its doc example is the correct step
function, verbatim.


**Handler arity is `(fn (_ self) ...)`.** The first parameter is the TYPE, the
second the instance. Writing `(fn (self) ...)` binds the type to `self`, and
`(first <a type>)` is a read of a non-pair — x-engine-c#16, a segfault rather
than an error.

**The %-globals share one flat namespace across the bundle's modules.** Naming
the element accessor `%py-elems` collided with `parse.x`'s list-literal element
parser of the same name, and 47 specs failed with a *syntax* error from a change
that touched only the runtime. It is the second collision of this kind here; the
first was `%py-len`, defined once as a parser helper and once as Python's
`len`, which made `len('hello')` answer 119. Grep the bundle for a name before
defining it.

## Why not sooner

The tagged-pair representation was right for lists and dicts and would have been
wrong to skip — it is what made mutation work, and the identity argument behind
it is the same one the type system needs. The refactor is worth doing **before**
`class`, and before more container types accrete on the current scheme, not
because the current one is broken but because the next thing does not fit it.
