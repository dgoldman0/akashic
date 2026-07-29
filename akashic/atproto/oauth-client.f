\ =====================================================================
\  oauth-client.f - AT Protocol policy over generic OAuth client config
\ =====================================================================
\  This state-free adapter qualifies one immutable generic OAuth client
\  selection against the AT Protocol client profile and one ready AT OAuth
\  server profile.  It performs no HTTP, metadata hosting, browser launch,
\  key lookup, assertion signing, DPoP construction, token work, persistence,
\  XRPC, or Streams work.
\
\  Exact configured client and redirect bytes remain owned by the generic
\  configuration.  The caller-owned workspace retains only transient parse
\  state and is wiped after every admitted result.
\ =====================================================================

PROVIDED akashic-at-oauth-client

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../security/oauth2/client-config.f
REQUIRE oauth-profile.f

\ =====================================================================
\  Public status vocabulary
\ =====================================================================

0  CONSTANT AT-OAUTH-CLIENT-S-OK
1  CONSTANT AT-OAUTH-CLIENT-S-INVALID
2  CONSTANT AT-OAUTH-CLIENT-S-ALIAS
3  CONSTANT AT-OAUTH-CLIENT-S-CONFIG
4  CONSTANT AT-OAUTH-CLIENT-S-PROFILE
5  CONSTANT AT-OAUTH-CLIENT-S-CLIENT-ID
6  CONSTANT AT-OAUTH-CLIENT-S-REDIRECT
7  CONSTANT AT-OAUTH-CLIENT-S-SCOPE
8  CONSTANT AT-OAUTH-CLIENT-S-AUTH-METHOD
9  CONSTANT AT-OAUTH-CLIENT-S-AUTH-ALGORITHM
10 CONSTANT AT-OAUTH-CLIENT-S-DPOP
11 CONSTANT AT-OAUTH-CLIENT-S-RANGE
12 CONSTANT AT-OAUTH-CLIENT-S-PROTECTED
13 CONSTANT AT-OAUTH-CLIENT-S-PLATFORM
14 CONSTANT AT-OAUTH-CLIENT-S-INTERNAL

: AT-OAUTH-CLIENT-STATUS-VALID?  ( status -- flag )
    DUP AT-OAUTH-CLIENT-S-OK >=
    SWAP AT-OAUTH-CLIENT-S-INTERNAL <= AND ;

\ =====================================================================
\  Caller-owned transient workspace
\ =====================================================================

\ ACTIVE carries the profile during callback preflight and the borrowed
\ configuration view after readiness.  Preflight restores its original cell.
  0 CONSTANT _ATOCW-ACTIVE
  8 CONSTANT _ATOCW-CLIENT-ID-A
 16 CONSTANT _ATOCW-CLIENT-ID-U
 24 CONSTANT _ATOCW-REDIRECT-A
 32 CONSTANT _ATOCW-REDIRECT-U
 40 CONSTANT _ATOCW-APPLICATION
 48 CONSTANT _ATOCW-URL-A
 56 CONSTANT _ATOCW-URL-U
 64 CONSTANT _ATOCW-AUTH-END
 72 CONSTANT _ATOCW-HOST-A
 80 CONSTANT _ATOCW-HOST-U
 88 CONSTANT _ATOCW-PORT
 96 CONSTANT _ATOCW-PORT-EXPLICIT
104 CONSTANT _ATOCW-PATH-A
112 CONSTANT _ATOCW-PATH-U
120 CONSTANT _ATOCW-COLON
128 CONSTANT _ATOCW-CLIENT-HOST-A
136 CONSTANT _ATOCW-CLIENT-HOST-U
144 CONSTANT _ATOCW-ALLOW-PORT
152 CONSTANT _ATOCW-REQUIRE-PATH
160 CONSTANT _ATOCW-ALLOW-QUERY
168 CONSTANT _ATOCW-QUERY
176 CONSTANT _ATOCW-REVERSE
432 CONSTANT AT-OAUTH-CLIENT-WORKSPACE-SIZE

: _ATOCW.ACTIVE          ( workspace -- address ) _ATOCW-ACTIVE + ;
: _ATOCW.CLIENT-ID-A     ( workspace -- address )
    _ATOCW-CLIENT-ID-A + ;
: _ATOCW.CLIENT-ID-U     ( workspace -- address )
    _ATOCW-CLIENT-ID-U + ;
: _ATOCW.REDIRECT-A      ( workspace -- address )
    _ATOCW-REDIRECT-A + ;
: _ATOCW.REDIRECT-U      ( workspace -- address )
    _ATOCW-REDIRECT-U + ;
: _ATOCW.APPLICATION     ( workspace -- address )
    _ATOCW-APPLICATION + ;
: _ATOCW.URL-A           ( workspace -- address ) _ATOCW-URL-A + ;
: _ATOCW.URL-U           ( workspace -- address ) _ATOCW-URL-U + ;
: _ATOCW.AUTH-END        ( workspace -- address ) _ATOCW-AUTH-END + ;
: _ATOCW.HOST-A          ( workspace -- address ) _ATOCW-HOST-A + ;
: _ATOCW.HOST-U          ( workspace -- address ) _ATOCW-HOST-U + ;
: _ATOCW.PORT            ( workspace -- address ) _ATOCW-PORT + ;
: _ATOCW.PORT-EXPLICIT   ( workspace -- address )
    _ATOCW-PORT-EXPLICIT + ;
