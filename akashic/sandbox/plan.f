\ =====================================================================
\  plan.f - Caller-owned sealed sandbox execution-plan container
\ =====================================================================
\  This module owns only the immutable representation produced after an
\  independent verifier has accepted a candidate.  It does not perform
\  semantic verification.  One caller-provided contiguous span contains a
\  fixed self-bound descriptor, one self-bound candidate layout, and an
\  exact private copy of the accepted candidate bytes.
\
\  SBOX-PLAN-PUBLISH-VERIFIED is the verifier's publication seam.  Its
\  caller must already have completed semantic verification.  The word
\  defensively repeats candidate geometry validation, rejects every alias
\  among its inputs, invalidates and clears the destination before staging,
\  and writes the plan seal last.
\ =====================================================================

REQUIRE candidate.f
REQUIRE profile.f

PROVIDED akashic-sbx-plan

\ =====================================================================
\  Status and fixed native descriptor
\ =====================================================================

0 CONSTANT SBOX-PLAN-S-OK
1 CONSTANT SBOX-PLAN-S-INVALID
2 CONSTANT SBOX-PLAN-S-CAPACITY
3 CONSTANT SBOX-PLAN-S-ALIAS

: SBOX-PLAN-STATUS-VALID?  ( status -- flag )
    DUP SBOX-PLAN-S-OK >=
    SWAP SBOX-PLAN-S-ALIAS <= AND ;

\ This is an ephemeral native object discriminator, not a public format
\ boundary.
0x534258504C414E21 CONSTANT _SPLAN-MAGIC  \ "SBXPLAN!"

  0 CONSTANT _SPL-MAGIC
  8 CONSTANT _SPL-SELF
 16 CONSTANT _SPL-TOTAL
 24 CONSTANT _SPL-CANDIDATE-OFF
 32 CONSTANT _SPL-CANDIDATE-U
 40 CONSTANT _SPL-PROFILE
 48 CONSTANT _SPL-PROFILE-TAG
 56 CONSTANT _SPL-MEMORY-U
 64 CONSTANT _SPL-FUNCTION-N
 72 CONSTANT _SPL-IMPORT-N
 80 CONSTANT _SPL-ENTRY-N
 88 CONSTANT _SPL-NAME-U
 96 CONSTANT _SPL-INITIAL-U
104 CONSTANT _SPL-INSTRUCTION-N
112 CONSTANT _SPL-LAYOUT-OFF
120 CONSTANT _SPL-RESERVED
128 CONSTANT _SPL-LAYOUT
256 CONSTANT SBOX-PLAN-DESCRIPTOR-SIZE

: _SPLAN-P.MAGIC         ( plan -- address ) _SPL-MAGIC + ;
: _SPLAN-P.SELF          ( plan -- address ) _SPL-SELF + ;
: _SPLAN-P.TOTAL         ( plan -- address ) _SPL-TOTAL + ;
: _SPLAN-P.CANDIDATE-OFF ( plan -- address ) _SPL-CANDIDATE-OFF + ;
: _SPLAN-P.CANDIDATE-U   ( plan -- address ) _SPL-CANDIDATE-U + ;
: _SPLAN-P.PROFILE       ( plan -- address ) _SPL-PROFILE + ;
: _SPLAN-P.PROFILE-TAG   ( plan -- address ) _SPL-PROFILE-TAG + ;
: _SPLAN-P.MEMORY-U      ( plan -- address ) _SPL-MEMORY-U + ;
: _SPLAN-P.FUNCTION-N    ( plan -- address ) _SPL-FUNCTION-N + ;
: _SPLAN-P.IMPORT-N      ( plan -- address ) _SPL-IMPORT-N + ;
: _SPLAN-P.ENTRY-N       ( plan -- address ) _SPL-ENTRY-N + ;
: _SPLAN-P.NAME-U        ( plan -- address ) _SPL-NAME-U + ;
: _SPLAN-P.INITIAL-U     ( plan -- address ) _SPL-INITIAL-U + ;
: _SPLAN-P.INSTRUCTION-N ( plan -- address ) _SPL-INSTRUCTION-N + ;
: _SPLAN-P.LAYOUT-OFF    ( plan -- address ) _SPL-LAYOUT-OFF + ;
: _SPLAN-P.RESERVED      ( plan -- address ) _SPL-RESERVED + ;

