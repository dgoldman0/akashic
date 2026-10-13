#!/usr/bin/env python3
"""A scheduled run reading its one document (agent/context-read.f).

The document's owner is the stand-in of doc_owner_fixture.py, attached
through its acquisition root with Desk's root Context, as Desk's broker
attaches it.  The run reads as itself, under one-use grants its facet
allows, exactly the version its locator names, within the room it may
disclose, and only text.
"""

from __future__ import annotations

import pytest

from doc_owner_fixture import DOC_OWNER
from native_forth import NativeForth


OK, UNAVAILABLE, STALE, DISCLOSURE, FAILED, NOMEM = range(6)

PRELUDE = DOC_OWNER + r"""
CREATE MD-RAW MAND-SIZE 7 + ALLOT  MD-RAW 7 + -8 AND CONSTANT MD
CREATE FC-RAW CFACET-SIZE 7 + ALLOT  FC-RAW 7 + -8 AND CONSTANT FC
VARIABLE CHILD  VARIABLE AM  VARIABLE ENTRIES
CFENTRY-F-INVOKE CFENTRY-F-AUTO-OBSERVE OR CONSTANT AUTO-READ
: ENTRY  ( op-a op-u -- )
    >R >R DOC-INST CINST.ID @ DOC-INST CINST.GENERATION @ CAP-E-OBSERVE AUTO-READ 0
    R> R> FC CFACET-ADD THROW ;
\ The run, as Desk's broker compiles it: a child of ROOT whose facet lets
\ it describe and snapshot the document's instance when ENTRIES is set,
\ under a read-only Mandate.
: AUTHORITY  ( -- )
    AM @ ?DUP IF AMRUN-FREE THEN
    ROOT @ CTX-CHILD-NEW THROW DUP CHILD !
    CTX.FLAGS DUP @ CTX-F-ACTIVE OR SWAP !
    FC CFACET-INIT
    FC CFACET.ID 32 21 FILL
    HD PHEAD.ID FC CFACET.PRACTICE-ID RID-COPY
    ROOT @ CTX.EPOCH @ FC CFACET.EPOCH !
    CHILD @ CTX.ID @ FC CFACET.CONTEXT-ID !
    CHILD @ CTX.GENERATION @ FC CFACET.CONTEXT-GEN !
    1 FC CFACET.REVISION !
    ENTRIES @ IF S" resource.describe" ENTRY S" resource.snapshot" ENTRY THEN
    MD MAND-INIT
    MD MAND.ID 32 22 FILL
    HD PHEAD.ID MD MAND.PRACTICE-ID RID-COPY
    FC CFACET.ID MD MAND.INPUT-FACET-ID RID-COPY
    FC CFACET.ID MD MAND.DISCLOSURE-FACET-ID RID-COPY
    ROOT @ CTX.EPOCH @ MD MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT MD MAND.PRINCIPAL !
    CHILD @ CTX.ID @ MD MAND.CONTEXT-ID !
    CHILD @ CTX.GENERATION @ MD MAND.CONTEXT-GENERATION !
    CAP-E-OBSERVE MD MAND.EFFECTS !
    MAND-D-READ-ONLY MD MAND.DISPOSITION !
    600000 MD MAND.TIME-BUDGET-MS !
    100000 MD MAND.DISCLOSURE-BUDGET !
    HD CHILD @ MD FC AMRUN-NEW THROW AM ! ;
CREATE LOC QLOC-SIZE ALLOT  CREATE BIND LBIND-SIZE ALLOT
CREATE ACQ RACQ-RESULT-SIZE ALLOT  CREATE SRC RCLI-SIZE ALLOT
CREATE RD ACREAD-SIZE ALLOT  RD ACREAD-INIT
\ The version DOC! set is the one to read; nothing is asked yet.
: NAME  ( -- ) DOC-LOC LOC QLOC-COPY THROW 0 DOC-DESCRIBES ! 0 DOC-SNAPSHOTS ! ;
\ Desk attaches the document and lends the run a client for it.
: ATTACH  ( -- )
    LOC DOC-ROOT ROOT @ RRG BIND ACQ RACQ-ATTACH THROW
    ACQ BIND ROOT @ BUS SRC RCLI-INIT THROW ;
: DETACH  ( -- ) BIND ACQ RACQ-DETACH THROW SRC RCLI-CLEAR ;
\ A fresh run, attached; the read with ROOM, then its status.
: READ  ( room -- status )
    -1 ENTRIES ! AUTHORITY ATTACH >R LOC SRC AM @ R> RD ACREAD-READ ;
: DONE  ( -- ) RD ACREAD-FREE DETACH ;
: COUNTS.  ( -- ) DOC-DESCRIBES @ . DOC-SNAPSHOTS @ . 0 DOC-DESCRIBES ! 0 DOC-SNAPSHOTS ! ;
: NOTES$  ( -- a u ) S" The quarterly report." ;
: OTHER$  ( -- a u ) S" The quarterly report, revised." ;
: SAME$  ( -- a u ) S" The quarterly report!" ;
CREATE BAD 4 ALLOT  66 BAD C! 255 BAD 1+ C! 66 BAD 2 + C! 66 BAD 3 + C!
CREATE LONG 64 ALLOT  LONG 64 CHAR q FILL
"""

