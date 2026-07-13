\ =====================================================================
\  mandate.f - Versioned, provider-neutral delegated work bounds
\ =====================================================================
\  A Mandate is a value contract, not an authority token.  It describes
\  which Context, effects, disposition, lifetime, and budgets a delegated
\  run may use.  Separate grants/handles authorize individual operations.
\ =====================================================================

PROVIDED akashic-interop-mandate

REQUIRE capability.f
REQUIRE ../runtime/identity.f

1296125508 CONSTANT MAND-MAGIC       \ "MAND"
2          CONSTANT MAND-ABI-VERSION

1 CONSTANT MAND-D-READ-ONLY
2 CONSTANT MAND-D-PROPOSAL
3 CONSTANT MAND-D-COMMIT

CAP-E-OBSERVE CAP-E-NAVIGATE OR CAP-E-MUTATE OR CAP-E-PERSIST OR
CAP-E-DESTRUCTIVE OR CAP-E-EXTERNAL OR CONSTANT MAND-EFFECTS-MASK

\ Version-2 Mandate, 32 cells / 256 bytes.  Practice and facet identities
\ are durable RID values; Context identities remain activation-local.
  0 CONSTANT _MAND-MAGIC
  8 CONSTANT _MAND-ABI
 16 CONSTANT _MAND-SIZE
 24 CONSTANT _MAND-ID               \ RID-SIZE bytes
 56 CONSTANT _MAND-ACTIVATION-EPOCH
 64 CONSTANT _MAND-PRINCIPAL
 72 CONSTANT _MAND-CONTEXT-ID
 80 CONSTANT _MAND-CONTEXT-GEN
 88 CONSTANT _MAND-EFFECTS
 96 CONSTANT _MAND-DISPOSITION
104 CONSTANT _MAND-EXPIRES-MS        \ 0 means activation lifetime
112 CONSTANT _MAND-TIME-BUDGET-MS
120 CONSTANT _MAND-MEMORY-BUDGET
128 CONSTANT _MAND-TOKEN-BUDGET
136 CONSTANT _MAND-TOOL-BUDGET
144 CONSTANT _MAND-DISCLOSURE-BUDGET
152 CONSTANT _MAND-FLAGS
160 CONSTANT _MAND-PRACTICE-ID        \ RID-SIZE bytes
192 CONSTANT _MAND-INPUT-FACET-ID     \ RID-SIZE bytes
224 CONSTANT _MAND-DISCLOSURE-FACET-ID \ RID-SIZE bytes
256 CONSTANT MAND-SIZE

: MAND.MAGIC              ( mandate -- a ) _MAND-MAGIC + ;
: MAND.ABI                ( mandate -- a ) _MAND-ABI + ;
: MAND.SIZE               ( mandate -- a ) _MAND-SIZE + ;
: MAND.ID                 ( mandate -- id ) _MAND-ID + ;
: MAND.ACTIVATION-EPOCH   ( mandate -- a ) _MAND-ACTIVATION-EPOCH + ;
: MAND.PRINCIPAL          ( mandate -- a ) _MAND-PRINCIPAL + ;
: MAND.CONTEXT-ID         ( mandate -- a ) _MAND-CONTEXT-ID + ;
: MAND.CONTEXT-GENERATION ( mandate -- a ) _MAND-CONTEXT-GEN + ;
: MAND.EFFECTS            ( mandate -- a ) _MAND-EFFECTS + ;
: MAND.DISPOSITION        ( mandate -- a ) _MAND-DISPOSITION + ;
: MAND.EXPIRES-MS         ( mandate -- a ) _MAND-EXPIRES-MS + ;
: MAND.TIME-BUDGET-MS     ( mandate -- a ) _MAND-TIME-BUDGET-MS + ;
: MAND.MEMORY-BUDGET      ( mandate -- a ) _MAND-MEMORY-BUDGET + ;
: MAND.TOKEN-BUDGET       ( mandate -- a ) _MAND-TOKEN-BUDGET + ;
: MAND.TOOL-BUDGET        ( mandate -- a ) _MAND-TOOL-BUDGET + ;
: MAND.DISCLOSURE-BUDGET  ( mandate -- a ) _MAND-DISCLOSURE-BUDGET + ;
: MAND.FLAGS              ( mandate -- a ) _MAND-FLAGS + ;
: MAND.PRACTICE-ID        ( mandate -- id ) _MAND-PRACTICE-ID + ;
: MAND.INPUT-FACET-ID     ( mandate -- id ) _MAND-INPUT-FACET-ID + ;
: MAND.DISCLOSURE-FACET-ID ( mandate -- id ) _MAND-DISCLOSURE-FACET-ID + ;

