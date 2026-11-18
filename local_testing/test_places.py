#!/usr/bin/env python3
"""Volumes, places and place sets (akashic/utils/fs/places.f).

Two RAM volumes stand for mounted storage.  The first holds a folder the
place `docs` covers, a folder beside it that no path in `docs` may reach,
and symbolic links that point out of `docs`, into it and nowhere.  The
second volume starts unattached, so its place starts unavailable.

Every check runs on a fresh native machine (native_forth.py) and prints
its results after a `RESULT:` marker.
"""
from native_forth import NativeForth

PLACES_ROOTS = ("utils/fs/places.f",)

# VFS reasons the checks name (VFS-R-* in utils/fs/vfs.f).
INVALID, NOENT, EXISTS, NOTDIR = 1, 2, 3, 4
READONLY, IO, BUSY, XDEV, NOVOLUME = 7, 9, 14, 19, 21

HELPERS = (
    # A RAM binding that also reads symbolic links.  A link's target is
    # chosen by the binding id its cached entry was given.
    'CREATE _TC-OPS VFS-OPS-SIZE ALLOT',
    'CREATE _TC-BINDING VFS-BINDING-DESC-SIZE ALLOT',
    'VARIABLE _RL-BUF  VARIABLE _RL-CAP  VARIABLE _RL-TA  VARIABLE _RL-TU',
    ': T-RL-RETURN  ( a u -- actual ior )  _RL-TU ! _RL-TA !',
    '    _RL-CAP @ 0= IF _RL-TU @ 0 EXIT THEN',
    '    _RL-TU @ _RL-CAP @ > IF 0 VFS-E-OVERFLOW EXIT THEN',
    '    _RL-TA @ _RL-BUF @ _RL-TU @ MOVE _RL-TU @ 0 ;',
    ': T-READLINK  ( buf cap inode vfs -- actual ior )',
    '    DROP >R _RL-CAP ! _RL-BUF ! R> IN.BID @',
    '    DUP 100 = IF DROP S" ../secret" T-RL-RETURN EXIT THEN',
    '    DUP 101 = IF DROP S" /secret/key" T-RL-RETURN EXIT THEN',
    '    DUP 102 = IF DROP S" sub" T-RL-RETURN EXIT THEN',
    '    DUP 103 = IF DROP S" nowhere" T-RL-RETURN EXIT THEN',
    '    DROP 0 VFS-E-CORRUPT ;',
    ': T-LINK  ( name-a name-u bid parent vfs -- )',
    '    >R >R >R VFS-T-SYMLINK R> 1 R> R> VFS-CACHE-DENTRY',
    '    ?DUP IF THROW THEN DROP ;',
    ': T-VFS  ( binding -- vfs )',
    '    524288 A-XMEM ARENA-NEW IF -1 THROW THEN',
    '    SWAP 0 VFS-NEW ?DUP IF THROW THEN ;',
    'VARIABLE VA  VARIABLE VB  VARIABLE PVA  VARIABLE PVB',
    'VARIABLE D-DOCS  VARIABLE D-ALL  VARIABLE D-OTHER',
    'VARIABLE SET  VARIABLE P-DOCS  VARIABLE P-ALL  VARIABLE P-OTHER',
    ': T-VOLUMES  ( -- )',
    '    VFS-RAM-OPS _TC-OPS VFS-OPS-SIZE MOVE',
    '    VFS-RAM-BINDING _TC-BINDING VFS-BINDING-DESC-SIZE MOVE',
    '    _TC-OPS _TC-BINDING VB.OPS !',
    "    ['] T-READLINK _TC-OPS VFS-OP-READLINK CELLS + !",
    '    _TC-BINDING VB.CAPS DUP @ VFS-CAP-READLINK OR SWAP !',
    '    _TC-BINDING T-VFS VA !  VFS-RAM-BINDING T-VFS VB !',
    '    S" docs" VA @ VFS-MKDIR THROW  S" secret" VA @ VFS-MKDIR THROW',
    '    S" /docs" VA @ VFS-CD? THROW',
    '    S" sub" VA @ VFS-MKDIR THROW  S" a.txt" VA @ VFS-MKFILE? THROW DROP',
    '    S" /secret" VA @ VFS-CD? THROW  S" key" VA @ VFS-MKFILE? THROW DROP',
    '    S" /" VA @ VFS-CD? THROW',
    '    S" out" 100 S" /docs" VA @ VFS-RESOLVE VA @ T-LINK',
    '    S" abs" 101 S" /docs" VA @ VFS-RESOLVE VA @ T-LINK',
    '    S" in" 102 S" /docs" VA @ VFS-RESOLVE VA @ T-LINK',
    '    S" dangling" 103 S" /docs" VA @ VFS-RESOLVE VA @ T-LINK ;',
    ': T-PLACES  ( -- )',
    '    S" va" PLACES-VOLUME THROW PVA !  S" vb" PLACES-VOLUME THROW PVB !',
    '    VA @ PVA @ PVOL-ATTACH THROW',
    '    S" docs" S" /docs" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-DOCS !',
    '    S" all" S" /" PLACE-READ-ONLY PVA @ PLACES-DECLARE THROW D-ALL !',
    '    S" other" S" /" PLACE-WRITABLE PVB @ PLACES-DECLARE THROW D-OTHER !',
    '    S" Documents" D-DOCS @ PLACE-LABEL! THROW',
    '    PLSET-NEW THROW SET !',
    '    PLACE-WRITABLE D-DOCS @ SET @ PLSET-GRANT THROW P-DOCS !',
    '    PLACE-READ-ONLY D-ALL @ SET @ PLSET-GRANT THROW P-ALL !',
    '    PLACE-WRITABLE D-OTHER @ SET @ PLSET-GRANT THROW P-OTHER !',
    '    P-DOCS @ SET @ PLSET-HOME!  P-ALL @ SET @ PLSET-ORIGIN! ;',
    ': R.  ( ior -- )  VFS-IOR-REASON . ;',
    'CREATE _PB 256 ALLOT',
    'T-VOLUMES T-PLACES',
)

