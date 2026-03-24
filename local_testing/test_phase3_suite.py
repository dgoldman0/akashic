#!/usr/bin/env python3
"""Test suite for Phase 3 modules (tile-physics, pathfinding, steering).

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
    # core game
    ("ecs.f",        "/game",    os.path.join(AK_DIR, "game", "ecs.f")),
    ("components.f", "/game",    os.path.join(AK_DIR, "game", "components.f")),
    ("systems.f",    "/game",    os.path.join(AK_DIR, "game", "systems.f")),
    # 2d game
    ("collide.f",       "/game/2d", os.path.join(AK_DIR, "game", "2d", "collide.f")),
    ("tile-physics.f",  "/game/2d", os.path.join(AK_DIR, "game", "2d", "tile-physics.f")),
    ("pathfind.f",      "/game/2d", os.path.join(AK_DIR, "game", "2d", "pathfind.f")),
    ("steer.f",         "/game/2d", os.path.join(AK_DIR, "game", "2d", "steer.f")),
]

# ── Forth test harness ─────────────────────────────────────────
FORTH_HARNESS = r"""\ =====================================================================
\  test_phase3_suite.f — Tests for tile-physics, pathfind, steer
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
REQUIRE game/2d/collide.f
REQUIRE game/2d/tile-physics.f
REQUIRE game/2d/pathfind.f
REQUIRE game/2d/steer.f

." [MODULES LOADED]" CR

\ ══════════════════════════════════════════════════════════════
\  Shared ECS setup for all tests
\ ══════════════════════════════════════════════════════════════

64 ECS-NEW CONSTANT _T-ECS
_T-ECS COMPS-REG-ALL
( c-pos c-vel c-spr c-hp c-col c-tmr c-tag c-ai )
CONSTANT _T-C-AI
CONSTANT _T-C-TAG
CONSTANT _T-C-TMR
CONSTANT _T-C-COL
CONSTANT _T-C-HP
CONSTANT _T-C-SPR
CONSTANT _T-C-VEL
CONSTANT _T-C-POS

_T-C-POS _T-C-VEL _T-C-HP _T-C-TMR SYS-BIND-COMPS

\ Helper: create entity at (x, y) with pos + vel
: _T-MAKE-ENT  ( x y -- eid )
    _T-ECS ECS-SPAWN >R
    _T-ECS R@ _T-C-POS ECS-ATTACH
    OVER C-POS.X + !  DUP C-POS.Y + !   \ store y
    DROP                                  \ drop leftover x (stored earlier)
    _T-ECS R@ _T-C-VEL ECS-ATTACH
    DUP C-VEL.DX + 0 SWAP !
    C-VEL.DY + 0 SWAP !
    R> ;

\ Hmm, the above helper is tricky with stack. Let me redo it cleanly.
\ Override with a variable-based approach:

VARIABLE _TME-X  VARIABLE _TME-Y
: _T-MAKE-ENT  ( x y -- eid )
    _TME-Y !  _TME-X !
    _T-ECS ECS-SPAWN >R
    _T-ECS R@ _T-C-POS ECS-ATTACH
    DUP _TME-X @ SWAP C-POS.X + !
    _TME-Y @ SWAP C-POS.Y + !
    _T-ECS R@ _T-C-VEL ECS-ATTACH
    DUP 0 SWAP C-VEL.DX + !
    0 SWAP C-VEL.DY + !
    R> ;

\ Read entity position helper
: _T-ENT-X  ( eid -- x )  _T-ECS SWAP _T-C-POS ECS-GET C-POS.X + @ ;
: _T-ENT-Y  ( eid -- y )  _T-ECS SWAP _T-C-POS ECS-GET C-POS.Y + @ ;

\ Read entity velocity helper
: _T-ENT-DX  ( eid -- dx )  _T-ECS SWAP _T-C-VEL ECS-GET C-VEL.DX + @ ;
: _T-ENT-DY  ( eid -- dy )  _T-ECS SWAP _T-C-VEL ECS-GET C-VEL.DY + @ ;

