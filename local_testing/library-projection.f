\ =====================================================================
\  Gate 4 milestone 4: bounded Library projection-owner contract fixture
\ =====================================================================

VARIABLE _lpo-fails
VARIABLE _lpo-checks
VARIABLE _lpo-depth
VARIABLE _lpo-store-slot
VARIABLE _lpo-vfs
VARIABLE _lpo-other-vfs
VARIABLE _lpo-old-vfs
VARIABLE _lpo-arena
VARIABLE _lpo-other-arena
VARIABLE _lpo-context
VARIABLE _lpo-cold-context
VARIABLE _lpo-creg
VARIABLE _lpo-rreg
VARIABLE _lpo-bus
VARIABLE _lpo-request
VARIABLE _lpo-status
VARIABLE _lpo-required
VARIABLE _lpo-before
VARIABLE _lpo-instance
VARIABLE _lpo-text-a
VARIABLE _lpo-text-u

PHEAD-SIZE XBUF _lpo-head
LIB-DIGEST-SIZE XBUF _lpo-arena-id
LIB-OPERATION-KEY-SIZE XBUF _lpo-key
LIB-DIGEST-SIZE 10 * XBUF _lpo-rids
LIB-DIGEST-SIZE XBUF _lpo-unknown-rid
LIBRARY-MANAGED-CREATE-REQUEST-SIZE XBUF _lpo-create
LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE XBUF _lpo-import
LIB-ORIGIN-SIZE XBUF _lpo-origin
LIB-ENTRY-SIZE XBUF _lpo-entry
LIB-ENTRY-SIZE XBUF _lpo-capture-entry
16 XBUF _lpo-content
8 XBUF _lpo-prune-content
RREF-SIZE XBUF _lpo-ref
QLOC-SIZE XBUF _lpo-loc-a
QLOC-SIZE XBUF _lpo-loc-b
QLOC-SIZE XBUF _lpo-loc-c
LIB-DIGEST-SIZE XBUF _lpo-digest-a
LIB-DIGEST-SIZE XBUF _lpo-digest-b
LIBRARY-PROJECTION-ROOT-SIZE XBUF _lpo-root
LBIND-SIZE XBUF _lpo-bind-a
LBIND-SIZE XBUF _lpo-bind-b
LBIND-SIZE XBUF _lpo-bind-fail
RACQ-RESULT-SIZE XBUF _lpo-result-a
RACQ-RESULT-SIZE XBUF _lpo-result-b
RACQ-RESULT-SIZE XBUF _lpo-result-fail
RACQ-TOKEN-SIZE XBUF _lpo-token-copy
RCLI-SIZE XBUF _lpo-client
LBIND-SIZE LIBRARY-PROJECTION-LEASE-MAX 1+ *
    CONSTANT _LPO-CAP-BINDS-SIZE
RACQ-RESULT-SIZE LIBRARY-PROJECTION-LEASE-MAX 1+ *
    CONSTANT _LPO-CAP-RESULTS-SIZE
VARIABLE _lpo-cap-binds
VARIABLE _lpo-cap-results
LIB-PROJECTION-MAX 8 * XBUF _lpo-cap-instances
CREATE _lpo-cap-rid-map
    0 , 3 , 4 , 5 , 6 , 7 , 8 , 9 ,

: _lpo-store  ( -- store ) _lpo-store-slot @ ;
: _lpo-rid  ( index -- rid ) LIB-DIGEST-SIZE * _lpo-rids + ;
: _lpo-cap-bind  ( index -- bind ) LBIND-SIZE * _lpo-cap-binds @ + ;
: _lpo-cap-result  ( index -- result )
    RACQ-RESULT-SIZE * _lpo-cap-results @ + ;
: _lpo-cap-rid  ( index -- rid )
    8 * _lpo-cap-rid-map + @ _lpo-rid ;

: _lpo-assert  ( flag -- )
    1 _lpo-checks +!
    0= IF
        1 _lpo-fails +!
        ." LIBRARY PROJECTION OWNER ASSERT " _lpo-checks @ . CR
    THEN ;

: _lpo-stack  ( -- )
    DEPTH DUP _lpo-depth @ <> IF
        ." LIBRARY PROJECTION OWNER STACK "
        _lpo-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _lpo-depth @ = _lpo-assert ;

: _lpo-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lpo-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _lpo-identity-loc!  ( rid locator -- status )
    >R
    _lpo-ref RREF-INIT
    _lpo-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpo-ref R> QLOC-IDENTITY! ;

