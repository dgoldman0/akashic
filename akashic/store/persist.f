\ =================================================================
\  persist.f  —  Chain Persistence (Block Log + State Snapshot)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PST-  / _PST-
\  Depends on: block.f state.f guard.f
\
\  Append-only block log in extended memory (XMEM).
\  Each entry: [cell: cbor_len] [cbor_len bytes of encoded block]
\
\  On restart, replay saved blocks via:
\   CHAIN-INIT   (genesis)
\   PST-REPLAY   (blocks 1..N)
\
\  Public API:
\   PST-INIT        ( -- )          allocate XMEM regions
\   PST-SAVE-BLOCK  ( blk -- flag ) encode + append to block log
\   PST-LOAD-BLOCK  ( idx blk -- flag ) decode block N from log
\   PST-BLOCK-COUNT ( -- n )        number of saved blocks
\   PST-CLEAR       ( -- )          reset log (discard all)
\   PST-SAVE-STATE  ( dst -- )      snapshot state+chain metadata
\   PST-LOAD-STATE  ( src -- )      restore state+chain metadata
\ =================================================================

REQUIRE ../store/block.f
REQUIRE ../store/state.f
REQUIRE ../concurrency/guard.f

PROVIDED akashic-persist

\ =====================================================================
\  1. Constants
\ =====================================================================

1048576 CONSTANT _PST-LOG-MAX           \ 1 MB max for block log
16384   CONSTANT _PST-ENC-SZ            \ per-block encode buffer

\ =====================================================================
\  2. Storage
\ =====================================================================

VARIABLE _PST-LOG-BASE                  \ XMEM base of block log
VARIABLE _PST-LOG-POS                   \ current write offset (bytes)
VARIABLE _PST-COUNT                     \ number of blocks in log

CREATE _PST-BUF _PST-ENC-SZ ALLOT      \ temp encode/decode buffer

\ =====================================================================
\  3. PST-INIT — allocate XMEM
\ =====================================================================

: PST-INIT  ( -- )
    _PST-LOG-MAX XMEM-ALLOT _PST-LOG-BASE !
    0 _PST-LOG-POS !
    0 _PST-COUNT ! ;

\ =====================================================================
\  4. PST-SAVE-BLOCK — encode block, append to log
\ =====================================================================

: PST-SAVE-BLOCK  ( blk -- flag )
    \ Encode block to temp buffer
    _PST-BUF _PST-ENC-SZ BLK-ENCODE   ( len )
    DUP 0= IF DROP 0 EXIT THEN
    \ Check remaining space (need len + 8 for length cell)
    DUP 8 + _PST-LOG-POS @ +
    _PST-LOG-MAX > IF DROP 0 EXIT THEN
    \ Save len on return stack for position advance
    DUP >R                             ( len  R: len )
    \ Compute destination address
    _PST-LOG-BASE @ _PST-LOG-POS @ +  ( len dest )
    \ Store length prefix
    2DUP !                             ( len dest )
    \ Copy encoded data after the length cell
    8 + _PST-BUF SWAP ROT CMOVE       ( -- )
    \ Advance position by 8 + len
    R> 8 + _PST-LOG-POS +!
    1 _PST-COUNT +!
    -1 ;

\ =====================================================================
\  5. PST-LOAD-BLOCK — read block N from log, decode into blk
\ =====================================================================

: PST-LOAD-BLOCK  ( idx blk -- flag )
    SWAP                               ( blk idx )
    DUP _PST-COUNT @ >= IF 2DROP 0 EXIT THEN
    \ Walk log to find the Nth entry
    _PST-LOG-BASE @ >R                 ( blk idx  R: cursor )
    0 ?DO
        R@ @                           \ length of this entry
        8 +                            \ skip cell + data
        R> + >R                        \ advance cursor
    LOOP
    \ R now points at the target entry
    R@ @                               ( blk len )
    R> 8 +                             ( blk len data-addr )
    ROT                                ( len data-addr blk )
    >R                                 ( len data-addr  R: blk )
    SWAP                               ( data-addr len )
    R> BLK-DECODE ;                    ( flag )

\ =====================================================================
\  6. PST-BLOCK-COUNT / PST-CLEAR
\ =====================================================================

: PST-BLOCK-COUNT  ( -- n )  _PST-COUNT @ ;

: PST-CLEAR  ( -- )
    0 _PST-LOG-POS !
    0 _PST-COUNT ! ;

\ =====================================================================
\  7. PST-SAVE-STATE / PST-LOAD-STATE
\ =====================================================================
\
\  Save/load state snapshot + chain height to a caller-supplied buffer.
\  Layout:  [ST-SNAPSHOT-SIZE bytes] [8-byte chain-height cell]
\  Total:   ST-SNAPSHOT-SIZE + 8 bytes

: PST-SAVE-STATE  ( dst -- )
    DUP ST-SNAPSHOT                    \ save account table + count
    ST-SNAPSHOT-SIZE + CHAIN-HEIGHT SWAP ! ; \ save chain height

: PST-LOAD-STATE  ( src -- )
    DUP ST-RESTORE                     \ restore account table + count
    ST-SNAPSHOT-SIZE + @ DROP ;         \ read height (informational)

\ =====================================================================
\  8. Concurrency guard
\ =====================================================================

GUARD _pst-guard

' PST-INIT       CONSTANT _pst-init-xt
' PST-SAVE-BLOCK CONSTANT _pst-save-xt
' PST-LOAD-BLOCK CONSTANT _pst-load-xt
' PST-CLEAR      CONSTANT _pst-clear-xt

: PST-INIT       _pst-init-xt  _pst-guard WITH-GUARD ;
: PST-SAVE-BLOCK _pst-save-xt  _pst-guard WITH-GUARD ;
: PST-LOAD-BLOCK _pst-load-xt  _pst-guard WITH-GUARD ;
: PST-CLEAR      _pst-clear-xt _pst-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
