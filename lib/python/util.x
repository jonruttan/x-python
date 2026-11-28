; # x-python -- Python on x-lang
;
; ## lib/python/util.x -- the list walks the whole bundle does
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

; A sweep after each of the loads this bundle drives.  The load is mostly
; garbage -- 734M objects allocated for 305K live, python/runtime's seven
; files 311M of it -- and the engine sweeps only when asked, so a source
; boot that never asked held all of it, which no 16 GB machine survives.
; Only the code that knows its own quiet points may ask: this bundle roots
; every compiled state it keeps (python/tokens.x), so a module of it can
; sweep between the loads it drives, and its largest files sweep between
; their own sections.
;   A session loaded from a state image skips the sweeps.  Its imports are
; no-ops and its heap is the image's, swept once by the writer; the recache
; hook below runs only after a load (x-lang lib/x/boot/reflect.x), so the
; mark it sets is never in an image, and the writer's child, which loads
; from source, sweeps like any other source boot.
(module python/core)
(import x/core/doors heap-collect int+ int- int< int* int/ str-byte-len)
(def %py-from-image (pair () ()))
(set! %image-recache-hooks
  (pair (fn (_) (%set-first! %py-from-image #t)) %image-recache-hooks))
(def python-sweep!
  (fn (_) (if (first %py-from-image) () (heap-collect))))

; --- collecting while a program runs ------------------------------------------
;
; X COLLECTS ONLY WHEN ASKED (x-lang docs/bundle-checklist.md, G1), and until
; this nothing asked while a program ran: python-sweep! is the boot's, and
; gc.collect() a program's own.  So nothing a program made was ever freed --
; a loop of 100,000 small lists passed 4 GB, and reading a module cost some
; 5 MB a line, which made `import random` 2.4 GB.
;
; So the runtime ticks where work repeats: each item a for loop or a
; comprehension takes, each pass of a while, each call of a def, and each
; statement the parser reads -- the parser's for 64, since a statement read
; makes some 67,000 objects where a loop's step makes some 4,000.  The LEXER
; does not tick: its handlers run inside the C reader, whose own hold on what
; it has read the collector cannot see (python/tokens.x, %py-jit-states, for
; the segfault that taught that), so a module's tokens are made whole and
; their garbage goes at the parser's first collect.
;
; WHEN TO COLLECT is when the heap has grown past %py-gc-next: twice what the
; last collect left, and never less than %py-gc-step past it, so a collect --
; whose cost is what it marks and sweeps, some 150 ms for a heap of 8.7M
; objects that leaves 0.4M -- is paid for by the work that doubled the heap.
; KNOWING it costs a walk: (Heap count) visits every object, some 80 ms at
; 8.7M, and there is no allocation counter to read instead.  So the heap is
; counted every %py-gc-every ticks, and that interval adapts: each count
; measures what the heap grew per tick since the last, and the next is put
; halfway to the mark at that rate.  A cycle between collects counts the heap
; a few times, whatever a tick costs.
;
; A collect is atomic (mark and sweep in one C call) and an x frame is a
; root, so wherever x code is running is a safe place to ask.
(def %py-gc-step 3000000)
(def %py-gc-first-every 64)
; ticks since the last count, the ticks the next count waits for, the heap
; the next collect waits for (0 until the first count), and the last count
(def %py-gc-ticks (pair 0 ()))
(def %py-gc-every (pair 64 ()))
(def %py-gc-next (pair 0 ()))
(def %py-gc-last (pair 0 ()))
(def %py-heap-count (prim-ref (lit heap) (lit count)))
(def python-gc-reset!
  (fn (_)
    (%set-first! %py-gc-ticks 0)
    (%set-first! %py-gc-every %py-gc-first-every)
    (%set-first! %py-gc-next 0)
    (%set-first! %py-gc-last 0)))
; what gc.collect() calls after it collects: a Python callable, or ().
; _weakref sets it, to run the callbacks of the refs the collect killed.
(def python-gc-after (pair () ()))
(def python-gc-now!
  (fn (_)
    (heap-collect)
    (let ((live (%py-heap-count)))
      (%set-first! %py-gc-last live)
      (%set-first! %py-gc-next (int+ live (if (int< live %py-gc-step) %py-gc-step live))))))
; the next interval: halfway to the mark at the rate the heap grew over the
; last one, within 16 and 1M ticks, and never more than four times the last.
; ONE SAMPLE IS NOT A RATE: a count just after a collect sees the heap hardly
; grown -- the first statement after the lexer's last collect grew it by 460
; objects -- and taking that at its word put the next count 200,000 ticks
; off, past the end of a 1,000-line module's parse, which then never
; collected.  Growing by at most four a count still reaches any interval in
; a few counts.
(def %py-gc-pace!
  (fn (_ n every)
    (let ((grew (int- n (first %py-gc-last))) (left (int- (first %py-gc-next) n)))
      (let ((e (if (int< grew 1) (int* every 2) (int/ (int* every left) (int* grew 2))))
            (most (int* every 4)))
        (let ((e (if (int< most e) most e)))
          (%set-first! %py-gc-every (if (int< e 16) 16 (if (int< 1048576 e) 1048576 e))))))))
(def %py-gc-check!
  (fn (_)
    (let ((every (first %py-gc-every)) (n (%py-heap-count)))
      (%set-first! %py-gc-ticks 0)
      (if (int< (first %py-gc-next) 1)
        (do (%set-first! %py-gc-next (int+ n %py-gc-step)) (%set-first! %py-gc-last n))
        (if (int< n (first %py-gc-next))
          (do (%py-gc-pace! n every) (%set-first! %py-gc-last n))
          (do (python-gc-now!) (%set-first! %py-gc-every every)))))))
(def python-gc-ticks!
  (fn (_ k)
    (let ((t (int+ (first %py-gc-ticks) k)))
      (if (int< t (first %py-gc-every)) (%set-first! %py-gc-ticks t) (%py-gc-check!)))))
(def python-gc-tick! (fn (_) (python-gc-ticks! 1)))

; Reverse-prepend: the accumulate-and-reverse list builder.  Every walk in the bundle
; accumulates front-to-back and reverses once, so this is the pattern underneath
; both names below -- and it is worth having spelled out, because
; `(%py-append (python-reverse xs) acc)` is `(python-rev-onto xs acc)` without the
; intermediate list.
(def python-rev-onto
  (fn (self xs acc)
    (if (null? xs) acc (self (rest xs) (pair (first xs) acc)))))

(def python-reverse (fn (_ xs) (python-rev-onto xs ())))

; The integer doors, for counts and positions only: a length, an index
; clamped to one, a byte count a read returned.  A door is 0 or 1 objects a
; call where the platform's + is ~90 and - ~110, and it neither checks its
; operands (nil segfaults) nor promotes past a word, so a value a program
; supplied never reaches one.
(def %py-fx+ int+)
(def python-fx- int-)
(def python-fx< int<)
(def %py-fx* int*)

(def %py-count-from
  (fn (self xs n)
    (if (null? xs) n (self (rest xs) (%py-fx+ n 1)))))

(def python-length (fn (_ xs) (%py-count-from xs 0)))

; Append and take, which the parser and the runtime both walk with.
(def %py-append
  (fn (self a b)
    (if (null? a) b (pair (first a) (self (rest a) b)))))
(def python-take
  (fn (self n l)
    (if (= n 0) () (if (null? l) () (pair (first l) (self (python-fx- n 1) (rest l)))))))

; A string's length through the raw byte door, not the Str8 class: the class
; call is ~15,000 objects, the primitive is at the floor, and the number
; converters ask it once per literal.
(def python-byte-len str-byte-len)

; The implementation version, here rather than in python/sys: python-version
; reads it when the core loads, before the libraries.
(def python-implementation-version "0.0.1")