VARIABLE _lpo-exact-rid
VARIABLE _lpo-exact-revision
VARIABLE _lpo-exact-digest
VARIABLE _lpo-exact-locator

: _lpo-exact-loc!  ( rid revision digest locator -- status )
    _lpo-exact-locator ! _lpo-exact-digest !
    _lpo-exact-revision ! _lpo-exact-rid !
    _lpo-ref RREF-INIT
    _lpo-exact-rid @ _lpo-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpo-ref
        _lpo-exact-revision @ _lpo-exact-digest @
        QLOC-DK-PROJECTION-CONTENT LIBRARY-PROJECTION-CONTRACT$
        _lpo-exact-locator @ QLOC-EXACT! ;

: _lpo-attach  ( locator binding result -- status )
    >R >R
    _lpo-root _lpo-context @ _lpo-rreg @
    R> R> LIBRARY-PROJECTION-ATTACH ;

: _lpo-cold-attach  ( locator binding result -- status )
    >R >R
    _lpo-root _lpo-cold-context @ _lpo-rreg @
    R> R> LIBRARY-PROJECTION-ATTACH ;

: _lpo-result-content?  ( expected-a expected-u -- flag )
    _lpo-text-u ! _lpo-text-a !
    S" content" _lpo-request @ CBR.RESULT CV-MAP-FIND DUP 0= IF
        DROP 0 EXIT
    THEN
    DUP CV-DATA@ SWAP CV-LEN@
    _lpo-text-a @ _lpo-text-u @ STR-STR= ;

: _lpo-create-documents  ( -- )
    S" managed-0" _lpo-content SWAP CMOVE
    9 0 ?DO
        [CHAR] 0 I + _lpo-content 8 + C!
        _lpo-key LIB-OPERATION-KEY-SIZE I 1+ FILL
        _lpo-create LIBRARY-MANAGED-CREATE-REQUEST-INIT
        I 1+ _lpo-create LIBMCR.EXPECTED-CATALOG-GENERATION !
        _lpo-key _lpo-create LIBRARY-MANAGED-CREATE-OPERATION-KEY!
            LIBSTORE-S-OK = _lpo-assert
        S" Projection fixture" _lpo-create
            LIBRARY-MANAGED-CREATE-TITLE!
            LIBSTORE-S-OK = _lpo-assert
        _lpo-content 9 _lpo-create LIBRARY-MANAGED-CREATE-CONTENT!
            LIBSTORE-S-OK = _lpo-assert
        LIB-MEDIA-TEXT-PLAIN _lpo-create LIBMCR.MEDIA !
        _lpo-create _lpo-entry _lpo-store
            LIBRARY-VFS-STORE-CREATE-MANAGED
            LIBSTORE-S-OK = _lpo-assert
        _lpo-entry LIB-ENTRY-VALID? _lpo-assert
        _lpo-entry LIBE.ID I _lpo-rid RID-COPY
        I _lpo-rid RID-PRESENT? _lpo-assert
        _lpo-entry LIBE.KIND @
            LIB-KIND-MANAGED-DOCUMENT = _lpo-assert
    LOOP
    9 0 ?DO
        I 0 ?DO
            I _lpo-rid J _lpo-rid RID= 0= _lpo-assert
        LOOP
    LOOP
    _lpo-stack ;

: _lpo-build-origin  ( -- )
    _lpo-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _lpo-origin LIBO.KIND !
    S" /imports/projection-capture.txt"
        DUP _lpo-origin LIBO.VFS LIBV.PATH-U !
        _lpo-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" capture bytes"
        DUP _lpo-origin LIBO.VFS LIBV.CONTENT-U !
        _lpo-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT
        _lpo-origin LIBO.VFS LIBV.DIGEST-KIND !
    _lpo-origin LIB-ORIGIN-VALID? _lpo-assert ;

: _lpo-create-capture  ( -- )
    _lpo-build-origin
    _lpo-key LIB-OPERATION-KEY-SIZE 0xA0 FILL
    _lpo-import LIBRARY-CAPTURE-IMPORT-REQUEST-INIT
    10 _lpo-import LIBCIR.EXPECTED-CATALOG-GENERATION !
    _lpo-key _lpo-import LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
        LIBSTORE-S-OK = _lpo-assert
    S" Projection capture" _lpo-import LIBRARY-CAPTURE-IMPORT-TITLE!
        LIBSTORE-S-OK = _lpo-assert
    S" capture bytes" _lpo-import LIBRARY-CAPTURE-IMPORT-CONTENT!
        LIBSTORE-S-OK = _lpo-assert
    LIB-MEDIA-TEXT-PLAIN _lpo-import LIBCIR.MEDIA !
    _lpo-origin _lpo-import LIBRARY-CAPTURE-IMPORT-ORIGIN!
        LIBSTORE-S-OK = _lpo-assert
    _lpo-import _lpo-capture-entry _lpo-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _lpo-assert
    _lpo-capture-entry LIBE.ID 9 _lpo-rid RID-COPY
    _lpo-capture-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lpo-assert
    9 _lpo-rid RID-PRESENT? _lpo-assert
    _lpo-stack ;

