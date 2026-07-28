\ Focused machine contracts for the caller-owned form body writer.

PROVIDED akashic-fuew-contracts

VARIABLE _fuewt-checks
VARIABLE _fuewt-fails
VARIABLE _fuewt-depth

CREATE _fuewt-writer-storage FUEW-SIZE 7 + ALLOT
CREATE _fuewt-body 256 ALLOT
CREATE _fuewt-other-body 128 ALLOT
CREATE _fuewt-small 16 ALLOT
CREATE _fuewt-alias 96 ALLOT
CREATE _fuewt-overlap-storage FUEW-SIZE 64 + 7 + ALLOT
CREATE _fuewt-adjacent-storage FUEW-SIZE 64 + 7 + ALLOT

: _fuewt-writer  ( -- address )
    _fuewt-writer-storage 7 + -8 AND ;

: _fuewt-overlap  ( -- address )
    _fuewt-overlap-storage 7 + -8 AND ;

: _fuewt-adjacent  ( -- address )
    _fuewt-adjacent-storage 7 + -8 AND ;

: _fuewt-assert  ( flag -- )
    1 _fuewt-checks +!
    0= IF
        1 _fuewt-fails +!
        ." FORM WRITER ASSERT " _fuewt-checks @ . CR
    THEN ;

: _fuewt-status  ( actual expected -- )
    2DUP <> IF
        ." FORM WRITER STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _fuewt-assert ;

: _fuewt-stack  ( -- )
    DEPTH DUP _fuewt-depth @ <> IF
        ." FORM WRITER STACK "
        _fuewt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _fuewt-depth @ = _fuewt-assert ;

: _fuewt-filled?  ( address length byte -- flag )
    BEGIN OVER WHILE
        2 PICK C@ OVER <> IF
            2DROP DROP 0 EXIT
        THEN
        >R 1- SWAP 1+ SWAP R>
    REPEAT
    2DROP DROP -1 ;

: _fuewt-zero?  ( address length -- flag )
    0 _fuewt-filled? ;

: _fuewt-building?  ( writer -- flag )
    FUEW-STATE@
    FUEW-S-OK = SWAP FUEW-STATE-BUILDING = AND ;

: _fuewt-length=  ( expected writer -- flag )
    FUEW-LENGTH@
    FUEW-S-OK = >R = R> AND ;

: _fuewt-count=  ( expected writer -- flag )
    FUEW-FIELD-COUNT@
    FUEW-S-OK = >R = R> AND ;

: _fuewt-body=  ( expected-a expected-u writer -- flag )
    FUEW-BODY@
    FUEW-S-OK <> IF
        2DROP 2DROP 0 EXIT
    THEN
    2SWAP COMPARE 0= ;

: _fuewt-test-vocabulary-and-shape  ( -- )
    -1 FUEW-STATUS-VALID? 0= _fuewt-assert
    FUEW-S-INTERNAL FUEW-STATUS-VALID? _fuewt-assert
    FUEW-S-INTERNAL 1+ FUEW-STATUS-VALID? 0= _fuewt-assert
    FUEW-SIZE 48 = _fuewt-assert

    _fuewt-writer FUEW-SIZE 0xA5 FILL
    _fuewt-body 32 0xA5 FILL
    0 1 _fuewt-writer FUEW-INIT
        FUEW-S-INVALID _fuewt-status
    _fuewt-writer FUEW-SIZE 0xA5 _fuewt-filled? _fuewt-assert
    _fuewt-body 32 0xA5 _fuewt-filled? _fuewt-assert

    _fuewt-body -1 _fuewt-writer FUEW-INIT
        FUEW-S-INVALID _fuewt-status
    _fuewt-writer FUEW-SIZE 0xA5 _fuewt-filled? _fuewt-assert

    _fuewt-body 32 _fuewt-writer 1+ FUEW-INIT
        FUEW-S-INVALID _fuewt-status
    _fuewt-writer FUEW-SIZE 0xA5 _fuewt-filled? _fuewt-assert

    _fuewt-overlap FUEW-SIZE 64 + 0xA5 FILL
    _fuewt-overlap 8 + 64 _fuewt-overlap FUEW-INIT
        FUEW-S-ALIAS _fuewt-status
    _fuewt-overlap FUEW-SIZE 64 + 0xA5
        _fuewt-filled? _fuewt-assert
    _fuewt-stack ;

