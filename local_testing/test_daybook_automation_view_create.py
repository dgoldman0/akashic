#!/usr/bin/env python3
"""daybook/automation-view.f: creating an Agent run.

The view reads the Daybook dispatch suite's service, with its scripted
fake broker behind the dispatch client answering with a real model list:
fetching the list with the room it needs, and refusing one that is not
whole or names no model; the model's choices in turn, its effort, tier
and verbosity only where it offers them; the limits; a prompt that
completes the operands and is exactly what the run may disclose; the
create; and the approval it then asks Desk's user for.  A run may read
one exact document version, which Desk's broker describes: what the run
may disclose is then its prompt and that document, which it observes.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_dispatch import run, text
from test_daybook_automation_owner import NOW, utc
from test_daybook_automation_service import _advance
from test_daybook_automation_view_runs import PRELUDE as RUNS_PRELUDE


OK, INVALID, STATE = 0, 1, 5
NOMEM, MODELS, NUMBER, PROMPT, NONE, DOCUMENT = 42, 45, 46, 47, 41, 48
MODEL, EFFORT, TIER, VERBOSITY = 1, 2, 3, 4
SMALL, UNAVAILABLE = 12, 2
MINUTES_MAX = (2**63 - 1) // 60000

PRELUDE = RUNS_PRELUDE + r"""
\ A model list from the scripted provider: "gpt-test", labelled "GPT
\ Test", which takes a verbosity, with efforts low and high and the
\ unlabelled tier flex; and "mini", unlabelled, with nothing to choose.
CREATE ML-RAW 1031 ALLOT  ML-RAW 7 + -8 AND CONSTANT ML
VARIABLE ML-U
: ML-BUILD  ( -- )
    ML 1024 0 FILL 2 ML !
    S" org.akashic.agent.testing.scripted" ML 8 + SACT-STR!
    S" gpt-test" ROT SACT-STR! S" GPT Test" ROT SACT-STR!
    SDSP-M-VERBOSITY SWAP SDSP-PUT
    2 SWAP SDSP-PUT
    S" low" ROT SACT-STR! S" Low" ROT SACT-STR!
    S" high" ROT SACT-STR! S" High" ROT SACT-STR!
    1 SWAP SDSP-PUT S" flex" ROT SACT-STR! 0 0 ROT SACT-STR!
    S" mini" ROT SACT-STR! 0 0 ROT SACT-STR!
    0 SWAP SDSP-PUT 0 SWAP SDSP-PUT 0 SWAP SDSP-PUT
    ML - ML-U ! ;
\ The list with no models.
: ML-NONE  ( -- ) ML-BUILD 0 ML ! ML 8 + SACT-STR-NEXT ML - ML-U ! ;
\ Desk's broker answering with the list, in full when there is room and
\ otherwise with the room it needs, and then ML-LATE; or with ML-STATUS
\ and no bytes when that is set; or claiming ML-CLAIM bytes it never
\ wrote; or, once, asking for only ML-SHORT bytes.
VARIABLE ML-STATUS  VARIABLE ML-CLAIM  VARIABLE ML-ASKS
VARIABLE ML-SHORT  VARIABLE ML-LATE
: FC-MODEL-LIST  ( buffer capacity context -- bytes status )
    DROP 1 ML-ASKS +!
    ML-STATUS @ ?DUP IF NIP NIP 0 SWAP EXIT THEN
    ML-CLAIM @ ?DUP IF NIP NIP S-OK EXIT THEN
    ML-SHORT @ ?DUP IF 0 ML-SHORT ! NIP NIP S-SMALL EXIT THEN
    ML-U @ < IF DROP ML-U @ S-SMALL EXIT THEN
    ML SWAP ML-U @ MOVE ML-U @ ML-LATE @ ;
