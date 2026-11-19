#!/usr/bin/env python3
"""Streams keeps its stores in its home's folder.

One RAM volume holds /records/own.  Where a check needs a home, the
registry's default set makes a place over that folder the home, as the
shipping form gives each applet a folder of its own under records, and a
Streams instance with no endpoint takes it.  The applet binds the folder
once as it opens (utils/fs/place-folder.f) and opens its draft, source
and observation stores there.  The repository lays out a streams folder
inside the folder it is given, and the runtime owner opens the repository
and composes the paths of the legacy evidence in the folder it is given.
Nothing lands at the volume's root.

Every check runs on a fresh native machine (native_forth.py) and prints
its results after a `RESULT:` marker.
"""
from native_forth import NativeForth

VOLUME = (
    'VARIABLE VA',
    ': T-VOLUME  ( -- )',
    '    16777216 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN VA !',
    '    S" records" VA @ VFS-MKDIR THROW',
    '    S" /records" VA @ VFS-CD? THROW  S" own" VA @ VFS-MKDIR THROW',
    '    S" /" VA @ VFS-CD? THROW ;',
    ': FOUND.  ( a u -- )  VA @ VFS-RESOLVE? NIP 0= . ;',
    # A folder path longer than the persistence layer takes.
    'CREATE LONG 300 ALLOT  LONG 300 CHAR a FILL  CHAR / LONG C!',
    'CREATE AUTH RID-SIZE ALLOT  AUTH RID-SIZE 0x61 FILL',
    'T-VOLUME',
)

APPLET = NativeForth(("tui/applets/streams/streams.f",), prelude=VOLUME + (
    'VARIABLE PVA  VARIABLE D-REC  VARIABLE T-SET  VARIABLE T-PLACE',
    'CREATE FI COMP-INST ALLOT  FI COMP-INST 0 FILL',
    ': T-PLACES  ( -- )',
    '    S" va" PLACES-VOLUME THROW PVA !  VA @ PVA @ PVOL-ATTACH THROW',
    '    S" records" S" /records" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW',
    '        D-REC ! ;',
    'T-PLACES',
    # The registry's default becomes a set whose home is /records/own,
    # granted at ACCESS.
    ': T-HOME  ( access -- )',
    '    PLSET-NEW THROW T-SET !',
    '    DUP D-REC @ T-SET @ PLSET-GRANT THROW T-PLACE !',
    '    S" own" T-PLACE @ T-SET @ PLSET-GRANT-IN THROW',
    '    T-SET @ PLSET-HOME!  T-SET @ PLACES-DEFAULT! ;',
    # A fresh Streams instance's state, as its init callback finds it.
    ': T-STATE  ( -- )',
    '    _STM-STATE-SIZE ALLOCATE THROW DUP _STM-STATE-SIZE 0 FILL',
    '    _STM-CURRENT-STATE !  FI _STM-CURRENT-INSTANCE ! ;',
    # Bind the home and open the three stores as the init callback does,
    # and show where each store keeps its file.
    ': T-OPEN  ( -- )',
    '    _STM-HOME-BIND',
    '    _STM-FOLDER _STM-FOLDER-U @ TYPE SPACE  _STM-FOLDER-VFS @ VA @ = .',
    '    _STM-DRAFT-STORAGE-INIT SDSTORE-S-ABSENT = .',
    '    _STM-DRAFT-STORE STREAMS-DRAFT-STORE-PATH$ TYPE SPACE',
    '    _STM-SOURCE-STORAGE-INIT SSSTORE-S-ABSENT = .',
    '    _STM-SOURCE-STORE STREAMS-SOURCE-STORE-PATH$ TYPE SPACE',
    '    _STM-CONFIGURED-INIT SREF-S-OK = .',
    '    _STM-CONFIGURED-REFRESH SREF.STORE',
    '        STREAMS-OBSERVATION-STORE-PATH$ TYPE SPACE ;',
))

REPOSITORY = NativeForth(
    ("tui/applets/streams/repository.f",), prelude=VOLUME + (
        'CREATE C0 PERSIST-PAGE-CACHE-SIZE ALLOT',
        'CREATE C1 PERSIST-PAGE-CACHE-SIZE ALLOT',
        'PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF C0M',
        'PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF C1M',
        'GUARD G',
        'STREAMS-REPOSITORY-SIZE XBUF R',
        'STREAMS-REPOSITORY-WORK-SIZE XBUF W',
        'STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF RB',
        '65536 XBUF AMAP',
        'C0M PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 C0 PPAGE-CACHE-INIT THROW',
        'C1M PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 C1 PPAGE-CACHE-INIT THROW',
        ': T-INIT  ( folder-a folder-u -- status )',
        '    VA @ C0 C1 G 0 0 R STREAMS-REPOSITORY-INIT ;',
    ))

OWNER = NativeForth(
    ("tui/applets/streams/runtime-owner.f",), prelude=VOLUME + (
        'STREAMS-RUNTIME-OWNER-SIZE XBUF OWN',
        'STREAMS-RUNTIME-OWNER-SIZE XBUF FAKE',
        'STREAMS-RUNTIME-MIGRATION-SCRATCH-SIZE XBUF BOOT',
        ': T-INIT  ( folder-a folder-u -- status )',
        '    VA @ 0 0 AUTH OWN STREAMS-RUNTIME-OWNER-INIT ;',
    ))


def result(suite, lines, max_steps=4_000_000_000):
    raw = suite.run(['." RESULT: "', *lines, 'CR'], max_steps)
    text = "".join(chr(b) if 0x20 <= b < 0x7F or b in (10, 13, 9) else ""
                   for b in raw)
    assert "RESULT:" in text, text[-600:]
    tail = text.rsplit("RESULT:", 1)[1]
    assert "??" not in tail, tail
    return " ".join(tail.split())


