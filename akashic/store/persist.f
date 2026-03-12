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
\  Files on disk (chain-id derived, e.g. chain_1.dat / state_1.snap):
\    chain_N.dat   — append-only block log
\                    Format: [8B len][len bytes CBOR] repeated
\    state_N.snap  — periodic state snapshot
\                    Format: [ST-SNAPSHOT-SIZE bytes][8B chain-height]
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
\   PST-SET-CHAIN-ID ( id -- )    set chain id (before PST-INIT)
\   PST-SET-CAPACITY ( chain-sec state-sec -- )  override sector counts
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

PROVIDED akashic-persist

\ =====================================================================
\  1. Constants & configurable sizing
\ =====================================================================

\ [FIX D06] Raised from 16384 to 262144 (256 KB) — 16 KB truncated
\ full blocks (256 txs × ~8 KB = ~2 MB CBOR).  256 KB covers
\ realistic blocks (up to ~30 txs).  Streaming encode needed for max.
262144 CONSTANT _PST-ENC-SZ

\ [FIX P31] Sector counts are now VARIABLEs — configurable via
\ PST-SET-CAPACITY before PST-INIT.  Defaults match previous constants.
VARIABLE _PST-CHAIN-SECTORS
VARIABLE _PST-STATE-SECTORS
1024 _PST-CHAIN-SECTORS !             \ ~512 KB for chain
512  _PST-STATE-SECTORS !             \ ~256 KB for state snapshot
\ *** _PST-STATE-SECTORS is sized for _ST-MAX-PAGES=16 (emulator).
\ *** Production: scale to ST-SNAPSHOT-SIZE / 512 + margin.

\ [FIX P31] Override sector sizes before PST-INIT.
: PST-SET-CAPACITY  ( chain-sectors state-sectors -- )
    _PST-STATE-SECTORS !
    _PST-CHAIN-SECTORS ! ;

\ [FIX B07] Block index: in-memory offset array for O(1) load.
\ Each entry stores the byte offset of the length prefix in chain.dat.
16384 CONSTANT _PST-IDX-MAX            \ max blocks in index

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

\ Separate 8-byte cell for length prefix I/O — cannot use _PST-BUF+ENC_SZ
\ because that would clobber _PST-IDX (allocated immediately after).
CREATE _PST-LEN-IO  8 ALLOT

\ [FIX B07] Offset index — 16384 × 8 bytes = 128 KB
CREATE _PST-IDX  _PST-IDX-MAX 8 * ALLOT

\ [FIX B08] Chain-id-derived filenames.
CREATE _PST-CHAIN-NAME 32 ALLOT       \ e.g. "chain_1.dat"
VARIABLE _PST-CHAIN-NAME-LEN
CREATE _PST-STATE-NAME 32 ALLOT       \ e.g. "state_1.snap"
VARIABLE _PST-STATE-NAME-LEN

\ =====================================================================
\  2b. Command builder — simple sequential string assembly
\ =====================================================================
\  Builds an EVALUATE-able command string in _PST-CMD.   No deep stack
\  gymnastics — just keep an offset counter and append pieces.

CREATE _PST-CMD 80 ALLOT
VARIABLE _PST-CMD-OFF

: _PST-CMD-RESET  ( -- )
    _PST-CMD 80 0 FILL  0 _PST-CMD-OFF ! ;

\ Append a counted string — CMOVE( src dst len ).
VARIABLE _PST-CS-LEN
: _PST-CMD-S  ( addr len -- )
    DUP _PST-CS-LEN !
    _PST-CMD _PST-CMD-OFF @ + SWAP CMOVE
    _PST-CS-LEN @ _PST-CMD-OFF +! ;

\ Execute the assembled command.
: _PST-CMD-EXEC  ( -- ... )
    _PST-CMD _PST-CMD-OFF @ EVALUATE ;

\ =====================================================================
\  2c. Number→string + name builder
\ =====================================================================

CREATE _PST-NBUF 20 ALLOT             \ temp for decimal digits

\ _PST-U>S ( u buf -- len )  Write unsigned decimal digits to buf.
VARIABLE _PST-US-N
VARIABLE _PST-US-BUF
VARIABLE _PST-US-LEN
: _PST-U>S  ( u buf -- len )
    _PST-US-BUF !
    DUP 0= IF
        DROP 48 _PST-US-BUF @ C!  1 EXIT
    THEN
    _PST-US-N !
    0 _PST-US-LEN !
    \ Extract digits in reverse
    BEGIN _PST-US-N @ 0> WHILE
        _PST-US-N @ 10 MOD 48 +
        _PST-US-BUF @ _PST-US-LEN @ + C!
        1 _PST-US-LEN +!
        _PST-US-N @ 10 / _PST-US-N !
    REPEAT
    \ Reverse in place
    _PST-US-LEN @ 2 / 0 ?DO
        _PST-US-BUF @ I + C@
        _PST-US-BUF @ _PST-US-LEN @ 1- I - + C@
        _PST-US-BUF @ I + C!
        _PST-US-BUF @ _PST-US-LEN @ 1- I - + C!
    LOOP
    _PST-US-LEN @ ;

