#!/usr/bin/env python3
"""The folder a store keeps its layout in (akashic/utils/fs/place-folder.f).

One RAM volume holds a records folder.  Places over it, over a folder of
its own inside it and over the volume's root stand for the homes a store
is given, and the checks bind each place's folder and compose paths under
it, as Streams' and Library's repositories do when they open.

Every check runs on a fresh native machine (native_forth.py) and prints
its results after a `RESULT:` marker.
"""
from native_forth import NativeForth

ROOTS = ("utils/fs/place-folder.f",)

# VFS reasons the checks name (VFS-R-* in utils/fs/vfs.f).
INVALID, NOENT, NAMETOOLONG = 1, 2, 17

HELPERS = (
    'VARIABLE VA  VARIABLE PVA  VARIABLE D-REC  VARIABLE D-ROOT',
    'VARIABLE SET  VARIABLE P-REC  VARIABLE P-RO  VARIABLE P-ROOT',
    'VARIABLE P-OWN  VARIABLE P-GONE',
    'CREATE _PB 256 ALLOT',
    ': T-SETUP  ( -- )',
    '    524288 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !',
    '    S" records" VA @ VFS-MKDIR THROW',
    '    S" /records" VA @ VFS-CD? THROW  S" own" VA @ VFS-MKDIR THROW',
    '    S" /" VA @ VFS-CD? THROW',
    '    S" va" PLACES-VOLUME THROW PVA !  VA @ PVA @ PVOL-ATTACH THROW',
    '    S" records" S" /records" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-REC !',
    '    S" root" S" /" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-ROOT !',
    '    PLSET-NEW THROW SET !',
    '    PLACE-WRITABLE D-REC @ SET @ PLSET-GRANT THROW P-REC !',
    '    PLACE-WRITABLE S" own" P-REC @ SET @ PLSET-GRANT-IN THROW P-OWN !',
    '    PLACE-WRITABLE S" gone" P-REC @ SET @ PLSET-GRANT-IN THROW P-GONE !',
    '    PLACE-WRITABLE D-ROOT @ SET @ PLSET-GRANT THROW P-ROOT !',
    '    PLSET-NEW THROW >R',
    '    PLACE-READ-ONLY D-REC @ R> PLSET-GRANT THROW P-RO ! ;',
    ': R.  ( ior -- )  VFS-IOR-REASON . ;',
    ': B.  ( vfs len ior -- )  R. _PB SWAP TYPE SPACE VA @ = . ;',
    ': P.  ( len ior -- )  R. _PB SWAP TYPE SPACE ;',
    'T-SETUP',
)

SUITE = NativeForth(ROOTS, prelude=HELPERS)


def result(lines, max_steps=50_000_000):
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


def test_a_place_binds_its_own_folder():
    """Each place answers its instance and the volume path of its folder:
    records, a folder of its own inside records, the volume's root, and
    records again through a read-only grant."""
    expect([
        ': T  P-REC @ _PB 256 PFOLDER-BIND B.',
        '     P-OWN @ _PB 256 PFOLDER-BIND B.',
        '     P-ROOT @ _PB 256 PFOLDER-BIND B.',
        '     P-RO @ _PB 256 PFOLDER-BIND B. ;',
        'T',
    ], [0, "/records", -1, 0, "/records/own", -1, 0, "/", -1,
        0, "/records", -1])


def test_a_folder_that_is_missing_or_no_place_binds_nothing():
    expect([
        ': T  P-GONE @ _PB 256 PFOLDER-BIND R. . .',
        '     0 _PB 256 PFOLDER-BIND R. . . ;',
        'T',
    ], [NOENT, 0, 0, INVALID, 0, 0])


def test_paths_are_composed_under_a_folder():
    """A name joins its folder with one slash, the volume's root included;
    a path that does not fit, an empty name and a folder that is no
    absolute path are refused."""
    expect([
        ': T  S" library" S" /records/own" _PB 256 PFOLDER-PATH P.',
        '     S" library/pages-0" S" /records/own" _PB 256 PFOLDER-PATH P.',
        '     S" library" S" /" _PB 256 PFOLDER-PATH P.',
        '     S" library" S" /records/own" _PB 20 PFOLDER-PATH R. .',
        '     S" library" S" /records/own" _PB 12 PFOLDER-PATH R. .',
        '     S" " S" /records" _PB 256 PFOLDER-PATH R. .',
        '     S" library" S" records" _PB 256 PFOLDER-PATH R. .',
        '     S" library" 0 0 _PB 256 PFOLDER-PATH R. . ;',
        'T',
    ], [0, "/records/own/library", 0, "/records/own/library/pages-0",
        0, "/library", 0, 20, NAMETOOLONG, 0,
        INVALID, 0, INVALID, 0, INVALID, 0])
