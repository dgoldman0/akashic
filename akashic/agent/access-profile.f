\ =====================================================================
\  access-profile.f - Desk-owned Agent disclosure and capability presets
\ =====================================================================
\  An access profile is policy metadata, not authority.  Desk compiles a
\  validated profile into an exact per-run capability facet and Mandate;
\  target owners still require and consume sealed one-use grants.
\ =====================================================================

PROVIDED akashic-agent-access-profile

REQUIRE ../interop/mandate.f
REQUIRE ../text/utf8.f

0 CONSTANT AAP-S-OK
1 CONSTANT AAP-S-INVALID
2 CONSTANT AAP-S-BUSY
3 CONSTANT AAP-S-UNAVAILABLE

1 CONSTANT AAP-PRESET-CHAT-ONLY
2 CONSTANT AAP-PRESET-PRACTICE-READ
3 CONSTANT AAP-PRESET-PRACTICE-ASSIST

1 CONSTANT AAP-F-CHAT-HISTORY
2 CONSTANT AAP-F-CONTEXT-OBSERVE
4 CONSTANT AAP-F-REVIEW-CHANGES
AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR
AAP-F-REVIEW-CHANGES OR CONSTANT AAP-FLAGS-MASK

1094796112 CONSTANT AAP-MAGIC       \ "AAPP"
1          CONSTANT AAP-ABI-VERSION

  0 CONSTANT _AAP-MAGIC
  8 CONSTANT _AAP-ABI
 16 CONSTANT _AAP-SIZE
 24 CONSTANT _AAP-PRESET
 32 CONSTANT _AAP-ID-A
 40 CONSTANT _AAP-ID-U
 48 CONSTANT _AAP-LABEL-A
 56 CONSTANT _AAP-LABEL-U
 64 CONSTANT _AAP-FLAGS
 72 CONSTANT _AAP-EFFECTS
 80 CONSTANT _AAP-DISPOSITION
 88 CONSTANT _AAP-HISTORY-ITEMS
 96 CONSTANT _AAP-HISTORY-BYTES
104 CONSTANT _AAP-TIME-BUDGET-MS
112 CONSTANT _AAP-MEMORY-BUDGET
120 CONSTANT _AAP-TOKEN-BUDGET
128 CONSTANT _AAP-TOOL-BUDGET
136 CONSTANT _AAP-DISCLOSURE-BUDGET
144 CONSTANT AGENT-ACCESS-PROFILE-SIZE

: AAP.MAGIC              ( profile -- a ) _AAP-MAGIC + ;
: AAP.ABI                ( profile -- a ) _AAP-ABI + ;
: AAP.SIZE               ( profile -- a ) _AAP-SIZE + ;
: AAP.PRESET             ( profile -- a ) _AAP-PRESET + ;
: AAP.ID-A               ( profile -- a ) _AAP-ID-A + ;
: AAP.ID-U               ( profile -- a ) _AAP-ID-U + ;
: AAP.LABEL-A            ( profile -- a ) _AAP-LABEL-A + ;
: AAP.LABEL-U            ( profile -- a ) _AAP-LABEL-U + ;
: AAP.FLAGS              ( profile -- a ) _AAP-FLAGS + ;
: AAP.EFFECTS            ( profile -- a ) _AAP-EFFECTS + ;
: AAP.DISPOSITION        ( profile -- a ) _AAP-DISPOSITION + ;
: AAP.HISTORY-ITEMS      ( profile -- a ) _AAP-HISTORY-ITEMS + ;
: AAP.HISTORY-BYTES      ( profile -- a ) _AAP-HISTORY-BYTES + ;
: AAP.TIME-BUDGET-MS     ( profile -- a ) _AAP-TIME-BUDGET-MS + ;
: AAP.MEMORY-BUDGET      ( profile -- a ) _AAP-MEMORY-BUDGET + ;
: AAP.TOKEN-BUDGET       ( profile -- a ) _AAP-TOKEN-BUDGET + ;
: AAP.TOOL-BUDGET        ( profile -- a ) _AAP-TOOL-BUDGET + ;
: AAP.DISCLOSURE-BUDGET  ( profile -- a ) _AAP-DISCLOSURE-BUDGET + ;

