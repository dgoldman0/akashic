#!/usr/bin/env python3
"""Test suite for Phase 7: fsm.f + btree.f + fog.f

Runs Forth test code through the Megapad-64 emulator and validates
correctness by parsing structured UART output.  Behaviour trees and the fog
of war are also checked against the host models in game_models.py, and a
host test checks that the shadowcast oracle is symmetric and that the map's
edge darkens nothing inside it.
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
from forth_disk import MEMORY_LOG, kdos_diagnostics, module_disk_files  # noqa: E402
import game_models  # noqa: E402

# Behaviour trees the suite runs against the host model: the fixed nested
# shapes and seeded random trees.  Fog maps the suite reveals against the
# host shadowcast: the probe's two maps and seeded random ones.
BT_TREES = game_models.bt_trees()
FOG_MAPS = game_models.fog_maps()


BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")


# ── Disk files (dependency order) ──────────────────────────────

# The modules the suite loads and their REQUIRE closure, each in its own
# directory on the disk, so the disk follows what the modules require.
DISK_FILES = module_disk_files((
    "text/utf8.f",
    "tui/ansi.f",
    "tui/keys.f",
    "tui/cell.f",
    "tui/screen.f",
    "tui/draw.f",
    "tui/box.f",
    "tui/region.f",
    "game/2d/camera.f",
    "game/2d/collide.f",
    "game/ai/fsm.f",
    "game/ai/btree.f",
    "game/2d/fog.f",
))


# ── Forth test harness ─────────────────────────────────────────
FORTH_HARNESS = r"""\ =====================================================================
\  test_phase7_suite.f — Tests for Phase 7 (fsm.f + btree.f + fog.f)
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

REQUIRE tui/screen.f
""" + MEMORY_LOG + r"""
REQUIRE game/ai/fsm.f
REQUIRE game/ai/btree.f
REQUIRE game/2d/fog.f

80 25 SCR-NEW SCR-USE

." [MODULES LOADED]" CR

\ =====================================================================
\  §1 — FSM tests
\ =====================================================================

." --- fsm.f ---" CR

VARIABLE _TF-FSM
VARIABLE _TF-CUR  -1 _TF-CUR !        \ the entity's current state
VARIABLE _TF-IDLE
VARIABLE _TF-CHASE
VARIABLE _TF-FLEE

\ Callback tracking VARIABLEs
VARIABLE _TF-ENTER-COUNT 0 _TF-ENTER-COUNT !
VARIABLE _TF-TICK-COUNT  0 _TF-TICK-COUNT !
VARIABLE _TF-LEAVE-COUNT 0 _TF-LEAVE-COUNT !

: _TF-ON-ENTER  ( eid ecs -- )
    2DROP 1 _TF-ENTER-COUNT +! ;

: _TF-ON-TICK  ( eid ecs dt -- )
    DROP 2DROP 1 _TF-TICK-COUNT +! ;

: _TF-ON-LEAVE  ( eid ecs -- )
    2DROP 1 _TF-LEAVE-COUNT +! ;

\ Guard: always false
: _TF-GUARD-NEVER  ( eid ecs -- flag )
    2DROP 0 ;

\ Guard: always true
: _TF-GUARD-ALWAYS  ( eid ecs -- flag )
    2DROP -1 ;

\ Conditional guard (external flag)
VARIABLE _TF-SHOULD-CHASE  0 _TF-SHOULD-CHASE !
: _TF-GUARD-CHASE  ( eid ecs -- flag )
    2DROP _TF-SHOULD-CHASE @ ;

\ --- Test: FSM-NEW ---
S" fsm:new-nonzero" T-NAME
FSM-NEW DUP _TF-FSM ! 0<> T-TRUE

S" fsm:initial-current-neg1" T-NAME
_TF-CUR @ -1 T-ASSERT

\ --- Test: FSM-STATE ---
S" fsm:define-idle-returns-0" T-NAME
_TF-FSM @
S" idle" ' _TF-ON-ENTER ' _TF-ON-TICK ' _TF-ON-LEAVE
FSM-STATE DUP _TF-IDLE ! 0 T-ASSERT

