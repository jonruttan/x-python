"""json -- reading and writing JSON.

x-python's own, written to CPython 3.14's interface: dumps and dump write
a value as JSON, loads and load read one, and JSONEncoder, JSONDecoder and
JSONDecodeError are the classes under them.

    >>> import json
    >>> json.dumps({"a": [1, 2.5, None]})
    '{"a": [1, 2.5, null]}'
    >>> json.loads('{"a": [1, 2.5, null]}')
    {'a': [1, 2.5, None]}

The json.tool command-line interface isn't here.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__version__ = '2.0.9'
__all__ = [
    'dump', 'dumps', 'load', 'loads',
    'JSONDecoder', 'JSONDecodeError', 'JSONEncoder',
]

from .decoder import JSONDecoder, JSONDecodeError
from .encoder import JSONEncoder

_default_encoder = JSONEncoder()
_default_decoder = JSONDecoder()


def _all_options(skipkeys, ensure_ascii, check_circular, allow_nan, indent,
                 separators, default, sort_keys, kw):
    given = dict(kw)
    given.update(skipkeys=skipkeys, ensure_ascii=ensure_ascii,
                 check_circular=check_circular, allow_nan=allow_nan,
                 indent=indent, separators=separators, default=default,
                 sort_keys=sort_keys)
    return given


def _make_encoder(cls, skipkeys, ensure_ascii, check_circular, allow_nan,
                  indent, separators, default, sort_keys, kw):
    if (cls is None and not skipkeys and ensure_ascii and check_circular
            and allow_nan and indent is None and separators is None
            and default is None and not sort_keys and not kw):
        return _default_encoder
    return (JSONEncoder if cls is None else cls)(
        **_all_options(skipkeys, ensure_ascii, check_circular, allow_nan,
                       indent, separators, default, sort_keys, kw))


def dump(obj, fp, *, skipkeys=False, ensure_ascii=True, check_circular=True,
         allow_nan=True, cls=None, indent=None, separators=None,
         default=None, sort_keys=False, **kw):
    """Write obj as JSON to fp, a file open for text, as dumps writes it."""
    encoder = _make_encoder(cls, skipkeys, ensure_ascii, check_circular,
                            allow_nan, indent, separators, default, sort_keys,
                            kw)
    for chunk in encoder.iterencode(obj):
        fp.write(chunk)


def dumps(obj, *, skipkeys=False, ensure_ascii=True, check_circular=True,
          allow_nan=True, cls=None, indent=None, separators=None,
          default=None, sort_keys=False, **kw):
    """obj written as JSON, as a str.

    The options are JSONEncoder's, which says what each does; cls is the
    encoder class to use, JSONEncoder when it is None, and it is given any
    other keywords too."""
    return _make_encoder(cls, skipkeys, ensure_ascii, check_circular,
                         allow_nan, indent, separators, default, sort_keys,
                         kw).encode(obj)


# the byte-order marks detect_encoding looks for
_BOM_UTF8 = b'\xef\xbb\xbf'
_BOMS_UTF16 = (b'\xfe\xff', b'\xff\xfe')
_BOMS_UTF32 = (b'\x00\x00\xfe\xff', b'\xff\xfe\x00\x00')


def detect_encoding(b):
    """The encoding the JSON bytes b are in: a byte-order mark says, and
    otherwise where the zero bytes fall in the first four, since the
    document starts with an ASCII character."""
    if b.startswith(_BOMS_UTF32):
        return 'utf-32'
    if b.startswith(_BOMS_UTF16):
        return 'utf-16'
    if b.startswith(_BOM_UTF8):
        return 'utf-8-sig'
    if len(b) >= 4:
        if not b[0]:
            # 00 00 -- -- is UTF-32 big-endian; 00 XX -- -- UTF-16's
            return 'utf-16-be' if b[1] else 'utf-32-be'
        if not b[1]:
            # XX 00 00 00 is UTF-32 little-endian; XX 00 00 XX or
            # XX 00 XX -- UTF-16's
            return 'utf-16-le' if b[2] or b[3] else 'utf-32-le'
    elif len(b) == 2:
        if not b[0]:
            return 'utf-16-be'
        if not b[1]:
            return 'utf-16-le'
    return 'utf-8'


def load(fp, *, cls=None, object_hook=None, parse_float=None,
         parse_int=None, parse_constant=None, object_pairs_hook=None, **kw):
    """The value the JSON document fp holds, read as loads reads it."""
    return loads(fp.read(), cls=cls, object_hook=object_hook,
                 parse_float=parse_float, parse_int=parse_int,
                 parse_constant=parse_constant,
                 object_pairs_hook=object_pairs_hook, **kw)


def loads(s, *, cls=None, object_hook=None, parse_float=None,
          parse_int=None, parse_constant=None, object_pairs_hook=None, **kw):
    """The value the JSON document s holds: a str, or bytes or a bytearray
    in UTF-8, UTF-16 or UTF-32.

    The hooks are JSONDecoder's, which says what each does; cls is the
    decoder class to use, JSONDecoder when it is None, and it is given any
    other keywords too."""
    if isinstance(s, str):
        if s.startswith('﻿'):
            raise JSONDecodeError(
                "Unexpected UTF-8 BOM (decode using utf-8-sig)", s, 0)
    else:
        if not isinstance(s, (bytes, bytearray)):
            raise TypeError('the JSON object must be str, bytes or bytearray, '
                            'not %s' % s.__class__.__name__)
        s = s.decode(detect_encoding(s), 'surrogatepass')

    hooks = (('object_hook', object_hook),
             ('object_pairs_hook', object_pairs_hook),
             ('parse_float', parse_float),
             ('parse_int', parse_int),
             ('parse_constant', parse_constant))
    if cls is None and not kw and all(h is None for _, h in hooks):
        return _default_decoder.decode(s)
    for name, hook in hooks:
        if hook is not None:
            kw[name] = hook
    return (JSONDecoder if cls is None else cls)(**kw).decode(s)
