\ =================================================================
\  search.f — Text Search for Gap Buffer
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SRCH- / _SRCH-
\  Depends on: text/gap-buf.f, utils/string.f
\
\  Byte-pattern matching over gap-buffer logical content.
\  Case-sensitive and case-insensitive variants.
\  Forward and reverse search.
\
\  Replace is not in this module — the caller does:
\    match GB-MOVE!  ndl-u GB-DEL 2DROP  repl-a repl-u GB-INS
\  and records undo entries as needed.
\
\  Public API:
\    SRCH-FIND    ( pos ndl-a ndl-u gb -- match | -1 )
\    SRCH-IFIND   ( pos ndl-a ndl-u gb -- match | -1 )
\    SRCH-RFIND   ( pos ndl-a ndl-u gb -- match | -1 )
\    SRCH-IRFIND  ( pos ndl-a ndl-u gb -- match | -1 )
\    SRCH-COUNT   ( ndl-a ndl-u gb -- n )
\    SRCH-ICOUNT  ( ndl-a ndl-u gb -- n )
\ =================================================================

PROVIDED akashic-search

REQUIRE gap-buf.f
REQUIRE ../utils/string.f

\ =====================================================================
\  S1 -- Module Temporaries
\ =====================================================================

VARIABLE _SRCH-GB       \ current gap buffer
VARIABLE _SRCH-NA       \ needle address
VARIABLE _SRCH-NU       \ needle length

\ =====================================================================
\  S2 -- Match Helpers  (uses _STR-LC from string.f)
\ =====================================================================

\ _SRCH-MATCH? ( pos -- flag )
\   Case-sensitive: does needle match at logical position pos?
: _SRCH-MATCH?  ( pos -- flag )
    _SRCH-NU @ 0 ?DO
        DUP I +  _SRCH-GB @ GB-BYTE@
        _SRCH-NA @ I + C@
        <> IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ _SRCH-IMATCH? ( pos -- flag )
\   Case-insensitive: does needle match at logical position pos?
: _SRCH-IMATCH?  ( pos -- flag )
    _SRCH-NU @ 0 ?DO
        DUP I +  _SRCH-GB @ GB-BYTE@  _STR-LC
        _SRCH-NA @ I + C@             _STR-LC
        <> IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ =====================================================================
\  S3 -- Forward Search
\ =====================================================================

\ _SRCH-SETUP ( pos ndl-a ndl-u gb -- pos | exits with -1 )
\   Common setup: save params, validate, return start position.
: _SRCH-SETUP  ( pos ndl-a ndl-u gb -- pos )
    _SRCH-GB !  _SRCH-NU !  _SRCH-NA ! ;

\ SRCH-FIND ( pos ndl-a ndl-u gb -- match | -1 )
\   Find first occurrence of needle at or after pos.
: SRCH-FIND  ( pos ndl-a ndl-u gb -- match | -1 )
    _SRCH-SETUP
    _SRCH-NU @ 0= IF DROP -1 EXIT THEN
    0 MAX                                     ( pos )
    _SRCH-GB @ GB-LEN _SRCH-NU @ -  1+       ( pos limit )
    OVER <= IF DROP -1 EXIT THEN
    _SRCH-GB @ GB-LEN _SRCH-NU @ -  1+
    SWAP ?DO
        I _SRCH-MATCH? IF I UNLOOP EXIT THEN
    LOOP
    -1 ;

\ SRCH-IFIND ( pos ndl-a ndl-u gb -- match | -1 )
\   Case-insensitive forward search.
: SRCH-IFIND  ( pos ndl-a ndl-u gb -- match | -1 )
    _SRCH-SETUP
    _SRCH-NU @ 0= IF DROP -1 EXIT THEN
    0 MAX
    _SRCH-GB @ GB-LEN _SRCH-NU @ -  1+
    OVER <= IF DROP -1 EXIT THEN
    _SRCH-GB @ GB-LEN _SRCH-NU @ -  1+
    SWAP ?DO
        I _SRCH-IMATCH? IF I UNLOOP EXIT THEN
    LOOP
    -1 ;

