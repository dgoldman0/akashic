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
REQUIRE ../../../text/cell-width.f
REQUIRE ../../../runtime/state-layout.f
REQUIRE ../../../interop/endpoint.f
REQUIRE service.f

512 CONSTANT _AG-PROMPT-CAP
0 CONSTANT _AG-PRM-ASK
1 CONSTANT _AG-PRM-AUTH
0 CONSTANT _AG-ANCHOR-NONE
1 CONSTANT _AG-ANCHOR-PENDING
2 CONSTANT _AG-ANCHOR-APPLIED

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
_AG-CURRENT-STATE CMP-CELL: _AG-PROMPT
_AG-CURRENT-STATE CMP-CELL: _AG-PROMPT-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-PROMPT-MODE
_AG-CURRENT-STATE _AG-PROMPT-CAP CMP-FIELD: _AG-PROMPT-BUF
_AG-CURRENT-STATE CMP-CELL: _AG-AUTH-PANEL
_AG-CURRENT-STATE CMP-CELL: _AG-AUTH-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-SETTINGS-PANEL
_AG-CURRENT-STATE CMP-CELL: _AG-SETTINGS-RGN
_AG-CURRENT-STATE CMP-CELL: _AG-LAST-REVISION
_AG-CURRENT-STATE CMP-CELL: _AG-SCROLL
_AG-CURRENT-STATE CMP-CELL: _AG-LAYOUT-ROWS
_AG-CURRENT-STATE CMP-CELL: _AG-LAYOUT-W
_AG-CURRENT-STATE CMP-CELL: _AG-LAYOUT-H
_AG-CURRENT-STATE CMP-CELL: _AG-COMPACT-STATUS
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-REQUEST-ID
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-GATEWAY-REV
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-RUNTIME-REV
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-BOTTOM-SEEN
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-ANCHOR-STATE
_AG-CURRENT-STATE CMP-CELL: _AG-REVIEW-REDRAW-PENDING

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
    0 _AG-SCROLL ! _AG-INVALIDATE ;

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

: _AG-ROLE-STYLE  ( role -- )
    CASE
        AROLE-USER OF 81 234 1 DRW-STYLE! ENDOF
        AROLE-ASSISTANT OF 42 234 1 DRW-STYLE! ENDOF
        AROLE-TOOL OF 220 234 1 DRW-STYLE! ENDOF
        AROLE-SYSTEM OF 244 234 1 DRW-STYLE! ENDOF
        253 234 0 DRW-STYLE!
    ENDCASE ;

VARIABLE _AGD-W
VARIABLE _AGD-H
VARIABLE _AGD-COUNT
VARIABLE _AGD-TOTAL
VARIABLE _AGD-START
VARIABLE _AGD-END
VARIABLE _AGD-I
VARIABLE _AGD-LINE
VARIABLE _AGD-MSG
VARIABLE _AGD-TEXT-W

VARIABLE _AGW-A
VARIABLE _AGW-U
VARIABLE _AGW-W
VARIABLE _AGW-EMPTY
VARIABLE _AGW-START
VARIABLE _AGW-SA
VARIABLE _AGW-SU
VARIABLE _AGW-NA
VARIABLE _AGW-NU
VARIABLE _AGW-CP
VARIABLE _AGW-CPW
VARIABLE _AGW-USED
VARIABLE _AGW-BA
VARIABLE _AGW-BU
VARIABLE _AGW-BSEEN
VARIABLE _AGW-SOFT

: _AG-CELL-WIDTH  ( cp -- cells )
    DUP 9 = IF DROP 1 EXIT THEN
    DUP 32 < OVER 127 = OR IF DROP 1 EXIT THEN
    DUP 32 >= OVER 126 <= AND IF DROP 1 EXIT THEN
    \ The screen buffer stores one codepoint per physical slot and cannot
    \ compose a zero-width codepoint into the preceding slot.  Reserve the
    \ same representable cell here that the renderer consumes so wrapping
    \ can never hide a combining/format codepoint or trailing text.
    CW-WIDTH 1 MAX ;

\ A zero-length message still owns one visual row.  Hard CR, LF, and CRLF
\ breaks are preserved, while soft breaks prefer the last ASCII whitespace
\ that fit.  Addresses returned by NEXT are borrowed from the message.
: _AG-WRAP-BASE  ( addr len width -- )
    1 MAX _AGW-W ! _AGW-U ! _AGW-A !
    _AGW-U @ 0= _AGW-EMPTY ! ;

: _AG-WRAP-INIT  ( addr len width -- )
    _AG-WRAP-BASE -1 _AGW-SOFT ! ;

\ Approval operands use an exact wrapper: every accepted byte remains in a
\ slice and whitespace is never consumed merely because it falls on an edge.
: _AG-WRAP-EXACT-INIT  ( addr len width -- )
    _AG-WRAP-BASE 0 _AGW-SOFT ! ;

