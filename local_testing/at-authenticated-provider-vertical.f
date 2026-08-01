\ Focused concrete authenticated-provider qualification.
\
\ The existing authenticated-session and bidirectional fixtures provide the
\ deterministic OAuth account and the owner-routed fake PDS peer.  This test
\ composes those fixtures through the production STREAMS-AT-ACCOUNT, public
\ streams-online singleton, and SAUTH interfaces, a real Streams applet
\ lifecycle, the real author-feed presenter, and the real text-post connector.
\ The peer remains the only external-I/O double: feed decoding, Streams
\ presentation, post encoding, createRecord receipt parsing, source
\ admission, cancellation, and provider teardown are all production paths.
\ The separate fake-provider applet vertical owns the visible publish-action
\ and receipt-panel assertions; this gate qualifies their concrete provider.

REQUIRE at-bidirectional-vertical.f
REQUIRE ../akashic/tui/applets/streams/atproto-authenticated-provider.f
REQUIRE ../akashic/tui/applets/streams/streams-online.f

PROVIDED at-auth-provider-vert

96 CONSTANT _SATPT-POLL-LIMIT
2 CONSTANT _SATPT-POLLS-PER-CHECKPOINT

VARIABLE _satpt-checks
VARIABLE _satpt-fails
VARIABLE _satpt-depth
VARIABLE _satpt-instance
VARIABLE _satpt-other-instance
VARIABLE _satpt-state
VARIABLE _satpt-provider
VARIABLE _satpt-heap-before
VARIABLE _satpt-heap-global
VARIABLE _satpt-polls
VARIABLE _satpt-checkpoint-polls
VARIABLE _satpt-changed
VARIABLE _satpt-status-value
VARIABLE _satpt-feed-sequence
VARIABLE _satpt-feed-count
VARIABLE _satpt-local-sequence-before
VARIABLE _satpt-clock-before-post
VARIABLE _satpt-clock-after-delivery

CREATE _satpt-service XIO-SERVICE-SIZE ALLOT
CREATE _satpt-endpoint IENDPOINT-SIZE ALLOT
CREATE _satpt-account STREAMS-AT-ACCOUNT-SIZE ALLOT
CREATE _satpt-candidate STREAMS-SOURCE-SIZE ALLOT
CREATE _satpt-source STREAMS-SOURCE-SIZE ALLOT
CREATE _satpt-rid RID-SIZE ALLOT
CREATE _satpt-failed-text 64 ALLOT
VARIABLE _satpt-failed-text-u

: _satpt-assert  ( flag -- )
    1 _satpt-checks +! 0= IF
        1 _satpt-fails +!
        ." AT AUTH PROVIDER ASSERT " _satpt-checks @ . CR
    THEN ;

: _satpt-status  ( actual expected -- )
    2DUP <> IF
        ." AT AUTH PROVIDER STATUS actual/expected " OVER . DUP . CR
    THEN = _satpt-assert ;

: _satpt-stack  ( -- )
    DEPTH DUP _satpt-depth @ <> IF
        ." AT AUTH PROVIDER STACK " _satpt-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _satpt-depth @ = _satpt-assert ;

: _satpt-zeroed?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;

: _satpt-service-clear?  ( -- flag )
    _satpt-service XIO-ACTIVE? 0=
    _satpt-service XIOS.RETAINED @ 0= AND ;

: _satpt-service-for  ( id-a id-u context -- service|0 )
    >R S" org.akashic.net.external-io" STR-STR= IF
        R>
    ELSE
        R> DROP 0
    THEN ;

: _satpt-factory  ( vfs xio-service -- provider status )
    _satpt-account STREAMS-AT-AUTH-PROVIDER-NEW ;

: _satpt-conflicting-factory  ( vfs xio-service -- provider status )
    2DROP 0 SAUTH-S-UNAVAILABLE ;

: _satpt-online-repeat  ( -- )
    ['] STREAMS-CONFIGURED-SYNDICATION-NEW ['] _satpt-factory
        STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS ;

