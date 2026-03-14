\ dom-tui.f — DOM-to-TUI Node Mapping
\
\ Maps DOM element nodes to TUI sidecar descriptors.  Walks the DOM
\ tree, allocates a sidecar for each visible element, and resolves
\ CSS properties into character-cell attributes (fg/bg color, border
\ style, text-align, display mode, visibility, dimensions).
\
\ The sidecar is stored in the DOM node's N.AUX field.  DTUI-DETACH
\ must be called before destroying the DOM to avoid stale pointers.
\
\ Prefix: DTUI-  (public)
\         _DTUI- (internal)
\
\ Load with:   REQUIRE dom-tui.f

PROVIDED akashic-tui-dom-tui

REQUIRE ../dom/dom.f
REQUIRE ../dom/html5.f
REQUIRE ../css/css.f
REQUIRE ../css/bridge.f
REQUIRE ../utils/string.f
REQUIRE cell.f
REQUIRE region.f
REQUIRE color.f

\ =====================================================================
\  §1 — Constants
\ =====================================================================

\ Sidecar descriptor size (9 cells = 72 bytes)
72 CONSTANT DTUI-SC-SIZE

\ --- Sidecar field offsets ---
\  +0   node           back-pointer to DOM node
\  +8   flags          see DTUI-F-* below
\ +16   row            computed row in screen coordinates
\ +24   col            computed column in screen coordinates
\ +32   width          computed width (character cells)
\ +40   height         computed height (character cells)
\ +48   style          packed: fg(8) bg(8) attrs(16) border-idx(8)
\ +56   draw-xt        custom draw hook ( node sc rgn -- ), 0 = default
\ +64   userdata       app-defined payload (widget ptr, etc.)

 0 CONSTANT _SC-NODE
 8 CONSTANT _SC-FLAGS
16 CONSTANT _SC-ROW
24 CONSTANT _SC-COL
32 CONSTANT _SC-W
40 CONSTANT _SC-H
48 CONSTANT _SC-STYLE
56 CONSTANT _SC-DRAW
64 CONSTANT _SC-UDATA

\ --- Sidecar flag bits ---
1  CONSTANT DTUI-F-DIRTY       \ needs repaint
2  CONSTANT DTUI-F-VISIBLE     \ visible (not display:none)
4  CONSTANT DTUI-F-BLOCK       \ display: block (else inline)
8  CONSTANT DTUI-F-HIDDEN      \ visibility: hidden (space reserved, no paint)
16 CONSTANT DTUI-F-FOCUSABLE   \ can receive focus
32 CONSTANT DTUI-F-GEOM-DIRTY  \ layout geometry changed, needs relayout

\ --- Style packing ---
\ bits  0-7:  fg color index  (0-255)
\ bits  8-15: bg color index  (0-255)
\ bits 16-31: CELL-A-* attribute flags
\ bits 32-39: border style index (0=none,1=single,2=double,3=rounded,4=heavy)

0 CONSTANT DTUI-BORDER-NONE
1 CONSTANT DTUI-BORDER-SINGLE
2 CONSTANT DTUI-BORDER-DOUBLE
3 CONSTANT DTUI-BORDER-ROUNDED
4 CONSTANT DTUI-BORDER-HEAVY

\ Default colors (256-palette)
7  CONSTANT _DTUI-DEFAULT-FG    \ white
0  CONSTANT _DTUI-DEFAULT-BG    \ black

\ =====================================================================
\  §2 — Sidecar Field Accessors
\ =====================================================================

: DTUI-SC-NODE   ( sc -- node )    _SC-NODE  + @ ;
: DTUI-SC-FLAGS  ( sc -- flags )   _SC-FLAGS + @ ;
: DTUI-SC-ROW    ( sc -- row )     _SC-ROW   + @ ;
: DTUI-SC-COL    ( sc -- col )     _SC-COL   + @ ;
: DTUI-SC-W      ( sc -- w )       _SC-W     + @ ;
: DTUI-SC-H      ( sc -- h )       _SC-H     + @ ;
: DTUI-SC-STYLE  ( sc -- packed )  _SC-STYLE + @ ;
: DTUI-SC-DRAW   ( sc -- xt|0 )   _SC-DRAW  + @ ;
: DTUI-SC-UDATA  ( sc -- udata )   _SC-UDATA + @ ;

