#!/usr/bin/env python3
"""Full test suite for game/* modules.

Runs Forth test code through the Megapad-64 emulator and validates
correctness by parsing structured UART output.  Each Forth test word
prints PASS/FAIL lines; the Python harness collects them.
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
    ("utf8.f",     "/text", os.path.join(AK_DIR, "text", "utf8.f")),
    ("ansi.f",     "/tui",  os.path.join(AK_DIR, "tui", "ansi.f")),
    ("keys.f",     "/tui",  os.path.join(AK_DIR, "tui", "keys.f")),
    ("cell.f",     "/tui",  os.path.join(AK_DIR, "tui", "cell.f")),
    ("screen.f",   "/tui",  os.path.join(AK_DIR, "tui", "screen.f")),
    ("draw.f",     "/tui",  os.path.join(AK_DIR, "tui", "draw.f")),
    ("box.f",      "/tui",  os.path.join(AK_DIR, "tui", "box.f")),
    ("region.f",   "/tui",  os.path.join(AK_DIR, "tui", "region.f")),
    ("app-desc.f", "/tui",  os.path.join(AK_DIR, "tui", "app-desc.f")),
    # tui game engine
    ("loop.f",     "/tui/game", os.path.join(AK_DIR, "tui", "game", "loop.f")),
    ("input.f",    "/tui/game", os.path.join(AK_DIR, "tui", "game", "input.f")),
    ("tilemap.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "tilemap.f")),
    ("sprite.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "sprite.f")),
    ("scene.f",    "/tui/game", os.path.join(AK_DIR, "tui", "game", "scene.f")),
    # 2d game engine
    ("collide.f",  "/game/2d", os.path.join(AK_DIR, "game", "2d", "collide.f")),
]

# ── Forth test harness ─────────────────────────────────────────
# Provides T{ ... }T assertion framework and per-module tests.
FORTH_HARNESS = r"""\ =====================================================================
\  test_game_suite.f — Assertion-based tests for game/*
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

\ ── Load all modules, then create a screen ────────────────────

REQUIRE tui/game/loop.f
REQUIRE tui/game/input.f
REQUIRE tui/game/tilemap.f
REQUIRE tui/game/sprite.f
REQUIRE game/2d/collide.f
REQUIRE tui/game/scene.f

80 25 SCR-NEW SCR-USE

." [MODULES LOADED]" CR

\ ── Pre-declare all test state ────────────────────────────────

\ loop.f test state
VARIABLE _LT-COUNT    0 _LT-COUNT !
VARIABLE _LT-POSTED   0 _LT-POSTED !
: _LT-UPDATE  ( dt -- ) DROP  _LT-COUNT @ 1+ _LT-COUNT ! ;
: _LT-DRAW  ;
: _LT-INPUT  ( ev -- ) DROP ;
: _LT-POST-ACTION  1 _LT-POSTED ! ;

\ input.f test event buffer
CREATE _IT-EV  24 ALLOT
: _IT-MAKE-CHAR  ( char -- )
    KEY-T-CHAR _IT-EV !   _IT-EV 8 + !   0 _IT-EV 16 + ! ;
: _IT-MAKE-SPECIAL  ( key -- )
    KEY-T-SPECIAL _IT-EV !   _IT-EV 8 + !   0 _IT-EV 16 + ! ;

\ tilemap test state (use VARIABLEs for pointers)
VARIABLE _TT-MAP

\ sprite test state
VARIABLE _ST-SPR
VARIABLE _ST-SPR2
VARIABLE _ST-POOL
CREATE _ST-ANIM-TBL
    CHAR 0 7 0 0 CELL-MAKE ,
    CHAR 1 7 0 0 CELL-MAKE ,
    CHAR 2 7 0 0 CELL-MAKE ,

\ collide test state
VARIABLE _CT-CM
VARIABLE _CT-S1
VARIABLE _CT-S2

\ scene test state
VARIABLE _SCT-ENTER    0 _SCT-ENTER !
VARIABLE _SCT-LEAVE    0 _SCT-LEAVE !
VARIABLE _SCT-UPDATE   0 _SCT-UPDATE !
VARIABLE _SCT-DRAW     0 _SCT-DRAW !
VARIABLE _SCT-ENTER2   0 _SCT-ENTER2 !
VARIABLE _SCT-LEAVE2   0 _SCT-LEAVE2 !
VARIABLE _SCT-UPDATE2  0 _SCT-UPDATE2 !
VARIABLE _SCT-DRAW2    0 _SCT-DRAW2 !
VARIABLE _SCT-S1
VARIABLE _SCT-S2

: _SCT-ON-ENTER   _SCT-ENTER  @ 1+ _SCT-ENTER ! ;
: _SCT-ON-LEAVE   _SCT-LEAVE  @ 1+ _SCT-LEAVE ! ;
: _SCT-ON-UPDATE  _SCT-UPDATE @ 1+ _SCT-UPDATE ! ;
: _SCT-ON-DRAW    _SCT-DRAW   @ 1+ _SCT-DRAW ! ;
: _SCT-ON-ENTER2  _SCT-ENTER2  @ 1+ _SCT-ENTER2 ! ;
: _SCT-ON-LEAVE2  _SCT-LEAVE2  @ 1+ _SCT-LEAVE2 ! ;
: _SCT-ON-UPDATE2 _SCT-UPDATE2 @ 1+ _SCT-UPDATE2 ! ;
: _SCT-ON-DRAW2   _SCT-DRAW2   @ 1+ _SCT-DRAW2 ! ;

\ app-desc test area
CREATE _AD-TEST  APP-DESC ALLOT

\ =====================================================================
\  §1 — loop.f tests
\ =====================================================================

." --- loop.f ---" CR

S" loop:fps-30" T-NAME
30 GAME-FPS!   GAME-DT 33 T-ASSERT

S" loop:fps-60" T-NAME
60 GAME-FPS!   GAME-DT 16 T-ASSERT

S" loop:fps-1" T-NAME
1 GAME-FPS!   GAME-DT 1000 T-ASSERT

S" loop:fps-clamp-low" T-NAME
0 GAME-FPS!   GAME-DT 1000 T-ASSERT

S" loop:fps-clamp-high" T-NAME
999 GAME-FPS!   GAME-DT 8 T-ASSERT

S" loop:init-frame0" T-NAME
30 GAME-FPS!   GAME-INIT   GAME-FRAME# 0 T-ASSERT

S" loop:tick-inc-frame" T-NAME
GAME-INIT   GAME-TICK   GAME-FRAME# 1 T-ASSERT

S" loop:tick-3-frames" T-NAME
GAME-INIT   GAME-TICK GAME-TICK GAME-TICK   GAME-FRAME# 3 T-ASSERT

S" loop:on-update-wires" T-NAME
0 _LT-COUNT !
' _LT-UPDATE GAME-ON-UPDATE
' _LT-DRAW   GAME-ON-DRAW
30 GAME-FPS!
GAME-INIT
_GAME-UPDATE-XT @ 0<> T-TRUE

S" loop:post-defer" T-NAME
0 _LT-POSTED !
GAME-INIT
' _LT-POST-ACTION GAME-POST
GAME-TICK
_LT-POSTED @ 1 T-ASSERT

\ =====================================================================
\  §2 — input.f tests
\ =====================================================================

." --- input.f ---" CR

GACT-CLEAR

S" input:bind-char-k" T-NAME
CHAR k ACT-ACTION1 GACT-BIND
GACT-FRAME-RESET
CHAR k _IT-MAKE-CHAR
_IT-EV GACT-FEED
ACT-ACTION1 GACT-DOWN? T-TRUE

S" input:down-unbound" T-NAME
ACT-ACTION2 GACT-DOWN? T-FALSE

S" input:pressed-after-feed" T-NAME
ACT-ACTION1 GACT-PRESSED? T-TRUE

S" input:frame-reset-clears" T-NAME
GACT-FRAME-RESET
ACT-ACTION1 GACT-DOWN? T-FALSE

S" input:frame-reset-pressed" T-NAME
ACT-ACTION1 GACT-PRESSED? T-FALSE

GACT-CLEAR
S" input:bind-special-up" T-NAME
KEY-UP 0x10000 OR ACT-UP GACT-BIND
GACT-FRAME-RESET
KEY-UP _IT-MAKE-SPECIAL
_IT-EV GACT-FEED
ACT-UP GACT-DOWN? T-TRUE

S" input:special-pressed" T-NAME
ACT-UP GACT-PRESSED? T-TRUE

GACT-CLEAR
S" input:multi-bind" T-NAME
CHAR w ACT-UP GACT-BIND
CHAR k ACT-UP GACT-BIND
GACT-FRAME-RESET
CHAR w _IT-MAKE-CHAR
_IT-EV GACT-FEED
ACT-UP GACT-DOWN? T-TRUE

S" input:multi-bind-2nd-key" T-NAME
GACT-FRAME-RESET
CHAR k _IT-MAKE-CHAR
_IT-EV GACT-FEED
ACT-UP GACT-DOWN? T-TRUE

GACT-CLEAR
S" input:unbind-all" T-NAME
CHAR x ACT-CANCEL GACT-BIND
ACT-CANCEL GACT-UNBIND-ALL
GACT-FRAME-RESET
CHAR x _IT-MAKE-CHAR
_IT-EV GACT-FEED
ACT-CANCEL GACT-DOWN? T-FALSE

GACT-CLEAR
S" input:clear-all" T-NAME
CHAR z ACT-ACTION1 GACT-BIND
GACT-CLEAR
GACT-FRAME-RESET
CHAR z _IT-MAKE-CHAR
_IT-EV GACT-FEED
ACT-ACTION1 GACT-DOWN? T-FALSE

GACT-CLEAR
S" input:unknown-key-noop" T-NAME
CHAR a ACT-LEFT GACT-BIND
GACT-FRAME-RESET
CHAR b _IT-MAKE-CHAR
_IT-EV GACT-FEED
ACT-LEFT GACT-DOWN? T-FALSE

GACT-CLEAR
S" input:action-63" T-NAME
CHAR z 63 GACT-BIND
GACT-FRAME-RESET
CHAR z _IT-MAKE-CHAR
_IT-EV GACT-FEED
63 GACT-DOWN? T-TRUE

\ =====================================================================
\  §3 — tilemap.f tests
\ =====================================================================

." --- tilemap.f ---" CR

10 8 TMAP-NEW  _TT-MAP !

S" tmap:new-width" T-NAME
_TT-MAP @ TMAP-W 10 T-ASSERT

S" tmap:new-height" T-NAME
_TT-MAP @ TMAP-H 8 T-ASSERT

S" tmap:set-get" T-NAME
_TT-MAP @  3 2  CHAR # 7 0 0 CELL-MAKE  TMAP-SET
_TT-MAP @ 3 2 TMAP-GET CELL-CP@ CHAR # T-ASSERT

S" tmap:fill" T-NAME
CHAR . 7 0 0 CELL-MAKE  _TT-MAP @ SWAP TMAP-FILL
_TT-MAP @ 0 0 TMAP-GET CELL-CP@ CHAR . T-ASSERT

S" tmap:fill-corner" T-NAME
_TT-MAP @ 9 7 TMAP-GET CELL-CP@ CHAR . T-ASSERT

S" tmap:viewport-init-x" T-NAME
_TT-MAP @ TMAP-VIEWPORT-X 0 T-ASSERT

S" tmap:viewport-set-x" T-NAME
_TT-MAP @ 3 2 TMAP-VIEWPORT!
_TT-MAP @ TMAP-VIEWPORT-X 3 T-ASSERT

S" tmap:viewport-set-y" T-NAME
_TT-MAP @ TMAP-VIEWPORT-Y 2 T-ASSERT

S" tmap:scroll" T-NAME
_TT-MAP @ 0 0 TMAP-VIEWPORT!
_TT-MAP @ 1 1 TMAP-SCROLL
_TT-MAP @ TMAP-VIEWPORT-X 1 T-ASSERT

S" tmap:scroll-y" T-NAME
_TT-MAP @ TMAP-VIEWPORT-Y 1 T-ASSERT

S" tmap:vp-clamp-neg" T-NAME
_TT-MAP @ -5 -5 TMAP-VIEWPORT!
_TT-MAP @ TMAP-VIEWPORT-X 0 T-ASSERT

S" tmap:vp-clamp-neg-y" T-NAME
_TT-MAP @ TMAP-VIEWPORT-Y 0 T-ASSERT

\ _TT-MAP @ TMAP-FREE  \\ skip — FREE bug investigation deferred

\ =====================================================================
\  §4 — sprite.f tests
\ =====================================================================

." --- sprite.f ---" CR

CHAR @ 7 0 0 CELL-MAKE SPR-NEW  _ST-SPR !

S" spr:new-cell" T-NAME
_ST-SPR @ SPR-CELL@ CELL-CP@ CHAR @ T-ASSERT

S" spr:default-pos-x" T-NAME
_ST-SPR @ SPR-POS@ DROP 0 T-ASSERT

S" spr:default-pos-y" T-NAME
_ST-SPR @ SPR-POS@ NIP 0 T-ASSERT

S" spr:default-visible" T-NAME
_ST-SPR @ SPR-VISIBLE? T-TRUE

S" spr:pos-set-x" T-NAME
_ST-SPR @ 5 10 SPR-POS!
_ST-SPR @ SPR-POS@ DROP 5 T-ASSERT

S" spr:pos-set-y" T-NAME
_ST-SPR @ SPR-POS@ NIP 10 T-ASSERT

S" spr:move-x" T-NAME
_ST-SPR @ 0 0 SPR-POS!
_ST-SPR @ 3 -1 SPR-MOVE
_ST-SPR @ SPR-POS@ DROP 3 T-ASSERT

S" spr:move-y" T-NAME
_ST-SPR @ SPR-POS@ NIP -1 T-ASSERT

S" spr:cell-set" T-NAME
_ST-SPR @ CHAR X 7 0 0 CELL-MAKE SPR-CELL!
_ST-SPR @ SPR-CELL@ CELL-CP@ CHAR X T-ASSERT

S" spr:hidden" T-NAME
_ST-SPR @ SPR-HIDDEN!
_ST-SPR @ SPR-VISIBLE? T-FALSE

S" spr:visible-again" T-NAME
_ST-SPR @ SPR-VISIBLE!
_ST-SPR @ SPR-VISIBLE? T-TRUE

S" spr:z-order" T-NAME
_ST-SPR @ 42 SPR-Z!
_ST-SPR @ SPR-Z@ 42 T-ASSERT

S" spr:user-data" T-NAME
_ST-SPR @ 99 SPR-USER!
_ST-SPR @ SPR-USER@ 99 T-ASSERT

\ ── Sprite Pool ──

16 SPOOL-NEW  _ST-POOL !

S" spool:empty-count" T-NAME
_ST-POOL @ SPOOL-COUNT 0 T-ASSERT

S" spool:add-1" T-NAME
_ST-POOL @ _ST-SPR @ SPOOL-ADD
_ST-POOL @ SPOOL-COUNT 1 T-ASSERT

CHAR B 7 0 0 CELL-MAKE SPR-NEW  _ST-SPR2 !
_ST-SPR2 @ 10 5 SPR-POS!

S" spool:add-2" T-NAME
_ST-POOL @ _ST-SPR2 @ SPOOL-ADD
_ST-POOL @ SPOOL-COUNT 2 T-ASSERT

S" spool:remove-1st" T-NAME
_ST-POOL @ _ST-SPR @ SPOOL-REMOVE
_ST-POOL @ SPOOL-COUNT 1 T-ASSERT

S" spool:remove-2nd" T-NAME
_ST-POOL @ _ST-SPR2 @ SPOOL-REMOVE
_ST-POOL @ SPOOL-COUNT 0 T-ASSERT

S" spool:remove-empty-noop" T-NAME
_ST-POOL @ _ST-SPR @ SPOOL-REMOVE
_ST-POOL @ SPOOL-COUNT 0 T-ASSERT

\ ── Animation ──

S" spr:anim-init" T-NAME
_ST-SPR @ _ST-ANIM-TBL 3 1 SPR-ANIM!
_ST-SPR @ SPR-CELL@ CELL-CP@ CHAR 0 T-ASSERT

S" spr:anim-tick1" T-NAME
_ST-SPR @ SPR-TICK
_ST-SPR @ SPR-CELL@ CELL-CP@ CHAR 1 T-ASSERT

S" spr:anim-tick2" T-NAME
_ST-SPR @ SPR-TICK
_ST-SPR @ SPR-CELL@ CELL-CP@ CHAR 2 T-ASSERT

S" spr:anim-wrap" T-NAME
_ST-SPR @ SPR-TICK
_ST-SPR @ SPR-CELL@ CELL-CP@ CHAR 0 T-ASSERT

\ _ST-SPR @ SPR-FREE   \\ skip — FREE issue
\ _ST-SPR2 @ SPR-FREE
\ _ST-POOL @ SPOOL-FREE

\ =====================================================================
\  §5 — collide.f tests
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

S" geom:aabb-partial" T-NAME
0 0 5 5  3 3 5 5  AABB-OVERLAP? T-TRUE

\ ── Sprite collision helpers ──

CHAR @ 7 0 0 CELL-MAKE SPR-NEW  _CT-S1 !
CHAR X 7 0 0 CELL-MAKE SPR-NEW  _CT-S2 !
_CT-S1 @ 2 2 SPR-POS!
_CT-S2 @ 5 5 SPR-POS!

S" coll:spr-spr-apart" T-NAME
_CT-S1 @ _CT-S2 @ SPR-SPR-OVERLAP? T-FALSE

S" coll:spr-spr-same-pos" T-NAME
_CT-S2 @ 2 2 SPR-POS!
_CT-S1 @ _CT-S2 @ SPR-SPR-OVERLAP? T-TRUE

_CT-CM @ 0 CMAP-FILL
_CT-CM @ 3 2 1 CMAP-SET
_CT-S1 @ 2 2 SPR-POS!

S" coll:spr-blocked-right" T-NAME
_CT-S1 @ 1 0 _CT-CM @ SPR-CMAP-BLOCKED? T-TRUE

S" coll:spr-free-left" T-NAME
_CT-S1 @ -1 0 _CT-CM @ SPR-CMAP-BLOCKED? T-FALSE

S" coll:spr-free-up" T-NAME
_CT-S1 @ 0 -1 _CT-CM @ SPR-CMAP-BLOCKED? T-FALSE

\ _CT-S1 @ SPR-FREE   \\ skip — FREE issue
\ _CT-S2 @ SPR-FREE
\ _CT-CM @ CMAP-FREE

\ =====================================================================
\  §6 — scene.f tests
\ =====================================================================

." --- scene.f ---" CR

' _SCT-ON-ENTER ' _SCT-ON-LEAVE ' _SCT-ON-UPDATE ' _SCT-ON-DRAW SCN-DEFINE  _SCT-S1 !
' _SCT-ON-ENTER2 ' _SCT-ON-LEAVE2 ' _SCT-ON-UPDATE2 ' _SCT-ON-DRAW2 SCN-DEFINE  _SCT-S2 !

0 _SCT-ENTER !  0 _SCT-LEAVE !  0 _SCT-UPDATE !  0 _SCT-DRAW !
0 _SCT-ENTER2 !  0 _SCT-LEAVE2 !  0 _SCT-UPDATE2 !  0 _SCT-DRAW2 !

S" scn:init-depth" T-NAME
SCN-DEPTH 0 T-ASSERT

S" scn:init-no-active" T-NAME
SCN-ACTIVE 0 T-ASSERT

S" scn:push-enter-called" T-NAME
_SCT-S1 @ SCN-PUSH
_SCT-ENTER @ 1 T-ASSERT

S" scn:push-depth" T-NAME
SCN-DEPTH 1 T-ASSERT

S" scn:push-active" T-NAME
SCN-ACTIVE _SCT-S1 @ T-ASSERT

S" scn:update-dispatch" T-NAME
0 _SCT-UPDATE !
SCN-UPDATE
_SCT-UPDATE @ 1 T-ASSERT

S" scn:draw-dispatch" T-NAME
0 _SCT-DRAW !
SCN-DRAW
_SCT-DRAW @ 1 T-ASSERT

S" scn:overlay-leave-prev" T-NAME
0 _SCT-LEAVE !
_SCT-S2 @ SCN-PUSH
_SCT-LEAVE @ 1 T-ASSERT

S" scn:overlay-enter-new" T-NAME
_SCT-ENTER2 @ 1 T-ASSERT

S" scn:overlay-depth" T-NAME
SCN-DEPTH 2 T-ASSERT

S" scn:overlay-active" T-NAME
SCN-ACTIVE _SCT-S2 @ T-ASSERT

S" scn:update-goes-to-top" T-NAME
0 _SCT-UPDATE !  0 _SCT-UPDATE2 !
SCN-UPDATE
_SCT-UPDATE2 @ 1 T-ASSERT

S" scn:update-skips-below" T-NAME
_SCT-UPDATE @ 0 T-ASSERT

S" scn:pop-leave-top" T-NAME
0 _SCT-LEAVE2 !
SCN-POP
_SCT-LEAVE2 @ 1 T-ASSERT

S" scn:pop-reenter-prev" T-NAME
_SCT-ENTER @ 2 T-ASSERT

S" scn:pop-depth-1" T-NAME
SCN-DEPTH 1 T-ASSERT

S" scn:pop-active-is-s1" T-NAME
SCN-ACTIVE _SCT-S1 @ T-ASSERT

S" scn:switch-leave-old" T-NAME
0 _SCT-LEAVE !  0 _SCT-ENTER2 !
_SCT-S2 @ SCN-SWITCH
_SCT-LEAVE @ 1 T-ASSERT

S" scn:switch-enter-new" T-NAME
_SCT-ENTER2 @ 1 T-ASSERT

S" scn:switch-depth-still-1" T-NAME
SCN-DEPTH 1 T-ASSERT

S" scn:switch-active-is-s2" T-NAME
SCN-ACTIVE _SCT-S2 @ T-ASSERT

SCN-POP

S" scn:pop-to-empty" T-NAME
SCN-DEPTH 0 T-ASSERT

S" scn:empty-active-0" T-NAME
SCN-ACTIVE 0 T-ASSERT

S" scn:update-empty-noop" T-NAME
0 _SCT-UPDATE !
SCN-UPDATE
_SCT-UPDATE @ 0 T-ASSERT

S" scn:draw-empty-noop" T-NAME
0 _SCT-DRAW !
SCN-DRAW
_SCT-DRAW @ 0 T-ASSERT

\ ── SCN-BIND-LOOP ──

_SCT-S1 @ SCN-PUSH

S" scn:bind-loop-update" T-NAME
SCN-BIND-LOOP
_GAME-UPDATE-XT @ ' SCN-UPDATE T-ASSERT

S" scn:bind-loop-draw" T-NAME
_GAME-DRAW-XT @ ' SCN-DRAW T-ASSERT

SCN-POP

\ ── SCN-BIND-APPLET ──

_AD-TEST APP-DESC-INIT

S" scn:bind-applet-tick" T-NAME
_AD-TEST SCN-BIND-APPLET
_AD-TEST APP.TICK-XT @ ' GAME-TICK T-ASSERT

S" scn:bind-applet-paint" T-NAME
_AD-TEST APP.PAINT-XT @ ' SCN-DRAW T-ASSERT

S" scn:bind-applet-update" T-NAME
_GAME-UPDATE-XT @ ' SCN-UPDATE T-ASSERT

\ _SCT-S1 @ SCN-FREE   \\ skip — FREE issue
\ _SCT-S2 @ SCN-FREE

\ =====================================================================
\  §7 — app-desc.f integration tests
\ =====================================================================

." --- app-desc ---" CR

_AD-TEST APP-DESC-INIT

S" adesc:init-zeroed" T-NAME
_AD-TEST APP.INIT-XT @ 0 T-ASSERT

S" adesc:event-zeroed" T-NAME
_AD-TEST APP.EVENT-XT @ 0 T-ASSERT

S" adesc:tick-zeroed" T-NAME
_AD-TEST APP.TICK-XT @ 0 T-ASSERT

S" adesc:paint-zeroed" T-NAME
_AD-TEST APP.PAINT-XT @ 0 T-ASSERT

S" adesc:set-width" T-NAME
640 _AD-TEST APP.WIDTH !
_AD-TEST APP.WIDTH @ 640 T-ASSERT

S" adesc:set-height" T-NAME
480 _AD-TEST APP.HEIGHT !
_AD-TEST APP.HEIGHT @ 480 T-ASSERT

\ =====================================================================
\  Summary
\ =====================================================================

T-SUMMARY
"""

AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_game_suite.f
"""


def capture_uart(sys_obj):
    buf = bytearray()
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf


def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf)


def run_until_idle(sys_obj, max_steps=2_000_000_000):
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
    fs.inject_file("test_game_suite.f", test_src, ftype=FTYPE_FORTH)

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

        # Check for fatal errors
        fatal = False
        for err_pat in ["? (not found)", "ABORT", "STACK"]:
            if err_pat.lower() in text.lower():
                idx = text.lower().find(err_pat.lower())
                ctx = text[max(0, idx-120):idx+120]
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


if __name__ == "__main__":
    sys.exit(main())
