\ =====================================================================
\  http-request-stream.f - Strict bounded incremental HTTP/1.1 requests
\ =====================================================================
\  The descriptor, header arena, and body destination all belong to the
\  caller.  The parser allocates no memory, owns no transport, and keeps no
\  module-global mutable state.  Body slices are borrowed only for the
\  duration of the configured callback:
\
\      ( request context -- status )
\
\  The callback reads the current slice with WREQ-BODY-SLICE and returns
\  zero only after it has accepted the complete slice.
\
\  This is deliberately a one-request, Content-Length-only HTTP/1.1 parser.
\  It rejects transfer codings, Expect, duplicate Content-Length fields,
\  bare LF, obs-fold, invalid control bytes, malformed Host authorities, and
\  ambiguous request targets.  Parsing pauses at HEADERS-READY before any
\  body byte is consumed.  The owner must explicitly select BODY-CONTINUE
\  (deliver slices to the callback) or BODY-DISCARD (drain without delivery).
\  FEED consumes no byte beyond the selected request, so a connection owner
\  retains any pipelined or otherwise unconsumed input tail.
\ =====================================================================

PROVIDED akashic-web-http-request-stream

REQUIRE ../utils/memory-span.f

0 CONSTANT WREQ-STATE-REQUEST-LINE
1 CONSTANT WREQ-STATE-REQUEST-LINE-LF
2 CONSTANT WREQ-STATE-HEADERS
3 CONSTANT WREQ-STATE-HEADERS-LF
4 CONSTANT WREQ-STATE-HEADERS-READY
5 CONSTANT WREQ-STATE-BODY
6 CONSTANT WREQ-STATE-DISCARD
7 CONSTANT WREQ-STATE-DONE
8 CONSTANT WREQ-STATE-STOPPED

0  CONSTANT WREQ-S-PENDING
1  CONSTANT WREQ-S-HEADERS-READY
2  CONSTANT WREQ-S-DONE
3  CONSTANT WREQ-S-INVALID
4  CONSTANT WREQ-S-STATE
5  CONSTANT WREQ-S-REQUEST-LINE-OVERFLOW
6  CONSTANT WREQ-S-HEADER-LINE-OVERFLOW
7  CONSTANT WREQ-S-HEADER-OVERFLOW
8  CONSTANT WREQ-S-HEADER-COUNT
9  CONSTANT WREQ-S-MALFORMED
10 CONSTANT WREQ-S-FRAMING
11 CONSTANT WREQ-S-BODY-OVERFLOW
12 CONSTANT WREQ-S-CALLBACK
13 CONSTANT WREQ-S-TRUNCATED
14 CONSTANT WREQ-S-CANCELLED

8192  CONSTANT WREQ-DEFAULT-REQUEST-LINE-LIMIT
8192  CONSTANT WREQ-DEFAULT-HEADER-LINE-LIMIT
64    CONSTANT WREQ-DEFAULT-HEADER-COUNT-LIMIT

1 CONSTANT _WREQ-F-CONTENT-LENGTH
2 CONSTANT _WREQ-F-HEADERS-COMPLETE
4 CONSTANT _WREQ-F-IN-CALLBACK
8 CONSTANT _WREQ-F-HOST
15 CONSTANT _WREQ-FLAGS-MASK

  0 CONSTANT _WREQ-STATE
  8 CONSTANT _WREQ-STATUS
 16 CONSTANT _WREQ-HEADER-A
 24 CONSTANT _WREQ-HEADER-CAPACITY
 32 CONSTANT _WREQ-HEADER-U
 40 CONSTANT _WREQ-REQUEST-LINE-LIMIT
 48 CONSTANT _WREQ-HEADER-LINE-LIMIT
 56 CONSTANT _WREQ-HEADER-COUNT-LIMIT
 64 CONSTANT _WREQ-BODY-LIMIT
 72 CONSTANT _WREQ-LINE-START
 80 CONSTANT _WREQ-LINE-U
 88 CONSTANT _WREQ-METHOD-OFFSET
 96 CONSTANT _WREQ-METHOD-U
104 CONSTANT _WREQ-TARGET-OFFSET
112 CONSTANT _WREQ-TARGET-U
120 CONSTANT _WREQ-HEADERS-OFFSET
128 CONSTANT _WREQ-HEADERS-U
136 CONSTANT _WREQ-HEADER-COUNT
144 CONSTANT _WREQ-CONTENT-LENGTH
152 CONSTANT _WREQ-BODY-REMAINING
160 CONSTANT _WREQ-FLAGS
168 CONSTANT _WREQ-BODY-XT
176 CONSTANT _WREQ-CONTEXT
184 CONSTANT _WREQ-BODY-A
192 CONSTANT _WREQ-BODY-U
200 CONSTANT _WREQ-CALL-RESULT
208 CONSTANT _WREQ-IN-A
216 CONSTANT _WREQ-IN-U
224 CONSTANT _WREQ-CONSUMED
232 CONSTANT _WREQ-T0
240 CONSTANT _WREQ-T1
248 CONSTANT _WREQ-T2
256 CONSTANT _WREQ-T3
264 CONSTANT _WREQ-T4
272 CONSTANT _WREQ-T5
280 CONSTANT WEB-HTTP-REQUEST-STREAM-SIZE

: WREQ.STATE              ( request -- a ) _WREQ-STATE + ;
: WREQ.STATUS             ( request -- a ) _WREQ-STATUS + ;
: WREQ.HEADER-A           ( request -- a ) _WREQ-HEADER-A + ;
: WREQ.HEADER-CAPACITY    ( request -- a ) _WREQ-HEADER-CAPACITY + ;
: WREQ.HEADER-U           ( request -- a ) _WREQ-HEADER-U + ;
: WREQ.REQUEST-LINE-LIMIT ( request -- a ) _WREQ-REQUEST-LINE-LIMIT + ;
: WREQ.HEADER-LINE-LIMIT  ( request -- a ) _WREQ-HEADER-LINE-LIMIT + ;
: WREQ.HEADER-COUNT-LIMIT ( request -- a ) _WREQ-HEADER-COUNT-LIMIT + ;
: WREQ.BODY-LIMIT         ( request -- a ) _WREQ-BODY-LIMIT + ;
: WREQ.LINE-START         ( request -- a ) _WREQ-LINE-START + ;
: WREQ.LINE-U             ( request -- a ) _WREQ-LINE-U + ;
: WREQ.METHOD-OFFSET      ( request -- a ) _WREQ-METHOD-OFFSET + ;
: WREQ.METHOD-U           ( request -- a ) _WREQ-METHOD-U + ;
: WREQ.TARGET-OFFSET      ( request -- a ) _WREQ-TARGET-OFFSET + ;
: WREQ.TARGET-U           ( request -- a ) _WREQ-TARGET-U + ;
: WREQ.HEADERS-OFFSET     ( request -- a ) _WREQ-HEADERS-OFFSET + ;
: WREQ.HEADERS-U          ( request -- a ) _WREQ-HEADERS-U + ;
: WREQ.HEADER-COUNT       ( request -- a ) _WREQ-HEADER-COUNT + ;
: WREQ.CONTENT-LENGTH     ( request -- a ) _WREQ-CONTENT-LENGTH + ;
: WREQ.BODY-REMAINING     ( request -- a ) _WREQ-BODY-REMAINING + ;
: WREQ.FLAGS              ( request -- a ) _WREQ-FLAGS + ;
: WREQ.BODY-XT            ( request -- a ) _WREQ-BODY-XT + ;
: WREQ.CONTEXT            ( request -- a ) _WREQ-CONTEXT + ;
: WREQ.BODY-A             ( request -- a ) _WREQ-BODY-A + ;
: WREQ.BODY-U             ( request -- a ) _WREQ-BODY-U + ;
: _WREQ.CALL-RESULT       ( request -- a ) _WREQ-CALL-RESULT + ;
: _WREQ.IN-A              ( request -- a ) _WREQ-IN-A + ;
: _WREQ.IN-U              ( request -- a ) _WREQ-IN-U + ;
: _WREQ.CONSUMED          ( request -- a ) _WREQ-CONSUMED + ;
: _WREQ.T0                ( request -- a ) _WREQ-T0 + ;
: _WREQ.T1                ( request -- a ) _WREQ-T1 + ;
: _WREQ.T2                ( request -- a ) _WREQ-T2 + ;
: _WREQ.T3                ( request -- a ) _WREQ-T3 + ;
: _WREQ.T4                ( request -- a ) _WREQ-T4 + ;
: _WREQ.T5                ( request -- a ) _WREQ-T5 + ;

