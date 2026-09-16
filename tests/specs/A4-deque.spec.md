# collections.deque

### a bound deque drops from the other end

```python
(python-run "from collections import deque\nd = deque((), 2)\nprint(len(d), bool(d), d.append(1), len(d), bool(d))\nd.append(2)\nd.append(3)\nprint(d, d.popleft(), d.popleft(), len(d))\ntry:\n    d.popleft()\nexcept IndexError as e:\n    print(\"IndexError\", e)\ntry:\n    d.pop()\nexcept IndexError as e:\n    print(\"IndexError\", e)\nfor i in range(5):\n    d.appendleft(i)\nprint(d, d.pop(), d.pop())\nd = deque([1, 2, 3, 4, 5], 3)\nprint(d, list(d))\nd.extend([6, 7])\nprint(d)\nd.extendleft([0, -1])\nprint(d)\n")
```
---
```output
0 False None 1 True
deque([], maxlen=2) 2 3 0
IndexError pop from an empty deque
IndexError pop from an empty deque
deque([], maxlen=2) 3 4
deque([3, 4, 5], maxlen=3) [3, 4, 5]
deque([5, 6, 7], maxlen=3)
deque([-1, 0, 5], maxlen=3)
```

### reading, storing and deleting by position, and no slices

```python
(python-run "from collections import deque\nd = deque((0, 1, 2, 3), 5)\nprint(d[0], d[1], d[-1], d[-4])\nd[3] = 5\nd[-4] = 9\nprint(d)\ndel d[1]\nprint(d)\nfor expr in [\"d[4]\", \"d[-5]\"]:\n    try:\n        eval(expr)\n    except IndexError as e:\n        print(\"IndexError\", e)\ntry:\n    d[4] = 0\nexcept IndexError as e:\n    print(\"IndexError\", e)\ntry:\n    del d[9]\nexcept IndexError as e:\n    print(\"IndexError\", e)\ntry:\n    d[\"0\"]\nexcept TypeError as e:\n    print(\"TypeError\", e)\ntry:\n    d[0:1]\nexcept TypeError as e:\n    print(\"TypeError\", e)\ntry:\n    d[0:1] = (-1, -2)\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    del d[0:1]\nexcept TypeError:\n    print(\"TypeError\")\n")
```
---
```output
0 1 3 0
deque([9, 1, 2, 5], maxlen=5)
deque([9, 2, 5], maxlen=5)
IndexError deque index out of range
IndexError deque index out of range
IndexError deque index out of range
IndexError deque index out of range
TypeError sequence index must be integer, not 'str'
TypeError sequence index must be integer, not 'slice'
TypeError
TypeError
```

### construction, the bound, and what a deque is not

```python
(python-run "from collections import deque\nprint(deque(), deque([1, 2, 3]), deque(\"ab\"), deque([], 2), deque([1, 2, 3], maxlen=2))\nprint(deque().maxlen, deque(maxlen=5).maxlen, deque(range(3), 0))\nprint(type(deque()).__name__, isinstance(deque(), list), isinstance(deque(), deque))\ntry:\n    deque((), -1)\nexcept ValueError as e:\n    print(\"ValueError\", e)\ntry:\n    deque(5)\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    ~deque()\nexcept TypeError:\n    print(\"TypeError\")\ntry:\n    hash(deque())\nexcept TypeError:\n    print(\"TypeError\")\n")
```
---
```output
deque([]) deque([1, 2, 3]) deque(['a', 'b']) deque([], maxlen=2) deque([2, 3], maxlen=2)
None 5 deque([], maxlen=0)
deque False True
ValueError maxlen must be non-negative
TypeError
TypeError
TypeError
```

### insert, index, count, remove, rotate, reverse, copy and clear

```python
(python-run "from collections import deque\nd = deque([1, 2, 3, 2])\nd.insert(1, 9)\nd.insert(-1, 8)\nd.insert(99, 7)\nprint(d, d.count(2), d.count(5), d.index(2), d.index(2, 3), d.index(7))\nd.remove(2)\nprint(d)\nfor expr in [\"d.remove(99)\", \"d.index(99)\", \"d.index(9, 2)\"]:\n    try:\n        eval(expr)\n    except ValueError as e:\n        print(\"ValueError\", e)\nd.rotate()\nprint(d)\nd.rotate(-2)\nprint(d)\nd.rotate(13)\nprint(d)\nd.reverse()\nprint(d)\ne = d.copy()\ne.append(0)\nprint(d, e)\nd.clear()\nprint(d, len(d), bool(d))\nf = deque([1], 1)\ntry:\n    f.insert(0, 2)\nexcept IndexError as e:\n    print(\"IndexError\", e)\n")
```
---
```output
deque([1, 9, 2, 3, 8, 2, 7]) 2 0 2 5 6
deque([1, 9, 3, 8, 2, 7])
ValueError deque.remove(x): x not in deque
ValueError deque.index(x): x not in deque
ValueError deque.index(x): x not in deque
deque([7, 1, 9, 3, 8, 2])
deque([9, 3, 8, 2, 7, 1])
deque([1, 9, 3, 8, 2, 7])
deque([7, 2, 8, 3, 9, 1])
deque([7, 2, 8, 3, 9, 1]) deque([7, 2, 8, 3, 9, 1, 0])
deque([]) 0 False
IndexError deque already at its maximum size
```

### equality, +, *, += and ordering, and a deque where an iterable is wanted

```python
(python-run "from collections import deque\na = deque([1, 2])\nb = deque([1, 2], 5)\nprint(a == b, a != b, a == [1, 2], a == deque([2, 1]))\nprint(a + deque([3]), deque([1, 2], 3) + deque([3, 4]), a * 2, 2 * a, deque([1, 2], 3) * 2)\ntry:\n    a + [3]\nexcept TypeError as e:\n    print(\"TypeError\", e)\nc = a\nc += [3, 4]\nprint(a, c is a)\nprint(deque([1, 2]) < deque([1, 3]), deque([2]) >= deque([1, 9]), deque([1]) <= deque([1]))\nprint([x * 10 for x in a], list(reversed(a)), 3 in a, 9 in a, len(a), bool(deque()))\nprint(sorted(deque([3, 1, 2])), sum(deque([1, 2, 3])), max(deque([4, 7, 5])))\n")
```
---
```output
True False False False
deque([1, 2, 3]) deque([2, 3, 4], maxlen=3) deque([1, 2, 1, 2]) deque([1, 2, 1, 2]) deque([2, 1, 2], maxlen=3)
TypeError can only concatenate deque (not "list") to deque
deque([1, 2, 3, 4]) True
True True True
[10, 20, 30, 40] [4, 3, 2, 1] True False 4 False
[1, 2, 3] 6 7
```

### a subclass of deque

```python
(python-run "from collections import deque\nclass D(deque):\n    def peek(self):\n        return self[-1]\nd = D([1, 2, 3], 2)\nd.append(4)\nprint(len(d), list(d), d[0], d.peek(), d.maxlen, isinstance(d, deque), type(d).__name__)\nprint(3 in d, 1 in d, d == deque([3, 4]))\n")
```
---
```output
2 [3, 4] 3 4 2 True D
True False True
```
