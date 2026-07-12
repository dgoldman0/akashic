\ =====================================================================
\  agent-auth.f - Non-blocking provider account panel
\ =====================================================================
\  This is a TUI projection of the provider-neutral auth/runtime ports.
\  It never owns credentials, auth protocol state, the runtime, or its region.
\ =====================================================================

PROVIDED akashic-tui-agent-auth

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../keys.f
REQUIRE ../../agent/runtime.f

40 CONSTANT _AAUP-RUNTIME
48 CONSTANT _AAUP-AUTH-REVISION
56 CONSTANT _AAUP-LAST-STATUS
64 CONSTANT _AAUP-CLOSE-XT
72 CONSTANT AGENT-AUTH-PANEL-SIZE

: AAUTHP.RUNTIME       ( panel -- a ) _AAUP-RUNTIME + ;
: AAUTHP.AUTH-REVISION ( panel -- a ) _AAUP-AUTH-REVISION + ;
: AAUTHP.LAST-STATUS   ( panel -- a ) _AAUP-LAST-STATUS + ;
: AAUTHP.CLOSE-XT      ( panel -- a ) _AAUP-CLOSE-XT + ;

VARIABLE _AAUP-W
VARIABLE _AAUP-H
VARIABLE _AAUP-P
VARIABLE _AAUP-AUTH
VARIABLE _AAUP-ROW
VARIABLE _AAUP-COL

: _AAUP-TEXT  ( addr len row col -- )
    DRW-TEXT ;

: _AAUP-VALUE-TEXT  ( value row col -- )
    _AAUP-COL ! _AAUP-ROW !
    DUP CV-TYPE@ CV-T-STRING = IF
        DUP CV-DATA@ SWAP CV-LEN@
        _AAUP-ROW @ _AAUP-COL @ _AAUP-TEXT
    ELSE
        DROP
    THEN ;

: _AAUP-HEADER  ( title-a title-u -- )
    15 24 1 DRW-STYLE!
    32 0 0 1 _AAUP-W @ DRW-FILL-RECT
    0 2 _AAUP-TEXT ;

: _AAUP-FOOTER  ( addr len -- )
    253 236 0 DRW-STYLE!
    32 _AAUP-H @ 1- 0 1 _AAUP-W @ DRW-FILL-RECT
    _AAUP-H @ 1- 2 _AAUP-TEXT ;

: _AAUP-DRAW-SIGNED-OUT  ( -- )
    253 234 0 DRW-STYLE!
    S" No account is connected." 3 3 _AAUP-TEXT
    _AAUP-AUTH @ AAUTH.METHODS @ AAUTH-M-DEVICE AND IF
        81 234 1 DRW-STYLE!
        S" Start sign-in" 6 3 _AAUP-TEXT
        S" Start sign-in   Close" _AAUP-FOOTER
    ELSE
        244 234 0 DRW-STYLE!
        S" This provider accepts a private credential." 5 3 _AAUP-TEXT
        S" Close" _AAUP-FOOTER
    THEN ;

: _AAUP-DRAW-PENDING  ( -- )
    244 234 0 DRW-STYLE!
    S" Browser authorization is pending." 3 3 _AAUP-TEXT
    253 234 1 DRW-STYLE!
    S" Address" 5 3 _AAUP-TEXT
    81 234 0 DRW-STYLE!
    _AAUP-AUTH @ AAUTH.VERIFY-URI 6 3 _AAUP-VALUE-TEXT
    253 234 1 DRW-STYLE!
    S" Code" 8 3 _AAUP-TEXT
    15 24 1 DRW-STYLE!
    32 9 3 1 _AAUP-W @ 6 - 1 MAX DRW-FILL-RECT
    _AAUP-AUTH @ AAUTH.USER-CODE 9 5 _AAUP-VALUE-TEXT
    S" Waiting for authorization   Cancel   Close" _AAUP-FOOTER ;