: _SPLAN-LAYOUT     ( plan -- layout ) _SPL-LAYOUT + ;
: _SPLAN-CANDIDATE  ( plan -- candidate )
    SBOX-PLAN-DESCRIPTOR-SIZE + ;

\ Every public nonempty plan or candidate span passes the architectural
\ caller-memory boundary before this module reads or writes it.  Boundary
\ failures deliberately close to the plan's INVALID status.
: _SPLAN-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP SBOX-PLAN-S-INVALID EXIT THEN
    DUP 0= IF 2DROP SBOX-PLAN-S-OK EXIT THEN
    OVER 0= IF 2DROP SBOX-PLAN-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP SBOX-PLAN-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID
    ELSE
        SBOX-PLAN-S-OK
    THEN ;

: _SPLAN-HEADER-STATUS  ( plan -- status )
    DUP 0= IF DROP SBOX-PLAN-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SBOX-PLAN-S-INVALID EXIT THEN
    SBOX-PLAN-DESCRIPTOR-SIZE _SPLAN-SPAN-STATUS ;

\ =====================================================================
\  Measurement and structural validation
\ =====================================================================

: SBOX-PLAN-MEASURE  ( candidate-u -- plan-u|0 status )
    DUP SBOX-CANDIDATE-HEADER-SIZE < IF
        DROP 0 SBOX-PLAN-S-INVALID EXIT
    THEN
    SBOX-PLAN-DESCRIPTOR-SIZE SBOX-BYTE-LENGTH+
    DUP SBOX-BYTE-S-OK = IF
        DROP SBOX-PLAN-S-OK EXIT
    THEN
    SBOX-BYTE-S-CAPACITY = IF
        DROP 0 SBOX-PLAN-S-CAPACITY
    ELSE
        DROP 0 SBOX-PLAN-S-INVALID
    THEN ;

: _SPLAN-LAYOUT-FIELDS-MATCH?  ( layout plan -- flag )
    >R
    DUP _SCAND-L.FUNCTION-N @ R@ _SPLAN-P.FUNCTION-N @ =
    OVER _SCAND-L.IMPORT-N @ R@ _SPLAN-P.IMPORT-N @ = AND
    OVER _SCAND-L.ENTRY-N @ R@ _SPLAN-P.ENTRY-N @ = AND
    OVER _SCAND-L.NAME-U @ R@ _SPLAN-P.NAME-U @ = AND
    OVER _SCAND-L.INITIAL-U @ R@ _SPLAN-P.INITIAL-U @ = AND
    OVER _SCAND-L.INSTRUCTION-N @
        R@ _SPLAN-P.INSTRUCTION-N @ = AND
    OVER _SCAND-L.TOTAL @ R@ _SPLAN-P.CANDIDATE-U @ = AND
    R> DROP NIP ;

: _SPLAN-LAYOUT-MATCH?  ( plan -- flag )
    DUP _SPLAN-LAYOUT
    DUP SBOX-CANDIDATE-LAYOUT-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    SWAP _SPLAN-LAYOUT-FIELDS-MATCH? ;

