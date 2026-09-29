# cmath

The functions of a complex argument, each computed from the real functions by
the formula CPython's `cmath` computes it with.  The expectations are CPython
3.14's, printed to nine significant digits.

## the module

### the polar form, exp, log and sqrt, on both sides of the cut

```python
(python-run "import cmath\nvals = [complex(0.5, 1.25), complex(-2.0, 0.0), complex(-2.0, -0.0), complex(0.0, -3.0), complex(1e-3, 1.0), complex(3.0, -4.0), 2, 0.25]\ndef show(name, r):\n    if type(r) == tuple:\n        print(name, \"%.9g %.9g\" % r)\n    elif type(r) == float:\n        print(name, \"%.9g\" % r)\n    else:\n        print(name, \"%.9g %.9g\" % (r.real, r.imag))\nfor v in vals:\n    print(v)\n    show(\"phase\", cmath.phase(v))\n    show(\"polar\", cmath.polar(v))\n    show(\"exp\", cmath.exp(v))\n    show(\"log\", cmath.log(v))\n    show(\"log10\", cmath.log10(v))\n    show(\"log2\", cmath.log(v, 2))\n    show(\"sqrt\", cmath.sqrt(v))\nshow(\"rect\", cmath.rect(2, 0.5))\nshow(\"rect\", cmath.rect(1, 0))\nprint(cmath.sqrt(-1), cmath.sqrt(complex(0.0, 0.0)), cmath.sqrt(4), type(cmath.sqrt(4)).__name__)")
```
---
```output
(0.5+1.25j)
phase 1.19028995
polar 1.3462912 1.19028995
exp 0.519878686 1.56461113
log 0.297353554 1.19028995
log10 0.129139008 0.516936357
log2 0.428990498 1.71722541
sqrt 0.960804663 0.650496427
(-2+0j)
phase 3.14159265
polar 2 3.14159265
exp 0.135335283 0
log 0.693147181 3.14159265
log10 0.301029996 1.36437635
log2 1 4.53236014
sqrt 0 1.41421356
(-2-0j)
phase -3.14159265
polar 2 -3.14159265
exp 0.135335283 -0
log 0.693147181 -3.14159265
log10 0.301029996 -1.36437635
log2 1 -4.53236014
sqrt 0 -1.41421356
-3j
phase -1.57079633
polar 3 -1.57079633
exp -0.989992497 -0.141120008
log 1.09861229 -1.57079633
log10 0.477121255 -0.682188177
log2 1.5849625 -2.26618007
sqrt 1.22474487 -1.22474487
(0.001+1j)
phase 1.56979633
polar 1.0000005 1.56979633
exp 0.540842878 0.842312877
log 4.9999975e-07 1.56979633
log10 2.17147132e-07 0.681753883
log2 7.2134716e-07 2.26473738
sqrt 0.707460423 0.706753316
(3-4j)
phase -0.927295218
polar 5 -0.927295218
exp -13.1287831 15.2007845
log 1.60943791 -0.927295218
log10 0.698970004 -0.402719196
log2 2.32192809 -1.33780421
sqrt 2 -1
2
phase 0
polar 2 0
exp 7.3890561 0
log 0.693147181 0
log10 0.301029996 0
log2 1 0
sqrt 1.41421356 0
0.25
phase 0
polar 0.25 0
exp 1.28402542 0
log -1.38629436 0
log10 -0.602059991 0
log2 -2 0
sqrt 0.5 0
rect 1.75516512 0.958851077
rect 1 0
1j 0j (2+0j) complex
```

### the circular and hyperbolic functions and their inverses

