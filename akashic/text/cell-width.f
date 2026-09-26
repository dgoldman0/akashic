\ =================================================================
\  cell-width.f — terminal cell widths
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: CW- / _CW-
\  Depends on: utf8.f, unicode-props.f, grapheme.f
\
\  Widths follow the shared text contract,
\  docs/rich-terminal/APT-1-TEXT.md Section 4, using the Unicode
\  15.1.0 tables generated into unicode-tables.f.
\
\  Public API:
\    CW-WIDTH    ( cp -- n )     Scalar width w(s): 0, 1, or 2.  A scalar
\                                that Section 5 replaces reports 1, the
\                                width of its U+FFFD.
\    CW-SWIDTH   ( addr u -- n ) String width: the sum of its characters'
\                                widths W(c).
\    CW-CELL-CP  ( cp -- cp' )   Project to one isolated width-one cell.
\    CW-CELL-CP-WITH ( cp state -- cp' )  Same; STATE is unused.
\    CW-STATE-SIZE  ( -- n )
\
\  CW-CELL-CP is a bridge for the cell plane, which does not yet store
\  wide and cluster cells.  It goes away when the screen does.
\ =================================================================

PROVIDED akashic-cell-width

REQUIRE utf8.f
REQUIRE unicode-props.f
REQUIRE grapheme.f

: CW-WIDTH  ( cp -- n )
    UP-PROPS DUP UP-INVALID? IF DROP 1 ELSE UP-WIDTH THEN ;

: CW-SWIDTH  ( addr u -- n )
    GR-SWIDTH ;

8 CONSTANT CW-STATE-SIZE

: CW-CELL-CP-WITH  ( cp state -- cp' )
    DROP
    DUP 0< IF DROP UTF8-REPLACEMENT EXIT THEN
    DUP 0x10FFFF > IF DROP UTF8-REPLACEMENT EXIT THEN
    DUP 0xD800 0xE000 WITHIN IF DROP UTF8-REPLACEMENT EXIT THEN
    UTF8-DISPLAY-CP
    DUP UP-PROPS DUP UP-INVALID? SWAP UP-WIDTH 1 <> OR IF
        DROP UTF8-REPLACEMENT
    THEN ;

: CW-CELL-CP  ( cp -- cp' )
    0 CW-CELL-CP-WITH ;

\ Every word is pure over immutable tables, except CW-SWIDTH, which is
\ GR-SWIDTH and carries that module's guard.