: _ATOCW.PATH-A          ( workspace -- address ) _ATOCW-PATH-A + ;
: _ATOCW.PATH-U          ( workspace -- address ) _ATOCW-PATH-U + ;
: _ATOCW.COLON           ( workspace -- address ) _ATOCW-COLON + ;
: _ATOCW.CLIENT-HOST-A   ( workspace -- address )
    _ATOCW-CLIENT-HOST-A + ;
: _ATOCW.CLIENT-HOST-U   ( workspace -- address )
    _ATOCW-CLIENT-HOST-U + ;
: _ATOCW.ALLOW-PORT      ( workspace -- address )
    _ATOCW-ALLOW-PORT + ;
: _ATOCW.REQUIRE-PATH    ( workspace -- address )
    _ATOCW-REQUIRE-PATH + ;
: _ATOCW.ALLOW-QUERY     ( workspace -- address )
    _ATOCW-ALLOW-QUERY + ;
: _ATOCW.QUERY           ( workspace -- address ) _ATOCW-QUERY + ;
: _ATOCW.REVERSE         ( workspace -- address ) _ATOCW-REVERSE + ;

: _ATOC-WIPE-WORKSPACE  ( workspace -- )
    AT-OAUTH-CLIENT-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Caller-memory admission
\ =====================================================================

: _ATOC-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP AT-OAUTH-CLIENT-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP AT-OAUTH-CLIENT-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-OAUTH-CLIENT-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-OAUTH-CLIENT-S-PLATFORM EXIT
    THEN
    DROP AT-OAUTH-CLIENT-S-PLATFORM ;

: _ATOC-FIXED-STATUS  ( address length -- status )
    OVER 0= IF 2DROP AT-OAUTH-CLIENT-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP AT-OAUTH-CLIENT-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATOC-CALLER>STATUS ;

: AT-OAUTH-CLIENT-WORKSPACE-CLEAR  ( workspace -- status )
    DUP AT-OAUTH-CLIENT-WORKSPACE-SIZE _ATOC-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _ATOC-WIPE-WORKSPACE
    AT-OAUTH-CLIENT-S-OK ;

: _ATOC-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;

: _ATOC-RETURN3  ( x1 x2 x3 status -- status )
    >R _ATOC-DROP3 R> ;

: _ATOC-GEOMETRY  ( config profile workspace -- status )
    DUP AT-OAUTH-CLIENT-WORKSPACE-SIZE _ATOC-FIXED-STATUS
    ?DUP IF _ATOC-RETURN3 EXIT THEN
    1 PICK AT-OAUTH-PROFILE-SIZE _ATOC-FIXED-STATUS
    ?DUP IF _ATOC-RETURN3 EXIT THEN
    2 PICK OAUTH2-CLIENT-CONFIG-SIZE _ATOC-FIXED-STATUS
    ?DUP IF _ATOC-RETURN3 EXIT THEN

    2 PICK OAUTH2-CLIENT-CONFIG-SIZE
    2 PICK AT-OAUTH-CLIENT-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        AT-OAUTH-CLIENT-S-ALIAS _ATOC-RETURN3 EXIT
    THEN
    1 PICK AT-OAUTH-PROFILE-SIZE
    2 PICK AT-OAUTH-CLIENT-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        AT-OAUTH-CLIENT-S-ALIAS _ATOC-RETURN3 EXIT
    THEN

    AT-OAUTH-CLIENT-S-OK _ATOC-RETURN3 ;

\ =====================================================================
\  ASCII, URI, DNS, and path helpers
\ =====================================================================

: _ATOC-LC  ( character -- lowercase-character )
    DUP [CHAR] A >= OVER [CHAR] Z <= AND IF 32 + THEN ;

: _ATOC-ALPHA?  ( character -- flag )
    DUP [CHAR] A >= OVER [CHAR] Z <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] a >= SWAP [CHAR] z <= AND ;

: _ATOC-DIGIT?  ( character -- flag )
    DUP [CHAR] 0 >= SWAP [CHAR] 9 <= AND ;

: _ATOC-ALNUM?  ( character -- flag )
    DUP _ATOC-ALPHA? IF DROP -1 EXIT THEN
    _ATOC-DIGIT? ;

: _ATOC-HEX?  ( character -- flag )
    DUP _ATOC-DIGIT? IF DROP -1 EXIT THEN
    DUP [CHAR] A >= OVER [CHAR] F <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] a >= SWAP [CHAR] f <= AND ;

