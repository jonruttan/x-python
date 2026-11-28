"""bisect -- find, by halving, where an item belongs in a sorted sequence.

x-python's own, written to CPython 3.14's interface: bisect_left,
bisect_right and insort_left, insort_right, with bisect and insort as
the right-hand pair's other names.  Items are only ever compared with <,
and lo, hi and key are taken as CPython's C module takes them: lo must
be a non-negative index, hi is an index or None, and a hi of -1 means
the whole sequence, as None does.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

from operator import index as _index

__all__ = ['bisect', 'bisect_left', 'bisect_right',
           'insort', 'insort_left', 'insort_right']


def _bounds(lo, hi):
    # lo and hi as ints, the way the C module's argument parsing makes them
    lo = _index(lo)
    if hi is None:
        return lo, -1
    if isinstance(hi, int):
        return lo, int(hi)
    if getattr(type(hi), '__index__', None) is not None:
        return lo, _index(hi)
    raise TypeError("argument should be integer or None, not '%s'"
                    % type(hi).__name__)


_SEQUENCES = (list, tuple, str, bytes, bytearray, range, memoryview)


def _span(a, lo, hi):
    # check lo, close an open hi at len(a), and make sure a can be indexed
    # -- in that order, even when there is nothing to search
    if lo < 0:
        raise ValueError('lo must be non-negative')
    if hi == -1:
        hi = len(a)
    # a dict is a mapping and no sequence, though a class built on one is
    # indexed through its __getitem__
    if type(a) is dict:
        raise TypeError('dict is not a sequence')
    if not isinstance(a, _SEQUENCES) and \
            getattr(type(a), '__getitem__', None) is None:
        raise TypeError("'%s' object does not support indexing"
                        % ('NoneType' if a is None else type(a).__name__))
    return lo, hi


def _left(a, x, lo, hi, key):
    # the first place x can go and every item before it is < x
    while lo < hi:
        mid = (lo + hi) // 2
        here = a[mid] if key is None else key(a[mid])
        if here < x:
            lo = mid + 1
        else:
            hi = mid
    return lo


def _right(a, x, lo, hi, key):
    # the last place x can go: past every item that x is not < than
    while lo < hi:
        mid = (lo + hi) // 2
        here = a[mid] if key is None else key(a[mid])
        if x < here:
            hi = mid
        else:
            lo = mid + 1
    return lo


def bisect_left(a, x, lo=0, hi=None, *, key=None):
    """Where x would go in the sorted a[lo:hi], before any equal items.

    Every item of a[lo:i] is < x, and none of a[i:hi] is.  key, when
    given, is applied to the items of a, not to x.
    """
    lo, hi = _span(a, *_bounds(lo, hi))
    return _left(a, x, lo, hi, key)


def bisect_right(a, x, lo=0, hi=None, *, key=None):
    """Where x would go in the sorted a[lo:hi], after any equal items.

    No item of a[lo:i] is > x, and every one of a[i:hi] is.  key, when
    given, is applied to the items of a, not to x.
    """
    lo, hi = _span(a, *_bounds(lo, hi))
    return _right(a, x, lo, hi, key)


def insort_left(a, x, lo=0, hi=None, *, key=None):
    """Insert x into the sorted a, before any items equal to it.

    key, when given, is applied to x as well as to the items of a.
    """
    lo, hi = _bounds(lo, hi)
    rank = x if key is None else key(x)
    lo, hi = _span(a, lo, hi)
    at = _left(a, rank, lo, hi, key)
    a.insert(at, x)


def insort_right(a, x, lo=0, hi=None, *, key=None):
    """Insert x into the sorted a, after any items equal to it.

    key, when given, is applied to x as well as to the items of a.
    """
    lo, hi = _bounds(lo, hi)
    rank = x if key is None else key(x)
    lo, hi = _span(a, lo, hi)
    at = _right(a, rank, lo, hi, key)
    a.insert(at, x)


bisect = bisect_right
insort = insort_right
