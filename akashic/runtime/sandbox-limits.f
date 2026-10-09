\ =====================================================================
\  sandbox-limits.f - One sandbox limit record and its narrowing
\ =====================================================================
\  One record holds every limit on a sandbox invocation: the instruction,
\  value-operation and copy budgets, the wall-clock time a job may take
\  from submission, and the ten value limits of sandbox/value.f.  Each
\  source of policy narrows it: the host's own policy, the module's
\  profile, its declaration, a grant and the request.  The effective
\  limit of a field is the smallest any source sets, so no source can
\  raise a limit another source has set.
\
\  BEGIN, CAP and SEAL build a record.  BEGIN leaves every field
\  unbounded, so a source caps only the fields it constrains.  MEET and
\  PROFILE-MEET narrow a sealed record in place.  MATERIALIZE turns a
\  record whose fields are all bounded into the sealed value limits and
\  the three budgets that SBOX-HOST-INIT takes, so a host's own policy
\  must bound every field.  The job service reads the wall-clock limit
\  itself.
\
\  The record is caller-owned and aligned, and holds no pointers.  There
\  is no Desk, Agent, declaration, grant, schema or persistence here.
\ =====================================================================

PROVIDED akashic-sbox-limits

REQUIRE ../sandbox/value.f
REQUIRE ../sandbox/profile.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Status and fields
\ =====================================================================

0 CONSTANT SBOX-LIMITS-S-OK
1 CONSTANT SBOX-LIMITS-S-INVALID
2 CONSTANT SBOX-LIMITS-S-STATE
3 CONSTANT SBOX-LIMITS-S-RANGE
4 CONSTANT SBOX-LIMITS-S-UNBOUNDED
5 CONSTANT SBOX-LIMITS-S-PROFILE
6 CONSTANT SBOX-LIMITS-S-VALUE
7 CONSTANT SBOX-LIMITS-S-ALIAS

0 CONSTANT SBOX-LIMIT-INSTRUCTION-BUDGET
1 CONSTANT SBOX-LIMIT-VALUE-OP-BUDGET
2 CONSTANT SBOX-LIMIT-COPY-BUDGET
3 CONSTANT SBOX-LIMIT-WALL-MS
4 CONSTANT _SBXL-VALUE-FIRST

\ The ten value limits follow, in SBOX-VALUE-LIMIT-* order.
SBOX-VALUE-LIMIT-DEPTH _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-DEPTH
SBOX-VALUE-LIMIT-BLOB-BYTES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-BLOB-BYTES
SBOX-VALUE-LIMIT-LIST-COUNT _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-LIST-COUNT
SBOX-VALUE-LIMIT-MAP-COUNT _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-MAP-COUNT
SBOX-VALUE-LIMIT-INPUT-NODES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-INPUT-NODES
SBOX-VALUE-LIMIT-INPUT-BYTES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-INPUT-BYTES
SBOX-VALUE-LIMIT-OUTPUT-ARENA-NODES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-OUTPUT-ARENA-NODES
SBOX-VALUE-LIMIT-OUTPUT-ARENA-BYTES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-OUTPUT-ARENA-BYTES
SBOX-VALUE-LIMIT-OUTPUT-RESULT-NODES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-OUTPUT-RESULT-NODES
SBOX-VALUE-LIMIT-OUTPUT-RESULT-BYTES _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-OUTPUT-RESULT-BYTES
SBOX-VALUE-LIMIT-COUNT _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-COUNT

\ A field no source has capped.  It is never a usable limit.
-1 1 RSHIFT CONSTANT SBOX-LIMIT-UNBOUNDED

\ =====================================================================
\  Caller-owned record
\ =====================================================================

0x5342584C494D4954 CONSTANT _SBXL-MAGIC  \ "SBXLIMIT"

 0 CONSTANT _SBXL-MAGIC-OFF
 8 CONSTANT _SBXL-SELF
16 CONSTANT _SBXL-VALUES
_SBXL-VALUES SBOX-LIMIT-COUNT 8 * + CONSTANT SBOX-LIMITS-SIZE

: _SBXL.MAGIC  ( limits -- address ) _SBXL-MAGIC-OFF + ;
: _SBXL.SELF   ( limits -- address ) _SBXL-SELF + ;

: _SBXL-NTH  ( field limits -- address )
    _SBXL-VALUES + SWAP 8 * + ;