SUITE = NativeForth(PLACES_ROOTS, prelude=HELPERS)


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


def test_names_follow_one_rule():
    expect([
        'CREATE _NB 256 ALLOT',
        ': T  S" docs" PLACE-NAME-VALID? .  S" a-b.c_9" PLACE-NAME-VALID? .',
        '     S" Docs" PLACE-NAME-VALID? .  S" a b" PLACE-NAME-VALID? .',
        '     S" ." PLACE-NAME-VALID? .  S" .." PLACE-NAME-VALID? .',
        '     S" ..." PLACE-NAME-VALID? .  S" a/b" PLACE-NAME-VALID? .',
        '     S" x" DROP 0 PLACE-NAME-VALID? .',
        '     _NB 256 97 FILL  _NB 255 PLACE-NAME-VALID? .',
        '     _NB 256 PLACE-NAME-VALID? . ;',
        'T',
    ], [-1, -1, 0, 0, 0, 0, -1, 0, 0, -1, 0])


def test_declarations_are_checked():
    expect([
        ': T  S" Bad" S" /" PLACE-WRITABLE PVA @ PLACES-DECLARE R. .',
        '     S" docs" S" /x" PLACE-WRITABLE PVA @ PLACES-DECLARE R. .',
        '     S" rel" S" docs" PLACE-WRITABLE PVA @ PLACES-DECLARE R. .',
        '     S" odd" S" /" 7 PVA @ PLACES-DECLARE R. .',
        # A folder is declared by its own path: no `..`, no empty name.
        '     S" b1" S" /a/../b" PLACE-WRITABLE PVA @ PLACES-DECLARE R. .',
        '     S" b2" S" /docs/" PLACE-WRITABLE PVA @ PLACES-DECLARE R. .',
        '     S" b3" S" //docs" PLACE-WRITABLE PVA @ PLACES-DECLARE R. .',
        '     S" va" PLACES-VOLUME R. PVA @ = .',
        '     S" Va" PLACES-VOLUME R. .',
        # A writable grant of a read-only place, and a second grant.
        '     PLSET-NEW THROW >R',
        '     PLACE-WRITABLE D-ALL @ R@ PLSET-GRANT R. .',
        '     PLACE-READ-ONLY D-ALL @ R@ PLSET-GRANT R. 0<> .',
        '     PLACE-READ-ONLY D-ALL @ R@ PLSET-GRANT R. .',
        '     R> PLSET-FREE ;',
        'T',
    ], [INVALID, 0, EXISTS, 0, INVALID, 0, INVALID, 0,
        INVALID, 0, INVALID, 0, INVALID, 0, 0, -1, INVALID, 0,
        READONLY, 0, 0, -1, EXISTS, 0])


