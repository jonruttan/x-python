# json: reading and writing JSON

`stdlib/json/`. Each expected output is a python3.14 run of the same
program.

### dumps writes each kind of value, with indent, separators and sort_keys

```python
(python-run "import json\nprint(json.dumps({\"a\": [1, 2.5, None, True, False], \"b\": \"x\"}))\nprint(json.dumps([1e16, -0.0, 10**20, 1e-7, 0.1]))\nprint(json.dumps(\"tab\\there \\\"q\\\" back\\\\slash \\x01 \\u00e9 \\u20ac \\U0001f600\"))\nprint(ascii(json.dumps(\"\\u00e9 \\u20ac \\U0001f600\", ensure_ascii=False)))\nprint(json.dumps({\"b\": 1, \"a\": {\"d\": [], \"c\": {}}}, sort_keys=True, indent=2))\nprint(json.dumps([1, [2, 3]], indent=\"\\t\"))\nprint(json.dumps({\"k\": [1, 2]}, separators=(\",\", \":\")))\nprint(json.dumps({1: \"int\", 2.5: \"float\", True: \"t\", None: \"n\"}))\nprint(json.dumps((1, 2)), json.dumps([]), json.dumps({}), json.dumps(None))\nprint(json.dumps([float(\"nan\"), float(\"inf\"), -float(\"inf\")]))\n")
```
---
```output
{"a": [1, 2.5, null, true, false], "b": "x"}
[1e+16, -0.0, 100000000000000000000, 1e-07, 0.1]
"tab\there \"q\" back\\slash \u0001 \u00e9 \u20ac \ud83d\ude00"
'"\xe9 \u20ac \U0001f600"'
{
  "a": {
    "c": {},
    "d": []
  },
  "b": 1
}
[
	1,
	[
		2,
		3
	]
]
{"k":[1,2]}
{"1": "t", "2.5": "float", "null": "n"}
[1, 2] [] {} null
[NaN, Infinity, -Infinity]
```

### default, an encoder subclass, and what can't be written

```python
(python-run "import json\nclass P:\n    def __init__(self, x): self.x = x\nprint(json.dumps({\"p\": P(3)}, default=lambda o: {\"P\": o.x}))\nclass Enc(json.JSONEncoder):\n    def default(self, o):\n        if isinstance(o, set):\n            return sorted(o)\n        return super().default(o)\nprint(json.dumps({\"s\": {3, 1, 2}}, cls=Enc))\nfor v, kw in (({\"p\": P(1)}, {}), ([float(\"nan\")], {\"allow_nan\": False}), ({(1, 2): 3}, {}), ({(1, 2): 3, \"ok\": 1}, {\"skipkeys\": True})):\n    try:\n        print(json.dumps(v, **kw))\n    except (TypeError, ValueError) as e:\n        print(type(e).__name__, e)\na = []\na.append(a)\ntry:\n    json.dumps(a)\nexcept ValueError as e:\n    print(\"ValueError\", e)\n")
```
---
```output
{"p": {"P": 3}}
{"s": [1, 2, 3]}
TypeError Object of type P is not JSON serializable
ValueError Out of range float values are not JSON compliant: nan
TypeError keys must be str, int, float, bool or None, not tuple
{"ok": 1}
ValueError Circular reference detected
```

### loads reads each kind of value, with its hooks

```python
(python-run "import json\nprint(ascii(json.loads('{\"a\": [1, 2.5, -3e2, null, true, false], \"b\": \"\\\\u00e9\\\\ud83d\\\\ude00\\\\n\"}')))\nprint(json.loads(' [1,2] '), json.loads('\"x\"'), json.loads('-0'), json.loads('1E400'))\nprint(json.loads('[NaN, Infinity, -Infinity]'), json.loads('{\"a\": 1, \"a\": 2}'))\nprint(json.loads('{\"a\": 1, \"b\": [2]}', object_pairs_hook=list))\nprint(json.loads('{\"a\": 1}', object_hook=lambda d: sorted(d.items())))\nprint(json.loads('[1.5, 2]', parse_float=str, parse_int=lambda s: int(s) * 10))\nprint(json.loads('\"a\\tb\"', strict=False) == \"a\\tb\")\nprint(ascii(json.loads(b'[1, \"\\xc3\\xa9\"]')), json.loads(bytearray(b'{\"x\": [true]}')))\nd = json.JSONDecoder()\nprint(d.raw_decode('{\"a\": 1} trailing'), d.decode('  [] '))\n")
```
---
```output
{'a': [1, 2.5, -300.0, None, True, False], 'b': '\xe9\U0001f600\n'}
[1, 2] x 0 inf
[nan, inf, -inf] {'a': 2}
[('a', 1), ('b', [2])]
[('a', 1)]
['1.5', 20]
True
[1, '\xe9'] {'x': [True]}
({'a': 1}, 8) []
```

### JSONDecodeError says where a document went wrong

