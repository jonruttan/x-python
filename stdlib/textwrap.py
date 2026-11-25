"""textwrap -- wrapping and filling text.

x-python's own, written to CPython 3.14's interface: TextWrapper, wrap,
fill, shorten, dedent and indent.  CPython splits text into chunks with a
regular expression, wordsep_re, that a subclass can replace; this one
splits by hand to the same rules, so a subclass can't change them that
way.

@author [Jon Ruttan](jonruttan@gmail.com)
@copyright 2026 Jon Ruttan
@license MIT No Attribution (MIT-0)
"""

__all__ = ['TextWrapper', 'wrap', 'fill', 'dedent', 'indent', 'shorten']

# What TextWrapper treats as whitespace: ASCII's, not all of Unicode's.
_whitespace = '\t\n\x0b\x0c\r '


def _is_ws(c):
    return c in _whitespace


def _is_word(c):
    # \w: a letter, a digit or the underscore
    return c.isalnum() or c == '_'


def _is_letter(c):
    # [^\d\W]: a word character that is not a decimal digit
    return _is_word(c) and not c.isdecimal()


def _word_punct(c):
    # [\w!"'&.,?]: what may come before an em-dash
    return _is_word(c) or c in '!"\'&.,?'


def _dashes_then_word(s, j):
    # Two or more '-' at j, then a word character.
    n = len(s)
    k = j
    while k < n and s[k] == '-':
        k += 1
    return k - j >= 2 and k < n and _is_word(s[k])


def _hyphen_breaks(s, j):
    # A '-' at j that a word may break after: two letters before it, or a
    # letter, a hyphen and a letter; and a letter, maybe a hyphen, and a
    # letter after it.
    n = len(s)
    before = ((j >= 2 and _is_letter(s[j - 2]) and _is_letter(s[j - 1])) or
              (j >= 3 and _is_letter(s[j - 3]) and s[j - 2] == '-' and
               _is_letter(s[j - 1])))
    if not before:
        return False
    k = j + 1
    if k >= n or not _is_letter(s[k]):
        return False
    k += 1
    if k < n and s[k] == '-':
        if k + 1 < n and _is_letter(s[k + 1]):
            return True
    return k < n and _is_letter(s[k])


def _chunks_hyphenated(s):
    # The chunks CPython's wordsep_re makes: runs of whitespace, em-dashes
    # between words, and words, broken after the hyphens a word may break at.
    out = []
    n = len(s)
    i = 0
    while i < n:
        if _is_ws(s[i]):
            j = i + 1
            while j < n and _is_ws(s[j]):
                j += 1
        elif i > 0 and _word_punct(s[i - 1]) and _dashes_then_word(s, i):
            j = i
            while s[j] == '-':
                j += 1
        else:
            # the shortest word that ends where one of the three may end it
            j = i + 1
            while True:
                if j < n and s[j] == '-' and _hyphen_breaks(s, j):
                    j += 1
                    break
                if j >= n or _is_ws(s[j]):
                    break
                if _word_punct(s[j - 1]) and _dashes_then_word(s, j):
                    break
                j += 1
        out.append(s[i:j])
        i = j
    return out


def _chunks_simple(s):
    # runs of whitespace and runs of the rest
    out = []
    n = len(s)
    i = 0
    while i < n:
        ws = _is_ws(s[i])
        j = i + 1
        while j < n and _is_ws(s[j]) == ws:
            j += 1
        out.append(s[i:j])
        i = j
    return out


def _ends_sentence(chunk):
    # a lowercase letter, then . ! or ?, then maybe a closing quote
    if chunk[-1:] in ('"', "'"):
        chunk = chunk[:-1]
    return (len(chunk) >= 2 and chunk[-1] in '.!?' and
            'a' <= chunk[-2] <= 'z')


