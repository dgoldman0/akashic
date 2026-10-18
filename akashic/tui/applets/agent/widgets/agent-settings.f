\ =====================================================================
\  agent-settings.f - Provider-neutral model and run settings view
\ =====================================================================
\  The view borrows a runtime and a region beneath the Agent's mounted
\  panel, which draws it in place of the transcript.  Model, reasoning,
\  speed and verbosity are canonical CHOICE fields; the heading, the chosen
\  setting's description and the footer are ordinary paint.  Providers
\  retain all catalog descriptors, while runtime wrappers enforce
\  active-run safety.
\ =====================================================================

PROVIDED akashic-tui-agent-settings

REQUIRE ../../../widget.f
REQUIRE ../../../draw.f
REQUIRE ../../../keys.f
REQUIRE ../../../region.f
REQUIRE ../../../widgets/field.f
REQUIRE ../runtime.f

40  CONSTANT _ARSP-RUNTIME
48  CONSTANT _ARSP-ROW
56  CONSTANT _ARSP-REVISION
64  CONSTANT _ARSP-LAST-STATUS
72  CONSTANT _ARSP-CLOSE-XT
80  CONSTANT _ARSP-FIELDS          \ one field record a setting
336 CONSTANT _ARSP-BUILDER         \ UFLD-BUILDER-SIZE bytes
376 CONSTANT _ARSP-BUILT-WIDTH     \ the view width the bound models fit
384 CONSTANT _ARSP-BUILT-REVISION  \ the settings revision they show
392 CONSTANT _ARSP-BUILT-ROW       \ the setting they show selected
400 CONSTANT _ARSP-READY           \ every field holds a current model
408 CONSTANT AGENT-SETTINGS-PANEL-SIZE

4 CONSTANT _ARSP-SETTINGS          \ model, reasoning, speed, verbosity

\ A field record: its widget and region, two model banks, each an
\ allocation and the bytes usable from its aligned base, the bank bound to
\ the widget (-1 for none) and the bound model's bytes.  A replacement is
\ always built in the bank not bound.
64 CONSTANT _ARSP-FIELD-SIZE

: ARSP.RUNTIME     ( panel -- a ) _ARSP-RUNTIME + ;
: ARSP.ROW         ( panel -- a ) _ARSP-ROW + ;
: ARSP.REVISION    ( panel -- a ) _ARSP-REVISION + ;
: ARSP.LAST-STATUS ( panel -- a ) _ARSP-LAST-STATUS + ;
: ARSP.CLOSE-XT    ( panel -- a ) _ARSP-CLOSE-XT + ;

: _ARSP-FIELD    ( index panel -- record )
    _ARSP-FIELDS + SWAP _ARSP-FIELD-SIZE * + ;
: _ARSPF.WIDGET  ( record -- a ) ;
: _ARSPF.REGION  ( record -- a ) 8 + ;
: _ARSPF.RAW     ( bank record -- a ) SWAP 16 * + 16 + ;
: _ARSPF.CAP     ( bank record -- a ) SWAP 16 * + 24 + ;
: _ARSPF.BOUND   ( record -- a ) 48 + ;
: _ARSPF.BYTES   ( record -- a ) 56 + ;
: _ARSPF-BASE    ( bank record -- address ) _ARSPF.RAW @ 7 + -8 AND ;

VARIABLE _ARSP-P
VARIABLE _ARSP-S
VARIABLE _ARSP-M
VARIABLE _ARSP-W
VARIABLE _ARSP-H
VARIABLE _ARSP-I
VARIABLE _ARSP-N

: _ARSP-TEXT  ( addr len row col -- ) DRW-TEXT ;

: _ARSP-HEADER  ( -- )
    15 24 1 DRW-STYLE!
    32 0 0 1 _ARSP-W @ DRW-FILL-RECT
    S" Run settings" 0 2 _ARSP-TEXT ;

