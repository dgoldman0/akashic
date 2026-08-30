#!/usr/bin/env python3
"""Minimal target-Forth oracle for UIDL semantic-provider records and events.

The rich-terminal vertical gate permits a small executable oracle here, not a
second cold load of the complete TUI closure.  This test extracts the two
semantic-provider sections verbatim from ``uidl-tui.f``, surrounds them with
an explicit one-element lifecycle host, and executes those actual definitions
in the target Forth.
"""

from __future__ import annotations

from pathlib import Path
import sys


LOCAL_TESTING = Path(__file__).resolve().parent
AKASHIC_ROOT = LOCAL_TESTING.parent
UIDL_TUI_SOURCE = AKASHIC_ROOT / "akashic" / "tui" / "uidl-tui.f"
sys.path.insert(0, str(LOCAL_TESTING))

from akashic_tui import Profile, PROFILES, build_image, smoke  # noqa: E402


PROFILE_NAME = "uidl-semantic-provider-byte-oracle"
ORACLE_PATH = "local_testing/utui-sem-oracle.f"
SMOKE_MAX_STEPS = 200_000_000
SMOKE_TIMEOUT_SECONDS = 12.0

DECLARATIONS_START = "0 CONSTANT UTUI-SEMANTIC-S-OK\n"
DECLARATIONS_END = (
    "\\ =====================================================================\n"
    "\\  §1d — Dynamic Sidecar Helpers\n"
)
RUNTIME_START = (
    ": _UTUI-SEMANTIC-CANONICAL-RESULT  "
    "( bytes status -- bytes status )\n"
)
RUNTIME_END = ": _UTUI-RESOLVED-VALID-BODY?  ( record available -- flag )\n"


def _extract_unique_section(source: str, start: str, end: str) -> str:
    """Return one exact production-source section and reject marker drift."""

    assert source.count(start) == 1, f"semantic start marker drift: {start!r}"
    assert source.count(end) == 1, f"semantic end marker drift: {end!r}"
    start_at = source.index(start)
    end_at = source.index(end, start_at)
    assert start_at < end_at
    return source[start_at:end_at].rstrip()


_UIDL_TUI_TEXT = UIDL_TUI_SOURCE.read_text(encoding="utf-8")
SEMANTIC_DECLARATIONS = _extract_unique_section(
    _UIDL_TUI_TEXT,
    DECLARATIONS_START,
    DECLARATIONS_END,
)
SEMANTIC_RUNTIME = _extract_unique_section(
    _UIDL_TUI_TEXT,
    RUNTIME_START,
    RUNTIME_END,
)


ORACLE_STUBS = r'''\ uidl-semantic-provider-oracle.f
PROVIDED uidl-semantic-provider-oracle

\ Explicit minimal host for the verbatim UIDL-TUI semantic sections below.
4 CONSTANT _UTUI-MAX-ELEMS
42 CONSTANT _usp-elem
1 CONSTANT _usp-index

VARIABLE _UTUI-DOC-LOADED
VARIABLE _usp-dirty-count
VARIABLE _usp-dirty-throw
CREATE _usp-sidecar 8 ALLOT

: 3DROP  ( a b c -- )  DROP 2DROP ;

: UIDL-ELEM-INDEX?  ( elem -- index flag )
    _usp-elem = IF _usp-index -1 ELSE 0 0 THEN ;
: UIDL-FIRST-CHILD  ( elem -- child|0 )  DROP 0 ;
: UIDL-NEXT-SIB     ( elem -- sibling|0 )  DROP 0 ;

: _UTUI-SIDECAR  ( elem -- sidecar )  DROP _usp-sidecar ;
: _UTUI-SC-WPTR@  ( sidecar -- widget|0 )  @ ;

: UIDL-DIRTY!  ( elem -- )
    DROP
    _usp-dirty-throw @ IF -700 THROW THEN
    1 _usp-dirty-count +! ;

\ The extracted capture keeps its pointer, alignment, length, and wrap
\ checks.  This tiny host has no other authoritative UIDL storage, so every
\ valid caller allocation is disjoint.
: UTUI-STORAGE-DISJOINT?  ( address length -- flag )
    MSPAN-NONWRAPPING? ;
'''


