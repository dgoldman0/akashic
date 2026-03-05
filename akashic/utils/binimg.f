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
\ Phase 2: Core Loader (IMG-LOAD)
\ Phase 3: Imports (auto-detect)
\ Phase 4: Module System Integration
\ Phase 5: Diagnostics & Hardening         — this file
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
\     [...dict...][reloc-buf 8K/64K][mark-base ... segment ... HERE]
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

\ Reloc buffer: adaptive sizing based on available memory.
\ In kernel space (base 2 MB RAM) a large ALLOT can clobber BIOS
\ structures, so we keep the buffer small.  When the caller has
\ entered userland (HERE in ext mem, 16 MB), the full 8192 slots
\ are safe.  The check is ULAND @ (currently in userland?) not
\ XMEM? (hardware present?) because the latter is true even when
\ HERE still points into base RAM.
1024 CONSTANT _IMG-RELOCS-SMALL  \ kernel-space cap (8 KB)
8192 CONSTANT _IMG-RELOCS-LARGE  \ userland cap (64 KB)

\ Flag bits
1 CONSTANT _IMG-FLAG-JIT
2 CONSTANT _IMG-FLAG-XMEM
4 CONSTANT _IMG-FLAG-EXEC
8 CONSTANT _IMG-FLAG-LIB

\ Error codes
-1 CONSTANT _IMG-ERR-IO
-2 CONSTANT _IMG-ERR-MAGIC
-5 CONSTANT _IMG-ERR-RELOC
-3 CONSTANT _IMG-ERR-IMPORT    \ unresolved import
-6 CONSTANT _IMG-ERR-NOEXEC    \ not an executable image

\ Import table
32 CONSTANT _IMG-IMPORT-ENTRY-SZ  \ bytes per import entry in file

\ =====================================================================
\  Module State
\ =====================================================================

VARIABLE _img-mark-base    \ HERE at mark time (start of segment)
VARIABLE _img-mark-latest  \ LATEST at mark time
VARIABLE _img-reloc-buf    \ address of reloc buffer (below segment)
VARIABLE _img-reloc-cap    \ runtime reloc capacity (set by IMG-MARK)
VARIABLE _img-seg-size     \ computed segment size
VARIABLE _img-fd           \ file descriptor during save

\ Import state (Phase 3) — ext-pairs buffer (static, large)
1024 CONSTANT _IMG-EXT-CAP
VARIABLE _img-ext-count        \ count of all out-of-segment relocs
VARIABLE _img-import-count     \ count of named imports
CREATE _img-ext-buf  _IMG-EXT-CAP 16 * ALLOT  \ (offset, value) pairs

\ Module/entry state (Phase 4)
VARIABLE _img-flags            \ flag bits for next save
VARIABLE _img-prov-offset      \ segment-rel offset of PROVIDED string
VARIABLE _img-entry-offset     \ segment-rel offset of entry point

\ =====================================================================
\  IMG-MARK  ( -- )
\    Park reloc buffer at current HERE, ALLOT past it, then snapshot
\    HERE as the segment start.  Enable BIOS relocation tracking.
\    Everything compiled after this call is part of the segment.
\
\    No ALLOCATE.  No heap dependency.  Just dictionary space.
\ =====================================================================

: IMG-MARK  ( -- )
    \ Pick reloc capacity: large if in userland, small otherwise
    ULAND @ IF _IMG-RELOCS-LARGE ELSE _IMG-RELOCS-SMALL THEN
    _img-reloc-cap !

    \ Park reloc buffer at HERE
    HERE _img-reloc-buf !
    _img-reloc-cap @ 8 * ALLOT

    \ Point BIOS at our buffer
    _img-reloc-buf @ _RELOC-BUF !
    0 _RELOC-COUNT !
    1 _RELOC-ACTIVE !

    \ Snapshot segment start (right after the reloc buffer)
    HERE _img-mark-base !
    LATEST _img-mark-latest !

    \ Phase 4 state
    0 _img-flags !
    -1 _img-prov-offset !
    -1 _img-entry-offset !
;

\ =====================================================================
\  IMG-PROVIDED  ( "token" -- )
\    Store a NUL-terminated module name in the segment.  After save,
\    the loader will call _MOD-MARK to register it so that REQUIRE
\    of the source .f file is skipped.
\ =====================================================================

