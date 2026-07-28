\ =====================================================================
\  record-key.f - Stateless AT Protocol record-key syntax
\ =====================================================================
\  Record keys are case-sensitive ASCII path segments.  This component
\  validates the protocol-wide "any" record-key grammar; Lexicon-specific
\  key policies such as tid, nsid, or literal:self remain caller policy.
\
\  The module owns no mutable state and publishes no borrowed view.
\
\  Public API:
\    AT-RKEY-LENGTH-MIN       ( -- 1 )
\    AT-RKEY-LENGTH-MAX       ( -- 512 )
\    AT-RKEY-STATUS-VALID?    ( status -- flag )
\    AT-RKEY-VALIDATE         ( source source-u -- status )
\    AT-RKEY-VALID?           ( source source-u -- flag )
\ =====================================================================

PROVIDED akashic-atproto-record-key

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f

1   CONSTANT AT-RKEY-LENGTH-MIN
512 CONSTANT AT-RKEY-LENGTH-MAX

0 CONSTANT AT-RKEY-S-OK
1 CONSTANT AT-RKEY-S-INVALID
2 CONSTANT AT-RKEY-S-CAPACITY
3 CONSTANT AT-RKEY-S-SYNTAX
4 CONSTANT AT-RKEY-S-RANGE
5 CONSTANT AT-RKEY-S-PROTECTED
6 CONSTANT AT-RKEY-S-PLATFORM

: AT-RKEY-STATUS-VALID?  ( status -- flag )
    DUP AT-RKEY-S-OK >=
    SWAP AT-RKEY-S-PLATFORM <= AND ;

: _ATRK-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP AT-RKEY-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP AT-RKEY-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-RKEY-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-RKEY-S-PLATFORM EXIT
    THEN
    DROP AT-RKEY-S-PLATFORM ;

: _ATRK-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP AT-RKEY-S-INVALID EXIT THEN
    DUP 0= IF 2DROP AT-RKEY-S-OK EXIT THEN
    OVER 0= IF 2DROP AT-RKEY-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATRK-CALLER>STATUS ;

: _ATRK-ALPHA?  ( byte -- flag )
    DUP [CHAR] A [CHAR] Z 1+ WITHIN IF DROP -1 EXIT THEN
    [CHAR] a [CHAR] z 1+ WITHIN ;

: _ATRK-DIGIT?  ( byte -- flag )
    [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _ATRK-CHAR?  ( byte -- flag )
    DUP _ATRK-ALPHA? IF DROP -1 EXIT THEN
    DUP _ATRK-DIGIT? IF DROP -1 EXIT THEN
    DUP [CHAR] . = IF DROP -1 EXIT THEN
    DUP [CHAR] - = IF DROP -1 EXIT THEN
    DUP [CHAR] _ = IF DROP -1 EXIT THEN
    DUP [CHAR] : = IF DROP -1 EXIT THEN
    [CHAR] ~ = ;

: _ATRK-DOT-RESERVED?  ( address length -- flag )
    DUP 1 = IF
        DROP C@ [CHAR] . = EXIT
    THEN
    DUP 2 = IF
        DROP
        DUP C@ [CHAR] . =
        SWAP 1+ C@ [CHAR] . = AND
        EXIT
    THEN
    2DROP 0 ;

: AT-RKEY-VALIDATE  ( source source-u -- status )
    DUP 0< IF 2DROP AT-RKEY-S-INVALID EXIT THEN
    DUP AT-RKEY-LENGTH-MAX U> IF
        2DROP AT-RKEY-S-CAPACITY EXIT
    THEN
    2DUP _ATRK-SPAN-STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    DUP AT-RKEY-LENGTH-MIN < IF
        2DROP AT-RKEY-S-SYNTAX EXIT
    THEN
    2DUP _ATRK-DOT-RESERVED? IF
        2DROP AT-RKEY-S-SYNTAX EXIT
    THEN
    0 ?DO
        DUP I + C@ _ATRK-CHAR? 0= IF
            DROP AT-RKEY-S-SYNTAX UNLOOP EXIT
        THEN
    LOOP
    DROP AT-RKEY-S-OK ;

: AT-RKEY-VALID?  ( source source-u -- flag )
    AT-RKEY-VALIDATE AT-RKEY-S-OK = ;
