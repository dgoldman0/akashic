\ =====================================================================
\  keyring-surface.f - Desk's screen for the passphrase keyring
\ =====================================================================
\  An overlay Desk opens above its tiles with Alt+K: an ordinary UIDL
\  dialog with a canonical list, so it lowers to rich output like any
\  applet's list.  Its status line says what state the machine's keyring
\  (security/passphrase-keyring.f) is in, and its rows offer what that
\  state allows:
\
\    not set up       Set up a passphrase
\    locked           Unlock, then Start over
\    damaged file     Start over
\    unlocked         Lock now, then Change the passphrase
\    deriving a key   Cancel, while the status line counts the work done
\
\  Start over makes a new keyring in place of the old one, whose saved
\  secrets are then lost; its row says so.
\
\  The rows follow the keyring: when a derivation ends while the screen
\  is open, the rows change with it.  Enter chooses the selected row and
\  Escape closes the screen.  The screen asks for no passphrase and acts
\  on nothing itself: Desk calls KRS-SERVICE after each key and each
\  tick, and once it says to close, Desk carries out KRS-CHOSEN, asking
\  for a passphrase in its own masked prompt.
\
\  Public API:
\    KRS-DESC       ( -- desc )
\    KRS-OVERLAY?   ( desc -- flag )
\    KRS-BOX        ( desc -- row col h w )
\    KRS-BIND       ( keyring style-xt instance -- )
\    KRS-SERVICE    ( instance -- close? )
\    KRS-CHOSEN     ( instance -- action )
\  The actions: KRS-NONE, after Escape, then KRS-SETUP, KRS-UNLOCK,
\  KRS-LOCK, KRS-CHANGE, KRS-CANCEL and KRS-START-OVER.
\ =====================================================================

PROVIDED akashic-desk-keyring-ui

REQUIRE ../../app-desc.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widgets/list.f
REQUIRE ../../../utils/string.f
REQUIRE ../../../security/passphrase-keyring.f

\ =====================================================================
\  State
\ =====================================================================

0 CONSTANT KRS-NONE
1 CONSTANT KRS-SETUP
2 CONSTANT KRS-UNLOCK
3 CONSTANT KRS-LOCK
4 CONSTANT KRS-CHANGE
5 CONSTANT KRS-CANCEL
6 CONSTANT KRS-START-OVER

\ The status line's texts: one for each settled state, and one naming
\ each derivation, followed by its share done.
: _KRS-ABSENT$  ( -- a u )
    S" No passphrase is set. Set one up to keep secrets on this machine." ;
: _KRS-LOCKED$  ( -- a u )
    S" Locked. Unlock it so that applets can open their saved secrets." ;
: _KRS-UNLOCKED$  ( -- a u )
    S" Unlocked. Applets can open the secrets they saved." ;
: _KRS-DAMAGED$  ( -- a u )
    S" The keyring file is damaged. Start over to make a new one." ;
: _KRS-UNLOCKING$  ( -- a u ) S" Unlocking: " ;
: _KRS-SETTING-UP$  ( -- a u ) S" Setting up: " ;
: _KRS-CHANGING$  ( -- a u ) S" Changing the passphrase: " ;

\ The status line holds the longest of them, a derivation's with "100%".
_KRS-UNLOCKING$ NIP _KRS-SETTING-UP$ NIP MAX _KRS-CHANGING$ NIP MAX 4 +
_KRS-ABSENT$ NIP MAX _KRS-LOCKED$ NIP MAX _KRS-UNLOCKED$ NIP MAX
_KRS-DAMAGED$ NIP MAX
    CONSTANT _KRS-STATUS-MAX

  0 CONSTANT _KRS-KEYRING
  8 CONSTANT _KRS-STYLE
 16 CONSTANT _KRS-LIST
 24 CONSTANT _KRS-LIST-RGN
 32 CONSTANT _KRS-E-LIST
 40 CONSTANT _KRS-E-STATUS
 48 CONSTANT _KRS-CHOSEN     \ the action chosen, KRS-NONE until one is
 56 CONSTANT _KRS-DONE       \ a row was chosen, or Escape closed it
 64 CONSTANT _KRS-STATE      \ the keyring state the rows were made for
 72 CONSTANT _KRS-STATUS-U   \ the status text's length
 80 CONSTANT _KRS-STATUS     \ the status text
_KRS-STATUS _KRS-STATUS-MAX + CONSTANT _KRS-SIZE

