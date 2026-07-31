\ Focused contracts for the caller-owned createRecord JSON codec.
\
\ The arenas below are fixture vector storage, not production instance
\ limits.  Production sizing remains entirely caller-provided.

PROVIDED at-create-record-codec-test

4096 CONSTANT _CRCT-BODY-CAPACITY
4096 CONSTANT _CRCT-RECORD-CAPACITY
ATURI-LENGTH-MAX 2048 + CONSTANT _CRCT-RESPONSE-CAPACITY

VARIABLE _crct-checks
VARIABLE _crct-fails
VARIABLE _crct-depth
VARIABLE _crct-record-u
VARIABLE _crct-expected-u
VARIABLE _crct-response-u
VARIABLE _crct-repo-u
VARIABLE _crct-collection-u
VARIABLE _crct-rkey-u
VARIABLE _crct-expected-uri-u
VARIABLE _crct-written
VARIABLE _crct-measured
VARIABLE _crct-long-u
VARIABLE _crct-part-a
VARIABLE _crct-part-u
VARIABLE _crct-build-uri-a
VARIABLE _crct-build-uri-u
VARIABLE _crct-build-cid-a
VARIABLE _crct-build-cid-u
VARIABLE _crct-result-uri-a
VARIABLE _crct-result-uri-u
VARIABLE _crct-result-cid-a
VARIABLE _crct-result-cid-u

CREATE _crct-work-store
    AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 7 + ALLOT
CREATE _crct-repo DID-LENGTH-MAX 1+ ALLOT
CREATE _crct-collection NSID-LENGTH-MAX 1+ ALLOT
CREATE _crct-rkey AT-RKEY-LENGTH-MAX 1+ ALLOT
CREATE _crct-record _CRCT-RECORD-CAPACITY ALLOT
CREATE _crct-output _CRCT-BODY-CAPACITY ALLOT
CREATE _crct-expected _CRCT-BODY-CAPACITY ALLOT
CREATE _crct-response _CRCT-RESPONSE-CAPACITY ALLOT
CREATE _crct-expected-uri ATURI-LENGTH-MAX 1+ ALLOT
CREATE _crct-uri-snapshot ATURI-LENGTH-MAX ALLOT
CREATE _crct-cid-snapshot AT-CID-TEXT-LENGTH ALLOT
CREATE _crct-long-document JOSE-JSON-MAX-DOCUMENT-BYTES 1+ ALLOT
CREATE _crct-max-output AT-CREATE-RECORD-BODY-MAX 1+ ALLOT
CREATE _crct-long-type NSID-LENGTH-MAX 1+ ALLOT
CREATE _crct-long-uri ATURI-LENGTH-MAX 1+ ALLOT
CREATE _crct-long-cid AT-CID-TEXT-LENGTH 1+ ALLOT

: _crct-work  ( -- workspace )
    _crct-work-store 7 + -8 AND ;

: _crct-assert  ( flag -- )
    1 _crct-checks +!
    0= IF
        1 _crct-fails +!
        ." CREATE RECORD CODEC ASSERT " _crct-checks @ . CR
    THEN ;

: _crct-status  ( actual expected -- )
    2DUP <> IF
        ." CREATE RECORD CODEC STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _crct-assert ;

: _crct-stack  ( -- )
    DEPTH DUP _crct-depth @ <> IF
        ." CREATE RECORD CODEC STACK "
        _crct-depth @ . ." -> " DUP . CR .S CR
    THEN
    _crct-depth @ = _crct-assert ;

: _crct-filled?  ( address length byte -- flag )
    >R
    BEGIN
        DUP
    WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _crct-long+  ( address length -- )
    DUP _crct-long-u @ + JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        2DROP 0 _crct-assert EXIT
    THEN
    DUP >R
    _crct-long-document _crct-long-u @ + SWAP CMOVE
    R> _crct-long-u +! ;

: _crct-long-c!  ( byte -- )
    _crct-long-u @ JOSE-JSON-MAX-DOCUMENT-BYTES U< 0= IF
        DROP 0 _crct-assert EXIT
    THEN
    _crct-long-document _crct-long-u @ + C!
    1 _crct-long-u +! ;

: _crct-work-span?  ( address length -- flag )
    2DUP +
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE + U> IF
        2DROP 0 EXIT
    THEN
    DROP _crct-work U< 0= ;