: _fuewt-test-empty-lifecycle  ( -- )
    \ A null address is valid when the complete arena has zero capacity.
    0 0 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    _fuewt-writer FUEW-SEAL FUEW-S-OK _fuewt-status
    0 0 _fuewt-writer _fuewt-body= _fuewt-assert
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status

    _fuewt-writer FUEW-SIZE 0xA5 FILL
    _fuewt-body 64 0xA5 FILL
    _fuewt-body 64 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    _fuewt-writer FUEW-VALID? _fuewt-assert
    _fuewt-writer _fuewt-building? _fuewt-assert
    0 _fuewt-writer _fuewt-length= _fuewt-assert
    0 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-body 64 _fuewt-zero? _fuewt-assert

    _fuewt-writer FUEW-BODY@
        FUEW-S-STATE _fuewt-status
        0= _fuewt-assert
        0= _fuewt-assert

    _fuewt-writer FUEW-SEAL FUEW-S-OK _fuewt-status
    _fuewt-writer FUEW-STATE@
        FUEW-S-OK _fuewt-status
        FUEW-STATE-SEALED = _fuewt-assert
    0 0 _fuewt-writer _fuewt-body= _fuewt-assert
    _fuewt-writer FUEW-SEAL FUEW-S-STATE _fuewt-status
    S" x" S" y" _fuewt-writer FUEW-FIELD
        FUEW-S-STATE _fuewt-status

    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-body 64 _fuewt-zero? _fuewt-assert
    _fuewt-writer FUEW-SIZE _fuewt-zero? _fuewt-assert
    _fuewt-writer FUEW-VALID? 0= _fuewt-assert
    _fuewt-writer FUEW-WIPE FUEW-S-INVALID _fuewt-status
    _fuewt-stack ;

: _fuewt-test-canonical-body  ( -- )
    _fuewt-body 256 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" client id" S" a+b/c%" _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status
    S" scope" S" atproto transition:generic"
        _fuewt-writer FUEW-FIELD FUEW-S-OK _fuewt-status
    0 0 0 0 _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status
    3 _fuewt-writer _fuewt-count= _fuewt-assert

    _fuewt-writer FUEW-SEAL FUEW-S-OK _fuewt-status
    S" client+id=a%2Bb%2Fc%25&scope=atproto+transition%3Ageneric&="
        _fuewt-writer _fuewt-body= _fuewt-assert
    _fuewt-writer FUEW-BODY@ DROP
        2DUP + _fuewt-body 256 + U< _fuewt-assert
        2DROP

    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-body 256 _fuewt-zero? _fuewt-assert
    _fuewt-stack ;

: _fuewt-test-transactional-capacity  ( -- )
    _fuewt-small 8 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" a" S" b" _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status
    3 _fuewt-writer _fuewt-length= _fuewt-assert
    1 _fuewt-writer _fuewt-count= _fuewt-assert

    S" long" S" value" _fuewt-writer FUEW-FIELD
        FUEW-S-CAPACITY _fuewt-status
    _fuewt-writer _fuewt-building? _fuewt-assert
    3 _fuewt-writer _fuewt-length= _fuewt-assert
    1 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-small 3 S" a=b" COMPARE 0= _fuewt-assert
    _fuewt-small 3 + 5 _fuewt-zero? _fuewt-assert

    0 0 0 0 _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status
    5 _fuewt-writer _fuewt-length= _fuewt-assert
    2 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-writer FUEW-SEAL FUEW-S-OK _fuewt-status
    S" a=b&=" _fuewt-writer _fuewt-body= _fuewt-assert
    _fuewt-small 5 + 3 _fuewt-zero? _fuewt-assert
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-small 8 _fuewt-zero? _fuewt-assert
    _fuewt-stack ;

: _fuewt-test-alias-and-adjacency  ( -- )
    _fuewt-alias 64 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" x" S" y" _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status

    _fuewt-alias 1 S" z" _fuewt-writer FUEW-FIELD
        FUEW-S-ALIAS _fuewt-status
    [CHAR] q _fuewt-alias 32 + C!
    _fuewt-alias 32 + 1 S" z" _fuewt-writer FUEW-FIELD
        FUEW-S-ALIAS _fuewt-status
    _fuewt-writer 1 S" z" _fuewt-writer FUEW-FIELD
        FUEW-S-ALIAS _fuewt-status
    3 _fuewt-writer _fuewt-length= _fuewt-assert
    1 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-alias 3 S" x=y" COMPARE 0= _fuewt-assert

    S" same" 2DUP _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status

    \ Arena immediately after the descriptor.
    _fuewt-adjacent FUEW-SIZE +
    32 _fuewt-adjacent FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" a" S" b" _fuewt-adjacent FUEW-FIELD
        FUEW-S-OK _fuewt-status
    _fuewt-adjacent FUEW-WIPE FUEW-S-OK _fuewt-status

    \ Arena immediately before the descriptor.
    _fuewt-adjacent 32
    _fuewt-adjacent 32 + FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" a" S" b" _fuewt-adjacent 32 + FUEW-FIELD
        FUEW-S-OK _fuewt-status
    _fuewt-adjacent 32 + FUEW-WIPE FUEW-S-OK _fuewt-status

    \ A source span exactly adjacent to the complete arena is admitted.
    [CHAR] n _fuewt-adjacent 32 + C!
    _fuewt-adjacent 32 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    _fuewt-adjacent 32 + 1 S" v"
        _fuewt-writer FUEW-FIELD FUEW-S-OK _fuewt-status
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-stack ;

