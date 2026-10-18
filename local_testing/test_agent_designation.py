#!/usr/bin/env python3
"""Model designations (run-settings.f) and the scripted provider.

The suite runs over the device-flow source's catalog: two models, gpt-fast
(efforts low and medium, no tiers) and gpt-slow (efforts low and high, the
priority tier).  It covers finding models and choices, every way a
designation stands against the catalog, and the scripted provider running
a turn on the model its designation names while chat keeps the selection.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


OK, PENDING, UNSUPPORTED, INVALID = 0, 1, 2, 3
AUTO, LOW, MEDIUM, HIGH = range(4)

PRELUDE = r"""
VARIABLE SRC  VARIABLE PRV  VARIABLE PLAIN  VARIABLE Q  VARIABLE CX
: ST  ( -- settings ) SRC @ DFSRC.SETTINGS ;
: M0  ( -- model ) 0 ST ARSET-MODEL-NTH ;
: M1  ( -- model ) 1 ST ARSET-MODEL-NTH ;
\ The catalog ready, with gpt-fast selected at its default effort.
: READY  ( -- )
    ARSET-STATE-READY ST ARSET.STATE ! 0 SRC @ _DFS-MODEL-SELECT DROP ;
: SETUP  ( -- )
    DEVFLOW-SOURCE-NEW DROP SRC ! SRC @ APSOURCE-PROVIDER-NEW DROP PRV !
    SCRIPTED-PROVIDER-NEW DROP PLAIN !
    AEQ-NEW DROP Q ! ACTX-NEW DROP CX ! READY ;
SETUP

\ Ids that stay put: a designation borrows its strings.
: FAST  ( -- a u ) S" gpt-fast" ;      : SLOW  ( -- a u ) S" gpt-slow" ;
: GONE  ( -- a u ) S" gpt-gone" ;      : GPT  ( -- a u ) S" gpt" ;
: E-LOW  ( -- a u ) S" low" ;          : E-MEDIUM  ( -- a u ) S" medium" ;
: E-HIGH  ( -- a u ) S" high" ;        : E-LOW-CAP  ( -- a u ) S" Low" ;
: PRIORITY  ( -- a u ) S" priority" ;  : NONE  ( -- a u ) 0 0 ;
\ A designation in DS.
CREATE DS AGENT-RUN-DESIGNATION-SIZE ALLOT
: DES  ( model-a model-u effort-a effort-u tier-a tier-u verbosity -- )
    DS ARDES-INIT DS ARDES.VERBOSITY !
    DS ARDES.TIER-U ! DS ARDES.TIER-A !
    DS ARDES.EFFORT-U ! DS ARDES.EFFORT-A !
    DS ARDES.MODEL-U ! DS ARDES.MODEL-A ! ;
\ The status and which model: 0, 1, or -1 for none.
: WHICH  ( model -- n )
    DUP 0= IF DROP -1 EXIT THEN DUP M0 = IF DROP 0 EXIT THEN M1 = IF 1 ELSE -2 THEN ;
: STAND.  ( -- ) DS ST ARSET-DESIGNATION . WHICH . ;
: ID.  ( choice -- ) ?DUP IF ARCH-ID TYPE ELSE ." -" THEN SPACE ;

\ A turn in TN, run RUN, naming DS when DESIGNATED? is set.
CREATE TN AGENT-TURN-REQUEST-SIZE ALLOT
: TURN  ( run designated? -- )
    TN ATURN-INIT 1 TN ATURN.THREAD-ID ! SWAP TN ATURN.RUN-ID !
    S" hello" TN ATURN.PROMPT-U ! TN ATURN.PROMPT-A !
    CX @ TN ATURN.CONTEXT ! CX @ ACTX.COUNT @ TN ATURN.CONTEXT-N !
    CX @ ACTX.REVISION @ TN ATURN.CONTEXT-REVISION !
    IF DS TN ATURN.DESIGNATION ! THEN ;
