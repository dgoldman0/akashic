\ =====================================================================
\  sandbox-build.f - Compile and verify one sandbox plan
\ =====================================================================
\  SBOX-BUILD turns restricted source into a verified plan for a sealed
\  profile.  It compiles into an artifact sized from the profile, verifies
\  the artifact into an exactly measured plan, and keeps that plan in a
\  caller-owned build record until SBOX-BUILD-RELEASE, or until
\  SBOX-BUILD-TAKE hands it to the caller.  The artifact and both
\  workspaces exist only during the call; each is scrubbed and freed
\  before SBOX-BUILD returns.  SBOX-BUILD-VERIFY does the same for an
\  artifact the caller already holds.
\
\  A refused build holds no plan and records where it failed: the
\  compiler's diagnostic code and source span, or the verifier's detail
\  with the source span of the instruction it names.  The plan borrows
\  its profile, so the caller keeps the profile alive and unchanged, and
\  stops running the plan before releasing it.
\ =====================================================================

PROVIDED akashic-sbox-build

REQUIRE ../sandbox/compiler.f
REQUIRE ../sandbox/verifier.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Status
\ =====================================================================

0 CONSTANT SBOX-BUILD-S-OK
1 CONSTANT SBOX-BUILD-S-INVALID
2 CONSTANT SBOX-BUILD-S-STATE
3 CONSTANT SBOX-BUILD-S-COMPILE
4 CONSTANT SBOX-BUILD-S-VERIFY
5 CONSTANT SBOX-BUILD-S-NOMEM

\ =====================================================================
\  Caller-owned record
\ =====================================================================

0x5342584255494C44 CONSTANT _SBB-MAGIC  \ "SBXBUILD"

0 CONSTANT _SBB-EMPTY
1 CONSTANT _SBB-READY

  0 CONSTANT _SBB-MAGIC-OFF
  8 CONSTANT _SBB-SELF
 16 CONSTANT _SBB-STATE
 24 CONSTANT _SBB-PLAN
 32 CONSTANT _SBB-PLAN-U
 40 CONSTANT _SBB-STEP
 48 CONSTANT _SBB-CODE
 56 CONSTANT _SBB-OFFSET
 64 CONSTANT _SBB-LENGTH
\ Call scratch, zero outside SBOX-BUILD.
 72 CONSTANT _SBB-SOURCE-A
 80 CONSTANT _SBB-SOURCE-U
 88 CONSTANT _SBB-PROFILE
 96 CONSTANT _SBB-MEMORY-U
104 CONSTANT _SBB-ARTIFACT
112 CONSTANT _SBB-ARTIFACT-U
120 CONSTANT _SBB-WRITTEN
128 CONSTANT _SBB-COMPILER-WS
136 CONSTANT _SBB-COMPILER-KEEP
144 CONSTANT _SBB-VERIFIER-WS
152 CONSTANT _SBB-VERIFIER-WS-U
160 CONSTANT SBOX-BUILD-SIZE

: _SBB.MAGIC        ( build -- a ) _SBB-MAGIC-OFF + ;
: _SBB.SELF         ( build -- a ) _SBB-SELF + ;
: _SBB.STATE        ( build -- a ) _SBB-STATE + ;
: _SBB.PLAN         ( build -- a ) _SBB-PLAN + ;
: _SBB.PLAN-U       ( build -- a ) _SBB-PLAN-U + ;
: _SBB.STEP         ( build -- a ) _SBB-STEP + ;
: _SBB.CODE         ( build -- a ) _SBB-CODE + ;
: _SBB.OFFSET       ( build -- a ) _SBB-OFFSET + ;
: _SBB.LENGTH       ( build -- a ) _SBB-LENGTH + ;
: _SBB.SOURCE-A     ( build -- a ) _SBB-SOURCE-A + ;
: _SBB.SOURCE-U     ( build -- a ) _SBB-SOURCE-U + ;
: _SBB.PROFILE      ( build -- a ) _SBB-PROFILE + ;
: _SBB.MEMORY-U     ( build -- a ) _SBB-MEMORY-U + ;
: _SBB.ARTIFACT    ( build -- a ) _SBB-ARTIFACT + ;
: _SBB.ARTIFACT-U  ( build -- a ) _SBB-ARTIFACT-U + ;
: _SBB.WRITTEN      ( build -- a ) _SBB-WRITTEN + ;
: _SBB.COMPILER-WS  ( build -- a ) _SBB-COMPILER-WS + ;
: _SBB.COMPILER-KEEP  ( build -- a ) _SBB-COMPILER-KEEP + ;
: _SBB.VERIFIER-WS  ( build -- a ) _SBB-VERIFIER-WS + ;
: _SBB.VERIFIER-WS-U  ( build -- a ) _SBB-VERIFIER-WS-U + ;

