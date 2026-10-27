"""The Agent's panel counts a change when an overlay that showed goes.

The Agent draws its account panel over its body from its paint callback,
and its own panel draws only its background while the account panel or the
run settings show.  Opening the prompt hides them, which changes what the
panel draws, so the panel counts the change and UIDL repaints the body, as
it repaints the element of any widget whose revision moves
(test_uidl_widget_repaint.py).  These tests run the Agent's own words in the
native simulator, on a state block of their own, with widget headers in the
overlays' places.
"""

from __future__ import annotations

from native_forth import NativeForth


PRELUDE = (
    "VARIABLE _AO-FAILS VARIABLE _AO-CHECKS",
    ': _AO-ASSERT 1 _AO-CHECKS +! 0= IF 1 _AO-FAILS +! ." AO ASSERT " _AO-CHECKS @ . CR THEN ;',
    ': _AO-DONE _AO-FAILS @ 0= IF ." AO PASS " ELSE ." AO FAIL " THEN _AO-CHECKS @ . CR ;',
    "80 24 SCR-NEW SCR-USE",
    "CREATE _AO-STATE _AG-STATE-SIZE ALLOT _AO-STATE _AG-STATE-SIZE 0 FILL",
    "_AO-STATE _AG-CURRENT-STATE !",
    "0 0 20 80 RGN-NEW _AG-PANEL-INIT",
    ": _AO-DRAW ( widget -- ) DROP ; : _AO-HANDLE ( event widget -- f ) 2DROP 0 ;",
    "CREATE _AO-AUTH WDG-HEADER-SIZE ALLOT CREATE _AO-SETTINGS WDG-HEADER-SIZE ALLOT",
    "_AO-AUTH 0 0 0 20 80 RGN-NEW ' _AO-DRAW ' _AO-HANDLE WDG-INIT _AO-AUTH WDG-HIDE",
    "_AO-SETTINGS 0 0 0 20 80 RGN-NEW ' _AO-DRAW ' _AO-HANDLE WDG-INIT _AO-SETTINGS WDG-HIDE",
    "_AO-AUTH _AG-AUTH-PANEL ! _AO-SETTINGS _AG-SETTINGS-PANEL !",
    "VARIABLE _AO-REV",
    ": _AO-MARK ( -- ) _AG-PANEL WDG-REVISION _AO-REV ! ;",
    ": _AO-MOVED? ( -- flag ) _AG-PANEL WDG-REVISION _AO-REV @ <> ;",
)

SUITE = NativeForth(("tui/applets/agent/agent.f",), prelude=PRELUDE)


def _run(lines: list[str]) -> str:
    return SUITE.run(lines + ["_AO-DONE"], 50_000_000).decode(errors="replace")


def _passed(output: str, minimum: int) -> None:
    assert "AO PASS" in output, output[-3000:]
    assert int(output.split("AO PASS")[1].split()[0]) >= minimum


def test_hiding_an_overlay_that_shows_counts_a_change_to_the_panel():
    _passed(_run([
        # With no overlay showing, hiding them changes nothing.
        "_AO-MARK _AG-HIDE-OVERLAYS _AO-MOVED? 0= _AO-ASSERT",
        # The account panel shows: the panel draws its background alone.
        # Hiding it changes what the panel draws, which the panel counts.
        "_AO-AUTH WDG-SHOW _AG-USER-OVERLAY? _AO-ASSERT",
        "_AO-MARK _AG-HIDE-OVERLAYS _AO-MOVED? _AO-ASSERT",
        "_AO-AUTH WDG-VISIBLE? 0= _AO-ASSERT _AG-USER-OVERLAY? 0= _AO-ASSERT",
        # The run settings, which the panel draws in its place, the same.
        "_AO-SETTINGS WDG-SHOW _AO-MARK _AG-HIDE-OVERLAYS _AO-MOVED? _AO-ASSERT",
        "_AO-SETTINGS WDG-VISIBLE? 0= _AO-ASSERT",
        # Hiding again changes nothing.
        "_AO-MARK _AG-HIDE-OVERLAYS _AO-MOVED? 0= _AO-ASSERT",
    ]), 8)
