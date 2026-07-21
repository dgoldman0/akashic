\ =====================================================================
\  daybook.f - Daily planner, tasks, events, and notes
\ =====================================================================
\  Durable data is stored in /daybook.md using a small Markdown dialect:
\    - [ ] 2026-07-10 | unfinished task
\    - [x] 2026-07-10 | finished task
\    - 2026-07-10 09:30 | timed event
\    > 2026-07-10 | note
\
\  Entry: DAYBOOK-ENTRY ( desc -- )  for Desk
\         DAYBOOK-RUN   ( -- )       standalone
\ =====================================================================

PROVIDED akashic-tui-daybook

REQUIRE ../../widgets/prompt.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../../utils/fs/vfs.f
REQUIRE ../../../utils/fs/vfs-access.f
REQUIRE ../../../utils/fs/vfs-replace.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../utils/datetime.f
REQUIRE ../../../text/utf8.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/capability.f
REQUIRE ../../../interop/endpoint.f
REQUIRE ../../../interop/intent.f
REQUIRE ../../../interop/lens-binding.f
REQUIRE ../../../interop/resource.f
REQUIRE ../../../interop/shared-document-lens.f

86400 CONSTANT _DB-SECONDS-DAY
96    CONSTANT _DB-MAX-ENTRIES
120   CONSTANT _DB-TEXT-CAP
160   CONSTANT _DB-ENTRY-SZ
32768 CONSTANT _DB-IO-CAP
256   CONSTANT _DB-PROMPT-CAP

1 CONSTANT _DB-K-TASK
2 CONSTANT _DB-K-EVENT
3 CONSTANT _DB-K-NOTE

0 CONSTANT _DB-PRM-NONE
1 CONSTANT _DB-PRM-TASK
2 CONSTANT _DB-PRM-EVENT
3 CONSTANT _DB-PRM-NOTE
4 CONSTANT _DB-PRM-DISCARD-CLOSE
5 CONSTANT _DB-PRM-DISCARD-RELOAD

0 CONSTANT _DB-L-S-OK
1 CONSTANT _DB-L-S-MISSING
2 CONSTANT _DB-L-S-IO
3 CONSTANT _DB-L-S-TOO-LARGE
4 CONSTANT _DB-L-S-INVALID
5 CONSTANT _DB-L-S-CAPACITY
6 CONSTANT _DB-L-S-TEXT
7 CONSTANT _DB-L-S-RECOVERY
8 CONSTANT _DB-L-S-STALE
9 CONSTANT _DB-L-S-SHARED

1001 CONSTANT _DB-W-S-SHARED

 0 CONSTANT _DB-E-KIND
 8 CONSTANT _DB-E-DONE
16 CONSTANT _DB-E-DATE
24 CONSTANT _DB-E-MINUTE
32 CONSTANT _DB-E-TEXT-U
40 CONSTANT _DB-E-TEXT

VARIABLE _DB-CURRENT-STATE
0 _DB-CURRENT-STATE !
VARIABLE _DB-CURRENT-INSTANCE
0 _DB-CURRENT-INSTANCE !
CMP-LAYOUT-BEGIN

_DB-CURRENT-STATE _DB-MAX-ENTRIES _DB-ENTRY-SZ * CMP-FIELD: _DB-ENTRIES
_DB-CURRENT-STATE CMP-CELL: _DB-COUNT
_DB-CURRENT-STATE CMP-CELL: _DB-SELECTED-DATE
_DB-CURRENT-STATE CMP-CELL: _DB-SELECTED
_DB-CURRENT-STATE CMP-CELL: _DB-DIRTY
_DB-CURRENT-STATE CMP-CELL: _DB-VIEW-DIRTY
_DB-CURRENT-STATE CMP-CELL: _DB-VFS
_DB-CURRENT-STATE VFA-SCOPE-SIZE CMP-FIELD: _DB-LOAD-SCOPE
_DB-CURRENT-STATE VREPL-SIZE CMP-FIELD: _DB-REPLACE
_DB-CURRENT-STATE CMP-CELL: _DB-DISCARD-ARMED
_DB-CURRENT-STATE CMP-CELL: _DB-SOURCE-BLOCKED
_DB-CURRENT-STATE CMP-CELL: _DB-SAVE-STALE

\ A Daybook instance is either a standalone VFS client or a lens onto the
\ activation-local semantic owner.  Service pointers are borrowed; identity,
\ reference, and binding state are copied into the instance allocation.
_DB-CURRENT-STATE SDLENS-SIZE CMP-FIELD: _DB-SHARED-LENS
_DB-CURRENT-STATE CMP-CELL: _DB-CAPTURE-HOP

_DB-CURRENT-STATE CMP-CELL: _DB-E-BODY
_DB-CURRENT-STATE CMP-CELL: _DB-E-SBAR
_DB-CURRENT-STATE CMP-CELL: _DB-E-SBAR-DATE
_DB-CURRENT-STATE CMP-CELL: _DB-E-SBAR-STATE

_DB-CURRENT-STATE 40 CMP-FIELD: _DB-PANEL
_DB-CURRENT-STATE CMP-CELL: _DB-PANEL-RGN

_DB-CURRENT-STATE CMP-CELL: _DB-PROMPT
_DB-CURRENT-STATE CMP-CELL: _DB-PROMPT-RGN
_DB-CURRENT-STATE CMP-CELL: _DB-PROMPT-MODE
_DB-CURRENT-STATE _DB-PROMPT-CAP CMP-FIELD: _DB-PROMPT-BUF

_DB-CURRENT-STATE _DB-IO-CAP CMP-FIELD: _DB-IO-BUF
_DB-CURRENT-STATE CMP-CELL: _DB-IO-U
_DB-CURRENT-STATE 16 CMP-FIELD: _DB-DATE-BUF
_DB-CURRENT-STATE 96 CMP-FIELD: _DB-STATUS-BUF
_DB-CURRENT-STATE CMP-CELL: _DB-STATUS-U

CMP-LAYOUT-SIZE CONSTANT _DB-STATE-SIZE

\ Private compatibility accessors keep the Daybook model code readable while
\ the shared discovery, exact binding, and request lifecycle live in SDLENS.
: _DB-RESOURCE-MODE       ( -- a ) _DB-SHARED-LENS SDLENS.MODE ;
: _DB-SHARED-CONTEXT      ( -- a ) _DB-SHARED-LENS SDLENS.CONTEXT ;
: _DB-SHARED-BUS          ( -- a ) _DB-SHARED-LENS SDLENS.BUS ;
: _DB-SHARED-REF          ( -- ref ) _DB-SHARED-LENS SDLENS.REF ;
: _DB-SHARED-BIND         ( -- bind ) _DB-SHARED-LENS SDLENS.BIND ;
: _DB-SHARED-SNAPSHOT-CAP ( -- a ) _DB-SHARED-LENS SDLENS.SNAPSHOT-CAP ;
: _DB-SHARED-REPLACE-CAP  ( -- a ) _DB-SHARED-LENS SDLENS.REPLACE-CAP ;
: _DB-SHARED-REQUEST      ( -- a ) _DB-SHARED-LENS SDLENS.REQUEST ;

: _DB-ACTIVATE  ( instance -- )
    DUP _DB-CURRENT-INSTANCE !
    CINST-STATE _DB-CURRENT-STATE ! ;

: _DB-SHARED-BLOCK!  ( -- )
    SDLENS-M-BLOCKED _DB-RESOURCE-MODE !
    -1 _DB-SOURCE-BLOCKED ! ;

: _DB-SHARED-REFRESH  ( -- status )
    _DB-SHARED-LENS SDLENS-REFRESH ;

: _DB-SHARED-INIT  ( -- )
    0 _DB-CAPTURE-HOP !
    S" org.akashic.resource.daybook" _DB-CURRENT-INSTANCE @
        _DB-SHARED-LENS SDLENS-INIT
    _DB-RESOURCE-MODE @ SDLENS-M-BLOCKED = IF
        -1 _DB-SOURCE-BLOCKED !
    ELSE
        0 _DB-SOURCE-BLOCKED !
    THEN ;

: _DB-SHARED-FINI  ( -- )
    0 _DB-CAPTURE-HOP !
    _DB-SHARED-LENS SDLENS-FINI ;

: _DB-ENTRY  ( index -- addr )
    _DB-ENTRY-SZ * _DB-ENTRIES + ;

: _DB-TODAY  ( -- epoch )
    DT-NOW-S _DB-SECONDS-DAY / _DB-SECONDS-DAY * ;

: _DB-CLEAR  ( -- )
    _DB-ENTRIES _DB-MAX-ENTRIES _DB-ENTRY-SZ * 0 FILL
    0 _DB-COUNT !
    0 _DB-SELECTED ! ;

VARIABLE _DB-A-KIND
VARIABLE _DB-A-DONE
VARIABLE _DB-A-DATE
VARIABLE _DB-A-MINUTE
VARIABLE _DB-A-TEXT-A
VARIABLE _DB-A-TEXT-U
VARIABLE _DB-A-N
VARIABLE _DB-A-ENTRY

VARIABLE _DB-TV-A
VARIABLE _DB-TV-U
VARIABLE _DB-TV-OK

: _DB-TEXT-VALID?  ( addr len -- flag )
    _DB-TV-U ! _DB-TV-A !
    _DB-TV-U @ 0< _DB-TV-U @ _DB-TEXT-CAP > OR IF 0 EXIT THEN
    _DB-TV-U @ 0> _DB-TV-A @ 0= AND IF 0 EXIT THEN
    _DB-TV-A @ _DB-TV-U @ UTF8-VALID? 0= IF 0 EXIT THEN
    -1 _DB-TV-OK !
    _DB-TV-U @ 0 ?DO
        _DB-TV-A @ I + C@ DUP 10 = SWAP 13 = OR IF
            0 _DB-TV-OK !
        THEN
    LOOP
    _DB-TV-OK @ ;

