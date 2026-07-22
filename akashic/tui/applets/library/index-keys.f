\ =====================================================================
\  index-keys.f - Library-owned ordered persistence keys
\ =====================================================================
\  These byte layouts express current Library meanings over the neutral
\  ordered-index contract.  They deliberately remain under the applet:
\  persistence/btree.f knows only unsigned byte keys and opaque values.
\
\  Numeric order fields use fixed big-endian bytes so bytewise comparison
\  agrees with nonnegative sequence/revision order.  Titles keep their exact
\  current bytes; there is no normalization, collation, or search policy here.
\  Each title byte b is represented by the fixed-width 9-bit symbol b+1 and
\  followed by the zero end symbol.  This preserves unsigned bytewise order,
\  distinguishes every prefix (including embedded U+0000), and still leaves
\  room for the RID tie-breaker below the neutral 256-byte key ceiling.
\ =====================================================================

PROVIDED akashic-tui-library-index-keys

REQUIRE model.f

RID-SIZE CONSTANT LIBPI-RID-KEY-SIZE
8 RID-SIZE + CONSTANT LIBPI-ORDER-KEY-SIZE
LIB-TITLE-MAX 1+ CONSTANT _LIBPI-TITLE-SYMBOLS
_LIBPI-TITLE-SYMBOLS 9 * 7 + 8 / CONSTANT _LIBPI-TITLE-BYTES
_LIBPI-TITLE-BYTES RID-SIZE + CONSTANT LIBPI-TITLE-KEY-SIZE
RID-SIZE 2 * CONSTANT LIBPI-EDGE-KEY-SIZE
RID-SIZE 8 + CONSTANT LIBPI-HISTORY-KEY-SIZE

: _LIBPI-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;

: _LIBPI-U64-BE!  ( nonnegative-u destination -- )
    >R
    DUP 56 RSHIFT 255 AND R@     C!
    DUP 48 RSHIFT 255 AND R@ 1 + C!
    DUP 40 RSHIFT 255 AND R@ 2 + C!
    DUP 32 RSHIFT 255 AND R@ 3 + C!
    DUP 24 RSHIFT 255 AND R@ 4 + C!
    DUP 16 RSHIFT 255 AND R@ 5 + C!
    DUP  8 RSHIFT 255 AND R@ 6 + C!
        255 AND R@ 7 + C!
    R> DROP ;

: _LIBPI-DEST?  ( destination bytes -- flag )
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _LIBPI-9BIT!  ( symbol symbol-index destination -- )
    >R
    9 * 8 /MOD R@ + >R
    7 SWAP - LSHIFT
    DUP 8 RSHIFT 255 AND R@ C@ OR R@ C!
    255 AND R@ 1+ C@ OR R@ 1+ C!
    R> DROP R> DROP ;

: LIBPI-RID-KEY  ( rid destination -- status )
    >R
    DUP RID-PRESENT? 0= IF DROP R> DROP LIB-S-INVALID EXIT THEN
    R@ LIBPI-RID-KEY-SIZE _LIBPI-DEST? 0= IF
        DROP R> DROP LIB-S-INVALID EXIT
    THEN
    R@ RID-COPY R> DROP LIB-S-OK ;

: LIBPI-ORDER-KEY  ( created-sequence rid destination -- status )
    >R
    OVER 0> 0= IF 2DROP R> DROP LIB-S-INVALID EXIT THEN
    DUP RID-PRESENT? 0= IF 2DROP R> DROP LIB-S-INVALID EXIT THEN
    R@ LIBPI-ORDER-KEY-SIZE _LIBPI-DEST? 0= IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    DUP RID-SIZE R@ LIBPI-ORDER-KEY-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    R@ LIBPI-ORDER-KEY-SIZE 0 FILL
    OVER R@ _LIBPI-U64-BE!
    DUP R@ 8 + RID-COPY
    2DROP R> DROP LIB-S-OK ;

: LIBPI-TITLE-KEY  ( title-a title-u rid destination -- status )
    >R
    2 PICK 0= IF _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT THEN
    1 PICK DUP 0> SWAP LIB-TITLE-MAX <= AND 0= IF
        _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT
    THEN
    DUP RID-PRESENT? 0= IF _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT THEN
    2 PICK 2 PICK MSPAN-NONWRAPPING? 0= IF
        _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT
    THEN
    R@ LIBPI-TITLE-KEY-SIZE _LIBPI-DEST? 0= IF
        _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT
    THEN
    2 PICK 2 PICK R@ LIBPI-TITLE-KEY-SIZE MSPAN-OVERLAP? IF
        _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT
    THEN
    DUP RID-SIZE R@ LIBPI-TITLE-KEY-SIZE MSPAN-OVERLAP? IF
        _LIBPI-DROP3 R> DROP LIB-S-INVALID EXIT
    THEN
    R@ LIBPI-TITLE-KEY-SIZE 0 FILL
    R>
    2 PICK 0 ?DO
        3 PICK I + C@ 1+ I 2 PICK _LIBPI-9BIT!
    LOOP
    DUP _LIBPI-TITLE-BYTES + 2 PICK SWAP RID-COPY
    2DROP 2DROP LIB-S-OK ;

: LIBPI-EDGE-KEY  ( collection-rid member-rid destination -- status )
    >R
    OVER RID-PRESENT? 0= IF 2DROP R> DROP LIB-S-INVALID EXIT THEN
    DUP RID-PRESENT? 0= IF 2DROP R> DROP LIB-S-INVALID EXIT THEN
    R@ LIBPI-EDGE-KEY-SIZE _LIBPI-DEST? 0= IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    OVER RID-SIZE R@ LIBPI-EDGE-KEY-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    DUP RID-SIZE R@ LIBPI-EDGE-KEY-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    R@ LIBPI-EDGE-KEY-SIZE 0 FILL
    OVER R@ RID-COPY
    DUP R@ RID-SIZE + RID-COPY
    2DROP R> DROP LIB-S-OK ;

: LIBPI-EDGE-PREFIX  ( collection-rid destination -- status )
    LIBPI-RID-KEY ;

: LIBPI-HISTORY-KEY  ( document-rid content-revision destination -- status )
    >R
    OVER RID-PRESENT? 0= IF 2DROP R> DROP LIB-S-INVALID EXIT THEN
    DUP 0> 0= IF 2DROP R> DROP LIB-S-INVALID EXIT THEN
    R@ LIBPI-HISTORY-KEY-SIZE _LIBPI-DEST? 0= IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    OVER RID-SIZE R@ LIBPI-HISTORY-KEY-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP LIB-S-INVALID EXIT
    THEN
    R@ LIBPI-HISTORY-KEY-SIZE 0 FILL
    OVER R@ RID-COPY
    DUP R@ RID-SIZE + _LIBPI-U64-BE!
    2DROP R> DROP LIB-S-OK ;
