\ yaml.f — YAML 1.2 reader & builder for KDOS / Megapad-64
\
\ A cursor-based YAML library supporting block and flow styles.
\ Operates on (addr len) cursor pairs pointing into YAML text.
\ Understands indentation-based scoping, flow collections,
\ multiple string styles, and multi-document streams.
\
\ Prefix: YAML-   (public API)
\         _YAML-  (internal helpers)
\
\ Load with:   REQUIRE yaml.f

REQUIRE string.f
REQUIRE ../text/utf8.f

PROVIDED akashic-yaml

\ =====================================================================
\  Error Handling  (mirrors json.f / toml.f)
\ =====================================================================

VARIABLE YAML-ERR
VARIABLE YAML-ABORT-ON-ERROR
0 YAML-ERR !
0 YAML-ABORT-ON-ERROR !

1 CONSTANT YAML-E-NOT-FOUND         \ key / path not found
2 CONSTANT YAML-E-WRONG-TYPE        \ value is not the expected type
3 CONSTANT YAML-E-UNTERMINATED      \ unterminated string or block
4 CONSTANT YAML-E-UNEXPECTED        \ unexpected character
5 CONSTANT YAML-E-OVERFLOW          \ buffer overflow
6 CONSTANT YAML-E-BAD-INDENT        \ illegal indentation
7 CONSTANT YAML-E-BAD-SCALAR        \ malformed scalar

: YAML-FAIL  ( err-code -- )
    YAML-ERR !
    YAML-ABORT-ON-ERROR @ IF ABORT" YAML error" THEN ;

: YAML-OK?  ( -- flag )  YAML-ERR @ 0= ;
: YAML-CLEAR-ERR  ( -- )  0 YAML-ERR ! ;

\ _YAML-FAIL-00 ( err -- 0 0 )  fail and leave 0 0
: _YAML-FAIL-00  ( err -- 0 0 )
    YAML-FAIL 0 0 ;

\ =====================================================================
\  Layer 0 — Primitives
\ =====================================================================
\
\  Character-level scanning and indentation helpers.

\ ── Whitespace & Comments ────────────────────────────────────────────

\ YAML-SKIP-WS ( addr len -- addr' len' )
\   Skip horizontal whitespace only (space, tab).
: YAML-SKIP-WS  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 32 = SWAP 9 = OR 0= IF EXIT THEN
        1 /STRING
    REPEAT ;

\ YAML-SKIP-COMMENT ( addr len -- addr' len' )
\   If at '#', skip to end of line. No-op otherwise.
: YAML-SKIP-COMMENT  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 35 <> IF EXIT THEN          \ # = 35
    BEGIN
        DUP 0> WHILE
        OVER C@ 10 = IF EXIT THEN
        OVER C@ 13 = IF EXIT THEN
        1 /STRING
    REPEAT ;

\ YAML-SKIP-EOL ( addr len -- addr' len' )
\   Skip one end-of-line: CR, LF, or CRLF.
: YAML-SKIP-EOL  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 13 = IF
        1 /STRING
        DUP 0> IF OVER C@ 10 = IF 1 /STRING THEN THEN EXIT
    THEN
    OVER C@ 10 = IF 1 /STRING THEN ;

\ YAML-SKIP-LINE ( addr len -- addr' len' )
\   Skip past the rest of the current line including EOL.
: YAML-SKIP-LINE  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 10 = SWAP 13 = OR IF
            YAML-SKIP-EOL EXIT
        THEN
        1 /STRING
    REPEAT ;

\ YAML-SKIP-NL ( addr len -- addr' len' )
\   Skip all whitespace (including newlines), blank lines, and comments.
: YAML-SKIP-NL  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@
        DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR IF
            1 /STRING
        ELSE
            OVER C@ 35 = IF YAML-SKIP-COMMENT
            ELSE EXIT
            THEN
        THEN
    REPEAT ;

\ ── Indentation Measurement ──────────────────────────────────────────

\ YAML-INDENT ( addr len -- n )
\   Count leading spaces on the current line.
\   Only counts space chars (ASCII 32). Tabs are not standard YAML
\   indentation.
: YAML-INDENT  ( addr len -- n )
    0 >R
    BEGIN
        DUP 0> IF OVER C@ 32 = ELSE 0 THEN
    WHILE
        R> 1+ >R
        1 /STRING
    REPEAT
    2DROP R> ;

\ _YAML-SKIP-INDENT ( addr len -- addr' len' )
\   Skip leading spaces at start of a line.
: _YAML-SKIP-INDENT  ( addr len -- addr' len' )
    BEGIN
        DUP 0> IF OVER C@ 32 = ELSE 0 THEN
    WHILE
        1 /STRING
    REPEAT ;

\ ── Line Boundary Helpers ────────────────────────────────────────────

\ _YAML-AT-EOL? ( addr len -- flag )
\   True if at end-of-line, comment, or end of input.
: _YAML-AT-EOL?  ( addr len -- flag )
    DUP 0> 0= IF 2DROP -1 EXIT THEN
    OVER C@ DUP 10 = OVER 13 = OR SWAP 35 = OR NIP NIP ;

\ _YAML-BOL ( addr len base-addr -- offset )
\   Compute the column offset of addr relative to base-addr.
\   This is approximate — used for tracking cursor on same line.
: _YAML-BOL  ( addr len base -- offset )
    DROP SWAP - ;

\ ── Document Markers ─────────────────────────────────────────────────

\ _YAML-3DASH? ( addr len -- flag )
\   Is current position at '---' ?
: _YAML-3DASH?  ( addr len -- flag )
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 45 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 45 <>  IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 45 <>  IF 2DROP 0 EXIT THEN
    \ Must be followed by ws, newline, or EOF
    DUP 3 > IF
        OVER 3 + C@ DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR
        NIP NIP EXIT
    THEN
    2DROP -1 ;

\ _YAML-3DOT? ( addr len -- flag )
\   Is current position at '...' ?
: _YAML-3DOT?  ( addr len -- flag )
    DUP 3 < IF 2DROP 0 EXIT THEN
    OVER C@ 46 <>     IF 2DROP 0 EXIT THEN
    OVER 1+ C@ 46 <>  IF 2DROP 0 EXIT THEN
    OVER 2 + C@ 46 <>  IF 2DROP 0 EXIT THEN
    DUP 3 > IF
        OVER 3 + C@ DUP 32 = OVER 9 = OR OVER 10 = OR SWAP 13 = OR
        NIP NIP EXIT
    THEN
    2DROP -1 ;

\ YAML-SKIP-DOC-START ( addr len -- addr' len' )
\   If at '---', skip past it and EOL. Otherwise no-op.
: YAML-SKIP-DOC-START  ( addr len -- addr' len' )
    2DUP _YAML-3DASH? IF
        3 /STRING
        YAML-SKIP-WS YAML-SKIP-COMMENT YAML-SKIP-EOL
    THEN ;

\ YAML-SKIP-DOC-END ( addr len -- addr' len' )
\   If at '...', skip past it and EOL. Otherwise no-op.
: YAML-SKIP-DOC-END   ( addr len -- addr' len' )
    2DUP _YAML-3DOT? IF
        3 /STRING
        YAML-SKIP-WS YAML-SKIP-COMMENT YAML-SKIP-EOL
    THEN ;

\ ── String Skipping ──────────────────────────────────────────────────

\ YAML-SKIP-DQ-STRING ( addr len -- addr' len' )
\   Skip a double-quoted YAML string. addr must point at opening ".
: YAML-SKIP-DQ-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 34 <> IF EXIT THEN
    1 /STRING
    BEGIN
        DUP 0> WHILE
        OVER C@ 92 = IF             \ backslash escape
            DUP 2 >= IF 2 /STRING ELSE 1 /STRING THEN
        ELSE
            OVER C@ 34 = IF         \ closing "
                1 /STRING EXIT
            THEN
            1 /STRING
        THEN
    REPEAT
    YAML-E-UNTERMINATED YAML-FAIL ;

\ YAML-SKIP-SQ-STRING ( addr len -- addr' len' )
\   Skip a single-quoted YAML string. addr must point at opening '.
\   In YAML, '' inside single-quoted strings is an escaped '.
: YAML-SKIP-SQ-STRING  ( addr len -- addr' len' )
    DUP 0> 0= IF EXIT THEN
    OVER C@ 39 <> IF EXIT THEN
    1 /STRING
    BEGIN
        DUP 0> WHILE
        OVER C@ 39 = IF
            1 /STRING
            \ '' = escaped single quote, continue; lone ' = end
            DUP 0> IF OVER C@ 39 = IF
                1 /STRING           \ skip escaped ''
            ELSE EXIT THEN
            ELSE EXIT THEN
        THEN
        1 /STRING
    REPEAT
    YAML-E-UNTERMINATED YAML-FAIL ;

\ ── Flow Collection Skipping ──────────────────────────────────────────

