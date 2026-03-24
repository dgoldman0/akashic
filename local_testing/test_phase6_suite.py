#!/usr/bin/env python3
"""Test suite for Phase 6: save.f + map-loader.f

Runs Forth test code through the Megapad-64 emulator and validates
correctness by parsing structured UART output.
"""
import os, sys, tempfile, re, struct

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import MP64FS, FTYPE_FORTH, FTYPE_DATA

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")


# ── CBOR encoder (Python side) for building test map files ─────────
def cbor_uint(n):
    """Encode unsigned integer."""
    if n < 24:
        return bytes([n])
    elif n < 256:
        return bytes([24, n])
    elif n < 65536:
        return bytes([25]) + n.to_bytes(2, 'big')
    elif n < 2**32:
        return bytes([26]) + n.to_bytes(4, 'big')
    else:
        return bytes([27]) + n.to_bytes(8, 'big')

def cbor_tstr(s):
    """Encode text string."""
    b = s.encode('utf-8')
    return cbor_head(3, len(b)) + b

def cbor_bstr(data):
    """Encode byte string."""
    return cbor_head(2, len(data)) + data

def cbor_array(n):
    """Encode array header."""
    return cbor_head(4, n)

def cbor_map(n):
    """Encode map header."""
    return cbor_head(5, n)

def cbor_head(major, n):
    """Encode major type + argument."""
    mt = major << 5
    if n < 24:
        return bytes([mt | n])
    elif n < 256:
        return bytes([mt | 24, n])
    elif n < 65536:
        return bytes([mt | 25]) + n.to_bytes(2, 'big')
    elif n < 2**32:
        return bytes([mt | 26]) + n.to_bytes(4, 'big')
    else:
        return bytes([mt | 27]) + n.to_bytes(8, 'big')


def build_test_map(width, height, tile_ids, cmap_data, spawns, triggers):
    """Build a CBOR-encoded map file for testing.
    
    tile_ids: list of tile ID ints (w*h), one layer
    cmap_data: bytes of w*h collision values
    spawns: list of (id, x, y) tuples
    triggers: list of (id, x, y, w, h, tag) tuples
    """
    # Count entries
    n_entries = 4  # w, h, layers, L0
    if cmap_data:
        n_entries += 1  # cmap
    if spawns:
        n_entries += 1 + len(spawns)  # spawns + SP0..SPn
    if triggers:
        n_entries += 1 + len(triggers)  # triggers + TR0..TRn

    buf = cbor_map(n_entries)
    # width
    buf += cbor_tstr("w") + cbor_uint(width)
    # height
    buf += cbor_tstr("h") + cbor_uint(height)
    # layers
    buf += cbor_tstr("layers") + cbor_uint(1)
    # L0 — tile data as 8-byte LE cells (tile IDs)
    layer_data = b""
    for tid in tile_ids:
        layer_data += tid.to_bytes(8, 'little')
    buf += cbor_tstr("L0") + cbor_bstr(layer_data)
    # cmap
    if cmap_data:
        buf += cbor_tstr("cmap") + cbor_bstr(cmap_data)
    # spawns
    if spawns:
        buf += cbor_tstr("spawns") + cbor_uint(len(spawns))
        for i, (sid, sx, sy) in enumerate(spawns):
            buf += cbor_tstr(f"SP{i}") + cbor_array(3)
            buf += cbor_uint(sid) + cbor_uint(sx) + cbor_uint(sy)
    # triggers
    if triggers:
        buf += cbor_tstr("triggers") + cbor_uint(len(triggers))
        for i, (tid, tx, ty, tw, th, tag) in enumerate(triggers):
            buf += cbor_tstr(f"TR{i}") + cbor_array(6)
            buf += cbor_uint(tid) + cbor_uint(tx) + cbor_uint(ty)
            buf += cbor_uint(tw) + cbor_uint(th) + cbor_uint(tag)

    return buf


# ── Disk files (dependency order) ──────────────────────────────

