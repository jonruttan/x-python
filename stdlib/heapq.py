"""heapq -- a binary heap kept in a plain list.

x-python's own, written to CPython 3.14's interface.  A min-heap is a
list where every heap[k] <= heap[2*k+1] and heap[k] <= heap[2*k+2], so
heap[0] is the smallest item; the *_max functions keep the mirror image,
with heap[0] the largest.  Items are only ever compared with <.

The sifting below moves items the same way CPython's does, so a heap
built here has the same layout as one built there.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = ['heappush', 'heappop', 'heapify', 'heapreplace', 'heappushpop',
           'heappush_max', 'heappop_max', 'heapify_max', 'heapreplace_max',
           'heappushpop_max', 'nlargest', 'nsmallest', 'merge']


def _kind(x):
    return 'None' if x is None else type(x).__name__


def _need_list(name, heap, numbered=True):
    if not isinstance(heap, list):
        where = 'argument 1' if numbered else 'argument'
        raise TypeError('%s() %s must be list, not %s'
                        % (name, where, _kind(heap)))


# -- the min-heap's two moves ----------------------------------------------

def _rise(heap, top, pos):
    # carry heap[pos] up towards top while it is smaller than its parent
    item = heap[pos]
    while pos > top:
        up = (pos - 1) >> 1
        parent = heap[up]
        if not item < parent:
            break
        heap[pos] = parent
        pos = up
    heap[pos] = item


def _sink(heap, pos):
    # walk the smaller child up into the hole at pos until a leaf is
    # reached, then let the displaced item rise back into place
    size = len(heap)
    top = pos
    item = heap[pos]
    kid = 2 * pos + 1
    while kid < size:
        other = kid + 1
        if other < size and not heap[kid] < heap[other]:
            kid = other
        heap[pos] = heap[kid]
        pos = kid
        kid = 2 * pos + 1
    heap[pos] = item
    _rise(heap, top, pos)


# -- the max-heap's, with each comparison turned round ---------------------

def _rise_max(heap, top, pos):
    item = heap[pos]
    while pos > top:
        up = (pos - 1) >> 1
        parent = heap[up]
        if not parent < item:
            break
        heap[pos] = parent
        pos = up
    heap[pos] = item


def _sink_max(heap, pos):
    size = len(heap)
    top = pos
    item = heap[pos]
    kid = 2 * pos + 1
    while kid < size:
        other = kid + 1
        if other < size and not heap[other] < heap[kid]:
            kid = other
        heap[pos] = heap[kid]
        pos = kid
        kid = 2 * pos + 1
    heap[pos] = item
    _rise_max(heap, top, pos)


# -- the public functions --------------------------------------------------

def heappush(heap, item):
    """Add item to the heap, keeping it a heap."""
    _need_list('heappush', heap)
    heap.append(item)
    _rise(heap, 0, len(heap) - 1)


def heappop(heap):
    """Remove and return the smallest item of the heap."""
    _need_list('heappop', heap, False)
    if not heap:
        raise IndexError('index out of range')
    last = heap.pop()
    if not heap:
        return last
    smallest = heap[0]
    heap[0] = last
    _sink(heap, 0)
    return smallest


def heapreplace(heap, item):
    """Pop the smallest item, then push item; the heap must not be empty.

    The item returned may be larger than the one pushed.
    """
    _need_list('heapreplace', heap)
    if not heap:
        raise IndexError('index out of range')
    smallest = heap[0]
    heap[0] = item
    _sink(heap, 0)
    return smallest


def heappushpop(heap, item):
    """Push item, then pop and return the smallest item, in one step."""
    _need_list('heappushpop', heap)
    if heap and heap[0] < item:
        item, heap[0] = heap[0], item
        _sink(heap, 0)
    return item


def heapify(x):
    """Rearrange the list x into a heap, in place, in linear time."""
    _need_list('heapify', x, False)
    for i in reversed(range(len(x) // 2)):
        _sink(x, i)


def heappush_max(heap, item):
    """Add item to the max-heap, keeping it a max-heap."""
    _need_list('heappush_max', heap)
    heap.append(item)
    _rise_max(heap, 0, len(heap) - 1)


def heappop_max(heap):
    """Remove and return the largest item of the max-heap."""
    _need_list('heappop_max', heap, False)
    if not heap:
        raise IndexError('index out of range')
    last = heap.pop()
    if not heap:
        return last
    largest = heap[0]
    heap[0] = last
    _sink_max(heap, 0)
    return largest


def heapreplace_max(heap, item):
    """Pop the largest item of the max-heap, then push item."""
    _need_list('heapreplace_max', heap)
    if not heap:
        raise IndexError('index out of range')
    largest = heap[0]
    heap[0] = item
    _sink_max(heap, 0)
    return largest


def heappushpop_max(heap, item):
    """Push item on the max-heap, then pop and return the largest item."""
    _need_list('heappushpop_max', heap)
    if heap and item < heap[0]:
        item, heap[0] = heap[0], item
        _sink_max(heap, 0)
    return item


def heapify_max(x):
    """Rearrange the list x into a max-heap, in place."""
    _need_list('heapify_max', x, False)
    for i in reversed(range(len(x) // 2)):
        _sink_max(x, i)


# -- merging sorted inputs -------------------------------------------------

def merge(*iterables, key=None, reverse=False):
    """Merge already-sorted iterables into one sorted stream, lazily.

    Like sorted(itertools.chain(*iterables)), but it never holds more than
    one item from each input.  key orders the items as sorted's key does;
    reverse=True expects each input sorted largest first.  Among equal
    items, those from an earlier input come first.
    """
    # each live input is an entry [sort key, tie-break, item, next]; the
    # tie-break is the input's position, negated for the max-heap so that
    # an earlier input still wins a tie
    if reverse:
        build, pop_, swap = heapify_max, heappop_max, heapreplace_max
        sign = -1
    else:
        build, pop_, swap = heapify, heappop, heapreplace
        sign = 1
    entries = []
    for place, source in enumerate(iterables):
        step = iter(source).__next__
        try:
            item = step()
        except StopIteration:
            continue
        rank = item if key is None else key(item)
        entries.append([rank, place * sign, item, step])
    build(entries)
    while len(entries) > 1:
        try:
            while True:
                entry = entries[0]
                yield entry[2]
                item = entry[3]()
                entry[0] = item if key is None else key(item)
                entry[2] = item
                swap(entries, entry)
        except StopIteration:
            pop_(entries)
    if entries:
        rank, place, item, step = entries[0]
        yield item
        while True:
            try:
                item = step()
            except StopIteration:
                return
            yield item


# -- the n smallest and largest --------------------------------------------

_MISSING = object()


def nsmallest(n, iterable, key=None):
    """Return the n smallest items of iterable, smallest first.

    The same list as sorted(iterable, key=key)[:n].
    """
    if n == 1:
        found = min(iter(iterable), default=_MISSING, key=key)
        return [] if found is _MISSING else [found]
    try:
        size = len(iterable)
    except (TypeError, AttributeError):
        pass
    else:
        if n >= size:
            return sorted(iterable, key=key)[:n]
    # keep the n smallest seen so far in a max-heap of decorated entries;
    # the running count breaks ties in favour of the item seen first
    source = iter(iterable)
    if key is None:
        best = [(item, i) for i, item in zip(range(n), source)]
    else:
        best = [(key(item), i, item) for i, item in zip(range(n), source)]
    if not best:
        return best
    heapify_max(best)
    count = n
    for item in source:
        rank = item if key is None else key(item)
        if rank < best[0][0]:
            heapreplace_max(best, (item, count) if key is None
                            else (rank, count, item))
            count += 1
    best.sort()
    return [entry[-1] if key is not None else entry[0] for entry in best]


def nlargest(n, iterable, key=None):
    """Return the n largest items of iterable, largest first.

    The same list as sorted(iterable, key=key, reverse=True)[:n].
    """
    if n == 1:
        found = max(iter(iterable), default=_MISSING, key=key)
        return [] if found is _MISSING else [found]
    try:
        size = len(iterable)
    except (TypeError, AttributeError):
        pass
    else:
        if n >= size:
            return sorted(iterable, key=key, reverse=True)[:n]
    # a min-heap of the n largest so far; counting down keeps the item
    # seen first ahead of a later equal one once the list is reversed
    source = iter(iterable)
    if key is None:
        best = [(item, i) for i, item in zip(range(0, -n, -1), source)]
    else:
        best = [(key(item), i, item)
                for i, item in zip(range(0, -n, -1), source)]
    if not best:
        return best
    heapify(best)
    count = -n
    for item in source:
        rank = item if key is None else key(item)
        if best[0][0] < rank:
            heapreplace(best, (item, count) if key is None
                        else (rank, count, item))
            count -= 1
    best.sort(reverse=True)
    return [entry[-1] if key is not None else entry[0] for entry in best]