: _crct-record+  ( address length -- )
    DUP _crct-record-u @ + _CRCT-RECORD-CAPACITY U> IF
        2DROP 0 _crct-assert EXIT
    THEN
    DUP >R
    _crct-record _crct-record-u @ + SWAP CMOVE
    R> _crct-record-u +! ;

: _crct-record-c!  ( byte -- )
    _crct-record-u @ _CRCT-RECORD-CAPACITY U< 0= IF
        DROP 0 _crct-assert EXIT
    THEN
    _crct-record _crct-record-u @ + C!
    1 _crct-record-u +! ;

: _crct-expected+  ( address length -- )
    DUP _crct-expected-u @ + _CRCT-BODY-CAPACITY U> IF
        2DROP 0 _crct-assert EXIT
    THEN
    DUP >R
    _crct-expected _crct-expected-u @ + SWAP CMOVE
    R> _crct-expected-u +! ;

: _crct-expected-c!  ( byte -- )
    _crct-expected-u @ _CRCT-BODY-CAPACITY U< 0= IF
        DROP 0 _crct-assert EXIT
    THEN
    _crct-expected _crct-expected-u @ + C!
    1 _crct-expected-u +! ;

: _crct-response+  ( address length -- )
    DUP _crct-response-u @ + _CRCT-RESPONSE-CAPACITY U> IF
        2DROP 0 _crct-assert EXIT
    THEN
    DUP >R
    _crct-response _crct-response-u @ + SWAP CMOVE
    R> _crct-response-u +! ;

: _crct-response-c!  ( byte -- )
    _crct-response-u @ _CRCT-RESPONSE-CAPACITY U< 0= IF
        DROP 0 _crct-assert EXIT
    THEN
    _crct-response _crct-response-u @ + C!
    1 _crct-response-u +! ;

: _crct-response-key  ( address length -- )
    34 _crct-response-c!
    _crct-response+
    34 _crct-response-c!
    58 _crct-response-c! ;

: _crct-response-string  ( address length -- )
    34 _crct-response-c!
    _crct-response+
    34 _crct-response-c! ;

: _crct-copy-inputs  ( -- )
    _crct-repo DID-LENGTH-MAX 1+ 0 FILL
    S" did:plc:abcdefghijklmnopqrstuvwx"
    DUP _crct-repo-u ! _crct-repo SWAP CMOVE
    _crct-collection NSID-LENGTH-MAX 1+ 0 FILL
    S" app.bsky.feed.post"
    DUP _crct-collection-u ! _crct-collection SWAP CMOVE
    _crct-rkey AT-RKEY-LENGTH-MAX 1+ 0 FILL
    S" Key:One"
    DUP _crct-rkey-u ! _crct-rkey SWAP CMOVE ;

: _crct-record-start  ( type-a type-u -- )
    _crct-part-u ! _crct-part-a !
    _crct-record _CRCT-RECORD-CAPACITY 0 FILL
    0 _crct-record-u !
    123 _crct-record-c!
    34 _crct-record-c! S" $type" _crct-record+
    34 _crct-record-c! 58 _crct-record-c! 34 _crct-record-c!
    _crct-part-a @ _crct-part-u @ _crct-record+
    34 _crct-record-c! ;

: _crct-build-base-record  ( -- )
    \ The outer protocol fields exclude JSON metacharacters by grammar.
    \ Escaped text therefore lives in the admitted record and must remain
    \ byte-exact beneath the deterministic envelope.
    S" app.bsky.feed.post" _crct-record-start
    44 _crct-record-c!
    34 _crct-record-c! S" text" _crct-record+
    34 _crct-record-c! 58 _crct-record-c! 34 _crct-record-c!
    S" line" _crct-record+
    92 _crct-record-c! 110 _crct-record-c!
    92 _crct-record-c! 34 _crct-record-c!
    S" quoted" _crct-record+
    92 _crct-record-c! 34 _crct-record-c!
    92 _crct-record-c! 92 _crct-record-c!
    S" slash" _crct-record+
    34 _crct-record-c! 44 _crct-record-c!
    34 _crct-record-c! S" nested" _crct-record+
    34 _crct-record-c! 58 _crct-record-c! 123 _crct-record-c!
    34 _crct-record-c! S" ok" _crct-record+
    34 _crct-record-c! 58 _crct-record-c!
    S" true" _crct-record+ 125 _crct-record-c!
    44 _crct-record-c!
    34 _crct-record-c! S" tags" _crct-record+
    34 _crct-record-c! 58 _crct-record-c! 91 _crct-record-c!
    34 _crct-record-c! S" a" _crct-record+ 34 _crct-record-c!
    44 _crct-record-c!
    34 _crct-record-c! S" b" _crct-record+ 34 _crct-record-c!
    93 _crct-record-c! 125 _crct-record-c! ;

