\ binimg.f — Relocatable binary image saver/loader for KDOS
\
\ Save compiled Forth dictionary regions as .m64 binary files with
\ full relocation metadata.  Load them back at any base address
\ without re-parsing source text.
\
\ Prefix: IMG-   (public API)
\         _IMG-  (internal helpers)
\
\ Phase 1: Core Saver (IMG-MARK, IMG-SAVE)
\ Phase 2: Core Loader (IMG-LOAD)          — future
\ Phase 3: Imports & Exports               — future
\ Phase 4: Module System Integration       — future
\ Phase 5: Diagnostics & Hardening         — future
\
\ Memory strategy:
\   No ALLOCATE / FREE — uses only HERE / ALLOT.
\   IMG-MARK parks the reloc buffer at HERE, ALLOTs past it,
\   then sets the segment mark.  IMG-SAVE builds the output
\   file at HERE (past the segment), writes it in one shot via
\   FWRITE, then denormalizes.  No heap interaction, no effect
\   on other modules or cores.
\
\   Layout during compilation:
\     [...dict...][reloc-buf 8K][mark-base ... segment ... HERE]
\
\   Layout during IMG-SAVE (temporary):
\     [...dict...][reloc-buf][segment][output-buf]
\
\ Load with:   REQUIRE utils/binimg.f

PROVIDED akashic-binimg

\ =====================================================================
\  Constants
\ =====================================================================

64 CONSTANT _IMG-HDR-SZ       \ .m64 header size (bytes)
1  CONSTANT _IMG-VERSION      \ format version
1024 CONSTANT _IMG-MAX-RELOCS \ max relocation entries

\ Flag bits
1 CONSTANT _IMG-FLAG-JIT
2 CONSTANT _IMG-FLAG-XMEM
4 CONSTANT _IMG-FLAG-EXEC
8 CONSTANT _IMG-FLAG-LIB

\ Error codes
-1 CONSTANT _IMG-ERR-IO
-2 CONSTANT _IMG-ERR-MAGIC
-5 CONSTANT _IMG-ERR-RELOC

\ =====================================================================
\  Module State
\ =====================================================================

VARIABLE _img-mark-base    \ HERE at mark time (start of segment)
VARIABLE _img-mark-latest  \ LATEST at mark time
VARIABLE _img-reloc-buf    \ address of reloc buffer (below segment)
VARIABLE _img-seg-size     \ computed segment size
VARIABLE _img-fd           \ file descriptor during save

\ =====================================================================
\  IMG-MARK  ( -- )
\    Park reloc buffer at current HERE, ALLOT past it, then snapshot
\    HERE as the segment start.  Enable BIOS relocation tracking.
\    Everything compiled after this call is part of the segment.
\
\    No ALLOCATE.  No heap dependency.  Just dictionary space.
\ =====================================================================

: IMG-MARK  ( -- )
    \ Park reloc buffer at HERE
    HERE _img-reloc-buf !
    _IMG-MAX-RELOCS 8 * ALLOT

    \ Point BIOS at our buffer
    _img-reloc-buf @ _RELOC-BUF !
    0 _RELOC-COUNT !
    1 _RELOC-ACTIVE !

    \ Snapshot segment start (right after the reloc buffer)
    HERE _img-mark-base !
    LATEST _img-mark-latest !
;

\ =====================================================================
\  _IMG-COLLECT-LINKS  ( -- )
\    Walk the dictionary chain from LATEST back to _img-mark-latest.
\    Each entry's link field (byte +0, 8 bytes) is an absolute addr.
\    Append each link field's absolute address to the BIOS reloc
\    buffer (same format as reloc_record: absolute slot address).
\ =====================================================================

: _IMG-COLLECT-LINKS  ( -- )
    LATEST                            ( entry )
    BEGIN
        DUP _img-mark-latest @ <>     ( entry flag )
    WHILE
        \ Append absolute address of this link field to reloc buf
        _RELOC-COUNT @ DUP _IMG-MAX-RELOCS >= IF
            DROP DROP ." IMG: reloc buf full" CR EXIT
        THEN
        8 * _img-reloc-buf @ +        ( entry buf-slot )
        OVER SWAP !                    ( entry )
        _RELOC-COUNT @ 1+ _RELOC-COUNT !
        \ Follow the link
        @                              ( prev-entry )
    REPEAT
    DROP
;

\ =====================================================================
\  _IMG-NORMALIZE  ( -- )
\    For each entry in the reloc buffer:
\      1. Read absolute address of the 8-byte slot
\      2. Convert buffer entry to segment-relative offset
\      3. Subtract seg-base from the value at that slot
\ =====================================================================

: _IMG-NORMALIZE  ( -- )
    \ Normalize relocs whose target values fall within the segment.
    \ Out-of-segment references (calls to KDOS/BIOS words, terminal
    \ link) are skipped — they become "imports" in Phase 3.
    0  ( j — compacted output index )
    _RELOC-COUNT @ 0 DO
        I 8 * _img-reloc-buf @ + @    ( j abs-slot-addr )
        DUP @                           ( j abs val )
        \ Is val in [mark-base, mark-base + seg-size)?
        DUP _img-mark-base @ >=
        OVER _img-mark-base @ _img-seg-size @ + < AND IF
            \ In-segment → normalize value and store in compacted slot
            _img-mark-base @ -          ( j abs norm-val )
            OVER !                       ( j abs )
            _img-mark-base @ -          ( j offset )
            OVER 8 * _img-reloc-buf @ + !  ( j )
            1+                           ( j+1 )
        ELSE
            \ Out-of-segment → discard from reloc table
            2DROP                        ( j )
        THEN
    LOOP
    _RELOC-COUNT !  \ update to filtered count
