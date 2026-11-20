# golden: one program's tokens and tree

`tests/golden/shapes.py` is a fixed program with one of each layout the
tokenizer and the parser decide: a comment, an import, a class with methods,
defaults and a star parameter, an if ladder, an f-string, a comprehension over
a tuple target, an augmented assignment, a dict comprehension and a based
number. Its token stream and the forms the parser emits for it are saved
here whole, one a line, so a change to either is seen as the lines it moved.

A changed line is not a failure of the bundle by itself: it is a change to
what the engine's reader or a dialect hands this parser, or to the parser,
and the diff says which tokens or forms it reached. Re-record a block only
with the change that explains it.

## the token stream

### every token of the program, in order

```python
(%seq
  (def %gold-lines
    (fn (self l)
      (if (null? l) () (%seq (write (first l)) (%seq (newline) (self (rest l)))))))
  (%gold-lines (python-tokenize (File read-all "tests/golden/shapes.py"))))
```
---
```output
('tok-newline)
('tok-kw "import")
('tok-name "math")
('tok-newline)
('tok-kw "class")
('tok-name "Shape")
('tok-op ":")
('tok-block (('tok-kw "def") ('tok-name "__init__") ('tok-group "(" (('tok-name "self") ('tok-op ",") ('tok-name "name") ('tok-op ",") ('tok-name "sides") ('tok-op "=") ('tok-number "0" 1)) ")") ('tok-op ":") ('tok-block (('tok-name "self") ('tok-op ".") ('tok-name "name") ('tok-op "=") ('tok-name "name") ('tok-newline) ('tok-name "self") ('tok-op ".") ('tok-name "sides") ('tok-op "=") ('tok-name "sides"))) ('tok-kw "def") ('tok-name "describe") ('tok-group "(" (('tok-name "self")) ")") ('tok-op ":") ('tok-block (('tok-kw "return") ('tok-fstring (123 115 101 108 102 46 110 97 109 101 125 58 32 123 115 101 108 102 46 115 105 100 101 115 125 32 115 105 100 101 115))))))
('tok-kw "def")
('tok-name "area")
('tok-group "(" (('tok-name "kind") ('tok-op ",") ('tok-op "*") ('tok-name "dims")) ")")
('tok-op ":")
('tok-block (('tok-kw "if") ('tok-name "kind") ('tok-op "==") ('tok-string (99 105 114 99 108 101)) ('tok-op ":") ('tok-block (('tok-kw "return") ('tok-name "math") ('tok-op ".") ('tok-name "pi") ('tok-op "*") ('tok-name "dims") ('tok-group "[" (('tok-number "0" 1)) "]") ('tok-op "**") ('tok-number "2" 1))) ('tok-kw "elif") ('tok-name "kind") ('tok-op "==") ('tok-string (114 101 99 116)) ('tok-op ":") ('tok-block (('tok-kw "return") ('tok-name "dims") ('tok-group "[" (('tok-number "0" 1)) "]") ('tok-op "*") ('tok-name "dims") ('tok-group "[" (('tok-number "1" 1)) "]"))) ('tok-kw "else") ('tok-op ":") ('tok-block (('tok-kw "raise") ('tok-name "ValueError") ('tok-group "(" (('tok-string (117 110 107 110 111 119 110 32)) ('tok-op "+") ('tok-name "kind")) ")")))))
('tok-name "shapes")
('tok-op "=")
('tok-group "[" (('tok-name "Shape") ('tok-group "(" (('tok-name "n") ('tok-op ",") ('tok-name "s")) ")") ('tok-kw "for") ('tok-name "n") ('tok-op ",") ('tok-name "s") ('tok-kw "in") ('tok-group "(" (('tok-group "(" (('tok-string (116 114 105 97 110 103 108 101)) ('tok-op ",") ('tok-number "3" 1)) ")") ('tok-op ",") ('tok-group "(" (('tok-string (115 113 117 97 114 101)) ('tok-op ",") ('tok-number "4" 1)) ")")) ")")) "]")
('tok-newline)
('tok-name "total")
('tok-op "=")
('tok-number "0" 1)
('tok-newline)
('tok-kw "for")
('tok-name "s")
('tok-kw "in")
('tok-name "shapes")
('tok-op ":")
('tok-block (('tok-name "total") ('tok-op "+=") ('tok-name "s") ('tok-op ".") ('tok-name "sides")))
('tok-name "print")
('tok-group "(" (('tok-name "total") ('tok-op ",") ('tok-group "{" (('tok-name "s") ('tok-op ".") ('tok-name "name") ('tok-op ":") ('tok-name "s") ('tok-op ".") ('tok-name "sides") ('tok-kw "for") ('tok-name "s") ('tok-kw "in") ('tok-name "shapes")) "}") ('tok-op ",") ('tok-name "area") ('tok-group "(" (('tok-string (114 101 99 116)) ('tok-op ",") ('tok-number "2" 1) ('tok-op ",") ('tok-number "0x10" 4)) ")")) ")")
```