: AAP-ID$  ( profile -- addr len )
    DUP AAP.ID-A @ SWAP AAP.ID-U @ ;

: AAP-LABEL$  ( profile -- addr len )
    DUP AAP.LABEL-A @ SWAP AAP.LABEL-U @ ;

: AAP-INIT  ( profile -- )
    DUP AGENT-ACCESS-PROFILE-SIZE 0 FILL
    AAP-MAGIC OVER AAP.MAGIC !
    AAP-ABI-VERSION OVER AAP.ABI !
    AGENT-ACCESS-PROFILE-SIZE SWAP AAP.SIZE ! ;

: _AAP-TEXT-VALID?  ( addr len -- flag )
    DUP 1 < OVER 64 > OR IF 2DROP 0 EXIT THEN
    UTF8-VALID? ;

VARIABLE _AAPV-P

: _AAP-COMMON-EXACT?  ( -- flag )
    _AAPV-P @ AAP.HISTORY-ITEMS @ 12 =
    _AAPV-P @ AAP.HISTORY-BYTES @ 4096 = AND
    _AAPV-P @ AAP.TIME-BUDGET-MS @ 600000 = AND
    _AAPV-P @ AAP.MEMORY-BUDGET @ 0= AND
    _AAPV-P @ AAP.TOKEN-BUDGET @ 0= AND ;

\ A preset is the authority vocabulary, not a cosmetic label.  Pin every
\ field Desk compiles so corruption cannot turn one preset into another while
\ retaining a trusted preset id.
: _AAP-PRESET-EXACT?  ( -- flag )
    _AAP-COMMON-EXACT? 0= IF 0 EXIT THEN
    _AAPV-P @ AAP.PRESET @ CASE
        AAP-PRESET-CHAT-ONLY OF
            _AAPV-P @ AAP-ID$ S" desk.chat-only" STR-STR=
            _AAPV-P @ AAP-LABEL$ S" Chat only" STR-STR= AND
            _AAPV-P @ AAP.FLAGS @ AAP-F-CHAT-HISTORY = AND
            _AAPV-P @ AAP.EFFECTS @ 0= AND
            _AAPV-P @ AAP.DISPOSITION @ MAND-D-READ-ONLY = AND
            _AAPV-P @ AAP.TOOL-BUDGET @ 0= AND
            _AAPV-P @ AAP.DISCLOSURE-BUDGET @ 8192 = AND
        ENDOF
        AAP-PRESET-PRACTICE-READ OF
            _AAPV-P @ AAP-ID$ S" desk.practice-read" STR-STR=
            _AAPV-P @ AAP-LABEL$ S" Practice read only" STR-STR= AND
            _AAPV-P @ AAP.FLAGS @
                AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR = AND
            _AAPV-P @ AAP.EFFECTS @ CAP-E-OBSERVE = AND
            _AAPV-P @ AAP.DISPOSITION @ MAND-D-READ-ONLY = AND
            _AAPV-P @ AAP.TOOL-BUDGET @ 4 = AND
            _AAPV-P @ AAP.DISCLOSURE-BUDGET @ 32768 = AND
        ENDOF
        AAP-PRESET-PRACTICE-ASSIST OF
            _AAPV-P @ AAP-ID$ S" desk.practice-assist" STR-STR=
            _AAPV-P @ AAP-LABEL$ S" Practice assist" STR-STR= AND
            _AAPV-P @ AAP.FLAGS @ AAP-F-CHAT-HISTORY
                AAP-F-CONTEXT-OBSERVE OR AAP-F-REVIEW-CHANGES OR = AND
            _AAPV-P @ AAP.EFFECTS @ CAP-E-OBSERVE CAP-E-NAVIGATE OR
                CAP-E-MUTATE OR CAP-E-PERSIST OR = AND
            _AAPV-P @ AAP.DISPOSITION @ MAND-D-COMMIT = AND
            _AAPV-P @ AAP.TOOL-BUDGET @ 8 = AND
            _AAPV-P @ AAP.DISCLOSURE-BUDGET @ 49152 = AND
        ENDOF
        0 SWAP
    ENDCASE ;

