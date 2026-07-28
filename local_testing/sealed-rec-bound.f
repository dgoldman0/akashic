\ sealed-rec-bound.f - Resolver, rejection, and cleanup contracts

PROVIDED sealed-record-bound-test

: _srt-test-resolver-contracts  ( -- )
    _srt-record 208 0xA5 FILL
    ['] _srt-no-key-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-KEY = _srt-assert
    0= _srt-assert
    _srt-record 208 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-record 208 0xA5 FILL
    ['] _srt-extra-result-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-CALLBACK = _srt-assert
    0= _srt-assert
    _srt-record 208 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-record 208 0xA5 FILL
    ['] _srt-missing-result-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-CALLBACK = _srt-assert
    0= _srt-assert
    _srt-record 208 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-record 208 0xA5 FILL
    ['] _srt-substituted-context-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-CALLBACK = _srt-assert
    0= _srt-assert
    _srt-record 208 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    0 _srt-nested-status !
    ['] _srt-recursive-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-KEY = _srt-assert
    0= _srt-assert
    _srt-nested-status @ SEALED-RECORD-S-BUSY = _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-stack ;

: _srt-test-rejections  ( -- )
    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE 0xA5 FILL
    ['] _srt-resolver _srt-base
    _srt-plain 32 _srt-plain 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-ALIAS = _srt-assert
    0= _srt-assert
    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE
        0xA5 _srt-filled? _srt-assert

    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE 0xA5 FILL
    ['] _srt-resolver _srt-base
    _srt-record 208 _srt-output 64 _srt-io
    _srt-record 96 +
        _srt-descriptor SEALED-RECORD-D.RECORD-ID !
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-ALIAS = _srt-assert
    0= _srt-assert
    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE
        0xA5 _srt-filled? _srt-assert

    _srt-workspace SEALED-RECORD-WORKSPACE-CLEAR DROP
    ['] _srt-resolver _srt-base
    _srt-plain 32 _srt-record 207 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-CAPACITY = _srt-assert
    0= _srt-assert

    ['] _srt-resolver _srt-base
    _srt-plain 32
    EXT-MEM-BASE EXT-MEM-SIZE + 1- 2 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-RANGE = _srt-assert
    0= _srt-assert

    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE 0xA5 FILL
    _SR-WORKSPACE-BUSY
        _srt-workspace _SR-W-RESERVED + !
    ['] _srt-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-BUSY = _srt-assert
    0= _srt-assert
    _srt-workspace _SR-W-RESERVED + @
        _SR-WORKSPACE-BUSY = _srt-assert
    _srt-workspace SEALED-RECORD-WORKSPACE-CLEAR
        SEALED-RECORD-S-OK = _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-stack ;

: _srt-open-publication-rethrow  ( -- )
    _srt-workspace -3201
        ['] _SR-WIPE-OPEN-OUTPUT
        _SR-RETHROW-AFTER-CLEANUPS ;

: _srt-seal-publication-rethrow  ( -- )
    _srt-workspace -3202
        ['] _SR-INVALIDATE-SEAL-OUTPUT
        _SR-RETHROW-AFTER-CLEANUPS ;

: _srt-output-cleanup-throw  ( workspace -- )
    DROP -3203 THROW ;

: _srt-cleanup-precedence-rethrow  ( -- )
    _srt-workspace -3204
        ['] _srt-output-cleanup-throw
        _SR-RETHROW-AFTER-CLEANUPS ;

: _srt-test-publication-cleanup  ( -- )
    _srt-output 64 0xA5 FILL
    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE 0x5A FILL
    _srt-output _srt-workspace _SRW.OUTPUT !
    64 _srt-workspace _SRW.OUTPUT-CAP !
    ['] _srt-open-publication-rethrow CATCH
        -3201 = _srt-assert
    _srt-output 64 _srt-zero? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-record 256 0xA5 FILL
    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE 0x5A FILL
    _srt-record _srt-workspace _SRW.OUTPUT !
    ['] _srt-seal-publication-rethrow CATCH
        -3202 = _srt-assert
    _srt-record 8 _srt-zero? _srt-assert
    _srt-record 8 + 248 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE 0x5A FILL
    ['] _srt-cleanup-precedence-rethrow CATCH
        -3203 = _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-stack ;

: _SRT-BOUNDARY-RUN  ( -- )
    0 _srt-fails !
    0 _srt-checks !
    DEPTH _srt-depth !
    _srt-init
    _srt-vector _srt-record 208 MOVE
    _srt-test-resolver-contracts
    _srt-test-rejections
    _srt-test-publication-cleanup
    _srt-stack
    _srt-fails @ 0= IF
        ." SEALED RECORD BOUNDARY PASS " _srt-checks @ . CR
    ELSE
        ." SEALED RECORD FAIL BOUNDARY " _srt-fails @ . CR
    THEN ;
