\ =====================================================================
\  screen-backend-apt1.f — Optional APT-1 CELL-1 screen adapter
\ =====================================================================
\
\  This module is deliberately not a dependency of screen.f, term-init.f,
\  app-shell.f, or KDOS.  Loading it requires MegaPad's separately supplied
\  presentation-terminal.f service.  A caller creates and starts PT-SESSION
\  storage, then constructs this caller-owned adapter from that live session.
\
\  Prefix: APTSCB- (public), _APTSCB- (internal)

PROVIDED akashic-tui-screen-backend-apt1

\ The selected system composition loads MegaPad's optional root
\ presentation-terminal.f module before this Akashic consumer.  This source
\ consumes that public PT-* ABI but never imports or copies the MegaPad source.
REQUIRE screen.f
REQUIRE ../utils/memory-span.f

PT-S-OK           SCB-S-OK           <> ABORT" APTSCB: status ABI mismatch"
PT-S-WOULD-BLOCK  SCB-S-WOULD-BLOCK  <> ABORT" APTSCB: status ABI mismatch"
PT-S-SESSION-LOST SCB-S-SESSION-LOST <> ABORT" APTSCB: status ABI mismatch"
PT-S-INVALID      SCB-S-INVALID      <> ABORT" APTSCB: status ABI mismatch"

SCB-DESC-SIZE CONSTANT _APTSCB-O-SESSION
SCB-DESC-SIZE 8 + CONSTANT _APTSCB-O-MAGIC
SCB-DESC-SIZE 16 + CONSTANT APTSCB-SIZE

HEX 4150545343420001 CONSTANT _APTSCB-MAGIC DECIMAL

: APTSCB.SESSION  ( adapter -- field ) _APTSCB-O-SESSION + ;
: APTSCB.MAGIC    ( adapter -- field ) _APTSCB-O-MAGIC + ;

