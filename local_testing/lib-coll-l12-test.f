\ Focused fresh-dictionary contracts for exact L12 collection ownership.

PROVIDED akashic-library-collection-l12-contracts

VARIABLE _L12C-checks
VARIABLE _L12C-fails
VARIABLE _L12C-depth
VARIABLE _L12C-arena
VARIABLE _L12C-vfs
VARIABLE _L12C-ior
VARIABLE _L12C-si-store
VARIABLE _L12C-si-pwork
VARIABLE _L12C-si-buffer
VARIABLE _L12C-si-guard
VARIABLE _L12C-id
VARIABLE _L12C-op
VARIABLE _L12C-sequence

CREATE _L12C-ops VFS-OPS-SIZE ALLOT
CREATE _L12C-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _L12C-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _L12C-bootstrap RID-SIZE ALLOT
CREATE _L12C-store PSTORE-SIZE ALLOT
CREATE _L12C-store-cold PSTORE-SIZE ALLOT
CREATE _L12C-pwork PSTORE-WORK-SIZE ALLOT
CREATE _L12C-pwork-cold PSTORE-WORK-SIZE ALLOT
LIBPA-RECORD-MAX PERSIST-RECORD-HEADER-SIZE + CONSTANT _L12C-buffer-u
_L12C-buffer-u XBUF _L12C-buffer
_L12C-buffer-u XBUF _L12C-buffer-cold
CREATE _L12C-adapter LIBPA-SIZE ALLOT
CREATE _L12C-adapter-cold LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _L12C-work
LIBPA-INDEX-WORK-SIZE XBUF _L12C-work-cold
8192 CONSTANT _L12C-audit-map-capacity
_L12C-audit-map-capacity XBUF _L12C-audit-map
_L12C-audit-map-capacity XBUF _L12C-audit-map-cold
GUARD _L12C-guard
GUARD _L12C-guard-cold

CREATE _L12C-entry LIB-ENTRY-SIZE ALLOT
CREATE _L12C-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _L12C-content LIB-CONTENT-SIZE ALLOT
CREATE _L12C-data 16 ALLOT
CREATE _L12C-members RID-SIZE 2 * ALLOT
CREATE _L12C-members-one RID-SIZE ALLOT
CREATE _L12C-members-bad RID-SIZE 2 * ALLOT
CREATE _L12C-collection LIB-COLLECTION-SIZE ALLOT
CREATE _L12C-collection-next LIB-COLLECTION-SIZE ALLOT
CREATE _L12C-collection-out LIB-COLLECTION-SIZE ALLOT
CREATE _L12C-collection-read LIB-COLLECTION-SIZE ALLOT
CREATE _L12C-collection-snapshot LIB-COLLECTION-SIZE ALLOT
CREATE _L12C-collection-cold LIB-COLLECTION-SIZE ALLOT
CREATE _L12C-rows LIBPA-RANGE-ROW-SIZE 2 * ALLOT
CREATE _L12C-continuation LIBPA-CONTINUATION-SIZE ALLOT
CREATE _L12C-many-rids RID-SIZE 129 * ALLOT
CREATE _L12C-many-collection LIB-COLLECTION-SIZE ALLOT

: _L12C-assert  ( flag -- )
    1 _L12C-checks +!
    0= IF
        1 _L12C-fails +!
        ." LIBRARY COLLECTION L12 ASSERT " _L12C-checks @ . CR
    THEN ;

: _L12C-stack  ( -- )
    DEPTH _L12C-depth @ = _L12C-assert ;

: _L12C-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY COLLECTION L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _L12C-assert _L12C-stack ;

: _L12C-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _L12C-text!  ( source-a source-u destination length-cell -- )
    >R
    OVER R@ !
    SWAP MOVE
    R> DROP ;

