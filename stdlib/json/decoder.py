"""json.decoder -- JSONDecoder and JSONDecodeError.

x-python's own, written to CPython 3.14's interface, with its hooks:
a decoder reads objects with parse_object, arrays with parse_array and
strings with parse_string, and a subclass may replace any of them.  Each
error is the one CPython raises, at the same position.  CPython finds a
string's pieces and the whitespace between values with regular
expressions; this module scans for them by hand.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

from json import scanner

__all__ = ['JSONDecoder', 'JSONDecodeError']

NaN = float('nan')
PosInf = float('inf')
NegInf = float('-inf')


class JSONDecodeError(ValueError):
    """A ValueError that says where a document stopped making sense.

    msg is the message alone and doc the document; pos is the index the
    error is at, and lineno and colno its line and column, counted from 1.
    """

    def __init__(self, msg, doc, pos):
        lineno = doc.count('\n', 0, pos) + 1
        colno = pos - doc.rfind('\n', 0, pos)
        ValueError.__init__(
            self, '%s: line %d column %d (char %d)' % (msg, lineno, colno, pos))
        self.msg = msg
        self.doc = doc
        self.pos = pos
        self.lineno = lineno
        self.colno = colno

    def __reduce__(self):
        return self.__class__, (self.msg, self.doc, self.pos)


_CONSTANTS = {'-Infinity': NegInf, 'Infinity': PosInf, 'NaN': NaN}

# what follows a backslash, and what it stands for; \u is read apart
BACKSLASH = {
    '"': '"', '\\': '\\', '/': '/',
    'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t',
}

WHITESPACE_STR = ' \t\n\r'

_HEX = '0123456789abcdefABCDEF'


def _skip_ws(s, i):
    n = len(s)
    while i < n and s[i] in WHITESPACE_STR:
        i += 1
    return i


def _char(s, i):
    # the character at i, or '' past the end
    return s[i:i + 1]


def _hex4(s, backslash):
    # the code the four hex digits after the \u at backslash spell
    digits = s[backslash + 2:backslash + 6]
    if len(digits) == 4 and all(c in _HEX for c in digits):
        return int(digits, 16)
    raise JSONDecodeError("Invalid \\uXXXX escape", s, backslash + 1)


def py_scanstring(s, end, strict=True, _b=BACKSLASH):
    """Read the JSON string whose opening quote is just before end.

    Answers the string, unescaped, and the index after its closing quote.
    With strict false, a control character may stand in it as itself."""
    start = end - 1
    n = len(s)
    parts = []
    i = end
    while True:
        # a run of characters that stand for themselves
        j = i
        while j < n and s[j] != '"' and s[j] != '\\' and s[j] >= ' ':
            j += 1
        if j == n:
            raise JSONDecodeError("Unterminated string starting at", s, start)
        if j > i:
            parts.append(s[i:j])
        c = s[j]
        if c == '"':
            return ''.join(parts), j + 1
        if c != '\\':
            if strict:
                raise JSONDecodeError("Invalid control character at", s, j)
            parts.append(c)
            i = j + 1
            continue
        if j + 1 == n:
            raise JSONDecodeError("Unterminated string starting at", s, start)
        e = s[j + 1]
        if e != 'u':
            if e not in _b:
                raise JSONDecodeError("Invalid \\escape", s, j)
            parts.append(_b[e])
            i = j + 2
            continue
        code = _hex4(s, j)
        i = j + 6
        # a high surrogate, then a low one, are one character between them
        if 0xd800 <= code <= 0xdbff and s[i:i + 2] == '\\u':
            low = _hex4(s, i)
            if 0xdc00 <= low <= 0xdfff:
                code = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00)
                i += 6
        parts.append(chr(code))


scanstring = py_scanstring


def JSONObject(s_and_end, strict, scan_once, object_hook, object_pairs_hook,
               memo=None, _ws=WHITESPACE_STR):
    """Read the members of the object whose '{' is just before end."""
    s, i = s_and_end
    if memo is None:
        memo = {}
    pairs = []
    i = _skip_ws(s, i)
    c = _char(s, i)
    if c == '}':
        return _finish_object(pairs, object_hook, object_pairs_hook, True), i + 1
    if c != '"':
        raise JSONDecodeError(
            "Expecting property name enclosed in double quotes", s, i)
    while True:
        # i is at the key's opening quote
        key, i = scanstring(s, i + 1, strict)
        key = memo.setdefault(key, key)
        i = _skip_ws(s, i)
        if _char(s, i) != ':':
            raise JSONDecodeError("Expecting ':' delimiter", s, i)
        i = _skip_ws(s, i + 1)
        try:
            value, i = scan_once(s, i)
        except StopIteration as err:
            raise JSONDecodeError("Expecting value", s, err.value) from None
        pairs.append((key, value))
        i = _skip_ws(s, i)
        c = _char(s, i)
        if c == '}':
            return _finish_object(pairs, object_hook, object_pairs_hook,
                                  False), i + 1
        if c != ',':
            raise JSONDecodeError("Expecting ',' delimiter", s, i)
        comma = i
        i = _skip_ws(s, i + 1)
        c = _char(s, i)
        if c != '"':
            if c == '}':
                raise JSONDecodeError(
                    "Illegal trailing comma before end of object", s, comma)
            raise JSONDecodeError(
                "Expecting property name enclosed in double quotes", s, i)


def _finish_object(pairs, object_hook, object_pairs_hook, empty):
    # object_pairs_hook sees the pairs; otherwise they become a dict, the
    # last of a repeated key winning, and object_hook sees that
    if object_pairs_hook is not None:
        return object_pairs_hook(pairs)
    d = {} if empty else dict(pairs)
    if object_hook is not None:
        return object_hook(d)
    return d


def JSONArray(s_and_end, scan_once, _ws=WHITESPACE_STR):
    """Read the elements of the array whose '[' is just before end."""
    s, i = s_and_end
    values = []
    i = _skip_ws(s, i)
    if _char(s, i) == ']':
        return values, i + 1
    while True:
        try:
            value, i = scan_once(s, i)
        except StopIteration as err:
            raise JSONDecodeError("Expecting value", s, err.value) from None
        values.append(value)
        i = _skip_ws(s, i)
        c = _char(s, i)
        if c == ']':
            return values, i + 1
        if c != ',':
            raise JSONDecodeError("Expecting ',' delimiter", s, i)
        comma = i
        i = _skip_ws(s, i + 1)
        if _char(s, i) == ']':
            raise JSONDecodeError(
                "Illegal trailing comma before end of array", s, comma)


class JSONDecoder(object):
    """Reads a JSON document into Python values.

    An object becomes a dict, an array a list, a string a str, a number
    an int or, with a fraction or an exponent, a float, and true, false and
    null True, False and None.  NaN, Infinity and -Infinity, which aren't
    standard JSON, become the floats they name.

    object_hook, given, is called on each dict and answers what stands in
    its place; object_pairs_hook, given, is called on each object's list of
    (key, value) pairs instead.  parse_float, parse_int and parse_constant
    read a number's or a constant's text.  With strict false, a string may
    hold control characters as themselves.
    """

    def __init__(self, *, object_hook=None, parse_float=None,
                 parse_int=None, parse_constant=None, strict=True,
                 object_pairs_hook=None):
        self.object_hook = object_hook
        self.parse_float = parse_float or float
        self.parse_int = parse_int or int
        self.parse_constant = parse_constant or _CONSTANTS.__getitem__
        self.strict = strict
        self.object_pairs_hook = object_pairs_hook
        self.parse_object = JSONObject
        self.parse_array = JSONArray
        self.parse_string = scanstring
        self.memo = {}
        self.scan_once = scanner.make_scanner(self)

    def decode(self, s):
        """The value the JSON document s, a str, holds; whitespace may come
        before and after it, and nothing else."""
        obj, end = self.raw_decode(s, idx=_skip_ws(s, 0))
        end = _skip_ws(s, end)
        if end != len(s):
            raise JSONDecodeError("Extra data", s, end)
        return obj

    def raw_decode(self, s, idx=0):
        """The value the JSON document starting at s[idx] holds, and the
        index where it ends; anything may follow it."""
        try:
            return self.scan_once(s, idx)
        except StopIteration as err:
            raise JSONDecodeError("Expecting value", s, err.value) from None