: _ATOC-URI-BYTE?  ( character -- flag )
    DUP _ATOC-ALNUM? IF DROP -1 EXIT THEN
    DUP [CHAR] - = IF DROP -1 EXIT THEN
    DUP [CHAR] . = IF DROP -1 EXIT THEN
    DUP [CHAR] _ = IF DROP -1 EXIT THEN
    DUP [CHAR] ~ = IF DROP -1 EXIT THEN
    DUP [CHAR] ! = IF DROP -1 EXIT THEN
    DUP [CHAR] $ = IF DROP -1 EXIT THEN
    DUP [CHAR] & = IF DROP -1 EXIT THEN
    DUP 39 = IF DROP -1 EXIT THEN
    DUP [CHAR] ( = IF DROP -1 EXIT THEN
    DUP [CHAR] ) = IF DROP -1 EXIT THEN
    DUP [CHAR] * = IF DROP -1 EXIT THEN
    DUP [CHAR] + = IF DROP -1 EXIT THEN
    DUP [CHAR] , = IF DROP -1 EXIT THEN
    DUP [CHAR] ; = IF DROP -1 EXIT THEN
    DUP [CHAR] = = IF DROP -1 EXIT THEN
    DUP [CHAR] : = IF DROP -1 EXIT THEN
    DUP [CHAR] / = IF DROP -1 EXIT THEN
    DUP [CHAR] ? = IF DROP -1 EXIT THEN
    DUP [CHAR] @ = IF DROP -1 EXIT THEN
    DUP [CHAR] [ = IF DROP -1 EXIT THEN
    DUP [CHAR] ] = IF DROP -1 EXIT THEN
    [CHAR] % = ;

: _ATOC-URI-BYTES?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP 0 ?DO
        OVER I + C@ DUP [CHAR] # = IF
            DROP 2DROP 0 UNLOOP EXIT
        THEN
        _ATOC-URI-BYTE? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-PERCENT-VALID?  ( address length -- flag )
    DUP 0 ?DO
        OVER I + C@ [CHAR] % = IF
            I 2 + 1 PICK >= IF
                2DROP 0 UNLOOP EXIT
            THEN
            OVER I 1+ + C@ _ATOC-HEX? 0= IF
                2DROP 0 UNLOOP EXIT
            THEN
            OVER I 2 + + C@ _ATOC-HEX? 0= IF
                2DROP 0 UNLOOP EXIT
            THEN
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-SEGMENT-START?  ( address length index -- flag )
    DUP 0= IF 2DROP DROP -1 EXIT THEN
    >R DROP R> 1- + C@ [CHAR] / = ;

: _ATOC-SEGMENT-END?  ( address length index -- flag )
    DUP 2 PICK >= IF 2DROP DROP -1 EXIT THEN
    >R DROP R> + C@ [CHAR] / = ;

: _ATOC-DOT-UNIT-U  ( address length index -- unit-length )
    DUP 2 PICK >= IF 2DROP DROP 0 EXIT THEN
    2 PICK OVER + C@ [CHAR] . = IF
        2DROP DROP 1 EXIT
    THEN
    DUP 2 + 2 PICK >= IF 2DROP DROP 0 EXIT THEN
    2 PICK OVER + C@ [CHAR] % <> IF
        2DROP DROP 0 EXIT
    THEN
    2 PICK OVER 1+ + C@ [CHAR] 2 <> IF
        2DROP DROP 0 EXIT
    THEN
    2 PICK SWAP 2 + + C@ _ATOC-LC [CHAR] e = IF
        2DROP 3
    ELSE
        2DROP 0
    THEN ;

: _ATOC-DOT-SEGMENT-AT?  ( address length index -- flag )
    2 PICK 2 PICK 2 PICK _ATOC-DOT-UNIT-U
    DUP 0= IF 2DROP 2DROP 0 EXIT THEN
    >R
    2 PICK 2 PICK 2 PICK R@ + _ATOC-SEGMENT-END? IF
        2DROP DROP R> DROP -1 EXIT
    THEN
    2 PICK 2 PICK 2 PICK R@ + _ATOC-DOT-UNIT-U
    DUP 0= IF
        DROP 2DROP DROP R> DROP 0 EXIT
    THEN
    R> + >R
    2 PICK 2 PICK 2 PICK R@ + _ATOC-SEGMENT-END? IF
        2DROP DROP R> DROP -1
    ELSE
        2DROP DROP R> DROP 0
    THEN ;

\ A dot component may spell each dot literally or as "%2e".  Encoded dots
\ embedded in an ordinary segment remain ordinary bytes.
: _ATOC-PATH-DOT-SEGMENT?  ( address length -- flag )
    DUP 0 ?DO
        2DUP I _ATOC-SEGMENT-START? IF
            2DUP I _ATOC-DOT-SEGMENT-AT? IF
                2DROP -1 UNLOOP EXIT
            THEN
        THEN
    LOOP
    2DROP 0 ;

: _ATOC-PATH-SAFE?  ( address length -- flag )
    _ATOC-PERCENT-VALID? ;

