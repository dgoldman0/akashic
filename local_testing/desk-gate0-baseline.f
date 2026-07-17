\ Deterministic reader-side verification for the retained Desk Gate 0 bytes.
\ Load streams.f first so the production MP64FS binding and complete Streams
\ lifecycle are available.  The harness injects the frozen records read-only
\ into the boot image; this leaf never regenerates or rewrites them.

PROVIDED desk-gate0-baseline-tests

VARIABLE _dg0-fails
VARIABLE _dg0-checks
VARIABLE _dg0-depth
VARIABLE _dg0-source-registry
VARIABLE _dg0-checkpoint
VARIABLE _dg0-instance
VARIABLE _dg0-observation
VARIABLE _dg0-text-u
VARIABLE _dg0-revision
VARIABLE _dg0-status
VARIABLE _dg0-byte

CREATE _dg0-source-store STREAMS-SOURCE-STORE-SIZE ALLOT
CREATE _dg0-observation-store STREAMS-OBSERVATION-STORE-SIZE ALLOT
CREATE _dg0-draft-store STREAMS-DRAFT-STORE-SIZE ALLOT
CREATE _dg0-draft-text STREAMS-DRAFT-TEXT-MAX ALLOT
CREATE _dg0-source-rid RID-SIZE ALLOT

: _dg0-assert  ( flag -- )
    1 _dg0-checks +! 0= IF
        1 _dg0-fails +! ." DESK GATE0 ASSERT " _dg0-checks @ . CR
    THEN ;

: _dg0-stack  ( -- ) DEPTH _dg0-depth @ = _dg0-assert ;

: _dg0-allocate  ( size variable -- )
    >R ALLOCATE ABORT" DESK GATE0 BASELINE FAIL allocation" R> ! ;

: _dg0-filled?  ( a u byte -- flag )
    _dg0-byte ! 0 ?DO
        DUP I + C@ _dg0-byte @ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;

: _dg0-source-init  ( path-a path-u -- )
    VFS-CUR _dg0-source-store STREAMS-SOURCE-STORE-INIT-AT
        SSSTORE-S-OK = _dg0-assert ;

: _dg0-source-load  ( -- status )
    _dg0-source-registry @ STREAMS-SOURCE-REGISTRY-SIZE
        _dg0-source-store STREAMS-SOURCE-STORE-LOAD ;

: _dg0-observation-init  ( path-a path-u -- )
    VFS-CUR _dg0-observation-store STREAMS-OBSERVATION-STORE-INIT-AT
        OSTORE-S-OK = _dg0-assert ;

: _dg0-observation-load  ( -- status )
    _dg0-checkpoint @ STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _dg0-observation-store STREAMS-OBSERVATION-STORE-LOAD ;

: _dg0-test-source-records  ( -- )
    S" /gate0/s-valid.bin" _dg0-source-init
    _dg0-source-load SSSTORE-S-OK = _dg0-assert
    _dg0-source-store STREAMS-SOURCE-STORE-BLOCKED? 0= _dg0-assert
    _dg0-source-registry @ STREAMS-SOURCE-REGISTRY-VALID? _dg0-assert
    _dg0-source-registry @ SSREG.GENERATION @ 1 = _dg0-assert
    _dg0-source-registry @ STREAMS-SOURCE-COUNT 1 = _dg0-assert
    0 _dg0-source-registry @ STREAMS-SOURCE-NTH DUP 0<> _dg0-assert
    DUP STREAMS-SOURCE-VALID? _dg0-assert
    DUP SSOURCE.REVISION @ 1 = _dg0-assert
    DUP SSOURCE.ID @ 0x101 = _dg0-assert
    DUP STREAMS-SOURCE-LABEL$ S" Gate 0 feed" STR-STR= _dg0-assert
    STREAMS-SOURCE-ENDPOINT$ S" https://example.test/gate0.json"
        STR-STR= _dg0-assert

    _dg0-source-registry @ STREAMS-SOURCE-REGISTRY-SIZE 90 FILL
    S" /gate0/s-corrupt.bin" _dg0-source-init
    _dg0-source-load SSSTORE-S-CORRUPT = _dg0-assert
    _dg0-source-store STREAMS-SOURCE-STORE-BLOCKED? _dg0-assert
    _dg0-source-registry @ STREAMS-SOURCE-REGISTRY-SIZE 90
        _dg0-filled? _dg0-assert

    _dg0-source-registry @ STREAMS-SOURCE-REGISTRY-SIZE 90 FILL
    S" /gate0/s-future.bin" _dg0-source-init
    _dg0-source-load SSSTORE-S-UNSUPPORTED = _dg0-assert
    _dg0-source-store STREAMS-SOURCE-STORE-BLOCKED? _dg0-assert
    _dg0-source-registry @ STREAMS-SOURCE-REGISTRY-SIZE 90
        _dg0-filled? _dg0-assert
    _dg0-stack ;

