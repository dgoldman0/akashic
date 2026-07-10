\ =====================================================================
\  app-desc.f - TUI applet descriptor, ABI version 1
\ =====================================================================
\  This is the first supported descriptor contract.  It replaces the
\  earlier prototype layout in place; no compatibility adapter exists.
\
\  APP-DESC is the TUI view/lifecycle adapter for a generic Akashic
\  component.  The host creates a CINST and passes it to every callback.
\  Applets do not own the terminal or event loop.
\ =====================================================================

PROVIDED akashic-tui-app-desc

REQUIRE ../runtime/instance.f

1095450960 CONSTANT APP-MAGIC       \ "AKAP"
1          CONSTANT APP-ABI-VERSION

1 CONSTANT APP-F-TICK-WHEN-CLEAN

  0 CONSTANT _AD-MAGIC
  8 CONSTANT _AD-ABI
 16 CONSTANT _AD-SIZE
 24 CONSTANT _AD-COMP-DESC
 32 CONSTANT _AD-INIT              \ ( instance -- )
 40 CONSTANT _AD-EVENT             \ ( event instance -- flag )
 48 CONSTANT _AD-TICK              \ ( instance -- )
 56 CONSTANT _AD-PAINT             \ ( instance -- )
 64 CONSTANT _AD-SHUTDOWN          \ ( instance -- )
 72 CONSTANT _AD-UIDL-A
 80 CONSTANT _AD-UIDL-U
 88 CONSTANT _AD-WIDTH
 96 CONSTANT _AD-HEIGHT
104 CONSTANT _AD-TITLE-A
112 CONSTANT _AD-TITLE-U
120 CONSTANT _AD-FLAGS
128 CONSTANT _AD-UIDL-FILE-A
136 CONSTANT _AD-UIDL-FILE-U
144 CONSTANT _AD-ACTIVATE          \ ( instance -- ), bind dynamic state
152 CONSTANT _AD-RESERVED-1

160 CONSTANT APP-DESC

: APP.MAGIC        ( desc -- a ) _AD-MAGIC + ;
: APP.ABI          ( desc -- a ) _AD-ABI + ;
: APP.SIZE         ( desc -- a ) _AD-SIZE + ;
: APP.COMP-DESC    ( desc -- a ) _AD-COMP-DESC + ;
: APP.INIT-XT      ( desc -- a ) _AD-INIT + ;
: APP.EVENT-XT     ( desc -- a ) _AD-EVENT + ;
: APP.TICK-XT      ( desc -- a ) _AD-TICK + ;
: APP.PAINT-XT     ( desc -- a ) _AD-PAINT + ;
: APP.SHUTDOWN-XT  ( desc -- a ) _AD-SHUTDOWN + ;
: APP.UIDL-A       ( desc -- a ) _AD-UIDL-A + ;
: APP.UIDL-U       ( desc -- a ) _AD-UIDL-U + ;
: APP.WIDTH        ( desc -- a ) _AD-WIDTH + ;
: APP.HEIGHT       ( desc -- a ) _AD-HEIGHT + ;
: APP.TITLE-A      ( desc -- a ) _AD-TITLE-A + ;
: APP.TITLE-U      ( desc -- a ) _AD-TITLE-U + ;
: APP.FLAGS        ( desc -- a ) _AD-FLAGS + ;
: APP.UIDL-FILE-A  ( desc -- a ) _AD-UIDL-FILE-A + ;
: APP.UIDL-FILE-U  ( desc -- a ) _AD-UIDL-FILE-U + ;
: APP.ACTIVATE-XT   ( desc -- a ) _AD-ACTIVATE + ;

: APP-DESC-INIT  ( desc -- )
    DUP APP-DESC 0 FILL
    APP-MAGIC OVER APP.MAGIC !
    APP-ABI-VERSION OVER APP.ABI !
    APP-DESC SWAP APP.SIZE ! ;

: APP-DESC-VALID?  ( desc -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP APP.MAGIC @ APP-MAGIC =
    OVER APP.ABI @ APP-ABI-VERSION = AND
    OVER APP.SIZE @ APP-DESC >= AND
    SWAP APP.COMP-DESC @ COMP-DESC-VALID? AND ;
