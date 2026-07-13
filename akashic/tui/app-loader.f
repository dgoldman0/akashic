\ =====================================================================
\  app-loader.f - trusted-local installed applet loader
\ =====================================================================
\  Prefix: ALOAD- (public), _ALOAD- (private)
\
\  This loader accepts only validated installed manifests and verified
\  in-memory .m64 images.  Manifest paths and export names are passed as
\  counted strings all the way to VFS and binimg; no textual command or
\  dictionary-name fallback exists.
\
\  The load commit boundary is a successful IMG-LOAD-EXPORT:
\    * every earlier failure restores HERE/LATEST and releases all handles
\      and heap allocations;
\    * entry/descriptor failures after it release the loader-owned APP-DESC
\      but may leave the already verified trusted-local image resident.
\
\  Entry contract: the exact named export receives ( desc -- ).  It runs
\  under CATCH with two sentinels.  A private unwind restores the caller's
\  data stack on every normal/throwing/imbalanced return, including removal
\  of accidental extra outputs.
\
\  Public API:
\    ALOAD-FROM-MFT   ( mft -- desc status )
\    ALOAD-MANIFEST   ( doc-a doc-u -- desc status )
\    ALOAD-PATH       ( path-a path-u -- desc status )
\    ALOAD-DESC-FREE  ( desc -- )
\
\  Synchronous and core-0 only.  This module is intentionally not wrapped
\  in a guard: no guard is held across VFS I/O.
\ =====================================================================

PROVIDED akashic-tui-app-loader

REQUIRE ../utils/fs/vfs.f
REQUIRE ../utils/binimg.f
REQUIRE ../math/sha3.f
REQUIRE app-manifest.f
REQUIRE app-desc.f

\ =====================================================================
\  Status contract and explicit resource caps
\ =====================================================================
\
\  MFT-PARSE / MFT-VALIDATE-INSTALLED errors (-110..-119) propagate
\  unchanged.  Loader-owned statuses occupy the range below.  Entry through
\  presentation failures, plus ALOAD-E-QUARANTINE, are post-load errors:
\  the verified image may be resident, but no descriptor is returned.

   0 CONSTANT ALOAD-S-OK
-120 CONSTANT ALOAD-E-MANIFEST-PATH    \ invalid manifest path argument
-121 CONSTANT ALOAD-E-MANIFEST-OPEN    \ manifest VFS open failed
-122 CONSTANT ALOAD-E-MANIFEST-SIZE    \ empty or over-cap manifest
-123 CONSTANT ALOAD-E-MANIFEST-READ    \ manifest exact read failed
-124 CONSTANT ALOAD-E-ALLOC             \ heap allocation failed
-125 CONSTANT ALOAD-E-IMAGE-OPEN        \ image VFS open failed
-126 CONSTANT ALOAD-E-IMAGE-SIZE        \ empty or over-cap image
-127 CONSTANT ALOAD-E-IMAGE-READ        \ image exact read failed
-128 CONSTANT ALOAD-E-IMAGE-HASH        \ SHA3-256 lowercase hex mismatch
-129 CONSTANT ALOAD-E-IMAGE-VERIFY      \ malformed/unsafe .m64 image
-130 CONSTANT ALOAD-E-EXPORT            \ exact named export absent/invalid
-131 CONSTANT ALOAD-E-IMAGE-LOAD        \ verified image could not be loaded
-132 CONSTANT ALOAD-E-ENTRY-THROW       \ entry raised an exception
-133 CONSTANT ALOAD-E-ENTRY-STACK       \ entry violated ( desc -- )
-134 CONSTANT ALOAD-E-DESC              \ invalid APP-DESC after entry
-135 CONSTANT ALOAD-E-COMPONENT         \ component ID/version mismatch
-136 CONSTANT ALOAD-E-PRESENTATION      \ manifest ABI/presentation mismatch
-137 CONSTANT ALOAD-E-CORE              \ loader called away from core 0
-138 CONSTANT ALOAD-E-UNEXPECTED        \ unexpected throw before load commit
-139 CONSTANT ALOAD-E-QUARANTINE        \ unexpected throw after load commit
-140 CONSTANT ALOAD-E-BUSY              \ recursive/concurrent loader entry

