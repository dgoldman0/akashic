\ Deterministic harness contracts for the crash-recoverable observation store.

PROVIDED streams-observation-store-tests

." [ostc] compiling observation-store contracts" CR

VARIABLE _ostc-fails
VARIABLE _ostc-checks
VARIABLE _ostc-depth
VARIABLE _ostc-vfs
VARIABLE _ostc-old-vfs
VARIABLE _ostc-candidate-a
VARIABLE _ostc-loaded-a
VARIABLE _ostc-live-a
VARIABLE _ostc-raw-before-a
VARIABLE _ostc-raw-after-a
VARIABLE _ostc-byte
VARIABLE _ostc-data-a
VARIABLE _ostc-data-u
VARIABLE _ostc-path-a
VARIABLE _ostc-path-u
VARIABLE _ostc-fd
VARIABLE _ostc-read-destination
VARIABLE _ostc-read-store
VARIABLE _ostc-case-store
VARIABLE _ostc-status
VARIABLE _ostc-length

VARIABLE _ostc-store-main-a
VARIABLE _ostc-store-cold-a
VARIABLE _ostc-store-case-a

: _ostc-store-main  ( -- store ) _ostc-store-main-a @ ;
: _ostc-store-cold  ( -- store ) _ostc-store-cold-a @ ;
: _ostc-store-case  ( -- store ) _ostc-store-case-a @ ;

: _ostc-candidate  ( -- checkpoint ) _ostc-candidate-a @ ;
: _ostc-loaded     ( -- checkpoint ) _ostc-loaded-a @ ;
: _ostc-live       ( -- checkpoint ) _ostc-live-a @ ;
: _ostc-raw-before ( -- record ) _ostc-raw-before-a @ ;
: _ostc-raw-after  ( -- record ) _ostc-raw-after-a @ ;

: _ostc-assert  ( flag -- )
    1 _ostc-checks +! 0= IF
        1 _ostc-fails +! ." OSTC ASSERT " _ostc-checks @ . CR
    THEN ;

: _ostc-stack  ( -- )
    DEPTH DUP _ostc-depth @ <> IF
        ." OSTC STACK " _ostc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _ostc-depth @ = _ostc-assert ;

: _ostc-allocate  ( size variable -- )
    >R ALLOCATE ABORT" STREAMS OBSERVATION STORE CONTRACTS FAIL allocation"
    R> ! ;

: _ostc-free  ( variable -- )
    DUP @ ?DUP IF FREE 0 SWAP ! ELSE DROP THEN ;

: _ostc-filled?  ( address length byte -- flag )
    _ostc-byte ! 0 ?DO
        DUP I + C@ _ostc-byte @ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;

: _ostc-checkpoint=  ( checkpoint-a checkpoint-b -- flag )
    STREAMS-OBSERVATION-CHECKPOINT-SIZE SWAP
        STREAMS-OBSERVATION-CHECKPOINT-SIZE COMPARE 0= ;

: _ostc-record=  ( record-a record-b -- flag )
    STREAMS-OBSERVATION-STORE-RECORD-MAX SWAP
        STREAMS-OBSERVATION-STORE-RECORD-MAX COMPARE 0= ;

: _ostc-generation!  ( generation checkpoint -- )
    DUP >R OCHK.GENERATION ! R> OCHK-SEAL ;

: _ostc-store-init  ( store -- )
    _ostc-vfs @ SWAP STREAMS-OBSERVATION-STORE-INIT
        OSTORE-S-OK = _ostc-assert ;

: _ostc-put  ( data-a data-u path-a path-u -- )
    _ostc-path-u ! _ostc-path-a ! _ostc-data-u ! _ostc-data-a !
    _ostc-path-a @ _ostc-path-u @ _ostc-vfs @ VFS-RESOLVE IF
        _ostc-path-a @ _ostc-path-u @ _ostc-vfs @ VFS-RM
            0= _ostc-assert
    THEN
    _ostc-path-a @ _ostc-path-u @ _ostc-vfs @ VFS-CREATE
        DUP 0<> _ostc-assert DUP 0= IF DROP EXIT THEN DROP
    _ostc-path-a @ _ostc-path-u @ VFS-OPEN DUP _ostc-fd !
        0<> _ostc-assert
    _ostc-fd @ 0= IF EXIT THEN
    _ostc-data-a @ _ostc-data-u @ _ostc-fd @ VFS-WRITE-EXACT
        0= _ostc-assert
    _ostc-fd @ VFS-CLOSE 0 _ostc-fd !
    _ostc-vfs @ VFS-SYNC 0= _ostc-assert ;

: _ostc-put-target  ( data-a data-u store -- )
    >R R@ STREAMS-OBSERVATION-STORE-PATH$ _ostc-put R> DROP ;

