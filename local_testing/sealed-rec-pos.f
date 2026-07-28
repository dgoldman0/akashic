\ sealed-rec-pos.f - Successful sealing and opening contracts

PROVIDED sealed-record-pos-test

: _srt-test-vocabulary  ( -- )
    SEALED-RECORD-DESCRIPTOR-SIZE 80 = _srt-assert
    SEALED-RECORD-WORKSPACE-SIZE 66568 = _srt-assert
    SEALED-RECORD-HEADER-SIZE 160 = _srt-assert
    SEALED-RECORD-OVERHEAD 176 = _srt-assert
    SEALED-RECORD-DATA-MAX SEALED-RECORD-SIZE
        SEALED-RECORD-SIZE-MAX = _srt-assert
    0 SEALED-RECORD-SIZE 0= _srt-assert
    SEALED-RECORD-DATA-MAX 1+ SEALED-RECORD-SIZE 0= _srt-assert
    SEALED-RECORD-S-INTERNAL
        SEALED-RECORD-STATUS-VALID? _srt-assert
    SEALED-RECORD-S-INTERNAL 1+
        SEALED-RECORD-STATUS-VALID? 0= _srt-assert
    _srt-stack ;

: _srt-test-reference-open  ( -- )
    _srt-output 64 0xA5 FILL
    _srt-workspace SEALED-RECORD-WORKSPACE-CLEAR DROP
    0 _srt-resolver-calls !
    ['] _srt-resolver _srt-base
    _srt-vector 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-OK = _srt-assert
    32 = _srt-assert
    _srt-output _srt-plain 32 _srt-bytes= _srt-assert
    _srt-output 32 + 32 _srt-zero? _srt-assert
    _srt-vector 208 + 48 0xA5 _srt-filled? _srt-assert
    _srt-resolver-calls @ 1 = _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-stack ;

: _srt-test-seal-open  ( -- )
    _srt-record 256 0xA5 FILL
    _srt-workspace SEALED-RECORD-WORKSPACE-CLEAR DROP
    0 _srt-resolver-calls !
    ['] _srt-resolver _srt-base
    _srt-plain 32 _srt-record 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-OK = _srt-assert
    208 = _srt-assert
    _srt-record _srt-vector 8 _srt-bytes= _srt-assert
    _srt-record 32 + _SR-BE64@ 32 = _srt-assert
    _srt-record 128 + SEALED-RECORD-SALT-SIZE
        _SR-NONZERO-SPAN? _srt-assert
    _srt-record 208 + 48 0xA5 _srt-filled? _srt-assert
    _srt-resolver-calls @ 1 = _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-record 128 + _srt-output SEALED-RECORD-SALT-SIZE MOVE
    _srt-record2 256 0xA5 FILL
    ['] _srt-resolver _srt-base
    _srt-plain 32 _srt-record2 208 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    SEALED-RECORD-S-OK = _srt-assert
    208 = _srt-assert
    _srt-record2 128 + _srt-output SEALED-RECORD-SALT-SIZE
        _srt-bytes= 0= _srt-assert
    _srt-record2 208 + 48 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-output 64 0xA5 FILL
    0 _srt-resolver-calls !
    ['] _srt-resolver _srt-base
    _srt-record 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-OK = _srt-assert
    32 = _srt-assert
    _srt-output _srt-plain 32 _srt-bytes= _srt-assert
    _srt-output 32 + 32 _srt-zero? _srt-assert
    _srt-resolver-calls @ 1 = _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-stack ;

: _SRT-POSITIVE-RUN  ( -- )
    0 _srt-fails !
    0 _srt-checks !
    DEPTH _srt-depth !
    _srt-init
    _srt-test-vocabulary
    _srt-test-reference-open
    _srt-test-seal-open
    _srt-stack
    _srt-fails @ 0= IF
        ." SEALED RECORD POSITIVE PASS " _srt-checks @ . CR
    ELSE
        ." SEALED RECORD FAIL POSITIVE " _srt-fails @ . CR
    THEN ;
