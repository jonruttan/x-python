; # x-python -- Python on x-lang
;
; ## python/lexer.x -- the Lexer rules that colour Python
;
; @description One set of Lexer rules for colouring Python, read by the
;   line editor's painter and by the highlighting grammar alike.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Python's tokenizer is a second base: it answers tokens, not spans, and it
; stops at an unterminated string, which is the normal state of a line being
; typed or of a window onto a file.  These rules read every byte instead.
; Blanks are a run, and a bracket or an operator is one byte under `plain`,
; so a painter draws a line byte for byte with the author's spacing.  A
; string is one token with its prefix: a single-quoted one a nested span
; whose body takes a backslash escape, a triple-quoted one an until span,
; which ends at its first whole `"""` or `'''`.  Both run to the end of the
; text while unclosed, and so does a comment.  A Lexer literal is bytes, so
; each prefix -- r, b, u, f, rb, br, fr and rf -- opens with a literal of its
; own, and a prefix with no quote after it is a name.  Lowercase only: every
; literal adds string states, and the plan the Lexer records for its cache
; group is quadratic in the states.  The 25 prefixes of both cases made 686
; states and a 3.0 GB first prompt on an empty code cache; these 9 make 254
; and 0.73 GB.  An uppercase prefix paints as a name, then its string.
;
; The tags: blank, comment, string, number, name, decorator and plain.  The
; module imports x-lang libraries only, so a process colouring a file loads
; it without the interpreter.
(module python/lexer)
(import x/type/list)
(import x/type/str)
(import x/reader/lexer)

(def %py-lex-ident-start (list 95 (pair 65 90) (pair 97 122) (pair 128 255) (pair -128 -1)))
(def %py-lex-ident (list 95 (pair 48 57) (pair 65 90) (pair 97 122) (pair 128 255) (pair -128 -1)))
(def %py-lex-digits (list (pair 48 57)))
; a number's body: digits, letters, underscores and dots, so 0x1f, 1_000,
; 1e5j and 1.5 are each one token
(def %py-lex-num-body (list 46 95 (pair 48 57) (pair 65 90) (pair 97 122)))
; the body before an exponent letter, so the sign after it is read as well
(def %py-lex-num-mantissa (list 46 95 (pair 48 57)))

(def %py-lex-prefixes
  (list "" "r" "b" "u" "f" "rb" "br" "fr" "rf"))

(def %py-lex-bref (prim-ref (lit str) (lit byte-ref)))
(def %py-lex-cint (prim-ref (lit char) (lit ->int)))

(def %py-lex-string-rules
  (fn (_)
    (List flat-map
      (fn (_ p)
        (List flat-map
          (fn (_ q)
            (let ((q3 (Str8 append q q q)))
              (list (Lexer until (lit string) (Str8 append p q3) q3 (lit to-end))
                    (Lexer nested (lit string) (Str8 append p q) (lit body)
                      (list (list (lit body) (%py-lex-cint (%py-lex-bref q 0)) 92 ())) (lit to-end)))))
          (list "\"" "'")))
      %py-lex-prefixes)))

; A number is digits, or a dot before a digit, then its body; the second
; pattern of each pair reads an exponent's sign, which the body alone would
; leave, and wins by length when there is one.
(def python-lexer-rules
  (fn (_)
    (List append
      (list (Lexer run (lit blank) " \t\r\n" " \t\r\n")
            (Lexer until (lit comment) "#" "\n" (lit to-end)))
      (%py-lex-string-rules)
      (list
        (Lexer pattern (lit number)
          (list (list %py-lex-digits 1 1) (list %py-lex-num-body 0 ())))
        (Lexer pattern (lit number)
          (list (list %py-lex-digits 1 1) (list %py-lex-num-mantissa 0 ()) (list "eE" 1 1)
                (list "+-" 1 1) (list %py-lex-num-body 0 ())))
        (Lexer pattern (lit number)
          (list (list "." 1 1) (list %py-lex-digits 1 1) (list %py-lex-num-body 0 ())))
        (Lexer pattern (lit number)
          (list (list "." 1 1) (list %py-lex-digits 1 1) (list %py-lex-num-mantissa 0 ()) (list "eE" 1 1)
                (list "+-" 1 1) (list %py-lex-num-body 0 ())))
        (Lexer run (lit name) %py-lex-ident-start %py-lex-ident)
        (Lexer pattern (lit decorator)
          (list (list "@" 1 1) (list %py-lex-ident-start 1 1) (list %py-lex-ident 0 ())))
        (Lexer any (lit plain))))))

(provide python/lexer python-lexer-rules)
