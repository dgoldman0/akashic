\ =================================================================
\  app-shell.f — Applet Host Runtime
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ASHELL- / _ASHELL-
\  Depends on: akashic-tui-term-init, akashic-tui-keys,
\              akashic-tui-screen, akashic-tui-region,
\              akashic-tui-draw, akashic-tui-uidl-tui,
\              akashic-tui-focus
\
\  Runtime host for APPLETS (app-desc.f descriptors).  Owns the
\  terminal, event loop, paint cycle, and UIDL integration.
\  Applets provide passive callbacks; the shell drives everything.
\
\  This is the applet-side counterpart to app.f (standalone apps).
\  Standalone apps own their own terminal via app.f → APP-RUN.
\  Applets are hosted here — one at a time via ASHELL-RUN, or
\  many at a time via desk.f which is itself an applet.
\
\  Both paths share terminal primitives from term-init.f
\  (APP-INIT / APP-SHUTDOWN / APP-TITLE!), but this file does
\  NOT depend on app.f.
\
\  Lifecycle:
\    1. Terminal init (APP-INIT)
\    2. Root region created
\    3. UIDL document loaded (if provided)
\    4. App init callback
\    5. Initial paint + flush
\    6. Non-blocking event loop:
\       a. KEY-POLL → app event → UIDL dispatch
\       b. Drain deferred actions
\       c. Timer tick → app tick
\       d. Paint: UTUI-PAINT + app paint → SCR-FLUSH
\       e. YIELD?
\    7. App shutdown callback
\    8. UIDL detach + APP-SHUTDOWN
\
\  Public API:
\    ASHELL-RUN       ( desc -- )      Main entry (blocks until quit)
\    ASHELL-QUIT      ( -- )           Signal event loop to exit
\    ASHELL-DIRTY!    ( -- )           Request repaint next frame
\    ASHELL-REGION    ( -- rgn )       Root region
\    ASHELL-TICK-MS!  ( ms -- )        Set tick interval (default 50)
\    ASHELL-POST      ( xt -- )        Enqueue deferred action
\    ASHELL-UIDL?     ( -- flag )      Is a UIDL document loaded?
\    ASHELL-DESC      ( -- desc )      Current app descriptor
\    ASHELL-REQUEST-CLOSE ( reason -- decision )  Negotiate a close
\
\  The shell guarantees APP-SHUTDOWN runs even on THROW.
\ =================================================================

PROVIDED akashic-tui-app-shell

REQUIRE cogs/term-init.f
REQUIRE keys.f
REQUIRE screen.f
REQUIRE region.f
REQUIRE draw.f
REQUIRE focus.f
REQUIRE uidl-tui.f
REQUIRE ../utils/term.f
REQUIRE app-desc.f
REQUIRE ../utils/fs/drivers/vfs-mp64fs.f

\ =====================================================================
\  §1 — Context Switch & Child Painting  (browser API)
\ =====================================================================
\
\  UCTX-ALLOC / UCTX-FREE / UCTX-SAVE / UCTX-RESTORE / UCTX-CLEAR
\  are defined in uidl-tui.f §18b (which owns the private variables
\  they serialise).  The shell uses only the public API.

VARIABLE _ASHELL-ACTIVE-CTX   \ currently active UCTX buffer (0 = none)
0 _ASHELL-ACTIVE-CTX !

\ ASHELL-CTX-SWITCH ( uctx -- )
\   Save the current UIDL context (if any), then restore the given
\   context.  Pass 0 to deactivate without loading a new context.
: ASHELL-CTX-SWITCH  ( uctx -- )
    DUP _ASHELL-ACTIVE-CTX @ = IF DROP EXIT THEN
    _ASHELL-ACTIVE-CTX @ ?DUP IF UCTX-SAVE THEN
    DUP ?DUP IF UCTX-RESTORE THEN
    _ASHELL-ACTIVE-CTX ! ;

\ ASHELL-CTX-SAVE ( uctx -- )
\   Force-save the current globals into uctx.  Used when a sub-app
\   event handler has mutated state and the caller wants to persist
\   the changes before returning (no switch happens).
: ASHELL-CTX-SAVE  ( uctx -- )
    ?DUP IF UCTX-SAVE THEN ;

\ ASHELL-PAINT-CHILD ( uctx rgn has-uidl desc instance -- )
\   The browser's per-child paint primitive.  Context-switches to
\   uctx, sets the region, calls UTUI-PAINT (if has-uidl), then
\   calls the app descriptor's paint callback (if any).
VARIABLE _ASPC-HAS-UIDL
VARIABLE _ASPC-DESC
VARIABLE _ASPC-INST

: ASHELL-PAINT-CHILD  ( uctx rgn has-uidl desc instance -- )
    _ASPC-INST ! _ASPC-DESC ! _ASPC-HAS-UIDL !
    SWAP ASHELL-CTX-SWITCH
    ?DUP IF RGN-USE THEN
    _ASPC-DESC @ APP.ACTIVATE-XT @ ?DUP IF
        _ASPC-INST @ SWAP EXECUTE
    THEN
    _ASPC-HAS-UIDL @ IF UTUI-PAINT THEN
    _ASPC-DESC @ APP.PAINT-XT @ ?DUP IF
        _ASPC-INST @ SWAP EXECUTE
    THEN ;

\ =====================================================================
\  §2 — Shell State
\ =====================================================================

VARIABLE _ASHELL-RGN          \ Root region (0 = not created)
0 _ASHELL-RGN !

