\ =================================================================
\  style-palette.f — how each text meaning looks in CELL
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: SPAL- / _SPAL-
\  Depends on: cell.f, ../text/text-style.f
\
\  A palette gives each meaning of text-style.f the foreground colour
\  (an xterm-256 index) and the cell attributes CELL draws it with.
\  The background stays the one the text is drawn on, and plain text
\  keeps the drawing style it already has.  Meanings never change a
\  character's cells, so a palette changes colour and attributes only.
\
\  A palette is SPAL-SIZE bytes of caller storage, or the shared
\  SPAL-DEFAULT, whose colours suit a dark background.
\
\  Public API:
\    SPAL-SIZE     ( -- bytes )
\    SPAL-DEFAULT  ( -- palette )
\    SPAL-INIT     ( palette -- )           copy the default
\    SPAL-SET      ( fg attrs meaning palette -- )
\    SPAL-FG@      ( meaning palette -- fg )
\    SPAL-ATTRS@   ( meaning palette -- attrs )
\ =================================================================

PROVIDED akashic-tui-style-palette

REQUIRE cell.f
REQUIRE ../text/text-style.f

\ One cell per meaning: fg in bits 0-7, attributes above them.
TSTY-COUNT CELLS CONSTANT SPAL-SIZE

: _SPAL-ENTRY  ( meaning palette -- addr )  SWAP CELLS + ;

: SPAL-SET  ( fg attrs meaning palette -- )
    _SPAL-ENTRY >R 8 LSHIFT SWAP 0xFF AND OR R> ! ;

: SPAL-FG@     ( meaning palette -- fg )     _SPAL-ENTRY @ 0xFF AND ;
: SPAL-ATTRS@  ( meaning palette -- attrs )  _SPAL-ENTRY @ 8 RSHIFT ;

CREATE SPAL-DEFAULT  SPAL-SIZE ALLOT
SPAL-DEFAULT SPAL-SIZE 0 FILL
\  fg   attrs              meaning
    7   0                  TSTY-PLAIN     SPAL-DEFAULT SPAL-SET
   81   CELL-A-BOLD        TSTY-KEYWORD   SPAL-DEFAULT SPAL-SET
  245   CELL-A-ITALIC      TSTY-COMMENT   SPAL-DEFAULT SPAL-SET
  186   0                  TSTY-STRING    SPAL-DEFAULT SPAL-SET
  141   0                  TSTY-NUMBER    SPAL-DEFAULT SPAL-SET
  215   CELL-A-BOLD        TSTY-HEADING   SPAL-DEFAULT SPAL-SET
  223   CELL-A-ITALIC      TSTY-EMPHASIS  SPAL-DEFAULT SPAL-SET
  231   CELL-A-BOLD        TSTY-STRONG    SPAL-DEFAULT SPAL-SET
  114   0                  TSTY-CODE      SPAL-DEFAULT SPAL-SET
   75   CELL-A-UNDERLINE   TSTY-LINK      SPAL-DEFAULT SPAL-SET
  203   CELL-A-UNDERLINE   TSTY-ERROR     SPAL-DEFAULT SPAL-SET

: SPAL-INIT  ( palette -- )  SPAL-DEFAULT SWAP SPAL-SIZE CMOVE ;