## the parsed tree

### every form the parser emits, in order

```python
(%gold-lines (python-parse (File read-all "tests/golden/shapes.py")))
```
---
```output
('%py-hoist 'py-math '%py-deleted)
('%py-hoist 'py-Shape '%py-deleted)
('%py-hoist 'py-__init__ '%py-deleted)
('%py-hoist 'py-self '%py-deleted)
('%py-hoist 'py-name '%py-deleted)
('%py-hoist 'py-sides '%py-deleted)
('%py-hoist 'py-describe '%py-deleted)
('%py-hoist 'py-area '%py-deleted)
('%py-hoist 'py-pi '%py-deleted)
('%py-hoist 'py-n '%py-deleted)
('%py-hoist 'py-Shape '%py-deleted)
('%py-hoist 'py-shapes '%py-deleted)
('%py-hoist 'py-total '%py-deleted)
('%py-hoist 'py-s '%py-deleted)
('do ('set! 'py-math ('%py-imp '%py-import-call "math" ('lit ()) 0 ('%py-ns-here))))
('set! 'py-Shape ('%py-class-build '%py-build-class "Shape" ('list) ('fn ('_ '%py-bases) ('let (('%py-crows ('pair () ()))) ('%seq ('do ('%py-crow-put! '%py-crows "__init__" ('let (('%py-d0 0)) ('python-sig! ('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "__init__" '%py-more ('list "self" "name")) ('%seq ('%py-arity! "__init__" '%py-more 2 1) ('let (('py-self ('List 'ref 0 '%py-more)) ('py-name ('List 'ref 1 '%py-more)) ('py-sides ('python-opt '%py-more 2 '%py-d0))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%seq ('%py-setattr 'py-self "name" 'py-name) ('%py-setattr 'py-self "sides" 'py-sides)) ()))))))) "__init__" ('list "self" "name" "sides") 2 #f () ('list) #t ('%py-here) ('lit (('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "__init__" '%py-more ('list "self" "name" "sides")) ('%seq ('%py-arity! "__init__" '%py-more 3 0) ('let (('py-self ('List 'ref 0 '%py-more)) ('py-name ('List 'ref 1 '%py-more)) ('py-sides ('List 'ref 2 '%py-more))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%seq ('%py-setattr 'py-self "name" 'py-name) ('%py-setattr 'py-self "sides" 'py-sides)) ()))))))) "__init__" ("self" "name" "sides") 3 #f () ()))))) ('%py-crow-put! '%py-crows "describe" ('python-sig! ('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "describe" '%py-more ('list "self")) ('%seq ('%py-arity! "describe" '%py-more 1 0) ('let (('py-self ('List 'ref 0 '%py-more))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%py-return ('python-str-of-x ('%py-fjoin ('list ('%py-fmtfield ('%py-getattr 'py-self "name") "" "") ": " ('%py-fmtfield ('%py-getattr 'py-self "sides") "" "") " sides")))) ()))))))) "describe" ('list "self") 1 #f () ('list) #t ('%py-here) ('lit (('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "describe" '%py-more ('list "self")) ('%seq ('%py-arity! "describe" '%py-more 1 0) ('let (('py-self ('List 'ref 0 '%py-more))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%py-return ('python-str-of-x ('%py-fjoin ('list ('%py-fmtfield ('%py-getattr 'py-self "name") "" "") ": " ('%py-fmtfield ('%py-getattr 'py-self "sides") "" "") " sides")))) ()))))))) "describe" ("self") 1 #f () ())))) ()) ('%py-mkclass "Shape" '%py-bases ('python-reverse ('first '%py-crows))))))))
('set! 'py-area ('python-sig! ('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "area" '%py-more ('list "kind")) ('let (('py-kind ('List 'ref 0 '%py-more)) ('py-dims ('python-tuple-of-list ('python-drop '%py-more 1)))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 99 105 114 99 108 101)))) ('%py-return ('python-mul ('%py-getattr ('%py-name-live "math" 'py-math) "pi") ('%py-pow ('%py-index 'py-dims 0) 2))) ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 114 101 99 116)))) ('%py-return ('python-mul ('%py-index 'py-dims 0) ('%py-index 'py-dims 1))) ('%py-raise-any ('%py-call 'python-exc-ValueError ('python-add ('python-str-new ('list 117 110 107 110 111 119 110 32)) 'py-kind))))) ())))))) "area" ('list "kind") 1 #t () ('list) #t ('%py-here) ('lit (('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "area" '%py-more ('list "kind")) ('let (('py-kind ('List 'ref 0 '%py-more)) ('py-dims ('python-tuple-of-list ('python-drop '%py-more 1)))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 99 105 114 99 108 101)))) ('%py-return ('python-mul ('%py-getattr ('%py-name-live "math" 'py-math) "pi") ('%py-pow ('%py-index 'py-dims 0) 2))) ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 114 101 99 116)))) ('%py-return ('python-mul ('%py-index 'py-dims 0) ('%py-index 'py-dims 1))) ('%py-raise-any ('%py-call 'python-exc-ValueError ('python-add ('python-str-new ('list 117 110 107 110 111 119 110 32)) 'py-kind))))) ())))))) "area" ("kind") 1 #t () ()))))
('set! 'py-shapes ('let (('%py-acc ('pair () ()))) ('%seq ('%py-comp-each ('%py-iter-open ('%py-mktuple ('%py-mktuple ('python-str-new ('list 116 114 105 97 110 103 108 101)) 3) ('%py-mktuple ('python-str-new ('list 115 113 117 97 114 101)) 4))) ('fn ('_ '%py-item) ('let (('%py-unpacked ('%py-unpack '%py-item 2))) ('let (('py-n ('first '%py-unpacked)) ('py-s ('first ('rest '%py-unpacked)))) ('%set-first! '%py-acc ('pair ('%py-call ('%py-name-live "Shape" 'py-Shape) 'py-n 'py-s) ('first '%py-acc))))))) ('python-list-new ('List 'reverse ('first '%py-acc))))))
('set! 'py-total 0)
(('fn ('self '%py-src) ('let (('%py-item ('%py-iter-pull! '%py-src))) ('if ('same? '%py-item '%py-gen-done) () ('%seq ('set! 'py-s '%py-item) ('%seq ('set! 'py-total ('%py-iadd 'py-total ('%py-getattr 'py-s "sides"))) ('self '%py-src)))))) ('%py-iter-open 'py-shapes))
('%py-call '%py-print 'py-total ('let (('%py-acc ('%py-mkdict))) ('%seq ('%py-comp-each ('%py-iter-open 'py-shapes) ('fn ('_ 'py-s) ('%py-dset '%py-acc ('%py-getattr 'py-s "name") ('%py-getattr 'py-s "sides")))) '%py-acc)) ('%py-call ('%py-name-live "area" 'py-area) ('python-str-new ('list 114 101 99 116)) 2 16))
```

