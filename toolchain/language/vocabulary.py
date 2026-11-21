"""The base vocabulary: MegaPad's BIOS words and their documented effects.

The BIOS dictionary itself, every name with its IMMEDIATE flag, is read from
the entries in ``bios.asm``.  Effects come from the word tables in
``docs/BIOS-DICTIONARY.md``.  KDOS and MegaPad's other system modules are
read afterwards as Forth source, and their words take the effects their
stack comments declare (``checker.Checker.load_base``).

Four standard words that the dictionary document does not tabulate get their
ANS effects here, since Akashic calls them often: ``2!``, ``2@``, ``ON`` and
``CMOVE>``.  Every other undocumented BIOS word has no effect, and a
definition that calls one is reported as calling a word of unknown effect.

The document and KDOS's comments name cells informally, and the checker
reads no kind from a name, so the kinds of the base words that take or
return addresses, spans, characters and flags are declared here in Uroko's
form (``BASE_DECLARATIONS``).  Each keeps the shape of its given effect;
the checker refuses one that does not.  The primitives with exact rules,
such as ``@``, ``!`` and the comparisons, carry their kinds in the checker.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_ENTRY_FLAGS_RE = re.compile(r"\s*\.db\s+(0x[0-9A-Fa-f]+|\d+)")
_ENTRY_NAME_RE = re.compile(r'\s*\.ascii\s+"(.*)"\s*(;.*)?$')
_TABLE_WORD_RE = re.compile(r"`(.+?)`\Z")

ANS_SUPPLEMENT = {
    "2!": "( x1 x2 addr -- )",
    "2@": "( addr -- x1 x2 )",
    "ON": "( addr -- )",
    "CMOVE>": "( src dst u -- )",
}

BASE_DECLARATIONS = {
    # BIOS
    "FILL": "( a: addr u: u c: char -- )",
    "MOVE": "( src: addr dst: addr u: u -- )",
    "CMOVE": "( src: addr dst: addr u: u -- )",
    "CMOVE>": "( src: addr dst: addr u: u -- )",
    "COMPARE": "( s1: span s2: span -- n: n )",
    "TYPE": "( s: span -- )",
    "ACCEPT": "( buf: span -- n: u )",
    "COUNT": "( a: addr -- s: span )",
    "SOURCE": "( -- s: span )",
    "HERE": "( -- a: addr )",
    "ALLOT": "( n: n -- )",
    "OFF": "( a: addr -- )",
    "ON": "( a: addr -- )",
    "2@": "( a: addr -- x1 x2 )",
    "EMIT": "( c: char -- )",
    "KEY": "( -- c: char )",
    "WITHIN": "( n: n lo: n hi: n -- f: flag )",
    # KDOS
    "ALLOCATE": "( u: u -- a: addr ior: n )",
    "FREE": "( a: addr -- )",
    "RESIZE": "( a1: addr u: u -- a2: addr ior: n )",
}


@dataclass(frozen=True)
class BiosWord:
    name: str
    immediate: bool
    effect_text: str | None


def bios_words(megapad_root: Path) -> dict[str, BiosWord]:
    """Every BIOS dictionary entry, keyed by its uppercased name."""
    asm = (megapad_root / "bios.asm").read_text(encoding="utf-8", errors="replace")
    lines = asm.split("\n")
    flags_by_name: dict[str, int] = {}
    for index in range(1, len(lines) - 1):
        if ".dq" not in lines[index - 1]:
            continue
        flags_match = _ENTRY_FLAGS_RE.match(lines[index])
        if not flags_match:
            continue
        name_match = _ENTRY_NAME_RE.match(lines[index + 1])
        if not name_match:
            continue
        name = name_match.group(1).replace('\\"', '"').replace("\\\\", "\\")
        flags = int(flags_match.group(1), 0)
        if (flags & 0x7F) != len(name.encode("utf-8")):
            continue
        flags_by_name[name.upper()] = flags
    effects = documented_effects(megapad_root / "docs" / "BIOS-DICTIONARY.md")
    words = {}
    for name, flags in flags_by_name.items():
        text = effects.get(name) or ANS_SUPPLEMENT.get(name)
        words[name] = BiosWord(name, bool(flags & 0x80), text)
    return words


def documented_effects(path: Path) -> dict[str, str]:
    """Stack-effect cells of the dictionary document's word tables.

    Most tables number their words in a first column, as
    ``| 56 | `WITHIN` | `( n lo hi -- flag )` |``, and some start with the
    word, as ``| `CALLER-SPAN-STATUS` | `( addr len -- status )` |``; the
    effect is the cell after the word's.
    """
    effects: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").split("\n"):
        if not line.startswith("|") or "`" not in line:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        # A cell may itself hold an escaped bar, as in ( x -- x x \| 0 ).
        cells = _rejoin_escaped(cells)
        for index in range(min(2, len(cells) - 1)):
            match = _TABLE_WORD_RE.match(cells[index])
            if not match:
                continue
            effect = cells[index + 1].replace("\\|", "|")
            found = re.search(r"`(\(.*?\))`", effect)
            if found:
                effects.setdefault(match.group(1).upper(), found.group(1))
            break
    return effects


def _rejoin_escaped(cells: list[str]) -> list[str]:
    joined: list[str] = []
    for cell in cells:
        if joined and joined[-1].endswith("\\"):
            joined[-1] = joined[-1] + "|" + cell
        else:
            joined.append(cell)
    return joined
