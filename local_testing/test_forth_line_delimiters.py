#!/usr/bin/env python3
"""Every comment and string in an Akashic module closes on its own line.

KDOS evaluates source one line at a time, at the console and in the module
loader alike.  The BIOS parsers for ``(`` and ``.(`` and the string words stop
at the end of the line, so a comment split across two lines leaves its second
line to be interpreted as code.  A definition then breaks part way and the
rest of its body runs at the prompt.
"""

from __future__ import annotations

from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parents[1] / "akashic"

# Words that take the next token literally, so a following "(" is data.
_LITERAL_NEXT = frozenset(("CHAR", "[CHAR]", "'", "[']", "POSTPONE", "[COMPILE]"))
# Parsing words and the character that ends their text.
_STRING_WORDS = {'."': '"', 'S"': '"', 'C"': '"', 'ABORT"': '"', ".(": ")"}


def _tokens(line: str):
    """Yield (token, end) pairs; MegaPad separates tokens on ASCII spaces."""

    index = 0
    while True:
        while index < len(line) and line[index] == " ":
            index += 1
        if index >= len(line):
            return
        end = line.find(" ", index)
        end = len(line) if end < 0 else end
        yield line[index:end], end
        index = end


def unclosed_delimiter(line: str) -> str | None:
    """The parsing word whose text runs past the end of this line, if any."""

    index = 0
    literal_next = False
    while index < len(line):
        token, end = next(_tokens(line[index:]), (None, 0))
        if token is None:
            return None
        end += index
        if literal_next:
            literal_next = False
        elif token.startswith("\\"):
            return None
        elif token in _LITERAL_NEXT:
            literal_next = True
        elif token == "(":
            depth = 1
            position = end + 1
            while position < len(line) and depth:
                if line[position] == "(":
                    depth += 1
                elif line[position] == ")":
                    depth -= 1
                position += 1
            if depth:
                return token
            end = position
        elif token in _STRING_WORDS:
            close = line.find(_STRING_WORDS[token], end + 1)
            if close < 0:
                return token
            end = close + 1
        index = end
    return None


def violations(text: str) -> list[tuple[int, str]]:
    return [
        (number, line.strip())
        for number, line in enumerate(text.splitlines(), 1)
        if unclosed_delimiter(line)
    ]


def test_the_checker_finds_split_comments_and_strings() -> None:
    assert unclosed_delimiter("  ( worker-xt in-a in-u") == "("
    assert unclosed_delimiter(': X ( a -- b ) DUP ;') is None
    assert unclosed_delimiter(": X ( a ( nested ) -- b ) ;") is None
    assert unclosed_delimiter(": X ( a ( nested -- b ) ;") == "("
    assert unclosed_delimiter("DUP [CHAR] ( = IF") is None
    assert unclosed_delimiter("' ( EXECUTE") is None
    assert unclosed_delimiter('." open string') == '."'
    assert unclosed_delimiter('S" a ( b" TYPE') is None
    assert unclosed_delimiter(".( note") == ".("
    assert unclosed_delimiter("\\ ( a comment that never closes") is None
    assert unclosed_delimiter("1 2 + \\ trailing ( note") is None


def test_every_module_closes_its_comments_and_strings_on_one_line() -> None:
    found = {
        str(path.relative_to(SOURCE_ROOT)): problems
        for path in sorted(SOURCE_ROOT.rglob("*.f"))
        if (problems := violations(path.read_text(encoding="utf-8", errors="replace")))
    }
    assert found == {}
