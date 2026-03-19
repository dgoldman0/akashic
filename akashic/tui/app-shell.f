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
\  §1b — UIDL Context Save / Restore  (browser-owned)
\ =====================================================================
\
\  Per sub-app UIDL context buffer holding 15 scalar variables and
\  10 pool arrays.  Total ~99,448 bytes (~97 KiB).
\
\  The shell (browser) owns context management because it orchestrates
\  painting and event dispatch across multiple sub-apps.  Desk and
\  other multi-app hosts call ASHELL-CTX-SWITCH; they never touch
\  UCTX-SAVE / UCTX-RESTORE directly.

15 CONSTANT _UCTX-NVAR
120 CONSTANT _UCTX-VAR-SZ       \ 15 × 8

\ Pool sizes (must match module declarations)
32768 CONSTANT _UCTX-ELEMS-SZ   \ 256 × 128
20480 CONSTANT _UCTX-ATTRS-SZ   \ 512 × 40
12288 CONSTANT _UCTX-STRS-SZ
 2048 CONSTANT _UCTX-HASH-SZ    \ 256 × 8
 4096 CONSTANT _UCTX-HIDS-SZ    \ 256 × 16
 3072 CONSTANT _UCTX-SUBS-SZ    \ 128 × 24
20480 CONSTANT _UCTX-SC-SZ      \ 256 × 80
 1536 CONSTANT _UCTX-ACTS-SZ    \ 64 × 24
 2048 CONSTANT _UCTX-SHORTS-SZ  \ 64 × 32
  512 CONSTANT _UCTX-OVBUF-SZ   \ 32 × 16

\ Offsets into context buffer
_UCTX-VAR-SZ                                       CONSTANT _UCTX-O-ELEMS
_UCTX-O-ELEMS  _UCTX-ELEMS-SZ  +                   CONSTANT _UCTX-O-ATTRS
_UCTX-O-ATTRS  _UCTX-ATTRS-SZ  +                   CONSTANT _UCTX-O-STRS
_UCTX-O-STRS   _UCTX-STRS-SZ   +                   CONSTANT _UCTX-O-HASH
_UCTX-O-HASH   _UCTX-HASH-SZ   +                   CONSTANT _UCTX-O-HIDS
_UCTX-O-HIDS   _UCTX-HIDS-SZ   +                   CONSTANT _UCTX-O-SUBS
_UCTX-O-SUBS   _UCTX-SUBS-SZ   +                   CONSTANT _UCTX-O-SC
_UCTX-O-SC     _UCTX-SC-SZ     +                   CONSTANT _UCTX-O-ACTS
_UCTX-O-ACTS   _UCTX-ACTS-SZ   +                   CONSTANT _UCTX-O-SHORTS
_UCTX-O-SHORTS _UCTX-SHORTS-SZ +                   CONSTANT _UCTX-O-OVBUF
_UCTX-O-OVBUF  _UCTX-OVBUF-SZ  +                   CONSTANT _UCTX-TOTAL

\ --- Variable table: maps index → global VARIABLE address ---
CREATE _UCTX-VARS  _UCTX-NVAR CELLS ALLOT

: _UCTX-INIT-VARS  ( -- )
    _UDL-ECNT           _UCTX-VARS  0 CELLS + !
    _UDL-ACNT           _UCTX-VARS  1 CELLS + !
    _UDL-SPOS           _UCTX-VARS  2 CELLS + !
    _UDL-ROOT           _UCTX-VARS  3 CELLS + !
    _UDL-SUB-CNT        _UCTX-VARS  4 CELLS + !
    _UTUI-ELEM-BASE     _UCTX-VARS  5 CELLS + !
    _UTUI-DOC-LOADED    _UCTX-VARS  6 CELLS + !
    _UTUI-STATE         _UCTX-VARS  7 CELLS + !
    _UTUI-FOCUS-P       _UCTX-VARS  8 CELLS + !
    _UTUI-ACT-CNT       _UCTX-VARS  9 CELLS + !
    _UTUI-SHORT-CNT     _UCTX-VARS 10 CELLS + !
    _UTUI-OVERLAY-CNT   _UCTX-VARS 11 CELLS + !
    _UTUI-SAVED-FOCUS   _UCTX-VARS 12 CELLS + !
    _UTUI-SKIP-CHILDREN _UCTX-VARS 13 CELLS + !
    _UTUI-RGN           _UCTX-VARS 14 CELLS + ! ;
