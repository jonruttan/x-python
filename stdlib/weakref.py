"""Weak references: ref and finalize, as CPython's weakref module has them.

A ref holds its object by address, in the module _weakref
(lib/python/_weakref.x), so the collector does not see it; the collector's
free hook tells which refs a collection leaves dangling.  A dead ref answers
None, and its callback is called with it, newest ref first.  finalize is
CPython's: a ref whose callback is the finalizer, kept alive by a registry.

Divergences: there is no reference counting here, so an object dies at a
collection, and callbacks run when gc.collect() returns -- the collections
the runtime makes on its own clear refs but leave their callbacks for the next
gc.collect().  Finalizers do not run at exit.  ref(o) makes a new ref each time
where CPython hands back the one it has.  proxy, WeakMethod, WeakSet and the
weak dictionaries are not here yet.
"""

import _weakref
import sys

__all__ = ["ref", "getweakrefcount", "getweakrefs", "ReferenceType", "finalize"]

# CPython refuses these, and here some are not heap objects at all: an int, a
# None or a bool may be a constant the whole runtime shares.
_NOT_WEAK = (type(None), bool, int, float, complex, str, bytes, bytearray,
             tuple, list, dict, type(Ellipsis), type(NotImplemented))


def _check(ob):
    if type(ob) in _NOT_WEAK:
        raise TypeError("cannot create weak reference to %r object"
                        % type(ob).__name__)


class ReferenceType:
    """A weak reference to an object: calling it answers the object, or None
    once the object has been collected."""

    def __init__(self, ob, callback=None):
        _check(ob)
        self.__callback__ = callback
        self._hash = None
        self._cell = _weakref.new(ob, self, callback)

    def __call__(self):
        return _weakref.get(self._cell)

    def __repr__(self):
        ob = self()
        if ob is None:
            return "<weakref at %#x; dead>" % id(self)
        return "<weakref at %#x; to %r at %#x>" % (id(self), type(ob).__name__, id(ob))

    def __eq__(self, other):
        if not isinstance(other, ReferenceType):
            return NotImplemented
        a, b = self(), other()
        if a is None or b is None:
            return self is other
        return a == b

    def __ne__(self, other):
        eq = self.__eq__(other)
        return eq if eq is NotImplemented else not eq

    def __hash__(self):
        if self._hash is None:
            ob = self()
            if ob is None:
                raise TypeError("weak object has gone away")
            self._hash = hash(ob)
        return self._hash


ref = ReferenceType


def getweakrefcount(ob):
    return len(_weakref.refs(ob))


def getweakrefs(ob):
    return _weakref.refs(ob)


class _FinalizeInfo:
    pass


class finalize:
    """Call func(*args, **kwargs) when obj is collected, unless the finalizer
    has been called or detached first."""

    _registry = {}

    def __init__(self, obj, func, *args, **kwargs):
        _check(obj)
        info = _FinalizeInfo()
        info.weakref = ref(obj, self)
        info.func = func
        info.args = args
        info.kwargs = kwargs or None
        finalize._registry[self] = info

    def __call__(self, _=None):
        info = finalize._registry.pop(self, None)
        if info:
            return info.func(*info.args, **(info.kwargs or {}))

    def detach(self):
        info = finalize._registry.get(self)
        obj = info and info.weakref()
        if obj is not None and finalize._registry.pop(self, None):
            return (obj, info.func, info.args, info.kwargs or {})

    def peek(self):
        info = finalize._registry.get(self)
        obj = info and info.weakref()
        if obj is not None:
            return (obj, info.func, info.args, info.kwargs or {})

    @property
    def alive(self):
        return self in finalize._registry

    def __repr__(self):
        info = finalize._registry.get(self)
        obj = info and info.weakref()
        if obj is None:
            return "<finalize object at %#x; dead>" % id(self)
        return "<finalize object at %#x; for %r at %#x>" % (id(self), type(obj).__name__, id(obj))


def _run_callbacks():
    for r, callback in _weakref.dead():
        try:
            callback(r)
        except Exception as e:
            print("Exception ignored while calling weakref callback %r:" % (callback,),
                  file=sys.stderr)
            print("%s: %s" % (type(e).__name__, e), file=sys.stderr)


_weakref.on_collect(_run_callbacks)
