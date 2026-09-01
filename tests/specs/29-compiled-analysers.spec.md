Compiled analysers (`python/tokens.x`). The per-character body states —
whitespace, comment, blank, name, number — can be compiled to native code
through the platform's assembler lane, and the swap is lazy: nothing happens
until `%py-jit-threshold` bytes of source have passed through
`python-tokenize`, then one guarded attempt pins `active` or `failed`.

EVERY CASE HERE HOLDS ON EVERY PLATFORM. On a platform whose `compile-asm`
cannot forward fvars the attempt refuses and the interpreted states carry on;
the stdout is the same either way, which is what makes the fallback a
contract rather than a hope. The one thing a spec cannot pin platform-wide is
`active` itself.

## the threshold

### below it, nothing is attempted

The suite's own sources are tiny, so every earlier spec file ran interpreted;
this pins that the accounting is why.

```python
(%seq
  (do
    (write (python-tokenize "a"))
    (newline)
    (write (first %py-jit)))
  (newline))
```
---
```output
(('tok-name "a"))
'off
```

## the swap

### compiled and interpreted states tokenize identically

The same source, lexed before and after the adoption attempt. On a JIT
platform the second run is the compiled states, so this equality is the
compiled-equals-interpreted contract; on any other platform it is trivially
true, and the attempt has pinned itself out of the way.

```python
(%seq
  (do
    (def %src "abc de_2 12 3.5 0.25 # comment\n\nif x_1:\n    y = 'str' + \"str\"\n")
    (def %before (python-tokenize %src))
    (%set-first! %py-jit-threshold 0)
    (def %after (python-tokenize %src))
    (write (equal? %before %after))
    (newline)
    ; one attempt was made: off is over, whichever way it went
    (write (eq? (first %py-jit) (lit off))))
  (newline))
```
---
```output
#t
#f
```

### python still runs end to end after the attempt

```python
(python-run "total = 0\nfor n in [1, 2.5, 42]:\n    total = total + n  # accumulate\n\nprint(total)\nprint('ok_2')\n")
```
---
```output
45.5
ok_2
```
