depth = "deep"
try:
    from ... import nothing
except ImportError as e:
    print("ImportError", e)
