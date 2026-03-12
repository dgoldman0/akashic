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
\  <style> tag extraction
\ =====================================================================
\  After parsing, walk the DOM looking for <style> elements.
\  Concatenate text content of all <style> nodes into a CSS buffer
\  and call DOM-SET-STYLESHEET so the bridge picks them up.
\
\  Supports multiple <style> tags — their content is concatenated
\  with a newline separator.

CREATE _D2B-CSS-BUF 8192 ALLOT    \ collected stylesheet text
VARIABLE _D2B-CSS-LEN              \ current length in buffer
CREATE _D2B-STYLE-NODES 64 ALLOT  \ up to 8 style node pointers

VARIABLE _D2B-STN    \ style node count
VARIABLE _D2B-STI    \ iteration index
VARIABLE _D2B-STC    \ current style node

: _D2B-EXTRACT-STYLES  ( dom-root -- )
    0 _D2B-CSS-LEN !

    \ Find all <style> elements (up to 8)
    S" style" _D2B-STYLE-NODES 8 DOM-GET-BY-TAG _D2B-STN !

    _D2B-STN @ 0= IF EXIT THEN

    \ Collect text content from each <style> node
    0 _D2B-STI !
    BEGIN _D2B-STI @ _D2B-STN @ < WHILE
        _D2B-STYLE-NODES _D2B-STI @ 8 * + @ _D2B-STC !

        \ Get first child (should be a text node with the CSS)
        _D2B-STC @ DOM-FIRST-CHILD DUP 0<> IF
            DOM-TEXT                     ( css-a css-u )
            DUP 0> IF
                \ Check buffer space
                DUP _D2B-CSS-LEN @ + 8192 <= IF
                    \ Copy CSS text into buffer
                    _D2B-CSS-BUF _D2B-CSS-LEN @ +
                    SWAP CMOVE
                    _D2B-CSS-LEN +!
                    \ Add newline separator
                    _D2B-CSS-LEN @ 8192 < IF
                        10 _D2B-CSS-BUF _D2B-CSS-LEN @ + C!
                        1 _D2B-CSS-LEN +!
                    THEN
                ELSE
                    2DROP   \ buffer full — skip
                THEN
            ELSE
                2DROP
            THEN
        ELSE
            DROP
        THEN

        _D2B-STI @ 1+ _D2B-STI !
    REPEAT

    \ Set the collected stylesheet
    _D2B-CSS-LEN @ 0> IF
        _D2B-CSS-BUF _D2B-CSS-LEN @ DOM-SET-STYLESHEET
    THEN ;

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

    \ 1b. Extract <style> tags → DOM-SET-STYLESHEET
    _D2B-DOM @ _D2B-EXTRACT-STYLES

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

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _d2b-guard

' DOM2BMP-SIZE    CONSTANT _dom2bmp-size-xt
' DOM2BMP-RENDER  CONSTANT _dom2bmp-render-xt

: DOM2BMP-SIZE    _dom2bmp-size-xt _d2b-guard WITH-GUARD ;
: DOM2BMP-RENDER  _dom2bmp-render-xt _d2b-guard WITH-GUARD ;
[THEN] [THEN]
