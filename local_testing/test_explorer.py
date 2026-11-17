#!/usr/bin/env python3
"""Test suite for akashic-tui explorer widget (explorer.f).

Tests the File Explorer widget that bridges tree.f to a place set.
Covers: creation, the place rows, VFS callbacks, navigation,
expand/collapse, selection callbacks with their place, new file/dir,
rename, a read-only and an unavailable place, and cleanup.
Every check runs on a fresh native machine (native_forth.py).
"""
from native_forth import NativeForth

# The explorer and everything it REQUIREs, in the canonical load order.
EXPLORER_ROOTS = ("tui/widgets/explorer.f",)

# Key event buffer + VFS helper
HELPERS = (
    'CREATE _EV 24 ALLOT',
    'VARIABLE _TARN',
    ': T-VFS-NEW  ( -- vfs )',
    '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
    '    _TARN @ VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN ;',
    # A place set over a volume: the place `files`, labelled Files, over
    # its root, and three more a test may add to the set.
    'VARIABLE _TVOL  VARIABLE _TSET  VARIABLE _TP',
    'VARIABLE _TP-DOCS  VARIABLE _TP-RO  VARIABLE _TP-GONE',
    ': T-PLACES  ( vfs -- set )',
    '    S" tv" PLACES-VOLUME THROW _TVOL !  _TVOL @ PVOL-ATTACH THROW',
    '    PLSET-NEW THROW _TSET !',
    '    S" files" S" /" PLACE-WRITABLE _TVOL @ PLACES-DECLARE THROW',
    '    S" Files" 2 PICK PLACE-LABEL! THROW',
    '    PLACE-WRITABLE SWAP _TSET @ PLSET-GRANT THROW _TP !',
    '    _TSET @ ;',
    # The folder /docs again, as a writable place of its own.
    ': T-PLACE-DOCS  ( -- )',
    '    S" docs" S" /docs" PLACE-WRITABLE _TVOL @ PLACES-DECLARE THROW',
    '    S" Docs" 2 PICK PLACE-LABEL! THROW',
    '    PLACE-WRITABLE SWAP _TSET @ PLSET-GRANT THROW _TP-DOCS ! ;',
    # The folder /src, read-only.
    ': T-PLACE-RO  ( -- )',
    '    S" ro" S" /src" PLACE-READ-ONLY _TVOL @ PLACES-DECLARE THROW',
    '    PLACE-READ-ONLY SWAP _TSET @ PLSET-GRANT THROW _TP-RO ! ;',
    # A place on a volume that is not attached.
    ': T-PLACE-GONE  ( -- )',
    '    S" gone" S" /" PLACE-WRITABLE S" away" PLACES-VOLUME THROW',
    '    PLACES-DECLARE THROW  S" Card" 2 PICK PLACE-LABEL! THROW',
    '    PLACE-WRITABLE SWAP _TSET @ PLSET-GRANT THROW _TP-GONE ! ;',
    ': T-KEY  ( code -- )  KEY-T-SPECIAL _EV !  _EV 8 + !  0 _EV 16 + ! ;',
)

SUITE = NativeForth(EXPLORER_ROOTS, prelude=HELPERS)


def uart_text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw)


def run_forth(lines, max_steps=50_000_000):
    return uart_text(SUITE.run(lines, max_steps))


def check(name, forth_lines, expected):
    output = run_forth(forth_lines)
    tail = "\n".join(output.strip().split("\n")[-6:])
    assert expected in output, f"{name}: expected {expected!r}, got:\n{tail}"


# =====================================================================
#  Common test setup: VFS + explorer
# =====================================================================
#
#  Creates a ramdisk VFS with this structure:
#    /                 (root dir)
#    ├── docs/         (subdir)
#    │   └── readme    (file)
#    ├── src/          (subdir, empty)
#    ├── hello.f       (file)
#    └── notes.txt     (file)
#
#  The explorer is given a set of one place, `files` over the root, so
#  its one top row is that place and the entries above are below it.

