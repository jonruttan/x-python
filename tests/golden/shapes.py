# shapes.py -- one of each layout the tokenizer and the parser decide
import math

class Shape:
    def __init__(self, name, sides=0):
        self.name = name
        self.sides = sides

    def describe(self):
        return f"{self.name}: {self.sides} sides"

def area(kind, *dims):
    if kind == "circle":
        return math.pi * dims[0] ** 2
    elif kind == "rect":
        return dims[0] * dims[1]
    else:
        raise ValueError("unknown " + kind)

shapes = [Shape(n, s) for n, s in (("triangle", 3), ("square", 4))]
total = 0
for s in shapes:
    total += s.sides  # counted
print(total, {s.name: s.sides for s in shapes}, area("rect", 2, 0x10))
