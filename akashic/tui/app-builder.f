\ =====================================================================
\  app-builder.f - trusted-local source -> image -> catalog transaction
\ =====================================================================
\
\  This is a developer workflow for native local Forth, not a sandbox.
\  The source is compiled with MegaPad's checked evaluator, serialized as
\  a v2 named-export image, and then removed from the live dictionary.
\  Immutable content-addressed image and installed-manifest files are
\  published first.  The durable catalog upsert is the final commit point.
\
\  Public API:
\    ABUILD-CATALOG!       ( catalog -- )
\    ABUILD-INSTALL        ( project-path-a project-path-u -- entry status )
\    ABUILD-LAST-STATUS    ( -- status )
\    ABUILD-LAST-DETAIL    ( -- detail )
\    ABUILD-EVAL-STATUS    ( -- status )
\    ABUILD-EVAL-LINE      ( -- line )
\    ABUILD-EVAL-COLUMN    ( -- column )
\    ABUILD-EVAL-THROW     ( -- throw-code )
\    ABUILD-EVAL-TOKEN     ( -- addr len )
\    ABUILD-SOURCE-PATH    ( -- addr len )
\    ABUILD-INSTALLED-PATH ( -- addr len )
\
\  A successful return owns no temporary buffers.  The returned catalog
\  entry is stable until the next catalog mutation.  Failed compilation
\  preserves evaluator diagnostics while rolling HERE/LATEST back through
\  IMG-DISCARD.  Native source may still perform arbitrary ambient side
\  effects while it is evaluated; trusted-local is the security boundary.
\ =====================================================================

PROVIDED akashic-tui-app-builder

REQUIRE app-manifest.f
REQUIRE app-catalog.f
REQUIRE ../utils/binimg.f
REQUIRE ../utils/fmt.f
REQUIRE ../utils/buffer-writer.f
REQUIRE ../utils/fs/vfs-replace.f
REQUIRE ../math/sha3.f

\ ---------------------------------------------------------------------
\ Status values
\ ---------------------------------------------------------------------

   0 CONSTANT ABUILD-S-OK
-200 CONSTANT ABUILD-E-SETUP
-201 CONSTANT ABUILD-E-BUSY
-202 CONSTANT ABUILD-E-IO
-203 CONSTANT ABUILD-E-BOUNDS
-204 CONSTANT ABUILD-E-NOMEM
-205 CONSTANT ABUILD-E-MANIFEST
-206 CONSTANT ABUILD-E-COMPILE
-207 CONSTANT ABUILD-E-ENTRY
-208 CONSTANT ABUILD-E-IMAGE
-209 CONSTANT ABUILD-E-SERIALIZE
-210 CONSTANT ABUILD-E-COLLISION
-211 CONSTANT ABUILD-E-PUBLISH
-212 CONSTANT ABUILD-E-CATALOG
-213 CONSTANT ABUILD-E-THROW

4096   CONSTANT ABUILD-MANIFEST-MAX
524288 CONSTANT ABUILD-SOURCE-MAX
4096   CONSTANT _AB-MANIFEST-BUF-MAX
1024   CONSTANT _AB-CHECK-BUF-SIZE

\ Internal result from immutable-file probing.
1 CONSTANT _AB-PUB-MISSING

\ ---------------------------------------------------------------------
\ Operation state
\ ---------------------------------------------------------------------

VARIABLE _ab-catalog
VARIABLE _ab-busy
VARIABLE _ab-status
VARIABLE _ab-detail
VARIABLE _ab-result
VARIABLE _ab-path-a
VARIABLE _ab-path-u

VARIABLE _ab-project-a
VARIABLE _ab-project-u
VARIABLE _ab-project-mft
VARIABLE _ab-source-a
VARIABLE _ab-source-u
VARIABLE _ab-image-a
VARIABLE _ab-image-u
VARIABLE _ab-image-cap
VARIABLE _ab-installed-mft
VARIABLE _ab-marked
VARIABLE _ab-eval-depth
VARIABLE _ab-eval-saved
VARIABLE _ab-fd

CREATE _ab-source-digest   SHA3-256-LEN ALLOT
CREATE _ab-image-digest    SHA3-256-LEN ALLOT
CREATE _ab-manifest-digest SHA3-256-LEN ALLOT
CREATE _ab-source-hex      64 ALLOT
CREATE _ab-image-hex       64 ALLOT
CREATE _ab-image-path      24 ALLOT
CREATE _ab-manifest-path   24 ALLOT
VARIABLE _ab-image-path-u
VARIABLE _ab-manifest-path-u
CREATE _ab-source-path MFT-PATH-MAX ALLOT
VARIABLE _ab-source-path-u