: _AAUP-DRAW-READY  ( -- )
    42 234 1 DRW-STYLE!
    S" Connected" 3 3 _AAUP-TEXT
    253 234 1 DRW-STYLE!
    S" Account" 5 3 _AAUP-TEXT
    253 234 0 DRW-STYLE!
    _AAUP-AUTH @ AAUTH.ACCOUNT-LABEL 5 15 _AAUP-VALUE-TEXT
    253 234 1 DRW-STYLE!
    S" Plan" 7 3 _AAUP-TEXT
    253 234 0 DRW-STYLE!
    _AAUP-AUTH @ AAUTH.PLAN 7 15 _AAUP-VALUE-TEXT
    S" Close   Sign out" _AAUP-FOOTER ;

: _AAUP-DRAW-ERROR  ( -- )
    203 234 1 DRW-STYLE!
    S" Sign-in failed" 3 3 _AAUP-TEXT
    253 234 0 DRW-STYLE!
    _AAUP-AUTH @ AAUTH.ERROR 5 3 _AAUP-VALUE-TEXT
    S" Retry sign-in   Close" _AAUP-FOOTER ;

: _AAUP-DRAW  ( panel -- )
    DUP _AAUP-P ! WDG-REGION DUP RGN-W _AAUP-W ! RGN-H _AAUP-H !
    253 234 0 DRW-STYLE!
    32 0 0 _AAUP-H @ _AAUP-W @ DRW-FILL-RECT
    S" Agent account" _AAUP-HEADER
    _AAUP-P @ AAUTHP.RUNTIME @ ARUNTIME-AUTH DUP _AAUP-AUTH !
    DUP 0= IF
        DROP 244 234 0 DRW-STYLE!
        S" This provider has no account interface." 3 3 _AAUP-TEXT
        S" Close" _AAUP-FOOTER DRW-STYLE-RESET EXIT
    THEN
    AAUTH.STATE @ CASE
        AAUTH-STATE-SIGNED-OUT OF _AAUP-DRAW-SIGNED-OUT ENDOF
        AAUTH-STATE-STARTING OF
            244 234 0 DRW-STYLE!
            S" Contacting the sign-in service..." 3 3 _AAUP-TEXT
            S" Cancel   Close" _AAUP-FOOTER
        ENDOF
        AAUTH-STATE-PENDING OF _AAUP-DRAW-PENDING ENDOF
        AAUTH-STATE-READY OF _AAUP-DRAW-READY ENDOF
        AAUTH-STATE-REFRESHING OF
            244 234 0 DRW-STYLE!
            S" Refreshing account access..." 3 3 _AAUP-TEXT
            S" Cancel   Close" _AAUP-FOOTER
        ENDOF
        AAUTH-STATE-ERROR OF _AAUP-DRAW-ERROR ENDOF
        244 234 0 DRW-STYLE!
        S" Account access is unavailable." 3 3 _AAUP-TEXT
        S" Close" _AAUP-FOOTER
    ENDCASE
    DRW-STYLE-RESET ;

: _AAUP-CLOSE  ( panel -- )
    DUP WDG-HIDE
    DUP AAUTHP.CLOSE-XT @ ?DUP IF EXECUTE ELSE DROP THEN ;

VARIABLE _AAUP-H-P
VARIABLE _AAUP-H-E
VARIABLE _AAUP-H-CODE

: _AAUP-BEGIN  ( panel -- )
    DUP _AAUP-H-P ! AAUTHP.RUNTIME @ ARUNTIME-AUTH-BEGIN
    _AAUP-H-P @ AAUTHP.LAST-STATUS ! _AAUP-H-P @ WDG-DIRTY ;

