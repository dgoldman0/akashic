\ =====================================================================
\  sha3-context.f - Caller-owned incremental SHA3-256
\ =====================================================================
\  This is the storage-neutral SHA3-256 path for data that arrives in
\  independently owned chunks.  Unlike the BIOS SHA3 engine, every bit of
\  operation state lives in one caller-provided context, so independent
\  operations may be interleaved and a PBLOB reader may feed exact bytes
\  without holding global hashing state.
\
\  The context contains only scalar counters, Keccak lanes, a rate buffer,
\  and permutation scratch.  It contains no addresses or callbacks and this
\  module owns no mutable storage.  Public mutations validate all geometry,
\  state, capacity, and alias rules before changing either the context or a
\  digest destination.
\
\  Public API:
\    SHA3-256-CONTEXT-SIZE          ( -- 648 )
\    SHA3-256-CONTEXT-DIGEST-SIZE   ( -- 32 )
\    SHA3-256-CONTEXT-VALID?        ( context -- flag )
\    SHA3-256-CONTEXT-INIT          ( context -- status )
\    SHA3-256-CONTEXT-UPDATE        ( source source-u context -- status )
\    SHA3-256-CONTEXT-FINAL         ( digest context -- status )
\    SHA3-256-CONTEXT-FINAL-COMPARE ( expected context -- match? status )
\
\  FINAL and FINAL-COMPARE are terminal operations.  A structurally valid
\  finalized context remains inspectable, but no update or second final is
\  admitted.  A false match accompanied by S-OK is an ordinary digest
\  mismatch, not an operation failure.
\ =====================================================================

PROVIDED akashic-sha3-context

REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Public constants and status vocabulary
\ =====================================================================

0 CONSTANT SHA3-CONTEXT-S-OK
1 CONSTANT SHA3-CONTEXT-S-INVALID
2 CONSTANT SHA3-CONTEXT-S-STATE
3 CONSTANT SHA3-CONTEXT-S-CAPACITY
4 CONSTANT SHA3-CONTEXT-S-ALIAS

32  CONSTANT SHA3-256-CONTEXT-DIGEST-SIZE
136 CONSTANT _SHA3C-RATE

0x53334354584D454D CONSTANT _SHA3C-MAGIC  \ "S3CTXMEM"

1 CONSTANT _SHA3C-PHASE-ABSORBING
2 CONSTANT _SHA3C-PHASE-FINAL

  0 CONSTANT _SHA3C-MAGIC-OFF
  8 CONSTANT _SHA3C-PHASE-OFF
 16 CONSTANT _SHA3C-BUFFERED-OFF
 24 CONSTANT _SHA3C-TOTAL-OFF
 32 CONSTANT _SHA3C-STATE-OFF
232 CONSTANT _SHA3C-BUFFER-OFF
368 CONSTANT _SHA3C-B-OFF
568 CONSTANT _SHA3C-C-OFF
608 CONSTANT _SHA3C-D-OFF
648 CONSTANT SHA3-256-CONTEXT-SIZE

-1 1 RSHIFT CONSTANT _SHA3C-LENGTH-MAX

: SHA3-CONTEXT-STATUS-VALID?  ( status -- flag )
    DUP SHA3-CONTEXT-S-OK >=
    SWAP SHA3-CONTEXT-S-ALIAS <= AND ;

\ =====================================================================
\  Context fields and bounded byte predicates
\ =====================================================================

: _SHA3C.MAGIC     ( context -- address ) _SHA3C-MAGIC-OFF + ;
: _SHA3C.PHASE     ( context -- address ) _SHA3C-PHASE-OFF + ;
: _SHA3C.BUFFERED  ( context -- address ) _SHA3C-BUFFERED-OFF + ;
: _SHA3C.TOTAL     ( context -- address ) _SHA3C-TOTAL-OFF + ;
: _SHA3C.STATE     ( context -- address ) _SHA3C-STATE-OFF + ;
: _SHA3C.BUFFER    ( context -- address ) _SHA3C-BUFFER-OFF + ;
: _SHA3C.B         ( context -- address ) _SHA3C-B-OFF + ;
: _SHA3C.C         ( context -- address ) _SHA3C-C-OFF + ;
: _SHA3C.D         ( context -- address ) _SHA3C-D-OFF + ;

: _SHA3C-READ-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SHA3C-DIGEST-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _SHA3C-ZERO?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SHA3C-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;

: _SHA3C-PHASE?  ( phase -- flag )
    DUP _SHA3C-PHASE-ABSORBING =
    SWAP _SHA3C-PHASE-FINAL = OR ;

