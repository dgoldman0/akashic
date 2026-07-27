\ =====================================================================
\  base64url.f - Strict canonical unpadded Base64url
\ =====================================================================
\  This is the JOSE-facing RFC 4648 Base64url codec.  It deliberately does
\  not share the permissive legacy net/base64.f decoder: JOSE admits only
\  the URL-safe alphabet, no padding or whitespace, and one canonical
\  encoding for a byte string.
\
\  Both transforms are caller-owned and transactional with respect to
\  returned statuses.  They validate the complete mapped source and
\  advertised destination-capacity span, exact result length, capacity, and
\  alias geometry before the first destination byte is changed.  The module
\  owns no mutable scratch and independent calls may be interleaved.
\
\  Empty input is represented by any address with length zero; in
\  particular, ( 0 0 ) is valid.  A nonempty span must be admitted by the
\  generic caller-memory boundary.  Source and the exact destination result
\  may not overlap.  Unused destination capacity is not part of the written
\  span, though the complete advertised capacity must be mapped and safe.
\  Returned failures never publish output.  An unexpected fault after
\  admission is not converted to a status: it propagates because publication
\  may already be partial and this state-free codec has no cleanup to hide.
\
\  Public API:
\    JOSE-B64URL-ENCODED-LENGTH  ( source-u -- result-u status )
\    JOSE-B64URL-DECODED-LENGTH  ( source source-u -- result-u status )
\    JOSE-B64URL-ENCODE          ( source source-u destination capacity
\                                  -- written status )
\    JOSE-B64URL-DECODE          ( source source-u destination capacity
\                                  -- written status )
\ =====================================================================

PROVIDED akashic-security-jose-base64url

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f

\ =====================================================================
\  Status vocabulary and bounded lengths
\ =====================================================================

0 CONSTANT JOSE-B64URL-S-OK
1 CONSTANT JOSE-B64URL-S-INVALID
2 CONSTANT JOSE-B64URL-S-CAPACITY
3 CONSTANT JOSE-B64URL-S-ALIAS
4 CONSTANT JOSE-B64URL-S-RANGE
5 CONSTANT JOSE-B64URL-S-PROTECTED
6 CONSTANT JOSE-B64URL-S-PLATFORM

-1 1 RSHIFT CONSTANT _JBU-LENGTH-MAX

\ The largest raw byte count whose unpadded encoding fits in one positive
\ Forth length.  MAX/4 has a remainder of three, so the final partial group
\ may use either of its two admitted source bytes without overflow.
_JBU-LENGTH-MAX 4 / 3 * 2 + CONSTANT _JBU-ENCODE-INPUT-MAX

: JOSE-B64URL-STATUS-VALID?  ( status -- flag )
    DUP JOSE-B64URL-S-OK >=
    SWAP JOSE-B64URL-S-PLATFORM <= AND ;

\ =====================================================================
\  Caller-memory and alphabet predicates
\ =====================================================================

\ Preserve the generic boundary's distinctions at this public API.  An
\ undocumented result is a platform failure, never malformed caller data.
\ CALLER-SPAN-STATUS already contains the BIOS exception boundary; no codec
\ word catches a fault from this mapper or from admitted byte access.
: _JBU-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP JOSE-B64URL-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP JOSE-B64URL-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP JOSE-B64URL-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP JOSE-B64URL-S-PLATFORM EXIT
    THEN
    DROP JOSE-B64URL-S-PLATFORM ;

: _JBU-CALLER-SPAN-STATUS  ( address length -- status )
    CALLER-SPAN-STATUS _JBU-CALLER>STATUS ;

: _JBU-ENCODE-CHAR  ( sextet -- char )
    DUP 26 U< IF 65 + EXIT THEN
    DUP 52 U< IF 71 + EXIT THEN
    DUP 62 U< IF  4 - EXIT THEN
    DUP 62 = IF DROP 45 EXIT THEN
    DROP 95 ;

: _JBU-DECODE-CHAR  ( char -- sextet|-1 )
    DUP  65 >= OVER  90 <= AND IF 65 - EXIT THEN
    DUP  97 >= OVER 122 <= AND IF 71 - EXIT THEN
    DUP  48 >= OVER  57 <= AND IF  4 + EXIT THEN
    DUP  45 = IF DROP 62 EXIT THEN
    DUP  95 = IF DROP 63 EXIT THEN
    DROP -1 ;

: _JBU-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _JBU-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;

\ =====================================================================
\  Exact length preflight
\ =====================================================================