: _ATOC-LABEL?  ( address length -- flag )
    DUP 0= OVER 63 > OR IF 2DROP 0 EXIT THEN
    OVER C@ _ATOC-ALNUM? 0= IF 2DROP 0 EXIT THEN
    2DUP + 1- C@ _ATOC-ALNUM? 0= IF 2DROP 0 EXIT THEN
    DUP 0 ?DO
        OVER I + C@ DUP _ATOC-ALNUM? 0=
        SWAP [CHAR] - <> AND IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-ADVANCE  ( address length count -- address' length' )
    DUP >R
    ROT +
    SWAP R> - ;

: _ATOC-DOT-INDEX  ( address length -- index|-1 )
    DUP 0 ?DO
        OVER I + C@ [CHAR] . = IF
            2DROP I UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-DIGITS?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP 0 ?DO
        OVER I + C@ _ATOC-DIGIT? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-HEX-BYTES?  ( address length -- flag )
    DUP 0 ?DO
        OVER I + C@ _ATOC-HEX? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-DNS-LAST-LABEL  ( address length -- address' length' )
    BEGIN
        2DUP _ATOC-DOT-INDEX DUP 0< IF DROP EXIT THEN
        1+ _ATOC-ADVANCE
    AGAIN ;

\ Match the WHATWG "ends in a number" gate before a special HTTPS URL parser
\ can reinterpret a nominal DNS name as an IPv4 address.  A final all-decimal
\ label or "0x"/"0X" followed by zero or more hex digits triggers that gate.
: _ATOC-DNS-ENDS-NUMBER?  ( address length -- flag )
    _ATOC-DNS-LAST-LABEL
    2DUP _ATOC-DIGITS? IF 2DROP -1 EXIT THEN
    DUP 2 < IF 2DROP 0 EXIT THEN
    OVER C@ [CHAR] 0 <> IF 2DROP 0 EXIT THEN
    OVER 1+ C@ _ATOC-LC [CHAR] x <> IF 2DROP 0 EXIT THEN
    2 _ATOC-ADVANCE
    _ATOC-HEX-BYTES? ;

: _ATOC-DNS-LABELS?  ( address length -- flag )
    BEGIN
        DUP 0= IF 2DROP 0 EXIT THEN
        2DUP _ATOC-DOT-INDEX DUP 0< IF
            DROP _ATOC-LABEL? EXIT
        THEN
        DUP 0= IF 2DROP DROP 0 EXIT THEN
        >R
        OVER R@ _ATOC-LABEL? 0= IF
            R> DROP 2DROP 0 EXIT
        THEN
        R> 1+ _ATOC-ADVANCE
    AGAIN ;

: _ATOC-DNS?  ( address length -- flag )
    DUP 0= OVER 253 > OR IF 2DROP 0 EXIT THEN
    2DUP _ATOC-DNS-ENDS-NUMBER? IF 2DROP 0 EXIT THEN
    _ATOC-DNS-LABELS? ;

: _ATOC-BYTES-I=  ( first-a first-u second-a second-u -- flag )
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    DROP SWAP
    0 ?DO
        OVER I + C@ _ATOC-LC
        OVER I + C@ _ATOC-LC <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ATOC-HTTPS-PREFIX?  ( address length -- flag )
    DUP 8 < IF 2DROP 0 EXIT THEN
    DROP
    DUP      C@ _ATOC-LC [CHAR] h =
    OVER 1+ C@ _ATOC-LC [CHAR] t = AND
    OVER 2 + C@ _ATOC-LC [CHAR] t = AND
    OVER 3 + C@ _ATOC-LC [CHAR] p = AND
    OVER 4 + C@ _ATOC-LC [CHAR] s = AND
    OVER 5 + C@ [CHAR] : = AND
    OVER 6 + C@ [CHAR] / = AND
    OVER 7 + C@ [CHAR] / = AND
    SWAP DROP ;

\ =====================================================================
\  Bounded HTTPS URL parser
\ =====================================================================

: _ATOC-URL-RESET  ( address length workspace -- )
    >R
    R@ _ATOCW-URL-A + _ATOCW-CLIENT-HOST-A _ATOCW-URL-A - 0 FILL
    R@ _ATOCW-ALLOW-PORT + _ATOCW-REVERSE _ATOCW-ALLOW-PORT - 0 FILL
    R@ _ATOCW.URL-U !
    R@ _ATOCW.URL-A !
    -1 R@ _ATOCW.COLON !
    -1 R@ _ATOCW.QUERY !
    R> DROP ;

: _ATOC-AUTH-END  ( workspace -- index )
    DUP _ATOCW.URL-U @ 8 ?DO
        DUP _ATOCW.URL-A @ I + C@
        DUP [CHAR] / = SWAP [CHAR] ? = OR IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    _ATOCW.URL-U @ ;

: _ATOC-AUTHORITY-SCAN  ( workspace -- flag )
    DUP _ATOCW.AUTH-END @ 8 ?DO
        DUP _ATOCW.URL-A @ I + C@
        DUP [CHAR] @ = OVER [CHAR] % = OR
        OVER [CHAR] [ = OR OVER [CHAR] ] = OR IF
            DROP DROP 0 UNLOOP EXIT
        THEN
        [CHAR] : = IF
            DUP _ATOCW.COLON @ 0>= IF
                DROP 0 UNLOOP EXIT
            THEN
            I OVER _ATOCW.COLON !
        THEN
    LOOP
    DROP -1 ;