_EXPL_SETUP = [
    # Screen + region; EXPL-NEW takes the region but leaves it to its
    # caller, so it is kept for cleanup.
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
    'VARIABLE _TR  0 0 20 40 RGN-NEW DUP _TR !',
    # VFS
    'T-VFS-NEW',
    # Stash VFS handle
    'VARIABLE _TV  DUP _TV !',
    # Create files/dirs in root (cwd = root after VFS-NEW)
    'S" docs"      _TV @ VFS-MKDIR DROP',
    'S" src"       _TV @ VFS-MKDIR DROP',
    'S" hello.f"   _TV @ VFS-MKFILE DROP',
    'S" notes.txt" _TV @ VFS-MKFILE DROP',
    # Create file inside docs/
    'S" docs" _TV @ VFS-CD DROP',
    'S" readme" _TV @ VFS-MKFILE DROP',
    'S" .." _TV @ VFS-CD DROP',
    # Create explorer: ( rgn set -- widget )
    'DROP _TV @ T-PLACES  EXPL-NEW',
    # Stash explorer widget
    'VARIABLE _TW  DUP _TW !',
]

_EXPL_CLEANUP = 'EXPL-FREE _TR @ RGN-FREE SCR-FREE'


# =====================================================================
#  Tests
# =====================================================================

def test_expl_create():
    """EXPL-NEW creates explorer with type WDG-T-EXPLORER."""
    check("type is WDG-T-EXPLORER (16)",
        _EXPL_SETUP + [
            '_TW @ WDG-TYPE . 8888 .',
            _EXPL_CLEANUP], "16 8888")


def test_expl_tree_embedded():
    """Explorer has an embedded tree widget."""
    check("tree widget is non-zero",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")
    check("tree type is WDG-T-TREE (11)",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE WDG-TYPE . 8888 .',
            _EXPL_CLEANUP], "11 8888")


def test_expl_set_accessor():
    """EXPL-SET returns the place set."""
    check("EXPL-SET matches the set given",
        _EXPL_SETUP + [
            '_TW @ EXPL-SET _TSET @ = . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_selected_place_row():
    """Initially the first place's own row is selected: no entry, the place."""
    check("EXPL-SELECTED = 0 and the place",
        _EXPL_SETUP + [
            '_TW @ EXPL-SELECTED _TP @ = . . 8888 .',
            _EXPL_CLEANUP], "-1 0 8888")


def test_expl_leaf_callback():
    """_EXPL-LEAF? returns true for files, false for dirs."""
    check("a place and a directory are not leaves",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TP @ _EXPL-LEAF? .  _TV @ V.ROOT @ _EXPL-LEAF? . 8888 .',
            _EXPL_CLEANUP], "0 0 8888")
    # Find hello.f — it's a child of root
    check("file is a leaf",
        _EXPL_SETUP + [
            # Ensure children loaded, get first child (notes.txt = file, prepended)
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TV @ V.ROOT @ DUP _TV @ _VFS-ENSURE-CHILDREN',
            '_TV @ V.ROOT @ IN.CHILD @',   # first child = notes.txt
            '_EXPL-LEAF? . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_children_callback():
    """_EXPL-CHILDREN returns first child for dirs, 0 for files."""
    # Root is a directory — should have children after ensure
    check("a place's children are its folder's",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TP @ _EXPL-CHILDREN DUP 0<> .',
            '_TV @ V.ROOT @ _EXPL-CHILDREN = . 8888 .',
            _EXPL_CLEANUP], "-1 -1 8888")


def test_expl_next_callback():
    """_EXPL-NEXT returns next sibling."""
    check("first child has a sibling",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TP @ _EXPL-CHILDREN',
            '_EXPL-NEXT 0<> .  _TP @ _EXPL-NEXT . 8888 .',
            _EXPL_CLEANUP], "-1 0 8888")


def test_expl_label_callback():
    """_EXPL-LABEL returns a place's label and an entry's name; the tree
    marks directories."""
    check("a place row reads its label, an entry its name",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TP @ _EXPL-LABEL TYPE SPACE',
            'S" /docs" _TV @ VFS-RESOLVE _EXPL-LABEL TYPE SPACE 8888 .',
            _EXPL_CLEANUP], "Files docs 8888")