: IMG-PROVIDED  ( "token" -- )
    PARSE-NAME                        \ fills NAMEBUF, sets PN-LEN
    PN-LEN @ DUP 0= IF DROP EXIT THEN ( len )
    HERE _img-mark-base @ -  _img-prov-offset !  ( len )
    DUP >R
    NAMEBUF HERE R@ CMOVE             ( len ; name at HERE )
    R> ALLOT  0 C,                    ( -- ; NUL-terminated )
;

\ =====================================================================
\  IMG-ENTRY  ( xt -- )
\    Record an entry-point xt for the current segment.  Sets the
\    EXEC flag.  The xt must belong to a word compiled after IMG-MARK.
\ =====================================================================

: IMG-ENTRY  ( xt -- )
    _img-mark-base @ -  _img-entry-offset !
    _img-flags @ _IMG-FLAG-EXEC OR  _img-flags !
;

\ =====================================================================
\  IMG-XMEM  ( -- )
\    Set the XMEM flag.  When set, the loader allocates the segment
\    in extended memory via XMEM-ALLOT instead of base-RAM ALLOT.
\ =====================================================================

: IMG-XMEM  ( -- )
    _img-flags @ _IMG-FLAG-XMEM OR  _img-flags !
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
        _RELOC-COUNT @ DUP _img-reloc-cap @ >= IF
            ABORT" IMG: reloc buffer overflow"
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
\  _IMG-XT>ENTRY  ( xt -- entry | 0 )
\    Reverse-lookup: given a code-field address (xt), find the
\    dictionary entry.  Walks the pre-mark dictionary only (link
\    fields in the segment may be normalized during save).
\ =====================================================================

: _IMG-XT>ENTRY  ( xt -- entry | 0 )
    _img-mark-latest @
    BEGIN DUP WHILE
        DUP 8 + C@ 127 AND    ( xt entry name-len )
        OVER 9 + +             ( xt entry code-field )
        2 PICK = IF
            NIP EXIT
        THEN
        @
    REPEAT
    NIP
;

\ =====================================================================
\  _IMG-RECORD-EXT  ( abs-slot-addr val -- )
\    Record an out-of-segment relocation: store the segment-relative
\    offset and the original absolute value for later import detection
\    and denormalization.
\ =====================================================================

: _IMG-RECORD-EXT  ( abs-slot-addr val -- )
    _img-ext-count @ _IMG-EXT-CAP >= IF
        ABORT" IMG-SAVE: ext-pair overflow (>1024 external refs)"
    THEN
    _img-ext-count @ 16 * _img-ext-buf +  ( abs val pair )
    ROT _img-mark-base @ -                  ( val pair offset )
    OVER !                                   ( val pair )
    8 + !                                    ( )
    _img-ext-count @ 1+ _img-ext-count !
;

\ =====================================================================
\  _IMG-COUNT-IMPORTS  ( -- n )
\    Count out-of-segment relocs that resolve to named dictionary
\    entries (i.e., actual callable imports, not terminal links).
\ =====================================================================

: _IMG-COUNT-IMPORTS  ( -- n )
    0
    _img-ext-count @ 0 ?DO
        I 16 * _img-ext-buf + 8 + @   ( count xt )
        _IMG-XT>ENTRY 0<> IF 1+ THEN
    LOOP
;

\ =====================================================================
\  _IMG-NORMALIZE  ( -- )
\    For each entry in the reloc buffer:
\      1. Read absolute address of the 8-byte slot
\      2. Convert buffer entry to segment-relative offset
\      3. Subtract seg-base from the value at that slot
\    Out-of-segment references are recorded as imports (Phase 3).
\ =====================================================================

: _IMG-NORMALIZE  ( -- )
    \ Normalize relocs whose target values fall within the segment.
    \ Out-of-segment references (calls to KDOS/BIOS words, terminal
    \ link) are recorded as ext-pairs and their slots zeroed.
    0  ( j — compacted output index )
    _RELOC-COUNT @ 0 ?DO
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
            \ Out-of-segment → record for import & denorm, zero slot
            2DUP _IMG-RECORD-EXT         ( j abs val )
            DROP 0 SWAP !                ( j )
        THEN
    LOOP
    _RELOC-COUNT !  \ update to filtered count