: AAP-VALID?  ( profile -- flag )
    DUP 0= IF DROP 0 EXIT THEN DUP _AAPV-P !
    DUP AAP.MAGIC @ AAP-MAGIC =
    OVER AAP.ABI @ AAP-ABI-VERSION = AND
    OVER AAP.SIZE @ AGENT-ACCESS-PROFILE-SIZE >= AND 0= IF DROP 0 EXIT THEN
    DROP
    _AAPV-P @ AAP.PRESET @ DUP AAP-PRESET-CHAT-ONLY =
        OVER AAP-PRESET-PRACTICE-READ = OR
        SWAP AAP-PRESET-PRACTICE-ASSIST = OR 0= IF 0 EXIT THEN
    _AAPV-P @ AAP-ID$ _AAP-TEXT-VALID? 0= IF 0 EXIT THEN
    _AAPV-P @ AAP-LABEL$ _AAP-TEXT-VALID? 0= IF 0 EXIT THEN
    _AAPV-P @ AAP.FLAGS @ DUP 0< IF DROP 0 EXIT THEN
        AAP-FLAGS-MASK INVERT AND IF 0 EXIT THEN
    _AAPV-P @ AAP.EFFECTS @ MAND-EFFECT-MASK-VALID? 0= IF 0 EXIT THEN
    _AAPV-P @ AAP.DISPOSITION @ MAND-DISPOSITION-VALID? 0= IF 0 EXIT THEN
    _AAPV-P @ AAP.HISTORY-ITEMS @ DUP 0< SWAP 64 > OR IF 0 EXIT THEN
    _AAPV-P @ AAP.HISTORY-BYTES @ 0< IF 0 EXIT THEN
    _AAPV-P @ AAP.TIME-BUDGET-MS @ 0< IF 0 EXIT THEN
    _AAPV-P @ AAP.MEMORY-BUDGET @ 0< IF 0 EXIT THEN
    _AAPV-P @ AAP.TOKEN-BUDGET @ 0< IF 0 EXIT THEN
    _AAPV-P @ AAP.TOOL-BUDGET @ 0< IF 0 EXIT THEN
    _AAPV-P @ AAP.DISCLOSURE-BUDGET @ DUP 1 < IF DROP 0 EXIT THEN
    _AAPV-P @ AAP.HISTORY-BYTES @ < IF 0 EXIT THEN
    _AAPV-P @ AAP.FLAGS @ AAP-F-CHAT-HISTORY AND IF
        _AAPV-P @ AAP.HISTORY-ITEMS @ 0> 0= IF 0 EXIT THEN
        _AAPV-P @ AAP.HISTORY-BYTES @ 0> 0= IF 0 EXIT THEN
    ELSE
        _AAPV-P @ AAP.HISTORY-ITEMS @ IF 0 EXIT THEN
        _AAPV-P @ AAP.HISTORY-BYTES @ IF 0 EXIT THEN
    THEN
    _AAPV-P @ AAP.FLAGS @
        AAP-F-CONTEXT-OBSERVE AAP-F-REVIEW-CHANGES OR AND 0= IF
        _AAPV-P @ AAP.TOOL-BUDGET @ IF 0 EXIT THEN
    THEN
    _AAPV-P @ AAP.FLAGS @ AAP-F-CONTEXT-OBSERVE AND IF
        _AAPV-P @ AAP.EFFECTS @ CAP-E-OBSERVE AND 0= IF 0 EXIT THEN
    THEN
    _AAPV-P @ AAP.FLAGS @ AAP-F-REVIEW-CHANGES AND IF
        _AAPV-P @ AAP.EFFECTS @
            CAP-E-NAVIGATE CAP-E-MUTATE OR CAP-E-PERSIST OR AND
            0= IF 0 EXIT THEN
        _AAPV-P @ AAP.DISPOSITION @ MAND-D-COMMIT <> IF 0 EXIT THEN
    THEN
    _AAP-PRESET-EXACT? ;

VARIABLE _AAPI-PRESET
VARIABLE _AAPI-P

