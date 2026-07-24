\ Disposable public-service scale contracts for L12 collection membership.
\
\ The ordinary service and adapter gates create complete documents and prove
\ every document secondary index.  Repeating those unrelated index mutations
\ 127 times here would dominate the emulator before the operation under test
\ begins.  This fixture therefore builds valid, fully decodable current
\ document records and only the RID-directory references consumed by
\ collection membership validation.  These are membership-target stubs, not
\ a valid complete catalog: they are neither counted as documents nor exposed
\ to any other query, and the entire repository is destroyed after this run.
\ No production surface accepts or constructs this narrow fixture shape.

PROVIDED akashic-library-svc-scale-l12-contracts

REQUIRE lib-repo-l12-test.f
REQUIRE lib-service-l12-test.f

LIB-ENTRY-SIZE XBUF _LS12S-entry
LIB-CONTENT-SIZE XBUF _LS12S-content
LIB-ENTRY-SIZE XBUF _LS12S-result
VARIABLE _LS12S-id
VARIABLE _LS12S-mutation
VARIABLE _LS12S-next-before
VARIABLE _LS12S-adapter
VARIABLE _LS12S-index

LIBPA-RANGE-ROW-SIZE 128 * XBUF _LS12S-membership-rows
LIBPA-RANGE-ROW-SIZE XBUF _LS12S-membership-tail
LIBPA-CONTINUATION-SIZE XBUF _LS12S-membership-continuation
VARIABLE _LS12S-membership-first-n
VARIABLE _LS12S-membership-tail-n

: _LS12S-value!  ( id mutation -- status )
    _LS12S-mutation !
    _LS12S-id !
    _LS12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LS12-draft LSDID.ID RID-CLEAR
    _LS12S-id @ _LS12-draft LSDID.ID !
    _LS12-draft LSDID.OPERATION-KEY RID-CLEAR
    _LS12S-id @ 0x200000 +
        _LS12-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _LS12-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _LS12-draft LSDID.MEDIA !
    _LS12S-mutation @ _LS12-draft LSDID.MUTATION-SEQUENCE !
    0 _LS12-draft LSDID.CONTENT-A !
    0 _LS12-draft LSDID.CONTENT-U !
    S" Scale member" _LS12-draft LSDID.TITLE
        _LS12-draft LSDID.TITLE-U _LS12-text!
    _LS12-draft _LS12S-entry _LS12S-content
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE ;

: _LS12S-create-one  ( id -- )
    _LS12S-id !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12S-mutation !
    _LS12S-id @ _LS12S-mutation @ _LS12S-value!
        LIBRARY-SERVICE-S-OK _LS12-status

    _LS12-create-request LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _LS12S-entry _LS12-create-request LSDCR.ENTRY !
    _LS12S-content _LS12-create-request LSDCR.CONTENT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-create-request LSDCR.EXPECTED-LOGICAL !
    _LS12S-result _LS12-create-request LSDCR.RESULT !
    _LS12-create-request
        LIBRARY-DOCUMENT-CREATE-REQUEST-VALID? _LS12-assert
    _LS12-create-request _LS12-service _LS12-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12S-result _LS12S-entry _LS12-entry= _LS12-assert
    _LS12-stack ;

: _LS12S-create-complete-baseline  ( -- )
    1 _LS12S-create-one
    2 _LS12S-create-one
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        2 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        2 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        3 = _LS12-assert
    _LS12-stack ;

: _LS12S-create-collection  ( -- )
    _LS12-collection-initial!
    _LS12-collection-request _LS12-service _LS12-work
        LIBRARY-SERVICE-CREATE-COLLECTION
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-collection-result _LS12-many-collection
        _LS12-collection= _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-COLLECTION-COUNT@
        1 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        2 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        2 = _LS12-assert
    1 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-collection-read _LS12-collection-result
        _LS12-collection= _LS12-assert
    _LS12-stack ;

