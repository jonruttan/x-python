# an instance's __dict__

An instance's `__dict__` is its attributes as a dict, and the same dict each
time: a store or a deletion through it sets or deletes the attribute, without
going through `__setattr__`, and an attribute set the ordinary way shows in
it.  The runtime's own rows are neither shown nor dropped.  The expectations
are CPython 3.14's.

## __dict__

### a live view: stores, update, deletion, clear, vars, exec

```python
(python-run "class P:\n    def __init__(self, x, y):\n        self.x = x\n        self.y = y\n    def norm(self):\n        return self.x + self.y\np = P(1, 2)\nprint(p.__dict__, vars(p) is p.__dict__, p.__dict__ is p.__dict__)\np.__dict__[\"z\"] = 3\np.__dict__.update(w=4)\nprint(p.z, p.w, sorted(p.__dict__))\ndel p.__dict__[\"x\"]\nprint(hasattr(p, \"x\"), p.__dict__)\np.y = 20\nprint(p.__dict__[\"y\"], \"norm\" in p.__dict__, len(p.__dict__))\np.__dict__.clear()\nprint(p.__dict__, hasattr(p, \"y\"))\nclass S:\n    def __setattr__(self, k, v):\n        print(\"setattr\", k)\n        object.__setattr__(self, k, v)\ns = S()\ns.a = 1\ns.__dict__[\"b\"] = 2\nprint(s.a, s.b, s.__dict__)\nclass L(list):\n    pass\nl = L([1])\nl.tag = \"t\"\nprint(l.__dict__, sorted(n for n in dir(l) if not n.startswith(\"_\") and n not in dir(list)))\nexec(\"q = 5\", p.__dict__)\nprint(p.q)")
```
---
```output
{'x': 1, 'y': 2} True True
3 4 ['w', 'x', 'y', 'z']
False {'y': 2, 'z': 3, 'w': 4}
20 False 3
{} False
setattr a
1 2 {'a': 1, 'b': 2}
{'tag': 't'} ['tag']
5
```
