\ =====================================================================
\  akashic/tui/widgets/prompt.f - Non-blocking command bar
\ =====================================================================
\
\  A one-line prompt that can be painted over an application's status
\  bar.  The caller owns the text buffer and outer region.  The prompt
\  owns its input widget and the input's child region.
\
\  While it is shown, the prompt is also one TEXT field (field-model.f):
\  its label, its input's value (mask characters when it masks), caret,
\  selection, scroll and placeholder.  A rich renderer that finds it in
\  the draw shows that field and names positions in it; this CELL paint
\  stays the complete fallback.
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
\    PRM-INSTANCE@    ( prompt -- instance|0 )
\    PRM-FIELD-ROOT   ( prompt -- row col height width )
\    PRM-FIELD-CAPTURE ( dst cap prompt -- bytes status )
\ =====================================================================

PROVIDED akashic-tui-prompt

REQUIRE input.f
REQUIRE ../../text/cell-width.f
REQUIRE ../draw.f
REQUIRE ../region.f
REQUIRE ../keys.f
REQUIRE ../widget.f
REQUIRE ../field-model.f
REQUIRE ../../utils/memory-span.f

40  CONSTANT _PRM-O-INPUT
48  CONSTANT _PRM-O-INPUT-RGN
56  CONSTANT _PRM-O-LABEL-A
64  CONSTANT _PRM-O-LABEL-U
72  CONSTANT _PRM-O-SUBMIT-XT
80  CONSTANT _PRM-O-CANCEL-XT
88  CONSTANT _PRM-O-ACTIVE
96  CONSTANT _PRM-O-FG
104 CONSTANT _PRM-O-BG
112 CONSTANT _PRM-O-INSTANCE    \ process-lifetime identity, never 0
120 CONSTANT _PRM-O-REVISION    \ advances with the label and the bounds
128 CONSTANT _PRM-DESC-SIZE

VARIABLE _PRM-NEXT-INSTANCE
0 _PRM-NEXT-INSTANCE !

VARIABLE _PRM-W
VARIABLE _PRM-START
VARIABLE _PRM-WIDTH

: _PRM-SYNC-INPUT-RGN  ( prompt -- )
    _PRM-W !
    _PRM-W @ WDG-REGION RGN-W _PRM-WIDTH !
    \ The label starts at column 1 and takes its width in cells.
    _PRM-W @ _PRM-O-LABEL-A + @ _PRM-W @ _PRM-O-LABEL-U + @ CW-SWIDTH 2 +
    _PRM-WIDTH @ 1- MIN 0 MAX _PRM-START !
    _PRM-W @ _PRM-O-INPUT-RGN + @ >R
    _PRM-W @ WDG-REGION RGN-ROW
        R@ _RGN-O-ROW + !
    _PRM-W @ WDG-REGION RGN-COL _PRM-START @ +
        R@ _RGN-O-COL + !
    1 R@ _RGN-O-H + !
    _PRM-WIDTH @ _PRM-START @ - 1 MAX
        R> _RGN-O-W + ! ;

: _PRM-DRAW-BODY  ( prompt -- )
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

