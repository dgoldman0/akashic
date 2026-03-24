#!/usr/bin/env python3
"""Full test suite for tui/game/* modules (Phase 0 + Phase 1).

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
    # tui widgets needed by game-canvas
    ("canvas.f", "/tui/widgets", os.path.join(AK_DIR, "tui", "widgets", "canvas.f")),
    # standalone game engine (used by world-render for tilemap/sprite formats)
    ("loop.f",    "/game", os.path.join(AK_DIR, "game", "loop.f")),
    ("input.f",   "/game", os.path.join(AK_DIR, "game", "input.f")),
    ("tilemap.f", "/game", os.path.join(AK_DIR, "game", "tilemap.f")),
    ("sprite.f",  "/game", os.path.join(AK_DIR, "game", "sprite.f")),
    ("collide.f", "/game", os.path.join(AK_DIR, "game", "collide.f")),
    ("scene.f",   "/game", os.path.join(AK_DIR, "game", "scene.f")),
    # TUI game components (Phase 0 + Phase 1)
    ("game-view.f",     "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-view.f")),
    ("game-canvas.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-canvas.f")),
    ("game-applet.f",   "/tui/game", os.path.join(AK_DIR, "tui", "game", "game-applet.f")),
    ("atlas.f",         "/tui/game", os.path.join(AK_DIR, "tui", "game", "atlas.f")),
    ("camera.f",        "/tui/game", os.path.join(AK_DIR, "tui", "game", "camera.f")),
    ("world-render.f",  "/tui/game", os.path.join(AK_DIR, "tui", "game", "world-render.f")),
]

# ── Forth test harness ─────────────────────────────────────────
FORTH_HARNESS = r"""\ =====================================================================
\  test_tui_game_suite.f — Tests for tui/game/* (Phase 0 + Phase 1)
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

\ ── Load all modules ──────────────────────────────────────────

REQUIRE tui/game/game-view.f
REQUIRE tui/game/game-canvas.f
REQUIRE tui/game/game-applet.f
REQUIRE tui/game/atlas.f
REQUIRE tui/game/camera.f
REQUIRE tui/game/world-render.f

\ Need tilemap/sprite for world-render tests
REQUIRE game/tilemap.f
REQUIRE game/sprite.f

80 25 SCR-NEW SCR-USE

." [MODULES LOADED]" CR

\ ── Pre-declare test state ────────────────────────────────────

\ game-view test state
VARIABLE _GVT-WIDGET
VARIABLE _GVT-UPDATE-COUNT   0 _GVT-UPDATE-COUNT !
VARIABLE _GVT-DRAW-COUNT     0 _GVT-DRAW-COUNT !
VARIABLE _GVT-INPUT-COUNT    0 _GVT-INPUT-COUNT !
VARIABLE _GVT-RESIZE-COUNT   0 _GVT-RESIZE-COUNT !
VARIABLE _GVT-LAST-DT        0 _GVT-LAST-DT !

: _GVT-ON-UPDATE  ( dt -- )
    _GVT-LAST-DT !
    _GVT-UPDATE-COUNT @ 1+ _GVT-UPDATE-COUNT ! ;
: _GVT-ON-DRAW  ( rgn -- )
    DROP
    _GVT-DRAW-COUNT @ 1+ _GVT-DRAW-COUNT ! ;
: _GVT-ON-INPUT  ( ev -- )
    DROP
    _GVT-INPUT-COUNT @ 1+ _GVT-INPUT-COUNT ! ;
: _GVT-ON-RESIZE  ( w h -- )
    2DROP
    _GVT-RESIZE-COUNT @ 1+ _GVT-RESIZE-COUNT ! ;

\ game-canvas test state
VARIABLE _GCVST-WIDGET

\ game-applet test state
VARIABLE _GAPPT-DESC
VARIABLE _GAPPT-INIT-COUNT   0 _GAPPT-INIT-COUNT !
: _GAPPT-ON-INIT  _GAPPT-INIT-COUNT @ 1+ _GAPPT-INIT-COUNT ! ;
: _GAPPT-ON-UPDATE  ( dt -- ) DROP ;
: _GAPPT-ON-DRAW    ( rgn -- ) DROP ;
: _GAPPT-ON-INPUT   ( ev -- ) DROP ;
: _GAPPT-ON-SHUTDOWN ;

\ atlas test state
VARIABLE _ATT-ATLAS

\ camera test state
VARIABLE _CAMT-CAM

\ world-render test state
VARIABLE _WRENT-WREN
VARIABLE _WRENT-ATLAS
VARIABLE _WRENT-CAM

\ Shared test region
0 0 25 80 RGN-NEW CONSTANT _TEST-RGN


\ =====================================================================
\  §1 — game-view.f tests
\ =====================================================================

." --- game-view.f ---" CR

S" gv:new-returns-nonzero" T-NAME
_TEST-RGN GV-NEW DUP _GVT-WIDGET ! 0<> T-TRUE

S" gv:type-is-17" T-NAME
_GVT-WIDGET @ _WDG-O-TYPE + @ 17 T-ASSERT

S" gv:region-stored" T-NAME
_GVT-WIDGET @ _WDG-O-REGION + @ _TEST-RGN T-ASSERT

S" gv:flags-visible-dirty" T-NAME
_GVT-WIDGET @ _WDG-O-FLAGS + @
WDG-F-VISIBLE WDG-F-DIRTY OR T-ASSERT

S" gv:default-fps-30" T-NAME
_GVT-WIDGET @ 72 + @ 30 T-ASSERT

S" gv:default-frame-ms-33" T-NAME
_GVT-WIDGET @ 80 + @ 33 T-ASSERT

S" gv:default-frame-num-0" T-NAME
_GVT-WIDGET @ 104 + @ 0 T-ASSERT

S" gv:default-not-paused" T-NAME
_GVT-WIDGET @ GV-PAUSED? T-FALSE

S" gv:fps!-sets-fps" T-NAME
_GVT-WIDGET @ 60 GV-FPS!
_GVT-WIDGET @ 72 + @ 60 T-ASSERT

S" gv:fps!-sets-frame-ms" T-NAME
_GVT-WIDGET @ 80 + @ 16 T-ASSERT

S" gv:fps!-low-clamps" T-NAME
_GVT-WIDGET @ 1 GV-FPS!
_GVT-WIDGET @ 80 + @ 1000 T-ASSERT

S" gv:on-update-wires" T-NAME
_GVT-WIDGET @ ' _GVT-ON-UPDATE GV-ON-UPDATE
_GVT-WIDGET @ 40 + @ 0<> T-TRUE

S" gv:on-draw-wires" T-NAME
_GVT-WIDGET @ ' _GVT-ON-DRAW GV-ON-DRAW
_GVT-WIDGET @ 48 + @ 0<> T-TRUE

S" gv:on-input-wires" T-NAME
_GVT-WIDGET @ ' _GVT-ON-INPUT GV-ON-INPUT
_GVT-WIDGET @ 56 + @ 0<> T-TRUE

S" gv:on-resize-wires" T-NAME
_GVT-WIDGET @ ' _GVT-ON-RESIZE GV-ON-RESIZE
_GVT-WIDGET @ 64 + @ 0<> T-TRUE

S" gv:pause-sets-flag" T-NAME
_GVT-WIDGET @ GV-PAUSE
_GVT-WIDGET @ GV-PAUSED? T-TRUE

S" gv:resume-clears-flag" T-NAME
_GVT-WIDGET @ GV-RESUME
_GVT-WIDGET @ GV-PAUSED? T-FALSE

S" gv:frame-num-starts-0" T-NAME
_GVT-WIDGET @ GV-FRAME# 0 T-ASSERT

\ Restore FPS to 30 for tick tests
_GVT-WIDGET @ 30 GV-FPS!

\ =====================================================================
\  §2 — game-canvas.f tests
\ =====================================================================

." --- game-canvas.f ---" CR

S" gcvs:new-returns-nonzero" T-NAME
_TEST-RGN 30 GCVS-NEW DUP _GCVST-WIDGET ! 0<> T-TRUE

S" gcvs:type-is-18" T-NAME
_GCVST-WIDGET @ _WDG-O-TYPE + @ 18 T-ASSERT

S" gcvs:region-stored" T-NAME
_GCVST-WIDGET @ _WDG-O-REGION + @ _TEST-RGN T-ASSERT

S" gcvs:flags-visible-dirty" T-NAME
_GCVST-WIDGET @ _WDG-O-FLAGS + @
WDG-F-VISIBLE WDG-F-DIRTY OR T-ASSERT

S" gcvs:internal-gv-nonzero" T-NAME
_GCVST-WIDGET @ 40 + @ 0<> T-TRUE

S" gcvs:internal-cvs-nonzero" T-NAME
_GCVST-WIDGET @ 48 + @ 0<> T-TRUE

S" gcvs:auto-clear-default-on" T-NAME
_GCVST-WIDGET @ 64 + @ 0<> T-TRUE

S" gcvs:canvas-returns-cvs" T-NAME
_GCVST-WIDGET @ GCVS-CANVAS
_GCVST-WIDGET @ 48 + @ T-ASSERT

S" gcvs:dot-w-positive" T-NAME
_GCVST-WIDGET @ GCVS-DOT-W 0> T-TRUE

S" gcvs:dot-h-positive" T-NAME
_GCVST-WIDGET @ GCVS-DOT-H 0> T-TRUE

S" gcvs:auto-clear-toggle-off" T-NAME
_GCVST-WIDGET @ 0 GCVS-AUTO-CLEAR!
_GCVST-WIDGET @ 64 + @ 0= T-TRUE

S" gcvs:auto-clear-toggle-on" T-NAME
_GCVST-WIDGET @ -1 GCVS-AUTO-CLEAR!
_GCVST-WIDGET @ 64 + @ 0<> T-TRUE

S" gcvs:pause-delegates" T-NAME
_GCVST-WIDGET @ GCVS-PAUSE
_GCVST-WIDGET @ 40 + @ GV-PAUSED? T-TRUE

S" gcvs:resume-delegates" T-NAME
_GCVST-WIDGET @ GCVS-RESUME
_GCVST-WIDGET @ 40 + @ GV-PAUSED? T-FALSE


\ =====================================================================
\  §3 — game-applet.f tests
\ =====================================================================

." --- game-applet.f ---" CR

S" gapp:desc-returns-nonzero" T-NAME
GAME-APP-DESC DUP _GAPPT-DESC ! 0<> T-TRUE

S" gapp:init-xt-wired" T-NAME
_GAPPT-DESC @ APP.INIT-XT @ 0<> T-TRUE

S" gapp:event-xt-wired" T-NAME
_GAPPT-DESC @ APP.EVENT-XT @ 0<> T-TRUE

S" gapp:tick-xt-wired" T-NAME
_GAPPT-DESC @ APP.TICK-XT @ 0<> T-TRUE

S" gapp:paint-xt-wired" T-NAME
_GAPPT-DESC @ APP.PAINT-XT @ 0<> T-TRUE

S" gapp:shutdown-xt-wired" T-NAME
_GAPPT-DESC @ APP.SHUTDOWN-XT @ 0<> T-TRUE

S" gapp:default-fps-30" T-NAME
_GAPPT-DESC @ 152 + @ 30 T-ASSERT

S" gapp:default-gv-0" T-NAME
_GAPPT-DESC @ 160 + @ 0 T-ASSERT

S" gapp:fps!-stores" T-NAME
60 _GAPPT-DESC @ GAPP-FPS!
_GAPPT-DESC @ 152 + @ 60 T-ASSERT

S" gapp:on-init!-stores" T-NAME
' _GAPPT-ON-INIT _GAPPT-DESC @ GAPP-ON-INIT!
_GAPPT-DESC @ 112 + @ 0<> T-TRUE

S" gapp:on-update!-stores" T-NAME
' _GAPPT-ON-UPDATE _GAPPT-DESC @ GAPP-ON-UPDATE!
_GAPPT-DESC @ 120 + @ 0<> T-TRUE

S" gapp:on-draw!-stores" T-NAME
' _GAPPT-ON-DRAW _GAPPT-DESC @ GAPP-ON-DRAW!
_GAPPT-DESC @ 128 + @ 0<> T-TRUE

S" gapp:on-input!-stores" T-NAME
' _GAPPT-ON-INPUT _GAPPT-DESC @ GAPP-ON-INPUT!
_GAPPT-DESC @ 136 + @ 0<> T-TRUE

S" gapp:on-shutdown!-stores" T-NAME
' _GAPPT-ON-SHUTDOWN _GAPPT-DESC @ GAPP-ON-SHUTDOWN!
_GAPPT-DESC @ 144 + @ 0<> T-TRUE

S" gapp:title!-stores" T-NAME
S" Test Game" _GAPPT-DESC @ GAPP-TITLE!
_GAPPT-DESC @ APP.TITLE-U @ 9 T-ASSERT

S" gapp:gv-returns-0-before-init" T-NAME
_GAPPT-DESC @ GAPP-GV 0 T-ASSERT


\ =====================================================================
\  §4 — atlas.f tests
\ =====================================================================

." --- atlas.f ---" CR

S" atlas:new-returns-nonzero" T-NAME
64 ATLAS-NEW DUP _ATT-ATLAS ! 0<> T-TRUE

S" atlas:cap-returns-capacity" T-NAME
_ATT-ATLAS @ ATLAS-CAP 64 T-ASSERT

S" atlas:initial-count-0" T-NAME
_ATT-ATLAS @ 16 + @ 0 T-ASSERT

S" atlas:define-and-get-roundtrip" T-NAME
_ATT-ATLAS @ 0 CHAR # 7 1 0 ATLAS-DEFINE
_ATT-ATLAS @ 0 ATLAS-GET CELL-CP@ CHAR # T-ASSERT

S" atlas:define-fg-correct" T-NAME
_ATT-ATLAS @ 0 ATLAS-GET CELL-FG@ 7 T-ASSERT

S" atlas:define-bg-correct" T-NAME
_ATT-ATLAS @ 0 ATLAS-GET CELL-BG@ 1 T-ASSERT

S" atlas:define-multiple" T-NAME
_ATT-ATLAS @ 1 CHAR . 2 3 0 ATLAS-DEFINE
_ATT-ATLAS @ 2 CHAR ~ 4 5 0 ATLAS-DEFINE
_ATT-ATLAS @ 1 ATLAS-GET CELL-CP@ CHAR . T-ASSERT

S" atlas:get-tile-2" T-NAME
_ATT-ATLAS @ 2 ATLAS-GET CELL-CP@ CHAR ~ T-ASSERT

S" atlas:get-out-of-range-returns-blank" T-NAME
_ATT-ATLAS @ 999 ATLAS-GET CELL-BLANK T-ASSERT

S" atlas:get-undefined-returns-0" T-NAME
\ Tile 63 never defined — should be 0 (zero-filled data)
_ATT-ATLAS @ 63 ATLAS-GET 0 T-ASSERT

S" atlas:count-after-defines" T-NAME
_ATT-ATLAS @ 16 + @ 3 T-ASSERT

S" atlas:define-attrs" T-NAME
_ATT-ATLAS @ 10 CHAR X 7 0 5 ATLAS-DEFINE
_ATT-ATLAS @ 10 ATLAS-GET CELL-ATTRS@ 5 T-ASSERT

S" atlas:overwrite-tile" T-NAME
_ATT-ATLAS @ 0 CHAR @ 6 2 0 ATLAS-DEFINE
_ATT-ATLAS @ 0 ATLAS-GET CELL-CP@ CHAR @ T-ASSERT

S" atlas:new-cap-1" T-NAME
1 ATLAS-NEW ATLAS-CAP 1 T-ASSERT


\ =====================================================================
\  §5 — camera.f tests
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


\ =====================================================================
\  §6 — world-render.f tests
\ =====================================================================

." --- world-render.f ---" CR

S" wren:new-returns-nonzero" T-NAME
16 ATLAS-NEW _WRENT-ATLAS !
200 150 30 20 CAM-NEW _WRENT-CAM !
_TEST-RGN _WRENT-ATLAS @ _WRENT-CAM @ WREN-NEW
DUP _WRENT-WREN ! 0<> T-TRUE

S" wren:atlas-stored" T-NAME
_WRENT-WREN @ 0 + @ _WRENT-ATLAS @ T-ASSERT

S" wren:cam-stored" T-NAME
_WRENT-WREN @ 8 + @ _WRENT-CAM @ T-ASSERT

S" wren:rgn-stored" T-NAME
_WRENT-WREN @ 16 + @ _TEST-RGN T-ASSERT

S" wren:layers-initially-0" T-NAME
_WRENT-WREN @ 24 + @ 0 T-ASSERT

S" wren:layer1-initially-0" T-NAME
_WRENT-WREN @ 32 + @ 0 T-ASSERT

S" wren:layer2-initially-0" T-NAME
_WRENT-WREN @ 40 + @ 0 T-ASSERT

S" wren:layer3-initially-0" T-NAME
_WRENT-WREN @ 48 + @ 0 T-ASSERT

S" wren:spool-initially-0" T-NAME
_WRENT-WREN @ 56 + @ 0 T-ASSERT

\ Create a small tilemap for set-map test
4 4 TMAP-NEW CONSTANT _WREN-TEST-MAP

S" wren:set-map-layer0" T-NAME
_WRENT-WREN @ 0 _WREN-TEST-MAP WREN-SET-MAP
_WRENT-WREN @ 24 + @ _WREN-TEST-MAP T-ASSERT

S" wren:set-map-layer1" T-NAME
_WRENT-WREN @ 1 _WREN-TEST-MAP WREN-SET-MAP
_WRENT-WREN @ 32 + @ _WREN-TEST-MAP T-ASSERT

S" wren:set-map-layer2" T-NAME
_WRENT-WREN @ 2 _WREN-TEST-MAP WREN-SET-MAP
_WRENT-WREN @ 40 + @ _WREN-TEST-MAP T-ASSERT

S" wren:set-map-layer3" T-NAME
_WRENT-WREN @ 3 _WREN-TEST-MAP WREN-SET-MAP
_WRENT-WREN @ 48 + @ _WREN-TEST-MAP T-ASSERT

\ Create a sprite pool for set-sprites test
4 SPOOL-NEW CONSTANT _WREN-TEST-SPOOL

S" wren:set-sprites" T-NAME
_WRENT-WREN @ _WREN-TEST-SPOOL WREN-SET-SPRITES
_WRENT-WREN @ 56 + @ _WREN-TEST-SPOOL T-ASSERT


\ =====================================================================
\  Summary
\ =====================================================================

T-SUMMARY
"""

AUTOEXEC_F = r"""\ autoexec.f
ENTER-USERLAND
LOAD test_tui_game_suite.f
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
    fs.inject_file("test_tui_game_suite.f", test_src, ftype=FTYPE_FORTH)

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
            print("\n--- UART tail (last 1200 chars) ---")
            print(text[-1200:])

    finally:
        os.unlink(img_path)

    return rc


if __name__ == "__main__":
    sys.exit(main())
