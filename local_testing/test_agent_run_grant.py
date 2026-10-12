#!/usr/bin/env python3
"""One-use grants for an Agent run's requests (agent/run-grant.f).

A run grants a request its facet allows with the flags asked for, while
its Mandate is active; a grant on the Mandate's say alone is only for
observing; a grant lasts a minute and never past the run's deadline; and
it is bound to the exact request, so the bus consumes it once.
"""

from __future__ import annotations

import pytest

from native_forth import NativeForth


PRELUDE = r"""
CREATE HD-RAW PHEAD-SIZE 7 + ALLOT  HD-RAW 7 + -8 AND CONSTANT HD
VARIABLE ROOT  VARIABLE CHILD  VARIABLE AM
CREATE MD-RAW MAND-SIZE 7 + ALLOT  MD-RAW 7 + -8 AND CONSTANT MD
CREATE FC-RAW CFACET-SIZE 7 + ALLOT  FC-RAW 7 + -8 AND CONSTANT FC
HD PHEAD-INIT HD PHEAD.ID 32 4 FILL HD PHEAD.CURRENT-ROOT 32 9 FILL
777 CTX-NEW THROW ROOT !  HD ROOT @ CTX.PRACTICE !
\ Two operations on target 5, generation 1: one that observes, one that
\ mutates.
CREATE READ-CAP CAP-DESC ALLOT  READ-CAP CAP-DESC-INIT
CREATE WRITE-CAP CAP-DESC ALLOT  WRITE-CAP CAP-DESC-INIT
CREATE SAVE-CAP CAP-DESC ALLOT  SAVE-CAP CAP-DESC-INIT
: READ$  ( -- a u ) S" doc.read" ;  : WRITE$  ( -- a u ) S" doc.write" ;
: SAVE$  ( -- a u ) S" doc.save" ;
SAVE$ SAVE-CAP CAP.ID-U ! SAVE-CAP CAP.ID-A !
CAP-E-MUTATE SAVE-CAP CAP.EFFECTS !  CAP-K-COMMAND SAVE-CAP CAP.KIND !
CFENTRY-F-INVOKE CFENTRY-F-REVIEW-COMMIT OR CONSTANT REVIEWED
READ$ READ-CAP CAP.ID-U ! READ-CAP CAP.ID-A !
CAP-E-OBSERVE READ-CAP CAP.EFFECTS !  CAP-K-RESOURCE READ-CAP CAP.KIND !
WRITE$ WRITE-CAP CAP.ID-U ! WRITE-CAP CAP.ID-A !
CAP-E-MUTATE WRITE-CAP CAP.EFFECTS !  CAP-K-COMMAND WRITE-CAP CAP.KIND !
CFENTRY-F-INVOKE CFENTRY-F-AUTO-OBSERVE OR CONSTANT AUTO-READ
\ A run whose facet lets it read target 5 automatically, invoke a write
\ of it, and save it on review; its Mandate is read-only.
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
    5 1 CAP-E-OBSERVE AUTO-READ 4096 READ$ FC CFACET-ADD THROW
    5 1 CAP-E-MUTATE CFENTRY-F-INVOKE 4096 WRITE$ FC CFACET-ADD THROW
    5 1 CAP-E-MUTATE REVIEWED 4096 SAVE$ FC CFACET-ADD THROW
    MD MAND-INIT
    MD MAND.ID 32 22 FILL
    HD PHEAD.ID MD MAND.PRACTICE-ID RID-COPY
    FC CFACET.ID MD MAND.INPUT-FACET-ID RID-COPY
    FC CFACET.ID MD MAND.DISCLOSURE-FACET-ID RID-COPY
    ROOT @ CTX.EPOCH @ MD MAND.ACTIVATION-EPOCH !
    CPRINC-AGENT MD MAND.PRINCIPAL !
    CHILD @ CTX.ID @ MD MAND.CONTEXT-ID !
    CHILD @ CTX.GENERATION @ MD MAND.CONTEXT-GENERATION !
    CAP-E-OBSERVE CAP-E-MUTATE OR MD MAND.EFFECTS !
    MAND-D-READ-ONLY MD MAND.DISPOSITION !
    600000 MD MAND.TIME-BUDGET-MS !
    4096 MD MAND.DISCLOSURE-BUDGET !
    HD CHILD @ MD FC AMRUN-NEW THROW AM ! ;
AUTHORITY
CREATE SECRET 32 ALLOT  SECRET 32 7 FILL
VARIABLE BUS  VARIABLE TAB  VARIABLE BARE
: BUSES  ( -- )
    0 0 CBUS-NEW THROW BUS !  777 SECRET AHT-NEW THROW TAB !
    TAB @ BUS @ CBUS-AUTHORITY!  0 0 CBUS-NEW THROW BARE ! ;
BUSES
VARIABLE REQ
CBR-NEW THROW REQ !
\ The request: the Agent asks CAP of target ID, generation 1.
: ASK  ( cap id -- )
    REQ @ CBR.TARGET-ID ! 1 REQ @ CBR.TARGET-GEN ! REQ @ CBR.CAP !
    CPRINC-AGENT REQ @ CBR.PRINCIPAL !
    CHILD @ CTX.ID @ REQ @ CBR.CONTEXT-ID !
    CHILD @ CTX.GENERATION @ REQ @ CBR.CONTEXT-GEN !
    777 REQ @ CBR.EPOCH !
    MD MAND.ID REQ @ CBR.MANDATE-ID RID-COPY
    REQ @ CBR.INVOCATION-ID 32 9 FILL
    REQ @ CBR.HANDLE IH-INIT ;
: ISSUE  ( grant-flags facet-flags -- status ) REQ @ AM @ BUS @ AGRANT-ISSUE ;
CREATE BIND AUTH-BINDING-SIZE ALLOT
\ The bus consuming the request's grant now: the grant and the status.
: CONSUME  ( -- grant status )
    REQ @ BIND CBR-AUTH-BIND! THROW
    MS@ BIND REQ @ CBR.HANDLE TAB @ AHT-CONSUME ;
: OK?  ( status -- flag ) CBUS-S-OK = ;
: DENIED?  ( status -- flag ) CBUS-S-DENIED = ;
: INVALID?  ( status -- flag ) CBUS-S-INVALID = ;
"""

