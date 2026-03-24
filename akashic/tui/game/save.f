\ =====================================================================
\  akashic/tui/game/save.f — Game Save / Load (CBOR-based)
\ =====================================================================
\
\  Serialize / deserialize game state as a CBOR map stored on disk.
\
\  Save context: accumulates key-value entries in a linear buffer,
\  then encodes them as a CBOR map and writes to a named file.
\
\  Load context: reads a file from disk, parses the CBOR map, and
\  provides key-based lookups (scan the map sequentially).
\
\  Save Context Descriptor (72 bytes, 9 cells):
\    +0   buf        Scratch buffer address (for entries)
\    +8   buf-cap    Buffer capacity
\    +16  count      Number of entries
\    +24  eptr       Entry write pointer (byte offset into buf)
\    +32  fd         File descriptor (during write/read)
\    +40  mode       0=save, 1=load
\    +48  parse-addr Parsed CBOR start (load mode)
\    +56  parse-len  Parsed CBOR length (load mode)
\    +64  map-count  CBOR map pair count (load mode)
\
\  Public API:
\    GSAVE-NEW   ( -- ctx )
\    GSAVE-INT   ( ctx key-a key-u val -- )
\    GSAVE-STR   ( ctx key-a key-u str-a str-u -- )
\    GSAVE-BLOB  ( ctx key-a key-u addr len -- )
\    GSAVE-WRITE ( ctx path-a path-u -- ior )
\    GSAVE-FREE  ( ctx -- )
\
\    GLOAD-OPEN  ( path-a path-u -- ctx | 0 )
\    GLOAD-INT   ( ctx key-a key-u -- val )
\    GLOAD-STR   ( ctx key-a key-u -- addr len )
\    GLOAD-BLOB  ( ctx key-a key-u -- addr len )
\    GLOAD-CLOSE ( ctx -- )
\
\  Prefix: GSAVE- / GLOAD- (public), _GSV- (internal)
\  Provider: akashic-tui-game-save
\  Dependencies: cbor.f

PROVIDED akashic-tui-game-save

REQUIRE ../../cbor/cbor.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

0  CONSTANT _GSV-O-BUF
8  CONSTANT _GSV-O-CAP
16 CONSTANT _GSV-O-COUNT
24 CONSTANT _GSV-O-EPTR
32 CONSTANT _GSV-O-FD
40 CONSTANT _GSV-O-MODE
48 CONSTANT _GSV-O-PADDR
56 CONSTANT _GSV-O-PLEN
64 CONSTANT _GSV-O-MCOUNT
72 CONSTANT _GSV-DESC-SZ

\ Entry types stored in the linear buffer
0 CONSTANT _GSV-T-INT
1 CONSTANT _GSV-T-STR
2 CONSTANT _GSV-T-BLOB

\ Default save buffer: 16 KB
16384 CONSTANT _GSV-DEFAULT-CAP

\ Save file pre-allocation: 64 sectors = 32 KB
64 CONSTANT _GSV-FILE-SECTORS

\ =====================================================================
\  §2 — File I/O Helpers (EVALUATE-based, like persist.f)
\ =====================================================================
\  KDOS OPEN/MKFILE parse filenames from the input stream, so we
\  build command strings and EVALUATE them.

CREATE _GSV-CMD 80 ALLOT
VARIABLE _GSV-CMD-OFF

: _GSV-CMD-RESET  ( -- )
    _GSV-CMD 80 0 FILL  0 _GSV-CMD-OFF ! ;

VARIABLE _GSV-CS-LEN
: _GSV-CMD-S  ( addr len -- )
    DUP _GSV-CS-LEN !
    _GSV-CMD _GSV-CMD-OFF @ + SWAP CMOVE
    _GSV-CS-LEN @ _GSV-CMD-OFF +! ;

: _GSV-CMD-EXEC  ( -- ... )
    _GSV-CMD _GSV-CMD-OFF @ EVALUATE ;

