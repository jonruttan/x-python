"""string -- common string constants, capwords, Template and Formatter.

x-python's own, written to CPython 3.14's interface.  CPython's Template
matches placeholders with a regular expression a subclass can replace;
this one reads them by hand, so a subclass can change the delimiter but
not idpattern, braceidpattern or pattern.  string.templatelib, the
t-string types, is not here.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = [
    'ascii_letters', 'ascii_lowercase', 'ascii_uppercase', 'capwords',
    'digits', 'hexdigits', 'octdigits', 'printable', 'punctuation',
    'whitespace', 'Formatter', 'Template',
]

whitespace = ' \t\n\r\v\f'
ascii_lowercase = 'abcdefghijklmnopqrstuvwxyz'
ascii_uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
ascii_letters = ascii_lowercase + ascii_uppercase
digits = '0123456789'
hexdigits = digits + 'abcdef' + 'ABCDEF'
octdigits = '01234567'
punctuation = r"""!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"""
printable = digits + ascii_letters + punctuation + whitespace


def capwords(s, sep=None):
    """capwords(s [,sep]) -> string

    Split s into words with str.split, capitalize each, and join them with
    sep, or with a single space when sep is None."""
    return (sep or ' ').join(map(str.capitalize, s.split(sep)))


# --- Template ---------------------------------------------------------------

_ident_start = '_' + ascii_letters
_ident_rest = _ident_start + digits


class Template:
    """A string class for supporting $-substitutions."""

    delimiter = '$'

    def __init__(self, template):
        self.template = template

    # Each placeholder as (kind, start, end, name): kind is 'escaped' for a
    # doubled delimiter, 'named' for $name or ${name}, and 'invalid' for a
    # delimiter followed by neither.
    def _scan(self):
        t = self.template
        d = self.delimiter
        n = len(t)
        dl = len(d)
        i = 0
        while True:
            i = t.find(d, i)
            if i < 0:
                return
            j = i + dl
            if t.startswith(d, j):
                yield ('escaped', i, j + dl, None)
                i = j + dl
            elif j < n and t[j] == '{':
                k = j + 1
                if k < n and t[k] in _ident_start:
                    m = k + 1
                    while m < n and t[m] in _ident_rest:
                        m += 1
                    if m < n and t[m] == '}':
                        yield ('named', i, m + 1, t[k:m])
                        i = m + 1
                        continue
                yield ('invalid', i, j, None)
                i = j
            elif j < n and t[j] in _ident_start:
                m = j + 1
                while m < n and t[m] in _ident_rest:
                    m += 1
                yield ('named', i, m, t[j:m])
                i = m
            else:
                yield ('invalid', i, j, None)
                i = j

    def _invalid(self, i):
        lines = self.template[:i].splitlines(keepends=True)
        if not lines:
            colno = 1
            lineno = 1
        else:
            colno = i - len(''.join(lines[:-1]))
            lineno = len(lines)
        raise ValueError('Invalid placeholder in string: line %d, col %d' %
                         (lineno, colno))

    def _expand(self, mapping, safe):
        t = self.template
        out = []
        last = 0
        for kind, start, end, name in self._scan():
            out.append(t[last:start])
            last = end
            if kind == 'escaped':
                out.append(self.delimiter)
            elif kind == 'named':
                if safe:
                    try:
                        out.append(str(mapping[name]))
                    except KeyError:
                        out.append(t[start:end])
                else:
                    out.append(str(mapping[name]))
            elif safe:
                out.append(t[start:end])
            else:
                self._invalid(start + len(self.delimiter))
        out.append(t[last:])
        return ''.join(out)

    def substitute(self, mapping=None, **kws):
        """The template with each placeholder replaced from mapping and
        kws; a missing name is a KeyError."""
        return self._expand(_chain_map(mapping, kws), False)

    def safe_substitute(self, mapping=None, **kws):
        """As substitute, but a missing name or a stray delimiter is left
        as it was."""
        return self._expand(_chain_map(mapping, kws), True)

    def is_valid(self):
        """True when the template has no invalid placeholder."""
        for kind, start, end, name in self._scan():
            if kind == 'invalid':
                return False
        return True

    def get_identifiers(self):
        """The names of the template's placeholders, each once, in order."""
        ids = []
        for kind, start, end, name in self._scan():
            if kind == 'named' and name not in ids:
                ids.append(name)
        return ids


class _ChainMap:
    # kws first, then the mapping: what substitute's two sources mean
    def __init__(self, first, second):
        self._first = first
        self._second = second

    def __getitem__(self, key):
        if key in self._first:
            return self._first[key]
        return self._second[key]


def _chain_map(mapping, kws):
    if mapping is None:
        return kws
    if not kws:
        return mapping
    return _ChainMap(kws, mapping)


# --- Formatter --------------------------------------------------------------

