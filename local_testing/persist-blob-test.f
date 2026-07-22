\ RAM-VFS contracts for neutral immutable chunked blobs.

PROVIDED akashic-persistence-blob-contracts

VARIABLE _PBLC-fails
VARIABLE _PBLC-checks
VARIABLE _PBLC-depth
VARIABLE _PBLC-arena
VARIABLE _PBLC-vfs
VARIABLE _PBLC-ior
VARIABLE _PBLC-old-vfs
VARIABLE _PBLC-page-id
VARIABLE _PBLC-source-mode
VARIABLE _PBLC-sink-mode
VARIABLE _PBLC-sink-bytes
VARIABLE _PBLC-sink-calls
VARIABLE _PBLC-sink-errors
VARIABLE _PBLC-store-fault-at
VARIABLE _PBLC-old-generation

CREATE _PBLC-ops VFS-OPS-SIZE ALLOT
CREATE _PBLC-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _PBLC-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _PBLC-store PSTORE-SIZE ALLOT
CREATE _PBLC-reopen-store PSTORE-SIZE ALLOT
CREATE _PBLC-store-work PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-reopen-work PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-alias-store-work PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-record-buffer 33000 ALLOT
CREATE _PBLC-reopen-buffer 33000 ALLOT
CREATE _PBLC-alias-buffer PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-blob-work PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-read-work PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-blob PBLOB-SIZE ALLOT
CREATE _PBLC-empty PBLOB-SIZE ALLOT
CREATE _PBLC-reopened-blob PBLOB-SIZE ALLOT
CREATE _PBLC-deep-blob PBLOB-SIZE ALLOT
CREATE _PBLC-corrupt-blob PBLOB-SIZE ALLOT
CREATE _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _PBLC-store-i0 PSTORE-SIZE ALLOT
CREATE _PBLC-store-i1 PSTORE-SIZE ALLOT
CREATE _PBLC-store-i2 PSTORE-SIZE ALLOT
CREATE _PBLC-store-i3 PSTORE-SIZE ALLOT
CREATE _PBLC-work-i0 PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-work-i1 PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-work-i2 PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-work-i3 PSTORE-WORK-SIZE ALLOT
CREATE _PBLC-buffer-i0 33000 ALLOT
CREATE _PBLC-buffer-i1 33000 ALLOT
CREATE _PBLC-buffer-i2 33000 ALLOT
CREATE _PBLC-buffer-i3 33000 ALLOT
CREATE _PBLC-bwork-i0 PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-bwork-i1 PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-bwork-i2 PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-bwork-i3 PBLOB-WORK-SIZE ALLOT
CREATE _PBLC-blob-i0 PBLOB-SIZE ALLOT
CREATE _PBLC-blob-i1 PBLOB-SIZE ALLOT
CREATE _PBLC-blob-i2 PBLOB-SIZE ALLOT
CREATE _PBLC-blob-i3 PBLOB-SIZE ALLOT
CREATE _PBLC-mismatch-before PBLOB-SIZE ALLOT
CREATE _PBLC-identity-i0 PERSIST-IDENTITY-SIZE ALLOT
CREATE _PBLC-identity-i1 PERSIST-IDENTITY-SIZE ALLOT
CREATE _PBLC-identity-i2 PERSIST-IDENTITY-SIZE ALLOT
CREATE _PBLC-identity-i3 PERSIST-IDENTITY-SIZE ALLOT
GUARD _PBLC-guard
GUARD _PBLC-reopen-guard
GUARD _PBLC-guard-i0
GUARD _PBLC-guard-i1
GUARD _PBLC-guard-i2
GUARD _PBLC-guard-i3

: _PBLC-assert  ( flag -- )
    1 _PBLC-checks +!
    0= IF
        1 _PBLC-fails +!
        ." PERSISTENCE BLOB ASSERT " _PBLC-checks @ . CR
    THEN ;

: _PBLC-stack  ( -- )
    DEPTH DUP _PBLC-depth @ <> IF
        ." PERSISTENCE BLOB STACK " _PBLC-depth @ . ." -> " DUP . CR .S CR
    THEN
    _PBLC-depth @ = _PBLC-assert ;

: _PBLC-status  ( actual expected -- )
    2DUP <> IF
        ." PERSISTENCE BLOB STATUS actual/expected " 2DUP . . CR
    THEN
    = _PBLC-assert _PBLC-stack ;

: _PBLC-bytes=  ( a b u -- flag )
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _PBLC-fault  ( point ordinal context -- status )
    2DROP _PBLC-store-fault-at @ = IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

