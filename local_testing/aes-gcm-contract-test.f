\ aes-gcm-contract-test.f - Native AES-GCM descriptor and CAVP contracts

PROVIDED akashic-aes-gcm-contract-test

VARIABLE _agct-fails
VARIABLE _agct-checks
VARIABLE _agct-depth

: _agct-assert  ( flag -- )
    1 _agct-checks +!
    0= IF
        1 _agct-fails +!
        ." AES-GCM ASSERT " _agct-checks @ . CR
    THEN ;

: _agct-stack  ( -- )
    DEPTH _agct-depth @ = _agct-assert ;

: _agct-bytes=  ( first second length -- flag )
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _agct-filled?  ( address length byte -- flag )
    SWAP 0 ?DO
        OVER I + C@ OVER <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

\ NIST CAVP GCM vectors, gcmEncryptExtIV128/256.rsp (CAVS 14.0).

CREATE _agct-v1-key
    0x11 C, 0x75 C, 0x4C C, 0xD7 C, 0x2A C, 0xEC C, 0x30 C, 0x9B C,
    0xF5 C, 0x2F C, 0x76 C, 0x87 C, 0x21 C, 0x2E C, 0x89 C, 0x57 C,
CREATE _agct-v1-iv
    0x3C C, 0x81 C, 0x9D C, 0x9A C, 0x9B C, 0xED C,
    0x08 C, 0x76 C, 0x15 C, 0x03 C, 0x0B C, 0x65 C,
CREATE _agct-v1-tag
    0x25 C, 0x03 C, 0x27 C, 0xC6 C, 0x74 C, 0xAA C, 0xF4 C, 0x77 C,
    0xAE C, 0xF2 C, 0x67 C, 0x57 C, 0x48 C, 0xCF C, 0x69 C, 0x71 C,

CREATE _agct-v2-key
    0x88 C, 0x6C C, 0xFF C, 0x5F C, 0x3E C, 0x6B C, 0x8D C, 0x0E C,
    0x1A C, 0xD0 C, 0xA3 C, 0x8F C, 0xCD C, 0xB2 C, 0x6D C, 0xE9 C,
    0x7E C, 0x8A C, 0xCB C, 0xE7 C, 0x9F C, 0x6B C, 0xED C, 0x66 C,
    0x95 C, 0x9A C, 0x59 C, 0x8F C, 0xA5 C, 0x04 C, 0x7D C, 0x65 C,
CREATE _agct-v2-iv
    0x3A C, 0x8E C, 0xFA C, 0x1C C, 0xD7 C, 0x4B C,
    0xBA C, 0xB5 C, 0x44 C, 0x8F C, 0x99 C, 0x45 C,
CREATE _agct-v2-aad
    0x51 C, 0x9F C, 0xEE C, 0x51 C, 0x9D C, 0x25 C, 0xC7 C, 0xA3 C,
    0x04 C, 0xD6 C, 0xC6 C, 0xAA C, 0x18 C, 0x97 C, 0xEE C, 0x1E C,
    0xB8 C, 0xC5 C, 0x96 C, 0x55 C,
CREATE _agct-v2-tag
    0xF6 C, 0xD4 C, 0x75 C, 0x05 C, 0xEC C, 0x96 C, 0xC9 C, 0x8A C,
    0x42 C, 0xDC C, 0x3A C, 0xE7 C, 0x19 C, 0x87 C, 0x7B C, 0x87 C,

CREATE _agct-v3-key
    0xFE C, 0x9B C, 0xB4 C, 0x7D C, 0xEB C, 0x3A C, 0x61 C, 0xE4 C,
    0x23 C, 0xC2 C, 0x23 C, 0x18 C, 0x41 C, 0xCF C, 0xD1 C, 0xFB C,
CREATE _agct-v3-iv
    0x4D C, 0x32 C, 0x8E C, 0xB7 C, 0x76 C, 0xF5 C,
    0x00 C, 0xA2 C, 0xF7 C, 0xFB C, 0x47 C, 0xAA C,
CREATE _agct-v3-pt
    0xF1 C, 0xCC C, 0x38 C, 0x18 C, 0xE4 C, 0x21 C, 0x87 C,
    0x6B C, 0xB6 C, 0xB8 C, 0xBB C, 0xD6 C, 0xC9 C,