: _crct-build-expected-body  ( -- )
    _crct-expected _CRCT-BODY-CAPACITY 0 FILL
    0 _crct-expected-u !
    123 _crct-expected-c!
    34 _crct-expected-c! S" repo" _crct-expected+
    34 _crct-expected-c! 58 _crct-expected-c!
    34 _crct-expected-c!
    _crct-repo _crct-repo-u @ _crct-expected+
    34 _crct-expected-c! 44 _crct-expected-c!
    34 _crct-expected-c! S" collection" _crct-expected+
    34 _crct-expected-c! 58 _crct-expected-c!
    34 _crct-expected-c!
    _crct-collection _crct-collection-u @ _crct-expected+
    34 _crct-expected-c! 44 _crct-expected-c!
    34 _crct-expected-c! S" rkey" _crct-expected+
    34 _crct-expected-c! 58 _crct-expected-c!
    34 _crct-expected-c!
    _crct-rkey _crct-rkey-u @ _crct-expected+
    34 _crct-expected-c! 44 _crct-expected-c!
    34 _crct-expected-c! S" record" _crct-expected+
    34 _crct-expected-c! 58 _crct-expected-c!
    _crct-record _crct-record-u @ _crct-expected+
    125 _crct-expected-c! ;

: _crct-prepare-body  ( -- )
    _crct-copy-inputs
    _crct-build-base-record ;

: _crct-body  ( -- written status )
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-record _crct-record-u @
    _crct-output _CRCT-BODY-CAPACITY _crct-work
    AT-CREATE-RECORD-BODY ;

: _crct-body-measure  ( -- bytes status )
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-record _crct-record-u @
    _crct-work AT-CREATE-RECORD-BODY-MEASURE ;

: _crct-body-result  ( written status expected -- )
    >R R> _crct-status
    0= _crct-assert ;

: _crct-expect-body  ( expected -- )
    >R
    _crct-output _CRCT-BODY-CAPACITY 0xA5 FILL
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0xA5 FILL
    _crct-body R> _crct-body-result
    _crct-output _CRCT-BODY-CAPACITY 0xA5
    _crct-filled? _crct-assert
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert ;

: _crct-build-max-record  ( -- )
    _crct-long-document JOSE-JSON-MAX-DOCUMENT-BYTES 0 FILL
    0 _crct-long-u !
    123 _crct-long-c!
    34 _crct-long-c! S" $type" _crct-long+ 34 _crct-long-c!
    58 _crct-long-c! 34 _crct-long-c!
    S" app.bsky.feed.post" _crct-long+ 34 _crct-long-c!
    44 _crct-long-c!
    34 _crct-long-c! S" x" _crct-long+ 34 _crct-long-c!
    58 _crct-long-c! 34 _crct-long-c!
    JOSE-JSON-MAX-DOCUMENT-BYTES _crct-long-u @ - 2 -
    _crct-long-document _crct-long-u @ + SWAP [CHAR] a FILL
    JOSE-JSON-MAX-DOCUMENT-BYTES 2 - _crct-long-u !
    34 _crct-long-c! 125 _crct-long-c! ;

: _crct-build-type-only  ( type-a type-u -- )
    _crct-record-start
    125 _crct-record-c! ;

: _crct-build-missing-type  ( -- )
    _crct-record _CRCT-RECORD-CAPACITY 0 FILL
    0 _crct-record-u !
    123 _crct-record-c!
    34 _crct-record-c! S" text" _crct-record+
    34 _crct-record-c! 58 _crct-record-c!
    34 _crct-record-c! S" no type" _crct-record+
    34 _crct-record-c! 125 _crct-record-c! ;

: _crct-build-nonstring-type  ( -- )
    _crct-record _CRCT-RECORD-CAPACITY 0 FILL
    0 _crct-record-u !
    123 _crct-record-c!
    34 _crct-record-c! S" $type" _crct-record+
    34 _crct-record-c! 58 _crct-record-c!
    S" true" _crct-record+
    125 _crct-record-c! ;

: _crct-build-duplicate-type  ( -- )
    S" app.bsky.feed.post" _crct-record-start
    44 _crct-record-c! 34 _crct-record-c!
    92 _crct-record-c! S" u0024type" _crct-record+
    34 _crct-record-c! 58 _crct-record-c! 34 _crct-record-c!
    S" app.bsky.feed.post" _crct-record+
    34 _crct-record-c! 125 _crct-record-c! ;