: _SPLAN-CANDIDATE-MATCH?  ( plan -- flag )
    DUP _SPLAN-CANDIDATE >R
    R@ _SCAND-MAGIC?
    R@ _SCAND-H-FLAGS + SBOX-CANDIDATE-U64-LE@ 0= AND
    R@ SBOX-CANDIDATE-TOTAL@
        2 PICK _SPLAN-P.CANDIDATE-U @ = AND
    R@ SBOX-CANDIDATE-PROFILE-TAG@
        2 PICK _SPLAN-P.PROFILE-TAG @ = AND
    R@ SBOX-CANDIDATE-MEMORY-U@
        2 PICK _SPLAN-P.MEMORY-U @ = AND
    R@ SBOX-CANDIDATE-FUNCTION-N@
        2 PICK _SPLAN-P.FUNCTION-N @ = AND
    R@ SBOX-CANDIDATE-IMPORT-N@
        2 PICK _SPLAN-P.IMPORT-N @ = AND
    R@ SBOX-CANDIDATE-ENTRY-N@
        2 PICK _SPLAN-P.ENTRY-N @ = AND
    R@ SBOX-CANDIDATE-NAME-U@
        2 PICK _SPLAN-P.NAME-U @ = AND
    R@ SBOX-CANDIDATE-INITIAL-U@
        2 PICK _SPLAN-P.INITIAL-U @ = AND
    R@ SBOX-CANDIDATE-INSTRUCTION-N@
        2 PICK _SPLAN-P.INSTRUCTION-N @ = AND
    R> DROP NIP ;

: _SPLAN-PROFILE-DISJOINT?  ( plan -- flag )
    DUP _SPLAN-P.PROFILE @ DUP 0= IF 2DROP 0 EXIT THEN
    DUP SBOX-PROFILE-SIZE MSPAN-NONWRAPPING? 0= IF
        2DROP 0 EXIT
    THEN
    SBOX-PROFILE-SIZE
    2 PICK 3 PICK _SPLAN-P.TOTAL @ MSPAN-OVERLAP? 0=
    NIP ;

: SBOX-PLAN-VALID?  ( plan -- flag )
    DUP _SPLAN-HEADER-STATUS IF DROP 0 EXIT THEN
    DUP _SPLAN-P.MAGIC @ _SPLAN-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SPLAN-P.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SPLAN-P.RESERVED @ IF DROP 0 EXIT THEN
    DUP _SPLAN-P.CANDIDATE-OFF @
        SBOX-PLAN-DESCRIPTOR-SIZE <> IF DROP 0 EXIT THEN
    DUP _SPLAN-P.LAYOUT-OFF @ _SPL-LAYOUT <> IF DROP 0 EXIT THEN
    DUP _SPLAN-P.PROFILE-TAG @ 0= IF DROP 0 EXIT THEN
    DUP _SPLAN-P.MEMORY-U @ 0< IF DROP 0 EXIT THEN

    DUP _SPLAN-P.CANDIDATE-U @ SBOX-PLAN-MEASURE
    DUP IF 2DROP DROP 0 EXIT THEN
    DROP
    OVER _SPLAN-P.TOTAL @ <> IF DROP 0 EXIT THEN

    DUP DUP _SPLAN-P.TOTAL @ _SPLAN-SPAN-STATUS IF
        DROP 0 EXIT
    THEN
    DUP _SPLAN-PROFILE-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _SPLAN-LAYOUT-MATCH? 0= IF DROP 0 EXIT THEN
    _SPLAN-CANDIDATE-MATCH? ;

\ =====================================================================
\  Verifier-only publication
\ =====================================================================

: _SPLAN-CANDIDATE>STATUS  ( candidate-status -- plan-status )
    DUP SBOX-CANDIDATE-S-OK = IF DROP SBOX-PLAN-S-OK EXIT THEN
    DUP SBOX-CANDIDATE-S-CAPACITY = IF
        DROP SBOX-PLAN-S-CAPACITY EXIT
    THEN
    DUP SBOX-CANDIDATE-S-ALIAS = IF DROP SBOX-PLAN-S-ALIAS EXIT THEN
    DROP SBOX-PLAN-S-INVALID ;

: _SPLAN-DROP6>STATUS  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R 2DROP 2DROP 2DROP R> ;

