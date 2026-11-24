"""itertools -- functions creating iterators for efficient looping.

x-python's own, written to CPython 3.14's interface.  CPython's are
classes written in C; most here are generator functions, so what they
answer is a generator rather than an instance of a type named for the
function.  count, repeat and chain are classes, since programs print
the first two and call chain.from_iterable.  A function that checks its
arguments checks them at the call, as CPython's do, and answers the
generator after: a check inside a generator would wait for the first
next().

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = [
    'accumulate', 'batched', 'chain', 'combinations',
    'combinations_with_replacement', 'compress', 'count', 'cycle',
    'dropwhile', 'filterfalse', 'groupby', 'islice', 'pairwise',
    'permutations', 'product', 'repeat', 'starmap', 'takewhile', 'tee',
    'zip_longest',
]


# --- infinite iterators -----------------------------------------------------

class count:
    """count(start=0, step=1) --> start, start+step, start+2*step, ..."""

    def __init__(self, start=0, step=1):
        for v in (start, step):
            if not isinstance(v, (int, float, complex)):
                raise TypeError('a number is required')
        self._n = start
        self._step = step

    def __iter__(self):
        return self

    def __next__(self):
        n = self._n
        self._n = n + self._step
        return n

    def __repr__(self):
        if self._step == 1 and type(self._step) is int:
            return 'count(%r)' % (self._n,)
        return 'count(%r, %r)' % (self._n, self._step)


def cycle(iterable):
    """cycle(p) --> p0, p1, ... plast, p0, p1, ..."""
    saved = []
    for element in iterable:
        yield element
        saved.append(element)
    while saved:
        for element in saved:
            yield element


class repeat:
    """repeat(object [,times]) --> object for the specified number of
    times; without times, forever."""

    def __init__(self, object, times=None):
        self._object = object
        if times is not None and times < 0:
            times = 0
        self._times = times

    def __iter__(self):
        return self

    def __next__(self):
        if self._times is None:
            return self._object
        if self._times <= 0:
            raise StopIteration
        self._times -= 1
        return self._object

    def __length_hint__(self):
        if self._times is None:
            raise TypeError('len() of unsized object')
        return self._times

    def __repr__(self):
        if self._times is None:
            return 'repeat(%r)' % (self._object,)
        return 'repeat(%r, %r)' % (self._object, self._times)


# --- iterators terminating on the shortest input ----------------------------

def accumulate(iterable, func=None, initial=None):
    """accumulate(p[, func][, initial=None]) --> p0, p0+p1, p0+p1+p2, ..."""
    it = iter(iterable)
    total = initial
    if initial is None:
        try:
            total = next(it)
        except StopIteration:
            return
    yield total
    for element in it:
        total = total + element if func is None else func(total, element)
        yield total


def batched(iterable, n, strict=False):
    """batched(p, n) --> tuples of length n from p; the last may be shorter,
    unless strict, when that is a ValueError."""
    if n < 1:
        raise ValueError('n must be at least one')
    return _batched(iter(iterable), n, strict)


def _batched(it, n, strict):
    while True:
        batch = tuple(islice(it, n))
        if not batch:
            return
        if strict and len(batch) != n:
            raise ValueError('batched(): incomplete batch')
        yield batch


class chain:
    """chain(*iterables) --> elements of each iterable in turn."""

    def __init__(self, *iterables):
        self._sources = iter(iterables)
        self._active = None

    @classmethod
    def from_iterable(cls, iterable):
        """chain.from_iterable(iterable) --> one iterable's iterables, chained."""
        c = cls()
        c._sources = iter(iterable)
        return c

    def __iter__(self):
        return self

    def __next__(self):
        while True:
            if self._active is None:
                self._active = iter(next(self._sources))
            try:
                return next(self._active)
            except StopIteration:
                self._active = None


def compress(data, selectors):
    """compress(data, selectors) --> data where its selector is true."""
    for d, s in zip(data, selectors):
        if s:
            yield d


def dropwhile(predicate, iterable):
    """dropwhile(pred, seq) --> seq[n], seq[n+1], ... once pred fails."""
    it = iter(iterable)
    for x in it:
        if not predicate(x):
            yield x
            break
    for x in it:
        yield x


def filterfalse(predicate, iterable):
    """filterfalse(pred, seq) --> the elements for which pred is false."""
    if predicate is None:
        predicate = bool
    for x in iterable:
        if not predicate(x):
            yield x


class _Grouper:
    """One group of groupby's: the run of elements sharing its key."""

    def __init__(self, parent, key):
        self._parent = parent
        self._key = key

    def __iter__(self):
        return self

    def __next__(self):
        p = self._parent
        if p._group is not self or p._done:
            raise StopIteration
        if p._pending:
            p._pending = False
            return p._value
        try:
            value = next(p._it)
        except StopIteration:
            p._done = True
            raise
        key = value if p._keyfunc is None else p._keyfunc(value)
        if key == self._key:
            return value
        # the next group starts here: groupby will hand it out
        p._value, p._curkey, p._pending = value, key, True
        p._group = None
        raise StopIteration


class groupby:
    """groupby(iterable, key=None) --> (key, group) for each run of
    consecutive elements sharing a key."""

    def __init__(self, iterable, key=None):
        self._it = iter(iterable)
        self._keyfunc = key
        self._group = None
        self._pending = False
        self._done = False
        self._value = None
        self._curkey = None
        self._started = False

    def __iter__(self):
        return self

    def __next__(self):
        if self._done:
            raise StopIteration
        # drain what the current group left unread
        if self._group is not None:
            g = self._group
            for _ in g:
                pass
            if self._done:
                raise StopIteration
        if not self._pending:
            try:
                value = next(self._it)
            except StopIteration:
                self._done = True
                raise
            self._value = value
            self._curkey = value if self._keyfunc is None else self._keyfunc(value)
            self._pending = True
        g = _Grouper(self, self._curkey)
        self._group = g
        return (self._curkey, g)