: _crct-build-malformed-unknown-record  ( -- )
    S" app.bsky.feed.post" _crct-record-start
    44 _crct-record-c! 34 _crct-record-c!
    S" unknown" _crct-record+ 34 _crct-record-c! 58 _crct-record-c!
    123 _crct-record-c!
    34 _crct-record-c! S" items" _crct-record+
    34 _crct-record-c! 58 _crct-record-c!
    91 _crct-record-c! 49 _crct-record-c!
    44 _crct-record-c! 93 _crct-record-c!
    125 _crct-record-c! 125 _crct-record-c! ;

: _crct-standard-uri  ( -- address length )
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/Key:One" ;

: _crct-dag-cid  ( -- address length )
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;

: _crct-raw-cid  ( -- address length )
    S" bafkreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;

: _crct-set-standard-uri  ( -- )
    _crct-expected-uri ATURI-LENGTH-MAX 1+ 0 FILL
    _crct-standard-uri
    DUP _crct-expected-uri-u !
    _crct-expected-uri SWAP CMOVE ;

: _crct-response-start  ( -- )
    _crct-response _CRCT-RESPONSE-CAPACITY 0 FILL
    0 _crct-response-u !
    123 _crct-response-c! ;

: _crct-build-simple-receipt
  \ ( uri-a uri-u cid-a cid-u -- )
    _crct-build-cid-u ! _crct-build-cid-a !
    _crct-build-uri-u ! _crct-build-uri-a !
    _crct-response-start
    S" uri" _crct-response-key
    _crct-build-uri-a @ _crct-build-uri-u @ _crct-response-string
    44 _crct-response-c!
    S" cid" _crct-response-key
    _crct-build-cid-a @ _crct-build-cid-u @ _crct-response-string
    125 _crct-response-c! ;

: _crct-build-success-receipt  ( -- )
    _crct-response-start
    S" cid" _crct-response-key
    _crct-dag-cid _crct-response-string
    44 _crct-response-c!
    S" extra" _crct-response-key
    123 _crct-response-c!
    S" nested" _crct-response-key
    91 _crct-response-c!
    S" true,null," _crct-response+
    123 _crct-response-c!
    S" x" _crct-response-key
    34 _crct-response-c! 92 _crct-response-c!
    S" u0061" _crct-response+
    34 _crct-response-c! 125 _crct-response-c!
    93 _crct-response-c! 125 _crct-response-c!
    44 _crct-response-c!
    S" uri" _crct-response-key
    34 _crct-response-c! 92 _crct-response-c!
    S" u0061t://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/Key:One"
    _crct-response+
    34 _crct-response-c!
    125 _crct-response-c! ;

: _crct-receipt  ( -- uri-a uri-u cid-a cid-u status )
    _crct-response _crct-response-u @
    _crct-expected-uri _crct-expected-uri-u @
    _crct-work AT-CREATE-RECORD-RECEIPT ;

: _crct-save-receipt  ( uri-a uri-u cid-a cid-u -- )
    _crct-result-cid-u ! _crct-result-cid-a !
    _crct-result-uri-u ! _crct-result-uri-a ! ;

: _crct-expect-receipt-failure  ( expected-status -- )
    >R
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0xA5 FILL
    _crct-receipt R> _crct-status
    OR OR OR 0= _crct-assert
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert ;

: _crct-build-malformed-unknown-receipt  ( -- )
    _crct-response-start
    S" uri" _crct-response-key
    _crct-expected-uri _crct-expected-uri-u @ _crct-response-string
    44 _crct-response-c!
    S" cid" _crct-response-key
    _crct-dag-cid _crct-response-string
    44 _crct-response-c!
    S" extra" _crct-response-key
    123 _crct-response-c!
    S" items" _crct-response-key
    91 _crct-response-c! 49 _crct-response-c!
    44 _crct-response-c! 93 _crct-response-c!
    125 _crct-response-c! 125 _crct-response-c! ;

: _crct-build-duplicate-uri-receipt  ( -- )
    _crct-response-start
    S" uri" _crct-response-key
    _crct-expected-uri _crct-expected-uri-u @ _crct-response-string
    44 _crct-response-c!
    34 _crct-response-c! 92 _crct-response-c!
    S" u0075ri" _crct-response+
    34 _crct-response-c! 58 _crct-response-c!
    _crct-expected-uri _crct-expected-uri-u @ _crct-response-string
    44 _crct-response-c!
    S" cid" _crct-response-key
    _crct-dag-cid _crct-response-string
    125 _crct-response-c! ;

