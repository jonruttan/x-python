; # x-python -- Python on x-lang
;
; ## python/io.x -- the io module
;
; @description StringIO and BytesIO, two names for one stream: a list of
;   elements, a position in it, and a closed flag.  The elements are code
;   points for the text one and bytes for the binary one, which is the only
;   difference between them -- what read and getvalue hand back, and what
;   write takes apart.  A file open() answers is that stream over a
;   descriptor, read a chunk at a time as it is asked for and written as it
;   is written to.  And the classes of the standard streams sys holds.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; A stream constructed from a buffer COPIES it: writing into the stream must
; not reach the bytes it was built from, which is what io_bytesio_cow asks.

(module python/io)

(def %py-io ())
(def %py-io-new
  (fn (_ text? buf) (%make-instance %py-io (list text? (list buf) (list 0) (list #f)))))
(def %py-io-is (fn (_ v) (%type? v %py-io)))
(def %py-io-text? (fn (_ v) (first (first v))))
(def %py-io-buf (fn (_ v) (first (List ref 1 (first v)))))
(def %py-io-buf! (fn (_ v b) (%seq (%set-first! (List ref 1 (first v)) b) ())))
(def %py-io-pos (fn (_ v) (first (List ref 2 (first v)))))
(def %py-io-pos! (fn (_ v p) (%seq (%set-first! (List ref 2 (first v)) p) ())))
(def %py-io-closed? (fn (_ v) (first (List ref 3 (first v)))))

; A file is the same stream over a descriptor (%py-open below).  A fifth
; field holds what it was opened as, (NAME MODE ENCODING), and a sixth what
; reading it keeps:
;
;   0 the descriptor        5 (ENCODING ERRORS NEWLINE), for text
;   1 bytes not yet decoded 6 the string each read fills
;   2 whether the end came  7 whether it reads
;   3 the position the      8 whether it writes
;     buffer starts at
;   4 whether a \r waits
;     for what follows it
;
; The buffer holds what was read and not yet taken, so a file costs what is
; asked of it.  An in-memory stream has neither field, and its buffer starts
; at 0.
(def %py-io-chunk 8192)
(def %py-io-make (prim-ref (lit str) (lit make)))
(def %py-io-bref (prim-ref (lit str) (lit byte-ref)))
(def %py-io-code (prim-ref (lit char) (lit ->int)))
(def %py-io-file-new
  (fn (_ text? info fd decode reads? writes? at)
    (%make-instance %py-io
      (list text? (list ()) (list at) (list #f) info
        (list fd () #f at #f decode (%py-io-make %py-io-chunk) reads? writes?)))))
(def %py-io-info
  (fn (_ v)
    (let ((r (rest (rest (rest (rest (first v)))))))
      (if (null? r) () (first r)))))
(def %py-io-file? (fn (_ v) (not (null? (%py-io-info v)))))
(def %py-io-st (fn (_ v k) (List ref k (List ref 5 (first v)))))
(def %py-io-st!
  (fn (_ v k x) (%seq (%set-first! (%py-drop (List ref 5 (first v)) k) x) ())))
(def %py-io-base (fn (_ v) (if (%py-io-file? v) (%py-io-st v 3) 0)))
; what is buffered from the position on
(def %py-io-rest
  (fn (_ v) (%py-drop (%py-io-buf v) (- (%py-io-pos v) (%py-io-base v)))))

(def %py-io-name
  (fn (_ v)
    (match
      ((null? (%py-io-info v)) (if (%py-io-text? v) "io.StringIO" "io.BytesIO"))
      ((%py-io-text? v) "_io.TextIOWrapper")
      ((not (%py-io-st v 8)) "_io.BufferedReader")
      ((%py-io-st v 7) "_io.BufferedRandom")
      (#t "_io.BufferedWriter"))))

; The class a stream answers to, for type() and isinstance: a file's is the
; one CPython opens it as.
(def %py-io-class
  (fn (_ v)
    (match
      ((null? (%py-io-info v)) (if (%py-io-text? v) %py-cls-StringIO %py-cls-BytesIO))
      ((%py-io-text? v) %py-cls-TextIOWrapper)
      ((not (%py-io-st v 8)) %py-cls-BufferedReader)
      ((%py-io-st v 7) %py-cls-BufferedRandom)
      (#t %py-cls-BufferedWriter))))

; <io.StringIO object>, and a file as CPython prints one:
; <_io.TextIOWrapper name='a.txt' mode='r' encoding='utf-8'>, or for bytes
; <_io.BufferedReader name='a.txt'>.
(def %py-io-repr
  (fn (_ v)
    (let ((info (%py-io-info v)))
      (if (null? info)
        (Str8 append "<" (Str8 append (%py-io-name v) " object>"))
        (Str8 append "<"
          (Str8 append (%py-io-name v)
            (Str8 append " name="
              (Str8 append (%py-repr-of (%py-str-of-x (first info)))
                (if (%py-io-text? v)
                  (Str8 append " mode="
                    (Str8 append (%py-repr-of (%py-str-of-x (first (rest info))))
                      (Str8 append " encoding="
                        (Str8 append (%py-repr-of (%py-str-of-x (first (rest (rest info))))) ">"))))
                  ">")))))))))

; CPython ends the sentence with a period for a file and without one for an
; in-memory stream.
(def %py-io-shut!
  (fn (_ v)
    (if (%py-io-closed? v)
      (Err raise (lit value)
        (if (%py-io-file? v) "I/O operation on closed file." "I/O operation on closed file")
        ())
      ())))

; An open stream that reads, or the refusal of one that does not.
(def %py-io-reads!
  (fn (_ v)
    (%seq (%py-io-shut! v)
      (if (if (%py-io-file? v) (not (%py-io-st v 7)) #f)
        (%py-io-refuse! "not readable")
        ()))))
(def %py-io-refuse!
  (fn (_ what)
    (%py-raise
      (%py-instantiate %py-exc-UnsupportedOperation (list (%py-str-of-x what))))))

; A stream prints as its class and nothing about its contents, which is the
; layout every object here prints in; a file, as its name and mode too.
(set! %py-io
  (%make-type
    "PY-IO"
    (list
      (pair (lit write) (fn (_ self) (display (%py-io-repr self)))))))

; --- the elements ---------------------------------------------------------------
; One list either way: code points for a text stream, bytes for a binary one.

(def %py-io-elems-of
  (fn (_ v x)
    (if (%py-io-text? v)
      (if (%py-str-is x) (%py-str-cps x) (Err raise (lit type) "a str is required" ()))
      (if (%py-bytes-is x) (%py-bytes-list x) (Err raise (lit type) "a bytes-like object is required" ())))))

(def %py-io-value-of
  (fn (_ v el) (if (%py-io-text? v) (%py-str-new el) (%py-bytes-new el))))

(def %py-io-zeros
  (fn (self k acc) (if (<= k 0) acc (self (- k 1) (pair 0 acc)))))

; The buffer with `new` laid over it at `at`, the gap NUL-filled when the
; position is past the end -- which is what seeking beyond it and writing
; leaves behind.
(def %py-io-lay
  (fn (self buf at new)
    (match
      ((null? new) buf)
      ((= at 0) (pair (first new) (self (if (null? buf) () (rest buf)) 0 (rest new))))
      ((null? buf) (pair 0 (self () (- at 1) new)))
      (#t (pair (first buf) (self (rest buf) (- at 1) new))))))

(def %py-io-take
  (fn (self l k acc)
    (if (= k 0) (%py-reverse acc)
      (if (null? l) (%py-reverse acc) (self (rest l) (- k 1) (pair (first l) acc))))))

; --- reading a file ---------------------------------------------------------------

(def %py-io-bytes
  (fn (self s i acc)
    (if (< i 0) acc (self s (- i 1) (pair (%py-io-code (%py-io-bref s i)) acc)))))

; One read of the descriptor: its bytes, none at the end.
(def %py-io-read-fd
  (fn (_ v)
    (let ((n (File read (%py-io-st v 0) (%py-io-st v 6) %py-io-chunk)))
      (if (< n 0)
        (%py-os-raise! (Err errno-of n) (first (%py-io-info v)))
        (%py-io-bytes (%py-io-st v 6) (- n 1) ())))))

; The next elements of a file, none once its end is reached: one read's bytes,
; or for text what they decode to.
(def %py-io-chunk!
  (fn (_ v)
    (if (%py-io-st v 2)
      ()
      (let ((bs (%py-io-read-fd v)))
        (%seq (if (null? bs) (%py-io-st! v 2 #t) ())
          (if (%py-io-text? v) (%py-io-decode! v bs (null? bs)) bs))))))

; A utf-8 sequence a read ends inside waits for the rest of it; at the end of
; the file what waits is decoded as it stands.
(def %py-io-decode!
  (fn (_ v bs last?)
    (let ((d (%py-io-st v 5)) (all (%py-list-cat (%py-io-st v 1) bs)))
      (let ((n (- (%py-length all)
                 (match
                   (last? 0)
                   ((eq? (%ps-codec (first d)) (lit ascii)) 0)
                   (#t (%py-io-tail (%py-reverse all) 1))))))
        (%seq (%py-io-st! v 1 (%py-drop all n))
          (%py-io-newlines! v
            (%ps-decode-as (%py-io-take all n ()) (first d) (first (rest d)))
            last?))))))

; How many bytes at the end begin a sequence the rest of has not arrived: R
; is the bytes backwards and K the count so far.
(def %py-io-tail
  (fn (self r k)
    (match
      ((null? r) 0)
      ((> k 3) 0)
      ((< (first r) 128) 0)
      ((< (first r) 192) (self (rest r) (+ k 1)))
      ((< k (match ((< (first r) 224) 2) ((< (first r) 240) 3) (#t 4))) k)
      (#t 0))))

; \r\n and a lone \r read as \n when the newline argument is None, the
; default.  A \r a read ends on waits for the next, which may begin with its
; \n.
(def %py-io-newlines!
  (fn (_ v cps last?)
    (if (not (null? (first (rest (rest (%py-io-st v 5))))))
      cps
      (let ((all (if (%py-io-st v 4) (pair 13 cps) cps)))
        (let ((r (%py-reverse all)))
          (if (match (last? #f) ((null? r) #f) (#t (= (first r) 13)))
            (%seq (%py-io-st! v 4 #t) (%py-universal (%py-reverse (rest r)) ()))
            (%seq (%py-io-st! v 4 #f) (%py-universal all ()))))))))

; What was taken leaves the buffer.
(def %py-io-trim!
  (fn (_ v)
    (if (%py-io-file? v)
      (let ((gone (- (%py-io-pos v) (%py-io-base v)))
            (held (%py-length (%py-io-buf v))))
        (let ((k (if (> gone held) held gone)))
          (%seq (%py-io-buf! v (%py-drop (%py-io-buf v) k))
            (%py-io-st! v 3 (+ (%py-io-base v) k)))))
      ())))

(def %py-io-member?
  (fn (self x l) (if (null? l) #f (if (= (first l) x) #t (self x (rest l))))))
(def %py-io-newline? (fn (_ l) (%py-io-member? 10 l)))

; WANT is a count of elements, () for all there is, or `line` for as far as
; the next \n: whether N elements, the newest of them C, are enough.
(def %py-io-enough?
  (fn (_ want n c)
    (match
      ((null? want) #f)
      ((eq? want (lit line)) (%py-io-newline? c))
      (#t (>= n want)))))

; Reads until there is enough or the file ends; the elements gather backwards.
(def %py-io-gather
  (fn (self v want n racc)
    (let ((c (%py-io-chunk! v)))
      (let ((more (%py-rev-onto c racc)) (m (+ n (%py-length c))))
        (if (if (%py-io-st v 2) #t (%py-io-enough? want m c))
          more
          (self v want m more))))))

; A file's buffer is brought to hold WANT from the position on, or all the
; file has left; an in-memory stream holds all it has already.
(def %py-io-need!
  (fn (_ v want)
    (if (%py-io-file? v)
      (%seq (%py-io-trim! v)
        (let ((have (%py-io-buf v)))
          (if (if (%py-io-st v 2) #t (%py-io-enough? want (%py-length have) have))
            ()
            (%py-io-buf! v
              (%py-reverse
                (%py-io-gather v want (%py-length have) (%py-reverse have)))))))
      ())))

; The descriptor's own offset moved, or the OSError that refuses it; a pipe's
; refusal is io.UnsupportedOperation.
(def %py-io-lseek!
  (fn (_ v off whence)
    (let ((p (File seek (%py-io-st v 0) off whence)))
      (match
        ((>= p 0) p)
        ((= (Err errno-of p) 29)
          (%py-raise
            (%py-instantiate %py-exc-UnsupportedOperation
              (list (%py-str-of-x "underlying stream is not seekable")))))
        (#t (%py-os-raise! (Err errno-of p) (first (%py-io-info v))))))))

; Reading starts over at byte P, which is position AT.
(def %py-io-restart!
  (fn (_ v p at)
    (%seq (%py-io-lseek! v p (lit set))
      (%seq (%py-io-buf! v ())
        (%seq (%py-io-st! v 1 ())
          (%seq (%py-io-st! v 2 #f)
            (%seq (%py-io-st! v 3 at)
              (%py-io-st! v 4 #f))))))))

; Reads on, keeping nothing, until the buffer reaches the position or the
; file ends.
(def %py-io-forward!
  (fn (self v)
    (%seq (%py-io-trim! v)
      (if (match
            ((%py-io-st v 2) #t)
            (#t (>= (+ (%py-io-base v) (%py-length (%py-io-buf v))) (%py-io-pos v))))
        ()
        (%seq (%py-io-buf! v (%py-io-chunk! v)) (self v))))))

; The position the file ends at, reading to it and keeping nothing.
(def %py-io-end!
  (fn (self v)
    (let ((end (+ (%py-io-base v) (%py-length (%py-io-buf v)))))
      (if (%py-io-st v 2)
        end
        (%seq (%py-io-st! v 3 end)
          (%seq (%py-io-buf! v (%py-io-chunk! v)) (self v)))))))

; A position in bytes is the descriptor's offset, so a byte file seeks there
; and reads nothing.  A position in text is a count of code points, which
; only reading finds: backwards is from the start again.  A text file that
; does not read has only its descriptor to go by, and its positions are bytes.
(def %py-io-file-seek!
  (fn (_ v off whence)
    (if (if (%py-io-text? v) (%py-io-st v 7) #f)
      (let ((p (+ off (match
                        ((= whence 1) (%py-io-pos v))
                        ((= whence 2) (%py-io-end! v))
                        (#t 0)))))
        (if (< p 0)
          (Err raise (lit value) "negative seek value" ())
          (%seq (if (< p (%py-io-base v)) (%py-io-restart! v 0 0) ())
            (%seq (%py-io-pos! v p)
              (%seq (%py-io-forward! v) p)))))
      (let ((p (if (= whence 2)
                 (%py-io-lseek! v off (lit end))
                 (%py-io-lseek! v (+ off (if (= whence 1) (%py-io-pos v) 0)) (lit set)))))
        (%seq (%py-io-restart! v p p)
          (%seq (%py-io-pos! v p) p))))))

(def %py-io-close!
  (fn (_ v)
    (%seq
      (if (if (%py-io-file? v) (not (%py-io-closed? v)) #f)
        (File close (%py-io-st v 0))
        ())
      (%seq (%set-first! (List ref 3 (first v)) #t) ()))))

; --- writing a file ---------------------------------------------------------------
; A write goes to the descriptor as it is made: nothing waits in a buffer, so
; a file that is never closed has what was written to it.

; BS written, all of it.
(def %py-io-put!
  (fn (self v bs)
    (if (null? bs)
      ()
      (let ((n (%ps-write-bytes-to (%py-io-st v 0) bs)))
        (match
          ((< n 0) (%py-os-raise! (Err errno-of n) (first (%py-io-info v))))
          ((< n (%py-length bs)) (self v (%py-drop bs n)))
          (#t ()))))))

; What a write takes: a str for text, bytes or a bytearray for bytes.
(def %py-io-written
  (fn (_ v x)
    (match
      ((%py-io-text? v)
        (if (%py-str-is x)
          (%py-str-cps x)
          (Err raise (lit type)
            (Str8 append "write() argument must be str, not "
              (%py-class-name (%py-type-of x))) ())))
      ((%py-bytes-is x) (%py-bytes-list x))
      (#t
        (Err raise (lit type)
          (Str8 append "a bytes-like object is required, not '"
            (Str8 append (%py-class-name (%py-type-of x)) "'")) ())))))

; The bytes text goes out as: each \n as the newline argument when that is
; \r or \r\n, and the whole in the file's encoding.
(def %py-io-encoded
  (fn (_ v cps)
    (let ((d (%py-io-st v 5)))
      (let ((nl (first (rest (rest d)))))
        (%ps-encode-as
          (if (null? nl) cps
            (let ((to (%py-str-cps nl)))
              (if (%py-io-member? 13 to) (%py-io-turn cps to ()) cps)))
          (first d) (first (rest d)))))))
(def %py-io-turn
  (fn (self cps to acc)
    (match
      ((null? cps) (%py-reverse acc))
      ((= (first cps) 10) (self (rest cps) to (%py-rev-onto to acc)))
      (#t (self (rest cps) to (pair (first cps) acc))))))

; What was read ahead of the position is let go before a write.  In bytes
; the descriptor's offset is brought back to the position, which is that
; offset.  In text the write lands where the descriptor is, past what was
; read ahead, and what was read and not taken is dropped: CPython's text
; files do the same, and a program that means the position seeks to it.
(def %py-io-sync!
  (fn (_ v)
    (%seq (%py-io-trim! v)
      (match
        ((not (%py-io-st v 7)) ())
        ((%py-io-text? v)
          (%py-io-restart! v (%py-io-lseek! v 0 (lit cur)) (%py-io-pos v)))
        (#t (%py-io-restart! v (%py-io-pos v) (%py-io-pos v)))))))

(def %py-io-file-write!
  (fn (_ v x)
    (if (not (%py-io-st v 8))
      (%py-io-refuse! "not writable")
      (let ((new (%py-io-written v x)))
        (%seq (%py-io-sync! v)
          (%seq (%py-io-put! v (if (%py-io-text? v) (%py-io-encoded v new) new))
            (%seq (%py-io-wrote! v (%py-length new))
              (%py-length new))))))))

; After a write the position is past it; in bytes that is where the
; descriptor is, which for a file that appends is its end.
(def %py-io-wrote!
  (fn (_ v n)
    (let ((p (if (%py-io-text? v)
               (+ (%py-io-pos v) n)
               (%py-io-lseek! v 0 (lit cur)))))
      (%seq (%py-io-pos! v p)
        (%seq (%py-io-buf! v ())
          (%seq (%py-io-st! v 3 p) (%py-io-st! v 2 #f)))))))

; truncate(), truncate(None): at the position; truncate(n): at n bytes.  The
; position stays.  A text file's position is not a count of bytes, so with
; text read and not taken there is no saying where it is, and truncate()
; wants its size.
(def %py-io-truncate!
  (fn (_ v . more)
    (%seq (%py-io-shut! v)
      (if (not (if (%py-io-file? v) (%py-io-st v 8) #f))
        (%py-io-refuse! "truncate")
        (%seq
          (if (match
                ((not (%py-io-text? v)) #f)
                ((not (null? more)) (null? (first more)))
                (#t #t))
            (%seq (%py-io-trim! v)
              (if (if (null? (%py-io-buf v)) (null? (%py-io-st v 1)) #f)
                ()
                (%py-io-refuse! "truncate() after a read wants a size")))
            ())
          (%seq (%py-io-sync! v)
            (let ((n (match
                       ((null? more) (%py-io-lseek! v 0 (lit cur)))
                       ((null? (first more)) (%py-io-lseek! v 0 (lit cur)))
                       (#t (%py-boolnorm (first more))))))
              (let ((r (File truncate (%py-io-st v 0) n)))
                (if (< r 0)
                  (%py-os-raise! (Err errno-of r) (first (%py-io-info v)))
                  n)))))))))

; --- the operations ---------------------------------------------------------------

(def %py-io-write!
  (fn (_ v x)
    (%seq (%py-io-shut! v)
      (if (%py-io-file? v)
        (%py-io-file-write! v x)
        (let ((new (%py-io-elems-of v x)))
          (%seq
            (%py-io-buf! v (%py-io-lay (%py-io-buf v) (%py-io-pos v) new))
            (%seq (%py-io-pos! v (+ (%py-io-pos v) (%py-length new)))
              (%py-length new))))))))

; GOT is taken: the position moves past it and a file's buffer lets it go.
(def %py-io-took!
  (fn (_ v got)
    (%seq (%py-io-pos! v (+ (%py-io-pos v) (%py-length got)))
      (%seq (%py-io-trim! v) got))))

; read(), read(None) and read(-1) are all there is; read(n) at most n.
(def %py-io-read
  (fn (_ v . more)
    (%seq (%py-io-reads! v)
      (let ((n (match
                 ((null? more) ())
                 ((null? (first more)) ())
                 ((< (%py-boolnorm (first more)) 0) ())
                 (#t (%py-boolnorm (first more))))))
        (%seq (%py-io-need! v n)
          (%py-io-value-of v
            (%py-io-took! v
              (if (null? n) (%py-io-rest v) (%py-io-take (%py-io-rest v) n ())))))))))

(def %py-io-getvalue
  (fn (_ v) (%seq (%py-io-shut! v) (%py-io-value-of v (%py-io-buf v)))))

; seek(n), seek(n, 0|1|2): from the start, from here, from the end.  A
; position past the end is allowed; it is the write that fills the gap.
(def %py-io-seek!
  (fn (_ v n . more)
    (%seq (%py-io-shut! v)
      (let ((whence (if (null? more) 0 (%py-boolnorm (first more)))))
        (if (%py-io-file? v)
          (%py-io-file-seek! v (%py-boolnorm n) whence)
          (let ((base (match
                        ((= whence 1) (%py-io-pos v))
                        ((= whence 2) (%py-length (%py-io-buf v)))
                        (#t 0))))
            (let ((p (+ base (%py-boolnorm n))))
              (if (< p 0)
                (Err raise (lit value) "negative seek value" ())
                (%seq (%py-io-pos! v p) p)))))))))

(def %py-io-readinto!
  (fn (_ v arr)
    (%seq (%py-io-reads! v)
      (if (not (%py-barr-is arr))
        (Err raise (lit type) "readinto() wants a bytearray" ())
        (let ((room (%py-length (%py-bytes-list arr))))
          (%seq (%py-io-need! v room)
            (let ((got (%py-io-took! v (%py-io-take (%py-io-rest v) room ()))))
              (%seq (%py-barr-set! arr (%py-io-lay (%py-bytes-list arr) 0 got))
                (%py-length got)))))))))

; Iterating a stream answers its remaining LINES, each keeping its newline.
(def %py-io-lines
  (fn (self v el acc cur)
    (if (null? el)
      (%py-reverse (if (null? cur) acc (pair (%py-io-value-of v (%py-reverse cur)) acc)))
      (if (= (first el) 10)
        (self v (rest el) (pair (%py-io-value-of v (%py-reverse (pair 10 cur))) acc) ())
        (self v (rest el) acc (pair (first el) cur))))))

(def %py-io-elems
  (fn (_ v) (%py-io-lines v (%py-io-rest v) () ())))

; All the lines left, for what wants the whole of them -- list(f),
; readlines() -- with the position where the last of them ended.
(def %py-io-drain!
  (fn (_ v)
    (%seq (%py-io-reads! v)
      (%seq (%py-io-need! v ())
        (let ((ls (%py-io-elems v)))
          (%seq (%py-io-pos! v (+ (%py-io-base v) (%py-length (%py-io-buf v))))
            (%seq (%py-io-trim! v) ls)))))))

(def %py-io-iter! (fn (_ v) (%py-list-new (%py-io-drain! v))))

; The elements up to and with the next \n.
(def %py-io-line-take
  (fn (self l acc)
    (match
      ((null? l) (%py-reverse acc))
      ((= (first l) 10) (%py-reverse (pair 10 acc)))
      (#t (self (rest l) (pair (first l) acc))))))

; The next line, None when there is none: what a for loop and next() pull, so
; a file is read as far as the loop has come.
(def %py-io-line!
  (fn (_ v)
    (%seq (%py-io-reads! v)
      (%seq (%py-io-need! v (lit line))
        (let ((got (%py-io-took! v (%py-io-line-take (%py-io-rest v) ()))))
          (if (null? got) () (%py-io-value-of v got)))))))

(def %py-io-each
  (fn (self f l) (if (null? l) () (%seq (f (first l)) (self f (rest l))))))

(def %py-io-readline
  (fn (_ v)
    (let ((l (%py-io-line! v)))
      (if (null? l) (%py-io-value-of v ()) l))))

; --- the surfaces -----------------------------------------------------------------

(def %py-io-attr
  (fn (_ v name)
    (match
      ((Str8 =? name "write") (fn (_ x) (%py-io-write! v x)))
      ((Str8 =? name "read") (fn (_ . a) (apply %py-io-read (pair v a))))
      ((if (%py-io-file? v) #f (Str8 =? name "getvalue")) (fn (_) (%py-io-getvalue v)))
      ((if (%py-io-file? v) (Str8 =? name "fileno") #f)
        (fn (_)
          (if (%py-io-closed? v)
            (Err raise (lit value) "I/O operation on closed file" ())
            (%py-io-st v 0))))
      ((Str8 =? name "tell") (fn (_) (%py-io-pos v)))
      ((Str8 =? name "seek") (fn (_ n . a) (apply %py-io-seek! (pair v (pair n a)))))
      ((Str8 =? name "readinto") (fn (_ arr) (%py-io-readinto! v arr)))
      ((Str8 =? name "readline") (fn (_) (%py-io-readline v)))
      ((Str8 =? name "flush") (fn (_) (%py-io-shut! v)))
      ((Str8 =? name "close") (fn (_) (%py-io-close! v)))
      ((Str8 =? name "__enter__") (fn (_) (%seq (%py-io-shut! v) v)))
      ((Str8 =? name "__exit__") (fn (_ . a) (%py-io-close! v)))
      ((Str8 =? name "__iter__") (fn (_) (%seq (%py-io-shut! v) v)))
      ((Str8 =? name "__next__")
        (fn (_) (let ((l (%py-io-line! v))) (if (null? l) (%py-raise-stop ()) l))))
      ((Str8 =? name "readlines") (fn (_) (%py-io-iter! v)))
      ((Str8 =? name "closed") (%py-io-closed? v))
      ((Str8 =? name "readable")
        (fn (_) (%seq (%py-io-shut! v) (if (%py-io-file? v) (%py-io-st v 7) #t))))
      ((Str8 =? name "writable")
        (fn (_) (%seq (%py-io-shut! v) (if (%py-io-file? v) (%py-io-st v 8) #t))))
      ((Str8 =? name "writelines")
        (fn (_ lines)
          (%seq (%py-io-each (fn (_ x) (%py-io-write! v x)) (%py-iter-elems lines)) ())))
      ((Str8 =? name "truncate") (fn (_ . a) (apply %py-io-truncate! (pair v a))))
      ((Str8 =? name "seekable")
        (fn (_)
          (%seq (%py-io-shut! v)
            (if (%py-io-file? v) (>= (File seek (%py-io-st v 0) 0 (lit cur)) 0) #t))))
      ; what a file was opened as
      ((if (null? (%py-io-info v)) #f (Str8 =? name "name"))
        (%py-str-of-x (first (%py-io-info v))))
      ((if (null? (%py-io-info v)) #f (Str8 =? name "mode"))
        (%py-str-of-x (first (rest (%py-io-info v)))))
      ((if (null? (%py-io-info v)) #f (if (%py-io-text? v) (Str8 =? name "encoding") #f))
        (%py-str-of-x (first (rest (rest (%py-io-info v))))))
      (#t
        (Err raise (lit attribute)
          (Str8 append (Str8 append "'" (%py-io-name v))
            (Str8 append "' object has no attribute '" (Str8 append name "'"))) ())))))

(def %py-io-methods
  (fn (_ text?)
    (list
      (pair "%ctor"
        (fn (_ . a)
          (%py-io-new text?
            (if (null? a) ()
              (if (null? (first a)) ()
                (%py-io-elems-of (%py-io-new text? ()) (first a)))))))
      (pair "write" (%py-sig! (fn (_ o x) (%py-io-write! (%py-native-of o) x))
                      "write" (list "self" "s") 2 #f () () #t))
      (pair "read" (%py-sig! (fn (_ o . a) (apply %py-io-read (pair (%py-native-of o) a)))
                     "read" (list "self") 1 #t () () #t))
      (pair "getvalue" (%py-sig! (fn (_ o) (%py-io-getvalue (%py-native-of o)))
                         "getvalue" (list "self") 1 #f () () #t))
      (pair "tell" (%py-sig! (fn (_ o) (%py-io-pos (%py-native-of o)))
                     "tell" (list "self") 1 #f () () #t))
      (pair "seek" (%py-sig! (fn (_ o n . a) (apply %py-io-seek! (pair (%py-native-of o) (pair n a))))
                     "seek" (list "self" "pos") 2 #t () () #t))
      (pair "readinto" (%py-sig! (fn (_ o arr) (%py-io-readinto! (%py-native-of o) arr))
                         "readinto" (list "self" "buf") 2 #f () () #t))
      (pair "readline" (%py-sig! (fn (_ o) (%py-io-readline (%py-native-of o)))
                         "readline" (list "self") 1 #f () () #t))
      (pair "flush" (%py-sig! (fn (_ o) ()) "flush" (list "self") 1 #f () () #t))
      (pair "close"
        (%py-sig! (fn (_ o) (%py-io-close! (%py-native-of o)))
          "close" (list "self") 1 #f () () #t))
      (pair "__enter__" (fn (_ o) o))
      (pair "__exit__"
        (fn (_ o . a) (%py-io-close! (%py-native-of o))))
      (pair "__iter__" (fn (_ o) (%py-io-iter! (%py-native-of o))))
      (pair "__repr__" (fn (_ o) (Str8 append "<" (Str8 append (%py-io-name (%py-native-of o)) " object>"))))
      (pair "__str__" (fn (_ o) (Str8 append "<" (Str8 append (%py-io-name (%py-native-of o)) " object>")))))))

; IOBase carries no behaviour of its own: it is the base a program writes its
; own stream against, and `print(..., file=x)` asks that object for write.
(def %py-cls-IOBase (%py-class-new "IOBase" %py-cls-object () "io.IOBase"))
(def %py-cls-StringIO
  (%py-class-new "StringIO" %py-cls-IOBase (%py-io-methods #t) "io.StringIO"))
(def %py-cls-BytesIO
  (%py-class-new "BytesIO" %py-cls-IOBase (%py-io-methods #f) "io.BytesIO"))

; What a write to a stream that cannot take one raises: an OSError, and a
; ValueError too, so either handler catches it.
(def %py-exc-UnsupportedOperation
  (%py-class-new "UnsupportedOperation" (list %py-exc-OSError %py-exc-ValueError) ()
    "io.UnsupportedOperation"))

; --- the standard streams ---------------------------------------------------------
; sys.stdin, sys.stdout and sys.stderr: a text stream over a file descriptor,
; with the byte stream beneath it as `buffer`.  Each is an ordinary instance
; carrying name, mode and encoding as attributes, as CPython's do, and its
; descriptor under "%fd" and whether it writes under "%out?" -- keys no Python
; identifier can spell.
;
; Text written to stdout takes print's own door, and to any other descriptor
; goes out as its utf-8 bytes; bytes go straight to the descriptor.  Reading
; stdin is not offered: the interpreter's own reader takes its input from that
; descriptor, at the REPL and under the spec harness alike, and a read here
; would take from underneath it.

(def %py-io-row
  (fn (_ o k)
    (let ((e (%py-alist-find k (%py-obj-attrs o))))
      (if (null? e)
        (Err raise (lit value) "I/O operation on uninitialized object" ())
        (rest e)))))

(def %py-io-put-text
  (fn (_ fd cps)
    (if (= fd 1) (%py-str-display cps) (%ps-write-bytes-to fd (%ps-encode cps ())))))

(def %py-io-writable!
  (fn (_ o)
    (if (%py-io-row o "%out?")
      ()
      (%py-raise
        (%py-instantiate %py-exc-UnsupportedOperation (list (%py-str-of-x "not writable")))))))

(def %py-io-std-write
  (fn (_ o s)
    (%seq (%py-io-writable! o)
      (if (%py-str-is s)
        (%seq (%py-io-put-text (%py-io-row o "%fd") (%py-str-cps s))
          (%py-length (%py-str-cps s)))
        (Err raise (lit type)
          (Str8 append "write() argument must be str, not "
            (%py-class-name (%py-type-of s))) ())))))

(def %py-io-std-write-bytes
  (fn (_ o b)
    (%seq (%py-io-writable! o)
      (if (%py-bytes-is b)
        (let ((bs (%py-bytes-list b)))
          (%seq (%ps-write-bytes-to (%py-io-row o "%fd") bs)
            (%py-length bs)))
        (Err raise (lit type)
          (Str8 append "a bytes-like object is required, not '"
            (Str8 append (%py-class-name (%py-type-of b)) "'")) ())))))

; <_io.TextIOWrapper name='<stdout>' mode='w' encoding='utf-8'>, and the byte
; stream beneath it as <_io.BufferedWriter name='<stdout>'>.
(def %py-io-std-repr
  (fn (_ o)
    (let ((head (Str8 append "<"
                  (Str8 append (%py-class-qualname (%py-obj-class o))
                    (Str8 append " name=" (%py-repr-of (%py-io-row o "name")))))))
      (if (%py-subclass? (%py-obj-class o) %py-cls-TextIOWrapper)
        (Str8 append head
          (Str8 append " mode="
            (Str8 append (%py-repr-of (%py-io-row o "mode"))
              (Str8 append " encoding="
                (Str8 append (%py-repr-of (%py-io-row o "encoding")) ">")))))
        (Str8 append head ">")))))

(def %py-io-std-methods
  (fn (_ write)
    (list
      (pair "write" (%py-sig! write "write" (list "self" "s") 2 #f () () #t))
      (pair "flush" (%py-sig! (fn (_ o) ()) "flush" (list "self") 1 #f () () #t))
      (pair "fileno"
        (%py-sig! (fn (_ o) (%py-io-row o "%fd")) "fileno" (list "self") 1 #f () () #t))
      (pair "__repr__" %py-io-std-repr)
      (pair "__str__" %py-io-std-repr))))

(def %py-cls-TextIOWrapper
  (%py-class-new "TextIOWrapper" %py-cls-IOBase (%py-io-std-methods %py-io-std-write)
    "_io.TextIOWrapper"))
(def %py-cls-BufferedWriter
  (%py-class-new "BufferedWriter" %py-cls-IOBase (%py-io-std-methods %py-io-std-write-bytes)
    "_io.BufferedWriter"))
(def %py-cls-BufferedReader
  (%py-class-new "BufferedReader" %py-cls-IOBase (%py-io-std-methods %py-io-std-write-bytes)
    "_io.BufferedReader"))
(def %py-cls-BufferedRandom
  (%py-class-new "BufferedRandom" %py-cls-IOBase (%py-io-std-methods %py-io-std-write-bytes)
    "_io.BufferedRandom"))

; One standard stream: fd, its name as CPython spells it, and whether it writes.
(def %py-io-std
  (fn (_ fd name out?)
    (let ((raw (%py-obj-new (if out? %py-cls-BufferedWriter %py-cls-BufferedReader)))
          (text (%py-obj-new %py-cls-TextIOWrapper)))
      (%seq
        (%py-obj-set-attrs! raw
          (list (pair "%fd" fd) (pair "%out?" out?)
            (pair "name" (%py-str-of-x name))
            (pair "mode" (%py-str-of-x (if out? "wb" "rb")))))
        (%seq
          (%py-obj-set-attrs! text
            (list (pair "%fd" fd) (pair "%out?" out?)
              (pair "name" (%py-str-of-x name))
              (pair "mode" (%py-str-of-x (if out? "w" "r")))
              (pair "encoding" (%py-str-of-x "utf-8"))
              (pair "buffer" raw)))
          text)))))

; --- files --------------------------------------------------------------------------
; open(file, mode='r', buffering, encoding, errors, newline, closefd, opener): a
; file opened as the mode says -- r to read, w to write from empty, a to
; write at the end, x to write a file that must not exist yet, each with a +
; to do both.  Opening one reads nothing: what is asked of it is read from its
; descriptor a chunk at a time -- the text the bytes decode to, or, with a b
; in the mode, the bytes themselves -- a write goes to the descriptor as it
; is made, and close() closes it.  A text read turns \r\n and \r into \n
; unless the newline argument asks otherwise, as CPython's universal newlines
; do.  A relative path is the working directory's, as the process has it.
(def %py-open
  (%py-sig!
    (fn (_ file . a)
      (def mode (%py-open-text (%py-opt a 0 ()) "r"))
      (def encoding (%py-opt a 2 ()))
      (def binary? (%py-open-has? mode "b"))
      (%py-open-mode! mode binary? encoding)
      (def path
        (if (%py-str-is file)
          (%py-text->x file)
          (Err raise (lit type) "open() takes a path as a str here" ())))
      (def enc (%py-open-text encoding "utf-8"))
      ; an encoding nothing here knows is refused before the file is opened
      (if binary? () (%ps-codec enc))
      (def both? (%py-open-has? mode "+"))
      (def reads? (if both? #t (%py-open-has? mode "r")))
      (def writes? (if both? #t (not (%py-open-has? mode "r"))))
      (def fd (%py-open-fd path (%py-open-flags mode both?)))
      ; a file that appends starts at its end
      (def at (if (%py-open-has? mode "a") (File seek fd 0 (lit end)) 0))
      (if binary?
        (%py-io-file-new #f (list path (%py-open-bytes-mode mode both?) ()) fd ()
          reads? writes? at)
        (%py-io-file-new #t (list path mode enc) fd
          (list enc (%py-open-text (%py-opt a 3 ()) "strict") (%py-opt a 4 ()))
          reads? writes? at)))
    "open" (list "file" "mode" "buffering" "encoding" "errors" "newline" "closefd" "opener")
    1 #f))

(def %py-open-has?
  (fn (_ mode c) (not (null? (Str8 index-of c mode)))))

; What the platform's open is asked for.
(def %py-open-flags
  (fn (_ mode both?)
    (pair (if both? (lit rdwr) (if (%py-open-has? mode "r") (lit rdonly) (lit wronly)))
      (match
        ((%py-open-has? mode "w") (list (lit creat) (lit trunc)))
        ((%py-open-has? mode "a") (list (lit creat) (lit append)))
        ((%py-open-has? mode "x") (list (lit creat) (lit excl)))
        (#t ())))))

; The mode a byte file answers, which is CPython's spelling and not the one
; it was opened with: xb, ab, rb+ for any that reads and writes, wb, rb.
(def %py-open-bytes-mode
  (fn (_ mode both?)
    (match
      ((%py-open-has? mode "x") (if both? "xb+" "xb"))
      ((%py-open-has? mode "a") (if both? "ab+" "ab"))
      (both? "rb+")
      ((%py-open-has? mode "w") "wb")
      (#t "rb"))))

; The descriptor, or the OSError that says why there is none.  A directory
; opens to read as a descriptor nothing can be read from, so it is refused
; here, as CPython refuses it.  A file made here is made readable and
; writable by all, less what the process's umask takes away.
(def %py-open-fd
  (fn (_ path flags)
    (if (%py-open-dir? path)
      (%py-os-raise! 21 path)
      (let ((fd (File open path flags 438)))
        (if (< fd 0) (%py-os-raise! (Err errno-of fd) path) fd)))))
; the file type bits of the mode say directory
(def %py-open-dir?
  (fn (_ path)
    (let ((mode (guard (_ ()) (Assoc get (lit mode) (File stat path)))))
      (if (null? mode) #f (= (Num quotient (% mode 65536) 4096) 4)))))

; OSError(errno, strerror, filename), as the class CPython has for the errno.
(def %py-os-raise!
  (fn (_ en path)
    (%py-raise
      (%py-instantiate
        (match
          ((= en 2) %py-exc-FileNotFoundError)
          ((= en 13) %py-exc-PermissionError)
          ((= en 17) %py-exc-FileExistsError)
          ((= en 21) %py-exc-IsADirectoryError)
          (#t %py-exc-OSError))
        (list en (%py-str-of-x (%py-os-text en)) (%py-str-of-x path))))))
; the platform's message for an errno, without the operation it leads with
(def %py-os-text
  (fn (_ en)
    (let ((m ((Err from-errno en (lit io)) msg)))
      (Str8 sub 4 (- (Str8 length m) 4) m))))

; A text argument or its default when None.
(def %py-open-text
  (fn (_ v dflt)
    (match
      ((null? v) dflt)
      ((%py-str-is v) (%py-text->x v))
      (#t (Err raise (lit type) "open() takes its mode, encoding and errors as strs" ())))))

; What CPython refuses in a mode is refused here, in its words and its order.
(def %py-open-mode!
  (fn (_ mode binary? encoding)
    (let ((n (%py-open-count mode (list "r" "w" "a" "x") 0)))
      (match
        ((not (%py-open-only? mode 0 ""))
          (Err raise (lit value) (Str8 append "invalid mode: '" (Str8 append mode "'")) ()))
        ((if binary? (%py-open-has? mode "t") #f)
          (Err raise (lit value) "can't have text and binary mode at once" ()))
        ((> n 1)
          (Err raise (lit value) "must have exactly one of create/read/write/append mode" ()))
        ((= n 0)
          (Err raise (lit value)
            "Must have exactly one of create/read/write/append mode and at most one plus"
            ()))
        ((if binary? (not (null? encoding)) #f)
          (Err raise (lit value) "binary mode doesn't take an encoding argument" ()))
        (#t ())))))
(def %py-open-count
  (fn (self mode cs n)
    (if (null? cs) n
      (self mode (rest cs) (if (%py-open-has? mode (first cs)) (+ n 1) n)))))
; every character one a mode may hold, and none of them twice
(def %py-open-only?
  (fn (self mode i seen)
    (if (>= i (Str8 length mode))
      #t
      (let ((c (Str8 sub i 1 mode)))
        (match
          ((not (%py-open-has? "rwaxbt+" c)) #f)
          ((%py-open-has? seen c) #f)
          (#t (self mode (+ i 1) (Str8 append seen c))))))))

; \r\n and a lone \r read as \n when NEWLINE is None, the default.
(def %py-universal
  (fn (_ cps newline)
    (if (null? newline) (%py-universal-go cps ()) cps)))
(def %py-universal-go
  (fn (self cps acc)
    (match
      ((null? cps) (%py-reverse acc))
      ((not (= (first cps) 13)) (self (rest cps) (pair (first cps) acc)))
      ((if (null? (rest cps)) #f (= (first (rest cps)) 10)) (self (rest (rest cps)) (pair 10 acc)))
      (#t (self (rest cps) (pair 10 acc))))))

(def %py-io-module
  (fn (_)
    (%py-module-new "io"
      (list
        (pair "StringIO" %py-cls-StringIO)
        (pair "BytesIO" %py-cls-BytesIO)
        (pair "IOBase" %py-cls-IOBase)
        (pair "UnsupportedOperation" %py-exc-UnsupportedOperation)
        (pair "open" %py-open)))))

(provide python/io
  %py-cls-BytesIO %py-cls-StringIO %py-io-attr %py-io-class %py-io-drain! %py-io-is
  %py-io-line! %py-io-module %py-io-std %py-io-text? %py-open)