```python
(python-run "import json\ndocs = ['', '[1,]', '{\"a\" 1}', '{\"a\": 1,}', '[1 2]', '{1: 2}', '\"abc', '\"\\\\x\"', '\"\\\\u12\"', '[1]x', 'nul', '\"a\\x01\"', '{\"a\":\\n  [1,\\n   ?]}', '\\ufeff[]']\nfor doc in docs:\n    try:\n        json.loads(doc)\n    except json.JSONDecodeError as e:\n        print(ascii(doc), \"|\", e, \"|\", e.msg, e.pos, e.lineno, e.colno)\nprint(issubclass(json.JSONDecodeError, ValueError))\ntry:\n    json.loads(5)\nexcept TypeError as e:\n    print(\"TypeError\", e)\n")
```
---
```output
'' | Expecting value: line 1 column 1 (char 0) | Expecting value 0 1 1
'[1,]' | Illegal trailing comma before end of array: line 1 column 3 (char 2) | Illegal trailing comma before end of array 2 1 3
'{"a" 1}' | Expecting ':' delimiter: line 1 column 6 (char 5) | Expecting ':' delimiter 5 1 6
'{"a": 1,}' | Illegal trailing comma before end of object: line 1 column 8 (char 7) | Illegal trailing comma before end of object 7 1 8
'[1 2]' | Expecting ',' delimiter: line 1 column 4 (char 3) | Expecting ',' delimiter 3 1 4
'{1: 2}' | Expecting property name enclosed in double quotes: line 1 column 2 (char 1) | Expecting property name enclosed in double quotes 1 1 2
'"abc' | Unterminated string starting at: line 1 column 1 (char 0) | Unterminated string starting at 0 1 1
'"\\x"' | Invalid \escape: line 1 column 2 (char 1) | Invalid \escape 1 1 2
'"\\u12"' | Invalid \uXXXX escape: line 1 column 3 (char 2) | Invalid \uXXXX escape 2 1 3
'[1]x' | Extra data: line 1 column 4 (char 3) | Extra data 3 1 4
'nul' | Expecting value: line 1 column 1 (char 0) | Expecting value 0 1 1
'"a\x01"' | Invalid control character at: line 1 column 3 (char 2) | Invalid control character at 2 1 3
'{"a":\n  [1,\n   ?]}' | Expecting value: line 3 column 4 (char 15) | Expecting value 15 3 4
'\ufeff[]' | Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0) | Unexpected UTF-8 BOM (decode using utf-8-sig) 0 1 1
True
TypeError the JSON object must be str, bytes or bytearray, not int
```

### dump and load on files, a round trip, and the submodules

```python
(python-run "import json, io\nbuf = io.StringIO()\njson.dump({\"a\": [1, {\"b\": None}]}, buf, indent=1)\nprint(buf.getvalue())\nprint(json.load(io.StringIO('{\"z\": [true]}')))\nv = {\"list\": [1, 2.0, \"three\", [4, {\"five\": 5}]], \"none\": None, \"nested\": {\"x\": {\"y\": {}}}}\nprint(json.loads(json.dumps(v)) == v, json.loads(json.dumps(v, indent=4)) == v)\nfrom json import decoder, encoder, scanner\nprint(decoder.JSONDecodeError is json.JSONDecodeError, encoder.JSONEncoder is json.JSONEncoder)\nprint(sorted(json.__all__))\n")
```
---
```output
{
 "a": [
  1,
  {
   "b": null
  }
 ]
}
{'z': [True]}
True True
True True
['JSONDecodeError', 'JSONDecoder', 'JSONEncoder', 'dump', 'dumps', 'load', 'loads']
```

### a repeated dict key is one entry, a number equals nothing else, and bytes.startswith takes a tuple

```python
(python-run "d = {\"a\": 1, \"b\": 2, \"a\": 3}\nprint(d, len(d), list(d))\nprint({1: \"int\", 2.5: \"float\", True: \"t\", None: \"n\"}, {True: \"t\", 1: \"int\"})\nprint(dict([(\"x\", 1), (\"y\", 2), (\"x\", 3)]), dict([(0, \"zero\"), (False, \"f\")]))\nprint(b\"abc\".startswith((b\"x\", b\"ab\")), b\"abc\".endswith((b\"c\",)), b\"abc\".startswith(()), b\"abc\".startswith((b\"b\",), 1))\ntry:\n    b\"abc\".startswith((\"a\",))\nexcept TypeError as e:\n    print(\"TypeError\")\nprint(2.5 == None, None == 2.5, 1 == None, 0 == False, 1.0 == True, 2.5 != None, [2.5] == [None])\n")
```
---
```output
{'a': 3, 'b': 2} 2 ['a', 'b']
{1: 't', 2.5: 'float', None: 'n'} {True: 'int'}
{'x': 3, 'y': 2} {0: 'f'}
True True False True
TypeError
False False False True True True False
```
