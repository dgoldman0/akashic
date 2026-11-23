\ cbor.f — CBOR Codec for KDOS / Megapad-64
\
\ RFC 8949 subset: unsigned/negative integers, byte/text strings,
\ arrays, maps, booleans, null, semantic tags.
\ No floating point.  Integer-only.
\
\ A word that encodes or decodes a whole item of its own saves and
\ restores the cursors with CBOR-SAVE and CBOR-RESTORE, so any CBOR
\ user can call it between its own CBOR calls (see Nesting below).
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
VARIABLE _CB-POS       \ bytes encoded, those past the capacity included
VARIABLE _CB-OVF       \ overflow flag (TRUE if bytes dropped)

\ CBOR-RESET ( dst max -- )
\   Set output buffer for encoding.
: CBOR-RESET  ( dst max -- )
    _CB-MAX ! _CB-DST ! 0 _CB-POS ! 0 _CB-OVF ! ;

\ _CB-EMIT ( byte -- )  Write one byte.
\   A byte past the buffer's capacity is dropped and still counted, so
\   CBOR-SIZE reports the size an encoding needs whether or not it fit.
: _CB-EMIT  ( byte -- )
    _CB-POS @ _CB-MAX @ < IF
        _CB-DST @ _CB-POS @ + C!
    ELSE DROP -1 _CB-OVF ! THEN
    1 _CB-POS +! ;

\ CBOR-OK? ( -- flag )  TRUE if no bytes were dropped during encoding.
: CBOR-OK?  ( -- flag )  _CB-OVF @ 0= ;

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
    \ The part that fits moves whole; the rest is dropped and counted, as
    \ _CB-EMIT drops and counts each byte past the capacity.
    _CB-MAX @ _CB-POS @ - 0 MAX  OVER MIN      ( addr len fit )
    ROT OVER                                   ( len fit addr fit )
    _CB-DST @ _CB-POS @ +  SWAP CMOVE          ( len fit )
    OVER < IF -1 _CB-OVF ! THEN                ( len )
    _CB-POS +! ;

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
\   After an overflow, len is the capacity: the bytes that fit.
: CBOR-RESULT  ( -- addr len )
    _CB-DST @ _CB-POS @ _CB-MAX @ MIN ;

\ CBOR-SIZE ( -- n )  Bytes the encoding has produced so far, those that
\   did not fit included.  Encoding an item into a buffer of 0 bytes
\   measures the buffer it needs: 0 0 CBOR-RESET, encode, CBOR-SIZE.
: CBOR-SIZE  ( -- n )  _CB-POS @ ;

\ =====================================================================
\  Decoder State
\ =====================================================================
\
\ Every read is checked against the input's end, and each CBOR-NEXT-*
\ word checks that the item has the major type it reads.  An item, a
\ string or an argument that runs past the end, an array or map count
\ larger than the bytes left could hold, an item of another type, or an
\ argument form this subset does not decode (reserved, or indefinite
\ length) is a decode error.  The error is recorded, and the read
\ position moves to the input's end, so every later read finds the input
\ exhausted and nothing past the end is ever read.  The word that met
\ the error returns 0, or an empty string at the input's end.
\ CBOR-INPUT-OK? tells whether the input has decoded cleanly since
\ CBOR-PARSE.

VARIABLE _CB-SRC       \ input buffer address
VARIABLE _CB-END       \ input buffer end
VARIABLE _CB-PTR       \ current read position
VARIABLE _CB-BAD       \ decode error flag (TRUE once the input was malformed)

\ CBOR-PARSE ( addr len -- ior )
\   Set input cursor for decoding and clear the decode error.
\   Returns 0 on success.
: CBOR-PARSE  ( addr len -- ior )
    OVER + _CB-END !
    _CB-SRC !
    _CB-SRC @ _CB-PTR !
    0 _CB-BAD !
    0 ;

\ CBOR-INPUT-OK? ( -- flag )  TRUE if the input has decoded without a
\   decode error since CBOR-PARSE.
: CBOR-INPUT-OK?  ( -- flag )  _CB-BAD @ 0= ;

\ _CB-AVAIL ( -- n )  Bytes remaining in input.
: _CB-AVAIL  ( -- n )
    _CB-END @ _CB-PTR @ - 0 MAX ;

\ _CB-FAIL ( -- )  Record a decode error and move to the input's end.
: _CB-FAIL  ( -- )
    -1 _CB-BAD !  _CB-END @ _CB-PTR ! ;