: _AG-WRAP-NEXT  ( -- addr len true | false )
    _AGW-EMPTY @ IF
        0 _AGW-EMPTY ! _AGW-A @ 0 -1 EXIT
    THEN
    _AGW-U @ 0= IF 0 EXIT THEN
    _AGW-A @ DUP _AGW-START ! _AGW-SA !
    _AGW-U @ _AGW-SU !
    0 _AGW-USED ! 0 _AGW-BSEEN !
    BEGIN _AGW-SU @ 0> WHILE
        _AGW-SA @ _AGW-SU @ UTF8-DECODE
        _AGW-NU ! _AGW-NA ! _AGW-CP !
        _AGW-CP @ DUP 10 = SWAP 13 = OR IF
            _AGW-CP @ 13 = _AGW-NU @ 0> AND IF
                _AGW-NA @ C@ 10 = IF
                    1 _AGW-NA +! -1 _AGW-NU +!
                THEN
            THEN
            _AGW-NA @ _AGW-A ! _AGW-NU @ _AGW-U !
            _AGW-U @ 0= IF -1 _AGW-EMPTY ! THEN
            _AGW-START @ _AGW-SA @ _AGW-START @ - -1 EXIT
        THEN
        _AGW-CP @ _AG-CELL-WIDTH _AGW-CPW !
        _AGW-USED @ _AGW-CPW @ + _AGW-W @ > IF
            _AGW-SOFT @ IF
                _AGW-CP @ DUP 32 = SWAP 9 = OR IF
                    _AGW-NA @ _AGW-A ! _AGW-NU @ _AGW-U !
                    _AGW-START @ _AGW-SA @ _AGW-START @ - -1 EXIT
                THEN
                _AGW-BSEEN @ IF
                    _AGW-BA @ _AGW-A ! _AGW-BU @ _AGW-U !
                    _AGW-START @ _AGW-BA @ _AGW-START @ - -1 EXIT
                THEN
            THEN
            _AGW-SA @ _AGW-START @ = IF
                _AGW-NA @ _AGW-A ! _AGW-NU @ _AGW-U !
                _AGW-START @ _AGW-NA @ _AGW-START @ - -1 EXIT
            THEN
            _AGW-SA @ _AGW-A ! _AGW-SU @ _AGW-U !
            _AGW-START @ _AGW-SA @ _AGW-START @ - -1 EXIT
        THEN
        _AGW-CPW @ _AGW-USED +!
        _AGW-SOFT @ _AGW-CP @ DUP 32 = SWAP 9 = OR AND IF
            _AGW-NA @ _AGW-BA ! _AGW-NU @ _AGW-BU !
            -1 _AGW-BSEEN !
        THEN
        _AGW-NA @ _AGW-SA ! _AGW-NU @ _AGW-SU !
    REPEAT
    _AGW-SA @ _AGW-A ! _AGW-SU @ _AGW-U !
    _AGW-START @ _AGW-SA @ _AGW-START @ - -1 ;

VARIABLE _AGWC-N

: _AG-WRAPPED-ROWS  ( addr len width -- rows )
    _AG-WRAP-INIT 0 _AGWC-N !
    BEGIN _AG-WRAP-NEXT WHILE
        2DROP 1 _AGWC-N +!
    REPEAT
    _AGWC-N @ ;

: _AG-EXACT-ROWS  ( addr len width -- rows )
    _AG-WRAP-EXACT-INIT 0 _AGWC-N !
    BEGIN _AG-WRAP-NEXT WHILE
        2DROP 1 _AGWC-N +!
    REPEAT
    _AGWC-N @ ;

VARIABLE _AGDC-A
VARIABLE _AGDC-U
VARIABLE _AGDC-ROW
VARIABLE _AGDC-COL
VARIABLE _AGDC-MAX
VARIABLE _AGDC-USED
VARIABLE _AGDC-PHYS
VARIABLE _AGDC-CP
VARIABLE _AGDC-CPW
VARIABLE _AGDC-MARK-SPACES
0 _AGDC-MARK-SPACES !