def test_a_set_lists_its_places_in_order_with_their_roles():
    expect([
        ': T  SET @ PLSET-FIRST DUP P-DOCS @ = .',
        '     PLACE-NEXT DUP P-ALL @ = .  PLACE-NEXT DUP P-OTHER @ = .',
        '     PLACE-NEXT .',
        '     SET @ PLSET-HOME P-DOCS @ = .  SET @ PLSET-ORIGIN P-ALL @ = .',
        '     S" all" SET @ PLSET-FIND P-ALL @ = .  S" none" SET @ PLSET-FIND .',
        '     P-ALL @ SET @ PLSET-MEMBER? .  D-ALL @ SET @ PLSET-MEMBER? .',
        '     0 SET @ PLSET-MEMBER? .',
        '     P-DOCS @ PLACE-NAME TYPE SPACE  P-DOCS @ PLACE-LABEL TYPE SPACE',
        '     P-ALL @ PLACE-LABEL TYPE SPACE',
        # A place of another set cannot be this set's home.
        '     PLSET-NEW THROW >R  PLACE-READ-ONLY D-ALL @ R@ PLSET-GRANT THROW',
        '     SET @ PLSET-HOME!  SET @ PLSET-HOME P-DOCS @ = .  R> PLSET-FREE ;',
        'T',
    ], [-1, -1, -1, 0, -1, -1, -1, 0, -1, 0, 0,
        "docs", "Documents", "all", -1])


def test_a_set_marks_where_a_persons_documents_go():
    expect([
        # A set declares no documents place until composition marks one.
        ': T  SET @ PLSET-DOCUMENTS .',
        '     P-OTHER @ SET @ PLSET-DOCUMENTS!  SET @ PLSET-DOCUMENTS P-OTHER @ = .',
        '     SET @ PLSET-HOME P-DOCS @ = .  SET @ PLSET-ORIGIN P-ALL @ = .',
        # Marking one moves the set's revision, so a list of places redraws.
        '     SET @ PLSET-REVISION  P-DOCS @ SET @ PLSET-DOCUMENTS!',
        '     SET @ PLSET-REVISION <> .  SET @ PLSET-DOCUMENTS P-DOCS @ = .',
        # A place of another set cannot be this set's documents place.
        '     PLSET-NEW THROW >R  PLACE-READ-ONLY D-ALL @ R@ PLSET-GRANT THROW',
        '     SET @ PLSET-DOCUMENTS!  SET @ PLSET-DOCUMENTS P-DOCS @ = .',
        '     R> PLSET-FREE',
        '     0 SET @ PLSET-DOCUMENTS!  SET @ PLSET-DOCUMENTS . ;',
        'T',
    ], [0, -1, -1, -1, -1, -1, -1, 0])


