\ =====================================================================
\  akashic/tui/game/widgets/dialog-box.f — RPG Dialog Box Widget
\ =====================================================================
\
\  An RPG-style text box with typewriter-effect text reveal, optional
\  speaker name, portrait canvas, and branching choices.  The box
\  renders at the bottom of the game view.
\
\  Text is revealed character by character.  DBOX-TICK advances the
\  reveal cursor.  The player can press ENTER/SPACE to skip to
\  full reveal, or arrow-select among choices once text is fully
\  shown.
\
\  Portrait: an optional Braille canvas sub-widget rendered to the
\  left of the text area.  Set with DBOX-PORTRAIT!.
\
\  Descriptor (header + 14 cells = 152 bytes):
\    +0..+39  widget header  (type = WDG-T-DIALOG-BOX)
\    +40   speaker-a     Speaker name string address
\    +48   speaker-u     Speaker name string length
\    +56   text-a        Full message text address
\    +64   text-u        Full message text length
\    +72   reveal-pos    Characters revealed so far (typewriter)
\    +80   speed         Characters per tick (default 1)
\    +88   choices-a     Choice labels array (addr+len pairs) or 0
\    +96   choice-count  Number of choices
\    +104  choice-sel    Currently highlighted choice
\    +112  result        -1 = open, >=0 = chosen index
\    +120  portrait      Canvas widget address (or 0)
\    +128  flags2        DBOX-F-* flags
\    +136  on-done-xt    Callback ( choice widget -- ) or 0
\    +144  reserved
\
\  Public API:
\    DBOX-NEW         ( rgn -- widget )
\    DBOX-FREE        ( widget -- )
\    DBOX-SET         ( speaker-a u text-a u widget -- )
\    DBOX-CHOICES!    ( labels count widget -- )
\    DBOX-PORTRAIT!   ( canvas widget -- )
\    DBOX-SPEED!      ( n widget -- )
\    DBOX-TICK        ( widget -- )
\    DBOX-SKIP        ( widget -- )
\    DBOX-DONE?       ( widget -- flag )
\    DBOX-REVEALED?   ( widget -- flag )
\    DBOX-RESULT      ( widget -- n )
\    DBOX-ON-DONE     ( xt widget -- )
\    DBOX-RESET       ( widget -- )
\
\  Prefix: DBOX- (public), _DBOX- (internal)
\  Provider: akashic-tui-game-widgets-dialog-box
\  Dependencies: widget.f, draw.f, box.f, keys.f, region.f

PROVIDED ak-tui-gw-dialog-box

REQUIRE ../../widget.f
REQUIRE ../../draw.f
REQUIRE ../../box.f
REQUIRE ../../keys.f
REQUIRE ../../region.f

\ =====================================================================
\  §1 — Constants & Layout
\ =====================================================================

20 CONSTANT WDG-T-DIALOG-BOX

40  CONSTANT _DBOX-O-SPK-A
48  CONSTANT _DBOX-O-SPK-U
56  CONSTANT _DBOX-O-TXT-A
64  CONSTANT _DBOX-O-TXT-U
72  CONSTANT _DBOX-O-REVEAL
80  CONSTANT _DBOX-O-SPEED
88  CONSTANT _DBOX-O-CHOICES
96  CONSTANT _DBOX-O-CCNT
104 CONSTANT _DBOX-O-CSEL
112 CONSTANT _DBOX-O-RESULT
120 CONSTANT _DBOX-O-PORTRAIT
128 CONSTANT _DBOX-O-FLAGS2
136 CONSTANT _DBOX-O-DONE-XT
144 CONSTANT _DBOX-O-RESERVED
152 CONSTANT _DBOX-DESC-SZ

\ Flags2
1 CONSTANT DBOX-F-REVEALED   \ text fully revealed

\ =====================================================================
\  §2 — Configuration
\ =====================================================================

VARIABLE _DBOX-S-SA   VARIABLE _DBOX-S-SU
VARIABLE _DBOX-S-TA   VARIABLE _DBOX-S-TU