4096    CONSTANT ALOAD-MANIFEST-MAX     \ 4 KiB installed manifest hard cap
1048576 CONSTANT ALOAD-IMAGE-MAX        \ 1 MiB installed image hard cap

\ Private exception used solely to make CATCH restore entry stack effects.
-17391 CONSTANT _ALOAD-X-ENTRY-RETURN

0xA10AD35C13579BDF CONSTANT _ALOAD-SENTINEL-A
0x5E17A10ADEADBEEF CONSTANT _ALOAD-SENTINEL-B

\ =====================================================================
\  Core loader state and ownership cleanup
\ =====================================================================

VARIABLE _aload-mft
VARIABLE _aload-fd
VARIABLE _aload-image-a
VARIABLE _aload-image-u
VARIABLE _aload-desc
VARIABLE _aload-entry-xt
VARIABLE _aload-export-off
VARIABLE _aload-status
VARIABLE _aload-saved-here
VARIABLE _aload-saved-latest
VARIABLE _aload-snapshot-valid
VARIABLE _aload-committed
VARIABLE _aload-busy
VARIABLE _aload-result-desc
VARIABLE _aload-result-status

0 _aload-busy !

VARIABLE _aload-title-a
VARIABLE _aload-title-u
VARIABLE _aload-title-copy
VARIABLE _aload-uidl-a
VARIABLE _aload-uidl-u
VARIABLE _aload-uidl-copy

: _ALOAD-IMAGE-CLEAN  ( -- )
    _aload-fd @ ?DUP IF
        VFS-CLOSE 0 _aload-fd !
    THEN
    _aload-image-a @ ?DUP IF
        FREE 0 _aload-image-a !
    THEN
    0 _aload-image-u ! ;

: _ALOAD-DESC-CLEAN  ( -- )
    _aload-desc @ ?DUP IF
        FREE 0 _aload-desc !
    THEN
    0 _aload-title-copy ! 0 _aload-uidl-copy ! ;

: _ALOAD-ROLLBACK-DICTIONARY  ( -- )
    _aload-saved-here @ HERE <> IF
        _aload-saved-here @ HERE - ALLOT
    THEN
    _aload-saved-latest @ LATEST! ;

: _ALOAD-PRELOAD-FAIL  ( status -- 0 status )
    _aload-status !
    _ALOAD-IMAGE-CLEAN
    _ALOAD-DESC-CLEAN
    _aload-snapshot-valid @ IF _ALOAD-ROLLBACK-DICTIONARY THEN
    0 _aload-snapshot-valid !
    0 _aload-status @ ;

: _ALOAD-POSTLOAD-FAIL  ( status -- 0 status )
    _aload-status !
    _ALOAD-IMAGE-CLEAN
    _ALOAD-DESC-CLEAN
    0 _aload-snapshot-valid !
    0 _aload-status @ ;

\ =====================================================================
\  Exact string and digest helpers
\ =====================================================================

VARIABLE _als-a1
VARIABLE _als-u1
VARIABLE _als-a2
VARIABLE _als-u2

\ Zero-length strings are canonical only as (0 0).  Non-empty strings
\ require non-null addresses before COMPARE is allowed to dereference them.
: _ALOAD-STR=  ( a1 u1 a2 u2 -- flag )
    _als-u2 ! _als-a2 ! _als-u1 ! _als-a1 !
    _als-u1 @ _als-u2 @ <> IF 0 EXIT THEN
    _als-u1 @ 0= IF
        _als-a1 @ 0= _als-a2 @ 0= AND EXIT
    THEN
    _als-a1 @ 0= _als-a2 @ 0= OR IF 0 EXIT THEN
    _als-a1 @ _als-u1 @ _als-a2 @ _als-u2 @ COMPARE 0= ;

: _ALOAD-PAIR-VALID?  ( a u -- flag )
    DUP 0= IF DROP 0= ELSE DROP 0<> THEN ;

CREATE _aload-hash 32 ALLOT
CREATE _aload-hash-hex 64 ALLOT

