\ atpost-egress-test.f - focused AT text-post Streams composition contracts

PROVIDED akashic-atpost-egress-test

VARIABLE _atpet-fails
VARIABLE _atpet-checks
VARIABLE _atpet-depth

: _atpet-assert  ( flag -- )
    1 _atpet-checks +!
    0= IF
        1 _atpet-fails +!
        ." AT TEXT POST EGRESS ASSERT " _atpet-checks @ . CR
    THEN ;

: _atpet-stack  ( -- )
    DEPTH DUP _atpet-depth @ <> IF
        ." AT TEXT POST EGRESS STACK "
        _atpet-depth @ . ." -> " DUP . CR .S CR
    THEN
    _atpet-depth @ = _atpet-assert ;

: _atpet-status  ( actual expected -- )
    = _atpet-assert ;

: _atpet-ok  ( status -- )
    AT-TEXT-POST-CONNECTOR-S-OK _atpet-status ;

CREATE _atpet-id-a RID-SIZE ALLOT
CREATE _atpet-id-b RID-SIZE ALLOT
CREATE _atpet-endpoint-a RID-SIZE ALLOT
CREATE _atpet-endpoint-b RID-SIZE ALLOT

CREATE _atpet-target-a-raw HTARGET-SIZE 7 + ALLOT
CREATE _atpet-target-b-raw HTARGET-SIZE 7 + ALLOT
CREATE _atpet-target-bad-raw HTARGET-SIZE 7 + ALLOT
CREATE _atpet-create-a-raw ATPCS-OWNER-SIZE 7 + ALLOT
CREATE _atpet-create-b-raw ATPCS-OWNER-SIZE 7 + ALLOT
CREATE _atpet-clock-a-raw TID-CLOCK-SIZE 7 + ALLOT
CREATE _atpet-clock-b-raw TID-CLOCK-SIZE 7 + ALLOT
CREATE _atpet-owner-a-raw AT-TEXT-POST-CONNECTOR-SIZE 7 + ALLOT
CREATE _atpet-owner-b-raw AT-TEXT-POST-CONNECTOR-SIZE 7 + ALLOT
CREATE _atpet-probe-raw AT-TEXT-POST-CONNECTOR-SIZE 7 + ALLOT
CREATE _atpet-alias-raw
    AT-TEXT-POST-CONNECTOR-SIZE ATPCS-OWNER-SIZE + 7 + ALLOT

CREATE _atpet-event-a-raw STREAMS-EVENT-SIZE 7 + ALLOT
CREATE _atpet-event-b-raw STREAMS-EVENT-SIZE 7 + ALLOT
CREATE _atpet-event-probe-raw STREAMS-EVENT-SIZE 7 + ALLOT
CREATE _atpet-op-a-raw XIO-OP-SIZE 7 + ALLOT
CREATE _atpet-op-b-raw XIO-OP-SIZE 7 + ALLOT
CREATE _atpet-result-a-raw STREAMS-CONNECTOR-RESULT-SIZE 7 + ALLOT
CREATE _atpet-result-b-raw STREAMS-CONNECTOR-RESULT-SIZE 7 + ALLOT

: _atpet-target-a  ( -- target )
    _atpet-target-a-raw 7 + -8 AND ;

: _atpet-target-b  ( -- target )
    _atpet-target-b-raw 7 + -8 AND ;

: _atpet-target-bad  ( -- target )
    _atpet-target-bad-raw 7 + -8 AND ;

: _atpet-create-a  ( -- owner )
    _atpet-create-a-raw 7 + -8 AND ;

: _atpet-create-b  ( -- owner )
    _atpet-create-b-raw 7 + -8 AND ;

: _atpet-clock-a  ( -- clock )
    _atpet-clock-a-raw 7 + -8 AND ;

: _atpet-clock-b  ( -- clock )
    _atpet-clock-b-raw 7 + -8 AND ;

: _atpet-owner-a  ( -- owner )
    _atpet-owner-a-raw 7 + -8 AND ;

: _atpet-owner-b  ( -- owner )
    _atpet-owner-b-raw 7 + -8 AND ;

: _atpet-probe  ( -- owner )
    _atpet-probe-raw 7 + -8 AND ;

