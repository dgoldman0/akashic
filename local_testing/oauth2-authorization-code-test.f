\ Focused generic OAuth authorization-code transaction contracts.
\ The linked image installs this source under an MP64FS-safe guest name.

PROVIDED akashic-o2code-tests

VARIABLE _o2ct-checks
VARIABLE _o2ct-fails
VARIABLE _o2ct-depth
VARIABLE _o2ct-query-u
VARIABLE _o2ct-copy-u
VARIABLE _o2ct-callback-count
VARIABLE _o2ct-seen-binding-u
VARIABLE _o2ct-seen-state-u
VARIABLE _o2ct-seen-challenge-u
VARIABLE _o2ct-seen-request-uri-u
VARIABLE _o2ct-seen-code-u
VARIABLE _o2ct-seen-verifier-u

: _o2ct-assert  ( flag -- )
    1 _o2ct-checks +!
    0= IF
        1 _o2ct-fails +!
        ." OAUTH2 AUTHORIZATION CODE ASSERT " _o2ct-checks @ . CR
        TX-FLUSH
    THEN ;

: _o2ct-status  ( actual expected -- )
    2DUP <> IF
        ." OAUTH2 AUTHORIZATION CODE STATUS actual/expected "
        2DUP SWAP . . CR TX-FLUSH
    THEN
    = _o2ct-assert ;

: _o2ct-stack  ( -- )
    DEPTH DUP _o2ct-depth @ <> IF
        ." OAUTH2 AUTHORIZATION CODE STACK "
        _o2ct-depth @ . ." -> " DUP . CR .S CR
        TX-FLUSH
    THEN
    _o2ct-depth @ = _o2ct-assert ;

: _o2ct-filled?  ( address length byte -- flag )
    0x0101010101010101 *
    BEGIN
        2 PICK 7 AND 0<>
        2 PICK 0<> AND
    WHILE
        2 PICK C@ OVER 0xFF AND <> IF
            2DROP DROP 0 EXIT
        THEN
        >R
        1- SWAP 1+ SWAP
        R>
    REPEAT
    BEGIN 1 PICK 8 U< 0= WHILE
        2 PICK @ OVER <> IF
            2DROP DROP 0 EXIT
        THEN
        >R
        8 - SWAP 8 + SWAP
        R>
    REPEAT
    BEGIN 1 PICK WHILE
        2 PICK C@ OVER 0xFF AND <> IF
            2DROP DROP 0 EXIT
        THEN
        >R
        1- SWAP 1+ SWAP
        R>
    REPEAT
    2DROP DROP -1 ;

: _o2ct-zero?  ( address length -- flag )
    0 _o2ct-filled? ;

: _o2ct-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

CREATE _o2ct-object-storage O2CODE-TRANSACTION-SIZE 7 + ALLOT
CREATE _o2ct-object-b-storage O2CODE-TRANSACTION-SIZE 7 + ALLOT
CREATE _o2ct-object-copy O2CODE-TRANSACTION-SIZE ALLOT
CREATE _o2ct-work-storage O2CODE-WORKSPACE-SIZE 15 + ALLOT
CREATE _o2ct-work-b-storage O2CODE-WORKSPACE-SIZE 15 + ALLOT
CREATE _o2ct-query O2CODE-CALLBACK-QUERY-CAPACITY 256 + ALLOT
CREATE _o2ct-challenge-copy O2CODE-CHALLENGE-SIZE ALLOT
CREATE _o2ct-state-copy O2CODE-STATE-SIZE ALLOT
CREATE _o2ct-verifier-copy O2CODE-VERIFIER-SIZE ALLOT
CREATE _o2ct-binding-copy O2CODE-BINDING-CAPACITY ALLOT
CREATE _o2ct-request-uri-copy O2CODE-REQUEST-URI-CAPACITY ALLOT
CREATE _o2ct-code-copy O2CODE-CODE-CAPACITY ALLOT
CREATE _o2ct-recomputed O2CODE-CHALLENGE-SIZE ALLOT
CREATE _o2ct-decoded-raw 32 ALLOT
CREATE _o2ct-pkce-work OAUTH2-PKCE-WORKSPACE-SIZE ALLOT

: _o2ct-object  ( -- address )
    _o2ct-object-storage 7 + -8 AND ;

: _o2ct-object-b  ( -- address )
    _o2ct-object-b-storage 7 + -8 AND ;

: _o2ct-work  ( -- address )
    _o2ct-work-storage 7 + -8 AND ;

: _o2ct-work-b  ( -- address )
    _o2ct-work-b-storage 7 + -8 AND ;

: _o2ct-work-zero?  ( -- flag )
    _o2ct-work O2CODE-WORKSPACE-SIZE _o2ct-zero? ;

: _o2ct-work-b-zero?  ( -- flag )
    _o2ct-work-b O2CODE-WORKSPACE-SIZE _o2ct-zero? ;

