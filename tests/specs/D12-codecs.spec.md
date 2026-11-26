# codecs: utf-16, utf-32, utf-8-sig and surrogatepass

`lib/python/str.x`. Each expected output is a python3.14 run of the same
program, all ASCII.

### utf-16, utf-32 and utf-8-sig round trips, the BOM written, and surrogate pairs

```python
(python-run "s = 'A\\xe9€' + chr(0x1f600)\nfor enc in ('utf-16', 'utf-16-le', 'utf-16-be', 'utf-32', 'utf-32-le', 'utf-32-be', 'utf-8-sig'):\n    b = s.encode(enc)\n    print(enc, b, ascii(b.decode(enc)), b.decode(enc) == s)\nprint(''.encode('utf-16'), ''.encode('utf-32'), ''.encode('utf-8-sig'), ascii(b''.decode('utf-16')))\nprint(ascii(str(b'\\x00A\\x00B', 'utf-16-be')), bytes('AB', 'utf-32-le'))\nprint(ascii(b'\\xd8\\x3d\\xde\\x00'.decode('utf-16-be')), len(b'\\x3d\\xd8\\x00\\xde'.decode('utf-16-le')))\n")
```
---
```output
utf-16 b'\xff\xfeA\x00\xe9\x00\xac =\xd8\x00\xde' 'A\xe9\u20ac\U0001f600' True
utf-16-le b'A\x00\xe9\x00\xac =\xd8\x00\xde' 'A\xe9\u20ac\U0001f600' True
utf-16-be b'\x00A\x00\xe9 \xac\xd8=\xde\x00' 'A\xe9\u20ac\U0001f600' True
utf-32 b'\xff\xfe\x00\x00A\x00\x00\x00\xe9\x00\x00\x00\xac \x00\x00\x00\xf6\x01\x00' 'A\xe9\u20ac\U0001f600' True
utf-32-le b'A\x00\x00\x00\xe9\x00\x00\x00\xac \x00\x00\x00\xf6\x01\x00' 'A\xe9\u20ac\U0001f600' True
utf-32-be b'\x00\x00\x00A\x00\x00\x00\xe9\x00\x00 \xac\x00\x01\xf6\x00' 'A\xe9\u20ac\U0001f600' True
utf-8-sig b'\xef\xbb\xbfA\xc3\xa9\xe2\x82\xac\xf0\x9f\x98\x80' 'A\xe9\u20ac\U0001f600' True
b'\xff\xfe' b'\xff\xfe\x00\x00' b'\xef\xbb\xbf' ''
'AB' b'A\x00\x00\x00B\x00\x00\x00'
'\U0001f600' 1
```

### the BOM read and dropped, little-endian without one, and the names a codec is found by

```python
(python-run "print(ascii(b'\\xff\\xfeA\\x00'.decode('utf-16')), ascii(b'\\xfe\\xff\\x00A'.decode('utf-16')), ascii(b'A\\x00'.decode('utf-16')))\nprint(ascii(b'\\xff\\xfe\\x00\\x00A\\x00\\x00\\x00'.decode('utf-32')), ascii(b'\\x00\\x00\\xfe\\xff\\x00\\x00\\x00A'.decode('utf-32')), ascii(b'A\\x00\\x00\\x00'.decode('utf-32')))\nprint(ascii(b'\\xff\\xfe\\xff\\xfeA\\x00'.decode('utf-16')), ascii(b'\\xff\\xfeA\\x00'.decode('utf-16-le')), ascii(b'\\xfe\\xff\\x00A'.decode('utf-16-be')))\nprint(ascii(b'\\xef\\xbb\\xbfA'.decode('utf-8-sig')), ascii(b'A'.decode('utf-8-sig')), ascii(b'\\xef\\xbb\\xbf\\xef\\xbb\\xbfA'.decode('utf-8-sig')), ascii(b'\\xef\\xbb\\xbfA'.decode('utf-8')))\nfor n in ('UTF-16', 'utf_16', 'utf16', 'u16', 'UTF-16LE', 'utf_16_be', 'utf 32', 'U32', 'utf_32le', 'UTF-8-SIG', 'utf_8_sig', 'u8', 'US-ASCII', 'utf16le', 'utf8sig'):\n    try:\n        print(n, 'A'.encode(n))\n    except LookupError as e:\n        print(n, 'LookupError', e)\n")
```
---
```output
'A' 'A' 'A'
'A' 'A' 'A'
'\ufeffA' '\ufeffA' '\ufeffA'
'A' 'A' '\ufeffA' '\ufeffA'
UTF-16 b'\xff\xfeA\x00'
utf_16 b'\xff\xfeA\x00'
utf16 b'\xff\xfeA\x00'
u16 b'\xff\xfeA\x00'
UTF-16LE b'A\x00'
utf_16_be b'\x00A'
utf 32 b'\xff\xfe\x00\x00A\x00\x00\x00'
U32 b'\xff\xfe\x00\x00A\x00\x00\x00'
utf_32le b'A\x00\x00\x00'
UTF-8-SIG b'\xef\xbb\xbfA'
utf_8_sig b'\xef\xbb\xbfA'
u8 b'A'
US-ASCII b'A'
utf16le LookupError unknown encoding: utf16le
utf8sig LookupError unknown encoding: utf8sig
```