\ =====================================================================
\  S4 -- Reverse Search
\ =====================================================================

\ SRCH-RFIND ( pos ndl-a ndl-u gb -- match | -1 )
\   Find last occurrence of needle at or before pos.
: SRCH-RFIND  ( pos ndl-a ndl-u gb -- match | -1 )
    _SRCH-SETUP
    _SRCH-NU @ 0= IF DROP -1 EXIT THEN
    \ Clamp pos to max valid start
    _SRCH-GB @ GB-LEN _SRCH-NU @ -  MIN      ( pos )
    BEGIN
        DUP 0 >= WHILE
        DUP _SRCH-MATCH? IF EXIT THEN
        1-
    REPEAT ;                                   \ -1 (from 0 - 1)

\ SRCH-IRFIND ( pos ndl-a ndl-u gb -- match | -1 )
\   Case-insensitive reverse search.
: SRCH-IRFIND  ( pos ndl-a ndl-u gb -- match | -1 )
    _SRCH-SETUP
    _SRCH-NU @ 0= IF DROP -1 EXIT THEN
    _SRCH-GB @ GB-LEN _SRCH-NU @ -  MIN
    BEGIN
        DUP 0 >= WHILE
        DUP _SRCH-IMATCH? IF EXIT THEN
        1-
    REPEAT ;

\ =====================================================================
\  S5 -- Count
\ =====================================================================

\ SRCH-COUNT ( ndl-a ndl-u gb -- n )
\   Count non-overlapping occurrences (forward, case-sensitive).
: SRCH-COUNT  ( ndl-a ndl-u gb -- n )
    _SRCH-SETUP DROP                           \ pos not needed
    _SRCH-NU @ 0= IF 0 EXIT THEN
    0  0                                       ( count pos )
    BEGIN
        DUP  _SRCH-GB @ GB-LEN _SRCH-NU @ -  <=
    WHILE
        DUP _SRCH-MATCH? IF
            SWAP 1+ SWAP
            _SRCH-NU @ +                       \ skip past match
        ELSE
            1+
        THEN
    REPEAT
    DROP ;

\ SRCH-ICOUNT ( ndl-a ndl-u gb -- n )
\   Count non-overlapping occurrences (case-insensitive).
: SRCH-ICOUNT  ( ndl-a ndl-u gb -- n )
    _SRCH-SETUP DROP
    _SRCH-NU @ 0= IF 0 EXIT THEN
    0  0
    BEGIN
        DUP  _SRCH-GB @ GB-LEN _SRCH-NU @ -  <=
    WHILE
        DUP _SRCH-IMATCH? IF
            SWAP 1+ SWAP
            _SRCH-NU @ +
        ELSE
            1+
        THEN
    REPEAT
    DROP ;

\ =====================================================================
\  S6 -- Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _srch-guard

' SRCH-FIND    CONSTANT _srch-find-xt
' SRCH-IFIND   CONSTANT _srch-ifind-xt
' SRCH-RFIND   CONSTANT _srch-rfind-xt
' SRCH-IRFIND  CONSTANT _srch-irfind-xt
' SRCH-COUNT   CONSTANT _srch-cnt-xt
' SRCH-ICOUNT  CONSTANT _srch-icnt-xt

: SRCH-FIND    _srch-find-xt   _srch-guard WITH-GUARD ;
: SRCH-IFIND   _srch-ifind-xt  _srch-guard WITH-GUARD ;
: SRCH-RFIND   _srch-rfind-xt  _srch-guard WITH-GUARD ;
: SRCH-IRFIND  _srch-irfind-xt _srch-guard WITH-GUARD ;
: SRCH-COUNT   _srch-cnt-xt    _srch-guard WITH-GUARD ;
: SRCH-ICOUNT  _srch-icnt-xt   _srch-guard WITH-GUARD ;
[THEN] [THEN]
