#!/usr/bin/env python3
"""Every filesystem operation in Akashic names its instance.

KDOS once kept a process-wide current filesystem: VFS-USE selected an
instance, VFS-CUR read the selection back and _VFS-CUR held it, so code
that read the selection reached whichever instance another module had
selected last.  Every module now passes the instance it works on, or the
place its files belong to (docs/utils/fs/places.md), and the three words
are gone.  This check keeps them gone: no file under akashic/ names them,
in code or in a comment.  KDOS names ignore case, so neither may any
spelling of them.
"""

from __future__ import annotations

import re
from pathlib import Path

SOURCE_ROOT = Path(__file__).resolve().parents[1] / "akashic"

# A name that only starts or ends with one of the words, such as
# VFS-USERLAND, is another word.
SELECTOR_WORDS = re.compile(
    r"(?<![A-Za-z0-9_-])(?:_?VFS-CUR|VFS-USE)(?![A-Za-z0-9_-])",
    re.IGNORECASE,
)


def selector_mentions(text: str) -> list[tuple[int, str]]:
    """The lines of TEXT that name a selector word, numbered from 1."""

    return [
        (number, line.strip())
        for number, line in enumerate(text.splitlines(), start=1)
        if SELECTOR_WORDS.search(line)
    ]


def test_the_pattern_finds_each_word_and_no_longer_name() -> None:
    assert selector_mentions("vfs VFS-USE") == [(1, "vfs VFS-USE")]
    assert selector_mentions("VFS-CUR VFS-OPEN") == [(1, "VFS-CUR VFS-OPEN")]
    assert selector_mentions("0 _vfs-cur !") == [(1, "0 _vfs-cur !")]
    assert selector_mentions("\\ `VFS-USE`, then") == [(1, "\\ `VFS-USE`, then")]
    assert selector_mentions("VFS-USERLAND VFS-CURSOR MY-VFS-USE") == []


def test_no_module_names_the_selector() -> None:
    files = sorted(path for path in SOURCE_ROOT.rglob("*") if path.is_file())
    assert files, SOURCE_ROOT
    found = [
        f"{path.relative_to(SOURCE_ROOT.parent)}:{number}: {line}"
        for path in files
        for number, line in selector_mentions(
            path.read_text(encoding="utf-8", errors="replace")
        )
    ]
    assert not found, "\n".join(found)