: _KRS.KEYRING   ( s -- a ) _KRS-KEYRING + ;
: _KRS.STYLE     ( s -- a ) _KRS-STYLE + ;
: _KRS.LIST      ( s -- a ) _KRS-LIST + ;
: _KRS.LIST-RGN  ( s -- a ) _KRS-LIST-RGN + ;
: _KRS.E-LIST    ( s -- a ) _KRS-E-LIST + ;
: _KRS.E-STATUS  ( s -- a ) _KRS-E-STATUS + ;
: _KRS.CHOSEN    ( s -- a ) _KRS-CHOSEN + ;
: _KRS.DONE      ( s -- a ) _KRS-DONE + ;
: _KRS.STATE     ( s -- a ) _KRS-STATE + ;
: _KRS.STATUS-U  ( s -- a ) _KRS-STATUS-U + ;
: _KRS.STATUS    ( s -- a ) _KRS-STATUS + ;

\ The keyring's state, or KEYRING-ABSENT when the screen has none.
: _KRS-KEYRING-STATE  ( s -- state )
    _KRS.KEYRING @ ?DUP IF KEYRING-STATE@ ELSE KEYRING-ABSENT THEN ;

: _KRS-DERIVING?  ( state -- flag )
    DUP KEYRING-UNLOCKING = OVER KEYRING-SETTING-UP = OR
    SWAP KEYRING-CHANGING = OR ;

\ =====================================================================
\  Rows
\ =====================================================================

\ The action of row INDEX in STATE, or KRS-NONE past the rows.
: _KRS-ACTION  ( index state -- action )
    DUP _KRS-DERIVING? IF DROP 0= IF KRS-CANCEL ELSE KRS-NONE THEN EXIT THEN
    CASE
        KEYRING-ABSENT OF 0= IF KRS-SETUP ELSE KRS-NONE THEN ENDOF
        KEYRING-LOCKED OF
            DUP 0= IF DROP KRS-UNLOCK ELSE 1 = IF KRS-START-OVER ELSE KRS-NONE THEN THEN
        ENDOF
        KEYRING-DAMAGED OF 0= IF KRS-START-OVER ELSE KRS-NONE THEN ENDOF
        KEYRING-UNLOCKED OF
            DUP 0= IF DROP KRS-LOCK ELSE 1 = IF KRS-CHANGE ELSE KRS-NONE THEN THEN
        ENDOF
        NIP KRS-NONE SWAP
    ENDCASE ;

: _KRS-ROW-N  ( state -- n )
    DUP KEYRING-UNLOCKED = SWAP KEYRING-LOCKED = OR IF 2 ELSE 1 THEN ;

: _KRS-ACTION$  ( action -- a u )
    CASE
        KRS-SETUP OF S" Set up a passphrase" ENDOF
        KRS-UNLOCK OF S" Unlock" ENDOF
        KRS-LOCK OF S" Lock now" ENDOF
        KRS-CHANGE OF S" Change the passphrase" ENDOF
        KRS-CANCEL OF S" Cancel" ENDOF
        KRS-START-OVER OF S" Start over, losing the saved secrets" ENDOF
        >R 0 0 R>
    ENDCASE ;

\ A row's key is its action, which no other row of the state has.
: _KRS-KEY  ( index widget -- key )
    LST-CONTEXT@ _KRS.STATE @ _KRS-ACTION ;

: _KRS-FIELD  ( index column widget -- a u )
    NIP LST-CONTEXT@ _KRS.STATE @ _KRS-ACTION _KRS-ACTION$ ;

\ Enter on a row chooses its action, and the screen closes.
: _KRS-OPENED  ( index widget -- )
    LST-CONTEXT@ >R R@ _KRS.STATE @ _KRS-ACTION
    DUP KRS-NONE = IF DROP R> DROP EXIT THEN
    R@ _KRS.CHOSEN !  -1 R> _KRS.DONE ! ;

\ Makes the rows for the keyring's state, the first selected.
: _KRS-ROWS  ( s -- )
    DUP _KRS-KEYRING-STATE OVER _KRS.STATE !
    DUP _KRS.LIST @ ?DUP 0= IF DROP EXIT THEN >R
    _KRS.STATE @ _KRS-ROW-N R@ LST-ROWS!
    0 R> LST-SELECT ;

\ =====================================================================
\  The status line
\ =====================================================================