def test_a_holder_is_given_what_it_needs_of_a_set():
    expect([
        ': T  P-OTHER @ SET @ PLSET-DOCUMENTS!',
        # Nothing asked: the origin alone, read-only, for shipped files.
        '     0 SET @ PLSET-DERIVE R. >R',
        '     R@ PLSET-FIRST DUP PLACE-NAME TYPE SPACE DUP PLACE-WRITABLE? .',
        '     DUP R@ PLSET-ORIGIN = .  PLACE-NEXT .',
        '     R@ PLSET-HOME .  R@ PLSET-DOCUMENTS .  R> PLSET-FREE',
        # Its records: the home at the access the set grants it, then the
        # origin, in the set's order, as places of the new set.
        '     PLACES-NEED-HOME SET @ PLSET-DERIVE R. >R',
        '     R@ PLSET-FIRST DUP PLACE-NAME TYPE SPACE DUP PLACE-WRITABLE? .',
        '     DUP R@ PLSET-HOME = .  DUP P-DOCS @ <> .',
        '     PLACE-NEXT DUP PLACE-NAME TYPE SPACE DUP R@ PLSET-ORIGIN = .',
        '     PLACE-NEXT .  R@ PLSET-DOCUMENTS .  R> PLSET-FREE',
        # Documents and the list: every place, writable only where
        # documents go, and no home of its own.
        '     PLACES-NEED-DOCUMENTS PLACES-NEED-LIST OR SET @ PLSET-DERIVE R. >R',
        '     R@ PLSET-FIRST DUP PLACE-NAME TYPE SPACE DUP PLACE-WRITABLE? .',
        '     PLACE-NEXT DUP PLACE-NAME TYPE SPACE DUP PLACE-WRITABLE? .',
        '     PLACE-NEXT DUP PLACE-NAME TYPE SPACE DUP PLACE-WRITABLE? .',
        '     R@ PLSET-DOCUMENTS = .  R@ PLSET-HOME .  R> PLSET-FREE',
        # A narrowed set narrows what is derived from it.
        '     SET @ PLSET-READ-ONLY!  PLACES-NEED-HOME SET @ PLSET-DERIVE R. >R',
        '     R@ PLSET-FIRST PLACE-WRITABLE? .  R> PLSET-FREE',
        # Something that is no set.
        '     0 0 PLSET-DERIVE R. . ;',
        'T',
    ], [0, "all", 0, -1, 0, 0, 0,
        0, "docs", -1, -1, -1, "all", -1, 0, 0,
        0, "docs", 0, "all", 0, "other", -1, -1, 0,
        0, 0,
        INVALID, 0])


def test_paths_start_at_the_folder():
    expect([
        ': T  S" a.txt" P-DOCS @ PLACE-RESOLVE R. S" /docs/a.txt" VA @ VFS-RESOLVE = .',
        '     S" /a.txt" P-DOCS @ PLACE-RESOLVE R. S" /docs/a.txt" VA @ VFS-RESOLVE = .',
        '     S" sub/../a.txt" P-DOCS @ PLACE-RESOLVE R. 0<> .',
        '     S" " P-DOCS @ PLACE-RESOLVE R. P-DOCS @ PLACE-ROOT = .',
        '     S" /" P-DOCS @ PLACE-RESOLVE R. S" /docs" VA @ VFS-RESOLVE = .',
        '     S" nope" P-DOCS @ PLACE-RESOLVE R. .',
        '     S" sub" P-DOCS @ PLACE-RESOLVE THROW P-DOCS @ _PB 256 PLACE-PATH',
        '         R. _PB SWAP TYPE SPACE',
        '     P-DOCS @ PLACE-ROOT P-DOCS @ _PB 256 PLACE-PATH R. _PB SWAP TYPE SPACE',
        '     S" /docs/sub" VA @ VFS-RESOLVE P-ALL @ _PB 256 PLACE-PATH',
        '         R. _PB SWAP TYPE SPACE',
        '     S" /docs/sub" VA @ VFS-RESOLVE P-ALL @ _PB 5 PLACE-PATH R. . ;',
        'T',
    ], [0, -1, 0, -1, 0, -1, 0, -1, 0, -1, NOENT, 0,
        0, "/sub", 0, "/", 0, "/docs/sub", 17, 0])


def test_dotdot_does_not_leave_a_place():
    expect([
        ': T  S" .." P-DOCS @ PLACE-RESOLVE R. .',
        '     S" ../secret/key" P-DOCS @ PLACE-RESOLVE R. .',
        '     S" sub/../../secret" P-DOCS @ PLACE-RESOLVE R. .',
        '     S" /../secret/key" VFS-FF-READ P-DOCS @ PLACE-OPEN R. .',
        '     S" ../made" P-DOCS @ PLACE-CREATE R. .',
        '     S" ../made" P-DOCS @ PLACE-MKDIR R.',
        '     S" ../secret/key" P-DOCS @ PLACE-RM R.',
        '     S" ../secret/key" P-DOCS @ _PB 256 PLACE-BIND R. . .',
        '     S" /secret/key" VA @ VFS-RESOLVE DUP P-DOCS @ PLACE-HOLDS? .',
        '     DUP P-DOCS @ _PB 256 PLACE-PATH R. .',
        '     S" k2" ROT P-DOCS @ PLACE-RENAME R.',
        # A path that steps out and back in names an entry of the place.
        '     S" ../docs/a.txt" P-DOCS @ PLACE-RESOLVE R. 0<> .',
        '     S" /made" VA @ VFS-RESOLVE .  S" /secret/key" VA @ VFS-RESOLVE 0<> . ;',
        'T',
    ], [XDEV, 0, XDEV, 0, XDEV, 0, XDEV, 0, XDEV, 0, XDEV, XDEV,
        XDEV, 0, 0, 0, XDEV, 0, XDEV, 0, -1, 0, -1])


