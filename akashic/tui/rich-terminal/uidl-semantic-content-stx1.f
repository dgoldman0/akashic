\ =====================================================================
\  uidl-semantic-content-stx1.f -- frozen native text to STX1
\ =====================================================================
\
\  Translates one already-deep-validated, immutable USCOL text entry and
\  its correlated 48-byte summary into canonical little-endian STX1.
\  This module is not another validation authority: it performs only
\  constant-time correlation, span, capacity, and revision checks before
\  one bounded native-item/text-copy walk.  It does not decode UTF-8, sort
\  keys, prove geometry, or inspect native alignment padding.
\
\  The destination tag remains zero until the complete cursor accounting
\  succeeds.  Thus an impossible post-freeze cursor mismatch cannot leave
\  a valid-looking partial value.
\
\  Public API:
\    USSTX-PACK
\      ( entry entry-bytes summary source-revision destination capacity
\        -- bytes status )
\
\  Prefix: USSTX- (public), _USSTX- (private)

PROVIDED akashic-tui-rterm-usstx

REQUIRE ../semantic-collections.f

0x31585453 CONSTANT USSTX-TAG
1 CONSTANT USSTX-VERSION
72 CONSTANT USSTX-CONTENT-HEADER-SIZE
32 CONSTANT USSTX-ITEM-HEADER-SIZE

VARIABLE _USSTX-ENTRY
VARIABLE _USSTX-ENTRY-U
VARIABLE _USSTX-SUMMARY
VARIABLE _USSTX-REVISION
VARIABLE _USSTX-DST
VARIABLE _USSTX-CAP

VARIABLE _USSTX-FAMILY
VARIABLE _USSTX-ITEM-COUNT
VARIABLE _USSTX-UTF8-U
VARIABLE _USSTX-OUT-U

VARIABLE _USSTX-NATIVE
VARIABLE _USSTX-NATIVE-U
VARIABLE _USSTX-WIRE
VARIABLE _USSTX-WIRE-U
VARIABLE _USSTX-TEXT-U
VARIABLE _USSTX-NATIVE-STEP
VARIABLE _USSTX-WIRE-STEP
VARIABLE _USSTX-COPIED-UTF8

: _USSTX-ALIGNED?  ( address -- flag )  7 AND 0= ;

: _USSTX-ALIGNED-SPAN?  ( address bytes -- flag )
    OVER 0<> OVER 0> AND 0= IF 2DROP 0 EXIT THEN
    OVER _USSTX-ALIGNED? 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _USSTX-DISJOINT?  ( a u b v -- flag )
    MSPAN-OVERLAP? 0= ;

: _USSTX-U32?  ( value -- flag )
    DUP 0< IF DROP 0 EXIT THEN 0x100000000 U< ;

: _USSTX-UADD?  ( a b -- sum flag )
    OVER + DUP ROT U< 0= ;

\ Explicit byte stores make the wire order independent of native cell order
\ and admit byte-aligned caller storage.
: _USSTX-LE16!  ( value address -- )
    2DUP C!
    SWAP 8 RSHIFT SWAP 1+ C! ;

: _USSTX-LE32!  ( value address -- )
    2DUP _USSTX-LE16!
    SWAP 16 RSHIFT SWAP 2 + _USSTX-LE16! ;

: _USSTX-LE64!  ( value address -- )
    2DUP _USSTX-LE32!
    SWAP 32 RSHIFT SWAP 4 + _USSTX-LE32! ;

: _USSTX-TEXT-FAMILY?  ( family -- flag )
    DUP USCOL-F-TEXT-AREA = SWAP USCOL-F-TEXT-GRID = OR ;

: _USSTX-ARGS!
    ( entry entry-u summary revision destination capacity -- )
    _USSTX-CAP ! _USSTX-DST ! _USSTX-REVISION !
    _USSTX-SUMMARY ! _USSTX-ENTRY-U ! _USSTX-ENTRY ! ;

