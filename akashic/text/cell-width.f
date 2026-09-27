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
\    CW-WIDTH       ( cp -- n )     Scalar width w(s): 0, 1, or 2.  A
\                                   scalar that Section 5 replaces
\                                   reports 1, the width of its U+FFFD.
\    CW-CHAR-WIDTH  ( cp -- n )     W(c) of the character that is this
\                                   one scalar: 0 when it is
\                                   Default_Ignorable, 1 for a mark with
\                                   no base, else its w(s).
\    CW-SWIDTH      ( addr u -- n ) String width: the sum of its
\                                   characters' widths W(c).
\ =================================================================

PROVIDED akashic-cell-width

REQUIRE utf8.f
REQUIRE unicode-props.f
REQUIRE grapheme.f

: CW-WIDTH  ( cp -- n )
    UP-PROPS DUP UP-INVALID? IF DROP 1 ELSE UP-WIDTH THEN ;

: CW-CHAR-WIDTH  ( cp -- n )
    UP-PROPS DUP UP-INVALID? IF DROP 1 EXIT THEN
    DUP UP-IGNORABLE? IF DROP 0 EXIT THEN
    UP-WIDTH 1 MAX ;

: CW-SWIDTH  ( addr u -- n )
    GR-SWIDTH ;

\ Every word is pure over immutable tables, except CW-SWIDTH, which is
\ GR-SWIDTH and carries that module's guard.
