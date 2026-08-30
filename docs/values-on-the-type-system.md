# Python values want x's type system, not tagged pairs

**Status:** designed and proved, not built. The mechanism below was verified
probe by probe against x-engine-c v0.1.3; nothing here is inferred.

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

`Base eval` per statement is heavier than `eval!`. Not measured. Worth measuring
before committing, because the suite is 232 cases and a per-statement cost shows
up there first.

## Why not sooner

The tagged-pair representation was right for lists and dicts and would have been
wrong to skip — it is what made mutation work, and the identity argument behind
it is the same one the type system needs. The refactor is worth doing **before**
`class`, and before more container types accrete on the current scheme, not
because the current one is broken but because the next thing does not fit it.