def islice(iterable, *args):
    """islice(iterable, stop) or islice(iterable, start, stop[, step])."""
    s = slice(*args)
    start = 0 if s.start is None else s.start
    stop = s.stop
    step = 1 if s.step is None else s.step
    for v in (start, stop):
        if v is not None and (not isinstance(v, int) or v < 0):
            raise ValueError(
                ('Stop argument' if len(args) == 1 else 'Indices') +
                ' for islice() must be None or an integer: '
                '0 <= x <= sys.maxsize.')
    if not isinstance(step, int) or step < 1:
        raise ValueError('Step for islice() must be a positive integer or None.')
    return _islice(iterable, start, stop, step)


def _islice(iterable, start, stop, step):
    # Reads no further than stop: an element past it is never pulled.
    if stop is not None and stop <= 0:
        return
    i = 0
    nexti = start
    for element in iter(iterable):
        if i == nexti:
            yield element
            nexti += step
        i += 1
        if stop is not None and i >= stop:
            return


def pairwise(iterable):
    """pairwise(s) --> (s0, s1), (s1, s2), (s2, s3), ..."""
    it = iter(iterable)
    try:
        a = next(it)
    except StopIteration:
        return
    for b in it:
        yield (a, b)
        a = b


def starmap(function, iterable):
    """starmap(fun, seq) --> fun(*seq[0]), fun(*seq[1]), ..."""
    for args in iterable:
        yield function(*args)


def takewhile(predicate, iterable):
    """takewhile(pred, seq) --> seq[0], seq[1], ... until pred fails."""
    for x in iterable:
        if predicate(x):
            yield x
        else:
            return


def _tee_gen(it, buffers, mine):
    while True:
        if not mine:
            try:
                value = next(it)
            except StopIteration:
                return
            for b in buffers:
                b.append(value)
        yield mine.pop(0)


def tee(iterable, n=2):
    """tee(it, n=2) --> n independent iterators over one iterable."""
    if n < 0:
        raise ValueError('n must be >= 0')
    it = iter(iterable)
    buffers = [[] for _ in range(n)]
    return tuple(_tee_gen(it, buffers, b) for b in buffers)


def zip_longest(*iterables, fillvalue=None):
    """zip_longest(*iterables, fillvalue=None) --> tuples, padded with
    fillvalue until the longest is done."""
    iterators = [iter(it) for it in iterables]
    if not iterators:
        return
    active = len(iterators)
    while True:
        values = []
        for i in range(len(iterators)):
            it = iterators[i]
            if it is None:
                values.append(fillvalue)
                continue
            try:
                values.append(next(it))
            except StopIteration:
                active -= 1
                if not active:
                    return
                iterators[i] = None
                values.append(fillvalue)
        yield tuple(values)


# --- combinatoric iterators -------------------------------------------------

def product(*iterables, repeat=1):
    """product(*iterables, repeat=1) --> the cartesian product, as tuples."""
    if repeat < 0:
        raise ValueError('repeat argument cannot be negative')
    return _product([tuple(pool) for pool in iterables] * repeat)


def _product(pools):
    result = [()]
    for pool in pools:
        result = [x + (y,) for x in result for y in pool]
    for prod in result:
        yield prod


def permutations(iterable, r=None):
    """permutations(iterable, r=None) --> successive r-length permutations."""
    pool = tuple(iterable)
    n = len(pool)
    r = n if r is None else r
    if r < 0:
        raise ValueError('r must be non-negative')
    return _permutations(pool, n, r)


def _permutations(pool, n, r):
    if r > n:
        return
    indices = list(range(n))
    cycles = list(range(n, n - r, -1))
    yield tuple(pool[i] for i in indices[:r])
    while n:
        for i in reversed(range(r)):
            cycles[i] -= 1
            if cycles[i] == 0:
                indices[i:] = indices[i + 1:] + indices[i:i + 1]
                cycles[i] = n - i
            else:
                j = cycles[i]
                indices[i], indices[-j] = indices[-j], indices[i]
                yield tuple(pool[i] for i in indices[:r])
                break
        else:
            return


def combinations(iterable, r):
    """combinations(iterable, r) --> r-length subsequences, in order."""
    pool = tuple(iterable)
    n = len(pool)
    if r < 0:
        raise ValueError('r must be non-negative')
    return _combinations(pool, n, r)


def _combinations(pool, n, r):
    if r > n:
        return
    indices = list(range(r))
    yield tuple(pool[i] for i in indices)
    while True:
        for i in reversed(range(r)):
            if indices[i] != i + n - r:
                break
        else:
            return
        indices[i] += 1
        for j in range(i + 1, r):
            indices[j] = indices[j - 1] + 1
        yield tuple(pool[i] for i in indices)


def combinations_with_replacement(iterable, r):
    """combinations_with_replacement(iterable, r) --> r-length
    subsequences, elements allowed to repeat."""
    pool = tuple(iterable)
    n = len(pool)
    if r < 0:
        raise ValueError('r must be non-negative')
    return _combinations_with_replacement(pool, n, r)


def _combinations_with_replacement(pool, n, r):
    if not n and r:
        return
    indices = [0] * r
    yield tuple(pool[i] for i in indices)
    while True:
        for i in reversed(range(r)):
            if indices[i] != n - 1:
                break
        else:
            return
        indices[i:] = [indices[i] + 1] * (r - i)
        yield tuple(pool[i] for i in indices)