: JOSE-B64URL-ENCODED-LENGTH  ( source-u -- result-u status )
    DUP 0< IF
        DROP 0 JOSE-B64URL-S-INVALID EXIT
    THEN
    DUP _JBU-ENCODE-INPUT-MAX U> IF
        DROP 0 JOSE-B64URL-S-CAPACITY EXIT
    THEN
    DUP 3 / 4 *
    SWAP 3 MOD DUP 0= IF
        DROP
    ELSE
        1+ +
    THEN
    JOSE-B64URL-S-OK ;

\ Every input character must belong to the URL-safe alphabet.  Length one
\ modulo four is impossible without padding.  For a two-character tail the
\ low four bits of the final sextet are unused; for a three-character tail
\ the low two bits are unused.  Requiring those bits to be zero rejects
\ alternate spellings of the same byte string.
: _JBU-CANONICAL?  ( admitted-source source-u -- flag )
    DUP 4 MOD 1 = IF 2DROP 0 EXIT THEN

    DUP 0 ?DO
        OVER I + C@ _JBU-DECODE-CHAR 0< IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP

    DUP 0= IF 2DROP -1 EXIT THEN
    DUP 4 MOD
    DUP 0= IF
        DROP 2DROP -1 EXIT
    THEN
    DUP 2 = IF
        DROP
        2DUP + 1- C@ _JBU-DECODE-CHAR 15 AND 0=
        >R 2DROP R> EXIT
    THEN
    DUP 3 = IF
        DROP
        2DUP + 1- C@ _JBU-DECODE-CHAR 3 AND 0=
        >R 2DROP R> EXIT
    THEN
    DROP 2DROP 0 ;

: _JBU-DECODED-LENGTH-ADMITTED
  ( admitted-source source-u -- result-u status )
    2DUP _JBU-CANONICAL? 0= IF
        2DROP 0 JOSE-B64URL-S-INVALID EXIT
    THEN
    DUP 4 / 3 *
    SWAP 4 MOD DUP 0= IF
        DROP
    ELSE
        1- +
    THEN
    NIP
    JOSE-B64URL-S-OK ;

: JOSE-B64URL-DECODED-LENGTH  ( source source-u -- result-u status )
    2DUP _JBU-CALLER-SPAN-STATUS ?DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    _JBU-DECODED-LENGTH-ADMITTED ;

\ =====================================================================
\  Preflight shared by the mutating entry points
\ =====================================================================

\ Preserve a completed `(length status)` result while discarding the four
\ borrowed transform arguments beneath it.
: _JBU-RETURN-PREFLIGHT  ( four arguments length status -- length status )
    >R >R _JBU-DROP4 R> R> ;

: _JBU-ENCODE-PREFLIGHT  ( source source-u destination capacity -- result-u status )
    2OVER _JBU-CALLER-SPAN-STATUS ?DUP IF
        >R _JBU-DROP4 0 R> EXIT
    THEN
    2DUP _JBU-CALLER-SPAN-STATUS ?DUP IF
        >R _JBU-DROP4 0 R> EXIT
    THEN

    2 PICK JOSE-B64URL-ENCODED-LENGTH
    DUP JOSE-B64URL-S-OK <> IF
        _JBU-RETURN-PREFLIGHT EXIT
    THEN
    DROP >R

    DUP R@ U< IF
        R> DROP _JBU-DROP4
        0 JOSE-B64URL-S-CAPACITY EXIT
    THEN

    2OVER 3 PICK R@ MSPAN-OVERLAP? IF
        R> DROP _JBU-DROP4
        0 JOSE-B64URL-S-ALIAS EXIT
    THEN

    _JBU-DROP4 R> JOSE-B64URL-S-OK ;

: _JBU-DECODE-PREFLIGHT  ( source source-u destination capacity -- result-u status )
    2OVER _JBU-CALLER-SPAN-STATUS ?DUP IF
        >R _JBU-DROP4 0 R> EXIT
    THEN
    2DUP _JBU-CALLER-SPAN-STATUS ?DUP IF
        >R _JBU-DROP4 0 R> EXIT
    THEN

    2OVER _JBU-DECODED-LENGTH-ADMITTED
    DUP JOSE-B64URL-S-OK <> IF
        _JBU-RETURN-PREFLIGHT EXIT
    THEN
    DROP >R

    DUP R@ U< IF
        R> DROP _JBU-DROP4
        0 JOSE-B64URL-S-CAPACITY EXIT
    THEN

    2OVER 3 PICK R@ MSPAN-OVERLAP? IF
        R> DROP _JBU-DROP4
        0 JOSE-B64URL-S-ALIAS EXIT
    THEN

    _JBU-DROP4 R> JOSE-B64URL-S-OK ;

\ =====================================================================
\  Encoding after successful preflight
\ =====================================================================

