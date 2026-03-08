\ =================================================================
\  persist.f  —  Chain Persistence (Block Log + State Snapshot)
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: PST-  / _PST-
\  Depends on: block.f state.f guard.f
\
\  Disk-backed persistence using KDOS file I/O primitives
\  (OPEN, FREAD, FWRITE, FSEEK, FREWIND, FSIZE, FFLUSH, FCLOSE,
\  MKFILE).  See kdos.f §7.5–7.6.
\
\  Files on disk:
\    chain.dat   — append-only block log
\                  Format: [8B len][len bytes CBOR] repeated
\    state.snap  — periodic state snapshot
\                  Format: [ST-SNAPSHOT-SIZE bytes][8B chain-height]
\
\  Known KDOS limitations:
\   - MP64FS contiguous allocation; files cannot be resized
\   - MKFILE pre-allocates a fixed sector count — over-allocate
\   - FD pool is 16 slots (persist needs at most 2)
\   - FREAD/FWRITE operate via DMA (whole sectors) — use _PST-BUF
\     as scratch for small reads
\   - No concurrent access control; serialized via WITH-GUARD
\
\  When the akashic higher-level filesystem libraries are built
\  (see ROADMAP_filesystem.md), this module should be rewritten
\  against those abstractions.  The public API stays the same.
\
\  Public API:
\   PST-INIT        ( -- flag )     open/create chain files on disk
\   PST-SAVE-BLOCK  ( blk -- flag ) encode + append to chain.dat
\   PST-LOAD-BLOCK  ( idx blk -- flag ) decode block N from log
\   PST-BLOCK-COUNT ( -- n )        number of saved blocks
\   PST-CLEAR       ( -- )          reset log (truncate chain.dat)
\   PST-SAVE-STATE  ( -- flag )     snapshot state to state.snap
\   PST-LOAD-STATE  ( -- flag )     restore state from state.snap
\   PST-CLOSE       ( -- )          flush + close all files
\ =================================================================

REQUIRE ../store/block.f
REQUIRE ../store/state.f
REQUIRE ../concurrency/guard.f

PROVIDED akashic-persist

\ =====================================================================
\  1. Constants
\ =====================================================================

16384 CONSTANT _PST-ENC-SZ             \ per-block encode buffer
1024  CONSTANT _PST-CHAIN-SECTORS      \ pre-allocate ~512 KB for chain
40    CONSTANT _PST-STATE-SECTORS      \ pre-allocate ~20 KB for state
\ *** _PST-STATE-SECTORS is sized for _ST-MAX-PAGES=16 (emulator).
\ *** Production: scale to ST-SNAPSHOT-SIZE / 512 + margin.
\ *** E.g. 256 pages → ~4.5 MB snapshot → 9216 sectors.

\ =====================================================================
\  2. Storage
\ =====================================================================

VARIABLE _PST-CHAIN-FD                 \ file descriptor for chain.dat
VARIABLE _PST-STATE-FD                 \ file descriptor for state.snap
VARIABLE _PST-COUNT                    \ number of blocks in log
VARIABLE _PST-OK                       \ TRUE if init succeeded

0 _PST-CHAIN-FD !
0 _PST-STATE-FD !
0 _PST-COUNT !
0 _PST-OK !

CREATE _PST-BUF _PST-ENC-SZ ALLOT     \ temp encode/decode/DMA scratch

\ =====================================================================
\  3. Internal — open-or-create a file
\ =====================================================================
\  OPEN and MKFILE parse filenames from the input stream.  We use
\  EVALUATE with string literals so hardcoded names work inside
\  colon definitions.

: _PST-OPEN-CHAIN  ( -- fdesc|0 )
    S" OPEN chain.dat" EVALUATE ;

: _PST-OPEN-STATE  ( -- fdesc|0 )
    S" OPEN state.snap" EVALUATE ;

: _PST-MK-CHAIN  ( -- )
    S" 1024 5 MKFILE chain.dat" EVALUATE ;

: _PST-MK-STATE  ( -- )
    S" 40 5 MKFILE state.snap" EVALUATE ;

