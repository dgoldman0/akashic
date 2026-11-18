#!/usr/bin/env python3
"""Which file each hosted document is kept in (akashic/utils/fs/held-files.f).

One RAM volume holds a folder that two place sets are granted, so the
table is filled through one set's place and asked through the other's,
as Desk fills it for a document's owner and Pad asks it.

Every check runs on a fresh native machine (native_forth.py) and prints
its results after a `RESULT:` marker.
"""
from native_forth import NativeForth

ROOTS = ("utils/fs/held-files.f",)

INVALID = 1

HELPERS = (
    'VARIABLE VA  VARIABLE PVA  VARIABLE D-REC  VARIABLE D-DOCS',
    'VARIABLE S-OWNER  VARIABLE S-EDITOR',
    'VARIABLE P-OWNER  VARIABLE P-EDITOR  VARIABLE P-DOCS',
    'CREATE TABLE HELD-SIZE ALLOT  TABLE HELD-INIT',
    ': T-SETUP  ( -- )',
    '    524288 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !',
    '    S" records" VA @ VFS-MKDIR THROW  S" documents" VA @ VFS-MKDIR THROW',
    '    S" va" PLACES-VOLUME THROW PVA !  VA @ PVA @ PVOL-ATTACH THROW',
    '    S" records" S" /records" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-REC !',
    '    S" documents" S" /documents" PLACE-WRITABLE PVA @ PLACES-DECLARE',
    '        THROW D-DOCS !',
    # The owner holds records writable; the editor reads it and writes
    # documents, each through a place of its own set.
    '    PLSET-NEW THROW S-OWNER !',
    '    PLACE-WRITABLE D-REC @ S-OWNER @ PLSET-GRANT THROW P-OWNER !',
    '    PLSET-NEW THROW S-EDITOR !',
    '    PLACE-WRITABLE D-DOCS @ S-EDITOR @ PLSET-GRANT THROW P-DOCS !',
    '    PLACE-READ-ONLY D-REC @ S-EDITOR @ PLSET-GRANT THROW P-EDITOR ! ;',
    ': R.  ( ior -- )  VFS-IOR-REASON . ;',
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


def test_a_held_file_is_found_through_any_set_granting_its_place():
    expect([
        ': T  S" /doc.md" P-OWNER @ S" svc.doc" TABLE HELD-HOLD R.',
        # The editor's own place for the same folder finds the holder.
        '     S" /doc.md" P-EDITOR @ TABLE HELD-HOLDER TYPE SPACE',
        # Another path, or the same path in another folder, holds nothing.
        '     S" /other.md" P-EDITOR @ TABLE HELD-HOLDER NIP .',
        '     S" /doc.md" P-DOCS @ TABLE HELD-HOLDER NIP .',
        # The holder's file, by service: its path and its place's name,
        # which the editor's set turns into its own place.
        '     S" svc.doc" TABLE HELD-FILE 2SWAP TYPE SPACE',
        '     2DUP TYPE SPACE  S-EDITOR @ PLSET-FIND P-EDITOR @ = .',
        '     S" svc.none" TABLE HELD-FILE + + + . ;',
        'T',
    ], [0, "svc.doc", 0, 0, "/doc.md", "records", -1, 0])


def test_release_and_clear_forget_files():
    expect([
        ': T  S" /a.md" P-OWNER @ S" svc.a" TABLE HELD-HOLD R.',
        '     S" /b.md" P-OWNER @ S" svc.b" TABLE HELD-HOLD R.',
        '     S" /c.md" P-OWNER @ S" svc.a" TABLE HELD-HOLD R.',
        # Releasing a service forgets each of its files and no other.
        '     S" svc.a" TABLE HELD-RELEASE',
        '     S" /a.md" P-EDITOR @ TABLE HELD-HOLDER NIP .',
        '     S" /c.md" P-EDITOR @ TABLE HELD-HOLDER NIP .',
        '     S" /b.md" P-EDITOR @ TABLE HELD-HOLDER TYPE SPACE',
        '     TABLE HELD-CLEAR  TABLE @ .',
        '     S" /b.md" P-EDITOR @ TABLE HELD-HOLDER NIP . ;',
        'T',
    ], [0, 0, 0, 0, 0, "svc.b", 0, 0])


def test_a_hold_needs_a_place_a_path_and_a_service():
    expect([
        ': T  S" /x.md" 0 S" svc" TABLE HELD-HOLD R.',
        '     0 0 P-OWNER @ S" svc" TABLE HELD-HOLD R.',
        '     S" /x.md" P-OWNER @ 0 0 TABLE HELD-HOLD R.',
        '     TABLE @ .  S" /x.md" 0 TABLE HELD-HOLDER NIP . ;',
        'T',
    ], [INVALID, INVALID, INVALID, 0, 0])
