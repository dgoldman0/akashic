#!/usr/bin/env python3
"""tui/applets/agent/dispatch.f: the Agent's scheduled runs.

The suite runs a real runtime over the device-flow source's scripted
provider and catalog (gpt-fast, efforts low and medium; gpt-slow, efforts
low and high and the priority tier), with the run store on a RAM
filesystem and authority compiled as Desk's broker compiles it.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_daybook_automation_owner import NOW
from test_daybook_automation_store import RAM_VFS


BASE = 1 << 48


# Dispatch statuses.
(S_OK, S_INVALID, S_UNAVAILABLE, S_STARTED, S_WAITING, S_ENDED, S_RUNNING,
 S_UNKNOWN, S_PENDING, S_ALLOWED, S_REFUSED, S_GONE, S_SMALL) = range(13)
# Outcomes and reasons.
(COMPLETED, FAILED, CANCELLED, EXPIRED, STOPPED, BLOCKED, INDETERMINATE,
 NOT_STARTED) = range(1, 9)
R_NONE, R_REVOKED = 0, 2
R_AGENT_UNAVAILABLE, R_MODEL_UNAVAILABLE, R_TOO_LARGE = 5, 6, 7
R_INVALID, R_USER, R_SHUTDOWN, R_TOOL, R_APPROVAL = 9, 14, 15, 16, 17
R_TIME, R_OUTPUT, R_PROVIDER_START = 19, 20, 23
R_INTERRUPTED, R_KEY_CONFLICT = 26, 29
# Runtime statuses and the held refusal.
IDLE, RUNNING, APPROVAL, OFFLINE = 0, 1, 2, 3
HELD = 5
ACCEPTED, ENDED = 1, 2

PRELUDE = RAM_VFS + rf"""
{NOW} CONSTANT T-NOW
\ Sets the wall clock: the eight RTC bytes, low byte first.
: EPOCH-SET  ( ms -- ) 8 0 DO DUP 255 AND 0xFFFFFF0000000B08 I + C! 8 RSHIFT LOOP DROP ;
\ Desk's Practice, bytes 4, and its root Context at epoch 777.
CREATE HD-RAW PHEAD-SIZE 7 + ALLOT  HD-RAW 7 + -8 AND CONSTANT HD
VARIABLE ROOT  VARIABLE CHILD
CREATE MD-RAW MAND-SIZE 7 + ALLOT  MD-RAW 7 + -8 AND CONSTANT MD
CREATE FC-RAW CFACET-SIZE 7 + ALLOT  FC-RAW 7 + -8 AND CONSTANT FC
HD PHEAD-INIT HD PHEAD.ID 32 4 FILL HD PHEAD.CURRENT-ROOT 32 9 FILL
777 CTX-NEW THROW ROOT !  HD ROOT @ CTX.PRACTICE !
VARIABLE A-TIME  VARIABLE A-DISC  VARIABLE AM
\ The authority Desk's broker compiles for a run, as it compiles it: a
\ child Context, a facet with no entries, and a read-only Mandate with
\ A-TIME and A-DISC and no tool budget.  AM is the run.
: AUTHORITY  ( -- )
    ROOT @ CTX-CHILD-NEW THROW DUP CHILD !
    CTX.FLAGS DUP @ CTX-F-ACTIVE OR SWAP !
    FC CFACET-INIT
    FC CFACET.ID 32 21 FILL
    HD PHEAD.ID FC CFACET.PRACTICE-ID RID-COPY
    ROOT @ CTX.EPOCH @ FC CFACET.EPOCH !
    CHILD @ CTX.ID @ FC CFACET.CONTEXT-ID !
    CHILD @ CTX.GENERATION @ FC CFACET.CONTEXT-GEN !
    1 FC CFACET.REVISION !
    MD MAND-INIT
    MD MAND.ID 32 22 FILL
    HD PHEAD.ID MD MAND.PRACTICE-ID RID-COPY
    FC CFACET.ID MD MAND.INPUT-FACET-ID RID-COPY
    FC CFACET.ID MD MAND.DISCLOSURE-FACET-ID RID-COPY
    ROOT @ CTX.EPOCH @ MD MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT MD MAND.PRINCIPAL !
    CHILD @ CTX.ID @ MD MAND.CONTEXT-ID !
    CHILD @ CTX.GENERATION @ MD MAND.CONTEXT-GENERATION !
    MAND-D-READ-ONLY MD MAND.DISPOSITION !
    A-TIME @ MD MAND.TIME-BUDGET-MS !
    A-DISC @ MD MAND.DISCLOSURE-BUDGET !
    HD CHILD @ MD FC AMRUN-NEW THROW AM ! ;
\ Whether the run AM is still its caller's: not closed or freed.
: AM-LIVE?  ( -- flag ) AM @ AMRUN-STRUCTURAL-VALID? ;
\ Gives the caller's run back, as Desk's broker does when a start fails.
: AM-FREE  ( -- ) AM @ ?DUP IF AMRUN-FREE THEN 0 AM ! ;

\ The provider, signed in, its catalog ready with gpt-fast selected, and
\ a runtime connected to it.
VARIABLE SRC  VARIABLE PRV  VARIABLE RT
: ST  ( -- settings ) SRC @ DFSRC.SETTINGS ;
: SIGNED  ( state -- ) SRC @ DFSRC.AUTH AAUTH.STATE ! ;
DEVFLOW-SOURCE-NEW THROW SRC !  SRC @ APSOURCE-PROVIDER-NEW THROW PRV !
AAUTH-STATE-READY SIGNED
ARSET-STATE-READY ST ARSET.STATE !  0 SRC @ _DFS-MODEL-SELECT DROP
PRV @ ARUNTIME-NEW THROW RT !
: PUMP  ( -- ) 16 RT @ ARUNTIME-PUMP DROP ;
RT @ ARUNTIME-RECONNECT DROP PUMP

\ The dispatcher over the RAM filesystem.
CREATE DS-RAW ADISP-SIZE 7 + ALLOT  DS-RAW 7 + -8 AND CONSTANT DS
: D-PATH  ( -- a u ) S" /agent-dispatch.bin" ;
: D-WIPE  ( -- )
    D-PATH T-RM
    DS ADISP-STORE _ADST.REPL VREPL-STAGE$ T-RM
    DS ADISP-STORE _ADST.REPL VREPL-BACKUP$ T-RM
    DS ADISP-STORE _ADST.REPL VREPL-MARKER$ T-RM ;