\ Number→string helper
CREATE _GSV-NBUF 20 ALLOT
VARIABLE _GSV-US-N
VARIABLE _GSV-US-BUF
VARIABLE _GSV-US-LEN
: _GSV-U>S  ( u buf -- len )
    _GSV-US-BUF !
    DUP 0= IF
        DROP 48 _GSV-US-BUF @ C!  1 EXIT
    THEN
    _GSV-US-N !
    0 _GSV-US-LEN !
    BEGIN _GSV-US-N @ 0> WHILE
        _GSV-US-N @ 10 MOD 48 +
        _GSV-US-BUF @ _GSV-US-LEN @ + C!
        1 _GSV-US-LEN +!
        _GSV-US-N @ 10 / _GSV-US-N !
    REPEAT
    _GSV-US-LEN @ 2 / 0 ?DO
        _GSV-US-BUF @ I + C@
        _GSV-US-BUF @ _GSV-US-LEN @ 1- I - + C@
        _GSV-US-BUF @ I + C!
        _GSV-US-BUF @ _GSV-US-LEN @ 1- I - + C!
    LOOP
    _GSV-US-LEN @ ;

: _GSV-CMD-U  ( u -- )
    _GSV-NBUF _GSV-U>S
    _GSV-NBUF SWAP _GSV-CMD-S ;

\ Open a file by name (addr len on stack).
\ Copies name to cmd buffer, EVALUATEs "OPEN <name>".
VARIABLE _GSV-OPEN-A
VARIABLE _GSV-OPEN-U
: _GSV-FOPEN  ( path-a path-u -- fdesc | 0 )
    _GSV-OPEN-U ! _GSV-OPEN-A !
    _GSV-CMD-RESET
    S" OPEN " _GSV-CMD-S
    _GSV-OPEN-A @ _GSV-OPEN-U @ _GSV-CMD-S
    _GSV-CMD-EXEC ;

\ Create a file (pre-allocated sectors).
: _GSV-FMAKE  ( path-a path-u -- )
    _GSV-OPEN-U ! _GSV-OPEN-A !
    _GSV-CMD-RESET
    _GSV-FILE-SECTORS _GSV-CMD-U
    S"  5 MKFILE " _GSV-CMD-S
    _GSV-OPEN-A @ _GSV-OPEN-U @ _GSV-CMD-S
    _GSV-CMD-EXEC ;

\ Ensure file exists: try open, if fail create then open.
: _GSV-FENSURE  ( path-a path-u -- fdesc | 0 )
    2DUP _GSV-FOPEN DUP 0<> IF
        >R 2DROP R> EXIT
    THEN
    DROP
    2DUP _GSV-FMAKE
    _GSV-FOPEN ;

\ =====================================================================
\  §3 — Save Context: Constructor / Destructor
\ =====================================================================

: GSAVE-NEW  ( -- ctx )
    _GSV-DESC-SZ ALLOCATE
    0<> ABORT" GSAVE-NEW: desc alloc"
    DUP _GSV-DESC-SZ 0 FILL
    _GSV-DEFAULT-CAP ALLOCATE
    0<> ABORT" GSAVE-NEW: buf alloc"
    OVER _GSV-O-BUF + !
    _GSV-DEFAULT-CAP OVER _GSV-O-CAP + !
    0 OVER _GSV-O-COUNT + !
    0 OVER _GSV-O-EPTR + !
    0 OVER _GSV-O-MODE + ! ;

: GSAVE-FREE  ( ctx -- )
    DUP _GSV-O-BUF + @ FREE
    FREE ;

\ =====================================================================
\  §4 — Save Context: Accumulate Entries
\ =====================================================================
\
\  Entry format in the linear buffer:
\    [1B type] [2B key-len] [key-len bytes key]
\    For INT:  [8B value]
\    For STR:  [2B str-len] [str-len bytes string]
\    For BLOB: [2B blob-len] [blob-len bytes data]
\
\  All lengths stored as little-endian 16-bit for simplicity.
\  All emit helpers use VARIABLEs — no >R inside loops.

VARIABLE _GSV-E-CTX    \ current ctx for emit operations
VARIABLE _GSV-E-TMP    \ temp for multi-byte emit

\ Write a byte at eptr, advance eptr.
: _GSV-EMIT  ( byte -- )
    _GSV-E-CTX @ _GSV-O-BUF + @
    _GSV-E-CTX @ _GSV-O-EPTR + @ + C!
    _GSV-E-CTX @ _GSV-O-EPTR + DUP @ 1+ SWAP ! ;