\ Append a decimal number to the command buffer.
: _PST-CMD-U  ( u -- )
    _PST-NBUF _PST-U>S
    _PST-NBUF SWAP _PST-CMD-S ;

VARIABLE _PST-CID
1 _PST-CID !                          \ default chain id = 1

\ Build filenames from chain id.  Uses the command buffer as scratch,
\ then copies the result to the name buffers.
: _PST-BUILD-NAMES  ( -- )
    \ Build "chain_<id>.dat"
    _PST-CHAIN-NAME 32 0 FILL
    _PST-CMD-RESET
    S" chain_" _PST-CMD-S
    _PST-CID @ _PST-CMD-U
    S" .dat" _PST-CMD-S
    _PST-CMD _PST-CHAIN-NAME _PST-CMD-OFF @ CMOVE
    _PST-CMD-OFF @ _PST-CHAIN-NAME-LEN !
    \ Build "state_<id>.snap"
    _PST-STATE-NAME 32 0 FILL
    _PST-CMD-RESET
    S" state_" _PST-CMD-S
    _PST-CID @ _PST-CMD-U
    S" .snap" _PST-CMD-S
    _PST-CMD _PST-STATE-NAME _PST-CMD-OFF @ CMOVE
    _PST-CMD-OFF @ _PST-STATE-NAME-LEN ! ;

\ [FIX B08] Set chain id — call before PST-INIT.
: PST-SET-CHAIN-ID  ( id -- )
    _PST-CID !
    _PST-BUILD-NAMES ;

\ Build default names at load time.
_PST-BUILD-NAMES

\ =====================================================================
\  3. Internal — open-or-create a file
\ =====================================================================
\  OPEN and MKFILE parse filenames from the input stream.  We use
\  EVALUATE with dynamically-built command strings.

: _PST-OPEN-CHAIN  ( -- fdesc|0 )
    _PST-CMD-RESET
    S" OPEN " _PST-CMD-S
    _PST-CHAIN-NAME _PST-CHAIN-NAME-LEN @ _PST-CMD-S
    _PST-CMD-EXEC ;

: _PST-OPEN-STATE  ( -- fdesc|0 )
    _PST-CMD-RESET
    S" OPEN " _PST-CMD-S
    _PST-STATE-NAME _PST-STATE-NAME-LEN @ _PST-CMD-S
    _PST-CMD-EXEC ;

: _PST-MK-CHAIN  ( -- )
    _PST-CMD-RESET
    _PST-CHAIN-SECTORS @ _PST-CMD-U
    S"  5 MKFILE " _PST-CMD-S
    _PST-CHAIN-NAME _PST-CHAIN-NAME-LEN @ _PST-CMD-S
    _PST-CMD-EXEC ;

: _PST-MK-STATE  ( -- )
    _PST-CMD-RESET
    _PST-STATE-SECTORS @ _PST-CMD-U
    S"  5 MKFILE " _PST-CMD-S
    _PST-STATE-NAME _PST-STATE-NAME-LEN @ _PST-CMD-S
    _PST-CMD-EXEC ;

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
\  4. Internal — count blocks by walking chain.dat + build index
\ =====================================================================
\  Format: [8B len][len bytes data] repeated.
\  A len of 0 or read returning less than 8 marks the end.
\  [FIX B07] Also populates _PST-IDX with byte offsets for O(1) load.

: _PST-COUNT-BLOCKS  ( -- n )
    _PST-CHAIN-FD @ FREWIND
    0                                  ( count )
    BEGIN
        DUP _PST-IDX-MAX >= IF EXIT THEN  \ index full
        \ Record offset of this entry in index
        _PST-CHAIN-FD @ F.CURSOR
        OVER 8 * _PST-IDX + !         \ _PST-IDX[count] = cursor
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
    \ [FIX B07] Check index capacity
    _PST-COUNT @ _PST-IDX-MAX >= IF DROP 0 EXIT THEN
    \ Encode block to temp buffer
    _PST-BUF _PST-ENC-SZ BLK-ENCODE   ( len )
    DUP 0= IF DROP 0 EXIT THEN
    \ Seek to end of chain file
    _PST-CHAIN-FD @ FSIZE
    _PST-CHAIN-FD @ FSEEK
    \ [FIX B07] Record offset in index before writing
    _PST-CHAIN-FD @ F.CURSOR
    _PST-COUNT @ 8 * _PST-IDX + !
    \ Write 8-byte length prefix via dedicated I/O cell
    DUP >R
    _PST-LEN-IO !
    _PST-LEN-IO 8 _PST-CHAIN-FD @ FWRITE
    \ Write encoded block data
    _PST-BUF R> _PST-CHAIN-FD @ FWRITE
    \ Flush metadata
    _PST-CHAIN-FD @ FFLUSH
    1 _PST-COUNT +!
    -1 ;