def test_symbolic_links_do_not_leave_a_place():
    expect([
        ': T  S" out/key" P-DOCS @ PLACE-RESOLVE R. .',
        '     S" abs" P-DOCS @ PLACE-RESOLVE R. .',
        '     S" abs" VFS-FF-READ P-DOCS @ PLACE-OPEN R. .',
        '     S" out/new" P-DOCS @ PLACE-CREATE R. .',
        '     S" out/key" P-DOCS @ _PB 256 PLACE-BIND R. . .',
        '     S" abs" P-DOCS @ _PB 256 PLACE-BIND-WRITE R. . .',
        '     S" in" P-DOCS @ PLACE-RESOLVE R. S" /docs/sub" VA @ VFS-RESOLVE = .',
        '     S" in/made" P-DOCS @ PLACE-CREATE R. 0<> .',
        '     S" /docs/sub/made" VA @ VFS-RESOLVE 0<> .',
        '     S" dangling" P-DOCS @ PLACE-RESOLVE R. .',
        '     S" dangling" P-DOCS @ _PB 256 PLACE-BIND R. . .',
        # The same links reach their targets through the place over the
        # whole volume.
        '     S" docs/out/key" P-ALL @ PLACE-RESOLVE R. S" /secret/key" VA @ VFS-RESOLVE = .',
        # Removing a link removes the link, never its target.
        '     S" out" P-DOCS @ PLACE-RM R.  S" /docs/out" VA @ VFS-RESOLVE .',
        '     S" /secret/key" VA @ VFS-RESOLVE 0<> .  S" /secret/new" VA @ VFS-RESOLVE . ;',
        'T',
    ], [XDEV, 0, XDEV, 0, XDEV, 0, XDEV, 0, XDEV, 0, 0, XDEV, 0, 0,
        0, -1, 0, -1, -1, NOENT, 0, INVALID, 0, 0, 0, -1, 0, 0, -1, 0])


def test_a_read_only_place_refuses_every_change():
    expect([
        ': T  P-ALL @ PLACE-WRITABLE? .  P-DOCS @ PLACE-WRITABLE? .',
        '     S" n.txt" P-ALL @ PLACE-CREATE R. .',
        '     S" nd" P-ALL @ PLACE-MKDIR R.',
        '     S" docs/a.txt" P-ALL @ PLACE-RM R.',
        '     S" z" S" docs/a.txt" P-ALL @ PLACE-RESOLVE THROW P-ALL @ PLACE-RENAME R.',
        '     S" docs/a.txt" VFS-FF-READ VFS-FF-WRITE OR P-ALL @ PLACE-OPEN R. .',
        '     S" docs/a.txt" VFS-FF-READ VFS-FF-APPEND OR P-ALL @ PLACE-OPEN R. .',
        '     S" docs/a.txt" P-ALL @ _PB 256 PLACE-BIND-WRITE R. . .',
        '     S" docs/a.txt" P-ALL @ _PB 256 PLACE-BIND R. _PB SWAP TYPE SPACE VA @ = .',
        '     S" docs/a.txt" VFS-FF-READ P-ALL @ PLACE-OPEN R. DUP 0<> . VFS-CLOSE',
        '     P-ALL @ PLACE-SYNC R.',
        '     S" /n.txt" VA @ VFS-RESOLVE .  S" /docs/a.txt" VA @ VFS-RESOLVE 0<> .',
        # Narrowing a set makes its writable places read-only too.
        '     SET @ PLSET-READ-ONLY!  P-DOCS @ PLACE-WRITABLE? .',
        '     S" n.txt" P-DOCS @ PLACE-CREATE R. . ;',
        'T',
    ], [0, -1, READONLY, 0, READONLY, READONLY, READONLY, READONLY, 0,
        READONLY, 0, READONLY, 0, 0, 0, "/docs/a.txt", -1, 0, -1, 0,
        0, -1, 0, READONLY, 0])