\ Write a 16-bit LE value at eptr.
: _GSV-EMIT2  ( val -- )
    _GSV-E-TMP !
    _GSV-E-TMP @ 255 AND _GSV-EMIT
    _GSV-E-TMP @ 8 RSHIFT 255 AND _GSV-EMIT ;

\ Write an 8-byte cell at eptr (LE).
: _GSV-EMIT8  ( val -- )
    _GSV-E-TMP !
    _GSV-E-TMP @            255 AND _GSV-EMIT
    _GSV-E-TMP @  8 RSHIFT  255 AND _GSV-EMIT
    _GSV-E-TMP @ 16 RSHIFT  255 AND _GSV-EMIT
    _GSV-E-TMP @ 24 RSHIFT  255 AND _GSV-EMIT
    _GSV-E-TMP @ 32 RSHIFT  255 AND _GSV-EMIT
    _GSV-E-TMP @ 40 RSHIFT  255 AND _GSV-EMIT
    _GSV-E-TMP @ 48 RSHIFT  255 AND _GSV-EMIT
    _GSV-E-TMP @ 56 RSHIFT  255 AND _GSV-EMIT ;

\ Write raw bytes at eptr (copy from addr len).
VARIABLE _GSV-BLK-A
VARIABLE _GSV-BLK-U
: _GSV-EMITBLK  ( addr len -- )
    _GSV-BLK-U ! _GSV-BLK-A !
    _GSV-BLK-U @ 0 ?DO
        _GSV-BLK-A @ I + C@ _GSV-EMIT
    LOOP ;

\ Store params in VARIABLEs for GSAVE-* words
VARIABLE _GSV-CTX
VARIABLE _GSV-KA
VARIABLE _GSV-KU
VARIABLE _GSV-VA       \ value addr (for STR/BLOB)
VARIABLE _GSV-VU       \ value len  (for STR/BLOB)
VARIABLE _GSV-IVAL     \ integer value

\ Write key header: type byte + key-len + key bytes.
: _GSV-EMIT-KEY  ( type key-a key-u -- )
    _GSV-KU ! _GSV-KA !
    _GSV-EMIT                        \ emit type byte
    _GSV-KU @ _GSV-EMIT2            \ emit key length
    _GSV-KA @ _GSV-KU @ _GSV-EMITBLK ;  \ emit key bytes

\ Increment entry count on ctx.
: _GSV-INC-COUNT  ( -- )
    _GSV-E-CTX @ _GSV-O-COUNT + DUP @ 1+ SWAP ! ;

\ GSAVE-INT ( ctx key-a key-u val -- )
: GSAVE-INT  ( ctx key-a key-u val -- )
    _GSV-IVAL ! _GSV-KU ! _GSV-KA ! _GSV-E-CTX !
    _GSV-T-INT _GSV-KA @ _GSV-KU @ _GSV-EMIT-KEY
    _GSV-IVAL @ _GSV-EMIT8
    _GSV-INC-COUNT ;

\ GSAVE-STR ( ctx key-a key-u str-a str-u -- )
: GSAVE-STR  ( ctx key-a key-u str-a str-u -- )
    _GSV-VU ! _GSV-VA !
    _GSV-KU ! _GSV-KA ! _GSV-E-CTX !
    _GSV-T-STR _GSV-KA @ _GSV-KU @ _GSV-EMIT-KEY
    _GSV-VU @ _GSV-EMIT2
    _GSV-VA @ _GSV-VU @ _GSV-EMITBLK
    _GSV-INC-COUNT ;

\ GSAVE-BLOB ( ctx key-a key-u addr len -- )
: GSAVE-BLOB  ( ctx key-a key-u addr len -- )
    _GSV-VU ! _GSV-VA !
    _GSV-KU ! _GSV-KA ! _GSV-E-CTX !
    _GSV-T-BLOB _GSV-KA @ _GSV-KU @ _GSV-EMIT-KEY
    _GSV-VU @ _GSV-EMIT2
    _GSV-VA @ _GSV-VU @ _GSV-EMITBLK
    _GSV-INC-COUNT ;

