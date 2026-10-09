\ =====================================================================
\  plan.f - Caller-owned sealed sandbox execution-plan container
\ =====================================================================
\  This module owns only the immutable representation produced after an
\  independent verifier has accepted an artifact.  It does not perform
\  semantic verification.  One caller-provided contiguous span contains a
\  fixed self-bound descriptor, one self-bound artifact layout, and an
\  exact private copy of the accepted artifact bytes.  The descriptor also
\  keeps the artifact's content digest, which the verifier computed.
\
\  SBOX-PLAN-PUBLISH-VERIFIED is the verifier's publication seam.  Its
\  caller must already have completed semantic verification.  The word
\  defensively repeats artifact geometry validation, rejects every alias
\  among its inputs, invalidates and clears the destination before staging,
\  and writes the plan seal last.
\ =====================================================================

REQUIRE artifact.f
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
 24 CONSTANT _SPL-ARTIFACT-OFF
 32 CONSTANT _SPL-ARTIFACT-U
 40 CONSTANT _SPL-PROFILE
 48 CONSTANT _SPL-MEMORY-U
 56 CONSTANT _SPL-FUNCTION-N
 64 CONSTANT _SPL-IMPORT-N
 72 CONSTANT _SPL-ENTRY-N
 80 CONSTANT _SPL-NAME-U
 88 CONSTANT _SPL-INITIAL-U
 96 CONSTANT _SPL-INSTRUCTION-N
104 CONSTANT _SPL-LAYOUT-OFF
112 CONSTANT _SPL-RESERVED
120 CONSTANT _SPL-ARTIFACT-DIGEST
152 CONSTANT _SPL-LAYOUT
_SPL-LAYOUT SBOX-ARTIFACT-LAYOUT-SIZE + CONSTANT SBOX-PLAN-DESCRIPTOR-SIZE

: _SPLAN-P.MAGIC         ( plan -- address ) _SPL-MAGIC + ;
: _SPLAN-P.SELF          ( plan -- address ) _SPL-SELF + ;
: _SPLAN-P.TOTAL         ( plan -- address ) _SPL-TOTAL + ;
: _SPLAN-P.ARTIFACT-OFF ( plan -- address ) _SPL-ARTIFACT-OFF + ;
: _SPLAN-P.ARTIFACT-U   ( plan -- address ) _SPL-ARTIFACT-U + ;
: _SPLAN-P.PROFILE       ( plan -- address ) _SPL-PROFILE + ;
: _SPLAN-P.ARTIFACT-DIGEST ( plan -- address ) _SPL-ARTIFACT-DIGEST + ;
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
: _SPLAN-ARTIFACT  ( plan -- artifact )
    SBOX-PLAN-DESCRIPTOR-SIZE + ;

\ Every public nonempty plan or artifact span passes the architectural
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

: SBOX-PLAN-MEASURE  ( artifact-u -- plan-u|0 status )
    DUP SBOX-ARTIFACT-PREFIX-SIZE < IF
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
    DUP _SART-L.FUNCTION-N @ R@ _SPLAN-P.FUNCTION-N @ =
    OVER _SART-L.IMPORT-N @ R@ _SPLAN-P.IMPORT-N @ = AND
    OVER _SART-L.ENTRY-N @ R@ _SPLAN-P.ENTRY-N @ = AND
    OVER _SART-L.NAME-U @ R@ _SPLAN-P.NAME-U @ = AND
    OVER _SART-L.INITIAL-U @ R@ _SPLAN-P.INITIAL-U @ = AND
    OVER _SART-L.INSTRUCTION-N @
        R@ _SPLAN-P.INSTRUCTION-N @ = AND
    OVER _SART-L.TOTAL @ R@ _SPLAN-P.ARTIFACT-U @ = AND
    R> DROP NIP ;

: _SPLAN-LAYOUT-MATCH?  ( plan -- flag )
    DUP _SPLAN-LAYOUT
    DUP SBOX-ARTIFACT-LAYOUT-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    SWAP _SPLAN-LAYOUT-FIELDS-MATCH? ;

