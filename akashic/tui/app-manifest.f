\ =================================================================
\  app-manifest.f  —  Application Manifest Reader
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: MFT- / _MFT-
\  Depends on: akashic-toml
\
\  Reads a TOML manifest describing a TUI application's metadata.
\  The caller provides a (addr len) pair pointing to the TOML text
\  already in memory.  Returned string pointers reference the
\  original document — the caller must keep it alive.
\
\  Manifest format:
\    [app]
\    name    = "my-app"
\    title   = "My Application"
\    version = "0.1.0"
\    width   = 80
\    height  = 24
\    entry   = "my-main"
\
\    [deps]
\    uidl = true
\    css  = true
\
\  Public API:
\   MFT-PARSE      ( doc-a doc-l -- mft | 0 )  Parse manifest
\   MFT-FREE       ( mft -- )                   Release descriptor
\   MFT-NAME       ( mft -- addr len )           App name
\   MFT-TITLE      ( mft -- addr len )           App title
\   MFT-VERSION    ( mft -- addr len )           Version string
\   MFT-WIDTH      ( mft -- n )                  Preferred width  (0=auto)
\   MFT-HEIGHT     ( mft -- n )                  Preferred height (0=auto)
\   MFT-ENTRY      ( mft -- addr len )           Entry word name
\   MFT-DEP?       ( mft key-a key-l -- flag )   Is dependency required?
\ =================================================================

PROVIDED akashic-tui-app-manifest

REQUIRE ../utils/toml.f

\ =====================================================================
\  §1 — Error codes
\ =====================================================================

-110 CONSTANT MFT-E-NO-APP     \ Missing [app] section
-111 CONSTANT MFT-E-NO-NAME    \ Missing name key
-112 CONSTANT MFT-E-NO-ENTRY   \ Missing entry key

\ =====================================================================
\  §2 — Descriptor layout  (12 cells = 96 bytes)
\ =====================================================================
\
\  Offset  Field        Description
\  +0      name-addr    Pointer to name string (in source doc)
\  +8      name-len     Name length
\  +16     title-addr   Pointer to title string
\  +24     title-len    Title length
\  +32     version-addr Pointer to version string
\  +40     version-len  Version length
\  +48     width        Preferred width  (0 = auto)
\  +56     height       Preferred height (0 = auto)
\  +64     entry-addr   Pointer to entry word name
\  +72     entry-len    Entry word name length
\  +80     doc-addr     Original TOML document address (for lazy deps)
\  +88     doc-len      Original TOML document length

96 CONSTANT _MFT-SIZE

\ Field offsets
 0 CONSTANT _MFT-O-NAME-A
 8 CONSTANT _MFT-O-NAME-L
16 CONSTANT _MFT-O-TITLE-A
24 CONSTANT _MFT-O-TITLE-L
32 CONSTANT _MFT-O-VER-A
40 CONSTANT _MFT-O-VER-L
48 CONSTANT _MFT-O-WIDTH
56 CONSTANT _MFT-O-HEIGHT
64 CONSTANT _MFT-O-ENTRY-A
72 CONSTANT _MFT-O-ENTRY-L
80 CONSTANT _MFT-O-DOC-A
88 CONSTANT _MFT-O-DOC-L

\ =====================================================================
\  §3 — Internal helpers
\ =====================================================================

\ Store a string pair (addr len) into descriptor at mft+offset
: _MFT-SET-STR  ( str-a str-l mft offset -- )
    + >R                             ( str-a str-l   R: field-a )
    R@ 8 + !                         \ store len at field+8
    R> ! ;                           \ store addr at field+0

\ Read a string pair from descriptor at mft+offset
: _MFT-GET-STR  ( mft offset -- addr len )
    + DUP @ SWAP 8 + @ ;

\ Deallocate descriptor (ALLOT negative if at top of dict)
: _MFT-DEALLOC  ( mft -- )
    _MFT-SIZE NEGATE ALLOT DROP ;

\ =====================================================================
\  §4 — MFT-PARSE  ( doc-a doc-l -- mft | 0 )
\ =====================================================================
\   Parse a TOML manifest string.  Returns the descriptor address
\   on success, or 0 on failure.  The descriptor is ALLOTed at HERE.
\
\   Required keys:  [app].name, [app].entry
\   Optional keys:  title, version, width, height
\   Optional section: [deps]  (queried lazily by MFT-DEP?)