CREATE _ab-manifest-buf _AB-MANIFEST-BUF-MAX ALLOT
CREATE _ab-manifest-writer CBW-SIZE ALLOT
CREATE _ab-check-buf _AB-CHECK-BUF-SIZE ALLOT
CREATE _ab-find-buf 24 ALLOT

: ABUILD-CATALOG!  ( catalog -- ) _ab-catalog ! ;
: ABUILD-LAST-STATUS  ( -- status ) _ab-status @ ;
: ABUILD-LAST-DETAIL  ( -- detail ) _ab-detail @ ;
: ABUILD-EVAL-STATUS  ( -- status ) EVAL-STATUS @ ;
: ABUILD-EVAL-LINE    ( -- line ) EVAL-LINE @ ;
: ABUILD-EVAL-COLUMN  ( -- column ) EVAL-COLUMN @ ;
: ABUILD-EVAL-THROW   ( -- throw-code ) EVAL-THROW @ ;
: ABUILD-EVAL-TOKEN   ( -- addr len ) EVAL-TOKEN ;
: ABUILD-SOURCE-PATH  ( -- addr len )
    _ab-source-path _ab-source-path-u @ ;
: ABUILD-INSTALLED-PATH  ( -- addr len )
    _ab-manifest-path _ab-manifest-path-u @ ;

: _AB-CAPTURE-SOURCE-PATH  ( -- )
    _ab-project-mft @ MFT-SOURCE
    DUP _ab-source-path-u !
    _ab-source-path SWAP CMOVE ;

: _AB-FAIL  ( detail public-status -- public-status )
    SWAP _ab-detail ! ;

: _AB-FREE-VAR  ( variable-address -- )
    DUP @ ?DUP IF FREE THEN
    0 SWAP ! ;

: _AB-CLOSE-FD  ( -- )
    _ab-fd @ ?DUP IF VFS-CLOSE 0 _ab-fd ! THEN ;

: _AB-RESET-EVALUATOR  ( -- )
    EVALUATOR-RESET
    _ab-eval-saved @ IF _ab-eval-depth @ EVAL-DEPTH ! THEN ;

\ ---------------------------------------------------------------------
\ Bounded exact VFS read
\ ---------------------------------------------------------------------

VARIABLE _abr-a
VARIABLE _abr-u
VARIABLE _abr-cap
VARIABLE _abr-size
VARIABLE _abr-buf

: _AB-READ-FILE  ( path-a path-u cap -- buffer length status )
    _abr-cap ! _abr-u ! _abr-a !
    0 _abr-buf ! 0 _ab-fd !
    _abr-a @ _abr-u @ VFS-OPEN DUP _ab-fd !
    0= IF 0 0 ABUILD-E-IO EXIT THEN
    _ab-fd @ VFS-SIZE DUP _abr-size !
    1 < _abr-size @ _abr-cap @ > OR IF
        _AB-CLOSE-FD 0 0 ABUILD-E-BOUNDS EXIT
    THEN
    _abr-size @ ALLOCATE DUP IF
        2DROP _AB-CLOSE-FD 0 0 ABUILD-E-NOMEM EXIT
    THEN
    DROP _abr-buf !
    _abr-buf @ _abr-size @ _ab-fd @ VFS-READ-EXACT IF
        _AB-CLOSE-FD _abr-buf @ FREE 0 _abr-buf !
        0 0 ABUILD-E-IO EXIT
    THEN
    _AB-CLOSE-FD
    _abr-buf @ _abr-size @ ABUILD-S-OK
    0 _abr-buf ! ;

\ ---------------------------------------------------------------------
\ Safe dictionary lookup for binding a just-compiled marked export
\ ---------------------------------------------------------------------

: _AB-FIND-WORD  ( addr len -- xt flag )
    DUP 0= OVER 23 > OR IF 2DROP 0 0 EXIT THEN
    DUP _ab-find-buf C!
    _ab-find-buf 1+ SWAP CMOVE
    _ab-find-buf FIND
    DUP 0= IF NIP 0 THEN ;

\ ---------------------------------------------------------------------
\ Installed-manifest serializer
\ ---------------------------------------------------------------------

: _AB-SERIAL-RESET  ( -- writer-status )
    _ab-manifest-buf _AB-MANIFEST-BUF-MAX
        _ab-manifest-writer CBW-INIT ;

: _AB-APPEND  ( addr len -- )
    _ab-manifest-writer CBW-APPEND DROP ;