ORACLE_RUNTIME_PREREQUISITES = r'''\ The production resolved-state section
\ defines this immediately before the extracted semantic runtime.
-1 1 RSHIFT CONSTANT _UTUI-RS-SIGNED-MAX
'''


ORACLE_CASES = r'''\ Test providers and byte-oracle cases.
VARIABLE _usp-fails
VARIABLE _usp-checks
VARIABLE _usp-depth
VARIABLE _usp-out-dst
VARIABLE _usp-out-cap
VARIABLE _usp-cb-elem
VARIABLE _usp-cb-dst
VARIABLE _usp-cb-cap
VARIABLE _usp-reenter
VARIABLE _usp-next-revision
VARIABLE _usp-fill-byte
VARIABLE _usp-key-a
VARIABLE _usp-key-b
VARIABLE _usp-event-count
VARIABLE _usp-event-elem
VARIABLE _usp-event-context
VARIABLE _usp-event-intent
VARIABLE _usp-event-touch

CREATE _usp-record-storage 263 ALLOT
CREATE _usp-payload-storage 87 ALLOT
CREATE _usp-intent-storage 79 ALLOT

: _usp-record  ( -- address )
    _usp-record-storage 7 + 7 INVERT AND ;
: _usp-payload  ( -- address )
    _usp-payload-storage 7 + 7 INVERT AND ;
: _usp-intent  ( -- address )
    _usp-intent-storage 7 + 7 INVERT AND ;

: _usp-intent!  ( family root child kind modifiers revision scalar reserved -- )
    _usp-intent 56 + !
    _usp-intent 48 + !
    _usp-intent 40 + !
    _usp-intent 32 + !
    _usp-intent 24 + !
    _usp-intent 16 + !
    _usp-intent 8 + !
    _usp-intent ! ;

: _usp-assert  ( flag -- )
    1 _usp-checks +!
    0= IF
        1 _usp-fails +!
        ." UIDL SEMANTIC ASSERT " _usp-checks @ . CR
    THEN ;

: _usp-stack  ( -- )
    DEPTH DUP _usp-depth @ <> IF
        ." UIDL SEMANTIC STACK " _usp-depth @ . ." -> " DUP . CR .S CR
    THEN
    _usp-depth @ = _usp-assert ;

: _usp-filled?  ( address length byte -- flag )
    _usp-fill-byte !
    0 ?DO
        DUP I + C@ _usp-fill-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _usp-zero-provider
    ( elem context destination capacity -- payload-bytes status )
    2DROP 2DROP 0 UTUI-SEMANTIC-S-OK ;

: _usp-two-result  ( destination capacity -- payload-bytes status )
    _usp-out-cap ! _usp-out-dst !
    _usp-out-dst @ 0= IF 80 UTUI-SEMANTIC-S-OK EXIT THEN
    _usp-out-cap @ 80 U< IF 0 UTUI-SEMANTIC-S-CAPACITY EXIT THEN

    40 _usp-out-dst @ !
    3 _usp-out-dst @ 8 + !
    1 _usp-out-dst @ 16 + !
    _usp-key-a @ _usp-out-dst @ 24 + !
    101 _usp-out-dst @ 32 + !

    40 _usp-out-dst @ 40 + !
    4 _usp-out-dst @ 48 + !
    1 _usp-out-dst @ 56 + !
    _usp-key-b @ _usp-out-dst @ 64 + !
    202 _usp-out-dst @ 72 + !
    80 UTUI-SEMANTIC-S-OK ;

: _usp-two-provider
    ( elem context destination capacity -- payload-bytes status )
    2SWAP 2DROP _usp-two-result ;

: _usp-callback-args!  ( elem context destination capacity -- )
    _usp-cb-cap ! _usp-cb-dst ! DROP _usp-cb-elem ! ;

: _usp-revision-provider
    ( elem context destination capacity -- payload-bytes status )
    _usp-callback-args!
    _usp-reenter @ _usp-cb-dst @ 0<> AND IF
        0 _usp-reenter !
        _usp-next-revision @ _usp-cb-elem @ UTUI-SEMANTIC-REVISION!
            UTUI-SEMANTIC-S-OK = _usp-assert
    THEN
    _usp-cb-dst @ _usp-cb-cap @ _usp-two-result ;

: _usp-layout-provider
    ( elem context destination capacity -- payload-bytes status )
    _usp-callback-args!
    _usp-reenter @ _usp-cb-dst @ 0<> AND IF
        0 _usp-reenter !
        _UTUI-SEMANTIC-RESOLVED-BOUNDARY
    THEN
    _usp-cb-dst @ _usp-cb-cap @ _usp-two-result ;

: _usp-event-provider  ( elem context intent -- status )
    _usp-event-intent ! _usp-event-context ! _usp-event-elem !
    1 _usp-event-count +!
    _usp-event-elem @ _usp-elem = _usp-assert
    _usp-event-context @ 800 = _usp-assert
    _usp-event-intent @ _usp-intent <> _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-FAMILY@ 3 = _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-ROOT-KEY@ 11 = _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-CHILD-KEY@ 12 = _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-KIND@
        UTUI-SEMANTIC-EVENT-ACTIVATE = _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-MODIFIERS@ 5 = _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-REVISION@
        _usp-intent 40 + @ = _usp-assert
    _usp-event-intent @ UTUI-SEMANTIC-INTENT-SCALAR-OFFSET@
        0= _usp-assert
    _usp-event-touch @ IF
        _usp-event-elem @ UTUI-SEMANTIC-TOUCH
            UTUI-SEMANTIC-S-OK = _usp-assert
    THEN
    UTUI-SEMANTIC-S-OK ;

: _usp-event-reenter  ( elem context intent -- status )
    _usp-event-intent ! 2DROP
    1 _usp-event-count +!
    _usp-elem _UTUI-SEMANTIC-RESOLVED-GENERATION @
        _usp-event-intent @ UTUI-SEMANTIC-INTENT-SIZE
        UTUI-SEMANTIC-DISPATCH
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-INVALID = _usp-assert 0= _usp-assert
    UTUI-SEMANTIC-S-OK ;

: _usp-event-throw  ( elem context intent -- status )
    2DROP DROP
    1 _usp-event-count +!
    -701 THROW ;

: _usp-total-cases  ( -- )
    0 _UTUI-SEMANTIC-TOTAL? _usp-assert 56 = _usp-assert
    32 _UTUI-SEMANTIC-TOTAL? _usp-assert 88 = _usp-assert
    40 _UTUI-SEMANTIC-TOTAL? _usp-assert 96 = _usp-assert
    31 _UTUI-SEMANTIC-TOTAL? 0= _usp-assert 0= _usp-assert
    -1 _UTUI-SEMANTIC-TOTAL? 0= _usp-assert 0= _usp-assert
    _UTUI-RS-SIGNED-MAX UTUI-SEMANTIC-RECORD-HEADER-SIZE - 8 +
        _UTUI-SEMANTIC-TOTAL? 0= _usp-assert 0= _usp-assert ;

: _usp-scan-cases  ( -- )
    1 _usp-key-a ! 2 _usp-key-b !
    _usp-payload 80 _usp-two-result
        UTUI-SEMANTIC-S-OK = _usp-assert 80 = _usp-assert
    _usp-payload 7 AND 0= _usp-assert
    _usp-payload UTUI-SEMANTIC-ENTRY-BYTES@ 40 = _usp-assert
    _usp-payload UTUI-SEMANTIC-ENTRY-FAMILY@ 3 = _usp-assert
    _usp-payload UTUI-SEMANTIC-ENTRY-FAMILY-ABI@ 1 = _usp-assert
    _usp-payload UTUI-SEMANTIC-ENTRY-KEY@ 1 = _usp-assert
    _usp-payload 40 + UTUI-SEMANTIC-ENTRY-BYTES@ 40 = _usp-assert
    _usp-payload 40 + UTUI-SEMANTIC-ENTRY-FAMILY@ 4 = _usp-assert
    _usp-payload 40 + UTUI-SEMANTIC-ENTRY-FAMILY-ABI@ 1 = _usp-assert
    _usp-payload 40 + UTUI-SEMANTIC-ENTRY-KEY@ 2 = _usp-assert
    _usp-payload 80 _UTUI-SEMANTIC-PAYLOAD-VALID?
        _usp-assert 2 = _usp-assert

    1 _usp-payload 64 + !
    _usp-payload 80 _UTUI-SEMANTIC-PAYLOAD-VALID?
        0= _usp-assert 0= _usp-assert
    2 _usp-payload 64 + !
    24 _usp-payload !
    _usp-payload 80 _UTUI-SEMANTIC-PAYLOAD-VALID?
        0= _usp-assert 0= _usp-assert ;

: _usp-setup  ( -- )
    -1 _UTUI-DOC-LOADED !
    99 _usp-sidecar !
    0 _usp-dirty-count ! 0 _usp-dirty-throw !
    _UTUI-SEMANTIC-CLEAR-ALL
    _UTUI-SEMANTIC-SCRATCH-CLEAR
    _UTUI-SEMANTIC-EVENT-CLEAR
    0 _UTUI-SEMANTIC-RESOLVED-GENERATION !
    0 _usp-event-count ! 0 _usp-event-touch !
    _UTUI-SEMANTIC-RESOLVED-BOUNDARY ;

: _usp-set-and-highwater  ( -- )
    0 _usp-sidecar !
    1 ['] _usp-zero-provider 0 700 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    99 _usp-sidecar !

    1 ['] _usp-zero-provider 0 700 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-index _UTUI-SEMANTIC-BINDING
    DUP _UTUI-SB.REVISION @ 1 = _usp-assert
    DUP _UTUI-SB.SNAPSHOT-XT @ ['] _usp-zero-provider = _usp-assert
    DUP _UTUI-SB.EVENT-XT @ 0= _usp-assert
    _UTUI-SB.CONTEXT @ 700 = _usp-assert
    _usp-dirty-count @ 1 = _usp-assert ;

: _usp-zero-capture  ( -- )
    _usp-elem UTUI-SEMANTIC-SIZE
        UTUI-SEMANTIC-S-OK = _usp-assert 56 = _usp-assert
    _usp-record 256 165 FILL
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-OK = _usp-assert 56 = _usp-assert
    _usp-record 56 UTUI-SEMANTIC-RECORD-VALID? _usp-assert
    _usp-record @ _UTUI-SEMANTIC-RECORD-MAGIC = _usp-assert
    _usp-record 16 + @ 56 = _usp-assert
    _usp-record 24 + @ _usp-index = _usp-assert
    _usp-record 32 + @ 1 = _usp-assert
    _usp-record 40 + @ 1 = _usp-assert
    _usp-record 48 + @ 0= _usp-assert ;

: _usp-clear-and-republish  ( -- )
    _usp-elem UTUI-SEMANTIC-CLEAR
        UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-index _UTUI-SEMANTIC-BINDING
    DUP _UTUI-SB.REVISION @ 1 = _usp-assert
    DUP _UTUI-SB.SNAPSHOT-XT @ 0= _usp-assert
    DUP _UTUI-SB.EVENT-XT @ 0= _usp-assert
    _UTUI-SB.CONTEXT @ 0= _usp-assert
    _usp-elem UTUI-SEMANTIC-SIZE
        UTUI-SEMANTIC-S-UNSUPPORTED = _usp-assert 0= _usp-assert

    1 ['] _usp-two-provider 0 701 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    _usp-index _UTUI-SEMANTIC-BINDING
        _UTUI-SB.SNAPSHOT-XT @ 0= _usp-assert
    2 ['] _usp-two-provider 0 701 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert

    -1 _usp-dirty-throw !
    3 ['] _usp-zero-provider 0 702 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    0 _usp-dirty-throw !
    _usp-index _UTUI-SEMANTIC-BINDING
    DUP _UTUI-SB.REVISION @ 2 = _usp-assert
    DUP _UTUI-SB.SNAPSHOT-XT @ ['] _usp-two-provider = _usp-assert
    DUP _UTUI-SB.EVENT-XT @ 0= _usp-assert
    _UTUI-SB.CONTEXT @ 701 = _usp-assert ;

: _usp-two-capture  ( -- )
    1 _usp-key-a ! 2 _usp-key-b !
    _usp-record 256 0 FILL
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-OK = _usp-assert 136 = _usp-assert
    _usp-record 136 UTUI-SEMANTIC-RECORD-VALID? _usp-assert
    _usp-record @ _UTUI-SEMANTIC-RECORD-MAGIC = _usp-assert
    _usp-record 16 + @ 136 = _usp-assert
    _usp-record 32 + @ 2 = _usp-assert
    _usp-record 48 + @ 2 = _usp-assert
    _usp-record UTUI-SEMANTIC-RECORD-PAYLOAD@ 80 = _usp-assert
    DUP UTUI-SEMANTIC-ENTRY-BYTES@ 40 = _usp-assert
    DUP UTUI-SEMANTIC-ENTRY-FAMILY@ 3 = _usp-assert
    DUP UTUI-SEMANTIC-ENTRY-FAMILY-ABI@ 1 = _usp-assert
    DUP UTUI-SEMANTIC-ENTRY-KEY@ 1 = _usp-assert
    40 + UTUI-SEMANTIC-ENTRY-KEY@ 2 = _usp-assert ;

: _usp-publication-failures  ( -- )
    _usp-record 136 165 FILL
    _usp-elem _usp-record 135 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-CAPACITY = _usp-assert 0= _usp-assert
    _usp-record 136 165 _usp-filled? _usp-assert

    2 _usp-key-a ! 1 _usp-key-b !
    3 _usp-elem UTUI-SEMANTIC-REVISION!
        UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-record 256 165 FILL
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-INVALID = _usp-assert 0= _usp-assert
    _usp-record @ 0= _usp-assert
    _usp-record 136 UTUI-SEMANTIC-RECORD-VALID? 0= _usp-assert

    1 _usp-key-a ! 2 _usp-key-b !
    4 _usp-elem UTUI-SEMANTIC-REVISION!
        UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-OK = _usp-assert 136 = _usp-assert
    _usp-record @ _UTUI-SEMANTIC-RECORD-MAGIC = _usp-assert ;

: _usp-reentrant-invalidation  ( -- )
    5 ['] _usp-revision-provider 0 703 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    6 _usp-next-revision ! -1 _usp-reenter !
    _usp-record 256 165 FILL
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-INVALID = _usp-assert 0= _usp-assert
    _usp-record @ 0= _usp-assert
    _usp-index _UTUI-SEMANTIC-BINDING _UTUI-SB.REVISION @
        6 = _usp-assert

    7 ['] _usp-layout-provider 0 704 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    _UTUI-SEMANTIC-RESOLVED-GENERATION @ 1+ >R
    -1 _usp-reenter !
    _usp-record 256 165 FILL
    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-INVALID = _usp-assert 0= _usp-assert
    _usp-record @ 0= _usp-assert
    _UTUI-SEMANTIC-RESOLVED-GENERATION @ R> = _usp-assert

    _usp-elem _usp-record 256 UTUI-SEMANTIC-CAPTURE
        UTUI-SEMANTIC-S-OK = _usp-assert 136 = _usp-assert
    _usp-record 136 UTUI-SEMANTIC-RECORD-VALID? _usp-assert ;

: _usp-dispatch-current  ( -- status )
    _usp-elem _UTUI-SEMANTIC-RESOLVED-GENERATION @
    _usp-intent UTUI-SEMANTIC-INTENT-SIZE UTUI-SEMANTIC-DISPATCH ;

: _usp-event-cases  ( -- )
    3 11 12 UTUI-SEMANTIC-EVENT-ACTIVATE 5 8 0 0 _usp-intent!
    8 ['] _usp-two-provider 0 799 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-dispatch-current
        UTUI-SEMANTIC-S-UNSUPPORTED = _usp-assert
    _usp-event-count @ 0= _usp-assert

    9 ['] _usp-two-provider ['] _usp-event-provider
        800 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    9 _usp-intent 40 + !
    _usp-index _UTUI-SEMANTIC-BINDING
        _UTUI-SB.EVENT-XT @ ['] _usp-event-provider = _usp-assert
    _usp-dispatch-current UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-event-count @ 1 = _usp-assert

    8 _usp-intent 40 + !
    _usp-dispatch-current
        UTUI-SEMANTIC-S-UNAVAILABLE = _usp-assert
    9 _usp-intent 40 + !
    _usp-elem _UTUI-SEMANTIC-RESOLVED-GENERATION @ 1+
        _usp-intent UTUI-SEMANTIC-INTENT-SIZE UTUI-SEMANTIC-DISPATCH
        UTUI-SEMANTIC-S-UNAVAILABLE = _usp-assert

    0 _usp-intent !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    3 _usp-intent !
    0 _usp-intent 8 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    11 _usp-intent 8 + !
    2 _usp-intent 24 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    UTUI-SEMANTIC-EVENT-ACTIVATE _usp-intent 24 + !
    64 _usp-intent 32 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    5 _usp-intent 32 + !
    0 _usp-intent 40 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    9 _usp-intent 40 + !
    1 _usp-intent 48 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    0 _usp-intent 48 + !
    1 _usp-intent 56 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    0 _usp-intent 56 + !
    _usp-elem _UTUI-SEMANTIC-RESOLVED-GENERATION @
        _usp-intent 63 UTUI-SEMANTIC-DISPATCH
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    _usp-elem _UTUI-SEMANTIC-RESOLVED-GENERATION @
        _usp-intent 1+ UTUI-SEMANTIC-INTENT-SIZE UTUI-SEMANTIC-DISPATCH
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    _usp-event-count @ 1 = _usp-assert

    _usp-index _UTUI-SEMANTIC-BINDING _UTUI-SB.REVISION @ >R
    -1 _usp-dirty-throw !
    _usp-elem UTUI-SEMANTIC-TOUCH
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    0 _usp-dirty-throw !
    _usp-index _UTUI-SEMANTIC-BINDING _UTUI-SB.REVISION @
        R> = _usp-assert

    -1 _usp-event-touch !
    _usp-dispatch-current UTUI-SEMANTIC-S-OK = _usp-assert
    0 _usp-event-touch !
    _usp-event-count @ 2 = _usp-assert
    _usp-index _UTUI-SEMANTIC-BINDING _UTUI-SB.REVISION @
        10 = _usp-assert

    11 ['] _usp-two-provider ['] _usp-event-reenter
        801 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    11 _usp-intent 40 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-event-count @ 3 = _usp-assert
    _UTUI-SE-EVENT-ACTIVE @ 0= _usp-assert
    _UTUI-SE-ACTIVE @ 0= _usp-assert

    12 ['] _usp-two-provider ['] _usp-event-throw
        802 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    12 _usp-intent 40 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-INVALID = _usp-assert
    _usp-event-count @ 4 = _usp-assert
    _UTUI-SE-EVENT-ACTIVE @ 0= _usp-assert
    13 ['] _usp-two-provider ['] _usp-event-provider
        800 _usp-elem UTUI-SEMANTIC-SET
        UTUI-SEMANTIC-S-OK = _usp-assert
    13 _usp-intent 40 + !
    _usp-dispatch-current UTUI-SEMANTIC-S-OK = _usp-assert
    _usp-event-count @ 5 = _usp-assert

    -1 _usp-index _UTUI-SEMANTIC-BINDING _UTUI-SB.REVISION !
    _usp-dirty-count @ >R
    _usp-elem UTUI-SEMANTIC-TOUCH
        UTUI-SEMANTIC-S-INVALID = _usp-assert
    _usp-dirty-count @ R> = _usp-assert
    _usp-index _UTUI-SEMANTIC-BINDING _UTUI-SB.REVISION @
        -1 = _usp-assert ;

: _usp-run  ( -- )
    0 _usp-fails ! 0 _usp-checks ! DEPTH _usp-depth !
    _usp-setup _usp-stack
    _usp-total-cases _usp-stack
    _usp-scan-cases _usp-stack
    _usp-set-and-highwater _usp-stack
    _usp-zero-capture _usp-stack
    _usp-clear-and-republish _usp-stack
    _usp-two-capture _usp-stack
    _usp-publication-failures _usp-stack
    _usp-reentrant-invalidation _usp-stack
    _usp-event-cases _usp-stack
    _usp-fails @ 0= IF
        ." UIDL SEMANTIC PASS " _usp-checks @ .
    ELSE
        ." UIDL SEMANTIC FAIL " _usp-fails @ . ." / " _usp-checks @ .
    THEN CR ;

_usp-run
'''


