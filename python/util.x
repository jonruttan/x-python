; # x-python -- Python on x-lang
;
; ## python/util.x -- the two list walks the whole bundle does
;
; @description Bundle-local `reverse` and `length`, because the List class's
;   are built on `List fold` and that costs 53,000 objects a call.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; WHY THIS FILE EXISTS, in one measurement.  Every accumulate-and-reverse walk
; in this bundle ended in `(List reverse acc)`, and the parser is nothing but
; such walks -- there were 51 of them in python/parse.x alone.  Measured on the
; spec harness with (Sys time) and (Heap count), one call, empty argument:
;
;     (List reverse ())        3369us    60,342 objects
;     (List length  ())        3489us    59,380 objects
;     the same, written here      45us     4,782 objects
;
; The list is EMPTY in all three, so this is not the walk -- it is the entry.
; `List reverse` is `(List fold (fn (_ acc x) (pair x acc)) () lst)` and
; `List length` is `List fold` counting, and `(List fold f () ())` alone
; measures 3086us and 52,982 objects, the same on its second call as its
; first, while the boot layer's own `%fold` over the same nil measures 47us
; and 4,825.  So it is `List fold` specifically, it does not warm up, and
; everything the class builds on it inherits it.  `List ref` is NOT built on
; fold (15,591 objects) and is left alone.
;
; This is a PLATFORM cost and the platform is where it should be fixed; until
; it is, a bundle that parses through these walks cannot pay it 51 times per
; parse.  Nothing here is a new algorithm -- both are the same accumulate walk
; the boot layer's %rev-onto uses, spelled in the bundle so it owes the
; platform's class internals nothing.
;
; PROPER LISTS ONLY, and that is the whole difference in contract.  `List
; reverse` and `List length` take any iterable and normalize through
; `List from-seq`; these take a list or nil, which is what all 131 call sites
; passed.  A call that wants an iterable should still say `List`.

(provide python/util %py-reverse %py-rev-onto %py-length)

; Reverse-prepend: the tail-shape list builder.  Every walk in the bundle
; accumulates front-to-back and reverses once, so this is the shape underneath
; both names below -- and it is worth having spelled out, because
; `(%py-append (%py-reverse xs) acc)` is `(%py-rev-onto xs acc)` without the
; intermediate list.
(def %py-rev-onto
  (fn (self xs acc)
    (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))

(def %py-reverse (fn (_ xs) (%py-rev-onto xs ())))

(def %py-count-from
  (fn (self xs n)
    (if (null? xs) n (self (rest xs) (+ n 1)))))

(def %py-length (fn (_ xs) (%py-count-from xs 0)))