: _lpo-seed-lifecycle  ( -- )
    \ Keep document zero active but advance its domain revision independently
    \ of its content revision before a projection instance exists.
    0 _lpo-rid 1 _lpo-entry _lpo-store LIBRARY-VFS-STORE-ARCHIVE
        LIBSTORE-S-OK = _lpo-assert
    0 _lpo-rid 2 _lpo-entry _lpo-store LIBRARY-VFS-STORE-UNARCHIVE
        LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 3 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lpo-assert

    1 _lpo-rid 1 _lpo-entry _lpo-store LIBRARY-VFS-STORE-ARCHIVE
        LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lpo-assert

    S" prune-2" _lpo-prune-content SWAP CMOVE
    5 0 ?DO
        [CHAR] 2 I + _lpo-prune-content 6 + C!
        3 _lpo-rid I 1+ _lpo-prune-content 7 _lpo-entry _lpo-store
            LIBRARY-VFS-STORE-REPLACE-MANAGED
            LIBSTORE-S-OK = _lpo-assert
    LOOP
    _lpo-entry LIBE.DOMAIN-REVISION @ 6 = _lpo-assert
    _lpo-entry LIBE.OLDEST-CONTENT-REVISION @ 3 = _lpo-assert
    _lpo-stack ;

: _lpo-capacity-buffers-setup  ( -- )
    0 _lpo-cap-binds ! 0 _lpo-cap-results !
    _LPO-CAP-BINDS-SIZE ALLOCATE DUP IF NIP THROW THEN
        DROP _lpo-cap-binds !
    _LPO-CAP-RESULTS-SIZE ALLOCATE DUP IF
        NIP >R
        _lpo-cap-binds @ FREE 0 _lpo-cap-binds !
        R> THROW
    THEN
    DROP _lpo-cap-results !
    _lpo-cap-binds @ _LPO-CAP-BINDS-SIZE 0 FILL
    _lpo-cap-results @ _LPO-CAP-RESULTS-SIZE 0 FILL
    _lpo-stack ;

: _lpo-capacity-buffers-free  ( -- )
    _lpo-cap-results @ ?DUP IF
        DUP _LPO-CAP-RESULTS-SIZE 0 FILL FREE
        0 _lpo-cap-results !
    THEN
    _lpo-cap-binds @ ?DUP IF
        DUP _LPO-CAP-BINDS-SIZE 0 FILL FREE
        0 _lpo-cap-binds !
    THEN ;

: _lpo-store-setup  ( -- )
    VFS-CUR _lpo-old-vfs !
    _lpo-arena-id LIB-DIGEST-SIZE 0xB4 FILL
    _lpo-unknown-rid LIB-DIGEST-SIZE 0xEE FILL
    4194304 A-XMEM ARENA-NEW DUP 0= _lpo-assert DROP
    DUP _lpo-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lpo-vfs ! 0<> _lpo-assert
    _lpo-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY PROJECTION OWNER store allocation"
        _lpo-store-slot !
    _lpo-vfs @ _lpo-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lpo-assert
    _lpo-arena-id _lpo-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lpo-assert
    _lpo-create-documents
    _lpo-create-capture
    _lpo-seed-lifecycle

    \ The unrelated empty VFS is selected only by the ambient-fallback test.
    4194304 A-XMEM ARENA-NEW DUP 0= _lpo-assert DROP
    DUP _lpo-other-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lpo-other-vfs ! 0<> _lpo-assert
    _lpo-vfs @ VFS-USE
    _lpo-stack ;

