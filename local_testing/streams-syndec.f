\ Deterministic harness contracts for the retained Streams syndication decoder.

PROVIDED streams-syndec-tests

\ Load syndication-decode.f before this test module.  Keeping the test leaf
\ dependency-free avoids adding one nested EVALUATE level to the deep codec
\ closure on KDOS while still letting the profile resolve both roots.

." [sdt] compiling syndication decoder contracts" CR

VARIABLE _sdt-fails
VARIABLE _sdt-checks
VARIABLE _sdt-depth
VARIABLE _sdt-decoder
VARIABLE _sdt-document-a
VARIABLE _sdt-document-u
VARIABLE _sdt-fd
VARIABLE _sdt-candidate
VARIABLE _sdt-checkpoint

0 CONSTANT _SDTC-BODY-A
8 CONSTANT _SDTC-BODY-U
16 CONSTANT _SDTC-MEDIA
24 CONSTANT _SDTC-RESULT
32 CONSTANT _SDTC-SIZE

CREATE _sdt-context _SDTC-SIZE ALLOT
CREATE _sdt-provider STREAMS-CONFIGURED-PROVIDER-SIZE ALLOT
CREATE _sdt-source RID-SIZE ALLOT
CREATE _sdt-namespace RID-SIZE ALLOT

: _sdt-assert  ( flag -- )
    1 _sdt-checks +! 0= IF
        1 _sdt-fails +! ." SDT ASSERT " _sdt-checks @ . CR
    THEN ;

: _sdt-stack  ( -- )
    DEPTH DUP _sdt-depth @ <> IF
        ." SDT STACK " _sdt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sdt-depth @ = _sdt-assert ;

: _sdt-configure       ( source context -- status ) 2DROP SCONF-S-OK ;
: _sdt-requested$      ( context -- a u ) DROP S" https://feed.example/input" ;
: _sdt-effective$      ( context -- a u ) DROP S" https://feed.example/final" ;
: _sdt-body$           ( context -- a u )
    DUP _SDTC-BODY-A + @ SWAP _SDTC-BODY-U + @ ;
: _sdt-media           ( context -- media ) _SDTC-MEDIA + @ ;
: _sdt-outcome         ( context -- outcome ) DROP 0 ;
: _sdt-detail          ( context -- detail ) DROP 0 ;
: _sdt-http-status     ( context -- status ) DROP 200 ;
: _sdt-result-valid?   ( context -- flag ) _SDTC-RESULT + @ ;
: _sdt-cleanup         ( context -- error ) DROP 0 ;
: _sdt-releasable?     ( context -- flag ) DROP -1 ;
: _sdt-poison          ( error context -- ) 2DROP ;
: _sdt-release         ( context -- status ) DROP SCONF-S-OK ;
: _sdt-start           ( operation context -- step ) 2DROP XIO-STEP-SUCCEEDED ;
: _sdt-poll            ( operation context -- step ) 2DROP XIO-STEP-SUCCEEDED ;
: _sdt-cancel          ( operation context -- ) 2DROP ;
: _sdt-wipe            ( operation context -- ) 2DROP ;