CREATE _agct-v3-ct
    0xB8 C, 0x8C C, 0x5C C, 0x19 C, 0x77 C, 0xB3 C, 0x5B C,
    0x51 C, 0x7B C, 0x0A C, 0xEA C, 0xE9 C, 0x67 C,
CREATE _agct-v3-tag
    0x43 C, 0xFD C, 0x47 C, 0x27 C, 0xFE C, 0x5C C, 0xDB C, 0x4B C,
    0x5B C, 0x42 C, 0x81 C, 0x8D C, 0xEA C, 0x7E C, 0xF8 C, 0xC9 C,

CREATE _agct-v4-key
    0x37 C, 0xCC C, 0xDB C, 0xA1 C, 0xD9 C, 0x29 C, 0xD6 C, 0x43 C,
    0x6C C, 0x16 C, 0xBB C, 0xA5 C, 0xB5 C, 0xFF C, 0x34 C, 0xDE C,
    0xEC C, 0x88 C, 0xED C, 0x7D C, 0xF3 C, 0xD1 C, 0x5D C, 0x0F C,
    0x4D C, 0xDF C, 0x80 C, 0xC0 C, 0xC7 C, 0x31 C, 0xEE C, 0x1F C,
CREATE _agct-v4-iv
    0x5C C, 0x1B C, 0x21 C, 0xC8 C, 0x99 C, 0x8E C,
    0xD6 C, 0x29 C, 0x90 C, 0x06 C, 0xD3 C, 0xF9 C,
CREATE _agct-v4-aad
    0x22 C, 0xED C, 0x23 C, 0x59 C, 0x46 C, 0x23 C, 0x5A C, 0x85 C,
    0xA4 C, 0x5B C, 0xC5 C, 0xFA C, 0xD7 C, 0x14 C, 0x0B C, 0xFA C,
CREATE _agct-v4-pt
    0xAD C, 0x42 C, 0x60 C, 0xE3 C, 0xCD C, 0xC7 C, 0x6B C, 0xCC C,
    0x10 C, 0xC7 C, 0xB2 C, 0xC0 C, 0x6B C, 0x80 C, 0xB3 C, 0xBE C,
    0x94 C, 0x82 C, 0x58 C, 0xE5 C, 0xEF C, 0x20 C, 0xC5 C, 0x08 C,
    0xA8 C, 0x1F C, 0x51 C, 0xE9 C, 0x6A C, 0x51 C, 0x83 C, 0x88 C,
CREATE _agct-v4-ct
    0x3B C, 0x33 C, 0x5F C, 0x8B C, 0x08 C, 0xD3 C, 0x3C C, 0xCD C,
    0xCA C, 0xD2 C, 0x28 C, 0xA7 C, 0x47 C, 0x00 C, 0xF1 C, 0x00 C,
    0x75 C, 0x42 C, 0xA4 C, 0xD1 C, 0xE7 C, 0xFC C, 0x1E C, 0xBE C,
    0x3F C, 0x44 C, 0x7F C, 0xE7 C, 0x1A C, 0xF2 C, 0x98 C, 0x16 C,
CREATE _agct-v4-tag
    0x1F C, 0xBF C, 0x49 C, 0xCC C, 0x46 C, 0xF4 C, 0x58 C, 0xBF C,
    0x6E C, 0x88 C, 0xF6 C, 0x37 C, 0x09 C, 0x75 C, 0xE6 C, 0xD4 C,

CREATE _agct-d AES-GCM-DESCRIPTOR-SIZE ALLOT
CREATE _agct-w AES-GCM-WORKSPACE-SIZE ALLOT
CREATE _agct-tag AES-GCM-TAG-SIZE ALLOT
CREATE _agct-ct 64 ALLOT
CREATE _agct-out 64 ALLOT
CREATE _agct-in-place 64 ALLOT
CREATE _agct-bad-tag AES-GCM-TAG-SIZE ALLOT
CREATE _agct-bad-tag-copy AES-GCM-TAG-SIZE ALLOT
CREATE _agct-before 64 ALLOT
CREATE _agct-dout AES-GCM-BLOCK-SIZE ALLOT