: _LS12S-stub-stage-one  ( index-work -- status )
    >R
    _LS12S-entry R@ _LIBPIX.ENTRY-ARG !
    _LS12S-content R@ _LIBPIX.CONTENT-ARG !
    0 R@ _LIBPIX.FACTS-A !
    0 R@ _LIBPIX.FACTS-U !
    _LS12S-result R@ _LIBPIX.OUTPUT-ARG !
    R@ _LIBPIX-DOCUMENT-CREATE-ARGS? 0= IF
        R> DROP LIBPA-S-INVALID EXIT
    THEN
    R@ _LIBPIX-METADATA-VALIDATE
    DUP IF R> DROP EXIT THEN DROP
    R@ _LIBPIX-DOCUMENT-BLOB-STAGE
    DUP IF R> DROP EXIT THEN DROP

    \ Membership validation loads only the current document record through
    \ this root.  Deliberately do not populate or count any other document
    \ index: those invariants belong to the complete baseline gates.
    _LS12S-entry LIBE.ID R@ _LIBPIX.KEY0 LIBPI-RID-KEY
    DUP IF _LIBPA-LIB>STATUS R> DROP EXIT THEN DROP
    R@ _LIBPIX.KEY0 LIBPI-RID-KEY-SIZE
    R@ _LIBPIX.RECORD-REF PERSIST-REF-SIZE
    _LIBPIX-RID-DIRECTORY R@ _LIBPIX-PUT-STAGED
    R> DROP ;

: _LS12S-stub-seed-run  ( index-work -- status )
    _LS12S-index !
    _LS12S-index @ _LIBPIX-READY? 0= IF
        LIBPA-S-BUSY EXIT
    THEN
    _LS12S-index @ _LIBPIX.MUTATION-SEQUENCE @
        DUP 0> 0= IF DROP LIBPA-S-CORRUPT EXIT THEN
        _LS12S-mutation !
    _LS12S-index @ _LIBPIX-STAGE-BEGIN
    DUP IF EXIT THEN DROP
    3 _LS12S-id !
    BEGIN
        _LS12S-id @ 130 <
    WHILE
        _LS12S-id @ _LS12S-mutation @ _LS12S-value!
        DUP IF EXIT THEN DROP
        _LS12S-index @ _LS12S-stub-stage-one
        DUP IF EXIT THEN DROP
        1 _LS12S-id +!
    REPEAT
    \ Publish the scale fixture as one logical setup step without advancing
    \ Library's mutation sequence or document count.
    _LS12S-index @ _LIBPIX-STAGE-FINAL-PUBLISH ;

