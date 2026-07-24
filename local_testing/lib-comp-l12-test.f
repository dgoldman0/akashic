\ Focused semantic contracts for the L12 Library compaction adapter.

PROVIDED akashic-library-compaction-l12-contracts

VARIABLE _L12X-checks
VARIABLE _L12X-fails
VARIABLE _L12X-depth
VARIABLE _L12X-arena
VARIABLE _L12X-vfs
VARIABLE _L12X-ior
VARIABLE _L12X-step-done
VARIABLE _L12X-step-used
VARIABLE _L12X-step-status
VARIABLE _L12X-step-calls
VARIABLE _L12X-sink-u
VARIABLE _L12X-document-id
VARIABLE _L12X-operation-key
VARIABLE _L12X-mutation-sequence

CREATE _L12X-ops VFS-OPS-SIZE ALLOT
CREATE _L12X-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _L12X-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _L12X-bootstrap RID-SIZE ALLOT

LIBPA-RECORD-MAX PERSIST-RECORD-HEADER-SIZE + CONSTANT _L12X-buffer-u

CREATE _L12X-es-store PSTORE-SIZE ALLOT
CREATE _L12X-es-pwork PSTORE-WORK-SIZE ALLOT
_L12X-buffer-u XBUF _L12X-es-buffer
CREATE _L12X-es-adapter LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _L12X-es-work
GUARD _L12X-es-guard

CREATE _L12X-eb-store PSTORE-SIZE ALLOT
CREATE _L12X-eb-pwork PSTORE-WORK-SIZE ALLOT
_L12X-buffer-u XBUF _L12X-eb-buffer
CREATE _L12X-eb-adapter LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _L12X-eb-work
GUARD _L12X-eb-guard
CREATE _L12X-empty-context LIBPA-COMPACTION-CONTEXT-SIZE ALLOT

CREATE _L12X-ds-store PSTORE-SIZE ALLOT
CREATE _L12X-ds-pwork PSTORE-WORK-SIZE ALLOT
_L12X-buffer-u XBUF _L12X-ds-buffer
CREATE _L12X-ds-adapter LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _L12X-ds-work
GUARD _L12X-ds-guard

CREATE _L12X-db-store PSTORE-SIZE ALLOT
CREATE _L12X-db-pwork PSTORE-WORK-SIZE ALLOT
_L12X-buffer-u XBUF _L12X-db-buffer
CREATE _L12X-db-adapter LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _L12X-db-work
GUARD _L12X-db-guard
CREATE _L12X-document-context LIBPA-COMPACTION-CONTEXT-SIZE ALLOT

CREATE _L12X-entry LIB-ENTRY-SIZE ALLOT
CREATE _L12X-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _L12X-entry-read LIB-ENTRY-SIZE ALLOT
CREATE _L12X-terminal-entry LIB-ENTRY-SIZE ALLOT
CREATE _L12X-content LIB-CONTENT-SIZE ALLOT
CREATE _L12X-source 32 ALLOT
CREATE _L12X-source-descriptor LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _L12X-builder-descriptor LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _L12X-sink 32 ALLOT
CREATE _L12X-bootstrap-out RID-SIZE ALLOT
CREATE _L12X-range-rows LIBPA-RANGE-ROW-SIZE 2 * ALLOT
CREATE _L12X-continuation LIBPA-CONTINUATION-SIZE ALLOT
CREATE _L12X-state-prefix 3 ALLOT
LIB-METADATA-FACT-HEADER-SIZE 3 + CONSTANT _L12X-facts-u
CREATE _L12X-facts _L12X-facts-u ALLOT
CREATE _L12X-metadata-summary LIB-METADATA-SUMMARY-SIZE ALLOT

: _L12X-assert  ( flag -- )
    1 _L12X-checks +!
    0= IF
        1 _L12X-fails +!
        ." LIBRARY COMPACTION L12 ASSERT " _L12X-checks @ . CR
    THEN ;

: _L12X-stack  ( -- )
    DEPTH DUP _L12X-depth @ <> IF
        ." LIBRARY COMPACTION L12 STACK "
        _L12X-depth @ . ." -> " DUP . CR .S CR
    THEN
    _L12X-depth @ = _L12X-assert ;

: _L12X-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY COMPACTION L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _L12X-assert _L12X-stack ;

