#!/usr/bin/env python3
"""tui/applets/desk/schedule-agent.f: the Agent as the broker's handler.

The suite joins Desk's real broker to the Agent's real dispatcher, as
Desk joins them, over the dispatch suite's runtime, scripted provider and
catalog, with the permissions and the run store on one RAM filesystem.
Approvals are asked and answered through the broker's dispatch client,
as Daybook's service asks them, and runs are handed over the same way:
a run approved, started and followed to its end; the model list the
Agent gives; why the Agent could not run a schedule asked to be
approved; a run that waits behind chat and goes next; runs revoked or
cut short as the broker closes; and a run that names a document, which
the broker attaches through the stand-in owner of doc_owner_fixture.py
for the run's start alone, as Desk attaches one through its owners.
"""

from __future__ import annotations

import struct

import pytest

from doc_owner_fixture import DOC_BUS, DOC_DOCUMENT
from native_forth import NativeForth
from test_agent_dispatch import PRELUDE as DISPATCH_PRELUDE
from test_agent_dispatch import REFUSALS, REPLY


# Dispatch statuses.
(S_OK, S_INVALID, S_UNAVAILABLE, S_STARTED, S_WAITING, S_ENDED, S_RUNNING,
 S_UNKNOWN, S_PENDING, S_ALLOWED, S_REFUSED, S_GONE, S_SMALL) = range(13)
# Outcomes and reasons.
COMPLETED, FAILED, CANCELLED = 1, 2, 3
R_NONE, R_REVOKED, R_AGENT_UNAVAILABLE, R_MODEL_UNAVAILABLE = 0, 2, 5, 6
R_TOO_LARGE, R_INVALID, R_SHUTDOWN = 7, 9, 15
R_CONTEXT_UNAVAILABLE, R_CONTEXT_STALE = 11, 18
STOPPED, BLOCKED = 5, 6
ACCEPTED, ENDED = 1, 2

