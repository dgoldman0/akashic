"""Read Forth source the way KDOS reads it.

KDOS evaluates a source file one line at a time, and these rules come from
MegaPad's ``bios.asm``:

- tokens are separated by ASCII spaces only (``parse_word``), so a tab is
  part of a token;
- any token that begins with a backslash ends the line (the evaluator tests
  the first byte of every token before looking it up);
- ``(`` is a word of its own: it skips to the matching ``)``, counting nested
  parentheses, and stops at the end of the line when none matches
  (``w_paren``), so a parenthesized comment never spans lines;
- ``S"``, ``."`` and ``ABORT"`` skip one delimiter and take text up to the
  next double quote or the end of the line (``w_squote``);
- a word that takes a name, such as ``:`` or ``'``, takes the next token on
  the same line.
"""

from __future__ import annotations

import re


class LineCursor:
    """One source line and the position the interpreter has reached in it."""

    __slots__ = ("text", "number", "pos")

    def __init__(self, text: str, number: int) -> None:
        self.text = text
        self.number = number
        self.pos = 0

    def token(self) -> str | None:
        """The next space-delimited token, or None at the end of the line."""
        text = self.text
        end = len(text)
        pos = self.pos
        while pos < end and text[pos] == " ":
            pos += 1
        if pos >= end:
            self.pos = end
            return None
        start = pos
        while pos < end and text[pos] != " ":
            pos += 1
        self.pos = pos
        return text[start:pos]

    def paren(self) -> str:
        """Skip a ``(`` comment and return its text, nesting as BIOS does."""
        return self.paren_closed()[0]

    def paren_closed(self) -> tuple[str, bool]:
        """A ``(`` comment's text, and whether a matching ``)`` closed it."""
        text = self.text
        end = len(text)
        pos = self.pos
        start = pos
        depth = 1
        while pos < end:
            char = text[pos]
            pos += 1
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    self.pos = pos
                    return text[start : pos - 1], True
        self.pos = end
        return text[start:end], False

    def quoted(self) -> str:
        """Take a string after ``S"`` and its kin: one delimiter, then to ``"``."""
        text = self.text
        end = len(text)
        pos = self.pos + 1
        start = min(pos, end)
        while pos < end and text[pos] != '"':
            pos += 1
        self.pos = min(pos + 1, end)
        return text[start:min(pos, end)]

    def rest(self) -> str:
        """Skip the rest of the line, as a backslash comment does."""
        remainder = self.text[self.pos :]
        self.pos = len(self.text)
        return remainder


def lines(text: str):
    """Yield a cursor for each line, as FSLOAD splits on LF and drops CR."""
    for number, line in enumerate(text.split("\n"), 1):
        if line.endswith("\r"):
            line = line[:-1]
        yield LineCursor(line, number)


_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
_HEX_RE = re.compile(r"-?0[xX][0-9A-Fa-f]+\Z")


def parse_number(token: str, base: int) -> int | None:
    """The value of ``token`` as BIOS ``parse_number`` reads it, or None.

    An optional minus sign comes first, then either ``0x``/``0X`` and hex
    digits or digits in the current base.  Values wrap to 64 bits.
    """
    if not token:
        return None
    text = token
    negative = False
    if text[0] == "-":
        negative = True
        text = text[1:]
        if not text:
            return None
    if len(text) > 2 and text[0] == "0" and text[1] in "xX":
        digits = text[2:]
        radix = 16
    else:
        digits = text
        radix = base
    value = 0
    for char in digits.upper():
        digit = _DIGITS.find(char)
        if digit < 0 or digit >= radix:
            return None
        value = value * radix + digit
    if negative:
        value = -value
    return wrap(value)


def wrap(value: int) -> int:
    """A Python integer reduced to a signed 64-bit cell."""
    value &= (1 << 64) - 1
    if value >= 1 << 63:
        value -= 1 << 64
    return value
