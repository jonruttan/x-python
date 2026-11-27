# codecs in files: utf-16, utf-32 and utf-8-sig through open()

`lib/python/io.x`. Each expected output is a python3.14 run of the same
program, all ASCII.

### a file written in a BOM codec has one BOM, at its first byte, and reads back

```python
(python-run "p = \"/tmp/x-python-d14-codecs.txt\"\ndef raw():\n    with open(p, 'rb') as f:\n        return f.read()\nfor enc in ('utf-16', 'utf-32', 'utf-8-sig', 'utf-16-be', 'utf-32-le'):\n    with open(p, 'w', encoding=enc) as f:\n        f.write('')\n        f.write('ab')\n        f.write(chr(0x1f600))\n    print(enc, raw())\n    with open(p, 'a', encoding=enc) as f:\n        f.write('c')\n    print(raw())\n    with open(p, 'w+', encoding=enc) as f:\n        f.write('xy')\n        f.seek(0)\n        f.write('z')\n        f.seek(0)\n        print(ascii(f.read()))\n    print(raw())\n    with open(p, encoding=enc) as f:\n        print(ascii(f.read(1)), ascii(f.read(1)), ascii(f.read()))\nwith open(p, 'w', encoding='utf-16') as f:\n    f.write('')\nprint(raw())\nwith open(p, 'a', encoding='utf-16') as f:\n    f.write('q')\nprint(raw())\n")
```
---
```output
utf-16 b'\xff\xfea\x00b\x00=\xd8\x00\xde'
b'\xff\xfea\x00b\x00=\xd8\x00\xdec\x00'
'zy'
b'\xff\xfez\x00y\x00'
'z' 'y' ''
utf-32 b'\xff\xfe\x00\x00a\x00\x00\x00b\x00\x00\x00\x00\xf6\x01\x00'
b'\xff\xfe\x00\x00a\x00\x00\x00b\x00\x00\x00\x00\xf6\x01\x00c\x00\x00\x00'
'zy'
b'\xff\xfe\x00\x00z\x00\x00\x00y\x00\x00\x00'
'z' 'y' ''
utf-8-sig b'\xef\xbb\xbfab\xf0\x9f\x98\x80'
b'\xef\xbb\xbfab\xf0\x9f\x98\x80c'
'zy'
b'\xef\xbb\xbfzy'
'z' 'y' ''
utf-16-be b'\x00a\x00b\xd8=\xde\x00'
b'\x00a\x00b\xd8=\xde\x00\x00c'
'zy'
b'\x00z\x00y'
'z' 'y' ''
utf-32-le b'a\x00\x00\x00b\x00\x00\x00\x00\xf6\x01\x00'
b'a\x00\x00\x00b\x00\x00\x00\x00\xf6\x01\x00c\x00\x00\x00'
'zy'
b'z\x00\x00\x00y\x00\x00\x00'
'z' 'y' ''
b'\xff\xfe'
b'\xff\xfeq\x00'
```

### reading a file: the BOM settles the byte order, and a utf-16 or utf-32 stream with none is refused