: WREQ-STATE@          ( request -- state ) WREQ.STATE @ ;
: WREQ-STATUS@         ( request -- status ) WREQ.STATUS @ ;
: WREQ-HEADER-COUNT@   ( request -- count ) WREQ.HEADER-COUNT @ ;
: WREQ-CONTENT-LENGTH@ ( request -- length ) WREQ.CONTENT-LENGTH @ ;
: WREQ-BODY-LENGTH@    ( request -- length )
    DUP WREQ.FLAGS @ _WREQ-F-HEADERS-COMPLETE AND 0= IF
        DROP 0 EXIT
    THEN
    DUP WREQ.CONTENT-LENGTH @ SWAP WREQ.BODY-REMAINING @ - ;

: _WREQ-TCHAR?  ( c -- flag )
    DUP 33 < IF DROP 0 EXIT THEN
    DUP 126 > IF DROP 0 EXIT THEN
    DUP 34 = OVER 40 = OR OVER 41 = OR OVER 44 = OR
    OVER 47 = OR OVER 58 = OR OVER 59 = OR OVER 60 = OR
    OVER 61 = OR OVER 62 = OR OVER 63 = OR OVER 64 = OR
    OVER 91 = OR OVER 92 = OR OVER 93 = OR OVER 123 = OR
    OVER 125 = OR IF DROP 0 ELSE DROP -1 THEN ;

