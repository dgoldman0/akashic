\ =================================================================
\  stark-air.f  —  STARK AIR Constraint Descriptor
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: AIR-
\  Depends on: baby-bear.f
\
\  Algebraic Intermediate Representation for STARK constraint
\  systems.  Builds a compact descriptor that a generic STARK
\  prover/verifier interprets at runtime.
\
\  Public API — constants:
\   AIR-ADD        ( -- 0 )   transition op: addition
\   AIR-SUB        ( -- 1 )   transition op: subtraction
\   AIR-MUL        ( -- 2 )   transition op: multiplication
\
\  Public API — builder:
\   AIR-BEGIN      ( n-cols -- )
\   AIR-TRANS      ( type colA offA colB offB colR offR -- )
\   AIR-BOUNDARY   ( col row val -- )
\   AIR-END        ( -- air-addr )
\
\  Public API — queries:
\   AIR-N-COLS     ( air -- n )
\   AIR-N-TRANS    ( air -- n )
\   AIR-N-BOUND    ( air -- n )
\   AIR-MAX-OFF    ( air -- n )
\
\  Public API — evaluation:
\   AIR-EVAL-TRANS   ( air cols row -- residual )
\   AIR-CHECK-BOUND  ( air cols -- flag )
\
\  Descriptor layout (flat byte buffer):
\    Header 8 bytes:
\      +0 u16 n_cols  +2 u16 n_trans  +4 u16 n_bound  +6 u16 rsvd
\    Transition entries (8 bytes each):
\      +0 u8 type  +1 u8 colA  +2 u8 offA  +3 u8 colB
\      +4 u8 offB  +5 u8 colR  +6 u8 offR  +7 u8 rsvd
\    Boundary entries (8 bytes each):
\      +0 u8 col  +1 u8 rsvd  +2 u16 row  +4 u32 value
\
\  cols is a cell array of buffer base addresses.
\  trace[col][row] read as 32-bit LE at cols[col] + row*4.
\
\  Not reentrant.
\ =================================================================

REQUIRE baby-bear.f

PROVIDED akashic-stark-air

\ =====================================================================
\  Constants
\ =====================================================================

0 CONSTANT AIR-ADD
1 CONSTANT AIR-SUB
2 CONSTANT AIR-MUL

\ =====================================================================
\  16-bit LE helpers
\ =====================================================================

: _AIR-W16!  ( val addr -- )
    OVER OVER C!  SWAP 8 RSHIFT SWAP 1 + C! ;

: _AIR-W16@  ( addr -- val )
    DUP C@  SWAP 1 + C@ 8 LSHIFT OR ;

\ =====================================================================
\  Builder state
\ =====================================================================

CREATE _AIR-BUF 1024 ALLOT
VARIABLE _AIR-NCOLS
VARIABLE _AIR-NTRANS
VARIABLE _AIR-NBOUND

: AIR-BEGIN  ( n-cols -- )
    _AIR-NCOLS !
    0 _AIR-NTRANS !
    0 _AIR-NBOUND !
    _AIR-BUF 1024 0 FILL ;

\ =====================================================================
\  AIR-TRANS  ( type colA offA colB offB colR offR -- )
\ =====================================================================

VARIABLE _AT-TYPE
VARIABLE _AT-CA
VARIABLE _AT-OA
VARIABLE _AT-CB
VARIABLE _AT-OB
VARIABLE _AT-CR
VARIABLE _AT-OR

: AIR-TRANS  ( type colA offA colB offB colR offR -- )
    _AT-OR !  _AT-CR !  _AT-OB !  _AT-CB !
    _AT-OA !  _AT-CA !  _AT-TYPE !
    _AIR-NTRANS @ 8 * 8 + _AIR-BUF +
    DUP _AT-TYPE @ SWAP C!
    DUP _AT-CA @   SWAP 1 + C!
    DUP _AT-OA @   SWAP 2 + C!
    DUP _AT-CB @   SWAP 3 + C!
    DUP _AT-OB @   SWAP 4 + C!
    DUP _AT-CR @   SWAP 5 + C!
        _AT-OR @   SWAP 6 + C!
    _AIR-NTRANS @ 1 + _AIR-NTRANS ! ;

\ =====================================================================
\  AIR-BOUNDARY  ( col row val -- )
\ =====================================================================

VARIABLE _AB-COL
VARIABLE _AB-ROW
VARIABLE _AB-VAL

: AIR-BOUNDARY  ( col row val -- )
    _AB-VAL !  _AB-ROW !  _AB-COL !
    _AIR-NTRANS @ _AIR-NBOUND @ + 8 * 8 + _AIR-BUF +
    DUP _AB-COL @ SWAP C!
    DUP _AB-ROW @ SWAP 2 + _AIR-W16!
        _AB-VAL @  SWAP 4 + BB-W32!
    _AIR-NBOUND @ 1 + _AIR-NBOUND ! ;

\ =====================================================================
\  AIR-END  ( -- air-addr )
\ =====================================================================

VARIABLE _AE-SZ
VARIABLE _AE-DST

