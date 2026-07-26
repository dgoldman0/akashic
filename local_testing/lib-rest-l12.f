\ Focused scalable retained-content restore contracts for the L12 Library owner.

PROVIDED akashic-library-retained-restore-l12-contracts

VARIABLE _LR12-checks
VARIABLE _LR12-fails
VARIABLE _LR12-depth
VARIABLE _LR12-arena
VARIABLE _LR12-vfs
VARIABLE _LR12-ior
VARIABLE _LR12-si-store
VARIABLE _LR12-si-pwork
VARIABLE _LR12-si-buffer
VARIABLE _LR12-si-guard
VARIABLE _LR12-input-a
VARIABLE _LR12-input-u
VARIABLE _LR12-next-arg
VARIABLE _LR12-generation
VARIABLE _LR12-range-u
VARIABLE _LR12-fd
VARIABLE _LR12-byte
VARIABLE _LR12-offset

CREATE _LR12-ops VFS-OPS-SIZE ALLOT
CREATE _LR12-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _LR12-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _LR12-bootstrap RID-SIZE ALLOT
CREATE _LR12-store PSTORE-SIZE ALLOT
CREATE _LR12-store-cold PSTORE-SIZE ALLOT
CREATE _LR12-pwork PSTORE-WORK-SIZE ALLOT
CREATE _LR12-pwork-cold PSTORE-WORK-SIZE ALLOT
LIBPA-RECORD-MAX PERSIST-RECORD-HEADER-SIZE + CONSTANT _LR12-buffer-u
_LR12-buffer-u XBUF _LR12-buffer
_LR12-buffer-u XBUF _LR12-buffer-cold
CREATE _LR12-adapter LIBPA-SIZE ALLOT
CREATE _LR12-adapter-cold LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _LR12-work
LIBPA-INDEX-WORK-SIZE XBUF _LR12-work-cold
8192 CONSTANT _LR12-audit-map-capacity
_LR12-audit-map-capacity XBUF _LR12-audit-map
_LR12-audit-map-capacity XBUF _LR12-audit-map-cold
GUARD _LR12-guard
GUARD _LR12-guard-cold

CREATE _LR12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-SIZE ALLOT
CREATE _LR12-entry LIB-ENTRY-SIZE ALLOT
CREATE _LR12-entry-next LIB-ENTRY-SIZE ALLOT
CREATE _LR12-entry-bad LIB-ENTRY-SIZE ALLOT
CREATE _LR12-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _LR12-entry-sentinel LIB-ENTRY-SIZE ALLOT
CREATE _LR12-entry-cold LIB-ENTRY-SIZE ALLOT
CREATE _LR12-content LIB-CONTENT-SIZE ALLOT
CREATE _LR12-content-next LIB-CONTENT-SIZE ALLOT
CREATE _LR12-current LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LR12-target LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LR12-restored LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LR12-descriptor-out LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LR12-descriptor-sentinel LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _LR12-content-ref PERSIST-REF-SIZE ALLOT
CREATE _LR12-io-byte 1 ALLOT
CREATE _LR12-retained-facts
    LIBRARY-RETAINED-CONTENT-FACTS-SIZE ALLOT
CREATE _LR12-row LIBPA-RANGE-ROW-SIZE ALLOT
CREATE _LR12-continuation LIBPA-CONTINUATION-SIZE ALLOT
CREATE _LR12-range 8 ALLOT

LIB-CONTENT-WINDOW-MAX 1+ CONSTANT _LR12-large-u
_LR12-large-u XBUF _LR12-large
\ SHA3-256 of 65,537 "A" bytes with offsets 32767..32769 replaced by "XYZ".
\ Hashing that deterministic setup payload in guest Forth would dominate the
\ restore proof while adding no restore-path coverage.
CREATE _LR12-large-digest
0xA6 C, 0xAB C, 0x07 C, 0x22 C, 0xE8 C, 0xCC C, 0x7A C, 0x0E C,
0x58 C, 0xE0 C, 0xCA C, 0x12 C, 0xB6 C, 0x53 C, 0xC0 C, 0x65 C,
0x10 C, 0x12 C, 0xD0 C, 0x57 C, 0x38 C, 0xF7 C, 0x3C C, 0x4A C,
0x55 C, 0xA0 C, 0xA5 C, 0x4E C, 0xC8 C, 0x05 C, 0x55 C, 0xD0 C,
1 CONSTANT _LR12-target-domain
2 CONSTANT _LR12-next-retained-domain
0xFFFFFF0000000006 CONSTANT _LR12-uart-flush

