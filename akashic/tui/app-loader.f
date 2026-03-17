\ =================================================================
\  app-loader.f  —  Applet Package Loader
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ALOAD- / _ALOAD-
\  Depends on: akashic-binimg, akashic-tui-app-manifest,
\              akashic-tui-app-desc
\
\  Unified loader that ties together the binary image system
\  (binimg.f), the TOML manifest (app-manifest.f), and the
\  applet descriptor (app-desc.f) into a single load-and-launch
\  operation.
\
\  Applet package contract:
\    1. A TOML manifest declares name, entry word, .m64 filename,
\       optional UIDL filename, dimensions, dependencies.
\    2. The .m64 binary is a relocatable image saved with
\       IMG-SAVE-EXEC.  After loading, its entry word is available
\       in the dictionary.
\    3. The entry word has the signature:  ( desc -- )
\       It receives a zeroed APP-DESC and fills in its callbacks
\       (init-xt, event-xt, tick-xt, paint-xt, shutdown-xt)
\       plus optional UIDL pointer and title.
\    4. The loader returns the filled APP-DESC ready for
\       DESK-LAUNCH or ASHELL-RUN.
\
\  Public API:
\   ALOAD-FROM-MFT  ( mft -- desc ior )    Load applet from parsed manifest
\   ALOAD-MANIFEST  ( toml-a toml-l -- desc ior )   Parse manifest + load
\   ALOAD-ERR-PARSE   ( -- n )    Error: manifest parse failed
\   ALOAD-ERR-NOBIN   ( -- n )    Error: no binary field in manifest
\   ALOAD-ERR-LOAD    ( -- n )    Error: IMG-LOAD-EXEC failed
\   ALOAD-ERR-ENTRY   ( -- n )    Error: entry word not found
\ =================================================================

PROVIDED akashic-tui-app-loader

REQUIRE ../utils/binimg.f
REQUIRE app-manifest.f
REQUIRE app-desc.f

\ =====================================================================
\  §1 — Error codes
\ =====================================================================

-120 CONSTANT ALOAD-ERR-PARSE     \ manifest parse failed
-121 CONSTANT ALOAD-ERR-NOBIN     \ no binary= field
-122 CONSTANT ALOAD-ERR-LOAD      \ IMG-LOAD-EXEC failed
-123 CONSTANT ALOAD-ERR-ENTRY     \ entry word FIND failed

\ =====================================================================
\  §2 — Internal state
\ =====================================================================

VARIABLE _aload-mft       \ current manifest descriptor
VARIABLE _aload-desc      \ current APP-DESC being built

CREATE _aload-find-buf 32 ALLOT  \ counted string for FIND

\ =====================================================================
\  §3 — _ALOAD-FIND-WORD  ( addr len -- xt flag )
\    Build a counted string from (addr len) and call FIND.
\    Returns (xt -1|1) on success, (0 0) on failure.
\ =====================================================================

: _ALOAD-FIND-WORD  ( addr len -- xt flag )
    DUP 31 > IF 2DROP 0 0 EXIT THEN   \ name too long
    DUP _aload-find-buf C!            \ store count
    _aload-find-buf 1+ SWAP CMOVE     \ copy name bytes
    _aload-find-buf FIND              ( xt flag | caddr 0 )
    DUP 0= IF NIP 0 THEN ;           \ normalize failure to (0 0)

\ =====================================================================
\  §4 — _ALOAD-LOAD-BINARY  ( mft -- xt ior )
\    Read the binary= field from the manifest, use it as a filename
\    to load via IMG-LOAD-EXEC.  Returns entry xt and 0 on success.
\
\    The tricky part: IMG-LOAD-EXEC parses its filename from the
\    input stream, but we have the filename as (addr len).  We use
\    EVALUATE to inject the filename into the input stream followed
\    by IMG-LOAD-EXEC.
\ =====================================================================

\ Scratch buffer for building EVALUATE strings
CREATE _aload-eval-buf 80 ALLOT

