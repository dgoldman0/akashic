\ Focused contracts for applet-local canonical Library document values.

PROVIDED akashic-library-document-values-l12-contracts

VARIABLE _LDV12-checks
VARIABLE _LDV12-fails
VARIABLE _LDV12-depth

CREATE _LDV12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-SIZE ALLOT
CREATE _LDV12-metadata-buffer LIBRARY-DOCUMENT-METADATA-SIZE ALLOT
CREATE _LDV12-content-a LIB-CONTENT-SIZE ALLOT
CREATE _LDV12-content-b LIB-CONTENT-SIZE ALLOT
CREATE _LDV12-entry-a LIB-ENTRY-SIZE ALLOT
CREATE _LDV12-entry-b LIB-ENTRY-SIZE ALLOT
CREATE _LDV12-origin LIB-ORIGIN-SIZE ALLOT
LIB-METADATA-FACT-HEADER-SIZE LIB-ORIGIN-SIZE +
    CONSTANT _LDV12-ORIGIN-FACT-U
CREATE _LDV12-origin-fact _LDV12-ORIGIN-FACT-U ALLOT
CREATE _LDV12-data-a 64 ALLOT
CREATE _LDV12-data-b 64 ALLOT

: _LDV12-assert  ( flag -- )
    1 _LDV12-checks +!
    0= IF
        1 _LDV12-fails +!
        ." LIBRARY DOCUMENT VALUES L12 ASSERT " _LDV12-checks @ . CR
    THEN ;

: _LDV12-status  ( actual expected -- )
    2DUP <> IF
        ." DOCUMENT VALUE STATUS actual/expected " 2DUP SWAP . . CR
    THEN
    = _LDV12-assert ;

: _LDV12-stack  ( -- )
    DEPTH _LDV12-depth @ = _LDV12-assert ;

: _LDV12-draft!  ( -- )
    _LDV12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LDV12-draft LSDID.ID RID-CLEAR
    0x41 _LDV12-draft LSDID.ID !
    _LDV12-draft LSDID.OPERATION-KEY RID-CLEAR
    0x51 _LDV12-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _LDV12-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _LDV12-draft LSDID.MEDIA !
    1 _LDV12-draft LSDID.MUTATION-SEQUENCE !
    S" alpha body" _LDV12-data-a SWAP MOVE
    _LDV12-data-a _LDV12-draft LSDID.CONTENT-A !
    10 _LDV12-draft LSDID.CONTENT-U !
    S" Alpha"
    DUP _LDV12-draft LSDID.TITLE-U !
    _LDV12-draft LSDID.TITLE SWAP MOVE ;

: _LDV12-initial  ( -- )
    _LDV12-draft!
    _LDV12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-VALID? _LDV12-assert
    _LDV12-draft _LDV12-entry-a _LDV12-content-a
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-a LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-content-a LIB-CONTENT-VALID? _LDV12-assert
    _LDV12-entry-a LIBE.DOMAIN-REVISION @ 1 = _LDV12-assert
    _LDV12-entry-a LIBE.MUTATION-SEQUENCE @ 1 = _LDV12-assert
    _LDV12-stack ;

: _LDV12-metadata  ( -- )
    _LDV12-entry-a _LDV12-metadata-buffer
        LIBRARY-DOCUMENT-METADATA-FROM-ENTRY
        _LIBDV-S-OK _LDV12-status
    _LDV12-metadata-buffer
        LIBRARY-DOCUMENT-METADATA-VALID? _LDV12-assert
    _LDV12-metadata-buffer LIBDM.TITLE LIB-TITLE-MAX 0 FILL
    S" Beta"
    DUP _LDV12-metadata-buffer LIBDM.TITLE-U !
    _LDV12-metadata-buffer LIBDM.TITLE SWAP MOVE
    _LDV12-entry-a _LDV12-metadata-buffer 2 _LDV12-entry-b
        LIBRARY-SERVICE-PREPARE-METADATA-NEXT
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-b LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-entry-b LIBE.DOMAIN-REVISION @ 2 = _LDV12-assert
    _LDV12-entry-b LIBE.CURRENT-CONTENT-REVISION @ 1 =
        _LDV12-assert
    _LDV12-entry-b LIBE-TITLE$ S" Beta" COMPARE 0= _LDV12-assert
    _LDV12-stack ;

: _LDV12-content  ( -- )
    S" beta body plus" _LDV12-data-b SWAP MOVE
    _LDV12-entry-b _LDV12-data-b 14 3
        _LDV12-entry-a _LDV12-content-b
        LIBRARY-SERVICE-PREPARE-CONTENT-NEXT
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-a LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-content-b LIB-CONTENT-VALID? _LDV12-assert
    _LDV12-entry-a LIBE.DOMAIN-REVISION @ 3 = _LDV12-assert
    _LDV12-entry-a LIBE.CURRENT-CONTENT-REVISION @ 2 =
        _LDV12-assert
    _LDV12-content-b LIBCT.DOMAIN-REVISION @ 3 = _LDV12-assert
    _LDV12-content-b LIBCT.CONTENT-REVISION @ 2 = _LDV12-assert
    _LDV12-stack ;

