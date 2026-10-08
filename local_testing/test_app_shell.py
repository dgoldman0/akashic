#!/usr/bin/env python3
"""Test suite for akashic-tui-app-shell (TUI Application Shell Runtime).

Every check runs on a fresh native machine (native_forth.py) with KDOS and
the full dependency chain through uidl-tui + app-shell loaded, then
exercises the public API.
"""
import re

from native_forth import NativeForth

# T-APP makes an APP-DESC valid around one shared stateless component, as
# the shell requires before it creates the app's instance.
HELPERS = (
    'CREATE _CD COMP-DESC ALLOT  _CD COMP-DESC-INIT',
    ': T-APP  ( desc -- )  DUP APP-DESC-INIT  _CD SWAP APP.COMP-DESC ! ;',
)

# Terminal setup and the event loop wait on MS@ deadlines, so the clock
# must advance as the machine runs.
SUITE = NativeForth(("tui/event.f", "tui/app.f", "tui/app-shell.f"),
                    prelude=HELPERS, live_clock=True)


def _normalize(raw: bytes) -> str:
    """Strip terminal control sequences and join the printed lines."""
    text = raw.decode("latin-1")
    text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", text)
    text = re.sub(r"\x1b[@-_]", "", text)
    text = "".join(ch for ch in text if ch in "\n\t" or 0x20 <= ord(ch) < 0x7F)
    return " ".join(line.strip() for line in text.split("\n") if line.strip())


def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    clean = _normalize(SUITE.run(forth_lines, 80_000_000))
    if check_fn:
        assert check_fn(clean), f"{name}: check failed, normalized: {clean!r}"
    elif expected is not None:
        assert expected in clean, f"{name}: expected {expected!r}, normalized: {clean!r}"
    if not_expected is not None:
        assert not_expected not in clean, f"{name}: NOT expected {not_expected!r}, normalized: {clean!r}"


# ═══════════════════════════════════════════════════════════════════
#  §1 — APP-DESC Structure Tests
# ═══════════════════════════════════════════════════════════════════

def test_desc_size():
    """APP-DESC constant should include every v1 lifecycle field."""
    check("desc-size", [
        'APP-DESC .',
    ], expected='168')

def test_desc_init():
    """APP-DESC-INIT should stamp the header and zero every other field."""
    check("desc-init", [
        'CREATE _D APP-DESC ALLOT',
        '99 _D APP.TITLE-A !',
        '_D APP-DESC-INIT',
        '_D APP.MAGIC @ APP-MAGIC = .  _D APP.ABI @ APP-ABI-VERSION = .',
        '_D APP.SIZE @ .  _D APP.COMP-DESC @ .  _D APP.TITLE-A @ .',
    ], expected='-1 -1 168 0 0')

def test_field_offsets():
    """Field accessors should return correct addresses."""
    check("field-offsets", [
        'CREATE _D APP-DESC ALLOT  _D APP-DESC-INIT',
        '111 _D APP.INIT-XT !  222 _D APP.EVENT-XT !',
        '333 _D APP.TICK-XT !  444 _D APP.PAINT-XT !',
        '555 _D APP.SHUTDOWN-XT !  666 _D APP.UIDL-A !',
        '777 _D APP.UIDL-U !  80 _D APP.WIDTH !  24 _D APP.HEIGHT !',
        '888 _D APP.UIDL-FILE-A !  999 _D APP.UIDL-FILE-U !',
        '_D APP.INIT-XT @ .  _D APP.EVENT-XT @ .  _D APP.TICK-XT @ .',
        '_D APP.PAINT-XT @ .  _D APP.SHUTDOWN-XT @ .',
        '_D APP.UIDL-A @ .  _D APP.UIDL-U @ .',
        '_D APP.WIDTH @ .  _D APP.HEIGHT @ .',
        '_D APP.UIDL-FILE-A @ .  _D APP.UIDL-FILE-U @ .',
    ], expected='111 222 333 444 555 666 777 80 24 888 999')

def test_desc_requires_component():
    """A descriptor is valid only with a valid component descriptor."""
    check("desc-requires-component", [
        'CREATE _D APP-DESC ALLOT  _D APP-DESC-INIT',
        '_D APP-DESC-VALID? .',
        '_D T-APP  _D APP-DESC-VALID? .',
    ], expected='0 -1')


# ═══════════════════════════════════════════════════════════════════
#  §2 — Shell State (before run)
# ═══════════════════════════════════════════════════════════════════

def test_initial_state():
    """Shell state should be zeroed before any run."""
    check("initial-state", [
        'ASHELL-REGION .  ASHELL-UIDL? .  ASHELL-DESC .',
    ], expected='0 0 0')