\ =====================================================================
\  7. PST-LOAD-BLOCK — read block N from chain.dat, decode into blk
\ =====================================================================
\  [FIX B07] O(1) via _PST-IDX offset array (was O(n) walk).

: PST-LOAD-BLOCK  ( idx blk -- flag )
    SWAP                               ( blk idx )
    DUP _PST-COUNT @ >= IF 2DROP 0 EXIT THEN
    _PST-OK @ 0= IF 2DROP 0 EXIT THEN
    \ Seek directly to the block via index
    DUP 8 * _PST-IDX + @              ( blk idx offset )
    _PST-CHAIN-FD @ FSEEK
    DROP                               ( blk )
    \ Read length
    _PST-BUF 8 _PST-CHAIN-FD @ FREAD DROP
    _PST-BUF @                         ( blk len )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP _PST-ENC-SZ > IF 2DROP 0 EXIT THEN   \ [FIX D06] guard
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
\    [actual_snap bytes]  — ST-SNAPSHOT (header + pgdir + pages)
\    [8 bytes]            — chain height
\  ST-SNAPSHOT-SIZE is the worst-case (all 256 pages = ~4.7 MB).
\  We compute the actual size to avoid writing past _PST-BUF and
\  overflowing the disk file.

\ Compute actual snapshot size: 16 + MAX_PAGES*8 + used_pages*PAGE_BYTES.
VARIABLE _PST-SS
: _PST-SNAP-ACTUAL  ( -- n )
    16 _ST-MAX-PAGES CELLS +
    ST-COUNT DUP 0> IF
        ST-PAGE-ENTRIES 1- + ST-PAGE-ENTRIES / _ST-PAGE-BYTES *
    ELSE DROP 0
    THEN + ;

: PST-SAVE-STATE  ( -- flag )
    _PST-OK @ 0= IF 0 EXIT THEN
    _PST-SNAP-ACTUAL DUP _PST-ENC-SZ > IF DROP 0 EXIT THEN
    _PST-SS !
    _PST-STATE-FD @ FREWIND
    \ Snapshot state into scratch buffer
    _PST-BUF ST-SNAPSHOT
    \ Write actual snapshot data (not worst-case size)
    _PST-BUF _PST-SS @ _PST-STATE-FD @ FWRITE
    \ Write chain height
    CHAIN-HEIGHT _PST-BUF !
    _PST-BUF 8 _PST-STATE-FD @ FWRITE
    \ Write total length marker so LOAD knows how much to read
    _PST-SS @ _PST-BUF !
    _PST-BUF 8 _PST-STATE-FD @ FWRITE
    _PST-STATE-FD @ FFLUSH
    -1 ;

: PST-LOAD-STATE  ( -- flag )
    _PST-OK @ 0= IF 0 EXIT THEN
    _PST-STATE-FD @ FSIZE 0= IF 0 EXIT THEN
    _PST-STATE-FD @ FREWIND
    \ Compute expected snapshot size from current ST-COUNT
    \ (must match what was saved — rewritten after restore)
    \ Read the snapshot-size marker from end: seek to end - 8
    _PST-STATE-FD @ FSIZE 8 - DUP 0< IF DROP 0 EXIT THEN
    _PST-STATE-FD @ FSEEK
    _PST-BUF 8 _PST-STATE-FD @ FREAD 8 < IF 0 EXIT THEN
    _PST-BUF @ _PST-SS !
    _PST-SS @ _PST-ENC-SZ > IF 0 EXIT THEN
    _PST-SS @ 0= IF 0 EXIT THEN
    \ Now read from start: snapshot + height
    _PST-STATE-FD @ FREWIND
    _PST-BUF _PST-SS @ _PST-STATE-FD @ FREAD
    _PST-SS @ < IF 0 EXIT THEN
    _PST-BUF ST-RESTORE
    \ Skip chain height (informational)
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

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
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
[THEN] [THEN]

\ =================================================================
\  Done.
\ =================================================================
