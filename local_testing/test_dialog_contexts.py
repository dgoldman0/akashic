"""Each application's dialog lives in its UIDL context."""

from test_uidl_collection_snapshot import _run_forth


PRELUDE = [
    "VARIABLE _DC-FAILS VARIABLE _DC-CHECKS",
    ": _DC-ASSERT 1 _DC-CHECKS +! 0= IF 1 _DC-FAILS +! .\" DLGCTX ASSERT \" _DC-CHECKS @ . CR THEN ;",
    ": _DC-DONE _DC-FAILS @ 0= IF .\" DLGCTX PASS \" ELSE .\" DLGCTX FAIL \" THEN _DC-CHECKS @ . CR ;",
    "CREATE _DC-BT 24 ALLOT",
    "S\" OK\" _DC-BT 8 + ! _DC-BT ! DLG-B-DEFAULT DLG-B-CANCEL OR _DC-BT 16 + !",
    ": _DC-ASK S\" T\" S\" M\" _DC-BT 1 0 0 DLG-ASK ;",
    ": _DC-LEAVE ( ctx -- ) UCTX-SAVE UCTX-LIVE-DISOWN ;",
    "VARIABLE _DC-A VARIABLE _DC-B VARIABLE _DC-DA VARIABLE _DC-DB",
    "80 24 SCR-NEW SCR-USE",
    "UCTX-ALLOC DUP _DC-A ! 0<> _DC-ASSERT UCTX-ALLOC DUP _DC-B ! 0<> _DC-ASSERT",
    "_DC-A @ UCTX-CLEAR _DC-B @ UCTX-CLEAR",
]


def _passed(output: str, minimum: int) -> None:
    assert "DLGCTX PASS" in output, output[-3000:]
    count = int(output.split("DLGCTX PASS")[1].split()[0])
    assert count >= minimum


def test_each_context_keeps_its_own_dialog():
    """A's dialog is saved with A: once A gives up the live state nothing
    live names it, B asks for its own, and A finds its own again."""
    _passed(_run_forth(PRELUDE + [
        "_DC-A @ UCTX-RESTORE _DC-ASK _DC-ASSERT DLG-SHOWN DUP _DC-DA ! 0<> _DC-ASSERT",
        "_DC-A @ _DC-LEAVE DLG-SHOWN 0= _DC-ASSERT",
        "_DC-B @ UCTX-RESTORE DLG-SHOWN 0= _DC-ASSERT",
        "_DC-ASK _DC-ASSERT DLG-SHOWN DUP _DC-DB ! _DC-DA @ <> _DC-ASSERT",
        "_DC-B @ _DC-LEAVE",
        "_DC-A @ UCTX-RESTORE DLG-SHOWN _DC-DA @ = _DC-ASSERT _DC-A @ _DC-LEAVE",
        "_DC-B @ UCTX-RESTORE DLG-SHOWN _DC-DB @ = _DC-ASSERT _DC-B @ _DC-LEAVE",
        "_DC-B @ UCTX-FREE _DC-A @ UCTX-FREE _DC-DONE",
    ]), 9)


def test_a_context_freed_or_cleared_frees_its_dialog_unanswered():
    """The saved dialog goes with its context, without its asker being
    called back, and the context's cell is left empty."""
    _passed(_run_forth(PRELUDE + [
        "VARIABLE _DC-CALLED 0 _DC-CALLED !",
        ": _DC-CALLBACK ( index ctx -- ) 2DROP 1 _DC-CALLED +! ;",
        ": _DC-ASK-BACK S\" T\" S\" M\" _DC-BT 1 ['] _DC-CALLBACK 0 DLG-ASK ;",
        "_DC-A @ UCTX-RESTORE _DC-ASK-BACK _DC-ASSERT DLG-SHOWN _DC-DA ! _DC-A @ _DC-LEAVE",
        "_DC-A @ _UCTX-O-MODAL + @ _DC-DA @ = _DC-ASSERT",
        "_DC-A @ UCTX-CLEAR _DC-A @ _UCTX-O-MODAL + @ 0= _DC-ASSERT",
        "_DC-A @ UCTX-RESTORE DLG-SHOWN 0= _DC-ASSERT _DC-A @ _DC-LEAVE",
        "_DC-B @ UCTX-RESTORE _DC-ASK-BACK _DC-ASSERT _DC-B @ _DC-LEAVE",
        "_DC-B @ UCTX-FREE _DC-A @ UCTX-FREE",
        "_DC-CALLED @ 0= _DC-ASSERT _DC-DONE",
    ]), 8)