: _L12X-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _L12X-text!  ( source-a source-u destination length-cell -- )
    >R
    OVER R@ !
    SWAP MOVE
    R> DROP ;

: _L12X-runtime-init  ( -- )
    VFS-RAM-OPS _L12X-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _L12X-binding VFS-BINDING-DESC-SIZE MOVE
    _L12X-ops _L12X-binding VB.OPS !
    67108864 A-XMEM ARENA-NEW DUP 0= _L12X-assert DROP
        _L12X-arena !
    _L12X-arena @ _L12X-binding 0 VFS-NEW
        _L12X-ior ! _L12X-vfs !
    _L12X-ior @ 0= _L12X-assert
    _L12X-vfs @ 0<> _L12X-assert
    _L12X-identity PERSIST-IDENTITY-SIZE 0x79 FILL
    _L12X-bootstrap RID-SIZE 0xA9 FILL
    _L12X-stack ;

: _L12X-es-init  ( -- )
    S" /l12x-es-pages" S" /l12x-es-segment"
    S" /l12x-es-root-a" S" /l12x-es-root-b"
    _L12X-identity LIBPA-RECORD-MAX _L12X-vfs @ 0 0
    _L12X-es-guard 0 0 _L12X-es-store
        PSTORE-INIT PERSIST-S-OK _L12X-status
    _L12X-es-buffer _L12X-buffer-u _L12X-es-pwork
        PSTORE-WORK-INIT PERSIST-S-OK _L12X-status
    _L12X-es-store _L12X-es-adapter LIBPA-INIT
        LIBPA-S-OK _L12X-status
    _L12X-es-pwork _L12X-es-adapter _L12X-es-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12X-status
    _L12X-es-store _L12X-es-pwork PSTORE-PROVISION
        PERSIST-S-OK _L12X-status
    _L12X-es-adapter _L12X-es-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _L12X-status
    _L12X-bootstrap _L12X-es-adapter _L12X-es-work
        LIBPA-INDEX-PROVISION LIBPA-S-OK _L12X-status ;

: _L12X-eb-init  ( -- )
    S" /l12x-eb-pages" S" /l12x-eb-segment"
    S" /l12x-eb-root-a" S" /l12x-eb-root-b"
    _L12X-identity LIBPA-RECORD-MAX _L12X-vfs @ 0 0
    _L12X-eb-guard 0 0 _L12X-eb-store
        PSTORE-INIT PERSIST-S-OK _L12X-status
    _L12X-eb-buffer _L12X-buffer-u _L12X-eb-pwork
        PSTORE-WORK-INIT PERSIST-S-OK _L12X-status
    _L12X-eb-store _L12X-eb-adapter LIBPA-INIT
        LIBPA-S-OK _L12X-status
    _L12X-eb-pwork _L12X-eb-adapter _L12X-eb-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12X-status
    _L12X-eb-store _L12X-eb-pwork PSTORE-PROVISION
        PERSIST-S-OK _L12X-status
    _L12X-eb-adapter _L12X-eb-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _L12X-status ;

: _L12X-ds-init  ( -- )
    S" /l12x-ds-pages" S" /l12x-ds-segment"
    S" /l12x-ds-root-a" S" /l12x-ds-root-b"
    _L12X-identity LIBPA-RECORD-MAX _L12X-vfs @ 0 0
    _L12X-ds-guard 0 0 _L12X-ds-store
        PSTORE-INIT PERSIST-S-OK _L12X-status
    _L12X-ds-buffer _L12X-buffer-u _L12X-ds-pwork
        PSTORE-WORK-INIT PERSIST-S-OK _L12X-status
    _L12X-ds-store _L12X-ds-adapter LIBPA-INIT
        LIBPA-S-OK _L12X-status
    _L12X-ds-pwork _L12X-ds-adapter _L12X-ds-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12X-status
    _L12X-ds-store _L12X-ds-pwork PSTORE-PROVISION
        PERSIST-S-OK _L12X-status
    _L12X-ds-adapter _L12X-ds-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _L12X-status
    _L12X-bootstrap _L12X-ds-adapter _L12X-ds-work
        LIBPA-INDEX-PROVISION LIBPA-S-OK _L12X-status ;

