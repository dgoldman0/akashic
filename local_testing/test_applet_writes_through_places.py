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

Streams' and Library's stores keep layouts of several files of their
own.  Their holder binds its home's folder through the place once when
it opens (PFOLDER-BIND, utils/fs/place-folder.f), for writing only where
the place is writable, and hands the store that folder or a path
composed under it; the store writes by path inside it, as the
persistence and replacement libraries below it take an instance and a
path.  Those store modules are named below.  The repositories spell no
path from the volume's root, and no other applet module opens one of
Streams' stores at its default in the volume's root.  KDOS names ignore
case, so the checks do too, and they read code, not comments.
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

# Stores that keep a layout of their own under the folder their holder
# binds, and write by path inside it.
LAYOUT_STORES = {
    "library/repository.f",
    "streams/repository.f",
    "streams/draft-store.f",
    "streams/observation-store.f",
    "streams/source-store.f",
}

# The repositories, which compose every path of their layout under the
# folder they are given.
REPOSITORIES = ("library/repository.f", "streams/repository.f")

# A Streams store's default in the volume's root: the plain INIT and the
# target it opens.
ROOT_DEFAULTS = re.compile(
    r"(?<![A-Za-z0-9_?!@$./-])"
    r"STREAMS-(?:DRAFT|SOURCE|OBSERVATION)-STORE-(?:INIT|TARGET\$)"
    r"(?![A-Za-z0-9_?!@$./-])",
    re.IGNORECASE,
)

# A string literal that starts at a volume's root.
ROOT_LITERAL = re.compile(r'(?<![A-Za-z0-9_?!@$./-])S"\s+/')

_LINE_COMMENT = re.compile(r"(?:^|\s)\\(?:\s.*)?$")
_STACK_COMMENT = re.compile(r"(?:^|\s)\(\s[^)]*\)")


def code_of(line: str) -> str:
    """LINE without its Forth comments."""

    return _STACK_COMMENT.sub(" ", _LINE_COMMENT.sub("", line))


def lines_naming(pattern: re.Pattern[str], text: str) -> list[tuple[int, str]]:
    """The lines of TEXT whose code matches PATTERN, from 1."""

    return [
        (number, line.strip())
        for number, line in enumerate(text.splitlines(), start=1)
        if pattern.search(code_of(line))
    ]


def path_writes(text: str) -> list[tuple[int, str]]:
    """The lines of TEXT whose code names a path-level write, from 1."""

    return lines_naming(PATH_WRITES, text)


def _applet_modules() -> list[tuple[str, str]]:
    files = sorted(APPLETS.rglob("*.f"))
    assert files, APPLETS
    return [
        (path.relative_to(APPLETS).as_posix(), path.read_text(encoding="utf-8"))
        for path in files
    ]


def test_the_patterns_read_code_and_whole_names() -> None:
    assert path_writes("S\" x\" vfs VFS-MKDIR") == [(1, "S\" x\" vfs VFS-MKDIR")]
    assert path_writes("a u v vfs-rn-noreplace") == [(1, "a u v vfs-rn-noreplace")]
    assert path_writes("vfs r VREPL-INIT") == [(1, "vfs r VREPL-INIT")]
    assert path_writes("\\ VFS-RM would bypass the place") == []
    assert path_writes(": W  ( a u -- ) \\ not VFS-CREATE") == []
    assert path_writes("( VFS-RENAME ) PLACE-RENAME") == []
    assert path_writes("PLACE-RM PLACE-VREPL! VFS-WRITE VFS-TRUNCATE") == []
    assert path_writes("_VFS-RM-BODY MY-VFS-CREATE VFS-MKDIR-HELPER") == []
    assert path_writes("REQUIRE ../../../utils/fs/vfs-copy.f") == []

    assert lines_naming(ROOT_DEFAULTS, "vfs s STREAMS-DRAFT-STORE-INIT") != []
    assert lines_naming(ROOT_DEFAULTS, "streams-source-store-target$ v s") != []
    assert lines_naming(ROOT_DEFAULTS, "a u v s STREAMS-SOURCE-STORE-INIT-AT") == []
    assert lines_naming(ROOT_DEFAULTS, "STREAMS-OBSERVATION-STORE-NAME$") == []
    assert lines_naming(ROOT_DEFAULTS, "\\ not STREAMS-DRAFT-STORE-INIT") == []

    assert lines_naming(ROOT_LITERAL, ": P  S\" /library/root-0\" ;") != []
    assert lines_naming(ROOT_LITERAL, "S\" library\" S\" root-0\"") == []
    assert lines_naming(ROOT_LITERAL, "\\ S\" /streams\" was the layout") == []


def test_applets_write_only_through_their_places() -> None:
    found = [
        f"{name}:{number}: {line}"
        for name, text in _applet_modules()
        if name not in LAYOUT_STORES
        for number, line in path_writes(text)
    ]
    assert not found, "\n".join(found)


def test_each_layout_store_still_writes_by_path() -> None:
    stale = [
        name for name in sorted(LAYOUT_STORES)
        if not path_writes((APPLETS / name).read_text(encoding="utf-8"))
    ]
    assert not stale, stale


def test_the_repositories_compose_their_layout_under_their_folder() -> None:
    found = [
        f"{name}:{number}: {line}"
        for name in REPOSITORIES
        for number, line in lines_naming(
            ROOT_LITERAL, (APPLETS / name).read_text(encoding="utf-8")
        )
    ]
    assert not found, "\n".join(found)


def test_applets_open_streams_stores_in_their_home_folder() -> None:
    found = [
        f"{name}:{number}: {line}"
        for name, text in _applet_modules()
        if name not in LAYOUT_STORES
        for number, line in lines_naming(ROOT_DEFAULTS, text)
    ]
    assert not found, "\n".join(found)