: _lpo-runtime-setup  ( -- )
    _lpo-head PHEAD-INIT
    0x51 _lpo-head PHEAD.ID _lpo-id!
    0x52 _lpo-head PHEAD.CURRENT-ROOT _lpo-id!
    91 CTX-NEW DUP 0= _lpo-assert DROP _lpo-context !
    _lpo-head _lpo-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpo-context @ CTX.FLAGS !
    92 CTX-NEW DUP 0= _lpo-assert DROP _lpo-cold-context !
    _lpo-head _lpo-cold-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpo-cold-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _lpo-assert DROP _lpo-creg !
    _lpo-creg @ _lpo-context @ RREG-NEW
        DUP 0= _lpo-assert DROP _lpo-rreg !
    _lpo-creg @ 0 CBUS-NEW DUP 0= _lpo-assert DROP _lpo-bus !
    _lpo-bus @ _lpo-context @ CTX.QUEUE !
    _lpo-store _lpo-context @ _lpo-creg @ _lpo-rreg @ _lpo-bus @
        _lpo-root LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-OK = _lpo-assert
    CBR-NEW DUP 0= _lpo-assert DROP _lpo-request !
    _lpo-stack ;

: _lpo-root-contract  ( -- )
    LIB-PROJECTION-MAX 8 = _lpo-assert
    LIBRARY-PROJECTION-OWNER-MAX 8 = _lpo-assert
    LIBRARY-PROJECTION-LEASE-MAX 64 = _lpo-assert
    LIBRARY-PROJECTION-ROOT-SIZE RACQ-ROOT-SIZE > _lpo-assert
    LIBRARY-PROJECTION-OWNER$
        S" org.akashic.library" STR-STR= _lpo-assert
    LIBRARY-PROJECTION-CONTRACT$
        S" org.akashic.library.utf8-content.v1" STR-STR= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RACQ
        RACQ-ROOT-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RACQ
        _lpo-root = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RACQ RACQ-ROOT-OWNER$
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@ 0= _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        0= _lpo-assert
    _lpo-unknown-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    -1 _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        0= _lpo-assert
    LIBRARY-PROJECTION-OWNER-MAX _lpo-root
        LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@ 0= _lpo-assert

    \ Root initialization rejects a caller output placed over the Context's
    \ borrowed Practice head before any zero-fill or descriptor mutation.
    _lpo-creg @ CREG.TYPE-N @ _lpo-before !
    _lpo-store _lpo-context @ _lpo-creg @ _lpo-rreg @ _lpo-bus @
        _lpo-head LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-INVALID = _lpo-assert
    _lpo-head PHEAD-VALID? _lpo-assert
    _lpo-creg @ CREG.TYPE-N @ _lpo-before @ = _lpo-assert
    _lpo-stack ;

: _lpo-attach-alias-contract  ( -- )
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ _lpo-before !

    \ The typed wrapper rejects shared/partially shared outputs before the
    \ portable helper can initialize either object or retain the RID.
    _lpo-result-fail RACQ-RESULT-SIZE 0xA5 FILL
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @
        _lpo-result-fail _lpo-result-fail LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-result-fail C@ 0xA5 = _lpo-assert
    _lpo-result-fail RACQ-RESULT-SIZE 1- + C@ 0xA5 = _lpo-assert

    \ Generic RACQ knows only the 88-byte prefix; the Library wrapper closes
    \ the larger root tail and every bounded borrowed owner span.
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-root RACQ-ROOT-SIZE + LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-VALID? _lpo-assert
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-store LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-store LIBRARY-VFS-STORE-VALID? _lpo-assert
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-head LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-head PHEAD-VALID? _lpo-assert
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-arena @ A.BASE @ LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@
        _lpo-before @ = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-sharing-release  ( -- )
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a RACQ-RESULT-VALID? _lpo-assert
    _lpo-result-a RACQ.RESULT-REF RREF.ID
        0 _lpo-rid RID= _lpo-assert
    _lpo-result-a RACQ.RESULT-REF RREF.REVISION @ 0= _lpo-assert
    _lpo-bind-a LBIND-VALID? _lpo-assert
    _lpo-bind-a LBIND.REVISION @ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        DUP 0>= _lpo-assert
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        DUP _lpo-instance ! 0<> _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert

    \ Registry publication never bypasses the root retain.  The second
    \ acquisition shares the fixed-RID instance but owns a distinct token.
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ _lpo-before !
    _lpo-loc-a _lpo-bind-b _lpo-result-b _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@
        _lpo-before @ 1+ = _lpo-assert
    _lpo-bind-b LBIND.TARGET-ID @
        _lpo-bind-a LBIND.TARGET-ID @ = _lpo-assert
    _lpo-bind-b LBIND.TARGET-GEN @
        _lpo-bind-a LBIND.TARGET-GEN @ = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-instance @ = _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN RACQ.TOKEN-COOKIE @
        _lpo-result-b RACQ.RESULT-TOKEN RACQ.TOKEN-COOKIE @
        <> _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _lpo-assert
    _lpo-result-b RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN
        _lpo-result-b RACQ.RESULT-TOKEN <> _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 2 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert

    \ A context-mismatched LBIND fails after owner retention, so RACQ must
    \ roll the new lease back without disturbing the two existing clients.
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ _lpo-before !
    _lpo-loc-a _lpo-bind-fail _lpo-result-fail _lpo-cold-attach
        RACQ-S-ATTACH-FAILED = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@
        _lpo-before @ 1+ = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 2 = _lpo-assert

    \ A byte-copy is not a token.  A simulated release failure leaves the
    \ original lease active and retryable; the successful retry waits through
    \ one BUSY quiescence report and performs exactly one decrement.
    _lpo-result-a RACQ.RESULT-TOKEN _lpo-token-copy
        RACQ-TOKEN-SIZE MOVE
    _lpo-token-copy RACQ-RELEASE RACQ-S-STALE-TOKEN = _lpo-assert
    1 _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-FAILURES!
        RACQ-S-OK = _lpo-assert
    _lpo-bind-a _lpo-result-a RACQ-DETACH
        RACQ-S-RELEASE-FAILED = _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    1 _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-BUSY!
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@ _lpo-before !
    _lpo-bind-a _lpo-result-a RACQ-DETACH RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@
        _lpo-before @ 2 + = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-instance @ CINST-DESC COMP-DESC-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ _lpo-before !
    _lpo-result-a RACQ.RESULT-TOKEN RACQ-RELEASE
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@
        _lpo-before @ = _lpo-assert

    _lpo-bind-b _lpo-result-b RACQ-DETACH RACQ-S-OK = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-read-identity  ( index -- status )
    _lpo-rid _lpo-entry _lpo-store
        LIBRARY-VFS-STORE-READ-IDENTITY ;

