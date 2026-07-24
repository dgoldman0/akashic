\ =====================================================================
\  index-record-agreement.f - Exact Streams key/record agreement
\ =====================================================================
\  A PBTREE value may name a checked semantic record only when every
\  semantic field repeated by its canonical key agrees exactly with that
\  record.  These predicates validate both inputs before reading fields.
\  They do not dereference PERSIST-REF values, open storage, mutate memory,
\  choose authority, or perform query policy.
\
\  ABI 1 observation records contain no exact thread-root/parent evidence.
\  THREAD-TIME keys are structurally recognized but always fail agreement;
\  no adapter may publish such a row until a checked successor observation
\  shape permits exact-byte verification.
\
\  Public API:
\    STREAMS-PI-SOURCE-RID-RECORD-AGREES?
\    STREAMS-PI-SOURCE-ORDER-RECORD-AGREES?
\    STREAMS-PI-ACTIVE-ATTEMPT-RECORD-AGREES?
\    STREAMS-PI-ATTEMPT-HISTORY-RECORD-AGREES?
\    STREAMS-PI-NATIVE-HEAD-RECORD-AGREES?
\    STREAMS-PI-OBSERVATION-REVISION-RECORD-AGREES?
\    STREAMS-PI-GLOBAL-TIME-RECORD-AGREES?
\    STREAMS-PI-SOURCE-TIME-RECORD-AGREES?
\    STREAMS-PI-THREAD-TIME-RECORD-AGREES?
\    STREAMS-PI-RECORD-AGREES?
\      ( key-a key-u record-a record-u -- flag )
\
\  This module owns no mutable process-global state.
\ =====================================================================

PROVIDED akashic-tui-streams-record-agreement

REQUIRE index-keys.f
REQUIRE persistence-records.f

\ ---------------------------------------------------------------------
\ Canonical field offsets
\ ---------------------------------------------------------------------

1 CONSTANT _SPIRA-SOURCE-RID-ID

1 CONSTANT _SPIRA-SOURCE-ORDER-SEQUENCE
1 STREAMS-PI-U64-SIZE + CONSTANT _SPIRA-SOURCE-ORDER-ID

1 CONSTANT _SPIRA-ATTEMPT-SOURCE-ID
1 RID-SIZE + CONSTANT _SPIRA-ATTEMPT-SEQUENCE
1 RID-SIZE + STREAMS-PI-U64-SIZE +
    CONSTANT _SPIRA-ATTEMPT-ID

1 CONSTANT _SPIRA-NATIVE-SOURCE-ID
1 RID-SIZE + CONSTANT _SPIRA-NATIVE-NAMESPACE
1 RID-SIZE + STREAMS-PI-DIGEST-SIZE +
    CONSTANT _SPIRA-NATIVE-FORMAT
1 RID-SIZE + STREAMS-PI-DIGEST-SIZE + STREAMS-PI-U64-SIZE +
    CONSTANT _SPIRA-NATIVE-KIND
1 RID-SIZE + STREAMS-PI-DIGEST-SIZE +
STREAMS-PI-U64-SIZE 2 * +
    CONSTANT _SPIRA-NATIVE-DIGEST
STREAMS-PI-NATIVE-HEAD-PREFIX-SIZE
    CONSTANT _SPIRA-NATIVE-COLLISION

1 CONSTANT _SPIRA-OBSERVATION-ID
1 RID-SIZE + CONSTANT _SPIRA-OBSERVATION-REVISION

1 CONSTANT _SPIRA-GLOBAL-SEQUENCE
1 STREAMS-PI-U64-SIZE + CONSTANT _SPIRA-GLOBAL-OBSERVATION-ID
1 STREAMS-PI-U64-SIZE + RID-SIZE +
    CONSTANT _SPIRA-GLOBAL-REVISION

1 CONSTANT _SPIRA-SOURCE-TIME-SOURCE-ID
1 RID-SIZE + CONSTANT _SPIRA-SOURCE-TIME-SEQUENCE
1 RID-SIZE + STREAMS-PI-U64-SIZE +
    CONSTANT _SPIRA-SOURCE-TIME-OBSERVATION-ID
