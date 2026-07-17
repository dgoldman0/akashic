\ Deterministic contracts for the fixed-capacity VFS snapshot core.

32 CONSTANT _VFSNC-PAYLOAD-U
VFSNAP-HEADER-SIZE _VFSNC-PAYLOAD-U + CONSTANT _VFSNC-SCRATCH-U
_VFSNC-SCRATCH-U 1+ CONSTANT _VFSNC-RAW-U
VFSNAP-STORE-SIZE _VFSNC-SCRATCH-U + 64 + CONSTANT _VFSNC-ALIAS-U

VARIABLE _vfsnc-fails
VARIABLE _vfsnc-checks
VARIABLE _vfsnc-depth
VARIABLE _vfsnc-byte
VARIABLE _vfsnc-old-vfs
VARIABLE _vfsnc-vfs
VARIABLE _vfsnc-spec
VARIABLE _vfsnc-spec-probe
VARIABLE _vfsnc-store-a
VARIABLE _vfsnc-store-b
VARIABLE _vfsnc-scratch-a
VARIABLE _vfsnc-scratch-b
VARIABLE _vfsnc-context
VARIABLE _vfsnc-destination
VARIABLE _vfsnc-generation
VARIABLE _vfsnc-raw-a
VARIABLE _vfsnc-raw-b
VARIABLE _vfsnc-alias
VARIABLE _vfsnc-output
VARIABLE _vfsnc-fd
VARIABLE _vfsnc-data-a
VARIABLE _vfsnc-data-u
VARIABLE _vfsnc-path-a
VARIABLE _vfsnc-path-u
VARIABLE _vfsnc-read-dst
VARIABLE _vfsnc-read-store
VARIABLE _vfsnc-read-u
VARIABLE _vfsnc-case-store
VARIABLE _vfsnc-case-status
VARIABLE _vfsnc-old-vtable
VARIABLE _vfsnc-old-read-xt
VARIABLE _vfsnc-old-sync-xt
VARIABLE _vfsnc-old-delete-xt
VARIABLE _vfsnc-fault-count
VARIABLE _vfsnc-fault-at
VARIABLE _vfsnc-sync-armed
VARIABLE _vfsnc-close-count
VARIABLE _vfsnc-restore-count
VARIABLE _vfsnc-encode-generation

CREATE _vfsnc-record-magic
    65 C, 75 C, 86 C, 70 C, 83 C, 78 C, 48 C, 49 C,  \ "AKVFSN01"
CREATE _vfsnc-private-adjacent 16 ALLOT
CREATE _vfsnc-vtable VFS-VT-SIZE ALLOT

CREATE _vfsnc-callback-private-begin 0 ALLOT
VARIABLE _vfsnc-cb-context
VARIABLE _vfsnc-cb-payload
VARIABLE _vfsnc-cb-payload-u
VARIABLE _vfsnc-cb-generation
VARIABLE _vfsnc-cb-reenter
VARIABLE _vfsnc-cb-store
VARIABLE _vfsnc-cb-nested-status
VARIABLE _vfsnc-cb-encode-throw
VARIABLE _vfsnc-cb-validate-throw
VARIABLE _vfsnc-cb-zero-payload
CREATE _vfsnc-callback-private-end 0 ALLOT

: _vfsnc-assert  ( flag -- )
    1 _vfsnc-checks +!
    0= IF 1 _vfsnc-fails +! ." VFSNC ASSERT " _vfsnc-checks @ . CR THEN ;

: _vfsnc-stack  ( -- )
    DEPTH DUP _vfsnc-depth @ <> IF
        ." VFSNC STACK " _vfsnc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _vfsnc-depth @ = _vfsnc-assert ;

: _vfsnc-allocate  ( size variable -- )
    >R ALLOCATE ABORT" VFS FIXED SNAPSHOT CONTRACTS FAIL allocation"
    R> ! ;
: _vfsnc-free  ( variable -- )
    DUP @ ?DUP IF FREE 0 SWAP ! ELSE DROP THEN ;
: _vfsnc-filled?  ( a u byte -- flag )
    _vfsnc-byte ! 0 ?DO
        DUP I + C@ _vfsnc-byte @ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;
: _vfsnc-scratch-zero?  ( store -- flag )
    VFSNAP-SCRATCH$ 0 _vfsnc-filled? ;

: _vfsnc-encode  ( context payload-a payload-u next-generation -- status )
    _vfsnc-cb-generation ! _vfsnc-cb-payload-u !
    _vfsnc-cb-payload ! _vfsnc-cb-context !
    _vfsnc-cb-encode-throw @ IF -777 THROW THEN
    _vfsnc-cb-context @ 0= IF VFSNAP-S-INVALID EXIT THEN
    _vfsnc-cb-payload-u @ _VFSNC-PAYLOAD-U <> IF
        VFSNAP-S-CAPACITY EXIT
    THEN
    -1 _vfsnc-cb-zero-payload !
    _vfsnc-cb-payload-u @ 0 ?DO
        _vfsnc-cb-payload @ I + C@ IF
            0 _vfsnc-cb-zero-payload ! LEAVE
        THEN
    LOOP
    _vfsnc-cb-generation @ _vfsnc-cb-payload @ !
    _vfsnc-cb-context @ 8 + _vfsnc-cb-payload @ 8 +
        _VFSNC-PAYLOAD-U 8 - CMOVE
    _vfsnc-cb-reenter @ IF
        _vfsnc-cb-store @ VFSNAP-RECOVER _vfsnc-cb-nested-status !
    THEN
    VFSNAP-S-OK ;