\ =====================================================================
\  §5 — Save: Encode & Write
\ =====================================================================
\
\  Walk the entry buffer, encode each entry into CBOR, then write
\  the resulting bytes to disk.

CREATE _GSV-CBUF 16384 ALLOT          \ CBOR output buffer

\ Read a byte from entry buffer at offset, advance offset.
VARIABLE _GSV-RPTR
VARIABLE _GSV-RBUF
: _GSV-RBYTE  ( -- byte )
    _GSV-RBUF @ _GSV-RPTR @ + C@
    1 _GSV-RPTR +! ;

\ Read LE 16-bit from entry buffer.
: _GSV-R16  ( -- n )
    _GSV-RBYTE
    _GSV-RBYTE 8 LSHIFT OR ;

\ Read LE 64-bit from entry buffer.
: _GSV-R64  ( -- n )
    _GSV-RBYTE
    _GSV-RBYTE 8 LSHIFT OR
    _GSV-RBYTE 16 LSHIFT OR
    _GSV-RBYTE 24 LSHIFT OR
    _GSV-RBYTE 32 LSHIFT OR
    _GSV-RBYTE 40 LSHIFT OR
    _GSV-RBYTE 48 LSHIFT OR
    _GSV-RBYTE 56 LSHIFT OR ;

\ Encode one entry from the linear buffer into CBOR.
VARIABLE _GSV-ENC-TYPE
VARIABLE _GSV-ENC-KLEN
VARIABLE _GSV-ENC-KADDR
VARIABLE _GSV-ENC-VLEN
VARIABLE _GSV-ENC-VADDR

: _GSV-ENCODE-ONE  ( -- )
    _GSV-RBYTE _GSV-ENC-TYPE !
    _GSV-R16 _GSV-ENC-KLEN !
    _GSV-RBUF @ _GSV-RPTR @ + _GSV-ENC-KADDR !
    _GSV-ENC-KLEN @ _GSV-RPTR +!
    \ Encode key as CBOR text string
    _GSV-ENC-KADDR @ _GSV-ENC-KLEN @ CBOR-TSTR
    \ Encode value based on type
    _GSV-ENC-TYPE @ _GSV-T-INT = IF
        _GSV-R64 CBOR-UINT EXIT
    THEN
    _GSV-ENC-TYPE @ _GSV-T-STR = IF
        _GSV-R16 _GSV-ENC-VLEN !
        _GSV-RBUF @ _GSV-RPTR @ + _GSV-ENC-VADDR !
        _GSV-ENC-VLEN @ _GSV-RPTR +!
        _GSV-ENC-VADDR @ _GSV-ENC-VLEN @ CBOR-TSTR EXIT
    THEN
    \ BLOB
    _GSV-R16 _GSV-ENC-VLEN !
    _GSV-RBUF @ _GSV-RPTR @ + _GSV-ENC-VADDR !
    _GSV-ENC-VLEN @ _GSV-RPTR +!
    _GSV-ENC-VADDR @ _GSV-ENC-VLEN @ CBOR-BSTR ;

\ Encode all entries as CBOR.
: _GSV-ENCODE  ( ctx -- )
    DUP _GSV-O-BUF + @ _GSV-RBUF !
    0 _GSV-RPTR !
    _GSV-CBUF 16384 CBOR-RESET
    _GSV-O-COUNT + @                  ( count )
    DUP CBOR-MAP                      ( count )
    0 ?DO _GSV-ENCODE-ONE LOOP ;

\ GSAVE-WRITE ( ctx path-a path-u -- ior )
\   Encode accumulated entries to CBOR, write to named file.
\   Returns 0 on success, non-zero on failure.
VARIABLE _GSV-WR-FD
VARIABLE _GSV-WR-PA
VARIABLE _GSV-WR-PU
: GSAVE-WRITE  ( ctx path-a path-u -- ior )
    _GSV-WR-PU ! _GSV-WR-PA !
    \ Ensure filesystem is ready
    FS-OK @ 0= IF FS-ENSURE THEN
    \ Encode entries to CBOR
    DUP _GSV-ENCODE                   ( ctx )
    DROP
    \ Open/create file
    _GSV-WR-PA @ _GSV-WR-PU @ _GSV-FENSURE  ( fdesc )
    DUP 0= IF DROP -1 EXIT THEN
    _GSV-WR-FD !
    \ Rewind
    _GSV-WR-FD @ FREWIND
    \ Write CBOR result
    CBOR-RESULT                       ( addr len )
    _GSV-WR-FD @ FWRITE
    \ Flush and close
    _GSV-WR-FD @ FFLUSH
    _GSV-WR-FD @ FCLOSE
    0 _GSV-WR-FD !
    CBOR-OK? IF 0 ELSE -2 THEN ;

