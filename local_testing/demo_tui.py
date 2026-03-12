#!/usr/bin/env python3
"""Interactive TUI demo — builds a disk image with the full TUI stack,
boots the emulator from disk, and opens a pygame display window.

The BIOS auto-loads kdos.f from disk.  KDOS runs autoexec.f which
loads test_tui.f — a dashboard demo that exercises every TUI widget.

Usage:
    python local_testing/demo_tui.py [--scale N]

Keyboard (in the TUI):
    Tab         — cycle focus between widgets
    Arrow keys  — navigate within the focused widget
    Enter       — activate
    Escape      — close dropdown / dialog
    Ctrl+C      — quit
"""
import argparse
import os
import select
import sys
import tempfile
import termios
import time
import tty

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
TUI_DIR    = os.path.join(ROOT_DIR, "akashic", "tui")

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble                      # noqa: E402
from system import MegapadSystem              # noqa: E402
from diskutil import MP64FS, FTYPE_FORTH      # noqa: E402

# ---------------------------------------------------------------------------
#  Disk layout:
#    /kdos.f          — auto-loaded by BIOS (first FTYPE_FORTH file)
#    /autoexec.f      — auto-run by KDOS after boot
#    /text/utf8.f     — dependency of ansi.f
#    /tui/ansi.f      — TUI layer 0
#    /tui/keys.f      — TUI layer 0
#    /tui/cell.f      — TUI layer 1
#    /tui/screen.f    — TUI layer 1
#    /tui/draw.f      — TUI layer 2
#    /tui/box.f       — TUI layer 2
#    /tui/region.f    — TUI layer 3
#    /tui/layout.f    — TUI layer 3
#    /tui/widget.f    — TUI layer 4
#    /tui/label.f     — TUI layer 4
#    /tui/progress.f  — TUI layer 4
#    /tui/input.f     — TUI layer 4
#    /tui/list.f      — TUI layer 4
#    /tui/tabs.f      — TUI layer 4
#    /tui/menu.f      — TUI layer 4
#    /tui/dialog.f    — TUI layer 4
#    /test_tui.f      — demo application
# ---------------------------------------------------------------------------

