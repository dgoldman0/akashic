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

\ =====================================================================
\  Layer 1 — Type Introspection
\ =====================================================================
\
\  Examine the current value without consuming it.

\ Type tag constants
0 CONSTANT JSON-T-ERROR
1 CONSTANT JSON-T-STRING
2 CONSTANT JSON-T-NUMBER
3 CONSTANT JSON-T-OBJECT
4 CONSTANT JSON-T-ARRAY
5 CONSTANT JSON-T-BOOL
6 CONSTANT JSON-T-NULL

\ JSON-TYPE? ( addr len -- type )
\   Return the type tag for the value at the current cursor position.
: JSON-TYPE?  ( addr len -- type )
    JSON-SKIP-WS
    DUP 0> 0= IF 2DROP JSON-T-ERROR EXIT THEN
    OVER C@
    DUP 34 = IF DROP 2DROP JSON-T-STRING EXIT THEN       \ "
    DUP 123 = IF DROP 2DROP JSON-T-OBJECT EXIT THEN      \ {
    DUP 91 = IF DROP 2DROP JSON-T-ARRAY EXIT THEN        \ [
    DUP 116 = IF DROP 2DROP JSON-T-BOOL EXIT THEN        \ t (true)
    DUP 102 = IF DROP 2DROP JSON-T-BOOL EXIT THEN        \ f (false)
    DUP 110 = IF DROP 2DROP JSON-T-NULL EXIT THEN        \ n (null)
    DUP 45 = IF DROP 2DROP JSON-T-NUMBER EXIT THEN       \ - (negative)
    DUP 48 >= OVER 57 <= AND IF DROP 2DROP JSON-T-NUMBER EXIT THEN  \ 0-9
    DROP 2DROP JSON-T-ERROR ;

\ Convenience type-checking words
: JSON-STRING?  ( addr len -- flag )  JSON-TYPE? JSON-T-STRING = ;
: JSON-NUMBER?  ( addr len -- flag )  JSON-TYPE? JSON-T-NUMBER = ;
: JSON-OBJECT?  ( addr len -- flag )  JSON-TYPE? JSON-T-OBJECT = ;
: JSON-ARRAY?   ( addr len -- flag )  JSON-TYPE? JSON-T-ARRAY  = ;
: JSON-BOOL?    ( addr len -- flag )  JSON-TYPE? JSON-T-BOOL   = ;
: JSON-NULL?    ( addr len -- flag )  JSON-TYPE? JSON-T-NULL   = ;

\ =====================================================================
\  Layer 2 — Value Extraction
\ =====================================================================
\
\  Pull Forth-native values out of JSON text.

\ JSON-GET-STRING ( addr len -- str-addr str-len )
\   Extract the inner bytes of a JSON string (without quotes).
\   Does NOT unescape — returns raw bytes.  Zero-copy.
\   addr must point at the opening " quote.
: JSON-GET-STRING  ( addr len -- str-addr str-len )
    JSON-SKIP-WS
    DUP 0> 0= IF JSON-E-WRONG-TYPE JSON-FAIL 0 0 EXIT THEN
    OVER C@ 34 <> IF JSON-E-WRONG-TYPE JSON-FAIL 0 0 EXIT THEN
    1 /STRING                        \ skip opening "
    OVER                             \ save start address
    >R 0                             \ ( addr' len' 0=count  R: start )
    BEGIN
        OVER 0>
    WHILE
        2 PICK C@ 92 = IF           \ backslash escape
            OVER 2 < IF             \ malformed
                2DROP DROP R> DROP
                JSON-E-UNTERMINATED JSON-FAIL
                0 0 EXIT
            THEN
            >R 2 /STRING R>
            2 +                      \ count += 2
        ELSE
            2 PICK C@ 34 = IF       \ closing "
                NIP NIP R> SWAP EXIT
            THEN
            >R 1 /STRING R>
            1+
        THEN
    REPEAT
    2DROP DROP R> DROP
    JSON-E-UNTERMINATED JSON-FAIL
    0 0 ;

\ JSON-UNESCAPE ( src slen dest dmax -- len )
\   Decode JSON escape sequences into a user-provided buffer.
\   Handles: \" \\ \/ \n \r \t \b \f
\   Returns actual length written.  0 on error/overflow.
VARIABLE _JU-DST
VARIABLE _JU-MAX
VARIABLE _JU-POS

: JSON-UNESCAPE  ( src slen dest dmax -- len )
    _JU-MAX !  _JU-DST !  0 _JU-POS !
    BEGIN
        DUP 0>
    WHILE
        OVER C@ 92 = IF             \ backslash
            1 /STRING
            DUP 0> 0= IF 2DROP _JU-POS @ EXIT THEN
            OVER C@
            DUP 110 = IF DROP 10 ELSE        \ \n -> LF
            DUP 114 = IF DROP 13 ELSE        \ \r -> CR
            DUP 116 = IF DROP  9 ELSE        \ \t -> TAB
            DUP  98 = IF DROP  8 ELSE        \ \b -> BS
            DUP 102 = IF DROP 12 ELSE        \ \f -> FF
            DUP  34 = IF DROP 34 ELSE        \ \" -> "
            DUP  92 = IF DROP 92 ELSE        \ \\ -> backslash
            DUP  47 = IF DROP 47 ELSE        \ \/ -> /
                                              \ unknown: pass through
            THEN THEN THEN THEN THEN THEN THEN THEN
            \ store character
            _JU-POS @ _JU-MAX @ >= IF
                2DROP JSON-E-OVERFLOW JSON-FAIL 0 EXIT
            THEN
            _JU-DST @ _JU-POS @ + C!
            1 _JU-POS +!
            1 /STRING
        ELSE
            \ plain character
            _JU-POS @ _JU-MAX @ >= IF
                2DROP JSON-E-OVERFLOW JSON-FAIL 0 EXIT
            THEN
            OVER C@ _JU-DST @ _JU-POS @ + C!
            1 _JU-POS +!
            1 /STRING
        THEN
    REPEAT
    2DROP _JU-POS @ ;

\ JSON-GET-NUMBER ( addr len -- n )
\   Parse a signed integer from JSON.  Stops at first non-digit.
VARIABLE _JSON-NUM-NEG
: JSON-GET-NUMBER  ( addr len -- n )
    JSON-SKIP-WS
    0 _JSON-NUM-NEG !
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ 45 = IF                  \ minus sign
        -1 _JSON-NUM-NEG !
        1 /STRING
    THEN
    0                                \ accumulator
    BEGIN
        OVER 0> WHILE
        2 PICK C@ DUP 48 >= SWAP 57 <= AND
        0= IF NIP NIP
            _JSON-NUM-NEG @ IF NEGATE THEN
            EXIT
        THEN
        10 *
        2 PICK C@ 48 - +
        >R 1 /STRING R>
    REPEAT
    NIP NIP
    _JSON-NUM-NEG @ IF NEGATE THEN ;

\ JSON-GET-BOOL ( addr len -- flag )
\   Extract boolean: true -> -1, false -> 0.
: JSON-GET-BOOL  ( addr len -- flag )
    JSON-SKIP-WS
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ 116 = IF 2DROP -1 EXIT THEN    \ t -> true
    OVER C@ 102 = IF 2DROP  0 EXIT THEN    \ f -> false
    2DROP JSON-E-WRONG-TYPE JSON-FAIL 0 ;

\ =====================================================================
\  Layer 3 — Object Navigation (Depth-Aware)
\ =====================================================================
\
\  Scoped key lookup: searches only at the current nesting level.

\ JSON-ENTER ( addr len -- addr' len' )
\   Enter a { or [.  Returns cursor positioned at first element
\   (after the opening brace/bracket + whitespace).
: JSON-ENTER  ( addr len -- addr' len' )
    JSON-SKIP-WS
    DUP 0> 0= IF JSON-E-UNEXPECTED JSON-FAIL EXIT THEN
    OVER C@ DUP 123 = SWAP 91 = OR 0= IF
        JSON-E-WRONG-TYPE JSON-FAIL EXIT
    THEN
    1 /STRING JSON-SKIP-WS ;

\ _JSON-STR=  ( s1 l1 s2 l2 -- flag )
\   Compare two strings for equality.
: _JSON-STR=  ( s1 l1 s2 l2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN     \ lengths differ
    0 DO
        OVER I + C@  OVER I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ JSON-KEY ( addr len key-addr key-len -- val-addr val-len )
\   Depth-aware key lookup within the current object.
\   Searches only top-level keys of the object (does not descend
\   into nested structures).  Cursor must be inside an object
\   (past the opening {).  Returns cursor at the value for the key.
\   Calls JSON-FAIL if key not found.
VARIABLE _JK-KA
VARIABLE _JK-KL

: JSON-KEY  ( addr len kaddr klen -- vaddr vlen )
    _JK-KL ! _JK-KA !
    JSON-SKIP-WS
    BEGIN
        DUP 0> IF OVER C@ 125 <> ELSE 0 THEN   \ not } and len > 0
    WHILE
        \ skip comma if present
        OVER C@ 44 = IF 1 /STRING JSON-SKIP-WS THEN
        \ current position should be at a key string "..."
        OVER C@ 34 <> IF
            JSON-E-UNEXPECTED JSON-FAIL
            0 0 EXIT
        THEN
        \ extract key name and compare
        2DUP JSON-GET-STRING         ( oaddr olen kstr klen )
        _JK-KA @ _JK-KL @ _JSON-STR=
        IF
            \ found it — skip past the key string and colon
            JSON-SKIP-STRING         \ skip "key"
            JSON-SKIP-WS
            OVER C@ 58 = IF 1 /STRING THEN   \ skip :
            JSON-SKIP-WS
            EXIT
        THEN
        \ not this key — skip the whole key:value pair
        JSON-SKIP-KV
        JSON-SKIP-WS
    REPEAT
    2DROP
    JSON-E-NOT-FOUND JSON-FAIL
    0 0 ;

\ JSON-KEY? ( addr len key-addr key-len -- val-addr val-len flag )
\   Like JSON-KEY but returns a flag instead of failing.
\   flag = -1 on success, 0 on not-found.
VARIABLE _JK-SAVE-ABORT
: JSON-KEY?  ( addr len kaddr klen -- vaddr vlen flag )
    JSON-ABORT-ON-ERROR @ _JK-SAVE-ABORT !
    JSON-CLEAR-ERR
    0 JSON-ABORT-ON-ERROR !
    JSON-KEY
    _JK-SAVE-ABORT @ JSON-ABORT-ON-ERROR !
    JSON-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

\ JSON-HAS? ( addr len key-addr key-len -- flag )
\   Does this object contain the key?  Does not move cursor.
VARIABLE _JH-SAVE-ABORT
: JSON-HAS?  ( addr len kaddr klen -- flag )
    JSON-ABORT-ON-ERROR @ _JH-SAVE-ABORT !
    2>R 2DUP 2R>
    JSON-CLEAR-ERR
    0 JSON-ABORT-ON-ERROR !
    JSON-KEY
    _JH-SAVE-ABORT @ JSON-ABORT-ON-ERROR !
    JSON-OK?
    >R 2DROP 2DROP R> ;

\ =====================================================================
\  Layer 4 — Array Navigation
\ =====================================================================
\
\  Uses JSON-ENTER from Layer 3 to enter arrays.

\ JSON-NEXT ( addr len -- addr' len' flag )
\   Advance to the next element in an array or object.
\   Skips the current value, then skips comma + whitespace.
\   Returns flag = -1 if another element exists, 0 at end (] or }).
: JSON-NEXT  ( addr len -- addr' len' flag )
    JSON-SKIP-VALUE
    JSON-SKIP-WS
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 93 = IF 0 EXIT THEN          \ ]
    OVER C@ 125 = IF 0 EXIT THEN         \ }
    OVER C@ 44 = IF 1 /STRING THEN       \ skip ,
    JSON-SKIP-WS
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 93 = IF 0 EXIT THEN          \ ] after comma
    OVER C@ 125 = IF 0 EXIT THEN         \ } after comma
    -1 ;