### decoding errors under strict, replace, ignore and surrogatepass

```python
(python-run "def show(f):\n    try:\n        print(ascii(f()))\n    except (UnicodeError, LookupError) as e:\n        print(type(e).__name__, e)\ncases = [(b'\\x00', 'utf-16-le'), (b'A\\x00\\x00', 'utf-16-le'), (b'\\x00\\xd8', 'utf-16-le'),\n         (b'\\x00\\xd8A', 'utf-16-le'), (b'\\x00\\xdcA\\x00', 'utf-16-le'), (b'\\xd8\\x00\\x00A', 'utf-16-be'),\n         (b'\\xff\\xfe\\x00\\xd8A\\x00', 'utf-16'), (b'\\xfe\\xff\\xdc\\x00', 'utf-16'), (b'\\xff', 'utf-16'),\n         (b'A\\x00\\x00\\x00\\x00\\xd8\\x00\\x00', 'utf-32-le'), (b'\\x00\\x11\\x00\\x00', 'utf-32-be'),\n         (b'A\\x00\\x00', 'utf-32-le'), (b'A\\x00\\x00\\x00B\\x00', 'utf-32'), (b'\\x00\\x00\\xfe\\xff\\x00\\x00\\xdf\\xff', 'utf-32'),\n         (b'\\xed\\xa0\\x80\\xed\\xbf\\xbfA', 'utf-8'), (b'\\xef\\xbb\\xbf\\xed\\xa0\\x80', 'utf-8-sig'), (b'\\xef\\xbb', 'utf-8-sig')]\nfor b, enc in cases:\n    for err in ('strict', 'replace', 'ignore', 'surrogatepass'):\n        print(enc, err, end=' ')\n        show(lambda: b.decode(enc, err))\nshow(lambda: b'\\x00'.decode('utf-16-le', 'bogus'))\nprint(ascii(b'A\\x00'.decode('utf-16-le', 'bogus')))\n")
```
---
```output
utf-16-le strict UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x00 in position 0: truncated data
utf-16-le replace '\ufffd'
utf-16-le ignore ''
utf-16-le surrogatepass UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x00 in position 0: truncated data
utf-16-le strict UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x00 in position 2: truncated data
utf-16-le replace 'A\ufffd'
utf-16-le ignore 'A'
utf-16-le surrogatepass UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x00 in position 2: truncated data
utf-16-le strict UnicodeDecodeError 'utf-16-le' codec can't decode bytes in position 0-1: unexpected end of data
utf-16-le replace '\ufffd'
utf-16-le ignore ''
utf-16-le surrogatepass '\ud800'
utf-16-le strict UnicodeDecodeError 'utf-16-le' codec can't decode bytes in position 0-2: unexpected end of data
utf-16-le replace '\ufffd'
utf-16-le ignore ''
utf-16-le surrogatepass UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x41 in position 2: truncated data
utf-16-le strict UnicodeDecodeError 'utf-16-le' codec can't decode bytes in position 0-1: illegal encoding
utf-16-le replace '\ufffdA'
utf-16-le ignore 'A'
utf-16-le surrogatepass '\udc00A'
utf-16-be strict UnicodeDecodeError 'utf-16-be' codec can't decode bytes in position 0-1: illegal UTF-16 surrogate
utf-16-be replace '\ufffdA'
utf-16-be ignore 'A'
utf-16-be surrogatepass '\ud800A'
utf-16 strict UnicodeDecodeError 'utf-16-le' codec can't decode bytes in position 2-3: illegal UTF-16 surrogate
utf-16 replace '\ufffdA'
utf-16 ignore 'A'
utf-16 surrogatepass '\ud800A'
utf-16 strict UnicodeDecodeError 'utf-16-be' codec can't decode bytes in position 2-3: illegal encoding
utf-16 replace '\ufffd'
utf-16 ignore ''
utf-16 surrogatepass '\udc00'
utf-16 strict UnicodeDecodeError 'utf-16-le' codec can't decode byte 0xff in position 0: truncated data
utf-16 replace '\ufffd'
utf-16 ignore ''
utf-16 surrogatepass UnicodeDecodeError 'utf-16-le' codec can't decode byte 0xff in position 0: truncated data
utf-32-le strict UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 4-7: code point in surrogate code point range(0xd800, 0xe000)
utf-32-le replace 'A\ufffd'
utf-32-le ignore 'A'
utf-32-le surrogatepass 'A\ud800'
utf-32-be strict UnicodeDecodeError 'utf-32-be' codec can't decode bytes in position 0-3: code point not in range(0x110000)
utf-32-be replace '\ufffd'
utf-32-be ignore ''
utf-32-be surrogatepass UnicodeDecodeError 'utf-32-be' codec can't decode bytes in position 0-3: code point not in range(0x110000)
utf-32-le strict UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-2: truncated data
utf-32-le replace '\ufffd'
utf-32-le ignore ''
utf-32-le surrogatepass UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-2: truncated data
utf-32 strict UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 4-5: truncated data
utf-32 replace 'A\ufffd'
utf-32 ignore 'A'
utf-32 surrogatepass UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 4-5: truncated data
utf-32 strict UnicodeDecodeError 'utf-32-be' codec can't decode bytes in position 4-7: code point in surrogate code point range(0xd800, 0xe000)
utf-32 replace '\ufffd'
utf-32 ignore ''
utf-32 surrogatepass '\udfff'
utf-8 strict UnicodeDecodeError 'utf-8' codec can't decode byte 0xed in position 0: invalid continuation byte
utf-8 replace '\ufffd\ufffd\ufffd\ufffd\ufffd\ufffdA'
utf-8 ignore 'A'
utf-8 surrogatepass '\ud800\udfffA'
utf-8-sig strict UnicodeDecodeError 'utf-8' codec can't decode byte 0xed in position 0: invalid continuation byte
utf-8-sig replace '\ufffd\ufffd\ufffd'
utf-8-sig ignore ''
utf-8-sig surrogatepass '\ud800'
utf-8-sig strict UnicodeDecodeError 'utf-8' codec can't decode bytes in position 0-1: unexpected end of data
utf-8-sig replace '\ufffd'
utf-8-sig ignore ''
utf-8-sig surrogatepass UnicodeDecodeError 'utf-8' codec can't decode bytes in position 0-1: unexpected end of data
LookupError unknown error handler name 'bogus'
'A'
```