```python
(python-run "import cmath\nvals = [complex(0.5, 1.25), complex(-2.0, 0.0), complex(-2.0, -0.0), complex(0.0, -3.0), complex(0.25, 0.0), complex(3.0, -4.0), complex(0.0, 2.0), complex(0.0, -2.0), 0.5]\nnames = [\"cos\", \"sin\", \"tan\", \"cosh\", \"sinh\", \"tanh\", \"acos\", \"asin\", \"atan\", \"acosh\", \"asinh\", \"atanh\"]\nfor v in vals:\n    print(v)\n    for n in names:\n        r = getattr(cmath, n)(v)\n        print(n, \"%.9g %.9g\" % (r.real, r.imag))\nr = cmath.tanh(complex(400.0, 1.0))\nprint(\"%.9g %.9g\" % (r.real, r.imag))")
```
---
```output
(0.5+1.25j)
cos 1.65724786 -0.768000918
sin 0.905358634 1.40581625
tan 0.126108566 0.906724804
cosh 0.355565683 0.49451143
sinh 0.164313003 1.0700997
tanh 1.58396355 0.806634699
acos 1.26281496 -1.08557656
asin 0.307981372 1.08557656
atan 1.12655644 0.708303336
acosh 1.08557656 1.26281496
asinh 0.898893629 1.06118577
atanh 0.185894509 0.942514113
(-2+0j)
cos -0.416146837 0
sin -0.909297427 -0
tan 2.18503986 0
cosh 3.76219569 -0
sinh -3.62686041 0
tanh -0.96402758 0
acos 3.14159265 -1.3169579
asin -1.57079633 1.3169579
atan -1.10714872 0
acosh 1.3169579 3.14159265
asinh -1.44363548 0
atanh -0.549306144 1.57079633
(-2-0j)
cos -0.416146837 -0
sin -0.909297427 0
tan 2.18503986 -0
cosh 3.76219569 0
sinh -3.62686041 -0
tanh -0.96402758 -0
acos 3.14159265 1.3169579
asin -1.57079633 -1.3169579
atan -1.10714872 -0
acosh 1.3169579 -3.14159265
asinh -1.44363548 -0
atanh -0.549306144 -1.57079633
-3j
cos 10.067662 0
sin 0 -10.0178749
tan 0 -0.995054754
cosh -0.989992497 -0
sinh -0 -0.141120008
tanh 0 0.142546543
acos 1.57079633 1.81844646
asin 0 -1.81844646
atan 1.57079633 -0.34657359
acosh 1.81844646 -1.57079633
asinh 1.76274717 -1.57079633
atanh 0 -1.24904577
(0.25+0j)
cos 0.968912422 -0
sin 0.247403959 0
tan 0.255341921 0
cosh 1.0314131 0
sinh 0.252612317 0
tanh 0.244918662 0
acos 1.31811607 -0
asin 0.252680255 0
atan 0.244978663 0
acosh 0 1.31811607
asinh 0.247466462 0
atanh 0.255412812 0
(3-4j)
cos -27.0349456 3.85115333
sin 3.85373804 27.0168133
tan -0.000187346205 -0.999355987
cosh -6.58066304 7.58155274
sinh -6.54812004 7.61923172
tanh 1.00070954 -0.00490825807
acos 0.936812461 2.30550903
asin 0.633983866 -2.30550903
atan 1.448307 -0.158997192
acosh 2.30550903 -0.936812461
asinh 2.29991404 -0.917616853
atanh 0.117500907 -1.40992105
2j
cos 3.76219569 -0
sin 0 3.62686041
tan 0 0.96402758
cosh -0.416146837 0
sinh -0 0.909297427
tanh 0 -2.18503986
acos 1.57079633 -1.44363548
asin 0 1.44363548
atan 1.57079633 0.549306144
acosh 1.44363548 1.57079633
asinh 1.3169579 1.57079633
atanh 0 1.10714872
-2j
cos 3.76219569 0
sin 0 -3.62686041
tan 0 -0.96402758
cosh -0.416146837 -0
sinh -0 -0.909297427
tanh 0 2.18503986
acos 1.57079633 1.44363548
asin 0 -1.44363548
atan 1.57079633 -0.549306144
acosh 1.44363548 -1.57079633
asinh 1.3169579 -1.57079633
atanh 0 -1.10714872
0.5
cos 0.877582562 -0
sin 0.479425539 0
tan 0.54630249 0
cosh 1.12762597 0
sinh 0.521095305 0
tanh 0.462117157 0
acos 1.04719755 -0
asin 0.523598776 0
atan 0.463647609 0
acosh 0 1.04719755
asinh 0.481211825 0
atanh 0.549306144 0
1 0
```

### constants, arguments, refusals and the predicates

```python
(python-run "import cmath\nprint(\"%.12g %.12g %.12g\" % (cmath.pi, cmath.e, cmath.tau), cmath.inf, cmath.nan, cmath.infj, cmath.nanj)\nclass F:\n    def __float__(self):\n        return 1.5\nclass C:\n    def __complex__(self):\n        return complex(0, 2)\nclass Bad:\n    def __complex__(self):\n        return 1.0\nprint(cmath.sqrt(F()), cmath.sqrt(C()), cmath.phase(True))\nfor f, a in ((cmath.log, ([],)), (cmath.sqrt, (\"1\",)), (cmath.sqrt, (Bad(),)), (cmath.rect, (1j, 0)), (cmath.exp, ())):\n    try:\n        f(*a)\n    except TypeError as e:\n        print(\"TypeError\")\nfor f, a in ((cmath.log, (0,)), (cmath.atanh, (1,)), (cmath.atanh, (-1,)), (cmath.exp, (1000,)), (cmath.cosh, (complex(1000, 1),)), (cmath.log10, (0j,)), (cmath.polar, (complex(1e308, 1e308),))):\n    try:\n        print(f(*a))\n    except (ValueError, OverflowError) as e:\n        print(type(e).__name__, e)\nprint(cmath.isfinite(1j), cmath.isfinite(cmath.infj), cmath.isinf(complex(1, cmath.inf)), cmath.isnan(cmath.nanj), cmath.isnan(2))\nprint(cmath.isclose(1 + 1j, 1 + 1.0000000001j), cmath.isclose(1j, 1.1j), cmath.isclose(1j, 1.1j, rel_tol=0.2), cmath.isclose(0j, 1e-9j, abs_tol=1e-8), cmath.isclose(cmath.infj, cmath.infj))\ntry:\n    cmath.isclose(1, 1, rel_tol=-1)\nexcept ValueError as e:\n    print(\"ValueError\", e)\nfrom cmath import *\nprint(phase(-1), sqrt(-4))")
```
---
```output
3.14159265359 2.71828182846 6.28318530718 inf nan infj nanj
(1.224744871391589+0j) (1+1j) 0.0
TypeError
TypeError
TypeError
TypeError
TypeError
ValueError math domain error
ValueError math domain error
ValueError math domain error
OverflowError math range error
OverflowError math range error
ValueError math domain error
(1.4142135623730951e+308, 0.7853981633974483)
True False True True False
True False True True True
ValueError tolerances must be non-negative
3.141592653589793 2j
```
