\ bmp.f — BMP image encoder
\
\ Encodes a surface (RGBA8888) as a Windows BMP file (32-bit BGRA,
\ uncompressed, bottom-to-top rows).
\
\ Load with:   REQUIRE bmp.f
\ Depends on:  surface.f (via REQUIRE)
\
\ Public API:
\   BMP-FILE-SIZE  ( w h -- bytes )     Compute output size
\   BMP-ENCODE     ( surf buf max -- len | 0 )  Encode surface → BMP
\
\ Returns 0 from BMP-ENCODE if buffer is too small.
\ =====================================================================

REQUIRE surface.f

PROVIDED akashic-bmp

\ =====================================================================
\  Constants
\ =====================================================================

54 CONSTANT BMP-HDR-SIZE       \ 14 (file hdr) + 40 (DIB hdr)
 4 CONSTANT BMP-BPP-BYTES     \ 32-bit = 4 bytes per pixel

\ =====================================================================
\  BMP-FILE-SIZE  ( w h -- bytes )
\ =====================================================================
\  Computes the total file size for a w×h 32-bit BMP.
\  Row stride is w*4 (already 4-byte aligned at 32bpp).

: BMP-FILE-SIZE  ( w h -- bytes )
    *                          \ total pixels
    BMP-BPP-BYTES *            \ pixel data bytes
    BMP-HDR-SIZE +             \ + header
;

\ =====================================================================
\  Internal variables
\ =====================================================================

VARIABLE _BMP-SURF
VARIABLE _BMP-BUF
VARIABLE _BMP-POS
VARIABLE _BMP-W
VARIABLE _BMP-H
VARIABLE _BMP-ROW-BYTES
VARIABLE _BMP-SRC
VARIABLE _BMP-DST
VARIABLE _BMP-X
VARIABLE _BMP-PIX

\ =====================================================================
\  Internal: byte/word/dword writers (little-endian)
\ =====================================================================

: _BMP-B!  ( byte -- )
    _BMP-BUF @ _BMP-POS @ + C!
    1 _BMP-POS +!
;

: _BMP-W!  ( u16 -- )
    DUP           255 AND _BMP-B!
    8 RSHIFT  255 AND _BMP-B!
;

: _BMP-D!  ( u32 -- )
    DUP              255 AND _BMP-B!
    DUP  8 RSHIFT    255 AND _BMP-B!
    DUP 16 RSHIFT    255 AND _BMP-B!
        24 RSHIFT    255 AND _BMP-B!
;

\ =====================================================================
\  Internal: write BMP headers
\ =====================================================================

: _BMP-WRITE-HDR  ( -- )
    \ ── File header (14 bytes) ──
    66 _BMP-B!  77 _BMP-B!              \ "BM" signature
    _BMP-W @ _BMP-H @ BMP-FILE-SIZE _BMP-D!   \ file size
    0 _BMP-W!                            \ reserved1
    0 _BMP-W!                            \ reserved2
    BMP-HDR-SIZE _BMP-D!                 \ pixel data offset

    \ ── DIB header (BITMAPINFOHEADER, 40 bytes) ──
    40 _BMP-D!                           \ header size
    _BMP-W @ _BMP-D!                     \ width
    _BMP-H @ _BMP-D!                     \ height (positive = bottom-to-top)
    1 _BMP-W!                            \ color planes
    32 _BMP-W!                           \ bits per pixel
    0 _BMP-D!                            \ compression (BI_RGB = 0)
    _BMP-W @ _BMP-H @ * BMP-BPP-BYTES * _BMP-D!   \ image size
    2835 _BMP-D!                         \ X pixels/meter (~72 DPI)
    2835 _BMP-D!                         \ Y pixels/meter
    0 _BMP-D!                            \ colors in palette
    0 _BMP-D!                            \ important colors
;

\ =====================================================================
\  Internal: write pixel data (bottom-to-top, RGBA→BGRA)
\ =====================================================================

: _BMP-SWAP-PIXEL  ( rgba -- )
    \ Cell value: R=bits31-24  G=bits23-16  B=bits15-8  A=bits7-0
    \ BMP byte order in memory: B G R A
    DUP 24 RSHIFT 255 AND >R          \ R → rstack
    DUP 16 RSHIFT 255 AND >R          \ G → rstack
    DUP  8 RSHIFT 255 AND             \ B on stack
    SWAP         255 AND              \ B A
    SWAP _BMP-B!                      \ write B           stack: A
    R> _BMP-B!                        \ write G
    R> _BMP-B!                        \ write R
    _BMP-B!                           \ write A
;

: _BMP-WRITE-ROW  ( row -- )
    \ Compute source pointer: buf + row * stride
    _BMP-SURF @ SURF-STRIDE *
    _BMP-SURF @ SURF-BUF +
    _BMP-SRC !
    _BMP-W @ 0 DO
        _BMP-SRC @ I 4 * + L@
        _BMP-SWAP-PIXEL
    LOOP
;

: _BMP-WRITE-PIXELS  ( -- )
    \ BMP stores rows bottom-to-top.
    \ Iterate y from (h-1) down to 0.
    _BMP-H @ 1 -
    BEGIN
        DUP 0 >= WHILE
        DUP _BMP-WRITE-ROW
        1 -
    REPEAT
    DROP
;

\ =====================================================================
\  BMP-ENCODE  ( surf buf max -- len | 0 )
\ =====================================================================
\  Encode a surface as a 32-bit BMP into buf.
\  Returns the number of bytes written, or 0 if max < needed.

: BMP-ENCODE  ( surf buf max -- len | 0 )
    >R >R                             \ R: max buf
    DUP SURF-W                        \ surf w
    OVER SURF-H                       \ surf w h
    _BMP-H !  _BMP-W !
    _BMP-SURF !
    \ Check buffer size
    _BMP-W @ _BMP-H @ BMP-FILE-SIZE   \ needed
    R> R>                              \ needed buf max
    ROT                                \ buf max needed
    2DUP < IF                          \ max < needed?
        DROP DROP DROP
        0 EXIT                         \ buffer too small
    THEN
    NIP                                \ buf needed  (drop max)
    >R                                 \ buf   R: needed
    _BMP-BUF !                         \ store buf
    0 _BMP-POS !                       \ reset write position
    _BMP-WRITE-HDR
    _BMP-WRITE-PIXELS
    R>                                 \ return byte count
;