S" fsm:define-chase-returns-1" T-NAME
_TF-FSM @
S" chase" ' _TF-ON-ENTER ' _TF-ON-TICK ' _TF-ON-LEAVE
FSM-STATE DUP _TF-CHASE ! 1 T-ASSERT

S" fsm:define-flee-returns-2" T-NAME
_TF-FSM @
S" flee" 0 ' _TF-ON-TICK 0
FSM-STATE DUP _TF-FLEE ! 2 T-ASSERT

\ --- Test: FSM-START ---
0 _TF-ENTER-COUNT !
S" fsm:start-enter-called" T-NAME
_TF-FSM @ _TF-CUR 0 0 _TF-IDLE @ FSM-START
_TF-ENTER-COUNT @ 1 T-ASSERT

S" fsm:start-current-is-idle" T-NAME
_TF-CUR @ _TF-IDLE @ T-ASSERT

\ --- Test: FSM-TICK (no transitions) ---
0 _TF-TICK-COUNT !
S" fsm:tick-calls-on-tick" T-NAME
_TF-FSM @ _TF-CUR 42 99 16 FSM-TICK
_TF-TICK-COUNT @ 1 T-ASSERT

S" fsm:tick-stays-in-idle" T-NAME
_TF-CUR @ _TF-IDLE @ T-ASSERT

\ --- Test: FSM-TRANSITION (guard=never) ---
_TF-FSM @ _TF-IDLE @ _TF-CHASE @ ' _TF-GUARD-NEVER FSM-TRANSITION

0 _TF-TICK-COUNT !
0 _TF-LEAVE-COUNT !
0 _TF-ENTER-COUNT !
S" fsm:tick-no-transition-when-guard-false" T-NAME
_TF-FSM @ _TF-CUR 0 0 1 FSM-TICK
_TF-CUR @ _TF-IDLE @ T-ASSERT

S" fsm:enter-not-called-when-no-trans" T-NAME
_TF-ENTER-COUNT @ 0 T-ASSERT

\ --- Test: FSM-TRANSITION (guard=always, idle→chase) ---
_TF-FSM @ _TF-IDLE @ _TF-CHASE @ ' _TF-GUARD-ALWAYS FSM-TRANSITION

0 _TF-TICK-COUNT !
0 _TF-LEAVE-COUNT !
0 _TF-ENTER-COUNT !
S" fsm:transition-fires" T-NAME
_TF-FSM @ _TF-CUR 0 0 1 FSM-TICK
_TF-CUR @ _TF-CHASE @ T-ASSERT

S" fsm:leave-called-on-trans" T-NAME
_TF-LEAVE-COUNT @ 1 T-ASSERT

S" fsm:enter-called-on-trans" T-NAME
_TF-ENTER-COUNT @ 1 T-ASSERT

S" fsm:tick-called-after-trans" T-NAME
_TF-TICK-COUNT @ 1 T-ASSERT

\ --- Test: conditional guard ---
\ Add chase→idle transition with conditional guard
_TF-FSM @ _TF-CHASE @ _TF-IDLE @ ' _TF-GUARD-CHASE FSM-TRANSITION

\ Flag is false — should stay in chase
0 _TF-SHOULD-CHASE !
0 _TF-ENTER-COUNT !
_TF-FSM @ _TF-CUR 0 0 1 FSM-TICK
S" fsm:cond-guard-stays" T-NAME
_TF-CUR @ _TF-CHASE @ T-ASSERT

\ Set flag true — should transition back to idle
-1 _TF-SHOULD-CHASE !
0 _TF-ENTER-COUNT !
_TF-FSM @ _TF-CUR 0 0 1 FSM-TICK
S" fsm:cond-guard-fires" T-NAME
_TF-CUR @ _TF-IDLE @ T-ASSERT

