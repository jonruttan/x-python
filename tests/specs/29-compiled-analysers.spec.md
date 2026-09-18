Compiled analysers (`python/tokens.x`). The per-character body states —
whitespace, comment, blank, name, keyword, number — can be compiled to native code
through the platform's assembler lane, and the swap is lazy: nothing happens
until `%py-jit-threshold` bytes of source have passed through
`python-tokenize`, then one guarded attempt pins `active` or `failed`.

Every case here holds on every platform. Where the lane cannot compile an
analyser state the attempt refuses and the interpreted states carry on; the
stdout is the same either way, which is what makes the fallback a contract
rather than a hope. Which of `active` and `failed` is due is asked of the lane
directly, apart from the attempt, so a refusal the attempt's guard swallows
still fails a case here.

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
    (def %src "abc de_2 12 3.5 0.25 1e10 2.5E-3 .5 1_000.1_8 3j 2.5J # comment\n\nif x_1:\n    y = 'str' + \"str\"\n")
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

### the attempt pins active wherever the lane compiles an analyser

The lane is asked directly whether it compiles one analyser state, with the
mode declared and nothing taken from the attempt. Where it does, the attempt
must pin `active`; where it does not, `failed`. On a disagreement the case
prints the attempt's refusal.

```python
(%seq
  (do
    (def %lane
      (guard (_ #f)
        (%seq
          (compile-asm (lit (fn (me buffer score chr) (if (= chr 32) me ()))) () #t)
          #t)))
    (%set-first! %py-jit-threshold 0)
    (python-tokenize "x = 1\n")
    (write
      (if (eq? (first %py-jit) (if %lane (lit active) (lit failed)))
        #t
        (guard (e e) (%py-jit-compile!)))))
  (newline))
```
---
```output
#t
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
