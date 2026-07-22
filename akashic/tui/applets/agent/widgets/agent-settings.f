\ =====================================================================
\  agent-settings.f - Provider-neutral model and run settings panel
\ =====================================================================
\  The widget borrows a runtime and region. Providers retain all catalog
\  descriptors, while runtime wrappers enforce active-run safety.
\ =====================================================================

PROVIDED akashic-tui-agent-settings

REQUIRE ../../../widget.f
REQUIRE ../../../draw.f
REQUIRE ../../../keys.f
REQUIRE ../runtime.f

40 CONSTANT _ARSP-RUNTIME
48 CONSTANT _ARSP-ROW
56 CONSTANT _ARSP-REVISION
64 CONSTANT _ARSP-LAST-STATUS
72 CONSTANT _ARSP-CLOSE-XT
80 CONSTANT AGENT-SETTINGS-PANEL-SIZE

: ARSP.RUNTIME     ( panel -- a ) _ARSP-RUNTIME + ;
: ARSP.ROW         ( panel -- a ) _ARSP-ROW + ;
: ARSP.REVISION    ( panel -- a ) _ARSP-REVISION + ;
: ARSP.LAST-STATUS ( panel -- a ) _ARSP-LAST-STATUS + ;
: ARSP.CLOSE-XT    ( panel -- a ) _ARSP-CLOSE-XT + ;

VARIABLE _ARSP-P
VARIABLE _ARSP-S
VARIABLE _ARSP-M
VARIABLE _ARSP-W
VARIABLE _ARSP-H
VARIABLE _ARSP-I
VARIABLE _ARSP-N
VARIABLE _ARSP-POS
VARIABLE _ARSP-DELTA
VARIABLE _ARSP-STATUS
VARIABLE _ARSP-LA
VARIABLE _ARSP-LU
VARIABLE _ARSP-VA
VARIABLE _ARSP-VU
VARIABLE _ARSP-ROW-I

: _ARSP-TEXT  ( addr len row col -- ) DRW-TEXT ;

: _ARSP-HEADER  ( -- )
    15 24 1 DRW-STYLE!
    32 0 0 1 _ARSP-W @ DRW-FILL-RECT
    S" Run settings" 0 2 _ARSP-TEXT ;

: _ARSP-FOOTER  ( addr len -- )
    253 236 0 DRW-STYLE!
    32 _ARSP-H @ 1- 0 1 _ARSP-W @ DRW-FILL-RECT
    _ARSP-H @ 1- 2 _ARSP-TEXT ;

: _ARSP-ROW-STYLE  ( row-index -- )
    _ARSP-P @ ARSP.ROW @ = IF
        15 24 1 DRW-STYLE!
    ELSE
        253 234 0 DRW-STYLE!
    THEN ;

: _ARSP-CHOICE-SELECTED  ( model efforts? -- index )
    >R _ARSP-M !
    _ARSP-M @ 0= IF R> DROP -1 EXIT THEN
    R@ IF
        _ARSP-M @ ARMODEL.EFFORTS-N @
    ELSE
        _ARSP-M @ ARMODEL.TIERS-N @
    THEN
    _ARSP-N ! 0 _ARSP-I !
    BEGIN _ARSP-I @ _ARSP-N @ < WHILE
        _ARSP-I @ _ARSP-M @
        R@ IF ARMODEL-EFFORT-NTH ELSE ARMODEL-TIER-NTH THEN
        DUP IF ARCH.FLAGS @ ARCH-F-SELECTED AND IF
            R> DROP _ARSP-I @ EXIT
        THEN ELSE DROP THEN
        1 _ARSP-I +!
    REPEAT
    R> DROP -1 ;

: _ARSP-VERB-TEXT  ( verbosity -- addr len )
    CASE
        ARVERB-AUTO OF S" Auto" ENDOF
        ARVERB-LOW OF S" Low" ENDOF
        ARVERB-MEDIUM OF S" Medium" ENDOF
        ARVERB-HIGH OF S" High" ENDOF
        DROP S" Auto"
    ENDCASE ;

: _ARSP-DRAW-ROW  ( label-a label-u value-a value-u index -- )
    _ARSP-ROW-I ! _ARSP-VU ! _ARSP-VA ! _ARSP-LU ! _ARSP-LA !
    _ARSP-ROW-I @ _ARSP-ROW-STYLE
    32 _ARSP-ROW-I @ 2 * 3 + 1 1 _ARSP-W @ 2 - DRW-FILL-RECT
    _ARSP-LA @ _ARSP-LU @ _ARSP-ROW-I @ 2 * 3 + 3 _ARSP-TEXT
    _ARSP-VA @ _ARSP-VU @ _ARSP-ROW-I @ 2 * 3 + 19 _ARSP-TEXT ;