: _LR12-flush  ( -- )
    0 _LR12-uart-flush C! ;

: _LR12-assert  ( flag -- )
    1 _LR12-checks +!
    0= IF
        1 _LR12-fails +!
        ." LIBRARY RESTORE L12 ASSERT " _LR12-checks @ . CR
    THEN ;

: _LR12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY RESTORE L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LR12-assert ;

: _LR12-stack  ( -- )
    DEPTH _LR12-depth @ = _LR12-assert ;

: _LR12-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _LR12-store-init  ( store pwork buffer guard -- )
    _LR12-si-guard !
    _LR12-si-buffer !
    _LR12-si-pwork !
    _LR12-si-store !
    S" /lr12-pages" S" /lr12-segment"
    S" /lr12-root-a" S" /lr12-root-b"
    _LR12-identity LIBPA-RECORD-MAX _LR12-vfs @ 0 0
    _LR12-si-guard @ 0 0 _LR12-si-store @
        PSTORE-INIT PERSIST-S-OK _LR12-status
    _LR12-si-buffer @ _LR12-buffer-u _LR12-si-pwork @
        PSTORE-WORK-INIT PERSIST-S-OK _LR12-status ;

: _LR12-setup  ( -- )
    VFS-RAM-OPS _LR12-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _LR12-binding VFS-BINDING-DESC-SIZE MOVE
    _LR12-ops _LR12-binding VB.OPS !
    33554432 A-XMEM ARENA-NEW DUP 0= _LR12-assert DROP _LR12-arena !
    _LR12-arena @ _LR12-binding 0 VFS-NEW _LR12-ior ! _LR12-vfs !
    _LR12-ior @ 0= _LR12-assert
    _LR12-vfs @ 0<> _LR12-assert
    _LR12-identity PERSIST-IDENTITY-SIZE 0x71 FILL
    _LR12-bootstrap RID-SIZE 0xA1 FILL

    _LR12-store _LR12-pwork _LR12-buffer _LR12-guard
        _LR12-store-init
    _LR12-store _LR12-adapter LIBPA-INIT
        LIBPA-S-OK _LR12-status
    _LR12-audit-map _LR12-audit-map-capacity
        _LR12-pwork _LR12-adapter _LR12-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LR12-status
    _LR12-store _LR12-pwork PSTORE-PROVISION
        PERSIST-S-OK _LR12-status
    _LR12-adapter _LR12-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _LR12-status
    _LR12-bootstrap _LR12-adapter _LR12-work LIBPA-INDEX-PROVISION
        LIBPA-S-OK _LR12-status
    _LR12-stack ;

: _LR12-draft!  ( -- )
    _LR12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LR12-draft LSDID.ID RID-CLEAR
    0x41 _LR12-draft LSDID.ID !
    _LR12-draft LSDID.OPERATION-KEY RID-CLEAR
    0x51 _LR12-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _LR12-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _LR12-draft LSDID.MEDIA !
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
        _LR12-draft LSDID.MUTATION-SEQUENCE !
    S" seed one"
    DUP _LR12-draft LSDID.CONTENT-U !
    DROP _LR12-draft LSDID.CONTENT-A !
    S" Retained restore"
    DUP _LR12-draft LSDID.TITLE-U !
    _LR12-draft LSDID.TITLE SWAP MOVE
    0 0 _LR12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-FACTS!
        _LIBDV-S-OK _LR12-status
    _LR12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-VALID? _LR12-assert
    _LR12-draft _LR12-entry _LR12-content
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
        _LIBDV-S-OK _LR12-status ;