\ This is deliberately O(1).  FAMILY/KEY/ENTRY-BYTES bind the summary back
\ to the exact frozen native slice whose deep validation produced it.
: _USSTX-CORRELATE  ( -- status )
    _USSTX-ENTRY @ _USSTX-ENTRY-U @ _USSTX-ALIGNED-SPAN? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-SUMMARY @ USCOL-SUMMARY-SIZE _USSTX-ALIGNED-SPAN? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-ENTRY @ _USSTX-ENTRY-U @
        _USSTX-SUMMARY @ USCOL-SUMMARY-SIZE _USSTX-DISJOINT? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-REVISION @ 0= IF USCOL-S-INVALID EXIT THEN
    _USSTX-ENTRY-U @ USCOL-ENTRY-HEADER-SIZE U< IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-ENTRY-U @ 7 AND IF USCOL-S-INVALID EXIT THEN
    _USSTX-ENTRY @ USCOL-ENTRY-BYTES@
        _USSTX-ENTRY-U @ <> IF USCOL-S-INVALID EXIT THEN
    _USSTX-ENTRY @ USCOL-ENTRY-FAMILY-ABI@
        USCOL-FAMILY-ABI <> IF USCOL-S-INVALID EXIT THEN
    _USSTX-SUMMARY @ USCOL-SUMMARY-ENTRY-BYTES@
        _USSTX-ENTRY-U @ <> IF USCOL-S-INVALID EXIT THEN

    _USSTX-ENTRY @ USCOL-ENTRY-FAMILY@ DUP _USSTX-FAMILY !
    _USSTX-SUMMARY @ USCOL-SUMMARY-FAMILY@ <> IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-ENTRY @ USCOL-ENTRY-KEY@ DUP 0= IF
        DROP USCOL-S-INVALID EXIT
    THEN
    _USSTX-SUMMARY @ USCOL-SUMMARY-ROOT-KEY@ <> IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-FAMILY @ _USSTX-TEXT-FAMILY? 0= IF
        USCOL-S-UNSUPPORTED EXIT
    THEN
    _USSTX-ENTRY-U @ USCOL-TEXT-FIXED-SIZE U< IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-SUMMARY @ USCOL-SUMMARY-CHILD-COUNT@ IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-ENTRY @ USCOL-TEXT-ITEM-COUNT@
    _USSTX-SUMMARY @ USCOL-SUMMARY-ITEM-COUNT@ DUP _USSTX-ITEM-COUNT !
        <> IF USCOL-S-INVALID EXIT THEN
    _USSTX-SUMMARY @ USCOL-SUMMARY-UTF8-BYTES@ DUP _USSTX-UTF8-U !
        _USSTX-U32? 0= IF USCOL-S-INVALID EXIT THEN

    _USSTX-SUMMARY @ USCOL-SUMMARY-STX1-BYTES
    DUP USCOL-S-OK <> IF NIP EXIT THEN
    DROP _USSTX-OUT-U !

    _USSTX-CAP @ 0< IF USCOL-S-INVALID EXIT THEN
    _USSTX-CAP @ _USSTX-OUT-U @ U< IF
        USCOL-S-CAPACITY EXIT
    THEN
    _USSTX-DST @ _USSTX-CAP @ OVER 0<> OVER 0> AND 0= IF
        2DROP USCOL-S-INVALID EXIT
    THEN
    MSPAN-NONWRAPPING? 0= IF USCOL-S-INVALID EXIT THEN
    _USSTX-ENTRY @ _USSTX-ENTRY-U @
        _USSTX-DST @ _USSTX-CAP @ _USSTX-DISJOINT? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    _USSTX-SUMMARY @ USCOL-SUMMARY-SIZE
        _USSTX-DST @ _USSTX-CAP @ _USSTX-DISJOINT? 0= IF
        USCOL-S-INVALID EXIT
    THEN
    USCOL-S-OK ;

: _USSTX-HEADER!  ( -- )
    \ Zero is the invalid publication tag until the complete walk succeeds.
    0 _USSTX-DST @ _USSTX-LE32!
    USSTX-VERSION _USSTX-DST @ 4 + _USSTX-LE16!
    0 _USSTX-DST @ 6 + _USSTX-LE16!
    _USSTX-REVISION @ _USSTX-DST @ 8 + _USSTX-LE64!
    _USSTX-ENTRY @ USCOL-TEXT-ROWS@
        _USSTX-DST @ 16 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-COLUMNS@
        _USSTX-DST @ 20 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-VIEWPORT-ROW@
        _USSTX-DST @ 24 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-VIEWPORT-COLUMN@
        _USSTX-DST @ 28 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-VIEWPORT-ROWS@
        _USSTX-DST @ 32 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-VIEWPORT-COLUMNS@
        _USSTX-DST @ 36 + _USSTX-LE32!
    _USSTX-ITEM-COUNT @ _USSTX-DST @ 40 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-FLAGS@
        _USSTX-DST @ 44 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-PRIMARY-KEY@
        _USSTX-DST @ 48 + _USSTX-LE64!
    _USSTX-ENTRY @ USCOL-TEXT-ANCHOR-KEY@
        _USSTX-DST @ 56 + _USSTX-LE64!
    _USSTX-ENTRY @ USCOL-TEXT-PRIMARY-OFFSET@
        _USSTX-DST @ 64 + _USSTX-LE32!
    _USSTX-ENTRY @ USCOL-TEXT-ANCHOR-OFFSET@
        _USSTX-DST @ 68 + _USSTX-LE32! ;

: _USSTX-CURSORS!  ( -- )
    _USSTX-ENTRY @ USCOL-TEXT-FIRST _USSTX-NATIVE !
    _USSTX-ENTRY-U @ USCOL-TEXT-FIXED-SIZE - _USSTX-NATIVE-U !
    _USSTX-DST @ USSTX-CONTENT-HEADER-SIZE + _USSTX-WIRE !
    _USSTX-OUT-U @ USSTX-CONTENT-HEADER-SIZE - _USSTX-WIRE-U !
    0 _USSTX-COPIED-UTF8 ! ;

