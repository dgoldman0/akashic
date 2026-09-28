\ =====================================================================
\  agent.f - Conversation, streaming, tools, and approval applet
\ =====================================================================

PROVIDED akashic-tui-agent

REQUIRE ../../widgets/prompt.f
REQUIRE ../../widgets/dialog.f
REQUIRE widgets/agent-auth.f
REQUIRE widgets/agent-settings.f
REQUIRE ../../app-desc.f
REQUIRE ../../app-shell.f
REQUIRE ../../uidl-tui.f
REQUIRE ../../draw.f
REQUIRE ../../region.f
REQUIRE ../../keys.f
REQUIRE ../../widget.f
REQUIRE ../../widgets/list.f
REQUIRE ../../../text/text-lines.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/endpoint.f
REQUIRE service.f

512 CONSTANT _AG-PROMPT-CAP
0 CONSTANT _AG-PRM-ASK
1 CONSTANT _AG-PRM-AUTH
32 CONSTANT _AG-HEADER-CAP
\ A message's text as the transcript shows it: where it lies, the owned
\ copy that shows it, and the runtime revision both were taken at.
 0 CONSTANT _AGDT-REV
 8 CONSTANT _AGDT-A
16 CONSTANT _AGDT-U
24 CONSTANT _AGDT-COPY
32 CONSTANT _AGDT-SIZE

VARIABLE _AG-PENDING-SOURCE
0 _AG-PENDING-SOURCE !

VARIABLE _AG-CURRENT-STATE
0 _AG-CURRENT-STATE !
VARIABLE _AG-CURRENT-INSTANCE
0 _AG-CURRENT-INSTANCE !
CMP-LAYOUT-BEGIN

_AG-CURRENT-STATE CMP-CELL: _AG-RUNTIME
_AG-CURRENT-STATE CMP-CELL: _AG-PROVIDER
_AG-CURRENT-STATE CMP-CELL: _AG-SOURCE
_AG-CURRENT-STATE CMP-CELL: _AG-OWNS-RUNTIME
_AG-CURRENT-STATE CMP-CELL: _AG-E-BODY
_AG-CURRENT-STATE CMP-CELL: _AG-E-META
_AG-CURRENT-STATE CMP-CELL: _AG-E-SBAR
_AG-CURRENT-STATE CMP-CELL: _AG-E-SOURCE-CLASS
_AG-CURRENT-STATE CMP-CELL: _AG-E-PROVIDER
_AG-CURRENT-STATE CMP-CELL: _AG-E-MODEL
_AG-CURRENT-STATE CMP-CELL: _AG-E-EFFORT
_AG-CURRENT-STATE CMP-CELL: _AG-E-ACCESS
_AG-CURRENT-STATE CMP-CELL: _AG-E-STATE
_AG-CURRENT-STATE 40 CMP-FIELD: _AG-PANEL
_AG-CURRENT-STATE CMP-CELL: _AG-PANEL-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-LIST
_AG-CURRENT-STATE CMP-CELL: _AG-LIST-RGN
_AG-CURRENT-STATE 40 CMP-FIELD: _AG-REVIEW
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-PROMPT
_AG-CURRENT-STATE CMP-CELL: _AG-PROMPT-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-PROMPT-MODE
_AG-CURRENT-STATE _AG-PROMPT-CAP CMP-FIELD: _AG-PROMPT-BUF
_AG-CURRENT-STATE CMP-CELL: _AG-AUTH-PANEL
_AG-CURRENT-STATE CMP-CELL: _AG-AUTH-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-SETTINGS-PANEL
_AG-CURRENT-STATE CMP-CELL: _AG-SETTINGS-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-LAST-REVISION
_AG-CURRENT-STATE CMP-CELL: _AG-COMPACT-STATUS
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-REQUEST-ID
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-GATEWAY-REV
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-RUNTIME-REV
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-BOTTOM-SEEN
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-REDRAW-PENDING
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-TOP     \ rows above the dialog's view
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-ROWS    \ rows at its last drawn width
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-SPAN    \ rows its last draw showed
_AG-CURRENT-STATE _AG-HEADER-CAP CMP-FIELD: _AG-HEADER-BUF
_AG-CURRENT-STATE ACONV-MAX-MESSAGES _AGDT-SIZE * CMP-FIELD: _AG-DISPLAY

CMP-LAYOUT-SIZE CONSTANT _AG-STATE-SIZE

: _AG-ACTIVATE  ( instance -- )
    DUP _AG-CURRENT-INSTANCE !
    CINST-STATE _AG-CURRENT-STATE ! ;

