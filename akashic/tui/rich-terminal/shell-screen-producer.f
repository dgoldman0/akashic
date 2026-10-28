\ Optional shell candidate paired with the aggregate producer's exact ACK bank.
\ Complete immutable copies only.  Refusal never changes the legacy candidate.
\ The shell's part of each frame is frozen into one of the screen producer's
\ extension blocks and named by the frame's bank (_RTHP-TB.XBLOCK), so that
\ bank is the one record of the frame.  With a memory source attached, the
\ work space starts small and grows to what each candidate needs.
PROVIDED akashic-tui-rshsp
REQUIRE hybrid-screen-producer.f
REQUIRE ../../utils/memory-source.f
REQUIRE shell-membership.f
REQUIRE shell-family-clone.f
REQUIRE family-batch.f
REQUIRE shell-family-emit.f
REQUIRE frame-shadow.f
REQUIRE ../check-mode.f

128 CONSTANT RSHSP-SIZE
96 CONSTANT RSHSP-PART-HEADER-SIZE
0x5253485350303031 CONSTANT _RSHSP-MAGIC
: _RSHSP.MAGIC ( s -- a ) ;
: _RSHSP.SIZE ( s -- a ) 8 + ;
: _RSHSP.SELF ( s -- a ) 16 + ;
: _RSHSP.PRODUCER ( s -- a ) 24 + ;
: _RSHSP.SOURCE ( s -- a ) 32 + ;
: _RSHSP.SHELL ( s -- a ) 40 + ;
: _RSHSP.WORK ( s -- a ) 48 + ;
: _RSHSP.WORK-U ( s -- a ) 56 + ;
\ The bytes the last freeze needed for the shell's part of the frame.
: _RSHSP.PART-BYTES ( s -- a ) 64 + ;
: _RSHSP.WORK-USED ( s -- a ) 72 + ;
\ The memory source the work space grows into (0: fixed storage).
: _RSHSP.MEMORY ( s -- a ) 80 + ;
: _RSHSP.EXTENSION ( s -- a ) 88 + ;
\ The extension record the screen producer calls lies here, whole:
\ RTHP-EXTENSION-SIZE bytes.
: RSHSP-BYTES ( -- n ) RSHSP-SIZE ;
: RSHSP-WORK-USED@ ( s -- n ) _RSHSP.WORK-USED @ ;
: RSHSP-PART-BYTES@ ( s -- n ) _RSHSP.PART-BYTES @ ;
\ The shell's part of a frame, at the start of an extension block: offsets
\ into the part of the shell model, the taskbar's correlations and
\ actions, the panes' membership and the batch, then the frontiers.  The
\ bank that names the part holds its bytes, draw and owner.
: RSHSP-PART.BATCH ( b -- a ) ;
: RSHSP-PART.MODEL ( b -- a ) 8 + ;
: RSHSP-PART.MODEL-U ( b -- a ) 16 + ;
: RSHSP-PART.CORRELATIONS ( b -- a ) 24 + ;
: RSHSP-PART.CORRELATIONS-U ( b -- a ) 32 + ;
: RSHSP-PART.ACTIONS ( b -- a ) 40 + ;
: RSHSP-PART.ACTIONS-U ( b -- a ) 48 + ;
: RSHSP-PART.MEMBERSHIP ( b -- a ) 56 + ;
: RSHSP-PART.MEMBERSHIP-U ( b -- a ) 64 + ;
: RSHSP-PART.NEXT-REGION ( b -- a ) 72 + ;
: RSHSP-PART.NEXT-OBJECT ( b -- a ) 80 + ;
\ The control of Desk's own prompt, or zero.
: RSHSP-PART.PROMPT ( b -- a ) 88 + ;

