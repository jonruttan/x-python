"""json.encoder -- JSONEncoder.

x-python's own, written to CPython 3.14's interface.  CPython finds the
characters a string must escape with regular expressions; this module
walks the string.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = ['JSONEncoder']

# the escapes JSON spells with a letter, and \u00XX for the other control
# characters
ESCAPE_DCT = {
    '\\': '\\\\',
    '"': '\\"',
    '\b': '\\b',
    '\f': '\\f',
    '\n': '\\n',
    '\r': '\\r',
    '\t': '\\t',
}
for _i in range(0x20):
    ESCAPE_DCT.setdefault(chr(_i), '\\u%04x' % _i)
del _i

INFINITY = float('inf')


def py_encode_basestring(s):
    """s as a JSON string, its quotes, backslashes and control characters
    escaped."""
    out = ['"']
    start = 0
    for i, c in enumerate(s):
        if c < ' ' or c == '"' or c == '\\':
            if i > start:
                out.append(s[start:i])
            out.append(ESCAPE_DCT[c])
            start = i + 1
    out.append(s[start:])
    out.append('"')
    return ''.join(out)


encode_basestring = py_encode_basestring


def _u_escape(c):
    # \uXXXX, or two of them, a surrogate pair, past the first plane
    n = ord(c)
    if n < 0x10000:
        return '\\u%04x' % n
    n -= 0x10000
    return '\\u%04x\\u%04x' % (0xd800 | (n >> 10), 0xdc00 | (n & 0x3ff))


def py_encode_basestring_ascii(s):
    """s as a JSON string of ASCII alone: py_encode_basestring's escapes,
    and \\uXXXX for every character outside ' ' to '~'."""
    out = ['"']
    start = 0
    for i, c in enumerate(s):
        if c < ' ' or c > '~' or c == '"' or c == '\\':
            if i > start:
                out.append(s[start:i])
            esc = ESCAPE_DCT.get(c)
            out.append(esc if esc is not None else _u_escape(c))
            start = i + 1
    out.append(s[start:])
    out.append('"')
    return ''.join(out)


encode_basestring_ascii = py_encode_basestring_ascii


class JSONEncoder(object):
    """Writes Python values as JSON.

    A dict becomes an object, a list or a tuple an array, a str a string,
    an int or a float a number, and True, False and None true, false and
    null.  For anything else, default(o) is asked for a value that can be
    written in its place; a subclass, or the default argument, says what.
    """
    item_separator = ', '
    key_separator = ': '

    def __init__(self, *, skipkeys=False, ensure_ascii=True,
                 check_circular=True, allow_nan=True, sort_keys=False,
                 indent=None, separators=None, default=None):
        """skipkeys: leave out a dict item whose key isn't a str, an int, a
        float, a bool or None, where otherwise it is a TypeError.

        ensure_ascii: escape every character outside ASCII.

        check_circular: refuse a container that holds itself, with a
        ValueError, rather than recurse without end.

        allow_nan: write NaN, Infinity and -Infinity, which standard JSON
        has no way to say; otherwise they are a ValueError.

        sort_keys: write a dict's items in the order of their keys.

        indent: a string, or a number of spaces, to indent each level of
        nesting by, a newline before each element; None writes it all on
        one line.

        separators: the (item_separator, key_separator) to write; without
        them, (', ', ': '), or (',', ': ') where there is an indent.

        default: a function that answers a value to write in place of one
        that can't be written.
        """
        self.skipkeys = skipkeys
        self.ensure_ascii = ensure_ascii
        self.check_circular = check_circular
        self.allow_nan = allow_nan
        self.sort_keys = sort_keys
        self.indent = indent
        if separators is not None:
            self.item_separator, self.key_separator = separators
        elif indent is not None:
            self.item_separator = ','
        if default is not None:
            self.default = default

    def default(self, o):
        """The value to write in place of o, which JSON has no way to say;
        this one raises the TypeError that says so."""
        raise TypeError('Object of type %s is not JSON serializable'
                        % o.__class__.__name__)

    def encode(self, o):
        """o written as JSON, as one str."""
        if isinstance(o, str):
            if self.ensure_ascii:
                return encode_basestring_ascii(o)
            return encode_basestring(o)
        return ''.join(self.iterencode(o, _one_shot=True))

    def iterencode(self, o, _one_shot=False):
        """o written as JSON, in the pieces a writer can send as they come."""
        markers = {} if self.check_circular else None
        _encoder = (encode_basestring_ascii if self.ensure_ascii
                    else encode_basestring)
        allow_nan = self.allow_nan

        def floatstr(o):
            if o != o:
                text = 'NaN'
            elif o == INFINITY:
                text = 'Infinity'
            elif o == -INFINITY:
                text = '-Infinity'
            else:
                return _float_repr(o)
            if not allow_nan:
                raise ValueError(
                    "Out of range float values are not JSON compliant: "
                    + repr(o))
            return text

        indent = self.indent
        if indent is not None and not isinstance(indent, str):
            indent = ' ' * indent
        _iterencode = _make_iterencode(
            markers, self.default, _encoder, indent, floatstr,
            self.key_separator, self.item_separator, self.sort_keys,
            self.skipkeys, _one_shot)
        return _iterencode(o, 0)


# A float subclass is written as the float it is, not as it prints, and an
# int subclass (an IntEnum, say) as the int it is.  x-python's float and int
# don't offer their __repr__ to call that way, so there the value is made
# plain first.
_float_repr = getattr(float, '__repr__', None)
if _float_repr is None:
    def _float_repr(o):
        return repr(o if type(o) is float else float(o))

_int_repr = getattr(int, '__repr__', None)
if _int_repr is None:
    def _int_repr(o):
        return repr(o if type(o) is int else int(o))


def _note(exc, text):
    # where in the value the error was, as CPython notes it
    add = getattr(exc, 'add_note', None)
    if add is not None:
        add(text)


def _make_iterencode(markers, _default, _encoder, _indent, _floatstr,
                     _key_separator, _item_separator, _sort_keys, _skipkeys,
                     _one_shot):

    def scalar(o):
        # o's JSON text, or None when o is a container or needs default
        if isinstance(o, str):
            return _encoder(o)
        if o is None:
            return 'null'
        if o is True:
            return 'true'
        if o is False:
            return 'false'
        if isinstance(o, int):
            return _int_repr(o)
        if isinstance(o, float):
            return _floatstr(o)
        return None

    def enter(o):
        if markers is not None:
            if id(o) in markers:
                raise ValueError("Circular reference detected")
            markers[id(o)] = o

    def leave(o):
        if markers is not None:
            del markers[id(o)]

    def compound(o, level):
        if isinstance(o, (list, tuple)):
            return encode_list(o, level)
        if isinstance(o, dict):
            return encode_dict(o, level)
        return encode_other(o, level)

    def encode_list(lst, level):
        if not lst:
            yield '[]'
            return
        enter(lst)
        if _indent is not None:
            level += 1
            newline = '\n' + _indent * level
            sep = _item_separator + newline
            lead = '[' + newline
        else:
            newline = None
            sep = _item_separator
            lead = '['
        for i, value in enumerate(lst):
            prefix = lead if i == 0 else sep
            try:
                text = scalar(value)
                if text is not None:
                    yield prefix + text
                else:
                    yield prefix
                    yield from compound(value, level)
            except GeneratorExit:
                raise
            except BaseException as exc:
                _note(exc, 'when serializing %s item %d'
                      % (type(lst).__name__, i))
                raise
        if newline is not None:
            yield '\n' + _indent * (level - 1)
        yield ']'
        leave(lst)

    def json_key(key):
        # a key's JSON text before it is quoted, or None to skip the item
        if isinstance(key, str):
            return key
        if isinstance(key, float):
            return _floatstr(key)
        if key is True:
            return 'true'
        if key is False:
            return 'false'
        if key is None:
            return 'null'
        if isinstance(key, int):
            return _int_repr(key)
        if _skipkeys:
            return None
        raise TypeError('keys must be str, int, float, bool or None, not %s'
                        % key.__class__.__name__)

    def encode_dict(dct, level):
        if not dct:
            yield '{}'
            return
        enter(dct)
        yield '{'
        if _indent is not None:
            level += 1
            newline = '\n' + _indent * level
            sep = _item_separator + newline
        else:
            newline = None
            sep = _item_separator
        items = sorted(dct.items()) if _sort_keys else dct.items()
        first = True
        for key, value in items:
            text_key = json_key(key)
            if text_key is None:
                continue
            if first:
                first = False
                if newline is not None:
                    yield newline
            else:
                yield sep
            yield _encoder(text_key)
            yield _key_separator
            try:
                text = scalar(value)
                if text is not None:
                    yield text
                else:
                    yield from compound(value, level)
            except GeneratorExit:
                raise
            except BaseException as exc:
                # the key as it was given, not as it is written
                _note(exc, 'when serializing %s item %r'
                      % (type(dct).__name__, key))
                raise
        if not first and newline is not None:
            yield '\n' + _indent * (level - 1)
        yield '}'
        leave(dct)

    def encode_other(o, level):
        # what default answers for o, written in its place
        enter(o)
        replacement = _default(o)
        try:
            yield from encode_value(replacement, level)
        except GeneratorExit:
            raise
        except BaseException as exc:
            _note(exc, 'when serializing %s object' % type(o).__name__)
            raise
        leave(o)

    def encode_value(o, level):
        text = scalar(o)
        if text is not None:
            yield text
        else:
            yield from compound(o, level)

    return encode_value