: _sdt-provider-init  ( -- )
    _sdt-context _SDTC-SIZE 0 FILL
    _sdt-provider SCONF-INIT
    _sdt-context _sdt-provider SCONF.CONTEXT !
    ['] _sdt-configure _sdt-provider SCONF.CONFIGURE-XT !
    ['] _sdt-requested$ _sdt-provider SCONF.REQUESTED-XT !
    ['] _sdt-effective$ _sdt-provider SCONF.EFFECTIVE-XT !
    ['] _sdt-body$ _sdt-provider SCONF.BODY-XT !
    ['] _sdt-media _sdt-provider SCONF.MEDIA-KIND-XT !
    ['] _sdt-outcome _sdt-provider SCONF.OUTCOME-XT !
    ['] _sdt-detail _sdt-provider SCONF.DETAIL-XT !
    ['] _sdt-http-status _sdt-provider SCONF.HTTP-STATUS-XT !
    ['] _sdt-result-valid? _sdt-provider SCONF.RESULT-VALID-XT !
    ['] _sdt-cleanup _sdt-provider SCONF.CLEANUP-ERROR-XT !
    ['] _sdt-releasable? _sdt-provider SCONF.RELEASABLE-XT !
    ['] _sdt-poison _sdt-provider SCONF.POISON-XT !
    ['] _sdt-release _sdt-provider SCONF.RELEASE-XT !
    ['] _sdt-start _sdt-provider SCONF.START-XT !
    ['] _sdt-poll _sdt-provider SCONF.POLL-XT !
    ['] _sdt-cancel _sdt-provider SCONF.CANCEL-XT !
    ['] _sdt-wipe _sdt-provider SCONF.WIPE-XT !
    _sdt-provider SCONF-SEAL SCONF-S-OK = _sdt-assert
    _sdt-provider SCONF-VALID? _sdt-assert ;

: _sdt-provider-body!  ( a u media -- )
    _sdt-context _SDTC-MEDIA + !
    _sdt-context _SDTC-BODY-U + !
    _sdt-context _SDTC-BODY-A + !
    -1 _sdt-context _SDTC-RESULT + ! ;

: _sdt-load  ( name-a name-u -- document-a document-u )
    NAMEBUF 24 0 FILL NAMEBUF SWAP CMOVE
    FIND-BY-NAME DUP -1 = ABORT" SDT fixture missing"
    OPEN-BY-SLOT DUP 0= ABORT" SDT fixture open failed"
    DUP _sdt-fd ! FSIZE DUP _sdt-document-u !
    ALLOCATE ABORT" SDT fixture allocation failed"
    DUP _sdt-document-a !
    _sdt-document-u @ _sdt-fd @ FREAD
        _sdt-document-u @ <> ABORT" SDT fixture read failed"
    _sdt-fd @ FCLOSE
    _sdt-document-a @ _sdt-document-u @ ;

: _sdt-document-free  ( -- )
    _sdt-document-a @ ?DUP IF
        DUP _sdt-document-u @ 0 FILL FREE
    THEN
    0 _sdt-document-a ! 0 _sdt-document-u !
    0 _sdt-context _SDTC-BODY-A + !
    0 _sdt-context _SDTC-BODY-U + ! ;

: _sdt-candidate0  ( -- candidate )
    0 _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATE
    DUP 0<> _sdt-assert DUP _sdt-candidate ! ;

: _sdt-native=  ( a u -- flag )
    _sdt-candidate @ OCC.NATIVE-A @
    _sdt-candidate @ OCC.NATIVE-U @ 2SWAP STR-STR= ;

: _sdt-url=  ( a u -- flag )
    _sdt-candidate @ OCC.URL-A @
    _sdt-candidate @ OCC.URL-U @ 2SWAP STR-STR= ;

: _sdt-published=  ( a u -- flag )
    _sdt-candidate @ OCC.PUBLISHED-A @
    _sdt-candidate @ OCC.PUBLISHED-U @ 2SWAP STR-STR= ;

: _sdt-common-candidate  ( expected-format -- )
    _sdt-candidate0 DROP
    _sdt-candidate @ OCC.FORMAT @ = _sdt-assert
    _sdt-candidate @ OCC.NATIVE-KIND @ OCHK-NATIVE-PROVIDER-ID =
        _sdt-assert ;

: _sdt-check-json  ( -- )
    S" jsonfeed-base.json" _sdt-load
    SSOURCE-FORMAT-JSON-FEED _sdt-provider-body!
    \ Explicit selection remains a supported exact-match path.
    SSOURCE-FORMAT-JSON-FEED _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-OK = _sdt-assert
    SSOURCE-FORMAT-AUTO _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-OK = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-RESULT-VALID? _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-FORMAT@
        SSOURCE-FORMAT-JSON-FEED = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATES
        2 = SWAP 0<> AND _sdt-assert
    SYN-FORMAT-JSON-FEED _sdt-common-candidate
    S" jsonfeed:item:stable" _sdt-native= _sdt-assert
    S" https://example.test/items/json-stable" _sdt-url= _sdt-assert
    S" 2026-07-15T10:00:00Z" _sdt-published= _sdt-assert
    _sdt-candidate @ OCC.SUMMARY-U @ 0= _sdt-assert
    _sdt-candidate @ OCC.CONTENT-A @ _sdt-candidate @ OCC.CONTENT-U @
        S" The stable item remains unchanged." STR-STR= _sdt-assert
    0 _sdt-decoder @ STREAMS-SYNDICATION-AUTHOR$
        S" Ada Example" STR-STR= _sdt-assert

    \ Destroy the provider-owned input before applying borrowed candidates.
    _sdt-document-free
    S" jsonfeed:item:stable" _sdt-native= _sdt-assert
    _sdt-source 1 _sdt-namespace 1
        S" https://feed.example/input" _sdt-checkpoint @ OCHK-BEGIN
        OCHK-S-OK = _sdt-assert
    _sdt-source 1 S" https://feed.example/final"
        0 200
        _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATES
        _sdt-checkpoint @ OCHK-APPLY OCHK-S-OK = _sdt-assert
    _sdt-checkpoint @ OCHK-VALID? _sdt-assert
    _sdt-checkpoint @ OCHK.OBSERVATION-COUNT @ 2 = _sdt-assert ;

: _sdt-check-rss  ( -- )
    S" rss-base.xml" _sdt-load
    SSOURCE-FORMAT-RSS _sdt-provider-body!
    SSOURCE-FORMAT-AUTO _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-OK = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATES
        2 = SWAP 0<> AND _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-FORMAT@
        SSOURCE-FORMAT-RSS = _sdt-assert
    SYN-FORMAT-RSS-2 _sdt-common-candidate
    S" rss:item:stable" _sdt-native= _sdt-assert
    S" https://example.test/items/rss-stable" _sdt-url= _sdt-assert
    S" Wed, 15 Jul 2026 10:00:00 GMT" _sdt-published= _sdt-assert
    _sdt-candidate @ OCC.SUMMARY-U @ 0= _sdt-assert
    _sdt-candidate @ OCC.CONTENT-U @ 0> _sdt-assert
    _sdt-candidate @ OCC.MODIFIED-U @ 0= _sdt-assert
    0 _sdt-decoder @ STREAMS-SYNDICATION-AUTHOR$
        S" ada@example.test (Ada Example)" STR-STR= _sdt-assert
    _sdt-document-free ;

: _sdt-check-atom  ( -- )
    S" atom-base.xml" _sdt-load
    SSOURCE-FORMAT-ATOM _sdt-provider-body!
    SSOURCE-FORMAT-AUTO _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-OK = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATES
        2 = SWAP 0<> AND _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-FORMAT@
        SSOURCE-FORMAT-ATOM = _sdt-assert
    SYN-FORMAT-ATOM-1 _sdt-common-candidate
    S" urn:example:atom:item:stable" _sdt-native= _sdt-assert
    S" https://example.test/items/atom-stable" _sdt-url= _sdt-assert
    S" 2026-07-15T10:00:00Z" _sdt-published= _sdt-assert
    _sdt-candidate @ OCC.SUMMARY-A @ _sdt-candidate @ OCC.SUMMARY-U @
        S" The stable entry remains unchanged." STR-STR= _sdt-assert
    _sdt-candidate @ OCC.CONTENT-U @ 0= _sdt-assert
    _sdt-candidate @ OCC.MODIFIED-U @ 0> _sdt-assert
    0 _sdt-decoder @ STREAMS-SYNDICATION-AUTHOR$
        S" Ada Example" STR-STR= _sdt-assert
    _sdt-document-free ;

: _sdt-check-rejections  ( -- )
    S" malformed.json" _sdt-load
    SSOURCE-FORMAT-JSON-FEED _sdt-provider-body!
    \ AUTO forwards the selected codec's exact failure status.
    SSOURCE-FORMAT-AUTO _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYN-S-INVALID = _sdt-assert
    \ Codec failure preserves the preceding successful Atom result.
    _sdt-decoder @ STREAMS-SYNDICATION-FORMAT@
        SSOURCE-FORMAT-ATOM = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-CODEC-STATUS@
        SYN-S-INVALID = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATES
        2 = SWAP 0<> AND _sdt-assert
    _sdt-candidate0 DROP
    S" urn:example:atom:item:stable" _sdt-native= _sdt-assert
    0 _sdt-decoder @ STREAMS-SYNDICATION-AUTHOR$
        S" Ada Example" STR-STR= _sdt-assert

    SSOURCE-FORMAT-RSS _sdt-context _SDTC-MEDIA + !
    SSOURCE-FORMAT-JSON-FEED _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-MEDIA = _sdt-assert
    SSOURCE-FORMAT-TEXT _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-FORMAT = _sdt-assert
    SSOURCE-FORMAT-AUTO _sdt-context _SDTC-MEDIA + !
    SSOURCE-FORMAT-AUTO _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-MEDIA = _sdt-assert
    SSOURCE-FORMAT-RSS _sdt-context _SDTC-MEDIA + !
    0 _sdt-context _SDTC-RESULT + !
    SSOURCE-FORMAT-RSS _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE SYNDEC-S-RESULT = _sdt-assert
    -1 _sdt-context _SDTC-RESULT + !
    \ AUTO follows admitted RSS media and does not sniff the JSON body.
    SSOURCE-FORMAT-AUTO _sdt-provider _sdt-decoder @
        STREAMS-SYNDICATION-DECODE
        DUP SYN-S-INVALID = SWAP SYN-S-UNSUPPORTED = OR _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-FORMAT@
        SSOURCE-FORMAT-ATOM = _sdt-assert
    _sdt-document-free ;

\ Invoke BEGIN, each CHECK word, and FINISH as separate top-level autoexec
\ lines.  Wrapping codec entry inside one more _sdt-run call exceeds KDOS's
\ evaluator-depth budget in the recursive JSON/XML parsers.
: _sdt-begin  ( -- )
    0 _sdt-fails ! 0 _sdt-checks ! DEPTH _sdt-depth !
    _sdt-provider-init _sdt-stack
    STREAMS-SYNDICATION-DECODER-NEW
        SYNDEC-S-OK = _sdt-assert
    DUP 0<> _sdt-assert
    _sdt-decoder !
    _sdt-decoder @ STREAMS-SYNDICATION-DECODER-VALID? _sdt-assert
    STREAMS-OBSERVATION-CHECKPOINT-SIZE ALLOCATE
        ABORT" SDT checkpoint allocation failed" _sdt-checkpoint !
    _sdt-checkpoint @ OCHK-INIT
    _sdt-source RID-SIZE 0 FILL 1 _sdt-source !
    _sdt-namespace RID-SIZE 0 FILL 2 _sdt-namespace ! ;

: _sdt-finish  ( -- )
    _sdt-decoder @ STREAMS-SYNDICATION-DECODER-RESET
        SYNDEC-S-OK = _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-RESULT-VALID? 0= _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-CANDIDATES
        OR 0= _sdt-assert
    _sdt-decoder @ STREAMS-SYNDICATION-DECODER-FREE
        SYNDEC-S-OK = _sdt-assert
    0 _sdt-decoder !

    \ OCHK owns its copied strings after both input and decoder are gone.
    0 _sdt-checkpoint @ OCHK-OBSERVATION-NTH
        _sdt-checkpoint @ OCHK-OBSERVATION-CONTENT$
        S" The stable item remains unchanged." STR-STR= _sdt-assert
    _sdt-checkpoint @ FREE 0 _sdt-checkpoint !
    _sdt-stack

    _sdt-fails @ 0= IF
        ." STREAMS SYNDEC CONTRACTS PASS " _sdt-checks @ .
    ELSE
        ." STREAMS SYNDEC CONTRACTS FAIL " _sdt-fails @ . ." / "
            _sdt-checks @ .
    THEN CR ;
