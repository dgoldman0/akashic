\ =====================================================================
\  akashic/tui/game/input.f — Rebindable Game Input Mapping
\ =====================================================================
\
\  Translates raw key events into abstract game actions.  Supports
\  multiple keys per action and edge detection (pressed-this-frame
\  vs held).
\
\  Actions are small integers (0..63).  Each action can have up to 4
\  bound keys.  The input system maintains a "down" bitmap and a
\  "pressed" bitmap that is cleared each frame.
\
\  Usage:
\    KEY-UP   ACT-UP   GACT-BIND
\    [CHAR] k ACT-UP   GACT-BIND
\    ...
\    : my-input  ( ev -- )  GACT-FEED ;
\    ['] my-input GAME-ON-INPUT
\    ...
\    ACT-UP GACT-DOWN? IF ... THEN
\
\  Public API:
\    GACT-BIND       ( key action -- )   Bind key to action
\    GACT-UNBIND-ALL ( action -- )       Remove all bindings
\    GACT-FEED       ( ev -- )           Feed a key event (call from input cb)
\    GACT-FRAME-RESET ( -- )             Clear per-frame pressed state
\    GACT-DOWN?      ( action -- flag )  Is action held down?
\    GACT-PRESSED?   ( action -- flag )  Was action newly pressed this frame?
\    GACT-RELEASED?  ( action -- flag )  Was action released this frame?
\    GACT-CLEAR      ( -- )              Reset all state
\
\  Prefix: GACT- (public), _GACT- (internal)
\  Provider: akashic-tui-game-input
\  Dependencies: keys.f

PROVIDED akashic-tui-game-input

REQUIRE ../tui/keys.f

\ =====================================================================
\  §1 — Constants & Storage
\ =====================================================================

64 CONSTANT _GACT-MAX           \ Maximum number of actions
 4 CONSTANT _GACT-KEYS-PER      \ Max bindings per action

\ Binding table: _GACT-MAX × _GACT-KEYS-PER cells
\ Each cell holds a key code (0 = unbound).
\ For KEY-T-CHAR keys, the code is the character value.
\ For KEY-T-SPECIAL keys, the code is KEY-xxx OR'd with 0x10000
\ to distinguish from characters.
CREATE _GACT-BINDS  _GACT-MAX _GACT-KEYS-PER * CELLS ALLOT

\ Bitmaps — one bit per action (64 bits = 8 bytes each)
CREATE _GACT-DOWN     8 ALLOT   \ Currently held
CREATE _GACT-PRESSED  8 ALLOT   \ Newly pressed this frame
CREATE _GACT-RELEASED 8 ALLOT   \ Released this frame

\ Temporary
VARIABLE _GACT-TMP

\ =====================================================================
\  §2 — Bitmap Helpers
\ =====================================================================

\ _GACT-BIT-SET ( bitmap action -- )
: _GACT-BIT-SET  ( bitmap action -- )
    DUP 3 RSHIFT             ( bitmap action byte-idx )
    ROT +                    ( action addr )
    SWAP 7 AND               ( addr bit-idx )
    1 SWAP LSHIFT            ( addr mask )
    OVER C@ OR  SWAP C! ;

\ _GACT-BIT-CLR ( bitmap action -- )
: _GACT-BIT-CLR  ( bitmap action -- )
    DUP 3 RSHIFT
    ROT +
    SWAP 7 AND
    1 SWAP LSHIFT INVERT
    OVER C@ AND  SWAP C! ;

\ _GACT-BIT? ( bitmap action -- flag )
: _GACT-BIT?  ( bitmap action -- flag )
    DUP 3 RSHIFT
    ROT +  C@
    SWAP 7 AND
    RSHIFT  1 AND  0<> ;

\ =====================================================================
\  §3 — Binding Management
\ =====================================================================

\ _GACT-BIND-ADDR ( action slot -- addr )
\   Address of binding slot for an action.
: _GACT-BIND-ADDR  ( action slot -- addr )
    SWAP _GACT-KEYS-PER * +  CELLS _GACT-BINDS + ;

\ GACT-BIND ( key action -- )
\   Bind a key to an action.  Finds the first empty slot.
\   If all 4 slots are full, silently drops.
: GACT-BIND  ( key action -- )
    _GACT-KEYS-PER 0 DO
        DUP I _GACT-BIND-ADDR @  0= IF
            I _GACT-BIND-ADDR        ( key addr )
            SWAP OVER !              ( addr )
            DROP UNLOOP EXIT
        THEN
    LOOP
    2DROP ;

\ GACT-UNBIND-ALL ( action -- )
\   Remove all bindings for an action.
: GACT-UNBIND-ALL  ( action -- )
    _GACT-KEYS-PER 0 DO
        DUP I _GACT-BIND-ADDR  0 SWAP !
    LOOP
    DROP ;

\ =====================================================================
\  §4 — Key-to-Action Lookup
\ =====================================================================

\ _GACT-ENCODE-KEY ( ev -- encoded-key )
\   Encode a key event into the format used in the binding table.
\   CHAR events: code is the character.
\   SPECIAL events: code OR'd with 0x10000.
: _GACT-ENCODE-KEY  ( ev -- encoded-key )
    DUP @ KEY-T-CHAR = IF
        8 + @ EXIT
    THEN
    DUP @ KEY-T-SPECIAL = IF
        8 + @ 0x10000 OR EXIT
    THEN
    DROP 0 ;

\ _GACT-FIND-ACTION ( encoded-key -- action | -1 )
\   Search the binding table for a key.  Returns action ID or -1.
: _GACT-FIND-ACTION  ( encoded-key -- action | -1 )
    _GACT-MAX 0 DO
        _GACT-KEYS-PER 0 DO
            DUP  J I _GACT-BIND-ADDR @ = IF
                DROP J UNLOOP UNLOOP EXIT
            THEN
        LOOP
    LOOP
    DROP -1 ;

\ =====================================================================
\  §5 — Event Processing
\ =====================================================================

\ GACT-FEED ( ev -- )
\   Process a key event.  Updates down/pressed/released bitmaps.
\   Call this from your GAME-ON-INPUT callback.
: GACT-FEED  ( ev -- )
    DUP _GACT-ENCODE-KEY          ( ev encoded )
    DUP 0= IF 2DROP EXIT THEN
    SWAP @ KEY-T-CHAR = IF
        \ CHAR events are press-only (terminals don't report key-up)
        DUP _GACT-FIND-ACTION     ( encoded action )
        DUP -1 = IF 2DROP EXIT THEN
        NIP                       ( action )
        DUP _GACT-DOWN SWAP _GACT-BIT? 0= IF
            \ Newly pressed
            DUP _GACT-DOWN SWAP _GACT-BIT-SET
            _GACT-PRESSED SWAP _GACT-BIT-SET
        ELSE
            DROP
        THEN
        EXIT
    THEN
    \ SPECIAL events: same treatment (no key-up in terminal)
    _GACT-FIND-ACTION             ( action )
    DUP -1 = IF DROP EXIT THEN
    DUP _GACT-DOWN SWAP _GACT-BIT? 0= IF
        DUP _GACT-DOWN SWAP _GACT-BIT-SET
        _GACT-PRESSED SWAP _GACT-BIT-SET
    ELSE
        DROP
    THEN ;

\ GACT-FRAME-RESET ( -- )
\   Clear per-frame bitmaps.  Call at the START of each frame
\   (before GACT-FEED).  Also clears all "down" state since
\   terminals don't report key-up — every press is a one-frame event.
: GACT-FRAME-RESET  ( -- )
    _GACT-DOWN     8 0 FILL
    _GACT-PRESSED  8 0 FILL
    _GACT-RELEASED 8 0 FILL ;

\ =====================================================================
\  §6 — Query
\ =====================================================================

\ GACT-DOWN? ( action -- flag )
: GACT-DOWN?  ( action -- flag )
    _GACT-DOWN SWAP _GACT-BIT? ;

\ GACT-PRESSED? ( action -- flag )
: GACT-PRESSED?  ( action -- flag )
    _GACT-PRESSED SWAP _GACT-BIT? ;

\ GACT-RELEASED? ( action -- flag )
: GACT-RELEASED?  ( action -- flag )
    _GACT-RELEASED SWAP _GACT-BIT? ;

\ =====================================================================
\  §7 — Reset
\ =====================================================================

\ GACT-CLEAR ( -- )
\   Reset all bindings and state.
: GACT-CLEAR  ( -- )
    _GACT-BINDS  _GACT-MAX _GACT-KEYS-PER * CELLS  0 FILL
    _GACT-DOWN     8 0 FILL
    _GACT-PRESSED  8 0 FILL
    _GACT-RELEASED 8 0 FILL ;

\ Initialize
GACT-CLEAR

\ =====================================================================
\  §8 — Common Action Constants
\ =====================================================================
\  Games can define their own, but these are conventional defaults.

 0 CONSTANT ACT-UP
 1 CONSTANT ACT-DOWN
 2 CONSTANT ACT-LEFT
 3 CONSTANT ACT-RIGHT
 4 CONSTANT ACT-ACTION1      \ Primary action (Enter, Space, Z)
 5 CONSTANT ACT-ACTION2      \ Secondary action (X, Shift)
 6 CONSTANT ACT-CANCEL       \ Cancel / back (Escape)
 7 CONSTANT ACT-MENU         \ Open menu
 8 CONSTANT ACT-INVENTORY    \ Toggle inventory
 9 CONSTANT ACT-PAUSE        \ Pause game

\ =====================================================================
\  §9 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _gact-guard

' GACT-BIND        CONSTANT _gact-bind-xt
' GACT-UNBIND-ALL  CONSTANT _gact-unbind-all-xt
' GACT-FEED        CONSTANT _gact-feed-xt
' GACT-FRAME-RESET CONSTANT _gact-frame-reset-xt
' GACT-CLEAR       CONSTANT _gact-clear-xt

: GACT-BIND        _gact-bind-xt        _gact-guard WITH-GUARD ;
: GACT-UNBIND-ALL  _gact-unbind-all-xt  _gact-guard WITH-GUARD ;
: GACT-FEED        _gact-feed-xt        _gact-guard WITH-GUARD ;
: GACT-FRAME-RESET _gact-frame-reset-xt _gact-guard WITH-GUARD ;
: GACT-CLEAR       _gact-clear-xt       _gact-guard WITH-GUARD ;
[THEN] [THEN]
