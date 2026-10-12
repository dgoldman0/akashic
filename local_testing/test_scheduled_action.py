#!/usr/bin/env python3
"""interop/scheduled-action.f and scheduled-dispatch.f on the native executor.

The action catalog: classes, the canonical bytes of an Agent run's
operands (checked against a Python encoder), every refusal of malformed
operands, the operand digest and dispatch key (checked against hashlib),
and the closed table of outcome and reason pairs.  The dispatch contract:
requests and every rule they are checked against, responses, the client
record with missing or unfilled words, and model lists read only inside
their bytes.
"""

from __future__ import annotations

import hashlib
import struct

import pytest

from native_forth import NativeForth


S_OK, S_ACTION, S_SCHEMA, S_SHAPE, S_BUDGET, S_MODEL, S_PROMPT, S_CONTEXT, S_SMALL = range(9)
REMINDER, AGENT_RUN = 1, 2
MANUAL, AUTOMATIC = 1, 2
(D_OK, D_INVALID, D_UNAVAILABLE, D_STARTED, D_WAITING, D_ENDED, D_RUNNING,
 D_UNKNOWN, D_PENDING, D_ALLOWED, D_REFUSED, D_GONE, D_SMALL) = range(13)
A_UNAVAILABLE = 6

PROVIDER = b"org.akashic.agent.testing.scripted"
MODEL = b"gpt-test"
EFFORT = b"high"
PROMPT = b"Summarize the news."


def field(text: bytes) -> bytes:
    return struct.pack("<Q", len(text)) + text + b"\0" * (-len(text) % 8)


def operands(*, time=300_000, disclosure=4096, output=16_384, verbosity=2,
             provider=PROVIDER, model=MODEL, effort=EFFORT, tier=b"",
             prompt=PROMPT) -> bytes:
    head = struct.pack("<QQQQQQQ", 1, 0, 0, time, disclosure, output, verbosity)
    return head + field(provider) + field(model) + field(effort) + field(tier) + field(prompt)


def operand_digest(action: int, schema: int, data: bytes) -> bytes:
    return hashlib.sha3_256(
        b"akashic.sched.operands.v1" + struct.pack("<QQQ", action, schema, len(data)) + data
    ).digest()


def dispatch_key(store: bytes, rid: bytes, occurrence: int) -> bytes:
    return hashlib.sha3_256(
        b"akashic.daybook.dispatch.v1" + store + rid + struct.pack("<Q", occurrence)
    ).digest()


