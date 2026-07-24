\ Bounded RAM-VFS liveness contracts for L13 Streams semantic compaction.
\
\ The existing cold-migration fixture supplies one coherent representative
\ corpus.  This fixture snapshots that truth, proves pre-publication recovery
\ after one bounded step, then drives a fresh compaction through cleanup and a
\ cold reopen.  Source, attempt, native, and observation primaries; all derived
\ indexes relevant to the corpus; and the observation PBLOB are checked again.

PROVIDED akashic-streams-l13-compaction-contracts

VARIABLE _SL13C-checks
VARIABLE _SL13C-fails
VARIABLE _SL13C-depth
VARIABLE _SL13C-step-calls
VARIABLE _SL13C-generation-before
VARIABLE _SL13C-bank-before
VARIABLE _SL13C-blob-u
VARIABLE _SL13C-expected-a
VARIABLE _SL13C-expected-u

64 CONSTANT _SL13C-STEP-CALL-MAX
1048576 CONSTANT _SL13C-BYTE-BUDGET
64 CONSTANT _SL13C-WORK-BUDGET
4096 CONSTANT _SL13C-STEP-BYTE-BUDGET

CREATE _SL13C-builder-cache0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _SL13C-builder-cache1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13C-builder-cache0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13C-builder-cache1-memory
GUARD _SL13C-builder-guard

STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF _SL13C-builder-record
STREAMS-REPOSITORY-COMPACT-BUFFER-MIN XBUF _SL13C-compact-buffer

CREATE _SL13C-logical-before _SAR-ROOTS-OFF ALLOT
SPREC-SOURCE-SIZE XBUF _SL13C-source-before
SPREC-ATTEMPT-SIZE XBUF _SL13C-attempt-before
SPREC-NATIVE-HEAD-SIZE XBUF _SL13C-native-before
SPREC-OBSERVATION-SIZE XBUF _SL13C-observation-before
SPREC-OBSERVATION-SIZE XBUF _SL13C-observation-after
SPREC-OBSERVATION-SIZE XBUF _SL13C-observation-normalized

: _SL13C-assert  ( flag -- )
    1 _SL13C-checks +!
    0= IF
        1 _SL13C-fails +!
        ." STREAMS L13 COMPACTION ASSERT " _SL13C-checks @ . CR
    THEN ;

: _SL13C-stack  ( -- )
    DEPTH DUP _SL13C-depth @ <> IF
        ." STREAMS L13 COMPACTION STACK "
        _SL13C-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13C-depth @ = _SL13C-assert ;

: _SL13C-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 COMPACTION STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13C-assert _SL13C-stack ;

: _SL13C-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _SL13C-status ;

: _SL13C-logical-exact?  ( -- flag )
    _SL13M-root DUP 0= IF DROP 0 EXIT THEN
    _SAR-ROOTS-OFF
    _SL13C-logical-before _SAR-ROOTS-OFF COMPARE 0= ;

: _SL13C-record=  ( first second length -- flag )
    >R R@ SWAP R> COMPARE 0= ;

\ The four verification words reconstruct canonical lookup keys from the
\ frozen legacy fixture and read the currently selected Streams authority.
: _SL13C-capture-owner
  ( context repository repository-work -- repository-status )
    2DROP DROP
    _SL13M-verify-source
    _SL13M-readback _SL13C-source-before
        SPREC-SOURCE-SIZE MOVE
    _SL13M-verify-attempt
    _SL13M-readback _SL13C-attempt-before
        SPREC-ATTEMPT-SIZE MOVE
    _SL13M-verify-native
    _SL13M-readback _SL13C-native-before
        SPREC-NATIVE-HEAD-SIZE MOVE
    _SL13M-verify-observation
    _SL13M-readback _SL13C-observation-before
        SPREC-OBSERVATION-SIZE MOVE
    _SL13M-observation @ _SL13M-checkpoint
        OCHK-OBSERVATION-CONTENT$ NIP _SL13C-blob-u !
    STREAMS-REPOSITORY-S-OK ;

