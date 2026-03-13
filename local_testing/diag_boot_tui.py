#!/usr/bin/env python3
"""Diagnostic: test full TUI demo boot from disk.

Boots the exact same disk image as demo_tui.py, but captures all output
and checks for errors. Then tests KEY-POLL in the demo context.
"""
import os, sys, time, tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
TUI_DIR    = os.path.join(ROOT_DIR, "akashic", "tui")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import MP64FS, FTYPE_FORTH

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")


def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf


def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf)


def inject_line(sys_obj, line):
    sys_obj.uart.inject_input((line + "\r").encode())


def run_until_idle(sys_obj, max_steps=50_000_000, label=""):
    """Run until CPU goes idle or halted."""
    steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(500_000, max_steps - steps))
        steps += max(batch, 1)
    return steps


def run_steps(sys_obj, n):
    done = 0
    while done < n and not sys_obj.cpu.halted:
        batch = sys_obj.run_batch(min(500_000, n - done))
        done += max(batch, 1)
    return done


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
    ("label.f",    "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "label.f")),
    ("progress.f", "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "progress.f")),
    ("input.f",    "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "input.f")),
    ("list.f",     "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "list.f")),
    ("tabs.f",     "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "tabs.f")),
    ("menu.f",     "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "menu.f")),
    ("dialog.f",   "/tui/widgets",  os.path.join(TUI_DIR, "widgets", "dialog.f")),
]

# Same test_tui.f as demo_tui.py, but instead of infinite _DEMO-LOOP,
# we use a bounded loop that also prints markers.
TEST_TUI_DIAG = r"""\ test_tui.f — Akashic TUI Dashboard Demo (DIAGNOSTIC VERSION)
\ Same as demo except _DEMO-LOOP is bounded and prints markers.

REQUIRE tui/layout.f
REQUIRE tui/widgets/label.f
REQUIRE tui/widgets/progress.f
REQUIRE tui/widgets/input.f
REQUIRE tui/widgets/list.f
REQUIRE tui/widgets/tabs.f
REQUIRE tui/widgets/menu.f
REQUIRE tui/widgets/dialog.f

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
80 24 SCR-NEW CONSTANT _scr
_scr SCR-USE
SCR-CLEAR

\ --- Root region ---
0 0 24 80 RGN-NEW CONSTANT _root

\ --- Top-level vertical layout ---
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

\ Title bar
7 DRW-FG!  4 DRW-BG!  CELL-A-BOLD DRW-ATTR!
0x20 _rgn-title RGN-ROW _rgn-title RGN-COL 1 80 DRW-FILL-RECT
S" Akashic TUI Dashboard" _rgn-title RGN-ROW 1 78 DRW-TEXT-CENTER
0 DRW-BG!  0 DRW-ATTR!  7 DRW-FG!

\ Left panel — list
6 DRW-FG!  0 DRW-BG!  0 DRW-ATTR!
BOX-SINGLE _rgn-left RGN-ROW _rgn-left RGN-COL _rgn-left RGN-H _rgn-left RGN-W BOX-DRAW
CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
S" Navigation" _rgn-left RGN-ROW _rgn-left RGN-COL 2 + _rgn-left RGN-W 4 - DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!
_rgn-left 1 1 _rgn-left RGN-H 2 - _rgn-left RGN-W 2 - RGN-SUB CONSTANT _rgn-list

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

\ Right upper — info box
6 DRW-FG!  0 DRW-BG!  0 DRW-ATTR!
BOX-ROUND _rgn-info RGN-ROW _rgn-info RGN-COL _rgn-info RGN-H _rgn-info RGN-W BOX-DRAW
CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
S" System Status" _rgn-info RGN-ROW _rgn-info RGN-COL 2 + _rgn-info RGN-W 4 - DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!
_rgn-info 1 1 _rgn-info RGN-H 2 - _rgn-info RGN-W 2 - RGN-SUB CONSTANT _rgn-info-in

_rgn-info-in 0 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-cpu
_r-cpu S" CPU: Megapad-64 @ 100MHz" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-cpu

_rgn-info-in 1 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-mem
_r-mem S" RAM: 1024 KiB / XMEM: 16 MiB" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-mem

_rgn-info-in 2 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-upt
_r-upt S" Uptime: 0d 0h 0m 42s" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-upt

2 DRW-FG!
_rgn-info-in 4 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-loadlbl
_r-loadlbl S" Load: 67%" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-load
7 DRW-FG!

_rgn-info-in 5 0 1 _rgn-info-in RGN-W RGN-SUB CONSTANT _r-pbar
_r-pbar 100 PRG-BAR PRG-NEW CONSTANT _prg-load
_prg-load 67 PRG-SET

\ Right lower — console box
6 DRW-FG!  0 DRW-BG!  0 DRW-ATTR!
BOX-SINGLE _rgn-console-box RGN-ROW _rgn-console-box RGN-COL _rgn-console-box RGN-H _rgn-console-box RGN-W BOX-DRAW
CELL-A-BOLD DRW-ATTR!  7 DRW-FG!
S" Console" _rgn-console-box RGN-ROW _rgn-console-box RGN-COL 2 + _rgn-console-box RGN-W 4 - DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!
_rgn-console-box 1 1 _rgn-console-box RGN-H 2 - _rgn-console-box RGN-W 2 - RGN-SUB CONSTANT _rgn-con

3 DRW-FG!
_rgn-con 0 0 1 _rgn-con RGN-W RGN-SUB CONSTANT _r-prompt
_r-prompt S" Enter command:" _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-prompt
7 DRW-FG!

128 ALLOCATE 0<> ABORT" alloc"  CONSTANT _inp-buf
_rgn-con 1 0 1 _rgn-con RGN-W RGN-SUB CONSTANT _r-inp
_r-inp _inp-buf 128 INP-NEW CONSTANT _inp
S" type here..." _SDUP _inp INP-SET-PLACEHOLDER

_rgn-con 3 0 _rgn-con RGN-H 3 - _rgn-con RGN-W RGN-SUB CONSTANT _r-output
_r-output S" Welcome to Akashic TUI demo." _SDUP LBL-LEFT LBL-NEW CONSTANT _lbl-out

\ Status bar
7 DRW-FG!  0 DRW-BG!  CELL-A-DIM DRW-ATTR!
S" Tab=focus  Arrows=nav  Enter=act  Esc=close" _rgn-status RGN-ROW _rgn-status RGN-COL 1 + 78 DRW-TEXT-CENTER
0 DRW-ATTR!  7 DRW-FG!

\ Draw all widgets
_lst WDG-DRAW
_lbl-cpu WDG-DRAW   _lbl-mem WDG-DRAW   _lbl-upt WDG-DRAW
_lbl-load WDG-DRAW  _prg-load WDG-DRAW
_lbl-prompt WDG-DRAW  _inp WDG-DRAW  _lbl-out WDG-DRAW
SCR-FLUSH

\ Focus management
VARIABLE _wdg-cnt   VARIABLE _wdg-cur
CREATE _wdg-tab  16 ALLOT
_lst  _wdg-tab 0 + !
_inp  _wdg-tab 8 + !
2 _wdg-cnt !   0 _wdg-cur !

: _CUR-WDG  _wdg-cur @ 8 * _wdg-tab + @ ;
: _GIVE-FOCUS  DUP DUP WDG-FLAGS WDG-F-FOCUSED OR SWAP _WDG-FLAGS!  WDG-DIRTY ;
: _TAKE-FOCUS  DUP DUP WDG-FLAGS WDG-F-FOCUSED INVERT AND SWAP _WDG-FLAGS!  WDG-DIRTY ;
: _CYCLE-FOCUS
    _CUR-WDG _TAKE-FOCUS
    _wdg-cur @ 1 +  DUP _wdg-cnt @ < IF _wdg-cur ! ELSE DROP  0 _wdg-cur ! THEN
    _CUR-WDG _GIVE-FOCUS ;
_CUR-WDG _GIVE-FOCUS

\ Redraw + event processing
CREATE _EV 24 ALLOT

: _REDRAW-DIRTY
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

: _MARK-SETUP  ." DIAG-MARKER-SETUP-OK" CR ; _MARK-SETUP

\ ===  DIAGNOSTIC VERSION of _DEMO-LOOP  ===
\ Instead of AGAIN, loop 5000000 times max. Also counts key events.
\ On exit, print summary.
VARIABLE _keycount
VARIABLE _loopcount
0 _keycount !  0 _loopcount !

: _DEMO-LOOP-DIAG
    ." DIAG-MARKER-LOOP-START" CR
    5000000 0 DO
        _EV KEY-POLL IF
            _keycount @ 1 + _keycount !
            _EV @ KEY-T-SPECIAL = IF
                _EV 8 + @ KEY-TAB = IF _CYCLE-FOCUS THEN
            THEN
            _EV _CUR-WDG WDG-HANDLE DROP
            _REDRAW-DIRTY
        THEN
        _loopcount @ 1 + _loopcount !
    LOOP
    ." DIAG-MARKER-LOOP-END" CR
    ." KEYS=" _keycount @ .
    ." LOOPS=" _loopcount @ .
    CR ;

_DEMO-LOOP-DIAG
"""

AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_tui.f
"""


def build_disk(img_path):
    fs = MP64FS(total_sectors=4096)
    fs.format()

    kdos_src = open(KDOS_PATH, "rb").read()
    fs.inject_file("kdos.f", kdos_src, ftype=FTYPE_FORTH, flags=0x02)

    fs.mkdir("text")
    fs.mkdir("tui")

    for name, disk_dir, host_path in TUI_DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)

    demo_src = TEST_TUI_DIAG.encode("utf-8")
    fs.inject_file("test_tui.f", demo_src, ftype=FTYPE_FORTH)

    autoexec_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", autoexec_src, ftype=FTYPE_FORTH)

    fs.save(img_path)
    return img_path


def main():
    tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False, dir=SCRIPT_DIR)
    img_path = tmp.name
    tmp.close()

    results = []
    passed = failed = 0

    def check(name, cond, detail=""):
        nonlocal passed, failed
        if cond:
            passed += 1
            results.append(f"  PASS  {name}")
        else:
            failed += 1
            results.append(f"  FAIL  {name}  {detail}")

    try:
        build_disk(img_path)
        print("[*] Assembling BIOS...")
        with open(BIOS_PATH) as f:
            bios_code = assemble(f.read())

        sys_emu = MegapadSystem(ram_size=1024*1024,
                                ext_mem_size=16*(1<<20),
                                storage_image=img_path)
        buf = capture_uart(sys_emu)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        # ================================================================
        # Phase 1: Boot KDOS + load test_tui.f (no infinite loop)
        # ================================================================
        print("[*] Phase 1: Boot + TUI stack load...")

        # The bounded _DEMO-LOOP-DIAG runs 5M iterations, which is a LOT
        # of steps. We need many millions of instructions.
        # But! During boot, KDOS loads kdos.f first, then autoexec.f →
        # test_tui.f. test_tui.f loads all 8 TUI modules via REQUIRE.
        # Each REQUIRE = FSLOAD which goes idle when done.
        # After all REQUIREs, the setup code runs, then _DEMO-LOOP-DIAG.

        # Run a lot of steps. The loop runs 5M Forth iterations, each
        # iteration does multiple instructions. Let's run up to 500M
        # emulator steps.
        max_boot = 500_000_000
        steps = 0
        while steps < max_boot:
            if sys_emu.cpu.halted:
                break
            if sys_emu.cpu.idle and not sys_emu.uart.has_rx_data:
                break
            batch = sys_emu.run_batch(min(5_000_000, max_boot - steps))
            steps += max(batch, 1)

        text = uart_text(buf)
        print(f"[*] Phase 1 done: {steps:,} steps, {len(text)} chars output")

        # Check for errors
        has_err = False
        for err_tok in ["? (not found)", "ABORT", "error", "stack"]:
            if err_tok.lower() in text.lower():
                has_err = True
                # Find the error context
                idx = text.lower().find(err_tok.lower())
                ctx = text[max(0,idx-60):idx+80]
                print(f"  [!] Found error near: {ctx!r}")

        check("BOOT-NO-ERRORS", not has_err,
              f"errors in output")

        check("SETUP-OK", "DIAG-MARKER-SETUP-OK" in text,
              f"DIAG-MARKER-SETUP-OK not found in output")

        # The bounded demo loop should have completed, printing markers
        has_loop_start = "DIAG-MARKER-LOOP-START" in text
        has_loop_end = "DIAG-MARKER-LOOP-END" in text
        check("LOOP-STARTED", has_loop_start,
              f"DIAG-MARKER-LOOP-START not found")

        if not has_loop_end and has_loop_start:
            # Loop didn't finish in 500M steps. Run more.
            print("[*] Loop not finished, running more steps...")
            more = 2_000_000_000
            done2 = 0
            while done2 < more:
                if sys_emu.cpu.halted:
                    break
                if sys_emu.cpu.idle and not sys_emu.uart.has_rx_data:
                    break
                batch = sys_emu.run_batch(min(10_000_000, more - done2))
                done2 += max(batch, 1)
            text = uart_text(buf)
            has_loop_end = "DIAG-MARKER-LOOP-END" in text
            steps += done2
            print(f"[*] Extended run: +{done2:,} steps (total {steps:,})")

        check("LOOP-COMPLETED", has_loop_end,
              f"DIAG-MARKER-LOOP-END not found")

        # Extract key/loop counts
        if "KEYS=" in text:
            idx = text.index("KEYS=")
            chunk = text[idx:idx+40]
            print(f"  Counts: {chunk}")
        else:
            print(f"  [!] No KEYS= marker in output")

        # ================================================================
        # Phase 2: If loop finished, now test that KEY-POLL sees injected
        # bytes in the FULL demo context (all widgets loaded).
        # We ask the KDOS prompt to run a quick KEY-POLL test.
        # ================================================================

        if has_loop_end:
            print("[*] Phase 2: KEY-POLL test in full TUI context...")
            buf.clear()
            inject_line(sys_emu,
                ': _FK  500000 0 DO LOOP _EV KEY-POLL . _EV @ . _EV 8 + @ . ; _FK')
            run_steps(sys_emu, 1_000_000)
            sys_emu.uart.inject_input(b'Z')
            run_until_idle(sys_emu, max_steps=100_000_000, label="FK")
            fk_out = uart_text(buf)
            check("FULL-KEYPOLL", "-1 " in fk_out,
                  f"expected '-1' (key found), got: {fk_out!r}")
            check("FULL-KEYCODE", "90 " in fk_out,
                  f"expected '90' (ascii 'Z'), got: {fk_out!r}")
        else:
            print("[*] Skipping Phase 2 (loop didn't complete)")

        # Print last 500 chars of output for debugging
        print()
        print("--- Last 500 chars of UART output ---")
        print(text[-500:])
        print("--- End ---")

    finally:
        os.unlink(img_path)

    print()
    print("=" * 50)
    for r in results:
        print(r)
    print("=" * 50)
    print(f"{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