: _crct-build-duplicate-cid-receipt  ( -- )
    _crct-response-start
    S" uri" _crct-response-key
    _crct-expected-uri _crct-expected-uri-u @ _crct-response-string
    44 _crct-response-c!
    S" cid" _crct-response-key
    _crct-dag-cid _crct-response-string
    44 _crct-response-c!
    34 _crct-response-c! 92 _crct-response-c!
    S" u0063id" _crct-response+
    34 _crct-response-c! 58 _crct-response-c!
    _crct-dag-cid _crct-response-string
    125 _crct-response-c! ;

: _crct-build-missing-uri-receipt  ( -- )
    _crct-response-start
    S" cid" _crct-response-key
    _crct-dag-cid _crct-response-string
    125 _crct-response-c! ;

: _crct-build-missing-cid-receipt  ( -- )
    _crct-response-start
    S" uri" _crct-response-key
    _crct-expected-uri _crct-expected-uri-u @ _crct-response-string
    125 _crct-response-c! ;

: _crct-build-wrong-type-receipt  ( -- )
    _crct-response-start
    S" uri" _crct-response-key
    S" true" _crct-response+
    44 _crct-response-c!
    S" cid" _crct-response-key
    _crct-dag-cid _crct-response-string
    125 _crct-response-c! ;

: _crct-test-statuses  ( -- )
    AT-CREATE-RECORD-S-OK AT-CREATE-RECORD-STATUS-VALID?
    _crct-assert
    AT-CREATE-RECORD-S-INTERNAL AT-CREATE-RECORD-STATUS-VALID?
    _crct-assert
    -1 AT-CREATE-RECORD-STATUS-VALID? 0= _crct-assert
    AT-CREATE-RECORD-S-INTERNAL 1+
    AT-CREATE-RECORD-STATUS-VALID? 0= _crct-assert
    _ATCRC-BODY-FIXED-BYTES 47 = _crct-assert
    AT-CREATE-RECORD-BODY-MAX 68460 = _crct-assert
    AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0> _crct-assert
    _crct-work 7 AND 0= _crct-assert
    _ATCRW-STAGING-OFF 7 AND 0= _crct-assert
    _ATCRW-STAGING-OFF AT-CREATE-RECORD-BODY-MAX +
    7 + -8 AND AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE =
    _crct-assert
    _crct-stack ;

: _crct-test-body-measure  ( -- )
    _crct-prepare-body
    _crct-build-expected-body
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0x5A FILL
    _crct-body-measure
    DUP AT-CREATE-RECORD-S-OK _crct-status DROP
    DUP _crct-measured !
    _crct-expected-u @ = _crct-assert
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert

    _crct-prepare-body
    S" App.bsky.feed.post"
    DUP _crct-collection-u ! _crct-collection SWAP CMOVE
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0x5A FILL
    _crct-body-measure
    AT-CREATE-RECORD-S-COLLECTION _crct-body-result
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert
    _crct-stack ;

: _crct-test-body-exact  ( -- )
    _crct-prepare-body
    _crct-build-expected-body
    _crct-output _CRCT-BODY-CAPACITY 0xA5 FILL
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0x5A FILL
    _crct-body
    DUP AT-CREATE-RECORD-S-OK _crct-status DROP
    DUP _crct-written !
    DUP _crct-measured @ = _crct-assert
    _crct-expected-u @ = _crct-assert
    _crct-output _crct-written @
    _crct-expected _crct-expected-u @ COMPARE 0= _crct-assert
    _crct-output _crct-written @ + C@ 0xA5 = _crct-assert
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert

    \ The published body owns every byte after all caller inputs vanish.
    _crct-repo DID-LENGTH-MAX 1+ 0xA1 FILL
    _crct-collection NSID-LENGTH-MAX 1+ 0xB2 FILL
    _crct-rkey AT-RKEY-LENGTH-MAX 1+ 0xC3 FILL
    _crct-record _CRCT-RECORD-CAPACITY 0xD4 FILL
    _crct-output _crct-written @
    _crct-expected _crct-expected-u @ COMPARE 0= _crct-assert
    _crct-stack ;