: _atpet-alias  ( -- address )
    _atpet-alias-raw 7 + -8 AND ;

: _atpet-event-a  ( -- event )
    _atpet-event-a-raw 7 + -8 AND ;

: _atpet-event-b  ( -- event )
    _atpet-event-b-raw 7 + -8 AND ;

: _atpet-event-probe  ( -- event )
    _atpet-event-probe-raw 7 + -8 AND ;

: _atpet-op-a  ( -- operation )
    _atpet-op-a-raw 7 + -8 AND ;

: _atpet-op-b  ( -- operation )
    _atpet-op-b-raw 7 + -8 AND ;

: _atpet-result-a  ( -- result )
    _atpet-result-a-raw 7 + -8 AND ;

: _atpet-result-b  ( -- result )
    _atpet-result-b-raw 7 + -8 AND ;

 0 CONSTANT _ATPET-CLOCK-EPOCH
 8 CONSTANT _ATPET-CLOCK-STATUS
16 CONSTANT _ATPET-CLOCK-CALLS
24 CONSTANT _ATPET-CLOCK-SIZE

CREATE _atpet-clock-context-a _ATPET-CLOCK-SIZE ALLOT
CREATE _atpet-clock-context-b _ATPET-CLOCK-SIZE ALLOT

: _atpet-clock  ( context -- epoch-ms status )
    DUP _ATPET-CLOCK-CALLS + 1 SWAP +!
    DUP _ATPET-CLOCK-EPOCH + @
    SWAP _ATPET-CLOCK-STATUS + @ ;

: _atpet-clock-set  ( epoch-ms status context -- )
    >R
    R@ _ATPET-CLOCK-SIZE 0 FILL
    R@ _ATPET-CLOCK-STATUS + !
    R> _ATPET-CLOCK-EPOCH + ! ;

VARIABLE _atpet-scan-a
VARIABLE _atpet-scan-u
VARIABLE _atpet-scan-byte

: _atpet-all-byte?  ( address length byte -- flag )
    _atpet-scan-byte ! _atpet-scan-u ! _atpet-scan-a !
    BEGIN
        _atpet-scan-u @ 0>
    WHILE
        _atpet-scan-a @ C@ _atpet-scan-byte @ <> IF 0 EXIT THEN
        1 _atpet-scan-a +!
        -1 _atpet-scan-u +!
    REPEAT
    -1 ;

VARIABLE _atpet-build-event
VARIABLE _atpet-build-connector
VARIABLE _atpet-build-tag
VARIABLE _atpet-build-a
VARIABLE _atpet-build-u

: _atpet-event-header  ( tag connector event -- )
    _atpet-build-event ! _atpet-build-connector ! _atpet-build-tag !
    _atpet-build-event @ STREAMS-EVENT-INIT
        STREAMS-FLOW-S-OK _atpet-status
    _atpet-build-event @ SEVT.EVENT-ID RID-SIZE
        _atpet-build-tag @ FILL
    _atpet-build-connector @ SCON.ID
        _atpet-build-event @ SEVT.CONNECTOR-ID RID-COPY
    _atpet-build-event @ SEVT.FLOW-ID RID-SIZE
        _atpet-build-tag @ 1+ FILL
    _atpet-build-event @ SEVT.CORRELATION-ID RID-SIZE
        _atpet-build-tag @ 2 + FILL
    _atpet-build-event @ SEVT.IDEMPOTENCY-ID RID-SIZE
        _atpet-build-tag @ 3 + FILL
    _atpet-build-event @ SEVT.ORIGIN-ID RID-SIZE
        _atpet-build-tag @ 4 + FILL
    _atpet-build-connector @ SCON.ENDPOINT-ID
        _atpet-build-event @ SEVT.DESTINATION-ID RID-COPY
    _atpet-build-connector @ SCON.REVISION @
        _atpet-build-event @ SEVT.CONNECTOR-REVISION !
    STREAMS-EVENT-DIRECTION-EGRESS
        _atpet-build-event @ SEVT.DIRECTION !
    _atpet-build-connector @ SCON.PROTOCOL @
        _atpet-build-event @ SEVT.PROTOCOL !
    0x74657874 _atpet-build-event @ SEVT.MEDIA !
    _atpet-build-tag @ _atpet-build-event @ SEVT.SEQUENCE !
    _atpet-build-tag @ _atpet-build-event @ SEVT.RECEIVED-MS ! ;