: DTUI-SC-FLAGS! ( fl sc -- )      _SC-FLAGS + ! ;
: DTUI-SC-ROW!   ( r sc -- )       _SC-ROW   + ! ;
: DTUI-SC-COL!   ( c sc -- )       _SC-COL   + ! ;
: DTUI-SC-W!     ( w sc -- )       _SC-W     + ! ;
: DTUI-SC-H!     ( h sc -- )       _SC-H     + ! ;
: DTUI-SC-STYLE! ( s sc -- )       _SC-STYLE + ! ;
: DTUI-SC-DRAW!  ( xt sc -- )      _SC-DRAW  + ! ;
: DTUI-SC-UDATA! ( u sc -- )       _SC-UDATA + ! ;

\ =====================================================================
\  §3 — Style Pack / Unpack
\ =====================================================================

\ DTUI-PACK-STYLE ( fg bg attrs border -- packed )
: DTUI-PACK-STYLE  ( fg bg attrs border -- packed )
    32 LSHIFT >R
    16 LSHIFT >R
     8 LSHIFT >R
    R> OR R> OR R> OR ;

\ DTUI-UNPACK-FG ( packed -- fg )
: DTUI-UNPACK-FG  ( packed -- fg )
    255 AND ;

\ DTUI-UNPACK-BG ( packed -- bg )
: DTUI-UNPACK-BG  ( packed -- bg )
    8 RSHIFT 255 AND ;

\ DTUI-UNPACK-ATTRS ( packed -- attrs )
: DTUI-UNPACK-ATTRS  ( packed -- attrs )
    16 RSHIFT 65535 AND ;

\ DTUI-UNPACK-BORDER ( packed -- border-idx )
: DTUI-UNPACK-BORDER  ( packed -- border-idx )
    32 RSHIFT 255 AND ;

\ =====================================================================
\  §4 — Color Resolution (delegated to color.f)
\ =====================================================================
\
\ RGB→256 palette mapping and CSS color parsing now live in color.f
\ (shared by dom-tui.f and uidl-tui.f).  color.f provides:
\   TUI-RESOLVE-COLOR   ( r g b -- index )
\   TUI-PARSE-COLOR     ( val-a val-u -- index found? )
\   DTUI-RESOLVE-COLOR   ( r g b -- index )   backward-compat alias

\ Internal alias for backward compatibility within this file.
: _DTUI-PARSE-COLOR  ( val-a val-u -- index found? )  TUI-PARSE-COLOR ;

\ =====================================================================
\  §6 — Sidecar Pool (carved from DOM string pool)
\ =====================================================================
\
\ Sidecars are allocated in a contiguous block carved from the
\ string pool's top end (same technique as _DOME-CARVE in event.f).
\ Max sidecars = DOM node max.

VARIABLE _DTUI-BASE     \ sidecar block base address
VARIABLE _DTUI-MAX      \ max sidecars
VARIABLE _DTUI-COUNT    \ allocated count

\ _DTUI-CARVE ( -- )
\   Carve sidecar pool from DOM string pool.
: _DTUI-CARVE  ( -- )
    DOM-DOC D.NODE-MAX @  _DTUI-MAX !
    _DTUI-MAX @ DTUI-SC-SIZE *   \ total bytes needed
    DOM-DOC D.STR-END @  SWAP -
    DUP DOM-DOC D.STR-PTR @ < ABORT" DTUI: string pool full"
    DUP DOM-DOC D.STR-END !
    _DTUI-BASE !
    0 _DTUI-COUNT ! ;