: _crct-test-body-capacity  ( -- )
    _crct-prepare-body
    _crct-output _CRCT-BODY-CAPACITY 0xA5 FILL
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-record _crct-record-u @
    _crct-output _crct-measured @ _crct-work
    AT-CREATE-RECORD-BODY
    DUP AT-CREATE-RECORD-S-OK _crct-status DROP
    _crct-measured @ = _crct-assert
    _crct-output _crct-written @
    _crct-expected _crct-expected-u @ COMPARE 0= _crct-assert
    _crct-output _crct-written @ + C@ 0xA5 = _crct-assert

    _crct-prepare-body
    _crct-output _CRCT-BODY-CAPACITY 0xA5 FILL
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-record _crct-record-u @
    _crct-output _crct-measured @ 1- _crct-work
    AT-CREATE-RECORD-BODY
    AT-CREATE-RECORD-S-CAPACITY _crct-body-result
    _crct-output _CRCT-BODY-CAPACITY 0xA5
    _crct-filled? _crct-assert
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert
    _crct-stack ;

: _crct-test-body-maximum-measure  ( -- )
    _crct-copy-inputs
    _crct-build-max-record
    _crct-long-u @ JOSE-JSON-MAX-DOCUMENT-BYTES = _crct-assert
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-long-document _crct-long-u @
    _crct-work AT-CREATE-RECORD-BODY-MEASURE
    DUP AT-CREATE-RECORD-S-OK _crct-status DROP
    DUP _crct-measured !
    _ATCRC-BODY-FIXED-BYTES
    _crct-repo-u @ + _crct-collection-u @ +
    _crct-rkey-u @ + JOSE-JSON-MAX-DOCUMENT-BYTES +
    = _crct-assert
    _crct-stack ;

: _crct-test-body-maximum-encode  ( -- )
    _crct-copy-inputs
    _crct-build-max-record
    _crct-long-u @ JOSE-JSON-MAX-DOCUMENT-BYTES = _crct-assert
    _crct-max-output AT-CREATE-RECORD-BODY-MAX 1+ 0xA5 FILL
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-long-document _crct-long-u @
    _crct-max-output _crct-measured @ _crct-work
    AT-CREATE-RECORD-BODY
    DUP AT-CREATE-RECORD-S-OK _crct-status DROP
    DUP _crct-measured @ = _crct-assert
    1- _crct-max-output + C@ 125 = _crct-assert
    _crct-max-output _crct-measured @ + C@ 0xA5 = _crct-assert
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert
    _crct-stack ;

: _crct-test-body-admission  ( -- )
    _crct-prepare-body
    S" alice.test" DUP _crct-repo-u ! _crct-repo SWAP CMOVE
    AT-CREATE-RECORD-S-REPOSITORY _crct-expect-body

    _crct-prepare-body
    _crct-repo DID-LENGTH-MAX 1+ [CHAR] a FILL
    DID-LENGTH-MAX 1+ _crct-repo-u !
    AT-CREATE-RECORD-S-REPOSITORY _crct-expect-body

    _crct-prepare-body
    S" App.bsky.feed.post"
    DUP _crct-collection-u ! _crct-collection SWAP CMOVE
    AT-CREATE-RECORD-S-COLLECTION _crct-expect-body

    _crct-prepare-body
    _crct-collection NSID-LENGTH-MAX 1+ [CHAR] a FILL
    NSID-LENGTH-MAX 1+ _crct-collection-u !
    AT-CREATE-RECORD-S-COLLECTION _crct-expect-body

    _crct-prepare-body
    S" bad/key" DUP _crct-rkey-u ! _crct-rkey SWAP CMOVE
    AT-CREATE-RECORD-S-RKEY _crct-expect-body

    _crct-prepare-body
    _crct-rkey AT-RKEY-LENGTH-MAX 1+ [CHAR] a FILL
    AT-RKEY-LENGTH-MAX 1+ _crct-rkey-u !
    AT-CREATE-RECORD-S-RKEY _crct-expect-body

    _crct-prepare-body
    _crct-build-missing-type
    AT-CREATE-RECORD-S-MISSING _crct-expect-body

    _crct-prepare-body
    _crct-build-nonstring-type
    AT-CREATE-RECORD-S-TYPE _crct-expect-body

    _crct-prepare-body
    S" app.bsky.feed.like" _crct-build-type-only
    AT-CREATE-RECORD-S-TYPE _crct-expect-body

    _crct-prepare-body
    _crct-long-type NSID-LENGTH-MAX 1+ [CHAR] a FILL
    _crct-long-type NSID-LENGTH-MAX 1+ _crct-build-type-only
    AT-CREATE-RECORD-S-TYPE _crct-expect-body

    _crct-prepare-body
    _crct-build-duplicate-type
    AT-CREATE-RECORD-S-JSON _crct-expect-body

    _crct-prepare-body
    _crct-build-malformed-unknown-record
    AT-CREATE-RECORD-S-JSON _crct-expect-body

    _crct-long-document JOSE-JSON-MAX-DOCUMENT-BYTES 1+
    [CHAR] a FILL
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    _crct-output _CRCT-BODY-CAPACITY 0xA5 FILL
    _crct-repo _crct-repo-u @
    _crct-collection _crct-collection-u @
    _crct-rkey _crct-rkey-u @
    _crct-long-document JOSE-JSON-MAX-DOCUMENT-BYTES 1+
    _crct-output _CRCT-BODY-CAPACITY _crct-work
    AT-CREATE-RECORD-BODY
    AT-CREATE-RECORD-S-CAPACITY _crct-body-result
    _crct-output _CRCT-BODY-CAPACITY 0xA5
    _crct-filled? _crct-assert
    _crct-stack ;