CREATE _RSHSP-OWNED-START VARIABLE _RSHSP-OWNED-LIMIT
: RSHSP-STORAGE-DISJOINT? ( a u -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    2DUP _RSHSP-OWNED-START _RSHSP-OWNED-LIMIT @ _RSHSP-OWNED-START -
        MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP RTHP-MODULE-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP RSHMM-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    2DUP RSHFC-STORAGE-DISJOINT? 0= IF 2DROP 0 EXIT THEN
    RTE-FAMILY-EMIT-STORAGE-DISJOINT? ;
: _RSHSP-SPAN? ( a u -- flag )
    OVER 0= OVER 0> 0= OR IF 2DROP 0 EXIT THEN
    OVER 7 AND IF 2DROP 0 EXIT THEN RSHSP-STORAGE-DISJOINT? ;

VARIABLE _RSHSP-S VARIABLE _RSHSP-P VARIABLE _RSHSP-CURSOR VARIABLE _RSHSP-END
VARIABLE _RSHSP-M VARIABLE _RSHSP-MU VARIABLE _RSHSP-N VARIABLE _RSHSP-E
VARIABLE _RSHSP-Q VARIABLE _RSHSP-RESULT VARIABLE _RSHSP-ELIGIBLE
VARIABLE _RSHSP-REGIONS VARIABLE _RSHSP-PANES VARIABLE _RSHSP-CONTROLS
VARIABLE _RSHSP-TEXT VARIABLE _RSHSP-CORR VARIABLE _RSHSP-CLAIMS VARIABLE _RSHSP-ACTIONS
VARIABLE _RSHSP-MAP VARIABLE _RSHSP-MAP-U
VARIABLE _RSHSP-CATALOG VARIABLE _RSHSP-BATCH VARIABLE _RSHSP-ADMISSION
VARIABLE _RSHSP-FAMILIES VARIABLE _RSHSP-FAMILY-N VARIABLE _RSHSP-FAMILY-CAP
VARIABLE _RSHSP-REGION-N VARIABLE _RSHSP-FIRST-REGION VARIABLE _RSHSP-NEXT-ID
VARIABLE _RSHSP-SHELL-CONTROLS VARIABLE _RSHSP-BANDS VARIABLE _RSHSP-CONTENT-Z
VARIABLE _RSHSP-ITEM VARIABLE _RSHSP-OUT VARIABLE _RSHSP-BYTES VARIABLE _RSHSP-START
VARIABLE _RSHSP-KIND VARIABLE _RSHSP-COUNT VARIABLE _RSHSP-STRIDE
VARIABLE _RSHSP-REGION VARIABLE _RSHSP-FAMILY VARIABLE _RSHSP-PLAN
VARIABLE _RSHSP-I VARIABLE _RSHSP-J VARIABLE _RSHSP-RUN VARIABLE _RSHSP-MEMBER
VARIABLE _RSHSP-TEMP VARIABLE _RSHSP-SAVED VARIABLE _RSHSP-NEW
VARIABLE _RSHSP-CLAIM-BANK VARIABLE _RSHSP-CLAIM-U VARIABLE _RSHSP-BASE-CLAIM-U
VARIABLE _RSHSP-UNDER-CLAIM-U VARIABLE _RSHSP-OVERLAY-CLAIM-U
VARIABLE _RSHSP-HEADS VARIABLE _RSHSP-EVENTS VARIABLE _RSHSP-EVENTS-U
VARIABLE _RSHSP-DIFF VARIABLE _RSHSP-GQ
VARIABLE _RSHSP-GITEMS VARIABLE _RSHSP-GREFS VARIABLE _RSHSP-GTEXT
VARIABLE _RSHSP-GCOUNT VARIABLE _RSHSP-GUSED VARIABLE _RSHSP-GLIMIT VARIABLE _RSHSP-GCELLS
VARIABLE _RSHSP-GSLOTS
VARIABLE _RSHSP-GBASE VARIABLE _RSHSP-GR VARIABLE _RSHSP-REUSE
VARIABLE _RSHSP-GX0 VARIABLE _RSHSP-GW VARIABLE _RSHSP-GY0 VARIABLE _RSHSP-GY1
VARIABLE _RSHSP-GCX VARIABLE _RSHSP-GCY VARIABLE _RSHSP-GCW VARIABLE _RSHSP-GCH VARIABLE _RSHSP-GCF
VARIABLE _RSHSP-GA-ITEMS VARIABLE _RSHSP-GA-REFS VARIABLE _RSHSP-GA-TEXT VARIABLE _RSHSP-GA-TEXT-U
VARIABLE _RSHSP-GA-N VARIABLE _RSHSP-GA-I VARIABLE _RSHSP-GA-ITEM VARIABLE _RSHSP-GA-REF
VARIABLE _RSHSP-DBATCH
VARIABLE _RSHSP-PBACK VARIABLE _RSHSP-PRESIDUE VARIABLE _RSHSP-PCOLS VARIABLE _RSHSP-PROWS
VARIABLE _RSHSP-PDRAW VARIABLE _RSHSP-GREF
VARIABLE _RSHSP-PART VARIABLE _RSHSP-PART-CAP
VARIABLE _RSHSP-STATUS

: _RSHSP-FAIL ( -- ) RTE-S-UNAVAILABLE THROW ;
: _RSHSP-CHECK ( flag -- ) 0= IF _RSHSP-FAIL THEN ;
\ What a check that runs only with every-frame checks on names when it
\ fails (check-mode.f).
: _RSHSP-PARTS-DAMAGED ( -- c-addr u ) S" the shell's part of the frame" ;
: _RSHSP-MODEL-DAMAGED ( -- c-addr u ) S" the shell's model copy" ;
: _RSHSP-RECORDS-DAMAGED ( -- c-addr u ) S" the shell producer's records" ;
: _RSHSP-ADD ( n n -- n ) _RTHP-U32+? 0= IF DROP RTE-S-CAPACITY THROW THEN ;
: _RSHSP-MUL ( n n -- n ) _RTHP-U32*? 0= IF DROP RTE-S-CAPACITY THROW THEN ;
: _RSHSP-ALIGN ( n -- n ) 7 _RSHSP-ADD -8 AND ;
: _RSHSP-TAKE ( n -- a )
    _RSHSP-ALIGN
    DUP _RSHSP-CURSOR @ _RSHSP-S @ _RSHSP.WORK @ - _RSHSP-ADD
        _RSHSP-S @ _RSHSP.WORK-USED @ MAX _RSHSP-S @ _RSHSP.WORK-USED !
    DUP _RSHSP-END @ _RSHSP-CURSOR @ - U> IF DROP RTE-S-CAPACITY THROW THEN
    _RSHSP-CURSOR @ SWAP DUP _RSHSP-CURSOR +! OVER SWAP 0 FILL ;
: _RSHSP-COPY ( a u -- dst ) DUP _RSHSP-TAKE DUP >R SWAP MOVE R> ;
: _RSHSP-ZSPAN ( a u -- a|0 u ) DUP 0= IF NIP 0 SWAP THEN ;
\ Where the base candidate's controls, instruments and series are read
\ from: the producer's own candidate for a START, or for a DELTA its pending
\ target bank, whose identities the base producer has matched to the
\ acknowledged ones. The bank keeps unit text and sample references as
\ offsets into its own copies.
VARIABLE _RSHSP-SRC-CONTROLS VARIABLE _RSHSP-SRC-CORR VARIABLE _RSHSP-SRC-REGIONS
VARIABLE _RSHSP-SRC-INSTRUMENTS VARIABLE _RSHSP-SRC-INSTRUMENT-CORR
VARIABLE _RSHSP-SRC-UNITS VARIABLE _RSHSP-SRC-UNITS-U VARIABLE _RSHSP-SRC-UNIT-BASE
VARIABLE _RSHSP-SRC-SERIES VARIABLE _RSHSP-SRC-SAMPLES VARIABLE _RSHSP-SRC-SAMPLES-U
VARIABLE _RSHSP-SRC-SAMPLE-BASE
: _RSHSP-SOURCE-CANDIDATE ( -- )
    _RSHSP-P @ _RTHP.CONTROLS-A @ _RSHSP-SRC-CONTROLS !
    _RSHSP-P @ _RTHP.CORR-A @ _RSHSP-SRC-CORR !
    _RSHSP-P @ _RTHP.INSTRUMENT-REGIONS-A @ _RSHSP-SRC-REGIONS !
    _RSHSP-P @ _RTHP.INSTRUMENTS-A @ _RSHSP-SRC-INSTRUMENTS !
    _RSHSP-P @ _RTHP.INSTRUMENT-CORR-A @ _RSHSP-SRC-INSTRUMENT-CORR !
    _RSHSP-P @ _RTHP.INSTRUMENT-UNITS-A @ _RSHSP-SRC-UNITS !
    _RSHSP-P @ _RTHP.INSTRUMENT-UNITS-USED @ _RSHSP-SRC-UNITS-U !
    0 _RSHSP-SRC-UNIT-BASE !
    _RSHSP-P @ _RTHP.SERIES-A @ _RSHSP-SRC-SERIES !
    _RSHSP-P @ _RTHP.SERIES-SAMPLES-A @ _RSHSP-SRC-SAMPLES !
    _RSHSP-P @ _RTHP.SERIES-SAMPLES-USED @ _RSHSP-SRC-SAMPLES-U !
    0 _RSHSP-SRC-SAMPLE-BASE ! ;
: _RSHSP-SOURCE-TARGET ( -- )
    _RSHSP-P @ _RTHP.TARGET-PENDING @ >R
    R@ _RTHP-PACK-CONTROLS-A _RSHSP-SRC-CONTROLS !
    R@ _RTHP-PACK-CORR-A _RSHSP-SRC-CORR !
    R@ _RTHP-PACK-INSTRUMENT-REGIONS-A _RSHSP-SRC-REGIONS !
    R@ _RTHP-PACK-INSTRUMENTS-A _RSHSP-SRC-INSTRUMENTS !
    R@ _RTHP-PACK-INSTRUMENT-CORR-A _RSHSP-SRC-INSTRUMENT-CORR !
    R@ _RTHP-PACK-INSTRUMENT-UNITS-A DUP _RSHSP-SRC-UNITS ! _RSHSP-SRC-UNIT-BASE !
    R@ _RTHP-TB.INSTRUMENT-UNIT-BYTES @ _RSHSP-SRC-UNITS-U !
    R@ _RTHP-PACK-SERIES-A _RSHSP-SRC-SERIES !
    R@ _RTHP-PACK-SERIES-SAMPLES-A DUP _RSHSP-SRC-SAMPLES ! _RSHSP-SRC-SAMPLE-BASE !
    R> _RTHP-TB.SERIES-SAMPLE-BYTES @ _RSHSP-SRC-SAMPLES-U ! ;
: _RSHSP-REGION@ ( id -- row ) _RSHSP-CATALOG @ RTE-REGION-CATALOG-FIND DUP _RSHSP-CHECK ;
: _RSHSP-MEMBER@ ( token -- row ) _RSHSP-MAP @ _RSHSP-MAP-U @ RSHMM-FIND DUP _RSHSP-CHECK ;
: _RSHSP-CLEAR-RECT ( row col h w -- )
    _RSHSP-P @ _RTHP.SOURCE-DRAW @ _RSHSP-S @ _RSHSP.SOURCE @ SHSN-RECT-CLEAR?
    SHSN-S-OK = _RSHSP-CHECK _RSHSP-CHECK ;
: _RSHSP-ENTRY ( i -- e ) _RSHSP-M @ SHM-ENTRY ;
\ An overlay pane: a slot its host paints above the others, such as one of
\ Desk's own screens.
: _RSHSP-OVERLAY-PANE? ( e -- flag )
    DUP SHME.KIND @ SHM-K-PANE = SWAP SHME.FLAGS @ SHM-F-OVERLAY AND 0<> AND ;
: _RSHSP-CONTENT-RECT ( e -- row col h w )
    >R R@ SHME.CONTENT-ROW @ R@ SHME.CONTENT-COL @
    R@ SHME.CONTENT-H @ R> SHME.CONTENT-W @ ;
: _RSHSP-OVERLAP? ( e e -- flag )
    >R DUP SHME.CONTENT-ROW @ R@ SHME.CONTENT-ROW @ R@ SHME.CONTENT-H @ + <
    OVER SHME.CONTENT-ROW @ 2 PICK SHME.CONTENT-H @ + R@ SHME.CONTENT-ROW @ > AND
    OVER SHME.CONTENT-COL @ R@ SHME.CONTENT-COL @ R@ SHME.CONTENT-W @ + < AND
    SWAP DUP SHME.CONTENT-COL @ SWAP SHME.CONTENT-W @ + R> SHME.CONTENT-COL @ > AND ;
\ Panes do not overlap, but an overlay pane lies over the ordinary panes
\ beneath it.
: _RSHSP-PANES-APART? ( e e -- flag )
    OVER _RSHSP-OVERLAY-PANE? OVER _RSHSP-OVERLAY-PANE? <> IF 2DROP -1 EXIT THEN
    _RSHSP-OVERLAP? 0= ;
\ The host paints an overlay pane after the panes beneath it, as foreground,
\ and that paint is the overlay pane's own.  A rectangle of a pane beneath
\ is clear when every cell no overlay pane covers is: its rows are taken in
\ bands between the overlay panes' top and bottom edges, and each band in
\ the spans between the overlay panes it meets.  Overlay panes do not
\ overlap one another; where they would, the cells of the later one are
\ checked, which refuses.
VARIABLE _RSHSP-CX-R0 VARIABLE _RSHSP-CX-C0 VARIABLE _RSHSP-CX-R1 VARIABLE _RSHSP-CX-C1
VARIABLE _RSHSP-CX-A VARIABLE _RSHSP-CX-B VARIABLE _RSHSP-CX-COL
VARIABLE _RSHSP-CX-S VARIABLE _RSHSP-CX-E
: _RSHSP-CX-EDGE ( row -- )
    DUP _RSHSP-CX-A @ > OVER _RSHSP-CX-B @ < AND IF _RSHSP-CX-B ! ELSE DROP THEN ;
\ B: the first overlay pane edge below row A, or the rectangle's end.
: _RSHSP-CX-BAND ( -- )
    _RSHSP-CX-R1 @ _RSHSP-CX-B !
    _RSHSP-N @ 0 ?DO
        I _RSHSP-ENTRY DUP _RSHSP-OVERLAY-PANE? IF
            DUP SHME.CONTENT-ROW @ _RSHSP-CX-EDGE
            DUP SHME.CONTENT-ROW @ OVER SHME.CONTENT-H @ + _RSHSP-CX-EDGE
        THEN DROP
    LOOP ;
\ S..E: the first span from COL on that an overlay pane covers in band
\ A..B, cut to the rectangle; S = E = the rectangle's end when none does.
: _RSHSP-CX-SPAN ( -- )
    _RSHSP-CX-C1 @ DUP _RSHSP-CX-S ! _RSHSP-CX-E !
    _RSHSP-N @ 0 ?DO
        I _RSHSP-ENTRY DUP _RSHSP-OVERLAY-PANE? IF
            DUP SHME.CONTENT-ROW @ _RSHSP-CX-A @ > 0=
            OVER DUP SHME.CONTENT-ROW @ SWAP SHME.CONTENT-H @ + _RSHSP-CX-B @ < 0= AND IF
                DUP SHME.CONTENT-COL @ _RSHSP-CX-C0 @ MAX
                OVER DUP SHME.CONTENT-COL @ SWAP SHME.CONTENT-W @ + _RSHSP-CX-C1 @ MIN
                2DUP <
                2 PICK _RSHSP-CX-COL @ < 0= AND
                2 PICK _RSHSP-CX-S @ < AND IF
                    _RSHSP-CX-E ! _RSHSP-CX-S !
                ELSE 2DROP THEN
            THEN
        THEN DROP
    LOOP ;
: _RSHSP-UNCOVERED-CLEAR ( row col h w -- )
    _RSHSP-CX-C1 ! _RSHSP-CX-R1 ! _RSHSP-CX-C0 ! _RSHSP-CX-R0 !
    _RSHSP-CX-C0 @ _RSHSP-CX-C1 +! _RSHSP-CX-R0 @ _RSHSP-CX-R1 +!
    _RSHSP-CX-R0 @ _RSHSP-CX-A !
    BEGIN _RSHSP-CX-A @ _RSHSP-CX-R1 @ < WHILE
        _RSHSP-CX-BAND _RSHSP-CX-C0 @ _RSHSP-CX-COL !
        BEGIN _RSHSP-CX-COL @ _RSHSP-CX-C1 @ < WHILE
            _RSHSP-CX-SPAN
            _RSHSP-CX-S @ _RSHSP-CX-COL @ > IF
                _RSHSP-CX-A @ _RSHSP-CX-COL @
                _RSHSP-CX-B @ _RSHSP-CX-A @ - _RSHSP-CX-S @ _RSHSP-CX-COL @ -
                _RSHSP-CLEAR-RECT
            THEN
            _RSHSP-CX-E @ _RSHSP-CX-COL !
        REPEAT
        _RSHSP-CX-B @ _RSHSP-CX-A !
    REPEAT ;
\ A pane's overlay.  The document in a pane may paint one overlay over its
\ own content: the prompt it shows, captured as the last record of its
\ field snapshot, or the dialog it shows, a DIALOG with its buttons after
\ it and inside it.  The overlay's cells are its own; every other cell of
\ the pane must still be the shell's to project.  With dialogs negotiated
\ the overlay goes in a modal region over the pane's content, so the
\ terminal shows the rest of that application inactive while it is open.
\ Without them a prompt stays in the pane's content region, and there is no
\ dialog.  A record per overlay: its root's control index, its pane's SHM
\ entry index, and its modal region (0 while there is none).
24 CONSTANT _RSHSP-OV-SIZE
VARIABLE _RSHSP-OVERLAYS VARIABLE _RSHSP-OV-N VARIABLE _RSHSP-MODAL-N
VARIABLE _RSHSP-OVR VARIABLE _RSHSP-OVC VARIABLE _RSHSP-OVH VARIABLE _RSHSP-OVW
: _RSHSP-OV ( i -- record ) _RSHSP-OV-SIZE * _RSHSP-OVERLAYS @ + ;
: _RSHSP-SRC-KIND ( index -- kind )
    RTE-CONTROL-SIZE * _RSHSP-SRC-CONTROLS @ + _RTE-CONTROL.KIND @ ;
: _RSHSP-SRC-ATTACHMENT ( index -- token )
    RUCP-CORRELATION-SIZE * _RSHSP-SRC-CORR @ + RUCP-CORRELATION-ATTACHMENT@ ;
: _RSHSP-SRC-SOURCE ( index -- source )
    RUCP-CORRELATION-SIZE * _RSHSP-SRC-CORR @ + RUCP-CORRELATION-SOURCE@ ;
\ The root of an overlay: a document's prompt field, or the dialog widget
\ it shows.  A dialog element is the document's own paint, not an overlay.
: _RSHSP-OVERLAY-CONTROL? ( index -- flag )
    DUP _RSHSP-SRC-KIND DUP RTE-CONTROL-DIALOG = IF
        DROP _RSHSP-SRC-SOURCE UDLSN-SOURCE-OVERLAY = EXIT
    THEN
    RTE-CONTROL-FIELD <> IF DROP 0 EXIT THEN
    _RSHSP-SRC-SOURCE UFLSN-SOURCE-OVERLAY = ;
\ The signed slot of the document a token names; refuses an absent one.
: _RSHSP-DOCUMENT-SLOT ( token -- slot-id )
    _RSHSP-P @ _RTHP.SOURCE-DIR-USED @ RUHA-DOCUMENT-SIZE / 0 ?DO
        _RSHSP-P @ _RTHP.SOURCE-DIR-A @ I RUHA-DOCUMENT-SIZE * +
        2DUP RUHA-DOCUMENT-TOKEN@ = IF NIP RUHA-DOCUMENT-SLOT-ID@ UNLOOP EXIT THEN
        DROP
    LOOP DROP _RSHSP-FAIL ;
\ The SHM entry index of the pane that shows a slot; refuses none.
: _RSHSP-SLOT-PANE ( slot-id -- index )
    _RSHSP-N @ 0 ?DO
        I _RSHSP-ENTRY DUP SHME.KIND @ SHM-K-PANE =
        SWAP SHME.IDENTITY @ 2 PICK = AND IF DROP I UNLOOP EXIT THEN
    LOOP DROP _RSHSP-FAIL ;
: _RSHSP-OVERLAYS! ( -- )
    _RSHSP-N @ _RSHSP-OV-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-OVERLAYS !
    0 _RSHSP-OV-N !
    _RSHSP-P @ _RTHP.CONTROL-COUNT @ 0 ?DO
        I _RSHSP-OVERLAY-CONTROL? IF
            I _RSHSP-SRC-ATTACHMENT _RSHSP-DOCUMENT-SLOT _RSHSP-SLOT-PANE
            \ One overlay a pane.
            _RSHSP-OV-N @ 0 ?DO DUP I _RSHSP-OV 8 + @ <> _RSHSP-CHECK LOOP
            _RSHSP-OV-N @ _RSHSP-N @ U< _RSHSP-CHECK
            _RSHSP-OV-N @ _RSHSP-OV I OVER ! TUCK 8 + ! 0 SWAP 16 + !
            1 _RSHSP-OV-N +!
        THEN
    LOOP ;
: _RSHSP-PANE-OVERLAY ( index -- record|0 )
    _RSHSP-OV-N @ 0 ?DO
        I _RSHSP-OV DUP 8 + @ 2 PICK = IF NIP UNLOOP EXIT THEN DROP
    LOOP DROP 0 ;
: _RSHSP-OV-CONTROL ( record -- control ) @ RTE-CONTROL-SIZE * _RSHSP-SRC-CONTROLS @ + ;
: _RSHSP-BAND-CLEAR ( row col h w -- )
    DUP 0> 2 PICK 0> AND IF _RSHSP-UNCOVERED-CLEAR ELSE 2DROP 2DROP THEN ;
\ The overlay's root lies inside the pane's content, and the four bands of
\ the pane around it are clear.  The overlay's own cells are taken as its
\ paint, as the aggregate adapter took them; a dialog's buttons lie inside
\ its root.
: _RSHSP-OVERLAY-CLEAR ( entry control -- )
    DUP _RTE-CONTROL.ROW @ _RSHSP-OVR ! DUP _RTE-CONTROL.COL @ _RSHSP-OVC !
    DUP _RTE-CONTROL.HEIGHT @ _RSHSP-OVH ! _RTE-CONTROL.WIDTH @ _RSHSP-OVW !
    _RSHSP-E !
    _RSHSP-OVH @ 0> _RSHSP-OVW @ 0> AND _RSHSP-CHECK
    _RSHSP-OVR @ _RSHSP-E @ SHME.CONTENT-ROW @ >= _RSHSP-CHECK
    _RSHSP-OVC @ _RSHSP-E @ SHME.CONTENT-COL @ >= _RSHSP-CHECK
    _RSHSP-OVR @ _RSHSP-OVH @ +
        _RSHSP-E @ SHME.CONTENT-ROW @ _RSHSP-E @ SHME.CONTENT-H @ + > 0= _RSHSP-CHECK
    _RSHSP-OVC @ _RSHSP-OVW @ +
        _RSHSP-E @ SHME.CONTENT-COL @ _RSHSP-E @ SHME.CONTENT-W @ + > 0= _RSHSP-CHECK
    _RSHSP-E @ SHME.ROW @ _RSHSP-E @ SHME.COL @
        _RSHSP-OVR @ _RSHSP-E @ SHME.ROW @ - _RSHSP-E @ SHME.WIDTH @ _RSHSP-BAND-CLEAR
    _RSHSP-OVR @ _RSHSP-OVH @ + _RSHSP-E @ SHME.COL @
        _RSHSP-E @ SHME.ROW @ _RSHSP-E @ SHME.HEIGHT @ + _RSHSP-OVR @ _RSHSP-OVH @ + -
        _RSHSP-E @ SHME.WIDTH @ _RSHSP-BAND-CLEAR
    _RSHSP-OVR @ _RSHSP-E @ SHME.COL @ _RSHSP-OVH @
        _RSHSP-OVC @ _RSHSP-E @ SHME.COL @ - _RSHSP-BAND-CLEAR
    _RSHSP-OVR @ _RSHSP-OVC @ _RSHSP-OVW @ + _RSHSP-OVH @
        _RSHSP-E @ SHME.COL @ _RSHSP-E @ SHME.WIDTH @ + _RSHSP-OVC @ _RSHSP-OVW @ + -
        _RSHSP-BAND-CLEAR ;
\ Every cell of a pane is the shell's to project but its document's overlay
\ and the overlay panes above it.  An overlay pane's cells are its own
\ foreground paint.  Its document shows no overlay of its own, which would
\ need a modal region above the overlay pane's.
: _RSHSP-PANE-CLEAR ( index entry -- )
    DUP _RSHSP-OVERLAY-PANE? IF DROP _RSHSP-PANE-OVERLAY 0= _RSHSP-CHECK EXIT THEN
    SWAP _RSHSP-PANE-OVERLAY ?DUP IF _RSHSP-OV-CONTROL _RSHSP-OVERLAY-CLEAR EXIT THEN
    >R R@ SHME.ROW @ R@ SHME.COL @ R@ SHME.HEIGHT @ R> SHME.WIDTH @
    DUP 0> 2 PICK 0> AND _RSHSP-CHECK _RSHSP-UNCOVERED-CLEAR ;
\ Desk's own prompt, while it holds the hidden taskbar row: its field's
\ UFLD model in the copied shell model, its control and its region.
VARIABLE _RSHSP-PROMPT-A VARIABLE _RSHSP-PROMPT-U VARIABLE _RSHSP-PROMPT-N
VARIABLE _RSHSP-PROMPT-ID VARIABLE _RSHSP-PROMPT-REGION VARIABLE _RSHSP-ROW-ID
: _RSHSP-DIALOGS? ( -- flag )
    _RSHSP-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@ RTE-F-DIALOGS AND 0<> ;
\ The app shell's notice, with dialogs negotiated: its UDLG model in the
\ copied shell model, where its root lies, its control and its region.
\ Without dialogs a notice is paint over the taskbar, as before.
VARIABLE _RSHSP-NOTICE-A VARIABLE _RSHSP-NOTICE-U VARIABLE _RSHSP-NOTICE-N
VARIABLE _RSHSP-NOTICE-ID VARIABLE _RSHSP-NOTICE-REGION
VARIABLE _RSHSP-NR VARIABLE _RSHSP-NC VARIABLE _RSHSP-NH VARIABLE _RSHSP-NW
: _RSHSP-NOTICE! ( -- )
    _RSHSP-DIALOGS? IF _RSHSP-M @ SHM-NOTICE@ ELSE 0 0 THEN
    DUP _RSHSP-NOTICE-U ! SWAP _RSHSP-NOTICE-A ! 0<> 1 AND _RSHSP-NOTICE-N !
    0 _RSHSP-NR ! 0 _RSHSP-NC ! 0 _RSHSP-NH ! 0 _RSHSP-NW !
    _RSHSP-NOTICE-N @ 0= IF EXIT THEN
    _RSHSP-M @ SHM.NOTICE-ROW @ _RSHSP-NR ! _RSHSP-M @ SHM.NOTICE-COL @ _RSHSP-NC !
    _RSHSP-NOTICE-A @ DUP UDLG-HEIGHT@ _RSHSP-NH ! UDLG-WIDTH@ _RSHSP-NW ! ;
: _RSHSP-IN-NOTICE? ( row col -- flag )
    _RSHSP-NC @ - _RSHSP-NW @ U< SWAP _RSHSP-NR @ - _RSHSP-NH @ U< AND ;
\ The notice's cells are its own paint.  A rectangle of the shell is clear
\ when every cell of it the notice leaves is: what one rectangle leaves of
\ another is at most the bands above and below it and the spans beside it.
VARIABLE _RSHSP-NX-R0 VARIABLE _RSHSP-NX-C0 VARIABLE _RSHSP-NX-R1 VARIABLE _RSHSP-NX-C1
VARIABLE _RSHSP-PC-R0 VARIABLE _RSHSP-PC-C0 VARIABLE _RSHSP-PC-R1 VARIABLE _RSHSP-PC-C1
\ Rows R0 to R1 and columns C0 to C1, ends excluded, are clear; an empty
\ part is.
: _RSHSP-PART-CLEAR? ( r0 c0 r1 c1 -- flag )
    _RSHSP-PC-C1 ! _RSHSP-PC-R1 ! _RSHSP-PC-C0 ! _RSHSP-PC-R0 !
    _RSHSP-PC-R1 @ _RSHSP-PC-R0 @ > 0= _RSHSP-PC-C1 @ _RSHSP-PC-C0 @ > 0= OR
        IF -1 EXIT THEN
    _RSHSP-PC-R0 @ _RSHSP-PC-C0 @
    _RSHSP-PC-R1 @ _RSHSP-PC-R0 @ - _RSHSP-PC-C1 @ _RSHSP-PC-C0 @ -
    _RSHSP-P @ _RTHP.SOURCE-DRAW @ _RSHSP-S @ _RSHSP.SOURCE @ SHSN-RECT-CLEAR?
    SHSN-S-OK = AND ;
: _RSHSP-UNNOTICED-CLEAR? ( row col h w -- flag )
    DUP 0> 2 PICK 0> AND 0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK + _RSHSP-NX-C1 ! 2 PICK + _RSHSP-NX-R1 ! _RSHSP-NX-C0 ! _RSHSP-NX-R0 !
    _RSHSP-NOTICE-N @ 0<>
    _RSHSP-NR @ _RSHSP-NX-R1 @ < AND _RSHSP-NR @ _RSHSP-NH @ + _RSHSP-NX-R0 @ > AND
    _RSHSP-NC @ _RSHSP-NX-C1 @ < AND _RSHSP-NC @ _RSHSP-NW @ + _RSHSP-NX-C0 @ > AND 0= IF
        _RSHSP-NX-R0 @ _RSHSP-NX-C0 @ _RSHSP-NX-R1 @ _RSHSP-NX-C1 @ _RSHSP-PART-CLEAR? EXIT
    THEN
    _RSHSP-NX-R0 @ _RSHSP-NX-C0 @ _RSHSP-NR @ _RSHSP-NX-C1 @
        _RSHSP-PART-CLEAR? 0= IF 0 EXIT THEN
    _RSHSP-NR @ _RSHSP-NH @ + _RSHSP-NX-C0 @ _RSHSP-NX-R1 @ _RSHSP-NX-C1 @
        _RSHSP-PART-CLEAR? 0= IF 0 EXIT THEN
    _RSHSP-NR @ _RSHSP-NX-R0 @ MAX _RSHSP-NX-C0 @
        _RSHSP-NR @ _RSHSP-NH @ + _RSHSP-NX-R1 @ MIN _RSHSP-NC @
        _RSHSP-PART-CLEAR? 0= IF 0 EXIT THEN
    _RSHSP-NR @ _RSHSP-NX-R0 @ MAX _RSHSP-NC @ _RSHSP-NW @ +
        _RSHSP-NR @ _RSHSP-NH @ + _RSHSP-NX-R1 @ MIN _RSHSP-NX-C1 @
        _RSHSP-PART-CLEAR? ;
\ Desk's status at the taskbar's right end, with status fields negotiated:
\ its USF model in the copied shell model, where it lies, the identity its
\ static takes and its region.  Its cells the notice leaves must be the
\ shell's own paint; otherwise, or without status fields, it is residual
\ glyphs, as before.
VARIABLE _RSHSP-STATUS-A VARIABLE _RSHSP-STATUS-N
VARIABLE _RSHSP-STATUS-ID VARIABLE _RSHSP-STATUS-REGION
VARIABLE _RSHSP-SR VARIABLE _RSHSP-SC VARIABLE _RSHSP-SW
: _RSHSP-STATUS! ( -- )
    0 _RSHSP-STATUS-N ! 0 _RSHSP-SR ! 0 _RSHSP-SC ! 0 _RSHSP-SW !
    _RSHSP-P @ _RTHP.LIMITS RTE-LIMITS-FEATURES@ RTE-F-STATUS-FIELDS AND 0= IF EXIT THEN
    _RSHSP-M @ SHM-STATUS@ 0= IF DROP EXIT THEN _RSHSP-STATUS-A !
    _RSHSP-M @ SHM.STATUS-ROW @ _RSHSP-SR ! _RSHSP-M @ SHM.STATUS-COL @ _RSHSP-SC !
    _RSHSP-STATUS-A @ USF-WIDTH@ _RSHSP-SW !
    _RSHSP-SR @ _RSHSP-SC @ 1 _RSHSP-SW @ _RSHSP-UNNOTICED-CLEAR?
        1 AND _RSHSP-STATUS-N ! ;
: _RSHSP-ELIGIBILITY ( -- )
    _RSHSP-N @ 0 ?DO I _RSHSP-ENTRY DUP SHME.KIND @ SHM-K-PANE = IF
        DUP _RSHSP-E ! I SWAP _RSHSP-PANE-CLEAR
        I 0 ?DO I _RSHSP-ENTRY DUP SHME.KIND @ SHM-K-PANE = IF
            _RSHSP-E @ _RSHSP-PANES-APART? _RSHSP-CHECK ELSE DROP THEN LOOP
        1 _RSHSP-ELIGIBLE @ I 8 * + !
    ELSE DROP THEN LOOP ;
: _RSHSP-GAP-BLANK? ( row col h w -- flag )
    _RSHSP-BYTES ! DROP _RSHSP-START ! _RSHSP-TEMP !
    _RSHSP-BYTES @ 0 ?DO
        _RSHSP-TEMP @ _RSHSP-START @ I + _RSHSP-IN-NOTICE? 0= IF
            _RSHSP-TEMP @ _RSHSP-START @ I + SCR-GET
            DUP _SCR-C-PAIR AND IF DROP 0 UNLOOP EXIT THEN
            CELL-CP@ DUP 0= SWAP 32 = OR 0= IF 0 UNLOOP EXIT THEN
        THEN
    LOOP -1 ;
: _RSHSP-BAND? ( kind -- flag )
    _RSHSP-KIND !
    _RSHSP-KIND @ _RSHSP-M @ _RSHSP-MU @ _RSHPL-BAND-BOUNDS-PROVED
    RSHPL-S-OK <> IF 2DROP 2DROP 0 EXIT THEN
    _RSHSP-UNNOTICED-CLEAR? 0= IF 0 EXIT THEN
    0 _RSHSP-I ! BEGIN
        _RSHSP-I @ _RSHSP-KIND @ _RSHSP-M @ _RSHSP-MU @ _RSHPL-GAP-BOUNDS-PROVED
        DUP RSHPL-S-END = IF DROP 2DROP 2DROP -1 EXIT THEN
        RSHPL-S-OK <> IF 2DROP 2DROP 0 EXIT THEN
        _RSHSP-GAP-BLANK? 0= IF 0 EXIT THEN 1 _RSHSP-I +!
    AGAIN ;

: _RSHSP-ALLOCATE-PLAN ( -- )
    _RSHSP-N @ 8 _RSHSP-MUL _RSHSP-TAKE _RSHSP-ELIGIBLE !
    RSHPL-REQUEST-SIZE _RSHSP-TAKE _RSHSP-Q !
    RSHPL-RESULT-SIZE _RSHSP-TAKE _RSHSP-RESULT !
    _RSHSP-N @ 2 _RSHSP-ADD 96 _RSHSP-MUL _RSHSP-TAKE _RSHSP-REGIONS !
    _RSHSP-N @ RTE-PANE-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-PANES !
    _RSHSP-N @ 2 _RSHSP-ADD RTE-CONTROL-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-CONTROLS !
    _RSHSP-MU @ _RSHSP-TAKE _RSHSP-TEXT !
    _RSHSP-N @ 2 _RSHSP-ADD RSHPL-CORRELATION-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-CORR !
    _RSHSP-N @ 4 _RSHSP-MUL 2 _RSHSP-ADD RSHPL-CLAIM-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-CLAIMS !
    _RSHSP-MU @ _RSHSP-TAKE _RSHSP-ACTIONS !
    _RSHSP-N @ RSHMM-ENTRY-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-MAP !
    _RSHSP-M @ SHM-PROMPT@ DUP _RSHSP-PROMPT-U ! SWAP _RSHSP-PROMPT-A !
        IF 1 ELSE 0 THEN _RSHSP-PROMPT-N !
    _RSHSP-NOTICE! _RSHSP-STATUS!
    _RSHSP-OVERLAYS! _RSHSP-ELIGIBILITY
    0 _RSHSP-BANDS !
    SHM-K-TASK _RSHSP-BAND? IF 1 _RSHSP-BANDS +! THEN
    SHM-K-LAUNCHER _RSHSP-BAND? IF 2 _RSHSP-BANDS +! THEN
    _RSHSP-N @ 0 ?DO I _RSHSP-ENTRY SHME.KIND @
        DUP SHM-K-TASK = IF _RSHSP-BANDS @ 1 AND 0= IF 0 _RSHSP-BANDS ! THEN THEN
        SHM-K-LAUNCHER = IF _RSHSP-BANDS @ 2 AND 0= IF 0 _RSHSP-BANDS ! THEN THEN
    LOOP
    \ The panes' content takes the Z of the candidate's own region, above
    \ its instrument regions (_RTHP-BASE-LAYER!); the chrome lies above.
    _RSHSP-P @ _RTHP.BASE-Z @ DUP 2147483643 > IF DROP _RSHSP-FAIL THEN
        _RSHSP-CONTENT-Z !
    _RSHSP-P @ _RTHP.REGION @ _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ _RSHSP-ADD
        1 _RSHSP-ADD _RSHSP-FIRST-REGION !
    \ The first identity past the base candidate's objects.  The shell's
    \ controls take the identities after the applet controls, COPY-RUN moves
    \ the statics and instruments up past them, and Desk's status, which
    \ takes this one, with them.  The panes and residual glyphs follow.
    _RSHSP-P @ _RTHP.FIRST-OBJECT @ _RSHSP-P @ _RTHP.CONTROL-COUNT @ _RSHSP-ADD
        _RSHSP-P @ _RTHP.INSTRUMENT-LAST @ 1 _RSHSP-ADD MAX
        _RSHSP-P @ _RTHP.STATIC-LAST @ 1 _RSHSP-ADD MAX _RSHSP-STATUS-ID !
    _RSHSP-M @ _RSHSP-MU @ _RSHSP-M @ SHM.OWNER-ID @
    _RSHSP-P @ _RTHP.SOURCE-DRAW @ _RSHSP-ELIGIBLE @ _RSHSP-N @ 8 *
    _RSHSP-BANDS @ _RSHSP-Q @ RSHPL-REQUEST-SOURCE!
    _RSHSP-P @ _RTHP.OWNER @ _RSHSP-P @ _RTHP.OWNER-GEN @ _RSHSP-FIRST-REGION @
    _RSHSP-STATUS-ID @ _RSHSP-N @ _RSHSP-ADD 2 _RSHSP-ADD _RSHSP-NOTICE-N @ _RSHSP-ADD
        _RSHSP-STATUS-N @ _RSHSP-ADD
    _RSHSP-P @ _RTHP.FIRST-OBJECT @ _RSHSP-P @ _RTHP.CONTROL-COUNT @ _RSHSP-ADD
    _RSHSP-Q @ RSHPL-REQUEST-IDENTITY!
    -3 _RSHSP-CONTENT-Z @ _RSHSP-CONTENT-Z @ 1+ _RSHSP-Q @ RSHPL-REQUEST-Z!
    _RSHSP-REGIONS @ _RSHSP-N @ 2 + 96 *
    _RSHSP-PANES @ _RSHSP-N @ RTE-PANE-SIZE *
    _RSHSP-CONTROLS @ _RSHSP-N @ 2 + RTE-CONTROL-SIZE *
    _RSHSP-TEXT @ _RSHSP-MU @
    _RSHSP-CORR @ _RSHSP-N @ 2 + RSHPL-CORRELATION-SIZE *
    _RSHSP-CLAIMS @ _RSHSP-N @ 4 * 2 + RSHPL-CLAIM-SIZE *
    _RSHSP-ACTIONS @ _RSHSP-MU @ _RSHSP-RESULT @ RSHPL-RESULT-SIZE
    _RSHSP-Q @ RSHPL-REQUEST-OUTPUT!
    _RSHSP-Q @ _RSHPL-BUILD-PROVED RSHPL-S-OK = _RSHSP-CHECK
    _RSHSP-RESULT @ RSHPL-RESULT.PANES @
    _RSHSP-RESULT @ RSHPL-RESULT.TASKBARS @ OR _RSHSP-CHECK
    _RSHSP-RESULT @ RSHPL-RESULT.CONTROLS @ _RSHSP-SHELL-CONTROLS !
    \ Desk's prompt follows the shell's taskbar controls, and the notice it.
    _RSHSP-PROMPT-N @ IF
        _RSHSP-P @ _RTHP.FIRST-OBJECT @ _RSHSP-P @ _RTHP.CONTROL-COUNT @ _RSHSP-ADD
        _RSHSP-SHELL-CONTROLS @ _RSHSP-ADD
    ELSE 0 THEN _RSHSP-PROMPT-ID !
    _RSHSP-NOTICE-N @ IF
        _RSHSP-P @ _RTHP.FIRST-OBJECT @ _RSHSP-P @ _RTHP.CONTROL-COUNT @ _RSHSP-ADD
        _RSHSP-SHELL-CONTROLS @ _RSHSP-ADD _RSHSP-PROMPT-N @ _RSHSP-ADD
    ELSE 0 THEN _RSHSP-NOTICE-ID !
    _RSHSP-Q @ _RSHPL-Q.FIRST-OBJECT @
        _RSHSP-RESULT @ RSHPL-RESULT.PANES @ _RSHSP-ADD _RSHSP-NEXT-ID !
    _RSHSP-M @ _RSHSP-MU @
    _RSHSP-P @ _RTHP.SOURCE-DIR-A @ _RSHSP-P @ _RTHP.SOURCE-DIR-USED @
    _RSHSP-CORR @ _RSHSP-RESULT @ RSHPL-RESULT.CORRELATIONS @ RSHPL-CORRELATION-SIZE *
    _RSHSP-MAP @ _RSHSP-N @ RSHMM-ENTRY-SIZE * _RSHMM-BUILD-PROVED
        RSHMM-S-OK = _RSHSP-CHECK _RSHSP-MAP-U ! DROP ;

: _RSHSP-INSTRUMENT-CLIP! ( copied-region -- )
    \ RUIP omits an explicit clip when it equals the complete logical root.
    \ Shell ownership uses the same physical rectangle in explicit form.
    DUP _RTE-IR.FLAGS @ RTE-REGION-CLIPPED AND IF DROP EXIT THEN
    DUP _RTE-IR.X @ OVER _RTE-IR.CLIP-X !
    DUP _RTE-IR.Y @ OVER _RTE-IR.CLIP-Y !
    DUP _RTE-IR.COLS @ OVER _RTE-IR.CLIP-COLS !
    DUP _RTE-IR.ROWS @ OVER _RTE-IR.CLIP-ROWS !
    DUP _RTE-IR.FLAGS @ RTE-REGION-CLIPPED OR SWAP _RTE-IR.FLAGS ! ;

\ A modal region for each overlay follows the planner's regions.  Like a
\ pane's content region it has the surface as its logical bounds and the
\ pane's content as its clip, and it sits above every region of the shell.
: _RSHSP-MODAL-ROWS ( first-row -- next-row )
    _RSHSP-MODAL-N @ 0 ?DO
        I _RSHSP-OV 8 + @ _RSHSP-ENTRY _RSHSP-E !
        _RSHSP-ROW-ID @ I _RSHSP-OV 16 + !
        _RSHSP-ROW-ID @ OVER _RTE-IR.ID ! 1 _RSHSP-ROW-ID +!
        _RSHSP-P @ _RTHP.COLS @ OVER _RTE-IR.COLS !
        _RSHSP-P @ _RTHP.ROWS @ OVER _RTE-IR.ROWS !
        _RSHSP-E @ SHME.CONTENT-COL @ OVER _RTE-IR.CLIP-X !
        _RSHSP-E @ SHME.CONTENT-ROW @ OVER _RTE-IR.CLIP-Y !
        _RSHSP-E @ SHME.CONTENT-W @ OVER _RTE-IR.CLIP-COLS !
        _RSHSP-E @ SHME.CONTENT-H @ OVER _RTE-IR.CLIP-ROWS !
        _RSHSP-CONTENT-Z @ 2 + OVER _RTE-IR.Z !
        RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR
            OVER _RTE-IR.FLAGS !
        96 +
    LOOP ;
\ An overlay pane's host gives it every key while it is open and ignores a
\ press outside it, as Desk does its own screens.  With dialogs the
\ overlay pane's document therefore goes in a modal region over the whole
\ screen, surface-sized with the surface as its clip: a modal scope over
\ everything beneath it.  The regions follow the overlays' modal regions
\ at the same z, so they lie above them, and Desk's prompt lies above all.
VARIABLE _RSHSP-SCREEN-N VARIABLE _RSHSP-SCREEN-FIRST
: _RSHSP-SCREEN-ROWS ( first-row -- next-row )
    _RSHSP-ROW-ID @ _RSHSP-SCREEN-FIRST !
    _RSHSP-SCREEN-N @ 0 ?DO
        _RSHSP-ROW-ID @ OVER _RTE-IR.ID ! 1 _RSHSP-ROW-ID +!
        _RSHSP-P @ _RTHP.COLS @ 2DUP SWAP _RTE-IR.COLS ! OVER _RTE-IR.CLIP-COLS !
        _RSHSP-P @ _RTHP.ROWS @ 2DUP SWAP _RTE-IR.ROWS ! OVER _RTE-IR.CLIP-ROWS !
        _RSHSP-CONTENT-Z @ 2 + OVER _RTE-IR.Z !
        RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR
            OVER _RTE-IR.FLAGS !
        96 +
    LOOP ;
\ The modal region of the overlay pane at INDEX, in pane order, or 0.
: _RSHSP-SCREEN-REGION ( index -- region|0 )
    _RSHSP-SCREEN-N @ 0= IF DROP 0 EXIT THEN
    DUP _RSHSP-ENTRY _RSHSP-OVERLAY-PANE? 0= IF DROP 0 EXIT THEN
    _RSHSP-SCREEN-FIRST @ SWAP 0 ?DO
        I _RSHSP-ENTRY _RSHSP-OVERLAY-PANE? IF 1+ THEN
    LOOP ;
\ Desk's own prompt holds the hidden taskbar row.  With dialogs its region
\ is a modal scope over the whole screen, since Desk takes no other input
\ while the prompt is open; without them it is that row alone.  It sits
\ above every other region of the shell, the panes' modal regions too.
: _RSHSP-PROMPT-REGION-ROW ( row -- next-row )
    _RSHSP-PROMPT-N @ 0= IF 0 _RSHSP-PROMPT-REGION ! EXIT THEN
    _RSHSP-ROW-ID @ DUP _RSHSP-PROMPT-REGION ! OVER _RTE-IR.ID ! 1 _RSHSP-ROW-ID +!
    _RSHSP-P @ _RTHP.COLS @ 2DUP SWAP _RTE-IR.COLS ! OVER _RTE-IR.CLIP-COLS !
    _RSHSP-P @ _RTHP.ROWS @ OVER _RTE-IR.ROWS !
    _RSHSP-DIALOGS? IF
        _RSHSP-P @ _RTHP.ROWS @ OVER _RTE-IR.CLIP-ROWS !
        RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR RTE-REGION-MODAL OR
    ELSE
        _RSHSP-P @ _RTHP.ROWS @ 1- OVER _RTE-IR.CLIP-Y !
        1 OVER _RTE-IR.CLIP-ROWS !
        RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR
    THEN OVER _RTE-IR.FLAGS !
    _RSHSP-CONTENT-Z @ 3 + OVER _RTE-IR.Z ! 96 + ;
\ The app shell's notice lies in a region of its own, its rectangle the
\ clip, above every other region of the shell, Desk's prompt too.  It is no
\ modal scope: the notice takes no input, and what lies beneath it stays
\ active.
: _RSHSP-NOTICE-REGION-ROW ( row -- next-row )
    _RSHSP-NOTICE-N @ 0= IF 0 _RSHSP-NOTICE-REGION ! EXIT THEN
    _RSHSP-ROW-ID @ DUP _RSHSP-NOTICE-REGION ! OVER _RTE-IR.ID ! 1 _RSHSP-ROW-ID +!
    _RSHSP-P @ _RTHP.COLS @ OVER _RTE-IR.COLS !
    _RSHSP-P @ _RTHP.ROWS @ OVER _RTE-IR.ROWS !
    _RSHSP-NC @ OVER _RTE-IR.CLIP-X ! _RSHSP-NR @ OVER _RTE-IR.CLIP-Y !
    _RSHSP-NW @ OVER _RTE-IR.CLIP-COLS ! _RSHSP-NH @ OVER _RTE-IR.CLIP-ROWS !
    _RSHSP-CONTENT-Z @ 4 + OVER _RTE-IR.Z !
    RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR OVER _RTE-IR.FLAGS !
    96 + ;

\ Desk's status lies in a region of its own across the taskbar's right end,
\ past its entries, at the taskbar's z.  It takes no input.
: _RSHSP-STATUS-REGION-ROW ( row -- next-row )
    _RSHSP-STATUS-N @ 0= IF 0 _RSHSP-STATUS-REGION ! EXIT THEN
    _RSHSP-ROW-ID @ DUP _RSHSP-STATUS-REGION ! OVER _RTE-IR.ID ! 1 _RSHSP-ROW-ID +!
    _RSHSP-P @ _RTHP.COLS @ OVER _RTE-IR.COLS !
    _RSHSP-P @ _RTHP.ROWS @ OVER _RTE-IR.ROWS !
    _RSHSP-M @ SHM.END-COL @ OVER _RTE-IR.CLIP-X ! _RSHSP-SR @ OVER _RTE-IR.CLIP-Y !
    _RSHSP-P @ _RTHP.COLS @ _RSHSP-M @ SHM.END-COL @ - OVER _RTE-IR.CLIP-COLS !
    1 OVER _RTE-IR.CLIP-ROWS !
    _RSHSP-CONTENT-Z @ 1+ OVER _RTE-IR.Z !
    RTE-REGION-VISIBLE RTE-REGION-CLIPPED OR OVER _RTE-IR.FLAGS !
    96 + ;

: _RSHSP-CATALOG! ( -- )
    RTE-REGION-CATALOG-SIZE _RSHSP-TAKE _RSHSP-CATALOG !
    _RSHSP-P @ _RTHP.OWNER @ _RSHSP-CATALOG @ _RTE-RC.OWNER !
    _RSHSP-P @ _RTHP.OWNER-GEN @ _RSHSP-CATALOG @ _RTE-RC.GENERATION !
    _RSHSP-P @ _RTHP.COLS @ _RSHSP-CATALOG @ _RTE-RC.SURFACE-COLS !
    _RSHSP-P @ _RTHP.ROWS @ _RSHSP-CATALOG @ _RTE-RC.SURFACE-ROWS !
    _RSHSP-DIALOGS? IF _RSHSP-OV-N @ ELSE 0 THEN _RSHSP-MODAL-N !
    0 _RSHSP-SCREEN-N ! _RSHSP-DIALOGS? IF
        _RSHSP-N @ 0 ?DO
            I _RSHSP-ENTRY _RSHSP-OVERLAY-PANE? IF 1 _RSHSP-SCREEN-N +! THEN
        LOOP
    THEN
    _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @
    _RSHSP-RESULT @ RSHPL-RESULT.REGIONS @ _RSHSP-ADD 1 _RSHSP-ADD
    _RSHSP-MODAL-N @ _RSHSP-ADD _RSHSP-SCREEN-N @ _RSHSP-ADD
    _RSHSP-PROMPT-N @ _RSHSP-ADD _RSHSP-NOTICE-N @ _RSHSP-ADD
    _RSHSP-STATUS-N @ _RSHSP-ADD _RSHSP-REGION-N !
    _RSHSP-REGION-N @ 96 _RSHSP-MUL _RSHSP-TAKE _RSHSP-OUT !
    _RSHSP-OUT @ _RSHSP-CATALOG @ _RTE-RC.REGIONS-A !
    _RSHSP-REGION-N @ 96 * _RSHSP-CATALOG @ _RTE-RC.REGIONS-U !
    _RSHSP-P @ _RTHP.REGION @ _RSHSP-OUT @ _RTE-IR.ID !
    _RSHSP-P @ _RTHP.COLS @ _RSHSP-OUT @ _RTE-IR.COLS !
    _RSHSP-P @ _RTHP.ROWS @ _RSHSP-OUT @ _RTE-IR.ROWS !
    -2 _RSHSP-OUT @ _RTE-IR.Z !
    RTE-REGION-VISIBLE _RSHSP-OUT @ _RTE-IR.FLAGS !
    _RSHSP-SRC-REGIONS @ _RSHSP-OUT @ 96 +
        _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 96 * MOVE
    _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 0 ?DO
        _RSHSP-OUT @ I 1+ 96 * + _RSHSP-INSTRUMENT-CLIP!
    LOOP
    _RSHSP-REGIONS @ _RSHSP-OUT @ _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 1+ 96 * +
        _RSHSP-RESULT @ RSHPL-RESULT.REGIONS @ 96 * MOVE
    _RSHSP-FIRST-REGION @ _RSHSP-RESULT @ RSHPL-RESULT.REGIONS @ + _RSHSP-ROW-ID !
    _RSHSP-OUT @ _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 1+
        _RSHSP-RESULT @ RSHPL-RESULT.REGIONS @ + 96 * + _RSHSP-MODAL-ROWS
        _RSHSP-SCREEN-ROWS _RSHSP-PROMPT-REGION-ROW _RSHSP-NOTICE-REGION-ROW
        _RSHSP-STATUS-REGION-ROW DROP
    _RSHSP-CATALOG @ RTE-REGION-CATALOG-VALID? _RSHSP-CHECK
    _RSHSP-P @ _RTHP.CONTROL-COUNT @ _RSHSP-P @ _RTHP.STATIC-COUNT @ _RSHSP-ADD
    _RSHSP-N @ _RSHSP-ADD 6 _RSHSP-ADD _RSHSP-PROMPT-N @ _RSHSP-ADD
    _RSHSP-NOTICE-N @ _RSHSP-ADD _RSHSP-STATUS-N @ _RSHSP-ADD _RSHSP-FAMILY-CAP !
    _RSHSP-FAMILY-CAP @ RTE-FAMILY-ENTRY-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-FAMILIES !
    0 _RSHSP-FAMILY-N !
    RTE-FAMILY-BATCH-SIZE _RSHSP-TAKE _RSHSP-BATCH !
    RTE-FAMILY-ADMISSION-SIZE _RSHSP-TAKE _RSHSP-ADMISSION ! ;

\ A new family starts with a copied catalog row.  Text is compacted in item
\ order so the immutable clone never retains a containing source arena.
: _RSHSP-FAMILY! ( kind -- )
    _RSHSP-KIND !
    _RSHSP-FAMILY-N @ _RSHSP-FAMILY-CAP @ U< _RSHSP-CHECK
    _RSHSP-FAMILIES @ _RSHSP-FAMILY-N @ RTE-FAMILY-ENTRY-SIZE * + _RSHSP-FAMILY !
    1 _RSHSP-FAMILY-N +!
    _RSHSP-KIND @ _RSHSP-FAMILY @ _RTE-FE.KIND !
    _RSHSP-KIND @ RTE-FAMILY-PLAN-SIZE DUP _RSHSP-FAMILY @ _RTE-FE.PLAN-U !
        _RSHSP-TAKE DUP _RSHSP-PLAN ! _RSHSP-FAMILY @ _RTE-FE.PLAN-A !
    _RSHSP-CATALOG @ _RSHSP-PLAN @ 32 MOVE ;
: _RSHSP-PLAN-REGION! ( id -- )
    _RSHSP-REGION@ _RSHSP-PLAN @ 32 + 88 MOVE ;
: _RSHSP-PLAN-ITEMS! ( a u -- )
    _RSHSP-PLAN @ _RTE-CP.ITEMS-U ! _RSHSP-PLAN @ _RTE-CP.ITEMS-A ! ;
: _RSHSP-FAMILY-BYTES! ( a u -- )
    _RSHSP-ZSPAN _RSHSP-FAMILY @ _RTE-FE.BYTES-U ! _RSHSP-FAMILY @ _RTE-FE.BYTES-A ! ;
: _RSHSP-DENSE! ( pointer-field -- )
    DUP 8 + @ DUP IF
        _RSHSP-TEMP ! DUP @ _RSHSP-CURSOR @ _RSHSP-TEMP @ MOVE
        _RSHSP-CURSOR @ SWAP ! _RSHSP-TEMP @ _RSHSP-CURSOR +!
    ELSE 2DROP THEN ;
: _RSHSP-TEXT-MEASURE ( items n stride -- bytes )
    _RSHSP-STRIDE ! _RSHSP-COUNT ! _RSHSP-ITEM ! 0
    _RSHSP-COUNT @ 0 ?DO
        _RSHSP-KIND @ RTE-FAMILY-CONTROL = IF
            _RSHSP-ITEM @ _RTE-CONTROL.LABEL-U @ _RSHSP-ADD
            _RSHSP-ITEM @ _RTE-CONTROL.SHORTCUT-U @ _RSHSP-ADD
            _RSHSP-ITEM @ _RTE-CONTROL.CONTENT-U @ _RSHSP-ADD
        ELSE
            _RSHSP-ITEM @ _RTE-STATIC.LABEL-U @ _RSHSP-ADD
            _RSHSP-ITEM @ _RTE-STATIC.VALUE-U @ _RSHSP-ADD
        THEN _RSHSP-STRIDE @ _RSHSP-ITEM +!
    LOOP ;
: _RSHSP-COPY-RUN ( a n kind region -- )
    _RSHSP-REGION ! _RSHSP-FAMILY! _RSHSP-COUNT ! _RSHSP-START !
    _RSHSP-REGION @ _RSHSP-PLAN-REGION!
    _RSHSP-KIND @ RTE-FAMILY-ITEM-SIZE _RSHSP-STRIDE !
    _RSHSP-START @ _RSHSP-COUNT @ _RSHSP-STRIDE @ _RSHSP-MUL
        DUP _RSHSP-BYTES ! _RSHSP-COPY _RSHSP-OUT !
    _RSHSP-OUT @ _RSHSP-BYTES @ _RSHSP-PLAN-ITEMS!
    _RSHSP-OUT @ _RSHSP-COUNT @ _RSHSP-STRIDE @ _RSHSP-TEXT-MEASURE
        DUP _RSHSP-BYTES ! _RSHSP-TAKE _RSHSP-START !
    _RSHSP-CURSOR @ _RSHSP-SAVED ! _RSHSP-START @ _RSHSP-CURSOR !
    _RSHSP-COUNT @ 0 ?DO
        _RSHSP-OUT @ I _RSHSP-STRIDE @ * + _RSHSP-ITEM !
        _RSHSP-KIND @ RTE-FAMILY-CONTROL = IF
            _RSHSP-REGION @ _RSHSP-ITEM @ _RTE-CONTROL.REGION !
            _RSHSP-ITEM @ _RTE-CONTROL.LABEL-A _RSHSP-DENSE!
            _RSHSP-ITEM @ _RTE-CONTROL.SHORTCUT-A _RSHSP-DENSE!
            _RSHSP-ITEM @ _RTE-CONTROL.CONTENT-A _RSHSP-DENSE!
        ELSE
            _RSHSP-REGION @ _RSHSP-ITEM @ _RTE-STATIC.REGION !
            _RSHSP-SHELL-CONTROLS @ _RSHSP-PROMPT-N @ + _RSHSP-NOTICE-N @ +
                _RSHSP-ITEM @ _RTE-STATIC.ID +!
            _RSHSP-ITEM @ _RTE-STATIC.LABEL-A _RSHSP-DENSE!
            _RSHSP-ITEM @ _RTE-STATIC.VALUE-A _RSHSP-DENSE!
        THEN
    LOOP
    _RSHSP-SAVED @ _RSHSP-CURSOR ! _RSHSP-START @ _RSHSP-BYTES @ _RSHSP-FAMILY-BYTES! ;
\ An overlay with a modal region goes there, and any other control of an
\ overlay pane's document to that pane's modal region; any other control
\ goes to the content region of its document's pane.
: _RSHSP-ROOT-MEMBER ( index -- region )
    _RSHSP-MODAL-N @ 0 ?DO
        I _RSHSP-OV @ OVER = IF DROP I _RSHSP-OV 16 + @ UNLOOP EXIT THEN
    LOOP
    _RSHSP-SRC-ATTACHMENT _RSHSP-MEMBER@
    DUP RSHMM.SOURCE-INDEX @ _RSHSP-SCREEN-REGION ?DUP IF NIP EXIT THEN
    RSHMM.CONTENT-REGION @ ;
\ A dialog widget's button goes where its dialog does: the overlay of its
\ pane.
: _RSHSP-CONTROL-MEMBER ( index -- region )
    DUP _RSHSP-SRC-KIND RTE-CONTROL-BUTTON =
    OVER _RSHSP-SRC-SOURCE UDLSN-SOURCE-OVERLAY = AND IF
        _RSHSP-SRC-ATTACHMENT _RSHSP-DOCUMENT-SLOT _RSHSP-SLOT-PANE
        _RSHSP-PANE-OVERLAY DUP _RSHSP-CHECK @
        DUP _RSHSP-SRC-KIND RTE-CONTROL-DIALOG = _RSHSP-CHECK
    THEN
    _RSHSP-ROOT-MEMBER ;
\ Desk's prompt as a FIELD: its field's FDC1 on a root across the hidden
\ taskbar row.
: _RSHSP-PROMPT-CONTROL ( -- )
    _RSHSP-PROMPT-N @ 0= IF EXIT THEN
    _RSHSP-PROMPT-A @ _RSHSP-PROMPT-U @ UFLDC-BYTES UFLDC-S-OK = _RSHSP-CHECK
    DUP _RSHSP-TAKE _RSHSP-OUT !
    _RSHSP-PROMPT-A @ _RSHSP-PROMPT-U @ _RSHSP-OUT @ 3 PICK UFLDC-PACK
        UFLDC-S-OK = _RSHSP-CHECK OVER = _RSHSP-CHECK
    RTE-CONTROL-SIZE _RSHSP-TAKE >R
    _RSHSP-P @ _RTHP.OWNER @ R@ _RTE-CONTROL.OWNER !
    _RSHSP-P @ _RTHP.OWNER-GEN @ R@ _RTE-CONTROL.GENERATION !
    _RSHSP-PROMPT-ID @ R@ _RTE-CONTROL.ID !
    RTE-CONTROL-FIELD R@ _RTE-CONTROL.KIND !
    _RSHSP-PROMPT-A @ UFLD-STATE@ _RTHP-FF-STATE R@ _RTE-CONTROL.STATE !
    _RSHSP-P @ _RTHP.ROWS @ DUP R@ _RTE-CONTROL.ROOT-HEIGHT ! 1- R@ _RTE-CONTROL.ROW !
    1 R@ _RTE-CONTROL.HEIGHT !
    _RSHSP-P @ _RTHP.COLS @ DUP R@ _RTE-CONTROL.ROOT-WIDTH ! R@ _RTE-CONTROL.WIDTH !
    _RSHSP-PROMPT-A @ UFLD-LABEL@ R@ _RTE-CONTROL.LABEL-U ! R@ _RTE-CONTROL.LABEL-A !
    _RSHSP-OUT @ R@ _RTE-CONTROL.CONTENT-A ! R@ _RTE-CONTROL.CONTENT-U !
    _RSHSP-PROMPT-A @ DUP UFLD-UTF8-BYTES@ SWAP UFLD-LABEL-BYTES@ -
        R@ _RTE-CONTROL.CONTENT-UTF8 !
    R> 1 RTE-FAMILY-CONTROL _RSHSP-PROMPT-REGION @ _RSHSP-COPY-RUN ;
\ The app shell's notice as a DIALOG: its model's DLG1 on a root where the
\ notice lies, its title the label.
: _RSHSP-NOTICE-CONTROL ( -- )
    _RSHSP-NOTICE-N @ 0= IF EXIT THEN
    _RSHSP-NOTICE-A @ _RSHSP-NOTICE-U @ UDLGC-DIALOG-BYTES 0= _RSHSP-CHECK
    DUP _RSHSP-TAKE _RSHSP-OUT !
    _RSHSP-NOTICE-A @ _RSHSP-NOTICE-U @ _RSHSP-OUT @ 3 PICK UDLGC-DIALOG-PACK
        0= _RSHSP-CHECK OVER = _RSHSP-CHECK
    RTE-CONTROL-SIZE _RSHSP-TAKE >R
    _RSHSP-P @ _RTHP.OWNER @ R@ _RTE-CONTROL.OWNER !
    _RSHSP-P @ _RTHP.OWNER-GEN @ R@ _RTE-CONTROL.GENERATION !
    _RSHSP-NOTICE-ID @ R@ _RTE-CONTROL.ID !
    RTE-CONTROL-DIALOG R@ _RTE-CONTROL.KIND !
    RTE-CONTROL-VISIBLE R@ _RTE-CONTROL.STATE !
    _RSHSP-NR @ R@ _RTE-CONTROL.ROW ! _RSHSP-NC @ R@ _RTE-CONTROL.COL !
    _RSHSP-NH @ R@ _RTE-CONTROL.HEIGHT ! _RSHSP-NW @ R@ _RTE-CONTROL.WIDTH !
    _RSHSP-P @ _RTHP.ROWS @ R@ _RTE-CONTROL.ROOT-HEIGHT !
    _RSHSP-P @ _RTHP.COLS @ R@ _RTE-CONTROL.ROOT-WIDTH !
    _RSHSP-NOTICE-A @ UDLG-TITLE@ _RSHSP-ZSPAN
        R@ _RTE-CONTROL.LABEL-U ! R@ _RTE-CONTROL.LABEL-A !
    _RSHSP-OUT @ R@ _RTE-CONTROL.CONTENT-A ! R@ _RTE-CONTROL.CONTENT-U !
    _RSHSP-NOTICE-A @ UDLG-MESSAGE-BYTES@ R@ _RTE-CONTROL.CONTENT-UTF8 !
    R> 1 RTE-FAMILY-CONTROL _RSHSP-NOTICE-REGION @ _RSHSP-COPY-RUN ;
: _RSHSP-APP-CONTROLS ( -- )
    0 _RSHSP-I ! BEGIN _RSHSP-I @ _RSHSP-P @ _RTHP.CONTROL-COUNT @ U< WHILE
        _RSHSP-I @ _RSHSP-CONTROL-MEMBER _RSHSP-MEMBER !
        _RSHSP-I @ _RSHSP-J !
        -1 _RSHSP-RUN !
        BEGIN _RSHSP-J @ _RSHSP-P @ _RTHP.CONTROL-COUNT @ U< _RSHSP-RUN @ AND WHILE
            _RSHSP-J @ _RSHSP-CONTROL-MEMBER _RSHSP-MEMBER @ <> IF 0 _RSHSP-RUN !
            ELSE 1 _RSHSP-J +! THEN
        REPEAT
        _RSHSP-SRC-CONTROLS @ _RSHSP-I @ RTE-CONTROL-SIZE * +
        _RSHSP-J @ _RSHSP-I @ - RTE-FAMILY-CONTROL _RSHSP-MEMBER @ _RSHSP-COPY-RUN
        _RSHSP-J @ _RSHSP-I !
    REPEAT
    _RSHSP-SHELL-CONTROLS @ IF
        \ Both canonical roots belong to the planner's one taskbar region.
        \ Refuse a changed planner contract before COPY-RUN rewrites regions.
        _RSHSP-SHELL-CONTROLS @ 0 ?DO
            _RSHSP-CONTROLS @ I RTE-CONTROL-SIZE * + _RTE-CONTROL.REGION @
            _RSHSP-CONTROLS @ _RTE-CONTROL.REGION @ = _RSHSP-CHECK
        LOOP
        _RSHSP-CONTROLS @ _RSHSP-SHELL-CONTROLS @ RTE-FAMILY-CONTROL
        _RSHSP-CONTROLS @ _RTE-CONTROL.REGION @ _RSHSP-COPY-RUN
    THEN
    _RSHSP-PROMPT-CONTROL _RSHSP-NOTICE-CONTROL ;
: _RSHSP-STATICS ( -- )
    _RSHSP-P @ _RTHP.STATIC-COUNT @ 0 ?DO
        _RSHSP-P @ _RTHP.STATIC-CORR-A @ I _RTHP-STATIC-CORR-SIZE * + @
            _RSHSP-MEMBER@ RSHMM.CONTENT-REGION @ _RSHSP-MEMBER !
        _RSHSP-P @ _RTHP.STATICS-A @ I RTE-STATIC-SIZE * +
            1 RTE-FAMILY-STATIC _RSHSP-MEMBER @ _RSHSP-COPY-RUN
    LOOP ;

\ Desk's status as a STATUS_FIELD: its model's label, value, severity and
\ emphasis on a root where it lies.
: _RSHSP-STATUS-STATIC ( -- )
    _RSHSP-STATUS-N @ 0= IF EXIT THEN
    RTE-STATIC-SIZE _RSHSP-TAKE >R
    _RSHSP-P @ _RTHP.OWNER @ R@ _RTE-STATIC.OWNER !
    _RSHSP-P @ _RTHP.OWNER-GEN @ R@ _RTE-STATIC.GENERATION !
    _RSHSP-STATUS-ID @ R@ _RTE-STATIC.ID !
    RTE-STATIC-STATUS-FIELD R@ _RTE-STATIC.KIND !
    -1 R@ _RTE-STATIC.VISIBLE !
    _RSHSP-SR @ R@ _RTE-STATIC.ROW ! _RSHSP-SC @ R@ _RTE-STATIC.COL !
    1 R@ _RTE-STATIC.HEIGHT ! _RSHSP-SW @ R@ _RTE-STATIC.WIDTH !
    _RSHSP-P @ _RTHP.ROWS @ R@ _RTE-STATIC.ROOT-HEIGHT !
    _RSHSP-P @ _RTHP.COLS @ R@ _RTE-STATIC.ROOT-WIDTH !
    _RSHSP-STATUS-A @ USF-LABEL-COLS@ R@ _RTE-STATIC.LABEL-COLS !
    _RSHSP-STATUS-A @ USF-SEVERITY@ R@ _RTE-STATIC.SEVERITY !
    _RSHSP-STATUS-A @ USF-FLAGS@ USF-F-EMPHASIZED AND 0<> R@ _RTE-STATIC.EMPHASIZED !
    _RSHSP-STATUS-A @ USF-LABEL@ _RSHSP-ZSPAN
        R@ _RTE-STATIC.LABEL-U ! R@ _RTE-STATIC.LABEL-A !
    _RSHSP-STATUS-A @ USF-VALUE@ _RSHSP-ZSPAN
        R@ _RTE-STATIC.VALUE-U ! R@ _RTE-STATIC.VALUE-A !
    R> 1 RTE-FAMILY-STATIC _RSHSP-STATUS-REGION @ _RSHSP-COPY-RUN ;

: _RSHSP-SERIES ( -- )
    _RSHSP-P @ _RTHP.SERIES-COUNT @ 0= IF EXIT THEN
    RTE-FAMILY-SERIES _RSHSP-FAMILY!
    _RSHSP-P @ _RTHP.SERIES-PLAN _RSHSP-PLAN @ RTE-SERIES-PLAN-SIZE MOVE
    \ The records are copied, as the instruments are, so a bank's sample
    \ offsets can become addresses in its samples.
    _RSHSP-SRC-SERIES @ _RSHSP-P @ _RTHP.SERIES-COUNT @ RTE-SERIES-SIZE *
        DUP _RSHSP-PLAN @ _RTE-SRP.ITEMS-U !
        _RSHSP-COPY DUP _RSHSP-PLAN @ _RTE-SRP.ITEMS-A !
    _RSHSP-P @ _RTHP.SERIES-COUNT @ 0 ?DO
        DUP I RTE-SERIES-SIZE * + DUP _RTE-SERIES.SAMPLES-U @ IF
            _RSHSP-SRC-SAMPLE-BASE @ SWAP _RTE-SERIES.SAMPLES-A +!
        ELSE DROP THEN
    LOOP DROP
    _RSHSP-SRC-SAMPLES @ _RSHSP-SRC-SAMPLES-U @ _RSHSP-FAMILY-BYTES! ;
: _RSHSP-INSTRUMENTS ( -- )
    _RSHSP-P @ _RTHP.INSTRUMENT-COUNT @ 0= IF EXIT THEN
    RTE-FAMILY-INSTRUMENT _RSHSP-FAMILY!
    _RSHSP-P @ _RTHP.INSTRUMENT-PLAN _RSHSP-PLAN @ RTE-INSTRUMENT-PLAN-SIZE MOVE
    \ Family source spans are pairwise disjoint. Copy the normalized rows
    \ rather than borrowing the catalog's overlapping region subspan.
    _RSHSP-P @ _RTHP.INSTRUMENT-REGION-COUNT @ 96 *
        DUP _RSHSP-PLAN @ _RTE-IP.REGIONS-U !
    _RSHSP-CATALOG @ _RTE-RC.REGIONS-A @ 96 + SWAP
        _RSHSP-COPY _RSHSP-PLAN @ _RTE-IP.REGIONS-A !
    _RSHSP-SRC-INSTRUMENTS @
        _RSHSP-P @ _RTHP.INSTRUMENT-COUNT @ RTE-INSTRUMENT-SIZE *
        _RSHSP-COPY _RSHSP-OUT !
    _RSHSP-OUT @ _RSHSP-PLAN @ _RTE-IP.ITEMS-A !
    _RSHSP-P @ _RTHP.INSTRUMENT-COUNT @ 0 ?DO
        _RSHSP-OUT @ I RTE-INSTRUMENT-SIZE * + _RSHSP-ITEM !
        _RSHSP-ITEM @ _RTE-INSTRUMENT.UNIT-U @ IF
            _RSHSP-SRC-UNIT-BASE @ _RSHSP-ITEM @ _RTE-INSTRUMENT.UNIT-A +!
        THEN
        _RSHSP-SHELL-CONTROLS @ _RSHSP-PROMPT-N @ + _RSHSP-NOTICE-N @ +
            _RSHSP-ITEM @ _RTE-INSTRUMENT.ID +!
        _RSHSP-SRC-INSTRUMENT-CORR @ I RUIP-CORRELATION-SIZE * +
            RUIP-CORRELATION-ATTACHMENT@ _RSHSP-MEMBER@ _RSHSP-MEMBER !
        _RSHSP-ITEM @ _RTE-INSTRUMENT.REGION @ _RSHSP-REGION@ _RSHSP-REGION !
        _RSHSP-REGION @ _RTE-IR.FLAGS @ RTE-REGION-CLIPPED AND _RSHSP-CHECK
        _RSHSP-REGION @ _RTE-IR.Z @ -3 > _RSHSP-CHECK
        _RSHSP-REGION @ _RTE-IR.Z @ _RSHSP-CONTENT-Z @ < _RSHSP-CHECK
        _RSHSP-REGION @ _RTE-IR.CLIP-Y @ _RSHSP-MEMBER @ RSHMM.ROW @ >= _RSHSP-CHECK
        _RSHSP-REGION @ _RTE-IR.CLIP-X @ _RSHSP-MEMBER @ RSHMM.COL @ >= _RSHSP-CHECK
        _RSHSP-REGION @ _RTE-IR.CLIP-Y @ _RSHSP-REGION @ _RTE-IR.CLIP-ROWS @ +
            _RSHSP-MEMBER @ RSHMM.ROW @ _RSHSP-MEMBER @ RSHMM.HEIGHT @ + <= _RSHSP-CHECK
        _RSHSP-REGION @ _RTE-IR.CLIP-X @ _RSHSP-REGION @ _RTE-IR.CLIP-COLS @ +
            _RSHSP-MEMBER @ RSHMM.COL @ _RSHSP-MEMBER @ RSHMM.WIDTH @ + <= _RSHSP-CHECK
    LOOP
    _RSHSP-SRC-UNITS @ _RSHSP-SRC-UNITS-U @ _RSHSP-FAMILY-BYTES! ;
: _RSHSP-PANE-FAMILY ( -- )
    _RSHSP-RESULT @ RSHPL-RESULT.PANES @ 0= IF EXIT THEN
    RTE-FAMILY-PANE _RSHSP-FAMILY!
    _RSHSP-PANES @ _RTE-PANE.REGION @ _RSHSP-PLAN-REGION!
    _RSHSP-PANES @ _RSHSP-RESULT @ RSHPL-RESULT.PANES @ RTE-PANE-SIZE * _RSHSP-PLAN-ITEMS!
    _RSHSP-TEXT @ _RSHSP-RESULT @ RSHPL-RESULT.PANE-UTF8 @ _RSHSP-FAMILY-BYTES! ;

\ Existing menu claims remain a nonopaque prefix. Shell claims and the pane
\ exclusion rectangles appended after them are opaque, exact source geometry.
: _RSHSP-CLAIM-RECT ( index row col h w -- )
    _RSHSP-BYTES ! _RSHSP-COUNT ! _RSHSP-START ! _RSHSP-TEMP ! _RSHSP-J !
    _RSHSP-M @ SHM.OWNER-ID @ _RSHSP-P @ _RTHP.SOURCE-GEN @ 1
    _RSHSP-J @ _RSHSP-J @ 1+ 0
    _RSHSP-TEMP @ _RSHSP-START @ _RSHSP-TEMP @ _RSHSP-COUNT @ +
    _RSHSP-START @ _RSHSP-BYTES @ +
    _RSHSP-CLAIM-BANK @ _RSHSP-CLAIM-U @ + RUCL-ADMITTED-RECTANGLE!
        RUCL-S-OK = _RSHSP-CHECK
    RUCL-CLAIM-SIZE _RSHSP-CLAIM-U +! ;
\ The producer planned the residual runs of the whole surface for the draw
\ these planes hold, with the claims the shell's claim bank begins with, so
\ the shell's plans may take its runs where the shell's own claims and
\ regions leave them whole.  Its glyph banks are a reference of no runs
\ when they hold another draw's plan.
: _RSHSP-GLYPH-REFERENCE ( -- )
    _RSHSP-P @ _RTHP.GLYPH-ITEMS-A @
    _RSHSP-PDRAW @ DUP 0<> SWAP _RSHSP-P @ _RTHP.GLYPH-DRAW @ = AND
    _RSHSP-PCOLS @ _RSHSP-P @ _RTHP.COLS @ = AND
    _RSHSP-PROWS @ _RSHSP-P @ _RTHP.ROWS @ = AND
        IF _RSHSP-P @ _RTHP.GLYPH-COUNT @ ELSE 0 THEN
    _RSHSP-P @ _RTHP.GLYPH-REFS-A @ _RSHSP-P @ _RTHP.GLYPH-TEXT-A @
    _RSHSP-P @ _RTHP.GLYPH-TEXT-USED @
    _RSHSP-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@
    _RSHSP-GREF @ RGRP-REFERENCE! ;
\ The planner's claims of one KIND, the panes' chrome or the taskbar's bands.
: _RSHSP-PLANNER-CLAIMS ( kind -- )
    _RSHSP-RESULT @ RSHPL-RESULT.CLAIMS @ 0 ?DO
        _RSHSP-CLAIMS @ I RSHPL-CLAIM-SIZE * + _RSHSP-ITEM !
        _RSHSP-ITEM @ RSHPL-CLAIM.KIND @ OVER = IF
            I _RSHSP-ITEM @ RSHPL-CLAIM.ROW @ _RSHSP-ITEM @ RSHPL-CLAIM.COL @
            _RSHSP-ITEM @ RSHPL-CLAIM.HEIGHT @ _RSHSP-ITEM @ RSHPL-CLAIM.WIDTH @
                _RSHSP-CLAIM-RECT
        THEN
    LOOP DROP ;
\ The bank holds the producer's claims, then the taskbar's, the prompt's,
\ the notice's and the status field's, which every plan excludes; then the
\ panes' chrome, which an overlay pane lies over and the rest exclude; then
\ every pane's content, which the residue of the whole surface excludes.
: _RSHSP-GLYPH-WORK ( -- )
    _RSHSP-P @ _RTHP.CLAIMS-USED @
    _RSHSP-RESULT @ RSHPL-RESULT.CLAIMS @ _RSHSP-N @ _RSHSP-ADD _RSHSP-PROMPT-N @ _RSHSP-ADD
        _RSHSP-NOTICE-N @ _RSHSP-ADD _RSHSP-STATUS-N @ _RSHSP-ADD RUCL-CLAIM-SIZE _RSHSP-MUL
        _RSHSP-ADD DUP _RSHSP-BYTES ! _RSHSP-TAKE _RSHSP-CLAIM-BANK !
    _RSHSP-P @ _RTHP.CLAIMS-A @ _RSHSP-CLAIM-BANK @ _RSHSP-P @ _RTHP.CLAIMS-USED @ MOVE
    _RSHSP-P @ _RTHP.CLAIMS-USED @ _RSHSP-CLAIM-U !
    RSHPL-CLAIM-TASKBAR _RSHSP-PLANNER-CLAIMS
    _RSHSP-PROMPT-N @ IF
        _RSHSP-N @ _RSHSP-P @ _RTHP.ROWS @ 1- 0 1 _RSHSP-P @ _RTHP.COLS @ _RSHSP-CLAIM-RECT
    THEN
    _RSHSP-NOTICE-N @ IF
        _RSHSP-N @ 1+ _RSHSP-NR @ _RSHSP-NC @ _RSHSP-NH @ _RSHSP-NW @ _RSHSP-CLAIM-RECT
    THEN
    _RSHSP-STATUS-N @ IF
        _RSHSP-N @ 2 + _RSHSP-SR @ _RSHSP-SC @ 1 _RSHSP-SW @ _RSHSP-CLAIM-RECT
    THEN
    _RSHSP-CLAIM-U @ _RSHSP-OVERLAY-CLAIM-U !
    RSHPL-CLAIM-PANE _RSHSP-PLANNER-CLAIMS
    _RSHSP-CLAIM-U @ _RSHSP-BASE-CLAIM-U !
    _RSHSP-N @ 0 ?DO I _RSHSP-ENTRY DUP SHME.KIND @ SHM-K-PANE = IF
        I SWAP _RSHSP-CONTENT-RECT _RSHSP-CLAIM-RECT ELSE DROP THEN LOOP
    _RSHSP-P @ _RTHP.ROWS @ 1+ 8 _RSHSP-MUL _RSHSP-TAKE _RSHSP-HEADS !
    _RSHSP-CLAIM-U @ RUCL-CLAIM-SIZE / 2 _RSHSP-MUL RGRP-EVENT-SIZE _RSHSP-MUL
        DUP _RSHSP-EVENTS-U ! _RSHSP-TAKE _RSHSP-EVENTS !
    _RSHSP-P @ _RTHP.COLS @ 1+ 16 _RSHSP-MUL _RSHSP-TAKE _RSHSP-DIFF !
    RGRP-REQUEST-SIZE _RSHSP-TAKE _RSHSP-GQ !
    RGRP-REFERENCE-SIZE _RSHSP-TAKE _RSHSP-GREF !
    _RSHSP-GLYPH-REFERENCE ;

: _RSHSP-GLYPH-SCAN-RECT ( -- )
    _RSHSP-REGION @ _RTE-IR.FLAGS @ RTE-REGION-CLIPPED AND IF
        _RSHSP-REGION @ _RTE-IR.CLIP-X @ _RSHSP-GX0 !
        _RSHSP-REGION @ _RTE-IR.CLIP-COLS @ _RSHSP-GW !
        _RSHSP-REGION @ _RTE-IR.CLIP-Y @ DUP _RSHSP-GY0 !
        _RSHSP-REGION @ _RTE-IR.CLIP-ROWS @ + _RSHSP-GY1 !
    ELSE
        _RSHSP-REGION @ _RTE-IR.X @ 0 MAX _RSHSP-GX0 !
        _RSHSP-REGION @ _RTE-IR.X @ _RSHSP-REGION @ _RTE-IR.COLS @ +
            _RSHSP-P @ _RTHP.COLS @ MIN _RSHSP-GX0 @ - 0 MAX _RSHSP-GW !
        _RSHSP-REGION @ _RTE-IR.Y @ 0 MAX _RSHSP-GY0 !
        _RSHSP-REGION @ _RTE-IR.Y @ _RSHSP-REGION @ _RTE-IR.ROWS @ +
            _RSHSP-P @ _RTHP.ROWS @ MIN _RSHSP-GY0 @ MAX _RSHSP-GY1 !
    THEN ;

\ Plan the clip GCX GCY GCW GCH under flags GCF, appending after the GCOUNT
\ runs and GUSED text bytes already assembled for the region.
: _RSHSP-GLYPH-PLAN ( -- )
    _RSHSP-GQ @ RGRP-REQUEST-CLEAR
    _RSHSP-P @ _RTHP.OWNER @ _RSHSP-P @ _RTHP.OWNER-GEN @
    _RSHSP-REGION @ _RTE-IR.ID @ _RSHSP-GBASE @ _RSHSP-GCOUNT @ _RSHSP-ADD
        _RSHSP-GQ @ RGRP-REQUEST-IDENTITY!
    _RSHSP-P @ _RTHP.COLS @ _RSHSP-P @ _RTHP.ROWS @
    _RSHSP-REGION @ _RTE-IR.X @ _RSHSP-REGION @ _RTE-IR.Y @
    _RSHSP-REGION @ _RTE-IR.COLS @ _RSHSP-REGION @ _RTE-IR.ROWS @
    _RSHSP-GCX @ _RSHSP-GCY @ _RSHSP-GCW @ _RSHSP-GCH @
    _RSHSP-REGION @ _RTE-IR.Z @ _RSHSP-GCF @
    0 _RSHSP-GQ @ RGRP-REQUEST-REGION!
    _RSHSP-P @ _RTHP.LIMITS RTE-LIMITS-GLYPH-RUN-BYTES@ _RSHSP-GQ @ RGRP-REQUEST-LIMIT!
    _RSHSP-CLAIM-BANK @ _RSHSP-CLAIM-U @ _RSHSP-GQ @ RGRP-REQUEST-CLAIMS!
    _RSHSP-HEADS @ _RSHSP-P @ _RTHP.ROWS @ 1+ 8 *
    _RSHSP-EVENTS @ _RSHSP-EVENTS-U @
    _RSHSP-DIFF @ _RSHSP-P @ _RTHP.COLS @ 1+ 16 *
    _RSHSP-GQ @ RGRP-REQUEST-WORK!
    _RSHSP-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE
    _RSHSP-GITEMS @ _RSHSP-GCOUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * +
        _RSHSP-GSLOTS @ _RSHSP-GCOUNT @ - RTE-GLYPH-RUN-PLAN-ITEM-SIZE *
    _RSHSP-GREFS @ _RSHSP-GCOUNT @ 16 * +
        _RSHSP-GSLOTS @ _RSHSP-GCOUNT @ - 16 *
    _RSHSP-GTEXT @ _RSHSP-GUSED @ + _RSHSP-GLIMIT @ _RSHSP-GUSED @ -
    _RSHSP-GQ @ RGRP-REQUEST-OUTPUT!
    \ MENU-CLAIMS already counts records; CLAIMS-USED is the byte extent.
    _RSHSP-PBACK @ _RSHSP-PRESIDUE @ _RSHSP-PCOLS @ _RSHSP-PROWS @
    _RSHSP-P @ _RTHP.MENU-CLAIMS @ _RSHSP-GREF @
    _RSHSP-GQ @ _RGRP-BUILD-PAIRED-WITH-REFERENCE RGRP-S-OK = _RSHSP-CHECK
    DROP 2DROP
    \ The planner's text offsets start at its own output; rebase them.
    OVER 0 ?DO
        _RSHSP-GUSED @ _RSHSP-GREFS @ _RSHSP-GCOUNT @ I + 16 * + +!
    LOOP
    _RSHSP-GUSED +! _RSHSP-GCOUNT +! ;

\ Row reuse for a DELTA. The producer's ROW-DAMAGE names the rows whose
\ glyphs its candidate rebuilt; every other row keeps the acknowledged
\ frame's cells, residue, menus and claims, and a DELTA keeps the shell's
\ own claims and regions. The shell's runs on such a row therefore equal
\ the acknowledged part's. Runs never span rows, so copying those rows and
\ planning only the changed bands builds the same runs as planning the
\ whole region.
: _RSHSP-GLYPH-ACTIVE? ( -- flag )
    0 _RSHSP-GA-N ! 0 _RSHSP-GA-I !
    _RSHSP-REUSE @ 0= IF 0 EXIT THEN
    _RSHSP-P @ _RTHP.ROW-DAMAGE-A @ 0= IF 0 EXIT THEN
    _RSHSP-P @ _RTHP.ROW-DAMAGE-U @ _RSHSP-P @ _RTHP.ROWS @ U< IF 0 EXIT THEN
    _RSHSP-REGION @ _RTE-IR.ID @ _RSHSP-DBATCH @ _RTE-FB.CATALOG-A @
        RTE-REGION-CATALOG-FIND ?DUP 0= IF 0 EXIT THEN
    96 _RSHSP-REGION @ 96 COMPARE IF 0 EXIT THEN
    _RSHSP-DBATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        _RSHSP-DBATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * +
        DUP _RTE-FE.KIND @ RTE-FAMILY-GLYPH =
        OVER _RTE-FE.PLAN-A @ _RTE-LP.REGION-ID @ _RSHSP-REGION @ _RTE-IR.ID @ = AND IF
            DUP _RTE-FE.REFS-A @ _RSHSP-GA-REFS !
            DUP _RTE-FE.BYTES-A @ _RSHSP-GA-TEXT !
            DUP _RTE-FE.BYTES-U @ _RSHSP-GA-TEXT-U !
            RTE-FAMILY-ITEMS@ RTE-GLYPH-RUN-PLAN-ITEM-SIZE / SWAP _RSHSP-GA-ITEMS !
            \ Visible runs come first, in row order; tombstones follow.
            0 ?DO
                _RSHSP-GA-ITEMS @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RTE-LPI.VISIBLE @
                0= IF LEAVE THEN 1 _RSHSP-GA-N +!
            LOOP -1 UNLOOP EXIT
        THEN DROP
    LOOP -1 ;
: _RSHSP-GLYPH-COPY ( index -- )
    DUP RTE-GLYPH-RUN-PLAN-ITEM-SIZE * _RSHSP-GA-ITEMS @ + _RSHSP-GA-ITEM !
    16 * _RSHSP-GA-REFS @ + _RSHSP-GA-REF !
    _RSHSP-GCOUNT @ _RSHSP-GSLOTS @ U< 0= IF RTE-S-CAPACITY THROW THEN
    _RSHSP-GA-REF @ 8 + @ _RSHSP-GA-ITEM @ _RTE-LPI.TEXT-CAPACITY @ = _RSHSP-CHECK
    _RSHSP-GA-REF @ @ _RSHSP-GA-REF @ 8 + @ _RSHSP-ADD
        _RSHSP-GA-TEXT-U @ U> 0= _RSHSP-CHECK
    _RSHSP-GUSED @ _RSHSP-GA-REF @ 8 + @ _RSHSP-ADD
        _RSHSP-GLIMIT @ U> IF RTE-S-CAPACITY THROW THEN
    _RSHSP-GITEMS @ _RSHSP-GCOUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RSHSP-NEW !
    _RSHSP-GA-ITEM @ _RSHSP-NEW @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOVE
    _RSHSP-GBASE @ _RSHSP-GCOUNT @ _RSHSP-ADD _RSHSP-NEW @ _RTE-LPI.OBJECT !
    _RSHSP-GA-TEXT @ _RSHSP-GA-REF @ @ +
        _RSHSP-GTEXT @ _RSHSP-GUSED @ + _RSHSP-GA-REF @ 8 + @ MOVE
    _RSHSP-GREFS @ _RSHSP-GCOUNT @ 16 * + _RSHSP-NEW !
    _RSHSP-GUSED @ _RSHSP-NEW @ ! _RSHSP-GA-REF @ 8 + @ _RSHSP-NEW @ 8 + !
    _RSHSP-GA-REF @ 8 + @ _RSHSP-GUSED +! 1 _RSHSP-GCOUNT +! ;
: _RSHSP-GLYPH-ROW@ ( index -- row )
    RTE-GLYPH-RUN-PLAN-ITEM-SIZE * _RSHSP-GA-ITEMS @ + _RTE-LPI.ROW @
    _RSHSP-REGION @ _RTE-IR.Y @ + ;
: _RSHSP-GLYPH-ROW-COPY ( -- )
    BEGIN _RSHSP-GA-I @ _RSHSP-GA-N @ U<
        IF _RSHSP-GA-I @ _RSHSP-GLYPH-ROW@ _RSHSP-GR @ < ELSE 0 THEN
    WHILE 1 _RSHSP-GA-I +! REPEAT
    BEGIN _RSHSP-GA-I @ _RSHSP-GA-N @ U<
        IF _RSHSP-GA-I @ _RSHSP-GLYPH-ROW@ _RSHSP-GR @ = ELSE 0 THEN
    WHILE _RSHSP-GA-I @ _RSHSP-GLYPH-COPY 1 _RSHSP-GA-I +! REPEAT ;
: _RSHSP-ROW-DAMAGED? ( -- flag ) _RSHSP-P @ _RTHP.ROW-DAMAGE-A @ _RSHSP-GR @ + C@ 0<> ;
: _RSHSP-GLYPH-ROWS ( -- )
    _RSHSP-GX0 @ _RSHSP-GCX ! _RSHSP-GW @ _RSHSP-GCW !
    _RSHSP-REGION @ _RTE-IR.FLAGS @ RTE-REGION-CLIPPED OR _RSHSP-GCF !
    _RSHSP-GY0 @ _RSHSP-GR !
    BEGIN _RSHSP-GR @ _RSHSP-GY1 @ < WHILE
        _RSHSP-ROW-DAMAGED? IF
            _RSHSP-GR @ _RSHSP-GCY !
            BEGIN _RSHSP-GR @ _RSHSP-GY1 @ < IF _RSHSP-ROW-DAMAGED? ELSE 0 THEN
            WHILE 1 _RSHSP-GR +! REPEAT
            _RSHSP-GR @ _RSHSP-GCY @ - _RSHSP-GCH ! _RSHSP-GLYPH-PLAN
        ELSE _RSHSP-GLYPH-ROW-COPY 1 _RSHSP-GR +! THEN
    REPEAT ;
\ The slots a reused region's runs can take: the acknowledged visible runs
\ its unchanged rows copy, and on each changed row one for every scanned
\ cell, the most the planner makes there. The acknowledged runs of changed
\ rows are counted too, as slack. The count never exceeds one slot a cell,
\ the reservation of a region planned whole, so the build runs out of room
\ exactly where it did with that reservation.
: _RSHSP-GLYPH-SLOTS ( -- slots )
    _RSHSP-GA-N @
    _RSHSP-GY0 @ _RSHSP-GR !
    BEGIN _RSHSP-GR @ _RSHSP-GY1 @ < WHILE
        _RSHSP-ROW-DAMAGED? IF _RSHSP-GW @ + THEN
        1 _RSHSP-GR +!
    REPEAT
    _RSHSP-GCELLS @ MIN ;
: _RSHSP-GLYPH-HEADER ( -- )
    _RSHSP-PLAN @ RTE-GLYPH-RUN-PLAN-SIZE 0 FILL
    _RSHSP-P @ _RTHP.OWNER @ _RSHSP-PLAN @ _RTE-LP.OWNER !
    _RSHSP-P @ _RTHP.OWNER-GEN @ _RSHSP-PLAN @ _RTE-LP.GENERATION !
    _RSHSP-P @ _RTHP.COLS @ _RSHSP-PLAN @ _RTE-LP.SURFACE-COLS !
    _RSHSP-P @ _RTHP.ROWS @ _RSHSP-PLAN @ _RTE-LP.SURFACE-ROWS !
    _RSHSP-REGION @ _RTE-IR.ID @ _RSHSP-PLAN @ _RTE-LP.REGION-ID !
    _RSHSP-REGION @ _RTE-IR.X @ _RSHSP-PLAN @ _RTE-LP.REGION-X !
    _RSHSP-REGION @ _RTE-IR.Y @ _RSHSP-PLAN @ _RTE-LP.REGION-Y !
    _RSHSP-REGION @ _RTE-IR.COLS @ _RSHSP-PLAN @ _RTE-LP.REGION-COLS !
    _RSHSP-REGION @ _RTE-IR.ROWS @ _RSHSP-PLAN @ _RTE-LP.REGION-ROWS !
    _RSHSP-REGION @ _RTE-IR.CLIP-X @ _RSHSP-PLAN @ _RTE-LP.CLIP-X !
    _RSHSP-REGION @ _RTE-IR.CLIP-Y @ _RSHSP-PLAN @ _RTE-LP.CLIP-Y !
    _RSHSP-REGION @ _RTE-IR.CLIP-COLS @ _RSHSP-PLAN @ _RTE-LP.CLIP-COLS !
    _RSHSP-REGION @ _RTE-IR.CLIP-ROWS @ _RSHSP-PLAN @ _RTE-LP.CLIP-ROWS !
    _RSHSP-REGION @ _RTE-IR.Z @ _RSHSP-PLAN @ _RTE-LP.REGION-Z !
    _RSHSP-REGION @ _RTE-IR.FLAGS @ _RSHSP-PLAN @ _RTE-LP.REGION-FLAGS !
    _RSHSP-GITEMS @ _RSHSP-PLAN @ _RTE-LP.ITEMS-A !
    _RSHSP-GCOUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * _RSHSP-PLAN @ _RTE-LP.ITEMS-U ! ;
\ Shadow check of row reuse (frame-shadow.f).  A region whose unchanged rows
\ were copied from the acknowledged part is also planned whole, as a START
\ plans it, into a scratch block.  The counts, runs, text and references
\ must be the same, as items 4R to 4R+3 for region R.  The reused result is
\ then the one the region keeps, as it is with the check off.
VARIABLE _RSHSP-SG-A
VARIABLE _RSHSP-SG-U
VARIABLE _RSHSP-SG-HEAD
VARIABLE _RSHSP-SG-ITEMS
VARIABLE _RSHSP-SG-TEXT
VARIABLE _RSHSP-SG-REFS
VARIABLE _RSHSP-SG-SLOTS
VARIABLE _RSHSP-SG-COUNT
VARIABLE _RSHSP-SG-USED
VARIABLE _RSHSP-SG-CX
VARIABLE _RSHSP-SG-CY
VARIABLE _RSHSP-SG-CW
VARIABLE _RSHSP-SG-CH
VARIABLE _RSHSP-SG-CF
VARIABLE _RSHSP-SG-ITEM

: _RSHSP-SG-KEEP  ( -- )
    _RSHSP-GITEMS @ _RSHSP-SG-ITEMS ! _RSHSP-GTEXT @ _RSHSP-SG-TEXT !
    _RSHSP-GREFS @ _RSHSP-SG-REFS ! _RSHSP-GSLOTS @ _RSHSP-SG-SLOTS !
    _RSHSP-GCOUNT @ _RSHSP-SG-COUNT ! _RSHSP-GUSED @ _RSHSP-SG-USED !
    _RSHSP-GCX @ _RSHSP-SG-CX ! _RSHSP-GCY @ _RSHSP-SG-CY !
    _RSHSP-GCW @ _RSHSP-SG-CW ! _RSHSP-GCH @ _RSHSP-SG-CH !
    _RSHSP-GCF @ _RSHSP-SG-CF ! ;

: _RSHSP-SG-PUT-BACK  ( -- )
    _RSHSP-SG-ITEMS @ _RSHSP-GITEMS ! _RSHSP-SG-TEXT @ _RSHSP-GTEXT !
    _RSHSP-SG-REFS @ _RSHSP-GREFS ! _RSHSP-SG-SLOTS @ _RSHSP-GSLOTS !
    _RSHSP-SG-COUNT @ _RSHSP-GCOUNT ! _RSHSP-SG-USED @ _RSHSP-GUSED !
    _RSHSP-SG-CX @ _RSHSP-GCX ! _RSHSP-SG-CY @ _RSHSP-GCY !
    _RSHSP-SG-CW @ _RSHSP-GCW ! _RSHSP-SG-CH @ _RSHSP-GCH !
    _RSHSP-SG-CF @ _RSHSP-GCF ! ;

\ Plan the whole region into the scratch block, as the region's START
\ would; a refusal counts as a plan of no length, which differs.
: _RSHSP-SG-PLAN  ( -- )
    _RSHSP-GCELLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE *
    _RSHSP-GCELLS @ 16 * + _RSHSP-GLIMIT @ 7 + -8 AND + 4 CELLS +
        _RSHSP-SG-A _RSHSP-SG-U FSHD-GROW
    DUP 0= IF DROP FSHD-SKIP EXIT THEN
    DUP _RSHSP-SG-HEAD ! 4 CELLS +
    DUP _RSHSP-GITEMS ! _RSHSP-GCELLS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * +
    DUP _RSHSP-GREFS ! _RSHSP-GCELLS @ 16 * +
    _RSHSP-GTEXT !
    _RSHSP-GCELLS @ _RSHSP-GSLOTS !
    0 _RSHSP-GCOUNT ! 0 _RSHSP-GUSED !
    _RSHSP-REGION @ _RTE-IR.CLIP-X @ _RSHSP-GCX !
    _RSHSP-REGION @ _RTE-IR.CLIP-Y @ _RSHSP-GCY !
    _RSHSP-REGION @ _RTE-IR.CLIP-COLS @ _RSHSP-GCW !
    _RSHSP-REGION @ _RTE-IR.CLIP-ROWS @ _RSHSP-GCH !
    _RSHSP-REGION @ _RTE-IR.FLAGS @ _RSHSP-GCF !
    _RSHSP-SG-COUNT @ _RSHSP-SG-HEAD @ !
    _RSHSP-SG-USED @ _RSHSP-SG-HEAD @ CELL+ !
    ['] _RSHSP-GLYPH-PLAN CATCH IF
        -1 -1
    ELSE
        _RSHSP-GCOUNT @ _RSHSP-GUSED @
    THEN
    _RSHSP-SG-HEAD @ 3 CELLS + ! _RSHSP-SG-HEAD @ 2 CELLS + !
    _RSHSP-REGION @ _RTE-IR.ID @ 4 * _RSHSP-SG-ITEM !
    _RSHSP-SG-HEAD @ 2 CELLS _RSHSP-SG-HEAD @ 2 CELLS + 2 CELLS
        _RSHSP-SG-ITEM @ FSHD-STAGE-SHELL-GLYPHS FSHD-SAME? 0= IF EXIT THEN
    _RSHSP-SG-ITEMS @ _RSHSP-SG-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE *
    _RSHSP-GITEMS @ _RSHSP-SG-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE *
        _RSHSP-SG-ITEM @ 1+ FSHD-STAGE-SHELL-GLYPHS FSHD-SAME? DROP
    _RSHSP-SG-TEXT @ _RSHSP-SG-USED @ _RSHSP-GTEXT @ _RSHSP-SG-USED @
        _RSHSP-SG-ITEM @ 2 + FSHD-STAGE-SHELL-GLYPHS FSHD-SAME? DROP
    _RSHSP-SG-REFS @ _RSHSP-SG-COUNT @ 16 * _RSHSP-GREFS @ _RSHSP-SG-COUNT @ 16 *
        _RSHSP-SG-ITEM @ 3 + FSHD-STAGE-SHELL-GLYPHS FSHD-SAME? DROP ;

: _RSHSP-SH-GLYPH  ( -- )
    _RSHSP-P @ _RTHP.SOURCE-DRAW @ FSHD-DRAW !
    _RSHSP-SG-KEEP
    _RSHSP-SG-PLAN
    _RSHSP-SG-PUT-BACK ;

: _RSHSP-GLYPH ( region -- )
    _RSHSP-REGION !
    RTE-FAMILY-GLYPH _RSHSP-FAMILY!
    _RSHSP-CURSOR @ _RSHSP-SAVED !
    _RSHSP-REGION @ _RTE-IR.FLAGS @ RTE-REGION-CLIPPED AND IF
        _RSHSP-REGION @ _RTE-IR.CLIP-COLS @ _RSHSP-REGION @ _RTE-IR.CLIP-ROWS @
    ELSE _RSHSP-P @ _RTHP.COLS @ _RSHSP-P @ _RTHP.ROWS @ THEN
        _RSHSP-MUL DUP _RSHSP-GCELLS ! _RSHSP-GSLOTS !
    \ A region planned whole can take a slot for every cell; a reused one
    \ takes what its rows can. Text keeps its limit of four bytes a cell in
    \ both: a character of several scalars can take more, so a changed row's
    \ text has no smaller bound.
    _RSHSP-GLYPH-ACTIVE? DUP IF
        _RSHSP-GLYPH-SCAN-RECT _RSHSP-GLYPH-SLOTS _RSHSP-GSLOTS !
    THEN
    _RSHSP-GSLOTS @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-GITEMS !
    _RSHSP-GCELLS @ 4 _RSHSP-MUL
        _RSHSP-P @ _RTHP.GLYPH-TEXT-U @ MIN _RSHSP-GLIMIT !
    _RSHSP-GLIMIT @ _RSHSP-TAKE _RSHSP-GTEXT !
    _RSHSP-GSLOTS @ 16 _RSHSP-MUL _RSHSP-TAKE _RSHSP-GREFS !
    0 _RSHSP-GCOUNT ! 0 _RSHSP-GUSED ! _RSHSP-NEXT-ID @ _RSHSP-GBASE !
    IF
        _RSHSP-GLYPH-ROWS
        FSHD? IF _RSHSP-SH-GLYPH THEN
    ELSE
        _RSHSP-REGION @ _RTE-IR.CLIP-X @ _RSHSP-GCX !
        _RSHSP-REGION @ _RTE-IR.CLIP-Y @ _RSHSP-GCY !
        _RSHSP-REGION @ _RTE-IR.CLIP-COLS @ _RSHSP-GCW !
        _RSHSP-REGION @ _RTE-IR.CLIP-ROWS @ _RSHSP-GCH !
        _RSHSP-REGION @ _RTE-IR.FLAGS @ _RSHSP-GCF !
        _RSHSP-GLYPH-PLAN
    THEN
    _RSHSP-GCOUNT @ 0= IF
        -1 _RSHSP-FAMILY-N +! _RSHSP-SAVED @ RTE-GLYPH-RUN-PLAN-SIZE - _RSHSP-CURSOR ! EXIT
    THEN
    _RSHSP-GBASE @ _RSHSP-GCOUNT @ _RSHSP-ADD _RSHSP-NEXT-ID !
    _RSHSP-GLYPH-HEADER
    \ Compact the reserved slots in place, items, text, then references,
    \ the order the batch lists a family's spans in, so the admission's
    \ pairwise span check takes one pass. MOVE is overlap-safe; every
    \ destination is at or before its corresponding source, and the text
    \ ends before the references' source begins.
    _RSHSP-GITEMS @ _RSHSP-GCOUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RSHSP-NEW !
    _RSHSP-GTEXT @ _RSHSP-NEW @ _RSHSP-GUSED @ MOVE
    _RSHSP-NEW @ _RSHSP-GUSED @ _RSHSP-FAMILY-BYTES!
    _RSHSP-NEW @ _RSHSP-GUSED @ _RSHSP-ALIGN + _RSHSP-NEW !
    _RSHSP-GREFS @ _RSHSP-NEW @ _RSHSP-GCOUNT @ 16 * MOVE
    _RSHSP-NEW @ _RSHSP-FAMILY @ _RTE-FE.REFS-A !
    _RSHSP-GCOUNT @ 16 * _RSHSP-FAMILY @ _RTE-FE.REFS-U !
    _RSHSP-NEW @ _RSHSP-GCOUNT @ 16 * + _RSHSP-CURSOR ! ;
: _RSHSP-GLYPHS-BODY ( -- )
    _RSHSP-GLYPH-WORK
    _RSHSP-P @ _RTHP.REGION @ _RSHSP-REGION@ _RSHSP-GLYPH
    _RSHSP-GCOUNT @ 0= IF
        _RSHSP-CATALOG @ _RTE-RC.REGIONS-A @ DUP 96 + SWAP
            _RSHSP-CATALOG @ _RTE-RC.REGIONS-U @ 96 - MOVE
        -96 _RSHSP-CATALOG @ _RTE-RC.REGIONS-U +!
    THEN
    \ An ordinary pane's content leaves out the overlay panes above it,
    \ whose own content regions hold those cells, chrome beneath included.
    _RSHSP-BASE-CLAIM-U @ _RSHSP-CLAIM-U !
    _RSHSP-N @ 0 ?DO I _RSHSP-ENTRY DUP _RSHSP-OVERLAY-PANE? IF
        I SWAP _RSHSP-CONTENT-RECT _RSHSP-CLAIM-RECT ELSE DROP THEN LOOP
    _RSHSP-CLAIM-U @ _RSHSP-UNDER-CLAIM-U !
    _RSHSP-MAP-U @ RSHMM-ENTRY-SIZE / 0 ?DO
        _RSHSP-MAP @ I RSHMM-ENTRY-SIZE * +
        DUP RSHMM.SOURCE-INDEX @ _RSHSP-ENTRY _RSHSP-OVERLAY-PANE? IF
            _RSHSP-OVERLAY-CLAIM-U ELSE _RSHSP-UNDER-CLAIM-U THEN @ _RSHSP-CLAIM-U !
        RSHMM.CONTENT-REGION @ _RSHSP-REGION@ _RSHSP-GLYPH
    LOOP ;
\ Every planner request, claim, work and output span lies in the work arena,
\ so one proof that the arena is disjoint from screen storage covers every
\ planner call made under this one borrow of the projection planes.
: _RSHSP-GLYPHS-IN-PLANES ( back-a residue-a cols rows draw-generation residue-dirty? -- )
    DROP _RSHSP-PDRAW ! _RSHSP-PROWS ! _RSHSP-PCOLS ! _RSHSP-PRESIDUE ! _RSHSP-PBACK !
    _RSHSP-S @ _RSHSP.WORK @ _RSHSP-S @ _RSHSP.WORK-U @ SCR-STORAGE-DISJOINT?
    IF ['] _RSHSP-GLYPHS-BODY CATCH ELSE RTE-S-UNAVAILABLE THEN
    0 _RSHSP-PBACK ! 0 _RSHSP-PRESIDUE ! 0 _RSHSP-PDRAW ! 0 _RSHSP-GREF !
    ?DUP IF THROW THEN ;
: _RSHSP-GLYPHS ( -- ) ['] _RSHSP-GLYPHS-IN-PLANES SCR-WITH-PROJECTION-PLANES ;

VARIABLE _RSHSP-PART-USED VARIABLE _RSHSP-CLONE-U
VARIABLE _RSHSP-NEXT-REGION VARIABLE _RSHSP-NEXT-OBJECT
VARIABLE _RSHSP-META-U VARIABLE _RSHSP-PACK-A VARIABLE _RSHSP-PACK-U
VARIABLE _RSHSP-V-T VARIABLE _RSHSP-V-B VARIABLE _RSHSP-V-CAP
VARIABLE _RSHSP-V-U VARIABLE _RSHSP-V-BATCH VARIABLE _RSHSP-V-CAT
VARIABLE _RSHSP-V-ENTRY VARIABLE _RSHSP-V-PLAN
VARIABLE _RSHSP-V-NEXT VARIABLE _RSHSP-V-OBJECT VARIABLE _RSHSP-V-STRIDE
: _RSHSP-IN-PART? ( a u -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    OVER _RSHSP-V-B @ DUP RSHSP-PART.BATCH @ + U< IF 2DROP 0 EXIT THEN
    + _RSHSP-V-B @ _RSHSP-V-U @ + U> 0= ;
: _RSHSP-OFFSET-SPAN? ( offset bytes -- flag )
    DUP 0= IF DROP 0= EXIT THEN
    OVER RSHSP-PART-HEADER-SIZE U< IF 2DROP 0 EXIT THEN
    OVER _RSHSP-V-U @ U> IF 2DROP 0 EXIT THEN
    _RSHSP-V-U @ ROT - U> 0= ;
: _RSHSP-PART-GRAPH? ( -- flag )
    _RSHSP-V-B @ RSHSP-PART.BATCH @ DUP 7 AND IF DROP 0 EXIT THEN
    DUP RTE-FAMILY-BATCH-SIZE _RSHSP-OFFSET-SPAN? 0= IF DROP 0 EXIT THEN
    _RSHSP-V-B @ + _RSHSP-V-BATCH !
    _RSHSP-V-BATCH @ _RTE-FB.CATALOG-U @ RTE-REGION-CATALOG-SIZE <> IF 0 EXIT THEN
    _RSHSP-V-BATCH @ _RTE-FB.CATALOG-A @ DUP RTE-REGION-CATALOG-SIZE
        _RSHSP-IN-PART? 0= IF DROP 0 EXIT THEN _RSHSP-V-CAT !
    _RSHSP-V-CAT @ DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @
        _RSHSP-IN-PART? 0= IF 0 EXIT THEN
    _RSHSP-V-BATCH @ DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @
        _RSHSP-IN-PART? 0= IF 0 EXIT THEN
    _RSHSP-V-BATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE MOD IF 0 EXIT THEN
    _RSHSP-V-BATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        _RSHSP-V-BATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * + _RSHSP-V-ENTRY !
        _RSHSP-V-ENTRY @ _RTE-FE.KIND @ RTE-FAMILY-PLAN-SIZE DUP 0= IF DROP 0 UNLOOP EXIT THEN
        _RSHSP-V-ENTRY @ _RTE-FE.PLAN-U @ <> IF 0 UNLOOP EXIT THEN
        _RSHSP-V-ENTRY @ DUP _RTE-FE.PLAN-A @ SWAP _RTE-FE.PLAN-U @
            _RSHSP-IN-PART? 0= IF 0 UNLOOP EXIT THEN
        _RSHSP-V-ENTRY @ RTE-FAMILY-ITEMS@ _RSHSP-IN-PART? 0= IF 0 UNLOOP EXIT THEN
        _RSHSP-V-ENTRY @ DUP _RTE-FE.BYTES-A @ SWAP _RTE-FE.BYTES-U @
            _RSHSP-IN-PART? 0= IF 0 UNLOOP EXIT THEN
        _RSHSP-V-ENTRY @ DUP _RTE-FE.REFS-A @ SWAP _RTE-FE.REFS-U @
            _RSHSP-IN-PART? 0= IF 0 UNLOOP EXIT THEN
        _RSHSP-V-ENTRY @ RTE-FAMILY-REGIONS@ _RSHSP-IN-PART? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _RSHSP-V-BATCH @ RTE-FAMILY-BATCH-VALID? ;
: _RSHSP-PART-FRONTIERS? ( -- flag )
    _RSHSP-V-CAT @ _RTE-RC.REGIONS-U @ 96 U< IF 0 EXIT THEN
    _RSHSP-V-CAT @ DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @ + 96 - _RTE-IR.ID @
        1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RSHSP-V-B @ RSHSP-PART.NEXT-REGION @ <> IF 0 EXIT THEN
    0 _RSHSP-V-OBJECT !
    _RSHSP-V-BATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        _RSHSP-V-BATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * + _RSHSP-V-ENTRY !
        _RSHSP-V-ENTRY @ _RTE-FE.KIND @ RTE-FAMILY-SERIES <> IF
            _RSHSP-V-ENTRY @ _RTE-FE.KIND @ RTE-FAMILY-ITEM-SIZE _RSHSP-V-STRIDE !
            _RSHSP-V-ENTRY @ RTE-FAMILY-ITEMS@ _RSHSP-V-STRIDE @ / 0 ?DO
                DUP I _RSHSP-V-STRIDE @ * +
                _RSHSP-V-ENTRY @ _RTE-FE.KIND @ RTE-FAMILY-GLYPH <> IF 16 + THEN
                @ DUP _RTHP-U32? 0= IF DROP DROP 0 UNLOOP UNLOOP EXIT THEN
                _RSHSP-V-OBJECT @ MAX _RSHSP-V-OBJECT !
            LOOP DROP
        THEN
    LOOP
    _RSHSP-V-OBJECT @ 1 _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RSHSP-V-B @ RSHSP-PART.NEXT-OBJECT @ = ;

\ BANK, one of the screen producer's target banks, names a whole part of the
\ shell's: one at the start of an extension block, its spans in order and
\ inside it, its model and batch whole, and its catalog, batch and
\ frontiers those of the frame the bank records.
: _RSHSP-PART-VALID? ( bank -- flag )
    DUP _RSHSP-V-T ! _RTHP-XBLOCK@ _RSHSP-V-U ! _RSHSP-V-B !
    _RSHSP-V-B @ _RSHSP-P @ _RTHP-XBLOCK-CAPACITY
        DUP RSHSP-PART-HEADER-SIZE U< IF DROP 0 EXIT THEN _RSHSP-V-CAP !
    _RSHSP-V-U @ DUP RSHSP-PART-HEADER-SIZE U< SWAP _RSHSP-V-CAP @ U> OR IF 0 EXIT THEN
    _RSHSP-V-U @ DUP 7 AND SWAP _RTHP-U32? 0= OR IF 0 EXIT THEN
    _RSHSP-V-T @ _RTHP-TB.DRAW @ 0=
    _RSHSP-V-T @ _RTHP-TB.OWNER @ 0= OR
    _RSHSP-V-T @ _RTHP-TB.GENERATION @ 0= OR IF 0 EXIT THEN
    RSHSP-PART-HEADER-SIZE _RSHSP-V-NEXT !
    72 8 DO
        _RSHSP-V-B @ I + DUP @ SWAP 8 + @
        2DUP _RSHSP-OFFSET-SPAN? 0= IF 2DROP 0 UNLOOP EXIT THEN
        DUP IF
            SWAP _RSHSP-V-NEXT @ <> IF DROP 0 UNLOOP EXIT THEN
            7 + -8 AND _RSHSP-V-NEXT +!
        ELSE 2DROP THEN
    16 +LOOP
    _RSHSP-V-B @ RSHSP-PART.BATCH @ _RSHSP-V-NEXT @ <> IF 0 EXIT THEN
    _RSHSP-V-B @ RSHSP-PART.CORRELATIONS-U @ RSHPL-CORRELATION-SIZE MOD
    _RSHSP-V-B @ RSHSP-PART.MEMBERSHIP-U @ RSHMM-ENTRY-SIZE MOD OR IF 0 EXIT THEN
    _RSHSP-V-B @ RSHSP-PART.MODEL @ _RSHSP-V-B @ +
    _RSHSP-V-B @ RSHSP-PART.MODEL-U @ SHSN-FROZEN-VALIDATE SHSN-S-OK <> IF 0 EXIT THEN
    _RSHSP-PART-GRAPH? 0= IF 0 EXIT THEN
    _RSHSP-V-B @ DUP RSHSP-PART.MODEL @ + SHM.PROMPT-U @ 0<>
        _RSHSP-V-B @ RSHSP-PART.PROMPT @ 0<> <> IF 0 EXIT THEN
    _RSHSP-V-B @ DUP RSHSP-PART.MODEL @ +
    DUP SHM.WIDTH @ _RSHSP-V-CAT @ _RTE-RC.SURFACE-COLS @ <>
    SWAP SHM.HEIGHT @ _RSHSP-V-CAT @ _RTE-RC.SURFACE-ROWS @ <> OR IF 0 EXIT THEN
    _RSHSP-V-BATCH @ _RSHFC-MEASURE-PROVED RSHFC-S-OK <> IF DROP 0 EXIT THEN
        _RSHSP-V-NEXT @ + _RSHSP-V-U @ <> IF 0 EXIT THEN
    _RSHSP-PART-FRONTIERS? 0= IF 0 EXIT THEN
    _RSHSP-V-CAT @ _RTE-RC.OWNER @ _RSHSP-V-T @ _RTHP-TB.OWNER @ <>
    _RSHSP-V-CAT @ _RTE-RC.GENERATION @ _RSHSP-V-T @ _RTHP-TB.GENERATION @ <> OR
    _RSHSP-V-BATCH @ _RTE-FB.SURFACE-GENERATION @ _RSHSP-V-T @ _RTHP-TB.DRAW @ <> OR 0= ;

: _RSHSP-PACK ( source bytes offset-field -- )
    >R _RSHSP-PACK-U ! _RSHSP-PACK-A !
    _RSHSP-PACK-U @ R@ 8 + !
    _RSHSP-PACK-U @ IF
        _RSHSP-PART-USED @ R@ !
        _RSHSP-PACK-A @ _RSHSP-PART @ _RSHSP-PART-USED @ + _RSHSP-PACK-U @ MOVE
        _RSHSP-PACK-U @ _RSHSP-ALIGN _RSHSP-PART-USED +!
    ELSE 0 R@ ! THEN R> DROP ;
\ Freezing is the only write to a part.  The finished part is a proved copy
\ of the batch the preflight admitted and of the model the shell snapshot
\ validated, so it is checked once more only with every-frame checks on.
\ STAGE freezes into the extension block the frame on screen does not name,
\ after the pending bank dropped its part, so a part a bank names is never
\ written again, and later uses compare its identities only.
\ The batch's graph was checked by the preflight that admitted it, at the
\ end of BUILD-BATCH, and nothing since has changed what that check reads.
\ A START freezes right after it.  A DELTA's identity mapping rewrites
\ identities, which the graph check reads only as a pane's, nonzero before
\ and after; and it gives a glyph family new item and reference arrays,
\ fresh from the work space and so apart from every other span, holding the
\ admitted runs in order and then canonical tombstones with no text, whose
\ references continue the family's text at its end.  So the measure and the
\ copy take the batch as proved; the measure still checks every span.
\ The pending bank then names the part, which makes it the frame's.
: _RSHSP-FREEZE ( -- )
    _RSHSP-BATCH @ _RSHFC-MEASURE-PROVED RSHFC-S-OK = _RSHSP-CHECK _RSHSP-CLONE-U !
    RSHSP-PART-HEADER-SIZE _RSHSP-MU @ _RSHSP-ALIGN _RSHSP-ADD
    _RSHSP-RESULT @ RSHPL-RESULT.CORRELATIONS @ RSHPL-CORRELATION-SIZE _RSHSP-MUL _RSHSP-ADD
    _RSHSP-RESULT @ RSHPL-RESULT.ACTION-BYTES @ _RSHSP-ALIGN _RSHSP-ADD
    _RSHSP-MAP-U @ _RSHSP-ALIGN _RSHSP-ADD DUP _RSHSP-META-U !
    _RSHSP-CLONE-U @ _RSHSP-ADD DUP _RSHSP-S @ _RSHSP.PART-BYTES !
    DUP _RSHSP-PART-CAP @ U> IF DROP RTE-S-CAPACITY THROW THEN
    \ The batch, in the work space, and the extension block are both from
    \ Desk's memory source, so only every-frame checks prove them apart again.
    CHK-EVERY-FRAME? IF
        _RSHSP-BATCH @ _RSHSP-PART @ _RSHSP-PART-CAP @ _RSHFC-BATCH-OUTSIDE?
            _RSHSP-PARTS-DAMAGED CHK-NAME _RSHSP-CHECK
    THEN
    _RSHSP-PART @ SWAP 0 FILL
    RSHSP-PART-HEADER-SIZE _RSHSP-PART-USED !
    _RSHSP-M @ _RSHSP-MU @ _RSHSP-PART @ RSHSP-PART.MODEL _RSHSP-PACK
    _RSHSP-CORR @ _RSHSP-RESULT @ RSHPL-RESULT.CORRELATIONS @ RSHPL-CORRELATION-SIZE *
        _RSHSP-PART @ RSHSP-PART.CORRELATIONS _RSHSP-PACK
    _RSHSP-ACTIONS @ _RSHSP-RESULT @ RSHPL-RESULT.ACTION-BYTES @
        _RSHSP-PART @ RSHSP-PART.ACTIONS _RSHSP-PACK
    _RSHSP-MAP @ _RSHSP-MAP-U @ _RSHSP-PART @ RSHSP-PART.MEMBERSHIP _RSHSP-PACK
    _RSHSP-PART-USED @ _RSHSP-PART @ RSHSP-PART.BATCH !
    _RSHSP-BATCH @ _RSHSP-PART @ _RSHSP-PART-USED @ +
        _RSHSP-PART-CAP @ _RSHSP-PART-USED @ - _RSHFC-COPY-PROVED
        RSHFC-S-OK = _RSHSP-CHECK _RSHSP-PART-USED +!
    _RSHSP-NEXT-REGION @ _RSHSP-PART @ RSHSP-PART.NEXT-REGION !
    _RSHSP-NEXT-OBJECT @ _RSHSP-PART @ RSHSP-PART.NEXT-OBJECT !
    _RSHSP-PROMPT-ID @ _RSHSP-PART @ RSHSP-PART.PROMPT !
    _RSHSP-PART @ _RSHSP-PART-USED @ _RSHSP-P @ _RTHP-XBLOCK!
    CHK-EVERY-FRAME? IF
        _RSHSP-P @ _RTHP.TARGET-PENDING @ _RSHSP-PART-VALID?
            _RSHSP-PARTS-DAMAGED CHK-NAME _RSHSP-CHECK
    THEN ;
\ Diagnostics: complete preparations refused, and the last refusal's status
\ and where it happened (_RSHSP-PSTAGE: 1 target, 2 snapshot,
\ 3 model bounds, 4 geometry, 5 model proof, 6 catalog, 7 families, 8 glyph
\ runs, 9 preflight).
VARIABLE _RSHSP-DIAG-PREPARE-REFUSALS VARIABLE _RSHSP-DIAG-PREPARE-STATUS
VARIABLE _RSHSP-DIAG-PREPARE-STAGE VARIABLE _RSHSP-PSTAGE
: _RSHSP-BUILD-BATCH ( -- )
    1 _RSHSP-PSTAGE !
    _RSHSP-P @ _RTHP.TARGET-PENDING @ _RSHSP-CHECK
    0 _RSHSP-S @ _RSHSP.WORK-USED ! 0 _RSHSP-S @ _RSHSP.PART-BYTES !
    _RSHSP-S @ _RSHSP.WORK @ _RSHSP-CURSOR !
    _RSHSP-S @ _RSHSP.WORK @ _RSHSP-S @ _RSHSP.WORK-U @ + _RSHSP-END !
    2 _RSHSP-PSTAGE !
    _RSHSP-P @ _RTHP.SOURCE-DRAW @ _RSHSP-S @ _RSHSP.SOURCE @ SHSN-SNAPSHOT-FOR@
        SHSN-S-OK = _RSHSP-CHECK _RSHSP-MU ! _RSHSP-M !
    3 _RSHSP-PSTAGE !
    _RSHSP-M @ SHM.COUNT @ _RSHSP-N !
    4 _RSHSP-PSTAGE !
    _RSHSP-M @ SHM.WIDTH @ _RSHSP-P @ _RTHP.COLS @ = _RSHSP-CHECK
    _RSHSP-M @ SHM.HEIGHT @ _RSHSP-P @ _RTHP.ROWS @ = _RSHSP-CHECK
    _RSHSP-M @ _RSHSP-MU @ _RSHSP-COPY _RSHSP-M !
    \ The shell snapshot validated these bytes when it published them, so
    \ the copy is validated again only with every-frame checks on; the band
    \ helpers, the planner and the membership builder below skip it either
    \ way.  Nothing writes it afterwards.
    5 _RSHSP-PSTAGE !
    CHK-EVERY-FRAME? IF
        _RSHSP-M @ _RSHSP-MU @ SHSN-FROZEN-VALIDATE SHSN-S-OK =
            _RSHSP-MODEL-DAMAGED CHK-NAME _RSHSP-CHECK
    THEN
    6 _RSHSP-PSTAGE !
    _RSHSP-ALLOCATE-PLAN _RSHSP-CATALOG!
    7 _RSHSP-PSTAGE !
    _RSHSP-APP-CONTROLS _RSHSP-SERIES _RSHSP-INSTRUMENTS _RSHSP-STATICS
    _RSHSP-STATUS-STATIC _RSHSP-PANE-FAMILY
    8 _RSHSP-PSTAGE !
    _RSHSP-GLYPHS
    9 _RSHSP-PSTAGE !
    1 _RSHSP-BATCH @ _RTE-FB.ABI !
    _RSHSP-CATALOG @ _RSHSP-BATCH @ _RTE-FB.CATALOG-A !
    RTE-REGION-CATALOG-SIZE _RSHSP-BATCH @ _RTE-FB.CATALOG-U !
    _RSHSP-FAMILIES @ _RSHSP-BATCH @ _RTE-FB.FAMILIES-A !
    _RSHSP-FAMILY-N @ RTE-FAMILY-ENTRY-SIZE * _RSHSP-BATCH @ _RTE-FB.FAMILIES-U !
    _RSHSP-P @ _RTHP.ATTEMPT @ _RSHSP-BATCH @ _RTE-FB.ATTEMPT !
    _RSHSP-P @ _RTHP.SOURCE-GEN @ _RSHSP-BATCH @ _RTE-FB.SOURCE-GENERATION !
    _RSHSP-P @ _RTHP.SOURCE-DRAW @ _RSHSP-BATCH @ _RTE-FB.SURFACE-GENERATION !
    _RSHSP-BATCH @ _RSHSP-ADMISSION @ _RSHSP-S @ _RSHSP.SHELL @
        RTE-FAMILY-BATCH-PREFLIGHT DUP IF THROW ELSE DROP THEN ;
\ A complete START candidate defines every region and object with the
\ fresh identities its admission reserved.
: _RSHSP-BUILD ( -- )
    0 _RSHSP-REUSE ! _RSHSP-SOURCE-CANDIDATE _RSHSP-BUILD-BATCH
    _RSHSP-ADMISSION @ _RTE-FA.LAST-REGION @ 1 _RSHSP-ADD _RSHSP-NEXT-REGION !
    _RSHSP-ADMISSION @ _RTE-FA.OBJECT-LAST @ 1 _RSHSP-ADD _RSHSP-NEXT-OBJECT !
    _RSHSP-FREEZE ;

\ Full caller capacities are protected, including the screen producer's
\ extension blocks, which the shell freezes into.  Guards precede every
\ constructor store and are repeated before a new preparation.
CREATE _RSHSP-SPANS 64 ALLOT
VARIABLE _RSHSP-LIVE-PROOF
VARIABLE _RSHSP-IA VARIABLE _RSHSP-IU VARIABLE _RSHSP-ISOURCE VARIABLE _RSHSP-ISHELL
VARIABLE _RSHSP-IWORK VARIABLE _RSHSP-IWORKU
: _RSHSP-6DROP ( x x x x x x -- ) 2DROP 2DROP 2DROP ;
: _RSHSP-SPAN! ( a u i -- ) 16 * _RSHSP-SPANS + >R R@ 8 + ! R> ! ;
: _RSHSP-SPAN@ ( i -- a u ) 16 * _RSHSP-SPANS + DUP @ SWAP 8 + @ ;
\ RUHA's storage proof: a RUHA span lies apart from all four sidecar spans.
: _RSHSP-APART? ( a u -- flag )
    4 0 DO
        2DUP I _RSHSP-SPAN@ MSPAN-OVERLAP? IF 2DROP 0 UNLOOP EXIT THEN
    LOOP 2DROP -1 ;
: _RSHSP-EXTERNAL? ( a u -- flag )
    _RSHSP-IU ! _RSHSP-IA !
    _RSHSP-IA @ _RSHSP-IU @ _RSHSP-P @ RTHP-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSHSP-IA @ _RSHSP-IU @ _RSHSP-P @ DUP _RTHP.ARENA-A @ SWAP _RTHP.ARENA-U @
        MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSHSP-IA @ _RSHSP-IU @ _RSHSP-ISHELL @ RTE-SHELL-FACADE-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _RSHSP-IA @ _RSHSP-IU @ _RSHSP-P @ _RTHP.FACADE @ RTE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    \ The live predicate covers the source's banks, the screen, UIDL and the
    \ shell's live owners (shell-snapshot.md).
    _RSHSP-LIVE-PROOF @ IF
        _RSHSP-IA @ _RSHSP-IU @ _RSHSP-ISOURCE @ SHSN-LIVE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    ELSE
        _RSHSP-IA @ _RSHSP-IU @ _RSHSP-ISOURCE @ SHSN-SOURCE-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    THEN -1 ;
\ The screen producer's extension blocks as spans 2 and 3: each none, while
\ the producer has not grown it, or a span of its own.
: _RSHSP-XBLOCK-SPANS? ( -- flag )
    _RSHSP-P @ DUP _RTHP.XBLOCK0-A @ SWAP _RTHP.XBLOCK0-U @
        DUP IF 2DUP _RSHSP-SPAN? 0= IF 2DROP 0 EXIT THEN THEN 2 _RSHSP-SPAN!
    _RSHSP-P @ DUP _RTHP.XBLOCK1-A @ SWAP _RTHP.XBLOCK1-U @
        DUP IF 2DUP _RSHSP-SPAN? 0= IF 2DROP 0 EXIT THEN THEN 3 _RSHSP-SPAN!
    -1 ;
\ The caller has checked each span that holds bytes with _RSHSP-SPAN? just
\ before.  RUHA's storage is proved apart from all of them in one proof,
\ which builds RUHA's span set once rather than once per sidecar span.
: _RSHSP-SPANS? ( -- flag )
    4 0 DO
        I _RSHSP-SPAN@ DUP IF
            _RSHSP-EXTERNAL? 0= IF 0 UNLOOP EXIT THEN
            I 0 ?DO I _RSHSP-SPAN@ _RSHSP-IA @ _RSHSP-IU @ MSPAN-OVERLAP? IF
                0 UNLOOP UNLOOP EXIT THEN LOOP
        ELSE 2DROP THEN
    LOOP
    _RSHSP-P @ _RTHP.ADAPTER @ ['] _RSHSP-APART? _RUHA-SAFE-PROVE? ;
: _RSHSP-HEADER? ( sidecar -- flag )
    DUP RSHSP-SIZE _RSHSP-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RSHSP.MAGIC @ _RSHSP-MAGIC <>
    OVER _RSHSP.SIZE @ RSHSP-SIZE <> OR
    OVER _RSHSP.SELF @ 2 PICK <> OR IF DROP 0 EXIT THEN
    DUP _RSHSP.PRODUCER @ RTHP-SIZE _RSHSP-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RSHSP.SOURCE @ SHSN-SIZE _RSHSP-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RSHSP.SHELL @ RTE-SHELL-FACADE-SIZE _RSHSP-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _RSHSP.MEMORY @ ?DUP IF MSRC-VALID? 0= IF DROP 0 EXIT THEN THEN
    DUP _RSHSP.WORK @ OVER _RSHSP.WORK-U @ _RSHSP-SPAN? 0= IF DROP 0 EXIT THEN
    DROP -1 ;
\ The sidecar, and the producer, source and shell it names, for one
\ dispatch.
: _RSHSP-BIND ( sidecar -- )
    DUP _RSHSP-S !
    DUP _RSHSP.PRODUCER @ _RSHSP-P !
    DUP _RSHSP.SOURCE @ _RSHSP-ISOURCE !
    _RSHSP.SHELL @ _RSHSP-ISHELL ! ;
\ Whether SIDECAR, and the producer it names, are the records they say they
\ are: on a cell, with their own magic, size and address.
: _RSHSP-NAMED? ( sidecar -- flag )
    DUP 0= OVER 7 AND OR IF DROP 0 EXIT THEN
    DUP _RSHSP.MAGIC @ _RSHSP-MAGIC <>
    OVER _RSHSP.SIZE @ RSHSP-SIZE <> OR
    OVER _RSHSP.SELF @ 2 PICK <> OR IF DROP 0 EXIT THEN
    _RSHSP.PRODUCER @
    DUP 0= OVER 7 AND OR IF DROP 0 EXIT THEN
    DUP _RTHP.MAGIC @ _RTHP-MAGIC <>
    OVER _RTHP.SIZE @ RTHP-SIZE <> OR
    OVER _RTHP.SELF @ 2 PICK <> OR IF DROP 0 EXIT THEN
    DROP -1 ;
\ The caller has checked the header before its first store.  The header
\ proves the sidecar, producer, source, shell and work spans with
\ _RSHSP-SPAN?, a pure function of each span, so they are not checked again.
: _RSHSP-AUTHORITY? ( sidecar -- flag )
    _RSHSP-BIND
    _RSHSP-P @ DUP _RTHP.MAGIC @ _RTHP-MAGIC <>
    OVER _RTHP.SIZE @ RTHP-SIZE <> OR
    OVER _RTHP.SELF @ 2 PICK <> OR IF DROP 0 EXIT THEN DROP
    _RSHSP-P @ DUP _RTHP.ARENA-A @ SWAP _RTHP.ARENA-U @ _RSHSP-SPAN? 0= IF 0 EXIT THEN
    _RSHSP-P @ _RTHP.FACADE @ RTE-VALID? 0= IF 0 EXIT THEN
    _RSHSP-P @ _RTHP.ADAPTER @ RUHA-VALID? 0= IF 0 EXIT THEN
    _RSHSP-ISOURCE @ SHSN-VALID? 0= IF 0 EXIT THEN
    _RSHSP-ISHELL @ RTE-SHELL-VALID? 0= IF 0 EXIT THEN
    _RSHSP-ISHELL @ _RTE-SH.BASE @ _RSHSP-P @ _RTHP.FACADE @ <> IF 0 EXIT THEN
    _RSHSP-S @ RSHSP-SIZE 0 _RSHSP-SPAN!
    _RSHSP-S @ DUP _RSHSP.WORK @ SWAP _RSHSP.WORK-U @ 1 _RSHSP-SPAN!
    _RSHSP-XBLOCK-SPANS? 0= IF 0 EXIT THEN
    _RSHSP-SPANS? ;
: RSHSP-VALID? ( sidecar -- flag )
    DUP _RSHSP-HEADER? 0= IF DROP 0 EXIT THEN
    0 _RSHSP-LIVE-PROOF ! _RSHSP-AUTHORITY? ;

\ The screen producer's bank of the frame on screen, and the shell's part
\ of the frame a bank names, or 0.
: _RSHSP-ACTIVE-BANK ( -- bank|0 ) _RSHSP-P @ _RTHP.TARGET-ACTIVE @ ;
: _RSHSP-PART-OF ( bank|0 -- part|0 ) DUP IF _RTHP-TB.XBLOCK @ THEN ;
: _RSHSP-ACTIVE-PART ( -- part|0 ) _RSHSP-ACTIVE-BANK _RSHSP-PART-OF ;
: _RSHSP-PENDING-PART ( -- part|0 ) _RSHSP-P @ _RTHP.TARGET-PENDING @ _RSHSP-PART-OF ;
: _RSHSP-FRONTIERS! ( part -- )
    \ Hidden acknowledged objects have consumed their IDs even when a newer
    \ draw supersedes them before reveal. Base projection may reserve more
    \ IDs than the shell projection, so neither frontier may move backwards.
    DUP RSHSP-PART.NEXT-REGION @
    _RSHSP-P @ _RTHP.NEXT-REGION @ MAX _RSHSP-P @ _RTHP.NEXT-REGION !
    RSHSP-PART.NEXT-OBJECT @
    _RSHSP-P @ _RTHP.NEXT-OBJECT @ MAX _RSHSP-P @ _RTHP.NEXT-OBJECT ! ;
\ START-ACK advances the producer's frontiers from the ones the part records,
\ so it first checks them against the part's regions and objects again.
: _RSHSP-PART-FRONTIERS-OF? ( part -- flag )
    DUP _RSHSP-V-B ! DUP RSHSP-PART.BATCH @ + DUP _RSHSP-V-BATCH !
    _RTE-FB.CATALOG-A @ _RSHSP-V-CAT ! _RSHSP-PART-FRONTIERS? ;
: _RSHSP-START-ACK ( -- status )
    _RSHSP-PENDING-PART ?DUP IF
        DUP _RSHSP-PART-FRONTIERS-OF? 0= IF DROP RTE-S-INVALID EXIT THEN
        _RSHSP-FRONTIERS!
    THEN
    RTE-S-OK ;
\ The screen producer has made the pending bank the frame on screen, with
\ the part it names.
: _RSHSP-PUBLISH ( -- )
    _RSHSP-ACTIVE-PART ?DUP IF _RSHSP-FRONTIERS! THEN ;
\ The shell's part of the frame on screen still shows the shell: the
\ frame's draw is the screen's last and its owner the producer's, and the
\ part's model is the shell's snapshot for that draw.  A frame with no part
\ of the shell's is current as far as the shell can tell.
: _RSHSP-CURRENT? ( -- flag )
    _RSHSP-ACTIVE-BANK DUP _RSHSP-PART-OF DUP 0= IF 2DROP -1 EXIT THEN _RSHSP-PART !
    DUP _RTHP-TB.DRAW @ SCR-DRAW-GENERATION@ <>
    OVER _RTHP-TB.OWNER @ _RSHSP-P @ _RTHP.OWNER @ <> OR
    OVER _RTHP-TB.GENERATION @ _RSHSP-P @ _RTHP.OWNER-GEN @ <> OR IF DROP 0 EXIT THEN
    _RTHP-TB.DRAW @ _RSHSP-S @ _RSHSP.SOURCE @ SHSN-SNAPSHOT-FOR@
        SHSN-S-OK <> IF 2DROP 0 EXIT THEN
    _RSHSP-PART @ RSHSP-PART.MODEL @ _RSHSP-PART @ +
    _RSHSP-PART @ RSHSP-PART.MODEL-U @ COMPARE 0= ;
\ ---------------------------------------------------------------------
\  Storage that follows the candidate
\ ---------------------------------------------------------------------
\ A build that ran out of work space, or of room in the extension block it
\ freezes into, takes a larger block from the memory source and runs again:
\ what it needed and half again.  Neither block holds anything another step
\ reads: the work space is rebuilt by every candidate, and STAGE freezes
\ only into the extension block no bank names.  The screen producer grows
\ its extension blocks.  A new work space must be separate from the
\ shell's and the screen producer's storage; every dispatch proves the rest
\ again.  A refusal leaves the shell's part CELL, and the screen producer's
\ fallback record keeps the bytes asked for and held.
\ Diagnostics: blocks grown.
VARIABLE _RSHSP-DIAG-GROWTHS
VARIABLE _RSHSP-G-BYTES

\ ( need -- addr|0 ) a block for what the build needed and half again.
: _RSHSP-G-TAKE ( need -- addr|0 )
    DUP 1 RSHIFT + 7 + -8 AND DUP _RSHSP-G-BYTES !
    _RSHSP-S @ _RSHSP.MEMORY @ MSRC-ALLOC DUP IF EXIT THEN
    _RTHP-W-MEMORY-ASKED @ 0= IF
        _RSHSP-G-BYTES @ _RTHP-W-MEMORY-ASKED !
        _RSHSP-S @ _RSHSP.MEMORY @ MSRC-HELD@ _RTHP-W-MEMORY-HELD !
    THEN ;

: _RSHSP-G-FREE ( a u -- ) _RSHSP-S @ _RSHSP.MEMORY @ MSRC-FREE ;

: _RSHSP-G-SEPARATE? ( a u -- flag )
    2DUP _RSHSP-SPAN? 0= IF 2DROP 0 EXIT THEN
    2DUP _RSHSP-S @ RSHSP-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DUP _RSHSP-S @ DUP _RSHSP.WORK @ SWAP _RSHSP.WORK-U @ MSPAN-OVERLAP?
        IF 2DROP 0 EXIT THEN
    2DUP _RSHSP-P @ DUP _RTHP.XBLOCK0-A @ SWAP _RTHP.XBLOCK0-U @ MSPAN-OVERLAP?
        IF 2DROP 0 EXIT THEN
    2DUP _RSHSP-P @ DUP _RTHP.XBLOCK1-A @ SWAP _RTHP.XBLOCK1-U @ MSPAN-OVERLAP?
        IF 2DROP 0 EXIT THEN
    2DUP _RSHSP-P @ RTHP-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    _RSHSP-P @ DUP _RTHP.ARENA-A @ SWAP _RTHP.ARENA-U @ MSPAN-OVERLAP? 0= ;

: _RSHSP-WORK! ( addr -- )
    _RSHSP-S @ DUP _RSHSP.WORK @ SWAP _RSHSP.WORK-U @ _RSHSP-G-FREE
    _RSHSP-S @ _RSHSP.WORK ! _RSHSP-G-BYTES @ _RSHSP-S @ _RSHSP.WORK-U ! ;

\ After a build: a CAPACITY refusal whose storage grew is built again.
: _RSHSP-GROW ( status -- status' again? )
    DUP RTE-S-CAPACITY <> IF 0 EXIT THEN
    _RSHSP-S @ _RSHSP.WORK-USED @ _RSHSP-S @ _RSHSP.WORK-U @ U> IF
        _RSHSP-S @ _RSHSP.MEMORY @ 0= IF 0 EXIT THEN
        _RSHSP-S @ _RSHSP.WORK-USED @ _RSHSP-G-TAKE ?DUP 0= IF 0 EXIT THEN
        DUP _RSHSP-G-BYTES @ _RSHSP-G-SEPARATE? S" Desk's memory source" CHK-HANDOVER 0= IF
            _RSHSP-G-BYTES @ _RSHSP-G-FREE DROP RTE-S-INVALID 0 EXIT
        THEN
        _RSHSP-WORK!
    ELSE
        _RSHSP-S @ _RSHSP.PART-BYTES @ _RSHSP-PART-CAP @ U> 0= IF 0 EXIT THEN
        _RSHSP-S @ _RSHSP.PART-BYTES @ _RSHSP-P @ _RTHP-XBLOCK-GROW
        DUP RTE-S-OK <> IF NIP 0 EXIT THEN DROP
    THEN
    1 _RSHSP-DIAG-GROWTHS +! -1 ;

\ The pending bank drops any part it named, and BUILD-XT runs, again each
\ time a block it ran out of grew; it freezes the shell's part into the
\ extension block the frame on screen does not name, and the pending bank
\ names it.  A build that fails leaves the pending bank naming none.
: _RSHSP-STAGE ( build-xt -- status )
    >R
    _RSHSP-P @ _RTHP-XBLOCK-DROP
    BEGIN
        _RSHSP-P @ _RTHP-XBLOCK-FREE _RSHSP-PART-CAP ! _RSHSP-PART !
        R@ CATCH _RSHSP-GROW
    WHILE DROP REPEAT
    R> DROP
    DUP IF _RSHSP-P @ _RTHP-XBLOCK-DROP EXIT THEN DROP RTE-S-OK ;
: _RSHSP-PREPARE ( -- status )
    0 _RSHSP-PSTAGE !
    ['] _RSHSP-BUILD _RSHSP-STAGE
    DUP RTE-S-OK = IF EXIT THEN
    1 _RSHSP-DIAG-PREPARE-REFUSALS +! DUP _RSHSP-DIAG-PREPARE-STATUS !
    _RSHSP-PSTAGE @ _RSHSP-DIAG-PREPARE-STAGE ! ;

\ ---------------------------------------------------------------------
\  Shell DELTA
\ ---------------------------------------------------------------------
\ A changed draw whose shell layout matches the acknowledged part becomes a
\ retained DELTA instead of a complete START. The candidate is built as
\ usual, after the base producer has given its controls their acknowledged
\ identities. Every other item then takes the identity of the acknowledged
\ item in the same place: regions, the taskbar, panes, statics, instruments
\ and series by position, and residual glyph runs slot by slot within each
\ region. A region with fewer runs keeps its extra slots as invisible empty
\ runs; a region with more runs defines them with identities above every one
\ already used. Any other difference in shape leaves the draw to a START.

VARIABLE _RSHSP-DAE VARIABLE _RSHSP-DPE
VARIABLE _RSHSP-DNEXT VARIABLE _RSHSP-DN VARIABLE _RSHSP-DAN
VARIABLE _RSHSP-DPI VARIABLE _RSHSP-DAI VARIABLE _RSHSP-DP0 VARIABLE _RSHSP-DA0
VARIABLE _RSHSP-DTASK-P0 VARIABLE _RSHSP-DTASK-A0 VARIABLE _RSHSP-DTASK-N
VARIABLE _RSHSP-DPANE-P0 VARIABLE _RSHSP-DPANE-A0 VARIABLE _RSHSP-DPANE-N
VARIABLE _RSHSP-DSER-P0 VARIABLE _RSHSP-DSER-A0 VARIABLE _RSHSP-DSER-N
VARIABLE _RSHSP-DM-P0 VARIABLE _RSHSP-DM-A0 VARIABLE _RSHSP-DM-N
VARIABLE _RSHSP-DM-A VARIABLE _RSHSP-DM-B VARIABLE _RSHSP-DM-U
VARIABLE _RSHSP-DX-E VARIABLE _RSHSP-DX-MAX
\ Diagnostics: changed draws refused by the probe, preparations refused and
\ prepared, and where the last refusal happened: its stage (1 catalog,
\ 2 family shape, 3 controls, 4 statics/instruments/series/panes, 5 glyph
\ runs, 6 frontiers and freeze, 7 candidate build), family index and status.
VARIABLE _RSHSP-DIAG-PROBE-REFUSALS VARIABLE _RSHSP-DIAG-REFUSALS
VARIABLE _RSHSP-DIAG-PREPARED VARIABLE _RSHSP-DIAG-STAGE
VARIABLE _RSHSP-DIAG-FAMILY VARIABLE _RSHSP-DIAG-STATUS VARIABLE _RSHSP-DSTAGE
\ How many DELTA preparations each place refused, at DSTAGE * 16 plus the
\ build's PSTAGE in stage 7 or the family's kind in stages 2 to 5, and how
\ many probes each difference of the shell models refused (_RSHSP-DM-WHY).
CREATE _RSHSP-DIAG-DELTA-WHY 128 CELLS ALLOT
_RSHSP-DIAG-DELTA-WHY 128 CELLS 0 FILL
CREATE _RSHSP-DIAG-PROBE-WHY 16 CELLS ALLOT
_RSHSP-DIAG-PROBE-WHY 16 CELLS 0 FILL
VARIABLE _RSHSP-DM-WHY

\ The acknowledged part was checked in full when it was frozen.  With
\ every-frame checks on (check-mode.f) its structure is checked again before
\ a DELTA builds on it or a click is routed through it, since a bug may have
\ written it since.  Damage that keeps the structure breaks the seal of the
\ frame's bank, which covers the part: the screen producer checks that seal
\ before the comparison every DELTA starts with, and the shell before it
\ routes a click.  A damaged part names the shell's part of the frame; the
\ draw then goes out as a START, which reads nothing from it, and the click
\ goes nowhere.
: _RSHSP-ACTIVE-INTACT? ( -- flag )
    CHK-EVERY-FRAME? 0= IF -1 EXIT THEN
    _RSHSP-ACTIVE-BANK _RSHSP-PART-VALID? _RSHSP-PARTS-DAMAGED CHK-NAME ;
\ The acknowledged part a DELTA starts from: the frame on screen has one,
\ and that frame's wire owner is the producer's.
: _RSHSP-DELTA-BASE? ( -- flag )
    _RSHSP-ACTIVE-BANK DUP 0= IF EXIT THEN
    DUP _RTHP-TB.XBLOCK @ 0=
    OVER _RTHP-TB.OWNER @ _RSHSP-P @ _RTHP.OWNER @ <> OR
    SWAP _RTHP-TB.GENERATION @ _RSHSP-P @ _RTHP.OWNER-GEN @ <> OR 0= ;

\ Two shell models are equal apart from the epoch every paint advances and
\ the field of Desk's prompt, which typing changes: the prompt is in both
\ at the same place, or in neither.  A copy's capacity and used bytes end
\ where its prompt, or the notice after it, does.  The app shell's notice,
\ which follows the prompt, is the same in both, wherever the prompt's size
\ puts it.  Desk's status, which shows only with the taskbar and so never
\ with the prompt, ends both models at the same place or neither, and its
\ value, severity and place may change.
VARIABLE _RSHSP-DM-UA
: _RSHSP-DM-RANGE= ( start end -- flag )
    OVER - >R _RSHSP-DM-A @ OVER + R@ ROT _RSHSP-DM-B @ + R> COMPARE 0= ;
: _RSHSP-D-NOTICES= ( -- flag )
    _RSHSP-DM-A @ SHM.NOTICE-U @ ?DUP 0= IF -1 EXIT THEN
    _RSHSP-DM-A @ SHM.NOTICE-OFF @ OVER + _RSHSP-DM-UA @ U> IF DROP 0 EXIT THEN
    _RSHSP-DM-B @ SHM.NOTICE-OFF @ OVER + _RSHSP-DM-U @ U> IF DROP 0 EXIT THEN
    >R _RSHSP-DM-A @ DUP SHM.NOTICE-OFF @ + R@
    _RSHSP-DM-B @ DUP SHM.NOTICE-OFF @ + R> COMPARE 0= ;
: _RSHSP-D-MODELS= ( a1 u1 a2 u2 -- flag )
    _RSHSP-DM-U ! _RSHSP-DM-B ! _RSHSP-DM-UA ! _RSHSP-DM-A !
    1 _RSHSP-DM-WHY !
    _RSHSP-DM-UA @ SHM-HEADER-SIZE U< _RSHSP-DM-U @ SHM-HEADER-SIZE U< OR IF 0 EXIT THEN
    2 _RSHSP-DM-WHY !
    _RSHSP-DM-A @ SHM.PROMPT-OFF @ _RSHSP-DM-B @ SHM.PROMPT-OFF @ <> IF 0 EXIT THEN
    _RSHSP-DM-A @ SHM.PROMPT-OFF @ ?DUP IF
        3 _RSHSP-DM-WHY !
        DUP _RSHSP-DM-UA @ U> OVER _RSHSP-DM-U @ U> OR IF DROP 0 EXIT THEN
        0 0 SHM.CAPACITY _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.ENTRY-LIMIT 0 SHM.USED _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.OWNER-ID 0 SHM.EPOCH _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.WIDTH 0 SHM.PROMPT-U _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.NOTICE-U SHM-HEADER-SIZE _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        SHM-HEADER-SIZE SWAP _RSHSP-DM-RANGE= 0= IF 0 EXIT THEN
        4 _RSHSP-DM-WHY !
        _RSHSP-D-NOTICES= EXIT
    THEN
    5 _RSHSP-DM-WHY !
    _RSHSP-DM-A @ SHM.STATUS-OFF @ _RSHSP-DM-B @ SHM.STATUS-OFF @ <> IF 0 EXIT THEN
    _RSHSP-DM-A @ SHM.STATUS-OFF @ ?DUP IF
        6 _RSHSP-DM-WHY !
        DUP _RSHSP-DM-UA @ U> OVER _RSHSP-DM-U @ U> OR IF DROP 0 EXIT THEN
        0 0 SHM.CAPACITY _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.ENTRY-LIMIT 0 SHM.USED _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.OWNER-ID 0 SHM.EPOCH _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        0 SHM.WIDTH 0 SHM.STATUS-U _RSHSP-DM-RANGE= 0= IF DROP 0 EXIT THEN
        SHM-HEADER-SIZE SWAP _RSHSP-DM-RANGE= EXIT
    THEN
    7 _RSHSP-DM-WHY !
    _RSHSP-DM-UA @ _RSHSP-DM-U @ <> IF 0 EXIT THEN
    8 _RSHSP-DM-WHY !
    0 0 SHM.EPOCH _RSHSP-DM-RANGE= 0= IF 0 EXIT THEN
    9 _RSHSP-DM-WHY !
    0 SHM.WIDTH _RSHSP-DM-U @ _RSHSP-DM-RANGE= ;

\ Before a changed draw is built: only a draw whose shell model matches the
\ acknowledged one can become a DELTA.  This cheap check is advisory; the
\ preparation proves the complete shape.
: _RSHSP-PROBE-MODEL? ( -- flag )
    10 _RSHSP-DM-WHY !
    _RSHSP-ACTIVE-PART DUP 0= IF EXIT THEN
    DUP RSHSP-PART.MODEL @ OVER + SWAP RSHSP-PART.MODEL-U @
    SCR-DRAW-GENERATION@ _RSHSP-S @ _RSHSP.SOURCE @ SHSN-SNAPSHOT-FOR@
    12 _RSHSP-DM-WHY !
    SHSN-S-OK <> IF 2DROP 2DROP 0 EXIT THEN
    _RSHSP-D-MODELS= ;
: _RSHSP-DELTA-PROBE ( -- status )
    _RSHSP-PROBE-MODEL? IF RTE-S-OK EXIT THEN
    1 _RSHSP-DIAG-PROBE-REFUSALS +!
    _RSHSP-DM-WHY @ 15 MIN CELLS _RSHSP-DIAG-PROBE-WHY + 1 SWAP +!
    RTE-S-UNAVAILABLE ;

: _RSHSP-D-ID ( item -- a ) _RSHSP-KIND @ RTE-FAMILY-GLYPH <> IF 16 + THEN ;
\ An identity in [P0, P0+N) becomes the one in the same place from A0.
: _RSHSP-D-MAP ( id p0 a0 n -- id' )
    _RSHSP-DM-N ! _RSHSP-DM-A0 ! _RSHSP-DM-P0 !
    DUP _RSHSP-DM-P0 @ - DUP _RSHSP-DM-N @ U< IF NIP _RSHSP-DM-A0 @ + ELSE DROP THEN ;
\ The first of N consecutive identities held by ITEMS, or 0.
: _RSHSP-D-FIRST ( items n -- first|0 )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER _RSHSP-D-ID @ _RSHSP-TEMP !
    0 ?DO
        DUP I _RSHSP-STRIDE @ * + _RSHSP-D-ID @ _RSHSP-TEMP @ I + <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP DROP _RSHSP-TEMP @ ;
\ One more than the largest identity any non-series item of BATCH holds.
: _RSHSP-D-NEXT-OBJECT ( batch -- next )
    0 _RSHSP-DX-MAX !
    DUP _RTE-FB.FAMILIES-A @ SWAP _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        DUP I RTE-FAMILY-ENTRY-SIZE * + _RSHSP-DX-E !
        _RSHSP-DX-E @ _RTE-FE.KIND @ RTE-FAMILY-SERIES <> IF
            _RSHSP-DX-E @ RTE-FAMILY-ITEMS@
                _RSHSP-DX-E @ _RTE-FE.KIND @ RTE-FAMILY-ITEM-SIZE / 0 ?DO
                DUP I _RSHSP-DX-E @ _RTE-FE.KIND @ RTE-FAMILY-ITEM-SIZE * +
                _RSHSP-DX-E @ _RTE-FE.KIND @ RTE-FAMILY-GLYPH <> IF 16 + THEN @
                _RSHSP-DX-MAX @ MAX _RSHSP-DX-MAX !
            LOOP DROP
        THEN
    LOOP DROP _RSHSP-DX-MAX @ 1 _RSHSP-ADD ;

: _RSHSP-D-CATALOG ( -- )
    _RSHSP-CATALOG @ 32 _RSHSP-DBATCH @ _RTE-FB.CATALOG-A @ 32 COMPARE 0= _RSHSP-CHECK
    _RSHSP-CATALOG @ DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @
    _RSHSP-DBATCH @ _RTE-FB.CATALOG-A @ DUP _RTE-RC.REGIONS-A @ SWAP _RTE-RC.REGIONS-U @
    COMPARE 0= _RSHSP-CHECK ;

\ Applet controls already carry acknowledged identities. The taskbar takes
\ the acknowledged identities in place and must be otherwise unchanged,
\ since a DELTA cannot replace it.
: _RSHSP-D-CONTROLS ( -- )
    _RSHSP-DN @ _RSHSP-DAN @ = _RSHSP-CHECK
    _RSHSP-DN @ 0= IF EXIT THEN
    \ Desk's prompt takes its acknowledged identity; its field may change.
    _RSHSP-PROMPT-N @ IF
        _RSHSP-DPE @ _RTE-FE.PLAN-A @ _RTE-CP.REGION-ID @ _RSHSP-PROMPT-REGION @ = IF
            _RSHSP-DN @ 1 = _RSHSP-CHECK
            _RSHSP-DAI @ _RTE-CONTROL.KIND @ RTE-CONTROL-FIELD = _RSHSP-CHECK
            _RSHSP-DAI @ _RTE-CONTROL.ID @
                DUP _RSHSP-PROMPT-ID ! _RSHSP-DPI @ _RTE-CONTROL.ID !
            EXIT
        THEN
    THEN
    \ The notice takes its acknowledged identity and is unchanged, as the
    \ models are equal.
    _RSHSP-NOTICE-N @ IF
        _RSHSP-DPE @ _RTE-FE.PLAN-A @ _RTE-CP.REGION-ID @ _RSHSP-NOTICE-REGION @ = IF
            _RSHSP-DN @ 1 = _RSHSP-CHECK
            _RSHSP-DAI @ _RTE-CONTROL.KIND @ RTE-CONTROL-DIALOG = _RSHSP-CHECK
            _RSHSP-DAI @ _RTE-CONTROL.ID @
                DUP _RSHSP-NOTICE-ID ! _RSHSP-DPI @ _RTE-CONTROL.ID !
            _RSHSP-DPI @ _RSHSP-DAI @ RTE-FAMILY-CONTROL RTE-FAMILY-ITEM-SAME?
                _RSHSP-CHECK EXIT
        THEN
    THEN
    _RSHSP-DPI @ _RTE-CONTROL.KIND @ _RTE-CONTROL-TASKBAR-KIND? 0= IF
        _RSHSP-DN @ 0 ?DO
            _RSHSP-DPI @ I RTE-CONTROL-SIZE * + _RTE-CONTROL.ID @
            _RSHSP-DAI @ I RTE-CONTROL-SIZE * + _RTE-CONTROL.ID @ = _RSHSP-CHECK
        LOOP EXIT
    THEN
    _RSHSP-DPI @ _RSHSP-DN @ _RSHSP-D-FIRST DUP _RSHSP-CHECK _RSHSP-DTASK-P0 !
    _RSHSP-DAI @ _RSHSP-DN @ _RSHSP-D-FIRST DUP _RSHSP-CHECK _RSHSP-DTASK-A0 !
    _RSHSP-DN @ _RSHSP-DTASK-N !
    _RSHSP-DN @ 0 ?DO
        _RSHSP-DPI @ I RTE-CONTROL-SIZE * + _RSHSP-ITEM !
        _RSHSP-ITEM @ _RTE-CONTROL.KIND @ _RTE-CONTROL-TASKBAR-KIND? _RSHSP-CHECK
        _RSHSP-DTASK-A0 @ I + _RSHSP-ITEM @ _RTE-CONTROL.ID !
        _RSHSP-ITEM @ _RTE-CONTROL.PARENT @
            _RSHSP-DTASK-P0 @ _RSHSP-DTASK-A0 @ _RSHSP-DTASK-N @ _RSHSP-D-MAP
            _RSHSP-ITEM @ _RTE-CONTROL.PARENT !
        _RSHSP-ITEM @ _RSHSP-DAI @ I RTE-CONTROL-SIZE * + RTE-FAMILY-CONTROL
            RTE-FAMILY-ITEM-SAME? _RSHSP-CHECK
    LOOP ;

\ Statics, instruments, series and panes take the identity in place.
\ Instruments and series must be unchanged; a status field or pane may be
\ replaced.
: _RSHSP-D-PLACE ( -- )
    _RSHSP-DN @ _RSHSP-DAN @ = _RSHSP-CHECK
    _RSHSP-DN @ 0= IF EXIT THEN
    _RSHSP-DPI @ _RSHSP-DN @ _RSHSP-D-FIRST DUP _RSHSP-CHECK _RSHSP-DP0 !
    _RSHSP-DAI @ _RSHSP-DN @ _RSHSP-D-FIRST DUP _RSHSP-CHECK _RSHSP-DA0 !
    _RSHSP-KIND @ RTE-FAMILY-SERIES = IF
        _RSHSP-DP0 @ _RSHSP-DSER-P0 ! _RSHSP-DA0 @ _RSHSP-DSER-A0 !
        _RSHSP-DN @ _RSHSP-DSER-N !
    THEN
    _RSHSP-KIND @ RTE-FAMILY-PANE = IF
        _RSHSP-DP0 @ _RSHSP-DPANE-P0 ! _RSHSP-DA0 @ _RSHSP-DPANE-A0 !
        _RSHSP-DN @ _RSHSP-DPANE-N !
    THEN
    _RSHSP-DN @ 0 ?DO
        _RSHSP-DPI @ I _RSHSP-STRIDE @ * + _RSHSP-ITEM !
        _RSHSP-DA0 @ I + _RSHSP-ITEM @ _RSHSP-D-ID !
        _RSHSP-KIND @ RTE-FAMILY-INSTRUMENT = IF
            _RSHSP-ITEM @ _RTE-INSTRUMENT.SERIES-ID @
                _RSHSP-DSER-P0 @ _RSHSP-DSER-A0 @ _RSHSP-DSER-N @ _RSHSP-D-MAP
                _RSHSP-ITEM @ _RTE-INSTRUMENT.SERIES-ID !
        THEN
        _RSHSP-KIND @ DUP RTE-FAMILY-PANE <> SWAP RTE-FAMILY-STATIC <> AND IF
            _RSHSP-ITEM @ _RSHSP-DAI @ I _RSHSP-STRIDE @ * + _RSHSP-KIND @
                RTE-FAMILY-ITEM-SAME? _RSHSP-CHECK
        THEN
    LOOP ;

\ The canonical unused slot: one invisible cell with no text.
: _RSHSP-D-TOMBSTONE ( item -- )
    DUP RTE-GLYPH-RUN-PLAN-ITEM-SIZE 0 FILL
    1 OVER _RTE-LPI.HEIGHT ! 1 OVER _RTE-LPI.WIDTH !
    _RSHSP-PLAN @ _RTE-LP.REGION-ROWS @ OVER _RTE-LPI.ROOT-HEIGHT !
    _RSHSP-PLAN @ _RTE-LP.REGION-COLS @ SWAP _RTE-LPI.ROOT-WIDTH ! ;
: _RSHSP-D-GLYPHS ( -- )
    _RSHSP-DN @ _RSHSP-DAN @ MAX _RSHSP-COUNT !
    _RSHSP-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE _RSHSP-MUL _RSHSP-TAKE _RSHSP-NEW !
    _RSHSP-COUNT @ 16 _RSHSP-MUL _RSHSP-TAKE _RSHSP-OUT !
    _RSHSP-DPE @ _RTE-FE.PLAN-A @ _RSHSP-PLAN !
    _RSHSP-COUNT @ 0 ?DO
        _RSHSP-NEW @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RSHSP-ITEM !
        _RSHSP-OUT @ I 16 * + _RSHSP-TEMP !
        I _RSHSP-DN @ U< IF
            _RSHSP-DPI @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RSHSP-ITEM @
                RTE-GLYPH-RUN-PLAN-ITEM-SIZE MOVE
            _RSHSP-DPE @ _RTE-FE.REFS-A @ I 16 * + _RSHSP-TEMP @ 16 MOVE
            I _RSHSP-DAN @ U< IF
                _RSHSP-DAI @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RTE-LPI.OBJECT @
            ELSE
                _RSHSP-DNEXT @ DUP 1 _RSHSP-ADD _RSHSP-DNEXT !
            THEN _RSHSP-ITEM @ _RTE-LPI.OBJECT !
        ELSE
            _RSHSP-ITEM @ _RSHSP-D-TOMBSTONE
            _RSHSP-DAI @ I RTE-GLYPH-RUN-PLAN-ITEM-SIZE * + _RTE-LPI.OBJECT @
                _RSHSP-ITEM @ _RTE-LPI.OBJECT !
            _RSHSP-DPE @ _RTE-FE.BYTES-U @ _RSHSP-TEMP @ !
        THEN
    LOOP
    _RSHSP-NEW @ _RSHSP-PLAN @ _RTE-LP.ITEMS-A !
    _RSHSP-COUNT @ RTE-GLYPH-RUN-PLAN-ITEM-SIZE * _RSHSP-PLAN @ _RTE-LP.ITEMS-U !
    _RSHSP-OUT @ _RSHSP-DPE @ _RTE-FE.REFS-A !
    _RSHSP-COUNT @ 16 * _RSHSP-DPE @ _RTE-FE.REFS-U ! ;

: _RSHSP-D-REGION? ( -- flag )
    _RSHSP-KIND @ RTE-FAMILY-SERIES = IF -1 EXIT THEN
    _RSHSP-KIND @ RTE-FAMILY-INSTRUMENT = IF
        _RSHSP-DPE @ RTE-FAMILY-REGIONS@ _RSHSP-DAE @ RTE-FAMILY-REGIONS@ COMPARE 0= EXIT
    THEN
    _RSHSP-DPE @ _RTE-FE.PLAN-A @ _RTE-CP.REGION-ID @
    _RSHSP-DAE @ _RTE-FE.PLAN-A @ _RTE-CP.REGION-ID @ = ;
: _RSHSP-D-FAMILIES ( -- )
    _RSHSP-FAMILY-N @ RTE-FAMILY-ENTRY-SIZE *
        _RSHSP-DBATCH @ _RTE-FB.FAMILIES-U @ = _RSHSP-CHECK
    _RSHSP-FAMILY-N @ 0 ?DO
        I _RSHSP-DIAG-FAMILY ! 2 _RSHSP-DSTAGE !
        _RSHSP-FAMILIES @ I RTE-FAMILY-ENTRY-SIZE * + _RSHSP-DPE !
        _RSHSP-DBATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * + _RSHSP-DAE !
        _RSHSP-DPE @ _RTE-FE.KIND @ DUP _RSHSP-KIND !
            _RSHSP-DAE @ _RTE-FE.KIND @ = _RSHSP-CHECK
        _RSHSP-D-REGION? _RSHSP-CHECK
        _RSHSP-KIND @ RTE-FAMILY-ITEM-SIZE _RSHSP-STRIDE !
        _RSHSP-DPE @ RTE-FAMILY-ITEMS@ _RSHSP-STRIDE @ / _RSHSP-DN ! _RSHSP-DPI !
        _RSHSP-DAE @ RTE-FAMILY-ITEMS@ _RSHSP-STRIDE @ / _RSHSP-DAN ! _RSHSP-DAI !
        _RSHSP-KIND @ RTE-FAMILY-CONTROL = IF 3 _RSHSP-DSTAGE ! _RSHSP-D-CONTROLS ELSE
        _RSHSP-KIND @ RTE-FAMILY-GLYPH = IF 5 _RSHSP-DSTAGE ! _RSHSP-D-GLYPHS ELSE
            4 _RSHSP-DSTAGE ! _RSHSP-D-PLACE THEN THEN
    LOOP ;

\ Taskbar correlations and pane memberships name the identities just mapped.
: _RSHSP-D-METADATA ( -- )
    _RSHSP-RESULT @ RSHPL-RESULT.CORRELATIONS @ 0 ?DO
        _RSHSP-CORR @ I RSHPL-CORRELATION-SIZE * + RSHPL-CORRELATION.ID DUP @
        _RSHSP-DTASK-P0 @ _RSHSP-DTASK-A0 @ _RSHSP-DTASK-N @ _RSHSP-D-MAP SWAP !
    LOOP
    _RSHSP-MAP-U @ RSHMM-ENTRY-SIZE / 0 ?DO
        _RSHSP-MAP @ I RSHMM-ENTRY-SIZE * + RSHMM.PANE-ID DUP @
        _RSHSP-DPANE-P0 @ _RSHSP-DPANE-A0 @ _RSHSP-DPANE-N @ _RSHSP-D-MAP SWAP !
    LOOP ;

: _RSHSP-BUILD-DELTA ( -- )
    _RSHSP-ACTIVE-PART DUP RSHSP-PART.BATCH @ + _RSHSP-DBATCH !
    7 _RSHSP-DSTAGE ! 0 _RSHSP-DIAG-FAMILY !
    \ A DELTA copies the runs of rows no draw touched, except in safe mode.
    CHK-SAFE? 0= _RSHSP-REUSE ! _RSHSP-SOURCE-TARGET _RSHSP-BUILD-BATCH
    0 _RSHSP-REUSE !
    0 _RSHSP-DTASK-N ! 0 _RSHSP-DPANE-N ! 0 _RSHSP-DSER-N !
    \ New runs take identities above every one published or consumed by an
    \ acknowledged hidden START, which the producer's frontier covers.
    _RSHSP-P @ _RTHP.NEXT-OBJECT @
    _RSHSP-ACTIVE-PART RSHSP-PART.NEXT-OBJECT @ MAX _RSHSP-DNEXT !
    1 _RSHSP-DSTAGE ! _RSHSP-D-CATALOG _RSHSP-D-FAMILIES _RSHSP-D-METADATA
    6 _RSHSP-DSTAGE !
    _RSHSP-ACTIVE-PART RSHSP-PART.NEXT-REGION @ _RSHSP-NEXT-REGION !
    _RSHSP-BATCH @ _RSHSP-D-NEXT-OBJECT _RSHSP-NEXT-OBJECT !
    _RSHSP-FREEZE ;
: _RSHSP-DELTA-PREPARE ( -- status )
    0 _RSHSP-DSTAGE !
    _RSHSP-DELTA-BASE? IF _RSHSP-ACTIVE-INTACT? ELSE 0 THEN
    IF ['] _RSHSP-BUILD-DELTA _RSHSP-STAGE
    ELSE _RSHSP-P @ _RTHP-XBLOCK-DROP RTE-S-UNAVAILABLE THEN
    DUP RTE-S-OK = IF 1 _RSHSP-DIAG-PREPARED +! EXIT THEN
    1 _RSHSP-DIAG-REFUSALS +! DUP _RSHSP-DIAG-STATUS !
    _RSHSP-DSTAGE @ _RSHSP-DIAG-STAGE !
    _RSHSP-DSTAGE @ DUP 7 = IF DROP 112 _RSHSP-PSTAGE @ 15 MIN + ELSE
        DUP 2 6 WITHIN IF 16 * _RSHSP-KIND @ 15 MIN + ELSE 16 * THEN
    THEN 127 MIN CELLS _RSHSP-DIAG-DELTA-WHY + 1 SWAP +! ;
\ Inside an open retained DELTA, send what changed since the frame on
\ screen.  Both parts were checked in full when they were frozen, and the
\ acknowledged one again, with every-frame checks on, when the DELTA was
\ prepared.
: _RSHSP-DELTA-EMIT ( -- status )
    _RSHSP-PENDING-PART DUP 0= IF DROP RTE-S-UNAVAILABLE EXIT THEN
    _RSHSP-DELTA-BASE? 0= IF DROP RTE-S-INVALID EXIT THEN
    DUP RSHSP-PART.BATCH @ +
    _RSHSP-ACTIVE-PART DUP RSHSP-PART.BATCH @ +
    _RSHSP-S @ _RSHSP.SHELL @ _RTE-FAMILY-BATCH-DELTA-EMIT-PROVED ;
\ Each dispatch checks that the sidecar and its producer are the records
\ they say they are.  With every-frame checks on it also checks the
\ sidecar's header and proves its storage apart from the records it names,
\ the engine's storage, the source's live storage and RUHA's banks, and a
\ failure names the shell producer's records (check-mode.f).  Normal mode
\ skips these: RSHSP-INIT proved the storage it was lent, and the work
\ space and extension blocks that grow come from Desk's memory source,
\ whose live blocks never overlap.
: _RSHSP-DISPATCH ( event producer sidecar -- rte-status )
    DUP _RSHSP-NAMED? 0= IF DROP 2DROP RTE-S-INVALID EXIT THEN
    CHK-EVERY-FRAME? IF
        DUP _RSHSP-HEADER? _RSHSP-RECORDS-DAMAGED CHK-NAME
            0= IF DROP 2DROP RTE-S-INVALID EXIT THEN
        2 PICK RTHPX-PREPARE = 3 PICK RTHPX-DELTA-PREPARE = OR _RSHSP-LIVE-PROOF !
        DUP _RSHSP-AUTHORITY? _RSHSP-RECORDS-DAMAGED CHK-NAME
            0= IF DROP 2DROP RTE-S-INVALID EXIT THEN
    ELSE
        DUP _RSHSP-BIND
    THEN
    DROP _RSHSP-P @ <> IF DROP RTE-S-INVALID EXIT THEN
    _RSHSP-S @ _RSHSP.EXTENSION _RSHSP-P @ _RTHP.EXTENSION @ <> IF DROP RTE-S-INVALID EXIT THEN
    DUP RTHPX-PREPARE = IF DROP _RSHSP-PREPARE EXIT THEN
    DUP RTHPX-DELTA-PROBE = IF DROP _RSHSP-DELTA-PROBE EXIT THEN
    DUP RTHPX-DELTA-PREPARE = IF DROP _RSHSP-DELTA-PREPARE EXIT THEN
    DUP RTHPX-DELTA-EMIT = IF DROP _RSHSP-DELTA-EMIT EXIT THEN
    DUP RTHPX-EMIT = IF DROP
        _RSHSP-PENDING-PART DUP 0= IF DROP RTE-S-UNAVAILABLE EXIT THEN
        DUP RSHSP-PART.BATCH @ + _RSHSP-S @ _RSHSP.SHELL @
            RTE-FAMILY-BATCH-EMIT EXIT THEN
    \ The shell's part is the pending bank's own, so nothing is left to
    \ pair with it before it is published, or to drop when the bank drops
    \ it or retires.
    DUP RTHPX-PUBLISH-CHECK = IF DROP RTE-S-OK EXIT THEN
    DUP RTHPX-START-ACK = IF DROP _RSHSP-START-ACK EXIT THEN
    DUP RTHPX-PUBLISH = IF DROP _RSHSP-PUBLISH RTE-S-OK EXIT THEN
    DUP RTHPX-ABORT = IF DROP RTE-S-OK EXIT THEN
    DUP RTHPX-RETIRE = IF DROP RTE-S-OK EXIT THEN
    RTHPX-CURRENT = IF _RSHSP-CURRENT? IF RTE-S-OK ELSE RTE-S-UNAVAILABLE THEN EXIT THEN
    RTE-S-INVALID ;

: RSHSP-INIT
\ source shell-facade producer work-a/u sidecar -- status
    DUP RSHSP-SIZE _RSHSP-SPAN? 0= IF _RSHSP-6DROP RTE-S-INVALID EXIT THEN
    2 PICK 2 PICK _RSHSP-SPAN? 0= IF _RSHSP-6DROP RTE-S-INVALID EXIT THEN
    3 PICK RTHP-SIZE _RSHSP-SPAN? 0= IF _RSHSP-6DROP RTE-S-INVALID EXIT THEN
    4 PICK RTE-SHELL-FACADE-SIZE _RSHSP-SPAN? 0= IF _RSHSP-6DROP RTE-S-INVALID EXIT THEN
    5 PICK SHSN-SIZE _RSHSP-SPAN? 0= IF _RSHSP-6DROP RTE-S-INVALID EXIT THEN
    _RSHSP-S ! _RSHSP-IWORKU ! _RSHSP-IWORK !
    _RSHSP-P ! _RSHSP-ISHELL ! _RSHSP-ISOURCE !
    _RSHSP-P @ RTHP-VALID? 0= IF RTE-S-INVALID EXIT THEN
    _RSHSP-P @ _RTHP.PHASE @ _RTHP-PH-WAIT <> IF RTE-S-UNAVAILABLE EXIT THEN
    _RSHSP-P @ _RTHP.EXTENSION @ IF RTE-S-UNAVAILABLE EXIT THEN
    _RSHSP-ISHELL @ RTE-SHELL-VALID? 0= IF RTE-S-INVALID EXIT THEN
    _RSHSP-ISHELL @ _RTE-SH.BASE @ _RSHSP-P @ _RTHP.FACADE @ <> IF RTE-S-INVALID EXIT THEN
    _RSHSP-ISOURCE @ SHSN-VALID? 0= IF RTE-S-INVALID EXIT THEN
    _RSHSP-S @ RSHSP-SIZE 0 _RSHSP-SPAN!
    _RSHSP-IWORK @ _RSHSP-IWORKU @ 1 _RSHSP-SPAN!
    _RSHSP-XBLOCK-SPANS? 0= IF RTE-S-INVALID EXIT THEN
    -1 _RSHSP-LIVE-PROOF ! _RSHSP-SPANS? 0= IF RTE-S-INVALID EXIT THEN
    _RSHSP-S @ RSHSP-SIZE 0 FILL
    _RSHSP-MAGIC _RSHSP-S @ _RSHSP.MAGIC ! RSHSP-SIZE _RSHSP-S @ _RSHSP.SIZE !
    _RSHSP-S @ DUP _RSHSP.SELF !
    _RSHSP-P @ _RSHSP-S @ _RSHSP.PRODUCER !
    _RSHSP-ISOURCE @ _RSHSP-S @ _RSHSP.SOURCE !
    _RSHSP-ISHELL @ _RSHSP-S @ _RSHSP.SHELL !
    _RSHSP-IWORK @ _RSHSP-S @ _RSHSP.WORK ! _RSHSP-IWORKU @ _RSHSP-S @ _RSHSP.WORK-U !
    _RSHSP-S @ _RSHSP.EXTENSION DUP _RSHSP-OUT !
    _RTHP-EXTENSION-MAGIC OVER RTHPX.MAGIC ! RTHP-EXTENSION-SIZE OVER RTHPX.SIZE !
    DUP DUP RTHPX.SELF !
    _RSHSP-S @ OVER RTHPX.CONTEXT ! ['] _RSHSP-DISPATCH SWAP RTHPX.DISPATCH !
    RTE-S-OK ;
\ The smallest work space RSHSP-INIT accepts.  A shell producer that grows
\ from a memory source starts here.
8 CONSTANT RSHSP-FIRST-WORK-BYTES

\ RSHSP-MEMORY! ( memory sidecar -- rte-status )
\   From now on the shell producer owns its work space, which the caller
\   took from MEMORY with exactly the size it was initialized with, and
\   grows it into MEMORY.  Attach it before the first candidate.
: RSHSP-MEMORY! ( memory sidecar -- rte-status )
    DUP RSHSP-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    OVER MSRC-VALID? 0= IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RSHSP.MEMORY @ IF 2DROP RTE-S-INVALID EXIT THEN
    DUP _RSHSP.PRODUCER @ DUP _RTHP.TARGET-ACTIVE @ SWAP _RTHP.TARGET-PENDING @ OR
        IF 2DROP RTE-S-INVALID EXIT THEN
    _RSHSP.MEMORY ! RTE-S-OK ;

\ RSHSP-FINI ( sidecar -- )
\   Give back the work space the shell producer owns and clear it.  Call it
\   once it is uninstalled and nothing will dispatch to it.  The screen
\   producer keeps the parts it was given, in its own extension blocks.
: RSHSP-FINI ( sidecar -- )
    DUP _RSHSP.MAGIC @ _RSHSP-MAGIC = OVER _RSHSP.SELF @ 2 PICK = AND
    OVER _RSHSP.MEMORY @ 0<> AND IF
        DUP _RSHSP.WORK @ OVER _RSHSP.WORK-U @ 2 PICK _RSHSP.MEMORY @ MSRC-FREE
    THEN
    RSHSP-SIZE 0 FILL ;

: RSHSP-INSTALL ( sidecar -- rte-status )
    DUP RSHSP-VALID? 0= IF DROP RTE-S-INVALID EXIT THEN
    DUP _RSHSP.EXTENSION SWAP _RSHSP.PRODUCER @ RTHP-EXTENSION-INSTALL
        SCB-S-OK = IF RTE-S-OK ELSE RTE-S-UNAVAILABLE THEN ;

\ Caller has revoked the producer/input callbacks and drained/stopped the
\ transport (the Desk APTAS-UNINSTALL boundary). No wire authority is changed.
: RSHSP-UNINSTALL-AFTER-STOP ( sidecar -- rte-status )
    DUP RSHSP-VALID? 0= IF DROP RTE-S-INVALID EXIT THEN DROP
    _RSHSP-P @ _RTHP.FACADE @ RTE-UPDATE-STATE@
        RTE-S-OK <> IF DROP RTE-S-UNAVAILABLE EXIT THEN
    RTE-UPDATE-IDLE <> IF RTE-S-WOULD-BLOCK EXIT THEN
    _RSHSP-P @ _RTHP.EXTENSION @ DUP IF
        _RSHSP-S @ _RSHSP.EXTENSION <> IF RTE-S-UNAVAILABLE EXIT THEN
        0 _RSHSP-P @ _RTHP.EXTENSION !
    ELSE DROP THEN
    RTE-S-OK ;

VARIABLE _RSHSP-INPUT-OWNER VARIABLE _RSHSP-INPUT-GEN VARIABLE _RSHSP-INPUT-ID
VARIABLE _RSHSP-INPUT-INTENT VARIABLE _RSHSP-INPUT-CONTROL VARIABLE _RSHSP-INPUT-CORR
VARIABLE _RSHSP-INPUT-MODEL VARIABLE _RSHSP-INPUT-ENTRY VARIABLE _RSHSP-INPUT-MATCHES
VARIABLE _RSHSP-INPUT-BATCH
: _RSHSP-INPUT-NONE ( -- row col revision false ) 0 0 0 0 ;
\ The control a click names, in the batch of the part it is routed
\ through: the acknowledged one, which _RSHSP-CURRENT? found current.
: _RSHSP-CONTROL-FIND ( -- item|0 )
    0 _RSHSP-INPUT-MATCHES ! 0 _RSHSP-INPUT-CONTROL !
    _RSHSP-PART @ DUP RSHSP-PART.BATCH @ + _RSHSP-INPUT-BATCH !
    _RSHSP-INPUT-BATCH @ _RTE-FB.FAMILIES-U @ RTE-FAMILY-ENTRY-SIZE / 0 ?DO
        _RSHSP-INPUT-BATCH @ _RTE-FB.FAMILIES-A @ I RTE-FAMILY-ENTRY-SIZE * +
        DUP _RTE-FE.KIND @ RTE-FAMILY-CONTROL = IF
            RTE-FAMILY-ITEMS@ RTE-CONTROL-SIZE / 0 ?DO
                DUP I RTE-CONTROL-SIZE * + DUP _RTE-CONTROL.ID @ _RSHSP-INPUT-ID @ = IF
                    _RSHSP-INPUT-CONTROL ! 1 _RSHSP-INPUT-MATCHES +! ELSE DROP THEN
            LOOP DROP
        ELSE DROP THEN
    LOOP
    _RSHSP-INPUT-MATCHES @ 1 = IF _RSHSP-INPUT-CONTROL @ ELSE 0 THEN ;
: _RSHSP-CORRELATION-FIND ( -- correlation|0 )
    0 _RSHSP-INPUT-MATCHES ! 0 _RSHSP-INPUT-CORR !
    _RSHSP-PART @ RSHSP-PART.CORRELATIONS-U @ RSHPL-CORRELATION-SIZE / 0 ?DO
        _RSHSP-PART @ DUP RSHSP-PART.CORRELATIONS @ + I RSHPL-CORRELATION-SIZE * +
        DUP RSHPL-CORRELATION.ID @ _RSHSP-INPUT-ID @ = IF
            _RSHSP-INPUT-CORR ! 1 _RSHSP-INPUT-MATCHES +! ELSE DROP THEN
    LOOP
    _RSHSP-INPUT-MATCHES @ 1 = IF _RSHSP-INPUT-CORR @ ELSE 0 THEN ;
\ Desk's prompt takes positions in its value, at the first cell of its
\ value slot, against its field's revision.
: _RSHSP-PROMPT-TARGET ( -- row col revision found? )
    _RSHSP-INPUT-INTENT @ DUP RTE-INTENT-PLACE <> SWAP RTE-INTENT-EXTEND <> AND IF
        _RSHSP-INPUT-NONE EXIT
    THEN
    _RSHSP-PART @ DUP RSHSP-PART.MODEL @ + DUP SHM-PROMPT@ 0= IF
        2DROP _RSHSP-INPUT-NONE EXIT
    THEN
    SWAP SHM.HEIGHT @ 1- OVER UFLD-VALUE-ROW@ +
    OVER UFLD-VALUE-COLUMN@ ROT UFLD-REVISION@ -1 ;
VARIABLE _RSHSP-INPUT-ROOT VARIABLE _RSHSP-INPUT-CHILD VARIABLE _RSHSP-INPUT-SAVED-ID
: _RSHSP-TARGET-GEOMETRY? ( -- flag )
    _RSHSP-INPUT-CONTROL @ _RSHSP-INPUT-CHILD !
    _RSHSP-INPUT-ID @ _RSHSP-INPUT-SAVED-ID !
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.PARENT @ _RSHSP-INPUT-ID !
    _RSHSP-CONTROL-FIND _RSHSP-INPUT-ROOT !
    _RSHSP-INPUT-SAVED-ID @ _RSHSP-INPUT-ID !
    _RSHSP-INPUT-CHILD @ _RSHSP-INPUT-CONTROL !
    _RSHSP-INPUT-ROOT @ 0= IF 0 EXIT THEN
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.KIND @ RTE-CONTROL-TASKBAR <>
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.PARENT @ 0<> OR
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.REGION @ _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.REGION @ <> OR IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ SHME.KIND @ SHM-K-TASK = IF RTE-CONTROL-TASK ELSE RTE-CONTROL-LAUNCHER THEN
        _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.KIND @ <> IF 0 EXIT THEN
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.ORDER @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.INDEX @ <>
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.REGION @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.REGION @ <> OR
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.ROW @ _RSHSP-INPUT-ROOT @ _RTE-CONTROL.ROW @ +
        _RSHSP-INPUT-ENTRY @ SHME.ROW @ <> OR
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.COL @ _RSHSP-INPUT-ROOT @ _RTE-CONTROL.COL @ +
        _RSHSP-INPUT-ENTRY @ SHME.COL @ <> OR
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.WIDTH @ _RSHSP-INPUT-ENTRY @ SHME.WIDTH @ <> OR
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.HEIGHT @ _RSHSP-INPUT-ENTRY @ SHME.HEIGHT @ <> OR IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ SHME.KIND @ _RSHSP-INPUT-MODEL @
        _RSHSP-PART @ RSHSP-PART.MODEL-U @ RSHPL-BAND-BOUNDS
    RSHPL-S-OK <> IF 2DROP 2DROP 0 EXIT THEN
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.WIDTH @ <> IF DROP 2DROP 0 EXIT THEN
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.HEIGHT @ <> IF 2DROP 0 EXIT THEN
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.COL @ <> IF DROP 0 EXIT THEN
    _RSHSP-INPUT-ROOT @ _RTE-CONTROL.ROW @ <> IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ _RSHSP-INPUT-MODEL @ SHME-LABEL$
    _RSHSP-INPUT-CONTROL @ DUP _RTE-CONTROL.LABEL-A @ SWAP _RTE-CONTROL.LABEL-U @ COMPARE 0= ;
: _RSHSP-SHELL-TARGET? ( -- flag )
    _RSHSP-INPUT-INTENT @ RTE-INTENT-ACTIVATE <> IF 0 EXIT THEN
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.STATE @
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR AND
        RTE-CONTROL-VISIBLE RTE-CONTROL-ENABLED OR <> IF 0 EXIT THEN
    _RSHSP-CORRELATION-FIND DUP 0= IF DROP 0 EXIT THEN _RSHSP-INPUT-CORR !
    _RSHSP-PART @ DUP RSHSP-PART.MODEL @ + _RSHSP-INPUT-MODEL !
    _RSHSP-INPUT-MODEL @ SHM.FLAGS @ SHM-F-INPUT-BLOCKED AND IF 0 EXIT THEN
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.INDEX @
        DUP _RSHSP-INPUT-MODEL @ SHM.COUNT @ U< 0= IF DROP 0 EXIT THEN
        _RSHSP-INPUT-MODEL @ SHM-ENTRY _RSHSP-INPUT-ENTRY !
    _RSHSP-INPUT-ENTRY @ SHME.KIND @ DUP SHM-K-TASK <> SWAP SHM-K-LAUNCHER <> AND IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ SHME.KIND @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.KIND @ <>
    _RSHSP-INPUT-ENTRY @ SHME.KEY @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.KEY @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.IDENTITY @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.IDENTITY @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.OWNER-ID @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.OWNER @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.OWNER-GEN @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.GENERATION @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.ACTION @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ACTION @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.FLAGS @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.FLAGS @ <> OR IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ SHME.ROW @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ROW @ <>
    _RSHSP-INPUT-ENTRY @ SHME.COL @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.COL @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.HEIGHT @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.HEIGHT @ <> OR
    _RSHSP-INPUT-ENTRY @ SHME.WIDTH @ _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.WIDTH @ <> OR IF 0 EXIT THEN
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.SOURCE-OWNER @ _RSHSP-INPUT-MODEL @ SHM.OWNER-ID @ <>
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.SOURCE-GENERATION @ _RSHSP-INPUT-MODEL @ SHM.OWNER-GEN @ <> OR
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.EPOCH @ _RSHSP-INPUT-MODEL @ SHM.EPOCH @ <> OR
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.DRAW @ _RSHSP-ACTIVE-BANK _RTHP-TB.DRAW @ <> OR
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ATTACHMENT @ _RSHSP-INPUT-MODEL @ SHM.OWNER-ID @ <> OR IF 0 EXIT THEN
    _RSHSP-TARGET-GEOMETRY? 0= IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ SHME.FLAGS @ SHM-F-DISABLED AND IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ SHME.KIND @ SHM-K-LAUNCHER = IF
        _RSHSP-INPUT-ENTRY @ SHME.ACTION @ 0= IF 0 EXIT THEN
    THEN
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ACTION-OFFSET @
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ACTION-BYTES @ _RTHP-U32+? 0= IF DROP 0 EXIT THEN
    _RSHSP-PART @ RSHSP-PART.ACTIONS-U @ U> IF 0 EXIT THEN
    _RSHSP-INPUT-ENTRY @ _RSHSP-INPUT-MODEL @ SHME-ACTION$
    _RSHSP-PART @ DUP RSHSP-PART.ACTIONS @ +
        _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ACTION-OFFSET @ +
    _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ACTION-BYTES @ COMPARE 0= ;
: RSHSP-CONTROL-TARGET@
\ owner generation control-id intent sidecar -- row col revision found?
    DUP RSHSP-VALID? 0= IF DROP 2DROP 2DROP _RSHSP-INPUT-NONE EXIT THEN DROP
    _RSHSP-INPUT-INTENT ! _RSHSP-INPUT-ID ! _RSHSP-INPUT-GEN ! _RSHSP-INPUT-OWNER !
    _RSHSP-S @ _RSHSP.EXTENSION _RSHSP-P @ _RTHP.EXTENSION @ <> IF _RSHSP-INPUT-NONE EXIT THEN
    _RSHSP-ACTIVE-PART 0= IF
        _RSHSP-INPUT-OWNER @ _RSHSP-INPUT-GEN @ _RSHSP-INPUT-ID @ _RSHSP-INPUT-INTENT @
        _RSHSP-P @ RTHP-CONTROL-TARGET@ EXIT THEN
    _RSHSP-CURRENT? 0= IF _RSHSP-INPUT-NONE EXIT THEN
    _RSHSP-ACTIVE-INTACT? 0= IF _RSHSP-INPUT-NONE EXIT THEN
    _RSHSP-P @ _RTHP-ACTIVE-SEALED? 0= IF _RSHSP-INPUT-NONE EXIT THEN
    _RSHSP-INPUT-OWNER @ _RSHSP-ACTIVE-BANK _RTHP-TB.OWNER @ <>
    _RSHSP-INPUT-GEN @ _RSHSP-ACTIVE-BANK _RTHP-TB.GENERATION @ <> OR IF _RSHSP-INPUT-NONE EXIT THEN
    _RSHSP-CONTROL-FIND DUP 0= IF DROP _RSHSP-INPUT-NONE EXIT THEN _RSHSP-INPUT-CONTROL !
    _RSHSP-PART @ RSHSP-PART.PROMPT @ ?DUP IF
        _RSHSP-INPUT-ID @ = IF _RSHSP-PROMPT-TARGET EXIT THEN
    THEN
    _RSHSP-INPUT-CONTROL @ _RTE-CONTROL.KIND @ DUP RTE-CONTROL-TASK = SWAP RTE-CONTROL-LAUNCHER = OR IF
        _RSHSP-SHELL-TARGET? 0= IF _RSHSP-INPUT-NONE EXIT THEN
        _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.ROW @
        _RSHSP-INPUT-CORR @ RSHPL-CORRELATION.COL @ _RSHSP-INPUT-MODEL @ SHM.EPOCH @ -1 EXIT
    THEN
    _RSHSP-INPUT-OWNER @ _RSHSP-INPUT-GEN @ _RSHSP-INPUT-ID @ _RSHSP-INPUT-INTENT @
    _RSHSP-P @ RTHP-CONTROL-TARGET@ ;

HERE _RSHSP-OWNED-LIMIT !