: STEP  ( -- ) PUMP DS ADISP-PUMP ;
: STEPS  ( n -- ) 0 ?DO STEP LOOP ;
\ Pumps the runtime alone, as if the dispatcher were not looking.
: PUMPS  ( n -- ) 0 ?DO PUMP LOOP ;

\ An Agent run's operands in OPS: five minutes, 4096 bytes disclosed,
\ OUT-U bytes kept, the device-flow provider's gpt-fast at low effort,
\ and the prompt PROMPT names.
CREATE AD-RAW SACT-DRAFT-SIZE 7 + ALLOT  AD-RAW 7 + -8 AND CONSTANT AD
CREATE OPS-RAW 1031 ALLOT  OPS-RAW 7 + -8 AND CONSTANT OPS
VARIABLE OPS-U  VARIABLE OUT-U  16384 OUT-U !
: DEVFLOW$  ( -- a u ) S" org.akashic.agent.testing.device-flow" ;
: SCRIPTED$  ( -- a u ) S" org.akashic.agent.testing.scripted" ;
: FAST$  ( -- a u ) S" gpt-fast" ;      : SLOW$  ( -- a u ) S" gpt-slow" ;
: GONE$  ( -- a u ) S" gpt-gone" ;
: LOW$  ( -- a u ) S" low" ;           : MEDIUM$  ( -- a u ) S" medium" ;
: HIGH$  ( -- a u ) S" high" ;         : PRIORITY$  ( -- a u ) S" priority" ;
: NEWS$  ( -- a u ) S" Summarize the news." ;
: TASK$  ( -- a u ) S" Please handle this task." ;
: APPROVAL$  ( -- a u ) S" Ask for approval first." ;
: LINGER$  ( -- a u ) S" Please linger." ;
\ "Résumé." in UTF-8.
CREATE RESUME-B 82 C, 195 C, 169 C, 115 C, 117 C, 109 C, 195 C, 169 C, 46 C,
: RESUME$  ( -- a u ) RESUME-B 9 ;
\ Operands naming gpt-slow at high effort, priority tier, on PROMPT.
: OPS!  ( prompt-a prompt-u -- )
    AD SACT-DRAFT-INIT
    300000 AD SACT-D.TIME ! 4096 AD SACT-D.DISCLOSURE ! OUT-U @ AD SACT-D.OUTPUT !
    DEVFLOW$ AD SACT-D.PROVIDER SACT-D!
    SLOW$ AD SACT-D.MODEL SACT-D!
    HIGH$ AD SACT-D.EFFORT SACT-D!
    PRIORITY$ AD SACT-D.TIER SACT-D!
    AD SACT-D.PROMPT SACT-D!
    AD OPS 1024 SACT-AGENT-ENCODE DROP OPS-U ! ;
\ Re-encodes the operands after a change to the draft.
: OPS-AGAIN  ( -- ) AD OPS 1024 SACT-AGENT-ENCODE DROP OPS-U ! ;

\ Occurrence N of schedule bytes S in store bytes 3, handed over in RQ in
\ Practice 4 under permission bytes 6 at revision 1.
CREATE RQ-RAW 2063 ALLOT  RQ-RAW 7 + -8 AND CONSTANT RQ
: R-OCC  ( s n -- )
    >R
    S" Read the news" NIP S" daily at 09:00" NIP OPS-U @ SDSP-REQUEST-SIZE
        RQ SDSP-REQUEST-INIT
    SACT-AGENT-RUN RQ SDSP-R.ACTION ! SACT-SCHEMA RQ SDSP-R.SCHEMA !
    RQ SDSP-R.STORE 32 3 FILL RQ SDSP-R.SCHEDULE 32 ROT FILL
    1 RQ SDSP-R.REVISION ! RQ SDSP-R.TRIGGER-DIGEST 32 7 FILL
    S" Read the news" RQ SDSP-TAIL+ S" daily at 09:00" RQ SDSP-TAIL+
    OPS OPS-U @ RQ SDSP-TAIL+
    SACT-AGENT-RUN SACT-SCHEMA OPS OPS-U @ RQ SDSP-R.OPERANDS-DIGEST SACT-DIGEST
    RQ SDSP-R.PRACTICE 32 4 FILL
    SDSP-K-ON-TIME RQ SDSP-R.KIND !
    R> RQ SDSP-R.OCCURRENCE !
    RQ SDSP-R.STORE RQ SDSP-R.SCHEDULE RQ SDSP-R.OCCURRENCE @ RQ SDSP-R.KEY SDSP-KEY
    RQ SDSP-R.PERMISSION 32 6 FILL 1 RQ SDSP-R.PERMISSION-REVISION ! ;
\ RQ's dispatch key, kept: RQ changes.
CREATE KEY1 32 ALLOT  CREATE KEY2 32 ALLOT
: KEEP1  ( -- ) RQ SDSP-R.KEY KEY1 32 MOVE ;
: KEEP2  ( -- ) RQ SDSP-R.KEY KEY2 32 MOVE ;

\ A response with room for a summary.
CREATE RS-RAW 300 ALLOT  RS-RAW 7 + -8 AND CONSTANT RS
: RS0  ( -- ) 128 RS SDSP-RESPONSE-INIT ;
\ The permission, its revision and the Practice the response names.
: WHOSE.  ( -- )
    RS SDSP-P.PERMISSION C@ . RS SDSP-P.PERMISSION-REVISION @ . RS SDSP-P.PRACTICE C@ . ;
\ Starts RQ under AM, or under a fresh authority; the status.
: GO-AM  ( -- status ) RS0 RQ AM @ 0 RS DS ADISP-START ;
: GO  ( -- status ) AUTHORITY GO-AM ;
\ Starts RQ keeping a reference to its authority, so whether the runtime
\ closed it can be seen; GONE drops that reference.
: GO-KEPT  ( -- status ) AUTHORITY AM @ AMRUN-RETAIN DROP GO-AM ;
: GONE  ( -- ) AM @ AMRUN-RELEASE 0 AM ! ;
VARIABLE CV2
\ Starts RQ answering into a response whose RID is not zero.
: GO-DIRTY  ( -- status )
    AUTHORITY RS0 RS SDSP-P.RUN 32 9 FILL RQ AM @ 0 RS DS ADISP-START ;
