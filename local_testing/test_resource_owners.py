#!/usr/bin/env python3
"""The directory of resource owners (interop/resource-owners.f): who
publishes which owner id, what attaching a locator through it calls, and
what the directory refuses."""

from __future__ import annotations

import pytest

from native_forth import NativeForth


S_OK, S_INVALID, S_TAKEN, S_NOT_FOUND, S_NOMEM, S_REFUSED = range(6)

PRELUDE = r"""
\ Two instances, and a later one with the first's id: only their ids and
\ generations matter to the directory.
CREATE I1 COMP-INST ALLOT  I1 COMP-INST 0 FILL  7 I1 CINST.ID !  1 I1 CINST.GENERATION !
CREATE I2 COMP-INST ALLOT  I2 COMP-INST 0 FILL  8 I2 CINST.ID !  1 I2 CINST.GENERATION !
CREATE I1B COMP-INST ALLOT I1B COMP-INST 0 FILL 7 I1B CINST.ID ! 2 I1B CINST.GENERATION !
\ An instance the registry never held.
CREATE I3 COMP-INST ALLOT  I3 COMP-INST 0 FILL  9 I3 CINST.ID !  1 I3 CINST.GENERATION !
CREG-NEW DROP CONSTANT REG
: HOLD  ( -- ) I1 REG CREG-INST+ DROP I2 REG CREG-INST+ DROP I1B REG CREG-INST+ DROP ;
HOLD
CREATE DIR ROWN-SIZE ALLOT  REG DIR ROWN-INIT
: OWNER$  ( -- a u ) S" org.akashic.library" ;
: OTHER$  ( -- a u ) S" org.akashic.notes" ;
CREATE LONG 65 ALLOT  LONG 65 CHAR x FILL
CREATE ROOT1 64 ALLOT  CREATE ROOT2 64 ALLOT

\ A stand-in attach word that keeps what it was given.
CREATE GOT 6 CELLS ALLOT
: ATTACH  ( locator root context rreg binding result -- status )
    5 0 DO GOT 5 I - CELLS + ! LOOP GOT ! 42 ;
: ATTACH2  ( locator root context rreg binding result -- status )
    2DROP 2DROP 2DROP 43 ;

\ A policy that lets only I2 publish OTHER$, and anyone the rest.
: POLICY  ( owner-a owner-u instance context -- allowed? )
    DROP >R OTHER$ COMPARE 0= IF R> I2 = ELSE R> DROP -1 THEN ;

\ A locator naming OWNER$, and one naming an owner nobody publishes.
CREATE REF RREF-SIZE ALLOT  REF RREF-INIT  REF RREF.ID 32 7 FILL
CREATE LOC QLOC-SIZE ALLOT  OWNER$ REF LOC QLOC-IDENTITY! DROP
CREATE LOC2 QLOC-SIZE ALLOT  S" org.akashic.nobody" REF LOC2 QLOC-IDENTITY! DROP
CREATE BAD QLOC-SIZE ALLOT  BAD QLOC-SIZE 0 FILL
: FRESH  ( -- ) DIR ROWN-FREE REG DIR ROWN-INIT HOLD ;
: PUB  ( a u root xt inst -- status ) DIR ROWN-PUBLISH ;
"""