\ _CB-GET ( -- byte )  Read and advance one byte.  At the input's end it
\   is a decode error and gives 0.
: _CB-GET  ( -- byte )
    _CB-AVAIL 0= IF _CB-FAIL 0 EXIT THEN
    _CB-PTR @ C@  1 _CB-PTR +! ;

\ _CB-PEEK ( -- byte )  Peek at current byte (no advance), once a check
\   has found a byte left.
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
\   Read the argument the additional-info field announces: the field
\   itself below 24, or the 1, 2, 4 or 8 bytes that follow for 24 to 27.
\   28 to 30 are reserved and 31 starts an indefinite length, which this
\   subset does not decode.  Either, or an argument that runs past the
\   input's end, is a decode error and gives 0.
: _CB-READ-ARG  ( addl -- n )
    DUP 24 < IF EXIT THEN        \ 0..23: value is addl itself
    DUP 27 > IF DROP _CB-FAIL 0 EXIT THEN
    1 OVER 24 - LSHIFT _CB-AVAIL > IF DROP _CB-FAIL 0 EXIT THEN
    DUP 24 = IF DROP _CB-GET EXIT THEN
    DUP 25 = IF DROP _CB-GET2 EXIT THEN
        26 = IF _CB-GET4 EXIT THEN
    _CB-GET8 ;

\ _CB-HEAD ( -- major n )  Read an item's initial byte and its argument.
: _CB-HEAD  ( -- major n )
    _CB-GET DUP 5 RSHIFT SWAP 31 AND _CB-READ-ARG ;

\ _CB-EXPECT ( major n want -- n )  Keep n when the item's major type is
\   the one wanted; any other is a decode error and gives 0.
: _CB-EXPECT  ( major n want -- n )
    ROT <> IF DROP _CB-FAIL 0 THEN ;

\ _CB-STRING ( n -- addr len )  Take a string's n bytes from the input.
\   A length beyond the bytes left is a decode error and gives an empty
\   string at the input's end.
: _CB-STRING  ( n -- addr len )
    DUP _CB-AVAIL U> IF DROP _CB-FAIL 0 THEN
    _CB-PTR @ SWAP
    DUP _CB-PTR +! ;

\ _CB-ITEMS ( n -- n )  An array's item count.  Each item takes a byte at
\   least, so a count beyond the bytes left is a decode error and gives 0.
: _CB-ITEMS  ( n -- n )
    DUP _CB-AVAIL U> IF DROP _CB-FAIL 0 THEN ;

\ _CB-PAIRS ( n -- n )  A map's pair count, checked as _CB-ITEMS checks
\   an array's: each pair takes two bytes at least.
: _CB-PAIRS  ( n -- n )
    DUP _CB-AVAIL 2/ U> IF DROP _CB-FAIL 0 THEN ;

\ =====================================================================
\  Decoder — Public API
\ =====================================================================

\ CBOR-TYPE ( -- major-type )
\   Peek at the major type of the next item (0-7), or -1 at the end.
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
    _CB-HEAD CBOR-MT-UINT _CB-EXPECT ;

\ CBOR-NEXT-NINT ( -- n )
\   Decode negative integer (major type 1).
\   Returns the CBOR argument value.  The actual integer is -(1+n).
: CBOR-NEXT-NINT  ( -- n )
    _CB-HEAD CBOR-MT-NINT _CB-EXPECT ;

\ CBOR-NEXT-BSTR ( -- addr len )
\   Decode byte string (major type 2).  Returns pointer into input buffer.
: CBOR-NEXT-BSTR  ( -- addr len )
    _CB-HEAD CBOR-MT-BSTR _CB-EXPECT _CB-STRING ;

\ CBOR-NEXT-TSTR ( -- addr len )
\   Decode text string (major type 3).  Returns pointer into input buffer.
: CBOR-NEXT-TSTR  ( -- addr len )
    _CB-HEAD CBOR-MT-TSTR _CB-EXPECT _CB-STRING ;

\ CBOR-NEXT-ARRAY ( -- n )
\   Decode array header (major type 4), return item count.
: CBOR-NEXT-ARRAY  ( -- n )
    _CB-HEAD CBOR-MT-ARRAY _CB-EXPECT _CB-ITEMS ;

\ CBOR-NEXT-MAP ( -- n )
\   Decode map header (major type 5), return pair count.
: CBOR-NEXT-MAP  ( -- n )
    _CB-HEAD CBOR-MT-MAP _CB-EXPECT _CB-PAIRS ;

