\ =====================================================================
\  app-manifest.f - trusted-local applet manifest, format version 1
\ =====================================================================
\  This is an integrity and ABI contract for locally authored native
\  applets.  It is not a signature, permission, or sandbox boundary.
\
\  Project manifest (image fields omitted until Build & Install):
\
\    [package]
\    format = 1
\    trust = "local"
\    source = "/hello.f"
\
\    [app]
\    id = "local.hello"
\    version = "0.1.0"
\    abi = 1
\    entry = "HELLO-ENTRY"
\    title = "Hello"                 # optional; defaults to id
\    width = 40                       # optional; zero means automatic
\    height = 8                       # optional; zero means automatic
\
\  An installed manifest additionally carries source-sha3, image, and
\  image-sha3 in [package].  Both digests are 64 lowercase hex bytes.
\  All paths are bounded canonical absolute MP64FS paths.  Every path
\  component is at most 23 bytes and dot traversal is rejected.
\
\  Returned strings borrow the caller's TOML document.  MFT-FREE owns
\  only the heap descriptor; callers retain the document until finished.
\
\  Public API:
\    MFT-PARSE               ( doc-a doc-u -- mft status )
\    MFT-FREE                ( mft -- )
\    MFT-VALIDATE-PROJECT    ( mft -- status )
\    MFT-VALIDATE-INSTALLED  ( mft -- status )
\    MFT-* accessors below
\ =====================================================================

PROVIDED akashic-tui-app-manifest

REQUIRE ../utils/toml.f

\ ---------------------------------------------------------------------
\ Status values
\ ---------------------------------------------------------------------

   0 CONSTANT MFT-S-OK
-110 CONSTANT MFT-E-NO-PACKAGE
-111 CONSTANT MFT-E-NO-APP
-112 CONSTANT MFT-E-MISSING
-113 CONSTANT MFT-E-TYPE
-114 CONSTANT MFT-E-BOUNDS
-115 CONSTANT MFT-E-FORMAT
-116 CONSTANT MFT-E-TRUST
-117 CONSTANT MFT-E-DIGEST
-118 CONSTANT MFT-E-ABI
-119 CONSTANT MFT-E-ALLOC

1   CONSTANT MFT-FORMAT-VERSION
255 CONSTANT MFT-PATH-MAX
23  CONSTANT MFT-COMPONENT-MAX
63  CONSTANT MFT-ID-MAX
63  CONSTANT MFT-TITLE-MAX
31  CONSTANT MFT-VERSION-MAX
23  CONSTANT MFT-ENTRY-MAX
64  CONSTANT MFT-DIGEST-HEX-LEN

\ ---------------------------------------------------------------------
\ Descriptor - 32 cells / 256 bytes
\ ---------------------------------------------------------------------

  0 CONSTANT _MFT-O-DOC-A
  8 CONSTANT _MFT-O-DOC-U
 16 CONSTANT _MFT-O-FORMAT
 24 CONSTANT _MFT-O-ABI
 32 CONSTANT _MFT-O-WIDTH
 40 CONSTANT _MFT-O-HEIGHT
 48 CONSTANT _MFT-O-ID-A
 56 CONSTANT _MFT-O-ID-U
 64 CONSTANT _MFT-O-TITLE-A
 72 CONSTANT _MFT-O-TITLE-U
 80 CONSTANT _MFT-O-VERSION-A
 88 CONSTANT _MFT-O-VERSION-U
 96 CONSTANT _MFT-O-ENTRY-A
104 CONSTANT _MFT-O-ENTRY-U
112 CONSTANT _MFT-O-SOURCE-A
120 CONSTANT _MFT-O-SOURCE-U
128 CONSTANT _MFT-O-SOURCE-HASH-A
136 CONSTANT _MFT-O-SOURCE-HASH-U
144 CONSTANT _MFT-O-IMAGE-A
152 CONSTANT _MFT-O-IMAGE-U
160 CONSTANT _MFT-O-IMAGE-HASH-A
168 CONSTANT _MFT-O-IMAGE-HASH-U
176 CONSTANT _MFT-O-TRUST-A
184 CONSTANT _MFT-O-TRUST-U
192 CONSTANT _MFT-O-UIDL-A
200 CONSTANT _MFT-O-UIDL-U
256 CONSTANT MFT-SIZE