: AAP-PRESET!  ( preset profile -- status )
    _AAPI-P ! _AAPI-PRESET !
    _AAPI-PRESET @ DUP AAP-PRESET-CHAT-ONLY =
        OVER AAP-PRESET-PRACTICE-READ = OR
        SWAP AAP-PRESET-PRACTICE-ASSIST = OR 0= IF
        AAP-S-INVALID EXIT
    THEN
    _AAPI-P @ AAP-INIT
    _AAPI-PRESET @ _AAPI-P @ AAP.PRESET !
    _AAPI-PRESET @ CASE
        AAP-PRESET-CHAT-ONLY OF
            S" desk.chat-only"
                _AAPI-P @ AAP.ID-U ! _AAPI-P @ AAP.ID-A !
            S" Chat only"
                _AAPI-P @ AAP.LABEL-U ! _AAPI-P @ AAP.LABEL-A !
            AAP-F-CHAT-HISTORY _AAPI-P @ AAP.FLAGS !
            0 _AAPI-P @ AAP.EFFECTS !
            MAND-D-READ-ONLY _AAPI-P @ AAP.DISPOSITION !
            12 _AAPI-P @ AAP.HISTORY-ITEMS !
            4096 _AAPI-P @ AAP.HISTORY-BYTES !
            600000 _AAPI-P @ AAP.TIME-BUDGET-MS !
            0 _AAPI-P @ AAP.MEMORY-BUDGET !
            0 _AAPI-P @ AAP.TOKEN-BUDGET !
            0 _AAPI-P @ AAP.TOOL-BUDGET !
            8192 _AAPI-P @ AAP.DISCLOSURE-BUDGET !
        ENDOF
        AAP-PRESET-PRACTICE-READ OF
            S" desk.practice-read"
                _AAPI-P @ AAP.ID-U ! _AAPI-P @ AAP.ID-A !
            S" Practice read only"
                _AAPI-P @ AAP.LABEL-U ! _AAPI-P @ AAP.LABEL-A !
            AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR
                _AAPI-P @ AAP.FLAGS !
            CAP-E-OBSERVE _AAPI-P @ AAP.EFFECTS !
            MAND-D-READ-ONLY _AAPI-P @ AAP.DISPOSITION !
            12 _AAPI-P @ AAP.HISTORY-ITEMS !
            4096 _AAPI-P @ AAP.HISTORY-BYTES !
            600000 _AAPI-P @ AAP.TIME-BUDGET-MS !
            0 _AAPI-P @ AAP.MEMORY-BUDGET !
            0 _AAPI-P @ AAP.TOKEN-BUDGET !
            4 _AAPI-P @ AAP.TOOL-BUDGET !
            32768 _AAPI-P @ AAP.DISCLOSURE-BUDGET !
        ENDOF
        AAP-PRESET-PRACTICE-ASSIST OF
            S" desk.practice-assist"
                _AAPI-P @ AAP.ID-U ! _AAPI-P @ AAP.ID-A !
            S" Practice assist"
                _AAPI-P @ AAP.LABEL-U ! _AAPI-P @ AAP.LABEL-A !
            AAP-F-CHAT-HISTORY AAP-F-CONTEXT-OBSERVE OR
                AAP-F-REVIEW-CHANGES OR _AAPI-P @ AAP.FLAGS !
            CAP-E-OBSERVE CAP-E-NAVIGATE OR CAP-E-MUTATE OR CAP-E-PERSIST OR
                _AAPI-P @ AAP.EFFECTS !
            MAND-D-COMMIT _AAPI-P @ AAP.DISPOSITION !
            12 _AAPI-P @ AAP.HISTORY-ITEMS !
            4096 _AAPI-P @ AAP.HISTORY-BYTES !
            600000 _AAPI-P @ AAP.TIME-BUDGET-MS !
            0 _AAPI-P @ AAP.MEMORY-BUDGET !
            0 _AAPI-P @ AAP.TOKEN-BUDGET !
            8 _AAPI-P @ AAP.TOOL-BUDGET !
            49152 _AAPI-P @ AAP.DISCLOSURE-BUDGET !
        ENDOF
        DROP AAP-S-INVALID EXIT
    ENDCASE
    _AAPI-P @ AAP-VALID? IF AAP-S-OK ELSE AAP-S-INVALID THEN ;
