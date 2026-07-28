\ sealed-rec-neg.f - Authentication and record-shape failures

PROVIDED sealed-record-neg-test

: _srt-test-auth-and-shape  ( -- )
    _srt-record 207 + DUP C@ 1 XOR SWAP C!
    _srt-output 64 0xA5 FILL
    ['] _srt-resolver _srt-base
    _srt-record 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-AUTH = _srt-assert
    0= _srt-assert
    _srt-output 64 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-record 207 + DUP C@ 1 XOR SWAP C!

    _srt-record 160 + DUP C@ 1 XOR SWAP C!
    _srt-output 64 0xA5 FILL
    ['] _srt-resolver _srt-base
    _srt-record 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-AUTH = _srt-assert
    0= _srt-assert
    _srt-output 64 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-record 160 + DUP C@ 1 XOR SWAP C!

    _srt-record DUP C@ 1 XOR SWAP C!
    _srt-output 64 0xA5 FILL
    0 _srt-resolver-calls !
    ['] _srt-resolver _srt-base
    _srt-record 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-FORMAT = _srt-assert
    0= _srt-assert
    _srt-resolver-calls @ 0= _srt-assert
    _srt-output 64 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-record DUP C@ 1 XOR SWAP C!

    _srt-output 64 0xA5 FILL
    0 _srt-resolver-calls !
    ['] _srt-wrong-resolver _srt-base
    _srt-record 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-AUTH = _srt-assert
    0= _srt-assert
    _srt-resolver-calls @ 1 = _srt-assert
    _srt-output 64 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-output 64 0xA5 FILL
    0 _srt-resolver-calls !
    ['] _srt-resolver _srt-base
    _srt-other-id _srt-descriptor SEALED-RECORD-D.RECORD-ID !
    _srt-record 208 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-MISMATCH = _srt-assert
    0= _srt-assert
    _srt-resolver-calls @ 0= _srt-assert
    _srt-output 64 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert

    _srt-output 64 0xA5 FILL
    0 _srt-resolver-calls !
    ['] _srt-resolver _srt-base
    _srt-vector 209 _srt-output 64 _srt-io
    _srt-descriptor _srt-workspace SEALED-RECORD-OPEN
    SEALED-RECORD-S-FORMAT = _srt-assert
    0= _srt-assert
    _srt-resolver-calls @ 0= _srt-assert
    _srt-output 64 0xA5 _srt-filled? _srt-assert
    _srt-workspace-clean? _srt-assert
    _srt-stack ;

: _SRT-NEGATIVE-RUN  ( -- )
    0 _srt-fails !
    0 _srt-checks !
    DEPTH _srt-depth !
    _srt-init
    _srt-vector _srt-record 208 MOVE
    _srt-test-auth-and-shape
    _srt-stack
    _srt-fails @ 0= IF
        ." SEALED RECORD NEGATIVE PASS " _srt-checks @ . CR
    ELSE
        ." SEALED RECORD FAIL NEGATIVE " _srt-fails @ . CR
    THEN ;