\ The artifact copy agrees with the descriptor and layout.  The plan's
\ whole span is admitted before this runs, so its fields are read directly;
\ its directory records were proved when the plan was published.
: _SPLAN-ARTIFACT-MATCH?  ( plan -- flag )
    DUP _SPLAN-ARTIFACT
    DUP _SART-HEADER-FIXED? 0= IF 2DROP 0 EXIT THEN
    DUP _SART-H-TOTAL + SBOX-BYTE-U64-LE@
        2 PICK _SPLAN-P.ARTIFACT-U @ <> IF 2DROP 0 EXIT THEN
    DUP _SART-H-MEMORY-U + SBOX-BYTE-U64-LE@
        2 PICK _SPLAN-P.MEMORY-U @ <> IF 2DROP 0 EXIT THEN
    SBOX-ARTIFACT-SECTION-N 0 DO
        DUP I _SART-SECTION-COUNT
        2 PICK _SPLAN-LAYOUT I _SART-L.COUNT @ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

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
    DUP _SPLAN-P.ARTIFACT-OFF @
        SBOX-PLAN-DESCRIPTOR-SIZE <> IF DROP 0 EXIT THEN
    DUP _SPLAN-P.LAYOUT-OFF @ _SPL-LAYOUT <> IF DROP 0 EXIT THEN
    DUP _SPLAN-P.MEMORY-U @ 0< IF DROP 0 EXIT THEN

    DUP _SPLAN-P.ARTIFACT-U @ SBOX-PLAN-MEASURE
    DUP IF 2DROP DROP 0 EXIT THEN
    DROP
    OVER _SPLAN-P.TOTAL @ <> IF DROP 0 EXIT THEN

    DUP DUP _SPLAN-P.TOTAL @ _SPLAN-SPAN-STATUS IF
        DROP 0 EXIT
    THEN
    DUP _SPLAN-PROFILE-DISJOINT? 0= IF DROP 0 EXIT THEN
    DUP _SPLAN-LAYOUT-MATCH? 0= IF DROP 0 EXIT THEN
    _SPLAN-ARTIFACT-MATCH? ;

\ =====================================================================
\  Verifier-only publication
\ =====================================================================

: _SPLAN-ARTIFACT>STATUS  ( artifact-status -- plan-status )
    DUP SBOX-ARTIFACT-S-OK = IF DROP SBOX-PLAN-S-OK EXIT THEN
    DUP SBOX-ARTIFACT-S-CAPACITY = IF
        DROP SBOX-PLAN-S-CAPACITY EXIT
    THEN
    DUP SBOX-ARTIFACT-S-ALIAS = IF DROP SBOX-PLAN-S-ALIAS EXIT THEN
    DROP SBOX-PLAN-S-INVALID ;

: _SPLAN-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP DROP ;

: _SPLAN-DROP7>STATUS  ( x1 x2 x3 x4 x5 x6 x7 status -- status )
    >R _SPLAN-DROP7 R> ;

: _SPLAN-PUBLISH-GEOMETRY
  ( artifact artifact-u layout profile digest plan plan-u -- status )
    1 PICK 0= IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    1 PICK 7 AND IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    1 PICK OVER _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN

    6 PICK 6 PICK _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    4 PICK 7 AND IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    4 PICK SBOX-ARTIFACT-LAYOUT-SIZE _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    3 PICK 0= IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    3 PICK SBOX-PROFILE-SIZE _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    2 PICK 0= IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN
    2 PICK SBOX-ARTIFACT-DIGEST-SIZE _SPLAN-SPAN-STATUS IF
        SBOX-PLAN-S-INVALID _SPLAN-DROP7>STATUS EXIT
    THEN

    5 PICK SBOX-PLAN-MEASURE
    DUP IF
        >R DROP R> _SPLAN-DROP7>STATUS EXIT
    THEN
    DROP
    1 PICK U> IF
        SBOX-PLAN-S-CAPACITY _SPLAN-DROP7>STATUS EXIT
    THEN

    \ artifact/layout, artifact/profile and artifact/plan
    6 PICK 6 PICK
        6 PICK SBOX-ARTIFACT-LAYOUT-SIZE
        MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    6 PICK 6 PICK 5 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    6 PICK 6 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    \ layout/profile, layout/plan and profile/plan
    4 PICK SBOX-ARTIFACT-LAYOUT-SIZE
        5 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    4 PICK SBOX-ARTIFACT-LAYOUT-SIZE
        3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    3 PICK SBOX-PROFILE-SIZE 3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    \ The plan is cleared before the digest is copied into it.
    2 PICK SBOX-ARTIFACT-DIGEST-SIZE 3 PICK 3 PICK MSPAN-OVERLAP? IF
        SBOX-PLAN-S-ALIAS _SPLAN-DROP7>STATUS EXIT
    THEN
    SBOX-PLAN-S-OK _SPLAN-DROP7>STATUS ;