\ Draw a UTF-8 slice according to terminal cell widths.  The screen buffer
\ stores one codepoint per physical slot.  Wide glyphs therefore leave their
\ continuation cell blank so physical placement agrees with wrapping.  A
\ combining mark still needs one representational slot (the screen cannot
\ compose two codepoints into one cell), while USED retains its logical width
\ of zero.  Control bytes are made visible instead of affecting chrome.
: _AG-DRAW-CELLS  ( addr len row col max-cells -- )
    _AGDC-MAX ! _AGDC-COL ! _AGDC-ROW ! _AGDC-U ! _AGDC-A !
    0 _AGDC-USED ! 0 _AGDC-PHYS !
    BEGIN _AGDC-U @ 0> _AGDC-PHYS @ _AGDC-MAX @ < AND WHILE
        _AGDC-A @ _AGDC-U @ UTF8-DECODE
        _AGDC-U ! _AGDC-A ! _AGDC-CP !
        _AGDC-CP @ _AG-CELL-WIDTH _AGDC-CPW !
        _AGDC-USED @ _AGDC-CPW @ + _AGDC-MAX @ > IF
            _AGDC-USED @ 0= _AGDC-MAX @ 0> AND IF
                [CHAR] ? _AGDC-ROW @ _AGDC-COL @ DRW-CHAR
            THEN
            EXIT
        THEN
        _AGDC-MARK-SPACES @ _AGDC-CP @ 32 = AND IF
            0x00B7
        ELSE _AGDC-CP @ DUP 9 = IF DROP 32 ELSE
            DUP 32 < OVER 127 = OR IF DROP [CHAR] ? THEN
        THEN THEN
        _AGDC-ROW @ _AGDC-COL @ _AGDC-PHYS @ + DRW-CHAR
        _AGDC-CPW @ 1 MAX _AGDC-PHYS +!
        _AGDC-CPW @ _AGDC-USED +!
    REPEAT ;

VARIABLE _AGSW-A
VARIABLE _AGSW-U
VARIABLE _AGSW-N

: _AG-SAFE-WIDTH  ( addr len -- cells )
    _AGSW-U ! _AGSW-A ! 0 _AGSW-N !
    BEGIN _AGSW-U @ 0> WHILE
        _AGSW-A @ _AGSW-U @ UTF8-DECODE
        _AGSW-U ! _AGSW-A ! _AG-CELL-WIDTH _AGSW-N +!
    REPEAT
    _AGSW-N @ ;

4096 CONSTANT _AG-REVIEW-JSON-CAP
_AG-REVIEW-JSON-CAP 4 * CONSTANT _AG-REVIEW-VISIBLE-CAP

CREATE _AG-REVIEW-JSON _AG-REVIEW-JSON-CAP ALLOT
CREATE _AG-REVIEW-VISIBLE _AG-REVIEW-VISIBLE-CAP ALLOT
CREATE _AG-REVIEW-DIGEST SHA3-256-HEX-LEN ALLOT

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

VARIABLE _AGRI-G
VARIABLE _AGRI-W
VARIABLE _AGRI-N

: _AGRI-ADD  ( addr len -- )
    _AGRI-W @ _AG-WRAPPED-ROWS _AGRI-N +! ;

: _AGRI-ADD-EXACT  ( addr len -- )
    _AGRI-W @ _AG-EXACT-ROWS _AGRI-N +! ;

: _AG-REVIEW-INPUT-ROWS  ( gateway width -- rows )
    _AGRI-W ! DUP _AGRI-G ! DROP 0 _AGRI-N !
    _AGRI-G @ _AG-FINGERPRINT-LOAD 0= IF
        S" Operand fingerprint unavailable; approval disabled" _AGRI-ADD
        _AGRI-N @ EXIT
    THEN
    S" Canonical bytes:" _AGRI-ADD
    _AGFP-N @ NUM>STR _AGRI-ADD-EXACT
    S" SHA3-256:" _AGRI-ADD
    _AG-FINGERPRINT-HEX _AGRI-ADD-EXACT
    S" Operand (canonical JSON bytes):" _AGRI-ADD
    S" Spaces/non-ASCII use \xHH" _AGRI-ADD
    _AGRI-G @ _AG-INPUT-MODE CASE
        _AG-INPUT-READY OF
            _AGRI-G @ _AG-ARGS-DISPLAY IF
                _AGRI-ADD-EXACT
            ELSE
                2DROP
                S" Operand encoding changed; approval disabled" _AGRI-ADD
            THEN
        ENDOF
        _AG-INPUT-OMITTED OF
            S" Operand exceeds the exact display limit; approval disabled"
                _AGRI-ADD
        ENDOF
        _AG-INPUT-INVALID OF
            S" Operand integrity check failed; approval disabled" _AGRI-ADD
        ENDOF
    ENDCASE
    _AGRI-N @ ;

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
    _AG-ANCHOR-NONE _AG-REVIEW-ANCHOR-STATE !
    0 _AG-REVIEW-REDRAW-PENDING ! ;

