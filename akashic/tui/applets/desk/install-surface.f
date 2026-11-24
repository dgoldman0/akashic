\ =====================================================================
\  install-surface.f - Desk's question before an applet is installed
\ =====================================================================
\  An overlay Desk opens above its tiles when something asks to install
\  a project through the applet builder (app-builder.f): an ordinary
\  UIDL dialog with a canonical list, so it lowers to rich output like
\  Desk's other screens.  Its message names the project and says what
\  installing means, the builder's ABUILD-STATEMENT; its rows are Cancel,
\  then Install, so Enter alone cancels, and so does Escape.
\
\  The screen answers the builder's question itself, from KIS-SERVICE,
\  which Desk calls after each key and each tick, and says to close once
\  it has answered or once the question no longer waits, as when its
\  asker withdrew it.
\
\  Public API:
\    KIS-DESC       ( -- desc )
\    KIS-OVERLAY?   ( desc -- flag )
\    KIS-BOX        ( desc -- row col h w )
\    KIS-BIND       ( style-xt instance -- )
\    KIS-SERVICE    ( instance -- close? )
\ =====================================================================

PROVIDED akashic-desk-install-ui

REQUIRE ../../app-desc.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widgets/list.f
REQUIRE ../../app-builder.f

\ =====================================================================
\  State
\ =====================================================================

\ What the user chose.  The rows are Cancel, then Install.
0 CONSTANT _KIS-C-NONE
1 CONSTANT _KIS-C-CANCEL
2 CONSTANT _KIS-C-INSTALL

\ The project line: its lead and the longest path a manifest takes.
: _KIS-PROJECT-LEAD$  ( -- a u ) S" Project: " ;
_KIS-PROJECT-LEAD$ NIP MFT-PATH-MAX + CONSTANT _KIS-PROJECT-MAX

  0 CONSTANT _KIS-STYLE
  8 CONSTANT _KIS-LIST
 16 CONSTANT _KIS-LIST-RGN
 24 CONSTANT _KIS-E-LIST
 32 CONSTANT _KIS-CHOICE
 40 CONSTANT _KIS-ANSWERED     \ the screen answered the question
 48 CONSTANT _KIS-PROJECT-U
 56 CONSTANT _KIS-PROJECT      \ the project line
_KIS-PROJECT _KIS-PROJECT-MAX + 7 + -8 AND CONSTANT _KIS-SIZE

: _KIS.STYLE      ( s -- a ) _KIS-STYLE + ;
: _KIS.LIST       ( s -- a ) _KIS-LIST + ;
: _KIS.LIST-RGN   ( s -- a ) _KIS-LIST-RGN + ;
: _KIS.E-LIST     ( s -- a ) _KIS-E-LIST + ;
: _KIS.CHOICE     ( s -- a ) _KIS-CHOICE + ;
: _KIS.ANSWERED   ( s -- a ) _KIS-ANSWERED + ;
: _KIS.PROJECT-U  ( s -- a ) _KIS-PROJECT-U + ;
: _KIS.PROJECT    ( s -- a ) _KIS-PROJECT + ;

\ =====================================================================
\  Rows
\ =====================================================================

: _KIS-KEY  ( index widget -- key ) DROP 1+ ;

: _KIS-FIELD  ( index column widget -- a u )
    2DROP IF S" Install" ELSE S" Cancel" THEN ;

: _KIS-OPENED  ( index widget -- )
    LST-CONTEXT@ SWAP IF _KIS-C-INSTALL ELSE _KIS-C-CANCEL THEN
    SWAP _KIS.CHOICE ! ;

\ The project line for the question waiting, or none.
: _KIS-PROJECT!  ( s -- )
    >R ABUILD-ASKING DROP                          ( path-a path-u )
    _KIS-PROJECT-LEAD$ R@ _KIS.PROJECT SWAP MOVE
    _KIS-PROJECT-MAX _KIS-PROJECT-LEAD$ NIP - MIN
    DUP _KIS-PROJECT-LEAD$ NIP + R@ _KIS.PROJECT-U !
    R> _KIS.PROJECT _KIS-PROJECT-LEAD$ NIP + SWAP MOVE ;

\ =====================================================================
\  Overlay lifecycle
\ =====================================================================

: _KIS-UIDL  ( -- a u )
    S" <uidl arrange=stack><dialog id=screen><label id=project/><label id=statement/><label id=hint/><region id=rows/></dialog></uidl>" ;

: _KIS-TITLE$  ( -- a u ) S" Install an applet?" ;
: _KIS-HINT$  ( -- a u ) S" Up/Down choose  Enter answer  Esc cancel" ;

: _KIS-STYLE-ALL  ( s -- )
    _KIS.STYLE @ ?DUP IF UTUI-EACH-ELEM THEN ;

: _KIS-ACTIVATE  ( instance -- ) CINST-STATE _KIS-STYLE-ALL ;

CREATE _KIS-COLUMNS LST-COLUMN-SIZE ALLOT

: _KIS-COLUMNS-INIT  ( -- )
    _KIS-COLUMNS LST-COLUMN-SIZE 0 FILL
    LST-TEXT-COLUMN _KIS-COLUMNS LST-COLUMN-KIND + ! ;