_UCTX-INIT-VARS

\ --- Pool table: maps index → (global-addr, ctx-offset, size) ---
10 CONSTANT _UCTX-NPOOL
CREATE _UCTX-POOLS  _UCTX-NPOOL 3 * CELLS ALLOT

: _UCTX-INIT-POOLS  ( -- )
    _UDL-ELEMS        _UCTX-POOLS   0 + !
    _UCTX-O-ELEMS     _UCTX-POOLS   8 + !
    _UCTX-ELEMS-SZ    _UCTX-POOLS  16 + !
    _UDL-ATTRS        _UCTX-POOLS  24 + !
    _UCTX-O-ATTRS     _UCTX-POOLS  32 + !
    _UCTX-ATTRS-SZ    _UCTX-POOLS  40 + !
    _UDL-STRS         _UCTX-POOLS  48 + !
    _UCTX-O-STRS      _UCTX-POOLS  56 + !
    _UCTX-STRS-SZ     _UCTX-POOLS  64 + !
    _UDL-HASH         _UCTX-POOLS  72 + !
    _UCTX-O-HASH      _UCTX-POOLS  80 + !
    _UCTX-HASH-SZ     _UCTX-POOLS  88 + !
    _UDL-HIDS         _UCTX-POOLS  96 + !
    _UCTX-O-HIDS      _UCTX-POOLS 104 + !
    _UCTX-HIDS-SZ     _UCTX-POOLS 112 + !
    _UDL-SUBS         _UCTX-POOLS 120 + !
    _UCTX-O-SUBS      _UCTX-POOLS 128 + !
    _UCTX-SUBS-SZ     _UCTX-POOLS 136 + !
    _UTUI-SIDECARS    _UCTX-POOLS 144 + !
    _UCTX-O-SC        _UCTX-POOLS 152 + !
    _UCTX-SC-SZ       _UCTX-POOLS 160 + !
    _UTUI-ACTS        _UCTX-POOLS 168 + !
    _UCTX-O-ACTS      _UCTX-POOLS 176 + !
    _UCTX-ACTS-SZ     _UCTX-POOLS 184 + !
    _UTUI-SHORTS      _UCTX-POOLS 192 + !
    _UCTX-O-SHORTS    _UCTX-POOLS 200 + !
    _UCTX-SHORTS-SZ   _UCTX-POOLS 208 + !
    _UTUI-OVERLAY-BUF _UCTX-POOLS 216 + !
    _UCTX-O-OVBUF     _UCTX-POOLS 224 + !
    _UCTX-OVBUF-SZ    _UCTX-POOLS 232 + ! ;
_UCTX-INIT-POOLS

\ --- UCTX-ALLOC / FREE / SAVE / RESTORE / CLEAR ---

: UCTX-ALLOC  ( -- ctx | 0 )
    _UCTX-TOTAL ALLOCATE IF DROP 0 THEN ;

: UCTX-FREE  ( ctx -- )  FREE ;

\ Pool copy helper variables
VARIABLE _UCP-SRC   VARIABLE _UCP-DST   VARIABLE _UCP-SZ

: UCTX-SAVE  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    _UCTX-NVAR 0 DO
        I CELLS _UCTX-VARS + @
        @ OVER I CELLS + !
    LOOP
    _UCTX-NPOOL 0 DO
        I 3 * CELLS _UCTX-POOLS +
        DUP @       _UCP-SRC !
        DUP 16 + @  _UCP-SZ  !
        8 + @ OVER + _UCP-DST !
        _UCP-SRC @ _UCP-DST @ _UCP-SZ @ CMOVE
    LOOP
    DROP ;