: _AAUP-ACTION  ( code panel -- consumed? )
    _AAUP-H-P ! _AAUP-H-CODE !
    _AAUP-H-P @ AAUTHP.RUNTIME @ ARUNTIME-AUTH DUP 0= IF
        DROP -1 EXIT
    THEN
    AAUTH.STATE @ _AAUP-H-E !
    _AAUP-H-CODE @ DUP [CHAR] c = SWAP [CHAR] C = OR IF
        _AAUP-H-E @ DUP AAUTH-STATE-STARTING =
        OVER AAUTH-STATE-PENDING = OR
        SWAP AAUTH-STATE-REFRESHING = OR IF
            _AAUP-H-P @ AAUTHP.RUNTIME @ ARUNTIME-AUTH-CANCEL
            _AAUP-H-P @ AAUTHP.LAST-STATUS !
            _AAUP-H-P @ WDG-DIRTY
        THEN
        -1 EXIT
    THEN
    _AAUP-H-CODE @ DUP [CHAR] l = SWAP [CHAR] L = OR IF
        _AAUP-H-E @ AAUTH-STATE-READY = IF
            _AAUP-H-P @ AAUTHP.RUNTIME @ ARUNTIME-AUTH-CLEAR
            _AAUP-H-P @ AAUTHP.LAST-STATUS !
            _AAUP-H-P @ WDG-DIRTY
        THEN
        -1 EXIT
    THEN
    0 ;

: _AAUP-HANDLE  ( event panel -- consumed? )
    _AAUP-H-P ! DUP _AAUP-H-E !
    DUP KEY-IS-SPECIAL? IF
        KEY-CODE@ CASE
            KEY-ESC OF _AAUP-H-P @ _AAUP-CLOSE -1 ENDOF
            KEY-ENTER OF
                _AAUP-H-P @ AAUTHP.RUNTIME @ ARUNTIME-AUTH DUP 0= IF
                    DROP -1
                ELSE
                    AAUTH.STATE @ DUP AAUTH-STATE-SIGNED-OUT =
                    OVER AAUTH-STATE-ERROR = OR IF
                        DROP _AAUP-H-P @ _AAUP-BEGIN
                    ELSE
                        AAUTH-STATE-READY = IF _AAUP-H-P @ _AAUP-CLOSE THEN
                    THEN
                    -1
                THEN
            ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    KEY-IS-CHAR? IF
        _AAUP-H-E @ KEY-CODE@ _AAUP-H-P @ _AAUP-ACTION EXIT
    THEN
    0 ;

VARIABLE _AAUP-N-RUNTIME
VARIABLE _AAUP-N-RGN

: AAUTHP-NEW  ( runtime region -- panel )
    _AAUP-N-RGN ! _AAUP-N-RUNTIME !
    AGENT-AUTH-PANEL-SIZE ALLOCATE
    0<> ABORT" AAUTHP-NEW: alloc failed"
    DUP AGENT-AUTH-PANEL-SIZE 0 FILL
    DUP WDG-T-AGENT-AUTH _AAUP-N-RGN @
    ['] _AAUP-DRAW ['] _AAUP-HANDLE _WDG-INIT
    _AAUP-N-RUNTIME @ OVER AAUTHP.RUNTIME !
    DUP AAUTHP.RUNTIME @ ARUNTIME-AUTH ?DUP IF
        AAUTH.REVISION @ OVER AAUTHP.AUTH-REVISION !
    THEN
    DUP WDG-HIDE ;

: AAUTHP-SHOW  ( panel -- )
    0 OVER AAUTHP.LAST-STATUS ! WDG-SHOW ;

: AAUTHP-ACTIVE?  ( panel -- flag ) WDG-VISIBLE? ;

: AAUTHP-SYNC  ( panel -- changed? )
    DUP _AAUP-P ! AAUTHP.RUNTIME @ ARUNTIME-AUTH DUP 0= IF
        DROP 0 EXIT
    THEN
    AAUTH.REVISION @ DUP _AAUP-P @ AAUTHP.AUTH-REVISION @ = IF
        DROP 0 EXIT
    THEN
    _AAUP-P @ AAUTHP.AUTH-REVISION !
    _AAUP-P @ WDG-DIRTY -1 ;

: AAUTHP-ON-CLOSE  ( xt panel -- ) AAUTHP.CLOSE-XT ! ;

: AAUTHP-FREE  ( panel -- ) FREE ;