# Mapping: (disk-name, disk-dir, host-path)
TUI_DISK_FILES = [
    ("utf8.f",     "/text", os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")),
    ("ansi.f",     "/tui",  os.path.join(TUI_DIR, "ansi.f")),
    ("keys.f",     "/tui",  os.path.join(TUI_DIR, "keys.f")),
    ("cell.f",     "/tui",  os.path.join(TUI_DIR, "cell.f")),
    ("screen.f",   "/tui",  os.path.join(TUI_DIR, "screen.f")),
    ("draw.f",     "/tui",  os.path.join(TUI_DIR, "draw.f")),
    ("box.f",      "/tui",  os.path.join(TUI_DIR, "box.f")),
    ("region.f",   "/tui",  os.path.join(TUI_DIR, "region.f")),
    ("layout.f",   "/tui",  os.path.join(TUI_DIR, "layout.f")),
    ("widget.f",   "/tui",  os.path.join(TUI_DIR, "widget.f")),
    ("label.f",    "/tui",  os.path.join(TUI_DIR, "label.f")),
    ("progress.f", "/tui",  os.path.join(TUI_DIR, "progress.f")),
    ("input.f",    "/tui",  os.path.join(TUI_DIR, "input.f")),
    ("list.f",     "/tui",  os.path.join(TUI_DIR, "list.f")),
    ("tabs.f",     "/tui",  os.path.join(TUI_DIR, "tabs.f")),
    ("menu.f",     "/tui",  os.path.join(TUI_DIR, "menu.f")),
    ("dialog.f",   "/tui",  os.path.join(TUI_DIR, "dialog.f")),
]

# ---------------------------------------------------------------------------
#  test_tui.f — the demo Forth program that lives on disk
# ---------------------------------------------------------------------------

TEST_TUI_F = r"""\ test_tui.f — Akashic TUI Dashboard Demo
\ Loaded by autoexec.f via LOAD test_tui.f
\ Requires the full TUI stack.

REQUIRE tui/layout.f
REQUIRE tui/label.f
REQUIRE tui/progress.f
REQUIRE tui/input.f
REQUIRE tui/list.f
REQUIRE tui/tabs.f
REQUIRE tui/menu.f
REQUIRE tui/dialog.f

\ --- Helper: copy transient S" string to ALLOCATEd buffer ---
VARIABLE _sd-src   VARIABLE _sd-len   VARIABLE _sd-dst
: _SDUP  ( c-addr u -- new-addr u )
    _sd-len !  _sd-src !
    _sd-len @ ALLOCATE 0<> ABORT" _SDUP alloc"
    _sd-dst !
    _sd-src @ _sd-dst @ _sd-len @ CMOVE
    _sd-dst @ _sd-len @ ;

\ --- Helper: store (addr u) pair at base+offset ---
VARIABLE _p-base   VARIABLE _p-off
: _PAIR!  ( addr u base offset -- )
    _p-off !  _p-base !
    _p-base @ _p-off @ + 8 + !
    _p-base @ _p-off @ + ! ;

\ --- Screen setup ---
ANSI-CLEAR ANSI-HOME ANSI-CURSOR-OFF
80 24 SCR-NEW CONSTANT _scr
_scr SCR-USE
SCR-CLEAR

\ --- Root region  (full 80x24 screen) ---
0 0 24 80 RGN-NEW CONSTANT _root

\ --- Top-level vertical layout ---
\    row 0        : title bar (1 row)
\    rows 1..22   : body (expand)
\    row 23       : status bar (1 row)
_root LAY-VERTICAL 0 LAY-NEW CONSTANT _vlay
_vlay 1 1 LAY-ADD CONSTANT _rgn-title
_vlay 0 1 LAY-ADD CONSTANT _rgn-body
_vlay 1 1 LAY-ADD CONSTANT _rgn-status
LAY-F-EXPAND _vlay LAY-FLAGS!
_vlay LAY-COMPUTE

\ --- Body: horizontal split  left(30) | right(expand) ---
_rgn-body LAY-HORIZONTAL 1 LAY-NEW CONSTANT _hlay
_hlay 30 30 LAY-ADD CONSTANT _rgn-left
_hlay  0  1 LAY-ADD CONSTANT _rgn-right
LAY-F-EXPAND _hlay LAY-FLAGS!
_hlay LAY-COMPUTE

\ --- Right panel: upper info(8) | lower console(expand) ---
_rgn-right LAY-VERTICAL 0 LAY-NEW CONSTANT _rlay
_rlay 8 8 LAY-ADD CONSTANT _rgn-info
_rlay 0 1 LAY-ADD CONSTANT _rgn-console-box
LAY-F-EXPAND _rlay LAY-FLAGS!
_rlay LAY-COMPUTE

\ ======================================================================
\  Title bar  (static — just drawn once, not a widget)
\ ======================================================================
7 DRW-FG!  4 DRW-BG!  CELL-A-BOLD DRW-ATTR!
0x20 _rgn-title RGN-ROW _rgn-title RGN-COL 1 80 DRW-FILL-RECT
S" Akashic TUI Dashboard" _rgn-title RGN-ROW 1 78 DRW-TEXT-CENTER
0 DRW-BG!  0 DRW-ATTR!  7 DRW-FG!

\ ======================================================================
\  Left panel — bordered list
\ ======================================================================
6 DRW-FG!  0 DRW-BG!  0 DRW-ATTR!
BOX-SINGLE _rgn-left RGN-ROW _rgn-left RGN-COL _rgn-left RGN-H _rgn-left RGN-W BOX-DRAW
CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
S" Navigation" _rgn-left RGN-ROW _rgn-left RGN-COL 2 + _rgn-left RGN-W 4 - DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!

\ Inner region (inset 1 from box edges)
_rgn-left 1 1 _rgn-left RGN-H 2 - _rgn-left RGN-W 2 - RGN-SUB CONSTANT _rgn-list

\ 8 list items — (addr,len) pairs = 128 bytes
128 ALLOCATE 0<> ABORT" alloc"  CONSTANT _litems
S" Dashboard"   _SDUP  _litems   0 _PAIR!
S" Settings"    _SDUP  _litems  16 _PAIR!
S" Network"     _SDUP  _litems  32 _PAIR!
S" Storage"     _SDUP  _litems  48 _PAIR!
S" Performance" _SDUP  _litems  64 _PAIR!
S" Security"    _SDUP  _litems  80 _PAIR!
S" Logs"        _SDUP  _litems  96 _PAIR!
S" About"       _SDUP  _litems 112 _PAIR!

_rgn-list _litems 8 LST-NEW CONSTANT _lst

\ ======================================================================
\  Right upper — System Status info box
\ ======================================================================
6 DRW-FG!  0 DRW-BG!  0 DRW-ATTR!
BOX-ROUND _rgn-info RGN-ROW _rgn-info RGN-COL _rgn-info RGN-H _rgn-info RGN-W BOX-DRAW
CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
S" System Status" _rgn-info RGN-ROW _rgn-info RGN-COL 2 + _rgn-info RGN-W 4 - DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!

_rgn-info 1 1 _rgn-info RGN-H 2 - _rgn-info RGN-W 2 - RGN-SUB CONSTANT _rgn-info-in

\ Labels
_rgn-info-in 0 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-cpu
_r-cpu S" CPU: Megapad-64 @ 100MHz" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-cpu

_rgn-info-in 1 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-mem
_r-mem S" RAM: 1024 KiB / XMEM: 16 MiB" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-mem

_rgn-info-in 2 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-upt
_r-upt S" Uptime: 0d 0h 0m 42s" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-upt

\ Progress bar label + bar
2 DRW-FG!
_rgn-info-in 4 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-loadlbl
_r-loadlbl S" Load: 67%" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-load
7 DRW-FG!

_rgn-info-in 5 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-pbar
_r-pbar 100 PRG-BAR PRG-NEW CONSTANT _prg-load
_prg-load 67 PRG-SET

\ ======================================================================
\  Right lower — Console box with input
\ ======================================================================
6 DRW-FG!  0 DRW-BG!  0 DRW-ATTR!
BOX-SINGLE _rgn-console-box RGN-ROW _rgn-console-box RGN-COL _rgn-console-box RGN-H _rgn-console-box RGN-W BOX-DRAW
CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
S" Console" _rgn-console-box RGN-ROW _rgn-console-box RGN-COL 2 + _rgn-console-box RGN-W 4 - DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!

_rgn-console-box 1 1 _rgn-console-box RGN-H 2 - _rgn-console-box RGN-W 2 - RGN-SUB CONSTANT _rgn-con

\ Prompt label
3 DRW-FG!
_rgn-con 0 0 1 _rgn-con RGN-W RGN-SUB CONSTANT _r-prompt
_r-prompt S" Enter command:" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-prompt
7 DRW-FG!

\ Input field  (128-byte buffer)
128 ALLOCATE 0<> ABORT" alloc"  CONSTANT _inp-buf
_rgn-con 1 0 1 _rgn-con RGN-W RGN-SUB CONSTANT _r-inp
_r-inp _inp-buf 128 INP-NEW CONSTANT _inp
S" type here..." _SDUP _inp INP-SET-PLACEHOLDER

\ Welcome message label
_rgn-con 3 0 _rgn-con RGN-H 3 - _rgn-con RGN-W RGN-SUB CONSTANT _r-output
_r-output S" Welcome to Akashic TUI demo." _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-out

\ ======================================================================
\  Status bar  (static)
\ ======================================================================
7 DRW-FG!  0 DRW-BG!  CELL-A-DIM DRW-ATTR!
S" Tab=focus  Arrows=nav  Enter=act  Esc=close" _rgn-status RGN-ROW _rgn-status RGN-COL 1 + 78 DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!

\ ======================================================================
\  Draw all widgets (initial)
\ ======================================================================
_lst WDG-DRAW
_lbl-cpu WDG-DRAW   _lbl-mem WDG-DRAW   _lbl-upt WDG-DRAW
_lbl-load WDG-DRAW  _prg-load WDG-DRAW
_lbl-prompt WDG-DRAW  _inp WDG-DRAW  _lbl-out WDG-DRAW
SCR-FLUSH

\ ======================================================================
\  Focus management  (Tab-cycles between list / input)
\ ======================================================================
VARIABLE _wdg-cnt   VARIABLE _wdg-cur
CREATE _wdg-tab  16 ALLOT
_lst  _wdg-tab 0 + !
_inp  _wdg-tab 8 + !
2 _wdg-cnt !   0 _wdg-cur !

: _CUR-WDG  ( -- widget )
    _wdg-cur @ 8 * _wdg-tab + @ ;

: _GIVE-FOCUS  ( widget -- )
    DUP DUP WDG-FLAGS WDG-F-FOCUSED OR SWAP _WDG-FLAGS!
    WDG-DIRTY ;

: _TAKE-FOCUS  ( widget -- )
    DUP DUP WDG-FLAGS WDG-F-FOCUSED INVERT AND SWAP _WDG-FLAGS!
    WDG-DIRTY ;

: _CYCLE-FOCUS  ( -- )
    _CUR-WDG _TAKE-FOCUS
    _wdg-cur @ 1 +  DUP _wdg-cnt @ < IF
        _wdg-cur !
    ELSE DROP  0 _wdg-cur !
    THEN
    _CUR-WDG _GIVE-FOCUS ;

\ Start with list focused
_CUR-WDG _GIVE-FOCUS

\ ======================================================================
\  Redraw + event loop
\ ======================================================================
CREATE _EV 24 ALLOT

: _REDRAW-DIRTY  ( -- )
    _lst WDG-DIRTY?  IF _lst WDG-DRAW THEN
    _lbl-cpu WDG-DIRTY?  IF _lbl-cpu WDG-DRAW THEN
    _lbl-mem WDG-DIRTY?  IF _lbl-mem WDG-DRAW THEN
    _lbl-upt WDG-DIRTY?  IF _lbl-upt WDG-DRAW THEN
    _lbl-load WDG-DIRTY? IF _lbl-load WDG-DRAW THEN
    _prg-load WDG-DIRTY? IF _prg-load WDG-DRAW THEN
    _lbl-prompt WDG-DIRTY? IF _lbl-prompt WDG-DRAW THEN
    _inp WDG-DIRTY?  IF _inp WDG-DRAW THEN
    _lbl-out WDG-DIRTY? IF _lbl-out WDG-DRAW THEN
    SCR-FLUSH ;

\ _DRAW-FRAME ( -- )
\   Redraw the entire static frame: title bar, boxes, titles, status bar.
\   Then mark all widgets dirty so _REDRAW-DIRTY will repaint them.
: _DRAW-FRAME  ( -- )
    SCR-CLEAR  _scr SCR-USE
    \ Title bar
    7 DRW-FG!  4 DRW-BG!  CELL-A-BOLD DRW-ATTR!
    0x20 _rgn-title RGN-ROW _rgn-title RGN-COL 1 80 DRW-FILL-RECT
    S" Akashic TUI Dashboard" _rgn-title RGN-ROW 1 78 DRW-TEXT-CENTER
    0 DRW-BG!  0 DRW-ATTR!  7 DRW-FG!
    \ Left panel box + title
    6 DRW-FG!
    BOX-SINGLE _rgn-left RGN-ROW _rgn-left RGN-COL _rgn-left RGN-H _rgn-left RGN-W BOX-DRAW
    CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
    S" Navigation" _rgn-left RGN-ROW _rgn-left RGN-COL 2 + _rgn-left RGN-W 4 - DRW-TEXT-CENTER
    0 DRW-ATTR!  7 DRW-FG!
    \ Info box + title
    6 DRW-FG!
    BOX-ROUND _rgn-info RGN-ROW _rgn-info RGN-COL _rgn-info RGN-H _rgn-info RGN-W BOX-DRAW
    CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
    S" System Status" _rgn-info RGN-ROW _rgn-info RGN-COL 2 + _rgn-info RGN-W 4 - DRW-TEXT-CENTER
    0 DRW-ATTR!  7 DRW-FG!
    \ Console box + title
    6 DRW-FG!
    BOX-SINGLE _rgn-console-box RGN-ROW _rgn-console-box RGN-COL _rgn-console-box RGN-H _rgn-console-box RGN-W BOX-DRAW
    CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
    S" Console" _rgn-console-box RGN-ROW _rgn-console-box RGN-COL 2 + _rgn-console-box RGN-W 4 - DRW-TEXT-CENTER
    0 DRW-ATTR!  7 DRW-FG!
    \ Status bar
    7 DRW-FG!  0 DRW-BG!  CELL-A-DIM DRW-ATTR!
    S" Tab=focus  Arrows=nav  Enter=act  Esc=close" _rgn-status RGN-ROW _rgn-status RGN-COL 1 + 78 DRW-TEXT-CENTER
    0 DRW-ATTR!  7 DRW-FG!
    \ Mark all widgets dirty
    _lst WDG-DIRTY  _lbl-cpu WDG-DIRTY  _lbl-mem WDG-DIRTY
    _lbl-upt WDG-DIRTY  _lbl-load WDG-DIRTY  _prg-load WDG-DIRTY
    _lbl-prompt WDG-DIRTY  _inp WDG-DIRTY  _lbl-out WDG-DIRTY ;

VARIABLE _quit

: _DEMO-LOOP  ( -- )
    0 _quit !
    BEGIN
        _EV KEY-READ DROP

        _EV @ KEY-T-SPECIAL = IF
            _EV 8 + @ KEY-ESC = IF
                -1 _quit !
            THEN
            _EV 8 + @ KEY-TAB = IF
                _CYCLE-FOCUS
            THEN
            _EV 8 + @ KEY-ENTER = IF
                _CUR-WDG _lst = IF
                    S" Not implemented yet." DLG-INFO
                    _DRAW-FRAME
                    _REDRAW-DIRTY
                THEN
            THEN
        THEN

        _quit @ 0= IF
            _EV _CUR-WDG WDG-HANDLE DROP
            _REDRAW-DIRTY
        THEN

        _quit @
    UNTIL
    ANSI-CLEAR ANSI-HOME ANSI-CURSOR-ON
    S" [TUI] Demo exited. Back to REPL." TYPE CR ;

_DEMO-LOOP
"""

# Minimal dummy library — just a PROVIDED, nothing else.
# Used to test whether REQUIRE/PROVIDED chain works at all.
DUMMY_F = "PROVIDED akashic-dummy\n"

# autoexec.f — run by KDOS after boot
# Currently reduced to bare-minimum REQUIRE test for debugging.
AUTOEXEC_F = r"""\ autoexec.f — boot script
ENTER-USERLAND
LOAD test_tui.f
"""

# ---------------------------------------------------------------------------
#  Build disk image
# ---------------------------------------------------------------------------

def build_disk_image(img_path: str):
    """Create an MP64FS disk image with kdos.f + TUI stack + demo."""
    print("[*] Building disk image...")

    # Use 4096 sectors (2 MiB) — plenty of room
    fs = MP64FS(total_sectors=4096)
    fs.format()

    # 1. kdos.f — must be first Forth file (BIOS auto-loads it)
    kdos_src = open(KDOS_PATH, "rb").read()
    fs.inject_file("kdos.f", kdos_src, ftype=FTYPE_FORTH, flags=0x02)
    print(f"  kdos.f ({len(kdos_src):,} bytes)")

    # 2. Create directories
    fs.mkdir("text")
    fs.mkdir("tui")

    # 3. TUI source files
    for name, disk_dir, host_path in TUI_DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)
        print(f"  {disk_dir}/{name} ({len(src):,} bytes)")

    # 4. test_tui.f — the demo application
    demo_src = TEST_TUI_F.encode("utf-8")
    fs.inject_file("test_tui.f", demo_src, ftype=FTYPE_FORTH)
    print(f"  test_tui.f ({len(demo_src):,} bytes)")

    # 5. dummy.f — blank library for REQUIRE/PROVIDED isolation test
    dummy_src = DUMMY_F.encode("utf-8")
    fs.inject_file("dummy.f", dummy_src, ftype=FTYPE_FORTH)
    print(f"  dummy.f ({len(dummy_src):,} bytes)")

    # 6. autoexec.f — auto-run by KDOS
    autoexec_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", autoexec_src, ftype=FTYPE_FORTH)
    print(f"  autoexec.f ({len(autoexec_src):,} bytes)")

    fs.save(img_path)
    info = fs.info()
    print(f"[*] Disk image: {img_path}")
    print(f"    {info['files']} files, "
          f"{info['free_sectors']} free sectors")
    return img_path

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Akashic TUI demo (disk boot)")
    parser.add_argument("--scale", type=int, default=2,
                        help="Display scale factor (default: 2)")
    parser.add_argument("--no-display", action="store_true",
                        help="Run headless (print UART to stdout)")
    parser.add_argument("--keep-image", action="store_true",
                        help="Keep the disk image after exit")
    args = parser.parse_args()

    # -- Build disk image in a temp file --
    if args.keep_image:
        img_path = os.path.join(SCRIPT_DIR, "demo_tui.img")
    else:
        tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False,
                                          dir=SCRIPT_DIR)
        img_path = tmp.name
        tmp.close()

    try:
        build_disk_image(img_path)

        # -- Assemble BIOS --
        print("[*] Assembling BIOS...")
        with open(BIOS_PATH) as f:
            bios_code = assemble(f.read())

        # -- Create system with storage --
        sys_emu = MegapadSystem(ram_size=1024*1024,
                                ext_mem_size=16 * (1 << 20),
                                storage_image=img_path)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        # -- Wire UART TX to stdout --
        out_fd = sys.stdout.fileno()
        sys_emu.uart.on_tx = lambda b: os.write(out_fd, bytes([b]))

        # -- Start display --
        display = None
        if not args.no_display:
            try:
                from display import FramebufferDisplay
                def _on_close():
                    sys_emu.cpu.halted = True
                    print("\n[display] Window closed.")
                display = FramebufferDisplay(sys_emu, scale=args.scale,
                                             title="Akashic TUI Demo",
                                             on_close=_on_close)
                display.start()
                print(f"[display] Window opened (scale={args.scale}x)")
            except ImportError as e:
                print(f"[display] pygame not available: {e}",
                      file=sys.stderr)

        # -- Run: BIOS boots → loads kdos.f → KDOS runs autoexec.f --
        #    → autoexec.f does LOAD test_tui.f → demo event loop
        print("[*] Booting from disk...")

        # Small batch size so the display thread (pygame) gets GIL time
        # between batches to process keyboard events and inject them
        # into the UART RX buffer.  A 50k batch ≈ 0.5ms wall-clock on
        # typical hardware — frequent enough for smooth 60fps rendering
        # in the display thread.
        _BATCH = 50_000

        # -- Set stdin to raw mode for headless keyboard forwarding --
        stdin_fd = sys.stdin.fileno()
        old_termios = termios.tcgetattr(stdin_fd)
        try:
            tty.setraw(stdin_fd)

            while not sys_emu.cpu.halted:
                # Forward stdin keys (headless / no-display mode)
                rlist, _, _ = select.select([stdin_fd], [], [], 0)
                if rlist:
                    raw = os.read(stdin_fd, 64)
                    if raw:
                        if b'\x03' in raw:
                            break
                        sys_emu.uart.inject_input(raw)

                # Also quit if display window was closed
                if display is not None and not display.running:
                    break

                if sys_emu.cpu.idle and not sys_emu.uart.has_rx_data:
                    # CPU is idle (e.g. blocking KEY) — sleep longer
                    # to avoid burning host CPU, let display thread run
                    sys_emu.bus.tick(200_000)
                    sys_emu.cpu.idle = False
                    time.sleep(0.01)
                    continue

                try:
                    sys_emu.run_batch(_BATCH)
                except Exception:
                    break

                # Always yield briefly so the display thread can
                # process pygame events, inject keyboard input, and
                # render.  Without this, the GIL-holding main thread
                # starves the display thread completely.
                time.sleep(0.0001)  # 100µs — negligible but enough
        except KeyboardInterrupt:
            pass
        finally:
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, old_termios)
            if display is not None:
                display.stop()
            print("\n[*] Done.")
    finally:
        if not args.keep_image and os.path.exists(img_path):
            os.unlink(img_path)


if __name__ == "__main__":
    main()
