; # x-python -- Python on x-lang
;
; ## python/os.x -- the os module
;
; @description The operating system as Python names it: the machine uname()
;   describes, the process's id and working directory, the environment, and
;   the spellings of a path.
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;     ., .,
;     {O,O}
;     (   )
;      " "
;
; EACH FUNCTION IS ONE OF THE PLATFORM'S Sys DOORS, which are libc's, so
; nothing here knows which host it runs on.  The hosts x-lang builds for are
; all POSIX, so the spellings are POSIX's: os.name is "posix" and a path
; separates with "/".  os.path, the file operations and the rest of CPython's
; module are not here yet.

(module python/os)
(import python/core
  python-instantiate python-module-new python-sig! python-str-of-x python-text->x)
(import python/collections python-namedtuple-class)

; uname() is a named tuple of five strs, printed as CPython prints it,
; posix.uname_result(sysname='Darwin', ...).
(def %py-uname-fields (list "sysname" "nodename" "release" "version" "machine"))
(def %py-uname-keys (list (lit sysname) (lit nodename) (lit release) (lit version) (lit machine)))
(def %py-uname
  (fn (_ cls)
    (let ((u (Sys uname)))
      (python-instantiate cls
        (List map (fn (_ k) (python-str-of-x (Assoc get k u))) %py-uname-keys)))))

; getenv(key, default=None): the variable's value as a str, else the default.
(def %py-getenv
  (fn (_ key . dflt)
    (let ((v (Sys getenv (python-text->x key))))
      (if (null? v) (if (null? dflt) () (first dflt)) (python-str-of-x v)))))

(def python-os-module
  (fn (_)
    (let ((ur (python-namedtuple-class "uname_result" "posix.uname_result" %py-uname-fields)))
      (python-module-new "os"
        (list
          (pair "name" (python-str-of-x "posix"))
          (pair "sep" (python-str-of-x "/"))
          (pair "altsep" ())
          (pair "curdir" (python-str-of-x "."))
          (pair "pardir" (python-str-of-x ".."))
          (pair "extsep" (python-str-of-x "."))
          (pair "pathsep" (python-str-of-x ":"))
          (pair "linesep" (python-str-of-x "\n"))
          (pair "devnull" (python-str-of-x "/dev/null"))
          (pair "uname" (fn (_) (%py-uname ur)))
          (pair "getcwd" (fn (_) (python-str-of-x (Sys getcwd))))
          (pair "getpid" (fn (_) (Sys getpid)))
          (pair "cpu_count" (fn (_) (Sys cpu-count)))
          (pair "getenv" (python-sig! %py-getenv "getenv" (list "key" "default") 1 #f)))))))

(provide python/os python-os-module)