: _ALOAD-NIBBLE>LOWER  ( n -- c )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] a + THEN ;

: _ALOAD-HASH>LOWER-HEX  ( -- )
    32 0 DO
        _aload-hash I + C@
        DUP 4 RSHIFT _ALOAD-NIBBLE>LOWER
        _aload-hash-hex I 2* + C!
        0x0F AND _ALOAD-NIBBLE>LOWER
        _aload-hash-hex I 2* + 1+ C!
    LOOP ;

: _ALOAD-IMAGE-HASH-OK?  ( -- flag )
    _aload-image-a @ _aload-image-u @ _aload-hash SHA3-256-HASH
    _ALOAD-HASH>LOWER-HEX
    _aload-hash-hex 64 _aload-mft @ MFT-IMAGE-SHA3 _ALOAD-STR= ;

\ =====================================================================
\  VFS exact-read image acquisition
\ =====================================================================

: _ALOAD-READ-IMAGE  ( -- status )
    0 _aload-fd ! 0 _aload-image-a ! 0 _aload-image-u !
    _aload-mft @ MFT-IMAGE VFS-OPEN DUP _aload-fd ! 0= IF
        ALOAD-E-IMAGE-OPEN EXIT
    THEN
    _aload-fd @ VFS-SIZE DUP _aload-image-u !
    DUP 1 < OVER ALOAD-IMAGE-MAX > OR IF
        DROP _ALOAD-IMAGE-CLEAN ALOAD-E-IMAGE-SIZE EXIT
    THEN DROP
    _aload-image-u @ ALLOCATE DUP IF
        2DROP _ALOAD-IMAGE-CLEAN ALOAD-E-ALLOC EXIT
    THEN
    DROP _aload-image-a !
    _aload-image-a @ _aload-image-u @ _aload-fd @ VFS-READ-EXACT
    _aload-status !
    _aload-fd @ VFS-CLOSE 0 _aload-fd !
    _aload-status @ IF
        _ALOAD-IMAGE-CLEAN ALOAD-E-IMAGE-READ EXIT
    THEN
    ALOAD-S-OK ;

\ =====================================================================
\  Loader-owned APP-DESC allocation and manifest copies
\ =====================================================================

: _ALOAD-ALLOC-DESC  ( -- status )
    _aload-mft @ MFT-TITLE _aload-title-u ! _aload-title-a !
    _aload-mft @ MFT-UIDL-FILE _aload-uidl-u ! _aload-uidl-a !
    APP-DESC _aload-title-u @ + _aload-uidl-u @ +
    ALLOCATE DUP IF
        2DROP ALOAD-E-ALLOC EXIT
    THEN
    DROP DUP _aload-desc ! APP-DESC-INIT

    _aload-desc @ APP-DESC + _aload-title-copy !
    _aload-title-a @ _aload-title-copy @ _aload-title-u @ CMOVE
    _aload-title-copy @ _aload-title-u @ + _aload-uidl-copy !
    _aload-uidl-u @ IF
        _aload-uidl-a @ _aload-uidl-copy @ _aload-uidl-u @ CMOVE
    ELSE
        0 _aload-uidl-copy !
    THEN

    \ Seed manifest-owned presentation.  The entry may reinitialize the
    \ descriptor; successful validation below rebinds these owned copies.
    _aload-title-copy @ _aload-desc @ APP.TITLE-A !
    _aload-title-u @ _aload-desc @ APP.TITLE-U !
    _aload-uidl-copy @ _aload-desc @ APP.UIDL-FILE-A !
    _aload-uidl-u @ _aload-desc @ APP.UIDL-FILE-U !
    _aload-mft @ MFT-WIDTH _aload-desc @ APP.WIDTH !
    _aload-mft @ MFT-HEIGHT _aload-desc @ APP.HEIGHT !
    ALOAD-S-OK ;