;

\ =====================================================================
\  _IMG-DENORMALIZE  ( -- )
\    Undo normalization so the live dictionary stays valid.
\ =====================================================================

: _IMG-DENORMALIZE  ( -- )
    _RELOC-COUNT @ 0 DO
        \ Read offset from buffer, convert to absolute address
        I 8 * _img-reloc-buf @ + @   ( offset )
        _img-mark-base @ +           ( abs-slot-addr )
        \ Restore value: add seg-base back
        DUP @ _img-mark-base @ +     ( abs abs-val )
        SWAP !
        \ Restore buffer entry to absolute address
        I 8 * _img-reloc-buf @ +     ( buf-entry )
        DUP @ _img-mark-base @ +     ( buf-entry abs )
        SWAP !
    LOOP
;

\ =====================================================================
\  _IMG-BUILD-OUTPUT  ( -- addr size )
\    Build the complete .m64 at HERE (past the segment).
\    Returns output address and byte count.
\ =====================================================================

: _IMG-BUILD-OUTPUT  ( -- addr size )
    \ Total output size
    _IMG-HDR-SZ _img-seg-size @ + _RELOC-COUNT @ 8 * +
                                      ( out-size )
    HERE SWAP                         ( buf out-size )

    \ Zero the output area
    OVER OVER 0 FILL                  ( buf out-size )

    \ ── Header (64 bytes) ────────────────────────────────────────
    OVER                              ( buf out-size buf )
    77 OVER     C!                    \ 'M'
    70 OVER 1 + C!                    \ 'F'
    54 OVER 2 + C!                    \ '6'
    52 OVER 3 + C!                    \ '4'
    _IMG-VERSION OVER 4 + W!          \ version
    0 OVER 6 + W!                     \ flags
    _img-seg-size @ OVER 8 + !        \ segment size
    _RELOC-COUNT @ OVER 16 + !        \ reloc count
    0 OVER 24 + !                     \ exports (Phase 1: 0)
    0 OVER 32 + !                     \ imports (Phase 1: 0)
    0 OVER 40 + !                     \ entry point
    0 OVER 48 + !                     \ provided offset
    0 OVER 56 + !                     \ reserved
    DROP                              ( buf out-size )

    \ ── Segment copy ─────────────────────────────────────────────
    _img-mark-base @                  ( buf out-size src )
    2 PICK _IMG-HDR-SZ +             ( buf out-size src dst )
    _img-seg-size @ CMOVE            ( buf out-size )

    \ ── Reloc table ──────────────────────────────────────────────
    _RELOC-COUNT @ 0<> IF
        _img-reloc-buf @              ( buf out-size reloc-src )
        2 PICK _IMG-HDR-SZ + _img-seg-size @ +
                                      ( buf out-size reloc-src dst )
        _RELOC-COUNT @ 8 * CMOVE     ( buf out-size )
    THEN
;

\ =====================================================================
\  IMG-SAVE  ( "filename" -- ior )
\    Save [mark-base .. HERE) as a .m64 file.
\    File must already exist on disk.  Parses filename from input.
\    Returns 0 on success, negative on error.
\
\    After save the live dictionary is restored (denormalized).
\    No heap allocations.  No side effects on other modules.
\ =====================================================================

: IMG-SAVE  ( "filename" -- ior )
    \ 1. Stop tracking
    0 _RELOC-ACTIVE !

    \ 2. Segment size
    HERE _img-mark-base @ - _img-seg-size !

    \ 3. Collect dict-chain link fields
    _IMG-COLLECT-LINKS

    \ 4. Open file FIRST — OPEN-BY-SLOT builds fdesc at HERE via `,`
    \    so it must happen before we lay down the output buffer.
    PARSE-NAME
    FIND-BY-NAME DUP -1 = IF
        DROP
        _IMG-DENORMALIZE
        ." IMG-SAVE: not found: " NAMEBUF .ZSTR CR
        _IMG-ERR-IO EXIT
    THEN
    OPEN-BY-SLOT DUP 0= IF
        DROP
        _IMG-DENORMALIZE
        ." IMG-SAVE: open failed" CR
        _IMG-ERR-IO EXIT
    THEN
    _img-fd !

    \ 5. Normalize to base-0
    _IMG-NORMALIZE

    \ 6. Build output at HERE (past segment + fdesc — safe scratch)
    _IMG-BUILD-OUTPUT                 ( buf out-size )

    \ 7. Write entire .m64 in one FWRITE
    _img-fd @ FWRITE

    \ 8. Flush
    _img-fd @ FFLUSH

    \ 9. Denormalize (restore live dictionary)
    _IMG-DENORMALIZE

    \ Done — HERE still points past segment, caller keeps compiling.
    0
;