: _ARSP-DRAW-READY  ( -- )
    _ARSP-S @ ARSET-SELECTED-MODEL DUP _ARSP-M !
    DUP IF ARMODEL-LABEL ELSE DROP S" No model" THEN
    S" Model" 2SWAP 0 _ARSP-DRAW-ROW

    _ARSP-M @ 0= IF S" Unavailable" ELSE
        _ARSP-M @ -1 _ARSP-CHOICE-SELECTED DUP 0< IF
            DROP S" Default"
        ELSE
            _ARSP-M @ ARMODEL-EFFORT-NTH ARCH-LABEL
        THEN
    THEN
    S" Reasoning" 2SWAP 1 _ARSP-DRAW-ROW

    _ARSP-M @ 0 _ARSP-CHOICE-SELECTED DUP 0< IF
        DROP S" Standard"
    ELSE
        _ARSP-M @ ARMODEL-TIER-NTH ARCH-LABEL
    THEN
    S" Speed" 2SWAP 2 _ARSP-DRAW-ROW

    _ARSP-M @ ARMODEL.FLAGS @ ARMODEL-F-VERBOSITY AND IF
        _ARSP-S @ ARSET.VERBOSITY @ _ARSP-VERB-TEXT
    ELSE
        S" Not supported"
    THEN
    S" Verbosity" 2SWAP 3 _ARSP-DRAW-ROW

    244 234 0 DRW-STYLE!
    _ARSP-M @ IF
        _ARSP-P @ ARSP.ROW @ CASE
            0 OF _ARSP-M @ ARMODEL-DESC ENDOF
            1 OF
                _ARSP-M @ -1 _ARSP-CHOICE-SELECTED DUP 0< IF
                    DROP 0 0
                ELSE
                    _ARSP-M @ ARMODEL-EFFORT-NTH ARCH-DESC
                THEN
            ENDOF
            2 OF
                _ARSP-M @ 0 _ARSP-CHOICE-SELECTED DUP 0< IF
                    DROP S" Standard response speed"
                ELSE
                    _ARSP-M @ ARMODEL-TIER-NTH ARCH-DESC
                THEN
            ENDOF
            DROP 0 0
        ENDCASE
        12 3 _ARSP-TEXT
    THEN
    S" Refresh catalog   Close" _ARSP-FOOTER ;

: _ARSP-DRAW  ( panel -- )
    DUP _ARSP-P ! WDG-REGION DUP RGN-W _ARSP-W ! RGN-H _ARSP-H !
    253 234 0 DRW-STYLE!
    32 0 0 _ARSP-H @ _ARSP-W @ DRW-FILL-RECT
    _ARSP-HEADER
    _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS DUP _ARSP-S !
    DUP 0= IF
        DROP 244 234 0 DRW-STYLE!
        S" This provider exposes no run settings." 3 3 _ARSP-TEXT
        S" Close" _ARSP-FOOTER DRW-STYLE-RESET EXIT
    THEN
    ARSET.STATE @ CASE
        ARSET-STATE-EMPTY OF
            244 234 0 DRW-STYLE!
            S" The model catalog has not been loaded." 3 3 _ARSP-TEXT
            S" Refresh catalog   Close" _ARSP-FOOTER
        ENDOF
        ARSET-STATE-LOADING OF
            244 234 0 DRW-STYLE!
            S" Loading available models..." 3 3 _ARSP-TEXT
            S" Cancel refresh   Close" _ARSP-FOOTER
        ENDOF
        ARSET-STATE-READY OF _ARSP-DRAW-READY ENDOF
        ARSET-STATE-ERROR OF
            203 234 1 DRW-STYLE!
            S" Model catalog failed" 3 3 _ARSP-TEXT
            253 234 0 DRW-STYLE!
            _ARSP-S @ ARSET-ERROR 5 3 _ARSP-TEXT
            S" Retry refresh   Close" _ARSP-FOOTER
        ENDOF
    ENDCASE
    DRW-STYLE-RESET ;