### encoding errors under strict, replace, ignore and surrogatepass

```python
(python-run "def show(f):\n    try:\n        print(f())\n    except (UnicodeError, LookupError) as e:\n        print(type(e).__name__, e)\nfor s in (chr(0xd800), 'a' + chr(0xdfff) + chr(0xd800) + 'x', chr(0xd83d) + chr(0xde00)):\n    for enc in ('utf-8', 'utf-16', 'utf-16-be', 'utf-32-le', 'utf-8-sig', 'ascii'):\n        for err in ('strict', 'replace', 'ignore', 'surrogatepass'):\n            print(enc, err, end=' ')\n            show(lambda: s.encode(enc, err))\nshow(lambda: 'x'.encode('utf-16', 'bogus'))\nshow(lambda: chr(0xd800).encode('utf-16', 'bogus'))\ns = chr(0xd800) + 'a' + chr(0xdfff)\nprint(ascii(s.encode('utf-16-le', 'surrogatepass').decode('utf-16-le', 'surrogatepass')))\nprint(ascii(s.encode('utf-8', 'surrogatepass').decode('utf-8', 'surrogatepass')))\nprint(ascii(s.encode('utf-32', 'surrogatepass').decode('utf-32', 'surrogatepass')))\n")
```
---
```output
utf-8 strict UnicodeEncodeError 'utf-8' codec can't encode character '\ud800' in position 0: surrogates not allowed
utf-8 replace b'?'
utf-8 ignore b''
utf-8 surrogatepass b'\xed\xa0\x80'
utf-16 strict UnicodeEncodeError 'utf-16' codec can't encode character '\ud800' in position 0: surrogates not allowed
utf-16 replace b'\xff\xfe?\x00'
utf-16 ignore b'\xff\xfe'
utf-16 surrogatepass b'\xff\xfe\x00\xd8'
utf-16-be strict UnicodeEncodeError 'utf-16-be' codec can't encode character '\ud800' in position 0: surrogates not allowed
utf-16-be replace b'\x00?'
utf-16-be ignore b''
utf-16-be surrogatepass b'\xd8\x00'
utf-32-le strict UnicodeEncodeError 'utf-32-le' codec can't encode character '\ud800' in position 0: surrogates not allowed
utf-32-le replace b'?\x00\x00\x00'
utf-32-le ignore b''
utf-32-le surrogatepass b'\x00\xd8\x00\x00'
utf-8-sig strict UnicodeEncodeError 'utf-8' codec can't encode character '\ud800' in position 0: surrogates not allowed
utf-8-sig replace b'\xef\xbb\xbf?'
utf-8-sig ignore b'\xef\xbb\xbf'
utf-8-sig surrogatepass b'\xef\xbb\xbf\xed\xa0\x80'
ascii strict UnicodeEncodeError 'ascii' codec can't encode character '\ud800' in position 0: ordinal not in range(128)
ascii replace b'?'
ascii ignore b''
ascii surrogatepass UnicodeEncodeError 'ascii' codec can't encode character '\ud800' in position 0: ordinal not in range(128)
utf-8 strict UnicodeEncodeError 'utf-8' codec can't encode characters in position 1-2: surrogates not allowed
utf-8 replace b'a??x'
utf-8 ignore b'ax'
utf-8 surrogatepass b'a\xed\xbf\xbf\xed\xa0\x80x'
utf-16 strict UnicodeEncodeError 'utf-16' codec can't encode character '\udfff' in position 1: surrogates not allowed
utf-16 replace b'\xff\xfea\x00?\x00?\x00x\x00'
utf-16 ignore b'\xff\xfea\x00x\x00'
utf-16 surrogatepass b'\xff\xfea\x00\xff\xdf\x00\xd8x\x00'
utf-16-be strict UnicodeEncodeError 'utf-16-be' codec can't encode character '\udfff' in position 1: surrogates not allowed
utf-16-be replace b'\x00a\x00?\x00?\x00x'
utf-16-be ignore b'\x00a\x00x'
utf-16-be surrogatepass b'\x00a\xdf\xff\xd8\x00\x00x'
utf-32-le strict UnicodeEncodeError 'utf-32-le' codec can't encode character '\udfff' in position 1: surrogates not allowed
utf-32-le replace b'a\x00\x00\x00?\x00\x00\x00?\x00\x00\x00x\x00\x00\x00'
utf-32-le ignore b'a\x00\x00\x00x\x00\x00\x00'
utf-32-le surrogatepass b'a\x00\x00\x00\xff\xdf\x00\x00\x00\xd8\x00\x00x\x00\x00\x00'
utf-8-sig strict UnicodeEncodeError 'utf-8' codec can't encode characters in position 1-2: surrogates not allowed
utf-8-sig replace b'\xef\xbb\xbfa??x'
utf-8-sig ignore b'\xef\xbb\xbfax'
utf-8-sig surrogatepass b'\xef\xbb\xbfa\xed\xbf\xbf\xed\xa0\x80x'
ascii strict UnicodeEncodeError 'ascii' codec can't encode characters in position 1-2: ordinal not in range(128)
ascii replace b'a??x'
ascii ignore b'ax'
ascii surrogatepass UnicodeEncodeError 'ascii' codec can't encode characters in position 1-2: ordinal not in range(128)
utf-8 strict UnicodeEncodeError 'utf-8' codec can't encode characters in position 0-1: surrogates not allowed
utf-8 replace b'??'
utf-8 ignore b''
utf-8 surrogatepass b'\xed\xa0\xbd\xed\xb8\x80'
utf-16 strict UnicodeEncodeError 'utf-16' codec can't encode character '\ud83d' in position 0: surrogates not allowed
utf-16 replace b'\xff\xfe?\x00?\x00'
utf-16 ignore b'\xff\xfe'
utf-16 surrogatepass b'\xff\xfe=\xd8\x00\xde'
utf-16-be strict UnicodeEncodeError 'utf-16-be' codec can't encode character '\ud83d' in position 0: surrogates not allowed
utf-16-be replace b'\x00?\x00?'
utf-16-be ignore b''
utf-16-be surrogatepass b'\xd8=\xde\x00'
utf-32-le strict UnicodeEncodeError 'utf-32-le' codec can't encode character '\ud83d' in position 0: surrogates not allowed
utf-32-le replace b'?\x00\x00\x00?\x00\x00\x00'
utf-32-le ignore b''
utf-32-le surrogatepass b'=\xd8\x00\x00\x00\xde\x00\x00'
utf-8-sig strict UnicodeEncodeError 'utf-8' codec can't encode characters in position 0-1: surrogates not allowed
utf-8-sig replace b'\xef\xbb\xbf??'
utf-8-sig ignore b'\xef\xbb\xbf'
utf-8-sig surrogatepass b'\xef\xbb\xbf\xed\xa0\xbd\xed\xb8\x80'
ascii strict UnicodeEncodeError 'ascii' codec can't encode characters in position 0-1: ordinal not in range(128)
ascii replace b'??'
ascii ignore b''
ascii surrogatepass UnicodeEncodeError 'ascii' codec can't encode characters in position 0-1: ordinal not in range(128)
b'\xff\xfex\x00'
LookupError unknown error handler name 'bogus'
'\ud800a\udfff'
'\ud800a\udfff'
'\ud800a\udfff'
```

### json.loads of UTF-8, UTF-16 and UTF-32 bytes

```python
(python-run "import json\ndoc = '{\"a\": [1, \"\\xe9€\", \"' + chr(0x1f600) + '\"], \"b\": null}'\nfor enc in ('utf-8', 'utf-8-sig', 'utf-16', 'utf-16-le', 'utf-16-be', 'utf-32', 'utf-32-le', 'utf-32-be'):\n    b = doc.encode(enc)\n    print(enc, json.detect_encoding(b), ascii(json.loads(b)))\nprint(json.loads('7'.encode('utf-16-le')), json.loads('\"x\"'.encode('utf-32-be')), json.loads(bytearray('[true]'.encode('utf-16'))))\nprint(ascii(json.loads(b'\"\\x00\\x00\\xd8\"\\x00')))\n")
```
---
```output
utf-8 utf-8 {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-8-sig utf-8-sig {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-16 utf-16 {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-16-le utf-16-le {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-16-be utf-16-be {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-32 utf-32 {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-32-le utf-32-le {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
utf-32-be utf-32-be {'a': [1, '\xe9\u20ac', '\U0001f600'], 'b': None}
7 x [True]
'\ud800'
```