1 RID-SIZE + STREAMS-PI-U64-SIZE + RID-SIZE +
    CONSTANT _SPIRA-SOURCE-TIME-REVISION

\ ---------------------------------------------------------------------
\ Pure decoding and equality helpers
\ ---------------------------------------------------------------------

: _SPIRA-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;

: _SPIRA-BYTES=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    2 PICK 0= 2 PICK 0= OR IF DROP 2DROP 0 EXIT THEN
    2 PICK OVER MSPAN-NONWRAPPING? 0= IF
        DROP 2DROP 0 EXIT
    THEN
    OVER OVER MSPAN-NONWRAPPING? 0= IF
        DROP 2DROP 0 EXIT
    THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _SPIRA-BE=CELL?  ( encoded-a cell-a -- flag )
    >R
    STREAMS-PI-POSITIVE-U64-BE@
    0= IF DROP R> DROP 0 EXIT THEN
    R> @ = ;

: _SPIRA-KEY-FAMILY@  ( key-a key-u -- family|0 )
    DUP 1 < IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    DROP C@ ;

\ ---------------------------------------------------------------------
\ Directory families
\ ---------------------------------------------------------------------

: _SPIRA-SOURCE-RID@  ( record-a record-u -- rid|0 )
    2DUP SPREC-SOURCE-VALID? IF
        DROP SPRS.ID EXIT
    THEN
    2DUP SPREC-SOURCE-TOMBSTONE-VALID? IF
        DROP SPRT.SOURCE-ID EXIT
    THEN
    2DROP 0 ;

: STREAMS-PI-SOURCE-RID-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP _SPIRA-SOURCE-RID@ DUP 0= IF
        DROP _SPIRA-DROP4 0 EXIT
    THEN
    >R 2DROP
    2DUP STREAMS-PI-SOURCE-RID-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-RID-ID + R@ RID=
    NIP NIP R> DROP ;

: STREAMS-PI-SOURCE-ORDER-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-SOURCE-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-SOURCE-ORDER-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-ORDER-SEQUENCE +
        R@ SPRS.CREATION-SEQUENCE _SPIRA-BE=CELL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-ORDER-ID + R@ SPRS.ID RID=
    NIP NIP R> DROP ;

: STREAMS-PI-ACTIVE-ATTEMPT-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-ATTEMPT-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-ACTIVE-ATTEMPT-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ SPRA.STATE @ OCHK-ATTEMPT-ACCEPTED <> IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-RID-ID + R@ SPRA.SOURCE-ID RID=
    NIP NIP R> DROP ;

\ ---------------------------------------------------------------------
\ Attempt-history family
\ ---------------------------------------------------------------------

: STREAMS-PI-ATTEMPT-HISTORY-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-ATTEMPT-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-ATTEMPT-SOURCE-ID + R@ SPRA.SOURCE-ID RID=
        0= IF 2DROP R> DROP 0 EXIT THEN
    OVER _SPIRA-ATTEMPT-SEQUENCE +
        R@ SPRA.ATTEMPT-SEQUENCE _SPIRA-BE=CELL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-ATTEMPT-ID + R@ SPRA.ATTEMPT-ID RID=
    NIP NIP R> DROP ;

\ ---------------------------------------------------------------------
\ Identity families
\ ---------------------------------------------------------------------

: STREAMS-PI-NATIVE-HEAD-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-NATIVE-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-NATIVE-HEAD-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-NATIVE-SOURCE-ID + R@ SPRH.SOURCE-ID RID=
        0= IF 2DROP R> DROP 0 EXIT THEN
    OVER _SPIRA-NATIVE-NAMESPACE +
        R@ SPRH.NAMESPACE STREAMS-PI-DIGEST-SIZE
        _SPIRA-BYTES= 0= IF 2DROP R> DROP 0 EXIT THEN
    OVER _SPIRA-NATIVE-FORMAT +
        R@ SPRH.OBSERVATION-FORMAT _SPIRA-BE=CELL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-NATIVE-KIND +
        R@ SPRH.NATIVE-KIND _SPIRA-BE=CELL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-NATIVE-DIGEST +
        R@ SPRH.NATIVE-DIGEST STREAMS-PI-DIGEST-SIZE
        _SPIRA-BYTES= 0= IF 2DROP R> DROP 0 EXIT THEN
    OVER _SPIRA-NATIVE-COLLISION +
        R@ SPRH.COLLISION-ORDINAL _SPIRA-BE=CELL?
    NIP NIP R> DROP ;