def test_post_queue():
    """ASHELL-POST should enqueue without crashing."""
    check("post-queue", [
        'VARIABLE _PQ-RESULT  0 _PQ-RESULT !',
        ": _PQ-INC  1 _PQ-RESULT +! ;",
        # Use ' (tick) in interpret mode, not ['] which is compile-time only
        "' _PQ-INC ASHELL-POST",
        "' _PQ-INC ASHELL-POST",
        "' _PQ-INC ASHELL-POST",
        '_PQ-RESULT @ .',
    ], expected='0')  # actions enqueued but not yet drained


# ═══════════════════════════════════════════════════════════════════
#  §3 — Lifecycle Tests (quit immediately)
# ═══════════════════════════════════════════════════════════════════

def test_run_quit_no_uidl():
    """ASHELL-RUN with an app that quits immediately (no UIDL)."""
    check("run-quit-no-uidl", [
        'VARIABLE _RQN-INITED  0 _RQN-INITED !',
        'VARIABLE _RQN-SD      0 _RQN-SD !',
        ': _RQN-INIT-FN  ( inst -- ) DROP -1 _RQN-INITED ! ASHELL-QUIT ;',
        ': _RQN-SD-FN    ( inst -- ) DROP -1 _RQN-SD ! ;',
        'CREATE _RQN-D APP-DESC ALLOT  _RQN-D T-APP',
        "' _RQN-INIT-FN _RQN-D APP.INIT-XT !",
        "' _RQN-SD-FN _RQN-D APP.SHUTDOWN-XT !",
        '_RQN-D ASHELL-RUN',
        '_RQN-INITED @ .  _RQN-SD @ .',
    ], expected='-1 -1')

def test_run_passes_instance():
    """Callbacks receive the instance the shell created for the component."""
    # The shell frees the instance at teardown, so it is checked in init.
    check("run-passes-instance", [
        'VARIABLE _RPI-OK  0 _RPI-OK !',
        ': _RPI-INIT  ( inst -- ) CINST-DESC _CD = _RPI-OK ! ASHELL-QUIT ;',
        'CREATE _RPI-D APP-DESC ALLOT  _RPI-D T-APP',
        "' _RPI-INIT _RPI-D APP.INIT-XT !",
        '_RPI-D ASHELL-RUN',
        '_RPI-OK @ .',
    ], expected='-1')

def test_run_quit_with_uidl():
    """ASHELL-RUN with UIDL document — init->quit cycle."""
    check("run-quit-with-uidl", [
        'VARIABLE _RQU-OK  0 _RQU-OK !',
        ': _RQU-INIT  ( inst -- ) DROP ASHELL-UIDL? _RQU-OK !  ASHELL-QUIT ;',
        'CREATE _RQU-UIDL 256 ALLOT',
        'S" <uidl><region><label text=Hello/></region></uidl>"',
        '_RQU-UIDL SWAP MOVE',
        'CREATE _RQU-D APP-DESC ALLOT  _RQU-D T-APP',
        "' _RQU-INIT _RQU-D APP.INIT-XT !",
        '_RQU-UIDL _RQU-D APP.UIDL-A !',
        '49 _RQU-D APP.UIDL-U !',
        '_RQU-D ASHELL-RUN',
        '_RQU-OK @ .',
    ], expected='-1')

def test_region_available_in_init():
    """ASHELL-REGION should be non-zero inside app init callback."""
    check("region-in-init", [
        'VARIABLE _RGI-V  0 _RGI-V !',
        ': _RGI-INIT  ( inst -- ) DROP ASHELL-REGION _RGI-V !  ASHELL-QUIT ;',
        'CREATE _RGI-D APP-DESC ALLOT  _RGI-D T-APP',
        "' _RGI-INIT _RGI-D APP.INIT-XT !",
        '_RGI-D ASHELL-RUN',
        '_RGI-V @ 0<> .',
    ], expected='-1')

def test_cleanup_after_run():
    """After ASHELL-RUN returns, shell state should be reset."""
    check("cleanup-after-run", [
        ': _CLN-INIT  ( inst -- ) DROP ASHELL-QUIT ;',
        'CREATE _CLN-D APP-DESC ALLOT  _CLN-D T-APP',
        "' _CLN-INIT _CLN-D APP.INIT-XT !",
        '_CLN-D ASHELL-RUN',
        'ASHELL-DESC .  ASHELL-REGION .  ASHELL-UIDL? .',
    ], expected='0 0 0')


# ═══════════════════════════════════════════════════════════════════
#  §4 — Event Dispatch Tests
# ═══════════════════════════════════════════════════════════════════