VARIABLE _ASHELL-VFS          \ Shared VFS instance (0 = not yet created)
0 _ASHELL-VFS !

VARIABLE _ASHELL-DESC         \ Current app descriptor (0 = not running)
0 _ASHELL-DESC !

VARIABLE _ASHELL-INST         \ Current component instance
0 _ASHELL-INST !

VARIABLE _ASHELL-RUNNING      \ Event loop active flag
0 _ASHELL-RUNNING !

VARIABLE _ASHELL-DIRTY        \ Repaint requested flag
0 _ASHELL-DIRTY !

VARIABLE _ASHELL-HAS-UIDL     \ UIDL document loaded flag
0 _ASHELL-HAS-UIDL !

VARIABLE _ASHELL-UIDL-BUF     \ Shell-loaded UIDL file buffer (0 = not ours)
0 _ASHELL-UIDL-BUF !

VARIABLE _ASHELL-TICK-MS      \ Tick interval in milliseconds
50 _ASHELL-TICK-MS !

VARIABLE _ASHELL-LAST-TICK    \ MS@ snapshot of last tick
0 _ASHELL-LAST-TICK !

\ --- Toast state ---
CREATE _ASHELL-TOAST-MSG  2 CELLS ALLOT   \ addr + len
0 _ASHELL-TOAST-MSG !
0 _ASHELL-TOAST-MSG CELL+ !

VARIABLE _ASHELL-TOAST-EXPIRY             \ MS@ deadline
0 _ASHELL-TOAST-EXPIRY !

VARIABLE _ASHELL-TOAST-WAS-VIS            \ was-visible flag
0 _ASHELL-TOAST-WAS-VIS !

\ --- Shell cursor state ---
\  A keyboard-driven pointer activated by Alt+Arrow.
\  Visible only while Alt-modified keys are being pressed.
VARIABLE _ASHELL-CUR-ROW
VARIABLE _ASHELL-CUR-COL
VARIABLE _ASHELL-CUR-VIS        \ 0 = hidden, -1 = visible
VARIABLE _ASHELL-CUR-SAVED      \ back-buffer cell saved before draw
VARIABLE _ASHELL-CUR-SROW       \ row where we saved from
VARIABLE _ASHELL-CUR-SCOL       \ col where we saved from
VARIABLE _ASHELL-CUR-ACTIVE     \ -1 if a saved cell needs restoring

0 _ASHELL-CUR-ROW !
0 _ASHELL-CUR-COL !
0 _ASHELL-CUR-VIS !
0 _ASHELL-CUR-ACTIVE !

\ Button constants for ASHELL-CUR-CLICK / UTUI-DISPATCH-MOUSE
0 CONSTANT ASHELL-BTN-LEFT
1 CONSTANT ASHELL-BTN-MIDDLE
2 CONSTANT ASHELL-BTN-RIGHT

\ =====================================================================
\  §3 — Deferred Action Queue (FIFO, max 16 entries)
\ =====================================================================

16 CONSTANT _ASHELL-POST-MAX

CREATE _ASHELL-POST-Q  _ASHELL-POST-MAX CELLS ALLOT

VARIABLE _ASHELL-POST-HEAD
0 _ASHELL-POST-HEAD !

VARIABLE _ASHELL-POST-TAIL
0 _ASHELL-POST-TAIL !

: ASHELL-POST  ( xt -- )
    _ASHELL-POST-HEAD @ _ASHELL-POST-TAIL @ -
    _ASHELL-POST-MAX >= IF DROP EXIT THEN
    _ASHELL-POST-HEAD @
    _ASHELL-POST-MAX MOD CELLS _ASHELL-POST-Q + !
    1 _ASHELL-POST-HEAD +! ;

: _ASHELL-DRAIN-POSTED  ( -- )
    BEGIN
        _ASHELL-POST-TAIL @ _ASHELL-POST-HEAD @ <
        _ASHELL-RUNNING @ AND
    WHILE
        _ASHELL-POST-TAIL @
        _ASHELL-POST-MAX MOD CELLS _ASHELL-POST-Q + @
        1 _ASHELL-POST-TAIL +!
        EXECUTE
    REPEAT ;

\ =====================================================================
\  §4 — Public Accessors
\ =====================================================================

\ ASHELL-QUIT ( -- )
\   Idempotent aligned stop signal.  It does not provide a general
\   cross-core synchronization boundary; lifecycle ownership and result
\   publication remain the host's responsibility.
: ASHELL-QUIT  ( -- )
    0 _ASHELL-RUNNING ! ;

\ ASHELL-QUIT-PENDING? ( -- flag )
\   True if a sub-app has called ASHELL-QUIT but the host hasn't
\   processed it yet.
: ASHELL-QUIT-PENDING?  ( -- flag )
    _ASHELL-RUNNING @ 0= ;

\ ASHELL-CANCEL-QUIT ( -- )
\   Owner-lifecycle inverse of ASHELL-QUIT: cancel a pending quit and
\   re-arm the event loop.  It is likewise only an aligned signal store,
\   not a cross-core synchronization primitive.  Used by Desk to intercept
\   sub-app ASHELL-QUIT and close only that slot.
: ASHELL-CANCEL-QUIT  ( -- )
    -1 _ASHELL-RUNNING ! ;

VARIABLE _ASHELL-CLOSE-REASON

: _ASHELL-CALL-REQUEST-CLOSE  ( -- decision )
    _ASHELL-DESC @ APP.REQUEST-CLOSE-XT @ ?DUP 0= IF
        APP-CLOSE-D-ALLOW EXIT
    THEN
    _ASHELL-CLOSE-REASON @ _ASHELL-INST @ ROT EXECUTE ;

