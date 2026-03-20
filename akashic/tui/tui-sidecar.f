\ =====================================================================
\  akashic/tui/tui-sidecar.f — Shared TUI Sidecar Record
\ =====================================================================
\
\  Unified sidecar (per-element screen descriptor) used by both
\  dom-tui.f and uidl-tui.f.  Provides the record layout, field
\  accessors, style pack/unpack, flag helpers, TRBL pack/unpack,
\  and basic paint primitives.
\
\  Each system maps its own tree node → sidecar address.  This module
\  doesn't know about DOM or UIDL — it only knows about the record.
\
\  Prefix: TSC-  (public), _TSC- (internal)
\  Provider: akashic-tui-sidecar
\
\  Load with:   REQUIRE tui-sidecar.f

PROVIDED akashic-tui-sidecar

REQUIRE cell.f
REQUIRE draw.f

\ =====================================================================
\  §1 — Record Layout (96 bytes = 12 cells)
\ =====================================================================
\
\   +0  flags      unified flag bits (TSC-F-* below)
\   +8  row        screen row
\  +16  col        screen column
\  +24  w          width (character cells)
\  +32  h          height (character cells)
\  +40  style      packed style (see §3)
\  +48  aux1       DOM: node backptr    / UIDL: widget-struct ptr
\  +56  aux2       DOM: draw-xt         / UIDL: padding (packed TRBL)
\  +64  aux3       DOM: userdata        / UIDL: offsets (4×16-bit signed)
\  +72  aux4       (reserved / DOM)     / UIDL: margin (packed TRBL)
\  +80  aux5       reserved
\  +88  aux6       reserved

96 CONSTANT TSC-SIZE

 0 CONSTANT TSC-O-FLAGS
 8 CONSTANT TSC-O-ROW
16 CONSTANT TSC-O-COL
24 CONSTANT TSC-O-W
32 CONSTANT TSC-O-H
40 CONSTANT TSC-O-STYLE
48 CONSTANT TSC-O-AUX1
56 CONSTANT TSC-O-AUX2
64 CONSTANT TSC-O-AUX3
72 CONSTANT TSC-O-AUX4
80 CONSTANT TSC-O-AUX5
88 CONSTANT TSC-O-AUX6

\ =====================================================================
\  §2 — Flag Bit Constants
\ =====================================================================
\
\  Superset of both DOM and UIDL flag bits.  Systems only test the
\  flags they care about.

  1 CONSTANT TSC-F-HAS          \ sidecar allocated (UIDL)
  2 CONSTANT TSC-F-VISIBLE      \ element is visible
  4 CONSTANT TSC-F-FOCUSABLE    \ can receive focus
  8 CONSTANT TSC-F-HIDDEN       \ visibility:hidden (space reserved, no paint)
 16 CONSTANT TSC-F-BLOCK        \ display:block (DOM)
 32 CONSTANT TSC-F-DIRTY        \ needs repaint (DOM)
 64 CONSTANT TSC-F-GEOM-DIRTY   \ geometry changed (DOM)
128 CONSTANT TSC-F-HIDE         \ display:none (UIDL)

\ =====================================================================
\  §3 — Style Packing
\ =====================================================================
\
\  Bits  0-7:   fg color index (0-255)
\  Bits  8-15:  bg color index (0-255)
\  Bits 16-31:  attribute flags (CELL-A-*)   — 16 bits
\  Bits 32-33:  text-align  (0=left 1=center 2=right)
\  Bits 34-35:  position    (0=static 1=absolute 2=fixed)
\  Bits 36-43:  z-index     (0-255)
\  Bits 44-51:  border-idx  (0=none 1=single 2=double 3=rounded 4=heavy)
\  Bits 52-63:  reserved

\ =====================================================================
\  §4 — Field Accessors
\ =====================================================================

: TSC-FLAGS@  ( sc -- n )  TSC-O-FLAGS + @ ;
: TSC-ROW@    ( sc -- n )  TSC-O-ROW   + @ ;
: TSC-COL@    ( sc -- n )  TSC-O-COL   + @ ;
: TSC-W@      ( sc -- n )  TSC-O-W     + @ ;
: TSC-H@      ( sc -- n )  TSC-O-H     + @ ;
: TSC-STYLE@  ( sc -- n )  TSC-O-STYLE + @ ;
: TSC-AUX1@   ( sc -- n )  TSC-O-AUX1  + @ ;
: TSC-AUX2@   ( sc -- n )  TSC-O-AUX2  + @ ;
: TSC-AUX3@   ( sc -- n )  TSC-O-AUX3  + @ ;
: TSC-AUX4@   ( sc -- n )  TSC-O-AUX4  + @ ;

