\ json.f — JSON vocabulary for KDOS / Megapad-64
\
\ A complete JSON reader and builder library.
\ Operates on (addr len) cursor pairs pointing into JSON text.
\
\ Prefix: JSON-   (public API)
\         _JSON-  (internal helpers)
\
\ Load with:   REQUIRE json.f

PROVIDED akashic-json

\ =====================================================================
\  Error Handling
\ =====================================================================
\
\  Configurable: abort on error or set a flag and continue.
\  Application picks its mode at startup.

VARIABLE JSON-ERR                    \ 0 = ok, non-zero = error code
VARIABLE JSON-ABORT-ON-ERROR         \ -1 = abort, 0 = flag-only
0 JSON-ERR !
0 JSON-ABORT-ON-ERROR !              \ default: soft-fail

\ Error codes
1 CONSTANT JSON-E-NOT-FOUND         \ key not found
2 CONSTANT JSON-E-WRONG-TYPE        \ unexpected value type
3 CONSTANT JSON-E-UNTERMINATED      \ unterminated string
4 CONSTANT JSON-E-UNEXPECTED        \ unexpected character
5 CONSTANT JSON-E-OVERFLOW          \ buffer overflow

: JSON-FAIL  ( err-code -- )
    JSON-ERR !
    JSON-ABORT-ON-ERROR @ IF ABORT" JSON error" THEN ;

: JSON-OK?  ( -- flag )
    JSON-ERR @ 0= ;

: JSON-CLEAR-ERR  ( -- )
    0 JSON-ERR ! ;

\ =====================================================================
\  Layer 0 — Primitives
\ =====================================================================
\
\  Character-level scanning.  Every word takes an (addr len) cursor
\  and returns a new cursor advanced past the scanned element.

\ /STRING ( addr len n -- addr+n len-n )
\   Standard Forth word; defined here in case BIOS lacks it.
: /STRING  ( addr len n -- addr+n len-n )
    ROT OVER + -ROT - ;

\ JSON-SKIP-WS ( addr len -- addr' len' )
\   Skip JSON whitespace: space, tab, LF, CR.
: JSON-SKIP-WS  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 32 =            \ space
        OVER  9 = OR                 \ tab
        OVER 10 = OR                 \ LF
        SWAP 13 = OR                 \ CR
        0= IF EXIT THEN
        1 /STRING
    REPEAT ;

\ JSON-SKIP-STRING ( addr len -- addr' len' )
\   Skip past a JSON string value.  addr must point at opening ".
\   Cursor ends up just past the closing ".
: JSON-SKIP-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 34 <> IF EXIT THEN      \ not a " — bail
    1 /STRING                        \ skip opening "
    BEGIN
        DUP 0>
    WHILE
        OVER C@ 92 = IF             \ backslash — skip escape pair
            DUP 2 >= IF
                2 /STRING
            ELSE
                1 /STRING
            THEN
        ELSE
            OVER C@ 34 = IF         \ closing "
                1 /STRING EXIT
            THEN
            1 /STRING
        THEN
    REPEAT
    JSON-E-UNTERMINATED JSON-FAIL ;

\ JSON-SKIP-VALUE ( addr len -- addr' len' )
\   Skip one complete JSON value: string, number, object, array,
\   boolean, or null.  Depth-aware for nested structures.
VARIABLE _JSON-DEPTH
: JSON-SKIP-VALUE  ( addr len -- addr' len' )
    JSON-SKIP-WS
    DUP 0> 0= IF EXIT THEN
    OVER C@
    DUP 34 = IF                      \ " — string
        DROP JSON-SKIP-STRING EXIT
    THEN
    DUP 123 = OVER 91 = OR IF       \ { or [ — nested structure
        DROP
        1 _JSON-DEPTH !
        1 /STRING
        BEGIN
            DUP 0> _JSON-DEPTH @ 0> AND
        WHILE
            OVER C@
            DUP 34 = IF              \ " inside — skip string
                DROP JSON-SKIP-STRING
            ELSE DUP 123 = OVER 91 = OR IF   \ { or [
                DROP 1 _JSON-DEPTH +!
                1 /STRING
            ELSE DUP 125 = OVER 93 = OR IF   \ } or ]
                DROP -1 _JSON-DEPTH +!
                1 /STRING
            ELSE
                DROP 1 /STRING
            THEN THEN THEN
        REPEAT
        EXIT
    THEN
    \ number, true, false, null — scan until delimiter
    DROP
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 44 =            \ ,
        OVER 125 = OR               \ }
        OVER  93 = OR               \ ]
        OVER  32 = OR               \ space
        OVER   9 = OR               \ tab
        OVER  10 = OR               \ LF
        SWAP  13 = OR               \ CR
        IF EXIT THEN
        1 /STRING
    REPEAT ;

\ JSON-SKIP-KV ( addr len -- addr' len' )
\   Skip one "key":value pair in an object.
: JSON-SKIP-KV  ( addr len -- addr' len' )
    JSON-SKIP-WS
    JSON-SKIP-STRING                 \ skip key string
    JSON-SKIP-WS
    DUP 0> IF
        OVER C@ 58 = IF             \ : colon
            1 /STRING
        THEN
    THEN
    JSON-SKIP-VALUE ;               \ skip value
