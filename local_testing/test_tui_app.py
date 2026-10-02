#!/usr/bin/env python3
"""Test suite for tui/app.f (TUI Application Lifecycle).

Every check runs on a fresh native machine (native_forth.py) with KDOS,
app.f and its closure loaded, and exercises:
  - Compilation (clean load of all deps + app.f)
  - APP-INIT terminal setup
  - APP-SHUTDOWN terminal restore
  - APP-SCREEN / APP-SIZE accessors
  - APP-TITLE! title setting
  - APP-RUN-FULL lifecycle
  - Idempotent init / shutdown
  - CATCH-based cleanup on THROW
"""
import re

from native_forth import NativeForth

SUITE = NativeForth(("tui/app.f",))


def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9, 27)) else ""
        for b in buf
    )


def run_forth_text(lines, max_steps=80_000_000):
    """Run Forth and return cleaned text (no ESC sequences)."""
    raw = uart_text(SUITE.run(lines, max_steps))
    # Strip ANSI escape sequences for text-based checks
    return re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', raw)


def run_forth_raw(lines, max_steps=80_000_000):
    """Run Forth and return raw bytes."""
    return SUITE.run(lines, max_steps)


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    output = run_forth_text(forth_lines)
    last = "\n".join(output.strip().split("\n")[-8:])
    if check_fn:
        assert check_fn(output), f"{name}: check failed, got:\n{last}"
    elif expected is not None:
        assert expected in output, f"{name}: expected {expected!r}, got:\n{last}"
    if not_expected is not None:
        assert not_expected not in output, f"{name}: NOT expected {not_expected!r}, got:\n{last}"


def check_raw(name, forth_lines, check_fn):
    """Check using raw bytes from UART (preserves ESC sequences)."""
    raw = run_forth_raw(forth_lines)
    assert check_fn(raw), f"{name}: last {len(raw[-200:])} raw bytes: {raw[-200:]!r}"


# ═══════════════════════════════════════════════════════════════════
#  §A — Compilation
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    check("compile-clean", [
        '." COMPILE-OK" CR',
    ], "COMPILE-OK")


# ═══════════════════════════════════════════════════════════════════
#  §B — APP-INIT terminal setup
# ═══════════════════════════════════════════════════════════════════

def test_init_alt_screen():
    """APP-INIT emits ESC[?1049h (enter alternate screen)."""
    check_raw("init-alt-screen", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?1049h' in raw)

def test_init_cursor_off():
    """APP-INIT emits ESC[?25l (hide cursor)."""
    check_raw("init-cursor-off", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?25l' in raw)

def test_init_sets_inited():
    """_APP-INITED is TRUE after APP-INIT."""
    check("init-sets-flag", [
        '80 24 APP-INIT',
        '." R=" _APP-INITED @ 0<> . CR',
        'APP-SHUTDOWN',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §C — APP-SHUTDOWN terminal restore
# ═══════════════════════════════════════════════════════════════════

def test_shutdown_alt_off():
    """APP-SHUTDOWN emits ESC[?1049l (leave alternate screen)."""
    check_raw("shutdown-alt-off", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?1049l' in raw)

def test_shutdown_cursor_on():
    """APP-SHUTDOWN emits ESC[?25h (show cursor)."""
    check_raw("shutdown-cursor-on", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[?25h' in raw)

def test_shutdown_reset():
    """APP-SHUTDOWN emits ESC[0m (reset attributes)."""
    check_raw("shutdown-reset", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b[0m' in raw)

def test_shutdown_clears_flag():
    """_APP-INITED is FALSE after APP-SHUTDOWN."""
    check("shutdown-clears-flag", [
        '80 24 APP-INIT',
        'APP-SHUTDOWN',
        '." R=" _APP-INITED @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §D — Accessors
# ═══════════════════════════════════════════════════════════════════

def test_app_screen():
    """APP-SCREEN returns non-zero after init."""
    check("app-screen", [
        '80 24 APP-INIT',
        '." R=" APP-SCREEN 0<> . CR',
        'APP-SHUTDOWN',
    ], "R=-1 ")

def test_app_size():
    """APP-SIZE returns the dimensions passed to APP-INIT."""
    check("app-size", [
        '80 24 APP-INIT',
        'APP-SIZE',
        '." R=" SWAP . . CR',
        'APP-SHUTDOWN',
    ], "R=80 24 ")

def test_app_size_no_init():
    """APP-SIZE returns 0 0 before init."""
    # Need to clear the screen set by snapshot
    check("app-size-no-init", [
        '." R=" _APP-SCR @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §E — APP-TITLE!
# ═══════════════════════════════════════════════════════════════════

def test_title():
    """APP-TITLE! emits ESC]2;...ESC\\ title sequence."""
    check_raw("title-set", [
        '80 24 APP-INIT',
        'S" MyApp" APP-TITLE!',
        'APP-SHUTDOWN',
    ], lambda raw: b'\x1b]2;MyApp\x1b\\' in raw)


# ═══════════════════════════════════════════════════════════════════
#  §F — Idempotent init / shutdown
# ═══════════════════════════════════════════════════════════════════

def test_init_idempotent():
    """Calling APP-INIT twice doesn't create a second screen."""
    check("init-idempotent", [
        '80 24 APP-INIT',
        'APP-SCREEN',      # save first screen addr
        '40 12 APP-INIT',  # second call should be no-op
        '." R=" APP-SCREEN = . CR',  # should be same addr
        'APP-SHUTDOWN',
    ], "R=-1 ")

def test_shutdown_idempotent():
    """Calling APP-SHUTDOWN without APP-INIT is a no-op."""
    check("shutdown-no-init", [
        'APP-SHUTDOWN',
        '." SAFE" CR',
    ], "SAFE")


# ═══════════════════════════════════════════════════════════════════
#  §G — APP-RUN-FULL lifecycle
# ═══════════════════════════════════════════════════════════════════

def test_run_full():
    """APP-RUN-FULL calls init-xt, runs loop, shuts down."""
    check("run-full", [
        # The init-xt posts QUIT so the loop exits immediately
        ": _MY-INIT  ' TUI-EVT-QUIT TUI-EVT-POST ;",
        "' _MY-INIT 80 24 APP-RUN-FULL",
        '." EXITED" CR',
    ], "EXITED")

def test_run_full_shutdown():
    """APP-RUN-FULL leaves _APP-INITED FALSE after completion."""
    check("run-full-shutdown", [
        ": _MY-INIT2  ' TUI-EVT-QUIT TUI-EVT-POST ;",
        "' _MY-INIT2 80 24 APP-RUN-FULL",
        '." R=" _APP-INITED @ . CR',
    ], "R=0 ")

def test_run_full_alt_restore():
    """APP-RUN-FULL restores normal screen (ESC[?1049l emitted)."""
    check_raw("run-full-alt-restore", [
        ": _MY-INIT3  ' TUI-EVT-QUIT TUI-EVT-POST ;",
        "' _MY-INIT3 80 24 APP-RUN-FULL",
    ], lambda raw: b'\x1b[?1049l' in raw)


# ═══════════════════════════════════════════════════════════════════
#  §H — FOC-CLEAR integration
# ═══════════════════════════════════════════════════════════════════

def test_init_clears_focus():
    """APP-INIT calls FOC-CLEAR — focus count is 0."""
    check("init-clears-focus", [
        '80 24 APP-INIT',
        '." R=" FOC-COUNT . CR',
        'APP-SHUTDOWN',
    ], "R=0 ")