def test_a_writable_place_changes_only_its_folder():
    expect([
        'CREATE _RB 16 ALLOT',
        ': T  S" /secret" VA @ VFS-CD? THROW  VA @ V.CWD @ >R',
        '     S" new.txt" P-DOCS @ PLACE-CREATE R. 0<> .',
        '     S" new.txt" P-DOCS @ PLACE-CREATE R. .',
        '     S" new.txt" VFS-FF-READ VFS-FF-WRITE OR P-DOCS @ PLACE-OPEN THROW',
        '     S" hello" 2 PICK VFS-WRITE-EXACT R.  VFS-CLOSE',
        '     S" /new.txt" VFS-FF-READ P-DOCS @ PLACE-OPEN THROW',
        '     _RB 5 2 PICK VFS-READ-EXACT R.  VFS-CLOSE  _RB 5 TYPE SPACE',
        '     S" d2" P-DOCS @ PLACE-MKDIR R.  S" d2/x" P-DOCS @ PLACE-CREATE R. 0<> .',
        '     S" missing/x" P-DOCS @ PLACE-CREATE R. .',
        '     S" a.txt/x" P-DOCS @ PLACE-CREATE R. .',
        '     S" d2" P-DOCS @ PLACE-RM R.',
        '     S" y" S" d2/x" P-DOCS @ PLACE-RESOLVE THROW P-DOCS @ PLACE-RENAME R.',
        '     S" /docs/d2/y" VA @ VFS-RESOLVE 0<> .',
        '     S" d2" S" a.txt" P-DOCS @ PLACE-RESOLVE THROW P-DOCS @ PLACE-RENAME R.',
        '     S" d2/y" P-DOCS @ PLACE-RM R.  S" d2" P-DOCS @ PLACE-RM R.',
        '     S" /docs/d2" VA @ VFS-RESOLVE .',
        # The place's own folder is neither removed nor renamed.
        '     S" /" P-DOCS @ PLACE-RM R.  S" " P-DOCS @ PLACE-RM R.',
        '     S" z" P-DOCS @ PLACE-ROOT P-DOCS @ PLACE-RENAME R.',
        '     P-DOCS @ PLACE-SYNC R.',
        '     S" new.txt" P-DOCS @ _PB 256 PLACE-BIND-WRITE R. _PB SWAP TYPE SPACE VA @ = .',
        '     S" sub/n.bin" P-DOCS @ _PB 256 PLACE-BIND-WRITE R. _PB SWAP TYPE SPACE DROP',
        '     S" /x.bin" P-OTHER @ _PB 256 PLACE-BIND R. . .',
        '     S" sub/n.bin" P-DOCS @ _PB 10 PLACE-BIND R. . .',
        '     S" nosuch/n.bin" P-DOCS @ _PB 256 PLACE-BIND R. . .',
        # The volume's current directory is where the caller left it.
        '     VA @ V.CWD @ R> = .  P-DOCS @ PLACE-NAME-LIMIT . ;',
        'T',
    ], [0, -1, EXISTS, 0, 0, 0, "hello", 0, 0, -1, NOENT, 0, NOTDIR, 0,
        6, 0, -1, EXISTS, 0, 0, 0, INVALID, INVALID, INVALID, 0,
        0, "/docs/new.txt", -1, 0, "/docs/sub/n.bin",
        NOVOLUME, 0, 0, 17, 0, 0, NOENT, 0, 0, -1, 255])


