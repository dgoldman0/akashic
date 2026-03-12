\ cache.f — Glyph bitmap cache
\
\ Caches rasterized glyph bitmaps to avoid re-rasterizing frequently
\ used characters.  Direct-mapped hash table keyed on (glyph_id, size).
\
\ Each cache entry stores:
\   - glyph ID         (cell)
\   - pixel size        (cell)
\   - bitmap width      (cell)
\   - bitmap height     (cell)
\   - bitmap address    (cell)  — pointer into cache bitmap pool
\   - valid flag        (cell)
\
\ Bitmap pool: contiguous memory region.  New bitmaps are appended
\ sequentially.  When the pool is exhausted, the cache is flushed
\ and the pool pointer resets (simple generational eviction).
\
\ At 16×16 pixels (1 byte/pixel), each glyph bitmap = 256 bytes.
\ 256 cache slots × 256 bytes = 64 KiB pool — fits easily in memory.
\
\ Prefix: GC-    (public API)
\         _GC-   (internal)
\
\ Load with:   REQUIRE cache.f

PROVIDED akashic-cache
REQUIRE raster.f

\ =====================================================================
\  Configuration
\ =====================================================================

256 CONSTANT GC-SLOTS             \ number of cache slots (power of 2)
GC-SLOTS 1- CONSTANT _GC-MASK    \ hash mask

\ Maximum bitmap pool size: 256 slots × 32×32 bytes = 256 KiB
\ (enough for sizes up to 32px without eviction pressure)
262144 CONSTANT _GC-POOL-SIZE

\ =====================================================================
\  Cache entry table (6 cells per entry)
\ =====================================================================

HERE GC-SLOTS 6 * CELLS ALLOT CONSTANT _GC-TABLE

\ Entry field offsets (in cells)
0 CONSTANT _GCE-GID       \ glyph ID
1 CONSTANT _GCE-SIZE      \ pixel size
2 CONSTANT _GCE-W         \ bitmap width
3 CONSTANT _GCE-H         \ bitmap height
4 CONSTANT _GCE-BMP       \ bitmap address
5 CONSTANT _GCE-VALID     \ valid flag (0=empty, 1=valid)

: _GC-ENTRY  ( slot -- addr )  6 CELLS * _GC-TABLE + ;
: _GC-FIELD  ( slot field -- addr )  CELLS SWAP _GC-ENTRY + ;

\ =====================================================================
\  Bitmap pool
\ =====================================================================

HERE _GC-POOL-SIZE ALLOT CONSTANT _GC-POOL
VARIABLE _GC-POOL-PTR    \ next free byte in pool

: _GC-POOL-RESET  ( -- )  _GC-POOL _GC-POOL-PTR ! ;
_GC-POOL-RESET

: _GC-POOL-AVAIL  ( -- n )
    _GC-POOL _GC-POOL-SIZE + _GC-POOL-PTR @ - ;

: _GC-POOL-ALLOC  ( nbytes -- addr | 0 )
    DUP _GC-POOL-AVAIL > IF DROP 0 EXIT THEN
    _GC-POOL-PTR @        ( nbytes addr )
    SWAP _GC-POOL-PTR +! ;

\ =====================================================================
\  Hash function
\ =====================================================================
\  Simple XOR + multiply hash of (glyph_id, size).

: _GC-HASH  ( glyph-id size -- slot )
    SWAP 2654435761 *              \ Knuth multiplicative hash on gid
    XOR                            \ mix in size
    _GC-MASK AND ;

\ =====================================================================
\  Cache flush — invalidate all entries, reset pool
\ =====================================================================

: GC-FLUSH  ( -- )
    GC-SLOTS 0 DO
        0 I _GCE-VALID _GC-FIELD !
    LOOP
    _GC-POOL-RESET ;

GC-FLUSH

\ =====================================================================
\  Cache lookup
\ =====================================================================
\  Returns bitmap address, width, height if hit; 0 0 0 if miss.

: GC-LOOKUP  ( glyph-id size -- bmp-addr w h | 0 0 0 )
    2DUP _GC-HASH >R               ( gid size ) ( R: slot )
    R@ _GCE-VALID _GC-FIELD @ 0= IF
        2DROP R> DROP 0 0 0 EXIT    \ empty slot
    THEN
    R@ _GCE-GID _GC-FIELD @         ( gid size cached-gid )
    2 PICK <> IF
        2DROP R> DROP 0 0 0 EXIT    \ gid mismatch
    THEN
    R@ _GCE-SIZE _GC-FIELD @        ( gid size cached-size )
    OVER <> IF
        2DROP R> DROP 0 0 0 EXIT    \ size mismatch
    THEN
    2DROP
    R@ _GCE-BMP _GC-FIELD @
    R@ _GCE-W   _GC-FIELD @
    R> _GCE-H   _GC-FIELD @  ;