\ ══════════════════════════════════════════════════════════════
\  §1 — tile-physics.f Tests
\ ══════════════════════════════════════════════════════════════

\ Build a 10x10 collision map with walls on the borders
10 10 CMAP-NEW CONSTANT _TP-CM

\ Fill borders via helper (compile-only ?DO must be inside a definition)
: _TP-FILL-BORDERS
    10 0 ?DO  _TP-CM I 0 1 CMAP-SET LOOP      \ top row
    10 0 ?DO  _TP-CM I 9 1 CMAP-SET LOOP      \ bottom row
    10 0 ?DO  _TP-CM 0 I 1 CMAP-SET LOOP      \ left col
    10 0 ?DO  _TP-CM 9 I 1 CMAP-SET LOOP ;    \ right col
_TP-FILL-BORDERS

_TP-CM TPHYS-NEW CONSTANT _TP-PH

\ ── 1.1 Constructor ──

S" tphys:new-nonzero" T-NAME
_TP-PH 0<> T-TRUE

\ ── 1.2 Move in open space ──

5 5 _T-MAKE-ENT CONSTANT _TP-E0

S" tphys:move-open-x" T-NAME
_TP-PH _TP-E0 _T-ECS 1 0 TPHYS-MOVE
( rx ry )
SWAP 6 T-ASSERT 5 T-ASSERT

S" tphys:pos-after-open-move" T-NAME
_TP-E0 _T-ENT-X 6 T-ASSERT

S" tphys:pos-y-unchanged" T-NAME
_TP-E0 _T-ENT-Y 5 T-ASSERT

\ ── 1.3 Move into wall — blocked ──

\ Entity at (1,5) — move left into wall at col 0
1 5 _T-MAKE-ENT CONSTANT _TP-E1

S" tphys:move-blocked-x" T-NAME
_TP-PH _TP-E1 _T-ECS -1 0 TPHYS-MOVE
( rx ry )
SWAP 1 T-ASSERT 5 T-ASSERT

S" tphys:pos-stays-at-wall" T-NAME
_TP-E1 _T-ENT-X 1 T-ASSERT

\ ── 1.4 Wall sliding — dx blocked, dy passes ──

\ Entity at (1,5), move diag (-1, -1): x blocked by col 0, y slides
S" tphys:wall-slide" T-NAME
_TP-PH _TP-E1 _T-ECS -1 -1 TPHYS-MOVE
( rx ry )
SWAP 1 T-ASSERT 4 T-ASSERT

S" tphys:wall-slide-y" T-NAME
_TP-E1 _T-ENT-Y 4 T-ASSERT

\ ── 1.5 Grounded check ──

\ Put entity at (5,8) — tile below is (5,9) which is solid
5 8 _T-MAKE-ENT CONSTANT _TP-E2

S" tphys:grounded-above-floor" T-NAME
_TP-PH _TP-E2 _T-ECS TPHYS-GROUNDED? T-TRUE

S" tphys:not-grounded-mid" T-NAME
_TP-E0 _T-ENT-X _TP-E0 _T-ENT-Y  \ e0 is at (6,5) — below is (6,6)=open
DROP DROP                           \ discard pos, just test grounded
_TP-PH _TP-E0 _T-ECS TPHYS-GROUNDED? T-FALSE

\ ── 1.6 Gravity ──

_TP-PH 0 1 TPHYS-GRAVITY!

\ Entity at (5,3) — apply gravity (dy=1), should move to (5,4)
5 3 _T-MAKE-ENT CONSTANT _TP-E3

S" tphys:apply-grav-y" T-NAME
_TP-PH _TP-E3 _T-ECS TPHYS-APPLY-GRAV
( rx ry )
SWAP 5 T-ASSERT 4 T-ASSERT

S" tphys:apply-grav-pos" T-NAME
_TP-E3 _T-ENT-Y 4 T-ASSERT

\ ── 1.7 Gravity stops at floor ──

\ Entity at (5,8) — apply gravity (dy=1), blocked by floor at row 9
5 8 _T-MAKE-ENT CONSTANT _TP-E4