: _LR12-create  ( -- )
    _LR12-draft!
    _LR12-entry _LR12-content 0 0 0 _LR12-entry-out
        _LR12-adapter _LR12-work LIBPA-DOCUMENT-CREATE-EXACT
        LIBPA-S-OK _LR12-status
    _LR12-entry-out _LR12-entry LIB-ENTRY-SIZE MOVE
    _LR12-entry LIBE.DOMAIN-REVISION @ 1 = _LR12-assert
    _LR12-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _LR12-assert
    _LR12-stack ;

: _LR12-replace  ( data-a data-u -- )
    _LR12-input-u !
    _LR12-input-a !
    _LR12-entry
    _LR12-input-a @ _LR12-input-u @
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
    _LR12-entry-next _LR12-content-next
        LIBRARY-SERVICE-PREPARE-CONTENT-NEXT
        _LIBDV-S-OK _LR12-status
    _LR12-entry-next _LR12-content-next
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-entry LIBE.DOMAIN-REVISION @
    _LR12-entry-out _LR12-adapter _LR12-work
        LIBPA-DOCUMENT-CONTENT-REPLACE-EXACT
        LIBPA-S-OK _LR12-status
    _LR12-entry-out _LR12-entry LIB-ENTRY-SIZE MOVE ;

: _LR12-four-content-revisions  ( -- )
    S" seed two" _LR12-replace
    S" seed three" _LR12-replace
    S" seed four" _LR12-replace
    _LR12-entry LIBE.DOMAIN-REVISION @ 4 = _LR12-assert
    _LR12-entry LIBE.CURRENT-CONTENT-REVISION @ 4 = _LR12-assert
    _LR12-entry LIBE.OLDEST-CONTENT-REVISION @ 1 = _LR12-assert
    _LR12-stack ;

: _LR12-large!  ( -- )
    _LR12-large _LR12-large-u [CHAR] A FILL
    [CHAR] X _LR12-large PBLOB-CHUNK-SIZE 1- + C!
    [CHAR] Y _LR12-large PBLOB-CHUNK-SIZE + C!
    [CHAR] Z _LR12-large PBLOB-CHUNK-SIZE 1+ + C! ;

