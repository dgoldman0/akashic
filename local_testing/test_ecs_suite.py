#!/usr/bin/env python3
"""Test suite for tui/game/* Phase 2 modules (ECS, Components, Systems).

Runs Forth test code through the Megapad-64 emulator and validates
correctness by parsing structured UART output.
"""
import os, sys, tempfile, re

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AK_DIR     = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from diskutil import MP64FS, FTYPE_FORTH

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

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
    # tui game engine
    ("loop.f",    "/tui/game", os.path.join(AK_DIR, "tui", "game", "loop.f")),
    ("input.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "input.f")),
    ("tilemap.f", "/tui/game", os.path.join(AK_DIR, "tui", "game", "tilemap.f")),
    ("sprite.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "sprite.f")),
    ("scene.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "scene.f")),
    # 2d game engine
    ("collide.f", "/game/2d", os.path.join(AK_DIR, "game", "2d", "collide.f")),
    # core game (ECS)
    ("ecs.f",        "/game", os.path.join(AK_DIR, "game", "ecs.f")),
    ("components.f", "/game", os.path.join(AK_DIR, "game", "components.f")),
    ("systems.f",    "/game", os.path.join(AK_DIR, "game", "systems.f")),
]

# ── Forth test harness ─────────────────────────────────────────
FORTH_HARNESS = r"""\ =====================================================================
\  test_ecs_suite.f — Tests for game/ecs.f, components.f, systems.f
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

\ ── Load modules ──────────────────────────────────────────────

REQUIRE game/ecs.f
REQUIRE game/components.f
REQUIRE game/systems.f

." [MODULES LOADED]" CR

\ ══════════════════════════════════════════════════════════════
\  ECS Core Tests
\ ══════════════════════════════════════════════════════════════

\ Create a test ECS with 32 entity slots
32 ECS-NEW CONSTANT _TECS

S" ecs:new-returns-nonzero" T-NAME
_TECS 0<> T-TRUE

S" ecs:max-returns-32" T-NAME
_TECS ECS-MAX 32 T-ASSERT

S" ecs:initial-count-0" T-NAME
_TECS ECS-COUNT 0 T-ASSERT

\ ── Spawn / Kill / Alive ──────────────────────────────────────

_TECS ECS-SPAWN CONSTANT _TE0

S" ecs:spawn-returns-0" T-NAME
_TE0 0 T-ASSERT

S" ecs:spawn-alive" T-NAME
_TECS _TE0 ECS-ALIVE? T-TRUE

S" ecs:count-after-spawn" T-NAME
_TECS ECS-COUNT 1 T-ASSERT

_TECS ECS-SPAWN CONSTANT _TE1

S" ecs:second-spawn-returns-1" T-NAME
_TE1 1 T-ASSERT

S" ecs:count-is-2" T-NAME
_TECS ECS-COUNT 2 T-ASSERT

S" ecs:kill-clears-alive" T-NAME
_TECS _TE1 ECS-KILL
_TECS _TE1 ECS-ALIVE? T-FALSE

S" ecs:count-after-kill" T-NAME
_TECS ECS-COUNT 1 T-ASSERT

S" ecs:gen-increments" T-NAME
_TECS _TE1 ECS-GEN 1 T-ASSERT

\ Respawn in killed slot — generation should advance
_TECS ECS-SPAWN CONSTANT _TE1B

S" ecs:respawn-reuses-slot" T-NAME
_TE1B 1 T-ASSERT

S" ecs:respawn-gen" T-NAME
_TECS _TE1B ECS-GEN 2 T-ASSERT

S" ecs:e0-gen-still-1" T-NAME
_TECS _TE0 ECS-GEN 1 T-ASSERT

\ ── Component Registration ────────────────────────────────────

\ Use a fresh ECS for component tests
64 ECS-NEW CONSTANT _CECS

\ Register a 16-byte position component
_CECS 16 ECS-REG-COMP CONSTANT _CP-POS

S" ecs:reg-comp-returns-0" T-NAME
_CP-POS 0 T-ASSERT

\ Register an 8-byte tag component
_CECS 8 ECS-REG-COMP CONSTANT _CP-TAG

S" ecs:reg-comp-returns-1" T-NAME
_CP-TAG 1 T-ASSERT

\ ── Attach / Has? / Get / Detach ──────────────────────────────

_CECS ECS-SPAWN CONSTANT _CE0
_CECS ECS-SPAWN CONSTANT _CE1

S" ecs:has-before-attach" T-NAME
_CECS _CE0 _CP-POS ECS-HAS? T-FALSE

_CECS _CE0 _CP-POS ECS-ATTACH CONSTANT _CE0-POS

S" ecs:attach-returns-nonzero" T-NAME
_CE0-POS 0<> T-TRUE

S" ecs:has-after-attach" T-NAME
_CECS _CE0 _CP-POS ECS-HAS? T-TRUE

S" ecs:get-returns-same-addr" T-NAME
_CECS _CE0 _CP-POS ECS-GET _CE0-POS T-ASSERT

\ Write position data and read it back
42 _CE0-POS !
99 _CE0-POS 8 + !

S" ecs:pos-x-stored" T-NAME
_CE0-POS @ 42 T-ASSERT

S" ecs:pos-y-stored" T-NAME
_CE0-POS 8 + @ 99 T-ASSERT

\ Entity 1 shouldn't have pos
S" ecs:e1-no-pos" T-NAME
_CECS _CE1 _CP-POS ECS-HAS? T-FALSE

S" ecs:e1-get-returns-0" T-NAME
_CECS _CE1 _CP-POS ECS-GET 0 T-ASSERT

\ Attach tag to both entities
_CECS _CE0 _CP-TAG ECS-ATTACH CONSTANT _CE0-TAG
_CECS _CE1 _CP-TAG ECS-ATTACH CONSTANT _CE1-TAG
100 _CE0-TAG !
200 _CE1-TAG !

S" ecs:ce0-tag-stored" T-NAME
_CE0-TAG @ 100 T-ASSERT

S" ecs:ce1-tag-stored" T-NAME
_CE1-TAG @ 200 T-ASSERT

\ Different entities have different addresses
S" ecs:different-addrs" T-NAME
_CE0-TAG _CE1-TAG <> T-TRUE

\ Detach pos from entity 0
S" ecs:detach-removes" T-NAME
_CECS _CE0 _CP-POS ECS-DETACH
_CECS _CE0 _CP-POS ECS-HAS? T-FALSE

S" ecs:detach-get-returns-0" T-NAME
_CECS _CE0 _CP-POS ECS-GET 0 T-ASSERT

\ Tag still attached after pos detach
S" ecs:tag-survives-pos-detach" T-NAME
_CECS _CE0 _CP-TAG ECS-HAS? T-TRUE

\ Kill clears all components
S" ecs:kill-clears-comps" T-NAME
_CECS _CE0 ECS-KILL
_CECS _CE0 _CP-TAG ECS-HAS? T-FALSE

\ ── ECS-EACH iteration ────────────────────────────────────────

\ Fresh ECS for iteration tests
32 ECS-NEW CONSTANT _IECS
_IECS 8 ECS-REG-COMP CONSTANT _IC-VAL

\ Spawn 5 entities, attach component to 3 of them (0,2,4)
_IECS ECS-SPAWN CONSTANT _IE0
_IECS ECS-SPAWN CONSTANT _IE1
_IECS ECS-SPAWN CONSTANT _IE2
_IECS ECS-SPAWN CONSTANT _IE3
_IECS ECS-SPAWN CONSTANT _IE4

10 _IECS _IE0 _IC-VAL ECS-ATTACH !
\ _IE1 has no component
30 _IECS _IE2 _IC-VAL ECS-ATTACH !
\ _IE3 has no component
50 _IECS _IE4 _IC-VAL ECS-ATTACH !

VARIABLE _ITER-SUM   0 _ITER-SUM !
VARIABLE _ITER-CNT   0 _ITER-CNT !

: _ITER-CALLBACK  ( eid addr -- )
    @ _ITER-SUM @ + _ITER-SUM !
    DROP
    _ITER-CNT @ 1+ _ITER-CNT ! ;

_IECS _IC-VAL ' _ITER-CALLBACK ECS-EACH

S" ecs:each-count" T-NAME
_ITER-CNT @ 3 T-ASSERT

S" ecs:each-sum" T-NAME
_ITER-SUM @ 90 T-ASSERT

\ ── ECS-EACH2 iteration ──────────────────────────────────────

32 ECS-NEW CONSTANT _I2ECS
_I2ECS 16 ECS-REG-COMP CONSTANT _I2C-POS
_I2ECS  8 ECS-REG-COMP CONSTANT _I2C-TAG

_I2ECS ECS-SPAWN CONSTANT _I2E0
_I2ECS ECS-SPAWN CONSTANT _I2E1
_I2ECS ECS-SPAWN CONSTANT _I2E2

\ E0: has both POS and TAG
_I2ECS _I2E0 _I2C-POS ECS-ATTACH CONSTANT _I2E0-POS
5 _I2E0-POS !
_I2ECS _I2E0 _I2C-TAG ECS-ATTACH CONSTANT _I2E0-TAG
7 _I2E0-TAG !

\ E1: has only POS
_I2ECS _I2E1 _I2C-POS ECS-ATTACH CONSTANT _I2E1-POS
11 _I2E1-POS !

\ E2: has both POS and TAG
_I2ECS _I2E2 _I2C-POS ECS-ATTACH CONSTANT _I2E2-POS
13 _I2E2-POS !
_I2ECS _I2E2 _I2C-TAG ECS-ATTACH CONSTANT _I2E2-TAG
17 _I2E2-TAG !

VARIABLE _I2-SUM   0 _I2-SUM !
VARIABLE _I2-CNT   0 _I2-CNT !

: _I2-CALLBACK  ( eid pos-addr tag-addr -- )
    @ SWAP @ +
    _I2-SUM @ + _I2-SUM !
    DROP
    _I2-CNT @ 1+ _I2-CNT ! ;

_I2ECS _I2C-POS _I2C-TAG ' _I2-CALLBACK ECS-EACH2

S" ecs:each2-count" T-NAME
_I2-CNT @ 2 T-ASSERT

S" ecs:each2-sum" T-NAME
\ E0: pos.x=5 + tag=7 = 12,  E2: pos.x=13 + tag=17 = 30 → total=42
_I2-SUM @ 42 T-ASSERT

\ ══════════════════════════════════════════════════════════════
\  Components Module Tests
\ ══════════════════════════════════════════════════════════════

S" comp:pos-size" T-NAME
C-POS-SZ 16 T-ASSERT

S" comp:vel-size" T-NAME
C-VEL-SZ 16 T-ASSERT

S" comp:spr-size" T-NAME
C-SPR-SZ 8 T-ASSERT

S" comp:hp-size" T-NAME
C-HP-SZ 16 T-ASSERT

S" comp:col-size" T-NAME
C-COL-SZ 8 T-ASSERT

S" comp:tmr-size" T-NAME
C-TMR-SZ 16 T-ASSERT

S" comp:tag-size" T-NAME
C-TAG-SZ 8 T-ASSERT

S" comp:ai-size" T-NAME
C-AI-SZ 8 T-ASSERT

\ Field offset tests
S" comp:pos-x-offset" T-NAME
C-POS.X 0 T-ASSERT

S" comp:pos-y-offset" T-NAME
C-POS.Y 8 T-ASSERT

S" comp:vel-dx-offset" T-NAME
C-VEL.DX 0 T-ASSERT

S" comp:vel-dy-offset" T-NAME
C-VEL.DY 8 T-ASSERT

S" comp:hp-cur-offset" T-NAME
C-HP.CUR 0 T-ASSERT

S" comp:hp-max-offset" T-NAME
C-HP.MAX 8 T-ASSERT

S" comp:tmr-ticks-offset" T-NAME
C-TMR.TICKS 0 T-ASSERT

S" comp:tmr-xt-offset" T-NAME
C-TMR.XT 8 T-ASSERT

\ ── COMPS-REG-ALL test ────────────────────────────────────────

16 ECS-NEW CONSTANT _CRECS
_CRECS COMPS-REG-ALL
CONSTANT _CR-AI
CONSTANT _CR-TAG
CONSTANT _CR-TMR
CONSTANT _CR-COL
CONSTANT _CR-HP
CONSTANT _CR-SPR
CONSTANT _CR-VEL
CONSTANT _CR-POS

S" comp:reg-all-pos-0" T-NAME
_CR-POS 0 T-ASSERT

S" comp:reg-all-vel-1" T-NAME
_CR-VEL 1 T-ASSERT

S" comp:reg-all-ai-7" T-NAME
_CR-AI 7 T-ASSERT

\ ══════════════════════════════════════════════════════════════
\  System Runner Tests
\ ══════════════════════════════════════════════════════════════

\ Create ECS + runner for system tests
32 ECS-NEW CONSTANT _SECS
_SECS SYSRUN-NEW CONSTANT _SRUN

S" sys:new-returns-nonzero" T-NAME
_SRUN 0<> T-TRUE

S" sys:initial-count-0" T-NAME
_SRUN SYSRUN-COUNT 0 T-ASSERT

\ ── Simple custom systems ─────────────────────────────────────

VARIABLE _SYS-A-COUNT   0 _SYS-A-COUNT !
VARIABLE _SYS-B-COUNT   0 _SYS-B-COUNT !
VARIABLE _SYS-ORDER

: _SYS-A  ( ecs dt -- )
    2DROP
    _SYS-A-COUNT @ 1+ _SYS-A-COUNT !
    1 _SYS-ORDER @ 10 * + _SYS-ORDER ! ;

: _SYS-B  ( ecs dt -- )
    2DROP
    _SYS-B-COUNT @ 1+ _SYS-B-COUNT !
    2 _SYS-ORDER @ 10 * + _SYS-ORDER ! ;

\ Add B at priority 200, then A at priority 100
\ A should run first despite being added second
_SRUN ' _SYS-B 200 SYSRUN-ADD
_SRUN ' _SYS-A 100 SYSRUN-ADD

S" sys:count-after-add" T-NAME
_SRUN SYSRUN-COUNT 2 T-ASSERT

\ Tick once
0 _SYS-ORDER !
_SRUN 1 SYSRUN-TICK

S" sys:a-ran" T-NAME
_SYS-A-COUNT @ 1 T-ASSERT

S" sys:b-ran" T-NAME
_SYS-B-COUNT @ 1 T-ASSERT

S" sys:order-a-then-b" T-NAME
\ A runs first → order = 1, then B → order = 1*10+2 = 12
_SYS-ORDER @ 12 T-ASSERT

\ ── Disable / Enable ──────────────────────────────────────────

0 _SYS-A-COUNT !
0 _SYS-B-COUNT !
_SRUN 0 SYSRUN-DISABLE
_SRUN 1 SYSRUN-TICK

S" sys:disabled-skipped" T-NAME
_SYS-A-COUNT @ 0 T-ASSERT

S" sys:enabled-still-ran" T-NAME
_SYS-B-COUNT @ 1 T-ASSERT

_SRUN 0 SYSRUN-ENABLE
0 _SYS-A-COUNT !
0 _SYS-B-COUNT !
_SRUN 1 SYSRUN-TICK

S" sys:re-enabled-runs" T-NAME
_SYS-A-COUNT @ 1 T-ASSERT

\ ══════════════════════════════════════════════════════════════
\  Built-in System Tests: SYS-VELOCITY
\ ══════════════════════════════════════════════════════════════

64 ECS-NEW CONSTANT _VECS
_VECS C-POS-SZ ECS-REG-COMP CONSTANT _VC-POS
_VECS C-VEL-SZ ECS-REG-COMP CONSTANT _VC-VEL

_VC-POS SYS-C-POS !
_VC-VEL SYS-C-VEL !

_VECS ECS-SPAWN CONSTANT _VE0

\ Attach position at (10, 20)
_VECS _VE0 _VC-POS ECS-ATTACH CONSTANT _VE0-P
10 _VE0-P C-POS.X + !
20 _VE0-P C-POS.Y + !

\ Attach velocity (3, -2)
_VECS _VE0 _VC-VEL ECS-ATTACH CONSTANT _VE0-V
3 _VE0-V C-VEL.DX + !
-2 _VE0-V C-VEL.DY + !

\ Run velocity system with dt=1
_VECS 1 SYS-VELOCITY

S" vel:x-after-tick" T-NAME
_VE0-P C-POS.X + @ 13 T-ASSERT

S" vel:y-after-tick" T-NAME
_VE0-P C-POS.Y + @ 18 T-ASSERT

\ Run again with dt=5
_VECS 5 SYS-VELOCITY

S" vel:x-after-5dt" T-NAME
_VE0-P C-POS.X + @ 28 T-ASSERT

S" vel:y-after-5dt" T-NAME
_VE0-P C-POS.Y + @ 8 T-ASSERT

\ ══════════════════════════════════════════════════════════════
\  Built-in System Tests: SYS-TIMER
\ ══════════════════════════════════════════════════════════════

64 ECS-NEW CONSTANT _TMECS
_TMECS C-TMR-SZ ECS-REG-COMP CONSTANT _TMC-TMR

_TMC-TMR SYS-C-TMR !

_TMECS ECS-SPAWN CONSTANT _TMEID

VARIABLE _TMR-FIRED   0 _TMR-FIRED !
: _TMR-CALLBACK  ( eid -- ) DROP _TMR-FIRED @ 1+ _TMR-FIRED ! ;

_TMECS _TMEID _TMC-TMR ECS-ATTACH CONSTANT _TM-ADDR
3 _TM-ADDR C-TMR.TICKS + !
' _TMR-CALLBACK _TM-ADDR C-TMR.XT + !

\ Tick 1: ticks should go from 3 to 2
_TMECS 1 SYS-TIMER

S" tmr:ticks-after-1" T-NAME
_TM-ADDR C-TMR.TICKS + @ 2 T-ASSERT

S" tmr:not-fired-yet" T-NAME
_TMR-FIRED @ 0 T-ASSERT

\ Tick 2: 2 → 1
_TMECS 1 SYS-TIMER

S" tmr:ticks-after-2" T-NAME
_TM-ADDR C-TMR.TICKS + @ 1 T-ASSERT

\ Tick 3: 1 → 0, callback fires
_TMECS 1 SYS-TIMER

S" tmr:ticks-after-3" T-NAME
_TM-ADDR C-TMR.TICKS + @ 0 T-ASSERT

S" tmr:callback-fired" T-NAME
_TMR-FIRED @ 1 T-ASSERT

\ ══════════════════════════════════════════════════════════════
\  Built-in System Tests: SYS-CULL-DEAD
\ ══════════════════════════════════════════════════════════════

32 ECS-NEW CONSTANT _HECS
_HECS C-HP-SZ ECS-REG-COMP CONSTANT _HC-HP
_HC-HP SYS-C-HP !

_HECS ECS-SPAWN CONSTANT _HE0
_HECS ECS-SPAWN CONSTANT _HE1

\ E0: alive (hp=10), E1: dead (hp=0)
_HECS _HE0 _HC-HP ECS-ATTACH CONSTANT _HE0-HP
10 _HE0-HP C-HP.CUR + !
10 _HE0-HP C-HP.MAX + !

_HECS _HE1 _HC-HP ECS-ATTACH CONSTANT _HE1-HP
0 _HE1-HP C-HP.CUR + !
5 _HE1-HP C-HP.MAX + !

S" cull:both-alive-before" T-NAME
_HECS _HE0 ECS-ALIVE? _HECS _HE1 ECS-ALIVE? AND T-TRUE

_HECS 0 SYS-CULL-DEAD

S" cull:healthy-survives" T-NAME
_HECS _HE0 ECS-ALIVE? T-TRUE

S" cull:zero-hp-killed" T-NAME
_HECS _HE1 ECS-ALIVE? T-FALSE

S" cull:count-after" T-NAME
_HECS ECS-COUNT 1 T-ASSERT

\ ══════════════════════════════════════════════════════════════
\  Summary
\ ══════════════════════════════════════════════════════════════

T-SUMMARY
"""


AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_ecs_suite.f
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
    fs.inject_file("test_ecs_suite.f", test_src, ftype=FTYPE_FORTH)

    auto_src = AUTOEXEC_F.encode("utf-8")
    fs.inject_file("autoexec.f", auto_src, ftype=FTYPE_FORTH)

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
            print("\n--- UART tail (last 2000 chars) ---")
            print(text[-2000:])

    finally:
        os.unlink(img_path)

    return rc


if __name__ == "__main__":
    sys.exit(main())