: _APTSCB-CONTEXT-VALID?  ( adapter -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP APTSCB.SESSION @ 0<>
    SWAP APTSCB.MAGIC @ _APTSCB-MAGIC = AND ;

: APTSCB-SESSION@  ( adapter -- session|0 )
    DUP _APTSCB-CONTEXT-VALID? IF APTSCB.SESSION @ ELSE DROP 0 THEN ;

: APTSCB-VALID?  ( adapter -- flag )
    DUP _APTSCB-CONTEXT-VALID? 0= IF DROP 0 EXIT THEN
    DUP SCB.CONTEXT @ OVER =
    SWAP SCB-VALID? AND ;

VARIABLE _APTSCB-ADAPTER
VARIABLE _APTSCB-SESSION
VARIABLE _APTSCB-MODE
VARIABLE _APTSCB-COLS
VARIABLE _APTSCB-ROWS
VARIABLE _APTSCB-SPANS
VARIABLE _APTSCB-CELLS
VARIABLE _APTSCB-A
VARIABLE _APTSCB-N
VARIABLE _APTSCB-ROW
VARIABLE _APTSCB-COL
VARIABLE _APTSCB-CELL
VARIABLE _APTSCB-ATTRS
VARIABLE _APTSCB-STATUS

\ Collapse the presentation service's negotiation-only UNSUPPORTED status,
\ and any future status unknown to this frozen adapter ABI, into a lost
\ backend.  No PT status outside 0..3 may escape through the SCB interface.
: _APTSCB-MAP-STATUS  ( pt-status -- scb-status )
    DUP PT-S-OK = IF DROP SCB-S-OK EXIT THEN
    DUP PT-S-WOULD-BLOCK = IF DROP SCB-S-WOULD-BLOCK EXIT THEN
    DUP PT-S-INVALID = IF DROP SCB-S-INVALID EXIT THEN
    DROP SCB-S-SESSION-LOST ;

1  CONSTANT _APTSCB-WA-BOLD
2  CONSTANT _APTSCB-WA-DIM
4  CONSTANT _APTSCB-WA-ITALIC
8  CONSTANT _APTSCB-WA-UNDERLINE
16 CONSTANT _APTSCB-WA-BLINK
32 CONSTANT _APTSCB-WA-REVERSE
64 CONSTANT _APTSCB-WA-STRIKE

: _APTSCB-WIRE-ATTRS  ( cell -- attrs )
    CELL-ATTRS@ _APTSCB-ATTRS !
    0
    _APTSCB-ATTRS @ CELL-A-BOLD AND IF
        _APTSCB-WA-BOLD OR
    THEN
    _APTSCB-ATTRS @ CELL-A-DIM AND IF
        _APTSCB-WA-DIM OR
    THEN
    _APTSCB-ATTRS @ CELL-A-ITALIC AND IF
        _APTSCB-WA-ITALIC OR
    THEN
    _APTSCB-ATTRS @ CELL-A-UNDERLINE AND IF
        _APTSCB-WA-UNDERLINE OR
    THEN
    _APTSCB-ATTRS @ CELL-A-BLINK AND IF
        _APTSCB-WA-BLINK OR
    THEN
    _APTSCB-ATTRS @ CELL-A-REVERSE AND IF
        _APTSCB-WA-REVERSE OR
    THEN
    _APTSCB-ATTRS @ CELL-A-STRIKE AND IF
        _APTSCB-WA-STRIKE OR
    THEN ;

: _APTSCB-CELL-CP  ( cell -- cp )
    CELL-CP@ DUP 0= IF DROP 32 THEN CW-CELL-CP ;

: _APTSCB-BEGIN  ( mode cols rows span-count cell-count context -- status )
    _APTSCB-ADAPTER !
    _APTSCB-CELLS ! _APTSCB-SPANS !
    _APTSCB-ROWS ! _APTSCB-COLS ! _APTSCB-MODE !
    _APTSCB-ADAPTER @ _APTSCB-CONTEXT-VALID? 0= IF
        SCB-S-INVALID EXIT
    THEN
    _APTSCB-ADAPTER @ APTSCB.SESSION @ _APTSCB-SESSION !
    _APTSCB-MODE @ SCB-M-SNAPSHOT = IF
        _APTSCB-COLS @ _APTSCB-ROWS @
        _APTSCB-SPANS @ _APTSCB-CELLS @ _APTSCB-SESSION @
        PT-SNAPSHOT-BEGIN _APTSCB-MAP-STATUS
    ELSE
        _APTSCB-MODE @ SCB-M-DELTA <> IF SCB-S-INVALID EXIT THEN
        _APTSCB-SESSION @ PT-SNAPSHOT-NEEDED? IF
            SCB-S-WOULD-BLOCK EXIT
        THEN
        _APTSCB-COLS @ _APTSCB-ROWS @
        _APTSCB-SPANS @ _APTSCB-CELLS @ _APTSCB-SESSION @
        PT-TX-BEGIN _APTSCB-MAP-STATUS
    THEN ;

: _APTSCB-SPAN  ( cells count row col context -- status )
    _APTSCB-ADAPTER !
    _APTSCB-COL ! _APTSCB-ROW ! _APTSCB-N ! _APTSCB-A !
    _APTSCB-ADAPTER @ _APTSCB-CONTEXT-VALID? 0= IF
        SCB-S-INVALID EXIT
    THEN
    _APTSCB-ADAPTER @ APTSCB.SESSION @ _APTSCB-SESSION !
    _APTSCB-ROW @ _APTSCB-COL @ _APTSCB-N @ _APTSCB-SESSION @
    PT-SPAN-BEGIN _APTSCB-MAP-STATUS
    DUP SCB-S-OK <> IF EXIT THEN DROP
    SCB-S-OK _APTSCB-STATUS !
    _APTSCB-N @ 0 ?DO
        _APTSCB-STATUS @ SCB-S-OK = IF
            _APTSCB-A @ I 8 * + @ _APTSCB-CELL !
            _APTSCB-CELL @ _APTSCB-CELL-CP
            _APTSCB-CELL @ CELL-FG@
            _APTSCB-CELL @ CELL-BG@
            _APTSCB-CELL @ _APTSCB-WIRE-ATTRS
            _APTSCB-SESSION @ PT-CELL _APTSCB-MAP-STATUS
            _APTSCB-STATUS !
        THEN
    LOOP
    _APTSCB-STATUS @ ;

: _APTSCB-CURSOR  ( row col visible context -- status )
    _APTSCB-ADAPTER !
    _APTSCB-ADAPTER @ _APTSCB-CONTEXT-VALID? 0= IF
        2DROP DROP SCB-S-INVALID EXIT
    THEN
    _APTSCB-ADAPTER @ APTSCB.SESSION @ PT-CURSOR
    _APTSCB-MAP-STATUS ;

: _APTSCB-COMMIT  ( context -- status )
    DUP _APTSCB-CONTEXT-VALID? 0= IF DROP SCB-S-INVALID EXIT THEN
    APTSCB.SESSION @ PT-TX-COMMIT _APTSCB-MAP-STATUS ;

: _APTSCB-ABORT  ( context -- )
    DUP _APTSCB-CONTEXT-VALID? 0= IF DROP EXIT THEN
    APTSCB.SESSION @ 0 SWAP PT-TX-ABORT DROP ;

VARIABLE _APTSCBI-SESSION
VARIABLE _APTSCBI-ADAPTER

: _APTSCBI-STORAGE-VALID?  ( -- flag )
    _APTSCBI-SESSION @ 7 AND _APTSCBI-ADAPTER @ 7 AND OR IF 0 EXIT THEN
    _APTSCBI-SESSION @ PT-SESSION-SIZE MSPAN-NONWRAPPING? 0= IF
        0 EXIT
    THEN
    _APTSCBI-ADAPTER @ APTSCB-SIZE MSPAN-NONWRAPPING? 0= IF
        0 EXIT
    THEN
    _APTSCBI-SESSION @ PT-SESSION-SIZE
    _APTSCBI-ADAPTER @ APTSCB-SIZE MSPAN-OVERLAP? 0= ;

\ APTSCB-INIT ( session adapter -- status )
\   Construct from a caller-owned initialized PT session.  No session is
\   created or started implicitly, and loading this module alone emits no
\   bytes.  Binding remains illegal until the session is ACTIVE.
: APTSCB-INIT  ( session adapter -- status )
    _APTSCBI-ADAPTER ! _APTSCBI-SESSION !
    _APTSCBI-SESSION @ 0= _APTSCBI-ADAPTER @ 0= OR IF
        SCB-S-INVALID EXIT
    THEN
    _APTSCBI-STORAGE-VALID? 0= IF SCB-S-INVALID EXIT THEN
    _APTSCBI-ADAPTER @ APTSCB-SIZE 0 FILL
    _APTSCBI-SESSION @ PT-STATE@ PT-ST-LOST = IF
        SCB-S-SESSION-LOST EXIT
    THEN
    _APTSCBI-ADAPTER @
    ['] _APTSCB-BEGIN ['] _APTSCB-SPAN ['] _APTSCB-CURSOR
    ['] _APTSCB-COMMIT ['] _APTSCB-ABORT
    _APTSCBI-ADAPTER @ SCB-INIT DUP SCB-S-OK <> IF EXIT THEN DROP
    _APTSCBI-SESSION @ _APTSCBI-ADAPTER @ APTSCB.SESSION !
    _APTSCB-MAGIC _APTSCBI-ADAPTER @ APTSCB.MAGIC !
    SCB-S-OK ;

\ APTSCB-BIND ( adapter -- status )
\   Bind only an already-live adapter.  SCR-BACKEND! forces the mandatory
\   initial replacement snapshot.
: APTSCB-BIND  ( adapter -- status )
    DUP APTSCB-VALID? 0= IF DROP SCB-S-INVALID EXIT THEN
    DUP APTSCB.SESSION @ PT-ACTIVE? 0= IF
        DROP SCB-S-SESSION-LOST EXIT
    THEN
    DUP APTSCB.SESSION @ PT-OWNS? 0= IF
        DROP SCB-S-SESSION-LOST EXIT
    THEN
    SCR-BACKEND! ;

: _APTSCB-FALLBACK  ( adapter -- )
    DUP SCR-BACKEND@ = IF DROP SCR-ANSI ELSE DROP THEN ;

\ APTSCB-SERVICE ( adapter -- status )
\   Advance the separate PT service outside paint.  Call this before input
\   dispatch and before SCR-FLUSH?.  A soft reset forces a snapshot.  ANSI is
\   rebound only after PT reports its synchronized ANSI state; structural
\   SESSION-LOST retains the binary backend and must await an external reset.
: APTSCB-SERVICE  ( adapter -- status )
    DUP APTSCB-VALID? 0= IF DROP SCB-S-INVALID EXIT THEN
    DUP _APTSCB-ADAPTER !
    APTSCB.SESSION @ DUP _APTSCB-SESSION !
    DUP PT-STATE@ PT-ST-ANSI = IF
        DROP
        PT-STREAM-OWNED? IF SCB-S-WOULD-BLOCK EXIT THEN
        _APTSCB-ADAPTER @ _APTSCB-FALLBACK
        SCB-S-OK EXIT
    THEN
    DUP PT-OWNS? 0= IF DROP SCB-S-SESSION-LOST EXIT THEN
    PT-SERVICE _APTSCB-MAP-STATUS _APTSCB-STATUS !
    _APTSCB-SESSION @ PT-STATE@ PT-ST-ANSI = IF
        PT-STREAM-OWNED? IF SCB-S-WOULD-BLOCK EXIT THEN
        _APTSCB-ADAPTER @ _APTSCB-FALLBACK
        SCB-S-OK EXIT
    THEN
    _APTSCB-SESSION @ PT-STATE@ PT-ST-LOST = IF
        SCB-S-SESSION-LOST EXIT
    THEN
    _APTSCB-STATUS @ SCB-S-OK = IF
        _APTSCB-SESSION @ PT-SNAPSHOT-NEEDED? IF
            _APTSCB-ADAPTER @ SCR-BACKEND@ = IF SCR-FORCE THEN
        THEN
        SCB-S-OK EXIT
    THEN
    _APTSCB-STATUS @ SCB-S-WOULD-BLOCK = IF SCB-S-WOULD-BLOCK EXIT THEN
    _APTSCB-STATUS @ SCB-S-INVALID = IF SCB-S-INVALID EXIT THEN
    SCB-S-SESSION-LOST ;