class TextWrapper:
    """Wraps text to a width, as wrap() and fill() do, with every option an
    attribute a program may change between calls."""

    def __init__(self, width=70, initial_indent="", subsequent_indent="",
                 expand_tabs=True, replace_whitespace=True,
                 fix_sentence_endings=False, break_long_words=True,
                 drop_whitespace=True, break_on_hyphens=True, tabsize=8,
                 *, max_lines=None, placeholder=' [...]'):
        self.width = width
        self.initial_indent = initial_indent
        self.subsequent_indent = subsequent_indent
        self.expand_tabs = expand_tabs
        self.replace_whitespace = replace_whitespace
        self.fix_sentence_endings = fix_sentence_endings
        self.break_long_words = break_long_words
        self.drop_whitespace = drop_whitespace
        self.break_on_hyphens = break_on_hyphens
        self.tabsize = tabsize
        self.max_lines = max_lines
        self.placeholder = placeholder

    # --- the pieces, each as CPython names it -------------------------------

    def _munge_whitespace(self, text):
        if self.expand_tabs:
            text = text.expandtabs(self.tabsize)
        if self.replace_whitespace:
            text = ''.join(' ' if c in _whitespace else c for c in text)
        return text

    def _split(self, text):
        if self.break_on_hyphens is True:
            return _chunks_hyphenated(text)
        return _chunks_simple(text)

    def _fix_sentence_endings(self, chunks):
        i = 0
        while i < len(chunks) - 1:
            if chunks[i + 1] == " " and _ends_sentence(chunks[i]):
                chunks[i + 1] = "  "
                i += 2
            else:
                i += 1

    def _handle_long_word(self, reversed_chunks, cur_line, cur_len, width):
        space_left = 1 if width < 1 else width - cur_len
        if self.break_long_words and space_left > 0:
            chunk = reversed_chunks[-1]
            end = space_left
            if self.break_on_hyphens and len(chunk) > space_left:
                # break after the last hyphen that fits, unless only
                # hyphens come before it
                hyphen = chunk.rfind('-', 0, space_left)
                if hyphen > 0 and chunk[:hyphen].strip('-'):
                    end = hyphen + 1
            cur_line.append(chunk[:end])
            reversed_chunks[-1] = chunk[end:]
        elif not cur_line:
            cur_line.append(reversed_chunks.pop())

    def _wrap_chunks(self, chunks):
        if self.width <= 0:
            raise ValueError("invalid width %r (must be > 0)" % self.width)
        if self.max_lines is not None:
            first = (self.subsequent_indent if self.max_lines > 1
                     else self.initial_indent)
            if len(first) + len(self.placeholder.lstrip()) > self.width:
                raise ValueError("placeholder too large for max width")
        lines = []
        chunks.reverse()
        while chunks:
            indent = self.subsequent_indent if lines else self.initial_indent
            width = self.width - len(indent)
            # a line after the first starts at a word
            if self.drop_whitespace and lines and not chunks[-1].strip():
                del chunks[-1]
            cur_line = []
            cur_len = 0
            while chunks and cur_len + len(chunks[-1]) <= width:
                cur_len += len(chunks[-1])
                cur_line.append(chunks.pop())
            if chunks and len(chunks[-1]) > width:
                self._handle_long_word(chunks, cur_line, cur_len, width)
                cur_len = sum(len(c) for c in cur_line)
            # and ends at one
            if self.drop_whitespace and cur_line and not cur_line[-1].strip():
                cur_len -= len(cur_line[-1])
                del cur_line[-1]
            if not cur_line:
                continue
            if (self.max_lines is None or len(lines) + 1 < self.max_lines or
                    ((not chunks or
                      (self.drop_whitespace and len(chunks) == 1 and
                       not chunks[0].strip())) and cur_len <= width)):
                lines.append(indent + ''.join(cur_line))
                continue
            # the last line max_lines allows: end it with the placeholder
            while cur_line:
                if (cur_line[-1].strip() and
                        cur_len + len(self.placeholder) <= width):
                    cur_line.append(self.placeholder)
                    lines.append(indent + ''.join(cur_line))
                    return lines
                cur_len -= len(cur_line[-1])
                del cur_line[-1]
            if lines:
                prev = lines[-1].rstrip()
                if len(prev) + len(self.placeholder) <= self.width:
                    lines[-1] = prev + self.placeholder
                    return lines
            lines.append(indent + self.placeholder.lstrip())
            return lines
        return lines

    def _split_chunks(self, text):
        return self._split(self._munge_whitespace(text))

    # --- the interface ----------------------------------------------------

    def wrap(self, text):
        """The lines of text wrapped to self.width, without newlines."""
        chunks = self._split_chunks(text)
        if self.fix_sentence_endings:
            self._fix_sentence_endings(chunks)
        return self._wrap_chunks(chunks)

    def fill(self, text):
        """text wrapped to self.width, as one string of lines."""
        return "\n".join(self.wrap(text))


def wrap(text, width=70, **kwargs):
    """Wrap a paragraph to lines no longer than width; answer the lines."""
    return TextWrapper(width=width, **kwargs).wrap(text)


def fill(text, width=70, **kwargs):
    """Wrap a paragraph to width; answer it as one string."""
    return TextWrapper(width=width, **kwargs).fill(text)


def shorten(text, width, **kwargs):
    """Collapse text's whitespace and cut it to fit width, ending it with
    the placeholder when words had to go."""
    w = TextWrapper(width=width, max_lines=1, **kwargs)
    return w.fill(' '.join(text.strip().split()))


def dedent(text):
    """Remove the leading whitespace every line in text shares.  Tabs and
    spaces are both whitespace but not equal; a line of only whitespace
    becomes empty and is not counted."""
    if not isinstance(text, str):
        # CPython names the type's __qualname__; a builtin's is its __name__
        raise TypeError('expected str object, not %r' % type(text).__name__)
    lines = text.split('\n')
    counted = [l for l in lines if l and not l.isspace()]
    margin = 0
    if counted:
        # the common prefix of all of them is the common prefix of the
        # least and the greatest
        lo = min(counted)
        hi = max(counted)
        while (margin < len(lo) and lo[margin] == hi[margin] and
               lo[margin] in ' \t'):
            margin += 1
    return '\n'.join('' if l.isspace() else l[margin:] for l in lines)


def indent(text, prefix, predicate=None):
    """Put prefix before each line of text that predicate accepts; without a
    predicate, before each line that is not only whitespace."""
    out = []
    for line in text.splitlines(True):
        if (not line.isspace()) if predicate is None else predicate(line):
            out.append(prefix)
        out.append(line)
    return ''.join(out)