DISK_FILES = [
    # text
    ("utf8.f", "/text", os.path.join(AK_DIR, "text", "utf8.f")),
    # tui base
    ("ansi.f",      "/tui", os.path.join(AK_DIR, "tui", "ansi.f")),
    ("keys.f",      "/tui", os.path.join(AK_DIR, "tui", "keys.f")),
    ("cell.f",      "/tui", os.path.join(AK_DIR, "tui", "cell.f")),
    ("screen.f",    "/tui", os.path.join(AK_DIR, "tui", "screen.f")),
    ("draw.f",      "/tui", os.path.join(AK_DIR, "tui", "draw.f")),
    ("box.f",       "/tui", os.path.join(AK_DIR, "tui", "box.f")),
    ("region.f",    "/tui", os.path.join(AK_DIR, "tui", "region.f")),
    ("widget.f",    "/tui", os.path.join(AK_DIR, "tui", "widget.f")),
    ("app-desc.f",  "/tui", os.path.join(AK_DIR, "tui", "app-desc.f")),
    # tui widgets needed by game-canvas
    ("canvas.f", "/tui/widgets", os.path.join(AK_DIR, "tui", "widgets", "canvas.f")),
    # cbor
    ("cbor.f",  "/cbor", os.path.join(AK_DIR, "cbor", "cbor.f")),
    # tui game engine
    ("loop.f",    "/tui/game", os.path.join(AK_DIR, "tui", "game", "loop.f")),
    ("input.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "input.f")),
    ("tilemap.f", "/tui/game", os.path.join(AK_DIR, "tui", "game", "tilemap.f")),
    ("sprite.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "sprite.f")),
    ("scene.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "scene.f")),
    # 2d game engine
    ("collide.f", "/game/2d", os.path.join(AK_DIR, "game", "2d", "collide.f")),
    # TUI game components
    ("game-view.f",     "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-view.f")),
    ("game-canvas.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-canvas.f")),
    ("game-applet.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-applet.f")),
    ("atlas.f",         "/tui/game", os.path.join(AK_DIR, "tui", "game", "atlas.f")),
    ("camera.f",        "/game/2d",   os.path.join(AK_DIR, "game", "2d", "camera.f")),
    ("world-render.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "world-render.f")),
    # Phase 6 modules
    ("save.f",       "/game",     os.path.join(AK_DIR, "game", "save.f")),
    ("map-loader.f", "/tui/game", os.path.join(AK_DIR, "tui", "game", "map-loader.f")),
]


# ── Forth test harness ─────────────────────────────────────────
FORTH_HARNESS = r"""\ =====================================================================
\  test_phase6_suite.f — Tests for Phase 6 (save.f + map-loader.f)
\ =====================================================================

\ ── Minimal test harness ─────────────────────────────────────

VARIABLE _T-PASS   0 _T-PASS !
VARIABLE _T-FAIL   0 _T-FAIL !
VARIABLE _T-NAME-A
VARIABLE _T-NAME-U
CREATE _T-NAMEBUF 80 ALLOT

: T-NAME  ( addr u -- )
    80 MIN DUP _T-NAME-U !
    _T-NAMEBUF SWAP CMOVE
    _T-NAMEBUF _T-NAME-A ! ;

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

\ ── Load modules ─────────────────────────────────────────────

REQUIRE game/save.f
REQUIRE tui/game/map-loader.f
REQUIRE tui/game/atlas.f

80 25 SCR-NEW SCR-USE

." [MODULES LOADED]" CR

\ =====================================================================
\  §1 — save.f tests: GSAVE-NEW
\ =====================================================================

." --- save.f ---" CR

VARIABLE _SV-CTX

S" gsave:new-returns-nonzero" T-NAME
GSAVE-NEW DUP _SV-CTX ! 0<> T-TRUE

S" gsave:count-initially-zero" T-NAME
_SV-CTX @ 16 + @ 0 T-ASSERT

S" gsave:eptr-initially-zero" T-NAME
_SV-CTX @ 24 + @ 0 T-ASSERT

\ =====================================================================
\  §2 — save.f tests: accumulate entries
\ =====================================================================

\ Add an integer entry
S" gsave:int-increments-count" T-NAME
_SV-CTX @ S" hp" 42 GSAVE-INT
_SV-CTX @ 16 + @ 1 T-ASSERT

S" gsave:int-advances-eptr" T-NAME
_SV-CTX @ 24 + @ 0> T-TRUE

\ Add a string entry (use CREATE for value to avoid S" transient collision)
CREATE _SV-HERO  104 C, 101 C, 114 C, 111 C,  \ "hero"
S" gsave:str-increments-count" T-NAME
_SV-CTX @ S" name" _SV-HERO 4 GSAVE-STR
_SV-CTX @ 16 + @ 2 T-ASSERT

\ Add a blob entry
CREATE _SV-BLOB-DATA 65 C, 66 C, 67 C, 68 C,
S" gsave:blob-increments-count" T-NAME
_SV-CTX @ S" data" _SV-BLOB-DATA 4 GSAVE-BLOB
_SV-CTX @ 16 + @ 3 T-ASSERT

\ =====================================================================
\  §3 — save.f tests: encode + write + reload round-trip
\ =====================================================================

\ Write to a file
S" gsave:write-returns-0" T-NAME
_SV-CTX @ S" test_save.dat" GSAVE-WRITE 0 T-ASSERT

\ Free save context
_SV-CTX @ GSAVE-FREE

\ Now load it back
VARIABLE _LD-CTX

S" gload:open-returns-nonzero" T-NAME
S" test_save.dat" GLOAD-OPEN DUP _LD-CTX ! 0<> T-TRUE

S" gload:mode-is-1" T-NAME
_LD-CTX @ 40 + @ 1 T-ASSERT

\ Read back the integer
S" gload:int-hp-is-42" T-NAME
_LD-CTX @ S" hp" GLOAD-INT 42 T-ASSERT

\ Read back the string
S" gload:str-name-len-is-4" T-NAME
_LD-CTX @ S" name" GLOAD-STR
DUP 4 T-ASSERT

\ Check the first char is 'h'
S" gload:str-name-starts-with-h" T-NAME
DROP C@ 104 T-ASSERT

\ Read back the blob
S" gload:blob-data-len-is-4" T-NAME
_LD-CTX @ S" data" GLOAD-BLOB
DUP 4 T-ASSERT

S" gload:blob-data-byte0-is-65" T-NAME
DROP C@ 65 T-ASSERT

\ Read a missing key
S" gload:missing-key-returns-0" T-NAME
_LD-CTX @ S" nonexistent" GLOAD-INT 0 T-ASSERT

\ Close (GLOAD-CLOSE leaves nothing on stack)
_LD-CTX @ GLOAD-CLOSE

\ =====================================================================
\  §4 — save.f tests: multiple integers round-trip
\ =====================================================================

VARIABLE _SV2-CTX

GSAVE-NEW _SV2-CTX !
_SV2-CTX @ S" x" 10 GSAVE-INT
_SV2-CTX @ S" y" 20 GSAVE-INT
_SV2-CTX @ S" z" 30 GSAVE-INT
_SV2-CTX @ S" test_save2.dat" GSAVE-WRITE DROP
_SV2-CTX @ GSAVE-FREE

VARIABLE _LD2-CTX
S" test_save2.dat" GLOAD-OPEN _LD2-CTX !

S" gload:multi-int-x" T-NAME
_LD2-CTX @ S" x" GLOAD-INT 10 T-ASSERT

S" gload:multi-int-y" T-NAME
_LD2-CTX @ S" y" GLOAD-INT 20 T-ASSERT

S" gload:multi-int-z" T-NAME
_LD2-CTX @ S" z" GLOAD-INT 30 T-ASSERT

_LD2-CTX @ GLOAD-CLOSE

\ =====================================================================
\  §5 — map-loader.f tests
\ =====================================================================

." --- map-loader.f ---" CR

\ Set up an atlas for tile resolution
VARIABLE _MLT-ATLAS
16 ATLAS-NEW _MLT-ATLAS !
\ Define tile 0 = space, tile 1 = '#' wall, tile 2 = '.' floor
_MLT-ATLAS @ 0 32 7 0 0 ATLAS-DEFINE
_MLT-ATLAS @ 1 35 15 0 0 ATLAS-DEFINE
_MLT-ATLAS @ 2 46 7 0 0 ATLAS-DEFINE

\ Load the test map (injected by Python as testmap.bin)
VARIABLE _MLT-WORLD

S" mload:returns-nonzero" T-NAME
S" testmap.bin" _MLT-ATLAS @ MLOAD
DUP _MLT-WORLD ! 0<> T-TRUE

S" mload:width-is-4" T-NAME
_MLT-WORLD @ MLOAD-W 4 T-ASSERT

S" mload:height-is-3" T-NAME
_MLT-WORLD @ MLOAD-H 3 T-ASSERT

S" mload:nlayers-is-1" T-NAME
_MLT-WORLD @ 16 + @ 1 T-ASSERT

\ Check layer 0 exists
S" mload:layer0-nonzero" T-NAME
_MLT-WORLD @ 0 MLOAD-LAYER 0<> T-TRUE

\ Check tilemap dimensions
VARIABLE _MLT-TMAP
_MLT-WORLD @ 0 MLOAD-LAYER _MLT-TMAP !

S" mload:tmap-w-is-4" T-NAME
_MLT-TMAP @ TMAP-W 4 T-ASSERT

S" mload:tmap-h-is-3" T-NAME
_MLT-TMAP @ TMAP-H 3 T-ASSERT

\ Check tile content: tile (0,0) should be tile ID 1 → '#' = CP 35
S" mload:tile-0-0-cp-is-35" T-NAME
_MLT-TMAP @ 0 0 TMAP-GET CELL-CP@ 35 T-ASSERT

\ Check tile (1,0) = tile ID 2 → '.' = CP 46
S" mload:tile-1-0-cp-is-46" T-NAME
_MLT-TMAP @ 1 0 TMAP-GET CELL-CP@ 46 T-ASSERT

\ Check collision map
S" mload:cmap-nonzero" T-NAME
_MLT-WORLD @ MLOAD-CMAP 0<> T-TRUE

VARIABLE _MLT-CMAP
_MLT-WORLD @ MLOAD-CMAP _MLT-CMAP !

S" mload:cmap-0-0-is-1" T-NAME
_MLT-CMAP @ 0 0 CMAP-GET 1 T-ASSERT

S" mload:cmap-1-0-is-0" T-NAME
_MLT-CMAP @ 1 0 CMAP-GET 0 T-ASSERT

\ Check spawn point
S" mload:spawn0-x-is-2" T-NAME
_MLT-WORLD @ 0 MLOAD-SPAWN
DROP 2 T-ASSERT

S" mload:spawn0-y-is-1" T-NAME
_MLT-WORLD @ 0 MLOAD-SPAWN
SWAP DROP 1 T-ASSERT

\ Check trigger zone
S" mload:trigger0-x-is-3" T-NAME
_MLT-WORLD @ 0 MLOAD-TRIGGER
DROP DROP DROP DROP 3 T-ASSERT

S" mload:trigger0-tag-is-99" T-NAME
_MLT-WORLD @ 0 MLOAD-TRIGGER
SWAP DROP SWAP DROP SWAP DROP SWAP DROP 99 T-ASSERT

\ Free
\ Free (MLOAD-FREE leaves nothing on stack)
_MLT-WORLD @ MLOAD-FREE

\ =====================================================================
\  Summary
\ =====================================================================

T-SUMMARY
"""

AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_phase6_suite.f
"""


# ── Emulator helpers ──────────────────────────────────────────

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
            d = "/" + "/".join(parts[:i + 1])
            if d not in dirs_made:
                fs.mkdir(d.lstrip("/"))
                dirs_made.add(d)

    for name, disk_dir, host_path in DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)

    test_src = FORTH_HARNESS.encode("utf-8")
    fs.inject_file("test_phase6_suite.f", test_src, ftype=FTYPE_FORTH)

    auto_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", auto_src, ftype=FTYPE_FORTH)

    # Build & inject the test map file (CBOR)
    # 4x3 map, 1 layer:
    #   row 0: wall(1) floor(2) floor(2) wall(1)
    #   row 1: floor(2) floor(2) floor(2) floor(2)
    #   row 2: wall(1) wall(1) wall(1) wall(1)
    tile_ids = [
        1, 2, 2, 1,
        2, 2, 2, 2,
        1, 1, 1, 1,
    ]
    cmap_bytes = bytes([
        1, 0, 0, 1,
        0, 0, 0, 0,
        1, 1, 1, 1,
    ])
    spawns = [(0, 2, 1)]           # spawn 0 at (2,1)
    triggers = [(0, 3, 0, 1, 1, 99)]  # trigger 0 at (3,0) size 1x1 tag=99

    map_data = build_test_map(4, 3, tile_ids, cmap_bytes, spawns, triggers)
    fs.inject_file("testmap.bin", map_data, ftype=FTYPE_DATA)

    fs.save(img_path)


def main():
    tmp = tempfile.NamedTemporaryFile(suffix=".img", delete=False, dir=SCRIPT_DIR)
    img_path = tmp.name
    tmp.close()

    try:
        build_disk(img_path)
        print("[*] Assembling BIOS...")
        with open(BIOS_PATH) as f:
            bios_code = assemble(f.read())

        sys_emu = MegapadSystem(ram_size=1024 * 1024,
                                ext_mem_size=16 * (1 << 20),
                                storage_image=img_path)
        buf = capture_uart(sys_emu)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        print("[*] Running Phase 6 test suite...")
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

        # Check for fatal errors
        fatal = False
        test_section = text[text.find("[MODULES LOADED]"):] if "[MODULES LOADED]" in text else text
        for err_pat in ["ABORT", "STACK"]:
            if err_pat.lower() in test_section.lower():
                idx = test_section.lower().find(err_pat.lower())
                ctx = test_section[max(0, idx - 120):idx + 120]
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
            print("\n--- UART tail (last 2000 chars) ---")
            print(text[-2000:])

    finally:
        os.unlink(img_path)

    return rc


if __name__ == "__main__":
    sys.exit(main())
