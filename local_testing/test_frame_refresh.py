"""The occasional full refresh: when its check falls due, and what it finds.

The refresh (tui/rich-terminal/frame-refresh.f) runs a check once input has
been quiet for a while and at least once an interval, at a moment when no
paint is pending.  Its timing, counts and report run here against a fake
clock and a scripted check.  The check Desk registers is the snapshot
adapter's (RUHA-REFRESH-CHECK in uidl-hybrid-adapter.f): it captures every
visible document live and compares the capture with the snapshot of the
screen's last draw.  Those checks run the adapter's production words over a
UIDL document with one text area, whose text the test changes in the
widget's own buffer, without the word that counts the change, as a faulty
application would.
"""

from __future__ import annotations

from native_forth import NativeForth, SOURCE_ROOT, module_source
from test_data_graphics_series import run_series
from test_rich_adapter_provenance import _program

REFRESH = "tui/rich-terminal/frame-refresh.f"

# The module reads the clock through MS@; a fake one stands in for it.
FAKE_CLOCK = ("VARIABLE FAKE-MS", ": MS@ ( -- ms ) FAKE-MS @ ;")

PRELUDE = (
    "VARIABLE _FR-FAILS VARIABLE _FR-CHECKS",
    ': _FR-ASSERT 1 _FR-CHECKS +! 0= IF 1 _FR-FAILS +! ." FR ASSERT " _FR-CHECKS @ . CR THEN ;',
    ': _FR-DONE _FR-FAILS @ 0= IF ." FR PASS " ELSE ." FR FAIL " THEN _FR-CHECKS @ . CR ;',
    # A scripted check: whether it compares, whether it finds a difference,
    # and how often it ran, with the context it was given.
    "VARIABLE T-COMPARED -1 T-COMPARED ! VARIABLE T-DIFFERS VARIABLE T-CALLS VARIABLE T-CTX",
    ": T-CHECK ( ctx -- compared? differs? ) T-CTX ! 1 T-CALLS +! T-COMPARED @ T-DIFFERS @ ;",
    ": T-AT ( ms -- ) FAKE-MS ! ;",
    ": T-SERVE ( quiet? -- ) RFSH-SERVICE ;",
    # Names a report is given, compiled so that each keeps its own storage.
    ': T-COLLECTIONS S" collections" ; : T-MENUS S" menus" ; : T-FIELDS S" fields" ;',
    ': T-NOTES S" Notes" ; : T-OTHER S" Other" ; : T-NOTE S" note" ; : T-X S" x" ;',
    ": T-LONG S\" " + "T" * 80 + "\" ;",
)

SUITE = NativeForth(
    (REFRESH,),
    prelude=PRELUDE,
    replace={REFRESH: (*FAKE_CLOCK, *module_source(SOURCE_ROOT / REFRESH).decode().splitlines())},
)


def _passed(output: bytes, minimum: int) -> None:
    text = output.decode(errors="replace")
    assert "FR PASS" in text, text[-3000:]
    assert int(text.split("FR PASS")[1].split()[0]) >= minimum


def _run(lines: list[str]) -> bytes:
    return SUITE.run(lines + ["_FR-DONE"], 20_000_000)


def test_without_a_registered_check_nothing_falls_due():
    _passed(_run([
        "RFSH-DEADLINE -1 = _FR-ASSERT",
        "100000 T-AT -1 T-SERVE T-CALLS @ 0= _FR-ASSERT",
        "RFSH-INPUT 200000 T-AT -1 T-SERVE T-CALLS @ 0= _FR-ASSERT",
    ]), 3)


def test_a_check_falls_due_an_interval_after_the_last():
    _passed(_run([
        "1000 T-AT ' T-CHECK 77 RFSH-CHECK!",
        # The first interval runs from the registration.
        "RFSH-DEADLINE 6000 = _FR-ASSERT",
        "5999 T-AT -1 T-SERVE T-CALLS @ 0= _FR-ASSERT",
        "6000 T-AT -1 T-SERVE T-CALLS @ 1 = _FR-ASSERT T-CTX @ 77 = _FR-ASSERT",
        "RFSH-CHECKS @ 1 = _FR-ASSERT RFSH-MISSED @ 0= _FR-ASSERT",
        # The next falls due an interval after that check.
        "RFSH-DEADLINE 11000 = _FR-ASSERT",
        "10999 T-AT -1 T-SERVE T-CALLS @ 1 = _FR-ASSERT",
        "11500 T-AT -1 T-SERVE T-CALLS @ 2 = _FR-ASSERT",
        "RFSH-DEADLINE 16500 = _FR-ASSERT",
    ]), 10)