\ Every new local or provider review starts at the top of its final
\ conversation message.  The draw pass applies the anchor once it knows the
\ current wrapped height.
: _AG-SYNC-REVIEW  ( -- )
    _AG-REVIEW-IDENTITY DUP _AGSR-REQ ! 0= IF
        \ A resolved review must release its forced top anchor so the
        \ provider's resulting tool message is immediately visible.  Only
        \ reset a scroll position that belongs to a tracked review; an
        \ ordinary transcript with no prior review retains manual scrolling.
        _AG-REVIEW-REQUEST-ID @ IF 0 _AG-SCROLL ! THEN
        _AG-REVIEW-TRACKING-CLEAR EXIT
    THEN
    _AG-RUNTIME @ ARUNTIME.REVISION @ _AGSR-RREV !
    _AG-REVIEW-REQUEST IF
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ ATOOLG.REVISION @
    ELSE
        0
    THEN _AGSR-GREV !
    _AGSR-REQ @ _AG-REVIEW-REQUEST-ID @ =
    _AGSR-GREV @ _AG-REVIEW-GATEWAY-REV @ = AND
    _AGSR-RREV @ _AG-REVIEW-RUNTIME-REV @ = AND IF EXIT THEN
    _AGSR-REQ @ _AG-REVIEW-REQUEST-ID !
    _AGSR-GREV @ _AG-REVIEW-GATEWAY-REV !
    _AGSR-RREV @ _AG-REVIEW-RUNTIME-REV !
    0 _AG-REVIEW-BOTTOM-SEEN !
    0 _AG-REVIEW-REDRAW-PENDING !
    _AG-ANCHOR-PENDING _AG-REVIEW-ANCHOR-STATE !
    _AG-INVALIDATE ;

: _AG-REVIEW-INSPECTED?  ( -- flag )
    _AG-REVIEW-BOTTOM-SEEN @ 0<> ;

: _AG-REVIEW-APPROVABLE?  ( -- flag )
    _AG-REVIEW-REQUEST IF
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ DUP 0= IF DROP 0 EXIT THEN
        _AG-INPUT-REVIEWABLE? _AG-REVIEW-INSPECTED? AND
    ELSE
        _AG-REVIEW-IDENTITY 0<> _AG-REVIEW-INSPECTED? AND
    THEN ;

VARIABLE _AGRR-MSG
VARIABLE _AGRR-W

: _AG-CAP-LABEL  ( cap -- addr len )
    DUP CAP.TITLE-U @ IF
        DUP CAP.TITLE-A @ SWAP CAP.TITLE-U @
    ELSE
        CAP-ID
    THEN ;

VARIABLE _AGRM-REQ
VARIABLE _AGRM-CAP
VARIABLE _AGRM-W
VARIABLE _AGRM-N

: _AG-PROVIDER-REVIEW-ACTION$  ( -- addr len )
    _AG-REVIEW-INSPECTED? IF
        S" [F6] Approve once    [F7] Deny"
    ELSE
        S" F6 locked - PgDn; F7 deny"
    THEN ;

: _AGRM-ADD  ( addr len -- )
    _AGRM-W @ _AG-WRAPPED-ROWS _AGRM-N +! ;

: _AGRM-ADD-EXACT  ( addr len -- )
    _AGRM-W @ _AG-EXACT-ROWS _AGRM-N +! ;

\ Security-relevant envelope metadata is counted with the same wrapping
\ discipline used to draw it.  Approval cannot be unlocked by scrolling past
\ a nominal one-row field whose operation, target, or effects were clipped.
: _AG-REVIEW-METADATA-ROWS  ( request width -- rows )
    _AGRM-W ! DUP _AGRM-REQ ! CBR.CAP @ _AGRM-CAP ! 0 _AGRM-N !
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @
    _AG-INPUT-REVIEWABLE? 0= IF
        S" Operand cannot be approved"
    ELSE _AG-REVIEW-INSPECTED? IF
        S" Operand inspection complete"
    ELSE
        S" PgDn to inspect all rows"
    THEN THEN _AGRM-ADD
    S" Capability:" _AGRM-ADD
    _AGRM-CAP @ _AG-CAP-LABEL _AGRM-ADD
    S" Operation:" _AGRM-ADD
    _AGRM-CAP @ CAP-ID _AGRM-ADD-EXACT
    S" Target instance:" _AGRM-ADD
    _AGRM-REQ @ CBR.TARGET-ID @ NUM>STR _AGRM-ADD-EXACT
    S" Expected revision:" _AGRM-ADD
    _AGRM-REQ @ CBR.EXPECT-REV @ NUM>STR _AGRM-ADD-EXACT
    S" Effects:" _AGRM-ADD
    _AGRM-CAP @ CAP.EFFECTS @
    DUP CAP-E-OBSERVE AND IF S" observe" _AGRM-ADD THEN
    DUP CAP-E-NAVIGATE AND IF S" navigate" _AGRM-ADD THEN
    DUP CAP-E-MUTATE AND IF S" mutate" _AGRM-ADD THEN
    DUP CAP-E-PERSIST AND IF S" persist" _AGRM-ADD THEN
    DUP CAP-E-DESTRUCTIVE AND IF S" destructive" _AGRM-ADD THEN
    CAP-E-EXTERNAL AND IF S" external" _AGRM-ADD THEN
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @
    _AG-INPUT-REVIEWABLE? 0= IF
        S" [F7] Deny - F6 disabled"
    ELSE _AG-REVIEW-INSPECTED? IF
        S" [F6] Approve once  [F7] Deny"
    ELSE
        S" F6 locked - PgDn; F7 deny"
    THEN THEN _AGRM-ADD
    _AGRM-N @ ;

