#!/usr/bin/env python3
"""Test suite for tui/event.f (TUI Event Loop & Dispatch).

Every check runs on a fresh native machine (native_forth.py) with KDOS,
event.f and its closure loaded, and exercises:
  - Compilation (clean load of all deps + event.f)
  - TUI-EVT-QUIT / _TUI-EVT-RUNNING flag
  - Deferred action queue (TUI-EVT-POST + drain)
  - Timer tick mechanism
  - Dirty widget redraw via FOC-EACH
  - TUI-EVT-REDRAW flag
  - Global key handler registration
  - Loop start/quit cycle
"""
from native_forth import NativeForth

# Test helpers:
# _MOCK-DRAW / _MOCK-HANDLE: dummy draw / handle xts
# _MK-MOCK ( row col h w id -- wdg )  Allocate a mock widget
# _EV: event buffer (3 cells = 24 bytes)
# _HIT-ID: stores which widget-id the handler saw
# _DRAW-COUNT: counts how many times _MOCK-DRAW is called
# _TICK-COUNT: counts tick callback invocations
# _POST-LOG: counts posted action executions
TEST_HELPERS = (
    'VARIABLE _HIT-ID',
    'VARIABLE _DRAW-COUNT',
    'VARIABLE _TICK-COUNT',
    'VARIABLE _POST-LOG',
    'CREATE _EV 24 ALLOT',
    # Draw xt: increments _DRAW-COUNT
    ': _MOCK-DRAW ( wdg -- ) DROP  _DRAW-COUNT @ 1+ _DRAW-COUNT ! ;',
    # Handle xt: stores widget type-id in _HIT-ID, returns -1 (consumed)
    ': _MOCK-HANDLE ( ev wdg -- flag ) WDG-TYPE _HIT-ID ! DROP -1 ;',
    # _MK-MOCK ( row col h w id -- wdg )
    ': _MK-MOCK',
    '  >R',
    '  RGN-NEW',
    '  40 ALLOCATE DROP',
    '  DUP R>',
    '  3 PICK',
    "  ['] _MOCK-DRAW",
    "  ['] _MOCK-HANDLE",
    '  WDG-INIT',
    '  NIP',
    ';',
    # Screen creation helper (needed for SCR-FLUSH in event loop)
    '10 5 SCR-NEW SCR-USE',
)

# The tick tests need MS@ to advance as the machine runs.
SUITE = NativeForth(("tui/event.f",), prelude=TEST_HELPERS, live_clock=True)


def uart_text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw
    )


def run_forth(lines, max_steps=80_000_000):
    return uart_text(SUITE.run(lines, max_steps))


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    output = run_forth(forth_lines)
    last = "\n".join(output.strip().split("\n")[-8:])
    if check_fn:
        assert check_fn(output), f"{name}: check failed, got:\n{last}"
    elif expected is not None:
        assert expected in output, f"{name}: expected {expected!r}, got:\n{last}"
    if not_expected is not None:
        assert not_expected not in output, f"{name}: NOT expected {not_expected!r}, got:\n{last}"


# ═══════════════════════════════════════════════════════════════════
#  Mock widget helpers
# ═══════════════════════════════════════════════════════════════════

def _mk(row, col, h, w, wid):
    """Return Forth line creating a mock widget and leaving it on stack."""
    return f'{row} {col} {h} {w} {wid} _MK-MOCK'

def _mk_named(name, row, col, h, w, wid):
    """Return Forth lines creating a mock widget stored in a VARIABLE."""
    return [
        f'VARIABLE {name}',
        f'{_mk(row, col, h, w, wid)} {name} !',
    ]


# ═══════════════════════════════════════════════════════════════════
#  §A — Compilation
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    check("compile-clean", [
        '." COMPILE-OK" CR',
    ], "COMPILE-OK")


# ═══════════════════════════════════════════════════════════════════
#  §B — TUI-EVT-QUIT / Running Flag
# ═══════════════════════════════════════════════════════════════════

def test_quit_sets_flag():
    """TUI-EVT-QUIT sets _TUI-EVT-RUNNING to 0."""
    check("quit-flag", [
        '-1 _TUI-EVT-RUNNING !',
        'TUI-EVT-QUIT',
        '." R=" _TUI-EVT-RUNNING @ . CR',
    ], "R=0 ")

