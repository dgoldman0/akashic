#!/usr/bin/env python3
"""Test suite for the game library's camera and collision map
(game/2d/camera.f and game/2d/collide.f).

Runs Forth test code through the Megapad-64 emulator and validates
correctness by parsing structured UART output.  The checks came from the
suites of the retired terminal half (archive/game-terminal-half-550fbf48-
20261123), which loaded these two logic modules beside it.
"""
import os, sys, tempfile, re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import MP64FS, FTYPE_FORTH

sys.path.insert(0, SCRIPT_DIR)
from forth_disk import kdos_diagnostics, module_disk_files  # noqa: E402

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Disk files (dependency order) ──────────────────────────────
# The modules the suite loads and their REQUIRE closure, each in its own
# directory on the disk, so the disk follows what the modules require.
DISK_FILES = module_disk_files((
    "game/2d/collide.f",
    "game/2d/camera.f",
))

# ── Forth test harness ─────────────────────────────────────────
FORTH_HARNESS = r"""\ =====================================================================
\  test_game_2d_suite.f — Tests for game/2d/camera.f and collide.f
\ =====================================================================

\ ── Minimal test harness ─────────────────────────────────────

VARIABLE _T-PASS   0 _T-PASS !
VARIABLE _T-FAIL   0 _T-FAIL !
VARIABLE _T-NAME-A
VARIABLE _T-NAME-U

: T-NAME  _T-NAME-U ! _T-NAME-A ! ;

: T-ASSERT  ( actual expected -- )
    2DUP = IF
        2DROP
        _T-PASS @ 1+ _T-PASS !
        ." PASS: " _T-NAME-A @ _T-NAME-U @ TYPE CR
    ELSE
        ." FAIL: " _T-NAME-A @ _T-NAME-U @ TYPE
        ."  expected=" . ."  got=" . CR
        _T-FAIL @ 1+ _T-FAIL !
    THEN ;

: T-TRUE  ( flag -- )
    0<> IF
        _T-PASS @ 1+ _T-PASS !
        ." PASS: " _T-NAME-A @ _T-NAME-U @ TYPE CR
    ELSE
        ." FAIL: " _T-NAME-A @ _T-NAME-U @ TYPE ."  expected=TRUE got=FALSE" CR
        _T-FAIL @ 1+ _T-FAIL !
    THEN ;

: T-FALSE  ( flag -- )
    0= IF
        _T-PASS @ 1+ _T-PASS !
        ." PASS: " _T-NAME-A @ _T-NAME-U @ TYPE CR
    ELSE
        ." FAIL: " _T-NAME-A @ _T-NAME-U @ TYPE ."  expected=FALSE got=TRUE" CR
        _T-FAIL @ 1+ _T-FAIL !
    THEN ;

: T-SUMMARY
    CR ." === RESULTS ===" CR
    ." PASSED: " _T-PASS @ . CR
    ." FAILED: " _T-FAIL @ . CR
    _T-FAIL @ 0= IF ." ALL-TESTS-PASSED" CR THEN ;

\ ── Load the modules ──────────────────────────────────────────

REQUIRE game/2d/camera.f
REQUIRE game/2d/collide.f

." [MODULES LOADED]" CR

\ ── Pre-declare test state ────────────────────────────────────

\ camera test state
VARIABLE _CAMT-CAM

\ collide test state
VARIABLE _CT-CM


\ =====================================================================
\  §1 — camera.f tests
\ =====================================================================

." --- camera.f ---" CR

\ --- Group A: basic creation and snap ---
100 100 20 15 CAM-NEW _CAMT-CAM !

S" cam:new-returns-nonzero" T-NAME
_CAMT-CAM @ 0<> T-TRUE

S" cam:world-w-stored" T-NAME
_CAMT-CAM @ 0 + @ 100 T-ASSERT

S" cam:world-h-stored" T-NAME
_CAMT-CAM @ 8 + @ 100 T-ASSERT

S" cam:view-w-stored" T-NAME
_CAMT-CAM @ 16 + @ 20 T-ASSERT

S" cam:view-h-stored" T-NAME
_CAMT-CAM @ 24 + @ 15 T-ASSERT

S" cam:initial-x-0" T-NAME
_CAMT-CAM @ 32 + @ 0 T-ASSERT

S" cam:initial-y-0" T-NAME
_CAMT-CAM @ 40 + @ 0 T-ASSERT

S" cam:initial-smooth-0" T-NAME
_CAMT-CAM @ 64 + @ 0 T-ASSERT

_CAMT-CAM @ 50 50 CAM-SNAP

S" cam:snap-sets-x" T-NAME
_CAMT-CAM @ 32 + @ 10240 T-ASSERT

S" cam:snap-sets-y" T-NAME
_CAMT-CAM @ 40 + @ 11008 T-ASSERT

S" cam:snap-sets-target-x" T-NAME
_CAMT-CAM @ 48 + @ 10240 T-ASSERT

\ Diagnostic removed — bug was DUP OVER in CAM-SNAP

S" cam:snap-sets-target-y" T-NAME
_CAMT-CAM @ 56 + @ 11008 T-ASSERT

S" cam:x-returns-integer" T-NAME
_CAMT-CAM @ CAM-X 40 T-ASSERT

S" cam:y-returns-integer" T-NAME
_CAMT-CAM @ CAM-Y 43 T-ASSERT

\ --- Group B: smooth, follow ---
S" cam:smooth!-stores" T-NAME
_CAMT-CAM @ 128 CAM-SMOOTH!
_CAMT-CAM @ 64 + @ 128 T-ASSERT

S" cam:follow-sets-target" T-NAME
_CAMT-CAM @ 60 60 CAM-FOLLOW
_CAMT-CAM @ 48 + @ 12800 T-ASSERT

S" cam:follow-sets-target-y" T-NAME
_CAMT-CAM @ 56 + @ 13568 T-ASSERT

\ --- Group C: tick with fresh camera ---
100 100 20 15 CAM-NEW _CAMT-CAM !

S" cam:tick-instant-x" T-NAME
_CAMT-CAM @ 0 CAM-SMOOTH!
_CAMT-CAM @ 30 30 CAM-SNAP
_CAMT-CAM @ 40 40 CAM-FOLLOW
_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ 32 + @ 7680 T-ASSERT

S" cam:tick-instant-y" T-NAME
_CAMT-CAM @ 40 + @ 8448 T-ASSERT

\ --- Group D: bounds/view ---
S" cam:bounds!-updates" T-NAME
_CAMT-CAM @ 200 150 CAM-BOUNDS!
_CAMT-CAM @ 0 + @ 200 T-ASSERT

S" cam:view!-updates" T-NAME
_CAMT-CAM @ 30 20 CAM-VIEW!
_CAMT-CAM @ 16 + @ 30 T-ASSERT

S" cam:view!-updates-h" T-NAME
_CAMT-CAM @ 24 + @ 20 T-ASSERT

\ --- Group E: clamp (VW=30 VH=20 after view!) ---
S" cam:clamp-negative-x" T-NAME
_CAMT-CAM @ 0 CAM-SMOOTH!
_CAMT-CAM @ 0 0 CAM-SNAP
_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ 32 + @ 0 T-ASSERT

\ --- Group F: shake (fresh camera) ---
100 100 20 15 CAM-NEW _CAMT-CAM !

S" cam:shake-sets-fields" T-NAME
_CAMT-CAM @ 30 30 CAM-SNAP
_CAMT-CAM @ 5 10 CAM-SHAKE
_CAMT-CAM @ 72 + @ 5 T-ASSERT

S" cam:shake-dur-set" T-NAME
_CAMT-CAM @ 80 + @ 10 T-ASSERT

S" cam:shake-decays-on-tick" T-NAME
_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ 80 + @ 9 T-ASSERT

_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ CAM-TICK

S" cam:shake-dur-after-3-ticks" T-NAME
_CAMT-CAM @ 80 + @ 7 T-ASSERT

\ A tick draws its offsets once, so queries within it agree.
S" cam:shake-queries-agree" T-NAME
_CAMT-CAM @ CAM-X _CAMT-CAM @ CAM-X =
_CAMT-CAM @ CAM-Y _CAMT-CAM @ CAM-Y = AND T-TRUE

S" cam:shake-offset-within-amplitude" T-NAME
\ Snapped to (30,30) with a 20 by 15 view, the camera stands at (20,23).
_CAMT-CAM @ CAM-X 20 - DUP -2 >= SWAP 2 <= AND T-TRUE

\ A zero amplitude stops the shake; queries then divide by nothing.
S" cam:zero-amplitude-stops-shake" T-NAME
_CAMT-CAM @ 0 10 CAM-SHAKE
_CAMT-CAM @ 80 + @ 0=  _CAMT-CAM @ CAM-X 20 = AND T-TRUE

S" cam:zero-amplitude-ticks" T-NAME
_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ CAM-X 20 =  _CAMT-CAM @ CAM-Y 23 = AND T-TRUE

\ --- Group G: lerp (fresh camera) ---
200 150 30 20 CAM-NEW _CAMT-CAM !

S" cam:lerp-moves-toward-target" T-NAME
_CAMT-CAM @ 128 CAM-SMOOTH!
_CAMT-CAM @ 50 50 CAM-SNAP
_CAMT-CAM @ 70 70 CAM-FOLLOW
_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ 32 + @ 11520 T-ASSERT

S" cam:lerp-y-moves" T-NAME
_CAMT-CAM @ 40 + @ 12800 T-ASSERT

\ Close to its target a smoothed camera still moves one unit a tick.
S" cam:lerp-near-target-steps-one" T-NAME
_CAMT-CAM @ 48 + @ 1- _CAMT-CAM @ 32 + !
_CAMT-CAM @ 56 + @ 1+ _CAMT-CAM @ 40 + !
_CAMT-CAM @ CAM-TICK
_CAMT-CAM @ 32 + @ _CAMT-CAM @ 48 + @ =
_CAMT-CAM @ 40 + @ _CAMT-CAM @ 56 + @ = AND T-TRUE


\ =====================================================================
\  §2 — collide.f tests
\ =====================================================================

." --- collide.f ---" CR

8 6 CMAP-NEW  _CT-CM !

S" cmap:width" T-NAME
_CT-CM @ CMAP-W 8 T-ASSERT

S" cmap:height" T-NAME
_CT-CM @ CMAP-H 6 T-ASSERT

S" cmap:default-passable" T-NAME
_CT-CM @ 0 0 CMAP-SOLID? T-FALSE

S" cmap:set-solid" T-NAME
_CT-CM @ 3 2 1 CMAP-SET
_CT-CM @ 3 2 CMAP-SOLID? T-TRUE

S" cmap:get-value" T-NAME
_CT-CM @ 3 2 CMAP-GET 1 T-ASSERT

S" cmap:adjacent-passable" T-NAME
_CT-CM @ 4 2 CMAP-SOLID? T-FALSE

S" cmap:fill" T-NAME
_CT-CM @ 2 CMAP-FILL
_CT-CM @ 0 0 CMAP-GET 2 T-ASSERT

S" cmap:fill-corner" T-NAME
_CT-CM @ 7 5 CMAP-GET 2 T-ASSERT

_CT-CM @ 0 CMAP-FILL

S" cmap:oob-col" T-NAME
_CT-CM @ 99 0 CMAP-GET 0 T-ASSERT

S" cmap:oob-row" T-NAME
_CT-CM @ 0 99 CMAP-GET 0 T-ASSERT

S" cmap:oob-negative" T-NAME
_CT-CM @ -1 0 CMAP-GET 0 T-ASSERT

\ ── Geometric primitives ──

S" geom:pt-inside" T-NAME
5 5  2 2 8 8  PT-IN-RECT? T-TRUE

S" geom:pt-outside" T-NAME
1 1  2 2 8 8  PT-IN-RECT? T-FALSE

S" geom:pt-on-left-edge" T-NAME
2 2  2 2 8 8  PT-IN-RECT? T-TRUE

S" geom:pt-on-right-excl" T-NAME
10 5  2 2 8 8  PT-IN-RECT? T-FALSE

S" geom:aabb-overlap" T-NAME
0 0 4 4  2 2 4 4  AABB-OVERLAP? T-TRUE

S" geom:aabb-no-overlap" T-NAME
0 0 2 2  5 5 2 2  AABB-OVERLAP? T-FALSE

S" geom:aabb-touching-no" T-NAME
0 0 2 2  2 0 2 2  AABB-OVERLAP? T-FALSE


\ =====================================================================
\  Summary
\ =====================================================================

T-SUMMARY
"""

AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_game_2d_suite.f
"""


def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf


def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf)


def run_until_idle(sys_obj, max_steps=800_000_000):
    steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        batch = sys_obj.run_batch(min(5_000_000, max_steps - steps))
        steps += max(batch, 1)
    return steps


def build_disk(img_path):
    fs = MP64FS(total_sectors=4096)
    fs.format()

    kdos_src = open(KDOS_PATH, "rb").read()
    fs.inject_file("kdos.f", kdos_src, ftype=FTYPE_FORTH, flags=0x02)

    dirs_made = set()
    for _, disk_dir, _ in DISK_FILES:
        parts = disk_dir.strip("/").split("/")
        for i in range(len(parts)):
            d = "/" + "/".join(parts[:i+1])
            if d not in dirs_made:
                fs.mkdir(d.lstrip("/"))
                dirs_made.add(d)

    for name, disk_dir, host_path in DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)

    test_src = FORTH_HARNESS.encode("utf-8")
    fs.inject_file("test_game_2d_suite.f", test_src, ftype=FTYPE_FORTH)

    auto_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", auto_src, ftype=FTYPE_FORTH)

    fs.save(img_path)


def main():
    tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False)
    img_path = tmp.name
    tmp.close()

    try:
        build_disk(img_path)
        print("[*] Assembling BIOS...")
        with open(BIOS_PATH) as f:
            bios_code = assemble(f.read())

        sys_emu = MegapadSystem(ram_size=1024*1024,
                                ext_mem_size=16*(1 << 20),
                                storage_image=img_path)
        buf = capture_uart(sys_emu)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        print("[*] Running test suite...")
        steps = run_until_idle(sys_emu)
        text = uart_text(buf)

        print(f"[*] Completed in {steps:,} steps\n")

        # Parse results
        pass_lines = re.findall(r'^PASS: (.+)$', text, re.MULTILINE)
        fail_lines = re.findall(r'^FAIL: (.+)$', text, re.MULTILINE)

        for p in pass_lines:
            print(f"  \u2713 {p}")
        for f_line in fail_lines:
            print(f"  \u2717 {f_line}")

        print()

        # Check for fatal errors (only after [MODULES LOADED])
        fatal = False
        diagnostics = kdos_diagnostics(text)
        if diagnostics:
            print(f"[!] KDOS reported: {', '.join(diagnostics)}")
            fatal = True
        test_section = text[text.find("[MODULES LOADED]"):] if "[MODULES LOADED]" in text else text
        for err_pat in ["ABORT", "STACK"]:
            if err_pat.lower() in test_section.lower():
                idx = test_section.lower().find(err_pat.lower())
                ctx = test_section[max(0, idx-120):idx+120]
                print(f"[!] Fatal: '{err_pat}' detected near: ...{ctx}...")
                fatal = True

        # Extract summary
        m_passed = re.search(r'PASSED:\s*(\d+)', text)
        m_failed = re.search(r'FAILED:\s*(\d+)', text)
        n_passed = int(m_passed.group(1)) if m_passed else 0
        n_failed = int(m_failed.group(1)) if m_failed else -1

        print(f"  Total: {n_passed} passed, {n_failed} failed")

        if "ALL-TESTS-PASSED" in text and not fatal:
            print("\n[\u2713] ALL TESTS PASSED")
            rc = 0
        else:
            print(f"\n[\u2717] TEST FAILURES")
            rc = 1

        if fatal or n_failed != 0:
            print("\n--- UART tail (last 1200 chars) ---")
            print(text[-1200:])

    finally:
        os.unlink(img_path)

    return rc


def test_suite() -> None:
    """The suite as a test, so the test selection tool runs it."""
    assert main() == 0


if __name__ == "__main__":
    sys.exit(main())
