"""Regular expressions, as CPython's re module reads and matches them.

The pattern syntax is CPython's: classes and the \\d \\w \\s categories,
greedy, lazy and possessive repeats, groups named and numbered, backreferences,
lookahead and fixed-width lookbehind, atomic groups, (?(id)yes|no), and the
flags inline, scoped or passed.  The parser is here; the matcher is the module
_sre (lib/python/_sre.x), the split CPython makes.

Divergences: beyond ASCII, \\w and IGNORECASE know Latin-1, Greek, Cyrillic
and CJK, not all of Unicode, and \\d is the ASCII digits.  LOCALE is
accepted and does nothing.  A pattern that nests a repeat of a group very
deeply raises OverflowError where CPython would go on.  A flag is a RegexFlag
that holds an int rather than an int itself, so isinstance(re.I, int) is
False here.
"""

import _sre

__all__ = ["match", "fullmatch", "search", "sub", "subn", "split", "findall",
           "finditer", "compile", "purge", "escape", "error", "Pattern",
           "Match", "A", "I", "L", "M", "S", "X", "U", "ASCII", "IGNORECASE",
           "LOCALE", "MULTILINE", "DOTALL", "VERBOSE", "UNICODE", "NOFLAG",
           "RegexFlag", "PatternError"]

_MAXREPEAT = -1
_MAXPOS = 2 ** 62


# --- the flags ---------------------------------------------------------------

class RegexFlag:
    """A flag, or flags joined with |, printed as re.IGNORECASE|re.MULTILINE.

    It holds an int rather than being one: int subclasses do not take
    arithmetic in this runtime yet.  It takes |, &, ^ and ~ with ints and
    with itself, and int(), so a program combines and tests flags as it
    would in CPython.
    """

    def __init__(self, value=0):
        self._value = _flagint(value)

    def __int__(self):
        return self._value

    def __index__(self):
        return self._value

    def __repr__(self):
        v = self._value
        if v == 0:
            return "re.NOFLAG"
        names = []
        for name, bit in _FLAG_NAMES:
            if v & bit:
                names.append("re." + name)
                v &= ~bit
        if v:
            names.append(hex(v))
        return "|".join(names)

    __str__ = __repr__

    def __or__(self, other):
        return RegexFlag(self._value | _flagint(other))

    __ror__ = __or__

    def __and__(self, other):
        return RegexFlag(self._value & _flagint(other))

    __rand__ = __and__

    def __xor__(self, other):
        return RegexFlag(self._value ^ _flagint(other))

    __rxor__ = __xor__

    def __invert__(self):
        return RegexFlag(~self._value & 511)

    def __bool__(self):
        return self._value != 0

    def __eq__(self, other):
        if isinstance(other, (int, RegexFlag)):
            return self._value == _flagint(other)
        return NotImplemented

    def __hash__(self):
        return hash(self._value)


def _flagint(f):
    if isinstance(f, RegexFlag):
        return f._value
    if isinstance(f, int):
        return f
    raise TypeError("flags must be an int or a RegexFlag, not '%s'" % type(f).__name__)


_FLAG_NAMES = [("TEMPLATE", 1), ("IGNORECASE", 2), ("LOCALE", 4),
               ("MULTILINE", 8), ("DOTALL", 16), ("UNICODE", 32),
               ("VERBOSE", 64), ("DEBUG", 128), ("ASCII", 256)]

NOFLAG = RegexFlag(0)
I = IGNORECASE = RegexFlag(2)
L = LOCALE = RegexFlag(4)
M = MULTILINE = RegexFlag(8)
S = DOTALL = RegexFlag(16)
U = UNICODE = RegexFlag(32)
X = VERBOSE = RegexFlag(64)
DEBUG = RegexFlag(128)
A = ASCII = RegexFlag(256)

_FLAG_LETTERS = {"i": 2, "L": 4, "m": 8, "s": 16, "u": 32, "x": 64, "a": 256}