ORACLE_SOURCE = "\n\n".join(
    (
        ORACLE_STUBS.strip(),
        SEMANTIC_DECLARATIONS,
        ORACLE_RUNTIME_PREREQUISITES.strip(),
        SEMANTIC_RUNTIME,
        ORACLE_CASES.strip(),
    )
) + "\n"

AUTOEXEC = rf'''\ autoexec.f - minimal UIDL semantic-provider byte oracle
ENTER-USERLAND
." [akashic] loading minimal UIDL semantic-provider byte oracle" CR
REQUIRE utils/memory-span.f
REQUIRE {ORACLE_PATH}
'''


def test_uidl_semantic_provider_byte_oracle(tmp_path: Path) -> None:
    assert _UIDL_TUI_TEXT.count(DECLARATIONS_START) == 1
    assert _UIDL_TUI_TEXT.count(DECLARATIONS_END) == 1
    assert _UIDL_TUI_TEXT.count(RUNTIME_START) == 1
    assert _UIDL_TUI_TEXT.count(RUNTIME_END) == 1
    assert SEMANTIC_DECLARATIONS.startswith(DECLARATIONS_START)
    assert SEMANTIC_RUNTIME.startswith(RUNTIME_START)
    assert "UTUI-SEMANTIC-CAPTURE" in SEMANTIC_RUNTIME
    assert "UTUI-SEMANTIC-TOUCH" in SEMANTIC_RUNTIME
    assert "UTUI-SEMANTIC-DISPATCH" in SEMANTIC_RUNTIME
    assert "UTUI-SEMANTIC-RECORD-VALID?" in SEMANTIC_RUNTIME
    assert "REQUIRE tui/uidl-tui.f" not in ORACLE_SOURCE
    assert max(len(line.encode("utf-8")) for line in ORACLE_SOURCE.splitlines()) <= 255

    previous = PROFILES.get(PROFILE_NAME)
    PROFILES[PROFILE_NAME] = Profile(
        roots=("utils/memory-span.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("UIDL SEMANTIC PASS",),
        stable_markers=("UIDL SEMANTIC PASS",),
        failure_markers=(
            "UIDL SEMANTIC FAIL",
            "UIDL SEMANTIC ASSERT",
            "UIDL SEMANTIC STACK",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        initial_files=((ORACLE_PATH, ORACLE_SOURCE.encode("utf-8")),),
        linked=False,
        include_large_sample=False,
    )
    try:
        image = build_image(
            PROFILE_NAME,
            tmp_path / "uidl-semantic-provider.img",
        )
        assert smoke(
            PROFILE_NAME,
            image,
            cols=80,
            rows=24,
            max_steps=SMOKE_MAX_STEPS,
            timeout=SMOKE_TIMEOUT_SECONDS,
        )
    finally:
        if previous is None:
            PROFILES.pop(PROFILE_NAME, None)
        else:
            PROFILES[PROFILE_NAME] = previous


if __name__ == "__main__":
    import tempfile

    with tempfile.TemporaryDirectory() as directory:
        test_uidl_semantic_provider_byte_oracle(Path(directory))
