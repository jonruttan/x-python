"""operator -- Python's operators as functions.

x-python's own, written to CPython 3.14's interface.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = [
    'abs', 'add', 'and_', 'attrgetter', 'call', 'concat', 'contains',
    'countOf', 'delitem', 'eq', 'floordiv', 'ge', 'getitem', 'gt', 'iadd',
    'iand', 'iconcat', 'ifloordiv', 'ilshift', 'imatmul', 'imod', 'imul',
    'index', 'indexOf', 'inv', 'invert', 'ior', 'ipow', 'irshift', 'is_',
    'is_not', 'is_none', 'is_not_none', 'isub', 'itemgetter', 'itruediv',
    'ixor', 'le', 'length_hint', 'lshift', 'lt', 'matmul', 'methodcaller',
    'mod', 'mul', 'ne', 'neg', 'not_', 'or_', 'pos', 'pow', 'rshift',
    'setitem', 'sub', 'truediv', 'truth', 'xor',
]


_abs = abs


# Comparisons

def lt(a, b):
    return a < b

def le(a, b):
    return a <= b

def eq(a, b):
    return a == b

def ne(a, b):
    return a != b

def ge(a, b):
    return a >= b

def gt(a, b):
    return a > b


# Logic and identity

def not_(a):
    return not a

def truth(a):
    return True if a else False

def is_(a, b):
    return a is b

def is_not(a, b):
    return a is not b

def is_none(a):
    return a is None

def is_not_none(a):
    return a is not None


# Arithmetic and bits

def abs(a):
    return _abs(a)

def add(a, b):
    return a + b

def and_(a, b):
    return a & b

def floordiv(a, b):
    return a // b

def index(a):
    # int answers itself: this runtime's int carries no __index__ method.
    if isinstance(a, int):
        return int(a)
    method = getattr(type(a), '__index__', None)
    if method is None:
        raise TypeError("'%s' object cannot be interpreted as an integer"
                        % type(a).__name__)
    return method(a)

def inv(a):
    return ~a

def invert(a):
    return ~a

def lshift(a, b):
    return a << b

def mod(a, b):
    return a % b

def mul(a, b):
    return a * b

def matmul(a, b):
    return a @ b

def neg(a):
    return -a

def or_(a, b):
    return a | b

def pos(a):
    return +a

def pow(a, b):
    return a ** b

def rshift(a, b):
    return a >> b

def sub(a, b):
    return a - b

def truediv(a, b):
    return a / b

def xor(a, b):
    return a ^ b


# Sequences

def concat(a, b):
    if not hasattr(a, '__getitem__'):
        raise TypeError("'%s' object can't be concatenated" % type(a).__name__)
    return a + b

def contains(a, b):
    return b in a

def countOf(a, b):
    count = 0
    for i in a:
        if i is b or i == b:
            count += 1
    return count

def delitem(a, b):
    del a[b]

def getitem(a, b):
    return a[b]

def indexOf(a, b):
    for i, j in enumerate(a):
        if j is b or j == b:
            return i
    raise ValueError('sequence.index(x): x not in sequence')

def setitem(a, b, c):
    a[b] = c

def length_hint(obj, default=0):
    try:
        return len(obj)
    except TypeError:
        pass
    try:
        hint = type(obj).__length_hint__
    except AttributeError:
        return default
    val = hint(obj)
    if val is NotImplemented:
        return default
    return val


# Calls and lookups

# CPython makes obj and name positional-only (`/`); this runtime's parser
# does not take that marker yet, so a keyword argument named obj or name is
# the one call that differs.
def call(obj, *args, **kwargs):
    return obj(*args, **kwargs)


class attrgetter:
    """attrgetter(attr, ...) --> a callable that fetches the given
    attribute(s) from its operand; dotted names walk."""

    def __init__(self, attr, *attrs):
        names = (attr,) + attrs
        for name in names:
            if not isinstance(name, str):
                raise TypeError('attribute name must be a string')
        self._attrs = names
        self._paths = [name.split('.') for name in names]

    def _get(self, obj, path):
        for name in path:
            obj = getattr(obj, name)
        return obj

    def __call__(self, obj):
        if len(self._paths) == 1:
            return self._get(obj, self._paths[0])
        return tuple(self._get(obj, p) for p in self._paths)

    def __repr__(self):
        return 'operator.attrgetter(%s)' % ', '.join(repr(a) for a in self._attrs)


class itemgetter:
    """itemgetter(item, ...) --> a callable that fetches the given
    item(s) from its operand."""

    def __init__(self, item, *items):
        self._items = (item,) + items

    def __call__(self, obj):
        if len(self._items) == 1:
            return obj[self._items[0]]
        return tuple(obj[i] for i in self._items)

    def __repr__(self):
        return 'operator.itemgetter(%s)' % ', '.join(repr(i) for i in self._items)


class methodcaller:
    """methodcaller(name, /, *args, **kwargs) --> a callable that calls
    the named method on its operand."""

    def __init__(self, name, *args, **kwargs):
        if not isinstance(name, str):
            raise TypeError('method name must be a string')
        self._name = name
        self._args = args
        self._kwargs = kwargs

    def __call__(self, obj):
        return getattr(obj, self._name)(*self._args, **self._kwargs)

    def __repr__(self):
        args = [repr(self._name)]
        args.extend(repr(a) for a in self._args)
        args.extend('%s=%r' % (k, v) for k, v in self._kwargs.items())
        return 'operator.methodcaller(%s)' % ', '.join(args)


# In-place operations: the augmented assignment's protocol, answered.

def iadd(a, b):
    a += b
    return a

def iand(a, b):
    a &= b
    return a

def iconcat(a, b):
    if not hasattr(a, '__getitem__'):
        raise TypeError("'%s' object can't be concatenated" % type(a).__name__)
    a += b
    return a

def ifloordiv(a, b):
    a //= b
    return a

def ilshift(a, b):
    a <<= b
    return a

def imod(a, b):
    a %= b
    return a

def imul(a, b):
    a *= b
    return a

def imatmul(a, b):
    a @= b
    return a

def ior(a, b):
    a |= b
    return a

def ipow(a, b):
    a **= b
    return a

def irshift(a, b):
    a >>= b
    return a

def isub(a, b):
    a -= b
    return a

def itruediv(a, b):
    a /= b
    return a

def ixor(a, b):
    a ^= b
    return a


# The dunder aliases.
__lt__ = lt
__le__ = le
__eq__ = eq
__ne__ = ne
__ge__ = ge
__gt__ = gt
__not__ = not_
__abs__ = abs
__add__ = add
__and__ = and_
__call__ = call
__floordiv__ = floordiv
__index__ = index
__inv__ = inv
__invert__ = invert
__lshift__ = lshift
__mod__ = mod
__mul__ = mul
__matmul__ = matmul
__neg__ = neg
__or__ = or_
__pos__ = pos
__pow__ = pow
__rshift__ = rshift
__sub__ = sub
__truediv__ = truediv
__xor__ = xor
__concat__ = concat
__contains__ = contains
__delitem__ = delitem
__getitem__ = getitem
__setitem__ = setitem
__iadd__ = iadd
__iand__ = iand
__iconcat__ = iconcat
__ifloordiv__ = ifloordiv
__ilshift__ = ilshift
__imod__ = imod
__imul__ = imul
__imatmul__ = imatmul
__ior__ = ior
__ipow__ = ipow
__irshift__ = irshift
__isub__ = isub
__itruediv__ = itruediv
__ixor__ = ixor
