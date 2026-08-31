`decimal.Decimal`, from x-lang's `x/num/decimal`.

**Python's `float` is not this, and must not become it.** CPython's float is IEEE
754 binary — `0.1 + 0.2` is `0.30000000000000004` — and the conformance corpus
has a whole `float/` suite checking exactly that. `x/num/decimal` is *exact* for
`+ - *`, so mapping it onto `float` would move this bundle further from CPython
while looking like an improvement.

It is Python's `decimal.Decimal`, which has the same contract as x's: exact
`+ - *`, division rounding to a context precision, half-even. So it is bound to
that name and nothing else changes — arithmetic already dispatches through the
tower, so `+` on two decimals needed no code at all.

**Divergence, stated:** Python spells this `from decimal import Decimal`, and
this bundle has no `import` yet, so the name is a builtin. When modules land it
moves behind the import.

The context precision is set to 28, CPython's default, rather than left at x's
34 — `Decimal(1) / Decimal(3)` is a printed answer and the digit count is part
of it.

## the case it exists for

### exact addition

```python
(python-run "print(Decimal('0.1') + Decimal('0.2'))")
```
---
    0.3

### and equal to the exact value, which the float is not

```python
(python-run "print(Decimal('0.1') + Decimal('0.2') == Decimal('0.3'))\nprint(0.1 + 0.2 == 0.3)")
```
---
```output
True
False
```

That second `False` is CPython's answer too. x's float arithmetic IS binary
IEEE; only its *printing* is short — `print(0.1 + 0.2)` shows `0.3` here and
`0.30000000000000004` in CPython, which is a rendering difference in x's float
type rather than anything decimal changes.

## str, repr, and containers

### str is the bare number, repr names the type

```python
(python-run "d = Decimal('0.1')\nprint(str(d))\nprint(repr(d))")
```
---
```output
0.1
Decimal('0.1')
```

### print uses str

```python
(python-run "print(Decimal('0.1'))")
```
---
    0.1

### a container shows repr of its elements

```python
(python-run "print([Decimal('0.1')])")
```
---
    [Decimal('0.1')]

## arithmetic

### division rounds to the context, and the digit count matches CPython

```python
(python-run "print(Decimal(1) / Decimal(3))")
```
---
    0.3333333333333333333333333333

### multiplication is exact

```python
(python-run "print(Decimal('1.1') * Decimal('1.1'))")
```
---
    1.21

### from an int

```python
(python-run "print(Decimal(5))")
```
---
    5

### mixed with an int, through the tower

PENDING on the rendering: CPython prints `1.0`, keeping the operand's scale.
x's decimal canonicalizes by stripping trailing zeros, so one value has exactly
one storage form — a deliberate choice in `x/num/decimal`, and the reason `=` is
a pair compare rather than a walk. The arithmetic agrees; the printed form does
not.

```python
(python-run "print(Decimal('0.5') * 2)")
```

### large exponents

PENDING on the rendering: CPython prints `1E+60`, x prints `1e60`. Same value,
different exponent spelling.

```python
(python-run "print(Decimal('1e30') * Decimal('1e30'))")
```