: _lpo-managed-client?  ( client -- flag )
    DUP RCLI-VALID? 0= IF DROP 0 EXIT THEN
    DUP RCLI-REPLACE? 0= IF DROP 0 EXIT THEN
    RCLI.OWNER @ CINST-DESC
    DUP COMP.CAPS-N @ 3 =
    OVER S" resource.describe" ROT COMP-CAP-FIND 0<> AND
    OVER S" resource.snapshot" ROT COMP-CAP-FIND 0<> AND
    SWAP S" resource.replace" ROT COMP-CAP-FIND 0<> AND ;

: _lpo-capture-client?  ( client -- flag )
    DUP RCLI-VALID? 0= IF DROP 0 EXIT THEN
    DUP RCLI-REPLACE? IF DROP 0 EXIT THEN
    RCLI.OWNER @ CINST-DESC
    DUP COMP.CAPS-N @ 2 =
    OVER S" resource.describe" ROT COMP-CAP-FIND 0<> AND
    OVER S" resource.snapshot" ROT COMP-CAP-FIND 0<> AND
    SWAP S" resource.replace" ROT COMP-CAP-FIND 0= AND ;

: _lpo-client-init  ( result binding -- status )
    _lpo-context @ _lpo-bus @ _lpo-client RCLI-INIT ;

: _lpo-describe-managed  ( -- )
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" resource" _lpo-request @ CBR.RESULT CV-MAP-FIND
        _lpo-ref IRES-RREF@ IRES-S-OK = _lpo-assert
    _lpo-ref RREF.ID 0 _lpo-rid RID= _lpo-assert
    _lpo-ref RREF.REVISION @ 0= _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 3 = _lpo-assert
    S" kind" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" managed-document" STR-STR= _lpo-assert
    S" title" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" Projection fixture" STR-STR= _lpo-assert
    S" media_type" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" text/plain" STR-STR= _lpo-assert
    S" mutable" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 9 = _lpo-assert
    S" owner" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert ;

: _lpo-snapshot  ( locator expected-a expected-u -- )
    _lpo-text-u ! _lpo-text-a !
    DUP CPRINC-USER _lpo-request @ _lpo-client RCLI-SNAPSHOT-CALL
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-SNAPSHOT-RESULT? _lpo-assert
    _lpo-text-a @ _lpo-text-u @ _lpo-result-content? _lpo-assert ;