def test_running_flag_default():
    """_TUI-EVT-RUNNING is 0 by default (loop not entered yet)."""
    check("running-default", [
        '." R=" _TUI-EVT-RUNNING @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §C — Configuration Words
# ═══════════════════════════════════════════════════════════════════

def test_tick_ms():
    """TUI-EVT-TICK-MS! sets the tick interval."""
    check("tick-ms-set", [
        '200 TUI-EVT-TICK-MS!',
        '." R=" _TUI-EVT-TICK-MS @ . CR',
    ], "R=200 ")

def test_on_tick():
    """TUI-EVT-ON-TICK registers a callback xt."""
    check("on-tick-reg", [
        ': _MY-TICK  ." TICKED" ;',
        "' _MY-TICK TUI-EVT-ON-TICK",
        '_TUI-EVT-ON-TICK-XT @ EXECUTE CR',
    ], "TICKED")

def test_on_resize():
    """TUI-EVT-ON-RESIZE registers a callback xt."""
    check("on-resize-reg", [
        ': _MY-RESIZE ( w h -- ) + . ;',
        "' _MY-RESIZE TUI-EVT-ON-RESIZE",
        '80 24 _TUI-EVT-ON-RESIZE-XT @ EXECUTE CR',
    ], "104")

def test_on_key():
    """TUI-EVT-ON-KEY registers a global key handler xt."""
    check("on-key-reg", [
        ': _MY-KEY ( ev -- f ) DROP -1 ;',
        "' _MY-KEY TUI-EVT-ON-KEY",
        '." R=" _TUI-EVT-ON-KEY-XT @ 0<> . CR',
    ], "R=-1 ")

def test_redraw_flag():
    """TUI-EVT-REDRAW sets the redraw flag."""
    check("redraw-flag", [
        '0 _TUI-EVT-REDRAW-FLAG !',
        'TUI-EVT-REDRAW',
        '." R=" _TUI-EVT-REDRAW-FLAG @ 0<> . CR',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §D — Deferred Action Queue (TUI-EVT-POST)
# ═══════════════════════════════════════════════════════════════════

def test_post_single():
    """Post one action and drain — it executes."""
    check("post-single", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        '0 _POST-LOG !',
        ': _INC-LOG  _POST-LOG @ 1+ _POST-LOG ! ;',
        "' _INC-LOG TUI-EVT-POST",
        '_TUI-EVT-DRAIN-POSTED',
        '." R=" _POST-LOG @ . CR',
    ], "R=1 ")

def test_post_fifo_order():
    """Multiple posted actions execute in FIFO order."""
    check("post-fifo", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        ': _P1  ." A" ;',
        ': _P2  ." B" ;',
        ': _P3  ." C" ;',
        "' _P1 TUI-EVT-POST",
        "' _P2 TUI-EVT-POST",
        "' _P3 TUI-EVT-POST",
        '_TUI-EVT-DRAIN-POSTED',
        'CR',
    ], "ABC")

def test_post_drain_empty():
    """Draining empty queue is a no-op."""
    check("post-drain-empty", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        '_TUI-EVT-DRAIN-POSTED',
        '." OK" CR',
    ], "OK")

def test_post_overflow():
    """Posting more than 8 actions drops excess."""
    check("post-overflow", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        '0 _POST-LOG !',
        ': _INC-LOG2  _POST-LOG @ 1+ _POST-LOG ! ;',
        # Post 10 actions — only 8 should be stored
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",   # 9th — should be dropped
        "' _INC-LOG2 TUI-EVT-POST",   # 10th — should be dropped
        '_TUI-EVT-DRAIN-POSTED',
        '." R=" _POST-LOG @ . CR',
    ], "R=8 ")


# ═══════════════════════════════════════════════════════════════════
#  §E — Timer Tick Check
# ═══════════════════════════════════════════════════════════════════

def test_tick_no_callback():
    """_TUI-EVT-CHECK-TICK does nothing if no callback registered."""
    check("tick-no-cb", [
        '0 _TUI-EVT-ON-TICK-XT !',
        '_TUI-EVT-CHECK-TICK',
        '." OK" CR',
    ], "OK")