: SHA3-256-CONTEXT-VALID?  ( context -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP SHA3-256-CONTEXT-SIZE
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _SHA3C.MAGIC @ _SHA3C-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SHA3C.PHASE @ _SHA3C-PHASE? 0= IF DROP 0 EXIT THEN
    DUP _SHA3C.TOTAL @ DUP 0<
        SWAP _SHA3C-LENGTH-MAX > OR IF DROP 0 EXIT THEN
    DUP _SHA3C.BUFFERED @ DUP 0<
        SWAP _SHA3C-RATE >= OR IF DROP 0 EXIT THEN
    DUP _SHA3C.PHASE @ _SHA3C-PHASE-ABSORBING = IF
        DUP _SHA3C.TOTAL @ _SHA3C-RATE MOD
        OVER _SHA3C.BUFFERED @ =
        NIP EXIT
    THEN
    DUP _SHA3C.BUFFERED @ 0= 0= IF DROP 0 EXIT THEN
    DUP _SHA3C.BUFFER _SHA3C-RATE _SHA3C-ZERO? 0=
        IF DROP 0 EXIT THEN
    DUP _SHA3C.B _SHA3C-C-OFF _SHA3C-B-OFF -
        _SHA3C-ZERO? 0= IF DROP 0 EXIT THEN
    DUP _SHA3C.C _SHA3C-D-OFF _SHA3C-C-OFF -
        _SHA3C-ZERO? 0= IF DROP 0 EXIT THEN
    _SHA3C.D SHA3-256-CONTEXT-SIZE _SHA3C-D-OFF -
        _SHA3C-ZERO? ;

\ =====================================================================
\  Keccak-f[1600] lane and scratch access
\ =====================================================================

: _SHA3C-S  ( context index -- address )
    8 * SWAP _SHA3C.STATE + ;

: _SHA3C-BL  ( context index -- address )
    8 * SWAP _SHA3C.B + ;

: _SHA3C-CL  ( context index -- address )
    8 * SWAP _SHA3C.C + ;

: _SHA3C-DL  ( context index -- address )
    8 * SWAP _SHA3C.D + ;

: _SHA3C-XOR!  ( value address -- )
    DUP @ ROT XOR SWAP ! ;

: _SHA3C-XOR-C!  ( value address -- )
    DUP C@ ROT XOR SWAP C! ;

: _SHA3C-ROL  ( value count -- rotated )
    DUP 0= IF DROP EXIT THEN
    >R DUP R@ LSHIFT SWAP 64 R> - RSHIFT OR ;

\ Return the Rho rotation and Pi destination for a lane in x+5*y order.
\ CASE words avoid a writable table while keeping the FIPS mapping exact.
: _SHA3C-RHO-PI  ( index -- rotation destination )
    CASE
         0 OF  0  0 ENDOF
         1 OF  1 10 ENDOF
         2 OF 62 20 ENDOF
         3 OF 28  5 ENDOF
         4 OF 27 15 ENDOF
         5 OF 36 16 ENDOF
         6 OF 44  1 ENDOF
         7 OF  6 11 ENDOF
         8 OF 55 21 ENDOF
         9 OF 20  6 ENDOF
        10 OF  3  7 ENDOF
        11 OF 10 17 ENDOF
        12 OF 43  2 ENDOF
        13 OF 25 12 ENDOF
        14 OF 39 22 ENDOF
        15 OF 41 23 ENDOF
        16 OF 45  8 ENDOF
        17 OF 15 18 ENDOF
        18 OF 21  3 ENDOF
        19 OF  8 13 ENDOF
        20 OF 18 14 ENDOF
        21 OF  2 24 ENDOF
        22 OF 61  9 ENDOF
        23 OF 56 19 ENDOF
        24 OF 14  4 ENDOF
        0 0 ROT
    ENDCASE ;

: _SHA3C-RC  ( round -- constant )
    CASE
         0 OF 0x0000000000000001 ENDOF
         1 OF 0x0000000000008082 ENDOF
         2 OF 0x800000000000808A ENDOF
         3 OF 0x8000000080008000 ENDOF
         4 OF 0x000000000000808B ENDOF
         5 OF 0x0000000080000001 ENDOF
         6 OF 0x8000000080008081 ENDOF
         7 OF 0x8000000000008009 ENDOF
         8 OF 0x000000000000008A ENDOF
         9 OF 0x0000000000000088 ENDOF
        10 OF 0x0000000080008009 ENDOF
        11 OF 0x000000008000000A ENDOF
        12 OF 0x000000008000808B ENDOF
        13 OF 0x800000000000008B ENDOF
        14 OF 0x8000000000008089 ENDOF
        15 OF 0x8000000000008003 ENDOF
        16 OF 0x8000000000008002 ENDOF
        17 OF 0x8000000000000080 ENDOF
        18 OF 0x000000000000800A ENDOF
        19 OF 0x800000008000000A ENDOF
        20 OF 0x8000000080008081 ENDOF
        21 OF 0x8000000000008080 ENDOF
        22 OF 0x0000000080000001 ENDOF
        23 OF 0x8000000080008008 ENDOF
        0 SWAP
    ENDCASE ;

: _SHA3C-CHI-NEXT1  ( index -- next-index )
    DUP 5 MOD 4 = IF 4 - ELSE 1+ THEN ;

: _SHA3C-CHI-NEXT2  ( index -- next-index )
    DUP 5 MOD 3 >= IF 3 - ELSE 2 + THEN ;

\ Theta computes five column parities, their five diffusion lanes, and
\ applies those lanes to all 25 state words.
: _SHA3C-THETA  ( context -- )
    5 0 DO
        DUP I      _SHA3C-S @
        OVER I  5 + _SHA3C-S @ XOR
        OVER I 10 + _SHA3C-S @ XOR
        OVER I 15 + _SHA3C-S @ XOR
        OVER I 20 + _SHA3C-S @ XOR
        OVER I _SHA3C-CL !
    LOOP
    5 0 DO
        DUP I 4 + 5 MOD _SHA3C-CL @
        OVER I 1+ 5 MOD _SHA3C-CL @ 1 _SHA3C-ROL XOR
        OVER I _SHA3C-DL !
    LOOP
    25 0 DO
        DUP I 5 MOD _SHA3C-DL @
        OVER I _SHA3C-S _SHA3C-XOR!
    LOOP
    DROP ;

: _SHA3C-RHO-PI-STEP  ( context -- )
    25 0 DO
        DUP I _SHA3C-S @
        I _SHA3C-RHO-PI
        >R _SHA3C-ROL
        OVER R> _SHA3C-BL !
    LOOP
    DROP ;

: _SHA3C-CHI  ( context -- )
    25 0 DO
        DUP I _SHA3C-BL @
        OVER I _SHA3C-CHI-NEXT1 _SHA3C-BL @ INVERT
        2 PICK I _SHA3C-CHI-NEXT2 _SHA3C-BL @
        AND XOR
        OVER I _SHA3C-S !
    LOOP
    DROP ;

: _SHA3C-PERMUTE  ( context -- )
    24 0 DO
        DUP _SHA3C-THETA
        DUP _SHA3C-RHO-PI-STEP
        DUP _SHA3C-CHI
        I _SHA3C-RC OVER 0 _SHA3C-S _SHA3C-XOR!
    LOOP
    DROP ;

\ SHA3 maps each rate byte to the little-endian byte view of the first
\ seventeen Keccak lanes.  Megapad-64 cells use that byte order, so exact
\ byte absorption followed by cell permutation implements the mapping
\ without alignment or partial-cell reads.
: _SHA3C-ABSORB-BLOCK  ( context -- )
    _SHA3C-RATE 0 DO
        DUP _SHA3C.BUFFER I + C@
        OVER _SHA3C.STATE I + _SHA3C-XOR-C!
    LOOP
    _SHA3C-PERMUTE ;

\ =====================================================================
\  Public initialization and incremental update
\ =====================================================================

: SHA3-256-CONTEXT-INIT  ( context -- status )
    DUP 0= IF DROP SHA3-CONTEXT-S-INVALID EXIT THEN
    DUP SHA3-256-CONTEXT-SIZE
        MSPAN-NONWRAPPING? 0= IF DROP SHA3-CONTEXT-S-INVALID EXIT THEN
    DUP SHA3-256-CONTEXT-SIZE 0 FILL
    _SHA3C-MAGIC OVER _SHA3C.MAGIC !
    _SHA3C-PHASE-ABSORBING SWAP _SHA3C.PHASE !
    SHA3-CONTEXT-S-OK ;

: _SHA3C-UPDATE-RUN  ( source source-u context -- )
    OVER OVER _SHA3C.TOTAL +!
    SWAP 0 ?DO
        OVER I + C@
        OVER _SHA3C.BUFFERED @
        2 PICK _SHA3C.BUFFER +
        C!
        1 OVER _SHA3C.BUFFERED +!
        DUP _SHA3C.BUFFERED @ _SHA3C-RATE = IF
            DUP _SHA3C-ABSORB-BLOCK
            DUP _SHA3C.BUFFER _SHA3C-RATE 0 FILL
            0 OVER _SHA3C.BUFFERED !
        THEN
    LOOP
    2DROP ;

: SHA3-256-CONTEXT-UPDATE  ( source source-u context -- status )
    DUP SHA3-256-CONTEXT-VALID? 0= IF
        _SHA3C-DROP3 SHA3-CONTEXT-S-INVALID EXIT
    THEN
    DUP _SHA3C.PHASE @ _SHA3C-PHASE-ABSORBING <> IF
        _SHA3C-DROP3 SHA3-CONTEXT-S-STATE EXIT
    THEN
    2 PICK 2 PICK _SHA3C-READ-SPAN? 0= IF
        _SHA3C-DROP3 SHA3-CONTEXT-S-INVALID EXIT
    THEN
    2 PICK 2 PICK 2 PICK SHA3-256-CONTEXT-SIZE
        MSPAN-OVERLAP? IF
        _SHA3C-DROP3 SHA3-CONTEXT-S-ALIAS EXIT
    THEN
    OVER
    OVER _SHA3C.TOTAL @ _SHA3C-LENGTH-MAX SWAP -
    U> IF
        _SHA3C-DROP3 SHA3-CONTEXT-S-CAPACITY EXIT
    THEN
    _SHA3C-UPDATE-RUN
    SHA3-CONTEXT-S-OK ;

\ =====================================================================
\  Terminal padding, publication, and comparison
\ =====================================================================

: _SHA3C-FINALIZE  ( context -- )
    DUP _SHA3C.BUFFERED @
    OVER _SHA3C.BUFFER
    OVER +
    SWAP _SHA3C-RATE SWAP -
    0 FILL

    DUP _SHA3C.BUFFERED @ OVER _SHA3C.BUFFER +
    0x06 SWAP C!
    DUP _SHA3C.BUFFER _SHA3C-RATE 1- +
    DUP C@ 0x80 OR SWAP C!

    DUP _SHA3C-ABSORB-BLOCK
    DUP _SHA3C.BUFFER _SHA3C-RATE 0 FILL
    DUP _SHA3C.B
        SHA3-256-CONTEXT-SIZE _SHA3C-B-OFF - 0 FILL
    0 OVER _SHA3C.BUFFERED !
    _SHA3C-PHASE-FINAL SWAP _SHA3C.PHASE ! ;

: _SHA3C-FINAL-GEOMETRY
  ( digest-or-expected context -- status )
    DUP SHA3-256-CONTEXT-VALID? 0= IF
        2DROP SHA3-CONTEXT-S-INVALID EXIT
    THEN
    DUP _SHA3C.PHASE @ _SHA3C-PHASE-ABSORBING <> IF
        2DROP SHA3-CONTEXT-S-STATE EXIT
    THEN
    OVER SHA3-256-CONTEXT-DIGEST-SIZE
        _SHA3C-DIGEST-SPAN? 0= IF
        2DROP SHA3-CONTEXT-S-INVALID EXIT
    THEN
    OVER SHA3-256-CONTEXT-DIGEST-SIZE
    2 PICK SHA3-256-CONTEXT-SIZE MSPAN-OVERLAP? IF
        2DROP SHA3-CONTEXT-S-ALIAS EXIT
    THEN
    2DROP SHA3-CONTEXT-S-OK ;

: SHA3-256-CONTEXT-FINAL  ( digest context -- status )
    2DUP _SHA3C-FINAL-GEOMETRY DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    DUP _SHA3C-FINALIZE
    DUP _SHA3C.STATE
    2 PICK SHA3-256-CONTEXT-DIGEST-SIZE MOVE
    2DROP SHA3-CONTEXT-S-OK ;

: _SHA3C-DIGEST=  ( expected context -- flag )
    0
    SHA3-256-CONTEXT-DIGEST-SIZE 0 DO
        2 PICK I + C@
        2 PICK _SHA3C.STATE I + C@
        XOR OR
    LOOP
    0= >R 2DROP R> ;

: SHA3-256-CONTEXT-FINAL-COMPARE
  ( expected context -- match? status )
    2DUP _SHA3C-FINAL-GEOMETRY DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    DROP
    DUP _SHA3C-FINALIZE
    _SHA3C-DIGEST=
    SHA3-CONTEXT-S-OK ;

\ The permutation and context layout are deliberately exact: one lane is
\ one 64-bit cell, the state is 25 lanes, the SHA3-256 rate is 136 bytes,
\ and all remaining bytes are caller-owned scratch.
: _SHA3C-GEOMETRY-ABORT  ( -- )
    ." SHA3 context geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _SHA3C-GEOMETRY-ABORT
[THEN]

_SHA3C-STATE-OFF 200 + _SHA3C-BUFFER-OFF <> [IF]
    _SHA3C-GEOMETRY-ABORT
[THEN]

_SHA3C-BUFFER-OFF _SHA3C-RATE + _SHA3C-B-OFF <> [IF]
    _SHA3C-GEOMETRY-ABORT
[THEN]

_SHA3C-B-OFF 200 + _SHA3C-C-OFF <> [IF]
    _SHA3C-GEOMETRY-ABORT
[THEN]

_SHA3C-C-OFF 40 + _SHA3C-D-OFF <> [IF]
    _SHA3C-GEOMETRY-ABORT
[THEN]

_SHA3C-D-OFF 40 + SHA3-256-CONTEXT-SIZE <> [IF]
    _SHA3C-GEOMETRY-ABORT
[THEN]
