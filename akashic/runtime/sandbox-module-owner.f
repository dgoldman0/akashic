\ =====================================================================
\  sandbox-module-owner.f - The live table of installed sandbox modules
\ =====================================================================
\  The owner holds every installed module revision a host knows, keyed
\  by its exact (RID, positive revision), for one profile it borrows.
\  Each module has its declaration (docs/sandbox/declaration-format.md),
\  and, once verified, the plan that runs it.  The owner owns the module
\  records, the declaration copies and the plans; the caller owns the
\  owner record and keeps the profile alive until RELEASE.  There is no
\  fixed capacity: the table grows as modules are added.
\
\  A module is in one of four states:
\
\    DECLARED     known by its declaration; not yet verified.
\    VERIFIED     its artifact passed verification against the
\                 declaration, and the owner holds its plan.
\    QUARANTINED  its artifact or stored object failed a check.  It is
\                 never run, and stays until it is removed.
\    RETIRED      no longer run.  Its plan is freed once unpinned.
\
\  A host adds a module it has just built as VERIFIED, handing over the
\  plan it verified, so nothing is verified twice.  A module loaded from
\  storage starts DECLARED, and VERIFY checks its artifact on first use.
\  Every run pins the module's plan and unpins it when the run ends; a
\  pinned module cannot be removed, and the owner cannot be released
\  while any module is pinned.
\
\  A module handle is the address of its record, valid until REMOVE.
\  The owner is caller-serialized and keeps no module state of its own.
\ =====================================================================

PROVIDED akashic-sbox-mod-owner

REQUIRE identity.f
REQUIRE sandbox-build.f
REQUIRE sandbox-declaration.f
REQUIRE ../sandbox/digest.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

0 CONSTANT SBOX-MODULE-S-OK
1 CONSTANT SBOX-MODULE-S-INVALID
2 CONSTANT SBOX-MODULE-S-NOMEM
3 CONSTANT SBOX-MODULE-S-DUPLICATE
4 CONSTANT SBOX-MODULE-S-STATE
5 CONSTANT SBOX-MODULE-S-BUSY
6 CONSTANT SBOX-MODULE-S-PROFILE
7 CONSTANT SBOX-MODULE-S-MISMATCH
8 CONSTANT SBOX-MODULE-S-VERIFY

1 CONSTANT SBOX-MODULE-DECLARED
2 CONSTANT SBOX-MODULE-VERIFIED
3 CONSTANT SBOX-MODULE-QUARANTINED
4 CONSTANT SBOX-MODULE-RETIRED

\ Why a module is quarantined.
0 CONSTANT SBOX-MODULE-Q-NONE
\ The artifact is not the one the declaration names.
1 CONSTANT SBOX-MODULE-Q-ARTIFACT
\ The verifier refused the artifact; the detail is its SBOX-VERIFIER-D-.
2 CONSTANT SBOX-MODULE-Q-VERIFY
\ The verified plan does not match the declaration's entries.
3 CONSTANT SBOX-MODULE-Q-MISMATCH
\ The store found the module's stored object corrupt.
4 CONSTANT SBOX-MODULE-Q-STORE

\ =====================================================================
\  Records
\ =====================================================================

0x5342584D4F444F57 CONSTANT _SMO-MAGIC  \ "SBXMODOW"
0x5342584D4F44554C CONSTANT _SMM-MAGIC  \ "SBXMODUL"

\ The owner, in caller memory: its table of module records in key order,
\ a build record for VERIFY, and digest scratch.
   0 CONSTANT _SMO-MAGIC-OFF
   8 CONSTANT _SMO-SELF
  16 CONSTANT _SMO-PROFILE
  24 CONSTANT _SMO-LIST
  32 CONSTANT _SMO-COUNT
  40 CONSTANT _SMO-ROOM
  48 CONSTANT _SMO-BUILD
_SMO-BUILD SBOX-BUILD-SIZE + CONSTANT _SMO-DECL-WS
_SMO-DECL-WS SBOX-DECL-WORKSPACE-SIZE + CONSTANT _SMO-DIGEST-WS
_SMO-DIGEST-WS SBOX-DIGEST-WORKSPACE-SIZE + CONSTANT _SMO-DIGEST
_SMO-DIGEST 32 + CONSTANT SBOX-MODULE-OWNER-SIZE

