\ dom2bmp.f — End-to-end HTML → BMP renderer
\
\ Glues the full Akashic render pipeline:
\   HTML string → DOM tree → box tree → layout → paint → BMP bytes
\
\ Load with:   REQUIRE render/dom2bmp.f
\ Depends on:  paint.f, bmp.f  (and transitively the full pipeline)
\
\ Public API:
\   DOM2BMP-RENDER  ( html-a html-u vp-w vp-h buf max -- len | 0 )
\   DOM2BMP-SIZE    ( vp-w vp-h -- bytes )
\
\ The caller must provide:
\   - A DOM arena set up via ARENA-NEW + DOM-DOC-NEW / DOM-USE
\   - A BMP output buffer of at least DOM2BMP-SIZE bytes
\   - A loaded TTF font (for text rendering)
\
\ Returns the BMP byte count, or 0 if the buffer was too small.
\ =====================================================================

REQUIRE paint.f
REQUIRE bmp.f

PROVIDED akashic-dom2bmp

\ =====================================================================
\  Variables
\ =====================================================================

VARIABLE _D2B-VPW       \ viewport width
VARIABLE _D2B-VPH       \ viewport height
VARIABLE _D2B-BUF       \ output buffer address
VARIABLE _D2B-MAX       \ output buffer max size
VARIABLE _D2B-DOM       \ DOM root
VARIABLE _D2B-BOX       \ box tree root
VARIABLE _D2B-SURF      \ surface

\ =====================================================================
\  DOM2BMP-SIZE  ( vp-w vp-h -- bytes )
\ =====================================================================
\  Compute the BMP output size for a given viewport.

: DOM2BMP-SIZE  ( vp-w vp-h -- bytes )
    BMP-FILE-SIZE ;

\ =====================================================================
\  DOM2BMP-RENDER  ( html-a html-u vp-w vp-h buf max -- len | 0 )
\ =====================================================================
\  Full pipeline: parse HTML, build boxes, lay out, paint, encode BMP.
\
\  Assumes the current DOM document (set via DOM-USE) is available and
\  has enough arena space.  The surface is created in XMEM and destroyed
\  before returning.

: DOM2BMP-RENDER  ( html-a html-u vp-w vp-h buf max -- len | 0 )
    _D2B-MAX !
    _D2B-BUF !
    _D2B-VPH !
    _D2B-VPW !

    \ 1. Parse HTML → DOM tree
    DOM-PARSE-HTML  _D2B-DOM !
    _D2B-DOM @ 0= IF 0 EXIT THEN

    \ 2. Build box tree from DOM
    _D2B-DOM @ BOX-BUILD-TREE  _D2B-BOX !
    _D2B-BOX @ 0= IF 0 EXIT THEN

    \ 3. Layout
    _D2B-BOX @  _D2B-VPW @  _D2B-VPH @  LAYO-LAYOUT

    \ 4. Create surface + paint
    _D2B-VPW @  _D2B-VPH @  SURF-CREATE  _D2B-SURF !
    _D2B-SURF @  0xFFFFFFFF  SURF-CLEAR   \ white background

    _D2B-BOX @  _D2B-SURF @  PAINT-RENDER

    \ 5. Encode to BMP
    _D2B-SURF @  _D2B-BUF @  _D2B-MAX @  BMP-ENCODE

    \ 6. Clean up surface
    _D2B-SURF @ SURF-DESTROY
;
