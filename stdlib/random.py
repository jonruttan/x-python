"""Random numbers, as CPython's random module draws them.

The generator is the Mersenne Twister, MT19937, in x as the module _random
(lib/python/_random.x), seeded as CPython seeds it, so a program that seeds
with an int draws the numbers CPython draws: random.seed(42); random.random()
is 0.6394267984578837 here too.  The distributions are CPython's algorithms
over that stream, in Python as CPython has them.

Divergences: a str, bytes or bytearray seed is taken by its bytes as an int,
where CPython also hashes it with SHA-512, so its sequence is not CPython's.
seed() with no argument mixes the clock-free sources this runtime has, since
there is no os.urandom here.
"""

import _random
from math import log as _log, exp as _exp, pi as _pi, e as _e, ceil as _ceil
from math import sqrt as _sqrt, cos as _cos, sin as _sin, floor as _floor

__all__ = ["Random", "seed", "random", "uniform", "randint", "choice",
           "sample", "randrange", "shuffle", "normalvariate", "triangular",
           "gauss", "expovariate", "choices", "getstate", "setstate",
           "getrandbits", "randbytes"]

NV_MAGICCONST = 4 * _exp(-0.5) / _sqrt(2.0)
TWOPI = 2.0 * _pi
LOG4 = _log(4.0)
BPF = 53
RECIP_BPF = 2 ** -BPF

_N = 624
_MASK = 0xffffffff

_seed_count = [0]