def expect(suite, lines, wanted):
    got = result(suite, lines)
    assert got == " ".join(str(item) for item in wanted), got


STORE_PATHS = [
    "/records/own/streams-draft.bin",
    "/records/own/streams-sources.bin",
    "/records/own/streams-observation.bin",
]


def test_the_applet_opens_its_stores_in_its_home_folder():
    """Each store opens on the home's instance at its file in the home's
    folder; a saved draft lands there and not at the volume's root."""
    expect(APPLET, [
        ': T  PLACE-WRITABLE T-HOME  T-STATE  T-OPEN',
        '     S" hi" 1 _STM-DRAFT-STORE STREAMS-DRAFT-STORE-SAVE',
        '         SDSTORE-S-OK = .',
        '     S" /records/own/streams-draft.bin" FOUND.',
        '     S" /streams-draft.bin" FOUND.',
        '     DEPTH . ;',
        'T',
    ], ["/records/own", -1,
        -1, STORE_PATHS[0], -1, STORE_PATHS[1], -1, STORE_PATHS[2],
        -1, -1, 0, 0])


def test_a_read_only_home_opens_the_stores_for_reading():
    """Bound for reading, the stores open in the same folder and a save
    answers read-only, leaving no file behind."""
    expect(APPLET, [
        ': T  PLACE-READ-ONLY T-HOME  T-STATE  T-OPEN',
        '     S" hi" 1 _STM-DRAFT-STORE STREAMS-DRAFT-STORE-SAVE',
        '         SDSTORE-S-READ-ONLY = .',
        '     S" /records/own/streams-draft.bin" FOUND.',
        '     DEPTH . ;',
        'T',
    ], ["/records/own", -1,
        -1, STORE_PATHS[0], -1, STORE_PATHS[1], -1, STORE_PATHS[2],
        -1, 0, 0])


def test_without_a_home_every_store_stays_blocked():
    expect(APPLET, [
        ': T  0 PLACES-DEFAULT!  T-STATE',
        '     _STM-HOME-BIND  _STM-FOLDER-VFS @ .  _STM-FOLDER-U @ .',
        '     _STM-DRAFT-STORAGE-INIT SDSTORE-S-INVALID = .',
        '     _STM-SOURCE-STORAGE-INIT SSSTORE-S-INVALID = .',
        '     _STM-CONFIGURED-INIT SREF-S-INVALID = .',
        '     DEPTH . ;',
        'T',
    ], [0, 0, -1, -1, -1, 0])


def test_the_repository_lays_out_its_folder_inside_the_given_one():
    """A folder that is no absolute path, one too long for the layout's
    paths and an empty one are refused; in /records/own the repository
    provisions its streams folder there and none at the volume's root."""
    expect(REPOSITORY, [
        ': T  S" records" T-INIT STREAMS-REPOSITORY-S-INVALID = .',
        '     LONG 240 T-INIT STREAMS-REPOSITORY-S-INVALID = .',
        '     S" " T-INIT STREAMS-REPOSITORY-S-INVALID = .',
        '     S" /records/own" T-INIT STREAMS-REPOSITORY-S-OK = .',
        '     AMAP 65536 RB STREAMS-REPOSITORY-RECORD-BUFFER-MIN R W',
        '         STREAMS-REPOSITORY-WORK-INIT STREAMS-REPOSITORY-S-OK = .',
        '     R W STREAMS-REPOSITORY-LOAD STREAMS-REPOSITORY-S-ABSENT = .',
        '     AUTH R W STREAMS-REPOSITORY-PROVISION',
        '         STREAMS-REPOSITORY-S-OK = .',
        '     R W STREAMS-REPOSITORY-LOAD STREAMS-REPOSITORY-S-OK = .',
        '     S" /records/own/streams" FOUND.',
        '     S" /records/own/streams/root-0" FOUND.',
        '     S" /records/own/streams/pages-1" FOUND.',
        '     S" /streams" FOUND.',
        '     R W STREAMS-REPOSITORY-FINI STREAMS-REPOSITORY-S-OK = .',
        '     DEPTH . ;',
        'T',
    ], [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0, -1, 0])


def test_the_runtime_owner_works_in_the_folder_it_is_given():
    """The owner refuses an empty folder and one longer than the
    persistence layer takes.  From an empty volume it keeps /records/own,
    opens its repository there and is ready; the legacy evidence it reads
    lies in the same folder."""
    expect(OWNER, [
        ': T  S" " T-INIT SRT-S-INVALID = .',
        '     LONG 256 T-INIT SRT-S-INVALID = .',
        '     S" /records/own" T-INIT SRT-S-OK = .',
        '     OWN STREAMS-RUNTIME-OWNER-READY? .',
        '     OWN _SRT-FOLDER$ TYPE SPACE',
        '     S" /records/own/streams/root-0" FOUND.',
        '     S" /streams/root-0" FOUND.',
        '     OWN STREAMS-RUNTIME-OWNER-RELEASE SRT-S-OK = .',
        '     S" /records/own" DUP FAKE SRT.FOLDER-U !',
        '         FAKE SRT.FOLDER SWAP CMOVE  BOOT FAKE SRT.BOOT !',
        '     STREAMS-SOURCE-STORE-NAME$ FAKE _SRT-LEGACY-PATH$ TYPE SPACE',
        '     STREAMS-OBSERVATION-STORE-NAME$ FAKE _SRT-LEGACY-PATH$',
        '         TYPE SPACE',
        '     DEPTH . ;',
        'T',
    ], [-1, -1, -1, -1, "/records/own", -1, 0, -1,
        STORE_PATHS[1], STORE_PATHS[2], 0])
