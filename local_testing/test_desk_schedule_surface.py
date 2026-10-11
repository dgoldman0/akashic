#!/usr/bin/env python3
"""tui/applets/desk/schedule-surface.f: Desk's screens for scheduled runs.

The suite drives the screens' state over the broker suite's real broker,
permission store and fake handler, without a screen: the texts each row
shows, the approval's rows and the note on top when the Agent could not
run it, the approval following the broker's oldest one and forgetting a
withdrawn one, every answer the approval gives and the checks before
Allow grants, and the permissions' rows, their names and revoking.  The
overlays' keys, drawing and reading to the end run in Desk's smokes.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth
from test_schedule_broker import PRELUDE as BROKER_PRELUDE


S_PENDING, S_ALLOWED, S_REFUSED, S_GONE = 8, 9, 10, 11
R_AGENT_UNAVAILABLE, R_MODEL_UNAVAILABLE, R_TOO_LARGE = 5, 6, 7

PRELUDE = BROKER_PRELUDE + r"""
CREATE SS-RAW _SCHS-SIZE 7 + ALLOT  SS-RAW 7 + -8 AND CONSTANT SS
SS _SCHS-SIZE 0 FILL
VARIABLE VET-ANS
: S-VET  ( request context -- reason ) 2DROP VET-ANS @ ;
\ A screen's state, empty, over the broker.
: S-STATE  ( -- )
    SS _SCHS.TEXT _SCHT-FREE SS _SCHS.STATUS _SCHT-FREE SS _SCHS-SIZE 0 FILL
    B SS _SCHS.BROKER ! ;