\ Context is a byte seed.  Mode 1 fails at the second logical chunk and
\ mode 2 throws there.  Successful calls fill exactly the requested span.
: _PBLC-source  ( logical-offset destination-a requested-u seed -- actual-u status )
    _PBLC-source-mode @ IF
        3 PICK PBLOB-CHUNK-SIZE = IF
            _PBLC-source-mode @ 2 = IF -7301 THROW THEN
            2DROP 2DROP 0 PERSIST-S-FAULT EXIT
        THEN
    THEN
    SWAP DUP >R
    0 ?DO
        1 PICK I +
        3 PICK I + 2 PICK + 255 AND
        SWAP C!
    LOOP
    2DROP DROP R> PERSIST-S-OK ;

: _PBLC-sink  ( logical-offset payload-a payload-u seed -- status )
    _PBLC-sink-mode @ 1 = IF 2DROP 2DROP PERSIST-S-FAULT EXIT THEN
    _PBLC-sink-mode @ 2 = IF -7302 THROW THEN
    _PBLC-sink-mode @ 3 = _PBLC-sink-calls @ 1 = AND IF
        2DROP 2DROP PERSIST-S-FAULT EXIT
    THEN
    SWAP DUP >R
    0 ?DO
        1 PICK I + C@
        3 PICK I + 2 PICK + 255 AND
        <> IF 1 _PBLC-sink-errors +! THEN
    LOOP
    2DROP DROP
    R> DUP _PBLC-sink-bytes +! DROP
    1 _PBLC-sink-calls +!
    PERSIST-S-OK ;

: _PBLC-fill-source  ( logical-offset destination-a requested-u byte -- actual-u status )
    >R ROT DROP
    2DUP R@ FILL NIP
    R> DROP PERSIST-S-OK ;

: _PBLC-fill-sink  ( logical-offset payload-a payload-u byte -- status )
    SWAP >R ROT DROP R>
    DUP >R
    0 ?DO
        OVER I + C@ OVER <> IF 1 _PBLC-sink-errors +! THEN
    LOOP
    2DROP
    R> DUP _PBLC-sink-bytes +! DROP
    1 _PBLC-sink-calls +!
    PERSIST-S-OK ;