: _L12X-db-init  ( -- )
    S" /l12x-db-pages" S" /l12x-db-segment"
    S" /l12x-db-root-a" S" /l12x-db-root-b"
    _L12X-identity LIBPA-RECORD-MAX _L12X-vfs @ 0 0
    _L12X-db-guard 0 0 _L12X-db-store
        PSTORE-INIT PERSIST-S-OK _L12X-status
    _L12X-db-buffer _L12X-buffer-u _L12X-db-pwork
        PSTORE-WORK-INIT PERSIST-S-OK _L12X-status
    _L12X-db-store _L12X-db-adapter LIBPA-INIT
        LIBPA-S-OK _L12X-status
    _L12X-db-pwork _L12X-db-adapter _L12X-db-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12X-status
    _L12X-db-store _L12X-db-pwork PSTORE-PROVISION
        PERSIST-S-OK _L12X-status
    _L12X-db-adapter _L12X-db-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _L12X-status ;

: _L12X-run-empty-steps  ( -- )
    0 _L12X-step-done !
    0 _L12X-step-calls !
    BEGIN
        _L12X-step-done @ 0=
    WHILE
        _L12X-es-store PSTORE-CURRENT-ROOT@
        _L12X-eb-store _L12X-eb-pwork 3 _L12X-empty-context
        LIBPA-COMPACTION-STEP-XT EXECUTE
        _L12X-step-status !
        _L12X-step-used !
        _L12X-step-done !
        _L12X-step-status @ LIBPA-S-OK _L12X-status
        _L12X-step-status @ IF
            -1 _L12X-step-done !
        THEN
        _L12X-step-used @ DUP 0>= SWAP 3 <= AND _L12X-assert
        1 _L12X-step-calls +!
        _L12X-step-calls @ 256 < DUP _L12X-assert 0= IF
            -1 _L12X-step-done !
        THEN
    REPEAT
    _L12X-step-done @ _L12X-assert
    _L12X-stack ;

: _L12X-empty-contract  ( -- )
    _L12X-es-init
    _L12X-eb-init
    _L12X-es-adapter _L12X-es-work
    _L12X-eb-adapter _L12X-eb-work _L12X-empty-context
        LIBPA-COMPACTION-CONTEXT-INIT LIBPA-S-OK _L12X-status
    _L12X-empty-context LIBPA-COMPACTION-CONTEXT-VALID?
        _L12X-assert
    _L12X-empty-context _LIBPACOM.SOURCE-WORK @
        _L12X-es-work = _L12X-assert
    _L12X-empty-context _LIBPACOM.BUILDER-WORK @
        _L12X-eb-work = _L12X-assert
    _L12X-es-work _LIBPIX-READY? _L12X-assert
    _L12X-run-empty-steps
    _L12X-step-status @ IF EXIT THEN
    _L12X-eb-store PSTORE-GENERATION@ 1+
    _L12X-eb-store _L12X-eb-pwork _L12X-empty-context
        LIBPA-COMPACTION-FINALIZE-XT EXECUTE
        LIBPA-S-OK _L12X-status
    _L12X-eb-adapter _L12X-eb-work LIBPA-INDEX-REBIND
        LIBPA-S-OK _L12X-status
    _L12X-eb-work LIBPA-INDEX-LOGICAL-GENERATION@ 0=
        _L12X-assert
    _L12X-eb-work LIBPA-INDEX-MUTATION-SEQUENCE@ 0=
        _L12X-assert
    _L12X-eb-work LIBPA-INDEX-DOCUMENT-COUNT@ 0=
        _L12X-assert
    _L12X-bootstrap-out _L12X-eb-work LIBPA-INDEX-BOOTSTRAP-ID@
        LIBPA-S-OK _L12X-status
    _L12X-bootstrap _L12X-bootstrap-out RID= _L12X-assert
    _L12X-stack ;