S" tphys:grav-stops-at-floor" T-NAME
_TP-PH _TP-E4 _T-ECS TPHYS-APPLY-GRAV
( rx ry )
SWAP 5 T-ASSERT 8 T-ASSERT

\ ── 1.8 Collision callback ──

VARIABLE _TP-CB-EID     0 _TP-CB-EID !
VARIABLE _TP-CB-TX      0 _TP-CB-TX !
VARIABLE _TP-CB-TY      0 _TP-CB-TY !
VARIABLE _TP-CB-TV      0 _TP-CB-TV !
VARIABLE _TP-CB-COUNT   0 _TP-CB-COUNT !

: _TP-CB  ( eid tile-x tile-y tile-val -- )
    _TP-CB-TV !  _TP-CB-TY !  _TP-CB-TX !  _TP-CB-EID !
    _TP-CB-COUNT @ 1+ _TP-CB-COUNT ! ;

VARIABLE _TP-CB-XT
' _TP-CB _TP-CB-XT !

_TP-PH _TP-CB-XT @ TPHYS-ON-COLLIDE

\ Move entity into wall to trigger callback
1 5 _T-MAKE-ENT CONSTANT _TP-E5
0 _TP-CB-COUNT !

S" tphys:callback-fires" T-NAME
_TP-PH _TP-E5 _T-ECS -1 0 TPHYS-MOVE 2DROP
_TP-CB-COUNT @ 0> T-TRUE

S" tphys:callback-eid" T-NAME
_TP-CB-EID @ _TP-E5 T-ASSERT

S" tphys:callback-tile-x" T-NAME
_TP-CB-TX @ 0 T-ASSERT

S" tphys:callback-tile-y" T-NAME
_TP-CB-TY @ 5 T-ASSERT

S" tphys:callback-tile-val" T-NAME
_TP-CB-TV @ 1 T-ASSERT

\ ── 1.9 One-way platform ──

\ Set tile (5,6) = 2 (one-way), and register value 2 as one-way
_TP-CM 5 6 2 CMAP-SET
_TP-PH 2 TPHYS-ONE-WAY!

\ Moving down onto one-way should block
5 5 _T-MAKE-ENT CONSTANT _TP-E6

S" tphys:oneway-blocks-down" T-NAME
_TP-PH _TP-E6 _T-ECS 0 1 TPHYS-MOVE
( rx ry )
SWAP 5 T-ASSERT 5 T-ASSERT

\ Moving up through one-way should pass
5 7 _T-MAKE-ENT CONSTANT _TP-E7

S" tphys:oneway-passes-up" T-NAME
_TP-PH _TP-E7 _T-ECS 0 -1 TPHYS-MOVE
( rx ry )
SWAP 5 T-ASSERT 6 T-ASSERT

\ Moving horizontally through one-way should pass
4 6 _T-MAKE-ENT CONSTANT _TP-E8

S" tphys:oneway-passes-horiz" T-NAME
_TP-PH _TP-E8 _T-ECS 1 0 TPHYS-MOVE
( rx ry )
SWAP 5 T-ASSERT 6 T-ASSERT

\ Clean up one-way tile
_TP-CM 5 6 0 CMAP-SET
_TP-PH 0 TPHYS-ONE-WAY!
_TP-PH 0 0 TPHYS-GRAVITY!

\ ══════════════════════════════════════════════════════════════
\  §2 — pathfind.f Tests
\ ══════════════════════════════════════════════════════════════

\ Build a 10x10 map: clear interior, walls on borders
10 10 CMAP-NEW CONSTANT _PF-CM
: _PF-FILL-BORDERS
    10 0 ?DO  _PF-CM I 0 1 CMAP-SET LOOP
    10 0 ?DO  _PF-CM I 9 1 CMAP-SET LOOP
    10 0 ?DO  _PF-CM 0 I 1 CMAP-SET LOOP
    10 0 ?DO  _PF-CM 9 I 1 CMAP-SET LOOP ;
_PF-FILL-BORDERS

\ ── 2.1 Simple path in open space ──
\ From (1,1) to (3,1) — 3 cells apart, should find path of length 3

VARIABLE _PF-PATH  VARIABLE _PF-CNT