\ _DTUI-SC-ALLOC ( -- sidecar )
: _DTUI-SC-ALLOC  ( -- sidecar )
    _DTUI-COUNT @ _DTUI-MAX @ >= ABORT" DTUI: sidecar pool full"
    _DTUI-BASE @  _DTUI-COUNT @ DTUI-SC-SIZE * +
    DUP DTUI-SC-SIZE 0 FILL
    _DTUI-COUNT @ 1+  _DTUI-COUNT ! ;

\ =====================================================================
\  §7 — CSS Property Resolution → Sidecar Fields
\ =====================================================================

VARIABLE _DRN-SC    \ current sidecar being resolved
VARIABLE _DRN-ND    \ current node
VARIABLE _DRN-FG    VARIABLE _DRN-BG
VARIABLE _DRN-AT    VARIABLE _DRN-BD
VARIABLE _DRN-FL    \ flags accumulator

\ _DTUI-RESOLVE-DISPLAY ( node -- flags skip? )
\   Read 'display' property. Returns flags with DTUI-F-BLOCK set
\   appropriately, and skip?=-1 if display:none.
: _DTUI-RESOLVE-DISPLAY  ( node -- flags skip? )
    S" display" DOM-STYLE@  IF
        2DUP S" none" STR-STR= IF
            2DROP 0  -1 EXIT    \ display:none → skip
        THEN
        2DUP S" block" STR-STR= IF
            2DROP DTUI-F-BLOCK  0 EXIT
        THEN
        \ inline or anything else → inline
        2DROP 0  0
    ELSE
        2DROP DTUI-F-BLOCK  0    \ default = block
    THEN ;

\ _DTUI-RESOLVE-VISIBILITY ( node flags -- flags )
\   Set DTUI-F-HIDDEN if visibility:hidden.
: _DTUI-RESOLVE-VISIBILITY  ( node flags -- flags )
    SWAP S" visibility" DOM-STYLE@  IF
        S" hidden" STR-STR= IF
            DTUI-F-HIDDEN OR EXIT
        THEN
        2DROP
    ELSE 2DROP THEN ;

\ _DTUI-RESOLVE-FG ( node -- fg-index )
: _DTUI-RESOLVE-FG  ( node -- fg-index )
    S" color" DOM-STYLE@  IF
        _DTUI-PARSE-COLOR IF EXIT THEN
        2DROP
    ELSE 2DROP THEN
    _DTUI-DEFAULT-FG ;

\ _DTUI-RESOLVE-BG ( node -- bg-index )
: _DTUI-RESOLVE-BG  ( node -- bg-index )
    S" background-color" DOM-STYLE@  IF
        _DTUI-PARSE-COLOR IF EXIT THEN
        2DROP
    ELSE 2DROP THEN
    _DTUI-DEFAULT-BG ;

\ _DTUI-RESOLVE-ATTRS ( node -- cell-attrs )
\   Map CSS font/text properties to CELL-A-* flags.
: _DTUI-RESOLVE-ATTRS  ( node -- cell-attrs )
    >R 0
    R@ S" font-weight" DOM-STYLE@  IF
        S" bold" STR-STR= IF CELL-A-BOLD OR THEN
    ELSE 2DROP THEN
    R@ S" font-style" DOM-STYLE@  IF
        S" italic" STR-STR= IF CELL-A-ITALIC OR THEN
    ELSE 2DROP THEN
    R@ S" text-decoration" DOM-STYLE@  IF
        2DUP S" underline" STR-STR= IF
            2DROP CELL-A-UNDERLINE OR
        ELSE
            S" line-through" STR-STR= IF
                CELL-A-STRIKE OR
            ELSE 2DROP THEN
        THEN
    ELSE 2DROP THEN
    R> DROP ;

