\ cbor.f — CBOR Codec for KDOS / Megapad-64
\
\ RFC 8949 subset: unsigned/negative integers, byte/text strings,
\ arrays, maps, booleans, null, semantic tags.
\ No floating point.  Integer-only.
\
\ Prefix: CBOR-   (public API)
\         _CB-    (internal helpers)
\
\ Load with:   REQUIRE cbor.f

PROVIDED akashic-cbor

\ =====================================================================
\  Major Type Constants
\ =====================================================================

0 CONSTANT CBOR-MT-UINT     \ major type 0
1 CONSTANT CBOR-MT-NINT     \ major type 1
2 CONSTANT CBOR-MT-BSTR     \ major type 2
3 CONSTANT CBOR-MT-TSTR     \ major type 3
4 CONSTANT CBOR-MT-ARRAY    \ major type 4
5 CONSTANT CBOR-MT-MAP      \ major type 5
6 CONSTANT CBOR-MT-TAG      \ major type 6
7 CONSTANT CBOR-MT-SIMPLE   \ major type 7

\ =====================================================================
\  Encoder State
\ =====================================================================

VARIABLE _CB-DST       \ output buffer address
VARIABLE _CB-MAX       \ output buffer capacity
VARIABLE _CB-POS       \ current write position

\ CBOR-RESET ( dst max -- )
\   Set output buffer for encoding.
: CBOR-RESET  ( dst max -- )
    _CB-MAX ! _CB-DST ! 0 _CB-POS ! ;

\ _CB-EMIT ( byte -- )  Write one byte.
: _CB-EMIT  ( byte -- )
    _CB-POS @ _CB-MAX @ < IF
        _CB-DST @ _CB-POS @ + C!
        1 _CB-POS +!
    ELSE DROP THEN ;

\ _CB-EMIT2 ( n -- )  Write 2 bytes big-endian.
: _CB-EMIT2  ( n -- )
    DUP 8 RSHIFT 255 AND _CB-EMIT
    255 AND _CB-EMIT ;

\ _CB-EMIT4 ( n -- )  Write 4 bytes big-endian.
: _CB-EMIT4  ( n -- )
    DUP 24 RSHIFT 255 AND _CB-EMIT
    DUP 16 RSHIFT 255 AND _CB-EMIT
    DUP 8 RSHIFT 255 AND _CB-EMIT
    255 AND _CB-EMIT ;

\ _CB-EMIT8 ( n -- )  Write 8 bytes big-endian.
: _CB-EMIT8  ( n -- )
    DUP 56 RSHIFT 255 AND _CB-EMIT
    DUP 48 RSHIFT 255 AND _CB-EMIT
    DUP 40 RSHIFT 255 AND _CB-EMIT
    DUP 32 RSHIFT 255 AND _CB-EMIT
    DUP 24 RSHIFT 255 AND _CB-EMIT
    DUP 16 RSHIFT 255 AND _CB-EMIT
    DUP 8 RSHIFT 255 AND _CB-EMIT
    255 AND _CB-EMIT ;

\ _CB-EMITCPY ( addr len -- )  Copy bytes to output.
: _CB-EMITCPY  ( addr len -- )
    0 ?DO
        DUP I + C@ _CB-EMIT
    LOOP DROP ;

\ =====================================================================
\  Encoder — Argument Encoding
\ =====================================================================

\ _CB-ARG ( major n -- )
\   Encode initial byte + argument for major type 0-7.
\   Chooses 0, 1, 2, 4, or 8 extra bytes based on n.
VARIABLE _CB-MT   \ stash major type

: _CB-ARG  ( major n -- )
    SWAP _CB-MT !
    DUP 24 < IF
        _CB-MT @ 5 LSHIFT OR _CB-EMIT EXIT
    THEN
    DUP 256 < IF
        _CB-MT @ 5 LSHIFT 24 OR _CB-EMIT
        _CB-EMIT EXIT
    THEN
    DUP 65536 < IF
        _CB-MT @ 5 LSHIFT 25 OR _CB-EMIT
        _CB-EMIT2 EXIT
    THEN
    DUP 4294967296 < IF
        _CB-MT @ 5 LSHIFT 26 OR _CB-EMIT
        _CB-EMIT4 EXIT
    THEN
    _CB-MT @ 5 LSHIFT 27 OR _CB-EMIT
    _CB-EMIT8 ;