: MFT-PARSE  ( doc-a doc-l -- mft | 0 )
    \ Allocate descriptor at HERE
    HERE _MFT-SIZE ALLOT             ( doc-a doc-l mft )
    DUP _MFT-SIZE 0 FILL

    >R                               ( doc-a doc-l   R: mft )

    \ Store original doc pointer for lazy MFT-DEP? queries
    OVER R@ _MFT-O-DOC-A + !
    DUP  R@ _MFT-O-DOC-L + !

    \ --- Find [app] section (required) ---
    2DUP S" app" TOML-FIND-TABLE?    ( doc-a doc-l body-a body-l flag )
    0= IF
        2DROP 2DROP R> _MFT-DEALLOC 0 EXIT
    THEN
                                     ( doc-a doc-l body-a body-l )

    \ --- name (required) ---
    2DUP S" name" TOML-KEY?          ( ... val-a val-l flag )
    0= IF
        2DROP 2DROP 2DROP R> _MFT-DEALLOC 0 EXIT
    THEN
    TOML-GET-STRING                  ( doc-a doc-l body-a body-l str-a str-l )
    R@ _MFT-O-NAME-A _MFT-SET-STR   ( doc-a doc-l body-a body-l )

    \ --- entry (required) ---
    2DUP S" entry" TOML-KEY?
    0= IF
        2DROP 2DROP 2DROP R> _MFT-DEALLOC 0 EXIT
    THEN
    TOML-GET-STRING
    R@ _MFT-O-ENTRY-A _MFT-SET-STR

    \ --- title (optional — defaults to name) ---
    2DUP S" title" TOML-KEY?
    IF
        TOML-GET-STRING
        R@ _MFT-O-TITLE-A _MFT-SET-STR
    ELSE
        2DROP
        R@ _MFT-O-NAME-A + @  R@ _MFT-O-TITLE-A + !
        R@ _MFT-O-NAME-L + @  R@ _MFT-O-TITLE-L + !
    THEN

    \ --- version (optional) ---
    2DUP S" version" TOML-KEY?
    IF
        TOML-GET-STRING
        R@ _MFT-O-VER-A _MFT-SET-STR
    ELSE 2DROP THEN

    \ --- width (optional, default 0) ---
    2DUP S" width" TOML-KEY?
    IF   TOML-GET-INT  R@ _MFT-O-WIDTH + !
    ELSE 2DROP THEN

    \ --- height (optional, default 0) ---
    2DUP S" height" TOML-KEY?
    IF   TOML-GET-INT  R@ _MFT-O-HEIGHT + !
    ELSE 2DROP THEN

    2DROP 2DROP                      ( -- )
    R>                               ( mft )
;

\ =====================================================================
\  §5 — Accessors
\ =====================================================================

: MFT-NAME     ( mft -- addr len )  _MFT-O-NAME-A  _MFT-GET-STR ;
: MFT-TITLE    ( mft -- addr len )  _MFT-O-TITLE-A _MFT-GET-STR ;
: MFT-VERSION  ( mft -- addr len )  _MFT-O-VER-A   _MFT-GET-STR ;
: MFT-ENTRY    ( mft -- addr len )  _MFT-O-ENTRY-A _MFT-GET-STR ;
: MFT-WIDTH    ( mft -- n )         _MFT-O-WIDTH  + @ ;
: MFT-HEIGHT   ( mft -- n )         _MFT-O-HEIGHT + @ ;

\ =====================================================================
\  §6 — MFT-DEP?  ( mft key-a key-l -- flag )
\ =====================================================================
\   Check if a named dependency is listed as true in the [deps]
\   section.  Returns FALSE if [deps] is missing, the key is
\   absent, or the value is false.
\
\   Performs a lazy lookup into the original TOML document each time.

: MFT-DEP?  ( mft key-a key-l -- flag )
    2>R                              ( mft   R: key-a key-l )

    \ Retrieve original doc from descriptor
    DUP _MFT-O-DOC-A + @            ( mft doc-a )
    SWAP _MFT-O-DOC-L + @           ( doc-a doc-l )

    \ Find [deps] section (optional)
    S" deps" TOML-FIND-TABLE?        ( body-a body-l flag )
    0= IF 2DROP 2R> 2DROP 0 EXIT THEN

    \ Look up the key
    2R> TOML-KEY?                    ( val-a val-l flag )
    0= IF 2DROP 0 EXIT THEN

    \ Get boolean value
    TOML-GET-BOOL ;

\ =====================================================================
\  §7 — MFT-FREE  ( mft -- )
\ =====================================================================
\   Release the manifest descriptor.  Since it was ALLOTed via HERE,
\   we can only truly reclaim it if it is the most recent allocation.
\   Otherwise the memory remains until the next dictionary reset.

: MFT-FREE  ( mft -- )
    DUP _MFT-SIZE + HERE = IF
        _MFT-SIZE NEGATE ALLOT
    THEN
    DROP ;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _mft-guard

' MFT-PARSE   CONSTANT _mft-parse-xt
' MFT-FREE    CONSTANT _mft-free-xt
' MFT-NAME    CONSTANT _mft-name-xt
' MFT-TITLE   CONSTANT _mft-title-xt
' MFT-VERSION CONSTANT _mft-version-xt
' MFT-WIDTH   CONSTANT _mft-width-xt
' MFT-HEIGHT  CONSTANT _mft-height-xt
' MFT-ENTRY   CONSTANT _mft-entry-xt
' MFT-DEP?    CONSTANT _mft-dep-xt

: MFT-PARSE   _mft-parse-xt   _mft-guard WITH-GUARD ;
: MFT-FREE    _mft-free-xt    _mft-guard WITH-GUARD ;
: MFT-NAME    _mft-name-xt    _mft-guard WITH-GUARD ;
: MFT-TITLE   _mft-title-xt   _mft-guard WITH-GUARD ;
: MFT-VERSION _mft-version-xt _mft-guard WITH-GUARD ;
: MFT-WIDTH   _mft-width-xt   _mft-guard WITH-GUARD ;
: MFT-HEIGHT  _mft-height-xt  _mft-guard WITH-GUARD ;
: MFT-ENTRY   _mft-entry-xt   _mft-guard WITH-GUARD ;
: MFT-DEP?    _mft-dep-xt     _mft-guard WITH-GUARD ;
[THEN] [THEN]