: _LR12-install-large-target  ( -- )
    _LR12-large!
    _LR12-adapter _LR12-work LIBPA-INDEX-BEGIN
        LIBPA-S-OK _LR12-status
    _LR12-large-u ['] _LIBPIX-MEMORY-SOURCE _LR12-large
    _LR12-work _LIBPIX.BLOB
    _LR12-store _LR12-pwork _LR12-work _LIBPIX.BLOB-WORK
        PBLOB-WRITE PERSIST-S-OK _LR12-status
    _LR12-work _LIBPIX.STAGE
        LIBPA-CONTENT-DESCRIPTOR-SIZE 0 FILL
    _LIBPA-CONTENT-MAGIC
        _LR12-work _LIBPIX.STAGE _LIBPAC.MAGIC !
    LIBPA-CONTENT-F-LIBRARY
        _LR12-work _LIBPIX.STAGE _LIBPAC.FLAGS !
    _LR12-entry LIBE.ID
        _LR12-work _LIBPIX.STAGE _LIBPAC.RID RID-COPY
    _LR12-target-domain
        _LR12-work _LIBPIX.STAGE _LIBPAC.DOMAIN-REVISION !
    _LR12-target-domain
        _LR12-work _LIBPIX.STAGE _LIBPAC.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT
        _LR12-work _LIBPIX.STAGE _LIBPAC.KIND !
    LIB-MEDIA-TEXT-PLAIN
        _LR12-work _LIBPIX.STAGE _LIBPAC.MEDIA !
    _LR12-large-u _LR12-work _LIBPIX.STAGE _LIBPAC.DATA-U !
    _LR12-large-digest
        _LR12-work _LIBPIX.STAGE _LIBPAC.DIGEST LIB-DIGEST-SIZE MOVE
    _LR12-work _LIBPIX.BLOB
    _LR12-work _LIBPIX.STAGE _LIBPAC.BLOB
        PBLOB-COPY PERSIST-S-OK _LR12-status
    _LR12-work _LIBPIX.STAGE
        LIBPA-CONTENT-DESCRIPTOR-VALID? _LR12-assert
    _LR12-work _LIBPIX-CONTENT-APPEND
        LIBPA-S-OK _LR12-status
    _LR12-entry LIBE.ID _LR12-target-domain _LR12-work _LIBPIX.KEY0
        LIBPI-HISTORY-KEY LIB-S-OK _LR12-status
    _LR12-work _LIBPIX.KEY0 LIBPI-HISTORY-KEY-SIZE
    _LR12-work _LIBPIX.HISTORY-REF PERSIST-REF-SIZE
    _LIBPIX-HISTORY _LR12-work _LIBPIX-PUT
        LIBPA-S-OK _LR12-status
    1 _LR12-work _LIBPIX.RAW-N !
    _LR12-adapter _LR12-work LIBPA-INDEX-COMMIT
        LIBPA-S-OK _LR12-status

    _LR12-entry LIBE.ID _LR12-target-domain _LR12-target
        _LR12-adapter _LR12-work LIBPA-HISTORY-READ
        LIBPA-S-OK _LR12-status
    _LR12-target LIBPA-CONTENT-SIZE@ _LR12-large-u =
        _LR12-assert
    _LR12-target _LR12-retained-facts
        _LIBPA-DESCRIPTOR>RETAINED-FACTS
        LIBPA-S-OK _LR12-status
    _LR12-stack ;

: _LR12-archive  ( -- )
    _LR12-entry LIB-LIFECYCLE-ARCHIVED
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
    _LR12-entry-next LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
        _LIBDV-S-OK _LR12-status
    _LR12-entry-next
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-entry LIBE.DOMAIN-REVISION @
    _LR12-entry-out _LR12-adapter _LR12-work
        LIBPA-DOCUMENT-LIFECYCLE-REPLACE-EXACT
        LIBPA-S-OK _LR12-status
    _LR12-entry-out _LR12-entry LIB-ENTRY-SIZE MOVE
    _LR12-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED =
        _LR12-assert
    _LR12-stack ;

: _LR12-prepare-restore  ( -- )
    _LR12-entry _LR12-retained-facts
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
    _LR12-entry-next
        LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
        _LIBDV-S-OK _LR12-status
    _LR12-entry-next LIB-ENTRY-VALID? _LR12-assert
    _LR12-entry-next LIBE.DOMAIN-REVISION @
        _LR12-entry LIBE.DOMAIN-REVISION @ 1+ = _LR12-assert
    _LR12-entry-next LIBE.CURRENT-CONTENT-REVISION @ 5 =
        _LR12-assert
    _LR12-entry-next LIBE.OLDEST-CONTENT-REVISION @ 2 =
        _LR12-assert
    _LR12-entry-next LIBE.CONTENT-U @ _LR12-large-u =
        _LR12-assert
    _LR12-entry-next LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED =
        _LR12-assert
    _LR12-entry-next LIBE.RECEIPT
    _LR12-entry LIBE.RECEIPT LIB-RECEIPT-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-entry-next LIBE.METADATA-DIGEST
    _LR12-entry LIBE.METADATA-DIGEST LIB-DIGEST-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-stack ;

: _LR12-output-sentinel!  ( -- )
    _LR12-entry-out LIB-ENTRY-SIZE 0xA5 FILL
    _LR12-entry-out _LR12-entry-sentinel LIB-ENTRY-SIZE MOVE ;

: _LR12-output-unchanged?  ( -- flag )
    _LR12-entry-out _LR12-entry-sentinel LIB-ENTRY-SIZE _LR12-bytes= ;

: _LR12-read-sentinels!  ( -- )
    _LR12-entry-out LIB-ENTRY-SIZE 0xA5 FILL
    _LR12-entry-out _LR12-entry-sentinel LIB-ENTRY-SIZE MOVE
    _LR12-descriptor-out LIBPA-CONTENT-DESCRIPTOR-SIZE 0x5A FILL
    _LR12-descriptor-out _LR12-descriptor-sentinel
        LIBPA-CONTENT-DESCRIPTOR-SIZE MOVE ;

: _LR12-read-outputs-unchanged?  ( -- flag )
    _LR12-output-unchanged?
    _LR12-descriptor-out _LR12-descriptor-sentinel
        LIBPA-CONTENT-DESCRIPTOR-SIZE _LR12-bytes= AND ;

: _LR12-generation-same?  ( -- flag )
    _LR12-store PSTORE-GENERATION@ _LR12-generation @ = ;

: _LR12-rejected-restore
  ( next expected-logical expected-domain expected-status -- )
    >R
    _LR12-input-u !
    _LR12-input-a !
    _LR12-next-arg !
    _LR12-output-sentinel!
    _LR12-store PSTORE-GENERATION@ _LR12-generation !
    _LR12-next-arg @ _LR12-target-domain
    _LR12-input-a @ _LR12-input-u @ _LR12-entry-out
        _LR12-adapter _LR12-work
        LIBPA-DOCUMENT-RESTORE-RETAINED-EXACT
    R> _LR12-status
    _LR12-output-unchanged? _LR12-assert
    _LR12-generation-same? _LR12-assert ;

: _LR12-conflict-and-invalid  ( -- )
    _LR12-entry-next
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@ 1-
    _LR12-entry LIBE.DOMAIN-REVISION @
    LIBPA-S-CONFLICT _LR12-rejected-restore
    _LR12-entry-next
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-entry LIBE.DOMAIN-REVISION @ 1-
    LIBPA-S-CONFLICT _LR12-rejected-restore

    _LR12-entry-next _LR12-entry-bad LIB-ENTRY-SIZE MOVE
    LIB-LIFECYCLE-ACTIVE _LR12-entry-bad LIBE.LIFECYCLE !
    _LR12-entry-bad LIB-ENTRY-VALID? _LR12-assert
    _LR12-entry-bad
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-entry LIBE.DOMAIN-REVISION @
    LIBPA-S-INVALID _LR12-rejected-restore

    _LR12-entry-next _LR12-entry-bad LIB-ENTRY-SIZE MOVE
    _LR12-entry-bad LIBE.CONTENT-DIGEST DUP C@
        1 XOR SWAP C!
    _LR12-entry-bad LIB-ENTRY-VALID? _LR12-assert
    _LR12-entry-bad
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-entry LIBE.DOMAIN-REVISION @
    LIBPA-S-INVALID _LR12-rejected-restore

    \ Restore is semantically a return to an older retained content revision,
    \ not a way to mint another revision for the already-current bytes.
    _LR12-entry LIBE.ID _LR12-entry-out _LR12-current
        _LR12-adapter _LR12-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _LR12-status
    _LR12-current _LR12-retained-facts
        _LIBPA-DESCRIPTOR>RETAINED-FACTS
        LIBPA-S-OK _LR12-status
    _LR12-entry _LR12-retained-facts
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
    _LR12-entry-bad
        LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
        _LIBDV-S-INVALID _LR12-status

    \ A structurally valid forged next value cannot bypass the exact owner.
    \ The equal-current descriptor is present, but it is not a restore target.
    _LR12-entry-next _LR12-entry-bad LIB-ENTRY-SIZE MOVE
    _LR12-retained-facts LIBRCF.DATA-U @
        _LR12-entry-bad LIBE.CONTENT-U !
    _LR12-retained-facts LIBRCF.DIGEST
        _LR12-entry-bad LIBE.CONTENT-DIGEST RID-COPY
    _LR12-entry-bad LIB-ENTRY-VALID? _LR12-assert
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@ _LR12-input-a !
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ _LR12-input-u !
    _LR12-store PSTORE-GENERATION@ _LR12-generation !
    _LR12-output-sentinel!
    _LR12-entry-bad
    _LR12-retained-facts LIBRCF.DOMAIN-REVISION @
    _LR12-input-a @
    _LR12-entry LIBE.DOMAIN-REVISION @
    _LR12-entry-out _LR12-adapter _LR12-work
        LIBPA-DOCUMENT-RESTORE-RETAINED-EXACT
        LIBPA-S-INVALID _LR12-status
    _LR12-output-unchanged? _LR12-assert
    _LR12-generation-same? _LR12-assert
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
        _LR12-input-a @ = _LR12-assert
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@
        _LR12-input-u @ = _LR12-assert
    _LR12-stack ;

: _LR12-candidate-count  ( adapter work -- count status )
    >R >R
    LIBPA-RANGE-CANDIDATE S" XYZ"
    _LR12-row 1 _LR12-continuation
    R> R> LIBPA-RANGE-FIRST ;

: _LR12-restore  ( -- )
    _LR12-adapter _LR12-work _LR12-candidate-count
        LIBPA-S-OK _LR12-status
    0= _LR12-assert
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
        _LR12-generation !
    _LR12-entry LIBE.DOMAIN-REVISION @
        _LR12-input-u !
    _LR12-entry-next _LR12-target-domain
    _LR12-generation @ _LR12-input-u @
    _LR12-entry-out _LR12-adapter _LR12-work
        LIBPA-DOCUMENT-RESTORE-RETAINED-EXACT
        LIBPA-S-OK _LR12-status
    _LR12-entry-next _LR12-entry-out LIB-ENTRY-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-entry-out _LR12-entry LIB-ENTRY-SIZE MOVE
    _LR12-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED =
        _LR12-assert

    _LR12-entry LIBE.ID
    _LR12-entry LIBE.DOMAIN-REVISION @ _LR12-restored
        _LR12-adapter _LR12-work LIBPA-HISTORY-READ
        LIBPA-S-OK _LR12-status
    _LR12-restored LIBPA-CONTENT-SIZE@ _LR12-large-u =
        _LR12-assert
    _LR12-target _LIBPAC.BLOB
    _LR12-restored _LIBPAC.BLOB PBLOB-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-target _LIBPAC.DIGEST
    _LR12-restored _LIBPAC.DIGEST LIB-DIGEST-SIZE
        _LR12-bytes= _LR12-assert

    _LR12-entry LIBE.ID _LR12-target-domain _LR12-current
        _LR12-adapter _LR12-work LIBPA-HISTORY-READ
        LIBPA-S-NOT-FOUND _LR12-status
    _LR12-adapter _LR12-work _LR12-candidate-count
        LIBPA-S-OK _LR12-status
    1 = _LR12-assert
    _LR12-row LIBPA-RANGE-ROW-RID@
        _LR12-entry LIBE.ID RID= _LR12-assert
    _LR12-row LIBPA-RANGE-ROW-VALUE@
        LIBPA-CANDIDATE-BODY AND 0<> _LR12-assert
    _LR12-stack ;

: _LR12-retry  ( -- )
    _LR12-store PSTORE-GENERATION@ _LR12-generation !
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@ _LR12-input-a !
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ _LR12-input-u !
    _LR12-entry-out LIB-ENTRY-SIZE 0xA5 FILL
    _LR12-entry-next _LR12-target-domain
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@ 1-
    _LR12-entry LIBE.DOMAIN-REVISION @ 1-
    _LR12-entry-out _LR12-adapter _LR12-work
        LIBPA-DOCUMENT-RESTORE-RETAINED-EXACT
        LIBPA-S-OK _LR12-status
    _LR12-entry-next _LR12-entry-out LIB-ENTRY-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-generation-same? _LR12-assert
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
        _LR12-input-a @ = _LR12-assert
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@
        _LR12-input-u @ = _LR12-assert
    _LR12-stack ;

: _LR12-segment-byte@  ( offset -- byte )
    _LR12-offset !
    S" /lr12-segment" VFS-FF-READ VFS-FF-WRITE OR
        _LR12-vfs @ VFS-OPEN?
    _LR12-ior ! _LR12-fd !
    _LR12-ior @ 0= _LR12-assert
    _LR12-fd @ 0<> _LR12-assert
    _LR12-fd @ 0= IF 0 EXIT THEN
    _LR12-offset @ _LR12-fd @ VFS-SEEK? 0= _LR12-assert
    _LR12-io-byte 1 _LR12-fd @ VFS-READ-EXACT 0= _LR12-assert
    _LR12-fd @ VFS-CLOSE? 0= _LR12-assert
    _LR12-io-byte C@ ;

: _LR12-segment-byte!  ( byte offset -- )
    _LR12-offset !
    _LR12-io-byte C!
    S" /lr12-segment" VFS-FF-READ VFS-FF-WRITE OR
        _LR12-vfs @ VFS-OPEN?
    _LR12-ior ! _LR12-fd !
    _LR12-ior @ 0= _LR12-assert
    _LR12-fd @ 0<> _LR12-assert
    _LR12-fd @ 0= IF EXIT THEN
    _LR12-offset @ _LR12-fd @ VFS-SEEK? 0= _LR12-assert
    _LR12-io-byte 1 _LR12-fd @ VFS-WRITE-EXACT 0= _LR12-assert
    _LR12-fd @ VFS-CLOSE? 0= _LR12-assert
    _LR12-vfs @ VFS-SYNC 0= _LR12-assert ;

: _LR12-current-content-ref@  ( -- )
    _LR12-entry LIBE.ID _LR12-work _LIBPIX.RID-ARG !
    _LR12-work _LIBPIX.OLD-ENTRY _LR12-work _LIBPIX.ENTRY-ARG !
    _LR12-work _LIBPIX-RID-LOOKUP-CORE LIBPA-S-OK _LR12-status
    _LR12-work _LIBPIX.STAGE _LIBPAD.CONTENT-REF
        _LR12-content-ref PERSIST-REF-COPY ;

: _LR12-corrupt-read-atomic  ( -- )
    _LR12-current-content-ref@
    _LR12-content-ref PREF.OFFSET @ CREC-HEADER-SIZE +
        DUP _LR12-offset !
        _LR12-segment-byte@ DUP _LR12-byte !
    1 XOR _LR12-offset @ _LR12-segment-byte!

    _LR12-read-sentinels!
    _LR12-entry LIBE.ID _LR12-entry-out _LR12-descriptor-out
        _LR12-adapter _LR12-work LIBPA-DOCUMENT-READ
        LIBPA-S-CORRUPT _LR12-status
    _LR12-read-outputs-unchanged? _LR12-assert

    _LR12-byte @ _LR12-offset @ _LR12-segment-byte!
    _LR12-entry LIBE.ID _LR12-entry-out _LR12-descriptor-out
        _LR12-adapter _LR12-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _LR12-status
    _LR12-entry-out _LR12-entry LIB-ENTRY-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-entry-out _LR12-descriptor-out
        _LIBPIX-DESCRIPTOR-AGREES? _LR12-assert
    _LR12-stack ;

: _LR12-pruned-target  ( -- )
    \ Construct a valid next entry from the oldest still-retained descriptor,
    \ then ask the exact owner for the independently pruned target.  Pure
    \ preparation intentionally rejects an equal-current descriptor.
    _LR12-entry LIBE.ID _LR12-next-retained-domain _LR12-current
        _LR12-adapter _LR12-work LIBPA-HISTORY-READ
        LIBPA-S-OK _LR12-status
    _LR12-current _LR12-retained-facts
        _LIBPA-DESCRIPTOR>RETAINED-FACTS
        LIBPA-S-OK _LR12-status
    _LR12-entry _LR12-retained-facts
    _LR12-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1+
    _LR12-entry-bad
        LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
        _LIBDV-S-OK _LR12-status
    _LR12-entry-bad
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-entry LIBE.DOMAIN-REVISION @
    LIBPA-S-NOT-FOUND _LR12-rejected-restore
    _LR12-stack ;

: _LR12-range-sink
  ( logical-offset source-a source-u context -- persist-status )
    >R
    DUP _LR12-input-u !
    2 PICK PBLOB-CHUNK-SIZE 1- - DUP 0< IF
        DROP _LIBPA-DROP3 R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    DUP _LR12-input-a !
    _LR12-input-u @ + 8 > IF
        _LIBPA-DROP3 R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    OVER
    R@ _LR12-input-a @ +
    _LR12-input-u @ MOVE
    _LR12-input-a @ _LR12-input-u @ +
        _LR12-range-u @ MAX _LR12-range-u !
    _LIBPA-DROP3
    R> DROP PERSIST-S-OK ;

: _LR12-range-contract  ( descriptor adapter work -- )
    >R >R
    _LR12-range 8 0 FILL
    0 _LR12-range-u !
    PBLOB-CHUNK-SIZE 1- 3
    ['] _LR12-range-sink _LR12-range
    R> R> LIBPA-CONTENT-RANGE
        LIBPA-S-OK _LR12-status
    _LR12-range-u @ 3 = _LR12-assert
    _LR12-range 3 S" XYZ" COMPARE 0= _LR12-assert ;

: _LR12-cold  ( -- )
    _LR12-store-cold _LR12-pwork-cold _LR12-buffer-cold
    _LR12-guard-cold _LR12-store-init
    _LR12-store-cold _LR12-adapter-cold LIBPA-INIT
        LIBPA-S-OK _LR12-status
    _LR12-audit-map-cold _LR12-audit-map-capacity
        _LR12-pwork-cold _LR12-adapter-cold _LR12-work-cold
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _LR12-status
    _LR12-store-cold _LR12-pwork-cold PSTORE-PROVISION
        PERSIST-S-OK _LR12-status
    _LR12-adapter-cold _LR12-work-cold LIBPA-INDEX-OPEN
        LIBPA-S-OK _LR12-status
    _LR12-entry LIBE.ID _LR12-entry-cold _LR12-current
        _LR12-adapter-cold _LR12-work-cold LIBPA-DOCUMENT-READ
        LIBPA-S-OK _LR12-status
    _LR12-entry _LR12-entry-cold LIB-ENTRY-SIZE
        _LR12-bytes= _LR12-assert
    _LR12-current LIBPA-CONTENT-SIZE@ _LR12-large-u =
        _LR12-assert
    _LR12-current _LR12-adapter-cold _LR12-work-cold
        _LR12-range-contract
    _LR12-adapter-cold _LR12-work-cold _LR12-candidate-count
        LIBPA-S-OK _LR12-status
    1 = _LR12-assert
    _LR12-work-cold LIBPA-INDEX-LOGICAL-GENERATION@
    _LR12-work LIBPA-INDEX-LOGICAL-GENERATION@ = _LR12-assert
    _LR12-stack ;

: _LR12-RUN  ( -- )
    0 _LR12-checks !
    0 _LR12-fails !
    DEPTH _LR12-depth !
    _LR12-setup
    _LR12-create
    _LR12-four-content-revisions
    _LR12-install-large-target
    _LR12-archive
    _LR12-prepare-restore
    _LR12-conflict-and-invalid
    _LR12-restore
    _LR12-retry
    _LR12-corrupt-read-atomic
    _LR12-pruned-target
    _LR12-cold
    _LR12-stack
    _LR12-fails @ IF
        ." LIBRARY RESTORE L12 FAIL " _LR12-fails @ .
        ." /" _LR12-checks @ . CR
    ELSE
        ." LIBRARY RESTORE L12 PASS " _LR12-checks @ . CR
    THEN
    _LR12-flush ;