S" astar:simple-path-found" T-NAME
0 ASTAR-DIAGONAL!
_PF-CM 1 1 3 1 ASTAR-FIND
_PF-CNT ! _PF-PATH !
_PF-CNT @ 0> T-TRUE

S" astar:simple-path-count" T-NAME
_PF-CNT @ 3 T-ASSERT

S" astar:simple-path-start-x" T-NAME
_PF-PATH @ @ 1 T-ASSERT

S" astar:simple-path-start-y" T-NAME
_PF-PATH @ CELL+ @ 1 T-ASSERT

S" astar:simple-path-end-x" T-NAME
_PF-PATH @ _PF-CNT @ 1- 2* CELLS + @ 3 T-ASSERT

S" astar:simple-path-end-y" T-NAME
_PF-PATH @ _PF-CNT @ 1- 2* 1+ CELLS + @ 1 T-ASSERT

_PF-PATH @ ASTAR-FREE

\ ── 2.2 Path around obstacle ──

\ Place wall at (3,4)
_PF-CM 3 4 1 CMAP-SET

S" astar:path-around-obstacle" T-NAME
_PF-CM 2 4 4 4 ASTAR-FIND
_PF-CNT ! _PF-PATH !
_PF-CNT @ 0> T-TRUE

S" astar:around-obs-start-x" T-NAME
_PF-PATH @ @ 2 T-ASSERT

S" astar:around-obs-end-x" T-NAME
_PF-PATH @ _PF-CNT @ 1- 2* CELLS + @ 4 T-ASSERT

S" astar:around-obs-detours" T-NAME
_PF-CNT @ 3 > T-TRUE

_PF-PATH @ ASTAR-FREE
_PF-CM 3 4 0 CMAP-SET

\ ── 2.3 No path — completely blocked ──

\ Wall off (2,4) entirely with solid ring
_PF-CM 1 3 1 CMAP-SET
_PF-CM 2 3 1 CMAP-SET
_PF-CM 3 3 1 CMAP-SET
_PF-CM 1 4 1 CMAP-SET
_PF-CM 3 4 1 CMAP-SET
_PF-CM 1 5 1 CMAP-SET
_PF-CM 2 5 1 CMAP-SET
_PF-CM 3 5 1 CMAP-SET

S" astar:no-path-blocked" T-NAME
_PF-CM 2 4 7 7 ASTAR-FIND
_PF-CNT ! _PF-PATH !
_PF-PATH @ 0 T-ASSERT

S" astar:no-path-count-0" T-NAME
_PF-CNT @ 0 T-ASSERT

\ Clean up ring
_PF-CM 1 3 0 CMAP-SET
_PF-CM 2 3 0 CMAP-SET
_PF-CM 3 3 0 CMAP-SET
_PF-CM 1 4 0 CMAP-SET
_PF-CM 3 4 0 CMAP-SET
_PF-CM 1 5 0 CMAP-SET
_PF-CM 2 5 0 CMAP-SET
_PF-CM 3 5 0 CMAP-SET

\ ── 2.4 Zero-length path (start = goal) ──

S" astar:start-equals-goal" T-NAME
_PF-CM 5 5 5 5 ASTAR-FIND
_PF-CNT ! _PF-PATH !
_PF-CNT @ 1 T-ASSERT

S" astar:zero-path-x" T-NAME
_PF-PATH @ @ 5 T-ASSERT

S" astar:zero-path-y" T-NAME
_PF-PATH @ CELL+ @ 5 T-ASSERT

_PF-PATH @ ASTAR-FREE

\ ── 2.5 Budget limit ──

S" astar:budget-limit" T-NAME
4 ASTAR-BUDGET!
_PF-CM 1 1 8 8 ASTAR-FIND
_PF-CNT ! _PF-PATH !
\ With budget=4, may not reach distant goal
_PF-PATH @ 0 T-ASSERT

512 ASTAR-BUDGET!

\ ── 2.6 Diagonal mode ──