: _o2ct-work-filled?  ( -- flag )
    _o2ct-work O2CODE-WORKSPACE-SIZE 0xC3 _o2ct-filled? ;

: _o2ct-fill-work  ( -- )
    _o2ct-work O2CODE-WORKSPACE-SIZE 0xC3 FILL ;

: _o2ct-fill-work-b  ( -- )
    _o2ct-work-b O2CODE-WORKSPACE-SIZE 0x3C FILL ;

: _o2ct-binding  ( -- address length )
    S" account-slot-17" ;

: _o2ct-issuer  ( -- address length )
    S" https://issuer.example" ;

: _o2ct-request-uri  ( -- address length )
    S" urn:ietf:params:oauth:request_uri:slot-17" ;

: _o2ct-query-reset  ( -- )
    0 _o2ct-query-u ! ;

: _o2ct-query-char  ( byte -- )
    _o2ct-query _o2ct-query-u @ + C!
    1 _o2ct-query-u +! ;

: _o2ct-query-text  ( address length -- )
    DUP _o2ct-copy-u !
    _o2ct-query _o2ct-query-u @ + SWAP MOVE
    _o2ct-copy-u @ _o2ct-query-u +! ;

: _o2ct-query-state  ( -- )
    _o2ct-object _O2C.STATE O2CODE-STATE-SIZE
    _o2ct-query-text ;

: _o2ct-query-source  ( -- address length )
    _o2ct-query _o2ct-query-u @ ;

: _o2ct-query-add-state  ( -- )
    S" &state=" _o2ct-query-text
    _o2ct-query-state ;

: _o2ct-query-add-issuer  ( -- )
    S" &iss=https%3A%2F%2Fissuer.example"
    _o2ct-query-text ;

: _o2ct-build-success  ( -- )
    _o2ct-query-reset
    S" code=opaque%2Dauthorization%2Bcode"
    _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer
    S" &extension=one+two" _o2ct-query-text ;

: _o2ct-build-success-without-issuer  ( -- )
    _o2ct-query-reset
    S" code=issuer%2Doptional" _o2ct-query-text
    _o2ct-query-add-state ;

: _o2ct-build-denial  ( -- )
    _o2ct-query-reset
    S" error=access_denied" _o2ct-query-text
    S" &error_description=Owner+said+no"
    _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer ;

: _o2ct-build-state-mismatch  ( -- )
    _o2ct-query-reset
    S" code=never&state=definitely-wrong"
    _o2ct-query-text
    _o2ct-query-add-issuer ;

: _o2ct-build-issuer-mismatch  ( -- )
    _o2ct-query-reset
    S" code=never" _o2ct-query-text
    _o2ct-query-add-state
    S" &iss=https%3A%2F%2Fevil.example"
    _o2ct-query-text ;

: _o2ct-build-malformed-escape  ( -- )
    _o2ct-query-reset
    S" code=never&extension=%2G"
    _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer ;

: _o2ct-build-decoded-duplicate  ( -- )
    _o2ct-query-reset
    S" co%64e=first&code=second"
    _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer ;

: _o2ct-build-unknown-decoded-duplicate  ( -- )
    _o2ct-query-reset
    S" code=never&x=one&%78=two"
    _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer ;

: _o2ct-build-code-and-error  ( -- )
    _o2ct-query-reset
    S" code=one&error=access_denied"
    _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer ;

: _o2ct-build-missing-result  ( -- )
    _o2ct-query-reset
    S" extension=only" _o2ct-query-text
    _o2ct-query-add-state
    _o2ct-query-add-issuer ;

: _o2ct-build-missing-state  ( -- )
    _o2ct-query-reset
    S" code=never" _o2ct-query-text
    _o2ct-query-add-issuer ;

: _o2ct-object-copy!  ( -- )
    _o2ct-object _o2ct-object-copy
    O2CODE-TRANSACTION-SIZE MOVE ;

: _o2ct-object-unchanged?  ( -- flag )
    _o2ct-object _o2ct-object-copy
    O2CODE-TRANSACTION-SIZE _o2ct-bytes= ;

: _o2ct-phase?  ( expected -- )
    >R _o2ct-object O2CODE-PHASE@
    O2CODE-S-OK _o2ct-status
    R> = _o2ct-assert ;

: _o2ct-fresh  ( -- )
    _o2ct-object O2CODE-INIT?
    O2CODE-S-OK _o2ct-status ;

