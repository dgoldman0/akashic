#!/usr/bin/env python3
"""Library keeps its repository in its home's folder.

One RAM volume holds /records/own and /records/ro.  The registry's default
set makes a place over one of them the home, as the shipping form gives
each applet a folder of its own under records, and a Library instance
with no endpoint takes that home.  Its controller binds the folder once
as it opens (utils/fs/place-folder.f) and hands it to the repository,
which provisions its files in a library folder inside the home, none at
the volume's root; a read-only home leaves the repository absent.

Every check runs on a fresh native machine (native_forth.py) and prints
its results after a `RESULT:` marker.
"""
from native_forth import NativeForth

ROOTS = ("tui/applets/library/library.f",)

HELPERS = (
    'VARIABLE VA  VARIABLE PVA  VARIABLE D-REC',
    'VARIABLE T-SET  VARIABLE T-ACCESS  VARIABLE T-PLACE',
    'CREATE FI COMP-INST ALLOT  FI COMP-INST 0 FILL',
    ': T-VOLUME  ( -- )',
    '    16777216 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !',
    '    S" records" VA @ VFS-MKDIR THROW',
    '    S" /records" VA @ VFS-CD? THROW',
    '    S" own" VA @ VFS-MKDIR THROW  S" ro" VA @ VFS-MKDIR THROW',
    '    S" /" VA @ VFS-CD? THROW',
    '    S" va" PLACES-VOLUME THROW PVA !  VA @ PVA @ PVOL-ATTACH THROW',
    '    S" records" S" /records" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW',
    '        D-REC ! ;',
    # The registry's default becomes a set whose home is the folder SUB of
    # records, granted at ACCESS.
    ': T-HOME  ( sub-a sub-u access -- )',
    '    T-ACCESS !  PLSET-NEW THROW T-SET !',
    '    T-ACCESS @ D-REC @ T-SET @ PLSET-GRANT THROW T-PLACE !',
    '    T-ACCESS @ ROT ROT T-PLACE @ T-SET @ PLSET-GRANT-IN THROW',
    '    T-SET @ PLSET-HOME!  T-SET @ PLACES-DEFAULT! ;',
    # A fresh Library instance's state and runtime, as its init callback
    # leaves them before the owner opens.
    ': T-LIBRARY  ( -- )',
    '    _LAPP-STATE-SIZE ALLOCATE THROW DUP _LAPP-STATE-SIZE 0 FILL',
    '    _LAPP-CURRENT-STATE !  FI _LAPP-CURRENT-INSTANCE !',
    '    _LAPP-RUNTIME-SIZE ALLOCATE THROW DUP _LAPP-RUNTIME-SIZE 0 FILL',
    '    _LAPP-RUNTIME !  _LAPP-BOOTSTRAP-ID! ;',
    ': FOUND.  ( a u -- )  VA @ VFS-RESOLVE? NIP 0= . ;',
    'T-VOLUME',
)

SUITE = NativeForth(ROOTS, prelude=HELPERS, load_steps=6_000_000_000)


def result(lines, max_steps=4_000_000_000):
    raw = SUITE.run(['." RESULT: "', *lines, 'CR'], max_steps)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-600:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail
    return " ".join(tail.split())


def expect(lines, wanted):
    got = result(lines)
    assert got == " ".join(str(item) for item in wanted), got


def test_the_controller_provisions_its_repository_in_its_home_folder():
    """The controller binds /records/own and provisions its repository
    there; the library folder and its files lie inside the home, and the
    volume's root holds none of them."""
    expect([
        ': T  S" own" PLACE-WRITABLE T-HOME  T-LIBRARY',
        '     _LAPP-ENSURE-PROVISIONED LIBRARY-SERVICE-S-OK = .',
        '     _LAPP-FOLDER _LAPP-FOLDER-U @ TYPE SPACE  _LAPP-VFS @ VA @ = .',
        '     _LAPP-READY? .',
        '     S" /records/own/library" FOUND.',
        '     S" /records/own/library/root-0" FOUND.',
        '     S" /records/own/library/pages-0" FOUND.',
        '     S" /library" FOUND.',
        '     _LAPP-OWNER-CLOSE  DEPTH . ;',
        'T',
    ], [-1, "/records/own", -1, -1, -1, -1, -1, 0, 0])


def test_a_read_only_home_leaves_the_repository_absent():
    """Bound for reading, the home's folder holds no repository, and the
    controller's first use answers read-only instead of creating one."""
    expect([
        ': T  S" ro" PLACE-READ-ONLY T-HOME  T-LIBRARY',
        '     _LAPP-ENSURE-PROVISIONED LIBRARY-SERVICE-S-READ-ONLY = .',
        '     _LAPP-FOLDER _LAPP-FOLDER-U @ TYPE SPACE',
        '     _LAPP-READY? .',
        '     S" /records/ro/library" FOUND.',
        '     _LAPP-OWNER-CLOSE  DEPTH . ;',
        'T',
    ], [-1, "/records/ro", 0, 0, 0])