: _ALOAD-LOAD-BINARY  ( mft -- xt ior )
    DUP MFT-BINARY NIP 0= IF
        DROP 0 ALOAD-ERR-NOBIN EXIT
    THEN
    MFT-BINARY                        ( bin-a bin-l )
    \ Build "IMG-LOAD-EXEC <filename>" in eval buffer
    DUP 64 > IF 2DROP 0 ALOAD-ERR-NOBIN EXIT THEN
    \ "IMG-LOAD-EXEC " = 14 chars (13 letters + 1 trailing space)
    S" IMG-LOAD-EXEC " _aload-eval-buf SWAP CMOVE
    _aload-eval-buf 14 +              ( bin-a bin-l dest )
    ROT ROT                           ( dest bin-a bin-l )
    2DUP 2>R
    ROT SWAP CMOVE                    ( )
    2R>                               ( bin-a bin-l )
    NIP 14 +                          ( total-len )
    _aload-eval-buf SWAP EVALUATE     ( xt ior )
;

\ =====================================================================
\  §5 — _ALOAD-FILL-DESC  ( mft xt -- desc ior )
\    Allocate and zero an APP-DESC, fill metadata from manifest,
\    call the entry word to let the applet fill its callbacks.
\ =====================================================================

: _ALOAD-FILL-DESC  ( mft xt -- desc ior )
    SWAP >R                           ( xt   R: mft )
    \ Allocate APP-DESC at HERE
    HERE APP-DESC ALLOT               ( xt desc )
    DUP APP-DESC-INIT                 ( xt desc )
    \ Fill dimensions from manifest
    R@ MFT-WIDTH  OVER APP.WIDTH  !
    R@ MFT-HEIGHT OVER APP.HEIGHT !
    \ Fill title from manifest (MFT-TITLE returns addr len — two values)
    R@ MFT-TITLE DROP OVER APP.TITLE-A !
    R@ MFT-TITLE NIP  OVER APP.TITLE-U !
    R> DROP                           ( xt desc )
    \ Call entry word: xt ( desc -- )
    \ Save desc, let entry word consume its copy, then restore.
    DUP >R                            ( xt desc   R: desc )
    SWAP EXECUTE                      ( -- ; entry consumed desc )
    R>                                ( desc )
    0                                 ( desc 0 )
;

\ =====================================================================
\  §6 — ALOAD-FROM-MFT  ( mft -- desc ior )
\    Given an already-parsed manifest, load the binary, resolve the
\    entry word, build the APP-DESC.  On error, desc=0.
\ =====================================================================

: ALOAD-FROM-MFT  ( mft -- desc ior )
    DUP _aload-mft !
    \ 1. Load the binary image
    DUP _ALOAD-LOAD-BINARY            ( mft xt ior )
    ?DUP IF
        NIP NIP 0 SWAP EXIT           ( 0 ior )
    THEN                               ( mft xt )
    \ 2. If LOAD-EXEC returned 0 for xt, try FIND on entry name
    DUP 0= IF
        DROP
        DUP MFT-ENTRY                  ( mft entry-a entry-l )
        _ALOAD-FIND-WORD               ( mft xt flag )
        0= IF
            DROP 0 ALOAD-ERR-ENTRY EXIT
        THEN
    THEN                               ( mft xt )
    \ 3. Build APP-DESC
    _ALOAD-FILL-DESC                   ( desc ior )
;

\ =====================================================================
\  §7 — ALOAD-MANIFEST  ( toml-a toml-l -- desc ior )
\    Full pipeline: parse manifest TOML → load binary → build desc.
\    Frees the manifest descriptor on completion.
\ =====================================================================

: ALOAD-MANIFEST  ( toml-a toml-l -- desc ior )
    MFT-PARSE                          ( mft | 0 )
    DUP 0= IF
        ALOAD-ERR-PARSE EXIT
    THEN
    DUP >R
    ALOAD-FROM-MFT                     ( desc ior )
    R> MFT-FREE
;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _aload-guard

' ALOAD-FROM-MFT  CONSTANT _aload-from-mft-xt
' ALOAD-MANIFEST  CONSTANT _aload-manifest-xt

: ALOAD-FROM-MFT  _aload-from-mft-xt  _aload-guard WITH-GUARD ;
: ALOAD-MANIFEST  _aload-manifest-xt   _aload-guard WITH-GUARD ;
[THEN] [THEN]
