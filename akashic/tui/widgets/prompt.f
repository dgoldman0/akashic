\ =====================================================================
\  akashic/tui/widgets/prompt.f - Non-blocking command bar
\ =====================================================================
\
\  A one-line prompt that can be painted over an application's status
\  bar.  The caller owns the text buffer and outer region.  The prompt
\  owns its input widget and the input's child region.
\
\  Public API:
\    PRM-NEW          ( rgn buf cap -- prompt )
\    PRM-SHOW         ( label-a label-u initial-a initial-u prompt -- )
\    PRM-HIDE         ( prompt -- )
\    PRM-ACTIVE?      ( prompt -- flag )
\    PRM-GET-TEXT     ( prompt -- addr len )
\    PRM-ON-SUBMIT    ( xt prompt -- )       xt: ( prompt -- )
\    PRM-ON-CANCEL    ( xt prompt -- )       xt: ( prompt -- )
\    PRM-COLORS!      ( fg bg prompt -- )
\    PRM-MASK!        ( codepoint prompt -- )  0 disables masking
\    PRM-WIPE         ( prompt -- )          Zero caller-owned input
\    PRM-SET-BOUNDS   ( row col h w prompt -- )
\    PRM-FREE         ( prompt -- )
\ =====================================================================

PROVIDED akashic-tui-prompt

REQUIRE input.f
REQUIRE ../draw.f
REQUIRE ../region.f
REQUIRE ../keys.f
REQUIRE ../widget.f

40  CONSTANT _PRM-O-INPUT
48  CONSTANT _PRM-O-INPUT-RGN
56  CONSTANT _PRM-O-LABEL-A
64  CONSTANT _PRM-O-LABEL-U
72  CONSTANT _PRM-O-SUBMIT-XT
80  CONSTANT _PRM-O-CANCEL-XT
88  CONSTANT _PRM-O-ACTIVE
96  CONSTANT _PRM-O-FG
104 CONSTANT _PRM-O-BG
112 CONSTANT _PRM-DESC-SIZE

VARIABLE _PRM-W
VARIABLE _PRM-START
VARIABLE _PRM-WIDTH

: _PRM-SYNC-INPUT-RGN  ( prompt -- )
    _PRM-W !
    _PRM-W @ WDG-REGION RGN-W _PRM-WIDTH !
    _PRM-W @ _PRM-O-LABEL-U + @ 2 +
    _PRM-WIDTH @ 1- MIN 0 MAX _PRM-START !
    _PRM-W @ _PRM-O-INPUT-RGN + @ >R
    _PRM-W @ WDG-REGION RGN-ROW
        R@ _RGN-O-ROW + !
    _PRM-W @ WDG-REGION RGN-COL _PRM-START @ +
        R@ _RGN-O-COL + !
    1 R@ _RGN-O-H + !
    _PRM-WIDTH @ _PRM-START @ - 1 MAX
        R> _RGN-O-W + ! ;

: _PRM-DRAW  ( prompt -- )
    DUP _PRM-O-ACTIVE + @ 0= IF DROP EXIT THEN
    DUP _PRM-W !
    DUP _PRM-SYNC-INPUT-RGN
    DUP _PRM-O-FG + @ DRW-FG!
    DUP _PRM-O-BG + @ DRW-BG!
    0 DRW-ATTR!
    DUP WDG-REGION RGN-W _PRM-WIDTH !
    32 0 0 _PRM-WIDTH @ DRW-HLINE
    DUP _PRM-O-LABEL-A + @
    OVER _PRM-O-LABEL-U + @
    0 1 DRW-TEXT
    _PRM-O-INPUT + @ DUP WDG-DIRTY WDG-DRAW
    DRW-STYLE-RESET ;

VARIABLE _PRM-HND-W

: _PRM-HANDLE  ( event prompt -- consumed? )
    _PRM-HND-W !
    _PRM-HND-W @ _PRM-O-ACTIVE + @ 0= IF DROP 0 EXIT THEN
    DUP @ KEY-T-SPECIAL = IF
        DUP 8 + @ KEY-ESC = IF
            DROP
            0 _PRM-HND-W @ _PRM-O-ACTIVE + !
            _PRM-HND-W @ WDG-DIRTY
            _PRM-HND-W @ _PRM-O-CANCEL-XT + @ ?DUP IF
                _PRM-HND-W @ SWAP EXECUTE
            THEN
            -1 EXIT
        THEN
        DUP 8 + @ KEY-ENTER = IF
            DROP
            0 _PRM-HND-W @ _PRM-O-ACTIVE + !
            _PRM-HND-W @ WDG-DIRTY
            _PRM-HND-W @ _PRM-O-SUBMIT-XT + @ ?DUP IF
                _PRM-HND-W @ SWAP EXECUTE
            THEN
            -1 EXIT
        THEN
    THEN
    _PRM-HND-W @ _PRM-O-INPUT + @ WDG-HANDLE ;