class error(Exception):
    """A pattern that is not a regular expression."""

    def __init__(self, msg, pattern=None, pos=None):
        self.msg = msg
        self.pattern = pattern
        self.pos = pos
        if pattern is not None and pos is not None:
            nl = "\n" if isinstance(pattern, str) else b"\n"
            self.lineno = pattern.count(nl, 0, pos) + 1
            self.colno = pos - pattern.rfind(nl, 0, pos)
            if nl in pattern:
                msg = "%s (line %d, column %d)" % (msg, self.lineno, self.colno)
            else:
                msg = "%s at position %d" % (msg, pos)
        else:
            self.lineno = self.colno = None
        Exception.__init__(self, msg)


PatternError = error


# --- the parser ----------------------------------------------------------------
#
# The pattern is read as a list of code points, so a str and a bytes pattern
# are one parse.  Each node is the tuple _sre.x documents, with every flag
# already settled into it.

_REPEAT_CHARS = "*+?{"
_SPECIAL = "\\[](){}|^$.*+?"
_DIGITS = "0123456789"
_HEX = "0123456789abcdefABCDEF"
_OCT = "01234567"
_ASCII_LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_ESCAPES = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11, "\\": 92}
_CATS = {"d": (0, 0), "D": (0, 1), "w": (1, 0), "W": (1, 1), "s": (2, 0), "S": (2, 1)}
_WHITESPACE = " \t\n\r\v\f"