def test_tick_fires_when_elapsed():
    """Tick fires when enough time has elapsed."""
    check("tick-fires", [
        '0 _TICK-COUNT !',
        ': _MY-TICK3  _TICK-COUNT @ 1+ _TICK-COUNT ! ;',
        "' _MY-TICK3 TUI-EVT-ON-TICK",
        # Set tick interval very small and last-tick to 0 (far in the past)
        '1 TUI-EVT-TICK-MS!',
        '0 _TUI-EVT-LAST-TICK !',
        '_TUI-EVT-CHECK-TICK',
        '." R=" _TICK-COUNT @ . CR',
    ], "R=1 ")

def test_tick_skips_when_recent():
    """Tick doesn't fire if interval hasn't elapsed."""
    check("tick-skips", [
        '0 _TICK-COUNT !',
        ': _MY-TICK4  _TICK-COUNT @ 1+ _TICK-COUNT ! ;',
        "' _MY-TICK4 TUI-EVT-ON-TICK",
        # Set tick interval very large and last-tick to now
        '999999 TUI-EVT-TICK-MS!',
        'MS@ _TUI-EVT-LAST-TICK !',
        '_TUI-EVT-CHECK-TICK',
        '." R=" _TICK-COUNT @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §F — Dirty Widget Redraw
# ═══════════════════════════════════════════════════════════════════

def test_draw_dirty_widget():
    """_TUI-EVT-DRAW-DIRTY redraws dirty widgets in the focus chain."""
    check("draw-dirty", [
        'FOC-CLEAR',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WA', 0, 0, 1, 10, 1) + [
        '_WA @ FOC-ADD',
        # Widget starts VISIBLE|DIRTY from WDG-INIT
        '_TUI-EVT-DRAW-DIRTY',
        '." R=" _DRAW-COUNT @ . CR',
    ], "R=1 ")

def test_draw_clean_skipped():
    """Clean widgets are not redrawn."""
    check("draw-clean-skip", [
        'FOC-CLEAR',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WB', 0, 0, 1, 10, 2) + [
        '_WB @ FOC-ADD',
        '_WB @ WDG-CLEAN',   # clear dirty flag
        '_TUI-EVT-DRAW-DIRTY',
        '." R=" _DRAW-COUNT @ . CR',
    ], "R=0 ")

def test_redraw_marks_all_dirty():
    """TUI-EVT-REDRAW + _TUI-EVT-DRAW-DIRTY redraws all widgets."""
    check("redraw-all", [
        'FOC-CLEAR',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WC', 0, 0, 1, 10, 3) + [
        '_WC @ FOC-ADD',
    ] + _mk_named('_WD', 1, 0, 1, 10, 4) + [
        '_WD @ FOC-ADD',
        # Clean both widgets
        '_WC @ WDG-CLEAN',
        '_WD @ WDG-CLEAN',
        # Request redraw
        'TUI-EVT-REDRAW',
        '_TUI-EVT-DRAW-DIRTY',
        '." R=" _DRAW-COUNT @ . CR',
    ], "R=2 ")


# ═══════════════════════════════════════════════════════════════════
#  §G — Global Key Handler
# ═══════════════════════════════════════════════════════════════════

def test_global_key_intercepts():
    """Global handler can consume events before focus dispatch."""
    check("global-intercept", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_WE', 0, 0, 1, 10, 77) + [
        '_WE @ FOC-ADD',
        # Global handler always consumes
        ': _GOBBLER ( ev -- f ) DROP -1 ;',
        "' _GOBBLER TUI-EVT-ON-KEY",
        # Build a fake char event in _EV
        'KEY-T-CHAR _EV !',
        '65 _EV 8 + !',    # 'A'
        '0 _EV 16 + !',    # no mods
        # Simulate dispatch chain: global handler check then FOC-DISPATCH
        '_TUI-EVT-ON-KEY-XT @ ?DUP IF',
        '  _EV SWAP EXECUTE',
        'ELSE 0 THEN',
        '0= IF _EV FOC-DISPATCH THEN',
        # _HIT-ID should still be 0 (global consumed it)
        '." R=" _HIT-ID @ . CR',
    ], "R=0 ")

def test_global_key_passthrough():
    """Global handler returns 0 → focus dispatch runs."""
    check("global-passthru", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_WF', 0, 0, 1, 10, 88) + [
        '_WF @ FOC-ADD',
        # Global handler passes through
        ': _PASSER ( ev -- f ) DROP 0 ;',
        "' _PASSER TUI-EVT-ON-KEY",
        # Build fake char event
        'KEY-T-CHAR _EV !',
        '66 _EV 8 + !',    # 'B'
        '0 _EV 16 + !',
        # Simulate dispatch chain
        '_TUI-EVT-ON-KEY-XT @ ?DUP IF',
        '  _EV SWAP EXECUTE',
        'ELSE 0 THEN',
        '0= IF _EV FOC-DISPATCH THEN',
        # _HIT-ID should be 88 (widget type-id)
        '_HIT-ID @ . CR',
    ], "88")

