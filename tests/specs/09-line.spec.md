## python/line -- the line editor's seams

The editor carries no grammar. Python fills its two seams: `%py-paint`
displays a line with the tokenizer's own verdicts on keywords, names, numbers,
operators and strings, and `%py-complete` answers an identifier from the
keywords, the builtins and the names defined at the prompt.

### with no terminal, painting returns the line unchanged

```python
(do (import python/line %py-paint) (let ((s "def f(x): return x + 1  # c")) (Str8 =? (%py-paint s) s)))
```
---
    #t

The completer reads the buffer through one method, `before`, the text to the
left of the cursor; a stand-in with that method is enough to test it, and
lets these cases run on a platform that has no editor to build a buffer with.

### the identifier being completed ends at the cursor

```python
(do (import python/line %py-word-at)
    (def-class %spec-buf () text (method before (self) (member (lit text))))
    (%py-word-at (new %spec-buf text "x = pri")))
```
---
    "pri"

### a keyword and a builtin complete from their own tables

```python
(do (import python/line %py-complete)
    (let ((r (%py-complete (new %spec-buf text "pr"))))
      (list (first r) (List includes? "print" (rest r)))))
```
---
    ("pr" #t)

### a name defined at the prompt completes afterwards

```python
(do (import python/line %py-complete %py-session-name!)
    (%py-session-name! "frobnicate")
    (rest (%py-complete (new %spec-buf text "frob"))))
```
---
    ("frobnicate")