: _crct-test-receipt-detachment  ( -- )
    _crct-set-standard-uri
    _crct-build-success-receipt
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0xA5 FILL
    _crct-receipt
    DUP AT-CREATE-RECORD-S-OK _crct-status DROP
    _crct-save-receipt

    _crct-result-uri-a @ _crct-result-uri-u @
    _crct-work-span? _crct-assert
    _crct-result-cid-a @ _crct-result-cid-u @
    _crct-work-span? _crct-assert
    _crct-result-uri-a @ _crct-result-uri-u @
    _crct-result-cid-a @ _crct-result-cid-u @
    MSPAN-OVERLAP? 0= _crct-assert
    _crct-result-uri-a @ _crct-work - 0> _crct-assert
    _crct-work _crct-result-uri-a @ _crct-work -
    0 _crct-filled? _crct-assert

    _crct-result-uri-u @ _crct-expected-uri-u @ = _crct-assert
    _crct-result-uri-a @ _crct-result-uri-u @
    _crct-expected-uri _crct-expected-uri-u @
    COMPARE 0= _crct-assert
    _crct-result-cid-u @ AT-CID-TEXT-LENGTH = _crct-assert
    _crct-result-cid-a @ _crct-result-cid-u @
    _crct-dag-cid COMPARE 0= _crct-assert

    _crct-result-uri-a @ _crct-uri-snapshot
    _crct-result-uri-u @ CMOVE
    _crct-result-cid-a @ _crct-cid-snapshot
    _crct-result-cid-u @ CMOVE

    \ Returned bytes remain live after both external source spans vanish.
    _crct-response _CRCT-RESPONSE-CAPACITY 0xA5 FILL
    _crct-expected-uri ATURI-LENGTH-MAX 1+ 0x5A FILL
    _crct-result-uri-a @ _crct-result-uri-u @
    _crct-uri-snapshot _crct-result-uri-u @
    COMPARE 0= _crct-assert
    _crct-result-cid-a @ _crct-result-cid-u @
    _crct-cid-snapshot _crct-result-cid-u @
    COMPARE 0= _crct-assert

    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-CLEAR
    AT-CREATE-RECORD-S-OK _crct-status
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE
    0 _crct-filled? _crct-assert
    _crct-uri-snapshot _crct-result-uri-u @
    _crct-standard-uri COMPARE 0= _crct-assert
    _crct-cid-snapshot _crct-result-cid-u @
    _crct-dag-cid COMPARE 0= _crct-assert
    _crct-stack ;

: _crct-test-receipt-admission-a  ( -- )
    _crct-set-standard-uri
    _crct-expected-uri _crct-expected-uri-u @
    _crct-raw-cid _crct-build-simple-receipt
    AT-CREATE-RECORD-S-CID _crct-expect-receipt-failure

    _crct-set-standard-uri
    S" at://did:plc:abcdefghijklmnopqrstuvwx/app.bsky.feed.post/Other"
    _crct-dag-cid _crct-build-simple-receipt
    AT-CREATE-RECORD-S-URI _crct-expect-receipt-failure

    _crct-set-standard-uri
    _crct-build-malformed-unknown-receipt
    AT-CREATE-RECORD-S-JSON _crct-expect-receipt-failure

    _crct-set-standard-uri
    _crct-build-duplicate-uri-receipt
    AT-CREATE-RECORD-S-JSON _crct-expect-receipt-failure

    _crct-set-standard-uri
    _crct-build-duplicate-cid-receipt
    AT-CREATE-RECORD-S-JSON _crct-expect-receipt-failure
    _crct-stack ;