: _SPLAN-LAYOUTS=  ( first second -- flag )
    2DUP SBOX-ARTIFACT-LAYOUT-VALID?
    SWAP SBOX-ARTIFACT-LAYOUT-VALID? AND 0= IF
        2DROP 0 EXIT
    THEN
    16 + >R
    16 + SBOX-ARTIFACT-LAYOUT-SIZE 16 -
    R> OVER
    COMPARE 0= ;

: _SPLAN-PUBLISH-STAGED  ( plan -- status )
    DUP _SPLAN-P.RESERVED @
        SBOX-ARTIFACT-LAYOUT-VALID? 0= IF
        DROP SBOX-PLAN-S-INVALID EXIT
    THEN

    DUP _SPLAN-P.TOTAL @
    OVER _SPLAN-P.ARTIFACT-U @
    2 PICK _SPLAN-LAYOUT
    SBOX-ARTIFACT-INSPECT _SPLAN-ARTIFACT>STATUS
    DUP IF NIP EXIT THEN DROP

    DUP _SPLAN-P.RESERVED @
    OVER _SPLAN-LAYOUT _SPLAN-LAYOUTS= 0= IF
        DROP SBOX-PLAN-S-INVALID EXIT
    THEN

    \ Copy while _SPL-TOTAL still holds the admitted borrowed source.
    DUP _SPLAN-P.TOTAL @
    OVER _SPLAN-P.ARTIFACT-U @
    2 PICK _SPLAN-ARTIFACT
    SWAP MOVE

    DUP _SPLAN-P.ARTIFACT-U @ SBOX-PLAN-MEASURE
    DUP IF >R 2DROP R> EXIT THEN
    DROP
    OVER _SPLAN-P.TOTAL !

    DUP DUP _SPLAN-P.SELF !
    SBOX-PLAN-DESCRIPTOR-SIZE OVER _SPLAN-P.ARTIFACT-OFF !
    _SPL-LAYOUT OVER _SPLAN-P.LAYOUT-OFF !

    \ The artifact names the exact profile it was verified for.
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-PROFILE-DIGEST@
    OVER _SPLAN-P.PROFILE @ SBOX-PROFILE-DIGEST= 0= IF
        DROP SBOX-PLAN-S-INVALID EXIT
    THEN
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-MEMORY-U@
        OVER _SPLAN-P.MEMORY-U !
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-FUNCTION-N@
        OVER _SPLAN-P.FUNCTION-N !
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-IMPORT-N@
        OVER _SPLAN-P.IMPORT-N !
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-ENTRY-N@
        OVER _SPLAN-P.ENTRY-N !
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-NAME-U@
        OVER _SPLAN-P.NAME-U !
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-INITIAL-U@
        OVER _SPLAN-P.INITIAL-U !
    DUP _SPLAN-ARTIFACT SBOX-ARTIFACT-INSTRUCTION-N@
        OVER _SPLAN-P.INSTRUCTION-N !
    0 OVER _SPLAN-P.RESERVED !

    \ No write follows this publication seal.
    _SPLAN-MAGIC OVER _SPLAN-P.MAGIC !
    SBOX-PLAN-VALID? IF
        SBOX-PLAN-S-OK
    ELSE
        SBOX-PLAN-S-INVALID
    THEN ;

\ DIGEST is the artifact's content digest, which the verifier computed.
: SBOX-PLAN-PUBLISH-VERIFIED
  ( artifact artifact-u layout profile digest plan plan-u -- status )
    6 PICK 6 PICK 6 PICK 6 PICK 6 PICK 6 PICK 6 PICK
    _SPLAN-PUBLISH-GEOMETRY
    DUP IF
        >R _SPLAN-DROP7 R> EXIT
    THEN
    DROP

    \ Geometry and disjointness are now admitted.  Invalidate and scrub the
    \ complete caller destination before inspecting any artifact byte.
    1 PICK OVER 0 FILL

    \ Use invalid descriptor fields as bounded publication scratch.  MAGIC
    \ remains zero until the final write in _SPLAN-PUBLISH-STAGED.
    6 PICK 2 PICK _SPLAN-P.TOTAL !
    5 PICK 2 PICK _SPLAN-P.ARTIFACT-U !
    4 PICK 2 PICK _SPLAN-P.RESERVED !
    3 PICK 2 PICK _SPLAN-P.PROFILE !
    2 PICK 2 PICK _SPLAN-P.ARTIFACT-DIGEST SBOX-ARTIFACT-DIGEST-SIZE MOVE

    1 PICK _SPLAN-PUBLISH-STAGED
    DUP IF
        >R 1 PICK OVER 0 FILL R>
    THEN
    >R _SPLAN-DROP7 R> ;

\ =====================================================================
\  Read-only sealed-plan queries
\ =====================================================================

