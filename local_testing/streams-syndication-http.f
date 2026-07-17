\ Deterministic harness contracts for configured syndication authorization.

PROVIDED streams-scsyn-tests

\ Load syndication-http.f before this deterministic contract leaf.

." [shac] compiling configured syndication authorization contracts" CR

VARIABLE _shac-fails
VARIABLE _shac-checks
VARIABLE _shac-depth
VARIABLE _shac-provider
VARIABLE _shac-context
VARIABLE _shac-new-status
VARIABLE _shac-expected-status
VARIABLE _shac-calls-before
VARIABLE _shac-heap-before

VARIABLE _shac-auth-source
VARIABLE _shac-auth-target
VARIABLE _shac-auth-context
VARIABLE _shac-expected-source
VARIABLE _shac-expected-revision
VARIABLE _shac-expected-host-a
VARIABLE _shac-expected-host-u
VARIABLE _shac-expected-port
VARIABLE _shac-auth-mode
VARIABLE _shac-auth-calls

CREATE _shac-policy 8 ALLOT
CREATE _shac-rid RID-SIZE ALLOT
CREATE _shac-expected-rid RID-SIZE ALLOT
CREATE _shac-source STREAMS-SOURCE-SIZE ALLOT
CREATE _shac-variant STREAMS-SOURCE-SIZE ALLOT
CREATE _shac-span 64 ALLOT
CREATE _shac-operation XIO-OP-SIZE ALLOT
CREATE _shac-media MTYPE-SIZE ALLOT

: _shac-assert  ( flag -- )
    1 _shac-checks +! 0= IF
        1 _shac-fails +! ." SHAC ASSERT " _shac-checks @ . CR
    THEN ;

: _shac-stack  ( -- )
    DEPTH DUP _shac-depth @ <> IF
        ." SHAC STACK " _shac-depth @ . ." -> " DUP . CR .S CR
    THEN
    _shac-depth @ = _shac-assert ;

: _shac-source=  ( source-a source-b -- flag )
    STREAMS-SOURCE-SIZE SWAP STREAMS-SOURCE-SIZE COMPARE 0= ;

: _shac-expected-host!  ( a u -- )
    _shac-expected-host-u ! _shac-expected-host-a ! ;

: _shac-build-source  ( -- )
    _shac-source STREAMS-SOURCE-INIT
    _shac-rid RID-SIZE 0 FILL
    0x41 _shac-rid C! 0x75 _shac-rid 1+ C!
    _shac-rid _shac-source STREAMS-SOURCE-ID!
        SSREG-S-OK = _shac-assert
    7 _shac-source SSOURCE.REVISION !
    SSOURCE-KIND-SYNDICATION _shac-source SSOURCE.KIND !
    SSOURCE-FORMAT-AUTO _shac-source SSOURCE.FORMAT !
    S" Reviewed feed" _shac-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK = _shac-assert
    S" HTTPS://Feeds.Example.TEST:443/feed.json" _shac-source
        STREAMS-SOURCE-ENDPOINT! SSREG-S-OK = _shac-assert
    S" policy=exact" _shac-source STREAMS-SOURCE-CONFIG!
        SSREG-S-OK = _shac-assert
    _shac-source STREAMS-SOURCE-VALID? _shac-assert ;

: _shac-policy-base  ( -- )
    _shac-source _shac-expected-source !
    _shac-source SSOURCE.ID _shac-expected-rid RID-COPY
    _shac-source SSOURCE.REVISION @ _shac-expected-revision !
    S" feeds.example.test" _shac-expected-host!
    443 _shac-expected-port !
    1 _shac-auth-mode ! ;