: _AG-REVIEW-ROWS  ( message text-width -- rows )
    _AGRR-W ! DUP _AGRR-MSG !
    AMSG.STATE @ AMSG-S-APPROVAL <> IF 0 EXIT THEN
    _AG-REVIEW-REQUEST ?DUP IF
        _AGRR-W @ _AG-REVIEW-METADATA-ROWS
        _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @
        _AGRR-W @ _AG-REVIEW-INPUT-ROWS +
    ELSE
        S" Provider approval request (no local tool envelope)"
            _AGRR-W @ _AG-WRAPPED-ROWS
        _AG-PROVIDER-REVIEW-ACTION$ _AGRR-W @ _AG-WRAPPED-ROWS +
    THEN ;

VARIABLE _AGMR-MSG
VARIABLE _AGMR-W

: _AG-MESSAGE-ROWS  ( message text-width -- rows )
    _AGMR-W ! DUP _AGMR-MSG ! AMSG-TEXT _AGMR-W @ _AG-WRAPPED-ROWS
    1+ _AGMR-MSG @ _AGMR-W @ _AG-REVIEW-ROWS + ;

VARIABLE _AGRA-W
VARIABLE _AGRA-H
VARIABLE _AGRA-MSG-ROWS

: _AG-CURRENT-REVIEW-MESSAGE-ROWS  ( text-width -- rows )
    >R _AG-RUNTIME @ ARUNTIME.CONVERSATION @
    DUP ACONV.COUNT @ DUP 0= IF 2DROP R> DROP 0 EXIT THEN
    1- SWAP ACONV-NTH DUP AMSG.STATE @ AMSG-S-APPROVAL <> IF
        DROP R> DROP 0 EXIT
    THEN
    R> _AG-MESSAGE-ROWS ;

: _AG-APPLY-REVIEW-ANCHOR  ( text-width height -- )
    _AGRA-H ! _AGRA-W !
    _AG-REVIEW-ANCHOR-STATE @ _AG-ANCHOR-PENDING <> IF EXIT THEN
    _AG-REVIEW-IDENTITY DUP _AG-REVIEW-REQUEST-ID @ <> IF
        DROP _AG-REVIEW-TRACKING-CLEAR EXIT
    THEN
    DROP _AGRA-W @ _AG-CURRENT-REVIEW-MESSAGE-ROWS
    DUP _AGRA-MSG-ROWS ! 0= IF
        \ Runtime revision tracking restarts the anchor when the pending
        \ transcript message is promoted on the following Desk tick.
        _AG-ANCHOR-NONE _AG-REVIEW-ANCHOR-STATE ! EXIT
    THEN
    _AGRA-MSG-ROWS @ _AGRA-H @ - _AG-NONNEG _AG-SCROLL !
    _AG-ANCHOR-APPLIED _AG-REVIEW-ANCHOR-STATE ! ;

\ Inspection state is finalized only after a count-consistent frame has been
\ drawn.  Locked and unlocked prose can wrap to different heights; changing
\ the state during layout would make the row total disagree with the pixels.
: _AG-FINALIZE-REVIEW-BOTTOM  ( -- )
    _AG-REVIEW-BOTTOM-SEEN @ IF EXIT THEN
    _AG-REVIEW-ANCHOR-STATE @ _AG-ANCHOR-APPLIED <> IF EXIT THEN
    _AG-SCROLL @ IF EXIT THEN
    _AG-REVIEW-IDENTITY DUP 0= IF DROP EXIT THEN
    DUP _AG-REVIEW-REQUEST-ID @ <> IF DROP EXIT THEN
    DROP -1 _AG-REVIEW-BOTTOM-SEEN !
    -1 _AG-REVIEW-REDRAW-PENDING ! ;

: _AG-FLUSH-REVIEW-REDRAW  ( -- )
    _AG-REVIEW-REDRAW-PENDING @ 0= IF EXIT THEN
    0 _AG-REVIEW-REDRAW-PENDING ! _AG-INVALIDATE ;

: _AG-MARK-REVIEW-BOTTOM  ( -- )
    _AG-REVIEW-ANCHOR-STATE @ _AG-ANCHOR-APPLIED <> IF EXIT THEN
    _AG-SCROLL @ IF EXIT THEN
    _AG-REVIEW-IDENTITY DUP 0= IF DROP EXIT THEN
    DUP _AG-REVIEW-REQUEST-ID @ <> IF DROP EXIT THEN
    DROP -1 _AG-REVIEW-BOTTOM-SEEN ! ;

VARIABLE _AGTR-W
VARIABLE _AGTR-N