: _ARSP-FOOTER  ( addr len -- )
    253 236 0 DRW-STYLE!
    32 _ARSP-H @ 1- 0 1 _ARSP-W @ DRW-FILL-RECT
    _ARSP-H @ 1- 2 _ARSP-TEXT ;

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

\ =====================================================================
\  The settings as choices
\ =====================================================================

\ A catalog name is untrusted provider text: shown as given when it is
\ clean text, else by its ID, else as unnamed.
: _ARSP-CLEAN?  ( a u -- flag )  DUP IF USF-TEXT? ELSE 2DROP 0 THEN ;
: _ARSP-NAME  ( label-a label-u id-a id-u -- a u )
    2OVER _ARSP-CLEAN? IF 2DROP EXIT THEN
    2SWAP 2DROP 2DUP _ARSP-CLEAN? IF EXIT THEN
    2DROP S" (unnamed)" ;
: _ARSP-CHOICE-NAME  ( choice|0 -- a u )
    ?DUP 0= IF S" (unnamed)" EXIT THEN
    DUP ARCH-LABEL ROT ARCH-ID _ARSP-NAME ;

\ Each walk hands every choice of a setting, ( value label-a label-u ), to
\ the word in _ARSP-EMIT-XT: first to measure the model, then to build it.
VARIABLE _ARSP-EMIT-XT
: _ARSP-EMIT  ( value a u -- )  _ARSP-EMIT-XT @ EXECUTE ;

: _ARSP-MODEL-CHOICES  ( -- )
    _ARSP-S @ ARSET-MODEL-N 0 ?DO
        I _ARSP-S @ ARSET-MODEL-NTH ?DUP IF
            I SWAP DUP ARMODEL-LABEL ROT ARMODEL-ID _ARSP-NAME _ARSP-EMIT
        THEN
    LOOP ;

\ Reasoning offers Default only while no effort is chosen: the catalog
\ takes no effort back once one is.
: _ARSP-EFFORT-CHOICES  ( -- )
    _ARSP-M @ -1 _ARSP-CHOICE-SELECTED 0< IF -1 S" Default" _ARSP-EMIT THEN
    _ARSP-M @ ARMODEL.EFFORTS-N @ 0 ?DO
        I DUP _ARSP-M @ ARMODEL-EFFORT-NTH _ARSP-CHOICE-NAME _ARSP-EMIT
    LOOP ;

: _ARSP-TIER-CHOICES  ( -- )
    -1 S" Standard" _ARSP-EMIT
    _ARSP-M @ ARMODEL.TIERS-N @ 0 ?DO
        I DUP _ARSP-M @ ARMODEL-TIER-NTH _ARSP-CHOICE-NAME _ARSP-EMIT
    LOOP ;

: _ARSP-VERB-CHOICES  ( -- )
    ARVERB-AUTO S" Auto" _ARSP-EMIT
    ARVERB-LOW S" Low" _ARSP-EMIT
    ARVERB-MEDIUM S" Medium" _ARSP-EMIT
    ARVERB-HIGH S" High" _ARSP-EMIT ;

\ What one setting shows: its label, its current value, whether it can be
\ changed, and the walk over its choices.  A setting the model does not
\ offer shows one fixed choice and is read-only.
VARIABLE _ARSP-LABEL-A
VARIABLE _ARSP-LABEL-U
VARIABLE _ARSP-VALUE
VARIABLE _ARSP-WRITABLE
VARIABLE _ARSP-WALK-XT
VARIABLE _ARSP-ONLY-A
VARIABLE _ARSP-ONLY-U

: _ARSP-ONLY-CHOICE  ( -- )  _ARSP-VALUE @ _ARSP-ONLY-A @ _ARSP-ONLY-U @ _ARSP-EMIT ;

