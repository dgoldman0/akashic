\ =====================================================================
\  collection-values.f - Canonical Desk/Library collection preparation
\ =====================================================================
\  These caller-owned values are Library-domain inputs, not persistence
\  records.  This module owns initial collection shape, canonical membership,
\  and the durable v2 create-request seal so callers never manufacture a
\  sealed LIB-COLLECTION themselves.
\
\  The module is applet-local and stateless.  It performs no repository,
\  storage, VFS, query, controller, or UI operation.  Membership is bounded
\  only by the caller-owned span and signed-cell arithmetic; interface-level
\  request limits belong to their respective callers.
\ =====================================================================

PROVIDED akashic-tui-library-collection-values

REQUIRE model.f

\ These results intentionally match the service/repository OK and INVALID
\ values.  They remain private so this pure value module does not acquire a
\ dependency on the physical persistence owner.
0 CONSTANT _LIBCV-S-OK
2 CONSTANT _LIBCV-S-INVALID
-1 1 RSHIFT CONSTANT _LIBCV-MAX-SIGNED

: _LIBCV-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;

: _LIBCV-SPAN?  ( address length -- flag )
    OVER 0= IF NIP 0= EXIT THEN
    MSPAN-NONWRAPPING? ;

: _LIBCV-ZERO?  ( address length -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _LIBCV-TEXT-SLOT?  ( address capacity length allow-empty? -- flag )
    >R
    DUP 0< IF DROP 2DROP R> DROP 0 EXIT THEN
    DUP 2 PICK > IF DROP 2DROP R> DROP 0 EXIT THEN
    DUP 0= R@ 0= AND IF DROP 2DROP R> DROP 0 EXIT THEN
    DUP IF
        2 PICK OVER UTF8-VALID? 0= IF
            DROP 2DROP R> DROP 0 EXIT
        THEN
    THEN
    TUCK - >R + R> _LIBCV-ZERO?
    R> DROP ;

\ ---------------------------------------------------------------------
\ Initial collection draft
\ ---------------------------------------------------------------------

  0 CONSTANT _LSCID-ID
 32 CONSTANT _LSCID-OPERATION-KEY
 64 CONSTANT _LSCID-MUTATION-SEQUENCE
 72 CONSTANT _LSCID-MEMBERS-A
 80 CONSTANT _LSCID-MEMBER-N
 88 CONSTANT _LSCID-TITLE-U
 96 CONSTANT _LSCID-TITLE
160 CONSTANT LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE

: LSCID.ID                 ( draft -- rid ) _LSCID-ID + ;
: LSCID.OPERATION-KEY      ( draft -- rid ) _LSCID-OPERATION-KEY + ;
: LSCID.MUTATION-SEQUENCE  ( draft -- a ) _LSCID-MUTATION-SEQUENCE + ;
: LSCID.MEMBERS-A          ( draft -- a ) _LSCID-MEMBERS-A + ;
: LSCID.MEMBER-N           ( draft -- a ) _LSCID-MEMBER-N + ;
: LSCID.TITLE-U            ( draft -- a ) _LSCID-TITLE-U + ;
: LSCID.TITLE              ( draft -- a ) _LSCID-TITLE + ;

: LSCID-TITLE$  ( draft -- a u )
    DUP LSCID.TITLE SWAP LSCID.TITLE-U @ ;

: LSCID-MEMBERS  ( draft -- member-rids member-n )
    DUP LSCID.MEMBERS-A @ SWAP LSCID.MEMBER-N @ ;

: LIBRARY-COLLECTION-INITIAL-DRAFT-INIT  ( draft -- )
    LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE 0 FILL ;

: LIBRARY-COLLECTION-MEMBERS-CANONICAL?
  ( member-rids member-n -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP _LIBCV-MAX-SIGNED RID-SIZE / > IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP RID-SIZE * MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    DUP 0 ?DO
        OVER I RID-SIZE * + RID-PRESENT? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
        I IF
            OVER I 1- RID-SIZE * + RID-SIZE
            3 PICK I RID-SIZE * + RID-SIZE
            COMPARE 0< 0= IF
                2DROP 0 UNLOOP EXIT
            THEN
        THEN
    LOOP
    2DROP -1 ;

: LIBRARY-COLLECTION-INITIAL-DRAFT-VALID?  ( draft -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE
        MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP LSCID.ID RID-PRESENT? 0= IF DROP 0 EXIT THEN
    DUP LSCID.OPERATION-KEY RID-PRESENT? 0= IF DROP 0 EXIT THEN
    DUP LSCID.ID OVER LSCID.OPERATION-KEY RID= IF DROP 0 EXIT THEN
    DUP LSCID.MUTATION-SEQUENCE @ DUP 0> SWAP
        _LIBCV-MAX-SIGNED <= AND 0= IF DROP 0 EXIT THEN
    DUP LSCID.TITLE-U @ DUP 1 <
        SWAP LIB-COLLECTION-TITLE-MAX > OR IF DROP 0 EXIT THEN
    DUP LSCID.TITLE LIB-COLLECTION-TITLE-MAX
        2 PICK LSCID.TITLE-U @ 0 _LIBCV-TEXT-SLOT? 0= IF
        DROP 0 EXIT
    THEN
    DUP LSCID.MEMBERS-A @ OVER LSCID.MEMBER-N @
        LIBRARY-COLLECTION-MEMBERS-CANONICAL? 0= IF DROP 0 EXIT THEN
    DUP LSCID.MEMBERS-A @ OVER LSCID.MEMBER-N @ RID-SIZE *
    2 PICK LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE
        MSPAN-OVERLAP? IF DROP 0 EXIT THEN
    DROP -1 ;

\ ---------------------------------------------------------------------
\ Durable collection create-request seal
\ ---------------------------------------------------------------------

: _LIBCV-COLLECTION-REQUEST-HASH-FEED
  ( collection member-rids member-n -- )
    SHA3-256-BEGIN
    S" akashic.library.collection-create-request.v2" SHA3-256-ADD
    2 PICK LIBC.TITLE-U 8 SHA3-256-ADD
    2 PICK LIBC.TITLE LIB-COLLECTION-TITLE-MAX SHA3-256-ADD
    2 PICK LIBC.MEMBER-N 8 SHA3-256-ADD
    OVER OVER RID-SIZE * SHA3-256-ADD
    _LIBCV-DROP3 ;

: _LIBCV-COLLECTION-REQUEST-HASH
  ( collection member-rids member-n destination -- )
    >R _LIBCV-COLLECTION-REQUEST-HASH-FEED R> SHA3-256-END ;

: _LIBCV-COLLECTION-REQUEST-ARGS?
  ( initial-collection canonical-member-rids member-n -- flag )
    2DUP LIBRARY-COLLECTION-MEMBERS-CANONICAL? 0= IF
        _LIBCV-DROP3 0 EXIT
    THEN
    2 PICK 0= IF _LIBCV-DROP3 0 EXIT THEN
    2 PICK LIB-COLLECTION-SIZE MSPAN-NONWRAPPING? 0= IF
        _LIBCV-DROP3 0 EXIT
    THEN
    2 PICK LIBC.REVISION @ 1 <> IF _LIBCV-DROP3 0 EXIT THEN
    2 PICK LIBC.MEMBER-N @ OVER <> IF _LIBCV-DROP3 0 EXIT THEN
    _LIBCV-DROP3 -1 ;

: LIBRARY-COLLECTION-REQUEST-MATCHES?
  ( initial-collection canonical-member-rids member-n -- flag )
    2 PICK 2 PICK 2 PICK
        _LIBCV-COLLECTION-REQUEST-ARGS? 0= IF
        _LIBCV-DROP3 0 EXIT
    THEN
    2 PICK LIBC.REQUEST-SEAL >R
    _LIBCV-COLLECTION-REQUEST-HASH-FEED
    R> SHA3-256-END-COMPARE ;

: LIBRARY-COLLECTION-REQUEST-SEAL!
  ( initial-collection canonical-member-rids member-n -- service-status )
    2 PICK 2 PICK 2 PICK
        _LIBCV-COLLECTION-REQUEST-ARGS? 0= IF
        _LIBCV-DROP3 _LIBCV-S-INVALID EXIT
    THEN
    2 PICK 2 PICK 2 PICK
    5 PICK LIBC.REQUEST-SEAL _LIBCV-COLLECTION-REQUEST-HASH
    2 PICK LIB-COLLECTION-VALID? 0= IF
        2 PICK LIBC.REQUEST-SEAL LIB-DIGEST-SIZE 0 FILL
        _LIBCV-DROP3 _LIBCV-S-INVALID EXIT
    THEN
    _LIBCV-DROP3 _LIBCV-S-OK ;

\ ---------------------------------------------------------------------
\ Initial collection preparation
\ ---------------------------------------------------------------------

: _LIBCV-PREPARE-CREATE-ARGS?  ( draft collection -- flag )
    OVER LIBRARY-COLLECTION-INITIAL-DRAFT-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    DUP LIB-COLLECTION-SIZE _LIBCV-SPAN? 0= IF 2DROP 0 EXIT THEN
    OVER LIBRARY-COLLECTION-INITIAL-DRAFT-SIZE
    2 PICK LIB-COLLECTION-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    OVER LSCID.MEMBERS-A @ 2 PICK LSCID.MEMBER-N @ RID-SIZE *
    2 PICK LIB-COLLECTION-SIZE MSPAN-OVERLAP? IF 2DROP 0 EXIT THEN
    2DROP -1 ;

: _LIBCV-PREPARE-CREATE  ( draft collection -- service-status )
    >R
    DUP LSCID.ID R@ LIBC.ID RID-COPY
    DUP LSCID.OPERATION-KEY R@ LIBC.OPERATION-KEY RID-COPY
    1 R@ LIBC.REVISION !
    DUP LSCID.MUTATION-SEQUENCE @
        DUP R@ LIBC.MUTATION-SEQUENCE !
        R@ LIBC.CREATED-SEQUENCE !
    DUP LSCID.MEMBER-N @ R@ LIBC.MEMBER-N !
    DUP LSCID.TITLE-U @ R@ LIBC.TITLE-U !
    DUP LSCID.TITLE OVER LSCID.TITLE-U @
        R@ LIBC.TITLE SWAP MOVE
    DUP LSCID.MEMBERS-A @ OVER LSCID.MEMBER-N @
    R@ -ROT LIBRARY-COLLECTION-REQUEST-SEAL!
    DUP IF
        DROP DROP R@ LIB-COLLECTION-INIT
        R> DROP _LIBCV-S-INVALID EXIT
    THEN
    DROP
    R@ LIB-COLLECTION-VALID? 0= IF
        DROP R@ LIB-COLLECTION-INIT
        R> DROP _LIBCV-S-INVALID EXIT
    THEN
    DROP R> DROP _LIBCV-S-OK ;

: LIBRARY-SERVICE-PREPARE-COLLECTION-CREATE
  ( draft collection -- service-status )
    DUP 0= IF 2DROP _LIBCV-S-INVALID EXIT THEN
    DUP LIB-COLLECTION-SIZE _LIBCV-SPAN? 0= IF
        2DROP _LIBCV-S-INVALID EXIT
    THEN
    DUP LIB-COLLECTION-INIT
    2DUP _LIBCV-PREPARE-CREATE-ARGS? 0= IF
        2DROP _LIBCV-S-INVALID EXIT
    THEN
    _LIBCV-PREPARE-CREATE ;