: _ALOAD-BIND-PRESENTATION  ( -- )
    _aload-title-copy @ _aload-desc @ APP.TITLE-A !
    _aload-title-u @ _aload-desc @ APP.TITLE-U !
    _aload-uidl-copy @ _aload-desc @ APP.UIDL-FILE-A !
    _aload-uidl-u @ _aload-desc @ APP.UIDL-FILE-U !
    _aload-mft @ MFT-WIDTH _aload-desc @ APP.WIDTH !
    _aload-mft @ MFT-HEIGHT _aload-desc @ APP.HEIGHT ! ;

\ =====================================================================
\  Entry call: CATCH + sentinel/depth validation + forced unwind
\ =====================================================================

VARIABLE _aload-entry-depth
VARIABLE _aload-entry-returned
VARIABLE _aload-entry-status
VARIABLE _aload-entry-caught

: _ALOAD-ENTRY-THUNK  ( -- )
    _aload-desc @ _aload-entry-xt @ EXECUTE
    -1 _aload-entry-returned !
    DEPTH _aload-entry-depth @ <> IF
        ALOAD-E-ENTRY-STACK _aload-entry-status !
    ELSE
        DUP _ALOAD-SENTINEL-B <> IF
            ALOAD-E-ENTRY-STACK _aload-entry-status !
        THEN
        OVER _ALOAD-SENTINEL-A <> IF
            ALOAD-E-ENTRY-STACK _aload-entry-status !
        THEN
    THEN
    _ALOAD-X-ENTRY-RETURN THROW ;