\ Try to open; if not found, create then open.
: _PST-ENSURE-CHAIN  ( -- fdesc|0 )
    _PST-OPEN-CHAIN DUP 0<> IF EXIT THEN
    DROP
    _PST-MK-CHAIN
    _PST-OPEN-CHAIN ;

: _PST-ENSURE-STATE  ( -- fdesc|0 )
    _PST-OPEN-STATE DUP 0<> IF EXIT THEN
    DROP
    _PST-MK-STATE
    _PST-OPEN-STATE ;

\ =====================================================================
\  4. Internal — count blocks by walking chain.dat
\ =====================================================================
\  Format: [8B len][len bytes data] repeated.
\  A len of 0 or read returning less than 8 marks the end.

: _PST-COUNT-BLOCKS  ( -- n )
    _PST-CHAIN-FD @ FREWIND
    0                                  ( count )
    BEGIN
        \ Read 8 bytes (length cell) into scratch buffer
        _PST-BUF 8 _PST-CHAIN-FD @ FREAD
        8 < IF EXIT THEN               \ short read = end of data
        _PST-BUF @                     ( count len )
        DUP 0= IF DROP EXIT THEN      \ zero-length = end
        \ Skip past the block data
        _PST-CHAIN-FD @ F.CURSOR +
        _PST-CHAIN-FD @ FSEEK
        1+                             ( count+1 )
    AGAIN ;

\ =====================================================================
\  5. PST-INIT — open/create files, count existing blocks
\ =====================================================================

: PST-INIT  ( -- flag )
    \ Need filesystem loaded
    FS-OK @ 0= IF
        FS-ENSURE
        FS-OK @ 0= IF 0 EXIT THEN
    THEN
    _PST-ENSURE-CHAIN _PST-CHAIN-FD !
    _PST-CHAIN-FD @ 0= IF 0 EXIT THEN
    _PST-ENSURE-STATE _PST-STATE-FD !
    _PST-STATE-FD @ 0= IF
        _PST-CHAIN-FD @ FCLOSE
        0 _PST-CHAIN-FD !
        0 EXIT
    THEN
    _PST-COUNT-BLOCKS _PST-COUNT !
    -1 _PST-OK !
    -1 ;

\ =====================================================================
\  6. PST-SAVE-BLOCK — encode block, append to chain.dat
\ =====================================================================

: PST-SAVE-BLOCK  ( blk -- flag )
    _PST-OK @ 0= IF DROP 0 EXIT THEN
    \ Encode block to temp buffer
    _PST-BUF _PST-ENC-SZ BLK-ENCODE   ( len )
    DUP 0= IF DROP 0 EXIT THEN
    \ Seek to end of chain file
    _PST-CHAIN-FD @ FSIZE
    _PST-CHAIN-FD @ FSEEK
    \ Write 8-byte length prefix
    DUP >R
    _PST-BUF _PST-ENC-SZ + !          \ store len after encode data
    _PST-BUF _PST-ENC-SZ +            \ addr of length cell
    8 _PST-CHAIN-FD @ FWRITE
    \ Write encoded block data
    _PST-BUF R> _PST-CHAIN-FD @ FWRITE
    \ Flush metadata
    _PST-CHAIN-FD @ FFLUSH
    1 _PST-COUNT +!
    -1 ;

\ =====================================================================
\  7. PST-LOAD-BLOCK — read block N from chain.dat, decode into blk
\ =====================================================================

: PST-LOAD-BLOCK  ( idx blk -- flag )
    SWAP                               ( blk idx )
    DUP _PST-COUNT @ >= IF 2DROP 0 EXIT THEN
    _PST-OK @ 0= IF 2DROP 0 EXIT THEN
    \ Rewind and walk to the Nth entry
    _PST-CHAIN-FD @ FREWIND
    0 ?DO
        _PST-BUF 8 _PST-CHAIN-FD @ FREAD DROP
        _PST-BUF @                     \ length of this entry
        _PST-CHAIN-FD @ F.CURSOR +
        _PST-CHAIN-FD @ FSEEK          \ skip data
    LOOP
    \ Now at target entry — read length
    _PST-BUF 8 _PST-CHAIN-FD @ FREAD DROP
    _PST-BUF @                         ( blk len )
    DUP 0= IF 2DROP 0 EXIT THEN
    \ Read block data
    DUP >R
    _PST-BUF SWAP _PST-CHAIN-FD @ FREAD DROP
    \ Decode
    _PST-BUF R> ROT BLK-DECODE ;      ( flag )

