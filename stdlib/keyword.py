"""keyword -- Python's keywords, and a test for one.

x-python's own; the lists are CPython 3.14's.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = ["iskeyword", "issoftkeyword", "kwlist", "softkwlist"]

kwlist = [
    'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await',
    'break', 'class', 'continue', 'def', 'del', 'elif', 'else', 'except',
    'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is',
    'lambda', 'nonlocal', 'not', 'or', 'pass', 'raise', 'return', 'try',
    'while', 'with', 'yield',
]

softkwlist = ['_', 'case', 'match', 'type']

_kw = set(kwlist)
_softkw = set(softkwlist)


def iskeyword(s):
    return s in _kw


def issoftkeyword(s):
    return s in _softkw
