#!/usr/bin/env python3
"""Applets change files only through the places they are given.

Ownership of a file follows from what each applet is granted
(docs/utils/fs/places.md, "Who may write a file"): an applet's place set
holds the places its descriptor says it needs, and the PLACE- words
refuse a change outside a writable grant.  A word that creates, removes
or renames an entry by its path on a volume, or binds a store's file by
a path on a volume, goes around that check, so no applet module names
one.  An applet writes through a place word, a replacement bound with
PLACE-VREPL!, a copy with PLACE-COPY or PLACE-MOVE, or a file that a
place word opened, whose grant the open checked.

Streams' and Library's stores still keep root-absolute layouts on their
home's volume until slice 7 binds each store's folder in its home; those
files are named below and leave the list then.  KDOS names ignore case,
so the check does too, and it reads code, not comments.
"""

from __future__ import annotations

import re
from pathlib import Path

APPLETS = Path(__file__).resolve().parents[1] / "akashic" / "tui" / "applets"

# Words that change an entry by its path on a volume, or bind a store's
# file on a volume, without asking a place.
PATH_WRITES = re.compile(
    r"(?<![A-Za-z0-9_?!@$./-])"
    r"(?:VFS-MKDIR\??|VFS-MKFILE\??|VFS-CREATE|VFS-RM|VFS-RENAME|VFS-RN-[A-Z-]+"
    r"|VFS-SYMLINK|VFS-LINK|VFS-UNLINK|VFS-SETATTR|VFS-SETXATTR"
    r"|VFS-REMOVEXATTR|VFS-COPY|VFS-MOVE|VREPL-INIT|VFSNAP-INIT(?:-AT)?)"
    r"(?![A-Za-z0-9_?!@$./-])",
    re.IGNORECASE,
)

# Until slice 7 binds each store's folder in its home.
UNTIL_SLICE_7 = {
    "library/repository.f",
    "streams/repository.f",
    "streams/draft-store.f",
    "streams/observation-store.f",
    "streams/source-store.f",
}

_LINE_COMMENT = re.compile(r"(?:^|\s)\\(?:\s.*)?$")
_STACK_COMMENT = re.compile(r"(?:^|\s)\(\s[^)]*\)")


def code_of(line: str) -> str:
    """LINE without its Forth comments."""

    return _STACK_COMMENT.sub(" ", _LINE_COMMENT.sub("", line))


def path_writes(text: str) -> list[tuple[int, str]]:
    """The lines of TEXT whose code names a path-level write, from 1."""

    return [
        (number, line.strip())
        for number, line in enumerate(text.splitlines(), start=1)
        if PATH_WRITES.search(code_of(line))
    ]


def test_the_pattern_reads_code_and_whole_names() -> None:
    assert path_writes("S\" x\" vfs VFS-MKDIR") == [(1, "S\" x\" vfs VFS-MKDIR")]
    assert path_writes("a u v vfs-rn-noreplace") == [(1, "a u v vfs-rn-noreplace")]
    assert path_writes("vfs r VREPL-INIT") == [(1, "vfs r VREPL-INIT")]
    assert path_writes("\\ VFS-RM would bypass the place") == []
    assert path_writes(": W  ( a u -- ) \\ not VFS-CREATE") == []
    assert path_writes("( VFS-RENAME ) PLACE-RENAME") == []
    assert path_writes("PLACE-RM PLACE-VREPL! VFS-WRITE VFS-TRUNCATE") == []
    assert path_writes("_VFS-RM-BODY MY-VFS-CREATE VFS-MKDIR-HELPER") == []
    assert path_writes("REQUIRE ../../../utils/fs/vfs-copy.f") == []


def test_applets_write_only_through_their_places() -> None:
    files = sorted(APPLETS.rglob("*.f"))
    assert files, APPLETS
    found = [
        f"{path.relative_to(APPLETS)}:{number}: {line}"
        for path in files
        if path.relative_to(APPLETS).as_posix() not in UNTIL_SLICE_7
        for number, line in path_writes(path.read_text(encoding="utf-8"))
    ]
    assert not found, "\n".join(found)


def test_each_file_waiting_for_slice_7_still_needs_its_exception() -> None:
    stale = [
        name for name in sorted(UNTIL_SLICE_7)
        if not path_writes((APPLETS / name).read_text(encoding="utf-8"))
    ]
    assert not stale, stale