\ Appends A U to the status text, as far as it has room.
: _KRS-SAY+  ( a u s -- )
    >R _KRS-STATUS-MAX R@ _KRS.STATUS-U @ - MIN 0 MAX
    R@ _KRS.STATUS R@ _KRS.STATUS-U @ + SWAP DUP >R MOVE
    R> R> _KRS.STATUS-U +! ;

: _KRS-DERIVING$  ( state -- a u )
    CASE
        KEYRING-UNLOCKING OF _KRS-UNLOCKING$ ENDOF
        KEYRING-SETTING-UP OF _KRS-SETTING-UP$ ENDOF
        >R _KRS-CHANGING$ R>
    ENDCASE ;

: _KRS-STATE$  ( state -- a u )
    CASE
        KEYRING-ABSENT OF _KRS-ABSENT$ ENDOF
        KEYRING-LOCKED OF _KRS-LOCKED$ ENDOF
        KEYRING-DAMAGED OF _KRS-DAMAGED$ ENDOF
        >R _KRS-UNLOCKED$ R>
    ENDCASE ;

\ The share of the derivation done, in whole percent.
: _KRS-PERCENT  ( keyring -- n )
    KEYRING-PROGRESS ?DUP 0= IF DROP 0 EXIT THEN
    >R 100 * R> / ;

\ Builds the status text the keyring's state calls for.
: _KRS-STATUS!  ( s -- )
    0 OVER _KRS.STATUS-U !
    DUP _KRS-KEYRING-STATE DUP _KRS-DERIVING? IF
        _KRS-DERIVING$ 2 PICK _KRS-SAY+
        DUP _KRS.KEYRING @ _KRS-PERCENT NUM>STR 2 PICK _KRS-SAY+
        S" %" ROT _KRS-SAY+ EXIT
    THEN
    _KRS-STATE$ ROT _KRS-SAY+ ;

\ =====================================================================
\  Overlay lifecycle
\ =====================================================================

: _KRS-UIDL  ( -- a u )
    S" <uidl arrange=stack><dialog id=screen title=Keyring><label id=status/><label id=hint/><region id=rows/></dialog></uidl>" ;

: _KRS-HINT$  ( -- a u ) S" Up/Down choose  Enter select  Esc close" ;

: _KRS-STYLE-ALL  ( s -- )
    _KRS.STYLE @ ?DUP IF UTUI-EACH-ELEM THEN ;

\ Activation runs with the overlay's UIDL context current, before each of
\ its events, ticks and paints.  It keeps the style current, makes the
\ rows again when the keyring's state has moved, and sets the status
\ line when its text changes.
CREATE _KRS-PREVIOUS _KRS-STATUS-MAX ALLOT
VARIABLE _KRS-PREVIOUS-U

: _KRS-ACTIVATE  ( instance -- )
    CINST-STATE >R
    R@ _KRS-STYLE-ALL
    R@ _KRS-KEYRING-STATE R@ _KRS.STATE @ <> IF R@ _KRS-ROWS THEN
    R@ _KRS.STATUS R@ _KRS.STATUS-U @ DUP _KRS-PREVIOUS-U !
    _KRS-PREVIOUS SWAP MOVE
    R@ _KRS-STATUS!
    R@ _KRS.E-STATUS @ ?DUP IF
        R@ _KRS.STATUS R@ _KRS.STATUS-U @
        _KRS-PREVIOUS _KRS-PREVIOUS-U @ COMPARE IF
            S" text" R@ _KRS.STATUS R@ _KRS.STATUS-U @ UTUI-SET-ATTR
        ELSE
            DROP
        THEN
    THEN
    R> DROP ;

CREATE _KRS-COLUMNS LST-COLUMN-SIZE ALLOT

: _KRS-COLUMNS-INIT  ( -- )
    _KRS-COLUMNS LST-COLUMN-SIZE 0 FILL
    LST-TEXT-COLUMN _KRS-COLUMNS LST-COLUMN-KIND + ! ;