: MAND-INIT  ( mandate -- )
    DUP MAND-SIZE 0 FILL
    MAND-MAGIC OVER MAND.MAGIC !
    MAND-ABI-VERSION OVER MAND.ABI !
    MAND-SIZE SWAP MAND.SIZE ! ;

: MAND-DISPOSITION-VALID?  ( disposition -- flag )
    DUP MAND-D-READ-ONLY < SWAP MAND-D-COMMIT > OR 0= ;

: MAND-EFFECT-MASK-VALID?  ( effects -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    MAND-EFFECTS-MASK INVERT AND 0= ;

: MAND-BUDGETS-VALID?  ( mandate -- flag )
    DUP MAND.TIME-BUDGET-MS @ 0< IF DROP 0 EXIT THEN
    DUP MAND.MEMORY-BUDGET @ 0< IF DROP 0 EXIT THEN
    DUP MAND.TOKEN-BUDGET @ 0< IF DROP 0 EXIT THEN
    DUP MAND.TOOL-BUDGET @ 0< IF DROP 0 EXIT THEN
    MAND.DISCLOSURE-BUDGET @ 0< 0= ;

: MAND-STRUCTURAL-VALID?  ( mandate -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP MAND.MAGIC @ MAND-MAGIC =
    OVER MAND.ABI @ MAND-ABI-VERSION = AND
    OVER MAND.SIZE @ MAND-SIZE >= AND
    OVER MAND.ID RID-PRESENT? AND
    OVER MAND.ACTIVATION-EPOCH @ 0> AND
    OVER MAND.PRINCIPAL @ 0> AND
    OVER MAND.CONTEXT-ID @ 0> AND
    OVER MAND.CONTEXT-GENERATION @ 0> AND
    OVER MAND.PRACTICE-ID RID-PRESENT? AND
    OVER MAND.INPUT-FACET-ID RID-PRESENT? AND
    OVER MAND.DISCLOSURE-FACET-ID RID-PRESENT? AND
    OVER MAND.EFFECTS @ MAND-EFFECT-MASK-VALID? AND
    OVER MAND.DISPOSITION @ MAND-DISPOSITION-VALID? AND
    OVER MAND.EXPIRES-MS @ 0< 0= AND
    SWAP MAND-BUDGETS-VALID? AND ;

: MAND-ACTIVE?  ( activation-epoch now-ms mandate -- flag )
    >R
    R@ MAND-STRUCTURAL-VALID? 0= IF 2DROP R> DROP 0 EXIT THEN
    SWAP R@ MAND.ACTIVATION-EPOCH @ = 0= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ MAND.EXPIRES-MS @ DUP 0= IF
        2DROP R> DROP -1 EXIT
    THEN
    < R> DROP ;

: MAND-EFFECTS-VALID?  ( effects mandate -- flag )
    >R
    DUP MAND-EFFECT-MASK-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    DUP R@ MAND.EFFECTS @ AND =
    R> DROP ;

: MAND-COMMIT-VALID?  ( effects activation-epoch now-ms mandate -- flag )
    >R
    2DUP R@ MAND-ACTIVE? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    2DROP
    R@ MAND.DISPOSITION @ MAND-D-COMMIT <> IF
        DROP R> DROP 0 EXIT
    THEN
    R@ MAND-EFFECTS-VALID?
    R> DROP ;

: MAND-CONTEXT-MATCH?  ( context-id generation mandate -- flag )
    >R
    SWAP R@ MAND.CONTEXT-ID @ =
    SWAP R> MAND.CONTEXT-GENERATION @ = AND ;

: MAND-PRACTICE-MATCH?  ( practice-id mandate -- flag )
    MAND.PRACTICE-ID RID= ;

: MAND-INPUT-FACET-MATCH?  ( facet-id mandate -- flag )
    MAND.INPUT-FACET-ID RID= ;

: MAND-DISCLOSURE-FACET-MATCH?  ( facet-id mandate -- flag )
    MAND.DISCLOSURE-FACET-ID RID= ;