\ The broker with its fake handler, which says why it could not run an
\ approval: VET-ANS.
: S-FRESH  ( -- )
    B-FRESH A-OPS 0 VET-ANS ! ['] S-VET FH SBRK-H.VET-XT ! S-STATE ;
\ What SCHS-SERVICE does with an instance's state.
: SCHS-SERVICE-STATE  ( now s -- close? )
    DUP _SCHS-APPROVE? IF _SCHS-APPROVE-SERVICE EXIT THEN _SCHS-PERMS-SERVICE ;
\ The screen as an approval of the broker's oldest, as Desk binds it.
: AS-APPROVAL  ( -- )
    _SCHS-K-APPROVE SS _SCHS.KIND !
    B SBRK-ASKING DROP SS _SCHS.ASK-ID ! 0 SS _SCHS.READ !
    SS _SCHS-ASKING? IF SS _SCHS.REQUEST @ B SBRK-VET SS _SCHS.REASON ! THEN
    SS _SCHS-APPROVE-STATUS ;
: ASK  ( s -- ) R-ASK RQ BC SDSP-ASK 2DROP ;
: ROW.  ( index -- )
    DUP SS _SCHS-APPROVE-ROW _SCHS-HEADER$ TYPE ." |"
    SS _SCHS-APPROVE-ROW SS _SCHS-BODY$ TYPE CR ;
: ROWS.  ( -- ) SS _SCHS-ROW-N 0 ?DO I ROW. LOOP ;
: STATUS.  ( -- ) SS _SCHS.STATUS _SCHT$ TYPE ;
: CHOOSE  ( choice -- close? ) SS _SCHS.CHOICE ! T-NOW SS SCHS-SERVICE-STATE ;
\ Daybook's names for schedules: byte 1's is known, others are not.
: LABEL  ( rid context -- a u ) DROP C@ 1 = IF S" Morning news" ELSE 0 0 THEN ;
: AS-PERMS  ( -- )
    _SCHS-K-PERMS SS _SCHS.KIND ! ['] LABEL SS _SCHS.LABEL-XT ! 0 SS _SCHS.LABEL-CTX !
    SS _SCHS-PERMS-STATUS ;
: PERM.  ( index -- )
    DUP SS _SCHS-PERM SS _SCHS-TITLE$ TYPE ." |"
    SS _SCHS-PERM ['] _SCHS-PERMISSION+ SS _SCHS.TEXT _SCHT-COMPOSE TYPE CR ;
\ The row of the permission for schedule bytes S, or -1.
: ROW-OF  ( s -- index )
    SS _SCHS-PERMS-N 0 ?DO
        I SS _SCHS-PERM SPERM-P.SCHEDULE C@ OVER = IF DROP I UNLOOP EXIT THEN
    LOOP
    DROP -1 ;
\ The approval's rows in a list as the screen makes it, in a region
\ H rows high, its view at the top, as the screen sets it.
: LIST-ON  ( h -- )
    0 0 ROT 60 RGN-NEW
    SS _SCHS-APPROVE? IF
        ['] _SCHS-APPROVE-KEY ['] _SCHS-APPROVE-FIELD LST-NEW
        LST-CARDS LST-LOG OR LST-UNTRUSTED OR
    ELSE
        ['] _SCHS-PERMS-KEY ['] _SCHS-PERMS-FIELD LST-NEW LST-CARDS LST-UNTRUSTED OR
    THEN
    OVER LST-MODE!
    _SCHS-COLUMNS 2 2 PICK LST-COLUMNS!
    SS OVER LST-CONTEXT! SS _SCHS.LIST !
    SS _SCHS-ROW-N SS _SCHS-ROWS! ;
: LIST-OFF  ( -- ) SS _SCHS.LIST @ ?DUP IF LST-FREE THEN 0 SS _SCHS.LIST ! ;
\ Bytes ALLOCATE can still hand out: the bank-0 heap, the unused tail of
\ external memory and every reclaimed external block.
: AVAILABLE  ( -- u )
    HEAP-FREE-BYTES XMEM-FREE +
    XMEM-FL @ BEGIN ?DUP WHILE DUP @ ROT + SWAP 8 + @ REPEAT ;
\ Takes every block external memory can give, largest first; FEED gives
\ them back.
VARIABLE HOG
: STARVE  ( -- )
    0 HOG !
    1099511627776 BEGIN DUP 0> WHILE
        DUP ALLOCATE 0= IF HOG @ OVER ! HOG ! ELSE DROP 2/ THEN
    REPEAT DROP ;
: FEED  ( -- ) BEGIN HOG @ ?DUP WHILE DUP @ HOG ! FREE REPEAT ;
: TCAP  ( -- n ) SS _SCHS.TEXT _SCHT.CAP @ ;
: TBUF@  ( -- a ) SS _SCHS.TEXT _SCHT.BUF @ ;
: TCOMPOSE  ( x xt -- a u ) SS _SCHS.TEXT _SCHT-COMPOSE ;
\ A model with every option.
: GPTX$  ( -- a u ) S" gpt-x" ;  : HIGH$  ( -- a u ) S" high" ;
: PRIO$  ( -- a u ) S" priority" ;
\ A text built by XT from X.
: TEXT.  ( x xt -- ) SS _SCHS.TEXT _SCHT-COMPOSE TYPE CR ;
: TIME.  ( ms -- ) ['] _SCHT-TIME+ TEXT. ;
: WHEN.  ( ms -- ) ['] _SCHT-WHEN+ TEXT. ;
"""

SUITE = NativeForth(("tui/applets/desk/schedule-surface.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str], max_steps: int = 4_000_000_000) -> list[str]:
    output = forth.run(lines, max_steps).decode("latin-1")
    assert "??" not in output, output[-3000:]
    return [line for line in output.replace("\r", "").split("\n") if line.strip()]


def test_the_texts_rows_show(forth):
    rows = run(forth, [
        "S-FRESH 300000 TIME. 90000 TIME. 1500 TIME. 0 TIME.",
        "T-NOW WHEN. 0 WHEN. -1 WHEN.",
        # A model with every option, and one with none.
        "GPTX$ AD SACT-D.MODEL SACT-D! HIGH$ AD SACT-D.EFFORT SACT-D! "
        "PRIO$ AD SACT-D.TIER SACT-D! ARVERB-LOW AD SACT-D.VERBOSITY ! "
        "AD OPS 1024 SACT-AGENT-ENCODE DROP OPS-U ! 1 R-ASK RQ ' _SCHS-MODEL+ TEXT.",
        "A-OPS 1 R-ASK RQ ' _SCHS-MODEL+ TEXT. RQ ' _SCHS-LIMITS+ TEXT.",
    ])
    assert rows[:4] == ["5 min", "90 s", "1500 ms", "0 ms"]
    assert rows[4] == "2026-10-10 12:00 UTC"
    assert rows[5:7] == ["at a time not known"] * 2
    assert rows[7] == "gpt-x, high effort, priority tier, low verbosity"
    assert rows[8] == "gpt-test"
    assert rows[9] == "5 min to run, 4096 bytes to disclose, 16384 bytes of reply"


def test_an_approvals_rows(forth):
    rows = run(forth, [
        "S-FRESH 1 ASK AS-APPROVAL SS _SCHS-ROW-N . SS _SCHS-ALLOWABLE? . STATUS. CR",
        "ROWS.",
        # The Agent could not run it: a note comes first, and Allow goes.
        f"S-FRESH {R_TOO_LARGE} VET-ANS ! 1 ASK AS-APPROVAL SS _SCHS-ROW-N . "
        "SS _SCHS-ALLOWABLE? . STATUS. CR",
        "0 ROW. 1 ROW.",
        # An Agent only not connected keeps Allow.
        f"S-FRESH {R_AGENT_UNAVAILABLE} VET-ANS ! 1 ASK AS-APPROVAL SS _SCHS-ALLOWABLE? . "
        "0 ROW.",
        f"S-FRESH {R_MODEL_UNAVAILABLE} VET-ANS ! 1 ASK AS-APPROVAL SS _SCHS-ALLOWABLE? . "
        "0 ROW.",
    ])
    assert rows[0] == "6 -1 Read it to the end to allow it"
    assert rows[1:7] == [
        "Schedule|Read the news",
        "When|daily at 09:00",
        "Model|gpt-test",
        "Provider|org.akashic.agent.testing.scripted",
        "Limits|5 min to run, 4096 bytes to disclose, 16384 bytes of reply",
        "Prompt|Summarize the news.",
    ]
    assert rows[7] == "7 0 This cannot be allowed"
    assert rows[8] == ("Note|The prompt is too large for this model, so this "
                       "cannot be allowed.")
    assert rows[9] == "Schedule|Read the news"
    assert rows[10] == ("-1 Note|The Agent is not connected now. A run due while it "
                        "is not ends blocked.")
    assert rows[11] == ("0 Note|The Agent does not offer this model, so this cannot "
                        "be allowed.")


def test_an_approval_follows_the_broker(forth):
    rows = run(forth, [
        "S-FRESH 1 ASK AS-APPROVAL SS _SCHS-ASKING? . SS _SCHS.REQUEST @ 0<> . CR",
        # Asked again for the same schedule, the first is withdrawn: the
        # screen forgets its request and shows no rows.
        "1 ASK SS _SCHS-ASKING? . SS _SCHS.REQUEST @ . SS _SCHS-ROW-N . CR",
        # Its service closes it unanswered.
        "0 SS _SCHS.CHOICE ! T-NOW SS SCHS-SERVICE-STATE . CR",
    ])
    assert rows[0].split() == ["-1", "-1"]
    assert rows[1].split() == ["0", "0", "0"]
    assert rows[2].split() == ["-1"]


def test_answering_an_approval(forth):
    rows = run(forth, [
        # Nothing chosen keeps it open; refusing answers and closes it.
        "S-FRESH 1 R-ASK RQ BC SDSP-ASK DROP ASK-ID ! AS-APPROVAL "
        "0 SS _SCHS.CHOICE ! T-NOW SS SCHS-SERVICE-STATE . "
        "_SCHS-C-REFUSE CHOOSE . R0 ASK-ID @ RSP BC SDSP-ASKED . CR",
        # Allow before the end was shown keeps it open and says so.
        "S-FRESH 1 R-ASK RQ BC SDSP-ASK DROP ASK-ID ! AS-APPROVAL -1 SS _SCHS.SHOWN ! "
        "_SCHS-C-ALLOW CHOOSE . SS _SCHS.CHOICE @ . SS _SCHS.SHOWN @ . STATUS. CR",
        # Read, it grants.
        "-1 SS _SCHS.READ ! _SCHS-C-ALLOW CHOOSE . R0 ASK-ID @ RSP BC SDSP-ASKED . "
        "BS SPERM-COUNT@ . CR",
        # The Agent changed since it opened: Allow does not grant, and the
        # note and Read come back.
        "S-FRESH 1 R-ASK RQ BC SDSP-ASK DROP ASK-ID ! AS-APPROVAL -1 SS _SCHS.READ ! "
        f"{R_MODEL_UNAVAILABLE} VET-ANS ! _SCHS-C-ALLOW CHOOSE . SS _SCHS.READ @ . "
        "SS _SCHS.REFRESH @ . SS _SCHS-ROW-N . BS SPERM-COUNT@ . STATUS. CR",
        # A grant the store refuses keeps it open and says why.
        "S-FRESH 1 R-ASK RQ BC SDSP-ASK DROP ASK-ID ! AS-APPROVAL -1 SS _SCHS.READ ! "
        "1 T-SYNC-N ! _SCHS-C-ALLOW CHOOSE . 0 T-SYNC-N ! R0 ASK-ID @ RSP BC SDSP-ASKED . "
        "STATUS. CR",
        # Escape and R refuse as the user's choice: the same refusal.
        "_SCHS-C-REFUSE CHOOSE . R0 ASK-ID @ RSP BC SDSP-ASKED . CR",
    ])
    assert rows[0].split() == ["0", "-1", str(S_REFUSED)]
    assert rows[1] == "0 0 0 Read it to the end to allow it"
    assert rows[2].split() == ["-1", str(S_ALLOWED), "1"]
    assert rows[3] == "0 0 -1 7 0 This cannot be allowed"
    assert rows[4] == f"0 {S_PENDING} Not allowed: the permissions could not be written"
    assert rows[5].split() == ["-1", str(S_REFUSED)]


def test_the_permissions(forth):
    rows = run(forth, [
        "S-FRESH AS-PERMS SS _SCHS-PERMS-N . STATUS. CR",
        "1 APPROVE 2 APPROVE AS-PERMS SS _SCHS-PERMS-N . STATUS. CR",
        "1 ROW-OF PERM. 2 ROW-OF PERM.",
        # Keys are serials, which never move; no row has no permission.
        "1 ROW-OF SS _SCHS-PERM SPERM-P.SERIAL @ . 2 ROW-OF SS _SCHS-PERM SPERM-P.SERIAL @ . "
        "2 SS _SCHS-PERM . -1 SS _SCHS-PERM . CR",
    ])
    assert rows[0] == "0 No scheduled run has been allowed"
    assert rows[1].split() == ["2"]
    assert rows[2] == ("Morning news|Granted 2026-10-10 12:00 UTC; 5 min to run, "
                       "4096 bytes to disclose, 16384 bytes of reply")
    assert rows[3] == ("A schedule Daybook no longer has|Granted 2026-10-10 12:00 UTC; "
                       "5 min to run, 4096 bytes to disclose, 16384 bytes of reply")
    assert rows[4].split() == ["1", "2", "0", "0"]


def test_revoking_a_permission(forth):
    rows = run(forth, [
        "S-FRESH 1 APPROVE 2 APPROVE AS-PERMS "
        "2 ROW-OF SS _SCHS.ROW ! _SCHS-C-REVOKE CHOOSE . SS _SCHS-PERMS-N . "
        "SS _SCHS.REFRESH @ . STATUS. CR",
        "0 PERM.",
        # A revoke the store refuses says why; the permission stays.
        "0 SS _SCHS.ROW ! 1 T-SYNC-N ! _SCHS-C-REVOKE CHOOSE . 0 T-SYNC-N ! "
        "SS _SCHS-PERMS-N . STATUS. CR",
        # A choice carried out is gone: servicing again revokes nothing.
        "0 SS _SCHS.ROW ! T-NOW SS SCHS-SERVICE-STATE . SS _SCHS-PERMS-N . CR",
        # No such row; and Escape closes.
        "5 SS _SCHS.ROW ! _SCHS-C-REVOKE CHOOSE . SS _SCHS-PERMS-N . "
        "-1 SS _SCHS.DONE ! 0 CHOOSE . CR",
    ])
    assert rows[0] == "0 1 -1 Revoked; any run under it is cancelled"
    assert rows[1].startswith("Morning news|")
    assert rows[2] == "0 1 Not revoked: the permissions could not be written"
    assert rows[3].split() == ["0", "1"]
    assert rows[4].split() == ["0", "1", "-1"]


def test_permissions_that_cannot_be_read(forth):
    rows = run(forth, [
        "B-DAMAGED DROP S-STATE AS-PERMS SS _SCHS-PERMS-N . STATUS. CR",
    ])
    assert rows[0] == "0 The permissions cannot be read"


def test_allow_waits_until_the_end_was_shown(forth):
    rows = run(forth, [
        # Four rows show part of the request: not read until its end is.
        "S-FRESH 1 ASK AS-APPROVAL 4 LIST-ON SS _SCHS-SEEN SS _SCHS.READ @ . "
        "SS _SCHS.LIST @ LST-SCROLL-INFO . . . STATUS. CR",
        "SS _SCHS.LIST @ LST-SCROLL-END SS _SCHS-SEEN SS _SCHS.READ @ . STATUS. CR",
        # Back at the top, it stays read.
        "0 SS _SCHS.LIST @ LST-SCROLL-SET SS _SCHS-SEEN SS _SCHS.READ @ . LIST-OFF CR",
        # A request that fits is read when first shown; the permissions
        # are never read, and their status stays theirs.
        "S-FRESH 1 ASK AS-APPROVAL 60 LIST-ON SS _SCHS-SEEN SS _SCHS.READ @ . LIST-OFF "
        "1 APPROVE AS-PERMS 0 SS _SCHS.READ ! 60 LIST-ON SS _SCHS-SEEN SS _SCHS.READ @ . "
        "STATUS. LIST-OFF CR",
        # An approval with no list, or no rows, is not read.
        "S-FRESH 1 ASK AS-APPROVAL SS _SCHS-SEEN SS _SCHS.READ @ . "
        "60 LIST-ON 0 SS _SCHS.LIST @ LST-ROWS! SS _SCHS-SEEN SS _SCHS.READ @ . LIST-OFF CR",
    ])
    first = rows[0].split()
    assert first[0] == "0"
    visible, offset, content = (int(x) for x in first[1:4])
    assert offset == 0 and visible == 4 and content > visible
    assert " ".join(first[4:]) == "Read it to the end to allow it"
    assert rows[1] == "-1 A allows it to run when it is due"
    assert rows[2].split() == ["-1"]
    assert rows[3].split() == ["-1", "0"]
    assert rows[4].split() == ["0", "0"]


def test_revoking_cancels_the_run_under_it(forth):
    rows = run(forth, [
        # A run started under schedule 1's permission; schedule 2's is the
        # other.  Revoked from the screen, the broker cancels that run.
        "S-FRESH 1 APPROVE SAVE1 2 APPROVE SAVE2 USE1 1 1 R-OCC SUBMIT . "
        "AS-PERMS 1 ROW-OF SS _SCHS.ROW ! _SCHS-C-REVOKE CHOOSE . "
        "FH-CANCELS @ . FH-REASON @ . KEY? . SS _SCHS-PERMS-N . CR",
    ])
    assert rows[0].split() == ["3", "0", "1", "2", "-1", "1"]


def test_text_rooms_and_memory(forth):
    rows = run(forth, [
        # Each text grows the room to exactly its length; a shorter one
        # takes the room a longer one left.
        "S-STATE 300000 ' _SCHT-TIME+ TCOMPOSE NIP TCAP = . "
        "T-NOW ' _SCHT-WHEN+ TCOMPOSE NIP TCAP = . "
        "TBUF@ 300000 ' _SCHT-TIME+ TCOMPOSE 2DROP TBUF@ = . TCAP . CR",
        # Every byte the texts take is given back.
        "S-STATE AVAILABLE 300000 ' _SCHT-TIME+ TCOMPOSE 2DROP "
        "T-NOW ' _SCHT-WHEN+ TCOMPOSE 2DROP S\" a status line\" SS _SCHS-SAY "
        "S-STATE AVAILABLE = . CR",
        # Without memory: no text, and an empty status line.
        "S-STATE STARVE 300000 ' _SCHT-TIME+ TCOMPOSE . . "
        "S\" a status line\" SS _SCHS-SAY SS _SCHS.STATUS _SCHT$ NIP . FEED CR",
    ])
    assert rows[0].split() == ["-1", "-1", "-1", "20"]
    assert rows[1].split() == ["-1"]
    assert rows[2].split() == ["0", "0", "0"]
