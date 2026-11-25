"""copy -- shallow and deep copying.

x-python's own, written to CPython 3.14's interface: copy, deepcopy,
replace and Error.  A class controls its copies the ways CPython's do:
with __copy__ and __deepcopy__, with __reduce_ex__ or __reduce__, or with
__getnewargs_ex__, __getnewargs__, __getstate__ and __setstate__.

CPython reaches an object's parts through object.__reduce_ex__ and the
copyreg module.  x-python has neither, so _reduce below answers what
object.__reduce_ex__(4) would, and copyreg's dispatch_table isn't
consulted.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = ["Error", "copy", "deepcopy", "replace"]


class Error(Exception):
    pass


error = Error   # the old name


def _function():
    pass


class _Method:
    def method(self):
        pass


_NoneType = type(None)
_EllipsisType = type(...)
_NotImplementedType = type(NotImplemented)
_BuiltinFunctionType = type(len)
_FunctionType = type(_function)
_MethodType = type(_Method().method)

# What copy() hands back as it is: the immutable, and what can't be copied
# but is safe to share.
_copy_atomic_types = {_NoneType, int, float, bool, complex, str, tuple,
                      bytes, frozenset, type, range, slice, property,
                      _BuiltinFunctionType, _EllipsisType,
                      _NotImplementedType, _FunctionType}
try:
    _copy_atomic_types.add(super)
except NameError:
    pass    # x-python's super is a form a call spells, not a value
_copy_builtin_containers = {list, dict, set, bytearray}

# What deepcopy() hands back as it is: a tuple or a frozenset may hold
# something mutable, so they aren't here.
_atomic_types = {_NoneType, _EllipsisType, _NotImplementedType, int, float,
                 bool, complex, bytes, str, type, range,
                 _BuiltinFunctionType, _FunctionType, property}


def copy(x):
    """Shallow copy operation on arbitrary Python objects.

    The copy is a new object holding the same objects the original holds."""
    cls = type(x)
    if cls in _copy_atomic_types:
        return x
    if cls in _copy_builtin_containers:
        return cls.copy(x)
    if issubclass(cls, type):
        return x
    copier = getattr(cls, "__copy__", None)
    if copier is not None:
        return copier(x)
    rv = _reduce(x)
    if isinstance(rv, str):
        return x
    return _reconstruct(x, None, *rv)


def deepcopy(x, memo=None, _nil=[]):
    """Deep copy operation on arbitrary Python objects.

    The copy holds copies of what the original holds, down to the atoms.
    memo maps the id of each object copied so far to its copy, so an object
    met twice is copied once and a cycle is copied as a cycle."""
    cls = type(x)
    if cls in _atomic_types:
        return x
    d = id(x)
    if memo is None:
        memo = {}
    else:
        y = memo.get(d, _nil)
        if y is not _nil:
            return y
    copier = _deepcopy_dispatch.get(cls)
    if copier is not None:
        y = copier(x, memo)
    elif issubclass(cls, type):
        y = x
    else:
        copier = getattr(x, "__deepcopy__", None)
        if copier is not None:
            y = copier(memo)
        else:
            rv = _reduce(x)
            if isinstance(rv, str):
                y = x
            else:
                y = _reconstruct(x, memo, *rv)
    if y is not x:
        memo[d] = y
        _keep_alive(x, memo)
    return y


def _deepcopy_list(x, memo):
    y = []
    memo[id(x)] = y
    for a in x:
        y.append(deepcopy(a, memo))
    return y


def _deepcopy_tuple(x, memo):
    y = [deepcopy(a, memo) for a in x]
    # a cycle through the tuple may have copied it already
    try:
        return memo[id(x)]
    except KeyError:
        pass
    for k, j in zip(x, y):
        if k is not j:
            return tuple(y)
    return x


def _deepcopy_dict(x, memo):
    y = {}
    memo[id(x)] = y
    for key, value in x.items():
        y[deepcopy(key, memo)] = deepcopy(value, memo)
    return y


def _deepcopy_method(x, memo):
    # the same function, bound to a copy of its object
    return type(x)(x.__func__, deepcopy(x.__self__, memo))


_deepcopy_dispatch = {
    list: _deepcopy_list,
    tuple: _deepcopy_tuple,
    dict: _deepcopy_dict,
    _MethodType: _deepcopy_method,
}


def _keep_alive(x, memo):
    # The memo knows objects by id, so it keeps each original alive while
    # it lives; under its own id, which nothing else uses unless the memo
    # itself is copied.
    try:
        memo[id(memo)].append(x)
    except KeyError:
        memo[id(memo)] = [x]


# --- what object.__reduce_ex__(4) would answer -------------------------------

def _newobj(cls, *args):
    return cls.__new__(cls, *args)


def _newobj_ex(cls, args, kwargs):
    return cls.__new__(cls, *args, **kwargs)


# object's own, where there are any; the rest of this section stands in
# for them
_object_reduce_ex = getattr(object, "__reduce_ex__", None)
_object_reduce = getattr(object, "__reduce__", None)


def _reduce(x):
    # A class's own __reduce_ex__ or __reduce__ comes first, as it does for
    # CPython's object.__reduce_ex__.
    cls = type(x)
    reductor = getattr(cls, "__reduce_ex__", None)
    if reductor is not None and reductor is not _object_reduce_ex:
        return x.__reduce_ex__(4)
    reductor = getattr(cls, "__reduce__", None)
    if reductor is not None and reductor is not _object_reduce:
        return x.__reduce__()
    # a bound method reduces to reading the method off its object again
    if cls is _MethodType:
        return (getattr, (x.__self__, x.__func__.__name__))
    # set and frozenset reduce to a call of the class on a list; so does
    # bytearray, on bytes
    for base, part in ((set, list), (frozenset, list), (bytearray, bytes)):
        if isinstance(x, base):
            return (cls, (part(x),), _state(x))
    getnewargs_ex = getattr(x, "__getnewargs_ex__", None)
    if getnewargs_ex is not None:
        args, kwargs = getnewargs_ex()
    else:
        getnewargs = getattr(x, "__getnewargs__", None)
        args = getnewargs() if getnewargs is not None else _newargs(x)
        kwargs = None
    getstate = getattr(x, "__getstate__", None)
    state = getstate() if getstate is not None else _state(x)
    listiter = iter(x) if isinstance(x, list) else None
    dictiter = iter(x.items()) if isinstance(x, dict) else None
    if kwargs:
        return (_newobj_ex, (cls, args, kwargs), state, listiter, dictiter)
    return (_newobj, (cls,) + tuple(args), state, listiter, dictiter)


# The value a subclass of each immutable builtin is made from, as its
# __getnewargs__ answers in CPython.
_immutable_bases = (bool, int, float, str, bytes, tuple)


def _newargs(x):
    if isinstance(x, complex):
        return (x.real, x.imag)
    for base in _immutable_bases:
        if isinstance(x, base):
            return (base(x),)
    if (type(x) is not object and not isinstance(x, (list, dict)) and
            not hasattr(x, "__dict__") and not _slot_names(type(x))):
        # a builtin's own state isn't reachable from here
        raise TypeError("cannot pickle %r object" % type(x).__name__)
    return ()


def _slot_names(cls):
    # every slot cls and its bases declare, but __dict__ and __weakref__
    names = []
    seen = set()
    todo = [cls]
    while todo:
        c = todo.pop()
        if c in seen:
            continue
        seen.add(c)
        slots = vars(c).get("__slots__", ()) if hasattr(c, "__dict__") else ()
        if isinstance(slots, str):
            slots = (slots,)
        for name in slots:
            if name not in ("__dict__", "__weakref__") and name not in names:
                names.append(name)
        todo.extend(getattr(c, "__bases__", ()))
    return names


def _state(x):
    # object.__getstate__: the instance's dict, or None when it is empty;
    # with slots, the dict (or None) and a dict of the slots that are set
    d = getattr(x, "__dict__", None) or None
    names = _slot_names(type(x))
    if not names:
        return d
    slots = {}
    for name in names:
        try:
            slots[name] = getattr(x, name)
        except AttributeError:
            pass
    return (d, slots) if slots else d


def _reconstruct(x, memo, func, args,
                 state=None, listiter=None, dictiter=None, *_rest):
    deep = memo is not None
    if deep and args:
        args = [deepcopy(arg, memo) for arg in args]
    y = func(*args)
    if deep:
        memo[id(x)] = y
    if state is not None:
        if deep:
            state = deepcopy(state, memo)
        if hasattr(y, "__setstate__"):
            y.__setstate__(state)
        else:
            if isinstance(state, tuple) and len(state) == 2:
                state, slotstate = state
            else:
                slotstate = None
            if state is not None:
                y.__dict__.update(state)
            if slotstate is not None:
                for key, value in slotstate.items():
                    setattr(y, key, value)
    if listiter is not None:
        for item in listiter:
            y.append(deepcopy(item, memo) if deep else item)
    if dictiter is not None:
        for key, value in dictiter:
            if deep:
                key = deepcopy(key, memo)
                value = deepcopy(value, memo)
            y[key] = value
    return y


def replace(*args, **changes):
    """replace(obj, /, **changes)

    A new object like obj with the fields changes names replaced, as obj's
    class's __replace__ makes it: a named tuple, a frozen dataclass, a
    date."""
    # (*args stands in for a positional-only obj, which x-python's parser
    # doesn't take yet)
    if not args:
        raise TypeError("replace() missing 1 required positional argument: 'obj'")
    if len(args) > 1:
        raise TypeError("replace() takes 1 positional argument but %d were given"
                        % len(args))
    obj = args[0]
    cls = obj.__class__
    func = getattr(cls, "__replace__", None)
    if func is None:
        raise TypeError("replace() does not support %s objects" % cls.__name__)
    return func(obj, **changes)