def test_a_check_is_owed_once_input_has_been_quiet():
    _passed(_run([
        "0 T-AT ' T-CHECK 0 RFSH-CHECK!",
        "2000 T-AT RFSH-INPUT RFSH-DEADLINE 3000 = _FR-ASSERT",
        # More input moves the quiet time on; the interval still bounds it.
        "2600 T-AT RFSH-INPUT RFSH-DEADLINE 3600 = _FR-ASSERT",
        "4500 T-AT RFSH-INPUT RFSH-DEADLINE 5000 = _FR-ASSERT",
        "4900 T-AT -1 T-SERVE T-CALLS @ 0= _FR-ASSERT",
        "5000 T-AT -1 T-SERVE T-CALLS @ 1 = _FR-ASSERT",
        # The quiet after input is checked once: the next is an interval on.
        "5200 T-AT RFSH-INPUT RFSH-DEADLINE 6200 = _FR-ASSERT",
        "6200 T-AT -1 T-SERVE T-CALLS @ 2 = _FR-ASSERT",
        "RFSH-DEADLINE 11200 = _FR-ASSERT",
    ]), 8)


def test_a_due_check_waits_for_a_moment_with_no_paint_pending():
    _passed(_run([
        "0 T-AT ' T-CHECK 0 RFSH-CHECK!",
        "9000 T-AT 0 T-SERVE T-CALLS @ 0= _FR-ASSERT",
        "9050 T-AT 0 T-SERVE T-CALLS @ 0= _FR-ASSERT RFSH-DEADLINE 5000 = _FR-ASSERT",
        "9100 T-AT -1 T-SERVE T-CALLS @ 1 = _FR-ASSERT",
    ]), 4)


def test_a_check_that_could_not_compare_is_skipped_and_waits_an_interval():
    _passed(_run([
        "0 T-AT ' T-CHECK 0 RFSH-CHECK! 0 T-COMPARED ! -1 T-DIFFERS !",
        "5000 T-AT -1 T-SERVE",
        "RFSH-SKIPPED @ 1 = _FR-ASSERT RFSH-CHECKS @ 0= _FR-ASSERT",
        "RFSH-MISSED @ 0= _FR-ASSERT CHK-SAFE? 0= _FR-ASSERT",
        "RFSH-DEADLINE 10000 = _FR-ASSERT",
    ]), 5)


def test_a_difference_is_a_missed_change_that_turns_safe_mode_on():
    _passed(_run([
        "0 T-AT ' T-CHECK 0 RFSH-CHECK! -1 T-DIFFERS !",
        "5000 T-AT -1 T-SERVE",
        "RFSH-CHECKS @ 1 = _FR-ASSERT RFSH-MISSED @ 1 = _FR-ASSERT",
        "CHK-SAFE-MODE @ CHK-WHY-MISSED = _FR-ASSERT",
        # In safe mode every frame is built in full: no check falls due.
        "RFSH-DEADLINE -1 = _FR-ASSERT",
        "20000 T-AT -1 T-SERVE T-CALLS @ 1 = _FR-ASSERT",
    ]), 5)


def test_safe_mode_keeps_the_reason_it_was_given_first():
    _passed(_run([
        "CHK-WHY-BOOT CHK-SAFE-ON",
        "0 T-AT ' T-CHECK 0 RFSH-CHECK! -1 T-DIFFERS !",
        "RFSH-DEADLINE -1 = _FR-ASSERT",
        "5000 T-AT -1 T-SERVE T-CALLS @ 0= _FR-ASSERT",
        "CHK-SAFE-MODE @ CHK-WHY-BOOT = _FR-ASSERT",
    ]), 3)