\ Mode 0 denies, mode 1 evaluates the exact policy, and mode 2 throws.
: _shac-authorize  ( source target policy -- allowed? )
    _shac-auth-context ! _shac-auth-target ! _shac-auth-source !
    1 _shac-auth-calls +!
    _shac-auth-mode @ 2 = IF -4761 THROW THEN
    _shac-auth-mode @ 1 <> IF 0 EXIT THEN
    _shac-auth-context @ _shac-policy =
    _shac-auth-source @ _shac-expected-source @ _shac-source= AND
    _shac-auth-source @ SSOURCE.ID _shac-expected-rid RID= AND
    _shac-auth-source @ SSOURCE.REVISION @
        _shac-expected-revision @ = AND
    _shac-auth-target @ HTARGET-VALID? AND
    _shac-auth-target @ HTARGET-HOST$
        _shac-expected-host-a @ _shac-expected-host-u @ STR-STR= AND
    _shac-auth-target @ HTARGET-PORT@ _shac-expected-port @ = AND ;

: _shac-capture-new  ( provider status -- )
    _shac-new-status ! _shac-provider !
    _shac-new-status @ SCONF-S-OK = _shac-assert
    _shac-provider @ 0<> _shac-assert
    _shac-provider @ ?DUP 0= IF EXIT THEN
    DUP SCONF-VALID? _shac-assert
    SCONF.CONTEXT @ DUP _shac-context !
        _SCSYN-CONTEXT-VALID? _shac-assert ;