: _MFT-SET-STR  ( str-a str-u mft offset -- )
    + >R  R@ 8 + !  R> ! ;

: _MFT-GET-STR  ( mft offset -- str-a str-u )
    + DUP @ SWAP 8 + @ ;

: MFT-DOCUMENT    ( mft -- a u ) _MFT-O-DOC-A _MFT-GET-STR ;
: MFT-ID          ( mft -- a u ) _MFT-O-ID-A _MFT-GET-STR ;
: MFT-TITLE       ( mft -- a u ) _MFT-O-TITLE-A _MFT-GET-STR ;
: MFT-VERSION     ( mft -- a u ) _MFT-O-VERSION-A _MFT-GET-STR ;
: MFT-ENTRY       ( mft -- a u ) _MFT-O-ENTRY-A _MFT-GET-STR ;
: MFT-SOURCE      ( mft -- a u ) _MFT-O-SOURCE-A _MFT-GET-STR ;
: MFT-SOURCE-SHA3 ( mft -- a u ) _MFT-O-SOURCE-HASH-A _MFT-GET-STR ;
: MFT-IMAGE       ( mft -- a u ) _MFT-O-IMAGE-A _MFT-GET-STR ;
: MFT-IMAGE-SHA3  ( mft -- a u ) _MFT-O-IMAGE-HASH-A _MFT-GET-STR ;
: MFT-TRUST       ( mft -- a u ) _MFT-O-TRUST-A _MFT-GET-STR ;
: MFT-UIDL-FILE   ( mft -- a u ) _MFT-O-UIDL-A _MFT-GET-STR ;
: MFT-FORMAT      ( mft -- n ) _MFT-O-FORMAT + @ ;
: MFT-ABI         ( mft -- n ) _MFT-O-ABI + @ ;
: MFT-WIDTH       ( mft -- n ) _MFT-O-WIDTH + @ ;
: MFT-HEIGHT      ( mft -- n ) _MFT-O-HEIGHT + @ ;

\ Compatibility names for the abandoned prototype.  Their meaning is
\ now exact: NAME is the stable component ID and BINARY is the image path.
: MFT-NAME        ( mft -- a u ) MFT-ID ;
: MFT-BINARY      ( mft -- a u ) MFT-IMAGE ;
: MFT-DEP?        ( mft key-a key-u -- false ) 2DROP DROP 0 ;

\ ---------------------------------------------------------------------
\ Bounded scalar readers
\ ---------------------------------------------------------------------

VARIABLE _mft-current
VARIABLE _mft-status
VARIABLE _mft-doc-a
VARIABLE _mft-doc-u
VARIABLE _mft-package-a
VARIABLE _mft-package-u
VARIABLE _mft-app-a
VARIABLE _mft-app-u

VARIABLE _mfr-body-a
VARIABLE _mfr-body-u
VARIABLE _mfr-key-a
VARIABLE _mfr-key-u
VARIABLE _mfr-offset
VARIABLE _mfr-limit

: _MFT-FAIL  ( status -- )
    _mft-status @ 0= IF _mft-status ! ELSE DROP THEN ;