class Random:
    """A generator of its own, seeded with x as random.seed(x) is."""

    VERSION = 3

    def __init__(self, x=None):
        self._st = _random.new()
        self.seed(x)
        self.gauss_next = None

    # --- seeding and state ---------------------------------------------------

    def seed(self, a=None, version=2):
        if a is None:
            _seed_count[0] += 1
            a = (id(object()) << 20) ^ (id(self) << 3) ^ _seed_count[0]
        elif isinstance(a, (str, bytes, bytearray)):
            if isinstance(a, str):
                a = a.encode()
            a = int.from_bytes(a, "big")
        elif not isinstance(a, int):
            if isinstance(a, (float, bool)):
                a = hash(a)
            else:
                raise TypeError("The only supported seed types are:\n"
                                "None, int, float, str, bytes, and bytearray.")
        if a < 0:
            a = -a
        key = []
        while a:
            key.append(a & _MASK)
            a >>= 32
        if not key:
            key = [0]
        _random.init_by_array(self._st, key)
        self.gauss_next = None

    def getstate(self):
        return (self.VERSION, _random.getstate(self._st), self.gauss_next)

    def setstate(self, state):
        version = state[0]
        if version != 3:
            raise ValueError("state with version %s passed to "
                             "Random.setstate() of version %s" %
                             (version, self.VERSION))
        internal = state[1]
        if len(internal) != _N + 1:
            raise ValueError("state vector is the wrong size")
        for w in internal:
            if not isinstance(w, int) or not 0 <= w <= _MASK:
                raise ValueError("invalid state")
        if internal[_N] > _N:
            raise ValueError("invalid state")
        _random.setstate(self._st, tuple(internal))
        self.gauss_next = state[2]

    # --- the basic draws -----------------------------------------------------

    def random(self):
        """A float in [0.0, 1.0), from 53 random bits."""
        return _random.random(self._st)

    def getrandbits(self, k):
        """A non-negative int with k random bits."""
        if k < 0:
            raise ValueError("Cannot convert negative int")
        if k == 0:
            return 0
        if k <= 32:
            return _random.getrandbits(self._st, k)
        r = 0
        shift = 0
        while k > 0:
            w = _random.genrand(self._st)
            if k < 32:
                w >>= 32 - k
            r |= w << shift
            shift += 32
            k -= 32
        return r

    def randbytes(self, n):
        """n random bytes."""
        return self.getrandbits(n * 8).to_bytes(n, "little")

    def _randbelow(self, n):
        k = n.bit_length()
        r = self.getrandbits(k)
        while r >= n:
            r = self.getrandbits(k)
        return r

    # --- ints and sequences --------------------------------------------------

    def randrange(self, start, stop=None, step=1):
        """A random item of range(start, stop, step)."""
        istart = _index(start)
        if stop is None:
            if step != 1:
                raise TypeError("Missing a non-None stop argument")
            if istart > 0:
                return self._randbelow(istart)
            raise ValueError("empty range for randrange()")
        istop = _index(stop)
        width = istop - istart
        istep = _index(step)
        if istep == 1:
            if width > 0:
                return istart + self._randbelow(width)
            raise ValueError("empty range in randrange(%d, %d)" % (istart, istop))
        if istep > 0:
            n = (width + istep - 1) // istep
        elif istep < 0:
            n = (width + istep + 1) // istep
        else:
            raise ValueError("zero step for randrange()")
        if n <= 0:
            raise ValueError("empty range in randrange(%d, %d, %d)" % (istart, istop, istep))
        return istart + istep * self._randbelow(n)

    def randint(self, a, b):
        """A random int in [a, b], both ends included."""
        return self.randrange(a, b + 1)

    def choice(self, seq):
        """A random element of the non-empty sequence seq."""
        if not len(seq):
            raise IndexError("Cannot choose from an empty sequence")
        return seq[self._randbelow(len(seq))]

    def shuffle(self, x):
        """Shuffle the list x in place."""
        randbelow = self._randbelow
        for i in reversed(range(1, len(x))):
            j = randbelow(i + 1)
            x[i], x[j] = x[j], x[i]

    def sample(self, population, k, *, counts=None):
        """k unique elements chosen from population, in selection order."""
        if isinstance(population, (set, frozenset)):
            raise TypeError("Population must be a sequence.  "
                            "For dicts or sets, use sorted(d).")
        n = len(population)
        if counts is not None:
            cum_counts = []
            total = 0
            for c in counts:
                total += c
                cum_counts.append(total)
            if len(cum_counts) != n:
                raise ValueError("The number of counts does not match the population")
            if not isinstance(total, int):
                raise TypeError("Counts must be integers")
            if total < 0:
                raise ValueError("Counts must be non-negative")
            selections = self.sample(range(total), k=k)
            return [population[_bisect_right(cum_counts, s)] for s in selections]
        randbelow = self._randbelow
        if not 0 <= k <= n:
            raise ValueError("Sample larger than population or is negative")
        result = [None] * k
        setsize = 21
        if k > 5:
            setsize += 4 ** _ceil(_log(k * 3) / LOG4)
        if n <= setsize:
            pool = list(population)
            for i in range(k):
                j = randbelow(n - i)
                result[i] = pool[j]
                pool[j] = pool[n - i - 1]
        else:
            selected = set()
            for i in range(k):
                j = randbelow(n)
                while j in selected:
                    j = randbelow(n)
                selected.add(j)
                result[i] = population[j]
        return result

    def choices(self, population, weights=None, *, cum_weights=None, k=1):
        """k elements chosen from population with replacement."""
        random = self.random
        n = len(population)
        if cum_weights is None:
            if weights is None:
                n += 0.0
                return [population[_floor(random() * n)] for i in range(k)]
            cum_weights = []
            total = 0
            for w in weights:
                total += w
                cum_weights.append(total)
        elif weights is not None:
            raise TypeError("Cannot specify both weights and cumulative weights")
        if len(cum_weights) != n:
            raise ValueError("The number of weights does not match the population")
        total = cum_weights[-1] + 0.0
        if total <= 0.0:
            raise ValueError("Total of weights must be greater than zero")
        hi = n - 1
        return [population[_bisect_right(cum_weights, random() * total, 0, hi)]
                for i in range(k)]

    # --- real-valued distributions -------------------------------------------

    def uniform(self, a, b):
        """A random float between a and b."""
        return a + (b - a) * self.random()

    def triangular(self, low=0.0, high=1.0, mode=None):
        """A float from the triangular distribution on [low, high]."""
        u = self.random()
        try:
            c = 0.5 if mode is None else (mode - low) / (high - low)
        except ZeroDivisionError:
            return low
        if u > c:
            u = 1.0 - u
            c = 1.0 - c
            low, high = high, low
        return low + (high - low) * _sqrt(u * c)

    def normalvariate(self, mu=0.0, sigma=1.0):
        """The normal distribution, by Kinderman and Monahan's method."""
        random = self.random
        while True:
            u1 = random()
            u2 = 1.0 - random()
            z = NV_MAGICCONST * (u1 - 0.5) / u2
            zz = z * z / 4.0
            if zz <= -_log(u2):
                break
        return mu + z * sigma

    def gauss(self, mu=0.0, sigma=1.0):
        """The normal distribution, two values per pair of draws."""
        random = self.random
        z = self.gauss_next
        self.gauss_next = None
        if z is None:
            x2pi = random() * TWOPI
            g2rad = _sqrt(-2.0 * _log(1.0 - random()))
            z = _cos(x2pi) * g2rad
            self.gauss_next = _sin(x2pi) * g2rad
        return mu + z * sigma

    def expovariate(self, lambd=1.0):
        """The exponential distribution with rate lambd."""
        return -_log(1.0 - self.random()) / lambd


def _index(n):
    if isinstance(n, int):
        return n
    try:
        return n.__index__()
    except AttributeError:
        raise TypeError("'%s' object cannot be interpreted as an integer"
                        % type(n).__name__)


def _bisect_right(a, x, lo=0, hi=None):
    if hi is None:
        hi = len(a)
    while lo < hi:
        mid = (lo + hi) // 2
        if x < a[mid]:
            hi = mid
        else:
            lo = mid + 1
    return lo


_inst = Random()
seed = _inst.seed
random = _inst.random
uniform = _inst.uniform
triangular = _inst.triangular
randint = _inst.randint
choice = _inst.choice
randrange = _inst.randrange
sample = _inst.sample
shuffle = _inst.shuffle
choices = _inst.choices
normalvariate = _inst.normalvariate
gauss = _inst.gauss
expovariate = _inst.expovariate
getstate = _inst.getstate
setstate = _inst.setstate
getrandbits = _inst.getrandbits
randbytes = _inst.randbytes