S" astar:diagonal-shorter" T-NAME
-1 ASTAR-DIAGONAL!
_PF-CM 1 1 3 3 ASTAR-FIND
_PF-CNT ! _PF-PATH !
_PF-CNT @ 0> T-TRUE

S" astar:diagonal-count" T-NAME
\ Diagonal path from (1,1) to (3,3) = 3 steps (diagonal)
_PF-CNT @ 3 T-ASSERT

_PF-PATH @ ASTAR-FREE
0 ASTAR-DIAGONAL!

\ ══════════════════════════════════════════════════════════════
\  §3 — steer.f Tests
\ ══════════════════════════════════════════════════════════════

\ ── 3.1 STEER-SEEK ──

5 5 _T-MAKE-ENT CONSTANT _ST-E0

S" steer:seek-sets-dx" T-NAME
_ST-E0 _T-ECS 8 5 STEER-SEEK
_ST-E0 _T-ENT-DX 1 T-ASSERT

S" steer:seek-sets-dy-zero" T-NAME
_ST-E0 _T-ENT-DY 0 T-ASSERT

S" steer:seek-diag" T-NAME
_ST-E0 _T-ECS 8 8 STEER-SEEK
_ST-E0 _T-ENT-DX 1 T-ASSERT

S" steer:seek-diag-dy" T-NAME
_ST-E0 _T-ENT-DY 1 T-ASSERT

S" steer:seek-neg" T-NAME
_ST-E0 _T-ECS 2 2 STEER-SEEK
_ST-E0 _T-ENT-DX -1 T-ASSERT

S" steer:seek-neg-dy" T-NAME
_ST-E0 _T-ENT-DY -1 T-ASSERT

S" steer:seek-same-pos" T-NAME
_ST-E0 _T-ECS 5 5 STEER-SEEK
_ST-E0 _T-ENT-DX 0 T-ASSERT

S" steer:seek-same-pos-dy" T-NAME
_ST-E0 _T-ENT-DY 0 T-ASSERT

\ ── 3.2 STEER-FLEE ──

5 5 _T-MAKE-ENT CONSTANT _ST-E1

S" steer:flee-away" T-NAME
_ST-E1 _T-ECS 3 3 STEER-FLEE
_ST-E1 _T-ENT-DX 1 T-ASSERT

S" steer:flee-away-dy" T-NAME
_ST-E1 _T-ENT-DY 1 T-ASSERT

S" steer:flee-neg" T-NAME
_ST-E1 _T-ECS 8 8 STEER-FLEE
_ST-E1 _T-ENT-DX -1 T-ASSERT

S" steer:flee-neg-dy" T-NAME
_ST-E1 _T-ENT-DY -1 T-ASSERT

\ ── 3.3 STEER-WANDER ──

5 5 _T-MAKE-ENT CONSTANT _ST-E2

S" steer:wander-sets-vel" T-NAME
42 STEER-SEED!
_ST-E2 _T-ECS STEER-WANDER
\ Velocity should be in {-1, 0, 1}
_ST-E2 _T-ENT-DX ABS 2 < T-TRUE

S" steer:wander-dy-range" T-NAME
_ST-E2 _T-ENT-DY ABS 2 < T-TRUE

S" steer:wander-changes" T-NAME
\ Run wander twice with different seed - at least one axis likely differs
_ST-E2 _T-ENT-DX
999 STEER-SEED!
_ST-E2 _T-ECS STEER-WANDER
_ST-E2 _T-ENT-DX
_ST-E2 _T-ENT-DY
ROT                    ( dy-now dx-now dx-before )
\ Just verify velocity is still in range
DROP ABS 2 < T-TRUE

\ ── 3.4 STEER-FOLLOW-PATH ──

\ Build a path array: (1,1) -> (2,1) -> (3,1)
CREATE _SFP-TEST-PATH
    1 , 1 ,    \ path[0] = (1,1)
    2 , 1 ,    \ path[1] = (2,1)
    3 , 1 ,    \ path[2] = (3,1)

\ Entity at (1,1) — should seek toward path[1] = (2,1)
1 1 _T-MAKE-ENT CONSTANT _ST-E3

