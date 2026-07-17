#!/usr/bin/env python3
"""Focused deterministic handler-negotiation contracts."""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "intent-negotiation-contracts"

AUTOEXEC = r'''\ autoexec.f - deterministic handler negotiation contracts
ENTER-USERLAND
." [akashic] loading intent negotiation contracts" CR
REQUIRE interop/intent.f

VARIABLE _in-fails
VARIABLE _in-checks
VARIABLE _in-depth

: _in-assert  ( flag -- )
    1 _in-checks +!
    0= IF 1 _in-fails +! ." ASSERT " _in-checks @ . CR THEN ;

: _in-stack  ( -- ) DEPTH _in-depth @ = _in-assert ;

4 CONSTANT _IN-HANDLER-N

CREATE _in-caps _IN-HANDLER-N CAP-DESC * ALLOT
CREATE _in-intents _IN-HANDLER-N CINT-DESC-SIZE * ALLOT
CREATE _in-components _IN-HANDLER-N COMP-DESC * ALLOT
CREATE _in-instances _IN-HANDLER-N 8 * ALLOT

: _in-cap       ( index -- cap ) CAP-DESC * _in-caps + ;
: _in-intent    ( index -- intent ) CINT-DESC-SIZE * _in-intents + ;
: _in-component ( index -- component ) COMP-DESC * _in-components + ;
: _in-inst-cell ( index -- cell ) 8 * _in-instances + ;
: _in-instance  ( index -- instance ) _in-inst-cell @ ;

VARIABLE _in-router
VARIABLE _in-other-router
VARIABLE _in-capacity-router
VARIABLE _in-registry
VARIABLE _in-replacement

CREATE _in-selector CINT-SELECTOR-SIZE ALLOT
CREATE _in-result CINT-RESULT-SIZE ALLOT
CREATE _in-choice CINT-CHOICE-SIZE ALLOT
CREATE _in-foreign-cap CAP-DESC ALLOT
CREATE _in-text CINT-TEXT-MAX 1+ ALLOT

VARIABLE _in-unavailable-entry
VARIABLE _in-stale-entry

: _in-available  ( entry data -- status )
    DROP
    DUP _in-stale-entry @ = IF DROP CINT-S-STALE-HANDLER EXIT THEN
    _in-unavailable-entry @ = IF CINT-S-UNAVAILABLE ELSE CINT-S-OK THEN ;

: _in-handler-base  ( index -- )
    DUP _in-cap CAP-DESC-INIT
    DUP _in-cap CAP-K-COMMAND SWAP CAP.KIND !
    DUP _in-cap S" test.open" ROT DUP >R CAP.ID-U ! R> CAP.ID-A !
    DUP _in-cap CAP-E-NAVIGATE SWAP CAP.EFFECTS !
    DUP _in-intent CINT-DESC-INIT
    DUP _in-intent S" resource.open" ROT DUP >R CINTD.ID-U !
        R> CINTD.ID-A !
    DUP _in-cap OVER _in-intent CINTD.CAP !
    DUP _in-component COMP-DESC-INIT
    DUP _in-component S" org.akashic.test.intent.handler"
        ROT DUP >R COMP.ID-U ! R> COMP.ID-A !
    DUP _in-component S" 1.0.0"
        ROT DUP >R COMP.VERSION-U ! R> COMP.VERSION-A !
    DUP _in-cap OVER _in-component COMP.CAPS-A !
    DUP _in-component 1 SWAP COMP.CAPS-N !
    DUP _in-intent OVER _in-component COMP.INTENTS-A !
    _in-component 1 SWAP COMP.INTENTS-N ! ;

: _in-handler-setup  ( -- )
    _IN-HANDLER-N 0 ?DO I _in-handler-base LOOP

    \ Exact Daybook document/text handler with deliberately low priority.
    S" org.akashic.daybook"
        0 _in-intent DUP >R CINTD.OWNER-U ! R> CINTD.OWNER-A !
    S" document" 0 _in-intent DUP >R CINTD.KIND-U ! R> CINTD.KIND-A !
    S" text/plain" 0 _in-intent DUP >R CINTD.MEDIA-U ! R> CINTD.MEDIA-A !
    1 0 _in-intent CINTD.PRIORITY !

    \ Kind-specific text handler.
    S" document" 1 _in-intent DUP >R CINTD.KIND-U ! R> CINTD.KIND-A !
    S" text/plain" 1 _in-intent DUP >R CINTD.MEDIA-U ! R> CINTD.MEDIA-A !
    999 1 _in-intent CINTD.PRIORITY !

    \ Media-specific handler.
    S" text/plain" 2 _in-intent DUP >R CINTD.MEDIA-U ! R> CINTD.MEDIA-A !
    500 2 _in-intent CINTD.PRIORITY !

    \ Fully generic handler with the highest integer priority.
    1000 3 _in-intent CINTD.PRIORITY !

    _in-foreign-cap CAP-DESC-INIT
    CAP-K-COMMAND _in-foreign-cap CAP.KIND !
    S" test.foreign" _in-foreign-cap CAP.ID-U !
        _in-foreign-cap CAP.ID-A !
    CAP-E-NAVIGATE _in-foreign-cap CAP.EFFECTS !
    _in-text CINT-TEXT-MAX 1+ 65 FILL ;

: _in-selector-init  ( -- )
    _in-selector CINT-SELECTOR-INIT
    S" resource.open"
        _in-selector CINTS.ID-U ! _in-selector CINTS.ID-A ! ;

: _in-owner-daybook  ( -- )
    S" org.akashic.daybook"
        _in-selector CINTS.OWNER-U ! _in-selector CINTS.OWNER-A ! ;

: _in-owner-other  ( -- )
    S" org.akashic.other"
        _in-selector CINTS.OWNER-U ! _in-selector CINTS.OWNER-A ! ;

: _in-kind-document  ( -- )
    S" document"
        _in-selector CINTS.KIND-U ! _in-selector CINTS.KIND-A ! ;

: _in-kind-other  ( -- )
    S" image"
        _in-selector CINTS.KIND-U ! _in-selector CINTS.KIND-A ! ;

: _in-media-text  ( -- )
    S" text/plain"
        _in-selector CINTS.MEDIA-U ! _in-selector CINTS.MEDIA-A ! ;

: _in-entry  ( index -- entry ) _in-router @ CINT-NTH ;
: _in-result-slot  ( index -- cell )
    8 * _in-result CINTR.CANDIDATES + ;

: _in-negotiate  ( router -- status )
    _in-selector SWAP _in-result CINT-NEGOTIATE ;

: _in-primary-negotiate  ( -- status ) _in-router @ _in-negotiate ;

: _in-setup  ( -- )
    _in-handler-setup
    CINT-NEW DUP 0= _in-assert DROP _in-router !
    CINT-NEW DUP 0= _in-assert DROP _in-other-router !
    CINT-NEW DUP 0= _in-assert DROP _in-capacity-router !
    CREG-NEW DUP 0= _in-assert DROP _in-registry !
    _IN-HANDLER-N 0 ?DO
        I _in-intent CINT-DESC-VALID? _in-assert
        I _in-component _in-router @ CINT-REGISTER-COMP 0= _in-assert
        I _in-component CINST-NEW DUP 0= _in-assert DROP
            DUP I _in-inst-cell !
        _in-registry @ CREG-INST+ 0= _in-assert
    LOOP
    \ A separate activation-local router is used to prove stale choices.
    1 _in-component _in-other-router @ CINT-REGISTER-COMP 0= _in-assert ;

: _in-basic-cases  ( -- )
    CINT-DESC-SIZE 96 = _in-assert
    CINT-ENTRY-SIZE 112 = _in-assert
    CINT-SELECTOR-SIZE 128 = _in-assert
    CINT-CHOICE-SIZE 80 = _in-assert
    CINT-RESULT-SIZE 312 = _in-assert
    _in-router @ CINT-VALID? _in-assert
    _in-router @ CINT.COUNT @ 4 = _in-assert
    0 _in-entry CIE.PRIORITY @ 1 = _in-assert
    3 _in-entry CIE.PRIORITY @ 1000 = _in-assert
    0 _in-entry CIE.CAP @ 0 _in-cap = _in-assert

    \ No hint makes all four handlers equally applicable.  Priority cannot
    \ break the tie, and the legacy API fails closed rather than picking one.
    S" resource.open" _in-router @ CINT-RESOLVE-STATUS
        CINT-S-AMBIGUOUS = _in-assert 0= _in-assert
    S" resource.open" _in-router @ CINT-RESOLVE 0= _in-assert
    S" resource.open" _in-other-router @ CINT-RESOLVE-STATUS
        CINT-S-OK = _in-assert
    CIE.COMP-DESC @ 1 _in-component = _in-assert
    _in-selector-init
    _in-primary-negotiate CINT-S-AMBIGUOUS = _in-assert
    _in-result CINTR.COUNT @ 4 = _in-assert
    _in-result CINT-RESULT-VALID? _in-assert
    0 _in-result CINT-RESULT-NTH 0 _in-entry = _in-assert
    3 _in-result CINT-RESULT-NTH 3 _in-entry = _in-assert
    4 _in-result CINT-RESULT-NTH 0= _in-assert
    -1 _in-result CINT-RESULT-NTH 0= _in-assert
    4 _in-result-slot @ 0= _in-assert

    _in-selector-init S" missing.intent"
        _in-selector CINTS.ID-U ! _in-selector CINTS.ID-A !
    _in-primary-negotiate CINT-S-NO-HANDLER = _in-assert
    _in-result CINTR.COUNT @ 0= _in-assert ;

: _in-ranking-cases  ( -- )
    \ Exact owner+kind beats every generic route, despite priority 1.
    _in-selector-init _in-owner-daybook _in-kind-document _in-media-text
    _in-primary-negotiate CINT-S-OK = _in-assert
    _in-result CINTR.SELECTED @ 0 _in-entry = _in-assert
    _in-result CINTR.COUNT @ 1 = _in-assert
    _in-result CINT-RESULT-VALID? _in-assert
    1 _in-result-slot @ 0= _in-assert

    \ Without an owner hint, both exact-kind handlers remain a real tie.
    _in-selector-init _in-kind-document _in-media-text
    _in-primary-negotiate CINT-S-AMBIGUOUS = _in-assert
    _in-result CINTR.COUNT @ 2 = _in-assert
    0 _in-result CINT-RESULT-NTH 0 _in-entry = _in-assert
    1 _in-result CINT-RESULT-NTH 1 _in-entry = _in-assert

    \ A conflicting owner excludes the Daybook handler; exact kind wins.
    _in-selector-init _in-owner-other _in-kind-document _in-media-text
    _in-primary-negotiate CINT-S-OK = _in-assert
    _in-result CINTR.SELECTED @ 1 _in-entry = _in-assert

    \ With owner/kind conflicts removed, exact media beats the generic route.
    _in-selector-init _in-owner-other _in-kind-other _in-media-text
    _in-primary-negotiate CINT-S-OK = _in-assert
    _in-result CINTR.SELECTED @ 2 _in-entry = _in-assert ;

: _in-choice-cases  ( -- )
    1 _in-entry 1 _in-instance _in-router @ _in-choice CINT-CHOICE!
        CINT-S-OK = _in-assert
    _in-choice CINT-CHOICE-VALID? _in-assert
    CINT-CHOICE-SIZE 8 + _in-choice CINTC.SIZE !
    _in-choice CINT-CHOICE-VALID? 0= _in-assert
    CINT-CHOICE-SIZE _in-choice CINTC.SIZE !
    1 _in-choice CINTC.RESERVED !
    _in-choice CINT-CHOICE-VALID? 0= _in-assert
    0 _in-choice CINTC.RESERVED !
    _in-choice CINT-CHOICE-VALID? _in-assert
    0 _in-entry 1 _in-instance _in-router @ _in-choice CINT-CHOICE!
        CINT-S-INVALID = _in-assert
    _in-choice CINT-CHOICE-VALID? 0= _in-assert
    1 _in-entry 1 _in-instance _in-router @ _in-choice CINT-CHOICE!
        CINT-S-OK = _in-assert

    _in-selector-init _in-kind-document _in-media-text
    _in-choice _in-selector CINTS.CHOICE !
    _in-registry @ _in-selector CINTS.REGISTRY !
    _in-primary-negotiate CINT-S-OK = _in-assert
    _in-result CINTR.SELECTED @ 1 _in-entry = _in-assert
    _in-result CINTR.INSTANCE @ 1 _in-instance = _in-assert
    _in-registry @ CREG.INST-N @ 4 = _in-assert
    1 _in-instance CINST.REVISION @ 1 = _in-assert

    \ A remembered choice outside the top applicability class is stale and
    \ never falls through to the otherwise valid exact-owner handler.
    _in-owner-daybook
    _in-primary-negotiate CINT-S-STALE-CHOICE = _in-assert
    _in-result CINTR.SELECTED @ 0= _in-assert
    _in-result CINTR.COUNT @ 0= _in-assert
    _in-result CINT-RESULT-VALID? _in-assert

    \ No live instance for the explicit handler is unavailable; a new
    \ generation of the same handler makes the old choice explicitly stale.
    _in-selector-init _in-kind-document _in-media-text
    _in-choice _in-selector CINTS.CHOICE !
    _in-registry @ _in-selector CINTS.REGISTRY !
    1 _in-instance _in-registry @ CREG-INST- 0= _in-assert
    _in-primary-negotiate CINT-S-UNAVAILABLE = _in-assert
    _in-result CINTR.COUNT @ 0= _in-assert
    _in-result CINT-RESULT-VALID? _in-assert
    1 _in-component CINST-NEW DUP 0= _in-assert DROP
        DUP _in-replacement !
    _in-registry @ CREG-INST+ 0= _in-assert
    _in-primary-negotiate CINT-S-STALE-HANDLER = _in-assert
    _in-result CINT-RESULT-VALID? _in-assert
    _in-replacement @ _in-registry @ CREG-INST- 0= _in-assert
    _in-replacement @ CINST-FREE
    0 _in-replacement !
    1 _in-instance _in-registry @ CREG-INST+ 0= _in-assert

    \ Router identity/epoch is part of the activation-local choice.
    _in-other-router @ _in-negotiate CINT-S-STALE-CHOICE = _in-assert
    _in-result CINTR.SELECTED @ 0= _in-assert ;

: _in-availability-cases  ( -- )
    _in-selector-init _in-owner-daybook _in-kind-document _in-media-text
    ['] _in-available _in-selector CINTS.AVAILABLE-XT !
    0 _in-entry _in-unavailable-entry !
    _in-primary-negotiate CINT-S-UNAVAILABLE = _in-assert
    _in-result CINTR.COUNT @ 0= _in-assert
    _in-result CINTR.SELECTED @ 0= _in-assert

    0 _in-unavailable-entry ! 0 _in-entry _in-stale-entry !
    _in-primary-negotiate CINT-S-STALE-HANDLER = _in-assert
    _in-result CINTR.SELECTED @ 0= _in-assert
    0 _in-stale-entry ! ;

: _in-invalid-cases  ( -- )
    \ ABI records are closed: a larger record is not silently accepted as
    \ today's layout, and all declared reserved cells remain zero.
    _in-selector-init
    _in-selector CINT-SELECTOR-VALID? _in-assert
    CINT-SELECTOR-SIZE 8 + _in-selector CINTS.SIZE !
    _in-selector CINT-SELECTOR-VALID? 0= _in-assert
    CINT-SELECTOR-SIZE _in-selector CINTS.SIZE !
    _in-primary-negotiate CINT-S-AMBIGUOUS = _in-assert
    _in-result CINT-RESULT-VALID? _in-assert
    CINT-RESULT-SIZE 8 + _in-result CINTR.SIZE !
    _in-result CINT-RESULT-VALID? 0= _in-assert
    CINT-RESULT-SIZE _in-result CINTR.SIZE !
    0 _in-entry 4 _in-result-slot !
    _in-result CINT-RESULT-VALID? 0= _in-assert
    0 4 _in-result-slot !
    0 0 _in-result-slot !
    _in-result CINT-RESULT-VALID? 0= _in-assert
    0 _in-entry 0 _in-result-slot !
    0 _in-entry _in-result CINTR.SELECTED !
    _in-result CINT-RESULT-VALID? 0= _in-assert
    0 _in-result CINTR.SELECTED !
    _in-result CINT-RESULT-VALID? _in-assert

    _in-selector-init
    1 _in-selector CINTS.OWNER-U !
    0 _in-selector CINTS.OWNER-A !
    _in-primary-negotiate CINT-S-INVALID = _in-assert
    _in-result CINT-RESULT-VALID? _in-assert

    _in-selector-init
    _in-choice _in-selector CINTS.CHOICE !
    _in-primary-negotiate CINT-S-INVALID = _in-assert

    1 0 _in-intent CINTD.FLAGS !
    0 _in-intent CINT-DESC-VALID? 0= _in-assert
    0 0 _in-intent CINTD.FLAGS !
    0 _in-intent CINT-DESC-VALID? _in-assert
    1 0 _in-intent CINTD.RESERVED !
    0 _in-intent CINT-DESC-VALID? 0= _in-assert
    0 0 _in-intent CINTD.RESERVED !

    \ Intent IDs and routing dimensions are bounded UTF-8 text, including
    \ the borrowed descriptor declarations and caller-owned selectors.
    255 _in-text C!
    _in-text 1 3 _in-intent DUP >R CINTD.OWNER-U ! R> CINTD.OWNER-A !
    3 _in-intent CINT-DESC-VALID? 0= _in-assert
    _in-selector-init
    _in-text 1 _in-selector CINTS.KIND-U !
        _in-selector CINTS.KIND-A !
    _in-selector CINT-SELECTOR-VALID? 0= _in-assert
    _in-selector CINT-SELECTOR-INIT
    _in-text 1 _in-selector CINTS.ID-U !
        _in-selector CINTS.ID-A !
    _in-selector CINT-SELECTOR-VALID? 0= _in-assert
    65 _in-text C!
    _in-text CINT-TEXT-MAX 3 _in-intent DUP >R CINTD.OWNER-U !
        R> CINTD.OWNER-A !
    3 _in-intent CINT-DESC-VALID? _in-assert
    CINT-TEXT-MAX 1+ 3 _in-intent CINTD.OWNER-U !
    3 _in-intent CINT-DESC-VALID? 0= _in-assert
    0 3 _in-intent CINTD.OWNER-A !
    0 3 _in-intent CINTD.OWNER-U !
    3 _in-intent CINT-DESC-VALID? _in-assert ;

: _in-capability-and-bound-cases  ( -- )
    \ A syntactically valid capability from another component is still not
    \ this component's declared intent capability.
    _in-foreign-cap CAP-DESC-VALID? _in-assert
    _in-foreign-cap 0 _in-intent CINTD.CAP !
    0 _in-intent CINT-DESC-VALID? _in-assert
    0 _in-intent 0 _in-component _in-capacity-router @
        CINT-REGISTER-DESC CREG-E-NOT-FOUND = _in-assert
    _in-capacity-router @ CINT.COUNT @ 0= _in-assert
    0 _in-cap 0 _in-intent CINTD.CAP !

    0 _in-foreign-cap CAP.KIND !
    _in-foreign-cap 0 _in-intent CINTD.CAP !
    0 _in-intent CINT-DESC-VALID? 0= _in-assert
    CAP-K-COMMAND _in-foreign-cap CAP.KIND !
    0 _in-cap 0 _in-intent CINTD.CAP !

    \ The text and router bounds fail before mutation, while all 32 valid
    \ registrations remain visible as a deterministic Open With set.
    _in-text CINT-TEXT-MAX 1+ 0 _in-component 0 _in-cap 0
        _in-capacity-router @ CINT-REGISTER
        CREG-E-NOT-FOUND = _in-assert
    _in-capacity-router @ CINT.COUNT @ 0= _in-assert
    CINT-MAX 0 ?DO
        _in-text CINT-TEXT-MAX 0 _in-component 0 _in-cap I
            _in-capacity-router @ CINT-REGISTER 0= _in-assert
    LOOP
    _in-capacity-router @ CINT.COUNT @ CINT-MAX = _in-assert
    _in-text CINT-TEXT-MAX 0 _in-component 0 _in-cap 0
        _in-capacity-router @ CINT-REGISTER CREG-E-FULL = _in-assert
    0 _in-component _in-capacity-router @ CINT-REGISTER-COMP
        CREG-E-FULL = _in-assert
    _in-capacity-router @ CINT.COUNT @ CINT-MAX = _in-assert
    _in-selector CINT-SELECTOR-INIT
    _in-text CINT-TEXT-MAX _in-selector CINTS.ID-U !
        _in-selector CINTS.ID-A !
    _in-capacity-router @ _in-negotiate CINT-S-AMBIGUOUS = _in-assert
    _in-result CINTR.COUNT @ CINT-MAX = _in-assert
    CINT-MAX 1- _in-result CINT-RESULT-NTH 0<> _in-assert
    CINT-MAX _in-result CINT-RESULT-NTH 0= _in-assert ;

: _in-cleanup  ( -- )
    _IN-HANDLER-N 0 ?DO
        I _in-instance _in-registry @ CREG-INST- 0= _in-assert
        I _in-instance CINST-FREE
        0 I _in-inst-cell !
    LOOP
    _in-registry @ CREG-FREE
    _in-capacity-router @ CINT-FREE
    _in-other-router @ CINT-FREE
    _in-router @ CINT-FREE ;

: _in-run  ( -- )
    0 _in-fails ! 0 _in-checks ! DEPTH _in-depth !
    _in-setup
    _in-basic-cases
    _in-ranking-cases
    _in-choice-cases
    _in-availability-cases
    _in-invalid-cases
    _in-capability-and-bound-cases
    _in-cleanup
    _in-stack
    _in-fails @ 0= IF
        ." INTENT NEGOTIATION PASS " _in-checks @ .
    ELSE
        ." INTENT NEGOTIATION FAIL " _in-fails @ . ." / " _in-checks @ .
    THEN CR ;

_in-run
'''


def test_intent_negotiation(tmp_path: Path) -> None:
    PROFILES[PROFILE_NAME] = Profile(
        roots=("interop/intent.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("INTENT NEGOTIATION PASS",),
        stable_markers=("INTENT NEGOTIATION PASS",),
        failure_markers=("INTENT NEGOTIATION FAIL",),
    )
    image = build_image(PROFILE_NAME, tmp_path / f"{PROFILE_NAME}.img")
    assert smoke(
        PROFILE_NAME,
        image,
        cols=100,
        rows=30,
        max_steps=1_000_000_000,
        timeout=90.0,
    )


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_intent_negotiation(Path(directory))