PRELUDE = DISPATCH_PRELUDE + r"""
CREATE B-RAW SBRK-SIZE 7 + ALLOT  B-RAW 7 + -8 AND CONSTANT B
CREATE H-RAW SBRK-HANDLER-SIZE 7 + ALLOT  H-RAW 7 + -8 AND CONSTANT H
CREATE PS-RAW SPERM-SIZE 7 + ALLOT  PS-RAW 7 + -8 AND CONSTANT PS
: P-PATH  ( -- a u ) S" /schedule-perms.bin" ;
\ No permission file, and nothing left of a replacement.
: P-WIPE  ( -- )
    PS SPERM-SIZE 0 FILL TV @ P-PATH PS SPERM-INIT DROP
    P-PATH T-RM
    PS _SPERM.REPL VREPL-STAGE$ T-RM
    PS _SPERM.REPL VREPL-BACKUP$ T-RM
    PS _SPERM.REPL VREPL-MARKER$ T-RM
    PS SPERM-SIZE 0 FILL ;
: BC  ( -- client ) B SBRK-CLIENT ;
\ Desk's broker over no permission file, its handler the Agent's fresh
\ dispatcher, and the wall clock set.
: BK-FRESH  ( -- )
    B SBRK-VALID? IF B SBRK-FINI THEN
    FRESH P-WIPE T-NOW EPOCH-SET
    TV @ HD ROOT @ B SBRK-INIT DROP
    DS H DSAG-HANDLER-INIT H B SBRK-HANDLER! ;
\ A pump of Desk's loop: the runtime, the dispatcher, then the broker.
: TICK  ( -- ) STEP B SBRK-TICK ;
: TICKS  ( n -- ) 0 ?DO TICK LOOP ;
\ RQ asks for approval of schedule bytes S: it names no occurrence.
: R-ASK  ( s -- )
    1 R-OCC 0 RQ SDSP-R.KIND ! 0 RQ SDSP-R.OCCURRENCE ! RQ SDSP-R.KEY 32 0 FILL ;
VARIABLE ASK-ID  CREATE PERM 32 ALLOT  VARIABLE PREV
\ Asks for approval of schedule S and allows it: PERM and PREV are the
\ permission granted.
: APPROVE  ( s -- )
    R-ASK RQ BC SDSP-ASK DROP ASK-ID !
    ASK-ID @ -1 T-NOW B SBRK-ANSWER DROP
    RS0 ASK-ID @ RS BC SDSP-ASKED DROP
    RS SDSP-P.PERMISSION PERM RID-COPY RS SDSP-P.PERMISSION-REVISION @ PREV ! ;
\ Hands over occurrence N of schedule S under PERM, as Daybook does.
: HAND  ( s n -- status )
    R-OCC PERM RQ SDSP-R.PERMISSION RID-COPY PREV @ RQ SDSP-R.PERMISSION-REVISION !
    RS0 RQ RS BC SDSP-SUBMIT ;
: STAND  ( key -- status ) RS0 RS BC SDSP-STATUS ;
\ Whether the response names PERM.
: PERM?  ( -- flag ) RS SDSP-P.PERMISSION PERM RID= ;
\ A model list, field by field.
: STR.  ( a u -- ) TYPE ." |" ;
: CHOICES.  ( n choice -- choice' )
    SWAP 0 ?DO DUP SDSP-CHOICE-ID$ STR. DUP SDSP-CHOICE-LABEL$ STR. SDSP-CHOICE-NEXT LOOP ;
: MODEL.  ( model -- )
    DUP SDSP-MODEL-ID$ STR. DUP SDSP-MODEL-LABEL$ STR. DUP SDSP-MODEL-FLAGS .
    DUP SDSP-MODEL-EFFORTS OVER . CHOICES. DROP
    SDSP-MODEL-TIERS OVER . CHOICES. DROP ;
: LIST.  ( list -- )
    DUP SDSP-LIST-COUNT . DUP SDSP-LIST-PROVIDER$ STR. CR
    DUP SDSP-LIST-COUNT SWAP SDSP-LIST-FIRST
    SWAP 0 ?DO DUP MODEL. CR SDSP-MODEL-NEXT LOOP DROP ;
: BYTES.  ( a u -- ) 0 ?DO DUP I + C@ . LOOP DROP ;
\ The first bytes of memory, kept, and whether they are as kept: a list
\ measured, not written, leaves them alone.
CREATE LOW-SAVE 512 ALLOT
: LOW-KEEP  ( -- ) 0 LOW-SAVE 512 MOVE ;
: LOW-SAME?  ( -- flag ) 0 512 LOW-SAVE 512 COMPARE 0= ;
\ The Practice's root Context, active, with a request bus and the owner
\ of one document.
ROOT @ CTX.FLAGS DUP @ CTX-F-ACTIVE OR SWAP !
""" + DOC_BUS + DOC_DOCUMENT + r"""
\ Desk's owners, as the broker sees them: the stand-in's root attaches
\ every locator.
: OWNERS  ( locator binding result context -- status )
    DROP >R >R DOC-ROOT ROOT @ RRG R> R> RACQ-ATTACH ;
: D-FRESH  ( -- ) BK-FRESH ['] OWNERS 0 B SBRK-OWNERS! 0 DOC-REFUSE ! 0 DOC-STUCK ! ;
\ Operands that name the version of the document DOC! set, and may
\ disclose the prompt and it.
: DOC-OPS!  ( prompt-a prompt-u -- )
    2DUP OPS! DOC-LOC AD SACT-D.CONTEXT ! CAP-E-OBSERVE AD SACT-D.EFFECTS !
    NIP DOC-U @ + AD SACT-D.DISCLOSURE ! OPS-AGAIN ;
: NOTES$  ( -- a u ) S" The quarterly report." ;
: OTHER$  ( -- a u ) S" The quarterly report, revised." ;
\ The text of message I of RUN's transcript.
: SAID  ( i run -- ) DECODE DROP DUP >R ACONV-NTH AMSG-TEXT TYPE R> ACONV-FREE ;
\ A provider with ROOM bytes for a turn's input, whose text takes twice
\ its bytes there: a reference not yet read counts at its bytes alone.
VARIABLE ROOM
: ESCAPING  ( prompt-a prompt-u reference-a reference-u context -- used capacity )
    DROP SWAP IF 2* THEN + NIP ROOM @ ;
"""

SUITE = NativeForth(("tui/applets/desk/schedule-agent.f",
                     "tui/applets/agent/providers/devtools/device-flow.f"),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 4_000_000_000) -> list[str]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line for line in output.replace("\r", "").split("\n") if line.strip()]


def ints(line: str) -> list[int]:
    return [int(token) for token in line.split()]


def _text(value: str) -> bytes:
    data = value.encode()
    return struct.pack("<q", len(data)) + data + bytes(-len(data) % 8)