: _KIS-INIT  ( instance -- )
    CINST-STATE >R
    R@ _KIS-SIZE 0 FILL
    S" screen" UTUI-BY-ID ?DUP IF S" title" _KIS-TITLE$ UTUI-SET-ATTR THEN
    S" statement" UTUI-BY-ID ?DUP IF S" text" ABUILD-STATEMENT UTUI-SET-ATTR THEN
    S" hint" UTUI-BY-ID ?DUP IF S" text" _KIS-HINT$ UTUI-SET-ATTR THEN
    R@ _KIS-PROJECT!
    S" project" UTUI-BY-ID ?DUP IF
        S" text" R@ _KIS.PROJECT R@ _KIS.PROJECT-U @ UTUI-SET-ATTR
    THEN
    S" rows" UTUI-BY-ID DUP R@ _KIS.E-LIST ! 0= IF R> DROP EXIT THEN
    R@ _KIS.E-LIST @ UTUI-ELEM-RGN RGN-NEW DUP R@ _KIS.LIST-RGN !
    ['] _KIS-KEY ['] _KIS-FIELD LST-NEW
    ['] _KIS-OPENED OVER LST-ON-OPEN
    DUP R@ _KIS.LIST !
    _KIS-COLUMNS 1 ROT LST-COLUMNS!
    R@ R@ _KIS.LIST @ LST-CONTEXT!
    2 R@ _KIS.LIST @ LST-ROWS!
    0 R@ _KIS.LIST @ LST-SELECT
    R@ _KIS.LIST @ R@ _KIS.E-LIST @ UTUI-WIDGET-SET
    R@ _KIS.E-LIST @ UTUI-FOCUS!
    R> DROP ;

: _KIS-SHUTDOWN  ( instance -- )
    CINST-STATE >R
    R@ _KIS.E-LIST @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    R@ _KIS.LIST @ ?DUP IF LST-FREE THEN
    R@ _KIS.LIST-RGN @ ?DUP IF RGN-FREE THEN
    R> _KIS-SIZE 0 FILL ;

: _KIS-EV-TYPE  ( ev -- type ) @ ;
: _KIS-EV-CODE  ( ev -- code ) 8 + @ ;

\ Escape cancels; every other key goes to the list.
: _KIS-EVENT  ( ev instance -- handled? )
    CINST-STATE >R
    DUP _KIS-EV-TYPE KEY-T-SPECIAL = IF
        DUP _KIS-EV-CODE KEY-ESC = IF
            DROP _KIS-C-CANCEL R> _KIS.CHOICE ! -1 EXIT
        THEN
    THEN
    DROP R> DROP 0 ;

\ =====================================================================
\  Descriptor and Desk's interface
\ =====================================================================

CREATE KIS-DESC APP-DESC ALLOT
CREATE _KIS-COMP COMP-DESC ALLOT

: _KIS-SETUP  ( -- )
    _KIS-COLUMNS-INIT
    _KIS-COMP COMP-DESC-INIT
    S" org.akashic.desk.install" _KIS-COMP COMP.ID-U ! _KIS-COMP COMP.ID-A !
    S" 1.0.0" _KIS-COMP COMP.VERSION-U ! _KIS-COMP COMP.VERSION-A !
    _KIS-SIZE _KIS-COMP COMP.STATE-SIZE !
    KIS-DESC APP-DESC-INIT
    _KIS-COMP KIS-DESC APP.COMP-DESC !
    S" Install" KIS-DESC APP.TITLE-U ! KIS-DESC APP.TITLE-A !
    ['] _KIS-INIT KIS-DESC APP.INIT-XT !
    ['] _KIS-SHUTDOWN KIS-DESC APP.SHUTDOWN-XT !
    ['] _KIS-ACTIVATE KIS-DESC APP.ACTIVATE-XT !
    ['] _KIS-EVENT KIS-DESC APP.EVENT-XT !
    _KIS-UIDL KIS-DESC APP.UIDL-U ! KIS-DESC APP.UIDL-A ! ;

_KIS-SETUP

: KIS-OVERLAY?  ( desc -- flag )  KIS-DESC = ;

\ The centred box the question takes: its frame with the title on its top
\ edge, the project line, the statement on a reading column's lines, the
\ hint, the two rows and a spare one.
: KIS-BOX  ( desc -- row col h w )
    DROP SCR-H 3 - 14 MIN 8 MAX
    SCR-W 4 - 76 MIN DUP 24 < IF DROP SCR-W 2 - THEN
    OVER SCR-H SWAP - 1- 2 / 0 MAX
    OVER SCR-W SWAP - 2 / 0 MAX
    2SWAP ;

\ Binds a launched question.  STYLE-XT ( elem -- ) styles each element,
\ or is 0.
: KIS-BIND  ( style-xt instance -- )  CINST-STATE _KIS.STYLE ! ;

\ Answers the builder with what the user chose, and says whether Desk
\ should close the screen: once it has answered, or once the question no
\ longer waits.  Desk calls it after each key and each tick, never from
\ inside the screen's own callbacks.
: KIS-SERVICE  ( instance -- close? )
    CINST-STATE >R
    R@ _KIS.ANSWERED @ IF R> DROP -1 EXIT THEN
    ABUILD-QUESTION@ ABUILD-Q-ASKING <> IF R> DROP -1 EXIT THEN
    R@ _KIS.CHOICE @ ?DUP 0= IF R> DROP 0 EXIT THEN
    _KIS-C-INSTALL = ABUILD-ANSWER
    -1 R> _KIS.ANSWERED ! -1 ;