: _ALOAD-CALL-ENTRY  ( xt desc -- status )
    _aload-desc ! _aload-entry-xt !
    0 _aload-entry-returned !
    ALOAD-S-OK _aload-entry-status !
    _ALOAD-SENTINEL-A _ALOAD-SENTINEL-B
    DEPTH _aload-entry-depth !
    ['] _ALOAD-ENTRY-THUNK CATCH _aload-entry-caught !
    2DROP
    _aload-entry-returned @ 0= IF ALOAD-E-ENTRY-THROW EXIT THEN
    _aload-entry-caught @ _ALOAD-X-ENTRY-RETURN <> IF
        ALOAD-E-ENTRY-THROW EXIT
    THEN
    _aload-entry-status @ ;

\ =====================================================================
\  Post-entry ABI, identity, and presentation validation
\ =====================================================================

VARIABLE _aload-comp

: _ALOAD-COMPONENT-VALID?  ( -- flag )
    _aload-desc @ APP.COMP-DESC @ DUP _aload-comp !
    DUP COMP.ID-A @ SWAP COMP.ID-U @
    _aload-mft @ MFT-ID _ALOAD-STR= 0= IF 0 EXIT THEN
    _aload-comp @ DUP COMP.VERSION-A @ SWAP COMP.VERSION-U @
    _aload-mft @ MFT-VERSION _ALOAD-STR= ;

: _ALOAD-PRESENTATION-VALID?  ( -- flag )
    _aload-desc @ APP.ABI @ _aload-mft @ MFT-ABI <> IF 0 EXIT THEN
    _aload-desc @ APP.SIZE @ APP-DESC <> IF 0 EXIT THEN
    _aload-desc @ APP.WIDTH @ _aload-mft @ MFT-WIDTH <> IF 0 EXIT THEN
    _aload-desc @ APP.HEIGHT @ _aload-mft @ MFT-HEIGHT <> IF 0 EXIT THEN

    _aload-desc @ DUP APP.TITLE-A @ SWAP APP.TITLE-U @
    _aload-mft @ MFT-TITLE _ALOAD-STR= 0= IF 0 EXIT THEN
    _aload-desc @ DUP APP.UIDL-FILE-A @ SWAP APP.UIDL-FILE-U @
    _aload-mft @ MFT-UIDL-FILE _ALOAD-STR= 0= IF 0 EXIT THEN

    _aload-desc @ DUP APP.UIDL-A @ SWAP APP.UIDL-U @
    _ALOAD-PAIR-VALID? 0= IF 0 EXIT THEN
    _aload-mft @ MFT-UIDL-FILE NIP IF
        _aload-desc @ APP.UIDL-A @ _aload-desc @ APP.UIDL-U @ OR IF
            0 EXIT
        THEN
    THEN
    -1 ;

\ =====================================================================
\  Internal installed-manifest pipeline
\ =====================================================================

: _ALOAD-FROM-MFT-RUN  ( mft -- desc status )
    _aload-mft !
    0 _aload-fd ! 0 _aload-image-a ! 0 _aload-image-u ! 0 _aload-desc !

    _aload-mft @ MFT-VALIDATE-INSTALLED DUP IF
        _ALOAD-PRELOAD-FAIL EXIT
    THEN DROP

    _ALOAD-READ-IMAGE DUP IF _ALOAD-PRELOAD-FAIL EXIT THEN DROP
    _ALOAD-IMAGE-HASH-OK? 0= IF
        ALOAD-E-IMAGE-HASH _ALOAD-PRELOAD-FAIL EXIT
    THEN
    _aload-image-a @ _aload-image-u @ IMG-VERIFY-MEM DUP IF
        DROP ALOAD-E-IMAGE-VERIFY _ALOAD-PRELOAD-FAIL EXIT
    THEN DROP

    _aload-image-a @ _aload-image-u @ _aload-mft @ MFT-ENTRY
    IMG-EXPORT-FIND _aload-status ! _aload-export-off !
    _aload-status @ IF
        ALOAD-E-EXPORT _ALOAD-PRELOAD-FAIL EXIT
    THEN

    _ALOAD-ALLOC-DESC DUP IF _ALOAD-PRELOAD-FAIL EXIT THEN DROP

    _aload-image-a @ _aload-image-u @ _aload-mft @ MFT-ENTRY
    IMG-LOAD-EXPORT _aload-status ! _aload-entry-xt !
    _aload-status @ IF
        ALOAD-E-IMAGE-LOAD _ALOAD-PRELOAD-FAIL EXIT
    THEN
    -1 _aload-committed !
    _ALOAD-IMAGE-CLEAN

    _aload-entry-xt @ _aload-desc @ _ALOAD-CALL-ENTRY DUP IF
        _ALOAD-POSTLOAD-FAIL EXIT
    THEN DROP
    _aload-desc @ APP-DESC-VALID? 0= IF
        ALOAD-E-DESC _ALOAD-POSTLOAD-FAIL EXIT
    THEN
    _ALOAD-COMPONENT-VALID? 0= IF
        ALOAD-E-COMPONENT _ALOAD-POSTLOAD-FAIL EXIT
    THEN
    _ALOAD-PRESENTATION-VALID? 0= IF
        ALOAD-E-PRESENTATION _ALOAD-POSTLOAD-FAIL EXIT
    THEN

    _ALOAD-BIND-PRESENTATION
    0 _aload-snapshot-valid !
    _aload-desc @ ALOAD-S-OK ;

\ =====================================================================
\  Internal borrowed-document pipeline
\ =====================================================================

VARIABLE _alm-mft
VARIABLE _alm-desc
VARIABLE _alm-status
VARIABLE _alm-doc-a
VARIABLE _alm-doc-u

: _ALOAD-MANIFEST-RUN  ( doc-a doc-u -- desc status )
    MFT-PARSE _alm-status ! _alm-mft !
    _alm-status @ IF 0 _alm-status @ EXIT THEN
    _alm-mft @ _ALOAD-FROM-MFT-RUN _alm-status ! _alm-desc !
    _alm-mft @ MFT-FREE 0 _alm-mft !
    _alm-desc @ _alm-status @ ;

\ =====================================================================
\  ALOAD-PATH - bounded VFS exact-read manifest pipeline
\ =====================================================================

VARIABLE _alp-path-a
VARIABLE _alp-path-u
VARIABLE _alp-fd
VARIABLE _alp-doc-a
VARIABLE _alp-doc-u
VARIABLE _alp-desc
VARIABLE _alp-status
VARIABLE _alp-component-start
VARIABLE _alp-path-char

: _ALOAD-MANIFEST-PATH-CHAR?  ( c -- flag )
    _alp-path-char !
    _alp-path-char @ [CHAR] a >= _alp-path-char @ [CHAR] z <= AND
    _alp-path-char @ [CHAR] A >= _alp-path-char @ [CHAR] Z <= AND OR
    _alp-path-char @ [CHAR] 0 >= _alp-path-char @ [CHAR] 9 <= AND OR
    _alp-path-char @ [CHAR] . = OR _alp-path-char @ [CHAR] - = OR
    _alp-path-char @ [CHAR] _ = OR _alp-path-char @ [CHAR] / = OR ;

: _ALOAD-MANIFEST-COMPONENT?  ( end -- flag )
    _alp-component-start @ - DUP 0= OVER MFT-COMPONENT-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP 1 = IF
        _alp-path-a @ _alp-component-start @ + C@ [CHAR] . = IF
            DROP 0 EXIT
        THEN
    THEN
    DUP 2 = IF
        _alp-path-a @ _alp-component-start @ + C@ [CHAR] . =
        _alp-path-a @ _alp-component-start @ + 1+ C@ [CHAR] . = AND IF
            DROP 0 EXIT
        THEN
    THEN
    DROP -1 ;

: _ALOAD-MANIFEST-PATH-VALID?  ( -- flag )
    _alp-path-a @ 0= IF 0 EXIT THEN
    _alp-path-u @ 2 < _alp-path-u @ MFT-PATH-MAX > OR IF 0 EXIT THEN
    _alp-path-a @ C@ [CHAR] / <> IF 0 EXIT THEN
    1 _alp-component-start !
    _alp-path-u @ 1 DO
        _alp-path-a @ I + C@ DUP _ALOAD-MANIFEST-PATH-CHAR? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        [CHAR] / = IF
            I _ALOAD-MANIFEST-COMPONENT? 0= IF 0 UNLOOP EXIT THEN
            I 1+ _alp-component-start !
        THEN
    LOOP
    _alp-path-u @ _ALOAD-MANIFEST-COMPONENT? ;

: _ALOAD-PATH-CLEAN  ( -- )
    _alp-fd @ ?DUP IF VFS-CLOSE 0 _alp-fd ! THEN
    _alp-doc-a @ ?DUP IF FREE 0 _alp-doc-a ! THEN
    0 _alp-doc-u ! ;

: _ALOAD-PATH-RUN  ( -- desc status )
    0 _alp-fd ! 0 _alp-doc-a ! 0 _alp-doc-u !
    _ALOAD-MANIFEST-PATH-VALID? 0= IF
        0 ALOAD-E-MANIFEST-PATH EXIT
    THEN
    _alp-path-a @ _alp-path-u @ VFS-OPEN DUP _alp-fd ! 0= IF
        0 ALOAD-E-MANIFEST-OPEN EXIT
    THEN
    _alp-fd @ VFS-SIZE DUP _alp-doc-u !
    DUP 1 < OVER ALOAD-MANIFEST-MAX > OR IF
        DROP _ALOAD-PATH-CLEAN 0 ALOAD-E-MANIFEST-SIZE EXIT
    THEN DROP
    _alp-doc-u @ ALLOCATE DUP IF
        2DROP _ALOAD-PATH-CLEAN 0 ALOAD-E-ALLOC EXIT
    THEN
    DROP _alp-doc-a !
    _alp-doc-a @ _alp-doc-u @ _alp-fd @ VFS-READ-EXACT _alp-status !
    _alp-fd @ VFS-CLOSE 0 _alp-fd !
    _alp-status @ IF
        _ALOAD-PATH-CLEAN 0 ALOAD-E-MANIFEST-READ EXIT
    THEN
    _alp-doc-a @ _alp-doc-u @ _ALOAD-MANIFEST-RUN
    _alp-status ! _alp-desc !
    _ALOAD-PATH-CLEAN
    _alp-desc @ _alp-status @ ;

\ =====================================================================
\  Public, core-0, non-reentrant ownership boundary
\ =====================================================================

: _ALOAD-MFT-CLEAN  ( -- )
    _alm-mft @ ?DUP IF MFT-FREE 0 _alm-mft ! THEN ;

: _ALOAD-API-RESET  ( -- )
    0 _aload-result-desc ! 0 _aload-result-status !
    HERE _aload-saved-here ! LATEST _aload-saved-latest !
    -1 _aload-snapshot-valid ! 0 _aload-committed !
    0 _aload-mft ! 0 _aload-fd ! 0 _aload-image-a ! 0 _aload-image-u !
    0 _aload-desc ! 0 _aload-entry-xt ! 0 _aload-export-off !
    0 _aload-title-copy ! 0 _aload-uidl-copy !
    0 _alm-mft ! 0 _alm-desc ! 0 _alm-status !
    0 _alm-doc-a ! 0 _alm-doc-u !
    0 _alp-fd ! 0 _alp-doc-a ! 0 _alp-doc-u !
    0 _alp-desc ! 0 _alp-status ! ;

: _ALOAD-UNEXPECTED-CLEAN  ( -- status )
    _aload-committed @ IF
        ALOAD-E-QUARANTINE
    ELSE
        ALOAD-E-UNEXPECTED
    THEN _aload-status !
    _ALOAD-MFT-CLEAN
    _ALOAD-PATH-CLEAN
    _ALOAD-IMAGE-CLEAN
    _ALOAD-DESC-CLEAN
    _aload-snapshot-valid @ _aload-committed @ 0= AND IF
        _ALOAD-ROLLBACK-DICTIONARY
    THEN
    0 _aload-snapshot-valid ! 0 _aload-committed !
    _aload-status @ ;

: _ALOAD-FROM-MFT-THUNK  ( -- )
    _aload-mft @ _ALOAD-FROM-MFT-RUN
    _aload-result-status ! _aload-result-desc ! ;

: _ALOAD-MANIFEST-THUNK  ( -- )
    _alm-doc-a @ _alm-doc-u @ _ALOAD-MANIFEST-RUN
    _aload-result-status ! _aload-result-desc ! ;

: _ALOAD-PATH-THUNK  ( -- )
    _ALOAD-PATH-RUN _aload-result-status ! _aload-result-desc ! ;

: _ALOAD-API-FINISH  ( caught -- desc status )
    DUP 0<> IF
        DROP _ALOAD-UNEXPECTED-CLEAN 0 SWAP
    ELSE
        DROP
        _aload-result-status @ IF
            _aload-snapshot-valid @ _aload-committed @ 0= AND IF
                _ALOAD-ROLLBACK-DICTIONARY
            THEN
        THEN
        _aload-result-desc @ _aload-result-status @
    THEN
    0 _aload-snapshot-valid ! 0 _aload-committed !
    0 _aload-busy ! ;

: ALOAD-FROM-MFT  ( mft -- desc status )
    COREID 0<> IF DROP 0 ALOAD-E-CORE EXIT THEN
    _aload-busy @ IF DROP 0 ALOAD-E-BUSY EXIT THEN
    _ALOAD-API-RESET _aload-mft ! -1 _aload-busy !
    ['] _ALOAD-FROM-MFT-THUNK CATCH _ALOAD-API-FINISH ;

: ALOAD-MANIFEST  ( doc-a doc-u -- desc status )
    COREID 0<> IF 2DROP 0 ALOAD-E-CORE EXIT THEN
    _aload-busy @ IF 2DROP 0 ALOAD-E-BUSY EXIT THEN
    _ALOAD-API-RESET _alm-doc-u ! _alm-doc-a ! -1 _aload-busy !
    ['] _ALOAD-MANIFEST-THUNK CATCH _ALOAD-API-FINISH ;

: ALOAD-PATH  ( manifest-path-a manifest-path-u -- desc status )
    COREID 0<> IF 2DROP 0 ALOAD-E-CORE EXIT THEN
    _aload-busy @ IF 2DROP 0 ALOAD-E-BUSY EXIT THEN
    _ALOAD-API-RESET _alp-path-u ! _alp-path-a ! -1 _aload-busy !
    ['] _ALOAD-PATH-THUNK CATCH _ALOAD-API-FINISH ;

\ Only descriptors returned with ALOAD-S-OK are loader-owned.
: ALOAD-DESC-FREE  ( desc -- )
    ?DUP IF FREE THEN ;
