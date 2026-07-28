\ sealed-rec-base.f - Shared sealed-record contract fixtures

PROVIDED sealed-record-test-base

VARIABLE _srt-fails
VARIABLE _srt-checks
VARIABLE _srt-depth

: _srt-assert  ( flag -- )
    1 _srt-checks +!
    0= IF
        1 _srt-fails +!
        ." SEALED RECORD ASSERT " _srt-checks @ . CR
    THEN ;

: _srt-stack  ( -- )
    DEPTH DUP _srt-depth @ <> IF
        ." SEALED RECORD STACK "
        _srt-depth @ . ." -> " DUP . CR .S CR
    THEN
    _srt-depth @ = _srt-assert ;

: _srt-bytes=  ( first second length -- flag )
    >R SWAP R@ ROT R> COMPARE 0= ;

: _srt-filled?  ( address length byte -- flag )
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

: _srt-zero?  ( address length -- flag )
    0 _srt-filled? ;

VARIABLE _srt-seq-v
VARIABLE _srt-seq-a
VARIABLE _srt-seq-u

: _srt-sequence!  ( first-byte destination length -- )
    _srt-seq-u ! _srt-seq-a ! _srt-seq-v !
    BEGIN
        _srt-seq-u @
    WHILE
        _srt-seq-v @ 255 AND _srt-seq-a @ C!
        1 _srt-seq-v +!
        1 _srt-seq-a +!
        -1 _srt-seq-u +!
    REPEAT ;

VARIABLE _srt-hex-a
VARIABLE _srt-hex-u
VARIABLE _srt-hex-out

: _srt-hex-nibble  ( ascii -- nibble )
    DUP 57 <= IF 48 - ELSE 87 - THEN ;

: _srt-hex!  ( source source-u destination -- )
    _srt-hex-out ! _srt-hex-u ! _srt-hex-a !
    BEGIN
        _srt-hex-u @
    WHILE
        _srt-hex-a @ C@ _srt-hex-nibble 4 LSHIFT
        _srt-hex-a @ 1+ C@ _srt-hex-nibble OR
        _srt-hex-out @ C!
        2 _srt-hex-a +!
        -2 _srt-hex-u +!
        1 _srt-hex-out +!
    REPEAT ;

CREATE _srt-descriptor SEALED-RECORD-DESCRIPTOR-SIZE ALLOT
CREATE _srt-workspace SEALED-RECORD-WORKSPACE-SIZE ALLOT
CREATE _srt-root SEALED-RECORD-ROOT-KEY-SIZE ALLOT
CREATE _srt-wrong-root SEALED-RECORD-ROOT-KEY-SIZE ALLOT
CREATE _srt-key-id SEALED-RECORD-ID-SIZE ALLOT
CREATE _srt-record-id SEALED-RECORD-ID-SIZE ALLOT
CREATE _srt-other-id SEALED-RECORD-ID-SIZE ALLOT
CREATE _srt-plain 32 ALLOT
CREATE _srt-vector 256 ALLOT
CREATE _srt-record 256 ALLOT
CREATE _srt-record2 256 ALLOT
CREATE _srt-output 64 ALLOT

0x0102030405060708 CONSTANT _SRT-PURPOSE
0x1112131415161718 CONSTANT _SRT-REVISION

VARIABLE _srt-r-root
VARIABLE _srt-r-xt
VARIABLE _srt-r-context
VARIABLE _srt-resolver-calls
VARIABLE _srt-nested-status

: _srt-resolver-common
  \ ( key-id key-id-u consumer-xt consumer-context resolver-context
  \   root-key -- status )
    _srt-r-root !
    DROP
    _srt-r-context !
    _srt-r-xt !
    2DROP
    1 _srt-resolver-calls +!
    _srt-r-root @ SEALED-RECORD-ROOT-KEY-SIZE
    _srt-r-context @ _srt-r-xt @ EXECUTE ;

: _srt-resolver  ( five resolver arguments -- status )
    _srt-root _srt-resolver-common ;

: _srt-wrong-resolver  ( five resolver arguments -- status )
    _srt-wrong-root _srt-resolver-common ;

: _srt-no-key-resolver  ( five resolver arguments -- status )
    2DROP 2DROP DROP SEALED-RECORD-S-KEY ;

: _srt-extra-result-resolver  ( five resolver arguments -- status extra )
    _srt-resolver SEALED-RECORD-S-OK ;

: _srt-missing-result-resolver  ( five resolver arguments -- )
    2DROP 2DROP DROP ;

: _srt-substituted-context-resolver  ( five resolver arguments -- status )
    DROP
    DROP
    _srt-r-xt !
    2DROP
    _srt-root SEALED-RECORD-ROOT-KEY-SIZE
    _srt-descriptor _srt-r-xt @ EXECUTE ;

: _srt-recursive-resolver  ( five resolver arguments -- status )
    2DROP 2DROP DROP
    _srt-descriptor _srt-workspace SEALED-RECORD-SEAL
    _srt-nested-status ! DROP
    SEALED-RECORD-S-KEY ;

: _srt-base  ( resolver-xt -- )
    _srt-descriptor SEALED-RECORD-DESCRIPTOR-CLEAR DROP
    _srt-descriptor SEALED-RECORD-D.RESOLVER-XT !
    0 _srt-descriptor SEALED-RECORD-D.RESOLVER-CONTEXT !
    _srt-key-id _srt-descriptor SEALED-RECORD-D.KEY-ID !
    _srt-record-id _srt-descriptor SEALED-RECORD-D.RECORD-ID !
    _SRT-PURPOSE _srt-descriptor SEALED-RECORD-D.PURPOSE !
    _SRT-REVISION _srt-descriptor SEALED-RECORD-D.REVISION ! ;

: _srt-io  ( input input-u output output-cap -- )
    _srt-descriptor SEALED-RECORD-D.OUTPUT-CAP !
    _srt-descriptor SEALED-RECORD-D.OUTPUT !
    _srt-descriptor SEALED-RECORD-D.INPUT-U !
    _srt-descriptor SEALED-RECORD-D.INPUT ! ;

: _srt-init-vector  ( -- )
    _srt-vector 256 0xA5 FILL
    S" 414b535345414c31000000000000000100000000000000a000000000000000d00000000000000020010203040506070811121314151617180000000000000000"
        _srt-vector _srt-hex!
    S" 202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f"
        _srt-vector 64 + _srt-hex!
    S" a0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebf130072e2fedc9f7d2e04f4d01d0d1eb92204aa54255f59c27fcb38347ee1c87a"
        _srt-vector 128 + _srt-hex!
    S" e332e8c1a2b877469db5472cda0843b7"
        _srt-vector 192 + _srt-hex! ;

: _srt-init  ( -- )
    0 _srt-root SEALED-RECORD-ROOT-KEY-SIZE _srt-sequence!
    0x80 _srt-wrong-root SEALED-RECORD-ROOT-KEY-SIZE _srt-sequence!
    0x20 _srt-key-id SEALED-RECORD-ID-SIZE _srt-sequence!
    0x40 _srt-record-id SEALED-RECORD-ID-SIZE _srt-sequence!
    0x60 _srt-other-id SEALED-RECORD-ID-SIZE _srt-sequence!
    0 _srt-plain 32 _srt-sequence!
    _srt-init-vector ;

: _srt-workspace-clean?  ( -- flag )
    _srt-workspace SEALED-RECORD-WORKSPACE-SIZE _srt-zero? ;