VARIABLE _YSV-DEPTH
\ YAML-SKIP-FLOW ( addr len -- addr' len' )
\   Skip a flow collection: { ... } or [ ... ].
\   Depth-aware, handles nested structures and strings.
: YAML-SKIP-FLOW  ( addr len -- addr' len' )
    1 _YSV-DEPTH !
    1 /STRING                        \ skip opening { or [
    BEGIN
        DUP 0> _YSV-DEPTH @ 0> AND
    WHILE
        OVER C@
        DUP 34 = IF                  \ "
            DROP YAML-SKIP-DQ-STRING
        ELSE DUP 39 = IF            \ '
            DROP YAML-SKIP-SQ-STRING
        ELSE DUP 123 = OVER 91 = OR IF   \ { or [
            DROP 1 _YSV-DEPTH +!
            1 /STRING
        ELSE DUP 125 = OVER 93 = OR IF   \ } or ]
            DROP -1 _YSV-DEPTH +!
            1 /STRING
        ELSE DUP 35 = IF            \ # comment
            DROP YAML-SKIP-COMMENT
        ELSE
            DROP 1 /STRING
        THEN THEN THEN THEN THEN
    REPEAT ;

\ ── Block Scalar Skipping ────────────────────────────────────────────

\ _YAML-BLOCK-HEADER-INDENT ( addr len -- chomping clip-indent addr' len' )
\   Parse a block scalar header line: |, |-, |+, |2, >+3, etc.
\   chomping: 0=clip, 1=strip, -1=keep
\   clip-indent: 0=auto, >0 explicit
VARIABLE _YBH-CHOMP
VARIABLE _YBH-IND

: _YAML-BLOCK-HEADER  ( addr len -- chomp indent addr' len' )
    0 _YBH-CHOMP !  0 _YBH-IND !
    1 /STRING                        \ skip | or >
    \ Parse optional indicators
    DUP 0> IF
        OVER C@ 45 = IF 1 _YBH-CHOMP ! 1 /STRING    \ -  strip
        ELSE OVER C@ 43 = IF -1 _YBH-CHOMP ! 1 /STRING  \ + keep
        THEN THEN
    THEN
    DUP 0> IF
        OVER C@ DUP 49 >= SWAP 57 <= AND IF   \ 1-9
            OVER C@ 48 - _YBH-IND !
            1 /STRING
        THEN
    THEN
    DUP 0> IF
        OVER C@ 45 = _YBH-CHOMP @ 0= AND IF 1 _YBH-CHOMP ! 1 /STRING
        ELSE OVER C@ 43 = _YBH-CHOMP @ 0= AND IF -1 _YBH-CHOMP ! 1 /STRING
        THEN THEN
    THEN
    YAML-SKIP-WS YAML-SKIP-COMMENT YAML-SKIP-EOL
    _YBH-CHOMP @  _YBH-IND @ ROT ROT ;

\ YAML-SKIP-BLOCK-SCALAR ( addr len -- addr' len' )
\   Skip a block scalar (| or >) and its indented content lines.
\   addr must point at | or >.
VARIABLE _YSBS-BASE
: YAML-SKIP-BLOCK-SCALAR  ( addr len -- addr' len' )
    _YAML-BLOCK-HEADER  2DROP       \ consume header, ignore chomp/indent
    \ Determine base indent from first content line
    2DUP YAML-INDENT _YSBS-BASE !
    _YSBS-BASE @ 0= IF EXIT THEN    \ empty block scalar
    BEGIN
        DUP 0> IF 2DUP YAML-INDENT _YSBS-BASE @ >= ELSE 0 THEN
    WHILE
        YAML-SKIP-LINE
    REPEAT ;

\ ── Skip Any Scalar ──────────────────────────────────────────────────

\ _YAML-SKIP-PLAIN-SCALAR ( addr len -- addr' len' )
\   Skip a plain (unquoted) scalar value on the current line.
\   Stops at EOL, #-comment, flow indicators [:,{}[]] in flow context,
\   or mapping ': ' pattern.
: _YAML-SKIP-PLAIN-SCALAR  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 10 = SWAP 13 = OR IF EXIT THEN
        \ Flow indicators — plain scalars stop at , [ ] { }
        OVER C@ DUP 44 = OVER 91 = OR OVER 93 = OR
        OVER 123 = OR SWAP 125 = OR IF EXIT THEN
        \ '#' preceded by space = comment
        DUP 2 >= IF
            OVER C@ 32 = IF
                OVER 1+ C@ 35 = IF EXIT THEN
            THEN
        THEN
        \ ': ' or ':' at EOL = mapping separator (stop before colon)
        OVER C@ 58 = IF                 \ :
            DUP 1 > IF
                OVER 1+ C@ DUP 32 = OVER 10 = OR SWAP 13 = OR
                IF EXIT THEN
            ELSE EXIT THEN               \ colon at end of input
        THEN
        1 /STRING
    REPEAT ;

\ YAML-SKIP-VALUE ( addr len -- addr' len' )
\   Skip one YAML value of any kind at the current cursor.
\   Handles: quoted strings, flow collections, block scalars,
\   plain scalars.
: YAML-SKIP-VALUE  ( addr len -- addr' len' )
    YAML-SKIP-WS
    DUP 0> 0= IF EXIT THEN
    OVER C@
    DUP 34 = IF DROP YAML-SKIP-DQ-STRING EXIT THEN    \ "
    DUP 39 = IF DROP YAML-SKIP-SQ-STRING EXIT THEN    \ '
    DUP 123 = OVER 91 = OR IF DROP YAML-SKIP-FLOW EXIT THEN   \ { or [
    DUP 124 = OVER 62 = OR IF DROP YAML-SKIP-BLOCK-SCALAR EXIT THEN  \ | or >
    DROP _YAML-SKIP-PLAIN-SCALAR ;

\ =====================================================================
\  Layer 1 — Type Introspection
\ =====================================================================
\
\  Identify the type of the YAML value at the current cursor.

\ Type tag constants
0 CONSTANT YAML-T-ERROR
1 CONSTANT YAML-T-STRING
2 CONSTANT YAML-T-INTEGER
3 CONSTANT YAML-T-BOOL
4 CONSTANT YAML-T-NULL
5 CONSTANT YAML-T-MAPPING
6 CONSTANT YAML-T-SEQUENCE
7 CONSTANT YAML-T-FLOAT

\ ── Null detection ───────────────────────────────────────────────────

\ _YAML-IS-NULL? ( addr len -- flag )
\   Check for null indicators: 'null', '~', or empty value.
: _YAML-IS-NULL?  ( addr len -- flag )
    YAML-SKIP-WS
    DUP 0> 0= IF 2DROP -1 EXIT THEN       \ empty = null
    2DUP _YAML-AT-EOL? IF 2DROP -1 EXIT THEN  \ EOL = null
    OVER C@ 126 = IF                        \ ~ (tilde)
        DUP 1 = IF 2DROP -1 EXIT THEN
        OVER 1+ C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
        NIP NIP EXIT
    THEN
    \ Check 'null'
    DUP 4 < IF 2DROP 0 EXIT THEN
    OVER C@ 110 <>     IF 2DROP 0 EXIT THEN   \ n
    OVER 1+ C@ 117 <>  IF 2DROP 0 EXIT THEN   \ u
    OVER 2 + C@ 108 <> IF 2DROP 0 EXIT THEN   \ l
    OVER 3 + C@ 108 <> IF 2DROP 0 EXIT THEN   \ l
    DUP 4 = IF 2DROP -1 EXIT THEN
    OVER 4 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
    NIP NIP ;

\ ── Boolean detection ────────────────────────────────────────────────

\ _YAML-IS-BOOL? ( addr len -- flag )
\   Check for boolean indicators: true, false, yes, no, on, off
\   (YAML 1.2 Core Schema uses only true/false; we support common forms).
: _YAML-IS-BOOL?  ( addr len -- flag )
    YAML-SKIP-WS
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 116 = SWAP 84 = OR IF      \ t/T (true/True)
        DUP 4 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ DUP 114 = SWAP 82 = OR 0= IF 2DROP 0 EXIT THEN
        OVER 2 + C@ DUP 117 = SWAP 85 = OR 0= IF 2DROP 0 EXIT THEN
        OVER 3 + C@ DUP 101 = SWAP 69 = OR 0= IF 2DROP 0 EXIT THEN
        DUP 4 = IF 2DROP -1 EXIT THEN
        OVER 4 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
        NIP NIP EXIT
    THEN
    OVER C@ DUP 102 = SWAP 70 = OR IF      \ f/F (false/False)
        DUP 5 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ DUP 97 = SWAP 65 = OR 0= IF 2DROP 0 EXIT THEN
        OVER 2 + C@ DUP 108 = SWAP 76 = OR 0= IF 2DROP 0 EXIT THEN
        OVER 3 + C@ DUP 115 = SWAP 83 = OR 0= IF 2DROP 0 EXIT THEN
        OVER 4 + C@ DUP 101 = SWAP 69 = OR 0= IF 2DROP 0 EXIT THEN
        DUP 5 = IF 2DROP -1 EXIT THEN
        OVER 5 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
        NIP NIP EXIT
    THEN
    OVER C@ DUP 121 = SWAP 89 = OR IF      \ y/Y (yes/Yes)
        DUP 3 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ DUP 101 = SWAP 69 = OR 0= IF 2DROP 0 EXIT THEN
        OVER 2 + C@ DUP 115 = SWAP 83 = OR 0= IF 2DROP 0 EXIT THEN
        DUP 3 = IF 2DROP -1 EXIT THEN
        OVER 3 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
        NIP NIP EXIT
    THEN
    OVER C@ DUP 110 = SWAP 78 = OR IF      \ n/N (no/No)
        \ Distinguish from 'null'
        DUP 2 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ DUP 111 = SWAP 79 = OR 0= IF 2DROP 0 EXIT THEN
        DUP 2 = IF 2DROP -1 EXIT THEN
        OVER 2 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
        NIP NIP EXIT
    THEN
    OVER C@ DUP 111 = SWAP 79 = OR IF      \ o/O (on/off)
        DUP 2 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ DUP 110 = SWAP 78 = OR IF  \ on/On
            DUP 2 = IF 2DROP -1 EXIT THEN
            OVER 2 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
            NIP NIP EXIT
        THEN
        OVER 1+ C@ DUP 102 = SWAP 70 = OR IF  \ of -> off
            DUP 3 < IF 2DROP 0 EXIT THEN
            OVER 2 + C@ DUP 102 = SWAP 70 = OR 0= IF 2DROP 0 EXIT THEN
            DUP 3 = IF 2DROP -1 EXIT THEN
            OVER 3 + C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR
            NIP NIP EXIT
        THEN
        2DROP 0 EXIT
    THEN
    2DROP 0 ;

\ ── Integer detection ────────────────────────────────────────────────

: _YAML-DIGIT?  ( c -- flag )  DUP 48 >= SWAP 57 <= AND ;

\ _YAML-IS-INT? ( addr len -- flag )
: _YAML-IS-INT?  ( addr len -- flag )
    YAML-SKIP-WS
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 43 = SWAP 45 = OR IF 1 /STRING THEN   \ skip sign
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    \ Check for 0x, 0o, 0b
    OVER C@ 48 = OVER 2 >= AND IF
        OVER 1+ C@ DUP 120 = OVER 88 = OR        \ 0x
        OVER 111 = OR OVER 79 = OR                \ 0o
        SWAP 98 = OR SWAP 66 = OR IF              \ 0b
            2DROP -1 EXIT                          \ hex/oct/bin = int
        THEN
    THEN
    OVER C@ _YAML-DIGIT? 0= IF 2DROP 0 EXIT THEN
    \ Scan digits (with optional _)
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP _YAML-DIGIT? SWAP 95 = OR IF
            1 /STRING
        ELSE
            OVER C@ DUP 32 = OVER 10 = OR OVER 13 = OR
            OVER 35 = OR SWAP 44 = OR IF
                2DROP -1 EXIT          \ ends at delimiter = integer
            THEN
            \ Check for dot or e/E = float, not integer
            OVER C@ DUP 46 = OVER 101 = OR SWAP 69 = OR IF
                2DROP 0 EXIT
            THEN
            2DROP 0 EXIT
        THEN
    REPEAT
    2DROP -1 ;

\ ── Float detection ──────────────────────────────────────────────────

\ _YAML-IS-FLOAT? ( addr len -- flag )
\   Check for .inf, -.inf, .nan, or numeric with dot/exponent.
: _YAML-IS-FLOAT?  ( addr len -- flag )
    YAML-SKIP-WS
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    \ Check for .inf / .nan / -.inf / +.inf
    OVER C@ DUP 43 = SWAP 45 = OR IF
        DUP 2 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ 46 = IF 2DROP -1 EXIT THEN  \ +. or -. = .inf/.nan
    THEN
    OVER C@ 46 = IF
        DUP 4 < IF 2DROP 0 EXIT THEN
        OVER 1+ C@ DUP 105 = SWAP 110 = OR IF  \ .i (.inf) or .n (.nan)
            2DROP -1 EXIT
        THEN
    THEN
    \ Check for numeric with dot or e/E
    OVER C@ DUP _YAML-DIGIT? OVER 43 = OR SWAP 45 = OR 0= IF
        2DROP 0 EXIT
    THEN
    \ Scan for dot or e/E
    0 >R  \ flag: seen dot/e?
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 46 = OVER 101 = OR SWAP 69 = OR IF
            R> DROP -1 >R
        THEN
        OVER C@ DUP 32 = OVER 10 = OR OVER 13 = OR SWAP 35 = OR IF
            2DROP R> EXIT
        THEN
        1 /STRING
    REPEAT
    2DROP R> ;

\ ── Mapping / Sequence detection ──────────────────────────────────────

\ _YAML-AT-MAP-KEY? ( addr len -- flag )
\   Is the current position at a potential mapping key?
\   Looks for `key: ` or `key:` at EOL pattern.
\   Also handles quoted keys: "key": or 'key':
VARIABLE _YAMK-A
VARIABLE _YAMK-L
: _YAML-AT-MAP-KEY?  ( addr len -- flag )
    YAML-SKIP-WS
    _YAMK-L ! _YAMK-A !
    _YAMK-L @ 0> 0= IF 0 EXIT THEN
    \ Check for quoted key
    _YAMK-A @ C@ DUP 34 = SWAP 39 = OR IF
        _YAMK-A @ _YAMK-L @
        _YAMK-A @ C@ 34 = IF YAML-SKIP-DQ-STRING ELSE YAML-SKIP-SQ-STRING THEN
        YAML-SKIP-WS
        DUP 0> IF OVER C@ 58 = NIP NIP ELSE 2DROP 0 THEN EXIT
    THEN
    \ Check for '? ' explicit key
    _YAMK-A @ C@ 63 = IF
        _YAMK-L @ 1 > IF
            _YAMK-A @ 1+ C@ 32 = IF -1 EXIT THEN
        THEN
    THEN
    \ Plain key: scan for ': ' or ':' at EOL
    _YAMK-A @ _YAMK-L @
    BEGIN
        DUP 0> WHILE
        OVER C@ 58 = IF              \ :
            DUP 1 > IF
                OVER 1+ C@ DUP 32 = OVER 10 = OR SWAP 13 = OR IF
                    2DROP -1 EXIT
                THEN
            ELSE 2DROP -1 EXIT THEN  \ : at end of input
        THEN
        OVER C@ DUP 10 = SWAP 13 = OR IF 2DROP 0 EXIT THEN
        1 /STRING
    REPEAT
    2DROP 0 ;

\ _YAML-AT-SEQ-ITEM? ( addr len -- flag )
\   Is the current position at a sequence indicator '- '?
: _YAML-AT-SEQ-ITEM?  ( addr len -- flag )
    YAML-SKIP-WS
    DUP 2 < IF 2DROP 0 EXIT THEN
    OVER C@ 45 <>    IF 2DROP 0 EXIT THEN    \ -
    OVER 1+ C@ 32 =  NIP NIP ;              \ space after -

\ YAML-TYPE? ( addr len -- type )
\   Determine the type of value at the cursor.
: YAML-TYPE?  ( addr len -- type )
    YAML-SKIP-WS
    DUP 0> 0= IF 2DROP YAML-T-ERROR EXIT THEN
    \ Check structural types first
    OVER C@ 123 = IF 2DROP YAML-T-MAPPING EXIT THEN    \ { flow mapping
    OVER C@ 91 = IF 2DROP YAML-T-SEQUENCE EXIT THEN    \ [ flow sequence
    \ Block scalar indicators
    OVER C@ DUP 124 = SWAP 62 = OR IF 2DROP YAML-T-STRING EXIT THEN  \ | or >
    \ Quoted string
    OVER C@ DUP 34 = SWAP 39 = OR IF 2DROP YAML-T-STRING EXIT THEN
    \ Check for block sequence
    2DUP _YAML-AT-SEQ-ITEM? IF 2DROP YAML-T-SEQUENCE EXIT THEN
    \ Check scalar types
    2DUP _YAML-IS-NULL?  IF 2DROP YAML-T-NULL EXIT THEN
    2DUP _YAML-IS-BOOL?  IF 2DROP YAML-T-BOOL EXIT THEN
    2DUP _YAML-IS-FLOAT? IF 2DROP YAML-T-FLOAT EXIT THEN
    2DUP _YAML-IS-INT?   IF 2DROP YAML-T-INTEGER EXIT THEN
    \ Check for block mapping (key: value)
    2DUP _YAML-AT-MAP-KEY? IF 2DROP YAML-T-MAPPING EXIT THEN
    \ Default: treat as string (plain scalar)
    2DROP YAML-T-STRING ;

\ Convenience predicates
: YAML-STRING?   ( addr len -- flag )  YAML-TYPE? YAML-T-STRING = ;
: YAML-INTEGER?  ( addr len -- flag )  YAML-TYPE? YAML-T-INTEGER = ;
: YAML-BOOL?     ( addr len -- flag )  YAML-TYPE? YAML-T-BOOL = ;
: YAML-NULL?     ( addr len -- flag )  YAML-TYPE? YAML-T-NULL = ;
: YAML-MAPPING?  ( addr len -- flag )  YAML-TYPE? YAML-T-MAPPING = ;
: YAML-SEQUENCE? ( addr len -- flag )  YAML-TYPE? YAML-T-SEQUENCE = ;
: YAML-FLOAT?    ( addr len -- flag )  YAML-TYPE? YAML-T-FLOAT = ;

\ =====================================================================
\  Layer 2 — Value Extraction
\ =====================================================================

\ ── Double-Quoted String ─────────────────────────────────────────────

\ YAML-GET-DQ-STRING ( addr len -- str-addr str-len )
\   Extract inner bytes of a "..." string (without quotes). Zero-copy.
VARIABLE _YGDS-A
VARIABLE _YGDS-L
VARIABLE _YGDS-CNT

: YAML-GET-DQ-STRING  ( addr len -- str-addr str-len )
    1 /STRING  _YGDS-L ! _YGDS-A !  0 _YGDS-CNT !
    _YGDS-A @
    BEGIN _YGDS-L @ 0> WHILE
        _YGDS-A @ C@ 92 = IF
            _YGDS-L @ 2 < IF
                DROP YAML-E-UNTERMINATED _YAML-FAIL-00 EXIT
            THEN
            2 _YGDS-CNT +!
            _YGDS-A @ 2 + _YGDS-A !  _YGDS-L @ 2 - _YGDS-L !
        ELSE
            _YGDS-A @ C@ 34 = IF
                _YGDS-CNT @ EXIT
            THEN
            1 _YGDS-CNT +!
            _YGDS-A @ 1+ _YGDS-A !  _YGDS-L @ 1- _YGDS-L !
        THEN
    REPEAT
    DROP YAML-E-UNTERMINATED _YAML-FAIL-00 ;

\ ── Single-Quoted String ─────────────────────────────────────────────

\ YAML-GET-SQ-STRING ( addr len -- str-addr str-len )
\   Extract inner bytes of a '...' string (without quotes). Zero-copy.
\   Note: '' within single-quoted strings = escaped quote.
VARIABLE _YGSS-A
VARIABLE _YGSS-L
VARIABLE _YGSS-CNT

: YAML-GET-SQ-STRING  ( addr len -- str-addr str-len )
    1 /STRING  _YGSS-L ! _YGSS-A !  0 _YGSS-CNT !
    _YGSS-A @
    BEGIN _YGSS-L @ 0> WHILE
        _YGSS-A @ C@ 39 = IF
            _YGSS-L @ 1- 0> IF
                _YGSS-A @ 1+ C@ 39 = IF
                    \ Escaped '' — count both
                    2 _YGSS-CNT +!
                    _YGSS-A @ 2 + _YGSS-A !
                    _YGSS-L @ 2 - _YGSS-L !
                ELSE
                    \ End of string
                    _YGSS-CNT @ EXIT
                THEN
            ELSE
                \ End of string (last char)
                _YGSS-CNT @ EXIT
            THEN
        ELSE
            1 _YGSS-CNT +!
            _YGSS-A @ 1+ _YGSS-A !  _YGSS-L @ 1- _YGSS-L !
        THEN
    REPEAT
    DROP YAML-E-UNTERMINATED _YAML-FAIL-00 ;

\ ── Plain Scalar Extraction ──────────────────────────────────────────

\ YAML-GET-PLAIN ( addr len -- str-addr str-len )
\   Extract a plain (unquoted) scalar value on the current line.
\   Returns trimmed value. Zero-copy.
: YAML-GET-PLAIN  ( addr len -- str-addr str-len )
    YAML-SKIP-WS
    OVER                             \ save start
    >R
    _YAML-SKIP-PLAIN-SCALAR
    OVER R@ -                        \ compute length (end - start)
    \ Trim trailing whitespace
    DUP 0> IF
        BEGIN
            DUP 0> IF R@ OVER + 1- C@ DUP 32 = SWAP 9 = OR ELSE 0 THEN
        WHILE
            1-
        REPEAT
    THEN
    >R 2DROP R> R> SWAP ;            \ ( start-addr trimmed-len )

\ ── Dispatch string extraction ───────────────────────────────────────

\ YAML-GET-STRING ( addr len -- str-addr str-len )
\   Extract a YAML string value. Dispatches based on style:
\   "..." = double-quoted, '...' = single-quoted, else = plain scalar.
\   Block scalars (| and >) are NOT handled here — use
\   YAML-GET-BLOCK-SCALAR for those.
: YAML-GET-STRING  ( addr len -- str-addr str-len )
    YAML-SKIP-WS
    DUP 0> 0= IF YAML-E-WRONG-TYPE _YAML-FAIL-00 EXIT THEN
    OVER C@ 34 = IF YAML-GET-DQ-STRING EXIT THEN
    OVER C@ 39 = IF YAML-GET-SQ-STRING EXIT THEN
    YAML-GET-PLAIN ;

\ ── String Unescaping ────────────────────────────────────────────────

VARIABLE _YU-DST
VARIABLE _YU-MAX
VARIABLE _YU-POS

: _YU-STORE  ( c -- )
    _YU-POS @ _YU-MAX @ >= IF DROP YAML-E-OVERFLOW YAML-FAIL EXIT THEN
    _YU-DST @ _YU-POS @ + C!  1 _YU-POS +! ;

: _YU-HEX  ( c -- n )
    DUP 48 >= OVER 57 <= AND IF 48 - EXIT THEN
    DUP 65 >= OVER 70 <= AND IF 55 - EXIT THEN
    DUP 97 >= OVER 102 <= AND IF 87 - EXIT THEN
    DROP -1 ;

VARIABLE _YU-CP
: _YU-PARSE-HEX  ( addr n -- codepoint )
    0 _YU-CP !
    0 DO
        DUP I + C@ _YU-HEX
        DUP 0< IF DROP DROP 0xFFFD _YU-CP ! LEAVE THEN
        _YU-CP @ 4 LSHIFT OR _YU-CP !
    LOOP
    DROP _YU-CP @ ;

CREATE _YU-UBUF 4 ALLOT
: _YU-ENCODE-UTF8  ( cp -- )
    DUP 0x80 < IF _YU-STORE EXIT THEN
    _YU-UBUF UTF8-ENCODE _YU-UBUF -
    _YU-UBUF SWAP 0 DO DUP I + C@ _YU-STORE LOOP DROP ;

: YAML-UNESCAPE  ( src slen dest dmax -- len )
    _YU-MAX ! _YU-DST ! 0 _YU-POS !
    BEGIN DUP 0> WHILE
        OVER C@ 92 = IF             \ backslash
            1 /STRING
            DUP 0> 0= IF 2DROP _YU-POS @ EXIT THEN
            OVER C@
            DUP 110 = IF DROP 10 _YU-STORE 1 /STRING ELSE  \ \n
            DUP 114 = IF DROP 13 _YU-STORE 1 /STRING ELSE  \ \r
            DUP 116 = IF DROP  9 _YU-STORE 1 /STRING ELSE  \ \t
            DUP  98 = IF DROP  8 _YU-STORE 1 /STRING ELSE  \ \b
            DUP 102 = IF DROP 12 _YU-STORE 1 /STRING ELSE  \ \f
            DUP  34 = IF DROP 34 _YU-STORE 1 /STRING ELSE  \ \"
            DUP  92 = IF DROP 92 _YU-STORE 1 /STRING ELSE  \ \\
            DUP  47 = IF DROP 47 _YU-STORE 1 /STRING ELSE  \ \/
            DUP  48 = IF DROP  0 _YU-STORE 1 /STRING ELSE  \ \0 null
            DUP  97 = IF DROP  7 _YU-STORE 1 /STRING ELSE  \ \a bell
            DUP 101 = IF DROP 27 _YU-STORE 1 /STRING ELSE  \ \e escape
            DUP 118 = IF DROP 11 _YU-STORE 1 /STRING ELSE  \ \v vtab
            DUP  78 = IF DROP 0x85 _YU-ENCODE-UTF8 1 /STRING ELSE  \ \N NEL
            DUP  95 = IF DROP 0xA0 _YU-ENCODE-UTF8 1 /STRING ELSE  \ \_ NBSP
            DUP  76 = IF DROP 0x2028 _YU-ENCODE-UTF8 1 /STRING ELSE  \ \L LS
            DUP  80 = IF DROP 0x2029 _YU-ENCODE-UTF8 1 /STRING ELSE  \ \P PS
            DUP 120 = IF   \ \xNN
                DROP 1 /STRING
                DUP 2 >= IF OVER 2 _YU-PARSE-HEX _YU-ENCODE-UTF8 2 /STRING
                ELSE 0xFFFD _YU-ENCODE-UTF8 THEN
            ELSE DUP 117 = IF   \ \uNNNN
                DROP 1 /STRING
                DUP 4 >= IF OVER 4 _YU-PARSE-HEX _YU-ENCODE-UTF8 4 /STRING
                ELSE 0xFFFD _YU-ENCODE-UTF8 THEN
            ELSE DUP 85 = IF    \ \UNNNNNNNN
                DROP 1 /STRING
                DUP 8 >= IF OVER 8 _YU-PARSE-HEX _YU-ENCODE-UTF8 8 /STRING
                ELSE 0xFFFD _YU-ENCODE-UTF8 THEN
            ELSE
                \ Unknown escape: pass through
                _YU-STORE 1 /STRING
            THEN THEN THEN
            THEN THEN THEN THEN THEN THEN THEN THEN THEN
            THEN THEN THEN THEN THEN THEN THEN
        ELSE
            OVER C@ _YU-STORE 1 /STRING
        THEN
    REPEAT
    2DROP _YU-POS @ ;

\ ── Integer Extraction ───────────────────────────────────────────────

VARIABLE _YGI-NEG
VARIABLE _YGI-ACC

: _YGI-ACCUM-HEX  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ _YU-HEX DUP 0< IF DROP EXIT THEN
            _YGI-ACC @ 16 * + _YGI-ACC !  1 /STRING
        THEN
    REPEAT ;

: _YGI-ACCUM-OCT  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ DUP 48 >= SWAP 55 <= AND 0= IF EXIT THEN
            OVER C@ 48 -  _YGI-ACC @ 8 * + _YGI-ACC !  1 /STRING
        THEN
    REPEAT ;

: _YGI-ACCUM-BIN  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ DUP 48 = SWAP 49 = OR 0= IF EXIT THEN
            OVER C@ 48 -  _YGI-ACC @ 2 * + _YGI-ACC !  1 /STRING
        THEN
    REPEAT ;

: _YGI-ACCUM-DEC  ( addr len -- addr' len' )
    BEGIN DUP 0> WHILE
        OVER C@ 95 = IF 1 /STRING ELSE
            OVER C@ DUP 48 >= SWAP 57 <= AND 0= IF EXIT THEN
            OVER C@ 48 -  _YGI-ACC @ 10 * + _YGI-ACC !  1 /STRING
        THEN
    REPEAT ;

: _YGI-RESULT  ( -- n )
    _YGI-NEG @ IF _YGI-ACC @ NEGATE ELSE _YGI-ACC @ THEN ;

\ YAML-GET-INT ( addr len -- n )
\   Parse a YAML integer. Supports dec, 0x hex, 0o octal, 0b binary,
\   underscore separators, and +/- signs.
: YAML-GET-INT  ( addr len -- n )
    YAML-SKIP-WS
    0 _YGI-NEG !  0 _YGI-ACC !
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ 43 = IF 1 /STRING THEN
    DUP 0> IF OVER C@ 45 = IF -1 _YGI-NEG ! 1 /STRING THEN THEN
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    \ Check for 0x, 0o, 0b prefix
    OVER C@ 48 = OVER 2 >= AND IF
        OVER 1+ C@ DUP 120 = OVER 88 = OR IF
            DROP 2 /STRING _YGI-ACCUM-HEX 2DROP _YGI-RESULT EXIT
        THEN
        DUP 111 = OVER 79 = OR IF
            DROP 2 /STRING _YGI-ACCUM-OCT 2DROP _YGI-RESULT EXIT
        THEN
        DUP 98 = OVER 66 = OR IF
            DROP 2 /STRING _YGI-ACCUM-BIN 2DROP _YGI-RESULT EXIT
        THEN
        DROP
    THEN
    _YGI-ACCUM-DEC 2DROP _YGI-RESULT ;

\ ── Boolean Extraction ───────────────────────────────────────────────

\ YAML-GET-BOOL ( addr len -- flag )
\   true/True/TRUE/yes/Yes/YES/on/On/ON → -1
\   false/False/FALSE/no/No/NO/off/Off/OFF → 0
: YAML-GET-BOOL  ( addr len -- flag )
    YAML-SKIP-WS
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 116 = SWAP 84 = OR IF 2DROP -1 EXIT THEN   \ t/T
    OVER C@ DUP 121 = SWAP 89 = OR IF 2DROP -1 EXIT THEN   \ y/Y
    OVER C@ DUP 102 = SWAP 70 = OR IF 2DROP  0 EXIT THEN   \ f/F
    OVER C@ DUP 110 = SWAP 78 = OR IF                      \ n/N
        DUP 2 >= IF OVER 1+ C@ DUP 111 = SWAP 79 = OR IF
            2DROP 0 EXIT                                     \ no/No
        THEN THEN
    THEN
    OVER C@ DUP 111 = SWAP 79 = OR IF                      \ o/O
        DUP 2 >= IF OVER 1+ C@ DUP 110 = SWAP 78 = OR IF
            2DROP -1 EXIT                                    \ on/On
        THEN THEN
        DUP 3 >= IF OVER 1+ C@ DUP 102 = SWAP 70 = OR IF
            2DROP 0 EXIT                                     \ off/Off
        THEN THEN
    THEN
    2DROP YAML-E-WRONG-TYPE YAML-FAIL 0 ;

\ ── Float raw extraction ─────────────────────────────────────────────

\ YAML-GET-FLOAT-STR ( addr len -- str-a str-l )
\   Extract a float value as a raw string token.
: YAML-GET-FLOAT-STR  ( addr len -- str-a str-l )
    YAML-SKIP-WS  OVER
    BEGIN DUP 0> WHILE
        OVER C@ DUP 32 = OVER 9 = OR OVER 10 = OR OVER 13 = OR
        SWAP 35 = OR
        IF NIP SWAP - EXIT THEN
        1 /STRING
    REPEAT
    NIP SWAP - ;

\ =====================================================================
\  Layer 3 — Block Scalar Extraction
\ =====================================================================

\ YAML-GET-BLOCK-SCALAR ( addr len dest dmax -- len )
\   Extract a literal (|) or folded (>) block scalar into a buffer.
\   addr must point at | or >.
\   Returns actual bytes written. Handles chomp indicators (-, +).
\   Literal (|): preserves newlines.
\   Folded (>): replaces single newlines with spaces (double = kept).
VARIABLE _YGBS-DST
VARIABLE _YGBS-MAX
VARIABLE _YGBS-POS
VARIABLE _YGBS-BASE
VARIABLE _YGBS-FOLD
VARIABLE _YGBS-CHOMP

: _YGBS-PUT  ( c -- )
    _YGBS-POS @ _YGBS-MAX @ >= IF DROP YAML-E-OVERFLOW YAML-FAIL EXIT THEN
    _YGBS-DST @ _YGBS-POS @ + C!  1 _YGBS-POS +! ;

\ _YGBS-COPY-LINE ( addr len -- addr' len' )
\   Copy bytes to the output buffer until EOL or end of input.
\   Stops AT the newline char (does not consume it).
: _YGBS-COPY-LINE  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 10 = SWAP 13 = OR IF EXIT THEN
        OVER C@ _YGBS-PUT
        1 /STRING
    REPEAT ;

\ _YGBS-APPLY-CHOMP ( -- )
\   Apply chomping mode to the output buffer.
: _YGBS-APPLY-CHOMP  ( -- )
    _YGBS-CHOMP @ 1 = IF  \ strip: remove all trailing newlines
        BEGIN
            _YGBS-POS @ 0> IF
                _YGBS-DST @ _YGBS-POS @ 1- + C@ 10 =
            ELSE 0 THEN
        WHILE
            -1 _YGBS-POS +!
        REPEAT
    THEN
    _YGBS-CHOMP @ 0= IF  \ clip: keep exactly one trailing newline
        BEGIN
            _YGBS-POS @ 1 > IF
                _YGBS-DST @ _YGBS-POS @ 1- + C@ 10 =
                _YGBS-DST @ _YGBS-POS @ 2 - + C@ 10 = AND
            ELSE 0 THEN
        WHILE
            -1 _YGBS-POS +!
        REPEAT
    THEN ;

: YAML-GET-BLOCK-SCALAR  ( addr len dest dmax -- len )
    _YGBS-MAX ! _YGBS-DST ! 0 _YGBS-POS !
    OVER C@ 62 = IF -1 ELSE 0 THEN _YGBS-FOLD !  \ > = fold, | = literal
    _YAML-BLOCK-HEADER                  \ ( chomp indent addr' len' )
    2SWAP _YGBS-CHOMP ! DROP            \ store chomp, discard explicit indent
    \ Determine base indent from first content line
    2DUP YAML-INDENT _YGBS-BASE !
    _YGBS-BASE @ 0= IF 2DROP _YGBS-POS @ EXIT THEN
    BEGIN
        DUP 0> WHILE
        2DUP YAML-INDENT DUP _YGBS-BASE @ < IF
            \ Less indented line — check if blank
            DROP 2DUP _YAML-AT-EOL? IF
                \ Blank line: output newline
                10 _YGBS-PUT
                YAML-SKIP-LINE
            ELSE
                \ Real content at lower indent — end of block
                2DROP _YGBS-APPLY-CHOMP _YGBS-POS @ EXIT
            THEN
        ELSE
            DROP
            \ Skip past indent
            _YGBS-BASE @ /STRING
            \ Copy line content up to EOL
            _YGBS-COPY-LINE
            \ Handle the newline if present
            DUP 0> IF
                OVER C@ DUP 10 = SWAP 13 = OR IF
                    \ At EOL — handle folding
                    _YGBS-FOLD @ IF
                        \ Peek at next line: blank or less-indented = keep NL
                        2DUP YAML-SKIP-EOL
                        2DUP _YAML-AT-EOL? IF
                            10 _YGBS-PUT
                        ELSE
                            2DUP YAML-INDENT _YGBS-BASE @ >= IF
                                32 _YGBS-PUT      \ fold: NL → space
                            ELSE
                                10 _YGBS-PUT
                            THEN
                        THEN
                        2DROP
                    ELSE
                        10 _YGBS-PUT               \ literal: keep NL
                    THEN
                    YAML-SKIP-EOL
                THEN
            THEN
        THEN
    REPEAT
    _YGBS-APPLY-CHOMP
    2DROP _YGBS-POS @ ;

\ =====================================================================
\  Layer 4 — Mapping Navigation
\ =====================================================================

\ ── Key extraction helper ────────────────────────────────────────────

\ _YAML-EXTRACT-KEY ( addr len -- key-a key-l rest-a rest-l )
\   At a mapping line, extract the key and return cursor at value.
\   Handles plain keys, "quoted" keys, 'quoted' keys.
VARIABLE _YEK-A
VARIABLE _YEK-L

: _YAML-EXTRACT-KEY  ( addr len -- key-a key-l rest-a rest-l )
    YAML-SKIP-WS _YEK-L ! _YEK-A !
    _YEK-A @ C@ 34 = IF             \ double-quoted key
        _YEK-A @ _YEK-L @ YAML-GET-DQ-STRING  ( key-a key-l )
        _YEK-A @ _YEK-L @ YAML-SKIP-DQ-STRING
        YAML-SKIP-WS
        DUP 0> IF OVER C@ 58 = IF 1 /STRING THEN THEN
        YAML-SKIP-WS
        2SWAP EXIT
    THEN
    _YEK-A @ C@ 39 = IF             \ single-quoted key
        _YEK-A @ _YEK-L @ YAML-GET-SQ-STRING  ( key-a key-l )
        _YEK-A @ _YEK-L @ YAML-SKIP-SQ-STRING
        YAML-SKIP-WS
        DUP 0> IF OVER C@ 58 = IF 1 /STRING THEN THEN
        YAML-SKIP-WS
        2SWAP EXIT
    THEN
    \ Plain key: scan for ': ' or ':'+EOL
    _YEK-A @ 0  ( start count )
    _YEK-A @ _YEK-L @
    BEGIN
        DUP 0> WHILE
        OVER C@ 58 = IF             \ :
            DUP 1 > IF
                OVER 1+ C@ DUP 32 = OVER 10 = OR SWAP 13 = OR IF
                    \ Found ': ' — key is (start, count)
                    1 /STRING       \ skip :
                    YAML-SKIP-WS
                    2SWAP EXIT
                THEN
            ELSE
                \ ':' at end of input  — skip : and ws
                1 /STRING
                YAML-SKIP-WS
                2SWAP EXIT
            THEN
        THEN
        >R >R 1+ R> R>              \ increment count
        1 /STRING
    REPEAT
    \ No colon found — return the whole thing as key, empty value
    2DROP ;

\ ── Key Lookup ───────────────────────────────────────────────────────

VARIABLE _YK-KA
VARIABLE _YK-KL
VARIABLE _YK-BASE

\ _YAML-SKIP-BLANKLINES ( addr len -- addr' len' )
\   Skip past blank lines (CR/LF only) but preserve leading spaces
\   on the first content-bearing line.  Needed for indent detection.
: _YAML-SKIP-BLANKLINES  ( addr len -- addr' len' )
    BEGIN
        DUP 0> WHILE
        OVER C@ DUP 10 = SWAP 13 = OR IF
            1 /STRING
        ELSE EXIT THEN
    REPEAT ;

\ YAML-KEY ( addr len kaddr klen -- vaddr vlen )
\   Find key in a block mapping. Searches only at the current
\   indentation level (depth-aware).  Returns cursor at value.
: YAML-KEY  ( addr len kaddr klen -- vaddr vlen )
    _YK-KL ! _YK-KA !
    _YAML-SKIP-BLANKLINES
    \ Record base indent
    2DUP YAML-INDENT _YK-BASE !
    BEGIN
        DUP 0>
    WHILE
        _YAML-SKIP-BLANKLINES
        DUP 0> 0= IF YAML-E-NOT-FOUND _YAML-FAIL-00 EXIT THEN
        \ Check for document markers — stop search
        2DUP _YAML-3DASH? IF 2DROP YAML-E-NOT-FOUND _YAML-FAIL-00 EXIT THEN
        2DUP _YAML-3DOT?  IF 2DROP YAML-E-NOT-FOUND _YAML-FAIL-00 EXIT THEN
        \ Check indentation
        2DUP YAML-INDENT DUP _YK-BASE @ < IF
            \ Dedented past our scope — not found
            DROP 2DROP YAML-E-NOT-FOUND _YAML-FAIL-00 EXIT
        THEN
        _YK-BASE @ = IF
            \ Same indent level — try to match key
            _YAML-SKIP-INDENT
            2DUP _YAML-EXTRACT-KEY     ( orig-a orig-l rest-a rest-l key-a key-l )
            _YK-KA @ _YK-KL @ STR-STR=
            IF 2SWAP 2DROP EXIT THEN   \ found! return (rest-a rest-l)
            2DROP                       \ not this key — drop (rest-a rest-l)
            YAML-SKIP-LINE
        ELSE
            \ More indented — skip (belongs to previous key's value)
            YAML-SKIP-LINE
        THEN
    REPEAT
    YAML-E-NOT-FOUND _YAML-FAIL-00 ;

\ YAML-KEY? ( addr len kaddr klen -- vaddr vlen flag )
\   Like YAML-KEY but returns a flag instead of failing.
: YAML-KEY?  ( addr len kaddr klen -- vaddr vlen flag )
    YAML-ABORT-ON-ERROR @ >R
    YAML-CLEAR-ERR  0 YAML-ABORT-ON-ERROR !
    YAML-KEY
    R> YAML-ABORT-ON-ERROR !
    YAML-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

\ YAML-HAS?  ( addr len kaddr klen -- flag )
\   Does this mapping contain the key?
: YAML-HAS?  ( addr len kaddr klen -- flag )
    YAML-ABORT-ON-ERROR @ >R
    2>R 2DUP 2R>
    YAML-CLEAR-ERR  0 YAML-ABORT-ON-ERROR !
    YAML-KEY
    R> YAML-ABORT-ON-ERROR !
    YAML-OK?
    >R 2DROP 2DROP R> ;

\ =====================================================================
\  Layer 5 — Sequence Navigation
\ =====================================================================

\ YAML-ENTER ( addr len -- addr' len' )
\   Enter a flow collection (past {/[) or position at first item of
\   a block sequence/mapping.
: YAML-ENTER  ( addr len -- addr' len' )
    YAML-SKIP-WS
    DUP 0> 0= IF YAML-E-UNEXPECTED YAML-FAIL EXIT THEN
    OVER C@ DUP 123 = SWAP 91 = OR IF
        1 /STRING YAML-SKIP-NL EXIT   \ flow: skip { or [
    THEN
    \ Block: skip past '- '
    2DUP _YAML-AT-SEQ-ITEM? IF
        2 /STRING YAML-SKIP-WS EXIT
    THEN
    \ Already at content (mapping or value)
    ;

\ ── Flow collection navigation ───────────────────────────────────────

\ YAML-FLOW-NEXT ( addr len -- addr' len' flag )
\   Advance to next element in a flow collection.
\   Skips current value, comma, whitespace.
\   Returns flag = -1 if more elements, 0 at closing ]/}.
: YAML-FLOW-NEXT  ( addr len -- addr' len' flag )
    YAML-SKIP-VALUE YAML-SKIP-NL
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 93 = IF 0 EXIT THEN     \ ]
    OVER C@ 125 = IF 0 EXIT THEN    \ }
    OVER C@ 44 = IF 1 /STRING THEN  \ skip ,
    YAML-SKIP-NL
    DUP 0> 0= IF 0 EXIT THEN
    OVER C@ 93 = IF 0 EXIT THEN
    OVER C@ 125 = IF 0 EXIT THEN
    -1 ;

\ ── Block sequence navigation ────────────────────────────────────────

VARIABLE _YBN-BASE

\ YAML-BLOCK-NEXT ( addr len -- addr' len' flag )
\   Advance to the next item in a block sequence.
\   Skips current item's value lines, finds next '- ' at same indent.
\   Returns flag = -1 if found, 0 at end.
: YAML-BLOCK-NEXT  ( addr len -- addr' len' flag )
    \ Skip the rest of the current line
    YAML-SKIP-LINE
    BEGIN
        DUP 0> WHILE
        \ Skip blank lines and comments
        2DUP _YAML-AT-EOL? IF YAML-SKIP-LINE
        ELSE
            2DUP YAML-INDENT
            2DUP _YBN-BASE @ < IF
                2DROP 0 EXIT             \ dedent — end of sequence
            THEN
            _YBN-BASE @ = IF
                \ Same indent — is it a '- '?
                _YAML-SKIP-INDENT
                2DUP _YAML-AT-SEQ-ITEM? IF
                    2 /STRING YAML-SKIP-WS  \ skip '- '
                    -1 EXIT
                THEN
                \ Same indent but no dash — end of this sequence
                0 EXIT
            ELSE
                DROP
                \ More indented — part of current item, skip
                YAML-SKIP-LINE
            THEN
        THEN
    REPEAT
    0 ;

\ YAML-SEQ-INIT ( addr len -- addr' len' )
\   Initialize block sequence iteration. Records base indent.
\   Cursor must be at the first '- '.
: YAML-SEQ-INIT  ( addr len -- addr' len' )
    2DUP YAML-INDENT _YBN-BASE !
    _YAML-SKIP-INDENT
    2 /STRING YAML-SKIP-WS ;        \ skip '- '

\ YAML-NTH ( addr len n -- addr' len' )
\   Jump to the nth item (0-based) in a block sequence.
\   Cursor must be at or before the first '- '.
: YAML-NTH  ( addr len n -- addr' len' )
    >R
    YAML-SKIP-NL
    2DUP YAML-INDENT _YBN-BASE !
    _YAML-SKIP-INDENT
    2DUP _YAML-AT-SEQ-ITEM? 0= IF
        R> DROP YAML-E-WRONG-TYPE YAML-FAIL EXIT
    THEN
    2 /STRING YAML-SKIP-WS
    R> DUP 0= IF DROP EXIT THEN     \ 0th = already there
    0 DO
        YAML-BLOCK-NEXT 0= IF
            YAML-E-NOT-FOUND YAML-FAIL UNLOOP EXIT
        THEN
    LOOP ;

\ YAML-COUNT ( addr len -- n )
\   Count items in a block sequence by scanning.
: YAML-COUNT  ( addr len -- n )
    YAML-SKIP-NL
    2DUP YAML-INDENT _YBN-BASE !
    0 >R
    BEGIN
        DUP 0> WHILE
        2DUP _YAML-AT-EOL? IF YAML-SKIP-LINE
        ELSE
            2DUP YAML-INDENT DUP _YBN-BASE @ < IF
                DROP 2DROP R> EXIT
            THEN
            _YBN-BASE @ = IF
                _YAML-SKIP-INDENT
                2DUP _YAML-AT-SEQ-ITEM? IF
                    R> 1+ >R
                THEN
                YAML-SKIP-LINE
            ELSE
                DROP YAML-SKIP-LINE
            THEN
        THEN
    REPEAT
    2DROP R> ;

\ ── Flow collection count ────────────────────────────────────────────

\ YAML-FLOW-COUNT ( addr len -- n )
\   Count elements in a flow collection. Cursor must be past [/{.
: YAML-FLOW-COUNT  ( addr len -- n )
    0 >R
    YAML-SKIP-NL
    DUP 0> 0= IF 2DROP R> EXIT THEN
    OVER C@ 93 = IF 2DROP R> EXIT THEN
    OVER C@ 125 = IF 2DROP R> EXIT THEN
    R> 1+ >R
    BEGIN
        YAML-SKIP-VALUE YAML-SKIP-NL
        DUP 0> IF
            OVER C@ 44 = IF
                1 /STRING YAML-SKIP-NL
                R> 1+ >R -1
            ELSE 0 THEN
        ELSE 0 THEN
    0= UNTIL
    2DROP R> ;

\ =====================================================================
\  Layer 6 — Path Navigation
\ =====================================================================

\ _YAML-FIND-DOT ( addr len -- offset | -1 )
: _YAML-FIND-DOT  ( addr len -- offset )
    0 DO
        DUP I + C@ 46 = IF DROP I UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

VARIABLE _YP-PA
VARIABLE _YP-PL

\ YAML-PATH ( addr len path-a path-l -- addr' len' )
\   Navigate a dot-separated path through block mappings.
\   Each segment is a key name. Does NOT handle array indices.
: YAML-PATH  ( addr len paddr plen -- addr' len' )
    _YP-PL ! _YP-PA !
    BEGIN
        _YP-PL @ 0>
    WHILE
        _YP-PA @ _YP-PL @ _YAML-FIND-DOT
        DUP -1 = IF
            \ Last segment
            DROP
            _YP-PA @ _YP-PL @ YAML-KEY
            EXIT
        THEN
        \ Dot at offset — extract segment before dot
        >R
        _YP-PA @ R@ YAML-KEY
        YAML-OK? 0= IF R> DROP EXIT THEN
        \ Advance path past the dot
        _YP-PA @ R@ 1+ + _YP-PA !
        _YP-PL @ R> 1+ - _YP-PL !
    REPEAT ;

\ YAML-PATH? ( addr len path-a path-l -- addr' len' flag )
: YAML-PATH?  ( addr len paddr plen -- addr' len' flag )
    YAML-ABORT-ON-ERROR @ >R
    YAML-CLEAR-ERR  0 YAML-ABORT-ON-ERROR !
    YAML-PATH
    R> YAML-ABORT-ON-ERROR !
    YAML-OK? DUP 0= IF >R 2DROP 0 0 R> THEN ;

\ =====================================================================
\  Layer 7 — Iteration
\ =====================================================================

\ YAML-EACH-KEY ( addr len -- addr' len' key-a key-l flag )
\   Iterate over key-value pairs in a block mapping.
\   Returns next key and positions cursor at value.
\   flag = -1 if pair found, 0 at end.
VARIABLE _YEK-BASE
VARIABLE _YEK-INIT

: YAML-EACH-KEY  ( addr len -- addr' len' key-a key-l flag )
    YAML-SKIP-NL
    DUP 0> 0= IF 0 0 0 EXIT THEN
    \ Check for document markers
    2DUP _YAML-3DASH? IF 0 0 0 EXIT THEN
    2DUP _YAML-3DOT?  IF 0 0 0 EXIT THEN
    \ Check for end of block (dedent)
    2DUP YAML-INDENT
    _YEK-INIT @ 0= IF
        DUP _YEK-BASE !  -1 _YEK-INIT !
    THEN
    _YEK-BASE @ < IF 0 0 0 EXIT THEN
    \ Not at a map key? — end
    _YAML-SKIP-INDENT
    2DUP _YAML-AT-MAP-KEY? 0= IF 0 0 0 EXIT THEN
    _YAML-EXTRACT-KEY               ( key-a key-l val-a val-l )
    2SWAP -1 ;

\ YAML-EACH-RESET ( -- )
\   Reset iteration state. Call before starting a new YAML-EACH-KEY loop.
: YAML-EACH-RESET  ( -- )
    0 _YEK-BASE !  0 _YEK-INIT ! ;

\ =====================================================================
\  Layer 8 — Comparison & Guards
\ =====================================================================

\ YAML-STRING= ( addr len saddr slen -- flag )
\   Compare the string value at cursor to a Forth string.
: YAML-STRING=  ( addr len saddr slen -- flag )
    2>R YAML-GET-STRING 2R> STR-STR= ;

\ YAML-INT= ( addr len n -- flag )
: YAML-INT=  ( addr len n -- flag )
    >R YAML-GET-INT R> = ;

\ Type guards — assert and pass through, or fail.
: YAML-EXPECT-STRING  ( addr len -- addr len )
    2DUP YAML-STRING? 0= IF YAML-E-WRONG-TYPE YAML-FAIL THEN ;

: YAML-EXPECT-INTEGER  ( addr len -- addr len )
    2DUP YAML-INTEGER? 0= IF YAML-E-WRONG-TYPE YAML-FAIL THEN ;

: YAML-EXPECT-BOOL  ( addr len -- addr len )
    2DUP YAML-BOOL? 0= IF YAML-E-WRONG-TYPE YAML-FAIL THEN ;

: YAML-EXPECT-NULL  ( addr len -- addr len )
    2DUP YAML-NULL? 0= IF YAML-E-WRONG-TYPE YAML-FAIL THEN ;

: YAML-EXPECT-MAPPING  ( addr len -- addr len )
    2DUP YAML-MAPPING? 0= IF YAML-E-WRONG-TYPE YAML-FAIL THEN ;

: YAML-EXPECT-SEQUENCE  ( addr len -- addr len )
    2DUP YAML-SEQUENCE? 0= IF YAML-E-WRONG-TYPE YAML-FAIL THEN ;

\ =====================================================================
\  Layer 9 — Flow Mapping Key Lookup
\ =====================================================================

\ YAML-FKEY ( addr len kaddr klen -- vaddr vlen )
\   Find a key in a flow mapping { key: val, key: val }.
\   Cursor must be past the opening {.
VARIABLE _YFK-KA
VARIABLE _YFK-KL

: YAML-FKEY  ( addr len kaddr klen -- vaddr vlen )
    _YFK-KL ! _YFK-KA !
    YAML-SKIP-NL
    BEGIN
        DUP 0> IF OVER C@ 125 <> ELSE 0 THEN   \ not }
    WHILE
        OVER C@ 44 = IF 1 /STRING YAML-SKIP-NL THEN
        \ Extract key
        2DUP YAML-GET-STRING              ( obj-a obj-l key-a key-l )
        _YFK-KA @ _YFK-KL @ STR-STR= IF
            \ Match — skip key string and colon
            YAML-SKIP-VALUE YAML-SKIP-WS
            DUP 0> IF OVER C@ 58 = IF 1 /STRING THEN THEN
            YAML-SKIP-WS
            EXIT
        THEN
        \ No match — skip key : value pair
        YAML-SKIP-VALUE YAML-SKIP-WS      \ skip key
        DUP 0> IF OVER C@ 58 = IF 1 /STRING THEN THEN
        YAML-SKIP-VALUE YAML-SKIP-NL      \ skip value
    REPEAT
    2DROP YAML-E-NOT-FOUND _YAML-FAIL-00 ;

\ =====================================================================
\  Layer 10 — YAML Builder (Emitter)
\ =====================================================================
\
\  Build YAML text programmatically.
\  Supports block-style output with proper indentation.

\ ── Vectored output ──────────────────────────────────────────────────

VARIABLE YAML-EMIT-XT
VARIABLE YAML-TYPE-XT

: _YAML-DEFAULT-EMIT  EMIT ;
: _YAML-DEFAULT-TYPE  TYPE ;

' _YAML-DEFAULT-EMIT YAML-EMIT-XT !
' _YAML-DEFAULT-TYPE YAML-TYPE-XT !

: YAML-EMIT  ( c -- )   YAML-EMIT-XT @ EXECUTE ;
: YAML-TYPE  ( a u -- ) YAML-TYPE-XT @ EXECUTE ;

\ ── Buffer output target ─────────────────────────────────────────────

VARIABLE _YB-BUF
VARIABLE _YB-MAX
VARIABLE _YB-POS

: _YB-EMIT  ( c -- )
    _YB-POS @  _YB-MAX @  < IF
        _YB-BUF @ _YB-POS @ + C!
        1 _YB-POS +!
    ELSE DROP THEN ;

: _YB-TYPE  ( addr len -- )
    0 DO DUP I + C@ _YB-EMIT LOOP DROP ;

: YAML-SET-OUTPUT  ( addr max -- )
    _YB-MAX ! _YB-BUF !  0 _YB-POS !
    ['] _YB-EMIT YAML-EMIT-XT !
    ['] _YB-TYPE YAML-TYPE-XT ! ;

: YAML-OUTPUT-RESULT  ( -- addr len )
    _YB-BUF @ _YB-POS @ ;

: YAML-OUTPUT-RESET  ( -- )
    0 _YB-POS ! ;

\ ── Indentation State ────────────────────────────────────────────────

VARIABLE _YB-LEVEL                   \ current nesting depth
VARIABLE _YB-INDENT-SIZE             \ spaces per level (default 2)
VARIABLE _YB-NEED-NL                 \ need newline before next item?
VARIABLE _YB-IN-FLOW                 \ in a flow context?

: YAML-BUILD-RESET  ( -- )
    0 _YB-LEVEL !
    2 _YB-INDENT-SIZE !
    0 _YB-NEED-NL !
    0 _YB-IN-FLOW !
    ' _YAML-DEFAULT-EMIT YAML-EMIT-XT !
    ' _YAML-DEFAULT-TYPE YAML-TYPE-XT ! ;

YAML-BUILD-RESET

: YAML-SET-INDENT  ( n -- )
    _YB-INDENT-SIZE ! ;

: _YB-WRITE-INDENT  ( -- )
    _YB-LEVEL @ _YB-INDENT-SIZE @ *
    0 ?DO 32 YAML-EMIT LOOP ;

: _YB-NL  ( -- )
    10 YAML-EMIT ;

: _YB-ENSURE-NL  ( -- )
    _YB-NEED-NL @ IF
        _YB-NL  0 _YB-NEED-NL !
    THEN ;

\ ── Document markers ─────────────────────────────────────────────────

: YAML-DOC-START  ( -- )
    S" ---" YAML-TYPE _YB-NL ;

: YAML-DOC-END    ( -- )
    S" ..." YAML-TYPE _YB-NL ;

\ ── Block-style key-value ────────────────────────────────────────────

: YAML-KEY:  ( addr len -- )
    _YB-ENSURE-NL
    _YB-WRITE-INDENT
    YAML-TYPE
    S" : " YAML-TYPE ;

\ YAML-MAP-OPEN ( addr len -- )
\   Emit "key:" and start a new indented block.
: YAML-MAP-OPEN  ( addr len -- )
    _YB-ENSURE-NL
    _YB-WRITE-INDENT
    YAML-TYPE
    58 YAML-EMIT _YB-NL              \ ":"
    1 _YB-LEVEL +! ;

\ YAML-MAP-CLOSE ( -- )
\   End an indented mapping block.
: YAML-MAP-CLOSE  ( -- )
    _YB-LEVEL @ 0> IF -1 _YB-LEVEL +! THEN ;

\ ── Block-style sequence ─────────────────────────────────────────────

: YAML-SEQ-ITEM  ( -- )
    _YB-ENSURE-NL
    _YB-WRITE-INDENT
    S" - " YAML-TYPE ;

\ ── Scalar values ────────────────────────────────────────────────────

: YAML-STR  ( addr len -- )
    YAML-TYPE
    -1 _YB-NEED-NL ! ;

: YAML-DQ-STR  ( addr len -- )
    34 YAML-EMIT
    YAML-TYPE
    34 YAML-EMIT
    -1 _YB-NEED-NL ! ;

\ YAML-ESTR ( addr len -- )
\   Emit a double-quoted string with escaping.
: YAML-ESTR  ( addr len -- )
    34 YAML-EMIT
    0 DO
        DUP I + C@
        DUP 34 = IF DROP 92 YAML-EMIT 34 YAML-EMIT     \ \"
        ELSE DUP 92 = IF DROP 92 YAML-EMIT 92 YAML-EMIT \ \\
        ELSE DUP 10 = IF DROP 92 YAML-EMIT 110 YAML-EMIT \ \n
        ELSE DUP 13 = IF DROP 92 YAML-EMIT 114 YAML-EMIT \ \r
        ELSE DUP  9 = IF DROP 92 YAML-EMIT 116 YAML-EMIT \ \t
        ELSE DUP  0 = IF DROP 92 YAML-EMIT 48 YAML-EMIT  \ \0
        ELSE
            YAML-EMIT
        THEN THEN THEN THEN THEN THEN
    LOOP DROP
    34 YAML-EMIT
    -1 _YB-NEED-NL ! ;

: YAML-INT  ( n -- )
    DUP 0< IF
        45 YAML-EMIT NEGATE
    THEN
    DUP 0= IF DROP 48 YAML-EMIT -1 _YB-NEED-NL ! EXIT THEN
    \ Build digits in temporary location
    0 >R                             \ digit count on rstack
    BEGIN DUP 0> WHILE
        10 /MOD SWAP 48 + >R
        1 >R
    REPEAT
    DROP
    \ Now emit digits from rstack: count/char pairs
    BEGIN R> DUP 0> WHILE
        DROP R> YAML-EMIT
    REPEAT DROP
    -1 _YB-NEED-NL ! ;

: YAML-TRUE   ( -- )  S" true" YAML-TYPE  -1 _YB-NEED-NL ! ;
: YAML-FALSE  ( -- )  S" false" YAML-TYPE  -1 _YB-NEED-NL ! ;
: YAML-NULL   ( -- )  S" null" YAML-TYPE  -1 _YB-NEED-NL ! ;
: YAML-BOOL   ( flag -- )  IF YAML-TRUE ELSE YAML-FALSE THEN ;

\ ── Number output (reusable) ─────────────────────────────────────────

VARIABLE _YN-NEG
CREATE _YN-BUF 24 ALLOT

: YAML-NUM  ( n -- )
    DUP 0< IF
        45 YAML-EMIT NEGATE
    THEN
    DUP 0= IF
        DROP 48 YAML-EMIT
        -1 _YB-NEED-NL ! EXIT
    THEN
    _YN-BUF 24 + SWAP
    BEGIN DUP 0> WHILE
        10 /MOD SWAP 48 + ROT 1- DUP >R C! R> SWAP
    REPEAT
    DROP
    _YN-BUF 24 + OVER - YAML-TYPE
    -1 _YB-NEED-NL ! ;

\ ── Convenience key-value words ──────────────────────────────────────

: YAML-KV-STR  ( kaddr klen vaddr vlen -- )
    2SWAP YAML-KEY: YAML-STR ;

: YAML-KV-DQ   ( kaddr klen vaddr vlen -- )
    2SWAP YAML-KEY: YAML-DQ-STR ;

: YAML-KV-ESTR ( kaddr klen vaddr vlen -- )
    2SWAP YAML-KEY: YAML-ESTR ;

: YAML-KV-INT  ( kaddr klen n -- )
    >R YAML-KEY: R> YAML-NUM ;

: YAML-KV-BOOL ( kaddr klen flag -- )
    >R YAML-KEY: R> YAML-BOOL ;

: YAML-KV-NULL ( kaddr klen -- )
    YAML-KEY: YAML-NULL ;

\ ── Flow-style output ────────────────────────────────────────────────

VARIABLE _YFC-NEED

: YAML-F{  ( -- )
    123 YAML-EMIT  0 _YFC-NEED ! ;

: YAML-F}  ( -- )
    125 YAML-EMIT  -1 _YB-NEED-NL ! ;

: YAML-F[  ( -- )
    91 YAML-EMIT  0 _YFC-NEED ! ;

: YAML-F]  ( -- )
    93 YAML-EMIT  -1 _YB-NEED-NL ! ;

: _YFC-SEP  ( -- )
    _YFC-NEED @ IF S" , " YAML-TYPE THEN
    -1 _YFC-NEED ! ;

: YAML-FKEY:  ( addr len -- )
    _YFC-SEP
    YAML-TYPE
    S" : " YAML-TYPE
    0 _YFC-NEED ! ;

: YAML-FVAL-STR  ( addr len -- )
    _YFC-SEP  YAML-TYPE ;

: YAML-FVAL-DQ   ( addr len -- )
    _YFC-SEP
    34 YAML-EMIT YAML-TYPE 34 YAML-EMIT ;

: YAML-FVAL-INT  ( n -- )
    _YFC-SEP  YAML-NUM ;

: YAML-FVAL-BOOL ( flag -- )
    _YFC-SEP  IF YAML-TRUE ELSE YAML-FALSE THEN ;

: YAML-FVAL-NULL ( -- )
    _YFC-SEP  YAML-NULL ;

\ =====================================================================
\  Layer 11 — Multi-Document Support
\ =====================================================================

\ YAML-NEXT-DOC ( addr len -- addr' len' flag )
\   Advance to the next document in a multi-document stream.
\   Skips past '...' or '---' document boundaries.
\   flag = -1 if another document found, 0 at end.
: YAML-NEXT-DOC  ( addr len -- addr' len' flag )
    BEGIN
        DUP 0> WHILE
        2DUP _YAML-3DOT? IF
            3 /STRING YAML-SKIP-LINE
            \ After '...' there might be '---' or end
            YAML-SKIP-NL
            DUP 0> 0= IF 0 EXIT THEN
            2DUP _YAML-3DASH? IF
                3 /STRING YAML-SKIP-WS YAML-SKIP-COMMENT YAML-SKIP-EOL
                YAML-SKIP-NL
            THEN
            DUP 0> IF -1 ELSE 0 THEN EXIT
        THEN
        2DUP _YAML-3DASH? IF
            3 /STRING YAML-SKIP-WS YAML-SKIP-COMMENT YAML-SKIP-EOL
            YAML-SKIP-NL
            DUP 0> IF -1 ELSE 0 THEN EXIT
        THEN
        YAML-SKIP-LINE
    REPEAT
    0 ;