def test_the_report_keeps_the_first_difference_and_cuts_long_names():
    _passed(_run([
        "T-COLLECTIONS T-NOTES T-NOTE 4 99 RFSH-REPORT!",
        'RFSH-WHAT-A @ RFSH-WHAT-U @ S" collections" COMPARE 0= _FR-ASSERT',
        'RFSH-TITLE RFSH-TITLE-U @ S" Notes" COMPARE 0= _FR-ASSERT',
        'RFSH-ID RFSH-ID-U @ S" note" COMPARE 0= _FR-ASSERT',
        "RFSH-ELEMENT @ 4 = _FR-ASSERT RFSH-REVISION @ 99 = _FR-ASSERT",
        # A later difference leaves the first report as it is.
        "T-MENUS T-OTHER T-X 1 2 RFSH-REPORT!",
        "RFSH-ELEMENT @ 4 = _FR-ASSERT",
        'RFSH-TITLE RFSH-TITLE-U @ S" Notes" COMPARE 0= _FR-ASSERT',
    ]), 7)
    _passed(_run([
        "T-FIELDS T-LONG 0 0 -1 0 RFSH-REPORT!",
        "RFSH-TITLE-U @ 64 = _FR-ASSERT RFSH-ID-U @ 0= _FR-ASSERT",
        "RFSH-ELEMENT @ -1 = _FR-ASSERT",
    ]), 3)


# ---------------------------------------------------------------------
# The snapshot adapter's check
# ---------------------------------------------------------------------

# After the provenance program, draw 1 is captured: a document whose one
# element, the text area "note", holds "aggregate alpha".
CHECK_WORDS = r'''
VARIABLE _RC-STATUS VARIABLE _RC-DIFFERS VARIABLE _RC-AT
VARIABLE _RC-FLAGS VARIABLE _RC-BANK VARIABLE _RC-GEN
VARIABLE _RC-DRAW VARIABLE _RC-LAST
: _RC-CHECK ( -- )
    _RA-ADAPTER RUHA-REFRESH-CHECK _RC-DIFFERS ! _RC-STATUS ! ;
: _RC-KEEP ( -- )
    _RA-ADAPTER _RUHA-A.ACTIVE-BANK @ _RC-BANK !
    _RA-ADAPTER _RUHA-A.GENERATION @ _RC-GEN !
    _RA-ADAPTER _RUHA-A.LAST-DRAW @ _RC-DRAW !
    _RA-ADAPTER _RUHA-A.LAST-STATUS @ _RC-LAST !
    0 _RA-ADAPTER _RUHA-RECORD-AT _RUHA-R.FLAGS @ _RC-FLAGS ! ;
\ The check publishes nothing: the snapshot the adapter holds, and the
\ document's record, are as they were.
: _RC-SAME ( -- )
    _RA-ADAPTER _RUHA-A.ACTIVE-BANK @ _RC-BANK @ = _RA-ASSERT
    _RA-ADAPTER _RUHA-A.GENERATION @ _RC-GEN @ = _RA-ASSERT
    _RA-ADAPTER _RUHA-A.LAST-DRAW @ _RC-DRAW @ = _RA-ASSERT
    _RA-ADAPTER _RUHA-A.LAST-STATUS @ _RC-LAST @ = _RA-ASSERT
    0 _RA-ADAPTER _RUHA-RECORD-AT _RUHA-R.FLAGS @ _RC-FLAGS @ = _RA-ASSERT ;
\ Write TEXT at OFFSET into the buffer the text area borrows, as an
\ application that changes that data without TXTA-SET-TEXT would.
: _RC-POKE ( text-a text-u offset -- )
    _RA-TEXTAREA @ TXTA-BUFFER@ DROP + SWAP MOVE ;
: _RC-NOTE-INDEX ( -- index )
    _RA-CTX @ ASHELL-CTX-SWITCH
    S" note" UIDL-BY-ID UIDL-ELEM-INDEX? DROP ;
'''


def _check_program(body: str) -> str:
    return _program() + CHECK_WORDS + body + "\n_RP-DONE\n"