class _Parser:

    def __init__(self, pattern, flags):
        self.pattern = pattern
        self.is_bytes = not isinstance(pattern, str)
        if self.is_bytes:
            self.src = [chr(b) for b in pattern]
        else:
            self.src = list(pattern)
        self.n = len(self.src)
        self.pos = 0
        self.flags = flags
        self.groups = 1
        self.groupindex = {}
        self.open = []
        self.lookbehind = False

    def error(self, msg, pos=None):
        return error(msg, self.pattern, self.pos if pos is None else pos)

    def peek(self):
        return self.src[self.pos] if self.pos < self.n else None

    def get(self):
        c = self.src[self.pos]
        self.pos += 1
        return c

    def skip_verbose(self, flags):
        if not flags & 64:
            return
        while self.pos < self.n:
            c = self.src[self.pos]
            if c in _WHITESPACE:
                self.pos += 1
            elif c == "#":
                while self.pos < self.n and self.src[self.pos] != "\n":
                    self.pos += 1
            else:
                return

    # --- alternatives and sequences ------------------------------------------

    def parse(self):
        node = self.parse_alt(self.flags, 0)
        if self.pos < self.n:
            if self.src[self.pos] == ")":
                raise self.error("unbalanced parenthesis")
            raise self.error("internal error")
        return node

    def parse_alt(self, flags, nested):
        branches = [self.parse_seq(flags, nested)]
        while self.peek() == "|":
            self.pos += 1
            branches.append(self.parse_seq(flags, nested))
        if len(branches) == 1:
            return branches[0]
        return (5, tuple(branches))

    def parse_seq(self, flags, nested):
        items = []
        while True:
            self.skip_verbose(flags)
            c = self.peek()
            if c is None or c == "|" or c == ")":
                break
            start = self.pos
            if c in _REPEAT_CHARS and not (c == "{" and not self.is_quant()):
                raise self.error("nothing to repeat")
            atom, flags = self.parse_atom(flags, nested)
            if atom is None:
                continue
            self.skip_verbose(flags)
            atom = self.parse_quant(atom, flags, start)
            items.append(atom)
        if len(items) == 1:
            return items[0]
        return (4, tuple(items))

    # --- repeats -------------------------------------------------------------

    def is_quant(self):
        # {m}, {m,}, {,n} or {m,n}: anything else is a literal brace
        i = self.pos + 1
        j = i
        while j < self.n and self.src[j] in _DIGITS:
            j += 1
        k = j
        if k < self.n and self.src[k] == ",":
            k += 1
            while k < self.n and self.src[k] in _DIGITS:
                k += 1
        return k < self.n and self.src[k] == "}" and k > i

    def parse_quant(self, atom, flags, start):
        c = self.peek()
        if c is None or c not in _REPEAT_CHARS:
            return atom
        if c == "{" and not self.is_quant():
            return atom
        if atom[0] == 9 or atom[0] == 10:
            raise self.error("nothing to repeat", start)
        here = self.pos
        self.pos += 1
        if c == "*":
            lo, hi = 0, _MAXREPEAT
        elif c == "+":
            lo, hi = 1, _MAXREPEAT
        elif c == "?":
            lo, hi = 0, 1
        else:
            lo = self.read_int()
            if self.peek() == ",":
                self.pos += 1
                hi = self.read_int()
                if hi is None:
                    hi = _MAXREPEAT
            else:
                hi = lo
            if lo is None:
                lo = 0
            self.pos += 1
            if hi != _MAXREPEAT and hi < lo:
                raise self.error("min repeat greater than max repeat", here + 1)
        mode = 1
        nxt = self.peek()
        if nxt == "?":
            self.pos += 1
            mode = 0
        elif nxt == "+":
            self.pos += 1
            mode = 2
        self.skip_verbose(flags)
        nxt = self.peek()
        if nxt is not None and nxt in _REPEAT_CHARS and not (nxt == "{" and not self.is_quant()):
            raise self.error("multiple repeat")
        return (6, lo, hi, mode, atom)

    def read_int(self):
        start = self.pos
        while self.pos < self.n and self.src[self.pos] in _DIGITS:
            self.pos += 1
        if self.pos == start:
            return None
        return int("".join(self.src[start:self.pos]))

    # --- atoms ---------------------------------------------------------------

    def lit(self, cp, flags):
        if flags & 2:
            return (13, _sre.lower(cp))
        return (0, cp)

    def cat(self, flags, letter):
        cat, neg = _CATS[letter]
        if flags & 256 or self.is_bytes:
            cat += 3
        return (1, cat, neg)

    def parse_atom(self, flags, nested):
        c = self.get()
        if c == ".":
            return ((2,) if flags & 16 else (1,)), flags
        if c == "^":
            return ((9, 1) if flags & 8 else (9, 0)), flags
        if c == "$":
            return ((9, 3) if flags & 8 else (9, 2)), flags
        if c == "[":
            return self.parse_class(flags), flags
        if c == "(":
            return self.parse_group(flags, nested)
        if c == "\\":
            return self.parse_escape(flags), flags
        return self.lit(ord(c), flags), flags

    def parse_escape(self, flags):
        start = self.pos - 1
        if self.pos >= self.n:
            raise self.error("bad escape (end of pattern)", start)
        c = self.get()
        if c in _CATS:
            return (14 if flags & 2 else 3, 0, self.cat(flags, c))
        if c == "A":
            return (9, 0)
        if c == "Z":
            return (9, 4)
        if c == "b":
            return (9, 7 if (flags & 256 or self.is_bytes) else 5)
        if c == "B":
            return (9, 8 if (flags & 256 or self.is_bytes) else 6)
        if c in _DIGITS:
            # an octal escape, or a group reference
            if c == "0":
                return self.lit(self.read_octal(c, 2), flags)
            if (self.pos + 1 < self.n and self.src[self.pos] in _OCT and c in _OCT
                    and self.src[self.pos + 1] in _OCT):
                v = self.read_octal(c, 2)
                if v > 255:
                    raise self.error("octal escape value \\%s outside of range 0-0o377"
                                     % "".join(self.src[start + 1:self.pos]), start)
                return self.lit(v, flags)
            num = c
            if self.pos < self.n and self.src[self.pos] in _DIGITS:
                num += self.get()
            g = int(num)
            if g >= self.groups:
                raise self.error("invalid group reference %d" % g, start + 1)
            if g in self.open:
                raise self.error("cannot refer to an open group", start)
            if self.lookbehind:
                raise self.error("cannot refer to group defined in the same lookbehind subpattern", start)
            return (15 if flags & 2 else 8, g)
        return self.lit(self.escape_code(c, start, False), flags)

    def read_octal(self, first, more):
        digits = first
        while more and self.pos < self.n and self.src[self.pos] in _OCT:
            digits += self.get()
            more -= 1
        return int(digits, 8)

    def read_hex(self, count, start, c):
        digits = "".join(self.src[self.pos:self.pos + count])
        if len(digits) != count or any(d not in _HEX for d in digits):
            raise self.error("incomplete escape \\%s%s" % (c, digits), start)
        self.pos += count
        return int(digits, 16)

    def escape_code(self, c, start, in_class):
        # the code point of an escape that stands for one
        if c in _ESCAPES and (c != "b" or in_class):
            return _ESCAPES[c]
        if c == "x":
            return self.read_hex(2, start, c)
        if c == "u" and not self.is_bytes:
            return self.read_hex(4, start, c)
        if c == "U" and not self.is_bytes:
            v = self.read_hex(8, start, c)
            if v > 0x10FFFF:
                raise self.error("bad escape \\U%08x" % v, start)
            return v
        if c in _OCT and in_class:
            return self.read_octal(c, 2)
        if c in _ASCII_LETTERS or c in _DIGITS:
            raise self.error("bad escape \\" + c, start)
        return ord(c)

    # --- classes -------------------------------------------------------------

    def parse_class(self, flags):
        start = self.pos - 1
        neg = 0
        if self.peek() == "^":
            self.pos += 1
            neg = 1
        items = []
        first = True
        while True:
            if self.pos >= self.n:
                raise self.error("unterminated character set", start)
            c = self.get()
            if c == "]" and not first:
                break
            first = False
            here = self.pos - 1
            if c == "\\":
                if self.pos >= self.n:
                    raise self.error("unterminated character set", start)
                e = self.get()
                if e in _CATS:
                    items.extend(self.cat(flags, e))
                    continue
                lo = self.escape_code(e, here, True)
            else:
                lo = ord(c)
            if (self.peek() == "-" and self.pos + 1 < self.n
                    and self.src[self.pos + 1] != "]"):
                self.pos += 1
                d = self.get()
                if d == "\\":
                    if self.pos >= self.n:
                        raise self.error("unterminated character set", start)
                    e = self.get()
                    if e in _CATS:
                        raise self.error("bad character range %s" % "".join(self.src[here:self.pos]), here)
                    hi = self.escape_code(e, self.pos - 2, True)
                else:
                    hi = ord(d)
                if hi < lo:
                    raise self.error("bad character range %s" % "".join(self.src[here:self.pos]), here)
            else:
                hi = lo
            items.extend((0, lo, hi))
        return (14 if flags & 2 else 3, neg, tuple(items))

    # --- groups --------------------------------------------------------------

    def read_name(self, end):
        start = self.pos
        while self.pos < self.n and self.src[self.pos] != end:
            self.pos += 1
        if self.pos >= self.n:
            raise self.error("missing %s, unterminated name" % end, start)
        name = "".join(self.src[start:self.pos])
        self.pos += 1
        if not name:
            raise self.error("missing group name", start)
        return name, start

    def check_name(self, name, start):
        if not _isident(name):
            raise self.error("bad character in group name %r" % name, start)

    def close(self, start):
        if self.peek() != ")":
            raise self.error("missing ), unterminated subpattern", start)
        self.pos += 1

    def capture(self, flags, nested, start, name):
        g = self.groups
        self.groups += 1
        if name is not None:
            self.groupindex[name] = g
        self.open.append(g)
        node = self.parse_alt(flags, nested + 1)
        self.close(start)
        self.open.remove(g)
        return (7, g, node)

    def parse_group(self, flags, nested):
        start = self.pos - 1
        if self.peek() != "?":
            return self.capture(flags, nested, start, None), flags
        self.pos += 1
        if self.pos >= self.n:
            raise self.error("unexpected end of pattern")
        c = self.get()
        if c == ":":
            node = self.parse_alt(flags, nested + 1)
            self.close(start)
            return node, flags
        if c == "P":
            if self.pos >= self.n:
                raise self.error("unexpected end of pattern")
            d = self.get()
            if d == "<":
                name, nstart = self.read_name(">")
                self.check_name(name, nstart)
                if name in self.groupindex:
                    raise self.error("redefinition of group name %r as group %d; was group %d"
                                     % (name, self.groups, self.groupindex[name]), nstart)
                return self.capture(flags, nested, start, name), flags
            if d == "=":
                name, nstart = self.read_name(")")
                self.check_name(name, nstart)
                if name not in self.groupindex:
                    raise self.error("unknown group name %r" % name, nstart)
                g = self.groupindex[name]
                if g in self.open:
                    raise self.error("cannot refer to an open group", nstart)
                return (15 if flags & 2 else 8, g), flags
            raise self.error("unknown extension ?P" + d, start + 1)
        if c == "#":
            while self.pos < self.n and self.src[self.pos] != ")":
                self.pos += 1
            if self.pos >= self.n:
                raise self.error("missing ), unterminated comment", start)
            self.pos += 1
            return None, flags
        if c == "=" or c == "!":
            node = self.parse_alt(flags, nested + 1)
            self.close(start)
            return (10, 0, 1 if c == "!" else 0, 0, node), flags
        if c == "<":
            if self.pos >= self.n:
                raise self.error("unexpected end of pattern")
            d = self.get()
            if d != "=" and d != "!":
                raise self.error("unknown extension ?<" + d, start + 1)
            was = self.lookbehind
            self.lookbehind = True
            node = self.parse_alt(flags, nested + 1)
            self.lookbehind = was
            self.close(start)
            lo, hi = _width(node)
            if lo != hi:
                raise self.error("look-behind requires fixed-width pattern")
            return (10, 1, 1 if d == "!" else 0, lo, node), flags
        if c == ">":
            node = self.parse_alt(flags, nested + 1)
            self.close(start)
            return (11, node), flags
        if c == "(":
            return self.parse_cond(flags, nested, start), flags
        if c in _FLAG_LETTERS or c == "-":
            self.pos -= 1
            return self.parse_flags(flags, nested, start)
        raise self.error("unknown extension ?" + c, start + 1)

    def parse_cond(self, flags, nested, start):
        name, nstart = self.read_name(")")
        if name.isdigit():
            g = int(name)
            if g == 0:
                raise self.error("bad group number", nstart)
            if g >= self.groups:
                raise self.error("invalid group reference %d" % g, nstart)
        else:
            self.check_name(name, nstart)
            if name not in self.groupindex:
                raise self.error("unknown group name %r" % name, nstart)
            g = self.groupindex[name]
        yes = self.parse_seq(flags, nested + 1)
        no = (4, ())
        if self.peek() == "|":
            self.pos += 1
            no = self.parse_seq(flags, nested + 1)
            if self.peek() == "|":
                raise self.error("conditional backref with more than two branches")
        self.close(start)
        return (12, g, yes, no)

    def parse_flags(self, flags, nested, start):
        on = 0
        off = 0
        while self.pos < self.n and self.src[self.pos] in _FLAG_LETTERS:
            on |= _FLAG_LETTERS[self.get()]
        if self.peek() == "-":
            self.pos += 1
            while self.pos < self.n and self.src[self.pos] in _FLAG_LETTERS:
                off |= _FLAG_LETTERS[self.get()]
            if not off:
                raise self.error("missing flag", self.pos)
            if self.peek() != ":":
                raise self.error("missing :", self.pos)
        c = self.peek()
        if c is None:
            raise self.error("missing -, : or )", self.pos)
        if c == ")":
            self.pos += 1
            if start != 0:
                raise self.error("global flags not at the start of the expression", start)
            self.flags |= on
            return None, flags | on
        if c != ":":
            raise self.error("unknown flag" if c.isalpha() else "missing -, : or )", self.pos)
        self.pos += 1
        node = self.parse_alt((flags | on) & ~off, nested + 1)
        self.close(start)
        return node, flags


