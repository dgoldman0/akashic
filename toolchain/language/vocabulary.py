"""The base vocabulary: MegaPad's BIOS words and their documented effects.

The BIOS dictionary itself, every name with its IMMEDIATE flag, is read from
the entries in ``bios.asm``.  Effects come from the word tables in
``docs/BIOS-DICTIONARY.md``, and a BIOS word the tables omit has no effect:
a definition that calls one is reported as calling a word of unknown
effect.  KDOS and MegaPad's other system modules are read afterwards as
Forth source, and their words take the effects their stack comments declare
(``checker.Checker.load_base``).

The tables and KDOS's comments name cells informally, and the checker reads
no kind from a name.  MegaPad's ``uroko.f`` declares the kinds of the base
words in Uroko's form, one ``EFFECT NAME ( effect )`` line to a word, and
the checker reads it after KDOS as KDOS loads it.  The primitives with exact
rules, such as ``@``, ``!`` and the comparisons, carry their kinds in the
checker.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

_ENTRY_FLAGS_RE = re.compile(r"\s*\.db\s+(0x[0-9A-Fa-f]+|\d+)")
_ENTRY_NAME_RE = re.compile(r'\s*\.ascii\s+"(.*)"\s*(;.*)?$')
_TABLE_WORD_RE = re.compile(r"`(.+?)`\Z")

# MegaPad's modules that make the base vocabulary, in the order an image
# loads them: KDOS, Uroko's declarations of the BIOS and KDOS words, then
# the system modules that compile with those declarations in place.
BASE_MODULES = ("kdos.f", "uroko.f", "networking.f", "rich-terminal.f", "tools.f",
                "graphics.f")


def megapad_root(akashic_root: Path | None = None) -> Path:
    """The MegaPad checkout: ``MEGAPAD_ROOT``, else the one beside Akashic.

    A workspace links its checkouts side by side, so the MegaPad beside the
    Akashic checkout as it was reached comes first, then the one beside the
    folder a link to it resolves to.
    """
    configured = os.environ.get("MEGAPAD_ROOT")
    if configured:
        return Path(configured)
    here = akashic_root or Path(__file__).absolute().parents[2]
    for candidate in (here.parent / "megapad", here.resolve().parent / "megapad"):
        if (candidate / "kdos.f").is_file():
            return candidate
    return here.parent / "megapad"


def base_module_paths(megapad: Path, modules: tuple[str, ...] = BASE_MODULES) -> list[Path]:
    """The base modules' files, or an error naming the first one missing."""
    paths = [megapad / module for module in modules]
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(
                f"{path} is missing: the checker needs a MegaPad checkout that has it "
                "(set MEGAPAD_ROOT)")
    return paths


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
        words[name] = BiosWord(name, bool(flags & 0x80), effects.get(name))
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
