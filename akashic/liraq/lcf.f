\ lcf.f — LCF (LIRAQ Communication Format) reader / writer
\
\ LCF is a strict subset of TOML 1.0 (spec §2.3):
\   - All keys MUST be kebab-case
\   - DCS→Runtime messages have [action] with type key
\   - Runtime→DCS messages have [result] with status key
\   - Batch mutations use [[batch]] array-of-tables
\   - Inline tables ≤80 chars; multiline strings use """
\   - Max message size 64 KiB
\
\ The reader side is thin dispatch over toml.f primitives.
\ The writer side appends TOML text into a caller-supplied buffer.
\
\ Prefix: LCF-   (public API)
\         _LCF-  (internal helpers)

REQUIRE ../utils/string.f
REQUIRE ../text/utf8.f
REQUIRE ../utils/toml.f
REQUIRE ../utils/json.f

PROVIDED akashic-lcf

\ =====================================================================
\  Error codes (extend TOML range)
\ =====================================================================

VARIABLE LCF-ERR
0 LCF-ERR !

10 CONSTANT LCF-E-NO-ACTION
11 CONSTANT LCF-E-NO-RESULT
12 CONSTANT LCF-E-NO-TYPE
13 CONSTANT LCF-E-BAD-KEY
14 CONSTANT LCF-E-TOO-LARGE
15 CONSTANT LCF-E-OVERFLOW

: LCF-FAIL  ( code -- )  LCF-ERR ! ;
: LCF-OK?   ( -- flag )  LCF-ERR @ 0= ;
: LCF-CLEAR-ERR  ( -- )  0 LCF-ERR ! ;

\ =====================================================================
\  Format dispatch (JSON / TOML auto-detect)
\ =====================================================================

0 CONSTANT LCF-FMT-TOML
1 CONSTANT LCF-FMT-JSON

VARIABLE LCF-FORMAT   LCF-FMT-TOML LCF-FORMAT !
VARIABLE _LCF-FMT     \ per-operation detected format

\ _LCF-IS-JSON? ( doc-a doc-l -- flag )
\   TRUE if first non-whitespace character is { (JSON object).
: _LCF-IS-JSON?  ( doc-a doc-l -- flag )
    BEGIN DUP 0> WHILE
        OVER C@
        DUP 32 = OVER 10 = OR OVER 13 = OR OVER 9 = OR
        IF DROP 1 /STRING
        ELSE 123 = NIP NIP EXIT THEN
    REPEAT 2DROP 0 ;

: _LCF-DETECT  ( doc-a doc-l -- )
    _LCF-IS-JSON? IF LCF-FMT-JSON ELSE LCF-FMT-TOML THEN _LCF-FMT ! ;

: _LCF-IS-J?  ( -- flag ) _LCF-FMT @ LCF-FMT-JSON = ;

\ Dispatch: section lookup (TOML [table] <-> JSON object key)
: _LF-FIND-TABLE  ( cur-a cur-l name-a name-l -- cur-a' cur-l' )
    _LCF-IS-J? IF 2>R JSON-ENTER 2R> JSON-KEY JSON-ENTER
    ELSE TOML-FIND-TABLE THEN ;

: _LF-FIND-TABLE?  ( cur-a cur-l name-a name-l -- cur-a' cur-l' flag )
    _LCF-IS-J? IF
        2>R JSON-ENTER 2R> JSON-KEY?
        IF JSON-ENTER -1 ELSE 0 THEN
    ELSE TOML-FIND-TABLE? THEN ;

: _LF-KEY  ( cur-a cur-l key-a key-l -- val-a val-l )
    _LCF-IS-J? IF JSON-KEY ELSE TOML-KEY THEN ;

: _LF-KEY?  ( cur-a cur-l key-a key-l -- val-a val-l flag )
    _LCF-IS-J? IF JSON-KEY? ELSE TOML-KEY? THEN ;

: _LF-GET-STRING  ( val-a val-l -- str-a str-l )
    _LCF-IS-J? IF JSON-GET-STRING ELSE TOML-GET-STRING THEN ;

: _LF-GET-BOOL  ( val-a val-l -- flag )
    _LCF-IS-J? IF JSON-GET-BOOL ELSE TOML-GET-BOOL THEN ;

: _LF-GET-INT  ( val-a val-l -- n )
    _LCF-IS-J? IF JSON-GET-NUMBER ELSE TOML-GET-INT THEN ;

: _LF-FIND-ATABLE  ( doc-a doc-l name-a name-l n -- body-a body-l )
    _LCF-IS-J? IF
        >R 2>R JSON-ENTER 2R> JSON-KEY JSON-ENTER R> JSON-NTH JSON-ENTER
    ELSE TOML-FIND-ATABLE THEN ;

: _LF-CLEAR-ERR  ( -- )
    _LCF-IS-J? IF JSON-CLEAR-ERR ELSE TOML-CLEAR-ERR THEN ;

\ =====================================================================
\  Constants
\ =====================================================================

65536 CONSTANT LCF-MAX-SIZE

\ =====================================================================
\  Reader — message inspection
\ =====================================================================

\ LCF-ACTION? ( doc-a doc-l -- flag )
\   Does the message have an [action] table?
: LCF-ACTION?  ( doc-a doc-l -- flag )
    2DUP _LCF-DETECT
    S" action" _LF-FIND-TABLE? NIP NIP ;

\ LCF-RESULT? ( doc-a doc-l -- flag )
\   Does the message have a [result] table?
: LCF-RESULT?  ( doc-a doc-l -- flag )
    2DUP _LCF-DETECT
    S" result" _LF-FIND-TABLE? NIP NIP ;

\ LCF-ACTION-TYPE ( doc-a doc-l -- str-a str-l )
\   Extract the action type string.
: LCF-ACTION-TYPE  ( doc-a doc-l -- str-a str-l )
    2DUP _LCF-DETECT
    S" action" _LF-FIND-TABLE
    S" type" _LF-KEY _LF-GET-STRING ;

\ LCF-ACTION-TYPE? ( doc-a doc-l -- str-a str-l flag )
\   Like LCF-ACTION-TYPE but returns flag.
: LCF-ACTION-TYPE?  ( doc-a doc-l -- str-a str-l flag )
    2DUP _LCF-DETECT
    S" action" _LF-FIND-TABLE?
    IF
        S" type" _LF-KEY?
        IF _LF-GET-STRING -1
        ELSE 0 THEN
    ELSE 0 THEN ;

\ LCF-RESULT-STATUS ( doc-a doc-l -- str-a str-l )
\   Extract the result status string.
: LCF-RESULT-STATUS  ( doc-a doc-l -- str-a str-l )
    2DUP _LCF-DETECT
    S" result" _LF-FIND-TABLE
    S" status" _LF-KEY _LF-GET-STRING ;

\ LCF-RESULT-OK? ( doc-a doc-l -- flag )
\   Is the result status "ok"?
: LCF-RESULT-OK?  ( doc-a doc-l -- flag )
    LCF-RESULT-STATUS S" ok" STR-STR= ;

\ LCF-RESULT-ERROR ( doc-a doc-l -- err-a err-l )
\   Extract the error string from result.
: LCF-RESULT-ERROR  ( doc-a doc-l -- err-a err-l )
    2DUP _LCF-DETECT
    S" result" _LF-FIND-TABLE
    S" error" _LF-KEY _LF-GET-STRING ;

\ LCF-RESULT-DETAIL ( doc-a doc-l -- str-a str-l )
\   Extract the detail string from result.
: LCF-RESULT-DETAIL  ( doc-a doc-l -- str-a str-l )
    2DUP _LCF-DETECT
    S" result" _LF-FIND-TABLE
    S" detail" _LF-KEY _LF-GET-STRING ;

\ =====================================================================
\  Reader — batch access
\ =====================================================================

\ LCF-BATCH-NTH ( doc-a doc-l n -- body-a body-l )
\   Get the nth (0-based) [[batch]] entry.
: LCF-BATCH-NTH  ( doc-a doc-l n -- body-a body-l )
    >R 2DUP _LCF-DETECT S" batch" R> _LF-FIND-ATABLE ;

\ LCF-BATCH-OP ( body-a body-l -- str-a str-l )
\   Extract the "op" key from a batch entry body.
: LCF-BATCH-OP  ( body-a body-l -- str-a str-l )
    S" op" _LF-KEY _LF-GET-STRING ;

\ LCF-BATCH-COUNT ( doc-a doc-l -- n )
\   Count batch entries by probing index 0, 1, 2...
\   Simple but correct for typical small batches.
VARIABLE _LBC-N
: LCF-BATCH-COUNT  ( doc-a doc-l -- n )
    2DUP _LCF-DETECT
    _LCF-IS-J? IF
        JSON-ENTER S" batch" JSON-KEY?
        IF JSON-ENTER JSON-COUNT ELSE 0 THEN
    ELSE
        0 _LBC-N !
        BEGIN
            2DUP S" batch" _LBC-N @ TOML-FIND-ATABLE
            TOML-OK? 0= IF 2DROP THEN
            TOML-OK?
        WHILE
            1 _LBC-N +!
            TOML-CLEAR-ERR
        REPEAT
        2DROP TOML-CLEAR-ERR _LBC-N @
    THEN ;

\ =====================================================================
\  Reader — action field helpers
\ =====================================================================

\ LCF-ACTION-KEY ( doc-a doc-l key-a key-l -- val-a val-l )
\   Retrieve a key from the [action] table.
: LCF-ACTION-KEY  ( doc-a doc-l key-a key-l -- val-a val-l )
    2>R 2DUP _LCF-DETECT
    S" action" _LF-FIND-TABLE 2R> _LF-KEY ;

\ LCF-ACTION-STRING ( doc-a doc-l key-a key-l -- str-a str-l )
\   Retrieve a string value from [action].
: LCF-ACTION-STRING  ( doc-a doc-l key-a key-l -- str-a str-l )
    LCF-ACTION-KEY _LF-GET-STRING ;

\ LCF-QUERY-METHOD ( doc-a doc-l -- str-a str-l )
\   Shortcut for [action].method as string.
: LCF-QUERY-METHOD  ( doc-a doc-l -- str-a str-l )
    S" method" LCF-ACTION-STRING ;

\ LCF-QUERY-PATH ( doc-a doc-l -- str-a str-l )
\   Shortcut for [action].path as string.
: LCF-QUERY-PATH  ( doc-a doc-l -- str-a str-l )
    S" path" LCF-ACTION-STRING ;

\ =====================================================================
\  Reader — batch entry field helpers
\ =====================================================================

\ LCF-ENTRY-STRING ( body-a body-l key-a key-l -- str-a str-l )
\   Retrieve a string key from a batch entry body.
: LCF-ENTRY-STRING  ( body-a body-l key-a key-l -- str-a str-l )
    _LF-KEY _LF-GET-STRING ;

\ =====================================================================
\  Reader — capabilities
\ =====================================================================

\ LCF-CAP-VERSION ( doc-a doc-l -- str-a str-l )
\   Extract capabilities.version.
: LCF-CAP-VERSION  ( doc-a doc-l -- str-a str-l )
    2DUP _LCF-DETECT
    S" capabilities" _LF-FIND-TABLE
    S" version" _LF-KEY _LF-GET-STRING ;

\ LCF-CAP-BOOL ( doc-a doc-l key-a key-l -- flag )
\   Extract a boolean capability.
: LCF-CAP-BOOL  ( doc-a doc-l key-a key-l -- flag )
    2>R 2DUP _LCF-DETECT
    S" capabilities" _LF-FIND-TABLE 2R> _LF-KEY _LF-GET-BOOL ;

\ LCF-CAP-INT ( doc-a doc-l key-a key-l -- n )
\   Extract an integer capability.
: LCF-CAP-INT  ( doc-a doc-l key-a key-l -- n )
    2>R 2DUP _LCF-DETECT
    S" capabilities" _LF-FIND-TABLE 2R> _LF-KEY _LF-GET-INT ;

\ =====================================================================
\  Validation
\ =====================================================================

\ _LCF-KEBAB? ( c -- flag )
\   Is c a valid kebab-case character? [a-z0-9-]
: _LCF-KEBAB?  ( c -- flag )
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP -1 EXIT THEN
    45 = ;

\ LCF-VALID-KEY? ( addr len -- flag )
\   Check that all characters in a key are kebab-case.
: LCF-VALID-KEY?  ( addr len -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    0 DO
        DUP I + C@ _LCF-KEBAB? 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ LCF-VALIDATE ( doc-a doc-l -- flag )
\   Basic validation: size limit + has [action] or [result].
: LCF-VALIDATE  ( doc-a doc-l -- flag )
    LCF-CLEAR-ERR
    DUP LCF-MAX-SIZE > IF
        LCF-E-TOO-LARGE LCF-FAIL 2DROP 0 EXIT
    THEN
    2DUP _LCF-DETECT
    2DUP LCF-ACTION? IF 2DROP -1 EXIT THEN
    _LF-CLEAR-ERR
    2DUP LCF-RESULT? IF 2DROP -1 EXIT THEN
    2DROP LCF-E-NO-ACTION LCF-FAIL 0 ;

\ =====================================================================
\  Writer — buffer management
\ =====================================================================
\
\ The writer appends TOML text into a caller buffer.
\ Stack: ( buf-a buf-max buf-pos -- buf-a buf-max buf-pos' )
\ All writer words take and return this triple.
\
\ We use variables to keep the stack simple.

VARIABLE _LW-BUF    \ buffer base address
VARIABLE _LW-MAX    \ buffer capacity
VARIABLE _LW-POS    \ current write position

: LCF-W-INIT  ( buf-a buf-max -- )
    _LW-MAX ! _LW-BUF ! 0 _LW-POS ! ;

: LCF-W-LEN  ( -- n )
    _LW-POS @ ;

: LCF-W-STR  ( -- addr len )
    _LW-BUF @ _LW-POS @ ;

\ _LW-EMIT ( c -- )  append one byte
: _LW-EMIT  ( c -- )
    _LW-POS @ _LW-MAX @ >= IF DROP LCF-E-OVERFLOW LCF-FAIL EXIT THEN
    _LW-BUF @ _LW-POS @ + C!  1 _LW-POS +! ;

\ _LW-COPY ( addr len -- )  append multiple bytes
: _LW-COPY  ( addr len -- )
    0 DO DUP I + C@ _LW-EMIT LOOP DROP ;

\ _LW-NL ( -- )  emit newline
: _LW-NL  ( -- )  10 _LW-EMIT ;

\ ── Number serialization ─────────────────────────────────────────────

\ _LW-NUM-BUF: scratch for itoa — digits stored right-to-left
CREATE _LW-NBUF 24 ALLOT
VARIABLE _LW-NEG
VARIABLE _LW-VAL

\ _LW-ITOA ( n -- addr len )  convert signed integer to decimal string
\   Result is in _LW-NBUF, valid until next call.
: _LW-ITOA  ( n -- addr len )
    DUP 0= IF DROP _LW-NBUF 48 OVER C! 1 EXIT THEN
    0 _LW-NEG !
    DUP 0< IF NEGATE -1 _LW-NEG ! THEN
    _LW-VAL !
    \ Fill digits right-to-left from position 23
    24                                  \ pos (one past last digit)
    BEGIN _LW-VAL @ 0> WHILE
        1-                              \ pos--
        _LW-VAL @ 10 MOD 48 +          \ digit char
        _LW-NBUF 2 PICK + C!           \ store
        _LW-VAL @ 10 / _LW-VAL !
    REPEAT
    \ Prepend minus if negative
    _LW-NEG @ IF
        1- _LW-NBUF OVER + 45 SWAP C!
    THEN
    \ ( pos )  result starts at _LW-NBUF+pos, length = 24-pos
    _LW-NBUF OVER + SWAP 24 SWAP - ;

\ =====================================================================
\  Writer — high-level emission
\ =====================================================================

\ LCF-W-TABLE ( name-a name-l -- )   emit [name]\n
: LCF-W-TABLE  ( name-a name-l -- )
    91 _LW-EMIT  _LW-COPY  93 _LW-EMIT  _LW-NL ;

\ LCF-W-ATABLE ( name-a name-l -- )   emit [[name]]\n
: LCF-W-ATABLE  ( name-a name-l -- )
    91 _LW-EMIT 91 _LW-EMIT  _LW-COPY  93 _LW-EMIT 93 _LW-EMIT
    _LW-NL ;

\ LCF-W-KV-STR ( key-a key-l val-a val-l -- )  emit key = "val"\n
: LCF-W-KV-STR  ( key-a key-l val-a val-l -- )
    2>R  _LW-COPY
    32 _LW-EMIT 61 _LW-EMIT 32 _LW-EMIT
    34 _LW-EMIT  2R> _LW-COPY  34 _LW-EMIT
    _LW-NL ;

\ LCF-W-KV-INT ( key-a key-l n -- )  emit key = N\n
: LCF-W-KV-INT  ( key-a key-l n -- )
    >R _LW-COPY
    32 _LW-EMIT 61 _LW-EMIT 32 _LW-EMIT
    R> _LW-ITOA _LW-COPY
    _LW-NL ;

\ LCF-W-KV-BOOL ( key-a key-l flag -- )  emit key = true/false\n
: LCF-W-KV-BOOL  ( key-a key-l flag -- )
    >R _LW-COPY
    32 _LW-EMIT 61 _LW-EMIT 32 _LW-EMIT
    R> IF S" true" ELSE S" false" THEN _LW-COPY
    _LW-NL ;

\ LCF-W-NL ( -- )  emit blank line
: LCF-W-NL  ( -- )  _LW-NL ;

\ =====================================================================
\  Writer — convenience: complete messages
\ =====================================================================

\ LCF-W-OK ( buf-a buf-max -- len )
\   Write: [result] status = "ok" (TOML) or {"result":{"status":"ok"}} (JSON)
: LCF-W-OK  ( buf-a buf-max -- len )
    LCF-FORMAT @ LCF-FMT-JSON = IF
        2DUP LCF-W-INIT
        JSON-SET-OUTPUT
        JSON-{
            S" result" JSON-KEY: JSON-{
                S" status" S" ok" JSON-KV-STR
            JSON-}
        JSON-}
        JSON-OUTPUT-RESULT NIP DUP _LW-POS !
    ELSE
        LCF-W-INIT
        S" result" LCF-W-TABLE
        S" status" S" ok" LCF-W-KV-STR
        LCF-W-LEN
    THEN ;

\ LCF-W-ERROR ( buf-a buf-max err-a err-l detail-a detail-l -- len )
\   Write error response with status, error, detail.
: LCF-W-ERROR  ( buf-a buf-max err-a err-l detail-a detail-l -- len )
    LCF-FORMAT @ LCF-FMT-JSON = IF
        2>R 2>R
        2DUP LCF-W-INIT
        JSON-SET-OUTPUT
        JSON-{
            S" result" JSON-KEY: JSON-{
                S" status" S" error" JSON-KV-STR
                2R> S" error" 2SWAP JSON-KV-STR
                2R> S" detail" 2SWAP JSON-KV-STR
            JSON-}
        JSON-}
        JSON-OUTPUT-RESULT NIP DUP _LW-POS !
    ELSE
        2>R 2>R LCF-W-INIT
        S" result" LCF-W-TABLE
        S" status" S" error" LCF-W-KV-STR
        2R> S" error" 2SWAP LCF-W-KV-STR
        2R> S" detail" 2SWAP LCF-W-KV-STR
        LCF-W-LEN
    THEN ;

\ LCF-W-VALUE-RESULT ( buf-a buf-max val-a val-l -- len )
\   Write: [result] status = "ok" value = "val" (TOML or JSON)
: LCF-W-VALUE-RESULT  ( buf-a buf-max val-a val-l -- len )
    LCF-FORMAT @ LCF-FMT-JSON = IF
        2>R
        2DUP LCF-W-INIT
        JSON-SET-OUTPUT
        JSON-{
            S" result" JSON-KEY: JSON-{
                S" status" S" ok" JSON-KV-STR
                S" value" 2R> JSON-KV-STR
            JSON-}
        JSON-}
        JSON-OUTPUT-RESULT NIP DUP _LW-POS !
    ELSE
        2>R LCF-W-INIT
        S" result" LCF-W-TABLE
        S" status" S" ok" LCF-W-KV-STR
        S" value" 2R> LCF-W-KV-STR
        LCF-W-LEN
    THEN ;

\ LCF-W-INT-RESULT ( buf-a buf-max n -- len )
\   Write: [result] status = "ok" value = N (TOML or JSON)
: LCF-W-INT-RESULT  ( buf-a buf-max n -- len )
    LCF-FORMAT @ LCF-FMT-JSON = IF
        >R
        2DUP LCF-W-INIT
        JSON-SET-OUTPUT
        JSON-{
            S" result" JSON-KEY: JSON-{
                S" status" S" ok" JSON-KV-STR
                S" value" R> JSON-KV-NUM
            JSON-}
        JSON-}
        JSON-OUTPUT-RESULT NIP DUP _LW-POS !
    ELSE
        >R LCF-W-INIT
        S" result" LCF-W-TABLE
        S" status" S" ok" LCF-W-KV-STR
        S" value" R> LCF-W-KV-INT
        LCF-W-LEN
    THEN ;

\ =====================================================================
\  Notification reader/writer (DCS API spec §6)
\ =====================================================================

16 CONSTANT LCF-E-NO-NOTIFY

\ LCF-NOTIFICATION? ( doc-a doc-l -- flag )
\   Does the message have a [notification] table?
: LCF-NOTIFICATION?  ( doc-a doc-l -- flag )
    2DUP _LCF-DETECT
    S" notification" _LF-FIND-TABLE? NIP NIP ;

\ LCF-NOTIFY-TYPE ( doc-a doc-l -- type-a type-l )
\   Extract the notification type string.
: LCF-NOTIFY-TYPE  ( doc-a doc-l -- type-a type-l )
    2DUP _LCF-DETECT
    S" notification" _LF-FIND-TABLE
    S" type" _LF-KEY _LF-GET-STRING ;

\ LCF-NOTIFY-PATH ( doc-a doc-l -- path-a path-l )
\   Extract the notification path string.
: LCF-NOTIFY-PATH  ( doc-a doc-l -- path-a path-l )
    2DUP _LCF-DETECT
    S" notification" _LF-FIND-TABLE
    S" path" _LF-KEY _LF-GET-STRING ;

\ LCF-NOTIFY-VALUE ( doc-a doc-l -- val-a val-l )
\   Extract the notification value string.
: LCF-NOTIFY-VALUE  ( doc-a doc-l -- val-a val-l )
    2DUP _LCF-DETECT
    S" notification" _LF-FIND-TABLE
    S" value" _LF-KEY _LF-GET-STRING ;

\ LCF-W-NOTIFICATION ( buf max type-a type-l path-a path-l val-a val-l -- len )
\   Write a notification message.
: LCF-W-NOTIFICATION  ( buf max type-a type-l path-a path-l val-a val-l -- len )
    LCF-FORMAT @ LCF-FMT-JSON = IF
        2>R 2>R 2>R
        2DUP LCF-W-INIT
        JSON-SET-OUTPUT
        JSON-{
            S" notification" JSON-KEY: JSON-{
                2R> S" type" 2SWAP JSON-KV-STR
                2R> S" path" 2SWAP JSON-KV-STR
                2R> S" value" 2SWAP JSON-KV-STR
            JSON-}
        JSON-}
        JSON-OUTPUT-RESULT NIP DUP _LW-POS !
    ELSE
        2>R 2>R 2>R LCF-W-INIT
        S" notification" LCF-W-TABLE
        2R> S" type" 2SWAP LCF-W-KV-STR
        2R> S" path" 2SWAP LCF-W-KV-STR
        2R> S" value" 2SWAP LCF-W-KV-STR
        LCF-W-LEN
    THEN ;

\ ── Updated VALIDATE to also accept notification messages ────────────
\ (Re-defined here because LCF-NOTIFICATION? was not yet available
\  in the original VALIDATE position.)
: LCF-VALIDATE  ( doc-a doc-l -- flag )
    LCF-CLEAR-ERR
    DUP LCF-MAX-SIZE > IF
        LCF-E-TOO-LARGE LCF-FAIL 2DROP 0 EXIT
    THEN
    2DUP _LCF-DETECT
    2DUP LCF-ACTION? IF 2DROP -1 EXIT THEN
    _LF-CLEAR-ERR
    2DUP LCF-RESULT? IF 2DROP -1 EXIT THEN
    _LF-CLEAR-ERR
    2DUP LCF-NOTIFICATION? IF 2DROP -1 EXIT THEN
    2DROP LCF-E-NO-ACTION LCF-FAIL 0 ;

\ =====================================================================
\  Handshake / session (DCS API spec §3)
\ =====================================================================

\ LCF-W-HANDSHAKE ( buf max caps-n ver-a ver-l -- len )
\   Write a handshake request with capabilities count + version.
\   caps-n bitmask: bit0=queries, bit1=mutations, bit2=behaviors,
\   bit3=surfaces.
VARIABLE _LHW-VA
VARIABLE _LHW-VL
VARIABLE _LHW-C
: LCF-W-HANDSHAKE  ( buf max caps-n ver-a ver-l -- len )
    _LHW-VL ! _LHW-VA ! _LHW-C !
    LCF-FORMAT @ LCF-FMT-JSON = IF
        2DUP LCF-W-INIT
        JSON-SET-OUTPUT
        JSON-{
            S" action" JSON-KEY: JSON-{
                S" type" S" handshake" JSON-KV-STR
            JSON-}
            S" capabilities" JSON-KEY: JSON-{
                S" version" _LHW-VA @ _LHW-VL @ JSON-KV-STR
                S" queries"    _LHW-C @ 1 AND 0<> JSON-KV-BOOL
                S" mutations"  _LHW-C @ 2 AND 0<> JSON-KV-BOOL
                S" behaviors"  _LHW-C @ 4 AND 0<> JSON-KV-BOOL
                S" surfaces"   _LHW-C @ 8 AND 0<> JSON-KV-BOOL
            JSON-}
        JSON-}
        JSON-OUTPUT-RESULT NIP DUP _LW-POS !
    ELSE
        LCF-W-INIT
        S" action" LCF-W-TABLE
        S" type" S" handshake" LCF-W-KV-STR
        LCF-W-NL
        S" capabilities" LCF-W-TABLE
        S" version" _LHW-VA @ _LHW-VL @ LCF-W-KV-STR
        S" queries"   _LHW-C @ 1 AND 0<> LCF-W-KV-BOOL
        S" mutations" _LHW-C @ 2 AND 0<> LCF-W-KV-BOOL
        S" behaviors" _LHW-C @ 4 AND 0<> LCF-W-KV-BOOL
        S" surfaces"  _LHW-C @ 8 AND 0<> LCF-W-KV-BOOL
        LCF-W-LEN
    THEN ;

\ LCF-HANDSHAKE? ( doc-a doc-l -- flag )
\   Is this message a handshake?
: LCF-HANDSHAKE?  ( doc-a doc-l -- flag )
    LCF-ACTION-TYPE?
    IF S" handshake" STR-STR=
    ELSE 2DROP 0 THEN ;

\ LCF-SESSION-ID ( doc-a doc-l -- id-a id-l )
\   Extract session-id from a handshake response.
: LCF-SESSION-ID  ( doc-a doc-l -- id-a id-l )
    2DUP _LCF-DETECT
    S" result" _LF-FIND-TABLE
    S" session-id" _LF-KEY _LF-GET-STRING ;

\ =====================================================================
\  Operation vocabulary (spec_v1/05 — 24 named operations)
\ =====================================================================

\ The 24 standard DCS operations, stored as a sorted string table.
\ Each entry: counted string (1-byte length + chars), packed back-to-back.

CREATE _LCF-OPS
  5 C, 99 C, 108 C, 111 C, 115 C, 101 C,                 \ close
  6 C, 99 C, 114 C, 101 C, 97 C, 116 C, 101 C,           \ create
  6 C, 100 C, 101 C, 108 C, 101 C, 116 C, 101 C,         \ delete
  7 C, 100 C, 101 C, 115 C, 116 C, 114 C, 111 C, 121 C,  \ destroy
  4 C, 101 C, 109 C, 105 C, 116 C,                        \ emit
  5 C, 102 C, 111 C, 99 C, 117 C, 115 C,                  \ focus
  9 C, 103 C, 101 C, 116 C, 45 C, 115 C, 116 C, 97 C, 116 C, 101 C, \ get-state
  4 C, 104 C, 105 C, 100 C, 101 C,                        \ hide
  4 C, 108 C, 105 C, 115 C, 116 C,                        \ list
  4 C, 109 C, 111 C, 118 C, 101 C,                        \ move
  4 C, 111 C, 112 C, 101 C, 110 C,                        \ open
  5 C, 113 C, 117 C, 101 C, 114 C, 121 C,                 \ query
  4 C, 114 C, 101 C, 97 C, 100 C,                         \ read
  7 C, 114 C, 101 C, 102 C, 114 C, 101 C, 115 C, 104 C,  \ refresh
  8 C, 114 C, 101 C, 103 C, 105 C, 115 C, 116 C, 101 C, 114 C, \ register
  6 C, 114 C, 101 C, 115 C, 105 C, 122 C, 101 C,         \ resize
  6 C, 115 C, 99 C, 114 C, 111 C, 108 C, 108 C,          \ scroll
  13 C, 115 C, 101 C, 116 C, 45 C, 97 C, 116 C, 116 C, 114 C, 105 C, 98 C, 117 C, 116 C, 101 C, \ set-attribute
  9 C, 115 C, 101 C, 116 C, 45 C, 115 C, 116 C, 97 C, 116 C, 101 C, \ set-state
  4 C, 115 C, 104 C, 111 C, 119 C,                        \ show
  9 C, 115 C, 117 C, 98 C, 115 C, 99 C, 114 C, 105 C, 98 C, 101 C, \ subscribe
  11 C, 117 C, 110 C, 115 C, 117 C, 98 C, 115 C, 99 C, 114 C, 105 C, 98 C, 101 C, \ unsubscribe
  6 C, 117 C, 112 C, 100 C, 97 C, 116 C, 101 C,          \ update
  5 C, 119 C, 114 C, 105 C, 116 C, 101 C,                \ write
  0 C,                                                     \ sentinel

24 CONSTANT LCF-OP-COUNT

\ LCF-OP-VALID? ( name-a name-l -- flag )
\   Is name a valid DCS operation?
VARIABLE _LOP-PA
VARIABLE _LOP-PL
: LCF-OP-VALID?  ( name-a name-l -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    _LOP-PL ! _LOP-PA !
    _LCF-OPS
    BEGIN
        DUP C@ DUP 0>
    WHILE
        \ ( ptr len )
        SWAP 1+ SWAP                     \ skip length byte → ( str-start len )
        _LOP-PL @ OVER = IF
            2DUP _LOP-PA @ _LOP-PL @ STR-STR=
            IF 2DROP -1 EXIT THEN
        THEN
        +                                \ advance past this entry
    REPEAT
    2DROP 0 ;

\ LCF-OP-NTH ( n -- name-a name-l flag )
\   Return the nth operation name (0-based).  flag=-1 if valid index.
: LCF-OP-NTH  ( n -- name-a name-l flag )
    >R _LCF-OPS
    BEGIN
        R@ 0>
    WHILE
        DUP C@ DUP 0= IF DROP R> DROP 0 0 0 EXIT THEN
        1+ +
        R> 1- >R
    REPEAT
    R> DROP
    DUP C@ DUP 0= IF 2DROP 0 0 0 EXIT THEN
    SWAP 1+ SWAP -1 ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _lcf-guard

' LCF-FAIL        CONSTANT _lcf-fail-xt
' LCF-OK?         CONSTANT _lcf-ok-q-xt
' LCF-CLEAR-ERR   CONSTANT _lcf-clear-err-xt
' LCF-ACTION?     CONSTANT _lcf-action-q-xt
' LCF-RESULT?     CONSTANT _lcf-result-q-xt
' LCF-ACTION-TYPE CONSTANT _lcf-action-type-xt
' LCF-ACTION-TYPE? CONSTANT _lcf-action-type-q-xt
' LCF-RESULT-STATUS CONSTANT _lcf-result-status-xt
' LCF-RESULT-OK?  CONSTANT _lcf-result-ok-q-xt
' LCF-RESULT-ERROR CONSTANT _lcf-result-error-xt
' LCF-RESULT-DETAIL CONSTANT _lcf-result-detail-xt
' LCF-BATCH-NTH   CONSTANT _lcf-batch-nth-xt
' LCF-BATCH-OP    CONSTANT _lcf-batch-op-xt
' LCF-BATCH-COUNT CONSTANT _lcf-batch-count-xt
' LCF-ACTION-KEY  CONSTANT _lcf-action-key-xt
' LCF-ACTION-STRING CONSTANT _lcf-action-string-xt
' LCF-QUERY-METHOD CONSTANT _lcf-query-method-xt
' LCF-QUERY-PATH  CONSTANT _lcf-query-path-xt
' LCF-ENTRY-STRING CONSTANT _lcf-entry-string-xt
' LCF-CAP-VERSION CONSTANT _lcf-cap-version-xt
' LCF-CAP-BOOL    CONSTANT _lcf-cap-bool-xt
' LCF-CAP-INT     CONSTANT _lcf-cap-int-xt
' LCF-VALID-KEY?  CONSTANT _lcf-valid-key-q-xt
' LCF-VALIDATE    CONSTANT _lcf-validate-xt
' LCF-W-INIT      CONSTANT _lcf-w-init-xt
' LCF-W-LEN       CONSTANT _lcf-w-len-xt
' LCF-W-STR       CONSTANT _lcf-w-str-xt
' LCF-W-TABLE     CONSTANT _lcf-w-table-xt
' LCF-W-ATABLE    CONSTANT _lcf-w-atable-xt
' LCF-W-KV-STR    CONSTANT _lcf-w-kv-str-xt
' LCF-W-KV-INT    CONSTANT _lcf-w-kv-int-xt
' LCF-W-KV-BOOL   CONSTANT _lcf-w-kv-bool-xt
' LCF-W-NL        CONSTANT _lcf-w-nl-xt
' LCF-W-OK        CONSTANT _lcf-w-ok-xt
' LCF-W-ERROR     CONSTANT _lcf-w-error-xt
' LCF-W-VALUE-RESULT CONSTANT _lcf-w-value-result-xt
' LCF-W-INT-RESULT CONSTANT _lcf-w-int-result-xt
' LCF-NOTIFICATION? CONSTANT _lcf-notification-q-xt
' LCF-NOTIFY-TYPE CONSTANT _lcf-notify-type-xt
' LCF-NOTIFY-PATH CONSTANT _lcf-notify-path-xt
' LCF-NOTIFY-VALUE CONSTANT _lcf-notify-value-xt
' LCF-W-NOTIFICATION CONSTANT _lcf-w-notification-xt
' LCF-VALIDATE    CONSTANT _lcf-validate-xt
' LCF-W-HANDSHAKE CONSTANT _lcf-w-handshake-xt
' LCF-HANDSHAKE?  CONSTANT _lcf-handshake-q-xt
' LCF-SESSION-ID  CONSTANT _lcf-session-id-xt
' LCF-OP-VALID?   CONSTANT _lcf-op-valid-q-xt
' LCF-OP-NTH      CONSTANT _lcf-op-nth-xt

: LCF-FAIL        _lcf-fail-xt _lcf-guard WITH-GUARD ;
: LCF-OK?         _lcf-ok-q-xt _lcf-guard WITH-GUARD ;
: LCF-CLEAR-ERR   _lcf-clear-err-xt _lcf-guard WITH-GUARD ;
: LCF-ACTION?     _lcf-action-q-xt _lcf-guard WITH-GUARD ;
: LCF-RESULT?     _lcf-result-q-xt _lcf-guard WITH-GUARD ;
: LCF-ACTION-TYPE _lcf-action-type-xt _lcf-guard WITH-GUARD ;
: LCF-ACTION-TYPE? _lcf-action-type-q-xt _lcf-guard WITH-GUARD ;
: LCF-RESULT-STATUS _lcf-result-status-xt _lcf-guard WITH-GUARD ;
: LCF-RESULT-OK?  _lcf-result-ok-q-xt _lcf-guard WITH-GUARD ;
: LCF-RESULT-ERROR _lcf-result-error-xt _lcf-guard WITH-GUARD ;
: LCF-RESULT-DETAIL _lcf-result-detail-xt _lcf-guard WITH-GUARD ;
: LCF-BATCH-NTH   _lcf-batch-nth-xt _lcf-guard WITH-GUARD ;
: LCF-BATCH-OP    _lcf-batch-op-xt _lcf-guard WITH-GUARD ;
: LCF-BATCH-COUNT _lcf-batch-count-xt _lcf-guard WITH-GUARD ;
: LCF-ACTION-KEY  _lcf-action-key-xt _lcf-guard WITH-GUARD ;
: LCF-ACTION-STRING _lcf-action-string-xt _lcf-guard WITH-GUARD ;
: LCF-QUERY-METHOD _lcf-query-method-xt _lcf-guard WITH-GUARD ;
: LCF-QUERY-PATH  _lcf-query-path-xt _lcf-guard WITH-GUARD ;
: LCF-ENTRY-STRING _lcf-entry-string-xt _lcf-guard WITH-GUARD ;
: LCF-CAP-VERSION _lcf-cap-version-xt _lcf-guard WITH-GUARD ;
: LCF-CAP-BOOL    _lcf-cap-bool-xt _lcf-guard WITH-GUARD ;
: LCF-CAP-INT     _lcf-cap-int-xt _lcf-guard WITH-GUARD ;
: LCF-VALID-KEY?  _lcf-valid-key-q-xt _lcf-guard WITH-GUARD ;
: LCF-VALIDATE    _lcf-validate-xt _lcf-guard WITH-GUARD ;
: LCF-W-INIT      _lcf-w-init-xt _lcf-guard WITH-GUARD ;
: LCF-W-LEN       _lcf-w-len-xt _lcf-guard WITH-GUARD ;
: LCF-W-STR       _lcf-w-str-xt _lcf-guard WITH-GUARD ;
: LCF-W-TABLE     _lcf-w-table-xt _lcf-guard WITH-GUARD ;
: LCF-W-ATABLE    _lcf-w-atable-xt _lcf-guard WITH-GUARD ;
: LCF-W-KV-STR    _lcf-w-kv-str-xt _lcf-guard WITH-GUARD ;
: LCF-W-KV-INT    _lcf-w-kv-int-xt _lcf-guard WITH-GUARD ;
: LCF-W-KV-BOOL   _lcf-w-kv-bool-xt _lcf-guard WITH-GUARD ;
: LCF-W-NL        _lcf-w-nl-xt _lcf-guard WITH-GUARD ;
: LCF-W-OK        _lcf-w-ok-xt _lcf-guard WITH-GUARD ;
: LCF-W-ERROR     _lcf-w-error-xt _lcf-guard WITH-GUARD ;
: LCF-W-VALUE-RESULT _lcf-w-value-result-xt _lcf-guard WITH-GUARD ;
: LCF-W-INT-RESULT _lcf-w-int-result-xt _lcf-guard WITH-GUARD ;
: LCF-NOTIFICATION? _lcf-notification-q-xt _lcf-guard WITH-GUARD ;
: LCF-NOTIFY-TYPE _lcf-notify-type-xt _lcf-guard WITH-GUARD ;
: LCF-NOTIFY-PATH _lcf-notify-path-xt _lcf-guard WITH-GUARD ;
: LCF-NOTIFY-VALUE _lcf-notify-value-xt _lcf-guard WITH-GUARD ;
: LCF-W-NOTIFICATION _lcf-w-notification-xt _lcf-guard WITH-GUARD ;
: LCF-VALIDATE    _lcf-validate-xt _lcf-guard WITH-GUARD ;
: LCF-W-HANDSHAKE _lcf-w-handshake-xt _lcf-guard WITH-GUARD ;
: LCF-HANDSHAKE?  _lcf-handshake-q-xt _lcf-guard WITH-GUARD ;
: LCF-SESSION-ID  _lcf-session-id-xt _lcf-guard WITH-GUARD ;
: LCF-OP-VALID?   _lcf-op-valid-q-xt _lcf-guard WITH-GUARD ;
: LCF-OP-NTH      _lcf-op-nth-xt _lcf-guard WITH-GUARD ;
[THEN] [THEN]
