\ chain.f — Audio effect-chain routing
\ Part of Akashic audio library for Megapad-64 / KDOS
\
\ An ordered list of processing slots.  Each slot holds an
\ execution token for a ( buf desc -- ) effect-process word,
\ a descriptor pointer, and a bypass flag.  CHAIN-PROCESS runs
\ a PCM buffer through every non-bypassed slot in order.
\
\ Maximum 8 slots per chain (practical limit for real-time audio).
\
\ Memory: chain descriptor on heap (16 bytes) + slot array
\ (24 bytes per slot).
\
\ Prefix: CHAIN-   (public API)
\         _CH-     (internals)
\
\ Load with:   REQUIRE audio/chain.f
\
\ === Public API ===
\   CHAIN-CREATE   ( n-slots -- chain )
\   CHAIN-FREE     ( chain -- )
\   CHAIN-SET!     ( xt desc slot# chain -- )
\   CHAIN-BYPASS!  ( flag slot# chain -- )
\   CHAIN-PROCESS  ( buf chain -- )
\   CHAIN-CLEAR    ( chain -- )
\   CHAIN-N        ( chain -- n )

REQUIRE audio/pcm.f

PROVIDED akashic-audio-chain

\ =====================================================================
\  Chain descriptor layout  (2 cells = 16 bytes)
\ =====================================================================
\
\  +0   n-slots   Maximum number of slots (integer)
\  +8   slots     Pointer to slot array

16 CONSTANT CHAIN-DESC-SIZE

\ =====================================================================
\  Slot layout  (3 cells = 24 bytes per slot)
\ =====================================================================
\
\  +0   process-xt    Execution token for ( buf desc -- ) or 0
\  +8   desc          Effect descriptor pointer
\  +16  bypass        0 = active, 1 = bypassed

24 CONSTANT _CH-SLOT-SIZE

\ =====================================================================
\  Field accessors
\ =====================================================================

: CH.N      ( chain -- addr )  ;           \ n-slots at offset 0
: CH.SLOTS  ( chain -- addr )  8 + ;       \ slot array pointer

: _CH.XT    ( slot -- addr )  ;            \ process-xt at offset 0
: _CH.DESC  ( slot -- addr )  8 + ;        \ desc
: _CH.BYP   ( slot -- addr )  16 + ;       \ bypass flag

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _CH-TMP    \ general purpose
VARIABLE _CH-BUF    \ buffer during CHAIN-PROCESS
VARIABLE _CH-SLOT   \ slot pointer during iteration
VARIABLE _CH-CHAIN  \ chain pointer during PROCESS / CLEAR

\ =====================================================================
\  Internal: compute slot address
\ =====================================================================

: _CH-SLOT-ADDR  ( slot# chain -- slot-addr )
    CH.SLOTS @                        \ slots-base
    SWAP _CH-SLOT-SIZE * + ;          \ slots-base + slot# * 24

\ =====================================================================
\  CHAIN-CREATE — Allocate effect chain
\ =====================================================================
\  ( n-slots -- chain )

: CHAIN-CREATE  ( n-slots -- chain )
    DUP 8 > IF DROP 8 THEN           \ clamp to max 8
    DUP 1 < IF DROP 1 THEN           \ at least 1
    _CH-TMP !

    \ Allocate chain descriptor
    CHAIN-DESC-SIZE ALLOCATE
    0<> ABORT" CHAIN-CREATE: desc alloc failed"
    _CH-CHAIN !

    _CH-TMP @ _CH-CHAIN @ CH.N !

    \ Allocate slot array
    _CH-TMP @ _CH-SLOT-SIZE * ALLOCATE
    0<> ABORT" CHAIN-CREATE: slot alloc failed"
    _CH-CHAIN @ CH.SLOTS !

    \ Zero all slots (xt=0 means empty)
    _CH-TMP @ 0 DO
        I _CH-CHAIN @ _CH-SLOT-ADDR
        0 OVER _CH.XT  !
        0 OVER _CH.DESC !
        0 SWAP _CH.BYP  !
    LOOP

    _CH-CHAIN @ ;

\ =====================================================================
\  CHAIN-FREE — Free chain (does NOT free individual effects)
\ =====================================================================

: CHAIN-FREE  ( chain -- )
    DUP CH.SLOTS @ FREE
    FREE ;

\ =====================================================================
\  CHAIN-N — Number of slots
\ =====================================================================

: CHAIN-N  ( chain -- n )  CH.N @ ;

\ =====================================================================
\  CHAIN-SET! — Install effect at slot
\ =====================================================================
\  ( xt desc slot# chain -- )
\  Stores the process-xt and descriptor at the given slot,
\  and marks the slot as active (bypass = 0).

: CHAIN-SET!  ( xt desc slot# chain -- )
    _CH-SLOT-ADDR _CH-SLOT !          \ resolve slot address
    _CH-SLOT @ _CH.DESC !             \ store desc
    _CH-SLOT @ _CH.XT   ! ;           \ store xt

\ =====================================================================
\  CHAIN-BYPASS! — Bypass or enable a slot
\ =====================================================================
\  ( flag slot# chain -- )
\     flag = 1  ->  bypass (skip during CHAIN-PROCESS)
\     flag = 0  ->  enable (process normally)

: CHAIN-BYPASS!  ( flag slot# chain -- )
    _CH-SLOT-ADDR _CH.BYP ! ;

\ =====================================================================
\  CHAIN-CLEAR — Remove all effects from chain
\ =====================================================================

: CHAIN-CLEAR  ( chain -- )
    _CH-CHAIN !
    _CH-CHAIN @ CH.N @ 0 DO
        I _CH-CHAIN @ _CH-SLOT-ADDR
        0 OVER _CH.XT  !
        0 OVER _CH.DESC !
        0 SWAP _CH.BYP  !
    LOOP ;

\ =====================================================================
\  CHAIN-PROCESS — Run buffer through all active slots
\ =====================================================================
\  ( buf chain -- )
\  For each slot in order: if xt != 0 and bypass = 0,
\  call  xt  as  ( buf desc -- ) via EXECUTE.

: CHAIN-PROCESS  ( buf chain -- )
    _CH-CHAIN !
    _CH-BUF !

    _CH-CHAIN @ CH.N @ 0 DO
        I _CH-CHAIN @ _CH-SLOT-ADDR _CH-SLOT !

        _CH-SLOT @ _CH.XT @ DUP 0<> IF
            _CH-SLOT @ _CH.BYP @ 0= IF
                _CH-BUF @                 ( xt buf )
                _CH-SLOT @ _CH.DESC @     ( xt buf desc )
                ROT                       ( buf desc xt )
                EXECUTE                   ( -- effect consumes buf desc )
            ELSE
                DROP                      \ bypassed, drop xt
            THEN
        ELSE
            DROP                          \ empty slot, drop 0
        THEN
    LOOP ;