VARIABLE _PRM-N-RGN
VARIABLE _PRM-N-BUF
VARIABLE _PRM-N-CAP
VARIABLE _PRM-N-IRGN
VARIABLE _PRM-N-INP

: PRM-NEW  ( rgn buf cap -- prompt )
    _PRM-N-CAP ! _PRM-N-BUF ! _PRM-N-RGN !
    _PRM-N-RGN @ 0 0 1 _PRM-N-RGN @ RGN-W 1 MAX RGN-SUB
    DUP _PRM-N-IRGN !
    _PRM-N-BUF @ _PRM-N-CAP @ INP-NEW
    DUP _PRM-N-INP !
    DUP _WDG-FOCUS-SET
    DROP
    _PRM-DESC-SIZE ALLOCATE
    0<> ABORT" PRM-NEW: alloc failed"
    DUP WDG-T-PROMPT _PRM-N-RGN @
        ['] _PRM-DRAW ['] _PRM-HANDLE _WDG-INIT
    _PRM-N-INP @  OVER _PRM-O-INPUT + !
    _PRM-N-IRGN @ OVER _PRM-O-INPUT-RGN + !
    0 OVER _PRM-O-LABEL-A + !
    0 OVER _PRM-O-LABEL-U + !
    0 OVER _PRM-O-SUBMIT-XT + !
    0 OVER _PRM-O-CANCEL-XT + !
    0 OVER _PRM-O-ACTIVE + !
    15 OVER _PRM-O-FG + !
    24 OVER _PRM-O-BG + ! ;

VARIABLE _PRM-S-W
VARIABLE _PRM-S-IA
VARIABLE _PRM-S-IU
VARIABLE _PRM-S-LA
VARIABLE _PRM-S-LU

: PRM-SHOW  ( label-a label-u initial-a initial-u prompt -- )
    _PRM-S-W ! _PRM-S-IU ! _PRM-S-IA ! _PRM-S-LU ! _PRM-S-LA !
    _PRM-S-LA @ _PRM-S-W @ _PRM-O-LABEL-A + !
    _PRM-S-LU @ _PRM-S-W @ _PRM-O-LABEL-U + !
    _PRM-S-IA @ _PRM-S-IU @
        _PRM-S-W @ _PRM-O-INPUT + @ INP-SET-TEXT
    -1 _PRM-S-W @ _PRM-O-ACTIVE + !
    _PRM-S-W @ WDG-DIRTY ;

: PRM-HIDE  ( prompt -- )
    0 OVER _PRM-O-ACTIVE + !
    WDG-DIRTY ;

: PRM-ACTIVE?  ( prompt -- flag )
    _PRM-O-ACTIVE + @ 0<> ;

: PRM-GET-TEXT  ( prompt -- addr len )
    _PRM-O-INPUT + @ INP-GET-TEXT ;

: PRM-ON-SUBMIT  ( xt prompt -- )
    _PRM-O-SUBMIT-XT + ! ;

: PRM-ON-CANCEL  ( xt prompt -- )
    _PRM-O-CANCEL-XT + ! ;

: PRM-COLORS!  ( fg bg prompt -- )
    >R
    R@ _PRM-O-BG + !
    R@ _PRM-O-FG + !
    R> WDG-DIRTY ;

: PRM-MASK!  ( codepoint prompt -- )
    _PRM-O-INPUT + @ INP-MASK! ;

: PRM-WIPE  ( prompt -- )
    _PRM-O-INPUT + @ INP-WIPE ;

: PRM-SET-BOUNDS  ( row col h w prompt -- )
    >R
    R@ WDG-REGION >R
    R@ _RGN-O-W + !
    R@ _RGN-O-H + !
    R@ _RGN-O-COL + !
    R> _RGN-O-ROW + !
    R> WDG-DIRTY ;

: PRM-FREE  ( prompt -- )
    DUP _PRM-O-INPUT + @ ?DUP IF INP-FREE THEN
    DUP _PRM-O-INPUT-RGN + @ ?DUP IF RGN-FREE THEN
    FREE ;
