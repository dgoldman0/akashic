"""The shared prompt publishes itself as one TEXT field while it is shown:
its label, its input's value (mask characters when it masks), caret,
selection, scroll and placeholder, in the slots its paint uses."""

from __future__ import annotations

from test_widget_pointer import _numbers, _report

ROOTS = ("tui/widgets/prompt.f",)

PROMPT = [
    "80 24 SCR-NEW DUP SCR-USE SCR-CLEAR",
    "CREATE _PBUF 64 ALLOT VARIABLE _PR",
    "23 0 1 40 RGN-NEW _PBUF 64 PRM-NEW _PR !",
    # The prompt keeps its label's address, as applications' compiled
    # strings allow.
    ': _LABEL S" Open:" ; : _VALUE S" notes.md" ;',
    "_LABEL _VALUE _PR @ PRM-SHOW",
    "_PR @ WDG-DRAW",
    "CREATE _FMS 1031 ALLOT _FMS 7 + -8 AND CONSTANT _FM",
    ": _CAP  ( -- bytes status )  _FM 1024 _PR @ PRM-FIELD-CAPTURE ;",
    ": _INPUT  ( -- input )  _PR @ _PRM-O-INPUT + @ ;",
]


def test_a_shown_prompt_is_one_text_field_in_its_paint_slots() -> None:
    values = _numbers(
        PROMPT
        + [
            # Measured, then written: header, "Open:" and "notes.md".
            "0 0 _PR @ PRM-FIELD-CAPTURE",
            "_CAP",
            "_FM 240 UFLD-VALIDATE",
            "_FM UFLD-KIND@ _FM UFLD-STATE@ _FM UFLD-FLAGS@",
            # The label from column 1, the value where the input begins.
            "_FM UFLD-LABEL-COLUMN@ _FM UFLD-LABEL-WIDTH@",
            "_FM UFLD-VALUE-COLUMN@ _FM UFLD-VALUE-WIDTH@ _FM UFLD-WIDTH@",
            "_FM UFLD-CARET@ _FM UFLD-ANCHOR@ _FM UFLD-SCROLL@",
            '_FM UFLD-TEXT@ S" notes.md" COMPARE 0=',
            '_FM UFLD-LABEL@ S" Open:" COMPARE 0=',
            # The revision follows both the prompt and its input.
            "_FM UFLD-REVISION@ _PR @ _PRM-O-REVISION + @ _INPUT WDG-REVISION + =",
        ]
        + _report(19),
        roots=ROOTS,
    )

    assert values[::-1] == [240, 0, 240, 0, 0, 3, 7, 0, 1, 5, 7, 33, 40,
                            8, 8, 0, -1, -1, -1]


def test_masked_placeholder_and_narrow_prompts() -> None:
    values = _numbers(
        PROMPT
        + [
            # A masked prompt sends one mask character per character.
            "42 _PR @ PRM-MASK! _PR @ WDG-DRAW _CAP NIP",
            '_FM UFLD-TEXT@ S" ********" COMPARE 0= _FM UFLD-FLAGS@',
            # Its placeholder follows the value.
            ': _HINT S" Name" ; _HINT _INPUT INP-SET-PLACEHOLDER 0 _PR @ PRM-MASK!',
            "_PR @ WDG-DRAW _CAP",
            '_FM UFLD-PLACEHOLDER@ S" Name" COMPARE 0=',
            # Six columns: the input begins at column 5 and cuts the label.
            "23 0 1 6 _PR @ PRM-SET-BOUNDS _PR @ WDG-DRAW _CAP NIP",
            "_FM UFLD-LABEL-WIDTH@ _FM UFLD-VALUE-COLUMN@ _FM UFLD-VALUE-WIDTH@",
            "_FM UFLD-SCROLL@",
        ]
        + _report(11),
        roots=ROOTS,
    )

    assert values[::-1] == [0, -1, 2, 248, 0, -1, 0, 4, 5, 1, 8]


def test_only_a_shown_live_prompt_is_captured_apart_from_its_sources() -> None:
    values = _numbers(
        PROMPT
        + [
            "_PR @ PRM-INSTANCE@ 0<>",
            "_INPUT PRM-INSTANCE@",
            # A destination over the prompt itself is refused.
            "_PR @ 128 _PR @ PRM-FIELD-CAPTURE",
            "_PR @ PRM-HIDE _CAP",
        ]
        + _report(6),
        roots=ROOTS,
    )

    assert values[::-1] == [-1, 0, 0, 3, 0, 3]


def test_the_field_root_is_the_first_row_of_the_prompt_region() -> None:
    values = _numbers(PROMPT + ["_PR @ PRM-FIELD-ROOT"] + _report(4), roots=ROOTS)

    assert values[::-1] == [23, 0, 1, 40]