SUITE = NativeForth(("tui/applets/agent/context-read.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str]) -> list[str]:
    output = forth.run(lines, 2_000_000_000).decode("latin-1")
    assert "??" not in output and "not found" not in output, output[-3000:]
    return [line for line in output.replace("\r", "").split("\n") if line.strip()]


def ints(line: str) -> list[int]:
    return [int(cell) for cell in line.split()]


def test_a_run_reads_the_exact_version(forth):
    lines = run(forth, [
        "NOTES$ 3 DOC! NAME 100000 READ . RD ACREAD-TEXT TYPE CR",
        "RD ACREAD-TITLE TYPE CR",
        # Described and read once each, by the Agent under the run's
        # Mandate; the root holds the attachment until Desk detaches.
        "RD ACREAD-REVISION . COUNTS. DOC-PRINCIPAL @ CPRINC-AGENT = . "
        "DOC-MANDATE MD MAND.ID RID= . DOC-HELD @ . DONE DOC-HELD @ . "
        "RD ACREAD-TEXT . . DEPTH . CR",
    ])
    assert lines[0] == f"{OK} The quarterly report."
    assert lines[1] == "Field notes"
    assert ints(lines[2]) == [3, 1, 1, -1, -1, 1, 0, 0, 0, 0]


def test_a_changed_document_is_stale(forth):
    lines = run(forth, [
        # A newer revision: the description says so, and nothing is read.
        "NOTES$ 3 DOC! NAME OTHER$ 4 DOC! 100000 READ . COUNTS. "
        "RD ACREAD-TEXT NIP . DONE CR",
        # The same revision with other text: the snapshot is refused.
        "NOTES$ 3 DOC! NAME SAME$ 3 DOC! 100000 READ . COUNTS. DONE DEPTH . CR",
    ])
    assert ints(lines[0]) == [STALE, 1, 0, 0]
    assert ints(lines[1]) == [STALE, 1, 1, 0]


def test_a_document_larger_than_the_room(forth):
    lines = run(forth, [
        "NOTES$ 3 DOC! NAME NOTES$ NIP 1- READ . COUNTS. DONE "
        "NOTES$ NIP READ . COUNTS. RD ACREAD-TEXT NIP . DONE DEPTH . CR",
    ])
    assert ints(lines[0]) == [DISCLOSURE, 1, 0, OK, 1, 1, len("The quarterly report."), 0]


def test_a_document_larger_than_described(forth):
    # An owner that understates the size is still held to the room.
    lines = run(forth, [
        "NOTES$ 3 DOC! NAME 5 DOC-UNDERSTATE ! NOTES$ NIP 5 - READ . COUNTS. "
        "RD ACREAD-TEXT NIP . DONE 0 DOC-UNDERSTATE ! DEPTH . CR",
    ])
    assert ints(lines[0]) == [DISCLOSURE, 1, 1, 0, 0]


def test_only_text_is_read(forth):
    lines = run(forth, [
        "BAD 4 5 DOC! NAME 100000 READ . RD ACREAD-TEXT NIP . DONE DEPTH . CR",
    ])
    assert ints(lines[0]) == [FAILED, 0, 0]


def test_a_run_reads_only_with_its_grants(forth):
    lines = run(forth, [
        # A facet without the document's entries grants nothing.
        "NOTES$ 3 DOC! NAME 0 ENTRIES ! AUTHORITY ATTACH "
        "LOC SRC AM @ 100000 RD ACREAD-READ . COUNTS. DONE CR",
        # A run past its deadline reads nothing.
        "-1 ENTRIES ! AUTHORITY ATTACH -1 AM @ AMRUN.DEADLINE-MS ! "
        "LOC SRC AM @ 100000 RD ACREAD-READ . COUNTS. DONE DEPTH . CR",
    ])
    assert ints(lines[0]) == [FAILED, 0, 0]
    assert ints(lines[1]) == [FAILED, 0, 0, 0]


def test_a_document_not_attached_is_unavailable(forth):
    lines = run(forth, [
        "NOTES$ 3 DOC! NAME -1 ENTRIES ! AUTHORITY SRC RCLI-CLEAR "
        "LOC SRC AM @ 100000 RD ACREAD-READ . COUNTS. RD ACREAD-FREE DEPTH . CR",
        # A locator that is not exact names no version to read.
        "ATTACH LOC QLOC-INIT LOC SRC AM @ 100000 RD ACREAD-READ . DONE DEPTH . CR",
    ])
    assert ints(lines[0]) == [UNAVAILABLE, 0, 0, 0]
    assert ints(lines[1]) == [FAILED, 0]


def test_freeing_wipes_the_text(forth):
    lines = run(forth, [
        "VARIABLE AT LONG 64 6 DOC! NAME 100000 READ . RD ACREAD-TEXT DROP AT ! "
        "DONE : WIPED?  ( -- flag ) -1 64 16 DO AT @ I + C@ IF DROP 0 THEN LOOP ; "
        "WIPED? . DEPTH . CR",
    ])
    assert ints(lines[0]) == [OK, -1, 0]