: _agct-base  ( key key-u iv tag -- )
    _agct-d AES-GCM-DESCRIPTOR-CLEAR DROP
    _agct-d AES-GCM-D.TAG !
    AES-GCM-TAG-SIZE _agct-d AES-GCM-D.TAG-U !
    _agct-d AES-GCM-D.IV !
    AES-GCM-IV-SIZE _agct-d AES-GCM-D.IV-U !
    _agct-d AES-GCM-D.KEY-U !
    _agct-d AES-GCM-D.KEY !
    0 _agct-d AES-GCM-D.AAD !
    0 _agct-d AES-GCM-D.AAD-U !
    0 _agct-d AES-GCM-D.INPUT !
    0 _agct-d AES-GCM-D.OUTPUT !
    0 _agct-d AES-GCM-D.DATA-U ! ;

: _agct-clean?  ( -- flag )
    _agct-w AES-GCM-WORKSPACE-SIZE 0 _agct-filled? ;

: _agct-test-status  ( -- )
    AES-GCM-S-INTERNAL AES-GCM-STATUS-VALID? _agct-assert
    AES-GCM-S-INTERNAL 1+ AES-GCM-STATUS-VALID? 0= _agct-assert
    AES-GCM-DESCRIPTOR-SIZE 88 = _agct-assert
    AES-GCM-WORKSPACE-SIZE 240 = _agct-assert
    _aes-gcm-guard GUARD-HELD? 0= _agct-assert
    _agct-stack ;

: _agct-test-empty  ( -- )
    _agct-v1-key 16 _agct-v1-iv _agct-tag _agct-base
    _agct-d AES-GCM-DESCRIPTOR-VALID? _agct-assert
    _agct-tag 16 0xA5 FILL
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-OK = _agct-assert
    _agct-tag _agct-v1-tag 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert

    _agct-d _agct-w AES-GCM-OPEN AES-GCM-S-OK = _agct-assert
    _agct-clean? _agct-assert
    _aes-gcm-guard GUARD-HELD? 0= _agct-assert
    _agct-stack ;

: _agct-test-aad-only  ( -- )
    _agct-v2-key 32 _agct-v2-iv _agct-tag _agct-base
    _agct-v2-aad _agct-d AES-GCM-D.AAD !
    20 _agct-d AES-GCM-D.AAD-U !
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-OK = _agct-assert
    _agct-tag _agct-v2-tag 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert
    _agct-d _agct-w AES-GCM-OPEN AES-GCM-S-OK = _agct-assert
    _agct-clean? _agct-assert
    _agct-stack ;

: _agct-test-partial  ( -- )
    _agct-v3-key 16 _agct-v3-iv _agct-tag _agct-base
    _agct-v3-pt _agct-d AES-GCM-D.INPUT !
    _agct-ct _agct-d AES-GCM-D.OUTPUT !
    13 _agct-d AES-GCM-D.DATA-U !
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-OK = _agct-assert
    _agct-ct _agct-v3-ct 13 _agct-bytes= _agct-assert
    _agct-tag _agct-v3-tag 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert

    _agct-ct _agct-d AES-GCM-D.INPUT !
    _agct-out _agct-d AES-GCM-D.OUTPUT !
    _agct-out 13 0xA5 FILL
    _agct-d _agct-w AES-GCM-OPEN AES-GCM-S-OK = _agct-assert
    _agct-out _agct-v3-pt 13 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert
    _agct-stack ;

: _agct-test-multiblock-in-place  ( -- )
    _agct-v4-key 32 _agct-v4-iv _agct-tag _agct-base
    _agct-v4-aad _agct-d AES-GCM-D.AAD !
    16 _agct-d AES-GCM-D.AAD-U !
    _agct-v4-pt _agct-in-place 32 MOVE
    _agct-in-place _agct-d AES-GCM-D.INPUT !
    _agct-in-place _agct-d AES-GCM-D.OUTPUT !
    32 _agct-d AES-GCM-D.DATA-U !

    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-OK = _agct-assert
    _agct-in-place _agct-v4-ct 32 _agct-bytes= _agct-assert
    _agct-tag _agct-v4-tag 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert

    _agct-d _agct-w AES-GCM-OPEN AES-GCM-S-OK = _agct-assert
    _agct-in-place _agct-v4-pt 32 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert
    _agct-stack ;

