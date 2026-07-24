\ Focused fresh-dictionary contracts for the reentrant L12 Library model.

PROVIDED akashic-library-model-l12-contracts

VARIABLE _L12M-checks
VARIABLE _L12M-fails
VARIABLE _L12M-depth

CREATE _L12M-source 64 ALLOT
CREATE _L12M-digest SHA3-256-LEN ALLOT
CREATE _L12M-digest-after SHA3-256-LEN ALLOT
CREATE _L12M-content-a LIB-CONTENT-SIZE ALLOT
CREATE _L12M-content-b LIB-CONTENT-SIZE ALLOT
CREATE _L12M-entry-a LIB-ENTRY-SIZE ALLOT
CREATE _L12M-entry-b LIB-ENTRY-SIZE ALLOT
CREATE _L12M-collection-a LIB-COLLECTION-SIZE ALLOT
CREATE _L12M-collection-b LIB-COLLECTION-SIZE ALLOT

: _L12M-assert  ( flag -- )
    1 _L12M-checks +!
    0= IF
        1 _L12M-fails +!
        ." LIBRARY MODEL L12 ASSERT " _L12M-checks @ . CR
    THEN ;

: _L12M-status  ( actual expected -- )
    2DUP <> IF
        ." MODEL STATUS actual/expected " 2DUP SWAP . . CR
    THEN
    = _L12M-assert ;

: _L12M-stack  ( -- )
    DEPTH _L12M-depth @ = _L12M-assert ;

: _L12M-text!  ( source-a source-u destination length-cell -- )
    >R OVER R@ ! SWAP MOVE R> DROP ;

: _L12M-content!  ( -- )
    _L12M-source 64 0 FILL
    S" abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        _L12M-source SWAP MOVE
    _L12M-content-a LIB-CONTENT-INIT
    _L12M-content-a LIBCT.ID RID-CLEAR
    0x41 _L12M-content-a LIBCT.ID !
    1 _L12M-content-a LIBCT.DOMAIN-REVISION !
    1 _L12M-content-a LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12M-content-a LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _L12M-content-a LIBCT.MEDIA !
    _L12M-source _L12M-content-a LIBCT.DATA-A !
    40 _L12M-content-a LIBCT.DATA-U !
    _L12M-content-a LIB-CONTENT-DIGEST! LIB-S-OK _L12M-status
    _L12M-content-a _L12M-content-b LIB-CONTENT-SIZE MOVE
    0x42 _L12M-content-b LIBCT.ID ! ;

: _L12M-entry!  ( -- )
    _L12M-entry-a LIB-ENTRY-INIT
    _L12M-entry-a LIBE.ID RID-CLEAR
    0x41 _L12M-entry-a LIBE.ID !
    1 _L12M-entry-a LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12M-entry-a LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _L12M-entry-a LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _L12M-entry-a LIBE.MEDIA !
    1 _L12M-entry-a LIBE.CURRENT-CONTENT-REVISION !
    1 _L12M-entry-a LIBE.OLDEST-CONTENT-REVISION !
    40 _L12M-entry-a LIBE.CONTENT-U !
    _L12M-content-a LIBCT.DIGEST
        _L12M-entry-a LIBE.CONTENT-DIGEST RID-COPY
    1 _L12M-entry-a LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12M-entry-a LIBE.CREATED-CLOCK !
    1 _L12M-entry-a LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12M-entry-a LIBE.MODIFIED-CLOCK !
    1 _L12M-entry-a LIBE.MODIFIED-VALUE !
    S" First note"
        _L12M-entry-a LIBE.TITLE _L12M-entry-a LIBE.TITLE-U _L12M-text!
    0 0 _L12M-entry-a LIBE.METADATA-DIGEST SHA3-256-HASH
    _L12M-entry-a LIBE.RECEIPT DUP LIB-RECEIPT-INIT
    DUP LIBR.OPERATION-KEY RID-CLEAR
    0x51 OVER LIBR.OPERATION-KEY !
    LIB-IMPORT-CREATED OVER LIBR.METHOD !
    1 OVER LIBR.INITIAL-CONTENT-REVISION !
    40 OVER LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN OVER LIBR.INITIAL-MEDIA !
    _L12M-entry-a LIBE.CONTENT-DIGEST
        OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
    DROP
    _L12M-entry-a LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _L12M-status
    _L12M-entry-a _L12M-entry-b LIB-ENTRY-SIZE MOVE
    0x42 _L12M-entry-b LIBE.ID !
    0x52 _L12M-entry-b LIBE.RECEIPT LIBR.OPERATION-KEY ! ;