: _SMO.MAGIC      ( owner -- a ) _SMO-MAGIC-OFF + ;
: _SMO.SELF       ( owner -- a ) _SMO-SELF + ;
: _SMO.PROFILE    ( owner -- a ) _SMO-PROFILE + ;
: _SMO.LIST       ( owner -- a ) _SMO-LIST + ;
: _SMO.COUNT      ( owner -- a ) _SMO-COUNT + ;
: _SMO.ROOM       ( owner -- a ) _SMO-ROOM + ;
: _SMO.BUILD      ( owner -- build ) _SMO-BUILD + ;
: _SMO.DECL-WS    ( owner -- workspace ) _SMO-DECL-WS + ;
: _SMO.DIGEST-WS  ( owner -- workspace ) _SMO-DIGEST-WS + ;
: _SMO.DIGEST     ( owner -- digest ) _SMO-DIGEST + ;

\ One module, in its own allocation.
  0 CONSTANT _SMM-MAGIC-OFF
  8 CONSTANT _SMM-SELF
 16 CONSTANT _SMM-OWNER
 24 CONSTANT _SMM-STATE
 32 CONSTANT _SMM-PINS
 40 CONSTANT _SMM-REVISION
 48 CONSTANT _SMM-RID
 80 CONSTANT _SMM-DECL
 88 CONSTANT _SMM-DECL-U
 96 CONSTANT _SMM-DECL-DIGEST
128 CONSTANT _SMM-PLAN
136 CONSTANT _SMM-PLAN-U
144 CONSTANT _SMM-REASON
152 CONSTANT _SMM-DETAIL
160 CONSTANT _SMM-SIZE

: _SMM.MAGIC        ( module -- a ) _SMM-MAGIC-OFF + ;
: _SMM.SELF         ( module -- a ) _SMM-SELF + ;
: _SMM.OWNER        ( module -- a ) _SMM-OWNER + ;
: _SMM.STATE        ( module -- a ) _SMM-STATE + ;
: _SMM.PINS         ( module -- a ) _SMM-PINS + ;
: _SMM.REVISION     ( module -- a ) _SMM-REVISION + ;
: _SMM.RID          ( module -- rid ) _SMM-RID + ;
: _SMM.DECL         ( module -- a ) _SMM-DECL + ;
: _SMM.DECL-U       ( module -- a ) _SMM-DECL-U + ;
: _SMM.DECL-DIGEST  ( module -- digest ) _SMM-DECL-DIGEST + ;
: _SMM.PLAN         ( module -- a ) _SMM-PLAN + ;
: _SMM.PLAN-U       ( module -- a ) _SMM-PLAN-U + ;
: _SMM.REASON       ( module -- a ) _SMM-REASON + ;
: _SMM.DETAIL       ( module -- a ) _SMM-DETAIL + ;

: _SMO-SPAN?  ( address length -- flag )
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: SBOX-MODULE-OWNER-VALID?  ( owner -- flag )
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-MODULE-OWNER-SIZE _SMO-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SMO.MAGIC @ _SMO-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SMO.SELF @ = ;

: _SMM-VALID?  ( module -- flag )
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _SMM-SIZE _SMO-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SMM.MAGIC @ _SMM-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SMM.SELF @ = ;

\ A module this owner holds.
: _SMM-OURS?  ( module owner -- flag )
    OVER _SMM-VALID? 0= IF 2DROP 0 EXIT THEN
    SWAP _SMM.OWNER @ = ;

: _SMO-NTH  ( index owner -- module ) _SMO.LIST @ SWAP 8 * + @ ;

: _SMO-DROP3>STATUS  ( x1 x2 x3 status -- status ) >R 2DROP DROP R> ;
: _SMO-DROP4>STATUS  ( x1 x2 x3 x4 status -- status ) >R 2DROP 2DROP R> ;

\ =====================================================================
\  Keys
\ =====================================================================