: _lpo-current-retained-replace  ( -- )
    0 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 3 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    0 _lpo-rid 3 _lpo-digest-a _lpo-loc-a _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 1 = _lpo-assert
    _lpo-describe-managed
    _lpo-loc-a S" managed-0" _lpo-snapshot

    S" managed-updated" _lpo-digest-b SHA3-256-HASH
    _lpo-loc-a S" managed-updated" _lpo-digest-b CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-CALL
        CBUS-S-OK = _lpo-assert
    _lpo-loc-a _lpo-digest-b _lpo-request @ CBR.RESULT
        RCON-REPLACE-RESULT? _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND CV-DATA@
        4 = _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 2 = _lpo-assert
    _lpo-bind-a LBIND.REVISION @ 1 = _lpo-assert

    \ The retained frame is addressed by its content-frame domain revision,
    \ not by either intervening metadata-only domain revision.
    S" managed-0" _lpo-digest-a SHA3-256-HASH
    0 _lpo-rid 1 _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-b S" managed-0" _lpo-snapshot

    \ A retained historical frame remains readable through this RID owner,
    \ but its exact locator cannot be used as a writable-current alias.
    S" historical-denied" _lpo-digest-a SHA3-256-HASH
    _lpo-loc-b S" historical-denied" _lpo-digest-a CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-CALL
        CBUS-S-STALE-REVISION = _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 2 = _lpo-assert

    0 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 4 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 2 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-b
        SHA3-256-COMPARE _lpo-assert
    0 _lpo-rid 4 _lpo-digest-b _lpo-loc-c _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-c S" managed-updated" _lpo-snapshot
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-client RCLI-VALID? 0= _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-archived-ambient  ( -- )
    1 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 2 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    1 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    1 _lpo-rid 2 _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert

    \ The root remains bound to its configured store when an unrelated empty
    \ VFS becomes ambient.  Archived identity is unavailable because identity
    \ means active-current; the exact archived state remains readable.
    _lpo-other-vfs @ VFS-USE
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-bind-fail LBIND-INIT
    _lpo-result-fail RACQ-RESULT-INIT
    _lpo-loc-a _lpo-bind-fail _lpo-result-fail _lpo-attach
        RACQ-S-UNAVAILABLE = _lpo-assert
    _lpo-result-fail RACQ.RESULT-STATUS @
        RACQ-S-UNAVAILABLE = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-loc-b _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" resource" _lpo-request @ CBR.RESULT CV-MAP-FIND
        _lpo-ref IRES-RREF@ IRES-S-OK = _lpo-assert
    _lpo-ref RREF.ID 1 _lpo-rid RID= _lpo-assert
    _lpo-ref RREF.REVISION @ 0= _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 2 = _lpo-assert
    S" kind" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" managed-document" STR-STR= _lpo-assert
    S" title" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" Projection fixture" STR-STR= _lpo-assert
    S" media_type" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" text/plain" STR-STR= _lpo-assert
    S" mutable" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 0= _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 9 = _lpo-assert
    S" owner" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert
    _lpo-loc-b S" managed-1" _lpo-snapshot

    \ An archived exact state is readable but never mutable.  Refusal must
    \ leave its domain revision, lifecycle, and content digest unchanged.
    S" archived-denied" _lpo-digest-b SHA3-256-HASH
    _lpo-loc-b S" archived-denied" _lpo-digest-b CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-CALL
        CBUS-S-DENIED = _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 1 = _lpo-assert
    1 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 2 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a
        SHA3-256-COMPARE _lpo-assert
    _lpo-loc-b S" managed-1" _lpo-snapshot
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-vfs @ VFS-USE
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-published-tombstone  ( -- )
    \ Publication is never durable authority.  Once the configured store
    \ tombstones this RID, new acquisition and calls through the already
    \ published instance both fail closed.  Its existing lease remains an
    \ ordinary releasable lifetime token so final teardown cannot leak.
    2 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert
    2 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert

    2 _lpo-rid 1 _lpo-entry _lpo-store
        LIBRARY-VFS-STORE-TOMBSTONE-DESTRUCTIVE
        LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lpo-assert
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK <> _lpo-assert
    _lpo-loc-a CPRINC-USER _lpo-request @ _lpo-client
        RCLI-SNAPSHOT-CALL CBUS-S-OK <> _lpo-assert

    _lpo-bind-fail LBIND-INIT
    _lpo-loc-a _lpo-bind-fail _lpo-result-fail _lpo-attach
        RACQ-S-TOMBSTONED = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    2 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-capture-snapshot  ( -- )
    9 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    9 _lpo-rid _lpo-entry LIBE.DOMAIN-REVISION @ _lpo-digest-a
        _lpo-loc-a _lpo-exact-loc! QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-capture-client? _lpo-assert
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" resource" _lpo-request @ CBR.RESULT CV-MAP-FIND
        _lpo-ref IRES-RREF@ IRES-S-OK = _lpo-assert
    _lpo-ref RREF.ID 9 _lpo-rid RID= _lpo-assert
    _lpo-ref RREF.REVISION @ 0= _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 1 = _lpo-assert
    S" kind" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" capture" STR-STR= _lpo-assert
    S" title" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" Projection capture" STR-STR= _lpo-assert
    S" media_type" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" text/plain" STR-STR= _lpo-assert
    S" mutable" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 0= _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 13 = _lpo-assert
    S" owner" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert
    _lpo-loc-a S" capture bytes" _lpo-snapshot
    S" ignored" _lpo-digest-b SHA3-256-HASH
    _lpo-loc-a S" ignored" _lpo-digest-b CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-PREPARE
        RCLI-S-READONLY = _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-rejected  ( locator expected-status -- )
    _lpo-status !
    _lpo-bind-fail LBIND-INIT
    _lpo-result-fail RACQ-RESULT-INIT
    _lpo-bind-fail _lpo-result-fail _lpo-attach
        _lpo-status @ = _lpo-assert
    _lpo-result-fail RACQ.RESULT-STATUS @
        _lpo-status @ = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert ;