SUITE = NativeForth(("tui/applets/agent/run-grant.f",),
                    prelude=tuple(PRELUDE.strip().splitlines()))


@pytest.fixture(scope="module")
def forth():
    return SUITE.shared()


def run(forth, lines: list[str]) -> list[list[int]]:
    output = forth.run(lines, 400_000_000).decode("latin-1")
    assert "??" not in output and "not found" not in output, output[-2000:]
    return [[int(cell) for cell in line.split()]
            for line in output.replace("\r", "").split("\n") if line.strip()]


def test_a_run_grants_what_its_facet_allows(forth):
    rows = run(forth, [
        # Reading target 5 on the Mandate's say: the grant is in the
        # request's handle, bound to it, for a minute, and consumed once.
        "READ-CAP 5 ASK AGR-F-MANDATE-AUTO AUTO-READ ISSUE OK? . "
        "REQ @ CBR.HANDLE IH-VALID? . CONSUME OK? . DUP AGR.FLAGS @ AGR-F-MANDATE-AUTO = . "
        "AGR.EXPIRES @ MS@ - DUP 60000 <= SWAP 59000 > AND . "
        "CONSUME NIP OK? . DEPTH . CR",
        # The bus refuses the grant for any other request.
        "READ-CAP 5 ASK AGR-F-MANDATE-AUTO AUTO-READ ISSUE DROP "
        "REQ @ CBR.MANDATE-ID RID-CLEAR CONSUME NIP OK? . DEPTH . CR",
    ])
    assert rows == [[-1, -1, -1, -1, -1, 0, 0], [0, 0]]


def test_a_run_grants_nothing_else(forth):
    rows = run(forth, [
        # Another target, or flags the facet entry lacks.
        "READ-CAP 6 ASK AGR-F-MANDATE-AUTO AUTO-READ ISSUE DENIED? . "
        "REQ @ CBR.HANDLE IH-VALID? . "
        "READ-CAP 5 ASK AGR-F-REVIEWED-COMMIT CFENTRY-F-INVOKE CFENTRY-F-REVIEW-COMMIT OR "
        "ISSUE DENIED? . CR",
        # On the Mandate's say alone, a mutation is not granted, though
        # the facet lets the run invoke it.
        "WRITE-CAP 5 ASK AGR-F-MANDATE-AUTO CFENTRY-F-INVOKE ISSUE DENIED? . "
        "REQ @ CBR.HANDLE IH-VALID? . DEPTH . CR",
        # A reviewed commit the facet allows still needs the Mandate's
        # commit window, and a read-only Mandate has none.
        "SAVE-CAP 5 ASK AGR-F-REVIEWED-COMMIT REVIEWED ISSUE DENIED? . "
        "REQ @ CBR.HANDLE IH-VALID? . DEPTH . CR",
    ])
    assert rows == [[-1, 0, -1], [-1, 0, 0], [-1, 0, 0]]


def test_a_grant_ends_with_its_run(forth):
    rows = run(forth, [
        # A deadline sooner than a minute ends the grant with it.
        "READ-CAP 5 ASK MS@ 5000 + AM @ AMRUN.DEADLINE-MS ! "
        "AGR-F-MANDATE-AUTO AUTO-READ ISSUE OK? . "
        "CONSUME OK? . AGR.EXPIRES @ AM @ AMRUN.DEADLINE-MS @ = . CR",
        # A run past its deadline grants nothing.
        "READ-CAP 5 ASK -1 AM @ AMRUN.DEADLINE-MS ! "
        "AGR-F-MANDATE-AUTO AUTO-READ ISSUE DENIED? . "
        "0 AM @ AMRUN.DEADLINE-MS ! DEPTH . CR",
    ])
    assert rows == [[-1, -1, -1], [-1, 0]]


def test_what_a_grant_needs(forth):
    rows = run(forth, [
        # With no run, a request gets its grant without a Mandate's checks.
        "READ-CAP 6 ASK AGR-F-MANDATE-AUTO AUTO-READ REQ @ 0 BUS @ AGRANT-ISSUE OK? . "
        "CONSUME NIP OK? . CR",
        # A bus without an authority, or no request, gets none.
        "READ-CAP 5 ASK AGR-F-MANDATE-AUTO AUTO-READ REQ @ AM @ BARE @ AGRANT-ISSUE INVALID? . "
        "AGR-F-MANDATE-AUTO AUTO-READ 0 AM @ BUS @ AGRANT-ISSUE INVALID? . "
        "AGR-F-MANDATE-AUTO AUTO-READ REQ @ AM @ 0 AGRANT-ISSUE INVALID? . DEPTH . CR",
    ])
    assert rows == [[-1, -1], [-1, -1, -1, 0]]
