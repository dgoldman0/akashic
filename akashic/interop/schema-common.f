\ =====================================================================
\  schema-common.f - Caller-owned scalar and locator schema shapes
\ =====================================================================
\  Every word initializes storage supplied by its caller.  This module
\  deliberately owns no mutable schema instance and encodes no domain map,
\  paging shape, or locator resolution policy.
\ =====================================================================

PROVIDED akashic-interop-schema-common

REQUIRE schema.f
REQUIRE resource.f

IRES-RREF-URI-MAX CONSTANT CSC-RREF-TEXT-MAX
512 4 + CONSTANT CSC-VFS-LOCATOR-TEXT-MAX

: CSC-NULL!  ( schema -- )
    DUP CS-INIT CV-T-NULL SWAP CS-ALLOW! ;

: CSC-BOOL!  ( schema -- )
    DUP CS-INIT CV-T-BOOL SWAP CS-ALLOW! ;

: CSC-NONNEG-INT!  ( schema -- )
    DUP CS-INIT
    DUP CV-T-INT SWAP CS-ALLOW!
    0 SWAP CS-MIN! ;

: CSC-POSITIVE-REVISION!  ( schema -- )
    DUP CS-INIT
    DUP CV-T-INT SWAP CS-ALLOW!
    1 SWAP CS-MIN! ;

: CSC-UTF8!  ( max-length schema -- )
    DUP CS-INIT
    DUP CV-T-STRING SWAP CS-ALLOW!
    CS-MAX-LEN! ;

: CSC-SEMANTIC-RREF!  ( schema -- )
    DUP CS-INIT
    DUP CV-T-RESOURCE SWAP CS-ALLOW!
    CSC-RREF-TEXT-MAX SWAP CS-MAX-LEN! ;

: CSC-OPTIONAL-SEMANTIC-RREF!  ( schema -- )
    DUP CS-INIT
    DUP CV-T-NULL CS-TYPE-BIT CV-T-RESOURCE CS-TYPE-BIT OR
        SWAP CS-ALLOW-MASK!
    CSC-RREF-TEXT-MAX SWAP CS-MAX-LEN! ;

: CSC-RREF-TEXT!  ( schema -- )
    CSC-RREF-TEXT-MAX SWAP CSC-UTF8! ;

: CSC-VFS-LOCATOR-TEXT!  ( schema -- )
    CSC-VFS-LOCATOR-TEXT-MAX SWAP CSC-UTF8! ;