PRELUDE = r"""
CREATE TD-RAW SACT-DRAFT-SIZE 7 + ALLOT  TD-RAW 7 + -8 AND CONSTANT TD
CREATE TO-RAW 8199 ALLOT  TO-RAW 7 + -8 AND CONSTANT TO
VARIABLE TOU
CREATE TQ-RAW 16391 ALLOT  TQ-RAW 7 + -8 AND CONSTANT TQ
CREATE TP-RAW 1031 ALLOT  TP-RAW 7 + -8 AND CONSTANT TP
CREATE TL-RAW 4103 ALLOT  TL-RAW 7 + -8 AND CONSTANT TL
VARIABLE TLU
CREATE TC-RAW SDSP-CLIENT-SIZE 7 + ALLOT  TC-RAW 7 + -8 AND CONSTANT TC
CREATE TDIG 32 ALLOT
CREATE TSTR 512 ALLOT
VARIABLE TSTRU
: T-DUMP  ( a u -- ) 0 ?DO DUP I + C@ . LOOP DROP CR ;
: TB!  ( b -- ) TSTR TSTRU @ + C! 1 TSTRU +! ;
: T-STR  ( -- a u ) TSTR TSTRU @ ;
: T-DRAFT  ( -- )
    TD SACT-DRAFT-INIT
    300000 TD SACT-D.TIME !
    4096 TD SACT-D.DISCLOSURE !
    16384 TD SACT-D.OUTPUT !
    2 TD SACT-D.VERBOSITY !
    S" org.akashic.agent.testing.scripted" TD SACT-D.PROVIDER SACT-D!
    S" gpt-test" TD SACT-D.MODEL SACT-D!
    S" high" TD SACT-D.EFFORT SACT-D!
    0 0 TD SACT-D.TIER SACT-D!
    S" Summarize the news." TD SACT-D.PROMPT SACT-D! ;
\ An exact locator of revision 3 of a Library document, and a draft that
\ observes it.
CREATE TLOC QLOC-SIZE ALLOT  CREATE TLOC-REF RREF-SIZE ALLOT
TLOC-REF RREF-INIT  TLOC-REF RREF.ID 32 7 FILL
CREATE TLOC-DIG 32 ALLOT  TLOC-DIG 32 9 FILL
S" org.akashic.library" TLOC-REF 3 TLOC-DIG QLOC-DK-PROJECTION-CONTENT
    S" org.akashic.library.text" TLOC QLOC-EXACT! DROP
: T-DOC  ( -- ) T-DRAFT TLOC TD SACT-D.CONTEXT ! CAP-E-OBSERVE TD SACT-D.EFFECTS ! ;
: T-ENC  ( -- status ) TD TO 8192 SACT-AGENT-ENCODE SWAP TOU ! ;
: T-OK  ( -- status ) SACT-AGENT-RUN SACT-SCHEMA TO TOU @ SACT-OPERANDS-OK? ;
\ The request in TQ for the encoded operands: store bytes 1, schedule
\ bytes 2, revision 3, Practice bytes 4, occurrence 5 (kind ON-TIME) with
\ its key, permission bytes 6 revision 1, trigger digest bytes 7.
: T-REQUEST  ( -- )
    S" Morning brief" NIP S" daily at 08:00 UTC0" NIP TOU @ SDSP-REQUEST-SIZE
    TQ SDSP-REQUEST-INIT
    SACT-AGENT-RUN TQ SDSP-R.ACTION !  SACT-SCHEMA TQ SDSP-R.SCHEMA !
    TQ SDSP-R.STORE 32 1 FILL  TQ SDSP-R.SCHEDULE 32 2 FILL
    3 TQ SDSP-R.REVISION !  TQ SDSP-R.PRACTICE 32 4 FILL
    5 TQ SDSP-R.OCCURRENCE !  SDSP-K-ON-TIME TQ SDSP-R.KIND !
    TQ SDSP-R.PERMISSION 32 6 FILL  1 TQ SDSP-R.PERMISSION-REVISION !
    TQ SDSP-R.TRIGGER-DIGEST 32 7 FILL
    S" Morning brief" TQ SDSP-TAIL+
    S" daily at 08:00 UTC0" TQ SDSP-TAIL+
    TO TOU @ TQ SDSP-TAIL+
    SACT-AGENT-RUN SACT-SCHEMA TO TOU @ TQ SDSP-R.OPERANDS-DIGEST SACT-DIGEST
    TQ SDSP-R.STORE TQ SDSP-R.SCHEDULE 5 TQ SDSP-R.KEY SDSP-KEY ;
: T-QOK  ( -- status ) TQ -1 SDSP-REQUEST-OK? ;
\ Appenders for the words that say what a run names: one types the
\ words, the other adds their lengths to the cell its context names.
: T-SAY  ( a u context -- ) DROP TYPE ;
: T-COUNT  ( a u context -- ) +! DROP ;
VARIABLE T-SAID
\ Fake broker words: each prints what it was given, then answers.
: F-SUBMIT  ( request response ctx -- status ) . . . CR D_STARTED ;
: F-STATUS  ( key response ctx -- status ) . . . CR SDSP-S-RUNNING ;
: F-CANCEL  ( key ctx -- status ) . . CR SDSP-S-OK ;
: F-ASK  ( request ctx -- ask-id status ) . . CR 42 SDSP-S-PENDING ;
: F-ASKED  ( ask-id response ctx -- status ) . . . CR SDSP-S-ALLOWED ;
: F-CHECK  ( request ctx -- standing status ) . . CR SDSP-A-APPROVED SDSP-S-OK ;
: F-MODELS  ( buffer cap ctx -- bytes status ) . . . CR 64 SDSP-S-OK ;
\ A model list in TL: two models, the first with efforts low and high and
\ no tiers, the second with no efforts and one tier.
: T-LIST  ( -- )
    TL 4096 0 FILL
    2 TL SDSP-PUT
    S" org.akashic.agent.codex" ROT SACT-STR!
    S" gpt-a" ROT SACT-STR!  S" Model A" ROT SACT-STR!  SDSP-M-VERBOSITY SWAP SDSP-PUT
    2 SWAP SDSP-PUT
    S" low" ROT SACT-STR!  S" Low" ROT SACT-STR!
    S" high" ROT SACT-STR!  S" High" ROT SACT-STR!
    0 SWAP SDSP-PUT
    S" gpt-b" ROT SACT-STR!  S" Model B" ROT SACT-STR!  0 SWAP SDSP-PUT
    0 SWAP SDSP-PUT
    1 SWAP SDSP-PUT
    S" flex" ROT SACT-STR!  S" Flex" ROT SACT-STR!
    TL - TLU ! ;
"""