\ Orders (RID, REVISION) against MODULE's key: RID bytes, then revision.
: _SMO-KEY-COMPARE  ( rid revision module -- n )
    ROT RID-SIZE 2 PICK _SMM.RID RID-SIZE COMPARE ?DUP IF NIP NIP EXIT THEN
    _SMM.REVISION @ 2DUP = IF 2DROP 0 EXIT THEN
    < IF -1 ELSE 1 THEN ;

\ Where (RID, REVISION) is or belongs in the ordered table.
: _SMO-SEARCH  ( rid revision owner -- index found? )
    >R 0 R@ _SMO.COUNT @
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        4 PICK 4 PICK 2 PICK R@ _SMO-NTH _SMO-KEY-COMPARE
        DUP 0= IF DROP NIP NIP NIP NIP R> DROP -1 EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    DROP NIP NIP R> DROP 0 ;

: _SMO-KEY?  ( rid revision -- flag )
    1 < IF DROP 0 EXIT THEN
    DUP RID-SIZE _SMO-SPAN? 0= IF DROP 0 EXIT THEN
    RID-PRESENT? ;

\ =====================================================================
\  The table
\ =====================================================================

\ Room for at least one more module, doubling the table when it is full.
: _SMO-ROOM  ( owner -- status )
    DUP _SMO.COUNT @ OVER _SMO.ROOM @ < IF DROP SBOX-MODULE-S-OK EXIT THEN
    >R
    R@ _SMO.ROOM @ 2 * 8 MAX
    DUP 8 * ALLOCATE IF 2DROP R> DROP SBOX-MODULE-S-NOMEM EXIT THEN
    DUP 2 PICK 8 * 0 FILL
    R@ _SMO.LIST @ ?DUP IF
        OVER R@ _SMO.COUNT @ 8 * MOVE
        R@ _SMO.LIST @ R@ _SMO.ROOM @ 8 * 0 FILL
        R@ _SMO.LIST @ FREE
    THEN
    R@ _SMO.LIST !
    R> _SMO.ROOM !
    SBOX-MODULE-S-OK ;

: _SMO-INSERT  ( module index owner -- )
    >R
    R@ _SMO.LIST @ OVER 8 * +
    DUP DUP 8 + R@ _SMO.COUNT @ 4 PICK - 8 * MOVE
    NIP !
    1 R> _SMO.COUNT +! ;

: _SMO-DELETE  ( index owner -- )
    >R
    R@ _SMO.COUNT @ OVER - 1- 8 *
    SWAP 8 * R@ _SMO.LIST @ +
    DUP 8 + SWAP ROT MOVE
    -1 R@ _SMO.COUNT +!
    0 R@ _SMO.LIST @ R> _SMO.COUNT @ 8 * + ! ;

\ =====================================================================
\  Plans and declarations
\ =====================================================================

: _SMM-FREE-PLAN  ( module -- )
    DUP _SMM.PLAN @ ?DUP IF
        OVER _SMM.PLAN-U @ SBOX-BUILD-PLAN-FREE
    THEN
    0 OVER _SMM.PLAN !
    0 SWAP _SMM.PLAN-U ! ;

: _SMM-FREE  ( module -- )
    DUP _SMM-FREE-PLAN
    DUP _SMM.DECL @ ?DUP IF
        DUP 2 PICK _SMM.DECL-U @ 0 FILL FREE
    THEN
    DUP _SMM-SIZE 0 FILL
    FREE ;

\ The plan's entries are exactly the declared ones, in order, with the
\ same names and signatures.
: _SMO-ENTRIES-MATCH?  ( declaration plan -- flag )
    OVER SBOX-DECL-ENTRY-N@ OVER SBOX-PLAN-ENTRY-N@ <> IF 2DROP 0 EXIT THEN
    OVER SBOX-DECL-ENTRY-N@ 0 ?DO
        I 2 PICK SBOX-DECL-ENTRY-NAME$
        I 3 PICK SBOX-PLAN-ENTRY-NAME$ COMPARE IF 2DROP 0 UNLOOP EXIT THEN
        I 2 PICK SBOX-DECL-ENTRY-SIGNATURE@
        I 2 PICK SBOX-PLAN-ENTRY-SIGNATURE@ 0= IF
            2DROP 2DROP 0 UNLOOP EXIT
        THEN
        <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ PLAN runs DECLARATION: it borrows the owner's profile, comes from the