: _SBXL-FIELD?  ( field -- flag )
    DUP 0>= SWAP SBOX-LIMIT-COUNT < AND ;

: _SBXL-SPAN?  ( limits -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-LIMITS-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    SBOX-LIMITS-SIZE CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _SBXL-POSITIVE?  ( limits -- flag )
    SBOX-LIMIT-COUNT 0 ?DO
        I OVER _SBXL-NTH @ 0> 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SBXL-MARKED?  ( magic limits -- flag )
    DUP _SBXL-SPAN? 0= IF 2DROP 0 EXIT THEN
    TUCK _SBXL.MAGIC @ <> IF DROP 0 EXIT THEN
    DUP _SBXL.SELF @ OVER <> IF DROP 0 EXIT THEN
    _SBXL-POSITIVE? ;

: _SBXL-BUILDING?  ( limits -- flag )
    0 SWAP _SBXL-MARKED? ;

: SBOX-LIMITS-VALID?  ( limits -- flag )
    _SBXL-MAGIC SWAP _SBXL-MARKED? ;

: SBOX-LIMITS-BOUNDED?  ( limits -- flag )
    DUP SBOX-LIMITS-VALID? 0= IF DROP 0 EXIT THEN
    SBOX-LIMIT-COUNT 0 ?DO
        I OVER _SBXL-NTH @ SBOX-LIMIT-UNBOUNDED = IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ Distinct records must not share bytes.
: _SBXL-DISJOINT?  ( a b -- flag )
    2DUP = IF 2DROP -1 EXIT THEN
    SBOX-LIMITS-SIZE TUCK MSPAN-OVERLAP? 0= ;

\ =====================================================================
\  Building one source
\ =====================================================================

: SBOX-LIMITS-BEGIN  ( limits -- status )
    DUP _SBXL-SPAN? 0= IF DROP SBOX-LIMITS-S-INVALID EXIT THEN
    DUP SBOX-LIMITS-SIZE 0 FILL
    DUP DUP _SBXL.SELF !
    SBOX-LIMIT-COUNT 0 ?DO
        SBOX-LIMIT-UNBOUNDED I 2 PICK _SBXL-NTH !
    LOOP
    DROP SBOX-LIMITS-S-OK ;

\ Lowers FIELD to VALUE unless it is already lower.
: SBOX-LIMIT-CAP  ( value field limits -- status )
    DUP _SBXL-BUILDING? 0= IF
        DROP 2DROP SBOX-LIMITS-S-STATE EXIT
    THEN
    OVER _SBXL-FIELD? 0= IF DROP 2DROP SBOX-LIMITS-S-RANGE EXIT THEN
    2 PICK 0> 0= IF DROP 2DROP SBOX-LIMITS-S-RANGE EXIT THEN
    _SBXL-NTH DUP @ ROT MIN SWAP !
    SBOX-LIMITS-S-OK ;

: SBOX-LIMITS-SEAL  ( limits -- status )
    DUP _SBXL-BUILDING? 0= IF DROP SBOX-LIMITS-S-STATE EXIT THEN
    _SBXL-MAGIC SWAP _SBXL.MAGIC !
    SBOX-LIMITS-S-OK ;

: SBOX-LIMIT@  ( field limits -- value status )
    DUP SBOX-LIMITS-VALID? 0= IF
        2DROP 0 SBOX-LIMITS-S-INVALID EXIT
    THEN
    OVER _SBXL-FIELD? 0= IF 2DROP 0 SBOX-LIMITS-S-RANGE EXIT THEN
    _SBXL-NTH @ SBOX-LIMITS-S-OK ;

\ =====================================================================
\  Combining sources
\ =====================================================================

: SBOX-LIMITS-COPY  ( source destination -- status )
    OVER SBOX-LIMITS-VALID? 0= IF 2DROP SBOX-LIMITS-S-INVALID EXIT THEN
    DUP _SBXL-SPAN? 0= IF 2DROP SBOX-LIMITS-S-INVALID EXIT THEN
    2DUP _SBXL-DISJOINT? 0= IF 2DROP SBOX-LIMITS-S-ALIAS EXIT THEN
    2DUP = IF 2DROP SBOX-LIMITS-S-OK EXIT THEN
    2DUP SBOX-LIMITS-SIZE CMOVE
    DUP _SBXL.SELF !
    DROP SBOX-LIMITS-S-OK ;

\ Narrows TARGET to the smaller value of every field.
: SBOX-LIMITS-MEET  ( source target -- status )
    OVER SBOX-LIMITS-VALID? 0= IF 2DROP SBOX-LIMITS-S-INVALID EXIT THEN
    DUP SBOX-LIMITS-VALID? 0= IF 2DROP SBOX-LIMITS-S-INVALID EXIT THEN
    2DUP _SBXL-DISJOINT? 0= IF 2DROP SBOX-LIMITS-S-ALIAS EXIT THEN
    SBOX-LIMIT-COUNT 0 ?DO
        I 2 PICK _SBXL-NTH @
        I 2 PICK _SBXL-NTH DUP @ ROT MIN SWAP !
    LOOP
    2DROP SBOX-LIMITS-S-OK ;

: _SBXL-PROFILE-CAP  ( profile-field field profile target -- flag )
    >R >R SWAP R> SBOX-PROFILE-LIMIT@
    IF 2DROP R> DROP 0 EXIT THEN
    SWAP R> _SBXL-NTH DUP @ ROT MIN SWAP !
    -1 ;

\ Narrows TARGET's budgets to the sealed profile's ceilings.
: SBOX-LIMITS-PROFILE-MEET  ( profile target -- status )
    DUP SBOX-LIMITS-VALID? 0= IF 2DROP SBOX-LIMITS-S-INVALID EXIT THEN
    OVER SBOX-PROFILE-VALID? 0= IF 2DROP SBOX-LIMITS-S-PROFILE EXIT THEN
    SBOX-PROFILE-LIMIT-MAX-BUDGET SBOX-LIMIT-INSTRUCTION-BUDGET
        3 PICK 3 PICK _SBXL-PROFILE-CAP
    SBOX-PROFILE-LIMIT-VALUE-OPS SBOX-LIMIT-VALUE-OP-BUDGET
        4 PICK 4 PICK _SBXL-PROFILE-CAP AND
    SBOX-PROFILE-LIMIT-COPY-BYTES SBOX-LIMIT-COPY-BUDGET
        4 PICK 4 PICK _SBXL-PROFILE-CAP AND
    NIP NIP
    IF SBOX-LIMITS-S-OK ELSE SBOX-LIMITS-S-PROFILE THEN ;

\ =====================================================================
\  Materializing the effective limits for one invocation
\ =====================================================================

: _SBXL-MATERIALIZE-FAIL
  ( limits value-limits status -- 0 0 0 status )
    >R
    SBOX-VALUE-LIMITS-SIZE 0 FILL
    DROP 0 0 0 R> ;

: SBOX-LIMITS-MATERIALIZE
  ( limits value-limits -- instruction value-ops copy status )
    OVER SBOX-LIMITS-VALID? 0= IF
        2DROP 0 0 0 SBOX-LIMITS-S-INVALID EXIT
    THEN
    OVER SBOX-LIMITS-BOUNDED? 0= IF
        2DROP 0 0 0 SBOX-LIMITS-S-UNBOUNDED EXIT
    THEN
    OVER SBOX-LIMITS-SIZE 2 PICK SBOX-VALUE-LIMITS-SIZE
        MSPAN-OVERLAP? IF
        2DROP 0 0 0 SBOX-LIMITS-S-ALIAS EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-BEGIN IF
        2DROP 0 0 0 SBOX-LIMITS-S-INVALID EXIT
    THEN
    SBOX-VALUE-LIMIT-COUNT 0 ?DO
        I _SBXL-VALUE-FIRST + 2 PICK _SBXL-NTH @
        I 2 PICK SBOX-VALUE-LIMIT! IF
            SBOX-LIMITS-S-VALUE _SBXL-MATERIALIZE-FAIL UNLOOP EXIT
        THEN
    LOOP
    DUP SBOX-VALUE-LIMITS-SEAL IF
        SBOX-LIMITS-S-VALUE _SBXL-MATERIALIZE-FAIL EXIT
    THEN
    DROP >R
    SBOX-LIMIT-INSTRUCTION-BUDGET R@ _SBXL-NTH @
    SBOX-LIMIT-VALUE-OP-BUDGET R@ _SBXL-NTH @
    SBOX-LIMIT-COPY-BUDGET R@ _SBXL-NTH @
    R> DROP SBOX-LIMITS-S-OK ;