\ =====================================================================
\  §6 — Load Context: Open & Parse
\ =====================================================================

\ Read buffer for loading
CREATE _GSV-LBUF 16384 ALLOT

\ GLOAD-OPEN ( path-a path-u -- ctx | 0 )
\   Open a save file, read and parse CBOR.  Returns context or 0.
VARIABLE _GSV-LD-FD
VARIABLE _GSV-LD-BYTES
: GLOAD-OPEN  ( path-a path-u -- ctx | 0 )
    FS-OK @ 0= IF FS-ENSURE THEN
    _GSV-FOPEN                        ( fdesc | 0 )
    DUP 0= IF EXIT THEN
    _GSV-LD-FD !
    \ Rewind and read file contents
    _GSV-LD-FD @ FREWIND
    _GSV-LBUF 16384 _GSV-LD-FD @ FREAD
    _GSV-LD-BYTES !
    _GSV-LD-FD @ FCLOSE
    0 _GSV-LD-FD !
    \ Validate we got data
    _GSV-LD-BYTES @ 0= IF 0 EXIT THEN
    \ Parse CBOR
    _GSV-LBUF _GSV-LD-BYTES @ CBOR-PARSE
    0<> IF 0 EXIT THEN
    \ Check it's a map
    CBOR-TYPE CBOR-MT-MAP <> IF 0 EXIT THEN
    \ Allocate context
    _GSV-DESC-SZ ALLOCATE
    0<> IF 0 EXIT THEN               ( ctx )
    DUP _GSV-DESC-SZ 0 FILL
    _GSV-LBUF      OVER _GSV-O-PADDR + !
    _GSV-LD-BYTES @  OVER _GSV-O-PLEN + !
    1              OVER _GSV-O-MODE + !
    \ Read map header to get pair count
    CBOR-NEXT-MAP  OVER _GSV-O-MCOUNT + !
    ;

\ =====================================================================
\  §7 — Load Context: Key Lookup
\ =====================================================================
\
\  To find a key, we rewind the CBOR parse cursor to just after the
\  map header, then scan key-value pairs sequentially.

\ Compare two strings for equality.
VARIABLE _GSV-CMP-A1
VARIABLE _GSV-CMP-U1
VARIABLE _GSV-CMP-A2
VARIABLE _GSV-CMP-U2
: _GSV-STREQ  ( a1 u1 a2 u2 -- flag )
    _GSV-CMP-U2 ! _GSV-CMP-A2 !
    _GSV-CMP-U1 ! _GSV-CMP-A1 !
    _GSV-CMP-U1 @ _GSV-CMP-U2 @ <> IF 0 EXIT THEN
    _GSV-CMP-U1 @ 0 ?DO
        _GSV-CMP-A1 @ I + C@
        _GSV-CMP-A2 @ I + C@ <> IF 0 UNLOOP EXIT THEN
    LOOP
    -1 ;

\ Reset parse cursor to after the map header.
: _GSV-REWIND  ( ctx -- )
    DUP _GSV-O-PADDR + @
    SWAP _GSV-O-PLEN + @
    CBOR-PARSE DROP
    CBOR-NEXT-MAP DROP ;

