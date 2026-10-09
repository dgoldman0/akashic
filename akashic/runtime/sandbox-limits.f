\ =====================================================================
\  sandbox-limits.f - One sandbox limit record and its narrowing
\ =====================================================================
\  One record holds every limit on a sandbox invocation: the instruction,
\  value-operation and copy budgets, the wall-clock time a job may take
\  from submission, the ten value limits of sandbox/value.f, and the data
\  stack, call frames, loop frames and guest memory one activation may
\  have.  Every one is dynamic.  The profile fixes what a module means and
\  holds no limit; the host's own policy, sized for its device, sets each
\  field, and the module's declaration, a grant and the request narrow it.
\  The effective limit of a field is the smallest any source sets, so no
\  source can raise a limit another source has set.
\
\  BEGIN, CAP and SEAL build a record.  BEGIN leaves every field
\  unbounded, so a source caps only the fields it constrains.  MEET
\  narrows a sealed record in place.  MATERIALIZE turns a record whose
\  fields are all bounded into the sealed value limits and the activation
\  limits that SBOX-HOST-INIT takes, so a host's own policy must bound
\  every field.  The job service reads the wall-clock limit itself.
\
\  The record is caller-owned and aligned, and holds no pointers.  There
\  is no Desk, Agent, declaration, grant, schema or persistence here.
\ =====================================================================

PROVIDED akashic-sbox-limits

REQUIRE ../sandbox/value.f
REQUIRE ../sandbox/vm.f
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
5 CONSTANT SBOX-LIMITS-S-VALUE
6 CONSTANT SBOX-LIMITS-S-ALIAS

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

\ What one activation may have, after the value limits.
SBOX-VALUE-LIMIT-COUNT _SBXL-VALUE-FIRST +
    CONSTANT SBOX-LIMIT-DATA-STACK
SBOX-LIMIT-DATA-STACK 1+ CONSTANT SBOX-LIMIT-CALL-FRAMES
SBOX-LIMIT-DATA-STACK 2 + CONSTANT SBOX-LIMIT-LOOP-FRAMES
SBOX-LIMIT-DATA-STACK 3 + CONSTANT SBOX-LIMIT-MEMORY-BYTES
SBOX-LIMIT-DATA-STACK 4 + CONSTANT SBOX-LIMIT-COUNT

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

\ =====================================================================
\  Materializing the effective limits for one invocation
\ =====================================================================

: _SBXL-MATERIALIZE-FAIL
  ( limits value-limits vm-limits status -- status )
    >R
    SBOX-VM-LIMITS-SIZE 0 FILL
    SBOX-VALUE-LIMITS-SIZE 0 FILL
    DROP R> ;

\ The activation limits and the field each comes from, in order.
: _SBXL-VM-FIELD  ( vm-field -- field )
    CASE
        SBOX-VM-LIMIT-INSTRUCTIONS OF SBOX-LIMIT-INSTRUCTION-BUDGET ENDOF
        SBOX-VM-LIMIT-VALUE-OPS OF SBOX-LIMIT-VALUE-OP-BUDGET ENDOF
        SBOX-VM-LIMIT-COPY-BYTES OF SBOX-LIMIT-COPY-BUDGET ENDOF
        SBOX-VM-LIMIT-DATA-STACK OF SBOX-LIMIT-DATA-STACK ENDOF
        SBOX-VM-LIMIT-CALL-FRAMES OF SBOX-LIMIT-CALL-FRAMES ENDOF
        SBOX-VM-LIMIT-LOOP-FRAMES OF SBOX-LIMIT-LOOP-FRAMES ENDOF
        SBOX-VM-LIMIT-MEMORY-BYTES OF SBOX-LIMIT-MEMORY-BYTES ENDOF
        -1 SWAP
    ENDCASE ;

\ Fills the sealed value limits and the activation limits from a record
\ whose every field is bounded.  A failure clears both.
: SBOX-LIMITS-MATERIALIZE  ( limits value-limits vm-limits -- status )
    2 PICK SBOX-LIMITS-VALID? 0= IF
        DROP 2DROP SBOX-LIMITS-S-INVALID EXIT
    THEN
    2 PICK SBOX-LIMITS-BOUNDED? 0= IF
        DROP 2DROP SBOX-LIMITS-S-UNBOUNDED EXIT
    THEN
    DUP 0= OVER 7 AND OR IF DROP 2DROP SBOX-LIMITS-S-INVALID EXIT THEN
    DUP SBOX-VM-LIMITS-SIZE CALLER-SPAN-STATUS IF
        DROP 2DROP SBOX-LIMITS-S-INVALID EXIT
    THEN
    2 PICK SBOX-LIMITS-SIZE 3 PICK SBOX-VALUE-LIMITS-SIZE MSPAN-OVERLAP?
    3 PICK SBOX-LIMITS-SIZE 3 PICK SBOX-VM-LIMITS-SIZE MSPAN-OVERLAP? OR
    2 PICK SBOX-VALUE-LIMITS-SIZE 3 PICK SBOX-VM-LIMITS-SIZE
        MSPAN-OVERLAP? OR IF
        DROP 2DROP SBOX-LIMITS-S-ALIAS EXIT
    THEN
    OVER SBOX-VALUE-LIMITS-BEGIN IF
        DROP 2DROP SBOX-LIMITS-S-INVALID EXIT
    THEN
    SBOX-VALUE-LIMIT-COUNT 0 ?DO
        I _SBXL-VALUE-FIRST + 3 PICK _SBXL-NTH @
        I 3 PICK SBOX-VALUE-LIMIT! IF
            SBOX-LIMITS-S-VALUE _SBXL-MATERIALIZE-FAIL UNLOOP EXIT
        THEN
    LOOP
    OVER SBOX-VALUE-LIMITS-SEAL IF
        SBOX-LIMITS-S-VALUE _SBXL-MATERIALIZE-FAIL EXIT
    THEN
    SBOX-VM-LIMIT-COUNT 0 ?DO
        I _SBXL-VM-FIELD 3 PICK _SBXL-NTH @
        OVER I 8 * + !
    LOOP
    DROP 2DROP SBOX-LIMITS-S-OK ;