def test_an_unchanged_screen_matches_its_snapshot_and_keeps_its_state():
    run_series(_check_program(r'''
_RC-KEEP _RC-CHECK
_RC-STATUS @ RUHA-S-OK = _RA-ASSERT _RC-DIFFERS @ 0= _RA-ASSERT
RUHA-RC-FAMILY @ 0= _RA-ASSERT
_RC-SAME
\ The next draw still reuses the unchanged document's slices.
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-CONTENT-EPOCH@ 1 = _RA-ASSERT
_RA-SNAP @ RUHA-SNAPSHOT-GENERATION@ 2 = _RA-ASSERT
\ So does a check against that draw.
_RC-KEEP _RC-CHECK _RC-STATUS @ RUHA-S-OK = _RA-ASSERT _RC-DIFFERS @ 0= _RA-ASSERT
_RC-SAME
'''), minimum=16, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="PROVENANCE")


def test_a_change_nothing_reported_is_found_and_named():
    run_series(_check_program(r'''
_RC-NOTE-INDEX _RC-AT !
\ "aggregate alpha" becomes "aggregate omega" in the widget's buffer, and
\ nothing counts the change: the document does not draw.
S" omega" 10 _RC-POKE
_RC-KEEP _RC-CHECK
_RC-STATUS @ RUHA-S-OK = _RA-ASSERT _RC-DIFFERS @ _RA-ASSERT
RUHA-RC-FAMILY @ RUHA-RC-COLLECTIONS = _RA-ASSERT
RUHA-RC-FAMILY @ RUHA-RC-FAMILY-NAME S" collections" COMPARE 0= _RA-ASSERT
RUHA-RC-OWNER @ _RA-INSTANCE @ CINST.ID @ = _RA-ASSERT
RUHA-RC-SLOT @ _RA-SLOT = _RA-ASSERT
RUHA-RC-ELEMENT @ _RC-AT @ = _RA-ASSERT
RUHA-RC-ID RUHA-RC-ID-U @ S" note" COMPARE 0= _RA-ASSERT
_RA-CTX @ ASHELL-CTX-SWITCH
S" note" UIDL-BY-ID UIDL-REVISION RUHA-RC-REVISION @ = _RA-ASSERT
RUHA-RC-REVISION @ 0<> _RA-ASSERT
_RC-SAME
\ The ordinary capture of the next draw reuses the old text: the screen
\ would show it until something else redraws the document.
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@
    S" aggregate alpha" STR-STR= _RA-ASSERT
\ In safe mode, which the missed change turns on, every draw is captured
\ afresh, and the change reaches the snapshot.
CHK-WHY-MISSED CHK-SAFE-ON
3 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@
    S" aggregate omega" STR-STR= _RA-ASSERT
0 CHK-SAFE-MODE !
'''), minimum=20, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="PROVENANCE")


def test_a_counted_and_drawn_change_matches_its_snapshot():
    run_series(_check_program(r'''
\ The same change through the word that counts it: the document draws, and
\ the next draw's capture holds it.
S" aggregate omega" _RA-TEXTAREA @ TXTA-SET-TEXT
_RA-CTX @ ASHELL-CTX-SWITCH UTUI-PAINT UTUI-DRAW-COMPLETE
2 _RA-QUERY _RA-STATUS @ RUHA-S-OK = _RA-ASSERT
_RA-FIRST-ENTRY USCOL-TEXT-FIRST USCOL-ITEM-TEXT@
    S" aggregate omega" STR-STR= _RA-ASSERT
_RC-KEEP _RC-CHECK _RC-STATUS @ RUHA-S-OK = _RA-ASSERT _RC-DIFFERS @ 0= _RA-ASSERT
_RC-SAME
'''), minimum=12, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="PROVENANCE")


def test_a_screen_that_drew_since_its_snapshot_is_not_checked():
    run_series(_check_program(r'''
\ The screen completes a draw the adapter has not captured yet.
SCR-DRAW-COMPLETE
S" omega" 10 _RC-POKE
_RC-KEEP _RC-CHECK
_RC-STATUS @ RUHA-S-STALE = _RA-ASSERT _RC-DIFFERS @ 0= _RA-ASSERT
RUHA-RC-FAMILY @ 0= _RA-ASSERT
_RC-SAME
'''), minimum=10, extra_sources=("tui/rich-terminal/uidl-hybrid-adapter.f",),
        marker="PROVENANCE")