: _o2ct-test-vocabulary-and-init  ( -- )
    O2CODE-S-OK O2CODE-STATUS-VALID? _o2ct-assert
    O2CODE-S-INTERNAL O2CODE-STATUS-VALID? _o2ct-assert
    -1 O2CODE-STATUS-VALID? 0= _o2ct-assert
    O2CODE-S-INTERNAL 1+
    O2CODE-STATUS-VALID? 0= _o2ct-assert
    O2CODE-STATE-SIZE 43 = _o2ct-assert
    O2CODE-VERIFIER-SIZE 43 = _o2ct-assert
    O2CODE-CHALLENGE-SIZE 43 = _o2ct-assert
    O2CODE-TRANSACTION-SIZE 16096 = _o2ct-assert
    O2CODE-WORKSPACE-SIZE 14760 = _o2ct-assert
    O2CODE-ISSUER-OPTIONAL 0= _o2ct-assert
    O2CODE-ISSUER-REQUIRED -1 = _o2ct-assert

    _o2ct-object O2CODE-TRANSACTION-SIZE 0xA5 FILL
    _o2ct-fresh
    O2CODE-PHASE-EMPTY _o2ct-phase?
    _o2ct-object O2CODE-ERROR@
    O2CODE-S-PHASE _o2ct-status
    2DROP 2DROP
    _o2ct-object _O2C.BINDING
    O2CODE-TRANSACTION-SIZE _O2C-BINDING-OFF -
    _o2ct-zero? _o2ct-assert

    0 O2CODE-INIT? O2CODE-S-INVALID _o2ct-status
    _o2ct-object 1+ O2CODE-INIT?
    O2CODE-S-INVALID _o2ct-status
    _o2ct-stack ;

: _o2ct-prepare-required  ( -- status )
    _o2ct-binding _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work O2CODE-PREPARE ;

: _o2ct-prepare-optional-b  ( -- status )
    _o2ct-binding _o2ct-issuer O2CODE-ISSUER-OPTIONAL
    _o2ct-object-b _o2ct-work-b O2CODE-PREPARE ;

: _o2ct-test-prepare-entropy-and-pkce  ( -- )
    _o2ct-fresh
    _o2ct-fill-work
    _o2ct-prepare-required O2CODE-S-OK _o2ct-status
    O2CODE-PHASE-PREPARED _o2ct-phase?
    _o2ct-work-zero? _o2ct-assert

    _o2ct-object _O2C.BINDING-U @
    _o2ct-binding NIP = _o2ct-assert
    _o2ct-object _O2C.BINDING
    _o2ct-object _O2C.BINDING-U @
    _o2ct-binding COMPARE 0= _o2ct-assert
    _o2ct-object _O2C.ISSUER-U @
    _o2ct-issuer NIP = _o2ct-assert
    _o2ct-object _O2C.ISSUER
    _o2ct-object _O2C.ISSUER-U @
    _o2ct-issuer COMPARE 0= _o2ct-assert
    _o2ct-object _O2C.ISSUER-REQUIRED @
    O2CODE-ISSUER-REQUIRED = _o2ct-assert

    \ State is the canonical unpadded Base64url form of 256 hardware bits.
    _o2ct-object _O2C.STATE O2CODE-STATE-SIZE
    _o2ct-decoded-raw 32 JOSE-B64URL-DECODE
    JOSE-B64URL-S-OK _o2ct-status
    32 = _o2ct-assert

    \ The verifier is independently generated and its S256 value matches.
    _o2ct-object _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    OAUTH2-PKCE-VERIFIER-VALID? _o2ct-assert
    _o2ct-object _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    _o2ct-recomputed O2CODE-CHALLENGE-SIZE
    _o2ct-pkce-work OAUTH2-PKCE-S256
    OAUTH2-PKCE-S-OK _o2ct-status
    O2CODE-CHALLENGE-SIZE = _o2ct-assert
    _o2ct-recomputed _o2ct-object _O2C.CHALLENGE
    O2CODE-CHALLENGE-SIZE _o2ct-bytes= _o2ct-assert
    _o2ct-object _O2C.STATE
    _o2ct-object _O2C.VERIFIER
    O2CODE-STATE-SIZE _o2ct-bytes= 0= _o2ct-assert
    _o2ct-pkce-work OAUTH2-PKCE-WORKSPACE-SIZE
    _o2ct-zero? _o2ct-assert

    _o2ct-object _O2C.STATE _o2ct-state-copy
    O2CODE-STATE-SIZE MOVE
    _o2ct-object _O2C.VERIFIER _o2ct-verifier-copy
    O2CODE-VERIFIER-SIZE MOVE

    \ A second transaction obtains fresh entropy for both opaque values.
    _o2ct-object-b O2CODE-INIT?
    O2CODE-S-OK _o2ct-status
    _o2ct-fill-work-b
    _o2ct-prepare-optional-b O2CODE-S-OK _o2ct-status
    _o2ct-work-b-zero? _o2ct-assert
    _o2ct-object-b _O2C.PHASE @
    O2CODE-PHASE-PREPARED = _o2ct-assert
    _o2ct-object-b _O2C.ISSUER-REQUIRED @
    O2CODE-ISSUER-OPTIONAL = _o2ct-assert
    _o2ct-object-b _O2C.STATE _o2ct-state-copy
    O2CODE-STATE-SIZE _o2ct-bytes= 0= _o2ct-assert
    _o2ct-object-b _O2C.VERIFIER _o2ct-verifier-copy
    O2CODE-VERIFIER-SIZE _o2ct-bytes= 0= _o2ct-assert
    _o2ct-stack ;