: _DB-ADD  ( kind done date minute text-a text-u -- index | -1 )
    _DB-A-TEXT-U ! _DB-A-TEXT-A ! _DB-A-MINUTE !
    _DB-A-DATE ! _DB-A-DONE ! _DB-A-KIND !
    _DB-COUNT @ _DB-MAX-ENTRIES >= IF -1 EXIT THEN
    _DB-A-TEXT-A @ _DB-A-TEXT-U @ _DB-TEXT-VALID? 0= IF -1 EXIT THEN
    _DB-COUNT @ DUP _DB-ENTRY _DB-A-ENTRY !
    _DB-A-KIND @   _DB-A-ENTRY @ _DB-E-KIND + !
    _DB-A-DONE @   _DB-A-ENTRY @ _DB-E-DONE + !
    _DB-A-DATE @   _DB-A-ENTRY @ _DB-E-DATE + !
    _DB-A-MINUTE @ _DB-A-ENTRY @ _DB-E-MINUTE + !
    _DB-A-TEXT-U @ _DB-A-N !
    _DB-A-N @ _DB-A-ENTRY @ _DB-E-TEXT-U + !
    _DB-A-TEXT-A @ _DB-A-ENTRY @ _DB-E-TEXT + _DB-A-N @ CMOVE
    1 _DB-COUNT +! ;

VARIABLE _DB-N-A
VARIABLE _DB-N-U
VARIABLE _DB-N-ACC
VARIABLE _DB-N-OK

: _DB-FIXED-NUM  ( addr digits -- n flag )
    _DB-N-U ! _DB-N-A ! 0 _DB-N-ACC ! -1 _DB-N-OK !
    _DB-N-U @ 0 ?DO
        _DB-N-A @ I + C@
        DUP [CHAR] 0 < OVER [CHAR] 9 > OR IF
            DROP 0 _DB-N-OK !
        ELSE
            [CHAR] 0 - _DB-N-ACC @ 10 * + _DB-N-ACC !
        THEN
    LOOP
    _DB-N-ACC @ _DB-N-OK @ ;

VARIABLE _DB-P-A
VARIABLE _DB-P-U
VARIABLE _DB-P-Y
VARIABLE _DB-P-M
VARIABLE _DB-P-D
VARIABLE _DB-P-H
VARIABLE _DB-P-MIN

: _DB-PARSE-DATE  ( addr len -- epoch flag )
    _DB-P-U ! _DB-P-A !
    _DB-P-U @ 10 < IF 0 0 EXIT THEN
    _DB-P-A @ 4 + C@ [CHAR] - <> IF 0 0 EXIT THEN
    _DB-P-A @ 7 + C@ [CHAR] - <> IF 0 0 EXIT THEN
    _DB-P-A @ 4 _DB-FIXED-NUM 0= IF DROP 0 0 EXIT THEN _DB-P-Y !
    _DB-P-A @ 5 + 2 _DB-FIXED-NUM 0= IF DROP 0 0 EXIT THEN _DB-P-M !
    _DB-P-A @ 8 + 2 _DB-FIXED-NUM 0= IF DROP 0 0 EXIT THEN _DB-P-D !
    _DB-P-Y @ 1970 < IF 0 0 EXIT THEN
    _DB-P-M @ 1 < _DB-P-M @ 12 > OR IF 0 0 EXIT THEN
    _DB-P-D @ 1 < IF 0 0 EXIT THEN
    _DB-P-D @ _DB-P-M @ _DB-P-Y @ _DT-DIM@ > IF 0 0 EXIT THEN
    _DB-P-Y @ _DB-P-M @ _DB-P-D @ DT-YMD>EPOCH -1 ;

: _DB-PARSE-TIME  ( addr len -- minute flag )
    _DB-P-U ! _DB-P-A !
    _DB-P-U @ 5 < IF 0 0 EXIT THEN
    _DB-P-A @ 2 + C@ [CHAR] : <> IF 0 0 EXIT THEN
    _DB-P-A @ 2 _DB-FIXED-NUM 0= IF DROP 0 0 EXIT THEN _DB-P-H !
    _DB-P-A @ 3 + 2 _DB-FIXED-NUM 0= IF DROP 0 0 EXIT THEN _DB-P-MIN !
    _DB-P-H @ 23 > _DB-P-MIN @ 59 > OR IF 0 0 EXIT THEN
    _DB-P-H @ 60 * _DB-P-MIN @ + -1 ;

VARIABLE _DB-LINE-A
VARIABLE _DB-LINE-U
VARIABLE _DB-LINE-DATE
VARIABLE _DB-LINE-TIME
VARIABLE _DB-LINE-DONE
VARIABLE _DB-LINE-KIND
VARIABLE _DB-LINE-TEXT-A
VARIABLE _DB-LINE-TEXT-U
VARIABLE _DB-PARSE-ERROR
VARIABLE _DB-PARSE-COUNT
VARIABLE _DB-PARSE-HEADER
VARIABLE _DB-PARSE-COMMIT

: _DB-LINE-TEXT!  ( addr len -- flag )
    2DUP _DB-TEXT-VALID? 0= IF
        2DROP _DB-L-S-TEXT _DB-PARSE-ERROR ! 0 EXIT
    THEN
    _DB-LINE-TEXT-U ! _DB-LINE-TEXT-A ! -1 ;

: _DB-PARSE-TASK?  ( -- flag )
    _DB-LINE-U @ 19 < IF 0 EXIT THEN
    _DB-LINE-A @ C@ [CHAR] - <> IF 0 EXIT THEN
    _DB-LINE-A @ 1+ C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 2 + C@ [CHAR] [ <> IF 0 EXIT THEN
    _DB-LINE-A @ 4 + C@ [CHAR] ] <> IF 0 EXIT THEN
    _DB-LINE-A @ 5 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 16 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 17 + C@ [CHAR] | <> IF 0 EXIT THEN
    _DB-LINE-A @ 18 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 3 + C@ DUP [CHAR] x = IF
        DROP -1 _DB-LINE-DONE !
    ELSE BL <> IF 0 EXIT THEN 0 _DB-LINE-DONE ! THEN
    _DB-LINE-A @ 6 + 10 _DB-PARSE-DATE
    0= IF DROP 0 EXIT THEN _DB-LINE-DATE !
    _DB-LINE-A @ 19 + _DB-LINE-U @ 19 - _DB-LINE-TEXT! 0= IF
        0 EXIT
    THEN
    _DB-K-TASK _DB-LINE-KIND ! -1 _DB-LINE-TIME !
    -1 ;

: _DB-PARSE-EVENT?  ( -- flag )
    _DB-LINE-U @ 21 < IF 0 EXIT THEN
    _DB-LINE-A @ C@ [CHAR] - <> IF 0 EXIT THEN
    _DB-LINE-A @ 1+ C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 12 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 18 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 19 + C@ [CHAR] | <> IF 0 EXIT THEN
    _DB-LINE-A @ 20 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 2 + 10 _DB-PARSE-DATE
    0= IF DROP 0 EXIT THEN _DB-LINE-DATE !
    _DB-LINE-A @ 13 + 5 _DB-PARSE-TIME
    0= IF DROP 0 EXIT THEN _DB-LINE-TIME !
    _DB-LINE-A @ 21 + _DB-LINE-U @ 21 - _DB-LINE-TEXT! 0= IF
        0 EXIT
    THEN
    _DB-K-EVENT _DB-LINE-KIND ! 0 _DB-LINE-DONE !
    -1 ;

: _DB-PARSE-NOTE?  ( -- flag )
    _DB-LINE-U @ 15 < IF 0 EXIT THEN
    _DB-LINE-A @ C@ [CHAR] > <> IF 0 EXIT THEN
    _DB-LINE-A @ 1+ C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 12 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 13 + C@ [CHAR] | <> IF 0 EXIT THEN
    _DB-LINE-A @ 14 + C@ BL <> IF 0 EXIT THEN
    _DB-LINE-A @ 2 + 10 _DB-PARSE-DATE
    0= IF DROP 0 EXIT THEN _DB-LINE-DATE !
    _DB-LINE-A @ 15 + _DB-LINE-U @ 15 - _DB-LINE-TEXT! 0= IF
        0 EXIT
    THEN
    _DB-K-NOTE _DB-LINE-KIND ! 0 _DB-LINE-DONE ! -1 _DB-LINE-TIME !
    -1 ;

: _DB-ACCEPT-LINE  ( -- flag )
    _DB-PARSE-COUNT @ _DB-MAX-ENTRIES >= IF
        _DB-L-S-CAPACITY _DB-PARSE-ERROR ! 0 EXIT
    THEN
    _DB-PARSE-COMMIT @ IF
        _DB-LINE-KIND @ _DB-LINE-DONE @ _DB-LINE-DATE @
        _DB-LINE-TIME @ _DB-LINE-TEXT-A @ _DB-LINE-TEXT-U @ _DB-ADD
        0< IF _DB-L-S-INVALID _DB-PARSE-ERROR ! 0 EXIT THEN
    THEN
    1 _DB-PARSE-COUNT +! -1 ;

: _DB-PARSE-LINE  ( addr len -- flag )
    _DB-LINE-U ! _DB-LINE-A !
    _DB-LINE-U @ 0> IF
        _DB-LINE-A @ _DB-LINE-U @ + 1- C@ 13 = IF -1 _DB-LINE-U +! THEN
    THEN
    _DB-LINE-U @ 0= IF -1 EXIT THEN
    _DB-LINE-A @ _DB-LINE-U @ S" # Daybook" STR-STR= IF
        _DB-PARSE-HEADER @ _DB-PARSE-COUNT @ 0<> OR IF
            _DB-L-S-INVALID _DB-PARSE-ERROR ! 0 EXIT
        THEN
        -1 _DB-PARSE-HEADER ! -1 EXIT
    THEN
    _DB-PARSE-HEADER @ 0= IF
        _DB-L-S-INVALID _DB-PARSE-ERROR ! 0 EXIT
    THEN
    _DB-PARSE-TASK? IF _DB-ACCEPT-LINE EXIT THEN
    _DB-PARSE-EVENT? IF _DB-ACCEPT-LINE EXIT THEN
    _DB-PARSE-NOTE? IF _DB-ACCEPT-LINE EXIT THEN
    _DB-PARSE-ERROR @ 0= IF _DB-L-S-INVALID _DB-PARSE-ERROR ! THEN
    0 ;