: _LS12S-stub-seed-owner
  ( context repository repository-work -- repository-status )
    DUP LIBRARY-REPOSITORY-INDEX-WORK@ _LS12S-index !
    OVER LIBRARY-REPOSITORY-ADAPTER@ _LS12S-adapter !
    2DROP DROP
    _LS12S-adapter @ _LS12S-index @ _LIBPIX-ENTER
    DUP IF EXIT THEN DROP
    _LS12S-index @ ['] _LS12S-stub-seed-run
        _LIBPIX-WORK-CATCH
    _LS12S-index @ _LIBPIX-STAGE-DISCARD
    _LS12S-adapter @ _LS12S-index @ _LIBPIX-LEAVE ;

: _LS12S-seed-membership-targets  ( -- )
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12S-next-before !
    1 ['] _LS12S-stub-seed-owner
        _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-OK _LS12-status
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ 1+ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12S-next-before @ = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        2 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-COLLECTION-COUNT@
        1 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        2 = _LS12-assert
    _LS12-stack ;

: _LS12S-membership-read-owner
  ( context repository repository-work -- repository-status )
    DUP LIBRARY-REPOSITORY-INDEX-WORK@ _LS12S-index !
    OVER LIBRARY-REPOSITORY-ADAPTER@ _LS12S-adapter !
    2DROP DROP
    LIBPA-RANGE-MEMBERSHIP
    _LS12-collection-result LIBC.ID RID-SIZE
    _LS12S-membership-rows 128 _LS12S-membership-continuation
    _LS12S-adapter @ _LS12S-index @ LIBPA-RANGE-FIRST
    DUP IF NIP EXIT THEN
    DROP _LS12S-membership-first-n !
    LIBPA-RANGE-MEMBERSHIP
    _LS12-collection-result LIBC.ID RID-SIZE
    _LS12S-membership-tail 1 _LS12S-membership-continuation
    _LS12S-adapter @ _LS12S-index @ LIBPA-RANGE-AFTER
    DUP IF NIP EXIT THEN
    DROP _LS12S-membership-tail-n !
    LIBRARY-REPOSITORY-S-OK ;

: _LS12S-membership-boundary  ( -- )
    1 ['] _LS12S-membership-read-owner
        _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-OK _LS12-status
    _LS12S-membership-first-n @ 128 = _LS12-assert
    _LS12S-membership-tail-n @ 1 = _LS12-assert
    _LS12S-membership-rows LIBPA-RANGE-ROW-RID@
        _LS12-many-rids RID= _LS12-assert
    _LS12S-membership-rows 127 LIBPA-RANGE-ROW-SIZE * +
        LIBPA-RANGE-ROW-RID@
        _LS12-many-rids 127 RID-SIZE * + RID= _LS12-assert
    _LS12S-membership-tail LIBPA-RANGE-ROW-RID@
        _LS12-many-rids 128 RID-SIZE * + RID= _LS12-assert
    _LS12-stack ;

: _LS12S-replace-over-one-batch  ( -- )
    _LS12-many-rids RID-SIZE 129 * 0 FILL
    129 0 ?DO
        I 1+ _LS12-many-rids I RID-SIZE * + !
    LOOP
    _LS12S-seed-membership-targets

    _LS12-collection-result _LS12-many-collection
        LIBPA-COLLECTION-SIZE MOVE
    2 _LS12-many-collection LIBC.REVISION !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-many-collection LIBC.MUTATION-SEQUENCE !
    129 _LS12-many-collection LIBC.MEMBER-N !
    S" Collection beyond one batch"
        _LS12-many-collection LIBC.TITLE
        _LS12-many-collection LIBC.TITLE-U _LS12-text!
    _LS12-many-collection LIBPA-COLLECTION-VALID? _LS12-assert

    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-collection-request LIBRARY-COLLECTION-WRITE-REQUEST-INIT
    _LS12-many-collection
        _LS12-collection-request LSCWR.COLLECTION !
    _LS12-many-rids _LS12-collection-request LSCWR.MEMBERS !
    129 _LS12-collection-request LSCWR.MEMBER-N !
    _LS12-logical-before @
        _LS12-collection-request LSCWR.EXPECTED-LOGICAL !
    1 _LS12-collection-request LSCWR.EXPECTED-REVISION !
    _LS12-collection-result _LS12-collection-request LSCWR.RESULT !
    _LS12-collection-request
        LIBRARY-COLLECTION-WRITE-REQUEST-VALID? _LS12-assert
    _LS12-collection-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPLACE-COLLECTION
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-collection-result LIBC.REVISION @ 2 = _LS12-assert
    _LS12-collection-result LIBC.MEMBER-N @ 129 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        129 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        2 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ 1+ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-many-collection LIBC.MUTATION-SEQUENCE @
        1+ = _LS12-assert
    2 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-collection-read LIBC.MEMBER-N @ 129 = _LS12-assert
    _LS12S-membership-boundary

    _LS12-many-collection LIBC.OPERATION-KEY
    LIBPA-OPERATION-COLLECTION _LS12-many-collection LIBC.ID
        _LS12-operation=
    _LS12-stack ;

: _LS12S-RUN  ( -- )
    0 _LS12-fails !
    0 _LS12-checks !
    0 _LR12-fails !
    0 _LR12-checks !
    DEPTH _LS12-depth !
    DEPTH _LR12-depth !

    _LR12-runtime-init
    _LR12-repository-a-init
    _LS12-repository-ready
    101 _LS12-progress
    _LS12-service-init
    _LS12S-create-complete-baseline
    102 _LS12-progress
    _LS12S-create-collection
    103 _LS12-progress
    _LS12S-replace-over-one-batch
    104 _LS12-progress
    _LS12-finalizers
    _LR12-finish

    _LR12-fails @ IF 1 _LS12-fails +! THEN
    _LS12-fails @ IF
        ." LIBRARY SERVICE SCALE L12 FAIL "
        _LS12-fails @ . ." /" _LS12-checks @ . CR
    ELSE
        ." LIBRARY SERVICE SCALE L12 PASS "
        _LS12-checks @ . CR
    THEN ;
