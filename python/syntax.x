; # x-python -- Python on x-lang
;
; ## python/syntax.x -- the Python highlighting grammar
;
; @description The grammar x/tool/syntax colours Python files with: the line
;   editor's Lexer rules, with names classed as keywords, constants,
;   builtins and classes.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; lang.xon's (grammar python ...) form names this module, and x/tool/syntax
; imports it the first time a file needs the grammar, in whatever process is
; colouring: vi's, a REPL's, an HTML renderer's.  So it imports x-lang
; libraries and python/lexer, never the interpreter, and the words it colours
; are its own copy of the interpreter's tables.  A spec holds the two to the
; same words.
;
; A name is classed as the line editor's painter classes it: a keyword, then
; True, False and None as constants, then a builtin, then a leading capital
; as a class.  A decorator is a keyword.  A bracket, a comma, a colon, a
; semicolon or a dot is punctuation, every other plain byte an operator.

(module python/syntax)
(import x/type/list)
(import x/type/str)
(import x/tool/syntax)
(import python/lexer python-lexer-rules)

; The keywords python/tokens.x reads, as python-keywords lists them.
(def python-syntax-keywords
  (list "if" "elif" "else" "while" "def" "return" "pass" "and" "or" "not"
        "in" "is" "for" "break" "continue" "class" "import" "from" "as"
        "try" "except" "finally" "raise" "with" "lambda" "global" "nonlocal"
        "assert" "del" "yield" "async" "await"))

(def python-syntax-constants (list "True" "False" "None"))

; The builtins python/parse.x's python-builtins table names, each once, in
; the table's order, less the constants.
(def python-syntax-builtins
  (list "print" "__debug__" "len" "range" "slice" "str" "repr" "list" "hasattr"
        "object" "bytes" "staticmethod" "classmethod" "property" "type" "int"
        "float" "bool" "dict" "tuple" "isinstance" "pow" "abs" "round" "min"
        "max" "bytearray" "memoryview" "complex" "hash" "NotImplemented"
        "Ellipsis" "eval" "exec" "compile" "dir" "globals" "locals" "vars" "chr"
        "ord" "StopIteration" "StopAsyncIteration" "GeneratorExit" "next" "sum"
        "map" "zip" "all" "any" "sorted" "iter" "set" "frozenset" "bin" "hex"
        "oct" "divmod" "callable" "__import__" "__build_class__" "id" "getattr"
        "setattr" "delattr" "issubclass" "enumerate" "filter" "reversed"
        "SystemExit" "BaseException" "Exception" "ImportError"
        "ModuleNotFoundError" "OSError" "FileNotFoundError" "PermissionError"
        "FileExistsError" "IsADirectoryError" "open" "IOError" "EOFError"
        "KeyboardInterrupt" "IndentationError" "UnicodeError"
        "UnicodeDecodeError" "UnicodeEncodeError" "MemoryError" "OverflowError"
        "NotImplementedError" "ArithmeticError" "LookupError"
        "ZeroDivisionError" "IndexError" "KeyError" "AttributeError" "NameError"
        "UnboundLocalError" "TypeError" "ValueError" "AssertionError"
        "RuntimeError" "SyntaxError"))

(import x/core/doors str-byte-ref char->int str-byte-len)
(def %py-syntax-byte (fn (_ s i) (char->int (str-byte-ref s i))))
(def %py-syntax-upper? (fn (_ b) (if (>= b 65) (<= b 90) #f)))
(def %py-syntax-lower? (fn (_ b) (if (>= b 97) (<= b 122) #f)))

(def %py-syntax-name-class
  (fn (_ text)
    (match
      ((List includes? text python-syntax-keywords) (lit keyword))
      ((List includes? text python-syntax-constants) (lit constant))
      ((List includes? text python-syntax-builtins) (lit name))
      ((%py-syntax-upper? (%py-syntax-byte text 0)) (lit class))
      (#t ()))))

; ( ) , . : ; [ ] { }
(def %py-syntax-punct (list 40 41 44 46 58 59 91 93 123 125))

; A blank is plain only at the text's end, where the blank run meets the
; Lexer's end text and is not a token; it has no class.
(def %py-syntax-plain-class
  (fn (_ text)
    (let ((b (%py-syntax-byte text 0)))
      (match
        ((<= b 32) ())
        ((List includes? b %py-syntax-punct) (lit punct))
        (#t (lit operator))))))

; A line starting with a name, a comment or a decorator at its first column
; is taken to start outside any string, so spans need not read the file from
; its top.  A triple-quoted string with such a line in it colours inverted
; from that line to the end of the window, as other editors' Python grammars
; do.
(def %py-syntax-sync
  (fn (_ s ls)
    (if (>= ls (str-byte-len s)) #f
      (let ((b (%py-syntax-byte s ls)))
        (match
          ((List includes? b (list 35 64 95)) #t)
          ((%py-syntax-upper? b) #t)
          (#t (%py-syntax-lower? b)))))))

(Syntax register!
  (let ((g (Syntax make (lit python) (python-lexer-rules)
             (list (pair (lit comment) (lit comment))
                   (pair (lit string) (lit string))
                   (pair (lit number) (lit number))
                   (pair (lit decorator) (lit keyword))
                   (pair (lit name) %py-syntax-name-class)
                   (pair (lit plain) %py-syntax-plain-class)))))
    (g sync %py-syntax-sync)
    g))

(provide python/syntax python-syntax-keywords python-syntax-constants python-syntax-builtins)