\ declared artifact, and has exactly the declared entries.
: _SMO-PLAN-STATUS  ( declaration plan owner -- status )
    >R
    DUP SBOX-PLAN-PROFILE@ R> _SMO.PROFILE @ <> IF
        2DROP SBOX-MODULE-S-PROFILE EXIT
    THEN
    DUP SBOX-PLAN-ARTIFACT-DIGEST@ 32
        3 PICK SBOX-DECL-ARTIFACT-DIGEST@ 32 COMPARE IF
        2DROP SBOX-MODULE-S-MISMATCH EXIT
    THEN
    _SMO-ENTRIES-MATCH? IF SBOX-MODULE-S-OK ELSE SBOX-MODULE-S-MISMATCH THEN ;

: _SMM-QUARANTINE  ( reason detail module -- )
    >R
    R@ _SMM.DETAIL ! R@ _SMM.REASON !
    R@ _SMM-FREE-PLAN
    SBOX-MODULE-QUARANTINED R> _SMM.STATE ! ;

\ A fresh record for (RID, REVISION) in STATE.
: _SMO-NEW  ( rid revision state owner -- module|0 )
    _SMM-SIZE ALLOCATE IF 2DROP 2DROP DROP 0 EXIT THEN
    DUP _SMM-SIZE 0 FILL
    _SMM-MAGIC OVER _SMM.MAGIC !
    DUP DUP _SMM.SELF !
    TUCK _SMM.OWNER !
    TUCK _SMM.STATE !
    TUCK _SMM.REVISION !
    TUCK _SMM.RID RID-COPY ;

\ =====================================================================
\  Reading one module
\ =====================================================================

: SBOX-MODULE-STATE@  ( module -- state|0 )
    DUP _SMM-VALID? IF _SMM.STATE @ ELSE DROP 0 THEN ;

: SBOX-MODULE-KEY@  ( module -- rid revision )
    DUP _SMM.RID SWAP _SMM.REVISION @ ;

\ The declaration, or 0 0 for a module quarantined by its key.
: SBOX-MODULE-DECLARATION$  ( module -- declaration declaration-u )
    DUP _SMM.DECL @ SWAP _SMM.DECL-U @ ;

\ The declaration's digest, or 0 without a declaration.
: SBOX-MODULE-DECLARATION-DIGEST@  ( module -- digest|0 )
    DUP _SMM.DECL @ IF _SMM.DECL-DIGEST ELSE DROP 0 THEN ;

: SBOX-MODULE-PINS@  ( module -- n ) _SMM.PINS @ ;

: SBOX-MODULE-REASON@  ( module -- reason detail )
    DUP _SMM.REASON @ SWAP _SMM.DETAIL @ ;

\ =====================================================================
\  Owner lifecycle
\ =====================================================================

\ Binds OWNER, SBOX-MODULE-OWNER-SIZE cell-aligned bytes, to PROFILE,
\ which every module must name and which stays the caller's.  An owner
\ that still holds modules must be released first.
: SBOX-MODULE-OWNER-INIT  ( profile owner -- status )
    DUP 0= OVER 7 AND OR IF 2DROP SBOX-MODULE-S-INVALID EXIT THEN
    DUP SBOX-MODULE-OWNER-SIZE _SMO-SPAN? 0= IF
        2DROP SBOX-MODULE-S-INVALID EXIT
    THEN
    DUP SBOX-MODULE-OWNER-VALID? IF 2DROP SBOX-MODULE-S-STATE EXIT THEN
    OVER SBOX-PROFILE-VALID? 0= IF 2DROP SBOX-MODULE-S-INVALID EXIT THEN
    OVER SBOX-PROFILE-SIZE 2 PICK SBOX-MODULE-OWNER-SIZE MSPAN-OVERLAP? IF
        2DROP SBOX-MODULE-S-INVALID EXIT
    THEN
    DUP SBOX-MODULE-OWNER-SIZE 0 FILL
    DUP _SMO.BUILD SBOX-BUILD-INIT IF 2DROP SBOX-MODULE-S-INVALID EXIT THEN
    TUCK _SMO.PROFILE !
    DUP DUP _SMO.SELF !
    _SMO-MAGIC SWAP _SMO.MAGIC !
    SBOX-MODULE-S-OK ;