: _SBB-SPAN?  ( build -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-BUILD-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    SBOX-BUILD-SIZE CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: SBOX-BUILD-VALID?  ( build -- flag )
    DUP _SBB-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SBB.MAGIC @ _SBB-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBB.SELF @ OVER <> IF DROP 0 EXIT THEN
    _SBB.STATE @ DUP _SBB-EMPTY = SWAP _SBB-READY = OR ;

: _SBB-CLEAR-ERROR  ( build -- )
    0 OVER _SBB.STEP !
    0 OVER _SBB.CODE !
    -1 OVER _SBB.OFFSET !
    0 SWAP _SBB.LENGTH ! ;

\ A record that holds a plan must be released first, so no plan is lost.
: SBOX-BUILD-INIT  ( build -- status )
    DUP _SBB-SPAN? 0= IF DROP SBOX-BUILD-S-INVALID EXIT THEN
    DUP SBOX-BUILD-VALID? IF
        DUP _SBB.STATE @ _SBB-READY = IF
            DROP SBOX-BUILD-S-STATE EXIT
        THEN
    THEN
    DUP SBOX-BUILD-SIZE 0 FILL
    DUP DUP _SBB.SELF !
    _SBB-EMPTY OVER _SBB.STATE !
    DUP _SBB-CLEAR-ERROR
    _SBB-MAGIC SWAP _SBB.MAGIC !
    SBOX-BUILD-S-OK ;

\ =====================================================================
\  Building
\ =====================================================================

: _SBB-DISCARD  ( address length -- )
    OVER 0= IF 2DROP EXIT THEN
    OVER SWAP 0 FILL FREE ;

\ Scrubs and frees everything the call allocated except a published plan,
\ then clears the call scratch.
: _SBB-CLEANUP  ( build -- )
    >R
    R@ _SBB.VERIFIER-WS @ R@ _SBB.VERIFIER-WS-U @ _SBB-DISCARD
    \ The compiler leaves only its diagnostic region behind.
    R@ _SBB.COMPILER-WS @ R@ _SBB.COMPILER-KEEP @ _SBB-DISCARD
    R@ _SBB.ARTIFACT @ R@ _SBB.ARTIFACT-U @ _SBB-DISCARD
    R@ _SBB.STATE @ _SBB-READY <> IF
        R@ _SBB.PLAN @ R@ _SBB.PLAN-U @ _SBB-DISCARD
        0 R@ _SBB.PLAN !
        0 R@ _SBB.PLAN-U !
    THEN
    R@ _SBB.SOURCE-A SBOX-BUILD-SIZE _SBB-SOURCE-A - 0 FILL
    R> DROP ;

: _SBB-COMPILE  ( build -- status )
    >R
    R@ _SBB.SOURCE-A @ R@ _SBB.SOURCE-U @
    R@ _SBB.PROFILE @ R@ _SBB.MEMORY-U @
    R@ _SBB.ARTIFACT @ R@ _SBB.ARTIFACT-U @
    R@ _SBB.COMPILER-WS @
    SBOX-COMPILE
    SWAP R@ _SBB.WRITTEN !
    0= IF R> DROP SBOX-BUILD-S-OK EXIT THEN
    \ A refusal without diagnostics came from the call's own spans.
    R@ _SBB.COMPILER-WS @ SBOX-COMPILER-ERROR@
    IF 2DROP DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    R@ _SBB.LENGTH ! R@ _SBB.OFFSET ! R@ _SBB.CODE !
    SBOX-BUILD-S-COMPILE R@ _SBB.STEP !
    R> DROP SBOX-BUILD-S-COMPILE ;

\ Verifier details that name an instruction, INSTRUCTION-FLAGS through
\ UNREACHABLE.  Their index counts instructions as the source map does.
: _SBB-INSTRUCTION-DETAIL?  ( detail -- flag )
    SBOX-VERIFIER-D-INSTRUCTION-FLAGS SBOX-VERIFIER-D-UNREACHABLE 1+
    WITHIN ;

: _SBB-VERIFY-FAILED  ( build -- status )
    >R
    R@ _SBB.VERIFIER-WS @ SBOX-VERIFIER-ERROR-DETAIL@
    \ A refusal without diagnostics came from the call's own spans.
    IF DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    SBOX-BUILD-S-VERIFY R@ _SBB.STEP !
    DUP R@ _SBB.CODE !
    \ Only compiled source has a source map.
    _SBB-INSTRUCTION-DETAIL? R@ _SBB.COMPILER-WS @ 0<> AND IF
        R@ _SBB.VERIFIER-WS @ SBOX-VERIFIER-ERROR-INDEX@ DROP
        R@ _SBB.COMPILER-WS @ SBOX-COMPILER-SOURCE-SPAN@
        IF 2DROP ELSE R@ _SBB.LENGTH ! R@ _SBB.OFFSET ! THEN
    THEN
    R> DROP SBOX-BUILD-S-VERIFY ;

: _SBB-VERIFY  ( build -- status )
    >R
    R@ _SBB.WRITTEN @ SBOX-PLAN-MEASURE
    IF DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    DUP R@ _SBB.PLAN-U !
    ALLOCATE IF DROP R> DROP SBOX-BUILD-S-NOMEM EXIT THEN
    R@ _SBB.PLAN !
    \ The artifact the compiler wrote measures the verifier's workspace.
    R@ _SBB.ARTIFACT @ R@ _SBB.WRITTEN @ SBOX-VERIFIER-WORKSPACE-MEASURE
    IF DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    DUP ALLOCATE IF 2DROP R> DROP SBOX-BUILD-S-NOMEM EXIT THEN
    \ No diagnostics from an earlier use of this memory may survive.
    TUCK SWAP DUP R@ _SBB.VERIFIER-WS-U ! 0 FILL
    R@ _SBB.VERIFIER-WS !
    R@ _SBB.ARTIFACT @ R@ _SBB.WRITTEN @
    R@ _SBB.PROFILE @
    R@ _SBB.PLAN @ R@ _SBB.PLAN-U @
    R@ _SBB.VERIFIER-WS @
    SBOX-VERIFY
    IF R@ _SBB-VERIFY-FAILED R> DROP EXIT THEN
    _SBB-READY R@ _SBB.STATE !
    R> DROP SBOX-BUILD-S-OK ;

: _SBB-RUN  ( build -- status )
    >R
    \ The host holds the profile, so an unusable one is its own mistake.
    R@ _SBB.PROFILE @ SBOX-PROFILE-VALID? 0= IF
        R> DROP SBOX-BUILD-S-INVALID EXIT
    THEN
    \ The source measures the artifact and the compiler's workspace.
    R@ _SBB.SOURCE-A @ R@ _SBB.SOURCE-U @ SBOX-COMPILER-ARTIFACT-MAX
    IF DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    DUP R@ _SBB.ARTIFACT-U !
    ALLOCATE IF DROP R> DROP SBOX-BUILD-S-NOMEM EXIT THEN
    R@ _SBB.ARTIFACT !
    R@ _SBB.SOURCE-A @ R@ _SBB.SOURCE-U @ SBOX-COMPILER-DIAGNOSTIC-MEASURE
    IF DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    R@ _SBB.COMPILER-KEEP !
    R@ _SBB.SOURCE-A @ R@ _SBB.SOURCE-U @ SBOX-COMPILER-WORKSPACE-MEASURE
    IF DROP R> DROP SBOX-BUILD-S-INVALID EXIT THEN
    ALLOCATE IF DROP R> DROP SBOX-BUILD-S-NOMEM EXIT THEN
    \ No diagnostics from an earlier use of this memory may survive.
    DUP SBOX-COMPILER-DIAGNOSTIC-SIZE 0 FILL
    R@ _SBB.COMPILER-WS !
    R@ _SBB-COMPILE ?DUP IF R> DROP EXIT THEN
    R@ _SBB-VERIFY
    R> DROP ;

\ Builds SOURCE for PROFILE with MEMORY-U bytes of guest memory.  The
\ record must not hold a plan.
: SBOX-BUILD  ( source source-u profile memory-u build -- status )
    DUP SBOX-BUILD-VALID? 0= IF
        2DROP 2DROP DROP SBOX-BUILD-S-INVALID EXIT
    THEN
    DUP _SBB.STATE @ _SBB-READY = IF
        2DROP 2DROP DROP SBOX-BUILD-S-STATE EXIT
    THEN
    >R
    R@ _SBB.MEMORY-U ! R@ _SBB.PROFILE !
    R@ _SBB.SOURCE-U ! R@ _SBB.SOURCE-A !
    R@ _SBB-CLEAR-ERROR
    R@ _SBB-RUN
    R@ _SBB-CLEANUP
    R> DROP ;

\ Verifies ARTIFACT, which stays the caller's, into a plan for PROFILE.
\ The record must not hold a plan.  A refusal records the verifier's
\ detail without a source span.
: SBOX-BUILD-VERIFY  ( artifact artifact-u profile build -- status )
    DUP SBOX-BUILD-VALID? 0= IF
        2DROP 2DROP SBOX-BUILD-S-INVALID EXIT
    THEN
    DUP _SBB.STATE @ _SBB-READY = IF
        2DROP 2DROP SBOX-BUILD-S-STATE EXIT
    THEN
    >R
    R@ _SBB.PROFILE !
    R@ _SBB.WRITTEN ! R@ _SBB.ARTIFACT !
    R@ _SBB-CLEAR-ERROR
    R@ _SBB.PROFILE @ SBOX-PROFILE-VALID? IF
        R@ _SBB-VERIFY
    ELSE
        SBOX-BUILD-S-INVALID
    THEN
    \ Cleanup frees only what the call allocated.
    0 R@ _SBB.ARTIFACT !
    R@ _SBB-CLEANUP
    R> DROP ;

\ =====================================================================
\  Results and release
\ =====================================================================

\ The plan of a successful build.  The record keeps owning it.
: SBOX-BUILD-PLAN@  ( build -- plan|0 status )
    DUP SBOX-BUILD-VALID? 0= IF DROP 0 SBOX-BUILD-S-INVALID EXIT THEN
    DUP _SBB.STATE @ _SBB-READY <> IF DROP 0 SBOX-BUILD-S-STATE EXIT THEN
    _SBB.PLAN @ SBOX-BUILD-S-OK ;

\ Where the latest build failed.  STEP is SBOX-BUILD-S-COMPILE with a
\ SBOX-COMPILER-E- code, SBOX-BUILD-S-VERIFY with a SBOX-VERIFIER-D-
\ detail, or 0 when no step failed.  OFFSET is -1 when no source span is
\ known.
: SBOX-BUILD-ERROR@  ( build -- step code offset length status )
    DUP SBOX-BUILD-VALID? 0= IF
        DROP 0 0 -1 0 SBOX-BUILD-S-INVALID EXIT
    THEN
    >R
    R@ _SBB.STEP @ R@ _SBB.CODE @ R@ _SBB.OFFSET @ R@ _SBB.LENGTH @
    R> DROP SBOX-BUILD-S-OK ;

\ Hands a successful build's plan to the caller, who then owns PLAN-U
\ allocated bytes at PLAN and frees them with SBOX-BUILD-PLAN-FREE.  The
\ record is then empty.
: SBOX-BUILD-TAKE  ( build -- plan plan-u status )
    DUP SBOX-BUILD-VALID? 0= IF DROP 0 0 SBOX-BUILD-S-INVALID EXIT THEN
    DUP _SBB.STATE @ _SBB-READY <> IF DROP 0 0 SBOX-BUILD-S-STATE EXIT THEN
    >R
    R@ _SBB.PLAN @ R@ _SBB.PLAN-U @
    0 R@ _SBB.PLAN !
    0 R@ _SBB.PLAN-U !
    _SBB-EMPTY R@ _SBB.STATE !
    R> _SBB-CLEAR-ERROR
    SBOX-BUILD-S-OK ;

\ Releases and frees a plan SBOX-BUILD-TAKE handed over.  Nothing may
\ still run it.
: SBOX-BUILD-PLAN-FREE  ( plan plan-u -- )
    OVER SBOX-PLAN-RELEASE DROP _SBB-DISCARD ;

\ Releases a successful build's plan, which nothing may still run, and
\ clears the diagnostics.  The record is then empty.
: SBOX-BUILD-RELEASE  ( build -- status )
    DUP SBOX-BUILD-VALID? 0= IF DROP SBOX-BUILD-S-INVALID EXIT THEN
    >R
    SBOX-BUILD-S-OK
    R@ _SBB.STATE @ _SBB-READY = IF
        R@ _SBB.PLAN @ SBOX-PLAN-RELEASE IF DROP SBOX-BUILD-S-INVALID THEN
        R@ _SBB.PLAN @ R@ _SBB.PLAN-U @ _SBB-DISCARD
        0 R@ _SBB.PLAN !
        0 R@ _SBB.PLAN-U !
        _SBB-EMPTY R@ _SBB.STATE !
    THEN
    R@ _SBB-CLEAR-ERROR
    R> DROP ;