\ _DTUI-RESOLVE-BORDER ( node -- border-idx )
\   Map border-style CSS property to DTUI-BORDER-* index.
: _DTUI-RESOLVE-BORDER  ( node -- border-idx )
    S" border-style" DOM-STYLE@  IF
        2DUP S" solid"   STR-STR= IF 2DROP DTUI-BORDER-SINGLE  EXIT THEN
        2DUP S" double"  STR-STR= IF 2DROP DTUI-BORDER-DOUBLE  EXIT THEN
        2DUP S" rounded" STR-STR= IF 2DROP DTUI-BORDER-ROUNDED EXIT THEN
        2DUP S" ridge"   STR-STR= IF 2DROP DTUI-BORDER-HEAVY   EXIT THEN
        2DUP S" none"    STR-STR= IF 2DROP DTUI-BORDER-NONE    EXIT THEN
        2DROP DTUI-BORDER-NONE
    ELSE 2DROP DTUI-BORDER-NONE THEN ;

\ _DTUI-PARSE-DIM ( val-a val-u -- n )
\   Parse a CSS dimension value like "80" or "10px" to integer.
\   Strips trailing "px"/"ch"/"em" and converts.
VARIABLE _DPD-V

\ Helper: trim trailing non-digit chars.  EXIT cleanly returns
\ from this helper when a digit is found (LEAVE is illegal
\ inside BEGIN…WHILE…REPEAT).
: _DPD-TRIM  ( addr u -- addr u' )
    BEGIN
        DUP 0> WHILE
        2DUP + 1- C@
        DUP [CHAR] 0 < SWAP [CHAR] 9 > OR IF
            1-    \ drop last char
        ELSE
            EXIT  \ digit found — done trimming
        THEN
    REPEAT ;

: _DTUI-PARSE-DIM  ( val-a val-u -- n )
    DUP 0= IF 2DROP 0 EXIT THEN
    _DPD-TRIM
    DUP 0= IF 2DROP 0 EXIT THEN
    0 _DPD-V !
    OVER + SWAP DO
        I C@  DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF
            [CHAR] 0 -
            _DPD-V @ 10 * +  _DPD-V !
        ELSE DROP THEN
    LOOP
    _DPD-V @ ;

\ _DTUI-RESOLVE-DIM ( node prop-a prop-u -- n|0 )
\   Read a CSS dimension property, return integer or 0.
: _DTUI-RESOLVE-DIM  ( node prop-a prop-u -- n|0 )
    DOM-STYLE@  IF
        _DTUI-PARSE-DIM
    ELSE 2DROP 0 THEN ;

\ _DTUI-RESOLVE-NODE ( node sidecar -- )
\   Resolve all CSS properties into sidecar fields.
: _DTUI-RESOLVE-NODE  ( node sidecar -- )
    _DRN-SC !  _DRN-ND !
    _DRN-ND @  _DRN-SC @ _SC-NODE + !   \ back-pointer
    \ Display + visibility
    _DRN-ND @  _DTUI-RESOLVE-DISPLAY  IF
        \ display:none — mark invisible, done
        _DRN-SC @ _SC-FLAGS + !  EXIT
    THEN
    DTUI-F-VISIBLE OR  _DRN-FL !
    \ Visibility:hidden?
    _DRN-ND @ _DRN-FL @  _DTUI-RESOLVE-VISIBILITY  _DRN-FL !
    \ Focusable?
    _DRN-ND @ S" tabindex" DOM-ATTR-HAS? IF
        _DRN-FL @ DTUI-F-FOCUSABLE OR  _DRN-FL !
    ELSE
        _DRN-ND @ DOM-TAG-NAME
        2DUP S" input"    STR-STR= IF 2DROP _DRN-FL @ DTUI-F-FOCUSABLE OR _DRN-FL ! ELSE
        2DUP S" button"   STR-STR= IF 2DROP _DRN-FL @ DTUI-F-FOCUSABLE OR _DRN-FL ! ELSE
        2DUP S" select"   STR-STR= IF 2DROP _DRN-FL @ DTUI-F-FOCUSABLE OR _DRN-FL ! ELSE
        2DUP S" textarea" STR-STR= IF 2DROP _DRN-FL @ DTUI-F-FOCUSABLE OR _DRN-FL ! ELSE
        2DROP
        THEN THEN THEN THEN
    THEN
    _DRN-FL @ DTUI-F-DIRTY OR  _DRN-SC @ _SC-FLAGS + !
    \ Colors + attrs + border
    _DRN-ND @ _DTUI-RESOLVE-FG   _DRN-FG !
    _DRN-ND @ _DTUI-RESOLVE-BG   _DRN-BG !
    _DRN-ND @ _DTUI-RESOLVE-ATTRS _DRN-AT !
    _DRN-ND @ _DTUI-RESOLVE-BORDER _DRN-BD !
    _DRN-FG @ _DRN-BG @ _DRN-AT @ _DRN-BD @  DTUI-PACK-STYLE
    _DRN-SC @ _SC-STYLE + !
    \ Explicit dimensions
    _DRN-ND @ S" width"  _DTUI-RESOLVE-DIM   _DRN-SC @ _SC-W + !
    _DRN-ND @ S" height" _DTUI-RESOLVE-DIM   _DRN-SC @ _SC-H + ! ;

\ =====================================================================
\  §8 — Attach / Detach / Refresh
\ =====================================================================

VARIABLE _DAT-DOC

\ _DTUI-ATTACH-NODE ( node -- )
\   Callback for DOM-WALK-DEPTH.  Allocates & resolves sidecar.
: _DTUI-ATTACH-NODE  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    \ Check display:none early — skip subtree?  No, still allocate
    \ so detach is uniform.  Just mark invisible.
    _DTUI-SC-ALLOC
    2DUP  _DTUI-RESOLVE-NODE
    SWAP N.AUX ! ;

\ DTUI-ATTACH ( doc -- )
\   Walk DOM tree depth-first.  Allocate sidecars for all element
\   nodes and store in N.AUX.  Carves sidecar pool from string pool.
: DTUI-ATTACH  ( doc -- )
    _DAT-DOC !
    _DAT-DOC @ DOM-USE
    _DTUI-CARVE
    \ Walk from doc root (first child of doc, typically <html>)
    _DAT-DOC @ D.HTML @  DUP 0= IF
        DROP  _DAT-DOC @ DOM-USE
        DOM-DOC DOM-FIRST-CHILD
    THEN
    DUP 0= ABORT" DTUI-ATTACH: no root element"
    ['] _DTUI-ATTACH-NODE DOM-WALK-DEPTH ;

\ _DTUI-DETACH-NODE ( node -- )
\   Clear N.AUX for one node.
: _DTUI-DETACH-NODE  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    0 SWAP N.AUX ! ;

\ DTUI-DETACH ( doc -- )
\   Clear all N.AUX fields.  Sidecar memory remains in pool
\   until arena is destroyed.
: DTUI-DETACH  ( doc -- )
    DUP DOM-USE
    DUP D.HTML @  DUP 0= IF
        DROP DUP DOM-USE DOM-DOC DOM-FIRST-CHILD
    THEN
    DUP 0= IF 2DROP EXIT THEN
    ['] _DTUI-DETACH-NODE DOM-WALK-DEPTH
    DROP   \ drop doc
    0 _DTUI-COUNT ! ;

\ DTUI-SIDECAR ( node -- sidecar | 0 )
\   Get the TUI sidecar for a DOM node.
: DTUI-SIDECAR  ( node -- sidecar|0 )
    N.AUX @ ;

\ DTUI-VISIBLE? ( node -- flag )
\   True if node has a sidecar with VISIBLE flag set.
: DTUI-VISIBLE?  ( node -- flag )
    DTUI-SIDECAR DUP 0= IF EXIT THEN
    DTUI-SC-FLAGS  DTUI-F-VISIBLE AND  0<> ;

\ DTUI-STYLE! ( node fg bg attrs -- )
\   Override the resolved style for one node's sidecar.
VARIABLE _DST-FG  VARIABLE _DST-BG  VARIABLE _DST-AT

: DTUI-STYLE!  ( node fg bg attrs -- )
    _DST-AT !  _DST-BG !  _DST-FG !
    DTUI-SIDECAR DUP 0= IF DROP EXIT THEN
    DUP DTUI-SC-STYLE DTUI-UNPACK-BORDER  \ keep existing border
    >R   _DST-FG @ _DST-BG @ _DST-AT @ R>
    DTUI-PACK-STYLE
    SWAP DTUI-SC-STYLE! ;

\ =====================================================================
\  §8a — Dirty Marking (explicit primitives + convenience wrappers)
\ =====================================================================

\ DTUI-MARK-DIRTY ( node -- )
\   Set DTUI-F-DIRTY on the node's sidecar for repaint.
: DTUI-MARK-DIRTY  ( node -- )
    DTUI-SIDECAR DUP 0= IF DROP EXIT THEN
    DUP DTUI-SC-FLAGS DTUI-F-DIRTY OR  SWAP DTUI-SC-FLAGS! ;

\ DTUI-MARK-GEOM-DIRTY ( node -- )
\   Set both DTUI-F-GEOM-DIRTY and DTUI-F-DIRTY.
: DTUI-MARK-GEOM-DIRTY  ( node -- )
    DTUI-SIDECAR DUP 0= IF DROP EXIT THEN
    DUP DTUI-SC-FLAGS
    DTUI-F-DIRTY OR DTUI-F-GEOM-DIRTY OR
    SWAP DTUI-SC-FLAGS! ;

\ DTUI-CLEAR-DIRTY ( sc -- )
\   Clear the DTUI-F-DIRTY flag on a sidecar.
: DTUI-CLEAR-DIRTY  ( sc -- )
    DUP DTUI-SC-FLAGS DTUI-F-DIRTY INVERT AND
    SWAP DTUI-SC-FLAGS! ;

\ DTUI-CLEAR-GEOM-DIRTY ( sc -- )
\   Clear the DTUI-F-GEOM-DIRTY flag on a sidecar.
: DTUI-CLEAR-GEOM-DIRTY  ( sc -- )
    DUP DTUI-SC-FLAGS DTUI-F-GEOM-DIRTY INVERT AND
    SWAP DTUI-SC-FLAGS! ;

\ --- Convenience wrappers: DOM mutation + auto-dirty ---

\ DTUI-SET-TEXT! ( node txt-a txt-u -- )
\   DOM-SET-TEXT then mark dirty.
: DTUI-SET-TEXT!  ( node txt-a txt-u -- )
    ROT DUP >R -ROT  DOM-SET-TEXT
    R> DTUI-MARK-DIRTY ;

\ DTUI-ATTR! ( node name-a name-u val-a val-u -- )
\   DOM-ATTR! then mark dirty.
: DTUI-ATTR!  ( node name-a name-u val-a val-u -- )
    4 PICK >R           \ save node for later
    DOM-ATTR!            \ consumes all 5 args
    R> DTUI-MARK-DIRTY ;

\ DTUI-ATTR-DEL! ( node name-a name-u -- )
\   DOM-ATTR-DEL then mark dirty.
: DTUI-ATTR-DEL!  ( node name-a name-u -- )
    ROT DUP >R -ROT  DOM-ATTR-DEL
    R> DTUI-MARK-DIRTY ;

\ DTUI-REFRESH ( doc -- )
\   Re-resolve CSS into existing sidecars (after style/class change).

VARIABLE _DRF-SC

: _DTUI-REFRESH-NODE  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    DUP N.AUX @  DUP 0= IF 2DROP EXIT THEN
    _DRF-SC !
    _DRF-SC @  _DTUI-RESOLVE-NODE ;

: DTUI-REFRESH  ( doc -- )
    DUP DOM-USE
    DUP D.HTML @  DUP 0= IF
        DROP DUP DOM-USE DOM-DOC DOM-FIRST-CHILD
    THEN
    DUP 0= IF 2DROP EXIT THEN
    SWAP DROP    \ drop doc, keep root
    ['] _DTUI-REFRESH-NODE DOM-WALK-DEPTH ;

\ =====================================================================
\  §9 — Class Helpers
\ =====================================================================

\ DTUI-CLASS-ADD ( node addr len -- )
\   Add a CSS class to the node's class attribute and refresh its
\   sidecar.  Does not check for duplicates.
CREATE _DCA-BUF 256 ALLOT
VARIABLE _DCA-LEN
VARIABLE _DCA-NA   VARIABLE _DCA-NL

: DTUI-CLASS-ADD  ( node addr len -- )
    ROT >R
    _DCA-NL ! _DCA-NA !            \ save new class
    R@ DOM-CLASS                    \ ( old-a old-u )
    DUP 0= IF
        \ No existing class — just set it
        2DROP
        R@ S" class" _DCA-NA @ _DCA-NL @ DOM-ATTR!
    ELSE
        \ Overflow check: old-u + 1 + new-u must fit in 256
        DUP 1+ _DCA-NL @ + 256 > IF
            2DROP                   \ silently skip on overflow
        ELSE
            \ Copy old class to buffer
            DUP _DCA-LEN !
            _DCA-BUF SWAP MOVE
            \ Append space
            BL _DCA-BUF _DCA-LEN @ + C!
            1 _DCA-LEN +!
            \ Append new class
            _DCA-NA @ _DCA-BUF _DCA-LEN @ + _DCA-NL @ MOVE
            _DCA-NL @ _DCA-LEN +!
            \ Set combined attribute
            R@ S" class" _DCA-BUF _DCA-LEN @ DOM-ATTR!
        THEN
    THEN
    R> DUP N.AUX @  DUP 0= IF 2DROP EXIT THEN
    _DTUI-RESOLVE-NODE ;

\ DTUI-CLASS-REMOVE ( node addr len -- )
\   Remove a single class from the node's space-separated class
\   attribute.  Rebuilds the class string without the target token.
\   Deletes the class attribute entirely if the result is empty.
CREATE _DCR-BUF 256 ALLOT
VARIABLE _DCR-LEN
VARIABLE _DCR-TA   VARIABLE _DCR-TL

: DTUI-CLASS-REMOVE  ( node addr len -- )
    ROT >R
    _DCR-TL ! _DCR-TA !
    0 _DCR-LEN !
    R@ DOM-CLASS                    \ ( cls-a cls-u )
    DUP 0= IF 2DROP R> DROP EXIT THEN
    \ Walk tokens, skip matching, rebuild in _DCR-BUF
    BEGIN
        STR-SKIP-BL                 \ skip leading whitespace
        DUP 0> WHILE                \ while input remains
        STR-PARSE-TOKEN             \ ( tok tlen rest rlen )
        2SWAP                       \ ( rest rlen tok tlen )
        2DUP _DCR-TA @ _DCR-TL @ STR-STR= IF
            2DROP                   \ skip matching token
        ELSE
            \ Add space separator if buffer non-empty
            _DCR-LEN @ IF
                BL _DCR-BUF _DCR-LEN @ + C!
                1 _DCR-LEN +!
            THEN
            \ Append token to buffer
            DUP >R
            _DCR-BUF _DCR-LEN @ + SWAP MOVE
            R> _DCR-LEN +!
        THEN
    REPEAT
    2DROP                           \ drop leftover ( addr 0 )
    \ Update the attribute
    _DCR-LEN @ 0= IF
        R@ S" class" DOM-ATTR-DEL
    ELSE
        R@ S" class" _DCR-BUF _DCR-LEN @ DOM-ATTR!
    THEN
    R> DUP N.AUX @  DUP 0= IF 2DROP EXIT THEN
    _DTUI-RESOLVE-NODE ;

\ =====================================================================
\  §10 — Guard Wrappers
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _dtui-guard

' DTUI-ATTACH         CONSTANT _dtui-attach-xt
' DTUI-DETACH         CONSTANT _dtui-detach-xt
' DTUI-REFRESH        CONSTANT _dtui-refresh-xt
' DTUI-SIDECAR        CONSTANT _dtui-sidecar-xt
' DTUI-VISIBLE?       CONSTANT _dtui-visible-xt
' DTUI-STYLE!         CONSTANT _dtui-style-xt
' DTUI-RESOLVE-COLOR  CONSTANT _dtui-resolve-color-xt
' DTUI-CLASS-ADD      CONSTANT _dtui-class-add-xt
' DTUI-CLASS-REMOVE   CONSTANT _dtui-class-remove-xt
' DTUI-PACK-STYLE     CONSTANT _dtui-pack-style-xt
' DTUI-UNPACK-FG      CONSTANT _dtui-unpack-fg-xt
' DTUI-UNPACK-BG      CONSTANT _dtui-unpack-bg-xt
' DTUI-UNPACK-ATTRS   CONSTANT _dtui-unpack-attrs-xt
' DTUI-UNPACK-BORDER  CONSTANT _dtui-unpack-border-xt
' DTUI-MARK-DIRTY     CONSTANT _dtui-mark-dirty-xt
' DTUI-MARK-GEOM-DIRTY CONSTANT _dtui-mark-gdirty-xt
' DTUI-SET-TEXT!      CONSTANT _dtui-set-text-xt
' DTUI-ATTR!          CONSTANT _dtui-attr-bang-xt
' DTUI-ATTR-DEL!      CONSTANT _dtui-attr-del-xt
' DTUI-SC-UDATA       CONSTANT _dtui-sc-udata-xt
' DTUI-SC-UDATA!      CONSTANT _dtui-sc-udata-bang-xt

: DTUI-ATTACH          _dtui-attach-xt        _dtui-guard WITH-GUARD ;
: DTUI-DETACH          _dtui-detach-xt        _dtui-guard WITH-GUARD ;
: DTUI-REFRESH         _dtui-refresh-xt       _dtui-guard WITH-GUARD ;
: DTUI-SIDECAR         _dtui-sidecar-xt       _dtui-guard WITH-GUARD ;
: DTUI-VISIBLE?        _dtui-visible-xt       _dtui-guard WITH-GUARD ;
: DTUI-STYLE!          _dtui-style-xt         _dtui-guard WITH-GUARD ;
: DTUI-RESOLVE-COLOR   _dtui-resolve-color-xt _dtui-guard WITH-GUARD ;
: DTUI-CLASS-ADD       _dtui-class-add-xt     _dtui-guard WITH-GUARD ;
: DTUI-CLASS-REMOVE    _dtui-class-remove-xt  _dtui-guard WITH-GUARD ;
: DTUI-PACK-STYLE      _dtui-pack-style-xt    _dtui-guard WITH-GUARD ;
: DTUI-UNPACK-FG       _dtui-unpack-fg-xt     _dtui-guard WITH-GUARD ;
: DTUI-UNPACK-BG       _dtui-unpack-bg-xt     _dtui-guard WITH-GUARD ;
: DTUI-UNPACK-ATTRS    _dtui-unpack-attrs-xt  _dtui-guard WITH-GUARD ;
: DTUI-UNPACK-BORDER   _dtui-unpack-border-xt _dtui-guard WITH-GUARD ;
: DTUI-MARK-DIRTY      _dtui-mark-dirty-xt    _dtui-guard WITH-GUARD ;
: DTUI-MARK-GEOM-DIRTY _dtui-mark-gdirty-xt   _dtui-guard WITH-GUARD ;
: DTUI-SET-TEXT!        _dtui-set-text-xt      _dtui-guard WITH-GUARD ;
: DTUI-ATTR!            _dtui-attr-bang-xt     _dtui-guard WITH-GUARD ;
: DTUI-ATTR-DEL!        _dtui-attr-del-xt      _dtui-guard WITH-GUARD ;
: DTUI-SC-UDATA         _dtui-sc-udata-xt      _dtui-guard WITH-GUARD ;
: DTUI-SC-UDATA!        _dtui-sc-udata-bang-xt _dtui-guard WITH-GUARD ;
[THEN] [THEN]