: START  ( provider -- ior ) TN Q @ ROT APROV-START ;
: STOP  ( provider -- ) TN ATURN.RUN-ID @ Q @ ROT APROV-CANCEL DROP ;
\ The model, effort, tier and verbosity the provider's last turn ran on.
: LAST.  ( provider -- )
    SCRIPTED-LAST-RUN >R ROT WHICH . SWAP ID. ID. R> . ;
"""

SUITE = NativeForth(("tui/applets/agent/providers/devtools/device-flow.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 2_000_000_000) -> list[list[str]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.split() for line in output.replace("\r", "").split("\n") if line.strip()]


def numbers(rows):
    return [[int(token) for token in row] for row in rows]


def test_finding_models_and_choices(forth):
    rows = run(forth, [
        'READY S" gpt-fast" ST ARSET-FIND-MODEL WHICH . S" gpt-slow" ST ARSET-FIND-MODEL WHICH . '
        'S" gpt" ST ARSET-FIND-MODEL WHICH . 0 0 ST ARSET-FIND-MODEL WHICH . CR',
        'S" medium" M0 ARMODEL-FIND-EFFORT . S" high" M0 ARMODEL-FIND-EFFORT . '
        'S" high" M1 ARMODEL-FIND-EFFORT . S" priority" M1 ARMODEL-FIND-TIER . '
        'S" priority" M0 ARMODEL-FIND-TIER . 0 0 M1 ARMODEL-FIND-TIER . CR',
        # gpt-fast is selected at its default effort; gpt-slow has nothing
        # selected.
        "M0 ARMODEL-SELECTED-EFFORT ID. M0 ARMODEL-SELECTED-TIER ID. "
        "M1 ARMODEL-SELECTED-EFFORT ID. 0 ARMODEL-SELECTED-EFFORT ID. CR",
    ])
    assert rows == [
        ["0", "1", "-1", "-1"],
        ["1", "-1", "1", "0", "-1", "-1"],
        ["low", "-", "-", "-"],
    ]


DESIGNATIONS = {
    # designation words, status, model
    "gpt-fast, low": ("FAST E-LOW NONE 0", OK, 0),
    "gpt-fast, medium, high verbosity": ("FAST E-MEDIUM NONE 3", OK, 0),
    "gpt-slow, high, priority, low verbosity": ("SLOW E-HIGH PRIORITY 1", OK, 1),
    "gpt-slow, low, no tier": ("SLOW E-LOW NONE 0", OK, 1),
    "an unknown model": ("GONE E-LOW NONE 0", UNSUPPORTED, -1),
    "an unknown model naming nothing else": ("GONE NONE NONE 0", UNSUPPORTED, -1),
    "a model id's prefix": ("GPT E-LOW NONE 0", UNSUPPORTED, -1),
    "an effort the model lacks": ("FAST E-HIGH NONE 0", UNSUPPORTED, -1),
    "no effort for a model with efforts": ("FAST NONE NONE 0", UNSUPPORTED, -1),
    "an effort in another case": ("SLOW E-LOW-CAP NONE 0", UNSUPPORTED, -1),
    "a tier the model lacks": ("FAST E-LOW PRIORITY 0", UNSUPPORTED, -1),
    "a verbosity past high": ("FAST E-LOW NONE 4", INVALID, -1),
    "a negative verbosity": ("FAST E-LOW NONE -1", INVALID, -1),
}


def test_designations(forth):
    lines = [f"READY {words} DES STAND. CR" for words, _, _ in DESIGNATIONS.values()]
    lines += [
        # A model without efforts takes none, and no other.
        "M0 ARMODEL.EFFORTS-N @ 0 M0 ARMODEL.EFFORTS-N ! FAST NONE NONE 0 DES STAND. "
        "FAST E-LOW NONE 0 DES STAND. M0 ARMODEL.EFFORTS-N ! CR",
        # A model that does not let a run choose its verbosity takes only
        # its own.
        "M0 ARMODEL.FLAGS @ DUP ARMODEL-F-VERBOSITY INVERT AND M0 ARMODEL.FLAGS ! "
        "FAST E-LOW NONE 1 DES STAND. FAST E-LOW NONE 0 DES STAND. "
        "M0 ARMODEL.FLAGS ! CR",
        # Nothing to check, and a catalog not ready.
        '0 ST ARSET-DESIGNATION . . DS 0 ARSET-DESIGNATION . . CR',
        "FAST E-LOW NONE 0 DES ARSET-STATE-LOADING ST ARSET.STATE ! STAND. "
        "ARSET-STATE-EMPTY ST ARSET.STATE ! STAND. ARSET-STATE-ERROR ST ARSET.STATE ! "
        "STAND. READY CR",
    ]
    rows = numbers(run(forth, lines))
    assert len(rows) == len(DESIGNATIONS) + 4, rows
    for name, (_, status, model), row in zip(DESIGNATIONS, DESIGNATIONS.values(), rows):
        assert row == [status, model], name
    assert rows[-4] == [OK, 0, UNSUPPORTED, -1]
    assert rows[-3] == [UNSUPPORTED, -1, OK, 0]
    assert rows[-2] == [INVALID, 0, INVALID, 0]
    assert rows[-1] == [PENDING, -1, PENDING, -1, PENDING, -1]


def test_a_turn_runs_on_the_model_its_designation_names(forth):
    rows = run(forth, [
        # Designated: gpt-slow at high effort, the priority tier, low
        # verbosity, whatever is selected.
        "READY ST ARSET.REVISION @ SLOW E-HIGH PRIORITY 1 DES "
        "7 -1 TURN PRV @ START . PRV @ LAST. PRV @ STOP "
        "ST ARSET.REVISION @ = . CR",
        # The selection is as it was: gpt-fast at low effort, nothing chosen
        # on gpt-slow.
        "ST ARSET-SELECTED-MODEL WHICH . M1 ARMODEL.FLAGS @ ARMODEL-F-SELECTED AND . "
        "M1 ARMODEL-SELECTED-EFFORT ID. M1 ARMODEL-SELECTED-TIER ID. CR",
        # Chat runs on the selection.
        "8 0 TURN PRV @ START . PRV @ LAST. PRV @ STOP CR",
        # A designation the catalog does not offer starts nothing.
        "FAST E-HIGH NONE 0 DES 9 -1 TURN PRV @ START . PRV @ LAST. "
        "10 0 TURN PRV @ START . PRV @ STOP CR",
        # Nor does one before the catalog is ready.
        "FAST E-LOW NONE 0 DES ARSET-STATE-LOADING ST ARSET.STATE ! "
        "11 -1 TURN PRV @ START . READY CR",
        # A provider without a catalog runs no designated turn; chat runs on
        # whatever it has.
        "12 -1 TURN PLAIN @ START . 13 0 TURN PLAIN @ START . PLAIN @ LAST. "
        "PLAIN @ STOP CR",
        # Each turn records what it ran on: a provider whose catalog went
        # away since its last turn records no model.
        "ST PLAIN @ APROV.RUN-SETTINGS ! 14 0 TURN PLAIN @ START . PLAIN @ LAST. "
        "PLAIN @ STOP 0 PLAIN @ APROV.RUN-SETTINGS ! "
        "15 0 TURN PLAIN @ START . PLAIN @ LAST. PLAIN @ STOP CR",
    ])
    assert rows == [
        ["0", "1", "high", "priority", "1", "-1"],
        ["0", "0", "-", "-"],
        ["0", "0", "low", "-", "0"],
        ["2", "0", "low", "-", "0", "0"],
        ["2"],
        ["2", "0", "-1", "-", "-", "0"],
        ["0", "0", "low", "-", "0", "0", "-1", "-", "-", "0"],
    ]


def test_a_long_approval_reason_runs_to_a_line_for_each_change(forth):
    rows = run(forth, [
        "_SCRIPTED-LONG-REASON TYPE CR",
        # It is built once.
        "_SCRIPTED-LONG-REASON _SCRIPTED-LONG-REASON ROT = . = . CR",
    ])
    expected = [["Persist", "the", "simulated", "change?"]] + [
        ["Simulated", "change", str(n), "of", "100."] for n in range(1, 101)
    ]
    assert rows == expected + [["-1", "-1"]]