: _AG-TOTAL-ROWS  ( text-width -- rows )
    _AGTR-W ! 0 _AGTR-N !
    _AG-RUNTIME @ ARUNTIME.CONVERSATION @ DUP ACONV.COUNT @ 0 ?DO
        I OVER ACONV-NTH _AGTR-W @ _AG-MESSAGE-ROWS _AGTR-N +!
    LOOP
    DROP _AGTR-N @ ;

VARIABLE _AGLA-TOTAL
VARIABLE _AGLA-W
VARIABLE _AGLA-H

\ SCROLL is measured in visual rows hidden below the viewport.  A zero
\ offset follows the bottom.  Once the user scrolls, row growth and reflow
\ adjust that offset to keep the same top visual row anchored.
: _AG-LAYOUT-ADJUST  ( total width height -- )
    _AGLA-H ! _AGLA-W ! _AGLA-TOTAL !
    _AG-LAYOUT-W @ 0<> _AG-SCROLL @ 0> AND IF
        _AG-SCROLL @
        _AGLA-TOTAL @ _AG-LAYOUT-ROWS @ - +
        _AGLA-H @ _AG-LAYOUT-H @ - - _AG-NONNEG _AG-SCROLL !
    THEN
    _AGLA-TOTAL @ _AGLA-H @ - _AG-NONNEG
    _AG-SCROLL @ MIN _AG-SCROLL !
    _AGLA-TOTAL @ _AG-LAYOUT-ROWS !
    _AGLA-W @ _AG-LAYOUT-W ! _AGLA-H @ _AG-LAYOUT-H ! ;

: _AGD-VISIBLE?  ( -- flag )
    _AGD-LINE @ _AGD-START @ >= _AGD-LINE @ _AGD-END @ < AND ;

: _AGD-ROW  ( -- row ) _AGD-LINE @ _AGD-START @ - ;

: _AG-DRAW-ROW  ( addr len col -- )
    >R
    _AGD-VISIBLE? IF
        _AGD-ROW R@ _AGD-W @ R@ - 1 MAX _AG-DRAW-CELLS
    ELSE
        2DROP
    THEN
    R> DROP 1 _AGD-LINE +! ;

: _AG-DRAW-HEADER  ( message -- )
    DUP _AGD-MSG ! AMSG.ROLE @ DUP _AG-ROLE-STYLE _AG-ROLE-TEXT
    _AGD-VISIBLE? IF
        _AGD-ROW 1 _AGD-W @ 2 - 1 MAX _AG-DRAW-CELLS
        _AGD-MSG @ AMSG.STATE @ CASE
            AMSG-S-STREAMING OF
                244 234 0 DRW-STYLE! S" ..." _AGD-ROW 9 4 _AG-DRAW-CELLS
            ENDOF
            AMSG-S-APPROVAL OF
                220 234 1 DRW-STYLE! S" REVIEW" _AGD-ROW 9 6 _AG-DRAW-CELLS
            ENDOF
            AMSG-S-ERROR OF
                203 234 1 DRW-STYLE! S" ERROR" _AGD-ROW 9 5 _AG-DRAW-CELLS
            ENDOF
            AMSG-S-CANCELLED OF
                244 234 0 DRW-STYLE! S" CANCELLED" _AGD-ROW 9 9 _AG-DRAW-CELLS
            ENDOF
        ENDCASE
    ELSE
        2DROP
    THEN
    1 _AGD-LINE +! ;

VARIABLE _AGRV-REQ
VARIABLE _AGRV-CAP

: _AG-DRAW-REVIEW-WRAPPED  ( addr len -- )
    _AGD-TEXT-W @ _AG-WRAP-INIT
    BEGIN _AG-WRAP-NEXT WHILE
        2 _AG-DRAW-ROW
    REPEAT ;

: _AG-DRAW-REVIEW-EXACT  ( addr len -- )
    _AGD-TEXT-W @ _AG-WRAP-EXACT-INIT
    -1 _AGDC-MARK-SPACES !
    BEGIN _AG-WRAP-NEXT WHILE
        2 _AG-DRAW-ROW
    REPEAT
    0 _AGDC-MARK-SPACES ! ;

VARIABLE _AGRV-G

: _AG-DRAW-CANONICAL-BYTES  ( -- )
    S" Canonical bytes:" _AG-DRAW-REVIEW-WRAPPED
    _AGFP-N @ NUM>STR _AG-DRAW-REVIEW-EXACT ;