: _agct-test-bad-tag-wipes  ( -- )
    _agct-v4-key 32 _agct-v4-iv _agct-bad-tag _agct-base
    _agct-v4-aad _agct-d AES-GCM-D.AAD !
    16 _agct-d AES-GCM-D.AAD-U !
    _agct-v4-ct _agct-d AES-GCM-D.INPUT !
    _agct-out _agct-d AES-GCM-D.OUTPUT !
    32 _agct-d AES-GCM-D.DATA-U !
    _agct-v4-tag _agct-bad-tag 16 MOVE
    _agct-bad-tag DUP C@ 1+ SWAP C!
    _agct-bad-tag _agct-bad-tag-copy 16 MOVE
    _agct-out 32 0xA5 FILL

    _agct-d _agct-w AES-GCM-OPEN AES-GCM-S-AUTH = _agct-assert
    _agct-out 32 0 _agct-filled? _agct-assert
    _agct-bad-tag _agct-bad-tag-copy 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert
    _aes-gcm-guard GUARD-HELD? 0= _agct-assert
    _agct-stack ;

: _agct-test-rejected-geometry  ( -- )
    _agct-v4-key 32 _agct-v4-iv _agct-tag _agct-base
    _agct-in-place 64 0xA6 FILL
    _agct-v4-pt _agct-in-place 32 MOVE
    _agct-in-place _agct-before 64 MOVE
    _agct-in-place _agct-d AES-GCM-D.INPUT !
    _agct-in-place 1+ _agct-d AES-GCM-D.OUTPUT !
    32 _agct-d AES-GCM-D.DATA-U !
    _agct-tag 16 0x5A FILL
    _agct-w AES-GCM-WORKSPACE-SIZE 0xA5 FILL
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-ALIAS = _agct-assert
    _agct-w AES-GCM-WORKSPACE-SIZE 0xA5 _agct-filled? _agct-assert
    _agct-in-place _agct-before 64 _agct-bytes= _agct-assert
    _agct-tag 16 0x5A _agct-filled? _agct-assert

    24 _agct-d AES-GCM-D.KEY-U !
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-INVALID = _agct-assert
    _agct-w AES-GCM-WORKSPACE-SIZE 0xA5 _agct-filled? _agct-assert
    _agct-in-place _agct-before 64 _agct-bytes= _agct-assert
    _agct-tag 16 0x5A _agct-filled? _agct-assert
    _aes-gcm-guard GUARD-HELD? 0= _agct-assert
    _agct-stack ;

\ Begin a raw transaction and deliberately leave it active.  A complete
\ descriptor call must abort that stale operation and start from its own
\ fully rewritten configuration; the first replacement key byte may not be
\ lost to the abort.
: _agct-test-stale-active-recovery  ( -- )
    _agct-v4-key AES-KEY!
    _agct-v4-iv AES-IV!
    0 AES-KEY-MODE!
    0 AES-AAD-LEN!
    16 AES-DATA-LEN!
    0 AES-CMD!
    AES-STATUS@ 1 = _agct-assert

    _agct-v3-key 16 _agct-v3-iv _agct-tag _agct-base
    _agct-v3-pt _agct-d AES-GCM-D.INPUT !
    _agct-ct _agct-d AES-GCM-D.OUTPUT !
    13 _agct-d AES-GCM-D.DATA-U !
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-OK = _agct-assert
    _agct-ct _agct-v3-ct 13 _agct-bytes= _agct-assert
    _agct-tag _agct-v3-tag 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert
    _agct-stack ;