: _shac-new-authorized  ( -- )
    ['] _shac-authorize _shac-policy
        STREAMS-CONFIGURED-SYNDICATION-NEW-AUTHORIZED
        _shac-capture-new ;

: _shac-release  ( -- )
    _shac-provider @ 0= IF EXIT THEN
    _shac-provider @ SCONF-RELEASABLE? _shac-assert
    _shac-provider @ SCONF-RELEASE
        SCONF-S-OK = _shac-assert
    0 _shac-provider ! 0 _shac-context ! ;

: _shac-tls-pristine?  ( -- flag )
    _shac-context @ _SCS.C.TLS @
    DUP KDOSTLS-HOST NIP 0=
    OVER KDOSTLS.REMOTE-PORT @ 0= AND
    SWAP KDOSTLS.STATE @ KDOSTLS-STATE-CLOSED = AND ;

: _shac-expect-bind-denied  ( -- )
    _shac-auth-calls @ _shac-calls-before !
    _shac-context @ _SCS.C.SPEC @ HRES-SPEC-TARGET@
        _shac-context @ _SCSYN-BIND
        SCONF-S-INVALID = SWAP 0= AND _shac-assert
    _shac-auth-calls @ _shac-calls-before @ 1+ = _shac-assert
    _shac-context @ _SCS.C.LEASED @ 0= _shac-assert
    _shac-tls-pristine? _shac-assert ;

: _shac-expect-start-denied  ( -- )
    _shac-operation XIO-OP-INIT
    _shac-operation XIO-OP-VALID? _shac-assert
    _shac-auth-calls @ _shac-calls-before !
    _shac-operation _shac-provider @ SCONF-XIO-START
        XIO-STEP-SUCCEEDED = _shac-assert
    _shac-auth-calls @ _shac-calls-before @ 1+ = _shac-assert
    _shac-operation XIOO.RESULT @ _shac-provider @ = _shac-assert
    _shac-operation XIOO.ERROR @ 0= _shac-assert
    _shac-provider @ SCONF-OUTCOME
        SCONF-O-TRANSPORT = _shac-assert
    _shac-provider @ SCONF-DETAIL HRES-D-BIND-PORT = _shac-assert
    _shac-provider @ SCONF-RESULT-VALID? 0= _shac-assert
    _shac-context @ _SCS.C.RESOURCE @ HRES-PROVIDER-STATUS@
        SCONF-S-INVALID = _shac-assert
    _shac-tls-pristine? _shac-assert ;

: _shac-expect-configure  ( source expected-status -- )
    _shac-expected-status !
    _shac-auth-calls @ _shac-calls-before !
    _shac-provider @ SCONF-CONFIGURE
        _shac-expected-status @ = _shac-assert
    _shac-auth-calls @ _shac-calls-before @ 1+ = _shac-assert ;

: _shac-map-outcome  ( hres-outcome sconf-outcome -- )
    _shac-expected-status !
    _shac-context @ _SCS.C.RESOURCE @ HRES.OUTCOME !
    _shac-provider @ SCONF-OUTCOME
        _shac-expected-status @ = _shac-assert ;

: _shac-test-spans  ( -- )
    _shac-span 16 _shac-span 16 _SCSYN-SPANS-OVERLAP? _shac-assert
    _shac-span 16 _shac-span 8 + 16
        _SCSYN-SPANS-OVERLAP? _shac-assert
    _shac-span 16 _shac-span 16 + 16
        _SCSYN-SPANS-OVERLAP? 0= _shac-assert
    _shac-span 16 + 16 _shac-span 16
        _SCSYN-SPANS-OVERLAP? 0= _shac-assert
    _shac-span 8 _shac-span 32 + 8
        _SCSYN-SPANS-OVERLAP? 0= _shac-assert
    _shac-span 0 _shac-span 16
        _SCSYN-SPANS-OVERLAP? 0= _shac-assert
    -8 16 _shac-span 16 _SCSYN-SPANS-OVERLAP? _shac-assert
    _shac-span 16 -8 16 _SCSYN-SPANS-OVERLAP? _shac-assert
    _shac-stack ;

: _shac-media-kind  ( value-a value-u -- kind )
    _shac-media MTYPE-PARSE MTYPE-S-OK = _shac-assert
    _shac-media _SCSYN-MEDIA-FORMAT ;

: _shac-test-media  ( -- )
    _shac-media MTYPE-INIT
    S" application/feed+json" _shac-media-kind
        SSOURCE-FORMAT-JSON-FEED = _shac-assert
    S" Application/JSON" _shac-media-kind
        SSOURCE-FORMAT-JSON-FEED = _shac-assert
    S" application/atom+xml" _shac-media-kind
        SSOURCE-FORMAT-ATOM = _shac-assert
    S" application/rss+xml" _shac-media-kind
        SSOURCE-FORMAT-RSS = _shac-assert
    S" text/json" _shac-media-kind 0= _shac-assert
    S" application/problem+json" _shac-media-kind 0= _shac-assert
    SSOURCE-FORMAT-JSON-FEED SSOURCE-FORMAT-AUTO
        _SCSYN-FORMAT-ALLOWED? _shac-assert
    SSOURCE-FORMAT-JSON-FEED SSOURCE-FORMAT-JSON-FEED
        _SCSYN-FORMAT-ALLOWED? _shac-assert
    SSOURCE-FORMAT-JSON-FEED SSOURCE-FORMAT-RSS
        _SCSYN-FORMAT-ALLOWED? 0= _shac-assert
    _shac-stack ;

: _shac-test-default-deny  ( -- )
    HEAP-FREE-BYTES _shac-heap-before !
    0 _shac-policy STREAMS-CONFIGURED-SYNDICATION-NEW-AUTHORIZED
        SCONF-S-INVALID = SWAP 0= AND _shac-assert
    HEAP-FREE-BYTES _shac-heap-before @ = _shac-assert
    STREAMS-CONFIGURED-SYNDICATION-NEW _shac-capture-new
    _shac-source _shac-provider @ SCONF-CONFIGURE
        SCONF-S-INVALID = _shac-assert
    _shac-provider @ SCONF-REQUESTED$ OR 0= _shac-assert
    _shac-provider @ SCONF-OUTCOME SCONF-O-NONE = _shac-assert
    _shac-provider @ SCONF-RESULT-VALID? 0= _shac-assert
    _shac-provider @ SCONF-CLEANUP-ERROR@ 0= _shac-assert
    _shac-release
    HEAP-FREE-BYTES _shac-heap-before @ = _shac-assert
    _shac-stack ;

: _shac-test-authorized  ( -- )
    HEAP-FREE-BYTES _shac-heap-before !
    _shac-policy-base 0 _shac-auth-calls ! _shac-new-authorized

    \ A valid source wholly inside the provider context must be rejected
    \ before policy evaluation or any provider mutation.
    _shac-source _shac-context @ _SCS.C.SOURCE
        STREAMS-SOURCE-SIZE MOVE
    _shac-context @ _SCS.C.SOURCE _shac-provider @ SCONF-CONFIGURE
        SCONF-S-INVALID = _shac-assert
    _shac-auth-calls @ 0= _shac-assert
    _shac-context @ _SCS.C.RESOURCE @ HRES-STATE@
        HRES-STATE-IDLE = _shac-assert
    _shac-context @ _SCS.C.SPEC @ HRSPEC.FLAGS @ 0= _shac-assert

    \ Exact RID/revision/authority is insufficient when any other byte in
    \ the reviewed full source snapshot differs.
    _shac-source _shac-variant STREAMS-SOURCE-SIZE MOVE
    S" policy=changed" _shac-variant STREAMS-SOURCE-CONFIG!
        SSREG-S-OK = _shac-assert
    _shac-variant SCONF-S-INVALID _shac-expect-configure

    _shac-expected-rid DUP C@ 1 XOR SWAP C!
    _shac-source SCONF-S-INVALID _shac-expect-configure
    _shac-source SSOURCE.ID _shac-expected-rid RID-COPY

    S" other.example.test" _shac-expected-host!
    _shac-source SCONF-S-INVALID _shac-expect-configure
    S" feeds.example.test" _shac-expected-host!

    8443 _shac-expected-port !
    _shac-source SCONF-S-INVALID _shac-expect-configure
    443 _shac-expected-port !

    8 _shac-expected-revision !
    _shac-source SCONF-S-INVALID _shac-expect-configure
    7 _shac-expected-revision !

    _shac-source SCONF-S-OK _shac-expect-configure
    _shac-context @ _SCS.C.SOURCE _shac-source _shac-source=
        _shac-assert
    _shac-context @ _SCS.C.SPEC @ HRES-SPEC-TARGET@
        DUP HTARGET-HOST$ S" feeds.example.test" STR-STR= _shac-assert
        DUP HTARGET-PORT@ 443 = _shac-assert
        HTARGET-URI$ S" https://feeds.example.test/feed.json" STR-STR=
        _shac-assert
    _shac-provider @ SCONF-REQUESTED$
        S" https://feeds.example.test/feed.json" STR-STR= _shac-assert
    _shac-context @ _SCS.C.RESOURCE @ HRES-STATE@
        HRES-STATE-CONFIGURED = _shac-assert
    _shac-context @ _SCS.C.SPEC @ HRES-SPEC-ACCEPT$
        S" application/feed+json, application/json, application/atom+xml, application/rss+xml"
        STR-STR= _shac-assert
    _shac-context @ _SCS.C.RESOURCE @ DUP _HRES-BUILD-REQUEST
        HREQ-S-OK = _shac-assert
    HRES.REQUEST DUP HREQ.BUFFER @ SWAP HREQ.LENGTH @
        S" Accept: application/feed+json, application/json, application/atom+xml, application/rss+xml"
        STR-STR-CONTAINS _shac-assert
    _shac-tls-pristine? _shac-assert

    \ Distinguish the retained source from mutable caller memory: the policy
    \ follows the caller's revision 8, while the context copy remains 7.
    \ Correct bind-time reauthorization therefore denies before KDOSTLS.
    8 _shac-source SSOURCE.REVISION !
    8 _shac-expected-revision !
    _shac-expect-bind-denied
    7 _shac-source SSOURCE.REVISION !
    7 _shac-expected-revision !

    \ A callback exception is fail-closed at the physical bind as well.
    2 _shac-auth-mode ! _shac-expect-bind-denied
    1 _shac-auth-mode !

    \ Exercise the sealed HRES binding, still without network I/O.  A stale
    \ caller-source regression would authorize revision 8; the retained
    \ revision-7 source must instead publish an admitted transport outcome.
    8 _shac-source SSOURCE.REVISION !
    8 _shac-expected-revision !
    _shac-expect-start-denied
    7 _shac-source SSOURCE.REVISION !
    7 _shac-expected-revision !

    HRES-O-NONE SCONF-O-NONE _shac-map-outcome
    HRES-O-OK SCONF-O-OK _shac-map-outcome
    HRES-O-HTTP SCONF-O-HTTP _shac-map-outcome
    HRES-O-REDIRECT-LIMIT SCONF-O-REDIRECT-LIMIT _shac-map-outcome
    HRES-O-REDIRECT-LOOP SCONF-O-REDIRECT-LOOP _shac-map-outcome
    HRES-O-AUTHORITY-REQUIRED SCONF-O-AUTHORITY-REQUIRED
        _shac-map-outcome
    HRES-O-REDIRECT-INVALID SCONF-O-REDIRECT-INVALID _shac-map-outcome
    HRES-O-HEADER SCONF-O-HEADER _shac-map-outcome
    HRES-O-MEDIA SCONF-O-MEDIA _shac-map-outcome
    HRES-O-CONTENT-ENCODING SCONF-O-CONTENT-ENCODING _shac-map-outcome
    HRES-O-BODY-OVERFLOW SCONF-O-BODY-OVERFLOW _shac-map-outcome
    HRES-O-PROTOCOL SCONF-O-PROTOCOL _shac-map-outcome
    HRES-O-TRANSPORT SCONF-O-TRANSPORT _shac-map-outcome
    HRES-O-CANCELLED SCONF-O-CANCELLED _shac-map-outcome
    HRES-O-CLEANUP SCONF-O-CLEANUP _shac-map-outcome
    HRES-O-FAULT SCONF-O-FAULT _shac-map-outcome
    HRES-O-TIMED-OUT SCONF-O-TIMED-OUT _shac-map-outcome
    999 SCONF-O-FAULT _shac-map-outcome
    0 _SCSYN-OUTCOME SCONF-O-FAULT = _shac-assert
    HRES-O-NONE _shac-context @ _SCS.C.RESOURCE @ HRES.OUTCOME !

    _shac-operation _shac-provider @ SCONF-XIO-WIPE
    _shac-context @ _SCS.C.RESOURCE @ HRES-STATE@
        HRES-STATE-RELEASED = _shac-assert

    _shac-release
    HEAP-FREE-BYTES _shac-heap-before @ = _shac-assert
    _shac-stack ;

: _shac-test-throw  ( -- )
    HEAP-FREE-BYTES _shac-heap-before !
    _shac-policy-base 2 _shac-auth-mode ! 0 _shac-auth-calls !
    _shac-new-authorized
    _shac-source SCONF-S-INVALID _shac-expect-configure
    _shac-context @ _SCS.C.RESOURCE @ HRES-STATE@
        HRES-STATE-IDLE = _shac-assert
    _shac-context @ _SCS.C.LEASED @ 0= _shac-assert
    _shac-context @ _SCS.C.TLS @ KDOSTLS.STATE @
        KDOSTLS-STATE-CLOSED = _shac-assert
    1 _shac-auth-mode !
    _shac-source SCONF-S-OK _shac-expect-configure
    _shac-release
    HEAP-FREE-BYTES _shac-heap-before @ = _shac-assert
    _shac-stack ;

: _shac-run  ( -- )
    0 _shac-fails ! 0 _shac-checks ! DEPTH _shac-depth !
    0 _shac-provider ! 0 _shac-context !
    0x53484143504F4C31 _shac-policy !
    _shac-build-source _shac-stack
    _shac-test-spans
    _shac-test-media
    _shac-test-default-deny
    _shac-test-authorized
    _shac-test-throw
    _shac-fails @ 0= IF
        ." STREAMS SYNDICATION HTTP CONTRACTS PASS " _shac-checks @ .
    ELSE
        ." STREAMS SYNDICATION HTTP CONTRACTS FAIL " _shac-fails @ .
            ." / " _shac-checks @ .
    THEN CR ;