\ ASHELL-REQUEST-CLOSE ( reason -- decision )
\   Ask the current app whether a normal close may proceed.  Missing
\   callbacks allow.  A THROW or an invalid decision fails closed.
: ASHELL-REQUEST-CLOSE  ( reason -- decision )
    _ASHELL-CLOSE-REASON !
    ['] _ASHELL-CALL-REQUEST-CLOSE CATCH ?DUP IF
        DROP APP-CLOSE-D-CANCEL EXIT
    THEN
    DUP APP-CLOSE-DECISION-VALID? 0= IF
        DROP APP-CLOSE-D-CANCEL
    THEN ;

\ ASHELL-DIRTY! ( -- )
\   Mark the screen as needing repaint.
: ASHELL-DIRTY!  ( -- )
    -1 _ASHELL-DIRTY ! ;

\ ASHELL-REGION ( -- rgn )
\   The root region that covers the full screen.
: ASHELL-REGION  ( -- rgn )
    _ASHELL-RGN @ ;

\ --- Mouse event helpers ---
\ Extract fields from a synthetic mouse event (type=KEY-T-MOUSE).
: ASHELL-MOUSE-ROW  ( ev -- row )  16 + @ 16 RSHIFT ;
: ASHELL-MOUSE-COL  ( ev -- col )  16 + @ 0xFFFF AND ;
: ASHELL-MOUSE-BTN  ( ev -- btn )  8 + @ ;
: ASHELL-MOUSE?     ( ev -- flag ) @ KEY-T-MOUSE = ;

\ ASHELL-LOAD-UIDL ( path-a path-u rgn -- buf | 0 )
\   Open a VFS file, read its contents into an XMEM buffer, then
\   feed the content to UTUI-LOAD.  Returns the buffer address
\   (caller must XMEM-FREE-BLOCK with _ASHELL-UIDL-FILE-MAX) or 0
\   on failure.
8192 CONSTANT _ASHELL-UIDL-FILE-MAX

VARIABLE _ALUF-RGN
VARIABLE _ALUF-FD
VARIABLE _ALUF-BUF

: ASHELL-LOAD-UIDL  ( path-a path-u rgn -- buf | 0 )
    _ALUF-RGN !
    VFS-OPEN                          ( fd | 0 )
    DUP 0= IF EXIT THEN
    _ALUF-FD !
    _ASHELL-UIDL-FILE-MAX XMEM-ALLOT? IF
        _ALUF-FD @ VFS-CLOSE  0 EXIT
    THEN
    _ALUF-BUF !
    \ Read file into buffer
    _ALUF-BUF @  _ASHELL-UIDL-FILE-MAX  _ALUF-FD @ VFS-READ  ( actual )
    _ALUF-FD @ VFS-CLOSE
    \ Feed to UTUI-LOAD
    _ALUF-BUF @ SWAP  _ALUF-RGN @    ( buf-a actual rgn )
    UTUI-LOAD DROP
    _ALUF-BUF @ ;

\ ASHELL-TICK-MS! ( ms -- )
\   Set the tick callback interval.
: ASHELL-TICK-MS!  ( ms -- )
    _ASHELL-TICK-MS ! ;

\ ASHELL-UIDL? ( -- flag )
\   True if a UIDL document is currently loaded.
: ASHELL-UIDL?  ( -- flag )
    _ASHELL-HAS-UIDL @ ;

\ ASHELL-DESC ( -- desc )
\   The currently running app descriptor (0 if not running).
: ASHELL-DESC  ( -- desc )
    _ASHELL-DESC @ ;

: ASHELL-INSTANCE  ( -- instance )
    _ASHELL-INST @ ;

: _ASHELL-ACTIVATE  ( -- )
    _ASHELL-DESC @ ?DUP IF
        APP.ACTIVATE-XT @ ?DUP IF _ASHELL-INST @ SWAP EXECUTE THEN
    THEN ;

\ ASHELL-TOAST-VISIBLE? ( -- flag )
\   True if toast message is currently showing.
: ASHELL-TOAST-VISIBLE?  ( -- flag )
    \ Avoid an eight-byte RTC read on every event-loop and paint pass
    \ when no toast is active.  _ASHELL-TOAST-WAS-VIS is set together
    \ with the deadline by ASHELL-TOAST and cleared by the expiry path.
    _ASHELL-TOAST-WAS-VIS @ 0= IF 0 EXIT THEN
    _ASHELL-TOAST-EXPIRY @ MS@ > ;

: _ASHELL-DIRTY-TOAST-RECT  ( -- )
    _ASHELL-HAS-UIDL @ 0= IF EXIT THEN
    _ASHELL-TOAST-MSG 2@ NIP 4 + >R
    SCR-H 1-
    SCR-W R@ - 2 /
    1 R>
    _UTUI-DIRTY-RECT-D ;

\ ASHELL-TOAST ( addr u ms -- )
\   Show a toast message for ms milliseconds.
: ASHELL-TOAST  ( addr u ms -- )
    _ASHELL-TOAST-WAS-VIS @ IF _ASHELL-DIRTY-TOAST-RECT THEN
    MS@ + _ASHELL-TOAST-EXPIRY !
    _ASHELL-TOAST-MSG 2!
    -1 _ASHELL-TOAST-WAS-VIS !
    ASHELL-DIRTY! ;

\ _ASHELL-DRAW-TOAST ( -- )
\   Render toast overlay centred on bottom row.
: _ASHELL-DRAW-TOAST  ( -- )
    RGN-ROOT
    253 DRW-FG!  236 DRW-BG!  0 DRW-ATTR!
    _ASHELL-TOAST-MSG 2@               ( a u )
    DUP 4 +                            ( a u tw )
    \ Fill background bar:  ( cp row col h w -- )
    32
    SCR-H 1-
    SCR-W 3 PICK - 2/                 ( a u tw 32 row col )
    1  4 PICK
    DRW-FILL-RECT                      ( a u tw )
    \ Centre text:  ( addr len row col w -- )
    SCR-H 1-
    SCR-W 2 PICK - 2/                 ( a u tw row col )
    ROT                                ( a u row col tw )
    DRW-TEXT-CENTER
    DRW-STYLE-RESET ;

\ =====================================================================
\  §5 — Key Event Buffer
\ =====================================================================

CREATE _ASHELL-EV  24 ALLOT     \ 3-cell key event descriptor

\ =====================================================================
\  §5b — Shell Cursor (keyboard-driven pointer)
\ =====================================================================
\
\  Alt+Arrow moves a one-cell cursor (⊹ U+22B9).  Visible only while
\  Alt-modified keys are pressed — any non-Alt key hides it.
\  Alt+Del/End/PgDn synthesise left/middle/right clicks via
\  UTUI-DISPATCH-MOUSE (or the app's event handler for routing).

\ _ASHELL-CUR-CLAMP ( -- )
\   Clamp cursor position to valid screen coordinates.
: _ASHELL-CUR-CLAMP  ( -- )
    _ASHELL-CUR-ROW @ 0 MAX SCR-H 1- MIN _ASHELL-CUR-ROW !
    _ASHELL-CUR-COL @ 0 MAX SCR-W 1- MIN _ASHELL-CUR-COL ! ;

\ _ASHELL-CUR-INIT ( -- )
\   Centre the cursor on the screen.
: _ASHELL-CUR-INIT  ( -- )
    SCR-H 2/ _ASHELL-CUR-ROW !
    SCR-W 2/ _ASHELL-CUR-COL !
    0 _ASHELL-CUR-VIS ! ;

\ Forward reference — resolved in §7 after _ASHELL-DISPATCH-MOUSE
\   is defined.
DEFER _ASHELL-DISPATCH-MOUSE

\ _ASHELL-CUR-MOVE ( drow dcol -- )
\   Shift cursor position by delta, clamp, show, and dirty.
: _ASHELL-CUR-MOVE  ( drow dcol -- )
    _ASHELL-CUR-COL +!
    _ASHELL-CUR-ROW +!
    _ASHELL-CUR-CLAMP
    -1 _ASHELL-CUR-VIS !
    ASHELL-DIRTY! ;

\ ASHELL-CUR-CLICK ( btn -- )
\   Synthesise a click at the cursor position.  Builds a synthetic
\   mouse event (type=KEY-T-MOUSE, code=btn, mods=row<<16|col) and
\   routes it through the normal dispatch chain.  This way the app's
\   EVENT-XT (e.g. DESK-EVENT-CB) sees it and can do tile routing.
\   If the app doesn't consume it, UIDL mouse dispatch runs.
: ASHELL-CUR-CLICK  ( btn -- )
    \ Build synthetic mouse event in _ASHELL-EV
    KEY-T-MOUSE _ASHELL-EV !           \ type = mouse
    _ASHELL-EV 8 + !                   \ code = btn
    _ASHELL-CUR-ROW @ 16 LSHIFT
    _ASHELL-CUR-COL @ OR
    _ASHELL-EV 16 + !                  \ mods = row<<16 | col
    _ASHELL-EV _ASHELL-DISPATCH-MOUSE ;

\ _ASHELL-CUR-KEY? ( ev -- flag )
\   Check if the event is an Alt+Arrow/Alt+Del/Alt+End/Alt+PgDn.
\   If so, handle it and return TRUE.  Otherwise return FALSE.
VARIABLE _ACK-CODE    VARIABLE _ACK-MODS

: _ASHELL-CUR-KEY?  ( ev -- flag )
    DUP @ KEY-T-SPECIAL <> IF DROP 0 EXIT THEN
    DUP 16 + @ _ACK-MODS !
    8 + @ _ACK-CODE !
    _ACK-MODS @ KEY-MOD-ALT AND 0= IF 0 EXIT THEN
    \ Alt+Arrow → move
    _ACK-CODE @
    DUP KEY-UP    = IF DROP -1  0 _ASHELL-CUR-MOVE -1 EXIT THEN
    DUP KEY-DOWN  = IF DROP  1  0 _ASHELL-CUR-MOVE -1 EXIT THEN
    DUP KEY-LEFT  = IF DROP  0 -1 _ASHELL-CUR-MOVE -1 EXIT THEN
    DUP KEY-RIGHT = IF DROP  0  1 _ASHELL-CUR-MOVE -1 EXIT THEN
    \ Alt+Del → left click
    DUP KEY-DEL   = IF DROP ASHELL-BTN-LEFT   ASHELL-CUR-CLICK -1 EXIT THEN
    \ Alt+End → middle click
    DUP KEY-END   = IF DROP ASHELL-BTN-MIDDLE ASHELL-CUR-CLICK -1 EXIT THEN
    \ Alt+PgDn → right click
    DUP KEY-PGDN  = IF DROP ASHELL-BTN-RIGHT  ASHELL-CUR-CLICK -1 EXIT THEN
    DROP 0 ;

\ _ASHELL-CUR-RESTORE ( -- )
\   If we previously overwrote a cell with the cursor glyph,
\   put the original content back into the back buffer.
: _ASHELL-CUR-RESTORE  ( -- )
    _ASHELL-CUR-ACTIVE @ 0= IF EXIT THEN
    _ASHELL-CUR-SAVED @
    _ASHELL-CUR-SROW @
    _ASHELL-CUR-SCOL @
    SCR-SET
    0 _ASHELL-CUR-ACTIVE ! ;

\ _ASHELL-DRAW-CURSOR ( -- )
\   Save the cell underneath, then draw cursor glyph ⊹ (U+22B9).
\   The saved cell is restored at the start of the next paint
\   via _ASHELL-CUR-RESTORE so the cursor never corrupts content.
: _ASHELL-DRAW-CURSOR  ( -- )
    RGN-ROOT
    \ Save the cell currently at the cursor position
    _ASHELL-CUR-ROW @ _ASHELL-CUR-COL @ SCR-GET
    _ASHELL-CUR-SAVED !
    _ASHELL-CUR-ROW @ _ASHELL-CUR-SROW !
    _ASHELL-CUR-COL @ _ASHELL-CUR-SCOL !
    -1 _ASHELL-CUR-ACTIVE !
    \ Draw the cursor glyph on top
    15 DRW-FG!  0 DRW-BG!  1 DRW-ATTR!   \ bright white, bold
    0x22B9
    _ASHELL-CUR-ROW @
    _ASHELL-CUR-COL @
    DRW-CHAR
    DRW-STYLE-RESET ;

\ =====================================================================
\  §6 — Resize Handling
\ =====================================================================

: _ASHELL-ON-RESIZE  ( w h -- )
    SCR-RESIZE
    \ Rebuild root region from new screen dimensions
    _ASHELL-RGN @ ?DUP IF RGN-FREE THEN
    0 0 SCR-H SCR-W RGN-NEW _ASHELL-RGN !
    \ Clamp cursor to new dimensions
    _ASHELL-CUR-CLAMP
    \ Re-layout UIDL tree if loaded
    _ASHELL-HAS-UIDL @ IF
        UTUI-RELAYOUT
    THEN
    ASHELL-DIRTY! ;

\ =====================================================================
\  §7 — Event Dispatch
\ =====================================================================

\ _ASHELL-DISPATCH-KEY ( ev -- )
\   Route a key event through cursor handling, then the app's handler,
\   then UIDL dispatch.
: _ASHELL-DISPATCH-KEY  ( ev -- )
    \ 0. Shell cursor intercepts Alt+Arrow / Alt+Click keys first
    DUP _ASHELL-CUR-KEY? IF DROP EXIT THEN
    \ Any non-cursor key hides the cursor (Alt was not an arrow/click)
    _ASHELL-CUR-VIS @ IF
        0 _ASHELL-CUR-VIS !
        ASHELL-DIRTY!
    THEN
    _ASHELL-ACTIVATE
    \ 1. App's event handler gets first crack
    _ASHELL-DESC @ APP.EVENT-XT @ ?DUP IF
        OVER _ASHELL-INST @ ROT EXECUTE  ( ev consumed? )
        IF DROP ASHELL-DIRTY! EXIT THEN
    THEN
    \ 2. UIDL dispatch (shortcuts, focused element)
    _ASHELL-HAS-UIDL @ IF
        DUP UTUI-DISPATCH-KEY        ( ev consumed? )
        IF ASHELL-DIRTY! THEN
    THEN
    DROP ;

\ _ASHELL-DISPATCH-MOUSE-IMPL ( ev -- )
\   Route a mouse event through the app's handler, then UIDL dispatch.
\   ev layout: +0=KEY-T-MOUSE, +8=btn, +16=row<<16|col
: _ASHELL-DISPATCH-MOUSE-IMPL  ( ev -- )
    _ASHELL-ACTIVATE
    \ 1. App's event handler gets first crack
    _ASHELL-DESC @ APP.EVENT-XT @ ?DUP IF
        OVER _ASHELL-INST @ ROT EXECUTE  ( ev consumed? )
        IF DROP ASHELL-DIRTY! EXIT THEN
    THEN
    \ 2. UIDL mouse dispatch
    _ASHELL-HAS-UIDL @ IF
        DUP 16 + @ DUP 16 RSHIFT SWAP 0xFFFF AND   ( ev row col )
        2 PICK 8 + @                                 ( ev row col btn )
        UTUI-DISPATCH-MOUSE          ( ev handled? )
        IF ASHELL-DIRTY! THEN
    THEN
    DROP ;
' _ASHELL-DISPATCH-MOUSE-IMPL IS _ASHELL-DISPATCH-MOUSE

\ _ASHELL-CHECK-RESIZE ( ev -- )
\   If the event is a resize, handle it.
: _ASHELL-CHECK-RESIZE  ( ev -- )
    DUP @ KEY-T-RESIZE = IF
        DUP 8 + @                    \ width  (code field)
        OVER 16 + @                   \ height (mods field)
        _ASHELL-ON-RESIZE
    THEN
    DROP ;

\ _ASHELL-CHECK-HW-RESIZE ( -- )
\   Poll hardware RESIZED? flag.
: _ASHELL-CHECK-HW-RESIZE  ( -- )
    TERM-RESIZED? IF
        TERM-SIZE _ASHELL-ON-RESIZE
    THEN ;

\ =====================================================================
\  §8 — Timer Tick
\ =====================================================================

VARIABLE _ASHELL-TICK-TMP

: _ASHELL-CHECK-TICK  ( -- )
    _ASHELL-DESC @ APP.TICK-XT @ IF
        MS@ _ASHELL-TICK-TMP !
        _ASHELL-TICK-TMP @ _ASHELL-LAST-TICK @ -
        _ASHELL-TICK-MS @ >= IF
            _ASHELL-TICK-TMP @ _ASHELL-LAST-TICK !
            _ASHELL-ACTIVATE
            _ASHELL-INST @ _ASHELL-DESC @ APP.TICK-XT @ EXECUTE
            \ If tick caused any UIDL/widget changes, auto-dirty
            _UTUI-NEEDS-PAINT @ IF
                0 _UTUI-NEEDS-PAINT !
                ASHELL-DIRTY!
            THEN
        THEN
    THEN
    \ Toast expiry: if toast just expired, trigger repaint to clear it
    ASHELL-TOAST-VISIBLE? 0= IF
        _ASHELL-TOAST-WAS-VIS @ IF
            _ASHELL-DIRTY-TOAST-RECT
            0 _ASHELL-TOAST-WAS-VIS !
            ASHELL-DIRTY!
        THEN
    THEN ;

\ =====================================================================
\  §9 — Paint
\ =====================================================================

: _ASHELL-PAINT  ( -- )
    \ Check UIDL needs-paint flag (set by UIDL-DIRTY! hook)
    _UTUI-NEEDS-PAINT @ IF
        0 _UTUI-NEEDS-PAINT !
        ASHELL-DIRTY!
    THEN
    _ASHELL-DIRTY @ 0= IF EXIT THEN
    0 _ASHELL-DIRTY !
    \ Restore the cell that the cursor glyph overwrote last frame
    _ASHELL-CUR-RESTORE
    _ASHELL-ACTIVATE
    RGN-ROOT
    \ UIDL elements first (they own the background/structure)
    _ASHELL-HAS-UIDL @ IF
        UTUI-PAINT
    THEN
    \ App's custom widget painting (on top of UIDL)
    _ASHELL-DESC @ APP.PAINT-XT @ ?DUP IF
        _ASHELL-INST @ SWAP EXECUTE
    THEN
    \ Toast overlay (drawn last, on top of everything)
    ASHELL-TOAST-VISIBLE? IF
        _ASHELL-DRAW-TOAST
    THEN
    \ Shell cursor (drawn above toast)
    _ASHELL-CUR-VIS @ IF
        _ASHELL-DRAW-CURSOR
    THEN
    RGN-ROOT
    SCR-FLUSH ;

\ =====================================================================
\  §10 — Lifecycle: Init
\ =====================================================================

\ _ASHELL-VFS-INIT ( -- )
\   Lazy-create a shared VFS backed by the MP64FS boot disk.
\   Safe to call multiple times — only creates on first call.
\   Uses a 131072-byte XMEM arena (128 KiB), which covers the
\   VFS descriptor, inode slab, FD pool, string pool, and the
\   VMP binding context (~28 KiB minimum).
131072 CONSTANT _ASHELL-VFS-ARENA-SIZE

: _ASHELL-VFS-INIT  ( -- )
    _ASHELL-VFS @ ?DUP IF  VFS-USE  EXIT  THEN   \ already created
    VFS-CUR ?DUP IF  DUP _ASHELL-VFS !  VFS-USE  EXIT  THEN  \ someone else set it
    _ASHELL-VFS-ARENA-SIZE A-XMEM ARENA-NEW
    ABORT" ashell: VFS arena alloc failed"
                                           ( arena )
    VMP-NEW                                ( vfs )
    DUP VMP-INIT
    ABORT" ashell: VMP-INIT failed"
    _ASHELL-VFS !                      \ VFS-USE already called by VFS-NEW
;

\ Run eagerly at load time so VFS is available before any applet
\ launches (e.g. DESK-LAUNCH happens before ASHELL-RUN).
_ASHELL-VFS-INIT

\ _ASHELL-LOAD-UIDL-FILE ( path-a path-u -- flag )
\   Thin wrapper around ASHELL-LOAD-UIDL that uses the shell's root
\   region and stashes the buffer for _ASHELL-TEARDOWN to FREE.
: _ASHELL-LOAD-UIDL-FILE  ( path-a path-u -- flag )
    _ASHELL-RGN @ ASHELL-LOAD-UIDL    ( buf | 0 )
    DUP _ASHELL-UIDL-BUF !
    0<> ;

: _ASHELL-SETUP  ( desc -- )
    DUP APP-DESC-VALID? 0= ABORT" ashell: invalid app descriptor"
    DUP _ASHELL-DESC !
    DUP APP.COMP-DESC @ CINST-NEW
    0<> ABORT" ashell: component instance allocation failed"
    _ASHELL-INST !
    \ 0. VFS — ensure a shared filesystem is available for applets
    _ASHELL-VFS-INIT
    \ 1. Terminal init
    DUP APP.WIDTH @ OVER APP.HEIGHT @  APP-INIT
    \ 2. Terminal title
    DUP APP.TITLE-A @ ?DUP IF
        OVER APP.TITLE-U @  APP-TITLE!
    THEN
    \ 3. Root region (full screen)
    0 0 SCR-H SCR-W RGN-NEW _ASHELL-RGN !
    \ 3b. Centre shell cursor
    _ASHELL-CUR-INIT
    \ 4. UIDL document
    \   Priority: inline UIDL-A > file UIDL-FILE-A > none
    DUP APP.UIDL-A @ ?DUP IF
        \ --- inline UIDL (existing path) ---
        OVER APP.UIDL-U @           ( desc uidl-a uidl-u )
        _ASHELL-RGN @               ( desc uidl-a uidl-u rgn )
        UTUI-LOAD                   ( desc flag )
        IF -1 ELSE 0 THEN
        _ASHELL-HAS-UIDL !
    ELSE
        \ --- UIDL file path (new: shell loads from VFS) ---
        DUP APP.UIDL-FILE-A @ ?DUP IF
            OVER APP.UIDL-FILE-U @  ( desc path-a path-u )
            _ASHELL-LOAD-UIDL-FILE  ( desc flag )
            _ASHELL-HAS-UIDL !
        ELSE 0 _ASHELL-HAS-UIDL ! THEN
    THEN
    \ 5. Prepare runtime state (BEFORE init callback so quit-from-init works)
    -1 _ASHELL-RUNNING !
    MS@ _ASHELL-LAST-TICK !
    \ 6. App init callback
    _ASHELL-ACTIVATE
    DUP APP.INIT-XT @ ?DUP IF
        _ASHELL-INST @ SWAP EXECUTE
    THEN
    \ 7. Escape sequence timeout
    1 KEY-TIMEOUT!
    \ 8. Initial paint
    ASHELL-DIRTY!
    \ Init may immediately request close.  Reach negotiation before
    \ invoking another app callback or touching the terminal surface.
    _ASHELL-RUNNING @ IF _ASHELL-PAINT THEN
    DROP ;

\ =====================================================================
\  §11 — Lifecycle: Shutdown
\ =====================================================================

VARIABLE _ASHELL-TD-IOR

\ Keep the first teardown failure.  Every teardown stage is caught so
\ later host-owned resources are still released.
: _ASHELL-TD-REMEMBER  ( ior -- )
    ?DUP IF
        _ASHELL-TD-IOR @ 0= IF _ASHELL-TD-IOR ! ELSE DROP THEN
    THEN ;

: _ASHELL-TD-APP  ( -- )
    \ A descriptor may have been stored before CINST-NEW failed.  Never
    \ invoke an app callback without the live instance required by its ABI.
    _ASHELL-INST @ 0= IF EXIT THEN
    _ASHELL-DESC @ ?DUP IF
        APP.SHUTDOWN-XT @ ?DUP IF
            _ASHELL-INST @ SWAP EXECUTE
        THEN
    THEN ;

: _ASHELL-TD-UIDL  ( -- )
    _ASHELL-HAS-UIDL @ IF
        0 _ASHELL-HAS-UIDL !
        UTUI-DETACH
    THEN ;

: _ASHELL-TD-UIDL-BUF  ( -- )
    _ASHELL-UIDL-BUF DUP @ SWAP 0 SWAP ! ?DUP IF
        _ASHELL-UIDL-FILE-MAX XMEM-FREE-BLOCK
    THEN ;

: _ASHELL-TD-REGION  ( -- )
    _ASHELL-RGN DUP @ SWAP 0 SWAP ! ?DUP IF
        RGN-FREE
    THEN ;

: _ASHELL-TD-TERM  ( -- )
    APP-SHUTDOWN ;

: _ASHELL-TD-INST  ( -- )
    _ASHELL-INST DUP @ SWAP 0 SWAP ! ?DUP IF CINST-FREE THEN ;

\ _ASHELL-TEARDOWN ( -- ior )
\   Nonthrowing best-effort teardown.  The first cleanup error is returned
\   only after every independent stage has run and shell ownership has been
\   reset.  ASHELL-RUN decides whether a primary execution error takes
\   precedence over this result.
: _ASHELL-TEARDOWN  ( -- ior )
    0 _ASHELL-TD-IOR !
    ['] _ASHELL-TD-APP      CATCH _ASHELL-TD-REMEMBER
    ['] _ASHELL-TD-UIDL     CATCH _ASHELL-TD-REMEMBER
    ['] _ASHELL-TD-UIDL-BUF CATCH _ASHELL-TD-REMEMBER
    ['] _ASHELL-TD-REGION   CATCH _ASHELL-TD-REMEMBER
    ['] _ASHELL-TD-TERM     CATCH _ASHELL-TD-REMEMBER
    ['] _ASHELL-TD-INST     CATCH _ASHELL-TD-REMEMBER
    \ Reset shell state even when a cleanup stage failed.  Ownership fields
    \ are cleared before their release attempt, so no stale handle can be
    \ reused or released twice by a later run.
    0 _ASHELL-DESC !
    0 _ASHELL-INST !
    0 _ASHELL-RGN !
    0 _ASHELL-HAS-UIDL !
    0 _ASHELL-UIDL-BUF !
    0 _ASHELL-ACTIVE-CTX !
    0 _ASHELL-RUNNING !
    0 _ASHELL-DIRTY !
    0 _ASHELL-POST-HEAD !
    0 _ASHELL-POST-TAIL !
    0 _ASHELL-CUR-VIS !
    _ASHELL-TD-IOR @ ;

\ =====================================================================
\  §12 — Event Loop
\ =====================================================================

: _ASHELL-LOOP  ( -- )
    \ _ASHELL-RUNNING and _ASHELL-LAST-TICK already set by _ASHELL-SETUP
    BEGIN
        _ASHELL-RUNNING @
    WHILE
        \ 1. Non-blocking input poll
        _ASHELL-EV KEY-POLL IF
            \ 1a. Resize events
            _ASHELL-EV _ASHELL-CHECK-RESIZE
            \ 1b. Dispatch key/mouse
            _ASHELL-EV @ KEY-T-RESIZE <> IF
                _ASHELL-EV _ASHELL-DISPATCH-KEY
            THEN
        THEN
        \ 2. Hardware resize poll
        _ASHELL-CHECK-HW-RESIZE
        \ 3. Deferred actions
        _ASHELL-DRAIN-POSTED
        \ A deferred action may request close.  Return to the negotiation
        \ boundary before any further app callback, paint, or scheduler hop.
        _ASHELL-RUNNING @ IF
            \ 4. Timer tick
            _ASHELL-CHECK-TICK
            \ A tick may request close.  Treat that as another hard
            \ lifecycle boundary before paint or a scheduler hop.
            _ASHELL-RUNNING @ IF
                \ 5. Paint (only if dirty)
                _ASHELL-PAINT
                \ 6. Cooperative yield.
                _ASHELL-RUNNING @ IF YIELD? THEN
            THEN
        THEN
    REPEAT ;

\ _ASHELL-LOOP-UNTIL-CLOSED ( -- )
\   A normal ASHELL-QUIT is only a request.  CANCEL and DEFER both keep
\   the app alive; DEFER remains distinct so an app can report pending
\   work and issue ASHELL-QUIT again when that work completes.
: _ASHELL-LOOP-UNTIL-CLOSED  ( -- )
    BEGIN
        _ASHELL-LOOP
        APP-CLOSE-R-QUIT ASHELL-REQUEST-CLOSE
        APP-CLOSE-D-ALLOW = IF EXIT THEN
        ASHELL-CANCEL-QUIT
    AGAIN ;

\ =====================================================================
\  §13 — Main Entry Point
\ =====================================================================

\ ASHELL-RUN ( desc -- )
\   Run an application.  Blocks until ASHELL-QUIT is called or the
\   app's init/event/tick/paint callback THROWs.  Terminal is always
\   restored on exit.
VARIABLE _ASHELL-RUN-IOR

: _ASHELL-RUN-FINISH  ( primary-ior -- )
    _ASHELL-RUN-IOR !
    _ASHELL-TEARDOWN                 ( cleanup-ior )
    _ASHELL-RUN-IOR @ ?DUP IF
        NIP THROW                    \ primary execution error wins
    THEN
    ?DUP IF THROW THEN ;             \ otherwise surface cleanup failure

: ASHELL-RUN  ( desc -- )
    ['] _ASHELL-SETUP CATCH ?DUP IF
        _ASHELL-RUN-FINISH
    THEN
    ['] _ASHELL-LOOP-UNTIL-CLOSED CATCH _ASHELL-RUN-FINISH ;

\ =====================================================================
\  §14 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ashell-guard

' ASHELL-RUN     CONSTANT _ashell-run-xt
' ASHELL-QUIT    CONSTANT _ashell-quit-xt
' ASHELL-DIRTY!  CONSTANT _ashell-dirty-xt
' ASHELL-REGION  CONSTANT _ashell-region-xt
' ASHELL-TICK-MS! CONSTANT _ashell-tick-ms-xt
' ASHELL-POST    CONSTANT _ashell-post-xt
' ASHELL-UIDL?   CONSTANT _ashell-uidl-xt
' ASHELL-DESC    CONSTANT _ashell-desc-xt
' ASHELL-INSTANCE CONSTANT _ashell-inst-xt
' ASHELL-REQUEST-CLOSE CONSTANT _ashell-request-close-xt
' ASHELL-TOAST   CONSTANT _ashell-toast-xt
' ASHELL-TOAST-VISIBLE? CONSTANT _ashell-toast-vis-xt

\ ASHELL-RUN is an owner-core lifecycle driver and deliberately does not
\ hold WITH-GUARD across its yielding event loop.  CATCH is task-aware and
\ may span TASK-YIELD; a lifetime guard still must not monopolize shared
\ shell metadata while the owner task is parked.  Short bounded mutation
\ and accessor entry points remain guarded below.
: ASHELL-RUN      _ashell-run-xt EXECUTE ;
\ ASHELL-QUIT is an idempotent aligned stop signal.  Keep it lock-free so
\ callbacks and worker/host control paths can request negotiation even if a
\ bounded shell operation currently owns the metadata guard.
: ASHELL-QUIT     _ashell-quit-xt EXECUTE ;
: ASHELL-DIRTY!   _ashell-dirty-xt    _ashell-guard WITH-GUARD ;
: ASHELL-REGION   _ashell-region-xt   _ashell-guard WITH-GUARD ;
: ASHELL-TICK-MS! _ashell-tick-ms-xt  _ashell-guard WITH-GUARD ;
: ASHELL-POST     _ashell-post-xt     _ashell-guard WITH-GUARD ;
: ASHELL-UIDL?    _ashell-uidl-xt     _ashell-guard WITH-GUARD ;
: ASHELL-DESC     _ashell-desc-xt     _ashell-guard WITH-GUARD ;
: ASHELL-INSTANCE _ashell-inst-xt     _ashell-guard WITH-GUARD ;
\ Close negotiation dispatches arbitrary app code and may park for user
\ confirmation.  It is owner-core lifecycle work, never a guarded metadata
\ critical section; cross-core callers must post the request to the owner.
: ASHELL-REQUEST-CLOSE _ashell-request-close-xt EXECUTE ;
: ASHELL-TOAST    _ashell-toast-xt    _ashell-guard WITH-GUARD ;
: ASHELL-TOAST-VISIBLE? _ashell-toast-vis-xt _ashell-guard WITH-GUARD ;
[THEN] [THEN]