: _L12C-store-init  ( store pwork buffer guard -- )
    _L12C-si-guard !
    _L12C-si-buffer !
    _L12C-si-pwork !
    _L12C-si-store !
    S" /l12c-pages" S" /l12c-segment"
    S" /l12c-root-a" S" /l12c-root-b"
    _L12C-identity LIBPA-RECORD-MAX _L12C-vfs @ 0 0
    _L12C-si-guard @ 0 0 _L12C-si-store @
        PSTORE-INIT PERSIST-S-OK _L12C-status
    _L12C-si-buffer @ _L12C-buffer-u _L12C-si-pwork @
        PSTORE-WORK-INIT PERSIST-S-OK _L12C-status ;

: _L12C-setup  ( -- )
    VFS-RAM-OPS _L12C-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _L12C-binding VFS-BINDING-DESC-SIZE MOVE
    _L12C-ops _L12C-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW DUP 0= _L12C-assert DROP
        _L12C-arena !
    _L12C-arena @ _L12C-binding 0 VFS-NEW
        _L12C-ior ! _L12C-vfs !
    _L12C-ior @ 0= _L12C-assert
    _L12C-vfs @ 0<> _L12C-assert
    _L12C-identity PERSIST-IDENTITY-SIZE 0x79 FILL
    _L12C-bootstrap RID-SIZE 0xA9 FILL
    _L12C-store _L12C-pwork _L12C-buffer _L12C-guard
        _L12C-store-init
    _L12C-store _L12C-adapter LIBPA-INIT
        LIBPA-S-OK _L12C-status
    _L12C-audit-map _L12C-audit-map-capacity
        _L12C-pwork _L12C-adapter _L12C-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12C-status
    _L12C-store _L12C-pwork PSTORE-PROVISION
        PERSIST-S-OK _L12C-status
    _L12C-adapter _L12C-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _L12C-status
    _L12C-bootstrap _L12C-adapter _L12C-work
        LIBPA-INDEX-PROVISION LIBPA-S-OK _L12C-status ;

: _L12C-document!  ( id operation-key mutation-sequence -- )
    _L12C-sequence !
    _L12C-op !
    _L12C-id !
    _L12C-data 16 0 FILL
    S" payload" _L12C-data SWAP MOVE
    _L12C-content LIB-CONTENT-INIT
    _L12C-content LIBCT.ID RID-CLEAR
    _L12C-id @ _L12C-content LIBCT.ID !
    1 _L12C-content LIBCT.DOMAIN-REVISION !
    1 _L12C-content LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12C-content LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _L12C-content LIBCT.MEDIA !
    _L12C-data _L12C-content LIBCT.DATA-A !
    7 _L12C-content LIBCT.DATA-U !
    _L12C-content LIB-CONTENT-DIGEST!
        LIB-S-OK _L12C-status

    _L12C-entry LIB-ENTRY-INIT
    _L12C-entry LIBE.ID RID-CLEAR
    _L12C-id @ _L12C-entry LIBE.ID !
    1 _L12C-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12C-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _L12C-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _L12C-entry LIBE.MEDIA !
    1 _L12C-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _L12C-entry LIBE.OLDEST-CONTENT-REVISION !
    7 _L12C-entry LIBE.CONTENT-U !
    _L12C-content LIBCT.DIGEST
        _L12C-entry LIBE.CONTENT-DIGEST RID-COPY
    _L12C-sequence @ _L12C-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12C-entry LIBE.CREATED-CLOCK !
    _L12C-sequence @ _L12C-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12C-entry LIBE.MODIFIED-CLOCK !
    _L12C-sequence @ _L12C-entry LIBE.MODIFIED-VALUE !
    S" Note" _L12C-entry LIBE.TITLE
        _L12C-entry LIBE.TITLE-U _L12C-text!
    _L12C-entry LIBE.RECEIPT DUP LIB-RECEIPT-INIT
    DUP LIBR.OPERATION-KEY RID-CLEAR
    _L12C-op @ OVER LIBR.OPERATION-KEY !
    LIB-IMPORT-CREATED OVER LIBR.METHOD !
    1 OVER LIBR.INITIAL-CONTENT-REVISION !
    7 OVER LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN OVER LIBR.INITIAL-MEDIA !
    _L12C-entry LIBE.CONTENT-DIGEST
        OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
    DROP
    0 0 _L12C-entry LIBE.METADATA-DIGEST SHA3-256-HASH
    _L12C-entry LIB-ENTRY-REQUEST-SEAL!
        LIB-S-OK _L12C-status
    _L12C-entry LIB-ENTRY-VALID? _L12C-assert
    _L12C-content LIB-CONTENT-VALID? _L12C-assert ;