: _crct-test-receipt-admission-b  ( -- )
    _crct-set-standard-uri
    _crct-build-missing-uri-receipt
    AT-CREATE-RECORD-S-MISSING _crct-expect-receipt-failure

    _crct-set-standard-uri
    _crct-build-missing-cid-receipt
    AT-CREATE-RECORD-S-MISSING _crct-expect-receipt-failure

    _crct-set-standard-uri
    _crct-build-wrong-type-receipt
    AT-CREATE-RECORD-S-TYPE _crct-expect-receipt-failure

    _crct-set-standard-uri
    _crct-expected-uri ATURI-LENGTH-MAX 1+ [CHAR] a FILL
    ATURI-LENGTH-MAX 1+ _crct-expected-uri-u !
    _crct-standard-uri _crct-dag-cid _crct-build-simple-receipt
    _crct-work AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE 0 FILL
    _crct-receipt AT-CREATE-RECORD-S-CAPACITY _crct-status
    OR OR OR 0= _crct-assert

    _crct-set-standard-uri
    _crct-long-uri ATURI-LENGTH-MAX 1+ [CHAR] a FILL
    _crct-long-uri ATURI-LENGTH-MAX 1+
    _crct-dag-cid _crct-build-simple-receipt
    AT-CREATE-RECORD-S-URI _crct-expect-receipt-failure
    _crct-stack ;

: _crct-test-receipt-admission-c  ( -- )
    _crct-set-standard-uri
    _crct-dag-cid _crct-long-cid SWAP CMOVE
    [CHAR] a _crct-long-cid AT-CID-TEXT-LENGTH + C!
    _crct-expected-uri _crct-expected-uri-u @
    _crct-long-cid AT-CID-TEXT-LENGTH 1+
    _crct-build-simple-receipt
    AT-CREATE-RECORD-S-CID _crct-expect-receipt-failure

    _crct-expected-uri ATURI-LENGTH-MAX 1+ 0 FILL
    S" at://alice.test/app.bsky.feed.post/Key:One"
    DUP _crct-expected-uri-u !
    _crct-expected-uri SWAP CMOVE
    _crct-expected-uri _crct-expected-uri-u @
    _crct-dag-cid _crct-build-simple-receipt
    AT-CREATE-RECORD-S-URI _crct-expect-receipt-failure

    _crct-expected-uri ATURI-LENGTH-MAX 1+ 0 FILL
    S" at://did:plc:abcdefghijklmnopqrstuvwx"
    DUP _crct-expected-uri-u !
    _crct-expected-uri SWAP CMOVE
    _crct-expected-uri _crct-expected-uri-u @
    _crct-dag-cid _crct-build-simple-receipt
    AT-CREATE-RECORD-S-URI _crct-expect-receipt-failure
    _crct-stack ;

: _CRCT-RUN  ( -- )
    0 _crct-checks !
    0 _crct-fails !
    DEPTH _crct-depth !
    _crct-test-statuses
    _crct-test-body-measure
    _crct-test-body-exact
    _crct-test-body-capacity
    ." CREATE RECORD CODEC BODY BASIC READY" CR TX-FLUSH
    KEY DROP
    _crct-test-body-admission
    ." CREATE RECORD CODEC BODY ADMISSION READY" CR TX-FLUSH
    KEY DROP
    _crct-test-receipt-detachment
    ." CREATE RECORD CODEC RECEIPT DETACHMENT READY" CR TX-FLUSH
    KEY DROP
    _crct-test-receipt-admission-a
    ." CREATE RECORD CODEC RECEIPT ADMISSION A READY" CR TX-FLUSH
    KEY DROP
    _crct-test-receipt-admission-b
    ." CREATE RECORD CODEC RECEIPT ADMISSION B READY" CR TX-FLUSH
    KEY DROP
    _crct-test-receipt-admission-c
    ." CREATE RECORD CODEC ORDINARY READY" CR TX-FLUSH
    KEY DROP
    _crct-test-body-maximum-measure
    ." CREATE RECORD CODEC MAXIMUM MEASURE READY" CR TX-FLUSH
    KEY DROP
    _crct-test-body-maximum-encode
    _crct-fails @ IF
        ." CREATE RECORD CODEC FAIL checks/fails "
        _crct-checks @ . _crct-fails @ . CR
    ELSE
        ." CREATE RECORD CODEC PASS checks " _crct-checks @ . CR
    THEN ;
