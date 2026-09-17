# codecs and their error handlers

### utf-8 and ascii, strict, ignore and replace

```python
(python-run "b = b\"caf\\xc3\\xa9\"\nprint(repr(b.decode()), len(b.decode()), repr(bytearray(b).decode(\"utf-8\")))\nprint(repr(b\"\\x00a\".decode()), repr(b\"\".decode()))\nprint(repr(b\"\\xff\\xfe\".decode(\"utf-8\", \"replace\")), repr(b\"\\xff\\xfe\".decode(\"utf-8\", \"ignore\")))\nprint(repr(b\"\\xe4\\xb8\\x20\".decode(\"utf-8\", \"replace\")), repr(b\"\\xe4\\xf0\\xe4\".decode(\"utf-8\", \"replace\")))\nprint(repr(b\"\\xe4\\xb8\\x80\".decode(\"utf-8\", \"replace\")), repr(b\"\\xf0\\x9f\\x98\\x80\".decode()))\nprint(repr(b\"\\xc0\\x80\".decode(\"utf-8\", \"replace\")), repr(b\"\\xed\\xa0\\x80\".decode(\"utf-8\", \"replace\")))\nprint(repr(b\"\\xe5\\xa5\\xbd\".decode(\"ascii\", \"replace\")), repr(b\"\\xe5\\xa5\\xbd\".decode(\"ascii\", \"ignore\")))\nprint(repr(b\"\\xe5\\xa5\\xbd\".decode(\"utf-8\")), repr(b\"ab\".decode(\"us-ascii\")))\nprint(repr(b\"x\".decode(\"utf-8\", \"bogus\")))\n\ns = \"caf\" + chr(233)\nprint(repr(s.encode()), repr(s.encode(\"utf8\")), repr(s.encode(\"ascii\", \"replace\")))\nprint(repr(s.encode(\"ascii\", \"ignore\")), repr(bytes(s, \"utf-8\")), repr(bytes(\"ab\", \"ascii\")))\n\n\ndef err(f):\n    try:\n        f()\n    except (UnicodeError, LookupError, TypeError) as e:\n        print(type(e).__name__)\n\n\nerr(lambda: b\"\\xff\".decode())\nerr(lambda: b\"\\xff\".decode(\"utf-8\", \"strict\"))\nerr(lambda: str(b\"ni\\xe5\\xa5\\xbd\", \"ascii\"))\nerr(lambda: s.encode(\"ascii\"))\nerr(lambda: bytes(chr(0x1F600), \"ascii\"))\nerr(lambda: b\"x\".decode(5))\ntry:\n    b\"x\".decode(\"bogus\")\nexcept LookupError as e:\n    print(\"LookupError\", e)\ntry:\n    b\"\\xff\".decode(\"utf-8\", \"bogus\")\nexcept LookupError as e:\n    print(\"LookupError\", e)")
```
---
```output
'café' 4 'café'
'\x00a' ''
'��' ''
'� ' '���'
'一' '😀'
'��' '���'
'���' ''
'好' 'ab'
'x'
b'caf\xc3\xa9' b'caf\xc3\xa9' b'caf?'
b'caf' b'caf\xc3\xa9' b'ab'
UnicodeDecodeError
UnicodeDecodeError
UnicodeDecodeError
UnicodeEncodeError
UnicodeEncodeError
TypeError
LookupError unknown encoding: bogus
LookupError unknown error handler name 'bogus'
```
