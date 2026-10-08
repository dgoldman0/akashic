#!/usr/bin/env python3
"""Test suite for akashic-tui explorer widget (explorer.f).

Tests the File Explorer widget that bridges tree.f to the VFS layer.
Covers: creation, VFS callbacks, navigation, expand/collapse,
selection callbacks, new file/dir, rename, delete, and cleanup.
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
#  Explorer widget is created rooted at the VFS root inode.

_EXPL_SETUP = [
    # Screen + region; EXPL-NEW takes the region but leaves it to its
    # caller, so it is kept for cleanup.
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
    'VARIABLE _TR  0 0 20 40 RGN-NEW DUP _TR !',
    # VFS
    'T-VFS-NEW',
    'DUP VFS-USE',
    # Create files/dirs in root (cwd = root after VFS-NEW)
    'S" docs"      VFS-CUR VFS-MKDIR DROP',
    'S" src"       VFS-CUR VFS-MKDIR DROP',
    'S" hello.f"   VFS-CUR VFS-MKFILE DROP',
    'S" notes.txt" VFS-CUR VFS-MKFILE DROP',
    # Create file inside docs/
    'S" docs" VFS-CUR VFS-CD DROP',
    'S" readme" VFS-CUR VFS-MKFILE DROP',
    'S" .." VFS-CUR VFS-CD DROP',
    # Stash VFS handle
    'VARIABLE _TV  VFS-CUR _TV !',
    # Create explorer: ( rgn vfs root-inode -- widget )
    '_TV @ V.ROOT @  EXPL-NEW',
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


def test_expl_vfs_accessor():
    """EXPL-VFS returns the VFS instance."""
    check("EXPL-VFS matches stored VFS",
        _EXPL_SETUP + [
            '_TW @ EXPL-VFS _TV @ = . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_selected_root():
    """Initially, the root inode is selected."""
    check("EXPL-SELECTED = root inode",
        _EXPL_SETUP + [
            '_TW @ EXPL-SELECTED _TV @ V.ROOT @ = . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_leaf_callback():
    """_EXPL-LEAF? returns true for files, false for dirs."""
    check("root (dir) is not a leaf",
        _EXPL_SETUP + [
            '_TV @ V.ROOT @ _EXPL-LEAF? . 8888 .',
            _EXPL_CLEANUP], "0 8888")
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
    check("root children non-zero",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TV @ V.ROOT @ _EXPL-CHILDREN 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_next_callback():
    """_EXPL-NEXT returns next sibling."""
    check("first child has a sibling",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TV @ V.ROOT @ _EXPL-CHILDREN',
            '_EXPL-NEXT 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_label_callback():
    """_EXPL-LABEL returns the inode name; the tree marks directories."""
    check("root label is the inode name",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TW-W !',   # callbacks read the walking tree's context
            '_TV @ V.ROOT @ _EXPL-LABEL',
            '4 MIN TYPE SPACE 8888 .',
            _EXPL_CLEANUP], "/ 8888")


def test_expl_expand_root():
    """Expanding root reveals children in the tree."""
    check("expand root → tree shows children",
        _EXPL_SETUP + [
            # Expand root via tree
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
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
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
            # Simulate Down key event
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE _TREE-SETTLE _TREE-CUR-ROW @ . 8888 .',
            _EXPL_CLEANUP], "1 8888")


def test_expl_nav_up():
    """Up arrow moves cursor back."""
    check("down then up → cursor 0",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
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
            ': _T-ON-OPEN  ( inode expl -- ) DROP IN.TYPE @ _TOI ! ;',
            "' _T-ON-OPEN _TW @ EXPL-ON-OPEN",
            # Expand root and move down once to first child
            # Child order is newest-first (prepended): notes.txt, hello.f, src, docs
            # cursor 1 = notes.txt (a file)
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            # Now press Enter on notes.txt (file → fires on-open)
            'KEY-T-SPECIAL _EV !  KEY-ENTER _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TOI @ . 8888 .',
            _EXPL_CLEANUP], "1 8888")  # VFS-T-FILE = 1


def test_expl_on_select():
    """Navigation fires on-select callback."""
    check("on-select fires on nav",
        _EXPL_SETUP + [
            'VARIABLE _TSI  0 _TSI !',
            ': _T-ON-SEL  ( inode expl -- ) 2DROP 1 _TSI +! ;',
            "' _T-ON-SEL _TW @ EXPL-ON-SELECT",
            # Expand root
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
            # Down arrow → fires on-select
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TSI @ . 8888 .',
            _EXPL_CLEANUP], "1 8888")


def test_expl_new_file():
    """EXPL-NEW-FILE creates a file in the selected directory."""
    check("new file appears in root",
        _EXPL_SETUP + [
            # New file in root (root is selected)
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
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
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
    check("rename sets flag",
        _EXPL_SETUP + [
            '_TW @ EXPL-RENAME',
            '_TW @ 88 + @ 2 AND 0<> . 8888 .',  # flags2 bit 1
            _EXPL_CLEANUP], "-1 8888")
    check("rename creates input widget",
        _EXPL_SETUP + [
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
            'KEY-T-SPECIAL _EV !  KEY-F2 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ 88 + @ 2 AND 0<> . 8888 .',  # rename active
            _EXPL_CLEANUP], "-1 8888")


def test_expl_rename_esc_cancels():
    """Escape during rename cancels without changing anything."""
    check("ESC cancels rename mode",
        _EXPL_SETUP + [
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