: _lpo-acquire-failures  ( -- )
    0 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 4 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY

    \ Owner mismatch is rejected by the portable acquisition boundary before
    \ the Library callback is entered.
    _lpo-ref RREF-INIT
    0 _lpo-rid _lpo-ref RREF.ID RID-COPY
    S" org.akashic.wrong-owner" _lpo-ref _lpo-loc-a QLOC-IDENTITY!
        QLOC-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ _lpo-before !
    _lpo-loc-a RACQ-S-OWNER-MISMATCH _lpo-rejected
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@
        _lpo-before @ = _lpo-assert

    \ The projection contract, exact domain revision, and projection digest
    \ are independent closed qualifiers.
    0 _lpo-rid 4 _lpo-digest-a _lpo-loc-a _lpo-exact-loc! DROP
    _lpo-loc-a _lpo-loc-b QLOC-COPY DROP
    [CHAR] x _lpo-loc-b QLOC.PROJECTION C!
    _lpo-loc-b QLOC-VALID? _lpo-assert
    _lpo-loc-b RACQ-S-UNQUALIFIED _lpo-rejected

    0 _lpo-rid 999 _lpo-digest-a _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-REVISION-MISMATCH _lpo-rejected

    _lpo-digest-a _lpo-digest-b RID-COPY
    _lpo-digest-b DUP C@ 1 XOR SWAP C!
    0 _lpo-rid 4 _lpo-digest-b _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-DIGEST-MISMATCH _lpo-rejected

    _lpo-unknown-rid _lpo-loc-b _lpo-identity-loc! DROP
    _lpo-loc-b RACQ-S-NOT-FOUND _lpo-rejected

    \ Domain revision two on document zero was metadata-only and never a
    \ content-frame alias.  Document three's original frame is truly pruned.
    S" managed-0" _lpo-digest-a SHA3-256-HASH
    0 _lpo-rid 2 _lpo-digest-a _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-GONE _lpo-rejected
    S" managed-3" _lpo-digest-a SHA3-256-HASH
    3 _lpo-rid 1 _lpo-digest-a _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-PRUNED _lpo-rejected

    2 _lpo-rid _lpo-loc-b _lpo-identity-loc! DROP
    _lpo-loc-b RACQ-S-TOMBSTONED _lpo-rejected
    _lpo-stack ;