: _AB-CHAR+  ( c -- )
    _ab-manifest-writer CBW-CHAR DROP ;

: _AB-NL  ( -- ) 10 _AB-CHAR+ ;

: _AB-QUOTED  ( addr len -- )
    [CHAR] " _AB-CHAR+ _AB-APPEND [CHAR] " _AB-CHAR+ _AB-NL ;

: _AB-NUMBER-LINE  ( prefix-a prefix-u n -- )
    >R _AB-APPEND R> _ab-manifest-writer CBW-NUMBER DROP _AB-NL ;

: _AB-SERIAL-STATUS  ( -- status )
    _ab-manifest-writer CBW-STATUS@
    IF ABUILD-E-SERIALIZE ELSE ABUILD-S-OK THEN ;

: _AB-SERIALIZE-INSTALLED  ( -- status )
    _AB-SERIAL-RESET IF ABUILD-E-SERIALIZE EXIT THEN
    S" [package]" _AB-APPEND _AB-NL
    S" format = " 1 _AB-NUMBER-LINE
    S" trust = " _AB-APPEND S" local" _AB-QUOTED
    S" source = " _AB-APPEND
        _ab-project-mft @ MFT-SOURCE _AB-QUOTED
    S" source-sha3 = " _AB-APPEND _ab-source-hex 64 _AB-QUOTED
    S" image = " _AB-APPEND
        _ab-image-path _ab-image-path-u @ _AB-QUOTED
    S" image-sha3 = " _AB-APPEND _ab-image-hex 64 _AB-QUOTED
    _AB-NL
    S" [app]" _AB-APPEND _AB-NL
    S" id = " _AB-APPEND
        _ab-project-mft @ MFT-ID _AB-QUOTED
    S" title = " _AB-APPEND
        _ab-project-mft @ MFT-TITLE _AB-QUOTED
    S" version = " _AB-APPEND
        _ab-project-mft @ MFT-VERSION _AB-QUOTED
    S" abi = " 1 _AB-NUMBER-LINE
    S" entry = " _AB-APPEND
        _ab-project-mft @ MFT-ENTRY _AB-QUOTED
    S" width = " _ab-project-mft @ MFT-WIDTH _AB-NUMBER-LINE
    S" height = " _ab-project-mft @ MFT-HEIGHT _AB-NUMBER-LINE
    _ab-project-mft @ MFT-UIDL-FILE DUP IF
        S" uidl-file = " _AB-APPEND _AB-QUOTED
    ELSE
        2DROP
    THEN
    _AB-SERIAL-STATUS ;

\ ---------------------------------------------------------------------
\ Content-addressed names
\ ---------------------------------------------------------------------

: _AB-MAKE-IMAGE-PATH  ( -- )
    S" /.i" _ab-image-path SWAP CMOVE
    _ab-image-digest 6 _ab-image-path 3 + FMT->HEX DROP
    S" .m64" _ab-image-path 15 + SWAP CMOVE
    19 _ab-image-path-u ! ;

: _AB-MAKE-MANIFEST-PATH  ( -- )
    S" /.m" _ab-manifest-path SWAP CMOVE
    _ab-manifest-digest 6 _ab-manifest-path 3 + FMT->HEX DROP
    S" .toml" _ab-manifest-path 15 + SWAP CMOVE
    20 _ab-manifest-path-u ! ;

\ ---------------------------------------------------------------------
\ Immutable publication
\ ---------------------------------------------------------------------

VARIABLE _abp-data
VARIABLE _abp-u
VARIABLE _abp-path-a
VARIABLE _abp-path-u
VARIABLE _abp-off
VARIABLE _abp-chunk
CREATE _ab-repl VREPL-SIZE ALLOT

: _AB-CHECK-EXISTING  ( -- status )
    0 _ab-fd !
    _abp-path-a @ _abp-path-u @ VFS-OPEN DUP _ab-fd !
    0= IF _AB-PUB-MISSING EXIT THEN
    _ab-fd @ VFS-SIZE _abp-u @ <> IF
        _AB-CLOSE-FD ABUILD-E-COLLISION EXIT
    THEN
    0 _abp-off !
    BEGIN _abp-off @ _abp-u @ < WHILE
        _abp-u @ _abp-off @ - _AB-CHECK-BUF-SIZE MIN
        DUP _abp-chunk !
        _ab-check-buf SWAP _ab-fd @ VFS-READ-EXACT IF
            _AB-CLOSE-FD ABUILD-E-IO EXIT
        THEN
        _ab-check-buf _abp-chunk @
        _abp-data @ _abp-off @ + _abp-chunk @ COMPARE IF
            _AB-CLOSE-FD ABUILD-E-COLLISION EXIT
        THEN
        _abp-chunk @ _abp-off +!
    REPEAT
    _AB-CLOSE-FD ABUILD-S-OK ;