: _vfsnc-validate  ( payload-a payload-u envelope-generation -- status )
    _vfsnc-cb-generation ! _vfsnc-cb-payload-u ! _vfsnc-cb-payload !
    _vfsnc-cb-validate-throw @ IF -778 THROW THEN
    _vfsnc-cb-payload-u @ _VFSNC-PAYLOAD-U <> IF
        VFSNAP-S-CORRUPT EXIT
    THEN
    _vfsnc-cb-payload @ @ _vfsnc-cb-generation @ <> IF
        VFSNAP-S-CORRUPT EXIT
    THEN
    VFSNAP-S-OK ;

: _vfsnc-put  ( data-a data-u path-a path-u -- )
    _vfsnc-path-u ! _vfsnc-path-a ! _vfsnc-data-u ! _vfsnc-data-a !
    _vfsnc-path-a @ _vfsnc-path-u @ _vfsnc-vfs @ VFS-RESOLVE IF
        _vfsnc-path-a @ _vfsnc-path-u @ _vfsnc-vfs @ VFS-RM
            0= _vfsnc-assert
    THEN
    _vfsnc-path-a @ _vfsnc-path-u @ _vfsnc-vfs @ VFS-CREATE
        DUP 0<> _vfsnc-assert DUP 0= IF DROP EXIT THEN DROP
    _vfsnc-path-a @ _vfsnc-path-u @ VFS-OPEN DUP _vfsnc-fd !
        0<> _vfsnc-assert
    _vfsnc-fd @ 0= IF EXIT THEN
    _vfsnc-data-a @ _vfsnc-data-u @ _vfsnc-fd @ VFS-WRITE-EXACT
        0= _vfsnc-assert
    _vfsnc-fd @ VFS-CLOSE
    _vfsnc-vfs @ VFS-SYNC 0= _vfsnc-assert ;

: _vfsnc-put-target  ( data-a data-u store -- )
    >R R@ VFSNAP-PATH$ _vfsnc-put R> DROP ;

: _vfsnc-read-target  ( destination store -- length )
    _vfsnc-read-store ! _vfsnc-read-dst !
    _vfsnc-read-store @ VFSNAP-PATH$ VFS-OPEN DUP _vfsnc-fd !
        0<> _vfsnc-assert
    _vfsnc-fd @ 0= IF 0 EXIT THEN
    _vfsnc-fd @ VFS-SIZE _vfsnc-read-u !
    _vfsnc-read-u @ 0>= _vfsnc-assert
    _vfsnc-read-u @ _VFSNC-RAW-U <= _vfsnc-assert
    _vfsnc-read-u @ _VFSNC-RAW-U <= IF
        _vfsnc-read-dst @ _vfsnc-read-u @ _vfsnc-fd @ VFS-READ-EXACT
            0= _vfsnc-assert
    THEN
    _vfsnc-fd @ VFS-CLOSE _vfsnc-read-u @ ;

: _vfsnc-file-present?  ( path-a path-u -- flag )
    _vfsnc-vfs @ VFS-RESOLVE 0<> ;
: _vfsnc-stage-present?  ( store -- flag )
    VFSNAP.REPLACE VREPL-STAGE$ _vfsnc-file-present? ;
: _vfsnc-backup-present?  ( store -- flag )
    VFSNAP.REPLACE VREPL-BACKUP$ _vfsnc-file-present? ;
: _vfsnc-marker-present?  ( store -- flag )
    VFSNAP.REPLACE VREPL-MARKER$ _vfsnc-file-present? ;
: _vfsnc-artifacts-clean?  ( store -- flag )
    DUP _vfsnc-stage-present? 0=
    OVER _vfsnc-backup-present? 0= AND
    SWAP _vfsnc-marker-present? 0= AND ;

: _vfsnc-store-init  ( path-a path-u scratch store -- )
    >R _VFSNC-SCRATCH-U _vfsnc-vfs @ _vfsnc-spec @ R@
        VFSNAP-INIT-AT VFSNAP-S-OK = _vfsnc-assert
    R> DROP ;

: _vfsnc-fini-if-valid  ( store -- )
    DUP VFSNAP-VALID? IF
        VFSNAP-FINI VFSNAP-S-OK = _vfsnc-assert
    ELSE DROP THEN ;