: _atpet-build-event-with
  ( payload-a payload-u tag connector event -- )
    _atpet-build-event ! _atpet-build-connector !
    _atpet-build-tag ! _atpet-build-u ! _atpet-build-a !
    _atpet-build-tag @ _atpet-build-connector @ _atpet-build-event @
        _atpet-event-header
    _atpet-build-a @ _atpet-build-u @ _atpet-build-event @
        STREAMS-EVENT-BORROW STREAMS-FLOW-S-OK _atpet-status
    _atpet-build-event @ STREAMS-EVENT-SEAL
        STREAMS-FLOW-S-OK _atpet-status
    _atpet-build-event @ STREAMS-EVENT-VALID? _atpet-assert ;

VARIABLE _atpet-call-event
VARIABLE _atpet-call-op
VARIABLE _atpet-call-owner
VARIABLE _atpet-call-result
VARIABLE _atpet-call-connector

: _atpet-call-save  ( event operation owner result -- )
    _atpet-call-result ! _atpet-call-owner !
    _atpet-call-op ! _atpet-call-event !
    _atpet-call-owner @ AT-TEXT-POST-CONNECTOR-CONNECTOR@
    DUP _atpet-ok DROP _atpet-call-connector ! ;

: _atpet-start  ( event operation owner result -- )
    _atpet-call-save
    _atpet-call-result @ STREAMS-CONNECTOR-RESULT-INIT
    _atpet-call-event @ _atpet-call-op @
    _atpet-call-connector @ SCON.CONTEXT @ _atpet-call-result @
    _atpet-call-connector @ SCON.START-XT @ EXECUTE ;

: _atpet-start-raw  ( event operation owner result -- )
    _atpet-call-save
    _atpet-call-event @ _atpet-call-op @
    _atpet-call-connector @ SCON.CONTEXT @ _atpet-call-result @
    _atpet-call-connector @ SCON.START-XT @ EXECUTE ;

: _atpet-poll  ( event operation owner result -- )
    _atpet-call-save
    _atpet-call-result @ STREAMS-CONNECTOR-RESULT-INIT
    _atpet-call-event @ _atpet-call-op @
    _atpet-call-connector @ SCON.CONTEXT @ _atpet-call-result @
    _atpet-call-connector @ SCON.POLL-XT @ EXECUTE ;

: _atpet-cancel  ( event operation owner result -- )
    _atpet-call-save
    _atpet-call-result @ STREAMS-CONNECTOR-RESULT-INIT
    _atpet-call-event @ _atpet-call-op @
    _atpet-call-connector @ SCON.CONTEXT @ _atpet-call-result @
    _atpet-call-connector @ SCON.CANCEL-XT @ EXECUTE ;

: _atpet-cleanup  ( event operation owner -- error )
    0 _atpet-call-result !
    _atpet-call-owner ! _atpet-call-op ! _atpet-call-event !
    _atpet-call-owner @ AT-TEXT-POST-CONNECTOR-CONNECTOR@
    DUP _atpet-ok DROP _atpet-call-connector !
    _atpet-call-event @ _atpet-call-op @
    _atpet-call-connector @ SCON.CONTEXT @
    _atpet-call-connector @ SCON.CLEANUP-XT @ EXECUTE ;

VARIABLE _atpet-exp-completion
VARIABLE _atpet-exp-effect
VARIABLE _atpet-exp-result

: _atpet-expect-result  ( completion effect result -- )
    _atpet-exp-result ! _atpet-exp-effect ! _atpet-exp-completion !
    _atpet-exp-result @ STREAMS-CONNECTOR-RESULT-VALID? _atpet-assert
    _atpet-exp-result @ SCRR.COMPLETION @
        _atpet-exp-completion @ = _atpet-assert
    _atpet-exp-result @ SCRR.EFFECT @
        _atpet-exp-effect @ = _atpet-assert ;