def _parse(s):
    # What CPython's _string.formatter_parser yields:
    # (literal, field_name, format_spec, conversion), with None for the last
    # three after a literal no field follows.  It reads as CPython's does,
    # so it fails where CPython's fails and says what CPython's says.
    n = len(s)
    i = 0
    while i < n:
        start = i
        while i < n and s[i] != '{' and s[i] != '}':
            i += 1
        if i >= n:
            yield (s[start:i], None, None, None)
            return
        c = s[i]
        if i + 1 < n and s[i + 1] == c:
            # a doubled brace is one of it, in the literal
            yield (s[start:i + 1], None, None, None)
            i += 2
            continue
        if c == '}':
            raise ValueError("Single '}' encountered in format string")
        if i + 1 >= n:
            raise ValueError("Single '{' encountered in format string")
        literal = s[start:i]
        i += 1
        name_start = i
        c = None
        while i < n:
            c = s[i]
            i += 1
            if c == '{':
                raise ValueError("unexpected '{' in field name")
            if c == '[':
                while i < n and s[i] != ']':
                    i += 1
                continue
            if c == '}' or c == ':' or c == '!':
                break
        else:
            c = None
        if c is None:
            raise ValueError("expected '}' before end of string")
        name = s[name_start:i - 1]
        if c == '}':
            yield (literal, name, '', None)
            continue
        conversion = None
        if c == '!':
            if i >= n:
                raise ValueError("end of string while looking for conversion "
                                 "specifier")
            conversion = s[i]
            i += 1
            if i < n:
                c = s[i]
                i += 1
                if c == '}':
                    yield (literal, name, '', conversion)
                    continue
                if c != ':':
                    raise ValueError("expected ':' after conversion specifier")
        spec_start = i
        count = 1
        while i < n:
            c = s[i]
            i += 1
            if c == '{':
                count += 1
            elif c == '}':
                count -= 1
                if count == 0:
                    break
        if count:
            raise ValueError("unmatched '{' in format spec")
        yield (literal, name, s[spec_start:i - 1], conversion)


def _field_name_split(name):
    # CPython's _string.formatter_field_name_split: the first part, an int
    # when it is all digits, and an iterator of (is_attr, key) that reads
    # the rest only as it is asked, as CPython's does.
    i = 0
    n = len(name)
    while i < n and name[i] != '.' and name[i] != '[':
        i += 1
    first = name[:i]
    if first.isdigit():
        first = int(first)
    return first, _field_rest(name, i)


def _field_rest(name, i):
    n = len(name)
    while i < n:
        c = name[i]
        i += 1
        j = i
        if c == '.':
            while i < n and name[i] != '.' and name[i] != '[':
                i += 1
            key = name[j:i]
            if not key:
                raise ValueError("Empty attribute in format string")
            yield (True, key)
        elif c == '[':
            while i < n and name[i] != ']':
                i += 1
            if i >= n:
                raise ValueError("Missing ']' in format string")
            key = name[j:i]
            i += 1
            if not key:
                raise ValueError("Empty attribute in format string")
            yield (False, int(key) if key.isdigit() else key)
        else:
            raise ValueError("Only '.' or '[' may follow ']' in format field "
                             "specifier")


class Formatter:
    """str.format's engine, in pieces a subclass can replace."""

    def format(self, format_string, *args, **kwargs):
        return self.vformat(format_string, args, kwargs)

    def vformat(self, format_string, args, kwargs):
        used_args = set()
        result, _ = self._vformat(format_string, args, kwargs, used_args, 2)
        self.check_unused_args(used_args, args, kwargs)
        return result

    def _vformat(self, format_string, args, kwargs, used_args,
                 recursion_depth, auto_arg_index=0):
        if recursion_depth < 0:
            raise ValueError('Max string recursion exceeded')
        result = []
        for literal_text, field_name, format_spec, conversion in \
                self.parse(format_string):
            if literal_text:
                result.append(literal_text)
            if field_name is not None:
                if field_name == '':
                    if auto_arg_index is False:
                        raise ValueError('cannot switch from manual field '
                                         'specification to automatic field '
                                         'numbering')
                    field_name = str(auto_arg_index)
                    auto_arg_index += 1
                elif field_name.isdigit():
                    if auto_arg_index:
                        raise ValueError('cannot switch from automatic field '
                                         'numbering to manual field '
                                         'specification')
                    auto_arg_index = False
                obj, arg_used = self.get_field(field_name, args, kwargs)
                used_args.add(arg_used)
                obj = self.convert_field(obj, conversion)
                format_spec, auto_arg_index = self._vformat(
                    format_spec, args, kwargs, used_args,
                    recursion_depth - 1, auto_arg_index=auto_arg_index)
                result.append(self.format_field(obj, format_spec))
        return ''.join(result), auto_arg_index

    def get_value(self, key, args, kwargs):
        if isinstance(key, int):
            return args[key]
        return kwargs[key]

    def check_unused_args(self, used_args, args, kwargs):
        pass

    def format_field(self, value, format_spec):
        return format(value, format_spec)

    def convert_field(self, value, conversion):
        if conversion is None:
            return value
        if conversion == 's':
            return str(value)
        if conversion == 'r':
            return repr(value)
        if conversion == 'a':
            return ascii(value)
        raise ValueError("Unknown conversion specifier {0!s}".format(conversion))

    def parse(self, format_string):
        """(literal_text, field_name, format_spec, conversion) for each
        piece of format_string."""
        return _parse(format_string)

    def get_field(self, field_name, args, kwargs):
        first, rest = _field_name_split(field_name)
        obj = self.get_value(first, args, kwargs)
        for is_attr, i in rest:
            if is_attr:
                obj = getattr(obj, i)
            else:
                obj = obj[i]
        return obj, first
