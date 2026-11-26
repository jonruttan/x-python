"""json.scanner -- reading one JSON value.

x-python's own, written to CPython 3.14's interface: make_scanner(decoder)
answers the scan_once(string, idx) a JSONDecoder reads each value with.
It answers (value, end), or raises StopIteration(idx) where no value
starts.  Numbers are matched by hand, where CPython uses a regular
expression.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = ['make_scanner']

_DIGITS = '0123456789'


def _past_digits(string, i):
    n = len(string)
    while i < n and string[i] in _DIGITS:
        i += 1
    return i


def match_number(string, idx):
    """The JSON number at idx as (integer, frac, exp, end), or None.

    integer is the sign and the whole part, which has no leading zeros;
    frac is a '.' and its digits, and exp an 'e' or 'E', a sign maybe, and
    its digits.  A '.' or an 'e' without digits after it isn't part of the
    number, and frac or exp is None where there is none."""
    n = len(string)
    i = idx + 1 if string[idx:idx + 1] == '-' else idx
    lead = string[i:i + 1]
    if lead == '0':
        i += 1
    elif lead and lead in '123456789':
        i = _past_digits(string, i + 1)
    else:
        return None
    integer = string[idx:i]
    frac = exp = None
    if string[i:i + 1] == '.' and string[i + 1:i + 2] and string[i + 1] in _DIGITS:
        j = _past_digits(string, i + 1)
        frac, i = string[i:j], j
    if string[i:i + 1] and string[i] in 'eE':
        j = i + 2 if string[i + 1:i + 2] and string[i + 1] in '+-' else i + 1
        if string[j:j + 1] and string[j] in _DIGITS:
            k = _past_digits(string, j)
            exp, i = string[i:k], k
    return integer, frac, exp, i


# the words a JSON document may spell a value with, and the values
_WORDS = (('null', None), ('true', True), ('false', False))
# the ones outside the standard, which the decoder's parse_constant reads;
# a number is tried first, so '-' is a number's sign unless no digit follows
_CONSTANT_WORDS = ('NaN', 'Infinity', '-Infinity')


def py_make_scanner(context):
    """scan_once for the decoder context, its hooks read now."""
    parse_object = context.parse_object
    parse_array = context.parse_array
    parse_string = context.parse_string
    strict = context.strict
    parse_float = context.parse_float
    parse_int = context.parse_int
    parse_constant = context.parse_constant
    object_hook = context.object_hook
    object_pairs_hook = context.object_pairs_hook
    memo = context.memo

    def value_at(string, idx):
        try:
            c = string[idx]
        except IndexError:
            raise StopIteration(idx) from None
        if c == '"':
            return parse_string(string, idx + 1, strict)
        if c == '{':
            return parse_object((string, idx + 1), strict, value_at,
                                object_hook, object_pairs_hook, memo)
        if c == '[':
            return parse_array((string, idx + 1), value_at)
        for word, value in _WORDS:
            if string.startswith(word, idx):
                return value, idx + len(word)
        number = match_number(string, idx)
        if number is not None:
            integer, frac, exp, end = number
            if frac or exp:
                return parse_float(integer + (frac or '') + (exp or '')), end
            return parse_int(integer), end
        for word in _CONSTANT_WORDS:
            if string.startswith(word, idx):
                return parse_constant(word), idx + len(word)
        raise StopIteration(idx)

    def scan_once(string, idx):
        # the memo shares equal keys within one document, not across them
        try:
            return value_at(string, idx)
        finally:
            memo.clear()

    return scan_once


make_scanner = py_make_scanner