: _ATOC-PORT-PARSE  ( workspace -- flag )
    DUP _ATOCW.AUTH-END @ OVER _ATOCW.COLON @ - 1-
    DUP 0= IF 2DROP 0 EXIT THEN
    DROP
    0 OVER _ATOCW.PORT !
    DUP _ATOCW.AUTH-END @ OVER _ATOCW.COLON @ 1+ ?DO
        DUP _ATOCW.URL-A @ I + C@ DUP _ATOC-DIGIT? 0= IF
            DROP DROP 0 UNLOOP EXIT
        THEN
        [CHAR] 0 -
        OVER _ATOCW.PORT @ 10 * +
        DUP 65535 > IF 2DROP 0 UNLOOP EXIT THEN
        OVER _ATOCW.PORT !
    LOOP
    DUP _ATOCW.PORT @ 0>
    SWAP DROP ;

: _ATOC-AUTHORITY?  ( allow-port workspace -- flag )
    DUP _ATOC-AUTHORITY-SCAN 0= IF 2DROP 0 EXIT THEN

    DUP _ATOCW.COLON @ DUP 0< IF
        DROP DUP _ATOCW.AUTH-END @
    THEN
    8 -
    DUP 0= IF 2DROP DROP 0 EXIT THEN
    OVER _ATOCW.HOST-U !
    DUP _ATOCW.URL-A @ 8 + OVER _ATOCW.HOST-A !

    DUP _ATOCW.HOST-A @ OVER _ATOCW.HOST-U @
        _ATOC-DNS? 0= IF 2DROP 0 EXIT THEN

    DUP _ATOCW.COLON @ 0>= IF
        OVER 0= IF 2DROP 0 EXIT THEN
        -1 OVER _ATOCW.PORT-EXPLICIT !
        DUP _ATOC-PORT-PARSE 0= IF 2DROP 0 EXIT THEN
    ELSE
        443 OVER _ATOCW.PORT !
        0 OVER _ATOCW.PORT-EXPLICIT !
    THEN
    2DROP -1 ;

: _ATOC-QUERY-INDEX  ( workspace -- index )
    -1 OVER _ATOCW.QUERY !
    DUP _ATOCW.URL-U @ OVER _ATOCW.AUTH-END @ ?DO
        DUP _ATOCW.URL-A @ I + C@ [CHAR] ? = IF
            I OVER _ATOCW.QUERY ! LEAVE
        THEN
    LOOP
    _ATOCW.QUERY @ ;

: _ATOC-TAIL?  ( workspace -- flag )
    0 OVER _ATOCW.PATH-A !
    0 OVER _ATOCW.PATH-U !
    DUP _ATOC-QUERY-INDEX DROP

    DUP _ATOCW.AUTH-END @ OVER _ATOCW.URL-U @ < IF
        DUP _ATOCW.URL-A @ OVER _ATOCW.AUTH-END @ + C@
        [CHAR] / = IF
            DUP _ATOCW.URL-A @ OVER _ATOCW.AUTH-END @ +
            OVER _ATOCW.PATH-A !
            DUP _ATOCW.QUERY @ DUP 0< IF
                DROP DUP _ATOCW.URL-U @
            THEN
            OVER _ATOCW.AUTH-END @ -
            OVER _ATOCW.PATH-U !
        ELSE
            DUP _ATOCW.URL-A @ OVER _ATOCW.AUTH-END @ + C@
            [CHAR] ? <> IF DROP 0 EXIT THEN
        THEN
    THEN

    DUP _ATOCW.REQUIRE-PATH @ IF
        DUP _ATOCW.PATH-U @ 0= IF DROP 0 EXIT THEN
    THEN
    DUP _ATOCW.QUERY @ 0>=
    OVER _ATOCW.ALLOW-QUERY @ 0= AND IF DROP 0 EXIT THEN
    DUP _ATOCW.PATH-A @ OVER _ATOCW.PATH-U @
        _ATOC-PATH-SAFE? 0= IF DROP 0 EXIT THEN
    DROP -1 ;

: _ATOC-URL-PARSE
  ( allow-port require-path allow-query workspace -- flag )
    >R
    R@ _ATOCW.ALLOW-QUERY !
    R@ _ATOCW.REQUIRE-PATH !
    R@ _ATOCW.ALLOW-PORT !

    R@ _ATOCW.URL-A @ R@ _ATOCW.URL-U @
        _ATOC-URI-BYTES? 0= IF R> DROP 0 EXIT THEN
    R@ _ATOCW.URL-A @ R@ _ATOCW.URL-U @
        _ATOC-PERCENT-VALID? 0= IF R> DROP 0 EXIT THEN
    R@ _ATOCW.URL-A @ R@ _ATOCW.URL-U @
        _ATOC-HTTPS-PREFIX? 0= IF R> DROP 0 EXIT THEN

    R@ _ATOC-AUTH-END DUP 8 <= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ _ATOCW.AUTH-END !
    R@ _ATOCW.ALLOW-PORT @ R@ _ATOC-AUTHORITY? 0= IF
        R> DROP 0 EXIT
    THEN
    R@ _ATOC-TAIL? 0= IF R> DROP 0 EXIT THEN
    R> DROP -1 ;