: _vfsnc-reset-a  ( path-a path-u -- )
    _vfsnc-store-a @ _vfsnc-fini-if-valid
    _vfsnc-scratch-a @ _vfsnc-store-a @ _vfsnc-store-init ;
: _vfsnc-reset-b  ( path-a path-u -- )
    _vfsnc-store-b @ _vfsnc-fini-if-valid
    _vfsnc-scratch-b @ _vfsnc-store-b @ _vfsnc-store-init ;

: _vfsnc-blocking-load  ( expected-status store -- )
    _vfsnc-case-store ! _vfsnc-case-status !
    _vfsnc-destination @ _VFSNC-PAYLOAD-U 90 FILL
    77 _vfsnc-generation @ !
    _vfsnc-destination @ _VFSNC-PAYLOAD-U _vfsnc-generation @
        _vfsnc-case-store @ VFSNAP-LOAD
        _vfsnc-case-status @ = _vfsnc-assert
    _vfsnc-destination @ _VFSNC-PAYLOAD-U 90 _vfsnc-filled?
        _vfsnc-assert
    _vfsnc-generation @ @ 77 = _vfsnc-assert
    _vfsnc-case-store @ VFSNAP-BLOCKED? _vfsnc-assert
    _vfsnc-case-store @ VFSNAP-LAST-STATUS@
        _vfsnc-case-status @ = _vfsnc-assert
    _vfsnc-case-store @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-case-store @ VFSNAP-SCRATCH$ 73 FILL
    _vfsnc-context @ 1 _vfsnc-case-store @ VFSNAP-SAVE
        _vfsnc-case-status @ = _vfsnc-assert
    _vfsnc-case-store @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-case-store @ VFSNAP-RECOVER
        _vfsnc-case-status @ = _vfsnc-assert
    _vfsnc-case-store @ VFSNAP-BLOCKED? _vfsnc-assert
    _vfsnc-case-store @ VFSNAP-LAST-STATUS@
        _vfsnc-case-status @ = _vfsnc-assert
    _vfsnc-case-store @ _vfsnc-scratch-zero? _vfsnc-assert ;