: _SPLAN-PUBLISH-GEOMETRY
  ( candidate candidate-u layout profile plan plan-u -- status )
    1 PICK 0= IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN
    1 PICK 7 AND IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN
    1 PICK OVER _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN

    5 PICK 5 PICK _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN
    3 PICK 7 AND IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN
    3 PICK SBOX-CANDIDATE-LAYOUT-SIZE _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN
    2 PICK 0= IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN
    2 PICK SBOX-PROFILE-SIZE _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP6>STATUS EXIT
    THEN

    4 PICK SBOX-PLAN-MEASURE
    DUP IF
        >R DROP R> _SPLAN-DROP6>STATUS EXIT
    THEN
    DROP
    1 PICK U> IF
        SBOX-PLAN-S-CAPACITY _SPLAN-DROP6>STATUS EXIT
    THEN

    5 PICK 5 PICK
        5 PICK SBOX-CANDIDATE-LAYOUT-SIZE
        MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP6>STATUS EXIT
    THEN
    5 PICK 5 PICK 4 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP6>STATUS EXIT
    THEN
    5 PICK 5 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP6>STATUS EXIT
    THEN
    3 PICK SBOX-CANDIDATE-LAYOUT-SIZE
        4 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP6>STATUS EXIT
    THEN
    3 PICK SBOX-CANDIDATE-LAYOUT-SIZE
        3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP6>STATUS EXIT
    THEN
    2 PICK SBOX-PROFILE-SIZE 3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP6>STATUS EXIT
    THEN
    SBOX-PLAN-S-OK _SPLAN-DROP6>STATUS ;

: _SPLAN-LAYOUTS=  ( first second -- flag )
    2DUP SBOX-CANDIDATE-LAYOUT-VALID?
    SWAP SBOX-CANDIDATE-LAYOUT-VALID? AND 0= IF
        2DROP 0 EXIT
    THEN
    16 + >R
    16 + SBOX-CANDIDATE-LAYOUT-SIZE 16 -
    R> OVER
    COMPARE 0= ;

: _SPLAN-PUBLISH-STAGED  ( plan -- status )
    DUP _SPLAN-P.RESERVED @
        SBOX-CANDIDATE-LAYOUT-VALID? 0= IF
        DROP SBOX-PLAN-S-INVALID EXIT
    THEN

    DUP _SPLAN-P.TOTAL @
    OVER _SPLAN-P.CANDIDATE-U @
    2 PICK _SPLAN-LAYOUT
    SBOX-CANDIDATE-INSPECT _SPLAN-CANDIDATE>STATUS
    DUP IF NIP EXIT THEN DROP

    DUP _SPLAN-P.RESERVED @
    OVER _SPLAN-LAYOUT _SPLAN-LAYOUTS= 0= IF
        DROP SBOX-PLAN-S-INVALID EXIT
    THEN

    \ Copy while _SPL-TOTAL still holds the admitted borrowed source.
    DUP _SPLAN-P.TOTAL @
    OVER _SPLAN-P.CANDIDATE-U @
    2 PICK _SPLAN-CANDIDATE
    SWAP MOVE

    DUP _SPLAN-P.CANDIDATE-U @ SBOX-PLAN-MEASURE
    DUP IF >R 2DROP R> EXIT THEN
    DROP
    OVER _SPLAN-P.TOTAL !

    DUP DUP _SPLAN-P.SELF !
    SBOX-PLAN-DESCRIPTOR-SIZE OVER _SPLAN-P.CANDIDATE-OFF !
    _SPL-LAYOUT OVER _SPLAN-P.LAYOUT-OFF !

    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-PROFILE-TAG@
        OVER _SPLAN-P.PROFILE-TAG !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-MEMORY-U@
        OVER _SPLAN-P.MEMORY-U !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-FUNCTION-N@
        OVER _SPLAN-P.FUNCTION-N !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-IMPORT-N@
        OVER _SPLAN-P.IMPORT-N !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-ENTRY-N@
        OVER _SPLAN-P.ENTRY-N !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-NAME-U@
        OVER _SPLAN-P.NAME-U !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-INITIAL-U@
        OVER _SPLAN-P.INITIAL-U !
    DUP _SPLAN-CANDIDATE SBOX-CANDIDATE-INSTRUCTION-N@
        OVER _SPLAN-P.INSTRUCTION-N !
    0 OVER _SPLAN-P.RESERVED !

    \ No write follows this publication seal.
    _SPLAN-MAGIC OVER _SPLAN-P.MAGIC !
    SBOX-PLAN-VALID? IF
        SBOX-PLAN-S-OK
    ELSE
        SBOX-PLAN-S-INVALID
    THEN ;