: UCTX-RESTORE  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    _UCTX-NVAR 0 DO
        DUP I CELLS + @
        I CELLS _UCTX-VARS + @
        !
    LOOP
    _UCTX-NPOOL 0 DO
        I 3 * CELLS _UCTX-POOLS +
        DUP @       _UCP-DST !
        DUP 16 + @  _UCP-SZ  !
        8 + @ OVER + _UCP-SRC !
        _UCP-SRC @ _UCP-DST @ _UCP-SZ @ CMOVE
    LOOP
    DROP ;

: UCTX-CLEAR  ( ctx -- )
    DUP 0= IF DROP EXIT THEN
    _UCTX-TOTAL 0 FILL ;

\ =====================================================================
\  §1c — Context Switch & Child Painting  (browser API)
\ =====================================================================

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

\ ASHELL-PAINT-CHILD ( uctx rgn has-uidl desc -- )
\   The browser's per-child paint primitive.  Context-switches to
\   uctx, sets the region, calls UTUI-PAINT (if has-uidl), then
\   calls the app descriptor's paint callback (if any).
: ASHELL-PAINT-CHILD  ( uctx rgn has-uidl desc -- )
    >R >R                                 ( uctx rgn   R: desc has-uidl )
    SWAP ASHELL-CTX-SWITCH                ( rgn )
    ?DUP IF RGN-USE THEN
    R> IF UTUI-PAINT THEN                 (  R: desc )
    R> ?DUP IF APP.PAINT-XT @ ?DUP IF EXECUTE THEN THEN ;

\ =====================================================================
\  §2 — Shell State
\ =====================================================================

VARIABLE _ASHELL-RGN          \ Root region (0 = not created)
0 _ASHELL-RGN !

VARIABLE _ASHELL-VFS          \ Shared VFS instance (0 = not yet created)
0 _ASHELL-VFS !

VARIABLE _ASHELL-DESC         \ Current app descriptor (0 = not running)
0 _ASHELL-DESC !

VARIABLE _ASHELL-RUNNING      \ Event loop active flag
0 _ASHELL-RUNNING !

VARIABLE _ASHELL-DIRTY        \ Repaint requested flag
0 _ASHELL-DIRTY !

VARIABLE _ASHELL-HAS-UIDL     \ UIDL document loaded flag
0 _ASHELL-HAS-UIDL !

VARIABLE _ASHELL-UIDL-BUF     \ Shell-loaded UIDL file buffer (0 = not ours)
0 _ASHELL-UIDL-BUF !

VARIABLE _ASHELL-UIDL-BUF-LEN \ Byte count read from UIDL file
0 _ASHELL-UIDL-BUF-LEN !

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
\   Signal the event loop to exit after the current iteration.
: ASHELL-QUIT  ( -- )
    0 _ASHELL-RUNNING ! ;

\ ASHELL-DIRTY! ( -- )
\   Mark the screen as needing repaint.
: ASHELL-DIRTY!  ( -- )
    -1 _ASHELL-DIRTY ! ;

\ ASHELL-REGION ( -- rgn )
\   The root region that covers the full screen.
: ASHELL-REGION  ( -- rgn )
    _ASHELL-RGN @ ;

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

\ ASHELL-TOAST-VISIBLE? ( -- flag )
\   True if toast message is currently showing.
: ASHELL-TOAST-VISIBLE?  ( -- flag )
    _ASHELL-TOAST-EXPIRY @ MS@ > ;

\ ASHELL-TOAST ( addr u ms -- )
\   Show a toast message for ms milliseconds.
: ASHELL-TOAST  ( addr u ms -- )
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
\  §6 — Resize Handling
\ =====================================================================