: _ostc-read-target  ( destination store -- )
    _ostc-read-store ! _ostc-read-destination !
    _ostc-read-store @ STREAMS-OBSERVATION-STORE-PATH$
        _ostc-vfs @ VFS-RESOLVE 0<> _ostc-assert
    _ostc-read-store @ STREAMS-OBSERVATION-STORE-PATH$
        VFS-OPEN DUP _ostc-fd ! 0<> _ostc-assert
    _ostc-fd @ 0= IF EXIT THEN
    _ostc-fd @ VFS-SIZE STREAMS-OBSERVATION-STORE-RECORD-MAX =
        _ostc-assert
    _ostc-read-destination @ STREAMS-OBSERVATION-STORE-RECORD-MAX
        _ostc-fd @ VFS-READ-EXACT 0= _ostc-assert
    _ostc-fd @ VFS-CLOSE 0 _ostc-fd ! ;

: _ostc-artifacts-clean?  ( store -- flag )
    _ostc-case-store !
    _ostc-case-store @ STREAMS-OBSERVATION-STORE.REPLACE VREPL-STAGE$
        _ostc-vfs @ VFS-RESOLVE 0=
    _ostc-case-store @ STREAMS-OBSERVATION-STORE.REPLACE VREPL-BACKUP$
        _ostc-vfs @ VFS-RESOLVE 0= AND
    _ostc-case-store @ STREAMS-OBSERVATION-STORE.REPLACE VREPL-MARKER$
        _ostc-vfs @ VFS-RESOLVE 0= AND ;

: _ostc-marker-present?  ( store -- flag )
    STREAMS-OBSERVATION-STORE.REPLACE VREPL-MARKER$
        _ostc-vfs @ VFS-RESOLVE 0<> ;

: _ostc-target-present?  ( store -- flag )
    STREAMS-OBSERVATION-STORE-PATH$
        _ostc-vfs @ VFS-RESOLVE 0<> ;

: _ostc-stage-present?  ( store -- flag )
    STREAMS-OBSERVATION-STORE.REPLACE VREPL-STAGE$
        _ostc-vfs @ VFS-RESOLVE 0<> ;

: _ostc-backup-present?  ( store -- flag )
    STREAMS-OBSERVATION-STORE.REPLACE VREPL-BACKUP$
        _ostc-vfs @ VFS-RESOLVE 0<> ;

: _ostc-encode-live  ( -- )
    _ostc-live _ostc-store-main _STREAMS-OBSERVATION-STORE-ENCODE
        _ostc-status ! _ostc-length !
    _ostc-status @ OSTORE-S-OK = _ostc-assert
    _ostc-length @ STREAMS-OBSERVATION-STORE-RECORD-MAX = _ostc-assert ;

: _ostc-test-absent  ( -- )
    ." OSTC CASE absent at " _ostc-checks @ . CR
    _ostc-store-main _ostc-store-init
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-main
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-ABSENT = _ostc-assert
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 _ostc-filled?
        _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE-BLOCKED? 0= _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE.LAST-STATUS @
        OSTORE-S-ABSENT = _ostc-assert
    _ostc-store-main _ostc-artifacts-clean? _ostc-assert
    _ostc-stack ;

: _ostc-test-generation-one  ( -- )
    ." OSTC CASE generation-one at " _ostc-checks @ . CR
    _ostc-candidate OCHK-INIT
    1 _ostc-candidate _ostc-generation!
    _ostc-candidate OCHK-VALID? _ostc-assert
    _ostc-candidate _ostc-live STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _ostc-candidate 0 _ostc-store-main STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK = _ostc-assert
    _ostc-candidate _ostc-live _ostc-checkpoint= _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE-BLOCKED? 0= _ostc-assert
    _ostc-store-main _ostc-artifacts-clean? _ostc-assert

    _ostc-store-cold _ostc-store-init
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-cold
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _ostc-assert
    _ostc-loaded _ostc-candidate _ostc-checkpoint= _ostc-assert
    _ostc-loaded OCHK.GENERATION @ 1 = _ostc-assert
    _ostc-loaded OCHK-VALID? _ostc-assert
    _ostc-loaded _ostc-live STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _ostc-stack ;

: _ostc-test-generation-advance  ( -- )
    ." OSTC CASE generation-advance at " _ostc-checks @ . CR
    _ostc-live _ostc-candidate STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    2 _ostc-candidate _ostc-generation!
    _ostc-candidate OCHK-VALID? _ostc-assert
    _ostc-candidate 1 _ostc-store-main STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK = _ostc-assert
    _ostc-store-main _ostc-artifacts-clean? _ostc-assert

    _ostc-store-cold _ostc-store-init
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-cold
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _ostc-assert
    _ostc-loaded _ostc-candidate _ostc-checkpoint= _ostc-assert
    _ostc-loaded OCHK.GENERATION @ 2 = _ostc-assert
    _ostc-loaded OCHK-VALID? _ostc-assert
    _ostc-loaded _ostc-live STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _ostc-stack ;

