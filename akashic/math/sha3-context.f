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
\  and reserved zeroed workspace fixed by its stable 648-byte geometry.  It
\  contains no addresses or callbacks and this module owns no mutable storage.
\  Public mutations validate all geometry, state, capacity, and alias rules
\  before changing either the context or a digest destination.
\
\  Public API:
\    SHA3-256-CONTEXT-SIZE          ( -- 648 )
\    SHA3-256-CONTEXT-DIGEST-SIZE   ( -- 32 )
\    SHA3-256-CONTEXT-VALID?        ( context -- flag )
\    SHA3-256-CONTEXT-INIT          ( context -- status )
\    SHA3-256-CONTEXT-UPDATE        ( source source-u context -- status )
\    SHA3-256-CONTEXT-FINAL         ( digest context -- status )
\    SHA3-256-CONTEXT-FINAL-COMPARE ( expected context -- match? status )
\    SHA3-CONTEXT-S-HARDWARE        ( -- 5 )
\
\  FINAL and FINAL-COMPARE are terminal operations.  A structurally valid
\  finalized context remains inspectable, but no update or second final is
\  admitted.  A false match accompanied by S-OK is an ordinary digest
\  mismatch, not an operation failure.  A checked KECCAK-F1600 failure returns
\  SHA3-CONTEXT-S-HARDWARE, wipes the complete context so it is no longer
\  structurally valid, and never publishes a digest.
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
5 CONSTANT SHA3-CONTEXT-S-HARDWARE

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
    SWAP SHA3-CONTEXT-S-HARDWARE <= AND ;

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
\  Checked Keccak-f[1600] service
\ =====================================================================

: _SHA3C-XOR-C!  ( value address -- )
    DUP C@ ROT XOR SWAP C! ;

\ A checked raw-permutation failure leaves the 200-byte state unchanged, but
\ an UPDATE may already have committed earlier blocks.  Wipe the complete
\ context so it cannot remain structurally valid or later publish a digest.
\ The context API reports one distinct hardware-service status; the detailed
\ checked-crypto status remains available at the lower KECCAK-F1600 boundary.
: _SHA3C-PERMUTE  ( context -- status )
    DUP _SHA3C.STATE KECCAK-F1600
    DUP IF
        SWAP DUP SHA3-256-CONTEXT-SIZE 0 FILL DROP
        DROP SHA3-CONTEXT-S-HARDWARE
    ELSE
        NIP
    THEN ;

\ SHA3 maps each rate byte to the little-endian byte view of the first
\ seventeen Keccak lanes.  Megapad-64 cells use that byte order, so exact
\ byte absorption followed by cell permutation implements the mapping
\ without alignment or partial-cell reads.
: _SHA3C-ABSORB-BLOCK  ( context -- status )
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

: _SHA3C-UPDATE-RUN  ( source source-u context -- status )
    OVER OVER _SHA3C.TOTAL +!
    SWAP 0 ?DO
        OVER I + C@
        OVER _SHA3C.BUFFERED @
        2 PICK _SHA3C.BUFFER +
        C!
        1 OVER _SHA3C.BUFFERED +!
        DUP _SHA3C.BUFFERED @ _SHA3C-RATE = IF
            DUP _SHA3C-ABSORB-BLOCK
            DUP IF NIP NIP UNLOOP EXIT THEN DROP
            DUP _SHA3C.BUFFER _SHA3C-RATE 0 FILL
            0 OVER _SHA3C.BUFFERED !
        THEN
    LOOP
    2DROP SHA3-CONTEXT-S-OK ;

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
    _SHA3C-UPDATE-RUN ;

\ =====================================================================
\  Terminal padding, publication, and comparison
\ =====================================================================

: _SHA3C-FINALIZE  ( context -- status )
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
    DUP IF NIP EXIT THEN DROP
    DUP _SHA3C.BUFFER _SHA3C-RATE 0 FILL
    DUP _SHA3C.B
        SHA3-256-CONTEXT-SIZE _SHA3C-B-OFF - 0 FILL
    0 OVER _SHA3C.BUFFERED !
    _SHA3C-PHASE-FINAL SWAP _SHA3C.PHASE !
    SHA3-CONTEXT-S-OK ;

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
        NIP NIP EXIT
    THEN
    DROP
    DUP _SHA3C-FINALIZE
    DUP IF NIP NIP EXIT THEN DROP
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
    0= NIP NIP ;

: SHA3-256-CONTEXT-FINAL-COMPARE
  ( expected context -- match? status )
    2DUP _SHA3C-FINAL-GEOMETRY DUP IF
        NIP NIP 0 SWAP EXIT
    THEN
    DROP
    DUP _SHA3C-FINALIZE
    DUP IF NIP NIP 0 SWAP EXIT THEN DROP
    _SHA3C-DIGEST=
    SHA3-CONTEXT-S-OK ;

\ The permutation and context layout are deliberately exact: one lane is
\ one 64-bit cell, the state is 25 lanes, the SHA3-256 rate is 136 bytes,
\ and all remaining bytes are caller-owned reserved workspace.  Keeping this
\ geometry preserves validation and storage contracts while the software
\ round implementation itself has been removed.
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