\ A tool gateway's worth of zeroes: a gateway with nothing to do.
CREATE FAKE-G-RAW AGENT-TOOL-GATEWAY-SIZE 7 + ALLOT
FAKE-G-RAW 7 + -8 AND CONSTANT FAKE-G
FAKE-G AGENT-TOOL-GATEWAY-SIZE 0 FILL
: STAND  ( key -- status ) RS0 RS DS ADISP-STATUS ;
\ The response's outcome and reason, then its summary.
: ANS.  ( -- ) RS SDSP-P.OUTCOME @ . RS SDSP-P.REASON @ . ;
: SUM.  ( -- ) RS SDSP-SUMMARY$ TYPE ;
: RUNS  ( -- n ) DS ADISP-STORE ADST-COUNT@ ;
: R0  ( -- run ) 0 DS ADISP-STORE ADST-NTH ;
: R1  ( -- run ) 1 DS ADISP-STORE ADST-NTH ;
\ Whether the response names RUN.
: NAMES?  ( run -- flag ) ADST-R.RID RS SDSP-P.RUN RID= ;
: CHAT  ( -- n ) RT @ ARUNTIME.CONVERSATION @ ACONV.COUNT @ ;
: HELD?  ( -- flag ) RT @ ARUNTIME.HOLD @ 0<> ;
: STATUS@  ( -- status ) RT @ ARUNTIME.STATUS @ ;
\ The catalog's models, and which a model is: 0, 1, or -1 for none.
: M0  ( -- model ) 0 ST ARSET-MODEL-NTH ;
: M1  ( -- model ) 1 ST ARSET-MODEL-NTH ;
: WHICH  ( model -- n )
    DUP 0= IF DROP -1 EXIT THEN DUP M0 = IF DROP 0 EXIT THEN M1 = IF 1 ELSE -2 THEN ;
: ID.  ( choice -- ) ?DUP IF ARCH-ID TYPE ELSE ." -" THEN SPACE ;
\ The model, effort, tier and verbosity the provider's last turn ran on.
: LAST.  ( -- ) PRV @ SCRIPTED-LAST-RUN >R ROT WHICH . SWAP ID. ID. R> . ;
\ A provider whose room for a turn's input is ten bytes.
: TINY-ROOM  ( prompt-a prompt-u reference-a reference-u context -- used capacity )
    DROP NIP ROT DROP + 10 ;
\ RUN's transcript decoded, and its status.
: DECODE  ( run -- conversation status )
    ADST-TRANSCRIPT$ ATHREAD-DECODE NIP ;
\ Desk stops without closing anything: the run in flight is left so.  A
\ restarted Desk's provider has none of the old run's events.
: CRASH  ( -- )
    DS ADISP-STORE ADST-CLOSE DROP
    ARUN-S-CANCELLED RT @ ARUNTIME-RUN-STOP DROP
    RT @ ARUNTIME-RUN-TAKE 2DROP ACONV-FREE PUMP
    0 RT @ ARUNTIME-HOLD!
    DS _ADISP.WAITING 32 RTAB-FREE
    DS ADISP-SIZE 0 FILL ;

\ A fresh dispatcher over no file, the runtime idle and holding nothing,
\ with no event left over from a test before.
: FRESH  ( -- )
    DS ADISP-VALID? IF DS ADISP-FINI THEN
    4 PUMPS
    ARUN-S-IDLE RT @ ARUNTIME.STATUS !
    DS ADISP-SIZE 0 FILL T-OPS-RESET
    DS ADISP-STORE ADST-SIZE 0 FILL TV @ D-PATH DS ADISP-STORE ADST-INIT DROP D-WIPE
    DS ADISP-STORE ADST-SIZE 0 FILL
    RT @ TV @ DS ADISP-INIT DROP
    16384 OUT-U ! NEWS$ OPS! 300000 A-TIME ! 4096 A-DISC ! ;