\ A raw OPEN intentionally demonstrates the machine-level terminal contract.
\ The first data block creates plaintext in DOUT, but the final bad tag must
\ clear that window before status 3 is observed.
: _agct-test-native-dout-cleanup  ( -- )
    _agct-v4-tag _agct-bad-tag 16 MOVE
    _agct-bad-tag DUP C@ 1+ SWAP C!
    _agct-bad-tag _agct-bad-tag-copy 16 MOVE

    _agct-v4-key AES-KEY!
    _agct-v4-iv AES-IV!
    0 AES-KEY-MODE!
    16 AES-AAD-LEN!
    32 AES-DATA-LEN!
    _agct-bad-tag AES-TAG!
    1 AES-CMD!
    AES-STATUS@ 1 = _agct-assert
    _agct-v4-aad AES-DIN!
    AES-STATUS@ 1 = _agct-assert
    _agct-v4-ct AES-DIN!
    AES-STATUS@ 1 = _agct-assert
    _agct-v4-ct 16 + AES-DIN!
    AES-STATUS@ 3 = _agct-assert

    _agct-dout 16 0xA5 FILL
    _agct-dout AES-DOUT@
    _agct-dout 16 0 _agct-filled? _agct-assert
    _agct-bad-tag _agct-bad-tag-copy 16 _agct-bytes= _agct-assert

    _agct-w _AGCM-CLEAR-ENGINE-SAFE 0= _agct-assert
    _agct-w AES-GCM-WORKSPACE-CLEAR AES-GCM-S-OK = _agct-assert
    _agct-stack ;

\ Exercise configuration-mask rejection and reset behavior through the actual
\ MMIO/BIOS window rather than merely inspecting native source.
: _agct-test-native-configuration-masks  ( -- )
    _agct-w AES-GCM-WORKSPACE-SIZE 0 FILL
    _agct-w _AGCM-CLEAR-ENGINE-SAFE 0= _agct-assert

    \ Missing IV must reject even though key and both lengths were complete.
    _agct-v4-key AES-KEY!
    0 AES-KEY-MODE!
    0 AES-AAD-LEN!
    0 AES-DATA-LEN!
    0 AES-CMD!
    AES-STATUS@ 3 = _agct-assert
    _agct-dout 16 0xA5 FILL
    _agct-dout AES-DOUT@
    _agct-dout 16 0 _agct-filled? _agct-assert
    _agct-tag 16 0xA5 FILL
    _agct-tag AES-TAG@
    _agct-tag 16 0 _agct-filled? _agct-assert

    \ Fault handling must have cleared the preceding key mask.  Supplying only
    \ the formerly missing IV and lengths may not complete a new transaction.
    _agct-v4-iv AES-IV!
    0 AES-KEY-MODE!
    0 AES-AAD-LEN!
    0 AES-DATA-LEN!
    0 AES-CMD!
    AES-STATUS@ 3 = _agct-assert

    \ A complete descriptor operation recovers from the rejected epochs.
    _agct-v1-key 16 _agct-v1-iv _agct-tag _agct-base
    _agct-d _agct-w AES-GCM-SEAL AES-GCM-S-OK = _agct-assert
    _agct-tag _agct-v1-tag 16 _agct-bytes= _agct-assert
    _agct-clean? _agct-assert

    \ Terminal success also clears masks; IV plus lengths cannot reuse its key.
    _agct-v4-iv AES-IV!
    0 AES-KEY-MODE!
    0 AES-AAD-LEN!
    0 AES-DATA-LEN!
    0 AES-CMD!
    AES-STATUS@ 3 = _agct-assert

    \ OPEN additionally requires all sixteen expected-tag bytes.
    _agct-v4-key AES-KEY!
    _agct-v4-iv AES-IV!
    0 AES-KEY-MODE!
    0 AES-AAD-LEN!
    0 AES-DATA-LEN!
    1 AES-CMD!
    AES-STATUS@ 3 = _agct-assert

    _agct-w AES-GCM-WORKSPACE-SIZE 0 FILL
    _agct-w _AGCM-CLEAR-ENGINE-SAFE 0= _agct-assert
    _agct-w AES-GCM-WORKSPACE-CLEAR AES-GCM-S-OK = _agct-assert
    _agct-stack ;

: _AGCT-RUN  ( -- )
    0 _agct-fails !
    0 _agct-checks !
    DEPTH _agct-depth !
    _agct-test-status
    _agct-test-empty
    _agct-test-aad-only
    _agct-test-partial
    _agct-test-multiblock-in-place
    _agct-test-bad-tag-wipes
    _agct-test-rejected-geometry
    _agct-test-stale-active-recovery
    _agct-test-native-dout-cleanup
    _agct-test-native-configuration-masks
    _agct-stack
    _agct-fails @ 0= IF
        ." AES-GCM PASS " _agct-checks @ . CR
    ELSE
        ." AES-GCM FAIL " _agct-fails @ . CR
    THEN ;
