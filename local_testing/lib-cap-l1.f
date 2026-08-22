\ =====================================================================
\  Focused Checkpoint-1 Library capability and owner contracts
\ =====================================================================
\  This fixture enters through one real Library applet activation.  It calls
\  the five checked-in descriptors with caller-owned CBR/CV graphs, verifies
\  exact replay and scoped-read behavior, and then proves that ordinary UI
\  reload observes capability-created authority.  The last phase exercises
\  the canonical 65,536-byte read window and its 65,537-byte rejection at the
\  service boundary without manufacturing a second owner.  A separate focused
\  runner regenerates the query/read IVJSON maxima and exercises the
\  caller-bounded full-result decoder without provisioning Library storage.
\ =====================================================================

PROVIDED akashic-library-capability-l1-contracts

0xFFFFFF0000000006 CONSTANT _LC1-uart-flush

: _LC1-flush  ( -- )
    0 _LC1-uart-flush C! ;

." LIBRARY CAPABILITY L1 LOAD START" CR _LC1-flush

VARIABLE _LC1-checks
VARIABLE _LC1-fails
VARIABLE _LC1-depth
VARIABLE _LC1-outer-depth
VARIABLE _LC1-instance
VARIABLE _LC1-request
VARIABLE _LC1-cap
VARIABLE _LC1-actual
VARIABLE _LC1-before-revision
VARIABLE _LC1-logical
VARIABLE _LC1-collection-logical
VARIABLE _LC1-collection-revision
VARIABLE _LC1-expected
VARIABLE _LC1-source
VARIABLE _LC1-count
VARIABLE _LC1-node
VARIABLE _LC1-row
VARIABLE _LC1-direct-id
VARIABLE _LC1-direct-operation
VARIABLE _LC1-direct-u

CREATE _LC1-desc APP-DESC ALLOT
CREATE _LC1-ref0 RREF-SIZE ALLOT
CREATE _LC1-ref1 RREF-SIZE ALLOT
CREATE _LC1-document-id RID-SIZE ALLOT
CREATE _LC1-collection-id RID-SIZE ALLOT
CREATE _LC1-collection-seal SHA3-256-HEX-LEN ALLOT
CREATE _LC1-bad-seal SHA3-256-HEX-LEN ALLOT

CREATE _LC1-boundary-document-id RID-SIZE ALLOT
CREATE _LC1-oversize-document-id RID-SIZE ALLOT
CREATE _LC1-boundary-members RID-SIZE 2 * ALLOT
CREATE _LC1-boundary-collection LIBPA-COLLECTION-SIZE ALLOT
CREATE _LC1-oversize-current LIB-ENTRY-SIZE ALLOT
CREATE _LC1-oversize-next LIB-ENTRY-SIZE ALLOT
CREATE _LC1-oversize-result LIB-ENTRY-SIZE ALLOT
CREATE _LC1-oversize-content LIB-CONTENT-SIZE ALLOT
CREATE _LC1-oversize-replace-request
    LIBRARY-DOCUMENT-REPLACE-REQUEST-SIZE ALLOT
CREATE _LC1-oversize-target LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LC1-oversize-retained-facts
    LIBRARY-RETAINED-CONTENT-FACTS-SIZE ALLOT
CREATE _LC1-oversize-restore-request
    LIBRARY-DOCUMENT-RESTORE-REQUEST-SIZE ALLOT
CREATE _LC1-primary-collection LIBPA-COLLECTION-SIZE ALLOT
CREATE _LC1-primary-collection-read-request
    LIBRARY-COLLECTION-READ-REQUEST-SIZE ALLOT
CREATE _LC1-collection-next LIBPA-COLLECTION-SIZE ALLOT
CREATE _LC1-collection-replace-result LIBPA-COLLECTION-SIZE ALLOT
CREATE _LC1-collection-replace-request
    LIBRARY-COLLECTION-WRITE-REQUEST-SIZE ALLOT
CREATE _LC1-primary-current LIB-ENTRY-SIZE ALLOT
CREATE _LC1-tombstone-next LIB-ENTRY-SIZE ALLOT
CREATE _LC1-tombstone-result LIB-ENTRY-SIZE ALLOT
CREATE _LC1-tombstone-request LIBRARY-DOCUMENT-REPLACE-REQUEST-SIZE ALLOT

LIB-CONTENT-WINDOW-MAX 1+ CONSTANT _LC1-large-u
_LC1-large-u XBUF _LC1-large
43758 XBUF _LC1-canonical
\ SHA3-256 of 65,537 "A" bytes with offsets 32767..32769 replaced by "XYZ".
\ This is the same deterministic retained-content fixture used by lib-rest-l12.
CREATE _LC1-large-digest
0xA6 C, 0xAB C, 0x07 C, 0x22 C, 0xE8 C, 0xCC C, 0x7A C, 0x0E C,
0x58 C, 0xE0 C, 0xCA C, 0x12 C, 0xB6 C, 0x53 C, 0xC0 C, 0x65 C,
0x10 C, 0x12 C, 0xD0 C, 0x57 C, 0x38 C, 0xF7 C, 0x3C C, 0x4A C,
0x55 C, 0xA0 C, 0xA5 C, 0x4E C, 0xC8 C, 0x05 C, 0x55 C, 0xD0 C,
32 CONSTANT _LC1-primary-content-u

VARIABLE _LC1-owner-adapter
VARIABLE _LC1-owner-index
VARIABLE _LC1-boundary-old-vfs
VARIABLE _LC1-boundary-arena
VARIABLE _LC1-boundary-vfs
VARIABLE _LC1-boundary-ior

: _LC1-assert  ( flag -- )
    1 _LC1-checks +!
    0= IF
        1 _LC1-fails +!
        ." LIBRARY CAPABILITY L1 ASSERT " _LC1-checks @ . CR
        _LC1-flush
    THEN ;

: _LC1-stack  ( -- )
    DEPTH DUP _LC1-depth @ <> IF
        ." LIBRARY CAPABILITY L1 STACK "
        _LC1-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LC1-depth @ = _LC1-assert ;

: _LC1-outer-stack  ( -- )
    DEPTH DUP _LC1-outer-depth @ <> IF
        ." LIBRARY CAPABILITY L1 OUTER STACK "
        _LC1-outer-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LC1-outer-depth @ = _LC1-assert ;

: _LC1-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY CAPABILITY L1 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LC1-assert ;

: _LC1-ok  ( status -- ) 0= _LC1-assert ;

: _LC1-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _LC1-id!  ( value rid -- )
    DUP RID-CLEAR ! ;

: _LC1-lower-hex?  ( c -- flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] a >= SWAP [CHAR] f <= AND ;