\ --- Test: a guard ticks another machine mid-scan ---
\ M1 has two transitions from its first state: a guard that ticks M2 and
\ declines, then one that always fires.  M1 must reach its third state
\ and M2 its second, with M2's tick callback run once.
VARIABLE _TF-M1  VARIABLE _TF-M2
VARIABLE _TF-C1  VARIABLE _TF-C2
VARIABLE _TF-M2-TICKS  0 _TF-M2-TICKS !
: _TF-M2-TICK  ( eid ecs dt -- )  DROP 2DROP 1 _TF-M2-TICKS +! ;
: _TF-G-NESTS  ( eid ecs -- flag )  2DROP _TF-M2 @ _TF-C2 7 0 1 FSM-TICK 0 ;
FSM-NEW _TF-M1 !  FSM-NEW _TF-M2 !
_TF-M1 @ S" a" 0 0 0 FSM-STATE DROP
_TF-M1 @ S" b" 0 0 0 FSM-STATE DROP
_TF-M1 @ S" c" 0 0 0 FSM-STATE DROP
_TF-M1 @ 0 1 ' _TF-G-NESTS FSM-TRANSITION
_TF-M1 @ 0 2 ' _TF-GUARD-ALWAYS FSM-TRANSITION
_TF-M2 @ S" x" 0 ' _TF-M2-TICK 0 FSM-STATE DROP
_TF-M2 @ S" y" 0 ' _TF-M2-TICK 0 FSM-STATE DROP
_TF-M2 @ 0 1 ' _TF-GUARD-ALWAYS FSM-TRANSITION
_TF-M1 @ _TF-C1 1 0 0 FSM-START  _TF-M2 @ _TF-C2 7 0 0 FSM-START
_TF-M1 @ _TF-C1 1 0 1 FSM-TICK
S" fsm:nested-scan-outer-fires-next" T-NAME
_TF-C1 @ 2 T-ASSERT
S" fsm:nested-scan-inner-moved" T-NAME
_TF-C2 @ 1 T-ASSERT
S" fsm:nested-scan-inner-ticked-once" T-NAME
_TF-M2-TICKS @ 1 T-ASSERT
_TF-M1 @ FSM-FREE  _TF-M2 @ FSM-FREE

\ --- Test: on-enter receives the entity ---
VARIABLE _TF-SEEN-EID  0 _TF-SEEN-EID !
: _TF-ENTER-EID  ( eid ecs -- )  DROP _TF-SEEN-EID ! ;
FSM-NEW CONSTANT _TF-M3
_TF-M3 S" only" ' _TF-ENTER-EID 0 0 FSM-STATE DROP
VARIABLE _TF-C3
_TF-M3 _TF-C3 31 0 0 FSM-START
S" fsm:start-passes-entity" T-NAME
_TF-SEEN-EID @ 31 T-ASSERT
S" fsm:name" T-NAME
_TF-M3 0 FSM-NAME S" only" COMPARE 0 T-ASSERT
_TF-M3 FSM-FREE

\ --- Test: one definition for two entities ---
\ The guard moves even entities from idle to chase; entities 2 and 3
\ share the definition and keep their states in cells of their own.
: _TF-G-EVEN  ( eid ecs -- flag )  DROP 1 AND 0= ;
FSM-NEW CONSTANT _TF-M4
_TF-M4 S" idle" 0 0 0 FSM-STATE DROP
_TF-M4 S" chase" 0 0 0 FSM-STATE DROP
_TF-M4 0 1 ' _TF-G-EVEN FSM-TRANSITION
VARIABLE _TF-E2  VARIABLE _TF-E3
_TF-M4 _TF-E2 2 0 0 FSM-START  _TF-M4 _TF-E3 3 0 0 FSM-START
_TF-M4 _TF-E2 2 0 1 FSM-TICK   _TF-M4 _TF-E3 3 0 1 FSM-TICK
S" fsm:shared-definition-even-chases" T-NAME
_TF-E2 @ 1 T-ASSERT
S" fsm:shared-definition-odd-idles" T-NAME
_TF-E3 @ 0 T-ASSERT
_TF-M4 FSM-FREE