: _vfsnc-spec-contracts  ( -- )
    _vfsnc-spec-probe @ VFSNAP-SPEC-SIZE 90 FILL
    _vfsnc-record-magic 7 1 _VFSNC-PAYLOAD-U
        ['] _vfsnc-encode ['] _vfsnc-validate _vfsnc-spec-probe @
        VFSNAP-SPEC-INIT VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-spec-probe @ VFSNAP-SPEC-SIZE 90 _vfsnc-filled?
        _vfsnc-assert
    _vfsnc-record-magic 9 1 _VFSNC-PAYLOAD-U
        ['] _vfsnc-encode ['] _vfsnc-validate _vfsnc-spec-probe @
        VFSNAP-SPEC-INIT VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-record-magic 8 1 0
        ['] _vfsnc-encode ['] _vfsnc-validate _vfsnc-spec-probe @
        VFSNAP-SPEC-INIT VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-record-magic 8 1 _VFSNC-PAYLOAD-U
        0 ['] _vfsnc-validate _vfsnc-spec-probe @
        VFSNAP-SPEC-INIT VFSNAP-S-INVALID = _vfsnc-assert

    _vfsnc-record-magic 8 1 _VFSNC-PAYLOAD-U
        ['] _vfsnc-encode ['] _vfsnc-validate _vfsnc-spec @
        VFSNAP-SPEC-INIT VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-spec @ VFSNAP-SPEC.RECORD-MAGIC 8
        _vfsnc-record-magic 8 COMPARE 0= _vfsnc-assert
    _vfsnc-private-adjacent 8 _vfsnc-spec @ VFSNAP-SPEC-PRIVATE-ADD
        VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-private-adjacent 8 + 8 _vfsnc-spec @
        VFSNAP-SPEC-PRIVATE-ADD VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-private-adjacent 4 + 8 _vfsnc-spec @
        VFSNAP-SPEC-PRIVATE-ADD VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-callback-private-begin
        _vfsnc-callback-private-end _vfsnc-callback-private-begin -
        _vfsnc-spec @ VFSNAP-SPEC-PRIVATE-ADD
        VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-spec @ VFSNAP-SPEC-SEAL VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-spec @ VFSNAP-SPEC-SEALED? _vfsnc-assert
    _vfsnc-output @ 8 _vfsnc-spec @ VFSNAP-SPEC-PRIVATE-ADD
        VFSNAP-S-BUSY = _vfsnc-assert
    _vfsnc-stack ;

: _vfsnc-basic-contracts  ( -- )
    S" /vfsnap-main.bin" _vfsnc-reset-a
    _vfsnc-store-a @ VFSNAP-VALID? _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-PATH$ S" /vfsnap-main.bin" COMPARE 0=
        _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert

    _vfsnc-destination @ _VFSNC-PAYLOAD-U 90 FILL
    77 _vfsnc-generation @ !
    _vfsnc-destination @ _VFSNC-PAYLOAD-U _vfsnc-generation @
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-ABSENT = _vfsnc-assert
    _vfsnc-destination @ _VFSNC-PAYLOAD-U 90 _vfsnc-filled?
        _vfsnc-assert
    _vfsnc-generation @ @ 77 = _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert

    _vfsnc-context @ _VFSNC-PAYLOAD-U 165 FILL
    _vfsnc-context @ 0 _vfsnc-store-a @ VFSNAP-SAVE
        VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-cb-zero-payload @ _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-destination @ _VFSNC-PAYLOAD-U 0 FILL
    0 _vfsnc-generation @ !
    _vfsnc-destination @ _VFSNC-PAYLOAD-U _vfsnc-generation @
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-generation @ @ 1 = _vfsnc-assert
    _vfsnc-destination @ @ 1 = _vfsnc-assert
    _vfsnc-destination @ 8 + _VFSNC-PAYLOAD-U 8 - 165
        _vfsnc-filled? _vfsnc-assert
    _vfsnc-context @ 0 _vfsnc-store-a @ VFSNAP-SAVE
        VFSNAP-S-CONFLICT = _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-BLOCKED? 0= _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert

    _vfsnc-destination @ _VFSNC-PAYLOAD-U 90 FILL
    _vfsnc-destination @ _VFSNC-PAYLOAD-U 1- _vfsnc-generation @
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-CAPACITY = _vfsnc-assert
    _vfsnc-destination @ _VFSNC-PAYLOAD-U 90 _vfsnc-filled?
        _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-context @ 0x7FFFFFFFFFFFFFFF _vfsnc-store-a @ VFSNAP-SAVE
        VFSNAP-S-CAPACITY = _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-BLOCKED? 0= _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-context @ -1 _vfsnc-store-a @ VFSNAP-SAVE
        VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-BLOCKED? 0= _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-scratch-zero? _vfsnc-assert

    _vfsnc-raw-a @ _vfsnc-store-a @ _vfsnc-read-target
        _VFSNC-SCRATCH-U = _vfsnc-assert
    _vfsnc-stack ;

: _vfsnc-alias-contracts  ( -- )
    \ Overlapping store/scratch is rejected before any byte is filled.
    _vfsnc-alias @ _VFSNC-ALIAS-U 91 FILL
    S" /bad-overlap.bin" _vfsnc-alias @ 8 + _VFSNC-SCRATCH-U
        _vfsnc-vfs @ _vfsnc-spec @ _vfsnc-alias @
        VFSNAP-INIT-AT VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-alias @ _VFSNC-ALIAS-U 91 _vfsnc-filled? _vfsnc-assert

    \ Store, scratch, path, spec, and registered private state all classify.
    123 _VFSOP-STORE !
    S" /bad-private.bin" _vfsnc-scratch-b @ _VFSNC-SCRATCH-U
        _vfsnc-vfs @ _vfsnc-spec @ _VFSOP-STORE
        VFSNAP-INIT-AT VFSNAP-S-INVALID = _vfsnc-assert
    _VFSOP-STORE @ 123 = _vfsnc-assert
    _VFSOP-STORE 8 _vfsnc-scratch-b @ _VFSNC-SCRATCH-U
        _vfsnc-vfs @ _vfsnc-spec @ _vfsnc-store-b @
        VFSNAP-INIT-AT VFSNAP-S-INVALID = _vfsnc-assert
    _VFSOP-STORE @ 123 = _vfsnc-assert
    S" /bad-scratch.bin" _vfsnc-callback-private-begin _VFSNC-SCRATCH-U
        _vfsnc-vfs @ _vfsnc-spec @ _vfsnc-store-b @
        VFSNAP-INIT-AT VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-spec @ 8 _vfsnc-scratch-b @ _VFSNC-SCRATCH-U
        _vfsnc-vfs @ _vfsnc-spec @ _vfsnc-store-b @
        VFSNAP-INIT-AT VFSNAP-S-INVALID = _vfsnc-assert

    \ Exact adjacency between store, scratch, and path is admitted.
    S" /adj.bin" _vfsnc-alias @ VFSNAP-STORE-SIZE +
        _VFSNC-SCRATCH-U + SWAP CMOVE
    _vfsnc-alias @ VFSNAP-STORE-SIZE + _VFSNC-SCRATCH-U + 8
        _vfsnc-alias @ VFSNAP-STORE-SIZE + _VFSNC-SCRATCH-U
        _vfsnc-vfs @ _vfsnc-spec @ _vfsnc-alias @ VFSNAP-INIT-AT
        VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-alias @ VFSNAP-VALID? _vfsnc-assert
    _vfsnc-alias @ VFSNAP-FINI VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-alias @ VFSNAP-STORE-SIZE +
        _VFSNC-SCRATCH-U 0 _vfsnc-filled? _vfsnc-assert

    \ I/O aliases reject without the ordinary terminal scratch wipe.
    _vfsnc-store-a @ VFSNAP-SCRATCH$ 77 FILL
    _vfsnc-store-a @ VFSNAP.SCRATCH-A @ _VFSNC-PAYLOAD-U
        _vfsnc-generation @ _vfsnc-store-a @ VFSNAP-LOAD
        VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-SCRATCH$ 77 _vfsnc-filled? _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-SCRATCH$ 0 FILL

    456 _vfsnc-cb-context !
    _vfsnc-cb-context _VFSNC-PAYLOAD-U _vfsnc-generation @
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-cb-context @ 456 = _vfsnc-assert

    _vfsnc-spec @ _VFSNC-PAYLOAD-U _vfsnc-generation @
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-INVALID = _vfsnc-assert

    _vfsnc-output @ 40 88 FILL
    _vfsnc-output @ _VFSNC-PAYLOAD-U _vfsnc-output @ 24 +
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-output @ 40 88 _vfsnc-filled? _vfsnc-assert
    _vfsnc-output @ _VFSNC-PAYLOAD-U _vfsnc-output @ _VFSNC-PAYLOAD-U +
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-output @ _VFSNC-PAYLOAD-U + @ 1 = _vfsnc-assert
    _vfsnc-output @ @ 1 = _vfsnc-assert
    _vfsnc-stack ;

: _vfsnc-restore-original  ( -- )
    _vfsnc-raw-a @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target ;

: _vfsnc-record-case  ( expected-status -- )
    S" /vfsnap-main.bin" _vfsnc-reset-b
    _vfsnc-store-b @ _vfsnc-blocking-load ;

: _vfsnc-shape-case  ( value header-offset -- )
    >R
    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    _vfsnc-raw-b @ R> + !
    _vfsnc-raw-b @ _VFSNAP-HEADER-CRC
        _vfsnc-raw-b @ _VFSN-H-HEADER-CRC + !
    _vfsnc-raw-b @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case
    _vfsnc-restore-original ;

: _vfsnc-record-contracts  ( -- )
    \ Exact eight-byte magic remains distinct even with a valid header CRC.
    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    90 _vfsnc-raw-b @ C!
    _vfsnc-raw-b @ _VFSNAP-HEADER-CRC
        _vfsnc-raw-b @ _VFSN-H-HEADER-CRC + !
    _vfsnc-raw-b @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case
    _vfsnc-restore-original

    \ Header CRC, payload CRC, semantic generation, and future format.
    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    1 _vfsnc-raw-b @ _VFSN-H-HEADER-CRC + +!
    _vfsnc-raw-b @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case _vfsnc-restore-original

    \ A valid header CRC cannot bless invalid structural fields.
    63 _VFSN-H-HEADER-SIZE _vfsnc-shape-case
    0 _VFSN-H-GENERATION _vfsnc-shape-case
    _VFSNC-PAYLOAD-U 1- _VFSN-H-PAYLOAD-SIZE _vfsnc-shape-case
    1 _VFSN-H-FLAGS _vfsnc-shape-case

    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    _vfsnc-raw-b @ VFSNAP-HEADER-SIZE + 8 + DUP C@ 1+ SWAP C!
    _vfsnc-raw-b @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case _vfsnc-restore-original

    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    2 _vfsnc-raw-b @ VFSNAP-HEADER-SIZE + !
    _vfsnc-raw-b @ VFSNAP-HEADER-SIZE + _VFSNC-PAYLOAD-U
        _VFSNAP-PAYLOAD-CRC _vfsnc-raw-b @ _VFSN-H-PAYLOAD-CRC + !
    _vfsnc-raw-b @ _VFSNAP-HEADER-CRC
        _vfsnc-raw-b @ _VFSN-H-HEADER-CRC + !
    _vfsnc-raw-b @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case _vfsnc-restore-original

    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    2 _vfsnc-raw-b @ _VFSN-H-FORMAT + !
    _vfsnc-raw-b @ _VFSNAP-HEADER-CRC
        _vfsnc-raw-b @ _VFSN-H-HEADER-CRC + !
    _vfsnc-raw-b @ _VFSNC-SCRATCH-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-UNSUPPORTED _vfsnc-record-case _vfsnc-restore-original

    \ Header-short, truncated, and oversized records are never partial reads.
    _vfsnc-raw-a @ 63 _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case _vfsnc-restore-original
    _vfsnc-raw-a @ _VFSNC-SCRATCH-U 1- _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case _vfsnc-restore-original
    _vfsnc-raw-a @ _vfsnc-raw-b @ _VFSNC-SCRATCH-U CMOVE
    99 _vfsnc-raw-b @ _VFSNC-SCRATCH-U + C!
    _vfsnc-raw-b @ _VFSNC-RAW-U _vfsnc-store-a @ _vfsnc-put-target
    VFSNAP-S-CORRUPT _vfsnc-record-case _vfsnc-restore-original
    _vfsnc-stack ;

: _vfsnc-short-read  ( buf len offset inode vfs -- actual )
    2DROP 2DROP DROP 1 _vfsnc-fault-count +! 0 ;
: _vfsnc-fault-delete  ( inode vfs -- ior )
    1 _vfsnc-fault-count +!
    _vfsnc-fault-count @ _vfsnc-fault-at @ = IF 2DROP -1 EXIT THEN
    _vfsnc-old-delete-xt @ EXECUTE ;
: _vfsnc-arm-sync-delete  ( inode vfs -- ior )
    _vfsnc-old-delete-xt @ EXECUTE
    DUP 0= IF -1 _vfsnc-sync-armed ! THEN ;
: _vfsnc-fail-armed-sync  ( inode vfs -- ior )
    _vfsnc-sync-armed @ IF
        0 _vfsnc-sync-armed ! 2DROP -1 EXIT
    THEN
    _vfsnc-old-sync-xt @ EXECUTE ;

: _vfsnc-vtable-begin  ( -- )
    _vfsnc-vfs @ V.VTABLE @ DUP _vfsnc-old-vtable !
    DUP VFS-VT-SIZE _vfsnc-vtable SWAP CMOVE
    DUP VFS-VT-READ CELLS + @ _vfsnc-old-read-xt !
    DUP VFS-VT-SYNC CELLS + @ _vfsnc-old-sync-xt !
    VFS-VT-DELETE CELLS + @ _vfsnc-old-delete-xt !
    _vfsnc-vtable _vfsnc-vfs @ V.VTABLE !
    0 _vfsnc-fault-count ! ;
: _vfsnc-vtable-end  ( -- )
    _vfsnc-old-vtable @ _vfsnc-vfs @ V.VTABLE ! ;

: _vfsnc-close-after  ( fd -- )
    VFS-CLOSE 1 _vfsnc-close-count +! -779 THROW ;
: _vfsnc-restore-after  ( vfs -- )
    VFS-USE 1 _vfsnc-restore-count +! -780 THROW ;
: _vfsnc-hooks-reset  ( store -- )
    ['] VFS-CLOSE OVER VFSNAP.CLOSE-XT !
    ['] VFS-USE SWAP VFSNAP.RESTORE-XT ! ;

: _vfsnc-fault-contracts  ( -- )
    \ A zero-progress read becomes I/O, closes once, and latches.
    _vfsnc-restore-original S" /vfsnap-main.bin" _vfsnc-reset-b
    _vfsnc-vtable-begin
    ['] _vfsnc-short-read _vfsnc-vtable VFS-VT-READ CELLS + !
    VFSNAP-S-IO _vfsnc-store-b @ _vfsnc-blocking-load
    _vfsnc-fault-count @ 1 >= _vfsnc-assert
    _vfsnc-vtable-end

    \ Close-after-success and restore-after-success are each exact-once.
    S" /vfsnap-main.bin" _vfsnc-reset-b
    0 _vfsnc-close-count !
    ['] _vfsnc-close-after _vfsnc-store-b @ VFSNAP.CLOSE-XT !
    0 VFS-USE
    VFSNAP-S-IO _vfsnc-store-b @ _vfsnc-blocking-load
    _vfsnc-close-count @ 1 = _vfsnc-assert
    VFS-CUR 0= _vfsnc-assert
    _VFSRD-FD @ 0= _vfsnc-assert
    _VFSRD-HAVE-OLD-VFS @ 0= _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-hooks-reset _vfsnc-vfs @ VFS-USE

    S" /vfsnap-main.bin" _vfsnc-reset-b
    0 _vfsnc-restore-count !
    ['] _vfsnc-restore-after _vfsnc-store-b @ VFSNAP.RESTORE-XT !
    0 VFS-USE
    VFSNAP-S-IO _vfsnc-store-b @ _vfsnc-blocking-load
    _vfsnc-restore-count @ 1 = _vfsnc-assert
    VFS-CUR 0= _vfsnc-assert
    _VFSRD-HAVE-OLD-VFS @ 0= _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-hooks-reset _vfsnc-vfs @ VFS-USE

    \ Validate and encode exceptions are normalized, wiped, and blocked.
    S" /vfsnap-main.bin" _vfsnc-reset-b
    -1 _vfsnc-cb-validate-throw !
    VFSNAP-S-IO _vfsnc-store-b @ _vfsnc-blocking-load
    0 _vfsnc-cb-validate-throw !

    S" /vfsnap-throw.bin" _vfsnc-reset-b
    -1 _vfsnc-cb-encode-throw !
    _vfsnc-context @ 0 _vfsnc-store-b @ VFSNAP-SAVE
        VFSNAP-S-IO = _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-BLOCKED? _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-LAST-STATUS@ VFSNAP-S-IO = _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-PATH$ _vfsnc-file-present? 0= _vfsnc-assert
    _vfsnap-operation-active @ 0= _vfsnc-assert
    0 _vfsnc-cb-encode-throw !

    \ Recursive entry sees BUSY before touching outer callback scratch.
    S" /vfsnap-reenter.bin" _vfsnc-reset-b
    -1 _vfsnc-cb-reenter ! _vfsnc-store-b @ _vfsnc-cb-store !
    -1 _vfsnc-cb-nested-status !
    _vfsnc-context @ 0 _vfsnc-store-b @ VFSNAP-SAVE
        VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-cb-nested-status @ VFSNAP-S-BUSY = _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-scratch-zero? _vfsnc-assert
    0 _vfsnc-cb-reenter !
    _vfsnc-stack ;

: _vfsnc-encode-record  ( generation store -- )
    _VFSOP-STORE ! _vfsnc-encode-generation !
    _vfsnc-context @ _VFSS-CONTEXT !
    _vfsnc-encode-generation @ _VFSS-NEXT !
    _VFSNAP-ENCODE VFSNAP-S-OK = _vfsnc-assert ;

: _vfsnc-arm-rollback  ( -- )
    2 _vfsnc-store-a @ _vfsnc-encode-record
    _vfsnc-store-a @ VFSNAP.REPLACE _VRO-R !
    _vfsnc-store-a @ VFSNAP.SCRATCH-A @ _VFSNC-SCRATCH-U
        _vfsnc-store-a @ VFSNAP.REPLACE VREPL-STAGE$
        _VREPL-CREATE-WRITE VREPL-S-OK = _vfsnc-assert
    _vfsnc-store-a @ VFSNAP.SCRATCH-A @ _VRO-DATA !
    _VFSNC-SCRATCH-U _VRO-LEN ! -1 _VRO-ORIGINAL !
    _VREPL-WRITE-MARKER VREPL-S-OK = _vfsnc-assert
    _vfsnc-vfs @ VFS-SYNC 0= _vfsnc-assert
    _VRO-TARGET>BACKUP 0= _vfsnc-assert
    _vfsnc-vfs @ VFS-SYNC 0= _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-SCRATCH$ 0 FILL ;

: _vfsnc-recovery-contracts  ( -- )
    \ A durable original marker rolls back and normalizes to OK.
    _vfsnc-restore-original _vfsnc-arm-rollback
    _vfsnc-store-a @ _vfsnc-stage-present? _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-backup-present? _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-marker-present? _vfsnc-assert
    S" /vfsnap-main.bin" _vfsnc-reset-b
    _vfsnc-store-b @ VFSNAP-RECOVER VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-LAST-VREPL@ VREPL-S-ROLLED-BACK =
        _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-artifacts-clean? _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-scratch-zero? _vfsnc-assert

    \ Failing backup deletion is committed-cleanup and still publishes gen 2.
    _vfsnc-vtable-begin 2 _vfsnc-fault-at !
    ['] _vfsnc-fault-delete _vfsnc-vtable VFS-VT-DELETE CELLS + !
    _vfsnc-context @ 1 _vfsnc-store-b @ VFSNAP-SAVE
        VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-LAST-VREPL@
        VREPL-S-COMMITTED-CLEANUP = _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-backup-present? _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-marker-present? 0= _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-vtable-end
    S" /vfsnap-main.bin" _vfsnc-reset-b
    _vfsnc-store-b @ VFSNAP-RECOVER VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-artifacts-clean? _vfsnc-assert

    \ Arm on the successful marker delete, then fault the immediately
    \ following sync callback.  This targets the commit barrier by phase,
    \ independent of how many dirty inodes VFS-SYNC happens to visit.
    _vfsnc-vtable-begin 0 _vfsnc-sync-armed !
    ['] _vfsnc-arm-sync-delete
        _vfsnc-vtable VFS-VT-DELETE CELLS + !
    ['] _vfsnc-fail-armed-sync
        _vfsnc-vtable VFS-VT-SYNC CELLS + !
    _vfsnc-context @ 2 _vfsnc-store-b @ VFSNAP-SAVE
        VFSNAP-S-RECOVERY = _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-LAST-VREPL@ VREPL-S-UNCERTAIN =
        _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-BLOCKED? _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-backup-present? _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-marker-present? 0= _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-sync-armed @ 0= _vfsnc-assert
    _vfsnc-vtable-end
    _vfsnc-raw-b @ _vfsnc-store-b @ _vfsnc-read-target
        _VFSNC-SCRATCH-U = _vfsnc-assert
    _vfsnc-raw-b @ _VFSN-H-GENERATION + @ 3 = _vfsnc-assert

    \ A fresh descriptor deterministically accepts target and cleans backup.
    S" /vfsnap-main.bin" _vfsnc-reset-a
    _vfsnc-store-a @ VFSNAP-RECOVER VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-store-a @ _vfsnc-artifacts-clean? _vfsnc-assert
    _vfsnc-destination @ _VFSNC-PAYLOAD-U _vfsnc-generation @
        _vfsnc-store-a @ VFSNAP-LOAD VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-generation @ @ 3 = _vfsnc-assert

    \ Corrupt durable intent is recovery failure and remains evidence.
    S" bad" _vfsnc-store-a @ VFSNAP.REPLACE VREPL-MARKER$
        _vfsnc-put
    S" /vfsnap-main.bin" _vfsnc-reset-b
    _vfsnc-store-b @ VFSNAP-RECOVER VFSNAP-S-RECOVERY = _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-LAST-VREPL@
        VREPL-S-MARKER-CORRUPT = _vfsnc-assert
    _vfsnc-store-b @ VFSNAP-BLOCKED? _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-marker-present? _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-scratch-zero? _vfsnc-assert
    _vfsnc-store-b @ VFSNAP.REPLACE VREPL-MARKER$
        _vfsnc-vfs @ VFS-RM 0= _vfsnc-assert
    _vfsnc-vfs @ VFS-SYNC 0= _vfsnc-assert
    _vfsnc-stack ;

: _vfsnc-fini-contracts  ( -- )
    _vfsnc-store-a @ VFSNAP-VALID? _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-SCRATCH$ 66 FILL
    _vfsnc-store-a @ VFSNAP-FINI VFSNAP-S-OK = _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-VALID? 0= _vfsnc-assert
    _vfsnc-scratch-a @ _VFSNC-SCRATCH-U 0 _vfsnc-filled?
        _vfsnc-assert
    _vfsnc-store-a @ VFSNAP-FINI VFSNAP-S-INVALID = _vfsnc-assert
    _vfsnc-store-b @ _vfsnc-fini-if-valid
    _vfsnc-stack ;

: _vfsnc-setup  ( -- )
    VFSNAP-SPEC-SIZE _vfsnc-spec _vfsnc-allocate
    VFSNAP-SPEC-SIZE _vfsnc-spec-probe _vfsnc-allocate
    VFSNAP-STORE-SIZE _vfsnc-store-a _vfsnc-allocate
    VFSNAP-STORE-SIZE _vfsnc-store-b _vfsnc-allocate
    _VFSNC-SCRATCH-U _vfsnc-scratch-a _vfsnc-allocate
    _VFSNC-SCRATCH-U _vfsnc-scratch-b _vfsnc-allocate
    _VFSNC-PAYLOAD-U _vfsnc-context _vfsnc-allocate
    _VFSNC-PAYLOAD-U _vfsnc-destination _vfsnc-allocate
    8 _vfsnc-generation _vfsnc-allocate
    _VFSNC-RAW-U _vfsnc-raw-a _vfsnc-allocate
    _VFSNC-RAW-U _vfsnc-raw-b _vfsnc-allocate
    _VFSNC-ALIAS-U _vfsnc-alias _vfsnc-allocate
    40 _vfsnc-output _vfsnc-allocate
    VFS-CUR _vfsnc-old-vfs !
    1048576 A-XMEM ARENA-NEW DUP 0= _vfsnc-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _vfsnc-vfs ! 0<> _vfsnc-assert
    _vfsnc-vfs @ VFS-USE ;

: _vfsnc-cleanup  ( -- )
    _vfsnc-vfs @ VFS-USE
    _vfsnc-old-vfs @ VFS-USE _vfsnc-vfs @ VFS-DESTROY
    _vfsnc-output _vfsnc-free _vfsnc-alias _vfsnc-free
    _vfsnc-raw-b _vfsnc-free _vfsnc-raw-a _vfsnc-free
    _vfsnc-generation _vfsnc-free _vfsnc-destination _vfsnc-free
    _vfsnc-context _vfsnc-free
    _vfsnc-scratch-b _vfsnc-free _vfsnc-scratch-a _vfsnc-free
    _vfsnc-store-b _vfsnc-free _vfsnc-store-a _vfsnc-free
    _vfsnc-spec-probe _vfsnc-free _vfsnc-spec _vfsnc-free ;

: _vfsnc-report  ( -- )
    _vfsnc-stack
    _vfsnc-fails @ 0= IF
        ." VFS FIXED SNAPSHOT CONTRACTS PASS " _vfsnc-checks @ . CR
    ELSE
        ." VFS FIXED SNAPSHOT CONTRACTS FAIL " _vfsnc-fails @ .
            ." / " _vfsnc-checks @ . CR
    THEN ;

: _vfsnc-run  ( -- )
    0 _vfsnc-fails ! 0 _vfsnc-checks ! DEPTH _vfsnc-depth !
    VFSNAP-HEADER-SIZE 64 = _vfsnc-assert
    VFSNAP-S-OK 0= _vfsnc-assert
    VFSNAP-S-CONFLICT 9 = _vfsnc-assert
    _vfsnc-setup
    _vfsnc-spec-contracts
    _vfsnc-basic-contracts
    _vfsnc-alias-contracts
    _vfsnc-record-contracts
    _vfsnc-fault-contracts
    _vfsnc-recovery-contracts
    _vfsnc-fini-contracts
    _vfsnc-cleanup _vfsnc-report ;