: _MFT-READ-STRING  ( body-a body-u key-a key-u offset limit required -- )
    >R
    _mfr-limit ! _mfr-offset ! _mfr-key-u ! _mfr-key-a !
    _mfr-body-u ! _mfr-body-a !
    _mft-status @ IF R> DROP EXIT THEN
    _mfr-body-a @ _mfr-body-u @ _mfr-key-a @ _mfr-key-u @ TOML-KEY?
    0= IF
        2DROP R> IF MFT-E-MISSING _MFT-FAIL THEN EXIT
    THEN
    R> DROP
    2DUP TOML-STRING? 0= IF 2DROP MFT-E-TYPE _MFT-FAIL EXIT THEN
    TOML-GET-STRING
    TOML-OK? 0= IF 2DROP MFT-E-TYPE _MFT-FAIL EXIT THEN
    DUP 0= OVER _mfr-limit @ > OR IF
        2DROP MFT-E-BOUNDS _MFT-FAIL EXIT
    THEN
    _mft-current @ _mfr-offset @ _MFT-SET-STR ;

: _MFT-READ-INT  ( body-a body-u key-a key-u offset required -- )
    >R
    _mfr-offset ! _mfr-key-u ! _mfr-key-a !
    _mfr-body-u ! _mfr-body-a !
    _mft-status @ IF R> DROP EXIT THEN
    _mfr-body-a @ _mfr-body-u @ _mfr-key-a @ _mfr-key-u @ TOML-KEY?
    0= IF
        2DROP R> IF MFT-E-MISSING _MFT-FAIL THEN EXIT
    THEN
    R> DROP
    2DUP TOML-INTEGER? 0= IF 2DROP MFT-E-TYPE _MFT-FAIL EXIT THEN
    TOML-GET-INT _mft-current @ _mfr-offset @ + ! ;

\ ---------------------------------------------------------------------
\ Contract validation
\ ---------------------------------------------------------------------

: _MFT-SAFE-ATOM?  ( a u max -- flag )
    >R
    DUP 0= OVER R> > OR IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@
        DUP [CHAR] a >= OVER [CHAR] z <= AND
        OVER [CHAR] A >= OVER [CHAR] Z <= AND OR
        OVER [CHAR] 0 >= OVER [CHAR] 9 <= AND OR
        OVER [CHAR] . = OR OVER [CHAR] - = OR SWAP [CHAR] _ = OR
        0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _MFT-SAFE-TITLE?  ( a u -- flag )
    DUP 0= OVER MFT-TITLE-MAX > OR IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ DUP 32 < OVER 126 > OR
        OVER [CHAR] " = OR SWAP [CHAR] \ = OR IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

VARIABLE _mfp-a
VARIABLE _mfp-u
VARIABLE _mfp-start

: _MFT-PATH-CHAR?  ( c -- flag )
    DUP [CHAR] a >= OVER [CHAR] z <= AND
    OVER [CHAR] A >= OVER [CHAR] Z <= AND OR
    OVER [CHAR] 0 >= OVER [CHAR] 9 <= AND OR
    OVER [CHAR] . = OR OVER [CHAR] - = OR
    OVER [CHAR] _ = OR SWAP [CHAR] / = OR ;

: _MFT-PATH-COMPONENT?  ( end -- flag )
    _mfp-start @ - DUP 0= OVER MFT-COMPONENT-MAX > OR IF DROP 0 EXIT THEN
    DUP 1 = IF
        _mfp-a @ _mfp-start @ + C@ [CHAR] . = IF DROP 0 EXIT THEN
    THEN
    DUP 2 = IF
        _mfp-a @ _mfp-start @ + C@ [CHAR] . =
        _mfp-a @ _mfp-start @ + 1+ C@ [CHAR] . = AND IF
            DROP 0 EXIT
        THEN
    THEN
    DROP -1 ;

: _MFT-SAFE-PATH?  ( a u -- flag )
    _mfp-u ! _mfp-a !
    _mfp-u @ 2 < _mfp-u @ MFT-PATH-MAX > OR IF 0 EXIT THEN
    _mfp-a @ C@ [CHAR] / <> IF 0 EXIT THEN
    1 _mfp-start !
    _mfp-u @ 1 DO
        _mfp-a @ I + C@ DUP _MFT-PATH-CHAR? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        [CHAR] / = IF
            I _MFT-PATH-COMPONENT? 0= IF 0 UNLOOP EXIT THEN
            I 1+ _mfp-start !
        THEN
    LOOP
    _mfp-u @ _MFT-PATH-COMPONENT? ;