def _isident(name):
    # str.isidentifier, which this runtime's str does not have yet; a code
    # point past ASCII is taken as a letter
    if not name:
        return False
    for i, c in enumerate(name):
        if c == "_" or c.isalpha() or ord(c) > 127:
            continue
        if i and c.isdigit():
            continue
        return False
    return True


def _width(node):
    # the least and the most a node can match; -1 is no bound
    op = node[0]
    if op in (0, 1, 2, 3, 13, 14):
        return 1, 1
    if op == 4:
        lo = hi = 0
        for n in node[1]:
            a, b = _width(n)
            lo += a
            hi = -1 if hi < 0 or b < 0 else hi + b
        return lo, hi
    if op == 5:
        ws = [_width(n) for n in node[1]]
        lo = min(w[0] for w in ws)
        hi = -1 if any(w[1] < 0 for w in ws) else max(w[1] for w in ws)
        return lo, hi
    if op == 6:
        a, b = _width(node[4])
        lo = a * node[1]
        hi = -1 if node[2] < 0 or b < 0 else b * node[2]
        return lo, hi
    if op == 7:
        return _width(node[2])
    if op == 11:
        return _width(node[1])
    if op == 12:
        a, b = _width(node[2])
        c, d = _width(node[3])
        return min(a, c), (-1 if b < 0 or d < 0 else max(b, d))
    if op in (8, 15):
        return 0, -1
    return 0, 0