: _L12M-collection-one!  ( id operation collection -- )
    >R
    R@ LIB-COLLECTION-INIT
    R@ LIBC.ID RID-CLEAR
    R@ LIBC.OPERATION-KEY RID-CLEAR
    SWAP R@ LIBC.ID !
    R@ LIBC.OPERATION-KEY !
    1 R@ LIBC.REVISION !
    1 R@ LIBC.MUTATION-SEQUENCE !
    1 R@ LIBC.CREATED-SEQUENCE !
    S" Alpha" DUP R@ LIBC.TITLE-U !
    R@ LIBC.TITLE SWAP MOVE
    R@ LIBC.REQUEST-SEAL RID-CLEAR
    0x61 R@ LIBC.REQUEST-SEAL !
    R> DROP ;

: _L12M-collections!  ( -- )
    0x11 0x21 _L12M-collection-a _L12M-collection-one!
    0x12 0x22 _L12M-collection-b _L12M-collection-one! ;

\ Caller context remains live on the return stack through every nested model
\ validation.  The three validators must neither depend upon nor overwrite a
\ shared model scratch owner.
: _L12M-VALIDATE-TRIPLE  ( entry content collection -- flag )
    >R >R
    LIB-ENTRY-VALID?
    R> LIB-CONTENT-VALID? AND
    R> LIB-COLLECTION-VALID? AND ;

: _L12M-sha-unowned-end  ( -- )
    _L12M-digest SHA3-256-END-COMPARE DROP ;

: _L12M-sha-contracts  ( -- )
    _L12M-source 40 _L12M-digest SHA3-256-HASH
    _L12M-source 40 _L12M-digest
        SHA3-256-HASH-COMPARE _L12M-assert
    1 _L12M-digest C@ XOR _L12M-digest C!
    _L12M-source 40 _L12M-digest
        SHA3-256-HASH-COMPARE 0= _L12M-assert
    1 _L12M-digest C@ XOR _L12M-digest C!

    SHA3-256-BEGIN
    _L12M-source 17 SHA3-256-ADD
    _L12M-source 17 + 23 SHA3-256-ADD
    _L12M-digest SHA3-256-END-COMPARE _L12M-assert

    1 _L12M-digest C@ XOR _L12M-digest C!
    SHA3-256-BEGIN
    _L12M-source 40 SHA3-256-ADD
    _L12M-digest SHA3-256-END-COMPARE 0= _L12M-assert
    1 _L12M-digest C@ XOR _L12M-digest C!
    \ A normal one-shot operation immediately after mismatch proves release.
    _L12M-source 40 _L12M-digest
        SHA3-256-HASH-COMPARE _L12M-assert

    ['] _L12M-sha-unowned-end CATCH -258 = _L12M-assert
    \ The ownership THROW path must not poison the next guarded operation.
    _L12M-source 40 _L12M-digest-after SHA3-256-HASH
    _L12M-digest _L12M-digest-after SHA3-256-COMPARE _L12M-assert ;

: _L12M-model-contracts  ( -- )
    _L12M-content!
    _L12M-source 40 UTF8-VALID? _L12M-assert
    _L12M-content-a _LIBM-CONTENT-SHAPE? _L12M-assert
    _L12M-entry!
    _L12M-collections!
    _L12M-entry-a _L12M-content-a _L12M-collection-a
        _L12M-VALIDATE-TRIPLE _L12M-assert
    _L12M-entry-b _L12M-content-b _L12M-collection-b
        _L12M-VALIDATE-TRIPLE _L12M-assert

    \ Interleave independent owners and prove a damaged A never poisons B.
    _L12M-entry-a LIB-ENTRY-VALID? _L12M-assert
    _L12M-content-b LIB-CONTENT-VALID? _L12M-assert
    _L12M-collection-a LIB-COLLECTION-VALID? _L12M-assert
    1 _L12M-content-a LIBCT.DIGEST C@ XOR
        _L12M-content-a LIBCT.DIGEST C!
    _L12M-content-a LIB-CONTENT-VALID? 0= _L12M-assert
    _L12M-entry-b LIB-ENTRY-VALID? _L12M-assert
    _L12M-collection-b LIB-COLLECTION-VALID? _L12M-assert
    1 _L12M-content-a LIBCT.DIGEST C@ XOR
        _L12M-content-a LIBCT.DIGEST C!
    _L12M-content-a LIB-CONTENT-VALID? _L12M-assert
    _L12M-entry-a LIB-ENTRY-VALID? _L12M-assert ;

: _L12M-RUN  ( -- )
    0 _L12M-checks !
    0 _L12M-fails !
    DEPTH _L12M-depth !
    _L12M-sha-contracts
    _L12M-model-contracts
    _L12M-stack
    _L12M-fails @ IF
        ." LIBRARY MODEL L12 FAIL " _L12M-fails @ .
        ." /" _L12M-checks @ . CR
    ELSE
        ." LIBRARY MODEL L12 PASS " _L12M-checks @ . CR
    THEN ;