\ =====================================================================
\  Encoder — Public API
\ =====================================================================

\ CBOR-UINT ( n -- )  Encode unsigned integer.
: CBOR-UINT  ( n -- )  0 SWAP _CB-ARG ;

\ CBOR-NINT ( n -- )  Encode negative integer.
\   Encodes as major type 1, value n.
\   Represents the integer -(1+n).
\   E.g.  CBOR-NINT 0  → represents -1.
: CBOR-NINT  ( n -- )  1 SWAP _CB-ARG ;

\ CBOR-BSTR ( addr len -- )  Encode byte string.
: CBOR-BSTR  ( addr len -- )
    DUP 2 SWAP _CB-ARG
    _CB-EMITCPY ;

\ CBOR-TSTR ( addr len -- )  Encode text string.
: CBOR-TSTR  ( addr len -- )
    DUP 3 SWAP _CB-ARG
    _CB-EMITCPY ;

\ CBOR-ARRAY ( n -- )  Encode definite-length array header.
: CBOR-ARRAY  ( n -- )  4 SWAP _CB-ARG ;

\ CBOR-MAP ( n -- )  Encode definite-length map header.
: CBOR-MAP  ( n -- )  5 SWAP _CB-ARG ;

\ CBOR-TAG ( n -- )  Encode semantic tag.
: CBOR-TAG  ( n -- )  6 SWAP _CB-ARG ;

\ CBOR-TRUE ( -- )  Encode true (simple value 21).
: CBOR-TRUE  ( -- )  245 _CB-EMIT ;

\ CBOR-FALSE ( -- )  Encode false (simple value 20).
: CBOR-FALSE  ( -- )  244 _CB-EMIT ;

\ CBOR-NULL ( -- )  Encode null (simple value 22).
: CBOR-NULL  ( -- )  246 _CB-EMIT ;

\ CBOR-RESULT ( -- addr len )  Return encoded bytes.
: CBOR-RESULT  ( -- addr len )
    _CB-DST @ _CB-POS @ ;

\ =====================================================================
\  Decoder State
\ =====================================================================

VARIABLE _CB-SRC       \ input buffer address
VARIABLE _CB-END       \ input buffer end
VARIABLE _CB-PTR       \ current read position

\ CBOR-PARSE ( addr len -- ior )
\   Set input cursor for decoding.  Returns 0 on success.
: CBOR-PARSE  ( addr len -- ior )
    OVER + _CB-END !
    _CB-SRC !
    _CB-SRC @ _CB-PTR !
    0 ;

\ _CB-AVAIL ( -- n )  Bytes remaining in input.
: _CB-AVAIL  ( -- n )
    _CB-END @ _CB-PTR @ - ;

\ _CB-GET ( -- byte )  Read and advance one byte.
: _CB-GET  ( -- byte )
    _CB-PTR @ C@  1 _CB-PTR +! ;

\ _CB-PEEK ( -- byte )  Peek at current byte (no advance).
: _CB-PEEK  ( -- byte )
    _CB-PTR @ C@ ;

\ _CB-GET2 ( -- n )  Read 2 bytes big-endian.
: _CB-GET2  ( -- n )
    _CB-GET 8 LSHIFT _CB-GET OR ;

\ _CB-GET4 ( -- n )  Read 4 bytes big-endian.
: _CB-GET4  ( -- n )
    _CB-GET 24 LSHIFT
    _CB-GET 16 LSHIFT OR
    _CB-GET 8 LSHIFT OR
    _CB-GET OR ;

\ _CB-GET8 ( -- n )  Read 8 bytes big-endian.
: _CB-GET8  ( -- n )
    _CB-GET 56 LSHIFT
    _CB-GET 48 LSHIFT OR
    _CB-GET 40 LSHIFT OR
    _CB-GET 32 LSHIFT OR
    _CB-GET 24 LSHIFT OR
    _CB-GET 16 LSHIFT OR
    _CB-GET 8 LSHIFT OR
    _CB-GET OR ;

\ =====================================================================
\  Decoder — Argument Reading
\ =====================================================================

\ _CB-READ-ARG ( addl -- n )
\   Read the argument value given the additional-info field (0-27).
: _CB-READ-ARG  ( addl -- n )
    DUP 24 < IF EXIT THEN        \ 0..23: value is addl itself
    DUP 24 = IF DROP _CB-GET EXIT THEN
    DUP 25 = IF DROP _CB-GET2 EXIT THEN
    DUP 26 = IF DROP _CB-GET4 EXIT THEN
        27 = IF _CB-GET8 EXIT THEN
    0 ;   \ shouldn't reach here