: _AG-DRAW-REVIEW-INPUT  ( gateway -- )
    DUP _AGRV-G ! _AG-FINGERPRINT-LOAD 0= IF
        203 234 1 DRW-STYLE!
        S" Operand fingerprint unavailable; approval disabled"
            _AG-DRAW-REVIEW-WRAPPED
        220 234 1 DRW-STYLE!
        EXIT
    THEN
    _AG-DRAW-CANONICAL-BYTES
    S" SHA3-256:" _AG-DRAW-REVIEW-WRAPPED
    _AG-FINGERPRINT-HEX _AG-DRAW-REVIEW-EXACT
    S" Operand (canonical JSON bytes):" _AG-DRAW-REVIEW-WRAPPED
    S" Spaces/non-ASCII use \xHH" _AG-DRAW-REVIEW-WRAPPED
    _AGRV-G @ _AG-INPUT-MODE CASE
        _AG-INPUT-READY OF
            _AGRV-G @ _AG-ARGS-DISPLAY IF
                117 234 0 DRW-STYLE!
                _AG-DRAW-REVIEW-EXACT
                220 234 1 DRW-STYLE!
            ELSE
                2DROP 203 234 1 DRW-STYLE!
                S" Operand encoding changed; approval disabled"
                    _AG-DRAW-REVIEW-WRAPPED
                220 234 1 DRW-STYLE!
            THEN
        ENDOF
        _AG-INPUT-OMITTED OF
            203 234 1 DRW-STYLE!
            S" Operand exceeds the exact display limit; approval disabled"
                _AG-DRAW-REVIEW-WRAPPED
            220 234 1 DRW-STYLE!
        ENDOF
        _AG-INPUT-INVALID OF
            203 234 1 DRW-STYLE!
            S" Operand integrity check failed; approval disabled"
                _AG-DRAW-REVIEW-WRAPPED
            220 234 1 DRW-STYLE!
        ENDOF
    ENDCASE ;

: _AG-DRAW-LOCAL-REVIEW  ( request -- )
    DUP _AGRV-REQ ! CBR.CAP @ _AGRV-CAP !
    220 234 1 DRW-STYLE!
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @
    _AG-INPUT-REVIEWABLE? 0= IF
        S" Operand cannot be approved"
    ELSE _AG-REVIEW-INSPECTED? IF
        S" Operand inspection complete"
    ELSE
        S" PgDn to inspect all rows"
    THEN THEN _AG-DRAW-REVIEW-WRAPPED
    S" Capability:" _AG-DRAW-REVIEW-WRAPPED
    _AGRV-CAP @ _AG-CAP-LABEL _AG-DRAW-REVIEW-WRAPPED
    S" Operation:" _AG-DRAW-REVIEW-WRAPPED
    _AGRV-CAP @ CAP-ID _AG-DRAW-REVIEW-EXACT
    S" Target instance:" _AG-DRAW-REVIEW-WRAPPED
    _AGRV-REQ @ CBR.TARGET-ID @ NUM>STR _AG-DRAW-REVIEW-EXACT
    S" Expected revision:" _AG-DRAW-REVIEW-WRAPPED
    _AGRV-REQ @ CBR.EXPECT-REV @ NUM>STR _AG-DRAW-REVIEW-EXACT
    S" Effects:" _AG-DRAW-REVIEW-WRAPPED
    _AGRV-CAP @ CAP.EFFECTS @
    DUP CAP-E-OBSERVE AND IF S" observe" _AG-DRAW-REVIEW-WRAPPED THEN
    DUP CAP-E-NAVIGATE AND IF S" navigate" _AG-DRAW-REVIEW-WRAPPED THEN
    DUP CAP-E-MUTATE AND IF S" mutate" _AG-DRAW-REVIEW-WRAPPED THEN
    DUP CAP-E-PERSIST AND IF S" persist" _AG-DRAW-REVIEW-WRAPPED THEN
    DUP CAP-E-DESTRUCTIVE AND IF S" destructive" _AG-DRAW-REVIEW-WRAPPED THEN
    CAP-E-EXTERNAL AND IF S" external" _AG-DRAW-REVIEW-WRAPPED THEN
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @ _AG-DRAW-REVIEW-INPUT
    _AG-RUNTIME @ ARUNTIME.TOOL-GATEWAY @
    _AG-INPUT-REVIEWABLE? 0= IF
        S" [F7] Deny - F6 disabled"
    ELSE _AG-REVIEW-INSPECTED? IF
        S" [F6] Approve once  [F7] Deny"
    ELSE
        S" F6 locked - PgDn; F7 deny"
    THEN THEN _AG-DRAW-REVIEW-WRAPPED ;

: _AG-DRAW-PROVIDER-REVIEW  ( -- )
    220 234 1 DRW-STYLE!
    S" Provider approval request (no local tool envelope)"
        _AG-DRAW-REVIEW-WRAPPED
    _AG-PROVIDER-REVIEW-ACTION$ _AG-DRAW-REVIEW-WRAPPED ;