\ JSON-NTH ( addr len n -- addr' len' )
\   Jump to the nth element (0-based) in an array.
\   Cursor must be inside the array (past [).
: JSON-NTH  ( addr len n -- addr' len' )
    DUP 0= IF DROP EXIT THEN        \ 0th element: already there
    0 DO
        JSON-SKIP-VALUE
        JSON-SKIP-WS
        DUP 0> 0= IF
            JSON-E-NOT-FOUND JSON-FAIL UNLOOP EXIT
        THEN
        OVER C@ 93 = IF
            JSON-E-NOT-FOUND JSON-FAIL UNLOOP EXIT
        THEN
        OVER C@ 44 = IF 1 /STRING THEN
        JSON-SKIP-WS
    LOOP ;

\ JSON-COUNT ( addr len -- n )
\   Count elements in an array or object.
\   Cursor must be inside (past [ or {).  Scans without consuming.
: JSON-COUNT  ( addr len -- n )
    0 >R
    JSON-SKIP-WS
    DUP 0> 0= IF 2DROP R> EXIT THEN
    OVER C@ 93 = IF 2DROP R> EXIT THEN    \ empty array
    OVER C@ 125 = IF 2DROP R> EXIT THEN   \ empty object
    R> 1+ >R                              \ count first element
    BEGIN
        JSON-SKIP-VALUE
        JSON-SKIP-WS
        DUP 0> IF
            OVER C@ 44 = IF
                1 /STRING JSON-SKIP-WS
                R> 1+ >R
                -1
            ELSE 0 THEN
        ELSE 0 THEN
    0= UNTIL
    2DROP R> ;

\ =====================================================================
\  Layer 5 — Path Access
\ =====================================================================
\
\  Navigate deep structures with dot-separated key paths.
\  e.g. S" post.author.handle" JSON-PATH

\ _JSON-FIND-DOT ( addr len -- offset | -1 )
\   Find the first '.' (46) in a string.  Returns offset or -1.
: _JSON-FIND-DOT  ( addr len -- offset )
    0 DO
        DUP I + C@ 46 = IF DROP I UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ JSON-PATH ( addr len path-addr path-len -- addr' len' )
\   Navigate a dot-separated path.  Each segment is a key name.
\   Enters objects automatically.
\   Example: S" user.name" JSON-PATH
\   is equivalent to: JSON-ENTER S" user" JSON-KEY JSON-ENTER S" name" JSON-KEY
VARIABLE _JP-PA
VARIABLE _JP-PL

: JSON-PATH  ( addr len paddr plen -- addr' len' )
    _JP-PL ! _JP-PA !
    BEGIN
        _JP-PL @ 0>
    WHILE
        \ Enter the current object
        JSON-ENTER
        JSON-OK? 0= IF EXIT THEN
        \ Find dot in remaining path
        _JP-PA @ _JP-PL @ _JSON-FIND-DOT
        DUP -1 = IF
            \ no dot — last segment
            DROP
            _JP-PA @ _JP-PL @ JSON-KEY
            EXIT
        THEN
        \ dot found at offset — extract segment before dot
        >R
        _JP-PA @ R@ JSON-KEY         \ look up this segment
        JSON-OK? 0= IF R> DROP EXIT THEN
        \ advance path past the dot
        _JP-PA @ R@ 1+ + _JP-PA !
        _JP-PL @ R> 1+ - _JP-PL !
    REPEAT ;

\ JSON-PATH? ( addr len path-addr path-len -- addr' len' flag )
\   Like JSON-PATH but returns flag instead of failing.
VARIABLE _JPQ-SAVE-ABORT
: JSON-PATH?  ( addr len paddr plen -- addr' len' flag )
    JSON-ABORT-ON-ERROR @ _JPQ-SAVE-ABORT !
    JSON-CLEAR-ERR
    0 JSON-ABORT-ON-ERROR !
    JSON-PATH
    _JPQ-SAVE-ABORT @ JSON-ABORT-ON-ERROR !
    JSON-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;