: _L12C-create-documents  ( -- )
    0x41 0x51 1 _L12C-document!
    _L12C-entry _L12C-content 0 0 0 _L12C-entry-out
        _L12C-adapter _L12C-work LIBPA-DOCUMENT-CREATE-EXACT
        LIBPA-S-OK _L12C-status
    _L12C-entry-out LIBE.ID _L12C-members RID-COPY
    0x42 0x52 2 _L12C-document!
    _L12C-entry _L12C-content 0 0 1 _L12C-entry-out
        _L12C-adapter _L12C-work LIBPA-DOCUMENT-CREATE-EXACT
        LIBPA-S-OK _L12C-status
    _L12C-entry-out LIBE.ID _L12C-members RID-SIZE + RID-COPY
    _L12C-work LIBPA-INDEX-DOCUMENT-COUNT@ 2 =
        _L12C-assert
    _L12C-work LIBPA-INDEX-LOGICAL-GENERATION@ 2 =
        _L12C-assert ;

: _L12C-collection!  ( -- )
    _L12C-collection LIBPA-COLLECTION-INIT
    _L12C-collection LIBC.ID RID-CLEAR
    0x61 _L12C-collection LIBC.ID !
    _L12C-collection LIBC.OPERATION-KEY RID-CLEAR
    0x71 _L12C-collection LIBC.OPERATION-KEY !
    1 _L12C-collection LIBC.REVISION !
    3 _L12C-collection LIBC.MUTATION-SEQUENCE !
    3 _L12C-collection LIBC.CREATED-SEQUENCE !
    2 _L12C-collection LIBC.MEMBER-N !
    S" Alpha" _L12C-collection LIBC.TITLE
        _L12C-collection LIBC.TITLE-U _L12C-text!
    _L12C-collection _L12C-members 2
        LIBPA-COLLECTION-REQUEST-SEAL!
        LIBPA-S-OK _L12C-status
    _L12C-collection LIBPA-COLLECTION-VALID? _L12C-assert ;

: _L12C-range-two?  ( -- )
    LIBPA-RANGE-MEMBERSHIP
    _L12C-collection LIBC.ID RID-SIZE
    _L12C-rows 2 _L12C-continuation
    _L12C-adapter _L12C-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12C-assert
    2 = _L12C-assert
    _L12C-rows LIBPA-RANGE-ROW-RID@
        _L12C-members RID= _L12C-assert
    _L12C-rows LIBPA-RANGE-ROW-ORDER@ 1 = _L12C-assert
    _L12C-rows LIBPA-RANGE-ROW-SIZE +
        LIBPA-RANGE-ROW-RID@
        _L12C-members RID-SIZE + RID= _L12C-assert
    _L12C-rows LIBPA-RANGE-ROW-SIZE +
        LIBPA-RANGE-ROW-ORDER@ 2 = _L12C-assert ;