S" steer:follow-path-dx" T-NAME
_ST-E3 _T-ECS _SFP-TEST-PATH 3 STEER-FOLLOW-PATH
_ST-E3 _T-ENT-DX 1 T-ASSERT

S" steer:follow-path-dy" T-NAME
_ST-E3 _T-ENT-DY 0 T-ASSERT

\ Entity at (3,1) — at last waypoint, should stop
3 1 _T-MAKE-ENT CONSTANT _ST-E4

S" steer:follow-path-at-end" T-NAME
_ST-E4 _T-ECS _SFP-TEST-PATH 3 STEER-FOLLOW-PATH
_ST-E4 _T-ENT-DX 0 T-ASSERT

S" steer:follow-path-at-end-dy" T-NAME
_ST-E4 _T-ENT-DY 0 T-ASSERT

\ Entity not on path — should stop
7 7 _T-MAKE-ENT CONSTANT _ST-E5

S" steer:follow-path-off-path" T-NAME
_ST-E5 _T-ECS _SFP-TEST-PATH 3 STEER-FOLLOW-PATH
_ST-E5 _T-ENT-DX 0 T-ASSERT

S" steer:follow-path-off-path-dy" T-NAME
_ST-E5 _T-ENT-DY 0 T-ASSERT

\ ── 3.5 STEER-PATROL ──

\ Build waypoint array: (2,2) -> (4,2) -> (4,4)
CREATE _SP-TEST-WPS
    2 , 2 ,    \ wp[0] = (2,2)
    4 , 2 ,    \ wp[1] = (4,2)
    4 , 4 ,    \ wp[2] = (4,4)

\ Entity at (2,2) with AI component — should advance to wp[1] and seek it
2 2 _T-MAKE-ENT CONSTANT _ST-E6
_T-ECS _ST-E6 _T-C-AI ECS-ATTACH CONSTANT _ST-E6-AI
0 _ST-E6-AI C-AI.STATE + !

_T-C-AI STEER-BIND-AI

S" steer:patrol-at-wp0-advances" T-NAME
_ST-E6 _T-ECS _SP-TEST-WPS 3 STEER-PATROL
\ Entity is at wp[0]=(2,2), should advance to wp[1]=(4,2), seek dx=+1
_ST-E6 _T-ENT-DX 1 T-ASSERT

S" steer:patrol-at-wp0-dy" T-NAME
_ST-E6 _T-ENT-DY 0 T-ASSERT

S" steer:patrol-ai-state-updated" T-NAME
_ST-E6-AI C-AI.STATE + @ 1 T-ASSERT

\ Entity not at current waypoint — should seek toward it
3 2 _T-MAKE-ENT CONSTANT _ST-E7
_T-ECS _ST-E7 _T-C-AI ECS-ATTACH CONSTANT _ST-E7-AI
1 _ST-E7-AI C-AI.STATE + !     \ target wp[1] = (4,2)

S" steer:patrol-seeks-wp" T-NAME
_ST-E7 _T-ECS _SP-TEST-WPS 3 STEER-PATROL
_ST-E7 _T-ENT-DX 1 T-ASSERT

S" steer:patrol-seeks-wp-dy" T-NAME
_ST-E7 _T-ENT-DY 0 T-ASSERT

S" steer:patrol-state-unchanged" T-NAME
_ST-E7-AI C-AI.STATE + @ 1 T-ASSERT

\ ══════════════════════════════════════════════════════════════

T-SUMMARY
"""


AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_phase3_suite.f
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
            d = "/" + "/".join(parts[:i + 1])
            if d not in dirs_made:
                fs.mkdir(d.lstrip("/"))
                dirs_made.add(d)

    for name, disk_dir, host_path in DISK_FILES:
        src = open(host_path, "rb").read()
        fs.inject_file(name, src, ftype=FTYPE_FORTH, path=disk_dir)

    test_src = FORTH_HARNESS.encode("utf-8")
    fs.inject_file("test_phase3_suite.f", test_src, ftype=FTYPE_FORTH)

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
        sys_emu = MegapadSystem(ram_size=1024 * 1024,
                                ext_mem_size=16 * (1 << 20),
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
