\ hres-contracts.f - deterministic HTTP resource profile contracts
\
\ This test-only module keeps the large scripted transport fixture outside
\ autoexec.f so KDOS evaluates it with bounded source nesting.

PROVIDED akashic-hres-contracts

VARIABLE _hrc-fails
VARIABLE _hrc-checks
VARIABLE _hrc-depth

: _hrc-assert  ( flag -- )
    1 _hrc-checks +!
    0= IF 1 _hrc-fails +! ." HRC ASSERT " _hrc-checks @ . CR THEN ;

: _hrc-stack  ( -- )
    DEPTH DUP _hrc-depth @ <> IF
        ." HRC STACK " _hrc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _hrc-depth @ = _hrc-assert ;

: _hrc-mark  ( addr len -- )
    ." [hrc] " TYPE
    ."  eval=" EVAL-DEPTH @ . ."  data=" DEPTH . CR ;

4 CONSTANT _HRC-HOP-CAP
4096 CONSTANT _HRC-RESPONSE-CAP

CREATE _hrc-spec HRES-SPEC-SIZE ALLOT
CREATE _hrc-resource HTTP-RESOURCE-SIZE ALLOT
CREATE _hrc-body 128 ALLOT
CREATE _hrc-port NET-IO-PORT-SIZE ALLOT
CREATE _hrc-service XIO-SERVICE-SIZE ALLOT
CREATE _hrc-operation XIO-OP-SIZE ALLOT
CREATE _hrc-responses _HRC-HOP-CAP _HRC-RESPONSE-CAP * ALLOT
CREATE _hrc-response-us _HRC-HOP-CAP 8 * ALLOT
CREATE _hrc-sent _HRC-HOP-CAP HRES-REQUEST-MAX * ALLOT
CREATE _hrc-sent-us _HRC-HOP-CAP 8 * ALLOT
CREATE _hrc-expected HRES-REQUEST-MAX ALLOT

VARIABLE _hrc-build-hop
VARIABLE _hrc-active-hop
VARIABLE _hrc-response-pos
VARIABLE _hrc-expected-u
VARIABLE _hrc-binds
VARIABLE _hrc-releases
VARIABLE _hrc-bind-port
VARIABLE _hrc-bind-status
VARIABLE _hrc-release-open-state
VARIABLE _hrc-release-close-state
VARIABLE _hrc-open-starts
VARIABLE _hrc-open-polls
VARIABLE _hrc-open-polls-this
VARIABLE _hrc-send-calls
VARIABLE _hrc-recv-calls
VARIABLE _hrc-poll-calls
VARIABLE _hrc-cancels
VARIABLE _hrc-cancel-throw
VARIABLE _hrc-close-starts
VARIABLE _hrc-close-polls
VARIABLE _hrc-close-polls-this
VARIABLE _hrc-close-poll-throw
VARIABLE _hrc-release-mode
VARIABLE _hrc-media-mode
VARIABLE _hrc-media-calls
VARIABLE _hrc-media-errors
VARIABLE _hrc-forbid-io
VARIABLE _hrc-late-io
VARIABLE _hrc-lease-errors
VARIABLE _hrc-io-a
VARIABLE _hrc-io-u
VARIABLE _hrc-io-n
VARIABLE _hrc-io-rem
VARIABLE _hrc-copy-a
VARIABLE _hrc-copy-u
VARIABLE _hrc-location-a
VARIABLE _hrc-location-u
VARIABLE _hrc-mode
VARIABLE _hrc-uri-a
VARIABLE _hrc-uri-u
VARIABLE _hrc-redirect-max
VARIABLE _hrc-body-cap
VARIABLE _hrc-path-a
VARIABLE _hrc-path-u
VARIABLE _hrc-host-a
VARIABLE _hrc-host-u
VARIABLE _hrc-case-outcome
VARIABLE _hrc-case-detail
VARIABLE _hrc-case-mode
VARIABLE _hrc-hop-index
VARIABLE _hrc-hop-status