: STREAMS-PI-OBSERVATION-REVISION-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-OBSERVATION-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-OBSERVATION-REVISION-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-OBSERVATION-ID + R@ SPRO.OBSERVATION-ID RID=
        0= IF 2DROP R> DROP 0 EXIT THEN
    OVER _SPIRA-OBSERVATION-REVISION +
        R@ SPRO.REVISION _SPIRA-BE=CELL?
    NIP NIP R> DROP ;

\ ---------------------------------------------------------------------
\ Ordering families
\ ---------------------------------------------------------------------

: STREAMS-PI-GLOBAL-TIME-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-OBSERVATION-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-GLOBAL-TIME-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-GLOBAL-SEQUENCE +
        R@ SPRO.ACQUISITION-SEQUENCE _SPIRA-BE=CELL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-GLOBAL-OBSERVATION-ID +
        R@ SPRO.OBSERVATION-ID RID= 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-GLOBAL-REVISION +
        R@ SPRO.REVISION _SPIRA-BE=CELL?
    NIP NIP R> DROP ;

: STREAMS-PI-SOURCE-TIME-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-OBSERVATION-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    DROP >R
    2DUP STREAMS-PI-SOURCE-TIME-KEY-VALID? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-TIME-SOURCE-ID +
        R@ SPRO.SOURCE-ID RID= 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-TIME-SEQUENCE +
        R@ SPRO.ACQUISITION-SEQUENCE _SPIRA-BE=CELL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-TIME-OBSERVATION-ID +
        R@ SPRO.OBSERVATION-ID RID= 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    OVER _SPIRA-SOURCE-TIME-REVISION +
        R@ SPRO.REVISION _SPIRA-BE=CELL?
    NIP NIP R> DROP ;

: STREAMS-PI-THREAD-TIME-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    2DUP SPREC-OBSERVATION-VALID? 0= IF _SPIRA-DROP4 0 EXIT THEN
    2OVER STREAMS-PI-THREAD-TIME-KEY-VALID? 0= IF
        _SPIRA-DROP4 0 EXIT
    THEN
    _SPIRA-DROP4 0 ;

\ ---------------------------------------------------------------------
\ One generic current-family dispatcher
\ ---------------------------------------------------------------------

: STREAMS-PI-RECORD-AGREES?
  ( key-a key-u record-a record-u -- flag )
    3 PICK 3 PICK _SPIRA-KEY-FAMILY@
    DUP STREAMS-PI-F-SOURCE-RID = IF
        DROP STREAMS-PI-SOURCE-RID-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-SOURCE-ORDER = IF
        DROP STREAMS-PI-SOURCE-ORDER-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-ACTIVE-ATTEMPT = IF
        DROP STREAMS-PI-ACTIVE-ATTEMPT-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-ATTEMPT-BY-SOURCE = IF
        DROP STREAMS-PI-ATTEMPT-HISTORY-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-NATIVE-HEAD = IF
        DROP STREAMS-PI-NATIVE-HEAD-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-OBSERVATION-REVISION = IF
        DROP STREAMS-PI-OBSERVATION-REVISION-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-GLOBAL-TIME = IF
        DROP STREAMS-PI-GLOBAL-TIME-RECORD-AGREES? EXIT
    THEN
    DUP STREAMS-PI-F-SOURCE-TIME = IF
        DROP STREAMS-PI-SOURCE-TIME-RECORD-AGREES? EXIT
    THEN
    STREAMS-PI-F-THREAD-TIME = IF
        STREAMS-PI-THREAD-TIME-RECORD-AGREES? EXIT
    THEN
    _SPIRA-DROP4 0 ;
