\ =====================================================================
\  cid.f - Stateless blessed AT Protocol CID text admission
\ =====================================================================
\  AT Protocol narrows textual CIDs to canonical CIDv1 values encoded as
\  lowercase, unpadded base32 with the explicit multibase "b" prefix.
\  The binary CID must name either DRISL/DAG-CBOR data or raw blob bytes
\  and must carry a 32-byte SHA-256 multihash.
\
\  This module validates a caller-owned span in place.  It owns no mutable
\  state, allocates no storage, retains no borrow, and performs no hashing.
\  A successful check returns the exact multicodec value so callers can
\  enforce their own semantic requirement (for example, createRecord
\  results require DAG-CBOR rather than raw).
\
\  Public API:
\    AT-CID-TEXT-LENGTH             ( -- 59 )
\    AT-CID-CODEC-NONE              ( -- 0 )
\    AT-CID-CODEC-RAW               ( -- 0x55 )
\    AT-CID-CODEC-DAG-CBOR          ( -- 0x71 )
\    AT-CID-CODEC-VALID?            ( codec -- flag )
\    AT-CID-STATUS-VALID?           ( status -- flag )
\    AT-CID-TEXT-CHECK              ( source source-u -- codec status )
\    AT-CID-TEXT-VALID?             ( source source-u -- flag )
\ =====================================================================

PROVIDED akashic-atproto-cid

REQUIRE ../utils/caller-span.f

\ A blessed CID contains four profile bytes and a 32-byte digest.  Base32
\ therefore emits ceil(36 * 8 / 5) = 58 symbols; multibase adds one byte.
59 CONSTANT AT-CID-TEXT-LENGTH

0    CONSTANT AT-CID-CODEC-NONE
0x55 CONSTANT AT-CID-CODEC-RAW
0x71 CONSTANT AT-CID-CODEC-DAG-CBOR

0 CONSTANT AT-CID-S-OK
1 CONSTANT AT-CID-S-INVALID
2 CONSTANT AT-CID-S-LENGTH
3 CONSTANT AT-CID-S-ENCODING
4 CONSTANT AT-CID-S-PROFILE
5 CONSTANT AT-CID-S-RANGE
6 CONSTANT AT-CID-S-PROTECTED
7 CONSTANT AT-CID-S-PLATFORM

: AT-CID-CODEC-VALID?  ( codec -- flag )
    DUP AT-CID-CODEC-DAG-CBOR =
    SWAP AT-CID-CODEC-RAW = OR ;

: AT-CID-STATUS-VALID?  ( status -- flag )
    DUP AT-CID-S-OK >=
    SWAP AT-CID-S-PLATFORM <= AND ;

: _ATCID-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP AT-CID-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP AT-CID-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-CID-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-CID-S-PLATFORM EXIT
    THEN
    DROP AT-CID-S-PLATFORM ;

: _ATCID-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP AT-CID-S-INVALID EXIT THEN
    DUP 0= IF 2DROP AT-CID-S-OK EXIT THEN
    OVER 0= IF 2DROP AT-CID-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATCID-CALLER>STATUS ;

: _ATCID-BASE32-LOWER?  ( byte -- flag )
    DUP [CHAR] a [CHAR] z 1+ WITHIN IF DROP -1 EXIT THEN
    [CHAR] 2 [CHAR] 7 1+ WITHIN ;

\ Thirty-six binary bytes leave three significant bits in the final base32
\ symbol.  Its two low bits must therefore be zero in a canonical unpadded
\ spelling.  The admitted characters are values 0,4,...,28.
: _ATCID-FINAL?  ( byte -- flag )
    DUP [CHAR] a = IF DROP -1 EXIT THEN
    DUP [CHAR] e = IF DROP -1 EXIT THEN
    DUP [CHAR] i = IF DROP -1 EXIT THEN
    DUP [CHAR] m = IF DROP -1 EXIT THEN
    DUP [CHAR] q = IF DROP -1 EXIT THEN
    DUP [CHAR] u = IF DROP -1 EXIT THEN
    DUP [CHAR] y = IF DROP -1 EXIT THEN
    [CHAR] 4 = ;

: _ATCID-ENCODING?  ( source -- flag )
    DUP C@ [CHAR] b <> IF DROP 0 EXIT THEN
    1+ AT-CID-TEXT-LENGTH 1- 0 ?DO
        DUP I + C@ _ATCID-BASE32-LOWER? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    AT-CID-TEXT-LENGTH 2 - + C@ _ATCID-FINAL? ;

\ The first six base32 symbols encode the first 30 CID bits.  "afyrei"
\ spells CIDv1 + DAG-CBOR + SHA-256 + the first six bits of digest length;
\ "afkrei" is the corresponding raw-codec prefix.  The next symbol must
\ be a-h so its top two bits complete the exact 0x20 digest length while
\ its remaining three bits remain free digest data.
: _ATCID-PROFILE  ( source -- codec status )
    DUP 7 + C@ [CHAR] a [CHAR] h 1+ WITHIN 0= IF
        DROP AT-CID-CODEC-NONE AT-CID-S-PROFILE EXIT
    THEN
    DUP 1+ 6 S" afyrei" COMPARE 0= IF
        DROP AT-CID-CODEC-DAG-CBOR AT-CID-S-OK EXIT
    THEN
    DUP 1+ 6 S" afkrei" COMPARE 0= IF
        DROP AT-CID-CODEC-RAW AT-CID-S-OK EXIT
    THEN
    DROP AT-CID-CODEC-NONE AT-CID-S-PROFILE ;

: AT-CID-TEXT-CHECK  ( source source-u -- codec status )
    DUP 0< IF
        2DROP AT-CID-CODEC-NONE AT-CID-S-INVALID EXIT
    THEN
    DUP AT-CID-TEXT-LENGTH <> IF
        2DROP AT-CID-CODEC-NONE AT-CID-S-LENGTH EXIT
    THEN
    2DUP _ATCID-SPAN-STATUS ?DUP IF
        >R 2DROP AT-CID-CODEC-NONE R> EXIT
    THEN
    DROP
    DUP _ATCID-ENCODING? 0= IF
        DROP AT-CID-CODEC-NONE AT-CID-S-ENCODING EXIT
    THEN
    _ATCID-PROFILE ;

: AT-CID-TEXT-VALID?  ( source source-u -- flag )
    AT-CID-TEXT-CHECK AT-CID-S-OK = NIP ;