: _ARSP-WRAP  ( value delta count -- value' )
    _ARSP-N ! _ARSP-DELTA ! _ARSP-POS !
    _ARSP-N @ 0= IF 0 EXIT THEN
    _ARSP-POS @ _ARSP-DELTA @ + _ARSP-N @ + _ARSP-N @ MOD ;

: _ARSP-EFFORT-INDEX  ( model -- index )
    -1 _ARSP-CHOICE-SELECTED ;

: _ARSP-TIER-INDEX  ( model -- index )
    0 _ARSP-CHOICE-SELECTED ;

: _ARSP-CYCLE  ( delta panel -- )
    _ARSP-P ! _ARSP-DELTA !
    _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS DUP _ARSP-S !
    DUP 0= IF DROP EXIT THEN
    ARSET.STATE @ ARSET-STATE-READY <> IF EXIT THEN
    _ARSP-S @ ARSET-SELECTED-MODEL DUP _ARSP-M ! 0= IF EXIT THEN
    _ARSP-P @ ARSP.ROW @ CASE
        0 OF
            _ARSP-S @ ARSET.SELECTED @ _ARSP-DELTA @
            _ARSP-S @ ARSET.MODELS-N @ _ARSP-WRAP
            _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-MODEL!
        ENDOF
        1 OF
            _ARSP-M @ ARMODEL.EFFORTS-N @ DUP _ARSP-N ! 0= IF
                ARSET-S-UNSUPPORTED
            ELSE
                _ARSP-M @ _ARSP-EFFORT-INDEX _ARSP-DELTA @ _ARSP-N @
                _ARSP-WRAP _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-EFFORT!
            THEN
        ENDOF
        2 OF
            _ARSP-M @ _ARSP-TIER-INDEX 1+ _ARSP-DELTA @
            _ARSP-M @ ARMODEL.TIERS-N @ 1+ _ARSP-WRAP 1-
            _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-TIER!
        ENDOF
        3 OF
            _ARSP-S @ ARSET.VERBOSITY @ _ARSP-DELTA @ 4 _ARSP-WRAP
            _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-VERBOSITY!
        ENDOF
        ARSET-S-INVALID SWAP
    ENDCASE
    _ARSP-P @ ARSP.LAST-STATUS ! _ARSP-P @ WDG-DIRTY ;

: _ARSP-REFRESH  ( panel -- )
    DUP _ARSP-P ! ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS-REFRESH
    _ARSP-P @ ARSP.LAST-STATUS ! _ARSP-P @ WDG-DIRTY ;

: _ARSP-CLOSE  ( panel -- )
    DUP WDG-HIDE
    DUP ARSP.CLOSE-XT @ ?DUP IF EXECUTE ELSE DROP THEN ;

VARIABLE _ARSP-H-P

: _ARSP-HANDLE  ( event panel -- consumed? )
    _ARSP-H-P ! DUP KEY-IS-SPECIAL? IF
        KEY-CODE@ CASE
            KEY-ESC OF _ARSP-H-P @ _ARSP-CLOSE -1 ENDOF
            KEY-UP OF
                _ARSP-H-P @ ARSP.ROW @ 3 + 4 MOD
                _ARSP-H-P @ ARSP.ROW ! _ARSP-H-P @ WDG-DIRTY -1
            ENDOF
            KEY-DOWN OF
                _ARSP-H-P @ ARSP.ROW @ 1+ 4 MOD
                _ARSP-H-P @ ARSP.ROW ! _ARSP-H-P @ WDG-DIRTY -1
            ENDOF
            KEY-LEFT OF -1 _ARSP-H-P @ _ARSP-CYCLE -1 ENDOF
            KEY-RIGHT OF 1 _ARSP-H-P @ _ARSP-CYCLE -1 ENDOF
            KEY-ENTER OF
                _ARSP-H-P @ ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS
                DUP IF ARSET.STATE @ ARSET-STATE-READY <> ELSE DROP -1 THEN
                IF _ARSP-H-P @ _ARSP-REFRESH THEN -1
            ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DUP KEY-IS-CHAR? IF
        KEY-CODE@ DUP [CHAR] r = SWAP [CHAR] R = OR IF
            _ARSP-H-P @ _ARSP-REFRESH -1 EXIT
        THEN
        0 EXIT
    THEN
    DROP 0 ;

VARIABLE _ARSP-N-RUNTIME
VARIABLE _ARSP-N-RGN

: ARSP-NEW  ( runtime region -- panel )
    _ARSP-N-RGN ! _ARSP-N-RUNTIME !
    AGENT-SETTINGS-PANEL-SIZE ALLOCATE
    0<> ABORT" ARSP-NEW: alloc failed"
    DUP AGENT-SETTINGS-PANEL-SIZE 0 FILL
    DUP WDG-T-AGENT-SETTINGS _ARSP-N-RGN @
    ['] _ARSP-DRAW ['] _ARSP-HANDLE WDG-INIT
    _ARSP-N-RUNTIME @ OVER ARSP.RUNTIME !
    DUP ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS ?DUP IF
        ARSET.REVISION @ OVER ARSP.REVISION !
    THEN
    DUP WDG-HIDE ;

: ARSP-SHOW  ( panel -- )
    0 OVER ARSP.LAST-STATUS ! WDG-SHOW ;

: ARSP-ACTIVE?  ( panel -- flag ) WDG-VISIBLE? ;

: ARSP-SYNC  ( panel -- changed? )
    DUP _ARSP-P ! ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS DUP 0= IF
        DROP 0 EXIT
    THEN
    ARSET.REVISION @ DUP _ARSP-P @ ARSP.REVISION @ = IF DROP 0 EXIT THEN
    _ARSP-P @ ARSP.REVISION ! _ARSP-P @ WDG-DIRTY -1 ;

: ARSP-ON-CLOSE  ( xt panel -- ) ARSP.CLOSE-XT ! ;

: ARSP-FREE  ( panel -- ) FREE ;