\ =====================================================================
\  Decoder — Public API
\ =====================================================================

\ CBOR-TYPE ( -- major-type )
\   Peek at the major type of the next item (0-7).
\   Does NOT advance the cursor.
: CBOR-TYPE  ( -- type )
    _CB-AVAIL 0= IF -1 EXIT THEN
    _CB-PEEK 5 RSHIFT ;

\ CBOR-DONE? ( -- flag )
\   True if input is exhausted.
: CBOR-DONE?  ( -- flag )
    _CB-AVAIL 0= IF -1 ELSE 0 THEN ;

\ CBOR-NEXT-UINT ( -- n )
\   Decode unsigned integer (major type 0).
: CBOR-NEXT-UINT  ( -- n )
    _CB-GET 31 AND _CB-READ-ARG ;

\ CBOR-NEXT-NINT ( -- n )
\   Decode negative integer (major type 1).
\   Returns the CBOR argument value.  The actual integer is -(1+n).
: CBOR-NEXT-NINT  ( -- n )
    _CB-GET 31 AND _CB-READ-ARG ;

\ CBOR-NEXT-BSTR ( -- addr len )
\   Decode byte string.  Returns pointer into input buffer.
: CBOR-NEXT-BSTR  ( -- addr len )
    _CB-GET 31 AND _CB-READ-ARG
    _CB-PTR @ SWAP
    DUP _CB-PTR +! ;

\ CBOR-NEXT-TSTR ( -- addr len )
\   Decode text string.  Returns pointer into input buffer.
: CBOR-NEXT-TSTR  ( -- addr len )
    _CB-GET 31 AND _CB-READ-ARG
    _CB-PTR @ SWAP
    DUP _CB-PTR +! ;

\ CBOR-NEXT-ARRAY ( -- n )
\   Decode array header, return item count.
: CBOR-NEXT-ARRAY  ( -- n )
    _CB-GET 31 AND _CB-READ-ARG ;

\ CBOR-NEXT-MAP ( -- n )
\   Decode map header, return pair count.
: CBOR-NEXT-MAP  ( -- n )
    _CB-GET 31 AND _CB-READ-ARG ;

\ CBOR-NEXT-TAG ( -- n )
\   Decode semantic tag, return tag number.
: CBOR-NEXT-TAG  ( -- n )
    _CB-GET 31 AND _CB-READ-ARG ;

\ CBOR-NEXT-BOOL ( -- flag )
\   Decode boolean.  Returns -1 for true, 0 for false.
: CBOR-NEXT-BOOL  ( -- flag )
    _CB-GET 31 AND
    21 = IF -1 ELSE 0 THEN ;

\ CBOR-SKIP ( -- )
\   Skip one CBOR data item (including nested structures).
VARIABLE _CB-SKIP-N

: CBOR-SKIP  ( -- )
    _CB-AVAIL 0= IF EXIT THEN
    _CB-PEEK 5 RSHIFT           \ major type
    DUP 0 = OVER 1 = OR IF     \ uint or nint
        DROP _CB-GET 31 AND _CB-READ-ARG DROP EXIT
    THEN
    DUP 2 = OVER 3 = OR IF     \ bstr or tstr
        DROP _CB-GET 31 AND _CB-READ-ARG
        _CB-PTR +! EXIT
    THEN
    DUP 6 = IF                  \ tag — skip tag number, then skip content
        DROP _CB-GET 31 AND _CB-READ-ARG DROP
        CBOR-SKIP EXIT          \ recurse to skip tagged item
    THEN
    DUP 7 = IF                  \ simple/float
        DROP _CB-GET DROP EXIT
    THEN
    DUP 4 = IF                  \ array
        DROP _CB-GET 31 AND _CB-READ-ARG
        _CB-SKIP-N !
        _CB-SKIP-N @ 0 ?DO CBOR-SKIP LOOP
        EXIT
    THEN
    5 = IF                      \ map
        _CB-GET 31 AND _CB-READ-ARG
        2 * _CB-SKIP-N !
        _CB-SKIP-N @ 0 ?DO CBOR-SKIP LOOP
        EXIT
    THEN
    _CB-GET DROP ;              \ unknown — skip initial byte