: _hrc-zero?  ( addr len -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;

: _hrc-response-a  ( hop -- a )
    _HRC-RESPONSE-CAP * _hrc-responses + ;

: _hrc-response-u-a  ( hop -- a )
    8 * _hrc-response-us + ;

: _hrc-response-u@  ( hop -- u )
    _hrc-response-u-a @ ;

: _hrc-sent-a  ( hop -- a )
    HRES-REQUEST-MAX * _hrc-sent + ;

: _hrc-sent-u-a  ( hop -- a )
    8 * _hrc-sent-us + ;

: _hrc-sent-u@  ( hop -- u )
    _hrc-sent-u-a @ ;

: _hrc-response-select  ( hop -- )
    DUP _hrc-build-hop !
    DUP _hrc-response-a _HRC-RESPONSE-CAP 0 FILL
    _hrc-response-u-a 0 SWAP ! ;

: _hrc-response,  ( addr len -- )
    _hrc-copy-u ! _hrc-copy-a !
    _hrc-build-hop @ _hrc-response-u@
    _hrc-copy-u @ + _HRC-RESPONSE-CAP > IF
        1 _hrc-lease-errors +! EXIT
    THEN
    _hrc-copy-a @
    _hrc-build-hop @ _hrc-response-a
    _hrc-build-hop @ _hrc-response-u@ +
    _hrc-copy-u @ CMOVE
    _hrc-copy-u @ _hrc-build-hop @ _hrc-response-u-a +! ;

: _hrc-response-crlf,  ( -- )
    13 _hrc-build-hop @ _hrc-response-a
        _hrc-build-hop @ _hrc-response-u@ + C!
    1 _hrc-build-hop @ _hrc-response-u-a +!
    10 _hrc-build-hop @ _hrc-response-a
        _hrc-build-hop @ _hrc-response-u@ + C!
    1 _hrc-build-hop @ _hrc-response-u-a +! ;

: _hrc-response-line,  ( addr len -- )
    _hrc-response, _hrc-response-crlf, ;

: _hrc-content-length,  ( length -- )
    S" Content-Length: " _hrc-response,
    NUM>STR _hrc-response, _hrc-response-crlf, ;

: _hrc-expected,  ( addr len -- )
    DUP >R _hrc-expected _hrc-expected-u @ + SWAP CMOVE
    R> _hrc-expected-u +! ;

: _hrc-expected-crlf,  ( -- )
    13 _hrc-expected _hrc-expected-u @ + C! 1 _hrc-expected-u +!
    10 _hrc-expected _hrc-expected-u @ + C! 1 _hrc-expected-u +! ;

: _hrc-build-expected  ( path-a path-u host-a host-u -- )
    _hrc-host-u ! _hrc-host-a ! _hrc-path-u ! _hrc-path-a !
    _hrc-expected HRES-REQUEST-MAX 0 FILL 0 _hrc-expected-u !
    S" GET " _hrc-expected,
    _hrc-path-a @ _hrc-path-u @ _hrc-expected,
    S"  HTTP/1.1" _hrc-expected, _hrc-expected-crlf,
    S" Host: " _hrc-expected,
    _hrc-host-a @ _hrc-host-u @ _hrc-expected, _hrc-expected-crlf,
    S" Accept: application/feed+json, application/atom+xml, application/rss+xml"
        _hrc-expected, _hrc-expected-crlf,
    S" Accept-Encoding: identity" _hrc-expected, _hrc-expected-crlf,
    S" User-Agent: Akashic-HTTP-Resource/0.1"
        _hrc-expected, _hrc-expected-crlf,
    S" Connection: close" _hrc-expected, _hrc-expected-crlf,
    _hrc-expected-crlf, ;

: _hrc-wire?  ( hop -- flag )
    DUP _hrc-sent-a SWAP _hrc-sent-u@
    _hrc-expected _hrc-expected-u @ STR-STR= ;

: _hrc-note-io  ( -- )
    _hrc-forbid-io @ IF 1 _hrc-late-io +! THEN ;

: _hrc-open-start  ( context -- io-status )
    DROP _hrc-note-io 1 _hrc-open-starts +!
    0 _hrc-open-polls-this ! NIO-S-PENDING ;

: _hrc-open-poll  ( context -- io-status )
    DROP _hrc-note-io 1 _hrc-open-polls +!
    1 _hrc-open-polls-this +!
    _hrc-open-polls-this @ 2 >= IF NIO-S-OK ELSE NIO-S-PENDING THEN ;

: _hrc-send  ( buffer length context -- count io-status )
    DROP _hrc-io-u ! _hrc-io-a ! _hrc-note-io
    1 _hrc-send-calls +!
    _hrc-active-hop @ DUP 0< SWAP _HRC-HOP-CAP >= OR IF
        0 NIO-S-FAILED EXIT
    THEN
    _hrc-io-u @ 11 MIN _hrc-io-n !
    _hrc-active-hop @ _hrc-sent-u@
    _hrc-io-n @ + HRES-REQUEST-MAX > IF 0 NIO-S-FAILED EXIT THEN
    _hrc-io-a @
    _hrc-active-hop @ _hrc-sent-a
    _hrc-active-hop @ _hrc-sent-u@ +
    _hrc-io-n @ CMOVE
    _hrc-io-n @ _hrc-active-hop @ _hrc-sent-u-a +!
    _hrc-io-n @ NIO-S-OK ;

: _hrc-recv  ( buffer capacity context -- count io-status )
    DROP _hrc-io-u ! _hrc-io-a ! _hrc-note-io
    1 _hrc-recv-calls +!
    _hrc-active-hop @ DUP 0< SWAP _HRC-HOP-CAP >= OR IF
        0 NIO-S-FAILED EXIT
    THEN
    _hrc-active-hop @ _hrc-response-u@ _hrc-response-pos @ -
    DUP _hrc-io-rem ! 0= IF 0 NIO-S-EOF EXIT THEN
    _hrc-io-rem @ _hrc-io-u @ MIN 13 MIN _hrc-io-n !
    _hrc-active-hop @ _hrc-response-a _hrc-response-pos @ +
    _hrc-io-a @ _hrc-io-n @ CMOVE
    _hrc-io-n @ _hrc-response-pos +!
    _hrc-io-n @ NIO-S-OK ;

: _hrc-poll  ( context -- )
    DROP _hrc-note-io 1 _hrc-poll-calls +! ;

: _hrc-cancel  ( context -- )
    DROP 1 _hrc-cancels +!
    _hrc-cancel-throw @ IF -7630 THROW THEN ;

: _hrc-close-start  ( context -- io-status )
    DROP _hrc-note-io 1 _hrc-close-starts +!
    0 _hrc-close-polls-this ! NIO-S-PENDING ;

: _hrc-close-poll  ( context -- io-status )
    DROP _hrc-note-io 1 _hrc-close-polls +!
    _hrc-close-poll-throw @ IF -7620 THROW THEN
    1 _hrc-close-polls-this +!
    _hrc-close-polls-this @ 2 >= IF NIO-S-OK ELSE NIO-S-PENDING THEN ;

: _hrc-port-install  ( -- )
    _hrc-port NIO-INIT
    _hrc-port _hrc-port NIO.CONTEXT !
    ['] _hrc-open-start _hrc-port NIO.OPEN-START-XT !
    ['] _hrc-open-poll _hrc-port NIO.OPEN-POLL-XT !
    ['] _hrc-send _hrc-port NIO.SEND-XT !
    ['] _hrc-recv _hrc-port NIO.RECV-XT !
    ['] _hrc-poll _hrc-port NIO.POLL-XT !
    ['] _hrc-cancel _hrc-port NIO.CANCEL-XT !
    ['] _hrc-close-start _hrc-port NIO.CLOSE-START-XT !
    ['] _hrc-close-poll _hrc-port NIO.CLOSE-POLL-XT ! ;

: _hrc-fixture-reset  ( -- )
    _hrc-responses _HRC-HOP-CAP _HRC-RESPONSE-CAP * 0 FILL
    _hrc-response-us _HRC-HOP-CAP 8 * 0 FILL
    _hrc-sent _HRC-HOP-CAP HRES-REQUEST-MAX * 0 FILL
    _hrc-sent-us _HRC-HOP-CAP 8 * 0 FILL
    _hrc-expected HRES-REQUEST-MAX 0 FILL
    0 _hrc-expected-u ! 0 _hrc-active-hop ! 0 _hrc-response-pos !
    0 _hrc-binds ! 0 _hrc-releases !
    0 _hrc-open-starts ! 0 _hrc-open-polls !
    0 _hrc-open-polls-this ! 0 _hrc-send-calls ! 0 _hrc-recv-calls !
    0 _hrc-poll-calls ! 0 _hrc-cancels ! 0 _hrc-cancel-throw !
    0 _hrc-close-starts ! 0 _hrc-close-polls !
    0 _hrc-close-polls-this ! 0 _hrc-close-poll-throw !
    0 _hrc-release-mode !
    0 _hrc-bind-status !
    -1 _hrc-release-open-state ! -1 _hrc-release-close-state !
    0 _hrc-media-mode ! 0 _hrc-media-calls ! 0 _hrc-media-errors !
    0 _hrc-forbid-io ! 0 _hrc-late-io ! 0 _hrc-lease-errors !
    _hrc-port-install _hrc-port _hrc-bind-port ! ;

: _hrc-bind  ( target context -- port provider-status )
    _hrc-resource <> IF 1 _hrc-lease-errors +! THEN
    HTARGET-VALID? 0= IF 1 _hrc-lease-errors +! THEN
    _hrc-binds @ _HRC-HOP-CAP >= IF 0 -7600 EXIT THEN
    _hrc-binds @ _hrc-active-hop ! 1 _hrc-binds +!
    0 _hrc-response-pos !
    _hrc-bind-port @ _hrc-bind-status @ ;

: _hrc-release  ( port context -- provider-status )
    _hrc-resource <> IF 1 _hrc-lease-errors +! THEN
    _hrc-port <> IF 1 _hrc-lease-errors +! THEN
    _hrc-resource HRES.EXCHANGE HBUF.PORT @ IF
        1 _hrc-lease-errors +!
    THEN
    _hrc-port NIO.OPEN-STATE @ DUP _hrc-release-open-state !
    DUP NIO-OPEN-STATE-CLOSED = SWAP NIO-OPEN-STATE-CANCELLED = OR 0= IF
        1 _hrc-lease-errors +!
    THEN
    _hrc-port NIO.CLOSE-STATE @ DUP _hrc-release-close-state !
    DUP NIO-CLOSE-STATE-IDLE = OVER NIO-CLOSE-STATE-CLOSED = OR
    SWAP NIO-CLOSE-STATE-CANCELLED = OR 0= IF
        1 _hrc-lease-errors +!
    THEN
    1 _hrc-releases +!
    _hrc-release-mode @ IF -7601 ELSE 0 THEN ;

: _hrc-media-policy  ( media context -- media-status )
    _hrc-resource <> IF 1 _hrc-media-errors +! THEN
    MTYPE-VALID? 0= IF 1 _hrc-media-errors +! THEN
    1 _hrc-media-calls +!
    _hrc-media-mode @ 1 = IF -7610 EXIT THEN
    _hrc-media-mode @ 2 = IF -7611 THROW THEN
    _hrc-media-mode @ 3 = IF
        MS@ _hrc-operation XIOO.DEADLINE-MS !
    THEN
    0 ;

: _hrc-build-ok  ( hop -- )
    _hrc-response-select
    S" HTTP/1.1 200 OK" _hrc-response-line,
    S" Content-Type: application/feed+json; charset=utf-8"
        _hrc-response-line,
    S" ETag: v1" _hrc-response-line,
    S" Last-Modified: Wed, 16 Jul 2026 12:00:00 GMT"
        _hrc-response-line,
    5 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    S" hello" _hrc-response, ;

: _hrc-build-second  ( hop -- )
    _hrc-response-select
    S" HTTP/1.1 200 OK" _hrc-response-line,
    S" Content-Type: text/plain" _hrc-response-line,
    6 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    S" second" _hrc-response, ;

: _hrc-build-two-params  ( duplicate? -- )
    _hrc-mode ! 0 _hrc-response-select
    S" HTTP/1.1 200 OK" _hrc-response-line,
    _hrc-mode @ IF
        S" Content-Type: application/feed+json; charset=utf-8; CHARSET=us-ascii"
    ELSE
        S" Content-Type: application/feed+json; charset=utf-8; profile=full"
    THEN _hrc-response-line,
    5 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    S" hello" _hrc-response, ;

: _hrc-build-redirect  ( hop location-a location-u -- )
    _hrc-location-u ! _hrc-location-a ! _hrc-response-select
    S" HTTP/1.1 302 Found" _hrc-response-line,
    S" Location: " _hrc-response,
    _hrc-location-a @ _hrc-location-u @ _hrc-response,
    _hrc-response-crlf,
    0 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf, ;

: _hrc-build-full-budget-redirect  ( -- )
    0 _hrc-response-select
    S" HTTP/1.1 302 Found" _hrc-response-line,
    S" Location: /next" _hrc-response-line,
    5 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    S" 12345" _hrc-response, ;

: _hrc-build-bad  ( mode -- )
    _hrc-mode ! 0 _hrc-response-select
    _hrc-mode @ 3 = IF
        S" HTTP/1.1 304 Not Modified"
    ELSE
        _hrc-mode @ 4 = IF
            S" HTTP/1.1 404 Not Found"
        ELSE
            _hrc-mode @ 5 >= IF
                S" HTTP/1.1 302 Found"
            ELSE
                S" HTTP/1.1 200 OK"
            THEN
        THEN
    THEN _hrc-response-line,
    _hrc-mode @ 5 >= IF
        _hrc-mode @ 6 <> IF
            S" Location: /next" _hrc-response-line,
        THEN
        _hrc-mode @ 5 = IF
            S" Location: /other" _hrc-response-line,
        THEN
    ELSE
        _hrc-mode @ 0 <> IF
            S" Content-Type: application/feed+json" _hrc-response-line,
        THEN
        _hrc-mode @ 1 = IF
            S" Content-Type: application/feed+json" _hrc-response-line,
        THEN
        _hrc-mode @ 2 = IF
            S" Content-Encoding: gzip" _hrc-response-line,
        THEN
    THEN
    _hrc-mode @ 3 = _hrc-mode @ 5 >= OR IF 0 ELSE 2 THEN
        _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    _hrc-mode @ 3 <> _hrc-mode @ 5 < AND IF
        S" {}" _hrc-response,
    THEN ;

: _hrc-build-overflow  ( -- )
    0 _hrc-response-select
    S" HTTP/1.1 200 OK" _hrc-response-line,
    S" Content-Type: application/feed+json" _hrc-response-line,
    9 _hrc-content-length,
    S" Connection: close" _hrc-response-line,
    _hrc-response-crlf,
    S" 123456789" _hrc-response, ;

: _hrc-setup  ( uri-a uri-u redirect-max body-cap -- )
    _hrc-body-cap ! _hrc-redirect-max !
    _hrc-uri-u ! _hrc-uri-a !
    _hrc-spec HRES-SPEC-INIT
    _hrc-uri-a @ _hrc-uri-u @ _hrc-spec HRES-SPEC-TARGET!
        HRES-S-OK = _hrc-assert
    S" application/feed+json, application/atom+xml, application/rss+xml"
        _hrc-spec HRES-SPEC-ACCEPT! HRES-S-OK = _hrc-assert
    _hrc-redirect-max @ _hrc-spec HRES-SPEC-REDIRECT-MAX!
        HRES-S-OK = _hrc-assert
    _hrc-resource ['] _hrc-bind ['] _hrc-release
        _hrc-spec HRES-SPEC-BINDING! HRES-S-OK = _hrc-assert
    _hrc-resource ['] _hrc-media-policy _hrc-spec HRES-SPEC-MEDIA!
        HRES-S-OK = _hrc-assert
    _hrc-spec HRES-SPEC-SEAL HRES-S-OK = _hrc-assert
    _hrc-spec HRES-SPEC-VALID? _hrc-assert
    _hrc-resource HRES-INIT
    _hrc-spec _hrc-body _hrc-body-cap @ _hrc-resource HRES-CONFIGURE
        HRES-S-OK = _hrc-assert
    _hrc-resource HRES-VALID? _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-CONFIGURED = _hrc-assert ;

: _hrc-pump-active  ( -- status )
    4000 0 DO
        _hrc-resource HRES-POLL DUP HRES-S-PENDING <> IF
            UNLOOP EXIT
        THEN DROP
    LOOP HRES-S-PENDING ;

: _hrc-run-resource  ( -- status )
    _hrc-resource HRES-START DUP HRES-S-PENDING <> IF EXIT THEN DROP
    _hrc-pump-active ;

: _hrc-clean-result  ( -- )
    _hrc-resource HRES-WIPE HRES-S-OK = _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-IDLE = _hrc-assert ;

: _hrc-hop-status?  ( index expected-status -- )
    _hrc-hop-status ! _hrc-hop-index !
    _hrc-hop-index @ _hrc-resource HRES-HOP@ _hrc-assert
    _hrc-hop-status @ = _hrc-assert
    HTARGET-VALID? _hrc-assert ;

: _hrc-result-basics  ( -- )
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-OK = _hrc-assert
    _hrc-resource HRES-PROVIDER-STATUS@ 0= _hrc-assert
    _hrc-resource HRES-TRANSPORT-STATUS@ HBUF-S-OK = _hrc-assert
    _hrc-resource HRES-PARSER-STATUS@ HSTR-S-OK = _hrc-assert
    _hrc-resource HRES-POLICY-STATUS@ HTARGET-S-OK = _hrc-assert
    _hrc-resource HRES-LAST-STATUS@ HRES-S-OK = _hrc-assert
    _hrc-resource HRES-EXCHANGE-STATUS@ HBUF-S-OK = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 200 = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? _hrc-assert
    _hrc-resource HRES-BODY@ S" hello" STR-STR= _hrc-assert
    _hrc-resource HRES-ETAG@ _hrc-assert
        S" v1" STR-STR= _hrc-assert
    _hrc-resource HRES-LAST-MODIFIED@ _hrc-assert
        S" Wed, 16 Jul 2026 12:00:00 GMT" STR-STR= _hrc-assert
    _hrc-resource HRES-MEDIA@ _hrc-assert
    DUP MTYPE-TYPE$ S" application" STR-STRI= _hrc-assert
    DUP MTYPE-SUBTYPE$ S" feed+json" STR-STRI= _hrc-assert
    MTYPE-PARAM-COUNT@ 1 = _hrc-assert ;

: _hrc-test-idle-cleanup  ( -- )
    _hrc-resource HRES-INIT
    _hrc-resource HRES-VALID? _hrc-assert
    _hrc-resource HRES-CANCEL HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-IDLE = _hrc-assert
    _hrc-resource HRES-VALID? _hrc-assert
    _hrc-resource HRES-INIT
    _hrc-resource HRES-WIPE HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-IDLE = _hrc-assert
    _hrc-resource HRES-VALID? _hrc-assert
    _hrc-stack ;

: _hrc-test-success  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test:8443/feed?x=%3a" 3 128 _hrc-setup
    _hrc-resource HRES-START HRES-S-PENDING = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert
    _hrc-open-starts @ 1 = _hrc-assert
    _hrc-open-polls @ 0= _hrc-assert
    _hrc-send-calls @ 0= _hrc-assert
    _hrc-resource HRES-POLL HRES-S-PENDING = _hrc-assert
    _hrc-open-polls @ 1 = _hrc-assert _hrc-send-calls @ 0= _hrc-assert
    _hrc-resource HRES-POLL HRES-S-PENDING = _hrc-assert
    _hrc-open-polls @ 2 = _hrc-assert _hrc-send-calls @ 0= _hrc-assert
    _hrc-resource HRES-POLL HRES-S-PENDING = _hrc-assert
    _hrc-send-calls @ 1 = _hrc-assert
    _hrc-pump-active HRES-S-OK = _hrc-assert
    _hrc-result-basics
    _hrc-resource HRES-REQUESTED-URI$
        S" https://feeds.example.test:8443/feed?x=%3A"
        STR-STR= _hrc-assert
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://feeds.example.test:8443/feed?x=%3A"
        STR-STR= _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 0= _hrc-assert
    0 200 _hrc-hop-status?
    S" /feed?x=%3A" S" feeds.example.test:8443" _hrc-build-expected
    0 _hrc-wire? _hrc-assert
    0 _hrc-sent-a 0 _hrc-sent-u@ S" Authorization"
        STR-STRI-CONTAINS 0= _hrc-assert
    0 _hrc-sent-a 0 _hrc-sent-u@ S" Cookie"
        STR-STRI-CONTAINS 0= _hrc-assert
    _hrc-send-calls @ 1 > _hrc-assert _hrc-recv-calls @ 1 > _hrc-assert
    _hrc-close-starts @ 1 = _hrc-assert
    _hrc-close-polls @ 2 = _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert _hrc-media-errors @ 0= _hrc-assert
    _hrc-resource HRES-MEDIA-STATUS@ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PARSER HSTR.HEADER-BUF
        HSTR-HEADER-CAPACITY [CHAR] X FILL
    _hrc-result-basics
    _hrc-resource HRES-START HRES-S-BUSY = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-test-redirect-success  ( -- )
    _hrc-fixture-reset
    0 S" /next?z=1" _hrc-build-redirect
    1 _hrc-build-ok
    S" https://feeds.example.test/feed" 3 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-result-basics
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    _hrc-resource HRES-REQUESTED-URI$
        S" https://feeds.example.test/feed" STR-STR= _hrc-assert
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://feeds.example.test/next?z=1" STR-STR= _hrc-assert
    _hrc-resource HRES-LOCATION@ _hrc-assert
        S" /next?z=1" STR-STR= _hrc-assert
    0 302 _hrc-hop-status? 1 200 _hrc-hop-status?
    S" /feed" S" feeds.example.test" _hrc-build-expected
    0 _hrc-wire? _hrc-assert
    S" /next?z=1" S" feeds.example.test" _hrc-build-expected
    1 _hrc-wire? _hrc-assert
    _hrc-binds @ 2 = _hrc-assert _hrc-releases @ 2 = _hrc-assert
    _hrc-open-starts @ 2 = _hrc-assert
    _hrc-close-starts @ 2 = _hrc-assert
    _hrc-close-polls @ 4 = _hrc-assert _hrc-cancels @ 0= _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert _hrc-media-errors @ 0= _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-test-redirect-rejections  ( -- )
    _hrc-fixture-reset
    0 S" https://other.example.test/feed" _hrc-build-redirect
    S" https://feeds.example.test/a" 3 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-AUTHORITY-REQUIRED = _hrc-assert
    _hrc-resource HRES-DETAIL@ HTARGET-S-AUTHORITY-REQUIRED = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 0= _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-open-starts @ 1 = _hrc-assert
    _hrc-clean-result

    _hrc-fixture-reset
    0 S" /b" _hrc-build-redirect
    1 S" /a" _hrc-build-redirect
    S" https://feeds.example.test/a" 3 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-REDIRECT-LOOP = _hrc-assert
    _hrc-resource HRES-DETAIL@ HTARGET-S-LOOP = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    _hrc-binds @ 2 = _hrc-assert _hrc-open-starts @ 2 = _hrc-assert
    2 _hrc-resource HRES-HOP@ 0= _hrc-assert 2DROP
    _hrc-clean-result

    _hrc-fixture-reset
    0 S" /b" _hrc-build-redirect
    1 S" /c" _hrc-build-redirect
    S" https://feeds.example.test/a" 1 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-REDIRECT-LIMIT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HTARGET-S-REDIRECT-LIMIT = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    _hrc-binds @ 2 = _hrc-assert _hrc-open-starts @ 2 = _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-test-exact-redirect-budget  ( -- )
    _hrc-fixture-reset _hrc-build-full-budget-redirect
    S" https://feeds.example.test/feed" 3 5 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-BODY-OVERFLOW = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-BODY-BUDGET = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 302 = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    0 302 _hrc-hop-status?
    1 _hrc-resource HRES-HOP@ _hrc-assert
        0= _hrc-assert HTARGET-VALID? _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-open-starts @ 1 = _hrc-assert
    _hrc-send-calls @ 0> _hrc-assert _hrc-recv-calls @ 0> _hrc-assert
    1 _hrc-sent-u@ 0= _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 5 _hrc-zero? _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-admission-case  ( mode expected-outcome expected-detail -- )
    _hrc-case-detail ! _hrc-case-outcome ! _hrc-case-mode !
    _hrc-fixture-reset _hrc-case-mode @ _hrc-build-bad
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ _hrc-case-outcome @ = _hrc-assert
    _hrc-resource HRES-DETAIL@ _hrc-case-detail @ = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-close-starts @ 1 = _hrc-assert _hrc-cancels @ 0= _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert _hrc-media-errors @ 0= _hrc-assert
    _hrc-clean-result ;

: _hrc-test-admission  ( -- )
    0 HRES-O-MEDIA HRES-D-CONTENT-TYPE-MISSING _hrc-admission-case
    1 HRES-O-HEADER HRES-D-CONTENT-TYPE-DUPLICATE _hrc-admission-case
    2 HRES-O-CONTENT-ENCODING HRES-D-CONTENT-ENCODING-MISMATCH
        _hrc-admission-case
    3 HRES-O-HTTP 304 _hrc-admission-case
    4 HRES-O-HTTP 404 _hrc-admission-case
    5 HRES-O-HEADER HRES-D-LOCATION-DUPLICATE _hrc-admission-case
    6 HRES-O-REDIRECT-INVALID HRES-D-LOCATION-MISSING
        _hrc-admission-case
    _hrc-stack ;

: _hrc-test-overflow  ( -- )
    _hrc-fixture-reset _hrc-build-overflow
    S" https://feeds.example.test/feed" 2 8 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-BODY-OVERFLOW = _hrc-assert
    _hrc-resource HRES-DETAIL@ HSTR-S-BODY-OVERFLOW = _hrc-assert
    _hrc-resource HRES-PARSER-STATUS@
        HSTR-S-BODY-OVERFLOW = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 200 = _hrc-assert
    0 200 _hrc-hop-status?
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 8 _hrc-zero? _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert
    _hrc-close-starts @ 0= _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-test-close-failure-fallback  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    -1 _hrc-close-poll-throw !
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-TRANSPORT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HBUF-S-TRANSPORT = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ -7620 = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 200 = _hrc-assert
    0 200 _hrc-hop-status?
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-close-starts @ 1 = _hrc-assert
    _hrc-close-polls @ 1 = _hrc-assert _hrc-cancels @ 1 = _hrc-assert
    _hrc-releases @ 1 = _hrc-assert _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-test-cancel  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    _hrc-resource HRES-START HRES-S-PENDING = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-open-starts @ 1 = _hrc-assert
    _hrc-resource HRES-CANCEL HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RELEASED = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-CANCELLED = _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-close-starts @ 0= _hrc-assert _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert
    -1 _hrc-forbid-io !
    _hrc-resource HRES-POLL HRES-S-STATE = _hrc-assert
    _hrc-resource HRES-CANCEL HRES-S-OK = _hrc-assert
    _hrc-resource HRES-WIPE HRES-S-OK = _hrc-assert
    _hrc-resource HRES-POLL HRES-S-STATE = _hrc-assert
    _hrc-late-io @ 0= _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    0 _hrc-forbid-io !
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-stack ;

: _hrc-test-clean-reuse  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok 1 _hrc-build-second
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-result-basics
    _hrc-resource HRES-START HRES-S-BUSY = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert
    _hrc-resource HRES-WIPE HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RELEASED = _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-port NIO.OPEN-START-XT @ ['] _hrc-open-start = _hrc-assert
    _hrc-port NIO.CLOSE-POLL-XT @ ['] _hrc-close-poll = _hrc-assert
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-OK = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? _hrc-assert
    _hrc-resource HRES-BODY@ S" second" STR-STR= _hrc-assert
    _hrc-resource HRES-MEDIA@ _hrc-assert
    DUP MTYPE-TYPE$ S" text" STR-STRI= _hrc-assert
    MTYPE-SUBTYPE$ S" plain" STR-STRI= _hrc-assert
    _hrc-resource HRES-ETAG@ 0= _hrc-assert 2DROP
    _hrc-resource HRES-LAST-MODIFIED@ 0= _hrc-assert 2DROP
    _hrc-resource HRES-REDIRECT-COUNT@ 0= _hrc-assert
    S" /feed" S" feeds.example.test" _hrc-build-expected
    0 _hrc-wire? _hrc-assert 1 _hrc-wire? _hrc-assert
    _hrc-binds @ 2 = _hrc-assert _hrc-releases @ 2 = _hrc-assert
    _hrc-open-starts @ 2 = _hrc-assert
    _hrc-close-starts @ 2 = _hrc-assert
    _hrc-close-polls @ 4 = _hrc-assert _hrc-cancels @ 0= _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-media-calls @ 2 = _hrc-assert _hrc-media-errors @ 0= _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-test-media-policy  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    1 _hrc-media-mode !
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-MEDIA = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-MEDIA-REJECTED = _hrc-assert
    _hrc-resource HRES-MEDIA-STATUS@ -7610 = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert _hrc-media-errors @ 0= _hrc-assert
    _hrc-releases @ 1 = _hrc-assert _hrc-clean-result

    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    2 _hrc-media-mode !
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-MEDIA-REJECTED = _hrc-assert
    _hrc-resource HRES-MEDIA-STATUS@ -7611 = _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert _hrc-media-errors @ 0= _hrc-assert
    _hrc-releases @ 1 = _hrc-assert
    _hrc-resource HRES-WIPE HRES-S-OK = _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-stack ;

: _hrc-test-media-params  ( -- )
    _hrc-fixture-reset 0 _hrc-build-two-params
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-OK = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? _hrc-assert
    _hrc-resource HRES-MEDIA@ _hrc-assert
    MTYPE-PARAM-COUNT@ 2 = _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert
    _hrc-releases @ 1 = _hrc-assert
    _hrc-clean-result

    _hrc-fixture-reset -1 _hrc-build-two-params
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-MEDIA = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-MEDIA-PARAM-DUPLICATE = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES.MEDIA MTYPE-PARAM-COUNT@ 2 = _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert
    _hrc-releases @ 1 = _hrc-assert
    _hrc-clean-result _hrc-stack ;

: _hrc-pb-setup  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup ;

: _hrc-pb-open  ( -- )
    NIO-OPEN-STATE-OPEN _hrc-port NIO.OPEN-STATE !
    NIO-S-OK _hrc-port NIO.OPEN-STATUS ! ;

: _hrc-pb-noncoop  ( -- )
    0 _hrc-port NIO.RECV-XT ! ;

: _hrc-pb-no-actions  ( -- )
    _hrc-open-starts @ 0= _hrc-assert
    _hrc-open-polls @ 0= _hrc-assert
    _hrc-send-calls @ 0= _hrc-assert _hrc-recv-calls @ 0= _hrc-assert
    _hrc-close-starts @ 0= _hrc-assert _hrc-close-polls @ 0= _hrc-assert
    _hrc-media-calls @ 0= _hrc-assert ;

: _hrc-pb-sensitive-zero  ( -- )
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-resource HRES.WIRE HRES-REQUEST-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.HOST-VALUE 72 _hrc-zero? _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.REQUEST @ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.BODY-A @ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.BODY-CAP @ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.BODY-U @ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.RECV HBUF-RECV-CAPACITY
        _hrc-zero? _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PARSER HSTR.HEADER-BUF
        HSTR-HEADER-CAPACITY _hrc-zero? _hrc-assert
    _hrc-resource HRES.LOCATION HRES-LOCATION-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.LOCATION-U @ 0= _hrc-assert
    _hrc-resource HRES.LOCATION-PRESENT @ 0= _hrc-assert
    _hrc-resource HRES.ETAG HRES-ETAG-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.ETAG-U @ 0= _hrc-assert
    _hrc-resource HRES.ETAG-PRESENT @ 0= _hrc-assert
    _hrc-resource HRES.LAST-MODIFIED HRES-LAST-MODIFIED-MAX
        _hrc-zero? _hrc-assert
    _hrc-resource HRES.LAST-MODIFIED-U @ 0= _hrc-assert
    _hrc-resource HRES.LAST-MODIFIED-PRESENT @ 0= _hrc-assert
    _hrc-resource HRES.MEDIA MTYPE-VALID? 0= _hrc-assert ;

: _hrc-pb-fault-clear  ( -- )
    _hrc-resource HRES-WIPE HRES-S-OK = _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert ;

: _hrc-quarantine-dispose  ( -- )
    \ Test-only provider disposition after HRES has terminally quarantined
    \ the retained lease.  HRES remains poisoned; only the fake port is made
    \ safe before a later fixture initializes fresh ownership state.
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0<> _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ _hrc-port = _hrc-assert
    0 _hrc-cancel-throw !
    0 _hrc-port NIO.CLEANUP-FLAGS !
    0 _hrc-port NIO.CANCEL-ERROR ! 0 _hrc-port NIO.CLOSE-ERROR !
    NIO-OPEN-STATE-CLOSED _hrc-port NIO.OPEN-STATE !
    NIO-S-OK _hrc-port NIO.OPEN-STATUS !
    NIO-CLOSE-STATE-CLOSED _hrc-port NIO.CLOSE-STATE !
    NIO-S-OK _hrc-port NIO.CLOSE-STATUS !
    _hrc-port NIO.OPEN-STATE @ NIO-OPEN-STATE-CLOSED = _hrc-assert
    _hrc-port NIO.CLOSE-STATE @ NIO-CLOSE-STATE-CLOSED = _hrc-assert
    _hrc-port NIO.CANCEL-ERROR @ 0= _hrc-assert
    _hrc-port NIO.CLOSE-ERROR @ 0= _hrc-assert ;

: _hrc-pb-open-success  ( -- )
    _hrc-pb-setup _hrc-pb-open
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-PORT-NOT-DETACHED = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ 0= _hrc-assert
    _hrc-resource HRES-PROVIDER-STATUS@ 0= _hrc-assert
    _hrc-resource HRES-TRANSPORT-STATUS@ HBUF-S-OK = _hrc-assert
    _hrc-resource HRES-PARSER-STATUS@ HSTR-S-OK = _hrc-assert
    _hrc-resource HRES-POLICY-STATUS@ HTARGET-S-OK = _hrc-assert
    _hrc-resource HRES-LAST-STATUS@ HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-EXCHANGE-STATUS@ HBUF-S-OK = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-cancels @ 1 = _hrc-assert
    _hrc-releases @ 1 = _hrc-assert _hrc-lease-errors @ 0= _hrc-assert
    _hrc-release-open-state @ NIO-OPEN-STATE-CANCELLED = _hrc-assert
    _hrc-release-close-state @ NIO-CLOSE-STATE-CANCELLED = _hrc-assert
    _hrc-port NIO.OPEN-STATE @ NIO-OPEN-STATE-CANCELLED = _hrc-assert
    _hrc-port NIO.CLOSE-STATE @ NIO-CLOSE-STATE-CANCELLED = _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PORT @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-sensitive-zero _hrc-pb-fault-clear ;

: _hrc-pb-open-xio  ( -- )
    _hrc-pb-setup _hrc-pb-open
    _hrc-service XIO-SERVICE-INIT XIO-S-OK = _hrc-assert
    _hrc-operation XIO-OP-INIT
    _hrc-service 77 1 1 0 _hrc-resource
        ['] HRES-XIO-START ['] HRES-XIO-POLL
        ['] HRES-XIO-CANCEL ['] HRES-XIO-WIPE
        _hrc-operation XIO-OP-CONFIGURE XIO-S-OK = _hrc-assert
    _hrc-service _hrc-operation XIO-SUBMIT XIO-S-OK = _hrc-assert
    _hrc-service XIO-TICK
    _hrc-operation XIOO.STATE @ XIO-STATE-FAILED = _hrc-assert
    _hrc-operation XIOO.ERROR @ HRES-XERR-FAULT = _hrc-assert
    _hrc-operation XIOO.RESULT @ 0= _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-PORT-NOT-DETACHED = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-cancels @ 1 = _hrc-assert
    _hrc-releases @ 1 = _hrc-assert _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions
    _hrc-service _hrc-operation XIO-RESET XIO-S-OK = _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-service XIO-SERVICE-FINI XIO-S-OK = _hrc-assert ;

: _hrc-pb-close-error  ( -- )
    _hrc-pb-setup _hrc-pb-open
    -7641 _hrc-port NIO.CLOSE-ERROR !
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-PORT-NOT-DETACHED = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ -7641 = _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-release-open-state @ NIO-OPEN-STATE-CANCELLED = _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-fault-clear ;

: _hrc-pb-cancel-error  ( -- )
    _hrc-pb-setup _hrc-pb-open
    -7641 _hrc-port NIO.CLOSE-ERROR !
    -7642 _hrc-port NIO.CANCEL-ERROR !
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-PORT-NOT-DETACHED = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ -7642 = _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-release-open-state @ NIO-OPEN-STATE-CANCELLED = _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-fault-clear ;

: _hrc-pb-cancel-throw  ( -- )
    _hrc-pb-setup _hrc-pb-open -1 _hrc-cancel-throw !
    _hrc-run-resource HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-PORT-NOT-DETACHED = _hrc-assert
    _hrc-resource HRES-CLEANUP@ HRES-XERR-CLEANUP = _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ -7630 = _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 0= _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ _hrc-port = _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PORT @ 0= _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-sensitive-zero
    -1 _hrc-forbid-io !
    _hrc-resource HRES-POLL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-CANCEL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-WIPE HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-START HRES-S-CLEANUP = _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 0= _hrc-assert
    _hrc-late-io @ 0= _hrc-assert
    _hrc-quarantine-dispose ;

: _hrc-pb-noncoop-detached  ( -- )
    _hrc-pb-setup _hrc-pb-noncoop
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-NONCOOPERATIVE = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-release-open-state @ NIO-OPEN-STATE-CLOSED = _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ 0= _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-fault-clear ;

: _hrc-pb-noncoop-open  ( -- )
    _hrc-pb-setup _hrc-pb-noncoop _hrc-pb-open
    _hrc-run-resource HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-NONCOOPERATIVE = _hrc-assert
    _hrc-resource HRES-CLEANUP@ HRES-XERR-CLEANUP = _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ 0= _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-releases @ 0= _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ _hrc-port = _hrc-assert
    _hrc-port NIO.OPEN-STATE @ NIO-OPEN-STATE-OPEN = _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-sensitive-zero
    _hrc-quarantine-dispose ;

: _hrc-pb-error-no-port  ( -- )
    _hrc-pb-setup 0 _hrc-bind-port ! -7640 _hrc-bind-status !
    _hrc-run-resource HRES-S-OK = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-TRANSPORT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-BIND-PORT = _hrc-assert
    _hrc-resource HRES-PROVIDER-STATUS@ -7640 = _hrc-assert
    _hrc-resource HRES-LAST-STATUS@ HRES-S-OK = _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ 0= _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-releases @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-clean-result ;

: _hrc-pb-null-success  ( -- )
    _hrc-pb-setup 0 _hrc-bind-port !
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-BIND-PORT = _hrc-assert
    _hrc-resource HRES-PROVIDER-STATUS@ 0= _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ 0= _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-releases @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-sensitive-zero _hrc-pb-fault-clear ;

: _hrc-pb-error-port  ( -- )
    _hrc-pb-setup -7640 _hrc-bind-status !
    _hrc-run-resource HRES-S-FAULT = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-FAULT = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-BIND-PORT = _hrc-assert
    _hrc-resource HRES-PROVIDER-STATUS@ -7640 = _hrc-assert
    _hrc-resource HRES-CLEANUP@ 0= _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-release-open-state @ NIO-OPEN-STATE-CLOSED = _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ 0= _hrc-assert
    _hrc-lease-errors @ 0= _hrc-assert
    _hrc-pb-no-actions _hrc-pb-sensitive-zero _hrc-pb-fault-clear ;

: _hrc-test-provider-boundary  ( -- )
    _hrc-pb-open-success
    _hrc-pb-open-xio
    _hrc-pb-close-error
    _hrc-pb-cancel-error
    _hrc-pb-cancel-throw
    _hrc-pb-noncoop-detached
    _hrc-pb-noncoop-open
    _hrc-pb-error-no-port
    _hrc-pb-null-success
    _hrc-pb-error-port
    _hrc-stack ;

: _hrc-test-deadline-overrides-result  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    3 _hrc-media-mode !
    _hrc-service XIO-SERVICE-INIT XIO-S-OK = _hrc-assert
    _hrc-operation XIO-OP-INIT
    _hrc-service 77 1 1 0 _hrc-resource
        ['] HRES-XIO-START ['] HRES-XIO-POLL
        ['] HRES-XIO-CANCEL ['] HRES-XIO-WIPE
        _hrc-operation XIO-OP-CONFIGURE XIO-S-OK = _hrc-assert
    _hrc-service _hrc-operation XIO-SUBMIT XIO-S-OK = _hrc-assert
    4000 0 DO
        _hrc-operation XIOO.STATE @ XIO-STATE-ACTIVE <> IF LEAVE THEN
        _hrc-service XIO-TICK
    LOOP
    _hrc-operation XIOO.STATE @ XIO-STATE-TIMED-OUT = _hrc-assert
    _hrc-operation XIOO.ERROR @ XIO-E-DEADLINE = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RELEASED = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-TIMED-OUT = _hrc-assert
    _hrc-resource HRES-DETAIL@ XIO-E-DEADLINE = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 200 = _hrc-assert
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert
    _hrc-media-errors @ 0= _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-cancels @ 0= _hrc-assert _hrc-lease-errors @ 0= _hrc-assert
    _hrc-service _hrc-operation XIO-RESET XIO-S-OK = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-TIMED-OUT = _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-service XIO-SERVICE-FINI XIO-S-OK = _hrc-assert
    _hrc-stack ;

: _hrc-test-xio-ordinary-result  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    1 _hrc-media-mode !
    _hrc-service XIO-SERVICE-INIT XIO-S-OK = _hrc-assert
    _hrc-operation XIO-OP-INIT
    _hrc-service 77 1 1 0 _hrc-resource
        ['] HRES-XIO-START ['] HRES-XIO-POLL
        ['] HRES-XIO-CANCEL ['] HRES-XIO-WIPE
        _hrc-operation XIO-OP-CONFIGURE XIO-S-OK = _hrc-assert
    _hrc-service _hrc-operation XIO-SUBMIT XIO-S-OK = _hrc-assert
    4000 0 DO
        _hrc-operation XIOO.STATE @ XIO-STATE-ACTIVE <> IF LEAVE THEN
        _hrc-service XIO-TICK
    LOOP
    _hrc-operation XIOO.STATE @ XIO-STATE-SUCCEEDED = _hrc-assert
    _hrc-operation XIOO.RESULT @ _hrc-resource = _hrc-assert
    _hrc-service XIOS.RETAINED @ _hrc-operation = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RESULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-MEDIA = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-MEDIA-REJECTED = _hrc-assert
    _hrc-resource HRES-MEDIA-STATUS@ -7610 = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 200 = _hrc-assert
    _hrc-resource HRES.WIRE HRES-REQUEST-MAX _hrc-zero? 0= _hrc-assert
    _hrc-media-calls @ 1 = _hrc-assert _hrc-releases @ 1 = _hrc-assert
    _hrc-service _hrc-operation XIO-RESET XIO-S-OK = _hrc-assert
    _hrc-operation XIOO.STATE @ XIO-STATE-RESET = _hrc-assert
    _hrc-operation XIOO.RESULT @ 0= _hrc-assert
    _hrc-service XIOS.RETAINED @ 0= _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RELEASED = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-MEDIA = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-MEDIA-REJECTED = _hrc-assert
    _hrc-resource HRES-MEDIA-STATUS@ -7610 = _hrc-assert
    _hrc-resource HRES.WIRE HRES-REQUEST-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PARSER HSTR.HEADER-BUF
        HSTR-HEADER-CAPACITY _hrc-zero? _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-service XIO-SERVICE-FINI XIO-S-OK = _hrc-assert
    _hrc-stack ;

: _hrc-test-timeout-provenance  ( -- )
    _hrc-fixture-reset
    0 S" /next" _hrc-build-redirect
    1 _hrc-build-ok
    S" https://feeds.example.test/feed" 3 128 _hrc-setup
    _hrc-service XIO-SERVICE-INIT XIO-S-OK = _hrc-assert
    _hrc-operation XIO-OP-INIT
    _hrc-service 77 1 1 0 _hrc-resource
        ['] HRES-XIO-START ['] HRES-XIO-POLL
        ['] HRES-XIO-CANCEL ['] HRES-XIO-WIPE
        _hrc-operation XIO-OP-CONFIGURE XIO-S-OK = _hrc-assert
    _hrc-service _hrc-operation XIO-SUBMIT XIO-S-OK = _hrc-assert
    4000 0 DO
        _hrc-binds @ 2 = IF LEAVE THEN
        _hrc-service XIO-TICK
    LOOP
    _hrc-binds @ 2 = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://feeds.example.test/next" STR-STR= _hrc-assert
    0 302 _hrc-hop-status?
    MS@ _hrc-operation XIOO.DEADLINE-MS !
    _hrc-service XIO-TICK
    _hrc-operation XIOO.STATE @ XIO-STATE-TIMED-OUT = _hrc-assert
    _hrc-operation XIOO.ERROR @ XIO-E-DEADLINE = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-RELEASED = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-TIMED-OUT = _hrc-assert
    _hrc-resource HRES-DETAIL@ XIO-E-DEADLINE = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://feeds.example.test/next" STR-STR= _hrc-assert
    0 302 _hrc-hop-status?
    1 _hrc-resource HRES-HOP@ _hrc-assert
        0= _hrc-assert HTARGET-VALID? _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES.WIRE HRES-REQUEST-MAX _hrc-zero? _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 2 = _hrc-assert
    _hrc-service _hrc-operation XIO-RESET XIO-S-OK = _hrc-assert
    _hrc-resource HRES-REDIRECT-COUNT@ 1 = _hrc-assert
    _hrc-resource HRES-EFFECTIVE-URI$
        S" https://feeds.example.test/next" STR-STR= _hrc-assert
    _hrc-resource HRES-DECONFIGURE HRES-S-OK = _hrc-assert
    _hrc-service XIO-SERVICE-FINI XIO-S-OK = _hrc-assert
    _hrc-stack ;

: _hrc-test-cancel-throw-poison  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    _hrc-resource HRES-START HRES-S-PENDING = _hrc-assert
    -1 _hrc-cancel-throw !
    _hrc-resource HRES-CANCEL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-CANCELLED = _hrc-assert
    _hrc-resource HRES-DETAIL@ HBUF-S-TRANSPORT = _hrc-assert
    _hrc-resource HRES-CLEANUP@ HRES-XERR-CLEANUP = _hrc-assert
    _hrc-resource HRES-LOWER-ERROR@ -7630 = _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PORT @ _hrc-port = _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ _hrc-port = _hrc-assert
    _hrc-binds @ 1 = _hrc-assert _hrc-cancels @ 1 = _hrc-assert
    _hrc-releases @ 0= _hrc-assert _hrc-lease-errors @ 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES.WIRE HRES-REQUEST-MAX _hrc-zero? _hrc-assert
    -1 _hrc-forbid-io !
    _hrc-resource HRES-POLL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-CANCEL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-WIPE HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-START HRES-S-CLEANUP = _hrc-assert
    _hrc-cancels @ 1 = _hrc-assert _hrc-releases @ 0= _hrc-assert
    _hrc-late-io @ 0= _hrc-assert
    _hrc-quarantine-dispose
    _hrc-stack ;

: _hrc-test-cleanup-failure  ( -- )
    _hrc-fixture-reset 0 _hrc-build-ok
    S" https://feeds.example.test/feed" 2 128 _hrc-setup
    1 _hrc-release-mode !
    _hrc-run-resource HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-STATE@ HRES-STATE-FAULT = _hrc-assert
    _hrc-resource HRES-OUTCOME@ HRES-O-CLEANUP = _hrc-assert
    _hrc-resource HRES-DETAIL@ HRES-D-DETACH = _hrc-assert
    _hrc-resource HRES-CLEANUP@ -7601 = _hrc-assert
    _hrc-resource HRES-HTTP-STATUS@ 200 = _hrc-assert
    0 200 _hrc-hop-status?
    _hrc-resource HRES-RESULT-VALID? 0= _hrc-assert
    _hrc-resource HRES.BODY-U @ 0= _hrc-assert
    _hrc-body 128 _hrc-zero? _hrc-assert
    _hrc-resource HRES.WIRE HRES-REQUEST-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PARSER HSTR.HEADER-BUF
        HSTR-HEADER-CAPACITY _hrc-zero? _hrc-assert
    _hrc-resource HRES.LOCATION HRES-LOCATION-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.LOCATION-U @ 0= _hrc-assert
    _hrc-resource HRES.LOCATION-PRESENT @ 0= _hrc-assert
    _hrc-resource HRES.ETAG HRES-ETAG-MAX _hrc-zero? _hrc-assert
    _hrc-resource HRES.ETAG-U @ 0= _hrc-assert
    _hrc-resource HRES.ETAG-PRESENT @ 0= _hrc-assert
    _hrc-resource HRES.LAST-MODIFIED HRES-LAST-MODIFIED-MAX
        _hrc-zero? _hrc-assert
    _hrc-resource HRES.LAST-MODIFIED-U @ 0= _hrc-assert
    _hrc-resource HRES.LAST-MODIFIED-PRESENT @ 0= _hrc-assert
    _hrc-resource HRES.MEDIA DUP MTYPE-VALID? 0= _hrc-assert
    DUP MTYPE-TYPE$ NIP 0= _hrc-assert
    DUP MTYPE-SUBTYPE$ NIP 0= _hrc-assert
    MTYPE-PARAM-COUNT@ 0= _hrc-assert
    _hrc-resource HRES.EXCHANGE HBUF.PORT @ 0= _hrc-assert
    _hrc-resource HRES.ACTIVE-PORT @ _hrc-port = _hrc-assert
    _hrc-releases @ 1 = _hrc-assert _hrc-close-starts @ 1 = _hrc-assert
    _hrc-cancels @ 0= _hrc-assert
    -1 _hrc-forbid-io !
    _hrc-resource HRES-POLL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-CANCEL HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-WIPE HRES-S-CLEANUP = _hrc-assert
    _hrc-resource HRES-START HRES-S-CLEANUP = _hrc-assert
    _hrc-releases @ 1 = _hrc-assert _hrc-late-io @ 0= _hrc-assert
    _hrc-stack ;

: _hrc-run  ( -- )
    0 _hrc-fails ! 0 _hrc-checks ! DEPTH _hrc-depth !
    S" idle-cleanup" _hrc-mark
    _hrc-test-idle-cleanup
    S" success" _hrc-mark
    _hrc-test-success
    S" redirect-success" _hrc-mark
    _hrc-test-redirect-success
    S" redirect-rejections" _hrc-mark
    _hrc-test-redirect-rejections
    S" exact-redirect-budget" _hrc-mark
    _hrc-test-exact-redirect-budget
    S" admission" _hrc-mark
    _hrc-test-admission
    S" overflow" _hrc-mark
    _hrc-test-overflow
    S" close-failure-fallback" _hrc-mark
    _hrc-test-close-failure-fallback
    S" cancel" _hrc-mark
    _hrc-test-cancel
    S" clean-reuse" _hrc-mark
    _hrc-test-clean-reuse
    S" media-policy" _hrc-mark
    _hrc-test-media-policy
    S" media-params" _hrc-mark
    _hrc-test-media-params
    S" provider-boundary" _hrc-mark
    _hrc-test-provider-boundary
    S" deadline-overrides-result" _hrc-mark
    _hrc-test-deadline-overrides-result
    S" xio-ordinary-result" _hrc-mark
    _hrc-test-xio-ordinary-result
    S" timeout-provenance" _hrc-mark
    _hrc-test-timeout-provenance
    S" cancel-throw-poison" _hrc-mark
    _hrc-test-cancel-throw-poison
    S" cleanup-failure" _hrc-mark
    _hrc-test-cleanup-failure
    S" done" _hrc-mark
    _hrc-stack
    _hrc-fails @ 0= IF
        ." HTTP RESOURCE CONTRACTS PASS " _hrc-checks @ .
    ELSE
        ." HTTP RESOURCE CONTRACTS FAIL " _hrc-fails @ . ." / "
            _hrc-checks @ .
    THEN CR ;