\ Cursor checks are memory-safety accounting, not a second semantic proof.
\ ABI 1's already-proved unit row span is written directly to STX1.
: _USSTX-PACK-ONE?  ( -- flag )
    _USSTX-NATIVE-U @ USCOL-ITEM-HEADER-SIZE U< IF 0 EXIT THEN
    _USSTX-NATIVE @ USCOL-ITEM-TEXT-BYTES@ DUP _USSTX-TEXT-U !
        _USSTX-U32? 0= IF 0 EXIT THEN
    _USSTX-TEXT-U @ USCOL-TEXT-ITEM-BYTES DUP 0= IF DROP 0 EXIT THEN
        DUP _USSTX-NATIVE-STEP !
    _USSTX-NATIVE-U @ U> IF 0 EXIT THEN
    _USSTX-TEXT-U @ USSTX-ITEM-HEADER-SIZE _USSTX-UADD? 0= IF
        DROP 0 EXIT
    THEN
    DUP _USSTX-WIRE-STEP ! _USSTX-WIRE-U @ U> IF 0 EXIT THEN
    _USSTX-COPIED-UTF8 @ _USSTX-TEXT-U @ _USSTX-UADD? 0= IF
        DROP 0 EXIT
    THEN
    DUP _USSTX-UTF8-U @ U> IF DROP 0 EXIT THEN
    _USSTX-COPIED-UTF8 !

    _USSTX-NATIVE @ USCOL-ITEM-KEY@
        _USSTX-WIRE @ _USSTX-LE64!
    _USSTX-NATIVE @ USCOL-ITEM-ROW@
        _USSTX-WIRE @ 8 + _USSTX-LE32!
    _USSTX-NATIVE @ USCOL-ITEM-COLUMN@
        _USSTX-WIRE @ 12 + _USSTX-LE32!
    1 _USSTX-WIRE @ 16 + _USSTX-LE32!
    _USSTX-NATIVE @ USCOL-ITEM-COLUMN-SPAN@
        _USSTX-WIRE @ 20 + _USSTX-LE32!
    _USSTX-NATIVE @ USCOL-ITEM-ROLE@
        _USSTX-WIRE @ 24 + _USSTX-LE16!
    _USSTX-NATIVE @ USCOL-ITEM-STATE@
        _USSTX-WIRE @ 26 + _USSTX-LE16!
    _USSTX-TEXT-U @ _USSTX-WIRE @ 28 + _USSTX-LE32!
    _USSTX-NATIVE @ USCOL-ITEM-TEXT-OFFSET +
        _USSTX-WIRE @ USSTX-ITEM-HEADER-SIZE +
        _USSTX-TEXT-U @ MOVE

    _USSTX-NATIVE-STEP @ _USSTX-NATIVE +!
    _USSTX-NATIVE-STEP @ NEGATE _USSTX-NATIVE-U +!
    _USSTX-WIRE-STEP @ _USSTX-WIRE +!
    _USSTX-WIRE-STEP @ NEGATE _USSTX-WIRE-U +!
    -1 ;

: _USSTX-PACK-ITEMS?  ( -- flag )
    _USSTX-ITEM-COUNT @ 0 ?DO
        _USSTX-PACK-ONE? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _USSTX-NATIVE-U @ 0=
    _USSTX-WIRE-U @ 0= AND
    _USSTX-COPIED-UTF8 @ _USSTX-UTF8-U @ = AND ;

: _USSTX-PACK-BODY  ( -- bytes status )
    _USSTX-CORRELATE DUP USCOL-S-OK <> IF
        0 SWAP EXIT
    THEN
    DROP
    _USSTX-HEADER!
    _USSTX-CURSORS!
    _USSTX-PACK-ITEMS? 0= IF
        0 USCOL-S-INVALID EXIT
    THEN
    \ The tag is the final write; no fallible operation follows it.
    USSTX-TAG _USSTX-DST @ _USSTX-LE32!
    _USSTX-OUT-U @ USCOL-S-OK ;

: _USSTX-PACK-CALL  ( -- bytes status )
    ['] _USSTX-PACK-BODY CATCH ?DUP IF
        DROP 0 USCOL-S-INVALID
    THEN ;

: _USSTX-SCRUB  ( -- )
    0 _USSTX-ENTRY ! 0 _USSTX-ENTRY-U ! 0 _USSTX-SUMMARY !
    0 _USSTX-REVISION ! 0 _USSTX-DST ! 0 _USSTX-CAP !
    0 _USSTX-FAMILY ! 0 _USSTX-ITEM-COUNT ! 0 _USSTX-UTF8-U !
    0 _USSTX-OUT-U ! 0 _USSTX-NATIVE ! 0 _USSTX-NATIVE-U !
    0 _USSTX-WIRE ! 0 _USSTX-WIRE-U ! 0 _USSTX-TEXT-U !
    0 _USSTX-NATIVE-STEP ! 0 _USSTX-WIRE-STEP !
    0 _USSTX-COPIED-UTF8 ! ;

: USSTX-PACK
    ( entry entry-u summary revision destination capacity -- bytes status )
    _USSTX-ARGS!
    _USSTX-PACK-CALL
    >R >R _USSTX-SCRUB R> R> ;