: _AB-REPL-USABLE?  ( status -- flag )
    DUP VREPL-S-OK =
    OVER VREPL-S-ROLLED-BACK = OR
    SWAP VREPL-S-COMMITTED-CLEANUP = OR ;

: _AB-PUBLISH-IMMUTABLE  ( data-a data-u path-a path-u -- status )
    _abp-path-u ! _abp-path-a ! _abp-u ! _abp-data !
    _AB-CHECK-EXISTING DUP ABUILD-S-OK = IF EXIT THEN
    DUP _AB-PUB-MISSING <> IF EXIT THEN DROP
    VFS-CUR _ab-repl VREPL-INIT DUP IF EXIT THEN DROP
    _abp-path-a @ _abp-path-u @ _ab-repl VREPL-DERIVE-PATHS!
    DUP IF EXIT THEN DROP
    _ab-repl VREPL-RECOVER DUP _AB-REPL-USABLE? 0= IF EXIT THEN DROP
    _abp-data @ _abp-u @ _ab-repl VREPL-REPLACE
    DUP VREPL-S-OK = OVER VREPL-S-COMMITTED-CLEANUP = OR IF
        DROP ABUILD-S-OK
    THEN ;

\ ---------------------------------------------------------------------
\ Build body and cleanup
\ ---------------------------------------------------------------------

VARIABLE _ab-max
VARIABLE _ab-entry-xt

: _AB-INSTALL-BODY  ( -- status )
    _ab-catalog @ 0= IF ABUILD-E-SETUP EXIT THEN

    _ab-path-a @ _ab-path-u @ ABUILD-MANIFEST-MAX _AB-READ-FILE
    DUP IF >R 2DROP R> EXIT THEN
    DROP _ab-project-u ! _ab-project-a !

    _ab-project-a @ _ab-project-u @ MFT-PARSE
    DUP IF ABUILD-E-MANIFEST _AB-FAIL >R DROP R> EXIT THEN
    DROP _ab-project-mft !
    _ab-project-mft @ MFT-VALIDATE-PROJECT DUP IF
        ABUILD-E-MANIFEST _AB-FAIL EXIT
    THEN DROP

    _AB-CAPTURE-SOURCE-PATH
    _ab-source-path _ab-source-path-u @ ABUILD-SOURCE-MAX _AB-READ-FILE
    DUP IF >R 2DROP R> EXIT THEN
    DROP _ab-source-u ! _ab-source-a !
    _ab-source-a @ _ab-source-u @ _ab-source-digest SHA3-256-HASH
    _ab-source-digest 32 _ab-source-hex FMT->HEX DROP

    EVAL-DEPTH @ _ab-eval-depth ! -1 _ab-eval-saved !
    \ Reset the sticky nested-evaluator gate at the start of a new build;
    \ the previous operation's diagnostics remained readable until now.
    0 EVAL-STATUS ! 0 EVAL-THROW !
    IMG-MARK -1 _ab-marked !
    _ab-source-a @ _ab-source-u @ SOURCE-EVALUATE-CHECKED
    DUP IF ABUILD-E-COMPILE _AB-FAIL EXIT THEN DROP

    _ab-project-mft @ MFT-ENTRY _AB-FIND-WORD
    DUP 0= IF 2DROP ABUILD-E-ENTRY EXIT THEN
    DROP _ab-entry-xt !
    _ab-entry-xt @ _ab-project-mft @ MFT-ENTRY IMG-ENTRY-NAMED
    DUP IF ABUILD-E-ENTRY _AB-FAIL EXIT THEN DROP

    IMG-BUFFER-MAX
    DUP IF ABUILD-E-IMAGE _AB-FAIL >R DROP R> EXIT THEN
    DROP DUP _ab-max !
    ALLOCATE DUP IF
        2DROP ABUILD-E-NOMEM EXIT
    THEN
    DROP _ab-image-a ! _ab-max @ _ab-image-cap !
    _ab-image-a @ _ab-image-cap @ IMG-BUILD-INTO
    DUP IF ABUILD-E-IMAGE _AB-FAIL >R DROP R> EXIT THEN
    DROP _ab-image-u !

    IMG-DISCARD DUP IF ABUILD-E-IMAGE _AB-FAIL EXIT THEN
    DROP 0 _ab-marked ! _AB-RESET-EVALUATOR

    _ab-image-a @ _ab-image-u @ _ab-image-digest SHA3-256-HASH
    _ab-image-digest 32 _ab-image-hex FMT->HEX DROP
    _AB-MAKE-IMAGE-PATH
    _AB-SERIALIZE-INSTALLED DUP IF EXIT THEN DROP

    _ab-manifest-buf _ab-manifest-writer CBW-LENGTH@ MFT-PARSE
    DUP IF ABUILD-E-SERIALIZE _AB-FAIL >R DROP R> EXIT THEN
    DROP _ab-installed-mft !
    _ab-installed-mft @ MFT-VALIDATE-INSTALLED DUP IF
        ABUILD-E-SERIALIZE _AB-FAIL EXIT
    THEN DROP

    _ab-manifest-buf _ab-manifest-writer CBW-LENGTH@
        _ab-manifest-digest SHA3-256-HASH
    _AB-MAKE-MANIFEST-PATH

    _ab-image-a @ _ab-image-u @
        _ab-image-path _ab-image-path-u @ _AB-PUBLISH-IMMUTABLE
    DUP IF
        DUP ABUILD-E-COLLISION = IF EXIT THEN
        ABUILD-E-PUBLISH _AB-FAIL EXIT
    THEN DROP

    _ab-manifest-buf _ab-manifest-writer CBW-LENGTH@
        _ab-manifest-path _ab-manifest-path-u @ _AB-PUBLISH-IMMUTABLE
    DUP IF
        DUP ABUILD-E-COLLISION = IF EXIT THEN
        ABUILD-E-PUBLISH _AB-FAIL EXIT
    THEN DROP

    _ab-installed-mft @ MFT-ID
    _ab-installed-mft @ MFT-TITLE
    _ab-installed-mft @ MFT-VERSION
    _ab-manifest-path _ab-manifest-path-u @
    ACAT-F-ENABLED ACAT-F-PINNED OR
    _ab-catalog @ ACAT-UPSERT-PACKAGE
    DUP IF ABUILD-E-CATALOG _AB-FAIL EXIT THEN DROP

    _ab-installed-mft @ MFT-ID _ab-catalog @ ACAT-FIND-ID
    DUP 0= IF DROP ABUILD-E-CATALOG EXIT THEN
    _ab-result ! ABUILD-S-OK ;