: _ARSP-FIXED  ( value a u -- )
    _ARSP-ONLY-U ! _ARSP-ONLY-A ! _ARSP-VALUE !
    0 _ARSP-WRITABLE ! ['] _ARSP-ONLY-CHOICE _ARSP-WALK-XT ! ;

: _ARSP-OPEN  ( value walk-xt -- )
    _ARSP-WALK-XT ! _ARSP-VALUE ! -1 _ARSP-WRITABLE ! ;

: _ARSP-VERBOSITY?  ( -- flag )
    _ARSP-M @ DUP IF ARMODEL.FLAGS @ ARMODEL-F-VERBOSITY AND 0<> THEN ;

: _ARSP-SETTING  ( index -- )
    CASE
        0 OF
            S" Model" _ARSP-LABEL-U ! _ARSP-LABEL-A !
            _ARSP-M @ IF
                _ARSP-S @ ARSET.SELECTED @ ['] _ARSP-MODEL-CHOICES _ARSP-OPEN
            ELSE
                -1 S" No model" _ARSP-FIXED
            THEN
        ENDOF
        1 OF
            S" Reasoning" _ARSP-LABEL-U ! _ARSP-LABEL-A !
            _ARSP-M @ 0= IF
                -1 S" Unavailable" _ARSP-FIXED
            ELSE _ARSP-M @ ARMODEL.EFFORTS-N @ 0= IF
                -1 S" Default" _ARSP-FIXED
            ELSE
                _ARSP-M @ -1 _ARSP-CHOICE-SELECTED
                ['] _ARSP-EFFORT-CHOICES _ARSP-OPEN
            THEN THEN
        ENDOF
        2 OF
            S" Speed" _ARSP-LABEL-U ! _ARSP-LABEL-A !
            _ARSP-M @ IF
                _ARSP-M @ 0 _ARSP-CHOICE-SELECTED
                ['] _ARSP-TIER-CHOICES _ARSP-OPEN
            ELSE
                -1 S" Standard" _ARSP-FIXED
            THEN
        ENDOF
        3 OF
            S" Verbosity" _ARSP-LABEL-U ! _ARSP-LABEL-A !
            _ARSP-VERBOSITY? IF
                _ARSP-S @ ARSET.VERBOSITY @
                DUP ARVERB-AUTO ARVERB-HIGH 1+ WITHIN 0= IF DROP ARVERB-AUTO THEN
                ['] _ARSP-VERB-CHOICES _ARSP-OPEN
            ELSE
                _ARSP-S @ ARSET.VERBOSITY @ S" Not supported" _ARSP-FIXED
            THEN
        ENDOF
    ENDCASE ;

\ =====================================================================
\  Fields
\ =====================================================================

\ Each field spans the view less a column each side.  Its label starts two
\ columns in, and its value at column 18, or halfway when the view is
\ narrow; a view too narrow for both shows no fields.
VARIABLE _ARSP-FW
VARIABLE _ARSP-VC

: _ARSP-GEOMETRY?  ( view-width -- fits? )
    2 - DUP _ARSP-FW ! 2/ 18 MIN _ARSP-VC !
    _ARSP-VC @ 3 > _ARSP-FW @ _ARSP-VC @ - 1- 0> AND ;

: _ARSP-POSITION  ( -- )
    _ARSP-SETTINGS 0 DO
        _ARSP-P @ WDG-REGION DUP RGN-ROW I 2 * 3 + + SWAP RGN-COL 1+
        1 _ARSP-FW @
        I _ARSP-P @ _ARSP-FIELD _ARSPF.REGION @ RGN-BOUNDS!
    LOOP ;

VARIABLE _ARSP-R
VARIABLE _ARSP-BANK
VARIABLE _ARSP-NEED
VARIABLE _ARSP-STATUS

: _ARSP-PAD8  ( u -- u' )  7 + -8 AND ;

: _ARSP-MEASURE-CHOICE  ( value a u -- )
    NIP NIP _ARSP-PAD8 UFLD-CHOICE-HEADER-SIZE + _ARSP-NEED +! ;

: _ARSP-BUILD-CHOICE  ( value a u -- )
    _ARSP-STATUS @ IF 2DROP DROP EXIT THEN
    _ARSP-P @ _ARSP-BUILDER + UFLD-CHOICE _ARSP-STATUS ! ;

\ The bank to build in holds at least _ARSP-NEED bytes from its aligned
\ base, growing to exactly that when it does not.
: _ARSP-ROOM?  ( -- ok? )
    _ARSP-BANK @ _ARSP-R @ _ARSPF.CAP @ _ARSP-NEED @ < 0= IF -1 EXIT THEN
    _ARSP-BANK @ _ARSP-R @ _ARSPF.RAW DUP @ ?DUP IF FREE THEN 0 SWAP !
    0 _ARSP-BANK @ _ARSP-R @ _ARSPF.CAP !
    _ARSP-NEED @ 7 + ALLOCATE IF DROP 0 EXIT THEN
    _ARSP-BANK @ _ARSP-R @ _ARSPF.RAW !
    _ARSP-NEED @ _ARSP-BANK @ _ARSP-R @ _ARSPF.CAP ! -1 ;

: _ARSP-STATE  ( index -- state )
    UFLD-STATE-VISIBLE UFLD-STATE-ENABLED OR
    SWAP _ARSP-P @ ARSP.ROW @ = IF UFLD-STATE-SELECTED OR THEN ;

\ Build setting INDEX's model in the bank not bound and bind it.  The
\ content revision follows the settings revision, so an adjustment queued
\ against shown content is stale once the settings change.
: _ARSP-BUILD  ( index -- status )
    DUP _ARSP-P @ _ARSP-FIELD _ARSP-R !
    DUP _ARSP-SETTING
    UFLD-HEADER-SIZE _ARSP-LABEL-U @ _ARSP-PAD8 + _ARSP-NEED !
    ['] _ARSP-MEASURE-CHOICE _ARSP-EMIT-XT ! _ARSP-WALK-XT @ EXECUTE
    _ARSP-R @ _ARSPF.BOUND @ 0= IF 1 ELSE 0 THEN _ARSP-BANK !
    _ARSP-ROOM? 0= IF DROP UFLD-S-CAPACITY EXIT THEN
    _ARSP-BANK @ _ARSP-R @ _ARSPF-BASE _ARSP-NEED @
        _ARSP-P @ _ARSP-BUILDER + UFLD-BUILDER-INIT ?DUP IF NIP EXIT THEN
    DUP 1+ UFLD-K-CHOICE _ARSP-S @ ARSET.REVISION @ 1+
        _ARSP-FW @ 1 5 PICK _ARSP-STATE
        _ARSP-WRITABLE @ IF 0 ELSE UFLD-F-READ-ONLY THEN
        _ARSP-P @ _ARSP-BUILDER + UFLD-BEGIN ?DUP IF NIP EXIT THEN
    DROP
    0 2 1 _ARSP-VC @ 3 -  0 _ARSP-VC @ 1 _ARSP-FW @ _ARSP-VC @ - 1-
        _ARSP-P @ _ARSP-BUILDER + UFLD-SLOTS ?DUP IF EXIT THEN
    _ARSP-LABEL-A @ _ARSP-LABEL-U @
        _ARSP-P @ _ARSP-BUILDER + UFLD-LABEL ?DUP IF EXIT THEN
    _ARSP-VALUE @ _ARSP-P @ _ARSP-BUILDER + UFLD-CHOICE-VALUE ?DUP IF EXIT THEN
    0 _ARSP-STATUS ! ['] _ARSP-BUILD-CHOICE _ARSP-EMIT-XT !
    _ARSP-WALK-XT @ EXECUTE
    _ARSP-STATUS @ ?DUP IF EXIT THEN
    _ARSP-P @ _ARSP-BUILDER + UFLD-FINISH ?DUP IF NIP EXIT THEN
    _ARSP-BANK @ _ARSP-R @ _ARSPF-BASE OVER
        _ARSP-R @ _ARSPF.WIDGET @ FLD-BIND ?DUP IF NIP EXIT THEN
    _ARSP-R @ _ARSPF.BYTES !
    _ARSP-BANK @ _ARSP-R @ _ARSPF.BOUND !
    UFLD-S-OK ;

\ The fields hold current models: built again when the settings, the
\ view's width or the chosen setting have changed since they were built.
: _ARSP-FIELDS-ENSURE  ( -- ready? )
    _ARSP-W @ _ARSP-GEOMETRY? 0= IF 0 _ARSP-P @ _ARSP-READY + ! 0 EXIT THEN
    _ARSP-POSITION
    _ARSP-P @ _ARSP-READY + @
    _ARSP-P @ _ARSP-BUILT-WIDTH + @ _ARSP-W @ = AND
    _ARSP-P @ _ARSP-BUILT-REVISION + @ _ARSP-S @ ARSET.REVISION @ = AND
    _ARSP-P @ _ARSP-BUILT-ROW + @ _ARSP-P @ ARSP.ROW @ = AND IF -1 EXIT THEN
    0 _ARSP-P @ _ARSP-READY + !
    _ARSP-SETTINGS 0 DO
        I _ARSP-BUILD IF 0 UNLOOP EXIT THEN
    LOOP
    _ARSP-W @ _ARSP-P @ _ARSP-BUILT-WIDTH + !
    _ARSP-S @ ARSET.REVISION @ _ARSP-P @ _ARSP-BUILT-REVISION + !
    _ARSP-P @ ARSP.ROW @ _ARSP-P @ _ARSP-BUILT-ROW + !
    -1 _ARSP-P @ _ARSP-READY + ! -1 ;

: _ARSP-DRAW-FIELDS  ( -- )
    _ARSP-SETTINGS 0 DO
        I _ARSP-P @ _ARSP-FIELD _ARSPF.WIDGET @ _ARSP-P @ WDG-REGION WDG-DRAW-IN
    LOOP ;

\ =====================================================================
\  Drawing
\ =====================================================================

: _ARSP-DESCRIPTION  ( -- )
    244 234 0 DRW-STYLE!
    _ARSP-M @ 0= IF EXIT THEN
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
        >R 0 0 R>
    ENDCASE
    12 3 _ARSP-TEXT ;

: _ARSP-DRAW-READY  ( -- )
    _ARSP-FIELDS-ENSURE IF _ARSP-DRAW-FIELDS THEN
    _ARSP-DESCRIPTION
    S" Refresh catalog   Close" _ARSP-FOOTER ;

: _ARSP-NOT-READY  ( -- )  0 _ARSP-P @ _ARSP-READY + ! ;

: _ARSP-DRAW  ( panel -- )
    DUP _ARSP-P ! WDG-REGION DUP RGN-W _ARSP-W ! RGN-H _ARSP-H !
    253 234 0 DRW-STYLE!
    32 0 0 _ARSP-H @ _ARSP-W @ DRW-FILL-RECT
    _ARSP-HEADER
    _ARSP-P @ ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS DUP _ARSP-S !
    DUP 0= IF
        DROP _ARSP-NOT-READY 244 234 0 DRW-STYLE!
        S" This provider exposes no run settings." 3 3 _ARSP-TEXT
        S" Close" _ARSP-FOOTER DRW-STYLE-RESET EXIT
    THEN
    ARSET.STATE @ CASE
        ARSET-STATE-EMPTY OF
            _ARSP-NOT-READY 244 234 0 DRW-STYLE!
            S" The model catalog has not been loaded." 3 3 _ARSP-TEXT
            S" Refresh catalog   Close" _ARSP-FOOTER
        ENDOF
        ARSET-STATE-LOADING OF
            _ARSP-NOT-READY 244 234 0 DRW-STYLE!
            S" Loading available models..." 3 3 _ARSP-TEXT
            S" Cancel refresh   Close" _ARSP-FOOTER
        ENDOF
        ARSET-STATE-READY OF
            _ARSP-S @ ARSET-SELECTED-MODEL _ARSP-M !
            _ARSP-DRAW-READY
        ENDOF
        ARSET-STATE-ERROR OF
            _ARSP-NOT-READY 203 234 1 DRW-STYLE!
            S" Model catalog failed" 3 3 _ARSP-TEXT
            253 234 0 DRW-STYLE!
            _ARSP-S @ ARSET-ERROR 5 3 _ARSP-TEXT
            S" Retry refresh   Close" _ARSP-FOOTER
        ENDOF
    ENDCASE
    DRW-STYLE-RESET ;

\ =====================================================================
\  Input
\ =====================================================================

VARIABLE _ARSP-H-P
VARIABLE _ARSP-H-EV

\ A field's answer changes the runtime's setting it shows.
: _ARSP-APPLY  ( value row -- )
    CASE
        0 OF _ARSP-H-P @ ARSP.RUNTIME @ ARUNTIME-MODEL! ENDOF
        1 OF _ARSP-H-P @ ARSP.RUNTIME @ ARUNTIME-EFFORT! ENDOF
        2 OF _ARSP-H-P @ ARSP.RUNTIME @ ARUNTIME-TIER! ENDOF
        3 OF _ARSP-H-P @ ARSP.RUNTIME @ ARUNTIME-VERBOSITY! ENDOF
        NIP ARSET-S-INVALID SWAP
    ENDCASE
    _ARSP-H-P @ ARSP.LAST-STATUS ! _ARSP-H-P @ WDG-DIRTY ;

\ An adjustment chooses the setting it was asked of and moves its choice by
\ COUNT, wrapping; an activation moves it to the next choice.
: _ARSP-ADJUSTED  ( count widget -- )
    DUP FLD-MODEL@ DROP UFLD-KEY@ 1- DUP _ARSP-H-P @ ARSP.ROW ! >R
    FLD-MODEL@ UFLD-CHOICE-WRAP IF DROP R> DROP EXIT THEN
    R> _ARSP-APPLY ;

: _ARSP-ACTIVATED  ( widget -- )  1 SWAP _ARSP-ADJUSTED ;

: _ARSP-READY?  ( panel -- flag )  _ARSP-READY + @ 0<> ;

: _ARSP-REFRESH  ( panel -- )
    DUP _ARSP-P ! ARSP.RUNTIME @ ARUNTIME-RUN-SETTINGS-REFRESH
    _ARSP-P @ ARSP.LAST-STATUS ! _ARSP-P @ WDG-DIRTY ;

: _ARSP-CLOSE  ( panel -- )
    DUP WDG-HIDE
    DUP ARSP.CLOSE-XT @ ?DUP IF EXECUTE ELSE DROP THEN ;

: _ARSP-MOVE  ( delta -- )
    _ARSP-H-P @ ARSP.ROW @ + _ARSP-SETTINGS + _ARSP-SETTINGS MOD
    _ARSP-H-P @ ARSP.ROW ! _ARSP-H-P @ WDG-DIRTY ;

\ The chosen setting's field takes the event while the fields are shown.
: _ARSP-CHOSEN-HANDLE  ( -- )
    _ARSP-H-P @ _ARSP-READY? 0= IF EXIT THEN
    _ARSP-H-EV @ _ARSP-H-P @ ARSP.ROW @ _ARSP-H-P @ _ARSP-FIELD _ARSPF.WIDGET @
    WDG-HANDLE DROP ;

\ A pointer event is the field's it lies on.
: _ARSP-POINTER  ( -- consumed? )
    _ARSP-H-P @ _ARSP-READY? 0= IF 0 EXIT THEN
    _ARSP-SETTINGS 0 DO
        _ARSP-H-EV @ I _ARSP-H-P @ _ARSP-FIELD _ARSPF.WIDGET @ WDG-HANDLE IF
            -1 UNLOOP EXIT
        THEN
    LOOP 0 ;

: _ARSP-HANDLE  ( event panel -- consumed? )
    _ARSP-H-P ! _ARSP-H-EV !
    _ARSP-H-EV @ @ KEY-T-MOUSE = IF _ARSP-POINTER EXIT THEN
    _ARSP-H-EV @ KEY-IS-SPECIAL? IF
        _ARSP-H-EV @ KEY-CODE@ CASE
            KEY-ESC OF _ARSP-H-P @ _ARSP-CLOSE -1 ENDOF
            KEY-UP OF -1 _ARSP-MOVE -1 ENDOF
            KEY-DOWN OF 1 _ARSP-MOVE -1 ENDOF
            KEY-LEFT OF _ARSP-CHOSEN-HANDLE -1 ENDOF
            KEY-RIGHT OF _ARSP-CHOSEN-HANDLE -1 ENDOF
            KEY-F2 OF _ARSP-CHOSEN-HANDLE -1 ENDOF
            KEY-ENTER OF
                _ARSP-H-P @ _ARSP-READY? IF
                    _ARSP-CHOSEN-HANDLE
                ELSE
                    _ARSP-H-P @ _ARSP-REFRESH
                THEN -1
            ENDOF
            0 SWAP
        ENDCASE
        EXIT
    THEN
    _ARSP-H-EV @ KEY-IS-CHAR? IF
        _ARSP-H-EV @ KEY-CODE@ DUP [CHAR] r = SWAP [CHAR] R = OR IF
            _ARSP-H-P @ _ARSP-REFRESH -1 EXIT
        THEN
        0 EXIT
    THEN
    0 ;

\ =====================================================================
\  Lifetime
\ =====================================================================

VARIABLE _ARSP-N-RUNTIME
VARIABLE _ARSP-N-RGN
VARIABLE _ARSP-N-P
VARIABLE _ARSP-N-R

\ ARSP-NEW ( runtime region -- panel )
\   A hidden view drawn in REGION, which lies beneath the panel that draws
\   it, with a field for each setting in a region beneath REGION.
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
    DUP _ARSP-N-P !
    _ARSP-SETTINGS 0 DO
        I _ARSP-N-P @ _ARSP-FIELD _ARSP-N-R !
        -1 _ARSP-N-R @ _ARSPF.BOUND !
        _ARSP-N-RGN @ 0 0 1 1 RGN-SUB DUP _ARSP-N-R @ _ARSPF.REGION !
        FLD-NEW DUP _ARSP-N-R @ _ARSPF.WIDGET !
        253 234 0 3 PICK FLD-STYLE!
        15 24 CELL-A-BOLD 3 PICK FLD-SELECTED-STYLE!
        ['] _ARSP-ACTIVATED OVER FLD-ON-ACTIVATE
        ['] _ARSP-ADJUSTED SWAP FLD-ON-ADJUST
    LOOP
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

\ ARSP-FREE ( panel -- )
\   Release the view, its fields, their regions and their models.
: ARSP-FREE  ( panel -- )
    DUP _ARSP-N-P !
    _ARSP-SETTINGS 0 DO
        I _ARSP-N-P @ _ARSP-FIELD
        DUP _ARSPF.WIDGET @ ?DUP IF FLD-FREE THEN
        DUP _ARSPF.REGION @ ?DUP IF RGN-FREE THEN
        DUP 0 SWAP _ARSPF.RAW @ ?DUP IF FREE THEN
        1 SWAP _ARSPF.RAW @ ?DUP IF FREE THEN
    LOOP
    FREE ;