VARIABLE _DB-LOAD-POS
VARIABLE _DB-LOAD-START

: _DB-SCAN-FILE  ( commit? -- status )
    _DB-PARSE-COMMIT !
    0 _DB-PARSE-ERROR ! 0 _DB-PARSE-COUNT ! 0 _DB-PARSE-HEADER !
    _DB-IO-BUF _DB-IO-U @ UTF8-VALID? 0= IF _DB-L-S-INVALID EXIT THEN
    0 _DB-LOAD-POS ! 0 _DB-LOAD-START !
    BEGIN _DB-LOAD-POS @ _DB-IO-U @ < WHILE
        _DB-IO-BUF _DB-LOAD-POS @ + C@ 10 = IF
            _DB-IO-BUF _DB-LOAD-START @ +
            _DB-LOAD-POS @ _DB-LOAD-START @ - _DB-PARSE-LINE 0= IF
                _DB-PARSE-ERROR @ EXIT
            THEN
            _DB-LOAD-POS @ 1+ _DB-LOAD-START !
        THEN
        1 _DB-LOAD-POS +!
    REPEAT
    _DB-LOAD-START @ _DB-IO-U @ < IF
        _DB-IO-BUF _DB-LOAD-START @ +
        _DB-IO-U @ _DB-LOAD-START @ - _DB-PARSE-LINE 0= IF
            _DB-PARSE-ERROR @ EXIT
        THEN
    THEN
    _DB-PARSE-HEADER @ 0= IF _DB-L-S-INVALID EXIT THEN
    _DB-L-S-OK ;

: _DB-PARSE-FILE  ( -- status )
    0 _DB-SCAN-FILE DUP IF EXIT THEN DROP
    _DB-CLEAR
    -1 _DB-SCAN-FILE ;

VARIABLE _DB-LOAD-STATUS

: _DB-READ-FILE-BODY  ( -- )
    S" /daybook.md" VFS-FF-READ _DB-LOAD-SCOPE VFA-SCOPE-OPEN?
    DUP IF
        VFS-IOR-REASON VFS-R-NOENT = IF
            _DB-L-S-MISSING
        ELSE
            _DB-L-S-IO
        THEN
        _DB-LOAD-STATUS ! DROP EXIT
    THEN
    DROP
    _DB-IO-BUF _DB-IO-CAP ROT VFA-READ-FILE?
    DUP IF
        VFS-IOR-REASON VFS-R-OVERFLOW = IF
            _DB-L-S-TOO-LARGE
        ELSE
            _DB-L-S-IO
        THEN
        _DB-LOAD-STATUS ! DROP EXIT
    THEN
    DROP _DB-IO-U !
    _DB-L-S-OK _DB-LOAD-STATUS ! ;