: DBOX-SET  ( speaker-a u text-a u widget -- )
    >R
    _DBOX-S-TU !  _DBOX-S-TA !
    _DBOX-S-SU !  _DBOX-S-SA !
    _DBOX-S-SA @ R@ _DBOX-O-SPK-A + !
    _DBOX-S-SU @ R@ _DBOX-O-SPK-U + !
    _DBOX-S-TA @ R@ _DBOX-O-TXT-A + !
    _DBOX-S-TU @ R@ _DBOX-O-TXT-U + !
    0            R@ _DBOX-O-REVEAL + !
    0            R@ _DBOX-O-FLAGS2 + !
    -1           R@ _DBOX-O-RESULT + !
    R> WDG-DIRTY ;

: DBOX-CHOICES!  ( labels count widget -- )
    >R
    R@ _DBOX-O-CCNT    + !
    R@ _DBOX-O-CHOICES + !
    0 R@ _DBOX-O-CSEL  + !
    R> WDG-DIRTY ;

: DBOX-PORTRAIT!  ( canvas widget -- )
    _DBOX-O-PORTRAIT + ! ;

: DBOX-SPEED!  ( n widget -- )
    SWAP 1 MAX SWAP _DBOX-O-SPEED + ! ;

: DBOX-ON-DONE  ( xt widget -- )
    _DBOX-O-DONE-XT + ! ;

\ =====================================================================
\  §3 — Typewriter Control
\ =====================================================================

: DBOX-REVEALED?  ( widget -- flag )
    DUP _DBOX-O-REVEAL + @
    SWAP _DBOX-O-TXT-U + @ >= ;

: DBOX-DONE?  ( widget -- flag )
    _DBOX-O-RESULT + @ -1 <> ;

: DBOX-RESULT  ( widget -- n )
    _DBOX-O-RESULT + @ ;

: DBOX-TICK  ( widget -- )
    DUP DBOX-REVEALED? IF DROP EXIT THEN
    DUP _DBOX-O-SPEED + @
    OVER _DBOX-O-REVEAL + @ +
    OVER _DBOX-O-TXT-U + @ MIN
    OVER _DBOX-O-REVEAL + !
    DUP DBOX-REVEALED? IF
        DUP _DBOX-O-FLAGS2 + @
        DBOX-F-REVEALED OR
        OVER _DBOX-O-FLAGS2 + !
    THEN
    WDG-DIRTY ;

: DBOX-SKIP  ( widget -- )
    DUP _DBOX-O-TXT-U + @
    OVER _DBOX-O-REVEAL + !
    DUP _DBOX-O-FLAGS2 + @
    DBOX-F-REVEALED OR
    OVER _DBOX-O-FLAGS2 + !
    WDG-DIRTY ;

: DBOX-RESET  ( widget -- )
    DUP >R
    0 R@ _DBOX-O-REVEAL  + !
    0 R@ _DBOX-O-FLAGS2  + !
    -1 R@ _DBOX-O-RESULT + !
    0 R@ _DBOX-O-CSEL    + !
    R> WDG-DIRTY ;

\ =====================================================================
\  §4 — Drawing
\ =====================================================================

VARIABLE _DBOX-DW   \ widget
VARIABLE _DBOX-RW   \ region width
VARIABLE _DBOX-RH   \ region height
VARIABLE _DBOX-TX   \ text-area left column
VARIABLE _DBOX-TW   \ text-area width

: _DBOX-DRAW-SPEAKER  ( widget -- )
    DUP _DBOX-O-SPK-U + @ 0= IF DROP EXIT THEN
    DRW-STYLE-SAVE
    CELL-A-BOLD DRW-ATTR!
    DUP _DBOX-O-SPK-A + @
    OVER _DBOX-O-SPK-U + @
    1 _DBOX-TX @ DRW-TEXT
    DRW-STYLE-RESTORE
    DROP ;

VARIABLE _DBOX-MW  VARIABLE _DBOX-MR  VARIABLE _DBOX-MA  VARIABLE _DBOX-ML

: _DBOX-DRAW-TEXT  ( widget -- )
    DUP _DBOX-O-TXT-A + @  _DBOX-MA !
    DUP _DBOX-O-REVEAL + @ _DBOX-ML !
    DROP
    _DBOX-TW @ 2 - DUP 1 < IF DROP 1 THEN _DBOX-MW !
    2 _DBOX-MR !
    BEGIN
        _DBOX-ML @ 0>
        _DBOX-MR @ _DBOX-RH @ 2 - <
        AND
    WHILE
        _DBOX-MA @
        _DBOX-ML @ _DBOX-MW @ MIN
        _DBOX-MR @ _DBOX-TX @ DRW-TEXT
        _DBOX-ML @ _DBOX-MW @ MIN
        DUP _DBOX-MA +!
        NEGATE _DBOX-ML +!
        1 _DBOX-MR +!
    REPEAT ;