# --- compiled patterns ---------------------------------------------------------

class Pattern:
    """A compiled regular expression."""

    def __init__(self, pattern, flags, code, groups, groupindex):
        self.pattern = pattern
        self.flags = flags
        self._code = code
        self.groups = groups
        self.groupindex = groupindex
        self._bytes = not isinstance(pattern, str)

    def __repr__(self):
        r = repr(self.pattern)
        if len(r) > 200:
            r = r[:200]
        f = _flagint(self.flags)
        if not self._bytes:
            f &= ~32
        if f:
            return "re.compile(%s, %r)" % (r, RegexFlag(f))
        return "re.compile(%s)" % r

    def __eq__(self, other):
        if not isinstance(other, Pattern):
            return NotImplemented
        return self.pattern == other.pattern and self.flags == other.flags

    def __hash__(self):
        return hash((self.pattern, self.flags))

    def _check(self, string):
        if self._bytes:
            if isinstance(string, str):
                raise TypeError("cannot use a bytes pattern on a string-like object")
        elif not isinstance(string, str):
            if isinstance(string, (bytes, bytearray, memoryview)):
                raise TypeError("cannot use a string pattern on a bytes-like object")
            raise TypeError("expected string or bytes-like object, got '%s'"
                            % type(string).__name__)

    def _run(self, string, pos, endpos, mode, forbid):
        self._check(string)
        if endpos is None:
            endpos = _MAXPOS
        n = len(string)
        if pos < 0:
            pos = 0
        if endpos > n:
            endpos = n
        marks = _sre.match(self._code, self.groups, string, pos, endpos, mode, forbid)
        if marks is None:
            return None
        return Match(self, string, pos, endpos, marks)

    def match(self, string, pos=0, endpos=None):
        return self._run(string, pos, endpos, 0, -1)

    def fullmatch(self, string, pos=0, endpos=None):
        return self._run(string, pos, endpos, 1, -1)

    def search(self, string, pos=0, endpos=None):
        return self._run(string, pos, endpos, 2, -1)

    def finditer(self, string, pos=0, endpos=None):
        if endpos is None:
            endpos = _MAXPOS
        forbid = -1
        while True:
            m = self._run(string, pos, endpos, 2, forbid)
            if m is None:
                return
            yield m
            s, e = m.span()
            pos = e
            forbid = e if s == e else -1

    def findall(self, string, pos=0, endpos=None):
        out = []
        for m in self.finditer(string, pos, endpos):
            if self.groups == 0:
                out.append(m.group(0))
            elif self.groups == 1:
                out.append(m.group(1) if m.start(1) >= 0 else string[:0])
            else:
                out.append(m.groups(string[:0]))
        return out

    def split(self, string, maxsplit=0):
        out = []
        last = 0
        n = 0
        for m in self.finditer(string):
            if maxsplit and n >= maxsplit:
                break
            s, e = m.span()
            out.append(string[last:s])
            out.extend(m.groups())
            last = e
            n += 1
        out.append(string[last:])
        return out

    def subn(self, repl, string, count=0):
        if callable(repl):
            expand = repl
        else:
            pieces = _template(self, repl)
            if len(pieces) == 1 and not isinstance(pieces[0], int):
                lit = pieces[0]
                expand = lambda m: lit
            else:
                expand = lambda m: _expand(m, pieces)
        out = []
        last = 0
        n = 0
        for m in self.finditer(string):
            if count and n >= count:
                break
            s, e = m.span()
            out.append(string[last:s])
            out.append(expand(m))
            last = e
            n += 1
        out.append(string[last:])
        return string[:0].join(out), n

    def sub(self, repl, string, count=0):
        return self.subn(repl, string, count)[0]

    def __copy__(self):
        return self

    def __deepcopy__(self, memo):
        return self