def test_no_global_handler():
    """No global handler → events go straight to focus."""
    check("no-global-handler", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
        '0 _TUI-EVT-ON-KEY-XT !',
    ] + _mk_named('_WG', 0, 0, 1, 10, 55) + [
        '_WG @ FOC-ADD',
        # Build event
        'KEY-T-CHAR _EV !',
        '67 _EV 8 + !',    # 'C'
        '0 _EV 16 + !',
        # Simulate dispatch chain
        '_TUI-EVT-ON-KEY-XT @ ?DUP IF',
        '  _EV SWAP EXECUTE',
        'ELSE 0 THEN',
        '0= IF _EV FOC-DISPATCH THEN',
        '_HIT-ID @ . CR',
    ], "55")


# ═══════════════════════════════════════════════════════════════════
#  §H — Event Loop Start/Quit
# ═══════════════════════════════════════════════════════════════════

def test_loop_quit_via_post():
    """Loop starts and exits when TUI-EVT-QUIT is posted."""
    check("loop-quit-post", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        "' TUI-EVT-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." EXITED" CR',
    ], "EXITED")

def test_loop_running_during():
    """_TUI-EVT-RUNNING is TRUE inside the loop."""
    check("loop-running", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        'VARIABLE _WAS-RUNNING',
        ': _CHK-AND-QUIT  _TUI-EVT-RUNNING @ _WAS-RUNNING ! TUI-EVT-QUIT ;',
        "' _CHK-AND-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _WAS-RUNNING @ 0<> . CR',
    ], "R=-1 ")

def test_loop_post_resets_queue():
    """Loop entry resets the post queue — old posts don't re-fire."""
    check("loop-post-reset", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _POST-LOG !',
        ': _INC-AND-QUIT  _POST-LOG @ 1+ _POST-LOG ! TUI-EVT-QUIT ;',
        "' _INC-AND-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _POST-LOG @ . CR',
    ], "R=1 ")


# ═══════════════════════════════════════════════════════════════════
#  §I — Tick Callback in Loop
# ═══════════════════════════════════════════════════════════════════

def test_loop_tick_fires():
    """Tick callback fires during loop when interval has elapsed."""
    # Strategy: post an action that backdates LAST-TICK to 0, then the
    # tick callback (1 ms interval) fires on the next iteration and quits.
    check("loop-tick", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _TICK-COUNT !',
        '1 TUI-EVT-TICK-MS!',
        ': _T-TICK  _TICK-COUNT @ 1+ _TICK-COUNT ! TUI-EVT-QUIT ;',
        "' _T-TICK TUI-EVT-ON-TICK",
        ': _BACKDATE  0 _TUI-EVT-LAST-TICK ! ;',
        "' _BACKDATE TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _TICK-COUNT @ 0> . CR',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §J — Draw Dirty in Loop
# ═══════════════════════════════════════════════════════════════════

def test_loop_draws_dirty():
    """Loop draws dirty widgets during its iteration."""
    check("loop-draw", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WH', 0, 0, 1, 10, 42) + [
        '_WH @ FOC-ADD',
        "' TUI-EVT-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _DRAW-COUNT @ 0> . CR',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §K — Deferred Actions in Loop
# ═══════════════════════════════════════════════════════════════════

def test_loop_post_executes():
    """Posted action executes during loop iteration."""
    check("loop-post-exec", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _POST-LOG !',
        ': _P-INC  _POST-LOG @ 1+ _POST-LOG ! ;',
        "' _P-INC TUI-EVT-POST",
        "' TUI-EVT-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _POST-LOG @ . CR',
    ], "R=1 ")


# ═══════════════════════════════════════════════════════════════════
#  §L — YIELD? Compatibility
# ═══════════════════════════════════════════════════════════════════

def test_yield_no_crash():
    """YIELD? is callable and doesn't crash."""
    check("yield-ok", [
        'YIELD?',
        '." YIELD-OK" CR',
    ], "YIELD-OK")


# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════