: _ASHELL-ON-RESIZE  ( w h -- )
    SCR-RESIZE
    \ Rebuild root region from new screen dimensions
    _ASHELL-RGN @ ?DUP IF RGN-FREE THEN
    0 0 SCR-H SCR-W RGN-NEW _ASHELL-RGN !
    \ Re-layout UIDL tree if loaded
    _ASHELL-HAS-UIDL @ IF
        UTUI-RELAYOUT
    THEN
    ASHELL-DIRTY! ;

\ =====================================================================
\  §7 — Event Dispatch
\ =====================================================================

\ _ASHELL-DISPATCH-KEY ( ev -- )
\   Route a key event through the app's handler, then UIDL dispatch.
: _ASHELL-DISPATCH-KEY  ( ev -- )
    \ 1. App's event handler gets first crack
    _ASHELL-DESC @ APP.EVENT-XT @ ?DUP IF
        OVER SWAP EXECUTE            ( ev consumed? )
        IF DROP ASHELL-DIRTY! EXIT THEN
    THEN
    \ 2. UIDL dispatch (shortcuts, focused element)
    _ASHELL-HAS-UIDL @ IF
        DUP UTUI-DISPATCH-KEY        ( ev consumed? )
        IF ASHELL-DIRTY! THEN
    THEN
    DROP ;

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
    _ASHELL-DESC @ APP.TICK-XT @ 0= IF EXIT THEN
    MS@ _ASHELL-TICK-TMP !
    _ASHELL-TICK-TMP @ _ASHELL-LAST-TICK @ -
    _ASHELL-TICK-MS @ >= IF
        _ASHELL-TICK-TMP @ _ASHELL-LAST-TICK !
        _ASHELL-DESC @ APP.TICK-XT @ EXECUTE
        \ If tick caused any UIDL/widget changes, auto-dirty
        _UTUI-NEEDS-PAINT @ IF
            0 _UTUI-NEEDS-PAINT !
            ASHELL-DIRTY!
        THEN
    THEN
    \ Toast expiry: if toast just expired, trigger repaint to clear it
    ASHELL-TOAST-VISIBLE? 0= IF
        _ASHELL-TOAST-WAS-VIS @ IF
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
    RGN-ROOT
    \ UIDL elements first (they own the background/structure)
    _ASHELL-HAS-UIDL @ IF
        UTUI-PAINT
    THEN
    \ App's custom widget painting (on top of UIDL)
    _ASHELL-DESC @ APP.PAINT-XT @ ?DUP IF
        EXECUTE
    THEN
    \ Toast overlay (drawn last, on top of everything)
    ASHELL-TOAST-VISIBLE? IF
        _ASHELL-DRAW-TOAST
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
    DUP _ASHELL-VFS !                      \ VFS-USE already called by VFS-NEW
;

\ Run eagerly at load time so VFS is available before any applet
\ launches (e.g. DESK-LAUNCH happens before ASHELL-RUN).
_ASHELL-VFS-INIT

\ _ASHELL-LOAD-UIDL-FILE ( path-a path-u -- flag )
\   Open a VFS file, read its contents into a heap buffer, then
\   feed the content to UTUI-LOAD using the current root region.
\   Stores the buffer in _ASHELL-UIDL-BUF so _ASHELL-TEARDOWN
\   can FREE it.  Returns -1 on success, 0 on failure.
8192 CONSTANT _ASHELL-UIDL-FILE-MAX

: _ASHELL-LOAD-UIDL-FILE  ( path-a path-u -- flag )
    VFS-OPEN                          ( fd | 0 )
    DUP 0= IF EXIT THEN              ( fd )  \ not found → 0
    >R
    \ Allocate heap buffer
    _ASHELL-UIDL-FILE-MAX ALLOCATE IF
        R> VFS-CLOSE  0 EXIT         \ alloc failed → 0
    THEN                              ( buf  R: fd )
    DUP _ASHELL-UIDL-BUF !
    \ Read file content
    _ASHELL-UIDL-FILE-MAX R@ VFS-READ ( actual )
    DUP _ASHELL-UIDL-BUF-LEN !
    R> VFS-CLOSE                      ( actual )
    \ Feed to UTUI-LOAD
    _ASHELL-UIDL-BUF @  SWAP         ( buf-a actual )
    _ASHELL-RGN @                     ( buf-a actual rgn )
    UTUI-LOAD                         ( flag )
    IF -1 ELSE 0 THEN ;

