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
\  Constants
\ =====================================================================

65536 CONSTANT LCF-MAX-SIZE

\ =====================================================================
\  Reader — message inspection
\ =====================================================================

\ LCF-ACTION? ( doc-a doc-l -- flag )
\   Does the message have an [action] table?
: LCF-ACTION?  ( doc-a doc-l -- flag )
    S" action" TOML-FIND-TABLE? NIP NIP ;

\ LCF-RESULT? ( doc-a doc-l -- flag )
\   Does the message have a [result] table?
: LCF-RESULT?  ( doc-a doc-l -- flag )
    S" result" TOML-FIND-TABLE? NIP NIP ;

\ LCF-ACTION-TYPE ( doc-a doc-l -- str-a str-l )
\   Extract the action type string.
: LCF-ACTION-TYPE  ( doc-a doc-l -- str-a str-l )
    S" action" TOML-FIND-TABLE
    S" type" TOML-KEY TOML-GET-STRING ;

\ LCF-ACTION-TYPE? ( doc-a doc-l -- str-a str-l flag )
\   Like LCF-ACTION-TYPE but returns flag.
: LCF-ACTION-TYPE?  ( doc-a doc-l -- str-a str-l flag )
    TOML-CLEAR-ERR
    TOML-ABORT-ON-ERROR @ 0 TOML-ABORT-ON-ERROR !
    >R >R R> R>
    S" action" TOML-FIND-TABLE?
    IF
        S" type" TOML-KEY?
        IF TOML-GET-STRING -1
        ELSE 2DROP 0 0 0
        THEN
    ELSE
        2DROP 0 0 0
    THEN
    SWAP TOML-ABORT-ON-ERROR ! ;

\ LCF-RESULT-STATUS ( doc-a doc-l -- str-a str-l )
\   Extract the result status string.
: LCF-RESULT-STATUS  ( doc-a doc-l -- str-a str-l )
    S" result" TOML-FIND-TABLE
    S" status" TOML-KEY TOML-GET-STRING ;

\ LCF-RESULT-OK? ( doc-a doc-l -- flag )
\   Is the result status "ok"?
: LCF-RESULT-OK?  ( doc-a doc-l -- flag )
    LCF-RESULT-STATUS S" ok" STR-STR= ;

\ LCF-RESULT-ERROR ( doc-a doc-l -- err-a err-l )
\   Extract the error string from result.
: LCF-RESULT-ERROR  ( doc-a doc-l -- err-a err-l )
    S" result" TOML-FIND-TABLE
    S" error" TOML-KEY TOML-GET-STRING ;

\ LCF-RESULT-DETAIL ( doc-a doc-l -- str-a str-l )
\   Extract the detail string from result.
: LCF-RESULT-DETAIL  ( doc-a doc-l -- str-a str-l )
    S" result" TOML-FIND-TABLE
    S" detail" TOML-KEY TOML-GET-STRING ;

\ =====================================================================
\  Reader — batch access
\ =====================================================================

\ LCF-BATCH-NTH ( doc-a doc-l n -- body-a body-l )
\   Get the nth (0-based) [[batch]] entry.
: LCF-BATCH-NTH  ( doc-a doc-l n -- body-a body-l )
    >R S" batch" R> TOML-FIND-ATABLE ;

\ LCF-BATCH-OP ( body-a body-l -- str-a str-l )
\   Extract the "op" key from a batch entry body.
: LCF-BATCH-OP  ( body-a body-l -- str-a str-l )
    S" op" TOML-KEY TOML-GET-STRING ;

\ LCF-BATCH-COUNT ( doc-a doc-l -- n )
\   Count batch entries by probing index 0, 1, 2...
\   Simple but correct for typical small batches.
VARIABLE _LBC-N
: LCF-BATCH-COUNT  ( doc-a doc-l -- n )
    0 _LBC-N !
    BEGIN
        2DUP S" batch" _LBC-N @ TOML-FIND-ATABLE
        TOML-OK? 0= IF 2DROP THEN
        TOML-OK?
    WHILE
        1 _LBC-N +!
        TOML-CLEAR-ERR
    REPEAT
    2DROP TOML-CLEAR-ERR _LBC-N @ ;