: AIR-END  ( -- air-addr )
    _AIR-NCOLS @  _AIR-BUF      _AIR-W16!
    _AIR-NTRANS @ _AIR-BUF 2 +  _AIR-W16!
    _AIR-NBOUND @ _AIR-BUF 4 +  _AIR-W16!
    0             _AIR-BUF 6 +  _AIR-W16!
    _AIR-NTRANS @ _AIR-NBOUND @ + 8 * 8 +  _AE-SZ !
    HERE _AE-DST !
    _AE-SZ @ ALLOT
    _AIR-BUF _AE-DST @ _AE-SZ @ CMOVE
    _AE-DST @ ;

\ =====================================================================
\  Query words
\ =====================================================================

: AIR-N-COLS   ( air -- n )  _AIR-W16@ ;
: AIR-N-TRANS  ( air -- n )  2 + _AIR-W16@ ;
: AIR-N-BOUND  ( air -- n )  4 + _AIR-W16@ ;

VARIABLE _AM-MAX
VARIABLE _AM-J
VARIABLE _AM-AIR
VARIABLE _AM-ENT

: AIR-MAX-OFF  ( air -- n )
    _AM-AIR !
    0 _AM-MAX !  0 _AM-J !
    BEGIN _AM-J @ _AM-AIR @ AIR-N-TRANS < WHILE
        _AM-J @ 8 * 8 + _AM-AIR @ + _AM-ENT !
        _AM-ENT @ 2 + C@  _AM-MAX @ MAX  _AM-MAX !
        _AM-ENT @ 4 + C@  _AM-MAX @ MAX  _AM-MAX !
        _AM-ENT @ 6 + C@  _AM-MAX @ MAX  _AM-MAX !
        _AM-J @ 1 + _AM-J !
    REPEAT
    _AM-MAX @ ;

\ =====================================================================
\  Trace read helper
\ =====================================================================

: _AIR-TRACE@  ( row col cols -- val )
    SWAP 8 * + @        \ base = cols[col]
    SWAP 4 * +           \ base + row*4
    BB-W32@ ;

\ =====================================================================
\  Operation dispatch
\ =====================================================================

: _AIR-OP  ( valA valB type -- result )
    DUP 0 = IF DROP BB+ EXIT THEN
    DUP 1 = IF DROP BB- EXIT THEN
        2 = IF BB*      EXIT THEN
    DROP DROP 0 ;

\ =====================================================================
\  AIR-EVAL-TRANS  ( air cols row -- residual )
\ =====================================================================

VARIABLE _AET-AIR
VARIABLE _AET-COLS
VARIABLE _AET-ROW
VARIABLE _AET-SUM
VARIABLE _AET-J
VARIABLE _AET-ENT
VARIABLE _AET-VA
VARIABLE _AET-VB
VARIABLE _AET-VR

: AIR-EVAL-TRANS  ( air cols row -- residual )
    _AET-ROW !  _AET-COLS !  _AET-AIR !
    0 _AET-SUM !  0 _AET-J !
    BEGIN _AET-J @ _AET-AIR @ AIR-N-TRANS < WHILE
        _AET-J @ 8 * 8 + _AET-AIR @ +  _AET-ENT !
        \ valA = trace[row+offA][colA]
        _AET-ROW @  _AET-ENT @ 2 + C@  +
        _AET-ENT @ 1 + C@
        _AET-COLS @
        _AIR-TRACE@  _AET-VA !
        \ valB = trace[row+offB][colB]
        _AET-ROW @  _AET-ENT @ 4 + C@  +
        _AET-ENT @ 3 + C@
        _AET-COLS @
        _AIR-TRACE@  _AET-VB !
        \ valR = trace[row+offR][colR]
        _AET-ROW @  _AET-ENT @ 6 + C@  +
        _AET-ENT @ 5 + C@
        _AET-COLS @
        _AIR-TRACE@  _AET-VR !
        \ residual = valR - op(valA, valB)
        _AET-VA @  _AET-VB @  _AET-ENT @ C@  _AIR-OP
        _AET-VR @ SWAP BB-
        _AET-SUM @ BB+  _AET-SUM !
        _AET-J @ 1 + _AET-J !
    REPEAT
    _AET-SUM @ ;

\ =====================================================================
\  AIR-CHECK-BOUND  ( air cols -- flag )
\ =====================================================================

VARIABLE _ACB-AIR
VARIABLE _ACB-COLS
VARIABLE _ACB-J
VARIABLE _ACB-OK
VARIABLE _ACB-ENT

: AIR-CHECK-BOUND  ( air cols -- flag )
    _ACB-COLS !  _ACB-AIR !
    -1 _ACB-OK !  0 _ACB-J !
    BEGIN _ACB-J @ _ACB-AIR @ AIR-N-BOUND < WHILE
        _ACB-AIR @ AIR-N-TRANS  _ACB-J @ +  8 *  8 +
        _ACB-AIR @ +  _ACB-ENT !
        \ actual = trace[row][col]
        _ACB-ENT @ 2 + _AIR-W16@
        _ACB-ENT @ C@
        _ACB-COLS @
        _AIR-TRACE@
        \ expected
        _ACB-ENT @ 4 + BB-W32@
        <> IF 0 _ACB-OK ! THEN
        _ACB-J @ 1 + _ACB-J !
    REPEAT
    _ACB-OK @ ;
