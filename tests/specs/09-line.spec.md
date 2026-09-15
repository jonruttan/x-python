## python/line -- the line editor's seams

The editor carries no grammar. Python fills its two seams: `%py-paint`
displays a line with the tokenizer's own verdicts on keywords, names, numbers,
operators and strings, and `%py-complete` answers an identifier from the
keywords, the builtins and the names defined at the prompt.

### with no terminal, painting returns the line unchanged

```python
(do (import python/line) (let ((s "def f(x): return x + 1  # c")) (Str8 =? (%py-paint s) s)))
```
---
    #t

### the identifier being completed ends at the cursor

```python
(do (import python/line)
    (let ((ed (Edit make)))
      (ed insert! "x = pri")
      (%py-word-at ed)))
```
---
    "pri"

### a keyword and a builtin complete from their own tables

```python
(do (import python/line)
    (let ((ed (Edit make)))
      (ed insert! "pr")
      (let ((r (%py-complete ed)))
        (list (first r) (List includes? "print" (rest r))))))
```
---
    ("pr" #t)

### a name defined at the prompt completes afterwards

```python
(do (import python/line)
    (set! %py-session-names (pair "frobnicate" %py-session-names))
    (let ((ed (Edit make)))
      (ed insert! "frob")
      (rest (%py-complete ed))))
```
---
    ("frobnicate")
