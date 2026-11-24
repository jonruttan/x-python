"""functools -- tools for functions that act on or return functions.

x-python's own, written to CPython 3.14's interface: reduce, partial,
update_wrapper and wraps, cache and lru_cache, cmp_to_key, total_ordering
and cached_property.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = [
    'WRAPPER_ASSIGNMENTS', 'WRAPPER_UPDATES', 'cache', 'cached_property',
    'cmp_to_key', 'lru_cache', 'partial', 'reduce', 'total_ordering',
    'update_wrapper', 'wraps',
]


# --- reduce -----------------------------------------------------------------

_initial_missing = object()


def reduce(function, iterable, initial=_initial_missing):
    """reduce(function, iterable[, initial], /) -> value

    Apply a function of two arguments cumulatively to the items of an
    iterable, from left to right."""
    it = iter(iterable)
    if initial is _initial_missing:
        value = next(it, _initial_missing)
        if value is _initial_missing:
            raise TypeError("reduce() of empty iterable with no initial value")
    else:
        value = initial
    for element in it:
        value = function(value, element)
    return value


# --- partial ----------------------------------------------------------------

def _merged(first, second):
    # a new dict of first's items, then second's over them
    d = dict(first)
    d.update(second)
    return d


class partial:
    """New function with partial application of the given arguments
    and keywords."""

    def __init__(self, func, *args, **keywords):
        if not callable(func):
            raise TypeError("the first argument must be callable")
        if isinstance(func, partial):
            args = func.args + args
            keywords = _merged(func.keywords, keywords)
            func = func.func
        self.func = func
        self.args = args
        self.keywords = keywords

    def __call__(self, *args, **keywords):
        return self.func(*(self.args + args), **_merged(self.keywords, keywords))

    def __repr__(self):
        parts = [repr(self.func)]
        parts.extend(repr(x) for x in self.args)
        parts.extend("%s=%r" % (k, v) for k, v in self.keywords.items())
        return "functools.partial(" + ", ".join(parts) + ")"


# --- update_wrapper and wraps -----------------------------------------------

WRAPPER_ASSIGNMENTS = ('__module__', '__name__', '__qualname__', '__doc__',
                       '__annotate__', '__type_params__')
WRAPPER_UPDATES = ('__dict__',)


def update_wrapper(wrapper, wrapped, assigned=WRAPPER_ASSIGNMENTS,
                   updated=WRAPPER_UPDATES):
    """Make wrapper look like wrapped: copy the assigned attributes, update
    the updated ones, and set __wrapped__."""
    for attr in assigned:
        try:
            value = getattr(wrapped, attr)
        except AttributeError:
            pass
        else:
            try:
                setattr(wrapper, attr, value)
            except (AttributeError, TypeError):
                pass
    for attr in updated:
        try:
            getattr(wrapper, attr).update(getattr(wrapped, attr, {}))
        except (AttributeError, TypeError):
            pass
    wrapper.__wrapped__ = wrapped
    return wrapper


def wraps(wrapped, assigned=WRAPPER_ASSIGNMENTS, updated=WRAPPER_UPDATES):
    """A decorator that applies update_wrapper() with wrapped."""
    def decorating(wrapper):
        return update_wrapper(wrapper, wrapped, assigned, updated)
    return decorating


# --- cmp_to_key -------------------------------------------------------------

def cmp_to_key(mycmp):
    """Convert a cmp= function into a key= function."""
    class K:
        __slots__ = ['obj']

        def __init__(self, obj):
            self.obj = obj

        def __lt__(self, other):
            return mycmp(self.obj, other.obj) < 0

        def __gt__(self, other):
            return mycmp(self.obj, other.obj) > 0

        def __eq__(self, other):
            return mycmp(self.obj, other.obj) == 0

        def __le__(self, other):
            return mycmp(self.obj, other.obj) <= 0

        def __ge__(self, other):
            return mycmp(self.obj, other.obj) >= 0
    return K


# --- total_ordering ---------------------------------------------------------
#
# Each derived comparison is written from the one the class defines, and
# answers NotImplemented where that one did.

def _gt_from_lt(self, other):
    r = type(self).__lt__(self, other)
    if r is NotImplemented:
        return r
    return not r and self != other

def _le_from_lt(self, other):
    r = type(self).__lt__(self, other)
    if r is NotImplemented:
        return r
    return r or self == other

def _ge_from_lt(self, other):
    r = type(self).__lt__(self, other)
    if r is NotImplemented:
        return r
    return not r

def _ge_from_le(self, other):
    r = type(self).__le__(self, other)
    if r is NotImplemented:
        return r
    return not r or self == other

def _lt_from_le(self, other):
    r = type(self).__le__(self, other)
    if r is NotImplemented:
        return r
    return r and self != other

def _gt_from_le(self, other):
    r = type(self).__le__(self, other)
    if r is NotImplemented:
        return r
    return not r

def _lt_from_gt(self, other):
    r = type(self).__gt__(self, other)
    if r is NotImplemented:
        return r
    return not r and self != other

def _ge_from_gt(self, other):
    r = type(self).__gt__(self, other)
    if r is NotImplemented:
        return r
    return r or self == other

def _le_from_gt(self, other):
    r = type(self).__gt__(self, other)
    if r is NotImplemented:
        return r
    return not r

def _le_from_ge(self, other):
    r = type(self).__ge__(self, other)
    if r is NotImplemented:
        return r
    return not r or self == other

def _gt_from_ge(self, other):
    r = type(self).__ge__(self, other)
    if r is NotImplemented:
        return r
    return r and self != other

def _lt_from_ge(self, other):
    r = type(self).__ge__(self, other)
    if r is NotImplemented:
        return r
    return not r

_convert = {
    '__lt__': [('__gt__', _gt_from_lt), ('__le__', _le_from_lt),
               ('__ge__', _ge_from_lt)],
    '__le__': [('__ge__', _ge_from_le), ('__lt__', _lt_from_le),
               ('__gt__', _gt_from_le)],
    '__gt__': [('__lt__', _lt_from_gt), ('__ge__', _ge_from_gt),
               ('__le__', _le_from_gt)],
    '__ge__': [('__le__', _le_from_ge), ('__gt__', _gt_from_ge),
               ('__lt__', _lt_from_ge)],
}


def total_ordering(cls):
    """Class decorator that fills in missing ordering methods."""
    roots = [op for op in ('__lt__', '__le__', '__gt__', '__ge__')
             if getattr(cls, op, None) is not getattr(object, op, None)]
    if not roots:
        raise ValueError(
            'must define at least one ordering operation: < > <= >=')
    root = roots[0]
    for opname, opfunc in _convert[root]:
        if opname not in roots:
            opfunc.__name__ = opname
            setattr(cls, opname, opfunc)
    return cls


# --- cache and lru_cache ----------------------------------------------------

from collections import namedtuple as _namedtuple

_CacheInfo = _namedtuple("CacheInfo", ["hits", "misses", "maxsize", "currsize"])


_kwd_mark = object()


def _make_key(args, kwds, typed):
    key = args
    if kwds:
        key = key + (_kwd_mark,)
        for item in kwds.items():
            key = key + item
    if typed:
        key = key + tuple(type(v) for v in args)
        if kwds:
            key = key + tuple(type(v) for v in kwds.values())
    return key


class _lru_cache_wrapper:
    """A function wrapped in a cache: cache_info(), cache_clear() and
    __wrapped__ are what CPython's has."""

    def __init__(self, user_function, maxsize, typed):
        self.__wrapped__ = user_function
        self._maxsize = maxsize
        self._typed = typed
        self._cache = {}
        self._hits = 0
        self._misses = 0
        update_wrapper(self, user_function)

    def __call__(self, *args, **kwds):
        key = _make_key(args, kwds, self._typed)
        cache = self._cache
        if key in cache:
            self._hits += 1
            result = cache.pop(key)
            cache[key] = result      # most recently used goes last
            return result
        self._misses += 1
        result = self.__wrapped__(*args, **kwds)
        maxsize = self._maxsize
        if maxsize is None or maxsize > 0:
            cache[key] = result
            if maxsize is not None and len(cache) > maxsize:
                del cache[next(iter(cache))]
        return result

    def __get__(self, obj, objtype=None):
        if obj is None:
            return self
        return partial(self, obj)

    def cache_info(self):
        return _CacheInfo(self._hits, self._misses, self._maxsize,
                          len(self._cache))

    def cache_clear(self):
        self._cache.clear()
        self._hits = 0
        self._misses = 0

    def cache_parameters(self):
        return {'maxsize': self._maxsize, 'typed': self._typed}