: TSC-FLAGS!  ( n sc -- )  TSC-O-FLAGS + ! ;
: TSC-ROW!    ( n sc -- )  TSC-O-ROW   + ! ;
: TSC-COL!    ( n sc -- )  TSC-O-COL   + ! ;
: TSC-W!      ( n sc -- )  TSC-O-W     + ! ;
: TSC-H!      ( n sc -- )  TSC-O-H     + ! ;
: TSC-STYLE!  ( n sc -- )  TSC-O-STYLE + ! ;
: TSC-AUX1!   ( n sc -- )  TSC-O-AUX1  + ! ;
: TSC-AUX2!   ( n sc -- )  TSC-O-AUX2  + ! ;
: TSC-AUX3!   ( n sc -- )  TSC-O-AUX3  + ! ;
: TSC-AUX4!   ( n sc -- )  TSC-O-AUX4  + ! ;

\ =====================================================================
\  §5 — Style Pack / Unpack
\ =====================================================================

\ Core 3 fields (fg, bg, attrs) — both systems use these
: TSC-PACK-STYLE  ( fg bg attrs -- partial )
    16 LSHIFT SWAP 8 LSHIFT OR SWAP OR ;

: TSC-UNPACK-FG     ( style -- fg )     255 AND ;
: TSC-UNPACK-BG     ( style -- bg )     8 RSHIFT 255 AND ;
: TSC-UNPACK-ATTRS  ( style -- attrs )  16 RSHIFT 65535 AND ;

\ UIDL-specific style fields
: TSC-UNPACK-TALIGN  ( style -- align )   32 RSHIFT 3 AND ;
: TSC-UNPACK-POS     ( style -- pos )     34 RSHIFT 3 AND ;
: TSC-UNPACK-ZIDX    ( style -- z )       36 RSHIFT 255 AND ;

\ DOM-specific style field
: TSC-UNPACK-BORDER  ( style -- idx )     44 RSHIFT 255 AND ;

\ Pack border into style (DOM)
: TSC-PACK-BORDER  ( fg bg attrs border -- style )
    44 LSHIFT >R
    TSC-PACK-STYLE R> OR ;

\ Write z-index into an existing style word on a sidecar
: TSC-SET-ZIDX!  ( z sc -- )
    SWAP 255 AND 36 LSHIFT                   ( sc zbits )
    SWAP DUP TSC-STYLE@                      ( zbits sc style )
    0xFF000000000 INVERT AND                 ( zbits sc cleared )
    ROT OR SWAP TSC-STYLE! ;

\ Write text-align into an existing style word on a sidecar
: TSC-SET-TALIGN!  ( align sc -- )
    SWAP 3 AND 32 LSHIFT                     ( sc abits )
    SWAP DUP TSC-STYLE@                      ( abits sc style )
    0x300000000 INVERT AND                   ( abits sc cleared )
    ROT OR SWAP TSC-STYLE! ;

\ Write position into an existing style word on a sidecar
: TSC-SET-POS!  ( pos sc -- )
    SWAP 3 AND 34 LSHIFT                     ( sc pbits )
    SWAP DUP TSC-STYLE@                      ( pbits sc style )
    0xC00000000 INVERT AND                   ( pbits sc cleared )
    ROT OR SWAP TSC-STYLE! ;

\ Write border-idx into an existing style word on a sidecar
: TSC-SET-BORDER!  ( idx sc -- )
    SWAP 255 AND 44 LSHIFT                   ( sc bbits )
    SWAP DUP TSC-STYLE@                      ( bbits sc style )
    0xFF00000000000 INVERT AND               ( bbits sc cleared )
    ROT OR SWAP TSC-STYLE! ;

\ =====================================================================
\  §6 — Flag Helpers
\ =====================================================================

\ Visibility check: VISIBLE flag set AND not HIDDEN AND not HIDE
: TSC-VIS?  ( sc -- flag )
    TSC-FLAGS@
    DUP TSC-F-VISIBLE AND 0<>
    SWAP TSC-F-HIDDEN TSC-F-HIDE OR AND 0= AND ;