"""

SUITE = NativeForth(("tui/applets/agent/dispatch.f",
                     "tui/applets/agent/providers/devtools/device-flow.f"),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 4_000_000_000) -> list[list[str]]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line.split() for line in output.replace("\r", "").split("\n") if line.strip()]


def ints(row: list[str]) -> list[int]:
    return [int(token) for token in row]


REPLY = ("Connected through Akashic's provider-neutral runtime. "
         "You asked: Summarize the news.")


def test_a_run_starts_on_its_model_and_completes(forth):
    rows = run(forth, [
        "FRESH T-NOW EPOCH-SET 1 1 R-OCC KEEP1 GO-KEPT . R0 NAMES? . RUNS . "
        "R0 ADST-R.PHASE @ . HELD? . STATUS@ . CHAT . DS ADISP-IDLE? . DS ADISP-BUSY? . "
        "WHOSE. CR",
        # Chat waits behind it, and cannot cancel it.
        "NEWS$ RT @ ARUNTIME-SEND . RT @ ARUNTIME-CANCEL . KEY1 STAND . R0 NAMES? . CR",
        # It runs on gpt-slow at high effort and the priority tier, while
        # chat keeps gpt-fast selected, as run 2^48 + 1.
        "LAST. ST ARSET-SELECTED-MODEL WHICH . "
        "PRV @ APROV.CONTEXT @ _SPC.RUN-ID @ ADISP-RUN-BASE - . CR",
        "8 STEPS STATUS@ . HELD? . DS ADISP-BUSY? . DS ADISP-IDLE? . KEY1 STAND . ANS. "
        "R0 NAMES? . R0 ADST-R.PHASE @ . R0 ADST-R.REPLY-U @ . CHAT . WHOSE. CR",
        "SUM. CR",
        # Its transcript: the prompt, then the reply, with no model context.
        "R0 DECODE . DUP ACONV.COUNT @ . 0 OVER ACONV-NTH AMSG-TEXT NEWS$ COMPARE . "
        "1 OVER ACONV-NTH AMSG.ROLE @ AROLE-ASSISTANT = . "
        "1 OVER ACONV-NTH AMSG.TEXT-U @ . DUP ACONV.MODEL-CONTEXT @ ACTX.COUNT @ . "
        "DUP ACONV.ID @ ADISP-RUN-BASE - . ACONV-FREE CR",
        # The runtime closed the authority it owned; the record says when the
        # run was accepted and ended.
        "AM-LIVE? . AM @ AMRUN.FREE-PENDING @ . GONE "
        "R0 ADST-R.ACCEPTED @ T-NOW - . R0 ADST-R.ENDED @ T-NOW - . CR",
    ])
    reply = len(REPLY)
    assert ints(rows[0]) == [S_STARTED, -1, 1, ACCEPTED, -1, RUNNING, 0, 0, -1, 6, 1, 4]
    assert ints(rows[1]) == [HELD, HELD, S_RUNNING, -1]
    assert rows[2] == ["1", "high", "priority", "0", "0", "1"]
    assert ints(rows[3]) == [IDLE, 0, 0, -1, S_ENDED, COMPLETED, R_NONE, -1, ENDED,
                             reply, 0, 6, 1, 4]
    assert rows[4] == ["completed;", str(reply), "bytes", "of", "reply"]
    assert ints(rows[5]) == [0, 2, 0, -1, reply, 0, 1]
    assert ints(rows[6]) == [0, -1, 0, 0]


def test_a_known_key_answers_its_run_and_a_conflict_starts_nothing(forth):
    rows = run(forth, [
        "FRESH 1 1 R-OCC KEEP1 GO DROP 8 STEPS "
        "1 1 R-OCC GO . ANS. R0 NAMES? . RUNS . AM-LIVE? . AM-FREE CR",
        # Another request under the key is no run's.
        "2 RQ SDSP-R.PERMISSION-REVISION ! GO-DIRTY . ANS. RS SDSP-P.RUN RID-ZERO? . "
        "RUNS . AM-LIVE? . AM-FREE CR",
        # A run in flight answers that it runs.
        "1 2 R-OCC GO DROP GO . R1 NAMES? . RUNS . AM-LIVE? . AM-FREE 8 STEPS CR",
    ])
    assert ints(rows[0]) == [S_ENDED, COMPLETED, R_NONE, -1, 1, -1]
    assert ints(rows[1]) == [S_ENDED, INDETERMINATE, R_KEY_CONFLICT, -1, 1, -1]
    assert ints(rows[2]) == [S_RUNNING, -1, 2, -1]


REFUSALS = {
    # setup, the start, undoing the setup, the reason
    "another provider":
        ("SCRIPTED$ AD SACT-D.PROVIDER SACT-D! OPS-AGAIN", "GO", "",
         R_MODEL_UNAVAILABLE),
    "a model the catalog lacks":
        ("GONE$ AD SACT-D.MODEL SACT-D! OPS-AGAIN", "GO", "", R_MODEL_UNAVAILABLE),
    "an effort the model lacks":
        ("MEDIUM$ AD SACT-D.EFFORT SACT-D! OPS-AGAIN", "GO", "", R_MODEL_UNAVAILABLE),
    "a tier the model lacks":
        ("FAST$ AD SACT-D.MODEL SACT-D! LOW$ AD SACT-D.EFFORT SACT-D! OPS-AGAIN", "GO", "",
         R_MODEL_UNAVAILABLE),
    "a catalog still loading":
        ("ARSET-STATE-LOADING ST ARSET.STATE !", "GO", "ARSET-STATE-READY ST ARSET.STATE !",
         R_AGENT_UNAVAILABLE),
    "a provider offline":
        ("APROV-S-OFFLINE PRV @ APROV.STATE !", "GO", "APROV-S-READY PRV @ APROV.STATE !",
         R_AGENT_UNAVAILABLE),
    "a provider signed out":
        ("AAUTH-STATE-SIGNED-OUT SIGNED", "GO", "AAUTH-STATE-READY SIGNED",
         R_AGENT_UNAVAILABLE),
    "a provider signing in":
        ("AAUTH-STATE-PENDING SIGNED", "GO", "AAUTH-STATE-READY SIGNED",
         R_AGENT_UNAVAILABLE),
    "a prompt too large for the provider":
        ("' TINY-ROOM PRV @ APROV.INPUT-XT !", "GO", "0 PRV @ APROV.INPUT-XT !",
         R_TOO_LARGE),
    "an authority past its deadline":
        ("", "AUTHORITY -1 AM @ AMRUN.DEADLINE-MS ! GO-AM", "", R_INVALID),
    "an authority that cannot disclose the prompt":
        ("5 A-DISC !", "GO", "", R_INVALID),
    "a response with a stale run named":
        ("GONE$ AD SACT-D.MODEL SACT-D! OPS-AGAIN", "GO-DIRTY", "", R_MODEL_UNAVAILABLE),
    "a provider without a catalog":
        ("0 PRV @ APROV.RUN-SETTINGS !", "GO", "ST PRV @ APROV.RUN-SETTINGS !",
         R_MODEL_UNAVAILABLE),
    "an authority that already disclosed most of its budget":
        ("", "AUTHORITY 4090 AM @ AMRUN.DISCLOSURE-USED ! GO-AM", "", R_INVALID),
}


def test_refusals_record_nothing(forth):
    """A refused run is answered blocked under the permission it names,
    nothing is recorded, and its authority stays its caller's."""

    lines = [
        f"FRESH {setup} 1 1 R-OCC {go} . ANS. WHOSE. RUNS . AM-LIVE? . "
        f"HELD? . DS ADISP-IDLE? . RS SDSP-P.RUN RID-ZERO? . AM-FREE {undo} CR"
        for setup, go, undo, _ in REFUSALS.values()
    ]
    lines.append("FRESH GONE$ AD SACT-D.MODEL SACT-D! OPS-AGAIN 1 1 R-OCC GO DROP AM-FREE SUM. CR")
    rows = run(forth, lines)
    assert len(rows) == len(REFUSALS) + 1, rows
    for (name, (_, _, _, reason)), row in zip(REFUSALS.items(), rows):
        assert ints(row) == [S_ENDED, BLOCKED, reason, 6, 1, 4, 0, -1, 0, -1, -1], name
    assert rows[-1] == ["blocked:", "model", "unavailable"]