: _ASHELL-SETUP  ( desc -- )
    DUP _ASHELL-DESC !
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
    DUP APP.INIT-XT @ ?DUP IF EXECUTE THEN
    \ 7. Escape sequence timeout
    1 KEY-TIMEOUT!
    \ 8. Initial paint
    ASHELL-DIRTY!
    _ASHELL-PAINT
    DROP ;

\ =====================================================================
\  §11 — Lifecycle: Shutdown
\ =====================================================================

: _ASHELL-TEARDOWN  ( -- )
    \ App shutdown callback
    _ASHELL-DESC @ ?DUP IF
        APP.SHUTDOWN-XT @ ?DUP IF EXECUTE THEN
    THEN
    \ UIDL detach
    _ASHELL-HAS-UIDL @ IF
        UTUI-DETACH
        0 _ASHELL-HAS-UIDL !
    THEN
    \ Free shell-loaded UIDL file buffer (if we loaded it)
    _ASHELL-UIDL-BUF @ ?DUP IF
        FREE DROP
        0 _ASHELL-UIDL-BUF !
        0 _ASHELL-UIDL-BUF-LEN !
    THEN
    \ Free region
    _ASHELL-RGN @ ?DUP IF
        RGN-FREE
        0 _ASHELL-RGN !
    THEN
    \ Terminal teardown
    APP-SHUTDOWN
    \ Reset shell state
    0 _ASHELL-DESC !
    0 _ASHELL-RUNNING !
    0 _ASHELL-DIRTY !
    0 _ASHELL-POST-HEAD !
    0 _ASHELL-POST-TAIL ! ;

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
        \ 4. Timer tick
        _ASHELL-CHECK-TICK
        \ 5. Paint (only if dirty)
        _ASHELL-PAINT
        \ 6. Cooperative yield
        YIELD?
    REPEAT ;

\ =====================================================================
\  §13 — Main Entry Point
\ =====================================================================

\ ASHELL-RUN ( desc -- )
\   Run an application.  Blocks until ASHELL-QUIT is called or the
\   app's init/event/tick/paint callback THROWs.  Terminal is always
\   restored on exit.
: ASHELL-RUN  ( desc -- )
    ['] _ASHELL-SETUP CATCH ?DUP IF
        \ Setup failed — still try to clean up
        _ASHELL-TEARDOWN
        THROW
    THEN
    ['] _ASHELL-LOOP CATCH
    _ASHELL-TEARDOWN
    ?DUP IF THROW THEN ;

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
' ASHELL-TOAST   CONSTANT _ashell-toast-xt
' ASHELL-TOAST-VISIBLE? CONSTANT _ashell-toast-vis-xt

: ASHELL-RUN      _ashell-run-xt      _ashell-guard WITH-GUARD ;
: ASHELL-QUIT     _ashell-quit-xt     _ashell-guard WITH-GUARD ;
: ASHELL-DIRTY!   _ashell-dirty-xt    _ashell-guard WITH-GUARD ;
: ASHELL-REGION   _ashell-region-xt   _ashell-guard WITH-GUARD ;
: ASHELL-TICK-MS! _ashell-tick-ms-xt  _ashell-guard WITH-GUARD ;
: ASHELL-POST     _ashell-post-xt     _ashell-guard WITH-GUARD ;
: ASHELL-UIDL?    _ashell-uidl-xt     _ashell-guard WITH-GUARD ;
: ASHELL-DESC     _ashell-desc-xt     _ashell-guard WITH-GUARD ;
: ASHELL-TOAST    _ashell-toast-xt    _ashell-guard WITH-GUARD ;
: ASHELL-TOAST-VISIBLE? _ashell-toast-vis-xt _ashell-guard WITH-GUARD ;
[THEN] [THEN]
