\ Focused source contracts for pure canonical Library collection values.

PROVIDED akashic-library-collection-values-l1-contracts

VARIABLE _LCV1-checks
VARIABLE _LCV1-fails
VARIABLE _LCV1-depth

CREATE _LCV1-draft LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE ALLOT
CREATE _LCV1-output LIB-COLLECTION-SIZE ALLOT
CREATE _LCV1-overlap LIB-COLLECTION-SIZE ALLOT
CREATE _LCV1-member-one RID-SIZE ALLOT
CREATE _LCV1-members-two RID-SIZE 2 * ALLOT
CREATE _LCV1-members-64 RID-SIZE 64 * ALLOT
CREATE _LCV1-members-129 RID-SIZE 129 * ALLOT

\ SHA3-256 of the frozen v2 request bytes for title "Alpha" and the two
\ canonical RIDs whose first cells are 0x41 and 0x42.
CREATE _LCV1-known-seal
0x42 C, 0xD0 C, 0xF1 C, 0x94 C, 0x08 C, 0xC1 C, 0x77 C, 0x21 C,
0x5B C, 0xD3 C, 0xB0 C, 0x2A C, 0xE0 C, 0xC6 C, 0x7F C, 0x7B C,
0x62 C, 0xB4 C, 0xAA C, 0xF0 C, 0x09 C, 0x90 C, 0x3B C, 0xAF C,
0x51 C, 0xCA C, 0xEF C, 0xF3 C, 0xBB C, 0x2F C, 0x9C C, 0x1A C,

: _LCV1-assert  ( flag -- )
    1 _LCV1-checks +!
    0= IF
        1 _LCV1-fails +!
        ." LIBRARY COLLECTION VALUES L1 ASSERT " _LCV1-checks @ . CR
    THEN ;

: _LCV1-stack  ( -- )
    DEPTH _LCV1-depth @ = _LCV1-assert ;

: _LCV1-status  ( actual expected -- )
    2DUP <> IF
        ." COLLECTION VALUE STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LCV1-assert _LCV1-stack ;