: _dg0-test-observation-records  ( -- )
    S" /gate0/o-valid.bin" _dg0-observation-init
    _dg0-observation-load OSTORE-S-OK = _dg0-assert
    _dg0-observation-store STREAMS-OBSERVATION-STORE-BLOCKED? 0=
        _dg0-assert
    _dg0-checkpoint @ OCHK-VALID? _dg0-assert
    _dg0-checkpoint @ OCHK.GENERATION @ 2 = _dg0-assert
    _dg0-checkpoint @ OCHK.SOURCE-COUNT @ 1 = _dg0-assert
    _dg0-checkpoint @ OCHK.OBSERVATION-COUNT @ 1 = _dg0-assert
    _dg0-checkpoint @ OCHK.KEY-COUNT @ 1 = _dg0-assert
    0 _dg0-checkpoint @ OCHK-OBSERVATION-NTH
        DUP _dg0-observation ! 0<> _dg0-assert
    _dg0-observation @ OCO.REVISION @ 1 = _dg0-assert
    _dg0-observation @ _dg0-checkpoint @ OCHK-OBSERVATION-TITLE$
        S" Gate 0 observation" STR-STR= _dg0-assert
    _dg0-observation @ _dg0-checkpoint @ OCHK-OBSERVATION-CONTENT$
        S" Exact retained body" STR-STR= _dg0-assert
    _dg0-source-rid RID-CLEAR 0x101 _dg0-source-rid !
    _dg0-source-rid _dg0-checkpoint @ OCHK-SOURCE-FIND
        DUP 0<> _dg0-assert
    DUP OCS.STATE @ OCHK-ATTEMPT-SUCCEEDED = _dg0-assert
    DUP OCS.STARTED-MS @ 1000 = _dg0-assert
    OCS.FINISHED-MS @ 1001 = _dg0-assert

    _dg0-checkpoint @ STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    S" /gate0/o-corrupt.bin" _dg0-observation-init
    _dg0-observation-load OSTORE-S-CORRUPT = _dg0-assert
    _dg0-observation-store STREAMS-OBSERVATION-STORE-BLOCKED? _dg0-assert
    _dg0-checkpoint @ STREAMS-OBSERVATION-CHECKPOINT-SIZE 90
        _dg0-filled? _dg0-assert

    _dg0-checkpoint @ STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    S" /gate0/o-future.bin" _dg0-observation-init
    _dg0-observation-load OSTORE-S-UNSUPPORTED = _dg0-assert
    _dg0-observation-store STREAMS-OBSERVATION-STORE-BLOCKED? _dg0-assert
    _dg0-checkpoint @ STREAMS-OBSERVATION-CHECKPOINT-SIZE 90
        _dg0-filled? _dg0-assert
    _dg0-stack ;

: _dg0-test-legacy-draft  ( -- )
    S" /gate0/d-legacy.bin" VFS-CUR _dg0-draft-store
        STREAMS-DRAFT-STORE-INIT-AT SDSTORE-S-OK = _dg0-assert
    _dg0-draft-text STREAMS-DRAFT-TEXT-MAX _dg0-draft-store
        STREAMS-DRAFT-STORE-LOAD
    _dg0-status ! _dg0-revision ! _dg0-text-u !
    _dg0-status @ SDSTORE-S-OK = _dg0-assert
    _dg0-revision @ 7 = _dg0-assert
    _dg0-draft-text _dg0-text-u @ S" exact ☂ café" STR-STR=
        _dg0-assert
    _dg0-stack ;

: _dg0-test-missing-observation-companion  ( -- )
    S" /streams-sources.bin" VFS-CUR VFS-RESOLVE 0<> _dg0-assert
    S" /streams-observation.bin" VFS-CUR VFS-RESOLVE 0= _dg0-assert
    _STREAMS-COMP-SETUP
    STREAMS-COMP-DESC CINST-NEW DUP 0= _dg0-assert DROP
        _dg0-instance !
    _dg0-instance @ STREAMS-INIT-CB
    _STM-SOURCE-READY? _dg0-assert
    _STM-SOURCE-STORE-STATUS @ SSSTORE-S-OK = _dg0-assert
    _STM-SOURCE-REGISTRY SSREG.GENERATION @ 1 = _dg0-assert
    _STM-SOURCE-REGISTRY STREAMS-SOURCE-COUNT 1 = _dg0-assert
    _STM-CONFIGURED-INIT-STATUS @ SREF-S-OK = _dg0-assert
    _STM-CONFIGURED-REFRESH STREAMS-REFRESH-OWNER-VALID? _dg0-assert
    _STM-CONFIGURED-REFRESH SREF.STORE-STATUS @ OSTORE-S-ABSENT =
        _dg0-assert
    _STM-CONFIGURED-REFRESH SREF.LIVE @ DUP OCHK-VALID? _dg0-assert
    DUP OCHK.GENERATION @ 0= _dg0-assert
    OCHK.SOURCE-COUNT @ 0= _dg0-assert
    0 _STM-SOURCE-REGISTRY STREAMS-SOURCE-NTH
        _STM-SOURCE-ACQUISITION-STATE$ S" never refreshed" STR-STR=
        _dg0-assert
    S" /streams-observation.bin" VFS-CUR VFS-RESOLVE 0= _dg0-assert
    _dg0-instance @ CINST-FREE 0 _dg0-instance !
    _dg0-stack ;

: _dg0-run  ( -- )
    0 _dg0-fails ! 0 _dg0-checks ! DEPTH _dg0-depth !
    VFS-CUR 0<> _dg0-assert
    STREAMS-SOURCE-REGISTRY-SIZE _dg0-source-registry _dg0-allocate
    STREAMS-OBSERVATION-CHECKPOINT-SIZE _dg0-checkpoint _dg0-allocate
    _dg0-test-source-records
    _dg0-test-observation-records
    _dg0-test-legacy-draft
    _dg0-test-missing-observation-companion
    _dg0-source-registry @ FREE 0 _dg0-source-registry !
    _dg0-checkpoint @ FREE 0 _dg0-checkpoint !
    _dg0-stack
    _dg0-fails @ 0= IF
        ." DESK GATE0 BASELINE PASS " _dg0-checks @ . CR
    ELSE
        ." DESK GATE0 BASELINE FAIL " _dg0-fails @ . ." / "
            _dg0-checks @ . CR
    THEN ;