def test_only_a_provider_that_needs_a_sign_in_waits_for_one(forth):
    """A provider that takes no sign-in runs whatever its sign-in says."""

    rows = run(forth, [
        "FRESH AAUTH-STATE-SIGNED-OUT SIGNED "
        "PRV @ APROV.FEATURES @ APROV-F-AUTH INVERT AND PRV @ APROV.FEATURES ! "
        "1 1 R-OCC KEEP1 GO . 8 STEPS KEY1 STAND . ANS. "
        "PRV @ APROV.FEATURES @ APROV-F-AUTH OR PRV @ APROV.FEATURES ! "
        "AAUTH-STATE-READY SIGNED CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_ENDED, COMPLETED, R_NONE]


def test_a_run_stops_for_review(forth):
    rows = run(forth, [
        "FRESH TASK$ OPS! 1 1 R-OCC KEEP1 GO . 8 STEPS KEY1 STAND . ANS. HELD? . STATUS@ . CR",
        # The call is in its transcript, never made.
        "R0 DECODE . DUP ACONV.COUNT @ . 2 OVER ACONV-NTH AMSG.FLAGS @ AMSG-F-TOOL AND 0<> . "
        "2 OVER ACONV-NTH AMSG.STATE @ AMSG-S-CANCELLED = . ACONV-FREE CR",
        "FRESH APPROVAL$ OPS! 1 1 R-OCC KEEP1 GO . 8 STEPS KEY1 STAND . ANS. CR",
        # The next run's end is its own.
        "NEWS$ OPS! 1 2 R-OCC KEEP2 GO . 8 STEPS KEY2 STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_ENDED, STOPPED, R_TOOL, 0, IDLE]
    assert ints(rows[1]) == [0, 3, -1, -1]
    assert ints(rows[2]) == [S_STARTED, S_ENDED, STOPPED, R_APPROVAL]
    assert ints(rows[3]) == [S_STARTED, S_ENDED, COMPLETED, R_NONE]


def test_runs_wait_their_turn_and_chat_waits_behind_them(forth):
    rows = run(forth, [
        "FRESH LINGER$ RT @ ARUNTIME-SEND . 3 STEPS STATUS@ . CR",
        # Chat runs: a scheduled run waits, keeping its place in line.
        "1 1 R-OCC KEEP1 GO . HELD? . KEY1 STAND . RUNS . AM-LIVE? . AM-FREE "
        "DS ADISP-BUSY? . DS ADISP-IDLE? . CR",
        "1 2 R-OCC KEEP2 GO . AM-FREE KEY2 STAND . CR",
        # Chat starts nothing new ahead of them.
        "NEWS$ RT @ ARUNTIME-SEND . CR",
        "RT @ ARUNTIME-CANCEL . 2 STEPS STATUS@ . DS ADISP-IDLE? . CR",
        # The first in line goes first.
        "1 2 R-OCC GO . AM-FREE 1 1 R-OCC GO . RUNS . HELD? . CR",
        "1 2 R-OCC GO . AM-FREE 8 STEPS KEY1 STAND . ANS. HELD? . DS ADISP-IDLE? . CR",
        "1 2 R-OCC GO . 8 STEPS KEY2 STAND . ANS. HELD? . DS ADISP-BUSY? . STATUS@ . CR",
        # Then chat runs again, its conversation only its own.
        "NEWS$ RT @ ARUNTIME-SEND . 8 STEPS STATUS@ . CHAT . CR",
    ])
    assert ints(rows[0]) == [0, RUNNING]
    assert ints(rows[1]) == [S_WAITING, -1, S_WAITING, 0, -1, -1, 0]
    assert ints(rows[2]) == [S_WAITING, S_WAITING]
    assert ints(rows[3]) == [HELD]
    assert ints(rows[4]) == [0, 5, -1]
    assert ints(rows[5]) == [S_WAITING, S_STARTED, 1, -1]
    assert ints(rows[6]) == [S_WAITING, S_ENDED, COMPLETED, R_NONE, -1, -1]
    assert ints(rows[7]) == [S_STARTED, S_ENDED, COMPLETED, R_NONE, 0, 0, 5]
    assert ints(rows[8]) == [0, IDLE, 4]


def test_a_waiting_run_refused_leaves_the_line(forth):
    rows = run(forth, [
        "FRESH LINGER$ RT @ ARUNTIME-SEND DROP 3 STEPS 1 1 R-OCC KEEP1 GO . AM-FREE HELD? . "
        "RT @ ARUNTIME-CANCEL DROP 2 STEPS ARSET-STATE-LOADING ST ARSET.STATE ! "
        "1 1 R-OCC GO . ANS. AM-FREE ARSET-STATE-READY ST ARSET.STATE ! "
        "HELD? . DS ADISP-BUSY? . KEY1 STAND . CR",
    ])
    assert ints(rows[0]) == [S_WAITING, -1, S_ENDED, BLOCKED, R_AGENT_UNAVAILABLE, 0, 0,
                             S_UNKNOWN]


def test_cancelling(forth):
    rows = run(forth, [
        "FRESH LINGER$ OPS! 1 1 R-OCC KEEP1 GO . 4 STEPS KEY1 STAND . "
        "KEY1 SACT-R-REVOKED DS ADISP-CANCEL . KEY1 STAND . ANS. HELD? . STATUS@ . "
        "R0 ADST-R.PHASE @ . CR",
        # A reason that cannot explain a cancel is the user's.
        "1 2 R-OCC KEEP2 GO . KEY2 SACT-R-TOOL DS ADISP-CANCEL . KEY2 STAND . ANS. CR",
        # A run waiting gives up its place.
        "LINGER$ RT @ ARUNTIME-SEND . 3 STEPS 1 3 R-OCC GO . AM-FREE "
        "RQ SDSP-R.KEY SACT-R-USER DS ADISP-CANCEL . RQ SDSP-R.KEY STAND . HELD? . "
        "RT @ ARUNTIME-CANCEL DROP 2 STEPS CR",
        "KEY1 SACT-R-USER DS ADISP-CANCEL . KEY1 32 9 FILL KEY1 SACT-R-USER DS ADISP-CANCEL . CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_RUNNING, S_OK, S_ENDED, CANCELLED, R_REVOKED, 0,
                             IDLE, ENDED]
    assert ints(rows[1]) == [S_STARTED, S_OK, S_ENDED, CANCELLED, R_USER]
    assert ints(rows[2]) == [0, S_WAITING, S_OK, S_UNKNOWN, 0]
    assert ints(rows[3]) == [S_ENDED, S_UNKNOWN]


def test_a_reply_keeps_no_more_than_its_limit(forth):
    rows = run(forth, [
        "FRESH 10 OUT-U ! NEWS$ OPS! 1 1 R-OCC KEEP1 GO . 8 STEPS KEY1 STAND . ANS. "
        "R0 ADST-R.REPLY-U @ . R0 DECODE . 1 OVER ACONV-NTH AMSG.TEXT-U @ . ACONV-FREE CR",
        # A cut never splits a character: 67 bytes would end inside the
        # first e-acute of the prompt's echo, and 68 just after it.
        "FRESH 67 OUT-U ! RESUME$ OPS! 1 1 R-OCC KEEP1 GO DROP 8 STEPS "
        "R0 ADST-R.REPLY-U @ . KEY1 STAND DROP ANS. CR",
        "FRESH 68 OUT-U ! RESUME$ OPS! 1 1 R-OCC KEEP1 GO DROP 8 STEPS "
        "R0 ADST-R.REPLY-U @ . CR",
        # A run that completed before the dispatcher looked still ran out of
        # room; its reply completed.
        "FRESH 10 OUT-U ! NEWS$ OPS! 1 1 R-OCC KEEP1 GO DROP 8 PUMPS DS ADISP-PUMP "
        "KEY1 STAND . ANS. R0 ADST-R.REPLY-U @ . "
        "R0 DECODE . 1 OVER ACONV-NTH AMSG.STATE @ AMSG-S-COMPLETE = . ACONV-FREE CR",
        # A run that would never finish is stopped once its reply passes.
        "FRESH 10 OUT-U ! LINGER$ OPS! 1 1 R-OCC KEEP1 GO DROP 8 STEPS KEY1 STAND . ANS. "
        "R0 DECODE . 1 OVER ACONV-NTH AMSG.STATE @ AMSG-S-CANCELLED = . ACONV-FREE CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_ENDED, EXPIRED, R_OUTPUT, 10, 0, 10]
    assert ints(rows[1]) == [66, EXPIRED, R_OUTPUT]
    assert ints(rows[2]) == [68]
    assert ints(rows[3]) == [S_ENDED, EXPIRED, R_OUTPUT, 10, 0, -1]
    assert ints(rows[4]) == [S_ENDED, EXPIRED, R_OUTPUT, 0, -1]


def test_a_run_out_of_time(forth):
    rows = run(forth, [
        "FRESH LINGER$ OPS! 1 1 R-OCC KEEP1 GO . 2 STEPS -1 AM @ AMRUN.DEADLINE-MS ! "
        "4 STEPS KEY1 STAND . ANS. HELD? . CR",
        # A cause never outlives its run.
        "1 2 R-OCC KEEP2 GO DROP 2 STEPS KEY2 SACT-R-USER DS ADISP-CANCEL DROP "
        "1 3 R-OCC GO . 2 STEPS -1 AM @ AMRUN.DEADLINE-MS ! 4 STEPS "
        "RQ SDSP-R.KEY STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [S_STARTED, S_ENDED, EXPIRED, R_TIME, 0]
    assert ints(rows[1]) == [S_STARTED, S_ENDED, EXPIRED, R_TIME]


def test_a_restart_finds_the_run_left_in_flight(forth):
    rows = run(forth, [
        "FRESH LINGER$ OPS! 1 1 R-OCC KEEP1 GO . 2 STEPS CRASH "
        "RT @ TV @ DS ADISP-INIT . KEY1 STAND . ANS. R0 ADST-R.PHASE @ . STATUS@ . CR",
        "1 1 R-OCC GO . ANS. AM-LIVE? . AM-FREE CR",
        # A restart whose reconcile could not be written answers the same.
        "FRESH LINGER$ OPS! 1 1 R-OCC KEEP1 GO DROP 2 STEPS CRASH 1 T-SYNC-N ! "
        "RT @ TV @ DS ADISP-INIT . 0 T-SYNC-N ! KEY1 STAND . ANS. R0 ADST-R.PHASE @ . CR",
        "1 1 R-OCC GO . ANS. AM-LIVE? . AM-FREE CR",
    ])
    assert ints(rows[0]) == [S_STARTED, 0, S_ENDED, INDETERMINATE, R_INTERRUPTED, ENDED, IDLE]
    assert ints(rows[1]) == [S_ENDED, INDETERMINATE, R_INTERRUPTED, -1]
    assert ints(rows[2]) == [3, S_ENDED, INDETERMINATE, R_INTERRUPTED, ACCEPTED]
    assert ints(rows[3]) == [S_ENDED, INDETERMINATE, R_INTERRUPTED, -1]


def test_closing_ends_the_run_in_flight(forth):
    rows = run(forth, [
        "FRESH LINGER$ OPS! 1 1 R-OCC KEEP1 GO . 2 STEPS DS ADISP-FINI HELD? . STATUS@ . "
        "DS ADISP-VALID? . CR",
        "RT @ TV @ DS ADISP-INIT . KEY1 STAND . ANS. CR",
        "FRESH LINGER$ RT @ ARUNTIME-SEND DROP 3 STEPS 1 1 R-OCC GO . AM-FREE HELD? . "
        "DS ADISP-FINI HELD? . RT @ ARUNTIME-CANCEL DROP 2 STEPS CR",
    ])
    assert ints(rows[0]) == [S_STARTED, 0, IDLE, 0]
    assert ints(rows[1]) == [0, S_ENDED, CANCELLED, R_SHUTDOWN]
    assert ints(rows[2]) == [S_WAITING, -1, 0]


def test_answers_and_their_refusals(forth):
    rows = run(forth, [
        "FRESH KEY1 32 9 FILL KEY1 STAND . CR",
        # A summary larger than the response asks for room.
        "1 1 R-OCC KEEP1 GO DROP 8 STEPS 4 RS SDSP-RESPONSE-INIT KEY1 RS DS ADISP-STATUS . "
        "RS SDSP-P.SUMMARY-U @ 0> . CR",
        # A request that is no hand-over, and a dispatcher that is none.
        "1 2 R-OCC 0 RQ SDSP-R.KIND ! GO . RUNS . AM-LIVE? . AM-FREE "
        "RQ 0 0 RS 8 ADISP-START . KEY1 RS 8 ADISP-STATUS . KEY1 0 8 ADISP-CANCEL . "
        "8 ADISP-IDLE? . 8 ADISP-BUSY? . CR",
    ])
    assert ints(rows[0]) == [S_UNKNOWN]
    assert ints(rows[1]) == [S_SMALL, -1]
    assert ints(rows[2]) == [S_INVALID, 1, -1, S_UNAVAILABLE, S_UNAVAILABLE,
                             S_UNAVAILABLE, 0, 0]


def test_lifecycle_refusals(forth):
    rows = run(forth, [
        "FRESH DS ADISP-FINI RT @ TV @ DS 1+ ADISP-INIT . 0 TV @ DS ADISP-INIT . "
        "DS ADISP-VALID? . RT @ TV @ DS ADISP-INIT . RT @ TV @ DS ADISP-INIT . CR",
    ])
    # Misaligned, no runtime, then opened, and a dispatcher already in use.
    assert ints(rows[0]) == [1, 1, 0, 0, 5]


def test_a_store_that_fails_to_write_an_end(forth):
    rows = run(forth, [
        # The disk fails as the end is written: chat goes free, the next run
        # waits for the record, and the next pump writes it.
        "FRESH 1 1 R-OCC KEEP1 GO DROP 3 STEPS 1 T-SYNC-N ! STEP 0 T-SYNC-N ! "
        "DS ADISP-IDLE? . HELD? . KEY1 STAND . ANS. R0 ADST-R.PHASE @ . CR",
        "1 2 R-OCC KEEP2 GO . AM-FREE CR",
        "STEP R0 ADST-R.PHASE @ . DS ADISP-IDLE? . KEY1 STAND . ANS. "
        "R0 DECODE . DUP ACONV.COUNT @ . ACONV-FREE CR",
        "1 2 R-OCC GO . 8 STEPS KEY2 STAND . ANS. CR",
        # A store that blocks on the end is given up on; a reopen finds the
        # end it wrote.
        "FRESH 1 1 R-OCC KEEP1 GO DROP 3 STEPS 5 T-SYNC-N ! STEP 0 T-SYNC-N ! "
        "DS ADISP-STORE ADST-STATE@ . DS ADISP-IDLE? . HELD? . KEY1 STAND . CR",
        "1 2 R-OCC GO . ANS. AM-FREE CR",
        "DS ADISP-FINI RT @ TV @ DS ADISP-INIT . KEY1 STAND . ANS. CR",
    ])
    assert ints(rows[0]) == [0, 0, S_ENDED, COMPLETED, R_NONE, ACCEPTED]
    assert ints(rows[1]) == [S_WAITING]
    assert ints(rows[2]) == [ENDED, -1, S_ENDED, COMPLETED, R_NONE, 0, 2]
    assert ints(rows[3]) == [S_STARTED, S_ENDED, COMPLETED, R_NONE]
    assert ints(rows[4]) == [2, -1, 0, S_UNKNOWN]
    assert ints(rows[5]) == [S_ENDED, BLOCKED, R_AGENT_UNAVAILABLE]
    assert ints(rows[6]) == [0, S_ENDED, COMPLETED, R_NONE]


def test_a_start_its_provider_refuses(forth):
    rows = run(forth, [
        "FRESH 1 PRV @ APROV.CONTEXT @ _SPC.STATE ! 1 1 R-OCC KEEP1 GO . ANS. "
        "R0 ADST-R.PHASE @ . AM-LIVE? . HELD? . STATUS@ . RT @ ARUNTIME.RUN-CONV @ . "
        "RT @ ARUNTIME.FLAGS @ . 0 PRV @ APROV.CONTEXT @ _SPC.STATE ! AM-FREE CR",
        "R0 DECODE . DUP ACONV.COUNT @ . 1 OVER ACONV-NTH AMSG.STATE @ AMSG-S-ERROR = . "
        "ACONV-FREE CR",
        "FRESH LINGER$ RT @ ARUNTIME-SEND DROP 3 STEPS 1 1 R-OCC KEEP1 GO . AM-FREE HELD? . "
        "RT @ ARUNTIME-CANCEL DROP 2 STEPS 1 PRV @ APROV.CONTEXT @ _SPC.STATE ! "
        "1 1 R-OCC GO . ANS. AM-FREE 0 PRV @ APROV.CONTEXT @ _SPC.STATE ! "
        "HELD? . DS ADISP-BUSY? . CR",
    ])
    assert ints(rows[0]) == [S_ENDED, FAILED, R_PROVIDER_START, ENDED, -1, 0, IDLE, 0, 0]
    assert ints(rows[1]) == [0, 2, -1]
    # A run that waited and then could not start leaves the line, and chat
    # goes free.
    assert ints(rows[2]) == [S_WAITING, -1, S_ENDED, FAILED, R_PROVIDER_START, 0, 0]


def test_a_scheduled_run_reads_no_history_and_gets_no_tools(forth):
    rows = run(forth, [
        "FRESH AROLE-USER 1 NEWS$ RT @ ARUNTIME.DISCLOSURE-CONTEXT @ ACTX-APPEND-MESSAGE . DROP "
        "FAKE-G RT @ ARUNTIME-TOOL-GATEWAY! 1 1 R-OCC GO . 0 RT @ ARUNTIME-TOOL-GATEWAY! "
        "PRV @ SCRIPTED-LAST-CONTEXT-N . RT @ ARUNTIME.TURN-REQUEST ATURN.TOOL-GATEWAY @ . "
        "RT @ ARUNTIME.TURN-REQUEST ATURN.FLAGS @ . "
        "RT @ ARUNTIME.DISCLOSURE-CONTEXT @ ACTX-CLEAR 8 STEPS CR",
    ])
    assert ints(rows[0]) == [0, S_STARTED, 0, 0, 0]


def test_the_runtime_starts_only_what_it_can_run(forth):
    rows = run(forth, [
        "FRESH AUTHORITY ACONV-NEW DROP CV2 ! "
        "0 0 0 0 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . "
        "NEWS$ 0 0 0 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . "
        "NEWS$ 0 0 5 0 0 AM @ RT @ ARUNTIME-RUN-START . "
        "NEWS$ 0 0 5 0 CV2 @ 0 RT @ ARUNTIME-RUN-START . "
        "STATUS@ . RT @ ARUNTIME.RUN-CONV @ . AM-LIVE? . CR",
        "-1 AM @ AMRUN.DEADLINE-MS ! NEWS$ 0 0 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . "
        "AM-FREE AUTHORITY 5 AM @ AMRUN.MANDATE MAND.DISCLOSURE-BUDGET ! "
        "NEWS$ 0 0 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . AM-FREE AUTHORITY "
        "LINGER$ RT @ ARUNTIME-SEND DROP 2 STEPS NEWS$ 0 0 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . "
        "RT @ ARUNTIME-CANCEL DROP 2 STEPS AM-LIVE? . AM-FREE CV2 @ ACONV.COUNT @ . "
        "CV2 @ ACONV-FREE RT @ ARUNTIME.RUN-CONV @ . CR",
        "ARUN-S-IDLE RT @ ARUNTIME.STATUS ! RT @ ARUNTIME-RUN-ENDED? . RT @ ARUNTIME-RUN-TAKE . . . CR",
        "AUTHORITY ACONV-NEW DROP CV2 ! NEWS$ 0 0 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . 0 AM ! "
        "RT @ ARUNTIME.HOLD @ . NEWS$ RT @ ARUNTIME-SEND . RT @ ARUNTIME-IDLE? . "
        "RT @ ARUNTIME-RUN-ENDED? . RT @ ARUNTIME-RUN-TAKE . . . "
        "RT @ ARUNTIME.RUN-CONV @ CV2 @ = . CR",
        "ARUN-S-CANCELLED RT @ ARUNTIME-RUN-STOP . RT @ ARUNTIME-RUN-ENDED? . "
        "RT @ ARUNTIME-IDLE? . RT @ ARUNTIME-RUN-TAKE . . CV2 @ = . RT @ ARUNTIME-IDLE? . "
        "RT @ ARUNTIME-RUN-TAKE . . . CV2 @ ACONV-FREE PUMP CR",
        "ARUN-S-IDLE RT @ ARUNTIME.STATUS ! AUTHORITY ACONV-NEW DROP CV2 ! "
        "NEWS$ 0 0 6 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . 0 AM ! RT @ ARUNTIME-QUIESCE . "
        "RT @ ARUNTIME-RUN-ENDED? . RT @ ARUNTIME-RUN-TAKE 2DROP ACONV-FREE PUMP CR",
        "LINGER$ RT @ ARUNTIME-SEND . 2 STEPS ARUN-S-CANCELLED RT @ ARUNTIME-RUN-STOP . "
        "RT @ ARUNTIME-CANCEL . 2 STEPS CR",
    ])
    assert ints(rows[0]) == [1, 1, 1, 1, IDLE, 0, -1]
    # An inactive authority, one that cannot disclose the prompt, and a
    # runtime running chat.
    assert ints(rows[1]) == [1, 4, 2, -1, 0, 0]
    # With no run in its own conversation there is no end to take.
    assert ints(rows[2]) == [0, 0, 0, 0]
    # A run started directly holds chat by itself, and its end is taken
    # once it is over.
    assert ints(rows[3]) == [0, 0, HELD, 0, 0, 0, 0, 0, -1]
    assert ints(rows[4]) == [0, -1, 0, 0, 5, -1, -1, 0, 0, 0]
    # Quiescing ends such a run; RUN-STOP stops no chat run.
    assert ints(rows[5]) == [0, 0, -1]
    assert ints(rows[6]) == [0, 1, 0]


def test_a_run_starts_with_its_reference(forth):
    news, doc = len("Summarize the news."), len("A document to read.")
    rows = run(forth, [
        # The prompt and the reference together fill the disclosure: the
        # provider takes the reference with the turn, and the runtime keeps
        # none of it once the start returns.
        ': DOC$  ( -- a u ) S" A document to read." ; '
        "FRESH AUTHORITY ACONV-NEW DROP CV2 ! "
        "NEWS$ NIP DOC$ NIP + AM @ AMRUN.MANDATE MAND.DISCLOSURE-BUDGET ! "
        "NEWS$ DOC$ 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . "
        "AM @ AMRUN.DISCLOSURE-USED @ . 0 AM ! "
        "PRV @ SCRIPTED-LAST-REFERENCE DROP . RT @ ARUNTIME.RUN-REFERENCE-U @ . "
        "8 STEPS RT @ ARUNTIME-RUN-ENDED? . RT @ ARUNTIME-RUN-TAKE 2DROP ACONV-FREE PUMP CR",
        # A byte less of room, or a reference with no text, starts nothing.
        "AUTHORITY ACONV-NEW DROP CV2 ! "
        "NEWS$ NIP DOC$ NIP + 1- AM @ AMRUN.MANDATE MAND.DISCLOSURE-BUDGET ! "
        "NEWS$ DOC$ 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . AM-FREE AUTHORITY "
        "NEWS$ 0 5 5 0 CV2 @ AM @ RT @ ARUNTIME-RUN-START . AM-FREE "
        "CV2 @ ACONV-FREE STATUS@ . CR",
    ])
    assert ints(rows[0]) == [0, news + doc, doc, 0, -1]
    assert ints(rows[1]) == [4, 1, IDLE]


def test_a_store_that_cannot_be_used(forth):
    rows = run(forth, [
        "FRESH DS ADISP-FINI TBUF 16 0 FILL 16 TLEN ! D-PATH T-PUT-AT "
        "RT @ TV @ DS ADISP-INIT . 1 1 R-OCC GO . ANS. RUNS . AM-LIVE? . AM-FREE CR",
    ])
    assert ints(rows[0]) == [4, S_ENDED, BLOCKED, R_AGENT_UNAVAILABLE, 0, -1]