: _L12C-create-contracts  ( -- )
    _L12C-collection!
    _L12C-collection-out LIBPA-COLLECTION-SIZE 0xA5 FILL
    _L12C-collection _L12C-members 2 2 _L12C-collection-out
        _L12C-adapter _L12C-work
        LIBPA-COLLECTION-CREATE-EXACT
        LIBPA-S-OK _L12C-status
    _L12C-collection _L12C-collection-out
        LIBPA-COLLECTION-SIZE _L12C-bytes= _L12C-assert
    _L12C-work LIBPA-INDEX-LOGICAL-GENERATION@ 3 =
        _L12C-assert
    _L12C-work LIBPA-INDEX-MUTATION-SEQUENCE@ 3 =
        _L12C-assert
    _L12C-work LIBPA-INDEX-COLLECTION-COUNT@ 1 =
        _L12C-assert
    _L12C-work LIBPA-INDEX-MEMBERSHIP-COUNT@ 2 =
        _L12C-assert
    _L12C-store PSTORE-GENERATION@ >R
    _L12C-collection-out LIBPA-COLLECTION-SIZE 0xA5 FILL
    _L12C-collection _L12C-members 2 2 _L12C-collection-out
        _L12C-adapter _L12C-work
        LIBPA-COLLECTION-CREATE-EXACT
        LIBPA-S-OK _L12C-status
    _L12C-store PSTORE-GENERATION@ R> = _L12C-assert
    _L12C-collection _L12C-collection-out
        LIBPA-COLLECTION-SIZE _L12C-bytes= _L12C-assert
    _L12C-collection LIBC.ID _L12C-collection-read
        _L12C-adapter _L12C-work LIBPA-COLLECTION-READ
        LIBPA-S-OK _L12C-status
    _L12C-collection _L12C-collection-read
        LIBPA-COLLECTION-SIZE _L12C-bytes= _L12C-assert
    _L12C-range-two? ;

: _L12C-replace-contracts  ( -- )
    _L12C-members RID-SIZE + _L12C-members-one RID-COPY
    _L12C-collection-out _L12C-collection-next
        LIBPA-COLLECTION-SIZE MOVE
    2 _L12C-collection-next LIBC.REVISION !
    4 _L12C-collection-next LIBC.MUTATION-SEQUENCE !
    1 _L12C-collection-next LIBC.MEMBER-N !
    _L12C-collection-next LIBC.TITLE
        LIB-COLLECTION-TITLE-MAX 0 FILL
    S" Beta" _L12C-collection-next LIBC.TITLE
        _L12C-collection-next LIBC.TITLE-U _L12C-text!
    _L12C-collection-next LIBPA-COLLECTION-VALID? _L12C-assert
    _L12C-collection-next _L12C-members-one 1 3 1
        _L12C-collection-out _L12C-adapter _L12C-work
        LIBPA-COLLECTION-REPLACE-EXACT
        LIBPA-S-OK _L12C-status
    _L12C-collection-next _L12C-collection-out
        LIBPA-COLLECTION-SIZE _L12C-bytes= _L12C-assert
    _L12C-work LIBPA-INDEX-LOGICAL-GENERATION@ 4 =
        _L12C-assert
    _L12C-work LIBPA-INDEX-MUTATION-SEQUENCE@ 4 =
        _L12C-assert
    _L12C-work LIBPA-INDEX-MEMBERSHIP-COUNT@ 1 =
        _L12C-assert
    _L12C-collection-out _L12C-collection-read
        LIBPA-COLLECTION-SIZE MOVE
    LIBPA-RANGE-MEMBERSHIP
    _L12C-collection-out LIBC.ID RID-SIZE
    _L12C-rows 2 _L12C-continuation
    _L12C-adapter _L12C-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12C-assert
    1 = _L12C-assert
    _L12C-rows LIBPA-RANGE-ROW-RID@
        _L12C-members-one RID= _L12C-assert
    _L12C-rows LIBPA-RANGE-ROW-ORDER@ 2 = _L12C-assert ;

: _L12C-invalid-contracts  ( -- )
    _L12C-members _L12C-members-bad RID-COPY
    _L12C-members _L12C-members-bad RID-SIZE + RID-COPY
    _L12C-collection-out _L12C-collection-next
        LIBPA-COLLECTION-SIZE MOVE
    3 _L12C-collection-next LIBC.REVISION !
    5 _L12C-collection-next LIBC.MUTATION-SEQUENCE !
    2 _L12C-collection-next LIBC.MEMBER-N !
    _L12C-collection-out LIBPA-COLLECTION-SIZE 0xA5 FILL
    _L12C-collection-out _L12C-collection-snapshot
        LIBPA-COLLECTION-SIZE MOVE
    _L12C-collection-next _L12C-members-bad 2 4 2
        _L12C-collection-out _L12C-adapter _L12C-work
        LIBPA-COLLECTION-REPLACE-EXACT
        LIBPA-S-INVALID _L12C-status
    _L12C-collection-out _L12C-collection-snapshot
        LIBPA-COLLECTION-SIZE _L12C-bytes= _L12C-assert
    _L12C-work LIBPA-INDEX-LOGICAL-GENERATION@ 4 =
        _L12C-assert

    _L12C-members RID-SIZE + _L12C-members-bad RID-COPY
    _L12C-members _L12C-members-bad RID-SIZE + RID-COPY
    _L12C-collection-next _L12C-members-bad 2 4 2
        _L12C-collection-out _L12C-adapter _L12C-work
        LIBPA-COLLECTION-REPLACE-EXACT
        LIBPA-S-INVALID _L12C-status
    _L12C-work LIBPA-INDEX-LOGICAL-GENERATION@ 4 =
        _L12C-assert ;