PRELUDE = PRELUDE.replace("D_STARTED", "SDSP-S-STARTED")

SUITE = NativeForth(("interop/scheduled-dispatch.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 400_000_000) -> list[list[int]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [[int(token) for token in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def emit_bytes(data: bytes) -> list[str]:
    """Forth lines that leave DATA in TSTR."""

    lines = ["0 TSTRU !"]
    for start in range(0, len(data), 32):
        lines.append(" ".join(f"{byte} TB!" for byte in data[start:start + 32]))
    return lines


def test_classes_and_names(forth):
    lines = run(forth, [
        "1 1 SACT-CLASS . 2 1 SACT-CLASS . 2 2 SACT-CLASS . 3 1 SACT-CLASS . 0 1 SACT-CLASS . CR",
        "1 SACT-NAME$ T-DUMP 2 SACT-NAME$ T-DUMP 3 SACT-NAME$ NIP . CR",
    ])
    assert lines[0] == [MANUAL, AUTOMATIC, 0, 0, 0]
    assert bytes(lines[1]) == b"daybook.reminder"
    assert bytes(lines[2]) == b"agent.run.request"
    assert lines[3] == [0]


def test_an_agent_run_encodes_canonically(forth):
    lines = run(forth, [
        "T-DRAFT T-ENC . TOU @ . TD SACT-AGENT-SIZE . CR",
        "TO TOU @ T-DUMP",
        "TO SACT-PROVIDER$ T-DUMP TO SACT-MODEL$ T-DUMP TO SACT-EFFORT$ NIP . CR",
        "TO SACT-TIER$ NIP . TO SACT-PROMPT$ NIP . TO SACT-O.CONTEXT . CR",
    ])
    expected = operands()
    assert lines[0] == [S_OK, len(expected), len(expected)]
    assert bytes(lines[1]) == expected
    assert bytes(lines[2]) == PROVIDER
    assert bytes(lines[3]) == MODEL
    assert lines[4] == [len(EFFORT)]
    assert lines[5] == [0, len(PROMPT), 0]


def test_a_destination_too_small_takes_nothing(forth):
    lines = run(forth, [
        "T-DRAFT TO 64 170 FILL",
        "TD TO 64 SACT-AGENT-ENCODE . . TO C@ . CR",
    ])
    assert lines == [[S_SMALL, len(operands()), 170]]


def test_a_reminder_takes_no_operands(forth):
    lines = run(forth, [
        "1 1 TO 0 SACT-OPERANDS-OK? . 1 1 TO 8 SACT-OPERANDS-OK? . CR",
        "1 2 TO 0 SACT-OPERANDS-OK? . 9 1 TO 0 SACT-OPERANDS-OK? . CR",
    ])
    assert lines == [[S_OK, S_SHAPE], [S_SCHEMA, S_ACTION]]


@pytest.mark.parametrize("edit,status", [
    ("TO SACT-O.SCHEMA 2 SWAP !", S_SCHEMA),
    ("2 TO SACT-O.FLAGS !", S_SHAPE),
    ("1 TO SACT-O.FLAGS !", S_CONTEXT),
    ("1 TO SACT-O.EFFECTS !", S_CONTEXT),
    ("0 TO SACT-O.TIME !", S_BUDGET),
    ("0 TO SACT-O.DISCLOSURE !", S_BUDGET),
    ("-1 TO SACT-O.OUTPUT !", S_BUDGET),
    ("18 TO SACT-O.DISCLOSURE !", S_BUDGET),
    ("4 TO SACT-O.VERBOSITY !", S_MODEL),
    ("TOU @ 8 - TOU !", S_SHAPE),
    ("TOU @ 8 + TOU !", S_SHAPE),
    ("40 TOU !", S_SHAPE),
    ("1 TO SACT-O.PROVIDER 8 + 34 + C!", S_SHAPE),
    ("9 TO SACT-O.MODEL 8 + C!", S_MODEL),
    ("127 TO SACT-O.MODEL 8 + 1+ C!", S_MODEL),
    ("255 TO SACT-O.PROMPT 8 + C!", S_PROMPT),
    ("13 TO SACT-O.PROMPT 8 + C!", S_PROMPT),
    ("127 TO SACT-O.PROMPT 8 + C!", S_PROMPT),
])
def test_malformed_operands_are_refused(forth, edit, status):
    lines = run(forth, [f"T-DRAFT T-ENC . {edit} T-OK . CR"])
    assert lines == [[S_OK, status]]


def test_a_run_may_observe_one_exact_document(forth):
    lines = run(forth, [
        "T-DOC T-ENC . TOU @ . TO SACT-O.FLAGS @ . TO SACT-O.EFFECTS @ . "
        "TO SACT-O.CONTEXT QLOC-SIZE TLOC QLOC-SIZE COMPARE . "
        "TO SACT-PROMPT$ S\" Summarize the news.\" COMPARE . T-OK . CR",
    ])
    assert lines == [[S_OK, len(operands()) + 320, 1, 1, 0, 0, S_OK]]


@pytest.mark.parametrize("edit,status", [
    ("0 TO SACT-O.EFFECTS !", S_CONTEXT),
    ("CAP-E-OBSERVE CAP-E-MUTATE OR TO SACT-O.EFFECTS !", S_CONTEXT),
    ("0 TO SACT-O.FLAGS !", S_CONTEXT),
    ("0 TO SACT-O.CONTEXT QLOC.MAGIC !", S_CONTEXT),
    ("QLOC-M-IDENTITY TO SACT-O.CONTEXT QLOC.MODE !", S_CONTEXT),
    ("TOU @ 8 - TOU !", S_SHAPE),
    ("TO SACT-O.CONTEXT TO - TOU !", S_CONTEXT),
])
def test_a_document_must_be_one_exact_locator(forth, edit, status):
    lines = run(forth, [f"T-DOC T-ENC . {edit} T-OK . CR"])
    assert lines == [[S_OK, status]]


@pytest.mark.parametrize("change,status", [
    ("0 0 TD SACT-D.PROVIDER SACT-D!", S_MODEL),
    ("0 0 TD SACT-D.MODEL SACT-D!", S_MODEL),
    ("0 0 TD SACT-D.PROMPT SACT-D!", S_PROMPT),
    ("TO TD SACT-D.CONTEXT !", S_CONTEXT),
])
def test_drafts_that_cannot_encode(forth, change, status):
    assert run(forth, [f"T-DRAFT {change} T-ENC . CR"]) == [[status]]


def test_a_prompt_may_hold_tabs_and_line_feeds(forth):
    prompt = b"Line one.\n\tLine two \xe2\x80\x94 done."
    lines = run(forth, [
        "T-DRAFT", *emit_bytes(prompt),
        "T-STR TD SACT-D.PROMPT SACT-D! T-ENC . TO TOU @ T-DUMP",
    ])
    assert lines[0][0] == S_OK
    assert bytes(lines[0][1:]) == operands(prompt=prompt)


def test_the_operand_digest(forth):
    lines = run(forth, [
        "T-DRAFT T-ENC DROP",
        "2 1 TO TOU @ TDIG SACT-DIGEST TDIG 32 T-DUMP",
        "1 1 TO TOU @ TDIG SACT-DIGEST TDIG 32 T-DUMP",
        "1 TO TOU @ 1- + C! 2 1 TO TOU @ TDIG SACT-DIGEST TDIG 32 T-DUMP",
    ])
    data = operands()
    assert bytes(lines[0]) == operand_digest(2, 1, data)
    assert bytes(lines[1]) == operand_digest(1, 1, data)
    changed = data[:-1] + b"\x01"
    assert bytes(lines[2]) == operand_digest(2, 1, changed)
    assert len({bytes(line) for line in lines}) == 3


OUTCOMES = {
    0: {1}, 1: {6}, 2: {6, 3}, 3: {6}, 4: {6}, 5: {6}, 6: {6}, 7: {6}, 8: {6},
    9: {6}, 10: {6}, 11: {6}, 12: {8}, 13: {8}, 14: {3}, 15: {3}, 16: {5},
    17: {5}, 18: {5}, 19: {4}, 20: {4}, 21: {4}, 22: {2}, 23: {2}, 24: {2},
    25: {2}, 26: {7}, 27: {7}, 28: {7}, 29: {7},
}


def test_only_listed_outcome_and_reason_pairs_are_valid(forth):
    lines = run(forth, [
        f"{outcome} {reason} SACT-OUTCOME-OK? ."
        for outcome in range(0, 10) for reason in range(-1, 31)
    ] + ["CR"])
    flags = lines[0]
    index = 0
    for outcome in range(0, 10):
        for reason in range(-1, 31):
            allowed = outcome in OUTCOMES.get(reason, set())
            assert flags[index] == (-1 if allowed else 0), (outcome, reason)
            index += 1


def test_every_outcome_and_reason_has_words(forth):
    lines = run(forth, [
        " ".join(f"{o} SACT-OUTCOME$ NIP 0> ." for o in range(0, 10)) + " CR",
        " ".join(f"{r} SACT-REASON$ NIP 0> ." for r in range(-1, 31)) + " CR",
    ])
    assert lines[0] == [0] + [-1] * 8 + [0]
    assert lines[1] == [0, 0] + [-1] * 29 + [0]


def test_the_dispatch_key(forth):
    lines = run(forth, [
        "TQ 32 1 FILL TQ 32 + 32 2 FILL TQ TQ 32 + 5 TDIG SDSP-KEY TDIG 32 T-DUMP",
        "TQ TQ 32 + 6 TDIG SDSP-KEY TDIG 32 T-DUMP",
    ])
    assert bytes(lines[0]) == dispatch_key(b"\x01" * 32, b"\x02" * 32, 5)
    assert bytes(lines[1]) == dispatch_key(b"\x01" * 32, b"\x02" * 32, 6)


def test_a_well_formed_request(forth):
    lines = run(forth, [
        "T-DRAFT T-ENC DROP T-REQUEST T-QOK . TQ SDSP-REQUEST-U TQ SDSP-R.SIZE @ = . CR",
        "TQ SDSP-TITLE$ T-DUMP TQ SDSP-TRIGGER$ T-DUMP",
        "TQ SDSP-OPERANDS$ TOU @ = . TO = . CR",
        "TQ SDSP-R.KEY 32 T-DUMP",
    ])
    assert lines[0] == [D_OK, -1]
    assert bytes(lines[1]) == b"Morning brief"
    assert bytes(lines[2]) == b"daily at 08:00 UTC0"
    assert lines[3] == [-1, 0]
    assert bytes(lines[4]) == dispatch_key(b"\x01" * 32, b"\x02" * 32, 5)


@pytest.mark.parametrize("edit", [
    "1 TQ SDSP-R.SIZE +!",
    "SACT-REMINDER TQ SDSP-R.ACTION !",
    "TQ SDSP-R.STORE 32 0 FILL",
    "TQ SDSP-R.SCHEDULE 32 0 FILL",
    "0 TQ SDSP-R.REVISION !",
    "TQ SDSP-R.PRACTICE 32 0 FILL",
    "0 TQ SDSP-R.KIND !",
    "4 TQ SDSP-R.KIND !",
    "0 TQ SDSP-R.OCCURRENCE !",
    "6 TQ SDSP-R.OCCURRENCE !",
    "1 TQ SDSP-R.KEY C!",
    "1 TQ SDSP-R.OPERANDS-DIGEST C!",
    "0 TQ SDSP-TITLE$ DROP C!",
    "9 TQ SDSP-TRIGGER$ DROP C!",
    "0 TQ SDSP-OPERANDS$ DROP SACT-O.TIME !",
    "8 TQ SDSP-R.TAIL-U +! 8 TQ SDSP-R.SIZE +!",
])
def test_requests_are_refused(forth, edit):
    lines = run(forth, [f"T-DRAFT T-ENC DROP T-REQUEST {edit} T-QOK . CR"])
    assert lines == [[D_INVALID]]


def test_a_request_without_an_occurrence(forth):
    lines = run(forth, [
        "T-DRAFT T-ENC DROP T-REQUEST",
        "0 TQ SDSP-R.KIND ! 0 TQ SDSP-R.OCCURRENCE ! TQ SDSP-R.KEY 32 0 FILL",
        "TQ 0 SDSP-REQUEST-OK? . TQ -1 SDSP-REQUEST-OK? . CR",
        "TQ SDSP-R.PRACTICE 32 0 FILL TQ 0 SDSP-REQUEST-OK? . CR",
        "1 TQ SDSP-R.KIND ! TQ 0 SDSP-REQUEST-OK? . CR",
        "0 TQ SDSP-R.KIND ! 1 TQ SDSP-R.KEY C! TQ 0 SDSP-REQUEST-OK? . CR",
    ])
    assert lines == [[D_OK, D_INVALID], [D_OK], [D_INVALID], [D_INVALID]]


def test_responses(forth):
    lines = run(forth, [
        "TP 1024 255 FILL 16 TP SDSP-RESPONSE-INIT",
        "TP SDSP-P.OUTCOME @ . TP SDSP-P.CAPACITY @ . TP SDSP-RESPONSE-HEAD 16 + + C@ . CR",
        "S\" completed in 3 s\" TP SDSP-SUMMARY! . TP SDSP-SUMMARY$ T-DUMP",
        "S\" a summary longer than room\" TP SDSP-SUMMARY! . TP SDSP-P.SUMMARY-U @ . CR",
        "TP SDSP-SUMMARY$ NIP . CR",
    ])
    assert lines[0] == [0, 16, 255]
    assert lines[1][0] == D_OK and bytes(lines[1][1:]) == b"completed in 3 s"
    assert lines[2] == [D_SMALL, 26]
    assert lines[3] == [26]


def test_a_client_without_words_is_unavailable(forth):
    lines = run(forth, [
        "TQ TP 0 SDSP-SUBMIT . TQ TP 0 SDSP-STATUS . TQ 0 SDSP-CANCEL . CR",
        "TQ 0 SDSP-ASK . . 1 TP 0 SDSP-ASKED . TQ 0 SDSP-CHECK . . CR",
        "TL 64 0 SDSP-MODELS . . CR",
        "77 TC SDSP-CLIENT-INIT TC SDSP-CLIENT-VALID? . TQ TP TC SDSP-SUBMIT . CR",
        "TC 8 + 0 SWAP ! TC SDSP-CLIENT-VALID? . TQ TP TC SDSP-SUBMIT . CR",
    ])
    assert lines == [
        [D_UNAVAILABLE] * 3,
        [D_UNAVAILABLE, 0, D_UNAVAILABLE, D_UNAVAILABLE, A_UNAVAILABLE],
        [D_UNAVAILABLE, 0],
        [-1, D_UNAVAILABLE],
        [0, D_UNAVAILABLE],
    ]


def test_a_client_passes_its_context(forth):
    lines = run(forth, [
        "77 TC SDSP-CLIENT-INIT",
        "' F-SUBMIT TC SDSP-C.SUBMIT-XT ! ' F-STATUS TC SDSP-C.STATUS-XT !",
        "' F-CANCEL TC SDSP-C.CANCEL-XT ! ' F-ASK TC SDSP-C.ASK-XT !",
        "' F-ASKED TC SDSP-C.ASKED-XT ! ' F-CHECK TC SDSP-C.CHECK-XT !",
        "' F-MODELS TC SDSP-C.MODELS-XT !",
        "11 12 TC SDSP-SUBMIT . CR",
        "21 22 TC SDSP-STATUS . CR",
        "31 TC SDSP-CANCEL . CR",
        "41 TC SDSP-ASK . . CR",
        "51 52 TC SDSP-ASKED . CR",
        "61 TC SDSP-CHECK . . CR",
        "71 72 TC SDSP-MODELS . . CR",
        # A filled client whose header is damaged calls nothing.
        "TC 8 + 0 SWAP ! 11 12 TC SDSP-SUBMIT . 31 TC SDSP-CANCEL . CR",
        "TC 8 + TC SWAP ! 0 TC ! 11 12 TC SDSP-SUBMIT . CR",
    ])
    assert lines == [
        [77, 12, 11], [D_STARTED],
        [77, 22, 21], [D_RUNNING],
        [77, 31], [D_OK],
        [77, 41], [D_PENDING, 42],
        [77, 52, 51], [D_ALLOWED],
        [77, 61], [D_OK, 1],
        [77, 72, 71], [D_OK, 64],
        [D_UNAVAILABLE, D_UNAVAILABLE],
        [D_UNAVAILABLE],
    ]


def test_a_model_list_is_read_inside_its_bytes(forth):
    lines = run(forth, [
        "T-LIST TL TLU @ SDSP-LIST-OK? . TL SDSP-LIST-COUNT . CR",
        "TL SDSP-LIST-PROVIDER$ T-DUMP",
        "TL SDSP-LIST-FIRST DUP SDSP-MODEL-ID$ T-DUMP DUP SDSP-MODEL-FLAGS .",
        "DUP SDSP-MODEL-EFFORTS SWAP . SDSP-CHOICE-NEXT SDSP-CHOICE-LABEL$ T-DUMP",
        "DUP SDSP-MODEL-TIERS DROP . SDSP-MODEL-NEXT DUP SDSP-MODEL-LABEL$ T-DUMP",
        "SDSP-MODEL-TIERS SWAP . SDSP-CHOICE-ID$ T-DUMP",
        "TL TLU @ 1- SDSP-LIST-OK? . TL TLU @ 8 + SDSP-LIST-OK? . CR",
        "3 TL ! TL TLU @ SDSP-LIST-OK? . 2 TL ! CR",
        "0 TL SDSP-LIST-FIRST ! TL TLU @ SDSP-LIST-OK? . CR",
        "TL 4096 0 FILL 0 TL SDSP-PUT S\" p\" ROT SACT-STR! TL - TL SWAP SDSP-LIST-OK? . CR",
    ])
    assert lines[0] == [-1, 2]
    assert bytes(lines[1]) == b"org.akashic.agent.codex"
    assert bytes(lines[2]) == b"gpt-a"
    assert lines[3][0] == 1 and lines[3][1] == 2 and bytes(lines[3][2:]) == b"High"
    assert lines[4][0] == 0 and bytes(lines[4][1:]) == b"Model B"
    assert lines[5][0] == 1 and bytes(lines[5][1:]) == b"flex"
    assert lines[6:] == [[0, 0], [0], [0], [-1]]


def said(forth, line: str) -> str:
    output = forth.run([line + " CR"], 50_000_000).decode("latin-1")
    assert "??" not in output, output
    return output.strip()


def test_saying_what_a_run_names(forth):
    # A model with every option, then one with none: no effort, no tier and
    # the model's default verbosity.
    assert said(forth, 'T-DRAFT S" flex" TD SACT-D.TIER SACT-D! 3 TD SACT-D.VERBOSITY ! '
                       "T-ENC DROP TO ' T-SAY 0 SACT-SAY-MODEL") == (
        "gpt-test, high effort, flex tier, high verbosity")
    assert said(forth, "T-DRAFT 0 0 TD SACT-D.EFFORT SACT-D! 0 TD SACT-D.VERBOSITY ! "
                       "T-ENC DROP TO ' T-SAY 0 SACT-SAY-MODEL") == "gpt-test"
    assert said(forth, "T-DRAFT 1 TD SACT-D.VERBOSITY ! "
                       "T-ENC DROP TO ' T-SAY 0 SACT-SAY-MODEL") == (
        "gpt-test, high effort, low verbosity")
    assert said(forth, "T-DRAFT T-ENC DROP TO ' T-SAY 0 SACT-SAY-MODEL") == (
        "gpt-test, high effort, medium verbosity")
    # Time in whole minutes, whole seconds, or milliseconds.
    for ms, words in ((300_000, "5 min"), (90_000, "90 s"), (1500, "1500 ms"),
                      (0, "0 ms")):
        assert said(forth, f"{ms} 4096 16384 ' T-SAY 0 SACT-SAY-LIMITS") == (
            f"{words} to run, 4096 bytes to disclose, 16384 bytes of reply")
    # Each part reaches the appender with its context.
    assert said(forth, "0 T-SAID ! T-DRAFT T-ENC DROP TO ' T-COUNT T-SAID SACT-SAY-MODEL "
                       "T-SAID @ .") == str(len("gpt-test, high effort, medium verbosity"))
    assert said(forth, "0 T-SAID ! 300000 4096 16384 ' T-COUNT T-SAID SACT-SAY-LIMITS "
                       "T-SAID @ .") == str(len(
                           "5 min to run, 4096 bytes to disclose, 16384 bytes of reply"))