: _MFT-HEX-DIGEST?  ( a u -- flag )
    MFT-DIGEST-HEX-LEN <> IF DROP 0 EXIT THEN
    MFT-DIGEST-HEX-LEN 0 DO
        DUP I + C@
        DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND
        SWAP DUP [CHAR] a >= SWAP [CHAR] f <= AND OR
        0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _MFT-VALIDATE-COMMON  ( mft -- status )
    DUP 0= IF DROP MFT-E-BOUNDS EXIT THEN
    DUP MFT-FORMAT MFT-FORMAT-VERSION <> IF DROP MFT-E-FORMAT EXIT THEN
    DUP MFT-ABI 1 <> IF DROP MFT-E-ABI EXIT THEN
    DUP MFT-TRUST S" local" COMPARE 0<> IF DROP MFT-E-TRUST EXIT THEN
    DUP MFT-ID MFT-ID-MAX _MFT-SAFE-ATOM? 0= IF DROP MFT-E-BOUNDS EXIT THEN
    DUP MFT-VERSION MFT-VERSION-MAX _MFT-SAFE-ATOM? 0= IF
        DROP MFT-E-BOUNDS EXIT
    THEN
    DUP MFT-ENTRY MFT-ENTRY-MAX _MFT-SAFE-ATOM? 0= IF
        DROP MFT-E-BOUNDS EXIT
    THEN
    DUP MFT-TITLE _MFT-SAFE-TITLE? 0= IF DROP MFT-E-BOUNDS EXIT THEN
    DUP MFT-WIDTH 0< OVER MFT-WIDTH 4096 > OR IF DROP MFT-E-BOUNDS EXIT THEN
    DUP MFT-HEIGHT 0< OVER MFT-HEIGHT 4096 > OR IF DROP MFT-E-BOUNDS EXIT THEN
    DUP MFT-SOURCE _MFT-SAFE-PATH? 0= IF DROP MFT-E-BOUNDS EXIT THEN
    DUP MFT-UIDL-FILE DUP IF
        _MFT-SAFE-PATH? 0= IF DROP MFT-E-BOUNDS EXIT THEN
    ELSE 2DROP THEN
    DROP MFT-S-OK ;

: MFT-VALIDATE-PROJECT  ( mft -- status )
    _MFT-VALIDATE-COMMON ;

: MFT-VALIDATE-INSTALLED  ( mft -- status )
    DUP _MFT-VALIDATE-COMMON DUP IF NIP EXIT THEN DROP
    DUP MFT-SOURCE-SHA3 _MFT-HEX-DIGEST? 0= IF DROP MFT-E-DIGEST EXIT THEN
    DUP MFT-IMAGE _MFT-SAFE-PATH? 0= IF DROP MFT-E-BOUNDS EXIT THEN
    MFT-IMAGE-SHA3 _MFT-HEX-DIGEST? 0= IF MFT-E-DIGEST EXIT THEN
    MFT-S-OK ;

\ ---------------------------------------------------------------------
\ Parser
\ ---------------------------------------------------------------------

