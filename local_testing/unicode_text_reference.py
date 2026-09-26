#!/usr/bin/env python3
"""Python reference for the shared text contract, used to check Forth code.

It implements APT-1-TEXT.md Sections 3 to 5 directly from the pinned
Unicode 15.1.0 data (through the table generator's ``Ucd``), without sharing
any code with the Forth modules it checks.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from generate_unicode_text_tables import DEFAULT_UCD, Ucd, ucd_file


@lru_cache(maxsize=1)
def ucd(root: Path = DEFAULT_UCD) -> Ucd:
    return Ucd(root)


def ucd_path(name: str, root: Path = DEFAULT_UCD) -> Path:
    """Return a pinned UCD file (hash-checked), such as a conformance file."""

    return ucd_file(root, name)


def _is_break(data: Ucd, state: dict, cp: int) -> bool:
    cur = data.grapheme[cp]
    prev = state["prev"]
    if prev is None:
        result = True
    elif prev == "CR" and cur == "LF":
        result = False
    elif prev in ("Control", "CR", "LF") or cur in ("Control", "CR", "LF"):
        result = True
    elif prev == "L" and cur in ("L", "V", "LV", "LVT"):
        result = False
    elif prev in ("LV", "V") and cur in ("V", "T"):
        result = False
    elif prev in ("LVT", "T") and cur == "T":
        result = False
    elif cur in ("Extend", "ZWJ", "SpacingMark") or prev == "Prepend":
        result = False
    elif data.incb[cp] == "Consonant" and state["incb"] == 2:
        result = False
    elif cp in data.emoji["Extended_Pictographic"] and state["emoji"] == 2:
        result = False
    elif (prev == cur == "Regional_Indicator") and state["ri"] % 2 == 1:
        result = False
    else:
        result = True
    # Advance the state past cp.
    state["ri"] = state["ri"] + 1 if cur == "Regional_Indicator" else 0
    if cp in data.emoji["Extended_Pictographic"]:
        state["emoji"] = 1
    elif state["emoji"] == 1 and cur == "Extend":
        state["emoji"] = 1
    elif state["emoji"] == 1 and cur == "ZWJ":
        state["emoji"] = 2
    else:
        state["emoji"] = 0
    incb = data.incb[cp]
    if incb == "Consonant":
        state["incb"] = 1
    elif state["incb"] and incb == "Linker":
        state["incb"] = 2
    elif state["incb"] and incb == "Extend":
        pass
    else:
        state["incb"] = 0
    state["prev"] = cur
    return result


def segment(scalars: list[int], data: Ucd | None = None) -> list[list[int]]:
    """Split scalars into extended grapheme clusters (UAX #29, 15.1.0)."""

    data = data or ucd()
    state = {"prev": None, "ri": 0, "emoji": 0, "incb": 0}
    clusters: list[list[int]] = []
    for cp in scalars:
        if _is_break(data, state, cp) or not clusters:
            clusters.append([cp])
        else:
            clusters[-1].append(cp)
    return clusters


def display_scalars(text: str | bytes, *, keep_tab: bool = False) -> list[int]:
    """Section 5: decode with maximal-subpart U+FFFD, replace Cc, Zl, Zp."""

    if isinstance(text, bytes):
        text = text.decode("utf-8", errors="replace")
    data = ucd()
    result = []
    for ch in text:
        cp = ord(ch)
        if data.general_category[cp] in ("Cc", "Zl", "Zp") and not (keep_tab and cp == 9):
            cp = 0xFFFD
        result.append(cp)
    return result


def char_width(cluster: list[int], data: Ucd | None = None) -> int:
    """Section 4, W(c)."""

    data = data or ucd()
    if all(data.default_ignorable[cp] for cp in cluster):
        return 0
    first = cluster[0]
    if len(cluster) > 1:
        second = cluster[1]
        if (data.grapheme[first] == data.grapheme[second] == "Regional_Indicator"):
            return 2
        if first in data.emoji["Emoji"] and (
            second == 0xFE0F or second in data.emoji["Emoji_Modifier"]
        ):
            return 2
    width = data.scalar_width(first)
    return width if width else 1


def characters(text: str | bytes, *, keep_tab: bool = False) -> list[list[int]]:
    return segment(display_scalars(text, keep_tab=keep_tab))


def string_width(text: str | bytes) -> int:
    return sum(char_width(cluster) for cluster in characters(text))
