\ =====================================================================
\  sandbox-surface.f - Desk's screens for the shared sandbox
\ =====================================================================
\  Two small overlays Desk opens above its tiles.  Each is an ordinary
\  UIDL document with a canonical list, so it lowers to rich output like
\  any applet's list:
\
\    the access prompt  asks the user whether a component may use a
\                       module revision, when it asks through
\                       org.akashic.sandbox/authorize;
\    the inspector      lists the installed modules and the grants of the
\                       binding's Practice, and revokes, removes or
\                       withdraws them.
\
\  Each overlay keeps its state in its own instance.  Desk launches it,
\  binds it to the capability, sends it every key while it is open, and
\  after each key and each tick calls SBXS-SERVICE, which carries out what
\  the user chose outside the overlay's own callbacks and says whether to
\  close it.  An access prompt answers only the request it shows: the
\  request's identity must still match when the answer is given.
\ =====================================================================

PROVIDED akashic-desk-sandbox-surface

REQUIRE ../../app-desc.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widgets/list.f
REQUIRE ../../../interop/sandbox-capability.f
REQUIRE ../../../utils/string.f

\ =====================================================================
\  State
\ =====================================================================

1 CONSTANT _SXS-K-ACCESS
2 CONSTANT _SXS-K-INSPECT

\ What the user chose.  The access prompt's rows are Refuse, then Allow,
\ so Enter alone refuses.
1 CONSTANT _SXS-C-ALLOW
2 CONSTANT _SXS-C-REFUSE
1 CONSTANT _SXS-C-REVOKE
2 CONSTANT _SXS-C-REMOVE

160 CONSTANT _SXS-LINE
192 CONSTANT _SXS-ASK-MAX
 32 CONSTANT _SXS-STATE-MAX

  0 CONSTANT _SXS-KIND
  8 CONSTANT _SXS-CAP
 16 CONSTANT _SXS-STYLE
 24 CONSTANT _SXS-LIST
 32 CONSTANT _SXS-LIST-RGN
 40 CONSTANT _SXS-E-LIST
 48 CONSTANT _SXS-E-ASK
 56 CONSTANT _SXS-E-STATUS
 64 CONSTANT _SXS-ROWS
 72 CONSTANT _SXS-ASK
 80 CONSTANT _SXS-ASK-ID
 88 CONSTANT _SXS-CHOICE
 96 CONSTANT _SXS-ROW
104 CONSTANT _SXS-DONE
112 CONSTANT _SXS-REFRESH
120 CONSTANT _SXS-ASKED
128 CONSTANT _SXS-SHOWN
136 CONSTANT _SXS-STATUS-U
144 CONSTANT _SXS-STATUS
_SXS-STATUS _SXS-LINE + CONSTANT _SXS-TEXT
_SXS-TEXT _SXS-ASK-MAX + CONSTANT _SXS-COL0
_SXS-COL0 _SXS-LINE + CONSTANT _SXS-COL1
_SXS-COL1 _SXS-STATE-MAX + CONSTANT _SXS-SIZE

: _SXS.KIND      ( s -- a ) _SXS-KIND + ;
\ The capability instance, and Desk's style for each element.
: _SXS.CAP       ( s -- a ) _SXS-CAP + ;
: _SXS.STYLE     ( s -- a ) _SXS-STYLE + ;
: _SXS.LIST      ( s -- a ) _SXS-LIST + ;
: _SXS.LIST-RGN  ( s -- a ) _SXS-LIST-RGN + ;
: _SXS.E-LIST    ( s -- a ) _SXS-E-LIST + ;
: _SXS.E-ASK     ( s -- a ) _SXS-E-ASK + ;
: _SXS.E-STATUS  ( s -- a ) _SXS-E-STATUS + ;
: _SXS.ROWS      ( s -- a ) _SXS-ROWS + ;
\ The request an access prompt shows, and its identity.
: _SXS.ASK       ( s -- a ) _SXS-ASK + ;
: _SXS.ASK-ID    ( s -- a ) _SXS-ASK-ID + ;
\ The user's choice, the inspector row it is for, and whether Esc closed
\ the inspector.
: _SXS.CHOICE    ( s -- a ) _SXS-CHOICE + ;
: _SXS.ROW       ( s -- a ) _SXS-ROW + ;
: _SXS.DONE      ( s -- a ) _SXS-DONE + ;
\ Whether the rows changed, the question is on screen, and the status
\ line is current.
: _SXS.REFRESH   ( s -- a ) _SXS-REFRESH + ;
: _SXS.ASKED     ( s -- a ) _SXS-ASKED + ;
: _SXS.SHOWN     ( s -- a ) _SXS-SHOWN + ;
: _SXS.STATUS-U  ( s -- a ) _SXS-STATUS-U + ;
\ Text buffers: the status line, the question, and one per column, as a
\ list takes each field before it asks for the next.
: _SXS.STATUS    ( s -- a ) _SXS-STATUS + ;
: _SXS.TEXT      ( s -- a ) _SXS-TEXT + ;
: _SXS.COL0      ( s -- a ) _SXS-COL0 + ;
: _SXS.COL1      ( s -- a ) _SXS-COL1 + ;