: _AG-DRAW-REVIEW  ( -- )
    _AG-REVIEW-REQUEST ?DUP IF
        _AG-DRAW-LOCAL-REVIEW
    ELSE
        _AG-DRAW-PROVIDER-REVIEW
    THEN ;

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
    _AG-RUNTIME @ ARUNTIME.CONVERSATION @ ACONV.COUNT @ _AGD-COUNT !
    _AGD-W @ 4 - 1 MAX _AGD-TEXT-W !
    _AGD-TEXT-W @ _AG-TOTAL-ROWS DUP _AGD-TOTAL !
    _AGD-W @ _AGD-H @ _AG-LAYOUT-ADJUST
    _AGD-TEXT-W @ _AGD-H @ _AG-APPLY-REVIEW-ANCHOR
    _AGD-TOTAL @ _AGD-H @ - _AG-SCROLL @ - _AG-NONNEG _AGD-START !
    _AGD-START @ _AGD-H @ + _AGD-TOTAL @ MIN _AGD-END !
    0 _AGD-I ! 0 _AGD-LINE !
    BEGIN
        _AGD-I @ _AGD-COUNT @ < _AGD-LINE @ _AGD-END @ < AND
    WHILE
        _AGD-I @ _AG-RUNTIME @ ARUNTIME.CONVERSATION @ ACONV-NTH
        DUP _AGD-MSG ! _AG-DRAW-HEADER
        253 234 0 DRW-STYLE!
        _AGD-MSG @ AMSG-TEXT _AGD-TEXT-W @ _AG-WRAP-INIT
        BEGIN _AG-WRAP-NEXT WHILE
            2 _AG-DRAW-ROW
        REPEAT
        _AGD-MSG @ AMSG.STATE @ AMSG-S-APPROVAL = IF
            _AG-DRAW-REVIEW
        THEN
        1 _AGD-I +!
    REPEAT
    _AGD-COUNT @ 0= IF
        244 234 0 DRW-STYLE!
        S" Start a conversation" 1 2 DRW-TEXT
    THEN
    _AG-FINALIZE-REVIEW-BOTTOM
    DRW-STYLE-RESET ;

VARIABLE _AGH-WIDGET

: _AG-PANEL-HANDLE  ( event widget -- consumed? )
    _AGH-WIDGET !
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-ENTER OF _AG-SHOW-PROMPT -1 EXIT ENDOF
            KEY-UP OF
                _AG-SCROLL @ 1+ _AG-LAYOUT-ROWS @ _AG-LAYOUT-H @ -
                _AG-NONNEG MIN _AG-SCROLL ! _AG-INVALIDATE -1 EXIT
            ENDOF
            KEY-DOWN OF
                _AG-SCROLL @ 1- _AG-NONNEG _AG-SCROLL !
                _AG-MARK-REVIEW-BOTTOM _AG-INVALIDATE -1 EXIT
            ENDOF
            KEY-PGUP OF
                _AG-SCROLL @ _AG-LAYOUT-H @ 1- 1 MAX +
                _AG-LAYOUT-ROWS @ _AG-LAYOUT-H @ - _AG-NONNEG MIN
                _AG-SCROLL ! _AG-INVALIDATE -1 EXIT
            ENDOF
            KEY-PGDN OF
                _AG-SCROLL @ _AG-LAYOUT-H @ 1- 1 MAX - _AG-NONNEG
                _AG-SCROLL ! _AG-MARK-REVIEW-BOTTOM _AG-INVALIDATE -1 EXIT
            ENDOF
            KEY-ESC OF _AG-RUNTIME @ ARUNTIME-CANCEL DROP _AG-INVALIDATE -1 EXIT ENDOF
        ENDCASE
        0 EXIT
    THEN
    DROP 0 ;

: _AG-PANEL-INIT  ( region -- )
    DUP _AG-PANEL-RGN !
    _AG-PANEL 41 ROT
    ['] _AG-PANEL-DRAW ['] _AG-PANEL-HANDLE WDG-INIT ;

: _AG-DO-PROMPT  ( elem -- ) DROP _AG-SHOW-PROMPT ;
: _AG-DO-CANCEL  ( elem -- ) DROP _AG-RUNTIME @ ARUNTIME-CANCEL DROP _AG-INVALIDATE ;
VARIABLE _AG-REVIEW-APPROVED

: _AG-RESOLVE-REVIEW  ( approved -- )
    _AG-REVIEW-APPROVED !
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
    0 _AG-SCROLL ! _AG-INVALIDATE ;

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
    0 _AG-SCROLL ! 0 _AG-LAYOUT-ROWS ! 0 _AG-LAYOUT-W ! 0 _AG-LAYOUT-H !
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
    _AG-PANEL-RGN @ ?DUP IF RGN-FREE THEN
    _AG-OWNS-RUNTIME @ IF
        _AG-RUNTIME @ ARUNTIME-FREE
        _AG-PROVIDER @ APROV-FREE
        _AG-SOURCE @ APSOURCE-FREE
    THEN
    0 _AG-RUNTIME ! 0 _AG-PROVIDER ! 0 _AG-SOURCE ! 0 _AG-PROMPT !
    0 _AG-AUTH-PANEL ! 0 _AG-SETTINGS-PANEL ! ;

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