\ =====================================================================
\  Reader — action field helpers
\ =====================================================================

\ LCF-ACTION-KEY ( doc-a doc-l key-a key-l -- val-a val-l )
\   Retrieve a key from the [action] table.
: LCF-ACTION-KEY  ( doc-a doc-l key-a key-l -- val-a val-l )
    2>R S" action" TOML-FIND-TABLE 2R> TOML-KEY ;

\ LCF-ACTION-STRING ( doc-a doc-l key-a key-l -- str-a str-l )
\   Retrieve a string value from [action].
: LCF-ACTION-STRING  ( doc-a doc-l key-a key-l -- str-a str-l )
    LCF-ACTION-KEY TOML-GET-STRING ;

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
    TOML-KEY TOML-GET-STRING ;

\ =====================================================================
\  Reader — capabilities
\ =====================================================================

\ LCF-CAP-VERSION ( doc-a doc-l -- str-a str-l )
\   Extract capabilities.version.
: LCF-CAP-VERSION  ( doc-a doc-l -- str-a str-l )
    S" capabilities" TOML-FIND-TABLE
    S" version" TOML-KEY TOML-GET-STRING ;

\ LCF-CAP-BOOL ( doc-a doc-l key-a key-l -- flag )
\   Extract a boolean capability.
: LCF-CAP-BOOL  ( doc-a doc-l key-a key-l -- flag )
    2>R S" capabilities" TOML-FIND-TABLE 2R> TOML-KEY TOML-GET-BOOL ;

\ LCF-CAP-INT ( doc-a doc-l key-a key-l -- n )
\   Extract an integer capability.
: LCF-CAP-INT  ( doc-a doc-l key-a key-l -- n )
    2>R S" capabilities" TOML-FIND-TABLE 2R> TOML-KEY TOML-GET-INT ;

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
    2DUP LCF-ACTION? IF 2DROP -1 EXIT THEN
    TOML-CLEAR-ERR
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
\   Write: [result]\nstatus = "ok"\n
: LCF-W-OK  ( buf-a buf-max -- len )
    LCF-W-INIT
    S" result" LCF-W-TABLE
    S" status" S" ok" LCF-W-KV-STR
    LCF-W-LEN ;

\ LCF-W-ERROR ( buf-a buf-max err-a err-l detail-a detail-l -- len )
\   Write error response with status, error, detail.
: LCF-W-ERROR  ( buf-a buf-max err-a err-l detail-a detail-l -- len )
    2>R 2>R LCF-W-INIT
    S" result" LCF-W-TABLE
    S" status" S" error" LCF-W-KV-STR
    2R> S" error" 2SWAP LCF-W-KV-STR
    2R> S" detail" 2SWAP LCF-W-KV-STR
    LCF-W-LEN ;

\ LCF-W-VALUE-RESULT ( buf-a buf-max val-a val-l -- len )
\   Write: [result]\nstatus = "ok"\nvalue = "val"\n
: LCF-W-VALUE-RESULT  ( buf-a buf-max val-a val-l -- len )
    2>R LCF-W-INIT
    S" result" LCF-W-TABLE
    S" status" S" ok" LCF-W-KV-STR
    S" value" 2R> LCF-W-KV-STR
    LCF-W-LEN ;

\ LCF-W-INT-RESULT ( buf-a buf-max n -- len )
\   Write: [result]\nstatus = "ok"\nvalue = N\n
: LCF-W-INT-RESULT  ( buf-a buf-max n -- len )
    >R LCF-W-INIT
    S" result" LCF-W-TABLE
    S" status" S" ok" LCF-W-KV-STR
    S" value" R> LCF-W-KV-INT
    LCF-W-LEN ;