: _LC1-h64?  ( value -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-STRING <> IF DROP 0 EXIT THEN
    DUP CV-LEN@ SHA3-256-HEX-LEN <> IF DROP 0 EXIT THEN
    CV-DATA@ DUP 0= IF DROP 0 EXIT THEN
    SHA3-256-HEX-LEN 0 ?DO
        DUP I + C@ _LC1-lower-hex? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _LC1-string=  ( value expected-a expected-u -- flag )
    2>R
    DUP 0= IF DROP 2R> 2DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-STRING <> IF DROP 2R> 2DROP 0 EXIT THEN
    DUP CV-DATA@ SWAP CV-LEN@ 2R> STR-STR= ;

: _LC1-result-field  ( key-a key-u -- value|0 )
    _LC1-request @ CBR.RESULT CV-MAP-FIND ;

: _LC1-int-field  ( key-a key-u -- n )
    _LC1-result-field DUP 0= IF
        DROP 0 _LC1-assert 0 EXIT
    THEN
    DUP CV-TYPE@ CV-T-INT = _LC1-assert
    CV-DATA@ ;

: _LC1-bool-field  ( key-a key-u -- flag )
    _LC1-result-field DUP 0= IF
        DROP 0 _LC1-assert 0 EXIT
    THEN
    DUP CV-TYPE@ CV-T-BOOL = _LC1-assert
    CV-DATA@ ;

: _LC1-r0@  ( value destination -- flag )
    2DUP IRES-RREF@ IRES-S-OK <> IF 2DROP 0 EXIT THEN
    NIP
    DUP RREF.REVISION @ 0=
    SWAP RREF.ID RID-PRESENT? AND ;

: _LC1-result-free  ( -- )
    _LC1-request @ CBR.RESULT CV-FREE ;

: _LC1-args-free  ( -- )
    _LC1-request @ CBR.ARGS CV-FREE ;

: _LC1-args-slot  ( key-a key-u index -- child|0 )
    _LC1-request @ CBR.ARGS CV-MAP-SLOT!
    DUP 0= _LC1-assert DROP ;

: _LC1-resource!  ( rid value -- )
    >R
    _LC1-ref0 RREF-INIT
    _LC1-ref0 RREF.ID RID-COPY
    _LC1-ref0 R> IRES-RREF! IRES-S-OK = _LC1-assert ;

: _LC1-invocation!  ( value -- )
    _LC1-request @ CBR.INVOCATION-ID _LC1-id! ;

: _LC1-call  ( capability -- bus-status )
    _LC1-cap !
    _LC1-result-free
    _LC1-request @ CBR-ERROR-CLEAR
    _LC1-cap @ _LC1-request @ CBR.CAP !
    _LC1-request @ CBR.ARGS
        _LC1-cap @ CAP.IN-SCHEMA @ CS-VALIDATE-DEEP
        0= _LC1-assert
    \ ARGS and RESULT are inline CV roots owned by the caller's CBR.  Each
    \ root must overlap that request while their separately owned graphs stay
    \ disjoint from one another.
    _LC1-request @ CBR-SIZE _LC1-request @ CBR.ARGS
        CV-OWNED-SPAN-OVERLAP? _LC1-assert
    _LC1-request @ CBR-ARGS-SEAL! CBUS-S-OK = _LC1-assert
    _LC1-instance @ CINST.REVISION @ _LC1-before-revision !
    _LC1-request @ _LC1-instance @
        _LC1-cap @ CAP.HANDLER-XT @ EXECUTE
        _LC1-actual !
    \ Direct handler entry must not usurp the request bus's revision owner.
    _LC1-instance @ CINST.REVISION @ _LC1-before-revision @ <> IF
        ." LIBRARY CAPABILITY L1 INSTANCE REVISION before/after "
        _LC1-before-revision @ . _LC1-instance @ CINST.REVISION @ . CR
        _LC1-flush
    THEN
    _LC1-instance @ CINST.REVISION @
        _LC1-before-revision @ = _LC1-assert
    _LC1-actual @ CBUS-RESULT-BEARING? IF
        _LC1-request @ CBR.RESULT
            _LC1-cap @ CAP.OUT-SCHEMA @ CS-VALIDATE-DEEP
            0= _LC1-assert
        _LC1-request @ CBR.ARGS _LC1-request @ CBR.RESULT
            CV-OWNED-GRAPHS-DISJOINT? _LC1-assert
        _LC1-request @ CBR-SIZE _LC1-request @ CBR.RESULT
            CV-OWNED-SPAN-OVERLAP? _LC1-assert
    THEN
    _LC1-actual @ ;

: _LC1-error  ( actual-bus expected-bus service-code -- )
    >R _LC1-status
    _LC1-request @ CBR.ERROR-CODE @ R> = _LC1-assert
    _LC1-request @ CBR.ERROR-U @ 0> _LC1-assert
    _LC1-request @ CBR.RESULT CV-TYPE@ CV-T-NULL = _LC1-assert
    _LC1-result-free ;

: _LC1-request-setup  ( -- )
    CBR-NEW DUP 0= _LC1-assert DROP
    DUP _LC1-request !
    CPRINC-COMPONENT OVER CBR.PRINCIPAL !
    CBR-F-APPROVED OVER CBR.FLAGS !
    _LC1-instance @ CINST.ID @ OVER CBR.TARGET-ID !
    _LC1-instance @ CINST.GENERATION @ SWAP CBR.TARGET-GEN ! ;

: _LC1-service-map  ( service-status expected-bus-status -- )
    _LC1-expected !
    DUP _LC1-source !
    _LC1-request @ CBR-ERROR-CLEAR
    _LC1-request @ _LCAP-SERVICE>CBUS
        _LC1-expected @ _LC1-status
    _LC1-request @ CBR.ERROR-CODE @ _LC1-source @ = _LC1-assert
    _LC1-request @ CBR.ERROR-U @ 0> _LC1-assert ;

: _LC1-service-error-map  ( -- )
    LIBRARY-SERVICE-S-INVALID CBUS-S-INVALID _LC1-service-map
    LIBRARY-SERVICE-S-BUSY CBUS-S-BUSY _LC1-service-map
    LIBRARY-SERVICE-S-ABSENT CBUS-S-NOT-FOUND _LC1-service-map
    LIBRARY-SERVICE-S-NOT-FOUND CBUS-S-NOT-FOUND _LC1-service-map
    LIBRARY-SERVICE-S-TOMBSTONED CBUS-S-NOT-FOUND _LC1-service-map
    LIBRARY-SERVICE-S-GONE CBUS-S-NOT-FOUND _LC1-service-map
    LIBRARY-SERVICE-S-CAPACITY CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-OUTPUT-CAPACITY CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-IO CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-CORRUPT CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-CONFLICT CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-UNCERTAIN CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-FAULT CBUS-S-FAILED _LC1-service-map
    LIBRARY-SERVICE-S-IDEMPOTENCY-MISMATCH
        CBUS-S-FAILED _LC1-service-map
    _LC1-stack ;

." LIBRARY CAPABILITY L1 SUPPORT READY" CR _LC1-flush

\ ---------------------------------------------------------------------
\ Owned input graphs
\ ---------------------------------------------------------------------

: _LC1-document-args  ( expected content-a content-u -- )
    _LC1-count ! _LC1-source ! _LC1-expected !
    _LC1-args-free
    4 _LC1-request @ CBR.ARGS CV-MAP! _LC1-ok
    S" expected_logical_generation" 0 _LC1-args-slot
        _LC1-expected @ SWAP CV-INT!
    S" title" 1 _LC1-args-slot
        S" Capability document" ROT CV-STRING! _LC1-ok
    S" media_type" 2 _LC1-args-slot
        S" text/plain" ROT CV-STRING! _LC1-ok
    S" content" 3 _LC1-args-slot
        _LC1-source @ _LC1-count @ ROT CV-STRING! _LC1-ok ;

: _LC1-collection-map  ( expected member-count -- list-value )
    _LC1-count ! _LC1-expected !
    _LC1-args-free
    3 _LC1-request @ CBR.ARGS CV-MAP! _LC1-ok
    S" expected_logical_generation" 0 _LC1-args-slot
        _LC1-expected @ SWAP CV-INT!
    S" title" 1 _LC1-args-slot
        S" Capability collection" ROT CV-STRING! _LC1-ok
    S" members" 2 _LC1-args-slot DUP _LC1-node !
    _LC1-count @ SWAP CV-LIST! _LC1-ok
    _LC1-node @ ;

: _LC1-collection-one  ( expected -- )
    1 _LC1-collection-map
    0 SWAP CV-LIST-NTH
        _LC1-document-id SWAP _LC1-resource! ;

: _LC1-collection-duplicate  ( expected -- )
    2 _LC1-collection-map _LC1-node !
    _LC1-document-id 0 _LC1-node @ CV-LIST-NTH _LC1-resource!
    _LC1-document-id 1 _LC1-node @ CV-LIST-NTH _LC1-resource! ;

: _LC1-query-args  ( collection-revision seal-a -- )
    _LC1-source ! _LC1-expected !
    _LC1-args-free
    5 _LC1-request @ CBR.ARGS CV-MAP! _LC1-ok
    S" collection" 0 _LC1-args-slot
        _LC1-collection-id SWAP _LC1-resource!
    S" collection_domain_revision" 1 _LC1-args-slot
        _LC1-expected @ SWAP CV-INT!
    S" request_digest" 2 _LC1-args-slot
        _LC1-source @ SHA3-256-HEX-LEN ROT CV-STRING! _LC1-ok
    S" after" 3 _LC1-args-slot CV-NULL!
    S" limit" 4 _LC1-args-slot 8 SWAP CV-INT! ;

: _LC1-read-args  ( collection-revision seal-a document-revision -- )
    _LC1-count ! _LC1-source ! _LC1-expected !
    _LC1-args-free
    5 _LC1-request @ CBR.ARGS CV-MAP! _LC1-ok
    S" collection" 0 _LC1-args-slot
        _LC1-collection-id SWAP _LC1-resource!
    S" collection_domain_revision" 1 _LC1-args-slot
        _LC1-expected @ SWAP CV-INT!
    S" request_digest" 2 _LC1-args-slot
        _LC1-source @ SHA3-256-HEX-LEN ROT CV-STRING! _LC1-ok
    S" resource" 3 _LC1-args-slot
        _LC1-document-id SWAP _LC1-resource!
    S" domain_revision" 4 _LC1-args-slot
        _LC1-count @ SWAP CV-INT! ;

: _LC1-bad-seal!  ( -- )
    _LC1-collection-seal _LC1-bad-seal SHA3-256-HEX-LEN MOVE
    _LC1-bad-seal C@ [CHAR] 0 = IF [CHAR] 1 ELSE [CHAR] 0 THEN
        _LC1-bad-seal C! ;

VARIABLE _LC1-canonical-expected

: _LC1-canonical-boundary  ( expected-length -- )
    _LC1-canonical-expected !
    _LC1-request @ CBR.ARGS _LC1-canonical _LC1-canonical-expected @
        IVJSON-TYPED-ENCODE
    DUP 0= _LC1-assert DROP
        _LC1-canonical-expected @ = _LC1-assert
    0xA5 _LC1-canonical _LC1-canonical-expected @ 1- + C!
    _LC1-request @ CBR.ARGS _LC1-canonical
        _LC1-canonical-expected @ 1-
        IVJSON-TYPED-ENCODE
    DUP IVJSON-E-CAPACITY = _LC1-assert DROP 0= _LC1-assert
    _LC1-canonical _LC1-canonical-expected @ 1- + C@
        0xA5 = _LC1-assert
    _LC1-request @ CBR-ARGS-SEAL! CBUS-S-OK = _LC1-assert
    _LC1-request @ CBR.ARGS-LEN @
        _LC1-canonical-expected @ = _LC1-assert
    _LC1-request @ CBR-ARGS-SEAL-MATCH? _LC1-assert ;

: _LC1-document-canonical-boundary  ( -- )
    _LC1-large 4096 1 FILL
    _LC1-args-free
    4 _LC1-request @ CBR.ARGS CV-MAP! _LC1-ok
    S" expected_logical_generation" 0 _LC1-args-slot
        0x7FFFFFFFFFFFFFFF SWAP CV-INT!
    S" title" 1 _LC1-args-slot
        _LC1-large 128 ROT CV-STRING! _LC1-ok
    S" media_type" 2 _LC1-args-slot
        _LC1-large 13 ROT CV-STRING! _LC1-ok
    S" content" 3 _LC1-args-slot
        _LC1-large 4096 ROT CV-STRING! _LC1-ok
    _LC1-request @ CBR.ARGS
        LIBRARY-CAP-DOCUMENT-CREATE CAP.IN-SCHEMA @ CS-VALIDATE-DEEP
        0= _LC1-assert
    \ Every payload byte needs a six-byte JSON escape.  The exact typed
    \ envelope is therefore 25,562 bytes, not merely the 4 KiB content.
    25562 _LC1-canonical-boundary
    _LC1-args-free ;

: _LC1-collection-canonical-boundary  ( -- )
    _LC1-large 110 1 FILL
    _LC1-args-free
    3 _LC1-request @ CBR.ARGS CV-MAP! _LC1-ok
    S" expected_logical_generation" 0 _LC1-args-slot
        0x7FFFFFFFFFFFFFFF SWAP CV-INT!
    S" title" 1 _LC1-args-slot
        _LC1-large 64 ROT CV-STRING! _LC1-ok
    S" members" 2 _LC1-args-slot DUP _LC1-node !
    LIBRARY-CAPABILITY-MEMBER-MAX SWAP CV-LIST! _LC1-ok
    LIBRARY-CAPABILITY-MEMBER-MAX 0 DO
        _LC1-large 110 I _LC1-node @ CV-LIST-NTH CV-RESOURCE! _LC1-ok
    LOOP
    _LC1-request @ CBR.ARGS
        LIBRARY-CAP-COLLECTION-CREATE CAP.IN-SCHEMA @ CS-VALIDATE-DEEP
        0= _LC1-assert
    \ The 64 schema-bounded resource strings yield a 43,758-byte typed
    \ envelope at their worst legal escaping expansion.
    43758 _LC1-canonical-boundary
    _LC1-args-free ;

: _LC1-create-canonical-boundaries  ( -- )
    CBR-ARGS-CANONICAL-MAX 65536 = _LC1-assert
    _LC1-document-canonical-boundary
    _LC1-collection-canonical-boundary
    _LC1-stack ;

." LIBRARY CAPABILITY L1 ARGUMENTS READY" CR _LC1-flush

\ ---------------------------------------------------------------------
\ Five descriptor handlers and ordinary controller reload
\ ---------------------------------------------------------------------

: _LC1-status-absent  ( -- )
    _LC1-args-free
    _LC1-request @ CBR.ARGS CV-NULL!
    0 _LC1-invocation!
    LIBRARY-CAP-STATUS _LC1-call CBUS-S-OK _LC1-status
    S" ready" _LC1-bool-field 0= _LC1-assert
    S" logical_generation" _LC1-int-field 0= _LC1-assert
    _LAPP-READY? 0= _LC1-assert
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-ABSENT = _LC1-assert
    _LAPP-REPOSITORY _LAPP-REPOSITORY-WORK LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-ABSENT = _LC1-assert
    _LC1-result-free
    _LC1-stack ;

: _LC1-document-result  ( -- )
    S" resource" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-document-id RID-COPY
    S" domain_revision" _LC1-int-field 1 = _LC1-assert
    S" logical_generation" _LC1-int-field DUP 0> _LC1-assert
        _LC1-logical !
    S" operation_receipt" _LC1-result-field _LC1-h64? _LC1-assert
    S" content_digest" _LC1-result-field _LC1-h64? _LC1-assert ;

: _LC1-document-create-and-replay  ( -- )
    \ Replay and generation semantics do not depend on content size.  The
    \ boundary entry point independently exercises the exact 4 KiB maximum.
    _LC1-large _LC1-primary-content-u [CHAR] A FILL
    0 _LC1-large _LC1-primary-content-u
        _LC1-document-args
    0x11 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-CREATE _LC1-call CBUS-S-OK _LC1-status
    _LC1-document-result
    _LAPP-READY? _LC1-assert
    _LC1-result-free

    \ The original expected generation is deliberately stale on retry.
    LIBRARY-CAP-DOCUMENT-CREATE _LC1-call
        CBUS-S-NO-EFFECT _LC1-status
    S" resource" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-document-id RID= _LC1-assert
    S" logical_generation" _LC1-int-field
        _LC1-logical @ = _LC1-assert
    _LC1-result-free

    \ Same invocation plus altered content is not a replay.
    S" content" _LC1-request @ CBR.ARGS CV-MAP-FIND
        S" altered replay" ROT CV-STRING! _LC1-ok
    LIBRARY-CAP-DOCUMENT-CREATE _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-IDEMPOTENCY-MISMATCH
        _LC1-error

    \ A different invocation is a fresh operation, so its stale logical
    \ generation must conflict rather than inheriting replay treatment.
    0 S" stale fresh request" _LC1-document-args
    0x12 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-CREATE _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-stack ;

: _LC1-read-primary-collection  ( -- )
    _LC1-primary-collection-read-request
        LIBRARY-COLLECTION-READ-REQUEST-INIT
    _LC1-collection-id _LC1-primary-collection-read-request
        LSCRR.RID RID-COPY
    _LC1-collection-revision @ _LC1-primary-collection-read-request
        LSCRR.EXPECTED-REVISION !
    _LC1-primary-collection _LC1-primary-collection-read-request
        LSCRR.RESULT !
    _LC1-primary-collection-read-request
        _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-READ-COLLECTION-EXACT
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-primary-collection LIBPA-COLLECTION-VALID? _LC1-assert ;

: _LC1-collection-result  ( -- )
    S" resource" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-collection-id RID-COPY
    S" domain_revision" _LC1-int-field DUP 1 = _LC1-assert
        _LC1-collection-revision !
    S" logical_generation" _LC1-int-field DUP 0> _LC1-assert
        _LC1-collection-logical !
    S" request_digest" _LC1-result-field DUP _LC1-h64? _LC1-assert
    DUP CV-DATA@ _LC1-collection-seal SHA3-256-HEX-LEN MOVE DROP
    _LC1-read-primary-collection ;

: _LC1-collection-create-and-replay  ( -- )
    _LC1-logical @ _LC1-collection-one
    0x21 _LC1-invocation!
    LIBRARY-CAP-COLLECTION-CREATE _LC1-call CBUS-S-OK _LC1-status
    _LC1-collection-result
    _LC1-result-free

    \ As with documents, replay uses the original now-stale expectation.
    LIBRARY-CAP-COLLECTION-CREATE _LC1-call
        CBUS-S-NO-EFFECT _LC1-status
    S" resource" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-collection-id RID= _LC1-assert
    S" logical_generation" _LC1-int-field
        _LC1-collection-logical @ = _LC1-assert
    _LC1-result-free

    S" title" _LC1-request @ CBR.ARGS CV-MAP-FIND
        S" Altered collection" ROT CV-STRING! _LC1-ok
    LIBRARY-CAP-COLLECTION-CREATE _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error

    \ A schema-valid list with a duplicate RID fails canonical semantics.
    _LC1-collection-logical @ _LC1-collection-duplicate
    0x22 _LC1-invocation!
    LIBRARY-CAP-COLLECTION-CREATE _LC1-call
        CBUS-S-INVALID LIBRARY-SERVICE-S-INVALID _LC1-error

    0 _LC1-collection-one
    0x23 _LC1-invocation!
    LIBRARY-CAP-COLLECTION-CREATE _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-stack ;

: _LC1-query-result  ( -- )
    S" collection" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-collection-id RID= _LC1-assert
    S" collection_domain_revision" _LC1-int-field 1 = _LC1-assert
    S" request_digest" _LC1-result-field DUP _LC1-h64? _LC1-assert
    DUP CV-DATA@ SHA3-256-HEX-LEN
        _LC1-collection-seal SHA3-256-HEX-LEN COMPARE 0= _LC1-assert
    DROP
    S" documents" _LC1-result-field DUP _LC1-node !
    DUP 0<> _LC1-assert
    DUP CV-TYPE@ CV-T-LIST = _LC1-assert
    CV-LEN@ 1 = _LC1-assert
    0 _LC1-node @ CV-LIST-NTH DUP _LC1-row ! 0<> _LC1-assert
    S" resource" _LC1-row @ CV-MAP-FIND
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-document-id RID= _LC1-assert
    S" domain_revision" _LC1-row @ CV-MAP-FIND
        CV-DATA@ 1 = _LC1-assert
    S" title" _LC1-row @ CV-MAP-FIND
        S" Capability document" _LC1-string= _LC1-assert
    S" media_type" _LC1-row @ CV-MAP-FIND
        S" text/plain" _LC1-string= _LC1-assert
    S" content_bytes" _LC1-row @ CV-MAP-FIND
        CV-DATA@ _LC1-primary-content-u = _LC1-assert
    S" content_digest" _LC1-row @ CV-MAP-FIND
        _LC1-h64? _LC1-assert
    S" next" _LC1-result-field CV-TYPE@ CV-T-NULL = _LC1-assert ;

: _LC1-query-contract  ( -- )
    _LC1-collection-revision @ _LC1-collection-seal _LC1-query-args
    0 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call CBUS-S-OK _LC1-status
    _LC1-query-result
    _LC1-result-free

    \ A well-formed but nonmatching request seal cannot escape its scope.
    _LC1-bad-seal!
    _LC1-collection-revision @ _LC1-bad-seal _LC1-query-args
    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error

    \ The collection revision is independently exact.
    _LC1-collection-revision @ 1+ _LC1-collection-seal _LC1-query-args
    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-stack ;

: _LC1-read-result  ( -- )
    S" collection" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-collection-id RID= _LC1-assert
    S" collection_domain_revision" _LC1-int-field 1 = _LC1-assert
    S" request_digest" _LC1-result-field _LC1-h64? _LC1-assert
    S" resource" _LC1-result-field
        _LC1-ref1 _LC1-r0@ _LC1-assert
    _LC1-ref1 RREF.ID _LC1-document-id RID= _LC1-assert
    S" domain_revision" _LC1-int-field 1 = _LC1-assert
    S" media_type" _LC1-result-field
        S" text/plain" _LC1-string= _LC1-assert
    S" content_bytes" _LC1-int-field
        _LC1-primary-content-u = _LC1-assert
    S" content_digest" _LC1-result-field _LC1-h64? _LC1-assert
    S" content" _LC1-result-field
        _LC1-large _LC1-primary-content-u
        _LC1-string= _LC1-assert ;

: _LC1-read-contract  ( -- )
    _LC1-collection-revision @ _LC1-collection-seal 1 _LC1-read-args
    0 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-READ _LC1-call CBUS-S-OK _LC1-status
    _LC1-read-result
    _LC1-result-free

    \ Exact document revision and exact collection scope fail separately.
    _LC1-collection-revision @ _LC1-collection-seal 2 _LC1-read-args
    LIBRARY-CAP-DOCUMENT-READ _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-collection-revision @ 1+ _LC1-collection-seal 1 _LC1-read-args
    LIBRARY-CAP-DOCUMENT-READ _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-stack ;

: _LC1-reload-contract  ( -- )
    _LC1-instance @ CINST.REVISION @ _LC1-before-revision !
    _LAPP-V-ACTIVE _LAPP-VIEW !
    _LAPP-RELOAD LIBRARY-SERVICE-S-OK _LC1-status
    _LAPP-ROW-COUNT @ 1 = _LC1-assert
    _LAPP-ENTRY LIBE.ID _LC1-document-id RID= _LC1-assert
    _LAPP-ENTRY _LC1-primary-current LIB-ENTRY-SIZE MOVE
    _LAPP-PREVIEW-READY @ _LC1-assert
    _LAPP-PREVIEW-U @ _LC1-primary-content-u = _LC1-assert
    _LAPP-PREVIEW-BYTES _LAPP-PREVIEW-U @
        _LC1-large _LC1-primary-content-u
        STR-STR= _LC1-assert

    _LAPP-V-COLLECTIONS _LAPP-VIEW !
    _LAPP-RELOAD LIBRARY-SERVICE-S-OK _LC1-status
    _LAPP-ROW-COUNT @ 1 = _LC1-assert
    0 _LAPP-COLLECTION-ROW LIBCS.REF RREF.ID
        _LC1-collection-id RID= _LC1-assert
    _LC1-instance @ CINST.REVISION @
        _LC1-before-revision @ = _LC1-assert
    _LC1-stack ;

: _LC1-collection-replaced-replay  ( -- )
    _LC1-primary-collection _LC1-collection-next
        LIBPA-COLLECTION-SIZE MOVE
    _LC1-primary-collection LIBC.REVISION @ 1+
        _LC1-collection-next LIBC.REVISION !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@
        _LC1-collection-next LIBC.MUTATION-SEQUENCE !
    S" Replaced capability collection" DUP
        _LC1-collection-next LIBC.TITLE-U !
    _LC1-collection-next LIBC.TITLE SWAP MOVE
    \ Replacement retains the immutable create-request seal.  Its advanced
    \ domain revision is what makes the original create invocation historical.

    _LC1-collection-replace-request
        LIBRARY-COLLECTION-WRITE-REQUEST-INIT
    _LC1-collection-next _LC1-collection-replace-request
        LSCWR.COLLECTION !
    _LC1-document-id _LC1-collection-replace-request LSCWR.MEMBERS !
    1 _LC1-collection-replace-request LSCWR.MEMBER-N !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC1-collection-replace-request LSCWR.EXPECTED-LOGICAL !
    _LC1-primary-collection LIBC.REVISION @
        _LC1-collection-replace-request LSCWR.EXPECTED-REVISION !
    _LC1-collection-replace-result _LC1-collection-replace-request
        LSCWR.RESULT !
    _LC1-collection-replace-request _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-REPLACE-COLLECTION
        LIBRARY-SERVICE-S-OK _LC1-status
    ." LIBRARY CAPABILITY L1 REPLACEMENT STORED" CR _LC1-flush
    _LC1-collection-replace-request LSCWR.CHANGED @ -1 = _LC1-assert
    _LC1-collection-replace-result LIBC.REVISION @ DUP
        _LC1-primary-collection LIBC.REVISION @ 1+ = _LC1-assert
        _LC1-collection-revision !
    _LC1-collection-replace-result LIBC.REQUEST-SEAL
        _LC1-collection-seal SHA3-256->HEX
        SHA3-256-HEX-LEN = _LC1-assert

    \ The operation key still resolves, but the current collection no longer
    \ carries the original create seal.  Replaying that original invocation
    \ is therefore a conflict rather than a false no-effect success.
    _LC1-logical @ _LC1-collection-one
    0x21 _LC1-invocation!
    ." LIBRARY CAPABILITY L1 REPLACEMENT REPLAY" CR _LC1-flush
    LIBRARY-CAP-COLLECTION-CREATE _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-stack ;

: _LC1-tombstone-contract  ( -- )
    _LC1-primary-current
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@
    _LC1-tombstone-next
        LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-tombstone-request LIBRARY-DOCUMENT-REPLACE-REQUEST-INIT
    _LC1-tombstone-next _LC1-tombstone-request LSDRR.NEXT !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC1-tombstone-request LSDRR.EXPECTED-LOGICAL !
    _LC1-primary-current LIBE.DOMAIN-REVISION @
        _LC1-tombstone-request LSDRR.EXPECTED-DOMAIN !
    _LC1-tombstone-result _LC1-tombstone-request LSDRR.RESULT !
    ." LIBRARY CAPABILITY L1 TOMBSTONE STORE" CR _LC1-flush
    _LC1-tombstone-request _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-TOMBSTONE
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-tombstone-result LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _LC1-assert

    \ A current exact revision identifies the terminal object precisely.
    \ The public read maps that Library status to bus NOT-FOUND while
    \ retaining TOMBSTONED in the request error domain and no typed result.
    _LC1-collection-revision @ _LC1-collection-seal
    _LC1-tombstone-result LIBE.DOMAIN-REVISION @ _LC1-read-args
    0 _LC1-invocation!
    ." LIBRARY CAPABILITY L1 TOMBSTONE READ" CR _LC1-flush
    LIBRARY-CAP-DOCUMENT-READ _LC1-call
        CBUS-S-NOT-FOUND LIBRARY-SERVICE-S-TOMBSTONED _LC1-error

    \ The original create invocation resolves to the terminal object rather
    \ than manufacturing a replacement or reporting no effect.
    0 _LC1-large _LC1-primary-content-u _LC1-document-args
    0x11 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-CREATE _LC1-call
        CBUS-S-NOT-FOUND LIBRARY-SERVICE-S-TOMBSTONED _LC1-error
    _LC1-stack ;

." LIBRARY CAPABILITY L1 CORE READY" CR _LC1-flush

\ ---------------------------------------------------------------------
\ Direct service boundaries: 65,536 succeeds; 65,537 is too large to read
\ ---------------------------------------------------------------------

: _LC1-direct-document  ( id-byte operation-byte content-u -- status )
    _LC1-direct-u ! _LC1-direct-operation ! _LC1-direct-id !
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT
        LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LC1-direct-id @
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT LSDID.ID _LC1-id!
    _LC1-direct-operation @
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT
            LSDID.OPERATION-KEY _LC1-id!
    LIB-KIND-MANAGED-DOCUMENT
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT LSDID.MEDIA !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT
            LSDID.MUTATION-SEQUENCE !
    _LC1-large _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT
        LSDID.CONTENT-A !
    _LC1-direct-u @ _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT
        LSDID.CONTENT-U !
    S" Boundary document" DUP
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT LSDID.TITLE-U !
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT LSDID.TITLE
        SWAP MOVE
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-DRAFT
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-ENTRY
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CONTENT
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
    DUP IF EXIT THEN DROP

    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CREATE-REQUEST
        LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-ENTRY
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CREATE-REQUEST LSDCR.ENTRY !
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CONTENT
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CREATE-REQUEST LSDCR.CONTENT !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CREATE-REQUEST
            LSDCR.EXPECTED-LOGICAL !
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-RESULT
        _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CREATE-REQUEST LSDCR.RESULT !
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-CREATE-REQUEST
        _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-CREATE-MANAGED ;

: _LC1-oversize-replace-small  ( -- )
    _LC1-oversize-current S" seed two"
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@
    _LC1-oversize-next _LC1-oversize-content
        LIBRARY-SERVICE-PREPARE-CONTENT-NEXT
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-oversize-replace-request
        LIBRARY-DOCUMENT-REPLACE-REQUEST-INIT
    _LC1-oversize-next _LC1-oversize-replace-request LSDRR.NEXT !
    _LC1-oversize-content _LC1-oversize-replace-request LSDRR.CONTENT !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC1-oversize-replace-request LSDRR.EXPECTED-LOGICAL !
    _LC1-oversize-current LIBE.DOMAIN-REVISION @
        _LC1-oversize-replace-request LSDRR.EXPECTED-DOMAIN !
    _LC1-oversize-result _LC1-oversize-replace-request LSDRR.RESULT !
    _LC1-oversize-replace-request _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-REPLACE-CONTENT
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-oversize-result _LC1-oversize-current LIB-ENTRY-SIZE MOVE
    _LC1-oversize-current LIBE.DOMAIN-REVISION @ 2 = _LC1-assert
    _LC1-oversize-current LIBE.CURRENT-CONTENT-REVISION @ 2 =
        _LC1-assert ;

: _LC1-install-oversize-run  ( index-work -- status )
    >R
    R@ _LIBPIX-BEGIN-RUN DUP IF R> DROP EXIT THEN DROP
    _LC1-large-u ['] _LIBPIX-MEMORY-SOURCE _LC1-large
    R@ _LIBPIX.BLOB
    _LC1-owner-adapter @ _LIBPA-D.STORE @
    R@ _LIBPIX.PSTORE-WORK @ R@ _LIBPIX.BLOB-WORK
        PBLOB-WRITE
    DUP IF _LIBPA-PERSIST>STATUS R> DROP EXIT THEN DROP

    R@ _LIBPIX.STAGE LIBPA-CONTENT-DESCRIPTOR-SIZE 0 FILL
    _LIBPA-CONTENT-MAGIC R@ _LIBPIX.STAGE _LIBPAC.MAGIC !
    LIBPA-CONTENT-F-LIBRARY R@ _LIBPIX.STAGE _LIBPAC.FLAGS !
    _LC1-oversize-current LIBE.ID
        R@ _LIBPIX.STAGE _LIBPAC.RID RID-COPY
    1 R@ _LIBPIX.STAGE _LIBPAC.DOMAIN-REVISION !
    1 R@ _LIBPIX.STAGE _LIBPAC.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT R@ _LIBPIX.STAGE _LIBPAC.KIND !
    LIB-MEDIA-TEXT-PLAIN R@ _LIBPIX.STAGE _LIBPAC.MEDIA !
    _LC1-large-u R@ _LIBPIX.STAGE _LIBPAC.DATA-U !
    _LC1-large-digest R@ _LIBPIX.STAGE _LIBPAC.DIGEST
        LIB-DIGEST-SIZE MOVE
    R@ _LIBPIX.BLOB R@ _LIBPIX.STAGE _LIBPAC.BLOB PBLOB-COPY
    DUP IF _LIBPA-PERSIST>STATUS R> DROP EXIT THEN DROP
    R@ _LIBPIX.STAGE LIBPA-CONTENT-DESCRIPTOR-VALID? 0= IF
        R> DROP LIBPA-S-CORRUPT EXIT
    THEN
    R@ _LIBPIX.STAGE _LC1-oversize-target
        LIBPA-CONTENT-DESCRIPTOR-SIZE MOVE
    R@ _LIBPIX-CONTENT-APPEND DUP IF R> DROP EXIT THEN DROP
    _LC1-oversize-current LIBE.ID 1 R@ _LIBPIX.KEY0
        LIBPI-HISTORY-KEY
    DUP IF _LIBPA-LIB>STATUS R> DROP EXIT THEN DROP
    R@ _LIBPIX.KEY0 LIBPI-HISTORY-KEY-SIZE
    R@ _LIBPIX.HISTORY-REF PERSIST-REF-SIZE
    _LIBPIX-HISTORY R@ _LIBPIX-PUT
    DUP IF R> DROP EXIT THEN DROP
    1 R@ _LIBPIX.RAW-N !
    R@ _LIBPIX-COMMIT-RUN
    R> DROP ;

: _LC1-install-oversize-owner
  ( context repository repository-work -- repository-status )
    DUP LIBRARY-REPOSITORY-INDEX-WORK@ _LC1-owner-index !
    OVER LIBRARY-REPOSITORY-ADAPTER@ _LC1-owner-adapter !
    2DROP DROP
    _LC1-owner-adapter @ _LC1-owner-index @ _LIBPIX-ENTER
    DUP IF EXIT THEN DROP
    _LC1-owner-index @ ['] _LC1-install-oversize-run
        _LIBPIX-WORK-CATCH
    _LC1-owner-index @ _LIBPIX-STAGE-DISCARD
    _LC1-owner-adapter @ _LC1-owner-index @ _LIBPIX-LEAVE ;

: _LC1-install-oversize-retained  ( -- )
    \ The public capability creates at most 4 KiB, while this read contract
    \ needs a valid Library value one byte beyond its 65,536-byte output
    \ window.  Mirror the existing retained-restore qualification path:
    \ write the immutable PBLOB outside the staged mutation arena, replace
    \ one retained history descriptor, then restore it through the semantic
    \ owner.  This does not raise the 128-page physical transaction bound or
    \ manufacture a second repository/service graph.
    [CHAR] X _LC1-large PBLOB-CHUNK-SIZE 1- + C!
    [CHAR] Y _LC1-large PBLOB-CHUNK-SIZE + C!
    [CHAR] Z _LC1-large PBLOB-CHUNK-SIZE 1+ + C!
    1 ['] _LC1-install-oversize-owner
    _LAPP-REPOSITORY _LAPP-REPOSITORY-WORK
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-OK _LC1-status
    _LC1-oversize-target LIBPA-CONTENT-SIZE@ _LC1-large-u =
        _LC1-assert
    _LC1-oversize-target _LC1-oversize-retained-facts
        _LIBPA-DESCRIPTOR>RETAINED-FACTS LIBPA-S-OK _LC1-status ;

: _LC1-restore-oversize-current  ( -- )
    _LC1-oversize-current _LC1-oversize-retained-facts
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@
    _LC1-oversize-next LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-oversize-restore-request LIBRARY-DOCUMENT-RESTORE-REQUEST-INIT
    _LC1-oversize-next _LC1-oversize-restore-request LSDTR.NEXT !
    1 _LC1-oversize-restore-request LSDTR.RETAINED-DOMAIN !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC1-oversize-restore-request LSDTR.EXPECTED-LOGICAL !
    _LC1-oversize-current LIBE.DOMAIN-REVISION @
        _LC1-oversize-restore-request LSDTR.EXPECTED-DOMAIN !
    _LC1-oversize-result _LC1-oversize-restore-request LSDTR.RESULT !
    _LC1-oversize-restore-request _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-RESTORE-RETAINED
        LIBRARY-SERVICE-S-OK _LC1-status
    _LC1-oversize-result _LC1-oversize-current LIB-ENTRY-SIZE MOVE
    _LC1-oversize-current LIBE.DOMAIN-REVISION @ 3 = _LC1-assert
    _LC1-oversize-current LIBE.CONTENT-U @ _LC1-large-u = _LC1-assert ;

: _LC1-oversize-document  ( -- )
    0xB2 0xC2 16 _LC1-direct-document
        LIBRARY-SERVICE-S-OK _LC1-status
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-RESULT
        _LC1-oversize-current LIB-ENTRY-SIZE MOVE
    _LC1-oversize-current LIBE.ID
        _LC1-oversize-document-id RID= _LC1-assert
    _LC1-oversize-replace-small
    _LC1-install-oversize-retained
    _LC1-restore-oversize-current
    \ The retained PBLOB owns its copied bytes.  Restore the shared fixture
    \ buffer to the all-A payload expected by the exact-full document.
    [CHAR] A _LC1-large PBLOB-CHUNK-SIZE 1- + C!
    [CHAR] A _LC1-large PBLOB-CHUNK-SIZE + C!
    [CHAR] A _LC1-large PBLOB-CHUNK-SIZE 1+ + C! ;

: _LC1-boundary-collection-create  ( -- )
    _LC1-boundary-document-id
        _LC1-boundary-members RID-COPY
    _LC1-oversize-document-id
        _LC1-boundary-members RID-SIZE + RID-COPY
    _LC1-boundary-members 2
        LIBRARY-COLLECTION-MEMBERS-CANONICAL? _LC1-assert

    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT
        LIBRARY-COLLECTION-INITIAL-DRAFT-INIT
    0xD1 _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT
        LSCID.ID _LC1-id!
    0xE1 _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT
        LSCID.OPERATION-KEY _LC1-id!
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT
            LSCID.MUTATION-SEQUENCE !
    _LC1-boundary-members
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT LSCID.MEMBERS-A !
    2 _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT LSCID.MEMBER-N !
    S" Boundary collection" DUP
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT LSCID.TITLE-U !
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT LSCID.TITLE
        SWAP MOVE
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-DRAFT
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION
        LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        LIBRARY-SERVICE-S-OK _LC1-status

    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
        LIBRARY-COLLECTION-WRITE-REQUEST-INIT
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
            LSCWR.COLLECTION !
    _LC1-boundary-members
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
            LSCWR.MEMBERS !
    2 _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
        LSCWR.MEMBER-N !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
            LSCWR.EXPECTED-LOGICAL !
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-RESULT
        _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
            LSCWR.RESULT !
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-WRITE-REQUEST
        _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-CREATE-COLLECTION
        LIBRARY-SERVICE-S-OK _LC1-status
    _LAPP-CAPABILITY-WORK LCAPW.COLLECTION-RESULT
        _LC1-boundary-collection LIBPA-COLLECTION-SIZE MOVE
    _LC1-boundary-collection LIBPA-COLLECTION-VALID? _LC1-assert ;

: _LC1-boundary-read!  ( rid expected-domain -- )
    _LC1-expected ! _LC1-source !
    _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
        LIBRARY-SCOPED-READ-REQUEST-INIT
    _LC1-boundary-collection LIBC.ID
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
            LSSRR.SCOPE LSECS.COLLECTION RID-COPY
    _LC1-boundary-collection LIBC.REVISION @
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
            LSSRR.SCOPE LSECS.DOMAIN-REVISION !
    _LC1-boundary-collection LIBC.REQUEST-SEAL
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
            LSSRR.SCOPE LSECS.REQUEST-SEAL RID-COPY
    _LC1-source @
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ LSSRR.RID RID-COPY
    _LC1-expected @
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
            LSSRR.EXPECTED-DOMAIN !
    _LAPP-CAPABILITY-WORK LCAPW.READ-ENTRY LIB-ENTRY-INIT
    _LAPP-CAPABILITY-WORK LCAPW.READ-DESCRIPTOR
        LIBRARY-SERVICE-CONTENT-DESCRIPTOR-SIZE 0 FILL
    _LAPP-CAPABILITY-WORK LCAPW.READ-ENTRY
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ LSSRR.ENTRY !
    _LAPP-CAPABILITY-WORK LCAPW.READ-DESCRIPTOR
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ LSSRR.DESCRIPTOR !
    _LAPP-CAPABILITY-WORK LCAPW.CONTENT
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ LSSRR.CONTENT-A !
    LIB-CONTENT-WINDOW-MAX
        _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
            LSSRR.CONTENT-CAPACITY !
    _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
        LIBRARY-SCOPED-READ-REQUEST-VALID? _LC1-assert ;

: _LC1-capability-read-boundaries  ( -- )
    _LC1-boundary-collection LIBC.ID _LC1-collection-id RID-COPY
    _LC1-boundary-collection LIBC.REVISION @
        _LC1-collection-revision !
    _LC1-boundary-collection LIBC.REQUEST-SEAL
        _LC1-collection-seal SHA3-256->HEX
        SHA3-256-HEX-LEN = _LC1-assert

    _LC1-boundary-document-id _LC1-document-id RID-COPY
    _LC1-collection-revision @ _LC1-collection-seal 1 _LC1-read-args
    0 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-READ _LC1-call CBUS-S-OK _LC1-status
    S" content_bytes" _LC1-int-field
        LIB-CONTENT-WINDOW-MAX = _LC1-assert
    S" content" _LC1-result-field DUP CV-TYPE@ CV-T-STRING = _LC1-assert
    DUP CV-LEN@ LIB-CONTENT-WINDOW-MAX = _LC1-assert
    DUP CV-DATA@ SWAP CV-LEN@
        _LC1-large LIB-CONTENT-WINDOW-MAX STR-STR= _LC1-assert
    _LC1-result-free

    _LC1-oversize-document-id _LC1-document-id RID-COPY
    _LC1-collection-revision @ _LC1-collection-seal
    _LC1-oversize-current LIBE.DOMAIN-REVISION @ _LC1-read-args
    LIBRARY-CAP-DOCUMENT-READ _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-OUTPUT-CAPACITY _LC1-error ;

: _LC1-query-limit!  ( limit -- )
    S" limit" _LC1-request @ CBR.ARGS CV-MAP-FIND CV-INT! ;

: _LC1-query-after-args  ( cursor -- )
    _LC1-node !
    _LC1-collection-revision @ _LC1-collection-seal _LC1-query-args
    1 _LC1-query-limit!
    _LC1-node @
    S" after" _LC1-request @ CBR.ARGS CV-MAP-FIND
        CV-COPY _LC1-ok ;

: _LC1-query-pagination  ( -- )
    _LC1-collection-revision @ _LC1-collection-seal _LC1-query-args
    1 _LC1-query-limit!
    0 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call CBUS-S-OK _LC1-status
    S" documents" _LC1-result-field CV-LEN@ 1 = _LC1-assert
    S" next" _LC1-result-field DUP CV-TYPE@ CV-T-MAP = _LC1-assert
    _LC1-query-after-args
    _LC1-result-free

    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call CBUS-S-OK _LC1-status
    S" documents" _LC1-result-field CV-LEN@ 1 = _LC1-assert
    S" next" _LC1-result-field CV-TYPE@ CV-T-NULL = _LC1-assert
    _LC1-result-free

    \ Rebuild the first cursor, then tamper only its public fingerprint.
    \ The exact-scope wrapper must reject it before translating the token.
    _LC1-collection-revision @ _LC1-collection-seal _LC1-query-args
    1 _LC1-query-limit!
    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call CBUS-S-OK _LC1-status
    S" next" _LC1-result-field DUP CV-TYPE@ CV-T-MAP = _LC1-assert
    _LC1-query-after-args
    _LC1-result-free
    S" after" _LC1-request @ CBR.ARGS CV-MAP-FIND
    S" fingerprint" ROT CV-MAP-FIND CV-DATA@
    DUP C@ [CHAR] 0 = IF [CHAR] 1 ELSE [CHAR] 0 THEN SWAP C!
    LIBRARY-CAP-DOCUMENT-QUERY _LC1-call
        CBUS-S-FAILED LIBRARY-SERVICE-S-CONFLICT _LC1-error
    _LC1-stack ;

: _LC1-read-boundaries  ( -- )
    _LC1-large _LC1-large-u [CHAR] A FILL
    0xB1 _LC1-boundary-document-id _LC1-id!
    0xB2 _LC1-oversize-document-id _LC1-id!

    0xB1 0xC1 LIB-CONTENT-WINDOW-MAX _LC1-direct-document
        LIBRARY-SERVICE-S-OK _LC1-status
    _LAPP-CAPABILITY-WORK LCAPW.DOCUMENT-RESULT LIBE.ID
        _LC1-boundary-document-id RID= _LC1-assert
    _LC1-oversize-document

    _LC1-boundary-collection-create
    \ The public exact-full read below covers the successful service copy.
    \ Keep one direct one-over call to prove its failure cleanup contract.
    _LC1-oversize-document-id
        _LC1-oversize-current LIBE.DOMAIN-REVISION @ _LC1-boundary-read!
    _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ
        _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-READ-COLLECTION-MEMBER-EXACT
        LIBRARY-SERVICE-S-OUTPUT-CAPACITY _LC1-status
    _LAPP-CAPABILITY-WORK LCAPW.SCOPED-READ LSSRR.CONTENT-U @
        0= _LC1-assert
    _LAPP-CAPABILITY-WORK LCAPW.READ-ENTRY LIB-ENTRY-SIZE
        _LC1-zero? _LC1-assert
    _LAPP-CAPABILITY-WORK LCAPW.READ-DESCRIPTOR
        LIBRARY-SERVICE-CONTENT-DESCRIPTOR-SIZE
        _LC1-zero? _LC1-assert
    _LAPP-CAPABILITY-WORK LCAPW.CONTENT LIB-CONTENT-WINDOW-MAX
        _LC1-zero? _LC1-assert
    _LC1-capability-read-boundaries
    _LC1-query-pagination
    _LC1-stack ;

: _LC1-create-content-max  ( -- )
    _LC1-large LIBRARY-CAPABILITY-CREATE-CONTENT-MAX [CHAR] A FILL
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC1-large LIBRARY-CAPABILITY-CREATE-CONTENT-MAX
        _LC1-document-args
    0x31 _LC1-invocation!
    LIBRARY-CAP-DOCUMENT-CREATE _LC1-call CBUS-S-OK _LC1-status
    S" resource" _LC1-result-field _LC1-ref1 _LC1-r0@ _LC1-assert
    S" domain_revision" _LC1-int-field 1 = _LC1-assert
    S" logical_generation" _LC1-int-field 0> _LC1-assert
    S" content_digest" _LC1-result-field _LC1-h64? _LC1-assert
    _LC1-result-free
    _LC1-stack ;

\ ---------------------------------------------------------------------
\ Real applet activation
\ ---------------------------------------------------------------------

: _LC1-descriptors  ( -- )
    LIBRARY-APPLET-CAPABILITY-COUNT 5 = _LC1-assert
    LIBRARY-CAP-STATUS CAP-DESC-VALID? _LC1-assert
    S" library.status" LIBRARY-CAP-STATUS CAP.ID-A @
        LIBRARY-CAP-STATUS CAP.ID-U @ STR-STR= _LC1-assert
    LIBRARY-CAP-STATUS CAP.KIND @ CAP-K-RESOURCE = _LC1-assert
    LIBRARY-CAP-STATUS CAP.EFFECTS @ CAP-E-OBSERVE = _LC1-assert
    LIBRARY-CAP-STATUS CAP.FLAGS @
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR = _LC1-assert
    LIBRARY-CAP-STATUS CAP.IN-SCHEMA @ CS.FIELD-N @ 0= _LC1-assert
    LIBRARY-CAP-STATUS CAP.OUT-SCHEMA @ CS.FIELD-N @ 2 = _LC1-assert

    LIBRARY-CAP-DOCUMENT-CREATE CAP-DESC-VALID? _LC1-assert
    S" library.document.create" LIBRARY-CAP-DOCUMENT-CREATE CAP.ID-A @
        LIBRARY-CAP-DOCUMENT-CREATE CAP.ID-U @ STR-STR= _LC1-assert
    LIBRARY-CAP-DOCUMENT-CREATE CAP.KIND @ CAP-K-COMMAND = _LC1-assert
    LIBRARY-CAP-DOCUMENT-CREATE CAP.EFFECTS @
        CAP-E-MUTATE CAP-E-PERSIST OR = _LC1-assert
    LIBRARY-CAP-DOCUMENT-CREATE CAP.FLAGS @
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR = _LC1-assert
    LIBRARY-CAP-DOCUMENT-CREATE CAP.IN-SCHEMA @
        CS.FIELD-N @ 4 = _LC1-assert
    LIBRARY-CAP-DOCUMENT-CREATE CAP.OUT-SCHEMA @
        CS.FIELD-N @ 5 = _LC1-assert

    LIBRARY-CAP-COLLECTION-CREATE CAP-DESC-VALID? _LC1-assert
    S" library.collection.create" LIBRARY-CAP-COLLECTION-CREATE CAP.ID-A @
        LIBRARY-CAP-COLLECTION-CREATE CAP.ID-U @ STR-STR= _LC1-assert
    LIBRARY-CAP-COLLECTION-CREATE CAP.KIND @ CAP-K-COMMAND = _LC1-assert
    LIBRARY-CAP-COLLECTION-CREATE CAP.EFFECTS @
        CAP-E-MUTATE CAP-E-PERSIST OR = _LC1-assert
    LIBRARY-CAP-COLLECTION-CREATE CAP.FLAGS @
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR = _LC1-assert
    LIBRARY-CAP-COLLECTION-CREATE CAP.IN-SCHEMA @
        CS.FIELD-N @ 3 = _LC1-assert
    LIBRARY-CAP-COLLECTION-CREATE CAP.OUT-SCHEMA @
        CS.FIELD-N @ 4 = _LC1-assert

    LIBRARY-CAP-DOCUMENT-QUERY CAP-DESC-VALID? _LC1-assert
    S" library.document.query" LIBRARY-CAP-DOCUMENT-QUERY CAP.ID-A @
        LIBRARY-CAP-DOCUMENT-QUERY CAP.ID-U @ STR-STR= _LC1-assert
    LIBRARY-CAP-DOCUMENT-QUERY CAP.KIND @ CAP-K-RESOURCE = _LC1-assert
    LIBRARY-CAP-DOCUMENT-QUERY CAP.EFFECTS @ CAP-E-OBSERVE = _LC1-assert
    LIBRARY-CAP-DOCUMENT-QUERY CAP.FLAGS @
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR = _LC1-assert
    LIBRARY-CAP-DOCUMENT-QUERY CAP.IN-SCHEMA @
        CS.FIELD-N @ 5 = _LC1-assert
    LIBRARY-CAP-DOCUMENT-QUERY CAP.OUT-SCHEMA @
        CS.FIELD-N @ 5 = _LC1-assert

    LIBRARY-CAP-DOCUMENT-READ CAP-DESC-VALID? _LC1-assert
    S" library.document.read" LIBRARY-CAP-DOCUMENT-READ CAP.ID-A @
        LIBRARY-CAP-DOCUMENT-READ CAP.ID-U @ STR-STR= _LC1-assert
    LIBRARY-CAP-DOCUMENT-READ CAP.KIND @ CAP-K-RESOURCE = _LC1-assert
    LIBRARY-CAP-DOCUMENT-READ CAP.EFFECTS @ CAP-E-OBSERVE = _LC1-assert
    LIBRARY-CAP-DOCUMENT-READ CAP.FLAGS @
        CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR = _LC1-assert
    LIBRARY-CAP-DOCUMENT-READ CAP.IN-SCHEMA @
        CS.FIELD-N @ 5 = _LC1-assert
    LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @
        CS.FIELD-N @ 9 = _LC1-assert ;

." LIBRARY CAPABILITY L1 DEFINITIONS READY" CR _LC1-flush

: _LC1-shell-finish  ( -- )
    _LC1-args-free
    _LC1-result-free
    _LC1-request @ CBR-FREE
    0 _LC1-request !
    _LC1-stack
    ASHELL-QUIT ;

: _LC1-shell-init  ( instance -- )
    DUP _LC1-instance !
    LIBRARY-APPLET-INIT-CB
    _LC1-request-setup
    DEPTH _LC1-depth !
    ." LIBRARY CAPABILITY L1 PHASE DESCRIPTORS" CR _LC1-flush
    _LAPP-CAPABILITY-WORK LIBRARY-CAPABILITY-WORK-VALID? _LC1-assert
    _LC1-descriptors
    _LC1-service-error-map
    ." LIBRARY CAPABILITY L1 PHASE STATUS" CR _LC1-flush
    _LC1-status-absent
    ." LIBRARY CAPABILITY L1 PHASE CREATES" CR _LC1-flush
    _LC1-document-create-and-replay
    _LC1-collection-create-and-replay
    ." LIBRARY CAPABILITY L1 PHASE READ QUERY" CR _LC1-flush
    _LC1-query-contract
    _LC1-read-contract
    _LC1-reload-contract
    ." LIBRARY CAPABILITY L1 PHASE REPLACEMENT" CR _LC1-flush
    _LC1-collection-replaced-replay
    _LC1-tombstone-contract
    _LC1-shell-finish ;

: _LC1-boundary-shell-init  ( instance -- )
    DUP _LC1-instance !
    LIBRARY-APPLET-INIT-CB
    _LC1-request-setup
    DEPTH _LC1-depth !
    ." LIBRARY CAPABILITY BOUNDARY L1 PHASE PROVISION" CR _LC1-flush
    _LAPP-CAPABILITY-WORK LIBRARY-CAPABILITY-WORK-VALID? _LC1-assert
    _LAPP-ENSURE-PROVISIONED LIBRARY-SERVICE-S-OK _LC1-status
    ." LIBRARY CAPABILITY BOUNDARY L1 PHASE READS" CR _LC1-flush
    _LC1-read-boundaries
    _LC1-shell-finish ;

: _LC1-create-boundary-shell-init  ( instance -- )
    DUP _LC1-instance !
    LIBRARY-APPLET-INIT-CB
    _LC1-request-setup
    DEPTH _LC1-depth !
    ." LIBRARY CAPABILITY CREATE BOUNDARY L1 PHASE PROVISION" CR _LC1-flush
    _LAPP-CAPABILITY-WORK LIBRARY-CAPABILITY-WORK-VALID? _LC1-assert
    _LAPP-ENSURE-PROVISIONED LIBRARY-SERVICE-S-OK _LC1-status
    ." LIBRARY CAPABILITY CREATE BOUNDARY L1 PHASE CANONICAL" CR _LC1-flush
    _LC1-create-canonical-boundaries
    ." LIBRARY CAPABILITY CREATE BOUNDARY L1 PHASE EXACT MAX" CR _LC1-flush
    _LC1-create-content-max
    _LC1-shell-finish ;

\ ---------------------------------------------------------------------
\ Query/read IVJSON maxima and caller-bounded decode
\ ---------------------------------------------------------------------
\ This focused phase regenerates every published query/read capability bound
\ from a schema-valid worst-case graph.  It also proves that a full escaped
\ read result needs the caller-bounded decode entry point: the normal 65,536
\ byte document ceiling remains unchanged, one byte below the declared limit
\ is rejected without replacing the destination, and the exact limit decodes
\ deeply against the public result schema.

VARIABLE _LC1-wb-schema-wide
VARIABLE _LC1-wb-node
VARIABLE _LC1-wb-list
VARIABLE _LC1-wb-row
VARIABLE _LC1-wb-expected
VARIABLE _LC1-wb-encoder
VARIABLE _LC1-wb-length
VARIABLE _LC1-wb-ior
VARIABLE _LC1-wb-buffer
VARIABLE _LC1-wb-control

CREATE _LC1-wb-root CV-SIZE ALLOT
CREATE _LC1-wb-decoded CV-SIZE ALLOT
CREATE _LC1-wb-rid RID-SIZE ALLOT
CREATE _LC1-wb-ref RREF-SIZE ALLOT
CREATE _LC1-wb-hex SHA3-256-HEX-LEN ALLOT

_LC1-wb-root CV-INIT
_LC1-wb-decoded CV-INIT
0 _LC1-wb-buffer !
0 _LC1-wb-control !

: _LC1-wb-allocate  ( bytes -- address )
    ALLOCATE DUP IF NIP THROW THEN DROP ;

: _LC1-wb-buffers-free  ( -- )
    _LC1-wb-buffer @ ?DUP IF FREE 0 _LC1-wb-buffer ! THEN
    _LC1-wb-control @ ?DUP IF FREE 0 _LC1-wb-control ! THEN ;

: _LC1-wb-buffers-allocate  ( -- )
    _LC1-wb-buffers-free
    LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-TYPED-MAX
        _LC1-wb-allocate _LC1-wb-buffer !
    CV-MAX-STRING-LEN _LC1-wb-allocate DUP _LC1-wb-control !
        CV-MAX-STRING-LEN 1 FILL ;

: _LC1-wb-root-free  ( -- ) _LC1-wb-root CV-FREE ;

: _LC1-wb-root-map  ( count -- )
    _LC1-wb-root-free _LC1-wb-root CV-MAP! _LC1-ok ;

: _LC1-wb-map-slot  ( key-a key-u index map -- value )
    CV-MAP-SLOT! DUP 0= _LC1-assert DROP ;

: _LC1-wb-root-slot  ( key-a key-u index -- value )
    _LC1-wb-root _LC1-wb-map-slot ;

: _LC1-wb-r0!  ( value -- )
    >R _LC1-wb-ref RREF-INIT
    _LC1-wb-rid _LC1-wb-ref RREF.ID RID-COPY
    _LC1-wb-ref R> IRES-RREF! IRES-S-OK = _LC1-assert ;

: _LC1-wb-resource!  ( value -- )
    _LC1-wb-schema-wide @ IF
        _LC1-wb-control @ IRES-RREF-URI-MAX ROT CV-RESOURCE! _LC1-ok
    ELSE
        _LC1-wb-r0!
    THEN ;

: _LC1-wb-text!  ( semantic-a semantic-u maximum value -- )
    >R
    _LC1-wb-schema-wide @ IF
        NIP NIP _LC1-wb-control @ SWAP R> CV-STRING! _LC1-ok
    ELSE
        DROP R> CV-STRING! _LC1-ok
    THEN ;

: _LC1-wb-digest!  ( value -- )
    >R _LC1-wb-hex SHA3-256-HEX-LEN SHA3-256-HEX-LEN R>
        _LC1-wb-text! ;

: _LC1-wb-cursor!  ( value -- )
    _LC1-wb-node ! 6 _LC1-wb-node @ CV-MAP! _LC1-ok
    S" fingerprint" 0 _LC1-wb-node @ _LC1-wb-map-slot _LC1-wb-digest!
    S" observed_logical_generation" 1
        _LC1-wb-node @ _LC1-wb-map-slot
        CV-CELL-MAX SWAP CV-INT!
    S" first_order_sequence" 2 _LC1-wb-node @ _LC1-wb-map-slot
        CV-CELL-MAX SWAP CV-INT!
    S" first_resource" 3 _LC1-wb-node @ _LC1-wb-map-slot
        _LC1-wb-resource!
    S" last_order_sequence" 4 _LC1-wb-node @ _LC1-wb-map-slot
        CV-CELL-MAX SWAP CV-INT!
    S" last_resource" 5 _LC1-wb-node @ _LC1-wb-map-slot
        _LC1-wb-resource! ;

: _LC1-wb-row!  ( value -- )
    _LC1-wb-row ! 6 _LC1-wb-row @ CV-MAP! _LC1-ok
    S" resource" 0 _LC1-wb-row @ _LC1-wb-map-slot _LC1-wb-resource!
    S" domain_revision" 1 _LC1-wb-row @ _LC1-wb-map-slot
        CV-CELL-MAX SWAP CV-INT!
    _LC1-wb-control @ LIB-TITLE-MAX LIB-TITLE-MAX
        S" title" 2 _LC1-wb-row @ _LC1-wb-map-slot _LC1-wb-text!
    S" text/markdown" 13
        S" media_type" 3 _LC1-wb-row @ _LC1-wb-map-slot _LC1-wb-text!
    S" content_bytes" 4 _LC1-wb-row @ _LC1-wb-map-slot
        CV-CELL-MAX SWAP CV-INT!
    S" content_digest" 5 _LC1-wb-row @ _LC1-wb-map-slot
        _LC1-wb-digest! ;

: _LC1-wb-documents!  ( value -- )
    _LC1-wb-list ! LIBRARY-CAPABILITY-QUERY-MAX _LC1-wb-list @
        CV-LIST! _LC1-ok
    LIBRARY-CAPABILITY-QUERY-MAX 0 ?DO
        I _LC1-wb-list @ CV-LIST-NTH _LC1-wb-row!
    LOOP ;

: _LC1-wb-build-query-request  ( schema-wide? -- )
    _LC1-wb-schema-wide ! 5 _LC1-wb-root-map
    S" collection" 0 _LC1-wb-root-slot _LC1-wb-resource!
    S" collection_domain_revision" 1 _LC1-wb-root-slot
        CV-CELL-MAX SWAP CV-INT!
    S" request_digest" 2 _LC1-wb-root-slot _LC1-wb-digest!
    S" after" 3 _LC1-wb-root-slot _LC1-wb-cursor!
    S" limit" 4 _LC1-wb-root-slot
        LIBRARY-CAPABILITY-QUERY-MAX SWAP CV-INT! ;

: _LC1-wb-build-query-result  ( schema-wide? -- )
    _LC1-wb-schema-wide ! 5 _LC1-wb-root-map
    S" collection" 0 _LC1-wb-root-slot _LC1-wb-resource!
    S" collection_domain_revision" 1 _LC1-wb-root-slot
        CV-CELL-MAX SWAP CV-INT!
    S" request_digest" 2 _LC1-wb-root-slot _LC1-wb-digest!
    S" documents" 3 _LC1-wb-root-slot _LC1-wb-documents!
    S" next" 4 _LC1-wb-root-slot _LC1-wb-cursor! ;

: _LC1-wb-build-read-request  ( schema-wide? -- )
    _LC1-wb-schema-wide ! 5 _LC1-wb-root-map
    S" collection" 0 _LC1-wb-root-slot _LC1-wb-resource!
    S" collection_domain_revision" 1 _LC1-wb-root-slot
        CV-CELL-MAX SWAP CV-INT!
    S" request_digest" 2 _LC1-wb-root-slot _LC1-wb-digest!
    S" resource" 3 _LC1-wb-root-slot _LC1-wb-resource!
    S" domain_revision" 4 _LC1-wb-root-slot
        CV-CELL-MAX SWAP CV-INT! ;

: _LC1-wb-build-read-result  ( schema-wide? -- )
    _LC1-wb-schema-wide ! 9 _LC1-wb-root-map
    S" collection" 0 _LC1-wb-root-slot _LC1-wb-resource!
    S" collection_domain_revision" 1 _LC1-wb-root-slot
        CV-CELL-MAX SWAP CV-INT!
    S" request_digest" 2 _LC1-wb-root-slot _LC1-wb-digest!
    S" resource" 3 _LC1-wb-root-slot _LC1-wb-resource!
    S" domain_revision" 4 _LC1-wb-root-slot
        CV-CELL-MAX SWAP CV-INT!
    S" text/markdown" 13
        S" media_type" 5 _LC1-wb-root-slot _LC1-wb-text!
    S" content_bytes" 6 _LC1-wb-root-slot
    _LC1-wb-schema-wide @ IF CV-CELL-MAX ELSE CV-MAX-STRING-LEN THEN
        SWAP CV-INT!
    S" content_digest" 7 _LC1-wb-root-slot _LC1-wb-digest!
    _LC1-wb-control @ CV-MAX-STRING-LEN
        S" content" 8 _LC1-wb-root-slot CV-STRING! _LC1-ok ;

: _LC1-wb-exact-encode  ( expected encoder-xt -- )
    _LC1-wb-encoder ! _LC1-wb-expected !
    _LC1-wb-root _LC1-wb-buffer @ _LC1-wb-expected @
        _LC1-wb-encoder @ EXECUTE
    _LC1-wb-ior ! _LC1-wb-length !
    _LC1-wb-ior @ 0= _LC1-assert
    _LC1-wb-length @ _LC1-wb-expected @ = _LC1-assert

    0xA5 _LC1-wb-buffer @ _LC1-wb-expected @ 1- + C!
    _LC1-wb-root _LC1-wb-buffer @ _LC1-wb-expected @ 1-
        _LC1-wb-encoder @ EXECUTE
    _LC1-wb-ior ! _LC1-wb-length !
    _LC1-wb-ior @ IVJSON-E-CAPACITY = _LC1-assert
    _LC1-wb-length @ 0= _LC1-assert
    _LC1-wb-buffer @ _LC1-wb-expected @ 1- + C@
        0xA5 = _LC1-assert ;

: _LC1-wb-bound-check  ( plain-max typed-max schema -- )
    >R
    _LC1-wb-root R@ CS-VALIDATE-DEEP 0= _LC1-assert
    SWAP ['] IVJSON-ENCODE _LC1-wb-exact-encode
    ['] IVJSON-TYPED-ENCODE _LC1-wb-exact-encode
    R> DROP _LC1-wb-root-free ;

: _LC1-wb-encoded-bounds  ( -- )
    0 _LC1-wb-build-query-request
    LIBRARY-DOCUMENT-QUERY-REQUEST-SEMANTIC-PLAIN-MAX
    LIBRARY-DOCUMENT-QUERY-REQUEST-SEMANTIC-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-QUERY CAP.IN-SCHEMA @ _LC1-wb-bound-check
    -1 _LC1-wb-build-query-request
    LIBRARY-DOCUMENT-QUERY-REQUEST-SCHEMA-PLAIN-MAX
    LIBRARY-DOCUMENT-QUERY-REQUEST-SCHEMA-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-QUERY CAP.IN-SCHEMA @ _LC1-wb-bound-check

    0 _LC1-wb-build-query-result
    LIBRARY-DOCUMENT-QUERY-RESULT-SEMANTIC-PLAIN-MAX
    LIBRARY-DOCUMENT-QUERY-RESULT-SEMANTIC-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-QUERY CAP.OUT-SCHEMA @ _LC1-wb-bound-check
    -1 _LC1-wb-build-query-result
    LIBRARY-DOCUMENT-QUERY-RESULT-SCHEMA-PLAIN-MAX
    LIBRARY-DOCUMENT-QUERY-RESULT-SCHEMA-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-QUERY CAP.OUT-SCHEMA @ _LC1-wb-bound-check

    0 _LC1-wb-build-read-request
    LIBRARY-DOCUMENT-READ-REQUEST-SEMANTIC-PLAIN-MAX
    LIBRARY-DOCUMENT-READ-REQUEST-SEMANTIC-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-READ CAP.IN-SCHEMA @ _LC1-wb-bound-check
    -1 _LC1-wb-build-read-request
    LIBRARY-DOCUMENT-READ-REQUEST-SCHEMA-PLAIN-MAX
    LIBRARY-DOCUMENT-READ-REQUEST-SCHEMA-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-READ CAP.IN-SCHEMA @ _LC1-wb-bound-check

    0 _LC1-wb-build-read-result
    LIBRARY-DOCUMENT-READ-RESULT-SEMANTIC-PLAIN-MAX
    LIBRARY-DOCUMENT-READ-RESULT-SEMANTIC-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @ _LC1-wb-bound-check
    -1 _LC1-wb-build-read-result
    LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-PLAIN-MAX
    LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-TYPED-MAX
    LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @ _LC1-wb-bound-check
    _LC1-stack ;

: _LC1-wb-decoded-sentinel!  ( -- )
    _LC1-wb-decoded CV-FREE 42 _LC1-wb-decoded CV-INT! ;

: _LC1-wb-decoded-sentinel?  ( -- flag )
    _LC1-wb-decoded CV-TYPE@ CV-T-INT =
    _LC1-wb-decoded CV-DATA@ 42 = AND ;

: _LC1-wb-bounded-decode  ( -- )
    -1 _LC1-wb-build-read-result
    _LC1-wb-root _LC1-wb-buffer @
        LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-PLAIN-MAX
        IVJSON-ENCODE
    _LC1-wb-ior ! _LC1-wb-length !
    _LC1-wb-ior @ 0= _LC1-assert
    _LC1-wb-length @
        LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-PLAIN-MAX = _LC1-assert

    _LC1-wb-decoded-sentinel!
    _LC1-wb-buffer @ _LC1-wb-length @
        LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @ _LC1-wb-decoded
        IVJSON-DECODE-AS IVJSON-E-INVALID = _LC1-assert
    _LC1-wb-decoded-sentinel? _LC1-assert

    _LC1-wb-buffer @ _LC1-wb-length @ _LC1-wb-length @ 1-
        LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @ _LC1-wb-decoded
        IVJSON-DECODE-AS-LIMIT IVJSON-E-INVALID = _LC1-assert
    _LC1-wb-decoded-sentinel? _LC1-assert

    _LC1-wb-buffer @ _LC1-wb-length @ _LC1-wb-length @
        LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @ _LC1-wb-decoded
        IVJSON-DECODE-AS-LIMIT _LC1-ok
    _LC1-wb-decoded LIBRARY-CAP-DOCUMENT-READ CAP.OUT-SCHEMA @
        CS-VALIDATE-DEEP 0= _LC1-assert
    S" content" _LC1-wb-decoded CV-MAP-FIND
        DUP 0<> _LC1-assert
        DUP CV-TYPE@ CV-T-STRING = _LC1-assert
        CV-LEN@ CV-MAX-STRING-LEN = _LC1-assert
    _LC1-wb-root-free _LC1-wb-decoded CV-FREE
    _LC1-stack ;

: _LC1-WIRE-BOUND-RUN  ( -- )
    0 _LC1-checks ! 0 _LC1-fails !
    DEPTH _LC1-depth !
    ." LIBRARY WIRE BOUNDS PHASE SETUP" CR _LC1-flush
    _LC1-wb-buffers-allocate
    0x41 _LC1-wb-rid _LC1-id!
    _LC1-wb-rid _LC1-wb-hex SHA3-256->HEX
        SHA3-256-HEX-LEN = _LC1-assert
    LIBRARY-APPLET-CAPABILITIES-SETUP
    JSON-MAX-DOCUMENT 65536 = _LC1-assert
    LIBRARY-DOCUMENT-QUERY-RESULT-SCHEMA-PLAIN-MAX
        JSON-MAX-DOCUMENT > _LC1-assert
    LIBRARY-DOCUMENT-READ-RESULT-SCHEMA-PLAIN-MAX
        JSON-MAX-DOCUMENT > _LC1-assert
    ." LIBRARY WIRE BOUNDS PHASE ENCODE" CR _LC1-flush
    _LC1-wb-encoded-bounds
    ." LIBRARY WIRE BOUNDS PHASE DECODE" CR _LC1-flush
    _LC1-wb-bounded-decode
    ." LIBRARY WIRE BOUNDS PHASE CLEANUP" CR _LC1-flush
    _LC1-wb-buffers-free
    _LC1-stack
    _LC1-fails @ ?DUP IF
        ." LIBRARY WIRE BOUNDS FAIL " .
        ." / " _LC1-checks @ . CR
    ELSE
        ." LIBRARY WIRE BOUNDS PASS " _LC1-checks @ . CR
    THEN
    _LC1-flush ;

: _LC1-RUN  ( -- )
    0 _LC1-checks ! 0 _LC1-fails !
    DEPTH _LC1-outer-depth !
    _LC1-desc LIBRARY-APPLET-ENTRY
    ['] _LC1-shell-init _LC1-desc APP.INIT-XT !
    _LC1-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _LC1-assert
    _LC1-outer-stack
    _LC1-fails @ ?DUP IF
        ." LIBRARY CAPABILITY L1 FAIL " .
        ." / " _LC1-checks @ . CR
    ELSE
        ." LIBRARY CAPABILITY L1 PASS " _LC1-checks @ . CR
    THEN
    _LC1-flush ;

: _LC1-BOUNDARY-RUN  ( -- )
    0 _LC1-checks ! 0 _LC1-fails !
    DEPTH _LC1-outer-depth !
    \ Source loading has already completed from MP64FS.  The focused source
    \ image has only 4,430 free sectors and MP64FS itself tops out at 8,192;
    \ its copy-on-write files cannot hold both boundary documents.  Run this
    \ storage-heavy semantic profile on the same 32 MiB RAM-VFS contract used
    \ by Library's retained-restore qualification, while the core/UI profiles
    \ continue to exercise the platform VFS.
    VFS-CUR _LC1-boundary-old-vfs !
    33554432 A-XMEM ARENA-NEW
    DUP 0= _LC1-assert DROP _LC1-boundary-arena !
    _LC1-boundary-arena @ VFS-RAM-BINDING 0 VFS-NEW
        _LC1-boundary-ior ! _LC1-boundary-vfs !
    _LC1-boundary-ior @ 0= _LC1-assert
    _LC1-boundary-vfs @ 0<> _LC1-assert
    _LC1-boundary-vfs @ VFS-USE
    _LC1-desc LIBRARY-APPLET-ENTRY
    ['] _LC1-boundary-shell-init _LC1-desc APP.INIT-XT !
    \ The boundary runner does not exercise rendering.  Avoid asking the RAM
    \ VFS for the UIDL resource that was already source-packaged on MP64FS.
    0 _LC1-desc APP.UIDL-FILE-A !
    0 _LC1-desc APP.UIDL-FILE-U !
    _LC1-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _LC1-assert
    _LC1-boundary-old-vfs @ VFS-USE
    _LC1-boundary-vfs @ VFS-DESTROY
    _LC1-boundary-arena @ ARENA-DESTROY
    0 _LC1-boundary-vfs ! 0 _LC1-boundary-arena !
    _LC1-outer-stack
    _LC1-fails @ ?DUP IF
        ." LIBRARY CAPABILITY BOUNDARY L1 FAIL " .
        ." / " _LC1-checks @ . CR
    ELSE
        ." LIBRARY CAPABILITY BOUNDARY L1 PASS " _LC1-checks @ . CR
    THEN
    _LC1-flush ;

: _LC1-CREATE-BOUNDARY-RUN  ( -- )
    0 _LC1-checks ! 0 _LC1-fails !
    DEPTH _LC1-outer-depth !
    _LC1-desc LIBRARY-APPLET-ENTRY
    ['] _LC1-create-boundary-shell-init _LC1-desc APP.INIT-XT !
    _LC1-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _LC1-assert
    _LC1-outer-stack
    _LC1-fails @ ?DUP IF
        ." LIBRARY CAPABILITY CREATE BOUNDARY L1 FAIL " .
        ." / " _LC1-checks @ . CR
    ELSE
        ." LIBRARY CAPABILITY CREATE BOUNDARY L1 PASS " _LC1-checks @ . CR
    THEN
    _LC1-flush ;
