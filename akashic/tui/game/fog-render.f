\ =====================================================================
\  akashic/tui/game/fog-render.f — Fog of War TUI rendering
\ =====================================================================
\
\  Post-process the visible portion of the screen, applying fog
\  effects based on tile visibility:
\    UNSEEN     → replace cell with dark block
\    REMEMBERED → dim: darken fg, set bg=0
\    VISIBLE    → no change
\
\  Reads camera position to map screen coords → world coords.
\
\  Public API:
\    FOG-RENDER    ( fog cam rgn -- )
\
\  Prefix: FOG- (public), _FOG- (internal)
\  Provider: akashic-tui-game-fog-render
\  Dependencies: game/2d/fog.f, game/2d/camera.f, cell.f, screen.f, region.f

PROVIDED akashic-tui-game-fog-render

REQUIRE ../../game/2d/fog.f
REQUIRE ../../game/2d/camera.f
REQUIRE ../cell.f
REQUIRE ../screen.f
REQUIRE ../region.f

\ Dimmed colour used for remembered tiles
8 CONSTANT _FOG-DIM-FG

\ Unseen cell: solid dark block
\ Unicode '░' (0x2591) with dark grey fg, black bg
HEX 2591 DECIMAL CONSTANT _FOG-UNSEEN-CP
8 CONSTANT _FOG-UNSEEN-FG

VARIABLE _FOG-RN-FOG
VARIABLE _FOG-RN-CAM
VARIABLE _FOG-RN-RGN
VARIABLE _FOG-RN-VW
VARIABLE _FOG-RN-VH
VARIABLE _FOG-RN-CX
VARIABLE _FOG-RN-CY
VARIABLE _FOG-RN-WX
VARIABLE _FOG-RN-WY
VARIABLE _FOG-RN-ST
VARIABLE _FOG-RN-CELL

: FOG-RENDER  ( fog cam rgn -- )
    _FOG-RN-RGN ! _FOG-RN-CAM ! _FOG-RN-FOG !
    _FOG-RN-RGN @ RGN-W _FOG-RN-VW !
    _FOG-RN-RGN @ RGN-H _FOG-RN-VH !
    _FOG-RN-CAM @ CAM-X _FOG-RN-CX !
    _FOG-RN-CAM @ CAM-Y _FOG-RN-CY !
    _FOG-RN-RGN @ RGN-USE
    _FOG-RN-VH @ 0 ?DO                \ screen row
        _FOG-RN-VW @ 0 ?DO            \ screen col
            I _FOG-RN-CX @ + _FOG-RN-WX !
            J _FOG-RN-CY @ + _FOG-RN-WY !
            _FOG-RN-FOG @ _FOG-RN-WX @ _FOG-RN-WY @ FOG-STATE
            _FOG-RN-ST !
            _FOG-RN-ST @ FOG-VISIBLE = IF
                \ No modification needed
            ELSE
                _FOG-RN-ST @ FOG-UNSEEN = IF
                    \ Replace with dark block
                    _FOG-UNSEEN-CP _FOG-UNSEEN-FG 0 0 CELL-MAKE
                    J I SCR-SET
                ELSE
                    \ REMEMBERED: dim existing cell
                    J I SCR-GET _FOG-RN-CELL !
                    _FOG-DIM-FG _FOG-RN-CELL @ CELL-FG!
                    0 SWAP CELL-BG!
                    J I SCR-SET
                THEN
            THEN
        LOOP
    LOOP ;

\ =====================================================================
\  Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _fog-render-guard

' FOG-RENDER   CONSTANT _fog-render-xt
: FOG-RENDER   _fog-render-xt _fog-render-guard WITH-GUARD ;
[THEN] [THEN]