: _DB-READ-FILE  ( -- status )
    _DB-L-S-IO _DB-LOAD-STATUS !
    ['] _DB-READ-FILE-BODY _DB-LOAD-SCOPE VFA-SCOPE-CALL
    OR IF _DB-L-S-IO ELSE _DB-LOAD-STATUS @ THEN ;

: _DB-RECOVER  ( -- status )
    _DB-REPLACE VREPL-RECOVER
    DUP VREPL-S-OK = IF DROP _DB-L-S-OK EXIT THEN
    DUP VREPL-S-ROLLED-BACK = IF DROP _DB-L-S-OK EXIT THEN
    VREPL-S-COMMITTED-CLEANUP = IF _DB-L-S-OK ELSE _DB-L-S-RECOVERY THEN ;

: _DB-LOAD-DIRECT  ( -- status )
    _DB-RECOVER DUP IF -1 _DB-SOURCE-BLOCKED ! EXIT THEN DROP
    _DB-READ-FILE DUP _DB-L-S-MISSING = IF
        DROP _DB-CLEAR 0 _DB-SOURCE-BLOCKED ! _DB-L-S-OK EXIT
    THEN
    DUP IF -1 _DB-SOURCE-BLOCKED ! EXIT THEN DROP
    _DB-PARSE-FILE DUP IF -1 ELSE 0 THEN _DB-SOURCE-BLOCKED ! ;

VARIABLE _DB-SL-A
VARIABLE _DB-SL-U

VARIABLE _DB-SRQ-CAP
VARIABLE _DB-SRQ-PRINCIPAL

: _DB-SHARED-REQUEST!  ( capability principal -- status )
    _DB-SRQ-PRINCIPAL ! _DB-SRQ-CAP !
    _DB-SHARED-BIND _DB-SHARED-CONTEXT @ _DB-SHARED-REQUEST @
        LBIND-REQUEST! DUP IF EXIT THEN DROP
    _DB-SRQ-PRINCIPAL @ _DB-SHARED-REQUEST @ CBR.PRINCIPAL !
    _DB-SRQ-CAP @ _DB-SHARED-REQUEST @ CBR.CAP !
    LBIND-S-OK ;

: _DB-SHARED-SNAPSHOT  ( -- status )
    _DB-SHARED-REFRESH DUP IF
        DUP SDLENS-S-STALE = IF
            DROP _DB-L-S-STALE EXIT
        THEN
        DROP _DB-SHARED-BLOCK! _DB-L-S-SHARED EXIT
    THEN DROP
    _DB-SHARED-SNAPSHOT-CAP @ CPRINC-USER _DB-SHARED-REQUEST!
    DUP IF DROP _DB-SHARED-BLOCK! _DB-L-S-SHARED EXIT THEN DROP
    \ LBIND stamps identity; this operation still chooses null arguments.
    _DB-SHARED-REQUEST @ CBR.ARGS CV-NULL!
    _DB-SHARED-REQUEST @ _DB-SHARED-BUS @ CBUS-DISPATCH
    DUP CBUS-S-STALE-REVISION = IF DROP _DB-L-S-STALE EXIT THEN
    DUP IF DROP _DB-L-S-IO EXIT THEN DROP
    _DB-SHARED-REQUEST @ CBR.RESULT
    DUP CV-LEN@ _DB-SL-U ! CV-DATA@ _DB-SL-A !
    _DB-SL-U @ DUP 0< SWAP _DB-IO-CAP > OR IF
        _DB-L-S-TOO-LARGE EXIT
    THEN
    _DB-SL-U @ 0> _DB-SL-A @ 0= AND IF _DB-L-S-IO EXIT THEN
    _DB-SL-A @ _DB-IO-BUF _DB-SL-U @ CMOVE
    _DB-SL-U @ _DB-IO-U !
    _DB-L-S-OK ;

: _DB-LOAD-SHARED  ( -- status )
    _DB-SHARED-SNAPSHOT DUP IF
        -1 _DB-SOURCE-BLOCKED ! EXIT
    THEN DROP
    _DB-IO-U @ 0= IF
        _DB-CLEAR 0 _DB-SOURCE-BLOCKED ! _DB-L-S-OK EXIT
    THEN
    _DB-PARSE-FILE DUP IF -1 ELSE 0 THEN _DB-SOURCE-BLOCKED ! ;

: _DB-LOAD  ( -- status )
    _DB-RESOURCE-MODE @ CASE
        SDLENS-M-SHARED OF _DB-LOAD-SHARED ENDOF
        SDLENS-M-BLOCKED OF
            -1 _DB-SOURCE-BLOCKED ! _DB-L-S-SHARED
        ENDOF
        _DB-LOAD-DIRECT SWAP
    ENDCASE ;

VARIABLE _DB-APP-A
VARIABLE _DB-APP-U
VARIABLE _DB-APP-N

: _DB-IO-RESET  ( -- )  0 _DB-IO-U ! ;

: _DB-IO-APPEND  ( addr len -- )
    _DB-APP-U ! _DB-APP-A !
    _DB-IO-CAP _DB-IO-U @ - 0 MAX _DB-APP-U @ MIN _DB-APP-N !
    _DB-APP-A @ _DB-IO-BUF _DB-IO-U @ + _DB-APP-N @ CMOVE
    _DB-APP-N @ _DB-IO-U +! ;

: _DB-IO-CHAR  ( c -- )
    _DB-IO-U @ _DB-IO-CAP < IF
        _DB-IO-BUF _DB-IO-U @ + C! 1 _DB-IO-U +!
    ELSE DROP THEN ;

: _DB-IO-2D  ( n -- )
    DUP 10 / [CHAR] 0 + _DB-IO-CHAR
    10 MOD [CHAR] 0 + _DB-IO-CHAR ;

VARIABLE _DB-SER-E

: _DB-SERIALIZE-ENTRY  ( entry -- )
    _DB-SER-E !
    _DB-SER-E @ _DB-E-KIND + @ CASE
        _DB-K-TASK OF
            S" - [" _DB-IO-APPEND
            _DB-SER-E @ _DB-E-DONE + @ IF [CHAR] x ELSE BL THEN _DB-IO-CHAR
            S" ] " _DB-IO-APPEND
        ENDOF
        _DB-K-EVENT OF S" - " _DB-IO-APPEND ENDOF
        _DB-K-NOTE OF S" > " _DB-IO-APPEND ENDOF
    ENDCASE
    _DB-SER-E @ _DB-E-DATE + @ _DB-DATE-BUF 16 DT-DATE
    _DB-DATE-BUF SWAP _DB-IO-APPEND
    _DB-SER-E @ _DB-E-KIND + @ _DB-K-EVENT = IF
        BL _DB-IO-CHAR
        _DB-SER-E @ _DB-E-MINUTE + @ DUP 60 / _DB-IO-2D
        [CHAR] : _DB-IO-CHAR 60 MOD _DB-IO-2D
    THEN
    S"  | " _DB-IO-APPEND
    _DB-SER-E @ _DB-E-TEXT +
    _DB-SER-E @ _DB-E-TEXT-U + @ _DB-IO-APPEND
    10 _DB-IO-CHAR ;

: _DB-SERIALIZE  ( -- )
    _DB-IO-RESET
    S" # Daybook" _DB-IO-APPEND 10 _DB-IO-CHAR 10 _DB-IO-CHAR
    _DB-COUNT @ 0 ?DO I _DB-ENTRY _DB-SERIALIZE-ENTRY LOOP ;

VARIABLE _DB-SAVE-IOR

: _DB-WRITE-DIRECT  ( -- ior )
    _DB-SOURCE-BLOCKED @ IF _DB-L-S-RECOVERY EXIT THEN
    _DB-IO-BUF _DB-IO-U @ _DB-REPLACE VREPL-REPLACE
    DUP VREPL-S-OK = IF DROP 0 EXIT THEN
    DUP VREPL-S-COMMITTED-CLEANUP = IF DROP 0 EXIT THEN ;

: _DB-WRITE-SHARED  ( -- ior )
    0 _DB-SAVE-STALE !
    _DB-SOURCE-BLOCKED @ IF _DB-W-S-SHARED EXIT THEN
    _DB-SHARED-REPLACE-CAP @
    _DB-CAPTURE-HOP @ IF CPRINC-COMPONENT ELSE CPRINC-USER THEN
    _DB-SHARED-REQUEST! DUP IF
        DROP _DB-SHARED-BLOCK! _DB-W-S-SHARED EXIT
    THEN DROP
    _DB-CAPTURE-HOP @ IF
        \ This approval is a bounded implementation hop inside the already
        \ authorized daybook.task.capture handler.  It is not delegation:
        \ general derived authority does not exist yet.
        _DB-SHARED-REQUEST @ CBR-APPROVE
    THEN
    _DB-IO-BUF _DB-IO-U @ _DB-SHARED-REQUEST @ CBR.ARGS CV-STRING!
    IF _DB-W-S-SHARED EXIT THEN
    _DB-SHARED-REQUEST @ _DB-SHARED-BUS @ CBUS-DISPATCH
    DUP CBUS-S-STALE-REVISION = IF
        DROP -1 _DB-SAVE-STALE ! CBUS-S-STALE-REVISION EXIT
    THEN
    DUP IF EXIT THEN DROP
    _DB-SHARED-REQUEST @ _DB-SHARED-CONTEXT @ _DB-SHARED-BIND
        LBIND-ADVANCE DUP IF
        \ The owner has already committed and advanced.  Never report this as
        \ an unsaved failure or roll a captured entry back.  Invalidate the
        \ local lens, preserve the committed model, and require an explicit
        \ reload before another write.
        DROP _DB-SHARED-BIND LBIND-CLEAR
        -1 _DB-SOURCE-BLOCKED ! 0 EXIT
    THEN DROP
    0 ;

: _DB-WRITE  ( -- ior )
    0 _DB-SAVE-STALE !
    _DB-RESOURCE-MODE @ CASE
        SDLENS-M-SHARED OF _DB-WRITE-SHARED ENDOF
        SDLENS-M-BLOCKED OF _DB-W-S-SHARED ENDOF
        _DB-WRITE-DIRECT SWAP
    ENDCASE ;

: _DB-DAY-COUNT  ( -- n )
    0
    _DB-COUNT @ 0 ?DO
        I _DB-ENTRY _DB-E-DATE + @ _DB-SELECTED-DATE @ = IF 1+ THEN
    LOOP ;

VARIABLE _DB-KC-KIND
: _DB-KIND-COUNT  ( kind -- n )
    _DB-KC-KIND ! 0
    _DB-COUNT @ 0 ?DO
        I _DB-ENTRY DUP _DB-E-DATE + @ _DB-SELECTED-DATE @ =
        SWAP _DB-E-KIND + @ _DB-KC-KIND @ = AND IF 1+ THEN
    LOOP ;

: _DB-CLAMP-SELECTION  ( -- )
    _DB-DAY-COUNT DUP 0= IF DROP 0 _DB-SELECTED ! EXIT THEN
    1- _DB-SELECTED @ MIN 0 MAX _DB-SELECTED ! ;

VARIABLE _DB-NTH-WANT
VARIABLE _DB-NTH-SEEN
VARIABLE _DB-NTH-KIND

: _DB-NTH-IN-KIND  ( kind -- entry | 0 )
    _DB-NTH-KIND !
    _DB-COUNT @ 0 ?DO
        I _DB-ENTRY DUP _DB-E-DATE + @ _DB-SELECTED-DATE @ =
        OVER _DB-E-KIND + @ _DB-NTH-KIND @ = AND IF
            _DB-NTH-SEEN @ _DB-NTH-WANT @ = IF UNLOOP EXIT THEN
            1 _DB-NTH-SEEN +!
        THEN DROP
    LOOP 0 ;

: _DB-SELECTED-ENTRY  ( -- entry | 0 )
    _DB-SELECTED @ _DB-NTH-WANT ! 0 _DB-NTH-SEEN !
    _DB-K-EVENT _DB-NTH-IN-KIND ?DUP IF EXIT THEN
    _DB-K-TASK  _DB-NTH-IN-KIND ?DUP IF EXIT THEN
    _DB-K-NOTE  _DB-NTH-IN-KIND ;

VARIABLE _DB-ST-A
VARIABLE _DB-ST-U
VARIABLE _DB-ST-N

: _DB-ST-RESET  ( -- ) 0 _DB-STATUS-U ! ;
: _DB-ST-APPEND  ( addr len -- )
    _DB-ST-U ! _DB-ST-A !
    96 _DB-STATUS-U @ - 0 MAX _DB-ST-U @ MIN _DB-ST-N !
    _DB-ST-A @ _DB-STATUS-BUF _DB-STATUS-U @ + _DB-ST-N @ CMOVE
    _DB-ST-N @ _DB-STATUS-U +! ;

: _DB-UPDATE-STATUS  ( -- )
    _DB-SELECTED-DATE @ _DB-DATE-BUF 16 DT-DATE DROP
    _DB-E-SBAR-DATE @ ?DUP IF
        S" text" _DB-DATE-BUF 10 UTUI-SET-ATTR
    THEN
    _DB-ST-RESET
    _DB-DAY-COUNT NUM>STR _DB-ST-APPEND
    S"  entries  |  " _DB-ST-APPEND
    _DB-RESOURCE-MODE @ SDLENS-M-BLOCKED = IF
        S" Shared resource blocked"
    ELSE _DB-SOURCE-BLOCKED @ IF
        S" Source blocked"
    ELSE
        _DB-DIRTY @ IF S" Unsaved" ELSE S" Saved" THEN
    THEN THEN
    _DB-ST-APPEND
    _DB-E-SBAR-STATE @ ?DUP IF
        S" text" _DB-STATUS-BUF _DB-STATUS-U @ UTUI-SET-ATTR
    THEN ;

: _DB-INVALIDATE  ( -- )
    _DB-PANEL WDG-DIRTY
    _DB-E-BODY @ ?DUP IF UIDL-DIRTY! THEN
    _DB-UPDATE-STATUS
    ASHELL-DIRTY! ;

: _DB-SAVE  ( -- ior )
    _DB-SERIALIZE _DB-WRITE DUP _DB-SAVE-IOR !
    0= IF 0 _DB-DIRTY ! 0 _DB-DISCARD-ARMED ! THEN
    _DB-INVALIDATE
    _DB-SAVE-IOR @ ;

: _DB-TOUCH  ( -- )
    _DB-CURRENT-INSTANCE @ ?DUP IF CINST-TOUCH THEN ;

: _DB-SAVE-ERROR-TOAST  ( -- )
    _DB-SAVE-STALE @ IF
        S" Daybook changed elsewhere; reload before saving"
        3000 ASHELL-TOAST
    ELSE _DB-RESOURCE-MODE @ SDLENS-M-BLOCKED = IF
        S" Shared Daybook resource is unavailable; saving is blocked"
        3000 ASHELL-TOAST
    ELSE _DB-SOURCE-BLOCKED @ IF
        S" Reload a valid Daybook source before saving" 2600 ASHELL-TOAST
    ELSE
        S" Daybook save failed" 2200 ASHELL-TOAST
    THEN THEN THEN ;

: _DB-COMMIT  ( -- )
    -1 _DB-DIRTY ! 0 _DB-DISCARD-ARMED !
    _DB-SAVE IF
        _DB-SAVE-ERROR-TOAST
    ELSE
        _DB-TOUCH
    THEN ;

VARIABLE _DB-HAS-DATE

: _DB-HAS-ENTRY?  ( epoch -- flag )
    _DB-HAS-DATE !
    _DB-COUNT @ 0 ?DO
        I _DB-ENTRY _DB-E-DATE + @ _DB-HAS-DATE @ = IF
            -1 UNLOOP EXIT
        THEN
    LOOP 0 ;

: _DB-MONTH-NAME  ( month -- addr len )
    CASE
        1 OF S" January" ENDOF 2 OF S" February" ENDOF
        3 OF S" March" ENDOF 4 OF S" April" ENDOF
        5 OF S" May" ENDOF 6 OF S" June" ENDOF
        7 OF S" July" ENDOF 8 OF S" August" ENDOF
        9 OF S" September" ENDOF 10 OF S" October" ENDOF
        11 OF S" November" ENDOF 12 OF S" December" ENDOF
        S" Month"
    ENDCASE ;

VARIABLE _DB-DW
VARIABLE _DB-DH
VARIABLE _DB-DCAL-W
VARIABLE _DB-DY
VARIABLE _DB-DM
VARIABLE _DB-DD
VARIABLE _DB-DMONTH-EPOCH
VARIABLE _DB-DWDAY
VARIABLE _DB-DROW
VARIABLE _DB-DCOL
VARIABLE _DB-DEPOCH
VARIABLE _DB-DATTR

: _DB-DRAW-CALENDAR  ( -- )
    _DB-SELECTED-DATE @ DT-EPOCH>YMD _DB-DD ! _DB-DM ! _DB-DY !
    255 23 0 DRW-STYLE!
    32 0 0 _DB-DH @ _DB-DCAL-W @ DRW-FILL-RECT
    255 23 1 DRW-STYLE!
    _DB-DM @ _DB-MONTH-NAME 0 2 DRW-TEXT
    _DB-DY @ NUM>STR 0 _DB-DCAL-W @ 6 - DRW-TEXT
    250 23 0 DRW-STYLE!
    S" Mo Tu We Th Fr Sa Su" 2 1 DRW-TEXT
    _DB-DY @ _DB-DM @ 1 DT-YMD>EPOCH DUP _DB-DMONTH-EPOCH !
    _DB-SECONDS-DAY / 3 + 7 MOD _DB-DWDAY !
    _DB-DM @ _DB-DY @ _DT-DIM@ 1+ 1 DO
        _DB-DWDAY @ I 1- + DUP 7 / 4 + _DB-DROW !
        7 MOD 3 * 2 + _DB-DCOL !
        _DB-DMONTH-EPOCH @ I 1- _DB-SECONDS-DAY * + _DB-DEPOCH !
        0 _DB-DATTR !
        _DB-DEPOCH @ _DB-SELECTED-DATE @ = IF
            CELL-A-REVERSE _DB-DATTR +!
        THEN
        _DB-DEPOCH @ _DB-TODAY = IF CELL-A-UNDERLINE _DB-DATTR +! THEN
        _DB-DEPOCH @ _DB-HAS-ENTRY? IF CELL-A-BOLD _DB-DATTR +! THEN
        255 23 _DB-DATTR @ DRW-STYLE!
        I NUM>STR _DB-DROW @ _DB-DCOL @ 2 DRW-TEXT-RIGHT
    LOOP
    239 234 0 DRW-STYLE!
    9474 0 _DB-DCAL-W @ _DB-DH @ DRW-VLINE ;

VARIABLE _DB-AGENDA-COL
VARIABLE _DB-AGENDA-W
VARIABLE _DB-VIEW-INDEX
VARIABLE _DB-DRAW-KIND
VARIABLE _DB-DRAW-ROW
VARIABLE _DB-DRAW-E
VARIABLE _DB-DRAW-TEXT-W

: _DB-DRAW-TIME  ( minute row col -- )
    _DB-DCOL ! _DB-DROW !
    DUP 60 / DUP 10 / [CHAR] 0 + _DB-DROW @ _DB-DCOL @ DRW-CHAR
    10 MOD [CHAR] 0 + _DB-DROW @ _DB-DCOL @ 1+ DRW-CHAR
    [CHAR] : _DB-DROW @ _DB-DCOL @ 2 + DRW-CHAR
    60 MOD DUP 10 / [CHAR] 0 + _DB-DROW @ _DB-DCOL @ 3 + DRW-CHAR
    10 MOD [CHAR] 0 + _DB-DROW @ _DB-DCOL @ 4 + DRW-CHAR ;

: _DB-DRAW-ENTRY  ( entry -- )
    _DB-DRAW-E !
    _DB-VIEW-INDEX @ _DB-SELECTED @ = IF CELL-A-REVERSE ELSE 0 THEN
    _DB-DRAW-E @ _DB-E-KIND + @ _DB-K-TASK =
    _DB-DRAW-E @ _DB-E-DONE + @ AND IF CELL-A-DIM OR THEN
    253 234 ROT DRW-STYLE!
    _DB-DRAW-E @ _DB-E-KIND + @ CASE
        _DB-K-EVENT OF
            220 DRW-FG!
            _DB-DRAW-E @ _DB-E-MINUTE + @ _DB-DRAW-ROW @ _DB-AGENDA-COL @ 2 + _DB-DRAW-TIME
            253 DRW-FG!
            _DB-DRAW-E @ _DB-E-TEXT +
            _DB-DRAW-E @ _DB-E-TEXT-U + @ _DB-DRAW-TEXT-W @ MIN
            _DB-DRAW-ROW @ _DB-AGENDA-COL @ 9 + DRW-TEXT
        ENDOF
        _DB-K-TASK OF
            _DB-DRAW-E @ _DB-E-DONE + @ IF S" [x]" ELSE S" [ ]" THEN
            _DB-DRAW-ROW @ _DB-AGENDA-COL @ 2 + DRW-TEXT
            _DB-DRAW-E @ _DB-E-TEXT +
            _DB-DRAW-E @ _DB-E-TEXT-U + @ _DB-DRAW-TEXT-W @ 4 + MIN
            _DB-DRAW-ROW @ _DB-AGENDA-COL @ 6 + DRW-TEXT
        ENDOF
        _DB-K-NOTE OF
            45 _DB-DRAW-ROW @ _DB-AGENDA-COL @ 2 + DRW-CHAR
            _DB-DRAW-E @ _DB-E-TEXT +
            _DB-DRAW-E @ _DB-E-TEXT-U + @ _DB-DRAW-TEXT-W @ 2 + MIN
            _DB-DRAW-ROW @ _DB-AGENDA-COL @ 4 + DRW-TEXT
        ENDOF
    ENDCASE
    1 _DB-VIEW-INDEX +! ;

: _DB-DRAW-KIND-SECTION  ( kind -- )
    _DB-DRAW-KIND !
    _DB-DRAW-ROW @ _DB-DH @ >= IF EXIT THEN
    244 234 1 DRW-STYLE!
    _DB-DRAW-KIND @ CASE
        _DB-K-EVENT OF S" SCHEDULE" ENDOF
        _DB-K-TASK OF S" TASKS" ENDOF
        _DB-K-NOTE OF S" NOTES" ENDOF
    ENDCASE
    _DB-DRAW-ROW @ _DB-AGENDA-COL @ 1+ DRW-TEXT
    1 _DB-DRAW-ROW +!
    _DB-COUNT @ 0 ?DO
        I _DB-ENTRY DUP _DB-E-DATE + @ _DB-SELECTED-DATE @ =
        OVER _DB-E-KIND + @ _DB-DRAW-KIND @ = AND IF
            _DB-DRAW-ROW @ _DB-DH @ < IF
                DUP _DB-DRAW-ENTRY 1 _DB-DRAW-ROW +!
            THEN
        THEN DROP
    LOOP
    1 _DB-DRAW-ROW +! ;

: _DB-DRAW-AGENDA  ( -- )
    253 234 0 DRW-STYLE!
    32 0 _DB-AGENDA-COL @ _DB-DH @ _DB-AGENDA-W @ DRW-FILL-RECT
    255 234 1 DRW-STYLE!
    _DB-SELECTED-DATE @ _DB-DATE-BUF 16 DT-DATE
    _DB-DATE-BUF SWAP 0 _DB-AGENDA-COL @ 2 + DRW-TEXT
    244 234 0 DRW-STYLE!
    _DB-DAY-COUNT NUM>STR 0
    _DB-AGENDA-COL @ _DB-AGENDA-W @ + 10 - 0 MAX DRW-TEXT
    239 234 0 DRW-STYLE!
    9472 1 _DB-AGENDA-COL @ 1+ _DB-AGENDA-W @ 2 - DRW-HLINE
    _DB-AGENDA-W @ 11 - 1 MAX _DB-DRAW-TEXT-W !
    0 _DB-VIEW-INDEX ! 3 _DB-DRAW-ROW !
    _DB-DAY-COUNT 0= IF
        244 234 CELL-A-DIM DRW-STYLE!
        S" No entries for this day" 4 _DB-AGENDA-COL @ 2 + DRW-TEXT
        EXIT
    THEN
    _DB-K-EVENT _DB-DRAW-KIND-SECTION
    _DB-K-TASK _DB-DRAW-KIND-SECTION
    _DB-K-NOTE _DB-DRAW-KIND-SECTION ;

: _DB-PANEL-DRAW  ( widget -- )
    DUP WDG-REGION RGN-W _DB-DW !
    WDG-REGION RGN-H _DB-DH !
    _DB-DW @ 72 >= _DB-DH @ 14 >= AND IF
        25 _DB-DCAL-W !
        _DB-DCAL-W @ 1+ _DB-AGENDA-COL !
        _DB-DW @ _DB-AGENDA-COL @ - _DB-AGENDA-W !
        _DB-DRAW-CALENDAR
    ELSE
        0 _DB-AGENDA-COL ! _DB-DW @ _DB-AGENDA-W !
    THEN
    _DB-DRAW-AGENDA
    DRW-STYLE-RESET ;

: _DB-MOVE-DATE  ( days -- )
    _DB-SECONDS-DAY * _DB-SELECTED-DATE +!
    0 _DB-SELECTED ! _DB-TOUCH _DB-INVALIDATE ;

: _DB-SELECT-UP  ( -- )
    _DB-SELECTED @ 0> IF -1 _DB-SELECTED +! THEN _DB-INVALIDATE ;

: _DB-SELECT-DOWN  ( -- )
    _DB-DAY-COUNT 1- _DB-SELECTED @ > IF 1 _DB-SELECTED +! THEN
    _DB-INVALIDATE ;

: _DB-TOGGLE-SELECTED  ( -- )
    _DB-SELECTED-ENTRY ?DUP 0= IF EXIT THEN
    DUP _DB-E-KIND + @ _DB-K-TASK <> IF DROP EXIT THEN
    DUP _DB-E-DONE + DUP @ 0= SWAP ! DROP
    _DB-COMMIT ;

VARIABLE _DB-DEL-E
VARIABLE _DB-DEL-I

: _DB-DELETE-SELECTED  ( -- )
    _DB-SELECTED-ENTRY DUP 0= IF DROP EXIT THEN _DB-DEL-E !
    _DB-DEL-E @ _DB-ENTRIES - _DB-ENTRY-SZ / _DB-DEL-I !
    _DB-COUNT @ _DB-DEL-I @ - 1- DUP 0> IF
        _DB-DEL-E @ _DB-ENTRY-SZ + _DB-DEL-E @ ROT _DB-ENTRY-SZ * CMOVE
    ELSE DROP THEN
    -1 _DB-COUNT +!
    _DB-CLAMP-SELECTION
    _DB-COMMIT ;

VARIABLE _DB-H-WIDGET

: _DB-PANEL-HANDLE  ( event widget -- consumed? )
    _DB-H-WIDGET !
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-LEFT OF -1 _DB-MOVE-DATE -1 EXIT ENDOF
            KEY-RIGHT OF 1 _DB-MOVE-DATE -1 EXIT ENDOF
            KEY-PGUP OF -7 _DB-MOVE-DATE -1 EXIT ENDOF
            KEY-PGDN OF 7 _DB-MOVE-DATE -1 EXIT ENDOF
            KEY-UP OF _DB-SELECT-UP -1 EXIT ENDOF
            KEY-DOWN OF _DB-SELECT-DOWN -1 EXIT ENDOF
            KEY-HOME OF _DB-TODAY _DB-SELECTED-DATE ! 0 _DB-SELECTED ! _DB-TOUCH _DB-INVALIDATE -1 EXIT ENDOF
            KEY-ENTER OF _DB-TOGGLE-SELECTED -1 EXIT ENDOF
            KEY-DEL OF _DB-DELETE-SELECTED -1 EXIT ENDOF
        ENDCASE
        0 EXIT
    THEN
    DUP @ KEY-T-CHAR = IF
        DUP 16 + @ 0= IF
            8 + @ CASE
                BL OF _DB-TOGGLE-SELECTED -1 EXIT ENDOF
                [CHAR] t OF _DB-TODAY _DB-SELECTED-DATE ! 0 _DB-SELECTED ! _DB-TOUCH _DB-INVALIDATE -1 EXIT ENDOF
            ENDCASE
        THEN
    THEN
    DROP 0 ;

: _DB-PANEL-INIT  ( rgn -- )
    DUP _DB-PANEL-RGN !
    _DB-PANEL
    30 OVER !
    SWAP OVER 8 + !
    ['] _DB-PANEL-DRAW OVER 16 + !
    ['] _DB-PANEL-HANDLE OVER 24 + !
    WDG-F-VISIBLE WDG-F-DIRTY OR SWAP 32 + ! ;

VARIABLE _DB-SHOW-MODE
VARIABLE _DB-SHOW-LA
VARIABLE _DB-SHOW-LU

: _DB-SHOW-PROMPT  ( mode label-a label-u -- )
    _DB-SHOW-LU ! _DB-SHOW-LA ! _DB-SHOW-MODE !
    _DB-PROMPT @ 0= IF EXIT THEN
    _DB-SHOW-MODE @ _DB-PROMPT-MODE !
    _DB-SHOW-LA @ _DB-SHOW-LU @ 0 0 _DB-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _DB-DO-NEW-TASK  ( elem -- ) DROP _DB-PRM-TASK S" New task:" _DB-SHOW-PROMPT ;
: _DB-DO-NEW-EVENT ( elem -- ) DROP _DB-PRM-EVENT S" Event (HH:MM title):" _DB-SHOW-PROMPT ;
: _DB-DO-NEW-NOTE  ( elem -- ) DROP _DB-PRM-NOTE S" New note:" _DB-SHOW-PROMPT ;

VARIABLE _DB-SUB-A
VARIABLE _DB-SUB-U
VARIABLE _DB-SUB-MODE
VARIABLE _DB-SUB-MINUTE

: _DB-SELECT-NEW-TASK  ( -- )
    _DB-K-EVENT _DB-KIND-COUNT
    _DB-K-TASK _DB-KIND-COUNT + 1- 0 MAX _DB-SELECTED ! ;

: _DB-ADD-FAILED-TOAST  ( -- )
    S" Entry is too long or Daybook is full" 2400 ASHELL-TOAST ;

: _DB-LOAD-ERROR-TOAST  ( status -- )
    DUP _DB-L-S-STALE = IF
        DROP S" Daybook changed while reloading; reload again"
        2800 ASHELL-TOAST EXIT
    THEN
    DUP _DB-L-S-SHARED = IF
        DROP S" Shared Daybook resource is unavailable; saving is blocked"
        3200 ASHELL-TOAST EXIT
    THEN
    DUP _DB-L-S-TOO-LARGE = IF
        DROP S" Daybook source exceeds 32 KiB; current entries kept"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _DB-L-S-RECOVERY = IF
        DROP S" Daybook recovery failed; current entries kept"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _DB-L-S-INVALID = IF
        DROP S" Daybook source is invalid; current entries kept"
        3000 ASHELL-TOAST EXIT
    THEN
    DUP _DB-L-S-CAPACITY = IF
        DROP S" Daybook source has more than 96 entries; current entries kept"
        3000 ASHELL-TOAST EXIT
    THEN
    _DB-L-S-TEXT = IF
        S" Daybook source has text over 120 bytes; current entries kept"
    ELSE
        S" Daybook read failed; current entries kept"
    THEN
    3000 ASHELL-TOAST ;

: _DB-RELOAD-NOW  ( -- )
    _DB-LOAD DUP IF
        _DB-LOAD-ERROR-TOAST
    ELSE
        DROP 0 _DB-DIRTY ! 0 _DB-DISCARD-ARMED !
        _DB-CLAMP-SELECTION _DB-TOUCH _DB-INVALIDATE
        S" Daybook reloaded" 1400 ASHELL-TOAST
    THEN ;

: _DB-RESHOW-DISCARD-CLOSE  ( -- )
    _DB-PRM-DISCARD-CLOSE S" Type DISCARD to close without saving:"
    _DB-SHOW-PROMPT ;

: _DB-RESHOW-DISCARD-RELOAD  ( -- )
    _DB-PRM-DISCARD-RELOAD S" Type RELOAD to discard unsaved changes:"
    _DB-SHOW-PROMPT ;

: _DB-PROMPT-SUBMIT  ( prompt -- )
    PRM-GET-TEXT _DB-SUB-U ! _DB-SUB-A !
    _DB-PROMPT-MODE @ _DB-SUB-MODE !
    _DB-PRM-NONE _DB-PROMPT-MODE !
    _DB-SUB-MODE @ _DB-PRM-DISCARD-CLOSE = IF
        _DB-SUB-A @ _DB-SUB-U @ S" DISCARD" STR-STR= IF
            -1 _DB-DISCARD-ARMED !
            S" Unsaved Daybook changes will be discarded" 1800 ASHELL-TOAST
            ASHELL-QUIT
        ELSE
            S" Enter DISCARD exactly to confirm" 2000 ASHELL-TOAST
            _DB-RESHOW-DISCARD-CLOSE
        THEN
        _DB-INVALIDATE EXIT
    THEN
    _DB-SUB-MODE @ _DB-PRM-DISCARD-RELOAD = IF
        _DB-SUB-A @ _DB-SUB-U @ S" RELOAD" STR-STR= IF
            _DB-RELOAD-NOW
        ELSE
            S" Enter RELOAD exactly to confirm" 2000 ASHELL-TOAST
            _DB-RESHOW-DISCARD-RELOAD
        THEN
        _DB-INVALIDATE EXIT
    THEN
    _DB-SUB-U @ 0= IF _DB-INVALIDATE EXIT THEN
    _DB-SUB-MODE @ CASE
        _DB-PRM-TASK OF
            _DB-K-TASK 0 _DB-SELECTED-DATE @ -1
            _DB-SUB-A @ _DB-SUB-U @ _DB-ADD
            DUP 0< IF DROP _DB-ADD-FAILED-TOAST
            ELSE DROP _DB-SELECT-NEW-TASK _DB-COMMIT THEN
        ENDOF
        _DB-PRM-EVENT OF
            _DB-SUB-U @ 6 < IF
                S" Use HH:MM followed by a title" 2200 ASHELL-TOAST
            ELSE
                _DB-SUB-A @ 5 _DB-PARSE-TIME
                0= IF
                    DROP S" Invalid event time" 2200 ASHELL-TOAST
                ELSE
                    _DB-SUB-MINUTE !
                    _DB-K-EVENT 0 _DB-SELECTED-DATE @ _DB-SUB-MINUTE @
                    _DB-SUB-A @ 6 + _DB-SUB-U @ 6 - _DB-ADD
                    DUP 0< IF DROP _DB-ADD-FAILED-TOAST
                    ELSE
                        DROP _DB-K-EVENT _DB-KIND-COUNT 1- 0 MAX
                        _DB-SELECTED ! _DB-COMMIT
                    THEN
                THEN
            THEN
        ENDOF
        _DB-PRM-NOTE OF
            _DB-K-NOTE 0 _DB-SELECTED-DATE @ -1
            _DB-SUB-A @ _DB-SUB-U @ _DB-ADD
            DUP 0< IF DROP _DB-ADD-FAILED-TOAST
            ELSE
                DROP _DB-DAY-COUNT 1- 0 MAX _DB-SELECTED ! _DB-COMMIT
            THEN
        ENDOF
    ENDCASE
    _DB-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _DB-INVALIDATE ;

: _DB-PROMPT-CANCEL  ( prompt -- )
    DROP _DB-PRM-NONE _DB-PROMPT-MODE !
    _DB-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _DB-INVALIDATE ;

: _DB-DO-SAVE  ( elem -- )
    DROP _DB-SAVE IF
        _DB-SAVE-ERROR-TOAST
    ELSE
        S" Daybook saved" 1600 ASHELL-TOAST
    THEN ;

: _DB-DO-RELOAD  ( elem -- )
    DROP _DB-DIRTY @ IF
        _DB-RESHOW-DISCARD-RELOAD
    ELSE
        _DB-RELOAD-NOW
    THEN ;

: _DB-DO-TOGGLE ( elem -- ) DROP _DB-TOGGLE-SELECTED ;
: _DB-DO-DELETE ( elem -- ) DROP _DB-DELETE-SELECTED ;
: _DB-DO-TODAY  ( elem -- ) DROP _DB-TODAY _DB-SELECTED-DATE ! 0 _DB-SELECTED ! _DB-TOUCH _DB-INVALIDATE ;
: _DB-DO-PREVIOUS ( elem -- ) DROP -1 _DB-MOVE-DATE ;
: _DB-DO-NEXT ( elem -- ) DROP 1 _DB-MOVE-DATE ;
: _DB-DO-QUIT ( elem -- ) DROP ASHELL-QUIT ;
: _DB-DO-ABOUT ( elem -- ) DROP S" Daybook - tasks, events, and daily notes" 2600 ASHELL-TOAST ;

VARIABLE _DB-SOURCE-REQ
VARIABLE _DB-INIT-LOAD-STATUS
VARIABLE _DB-SOURCE-VALUE

: _DB-SOURCE-VALUE!  ( value -- status )
    _DB-SOURCE-VALUE !
    _DB-RESOURCE-MODE @ CASE
        SDLENS-M-SHARED OF
            _DB-SHARED-BIND _DB-SHARED-REF LBIND-REF DUP IF
                DROP IRES-S-INVALID EXIT
            THEN DROP
            _DB-SHARED-REF _DB-SOURCE-VALUE @ IRES-RREF!
        ENDOF
        SDLENS-M-BLOCKED OF IRES-S-INVALID ENDOF
        S" /daybook.md" _DB-SOURCE-VALUE @ IRES-VFS! SWAP
    ENDCASE ;

: _DB-SOURCE-COMPLETE  ( request -- )
    DUP CBR.STATUS @ CBUS-S-OK <> IF
        S" Could not route the Daybook source" 2000 ASHELL-TOAST
    THEN
    CBR-FREE ;

: _DB-POST-SOURCE-INTENT  ( intent-a intent-u -- )
    CBR-NEW DUP IF
        2DROP 2DROP S" Could not allocate source request" 1800 ASHELL-TOAST EXIT
    THEN
    DROP _DB-SOURCE-REQ !
    CPRINC-COMPONENT _DB-SOURCE-REQ @ CBR.PRINCIPAL !
    _DB-SOURCE-REQ @ CBR.ARGS _DB-SOURCE-VALUE! IF
        2DROP _DB-SOURCE-REQ @ CBR-FREE
        _DB-RESOURCE-MODE @ SDLENS-M-BLOCKED = IF
            S" Shared Daybook resource is unavailable" 2200 ASHELL-TOAST
        THEN EXIT
    THEN
    ['] _DB-SOURCE-COMPLETE _DB-SOURCE-REQ @ CBR.COMPLETE-XT !
    _DB-SOURCE-REQ @ _DB-CURRENT-INSTANCE @ CINST-POST-INTENT
    DUP CBUS-S-OK <> IF
        DROP _DB-SOURCE-REQ @ CBR-FREE
        S" Source routing is unavailable outside Desk" 1800 ASHELL-TOAST
    ELSE DROP THEN ;

: _DB-DO-EDIT-SOURCE  ( elem -- )
    DROP S" resource.open" _DB-POST-SOURCE-INTENT ;

: _DB-DO-REVEAL-SOURCE  ( elem -- )
    DROP S" resource.reveal" _DB-POST-SOURCE-INTENT ;

: DAYBOOK-INIT-CB  ( instance -- )
    _DB-ACTIVATE
    0 _DB-PROMPT ! 0 _DB-PROMPT-RGN ! _DB-PRM-NONE _DB-PROMPT-MODE !
    0 _DB-DIRTY ! 0 _DB-DISCARD-ARMED ! 0 _DB-SOURCE-BLOCKED !
    0 _DB-SAVE-STALE !
    _DB-TODAY _DB-SELECTED-DATE !
    VFS-CUR DUP 0= ABORT" daybook: no VFS available" _DB-VFS !
    _DB-VFS @ _DB-LOAD-SCOPE VFA-SCOPE-INIT
    0<> ABORT" daybook: access scope initialization failed"
    _DB-SHARED-INIT
    _DB-RESOURCE-MODE @ SDLENS-M-DIRECT = IF
        _DB-VFS @ _DB-REPLACE VREPL-INIT
        0<> ABORT" daybook: replacement initialization failed"
        S" /daybook.md" _DB-REPLACE VREPL-DERIVE-PATHS!
        0<> ABORT" daybook: replacement path setup failed"
    THEN
    S" daybook-body" UTUI-BY-ID _DB-E-BODY !
    S" sbar" UTUI-BY-ID _DB-E-SBAR !
    S" sbar-date" UTUI-BY-ID _DB-E-SBAR-DATE !
    S" sbar-state" UTUI-BY-ID _DB-E-SBAR-STATE !
    _DB-LOAD _DB-INIT-LOAD-STATUS !

    _DB-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW DUP _DB-PROMPT-RGN !
        _DB-PROMPT-BUF _DB-PROMPT-CAP PRM-NEW DUP _DB-PROMPT !
        ['] _DB-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _DB-PROMPT-CANCEL OVER PRM-ON-CANCEL
        15 23 ROT PRM-COLORS!
    THEN
    _DB-E-BODY @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW _DB-PANEL-INIT
        _DB-PANEL _DB-E-BODY @ UTUI-WIDGET-SET
    THEN
    S" save" ['] _DB-DO-SAVE UTUI-DO!
    S" reload" ['] _DB-DO-RELOAD UTUI-DO!
    S" new-task" ['] _DB-DO-NEW-TASK UTUI-DO!
    S" new-event" ['] _DB-DO-NEW-EVENT UTUI-DO!
    S" new-note" ['] _DB-DO-NEW-NOTE UTUI-DO!
    S" toggle" ['] _DB-DO-TOGGLE UTUI-DO!
    S" delete" ['] _DB-DO-DELETE UTUI-DO!
    S" today" ['] _DB-DO-TODAY UTUI-DO!
    S" previous-day" ['] _DB-DO-PREVIOUS UTUI-DO!
    S" next-day" ['] _DB-DO-NEXT UTUI-DO!
    S" quit" ['] _DB-DO-QUIT UTUI-DO!
    S" about" ['] _DB-DO-ABOUT UTUI-DO!
    S" edit-source" ['] _DB-DO-EDIT-SOURCE UTUI-DO!
    S" reveal-source" ['] _DB-DO-REVEAL-SOURCE UTUI-DO!
    _DB-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _DB-CLAMP-SELECTION _DB-UPDATE-STATUS
    _DB-INIT-LOAD-STATUS @ ?DUP IF _DB-LOAD-ERROR-TOAST THEN ;

: DAYBOOK-EVENT-CB  ( event instance -- consumed? )
    _DB-ACTIVATE
    _DB-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _DB-PANEL WDG-HANDLE ;

: DAYBOOK-PAINT-CB  ( instance -- )
    _DB-ACTIVATE
    _DB-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN DROP
    _DB-E-SBAR @ ?DUP IF UTUI-ELEM-RGN _DB-PROMPT @ PRM-SET-BOUNDS THEN
    _DB-PROMPT @ WDG-DRAW ;

: DAYBOOK-TICK-CB  ( instance -- )
    _DB-ACTIVATE
    _DB-VIEW-DIRTY @ IF
        0 _DB-VIEW-DIRTY !
        _DB-INVALIDATE
    THEN ;

: DAYBOOK-REQUEST-CLOSE-CB  ( reason instance -- decision )
    SWAP DROP _DB-ACTIVATE
    _DB-DIRTY @ 0= IF
        0 _DB-DISCARD-ARMED ! APP-CLOSE-D-ALLOW EXIT
    THEN
    _DB-DISCARD-ARMED @ IF
        0 _DB-DISCARD-ARMED ! APP-CLOSE-D-ALLOW EXIT
    THEN
    _DB-PROMPT @ 0= IF APP-CLOSE-D-CANCEL EXIT THEN
    _DB-PROMPT @ PRM-ACTIVE? IF
        _DB-PROMPT-MODE @ _DB-PRM-DISCARD-CLOSE = IF
            APP-CLOSE-D-DEFER EXIT
        THEN
        S" Finish or cancel the current Daybook prompt before closing"
        2400 ASHELL-TOAST
        APP-CLOSE-D-CANCEL EXIT
    THEN
    _DB-RESHOW-DISCARD-CLOSE
    APP-CLOSE-D-DEFER ;

: DAYBOOK-SHUTDOWN-CB  ( instance -- )
    _DB-ACTIVATE
    _DB-E-BODY @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _DB-PROMPT @ ?DUP IF PRM-FREE THEN
    _DB-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _DB-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    0 _DB-PROMPT ! 0 _DB-PROMPT-RGN ! 0 _DB-PANEL-RGN !
    _DB-SHARED-FINI ;

CREATE _DB-TEXT-SCHEMA CS-SIZE ALLOT
CREATE _DB-AGENDA-SCHEMA CS-SIZE ALLOT
CREATE _DB-RESOURCE-SCHEMA CS-SIZE ALLOT
CREATE _DB-INT-SCHEMA CS-SIZE ALLOT
3 CONSTANT _DB-CAP-COUNT
CREATE DAYBOOK-CAPS _DB-CAP-COUNT CAP-DESC * ALLOT
: DAYBOOK-CAP-CAPTURE  ( -- cap ) DAYBOOK-CAPS ;
: DAYBOOK-CAP-SOURCE   ( -- cap ) DAYBOOK-CAPS CAP-DESC + ;
: DAYBOOK-CAP-AGENDA   ( -- cap ) DAYBOOK-CAPS CAP-DESC 2 * + ;

VARIABLE _DBCH-A
VARIABLE _DBCH-U
VARIABLE _DBCH-REQ
VARIABLE _DBCH-COUNT-BEFORE
VARIABLE _DBCH-DIRTY-BEFORE
VARIABLE _DBCH-DISCARD-BEFORE
VARIABLE _DBCH-INDEX
VARIABLE _DBCH-PERSIST-THROW

: _DBCH-PERSIST-CALL  ( -- )
    _DB-SERIALIZE _DB-WRITE _DB-SAVE-IOR ! ;

: _DB-CAP-CAPTURE-HANDLER  ( request instance -- status )
    _DB-ACTIVATE
    DUP _DBCH-REQ !
    DUP CBR.ARGS DUP CV-DATA@ SWAP CV-LEN@ _DBCH-U ! _DBCH-A !
    _DB-COUNT @ _DBCH-COUNT-BEFORE !
    _DB-DIRTY @ _DBCH-DIRTY-BEFORE !
    _DB-DISCARD-ARMED @ _DBCH-DISCARD-BEFORE !
    _DB-K-TASK 0 _DB-SELECTED-DATE @ -1 _DBCH-A @ _DBCH-U @ _DB-ADD
    DUP 0< IF DROP DROP CBUS-S-BUSY EXIT THEN
    DUP _DBCH-INDEX !
    OVER CBR.RESULT CV-INT!
    DROP
    -1 _DB-DIRTY ! 0 _DB-DISCARD-ARMED !
    -1 _DB-CAPTURE-HOP !
    ['] _DBCH-PERSIST-CALL CATCH _DBCH-PERSIST-THROW !
    0 _DB-CAPTURE-HOP !
    _DBCH-PERSIST-THROW @ IF
        _DB-W-S-SHARED
    ELSE
        _DB-SAVE-IOR @
    THEN
    DUP 0= IF 0 _DB-DIRTY ! 0 _DB-DISCARD-ARMED ! THEN
    -1 _DB-VIEW-DIRTY !
    DUP IF
        _DBCH-INDEX @ _DB-ENTRY _DB-ENTRY-SZ 0 FILL
        _DBCH-COUNT-BEFORE @ _DB-COUNT !
        _DBCH-DIRTY-BEFORE @ _DB-DIRTY !
        _DBCH-DISCARD-BEFORE @ _DB-DISCARD-ARMED !
        _DBCH-REQ @ CBR.RESULT CV-FREE
        S" Daybook persistence failed" ROT _DBCH-REQ @ CBR-ERROR!
        CBUS-S-FAILED
    ELSE
        DROP CBUS-S-OK
    THEN ;

: _DB-CAP-SOURCE-HANDLER  ( request instance -- status )
    _DB-ACTIVATE
    DUP CBR.RESULT _DB-SOURCE-VALUE!
    IF DROP CBUS-S-FAILED ELSE DROP CBUS-S-OK THEN ;

: _DB-CAP-AGENDA-HANDLER  ( request instance -- status )
    _DB-ACTIVATE
    _DB-SERIALIZE
    _DB-IO-BUF _DB-IO-U @ ROT CBR.RESULT CV-STRING!
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _DB-CAP-SETUP  ( -- )
    _DB-TEXT-SCHEMA CS-INIT
    CV-T-STRING _DB-TEXT-SCHEMA CS-ALLOW!
    _DB-TEXT-CAP _DB-TEXT-SCHEMA CS-MAX-LEN!
    _DB-AGENDA-SCHEMA CS-INIT
    CV-T-STRING _DB-AGENDA-SCHEMA CS-ALLOW!
    _DB-IO-CAP _DB-AGENDA-SCHEMA CS-MAX-LEN!
    _DB-RESOURCE-SCHEMA CS-INIT
    CV-T-RESOURCE _DB-RESOURCE-SCHEMA CS-ALLOW!
    516 _DB-RESOURCE-SCHEMA CS-MAX-LEN!
    _DB-INT-SCHEMA CS-INIT
    CV-T-INT _DB-INT-SCHEMA CS-ALLOW!

    DAYBOOK-CAP-CAPTURE CAP-DESC-INIT
    CAP-K-COMMAND DAYBOOK-CAP-CAPTURE CAP.KIND !
    S" daybook.task.capture"
    DAYBOOK-CAP-CAPTURE CAP.ID-U ! DAYBOOK-CAP-CAPTURE CAP.ID-A !
    S" Capture task"
    DAYBOOK-CAP-CAPTURE CAP.TITLE-U ! DAYBOOK-CAP-CAPTURE CAP.TITLE-A !
    S" Add a task to Daybook's selected date and persist it"
    DAYBOOK-CAP-CAPTURE CAP.DESC-U ! DAYBOOK-CAP-CAPTURE CAP.DESC-A !
    _DB-TEXT-SCHEMA DAYBOOK-CAP-CAPTURE CAP.IN-SCHEMA !
    _DB-INT-SCHEMA DAYBOOK-CAP-CAPTURE CAP.OUT-SCHEMA !
    CAP-E-MUTATE CAP-E-PERSIST OR DAYBOOK-CAP-CAPTURE CAP.EFFECTS !
    CAP-F-NEEDS-TARGET DAYBOOK-CAP-CAPTURE CAP.FLAGS !
    ['] _DB-CAP-CAPTURE-HANDLER DAYBOOK-CAP-CAPTURE CAP.HANDLER-XT !

    DAYBOOK-CAP-SOURCE CAP-DESC-INIT
    CAP-K-RESOURCE DAYBOOK-CAP-SOURCE CAP.KIND !
    S" daybook.source"
    DAYBOOK-CAP-SOURCE CAP.ID-U ! DAYBOOK-CAP-SOURCE CAP.ID-A !
    S" Daybook source"
    DAYBOOK-CAP-SOURCE CAP.TITLE-U ! DAYBOOK-CAP-SOURCE CAP.TITLE-A !
    S" Read the durable Daybook source resource"
    DAYBOOK-CAP-SOURCE CAP.DESC-U ! DAYBOOK-CAP-SOURCE CAP.DESC-A !
    _DB-RESOURCE-SCHEMA DAYBOOK-CAP-SOURCE CAP.OUT-SCHEMA !
    CAP-E-OBSERVE DAYBOOK-CAP-SOURCE CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR CAP-F-CONTEXT-DEFAULT OR
    DAYBOOK-CAP-SOURCE CAP.FLAGS !
    ['] _DB-CAP-SOURCE-HANDLER DAYBOOK-CAP-SOURCE CAP.HANDLER-XT !

    DAYBOOK-CAP-AGENDA CAP-DESC-INIT
    CAP-K-RESOURCE DAYBOOK-CAP-AGENDA CAP.KIND !
    S" daybook.agenda.markdown"
    DAYBOOK-CAP-AGENDA CAP.ID-U ! DAYBOOK-CAP-AGENDA CAP.ID-A !
    S" Daybook agenda"
    DAYBOOK-CAP-AGENDA CAP.TITLE-U ! DAYBOOK-CAP-AGENDA CAP.TITLE-A !
    S" Read the bounded task, event, and note source"
    DAYBOOK-CAP-AGENDA CAP.DESC-U ! DAYBOOK-CAP-AGENDA CAP.DESC-A !
    _DB-AGENDA-SCHEMA DAYBOOK-CAP-AGENDA CAP.OUT-SCHEMA !
    CAP-E-OBSERVE DAYBOOK-CAP-AGENDA CAP.EFFECTS !
    CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR DAYBOOK-CAP-AGENDA CAP.FLAGS !
    ['] _DB-CAP-AGENDA-HANDLER DAYBOOK-CAP-AGENDA CAP.HANDLER-XT ! ;

CREATE DAYBOOK-COMP-DESC COMP-DESC ALLOT

: _DAYBOOK-COMP-SETUP  ( -- )
    _DB-CAP-SETUP
    DAYBOOK-COMP-DESC COMP-DESC-INIT
    S" org.akashic.daybook"
    DAYBOOK-COMP-DESC COMP.ID-U ! DAYBOOK-COMP-DESC COMP.ID-A !
    S" 1.0.0"
    DAYBOOK-COMP-DESC COMP.VERSION-U ! DAYBOOK-COMP-DESC COMP.VERSION-A !
    _DB-STATE-SIZE DAYBOOK-COMP-DESC COMP.STATE-SIZE !
    DAYBOOK-CAPS DAYBOOK-COMP-DESC COMP.CAPS-A !
    _DB-CAP-COUNT DAYBOOK-COMP-DESC COMP.CAPS-N ! ;

: DAYBOOK-ENTRY  ( desc -- )
    _DAYBOOK-COMP-SETUP
    DUP APP-DESC-INIT
    DAYBOOK-COMP-DESC   OVER APP.COMP-DESC !
    ['] DAYBOOK-INIT-CB OVER APP.INIT-XT !
    ['] DAYBOOK-EVENT-CB OVER APP.EVENT-XT !
    ['] DAYBOOK-TICK-CB OVER APP.TICK-XT !
    ['] DAYBOOK-PAINT-CB OVER APP.PAINT-XT !
    ['] DAYBOOK-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _DB-ACTIVATE OVER APP.ACTIVATE-XT !
    ['] DAYBOOK-REQUEST-CLOSE-CB OVER APP.REQUEST-CLOSE-XT !
    S" tui/applets/daybook/daybook.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Daybook" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE DAYBOOK-DESC APP-DESC ALLOT

: DAYBOOK-RUN  ( -- )
    DAYBOOK-DESC DAYBOOK-ENTRY
    DAYBOOK-DESC ASHELL-RUN ;