: _ostc-test-stale-conflict  ( -- )
    ." OSTC CASE stale-conflict at " _ostc-checks @ . CR
    _ostc-live _ostc-candidate STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    \ Expected generation one requires a generation-two candidate.  The
    \ durable target is already generation two, so this reaches the store's
    \ optimistic precondition and proves the stale expectation conflicts.
    _ostc-candidate _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _ostc-raw-before _ostc-store-main _ostc-read-target

    _ostc-candidate 1 _ostc-store-main STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-CONFLICT = _ostc-assert
    _ostc-candidate _ostc-loaded _ostc-checkpoint= _ostc-assert
    _ostc-raw-after _ostc-store-main _ostc-read-target
    _ostc-raw-before _ostc-raw-after _ostc-record= _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE-BLOCKED? 0= _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE.LAST-STATUS @
        OSTORE-S-CONFLICT = _ostc-assert
    _ostc-store-main _ostc-artifacts-clean? _ostc-assert

    _ostc-store-cold _ostc-store-init
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-cold
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _ostc-assert
    _ostc-loaded _ostc-live _ostc-checkpoint= _ostc-assert
    _ostc-stack ;

: _ostc-test-corrupt-refusal  ( -- )
    ." OSTC CASE corrupt-refusal at " _ostc-checks @ . CR
    _ostc-raw-before _ostc-store-main _ostc-read-target
    _ostc-raw-before _ostc-raw-after
        STREAMS-OBSERVATION-STORE-RECORD-MAX CMOVE
    _ostc-raw-after STREAMS-OBSERVATION-STORE-HEADER-SIZE +
        DUP C@ 1 XOR SWAP C!
    _ostc-raw-after STREAMS-OBSERVATION-STORE-RECORD-MAX
        _ostc-store-main _ostc-put-target

    _ostc-store-case _ostc-store-init
    _ostc-live _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-case
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-CORRUPT = _ostc-assert
    _ostc-loaded _ostc-live _ostc-checkpoint= _ostc-assert
    _ostc-store-case STREAMS-OBSERVATION-STORE-BLOCKED? _ostc-assert
    _ostc-store-case STREAMS-OBSERVATION-STORE.LAST-STATUS @
        OSTORE-S-CORRUPT = _ostc-assert
    _ostc-raw-before _ostc-store-case _ostc-read-target
    _ostc-raw-before _ostc-raw-after _ostc-record= _ostc-assert
    _ostc-candidate 2 _ostc-store-case STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-CORRUPT = _ostc-assert
    _ostc-raw-before _ostc-store-case _ostc-read-target
    _ostc-raw-before _ostc-raw-after _ostc-record= _ostc-assert

    _ostc-encode-live
    _ostc-store-main STREAMS-OBSERVATION-STORE.SCRATCH
        _ostc-length @ _ostc-store-main _ostc-put-target
    _ostc-store-main _STREAMS-OBSERVATION-STORE-SCRATCH-WIPE
    _ostc-store-cold _ostc-store-init
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-cold
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _ostc-assert
    _ostc-loaded _ostc-live _ostc-checkpoint= _ostc-assert
    _ostc-stack ;

: _ostc-arm-rollback  ( -- )
    _ostc-candidate _ostc-store-main _STREAMS-OBSERVATION-STORE-ENCODE
        _ostc-status ! _ostc-length !
    _ostc-status @ OSTORE-S-OK = _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE.REPLACE _VRO-R !
    _ostc-store-main STREAMS-OBSERVATION-STORE.SCRATCH _ostc-length @
        _ostc-store-main STREAMS-OBSERVATION-STORE.REPLACE VREPL-STAGE$
        _VREPL-CREATE-WRITE VREPL-S-OK = _ostc-assert
    _ostc-store-main STREAMS-OBSERVATION-STORE.SCRATCH
        _VRO-DATA ! _ostc-length @ _VRO-LEN !
    -1 _VRO-ORIGINAL !
    _VREPL-WRITE-MARKER VREPL-S-OK = _ostc-assert
    _ostc-vfs @ VFS-SYNC 0= _ostc-assert
    _VRO-TARGET>BACKUP 0= _ostc-assert
    _ostc-vfs @ VFS-SYNC 0= _ostc-assert ;