: _LDV12-lifecycle  ( -- )
    _LDV12-entry-a LIB-LIFECYCLE-ARCHIVED 4 _LDV12-entry-b
        LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-b LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-entry-b LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED =
        _LDV12-assert
    _LDV12-entry-b LIBE.DOMAIN-REVISION @ 4 = _LDV12-assert

    \ Repeating the target state yields the exact current value.
    _LDV12-entry-b LIB-LIFECYCLE-ARCHIVED 5 _LDV12-entry-a
        LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-b LIB-ENTRY-SIZE
        _LDV12-entry-a LIB-ENTRY-SIZE COMPARE 0= _LDV12-assert
    _LDV12-stack ;

: _LDV12-tombstone  ( -- )
    _LDV12-entry-a 5 _LDV12-entry-b
        LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-b LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-entry-b LIBE.LIFECYCLE @ LIB-LIFECYCLE-TOMBSTONED =
        _LDV12-assert
    _LDV12-entry-b LIBE.DOMAIN-REVISION @ 5 = _LDV12-assert
    _LDV12-entry-b LIBE.MUTATION-SEQUENCE @ 5 = _LDV12-assert
    _LDV12-stack ;

: _LDV12-invalid  ( -- )
    \ Output aliases are rejected before any current value is overwritten.
    _LDV12-entry-b _LDV12-data-b 14 6
        _LDV12-entry-b _LDV12-content-b
        LIBRARY-SERVICE-PREPARE-CONTENT-NEXT
        _LIBDV-S-INVALID _LDV12-status
    _LDV12-entry-b LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-stack ;

: _LDV12-capture  ( -- )
    _LDV12-draft!
    LIB-KIND-CAPTURE _LDV12-draft LSDID.KIND !
    9 _LDV12-draft LSDID.MUTATION-SEQUENCE !
    _LDV12-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _LDV12-origin LIBO.KIND !
    S" /document-values/capture.txt" DUP
        _LDV12-origin LIBO.VFS LIBV.PATH-U !
        _LDV12-origin LIBO.VFS LIBV.PATH SWAP MOVE
    _LDV12-data-a 10
        _LDV12-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    10 _LDV12-origin LIBO.VFS LIBV.CONTENT-U !
    QLOC-DK-PROJECTION-CONTENT
        _LDV12-origin LIBO.VFS LIBV.DIGEST-KIND !
    _LDV12-origin LIB-ORIGIN-VALID? _LDV12-assert
    _LDV12-origin-fact _LDV12-ORIGIN-FACT-U 0 FILL
    LIB-METADATA-FACT-ORIGIN
        _LDV12-origin-fact LIBMF.KIND !
    LIB-ORIGIN-SIZE
        _LDV12-origin-fact LIBMF.PAYLOAD-U !
    _LDV12-origin
        _LDV12-origin-fact LIBMF.PAYLOAD
        LIB-ORIGIN-SIZE MOVE
    _LDV12-origin-fact _LDV12-ORIGIN-FACT-U _LDV12-draft
        LIBRARY-DOCUMENT-INITIAL-DRAFT-FACTS!
        _LIBDV-S-OK _LDV12-status
    _LDV12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-VALID? _LDV12-assert
    _LDV12-draft _LDV12-entry-a _LDV12-content-a
        LIBRARY-SERVICE-PREPARE-CAPTURE-IMPORT
        _LIBDV-S-OK _LDV12-status
    _LDV12-entry-a LIB-ENTRY-VALID? _LDV12-assert
    _LDV12-content-a LIB-CONTENT-VALID? _LDV12-assert
    _LDV12-entry-a LIBE.KIND @ LIB-KIND-CAPTURE = _LDV12-assert
    _LDV12-entry-a LIBE.RECEIPT LIBR.METHOD @
        LIB-IMPORT-VFS-SNAPSHOT = _LDV12-assert
    _LDV12-stack ;

: _LDV12-RUN  ( -- )
    0 _LDV12-checks !
    0 _LDV12-fails !
    DEPTH _LDV12-depth !
    _LDV12-initial
    _LDV12-metadata
    _LDV12-content
    _LDV12-lifecycle
    _LDV12-tombstone
    _LDV12-invalid
    _LDV12-capture
    _LDV12-stack
    _LDV12-fails @ IF
        ." LIBRARY DOCUMENT VALUES L12 FAIL " _LDV12-fails @ .
        ." /" _LDV12-checks @ . CR
    ELSE
        ." LIBRARY DOCUMENT VALUES L12 PASS " _LDV12-checks @ . CR
    THEN ;