\ =====================================================================
\  8. PST-BLOCK-COUNT / PST-CLEAR
\ =====================================================================

: PST-BLOCK-COUNT  ( -- n )  _PST-COUNT @ ;

: PST-CLEAR  ( -- )
    _PST-OK @ 0= IF EXIT THEN
    \ Rewind chain file and write a zero-length marker
    _PST-CHAIN-FD @ FREWIND
    0 _PST-BUF !
    _PST-BUF 8 _PST-CHAIN-FD @ FWRITE
    _PST-CHAIN-FD @ FFLUSH
    0 _PST-COUNT ! ;

\ =====================================================================
\  9. PST-SAVE-STATE / PST-LOAD-STATE
\ =====================================================================
\  Layout in state.snap:
\    [ST-SNAPSHOT-SIZE bytes]  — account table + count
\    [8 bytes]                 — chain height

: PST-SAVE-STATE  ( -- flag )
    _PST-OK @ 0= IF 0 EXIT THEN
    _PST-STATE-FD @ FREWIND
    \ Snapshot state into scratch buffer
    _PST-BUF ST-SNAPSHOT
    \ Write snapshot data
    _PST-BUF ST-SNAPSHOT-SIZE _PST-STATE-FD @ FWRITE
    \ Write chain height
    CHAIN-HEIGHT _PST-BUF !
    _PST-BUF 8 _PST-STATE-FD @ FWRITE
    _PST-STATE-FD @ FFLUSH
    -1 ;

: PST-LOAD-STATE  ( -- flag )
    _PST-OK @ 0= IF 0 EXIT THEN
    _PST-STATE-FD @ FSIZE 0= IF 0 EXIT THEN
    _PST-STATE-FD @ FREWIND
    \ Read snapshot data
    _PST-BUF ST-SNAPSHOT-SIZE _PST-STATE-FD @ FREAD
    ST-SNAPSHOT-SIZE < IF 0 EXIT THEN
    _PST-BUF ST-RESTORE
    \ Read chain height (informational — not restored here)
    _PST-BUF 8 _PST-STATE-FD @ FREAD DROP
    -1 ;

\ =====================================================================
\  10. PST-CLOSE — flush and close all files
\ =====================================================================

: PST-CLOSE  ( -- )
    _PST-CHAIN-FD @ DUP 0<> IF
        DUP FFLUSH FCLOSE
    ELSE DROP THEN
    _PST-STATE-FD @ DUP 0<> IF
        DUP FFLUSH FCLOSE
    ELSE DROP THEN
    0 _PST-CHAIN-FD !
    0 _PST-STATE-FD !
    0 _PST-OK ! ;

\ =====================================================================
\  11. Concurrency guard
\ =====================================================================

GUARD _pst-guard

' PST-INIT       CONSTANT _pst-init-xt
' PST-SAVE-BLOCK CONSTANT _pst-save-xt
' PST-LOAD-BLOCK CONSTANT _pst-load-xt
' PST-CLEAR      CONSTANT _pst-clear-xt
' PST-SAVE-STATE CONSTANT _pst-sv-st-xt
' PST-LOAD-STATE CONSTANT _pst-ld-st-xt
' PST-CLOSE      CONSTANT _pst-close-xt

: PST-INIT       _pst-init-xt  _pst-guard WITH-GUARD ;
: PST-SAVE-BLOCK _pst-save-xt  _pst-guard WITH-GUARD ;
: PST-LOAD-BLOCK _pst-load-xt  _pst-guard WITH-GUARD ;
: PST-CLEAR      _pst-clear-xt _pst-guard WITH-GUARD ;
: PST-SAVE-STATE _pst-sv-st-xt _pst-guard WITH-GUARD ;
: PST-LOAD-STATE _pst-ld-st-xt _pst-guard WITH-GUARD ;
: PST-CLOSE      _pst-close-xt _pst-guard WITH-GUARD ;

\ =================================================================
\  Done.
\ =================================================================