SUITE = NativeForth(("interop/resource-owners.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str]) -> list[list[str]]:
    output = forth.run(lines, 400_000_000).decode("latin-1")
    assert "??" not in output and "not found" not in output, output[-2000:]
    return [line.split() for line in output.splitlines() if line.strip()]


def ints(row: list[str]) -> list[int]:
    return [int(cell) for cell in row]


def test_publishing_finding_and_withdrawing(forth):
    rows = run(forth, [
        "FRESH OWNER$ ROOT1 ' ATTACH I1 PUB . DIR ROWN-COUNT@ . "
        "OWNER$ DIR ROWN-FIND DUP ROWN-E.ROOT @ ROOT1 = . ROWN-E.ATTACH-XT @ ' ATTACH = . "
        "OTHER$ DIR ROWN-FIND . CR",
        # Withdrawing leaves nothing to find; a second withdraw finds nothing.
        "OWNER$ I1 DIR ROWN-WITHDRAW . OWNER$ DIR ROWN-FIND . DIR ROWN-COUNT@ . "
        "OWNER$ I1 DIR ROWN-WITHDRAW . CR",
    ])
    assert ints(rows[0]) == [S_OK, 1, -1, -1, 0]
    assert ints(rows[1]) == [S_OK, 0, 0, S_NOT_FOUND]


def test_what_a_publication_must_carry(forth):
    rows = run(forth, [
        "FRESH 0 0 ROOT1 ' ATTACH I1 PUB . LONG 65 ROOT1 ' ATTACH I1 PUB . "
        "LONG 64 ROOT1 ' ATTACH I1 PUB . 0 19 ROOT1 ' ATTACH I1 PUB . "
        "OWNER$ 0 ' ATTACH I1 PUB . OWNER$ ROOT1 0 I1 PUB . OWNER$ ROOT1 ' ATTACH 0 PUB . "
        "OWNER$ ROOT1 ' ATTACH I3 PUB . "
        "DIR ROWN-COUNT@ . LONG 64 DIR ROWN-FIND 0<> . CR",
    ])
    assert ints(rows[0]) == [S_INVALID, S_INVALID, S_OK, S_INVALID,
                             S_INVALID, S_INVALID, S_INVALID, S_INVALID, 1, -1]


def test_one_instance_holds_an_owner(forth):
    rows = run(forth, [
        # The same instance publishing again replaces its own publication.
        "FRESH OWNER$ ROOT1 ' ATTACH I1 PUB . OWNER$ ROOT2 ' ATTACH2 I1 PUB . "
        "DIR ROWN-COUNT@ . OWNER$ DIR ROWN-FIND DUP ROWN-E.ROOT @ ROOT2 = . "
        "ROWN-E.ATTACH-XT @ ' ATTACH2 = . CR",
        # Another instance, and a later one with the same id, can neither
        # take it over nor withdraw it.
        "OWNER$ ROOT1 ' ATTACH I2 PUB . OWNER$ ROOT1 ' ATTACH I1B PUB . "
        "OWNER$ I2 DIR ROWN-WITHDRAW . OWNER$ I1B DIR ROWN-WITHDRAW . "
        "OWNER$ 0 DIR ROWN-WITHDRAW . OWNER$ DIR ROWN-FIND ROWN-E.ROOT @ ROOT2 = . CR",
    ])
    assert ints(rows[0]) == [S_OK, S_OK, 1, -1, -1]
    assert ints(rows[1]) == [S_TAKEN, S_TAKEN, S_TAKEN, S_TAKEN, S_INVALID, -1]


def test_a_policy_decides_who_publishes(forth):
    rows = run(forth, [
        "FRESH ' POLICY 0 DIR ROWN-POLICY! "
        "OTHER$ ROOT1 ' ATTACH I1 PUB . DIR ROWN-COUNT@ . "
        "OTHER$ ROOT1 ' ATTACH I2 PUB . OWNER$ ROOT1 ' ATTACH I1 PUB . DIR ROWN-COUNT@ . CR",
    ])
    assert ints(rows[0]) == [S_REFUSED, 0, S_OK, S_OK, 2]


def test_an_owner_whose_instance_is_gone(forth):
    rows = run(forth, [
        # I1 stops without withdrawing: its publication is dropped when next
        # looked up, and I2 may then publish that owner.
        "FRESH OWNER$ ROOT1 ' ATTACH I1 PUB DROP OTHER$ ROOT2 ' ATTACH I2 PUB DROP "
        "OWNER$ ROOT1 ' ATTACH I2 PUB . I1 REG CREG-INST- DROP "
        "DIR ROWN-COUNT@ . OWNER$ DIR ROWN-FIND . DIR ROWN-COUNT@ . "
        "OWNER$ ROOT1 ' ATTACH I2 PUB . OTHER$ DIR ROWN-FIND 0<> . CR",
        # Nor is it reached through an attach.
        "FRESH OWNER$ ROOT1 ' ATTACH I1 PUB DROP I1 REG CREG-INST- DROP "
        "LOC 11 12 13 14 DIR ROWN-ATTACH RACQ-S-UNAVAILABLE = . DIR ROWN-COUNT@ . CR",
    ])
    assert ints(rows[0]) == [S_TAKEN, 2, 0, 1, S_OK, -1]
    assert ints(rows[1]) == [-1, 0]


def test_the_directory_grows(forth):
    # Thirty owners, past the table's first room of eight, are all found.
    rows = run(forth, [
        "FRESH CREATE NAMES 30 8 * ALLOT "
        ": NAME  ( i -- a u ) 8 * NAMES + 8 ; "
        ": NAMES!  ( -- ) 30 0 DO S\" owner-00\" I NAME DROP SWAP MOVE "
        "I NAME DROP 6 + I 10 /MOD 48 + 2 PICK C! 48 + SWAP 1+ C! LOOP ; "
        "NAMES! : ALL  ( -- n ) 0 30 0 DO I NAME ROOT1 ['] ATTACH I1 PUB 0= - LOOP ; "
        "ALL . DIR ROWN-COUNT@ . : FOUND  ( -- n ) 0 30 0 DO I NAME DIR ROWN-FIND 0<> - LOOP ; "
        "FOUND . 29 NAME DIR ROWN-FIND 0<> . CR",
    ])
    assert ints(rows[0]) == [30, 30, 30, -1]


def test_attaching_through_the_owner(forth):
    rows = run(forth, [
        # Through the published owner, the attach word gets the locator, the
        # owner's root, and the caller's context, registry, binding and
        # result, and its status is the answer.
        "FRESH OWNER$ ROOT1 ' ATTACH I1 PUB DROP "
        "LOC 11 12 13 14 DIR ROWN-ATTACH . "
        "GOT @ LOC = . GOT CELL+ @ ROOT1 = . GOT 2 CELLS + @ . GOT 3 CELLS + @ . "
        "GOT 4 CELLS + @ . GOT 5 CELLS + @ . DEPTH . CR",
        # Nobody publishes this owner; a locator that is not one is invalid.
        "LOC2 11 12 13 14 DIR ROWN-ATTACH RACQ-S-UNAVAILABLE = . "
        "BAD 11 12 13 14 DIR ROWN-ATTACH RACQ-S-INVALID = . DEPTH . CR",
    ])
    assert ints(rows[0]) == [42, -1, -1, 11, 12, 13, 14, 0]
    assert ints(rows[1]) == [-1, -1, 0]