: _ostc-test-cold-recovery  ( -- )
    ." OSTC CASE cold-recovery at " _ostc-checks @ . CR
    _ostc-live _ostc-candidate STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    3 _ostc-candidate _ostc-generation!
    _ostc-arm-rollback
    _ostc-store-main _ostc-target-present? 0= _ostc-assert
    _ostc-store-main _ostc-stage-present? _ostc-assert
    _ostc-store-main _ostc-backup-present? _ostc-assert
    _ostc-store-main _ostc-marker-present? _ostc-assert

    _ostc-store-cold _ostc-store-init
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE 90 FILL
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-cold
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _ostc-assert
    _ostc-loaded _ostc-live _ostc-checkpoint= _ostc-assert
    _ostc-loaded OCHK.GENERATION @ 2 = _ostc-assert
    _ostc-store-cold STREAMS-OBSERVATION-STORE.LAST-VREPL @
        VREPL-S-ROLLED-BACK = _ostc-assert
    _ostc-store-cold _ostc-artifacts-clean? _ostc-assert
    _ostc-stack ;

: _ostc-test-ambiguous-recovery  ( -- )
    ." OSTC CASE ambiguous-recovery at " _ostc-checks @ . CR
    _ostc-raw-before _ostc-store-cold _ostc-read-target
    S" bad" _ostc-store-cold STREAMS-OBSERVATION-STORE.REPLACE
        VREPL-MARKER$ _ostc-put
    _ostc-store-case _ostc-store-init
    _ostc-store-case STREAMS-OBSERVATION-STORE-RECOVER
        OSTORE-S-RECOVERY = _ostc-assert
    _ostc-store-case STREAMS-OBSERVATION-STORE-BLOCKED? _ostc-assert
    _ostc-store-case STREAMS-OBSERVATION-STORE.LAST-STATUS @
        OSTORE-S-RECOVERY = _ostc-assert
    _ostc-store-case STREAMS-OBSERVATION-STORE.LAST-VREPL @
        VREPL-S-MARKER-CORRUPT = _ostc-assert
    _ostc-store-case _ostc-marker-present? _ostc-assert
    _ostc-raw-after _ostc-store-case _ostc-read-target
    _ostc-raw-before _ostc-raw-after _ostc-record= _ostc-assert

    _ostc-live _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _ostc-loaded STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-store-case
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-RECOVERY = _ostc-assert
    _ostc-loaded _ostc-live _ostc-checkpoint= _ostc-assert
    _ostc-candidate 2 _ostc-store-case STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-RECOVERY = _ostc-assert
    _ostc-raw-after _ostc-store-case _ostc-read-target
    _ostc-raw-before _ostc-raw-after _ostc-record= _ostc-assert
    _ostc-store-case _ostc-marker-present? _ostc-assert
    _ostc-stack ;

: _ostc-run  ( -- )
    0 _ostc-fails ! 0 _ostc-checks ! DEPTH _ostc-depth !
    STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-candidate-a _ostc-allocate
    STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-loaded-a _ostc-allocate
    STREAMS-OBSERVATION-CHECKPOINT-SIZE _ostc-live-a _ostc-allocate
    STREAMS-OBSERVATION-STORE-RECORD-MAX _ostc-raw-before-a _ostc-allocate
    STREAMS-OBSERVATION-STORE-RECORD-MAX _ostc-raw-after-a _ostc-allocate
    STREAMS-OBSERVATION-STORE-SIZE _ostc-store-main-a _ostc-allocate
    STREAMS-OBSERVATION-STORE-SIZE _ostc-store-cold-a _ostc-allocate
    STREAMS-OBSERVATION-STORE-SIZE _ostc-store-case-a _ostc-allocate
    VFS-CUR _ostc-old-vfs !
    2097152 A-XMEM ARENA-NEW DUP 0= _ostc-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _ostc-vfs ! 0<> _ostc-assert
    _ostc-vfs @ VFS-USE

    _ostc-test-absent
    _ostc-test-generation-one
    _ostc-test-generation-advance
    _ostc-test-stale-conflict
    _ostc-test-corrupt-refusal
    _ostc-test-cold-recovery
    _ostc-test-ambiguous-recovery

    _ostc-old-vfs @ VFS-USE _ostc-vfs @ VFS-DESTROY
    _ostc-store-case-a _ostc-free _ostc-store-cold-a _ostc-free
    _ostc-store-main-a _ostc-free
    _ostc-raw-after-a _ostc-free _ostc-raw-before-a _ostc-free
    _ostc-live-a _ostc-free _ostc-loaded-a _ostc-free
    _ostc-candidate-a _ostc-free
    _ostc-stack
    _ostc-fails @ 0= IF
        ." STREAMS OBSERVATION STORE CONTRACTS PASS " _ostc-checks @ . CR
    ELSE
        ." STREAMS OBSERVATION STORE CONTRACTS FAIL " _ostc-fails @ .
        ." / " _ostc-checks @ . CR
    THEN ;
