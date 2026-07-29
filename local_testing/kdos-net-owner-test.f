\ Focused contracts for the shared core-0 KDOS network owner.
PROVIDED akashic-kdos-net-owner-test

VARIABLE _knot-fails
VARIABLE _knot-checks
VARIABLE _knot-depth

CREATE _knot-token-a 8 ALLOT
CREATE _knot-token-b 8 ALLOT

: _knot-assert  ( flag -- )
    1 _knot-checks +!
    0= IF
        1 _knot-fails +!
        ." KDOS NET OWNER ASSERT " _knot-checks @ . CR
    THEN ;

: _knot-stack  ( -- )
    DEPTH DUP _knot-depth @ <> IF
        ." KDOS NET OWNER STACK "
        _knot-depth @ . ." -> " DUP . CR .S CR
    THEN
    _knot-depth @ = _knot-assert ;

: _KNOT-RUN  ( -- )
    0 _knot-fails !
    0 _knot-checks !
    DEPTH _knot-depth !
    COREID 0= _knot-assert
    KDOSNET-OWNER@ 0= _knot-assert
    0 KDOSNET-CLAIM KDOSNET-S-INVALID = _knot-assert
    -1 KDOSNET-CLAIM KDOSNET-S-OK = _knot-assert
    KDOSNET-OWNER@ -1 = _knot-assert
    -1 KDOSNET-OWNER? _knot-assert
    -1 KDOSNET-RELEASE KDOSNET-S-OK = _knot-assert

    _knot-token-a KDOSNET-CLAIM
        KDOSNET-S-OK = _knot-assert
    KDOSNET-OWNER@ _knot-token-a = _knot-assert
    _knot-token-a KDOSNET-OWNER? _knot-assert
    _knot-token-a KDOSNET-OPERATE? _knot-assert
    _knot-token-b KDOSNET-OWNER? 0= _knot-assert
    _knot-token-b KDOSNET-OPERATE? 0= _knot-assert
    _knot-token-a KDOSNET-CLAIM
        KDOSNET-S-BUSY = _knot-assert
    _knot-token-b KDOSNET-CLAIM
        KDOSNET-S-BUSY = _knot-assert

    0 KDOSNET-RELEASE KDOSNET-S-INVALID = _knot-assert
    _knot-token-b KDOSNET-RELEASE
        KDOSNET-S-NOT-OWNER = _knot-assert
    KDOSNET-OWNER@ _knot-token-a = _knot-assert
    _knot-token-a KDOSNET-OWNER? _knot-assert

    _knot-token-a KDOSNET-RELEASE
        KDOSNET-S-OK = _knot-assert
    KDOSNET-OWNER@ 0= _knot-assert
    _knot-token-a KDOSNET-OWNER? 0= _knot-assert
    _knot-token-a KDOSNET-OPERATE? 0= _knot-assert
    _knot-token-a KDOSNET-RELEASE
        KDOSNET-S-NOT-OWNER = _knot-assert
    _knot-stack

    _knot-fails @ IF
        ." KDOS NET OWNER FAIL " _knot-fails @ .
        ." / " _knot-checks @ . CR
    ELSE
        ." KDOS NET OWNER PASS " _knot-checks @ . CR
    THEN ;