def test_event_callback():
    """App EVENT-XT wiring — init can quit cleanly."""
    check("event-callback-wired", [
        ': _EC-EV  ( ev inst -- flag ) 2DROP 0 ;',
        ': _EC-INIT  ( inst -- ) DROP ASHELL-QUIT ;',
        'CREATE _EC-D APP-DESC ALLOT  _EC-D T-APP',
        "' _EC-INIT _EC-D APP.INIT-XT !",
        "' _EC-EV   _EC-D APP.EVENT-XT !",
        '_EC-D ASHELL-RUN',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  §5 — Tick Callback Tests
# ═══════════════════════════════════════════════════════════════════

def test_tick_ms_accessor():
    """ASHELL-TICK-MS! should store the tick interval."""
    check("tick-ms-set", [
        '200 ASHELL-TICK-MS!',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  §6 — Dirty Flag Tests
# ═══════════════════════════════════════════════════════════════════

def test_dirty_flag():
    """ASHELL-DIRTY! should be callable outside of run."""
    check("dirty-flag", [
        'ASHELL-DIRTY!',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  §7 — Error Handling Tests
# ═══════════════════════════════════════════════════════════════════

def test_throw_in_init():
    """If app init THROWs, shell should still clean up and propagate."""
    check("throw-in-init", [
        ': _TI-INIT  ( inst -- ) DROP -999 THROW ;',
        'CREATE _TI-D APP-DESC ALLOT  _TI-D T-APP',
        "' _TI-INIT _TI-D APP.INIT-XT !",
        # CATCH restores stack to pre-CATCH state then pushes throw code.
        # The desc stays on stack from CATCH restore, so DROP it.
        "_TI-D ' ASHELL-RUN CATCH . DROP",
        'ASHELL-DESC .',
    ], expected='-999 0')


# ═══════════════════════════════════════════════════════════════════
#  §8 — All Callbacks Wired Test
# ═══════════════════════════════════════════════════════════════════

def test_all_callbacks():
    """Init and shutdown run around a run that quits from init."""
    check("all-callbacks", [
        'VARIABLE _AC-BITS  0 _AC-BITS !',
        ': _AC-INIT      ( inst -- ) DROP 1 _AC-BITS +!  ASHELL-QUIT ;',
        ': _AC-EVENT     ( ev inst -- flag ) 2DROP 0 ;',
        ': _AC-TICK      ( inst -- ) DROP ;',
        ': _AC-PAINT     ( inst -- ) DROP ;',
        ': _AC-SHUTDOWN  ( inst -- ) DROP 16 _AC-BITS +! ;',
        'CREATE _AC-D APP-DESC ALLOT  _AC-D T-APP',
        "' _AC-INIT     _AC-D APP.INIT-XT !",
        "' _AC-EVENT    _AC-D APP.EVENT-XT !",
        "' _AC-TICK     _AC-D APP.TICK-XT !",
        "' _AC-PAINT    _AC-D APP.PAINT-XT !",
        "' _AC-SHUTDOWN _AC-D APP.SHUTDOWN-XT !",
        '_AC-D ASHELL-RUN',
        '_AC-BITS @ .',
    ], expected='17')


# ═══════════════════════════════════════════════════════════════════
#  §9 — UIDL Integration Tests
# ═══════════════════════════════════════════════════════════════════

def test_uidl_by_id_in_init():
    """UTUI-BY-ID should work inside the app init callback."""
    check("uidl-by-id-in-init", [
        'VARIABLE _UBI-FOUND  0 _UBI-FOUND !',
        ': _UBI-INIT  ( inst -- ) DROP',
        '    S" lbl1" UTUI-BY-ID',
        '    0<> _UBI-FOUND !',
        '    ASHELL-QUIT ;',
        'CREATE _UBI-UIDL 256 ALLOT',
        'S" <uidl><region><label id=lbl1 text=Test/></region></uidl>"',
        '_UBI-UIDL SWAP MOVE',
        'CREATE _UBI-D APP-DESC ALLOT  _UBI-D T-APP',
        "' _UBI-INIT _UBI-D APP.INIT-XT !",
        '_UBI-UIDL _UBI-D APP.UIDL-A !',
        '56 _UBI-D APP.UIDL-U !',
        '_UBI-D ASHELL-RUN',
        '_UBI-FOUND @ .',
    ], expected='-1')

def test_uidl_action_registration():
    """UTUI-DO! should work when UIDL is loaded via shell."""
    check("uidl-action-reg", [
        'VARIABLE _UAR-FIRED  0 _UAR-FIRED !',
        ': _UAR-FIRE  -1 _UAR-FIRED ! ;',
        ': _UAR-INIT  ( inst -- ) DROP',
        "    S\" my-act\" ['] _UAR-FIRE UTUI-DO!",
        '    ASHELL-QUIT ;',
        'CREATE _UAR-UIDL 256 ALLOT',
        'S" <uidl><region><action do=my-act text=Go key=F1/></region></uidl>"',
        '_UAR-UIDL SWAP MOVE',
        'CREATE _UAR-D APP-DESC ALLOT  _UAR-D T-APP',
        "' _UAR-INIT _UAR-D APP.INIT-XT !",
        '_UAR-UIDL _UAR-D APP.UIDL-A !',
        '64 _UAR-D APP.UIDL-U !',
        '_UAR-D ASHELL-RUN',
        'S" OK" TYPE',
    ], expected='OK')
