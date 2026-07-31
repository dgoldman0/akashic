\ =====================================================================
\  json-writer.f - Caller-owned bounded JSON string output
\ =====================================================================
\  This layer adds JSON quoted-string emission to buffer-writer.f.  It
\  owns no storage or mutable state: the caller supplies both the writer
\  descriptor and its byte arena.  A string is reserved and committed as
\  one append, so capacity and admission failures cannot publish a JSON
\  fragment.
\ =====================================================================

PROVIDED akashic-json-writer

REQUIRE buffer-writer.f
REQUIRE ../text/utf8.f

: _JSONW-BYTE-SIZE  ( byte -- encoded-u )
    DUP 34 = IF DROP 2 EXIT THEN
    DUP 92 = IF DROP 2 EXIT THEN
    DUP 8 = IF DROP 2 EXIT THEN
    DUP 9 = IF DROP 2 EXIT THEN
    DUP 10 = IF DROP 2 EXIT THEN
    DUP 12 = IF DROP 2 EXIT THEN
    DUP 13 = IF DROP 2 EXIT THEN
    32 < IF 6 ELSE 1 THEN ;

\ The source is already geometry- and UTF-8-checked here.  Overflow is
\ reported as capacity because the encoded result cannot be represented
\ as a nonnegative machine-cell length.
: _JSONW-MEASURE-VALID  ( source-a source-u -- encoded-u status )
    2
    BEGIN 1 PICK WHILE
        2 PICK C@ _JSONW-BYTE-SIZE
        2DUP + DUP 2 PICK U< OVER 0< OR IF
            2DROP 2DROP DROP 0 CBW-S-CAPACITY EXIT
        THEN
        >R 2DROP
        1- SWAP 1+ SWAP R>
    REPEAT
    NIP NIP CBW-S-OK ;

: JSONW-STRING-MEASURE  ( source-a source-u -- encoded-u status )
    2DUP _CBW-SOURCE-VALID? 0= IF
        2DROP 0 CBW-S-INVALID EXIT
    THEN
    2DUP UTF8-VALID? 0= IF
        2DROP 0 CBW-S-INVALID EXIT
    THEN
    _JSONW-MEASURE-VALID ;

: _JSONW-HEX  ( nibble -- char )
    15 AND DUP 10 < IF 48 + ELSE 55 + THEN ;

: _JSONW-ESCAPE2  ( escape-char destination -- destination' )
    [CHAR] \ OVER C! 1+
    SWAP OVER C! 1+ ;

: _JSONW-CONTROL6  ( byte destination -- destination' )
    SWAP >R
    [CHAR] \ OVER C! 1+
    [CHAR] u OVER C! 1+
    [CHAR] 0 OVER C! 1+
    [CHAR] 0 OVER C! 1+
    R@ 4 RSHIFT _JSONW-HEX OVER C! 1+
    R> 15 AND _JSONW-HEX OVER C! 1+ ;

: _JSONW-EMIT-BYTE  ( byte destination -- destination' )
    OVER 34 = IF NIP [CHAR] " SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 92 = IF NIP [CHAR] \ SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 8 = IF NIP [CHAR] b SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 9 = IF NIP [CHAR] t SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 10 = IF NIP [CHAR] n SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 12 = IF NIP [CHAR] f SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 13 = IF NIP [CHAR] r SWAP _JSONW-ESCAPE2 EXIT THEN
    OVER 32 < IF _JSONW-CONTROL6 EXIT THEN
    SWAP OVER C! 1+ ;

: _JSONW-EMIT-BYTES  ( source-a source-u destination -- destination' )
    BEGIN OVER WHILE
        2 PICK C@ SWAP _JSONW-EMIT-BYTE
        >R 1- SWAP 1+ SWAP R>
    REPEAT
    NIP NIP ;

: _JSONW-FAIL  ( source-a source-u writer status -- status )
    OVER _CBW-LATCH >R
    DROP 2DROP R> ;

\ _CBW-RESERVE has already advanced LENGTH when this path is taken, but
\ no target byte has been touched.  Restore LENGTH before latching INVALID.
: _JSONW-ROLLBACK-INVALID
  \ ( source-a source-u writer encoded-u -- status )
    NEGATE 1 PICK _CBW.LENGTH +!
    CBW-S-INVALID _JSONW-FAIL ;

: JSONW-STRING  ( source-a source-u writer -- status )
    DUP _CBW-READY-STATUS DUP IF
        >R DROP 2DROP R> EXIT
    THEN DROP

    2 PICK 2 PICK _CBW-SOURCE-VALID? 0= IF
        CBW-S-INVALID _JSONW-FAIL EXIT
    THEN
    2 PICK 2 PICK 2 PICK CBW-SIZE MSPAN-OVERLAP? IF
        CBW-S-INVALID _JSONW-FAIL EXIT
    THEN
    2 PICK 2 PICK UTF8-VALID? 0= IF
        CBW-S-INVALID _JSONW-FAIL EXIT
    THEN

    2 PICK 2 PICK _JSONW-MEASURE-VALID
    DUP IF
        >R DROP R> _JSONW-FAIL EXIT
    THEN DROP

    DUP 2 PICK _CBW-RESERVE
    DUP IF
        >R 2DROP DROP 2DROP R> EXIT
    THEN DROP

    \ Reject only overlap with this newly reserved output.  A source may
    \ safely borrow an earlier, disjoint prefix in the same writer arena.
    2>R
    2 PICK 2 PICK 2R@ SWAP MSPAN-OVERLAP? IF
        2R> DROP _JSONW-ROLLBACK-INVALID EXIT
    THEN
    2R> SWAP DROP

    SWAP >R
    [CHAR] " OVER C! 1+
    _JSONW-EMIT-BYTES
    [CHAR] " OVER C! 1+ DROP
    R> DROP CBW-S-OK ;