VARIABLE _DBOX-CI   VARIABLE _DBOX-CC   VARIABLE _DBOX-CROW

: _DBOX-DRAW-CHOICES  ( widget -- )
    DUP _DBOX-O-CCNT + @ 0= IF DROP EXIT THEN
    DUP DBOX-REVEALED? 0= IF DROP EXIT THEN
    _DBOX-RH @ 2 - _DBOX-CROW !
    DUP _DBOX-O-CCNT + @ _DBOX-CC !
    DUP _DBOX-O-CHOICES + @ SWAP _DBOX-O-CSEL + @
    _DBOX-CC @ 0 ?DO
        I 2 PICK = IF CELL-A-REVERSE DRW-ATTR! THEN
        OVER I 16 * +         ( choices sel choice-entry )
        DUP @ SWAP 8 + @      ( choices sel c-addr c-len )
        _DBOX-CROW @ _DBOX-TX @ DRW-TEXT
        1 _DBOX-CROW +!
        I 2 PICK = IF 0 DRW-ATTR! THEN
    LOOP
    2DROP ;

: _DBOX-DRAW  ( widget -- )
    _DBOX-DW !
    _DBOX-DW @ WDG-REGION RGN-W _DBOX-RW !
    _DBOX-DW @ WDG-REGION RGN-H _DBOX-RH !

    \ Box frame
    BOX-SINGLE 0 0 _DBOX-RH @ _DBOX-RW @ BOX-DRAW

    \ Clear interior
    32 1 1 _DBOX-RH @ 2 - _DBOX-RW @ 2 - DRW-FILL-RECT

    \ Portrait offset: if portrait present, text starts further right
    _DBOX-DW @ _DBOX-O-PORTRAIT + @ 0<> IF
        _DBOX-DW @ _DBOX-O-PORTRAIT + @ WDG-REGION RGN-W 1+
        _DBOX-TX !
    ELSE
        1 _DBOX-TX !
    THEN
    _DBOX-RW @ _DBOX-TX @ - 1- _DBOX-TW !

    \ Portrait (if set)
    _DBOX-DW @ _DBOX-O-PORTRAIT + @ ?DUP IF WDG-DRAW THEN

    \ Speaker name
    _DBOX-DW @ _DBOX-DRAW-SPEAKER

    \ Revealed text
    _DBOX-DW @ _DBOX-DRAW-TEXT

    \ Choices
    _DBOX-DW @ _DBOX-DRAW-CHOICES ;

\ =====================================================================
\  §5 — Event Handler
\ =====================================================================

VARIABLE _DBOX-HW   VARIABLE _DBOX-HT   VARIABLE _DBOX-HC

: _DBOX-HANDLE  ( event widget -- consumed? )
    _DBOX-HW !
    DUP @ _DBOX-HT !
    8 + @ _DBOX-HC !
    _DBOX-HT @ KEY-T-SPECIAL = IF
        _DBOX-HC @ CASE
            KEY-ENTER OF
                _DBOX-HW @ DBOX-REVEALED? 0= IF
                    _DBOX-HW @ DBOX-SKIP
                ELSE
                    _DBOX-HW @ _DBOX-O-CCNT + @ 0> IF
                        _DBOX-HW @ _DBOX-O-CSEL + @
                        _DBOX-HW @ _DBOX-O-RESULT + !
                        _DBOX-HW @ _DBOX-O-DONE-XT + @ ?DUP IF
                            _DBOX-HW @ _DBOX-O-CSEL + @
                            _DBOX-HW @ ROT EXECUTE
                        THEN
                    ELSE
                        0 _DBOX-HW @ _DBOX-O-RESULT + !
                        _DBOX-HW @ _DBOX-O-DONE-XT + @ ?DUP IF
                            0 _DBOX-HW @ ROT EXECUTE
                        THEN
                    THEN
                THEN
                _DBOX-HW @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-UP OF
                _DBOX-HW @ DBOX-REVEALED? IF
                    _DBOX-HW @ _DBOX-O-CSEL + @ DUP 0> IF
                        1- _DBOX-HW @ _DBOX-O-CSEL + !
                        _DBOX-HW @ WDG-DIRTY
                    ELSE DROP THEN
                THEN
                -1 EXIT
            ENDOF
            KEY-DOWN OF
                _DBOX-HW @ DBOX-REVEALED? IF
                    _DBOX-HW @ _DBOX-O-CSEL + @
                    _DBOX-HW @ _DBOX-O-CCNT + @ 1- < IF
                        _DBOX-HW @ _DBOX-O-CSEL + @
                        1+ _DBOX-HW @ _DBOX-O-CSEL + !
                        _DBOX-HW @ WDG-DIRTY
                    THEN
                THEN
                -1 EXIT
            ENDOF
        ENDCASE
    THEN
    _DBOX-HT @ KEY-T-CHAR = IF
        _DBOX-HC @ 32 = IF    \ space = skip / confirm
            _DBOX-HW @ DBOX-REVEALED? 0= IF
                _DBOX-HW @ DBOX-SKIP
                _DBOX-HW @ WDG-DIRTY
                -1 EXIT
            THEN
        THEN
    THEN
    0 ;