: _L12X-document!  ( id operation-key mutation-sequence -- )
    _L12X-mutation-sequence !
    _L12X-operation-key !
    _L12X-document-id !
    _L12X-source 32 0 FILL
    S" payload" _L12X-source SWAP MOVE
    _L12X-content LIB-CONTENT-INIT
    _L12X-content LIBCT.ID RID-CLEAR
    _L12X-document-id @ _L12X-content LIBCT.ID !
    1 _L12X-content LIBCT.DOMAIN-REVISION !
    1 _L12X-content LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12X-content LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _L12X-content LIBCT.MEDIA !
    _L12X-source _L12X-content LIBCT.DATA-A !
    7 _L12X-content LIBCT.DATA-U !
    _L12X-content LIB-CONTENT-DIGEST! LIB-S-OK _L12X-status

    _L12X-entry LIB-ENTRY-INIT
    _L12X-entry LIBE.ID RID-CLEAR
    _L12X-document-id @ _L12X-entry LIBE.ID !
    1 _L12X-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12X-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _L12X-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _L12X-entry LIBE.MEDIA !
    1 _L12X-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _L12X-entry LIBE.OLDEST-CONTENT-REVISION !
    7 _L12X-entry LIBE.CONTENT-U !
    _L12X-content LIBCT.DIGEST
        _L12X-entry LIBE.CONTENT-DIGEST RID-COPY
    _L12X-mutation-sequence @ _L12X-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12X-entry LIBE.CREATED-CLOCK !
    _L12X-mutation-sequence @ _L12X-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12X-entry LIBE.MODIFIED-CLOCK !
    _L12X-mutation-sequence @ _L12X-entry LIBE.MODIFIED-VALUE !
    S" Note" _L12X-entry LIBE.TITLE
        _L12X-entry LIBE.TITLE-U _L12X-text!
    _L12X-facts _L12X-facts-u 0 FILL
    LIB-METADATA-FACT-TAG _L12X-facts LIBMF.KIND !
    3 _L12X-facts LIBMF.PAYLOAD-U !
    S" tag" _L12X-facts LIBMF.PAYLOAD SWAP MOVE
    _L12X-facts _L12X-facts-u _L12X-metadata-summary
        LIB-METADATA-SUMMARIZE LIB-S-OK _L12X-status
    _L12X-entry LIBE.RECEIPT DUP LIB-RECEIPT-INIT
    DUP LIBR.OPERATION-KEY RID-CLEAR
    _L12X-operation-key @ OVER LIBR.OPERATION-KEY !
    LIB-IMPORT-CREATED OVER LIBR.METHOD !
    1 OVER LIBR.INITIAL-CONTENT-REVISION !
    7 OVER LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN OVER LIBR.INITIAL-MEDIA !
    _L12X-entry LIBE.CONTENT-DIGEST
        OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
    DROP
    _L12X-metadata-summary _L12X-entry
        LIB-METADATA-SUMMARY-APPLY LIB-S-OK _L12X-status
    _L12X-entry LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _L12X-status
    _L12X-entry LIB-ENTRY-VALID? _L12X-assert
    _L12X-content LIB-CONTENT-VALID? _L12X-assert ;

: _L12X-run-document-steps  ( -- )
    0 _L12X-step-done !
    0 _L12X-step-calls !
    BEGIN
        _L12X-step-done @ 0=
    WHILE
        _L12X-ds-store PSTORE-CURRENT-ROOT@
        _L12X-db-store _L12X-db-pwork 3 _L12X-document-context
        LIBPA-COMPACTION-STEP-XT EXECUTE
        _L12X-step-status !
        _L12X-step-used !
        _L12X-step-done !
        _L12X-step-status @ LIBPA-S-OK _L12X-status
        _L12X-step-status @ IF
            -1 _L12X-step-done !
        THEN
        _L12X-step-used @ DUP 0>= SWAP 3 <= AND _L12X-assert
        1 _L12X-step-calls +!
        _L12X-step-calls @ 256 < DUP _L12X-assert 0= IF
            -1 _L12X-step-done !
        THEN
    REPEAT
    _L12X-step-done @ _L12X-assert
    _L12X-step-calls @ 3 > _L12X-assert
    _L12X-stack ;

: _L12X-sink-write
  ( logical-offset payload-a payload-u context -- status )
    DROP
    >R
    SWAP _L12X-sink + R@ MOVE
    R> _L12X-sink-u +!
    PERSIST-S-OK ;

: _L12X-range-only-active  ( family prefix-a prefix-u -- )
    _L12X-range-rows 2 _L12X-continuation
    _L12X-db-adapter _L12X-db-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12X-assert
    1 = _L12X-assert
    _L12X-range-rows LIBPA-RANGE-ROW-RID@
    _L12X-entry-out LIBE.ID RID= _L12X-assert ;