: _o2ct-prepare-throw
  \ ( binding binding-u issuer issuer-u policy object workspace -- status )
    -817 THROW ;

: _o2ct-test-prepare-preflight-and-throw  ( -- )
    _o2ct-fresh
    _o2ct-object-copy!
    _o2ct-fill-work
    _o2ct-binding _o2ct-issuer 1
    _o2ct-object _o2ct-work O2CODE-PREPARE
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-object-copy!
    0 0 _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work O2CODE-PREPARE
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-object-copy!
    _o2ct-query O2CODE-BINDING-CAPACITY 1+
    _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work O2CODE-PREPARE
    O2CODE-S-CAPACITY _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-object-copy!
    _o2ct-binding S" https://bad issuer"
    O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work O2CODE-PREPARE
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    \ Input/object and object/workspace alias are rejected before mutation.
    _o2ct-object-copy!
    _o2ct-object 1 _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work O2CODE-PREPARE
    O2CODE-S-ALIAS _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-object-copy!
    _o2ct-binding _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-object O2CODE-PREPARE
    O2CODE-S-ALIAS _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-object-copy!
    _o2ct-binding _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work 1+ O2CODE-PREPARE
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    \ An admitted internal THROW leaves the object atomic and wipes scratch.
    _o2ct-object-copy!
    _o2ct-binding _o2ct-issuer O2CODE-ISSUER-REQUIRED
    _o2ct-object _o2ct-work
    ['] _o2ct-prepare-throw _O2C-PREPARE-CALL
    O2CODE-S-INTERNAL _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-zero? _o2ct-assert

    \ A completed attempt cannot be prepared again.
    _o2ct-fill-work
    _o2ct-prepare-required O2CODE-S-OK _o2ct-status
    _o2ct-work-zero? _o2ct-assert
    _o2ct-fill-work
    _o2ct-object-copy!
    _o2ct-prepare-required O2CODE-S-PHASE _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert
    _o2ct-stack ;

: _o2ct-capture-binding  ( address length -- )
    DUP _o2ct-seen-binding-u !
    2DUP _o2ct-object _O2C.BINDING
    _o2ct-object _O2C.BINDING-U @ COMPARE
    0= _o2ct-assert
    _o2ct-binding-copy SWAP MOVE ;

: _o2ct-capture-state  ( address length -- )
    DUP _o2ct-seen-state-u !
    2DUP _o2ct-object _O2C.STATE O2CODE-STATE-SIZE
    COMPARE 0= _o2ct-assert
    _o2ct-state-copy SWAP MOVE ;

: _o2ct-capture-challenge  ( address length -- )
    DUP _o2ct-seen-challenge-u !
    2DUP _o2ct-object _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE
    COMPARE 0= _o2ct-assert
    _o2ct-challenge-copy SWAP MOVE ;

: _o2ct-capture-request-uri  ( address length -- )
    DUP _o2ct-seen-request-uri-u !
    2DUP _o2ct-object _O2C.REQUEST-URI
    _o2ct-object _O2C.REQUEST-URI-U @ COMPARE
    0= _o2ct-assert
    _o2ct-request-uri-copy SWAP MOVE ;

: _o2ct-callback-never
  \ ( context binding binding-u state state-u challenge challenge-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _O2C-DROP7
    0 _o2ct-assert
    0 ;

: _o2ct-par-callback
  \ ( context binding binding-u state state-u challenge challenge-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _o2ct-capture-challenge
    _o2ct-capture-state
    _o2ct-capture-binding
    DUP _o2ct-object = _o2ct-assert
    DUP O2CODE-PHASE@
    O2CODE-S-OK _o2ct-status
    O2CODE-PHASE-PREPARED = _o2ct-assert
    DUP _O2C.BORROWED @ -1 = _o2ct-assert
    DUP O2CODE-CLEAR? O2CODE-S-BUSY _o2ct-status
    ['] _o2ct-callback-never 0 2 PICK
    O2CODE-WITH-PAR O2CODE-S-BUSY _o2ct-status
    DROP 701 ;

: _o2ct-par-throw
  \ ( context binding binding-u state state-u challenge challenge-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _O2C-DROP7
    -818 THROW ;

: _o2ct-par-extra
  \ ( context binding binding-u state state-u challenge challenge-u
  \   -- callback-status extra )
    1 _o2ct-callback-count +!
    _O2C-DROP7
    701 702 ;

: _o2ct-start-prepared  ( -- )
    _o2ct-fresh
    _o2ct-fill-work
    _o2ct-prepare-required O2CODE-S-OK _o2ct-status
    _o2ct-work-zero? _o2ct-assert ;

: _o2ct-test-par-borrow  ( -- )
    _o2ct-start-prepared
    0 _o2ct-callback-count !
    ['] _o2ct-par-callback _o2ct-object _o2ct-object
    O2CODE-WITH-PAR 701 = _o2ct-assert
    _o2ct-callback-count @ 1 = _o2ct-assert
    O2CODE-PHASE-PREPARED _o2ct-phase?
    _o2ct-object _O2C.BORROWED @ 0= _o2ct-assert
    _o2ct-seen-binding-u @ _o2ct-binding NIP =
    _o2ct-assert
    _o2ct-seen-state-u @ O2CODE-STATE-SIZE =
    _o2ct-assert
    _o2ct-seen-challenge-u @ O2CODE-CHALLENGE-SIZE =
    _o2ct-assert

    \ PAR fields are a repeatable borrow until ACCEPT-PAR succeeds.
    ['] _o2ct-par-callback _o2ct-object _o2ct-object
    O2CODE-WITH-PAR 701 = _o2ct-assert
    _o2ct-callback-count @ 2 = _o2ct-assert
    O2CODE-PHASE-PREPARED _o2ct-phase?

    ['] _o2ct-par-throw 0 _o2ct-object
    O2CODE-WITH-PAR O2CODE-S-CALLBACK _o2ct-status
    _o2ct-callback-count @ 3 = _o2ct-assert
    _o2ct-object _O2C.BORROWED @ 0= _o2ct-assert
    O2CODE-PHASE-PREPARED _o2ct-phase?

    ['] _o2ct-par-extra 0 _o2ct-object
    O2CODE-WITH-PAR O2CODE-S-CALLBACK _o2ct-status
    _o2ct-callback-count @ 4 = _o2ct-assert
    _o2ct-object _O2C.BORROWED @ 0= _o2ct-assert
    O2CODE-PHASE-PREPARED _o2ct-phase?
    _o2ct-stack ;

: _o2ct-test-accept-par  ( -- )
    _o2ct-start-prepared
    _o2ct-object-copy!
    _o2ct-request-uri 0 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-request-uri O2CODE-MAX-PAR-EXPIRES-IN 1+
    100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-request-uri 1 -1 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-request-uri 1 _O2C-CELL-MAX
    _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-OVERFLOW _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    31 _o2ct-query C!
    _o2ct-query 1 1 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-query O2CODE-REQUEST-URI-CAPACITY 1+
    1 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-CAPACITY _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-object _O2C.BINDING 1
    1 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-ALIAS _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-request-uri 60 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-OK _o2ct-status
    O2CODE-PHASE-PAR-READY _o2ct-phase?
    _o2ct-object _O2C.REQUEST-URI
    _o2ct-object _O2C.REQUEST-URI-U @
    _o2ct-request-uri COMPARE 0= _o2ct-assert
    _o2ct-object _O2C.DEADLINE @ 160 = _o2ct-assert

    _o2ct-object-copy!
    _o2ct-request-uri 1 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-PHASE _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-stack ;

: _o2ct-launch-callback
  \ ( context binding binding-u request-uri request-uri-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _o2ct-capture-request-uri
    _o2ct-capture-binding
    DUP _o2ct-object = _o2ct-assert
    DUP O2CODE-PHASE@
    O2CODE-S-OK _o2ct-status
    O2CODE-PHASE-AWAITING = _o2ct-assert
    DUP _O2C.BORROWED @ -1 = _o2ct-assert
    DUP O2CODE-CLEAR? O2CODE-S-BUSY _o2ct-status
    ['] _o2ct-callback-never 0 0 3 PICK
    O2CODE-WITH-LAUNCH O2CODE-S-BUSY _o2ct-status
    DROP 702 ;

: _o2ct-launch-throw
  \ ( context binding binding-u request-uri request-uri-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _O2C-DROP5
    -819 THROW ;

: _o2ct-launch-extra
  \ ( context binding binding-u request-uri request-uri-u
  \   -- callback-status extra )
    1 _o2ct-callback-count +!
    _O2C-DROP5
    702 703 ;

: _o2ct-start-par-ready  ( -- )
    _o2ct-start-prepared
    _o2ct-request-uri 60 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-OK _o2ct-status ;

: _o2ct-assert-launch-finished  ( -- )
    O2CODE-PHASE-AWAITING _o2ct-phase?
    _o2ct-object _O2C.BORROWED @ 0= _o2ct-assert
    _o2ct-object _O2C.REQUEST-URI
    O2CODE-REQUEST-URI-CAPACITY _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.REQUEST-URI-U @ 0= _o2ct-assert
    _o2ct-object _O2C.DEADLINE @ 160 = _o2ct-assert ;

: _o2ct-test-launch-one-shot  ( -- )
    _o2ct-start-par-ready
    _o2ct-object-copy!
    ['] _o2ct-launch-callback _o2ct-object 160 _o2ct-object
    O2CODE-WITH-LAUNCH O2CODE-S-EXPIRED _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    0 _o2ct-callback-count !
    ['] _o2ct-launch-callback _o2ct-object 159 _o2ct-object
    O2CODE-WITH-LAUNCH 702 = _o2ct-assert
    _o2ct-callback-count @ 1 = _o2ct-assert
    _o2ct-seen-binding-u @ _o2ct-binding NIP =
    _o2ct-assert
    _o2ct-seen-request-uri-u @ _o2ct-request-uri NIP =
    _o2ct-assert
    _o2ct-assert-launch-finished

    ['] _o2ct-launch-callback 0 159 _o2ct-object
    O2CODE-WITH-LAUNCH O2CODE-S-PHASE _o2ct-status
    _o2ct-callback-count @ 1 = _o2ct-assert

    \ A thrown callback still consumes and wipes the launch material.
    _o2ct-start-par-ready
    ['] _o2ct-launch-throw 0 100 _o2ct-object
    O2CODE-WITH-LAUNCH O2CODE-S-CALLBACK _o2ct-status
    _o2ct-assert-launch-finished

    \ Stack-contract failure is treated identically and remains one-shot.
    _o2ct-start-par-ready
    ['] _o2ct-launch-extra 0 100 _o2ct-object
    O2CODE-WITH-LAUNCH O2CODE-S-CALLBACK _o2ct-status
    _o2ct-assert-launch-finished
    _o2ct-stack ;

: _o2ct-launch-ok
  \ ( context binding binding-u request-uri request-uri-u
  \   -- callback-status )
    _O2C-DROP5 704 ;

: _o2ct-start-awaiting  ( -- )
    _o2ct-start-par-ready
    ['] _o2ct-launch-ok 0 100 _o2ct-object
    O2CODE-WITH-LAUNCH 704 = _o2ct-assert
    O2CODE-PHASE-AWAITING _o2ct-phase? ;

: _o2ct-start-awaiting-optional  ( -- )
    _o2ct-fresh
    _o2ct-fill-work
    _o2ct-binding _o2ct-issuer O2CODE-ISSUER-OPTIONAL
    _o2ct-object _o2ct-work O2CODE-PREPARE
    O2CODE-S-OK _o2ct-status
    _o2ct-request-uri 60 100 _o2ct-object O2CODE-ACCEPT-PAR
    O2CODE-S-OK _o2ct-status
    ['] _o2ct-launch-ok 0 100 _o2ct-object
    O2CODE-WITH-LAUNCH 704 = _o2ct-assert ;

: _o2ct-accept-query  ( -- status )
    _o2ct-query-source _o2ct-object _o2ct-work
    O2CODE-ACCEPT-CALLBACK ;

: _o2ct-expect-awaiting-rejection  ( expected-status -- )
    >R
    _o2ct-fill-work
    _o2ct-accept-query R> _o2ct-status
    _o2ct-work-zero? _o2ct-assert
    _o2ct-object-unchanged? _o2ct-assert
    O2CODE-PHASE-AWAITING _o2ct-phase? ;

: _o2ct-test-callback-rejections-and-success  ( -- )
    _o2ct-start-awaiting
    _o2ct-object-copy!

    _o2ct-build-malformed-escape
    O2CODE-S-ENCODING _o2ct-expect-awaiting-rejection
    _o2ct-build-decoded-duplicate
    O2CODE-S-DUPLICATE _o2ct-expect-awaiting-rejection
    _o2ct-build-unknown-decoded-duplicate
    O2CODE-S-DUPLICATE _o2ct-expect-awaiting-rejection
    _o2ct-build-state-mismatch
    O2CODE-S-STATE _o2ct-expect-awaiting-rejection
    _o2ct-build-issuer-mismatch
    O2CODE-S-ISSUER _o2ct-expect-awaiting-rejection
    _o2ct-build-success-without-issuer
    O2CODE-S-ISSUER _o2ct-expect-awaiting-rejection
    _o2ct-build-missing-state
    O2CODE-S-MISSING _o2ct-expect-awaiting-rejection
    _o2ct-build-code-and-error
    O2CODE-S-RESPONSE _o2ct-expect-awaiting-rejection
    _o2ct-build-missing-result
    O2CODE-S-RESPONSE _o2ct-expect-awaiting-rejection

    \ A later valid response succeeds after every rejected callback.
    _o2ct-build-success
    _o2ct-fill-work
    _o2ct-accept-query O2CODE-S-OK _o2ct-status
    _o2ct-work-zero? _o2ct-assert
    O2CODE-PHASE-CODE-READY _o2ct-phase?
    _o2ct-object _O2C.CODE
    _o2ct-object _O2C.CODE-U @
    S" opaque-authorization+code"
    COMPARE 0= _o2ct-assert

    \ Terminal callback acceptance is not repeatable and is preflight-only.
    _o2ct-object-copy!
    _o2ct-fill-work
    _o2ct-accept-query O2CODE-S-PHASE _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert
    _o2ct-stack ;

: _o2ct-test-issuer-optional  ( -- )
    _o2ct-start-awaiting-optional
    _o2ct-object-copy!
    _o2ct-build-issuer-mismatch
    O2CODE-S-ISSUER _o2ct-expect-awaiting-rejection

    _o2ct-build-success-without-issuer
    _o2ct-fill-work
    _o2ct-accept-query O2CODE-S-OK _o2ct-status
    _o2ct-work-zero? _o2ct-assert
    O2CODE-PHASE-CODE-READY _o2ct-phase?
    _o2ct-object _O2C.CODE
    _o2ct-object _O2C.CODE-U @
    S" issuer-optional" COMPARE 0= _o2ct-assert
    _o2ct-stack ;

: _o2ct-test-denial-diagnostics  ( -- )
    _o2ct-start-awaiting
    _o2ct-build-denial
    _o2ct-fill-work
    _o2ct-accept-query O2CODE-S-DENIED _o2ct-status
    _o2ct-work-zero? _o2ct-assert
    O2CODE-PHASE-DENIED _o2ct-phase?
    _o2ct-object O2CODE-ERROR@
    O2CODE-S-OK _o2ct-status
    S" Owner said no" COMPARE 0= _o2ct-assert
    S" access_denied" COMPARE 0= _o2ct-assert

    _o2ct-object _O2C.STATE O2CODE-STATE-SIZE
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.CODE O2CODE-CODE-CAPACITY
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.CODE-U @ 0= _o2ct-assert
    ['] _o2ct-callback-never 0 _o2ct-object
    O2CODE-WITH-GRANT O2CODE-S-PHASE _o2ct-status

    _o2ct-object-copy!
    _o2ct-fill-work
    _o2ct-accept-query O2CODE-S-PHASE _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert
    _o2ct-stack ;

: _o2ct-callback-operation-throw
  ( query query-u object workspace -- status )
    -820 THROW ;

: _o2ct-test-callback-geometry-and-throw  ( -- )
    _o2ct-start-awaiting
    _o2ct-build-success
    _o2ct-object-copy!
    _o2ct-fill-work

    _o2ct-query O2CODE-CALLBACK-QUERY-CAPACITY 1+
    _o2ct-object _o2ct-work O2CODE-ACCEPT-CALLBACK
    O2CODE-S-CAPACITY _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-work 1 _o2ct-object _o2ct-work
    O2CODE-ACCEPT-CALLBACK O2CODE-S-ALIAS _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-object _O2C.BINDING 1
    _o2ct-object _o2ct-work O2CODE-ACCEPT-CALLBACK
    O2CODE-S-ALIAS _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    _o2ct-query-source _o2ct-object _o2ct-object
    O2CODE-ACCEPT-CALLBACK O2CODE-S-ALIAS _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    _o2ct-query-source _o2ct-object _o2ct-work 1+
    O2CODE-ACCEPT-CALLBACK O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-filled? _o2ct-assert

    \ An admitted parser THROW is atomic and clears all transient state.
    _o2ct-query-source _o2ct-object _o2ct-work
    ['] _o2ct-callback-operation-throw _O2C-CALLBACK-CALL
    O2CODE-S-INTERNAL _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert
    _o2ct-work-zero? _o2ct-assert
    O2CODE-PHASE-AWAITING _o2ct-phase?
    _o2ct-stack ;

: _o2ct-capture-code  ( address length -- )
    DUP _o2ct-seen-code-u !
    2DUP _o2ct-object _O2C.CODE
    _o2ct-object _O2C.CODE-U @ COMPARE 0= _o2ct-assert
    _o2ct-code-copy SWAP MOVE ;

: _o2ct-capture-verifier  ( address length -- )
    DUP _o2ct-seen-verifier-u !
    2DUP _o2ct-object _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    COMPARE 0= _o2ct-assert
    _o2ct-verifier-copy SWAP MOVE ;

: _o2ct-grant-callback
  \ ( context binding binding-u code code-u verifier verifier-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _o2ct-capture-verifier
    _o2ct-capture-code
    _o2ct-capture-binding
    DUP _o2ct-object = _o2ct-assert
    DUP O2CODE-PHASE@
    O2CODE-S-OK _o2ct-status
    O2CODE-PHASE-SPENT = _o2ct-assert
    DUP _O2C.BORROWED @ -1 = _o2ct-assert
    DUP O2CODE-CLEAR? O2CODE-S-BUSY _o2ct-status
    ['] _o2ct-callback-never 0 2 PICK
    O2CODE-WITH-GRANT O2CODE-S-BUSY _o2ct-status
    DROP 703 ;

: _o2ct-grant-throw
  \ ( context binding binding-u code code-u verifier verifier-u
  \   -- callback-status )
    1 _o2ct-callback-count +!
    _O2C-DROP7
    -821 THROW ;

: _o2ct-grant-extra
  \ ( context binding binding-u code code-u verifier verifier-u
  \   -- callback-status extra )
    1 _o2ct-callback-count +!
    _O2C-DROP7
    703 704 ;

: _o2ct-start-code-ready  ( -- )
    _o2ct-start-awaiting
    _o2ct-build-success
    _o2ct-fill-work
    _o2ct-accept-query O2CODE-S-OK _o2ct-status
    _o2ct-work-zero? _o2ct-assert ;

: _o2ct-assert-grant-finished  ( -- )
    O2CODE-PHASE-SPENT _o2ct-phase?
    _o2ct-object _O2C.BORROWED @ 0= _o2ct-assert
    _o2ct-object _O2C.STATE O2CODE-STATE-SIZE
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.VERIFIER O2CODE-VERIFIER-SIZE
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.CHALLENGE O2CODE-CHALLENGE-SIZE
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.CODE O2CODE-CODE-CAPACITY
    _o2ct-zero? _o2ct-assert
    _o2ct-object _O2C.CODE-U @ 0= _o2ct-assert ;

: _o2ct-test-grant-one-shot  ( -- )
    _o2ct-start-code-ready
    _o2ct-object-copy!
    0 0 _o2ct-object O2CODE-WITH-GRANT
    O2CODE-S-INVALID _o2ct-status
    _o2ct-object-unchanged? _o2ct-assert

    0 _o2ct-callback-count !
    ['] _o2ct-grant-callback _o2ct-object _o2ct-object
    O2CODE-WITH-GRANT 703 = _o2ct-assert
    _o2ct-callback-count @ 1 = _o2ct-assert
    _o2ct-seen-binding-u @ _o2ct-binding NIP =
    _o2ct-assert
    _o2ct-seen-code-u @ S" opaque-authorization+code" NIP =
    _o2ct-assert
    _o2ct-seen-verifier-u @ O2CODE-VERIFIER-SIZE =
    _o2ct-assert
    _o2ct-code-copy _o2ct-seen-code-u @
    S" opaque-authorization+code" COMPARE 0= _o2ct-assert
    _o2ct-verifier-copy O2CODE-VERIFIER-SIZE
    OAUTH2-PKCE-VERIFIER-VALID? _o2ct-assert
    _o2ct-assert-grant-finished

    ['] _o2ct-grant-callback 0 _o2ct-object
    O2CODE-WITH-GRANT O2CODE-S-PHASE _o2ct-status
    _o2ct-callback-count @ 1 = _o2ct-assert

    \ THROW and stack-contract failure still consume and wipe the grant.
    _o2ct-start-code-ready
    ['] _o2ct-grant-throw 0 _o2ct-object
    O2CODE-WITH-GRANT O2CODE-S-CALLBACK _o2ct-status
    _o2ct-assert-grant-finished

    _o2ct-start-code-ready
    ['] _o2ct-grant-extra 0 _o2ct-object
    O2CODE-WITH-GRANT O2CODE-S-CALLBACK _o2ct-status
    _o2ct-assert-grant-finished
    _o2ct-stack ;

: _O2CT-RUN  ( -- )
    0 _o2ct-checks !
    0 _o2ct-fails !
    0 _o2ct-callback-count !
    DEPTH _o2ct-depth !

    _o2ct-test-vocabulary-and-init
    ." OAUTH2 AUTHORIZATION CODE GROUP LIFECYCLE" CR TX-FLUSH
    _o2ct-test-prepare-entropy-and-pkce
    _o2ct-test-prepare-preflight-and-throw
    ." OAUTH2 AUTHORIZATION CODE GROUP PREPARE" CR TX-FLUSH
    _o2ct-test-par-borrow
    _o2ct-test-accept-par
    _o2ct-test-launch-one-shot
    ." OAUTH2 AUTHORIZATION CODE GROUP PAR" CR TX-FLUSH
    _o2ct-test-callback-rejections-and-success
    _o2ct-test-issuer-optional
    _o2ct-test-denial-diagnostics
    _o2ct-test-callback-geometry-and-throw
    ." OAUTH2 AUTHORIZATION CODE GROUP RESPONSE" CR TX-FLUSH
    _o2ct-test-grant-one-shot
    ." OAUTH2 AUTHORIZATION CODE GROUP GRANT" CR TX-FLUSH

    _o2ct-stack
    _o2ct-fails @ IF
        ." OAUTH2 AUTHORIZATION CODE FAIL "
        _o2ct-fails @ . ." / " _o2ct-checks @ . CR
    ELSE
        ." OAUTH2 AUTHORIZATION CODE PASS "
        _o2ct-checks @ . CR
    THEN
    TX-FLUSH ;