# --- a match -----------------------------------------------------------------

class Match:
    """The result of a successful match."""

    def __init__(self, pattern, string, pos, endpos, marks):
        self.re = pattern
        self.string = string
        self.pos = pos
        self.endpos = endpos
        self._marks = marks
        li = marks[0]
        self.lastindex = None if li < 0 else li
        self.lastgroup = None
        if li >= 0:
            for name, g in pattern.groupindex.items():
                if g == li:
                    self.lastgroup = name

    def _index(self, g):
        if isinstance(g, int) and not isinstance(g, bool):
            if 0 <= g <= self.re.groups:
                return g
        elif isinstance(g, str):
            if g in self.re.groupindex:
                return self.re.groupindex[g]
        else:
            try:
                g = g.__index__()
            except AttributeError:
                raise IndexError("no such group")
            return self._index(g)
        raise IndexError("no such group")

    def span(self, group=0):
        g = self._index(group)
        return (self._marks[2 * g + 1], self._marks[2 * g + 2])

    def start(self, group=0):
        return self.span(group)[0]

    def end(self, group=0):
        return self.span(group)[1]

    @property
    def regs(self):
        return tuple(self.span(g) for g in range(self.re.groups + 1))

    def _group(self, g, default=None):
        s, e = self.span(g)
        if s < 0:
            return default
        return self.string[s:e]

    def group(self, *args):
        if not args:
            return self._group(0)
        if len(args) == 1:
            return self._group(args[0])
        return tuple(self._group(a) for a in args)

    def __getitem__(self, g):
        return self._group(g)

    def groups(self, default=None):
        return tuple(self._group(g, default) for g in range(1, self.re.groups + 1))

    def groupdict(self, default=None):
        return {name: self._group(g, default) for name, g in self.re.groupindex.items()}

    def expand(self, template):
        return _expand(self, _template(self.re, template))

    def __bool__(self):
        return True

    def __repr__(self):
        return "<re.Match object; span=%r, match=%r>" % (self.span(), self.group(0))

    def __copy__(self):
        return self

    def __deepcopy__(self, memo):
        return self