### a second parse in the same process emits the same forms

```python
(%gold-lines (python-parse (File read-all "tests/golden/shapes.py")))
```
---
```output
('%py-hoist 'py-math '%py-deleted)
('%py-hoist 'py-Shape '%py-deleted)
('%py-hoist 'py-__init__ '%py-deleted)
('%py-hoist 'py-self '%py-deleted)
('%py-hoist 'py-name '%py-deleted)
('%py-hoist 'py-sides '%py-deleted)
('%py-hoist 'py-describe '%py-deleted)
('%py-hoist 'py-area '%py-deleted)
('%py-hoist 'py-pi '%py-deleted)
('%py-hoist 'py-n '%py-deleted)
('%py-hoist 'py-Shape '%py-deleted)
('%py-hoist 'py-shapes '%py-deleted)
('%py-hoist 'py-total '%py-deleted)
('%py-hoist 'py-s '%py-deleted)
('do ('set! 'py-math ('%py-imp '%py-import-call "math" ('lit ()) 0 ('%py-ns-here))))
('set! 'py-Shape ('%py-class-build '%py-build-class "Shape" ('list) ('fn ('_ '%py-bases) ('let (('%py-crows ('pair () ()))) ('%seq ('do ('%py-crow-put! '%py-crows "__init__" ('let (('%py-d0 0)) ('python-sig! ('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "__init__" '%py-more ('list "self" "name")) ('%seq ('%py-arity! "__init__" '%py-more 2 1) ('let (('py-self ('List 'ref 0 '%py-more)) ('py-name ('List 'ref 1 '%py-more)) ('py-sides ('python-opt '%py-more 2 '%py-d0))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%seq ('%py-setattr 'py-self "name" 'py-name) ('%py-setattr 'py-self "sides" 'py-sides)) ()))))))) "__init__" ('list "self" "name" "sides") 2 #f () ('list) #t ('%py-here) ('lit (('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "__init__" '%py-more ('list "self" "name" "sides")) ('%seq ('%py-arity! "__init__" '%py-more 3 0) ('let (('py-self ('List 'ref 0 '%py-more)) ('py-name ('List 'ref 1 '%py-more)) ('py-sides ('List 'ref 2 '%py-more))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%seq ('%py-setattr 'py-self "name" 'py-name) ('%py-setattr 'py-self "sides" 'py-sides)) ()))))))) "__init__" ("self" "name" "sides") 3 #f () ()))))) ('%py-crow-put! '%py-crows "describe" ('python-sig! ('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "describe" '%py-more ('list "self")) ('%seq ('%py-arity! "describe" '%py-more 1 0) ('let (('py-self ('List 'ref 0 '%py-more))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%py-return ('python-str-of-x ('%py-fjoin ('list ('%py-fmtfield ('%py-getattr 'py-self "name") "" "") ": " ('%py-fmtfield ('%py-getattr 'py-self "sides") "" "") " sides")))) ()))))))) "describe" ('list "self") 1 #f () ('list) #t ('%py-here) ('lit (('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "describe" '%py-more ('list "self")) ('%seq ('%py-arity! "describe" '%py-more 1 0) ('let (('py-self ('List 'ref 0 '%py-more))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('%py-return ('python-str-of-x ('%py-fjoin ('list ('%py-fmtfield ('%py-getattr 'py-self "name") "" "") ": " ('%py-fmtfield ('%py-getattr 'py-self "sides") "" "") " sides")))) ()))))))) "describe" ("self") 1 #f () ())))) ()) ('%py-mkclass "Shape" '%py-bases ('python-reverse ('first '%py-crows))))))))
('set! 'py-area ('python-sig! ('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "area" '%py-more ('list "kind")) ('let (('py-kind ('List 'ref 0 '%py-more)) ('py-dims ('python-tuple-of-list ('python-drop '%py-more 1)))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 99 105 114 99 108 101)))) ('%py-return ('python-mul ('%py-getattr ('%py-name-live "math" 'py-math) "pi") ('%py-pow ('%py-index 'py-dims 0) 2))) ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 114 101 99 116)))) ('%py-return ('python-mul ('%py-index 'py-dims 0) ('%py-index 'py-dims 1))) ('%py-raise-any ('%py-call 'python-exc-ValueError ('python-add ('python-str-new ('list 117 110 107 110 111 119 110 32)) 'py-kind))))) ())))))) "area" ('list "kind") 1 #t () ('list) #t ('%py-here) ('lit (('fn ('%py-fn . '%py-more) ('%seq ('%py-need! "area" '%py-more ('list "kind")) ('let (('py-kind ('List 'ref 0 '%py-more)) ('py-dims ('python-tuple-of-list ('python-drop '%py-more 1)))) ('%py-escape ('fn ('_ '%py-return) ('%seq ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 99 105 114 99 108 101)))) ('%py-return ('python-mul ('%py-getattr ('%py-name-live "math" 'py-math) "pi") ('%py-pow ('%py-index 'py-dims 0) 2))) ('if ('%py-truthy ('python-eq 'py-kind ('python-str-new ('list 114 101 99 116)))) ('%py-return ('python-mul ('%py-index 'py-dims 0) ('%py-index 'py-dims 1))) ('%py-raise-any ('%py-call 'python-exc-ValueError ('python-add ('python-str-new ('list 117 110 107 110 111 119 110 32)) 'py-kind))))) ())))))) "area" ("kind") 1 #t () ()))))
('set! 'py-shapes ('let (('%py-acc ('pair () ()))) ('%seq ('%py-comp-each ('%py-iter-open ('%py-mktuple ('%py-mktuple ('python-str-new ('list 116 114 105 97 110 103 108 101)) 3) ('%py-mktuple ('python-str-new ('list 115 113 117 97 114 101)) 4))) ('fn ('_ '%py-item) ('let (('%py-unpacked ('%py-unpack '%py-item 2))) ('let (('py-n ('first '%py-unpacked)) ('py-s ('first ('rest '%py-unpacked)))) ('%set-first! '%py-acc ('pair ('%py-call ('%py-name-live "Shape" 'py-Shape) 'py-n 'py-s) ('first '%py-acc))))))) ('python-list-new ('List 'reverse ('first '%py-acc))))))
('set! 'py-total 0)
(('fn ('self '%py-src) ('let (('%py-item ('%py-iter-pull! '%py-src))) ('if ('same? '%py-item '%py-gen-done) () ('%seq ('set! 'py-s '%py-item) ('%seq ('set! 'py-total ('%py-iadd 'py-total ('%py-getattr 'py-s "sides"))) ('self '%py-src)))))) ('%py-iter-open 'py-shapes))
('%py-call '%py-print 'py-total ('let (('%py-acc ('%py-mkdict))) ('%seq ('%py-comp-each ('%py-iter-open 'py-shapes) ('fn ('_ 'py-s) ('%py-dset '%py-acc ('%py-getattr 'py-s "name") ('%py-getattr 'py-s "sides")))) '%py-acc)) ('%py-call ('%py-name-live "area" 'py-area) ('python-str-new ('list 114 101 99 116)) 2 16))
```