: _PBLC-store-init  ( -- status )
    S" /blob-pages" S" /blob-segment" S" /blob-root-a" S" /blob-root-b"
    _PBLC-identity PBLOB-CHUNK-SIZE _PBLC-vfs @ 0 0 _PBLC-guard
    ['] _PBLC-fault 0 _PBLC-store PSTORE-INIT ;

: _PBLC-reopen-store-init  ( -- status )
    S" /blob-pages" S" /blob-segment" S" /blob-root-a" S" /blob-root-b"
    _PBLC-identity PBLOB-CHUNK-SIZE _PBLC-vfs @ 0 0 _PBLC-reopen-guard
    ['] _PBLC-fault 0 _PBLC-reopen-store PSTORE-INIT ;

: _PBLC-store-i0-init  ( -- status )
    S" /bi0-pages" S" /bi0-segment" S" /bi0-root-a" S" /bi0-root-b"
    _PBLC-identity-i0 PBLOB-CHUNK-SIZE _PBLC-vfs @ 0 0 _PBLC-guard-i0
    ['] _PBLC-fault 0 _PBLC-store-i0 PSTORE-INIT ;

: _PBLC-store-i1-init  ( -- status )
    S" /bi1-pages" S" /bi1-segment" S" /bi1-root-a" S" /bi1-root-b"
    _PBLC-identity-i1 PBLOB-CHUNK-SIZE _PBLC-vfs @ 0 0 _PBLC-guard-i1
    ['] _PBLC-fault 0 _PBLC-store-i1 PSTORE-INIT ;

: _PBLC-store-i2-init  ( -- status )
    S" /bi2-pages" S" /bi2-segment" S" /bi2-root-a" S" /bi2-root-b"
    _PBLC-identity-i2 PBLOB-CHUNK-SIZE _PBLC-vfs @ 0 0 _PBLC-guard-i2
    ['] _PBLC-fault 0 _PBLC-store-i2 PSTORE-INIT ;

: _PBLC-store-i3-init  ( -- status )
    S" /bi3-pages" S" /bi3-segment" S" /bi3-root-a" S" /bi3-root-b"
    _PBLC-identity-i3 PBLOB-CHUNK-SIZE _PBLC-vfs @ 0 0 _PBLC-guard-i3
    ['] _PBLC-fault 0 _PBLC-store-i3 PSTORE-INIT ;

: _PBLC-setup  ( -- )
    VFS-CUR _PBLC-old-vfs !
    VFS-RAM-OPS _PBLC-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _PBLC-binding VFS-BINDING-DESC-SIZE MOVE
    _PBLC-ops _PBLC-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW DUP 0= _PBLC-assert DROP _PBLC-arena !
    _PBLC-arena @ _PBLC-binding 0 VFS-NEW _PBLC-ior ! _PBLC-vfs !
    _PBLC-ior @ 0= _PBLC-assert
    _PBLC-vfs @ 0<> _PBLC-assert
    _PBLC-identity PERSIST-IDENTITY-SIZE 91 FILL
    0 _PBLC-store-fault-at !
    _PBLC-store-init PERSIST-S-OK _PBLC-status
    _PBLC-record-buffer 33000 _PBLC-store-work PSTORE-WORK-INIT
        PERSIST-S-OK _PBLC-status
    _PBLC-alias-buffer PBLOB-WORK-SIZE _PBLC-alias-store-work
        PSTORE-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-blob-work PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-read-work PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-store _PBLC-store-work PSTORE-PROVISION PERSIST-S-OK _PBLC-status
    _PBLC-store _PBLC-store-work PSTORE-OPEN PERSIST-S-ABSENT _PBLC-status
    _PBLC-stack ;

: _PBLC-descriptor-contracts  ( -- )
    0 PBLOB-WORK-INIT PERSIST-S-INVALID _PBLC-status
    _PBLC-blob PBLOB-SIZE 0 FILL
    _PBLC-blob PBLOB-VALID? 0= _PBLC-assert
    0 ['] _PBLC-source 7 _PBLC-empty _PBLC-store _PBLC-store-work
        _PBLC-blob-work PBLOB-WRITE PERSIST-S-BUSY _PBLC-status
    _PBLC-store _PBLC-store-work PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    1 ['] _PBLC-source 7 _PBLC-blob-work _PBLC-store _PBLC-store-work
        _PBLC-blob-work PBLOB-WRITE PERSIST-S-INVALID _PBLC-status
    1 ['] _PBLC-source 7 -32 _PBLC-store _PBLC-store-work
        _PBLC-blob-work PBLOB-WRITE PERSIST-S-INVALID _PBLC-status
    _PBLC-store _PBLC-store-work PSTORE-TX-READY? _PBLC-assert _PBLC-stack
    0 0 0 _PBLC-empty _PBLC-store _PBLC-store-work _PBLC-blob-work
        PBLOB-WRITE PERSIST-S-OK _PBLC-status
    _PBLC-empty PBLOB-VALID? _PBLC-assert
    _PBLC-empty PBLOB-TOTAL@ 0= _PBLC-assert
    _PBLC-empty PBLOB-CHUNK-COUNT@ 0= _PBLC-assert
    _PBLC-empty PBLOB-LEVEL@ -1 = _PBLC-assert
    _PBLC-empty PBLOB-ROOT@ 0= _PBLC-assert
    _PBLC-blob-work PBLOB-CHUNK-WRITES@ 0= _PBLC-assert
    _PBLC-blob-work PBLOB-MANIFEST-WRITES@ 0= _PBLC-assert
    _PBLC-store _PBLC-store-work PSTORE-ABORT PERSIST-S-OK _PBLC-status
    _PBLC-stack ;

: _PBLC-corruption-and-alias-contracts  ( -- )
    _PBLC-blob _PBLC-corrupt-blob PBLOB-COPY PERSIST-S-OK _PBLC-status
    1 _PBLC-corrupt-blob _PBL.LEVEL !
    _PBLC-corrupt-blob PBLOB-VALID? 0= _PBLC-assert
    _PBLC-blob _PBLC-corrupt-blob PBLOB-COPY PERSIST-S-OK _PBLC-status
    0 _PBLC-corrupt-blob _PBL.MAGIC !
    _PBLC-corrupt-blob PBLOB-VALID? 0= _PBLC-assert

    _PBLC-blob PBLOB-ROOT@ _PBLC-store _PBLC-store-work
        PSTORE-READ-RECORD PERSIST-S-OK _PBLC-status
    _PBLC-blob _PBLC-corrupt-blob PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-store-work PSTORE-RECORD-PAYLOAD$ DROP
        _PBLOB-NODE-HEADER-SIZE +
        _PBLC-corrupt-blob _PBL.ROOT PERSIST-REF-COPY
    _PBLC-corrupt-blob PBLOB-VALID? _PBLC-assert
    _PBLC-corrupt-blob 0 1 ['] _PBLC-sink 7 _PBLC-store
        _PBLC-store-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-CORRUPT _PBLC-status

    -1 _PBLC-read-work _PBW.BUSY !
    _PBLC-blob 0 1 ['] _PBLC-sink 7 _PBLC-store
        _PBLC-store-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-BUSY _PBLC-status
    0 _PBLC-read-work _PBW.BUSY !
    _PBLC-blob 0 1 ['] _PBLC-sink 7 _PBLC-store
        _PBLC-store-work _PBLC-store-work PBLOB-READ-RANGE
        PERSIST-S-INVALID _PBLC-status

    \ An otherwise-unbound PSTORE work still owns its borrowed record buffer.
    \ Neither the public blob descriptor nor the much larger blob workspace
    \ may hide inside that buffer and be clobbered by later record I/O.
    _PBLC-blob _PBLC-alias-buffer PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-alias-buffer 0 1 ['] _PBLC-sink 7 _PBLC-store
        _PBLC-alias-store-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-INVALID _PBLC-status
    _PBLC-alias-buffer PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-blob 0 1 ['] _PBLC-sink 7 _PBLC-store
        _PBLC-alias-store-work _PBLC-alias-buffer PBLOB-READ-RANGE
        PERSIST-S-INVALID _PBLC-status
    _PBLC-stack ;

: _PBLC-storage-fault-at  ( fault-point -- )
    _PBLC-store-fault-at !
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    8 ['] _PBLC-source 51 _PBLC-empty _PBLC-reopen-store
        _PBLC-reopen-work _PBLC-blob-work PBLOB-WRITE
        PERSIST-S-FAULT _PBLC-status
    _PBLC-empty PBLOB-VALID? 0= _PBLC-assert
    _PBLC-blob-work _PBW.BUSY @ 0= _PBLC-assert
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-ABORT
        PERSIST-S-OK _PBLC-status
    0 _PBLC-store-fault-at !
    _PBLC-vfs @ V.OPEN-COUNT @ 0= _PBLC-assert
    _PBLC-stack ;

: _PBLC-storage-faults  ( -- )
    PERSIST-FAULT-SEGMENT-WRITTEN _PBLC-storage-fault-at
    PERSIST-FAULT-SEGMENT-VERIFIED _PBLC-storage-fault-at ;

: _PBLC-write-and-commit  ( -- )
    0 _PBLC-source-mode !
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBLC-store _PBLC-store-work PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    PBLOB-CHUNK-SIZE 2 * 19 + ['] _PBLC-source 7 _PBLC-blob
        _PBLC-store _PBLC-store-work _PBLC-blob-work PBLOB-WRITE
        PERSIST-S-OK _PBLC-status
    _PBLC-blob PBLOB-VALID? _PBLC-assert
    _PBLC-blob PBLOB-TOTAL@ PBLOB-CHUNK-SIZE 2 * 19 + = _PBLC-assert
    _PBLC-blob PBLOB-CHUNK-COUNT@ 3 = _PBLC-assert
    _PBLC-blob PBLOB-LEVEL@ 0= _PBLC-assert
    _PBLC-blob-work PBLOB-CHUNK-WRITES@ 3 = _PBLC-assert
    _PBLC-blob-work PBLOB-MANIFEST-WRITES@ 1 = _PBLC-assert
    _PBLC-blob-work PBLOB-BYTES@ PBLOB-CHUNK-SIZE 2 * 19 + = _PBLC-assert
    _PBLC-blob-work PBLOB-CALLBACKS@ 3 = _PBLC-assert
    _PBLC-blob-work PBLOB-WORKING-PEAK@ PBLOB-WORK-SIZE = _PBLC-assert
    _PBLC-blob _PBLC-page PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE _PBLC-store _PBLC-store-work
        PSTORE-APPEND-PAGE SWAP _PBLC-page-id ! PERSIST-S-OK _PBLC-status
    _PBLC-page-id @ 0= _PBLC-assert
    _PBLC-page-id @ _PBLC-store _PBLC-store-work PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBLC-status
    _PBLC-store _PBLC-store-work PSTORE-COMMIT PERSIST-S-OK _PBLC-status
    _PBLC-store PSTORE-CURRENT-ROOT@ PROOTV.RECORD-COUNT @ 4 = _PBLC-assert
    _PBLC-stack ;

: _PBLC-range-contracts  ( -- )
    0 _PBLC-sink-mode ! 0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls !
    0 _PBLC-sink-errors !
    _PBLC-blob PBLOB-CHUNK-SIZE 8 - 32 ['] _PBLC-sink 7
        _PBLC-store _PBLC-store-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 32 = _PBLC-assert
    _PBLC-sink-calls @ 2 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-read-work PBLOB-CHUNK-READS@ 2 = _PBLC-assert
    _PBLC-read-work PBLOB-MANIFEST-READS@ 2 = _PBLC-assert
    _PBLC-read-work PBLOB-BYTES@ 32 = _PBLC-assert
    _PBLC-read-work PBLOB-CALLBACKS@ 2 = _PBLC-assert
    _PBLC-stack

    \ Stream the complete 65,555-byte blob, crossing the current fixed
    \ 64 KiB Library view rather than proving only a short range near EOF.
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    _PBLC-blob 0 ['] _PBLC-sink 7 _PBLC-store _PBLC-store-work
        _PBLC-read-work PBLOB-STREAM PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ PBLOB-CHUNK-SIZE 2 * 19 + = _PBLC-assert
    _PBLC-sink-calls @ 3 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-read-work PBLOB-CHUNK-READS@ 3 = _PBLC-assert
    _PBLC-read-work PBLOB-MANIFEST-READS@ 3 = _PBLC-assert
    _PBLC-read-work PBLOB-BYTES@ PBLOB-CHUNK-SIZE 2 * 19 + = _PBLC-assert
    _PBLC-read-work PBLOB-CALLBACKS@ 3 = _PBLC-assert

    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    _PBLC-blob PBLOB-CHUNK-SIZE 2 * 11 + ['] _PBLC-sink 7
        _PBLC-store _PBLC-store-work _PBLC-read-work PBLOB-STREAM
        PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 8 = _PBLC-assert
    _PBLC-sink-calls @ 1 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert

    _PBLC-blob PBLOB-CHUNK-SIZE 2 * 20 + 0 ['] _PBLC-sink 7
        _PBLC-store _PBLC-store-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-NOT-FOUND _PBLC-status
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    _PBLC-blob PBLOB-CHUNK-SIZE 2 * 18 + PERSIST-MAX-SIGNED
        ['] _PBLC-sink 7 _PBLC-store _PBLC-store-work _PBLC-read-work
        PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 1 = _PBLC-assert
    _PBLC-sink-calls @ 1 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-read-work PBLOB-BYTES@ 1 = _PBLC-assert
    _PBLC-blob 0 -1 ['] _PBLC-sink 7
        _PBLC-store _PBLC-store-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-INVALID _PBLC-status
    _PBLC-stack ;

: _PBLC-level-one-contracts  ( -- )
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBLC-store _PBLC-store-work PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    PBLOB-CHUNK-SIZE 64 * 5 + ['] _PBLC-fill-source 23 _PBLC-deep-blob
        _PBLC-store _PBLC-store-work _PBLC-blob-work PBLOB-WRITE
        PERSIST-S-OK _PBLC-status
    _PBLC-deep-blob PBLOB-VALID? _PBLC-assert
    _PBLC-deep-blob PBLOB-CHUNK-COUNT@ 65 = _PBLC-assert
    _PBLC-deep-blob PBLOB-LEVEL@ 1 = _PBLC-assert
    _PBLC-blob-work PBLOB-CHUNK-WRITES@ 65 = _PBLC-assert
    _PBLC-blob-work PBLOB-MANIFEST-WRITES@ 3 = _PBLC-assert
    _PBLC-blob-work PBLOB-CALLBACKS@ 65 = _PBLC-assert
    _PBLC-blob-work PBLOB-BYTES@ PBLOB-CHUNK-SIZE 64 * 5 + = _PBLC-assert
    _PBLC-deep-blob _PBLC-page PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE _PBLC-store _PBLC-store-work
        PSTORE-APPEND-PAGE SWAP _PBLC-page-id ! PERSIST-S-OK _PBLC-status
    _PBLC-page-id @ 1 = _PBLC-assert
    1 _PBLC-store _PBLC-store-work PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBLC-status
    _PBLC-store _PBLC-store-work PSTORE-COMMIT PERSIST-S-OK _PBLC-status

    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    _PBLC-deep-blob PBLOB-CHUNK-SIZE 64 * 4 - 12
        ['] _PBLC-fill-sink 23 _PBLC-store _PBLC-store-work _PBLC-read-work
        PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 9 = _PBLC-assert
    _PBLC-sink-calls @ 2 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-read-work PBLOB-CHUNK-READS@ 2 = _PBLC-assert
    _PBLC-read-work PBLOB-MANIFEST-READS@ 4 = _PBLC-assert
    _PBLC-read-work PBLOB-BYTES@ 9 = _PBLC-assert

    \ Exercise every chunk and both manifest levels, rather than inferring
    \ the level-one traversal from a two-chunk boundary sample.
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    _PBLC-deep-blob 0 ['] _PBLC-fill-sink 23 _PBLC-store
        _PBLC-store-work _PBLC-read-work PBLOB-STREAM
        PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ PBLOB-CHUNK-SIZE 64 * 5 + = _PBLC-assert
    _PBLC-sink-calls @ 65 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-read-work PBLOB-CHUNK-READS@ 65 = _PBLC-assert
    _PBLC-read-work PBLOB-MANIFEST-READS@ 130 = _PBLC-assert
    _PBLC-read-work PBLOB-BYTES@ PBLOB-CHUNK-SIZE 64 * 5 + = _PBLC-assert
    _PBLC-read-work PBLOB-CALLBACKS@ 65 = _PBLC-assert
    _PBLC-stack ;

: _PBLC-cold-reopen  ( -- )
    _PBLC-reopen-store-init PERSIST-S-OK _PBLC-status
    _PBLC-reopen-buffer 33000 _PBLC-reopen-work PSTORE-WORK-INIT
        PERSIST-S-OK _PBLC-status
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-PROVISION
        PERSIST-S-OK _PBLC-status
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-OPEN PERSIST-S-OK _PBLC-status
    0 _PBLC-reopen-store _PBLC-reopen-work PSTORE-READ-PAGE
        PERSIST-S-OK _PBLC-status
    _PBLC-reopen-work PSTORE-PAGE-PAYLOAD$ DROP
        _PBLC-reopened-blob PBLOB-SIZE MOVE
    _PBLC-reopened-blob PBLOB-VALID? _PBLC-assert
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    _PBLC-reopened-blob PBLOB-CHUNK-SIZE 4 - 12 ['] _PBLC-sink 7
        _PBLC-reopen-store _PBLC-reopen-work _PBLC-read-work
        PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 12 = _PBLC-assert
    _PBLC-sink-calls @ 2 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-stack ;

: _PBLC-source-fault-at  ( mode -- )
    _PBLC-source-mode !
    _PBLC-reopen-store PSTORE-GENERATION@ _PBLC-old-generation !
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    PBLOB-CHUNK-SIZE 2 * ['] _PBLC-source 3 _PBLC-empty
        _PBLC-reopen-store _PBLC-reopen-work _PBLC-blob-work PBLOB-WRITE
        PERSIST-S-FAULT _PBLC-status
    _PBLC-blob-work _PBW.BUSY @ 0= _PBLC-assert
    _PBLC-empty PBLOB-VALID? 0= _PBLC-assert
    _PBLC-blob-work PBLOB-CHUNK-WRITES@ 1 = _PBLC-assert
    _PBLC-blob-work PBLOB-CALLBACKS@
        _PBLC-source-mode @ 1 = IF 2 ELSE 1 THEN = _PBLC-assert
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-TX-READY? 0= _PBLC-assert
    _PBLC-reopen-store PSTORE-STATUS@ PERSIST-S-FAULT _PBLC-status
    _PBLC-reopen-work PSTORE-WORK-STATUS@ PERSIST-S-FAULT _PBLC-status
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-COMMIT
        PERSIST-S-CONFLICT _PBLC-status
    _PBLC-reopen-store PSTORE-GENERATION@
        _PBLC-old-generation @ = _PBLC-assert
    _PBLC-reopen-store PSTORE-STATUS@ PERSIST-S-FAULT _PBLC-status
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-ABORT PERSIST-S-OK _PBLC-status
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    _PBLC-reopen-work PSTORE-PROPOSED-ROOT@ PROOTV.SEGMENT-TAIL @
        _PBLC-reopen-store PSTORE-CURRENT-ROOT@ PROOTV.SEGMENT-TAIL @ =
        _PBLC-assert
    _PBLC-reopen-store _PBLC-reopen-work PSTORE-ABORT
        PERSIST-S-OK _PBLC-status ;

: _PBLC-callback-faults  ( -- )
    1 _PBLC-source-fault-at
    2 _PBLC-source-fault-at
    0 _PBLC-source-mode !

    1 _PBLC-sink-mode !
    _PBLC-reopened-blob 0 8 ['] _PBLC-sink 7 _PBLC-reopen-store
        _PBLC-reopen-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-FAULT _PBLC-status
    _PBLC-read-work _PBW.BUSY @ 0= _PBLC-assert
    2 _PBLC-sink-mode !
    _PBLC-reopened-blob 0 8 ['] _PBLC-sink 7 _PBLC-reopen-store
        _PBLC-reopen-work _PBLC-read-work PBLOB-READ-RANGE
        PERSIST-S-FAULT _PBLC-status
    _PBLC-read-work _PBW.BUSY @ 0= _PBLC-assert

    \ Delivery is progressive across chunks: a second-callback fault does
    \ not erase the first callback or its eight delivered bytes.
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-calls ! 0 _PBLC-sink-errors !
    3 _PBLC-sink-mode !
    _PBLC-reopened-blob PBLOB-CHUNK-SIZE 8 - 32 ['] _PBLC-sink 7
        _PBLC-reopen-store _PBLC-reopen-work _PBLC-read-work
        PBLOB-READ-RANGE PERSIST-S-FAULT _PBLC-status
    _PBLC-sink-calls @ 1 = _PBLC-assert
    _PBLC-sink-bytes @ 8 = _PBLC-assert
    _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-read-work PBLOB-CALLBACKS@ 2 = _PBLC-assert
    _PBLC-read-work PBLOB-BYTES@ 8 = _PBLC-assert
    0 _PBLC-sink-mode !
    _PBLC-vfs @ V.OPEN-COUNT @ 0= _PBLC-assert
    _PBLC-stack ;

: _PBLC-four-store-setup  ( -- )
    _PBLC-identity-i0 PERSIST-IDENTITY-SIZE 11 FILL
    _PBLC-identity-i1 PERSIST-IDENTITY-SIZE 22 FILL
    _PBLC-identity-i2 PERSIST-IDENTITY-SIZE 33 FILL
    _PBLC-identity-i3 PERSIST-IDENTITY-SIZE 44 FILL
    _PBLC-store-i0-init PERSIST-S-OK _PBLC-status
    _PBLC-store-i1-init PERSIST-S-OK _PBLC-status
    _PBLC-store-i2-init PERSIST-S-OK _PBLC-status
    _PBLC-store-i3-init PERSIST-S-OK _PBLC-status
    _PBLC-buffer-i0 33000 _PBLC-work-i0 PSTORE-WORK-INIT
        PERSIST-S-OK _PBLC-status
    _PBLC-buffer-i1 33000 _PBLC-work-i1 PSTORE-WORK-INIT
        PERSIST-S-OK _PBLC-status
    _PBLC-buffer-i2 33000 _PBLC-work-i2 PSTORE-WORK-INIT
        PERSIST-S-OK _PBLC-status
    _PBLC-buffer-i3 33000 _PBLC-work-i3 PSTORE-WORK-INIT
        PERSIST-S-OK _PBLC-status
    _PBLC-bwork-i0 PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-bwork-i1 PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-bwork-i2 PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-bwork-i3 PBLOB-WORK-INIT PERSIST-S-OK _PBLC-status
    _PBLC-store-i0 _PBLC-work-i0 PSTORE-PROVISION PERSIST-S-OK _PBLC-status
    _PBLC-store-i1 _PBLC-work-i1 PSTORE-PROVISION PERSIST-S-OK _PBLC-status
    _PBLC-store-i2 _PBLC-work-i2 PSTORE-PROVISION PERSIST-S-OK _PBLC-status
    _PBLC-store-i3 _PBLC-work-i3 PSTORE-PROVISION PERSIST-S-OK _PBLC-status
    _PBLC-store-i0 _PBLC-work-i0 PSTORE-OPEN PERSIST-S-ABSENT _PBLC-status
    _PBLC-store-i1 _PBLC-work-i1 PSTORE-OPEN PERSIST-S-ABSENT _PBLC-status
    _PBLC-store-i2 _PBLC-work-i2 PSTORE-OPEN PERSIST-S-ABSENT _PBLC-status
    _PBLC-store-i3 _PBLC-work-i3 PSTORE-OPEN PERSIST-S-ABSENT _PBLC-status ;

: _PBLC-four-store-interleave  ( -- )
    _PBLC-four-store-setup
    _PBLC-store-i0 _PBLC-work-i0 PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    _PBLC-store-i1 _PBLC-work-i1 PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    _PBLC-store-i2 _PBLC-work-i2 PSTORE-BEGIN PERSIST-S-OK _PBLC-status
    _PBLC-store-i3 _PBLC-work-i3 PSTORE-BEGIN PERSIST-S-OK _PBLC-status

    \ A valid active workspace owned by another store must be rejected
    \ before descriptor mutation or a source callback.
    _PBLC-blob-i0 PBLOB-SIZE 0xA5 FILL
    _PBLC-blob-i0 _PBLC-mismatch-before PBLOB-SIZE MOVE
    5 ['] _PBLC-source 11 _PBLC-blob-i0 _PBLC-store-i0 _PBLC-work-i1
        _PBLC-bwork-i0 PBLOB-WRITE PERSIST-S-BUSY _PBLC-status
    _PBLC-bwork-i0 PBLOB-CALLBACKS@ 0= _PBLC-assert
    _PBLC-blob-i0 _PBLC-mismatch-before PBLOB-SIZE _PBLC-bytes=
        _PBLC-assert

    5 ['] _PBLC-source 11 _PBLC-blob-i0 _PBLC-store-i0 _PBLC-work-i0
        _PBLC-bwork-i0 PBLOB-WRITE PERSIST-S-OK _PBLC-status
    6 ['] _PBLC-source 22 _PBLC-blob-i1 _PBLC-store-i1 _PBLC-work-i1
        _PBLC-bwork-i1 PBLOB-WRITE PERSIST-S-OK _PBLC-status
    7 ['] _PBLC-source 33 _PBLC-blob-i2 _PBLC-store-i2 _PBLC-work-i2
        _PBLC-bwork-i2 PBLOB-WRITE PERSIST-S-OK _PBLC-status
    8 ['] _PBLC-source 44 _PBLC-blob-i3 _PBLC-store-i3 _PBLC-work-i3
        _PBLC-bwork-i3 PBLOB-WRITE PERSIST-S-OK _PBLC-status

    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBLC-blob-i0 _PBLC-page PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE _PBLC-store-i0 _PBLC-work-i0
        PSTORE-APPEND-PAGE SWAP DROP PERSIST-S-OK _PBLC-status
    0 _PBLC-store-i0 _PBLC-work-i0 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBLC-blob-i1 _PBLC-page PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE _PBLC-store-i1 _PBLC-work-i1
        PSTORE-APPEND-PAGE SWAP DROP PERSIST-S-OK _PBLC-status
    0 _PBLC-store-i1 _PBLC-work-i1 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBLC-blob-i2 _PBLC-page PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE _PBLC-store-i2 _PBLC-work-i2
        PSTORE-APPEND-PAGE SWAP DROP PERSIST-S-OK _PBLC-status
    0 _PBLC-store-i2 _PBLC-work-i2 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PBLC-blob-i3 _PBLC-page PBLOB-COPY PERSIST-S-OK _PBLC-status
    _PBLC-page PERSIST-PAGE-PAYLOAD-SIZE _PBLC-store-i3 _PBLC-work-i3
        PSTORE-APPEND-PAGE SWAP DROP PERSIST-S-OK _PBLC-status
    0 _PBLC-store-i3 _PBLC-work-i3 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PBLC-status

    _PBLC-store-i2 _PBLC-work-i2 PSTORE-COMMIT PERSIST-S-OK _PBLC-status
    _PBLC-store-i0 _PBLC-work-i0 PSTORE-COMMIT PERSIST-S-OK _PBLC-status
    _PBLC-store-i3 _PBLC-work-i3 PSTORE-COMMIT PERSIST-S-OK _PBLC-status
    _PBLC-store-i1 _PBLC-work-i1 PSTORE-COMMIT PERSIST-S-OK _PBLC-status
    _PBLC-store-i0 PSTORE-GENERATION@ 1 = _PBLC-assert
    _PBLC-store-i1 PSTORE-GENERATION@ 1 = _PBLC-assert
    _PBLC-store-i2 PSTORE-GENERATION@ 1 = _PBLC-assert
    _PBLC-store-i3 PSTORE-GENERATION@ 1 = _PBLC-assert

    0 _PBLC-sink-bytes ! 0 _PBLC-sink-errors ! 0 _PBLC-sink-calls !
    _PBLC-blob-i0 0 5 ['] _PBLC-sink 11 _PBLC-store-i0 _PBLC-work-i0
        _PBLC-bwork-i0 PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 5 = _PBLC-assert _PBLC-sink-errors @ 0= _PBLC-assert
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-errors ! 0 _PBLC-sink-calls !
    _PBLC-blob-i1 0 6 ['] _PBLC-sink 22 _PBLC-store-i1 _PBLC-work-i1
        _PBLC-bwork-i1 PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 6 = _PBLC-assert _PBLC-sink-errors @ 0= _PBLC-assert
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-errors ! 0 _PBLC-sink-calls !
    _PBLC-blob-i2 0 7 ['] _PBLC-sink 33 _PBLC-store-i2 _PBLC-work-i2
        _PBLC-bwork-i2 PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 7 = _PBLC-assert _PBLC-sink-errors @ 0= _PBLC-assert
    0 _PBLC-sink-bytes ! 0 _PBLC-sink-errors ! 0 _PBLC-sink-calls !
    _PBLC-blob-i3 0 8 ['] _PBLC-sink 44 _PBLC-store-i3 _PBLC-work-i3
        _PBLC-bwork-i3 PBLOB-READ-RANGE PERSIST-S-OK _PBLC-status
    _PBLC-sink-bytes @ 8 = _PBLC-assert _PBLC-sink-errors @ 0= _PBLC-assert
    _PBLC-vfs @ V.OPEN-COUNT @ 0= _PBLC-assert
    _PBLC-stack ;

: _PBLC-run  ( -- )
    0 _PBLC-fails ! 0 _PBLC-checks ! DEPTH _PBLC-depth !
    0 _PBLC-source-mode ! 0 _PBLC-sink-mode !
    _PBLC-setup
    _PBLC-descriptor-contracts
    _PBLC-write-and-commit
    _PBLC-range-contracts
    _PBLC-level-one-contracts
    _PBLC-corruption-and-alias-contracts
    _PBLC-cold-reopen
    _PBLC-callback-faults
    _PBLC-storage-faults
    _PBLC-four-store-interleave
    _PBLC-old-vfs @ VFS-USE
    _PBLC-vfs @ VFS-DESTROY
    _PBLC-stack
    _PBLC-fails @ 0= IF
        ." PERSISTENCE BLOB PASS " _PBLC-checks @ . CR
    ELSE
        ." PERSISTENCE BLOB FAIL " _PBLC-fails @ . ." /" _PBLC-checks @ . CR
    THEN ;