\ Frees every module and clears the owner.  No module may be pinned.
: SBOX-MODULE-OWNER-RELEASE  ( owner -- status )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF DROP SBOX-MODULE-S-INVALID EXIT THEN
    DUP _SMO.COUNT @ 0 ?DO
        I OVER _SMO-NTH _SMM.PINS @ IF
            DROP SBOX-MODULE-S-BUSY UNLOOP EXIT
        THEN
    LOOP
    DUP _SMO.COUNT @ 0 ?DO I OVER _SMO-NTH _SMM-FREE LOOP
    DUP _SMO.LIST @ ?DUP IF
        DUP 2 PICK _SMO.ROOM @ 8 * 0 FILL FREE
    THEN
    DUP _SMO.BUILD SBOX-BUILD-RELEASE DROP
    SBOX-MODULE-OWNER-SIZE 0 FILL
    SBOX-MODULE-S-OK ;

\ =====================================================================
\  Adding
\ =====================================================================

\ Adds the module DECLARATION describes.  With BUILD 0 it is DECLARED.
\ Otherwise BUILD holds the plan the caller just verified for it, and the
\ module takes that plan and is VERIFIED; on a refusal the build keeps
\ it.  The declaration is copied.
: SBOX-MODULE-ADD
  ( declaration declaration-u build|0 owner -- module|0 status )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF
        SBOX-MODULE-S-INVALID _SMO-DROP4>STATUS 0 SWAP EXIT
    THEN
    >R
    \ Validating also gives the declaration's digest.
    2 PICK 2 PICK R@ _SMO.DIGEST R@ _SMO.DECL-WS SBOX-DECL-DIGEST IF
        DROP 2DROP R> DROP 0 SBOX-MODULE-S-INVALID EXIT
    THEN
    2 PICK SBOX-DECL-PROFILE-DIGEST@ R@ _SMO.PROFILE @ SBOX-PROFILE-DIGEST=
        0= IF
        DROP 2DROP R> DROP 0 SBOX-MODULE-S-PROFILE EXIT
    THEN
    2 PICK SBOX-DECL-MODULE@ R@ _SMO-SEARCH NIP IF
        DROP 2DROP R> DROP 0 SBOX-MODULE-S-DUPLICATE EXIT
    THEN
    DUP IF
        DUP SBOX-BUILD-PLAN@ IF
            2DROP 2DROP R> DROP 0 SBOX-MODULE-S-STATE EXIT
        THEN
        3 PICK SWAP R@ _SMO-PLAN-STATUS ?DUP IF
            >R DROP 2DROP R> R> DROP 0 SWAP EXIT
        THEN
    THEN
    R@ _SMO-ROOM ?DUP IF >R DROP 2DROP R> R> DROP 0 SWAP EXIT THEN
    2 PICK SBOX-DECL-MODULE@ SBOX-MODULE-DECLARED R@ _SMO-NEW
    ?DUP 0= IF DROP 2DROP R> DROP 0 SBOX-MODULE-S-NOMEM EXIT THEN
    \ The declaration copy.
    2 PICK ALLOCATE IF
        DROP _SMM-FREE DROP 2DROP R> DROP 0 SBOX-MODULE-S-NOMEM EXIT
    THEN
    4 PICK OVER 5 PICK MOVE
    OVER _SMM.DECL !
    2 PICK OVER _SMM.DECL-U !
    R@ _SMO.DIGEST OVER _SMM.DECL-DIGEST 32 MOVE
    \ The verified plan, taken from the build.
    SWAP ?DUP IF
        SBOX-BUILD-TAKE DROP
        2 PICK _SMM.PLAN-U ! OVER _SMM.PLAN !
        SBOX-MODULE-VERIFIED OVER _SMM.STATE !
    THEN
    NIP NIP
    DUP SBOX-MODULE-KEY@ R@ _SMO-SEARCH DROP
    OVER SWAP R> _SMO-INSERT
    SBOX-MODULE-S-OK ;