: _satpt-online-conflict  ( -- )
    ['] STREAMS-CONFIGURED-SYNDICATION-NEW
        ['] _satpt-conflicting-factory
        STREAMS-ONLINE-COMP-SETUP-WITH-PROVIDERS ;

: _satpt-online-compose  ( -- )
    ['] STREAMS-CONFIGURED-SYNDICATION-NEW ['] _satpt-factory
        STREAMS-DESC STREAMS-ONLINE-ENTRY-WITH-PROVIDERS ;

: _satpt-provider-context  ( -- context )
    _satpt-provider @ SAUTH.CONTEXT @ ;

: _satpt-publish-scratch-clear?  ( -- flag )
    _SATP-TEXT-A @ 0=
    _SATP-TEXT-U @ 0= AND
    _satpt-provider-context SATP.LOCAL-EVENT
        STREAMS-EVENT-SIZE _satpt-zeroed? AND ;

: _satpt-account-init  ( -- )
    _satpt-account STREAMS-AT-ACCOUNT-INIT
    S" Scripted authenticated account"
        _satpt-account SATACC.ACCOUNT-U !
        _satpt-account SATACC.ACCOUNT-A !
    S" fixture-account"
        _satpt-account SATACC.BINDING-U !
        _satpt-account SATACC.BINDING-A !
    _atxr-active-vault @ _satpt-account SATACC.VAULT !
    _atoct-config _satpt-account SATACC.CONFIG !
    _atopt-profile _satpt-account SATACC.PROFILE !
    _atxr-active-session @ _satpt-account SATACC.SESSION !

    _ATBV-EPOCH-A _atbv-clock-context-a ATBVC.EPOCH !
    0 _atbv-clock-context-a ATBVC.CALLS !
    _atbv-clock-context-a _satpt-account SATACC.CLOCK-CONTEXT !
    ['] _atbv-clock _satpt-account SATACC.CLOCK-XT !
    17 _atbv-tid-clock-a TID-CLOCK-INIT TID-S-OK _satpt-status
    _atbv-tid-clock-a _satpt-account SATACC.TID-CLOCK !

    _atbv-create-target HTARGET-INIT
    S" https://pds.example/xrpc/com.atproto.repo.createRecord"
        _atbv-create-target HTARGET-PARSE HTARGET-S-OK _satpt-status
    _atbv-create-target _satpt-account SATACC.CREATE-TARGET !
    10000 _satpt-account SATACC.TIMEOUT-MS !
    STREAMS-RUNTIME-PROFILE-STANDARD
        _satpt-account SATACC.RUNTIME-PROFILE !
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
        _satpt-account SATACC.FEED-REQUEST-CAP !
    _atbv-document-u @ _satpt-account SATACC.FEED-BODY-CAP !
    _ATBV-XREQUEST-CAPACITY _satpt-account SATACC.POST-REQUEST-CAP !
    _ATBV-XBODY-CAPACITY _satpt-account SATACC.POST-BODY-CAP !
    _ATBV-CREATE-BODY-CAPACITY
        _satpt-account SATACC.CREATE-BODY-CAP !
    _ATBV-RESULT-CAPACITY _satpt-account SATACC.RESULT-BYTES-CAP !
    _satpt-account STREAMS-AT-ACCOUNT-SEAL
        SAUTH-S-OK _satpt-status
    _satpt-account STREAMS-AT-ACCOUNT-VALID? _satpt-assert ;

: _satpt-peer-buffers-allocate  ( -- )
    _atbv-document-u @ _ATBV-RESPONSE-RESERVE +
        DUP _atbv-feed-response-cap !
        _atbv-feed-response _atxr-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 *
        _atbv-feed-capture _atxr-allocate
    AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN
        _atbv-feed-expected _atxr-allocate
    _ATBV-WIRE-RESPONSE-CAPACITY _atbv-response-a _atxr-allocate
    _ATBV-CAPTURE-CAPACITY _atbv-capture-a _atxr-allocate
    _ATBV-EXPECTED-CAPACITY _atbv-expected-a _atxr-allocate ;

: _satpt-install-feed-peer  ( -- )
    _satpt-provider-context SATP.FEED-OWNER-P @
        AT-AUTHOR-FEED-CONNECTOR-EXCHANGE@
    AT-AUTHOR-FEED-CONNECTOR-S-OK _satpt-status
    DUP
    _atbv-feed-response @ _atbv-feed-response-cap @
    _atbv-feed-capture @
        AT-XRPC-EXCHANGE-REQUEST-CAPACITY-MIN 2 *
    _atbv-feed-context _atbv-init-context
    _atbv-feed-context _atbv-install-port
    _atbv-build-feed-responses
    _atbv-build-feed-expected ;

: _satpt-install-post-peer  ( -- )
    _satpt-provider-context SATP.POST-EXCHANGE-P @
    DUP
    _atbv-response-a @ _ATBV-WIRE-RESPONSE-CAPACITY
    _atbv-capture-a @ _ATBV-CAPTURE-CAPACITY
    _atbv-context-a _atbv-init-context
    _atbv-context-a _atbv-install-port
    _atbv-build-post-response-a
    _atbv-build-expected-a ;

: _satpt-drive-xio-first  ( -- )
    0 _satpt-polls !
    _satpt-service XIO-ACTIVE? _satpt-assert
    _satpt-service XIO-TICK
    1 _satpt-polls +!
    _satpt-polls @ _SATPT-POLL-LIMIT U< _satpt-assert ;

: _satpt-drive-xio-finished  ( -- )
    _satpt-service XIO-ACTIVE? 0= _satpt-assert
    _satpt-polls @ _SATPT-POLL-LIMIT U< _satpt-assert
    _satpt-provider-context SATP.XIO-OP XIOO.STATE @
        XIO-STATE-SUCCEEDED = _satpt-assert
    _satpt-service XIOS.RETAINED @
        _satpt-provider-context SATP.XIO-OP = _satpt-assert ;

: _satpt-drive-xio-rest  ( -- )
    BEGIN
        _satpt-service XIO-ACTIVE?
        _satpt-polls @ _SATPT-POLL-LIMIT U< AND
    WHILE
        _satpt-service XIO-TICK 1 _satpt-polls +!
    REPEAT
    _satpt-drive-xio-finished ;

: _satpt-drive-xio-terminal  ( -- )
    _satpt-drive-xio-first _satpt-drive-xio-rest ;

: _satpt-app-tick  ( -- )
    _satpt-instance @ STREAMS-TICK-CB
    _satpt-instance @ _STM-ACTIVATE
    _STM-AUTH-TICK-CHANGED @ _satpt-changed !
    _STM-AUTH-TICK-STATUS @ _satpt-status-value ! ;

: _satpt-wrong-instance-noop  ( -- )
    _satpt-other-instance @ _satpt-provider @ SAUTH-TICK
    _satpt-status-value ! _satpt-changed !
    _satpt-changed @ 0= _satpt-assert
    _satpt-status-value @ SAUTH-S-STATE _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FEED-ACTIVE _satpt-status
    _satpt-service XIO-ACTIVE? _satpt-assert

    _satpt-other-instance @ _satpt-provider @ SAUTH-CANCEL
    _satpt-status-value ! _satpt-changed !
    _satpt-changed @ 0= _satpt-assert
    _satpt-status-value @ SAUTH-S-STATE _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FEED-ACTIVE _satpt-status
    _satpt-service XIO-ACTIVE? _satpt-assert ;

: _satpt-read-source  ( -- )
    _satpt-rid _satpt-source _satpt-instance @
        STREAMS-SOURCE-READ-OWNER
        STREAMS-SOURCE-S-OK _satpt-status
    _satpt-source STREAMS-SOURCE-VALID? _satpt-assert
    _satpt-source SSOURCE.ID _satpt-rid RID= _satpt-assert ;

: _satpt-revise-source  ( label-a label-u -- )
    _satpt-source STREAMS-SOURCE-LABEL! SSREG-S-OK _satpt-status
    _satpt-source SSOURCE.REVISION @
    _satpt-source SWAP _satpt-instance @ STREAMS-SOURCE-REPLACE-OWNER
        STREAMS-SOURCE-S-OK _satpt-status
    _satpt-read-source ;

: _SATPT-SETUP  ( -- )
    0 _satpt-checks ! 0 _satpt-fails !
    DEPTH _satpt-depth !
    HEAP-FREE-BYTES _satpt-heap-global !
    0 _satpt-instance ! 0 _satpt-other-instance !
    0 _satpt-state ! 0 _satpt-provider !
    _satpt-rid RID-CLEAR
    0 _satpt-local-sequence-before !
    0 _satpt-clock-before-post ! 0 _satpt-clock-after-delivery !
    _satpt-candidate STREAMS-SOURCE-SIZE 0 FILL
    _satpt-source STREAMS-SOURCE-SIZE 0 FILL

    _satpt-account-init
    _satpt-peer-buffers-allocate
    _satpt-service XIO-SERVICE-INIT XIO-S-OK _satpt-status
    _satpt-endpoint IENDPOINT-INIT
    _satpt-service _satpt-endpoint IEND.CONTEXT !
    ['] _satpt-service-for _satpt-endpoint IEND.SERVICE-XT !

    _satpt-online-compose
    ['] _satpt-online-repeat CATCH 0= _satpt-assert
    ['] _satpt-online-conflict CATCH
        STREAMS-ONLINE-E-FACTORY-CONFLICT = _satpt-assert
    _STREAMS-ONLINE-CONFIGURED-FACTORY @
        ['] STREAMS-CONFIGURED-SYNDICATION-NEW = _satpt-assert
    _STREAMS-ONLINE-AUTH-FACTORY @ ['] _satpt-factory = _satpt-assert
    STREAMS-ONLINE-COMP-DESC COMP.STATE-INIT-XT @
        ['] _STREAMS-ONLINE-STATE-INIT = _satpt-assert
    STREAMS-DESC APP.COMP-DESC @ STREAMS-ONLINE-COMP-DESC =
        _satpt-assert

    STREAMS-ONLINE-COMP-DESC CINST-NEW DUP 0= _satpt-assert DROP
    DUP _satpt-instance ! DUP CINST-STATE _satpt-state !
    _satpt-endpoint OVER CINST.ENDPOINT !
    STREAMS-ONLINE-COMP-DESC CINST-NEW DUP 0= _satpt-assert DROP
    _satpt-other-instance !
    HEAP-FREE-BYTES _satpt-heap-before !
    STREAMS-INIT-CB

    _satpt-instance @ _STM-ACTIVATE
    _STM-AUTH-INIT-STATUS @ SAUTH-S-OK _satpt-status
    _STM-AUTH-PROVIDER @ DUP 0<> _satpt-assert
        DUP SAUTH-VALID? _satpt-assert _satpt-provider !
    _satpt-provider @ SAUTH-ACCOUNT$
        S" Scripted authenticated account" STR-STR= _satpt-assert
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-IDLE _satpt-status
    _satpt-instance @ STREAMS-SOURCE-STORAGE-READY? _satpt-assert
    _satpt-service-clear? _satpt-assert

    S" did:plc:abcdefghijklmnopqrstuvwx"
        _satpt-candidate _satpt-provider @ SAUTH-SOURCE-BUILD
        SAUTH-S-OK _satpt-status
    _satpt-candidate STREAMS-SOURCE-CONFIG$
        S" fixture-account" STR-STR= _satpt-assert
    _satpt-candidate _satpt-rid _satpt-instance @
        STREAMS-SOURCE-CREATE-OWNER
        STREAMS-SOURCE-S-OK _satpt-status
    _satpt-rid RID-PRESENT? _satpt-assert
    _satpt-read-source
    _satpt-source SSOURCE.REVISION @ 1 = _satpt-assert
    _satpt-source _satpt-provider @ SAUTH-SOURCE-SUPPORTED?
        _satpt-assert
    _satpt-source _satpt-instance @
        STREAMS-AUTH-SOURCE-ADMISSIBLE? _satpt-assert
    _satpt-stack ;

: _SATPT-FEED  ( -- )
    _satpt-source _satpt-instance @ _satpt-provider @ SAUTH-REFRESH
        SAUTH-S-OK _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FEED-ACTIVE _satpt-status
    _satpt-install-feed-peer
    _satpt-wrong-instance-noop
    _satpt-drive-xio-terminal
    _satpt-app-tick
    _satpt-changed @ _satpt-assert
    _satpt-status-value @ SAUTH-S-OK _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FEED-READY _satpt-status
    _satpt-service-clear? _satpt-assert

    _STM-ITEM-COUNT DUP 2 = _satpt-assert _satpt-feed-count !
    _STM-FEED-SEQUENCE @ DUP 1 = _satpt-assert
        _satpt-feed-sequence !
    _STM-FEED-SOURCE @ _STM-SOURCE-AUTHENTICATED = _satpt-assert
    _STM-FEED-PROVENANCE$
        S" PDS-authenticated / AppView proxy requested"
        STR-STR= _satpt-assert
    0 _STM-ITEM BFM.ITEM.TEXT _atbv-text-a$ STR-STR= _satpt-assert
    _atbv-check-feed-wire
    _satpt-provider @ SAUTH-SOURCE@
        DUP 0<> _satpt-assert
        SSOURCE.REVISION @ 1 = _satpt-assert
    _satpt-stack ;

: _SATPT-FEED-REPEAT  ( -- )
    _satpt-source SSOURCE.REVISION @ 1 = _satpt-assert
    _satpt-source _satpt-instance @ _satpt-provider @ SAUTH-REFRESH
        SAUTH-S-OK _satpt-status
    _satpt-install-feed-peer
    _satpt-drive-xio-terminal
    _satpt-app-tick
    _satpt-changed @ _satpt-assert
    _satpt-status-value @ SAUTH-S-OK _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FEED-READY _satpt-status
    _satpt-service-clear? _satpt-assert

    _STM-ITEM-COUNT _satpt-feed-count @ = _satpt-assert
    _STM-FEED-SEQUENCE @
        DUP _satpt-feed-sequence @ 1+ = _satpt-assert
        _satpt-feed-sequence !
    _STM-FEED-SOURCE @ _STM-SOURCE-AUTHENTICATED = _satpt-assert
    0 _STM-ITEM BFM.ITEM.TEXT _atbv-text-a$ STR-STR= _satpt-assert
    _atbv-check-feed-wire
    _satpt-provider @ SAUTH-SOURCE@
        DUP 0<> _satpt-assert
        SSOURCE.REVISION @ 1 = _satpt-assert
    _satpt-stack ;

: _SATPT-STALE-FEED  ( -- )
    _satpt-source _satpt-instance @ _satpt-provider @ SAUTH-REFRESH
        SAUTH-S-OK _satpt-status
    _satpt-install-feed-peer
    _satpt-drive-xio-terminal
    S" Feed source revised before presentation" _satpt-revise-source
    _satpt-source SSOURCE.REVISION @ 2 = _satpt-assert
    _satpt-app-tick
    _satpt-changed @ _satpt-assert
    _satpt-status-value @ SAUTH-S-STATE _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FAILED _satpt-status
    _satpt-service-clear? _satpt-assert
    _STM-ITEM-COUNT _satpt-feed-count @ = _satpt-assert
    _STM-FEED-SEQUENCE @ _satpt-feed-sequence @ = _satpt-assert
    _satpt-provider @ SAUTH-SOURCE@
        DUP 0<> _satpt-assert
        SSOURCE.REVISION @ 1 = _satpt-assert
    _satpt-source _satpt-instance @
        STREAMS-AUTH-SOURCE-ADMISSIBLE? _satpt-assert
    _satpt-stack ;

: _SATPT-FAILED-PUBLISH  ( -- )
    _satpt-failed-text 64 0 FILL
    S" caller text must not survive a refused publish"
    DUP _satpt-failed-text-u !
    _satpt-failed-text SWAP MOVE
    _satpt-provider-context SATP.LOCAL-SEQUENCE @
        _satpt-local-sequence-before !
    0x7FFFFFFFFFFFFFFF
        _satpt-provider-context SATP.LOCAL-SEQUENCE !
    _satpt-failed-text _satpt-failed-text-u @
        _satpt-source _satpt-instance @ _satpt-provider @ SAUTH-PUBLISH
        SAUTH-S-CAPACITY _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-FAILED _satpt-status
    _satpt-publish-scratch-clear? _satpt-assert
    _satpt-failed-text 64 0 FILL
    0 _satpt-failed-text-u !
    _satpt-local-sequence-before @
        _satpt-provider-context SATP.LOCAL-SEQUENCE !
    _satpt-service-clear? _satpt-assert
    _satpt-provider @ SAUTH-RELEASABLE? _satpt-assert
    _satpt-stack ;

: _SATPT-POST-START  ( -- )
    _atbv-clock-context-a ATBVC.CALLS @ _satpt-clock-before-post !
    _atbv-text-a$ _satpt-source _satpt-instance @ _satpt-provider @
        SAUTH-PUBLISH SAUTH-S-OK _satpt-status
    _satpt-publish-scratch-clear? _satpt-assert
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-POST-ACTIVE _satpt-status
    _satpt-install-post-peer
    _satpt-stack ;

: _SATPT-POST-DRIVE-FIRST  ( -- )
    0 _satpt-polls !
    _satpt-service XIO-ACTIVE? _satpt-assert
    _satpt-stack ;

: _SATPT-POST-DRIVE-CHUNK  ( -- )
    0 _satpt-checkpoint-polls !
    BEGIN
        _satpt-service XIO-ACTIVE?
        _satpt-polls @ _SATPT-POLL-LIMIT U< AND
        _satpt-checkpoint-polls @ _SATPT-POLLS-PER-CHECKPOINT U< AND
    WHILE
        _satpt-service XIO-TICK
        1 _satpt-polls +! 1 _satpt-checkpoint-polls +!
    REPEAT
    _satpt-stack ;

: _SATPT-POST-DRIVE  ( -- )
    _satpt-drive-xio-finished
    _satpt-stack ;

: _SATPT-POST-FINISH  ( -- )
    \ The request is already a terminal external fact.  Advancing the source
    \ before the app consumes it must not erase or relabel that receipt.
    S" Post source revised after wire completion" _satpt-revise-source
    _satpt-source SSOURCE.REVISION @ 3 = _satpt-assert
    _satpt-app-tick
    _satpt-changed @ _satpt-assert
    _satpt-status-value @ SAUTH-S-OK _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-POST-DELIVERED _satpt-status
    _satpt-provider @ SAUTH-URI$ _atbv-uri-a$ STR-STR= _satpt-assert
    _satpt-provider @ SAUTH-CID$ _atbv-cid-a$ STR-STR= _satpt-assert
    _satpt-provider @ SAUTH-SOURCE@
        DUP 0<> _satpt-assert
        SSOURCE.REVISION @ 2 = _satpt-assert
    _atbv-check-post-wire-a
    _atbv-clock-context-a ATBVC.CALLS @
        DUP _satpt-clock-before-post @ 1+ = _satpt-assert
        _satpt-clock-after-delivery !
    _satpt-service-clear? _satpt-assert
    _satpt-stack ;

: _SATPT-POST-MUTATION-CANCEL  ( -- )
    _ATBV-PEER-SCRIPTED _atbv-context-a _atbv-peer-reset
    _atbv-no-effect-text$
        _satpt-source _satpt-instance @ _satpt-provider @ SAUTH-PUBLISH
        SAUTH-S-OK _satpt-status
    _satpt-publish-scratch-clear? _satpt-assert
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-POST-ACTIVE _satpt-status

    \ No service tick has crossed the wire.  A source mutation therefore
    \ cancels the accepted flow with a truthful no-effect result.
    S" Post source revised before wire start" _satpt-revise-source
    _satpt-source SSOURCE.REVISION @ 4 = _satpt-assert
    _satpt-app-tick
    _satpt-changed @ _satpt-assert
    _satpt-status-value @ SAUTH-S-POST _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-POST-NO-EFFECT _satpt-status
    _satpt-provider @ SAUTH-URI$ NIP 0= _satpt-assert
    _satpt-provider @ SAUTH-CID$ NIP 0= _satpt-assert
    _atbv-context-a ATBVT.CAPTURE-U @ 0= _satpt-assert
    _atbv-clock-context-a ATBVC.CALLS @
        _satpt-clock-after-delivery @ = _satpt-assert
    _satpt-service-clear? _satpt-assert
    _satpt-provider @ SAUTH-RELEASABLE? _satpt-assert
    _satpt-stack ;

: _SATPT-CLOSE-ACTIVE  ( -- )
    _ATBV-PEER-SCRIPTED _atbv-context-a _atbv-peer-reset
    _atbv-no-effect-text$
        _satpt-source _satpt-instance @ _satpt-provider @ SAUTH-PUBLISH
        SAUTH-S-OK _satpt-status
    _satpt-publish-scratch-clear? _satpt-assert
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-POST-ACTIVE _satpt-status

    APP-CLOSE-R-WINDOW _satpt-instance @ STREAMS-REQUEST-CLOSE-CB
        APP-CLOSE-D-ALLOW = _satpt-assert
    _STM-AUTH-QUIESCE-CHANGED @ _satpt-assert
    _STM-AUTH-QUIESCE-STATUS @ SAUTH-S-POST _satpt-status
    _satpt-provider @ SAUTH-STATE@
        SAUTH-STATE-POST-NO-EFFECT _satpt-status
    _satpt-provider @ SAUTH-URI$ NIP 0= _satpt-assert
    _satpt-provider @ SAUTH-CID$ NIP 0= _satpt-assert
    _atbv-context-a ATBVT.CAPTURE-U @ 0= _satpt-assert
    _atbv-clock-context-a ATBVC.CALLS @
        _satpt-clock-after-delivery @ = _satpt-assert
    _satpt-service-clear? _satpt-assert
    _satpt-provider @ SAUTH-RELEASABLE? _satpt-assert
    _satpt-stack ;

: _satpt-peer-buffers-free  ( -- )
    _atbv-feed-expected _atxr-free
    _atbv-feed-capture _atxr-free
    _atbv-feed-response _atxr-free
    _atbv-expected-a _atxr-free
    _atbv-capture-a _atxr-free
    _atbv-response-a _atxr-free
    _atbv-feed-context _ATBVT-SIZE 0 FILL
    _atbv-context-a _ATBVT-SIZE 0 FILL
    0 _atbv-feed-response-cap !
    0 _atbv-feed-expected-u !
    0 _atbv-expected-u-a ! ;

: _SATPT-RELEASE  ( -- )
    _satpt-instance @ STREAMS-SHUTDOWN-CB
    _satpt-instance @ _STM-ACTIVATE
    _STM-AUTH-PROVIDER @ 0= _satpt-assert
    _STM-AUTH-INIT-STATUS @ SAUTH-S-UNAVAILABLE _satpt-status
    _satpt-service-clear? _satpt-assert
    HEAP-FREE-BYTES _satpt-heap-before @ = _satpt-assert
    0 _satpt-provider !

    _satpt-instance @ CINST-FREE
    0 _satpt-instance ! 0 _satpt-state !
    _satpt-other-instance @ CINST-FREE
    0 _satpt-other-instance !
    _satpt-service XIO-SERVICE-FINI XIO-S-OK _satpt-status
    _satpt-service XIO-SERVICE-SIZE _satpt-zeroed? _satpt-assert

    _satpt-peer-buffers-free
    _atbv-document-a @ ?DUP IF
        DUP _atbv-document-u @ 0 FILL FREE
    THEN
    0 _atbv-document-a ! 0 _atbv-document-u !
    _satpt-account STREAMS-AT-ACCOUNT-SIZE 0 FILL
    _satpt-endpoint IENDPOINT-SIZE 0 FILL
    _satpt-candidate STREAMS-SOURCE-SIZE 0 FILL
    _satpt-source STREAMS-SOURCE-SIZE 0 FILL
    _satpt-rid RID-CLEAR
    _satpt-failed-text 64 0 FILL
    0 _satpt-failed-text-u !
    0 _satpt-local-sequence-before !
    0 _satpt-clock-before-post ! 0 _satpt-clock-after-delivery !
    _atbv-receipt 512 0 FILL
    0 _atbv-receipt-u !
    _atbv-create-target HTARGET-SIZE 0 FILL
    _atbv-tid-clock-a TID-CLOCK-SIZE 0 FILL
    _atbv-clock-context-a _ATBVC-SIZE 0 FILL
    HEAP-FREE-BYTES _satpt-heap-global @ = _satpt-assert
    _satpt-stack ;

: _SATPT-FINISH  ( -- )
    _ATXR-FINISH
    _satpt-stack
    _satpt-fails @ _atxr-fails @ OR IF
        ." AT AUTH PROVIDER VERTICAL FAIL checks/fails "
        _satpt-checks @ . _satpt-fails @ _atxr-fails @ + . CR
    ELSE
        ." AT AUTH PROVIDER VERTICAL PASS checks "
        _satpt-checks @ . CR
    THEN
    TX-FLUSH ;