: _WREQ-TOKEN?  ( addr len -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ _WREQ-TCHAR? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _WREQ-UPPER-HEX?  ( c -- flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND
    SWAP DUP [CHAR] A >= SWAP [CHAR] F <= AND OR ;

: _WREQ-HEXDIG?  ( c -- flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND
    OVER [CHAR] A >= 2 PICK [CHAR] F <= AND OR
    SWAP DUP [CHAR] a >= SWAP [CHAR] f <= AND OR ;

: _WREQ-HEX-VALUE  ( c -- u )
    DUP [CHAR] 9 <= IF [CHAR] 0 - EXIT THEN
    [CHAR] A - 10 + ;

: _WREQ-UNRESERVED?  ( c -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND
    OVER [CHAR] A >= 2 PICK [CHAR] Z <= AND OR
    OVER [CHAR] 0 >= 2 PICK [CHAR] 9 <= AND OR
    OVER [CHAR] - = OR OVER [CHAR] . = OR
    OVER [CHAR] _ = OR SWAP [CHAR] ~ = OR ;

\ Enforce a single canonical spelling before routing: literal backslash is
\ never accepted, percent triplets use uppercase hexadecimal, and an escape
\ may not disguise an unreserved byte, a control byte, or a path/query
\ delimiter.  Multibyte UTF-8 octets and non-delimiter reserved bytes remain
\ available to applications as their exact percent-encoded spelling.
: _WREQ-TARGET?  ( addr len request -- flag )
    2 PICK OVER _WREQ.T2 !
    1 PICK OVER _WREQ.T3 !
    NIP NIP
    DUP _WREQ.T3 @ 0= IF DROP 0 EXIT THEN
    DUP _WREQ.T2 @ 0= IF DROP 0 EXIT THEN
    DUP _WREQ.T2 @ OVER _WREQ.T3 @ MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP _WREQ.T2 @ C@ [CHAR] / <> IF DROP 0 EXIT THEN
    DUP _WREQ.T3 @ 0 ?DO
        DUP _WREQ.T2 @ I + C@
        DUP 33 < OVER 126 > OR
        OVER [CHAR] # = OR OVER [CHAR] \ = OR IF
            DROP DROP 0 UNLOOP EXIT
        THEN
        DUP [CHAR] % = IF
            DROP
            I 2 + OVER _WREQ.T3 @ >= IF
                DROP 0 UNLOOP EXIT
            THEN
            DUP _WREQ.T2 @ I + 1+ C@ _WREQ-UPPER-HEX? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            DUP _WREQ.T2 @ I + 2 + C@ _WREQ-UPPER-HEX? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
            DUP _WREQ.T2 @ I + 1+ C@ _WREQ-HEX-VALUE 16 *
            OVER _WREQ.T2 @ I + 2 + C@ _WREQ-HEX-VALUE +
            DUP 32 < OVER 127 = OR
            OVER _WREQ-UNRESERVED? OR
            OVER [CHAR] / = OR OVER [CHAR] \ = OR
            OVER [CHAR] ? = OR OVER [CHAR] # = OR
            SWAP [CHAR] % = OR IF
                DROP 0 UNLOOP EXIT
            THEN
            DROP
        ELSE
            DROP
        THEN
    LOOP
    DROP -1 ;

: _WREQ-OWS?  ( c -- flag )
    DUP 32 = SWAP 9 = OR ;

: _WREQ-VALUE-CHAR?  ( c -- flag )
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 32 < SWAP 126 > OR 0= ;

: _WREQ-LOWER  ( c -- c' )
    DUP 65 >= OVER 90 <= AND IF 32 + THEN ;

: _WREQ-CIEQ?  ( a1 u1 a2 u2 -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP 2DROP -1 EXIT THEN
    >R SWAP DROP R>
    0 ?DO
        OVER I + C@ _WREQ-LOWER
        OVER I + C@ _WREQ-LOWER
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

: _WREQ-DIGITS?  ( addr len -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ DUP [CHAR] 0 < SWAP [CHAR] 9 > OR IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _WREQ-REG-HOST-CHAR?  ( c -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND
    OVER [CHAR] A >= 2 PICK [CHAR] Z <= AND OR
    OVER [CHAR] 0 >= 2 PICK [CHAR] 9 <= AND OR
    OVER [CHAR] - = OR OVER [CHAR] . = OR
    OVER [CHAR] _ = OR OVER [CHAR] ~ = OR
    OVER [CHAR] ! = OR OVER [CHAR] $ = OR
    OVER [CHAR] & = OR OVER [CHAR] ' = OR
    OVER [CHAR] ( = OR OVER [CHAR] ) = OR
    OVER [CHAR] * = OR OVER [CHAR] + = OR
    OVER [CHAR] , = OR OVER [CHAR] ; = OR
    SWAP [CHAR] = = OR ;

\ Accept the conservative IPv6 core needed for an HTTP Host authority:
\ eight hexadecimal groups, or fewer groups with exactly one "::".
\ IPvFuture, zones, and embedded dotted-decimal forms remain rejected.
: _WREQ-IPV6?  ( inner-a inner-u request -- flag )
    0 OVER _WREQ.T0 !
    0 OVER _WREQ.T1 !
    0 OVER _WREQ.T2 !
    1 PICK 0= IF 2DROP DROP 0 EXIT THEN
    1 PICK 0 ?DO
        2 PICK I + C@ DUP _WREQ-HEXDIG? IF
            DROP
            DUP _WREQ.T1 @ 4 >= IF
                2DROP DROP 0 UNLOOP EXIT
            THEN
            1 OVER _WREQ.T1 +!
        ELSE
            [CHAR] : <> IF
                2DROP DROP 0 UNLOOP EXIT
            THEN
            DUP _WREQ.T1 @ 0> IF
                1 OVER _WREQ.T0 +!
                0 OVER _WREQ.T1 !
                DUP _WREQ.T0 @ 8 > IF
                    2DROP DROP 0 UNLOOP EXIT
                THEN
            ELSE
                I 0= IF
                    1 PICK 2 < IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                    2 PICK 1+ C@ [CHAR] : <> IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                ELSE
                    2 PICK I + 1- C@ [CHAR] : <> IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                    DUP _WREQ.T2 @ IF
                        2DROP DROP 0 UNLOOP EXIT
                    THEN
                    -1 OVER _WREQ.T2 !
                THEN
            THEN
        THEN
    LOOP
    DUP _WREQ.T1 @ 0> IF
        1 OVER _WREQ.T0 +!
        0 OVER _WREQ.T1 !
    ELSE
        1 PICK 2 < IF
            2DROP DROP 0 EXIT
        THEN
        2 PICK 2 PICK + 1- C@ [CHAR] : <> IF
            2DROP DROP 0 EXIT
        THEN
        2 PICK 2 PICK + 2 - C@ [CHAR] : <> IF
            2DROP DROP 0 EXIT
        THEN
    THEN
    DUP _WREQ.T2 @ IF
        DUP _WREQ.T0 @ 8 <
    ELSE
        DUP _WREQ.T0 @ 8 =
    THEN
    >R 2DROP DROP R> ;

\ Validate the Host field as an authority, not merely a nonempty string.
\ Brackets make an IP literal's colons unambiguous; an unbracketed host may
\ contain at most one colon and that colon must introduce a nonempty decimal
\ port.  Percent escapes, userinfo, slashes, and whitespace are excluded.
: _WREQ-HOST-AUTHORITY?  ( request -- flag )
    DUP WREQ.HEADER-A @ OVER _WREQ.T1 @ +
    OVER _WREQ.T2 @
    DUP 3 PICK _WREQ.T3 !
    OVER 3 PICK _WREQ.T4 !
    2DROP
    DUP _WREQ.T3 @ 0= IF DROP 0 EXIT THEN
    DUP _WREQ.T4 @ OVER _WREQ.T3 @ MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP _WREQ.T4 @ C@ [CHAR] [ = IF
        -1 OVER _WREQ.T5 !
        DUP _WREQ.T3 @ 1 ?DO
            DUP _WREQ.T4 @ I + C@ [CHAR] ] = IF
                DUP _WREQ.T5 @ 0>= IF
                    DROP 0 UNLOOP EXIT
                THEN
                I OVER _WREQ.T5 !
            THEN
        LOOP
        DUP _WREQ.T5 @ 1 <= IF DROP 0 EXIT THEN
        DUP _WREQ.T4 @ 1+
        OVER _WREQ.T5 @ 1-
        2 PICK _WREQ-IPV6? 0= IF DROP 0 EXIT THEN
        DUP _WREQ.T5 @ 1+
        OVER _WREQ.T3 @ = IF DROP -1 EXIT THEN
        DUP _WREQ.T5 @ 1+ OVER _WREQ.T3 @ >= IF
            DROP 0 EXIT
        THEN
        DUP _WREQ.T4 @ OVER _WREQ.T5 @ 1+ + C@ [CHAR] : <> IF
            DROP 0 EXIT
        THEN
        DUP _WREQ.T4 @ OVER _WREQ.T5 @ 2 + +
        OVER _WREQ.T3 @ 2 PICK _WREQ.T5 @ - 2 -
        _WREQ-DIGITS? NIP EXIT
    THEN
    -1 OVER _WREQ.T5 !
    DUP _WREQ.T3 @ 0 ?DO
        DUP _WREQ.T4 @ I + C@
        DUP [CHAR] : = IF
            DROP
            DUP _WREQ.T5 @ 0>= IF
                DROP 0 UNLOOP EXIT
            THEN
            I OVER _WREQ.T5 !
        ELSE
            _WREQ-REG-HOST-CHAR? 0= IF
                DROP 0 UNLOOP EXIT
            THEN
        THEN
    LOOP
    DUP _WREQ.T5 @ 0< IF DROP -1 EXIT THEN
    DUP _WREQ.T5 @ 0= IF DROP 0 EXIT THEN
    DUP _WREQ.T4 @ OVER _WREQ.T5 @ 1+ +
    OVER _WREQ.T3 @ 2 PICK _WREQ.T5 @ - 1-
    _WREQ-DIGITS? NIP ;

: _WREQ-STATE?  ( state -- flag )
    DUP WREQ-STATE-REQUEST-LINE >=
    SWAP WREQ-STATE-STOPPED <= AND ;

: _WREQ-RANGE?  ( offset length bound -- flag )
    >R
    OVER 0< OVER 0< OR IF 2DROP R> DROP 0 EXIT THEN
    OVER R@ > IF 2DROP R> DROP 0 EXIT THEN
    SWAP R> SWAP - <= ;

: _WREQ-STATUS-STATE?  ( request -- flag )
    DUP WREQ.STATE @
    DUP WREQ-STATE-HEADERS-READY = IF
        DROP WREQ.STATUS @ WREQ-S-HEADERS-READY = EXIT
    THEN
    DUP WREQ-STATE-DONE = IF
        DROP WREQ.STATUS @ WREQ-S-DONE = EXIT
    THEN
    DUP WREQ-STATE-STOPPED = IF
        DROP WREQ.STATUS @ DUP WREQ-S-INVALID >=
        SWAP WREQ-S-CANCELLED <= AND EXIT
    THEN
    DROP WREQ.STATUS @ WREQ-S-PENDING = ;

: _WREQ-DYNAMIC-VALID?  ( request -- flag )
    DUP WREQ.STATE @ _WREQ-STATE? 0= IF DROP 0 EXIT THEN
    DUP _WREQ-STATUS-STATE? 0= IF DROP 0 EXIT THEN
    DUP WREQ.FLAGS @ _WREQ-FLAGS-MASK INVERT AND IF DROP 0 EXIT THEN
    DUP WREQ.STATE @ WREQ-STATE-HEADERS-READY >=
    OVER WREQ.STATE @ WREQ-STATE-DONE <= AND IF
        DUP WREQ.FLAGS @ _WREQ-F-HEADERS-COMPLETE AND 0= IF
            DROP 0 EXIT
        THEN
    ELSE
        DUP WREQ.STATE @ WREQ-STATE-STOPPED <> IF
            DUP WREQ.FLAGS @ _WREQ-F-HEADERS-COMPLETE AND IF
                DROP 0 EXIT
            THEN
        THEN
    THEN
    DUP WREQ.HEADER-U @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER WREQ.HEADER-CAPACITY @ > IF DROP 0 EXIT THEN
    DUP WREQ.LINE-START @ OVER WREQ.LINE-U @
        2 PICK WREQ.HEADER-U @ _WREQ-RANGE? 0= IF DROP 0 EXIT THEN
    DUP WREQ.METHOD-OFFSET @ OVER WREQ.METHOD-U @
        2 PICK WREQ.HEADER-U @ _WREQ-RANGE? 0= IF DROP 0 EXIT THEN
    DUP WREQ.TARGET-OFFSET @ OVER WREQ.TARGET-U @
        2 PICK WREQ.HEADER-U @ _WREQ-RANGE? 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADERS-OFFSET @ OVER WREQ.HEADERS-U @
        2 PICK WREQ.HEADER-U @ _WREQ-RANGE? 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADER-COUNT @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER WREQ.HEADER-COUNT-LIMIT @ > IF DROP 0 EXIT THEN
    DUP WREQ.CONTENT-LENGTH @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER WREQ.BODY-LIMIT @ > IF DROP 0 EXIT THEN
    DUP WREQ.BODY-REMAINING @ DUP 0< IF 2DROP 0 EXIT THEN
    OVER WREQ.CONTENT-LENGTH @ > IF DROP 0 EXIT THEN
    DUP WREQ.FLAGS @ _WREQ-F-HEADERS-COMPLETE AND IF
        DUP WREQ.FLAGS @ _WREQ-F-HOST AND 0= IF DROP 0 EXIT THEN
        DUP WREQ.METHOD-U @ 0= IF DROP 0 EXIT THEN
        DUP WREQ.TARGET-U @ 0= IF DROP 0 EXIT THEN
    ELSE
        DUP WREQ.BODY-REMAINING @ IF DROP 0 EXIT THEN
    THEN
    DUP WREQ.BODY-U @ DUP 0< IF 2DROP 0 EXIT THEN
    DUP 2 PICK WREQ.BODY-REMAINING @ > IF 2DROP 0 EXIT THEN
    DUP 0> 2 PICK WREQ.BODY-A @ 0= AND IF 2DROP 0 EXIT THEN
    DUP 0= 2 PICK WREQ.BODY-A @ 0<> AND IF 2DROP 0 EXIT THEN
    DUP 0> IF
        1 PICK WREQ.BODY-A @ OVER MSPAN-NONWRAPPING? 0= IF
            2DROP 0 EXIT
        THEN
        1 PICK WREQ.BODY-A @ OVER
        3 PICK WEB-HTTP-REQUEST-STREAM-SIZE MSPAN-OVERLAP? IF
            2DROP 0 EXIT
        THEN
        1 PICK WREQ.BODY-A @ OVER
        3 PICK WREQ.HEADER-A @ 4 PICK WREQ.HEADER-CAPACITY @
        MSPAN-OVERLAP? IF
            2DROP 0 EXIT
        THEN
    THEN
    2DROP -1 ;

: WREQ-VALID?  ( request -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP WEB-HTTP-REQUEST-STREAM-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    DUP WREQ.HEADER-CAPACITY @ 0> 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADER-A @ 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADER-A @ OVER WREQ.HEADER-CAPACITY @
    MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADER-A @ OVER WREQ.HEADER-CAPACITY @
    2 PICK WEB-HTTP-REQUEST-STREAM-SIZE MSPAN-OVERLAP? IF
        DROP 0 EXIT
    THEN
    DUP WREQ.REQUEST-LINE-LIMIT @ 0> 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADER-LINE-LIMIT @ 0> 0= IF DROP 0 EXIT THEN
    DUP WREQ.HEADER-COUNT-LIMIT @ 0> 0= IF DROP 0 EXIT THEN
    DUP WREQ.BODY-LIMIT @ 0< IF DROP 0 EXIT THEN
    _WREQ-DYNAMIC-VALID? ;

: _WREQ-FAIL  ( status request -- status )
    >R
    DUP R@ WREQ.STATUS !
    WREQ-STATE-STOPPED R@ WREQ.STATE !
    R> DROP ;

: _WREQ-DYNAMIC-RESET  ( request -- )
    WREQ-STATE-REQUEST-LINE OVER WREQ.STATE !
    WREQ-S-PENDING OVER WREQ.STATUS !
    0 OVER WREQ.HEADER-U !
    0 OVER WREQ.LINE-START !
    0 OVER WREQ.LINE-U !
    0 OVER WREQ.METHOD-OFFSET !
    0 OVER WREQ.METHOD-U !
    0 OVER WREQ.TARGET-OFFSET !
    0 OVER WREQ.TARGET-U !
    0 OVER WREQ.HEADERS-OFFSET !
    0 OVER WREQ.HEADERS-U !
    0 OVER WREQ.HEADER-COUNT !
    0 OVER WREQ.CONTENT-LENGTH !
    0 OVER WREQ.BODY-REMAINING !
    0 OVER WREQ.FLAGS !
    0 OVER WREQ.BODY-A !
    0 OVER WREQ.BODY-U !
    0 OVER _WREQ.CALL-RESULT !
    0 OVER _WREQ.IN-A !
    0 OVER _WREQ.IN-U !
    0 OVER _WREQ.CONSUMED !
    0 OVER _WREQ.T0 !
    0 OVER _WREQ.T1 !
    0 OVER _WREQ.T2 !
    0 OVER _WREQ.T3 !
    0 OVER _WREQ.T4 !
    0 SWAP _WREQ.T5 ! ;

: WREQ-INIT
    ( header-a header-capacity body-limit body-xt context request -- status )
    DUP 0= IF
        2DROP 2DROP 2DROP WREQ-S-INVALID EXIT
    THEN
    DUP WEB-HTTP-REQUEST-STREAM-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP 2DROP 2DROP WREQ-S-INVALID EXIT
    THEN
    DUP WREQ-VALID? IF
        DUP WREQ.FLAGS @ _WREQ-F-IN-CALLBACK AND IF
            2DROP 2DROP 2DROP WREQ-S-STATE EXIT
        THEN
    THEN
    >R
    R@ WEB-HTTP-REQUEST-STREAM-SIZE 0 FILL
    R@ WREQ.CONTEXT !
    R@ WREQ.BODY-XT !
    R@ WREQ.BODY-LIMIT !
    R@ WREQ.HEADER-CAPACITY !
    R@ WREQ.HEADER-A !
    WREQ-DEFAULT-REQUEST-LINE-LIMIT R@ WREQ.REQUEST-LINE-LIMIT !
    WREQ-DEFAULT-HEADER-LINE-LIMIT R@ WREQ.HEADER-LINE-LIMIT !
    WREQ-DEFAULT-HEADER-COUNT-LIMIT R@ WREQ.HEADER-COUNT-LIMIT !
    R@ WREQ-VALID? 0= IF
        WREQ-S-INVALID R@ WREQ.STATUS !
        WREQ-STATE-STOPPED R@ WREQ.STATE !
        R> DROP WREQ-S-INVALID EXIT
    THEN
    R@ _WREQ-DYNAMIC-RESET
    R> DROP WREQ-S-PENDING ;

: WREQ-LIMITS!
    ( request-line header-line header-count body-limit request -- status )
    DUP WREQ-VALID? 0= IF
        2DROP 2DROP DROP WREQ-S-INVALID EXIT
    THEN
    DUP WREQ.STATE @ WREQ-STATE-REQUEST-LINE <>
    OVER WREQ.HEADER-U @ 0<> OR IF
        2DROP 2DROP DROP WREQ-S-STATE EXIT
    THEN
    >R
    R@ _WREQ.T0 !
    R@ _WREQ.T1 !
    R@ _WREQ.T2 !
    R@ _WREQ.T3 !
    R@ _WREQ.T3 @ 0> 0=
    R@ _WREQ.T2 @ 0> 0= OR
    R@ _WREQ.T1 @ 0> 0= OR
    R@ _WREQ.T0 @ 0< OR IF
        R> DROP WREQ-S-INVALID EXIT
    THEN
    R@ _WREQ.T3 @ R@ WREQ.REQUEST-LINE-LIMIT !
    R@ _WREQ.T2 @ R@ WREQ.HEADER-LINE-LIMIT !
    R@ _WREQ.T1 @ R@ WREQ.HEADER-COUNT-LIMIT !
    R@ _WREQ.T0 @ R@ WREQ.BODY-LIMIT !
    R> DROP WREQ-S-PENDING ;

: WREQ-RESET  ( request -- status )
    DUP WREQ-VALID? 0= IF DROP WREQ-S-INVALID EXIT THEN
    DUP WREQ.FLAGS @ _WREQ-F-IN-CALLBACK AND IF
        DROP WREQ-S-STATE EXIT
    THEN
    DUP WREQ.HEADER-U @ DUP 0> IF
        OVER WREQ.HEADER-A @ SWAP 0 FILL
    ELSE
        DROP
    THEN
    _WREQ-DYNAMIC-RESET
    WREQ-S-PENDING ;

: _WREQ-HEAD-BYTE  ( c request -- status )
    >R
    R@ WREQ.HEADER-U @ R@ WREQ.HEADER-CAPACITY @ >= IF
        DROP R> DROP WREQ-S-HEADER-OVERFLOW EXIT
    THEN
    R@ WREQ.HEADER-A @ R@ WREQ.HEADER-U @ + C!
    1 R@ WREQ.HEADER-U +!
    R> DROP WREQ-S-PENDING ;

: _WREQ-PARSE-REQUEST-LINE  ( request -- status )
    DUP WREQ.LINE-U @ 0= IF DROP WREQ-S-MALFORMED EXIT THEN
    -1 OVER _WREQ.T0 !
    -1 OVER _WREQ.T1 !
    DUP WREQ.HEADER-A @ OVER WREQ.LINE-START @ + SWAP
    DUP WREQ.LINE-U @ 0 ?DO
        OVER I + C@ 32 = IF
            DUP _WREQ.T0 @ 0< IF
                I OVER _WREQ.T0 !
            ELSE
                DUP _WREQ.T1 @ 0< IF
                    I OVER _WREQ.T1 !
                ELSE
                    2DROP WREQ-S-MALFORMED UNLOOP EXIT
                THEN
            THEN
        THEN
    LOOP
    NIP
    DUP _WREQ.T0 @ 1 < IF DROP WREQ-S-MALFORMED EXIT THEN
    DUP _WREQ.T1 @ OVER _WREQ.T0 @ 1+ <= IF
        DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP WREQ.LINE-U @ OVER _WREQ.T1 @ 1+ - 8 <> IF
        DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP WREQ.HEADER-A @ OVER WREQ.LINE-START @ +
    OVER _WREQ.T1 @ + 1+ 8 S" HTTP/1.1" COMPARE IF
        DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP WREQ.HEADER-A @ OVER WREQ.LINE-START @ +
    OVER _WREQ.T0 @ _WREQ-TOKEN? 0= IF
        DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP WREQ.HEADER-A @ OVER WREQ.LINE-START @ +
    OVER _WREQ.T0 @ + 1+
    OVER _WREQ.T1 @ 2 PICK _WREQ.T0 @ - 1-
    2 PICK _WREQ-TARGET? 0= IF
        DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP WREQ.LINE-START @ OVER WREQ.METHOD-OFFSET !
    DUP _WREQ.T0 @ OVER WREQ.METHOD-U !
    DUP WREQ.LINE-START @ OVER _WREQ.T0 @ + 1+
    OVER WREQ.TARGET-OFFSET !
    DUP _WREQ.T1 @ OVER _WREQ.T0 @ - 1-
    SWAP WREQ.TARGET-U !
    WREQ-S-PENDING ;

: _WREQ-HEADER-NAME=?  ( literal-a literal-u request -- flag )
    >R
    R@ WREQ.HEADER-A @ R@ WREQ.LINE-START @ + R@ _WREQ.T0 @
    2SWAP _WREQ-CIEQ?
    R> DROP ;

: _WREQ-CURRENT-VALUE  ( request -- value-a value-u )
    DUP WREQ.HEADER-A @ OVER _WREQ.T1 @ +
    SWAP _WREQ.T2 @ ;

: _WREQ-DECIMAL  ( addr len request -- status )
    OVER 0= IF 2DROP DROP WREQ-S-FRAMING EXIT THEN
    0 OVER _WREQ.T3 !
    SWAP 0 ?DO
        OVER I + C@ DUP 48 < OVER 57 > OR IF
            DROP 2DROP WREQ-S-FRAMING UNLOOP EXIT
        THEN
        48 - OVER _WREQ.T4 !
        DUP _WREQ.T4 @ OVER WREQ.BODY-LIMIT @ > IF
            2DROP WREQ-S-BODY-OVERFLOW UNLOOP EXIT
        THEN
        DUP WREQ.BODY-LIMIT @ OVER _WREQ.T4 @ - 10 /
        OVER _WREQ.T3 @ SWAP > IF
            2DROP WREQ-S-BODY-OVERFLOW UNLOOP EXIT
        THEN
        DUP _WREQ.T3 @ 10 * OVER _WREQ.T4 @ +
        OVER _WREQ.T3 !
    LOOP
    NIP
    DUP _WREQ.T3 @ OVER WREQ.CONTENT-LENGTH !
    DROP WREQ-S-PENDING ;

: _WREQ-PARSE-HEADER  ( request -- status )
    DUP WREQ.LINE-U @ 0= IF DROP WREQ-S-MALFORMED EXIT THEN
    DUP WREQ.HEADER-A @ OVER WREQ.LINE-START @ + C@
    DUP 32 = SWAP 9 = OR IF DROP WREQ-S-MALFORMED EXIT THEN
    DUP WREQ.HEADER-COUNT @ OVER WREQ.HEADER-COUNT-LIMIT @ >= IF
        DROP WREQ-S-HEADER-COUNT EXIT
    THEN
    1 OVER WREQ.HEADER-COUNT +!
    -1 OVER _WREQ.T0 !
    DUP WREQ.HEADER-A @ OVER WREQ.LINE-START @ + SWAP
    DUP WREQ.LINE-U @ 0 ?DO
        OVER I + C@
        OVER _WREQ.T0 @ 0< IF
            DUP 58 = IF
                DROP I OVER _WREQ.T0 ! -1
            ELSE
                _WREQ-TCHAR?
            THEN
        ELSE
            _WREQ-VALUE-CHAR?
        THEN
        0= IF
            2DROP WREQ-S-MALFORMED UNLOOP EXIT
        THEN
    LOOP
    NIP
    DUP _WREQ.T0 @ 1 < IF DROP WREQ-S-MALFORMED EXIT THEN
    DUP WREQ.LINE-START @ OVER _WREQ.T0 @ + 1+
    OVER _WREQ.T1 !
    DUP WREQ.LINE-U @ OVER _WREQ.T0 @ - 1-
    OVER _WREQ.T2 !
    BEGIN
        DUP _WREQ.T2 @ 0> IF
            DUP WREQ.HEADER-A @ OVER _WREQ.T1 @ + C@ _WREQ-OWS?
        ELSE
            0
        THEN
    WHILE
        1 OVER _WREQ.T1 +!
        -1 OVER _WREQ.T2 +!
    REPEAT
    BEGIN
        DUP _WREQ.T2 @ 0> IF
            DUP WREQ.HEADER-A @ OVER _WREQ.T1 @ +
            OVER _WREQ.T2 @ 1- + C@ _WREQ-OWS?
        ELSE
            0
        THEN
    WHILE
        -1 OVER _WREQ.T2 +!
    REPEAT

    S" Host" 2 PICK _WREQ-HEADER-NAME=? IF
        DUP WREQ.FLAGS @ _WREQ-F-HOST AND IF
            DROP WREQ-S-FRAMING EXIT
        THEN
        DUP _WREQ-HOST-AUTHORITY? 0= IF
            DROP WREQ-S-MALFORMED EXIT
        THEN
        DUP WREQ.FLAGS DUP @ _WREQ-F-HOST OR SWAP !
        DROP WREQ-S-PENDING EXIT
    THEN
    S" Transfer-Encoding" 2 PICK _WREQ-HEADER-NAME=? IF
        DROP WREQ-S-FRAMING EXIT
    THEN
    S" Expect" 2 PICK _WREQ-HEADER-NAME=? IF
        DROP WREQ-S-FRAMING EXIT
    THEN
    S" Content-Length" 2 PICK _WREQ-HEADER-NAME=? IF
        DUP WREQ.FLAGS @ _WREQ-F-CONTENT-LENGTH AND IF
            DROP WREQ-S-FRAMING EXIT
        THEN
        DUP _WREQ-CURRENT-VALUE 2 PICK _WREQ-DECIMAL
        DUP IF NIP EXIT THEN DROP
        DUP WREQ.FLAGS DUP @ _WREQ-F-CONTENT-LENGTH OR SWAP !
    THEN
    DROP WREQ-S-PENDING ;

: _WREQ-FINAL-HEADERS  ( request -- status )
    DUP WREQ.FLAGS @ _WREQ-F-HOST AND 0= IF
        DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP WREQ.HEADER-U @ OVER WREQ.HEADERS-OFFSET @ -
    DUP 2 < IF 2DROP WREQ-S-MALFORMED EXIT THEN
    2 - OVER WREQ.HEADERS-U !
    DUP WREQ.CONTENT-LENGTH @ DUP
    2 PICK WREQ.BODY-REMAINING !
    DROP
    DUP WREQ.FLAGS DUP @ _WREQ-F-HEADERS-COMPLETE OR SWAP !
    WREQ-STATE-HEADERS-READY OVER WREQ.STATE !
    WREQ-S-HEADERS-READY SWAP WREQ.STATUS !
    WREQ-S-PENDING ;

: _WREQ-FINISH-REQUEST-LINE  ( request -- status )
    DUP _WREQ-PARSE-REQUEST-LINE DUP IF NIP EXIT THEN DROP
    DUP WREQ.HEADER-U @ OVER WREQ.HEADERS-OFFSET !
    DUP WREQ.HEADER-U @ OVER WREQ.LINE-START !
    0 OVER WREQ.LINE-U !
    WREQ-STATE-HEADERS SWAP WREQ.STATE !
    WREQ-S-PENDING ;

: _WREQ-FINISH-HEADER-LINE  ( request -- status )
    DUP WREQ.LINE-U @ 0= IF
        _WREQ-FINAL-HEADERS EXIT
    THEN
    DUP _WREQ-PARSE-HEADER DUP IF NIP EXIT THEN DROP
    DUP WREQ.HEADER-U @ OVER WREQ.LINE-START !
    0 OVER WREQ.LINE-U !
    WREQ-STATE-HEADERS SWAP WREQ.STATE !
    WREQ-S-PENDING ;

: _WREQ-CONSUME-LINE-BYTE  ( request -- status )
    DUP _WREQ.IN-A @ C@ DUP 10 = IF
        2DROP WREQ-S-MALFORMED EXIT
    THEN
    DUP 13 = IF
        DROP 13 OVER _WREQ-HEAD-BYTE
        DUP IF NIP EXIT THEN DROP
        DUP WREQ.STATE @ WREQ-STATE-REQUEST-LINE = IF
            WREQ-STATE-REQUEST-LINE-LF
        ELSE
            WREQ-STATE-HEADERS-LF
        THEN
        SWAP WREQ.STATE !
        WREQ-S-PENDING EXIT
    THEN
    OVER _WREQ.T5 !
    DUP WREQ.STATE @ WREQ-STATE-REQUEST-LINE = IF
        DUP WREQ.LINE-U @ OVER WREQ.REQUEST-LINE-LIMIT @ >= IF
            DROP WREQ-S-REQUEST-LINE-OVERFLOW EXIT
        THEN
    ELSE
        DUP WREQ.LINE-U @ OVER WREQ.HEADER-LINE-LIMIT @ >= IF
            DROP WREQ-S-HEADER-LINE-OVERFLOW EXIT
        THEN
        DUP WREQ.LINE-U @ 0= IF
            DUP _WREQ.T5 @ DUP 32 = SWAP 9 = OR IF
                DROP WREQ-S-MALFORMED EXIT
            THEN
        THEN
    THEN
    DUP _WREQ.T5 @ OVER _WREQ-HEAD-BYTE
    DUP IF NIP EXIT THEN DROP
    1 SWAP WREQ.LINE-U +!
    WREQ-S-PENDING ;

: _WREQ-CONSUME-LF  ( request -- status )
    DUP _WREQ.IN-A @ C@ 10 <> IF DROP WREQ-S-MALFORMED EXIT THEN
    10 OVER _WREQ-HEAD-BYTE DUP IF NIP EXIT THEN DROP
    DUP WREQ.STATE @ WREQ-STATE-REQUEST-LINE-LF = IF
        _WREQ-FINISH-REQUEST-LINE
    ELSE
        _WREQ-FINISH-HEADER-LINE
    THEN ;

: _WREQ-ADVANCE  ( count request -- )
    >R
    DUP R@ _WREQ.IN-A +!
    DUP NEGATE R@ _WREQ.IN-U +!
    R@ _WREQ.CONSUMED +!
    R> DROP ;

: _WREQ-HEAD-STEP  ( request -- )
    DUP WREQ.STATE @ DUP WREQ-STATE-REQUEST-LINE =
    SWAP WREQ-STATE-HEADERS = OR IF
        DUP _WREQ-CONSUME-LINE-BYTE
    ELSE
        DUP _WREQ-CONSUME-LF
    THEN
    >R
    1 OVER _WREQ-ADVANCE
    R> ?DUP IF OVER _WREQ-FAIL DROP THEN
    DROP ;

: _WREQ-CALL-BODY-INNER  ( request -- request )
    DUP DUP WREQ.CONTEXT @
    2 PICK WREQ.BODY-XT @ EXECUTE
    OVER _WREQ.CALL-RESULT ! ;

: _WREQ-CALL-BODY  ( request -- status )
    DUP WREQ.BODY-XT @ 0= IF DROP WREQ-S-PENDING EXIT THEN
    0 OVER _WREQ.CALL-RESULT !
    DUP WREQ.FLAGS DUP @ _WREQ-F-IN-CALLBACK OR SWAP !
    ['] _WREQ-CALL-BODY-INNER CATCH DUP IF
        OVER WREQ.FLAGS DUP @ _WREQ-F-IN-CALLBACK INVERT AND SWAP !
        2DROP WREQ-S-CALLBACK EXIT
    THEN
    DROP
    DUP WREQ.FLAGS DUP @ _WREQ-F-IN-CALLBACK INVERT AND SWAP !
    DUP _WREQ.CALL-RESULT @ IF DROP WREQ-S-CALLBACK EXIT THEN
    DROP WREQ-S-PENDING ;

: _WREQ-BODY-STEP  ( request -- )
    DUP _WREQ.IN-U @ OVER WREQ.BODY-REMAINING @ MIN
    OVER WREQ.BODY-U !
    DUP _WREQ.IN-A @ OVER WREQ.BODY-A !
    DUP _WREQ-CALL-BODY ?DUP IF
        0 OVER WREQ.BODY-A !
        0 OVER WREQ.BODY-U !
        OVER _WREQ-FAIL DROP
        DROP EXIT
    THEN
    DUP WREQ.BODY-U @ >R
    0 OVER WREQ.BODY-A !
    0 OVER WREQ.BODY-U !
    R@ NEGATE OVER WREQ.BODY-REMAINING +!
    R> OVER _WREQ-ADVANCE
    DUP WREQ.BODY-REMAINING @ 0= IF
        WREQ-STATE-DONE OVER WREQ.STATE !
        WREQ-S-DONE OVER WREQ.STATUS !
    THEN
    DROP ;

: _WREQ-DISCARD-STEP  ( request -- )
    DUP _WREQ.IN-U @ OVER WREQ.BODY-REMAINING @ MIN
    >R
    R@ NEGATE OVER WREQ.BODY-REMAINING +!
    R> OVER _WREQ-ADVANCE
    DUP WREQ.BODY-REMAINING @ 0= IF
        WREQ-STATE-DONE OVER WREQ.STATE !
        WREQ-S-DONE OVER WREQ.STATUS !
    THEN
    DROP ;

: _WREQ-BODY-DECISION  ( next-state request -- status )
    DUP WREQ-VALID? 0= IF 2DROP WREQ-S-INVALID EXIT THEN
    DUP WREQ.STATE @ WREQ-STATE-HEADERS-READY <> IF
        2DROP WREQ-S-STATE EXIT
    THEN
    DUP WREQ.BODY-REMAINING @ 0= IF
        NIP
        WREQ-STATE-DONE OVER WREQ.STATE !
        WREQ-S-DONE SWAP WREQ.STATUS !
        WREQ-S-DONE EXIT
    THEN
    WREQ-S-PENDING OVER WREQ.STATUS !
    SWAP OVER WREQ.STATE !
    DROP WREQ-S-PENDING ;

: WREQ-BODY-CONTINUE  ( request -- status )
    DUP WREQ-VALID? 0= IF DROP WREQ-S-INVALID EXIT THEN
    DUP WREQ.STATE @ WREQ-STATE-HEADERS-READY <> IF
        DROP WREQ-S-STATE EXIT
    THEN
    DUP WREQ.BODY-REMAINING @ 0> OVER WREQ.BODY-XT @ 0= AND IF
        DROP WREQ-S-CALLBACK EXIT
    THEN
    WREQ-STATE-BODY SWAP _WREQ-BODY-DECISION ;

: WREQ-BODY-DISCARD  ( request -- status )
    WREQ-STATE-DISCARD SWAP _WREQ-BODY-DECISION ;

: _WREQ-FEED-RESULT  ( request -- consumed status )
    DUP _WREQ.CONSUMED @
    OVER WREQ.STATUS @
    0 3 PICK _WREQ.IN-A !
    0 3 PICK _WREQ.IN-U !
    ROT DROP ;

: WREQ-FEED  ( addr len request -- consumed status )
    DUP WREQ-VALID? 0= IF
        2DROP DROP 0 WREQ-S-INVALID EXIT
    THEN
    DUP WREQ.FLAGS @ _WREQ-F-IN-CALLBACK AND IF
        2DROP DROP 0 WREQ-S-STATE EXIT
    THEN
    >R
    DUP 0< IF 2DROP R> DROP 0 WREQ-S-INVALID EXIT THEN
    DUP 0> 2 PICK 0= AND IF
        2DROP R> DROP 0 WREQ-S-INVALID EXIT
    THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP 0 WREQ-S-INVALID EXIT
    THEN
    2DUP R@ WEB-HTTP-REQUEST-STREAM-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 WREQ-S-INVALID EXIT
    THEN
    2DUP R@ WREQ.HEADER-A @ R@ WREQ.HEADER-CAPACITY @
        MSPAN-OVERLAP? IF
        2DROP R> DROP 0 WREQ-S-INVALID EXIT
    THEN
    DUP R@ _WREQ.IN-U !
    OVER R@ _WREQ.IN-A !
    2DROP
    0 R@ _WREQ.CONSUMED !
    R>
    BEGIN
        DUP _WREQ.IN-U @ 0>
        OVER WREQ.STATUS @ WREQ-S-PENDING = AND
    WHILE
        DUP WREQ.STATE @ CASE
            WREQ-STATE-REQUEST-LINE OF DUP _WREQ-HEAD-STEP ENDOF
            WREQ-STATE-REQUEST-LINE-LF OF DUP _WREQ-HEAD-STEP ENDOF
            WREQ-STATE-HEADERS OF DUP _WREQ-HEAD-STEP ENDOF
            WREQ-STATE-HEADERS-LF OF DUP _WREQ-HEAD-STEP ENDOF
            WREQ-STATE-BODY OF DUP _WREQ-BODY-STEP ENDOF
            WREQ-STATE-DISCARD OF DUP _WREQ-DISCARD-STEP ENDOF
            WREQ-S-STATE 2 PICK _WREQ-FAIL DROP
        ENDCASE
    REPEAT
    _WREQ-FEED-RESULT ;

: WREQ-EOF  ( request -- status )
    DUP WREQ-VALID? 0= IF DROP WREQ-S-INVALID EXIT THEN
    DUP WREQ.FLAGS @ _WREQ-F-IN-CALLBACK AND IF
        DROP WREQ-S-STATE EXIT
    THEN
    DUP WREQ.STATE @ WREQ-STATE-DONE = IF
        DROP WREQ-S-DONE EXIT
    THEN
    DUP WREQ.STATE @ WREQ-STATE-STOPPED = IF
        WREQ.STATUS @ EXIT
    THEN
    WREQ-S-TRUNCATED SWAP _WREQ-FAIL ;

: WREQ-CANCEL  ( request -- status )
    DUP WREQ-VALID? 0= IF DROP WREQ-S-INVALID EXIT THEN
    DUP WREQ.FLAGS @ _WREQ-F-IN-CALLBACK AND IF
        DROP WREQ-S-STATE EXIT
    THEN
    DUP WREQ.STATE @ WREQ-STATE-DONE = IF
        DROP WREQ-S-DONE EXIT
    THEN
    DUP WREQ.STATE @ WREQ-STATE-STOPPED = IF
        WREQ.STATUS @ EXIT
    THEN
    WREQ-S-CANCELLED SWAP _WREQ-FAIL ;

: WREQ-DONE?  ( request -- flag )
    DUP WREQ-VALID? 0= IF DROP 0 EXIT THEN
    WREQ.STATE @ WREQ-STATE-DONE = ;

: WREQ-HEADERS-READY?  ( request -- flag )
    DUP WREQ-VALID? 0= IF DROP 0 EXIT THEN
    WREQ.STATE @ WREQ-STATE-HEADERS-READY = ;

: _WREQ-METADATA?  ( request -- flag )
    DUP WREQ-VALID? 0= IF DROP 0 EXIT THEN
    WREQ.FLAGS @ _WREQ-F-HEADERS-COMPLETE AND 0<> ;

: WREQ-METHOD  ( request -- method-a method-u )
    DUP _WREQ-METADATA? 0= IF DROP 0 0 EXIT THEN
    DUP WREQ.HEADER-A @ OVER WREQ.METHOD-OFFSET @ +
    SWAP WREQ.METHOD-U @ ;

: WREQ-TARGET  ( request -- target-a target-u )
    DUP _WREQ-METADATA? 0= IF DROP 0 0 EXIT THEN
    DUP WREQ.HEADER-A @ OVER WREQ.TARGET-OFFSET @ +
    SWAP WREQ.TARGET-U @ ;

: WREQ-HEADERS  ( request -- headers-a headers-u )
    DUP _WREQ-METADATA? 0= IF DROP 0 0 EXIT THEN
    DUP WREQ.HEADER-A @ OVER WREQ.HEADERS-OFFSET @ +
    SWAP WREQ.HEADERS-U @ ;

: WREQ-BODY-SLICE  ( request -- body-a body-u )
    DUP WREQ.BODY-A @ SWAP WREQ.BODY-U @ ;

: WREQ-HEADER-LOOKUP  ( name-a name-u request -- value-a value-u count flag )
    DUP _WREQ-METADATA? 0= IF 2DROP DROP 0 0 0 0 EXIT THEN
    2 PICK 2 PICK _WREQ-TOKEN? 0= IF
        2DROP DROP 0 0 0 0 EXIT
    THEN
    >R
    2DUP R@ WEB-HTTP-REQUEST-STREAM-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP 0 0 0 0 EXIT
    THEN
    DUP R@ _WREQ.T1 !
    OVER R@ _WREQ.T0 !
    2DROP
    R@ WREQ.HEADERS-OFFSET @ R@ _WREQ.T2 !
    R@ WREQ.HEADERS-OFFSET @ R@ WREQ.HEADERS-U @ +
    R@ _WREQ.T3 !
    0 0 0 R>
    BEGIN
        DUP _WREQ.T2 @ OVER _WREQ.T3 @ <
    WHILE
        DUP _WREQ.T2 @ OVER _WREQ.T5 !
        BEGIN
            DUP _WREQ.T5 @ OVER _WREQ.T3 @ <
            IF
                DUP WREQ.HEADER-A @ OVER _WREQ.T5 @ + C@ 13 <>
            ELSE
                0
            THEN
        WHILE
            1 OVER _WREQ.T5 +!
        REPEAT
        DUP _WREQ.T5 @ OVER _WREQ.T3 @ >= IF
            2DROP 2DROP 0 0 0 0 EXIT
        THEN
        DUP _WREQ.T5 @ 1+ OVER _WREQ.T3 @ >= IF
            2DROP 2DROP 0 0 0 0 EXIT
        THEN
        DUP WREQ.HEADER-A @ OVER _WREQ.T5 @ + 1+ C@ 10 <> IF
            2DROP 2DROP 0 0 0 0 EXIT
        THEN
        DUP _WREQ.T2 @ OVER _WREQ.T4 !
        BEGIN
            DUP _WREQ.T4 @ OVER _WREQ.T5 @ <
            IF
                DUP WREQ.HEADER-A @ OVER _WREQ.T4 @ + C@ 58 <>
            ELSE
                0
            THEN
        WHILE
            1 OVER _WREQ.T4 +!
        REPEAT
        DUP _WREQ.T4 @ OVER _WREQ.T5 @ >= IF
            2DROP 2DROP 0 0 0 0 EXIT
        THEN
        DUP WREQ.HEADER-A @ OVER _WREQ.T2 @ +
        OVER _WREQ.T4 @ 2 PICK _WREQ.T2 @ -
        2 PICK _WREQ.T0 @ 3 PICK _WREQ.T1 @ _WREQ-CIEQ? IF
            DUP _WREQ.T5 @ 2 + OVER _WREQ.T2 !
            DUP _WREQ.T4 @ 1+ OVER _WREQ.T4 !
            BEGIN
                DUP _WREQ.T4 @ OVER _WREQ.T5 @ <
                IF
                    DUP WREQ.HEADER-A @ OVER _WREQ.T4 @ + C@
                    _WREQ-OWS?
                ELSE
                    0
                THEN
            WHILE
                1 OVER _WREQ.T4 +!
            REPEAT
            BEGIN
                DUP _WREQ.T5 @ OVER _WREQ.T4 @ >
                IF
                    DUP WREQ.HEADER-A @ OVER _WREQ.T5 @ 1- + C@
                    _WREQ-OWS?
                ELSE
                    0
                THEN
            WHILE
                -1 OVER _WREQ.T5 +!
            REPEAT
            OVER 0= IF
                >R DROP 2DROP
                R@ WREQ.HEADER-A @ R@ _WREQ.T4 @ +
                R@ _WREQ.T5 @ R@ _WREQ.T4 @ -
                1 R>
            ELSE
                SWAP 1+ SWAP
            THEN
        ELSE
            DUP _WREQ.T5 @ 2 + OVER _WREQ.T2 !
        THEN
    REPEAT
    DROP -1 ;

\ LOOKUP returns the first trimmed value and the complete occurrence count.
: WREQ-HEADER-COUNT  ( name-a name-u request -- count flag )
    WREQ-HEADER-LOOKUP >R NIP NIP R> ;

\ Convenience lookup only: duplicate-sensitive callers use LOOKUP or COUNT.
: WREQ-HEADER  ( name-a name-u request -- value-a value-u flag )
    WREQ-HEADER-LOOKUP
    0= IF 2DROP DROP 0 0 0 EXIT THEN
    0> IF -1 ELSE 2DROP 0 0 0 THEN ;

\ All persistent and scratch mutation is descriptor-local.  Distinct request
\ descriptors can therefore be interleaved by a cooperative server.  As with
\ the existing transport primitives, a future preemptive runtime must still
\ serialize an individual descriptor while one of its words is executing.