\ Adds a QUARANTINED module the host knows only by its key, because its
\ stored object is unreadable.  REASON says why.
: SBOX-MODULE-ADD-QUARANTINED  ( rid revision reason owner -- module|0 status )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF
        SBOX-MODULE-S-INVALID _SMO-DROP4>STATUS 0 SWAP EXIT
    THEN
    >R
    DUP SBOX-MODULE-Q-ARTIFACT SBOX-MODULE-Q-STORE 1+ WITHIN 0=
    3 PICK 3 PICK _SMO-KEY? 0= OR IF
        DROP 2DROP R> DROP 0 SBOX-MODULE-S-INVALID EXIT
    THEN
    2 PICK 2 PICK R@ _SMO-SEARCH NIP IF
        DROP 2DROP R> DROP 0 SBOX-MODULE-S-DUPLICATE EXIT
    THEN
    R@ _SMO-ROOM ?DUP IF >R DROP 2DROP R> R> DROP 0 SWAP EXIT THEN
    2 PICK 2 PICK SBOX-MODULE-QUARANTINED R@ _SMO-NEW
    ?DUP 0= IF DROP 2DROP R> DROP 0 SBOX-MODULE-S-NOMEM EXIT THEN
    TUCK _SMM.REASON !
    NIP NIP
    DUP SBOX-MODULE-KEY@ R@ _SMO-SEARCH DROP
    OVER SWAP R> _SMO-INSERT
    SBOX-MODULE-S-OK ;

\ =====================================================================
\  Finding and listing
\ =====================================================================

\ The module with exactly this key.  There is no "latest" lookup.
: SBOX-MODULE-FIND  ( rid revision owner -- module|0 )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF DROP 2DROP 0 EXIT THEN
    2 PICK 2 PICK _SMO-KEY? 0= IF DROP 2DROP 0 EXIT THEN
    >R R@ _SMO-SEARCH IF R> _SMO-NTH ELSE DROP R> DROP 0 THEN ;

: SBOX-MODULE-COUNT@  ( owner -- n )
    DUP SBOX-MODULE-OWNER-VALID? IF _SMO.COUNT @ ELSE DROP 0 THEN ;

\ The module at INDEX in key order.
: SBOX-MODULE-NTH  ( index owner -- module|0 )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF 2DROP 0 EXIT THEN
    OVER 0 2 PICK _SMO.COUNT @ WITHIN 0= IF 2DROP 0 EXIT THEN
    _SMO-NTH ;

\ =====================================================================
\  One module
\ =====================================================================