def lru_cache(maxsize=128, typed=False):
    """Least-recently-used cache decorator: @lru_cache, @lru_cache() or
    @lru_cache(maxsize=N, typed=False)."""
    if isinstance(maxsize, int) and not isinstance(maxsize, bool):
        if maxsize < 0:
            maxsize = 0
    elif callable(maxsize) and isinstance(typed, bool):
        user_function, maxsize = maxsize, 128
        return _lru_cache_wrapper(user_function, maxsize, typed)
    elif maxsize is not None:
        raise TypeError(
            'Expected first argument to be an integer, a callable, or None')

    def decorating_function(user_function):
        return _lru_cache_wrapper(user_function, maxsize, typed)
    return decorating_function


def cache(user_function):
    """Simple lightweight unbounded cache.  Sometimes called "memoize"."""
    return lru_cache(maxsize=None)(user_function)


# --- cached_property --------------------------------------------------------

class cached_property:
    """A property computed once per instance, then kept in its __dict__."""

    def __init__(self, func):
        self.func = func
        self.attrname = None
        self.__doc__ = func.__doc__

    def __set_name__(self, owner, name):
        if self.attrname is None:
            self.attrname = name
        elif name != self.attrname:
            raise TypeError(
                "Cannot assign the same cached_property to two different "
                "names (%r and %r)." % (self.attrname, name))

    def __get__(self, instance, owner=None):
        if instance is None:
            return self
        name = self.attrname if self.attrname is not None else self.func.__name__
        cache = instance.__dict__
        if name in cache:
            return cache[name]
        val = self.func(instance)
        cache[name] = val
        return val
