#!/usr/bin/env python3
"""Test suite for akashic-tui explorer widget (explorer.f).

Tests the File Explorer widget that bridges tree.f to the VFS layer.
Covers: creation, VFS callbacks, navigation, expand/collapse,
selection callbacks, new file/dir, rename, delete, and cleanup.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# TUI dependency chain
ANSI_F     = os.path.join(ROOT_DIR, "akashic", "tui", "ansi.f")
KEYS_F     = os.path.join(ROOT_DIR, "akashic", "tui", "keys.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
CELL_F     = os.path.join(ROOT_DIR, "akashic", "tui", "cell.f")
SCREEN_F   = os.path.join(ROOT_DIR, "akashic", "tui", "screen.f")
DRAW_F     = os.path.join(ROOT_DIR, "akashic", "tui", "draw.f")
BOX_F      = os.path.join(ROOT_DIR, "akashic", "tui", "box.f")
REGION_F   = os.path.join(ROOT_DIR, "akashic", "tui", "region.f")
LAYOUT_F   = os.path.join(ROOT_DIR, "akashic", "tui", "layout.f")
WIDGET_F   = os.path.join(ROOT_DIR, "akashic", "tui", "widget.f")
LABEL_F    = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "label.f")
PROGRESS_F = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "progress.f")
INPUT_F    = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "input.f")
LIST_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "list.f")
TABS_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "tabs.f")
MENU_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "menu.f")
DIALOG_F   = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "dialog.f")
CANVAS_F   = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "canvas.f")
TREE_F     = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "tree.f")
EXPLORER_F = os.path.join(ROOT_DIR, "akashic", "tui", "widgets", "explorer.f")

# VFS dependency
VFS_F      = os.path.join(ROOT_DIR, "akashic", "utils", "fs", "vfs.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──

_snapshot = None

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_lines(path):
    """Load Forth file, stripping blanks, comments, REQUIRE/PROVIDED."""
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:nl+1] if nl != -1 else data[pos:]

def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf)

def save_cpu_state(cpu):
    return {k: getattr(cpu, k) for k in
            ['pc','psel','xsel','spsel','flag_z','flag_c','flag_n','flag_v',
             'flag_p','flag_g','flag_i','flag_s','d_reg','q_out','t_reg',
             'ivt_base','ivec_id','trap_addr','halted','idle','cycle_count',
             '_ext_modifier']} | {'regs': list(cpu.regs)}

def restore_cpu_state(cpu, state):
    cpu.regs[:] = state['regs']
    for k, v in state.items():
        if k != 'regs':
            setattr(cpu, k, v)

def build_snapshot():
    """Build BIOS+KDOS+TUI+VFS+explorer snapshot."""
    global _snapshot
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + TUI stack + VFS + explorer ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    # TUI stack
    utf8_lines     = _load_forth_lines(UTF8_F)
    ansi_lines     = _load_forth_lines(ANSI_F)
    keys_lines     = _load_forth_lines(KEYS_F)
    cell_lines     = _load_forth_lines(CELL_F)
    screen_lines   = _load_forth_lines(SCREEN_F)
    draw_lines     = _load_forth_lines(DRAW_F)
    box_lines      = _load_forth_lines(BOX_F)
    region_lines   = _load_forth_lines(REGION_F)
    layout_lines   = _load_forth_lines(LAYOUT_F)
    widget_lines   = _load_forth_lines(WIDGET_F)
    label_lines    = _load_forth_lines(LABEL_F)
    progress_lines = _load_forth_lines(PROGRESS_F)
    input_lines    = _load_forth_lines(INPUT_F)
    list_lines     = _load_forth_lines(LIST_F)
    tabs_lines     = _load_forth_lines(TABS_F)
    menu_lines     = _load_forth_lines(MENU_F)
    dialog_lines   = _load_forth_lines(DIALOG_F)
    canvas_lines   = _load_forth_lines(CANVAS_F)
    tree_lines     = _load_forth_lines(TREE_F)

    # VFS
    vfs_lines      = _load_forth_lines(VFS_F)

    # Explorer widget
    explorer_lines = _load_forth_lines(EXPLORER_F)

    # Key event buffer + VFS helper
    helpers = [
        'CREATE _EV 24 ALLOT',
        'VARIABLE _TARN',
        ': T-VFS-NEW  ( -- vfs )',
        '    524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  _TARN !',
        '    _TARN @ VFS-RAM-VTABLE VFS-NEW ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload = "\n".join(
        kdos_lines + ["ENTER-USERLAND"] +
        utf8_lines + ansi_lines + keys_lines +
        cell_lines + screen_lines +
        draw_lines + box_lines +
        region_lines + layout_lines +
        widget_lines + label_lines + progress_lines +
        input_lines + list_lines + tabs_lines + menu_lines +
        dialog_lines + canvas_lines + tree_lines +
        vfs_lines +
        explorer_lines +
        helpers
    ) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    mx = 800_000_000

    while steps < mx:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    errors = False
    for l in text.strip().split('\n'):
        if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower()):
            print(f"  [!] COMPILE ERROR: {l}")
            errors = True
    if errors:
        print("[!] Snapshot has compilation errors — tests may fail.")
        for l in text.strip().split('\n')[-40:]:
            print(f"    {l}")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def _make_system():
    """Create a fresh system restored from snapshot."""
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    return sys_obj


def run_forth(lines, max_steps=50_000_000):
    """Run Forth lines and return printable text."""
    sys_obj = _make_system()
    buf = capture_uart(sys_obj)
    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode()
    pos = 0
    steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)


# ── Test framework ──

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")


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
    # Screen + region
    '24 80 SCR-NEW DUP SCR-USE SCR-CLEAR DRW-STYLE-RESET',
    '0 0 20 40 RGN-NEW',
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

_EXPL_CLEANUP = 'EXPL-FREE RGN-FREE SCR-FREE'


# =====================================================================
#  Tests
# =====================================================================

def test_expl_create():
    """EXPL-NEW creates explorer with type WDG-T-EXPLORER."""
    print("\n── Explorer create ──")
    check("type is WDG-T-EXPLORER (16)",
        _EXPL_SETUP + [
            '_TW @ WDG-TYPE . 8888 .',
            _EXPL_CLEANUP], "16 8888")


def test_expl_tree_embedded():
    """Explorer has an embedded tree widget."""
    print("\n── Explorer embedded tree ──")
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
    print("\n── Explorer VFS accessor ──")
    check("EXPL-VFS matches stored VFS",
        _EXPL_SETUP + [
            '_TW @ EXPL-VFS _TV @ = . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_selected_root():
    """Initially, the root inode is selected."""
    print("\n── Explorer selected (initial) ──")
    check("EXPL-SELECTED = root inode",
        _EXPL_SETUP + [
            '_TW @ EXPL-SELECTED _TV @ V.ROOT @ = . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_leaf_callback():
    """_EXPL-LEAF? returns true for files, false for dirs."""
    print("\n── Explorer leaf callback ──")
    check("root (dir) is not a leaf",
        _EXPL_SETUP + [
            '_TV @ V.ROOT @ _EXPL-LEAF? . 8888 .',
            _EXPL_CLEANUP], "0 8888")
    # Find hello.f — it's a child of root
    check("file is a leaf",
        _EXPL_SETUP + [
            # Ensure children loaded, get first child (notes.txt = file, prepended)
            '_TW @ _EXPL-CUR !',
            '_TV @ V.ROOT @ DUP _TV @ _VFS-ENSURE-CHILDREN',
            '_TV @ V.ROOT @ IN.CHILD @',   # first child = notes.txt
            '_EXPL-LEAF? . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_children_callback():
    """_EXPL-CHILDREN returns first child for dirs, 0 for files."""
    print("\n── Explorer children callback ──")
    # Root is a directory — should have children after ensure
    check("root children non-zero",
        _EXPL_SETUP + [
            '_TW @ _EXPL-CUR !',
            '_TV @ V.ROOT @ _EXPL-CHILDREN 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_next_callback():
    """_EXPL-NEXT returns next sibling."""
    print("\n── Explorer next callback ──")
    check("first child has a sibling",
        _EXPL_SETUP + [
            '_TW @ _EXPL-CUR !',
            '_TV @ V.ROOT @ _EXPL-CHILDREN',
            '_EXPL-NEXT 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_label_callback():
    """_EXPL-LABEL prepends [D] for dirs."""
    print("\n── Explorer label callback ──")
    check("root label starts with [D]",
        _EXPL_SETUP + [
            '_TW @ _EXPL-CUR !',
            '_TV @ V.ROOT @ _EXPL-LABEL',
            '4 MIN TYPE 8888 .',
            _EXPL_CLEANUP], "[D] 8888")


def test_expl_expand_root():
    """Expanding root reveals children in the tree."""
    print("\n── Explorer expand root ──")
    check("expand root → tree shows children",
        _EXPL_SETUP + [
            # Expand root via tree
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "5 8888")  # root + docs + src + hello.f + notes.txt


def test_expl_expand_all():
    """EXPL-EXPAND-ALL shows entire tree."""
    print("\n── Explorer expand all ──")
    check("expand all → 6 visible (root + docs + readme + src + hello.f + notes.txt)",
        _EXPL_SETUP + [
            '_TW @ EXPL-EXPAND-ALL',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "6 8888")


def test_expl_nav_down():
    """Down arrow moves cursor in tree."""
    print("\n── Explorer nav down ──")
    check("down from root → cursor 1",
        _EXPL_SETUP + [
            # First expand root so there are visible children
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
            # Simulate Down key event
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE 80 + @ . 8888 .',  # cursor = offset +80
            _EXPL_CLEANUP], "1 8888")


def test_expl_nav_up():
    """Up arrow moves cursor back."""
    print("\n── Explorer nav up ──")
    check("down then up → cursor 0",
        _EXPL_SETUP + [
            '_TW @ EXPL-TREE _TV @ V.ROOT @ TREE-EXPAND',
            'KEY-T-SPECIAL _EV !  KEY-DOWN _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            'KEY-T-SPECIAL _EV !  KEY-UP _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE 80 + @ . 8888 .',
            _EXPL_CLEANUP], "0 8888")


def test_expl_enter_toggles_dir():
    """Enter on a directory toggles expand/collapse."""
    print("\n── Explorer Enter toggles dir ──")
    # Initially cursor on root. Enter should expand root.
    check("enter on root toggles expand",
        _EXPL_SETUP + [
            'KEY-T-SPECIAL _EV !  KEY-ENTER _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "5 8888")  # root + 4 children


def test_expl_enter_fires_on_open():
    """Enter on a file fires on-open callback."""
    print("\n── Explorer Enter fires on-open ──")
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
    print("\n── Explorer on-select ──")
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
    print("\n── Explorer new file ──")
    check("new file appears in root",
        _EXPL_SETUP + [
            # New file in root (root is selected)
            '_TW @ EXPL-NEW-FILE',
            # Check: "newfile" exists via VFS-RESOLVE 
            'S" newfile" _TV @  VFS-RESOLVE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_new_dir():
    """EXPL-NEW-DIR creates a subdirectory."""
    print("\n── Explorer new dir ──")
    check("new dir appears in root",
        _EXPL_SETUP + [
            '_TW @ EXPL-NEW-DIR',
            'S" newfolder" _TV @  VFS-RESOLVE 0<> . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_new_file_in_subdir():
    """New file is created in the selected directory, not root."""
    print("\n── Explorer new file in subdir ──")
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
    print("\n── Explorer refresh ──")
    check("refresh marks dirty",
        _EXPL_SETUP + [
            '_TW @ WDG-CLEAN',
            '_TW @ EXPL-REFRESH',
            '_TW @ WDG-DIRTY? . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_show_hidden():
    """EXPL-SHOW-HIDDEN! toggles the hidden flag."""
    print("\n── Explorer show-hidden ──")
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
    print("\n── Explorer rename flag ──")
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
    print("\n── Explorer F5 refresh ──")
    check("F5 returns consumed",
        _EXPL_SETUP + [
            '_TW @ WDG-CLEAN',
            'KEY-T-SPECIAL _EV !  KEY-F5 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE . 8888 .',
            _EXPL_CLEANUP], "-1 8888")


def test_expl_handle_f2():
    """F2 key starts rename mode."""
    print("\n── Explorer F2 rename ──")
    check("F2 activates rename",
        _EXPL_SETUP + [
            'KEY-T-SPECIAL _EV !  KEY-F2 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE DROP',
            '_TW @ 88 + @ 2 AND 0<> . 8888 .',  # rename active
            _EXPL_CLEANUP], "-1 8888")


def test_expl_rename_esc_cancels():
    """Escape during rename cancels without changing anything."""
    print("\n── Explorer rename ESC cancels ──")
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
    print("\n── Explorer unrelated key ──")
    check("char 'a' not consumed",
        _EXPL_SETUP + [
            'KEY-T-CHAR _EV !  65 _EV 8 + !  0 _EV 16 + !',
            '_EV _TW @ WDG-HANDLE . 8888 .',
            _EXPL_CLEANUP], "0 8888")


def test_expl_collapse_all():
    """EXPL-COLLAPSE-ALL collapses the tree."""
    print("\n── Explorer collapse all ──")
    check("collapse all → 1 visible",
        _EXPL_SETUP + [
            '_TW @ EXPL-EXPAND-ALL',
            '_TW @ EXPL-COLLAPSE-ALL',
            '_TW @ EXPL-TREE _TREE-VIS-COUNT . 8888 .',
            _EXPL_CLEANUP], "1 8888")


def test_expl_free():
    """EXPL-FREE doesn't crash."""
    print("\n── Explorer free ──")
    check("free completes",
        _EXPL_SETUP + [
            'EXPL-FREE 7777 .',
            'RGN-FREE SCR-FREE'], "7777")


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()

    test_expl_create()
    test_expl_tree_embedded()
    test_expl_vfs_accessor()
    test_expl_selected_root()
    test_expl_leaf_callback()
    test_expl_children_callback()
    test_expl_next_callback()
    test_expl_label_callback()
    test_expl_expand_root()
    test_expl_expand_all()
    test_expl_nav_down()
    test_expl_nav_up()
    test_expl_enter_toggles_dir()
    test_expl_enter_fires_on_open()
    test_expl_on_select()
    test_expl_new_file()
    test_expl_new_dir()
    test_expl_new_file_in_subdir()
    test_expl_refresh()
    test_expl_show_hidden()
    test_expl_rename_flag()
    test_expl_handle_f5()
    test_expl_handle_f2()
    test_expl_rename_esc_cancels()
    test_expl_unrelated_key()
    test_expl_collapse_all()
    test_expl_free()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)