: TSC-DIRTY?  ( sc -- flag )
    TSC-FLAGS@ TSC-F-DIRTY AND 0<> ;

: TSC-MARK-DIRTY  ( sc -- )
    DUP TSC-FLAGS@ TSC-F-DIRTY OR SWAP TSC-FLAGS! ;

: TSC-CLEAR-DIRTY  ( sc -- )
    DUP TSC-FLAGS@ TSC-F-DIRTY INVERT AND SWAP TSC-FLAGS! ;

: TSC-MARK-GEOM-DIRTY  ( sc -- )
    DUP TSC-FLAGS@ TSC-F-DIRTY OR TSC-F-GEOM-DIRTY OR SWAP TSC-FLAGS! ;

: TSC-CLEAR-GEOM-DIRTY  ( sc -- )
    DUP TSC-FLAGS@ TSC-F-GEOM-DIRTY INVERT AND SWAP TSC-FLAGS! ;

\ =====================================================================
\  §7 — TRBL Pack / Unpack  (moved from uidl-tui.f)
\ =====================================================================

\ Pack 4 unsigned bytes (top, right, bottom, left) → single cell
\   top=bits 0-7, right=8-15, bottom=16-23, left=24-31
: TSC-PACK-TRBL  ( t r b l -- packed )
    24 LSHIFT SWAP 16 LSHIFT OR SWAP 8 LSHIFT OR SWAP OR ;

: TSC-UNPACK-TRBL  ( packed -- t r b l )
    DUP 255 AND                     \ top
    OVER 8 RSHIFT 255 AND          \ right
    2 PICK 16 RSHIFT 255 AND       \ bottom
    3 PICK 24 RSHIFT 255 AND       \ left
    >R >R >R NIP R> R> R> ;

\ Pack 4 signed 16-bit offsets → single cell
\   top=bits 0-15, right=16-31, bottom=32-47, left=48-63
: TSC-PACK-OFFS  ( top right bottom left -- packed )
    0xFFFF AND 48 LSHIFT
    SWAP 0xFFFF AND 32 LSHIFT OR
    SWAP 0xFFFF AND 16 LSHIFT OR
    SWAP 0xFFFF AND OR ;

\ Sign-extend a 16-bit value to full cell width
: TSC-SEXT16  ( u16 -- signed )
    DUP 0x8000 AND IF 0xFFFFFFFFFFFF0000 OR THEN ;

: TSC-UNPACK-OFFS  ( packed -- top right bottom left )
    DUP 0xFFFF AND TSC-SEXT16                  \ top
    OVER 16 RSHIFT 0xFFFF AND TSC-SEXT16       \ right
    2 PICK 32 RSHIFT 0xFFFF AND TSC-SEXT16     \ bottom
    3 PICK 48 RSHIFT 0xFFFF AND TSC-SEXT16     \ left
    >R >R >R NIP R> R> R> ;

\ =====================================================================
\  §8 — Paint Helpers
\ =====================================================================

\ Apply sidecar style to the draw engine (fg, bg, attrs)
: TSC-APPLY-STYLE  ( sc -- )
    TSC-STYLE@
    DUP TSC-UNPACK-FG
    OVER TSC-UNPACK-BG
    ROT TSC-UNPACK-ATTRS
    DRW-STYLE! ;

\ Apply style with reverse-video when the FOCUSABLE flag doubles as
\ "focused" indicator.  Caller sets the flag to mean "focused" before
\ calling this.  Convenience for UIDL's _UTUI-APPLY-STYLE pattern.
: TSC-APPLY-STYLE-FOC  ( sc focus? -- )
    >R
    TSC-STYLE@
    DUP TSC-UNPACK-FG
    OVER TSC-UNPACK-BG
    ROT TSC-UNPACK-ATTRS
    R> IF CELL-A-REVERSE OR THEN
    DRW-STYLE! ;

\ Fill sidecar's bounding rectangle with spaces (background fill)
: TSC-FILL-BG  ( sc -- )
    DUP TSC-APPLY-STYLE
    >R
    32
    R@ TSC-ROW@
    R@ TSC-COL@
    R@ TSC-H@
    R> TSC-W@
    DRW-FILL-RECT ;

\ Zero-fill an entire sidecar record
: TSC-CLEAR  ( sc -- )
    TSC-SIZE 0 FILL ;