: SBOX-PLAN-TOTAL@  ( plan -- total|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.TOTAL @ ELSE DROP 0 THEN ;

: SBOX-PLAN-PROFILE@  ( plan -- profile|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.PROFILE @ ELSE DROP 0 THEN ;

\ The digest of the profile the plan was verified for, which its artifact
\ names.  Callers read the 32 bytes and never write them.
: SBOX-PLAN-PROFILE-DIGEST@  ( plan -- digest|0 )
    DUP SBOX-PLAN-VALID? IF
        _SPLAN-ARTIFACT _SART-H-PROFILE +
    ELSE DROP 0 THEN ;

\ The SHA3-256 content digest of the artifact, in its artifact domain.
: SBOX-PLAN-ARTIFACT-DIGEST@  ( plan -- digest|0 )
    DUP SBOX-PLAN-VALID? IF _SPLAN-P.ARTIFACT-DIGEST ELSE DROP 0 THEN ;

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

: SBOX-PLAN-ARTIFACT$  ( plan -- artifact artifact-u | 0 0 )
    DUP SBOX-PLAN-VALID? IF
        DUP _SPLAN-ARTIFACT
        SWAP _SPLAN-P.ARTIFACT-U @
    ELSE
        DROP 0 0
    THEN ;

: _SPLAN-INDEXED@
  ( index plan count artifact-offset element-u -- address|0 )
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
    1 PICK _SPLAN-LAYOUT _SART-L.FUNCTION-OFF @
    SBOX-ARTIFACT-FUNCTION-SIZE _SPLAN-INDEXED@ ;

: _SPLAN-ENTRY-ADMITTED@  ( index plan -- record|0 )
    DUP _SPLAN-P.ENTRY-N @
    1 PICK _SPLAN-LAYOUT _SART-L.ENTRY-OFF @
    SBOX-ARTIFACT-ENTRY-SIZE _SPLAN-INDEXED@ ;

: _SPLAN-INSTRUCTION-ADMITTED@  ( index plan -- record|0 )
    DUP _SPLAN-P.INSTRUCTION-N @
    1 PICK _SPLAN-LAYOUT _SART-L.INSTRUCTION-OFF @
    SBOX-ARTIFACT-INSTRUCTION-SIZE _SPLAN-INDEXED@ ;

: SBOX-PLAN-FUNCTION@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    _SPLAN-FUNCTION-ADMITTED@ ;

: SBOX-PLAN-IMPORT@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    DUP _SPLAN-P.IMPORT-N @
    1 PICK _SPLAN-LAYOUT SBOX-ARTIFACT-LAYOUT-IMPORTS@
    SBOX-ARTIFACT-IMPORT-SIZE _SPLAN-INDEXED@ ;

: SBOX-PLAN-ENTRY@  ( index plan -- record|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    _SPLAN-ENTRY-ADMITTED@ ;

: SBOX-PLAN-ENTRY-SIGNATURE@  ( index plan -- signature-id flag )
    SBOX-PLAN-ENTRY@
    DUP 0= IF DROP 0 0 EXIT THEN
    SBOX-ARTIFACT-ENTRY-SIGNATURE-ID-OFFSET +
    SBOX-BYTE-U32-LE@ -1 ;

: SBOX-PLAN-NAME@  ( index plan -- byte-address|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    DUP _SPLAN-P.NAME-U @
    1 PICK _SPLAN-LAYOUT SBOX-ARTIFACT-LAYOUT-NAMES@
    1 _SPLAN-INDEXED@ ;

: SBOX-PLAN-ENTRY-NAME$  ( index plan -- address length | 0 0 )
    >R
    R@ SBOX-PLAN-ENTRY@
    DUP 0= IF DROP R> DROP 0 0 EXIT THEN
    DUP SBOX-ARTIFACT-ENTRY-NAME-OFFSET +
        SBOX-BYTE-U32-LE@
    SWAP SBOX-ARTIFACT-ENTRY-NAME-U-OFFSET +
        SBOX-BYTE-U16-LE@
    R> SWAP >R
    SBOX-PLAN-NAME@
    DUP 0= IF DROP R> DROP 0 0 EXIT THEN
    R> ;

: SBOX-PLAN-INITIAL@  ( index plan -- byte-address|0 )
    DUP SBOX-PLAN-VALID? 0= IF 2DROP 0 EXIT THEN
    DUP _SPLAN-P.INITIAL-U @
    1 PICK _SPLAN-LAYOUT SBOX-ARTIFACT-LAYOUT-INITIAL@
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