: _SL13C-capture-truth  ( -- )
    0 ['] _SL13C-capture-owner
        _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-root DUP 0<> _SL13C-assert
    DUP STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13C-assert
    _SL13C-logical-before _SAR-ROOTS-OFF MOVE
    _SL13M-repository STREAMS-REPOSITORY-GENERATION@
        DUP 0> _SL13C-assert _SL13C-generation-before !
    _SL13M-repository STREAMS-REPOSITORY-ACTIVE-BANK@
        DUP PERSIST-DATA-BANK-VALID? _SL13C-assert
        _SL13C-bank-before !
    _SL13C-blob-u @ 0> _SL13C-assert
    _SL13C-stack ;

: _SL13C-get-equals  ( key-u expected-a expected-u -- )
    _SL13C-expected-u !
    _SL13C-expected-a !
    _SL13M-key SWAP
    _SL13M-readback STREAMS-PERSISTENCE-RECORD-MAX
    _SL13M-adapter _SL13M-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13C-assert
    SWAP DUP _SL13C-expected-u @ = _SL13C-assert
    DROP DROP
    _SL13M-readback _SL13C-expected-u @
    _SL13C-expected-a @ _SL13C-expected-u @
        COMPARE 0= _SL13C-assert
    _SL13C-stack ;

: _SL13C-get-absent  ( key-u -- )
    _SL13M-key SWAP
    _SL13M-readback STREAMS-PERSISTENCE-RECORD-MAX
    _SL13M-adapter _SL13M-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-NOT-FOUND = _SL13C-assert
    SWAP 0= _SL13C-assert
    DROP
    _SL13C-stack ;

: _SL13C-verify-secondary-indexes  ( -- )
    _SL13C-source-before SPRS.CREATION-SEQUENCE @
    _SL13C-source-before SPRS.ID
    _SL13M-key STREAMS-PI-SOURCE-ORDER-KEY
        STREAMS-PI-S-OK _SL13C-status
    STREAMS-PI-SOURCE-ORDER-KEY-SIZE
    _SL13C-source-before SPREC-SOURCE-SIZE _SL13C-get-equals

    _SL13C-attempt-before SPRA.SOURCE-ID
    _SL13M-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
        STREAMS-PI-S-OK _SL13C-status
    STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE _SL13C-get-absent

    _SL13C-observation-after SPRO.ACQUISITION-SEQUENCE @
    _SL13C-observation-after SPRO.OBSERVATION-ID
    _SL13C-observation-after SPRO.REVISION @
    _SL13M-key STREAMS-PI-GLOBAL-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    STREAMS-PI-GLOBAL-TIME-KEY-SIZE
    _SL13C-observation-after SPREC-OBSERVATION-SIZE
        _SL13C-get-equals

    _SL13C-observation-after SPRO.SOURCE-ID
    _SL13C-observation-after SPRO.ACQUISITION-SEQUENCE @
    _SL13C-observation-after SPRO.OBSERVATION-ID
    _SL13C-observation-after SPRO.REVISION @
    _SL13M-key STREAMS-PI-SOURCE-TIME-KEY
        STREAMS-PI-S-OK _SL13C-status
    STREAMS-PI-SOURCE-TIME-KEY-SIZE
    _SL13C-observation-after SPREC-OBSERVATION-SIZE
        _SL13C-get-equals
    _SL13C-stack ;

: _SL13C-verify-after-owner
  ( context repository repository-work -- repository-status )
    2DROP DROP
    _SL13M-verify-source
    _SL13M-readback _SL13C-source-before SPREC-SOURCE-SIZE
        _SL13C-record= _SL13C-assert

    _SL13M-verify-attempt
    _SL13M-readback _SL13C-attempt-before SPREC-ATTEMPT-SIZE
        _SL13C-record= _SL13C-assert

    _SL13M-verify-native
    _SL13M-readback _SL13C-native-before SPREC-NATIVE-HEAD-SIZE
        _SL13C-record= _SL13C-assert

    \ Compaction rewrites only the observation's physical PBLOB descriptor.
    \ Normalize that field, then require every semantic byte to remain exact.
    _SL13M-verify-observation
    _SL13M-readback _SL13C-observation-after
        SPREC-OBSERVATION-SIZE MOVE
    _SL13C-observation-after _SL13C-observation-normalized
        SPREC-OBSERVATION-SIZE MOVE
    _SL13C-observation-before SPRO.CONTENT
    _SL13C-observation-normalized SPRO.CONTENT
        PBLOB-SIZE MOVE
    _SL13C-observation-normalized
    _SL13C-observation-before SPREC-OBSERVATION-SIZE
        _SL13C-record= _SL13C-assert

    _SL13C-verify-secondary-indexes
    STREAMS-REPOSITORY-S-OK ;

: _SL13C-verify-published-truth  ( -- )
    _SL13C-logical-exact? _SL13C-assert
    0 ['] _SL13C-verify-after-owner
        _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13C-stack ;

: _SL13C-compaction-init  ( -- )
    _SL13C-builder-cache0-memory _SL13C-builder-cache0
        _SL13C-cache-init
    _SL13C-builder-cache1-memory _SL13C-builder-cache1
        _SL13C-cache-init
    _SL13C-builder-cache0 _SL13C-builder-cache1
    _SL13C-builder-guard
    _SL13C-builder-record STREAMS-REPOSITORY-RECORD-BUFFER-MIN
    _SL13C-compact-buffer STREAMS-REPOSITORY-COMPACT-BUFFER-MIN
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-INIT
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository
        STREAMS-REPOSITORY-COMPACTION-CONFIGURED? _SL13C-assert
    _SL13M-repository
        STREAMS-REPOSITORY-COMPACTION-BOUND? 0= _SL13C-assert
    _SL13C-stack ;

: _SL13C-bind  ( -- )
    _SL13C-BYTE-BUDGET
    _SL13C-WORK-BUDGET
    _SL13C-STEP-BYTE-BUDGET
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-BIND
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository
        STREAMS-REPOSITORY-COMPACTION-BOUND? _SL13C-assert
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-IDLE = _SL13C-assert
    _SL13C-stack ;

: _SL13C-interruption-recovery  ( -- )
    _SL13C-bind
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-BEGIN
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-BUILDING = _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-BLOCKED? _SL13C-assert

    \ One callback is strictly below this corpus's four authoritative rows.
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-STEP
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-WORK@
        1 = _SL13C-assert
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-BUILDING = _SL13C-assert

    \ RECOVER derives the selected shared root, discards the unpublished target,
    \ mirrors the selected root, and clears the fence without a phase journal.
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-RECOVER
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-CLEANED = _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-BLOCKED? 0= _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-GENERATION@
        _SL13C-generation-before @ = _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-ACTIVE-BANK@
        _SL13C-bank-before @ = _SL13C-assert
    _SL13C-logical-exact? _SL13C-assert
    \ Recovery must reopen the selected source authority, not merely restore
    \ coordinator state.  Prove every primary, secondary, and PBLOB now,
    \ before a later successful compaction could mask a damaged source bank.
    _SL13C-verify-published-truth
    _SL13C-stack ;

: _SL13C-drive-ready  ( -- ready? )
    0 _SL13C-step-calls !
    BEGIN
        _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
            PCOMPACT-STATE-BUILDING =
    WHILE
        _SL13C-step-calls @ _SL13C-STEP-CALL-MAX >= IF
            0 _SL13C-assert 0 EXIT
        THEN
        _SL13M-repository _SL13M-repository-work
            STREAMS-REPOSITORY-COMPACTION-STEP
        DUP STREAMS-REPOSITORY-S-OK <> IF
            ." STREAMS L13 COMPACTION STEP FAILURE status/phase/tree/family "
            DUP .
            _SL13M-repository-work _SRW.COMPACTION-CONTEXT
            DUP _SPACOM.PHASE @ .
            DUP _SPACOM.TREE @ .
            DUP _SPACOM.FAMILY @ . CR
            ." STREAMS L13 COMPACTION STEP FAILURE row-u/kind/copied "
            DUP _SPACOM.RECORD-U @ .
            DUP _SPACOM.RECORD SPREC.KIND @ .
            DUP _SPACOM.COPIED-SOURCE @ .
            DUP _SPACOM.COPIED-ATTEMPT @ .
            DUP _SPACOM.COPIED-OBSERVATION @ .
            DUP _SPACOM.COPIED-NATIVE @ . CR
            DROP
            _SL13M-repository-work _SRW.COMPACTION-CONTEXT >R
            ." STREAMS L13 COMPACTION STEP FAILURE key-u/tag "
            R@ _SPACOM.KEY-U @ .
            R@ _SPACOM.KEY C@ . CR
            ." STREAMS L13 COMPACTION STEP FAILURE active/done/used/context-status "
            R@ _SPACOM.ROW-ACTIVE @ .
            R@ _SPACOM.BLOB-DONE @ .
            R@ _SPACOM.USED @ .
            R@ _SPACOM.STATUS @ . CR
            ." STREAMS L13 COMPACTION STEP FAILURE lookup-kind/state/agrees "
            R@ _SPACOM.LOOKUP SPREC.KIND @ .
            R@ _SPACOM.LOOKUP SPRA.STATE @ .
            R@ _SPACOM.RECORD R@ _SPACOM.LOOKUP
                STREAMS-SRA-OBSERVATION-ATTEMPT-AGREES? . CR
            ." STREAMS L13 COMPACTION STEP FAILURE builder-state/status "
            R@ _SPACOM.BUILDER-WORK @
            DUP _SPAW.STATE @ .
            _SPAW.STATUS @ . CR
            ." STREAMS L13 COMPACTION STEP FAILURE attempt-root card/page/gen "
            STREAMS-PI-TREE-ATTEMPTS
            R@ _SPACOM.SOURCE-WORK @ _SPAW-ROOT
            DUP PBTREE-ROOT-CARDINALITY@ .
            DUP PBTREE-ROOT-PAGE@ .
            PBTREE-ROOT-GENERATION@ . CR
            R@ _SPACOM.KEY R@ _SPACOM.KEY-U @
            R@ _SPACOM.LOOKUP STREAMS-PERSISTENCE-RECORD-MAX
            R@ _SPACOM.SOURCE-ADAPTER @
            R@ _SPACOM.SOURCE-WORK @ STREAMS-PA-GET
            ." STREAMS L13 COMPACTION STEP FAILURE get-u/status "
            SWAP . . CR
            ." STREAMS L13 COMPACTION STEP FAILURE get-kind "
            R@ _SPACOM.LOOKUP SPREC.KIND @ . CR
            R> DROP
            STREAMS-REPOSITORY-S-OK _SL13C-status
            0 EXIT
        THEN
        STREAMS-REPOSITORY-S-OK _SL13C-status
        1 _SL13C-step-calls +!
    REPEAT
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-READY =
    DUP _SL13C-assert ;

: _SL13C-full-compaction  ( -- )
    _SL13C-bind
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-BEGIN
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository STREAMS-REPOSITORY-BLOCKED? _SL13C-assert
    _SL13C-drive-ready 0= IF EXIT THEN
    _SL13C-step-calls @ DUP 0>
    SWAP _SL13C-STEP-CALL-MAX <= AND _SL13C-assert
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-WORK@
        _SL13C-step-calls @ = _SL13C-assert
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-BYTES@
        _SL13C-blob-u @ = _SL13C-assert

    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-FINALIZE
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-FINALIZED = _SL13C-assert
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-PUBLISH
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-PUBLISHED = _SL13C-assert
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-MIRROR
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-MIRRORED = _SL13C-assert
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-COMPACTION-CLEANUP
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository-work STREAMS-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-CLEANED = _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-BLOCKED? 0= _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-GENERATION@
        _SL13C-generation-before @ 1+ = _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-ACTIVE-BANK@
        _SL13C-bank-before @ <> _SL13C-assert
    _SL13C-logical-exact? _SL13C-assert
    _SL13C-stack ;

: _SL13C-cold-reopen  ( -- )
    _SL13M-repository _SL13M-repository-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-cache0-memory _SL13M-cache0 _SL13C-cache-init
    _SL13M-cache1-memory _SL13M-cache1 _SL13C-cache-init
    _SL13M-vfs @ _SL13M-cache0 _SL13M-cache1 _SL13M-guard
    ['] _SL13M-fault 0 _SL13M-repository
        STREAMS-REPOSITORY-INIT
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-record-buffer STREAMS-REPOSITORY-RECORD-BUFFER-MIN
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-WORK-INIT
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13C-status
    _SL13M-repository STREAMS-REPOSITORY-GENERATION@
        _SL13C-generation-before @ 1+ = _SL13C-assert
    _SL13M-repository STREAMS-REPOSITORY-ACTIVE-BANK@
        _SL13C-bank-before @ <> _SL13C-assert
    _SL13C-logical-exact? _SL13C-assert
    _SL13C-stack ;

: _SL13C-seed  ( -- )
    0 _SL13M-checks !
    0 _SL13M-fails !
    DEPTH _SL13M-depth !
    _SL13M-case-setup
    _SL13M-source-legacy
    _SL13M-observation-legacy
    _SL13M-capture-evidence
    _SL13M-migrate STREAMS-MIGRATION-S-OK _SL13C-status
    _SL13C-capture-truth
    _SL13M-fails @ 0= _SL13C-assert
    _SL13C-stack ;

: _SL13C-finish  ( -- )
    _SL13M-fails @ 0= _SL13C-assert
    _SL13M-case-finish
    _SL13C-stack ;

: _SL13C-RUN  ( -- )
    0 _SL13C-checks !
    0 _SL13C-fails !
    DEPTH _SL13C-depth !
    _SL13C-seed
    _SL13C-compaction-init
    _SL13C-interruption-recovery
    _SL13C-full-compaction
    _SL13C-cold-reopen
    _SL13C-verify-published-truth
    _SL13C-finish
    _SL13C-fails @ IF
        ." STREAMS L13 COMPACTION FAIL "
            _SL13C-fails @ . ." / " _SL13C-checks @ . CR
    ELSE
        ." STREAMS L13 COMPACTION PASS " _SL13C-checks @ . CR
    THEN ;