: _AG-NONNEG  ( n -- n' )
    DUP 0< IF DROP 0 THEN ;

: _AG-STATUS-TEXT  ( status -- addr len )
    CASE
        ARUN-S-IDLE OF S" Ready to request" ENDOF
        ARUN-S-RUNNING OF S" Streaming" ENDOF
        ARUN-S-APPROVAL OF S" Review required" ENDOF
        ARUN-S-OFFLINE OF S" Offline" ENDOF
        ARUN-S-ERROR OF S" Error" ENDOF
        ARUN-S-CANCELLED OF S" Cancelled" ENDOF
        ARUN-S-EXPIRED OF S" Expired" ENDOF
        S" Unknown" ROT
    ENDCASE ;

: _AG-STATUS-SHORT  ( status -- addr len )
    CASE
        ARUN-S-IDLE OF S" Ready" ENDOF
        ARUN-S-RUNNING OF S" Stream" ENDOF
        ARUN-S-APPROVAL OF S" Review" ENDOF
        ARUN-S-OFFLINE OF S" Offline" ENDOF
        ARUN-S-ERROR OF S" Error" ENDOF
        ARUN-S-CANCELLED OF S" Cancelled" ENDOF
        ARUN-S-EXPIRED OF S" Expired" ENDOF
        S" Unknown" ROT
    ENDCASE ;

: _AG-SOURCE-CLASS-TEXT  ( provider -- addr len )
    APROV.FLAGS @ APROV-PF-CLASS-MASK AND CASE
        APROV-PF-DEMO OF S" DEMO" ENDOF
        APROV-PF-OFFLINE OF S" OFFLINE" ENDOF
        APROV-PF-REMOTE OF
            _AG-RUNTIME @ ARUNTIME-REMOTE-VERIFIED? IF
                S" REMOTE"
            ELSE
                S" REMOTE?"
            THEN
        ENDOF
        S" CUSTOM" ROT
    ENDCASE ;

VARIABLE _AGL-A
VARIABLE _AGL-U
VARIABLE _AGL-START

\ Provider identifiers remain the canonical identity.  A narrow status row
\ uses only the final component; a wide row retains the complete ID.  This is
\ presentation, never a provenance or policy inference.
: _AG-ID-LEAF  ( addr len -- addr' len' )
    _AGL-U ! _AGL-A ! 0 _AGL-START !
    _AGL-U @ 0 ?DO
        _AGL-A @ I + C@ [CHAR] . = IF I 1+ _AGL-START ! THEN
    LOOP
    _AGL-A @ _AGL-START @ + _AGL-U @ _AGL-START @ - ;

: _AG-COMPACT-NOW?  ( -- flag )
    _AG-E-SBAR @ ?DUP 0= IF -1 EXIT THEN
    UTUI-ELEM-RGN NIP NIP NIP
    DUP 0= SWAP 105 < OR ;

: _AG-AUTH-MISSING?  ( -- flag )
    _AG-RUNTIME @ ARUNTIME.PROVIDER @
    DUP APROV.FEATURES @ APROV-F-AUTH AND 0= IF DROP 0 EXIT THEN
    APROV-AUTH AAUTH-READY? 0= ;

: _AG-DEVICE-AUTH?  ( -- flag )
    _AG-RUNTIME @ ARUNTIME-AUTH DUP 0= IF DROP 0 EXIT THEN
    AAUTH.METHODS @ AAUTH-M-DEVICE AND 0<> ;

: _AG-RUN-SETTINGS-STATE  ( -- state | -1 )
    _AG-RUNTIME @ ARUNTIME-RUN-SETTINGS DUP 0= IF DROP -1 EXIT THEN
    ARSET.STATE @ ;

VARIABLE _AGSE-MODEL
VARIABLE _AGSE-I

: _AG-SELECTED-EFFORT  ( model -- choice | 0 )
    DUP _AGSE-MODEL ! 0= IF 0 EXIT THEN
    0 _AGSE-I !
    BEGIN _AGSE-I @ _AGSE-MODEL @ ARMODEL.EFFORTS-N @ < WHILE
        _AGSE-I @ _AGSE-MODEL @ ARMODEL-EFFORT-NTH
        DUP IF
            DUP ARCH.FLAGS @ ARCH-F-SELECTED AND IF EXIT THEN
        THEN
        DROP 1 _AGSE-I +!
    REPEAT
    0 ;

: _AG-UPDATE-RUN-IDENTITY  ( -- )
    _AG-E-MODEL @ 0= _AG-E-EFFORT @ 0= AND IF EXIT THEN
    _AG-RUNTIME @ ARUNTIME-RUN-SETTINGS DUP 0= IF
        DROP
        _AG-E-MODEL @ ?DUP IF
            S" text" _AG-COMPACT-STATUS @ IF S" default" ELSE S" Provider default" THEN
            UTUI-SET-ATTR
        THEN
        _AG-E-EFFORT @ ?DUP IF
            S" text" _AG-COMPACT-STATUS @ IF S" default" ELSE S" Default effort" THEN
            UTUI-SET-ATTR
        THEN
        EXIT
    THEN
    DUP ARSET.STATE @ ARSET-STATE-READY <> IF
        DROP
        _AG-E-MODEL @ ?DUP IF
            S" text" _AG-COMPACT-STATUS @ IF S" model n/a" ELSE S" Model unavailable" THEN
            UTUI-SET-ATTR
        THEN
        _AG-E-EFFORT @ ?DUP IF
            S" text" _AG-COMPACT-STATUS @ IF S" effort n/a" ELSE S" Effort unavailable" THEN
            UTUI-SET-ATTR
        THEN
        EXIT
    THEN
    ARSET-SELECTED-MODEL DUP 0= IF
        DROP
        _AG-E-MODEL @ ?DUP IF S" text" S" No model" UTUI-SET-ATTR THEN
        _AG-E-EFFORT @ ?DUP IF
            S" text" _AG-COMPACT-STATUS @ IF S" default" ELSE S" Default effort" THEN
            UTUI-SET-ATTR
        THEN
        EXIT
    THEN
    >R
    _AG-E-MODEL @ ?DUP IF
        S" text" _AG-COMPACT-STATUS @ IF
            R@ ARMODEL-ID DUP 0= IF 2DROP R@ ARMODEL-LABEL THEN
        ELSE
            R@ ARMODEL-LABEL DUP 0= IF 2DROP R@ ARMODEL-ID THEN
        THEN
        UTUI-SET-ATTR
    THEN
    _AG-E-EFFORT @ ?DUP IF
        S" text" R@ _AG-SELECTED-EFFORT DUP IF
            _AG-COMPACT-STATUS @ IF
                DUP ARCH-ID DUP 0= IF 2DROP ARCH-LABEL ELSE ROT DROP THEN
            ELSE
                ARCH-LABEL
            THEN
        ELSE
            DROP _AG-COMPACT-STATUS @ IF S" default" ELSE S" Default effort" THEN
        THEN
        UTUI-SET-ATTR
    THEN
    R> DROP ;

: _AG-UPDATE-ACCESS  ( -- )
    _AG-E-ACCESS @ ?DUP IF
        S" text" _AG-RUNTIME @ ARUNTIME-SCOPE-AVAILABLE? 0= IF
            _AG-COMPACT-STATUS @ IF
                S" Unscoped"
            ELSE
                S" Unscoped; Scope unavailable"
            THEN
        ELSE
            _AG-COMPACT-STATUS @ IF
                _AG-RUNTIME @ ARUNTIME-ACCESS-PROFILE ?DUP IF
                    AAP.PRESET @ CASE
                        AAP-PRESET-CHAT-ONLY OF S" Chat" ENDOF
                        AAP-PRESET-PRACTICE-READ OF S" Read" ENDOF
                        AAP-PRESET-PRACTICE-ASSIST OF S" Assist" ENDOF
                        AAP-PRESET-PRACTICE-LIBRARY-BURROW OF S" Burrow" ENDOF
                        S" Scoped" ROT
                    ENDCASE
                ELSE
                    S" Unscoped"
                THEN
            ELSE
                _AG-RUNTIME @ ARUNTIME-ACCESS-SCOPE$
            THEN
        THEN
        DUP 0= IF 2DROP S" Access unavailable" THEN
        UTUI-SET-ATTR
    THEN ;

: _AG-UPDATE-STATUS  ( -- )
    _AG-E-SOURCE-CLASS @ ?DUP IF
        S" text" _AG-RUNTIME @ ARUNTIME.PROVIDER @ _AG-SOURCE-CLASS-TEXT
        UTUI-SET-ATTR
    THEN
    _AG-E-PROVIDER @ ?DUP IF
        S" text" _AG-RUNTIME @ ARUNTIME.PROVIDER @
        DUP APROV.ID-A @ SWAP APROV.ID-U @
        _AG-COMPACT-STATUS @ IF _AG-ID-LEAF THEN UTUI-SET-ATTR
    THEN
    _AG-UPDATE-RUN-IDENTITY
    _AG-UPDATE-ACCESS
    _AG-E-STATE @ ?DUP IF
        S" text" _AG-AUTH-MISSING? IF
            _AG-DEVICE-AUTH? IF
                _AG-COMPACT-STATUS @ IF S" Sign in" ELSE S" Sign-in required" THEN
            ELSE
                _AG-COMPACT-STATUS @ IF S" Credential" ELSE S" Credential required" THEN
            THEN
        ELSE
            _AG-RUN-SETTINGS-STATE DUP ARSET-STATE-LOADING = IF
                DROP _AG-COMPACT-STATUS @ IF S" Models..." ELSE S" Loading models" THEN
            ELSE DUP ARSET-STATE-ERROR = IF
                DROP _AG-COMPACT-STATUS @ IF S" Model error" ELSE S" Model catalog error" THEN
            ELSE DROP _AG-RUNTIME @ ARUNTIME.STORE-STATUS @ ACSTORE-S-OK <> IF
                _AG-COMPACT-STATUS @ IF S" No history" ELSE S" History unavailable" THEN
            ELSE
                _AG-RUNTIME @ ARUNTIME.STATUS @
                _AG-COMPACT-STATUS @ IF _AG-STATUS-SHORT ELSE _AG-STATUS-TEXT THEN
            THEN THEN THEN
        THEN
        UTUI-SET-ATTR
    THEN ;

: _AG-INVALIDATE  ( -- )
    _AG-PANEL WDG-DIRTY
    _AG-E-BODY @ ?DUP IF UIDL-DIRTY! THEN
    _AG-E-META @ ?DUP IF UIDL-DIRTY! THEN
    _AG-E-SBAR @ ?DUP IF UIDL-DIRTY! THEN
    _AG-UPDATE-STATUS
    ASHELL-DIRTY! ;

: _AG-SYNC-STATUS-MODE  ( -- )
    _AG-COMPACT-NOW? DUP _AG-COMPACT-STATUS @ = IF DROP EXIT THEN
    _AG-COMPACT-STATUS !
    _AG-E-META @ ?DUP IF UIDL-DIRTY! THEN
    _AG-E-SBAR @ ?DUP IF UIDL-DIRTY! THEN
    _AG-UPDATE-STATUS ASHELL-DIRTY! ;

: _AG-HIDE-OVERLAYS  ( -- )
    _AG-AUTH-PANEL @ ?DUP IF WDG-HIDE THEN
    _AG-SETTINGS-PANEL @ ?DUP IF WDG-HIDE THEN ;

: _AG-SHOW-ACCOUNT  ( -- )
    _AG-RUNTIME @ ARUNTIME-AUTH 0= IF
        S" This provider has no account interface" 1800 ASHELL-TOAST EXIT
    THEN
    _AG-PROMPT @ ?DUP IF PRM-HIDE THEN
    _AG-SETTINGS-PANEL @ ?DUP IF WDG-HIDE THEN
    _AG-AUTH-PANEL @ ?DUP IF AAUTHP-SHOW THEN
    _AG-INVALIDATE ;

: _AG-SHOW-SETTINGS  ( -- )
    _AG-RUNTIME @ ARUNTIME-RUN-SETTINGS 0= IF
        S" This provider has no run settings" 1800 ASHELL-TOAST EXIT
    THEN
    _AG-PROMPT @ ?DUP IF PRM-HIDE THEN
    _AG-AUTH-PANEL @ ?DUP IF WDG-HIDE THEN
    _AG-SETTINGS-PANEL @ ?DUP IF ARSP-SHOW THEN
    _AG-INVALIDATE ;

: _AG-SHOW-PROMPT  ( -- )
    _AG-PROMPT @ 0= IF EXIT THEN
    _AG-AUTH-MISSING? IF
        _AG-DEVICE-AUTH? IF _AG-SHOW-ACCOUNT EXIT THEN
    THEN
    _AG-RUN-SETTINGS-STATE DUP -1 <> SWAP ARSET-STATE-READY <> AND IF
        _AG-SHOW-SETTINGS EXIT
    THEN
    _AG-HIDE-OVERLAYS
    _AG-PRM-ASK _AG-PROMPT-MODE !
    0 _AG-PROMPT @ PRM-MASK!
    S" Ask:" 0 0 _AG-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _AG-SHOW-AUTH-PROMPT  ( -- )
    _AG-PROMPT @ 0= IF EXIT THEN
    _AG-RUNTIME @ ARUNTIME.PROVIDER @ APROV.FEATURES @
    APROV-F-AUTH AND 0= IF
        S" This provider uses no credential" 1600 ASHELL-TOAST EXIT
    THEN
    _AG-RUNTIME @ ARUNTIME-BUSY? IF
        S" Finish or cancel the active run first" 1800 ASHELL-TOAST EXIT
    THEN
    _AG-HIDE-OVERLAYS
    _AG-PROMPT @ PRM-WIPE
    42 _AG-PROMPT @ PRM-MASK!
    _AG-PRM-AUTH _AG-PROMPT-MODE !
    S" Credential:" 0 0 _AG-PROMPT @ PRM-SHOW
    ASHELL-DIRTY! ;

: _AG-AUTH-SET-TOAST  ( status -- )
    CASE
        AAUTH-S-OK OF S" Credential set" 1200 ENDOF
        AAUTH-S-UNSUPPORTED OF S" Provider does not accept a credential" 1800 ENDOF
        AAUTH-S-CAPACITY OF S" Credential is too long" 1800 ENDOF
        AAUTH-S-BUSY OF S" Finish or cancel the active run first" 1800 ENDOF
        DROP S" Credential was rejected" 1800 0
    ENDCASE
    ASHELL-TOAST ;

VARIABLE _AG-AUTH-STATUS

: _AG-SEND-STATUS-TOAST  ( status -- )
    CASE
        1 OF S" Request scope or input was rejected" 2200 ENDOF
        2 OF S" Another run or review is active" 2000 ENDOF
        3 OF S" Conversation context is full; clear it before sending" 2600 ENDOF
        4 OF S" Model settings are not ready" 2000 ENDOF
        DROP
        _AG-RUNTIME @ ARUNTIME.STATUS @ ARUN-S-OFFLINE = IF
            S" Agent is offline" 1800
        ELSE
            S" Request could not be started" 2200
        THEN
        0
    ENDCASE
    ASHELL-TOAST ;

: _AG-PROMPT-SUBMIT  ( prompt -- )
    _AG-PROMPT-MODE @ _AG-PRM-AUTH = IF
        DUP PRM-GET-TEXT _AG-RUNTIME @ ARUNTIME-AUTH-SET
        DUP _AG-AUTH-STATUS ! _AG-AUTH-SET-TOAST
        DUP PRM-WIPE
        0 SWAP PRM-MASK!
        _AG-PRM-ASK _AG-PROMPT-MODE !
        _AG-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
        _AG-INVALIDATE EXIT
    THEN
    PRM-GET-TEXT DUP 0= IF
        2DROP S" Message is empty" 1400 ASHELL-TOAST
    ELSE
        _AG-RUNTIME @ ARUNTIME-SEND DUP IF
            _AG-SEND-STATUS-TOAST
        ELSE
            DROP
        THEN
    THEN
    _AG-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _AG-LIST @ ?DUP IF LST-SCROLL-END THEN _AG-INVALIDATE ;

: _AG-PROMPT-CANCEL  ( prompt -- )
    DUP PRM-WIPE
    0 SWAP PRM-MASK!
    _AG-PRM-ASK _AG-PROMPT-MODE !
    _AG-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _AG-INVALIDATE ;

: _AG-ROLE-TEXT  ( role -- addr len )
    CASE
        AROLE-USER OF S" YOU" ENDOF
        AROLE-ASSISTANT OF S" AGENT" ENDOF
        AROLE-TOOL OF S" TOOL" ENDOF
        AROLE-SYSTEM OF S" SYSTEM" ENDOF
        S" MESSAGE" ROT
    ENDCASE ;

\ =====================================================================
\  Transcript
\ =====================================================================
\
\  The transcript is a canonical card list in log mode (list.f): one card
\  per message, its header on the first line and its text below, broken
\  into lines by the shared line rule (text-lines.f).  A rich terminal
\  receives the same cards as an item view and lays them out itself.  The
\  list follows the end while its view shows it.  Messages come from
\  outside the application, so the list is untrusted: explicit direction
\  controls stay inert.

2 CONSTANT _AG-CARD-FIELDS
CREATE _AG-CARD-COLUMNS  LST-COLUMN-SIZE _AG-CARD-FIELDS * ALLOT

: _AG-CARD-COLUMNS-INIT  ( -- )
    _AG-CARD-COLUMNS LST-COLUMN-SIZE _AG-CARD-FIELDS * 0 FILL
    LST-TEXT-COLUMN _AG-CARD-COLUMNS LST-COLUMN-KIND + !
    LST-TEXT-COLUMN _AG-CARD-COLUMNS LST-COLUMN-SIZE + LST-COLUMN-KIND + !
    LST-COLUMN-WRAP _AG-CARD-COLUMNS LST-COLUMN-SIZE + LST-COLUMN-FLAGS + ! ;

: _AG-CONV  ( -- conversation )  _AG-RUNTIME @ ARUNTIME.CONVERSATION @ ;

\ A message's state as its header shows it, or nothing.
: _AG-STATE-LABEL  ( state -- addr len )
    CASE
        AMSG-S-STREAMING OF S" ..." ENDOF
        AMSG-S-APPROVAL OF S" REVIEW" ENDOF
        AMSG-S-ERROR OF S" ERROR" ENDOF
        AMSG-S-CANCELLED OF S" CANCELLED" ENDOF
        0 0 ROT
    ENDCASE ;

: _AG-STATE-MEANING  ( state -- meaning )
    CASE
        AMSG-S-APPROVAL OF TSTY-STRONG ENDOF
        AMSG-S-ERROR OF TSTY-ERROR ENDOF
        TSTY-COMMENT SWAP
    ENDCASE ;

VARIABLE _AGHD-N

: _AGHD+  ( addr len -- )
    DUP _AGHD-N @ + _AG-HEADER-CAP > IF 2DROP EXIT THEN
    _AG-HEADER-BUF _AGHD-N @ + SWAP DUP _AGHD-N +! MOVE ;

\ A card's header: its message's role, and its state when it has one.
: _AG-HEADER  ( message -- addr len )
    0 _AGHD-N !
    DUP AMSG.ROLE @ _AG-ROLE-TEXT _AGHD+
    AMSG.STATE @ _AG-STATE-LABEL DUP IF
        2>R S"   " _AGHD+ 2R> _AGHD+
    ELSE
        2DROP
    THEN
    _AG-HEADER-BUF _AGHD-N @ ;

\ A message's text as the transcript shows it: CR LF and a lone CR break
\ lines as LF does.  Text without CR is shown where it lies; other text is
\ shown from a copy, kept while the runtime's revision stays the same,
\ since every change to the conversation moves that revision.  A cleared
\ entry holds revision 0, which no runtime has: they start at 1.
: _AG-DT  ( index -- entry )  _AGDT-SIZE * _AG-DISPLAY + ;

: _AG-DT-RELEASE  ( entry -- )
    DUP _AGDT-COPY + @ ?DUP IF FREE THEN
    _AGDT-SIZE 0 FILL ;

: _AG-DISPLAY-RELEASE  ( -- )
    ACONV-MAX-MESSAGES 0 DO I _AG-DT _AG-DT-RELEASE LOOP ;

VARIABLE _AGDT-E
VARIABLE _AGDT-SA
VARIABLE _AGDT-SU
VARIABLE _AGDT-D

: _AG-HAS-CR?  ( addr len -- flag )
    OVER + SWAP ?DO I C@ 13 = IF UNLOOP -1 EXIT THEN LOOP 0 ;

\ Copy text to DST with each CR LF and each lone CR as one LF; the copy's
\ length.
: _AG-LF-COPY  ( src len dst -- len' )
    _AGDT-D ! _AGDT-SU ! _AGDT-SA !
    0 _AGDT-SU @ 0 ?DO                              ( n )
        _AGDT-SA @ I + C@ DUP 13 = IF
            DROP
            I 1+ _AGDT-SU @ < IF _AGDT-SA @ I + 1+ C@ 10 = ELSE 0 THEN
            0= IF 10 OVER _AGDT-D @ + C! 1+ THEN
        ELSE
            OVER _AGDT-D @ + C! 1+
        THEN
    LOOP ;

: _AG-DISPLAY-TEXT  ( message index -- addr len )
    _AG-DT _AGDT-E !
    _AGDT-E @ _AGDT-REV + @ _AG-RUNTIME @ ARUNTIME.REVISION @ = IF
        DROP _AGDT-E @ _AGDT-A + @ _AGDT-E @ _AGDT-U + @ EXIT
    THEN
    _AGDT-E @ _AG-DT-RELEASE
    AMSG-TEXT 2DUP _AG-HAS-CR? IF
        \ Without memory for the copy, a CR shows as U+FFFD.
        DUP ALLOCATE 0= IF
            DUP _AGDT-E @ _AGDT-COPY + !
            >R R@ _AG-LF-COPY R> SWAP
        ELSE
            DROP
        THEN
    THEN
    _AGDT-E @ _AGDT-U + ! _AGDT-E @ _AGDT-A + !
    _AG-RUNTIME @ ARUNTIME.REVISION @ _AGDT-E @ _AGDT-REV + !
    _AGDT-E @ _AGDT-A + @ _AGDT-E @ _AGDT-U + @ ;

\ The list calls these for whichever Agent owns it, so each one first
\ makes that instance current.  Cards are keyed by their message's place,
\ which a conversation only appends to, drops from its end, or clears.
: _AG-CARD-KEY  ( row list -- key )  DROP 1+ ;

: _AG-CARD-FIELD  ( row column list -- addr len )
    LST-CONTEXT@ _AG-ACTIVATE
    SWAP DUP _AG-CONV ACONV-NTH ?DUP 0= IF 2DROP 0 0 EXIT THEN
    ROT IF SWAP _AG-DISPLAY-TEXT ELSE NIP _AG-HEADER THEN ;

VARIABLE _AGCS-MSG
VARIABLE _AGCS-MAP
VARIABLE _AGCS-U
VARIABLE _AGCS-ROLE-U

\ The header's role reads as a heading and its state as what it says; the
\ text is plain.
: _AG-CARD-STYLE  ( text-a text-u map row column list -- styled? )
    LST-CONTEXT@ _AG-ACTIVATE
    IF 2DROP 2DROP 0 EXIT THEN
    _AG-CONV ACONV-NTH _AGCS-MSG ! _AGCS-MAP ! NIP _AGCS-U !
    _AGCS-MSG @ 0= IF 0 EXIT THEN
    _AGCS-MAP @ _AGCS-U @ 0 FILL
    _AGCS-MSG @ AMSG.ROLE @ _AG-ROLE-TEXT NIP _AGCS-U @ MIN DUP _AGCS-ROLE-U !
        _AGCS-MAP @ SWAP TSTY-HEADING FILL
    _AGCS-MSG @ AMSG.STATE @ _AG-STATE-LABEL NIP
    _AGCS-U @ _AGCS-ROLE-U @ 2 + - MIN DUP 0> IF
        _AGCS-MAP @ _AGCS-ROLE-U @ 2 + + SWAP
        _AGCS-MSG @ AMSG.STATE @ _AG-STATE-MEANING FILL
    ELSE
        DROP
    THEN
    -1 ;

: _AG-LIST-NEW  ( rgn -- list )
    ['] _AG-CARD-KEY ['] _AG-CARD-FIELD LST-NEW
    _AG-CURRENT-INSTANCE @ OVER LST-CONTEXT!
    _AG-CARD-COLUMNS _AG-CARD-FIELDS 2 PICK LST-COLUMNS!
    LST-CARDS LST-UNTRUSTED OR LST-LOG OR OVER LST-MODE!
    ['] _AG-CARD-STYLE OVER LST-STYLE! ;

ATOOLG-ARGS-REVIEW-MAX CONSTANT _AG-REVIEW-JSON-CAP
_AG-REVIEW-JSON-CAP 4 * CONSTANT _AG-REVIEW-VISIBLE-CAP
_AG-REVIEW-JSON-CAP _AG-REVIEW-VISIBLE-CAP +
    SHA3-256-HEX-LEN + CONSTANT _AG-REVIEW-STORAGE-CAP

_AG-REVIEW-STORAGE-CAP XBUF _AG-REVIEW-STORAGE
: _AG-REVIEW-JSON     ( -- addr ) _AG-REVIEW-STORAGE ;
: _AG-REVIEW-VISIBLE  ( -- addr )
    _AG-REVIEW-STORAGE _AG-REVIEW-JSON-CAP + ;
: _AG-REVIEW-DIGEST   ( -- addr )
    _AG-REVIEW-VISIBLE _AG-REVIEW-VISIBLE-CAP + ;

0 CONSTANT _AG-INPUT-READY
1 CONSTANT _AG-INPUT-OMITTED
2 CONSTANT _AG-INPUT-INVALID

VARIABLE _AGAC-G
VARIABLE _AGFP-A
VARIABLE _AGFP-U
VARIABLE _AGFP-N

: _AG-ARGS-CANONICAL  ( gateway -- addr len flag )
    DUP 0= IF DROP 0 0 0 EXIT THEN
    _AGAC-G !
    _AG-REVIEW-JSON _AG-REVIEW-JSON-CAP _AGAC-G @
        ATOOLG-ARGS-CANONICAL
    DUP IF 2DROP 0 0 0 EXIT THEN
    DROP _AG-REVIEW-JSON SWAP -1 ;

: _AG-FINGERPRINT-LOAD  ( gateway -- flag )
    ATOOLG-ARGS-FINGERPRINT
    _AGFP-N ! _AGFP-U ! _AGFP-A !
    _AGFP-A @ 0<> _AGFP-U @ SHA3-256-LEN = AND ;

: _AG-FINGERPRINT-HEX  ( -- addr len )
    _AGFP-A @ _AG-REVIEW-DIGEST SHA3-256->HEX
    _AG-REVIEW-DIGEST SWAP ;

VARIABLE _AGVE-A
VARIABLE _AGVE-U
VARIABLE _AGVE-N
VARIABLE _AGVE-B

: _AGVE-HEX  ( nibble -- char )
    15 AND DUP 10 < IF 48 + ELSE 55 + THEN ;

: _AGVE-EMIT  ( char -- )
    _AG-REVIEW-VISIBLE _AGVE-N @ + C!
    1 _AGVE-N +! ;

\ The canonical JSON is compact and already quotes/escapes JSON controls.
\ For review, make every remaining nonprinting byte visible as \xHH.  Space
\ and every non-ASCII UTF-8 byte are included, so the operand is injective,
\ cannot contain a real line break or bidi control, and remains ASCII-only.
: _AG-JSON-VISIBLE  ( addr len -- addr' len' )
    _AGVE-U ! _AGVE-A ! 0 _AGVE-N !
    _AGVE-U @ 0 ?DO
        _AGVE-A @ I + C@ DUP 33 >= OVER 126 <= AND IF
            _AGVE-EMIT
        ELSE
            _AGVE-B !
            92 _AGVE-EMIT [CHAR] x _AGVE-EMIT
            _AGVE-B @ 4 RSHIFT _AGVE-HEX _AGVE-EMIT
            _AGVE-B @ _AGVE-HEX _AGVE-EMIT
        THEN
    LOOP
    _AG-REVIEW-VISIBLE _AGVE-N @ ;

: _AG-ARGS-DISPLAY  ( gateway -- addr len flag )
    _AG-ARGS-CANONICAL IF
        _AG-JSON-VISIBLE -1
    ELSE
        2DROP 0 0 0
    THEN ;

: _AG-INPUT-MODE  ( gateway -- mode )
    DUP _AG-FINGERPRINT-LOAD 0= IF DROP _AG-INPUT-INVALID EXIT THEN
    DUP ATOOLG-ARGS-FINGERPRINT-MATCH? 0= IF
        DROP _AG-INPUT-INVALID EXIT
    THEN
    _AG-ARGS-CANONICAL IF
        2DROP _AG-INPUT-READY
    ELSE
        2DROP _AG-INPUT-OMITTED
    THEN ;

: _AG-INPUT-REVIEWABLE?  ( gateway -- flag )
    _AG-INPUT-MODE _AG-INPUT-READY = ;

: _AG-REVIEW-REQUEST  ( -- request | 0 )
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ ?DUP IF
        DUP ATOOLG.STATE @ ATOOLG-S-APPROVAL = IF
            ATOOLG.REQUEST @
        ELSE
            DROP 0
        THEN
    ELSE
        0
    THEN ;

: _AG-REVIEW-IDENTITY  ( -- request-or-message | 0 )
    _AG-REVIEW-REQUEST ?DUP IF EXIT THEN
    _AG-RUNTIME @ ARUNTIME.STATUS @ ARUN-S-APPROVAL <> IF 0 EXIT THEN
    _AG-RUNTIME @ ARUNTIME.APPROVAL-MSG @ ;

VARIABLE _AGSR-REQ
VARIABLE _AGSR-GREV
VARIABLE _AGSR-RREV

: _AG-REVIEW-TRACKING-CLEAR  ( -- )
    0 _AG-REVIEW-REQUEST-ID !
    0 _AG-REVIEW-GATEWAY-REV !
    0 _AG-REVIEW-RUNTIME-REV !
    0 _AG-REVIEW-BOTTOM-SEEN !
    0 _AG-REVIEW-REDRAW-PENDING !
    0 _AG-REVIEW-TOP ! ;

\ _AG-REVIEW-CURRENT? ( -- flag )
\   Is the tracked review the one pending now, at the same gateway and
\   runtime revisions?  Leaves those in _AGSR-REQ, -GREV and -RREV.
: _AG-REVIEW-CURRENT?  ( -- flag )
    _AG-REVIEW-IDENTITY _AGSR-REQ !
    _AG-REVIEW-REQUEST IF
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ ATOOLG.REVISION @
    ELSE
        0
    THEN _AGSR-GREV !
    _AG-RUNTIME @ ARUNTIME.REVISION @ _AGSR-RREV !
    _AGSR-REQ @ 0<>
    _AGSR-REQ @ _AG-REVIEW-REQUEST-ID @ = AND
    _AGSR-GREV @ _AG-REVIEW-GATEWAY-REV @ = AND
    _AGSR-RREV @ _AG-REVIEW-RUNTIME-REV @ = AND ;

\ Every new or changed review opens at the top of its dialog, locked.  A
\ resolved review lets the transcript show its end, where the result
\ appears; an ordinary transcript keeps where the user scrolled it.
: _AG-SYNC-REVIEW  ( -- )
    _AG-REVIEW-IDENTITY 0= IF
        _AG-REVIEW-REQUEST-ID @ IF
            _AG-LIST @ ?DUP IF LST-SCROLL-END THEN
        THEN
        _AG-REVIEW-TRACKING-CLEAR EXIT
    THEN
    _AG-REVIEW-CURRENT? IF EXIT THEN
    _AGSR-REQ @ _AG-REVIEW-REQUEST-ID !
    _AGSR-GREV @ _AG-REVIEW-GATEWAY-REV !
    _AGSR-RREV @ _AG-REVIEW-RUNTIME-REV !
    0 _AG-REVIEW-BOTTOM-SEEN !
    0 _AG-REVIEW-REDRAW-PENDING !
    0 _AG-REVIEW-TOP !
    _AG-INVALIDATE ;

: _AG-REVIEW-INSPECTED?  ( -- flag )
    _AG-REVIEW-BOTTOM-SEEN @ 0<> _AG-REVIEW-CURRENT? AND ;

: _AG-REVIEW-APPROVABLE?  ( -- flag )
    _AG-REVIEW-REQUEST IF
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ DUP 0= IF DROP 0 EXIT THEN
        _AG-INPUT-REVIEWABLE? _AG-REVIEW-INSPECTED? AND
    ELSE
        _AG-REVIEW-IDENTITY 0<> _AG-REVIEW-INSPECTED? AND
    THEN ;

: _AG-FLUSH-REVIEW-REDRAW  ( -- )
    _AG-REVIEW-REDRAW-PENDING @ 0= IF EXIT THEN
    0 _AG-REVIEW-REDRAW-PENDING ! _AG-INVALIDATE ;

: _AG-REVIEW-OPEN?  ( -- flag )
    _AG-RUNTIME @ 0= IF 0 EXIT THEN
    _AG-REVIEW-IDENTITY 0<> ;

\ An account or run-settings panel the user opened covers the body.
: _AG-USER-OVERLAY?  ( -- flag )
    _AG-AUTH-PANEL @ ?DUP IF AAUTHP-ACTIVE? IF -1 EXIT THEN THEN
    _AG-SETTINGS-PANEL @ ?DUP IF ARSP-ACTIVE? IF -1 EXIT THEN THEN
    0 ;

: _AG-CAP-LABEL  ( cap -- addr len )
    DUP CAP.TITLE-U @ IF
        DUP CAP.TITLE-A @ SWAP CAP.TITLE-U @
    ELSE
        CAP-ID
    THEN ;

\ =====================================================================
\  Review dialog
\ =====================================================================
\
\  A pending review opens a dialog over the transcript.  It shows the
\  message that asked for the review, then every detail of the request,
\  each paragraph broken into lines at the dialog's width by the shared
\  line rule, and scrolls by rows.  One walk over the paragraphs both
\  counts the rows and draws them, so the two always agree.  Approve (F6)
\  unlocks only after a drawn frame has shown the last row; Deny (F7)
\  never locks.  Exact values (identifiers, numbers, the digest, and the
\  operand) show every byte: a space as a middle dot.

\ Looks.
0 CONSTANT _AGRV-TEXT
1 CONSTANT _AGRV-LABEL
2 CONSTANT _AGRV-VALUE      \ exact
3 CONSTANT _AGRV-OPERAND    \ exact
4 CONSTANT _AGRV-FAULT
5 CONSTANT _AGRV-HEAD

: _AGRV-EXACT?  ( look -- flag )
    DUP _AGRV-VALUE = SWAP _AGRV-OPERAND = OR ;

: _AGRV-LOOK!  ( look -- )
    CASE
        _AGRV-LABEL OF 220 234 1 DRW-STYLE! ENDOF
        _AGRV-OPERAND OF 117 234 0 DRW-STYLE! ENDOF
        _AGRV-FAULT OF 203 234 1 DRW-STYLE! ENDOF
        _AGRV-HEAD OF 81 234 1 DRW-STYLE! ENDOF
        253 234 0 DRW-STYLE!
    ENDCASE ;

VARIABLE _AGRV-XT       \ the walk's visitor ( addr len look -- )
VARIABLE _AGRV-REQ
VARIABLE _AGRV-CAP
VARIABLE _AGRV-G

: _AGRV-P  ( addr len look -- )  _AGRV-XT @ EXECUTE ;

\ The message that asked for the review: the conversation's last, while
\ it waits for approval.
: _AG-REVIEW-MESSAGE  ( -- index | -1 )
    _AG-CONV ACONV.COUNT @ 1- DUP 0< IF EXIT THEN
    DUP _AG-CONV ACONV-NTH AMSG.STATE @ AMSG-S-APPROVAL <> IF DROP -1 THEN ;

: _AGRV-MESSAGE  ( -- )
    _AG-REVIEW-MESSAGE DUP 0< IF DROP EXIT THEN
    DUP _AG-CONV ACONV-NTH DUP _AG-HEADER _AGRV-HEAD _AGRV-P
    SWAP _AG-DISPLAY-TEXT _AGRV-TEXT _AGRV-P ;

: _AGRV-INPUT  ( gateway -- )
    DUP _AGRV-G ! _AG-FINGERPRINT-LOAD 0= IF
        S" Operand fingerprint unavailable; approval disabled"
            _AGRV-FAULT _AGRV-P EXIT
    THEN
    S" Canonical bytes:" _AGRV-LABEL _AGRV-P
    _AGFP-N @ NUM>STR _AGRV-VALUE _AGRV-P
    S" SHA3-256:" _AGRV-LABEL _AGRV-P
    _AG-FINGERPRINT-HEX _AGRV-VALUE _AGRV-P
    S" Operand (canonical JSON bytes):" _AGRV-LABEL _AGRV-P
    S" Spaces/non-ASCII use \xHH" _AGRV-LABEL _AGRV-P
    _AGRV-G @ _AG-INPUT-MODE CASE
        _AG-INPUT-READY OF
            _AGRV-G @ _AG-ARGS-DISPLAY IF
                _AGRV-OPERAND _AGRV-P
            ELSE
                2DROP S" Operand encoding changed; approval disabled"
                    _AGRV-FAULT _AGRV-P
            THEN
        ENDOF
        _AG-INPUT-OMITTED OF
            S" Operand exceeds the exact display limit; approval disabled"
                _AGRV-FAULT _AGRV-P
        ENDOF
        _AG-INPUT-INVALID OF
            S" Operand integrity check failed; approval disabled"
                _AGRV-FAULT _AGRV-P
        ENDOF
    ENDCASE ;

: _AGRV-LOCAL  ( request -- )
    DUP _AGRV-REQ ! CBR.CAP @ _AGRV-CAP !
    S" Capability:" _AGRV-LABEL _AGRV-P
    _AGRV-CAP @ _AG-CAP-LABEL _AGRV-TEXT _AGRV-P
    S" Operation:" _AGRV-LABEL _AGRV-P
    _AGRV-CAP @ CAP-ID _AGRV-VALUE _AGRV-P
    S" Target instance:" _AGRV-LABEL _AGRV-P
    _AGRV-REQ @ CBR.TARGET-ID @ NUM>STR _AGRV-VALUE _AGRV-P
    S" Expected revision:" _AGRV-LABEL _AGRV-P
    _AGRV-REQ @ CBR.EXPECT-REV @ NUM>STR _AGRV-VALUE _AGRV-P
    S" Effects:" _AGRV-LABEL _AGRV-P
    _AGRV-CAP @ CAP.EFFECTS @
    DUP CAP-E-OBSERVE AND IF S" observe" _AGRV-TEXT _AGRV-P THEN
    DUP CAP-E-NAVIGATE AND IF S" navigate" _AGRV-TEXT _AGRV-P THEN
    DUP CAP-E-MUTATE AND IF S" mutate" _AGRV-TEXT _AGRV-P THEN
    DUP CAP-E-PERSIST AND IF S" persist" _AGRV-TEXT _AGRV-P THEN
    DUP CAP-E-DESTRUCTIVE AND IF S" destructive" _AGRV-TEXT _AGRV-P THEN
    CAP-E-EXTERNAL AND IF S" external" _AGRV-TEXT _AGRV-P THEN
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ _AGRV-INPUT ;

\ _AGRV-EACH ( xt -- )   Call XT ( addr len look -- ) for each paragraph.
: _AGRV-EACH  ( xt -- )
    _AGRV-XT !
    _AGRV-MESSAGE
    _AG-REVIEW-REQUEST ?DUP IF
        _AGRV-LOCAL
    ELSE
        S" Provider approval request (no local tool envelope)"
            _AGRV-LABEL _AGRV-P
    THEN ;

\ Exact values show a space as U+00B7, so no byte hides at a line's end.
VARIABLE _AGRV-SB-A    0 _AGRV-SB-A !
VARIABLE _AGRV-SB-CAP  0 _AGRV-SB-CAP !

: _AGRV-SB-FIT?  ( u -- ok? )
    DUP _AGRV-SB-CAP @ > 0= IF DROP -1 EXIT THEN
    64 MAX DUP ALLOCATE IF 2DROP 0 EXIT THEN
    _AGRV-SB-A @ ?DUP IF FREE THEN
    _AGRV-SB-A ! _AGRV-SB-CAP ! -1 ;

\ The paragraph as the dialog shows it.  An exact value that finds no
\ memory for its copy fails the walk, which keeps approval locked.
VARIABLE _AGRV-FAILED

: _AGRV-SHOWN  ( addr len look -- addr' len' )
    _AGRV-EXACT? 0= IF EXIT THEN
    DUP 2* _AGRV-SB-FIT? 0= IF -1 _AGRV-FAILED ! EXIT THEN
    _AGRV-SB-A @ 0 2SWAP                            ( dst n addr len )
    OVER + SWAP ?DO
        I C@ 32 = IF
            0xC2 2 PICK 2 PICK + C!  0xB7 2 PICK 2 PICK + 1+ C!  2 +
        ELSE
            I C@ 2 PICK 2 PICK + C!  1+
        THEN
    LOOP ;

CREATE _AG-TLN TLINES-SIZE ALLOT  _AG-TLN TLINES-INIT

VARIABLE _AGRV-W        \ the dialog's text width
VARIABLE _AGRV-N        \ rows counted, or the row being drawn
VARIABLE _AGRV-Y0       \ the dialog's first content row
VARIABLE _AGRV-VIEWH    \ content rows it shows
VARIABLE _AGRV-RW       \ the dialog's width
VARIABLE _AGRV-RH       \ and height

: _AGRV-COUNT  ( addr len look -- )
    _AGRV-SHOWN TROW-F-UNTRUSTED BIDI-AUTO _AGRV-W @ _AG-TLN TLINES-COUNT
    0= IF -1 _AGRV-FAILED ! THEN _AGRV-N +! ;

: _AGRV-ROWS  ( -- rows )
    0 _AGRV-N ! ['] _AGRV-COUNT _AGRV-EACH _AGRV-N @ ;

\ Draw the line the cursor has read, when its row is in view.
: _AGRV-DRAW-LINE  ( -- )
    _AGRV-N @ _AG-REVIEW-TOP @ -
    DUP 0< OVER _AGRV-VIEWH @ < 0= OR IF DROP EXIT THEN
    _AGRV-Y0 @ +                                     ( row )
    _AG-TLN TLINES-ROW ?DUP IF
        SWAP 1
        _AG-TLN TLINES-RTL? IF _AGRV-W @ _AG-TLN TLINES-WIDTH - 0 MAX + THEN
        DRW-TROW EXIT
    THEN
    _AG-TLN TLINES-BYTES ROT 1 DRW-TEXT ;

: _AGRV-DRAW-P  ( addr len look -- )
    DUP _AGRV-LOOK!
    _AGRV-SHOWN TROW-F-UNTRUSTED BIDI-AUTO _AGRV-W @ _AG-TLN TLINES-START
    BEGIN WHILE
        _AGRV-DRAW-LINE 1 _AGRV-N +!
        _AG-TLN TLINES-NEXT
    REPEAT
    _AG-TLN TLINES-FAILED? IF -1 _AGRV-FAILED ! THEN ;

: _AGRV-DRAW-WALK  ( -- )
    0 _AGRV-N ! ['] _AGRV-DRAW-P _AGRV-EACH ;

: _AGRV-FOOTER$  ( -- addr len )
    _AG-REVIEW-REQUEST IF
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ _AG-INPUT-REVIEWABLE? 0= IF
            S" Operand cannot be approved  [F7] Deny" EXIT
        THEN
    THEN
    _AG-REVIEW-INSPECTED? IF S" [F6] Approve once  [F7] Deny" EXIT THEN
    S" PgDn to inspect all rows  F6 locked  [F7] Deny" ;

\ A title row when the dialog has room, its content, and a footer row.
: _AGRV-GEOMETRY  ( widget -- )
    WDG-REGION DUP RGN-W _AGRV-RW ! RGN-H _AGRV-RH !
    _AGRV-RH @ 3 < IF 0 ELSE 1 THEN _AGRV-Y0 !
    _AGRV-RH @ _AGRV-Y0 @ - 1- 0 MAX _AGRV-VIEWH !
    _AGRV-RW @ 2 - 1 MAX _AGRV-W ! ;

: _AGRV-DRAW-BODY  ( widget -- )
    _AGRV-GEOMETRY
    253 234 0 DRW-STYLE!
    32 0 0 _AGRV-RH @ _AGRV-RW @ DRW-FILL-RECT
    _AGRV-Y0 @ IF
        15 24 1 DRW-STYLE!
        32 0 0 1 _AGRV-RW @ DRW-FILL-RECT
        S" Review required" 0 2 DRW-TEXT
    THEN
    0 _AGRV-FAILED !
    _AGRV-ROWS DUP _AG-REVIEW-ROWS !
    _AGRV-VIEWH @ - 0 MAX _AG-REVIEW-TOP @ MIN 0 MAX _AG-REVIEW-TOP !
    _AGRV-VIEWH @ _AG-REVIEW-SPAN !
    ['] _AGRV-DRAW-WALK _AGRV-Y0 @ 1 _AGRV-VIEWH @ _AGRV-W @ DRW-WITH-CLIP
    _AGRV-RH @ 1 > IF
        253 236 0 DRW-STYLE!
        32 _AGRV-RH @ 1- 0 1 _AGRV-RW @ DRW-FILL-RECT
        _AGRV-FOOTER$ _AGRV-RH @ 1- 2 DRW-TEXT
    THEN
    \ A drawn frame has shown the last row: approval unlocks, and the next
    \ frame's footer says so.
    _AGRV-FAILED @ 0= _AGRV-VIEWH @ 0> AND
    _AG-REVIEW-TOP @ _AGRV-VIEWH @ + _AG-REVIEW-ROWS @ < 0= AND IF
        _AG-REVIEW-BOTTOM-SEEN @ 0= _AG-REVIEW-CURRENT? AND IF
            -1 _AG-REVIEW-BOTTOM-SEEN !  -1 _AG-REVIEW-REDRAW-PENDING !
        THEN
    THEN
    DRW-STYLE-RESET ;

: _AGRV-DRAW  ( widget -- )  ['] _AGRV-DRAW-BODY DRW-OVERLAY ;

: _AGRV-SCROLL  ( rows -- )
    _AG-REVIEW-TOP @ + _AG-REVIEW-ROWS @ _AG-REVIEW-SPAN @ - 0 MAX MIN 0 MAX
    _AG-REVIEW-TOP !
    _AG-REVIEW WDG-DIRTY ASHELL-DIRTY! ;

: _AGRV-PAGE  ( -- rows )  _AG-REVIEW-SPAN @ 1- 1 MAX ;

: _AG-REVIEW-HANDLE  ( event widget -- consumed? )
    DROP
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-UP OF -1 _AGRV-SCROLL -1 ENDOF
            KEY-DOWN OF 1 _AGRV-SCROLL -1 ENDOF
            KEY-PGUP OF _AGRV-PAGE NEGATE _AGRV-SCROLL -1 ENDOF
            KEY-PGDN OF _AGRV-PAGE _AGRV-SCROLL -1 ENDOF
            KEY-HOME OF _AG-REVIEW-TOP @ NEGATE _AGRV-SCROLL -1 ENDOF
            KEY-END OF _AG-REVIEW-ROWS @ _AGRV-SCROLL -1 ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DUP @ KEY-T-MOUSE = IF
        8 + @ KEY-MOUSE-BUTTON CASE
            KEY-MOUSE-SCROLL-UP OF -3 _AGRV-SCROLL ENDOF
            KEY-MOUSE-SCROLL-DN OF 3 _AGRV-SCROLL ENDOF
        ENDCASE
        \ Every press on the dialog is its own.
        -1 EXIT
    THEN
    DROP 0 ;

: _AG-REVIEW-INIT  ( region -- )
    DUP _AG-REVIEW-RGN !
    _AG-REVIEW 42 ROT
    ['] _AGRV-DRAW ['] _AG-REVIEW-HANDLE WDG-INIT ;

\ =====================================================================
\  Panel
\ =====================================================================

VARIABLE _AGD-W
VARIABLE _AGD-H

\ Place REGION exactly over the panel.
: _AG-OVER-PANEL  ( region -- )
    >R _AG-PANEL-RGN @ DUP RGN-ROW OVER RGN-COL 2 PICK RGN-H 3 PICK RGN-W
    R> RGN-BOUNDS! DROP ;

: _AG-PANEL-DRAW  ( widget -- )
    DUP WDG-REGION RGN-W _AGD-W !
    WDG-REGION RGN-H _AGD-H !
    253 234 0 DRW-STYLE!
    32 0 0 _AGD-H @ _AGD-W @ DRW-FILL-RECT
    _AG-RUNTIME @ 0= IF
        203 234 1 DRW-STYLE!
        S" Agent runtime unavailable" 1 2 DRW-TEXT
        DRW-STYLE-RESET EXIT
    THEN
    \ A dialog or panel covers the body: the transcript waits beneath it.
    _AG-USER-OVERLAY? _AG-REVIEW-OPEN? OR IF DRW-STYLE-RESET EXIT THEN
    _AG-CONV ACONV.COUNT @ ?DUP 0= IF
        244 234 0 DRW-STYLE!
        S" Start a conversation" 1 2 DRW-TEXT
        DRW-STYLE-RESET EXIT
    THEN
    _AG-LIST @ LST-RECOUNT
    _AG-LIST-RGN @ _AG-OVER-PANEL
    253 234 0 DRW-STYLE! DRW-STYLE-SAVE
    _AG-LIST @ _AG-PANEL-RGN @ WDG-DRAW-IN
    DRW-STYLE-RESET ;

\ Enter asks and Escape cancels; other keys and the pointer scroll the
\ review dialog while it is open, and the transcript otherwise.
: _AG-PANEL-HANDLE  ( event widget -- consumed? )
    DROP
    DUP @ KEY-T-SPECIAL = IF
        DUP 8 + @ KEY-ENTER = IF DROP _AG-SHOW-PROMPT -1 EXIT THEN
        DUP 8 + @ KEY-ESC = IF
            DROP _AG-RUNTIME @ ARUNTIME-CANCEL DROP _AG-INVALIDATE -1 EXIT
        THEN
    THEN
    _AG-REVIEW-OPEN? IF _AG-REVIEW WDG-HANDLE EXIT THEN
    _AG-USER-OVERLAY? IF DROP 0 EXIT THEN
    _AG-CONV ACONV.COUNT @ 0= IF DROP 0 EXIT THEN
    _AG-LIST @ WDG-HANDLE DUP IF _AG-INVALIDATE THEN ;

: _AG-PANEL-INIT  ( region -- )
    DUP _AG-PANEL-RGN !
    _AG-PANEL 41 ROT
    ['] _AG-PANEL-DRAW ['] _AG-PANEL-HANDLE WDG-INIT ;

: _AG-DO-PROMPT  ( elem -- ) DROP _AG-SHOW-PROMPT ;
: _AG-DO-CANCEL  ( elem -- ) DROP _AG-RUNTIME @ ARUNTIME-CANCEL DROP _AG-INVALIDATE ;
VARIABLE _AG-REVIEW-APPROVED

: _AG-RESOLVE-REVIEW  ( approved -- )
    _AG-REVIEW-APPROVED !
    \ A review that changed since it was read locks again first.
    _AG-SYNC-REVIEW
    _AG-REVIEW-APPROVED @ IF
        _AG-REVIEW-IDENTITY ?DUP IF
            DROP _AG-REVIEW-APPROVABLE? 0= IF
                _AG-REVIEW-REQUEST 0= IF
                    S" Approval locked: inspect every operand row with PgDn"
                ELSE
                    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @
                    _AG-INPUT-REVIEWABLE? IF
                        S" Approval locked: inspect every operand row with PgDn"
                    ELSE
                        S" Approval disabled: exact canonical operand unavailable"
                    THEN
                THEN
                    2600 ASHELL-TOAST
                _AG-INVALIDATE EXIT
            THEN
        THEN
    THEN
    _AG-REVIEW-APPROVED @ _AG-RUNTIME @ ARUNTIME-RESOLVE IF
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ ?DUP IF
            ATOOLG.STATE @ CASE
                ATOOLG-S-IDLE OF S" Review rejected: gateway idle" ENDOF
                ATOOLG-S-QUEUED OF S" Review rejected: gateway queued" ENDOF
                ATOOLG-S-APPROVAL OF S" Review resolution failed" ENDOF
                ATOOLG-S-COMPLETE OF S" Review rejected: gateway complete" ENDOF
                S" Review state is invalid" ROT
            ENDCASE
        ELSE
            S" No review request is pending"
        THEN
        1800 ASHELL-TOAST
    ELSE
        _AG-REVIEW-APPROVED @ IF
            S" Request approved" 1000 ASHELL-TOAST
        ELSE
            S" Request denied" 1000 ASHELL-TOAST
        THEN
    THEN
    _AG-INVALIDATE ;

: _AG-DO-APPROVE ( elem -- ) DROP -1 _AG-RESOLVE-REVIEW ;
: _AG-DO-DENY    ( elem -- ) DROP 0 _AG-RESOLVE-REVIEW ;

: _AG-CLEAR-STATUS-TOAST  ( ior -- )
    IF
        S" Finish or cancel the active run before clearing" 2200
    ELSE
        S" Conversation cleared" 1200
    THEN
    ASHELL-TOAST ;

: _AG-RECONNECT-STATUS-TOAST  ( ior -- )
    IF S" Agent reconnect failed" 1800 ELSE S" Reconnect requested" 1200 THEN
    ASHELL-TOAST ;

: _AG-DO-CLEAR  ( elem -- )
    DROP _AG-RUNTIME @ ARUNTIME-CLEAR _AG-CLEAR-STATUS-TOAST
    _AG-LIST @ ?DUP IF LST-SCROLL-END THEN _AG-INVALIDATE ;

: _AG-DO-RECONNECT  ( elem -- )
    DROP _AG-RUNTIME @ ARUNTIME-RECONNECT _AG-RECONNECT-STATUS-TOAST
    _AG-INVALIDATE ;
: _AG-DO-CREDENTIAL ( elem -- ) DROP _AG-SHOW-AUTH-PROMPT ;
: _AG-DO-ACCOUNT ( elem -- ) DROP _AG-SHOW-ACCOUNT ;
: _AG-DO-SETTINGS ( elem -- ) DROP _AG-SHOW-SETTINGS ;

: _AG-ACCESS-STATUS-TOAST  ( status -- )
    CASE
        AAP-S-OK OF S" Agent access profile changed" 1400 ENDOF
        AAP-S-INVALID OF S" Access preset is invalid" 1800 ENDOF
        AAP-S-BUSY OF S" Finish or cancel the active run before changing access" 2400 ENDOF
        AAP-S-UNAVAILABLE OF S" Access controls require a Desk scope" 2200 ENDOF
        DROP S" Access profile change failed" 2000 0
    ENDCASE
    ASHELL-TOAST ;

: _AG-ACCESS!  ( preset -- )
    _AG-RUNTIME @ ARUNTIME-ACCESS-PRESET!
    _AG-ACCESS-STATUS-TOAST _AG-INVALIDATE ;

: _AG-DO-ACCESS-CHAT   ( elem -- ) DROP AAP-PRESET-CHAT-ONLY _AG-ACCESS! ;
: _AG-DO-ACCESS-READ   ( elem -- ) DROP AAP-PRESET-PRACTICE-READ _AG-ACCESS! ;
: _AG-DO-ACCESS-ASSIST ( elem -- ) DROP AAP-PRESET-PRACTICE-ASSIST _AG-ACCESS! ;
: _AG-DO-ACCESS-LIBRARY-BURROW  ( elem -- )
    DROP AAP-PRESET-PRACTICE-LIBRARY-BURROW _AG-ACCESS! ;

: _AG-DO-REFRESH-MODELS ( elem -- )
    DROP _AG-RUNTIME @ ARUNTIME-RUN-SETTINGS-REFRESH DUP
    ARSET-S-PENDING = SWAP ARSET-S-OK = OR IF
        S" Model catalog refresh started" 1200 ASHELL-TOAST
    ELSE
        S" Model catalog refresh failed" 1800 ASHELL-TOAST
    THEN
    _AG-SHOW-SETTINGS ;
: _AG-DO-CLEAR-CREDENTIAL ( elem -- )
    DROP _AG-RUNTIME @ ARUNTIME-AUTH-CLEAR DUP IF
        _AG-AUTH-SET-TOAST
    ELSE
        DROP S" Credential cleared" 1200 ASHELL-TOAST
    THEN
    _AG-INVALIDATE ;
: _AG-DO-QUIT    ( elem -- ) DROP ASHELL-QUIT ;
: _AG-DO-ABOUT   ( elem -- ) DROP S" Agent - provider-neutral conversations and app tools" 2500 ASHELL-TOAST ;

: _AG-BIND-STORE  ( -- )
    VFS-CUR ?DUP 0= IF EXIT THEN
    AVFSSTORE-NEW DUP IF
        NIP _AG-RUNTIME @ ARUNTIME.STORE-STATUS ! EXIT
    THEN
    DROP _AG-RUNTIME @ ARUNTIME-CONVERSATION-STORE! DROP ;

: AGENT-INIT-CB  ( instance -- )
    _AG-ACTIVATE
    0 _AG-OWNS-RUNTIME !
    -1 _AG-COMPACT-STATUS !
    _AG-REVIEW-TRACKING-CLEAR
    _AG-DISPLAY ACONV-MAX-MESSAGES _AGDT-SIZE * 0 FILL
    0 _AG-LAST-REVISION ! _AG-PRM-ASK _AG-PROMPT-MODE !
    S" org.akashic.agent.runtime" _AG-CURRENT-INSTANCE @ CINST-SERVICE
    DUP _AG-RUNTIME !
    0= IF
        _AG-PENDING-SOURCE @ ?DUP 0= IF
            OFFLINE-SOURCE-NEW
            0<> ABORT" agent: offline source allocation failed"
        THEN
        0 _AG-PENDING-SOURCE !
        DUP _AG-SOURCE !
        APSOURCE-PROVIDER-NEW 0<> ABORT" agent: provider allocation failed"
        DUP _AG-PROVIDER !
        ARUNTIME-NEW 0<> ABORT" agent: runtime allocation failed"
        _AG-RUNTIME ! -1 _AG-OWNS-RUNTIME !
        _AG-BIND-STORE
    ELSE
        S" org.akashic.agent.provider-source"
        _AG-CURRENT-INSTANCE @ CINST-SERVICE _AG-SOURCE !
    THEN
    S" agent-body" UTUI-BY-ID _AG-E-BODY !
    S" meta" UTUI-BY-ID _AG-E-META !
    S" sbar" UTUI-BY-ID _AG-E-SBAR !
    S" source-class" UTUI-BY-ID _AG-E-SOURCE-CLASS !
    S" provider" UTUI-BY-ID _AG-E-PROVIDER !
    S" model" UTUI-BY-ID _AG-E-MODEL !
    S" effort" UTUI-BY-ID _AG-E-EFFORT !
    S" access" UTUI-BY-ID _AG-E-ACCESS !
    S" state" UTUI-BY-ID _AG-E-STATE !

    _AG-E-SBAR @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW DUP _AG-PROMPT-RGN !
        _AG-PROMPT-BUF _AG-PROMPT-CAP PRM-NEW DUP _AG-PROMPT !
        ['] _AG-PROMPT-SUBMIT OVER PRM-ON-SUBMIT
        ['] _AG-PROMPT-CANCEL OVER PRM-ON-CANCEL
        15 24 ROT PRM-COLORS!
    THEN
    _AG-E-BODY @ ?DUP IF
        UTUI-ELEM-RGN RGN-NEW _AG-PANEL-INIT
        _AG-CARD-COLUMNS-INIT
        _AG-PANEL-RGN @ 0 0 1 1 RGN-SUB DUP _AG-LIST-RGN !
            _AG-LIST-NEW _AG-LIST !
        _AG-E-BODY @ UTUI-ELEM-RGN RGN-NEW _AG-REVIEW-INIT
        _AG-PANEL _AG-E-BODY @ UTUI-WIDGET-SET
        _AG-E-BODY @ UTUI-ELEM-RGN RGN-NEW DUP _AG-AUTH-RGN !
        _AG-RUNTIME @ SWAP AAUTHP-NEW _AG-AUTH-PANEL !
        _AG-E-BODY @ UTUI-ELEM-RGN RGN-NEW DUP _AG-SETTINGS-RGN !
        _AG-RUNTIME @ SWAP ARSP-NEW _AG-SETTINGS-PANEL !
    THEN
    S" prompt" ['] _AG-DO-PROMPT UTUI-DO!
    S" cancel" ['] _AG-DO-CANCEL UTUI-DO!
    S" approve" ['] _AG-DO-APPROVE UTUI-DO!
    S" deny" ['] _AG-DO-DENY UTUI-DO!
    S" clear" ['] _AG-DO-CLEAR UTUI-DO!
    S" reconnect" ['] _AG-DO-RECONNECT UTUI-DO!
    S" credential" ['] _AG-DO-CREDENTIAL UTUI-DO!
    S" account" ['] _AG-DO-ACCOUNT UTUI-DO!
    S" clear-credential" ['] _AG-DO-CLEAR-CREDENTIAL UTUI-DO!
    S" settings" ['] _AG-DO-SETTINGS UTUI-DO!
    S" refresh-models" ['] _AG-DO-REFRESH-MODELS UTUI-DO!
    S" access-chat" ['] _AG-DO-ACCESS-CHAT UTUI-DO!
    S" access-read" ['] _AG-DO-ACCESS-READ UTUI-DO!
    S" access-assist" ['] _AG-DO-ACCESS-ASSIST UTUI-DO!
    S" access-library-burrow" ['] _AG-DO-ACCESS-LIBRARY-BURROW UTUI-DO!
    S" quit" ['] _AG-DO-QUIT UTUI-DO!
    S" about" ['] _AG-DO-ABOUT UTUI-DO!
    _AG-E-BODY @ ?DUP IF UTUI-FOCUS! THEN
    _AG-RUNTIME @ ARUNTIME.REVISION @ _AG-LAST-REVISION !
    _AG-COMPACT-NOW? _AG-COMPACT-STATUS !
    _AG-INVALIDATE ;

: AGENT-EVENT-CB  ( event instance -- consumed? )
    _AG-ACTIVATE
    _AG-AUTH-PANEL @ ?DUP IF
        DUP AAUTHP-ACTIVE? IF
            WDG-HANDLE DUP IF _AG-INVALIDATE THEN EXIT
        THEN
        DROP
    THEN
    _AG-SETTINGS-PANEL @ ?DUP IF
        DUP ARSP-ACTIVE? IF
            WDG-HANDLE DUP IF _AG-INVALIDATE THEN EXIT
        THEN
        DROP
    THEN
    DUP @ KEY-T-SPECIAL = IF
        DUP KEY-CODE@ CASE
            KEY-F6 OF DROP -1 _AG-RESOLVE-REVIEW -1 EXIT ENDOF
            KEY-F7 OF DROP 0 _AG-RESOLVE-REVIEW -1 EXIT ENDOF
            KEY-F8 OF DROP _AG-SHOW-SETTINGS -1 EXIT ENDOF
            KEY-F9 OF DROP _AG-SHOW-ACCOUNT -1 EXIT ENDOF
        ENDCASE
    THEN
    _AG-PROMPT @ ?DUP IF
        DUP PRM-ACTIVE? IF WDG-HANDLE EXIT THEN DROP
    THEN
    \ Pointer input is the prompt's or UIDL's; the panel gets it through UIDL.
    DUP @ KEY-T-MOUSE = IF DROP 0 EXIT THEN
    DUP @ KEY-T-CHAR = IF
        DUP KEY-HAS-CTRL? IF
            DUP KEY-CODE@ [CHAR] l = IF
                DROP _AG-SHOW-PROMPT -1 EXIT
            THEN
            DUP KEY-CODE@ [CHAR] k = IF
                DUP KEY-HAS-SHIFT? IF
                    DROP 0 _AG-DO-CLEAR-CREDENTIAL -1 EXIT
                THEN
                DROP _AG-SHOW-AUTH-PROMPT -1 EXIT
            THEN
        THEN
    THEN
    _UTUI-MENU-OPEN @ IF DROP 0 EXIT THEN
    _AG-PANEL WDG-HANDLE ;

: AGENT-TICK-CB  ( instance -- )
    _AG-ACTIVATE
    _AG-OWNS-RUNTIME @ IF 8 _AG-RUNTIME @ ARUNTIME-PUMP DROP THEN
    _AG-SYNC-REVIEW
    _AG-FLUSH-REVIEW-REDRAW
    _AG-SYNC-STATUS-MODE
    _AG-RUNTIME @ ARUNTIME.REVISION @ _AG-LAST-REVISION @ <> IF
        _AG-RUNTIME @ ARUNTIME.REVISION @ _AG-LAST-REVISION !
        _AG-INVALIDATE
    THEN
    _AG-AUTH-PANEL @ ?DUP IF AAUTHP-SYNC IF ASHELL-DIRTY! THEN THEN
    _AG-SETTINGS-PANEL @ ?DUP IF ARSP-SYNC IF ASHELL-DIRTY! THEN THEN ;

: AGENT-PAINT-CB  ( instance -- )
    _AG-ACTIVATE
    _AG-USER-OVERLAY? 0= _AG-REVIEW-OPEN? AND IF
        _AG-REVIEW-RGN @ _AG-OVER-PANEL
        _AG-REVIEW WDG-DRAW
    THEN
    _AG-AUTH-PANEL @ ?DUP IF DUP AAUTHP-ACTIVE? IF WDG-DRAW ELSE DROP THEN THEN
    _AG-SETTINGS-PANEL @ ?DUP IF DUP ARSP-ACTIVE? IF WDG-DRAW ELSE DROP THEN THEN
    _AG-PROMPT @ ?DUP 0= IF EXIT THEN
    DUP PRM-ACTIVE? 0= IF DROP EXIT THEN DROP
    _AG-E-SBAR @ ?DUP IF UTUI-ELEM-RGN _AG-PROMPT @ PRM-SET-BOUNDS THEN
    _AG-PROMPT @ WDG-DRAW ;

\ Shared runtimes belong to the containing Practice, not to this visual
\ lens.  Closing that lens must never cancel work another view or the owner
\ is supervising.  A standalone Agent owns its runtime, so an active stream
\ or approval is explicitly cancelled before its resources are released.
: AGENT-REQUEST-CLOSE-CB  ( reason instance -- decision )
    _AG-ACTIVATE DROP
    _AG-RUNTIME @ 0= IF APP-CLOSE-D-ALLOW EXIT THEN
    _AG-OWNS-RUNTIME @ 0= IF APP-CLOSE-D-ALLOW EXIT THEN
    _AG-RUNTIME @ ARUNTIME-BUSY? 0= IF APP-CLOSE-D-ALLOW EXIT THEN
    S" Cancel the active Agent run and close?" DLG-CONFIRM 0= IF
        APP-CLOSE-D-CANCEL EXIT
    THEN
    _AG-RUNTIME @ ARUNTIME-CANCEL IF
        APP-CLOSE-D-CANCEL
    ELSE
        APP-CLOSE-D-ALLOW
    THEN ;

: AGENT-SHUTDOWN-CB  ( instance -- )
    _AG-ACTIVATE
    _AG-E-BODY @ ?DUP IF 0 SWAP UTUI-WIDGET-SET THEN
    _AG-PROMPT @ ?DUP IF DUP PRM-WIPE PRM-FREE THEN
    _AG-AUTH-PANEL @ ?DUP IF AAUTHP-FREE THEN
    _AG-SETTINGS-PANEL @ ?DUP IF ARSP-FREE THEN
    _AG-AUTH-RGN @ ?DUP IF RGN-FREE THEN
    _AG-SETTINGS-RGN @ ?DUP IF RGN-FREE THEN
    _AG-PROMPT-RGN @ ?DUP IF RGN-FREE THEN
    _AG-LIST @ ?DUP IF LST-FREE THEN
    _AG-LIST-RGN @ ?DUP IF RGN-FREE THEN
    _AG-REVIEW-RGN @ ?DUP IF RGN-FREE THEN
    _AG-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    _AG-DISPLAY-RELEASE
    _AG-OWNS-RUNTIME @ IF
        _AG-RUNTIME @ ARUNTIME-FREE
        _AG-PROVIDER @ APROV-FREE
        _AG-SOURCE @ APSOURCE-FREE
    THEN
    0 _AG-RUNTIME ! 0 _AG-PROVIDER ! 0 _AG-SOURCE ! 0 _AG-PROMPT !
    0 _AG-AUTH-PANEL ! 0 _AG-SETTINGS-PANEL !
    0 _AG-LIST ! 0 _AG-LIST-RGN ! 0 _AG-REVIEW-RGN ! ;

CREATE AGENT-COMP-DESC COMP-DESC ALLOT

: _AGENT-COMP-SETUP  ( -- )
    AGENT-COMP-DESC COMP-DESC-INIT
    S" org.akashic.agent"
    AGENT-COMP-DESC COMP.ID-U ! AGENT-COMP-DESC COMP.ID-A !
    S" 1.0.0"
    AGENT-COMP-DESC COMP.VERSION-U ! AGENT-COMP-DESC COMP.VERSION-A !
    _AG-STATE-SIZE AGENT-COMP-DESC COMP.STATE-SIZE ! ;

: AGENT-ENTRY  ( app-desc -- )
    _AGENT-COMP-SETUP
    DUP APP-DESC-INIT
    AGENT-COMP-DESC OVER APP.COMP-DESC !
    ['] AGENT-INIT-CB OVER APP.INIT-XT !
    ['] AGENT-EVENT-CB OVER APP.EVENT-XT !
    ['] AGENT-TICK-CB OVER APP.TICK-XT !
    ['] AGENT-PAINT-CB OVER APP.PAINT-XT !
    ['] AGENT-SHUTDOWN-CB OVER APP.SHUTDOWN-XT !
    ['] _AG-ACTIVATE OVER APP.ACTIVATE-XT !
    ['] AGENT-REQUEST-CLOSE-CB OVER APP.REQUEST-CLOSE-XT !
    S" tui/applets/agent/agent.uidl"
    ROT DUP >R APP.UIDL-FILE-U ! R@ APP.UIDL-FILE-A !
    0 R@ APP.WIDTH ! 0 R@ APP.HEIGHT !
    S" Agent" R@ APP.TITLE-U ! R> APP.TITLE-A ! ;

CREATE AGENT-DESC APP-DESC ALLOT

VARIABLE _AGSET-SOURCE

: AGENT-SOURCE!  ( source -- )
    _AGSET-SOURCE !
    _AGSET-SOURCE @ _AG-PENDING-SOURCE @ = IF EXIT THEN
    _AG-PENDING-SOURCE @ ?DUP IF APSOURCE-FREE THEN
    _AGSET-SOURCE @ _AG-PENDING-SOURCE ! ;

: AGENT-RUN  ( -- )
    AGENT-DESC AGENT-ENTRY
    AGENT-DESC ASHELL-RUN ;