: _lpo-capacity-contract  ( -- )
    LIB-PROJECTION-MAX 0 ?DO
        I _lpo-cap-rid _lpo-loc-a _lpo-identity-loc! DROP
        _lpo-loc-a I _lpo-cap-bind I _lpo-cap-result _lpo-attach
            RACQ-S-OK = _lpo-assert
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
            DUP 0>= _lpo-assert
            _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
            DUP 0<> _lpo-assert
            I 8 * _lpo-cap-instances + !
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
            1 = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ LIB-PROJECTION-MAX = _lpo-assert

    \ A ninth distinct RID cannot evict or retarget any fixed-RID owner.
    \ The ninth request is an exact archived state because archived identity
    \ is deliberately unavailable.
    1 _lpo-read-identity LIBSTORE-S-OK = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    1 _lpo-rid 2 _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-b 8 _lpo-cap-bind 8 _lpo-cap-result _lpo-attach
        RACQ-S-CAPACITY = _lpo-assert
    8 _lpo-cap-result RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    1 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    LIB-PROJECTION-MAX 0 ?DO
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
            _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
            I 8 * _lpo-cap-instances + @ = _lpo-assert
    LOOP

    \ Pool fullness is per distinct owner, not per lease.  Sharing remains
    \ available and must retain the original instance.
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc! DROP
    _lpo-loc-a 9 _lpo-cap-bind 9 _lpo-cap-result _lpo-attach
        RACQ-S-OK = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-cap-instances @ = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIB-PROJECTION-MAX 1+ = _lpo-assert

    \ Releasing one final reference frees exactly that owner slot.  The
    \ refused archived state can then acquire it without disturbing owners.
    7 _lpo-cap-bind 7 _lpo-cap-result RACQ-DETACH
        RACQ-S-OK = _lpo-assert
    9 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    _lpo-loc-b 7 _lpo-cap-bind 7 _lpo-cap-result _lpo-attach
        RACQ-S-OK = _lpo-assert
    1 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        DUP 0>= _lpo-assert
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        0<> _lpo-assert
    7 0 ?DO
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
            _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
            I 8 * _lpo-cap-instances + @ = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIB-PROJECTION-MAX 1+ = _lpo-assert

    LIB-PROJECTION-MAX 0 ?DO
        I _lpo-cap-bind I _lpo-cap-result RACQ-DETACH
            RACQ-S-OK = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpo-assert
    9 _lpo-cap-bind 9 _lpo-cap-result RACQ-DETACH
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-lease-capacity-contract  ( -- )
    \ Lease capacity is independent of the eight-owner pool.  One fixed-RID
    \ owner may be shared through exactly 64 distinct activation-local tokens.
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    LIBRARY-PROJECTION-LEASE-MAX 0 ?DO
        _lpo-loc-a I _lpo-cap-bind I _lpo-cap-result _lpo-attach
            RACQ-S-OK = _lpo-assert
        I _lpo-cap-result RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
            _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        DUP 0>= _lpo-assert
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        DUP _lpo-instance ! 0<> _lpo-assert

    \ The 65th token refuses without changing the shared instance or counts.
    _lpo-loc-a LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-bind
        LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-result _lpo-attach
        RACQ-S-CAPACITY = _lpo-assert
    LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-result
        RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-instance @ = _lpo-assert

    \ Releasing any one token makes one ledger slot reusable without
    \ retargeting the owner or changing its other 63 references.
    0 _lpo-cap-bind 0 _lpo-cap-result RACQ-DETACH
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX 1- = _lpo-assert
    _lpo-loc-a LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-bind
        LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-result _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-instance @ = _lpo-assert

    LIBRARY-PROJECTION-LEASE-MAX 1+ 1 ?DO
        I _lpo-cap-bind I _lpo-cap-result RACQ-DETACH
            RACQ-S-OK = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-root-fini-contract  ( -- )
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc! DROP
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-BUSY = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-bind-a _lpo-result-a RACQ-DETACH RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-SIZE _lpo-zero? _lpo-assert
    _lpo-creg @ CREG.INST-N @ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-teardown  ( -- )
    _lpo-request @ CBR-FREE
    0 _lpo-request !
    _lpo-bus @ CBUS-FREE
    _lpo-rreg @ RREG-FREE
    _lpo-creg @ CREG-FREE
    _lpo-cold-context @ CTX-FREE
    _lpo-context @ CTX-FREE
    _lpo-vfs @ VFS-USE
    _lpo-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lpo-assert
    _lpo-store-slot @ FREE 0 _lpo-store-slot !
    _lpo-old-vfs @ VFS-USE
    _lpo-other-vfs @ VFS-DESTROY
    _lpo-vfs @ VFS-DESTROY
    _lpo-capacity-buffers-free
    _lpo-stack ;

: _lpo-run  ( -- )
    0 _lpo-fails ! 0 _lpo-checks ! DEPTH _lpo-depth !
    _lpo-capacity-buffers-setup
    _lpo-store-setup
    _lpo-runtime-setup
    _lpo-root-contract
    _lpo-attach-alias-contract
    _lpo-sharing-release
    _lpo-current-retained-replace
    _lpo-archived-ambient
    _lpo-capture-snapshot
    _lpo-published-tombstone
    _lpo-acquire-failures
    _lpo-capacity-contract
    _lpo-lease-capacity-contract
    _lpo-root-fini-contract
    _lpo-teardown
    _lpo-stack
    _lpo-fails @ ?DUP IF
        ." LIBRARY PROJECTION OWNER FAIL " .
        ."  / " _lpo-checks @ . CR
    ELSE
        ." LIBRARY PROJECTION OWNER PASS " _lpo-checks @ . CR
    THEN ;

_lpo-run