: _MFT-PARSE-BODY  ( -- )
    _mft-doc-a @ _mft-doc-u @ S" package" TOML-FIND-TABLE?
    0= IF 2DROP MFT-E-NO-PACKAGE _MFT-FAIL EXIT THEN
    _mft-package-u ! _mft-package-a !
    _mft-doc-a @ _mft-doc-u @ S" app" TOML-FIND-TABLE?
    0= IF 2DROP MFT-E-NO-APP _MFT-FAIL EXIT THEN
    _mft-app-u ! _mft-app-a !

    _mft-package-a @ _mft-package-u @ S" format"
        _MFT-O-FORMAT -1 _MFT-READ-INT
    _mft-package-a @ _mft-package-u @ S" trust"
        _MFT-O-TRUST-A 15 -1 _MFT-READ-STRING
    _mft-package-a @ _mft-package-u @ S" source"
        _MFT-O-SOURCE-A MFT-PATH-MAX -1 _MFT-READ-STRING
    _mft-package-a @ _mft-package-u @ S" source-sha3"
        _MFT-O-SOURCE-HASH-A MFT-DIGEST-HEX-LEN 0 _MFT-READ-STRING
    _mft-package-a @ _mft-package-u @ S" image"
        _MFT-O-IMAGE-A MFT-PATH-MAX 0 _MFT-READ-STRING
    _mft-package-a @ _mft-package-u @ S" image-sha3"
        _MFT-O-IMAGE-HASH-A MFT-DIGEST-HEX-LEN 0 _MFT-READ-STRING

    _mft-app-a @ _mft-app-u @ S" id"
        _MFT-O-ID-A MFT-ID-MAX -1 _MFT-READ-STRING
    _mft-app-a @ _mft-app-u @ S" version"
        _MFT-O-VERSION-A MFT-VERSION-MAX -1 _MFT-READ-STRING
    _mft-app-a @ _mft-app-u @ S" abi"
        _MFT-O-ABI -1 _MFT-READ-INT
    _mft-app-a @ _mft-app-u @ S" entry"
        _MFT-O-ENTRY-A MFT-ENTRY-MAX -1 _MFT-READ-STRING
    _mft-app-a @ _mft-app-u @ S" title"
        _MFT-O-TITLE-A MFT-TITLE-MAX 0 _MFT-READ-STRING
    _mft-app-a @ _mft-app-u @ S" width"
        _MFT-O-WIDTH 0 _MFT-READ-INT
    _mft-app-a @ _mft-app-u @ S" height"
        _MFT-O-HEIGHT 0 _MFT-READ-INT
    _mft-app-a @ _mft-app-u @ S" uidl-file"
        _MFT-O-UIDL-A MFT-PATH-MAX 0 _MFT-READ-STRING

    _mft-status @ 0= IF
        _mft-current @ MFT-TITLE NIP 0= IF
            _mft-current @ MFT-ID
            _mft-current @ _MFT-O-TITLE-A _MFT-SET-STR
        THEN
    THEN ;

: MFT-PARSE  ( doc-a doc-u -- mft status )
    _mft-doc-u ! _mft-doc-a !
    0 _mft-status ! 0 _mft-current !
    _mft-doc-a @ 0= _mft-doc-u @ 1 < OR IF 0 MFT-E-BOUNDS EXIT THEN
    MFT-SIZE ALLOCATE DUP IF 2DROP 0 MFT-E-ALLOC EXIT THEN
    DROP DUP _mft-current ! MFT-SIZE 0 FILL
    _mft-doc-a @ _mft-doc-u @ _mft-current @ _MFT-O-DOC-A _MFT-SET-STR
    _MFT-PARSE-BODY
    _mft-status @ 0= IF
        _mft-current @ MFT-VALIDATE-PROJECT _mft-status !
    THEN
    _mft-status @ DUP IF
        >R _mft-current @ FREE 0 _mft-current ! 0 R>
    ELSE
        DROP _mft-current @ MFT-S-OK
    THEN ;

: MFT-FREE  ( mft -- )
    ?DUP IF FREE THEN ;

\ Manifest parsing owns only short metadata critical sections.  It performs
\ no file I/O and never yields, so guard wrapping is valid.
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _mft-guard

' MFT-PARSE CONSTANT _mft-parse-xt
' MFT-VALIDATE-PROJECT CONSTANT _mft-project-xt
' MFT-VALIDATE-INSTALLED CONSTANT _mft-installed-xt

: MFT-PARSE _mft-parse-xt _mft-guard WITH-GUARD ;
: MFT-VALIDATE-PROJECT _mft-project-xt _mft-guard WITH-GUARD ;
: MFT-VALIDATE-INSTALLED _mft-installed-xt _mft-guard WITH-GUARD ;
[THEN] [THEN]