\ A visible prompt replaces the semantic status row painted immediately
\ before the applet callback.  Keep that ordinary painter order explicit so
\ every CELL write, including the nested input widget, is the final writer.
: _PRM-DRAW  ( prompt -- )
    ['] _PRM-DRAW-BODY DRW-OVERLAY ;

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
    DUP WDG-FOCUS-SET
    DROP
    _PRM-DESC-SIZE ALLOCATE
    0<> ABORT" PRM-NEW: alloc failed"
    DUP WDG-T-PROMPT _PRM-N-RGN @
        ['] _PRM-DRAW ['] _PRM-HANDLE WDG-INIT
    _PRM-N-INP @  OVER _PRM-O-INPUT + !
    _PRM-N-IRGN @ OVER _PRM-O-INPUT-RGN + !
    0 OVER _PRM-O-LABEL-A + !
    0 OVER _PRM-O-LABEL-U + !
    0 OVER _PRM-O-SUBMIT-XT + !
    0 OVER _PRM-O-CANCEL-XT + !
    0 OVER _PRM-O-ACTIVE + !
    15 OVER _PRM-O-FG + !
    24 OVER _PRM-O-BG + !
    1 OVER _PRM-O-REVISION + !
    _PRM-NEXT-INSTANCE @ DUP -1 = IF DROP 1 ELSE 1+ THEN
    DUP _PRM-NEXT-INSTANCE ! OVER _PRM-O-INSTANCE + ! ;

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
    1 _PRM-S-W @ _PRM-O-REVISION + +!
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
    \ Unchanged bounds leave the published field as it was.
    3 PICK R@ _RGN-O-ROW + @ = 3 PICK R@ _RGN-O-COL + @ = AND
    2 PICK R@ _RGN-O-H + @ = AND OVER R@ _RGN-O-W + @ = AND IF
        2DROP 2DROP R> DROP R> WDG-DIRTY EXIT
    THEN
    R@ _RGN-O-W + !
    R@ _RGN-O-H + !
    R@ _RGN-O-COL + !
    R> _RGN-O-ROW + !
    1 R@ _PRM-O-REVISION + +!
    R> WDG-DIRTY ;

: PRM-FREE  ( prompt -- )
    0 OVER _PRM-O-INSTANCE + !
    DUP _PRM-O-INPUT + @ ?DUP IF INP-FREE THEN
    DUP _PRM-O-INPUT-RGN + @ ?DUP IF RGN-FREE THEN
    FREE ;

\ =====================================================================
\  The prompt as a TEXT field
\ =====================================================================

\ _PRM-GENUINE? ( widget -- flag )
\   A live prompt this module made: its type, draw and handle words,
\   identity, region and input.
: _PRM-GENUINE?  ( widget -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _PRM-DESC-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP WDG-TYPE WDG-T-PROMPT <> IF DROP 0 EXIT THEN
    DUP _WDG-O-DRAW-XT + @ ['] _PRM-DRAW <> IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _PRM-HANDLE <> IF DROP 0 EXIT THEN
    DUP _PRM-O-INSTANCE + @ 0= IF DROP 0 EXIT THEN
    DUP _PRM-O-INPUT + @ DUP 0= SWAP 7 AND OR IF DROP 0 EXIT THEN
    WDG-REGION DUP 0= SWAP 7 AND OR 0= ;

\ PRM-INSTANCE@ ( prompt -- instance|0 )
\   The prompt's identity for as long as it lives; 0 for anything else.
: PRM-INSTANCE@  ( prompt -- instance|0 )
    DUP _PRM-GENUINE? 0= IF DROP 0 EXIT THEN _PRM-O-INSTANCE + @ ;

\ PRM-FIELD-ROOT ( prompt -- row col height width )
\   The screen cells the prompt's field takes: the first row of its region,
\   which is all it paints.
: PRM-FIELD-ROOT  ( prompt -- row col height width )
    WDG-REGION >R R@ RGN-ROW R@ RGN-COL 1 R> RGN-W ;

\ The field's slots, as the paint lays them out: the label from column 1,
\ cut where the input begins, and the input's columns as the value.
VARIABLE _PRM-F-W  VARIABLE _PRM-F-INPUT  VARIABLE _PRM-F-LW
VARIABLE _PRM-F-CHARS  VARIABLE _PRM-F-CARET  VARIABLE _PRM-F-ANCHOR
VARIABLE _PRM-F-SCROLL  VARIABLE _PRM-F-MASK  VARIABLE _PRM-F-LABEL-U
VARIABLE _PRM-F-VALUE-U  VARIABLE _PRM-F-NEED  VARIABLE _PRM-F-DST
VARIABLE _PRM-F-CAP
CREATE _PRM-F-BUILDER-S UFLD-BUILDER-SIZE 7 + ALLOT
_PRM-F-BUILDER-S 7 + -8 AND CONSTANT _PRM-F-BUILDER

: _PRM-F-PREPARE  ( prompt -- )
    DUP _PRM-F-W ! DUP _PRM-SYNC-INPUT-RGN
    _PRM-O-INPUT + @ DUP _PRM-F-INPUT !
    DUP INP-SHOWN-STATE
        _PRM-F-SCROLL ! _PRM-F-ANCHOR ! _PRM-F-CARET ! _PRM-F-CHARS !
    INP-MASK@ _PRM-F-MASK !
    \ A label the input covers completely is not shown, so it has no slot.
    _PRM-F-W @ _PRM-O-LABEL-A + @ _PRM-F-W @ _PRM-O-LABEL-U + @ CW-SWIDTH
        _PRM-START @ 1- MIN 0 MAX _PRM-F-LW !
    _PRM-F-LW @ IF _PRM-F-W @ _PRM-O-LABEL-U + @ ELSE 0 THEN _PRM-F-LABEL-U !
    _PRM-F-MASK @ IF
        _PRM-F-CHARS @ _PRM-F-MASK @ _UFLD-CP-BYTES *
    ELSE
        _PRM-F-INPUT @ INP-GET-TEXT NIP
    THEN _PRM-F-VALUE-U ! ;

\ The destination lies apart from everything the field is read from: the
\ prompt, its input and their regions, the input's buffer, the label and
\ the placeholder.
: _PRM-F-APART?  ( -- flag )
    _PRM-F-DST @ _PRM-F-CAP @
    2DUP _PRM-F-W @ _PRM-DESC-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _PRM-F-INPUT @ _INP-DESC-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _PRM-F-W @ WDG-REGION RGN-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _PRM-F-INPUT @ WDG-REGION RGN-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _PRM-F-INPUT @ _INP-O-BUF-A + @ _PRM-F-INPUT @ _INP-O-BUF-CAP + @
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _PRM-F-W @ _PRM-O-LABEL-A + @ _PRM-F-W @ _PRM-O-LABEL-U + @
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    _PRM-F-INPUT @ INP-PLACEHOLDER@ MSPAN-OVERLAP? 0= ;

: _PRM-F-BYTES  ( -- bytes )
    UFLD-HEADER-SIZE _PRM-F-LABEL-U @ _UFLD-ALIGN8 +
    _PRM-F-VALUE-U @ _UFLD-ALIGN8 +
    _PRM-F-INPUT @ INP-PLACEHOLDER@ NIP _UFLD-ALIGN8 + ;

: _PRM-F-BUILD  ( -- bytes status )
    _PRM-F-DST @ _PRM-F-CAP @ _PRM-F-BUILDER UFLD-BUILDER-INIT
        ?DUP IF 0 SWAP EXIT THEN
    1 UFLD-K-TEXT
    _PRM-F-W @ _PRM-O-REVISION + @ _PRM-F-INPUT @ INP-REVISION@ +
    _PRM-F-W @ WDG-REGION RGN-W 1
    UFLD-STATE-VISIBLE UFLD-STATE-ENABLED OR UFLD-STATE-SELECTED OR
    _PRM-F-MASK @ IF UFLD-F-MASKED ELSE 0 THEN
    _PRM-F-BUILDER UFLD-BEGIN ?DUP IF 0 SWAP EXIT THEN
    _PRM-F-LW @ IF 0 1 1 _PRM-F-LW @ ELSE 0 0 0 0 THEN
    0 _PRM-START @ 1 _PRM-F-W @ WDG-REGION RGN-W _PRM-START @ -
    _PRM-F-BUILDER UFLD-SLOTS ?DUP IF 0 SWAP EXIT THEN
    _PRM-F-LW @ IF _PRM-F-W @ _PRM-O-LABEL-A + @ ELSE 0 THEN
    _PRM-F-LABEL-U @ _PRM-F-BUILDER UFLD-LABEL ?DUP IF 0 SWAP EXIT THEN
    _PRM-F-MASK @ IF
        _PRM-F-MASK @ _PRM-F-CHARS @ _PRM-F-BUILDER UFLD-TEXT-FILL
    ELSE
        _PRM-F-INPUT @ INP-GET-TEXT _PRM-F-BUILDER UFLD-TEXT
    THEN ?DUP IF 0 SWAP EXIT THEN
    _PRM-F-CARET @ _PRM-F-ANCHOR @ _PRM-F-SCROLL @
    _PRM-F-INPUT @ INP-PLACEHOLDER@ _PRM-F-BUILDER UFLD-TEXT-EDIT
        ?DUP IF 0 SWAP EXIT THEN
    _PRM-F-BUILDER UFLD-FINISH ;

\ PRM-FIELD-CAPTURE ( dst cap prompt -- bytes status )
\   Write the shown prompt's TEXT field model at DST, an aligned span of
\   CAP bytes apart from everything the prompt reads, or with DST 0 and
\   CAP 0 only measure it.  The status is a UFLD-S- value.  It lays the
\   prompt out as its draw does, so it holds before that draw as after it.
: PRM-FIELD-CAPTURE  ( dst cap prompt -- bytes status )
    DUP _PRM-GENUINE? 0= IF 2DROP DROP 0 UFLD-S-INVALID EXIT THEN
    DUP _PRM-O-ACTIVE + @ 0= IF 2DROP DROP 0 UFLD-S-INVALID EXIT THEN
    _PRM-F-PREPARE _PRM-F-CAP ! _PRM-F-DST !
    _PRM-F-BYTES _PRM-F-NEED !
    _PRM-F-DST @ 0= IF
        _PRM-F-CAP @ IF 0 UFLD-S-INVALID EXIT THEN
        _PRM-F-NEED @ UFLD-S-OK EXIT
    THEN
    _PRM-F-DST @ _PRM-F-CAP @ MSPAN-NONWRAPPING? 0= IF 0 UFLD-S-INVALID EXIT THEN
    _PRM-F-APART? 0= IF 0 UFLD-S-INVALID EXIT THEN
    _PRM-F-CAP @ _PRM-F-NEED @ U< IF 0 UFLD-S-CAPACITY EXIT THEN
    _PRM-F-BUILD DUP IF EXIT THEN
    OVER _PRM-F-NEED @ <> IF 2DROP 0 UFLD-S-INVALID EXIT THEN ;