: _atpet-result-pending  ( result -- )
    >R STREAMS-CONNECTOR-COMPLETION-PENDING
    STREAMS-EFFECT-UNCERTAIN R> _atpet-expect-result ;

: _atpet-result-created  ( result -- )
    >R STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED R> _atpet-expect-result ;

: _atpet-result-no-effect  ( result -- )
    >R STREAMS-CONNECTOR-COMPLETION-FAILED
    STREAMS-EFFECT-NOT-APPLIED R> _atpet-expect-result ;

: _atpet-result-uncertain  ( result -- )
    >R STREAMS-CONNECTOR-COMPLETION-INDETERMINATE
    STREAMS-EFFECT-UNCERTAIN R> _atpet-expect-result ;

: _atpet-result-cancelled  ( result -- )
    >R STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED R> _atpet-expect-result ;

: _atpet-connector-a  ( -- connector )
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-CONNECTOR@
    DUP _atpet-ok DROP ;

: _atpet-connector-b  ( -- connector )
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-CONNECTOR@
    DUP _atpet-ok DROP ;

: _atpet-uri-a$  ( -- address length )
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/a-one" ;

: _atpet-uri-b$  ( -- address length )
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/b-two" ;

: _atpet-cid-a$  ( -- address length )
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;

: _atpet-cid-b$  ( -- address length )
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab" ;

CREATE _atpet-expected-record 256 ALLOT
VARIABLE _atpet-expected-u

: _atpet-expected-c!  ( character -- )
    _atpet-expected-record _atpet-expected-u @ + C!
    1 _atpet-expected-u +! ;

: _atpet-expected+  ( address length -- )
    DUP >R
    _atpet-expected-record _atpet-expected-u @ + SWAP MOVE
    R> _atpet-expected-u +! ;