: _SXS-ACCESS?  ( s -- flag ) _SXS.KIND @ _SXS-K-ACCESS = ;

\ =====================================================================
\  Text
\ =====================================================================

\ Appends TEXT to the LENGTH bytes at BUFFER, as far as CAPACITY allows.
: _SXS-APPEND  ( buffer length capacity text-a text-u -- buffer length' capacity )
    >R >R
    2DUP SWAP - R> SWAP R> MIN
    DUP >R 4 PICK 4 PICK + SWAP MOVE
    SWAP R> + SWAP ;

\ Appends a module revision: its name, or (lost) when the store lost its
\ declaration, and its revision.
: _SXS-APPEND-MODULE  ( buffer length capacity module|0 -- buffer length' capacity )
    ?DUP 0= IF S" (removed)" _SXS-APPEND EXIT THEN
    DUP >R SBOX-MODULE-DECLARATION$ DROP ?DUP IF
        SBOX-DECL-MODULE-NAME$
    ELSE
        S" (lost)"
    THEN
    _SXS-APPEND S"  " _SXS-APPEND
    R> SBOX-MODULE-KEY@ NIP NUM>STR _SXS-APPEND ;

: _SXS-SAID  ( s -- )
    0 OVER _SXS.STATUS-U ! 0 SWAP _SXS.SHOWN ! ;

\ Adds TEXT to the status line, as far as it has room.
: _SXS-SAY  ( text-a text-u s -- )
    >R
    _SXS-LINE R@ _SXS.STATUS-U @ - MIN 0 MAX
    TUCK R@ _SXS.STATUS R@ _SXS.STATUS-U @ + SWAP MOVE
    R@ _SXS.STATUS-U +!
    0 R> _SXS.SHOWN ! ;

: _SXS-WHY$  ( store-status -- a u )
    CASE
        SBOX-STORE-S-BUSY OF S" it is running" ENDOF
        SBOX-STORE-S-RECOVERY OF S" the store is in recovery" ENDOF
        SBOX-STORE-S-IO OF S" the store could not be written" ENDOF
        SBOX-STORE-S-NOMEM OF S" memory ran out" ENDOF
        >R S" the store refused" R>
    ENDCASE ;

\ Says what became of SUBJECT: "SUBJECT: DONE", or "SUBJECT: not DONE
\ (why)" when the store refused with STATUS.
: _SXS-OUTCOME!  ( subject-a subject-u done-a done-u status s -- )
    DUP _SXS-SAID
    5 PICK 5 PICK 2 PICK _SXS-SAY
    S" : " 2 PICK _SXS-SAY
    OVER IF S" not " 2 PICK _SXS-SAY THEN
    3 PICK 3 PICK 2 PICK _SXS-SAY
    OVER IF
        S"  (" 2 PICK _SXS-SAY
        OVER _SXS-WHY$ 2 PICK _SXS-SAY
        S" )" 2 PICK _SXS-SAY
    THEN
    2DROP 2DROP 2DROP ;

\ =====================================================================
\  The access prompt
\ =====================================================================

: _SXS-ACCESS-KEY  ( index widget -- key ) DROP 1+ ;

: _SXS-ACCESS-FIELD  ( index column widget -- a u )
    2DROP IF S" Allow" ELSE S" Refuse" THEN ;

: _SXS-ACCESS-OPENED  ( index widget -- )
    LST-CONTEXT@ SWAP IF _SXS-C-ALLOW ELSE _SXS-C-REFUSE THEN
    SWAP _SXS.CHOICE ! ;

\ "GRANTEE asks to use MODULE revision N".
: _SXS-QUESTION  ( s -- a u )
    DUP >R _SXS.TEXT 0 _SXS-ASK-MAX R>
    _SXS.ASK @ SBOX-CAPABILITY-ASK@
    >R 2>R _SXS-APPEND
    S"  asks to use " _SXS-APPEND
    2R> _SXS-APPEND
    S"  revision " _SXS-APPEND
    R> NUM>STR _SXS-APPEND
    DROP ;

\ Answers the request the prompt shows, once the user chose, and closes
\ the prompt; a request that no longer waits closes it unanswered.
: _SXS-ACCESS-SERVICE  ( s -- close? )
    DUP _SXS.ASK @ OVER _SXS.ASK-ID @ 2 PICK _SXS.CAP @
        SBOX-CAPABILITY-ASKING? 0= IF DROP -1 EXIT THEN
    DUP _SXS.CHOICE @ ?DUP 0= IF DROP 0 EXIT THEN
    _SXS-C-ALLOW =
    OVER _SXS.ASK @ 2 PICK _SXS.ASK-ID @ 3 PICK _SXS.CAP @
    SBOX-CAPABILITY-ANSWER DROP
    DROP -1 ;

\ =====================================================================
\  The inspector
\ =====================================================================
\ Its rows are the installed modules, in the module table's order, then
\ the grants of the binding's Practice, in the store's order.

: _SXS-OWNER  ( s -- owner|0 ) _SXS.CAP @ SBOX-CAPABILITY-MODULES@ ;
: _SXS-STORE  ( s -- store|0 ) _SXS.CAP @ SBOX-CAPABILITY-STORE@ ;

: _SXS-MODULE-N  ( s -- n )
    _SXS-OWNER ?DUP IF SBOX-MODULE-COUNT@ ELSE 0 THEN ;

\ Whether the store's grant INDEX is for the binding's Practice.
: _SXS-OURS?  ( index s -- flag )
    DUP _SXS.CAP @ SBOX-CAPABILITY-PRACTICE ?DUP 0= IF 2DROP 0 EXIT THEN
    >R _SXS-STORE SBOX-STORE-GRANT@ 2DROP 2DROP
    RID-SIZE R> RID-SIZE COMPARE 0= ;

: _SXS-GRANT-N  ( s -- n )
    DUP _SXS-STORE ?DUP 0= IF DROP 0 EXIT THEN
    0 SWAP SBOX-STORE-GRANT-COUNT@ 0 ?DO
        I 2 PICK _SXS-OURS? IF 1+ THEN
    LOOP
    NIP ;

\ The store's index of the Practice's grant K, or -1.
: _SXS-GRANT-INDEX  ( k s -- index|-1 )
    DUP _SXS-STORE ?DUP 0= IF 2DROP -1 EXIT THEN
    SBOX-STORE-GRANT-COUNT@ 0 ?DO
        I OVER _SXS-OURS? IF
            OVER 0= IF 2DROP I UNLOOP EXIT THEN
            SWAP 1- SWAP
        THEN
    LOOP
    2DROP -1 ;

: _SXS-STATE$  ( module -- a u )
    SBOX-MODULE-STATE@ CASE
        SBOX-MODULE-QUARANTINED OF S" quarantined" ENDOF
        SBOX-MODULE-RETIRED OF S" revoked" ENDOF
        >R S" installed" R>
    ENDCASE ;

: _SXS-MODULE$  ( module s -- a u )
    SWAP >R _SXS.COL0 0 _SXS-LINE R> _SXS-APPEND-MODULE DROP ;

\ "GRANTEE uses MODULE N" for the store's grant INDEX.
: _SXS-GRANT$  ( index s -- a u )
    >R R@ _SXS-STORE SBOX-STORE-GRANT@
    R@ _SXS-OWNER SBOX-MODULE-FIND >R
    ROT DROP
    R> R> _SXS.COL0 0 _SXS-LINE
    5 PICK 5 PICK _SXS-APPEND S"  uses " _SXS-APPEND
    3 PICK _SXS-APPEND-MODULE DROP
    >R >R DROP 2DROP R> R> ;

: _SXS-FNV  ( hash address length -- hash' )
    0 ?DO DUP I + C@ ROT XOR 0x100000001B3 * SWAP LOOP DROP ;

\ A row's key does not move when other rows do: a hash of the module's
\ identity, or of the grant's.
: _SXS-MODULE-KEY  ( module -- key )
    SBOX-MODULE-KEY@ >R 0xCBF29CE484222325 SWAP RID-SIZE _SXS-FNV R> XOR ;

: _SXS-GRANT-KEY  ( index s -- key )
    _SXS-STORE SBOX-STORE-GRANT@
    >R >R 2>R DROP
    0x84222325CBF29CE4 2R> _SXS-FNV
    R> RID-SIZE _SXS-FNV R> XOR ;

: _SXS-INSPECT-KEY  ( index widget -- key )
    LST-CONTEXT@ >R
    DUP R@ _SXS-MODULE-N < IF
        R> _SXS-OWNER SBOX-MODULE-NTH ?DUP IF _SXS-MODULE-KEY ELSE 1 THEN
    ELSE
        R@ _SXS-MODULE-N - R@ _SXS-GRANT-INDEX
        DUP 0< IF DROP R> DROP 1 ELSE R> _SXS-GRANT-KEY THEN
    THEN
    ?DUP 0= IF 1 THEN ;

: _SXS-INSPECT-FIELD  ( index column widget -- a u )
    LST-CONTEXT@ >R
    OVER R@ _SXS-MODULE-N < IF
        SWAP R@ _SXS-OWNER SBOX-MODULE-NTH SWAP
        IF R> DROP _SXS-STATE$ EXIT THEN
        R> _SXS-MODULE$ EXIT
    THEN
    IF R> 2DROP S" granted" EXIT THEN
    R@ _SXS-MODULE-N - R@ _SXS-GRANT-INDEX
    DUP 0< IF R> 2DROP 0 0 EXIT THEN
    R> _SXS-GRANT$ ;

\ Carries out CHOICE on ROW: on a module, revoking or removing it; on a
\ grant, withdrawing it either way.  The subject is written first, since
\ a removed module is gone.
: _SXS-ACT  ( choice row s -- )
    >R
    DUP R@ _SXS-MODULE-N < IF
        R@ _SXS-OWNER SBOX-MODULE-NTH ?DUP 0= IF DROP R> DROP EXIT THEN
        DUP R@ _SXS-MODULE$ 2SWAP
        SWAP _SXS-C-REVOKE = IF
            R@ _SXS-STORE SBOX-STORE-REVOKE S" revoked" ROT
        ELSE
            R@ _SXS-STORE SBOX-STORE-REMOVE S" removed" ROT
        THEN
        R> _SXS-OUTCOME! EXIT
    THEN
    NIP R@ _SXS-MODULE-N - R@ _SXS-GRANT-INDEX
    DUP 0< IF DROP R> DROP EXIT THEN
    DUP R@ _SXS-GRANT$ ROT
    R@ _SXS-STORE SBOX-STORE-GRANT@ R@ _SXS-STORE SBOX-STORE-UNGRANT
    >R S" grant withdrawn" R> R> _SXS-OUTCOME! ;

: _SXS-INSPECT-SERVICE  ( s -- close? )
    DUP _SXS.DONE @ IF DROP -1 EXIT THEN
    DUP _SXS.CHOICE @ ?DUP 0= IF DROP 0 EXIT THEN
    0 2 PICK _SXS.CHOICE !
    OVER _SXS.ROW @ 2 PICK _SXS-ACT
    -1 SWAP _SXS.REFRESH !
    0 ;

\ The status line an inspector opens with.
: _SXS-INSPECT-STATUS  ( s -- )
    DUP _SXS-SAID
    DUP _SXS-STORE ?DUP 0= IF S" no module storage" ROT _SXS-SAY EXIT THEN
    SBOX-STORE-RECOVERY? IF
        S" the store is in recovery: nothing can change" ROT _SXS-SAY EXIT
    THEN
    DROP ;

\ =====================================================================
\  Overlay lifecycle
\ =====================================================================

: _SXS-UIDL  ( -- a u )
    S" <uidl arrange=stack><label id=title/><label id=ask/><region id=rows/><label id=status/><label id=hint/></uidl>" ;

: _SXS-TITLE$  ( s -- a u )
    _SXS-ACCESS? IF S" Module access" ELSE S" Sandbox modules" THEN ;

: _SXS-HINT$  ( s -- a u )
    _SXS-ACCESS? IF
        S" Up/Down choose  Enter answer  Esc refuse"
    ELSE
        S" R revoke or withdraw  D remove  Esc close"
    THEN ;

12 CONSTANT _SXS-STATE-W
CREATE _SXS-ACCESS-COLUMNS LST-COLUMN-SIZE ALLOT
CREATE _SXS-INSPECT-COLUMNS 2 LST-COLUMN-SIZE * ALLOT

: _SXS-COLUMNS-INIT  ( -- )
    _SXS-ACCESS-COLUMNS LST-COLUMN-SIZE 0 FILL
    LST-TEXT-COLUMN _SXS-ACCESS-COLUMNS LST-COLUMN-KIND + !
    _SXS-INSPECT-COLUMNS 2 LST-COLUMN-SIZE * 0 FILL
    LST-TEXT-COLUMN _SXS-INSPECT-COLUMNS LST-COLUMN-KIND + !
    _SXS-INSPECT-COLUMNS LST-COLUMN-SIZE +
        LST-TEXT-COLUMN OVER LST-COLUMN-KIND + !
        _SXS-STATE-W SWAP LST-COLUMN-WIDTH + ! ;

: _SXS-ROW-N  ( s -- n )
    DUP _SXS-ACCESS? IF DROP 2 EXIT THEN
    DUP _SXS-MODULE-N SWAP _SXS-GRANT-N + ;

: _SXS-STYLE-ALL  ( s -- )
    _SXS.STYLE @ ?DUP 0= IF EXIT THEN
    UIDL-ROOT OVER EXECUTE
    UIDL-ROOT ?DUP IF
        UIDL-FIRST-CHILD
        BEGIN ?DUP WHILE 2DUP SWAP EXECUTE UIDL-NEXT-SIB REPEAT
    THEN
    DROP ;

\ Activation runs with the overlay's UIDL context current, before each of
\ its events, ticks and paints.  It keeps the style, the rows, the
\ question and the status line current.
: _SXS-ACTIVATE  ( instance -- )
    CINST-STATE >R
    R@ _SXS-STYLE-ALL
    R@ _SXS.LIST @ ?DUP IF
        R@ _SXS-ROW-N DUP R@ _SXS.ROWS @ <> R@ _SXS.REFRESH @ OR IF
            DUP R@ _SXS.ROWS ! SWAP LST-ROWS!
            0 R@ _SXS.REFRESH !
            R@ _SXS.E-LIST @ ?DUP IF UIDL-DIRTY! THEN
        ELSE
            2DROP
        THEN
    THEN
    \ The question reads the request, so only while it still waits.
    R@ _SXS-ACCESS? R@ _SXS.ASKED @ 0= AND IF
        R@ _SXS.ASK @ R@ _SXS.ASK-ID @ R@ _SXS.CAP @
            SBOX-CAPABILITY-ASKING? IF
            -1 R@ _SXS.ASKED !
            R@ _SXS.E-ASK @ ?DUP IF
                S" text" R@ _SXS-QUESTION UTUI-SET-ATTR
            THEN
        THEN
    THEN
    R@ _SXS.SHOWN @ 0= IF
        -1 R@ _SXS.SHOWN !
        R@ _SXS.E-STATUS @ ?DUP IF
            S" text" R@ _SXS.STATUS R@ _SXS.STATUS-U @ UTUI-SET-ATTR
        THEN
    THEN
    R> DROP ;

: _SXS-INIT  ( instance kind -- )
    SWAP CINST-STATE >R
    R@ _SXS-SIZE 0 FILL
    R@ _SXS.KIND !
    -1 R@ _SXS.SHOWN !
    S" ask" UTUI-BY-ID R@ _SXS.E-ASK !
    S" status" UTUI-BY-ID R@ _SXS.E-STATUS !
    S" title" UTUI-BY-ID ?DUP IF S" text" R@ _SXS-TITLE$ UTUI-SET-ATTR THEN
    S" hint" UTUI-BY-ID ?DUP IF S" text" R@ _SXS-HINT$ UTUI-SET-ATTR THEN
    S" rows" UTUI-BY-ID DUP R@ _SXS.E-LIST ! 0= IF R> DROP EXIT THEN
    R@ _SXS.E-LIST @ UTUI-ELEM-RGN RGN-NEW DUP R@ _SXS.LIST-RGN !
    R@ _SXS-ACCESS? IF
        ['] _SXS-ACCESS-KEY ['] _SXS-ACCESS-FIELD LST-NEW
        DUP R@ _SXS.LIST !
        _SXS-ACCESS-COLUMNS 1 ROT LST-COLUMNS!
        ['] _SXS-ACCESS-OPENED R@ _SXS.LIST @ LST-ON-OPEN
    ELSE
        ['] _SXS-INSPECT-KEY ['] _SXS-INSPECT-FIELD LST-NEW
        DUP R@ _SXS.LIST !
        _SXS-INSPECT-COLUMNS 2 ROT LST-COLUMNS!
    THEN
    R@ R@ _SXS.LIST @ LST-CONTEXT!
    R@ _SXS-ROW-N DUP R@ _SXS.ROWS ! R@ _SXS.LIST @ LST-ROWS!
    R@ _SXS.LIST @ R@ _SXS.E-LIST @ UTUI-WIDGET-SET
    R@ _SXS.E-LIST @ UTUI-FOCUS!
    R> DROP ;

: _SXS-ACCESS-INIT  ( instance -- ) _SXS-K-ACCESS _SXS-INIT ;
: _SXS-INSPECT-INIT  ( instance -- ) _SXS-K-INSPECT _SXS-INIT ;

: _SXS-SHUTDOWN  ( instance -- )
    CINST-STATE >R
    R@ _SXS.E-LIST @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    R@ _SXS.LIST @ ?DUP IF LST-FREE THEN
    R@ _SXS.LIST-RGN @ ?DUP IF RGN-FREE THEN
    R> _SXS-SIZE 0 FILL ;

: _SXS-EV-TYPE  ( ev -- type ) @ ;
: _SXS-EV-CODE  ( ev -- code ) 8 + @ ;
: _SXS-EV-PLAIN?  ( ev -- flag )
    16 + @ KEY-MOD-CTRL KEY-MOD-ALT OR AND 0= ;

\ Esc refuses at an access prompt and closes the inspector.  In the
\ inspector, R revokes the selected module or withdraws the selected
\ grant, and D removes the selected module.  Every other key goes to the
\ list.
: _SXS-EVENT  ( ev instance -- handled? )
    CINST-STATE >R
    DUP _SXS-EV-TYPE KEY-T-SPECIAL = IF
        DUP _SXS-EV-CODE KEY-ESC = IF
            DROP
            R@ _SXS-ACCESS? IF
                _SXS-C-REFUSE R@ _SXS.CHOICE !
            ELSE
                -1 R@ _SXS.DONE !
            THEN
            R> DROP -1 EXIT
        THEN
    THEN
    R@ _SXS-ACCESS? 0= IF
        DUP _SXS-EV-TYPE KEY-T-CHAR = OVER _SXS-EV-PLAIN? AND IF
            DUP _SXS-EV-CODE 32 OR
            DUP [CHAR] r = SWAP [CHAR] d = OR IF
                _SXS-EV-CODE 32 OR [CHAR] r = IF
                    _SXS-C-REVOKE
                ELSE
                    _SXS-C-REMOVE
                THEN
                R@ _SXS.CHOICE !
                R@ _SXS.LIST @ ?DUP IF LST-SELECTED ELSE -1 THEN
                R> _SXS.ROW ! -1 EXIT
            THEN
        THEN
    THEN
    DROP R> DROP 0 ;

\ =====================================================================
\  Descriptors and Desk's interface
\ =====================================================================

CREATE SBXS-ACCESS-DESC APP-DESC ALLOT
CREATE SBXS-INSPECT-DESC APP-DESC ALLOT
CREATE _SXS-ACCESS-COMP COMP-DESC ALLOT
CREATE _SXS-INSPECT-COMP COMP-DESC ALLOT

: _SXS-DESC!  ( init-xt title-a title-u id-a id-u comp desc -- )
    >R
    DUP COMP-DESC-INIT
    TUCK COMP.ID-U ! TUCK COMP.ID-A !
    S" 1.0.0" 2 PICK COMP.VERSION-U ! OVER COMP.VERSION-A !
    _SXS-SIZE OVER COMP.STATE-SIZE !
    R@ APP-DESC-INIT
    R@ APP.COMP-DESC !
    R@ APP.TITLE-U ! R@ APP.TITLE-A !
    R@ APP.INIT-XT !
    ['] _SXS-SHUTDOWN R@ APP.SHUTDOWN-XT !
    ['] _SXS-ACTIVATE R@ APP.ACTIVATE-XT !
    ['] _SXS-EVENT R@ APP.EVENT-XT !
    _SXS-UIDL R@ APP.UIDL-U ! R> APP.UIDL-A ! ;

: _SXS-SETUP  ( -- )
    _SXS-COLUMNS-INIT
    ['] _SXS-ACCESS-INIT S" Module access"
        S" org.akashic.desk.sandbox-access" _SXS-ACCESS-COMP SBXS-ACCESS-DESC
        _SXS-DESC!
    ['] _SXS-INSPECT-INIT S" Sandbox modules"
        S" org.akashic.desk.sandbox-modules" _SXS-INSPECT-COMP
        SBXS-INSPECT-DESC _SXS-DESC! ;

_SXS-SETUP

: SBXS-OVERLAY?  ( desc -- flag )
    DUP SBXS-ACCESS-DESC = SWAP SBXS-INSPECT-DESC = OR ;

\ The centred box an overlay of DESC takes: the title, the question or a
\ page of rows, the status and hint lines, and one spare row.
: SBXS-BOX  ( desc -- row col h w )
    SBXS-ACCESS-DESC = IF 7 ELSE SCR-H 8 - 1 MAX 10 MIN 4 + THEN
    SCR-W 4 - 68 MIN DUP 24 < IF DROP SCR-W 2 - THEN
    OVER SCR-H SWAP - 2 / 0 MAX
    OVER SCR-W SWAP - 2 / 0 MAX
    2SWAP ;

\ Binds a launched access prompt to the request ASK, which the
\ capability CAP knows as ID.  STYLE-XT ( elem -- ) styles each element,
\ or is 0.
: SBXS-ACCESS-BIND  ( ask id cap style-xt instance -- )
    CINST-STATE >R
    R@ _SXS.STYLE ! R@ _SXS.CAP ! R@ _SXS.ASK-ID ! R@ _SXS.ASK !
    0 R> _SXS.ASKED ! ;

\ Binds a launched inspector to the capability CAP.
: SBXS-INSPECT-BIND  ( cap style-xt instance -- )
    CINST-STATE >R
    R@ _SXS.STYLE ! R@ _SXS.CAP !
    -1 R@ _SXS.REFRESH !
    R> _SXS-INSPECT-STATUS ;

\ Carries out what the user chose and says whether Desk should close the
\ overlay.  Desk calls it after the host dispatches each key and on each
\ tick, never from inside the overlay's callbacks.
: SBXS-SERVICE  ( instance -- close? )
    CINST-STATE DUP _SXS-ACCESS? IF _SXS-ACCESS-SERVICE EXIT THEN
    _SXS-INSPECT-SERVICE ;