# --- replacement templates -----------------------------------------------------

def _template(pattern, repl):
    # the pieces of a replacement: literal text, and group numbers as ints
    is_bytes = not isinstance(repl, str)
    if is_bytes != pattern._bytes:
        if is_bytes:
            raise TypeError("expected str instance, %s found" % type(repl).__name__)
        raise TypeError("expected a bytes-like object, %s found" % type(repl).__name__)
    src = [chr(b) for b in repl] if is_bytes else repl
    n = len(src)
    pieces = []
    lit = []
    i = 0

    def flush():
        if lit:
            text = "".join(lit)
            pieces.append(bytes([ord(c) for c in text]) if is_bytes else text)
            del lit[:]

    def fail(msg, pos):
        raise error(msg, repl, pos)

    while i < n:
        c = src[i]
        if c != "\\":
            lit.append(c)
            i += 1
            continue
        start = i
        i += 1
        if i >= n:
            fail("bad escape (end of pattern)", start)
        c = src[i]
        i += 1
        if c == "g":
            if i >= n or src[i] != "<":
                fail("missing <", i)
            j = i + 1
            while j < n and src[j] != ">":
                j += 1
            if j >= n:
                fail("missing >, unterminated name", i + 1)
            name = "".join(src[i + 1:j])
            if not name:
                fail("missing group name", i + 1)
            if name.isdigit():
                g = int(name)
                if g > pattern.groups:
                    fail("invalid group reference %d" % g, i + 1)
            else:
                if not _isident(name):
                    fail("bad character in group name %r" % name, i + 1)
                if name not in pattern.groupindex:
                    raise IndexError("unknown group name %r" % name)
                g = pattern.groupindex[name]
            i = j + 1
            flush()
            pieces.append(g)
        elif c == "0":
            j = i
            while j < n and j < i + 2 and src[j] in _OCT:
                j += 1
            lit.append(chr(int("0" + "".join(src[i:j]), 8)))
            i = j
        elif c in _DIGITS:
            if (i + 1 < n and c in _OCT and src[i] in _OCT and src[i + 1] in _OCT):
                v = int(c + src[i] + src[i + 1], 8)
                if v > 255:
                    fail("octal escape value \\%s outside of range 0-0o377"
                         % (c + src[i] + src[i + 1]), start)
                lit.append(chr(v))
                i += 2
                continue
            num = c
            if i < n and src[i] in _DIGITS:
                num += src[i]
                i += 1
            g = int(num)
            if g > pattern.groups:
                fail("invalid group reference %d" % g, start + 1)
            flush()
            pieces.append(g)
        elif c in _ESCAPES:
            lit.append(chr(_ESCAPES[c]))
        elif c in _ASCII_LETTERS:
            fail("bad escape \\" + c, start)
        else:
            lit.append("\\" + c)
    flush()
    if not pieces:
        pieces.append(repl[:0])
    return pieces


