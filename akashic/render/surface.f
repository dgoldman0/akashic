\ surface.f — Pixel buffer abstraction for rendering pipeline
\ Part of Akashic render library for Megapad-64 / KDOS
\
\ A surface is a flat RGBA8888 pixel buffer with width, height,
\ stride, and a clip rectangle.  All rendering targets use this
\ abstraction — framebuffers, off-screen images, sub-windows.
\
\ Pixel format: 32-bit RGBA8888
\   bits [31:24] = R   [23:16] = G   [15:8] = B   [7:0] = A
\   Compatible with COLOR-PACK-RGBA / COLOR-UNPACK-RGBA.
\
\ Memory: pixel data is allocated via ALLOCATE (heap).
\ SURF-CREATE-FROM wraps an existing buffer (no allocation).
\
\ CMOVE convention: ( src dst len -- ) per KDOS.
\
\ Prefix: SURF-   (public API)
\         _SURF-  (internal helpers)
\
\ Load with:   REQUIRE surface.f
\
\ === Public API ===
\   SURF-CREATE      ( w h -- surf )       allocate surface
\   SURF-CREATE-FROM ( buf w h stride -- surf )  wrap existing buffer
\   SURF-DESTROY     ( surf -- )           free surface & descriptor
\   SURF-CLEAR       ( surf rgba -- )      fill with solid color
\   SURF-PIXEL@      ( surf x y -- rgba )  read pixel
\   SURF-PIXEL!      ( surf x y rgba -- )  write pixel
\   SURF-FILL-RECT   ( surf x y w h rgba -- )  fill rectangle
\   SURF-HLINE       ( surf x y len rgba -- )   horizontal span
\   SURF-CLIP!       ( surf x y w h -- )   set clip rectangle
\   SURF-CLIP-RESET  ( surf -- )           reset clip to full surface
\   SURF-BUF         ( surf -- addr )      pixel data pointer
\   SURF-W           ( surf -- w )         width
\   SURF-H           ( surf -- h )         height
\   SURF-STRIDE      ( surf -- stride )    bytes per row
\   SURF-BLIT        ( src dst dx dy -- )  copy src onto dst
\   SURF-BLIT-ALPHA  ( src dst dx dy -- )  alpha-blended blit
\   SURF-SUB         ( surf x y w h -- sub )  create sub-surface (shared buffer)
\   SURF-CLEAR-REGION ( surf x y w h rgba -- )  alias for SURF-FILL-RECT

REQUIRE ../math/color.f

PROVIDED akashic-surface