def test_an_unavailable_place_says_why():
    expect([
        ': W.  ( place -- )  PLACE-WHY DUP 0= IF 2DROP ." -" ELSE TYPE THEN SPACE ;',
        ': T  P-OTHER @ PLACE-STATUS R.  P-OTHER @ W.',
        '     P-OTHER @ PLACE-VFS .  P-OTHER @ PLACE-ROOT .',
        '     S" x" P-OTHER @ PLACE-RESOLVE R. .',
        '     S" x" P-OTHER @ PLACE-CREATE R. .',
        '     S" x" VFS-FF-READ P-OTHER @ PLACE-OPEN R. .',
        '     P-OTHER @ PLACE-SYNC R.',
        '     VFS-E-IO PVB @ PVOL-REFUSE  P-OTHER @ PLACE-STATUS R.  P-OTHER @ W.',
        '     S" x" P-OTHER @ PLACE-MKDIR R.',
        '     VB @ PVB @ PVOL-ATTACH R.  P-OTHER @ PLACE-STATUS R.  P-OTHER @ W.',
        '     P-OTHER @ PLACE-VFS VB @ = .',
        '     S" x" P-OTHER @ PLACE-CREATE R. 0<> .  S" /x" VB @ VFS-RESOLVE 0<> .',
        '     S" /x" VA @ VFS-RESOLVE .',
        '     VA @ PVB @ PVOL-ATTACH R.  VB @ PVB @ PVOL-ATTACH R.',
        '     PVB @ PVOL-DETACH  P-OTHER @ PLACE-STATUS R.  P-OTHER @ W.',
        '     P-DOCS @ PLACE-STATUS R.  P-DOCS @ W. ;',
        'T',
    ], [NOVOLUME, "volume missing", 0, 0, NOVOLUME, 0, NOVOLUME, 0,
        NOVOLUME, 0, NOVOLUME, IO, "mount refused", IO,
        0, 0, "-", -1, 0, -1, -1, 0, BUSY, 0,
        NOVOLUME, "volume missing", 0, "-"])


def test_a_missing_folder_and_the_required_check():
    expect([
        'VARIABLE D-GHOST  VARIABLE P-GHOST',
        ': T  S" ghost" S" /later" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW D-GHOST !',
        '     PLACE-WRITABLE D-GHOST @ SET @ PLSET-GRANT THROW P-GHOST !',
        '     P-GHOST @ PLACE-STATUS R.  P-GHOST @ PLACE-WHY TYPE SPACE',
        '     S" x" P-GHOST @ PLACE-CREATE R. .',
        '     PLACES-CHECK . .',
        '     -1 D-GHOST @ PLACE-REQUIRED!  PLACES-CHECK R. D-GHOST @ = .',
        '     -1 D-OTHER @ PLACE-REQUIRED!  PLACES-CHECK R. D-OTHER @ = .',
        '     0 D-OTHER @ PLACE-REQUIRED!',
        # The folder appears: the place is usable without being redeclared.
        '     S" later" P-ALL @ PLACE-MKDIR R.',
        '     SET @ PLSET-FREE  PLSET-NEW THROW SET !',
        '     PLACE-WRITABLE D-GHOST @ SET @ PLSET-GRANT THROW P-GHOST !',
        '     S" /" VA @ VFS-CD? THROW  S" later" VA @ VFS-MKDIR R.',
        '     P-GHOST @ PLACE-STATUS R.  PLACES-CHECK . .',
        '     S" x" P-GHOST @ PLACE-CREATE R. 0<> .  S" /later/x" VA @ VFS-RESOLVE 0<> .',
        # A file where the folder should be is not a folder.
        '     S" f" S" /docs/a.txt" PLACE-READ-ONLY PVA @ PLACES-DECLARE THROW',
        '     PLACE-READ-ONLY SWAP SET @ PLSET-GRANT THROW PLACE-STATUS R. ;',
        'T',
    ], [NOENT, "folder missing", NOENT, 0, 0, 0, NOENT, -1, NOVOLUME, -1,
        READONLY, 0, 0, 0, 0, 0, -1, -1, NOTDIR])