\ =====================================================================
\  AT client identifier and redirect policy
\ =====================================================================

: _ATOC-CLIENT-ID?  ( workspace -- flag )
    DUP _ATOCW.CLIENT-ID-A @
    OVER _ATOCW.CLIENT-ID-U @
    2 PICK _ATOC-URL-RESET
    0 -1 -1 3 PICK _ATOC-URL-PARSE 0= IF
        DROP 0 EXIT
    THEN
    DUP _ATOCW.PATH-A @ OVER _ATOCW.PATH-U @
        _ATOC-PATH-DOT-SEGMENT? IF
        DROP 0 EXIT
    THEN
    DUP _ATOCW.HOST-A @ OVER _ATOCW.CLIENT-HOST-A !
    DUP _ATOCW.HOST-U @ OVER _ATOCW.CLIENT-HOST-U !
    DROP -1 ;

: _ATOC-REVERSE-RANGE  ( left right workspace -- )
    >R
    BEGIN 2DUP <
    WHILE
        OVER R@ _ATOCW.REVERSE + C@
        R@ _ATOCW.QUERY !
        DUP R@ _ATOCW.REVERSE + C@
        2 PICK R@ _ATOCW.REVERSE + C!
        R@ _ATOCW.QUERY @
        1 PICK R@ _ATOCW.REVERSE + C!
        SWAP 1+ SWAP 1-
    REPEAT
    2DROP R> DROP ;

: _ATOC-REVERSED-HOST  ( workspace -- )
    DUP _ATOCW.CLIENT-HOST-U @ 0 ?DO
        DUP _ATOCW.CLIENT-HOST-U @ 1- I -
        OVER _ATOCW.CLIENT-HOST-A @ + C@ _ATOC-LC
        OVER _ATOCW.REVERSE I + C!
    LOOP
    0 OVER _ATOCW.AUTH-END !
    DUP _ATOCW.CLIENT-HOST-U @ 1+ 0 ?DO
        I OVER _ATOCW.CLIENT-HOST-U @ =
        OVER _ATOCW.REVERSE I + C@ [CHAR] . = OR IF
            DUP _ATOCW.AUTH-END @ I 1- 2 PICK
                _ATOC-REVERSE-RANGE
            I 1+ OVER _ATOCW.AUTH-END !
        THEN
    LOOP
    DROP ;

: _ATOC-CUSTOM-REDIRECT?  ( workspace -- flag )
    DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.REDIRECT-U @
        _ATOC-URI-BYTES? 0= IF DROP 0 EXIT THEN
    DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.REDIRECT-U @
        _ATOC-PERCENT-VALID? 0= IF DROP 0 EXIT THEN

    DUP _ATOCW.REDIRECT-A @ C@ _ATOC-ALPHA? 0= IF
        DROP 0 EXIT
    THEN
    -1 OVER _ATOCW.COLON !
    DUP _ATOCW.REDIRECT-U @ 0 ?DO
        DUP _ATOCW.REDIRECT-A @ I + C@ [CHAR] : = IF
            I OVER _ATOCW.COLON ! LEAVE
        THEN
    LOOP
    DUP _ATOCW.COLON @
    OVER _ATOCW.CLIENT-HOST-U @ <> IF DROP 0 EXIT THEN

    DUP _ATOC-REVERSED-HOST
    DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.CLIENT-HOST-U @
    2 PICK _ATOCW.REVERSE
    3 PICK _ATOCW.CLIENT-HOST-U @
        _ATOC-BYTES-I= 0= IF DROP 0 EXIT THEN

    DUP _ATOCW.COLON @ 1+
    OVER _ATOCW.REDIRECT-U @ >= IF DROP 0 EXIT THEN
    DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.COLON @ 1+ + C@
        [CHAR] / <> IF DROP 0 EXIT THEN
    DUP _ATOCW.COLON @ 2 +
    OVER _ATOCW.REDIRECT-U @ < IF
        DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.COLON @ 2 + + C@
        [CHAR] / = IF DROP 0 EXIT THEN
    THEN

    -1 OVER _ATOCW.QUERY !
    DUP _ATOCW.REDIRECT-U @ OVER _ATOCW.COLON @ 1+ ?DO
        DUP _ATOCW.REDIRECT-A @ I + C@ [CHAR] ? = IF
            I OVER _ATOCW.QUERY ! LEAVE
        THEN
    LOOP
    DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.COLON @ 1+ +
    1 PICK _ATOCW.QUERY @ DUP 0< IF
        DROP 1 PICK _ATOCW.REDIRECT-U @
    THEN
    2 PICK _ATOCW.COLON @ 1+ -
        _ATOC-PATH-SAFE?
    SWAP DROP ;