```python
(python-run "p = \"/tmp/x-python-d14-codecs.txt\"\ndef read(data, enc, err='strict'):\n    with open(p, 'wb') as f:\n        f.write(data)\n    try:\n        with open(p, encoding=enc, errors=err) as f:\n            print(ascii(f.read()))\n    except UnicodeError as e:\n        print(type(e).__name__, e)\nfor d in (b'', b'h', b'h\\x00', b'h\\x00\\x00', b'h\\x00\\x00\\x00', b'\\xff\\xfe', b'\\xff\\xfeh', b'\\xfe\\xff\\x00h\\x00i', b'\\x00\\x00\\xfe\\xff\\x00\\x00\\x00h'):\n    for enc in ('utf-16', 'utf-32', 'utf-16-le'):\n        print(d, enc, end=' ')\n        read(d, enc)\nread(b'h\\x00i\\x00', 'utf-16', 'replace')\nread(b'\\xff\\xfe\\x00\\xd8h\\x00', 'utf-16', 'replace')\nread(b'\\xef\\xbb', 'utf-8-sig')\nread(b'\\xef', 'utf-8-sig')\nread(b'\\xef\\xbb\\xbfhi\\r\\nthere', 'utf-8-sig')\nread(b'hi', 'utf-8-sig')\nread(b'\\xef\\xbb\\xbf\\xef\\xbb\\xbfhi', 'utf-8-sig')\n")
```
---
```output
b'' utf-16 ''
b'' utf-32 ''
b'' utf-16-le ''
b'h' utf-16 UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x68 in position 0: truncated data
b'h' utf-32 UnicodeDecodeError 'utf-32-le' codec can't decode byte 0x68 in position 0: truncated data
b'h' utf-16-le UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x68 in position 0: truncated data
b'h\x00' utf-16 UnicodeDecodeError 'utf-16' codec can't decode bytes in position 0-1: Stream does not start with BOM
b'h\x00' utf-32 UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-1: truncated data
b'h\x00' utf-16-le 'h'
b'h\x00\x00' utf-16 UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x00 in position 2: truncated data
b'h\x00\x00' utf-32 UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-2: truncated data
b'h\x00\x00' utf-16-le UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x00 in position 2: truncated data
b'h\x00\x00\x00' utf-16 UnicodeDecodeError 'utf-16' codec can't decode bytes in position 0-1: Stream does not start with BOM
b'h\x00\x00\x00' utf-32 UnicodeDecodeError 'utf-32' codec can't decode bytes in position 0-3: Stream does not start with BOM
b'h\x00\x00\x00' utf-16-le 'h\x00'
b'\xff\xfe' utf-16 ''
b'\xff\xfe' utf-32 UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-1: truncated data
b'\xff\xfe' utf-16-le '\ufeff'
b'\xff\xfeh' utf-16 UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x68 in position 2: truncated data
b'\xff\xfeh' utf-32 UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-2: truncated data
b'\xff\xfeh' utf-16-le UnicodeDecodeError 'utf-16-le' codec can't decode byte 0x68 in position 2: truncated data
b'\xfe\xff\x00h\x00i' utf-16 'hi'
b'\xfe\xff\x00h\x00i' utf-32 UnicodeDecodeError 'utf-32-le' codec can't decode bytes in position 0-3: code point not in range(0x110000)
b'\xfe\xff\x00h\x00i' utf-16-le '\ufffe\u6800\u6900'
b'\x00\x00\xfe\xff\x00\x00\x00h' utf-16 UnicodeDecodeError 'utf-16' codec can't decode bytes in position 0-1: Stream does not start with BOM
b'\x00\x00\xfe\xff\x00\x00\x00h' utf-32 'h'
b'\x00\x00\xfe\xff\x00\x00\x00h' utf-16-le '\x00\ufffe\x00\u6800'
UnicodeDecodeError 'utf-16' codec can't decode bytes in position 0-1: Stream does not start with BOM
'\ufffdh'
''
''
'hi\nthere'
'hi'
'\ufeffhi'
```

### a character split between two reads, newlines, seek, and surrogates in a file

```python
(python-run "p = \"/tmp/x-python-d14-codecs.txt\"\nfor name, enc, n in (('long-utf16.txt', 'utf-16', 4094), ('long-utf16be.txt', 'utf-16-be', 4095), ('long-utf8sig.txt', 'utf-8-sig', 8188)):\n    q = \"tests/modules/data/\" + name\n    with open(q, encoding=enc) as f:\n        t = f.read()\n    print(enc, len(t), ascii(t[n - 2:n + 4]), ascii(t[-6:]))\n    with open(q, encoding=enc) as f:\n        print([len(line) for line in f])\n    with open(q, encoding=enc, newline='') as f:\n        print(ascii(f.readlines()[-2:]))\n        f.seek(0)\n        print(ascii(f.read(3)))\nwith open(p, 'w', encoding='utf-16-le', newline='\\r\\n') as f:\n    f.write('x\\ny\\n')\nwith open(p, 'rb') as f:\n    print(f.read())\nwith open(p, 'w', encoding='utf-16') as f:\n    try:\n        f.write('a' + chr(0xd800))\n    except UnicodeError as e:\n        print(type(e).__name__, e)\nwith open(p, 'w', encoding='utf-16', errors='surrogatepass') as f:\n    f.write('a' + chr(0xd800))\nwith open(p, 'rb') as f:\n    print(f.read())\nwith open(p, encoding='utf-16', errors='surrogatepass') as f:\n    print(ascii(f.read()))\n")
```
---
```output
utf-16 4108 'aa\U0001f600\xe9b\n' 'c\nb\nc\n'
[4098, 2, 2, 2, 2, 2]
['b\r\n', 'c\n']
'aaa'
utf-16-be 4109 'aa\U0001f600\xe9b\n' 'c\nb\nc\n'
[4099, 2, 2, 2, 2, 2]
['b\r\n', 'c\n']
'aaa'
utf-8-sig 8202 'aa\U0001f600\xe9b\n' 'c\nb\nc\n'
[8192, 2, 2, 2, 2, 2]
['b\r\n', 'c\n']
'aaa'
b'x\x00\r\x00\n\x00y\x00\r\x00\n\x00'
UnicodeEncodeError 'utf-16' codec can't encode character '\ud800' in position 1: surrogates not allowed
b'\xff\xfea\x00\x00\xd8'
'a\ud800'
```