: ML-ON  ( -- )
    ML-BUILD 0 ML-STATUS ! 0 ML-CLAIM ! 0 ML-ASKS ! 0 ML-SHORT ! S-OK ML-LATE !
    ['] FC-MODEL-LIST FC SDSP-C.MODELS-XT ! ;
\ Each choice of KIND, a line each.
: NAMES  ( kind -- )
    DUP VW DBAV-CHOICES 0 ?DO I OVER VW DBAV-CHOICE$ TYPE CR LOOP DROP ;
\ A fresh service and view, with the fake broker and its list.
: C-FRESH  ( -- ) S-FRESH . FC-RESET FC-ON ML-ON V-NEW ;
\ An Agent run's create begun, with the list fetched.
: C-BEGIN  ( -- ) DBAS-ACTION-AGENT VW DBAV-BEGIN . VW DBAV-MODELS-FETCH . ;
\ A two-line prompt.
CREATE PR 64 ALLOT  VARIABLE PR-U
: PR+  ( a u -- ) TUCK PR PR-U @ + SWAP MOVE PR-U +! ;
: BRIEF  ( -- a u )
    0 PR-U ! S" Summarize the news." PR+ 10 PR PR-U @ + C! 1 PR-U +!
    S" Keep it short." PR+ PR PR-U @ ;
\ A prompt of U bytes in lines of 80, in an allocated block at LONG-A.
VARIABLE LONG-A
: LONG  ( u -- a u )
    DUP ALLOCATE DROP DUP LONG-A ! SWAP
    2DUP 0 ?DO
        I 80 MOD 79 = IF 10 ELSE I 26 MOD [CHAR] a + THEN OVER I + C!
    LOOP DROP ;
\ The operands the view's last create stored.
: NEW-OPS  ( -- operands u ) VW _DBAV.RID SOW DBAO-ACTION DBAS-A.OPERANDS BSLOT$ ;
\ Its limits, verbosity, effects and flags, then a line each for its
\ provider, model, effort, tier and prompt.
\ Desk's broker describing documents: "Field notes", at revision 3 and
\ DOC-BYTES bytes, unless DOC-STATUS says otherwise.
VARIABLE DOC-STATUS  VARIABLE DOC-BYTES  VARIABLE DOC-ASKS
: FC-DESCRIBE  ( locator facts context -- status )
    DROP NIP 1 DOC-ASKS +!
    DOC-STATUS @ ?DUP IF NIP EXIT THEN
    3 OVER SDSP-F.REVISION ! DOC-BYTES @ OVER SDSP-F.SIZE !
    S" Field notes" ROT SDSP-FACTS-TITLE! ;
: DOC-ON  ( -- )
    0 DOC-STATUS ! 21 DOC-BYTES ! 0 DOC-ASKS ! ['] FC-DESCRIBE FC SDSP-C.DESCRIBE-XT ! ;
\ An exact locator of revision 3 of a Library document, and an identity
\ one, which names no version.
CREATE DLOC QLOC-SIZE ALLOT  CREATE DLOC-REF RREF-SIZE ALLOT
DLOC-REF RREF-INIT  DLOC-REF RREF.ID 32 7 FILL
CREATE DLOC-DIG 32 ALLOT  DLOC-DIG 32 9 FILL
S" org.akashic.library" DLOC-REF 3 DLOC-DIG QLOC-DK-PROJECTION-CONTENT
    S" org.akashic.library.utf8-content.v1" DLOC QLOC-EXACT! DROP
CREATE ILOC QLOC-SIZE ALLOT  S" org.akashic.library" DLOC-REF ILOC QLOC-IDENTITY! DROP
: OPS.  ( -- )
    NEW-OPS DROP DUP SACT-O.TIME @ . DUP SACT-O.DISCLOSURE @ .
    DUP SACT-O.OUTPUT @ . DUP SACT-O.VERBOSITY @ . DUP SACT-O.EFFECTS @ .
    DUP SACT-O.FLAGS @ . CR
    DUP SACT-PROVIDER$ TYPE CR DUP SACT-MODEL$ TYPE CR DUP SACT-EFFORT$ TYPE CR
    DUP SACT-TIER$ TYPE CR SACT-PROMPT$ TYPE CR ;
"""

SUITE = NativeForth(("tui/applets/daybook/automation-view.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture()
def machine():
    machine = SUITE.shared()
    machine.runtime.rtc.set_epoch_ms(NOW)
    _advance(machine, 1000, 0)
    return machine


def lines(machine, line: str) -> list[str]:
    output = machine.run([line], 8_000_000_000).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [row.rstrip() for row in output.replace("\r", "").split("\n") if row.strip()]


def _fresh(machine) -> None:
    assert run(machine, ["C-FRESH CR"]) == [[OK, OK]]


def test_the_models_desk_lists(machine):
    _fresh(machine)
    # Asked first with no room, then with the room the list needs.
    assert run(machine, [f"C-BEGIN ML-ASKS @ . {MODEL} VW DBAV-CHOICES . CR"]) == [
        [OK, OK, 2, 2]]
    # Each model by its label, or its id when it has none.
    assert lines(machine, f"{MODEL} NAMES") == ["GPT Test", "mini"]
    # Asked again while the room it asks for falls short.
    assert run(machine, [f"ML-ON 16 ML-SHORT ! C-BEGIN ML-ASKS @ . "
                         f"{MODEL} VW DBAV-CHOICES . CR"]) == [[OK, OK, 3, 2]]
    # Nothing but the models until one is chosen.
    assert run(machine, [f"{EFFORT} VW DBAV-CHOICES . {TIER} VW DBAV-CHOICES . "
                         f"{VERBOSITY} VW DBAV-CHOICES . 0 VW DBAV-NEXT-KIND . "
                         f"0 {EFFORT} VW DBAV-CHOOSE . CR"]) == [[0, 0, 0, MODEL, NONE]]


def test_a_model_offers_its_choices_in_turn(machine):
    _fresh(machine)
    run(machine, ["C-BEGIN CR"])
    assert run(machine, [f"0 {MODEL} VW DBAV-CHOOSE . {MODEL} VW DBAV-NEXT-KIND . CR"]) == [
        [OK, EFFORT]]
    assert lines(machine, f"{EFFORT} NAMES") == ["Low", "High"]
    assert run(machine, [f"1 {EFFORT} VW DBAV-CHOOSE . {EFFORT} VW DBAV-NEXT-KIND . CR"]) == [
        [OK, TIER]]
    # The first tier is none: the model's default.  A tier without a label
    # shows its id.
    assert lines(machine, f"{TIER} NAMES") == ["Default", "flex"]
    assert run(machine, [f"1 {TIER} VW DBAV-CHOOSE . {TIER} VW DBAV-NEXT-KIND . CR"]) == [
        [OK, VERBOSITY]]
    assert lines(machine, f"{VERBOSITY} NAMES") == ["Default", "Low", "Medium", "High"]
    assert run(machine, [f"2 {VERBOSITY} VW DBAV-CHOOSE . "
                         f"{VERBOSITY} VW DBAV-NEXT-KIND . CR"]) == [[OK, 0]]
    # Choices beyond those offered are refused.
    assert run(machine, [f"2 {EFFORT} VW DBAV-CHOOSE . 2 {TIER} VW DBAV-CHOOSE . "
                         f"4 {VERBOSITY} VW DBAV-CHOOSE . -1 {MODEL} VW DBAV-CHOOSE . "
                         f"2 {MODEL} VW DBAV-CHOOSE . 0 9 VW DBAV-CHOOSE . "
                         "9 VW DBAV-CHOICES . CR"]) == [[NONE] * 6 + [0]]
    # Another model forgets what was chosen for the last, and mini offers
    # nothing more.
    assert run(machine, [f"1 {MODEL} VW DBAV-CHOOSE . {MODEL} VW DBAV-NEXT-KIND . "
                         "VW _DBAV.EFFORT @ . VW _DBAV.TIER @ . VW _DBAV.VERBOSITY @ . "
                         f"{EFFORT} VW DBAV-CHOICES . {TIER} VW DBAV-CHOICES . "
                         f"{VERBOSITY} VW DBAV-CHOICES . CR"]) == [[OK, 0, 0, 0, 0, 0, 0, 0]]
    # The tier choice can return to none.
    assert run(machine, [f"0 {MODEL} VW DBAV-CHOOSE DROP 1 {TIER} VW DBAV-CHOOSE DROP "
                         f"0 {TIER} VW DBAV-CHOOSE . VW _DBAV.TIER @ . CR"]) == [[OK, 0]]


def test_no_models(machine):
    _fresh(machine)
    # The broker cannot answer, the service has no client, the list is
    # not whole, or it names no model.
    assert run(machine, [f"{UNAVAILABLE} ML-STATUS ! C-BEGIN "
                         f"{MODEL} VW DBAV-CHOICES . CR"]) == [[OK, MODELS, 0]]
    assert run(machine, ["0 ML-STATUS ! 0 SV DBSVC-CLIENT! C-BEGIN FC-ON ML-ON CR"]) == [
        [OK, MODELS]]
    assert run(machine, [f"3 ML ! C-BEGIN {MODEL} VW DBAV-CHOICES . "
                         "ML-NONE C-BEGIN CR"]) == [[OK, MODELS, 0, OK, MODELS]]
    # A broker that refuses, though it wrote the list.
    assert run(machine, [f"ML-ON {UNAVAILABLE} ML-LATE ! C-BEGIN "
                         f"{MODEL} VW DBAV-CHOICES . CR"]) == [[OK, MODELS, 0]]
    # A broker that asks for no more room than it had, or claims bytes
    # beyond the room it was given.
    assert run(machine, [f"ML-ON {SMALL} ML-STATUS ! C-BEGIN ML-ASKS @ . "
                         "ML-ON 99 ML-CLAIM ! C-BEGIN ML-ASKS @ . CR"]) == [
        [OK, MODELS, 1, OK, MODELS, 1]]
    # Without memory for the list.
    assert run(machine, ["ML-ON DBAS-ACTION-AGENT VW DBAV-BEGIN . "
                         "STARVE VW DBAV-MODELS-FETCH FEED . VW _DBAV.MODELS @ . CR"]) == [
        [OK, NOMEM, 0]]
    # After any of these, there are no models to choose.
    assert run(machine, [f"0 {MODEL} VW DBAV-CHOOSE . CR"]) == [[NONE]]
    # A view outside Desk has no broker to ask.
    assert run(machine, ["VW DBAV-FREE 0 VW DBAV-INIT VW DBAV-MODELS-FETCH . V-NEW CR"]) == [
        [STATE, OK]]


def test_limits(machine):
    _fresh(machine)
    assert run(machine, ['S" 10" VW DBAV-MINUTES! . VW _DBAV.TIME @ . '
                         'S"  5 " VW DBAV-MINUTES! . VW _DBAV.TIME @ . '
                         f'S" {MINUTES_MAX}" VW DBAV-MINUTES! . VW _DBAV.TIME @ . CR']) == [
        [OK, 600000, OK, 300000, OK, MINUTES_MAX * 60000]]
    for answer in ("", "0", "-1", "1.5", "ten", "1 0", "+5", str(MINUTES_MAX + 1),
                   "1" * 19, "1" * 20):
        assert run(machine, [f'S" {answer}" VW DBAV-MINUTES! . VW _DBAV.TIME @ . CR']) == [
            [NUMBER, MINUTES_MAX * 60000]], answer
    # Any number a cell holds, and none beyond.
    assert run(machine, ['S" 16384" VW DBAV-REPLY! . VW _DBAV.OUTPUT @ . '
                         f'S" {2**63 - 1}" VW DBAV-REPLY! . VW _DBAV.OUTPUT @ . CR']) == [
        [OK, 16384, OK, 2**63 - 1]]
    # Twenty digits can wrap to a small number, here 5.
    for answer in ("", "0", "-5", "1k", str(2**63), "9" * 19, "1" * 20,
                   str(2**64 + 5)):
        assert run(machine, [f'S" {answer}" VW DBAV-REPLY! . CR']) == [[NUMBER]], answer


def _steps(machine, when: str = "09:00 Morning brief") -> None:
    assert run(machine, [
        f'C-BEGIN S" {when}" VW DBAV-WHEN! . S" daily" VW DBAV-REPEAT! . '
        f'S" " VW DBAV-ZONE! . 0 {MODEL} VW DBAV-CHOOSE . 1 {EFFORT} VW DBAV-CHOOSE . '
        f'1 {TIER} VW DBAV-CHOOSE . 2 {VERBOSITY} VW DBAV-CHOOSE . '
        'S" 10" VW DBAV-MINUTES! . S" 16384" VW DBAV-REPLY! . CR'
    ]) == [[OK] * 11]


def test_an_agent_run_is_created_and_asks_for_approval(machine):
    _fresh(machine)
    _steps(machine)
    assert run(machine, ["BRIEF VW DBAV-PROMPT! . VW DBAV-CREATE . "
                         "VW _DBAV.RID SOW DBAO-FIND DUP DBAS-S.ACTION @ . "
                         "DUP DBAS-S.REVISION @ . DBAS-S.NEXT-UTC @ . CR"]) == [
        [OK, OK, 2, 1, utc(2026, 10, 11, 9)]]
    # Its operands hold what was chosen, and disclose exactly the prompt.
    assert lines(machine, "OPS.") == [
        f"600000 {len('Summarize the news.') + 1 + len('Keep it short.')} 16384 2 0 0",
        "org.akashic.agent.testing.scripted", "gpt-test", "high", "flex",
        "Summarize the news.", "Keep it short."]
    assert text(machine, "VW _DBAV.RID SOW DBAO-FIND DBAS-S.TITLE DBAS-FIELD$ TYPE") == (
        "Morning brief")
    # Then Desk's user is asked to approve it as it is, at the revision
    # it has, here after a pause and a resume.
    assert run(machine, ["VW _DBAV.RID 1 DBSVC-NOW SOW DBAO-PAUSE . "
                         "VW _DBAV.RID 2 DBSVC-NOW SOW DBAO-RESUME . "
                         "VW DBAV-ASK-CREATED . FC-ASKS @ . "
                         "FC-REQ SDSP-R.SCHEDULE 32 VW _DBAV.RID 32 COMPARE 0= . "
                         "FC-REQ SDSP-R.REVISION @ . "
                         "FC-REQ SDSP-OPERANDS$ NEW-OPS COMPARE 0= . CR"]) == [
        [OK, OK, OK, 1, -1, 3, -1]]
    # A create begun since has made nothing to ask about.
    assert run(machine, ["DBAS-ACTION-AGENT VW DBAV-BEGIN . VW DBAV-ASK-CREATED . "
                         "FC-ASKS @ . CR"]) == [[OK, NONE, 1]]
    assert text(machine, "V-NEW VW DBAV-ASK-NOTE TYPE") == "0 Waiting for approval in Desk"


def test_a_long_prompt_is_kept_whole(machine):
    _fresh(machine)
    _steps(machine)
    assert run(machine, ["100000 LONG VW DBAV-PROMPT! . VW DBAV-CREATE . "
                         "NEW-OPS DROP DUP SACT-O.DISCLOSURE @ . "
                         "SACT-PROMPT$ LONG-A @ 100000 COMPARE 0= . LONG-A @ FREE CR"]) == [
        [OK, OK, 100000, -1]]


def test_prompts_and_creates_refused(machine):
    _fresh(machine)
    _steps(machine)
    # An empty prompt, or one with a control character other than tab
    # and line feed.
    assert run(machine, ['0 0 VW DBAV-PROMPT! . S" Ring" PR SWAP MOVE 7 PR 4 + C! '
                         "PR 5 VW DBAV-PROMPT! . VW _DBAV.OPS @ . CR"]) == [
        [PROMPT, PROMPT, 0]]
    # Without memory for the operands.
    assert run(machine, ["STARVE BRIEF VW DBAV-PROMPT! FEED . VW _DBAV.OPS @ . CR"]) == [
        [NOMEM, 0]]
    # A tab is text.
    assert run(machine, ["9 PR 4 + C! PR 5 VW DBAV-PROMPT! . CR"]) == [[OK]]
    # Without a model, or without limits, the operands are not whole.
    assert run(machine, ['C-BEGIN S" 1" VW DBAV-MINUTES! . S" 1" VW DBAV-REPLY! . '
                         "BRIEF VW DBAV-PROMPT! . VW _DBAV.OPS @ . CR"]) == [
        [OK, OK, OK, OK, INVALID, 0]]
    assert run(machine, [f"C-BEGIN 0 {MODEL} VW DBAV-CHOOSE . "
                         "BRIEF VW DBAV-PROMPT! . CR"]) == [[OK, OK, OK, INVALID]]
    # A create not yet made, or a reminder's, asks for no approval.
    assert run(machine, ["VW DBAV-ASK-CREATED . "
                         'DBAS-ACTION-REMINDER VW DBAV-BEGIN . S" 13:00 Water" VW DBAV-WHEN! . '
                         'S" " VW DBAV-REPEAT! . S" " VW DBAV-ZONE! . VW DBAV-CREATE . '
                         "VW DBAV-ASK-CREATED . FC-ASKS @ . "
                         f"{MODEL} VW DBAV-CHOICES . {EFFORT} VW DBAV-CHOICES . CR"]) == [
        [NONE, OK, OK, OK, OK, OK, NONE, 0, 0, 0]]


def test_the_create_gives_back_its_memory(machine):
    _fresh(machine)
    # Operands made again, a list fetched again, a create begun again,
    # and the view freed: what they took is back.
    assert run(machine, [
        f'VW DBAV-FREE AVAILABLE 16 ML-SHORT ! C-BEGIN 0 {MODEL} VW DBAV-CHOOSE . '
        'S" 1" VW DBAV-MINUTES! . S" 1" VW DBAV-REPLY! . '
        "BRIEF VW DBAV-PROMPT! . BRIEF VW DBAV-PROMPT! . VW DBAV-MODELS-FETCH . "
        "BRIEF VW DBAV-PROMPT! . "
        "DBAS-ACTION-AGENT VW DBAV-BEGIN . VW DBAV-MODELS-FETCH . "
        "VW DBAV-FREE AVAILABLE = . CR"]) == [
        [OK, OK, OK, OK, OK, OK, OK, OK, INVALID, OK, OK, -1]]


def test_messages():
    expected = {
        NOMEM: "Not enough memory",
        MODELS: "The Agent offers no models now",
        NUMBER: "Use a whole number above zero",
        PROMPT: "A prompt is text, and not empty",
    }
    machine = SUITE.shared()
    for status, message in expected.items():
        assert text(machine, f"{status} DBAV-MESSAGE TYPE") == message


def test_an_agent_run_that_reads_a_document(machine):
    _fresh(machine)
    # Named before the steps, the document is described through Desk.
    assert run(machine, ["DOC-ON C-BEGIN DLOC VW DBAV-DOCUMENT! . VW DBAV-DOCUMENT? . "
                         "DOC-ASKS @ . CR"]) == [[OK, OK, OK, -1, 1]]
    assert text(machine, "VW DBAV-DOCUMENT$ TYPE") == "Field notes"
    assert run(machine, [
        'S" 09:00 Morning brief" VW DBAV-WHEN! . S" daily" VW DBAV-REPEAT! . '
        f'S" " VW DBAV-ZONE! . 0 {MODEL} VW DBAV-CHOOSE . 1 {EFFORT} VW DBAV-CHOOSE . '
        f'1 {TIER} VW DBAV-CHOOSE . 2 {VERBOSITY} VW DBAV-CHOOSE . '
        'S" 10" VW DBAV-MINUTES! . S" 16384" VW DBAV-REPLY! . '
        "BRIEF VW DBAV-PROMPT! . VW DBAV-CREATE . CR"]) == [[OK] * 11]
    # It may disclose its prompt and the document, which it only observes.
    prompt = len("Summarize the news.") + 1 + len("Keep it short.")
    assert lines(machine, "OPS.")[0] == f"600000 {prompt + 21} 16384 2 1 1"
    assert run(machine, ["NEW-OPS DROP SACT-O.CONTEXT QLOC-SIZE DLOC QLOC-SIZE COMPARE . "
                         "NEW-OPS DROP SACT-PROMPT$ BRIEF COMPARE . CR"]) == [[0, 0]]
    # A fresh create names none.
    assert run(machine, ["C-BEGIN VW DBAV-DOCUMENT? . CR"]) == [[OK, OK, 0]]


def test_a_document_that_cannot_be_named(machine):
    _fresh(machine)
    assert run(machine, [
        # A locator naming no version, one that is not a locator, and a
        # document Desk's broker cannot describe.
        "DOC-ON C-BEGIN ILOC VW DBAV-DOCUMENT! . DOC-ASKS @ . "
        "CREATE JUNK QLOC-SIZE ALLOT JUNK QLOC-SIZE 0 FILL JUNK VW DBAV-DOCUMENT! . "
        f"{UNAVAILABLE} DOC-STATUS ! DLOC VW DBAV-DOCUMENT! . DOC-ASKS @ . "
        "VW DBAV-DOCUMENT? . CR"]) == [[OK, OK, DOCUMENT, 0, DOCUMENT, DOCUMENT, 1, 0]]
    assert text(machine, f"{DOCUMENT} DBAV-MESSAGE TYPE") == (
        "The document's owner cannot say what it is now")