def _list(provider: str, models: list[tuple]) -> bytes:
    out = struct.pack("<q", len(models)) + _text(provider)
    for model, label, flags, efforts, tiers in models:
        out += _text(model) + _text(label) + struct.pack("<q", flags)
        for choices in (efforts, tiers):
            out += struct.pack("<q", len(choices))
            for choice, choice_label in choices:
                out += _text(choice) + _text(choice_label)
    return out


DEVICE_FLOW = "org.akashic.agent.testing.device-flow"
MODELS = _list(DEVICE_FLOW, [
    ("gpt-fast", "Swift", 1, [("low", "Low"), ("medium", "Medium")], []),
    ("gpt-slow", "Deliberate", 1, [("low", "Low"), ("high", "High")],
     [("priority", "Fast")]),
])


def test_an_approved_schedule_runs_through_the_broker(forth):
    rows = run(forth, [
        # Asked, it can run; allowed, it is granted.
        "BK-FRESH 1 R-ASK RQ BC SDSP-ASK . ASK-ID ! B SBRK-ASKING NIP B SBRK-VET . "
        "ASK-ID @ -1 T-NOW B SBRK-ANSWER . RS0 ASK-ID @ RS BC SDSP-ASKED . "
        "RS SDSP-P.PERMISSION RID-ZERO? . CR",
        "RS SDSP-P.PERMISSION PERM RID-COPY RS SDSP-P.PERMISSION-REVISION @ PREV ! "
        "1 1 HAND . KEEP1 PERM? . DS ADISP-BUSY? . B SBRK-ACTIVE? . HELD? . CR",
        "8 TICKS KEY1 STAND . ANS. PERM? . SUM. CR",
        # Daybook heard its end; the Agent still has it.
        "B SBRK-ACTIVE? . DS ADISP-BUSY? . HELD? . RUNS . R0 ADST-R.PHASE @ . "
        "R0 ADST-R.PERMISSION PERM RID= . KEY1 STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [S_PENDING, 0, 0, S_ALLOWED, 0]
    assert ints(rows[1]) == [S_STARTED, -1, -1, -1, -1]
    assert rows[2].split()[:4] == [str(S_ENDED), str(COMPLETED), str(R_NONE), "-1"]
    assert rows[2].split()[4:6] == ["completed;", str(len(REPLY.encode()))]
    assert ints(rows[3]) == [0, 0, 0, 1, ENDED, -1, S_ENDED, COMPLETED, R_NONE]


def test_the_models_the_agent_lists(forth):
    rows = run(forth, [
        # Written over bytes that are not zero, the padding is zeroed; only
        # the list is written.
        f"BK-FRESH TBUF 4096 255 FILL LOW-KEEP TBUF 4096 BC SDSP-MODELS . . "
        f"LOW-SAME? . TBUF {len(MODELS)} SDSP-LIST-OK? . TBUF {len(MODELS)} + C@ . CR",
        "TBUF LIST.",
        f"TBUF {len(MODELS)} BYTES. CR",
        # Room for it exactly; one byte short, the list is not written and
        # says what it needs.
        f"TBUF {len(MODELS)} BC SDSP-MODELS . . "
        f"TBUF 4096 0 FILL TBUF {len(MODELS) - 1} BC SDSP-MODELS . . TBUF C@ . CR",
        # A catalog still loading, and a provider with none, list nothing.
        "ARSET-STATE-LOADING ST ARSET.STATE ! TBUF 4096 BC SDSP-MODELS . . "
        "ARSET-STATE-READY ST ARSET.STATE ! "
        "0 PRV @ APROV.RUN-SETTINGS ! TBUF 4096 BC SDSP-MODELS . . "
        "ST PRV @ APROV.RUN-SETTINGS ! CR",
        # A model that takes no verbosity.
        "M0 ARMODEL.FLAGS @ DUP ARMODEL-F-VERBOSITY INVERT AND M0 ARMODEL.FLAGS ! "
        "TBUF 4096 BC SDSP-MODELS 2DROP M0 ARMODEL.FLAGS ! TBUF SDSP-LIST-FIRST MODEL. CR",
        # A dispatcher damaged, and none.
        "DS _ADISP.MAGIC @ 0 DS _ADISP.MAGIC ! TBUF 4096 BC SDSP-MODELS . . "
        "DS _ADISP.MAGIC ! DS ADISP-FINI TBUF 4096 BC SDSP-MODELS . . CR",
    ])
    assert ints(rows[0]) == [S_OK, len(MODELS), -1, -1, 255]
    assert rows[1] == f"2 {DEVICE_FLOW}|"
    assert rows[2] == "gpt-fast|Swift|1 2 low|Low|medium|Medium|0 "
    assert rows[3] == "gpt-slow|Deliberate|1 2 low|Low|high|High|1 priority|Fast|"
    assert bytes(ints(rows[4])) == MODELS
    assert ints(rows[5]) == [S_OK, len(MODELS), S_SMALL, len(MODELS), 0]
    assert ints(rows[6]) == [S_UNAVAILABLE, 0, S_UNAVAILABLE, 0]
    assert rows[7] == "gpt-fast|Swift|0 2 low|Low|medium|Medium|0 "
    assert ints(rows[8]) == [S_UNAVAILABLE, 0, S_UNAVAILABLE, 0]


# What a schedule asked to be approved could not run for: the dispatch
# suite's refusals of the Agent itself, and none for its authority, which
# an approval does not have yet.
VETS = {name: (setup, undo, reason) for name, (setup, go, undo, reason) in REFUSALS.items()
        if go == "GO" and reason != R_INVALID}


def test_why_a_schedule_could_not_run(forth):
    lines = [f"BK-FRESH {setup} 1 R-ASK RQ B SBRK-VET . {undo} CR"
             for setup, undo, _ in VETS.values()]
    lines += [
        "BK-FRESH 1 R-ASK RQ B SBRK-VET . CR",
        # A provider with room for ten bytes takes ten, and not eleven.
        "BK-FRESH ' TINY-ROOM PRV @ APROV.INPUT-XT ! "
        'S" 0123456789" OPS! 1 R-ASK RQ B SBRK-VET . '
        'S" 0123456789A" OPS! 1 R-ASK RQ B SBRK-VET . 0 PRV @ APROV.INPUT-XT ! CR',
        # A hand-over is not an approval; an Agent gone or never there
        # cannot say.
        "BK-FRESH 1 1 R-OCC RQ B SBRK-VET . 1 R-ASK DS ADISP-FINI RQ B SBRK-VET . "
        "BK-FRESH 0 B SBRK-HANDLER! RQ B SBRK-VET . RQ 0 SBRK-VET . CR",
    ]
    rows = run(forth, lines)
    for (name, (_, _, reason)), row in zip(VETS.items(), rows):
        assert ints(row) == [reason], name
    assert len(VETS) >= 7
    assert ints(rows[len(VETS)]) == [0]
    assert ints(rows[len(VETS) + 1]) == [0, R_TOO_LARGE]
    assert ints(rows[len(VETS) + 2]) == [R_INVALID, R_AGENT_UNAVAILABLE,
                                         R_AGENT_UNAVAILABLE, R_AGENT_UNAVAILABLE]


def test_asking_does_not_touch_a_run(forth):
    rows = run(forth, [
        # A run on gpt-slow lingers; a schedule on gpt-fast is asked about.
        "BK-FRESH LINGER$ OPS! 2 APPROVE 2 1 HAND . KEEP1 3 TICKS "
        "FAST$ AD SACT-D.MODEL SACT-D! LOW$ AD SACT-D.EFFORT SACT-D! "
        "0 0 AD SACT-D.TIER SACT-D! OPS-AGAIN 3 R-ASK RQ B SBRK-VET . "
        "KEY1 STAND . DS ADISP-IDLE? . CR",
        # The provider ran nothing since the run started, which ends as
        # the user asks.
        "LAST. CR",
        "KEY1 SACT-R-USER DS ADISP-CANCEL . 3 TICKS KEY1 STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [S_STARTED, 0, S_RUNNING, 0]
    assert rows[1].split() == ["1", "high", "priority", "0"]
    assert ints(rows[2]) == [S_OK, S_ENDED, CANCELLED, 14]


def test_a_run_waits_for_chat_and_goes_next(forth):
    rows = run(forth, [
        "BK-FRESH 1 APPROVE LINGER$ RT @ ARUNTIME-SEND DROP 3 TICKS "
        "1 1 HAND . KEEP1 B SBRK-ACTIVE? . KEY1 STAND . HELD? . RUNS . CR",
        # Chat ends; the next tick starts the run, which completes.
        "RT @ ARUNTIME-CANCEL DROP 3 TICKS KEY1 STAND . RUNS . 8 TICKS KEY1 STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [S_WAITING, -1, S_WAITING, -1, 0]
    assert ints(rows[1]) == [S_RUNNING, 1, S_ENDED, COMPLETED, R_NONE]


def test_revoking_stops_a_run(forth):
    rows = run(forth, [
        "BK-FRESH LINGER$ OPS! 1 APPROVE 1 1 HAND . KEEP1 3 TICKS KEY1 STAND . "
        "PERM B SBRK-REVOKE . 3 TICKS KEY1 STAND . ANS. PERM? . CR",
        # The Agent's record says the same.
        "R0 ADST-R.OUTCOME @ . R0 ADST-R.REASON @ . DS ADISP-BUSY? . HELD? . CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_RUNNING, 0, S_ENDED, CANCELLED, R_REVOKED, -1]
    assert ints(rows[1]) == [CANCELLED, R_REVOKED, 0, 0]


def test_closing_the_broker_cancels_runs_in_flight(forth):
    rows = run(forth, [
        # One run lingers and one waits behind it.
        "BK-FRESH LINGER$ OPS! 1 APPROVE 1 1 HAND . KEEP1 3 TICKS "
        "1 2 HAND . KEEP2 B SBRK-ACTIVE? . DS ADISP-BUSY? . CR",
        "B SBRK-FINI B SBRK-VALID? . DS ADISP-BUSY? . HELD? . RUNS . "
        "R0 ADST-R.OUTCOME @ . R0 ADST-R.REASON @ . CR",
        # A broker opened again asks the Agent about runs it does not know.
        "TV @ HD ROOT @ B SBRK-INIT . H B SBRK-HANDLER! KEY1 STAND . ANS. "
        "KEY2 STAND . CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_WAITING, -1, -1]
    assert ints(rows[1]) == [0, 0, 0, 1, CANCELLED, R_SHUTDOWN]
    assert ints(rows[2]) == [0, S_ENDED, CANCELLED, R_SHUTDOWN, S_UNKNOWN]


def test_the_handler_is_the_dispatchers(forth):
    rows = run(forth, [
        "DS H DSAG-HANDLER-INIT H SBRK-H.START-XT @ ' ADISP-START = . "
        "H SBRK-H.STATUS-XT @ ' ADISP-STATUS = . H SBRK-H.CANCEL-XT @ ' ADISP-CANCEL = . "
        "H SBRK-H.MODELS-XT @ ' ADISP-MODELS = . H SBRK-H.IDLE-XT @ ' ADISP-IDLE? = . "
        "H SBRK-H.VET-XT @ ' ADISP-VET = . H _SBRK-HANDLER? . H _SBH-CONTEXT + @ DS = . CR",
    ])
    assert ints(rows[0]) == [-1] * 8


def test_a_run_reads_its_document_while_it_starts(forth):
    import hashlib
    notes = b"The quarterly report."
    digest = hashlib.sha3_256(notes).hexdigest()
    rows = run(forth, [
        # The run reads revision 3 as itself while it starts; the owner has
        # the document back once START answers.
        "D-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! 1 APPROVE "
        "0 DOC-DESCRIBES ! 0 DOC-SNAPSHOTS ! 1 1 HAND . KEEP1 DOC-HELD @ . "
        "PRV @ SCRIPTED-LAST-REFERENCE DROP . DOC-DESCRIBES @ . DOC-SNAPSHOTS @ . "
        "DOC-PRINCIPAL @ CPRINC-AGENT = . CR",
        "8 TICKS KEY1 STAND . ANS. CR",
        # The transcript says which version was read, never its text; the
        # model was given the text as a reference.
        "0 R0 SAID CR",
        "2 R0 SAID CR",
    ])
    assert ints(rows[0]) == [S_STARTED, 0, len(notes), 1, 1, -1]
    assert ints(rows[1]) == [S_ENDED, COMPLETED, R_NONE]
    assert rows[2] == f"Read the document: Field notes (revision 3, {len(notes)} bytes)"
    assert f"With a reference of {len(notes)} bytes, SHA3 {digest[:8]}." in rows[3]
    assert "quarterly" not in rows[2] + rows[3]


def test_a_changed_document_stops_the_run_for_review(forth):
    rows = run(forth, [
        # Approved at revision 3, the document is at revision 4 when the run
        # is due: it is described, not read, and the run stops for review.
        "D-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! 1 APPROVE OTHER$ 4 DOC! "
        "0 DOC-SNAPSHOTS ! 1 1 HAND . ANS. DOC-SNAPSHOTS @ . DOC-HELD @ . RUNS . "
        "R0 ADST-R.PHASE @ . CR",
        # The owner kept no version that old: the broker stops it as it
        # attaches.
        "D-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! 1 APPROVE RACQ-S-GONE DOC-REFUSE ! "
        "1 1 HAND . ANS. DOC-HELD @ . RUNS . 0 DOC-REFUSE ! CR",
    ])
    assert ints(rows[0]) == [S_ENDED, STOPPED, R_CONTEXT_STALE, 0, 0, 1, ENDED]
    assert ints(rows[1]) == [S_ENDED, STOPPED, R_CONTEXT_STALE, 0, 0]


def test_a_document_that_cannot_be_attached_blocks_the_run(forth):
    rows = run(forth, [
        # Its owner does not have it; and Desk has set no owners.
        "D-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! 1 APPROVE RACQ-S-NOT-FOUND DOC-REFUSE ! "
        "1 1 HAND . ANS. RUNS . 0 DOC-REFUSE ! CR",
        "BK-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! 1 APPROVE 1 1 HAND . ANS. RUNS . DOC-HELD @ . CR",
    ])
    assert ints(rows[0]) == [S_ENDED, BLOCKED, R_CONTEXT_UNAVAILABLE, 0]
    assert ints(rows[1]) == [S_ENDED, BLOCKED, R_CONTEXT_UNAVAILABLE, 0, 0]


def test_a_document_its_owner_will_not_release_yet(forth):
    rows = run(forth, [
        # The owner refuses the release once: the broker asks again on its
        # next tick, and the run goes on meanwhile.
        "D-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! 1 APPROVE 1 DOC-STUCK ! "
        "1 1 HAND . KEEP1 DOC-HELD @ . B SBRK-TICK DOC-HELD @ . "
        "8 TICKS KEY1 STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [S_STARTED, 1, 0, S_ENDED, COMPLETED, R_NONE]


def test_a_document_too_large_for_the_model_once_read(forth):
    rows = run(forth, [
        # By its size, the prompt and the document fit; read, they do not.
        # The run is recorded, read, and blocked before the provider starts.
        "D-FRESH NOTES$ 3 DOC! NEWS$ DOC-OPS! NEWS$ NIP NOTES$ NIP + ROOM ! "
        "' ESCAPING PRV @ APROV.INPUT-XT ! 1 APPROVE 1 1 HAND . ANS. RUNS . "
        "R0 ADST-R.OUTCOME @ . R0 ADST-R.REASON @ . DOC-HELD @ . "
        "0 PRV @ APROV.INPUT-XT ! CR",
    ])
    assert ints(rows[0]) == [S_ENDED, BLOCKED, R_TOO_LARGE, 1, BLOCKED, R_TOO_LARGE, 0]


def test_what_a_documents_owner_says_of_it(forth):
    rows = run(forth, [
        # Desk asks for itself, and the owner has the document back at once.
        "D-FRESH NOTES$ 3 DOC! CREATE TT 64 ALLOT CREATE FF SDSP-FACTS-SIZE ALLOT "
        "TT 64 FF SDSP-FACTS-INIT DOC-LOC FF BC SDSP-DESCRIBE . FF SDSP-F.REVISION @ . "
        "FF SDSP-F.SIZE @ . DOC-HELD @ . DOC-PRINCIPAL @ CPRINC-SYSTEM = . "
        "FF SDSP-FACTS-TITLE$ TYPE CR",
        # A title longer than the buffer says how long it is; an owner
        # without the document, and no owners at all, cannot say.
        "TT 4 FF SDSP-FACTS-INIT DOC-LOC FF BC SDSP-DESCRIBE . FF SDSP-F.TITLE-U @ . "
        "RACQ-S-NOT-FOUND DOC-REFUSE ! DOC-LOC FF BC SDSP-DESCRIBE . 0 DOC-REFUSE ! "
        "BK-FRESH DOC-LOC FF BC SDSP-DESCRIBE . DOC-HELD @ . "
        "TT 64 FF SDSP-FACTS-INIT 0 FF BC SDSP-DESCRIBE . CR",
    ])
    assert rows[0] == f"{S_OK} 3 21 0 -1 Field notes"
    assert ints(rows[1]) == [S_SMALL, len("Field notes"), S_UNAVAILABLE, S_UNAVAILABLE, 0,
                             S_INVALID]