: SBOX-PLAN-PUBLISH-VERIFIED
  ( candidate candidate-u layout profile plan plan-u -- status )
    5 PICK 5 PICK 5 PICK 5 PICK 5 PICK 5 PICK
    _SPLAN-PUBLISH-GEOMETRY
    DUP IF
        >R 2DROP 2DROP 2DROP R> EXIT
    THEN
    DROP

    \ Geometry and disjointness are now admitted.  Invalidate and scrub the
    \ complete caller destination before inspecting any candidate byte.
    1 PICK OVER 0 FILL

    \ Use invalid descriptor fields as bounded publication scratch.  MAGIC
    \ remains zero until the final write in _SPLAN-PUBLISH-STAGED.
    5 PICK 2 PICK _SPLAN-P.TOTAL !
    4 PICK 2 PICK _SPLAN-P.CANDIDATE-U !
    3 PICK 2 PICK _SPLAN-P.RESERVED !
    2 PICK 2 PICK _SPLAN-P.PROFILE !

    1 PICK _SPLAN-PUBLISH-STAGED
    DUP IF
        >R 1 PICK OVER 0 FILL R>
    THEN
    >R 2DROP 2DROP 2DROP R> ;

\ =====================================================================
\  Read-only sealed-plan queries
\ =====================================================================