def test_the_revision_moves_with_membership_and_state():
    expect([
        'VARIABLE _REV',
        ': MOVED?  ( -- )  SET @ PLSET-REVISION DUP _REV @ <> . _REV ! ;',
        ': T  SET @ PLSET-REVISION _REV !',
        '     S" a.txt" P-DOCS @ PLACE-RESOLVE 2DROP  P-DOCS @ PLACE-STATUS DROP',
        '     P-OTHER @ PLACE-WHY 2DROP  S" t" P-DOCS @ PLACE-CREATE 2DROP  MOVED?',
        '     VB @ PVB @ PVOL-ATTACH DROP  MOVED?',
        '     PVB @ PVOL-DETACH  MOVED?',
        '     VFS-E-IO PVB @ PVOL-REFUSE  MOVED?',
        '     P-ALL @ SET @ PLSET-HOME!  MOVED?',
        '     P-DOCS @ SET @ PLSET-ORIGIN!  MOVED?',
        '     S" more" S" /secret" PLACE-READ-ONLY PVA @ PLACES-DECLARE THROW  MOVED?',
        '     PLACE-READ-ONLY SWAP SET @ PLSET-GRANT THROW DROP  MOVED?',
        '     S" Everything" D-ALL @ PLACE-LABEL! DROP  MOVED?',
        '     SET @ PLSET-READ-ONLY!  MOVED?',
        '     SET @ PLSET-FIRST DROP  SET @ PLSET-HOME DROP  MOVED? ;',
        'T',
    ], [0, -1, -1, -1, -1, -1, -1, -1, -1, -1, 0])


def test_the_default_set():
    expect([
        ': T  PLACES-DEFAULT .  SET @ PLACES-DEFAULT!  PLACES-DEFAULT SET @ = .',
        '     D-ALL @ PLACES-DEFAULT!  PLACES-DEFAULT SET @ = .',
        '     SET @ PLSET-FREE  PLACES-DEFAULT . ;',
        'T',
    ], [0, -1, -1, 0])


def test_a_live_entry_is_placed_by_its_own_parent_chain():
    """PLACE-PATH, PLACE-HOLDS? and PLACE-RENAME take a live entry.  They
    find the folder among the entry's parents and match it against the
    declared path, so they look nothing up before they use the entry."""
    expect([
        'VARIABLE P-DEEP',
        ': T  S" deep" S" /docs/sub" PLACE-WRITABLE PVA @ PLACES-DECLARE THROW',
        '     PLACE-WRITABLE SWAP SET @ PLSET-GRANT THROW P-DEEP !',
        '     S" f" P-DEEP @ PLACE-CREATE THROW DROP',
        '     S" /docs/sub/f" VA @ VFS-RESOLVE P-DEEP @ _PB 256 PLACE-PATH',
        '         R. _PB SWAP TYPE SPACE',
        '     S" /docs/sub" VA @ VFS-RESOLVE P-DEEP @ _PB 256 PLACE-PATH',
        '         R. _PB SWAP TYPE SPACE',
        '     S" /docs/sub" VA @ VFS-RESOLVE P-DEEP @ PLACE-HOLDS? .',
        '     S" /docs/a.txt" VA @ VFS-RESOLVE P-DEEP @ PLACE-HOLDS? .',
        '     S" /docs" VA @ VFS-RESOLVE P-DEEP @ PLACE-HOLDS? .',
        '     VA @ V.ROOT @ P-DEEP @ PLACE-HOLDS? .  0 P-DEEP @ PLACE-HOLDS? .',
        '     S" /docs/a.txt" VA @ VFS-RESOLVE P-DEEP @ _PB 256 PLACE-PATH R. .',
        # Another volume's entry is in no place of this one.
        '     VB @ V.ROOT @ P-DEEP @ PLACE-HOLDS? .',
        '     S" g" S" /docs/sub/f" VA @ VFS-RESOLVE P-DEEP @ PLACE-RENAME R.',
        '     S" /docs/sub/g" VA @ VFS-RESOLVE 0<> .',
        '     S" h" S" /docs/a.txt" VA @ VFS-RESOLVE P-DEEP @ PLACE-RENAME R.',
        '     S" h" S" /docs/sub" VA @ VFS-RESOLVE P-DEEP @ PLACE-RENAME R.',
        # A folder of the same name elsewhere is not the place's folder.
        '     S" /secret" VA @ VFS-CD? THROW  S" sub" VA @ VFS-MKDIR THROW',
        '     S" /" VA @ VFS-CD? THROW',
        '     S" /secret/sub" VA @ VFS-RESOLVE P-DEEP @ PLACE-HOLDS? . ;',
        'T',
    ], [0, "/f", 0, "/", -1, 0, 0, 0, 0, XDEV, 0, 0, 0, -1, XDEV, INVALID, 0])