: _L12X-range-empty  ( family prefix-a prefix-u -- )
    _L12X-range-rows 2 _L12X-continuation
    _L12X-db-adapter _L12X-db-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12X-assert
    0= _L12X-assert ;

: _L12X-document-contract  ( -- )
    _L12X-ds-init
    _L12X-db-init
    0x41 0x51 1 _L12X-document!
    _L12X-entry _L12X-content _L12X-facts _L12X-facts-u
        0 _L12X-entry-out
        _L12X-ds-adapter _L12X-ds-work
        LIBPA-DOCUMENT-CREATE-EXACT LIBPA-S-OK _L12X-status
    S" tag" _L12X-entry-out _L12X-ds-adapter _L12X-ds-work
        LIBPA-INDEX-TAG?
        LIBPA-S-OK = _L12X-assert
        _L12X-assert
    _L12X-entry-out LIBE.ID _L12X-entry-read _L12X-source-descriptor
        _L12X-ds-adapter _L12X-ds-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _L12X-status

    \ Advance the control document's domain without replacing its content.
    \ Compaction must resolve the current content frame by its descriptor
    \ domain, not assume every metadata/lifecycle domain has a history row.
    _L12X-entry-read LIB-LIFECYCLE-ARCHIVED 2 _L12X-entry
        LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
        LIB-S-OK _L12X-status
    _L12X-entry 1 1 _L12X-entry-out
        _L12X-ds-adapter _L12X-ds-work
        LIBPA-DOCUMENT-LIFECYCLE-REPLACE-EXACT
        LIBPA-S-OK _L12X-status
    _L12X-entry-out LIB-LIFECYCLE-ACTIVE 3 _L12X-entry-read
        LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
        LIB-S-OK _L12X-status
    _L12X-entry-read 2 2 _L12X-entry-out
        _L12X-ds-adapter _L12X-ds-work
        LIBPA-DOCUMENT-LIFECYCLE-REPLACE-EXACT
        LIBPA-S-OK _L12X-status
    _L12X-entry-out LIBE.DOMAIN-REVISION @ 3 = _L12X-assert
    _L12X-entry-out LIBE.CURRENT-CONTENT-REVISION @ 1 =
        _L12X-assert

    \ Seed a second document through the same public mutation surface, then
    \ erase all of its visible secondaries before compaction. The active
    \ document remains as the exact control row in every shared range.
    0x42 0x52 4 _L12X-document!
    _L12X-entry _L12X-content _L12X-facts _L12X-facts-u
        3 _L12X-entry-read
        _L12X-ds-adapter _L12X-ds-work
        LIBPA-DOCUMENT-CREATE-EXACT LIBPA-S-OK _L12X-status
    _L12X-entry-read 5 _L12X-entry
        LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
        LIB-S-OK _L12X-status
    _L12X-entry 4 1 _L12X-terminal-entry
        _L12X-ds-adapter _L12X-ds-work
        LIBPA-DOCUMENT-TOMBSTONE-EXACT LIBPA-S-OK _L12X-status
    _L12X-terminal-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _L12X-assert

    _L12X-ds-adapter _L12X-ds-work
    _L12X-db-adapter _L12X-db-work _L12X-document-context
        LIBPA-COMPACTION-CONTEXT-INIT LIBPA-S-OK _L12X-status
    _L12X-document-context LIBPA-COMPACTION-CONTEXT-VALID?
        _L12X-assert
    _L12X-document-context _LIBPACOM.SOURCE-WORK @
        _L12X-ds-work = _L12X-assert
    _L12X-document-context _LIBPACOM.BUILDER-WORK @
        _L12X-db-work = _L12X-assert
    _L12X-ds-work _LIBPIX-READY? _L12X-assert
    _L12X-run-document-steps
    _L12X-step-status @ IF EXIT THEN
    _L12X-db-store PSTORE-GENERATION@ 1+
    _L12X-db-store _L12X-db-pwork _L12X-document-context
        LIBPA-COMPACTION-FINALIZE-XT EXECUTE
        LIBPA-S-OK _L12X-status
    _L12X-db-adapter _L12X-db-work LIBPA-INDEX-REBIND
        LIBPA-S-OK _L12X-status

    _L12X-db-work LIBPA-INDEX-LOGICAL-GENERATION@ 5 =
        _L12X-assert
    _L12X-db-work LIBPA-INDEX-MUTATION-SEQUENCE@ 5 =
        _L12X-assert
    _L12X-db-work LIBPA-INDEX-DOCUMENT-COUNT@ 2 =
        _L12X-assert
    _L12X-entry-out LIBE.ID _L12X-entry-read _L12X-builder-descriptor
        _L12X-db-adapter _L12X-db-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _L12X-status
    S" tag" _L12X-entry-read _L12X-db-adapter _L12X-db-work
        LIBPA-INDEX-TAG?
        LIBPA-S-OK = _L12X-assert
        _L12X-assert
    _L12X-entry-out _L12X-entry-read LIB-ENTRY-SIZE
        _L12X-bytes= _L12X-assert
    _L12X-entry-read LIBE.DOMAIN-REVISION @ 3 = _L12X-assert
    _L12X-builder-descriptor LIBPA-CONTENT-DOMAIN-REVISION@
        1 = _L12X-assert
    _L12X-source-descriptor _L12X-builder-descriptor
        LIBPA-CONTENT-EQUAL? _L12X-assert

    _L12X-sink 32 0 FILL
    0 _L12X-sink-u !
    _L12X-builder-descriptor 0 ['] _L12X-sink-write 0
        _L12X-db-adapter _L12X-db-work LIBPA-CONTENT-STREAM
        LIBPA-S-OK _L12X-status
    _L12X-sink-u @ 7 = _L12X-assert
    _L12X-source _L12X-sink 7 _L12X-bytes= _L12X-assert

    \ The compacted tombstone remains terminal point authority by RID.
    _L12X-terminal-entry LIBE.ID
    _L12X-entry-read _L12X-builder-descriptor
    _L12X-db-adapter _L12X-db-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _L12X-status
    _L12X-terminal-entry _L12X-entry-read LIB-ENTRY-SIZE
        _L12X-bytes= _L12X-assert
    _L12X-entry-read LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _L12X-assert

    \ Every shared visible range contains only the retained active document.
    \ This detects stale pre-tombstone rows as well as newly synthesized
    \ terminal rows.
    LIBPA-RANGE-DOCUMENT-RECENCY 0 0 _L12X-range-only-active
    LIBPA-RANGE-DOCUMENT-TITLE S" Note" _L12X-range-only-active
    LIBPA-RANGE-EXACT-TAG S" tag" _L12X-range-only-active
    LIBPA-RANGE-CANDIDATE S" Not" _L12X-range-only-active
    LIBPA-RANGE-CANDIDATE S" pay" _L12X-range-only-active

    LIB-LIFECYCLE-ACTIVE _L12X-state-prefix C!
    LIB-KIND-MANAGED-DOCUMENT _L12X-state-prefix 1+ C!
    LIB-MEDIA-TEXT-PLAIN _L12X-state-prefix 2 + C!
    LIBPA-RANGE-DOCUMENT-STATE-CREATION
        _L12X-state-prefix 3 _L12X-range-only-active
    LIBPA-RANGE-DOCUMENT-STATE-RECENCY
        _L12X-state-prefix 3 _L12X-range-only-active

    LIB-LIFECYCLE-TOMBSTONED _L12X-state-prefix C!
    LIB-MEDIA-NONE _L12X-state-prefix 2 + C!
    LIBPA-RANGE-DOCUMENT-STATE-CREATION
        _L12X-state-prefix 3 _L12X-range-empty
    LIBPA-RANGE-DOCUMENT-STATE-RECENCY
        _L12X-state-prefix 3 _L12X-range-empty
    LIBPA-RANGE-HISTORY
        _L12X-terminal-entry LIBE.ID RID-SIZE _L12X-range-empty
    _L12X-stack ;

: _L12X-RUN  ( -- )
    DEPTH _L12X-depth !
    0 _L12X-checks !
    0 _L12X-fails !
    _L12X-runtime-init
    _L12X-empty-contract
    _L12X-document-contract
    _L12X-stack
    _L12X-fails @ IF
        ." LIBRARY COMPACTION L12 FAIL "
        _L12X-fails @ . ." / " _L12X-checks @ . CR
    ELSE
        ." LIBRARY COMPACTION L12 PASS "
        _L12X-checks @ . ." assertions" CR
    THEN ;
