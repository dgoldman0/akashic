\ composite.f — Alpha compositing & blend modes for render pipeline
\ Part of Akashic render library for Megapad-64 / KDOS
\
\ Operates on packed RGBA8888 integers (same format as SURF-PIXEL!).
\ This is the fast-path alternative to COLOR-BLEND which works in
\ FP16 unpacked channels.  All per-pixel math here is integer-only.
\
\ Pixel format: 32-bit RGBA8888
\   bits [31:24] = R   [23:16] = G   [15:8] = B   [7:0] = A
\
\ Porter-Duff compositing modes operate on premultiplied alpha:
\   out = src_op(src) + dst_op(dst)
\
\ Blend modes (multiply, screen, overlay) combine RGB channels
\ and composite with source-over for alpha.
\
\ CMOVE convention: ( src dst len -- ) per KDOS.
\
\ Prefix: COMP-   (public API)
\         _COMP-  (internal helpers)
\
\ Load with:   REQUIRE render/composite.f
\
\ Dependencies:
\   akashic-surface   — surface pixel access & HLINE
\   akashic-color     — color packing (loaded by surface)
\
\ === Public API ===
\   COMP-OVER          ( src dst -- result )           source-over
\   COMP-IN            ( src dst -- result )           source-in
\   COMP-OUT           ( src dst -- result )           source-out
\   COMP-ATOP          ( src dst -- result )           source-atop
\   COMP-XOR           ( src dst -- result )           XOR
\   COMP-MULTIPLY      ( src dst -- result )           multiply blend
\   COMP-SCREEN        ( src dst -- result )           screen blend
\   COMP-OVERLAY       ( src dst -- result )           overlay blend
\   COMP-DARKEN        ( src dst -- result )           darken (min)
\   COMP-LIGHTEN       ( src dst -- result )           lighten (max)
\   COMP-OPACITY       ( rgba alpha -- rgba' )         scale alpha
\   COMP-SCANLINE-OVER ( src-addr dst-addr len -- )    bulk scanline
\   COMP-SCANLINE-COPY ( src-addr dst-addr len -- )    bulk opaque copy
\   COMP-BLIT-MONO     ( mono-buf w h surf x y fg -- ) monochrome blit

REQUIRE surface.f

PROVIDED akashic-composite

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _COMP-SR   VARIABLE _COMP-SG   VARIABLE _COMP-SB   VARIABLE _COMP-SA
VARIABLE _COMP-DR   VARIABLE _COMP-DG   VARIABLE _COMP-DB   VARIABLE _COMP-DA
VARIABLE _COMP-TMP
VARIABLE _COMP-PTR
VARIABLE _COMP-CNT
VARIABLE _COMP-SURF

\ =====================================================================
\  Internal helpers — integer channel extraction and packing
\ =====================================================================
\  All work on 0..255 integer channels, no FP16.

\ Unpack RGBA8888 to 4 integer channels on stack
: _COMP-UNPACK  ( rgba -- r g b a )
    DUP 24 RSHIFT 0xFF AND SWAP    ( r rgba )
    DUP 16 RSHIFT 0xFF AND SWAP    ( r g rgba )
    DUP  8 RSHIFT 0xFF AND SWAP    ( r g b rgba )
                  0xFF AND ;       ( r g b a )

\ Pack 4 integer channels (clamped 0..255) to RGBA8888
: _COMP-PACK  ( r g b a -- rgba )
    0xFF AND                                ( r g b a8 )
    SWAP 0xFF AND  8 LSHIFT OR             ( r g ba )
    SWAP 0xFF AND 16 LSHIFT OR             ( r gba )
    SWAP 0xFF AND 24 LSHIFT OR ;           ( rgba )

\ Integer multiply: (a * b) / 255  using the fast approximation
\ (a * b + 128) >> 8 ... but more accurate: ((a*b)+1 + ((a*b)>>8)) >> 8
\ For speed, use (a * b + 127) / 255 ≈ (a * b + 128) >> 8
: _COMP-MUL255  ( a b -- result )
    * 128 + 8 RSHIFT
    0 MAX 255 MIN ;

\ =====================================================================
\  COMP-OVER — Source-over (Porter-Duff)
\ =====================================================================
\  out = src + dst * (1 - src_alpha)
\  Inputs should be premultiplied.
\  ( src dst -- result )

: COMP-OVER  ( src dst -- result )
    OVER 0xFF AND                    ( src dst sa )
    DUP 255 = IF
        DROP DROP EXIT               \ fully opaque src, just return src
    THEN
    DUP 0= IF
        DROP SWAP DROP EXIT           \ fully transparent src, return dst
    THEN
    255 SWAP -                        ( src dst inv-sa )
    _COMP-TMP !

    _COMP-UNPACK                     ( src dr dg db da )
    _COMP-TMP @ _COMP-MUL255 _COMP-DA !   ( src dr dg db' )
    _COMP-TMP @ _COMP-MUL255 _COMP-DB !   ( src dr dg' )
    _COMP-TMP @ _COMP-MUL255 _COMP-DG !   ( src dr' )
    _COMP-TMP @ _COMP-MUL255 _COMP-DR !   ( src )

    _COMP-UNPACK                     ( sr sg sb sa )
    _COMP-DA @ + 255 MIN _COMP-DA !
    _COMP-DB @ + 255 MIN _COMP-DB !
    _COMP-DG @ + 255 MIN _COMP-DG !
    _COMP-DR @ + 255 MIN _COMP-DR !

    _COMP-DR @ _COMP-DG @ _COMP-DB @ _COMP-DA @
    _COMP-PACK ;

\ =====================================================================
\  COMP-IN — Source-in (Porter-Duff)
\ =====================================================================
\  out = src * dst_alpha
\  ( src dst -- result )

: COMP-IN  ( src dst -- result )
    0xFF AND                          ( src da )
    _COMP-TMP !
    _COMP-UNPACK                     ( sr sg sb sa )
    _COMP-TMP @ _COMP-MUL255        ( sr sg sb sa' )
    >R
    _COMP-TMP @ _COMP-MUL255        ( sr sg sb' )
    >R
    _COMP-TMP @ _COMP-MUL255        ( sr sg' )
    >R
    _COMP-TMP @ _COMP-MUL255        ( sr' )
    R> R> R>                         ( sr' sg' sb' sa' )
    _COMP-PACK ;

\ =====================================================================
\  COMP-OUT — Source-out (Porter-Duff)
\ =====================================================================
\  out = src * (1 - dst_alpha)
\  ( src dst -- result )

: COMP-OUT  ( src dst -- result )
    0xFF AND 255 SWAP -               ( src inv-da )
    _COMP-TMP !
    _COMP-UNPACK                     ( sr sg sb sa )
    _COMP-TMP @ _COMP-MUL255
    >R
    _COMP-TMP @ _COMP-MUL255
    >R
    _COMP-TMP @ _COMP-MUL255
    >R
    _COMP-TMP @ _COMP-MUL255
    R> R> R>
    _COMP-PACK ;

\ =====================================================================
\  COMP-ATOP — Source-atop (Porter-Duff)
\ =====================================================================
\  out = src * dst_alpha + dst * (1 - src_alpha)
\  ( src dst -- result )

: COMP-ATOP  ( src dst -- result )
    OVER 0xFF AND 255 SWAP -  _COMP-SA !    \ inv-src-alpha
    DUP  0xFF AND             _COMP-DA !    \ dst-alpha

    _COMP-UNPACK                     ( src dr dg db da )
    _COMP-SA @ _COMP-MUL255 >R      ( src dr dg db ) ( R: da' )
    _COMP-SA @ _COMP-MUL255 >R      ( src dr dg )    ( R: da' db' )
    _COMP-SA @ _COMP-MUL255 >R      ( src dr )       ( R: da' db' dg' )
    _COMP-SA @ _COMP-MUL255 >R      ( src )          ( R: da' db' dg' dr' )

    _COMP-UNPACK                     ( sr sg sb sa )
    _COMP-DA @ _COMP-MUL255         ( sr sg sb sa' )
    R> + 255 MIN                     ( sr sg sb  r+sa' )
    SWAP                             ( sr sg r+sa' sb )
    _COMP-DA @ _COMP-MUL255         ( sr sg r+sa' sb' )
    R> + 255 MIN                     ( sr sg r+sa' b' )
    SWAP ROT                         ( sr b' r+sa' sg )
    _COMP-DA @ _COMP-MUL255         ( sr b' r+sa' sg' )
    R> + 255 MIN                     ( sr b' r+sa' g' )
    SWAP ROT ROT                     ( r+sa' g' sr b' )
    SWAP                             ( r+sa' g' b' sr )
    _COMP-DA @ _COMP-MUL255         ( r+sa' g' b' sr' )
    R> + 255 MIN                     ( r+sa' g' b' a' )
    >R ROT R>                        ( g' b' r+sa' a' )
    >R >R SWAP R> SWAP R>            ( r+sa' g' b' a' )
    _COMP-PACK ;

\ =====================================================================
\  COMP-XOR — XOR (Porter-Duff)
\ =====================================================================
\  out = src * (1 - dst_alpha) + dst * (1 - src_alpha)
\  ( src dst -- result )

: COMP-XOR  ( src dst -- result )
    OVER 0xFF AND 255 SWAP - _COMP-SA !   \ inv-src-alpha
    DUP  0xFF AND 255 SWAP - _COMP-DA !   \ inv-dst-alpha

    _COMP-UNPACK                     ( src dr dg db da )
    _COMP-SA @ _COMP-MUL255 _COMP-DB !  ( src dr dg db -- reusing vars )
    _COMP-SA @ _COMP-MUL255 _COMP-DG !
    _COMP-SA @ _COMP-MUL255 _COMP-DR !
    _COMP-SA @ _COMP-MUL255
    _COMP-DB @ SWAP _COMP-DG @ SWAP _COMP-DR @ SWAP
    \ Stack: ( src d.r' d.g' d.b' d.a' )
    >R >R >R >R

    _COMP-UNPACK                     ( sr sg sb sa )
    _COMP-DA @ _COMP-MUL255 R> + 255 MIN    ( sr sg sb a' )
    >R
    _COMP-DA @ _COMP-MUL255 R> + 255 MIN    ( sr sg b' )
    >R
    _COMP-DA @ _COMP-MUL255 R> + 255 MIN    ( sr g' )
    >R
    _COMP-DA @ _COMP-MUL255 R> + 255 MIN    ( r' )
    R> R> R>                         ( r' g' b' a' )
    _COMP-PACK ;

\ =====================================================================
\  Blend modes — operate per-channel on RGB, then composite alpha
\ =====================================================================
\  These assume non-premultiplied or use a simplified model:
\    result_ch = blend(src_ch, dst_ch)
\    result composited via source-over for alpha.

\ Helper: apply a blend function to all channels, then composite alpha.
\ Expects src and dst unpacked in variables, blend XT on stack.
\ We inline the blend modes instead for simplicity + no DEFER needed.

\ =====================================================================
\  COMP-MULTIPLY — Multiply blend
\ =====================================================================
\  result_ch = src_ch * dst_ch / 255
\  result_alpha = src_a + dst_a * (1 - src_a)
\  ( src dst -- result )

: COMP-MULTIPLY  ( src dst -- result )
    _COMP-UNPACK _COMP-DA ! _COMP-DB ! _COMP-DG ! _COMP-DR !
    _COMP-UNPACK _COMP-SA ! _COMP-SB ! _COMP-SG ! _COMP-SR !

    \ Blend RGB: ch = src * dst / 255
    _COMP-SR @ _COMP-DR @ _COMP-MUL255
    _COMP-SG @ _COMP-DG @ _COMP-MUL255
    _COMP-SB @ _COMP-DB @ _COMP-MUL255

    \ Alpha: sa + da * (1 - sa)
    255 _COMP-SA @ - _COMP-TMP !
    _COMP-SA @ _COMP-DA @ _COMP-TMP @ _COMP-MUL255 + 255 MIN

    _COMP-PACK ;

\ =====================================================================
\  COMP-SCREEN — Screen blend
\ =====================================================================
\  result_ch = src + dst - src * dst / 255
\  ( src dst -- result )

: COMP-SCREEN  ( src dst -- result )
    _COMP-UNPACK _COMP-DA ! _COMP-DB ! _COMP-DG ! _COMP-DR !
    _COMP-UNPACK _COMP-SA ! _COMP-SB ! _COMP-SG ! _COMP-SR !

    \ Screen: s + d - s*d/255
    _COMP-SR @ _COMP-DR @ + _COMP-SR @ _COMP-DR @ _COMP-MUL255 - 0 MAX 255 MIN
    _COMP-SG @ _COMP-DG @ + _COMP-SG @ _COMP-DG @ _COMP-MUL255 - 0 MAX 255 MIN
    _COMP-SB @ _COMP-DB @ + _COMP-SB @ _COMP-DB @ _COMP-MUL255 - 0 MAX 255 MIN

    \ Alpha
    255 _COMP-SA @ - _COMP-TMP !
    _COMP-SA @ _COMP-DA @ _COMP-TMP @ _COMP-MUL255 + 255 MIN

    _COMP-PACK ;

\ =====================================================================
\  COMP-OVERLAY — Overlay blend
\ =====================================================================
\  if dst_ch < 128: result = 2 * src * dst / 255
\  else:            result = 255 - 2 * (255-src) * (255-dst) / 255
\  ( src dst -- result )

VARIABLE _COMP-OV-CH

: _COMP-OVERLAY-CH  ( src-ch dst-ch -- result-ch )
    _COMP-OV-CH !
    _COMP-OV-CH @ 128 < IF
        \ 2 * s * d / 255
        _COMP-OV-CH @ _COMP-MUL255 2 * 255 MIN
    ELSE
        \ 255 - 2*(255-s)*(255-d)/255
        255 SWAP -  255 _COMP-OV-CH @ -  _COMP-MUL255 2 *
        255 SWAP - 0 MAX
    THEN ;

: COMP-OVERLAY  ( src dst -- result )
    _COMP-UNPACK _COMP-DA ! _COMP-DB ! _COMP-DG ! _COMP-DR !
    _COMP-UNPACK _COMP-SA ! _COMP-SB ! _COMP-SG ! _COMP-SR !

    _COMP-SR @ _COMP-DR @ _COMP-OVERLAY-CH
    _COMP-SG @ _COMP-DG @ _COMP-OVERLAY-CH
    _COMP-SB @ _COMP-DB @ _COMP-OVERLAY-CH

    255 _COMP-SA @ - _COMP-TMP !
    _COMP-SA @ _COMP-DA @ _COMP-TMP @ _COMP-MUL255 + 255 MIN

    _COMP-PACK ;

\ =====================================================================
\  COMP-DARKEN / COMP-LIGHTEN — Min/Max blend
\ =====================================================================

: COMP-DARKEN  ( src dst -- result )
    _COMP-UNPACK _COMP-DA ! _COMP-DB ! _COMP-DG ! _COMP-DR !
    _COMP-UNPACK _COMP-SA ! _COMP-SB ! _COMP-SG ! _COMP-SR !

    _COMP-SR @ _COMP-DR @ MIN
    _COMP-SG @ _COMP-DG @ MIN
    _COMP-SB @ _COMP-DB @ MIN

    255 _COMP-SA @ - _COMP-TMP !
    _COMP-SA @ _COMP-DA @ _COMP-TMP @ _COMP-MUL255 + 255 MIN
    _COMP-PACK ;

: COMP-LIGHTEN  ( src dst -- result )
    _COMP-UNPACK _COMP-DA ! _COMP-DB ! _COMP-DG ! _COMP-DR !
    _COMP-UNPACK _COMP-SA ! _COMP-SB ! _COMP-SG ! _COMP-SR !

    _COMP-SR @ _COMP-DR @ MAX
    _COMP-SG @ _COMP-DG @ MAX
    _COMP-SB @ _COMP-DB @ MAX

    255 _COMP-SA @ - _COMP-TMP !
    _COMP-SA @ _COMP-DA @ _COMP-TMP @ _COMP-MUL255 + 255 MIN
    _COMP-PACK ;

\ =====================================================================
\  COMP-OPACITY — Scale alpha channel
\ =====================================================================
\  ( rgba alpha-byte -- rgba' )
\  Multiplies the alpha channel by alpha-byte/255.
\  Also scales RGB if premultiplied.

: COMP-OPACITY  ( rgba alpha -- rgba' )
    _COMP-TMP !
    _COMP-UNPACK                     ( r g b a )
    _COMP-TMP @ _COMP-MUL255        ( r g b a' )
    >R
    _COMP-TMP @ _COMP-MUL255        ( r g b' )
    >R
    _COMP-TMP @ _COMP-MUL255        ( r g' )
    >R
    _COMP-TMP @ _COMP-MUL255        ( r' )
    R> R> R>                         ( r' g' b' a' )
    _COMP-PACK ;

\ =====================================================================
\  COMP-SCANLINE-COPY — Bulk opaque pixel copy
\ =====================================================================
\  ( src-addr dst-addr len -- )
\  Copies `len` pixels (4 bytes each) from src to dst.
\  Uses CMOVE (KDOS: src dst len).

: COMP-SCANLINE-COPY  ( src-addr dst-addr len -- )
    4 * CMOVE ;

\ =====================================================================
\  COMP-SCANLINE-OVER — Bulk source-over compositing
\ =====================================================================
\  ( src-addr dst-addr len -- )
\  Composites `len` packed RGBA pixels from src over dst.

VARIABLE _COMP-SL-SRC
VARIABLE _COMP-SL-DST
VARIABLE _COMP-SL-CNT
VARIABLE _COMP-SL-S
VARIABLE _COMP-SL-D

: COMP-SCANLINE-OVER  ( src-addr dst-addr len -- )
    _COMP-SL-CNT !  _COMP-SL-DST !  _COMP-SL-SRC !

    _COMP-SL-CNT @ 0 DO
        _COMP-SL-SRC @ L@ _COMP-SL-S !
        _COMP-SL-DST @ L@ _COMP-SL-D !

        \ Fast path: skip transparent source
        _COMP-SL-S @ 0xFF AND 0= IF
            \ do nothing — keep dst
        ELSE
            \ Fast path: opaque source overwrites
            _COMP-SL-S @ 0xFF AND 255 = IF
                _COMP-SL-S @ _COMP-SL-DST @ L!
            ELSE
                \ General composite
                _COMP-SL-S @ _COMP-SL-D @ COMP-OVER
                _COMP-SL-DST @ L!
            THEN
        THEN

        _COMP-SL-SRC @ 4 + _COMP-SL-SRC !
        _COMP-SL-DST @ 4 + _COMP-SL-DST !
    LOOP ;

\ =====================================================================
\  COMP-BLIT-MONO — Blit monochrome bitmap with foreground color
\ =====================================================================
\  ( mono-buf w h surf x y fg-rgba -- )
\  For each non-zero byte in the mono bitmap, writes fg-rgba to the
\  surface at the corresponding (x+col, y+row) position.
\  Used for glyph rendering — replaces the DRAW-GLYPH inner loop.

VARIABLE _COMP-MONO-BUF
VARIABLE _COMP-MONO-W
VARIABLE _COMP-MONO-H
VARIABLE _COMP-MONO-X
VARIABLE _COMP-MONO-Y
VARIABLE _COMP-MONO-FG

: COMP-BLIT-MONO  ( mono-buf w h surf x y fg-rgba -- )
    _COMP-MONO-FG !
    _COMP-MONO-Y !  _COMP-MONO-X !
    _COMP-SURF !
    _COMP-MONO-H !  _COMP-MONO-W !
    _COMP-MONO-BUF !

    _COMP-MONO-H @ 0 DO
        _COMP-MONO-W @ 0 DO
            _COMP-MONO-BUF @  J _COMP-MONO-W @ * +  I +
            C@ 0<> IF
                _COMP-SURF @
                _COMP-MONO-X @ I +
                _COMP-MONO-Y @ J +
                _COMP-MONO-FG @
                SURF-PIXEL!
            THEN
        LOOP
    LOOP ;

\ =====================================================================
\  COMP-BLIT-MONO-ALPHA — Blit mono bitmap with alpha blending
\ =====================================================================
\  ( mono-buf w h surf x y fg-rgba -- )
\  Same as COMP-BLIT-MONO but the mono bitmap byte (0..255) is used
\  as the coverage/alpha value — 0xFF = fully opaque, intermediate
\  values = partial coverage.  Blends against existing surface pixels.

VARIABLE _COMP-MBA-BYTE
VARIABLE _COMP-MBA-SRC
VARIABLE _COMP-MBA-DST

: COMP-BLIT-MONO-ALPHA  ( mono-buf w h surf x y fg-rgba -- )
    _COMP-MONO-FG !
    _COMP-MONO-Y !  _COMP-MONO-X !
    _COMP-SURF !
    _COMP-MONO-H !  _COMP-MONO-W !
    _COMP-MONO-BUF !

    _COMP-MONO-H @ 0 DO
        _COMP-MONO-W @ 0 DO
            _COMP-MONO-BUF @  J _COMP-MONO-W @ * +  I +
            C@ DUP 0<> IF
                _COMP-MBA-BYTE !

                \ Build source color: fg with alpha scaled by coverage
                _COMP-MONO-FG @ _COMP-MBA-BYTE @ COMP-OPACITY
                _COMP-MBA-SRC !

                \ Read existing pixel
                _COMP-SURF @
                _COMP-MONO-X @ I +
                _COMP-MONO-Y @ J +
                SURF-PIXEL@
                _COMP-MBA-DST !

                \ Composite and write
                _COMP-MBA-SRC @ _COMP-MBA-DST @ COMP-OVER
                _COMP-TMP !

                _COMP-SURF @
                _COMP-MONO-X @ I +
                _COMP-MONO-Y @ J +
                _COMP-TMP @
                SURF-PIXEL!
            ELSE
                DROP
            THEN
        LOOP
    LOOP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _comp-guard

' COMP-OVER       CONSTANT _comp-over-xt
' COMP-IN         CONSTANT _comp-in-xt
' COMP-OUT        CONSTANT _comp-out-xt
' COMP-ATOP       CONSTANT _comp-atop-xt
' COMP-XOR        CONSTANT _comp-xor-xt
' COMP-MULTIPLY   CONSTANT _comp-multiply-xt
' COMP-SCREEN     CONSTANT _comp-screen-xt
' COMP-OVERLAY    CONSTANT _comp-overlay-xt
' COMP-DARKEN     CONSTANT _comp-darken-xt
' COMP-LIGHTEN    CONSTANT _comp-lighten-xt
' COMP-OPACITY    CONSTANT _comp-opacity-xt
' COMP-SCANLINE-COPY CONSTANT _comp-scanline-copy-xt
' COMP-SCANLINE-OVER CONSTANT _comp-scanline-over-xt
' COMP-BLIT-MONO  CONSTANT _comp-blit-mono-xt
' COMP-BLIT-MONO-ALPHA CONSTANT _comp-blit-mono-alpha-xt

: COMP-OVER       _comp-over-xt _comp-guard WITH-GUARD ;
: COMP-IN         _comp-in-xt _comp-guard WITH-GUARD ;
: COMP-OUT        _comp-out-xt _comp-guard WITH-GUARD ;
: COMP-ATOP       _comp-atop-xt _comp-guard WITH-GUARD ;
: COMP-XOR        _comp-xor-xt _comp-guard WITH-GUARD ;
: COMP-MULTIPLY   _comp-multiply-xt _comp-guard WITH-GUARD ;
: COMP-SCREEN     _comp-screen-xt _comp-guard WITH-GUARD ;
: COMP-OVERLAY    _comp-overlay-xt _comp-guard WITH-GUARD ;
: COMP-DARKEN     _comp-darken-xt _comp-guard WITH-GUARD ;
: COMP-LIGHTEN    _comp-lighten-xt _comp-guard WITH-GUARD ;
: COMP-OPACITY    _comp-opacity-xt _comp-guard WITH-GUARD ;
: COMP-SCANLINE-COPY _comp-scanline-copy-xt _comp-guard WITH-GUARD ;
: COMP-SCANLINE-OVER _comp-scanline-over-xt _comp-guard WITH-GUARD ;
: COMP-BLIT-MONO  _comp-blit-mono-xt _comp-guard WITH-GUARD ;
: COMP-BLIT-MONO-ALPHA _comp-blit-mono-alpha-xt _comp-guard WITH-GUARD ;
[THEN] [THEN]
