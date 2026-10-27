## python/line -- the line editor's seams

The editor carries no grammar. Python fills its two seams: `python-paint`
displays a line with the tokenizer's own verdicts on keywords, names, numbers,
operators and strings, and `python-complete` answers an identifier from the
keywords, the builtins and the names defined at the prompt.

### with no terminal, painting returns the line unchanged

```python
(do (import python/line python-paint) (let ((s "def f(x): return x + 1  # c")) (Str8 =? (python-paint s) s)))
```
---
    #t

The completer reads the buffer through one method, `before`, the text to the
left of the cursor; a stand-in with that method is enough to test it, and
lets these cases run on a platform that has no editor to build a buffer with.

### the identifier being completed ends at the cursor

```python
(do (import python/line %py-word-at)
    (def-class %spec-buf () text
      (method before (self) (field (lit text))))
    (%py-word-at (new %spec-buf text "x = pri")))
```
---
    "pri"

### a keyword and a builtin complete from their own tables

```python
(do (import python/line python-complete)
    (let ((r (python-complete (new %spec-buf text "pr"))))
      (list (first r) (List includes? "print" (rest r)))))
```
---
    ("pr" #t)

### a name defined at the prompt completes afterwards

```python
(do (import python/line python-complete python-session-name!)
    (python-session-name! "frobnicate")
    (rest (python-complete (new %spec-buf text "frob"))))
```
---
    ("frobnicate")

## painting

With colour on, each token is wrapped in its colour's code.  The harness has
no terminal, so its codes are empty: these cases force colour on, set the
codes the painter reads to markers, rebuild the palette from them and paint.
The reset the platform painter writes after each coloured span is dropped
first; what the spec pins is which bytes take which colour.  A keyword is
bold magenta, `<b><m>`; a decorator magenta; True, False and None bold red;
a builtin blue, `<n>`; a capitalised name bold cyan, `<C>`; a number yellow;
a string green, `<s>`; a comment dim, `<c>`.

### keywords, builtins, names, numbers, strings and comments each take their colour

```python
(do (import python/line python-paint)
    (eval (lit (set! %ansi? #t)) (module x/repl/ansi))
    (Ansi bold "<b>") (Ansi magenta "<m>") (Ansi bold-red "<R>") (Ansi blue "<n>")
    (Ansi bold-cyan "<C>") (Ansi yellow "<y>") (Ansi green "<s>") (Ansi dim "<c>")
    (eval (lit (%py-line-install!)) (module python/line))
    (def %spec-painted
      (fn (_ s) (Str8 replace "\x1b[0m" "" (python-paint s))))
    (List map %spec-painted
      (list "def f(x): return x + 1  # c"
            "if x: print(\"hi\") # c"
            "class Foo(Bar): pass"
            "True, False, None, len, Foo, foo, _x9"
            "f\"a{b}\" + rb\"\"\"x\"\"\" + 1_000 + 0x1f + 1.5e-3 + .5 + 1e5j")))
```
---
    ("<b><m>def f(x): <b><m>return x + <y>1  <c># c" "<b><m>if x: <n>print(<s>\"hi\") <c># c" "<b><m>class <C>Foo(<C>Bar): <b><m>pass" "<R>True, <R>False, <R>None, <n>len, <C>Foo, foo, _x9" "<s>f\"a{b}\" + <s>rb\"\"\"x\"\"\" + <y>1_000 + <y>0x1f + <y>1.5e-3 + <y>.5 + <y>1e5j")

### strings: prefixes, escapes, triple quotes, and one left open runs to the end

```python
(List map %spec-painted
  (list "r'\\d+' + b'x' + u\"y\" + F\"z\" + BR\"w\" + bu'no'"
        "\"a\\\"b\" + 'c\\'d'"
        "x = \"\"\"abc\"\"\" + 1"
        "x = '''a'b''' + 2"
        "s = 'abc"
        "x = \"unterminated # not a comment"
        "t = \"\"\"open ' \" triple"))
```
---
    ("<s>r'\\d+' + <s>b'x' + <s>u\"y\" + <s>F\"z\" + <s>BR\"w\" + <s>bu'no'" "<s>\"a\\\"b\" + <s>'c\\'d'" "x = <s>\"\"\"abc\"\"\" + <y>1" "x = <s>'''a'b''' + <y>2" "s = <s>'abc" "x = <s>\"unterminated # not a comment" "t = <s>\"\"\"open ' \" triple")

### a comment runs to the end, a decorator is one span, and operators stay plain

```python
(let ((r (List map %spec-painted
           (list "# only a comment"
                 "@property"
                 "a += b // c ** 2 and not d"
                 "x.y(1).z # @no"))))
  (eval (lit (set! %ansi? #f)) (module x/repl/ansi))
  (Ansi bold "") (Ansi magenta "") (Ansi bold-red "") (Ansi blue "")
  (Ansi bold-cyan "") (Ansi yellow "") (Ansi green "") (Ansi dim "")
  (eval (lit (%py-line-install!)) (module python/line))
  r)
```
---
    ("<c># only a comment" "<m>@property" "a += b // c ** <y>2 <b><m>and <b><m>not d" "x.y(<y>1).z <c># @no")