: _L12C-unbounded-seal-contract  ( -- )
    _L12C-many-rids RID-SIZE 129 * 0 FILL
    129 0 ?DO
        I 1+ _L12C-many-rids I RID-SIZE * + !
    LOOP
    _L12C-many-collection LIBPA-COLLECTION-INIT
    _L12C-many-collection LIBC.ID RID-CLEAR
    0x81 _L12C-many-collection LIBC.ID !
    _L12C-many-collection LIBC.OPERATION-KEY RID-CLEAR
    0x82 _L12C-many-collection LIBC.OPERATION-KEY !
    1 _L12C-many-collection LIBC.REVISION !
    9 _L12C-many-collection LIBC.MUTATION-SEQUENCE !
    9 _L12C-many-collection LIBC.CREATED-SEQUENCE !
    129 _L12C-many-collection LIBC.MEMBER-N !
    S" Unbounded" _L12C-many-collection LIBC.TITLE
        _L12C-many-collection LIBC.TITLE-U _L12C-text!
    _L12C-many-collection _L12C-many-rids 129
        LIBPA-COLLECTION-REQUEST-SEAL!
        LIBPA-S-OK _L12C-status
    _L12C-many-collection LIBPA-COLLECTION-VALID? _L12C-assert ;

: _L12C-cold-contracts  ( -- )
    _L12C-store-cold _L12C-pwork-cold
        _L12C-buffer-cold _L12C-guard-cold _L12C-store-init
    _L12C-store-cold _L12C-adapter-cold LIBPA-INIT
        LIBPA-S-OK _L12C-status
    _L12C-audit-map-cold _L12C-audit-map-capacity
        _L12C-pwork-cold _L12C-adapter-cold _L12C-work-cold
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12C-status
    _L12C-adapter-cold _L12C-work-cold LIBPA-INDEX-OPEN
        LIBPA-S-OK _L12C-status
    _L12C-collection-read LIBC.ID _L12C-collection-cold
        _L12C-adapter-cold _L12C-work-cold
        LIBPA-COLLECTION-READ LIBPA-S-OK _L12C-status
    _L12C-collection-read _L12C-collection-cold
        LIBPA-COLLECTION-SIZE _L12C-bytes= _L12C-assert
    _L12C-work-cold LIBPA-INDEX-LOGICAL-GENERATION@ 4 =
        _L12C-assert
    _L12C-work-cold LIBPA-INDEX-COLLECTION-COUNT@ 1 =
        _L12C-assert
    _L12C-work-cold LIBPA-INDEX-MEMBERSHIP-COUNT@ 1 =
        _L12C-assert ;

: _L12C-RUN  ( -- )
    DEPTH _L12C-depth !
    0 _L12C-checks !
    0 _L12C-fails !
    _L12C-setup
    _L12C-create-documents
    _L12C-create-contracts
    _L12C-replace-contracts
    _L12C-invalid-contracts
    _L12C-unbounded-seal-contract
    _L12C-cold-contracts
    _L12C-stack
    _L12C-fails @ IF
        ." LIBRARY COLLECTION L12 FAIL "
        _L12C-fails @ . ." / " _L12C-checks @ . CR
    ELSE
        ." LIBRARY COLLECTION L12 PASS "
        _L12C-checks @ . ." assertions" CR
    THEN ;