: _LCV1-zero?  ( address length -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _LCV1-rid!  ( value rid -- )
    DUP RID-CLEAR ! ;

: _LCV1-members!  ( member-rids member-n -- )
    0 ?DO
        DUP I RID-SIZE * + DUP RID-CLEAR
        I 1+ SWAP !
    LOOP
    DROP ;

: _LCV1-title!  ( source-a source-u draft -- )
    >R
    R@ LSCID.TITLE LIB-COLLECTION-TITLE-MAX 0 FILL
    DUP R@ LSCID.TITLE-U !
    R@ LSCID.TITLE SWAP MOVE
    R> DROP ;

: _LCV1-draft!  ( member-rids member-n -- )
    _LCV1-draft LIBRARY-COLLECTION-INITIAL-DRAFT-INIT
    0x31 _LCV1-draft LSCID.ID _LCV1-rid!
    0x51 _LCV1-draft LSCID.OPERATION-KEY _LCV1-rid!
    7 _LCV1-draft LSCID.MUTATION-SEQUENCE !
    DUP _LCV1-draft LSCID.MEMBER-N !
    SWAP _LCV1-draft LSCID.MEMBERS-A !
    DROP
    S" Alpha" _LCV1-draft _LCV1-title! ;

: _LCV1-expect-invalid-clean  ( -- )
    _LCV1-output LIB-COLLECTION-SIZE 0xA5 FILL
    _LCV1-draft _LCV1-output
        LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        _LIBCV-S-INVALID _LCV1-status
    _LCV1-output LIB-COLLECTION-SIZE _LCV1-zero? _LCV1-assert
    _LCV1-stack ;

: _LCV1-output-contract  ( expected-member-n -- )
    _LCV1-output LIB-COLLECTION-VALID? _LCV1-assert
    _LCV1-output LIBC.ID _LCV1-draft LSCID.ID RID= _LCV1-assert
    _LCV1-output LIBC.OPERATION-KEY
        _LCV1-draft LSCID.OPERATION-KEY RID= _LCV1-assert
    _LCV1-output LIBC.REVISION @ 1 = _LCV1-assert
    _LCV1-output LIBC.MUTATION-SEQUENCE @ 7 = _LCV1-assert
    _LCV1-output LIBC.CREATED-SEQUENCE @ 7 = _LCV1-assert
    _LCV1-output LIBC.MEMBER-N @ OVER = _LCV1-assert
    _LCV1-output LIBC-TITLE$ S" Alpha" COMPARE 0= _LCV1-assert
    _LCV1-output LIBC.FLAGS @ 0= _LCV1-assert
    _LCV1-output LIBC.RESERVED 8 _LCV1-zero? _LCV1-assert
    _LCV1-output _LCV1-draft LSCID-MEMBERS
        LIBRARY-COLLECTION-REQUEST-MATCHES? _LCV1-assert
    DROP _LCV1-stack ;

: _LCV1-prepare-ok  ( member-rids member-n -- )
    DUP >R _LCV1-draft!
    _LCV1-output LIB-COLLECTION-SIZE 0xA5 FILL
    _LCV1-draft _LCV1-output
        LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        _LIBCV-S-OK _LCV1-status
    R> _LCV1-output-contract ;

: _LCV1-cardinalities  ( -- )
    0 0 _LCV1-prepare-ok
    _LCV1-member-one 1 _LCV1-prepare-ok
    _LCV1-members-64 64 _LCV1-prepare-ok
    _LCV1-members-129 129 _LCV1-prepare-ok
    _LCV1-stack ;

: _LCV1-compatible-seal  ( -- )
    0x41 _LCV1-members-two _LCV1-rid!
    0x42 _LCV1-members-two RID-SIZE + _LCV1-rid!
    _LCV1-members-two 2 _LCV1-prepare-ok
    _LCV1-output LIBC.REQUEST-SEAL
        LIB-DIGEST-SIZE _LCV1-known-seal LIB-DIGEST-SIZE
        COMPARE 0= _LCV1-assert
    _LCV1-output _LCV1-members-two 1
        LIBRARY-COLLECTION-REQUEST-MATCHES? 0= _LCV1-assert
    _LCV1-stack ;

: _LCV1-canonicality  ( -- )
    0 0 LIBRARY-COLLECTION-MEMBERS-CANONICAL? _LCV1-assert
    _LCV1-members-two 2 _LCV1-members!
    _LCV1-members-two 2
        LIBRARY-COLLECTION-MEMBERS-CANONICAL? _LCV1-assert

    \ Zero RIDs, duplicates, and descending byte order are all rejected.
    _LCV1-members-two RID-CLEAR
    _LCV1-members-two 2 _LCV1-draft!
    _LCV1-expect-invalid-clean

    _LCV1-members-two 2 _LCV1-members!
    _LCV1-members-two
        _LCV1-members-two RID-SIZE + RID-COPY
    _LCV1-members-two 2 _LCV1-draft!
    _LCV1-expect-invalid-clean

    _LCV1-members-two 2 _LCV1-members!
    2 _LCV1-members-two !
    1 _LCV1-members-two RID-SIZE + !
    _LCV1-members-two 2 _LCV1-draft!
    _LCV1-expect-invalid-clean

    \ Counts are caller-sized but must fit exact signed-cell RID arithmetic.
    _LCV1-member-one -1 _LCV1-draft!
    _LCV1-expect-invalid-clean
    _LCV1-member-one _LIBCV-MAX-SIGNED RID-SIZE / 1+ _LCV1-draft!
    _LCV1-expect-invalid-clean
    _LCV1-stack ;

: _LCV1-title-contracts  ( -- )
    _LCV1-member-one 1 _LCV1-draft!
    0 _LCV1-draft LSCID.TITLE-U !
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    LIB-COLLECTION-TITLE-MAX 1+ _LCV1-draft LSCID.TITLE-U !
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    _LCV1-draft LSCID.TITLE LIB-COLLECTION-TITLE-MAX 0 FILL
    0xC0 _LCV1-draft LSCID.TITLE C!
    1 _LCV1-draft LSCID.TITLE-U !
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    1 _LCV1-draft LSCID.TITLE 5 + C!
    _LCV1-expect-invalid-clean

    \ A valid two-byte UTF-8 title is copied without reinterpretation.
    _LCV1-member-one 1 _LCV1-draft!
    _LCV1-draft LSCID.TITLE LIB-COLLECTION-TITLE-MAX 0 FILL
    0xC3 _LCV1-draft LSCID.TITLE C!
    0xA9 _LCV1-draft LSCID.TITLE 1+ C!
    2 _LCV1-draft LSCID.TITLE-U !
    _LCV1-draft _LCV1-output
        LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        _LIBCV-S-OK _LCV1-status
    _LCV1-output LIBC.TITLE-U @ 2 = _LCV1-assert
    _LCV1-output LIBC.TITLE 2 UTF8-VALID? _LCV1-assert
    _LCV1-stack ;

: _LCV1-identity-and-sequence  ( -- )
    _LCV1-member-one 1 _LCV1-draft!
    _LCV1-draft LSCID.ID RID-CLEAR
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    _LCV1-draft LSCID.OPERATION-KEY RID-CLEAR
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    _LCV1-draft LSCID.ID
        _LCV1-draft LSCID.OPERATION-KEY RID-COPY
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    0 _LCV1-draft LSCID.MUTATION-SEQUENCE !
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    -1 _LCV1-draft LSCID.MUTATION-SEQUENCE !
    _LCV1-expect-invalid-clean

    _LCV1-member-one 1 _LCV1-draft!
    _LIBCV-MAX-SIGNED _LCV1-draft LSCID.MUTATION-SEQUENCE !
    _LCV1-draft _LCV1-output
        LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        _LIBCV-S-OK _LCV1-status
    _LCV1-output LIBC.MUTATION-SEQUENCE @
        _LIBCV-MAX-SIGNED = _LCV1-assert
    _LCV1-output LIBC.CREATED-SEQUENCE @
        _LIBCV-MAX-SIGNED = _LCV1-assert
    _LCV1-stack ;

: _LCV1-span-and-overlap  ( -- )
    \ Null and wrapping nonempty member spans fail before dereference.
    0 1 _LCV1-draft!
    _LCV1-expect-invalid-clean
    -16 1 _LCV1-draft!
    _LCV1-expect-invalid-clean

    \ Borrowed membership may not alias its draft or its destination.
    _LCV1-draft LSCID.ID 1 _LCV1-draft!
    _LCV1-expect-invalid-clean
    _LCV1-output 1 _LCV1-draft!
    _LCV1-expect-invalid-clean

    \ An aliased destination is still left as one clean collection span.
    _LCV1-member-one 1 _LCV1-draft!
    _LCV1-draft _LCV1-overlap
        LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE MOVE
    _LCV1-overlap _LCV1-overlap
        LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        _LIBCV-S-INVALID _LCV1-status
    _LCV1-overlap LIB-COLLECTION-SIZE _LCV1-zero? _LCV1-assert

    \ A null draft also leaves an otherwise valid destination clean.
    _LCV1-output LIB-COLLECTION-SIZE 0xA5 FILL
    0 _LCV1-output LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
        _LIBCV-S-INVALID _LCV1-status
    _LCV1-output LIB-COLLECTION-SIZE _LCV1-zero? _LCV1-assert
    _LCV1-stack ;

: _LCV1-RUN  ( -- )
    0 _LCV1-checks !
    0 _LCV1-fails !
    DEPTH _LCV1-depth !
    _LCV1-member-one 1 _LCV1-members!
    _LCV1-members-64 64 _LCV1-members!
    _LCV1-members-129 129 _LCV1-members!
    _LCV1-cardinalities
    _LCV1-compatible-seal
    _LCV1-canonicality
    _LCV1-title-contracts
    _LCV1-identity-and-sequence
    _LCV1-span-and-overlap
    _LCV1-stack
    _LCV1-fails @ IF
        ." LIBRARY COLLECTION VALUES L1 FAIL " _LCV1-fails @ .
        ." /" _LCV1-checks @ . CR
    ELSE
        ." LIBRARY COLLECTION VALUES L1 PASS " _LCV1-checks @ . CR
    THEN ;