: _JBU-ENCODE-THREE  ( source destination -- )
    OVER C@ 2 RSHIFT
        _JBU-ENCODE-CHAR OVER C!

    OVER C@ 3 AND 4 LSHIFT
    2 PICK 1+ C@ 4 RSHIFT OR
        _JBU-ENCODE-CHAR OVER 1+ C!

    OVER 1+ C@ 15 AND 2 LSHIFT
    2 PICK 2 + C@ 6 RSHIFT OR
        _JBU-ENCODE-CHAR OVER 2 + C!

    OVER 2 + C@ 63 AND
        _JBU-ENCODE-CHAR OVER 3 + C!
    2DROP ;

: _JBU-ENCODE-TWO  ( source destination -- )
    OVER C@ 2 RSHIFT
        _JBU-ENCODE-CHAR OVER C!

    OVER C@ 3 AND 4 LSHIFT
    2 PICK 1+ C@ 4 RSHIFT OR
        _JBU-ENCODE-CHAR OVER 1+ C!

    OVER 1+ C@ 15 AND 2 LSHIFT
        _JBU-ENCODE-CHAR OVER 2 + C!
    2DROP ;

: _JBU-ENCODE-ONE  ( source destination -- )
    OVER C@ 2 RSHIFT
        _JBU-ENCODE-CHAR OVER C!
    OVER C@ 3 AND 4 LSHIFT
        _JBU-ENCODE-CHAR OVER 1+ C!
    2DROP ;

: _JBU-ENCODE-RUN  ( source source-u destination -- )
    BEGIN
        OVER 3 >=
    WHILE
        2 PICK OVER _JBU-ENCODE-THREE
        4 + >R
        3 - SWAP 3 + SWAP
        R>
    REPEAT
    OVER 2 = IF
        2 PICK OVER _JBU-ENCODE-TWO
    ELSE
        OVER 1 = IF
            2 PICK OVER _JBU-ENCODE-ONE
        THEN
    THEN
    _JBU-DROP3 ;

: JOSE-B64URL-ENCODE  ( source source-u destination capacity -- written status )
    2OVER 2OVER _JBU-ENCODE-PREFLIGHT
    DUP JOSE-B64URL-S-OK <> IF
        _JBU-RETURN-PREFLIGHT EXIT
    THEN
    DROP >R
    DROP _JBU-ENCODE-RUN
    R> JOSE-B64URL-S-OK ;

\ =====================================================================
\  Decoding after successful canonical preflight
\ =====================================================================

: _JBU-DECODE-FOUR  ( source destination -- )
    OVER C@ _JBU-DECODE-CHAR 2 LSHIFT
    2 PICK 1+ C@ _JBU-DECODE-CHAR 4 RSHIFT OR
        OVER C!

    OVER 1+ C@ _JBU-DECODE-CHAR 15 AND 4 LSHIFT
    2 PICK 2 + C@ _JBU-DECODE-CHAR 2 RSHIFT OR
        OVER 1+ C!

    OVER 2 + C@ _JBU-DECODE-CHAR 3 AND 6 LSHIFT
    2 PICK 3 + C@ _JBU-DECODE-CHAR OR
        OVER 2 + C!
    2DROP ;

: _JBU-DECODE-THREE  ( source destination -- )
    OVER C@ _JBU-DECODE-CHAR 2 LSHIFT
    2 PICK 1+ C@ _JBU-DECODE-CHAR 4 RSHIFT OR
        OVER C!

    OVER 1+ C@ _JBU-DECODE-CHAR 15 AND 4 LSHIFT
    2 PICK 2 + C@ _JBU-DECODE-CHAR 2 RSHIFT OR
        OVER 1+ C!
    2DROP ;

: _JBU-DECODE-TWO  ( source destination -- )
    OVER C@ _JBU-DECODE-CHAR 2 LSHIFT
    2 PICK 1+ C@ _JBU-DECODE-CHAR 4 RSHIFT OR
        OVER C!
    2DROP ;

: _JBU-DECODE-RUN  ( source source-u destination -- )
    BEGIN
        OVER 4 >=
    WHILE
        2 PICK OVER _JBU-DECODE-FOUR
        3 + >R
        4 - SWAP 4 + SWAP
        R>
    REPEAT
    OVER 3 = IF
        2 PICK OVER _JBU-DECODE-THREE
    ELSE
        OVER 2 = IF
            2 PICK OVER _JBU-DECODE-TWO
        THEN
    THEN
    _JBU-DROP3 ;

: JOSE-B64URL-DECODE  ( source source-u destination capacity -- written status )
    2OVER 2OVER _JBU-DECODE-PREFLIGHT
    DUP JOSE-B64URL-S-OK <> IF
        _JBU-RETURN-PREFLIGHT EXIT
    THEN
    DROP >R
    DROP _JBU-DECODE-RUN
    R> JOSE-B64URL-S-OK ;