\ =====================================================================
\  §6 — Constructor / Destructor
\ =====================================================================

: DBOX-NEW  ( rgn -- widget )
    _DBOX-DESC-SZ ALLOCATE
    0<> ABORT" DBOX-NEW: alloc"
    WDG-T-DIALOG-BOX  OVER _WDG-O-TYPE       + !
    SWAP               OVER _WDG-O-REGION     + !
    ['] _DBOX-DRAW     OVER _WDG-O-DRAW-XT    + !
    ['] _DBOX-HANDLE   OVER _WDG-O-HANDLE-XT  + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                       OVER _WDG-O-FLAGS      + !
    0 OVER _DBOX-O-SPK-A    + !
    0 OVER _DBOX-O-SPK-U    + !
    0 OVER _DBOX-O-TXT-A    + !
    0 OVER _DBOX-O-TXT-U    + !
    0 OVER _DBOX-O-REVEAL   + !
    1 OVER _DBOX-O-SPEED    + !
    0 OVER _DBOX-O-CHOICES  + !
    0 OVER _DBOX-O-CCNT     + !
    0 OVER _DBOX-O-CSEL     + !
    -1 OVER _DBOX-O-RESULT  + !
    0 OVER _DBOX-O-PORTRAIT + !
    0 OVER _DBOX-O-FLAGS2   + !
    0 OVER _DBOX-O-DONE-XT  + !
    0 OVER _DBOX-O-RESERVED + ! ;

: DBOX-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\  §7 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _dbox-guard

' DBOX-NEW        CONSTANT _dbox-new-xt
' DBOX-FREE       CONSTANT _dbox-free-xt
' DBOX-SET        CONSTANT _dbox-set-xt
' DBOX-CHOICES!   CONSTANT _dbox-choices-xt
' DBOX-PORTRAIT!  CONSTANT _dbox-portrait-xt
' DBOX-SPEED!     CONSTANT _dbox-speed-xt
' DBOX-TICK       CONSTANT _dbox-tick-xt
' DBOX-SKIP       CONSTANT _dbox-skip-xt
' DBOX-RESET      CONSTANT _dbox-reset-xt

: DBOX-NEW        _dbox-new-xt        _dbox-guard WITH-GUARD ;
: DBOX-FREE       _dbox-free-xt       _dbox-guard WITH-GUARD ;
: DBOX-SET        _dbox-set-xt        _dbox-guard WITH-GUARD ;
: DBOX-CHOICES!   _dbox-choices-xt    _dbox-guard WITH-GUARD ;
: DBOX-PORTRAIT!  _dbox-portrait-xt   _dbox-guard WITH-GUARD ;
: DBOX-SPEED!     _dbox-speed-xt      _dbox-guard WITH-GUARD ;
: DBOX-TICK       _dbox-tick-xt       _dbox-guard WITH-GUARD ;
: DBOX-SKIP       _dbox-skip-xt       _dbox-guard WITH-GUARD ;
: DBOX-RESET      _dbox-reset-xt      _dbox-guard WITH-GUARD ;
[THEN] [THEN]