\ Verifies a DECLARED module's ARTIFACT, which stays the caller's.  An
\ artifact that is not the declared one, that the verifier refuses, or
\ whose entries differ from the declaration quarantines the module.
: SBOX-MODULE-VERIFY  ( artifact artifact-u module owner -- status )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF
        SBOX-MODULE-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN
    2DUP _SMM-OURS? 0= IF SBOX-MODULE-S-INVALID _SMO-DROP4>STATUS EXIT THEN
    OVER _SMM.STATE @ SBOX-MODULE-DECLARED <> IF
        SBOX-MODULE-S-STATE _SMO-DROP4>STATUS EXIT
    THEN
    3 PICK 3 PICK _SMO-SPAN? 0= IF
        SBOX-MODULE-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN
    \ The owner's build record is empty between calls.
    DUP _SMO.BUILD SBOX-BUILD-PLAN@ NIP SBOX-BUILD-S-STATE <> IF
        SBOX-MODULE-S-STATE _SMO-DROP4>STATUS EXIT
    THEN
    3 PICK 3 PICK 2 PICK _SMO.DIGEST 3 PICK _SMO.DIGEST-WS
        SBOX-DIGEST-ARTIFACT IF
        SBOX-MODULE-S-INVALID _SMO-DROP4>STATUS EXIT
    THEN
    DUP _SMO.DIGEST 32 3 PICK _SMM.DECL @ SBOX-DECL-ARTIFACT-DIGEST@ 32
        COMPARE IF
        DROP SBOX-MODULE-Q-ARTIFACT 0 ROT _SMM-QUARANTINE
        2DROP SBOX-MODULE-S-MISMATCH EXIT
    THEN
    3 PICK 3 PICK 2 PICK _SMO.PROFILE @ 3 PICK _SMO.BUILD SBOX-BUILD-VERIFY
    DUP SBOX-BUILD-S-NOMEM = IF
        DROP SBOX-MODULE-S-NOMEM _SMO-DROP4>STATUS EXIT
    THEN
    IF
        \ The artifact is the declared one, so the refusal is its own.
        DUP _SMO.BUILD SBOX-BUILD-ERROR@ DROP 2DROP NIP
        SBOX-MODULE-Q-VERIFY SWAP 3 PICK _SMM-QUARANTINE
        SBOX-MODULE-S-VERIFY _SMO-DROP4>STATUS EXIT
    THEN
    OVER _SMM.DECL @ OVER _SMO.BUILD SBOX-BUILD-PLAN@ DROP 2 PICK
        _SMO-PLAN-STATUS IF
        DUP _SMO.BUILD SBOX-BUILD-RELEASE DROP
        SBOX-MODULE-Q-MISMATCH 0 3 PICK _SMM-QUARANTINE
        SBOX-MODULE-S-MISMATCH _SMO-DROP4>STATUS EXIT
    THEN
    DUP _SMO.BUILD SBOX-BUILD-TAKE DROP
    3 PICK _SMM.PLAN-U ! 2 PICK _SMM.PLAN !
    SBOX-MODULE-VERIFIED 2 PICK _SMM.STATE !
    SBOX-MODULE-S-OK _SMO-DROP4>STATUS ;

\ Pins a VERIFIED module's plan for one run.
: SBOX-MODULE-PIN  ( module -- plan|0 status )
    DUP _SMM-VALID? 0= IF DROP 0 SBOX-MODULE-S-INVALID EXIT THEN
    DUP _SMM.STATE @ SBOX-MODULE-VERIFIED <> IF
        DROP 0 SBOX-MODULE-S-STATE EXIT
    THEN
    1 OVER _SMM.PINS +!
    _SMM.PLAN @ SBOX-MODULE-S-OK ;

\ Ends one run's pin.  A RETIRED module's plan is freed with its last.
: SBOX-MODULE-UNPIN  ( module -- status )
    DUP _SMM-VALID? 0= IF DROP SBOX-MODULE-S-INVALID EXIT THEN
    DUP _SMM.PINS @ 1 < IF DROP SBOX-MODULE-S-STATE EXIT THEN
    -1 OVER _SMM.PINS +!
    DUP _SMM.PINS @ 0= OVER _SMM.STATE @ SBOX-MODULE-RETIRED = AND IF
        DUP _SMM-FREE-PLAN
    THEN
    DROP SBOX-MODULE-S-OK ;

\ Stops a module from running again.  Its plan is freed now, or by the
\ last UNPIN.
: SBOX-MODULE-RETIRE  ( module -- status )
    DUP _SMM-VALID? 0= IF DROP SBOX-MODULE-S-INVALID EXIT THEN
    SBOX-MODULE-RETIRED OVER _SMM.STATE !
    DUP _SMM.PINS @ 0= IF DUP _SMM-FREE-PLAN THEN
    DROP SBOX-MODULE-S-OK ;

\ Forgets an unpinned module and frees everything it held.  Its handle
\ is then invalid.
: SBOX-MODULE-REMOVE  ( module owner -- status )
    DUP SBOX-MODULE-OWNER-VALID? 0= IF 2DROP SBOX-MODULE-S-INVALID EXIT THEN
    2DUP _SMM-OURS? 0= IF 2DROP SBOX-MODULE-S-INVALID EXIT THEN
    OVER _SMM.PINS @ IF 2DROP SBOX-MODULE-S-BUSY EXIT THEN
    OVER SBOX-MODULE-KEY@ 2 PICK _SMO-SEARCH DROP
    OVER _SMO-DELETE
    DROP _SMM-FREE
    SBOX-MODULE-S-OK ;