\ --- Test: states and transitions grow as they are defined ---
\ Twenty states in a ring, forty transitions: each state's first
\ transition declines and its second moves on.
FSM-NEW CONSTANT _TF-M5
: _TF-RING  ( -- )
    20 0 DO _TF-M5 S" ring" 0 0 0 FSM-STATE DROP LOOP
    20 0 DO
        _TF-M5 I I 1+ 20 MOD ['] _TF-GUARD-NEVER FSM-TRANSITION
        _TF-M5 I I 1+ 20 MOD ['] _TF-GUARD-ALWAYS FSM-TRANSITION
    LOOP ;
_TF-RING
VARIABLE _TF-C5
_TF-M5 _TF-C5 0 0 0 FSM-START
: _TF-GO-ROUND  25 0 DO _TF-M5 _TF-C5 0 0 1 FSM-TICK LOOP ;
_TF-GO-ROUND
S" fsm:twenty-states" T-NAME
_TF-M5 FSM-STATES 20 T-ASSERT
S" fsm:ring-after-25-ticks" T-NAME
_TF-C5 @ 5 T-ASSERT
_TF-M5 FSM-FREE

\ --- Test: FSM-FREE ---
S" fsm:free-no-crash" T-NAME
_TF-FSM @ FSM-FREE -1 T-TRUE

\ =====================================================================
\  §2 — Behaviour Tree tests
\ =====================================================================

." --- btree.f ---" CR

\ --- leaf: action that succeeds ---
: _TB-ACT-OK  ( eid ecs -- status )
    2DROP BT-SUCCESS ;

: _TB-ACT-FAIL  ( eid ecs -- status )
    2DROP BT-FAILURE ;

: _TB-ACT-RUN  ( eid ecs -- status )
    2DROP BT-RUNNING ;

: _TB-COND-T  ( eid ecs -- flag )
    2DROP -1 ;

: _TB-COND-F  ( eid ecs -- flag )
    2DROP 0 ;

VARIABLE _TB-CALL-COUNT  0 _TB-CALL-COUNT !
: _TB-ACT-COUNT  ( eid ecs -- status )
    2DROP 1 _TB-CALL-COUNT +! BT-SUCCESS ;

\ --- Test: BT-ACTION ---
S" bt:action-success" T-NAME
' _TB-ACT-OK BT-ACTION
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
BT-FREE

S" bt:action-failure" T-NAME
' _TB-ACT-FAIL BT-ACTION
DUP 0 0 0 BT-RUN BT-FAILURE T-ASSERT
BT-FREE

S" bt:action-running" T-NAME
' _TB-ACT-RUN BT-ACTION
DUP 0 0 0 BT-RUN BT-RUNNING T-ASSERT
BT-FREE

\ --- Test: BT-CONDITION ---
S" bt:condition-true-is-success" T-NAME
' _TB-COND-T BT-CONDITION
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
BT-FREE

S" bt:condition-false-is-failure" T-NAME
' _TB-COND-F BT-CONDITION
DUP 0 0 0 BT-RUN BT-FAILURE T-ASSERT
BT-FREE

\ --- Test: BT-SEQUENCE (all succeed) ---
S" bt:seq-all-success" T-NAME
CREATE _TB-SEQ-OK 3 CELLS ALLOT
' _TB-ACT-OK BT-ACTION _TB-SEQ-OK !
' _TB-ACT-OK BT-ACTION _TB-SEQ-OK 8 + !
' _TB-ACT-OK BT-ACTION _TB-SEQ-OK 16 + !
_TB-SEQ-OK 3 BT-SEQUENCE
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
BT-FREE

\ --- Test: BT-SEQUENCE (second fails) ---
S" bt:seq-fail-at-second" T-NAME
CREATE _TB-SEQ-F2 2 CELLS ALLOT
' _TB-ACT-OK BT-ACTION _TB-SEQ-F2 !
' _TB-ACT-FAIL BT-ACTION _TB-SEQ-F2 8 + !
_TB-SEQ-F2 2 BT-SEQUENCE
DUP 0 0 0 BT-RUN BT-FAILURE T-ASSERT
BT-FREE

\ --- Test: BT-SELECTOR (first succeeds) ---
S" bt:sel-first-ok" T-NAME
CREATE _TB-SEL-1 2 CELLS ALLOT
' _TB-ACT-OK BT-ACTION _TB-SEL-1 !
' _TB-ACT-FAIL BT-ACTION _TB-SEL-1 8 + !
_TB-SEL-1 2 BT-SELECTOR
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
BT-FREE

\ --- Test: BT-SELECTOR (first fails, second succeeds) ---
S" bt:sel-fallback" T-NAME
CREATE _TB-SEL-2 2 CELLS ALLOT
' _TB-ACT-FAIL BT-ACTION _TB-SEL-2 !
' _TB-ACT-OK BT-ACTION _TB-SEL-2 8 + !
_TB-SEL-2 2 BT-SELECTOR
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
BT-FREE

\ --- Test: BT-SELECTOR (all fail) ---
S" bt:sel-all-fail" T-NAME
CREATE _TB-SEL-AF 2 CELLS ALLOT
' _TB-ACT-FAIL BT-ACTION _TB-SEL-AF !
' _TB-ACT-FAIL BT-ACTION _TB-SEL-AF 8 + !
_TB-SEL-AF 2 BT-SELECTOR
DUP 0 0 0 BT-RUN BT-FAILURE T-ASSERT
BT-FREE

\ --- Test: BT-INVERT ---
S" bt:invert-success-to-failure" T-NAME
' _TB-ACT-OK BT-ACTION BT-INVERT
DUP 0 0 0 BT-RUN BT-FAILURE T-ASSERT
BT-FREE

S" bt:invert-failure-to-success" T-NAME
' _TB-ACT-FAIL BT-ACTION BT-INVERT
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
BT-FREE

S" bt:invert-running-passthrough" T-NAME
' _TB-ACT-RUN BT-ACTION BT-INVERT
DUP 0 0 0 BT-RUN BT-RUNNING T-ASSERT
BT-FREE

\ --- Test: BT-REPEAT ---
\ A repeat or a cooldown keeps its counts in the entity's state block.
4 CELLS ALLOCATE DROP CONSTANT _TB-ST
_TB-ST 4 CELLS 0 FILL
S" bt:repeat-state-cells" T-NAME
' _TB-ACT-COUNT BT-ACTION 3 BT-REPEAT
DUP BT-STATE-CELLS 1 T-ASSERT
S" bt:repeat-3-times" T-NAME
0 _TB-CALL-COUNT !
DUP _TB-ST 0 0 BT-RUN BT-RUNNING T-ASSERT       \ run 1/3
DUP _TB-ST 0 0 BT-RUN BT-RUNNING T-ASSERT       \ run 2/3

S" bt:repeat-completes-at-3" T-NAME
DUP _TB-ST 0 0 BT-RUN BT-SUCCESS T-ASSERT       \ run 3/3 → done

S" bt:repeat-called-3" T-NAME
_TB-CALL-COUNT @ 3 T-ASSERT
BT-FREE

\ --- Test: BT-REPEAT with n=0 (infinite) ---
S" bt:repeat-infinite" T-NAME
_TB-ST 4 CELLS 0 FILL
0 _TB-CALL-COUNT !
' _TB-ACT-COUNT BT-ACTION 0 BT-REPEAT
DUP _TB-ST 0 0 BT-RUN BT-RUNNING T-ASSERT
DUP _TB-ST 0 0 BT-RUN BT-RUNNING T-ASSERT
DUP _TB-ST 0 0 BT-RUN BT-RUNNING T-ASSERT

S" bt:repeat-inf-count-3" T-NAME
_TB-CALL-COUNT @ 3 T-ASSERT
BT-FREE

\ --- Test: BT-COOLDOWN ---
S" bt:cooldown-state-cells" T-NAME
_TB-ST 4 CELLS 0 FILL
' _TB-ACT-COUNT BT-ACTION 2 BT-COOLDOWN
DUP BT-STATE-CELLS 2 T-ASSERT
S" bt:cooldown-first-runs" T-NAME
0 _TB-CALL-COUNT !
DUP _TB-ST 0 0 BT-RUN BT-SUCCESS T-ASSERT   \ runs child

S" bt:cooldown-skip-1" T-NAME
DUP _TB-ST 0 0 BT-RUN BT-SUCCESS T-ASSERT   \ cooldown tick 1, returns last

S" bt:cooldown-skip-2" T-NAME
DUP _TB-ST 0 0 BT-RUN BT-SUCCESS T-ASSERT   \ cooldown tick 2, returns last

S" bt:cooldown-resumes" T-NAME
DUP _TB-ST 0 0 BT-RUN BT-SUCCESS T-ASSERT   \ runs child again

S" bt:cooldown-call-count" T-NAME
_TB-CALL-COUNT @ 2 T-ASSERT          \ only 2 actual child calls
BT-FREE

\ --- Test: BT-PARALLEL ---
S" bt:parallel-threshold-met" T-NAME
CREATE _TB-PAR-1 3 CELLS ALLOT
' _TB-ACT-OK BT-ACTION _TB-PAR-1 !
' _TB-ACT-FAIL BT-ACTION _TB-PAR-1 8 + !
' _TB-ACT-OK BT-ACTION _TB-PAR-1 16 + !
_TB-PAR-1 3 2 BT-PARALLEL             \ 3 children, threshold=2
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT   \ 2/3 succeed >= threshold
BT-FREE

S" bt:parallel-threshold-not-met" T-NAME
CREATE _TB-PAR-2 3 CELLS ALLOT
' _TB-ACT-OK BT-ACTION _TB-PAR-2 !
' _TB-ACT-FAIL BT-ACTION _TB-PAR-2 8 + !
' _TB-ACT-FAIL BT-ACTION _TB-PAR-2 16 + !
_TB-PAR-2 3 2 BT-PARALLEL             \ 3 children, threshold=2
DUP 0 0 0 BT-RUN BT-FAILURE T-ASSERT   \ 2 fail > (3-2) → failure
BT-FREE

\ --- Test: composites nest ---
\ A sequence of a selector and two counting actions: the selector fails
\ its first child and succeeds with its second, and both actions run.
VARIABLE _TB-NX  0 _TB-NX !
VARIABLE _TB-NY  0 _TB-NY !
: _TB-ACT-X  ( eid ecs -- status )  2DROP 1 _TB-NX +! BT-SUCCESS ;
: _TB-ACT-Y  ( eid ecs -- status )  2DROP 1 _TB-NY +! BT-SUCCESS ;
CREATE _TB-NSEL 2 CELLS ALLOT
' _TB-ACT-FAIL BT-ACTION _TB-NSEL !
' _TB-ACT-OK BT-ACTION _TB-NSEL 8 + !
CREATE _TB-NSEQ 3 CELLS ALLOT
_TB-NSEL 2 BT-SELECTOR _TB-NSEQ !
' _TB-ACT-X BT-ACTION _TB-NSEQ 8 + !
' _TB-ACT-Y BT-ACTION _TB-NSEQ 16 + !
S" bt:nested-sequence-succeeds" T-NAME
_TB-NSEQ 3 BT-SEQUENCE
DUP 0 0 0 BT-RUN BT-SUCCESS T-ASSERT
S" bt:nested-sequence-runs-both-actions" T-NAME
_TB-NX @ 1 = _TB-NY @ 1 = AND T-TRUE
\ The sequence and the selector, their two arrays, and four leaves
-1 MLOG-HOLD  MLOG-START  BT-FREE  MLOG-STOP  0 MLOG-HOLD
S" bt:nested-free-count" T-NAME
MLOG-FREES 8 T-ASSERT
S" bt:nested-free-no-repeats" T-NAME
MLOG-REPEATS 0 T-ASSERT

""" + game_models.bt_forth(BT_TREES) + r"""
\ =====================================================================
\  §3 — Fog of War tests
\ =====================================================================

." --- fog.f ---" CR

\ 10x10 map with a wall across (3,3) to (5,3), the probe's first map:
\   ..........
\   ..........
\   ..........
\   ...###....
\   ..........
VARIABLE _TFG-FOG
10 10 CMAP-NEW CONSTANT _TFG-MAP
_TFG-MAP 3 3 1 CMAP-SET  _TFG-MAP 4 3 1 CMAP-SET  _TFG-MAP 5 3 1 CMAP-SET

S" fog:new-nonzero" T-NAME
10 10 FOG-NEW DUP _TFG-FOG ! 0<> T-TRUE
_TFG-FOG @ _TFG-MAP FOG-BLOCK-MAP!

S" fog:size" T-NAME
_TFG-FOG @ FOG-W _TFG-FOG @ FOG-H * 100 T-ASSERT

S" fog:initial-unseen-0-0" T-NAME
_TFG-FOG @ 0 0 FOG-STATE 0 T-ASSERT

S" fog:initial-unseen-5-5" T-NAME
_TFG-FOG @ 5 5 FOG-STATE 0 T-ASSERT

S" fog:oob-returns-unseen" T-NAME
_TFG-FOG @ -1 0 FOG-STATE 0 T-ASSERT

S" fog:oob-returns-unseen2" T-NAME
_TFG-FOG @ 10 10 FOG-STATE 0 T-ASSERT

S" fog:reveal-centre-visible" T-NAME
_TFG-FOG @ 1 1 3 FOG-REVEAL
_TFG-FOG @ 1 1 FOG-STATE 2 T-ASSERT

S" fog:reveal-adjacent-visible" T-NAME
_TFG-FOG @ 2 1 FOG-STATE 2 T-ASSERT

S" fog:reveal-adjacent-visible2" T-NAME
_TFG-FOG @ 1 2 FOG-STATE 2 T-ASSERT

S" fog:reveal-corner-visible" T-NAME
_TFG-FOG @ 0 0 FOG-STATE 2 T-ASSERT

S" fog:far-tile-unseen" T-NAME
_TFG-FOG @ 9 9 FOG-STATE 0 T-ASSERT

S" fog:hide-all-demotes" T-NAME
_TFG-FOG @ FOG-HIDE-ALL
_TFG-FOG @ 1 1 FOG-STATE 1 T-ASSERT

S" fog:hide-all-remembered" T-NAME
_TFG-FOG @ 0 0 FOG-STATE 1 T-ASSERT

S" fog:hide-all-unseen-stays" T-NAME
_TFG-FOG @ 9 9 FOG-STATE 0 T-ASSERT

S" fog:re-reveal-visible" T-NAME
_TFG-FOG @ 1 1 3 FOG-REVEAL
_TFG-FOG @ 1 1 FOG-STATE 2 T-ASSERT

\ From (1,3) with radius 8 the wall hides the tiles behind it.
_TFG-FOG @ FOG-HIDE-ALL
_TFG-FOG @ 1 3 8 FOG-REVEAL

S" fog:wall-itself-visible" T-NAME
_TFG-FOG @ 3 3 FOG-STATE 2 T-ASSERT

S" fog:beside-wall-visible" T-NAME
_TFG-FOG @ 2 3 FOG-STATE 2 T-ASSERT

S" fog:behind-wall-blocked" T-NAME
_TFG-FOG @ 6 3 FOG-STATE 2 <>  _TFG-FOG @ 8 3 FOG-STATE 2 <> AND T-TRUE

S" fog:past-the-wall-visible" T-NAME
_TFG-FOG @ 6 5 FOG-STATE 2 T-ASSERT

\ Reveals between hides light one layer; a hide demotes all of them.
S" fog:second-source-adds" T-NAME
_TFG-FOG @ 8 8 2 FOG-REVEAL
_TFG-FOG @ 8 8 FOG-STATE 2 =  _TFG-FOG @ 2 3 FOG-STATE 2 = AND T-TRUE

S" fog:hide-demotes-both-sources" T-NAME
_TFG-FOG @ FOG-HIDE-ALL
_TFG-FOG @ 8 8 FOG-STATE 1 =  _TFG-FOG @ 2 3 FOG-STATE 1 = AND T-TRUE

S" fog:reset-forgets" T-NAME
_TFG-FOG @ FOG-RESET
_TFG-FOG @ 2 3 FOG-STATE 0 T-ASSERT

\ One wall at (2,2): from (0,0) the open tiles beside it stay in view and
\ the tiles behind it fall in its shadow.
10 10 CMAP-NEW CONSTANT _TFG-MAP2
_TFG-MAP2 2 2 1 CMAP-SET
10 10 FOG-NEW CONSTANT _TFG-FOG2
_TFG-FOG2 _TFG-MAP2 FOG-BLOCK-MAP!
_TFG-FOG2 0 0 8 FOG-REVEAL

S" fog:one-wall-open-tiles-visible" T-NAME
_TFG-FOG2 5 1 FOG-STATE 2 =  _TFG-FOG2 3 0 FOG-STATE 2 = AND
_TFG-FOG2 0 5 FOG-STATE 2 = AND T-TRUE

S" fog:one-wall-shadow" T-NAME
_TFG-FOG2 3 3 FOG-STATE 2 <>  _TFG-FOG2 4 4 FOG-STATE 2 <> AND T-TRUE

\ The same map through a token with a context cell sees the same tiles.
: _TFG-TOKEN  ( x y ctx -- flag )  -ROT CMAP-SOLID? ;
S" fog:token-source-agrees" T-NAME
10 10 FOG-NEW CONSTANT _TFG-FOG3
_TFG-FOG3 ' _TFG-TOKEN _TFG-MAP2 FOG-BLOCK-XT!
_TFG-FOG3 0 0 8 FOG-REVEAL
: _TFG-SAME?  ( -- flag )
    -1  10 0 DO 10 0 DO
        _TFG-FOG2 I J FOG-STATE _TFG-FOG3 I J FOG-STATE <> IF DROP 0 THEN
    LOOP LOOP ;
_TFG-SAME? T-TRUE

S" fog:free-each-block-once" T-NAME
-1 MLOG-HOLD  MLOG-START
_TFG-FOG @ FOG-FREE  _TFG-FOG2 FOG-FREE  _TFG-FOG3 FOG-FREE
MLOG-STOP  0 MLOG-HOLD
MLOG-REPEATS 0 T-ASSERT

""" + game_models.fog_forth(FOG_MAPS) + r"""
\ =====================================================================
\  §4 — Summary
\ =====================================================================

T-SUMMARY

"""


AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_phase7_suite.f
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
    fs.inject_file("test_phase7_suite.f", test_src, ftype=FTYPE_FORTH)

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

        sys_emu = MegapadSystem(ram_size=1024 * 1024,
                                ext_mem_size=16 * (1 << 20),
                                storage_image=img_path)
        buf = capture_uart(sys_emu)
        sys_emu.load_binary(0, bios_code)
        sys_emu.boot()

        print("[*] Running Phase 7 test suite...")
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
        diagnostics = kdos_diagnostics(text)
        if diagnostics:
            print(f"[!] KDOS reported: {', '.join(diagnostics)}")
            fatal = True
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

        # The behaviour trees' trials against the host model
        problems = game_models.bt_check(text, BT_TREES)
        print(f"  Behaviour trees: {len(BT_TREES)} trees against the host "
              f"model, {len(problems)} differences")
        for problem in problems[:20]:
            print(f"  \u2717 {problem}")
        if problems:
            fatal = True

        # The fog's layers against the host shadowcast
        problems = game_models.fog_check(text, FOG_MAPS)
        print(f"  Fog: {len(FOG_MAPS)} maps against the host shadowcast, "
              f"{len(problems)} differences")
        for problem in problems[:20]:
            print(f"  \u2717 {problem}")
        if problems:
            fatal = True

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


def test_suite() -> None:
    """The suite as a test, so the test selection tool runs it."""
    assert main() == 0


def test_shadowcast_oracle_is_symmetric_and_edge_blind() -> None:
    """The oracle's own properties, on small seeded maps.

    A floor tile sees another exactly when the other sees it, within the
    radius, and treating the outside of the map as open ground lights the
    same tiles inside it as treating it as walls.
    """
    import random

    rng = random.Random(7)
    for _ in range(40):
        width, height = rng.randint(3, 10), rng.randint(3, 8)
        density = rng.choice([0.1, 0.25, 0.4])
        walls = {(x, y) for y in range(height) for x in range(width)
                 if rng.random() < density}
        floors = [(x, y) for y in range(height) for x in range(width)
                  if (x, y) not in walls]
        radius = rng.randint(1, 10)
        seen = {tile: game_models.shadowcast(width, height, walls, *tile, radius)
                for tile in floors}
        for a in floors:
            assert seen[a] == game_models.shadowcast(
                width, height, walls, *a, radius, edge_blocks=False)
            for b in floors:
                assert (b in seen[a]) == (a in seen[b]), (a, b)


if __name__ == "__main__":
    sys.exit(main())