;

\ =====================================================================
\  _IMG-DENORMALIZE  ( -- )
\    Undo normalization so the live dictionary stays valid.
\ =====================================================================

: _IMG-DENORMALIZE  ( -- )
    _RELOC-COUNT @ 0 ?DO
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
    \ Restore out-of-segment slots (imports + terminal link)
    _img-ext-count @ 0 ?DO
        I 16 * _img-ext-buf +        ( pair )
        DUP @                           ( pair offset )
        _img-mark-base @ +             ( pair abs-slot-addr )
        SWAP 8 + @                      ( abs-slot-addr original-val )
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
    _img-import-count @ _IMG-IMPORT-ENTRY-SZ * +
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
    _img-flags @ OVER 6 + W!          \ flags
    _img-seg-size @ OVER 8 + !        \ segment size
    _RELOC-COUNT @ OVER 16 + !        \ reloc count
    0 OVER 24 + !                     \ exports (0 for now)
    _img-import-count @ OVER 32 + !   \ imports
    LATEST _img-mark-base @ - OVER 40 + !  \ chain head offset
    _img-prov-offset @ OVER 48 + !    \ provided offset
    _img-entry-offset @ OVER 56 + !   \ entry offset
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

    \ ── Import table ─────────────────────────────────────────────
    \ Each entry: fixup_offset(8) + name(24, NUL-padded).
    \ Only ext-pairs with a resolvable XT>ENTRY are written.
    _img-import-count @ 0<> IF
        OVER _IMG-HDR-SZ + _img-seg-size @ +
        _RELOC-COUNT @ 8 * +             ( buf out-size imp-dest )
        _img-ext-count @ 0 ?DO
            I 16 * _img-ext-buf + 8 + @   ( ... imp-dest xt )
            _IMG-XT>ENTRY DUP IF
                \ Write fixup offset at imp-dest+0
                I 16 * _img-ext-buf + @    ( ... imp-dest entry offset )
                2 PICK !                      ( ... imp-dest entry )
                \ Write name at imp-dest+8 (up to 23 chars)
                ENTRY>NAME 23 MIN            ( ... imp-dest addr len )
                2 PICK 8 +                    ( ... imp-dest addr len dest+8 )
                SWAP CMOVE                    ( ... imp-dest )
                _IMG-IMPORT-ENTRY-SZ +        ( ... imp-dest' )
            ELSE
                DROP
            THEN
        LOOP
        DROP                                  ( buf out-size )
    THEN
;

\ =====================================================================
\  IMG-SAVE  ( "filename" -- ior )
\    Save [mark-base .. HERE) as a .m64 file.
\    File must already exist on disk.  Parses filename from input.
\    Returns 0 on success, negative on error.
\
\    After save the live dictionary is restored (denormalized).
\ =====================================================================

: IMG-SAVE  ( "filename" -- ior )
    \ 1. Stop tracking
    0 _RELOC-ACTIVE !
    0 _img-ext-count !

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

    \ 5. Normalize to base-0 (also records out-of-segment relocs)
    _IMG-NORMALIZE

    \ 5b. Count named imports (resolvable XT>ENTRY lookups)
    _IMG-COUNT-IMPORTS _img-import-count !

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

\ =====================================================================
\  IMG-SAVE-EXEC  ( xt "filename" -- ior )
\    Convenience: record entry point then save.  Equivalent to
\    IMG-ENTRY followed by IMG-SAVE.
\ =====================================================================

: IMG-SAVE-EXEC  ( xt "filename" -- ior )
    IMG-ENTRY
    IMG-SAVE
;

\ =====================================================================
\  Phase 2 — Core Loader
\ =====================================================================

\ Loader state
VARIABLE _img-load-base    \ base address where segment was loaded
VARIABLE _img-load-fd      \ file descriptor during load
VARIABLE _img-load-seg     \ loaded segment size
VARIABLE _img-load-nrel    \ loaded reloc count
VARIABLE _img-load-head    \ chain-head offset from header
VARIABLE _img-load-nimp    \ loaded import count
VARIABLE _img-load-flags   \ loaded flags from header
VARIABLE _img-load-prov    \ loaded provided offset
VARIABLE _img-load-entry   \ loaded entry offset
VARIABLE _img-scratch      \ scratch address for reloc/import tables
VARIABLE _img-splice-guard \ countdown guard for chain walk

CREATE _img-find-buf  32 ALLOT  \ counted string buffer for FIND

\ =====================================================================
\  _IMG-RELOCATE  ( reloc-buf count base -- )
\    Apply relocations: for each u64 offset in reloc-buf, add base
\    to the 8-byte value at (base + offset).
\ =====================================================================

: _IMG-RELOCATE  ( reloc-buf count base -- )
    ROT ROT                           ( base reloc-buf count )
    0 ?DO
        DUP I 8 * + @                ( base reloc-buf offset )
        2 PICK +                      ( base reloc-buf slot-addr )
        DUP @                         ( base reloc-buf slot-addr val )
        3 PICK +                      ( base reloc-buf slot-addr relocated )
        SWAP !                        ( base reloc-buf )
    LOOP
    2DROP
;

\ =====================================================================
\  _IMG-SPLICE-DICT  ( -- )
\    Splice the loaded dictionary chain into the live dictionary.
\    Uses _img-load-base, _img-load-head, _img-load-seg.
\    Walks from the chain head to find the tail (terminal link),
\    splices tail→LATEST, sets LATEST to head.
\ =====================================================================

: _IMG-SPLICE-DICT  ( -- )
    \ Guard: max entries = seg-size / 10 (min entry = 8 link + 1 len + 1 char)
    _img-load-seg @ 10 / 1+ _img-splice-guard !
    _img-load-base @ _img-load-head @ +   ( head )
    DUP                                     ( head cur )
    BEGIN
        DUP @                               ( head cur link )
        DUP _img-load-base @ >=
        OVER _img-load-base @ _img-load-seg @ + < AND
    WHILE
        NIP DUP                             ( head link link )
        _img-splice-guard @ 1- DUP _img-splice-guard !
        0= IF ABORT" IMG-LOAD: corrupt dict chain (loop detected)" THEN
    REPEAT
    DROP                                    ( head tail )

    \ tail.link → current LATEST
    LATEST SWAP !                           ( head )

    \ Set LATEST to head
    LATEST!
;

\ =====================================================================
\  _IMG-STRLEN  ( c-addr max -- len )
\    Count bytes until NUL or max, whichever comes first.
\ =====================================================================

: _IMG-STRLEN  ( c-addr max -- len )
    SWAP OVER                 ( max c-addr max )
    0 ?DO                     ( max c-addr )
        DUP I + C@            ( max c-addr byte )
        0= IF
            2DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP                      ( max )
;

\ =====================================================================
\  _IMG-RESOLVE-IMPORTS  ( imp-base count -- )
\    For each import entry, look up the name via FIND and patch the
\    fixup slot with the resolved xt.
\    Import entry (32 bytes): fixup_offset(8) + name(24, NUL-padded).
\ =====================================================================

: _IMG-RESOLVE-IMPORTS  ( imp-base count -- )
    0 ?DO                                  ( imp-base )
        \ Build counted string from name at imp-base+8
        DUP 8 +  23 _IMG-STRLEN           ( imp-base len )
        DUP _img-find-buf C!              ( imp-base len )
        OVER 8 +                           ( imp-base len name-addr )
        _img-find-buf 1+                  ( imp-base len name-addr buf+1 )
        ROT CMOVE                          ( imp-base )
        \ Resolve via FIND
        _img-find-buf FIND                ( imp-base [xt flag | caddr 0] )
        0<> IF
            \ Found: patch fixup slot
            SWAP DUP @ _img-load-base @ +  ( xt imp-base abs-slot )
            ROT SWAP !                     ( imp-base )
        ELSE
            \ Not found: print warning
            DROP                            ( imp-base )
            ." IMG: import not found: "
            _img-find-buf 1+ _img-find-buf C@ TYPE CR
        THEN
        _IMG-IMPORT-ENTRY-SZ +             ( imp-base' )
    LOOP
    DROP
;

\ =====================================================================
\  IMG-LOAD  ( "filename" -- ior )
\    Load a .m64 file into the dictionary, relocate, and splice
\    the dictionary chain.  After loading, the words defined in the
\    file are available for use.
\
\    File must exist on disk.  Parses filename from input stream.
\    Returns 0 on success, negative error code on failure.
\
\    Strategy: read the ENTIRE file in one FREAD (avoids the sector-
\    aligned cursor issue where FREAD advances by whole sectors).
\    The file lands at HERE.  The segment lives at HERE+64.
\    We ALLOT header+segment to make it permanent, then use the
\    reloc data still sitting past the ALLOT (scratch at new HERE).
\ =====================================================================

: IMG-LOAD  ( "filename" -- ior )
    \ 1. Open (fdesc at HERE, advances HERE by 56 bytes)
    PARSE-NAME
    FIND-BY-NAME DUP -1 = IF
        DROP
        ." IMG-LOAD: not found: " NAMEBUF .ZSTR CR
        _IMG-ERR-IO EXIT
    THEN
    OPEN-BY-SLOT DUP 0= IF
        DROP
        ." IMG-LOAD: open failed" CR
        _IMG-ERR-IO EXIT
    THEN
    _img-load-fd !

    \ 2. Read entire file into HERE in one FREAD
    \    FREAD DMA is sector-aligned, cursor advances by sectors.
    \    One big read avoids the misalignment problem.
    _img-load-fd @ FSIZE              ( file-size )
    DUP 64 < IF
        DROP ." IMG-LOAD: file too small" CR
        _IMG-ERR-MAGIC EXIT
    THEN
    HERE OVER                         ( fsize buf fsize )
    _img-load-fd @ FREAD DROP         ( fsize )

    \ 3. Validate header at HERE
    HERE     C@ 77 <> IF DROP ." IMG-LOAD: bad magic" CR _IMG-ERR-MAGIC EXIT THEN
    HERE 1 + C@ 70 <> IF DROP ." IMG-LOAD: bad magic" CR _IMG-ERR-MAGIC EXIT THEN
    HERE 2 + C@ 54 <> IF DROP ." IMG-LOAD: bad magic" CR _IMG-ERR-MAGIC EXIT THEN
    HERE 3 + C@ 52 <> IF DROP ." IMG-LOAD: bad magic" CR _IMG-ERR-MAGIC EXIT THEN
    HERE 4 + W@ _IMG-VERSION > IF
        DROP ." IMG-LOAD: version too new" CR _IMG-ERR-MAGIC EXIT
    THEN

    \ 4. Extract metadata
    HERE 6  + W@ _img-load-flags !
    HERE 8  + @ _img-load-seg !
    HERE 16 + @ _img-load-nrel !
    HERE 32 + @ _img-load-nimp !
    HERE 40 + @ _img-load-head !
    HERE 48 + @ _img-load-prov !
    HERE 56 + @ _img-load-entry !
    DROP                              \ drop file-size

    \ 5. Allocate segment — XMEM or base-RAM
    _img-load-flags @ _IMG-FLAG-XMEM AND IF
        \ XMEM: allocate in ext memory, copy segment there
        _img-load-seg @ XMEM-ALLOT _img-load-base !
        HERE 64 + _img-load-base @ _img-load-seg @ CMOVE
        HERE 64 + _img-load-seg @ + _img-scratch !
    ELSE
        \ Normal: segment at HERE+64, ALLOT to make permanent
        HERE 64 + _img-load-base !
        64 _img-load-seg @ + ALLOT
        HERE _img-scratch !
    THEN

    \ 6. Relocate
    _img-load-nrel @ 0<> IF
        _img-scratch @ _img-load-nrel @ _img-load-base @ _IMG-RELOCATE
    THEN

    \ 7. Resolve imports
    _img-load-nimp @ 0<> IF
        _img-scratch @ _img-load-nrel @ 8 * +
        _img-load-nimp @ _IMG-RESOLVE-IMPORTS
    THEN

    \ 8. Splice dictionary chain
    _IMG-SPLICE-DICT

    \ 9. Register PROVIDED token if present  (-1 = none)
    _img-load-prov @ -1 <> IF
        NAMEBUF 24 0 FILL
        _img-load-base @ _img-load-prov @ +   ( str-addr )
        DUP 23 _IMG-STRLEN 23 MIN             ( str-addr len )
        NAMEBUF SWAP CMOVE
        _MOD-MARK
    THEN

    0
;

\ =====================================================================
\  IMG-LOAD-EXEC  ( "filename" -- xt ior )
\    Load a .m64 file that has the EXEC flag set (bit 2).  Returns
\    the entry-point xt and 0 on success.  On error, returns dummy
\    xt=0 and a negative ior.  Returns _IMG-ERR-NOEXEC if the
\    image is not an executable.
\ =====================================================================

: IMG-LOAD-EXEC  ( "filename" -- xt ior )
    IMG-LOAD DUP 0<> IF
        0 SWAP EXIT               \ error → ( 0 ior )
    THEN
    _img-load-flags @ _IMG-FLAG-EXEC AND 0= IF
        DROP 0 _IMG-ERR-NOEXEC EXIT
    THEN
    DROP
    _img-load-base @ _img-load-entry @ +
    0
;

\ =====================================================================
\  Phase 5 — Diagnostics & Hardening
\ =====================================================================

\ Helper: open a .m64 file, read whole file at HERE, validate header.
\ On success: leaves file-size on stack, header data at HERE.
\ On failure: prints diagnostic, returns 0.

: _IMG-OPEN-READ  ( "filename" -- file-size | 0 )
    PARSE-NAME
    FIND-BY-NAME DUP -1 = IF
        DROP ." IMG: not found: " NAMEBUF .ZSTR CR 0 EXIT
    THEN
    OPEN-BY-SLOT DUP 0= IF
        DROP ." IMG: open failed" CR 0 EXIT
    THEN
    DUP FSIZE                         ( fd file-size )
    DUP 64 < IF
        2DROP ." IMG: file too small" CR 0 EXIT
    THEN
    \ FREAD ( buf len fd -- n )
    HERE OVER                         ( fd fsize HERE fsize )
    3 PICK                            ( fd fsize HERE fsize fd )
    FREAD DROP                        ( fd fsize ; data at HERE )
    NIP                               ( fsize )
    \ Validate magic
    HERE     C@ 77 <>
    HERE 1 + C@ 70 <> OR
    HERE 2 + C@ 54 <> OR
    HERE 3 + C@ 52 <> OR IF
        DROP ." IMG: bad magic" CR 0 EXIT
    THEN
    HERE 4 + W@ _IMG-VERSION > IF
        DROP ." IMG: version too new" CR 0 EXIT
    THEN
;

\ =====================================================================
\  IMG-INFO  ( "filename" -- )
\    Read and print the .m64 header without loading.
\ =====================================================================

: IMG-INFO  ( "filename" -- )
    _IMG-OPEN-READ                    ( file-size | 0 )
    DUP 0= IF DROP EXIT THEN

    \ Extract fields from header at HERE
    HERE 4  + W@                      \ version
    HERE 6  + W@                      \ flags
    HERE 8  + @                       \ seg-size
    HERE 16 + @                       \ reloc-count
    HERE 24 + @                       \ export-count
    HERE 32 + @                       \ import-count
    HERE 40 + @                       \ chain-head (unused for display)
    HERE 48 + @                       \ prov-offset
    HERE 56 + @                       \ entry-point

    ( fsize ver flags seg nrel nexp nimp head prov entry )
    \ PICK indices (0=TOS): 0=entry 1=prov 2=head 3=nimp
    \   4=nexp 5=nrel 6=seg 7=flags 8=ver 9=fsize

    ." MF64 v" 8 PICK . CR           \ version
    ."   Flags:     "
    7 PICK                            \ flags
    DUP _IMG-FLAG-EXEC AND IF ." EXEC " THEN
    DUP _IMG-FLAG-LIB  AND IF ." LIB " THEN
    DUP _IMG-FLAG-XMEM AND IF ." XMEM " THEN
    DUP _IMG-FLAG-JIT  AND IF ." JIT " THEN
    DUP 0= IF ." (none)" THEN
    DROP CR
    ."   Segment:   " 6 PICK . ." bytes" CR
    ."   Relocs:    " 5 PICK . CR
    ."   Exports:   " 4 PICK . CR
    ."   Imports:   " 3 PICK . CR
    ."   Provided:  "
    OVER -1 <> IF                     \ prov-offset (pos 1) valid?
        HERE 64 + 2 PICK +           ( ... prov entry prov-addr )
        DUP 64 _IMG-STRLEN           ( ... prov entry prov-addr len )
        TYPE                          ( ... prov entry )
    ELSE ." (none)"
    THEN CR
    ."   Entry:     "
    DUP -1 <> IF
        .
    ELSE
        DROP ." (none)"
    THEN CR
    ."   File size: " 8 PICK . ." bytes" CR
    \ Drop remaining values on stack
    \ After entry consumed by ./DROP above: ( fsize ver flags seg nrel nexp nimp head prov )
    2DROP 2DROP 2DROP 2DROP DROP
;

\ =====================================================================
\  IMG-VERIFY  ( "filename" -- ior )
\    Non-destructive validation of a .m64 file.
\    Reads file, applies relocations to a temp copy, checks:
\    - All reloc offsets within segment bounds
\    - All import names resolve via FIND
\    - Entry-point offset within segment bounds (if EXEC flag)
\    Does NOT splice into dictionary.  Returns 0 if OK.
\ =====================================================================

: IMG-VERIFY  ( "filename" -- ior )
    _IMG-OPEN-READ                    ( file-size | 0 )
    DUP 0= IF _IMG-ERR-MAGIC EXIT THEN

    \ Parse header fields
    HERE 6  + W@                      ( fsize flags )
    HERE 8  + @                       ( fsize flags seg )
    HERE 16 + @                       ( fsize flags seg nrel )
    HERE 32 + @                       ( fsize flags seg nrel nimp )
    HERE 48 + @                       ( fsize flags seg nrel nimp prov )
    HERE 56 + @                       ( fsize flags seg nrel nimp prov entry )

    \ Stack indices (0=TOS): entry=0 prov=1 nimp=2 nrel=3 seg=4 flags=5 fsize=6

    \ Check file size is large enough for all sections
    \ expected = 64 + seg + nrel*8 + nimp*32 (import entry = 32 bytes)
    64                                ( ... entry min )
    5 PICK +                          ( ... entry min+seg )
    4 PICK 8 * +                      ( ... entry min+seg+rel )
    3 PICK _IMG-IMPORT-ENTRY-SZ * +   ( ... entry expected )
    7 PICK > IF
        ." IMG-VERIFY: file truncated" CR
        2DROP 2DROP 2DROP DROP
        _IMG-ERR-MAGIC EXIT
    THEN

    \ Check all reloc offsets within segment
    \ Relocs start at HERE + 64 + seg
    HERE 64 + 5 PICK +               ( ... reloc-base )  \ 8-item: seg=5
    4 PICK 0 ?DO                      ( ... reloc-base )  \ 8-item: nrel=4
        DUP I 8 * + @                ( ... reloc-base offset )
        6 PICK >= IF                  \ 9-item: seg=6
            ." IMG-VERIFY: reloc[" I . ." ] offset out of range" CR
            DROP
            2DROP 2DROP 2DROP DROP
            _IMG-ERR-RELOC EXIT
        THEN
    LOOP
    DROP                              ( fsize flags seg nrel nimp prov entry )

    \ Check import name resolution
    \ Imports at HERE + 64 + seg + nrel*8 (no export section in v1)
    \ Import entry: 8-byte fixup-offset + 24-byte inline name (NUL-padded)
    HERE 64 + 5 PICK + 4 PICK 8 * +  ( ... imp-base )  \ 8-item: seg=5 nrel=4
    3 PICK 0 ?DO                      ( ... imp-base )   \ 8-item: nimp=3
        DUP I _IMG-IMPORT-ENTRY-SZ * + ( ... imp-base entry-addr )
        \ Check fixup offset within segment
        DUP @ 7 PICK >= IF           \ 10-item: seg=7
            ." IMG-VERIFY: import[" I . ." ] fixup offset out of range" CR
            2DROP
            2DROP 2DROP 2DROP DROP
            _IMG-ERR-RELOC EXIT
        THEN
        \ Inline name at entry+8 (up to 23 chars NUL-terminated)
        8 +                           ( ... imp-base name-addr )
        DUP 23 _IMG-STRLEN            ( ... imp-base name-addr len )
        DUP 0= IF
            ." IMG-VERIFY: import[" I . ." ] empty name" CR
            2DROP DROP
            2DROP 2DROP 2DROP DROP
            _IMG-ERR-IMPORT EXIT
        THEN
        \ Build counted string in _img-find-buf
        DUP _img-find-buf C!          ( ... imp-base name-addr len )
        _img-find-buf 1 + SWAP CMOVE  ( ... imp-base )
        _img-find-buf FIND 0= IF
            ." IMG-VERIFY: unresolved import: "
            _img-find-buf COUNT TYPE CR
            DROP                      \ drop c-addr from FIND
            2DROP 2DROP 2DROP 2DROP   \ drop 8: imp-base + 7 base values
            _IMG-ERR-IMPORT EXIT
        THEN
        DROP                          ( ... imp-base )
    LOOP
    DROP                              ( fsize flags seg nrel nimp prov entry )

    \ Check entry-point if EXEC
    5 PICK _IMG-FLAG-EXEC AND IF      \ 7-item: flags=5
        DUP -1 = IF
            ." IMG-VERIFY: EXEC flag set but no entry point" CR
            2DROP 2DROP 2DROP DROP
            _IMG-ERR-NOEXEC EXIT
        THEN
        DUP 5 PICK >= IF             \ 8-item (after DUP): seg=5
            ." IMG-VERIFY: entry point out of segment" CR
            2DROP 2DROP 2DROP DROP
            _IMG-ERR-RELOC EXIT
        THEN
    THEN

    \ Check provided offset if present
    OVER -1 <> IF
        OVER 5 PICK >= IF            \ 8-item (after OVER): seg=5
            ." IMG-VERIFY: provided offset out of segment" CR
            2DROP 2DROP 2DROP DROP
            _IMG-ERR-RELOC EXIT
        THEN
    THEN

    \ All checks passed
    2DROP 2DROP 2DROP DROP
    0
;

\ =====================================================================
\  IMG-CHECKSUM  ( "filename" -- u64 )
\    Compute FNV-1a 64-bit hash over segment + relocation table +
\    import/export tables.  Skips the header and reserved field.
\    Useful for reproducible-build verification.
\ =====================================================================

\ FNV-1a 64-bit constants
\ Using 32-bit FNV-1a for portability (64-bit MUL can overflow weirdly)
\ FNV offset basis = 2166136261 (0x811c9dc5)
\ FNV prime = 16777619 (0x01000193)
\ Operates byte-at-a-time for simplicity.

: IMG-CHECKSUM  ( "filename" -- u64 )
    _IMG-OPEN-READ                    ( file-size | 0 )
    DUP 0= IF EXIT THEN              ( file-size )

    HERE 8 + @                        ( fsize seg-size )
    HERE 16 + @                       ( fsize seg nrel )
    HERE 24 + @                       ( fsize seg nrel nexp )
    HERE 32 + @                       ( fsize seg nrel nexp nimp )

    \ Compute data length: seg + nrel*8 + nexp*16 + nimp*32
    3 PICK                            ( ... nimp data-len=seg )
    3 PICK 8 * +                      ( ... nimp data-len )
    2 PICK 16 * +                     ( ... nimp data-len )
    OVER _IMG-IMPORT-ENTRY-SZ * +     ( fsize seg nrel nexp nimp data-len )

    \ Data starts at HERE + 64 (segment)
    HERE 64 +                         ( ... data-len data-addr )
    SWAP                              ( ... data-addr data-len )

    \ FNV-1a hash
    2166136261                        ( ... data-addr data-len hash )
    ROT ROT                           ( ... hash data-addr data-len )
    0 ?DO                             ( ... hash data-addr )
        DUP I + C@                    ( hash data-addr byte )
        ROT XOR                       ( data-addr hash' )
        16777619 *                    ( data-addr hash'' )
        SWAP                          ( hash'' data-addr )
    LOOP
    DROP                              ( fsize seg nrel nexp nimp hash )

    \ Clean up stack: drop fsize seg nrel nexp nimp, keep hash
    SWAP DROP SWAP DROP SWAP DROP SWAP DROP SWAP DROP
;