: _ATOC-WEB-REDIRECT?  ( workspace -- flag )
    DUP _ATOCW.REDIRECT-A @
    OVER _ATOCW.REDIRECT-U @
    2 PICK _ATOC-URL-RESET
    -1 0 -1 3 PICK _ATOC-URL-PARSE 0= IF
        DROP 0 EXIT
    THEN
    DUP _ATOCW.PORT-EXPLICIT @
    OVER _ATOCW.PORT @ 443 = AND IF DROP 0 EXIT THEN
    DROP -1 ;

: _ATOC-NATIVE-HTTPS-REDIRECT?  ( workspace -- flag )
    DUP _ATOCW.REDIRECT-A @
    OVER _ATOCW.REDIRECT-U @
    2 PICK _ATOC-URL-RESET
    -1 0 -1 3 PICK _ATOC-URL-PARSE 0= IF
        DROP 0 EXIT
    THEN
    DUP _ATOCW.PORT @ 443 <> IF DROP 0 EXIT THEN
    DUP _ATOCW.HOST-A @ OVER _ATOCW.HOST-U @
    2 PICK _ATOCW.CLIENT-HOST-A @
    3 PICK _ATOCW.CLIENT-HOST-U @
        _ATOC-BYTES-I=
    SWAP DROP ;

: _ATOC-NATIVE-REDIRECT?  ( workspace -- flag )
    DUP _ATOCW.REDIRECT-A @ OVER _ATOCW.REDIRECT-U @
    _ATOC-HTTPS-PREFIX? IF
        _ATOC-NATIVE-HTTPS-REDIRECT? EXIT
    THEN
    _ATOC-CUSTOM-REDIRECT? ;

: _ATOC-REDIRECT?  ( workspace -- flag )
    DUP _ATOCW.APPLICATION @
    OAUTH2-CLIENT-CONFIG-APPLICATION-WEB = IF
        _ATOC-WEB-REDIRECT? EXIT
    THEN
    _ATOC-NATIVE-REDIRECT? ;

\ =====================================================================
\  Scope, client authentication, and DPoP policy
\ =====================================================================

: _ATOC-ATPROTO-AT?  ( address length index -- flag )
    >R
    DUP R@ 7 + < IF 2DROP R> DROP 0 EXIT THEN
    OVER R@ + 7 S" atproto" COMPARE 0= 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP R@ 7 + = IF
        2DROP R> DROP -1 EXIT
    THEN
    OVER R@ 7 + + C@ BL =
    ROT DROP SWAP DROP
    R> DROP ;

: _ATOC-ATPROTO-SCOPE?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP 0 ?DO
        I 0= IF
            -1
        ELSE
            OVER I 1- + C@ BL =
        THEN
        IF
            2DUP I _ATOC-ATPROTO-AT? IF
                2DROP -1 UNLOOP EXIT
            THEN
        THEN
    LOOP
    2DROP 0 ;

: _ATOC-SCOPE-POLICY  ( workspace -- status )
    >R
    R@ _ATOCW.ACTIVE @ OAUTH2-CLIENT-VIEW-SCOPE@
    _ATOC-ATPROTO-SCOPE? IF
        R> DROP AT-OAUTH-CLIENT-S-OK
    ELSE
        R> DROP AT-OAUTH-CLIENT-S-SCOPE
    THEN ;

: _ATOC-AUTH-POLICY  ( workspace -- status )
    >R
    R@ _ATOCW.ACTIVE @ OAUTH2-CLIENT-VIEW-AUTH-METHOD@
    R@ _ATOCW.APPLICATION @
    OAUTH2-CLIENT-CONFIG-APPLICATION-NATIVE = IF
        2DUP S" none" COMPARE 0= 0= IF
            2DROP R> DROP
            AT-OAUTH-CLIENT-S-AUTH-METHOD EXIT
        THEN
    THEN
    2DUP S" none" COMPARE 0= IF
        2DROP
        R@ _ATOCW.ACTIVE @
            OAUTH2-CLIENT-VIEW-AUTH-ALGORITHM@
        DUP 0= IF
            2DROP R> DROP AT-OAUTH-CLIENT-S-OK
        ELSE
            2DROP R> DROP AT-OAUTH-CLIENT-S-AUTH-ALGORITHM
        THEN
        EXIT
    THEN
    S" private_key_jwt" COMPARE 0= 0= IF
        R> DROP AT-OAUTH-CLIENT-S-AUTH-METHOD EXIT
    THEN

    R@ _ATOCW.ACTIVE @ OAUTH2-CLIENT-VIEW-AUTH-ALGORITHM@
    S" ES256" COMPARE 0= IF
        R> DROP AT-OAUTH-CLIENT-S-OK
    ELSE
        R> DROP AT-OAUTH-CLIENT-S-AUTH-ALGORITHM
    THEN ;

: _ATOC-DPOP-POLICY  ( workspace -- status )
    _ATOCW.ACTIVE @ OAUTH2-CLIENT-VIEW-DPOP-BOUND?
    IF AT-OAUTH-CLIENT-S-OK
    ELSE AT-OAUTH-CLIENT-S-DPOP THEN ;

\ =====================================================================
\  Binding, policy execution, and public entry point
\ =====================================================================