\ =====================================================================
\  Cache store — rasterize a glyph and store in cache
\ =====================================================================
\  Allocates bitmap from pool, calls RAST-GLYPH, stores entry.
\  If pool is exhausted, flushes entire cache first.
\  Returns bitmap address, width, height.

VARIABLE _GC-ST-GID   VARIABLE _GC-ST-SZ
VARIABLE _GC-ST-W     VARIABLE _GC-ST-H
VARIABLE _GC-ST-BMP   VARIABLE _GC-ST-SLOT

: GC-STORE  ( glyph-id size -- bmp-addr w h | 0 0 0 )
    _GC-ST-SZ !  _GC-ST-GID !
    \ Compute bitmap dimensions: w=size, h=(asc-desc)*size/upem
    _GC-ST-SZ @ _GC-ST-W !
    TTF-ASCENDER TTF-DESCENDER - _GC-ST-SZ @ * TTF-UPEM / _GC-ST-H !
    \ Compute needed bytes
    _GC-ST-W @ _GC-ST-H @ *          ( nbytes )
    \ Try to allocate from pool
    DUP _GC-POOL-ALLOC              ( nbytes addr|0 )
    DUP 0= IF
        \ Pool exhausted — flush and retry
        DROP GC-FLUSH
        _GC-POOL-ALLOC              ( addr|0 )
        DUP 0= IF
            DROP 0 0 0 EXIT         \ bitmap too large even for empty pool
        THEN
    ELSE
        NIP                          ( addr )
    THEN
    _GC-ST-BMP !
    \ Rasterize
    _GC-ST-GID @  _GC-ST-SZ @
    _GC-ST-BMP @  _GC-ST-W @  _GC-ST-H @
    RAST-GLYPH                       ( ok? )
    0= IF 0 0 0 EXIT THEN           \ rasterization failed
    \ Store in cache
    _GC-ST-GID @ _GC-ST-SZ @ _GC-HASH _GC-ST-SLOT !
    _GC-ST-GID @  _GC-ST-SLOT @ _GCE-GID   _GC-FIELD !
    _GC-ST-SZ  @  _GC-ST-SLOT @ _GCE-SIZE  _GC-FIELD !
    _GC-ST-W   @  _GC-ST-SLOT @ _GCE-W     _GC-FIELD !
    _GC-ST-H   @  _GC-ST-SLOT @ _GCE-H     _GC-FIELD !
    _GC-ST-BMP @  _GC-ST-SLOT @ _GCE-BMP   _GC-FIELD !
    1             _GC-ST-SLOT @ _GCE-VALID  _GC-FIELD !
    \ Return results
    _GC-ST-BMP @ _GC-ST-W @ _GC-ST-H @ ;

\ =====================================================================
\  GC-GET — lookup or rasterize (main API)
\ =====================================================================
\  Checks cache first; on miss, rasterizes and stores.
\  Returns ( bmp-addr w h ) or ( 0 0 0 ) on failure.
\  Pre: TTF tables must be parsed (HEAD, MAXP, HHEA, HMTX, LOCA, GLYF, CMAP).

: GC-GET  ( glyph-id size -- bmp-addr w h | 0 0 0 )
    2DUP GC-LOOKUP                   ( gid size bmp w h | gid size 0 0 0 )
    DUP 0<> IF
        \ Cache hit — drop gid and size, return bmp w h
        >R >R >R 2DROP R> R> R>
    ELSE
        \ Cache miss — drop the three zeros, rasterize and store
        DROP 2DROP
        GC-STORE
    THEN ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _fcache-guard

' GC-FLUSH        CONSTANT _gc-flush-xt
' GC-LOOKUP       CONSTANT _gc-lookup-xt
' GC-STORE        CONSTANT _gc-store-xt
' GC-GET          CONSTANT _gc-get-xt

: GC-FLUSH        _gc-flush-xt _fcache-guard WITH-GUARD ;
: GC-LOOKUP       _gc-lookup-xt _fcache-guard WITH-GUARD ;
: GC-STORE        _gc-store-xt _fcache-guard WITH-GUARD ;
: GC-GET          _gc-get-xt _fcache-guard WITH-GUARD ;
[THEN] [THEN]