\ Scan for a text string key. Returns -1 if found (cursor on value),
\ 0 if not found.
VARIABLE _GSV-FK-CTX
VARIABLE _GSV-FK-KA
VARIABLE _GSV-FK-KU
: _GSV-FIND-KEY  ( ctx key-a key-u -- flag )
    _GSV-FK-KU ! _GSV-FK-KA ! _GSV-FK-CTX !
    _GSV-FK-CTX @ _GSV-REWIND
    _GSV-FK-CTX @ _GSV-O-MCOUNT + @ 0 ?DO
        \ Read key (must be text string)
        CBOR-TYPE CBOR-MT-TSTR <> IF
            CBOR-SKIP CBOR-SKIP        \ skip unknown key + value
        ELSE
            CBOR-NEXT-TSTR              ( addr len )
            _GSV-FK-KA @ _GSV-FK-KU @ _GSV-STREQ IF
                -1 UNLOOP EXIT          \ found — cursor on value
            THEN
            CBOR-SKIP                   \ skip value
        THEN
    LOOP
    0 ;

\ GLOAD-INT ( ctx key-a key-u -- val )
\   Look up an integer value by key.  Returns 0 if not found.
: GLOAD-INT  ( ctx key-a key-u -- val )
    _GSV-FIND-KEY IF
        CBOR-TYPE CBOR-MT-UINT = IF
            CBOR-NEXT-UINT EXIT
        THEN
        CBOR-SKIP
    THEN
    0 ;

\ GLOAD-STR ( ctx key-a key-u -- addr len )
\   Look up a text string value by key.  Returns 0 0 if not found.
\   Returned addr points into the load buffer — valid until GLOAD-CLOSE.
: GLOAD-STR  ( ctx key-a key-u -- addr len )
    _GSV-FIND-KEY IF
        CBOR-TYPE CBOR-MT-TSTR = IF
            CBOR-NEXT-TSTR EXIT
        THEN
        CBOR-SKIP
    THEN
    0 0 ;

\ GLOAD-BLOB ( ctx key-a key-u -- addr len )
\   Look up a byte string value by key.  Returns 0 0 if not found.
\   Returned addr points into the load buffer — valid until GLOAD-CLOSE.
: GLOAD-BLOB  ( ctx key-a key-u -- addr len )
    _GSV-FIND-KEY IF
        CBOR-TYPE CBOR-MT-BSTR = IF
            CBOR-NEXT-BSTR EXIT
        THEN
        CBOR-SKIP
    THEN
    0 0 ;

\ GLOAD-CLOSE ( ctx -- )
\   Free the load context.
: GLOAD-CLOSE  ( ctx -- )
    FREE ;

\ =====================================================================
\  §8 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _gsv-guard

' GSAVE-NEW   CONSTANT _gsave-new-xt
' GSAVE-INT   CONSTANT _gsave-int-xt
' GSAVE-STR   CONSTANT _gsave-str-xt
' GSAVE-BLOB  CONSTANT _gsave-blob-xt
' GSAVE-WRITE CONSTANT _gsave-write-xt
' GSAVE-FREE  CONSTANT _gsave-free-xt
' GLOAD-OPEN  CONSTANT _gload-open-xt
' GLOAD-INT   CONSTANT _gload-int-xt
' GLOAD-STR   CONSTANT _gload-str-xt
' GLOAD-BLOB  CONSTANT _gload-blob-xt
' GLOAD-CLOSE CONSTANT _gload-close-xt

: GSAVE-NEW   _gsave-new-xt   _gsv-guard WITH-GUARD ;
: GSAVE-INT   _gsave-int-xt   _gsv-guard WITH-GUARD ;
: GSAVE-STR   _gsave-str-xt   _gsv-guard WITH-GUARD ;
: GSAVE-BLOB  _gsave-blob-xt  _gsv-guard WITH-GUARD ;
: GSAVE-WRITE _gsave-write-xt _gsv-guard WITH-GUARD ;
: GSAVE-FREE  _gsave-free-xt  _gsv-guard WITH-GUARD ;
: GLOAD-OPEN  _gload-open-xt  _gsv-guard WITH-GUARD ;
: GLOAD-INT   _gload-int-xt   _gsv-guard WITH-GUARD ;
: GLOAD-STR   _gload-str-xt   _gsv-guard WITH-GUARD ;
: GLOAD-BLOB  _gload-blob-xt  _gsv-guard WITH-GUARD ;
: GLOAD-CLOSE _gload-close-xt _gsv-guard WITH-GUARD ;
[THEN] [THEN]