: _AB-CLEANUP  ( -- )
    _ab-marked @ IF
        IMG-DISCARD DUP IF
            _ab-status @ 0= IF
                DUP _ab-detail ! ABUILD-E-IMAGE _ab-status !
            THEN
        THEN DROP
        0 _ab-marked ! _AB-RESET-EVALUATOR
    THEN
    _AB-CLOSE-FD
    _ab-installed-mft @ ?DUP IF MFT-FREE 0 _ab-installed-mft ! THEN
    _ab-project-mft @ ?DUP IF MFT-FREE 0 _ab-project-mft ! THEN
    _ab-image-a _AB-FREE-VAR
    _ab-source-a _AB-FREE-VAR
    _ab-project-a _AB-FREE-VAR
    _abr-buf _AB-FREE-VAR
    0 _ab-busy ! ;

: _AB-RESET-OP  ( -- )
    0 _ab-status ! 0 _ab-detail ! 0 _ab-result !
    0 _ab-project-a ! 0 _ab-project-u ! 0 _ab-project-mft !
    0 _ab-source-a ! 0 _ab-source-u !
    0 _ab-image-a ! 0 _ab-image-u ! 0 _ab-image-cap !
    0 _ab-installed-mft ! 0 _ab-marked !
    0 _ab-eval-depth ! 0 _ab-eval-saved !
    0 _ab-fd ! 0 _abr-buf !
    0 _ab-image-path-u ! 0 _ab-manifest-path-u ! 0 _ab-source-path-u ! ;

: ABUILD-INSTALL  ( project-path-a project-path-u -- entry status )
    _ab-busy @ IF 2DROP 0 ABUILD-E-BUSY EXIT THEN
    _ab-path-u ! _ab-path-a !
    _AB-RESET-OP -1 _ab-busy !
    ['] _AB-INSTALL-BODY CATCH
    DUP IF
        _ab-detail ! ABUILD-E-THROW _ab-status !
    ELSE
        DROP _ab-status !
    THEN
    _AB-CLEANUP
    _ab-status @ DUP IF 0 SWAP EXIT THEN
    DROP _ab-result @ ABUILD-S-OK ;