: _atpet-expected-prefix  ( -- )
    0 _atpet-expected-u !
    [CHAR] { _atpet-expected-c!
    [CHAR] " _atpet-expected-c! S" $type" _atpet-expected+
    [CHAR] " _atpet-expected-c! [CHAR] : _atpet-expected-c!
    [CHAR] " _atpet-expected-c!
    S" app.bsky.feed.post" _atpet-expected+
    [CHAR] " _atpet-expected-c! [CHAR] , _atpet-expected-c!
    [CHAR] " _atpet-expected-c! S" text" _atpet-expected+
    [CHAR] " _atpet-expected-c! [CHAR] : _atpet-expected-c!
    [CHAR] " _atpet-expected-c! ;

: _atpet-expected-suffix  ( timestamp-a timestamp-u -- )
    [CHAR] " _atpet-expected-c! [CHAR] , _atpet-expected-c!
    [CHAR] " _atpet-expected-c! S" createdAt" _atpet-expected+
    [CHAR] " _atpet-expected-c! [CHAR] : _atpet-expected-c!
    [CHAR] " _atpet-expected-c! _atpet-expected+
    [CHAR] " _atpet-expected-c! [CHAR] } _atpet-expected-c! ;

: _atpet-expected  ( text-a text-u timestamp-a timestamp-u -- )
    2>R _atpet-expected-prefix _atpet-expected+ 2R>
    _atpet-expected-suffix ;

: _atpet-record-exact?  ( address length -- flag )
    _atpet-expected-record _atpet-expected-u @ COMPARE 0= ;

: _atpet-check-uri-a  ( -- )
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-URI@
    DUP _atpet-ok DROP _atpet-uri-a$ COMPARE 0= _atpet-assert ;

: _atpet-check-uri-b  ( -- )
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-URI@
    DUP _atpet-ok DROP _atpet-uri-b$ COMPARE 0= _atpet-assert ;

: _atpet-check-cid-a  ( -- )
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-CID@
    DUP _atpet-ok DROP _atpet-cid-a$ COMPARE 0= _atpet-assert ;

: _atpet-check-cid-b  ( -- )
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-CID@
    DUP _atpet-ok DROP _atpet-cid-b$ COMPARE 0= _atpet-assert ;

: _atpet-check-capture-a  ( -- )
    _atpet-create-a ATPCS.IAT @ 1718465400 = _atpet-assert
    _atpet-create-a ATPCS.COLLECTION
    _atpet-create-a ATPCS.COLLECTION-U @
    S" app.bsky.feed.post" COMPARE 0= _atpet-assert
    _atpet-create-a ATPCS.RKEY _atpet-create-a ATPCS.RKEY-U @
    S" 3kuxxnvrfns2b" COMPARE 0= _atpet-assert
    S" alpha" S" 2024-06-15T15:30:00Z" _atpet-expected
    _atpet-create-a ATPCS.RECORD _atpet-create-a ATPCS.RECORD-U @
    _atpet-record-exact? _atpet-assert ;

: _atpet-check-capture-b  ( -- )
    _atpet-create-b ATPCS.IAT @ 1718465460 = _atpet-assert
    _atpet-create-b ATPCS.COLLECTION
    _atpet-create-b ATPCS.COLLECTION-U @
    S" app.bsky.feed.post" COMPARE 0= _atpet-assert
    _atpet-create-b ATPCS.RKEY _atpet-create-b ATPCS.RKEY-U @
    S" 3kuxxppt6us2f" COMPARE 0= _atpet-assert
    S" beta" S" 2024-06-15T15:31:00Z" _atpet-expected
    _atpet-create-b ATPCS.RECORD _atpet-create-b ATPCS.RECORD-U @
    _atpet-record-exact? _atpet-assert ;

: _atpet-init-identities  ( -- )
    _atpet-id-a RID-SIZE 0x11 FILL
    _atpet-id-b RID-SIZE 0x12 FILL
    _atpet-endpoint-a RID-SIZE 0x21 FILL
    _atpet-endpoint-b RID-SIZE 0x22 FILL ;

: _atpet-init-dependencies  ( -- )
    1 _atpet-target-a _atpet-create-a ATPCS-INIT
        AT-CREATE-RECORD-S-OK _atpet-status
    2 _atpet-target-b _atpet-create-b ATPCS-INIT
        AT-CREATE-RECORD-S-OK _atpet-status
    7 _atpet-clock-a TID-CLOCK-INIT TID-S-OK _atpet-status
    11 _atpet-clock-b TID-CLOCK-INIT TID-S-OK _atpet-status
    1718465400123 0 _atpet-clock-context-a _atpet-clock-set
    1718465460999 0 _atpet-clock-context-b _atpet-clock-set ;

: _atpet-init-connectors  ( -- )
    _atpet-id-a _atpet-endpoint-a 1
    _atpet-clock-context-a ['] _atpet-clock _atpet-clock-a
    _atpet-target-a _atpet-create-a _atpet-owner-a
    AT-TEXT-POST-CONNECTOR-INIT _atpet-ok
    _atpet-id-b _atpet-endpoint-b 2
    _atpet-clock-context-b ['] _atpet-clock _atpet-clock-b
    _atpet-target-b _atpet-create-b _atpet-owner-b
    AT-TEXT-POST-CONNECTOR-INIT _atpet-ok
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-VALID? _atpet-assert
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-VALID? _atpet-assert
    _atpet-owner-a ATTPC.TARGET _atpet-target-a <> _atpet-assert
    _atpet-owner-b ATTPC.TARGET _atpet-target-b <> _atpet-assert
    _atpet-owner-a ATTPC.TARGET HTARGET-SIZE
        _atpet-target-a HTARGET-SIZE COMPARE 0= _atpet-assert
    _atpet-owner-b ATTPC.TARGET HTARGET-SIZE
        _atpet-target-b HTARGET-SIZE COMPARE 0= _atpet-assert
    _atpet-target-a HTARGET-SIZE 0 FILL
    _atpet-target-b HTARGET-SIZE 0 FILL
    _atpet-target-a AT-CREATE-RECORD-TARGET? 0= _atpet-assert
    _atpet-target-b AT-CREATE-RECORD-TARGET? 0= _atpet-assert
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-VALID? _atpet-assert
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-VALID? _atpet-assert
    _atpet-connector-a SCON.DIRECTION @
        STREAMS-CONNECTOR-DIRECTION-OUTPUT = _atpet-assert
    _atpet-connector-b SCON.DIRECTION @
        STREAMS-CONNECTOR-DIRECTION-OUTPUT = _atpet-assert
    _atpet-connector-a SCON.OP-SIZE @ XIO-OP-SIZE = _atpet-assert
    _atpet-connector-b SCON.OP-SIZE @ XIO-OP-SIZE = _atpet-assert
    _atpet-connector-a SCON.CONTEXT @ _atpet-owner-a = _atpet-assert
    _atpet-connector-b SCON.CONTEXT @ _atpet-owner-b = _atpet-assert ;

: _ATPET-SETUP  ( -- )
    _atpet-init-identities
    _atpet-init-dependencies
    _atpet-init-connectors
    S" alpha" 17 _atpet-connector-a _atpet-event-a
        _atpet-build-event-with
    S" beta" 29 _atpet-connector-b _atpet-event-b
        _atpet-build-event-with
    _atpet-stack ;

: _atpet-invalid-clock-preflight  ( -- )
    _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE 0xA5 FILL
    _atpet-id-a _atpet-endpoint-a 1
    _atpet-clock-context-a 0 _atpet-clock-a
    _atpet-target-a _atpet-create-a _atpet-probe
    AT-TEXT-POST-CONNECTOR-INIT
        AT-TEXT-POST-CONNECTOR-S-INVALID _atpet-status
    _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE 0xA5
        _atpet-all-byte? _atpet-assert ;

: _atpet-invalid-target-preflight  ( -- )
    _atpet-target-bad HTARGET-SIZE 0 FILL
    _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE 0xA5 FILL
    _atpet-id-a _atpet-endpoint-a 1
    _atpet-clock-context-a ['] _atpet-clock _atpet-clock-a
    _atpet-target-bad _atpet-create-a _atpet-probe
    AT-TEXT-POST-CONNECTOR-INIT
        AT-TEXT-POST-CONNECTOR-S-TARGET _atpet-status
    _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE 0xA5
        _atpet-all-byte? _atpet-assert ;

: _atpet-alias-preflight  ( -- )
    _atpet-alias
    AT-TEXT-POST-CONNECTOR-SIZE ATPCS-OWNER-SIZE + 0 FILL
    1 _atpet-target-bad _atpet-alias ATPCS-INIT
        AT-CREATE-RECORD-S-OK _atpet-status
    _atpet-id-a _atpet-endpoint-a 1
    _atpet-clock-context-a ['] _atpet-clock _atpet-clock-a
    _atpet-target-bad _atpet-alias _atpet-alias
    AT-TEXT-POST-CONNECTOR-INIT
        AT-TEXT-POST-CONNECTOR-S-ALIAS _atpet-status ;

: _atpet-result-alias-preflight  ( -- )
    _atpet-owner-a _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE MOVE
    _atpet-event-a _atpet-op-a _atpet-owner-a
        _atpet-owner-a ATTPC.ARG-EVENT _atpet-start-raw
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-SIZE
        _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE
        COMPARE 0= _atpet-assert ;

: _atpet-operation-alias-preflight  ( -- )
    _atpet-owner-a _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE MOVE
    _atpet-event-a _atpet-owner-a ATTPC.ARG-EVENT
        _atpet-owner-a _atpet-result-a _atpet-start
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-SIZE
        _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE
        COMPARE 0= _atpet-assert ;

: _atpet-result-payload-alias-preflight  ( -- )
    _atpet-result-a STREAMS-CONNECTOR-RESULT-SIZE 0x5A FILL
    S" trap" _atpet-result-a SWAP MOVE
    _atpet-result-a 4 43 _atpet-connector-a
        _atpet-event-probe _atpet-build-event-with
    _atpet-result-a _atpet-result-b
        STREAMS-CONNECTOR-RESULT-SIZE MOVE
    _atpet-event-probe _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start-raw
    _atpet-result-a STREAMS-CONNECTOR-RESULT-SIZE
        _atpet-result-b STREAMS-CONNECTOR-RESULT-SIZE
        COMPARE 0= _atpet-assert ;

: _atpet-payload-alias-preflight  ( -- )
    S" trap" _atpet-owner-a ATTPC.TEXT SWAP MOVE
    _atpet-owner-a ATTPC.TEXT 4 41 _atpet-connector-a
        _atpet-event-probe _atpet-build-event-with
    _atpet-owner-a _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE MOVE
    _atpet-event-probe _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-SIZE
        _atpet-probe AT-TEXT-POST-CONNECTOR-SIZE
        COMPARE 0= _atpet-assert ;

: _ATPET-PREFLIGHT  ( -- )
    _atpet-invalid-clock-preflight
    _atpet-invalid-target-preflight
    _atpet-alias-preflight
    _atpet-result-alias-preflight
    _atpet-operation-alias-preflight
    _atpet-result-payload-alias-preflight
    _atpet-payload-alias-preflight
    _atpet-stack ;

: _atpet-check-created-inspection  ( -- )
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    DUP _atpet-ok DROP
    AT-CREATE-RECORD-OUTCOME-CREATED = _atpet-assert
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    DUP _atpet-ok DROP
    AT-CREATE-RECORD-OUTCOME-CREATED = _atpet-assert
    _atpet-check-uri-a _atpet-check-cid-a
    _atpet-check-uri-b _atpet-check-cid-b ;

: _ATPET-CREATED  ( -- )
    _atpet-op-a XIO-OP-SIZE 0xA5 FILL
    _atpet-op-b XIO-OP-SIZE 0x5A FILL
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start
    _atpet-result-a _atpet-result-pending
    \ A second flow cannot claim A, and its cleanup cannot wipe A's work.
    _atpet-event-a _atpet-op-b _atpet-owner-a _atpet-result-b
        _atpet-start
    _atpet-result-b _atpet-result-no-effect
    _atpet-result-b SCRR.DETAIL @
        AT-TEXT-POST-CONNECTOR-S-BUSY = _atpet-assert
    _atpet-event-a _atpet-op-b _atpet-owner-a _atpet-cleanup
        0= _atpet-assert
    _atpet-create-a ATPCS.WIPES @ 0= _atpet-assert
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-result-b
        _atpet-start
    _atpet-result-b _atpet-result-pending
    _atpet-op-a XIO-OP-VALID? _atpet-assert
    _atpet-op-b XIO-OP-VALID? _atpet-assert
    _atpet-clock-context-a _ATPET-CLOCK-CALLS + @ 1 = _atpet-assert
    _atpet-clock-context-b _ATPET-CLOCK-CALLS + @ 1 = _atpet-assert
    _atpet-check-capture-a _atpet-check-capture-b
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@
    DUP _atpet-ok DROP 1718465400123 = _atpet-assert
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-LAST-EPOCH-MS@
    DUP _atpet-ok DROP 1718465460999 = _atpet-assert

    \ B's operation belongs to B; presenting it to A's cleanup is a no-op.
    _atpet-event-a _atpet-op-b _atpet-owner-a _atpet-cleanup
        0= _atpet-assert
    _atpet-create-a ATPCS.WIPES @ 0= _atpet-assert

    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-result-b
        _atpet-poll
    _atpet-result-b _atpet-result-created
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-poll
    _atpet-result-a _atpet-result-created
    _atpet-check-created-inspection
    _atpet-clock-context-a _ATPET-CLOCK-CALLS + @ 1 = _atpet-assert
    _atpet-clock-context-b _ATPET-CLOCK-CALLS + @ 1 = _atpet-assert

    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-cleanup
        0= _atpet-assert
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-cleanup
        0= _atpet-assert
    _atpet-create-a ATPCS.WIPES @ 1 = _atpet-assert
    _atpet-create-b ATPCS.WIPES @ 1 = _atpet-assert
    \ createRecord receipts deliberately survive request cleanup.
    _atpet-check-created-inspection
    _atpet-stack ;

: _atpet-rebuild-events  ( -- )
    _atpet-event-a STREAMS-EVENT-CLOSE DROP
    _atpet-event-b STREAMS-EVENT-CLOSE DROP
    S" alpha" 117 _atpet-connector-a _atpet-event-a
        _atpet-build-event-with
    S" beta" 129 _atpet-connector-b _atpet-event-b
        _atpet-build-event-with ;

: _atpet-test-no-effect  ( -- )
    ATPCS-MODE-NO-EFFECT _atpet-create-a ATPCS-MODE!
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start
    _atpet-result-a _atpet-result-no-effect
    _atpet-create-a ATPCS.RKEY _atpet-create-a ATPCS.RKEY-U @
    S" 3kuxxnvrfnt2b" COMPARE 0= _atpet-assert
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    DUP _atpet-ok DROP
    AT-CREATE-RECORD-OUTCOME-NO-EFFECT = _atpet-assert
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-cleanup
        0= _atpet-assert ;

: _atpet-test-clock-failure  ( -- )
    1718465400123 -77 _atpet-clock-context-a _atpet-clock-set
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start
    _atpet-result-a _atpet-result-no-effect
    _atpet-result-a SCRR.DETAIL @
        AT-TEXT-POST-CONNECTOR-S-CLOCK = _atpet-assert
    _atpet-op-a XIO-OP-VALID? _atpet-assert
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-cleanup
        0= _atpet-assert
    1718465400123 0 _atpet-clock-context-a _atpet-clock-set ;

: _atpet-test-uncertain  ( -- )
    ATPCS-MODE-UNCERTAIN _atpet-create-b ATPCS-MODE!
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-result-b
        _atpet-start
    _atpet-result-b _atpet-result-pending
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-result-b
        _atpet-poll
    _atpet-result-b _atpet-result-uncertain
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    DUP _atpet-ok DROP
    AT-CREATE-RECORD-OUTCOME-UNCERTAIN = _atpet-assert
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-cleanup
        0= _atpet-assert ;

: _ATPET-OUTCOMES  ( -- )
    _atpet-rebuild-events
    _atpet-test-clock-failure
    _atpet-test-no-effect
    _atpet-test-uncertain
    _atpet-stack ;

: _atpet-test-cancel-no-effect  ( -- )
    ATPCS-MODE-CANCEL-NO-EFFECT _atpet-create-a ATPCS-MODE!
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start
    _atpet-result-a _atpet-result-pending
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-cancel
    _atpet-result-a _atpet-result-cancelled
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    DUP _atpet-ok DROP
    AT-CREATE-RECORD-OUTCOME-NO-EFFECT = _atpet-assert
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-cleanup
        0= _atpet-assert ;

: _atpet-test-cancel-uncertain  ( -- )
    ATPCS-MODE-CANCEL-UNCERTAIN _atpet-create-b ATPCS-MODE!
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-result-b
        _atpet-start
    _atpet-result-b _atpet-result-pending
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-result-b
        _atpet-cancel
    _atpet-result-b _atpet-result-uncertain
    _atpet-owner-b AT-TEXT-POST-CONNECTOR-CREATE-OUTCOME@
    DUP _atpet-ok DROP
    AT-CREATE-RECORD-OUTCOME-UNCERTAIN = _atpet-assert
    _atpet-event-b _atpet-op-b _atpet-owner-b _atpet-cleanup
        0= _atpet-assert ;

: _atpet-test-cleanup-error  ( -- )
    ATPCS-MODE-CREATED _atpet-create-a ATPCS-MODE!
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-start
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-result-a
        _atpet-poll
    _atpet-result-a _atpet-result-created
    -4991 _atpet-create-a ATPCS-WIPE-IOR!
    _atpet-event-a _atpet-op-a _atpet-owner-a _atpet-cleanup
        -4991 = _atpet-assert
    _atpet-result-a _atpet-result-created
    _atpet-owner-a AT-TEXT-POST-CONNECTOR-CLEANUP-ERROR@
        -4991 = _atpet-assert
    _atpet-check-uri-a _atpet-check-cid-a ;

: _ATPET-CANCEL-CLEANUP  ( -- )
    _atpet-rebuild-events
    _atpet-test-cancel-no-effect
    _atpet-test-cancel-uncertain
    _atpet-rebuild-events
    _atpet-test-cleanup-error
    _atpet-stack ;

: _ATPET-FINISH  ( -- )
    _atpet-fails @ 0= IF
        ." AT TEXT POST EGRESS PASS " _atpet-checks @ . CR
    ELSE
        ." AT TEXT POST EGRESS FAIL " _atpet-fails @ . CR
    THEN ;

: _ATPET-START  ( -- )
    0 _atpet-fails ! 0 _atpet-checks ! DEPTH _atpet-depth ! ;