\ CBOR-NEXT-TAG ( -- n )
\   Decode semantic tag (major type 6), return tag number.  The item it
\   tags must follow.
: CBOR-NEXT-TAG  ( -- n )
    _CB-HEAD CBOR-MT-TAG _CB-EXPECT
    _CB-AVAIL 0= IF DROP _CB-FAIL 0 THEN ;

\ CBOR-NEXT-BOOL ( -- flag )
\   Decode boolean.  Returns -1 for true (0xF5), 0 for false (0xF4).
\   Any other item is a decode error and gives 0.
: CBOR-NEXT-BOOL  ( -- flag )
    _CB-GET
    DUP 245 = IF DROP -1 EXIT THEN
    244 <> IF _CB-FAIL THEN 0 ;

\ _CB-LEFT+ ( left n -- left' )  Add n items to the count CBOR-SKIP still
\   has to skip.  Every item takes a byte at least, so a count beyond the
\   bytes left is a decode error and gives 0, which ends the skip.
: _CB-LEFT+  ( left n -- left' )
    +  DUP _CB-AVAIL U> IF DROP _CB-FAIL 0 THEN ;

\ CBOR-SKIP ( -- )
\   Skip one CBOR data item, with the arrays, maps and tagged items nested
\   in it.  It keeps one count of the items still to skip instead of
\   recursing into each level: an array adds its items to the count, a map
\   its keys and values, and a tag the item it tags.  Nesting therefore
\   costs no return stack however deep the input goes, and every pass reads
\   a head, so the passes are bounded by the input's length.
: CBOR-SKIP  ( -- )
    1                                        ( left )
    BEGIN DUP 0<> _CB-BAD @ 0= AND WHILE
        1- _CB-HEAD SWAP                     ( left n major )
        DUP CBOR-MT-BSTR = OVER CBOR-MT-TSTR = OR IF
            DROP _CB-STRING 2DROP            \ string: its bytes
        ELSE DUP CBOR-MT-ARRAY = IF
            DROP _CB-ITEMS _CB-LEFT+         \ array: its items
        ELSE DUP CBOR-MT-MAP = IF
            DROP _CB-PAIRS 2* _CB-LEFT+      \ map: its keys and values
        ELSE CBOR-MT-TAG = IF
            DROP 1 _CB-LEFT+                 \ tag: the item it tags
        ELSE
            DROP                             \ integer or simple: the head
        THEN THEN THEN THEN
    REPEAT DROP ;

\ =====================================================================
\  Nesting — Saving and Restoring the Cursors
\ =====================================================================
\
\ The encoder keeps one cursor (its buffer, capacity, write position and
\ overflow flag) and the decoder keeps one (its input, end, read position
\ and decode error flag).  A word that encodes or decodes a whole item of
\ its own, such as a transaction inside a block or a block's hash inside
\ a message, may run between another user's CBOR calls.  It saves both
\ cursors before it starts and restores them when it is done, so the
\ caller's encoding or decoding carries on where it was.  Each save goes
\ in CBOR-CURSORS-SIZE bytes that the saving word provides, so words
\ nest as deeply as their own storage allows.

8 CELLS CONSTANT CBOR-CURSORS-SIZE

\ CBOR-SAVE ( addr -- )
\   Copy both cursors into the CBOR-CURSORS-SIZE bytes at addr.
: CBOR-SAVE  ( addr -- )
    _CB-DST @ OVER !  CELL+
    _CB-MAX @ OVER !  CELL+
    _CB-POS @ OVER !  CELL+
    _CB-OVF @ OVER !  CELL+
    _CB-SRC @ OVER !  CELL+
    _CB-END @ OVER !  CELL+
    _CB-PTR @ OVER !  CELL+
    _CB-BAD @ SWAP ! ;

\ CBOR-RESTORE ( addr -- )
\   Make the cursors CBOR-SAVE copied to addr the current ones.
: CBOR-RESTORE  ( addr -- )
    DUP @ _CB-DST !  CELL+
    DUP @ _CB-MAX !  CELL+
    DUP @ _CB-POS !  CELL+
    DUP @ _CB-OVF !  CELL+
    DUP @ _CB-SRC !  CELL+
    DUP @ _CB-END !  CELL+
    DUP @ _CB-PTR !  CELL+
    @ _CB-BAD ! ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _cbor-guard

' CBOR-RESET      CONSTANT _cbor-reset-xt
' CBOR-OK?        CONSTANT _cbor-ok-q-xt
' CBOR-UINT       CONSTANT _cbor-uint-xt
' CBOR-NINT       CONSTANT _cbor-nint-xt
' CBOR-BSTR       CONSTANT _cbor-bstr-xt
' CBOR-TSTR       CONSTANT _cbor-tstr-xt
' CBOR-ARRAY      CONSTANT _cbor-array-xt
' CBOR-MAP        CONSTANT _cbor-map-xt
' CBOR-TAG        CONSTANT _cbor-tag-xt
' CBOR-TRUE       CONSTANT _cbor-true-xt
' CBOR-FALSE      CONSTANT _cbor-false-xt
' CBOR-NULL       CONSTANT _cbor-null-xt
' CBOR-RESULT     CONSTANT _cbor-result-xt
' CBOR-SIZE       CONSTANT _cbor-size-xt
' CBOR-PARSE      CONSTANT _cbor-parse-xt
' CBOR-INPUT-OK?  CONSTANT _cbor-input-ok-q-xt
' CBOR-TYPE       CONSTANT _cbor-type-xt
' CBOR-DONE?      CONSTANT _cbor-done-q-xt
' CBOR-NEXT-UINT  CONSTANT _cbor-next-uint-xt
' CBOR-NEXT-NINT  CONSTANT _cbor-next-nint-xt
' CBOR-NEXT-BSTR  CONSTANT _cbor-next-bstr-xt
' CBOR-NEXT-TSTR  CONSTANT _cbor-next-tstr-xt
' CBOR-NEXT-ARRAY CONSTANT _cbor-next-array-xt
' CBOR-NEXT-MAP   CONSTANT _cbor-next-map-xt
' CBOR-NEXT-TAG   CONSTANT _cbor-next-tag-xt
' CBOR-NEXT-BOOL  CONSTANT _cbor-next-bool-xt
' CBOR-SKIP       CONSTANT _cbor-skip-xt
' CBOR-SAVE       CONSTANT _cbor-save-xt
' CBOR-RESTORE    CONSTANT _cbor-restore-xt

: CBOR-RESET      _cbor-reset-xt _cbor-guard WITH-GUARD ;
: CBOR-OK?        _cbor-ok-q-xt _cbor-guard WITH-GUARD ;
: CBOR-UINT       _cbor-uint-xt _cbor-guard WITH-GUARD ;
: CBOR-NINT       _cbor-nint-xt _cbor-guard WITH-GUARD ;
: CBOR-BSTR       _cbor-bstr-xt _cbor-guard WITH-GUARD ;
: CBOR-TSTR       _cbor-tstr-xt _cbor-guard WITH-GUARD ;
: CBOR-ARRAY      _cbor-array-xt _cbor-guard WITH-GUARD ;
: CBOR-MAP        _cbor-map-xt _cbor-guard WITH-GUARD ;
: CBOR-TAG        _cbor-tag-xt _cbor-guard WITH-GUARD ;
: CBOR-TRUE       _cbor-true-xt _cbor-guard WITH-GUARD ;
: CBOR-FALSE      _cbor-false-xt _cbor-guard WITH-GUARD ;
: CBOR-NULL       _cbor-null-xt _cbor-guard WITH-GUARD ;
: CBOR-RESULT     _cbor-result-xt _cbor-guard WITH-GUARD ;
: CBOR-SIZE       _cbor-size-xt _cbor-guard WITH-GUARD ;
: CBOR-PARSE      _cbor-parse-xt _cbor-guard WITH-GUARD ;
: CBOR-INPUT-OK?  _cbor-input-ok-q-xt _cbor-guard WITH-GUARD ;
: CBOR-TYPE       _cbor-type-xt _cbor-guard WITH-GUARD ;
: CBOR-DONE?      _cbor-done-q-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-UINT  _cbor-next-uint-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-NINT  _cbor-next-nint-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-BSTR  _cbor-next-bstr-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-TSTR  _cbor-next-tstr-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-ARRAY _cbor-next-array-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-MAP   _cbor-next-map-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-TAG   _cbor-next-tag-xt _cbor-guard WITH-GUARD ;
: CBOR-NEXT-BOOL  _cbor-next-bool-xt _cbor-guard WITH-GUARD ;
: CBOR-SKIP       _cbor-skip-xt _cbor-guard WITH-GUARD ;
: CBOR-SAVE       _cbor-save-xt _cbor-guard WITH-GUARD ;
: CBOR-RESTORE    _cbor-restore-xt _cbor-guard WITH-GUARD ;
[THEN] [THEN]