: SBOX-PLAN-TOTAL@  ( plan -- total|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.TOTAL @ ELSE DROP 0 THEN ;

: SBOX-PLAN-PROFILE@  ( plan -- profile|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.PROFILE @ ELSE DROP 0 THEN ;

: SBOX-PLAN-PROFILE-TAG@  ( plan -- tag|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.PROFILE-TAG @ ELSE DROP 0 THEN ;

: SBOX-PLAN-MEMORY-U@  ( plan -- memory-u|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.MEMORY-U @ ELSE DROP 0 THEN ;

: SBOX-PLAN-FUNCTION-N@  ( plan -- count|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.FUNCTION-N @ ELSE DROP 0 THEN ;

: SBOX-PLAN-IMPORT-N@  ( plan -- count|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.IMPORT-N @ ELSE DROP 0 THEN ;

: SBOX-PLAN-ENTRY-N@  ( plan -- count|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.ENTRY-N @ ELSE DROP 0 THEN ;

: SBOX-PLAN-NAME-U@  ( plan -- length|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.NAME-U @ ELSE DROP 0 THEN ;

: SBOX-PLAN-INITIAL-U@  ( plan -- length|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.INITIAL-U @ ELSE DROP 0 THEN ;

: SBOX-PLAN-INSTRUCTION-N@  ( plan -- count|0 )
    DUP SBOX-PLAN-VALID? IF
        _SPLAN-P.INSTRUCTION-N @
    ELSE DROP 0 THEN ;

: SBOX-PLAN-CANDIDATE$  ( plan -- candidate candidate-u | 0 0 )
    DUP SBOX-PLAN-VALID? IF
        DUP _SPLAN-CANDIDATE
        SWAP _SPLAN-P.CANDIDATE-U @
    ELSE
        DROP 0 0
    THEN ;

: _SPLAN-INDEXED@
  ( index plan count candidate-offset element-u -- address|0 )
    SWAP >R >R
    2 PICK 0< IF
        2DROP DROP R> DROP R> DROP 0 EXIT
    THEN
    2 PICK OVER >= IF
        2DROP DROP R> DROP R> DROP 0 EXIT
    THEN
    DROP SWAP
    R> * R> +
    SBOX-PLAN-DESCRIPTOR-SIZE + + ;

\ Internal execution accessors are valid only after a public boundary has
\ admitted the sealed plan.  They avoid revalidating the same immutable plan
\ and embedded layout for every instruction in one uninterrupted VM slice.
: _SPLAN-FUNCTION-ADMITTED@  ( index plan -- record|0 )
    DUP _SPLAN-P.FUNCTION-N @
    1 PICK _SPLAN-LAYOUT _SCAND-L.FUNCTION-OFF @
    SBOX-CANDIDATE-FUNCTION-SIZE _SPLAN-INDEXED@ ;

: _SPLAN-ENTRY-ADMITTED@  ( index plan -- record|0 )
    DUP _SPLAN-P.ENTRY-N @
    1 PICK _SPLAN-LAYOUT _SCAND-L.ENTRY-OFF @
    SBOX-CANDIDATE-ENTRY-SIZE _SPLAN-INDEXED@ ;

: _SPLAN-INSTRUCTION-ADMITTED@  ( index plan -- record|0 )
    DUP _SPLAN-P.INSTRUCTION-N @
    1 PICK _SPLAN-LAYOUT _SCAND-L.INSTRUCTION-OFF @
    SBOX-CANDIDATE-INSTRUCTION-SIZE _SPLAN-INDEXED@ ;

: SBOX-PLAN-FUNCTION@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    _SPLAN-FUNCTION-ADMITTED@ ;

: SBOX-PLAN-IMPORT@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    DUP _SPLAN-P.IMPORT-N @
    1 PICK _SPLAN-LAYOUT SBOX-CANDIDATE-LAYOUT-IMPORTS@
    SBOX-CANDIDATE-IMPORT-SIZE _SPLAN-INDEXED@ ;

: SBOX-PLAN-ENTRY@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    _SPLAN-ENTRY-ADMITTED@ ;

: SBOX-PLAN-NAME@  ( index plan -- byte-address|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    DUP _SPLAN-P.NAME-U @
    1 PICK _SPLAN-LAYOUT SBOX-CANDIDATE-LAYOUT-NAMES@
    1 _SPLAN-INDEXED@ ;

: SBOX-PLAN-INITIAL@  ( index plan -- byte-address|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    DUP _SPLAN-P.INITIAL-U @
    1 PICK _SPLAN-LAYOUT SBOX-CANDIDATE-LAYOUT-INITIAL@
    1 _SPLAN-INDEXED@ ;

: SBOX-PLAN-INSTRUCTION@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    _SPLAN-INSTRUCTION-ADMITTED@ ;

\ =====================================================================
\  Deterministic release
\ =====================================================================

: _SPLAN-DESCRIPTOR-ZERO?  ( plan -- flag )
    SBOX-PLAN-DESCRIPTOR-SIZE 0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: SBOX-PLAN-RELEASE  ( plan -- status )
    DUP _SPLAN-HEADER-STATUS DUP IF NIP EXIT THEN DROP
    DUP SBOX-PLAN-VALID? IF
        DUP _SPLAN-P.TOTAL @ >R
        0 OVER _SPLAN-P.MAGIC !
        DUP R@ 0 FILL
        R> DROP DROP SBOX-PLAN-S-OK EXIT
    THEN
    DUP _SPLAN-DESCRIPTOR-ZERO? IF
        DROP SBOX-PLAN-S-OK EXIT
    THEN
    \ A corrupt descriptor cannot safely supply an owned-copy extent.
    \ Fail closed after invalidating and clearing the admitted fixed header.
    0 OVER _SPLAN-P.MAGIC !
    DUP SBOX-PLAN-DESCRIPTOR-SIZE 0 FILL
    DROP SBOX-PLAN-S-INVALID ;