: _fuewt-test-invalid-sources  ( -- )
    _fuewt-body 64 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    0 1 S" value" _fuewt-writer FUEW-FIELD
        FUEW-S-INVALID _fuewt-status
    S" name" 0 1 _fuewt-writer FUEW-FIELD
        FUEW-S-INVALID _fuewt-status
    _fuewt-body -1 S" value" _fuewt-writer FUEW-FIELD
        FUEW-S-INVALID _fuewt-status
    0 _fuewt-writer _fuewt-length= _fuewt-assert
    0 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-body 64 _fuewt-zero? _fuewt-assert
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-stack ;

: _fuewt-test-internal-mismatch-rollback  ( -- )
    _fuewt-body 64 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" x" S" y" _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status

    \ The private commit helper normally receives its exact total from
    \ geometry.  Supplying six instead of the actual four-byte "&a=b"
    \ contribution deterministically forces its internal invariant branch
    \ without modifying the base component encoder.
    S" a" S" b" _fuewt-writer 6 _FUEW-FIELD-COMMIT
        FUEW-S-INTERNAL _fuewt-status
    3 _fuewt-writer _fuewt-length= _fuewt-assert
    1 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-body 3 S" x=y" COMPARE 0= _fuewt-assert
    _fuewt-body 3 + 6 _fuewt-zero? _fuewt-assert

    S" a" S" b" _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status
    _fuewt-writer FUEW-SEAL FUEW-S-OK _fuewt-status
    S" x=y&a=b" _fuewt-writer _fuewt-body= _fuewt-assert
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-stack ;

: _fuewt-test-reinitialize-and-corruption  ( -- )
    _fuewt-body 64 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    S" verifier" S" secret-value" _fuewt-writer FUEW-FIELD
        FUEW-S-OK _fuewt-status

    \ Prospective geometry is admitted before a live writer is cleared.
    \ A rejected replacement therefore preserves the existing transaction.
    0 1 _fuewt-writer FUEW-INIT
        FUEW-S-INVALID _fuewt-status
    _fuewt-writer _fuewt-building? _fuewt-assert
    21 _fuewt-writer _fuewt-length= _fuewt-assert
    1 _fuewt-writer _fuewt-count= _fuewt-assert
    _fuewt-body 21 S" verifier=secret-value"
        COMPARE 0= _fuewt-assert

    _fuewt-other-body 64 0xA5 FILL
    _fuewt-other-body 64 _fuewt-writer FUEW-INIT
        FUEW-S-OK _fuewt-status
    _fuewt-body 64 _fuewt-zero? _fuewt-assert
    _fuewt-other-body 64 _fuewt-zero? _fuewt-assert
    0 _fuewt-writer _fuewt-length= _fuewt-assert

    65 _fuewt-writer FUEW.LENGTH !
    _fuewt-writer FUEW-VALID? 0= _fuewt-assert
    _fuewt-writer FUEW-SEAL FUEW-S-INVALID _fuewt-status
    _fuewt-writer FUEW-WIPE FUEW-S-INVALID _fuewt-status
    _fuewt-other-body 64 _fuewt-zero? _fuewt-assert
    _fuewt-body 32 0xA5 FILL
    _fuewt-body 32 _fuewt-writer FUEW-INIT
        FUEW-S-INVALID _fuewt-status
    _fuewt-body 32 0xA5 _fuewt-filled? _fuewt-assert
    _fuewt-other-body 64 _fuewt-zero? _fuewt-assert

    0 _fuewt-writer FUEW.LENGTH !
    _fuewt-writer FUEW-VALID? _fuewt-assert
    _fuewt-writer FUEW-WIPE FUEW-S-OK _fuewt-status
    _fuewt-stack ;

: _FUEWT-RUN  ( -- )
    0 _fuewt-checks !
    0 _fuewt-fails !
    DEPTH _fuewt-depth !
    _fuewt-test-vocabulary-and-shape
    _fuewt-test-empty-lifecycle
    _fuewt-test-canonical-body
    _fuewt-test-transactional-capacity
    _fuewt-test-alias-and-adjacency
    _fuewt-test-invalid-sources
    _fuewt-test-internal-mismatch-rollback
    _fuewt-test-reinitialize-and-corruption
    _fuewt-fails @ IF
        ." FORM WRITER FAIL checks/fails "
        _fuewt-checks @ . _fuewt-fails @ . CR
    ELSE
        ." FORM WRITER PASS checks "
        _fuewt-checks @ . CR
    THEN ;