: _KRS-INIT  ( instance -- )
    CINST-STATE >R
    R@ _KRS-SIZE 0 FILL
    S" status" UTUI-BY-ID R@ _KRS.E-STATUS !
    S" hint" UTUI-BY-ID ?DUP IF S" text" _KRS-HINT$ UTUI-SET-ATTR THEN
    S" rows" UTUI-BY-ID DUP R@ _KRS.E-LIST ! 0= IF R> DROP EXIT THEN
    R@ _KRS.E-LIST @ UTUI-ELEM-RGN RGN-NEW DUP R@ _KRS.LIST-RGN !
    ['] _KRS-KEY ['] _KRS-FIELD LST-NEW
    ['] _KRS-OPENED OVER LST-ON-OPEN
    DUP R@ _KRS.LIST !
    _KRS-COLUMNS 1 ROT LST-COLUMNS!
    R@ R@ _KRS.LIST @ LST-CONTEXT!
    R@ _KRS.LIST @ R@ _KRS.E-LIST @ UTUI-WIDGET-SET
    R@ _KRS.E-LIST @ UTUI-FOCUS!
    R> DROP ;

: _KRS-SHUTDOWN  ( instance -- )
    CINST-STATE >R
    R@ _KRS.E-LIST @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    R@ _KRS.LIST @ ?DUP IF LST-FREE THEN
    R@ _KRS.LIST-RGN @ ?DUP IF RGN-FREE THEN
    R> _KRS-SIZE 0 FILL ;

: _KRS-EV-TYPE  ( ev -- type ) @ ;
: _KRS-EV-CODE  ( ev -- code ) 8 + @ ;

\ Escape closes the screen choosing nothing; every other key goes to the
\ list.
: _KRS-EVENT  ( ev instance -- handled? )
    CINST-STATE >R
    DUP _KRS-EV-TYPE KEY-T-SPECIAL = IF
        DUP _KRS-EV-CODE KEY-ESC = IF
            DROP KRS-NONE R@ _KRS.CHOSEN !  -1 R> _KRS.DONE ! -1 EXIT
        THEN
    THEN
    DROP R> DROP 0 ;

\ =====================================================================
\  Descriptor and Desk's interface
\ =====================================================================

CREATE KRS-DESC APP-DESC ALLOT
CREATE _KRS-COMP COMP-DESC ALLOT

: _KRS-SETUP  ( -- )
    _KRS-COLUMNS-INIT
    _KRS-COMP COMP-DESC-INIT
    S" org.akashic.desk.keyring" _KRS-COMP COMP.ID-U ! _KRS-COMP COMP.ID-A !
    S" 1.0.0" _KRS-COMP COMP.VERSION-U ! _KRS-COMP COMP.VERSION-A !
    _KRS-SIZE _KRS-COMP COMP.STATE-SIZE !
    KRS-DESC APP-DESC-INIT
    _KRS-COMP KRS-DESC APP.COMP-DESC !
    S" Keyring" KRS-DESC APP.TITLE-U ! KRS-DESC APP.TITLE-A !
    ['] _KRS-INIT KRS-DESC APP.INIT-XT !
    ['] _KRS-SHUTDOWN KRS-DESC APP.SHUTDOWN-XT !
    ['] _KRS-ACTIVATE KRS-DESC APP.ACTIVATE-XT !
    ['] _KRS-EVENT KRS-DESC APP.EVENT-XT !
    _KRS-UIDL KRS-DESC APP.UIDL-U ! KRS-DESC APP.UIDL-A ! ;

_KRS-SETUP

: KRS-OVERLAY?  ( desc -- flag )  KRS-DESC = ;

\ The centred box the screen takes: its dialog's frame with the title on
\ its top edge, the status and hint lines, two rows and a spare one, as
\ wide as a reading column.
: KRS-BOX  ( desc -- row col h w )
    DROP 8
    SCR-W 4 - 76 MIN DUP 24 < IF DROP SCR-W 2 - THEN
    OVER SCR-H SWAP - 1- 2 / 0 MAX
    OVER SCR-W SWAP - 2 / 0 MAX
    2SWAP ;

\ Binds a launched screen to KEYRING.  STYLE-XT ( elem -- ) styles each
\ element, or is 0.
: KRS-BIND  ( keyring style-xt instance -- )
    CINST-STATE >R
    R@ _KRS.STYLE ! R@ _KRS.KEYRING !
    R@ _KRS-ROWS
    R@ _KRS-STATUS!
    R@ _KRS.E-STATUS @ ?DUP IF
        S" text" R@ _KRS.STATUS R@ _KRS.STATUS-U @ UTUI-SET-ATTR
    THEN
    R> DROP ;

\ Whether Desk should close the screen: a row was chosen or Escape
\ pressed.  Desk calls it after the host dispatches each key and on each
\ tick, never from inside the screen's own callbacks.
: KRS-SERVICE  ( instance -- close? )  CINST-STATE _KRS.DONE @ 0<> ;

\ What the user chose, for Desk to carry out once the screen closes.
: KRS-CHOSEN  ( instance -- action )  CINST-STATE _KRS.CHOSEN @ ;