def test_expl_expand_root():
    """Expanding root reveals children in the tree."""
    check("expand root → tree shows children",
        _EXPL_SETUP + [
            # Expand root via tree
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "5 8888")  # root + docs + src + hello.f + notes.txt


def test_expl_expand_all():
    """EXPL-EXPAND-ALL shows entire tree."""
    check("expand all → 6 visible (root + docs + readme + src + hello.f + notes.txt)",
        _EXPL_SETUP + [
            '_TW @ EXPL-EXPAND-ALL',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "6 8888")


def test_expl_nav_down():
    """Down arrow moves cursor in tree."""
    check("down from root → cursor 1",
        _EXPL_SETUP + [
            # First expand root so there are visible children
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            # Simulate Down key event
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE _TREE-SETTLE _TREE-CUR-ROW @ . 8888 .',
            _EXPL_CLEANUP], "1 8888")


def test_expl_nav_up():
    """Up arrow moves cursor back."""
    check("down then up → cursor 0",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            'KEY-T-SPECIAL _EV !  KEY-UP _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE _TREE-SETTLE _TREE-CUR-ROW @ . 8888 .',
            _EXPL_CLEANUP], "0 8888")


def test_expl_enter_toggles_dir():
    """Enter on a directory toggles expand/collapse."""
    # Initially cursor on root. Enter should expand root.
    check("enter on root toggles expand",
        _EXPL_SETUP + [
            'KEY-T-SPECIAL _EV !  KEY-ENTER _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "5 8888")  # root + 4 children


def test_expl_enter_fires_on_open():
    """Enter on a file fires on-open callback."""
    check("on-open fires with file inode",
        _EXPL_SETUP + [
            # Set up on-open callback that prints the inode type
            'VARIABLE _TOI  0 _TOI !',
            'VARIABLE _TOP  0 _TOP !',
            ': _T-ON-OPEN  ( inode place expl -- ) DROP _TOP ! IN.TYPE @ _TOI ! ;',
            "' _T-ON-OPEN _TW @ EXPL-ON-OPEN",
            # Expand root and move down once to first child
            # Child order is newest-first (prepended): notes.txt, hello.f, src, docs
            # cursor 1 = notes.txt (a file)
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            # Now press Enter on notes.txt (file → fires on-open)
            'KEY-T-SPECIAL _EV !  KEY-ENTER _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TOI @ .  _TOP @ _TP @ = . 8888 .',
            _EXPL_CLEANUP], "1 -1 8888")  # VFS-T-FILE = 1, in its place


def test_expl_on_select():
    """Navigation fires on-select callback."""
    check("on-select fires on nav",
        _EXPL_SETUP + [
            'VARIABLE _TSI  0 _TSI !',
            ': _T-ON-SEL  ( inode place expl -- ) DROP 2DROP 1 _TSI +! ;',
            "' _T-ON-SEL _TW @ EXPL-ON-SELECT",
            # Expand root
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            # Down arrow → fires on-select
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TSI @ . 8888 .',
            _EXPL_CLEANUP], "1 8888")


def test_expl_new_file():
    """EXPL-NEW-FILE creates a file in the selected place's folder."""
    check("new file appears in the place's folder",
        _EXPL_SETUP + [
            # New file in the folder (the place's row is selected)
            '_TW @ EXPL-NEW-FILE',
            # Check: "newfile" exists via VFS-RESOLVE 
            'S" newfile" _TV @  VFS-RESOLVE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_new_dir():
    """EXPL-NEW-DIR creates a subdirectory."""
    check("new dir appears in root",
        _EXPL_SETUP + [
            '_TW @ EXPL-NEW-DIR',
            'S" newfolder" _TV @  VFS-RESOLVE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_new_file_in_subdir():
    """New file is created in the selected directory, not root."""
    check("new file in selected dir (src)",
        _EXPL_SETUP + [
            # Expand root and navigate to src/ (child index 3 with prepend order)
            # Prepend order: root(0), notes.txt(1), hello.f(2), src(3), docs(4)
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',  # cursor 1 = notes.txt
            '_EV _TW @ WDG-HANDLE DROP',  # cursor 2 = hello.f
            '_EV _TW @ WDG-HANDLE DROP',  # cursor 3 = src
            # Create new file — should go into src/
            '_TW @ EXPL-NEW-FILE',
            # Check: newfile exists under src via path resolution
            'S" src/newfile" _TV @  VFS-RESOLVE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_refresh():
    """EXPL-REFRESH marks widget dirty."""
    check("refresh marks dirty",
        _EXPL_SETUP + [
            '_TW @ WDG-CLEAN',
            '_TW @ EXPL-REFRESH',
            '_TW @ WDG-DIRTY? . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_show_hidden():
    """EXPL-SHOW-HIDDEN! toggles the hidden flag."""
    check("initially hidden = false",
        _EXPL_SETUP + [
            '_TW @ EXPL-SHOW-HIDDEN? . 8888 .',
            _EXPL_CLEANUP], "0 8888")
    check("set hidden = true",
        _EXPL_SETUP + [
            '-1 _TW @ EXPL-SHOW-HIDDEN!',
            '_TW @ EXPL-SHOW-HIDDEN? . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_rename_flag():
    """EXPL-RENAME sets rename-active flag and creates input widget."""
    check("a place's own row is not renamed",
        _EXPL_SETUP + [
            '_TW @ EXPL-RENAME',
            '_TW @ 88 + @ 2 AND . 8888 .',
            _EXPL_CLEANUP], "0 8888")
    check("rename sets flag",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',   # an entry, not the place
            '_TW @ EXPL-RENAME',
            '_TW @ 88 + @ 2 AND 0<> . 8888 .',  # flags2 bit 1
            _EXPL_CLEANUP], "-1 8888")
    check("rename creates input widget",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',   # an entry, not the place
            '_TW @ EXPL-RENAME',
            '_TW @ 80 + @ 0<> . 8888 .',  # rename-input field non-zero
            _EXPL_CLEANUP], "-1 8888")


def test_expl_handle_f5():
    """F5 key refreshes the explorer."""
    check("F5 returns consumed",
        _EXPL_SETUP + [
            '_TW @ WDG-CLEAN',
            'KEY-T-SPECIAL _EV !  KEY-F5 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_handle_f2():
    """F2 key starts rename mode."""
    check("F2 activates rename",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',   # an entry, not the place
            'KEY-T-SPECIAL _EV !  KEY-F2 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ 88 + @ 2 AND 0<> . 8888 .',  # rename active
            _EXPL_CLEANUP], "-1 8888")


def test_expl_rename_esc_cancels():
    """Escape during rename cancels without changing anything."""
    check("ESC cancels rename mode",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',   # an entry, not the place
            '_TW @ EXPL-RENAME',
            '_TW @ 88 + @ 2 AND 0<> . ',  # confirm active first
            'KEY-T-SPECIAL _EV !  KEY-ESC _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ 88 + @ 2 AND . 8888 .',  # should be 0 now
            _EXPL_CLEANUP], "0 8888")


def test_expl_unrelated_key():
    """Unrelated key is not consumed."""
    check("char 'a' not consumed",
        _EXPL_SETUP + [
            'KEY-T-CHAR _EV !  65 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE . 8888 .',
            _EXPL_CLEANUP], "0 8888")


def test_expl_collapse_all():
    """EXPL-COLLAPSE-ALL collapses the tree."""
    check("collapse all → 1 visible",
        _EXPL_SETUP + [
            '_TW @ EXPL-EXPAND-ALL',
            '_TW @ EXPL-COLLAPSE-ALL',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "1 8888")


def test_expl_free():
    """EXPL-FREE doesn't crash."""
    check("free completes",
        _EXPL_SETUP + [
            'EXPL-FREE 7777 .',
            '_TR @ RGN-FREE SCR-FREE'], "7777")


def test_expl_show_hidden_moves_the_explorer_revision_on_a_change():
    """Showing hidden files moves the explorer's revision once, and asking
    again moves nothing.  The tree's walker does not read the flag, so the
    tree's revision stays."""
    check("revision moves on a change only",
        _EXPL_SETUP + [
            '_TW @ WDG-REVISION _TW @ EXPL-TREE WDG-REVISION',
            '-1 _TW @ EXPL-SHOW-HIDDEN!',
            '_TW @ EXPL-TREE WDG-REVISION SWAP - . _TW @ WDG-REVISION SWAP - .',
            '_TW @ WDG-REVISION _TW @ EXPL-TREE WDG-REVISION',
            '-1 _TW @ EXPL-SHOW-HIDDEN!',
            '_TW @ EXPL-TREE WDG-REVISION SWAP - . _TW @ WDG-REVISION SWAP - . 8888 .',
            _EXPL_CLEANUP], "0 1 0 0 8888")


# =====================================================================
#  Places
# =====================================================================

def test_expl_top_rows_are_the_sets_places():
    """Each place of the set is a top row, in the set's order, by label."""
    check("two places, collapsed: two rows with their labels",
        _EXPL_SETUP[:-2] + [
            'DROP _TV @ T-PLACES DROP T-PLACE-DOCS',
            '_TSET @ EXPL-NEW',
            'VARIABLE _TW  DUP _TW !',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT .',
            '_TW @ EXPL-TREE _TW-W !',
            '_TP @ _EXPL-LABEL TYPE SPACE  _TP @ _EXPL-NEXT _TP-DOCS @ = .',
            '_TP-DOCS @ _EXPL-LABEL TYPE SPACE  _TP-DOCS @ _EXPL-NEXT . 8888 .',
            _EXPL_CLEANUP], "2 Files -1 Docs 0 8888")


def test_expl_selection_names_the_row_place():
    """One folder shown under two places: an entry's place is its row's."""
    check("readme under Files/docs and under Docs",
        _EXPL_SETUP[:-2] + [
            'DROP _TV @ T-PLACES DROP T-PLACE-DOCS',
            '_TSET @ EXPL-NEW',
            'VARIABLE _TW  DUP _TW !',
            '_TW @ EXPL-EXPAND-ALL',
            # Rows: Files, notes.txt, hello.f, src, docs, readme, Docs, readme
            '_TW @ EXPL-TREE _TREE-VIS-COUNT .',
            ': T-DOWN  ( n -- )  0 ?DO KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP LOOP ;',
            '5 T-DOWN  _TW @ EXPL-SELECTED _TP @ = .',
            'S" /docs/readme" _TV @ VFS-RESOLVE = .',
            '1 T-DOWN  _TW @ EXPL-SELECTED _TP-DOCS @ = . .',
            '1 T-DOWN  _TW @ EXPL-SELECTED _TP-DOCS @ = .',
            'S" /docs/readme" _TV @ VFS-RESOLVE = . 8888 .',
            _EXPL_CLEANUP], "8 -1 -1 -1 0 -1 -1 8888")


def test_expl_path_key_is_the_trees_key():
    """A path's key is the key the tree gives the entry at that path."""
    check("the place's row, a file below it and a file two levels down",
        _EXPL_SETUP + [
            '_TW @ EXPL-EXPAND-ALL',
            '_TW @ EXPL-TREE TREE-SELECTED-KEY S" /" _TP @ EXPL-PATH-KEY = .',
            # Rows: Files, notes.txt, hello.f, src, docs, readme
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE TREE-SELECTED-KEY S" /notes.txt" _TP @ EXPL-PATH-KEY = .',
            ': T-DOWN4  4 0 DO _EV _TW @ WDG-HANDLE DROP LOOP ;  T-DOWN4',
            '_TW @ EXPL-TREE TREE-SELECTED-KEY S" /docs/readme" _TP @ EXPL-PATH-KEY = .',
            '_TW @ EXPL-TREE TREE-SELECTED-KEY S" /docs" _TP @ EXPL-PATH-KEY <> . 8888 .',
            _EXPL_CLEANUP], "-1 -1 -1 -1 8888")


def test_expl_unavailable_place_says_why_and_stays_closed():
    """A place whose volume is missing shows the reason and has no rows."""
    check("the row reads its label and why; opening it shows nothing",
        _EXPL_SETUP[:-2] + [
            'DROP _TV @ T-PLACES DROP T-PLACE-GONE',
            '_TSET @ EXPL-NEW',
            'VARIABLE _TW  DUP _TW !',
            '_TW @ EXPL-TREE _TW-W !',
            '_TP-GONE @ _EXPL-LABEL TYPE SPACE  _TP-GONE @ _EXPL-CHILDREN .',
            '_TW @ EXPL-TREE _TP-GONE @ TREE-EXPAND',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT .',
            # Nothing is created on its row.
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-SELECTED _TP-GONE @ = . .',
            '_TW @ EXPL-NEW-FILE  S" /newfile" _TV @ VFS-RESOLVE . 8888 .',
            _EXPL_CLEANUP], "Card (volume missing) 0 2 -1 0 0 8888")


def test_expl_place_rows_follow_the_volume():
    """When the volume attaches, the row loses its reason and opens."""
    check("attach, then draw: the label is the plain label",
        _EXPL_SETUP[:-2] + [
            'DROP _TV @ T-PLACES DROP T-PLACE-GONE',
            '_TSET @ EXPL-NEW',
            'VARIABLE _TW  DUP _TW !',
            '_TW @ WDG-REVISION',
            'T-VFS-NEW S" away" PLACES-VOLUME THROW PVOL-ATTACH THROW',
            '_TW @ WDG-DRAW',
            '_TW @ WDG-REVISION SWAP - 0> .',
            '_TW @ EXPL-TREE _TW-W !',
            '_TP-GONE @ _EXPL-LABEL TYPE SPACE 8888 .',
            _EXPL_CLEANUP], "-1 Card 8888")


def test_expl_read_only_place_refuses_changes():
    """New, rename and delete do nothing in a read-only place."""
    check("no new entry, no rename input, no delete question",
        _EXPL_SETUP[:-2] + [
            'DROP _TV @ T-PLACES DROP T-PLACE-RO',
            '_TSET @ EXPL-NEW',
            'VARIABLE _TW  DUP _TW !',
            # Rows: Files, ro.  Select ro, then try each change.
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-SELECTED _TP-RO @ = . .',
            '_TW @ EXPL-NEW-FILE  _TW @ EXPL-NEW-DIR',
            'S" /src/newfile" _TV @ VFS-RESOLVE .  S" /src/newfolder" _TV @ VFS-RESOLVE .',
            '_TW @ EXPL-RENAME  _TW @ 88 + @ 2 AND .',
            '_TW @ EXPL-DELETE  _TW @ 104 + @ .',
            # The same folder is writable through the place over the root.
            'KEY-UP T-KEY _EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-NEW-FILE  S" /newfile" _TV @ VFS-RESOLVE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 0 0 0 0 0 -1 8888")


def test_expl_rename_and_delete_go_through_the_place():
    """A rename commits in the entry's place; the name limit is the volume's."""
    check("rename hello.f through the widget's commit",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TP @ TREE-EXPAND',
            # Rows: Files, notes.txt, hello.f, src, docs
            'KEY-DOWN T-KEY _EV _TW @ WDG-HANDLE DROP  _EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-RENAME',
            'S" hi.f" _TW @ 80 + @ INP-SET-TEXT',
            '_TW @ 80 + @ _EXPL-RENAME-COMMIT',
            'S" /hi.f" _TV @ VFS-RESOLVE 0<> .  S" /hello.f" _TV @ VFS-RESOLVE .',
            '_TW @ 88 + @ 2 AND . 8888 .',
            _EXPL_CLEANUP], "-1 0 0 8888")