def _expand(m, pieces):
    empty = m.string[:0]
    out = []
    for p in pieces:
        if isinstance(p, int):
            v = m.group(p)
            out.append(empty if v is None else v)
        else:
            out.append(p)
    return empty.join(out)


# --- the module's functions --------------------------------------------------

_cache = {}
_MAXCACHE = 512


def compile(pattern, flags=0):
    """Compile pattern into a Pattern."""
    if isinstance(pattern, Pattern):
        if flags:
            raise ValueError("cannot process flags argument with a compiled pattern")
        return pattern
    if not isinstance(pattern, (str, bytes)):
        raise TypeError("first argument must be string or compiled pattern")
    flags = _flagint(flags)
    key = (type(pattern), pattern, flags)
    p = _cache.get(key)
    if p is not None:
        return p
    if isinstance(pattern, str):
        if flags & 256 and flags & 32:
            raise ValueError("ASCII and UNICODE flags are incompatible")
        if not flags & 256:
            flags |= 32
    else:
        if flags & 32:
            raise ValueError("cannot use UNICODE flag with a bytes pattern")
        if flags & 4 and flags & 256:
            raise ValueError("ASCII and LOCALE flags are incompatible")
    parser = _Parser(pattern, flags)
    node = parser.parse()
    flags = parser.flags
    if isinstance(pattern, str) and flags & 256:
        flags &= ~32
    p = Pattern(pattern, RegexFlag(flags), _sre.compile(node), parser.groups - 1,
                parser.groupindex)
    if len(_cache) >= _MAXCACHE:
        _cache.clear()
    _cache[key] = p
    return p


def purge():
    """Clear the cache of compiled patterns."""
    _cache.clear()


def match(pattern, string, flags=0):
    return compile(pattern, flags).match(string)


def fullmatch(pattern, string, flags=0):
    return compile(pattern, flags).fullmatch(string)


def search(pattern, string, flags=0):
    return compile(pattern, flags).search(string)


def sub(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags).sub(repl, string, count)


def subn(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags).subn(repl, string, count)


def split(pattern, string, maxsplit=0, flags=0):
    return compile(pattern, flags).split(string, maxsplit)


def findall(pattern, string, flags=0):
    return compile(pattern, flags).findall(string)


def finditer(pattern, string, flags=0):
    return compile(pattern, flags).finditer(string)


_SPECIAL_CHARS = "()[]{}?*+-|^$\\.&~# \t\n\r\v\f"


def escape(pattern):
    """pattern with every character that is special in a pattern escaped."""
    if isinstance(pattern, str):
        return "".join("\\" + c if c in _SPECIAL_CHARS else c for c in pattern)
    out = bytearray()
    for b in pattern:
        if chr(b) in _SPECIAL_CHARS:
            out.append(92)
        out.append(b)
    return bytes(out)