: _ATOC-BIND  ( view workspace -- workspace )
    >R
    DUP R@ _ATOCW.ACTIVE !

    DUP OAUTH2-CLIENT-VIEW-CLIENT-ID@
    DUP R@ _ATOCW.CLIENT-ID-U !
    OVER R@ _ATOCW.CLIENT-ID-A !
    2DROP

    DUP OAUTH2-CLIENT-VIEW-REDIRECT-URI@
    DUP R@ _ATOCW.REDIRECT-U !
    OVER R@ _ATOCW.REDIRECT-A !
    2DROP

    OAUTH2-CLIENT-VIEW-APPLICATION-TYPE@
    R@ _ATOCW.APPLICATION !
    R> ;

: _ATOC-POLICY  ( workspace -- status )
    DUP _ATOC-CLIENT-ID? 0= IF
        DROP AT-OAUTH-CLIENT-S-CLIENT-ID EXIT
    THEN
    DUP _ATOC-REDIRECT? 0= IF
        DROP AT-OAUTH-CLIENT-S-REDIRECT EXIT
    THEN
    DUP _ATOC-SCOPE-POLICY ?DUP IF NIP EXIT THEN
    DUP _ATOC-AUTH-POLICY ?DUP IF NIP EXIT THEN
    _ATOC-DPOP-POLICY ;

: _ATOC-FINISH  ( status workspace -- status )
    >R
    DUP AT-OAUTH-CLIENT-STATUS-VALID? 0= IF
        DROP AT-OAUTH-CLIENT-S-INTERNAL
    THEN
    R@ _ATOC-WIPE-WORKSPACE
    R> DROP ;

: _ATOC-WITH-CONFIG  ( view workspace -- status )
    DUP _ATOCW.ACTIVE @ AT-OAUTH-PROFILE-READY? 0= IF
        2DROP AT-OAUTH-CLIENT-S-PROFILE EXIT
    THEN
    DUP _ATOC-WIPE-WORKSPACE
    _ATOC-BIND
    DUP _ATOC-POLICY
    SWAP _ATOC-FINISH ;

: _ATOC-CONFIG>STATUS  ( config-status -- status )
    DUP OAUTH2-CLIENT-CONFIG-S-INVALID = IF
        DROP AT-OAUTH-CLIENT-S-CONFIG EXIT
    THEN
    DUP OAUTH2-CLIENT-CONFIG-S-RANGE = IF
        DROP AT-OAUTH-CLIENT-S-RANGE EXIT
    THEN
    DUP OAUTH2-CLIENT-CONFIG-S-PROTECTED = IF
        DROP AT-OAUTH-CLIENT-S-PROTECTED EXIT
    THEN
    DUP OAUTH2-CLIENT-CONFIG-S-PLATFORM = IF
        DROP AT-OAUTH-CLIENT-S-PLATFORM EXIT
    THEN
    DROP AT-OAUTH-CLIENT-S-INTERNAL ;

: _ATOC-ADMIT-OP  ( config profile workspace -- status )
    \ Preserve the caller's active cell while it carries profile context.
    DUP >R
    DUP _ATOCW.ACTIVE @ >R
    1 PICK OVER _ATOCW.ACTIVE !
    NIP
    ['] _ATOC-WITH-CONFIG SWAP
    OAUTH2-CLIENT-CONFIG-WITH
    DUP OAUTH2-CLIENT-CONFIG-S-OK = IF
        DROP
        DUP AT-OAUTH-CLIENT-S-PROFILE = IF
            R> R@ _ATOCW.ACTIVE !
        ELSE
            R> DROP
        THEN
        R> DROP EXIT
    THEN
    DUP OAUTH2-CLIENT-CONFIG-S-CALLBACK = IF
        2DROP
        R> DROP
        R@ _ATOC-WIPE-WORKSPACE
        R> DROP
        AT-OAUTH-CLIENT-S-INTERNAL EXIT
    THEN
    NIP _ATOC-CONFIG>STATUS
    R> R@ _ATOCW.ACTIVE !
    R> DROP ;

: _ATOC-ADMIT-CALL  ( config profile workspace operation-xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _ATOC-WIPE-WORKSPACE
        _ATOC-DROP3
        R> DROP
        AT-OAUTH-CLIENT-S-INTERNAL EXIT
    THEN
    DROP
    R> DROP ;

: AT-OAUTH-CLIENT-ADMIT  ( config profile workspace -- status )
    2 PICK 2 PICK 2 PICK _ATOC-GEOMETRY
    ?DUP IF _ATOC-RETURN3 EXIT THEN
    ['] _ATOC-ADMIT-OP _ATOC-ADMIT-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

AT-OAUTH-CLIENT-WORKSPACE-SIZE 432 <> [IF]
    ." AT OAuth client workspace geometry mismatch" CR ABORT
[THEN]

_ATOCW-REVERSE 256 + AT-OAUTH-CLIENT-WORKSPACE-SIZE <> [IF]
    ." AT OAuth client reverse workspace mismatch" CR ABORT
[THEN]