\ =====================================================================
\  Surface descriptor layout  (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   buf        pointer to pixel data (4 bytes/pixel, RGBA8888)
\  +8   width      width in pixels
\  +16  height     height in pixels
\  +24  stride     bytes per row (width × 4, or custom for sub-surfaces)
\  +32  clip-x     clip rect origin X
\  +40  clip-y     clip rect origin Y
\  +48  clip-w     clip rect width
\  +56  clip-h     clip rect height
\  +64  flags      bit 0: 1=owns buffer (SURF-DESTROY should free it)
\  +72  (reserved)

80 CONSTANT SURF-DESC-SIZE

: S.BUF     ( surf -- addr )  ;             \ +0
: S.W       ( surf -- addr )  8 + ;         \ +8
: S.H       ( surf -- addr )  16 + ;        \ +16
: S.STRIDE  ( surf -- addr )  24 + ;        \ +24
: S.CLIP-X  ( surf -- addr )  32 + ;        \ +32
: S.CLIP-Y  ( surf -- addr )  40 + ;        \ +40
: S.CLIP-W  ( surf -- addr )  48 + ;        \ +48
: S.CLIP-H  ( surf -- addr )  56 + ;        \ +56
: S.FLAGS   ( surf -- addr )  64 + ;        \ +64

\ Flag bits
1 CONSTANT _SURF-F-OWNS-BUF

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _SURF-TMP
VARIABLE _SURF-X
VARIABLE _SURF-Y
VARIABLE _SURF-W2
VARIABLE _SURF-H2
VARIABLE _SURF-RGBA
VARIABLE _SURF-PTR
VARIABLE _SURF-CNT
VARIABLE _SURF-SRC
VARIABLE _SURF-DST
VARIABLE _SURF-DX
VARIABLE _SURF-DY
VARIABLE _SURF-ROW
VARIABLE _SURF-I
VARIABLE _SURF-J

\ Dedicated variables for SURF-FILL-RECT (avoid clobbering by SURF-HLINE)
VARIABLE _SFR-SURF
VARIABLE _SFR-X
VARIABLE _SFR-Y
VARIABLE _SFR-W
VARIABLE _SFR-H
VARIABLE _SFR-RGBA

\ =====================================================================
\  Accessors
\ =====================================================================

: SURF-BUF     ( surf -- addr )    S.BUF @ ;
: SURF-W       ( surf -- w )       S.W @ ;
: SURF-H       ( surf -- h )       S.H @ ;
: SURF-STRIDE  ( surf -- stride )  S.STRIDE @ ;

\ =====================================================================
\  SURF-CREATE — Allocate a new surface
\ =====================================================================
\  ( w h -- surf )
\  Allocates pixel buffer (w×h×4 bytes) and descriptor (80 bytes).
\  Clip rect set to full surface.  Buffer zeroed (transparent black).

: SURF-CREATE  ( w h -- surf )
    OVER _SURF-W2 !        \ save w
    DUP  _SURF-H2 !        \ save h

    \ Allocate descriptor
    SURF-DESC-SIZE ALLOCATE
    0<> ABORT" SURF-CREATE: descriptor alloc failed"
    _SURF-TMP !             \ surf → TMP

    \ Allocate pixel buffer: w × h × 4
    _SURF-W2 @ _SURF-H2 @ * 4 * ALLOCATE
    0<> IF
        _SURF-TMP @ FREE
        0 ABORT" SURF-CREATE: pixel buffer alloc failed"
    THEN
    _SURF-PTR !             \ buf → PTR

    \ Zero the pixel buffer
    _SURF-PTR @
    _SURF-W2 @ _SURF-H2 @ * 4 *
    0 FILL

    \ Fill descriptor
    _SURF-PTR @           _SURF-TMP @ S.BUF    !
    _SURF-W2 @            _SURF-TMP @ S.W      !
    _SURF-H2 @            _SURF-TMP @ S.H      !
    _SURF-W2 @ 4 *        _SURF-TMP @ S.STRIDE !
    0                     _SURF-TMP @ S.CLIP-X !
    0                     _SURF-TMP @ S.CLIP-Y !
    _SURF-W2 @            _SURF-TMP @ S.CLIP-W !
    _SURF-H2 @            _SURF-TMP @ S.CLIP-H !
    _SURF-F-OWNS-BUF     _SURF-TMP @ S.FLAGS  !

    _SURF-TMP @ ;

\ =====================================================================
\  SURF-CREATE-FROM — Wrap an existing pixel buffer
\ =====================================================================
\  ( buf w h stride -- surf )
\  Does not allocate pixel data.  SURF-DESTROY will NOT free the buffer.

: SURF-CREATE-FROM  ( buf w h stride -- surf )
    _SURF-TMP !            \ stride → TMP (reused below)
    _SURF-H2 !             \ h
    _SURF-W2 !             \ w
    _SURF-PTR !            \ buf

    SURF-DESC-SIZE ALLOCATE
    0<> ABORT" SURF-CREATE-FROM: descriptor alloc failed"
    _SURF-RGBA !           \ surf → RGBA (temp name)

    _SURF-PTR @            _SURF-RGBA @ S.BUF    !
    _SURF-W2 @             _SURF-RGBA @ S.W      !
    _SURF-H2 @             _SURF-RGBA @ S.H      !
    _SURF-TMP @            _SURF-RGBA @ S.STRIDE !
    0                      _SURF-RGBA @ S.CLIP-X !
    0                      _SURF-RGBA @ S.CLIP-Y !
    _SURF-W2 @             _SURF-RGBA @ S.CLIP-W !
    _SURF-H2 @             _SURF-RGBA @ S.CLIP-H !
    0                      _SURF-RGBA @ S.FLAGS  !

    _SURF-RGBA @ ;

\ =====================================================================
\  SURF-DESTROY — Free surface
\ =====================================================================
\  ( surf -- )
\  If the surface owns its buffer (created via SURF-CREATE), free it.
\  Always frees the descriptor.

: SURF-DESTROY  ( surf -- )
    DUP S.FLAGS @ _SURF-F-OWNS-BUF AND IF
        DUP S.BUF @ FREE
    THEN
    FREE ;

\ =====================================================================
\  SURF-CLIP! — Set clip rectangle
\ =====================================================================
\  ( surf x y w h -- )
\  Clips to surface bounds.

: SURF-CLIP!  ( surf x y w h -- )
    _SURF-H2 !  _SURF-W2 !  _SURF-Y !  _SURF-X !  _SURF-TMP !

    \ Clamp origin
    _SURF-X @ 0 MAX _SURF-TMP @ SURF-W MIN  _SURF-X !
    _SURF-Y @ 0 MAX _SURF-TMP @ SURF-H MIN  _SURF-Y !

    \ Clamp extent
    _SURF-X @ _SURF-W2 @ +  _SURF-TMP @ SURF-W MIN  _SURF-X @ -
    0 MAX _SURF-W2 !
    _SURF-Y @ _SURF-H2 @ +  _SURF-TMP @ SURF-H MIN  _SURF-Y @ -
    0 MAX _SURF-H2 !

    _SURF-X @   _SURF-TMP @ S.CLIP-X !
    _SURF-Y @   _SURF-TMP @ S.CLIP-Y !
    _SURF-W2 @  _SURF-TMP @ S.CLIP-W !
    _SURF-H2 @  _SURF-TMP @ S.CLIP-H !
    ;

\ =====================================================================
\  SURF-CLIP-RESET — Reset clip to full surface
\ =====================================================================

: SURF-CLIP-RESET  ( surf -- )
    0 OVER S.CLIP-X !
    0 OVER S.CLIP-Y !
    DUP SURF-W OVER S.CLIP-W !
    DUP SURF-H SWAP S.CLIP-H !
    ;

\ =====================================================================
\  Internal: compute pixel address
\ =====================================================================
\  _SURF-ADDR ( surf x y -- addr )
\  addr = buf + y * stride + x * 4
\  No bounds checking — caller must validate.

: _SURF-ADDR  ( surf x y -- addr )
    ROT              ( x y surf )
    DUP S.STRIDE @   ( x y surf stride )
    ROT *            ( x surf y*stride )
    SWAP S.BUF @ +   ( x base+y*stride )
    SWAP 4 * + ;     ( pixel-addr )

\ =====================================================================
\  Internal: clip check for single pixel
\ =====================================================================
\  _SURF-CLIP? ( surf x y -- flag )
\  Returns TRUE if (x,y) is within the clip rectangle.

: _SURF-CLIP?  ( surf x y -- flag )
    _SURF-Y !  _SURF-X !  _SURF-TMP !

    _SURF-X @ _SURF-TMP @ S.CLIP-X @ < IF 0 EXIT THEN
    _SURF-Y @ _SURF-TMP @ S.CLIP-Y @ < IF 0 EXIT THEN
    _SURF-X @ _SURF-TMP @ S.CLIP-X @ _SURF-TMP @ S.CLIP-W @ + >= IF 0 EXIT THEN
    _SURF-Y @ _SURF-TMP @ S.CLIP-Y @ _SURF-TMP @ S.CLIP-H @ + >= IF 0 EXIT THEN
    -1 ;

\ =====================================================================
\  SURF-PIXEL@ — Read one pixel
\ =====================================================================
\  ( surf x y -- rgba )
\  Returns 0 (transparent black) if out of bounds.

: SURF-PIXEL@  ( surf x y -- rgba )
    _SURF-Y !  _SURF-X !  _SURF-TMP !
    \ Bounds check
    _SURF-X @ 0< IF 0 EXIT THEN
    _SURF-Y @ 0< IF 0 EXIT THEN
    _SURF-X @ _SURF-TMP @ SURF-W >= IF 0 EXIT THEN
    _SURF-Y @ _SURF-TMP @ SURF-H >= IF 0 EXIT THEN
    _SURF-TMP @ _SURF-X @ _SURF-Y @  _SURF-ADDR L@ ;

\ =====================================================================
\  SURF-PIXEL! — Write one pixel
\ =====================================================================
\  ( surf x y rgba -- )
\  Clipped: silently discards if outside clip rect.

: SURF-PIXEL!  ( surf x y rgba -- )
    _SURF-RGBA !  _SURF-Y !  _SURF-X !  _SURF-TMP !
    \ Clip check
    _SURF-X @ _SURF-TMP @ S.CLIP-X @ < IF EXIT THEN
    _SURF-Y @ _SURF-TMP @ S.CLIP-Y @ < IF EXIT THEN
    _SURF-X @ _SURF-TMP @ S.CLIP-X @  _SURF-TMP @ S.CLIP-W @ + >= IF EXIT THEN
    _SURF-Y @ _SURF-TMP @ S.CLIP-Y @  _SURF-TMP @ S.CLIP-H @ + >= IF EXIT THEN
    \ Write
    _SURF-RGBA @  _SURF-TMP @ _SURF-X @ _SURF-Y @ _SURF-ADDR  L! ;

\ =====================================================================
\  SURF-HLINE — Horizontal span (fast path)
\ =====================================================================
\  ( surf x y len rgba -- )
\  Draws a horizontal line of `len` pixels starting at (x, y).
\  Clipped to the surface clip rectangle.

: SURF-HLINE  ( surf x y len rgba -- )
    _SURF-RGBA !  _SURF-CNT !  _SURF-Y !  _SURF-X !  _SURF-TMP !

    \ Vertical clip
    _SURF-Y @ _SURF-TMP @ S.CLIP-Y @ < IF EXIT THEN
    _SURF-Y @ _SURF-TMP @ S.CLIP-Y @  _SURF-TMP @ S.CLIP-H @ + >= IF EXIT THEN

    \ Horizontal clip — left edge
    _SURF-X @ _SURF-TMP @ S.CLIP-X @ < IF
        _SURF-TMP @ S.CLIP-X @  _SURF-X @ -   ( chop )
        _SURF-CNT @ OVER - _SURF-CNT !
        _SURF-TMP @ S.CLIP-X @  _SURF-X !
        DROP
    THEN
    _SURF-CNT @ 1 < IF EXIT THEN

    \ Horizontal clip — right edge
    _SURF-X @ _SURF-CNT @ +
    _SURF-TMP @ S.CLIP-X @  _SURF-TMP @ S.CLIP-W @ +
    OVER < IF
        DROP                              \ drop x+cnt
        _SURF-TMP @ S.CLIP-X @  _SURF-TMP @ S.CLIP-W @ +
        _SURF-X @ -  _SURF-CNT !
    ELSE
        DROP
    THEN
    _SURF-CNT @ 1 < IF EXIT THEN

    \ Compute start address
    _SURF-TMP @ _SURF-X @ _SURF-Y @ _SURF-ADDR   _SURF-PTR !

    \ Fill loop: write 32-bit RGBA for each pixel
    _SURF-CNT @ 0 DO
        _SURF-RGBA @  _SURF-PTR @  L!
        _SURF-PTR @ 4 + _SURF-PTR !
    LOOP ;

\ =====================================================================
\  SURF-FILL-RECT — Fill a rectangle with a solid color
\ =====================================================================
\  ( surf x y w h rgba -- )
\  Clipped to the clip rectangle.  Delegates to SURF-HLINE per row.

: SURF-FILL-RECT  ( surf x y w h rgba -- )
    _SFR-RGBA !  _SFR-H !  _SFR-W !  _SFR-Y !  _SFR-X !  _SFR-SURF !

    _SFR-H @ 0 DO
        _SFR-SURF @
        _SFR-X @
        _SFR-Y @ I +
        _SFR-W @
        _SFR-RGBA @
        SURF-HLINE
    LOOP ;

: SURF-CLEAR-REGION  ( surf x y w h rgba -- )
    SURF-FILL-RECT ;

\ =====================================================================
\  SURF-CLEAR — Fill entire surface with one color
\ =====================================================================
\  ( surf rgba -- )
\  Ignores clip rectangle — clears the entire buffer.

: SURF-CLEAR  ( surf rgba -- )
    _SURF-RGBA !  _SURF-TMP !

    _SURF-TMP @ SURF-BUF  _SURF-PTR !
    _SURF-TMP @ SURF-W  _SURF-TMP @ SURF-H *  _SURF-CNT !

    _SURF-CNT @ 0 DO
        _SURF-RGBA @ _SURF-PTR @ L!
        _SURF-PTR @ 4 + _SURF-PTR !
    LOOP ;

\ =====================================================================
\  SURF-BLIT — Copy one surface onto another
\ =====================================================================
\  ( src dst dx dy -- )
\  Copies src's pixels onto dst at offset (dx, dy).
\  Clips to dst's clip rectangle.  Opaque copy (no alpha blending).

VARIABLE _SURF-SRC-W
VARIABLE _SURF-SRC-H
VARIABLE _SURF-SX
VARIABLE _SURF-SY
VARIABLE _SURF-CW
VARIABLE _SURF-CH

: SURF-BLIT  ( src dst dx dy -- )
    _SURF-DY !  _SURF-DX !  _SURF-DST !  _SURF-SRC !

    _SURF-SRC @ SURF-W _SURF-SRC-W !
    _SURF-SRC @ SURF-H _SURF-SRC-H !
    0 _SURF-SX !   0 _SURF-SY !

    \ Clip left: if dx < clip-x, trim source from left
    _SURF-DX @ _SURF-DST @ S.CLIP-X @ < IF
        _SURF-DST @ S.CLIP-X @  _SURF-DX @ -  ( trim )
        DUP _SURF-SX +!
        _SURF-SRC-W @ OVER - _SURF-SRC-W !
        _SURF-DX @ + _SURF-DX !
    THEN

    \ Clip top: if dy < clip-y, trim source from top
    _SURF-DY @ _SURF-DST @ S.CLIP-Y @ < IF
        _SURF-DST @ S.CLIP-Y @  _SURF-DY @ -  ( trim )
        DUP _SURF-SY +!
        _SURF-SRC-H @ OVER - _SURF-SRC-H !
        _SURF-DY @ + _SURF-DY !
    THEN

    \ Clip right
    _SURF-DX @ _SURF-SRC-W @ +
    _SURF-DST @ S.CLIP-X @  _SURF-DST @ S.CLIP-W @ +
    OVER < IF
        DROP
        _SURF-DST @ S.CLIP-X @  _SURF-DST @ S.CLIP-W @ +
        _SURF-DX @ -  _SURF-SRC-W !
    ELSE
        DROP
    THEN

    \ Clip bottom
    _SURF-DY @ _SURF-SRC-H @ +
    _SURF-DST @ S.CLIP-Y @  _SURF-DST @ S.CLIP-H @ +
    OVER < IF
        DROP
        _SURF-DST @ S.CLIP-Y @  _SURF-DST @ S.CLIP-H @ +
        _SURF-DY @ -  _SURF-SRC-H !
    ELSE
        DROP
    THEN

    \ Bail if nothing to blit
    _SURF-SRC-W @ 1 < IF EXIT THEN
    _SURF-SRC-H @ 1 < IF EXIT THEN

    \ Blit row by row
    _SURF-SRC-H @ 0 DO
        \ src row address
        _SURF-SRC @ _SURF-SX @ _SURF-SY @ I + _SURF-ADDR   _SURF-PTR !
        \ dst row address
        _SURF-DST @ _SURF-DX @ _SURF-DY @ I + _SURF-ADDR   _SURF-ROW !
        \ Copy: CMOVE ( src dst len )
        _SURF-PTR @  _SURF-ROW @  _SURF-SRC-W @ 4 *  CMOVE
    LOOP ;

\ =====================================================================
\  SURF-BLIT-ALPHA — Alpha-blended blit
\ =====================================================================
\  ( src dst dx dy -- )
\  Same as SURF-BLIT but blends each pixel using premultiplied alpha.
\  Uses COLOR-BLEND from color.f.

VARIABLE _SURF-AB-S     \ source pixel
VARIABLE _SURF-AB-D     \ dest pixel
VARIABLE _SURF-AB-A     \ source address
VARIABLE _SURF-AB-B     \ dest address

: SURF-BLIT-ALPHA  ( src dst dx dy -- )
    _SURF-DY !  _SURF-DX !  _SURF-DST !  _SURF-SRC !

    _SURF-SRC @ SURF-W _SURF-SRC-W !
    _SURF-SRC @ SURF-H _SURF-SRC-H !
    0 _SURF-SX !   0 _SURF-SY !

    \ Same clipping as SURF-BLIT
    _SURF-DX @ _SURF-DST @ S.CLIP-X @ < IF
        _SURF-DST @ S.CLIP-X @  _SURF-DX @ -
        DUP _SURF-SX +!
        _SURF-SRC-W @ OVER - _SURF-SRC-W !
        _SURF-DX @ + _SURF-DX !
    THEN

    _SURF-DY @ _SURF-DST @ S.CLIP-Y @ < IF
        _SURF-DST @ S.CLIP-Y @  _SURF-DY @ -
        DUP _SURF-SY +!
        _SURF-SRC-H @ OVER - _SURF-SRC-H !
        _SURF-DY @ + _SURF-DY !
    THEN

    _SURF-DX @ _SURF-SRC-W @ +
    _SURF-DST @ S.CLIP-X @  _SURF-DST @ S.CLIP-W @ +
    OVER < IF
        DROP
        _SURF-DST @ S.CLIP-X @  _SURF-DST @ S.CLIP-W @ +
        _SURF-DX @ -  _SURF-SRC-W !
    ELSE  DROP  THEN

    _SURF-DY @ _SURF-SRC-H @ +
    _SURF-DST @ S.CLIP-Y @  _SURF-DST @ S.CLIP-H @ +
    OVER < IF
        DROP
        _SURF-DST @ S.CLIP-Y @  _SURF-DST @ S.CLIP-H @ +
        _SURF-DY @ -  _SURF-SRC-H !
    ELSE  DROP  THEN

    _SURF-SRC-W @ 1 < IF EXIT THEN
    _SURF-SRC-H @ 1 < IF EXIT THEN

    \ Alpha-blended blit: pixel by pixel
    _SURF-SRC-H @ 0 DO
        _SURF-SRC @ _SURF-SX @ _SURF-SY @ I + _SURF-ADDR   _SURF-AB-A !
        _SURF-DST @ _SURF-DX @ _SURF-DY @ I + _SURF-ADDR   _SURF-AB-B !

        _SURF-SRC-W @ 0 DO
            _SURF-AB-A @ L@  _SURF-AB-S !
            _SURF-AB-B @ L@  _SURF-AB-D !

            \ Skip fully transparent source pixels
            _SURF-AB-S @ 0xFF AND 0= IF
                \ do nothing — keep dst
            ELSE
                \ Unpack src, unpack dst, blend, pack, store
                _SURF-AB-S @ COLOR-UNPACK-RGBA   ( sr sg sb sa )
                _SURF-AB-D @ COLOR-UNPACK-RGBA   ( sr sg sb sa dr dg db da )
                COLOR-BLEND                       ( r g b a )
                COLOR-PACK-RGBA                   ( packed )
                _SURF-AB-B @ L!
            THEN

            _SURF-AB-A @ 4 + _SURF-AB-A !
            _SURF-AB-B @ 4 + _SURF-AB-B !
        LOOP
    LOOP ;

\ =====================================================================
\  SURF-SUB — Create sub-surface (shared backing buffer)
\ =====================================================================
\  ( surf x y w h -- sub )
\  The sub-surface aliases a rectangular region of the parent.
\  Uses the parent's stride.  Buffer is NOT owned (not freed).
\
\  Note: modifying pixels via the sub-surface modifies the parent.

: SURF-SUB  ( surf x y w h -- sub )
    _SURF-H2 !  _SURF-W2 !  _SURF-Y !  _SURF-X !  _SURF-TMP !

    \ Clamp to parent bounds
    _SURF-X @ 0 MAX  _SURF-TMP @ SURF-W MIN  _SURF-X !
    _SURF-Y @ 0 MAX  _SURF-TMP @ SURF-H MIN  _SURF-Y !
    _SURF-X @ _SURF-W2 @ +  _SURF-TMP @ SURF-W MIN  _SURF-X @ -
    0 MAX  _SURF-W2 !
    _SURF-Y @ _SURF-H2 @ +  _SURF-TMP @ SURF-H MIN  _SURF-Y @ -
    0 MAX  _SURF-H2 !

    \ Compute base address in parent
    _SURF-TMP @ _SURF-X @ _SURF-Y @ _SURF-ADDR   _SURF-PTR !

    \ Create via CREATE-FROM (not owned)
    _SURF-PTR @  _SURF-W2 @  _SURF-H2 @  _SURF-TMP @ SURF-STRIDE
    SURF-CREATE-FROM ;
