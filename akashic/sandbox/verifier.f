\ =====================================================================
\  verifier.f - Independent bounded sandbox artifact verifier
\ =====================================================================
\  This module accepts hostile address-free artifact bytes, one sealed
\  sandbox ABI profile, and caller-owned plan/workspace spans.  It does
\  not call the compiler or execute artifact code.  Verification derives
\  record geometry, lexical loop structure, exact control-flow stack heights,
\  and resource bounds independently.  Once every proof has passed it
\  decodes each instruction into the record the VM executes, then asks
\  plan.f to publish one owned artifact copy and those records as the final
\  operation.
\
\  Every public nonempty span is qualified at the architectural caller-memory
\  boundary before access.  Once all spans are admitted and proved disjoint,
\  the complete destination plan is scrubbed.  No verification failure writes
\  artifact or profile bytes, and no plan seal exists before all proofs pass.
\ =====================================================================

REQUIRE artifact.f
REQUIRE digest.f
REQUIRE profile.f
REQUIRE abi.f
REQUIRE plan.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

PROVIDED akashic-sbx-verifier

\ =====================================================================
\  Closed result and diagnostic vocabularies
\ =====================================================================

 0 CONSTANT SBOX-VERIFIER-S-OK
 1 CONSTANT SBOX-VERIFIER-S-INVALID
 2 CONSTANT SBOX-VERIFIER-S-RANGE
 3 CONSTANT SBOX-VERIFIER-S-PROTECTED
 4 CONSTANT SBOX-VERIFIER-S-PLATFORM
 5 CONSTANT SBOX-VERIFIER-S-ALIAS
 6 CONSTANT SBOX-VERIFIER-S-ARTIFACT
 7 CONSTANT SBOX-VERIFIER-S-PROFILE
 8 CONSTANT SBOX-VERIFIER-S-CAPACITY
 9 CONSTANT SBOX-VERIFIER-S-FORMAT
10 CONSTANT SBOX-VERIFIER-S-LIMIT
11 CONSTANT SBOX-VERIFIER-S-FUNCTION
12 CONSTANT SBOX-VERIFIER-S-IMPORT
13 CONSTANT SBOX-VERIFIER-S-ENTRY
14 CONSTANT SBOX-VERIFIER-S-OPCODE
15 CONSTANT SBOX-VERIFIER-S-TARGET
16 CONSTANT SBOX-VERIFIER-S-LOOP
17 CONSTANT SBOX-VERIFIER-S-STACK
18 CONSTANT SBOX-VERIFIER-S-UNREACHABLE
19 CONSTANT SBOX-VERIFIER-S-PLAN
20 CONSTANT SBOX-VERIFIER-S-INTERNAL

: SBOX-VERIFIER-STATUS-VALID?  ( status -- flag )
    DUP SBOX-VERIFIER-S-OK >=
    SWAP SBOX-VERIFIER-S-INTERNAL <= AND ;

 0 CONSTANT SBOX-VERIFIER-D-NONE
 1 CONSTANT SBOX-VERIFIER-D-ARTIFACT-SPAN
 2 CONSTANT SBOX-VERIFIER-D-PROFILE-SPAN
 3 CONSTANT SBOX-VERIFIER-D-PLAN-SPAN
 4 CONSTANT SBOX-VERIFIER-D-WORKSPACE-SPAN
 5 CONSTANT SBOX-VERIFIER-D-OVERLAP
 6 CONSTANT SBOX-VERIFIER-D-ARTIFACT-GEOMETRY
 7 CONSTANT SBOX-VERIFIER-D-PROFILE-DIGEST
 8 CONSTANT SBOX-VERIFIER-D-MEMORY
 9 CONSTANT SBOX-VERIFIER-D-COUNTS
10 CONSTANT SBOX-VERIFIER-D-PADDING
11 CONSTANT SBOX-VERIFIER-D-FUNCTION-CODE
12 CONSTANT SBOX-VERIFIER-D-FUNCTION-SIGNATURE
13 CONSTANT SBOX-VERIFIER-D-FUNCTION-FLAGS
14 CONSTANT SBOX-VERIFIER-D-ENTRY-GEOMETRY
15 CONSTANT SBOX-VERIFIER-D-ENTRY-NAME
16 CONSTANT SBOX-VERIFIER-D-ENTRY-ORDER
17 CONSTANT SBOX-VERIFIER-D-ENTRY-FUNCTION
18 CONSTANT SBOX-VERIFIER-D-ENTRY-FLAGS
19 CONSTANT SBOX-VERIFIER-D-ENTRY-SIGNATURE
20 CONSTANT SBOX-VERIFIER-D-INSTRUCTION-FLAGS
21 CONSTANT SBOX-VERIFIER-D-INSTRUCTION-OPCODE
22 CONSTANT SBOX-VERIFIER-D-INSTRUCTION-OPERANDS
23 CONSTANT SBOX-VERIFIER-D-INSTRUCTION-TARGET
24 CONSTANT SBOX-VERIFIER-D-LOOP-NESTING
25 CONSTANT SBOX-VERIFIER-D-LOOP-RECIPROCAL
26 CONSTANT SBOX-VERIFIER-D-LOOP-SCOPE
27 CONSTANT SBOX-VERIFIER-D-LOOP-INDEX
28 CONSTANT SBOX-VERIFIER-D-LOOP-RETURN
29 CONSTANT SBOX-VERIFIER-D-STACK-UNDERFLOW
30 CONSTANT SBOX-VERIFIER-D-STACK-MERGE
31 CONSTANT SBOX-VERIFIER-D-STACK-RETURN
32 CONSTANT SBOX-VERIFIER-D-UNREACHABLE
33 CONSTANT SBOX-VERIFIER-D-PLAN-PUBLISH
34 CONSTANT SBOX-VERIFIER-D-INTERNAL

: SBOX-VERIFIER-DETAIL-VALID?  ( detail -- flag )
    DUP SBOX-VERIFIER-D-NONE >=
    SWAP SBOX-VERIFIER-D-INTERNAL <= AND ;


\ =====================================================================
\  Caller-owned workspace, measured from the profile
\ =====================================================================

0x5342585645524946 CONSTANT _SBOX-VERIFIER-WORK-MAGIC  \ "SBXVERIF"

  0 CONSTANT _SVW-MAGIC
  8 CONSTANT _SVW-SELF
 16 CONSTANT _SVW-STATUS
 24 CONSTANT _SVW-DETAIL
 32 CONSTANT _SVW-ERROR-INDEX
 40 CONSTANT _SVW-ARTIFACT
 48 CONSTANT _SVW-ARTIFACT-U
 56 CONSTANT _SVW-PROFILE
 64 CONSTANT _SVW-PLAN
 72 CONSTANT _SVW-PLAN-U
 80 CONSTANT _SVW-FUNCTIONS
 88 CONSTANT _SVW-IMPORTS
 96 CONSTANT _SVW-ENTRIES
104 CONSTANT _SVW-NAMES
112 CONSTANT _SVW-INITIAL
120 CONSTANT _SVW-INSTRUCTIONS
128 CONSTANT _SVW-FUNCTION-N
136 CONSTANT _SVW-IMPORT-N
144 CONSTANT _SVW-ENTRY-N
152 CONSTANT _SVW-NAME-U
160 CONSTANT _SVW-INITIAL-U
168 CONSTANT _SVW-INSTRUCTION-N
176 CONSTANT _SVW-MEMORY-U
184 CONSTANT _SVW-CURRENT-INDEX
192 CONSTANT _SVW-CURRENT-FUNCTION
200 CONSTANT _SVW-FUNCTION-START
208 CONSTANT _SVW-FUNCTION-END
216 CONSTANT _SVW-FUNCTION-LOCALS
224 CONSTANT _SVW-FUNCTION-RESULTS
232 CONSTANT _SVW-QUEUE-HEAD
240 CONSTANT _SVW-QUEUE-TAIL
248 CONSTANT _SVW-LOOP-DEPTH
256 CONSTANT _SVW-MAX-STACK
264 CONSTANT _SVW-CURRENT-RECORD
272 CONSTANT _SVW-PREFIX
280 CONSTANT _SVW-NEXT-HEIGHT
288 CONSTANT _SVW-INSTRUCTION-CAP
296 CONSTANT _SVW-DIGEST-OFF
304 CONSTANT _SVW-RESERVED
312 CONSTANT _SVW-STARTS-OFF
320 CONSTANT _SVW-MAXES-OFF
328 CONSTANT _SVW-HEIGHTS-OFF
336 CONSTANT _SVW-SCOPES-OFF
344 CONSTANT _SVW-QUEUE-OFF
352 CONSTANT _SVW-LOOPS-OFF
360 CONSTANT _SVW-TOTAL
368 CONSTANT _SVW-DECODED-OFF
376 CONSTANT _SVW-HEADER-SIZE

\ The artifact layout follows the header.  The per-function and
\ per-instruction tables follow it, sized from the profile.
_SVW-HEADER-SIZE CONSTANT _SVW-LAYOUT

: _SVW.MAGIC             ( w -- a ) _SVW-MAGIC + ;
: _SVW.SELF              ( w -- a ) _SVW-SELF + ;
: _SVW.STATUS            ( w -- a ) _SVW-STATUS + ;
: _SVW.DETAIL            ( w -- a ) _SVW-DETAIL + ;
: _SVW.ERROR-INDEX       ( w -- a ) _SVW-ERROR-INDEX + ;
: _SVW.ARTIFACT         ( w -- a ) _SVW-ARTIFACT + ;
: _SVW.ARTIFACT-U       ( w -- a ) _SVW-ARTIFACT-U + ;
: _SVW.PROFILE           ( w -- a ) _SVW-PROFILE + ;
: _SVW.PLAN              ( w -- a ) _SVW-PLAN + ;
: _SVW.PLAN-U            ( w -- a ) _SVW-PLAN-U + ;
: _SVW.FUNCTIONS         ( w -- a ) _SVW-FUNCTIONS + ;
: _SVW.IMPORTS           ( w -- a ) _SVW-IMPORTS + ;
: _SVW.ENTRIES           ( w -- a ) _SVW-ENTRIES + ;
: _SVW.NAMES             ( w -- a ) _SVW-NAMES + ;
: _SVW.INITIAL           ( w -- a ) _SVW-INITIAL + ;
: _SVW.INSTRUCTIONS      ( w -- a ) _SVW-INSTRUCTIONS + ;
: _SVW.FUNCTION-N        ( w -- a ) _SVW-FUNCTION-N + ;
: _SVW.IMPORT-N          ( w -- a ) _SVW-IMPORT-N + ;
: _SVW.ENTRY-N           ( w -- a ) _SVW-ENTRY-N + ;
: _SVW.NAME-U            ( w -- a ) _SVW-NAME-U + ;
: _SVW.INITIAL-U         ( w -- a ) _SVW-INITIAL-U + ;
: _SVW.INSTRUCTION-N     ( w -- a ) _SVW-INSTRUCTION-N + ;
: _SVW.MEMORY-U          ( w -- a ) _SVW-MEMORY-U + ;
: _SVW.CURRENT-INDEX     ( w -- a ) _SVW-CURRENT-INDEX + ;
: _SVW.CURRENT-FUNCTION  ( w -- a ) _SVW-CURRENT-FUNCTION + ;
: _SVW.FUNCTION-START    ( w -- a ) _SVW-FUNCTION-START + ;
: _SVW.FUNCTION-END      ( w -- a ) _SVW-FUNCTION-END + ;
: _SVW.FUNCTION-LOCALS   ( w -- a ) _SVW-FUNCTION-LOCALS + ;
: _SVW.FUNCTION-RESULTS  ( w -- a ) _SVW-FUNCTION-RESULTS + ;
: _SVW.QUEUE-HEAD        ( w -- a ) _SVW-QUEUE-HEAD + ;
: _SVW.QUEUE-TAIL        ( w -- a ) _SVW-QUEUE-TAIL + ;
: _SVW.LOOP-DEPTH        ( w -- a ) _SVW-LOOP-DEPTH + ;
: _SVW.MAX-STACK         ( w -- a ) _SVW-MAX-STACK + ;
: _SVW.CURRENT-RECORD    ( w -- a ) _SVW-CURRENT-RECORD + ;
: _SVW.PREFIX            ( w -- a ) _SVW-PREFIX + ;
: _SVW.NEXT-HEIGHT       ( w -- a ) _SVW-NEXT-HEIGHT + ;
: _SVW.DIGEST-OFF        ( w -- a ) _SVW-DIGEST-OFF + ;
\ The artifact digest's work area, then the 32 digest bytes.
: _SVW-DIGEST-WORK  ( w -- a ) DUP _SVW.DIGEST-OFF @ + ;
: _SVW-DIGEST  ( w -- a ) _SVW-DIGEST-WORK SBOX-DIGEST-WORKSPACE-SIZE + ;
: _SVW.RESERVED          ( w -- a ) _SVW-RESERVED + ;
: _SVW.LAYOUT            ( w -- a ) _SVW-LAYOUT + ;
: _SVW.TOTAL             ( w -- a ) _SVW-TOTAL + ;
: _SVW.INSTRUCTION-CAP          ( w -- a ) _SVW-INSTRUCTION-CAP + ;

: _SVW-FUNCTION-START[]  ( index w -- a )
    DUP _SVW-STARTS-OFF + @ + SWAP 8 * + ;

: _SVW-FUNCTION-MAX[]  ( index w -- a )
    DUP _SVW-MAXES-OFF + @ + SWAP 8 * + ;

: _SVW-HEIGHT[]  ( index w -- a )
    DUP _SVW-HEIGHTS-OFF + @ + SWAP 8 * + ;

: _SVW-SCOPE[]  ( index w -- a )
    DUP _SVW-SCOPES-OFF + @ + SWAP 8 * + ;

: _SVW-QUEUE[]  ( index w -- a )
    DUP _SVW-QUEUE-OFF + @ + SWAP 8 * + ;

: _SVW-LOOP[]  ( index w -- a )
    DUP _SVW-LOOPS-OFF + @ + SWAP 8 * + ;

: _SVW-DECODED[]  ( index w -- record )
    DUP _SVW-DECODED-OFF + @ + SWAP SBOX-PLAN-DECODED-SIZE * + ;

\ =====================================================================
\  Caller-memory admission and workspace diagnostics
\ =====================================================================

: _SV-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP SBOX-VERIFIER-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP SBOX-VERIFIER-S-PROTECTED EXIT
    THEN
    DROP SBOX-VERIFIER-S-PLATFORM ;

: _SV-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP SBOX-VERIFIER-S-INVALID EXIT THEN
    DUP 0= IF 2DROP SBOX-VERIFIER-S-OK EXIT THEN
    OVER 0= IF 2DROP SBOX-VERIFIER-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP SBOX-VERIFIER-S-RANGE EXIT
    THEN
    CALLER-SPAN-STATUS _SV-CALLER>STATUS ;

\ =====================================================================
\  What one verification can hold
\ =====================================================================
\  The tables are sized from the artifact itself: its header's function
\  and instruction counts, each no more than its bytes could hold and no
\  more than the format's ceiling.  A header that claims more than its bytes
\  hold is rejected later; the bound only keeps the workspace honest.

: _SV-COUNT-CAP  ( count artifact-u record-size maximum -- n )
    >R / MIN R> MIN 0 MAX ;

: _SV-FUNCTION-CAP  ( artifact artifact-u -- n )
    SWAP SBOX-ARTIFACT-FUNCTION-N@ SWAP
    SBOX-ARTIFACT-FUNCTION-SIZE SBOX-ARTIFACT-FUNCTION-MAX _SV-COUNT-CAP ;

: _SV-INSTRUCTION-CAP  ( artifact artifact-u -- n )
    SWAP SBOX-ARTIFACT-INSTRUCTION-N@ SWAP
    SBOX-ARTIFACT-INSTRUCTION-SIZE SBOX-ARTIFACT-INSTRUCTION-MAX
    _SV-COUNT-CAP ;

\ Adds COUNT cells at OFFSET, recording OFFSET in FIELD of WORKSPACE
\ unless WORKSPACE is 0.  Every count is within the format's ceilings, so
\ no size overflows.
: _SV-REGION  ( offset count field workspace|0 -- offset' )
    ?DUP IF + 2 PICK SWAP ! ELSE DROP THEN
    8 * + ;

\ The workspace size for the artifact.  With a workspace it also records
\ where each table starts.  Every open loop began at a LOOP.ENTER, so the
\ loop table needs no more entries than there are instructions.
: _SV-GEOMETRY  ( artifact artifact-u workspace|0 -- bytes )
    >R 2DUP _SV-FUNCTION-CAP >R _SV-INSTRUCTION-CAP R>
    \ ( instructions functions )
    _SVW-LAYOUT SBOX-ARTIFACT-LAYOUT-SIZE +
    OVER 1+ _SVW-STARTS-OFF R@ _SV-REGION
    OVER _SVW-MAXES-OFF R@ _SV-REGION
    2 PICK _SVW-HEIGHTS-OFF R@ _SV-REGION
    2 PICK _SVW-SCOPES-OFF R@ _SV-REGION
    2 PICK _SVW-QUEUE-OFF R@ _SV-REGION
    2 PICK _SVW-LOOPS-OFF R@ _SV-REGION
    2 PICK SBOX-PLAN-DECODED-SIZE 8 / * _SVW-DECODED-OFF R@ _SV-REGION
    \ The digest work area and the digest are whole cells.
    SBOX-DIGEST-WORKSPACE-SIZE SBOX-DIGEST-SIZE + 8 /
        _SVW-DIGEST-OFF R@ _SV-REGION
    R@ IF 2 PICK R@ _SVW.INSTRUCTION-CAP ! THEN
    NIP NIP R> DROP ;

: _SV-ARTIFACT-SPAN-STATUS  ( artifact artifact-u -- status )
    DUP SBOX-ARTIFACT-PREFIX-SIZE < IF 2DROP SBOX-VERIFIER-S-CAPACITY EXIT THEN
    DUP SBOX-ARTIFACT-BYTES-MAX > IF 2DROP SBOX-VERIFIER-S-CAPACITY EXIT THEN
    _SV-SPAN-STATUS ;

\ The workspace SBOX-VERIFY needs for the artifact.
: SBOX-VERIFIER-WORKSPACE-MEASURE  ( artifact artifact-u -- bytes status )
    2DUP _SV-ARTIFACT-SPAN-STATUS ?DUP IF NIP NIP 0 SWAP EXIT THEN
    0 _SV-GEOMETRY SBOX-VERIFIER-S-OK ;

: _SV-DROP6>STATUS  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R 2DROP 2DROP 2DROP R> ;

: _SV-DUP6
  ( x1 x2 x3 x4 x5 x6 -- x1 x2 x3 x4 x5 x6 x1 x2 x3 x4 x5 x6 )
    5 PICK 5 PICK 5 PICK 5 PICK 5 PICK 5 PICK ;

: _SV-ADMIT
  ( artifact artifact-u profile plan plan-u workspace -- status )
    4 PICK SBOX-ARTIFACT-PREFIX-SIZE < IF
        SBOX-VERIFIER-S-CAPACITY _SV-DROP6>STATUS EXIT
    THEN
    3 PICK 7 AND IF
        SBOX-VERIFIER-S-INVALID _SV-DROP6>STATUS EXIT
    THEN
    3 PICK SBOX-PROFILE-SIZE _SV-SPAN-STATUS DUP IF
        _SV-DROP6>STATUS EXIT
    THEN DROP
    3 PICK SBOX-PROFILE-VALID? 0= IF
        SBOX-VERIFIER-S-PROFILE _SV-DROP6>STATUS EXIT
    THEN
    \ The artifact measures the workspace.
    5 PICK 5 PICK SBOX-VERIFIER-WORKSPACE-MEASURE DUP IF
        NIP _SV-DROP6>STATUS EXIT
    THEN DROP
    >R
    2 PICK 7 AND IF
        R> DROP SBOX-VERIFIER-S-INVALID _SV-DROP6>STATUS EXIT
    THEN
    DUP 7 AND IF
        R> DROP SBOX-VERIFIER-S-INVALID _SV-DROP6>STATUS EXIT
    THEN

    5 PICK 5 PICK SBOX-PLAN-MEASURE
    DUP IF
        2DROP
        R> DROP SBOX-VERIFIER-S-CAPACITY _SV-DROP6>STATUS EXIT
    THEN
    DROP
    2 PICK <> IF
        R> DROP SBOX-VERIFIER-S-CAPACITY _SV-DROP6>STATUS EXIT
    THEN

    2 PICK 2 PICK _SV-SPAN-STATUS DUP IF
        R> DROP _SV-DROP6>STATUS EXIT
    THEN DROP
    DUP R@ _SV-SPAN-STATUS DUP IF
        R> DROP _SV-DROP6>STATUS EXIT
    THEN DROP

    \ artifact/profile
    5 PICK 5 PICK 5 PICK SBOX-PROFILE-SIZE
        MSPAN-OVERLAP? IF
        R> DROP SBOX-VERIFIER-S-ALIAS _SV-DROP6>STATUS EXIT
    THEN
    \ artifact/plan
    5 PICK 5 PICK 4 PICK 4 PICK
        MSPAN-OVERLAP? IF
        R> DROP SBOX-VERIFIER-S-ALIAS _SV-DROP6>STATUS EXIT
    THEN
    \ artifact/workspace
    5 PICK 5 PICK 2 PICK R@
        MSPAN-OVERLAP? IF
        R> DROP SBOX-VERIFIER-S-ALIAS _SV-DROP6>STATUS EXIT
    THEN
    \ profile/plan
    3 PICK SBOX-PROFILE-SIZE 4 PICK 4 PICK
        MSPAN-OVERLAP? IF
        R> DROP SBOX-VERIFIER-S-ALIAS _SV-DROP6>STATUS EXIT
    THEN
    \ profile/workspace
    3 PICK SBOX-PROFILE-SIZE
        2 PICK R@
        MSPAN-OVERLAP? IF
        R> DROP SBOX-VERIFIER-S-ALIAS _SV-DROP6>STATUS EXIT
    THEN
    \ plan/workspace
    2 PICK 2 PICK 2 PICK R@
        MSPAN-OVERLAP? IF
        R> DROP SBOX-VERIFIER-S-ALIAS _SV-DROP6>STATUS EXIT
    THEN

    R> DROP SBOX-VERIFIER-S-OK _SV-DROP6>STATUS ;

: _SV-WORKSPACE-INIT
  ( artifact artifact-u profile plan plan-u workspace -- workspace )
    >R
    4 PICK 4 PICK 0 _SV-GEOMETRY R@ SWAP 0 FILL
    4 PICK 4 PICK R@ _SV-GEOMETRY R@ _SVW.TOTAL !
    R@ _SVW.PLAN-U !
    R@ _SVW.PLAN !
    R@ _SVW.PROFILE !
    R@ _SVW.ARTIFACT-U !
    R@ _SVW.ARTIFACT !
    R@ R@ _SVW.SELF !
    SBOX-VERIFIER-S-INTERNAL R@ _SVW.STATUS !
    SBOX-VERIFIER-D-NONE R@ _SVW.DETAIL !
    -1 R@ _SVW.ERROR-INDEX !
    0 R@ _SVW-HEIGHT[]
        R@ _SVW.INSTRUCTION-CAP @ 8 * -1 FILL
    _SBOX-VERIFIER-WORK-MAGIC R@ _SVW.MAGIC !
    R> ;

: _SV-WORKSPACE-STATUS  ( workspace -- status )
    DUP _SVW-HEADER-SIZE _SV-SPAN-STATUS
    ?DUP IF NIP EXIT THEN
    DUP 7 AND IF DROP SBOX-VERIFIER-S-INVALID EXIT THEN
    DUP _SVW.MAGIC @ _SBOX-VERIFIER-WORK-MAGIC <> IF
        DROP SBOX-VERIFIER-S-INVALID EXIT
    THEN
    DUP _SVW.SELF @ OVER <> IF
        DROP SBOX-VERIFIER-S-INVALID EXIT
    THEN
    DUP _SVW.STATUS @ SBOX-VERIFIER-STATUS-VALID? 0= IF
        DROP SBOX-VERIFIER-S-INVALID EXIT
    THEN
    DUP _SVW.DETAIL @ SBOX-VERIFIER-DETAIL-VALID? 0= IF
        DROP SBOX-VERIFIER-S-INVALID EXIT
    THEN
    _SVW.RESERVED @ IF
        SBOX-VERIFIER-S-INVALID
    ELSE
        SBOX-VERIFIER-S-OK
    THEN ;

: SBOX-VERIFIER-LAST-STATUS@  ( workspace -- last-status status )
    >R
    R@ _SV-WORKSPACE-STATUS DUP IF
        R> DROP 0 SWAP EXIT
    THEN
    DROP R@ _SVW.STATUS @ SBOX-VERIFIER-S-OK
    R> DROP ;

: SBOX-VERIFIER-ERROR-DETAIL@  ( workspace -- detail status )
    >R
    R@ _SV-WORKSPACE-STATUS DUP IF
        R> DROP 0 SWAP EXIT
    THEN
    DROP R@ _SVW.DETAIL @ SBOX-VERIFIER-S-OK
    R> DROP ;

: SBOX-VERIFIER-ERROR-INDEX@  ( workspace -- index status )
    >R
    R@ _SV-WORKSPACE-STATUS DUP IF
        R> DROP -1 SWAP EXIT
    THEN
    DROP R@ _SVW.ERROR-INDEX @ SBOX-VERIFIER-S-OK
    R> DROP ;

: _SV-FAIL  ( status detail index workspace -- status )
    >R
    R@ _SVW.ERROR-INDEX !
    R@ _SVW.DETAIL !
    DUP R@ _SVW.STATUS !
    R> DROP ;

\ =====================================================================
\  Admitted artifact/profile access
\ =====================================================================

: _SV-FUNCTION[]  ( index workspace -- record )
    >R SBOX-ARTIFACT-FUNCTION-SIZE *
    R> _SVW.FUNCTIONS @ + ;

: _SV-ENTRY[]  ( index workspace -- record )
    >R SBOX-ARTIFACT-ENTRY-SIZE *
    R> _SVW.ENTRIES @ + ;

: _SV-INSTRUCTION[]  ( index workspace -- record )
    >R SBOX-ARTIFACT-INSTRUCTION-SIZE *
    R> _SVW.INSTRUCTIONS @ + ;

: _SV-FUNCTION-INSTRUCTION-N@  ( record -- value )
    SBOX-ARTIFACT-FUNCTION-INSTRUCTION-N-OFFSET +
    SBOX-BYTE-U32-LE@ ;

: _SV-FUNCTION-PARAMS@  ( record -- value )
    SBOX-ARTIFACT-FUNCTION-PARAMS-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-FUNCTION-RESULTS@  ( record -- value )
    SBOX-ARTIFACT-FUNCTION-RESULTS-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-FUNCTION-LOCALS@  ( record -- value )
    SBOX-ARTIFACT-FUNCTION-LOCALS-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-FUNCTION-FLAGS@  ( record -- value )
    SBOX-ARTIFACT-FUNCTION-FLAGS-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-FUNCTION-RESERVED@  ( record -- value )
    SBOX-ARTIFACT-FUNCTION-RESERVED-OFFSET +
    SBOX-BYTE-U32-LE@ ;

: _SV-ENTRY-NAME-OFFSET@  ( record -- value )
    SBOX-ARTIFACT-ENTRY-NAME-OFFSET +
    SBOX-BYTE-U32-LE@ ;

: _SV-ENTRY-NAME-U@  ( record -- value )
    SBOX-ARTIFACT-ENTRY-NAME-U-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-ENTRY-FLAGS@  ( record -- value )
    SBOX-ARTIFACT-ENTRY-FLAGS-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-ENTRY-FUNCTION@  ( record -- value )
    SBOX-ARTIFACT-ENTRY-FUNCTION-INDEX-OFFSET +
    SBOX-BYTE-U32-LE@ ;

: _SV-ENTRY-SIGNATURE@  ( record -- value )
    SBOX-ARTIFACT-ENTRY-SIGNATURE-ID-OFFSET +
    SBOX-BYTE-U32-LE@ ;

: _SV-INSTRUCTION-OPCODE@  ( record -- value )
    SBOX-ARTIFACT-INSTRUCTION-OPCODE-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-INSTRUCTION-FLAGS@  ( record -- value )
    SBOX-ARTIFACT-INSTRUCTION-FLAGS-OFFSET +
    SBOX-BYTE-U16-LE@ ;

: _SV-INSTRUCTION-A@  ( record -- value )
    SBOX-ARTIFACT-INSTRUCTION-A-OFFSET +
    SBOX-BYTE-U32-LE@ ;

: _SV-INSTRUCTION-B@  ( record -- value )
    SBOX-ARTIFACT-INSTRUCTION-B-OFFSET +
    SBOX-BYTE-U64-LE@ ;

: _SV-ARTIFACT>STATUS  ( artifact-status -- verifier-status )
    DUP SBOX-ARTIFACT-S-CAPACITY = IF
        DROP SBOX-VERIFIER-S-CAPACITY EXIT
    THEN
    DUP SBOX-ARTIFACT-S-ALIAS = IF
        DROP SBOX-VERIFIER-S-ALIAS EXIT
    THEN
    DROP SBOX-VERIFIER-S-ARTIFACT ;

: _SV-PLAN>STATUS  ( plan-status -- verifier-status )
    DUP SBOX-PLAN-S-CAPACITY = IF
        DROP SBOX-VERIFIER-S-CAPACITY EXIT
    THEN
    DUP SBOX-PLAN-S-ALIAS = IF
        DROP SBOX-VERIFIER-S-ALIAS EXIT
    THEN
    DROP SBOX-VERIFIER-S-PLAN ;

: _SV-ZERO-SPAN?  ( address length -- flag )
    BEGIN
        DUP 0>
    WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        SWAP 1+ SWAP 1-
    REPEAT
    2DROP -1 ;

: _SV-LOAD-ARTIFACT  ( workspace -- status )
    >R
    R@ _SVW.ARTIFACT @
    R@ _SVW.ARTIFACT-U @
    R@ _SVW.LAYOUT
    SBOX-ARTIFACT-INSPECT
    DUP IF
        _SV-ARTIFACT>STATUS
        SBOX-VERIFIER-D-ARTIFACT-GEOMETRY -1 R@
        _SV-FAIL R> DROP EXIT
    THEN DROP

    \ The artifact must name exactly this profile.  The profile holds no
    \ limit: the format's ceilings bound the artifact, and the host bounds
    \ the run.
    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-PROFILE-DIGEST@
    R@ _SVW.PROFILE @ SBOX-PROFILE-DIGEST= 0= IF
        SBOX-VERIFIER-S-PROFILE
        SBOX-VERIFIER-D-PROFILE-DIGEST -1 R@
        _SV-FAIL R> DROP EXIT
    THEN

    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-MEMORY-U@
    DUP R@ _SVW.MEMORY-U !
    DUP 7 AND IF
        DROP SBOX-VERIFIER-S-LIMIT
        SBOX-VERIFIER-D-MEMORY -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    DROP

    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-FUNCTION-N@
        R@ _SVW.FUNCTION-N !
    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-IMPORT-N@
        R@ _SVW.IMPORT-N !
    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-ENTRY-N@
        R@ _SVW.ENTRY-N !
    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-NAME-U@
        R@ _SVW.NAME-U !
    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-INITIAL-U@
        R@ _SVW.INITIAL-U !
    R@ _SVW.ARTIFACT @ SBOX-ARTIFACT-INSTRUCTION-N@
        R@ _SVW.INSTRUCTION-N !

    R@ _SVW.FUNCTION-N @ 0= IF
        SBOX-VERIFIER-S-LIMIT
        SBOX-VERIFIER-D-COUNTS -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    \ No profile this runtime loads declares an import, so any import in
    \ an artifact names one its profile lacks.
    R@ _SVW.IMPORT-N @ IF
        SBOX-VERIFIER-S-IMPORT
        SBOX-VERIFIER-D-COUNTS -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.ENTRY-N @ 0= IF
        SBOX-VERIFIER-S-LIMIT
        SBOX-VERIFIER-D-COUNTS -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.NAME-U @ 0= IF
        SBOX-VERIFIER-S-FORMAT
        SBOX-VERIFIER-D-COUNTS -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.INSTRUCTION-N @ 0= IF
        SBOX-VERIFIER-S-LIMIT
        SBOX-VERIFIER-D-COUNTS -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.INITIAL-U @ R@ _SVW.MEMORY-U @ U> IF
        SBOX-VERIFIER-S-LIMIT
        SBOX-VERIFIER-D-MEMORY -1 R@
        _SV-FAIL R> DROP EXIT
    THEN

    R@ _SVW.ARTIFACT @
    R@ _SVW.LAYOUT SBOX-ARTIFACT-LAYOUT-FUNCTIONS@ +
        R@ _SVW.FUNCTIONS !
    R@ _SVW.ARTIFACT @
    R@ _SVW.LAYOUT SBOX-ARTIFACT-LAYOUT-IMPORTS@ +
        R@ _SVW.IMPORTS !
    R@ _SVW.ARTIFACT @
    R@ _SVW.LAYOUT SBOX-ARTIFACT-LAYOUT-ENTRIES@ +
        R@ _SVW.ENTRIES !
    R@ _SVW.ARTIFACT @
    R@ _SVW.LAYOUT SBOX-ARTIFACT-LAYOUT-NAMES@ +
        R@ _SVW.NAMES !
    R@ _SVW.ARTIFACT @
    R@ _SVW.LAYOUT SBOX-ARTIFACT-LAYOUT-INITIAL@ +
        R@ _SVW.INITIAL !
    R@ _SVW.ARTIFACT @
    R@ _SVW.LAYOUT SBOX-ARTIFACT-LAYOUT-INSTRUCTIONS@ +
        R@ _SVW.INSTRUCTIONS !

    R@ _SVW.NAMES @ R@ _SVW.NAME-U @ +
    R@ _SVW.INITIAL @ OVER -
    _SV-ZERO-SPAN? 0= IF
        SBOX-VERIFIER-S-FORMAT
        SBOX-VERIFIER-D-PADDING -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.INITIAL @ R@ _SVW.INITIAL-U @ +
    R@ _SVW.INSTRUCTIONS @ OVER -
    _SV-ZERO-SPAN? 0= IF
        SBOX-VERIFIER-S-FORMAT
        SBOX-VERIFIER-D-PADDING -1 R@
        _SV-FAIL R> DROP EXIT
    THEN

    R> DROP SBOX-VERIFIER-S-OK ;

\ =====================================================================
\  Function, import, and entry record proof
\ =====================================================================

: _SV-VALIDATE-FUNCTIONS  ( workspace -- status )
    >R
    0 R@ _SVW.PREFIX !
    0 R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @
        R@ _SVW.FUNCTION-N @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SV-FUNCTION[]
        R@ _SVW.CURRENT-RECORD !

        R@ _SVW.PREFIX @
        R@ _SVW.CURRENT-INDEX @ R@ _SVW-FUNCTION-START[] !

        R@ _SVW.CURRENT-RECORD @
            _SV-FUNCTION-INSTRUCTION-N@ DUP 0= IF
            DROP SBOX-VERIFIER-S-FUNCTION
            SBOX-VERIFIER-D-FUNCTION-CODE
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        R@ _SVW.INSTRUCTION-N @ R@ _SVW.PREFIX @ - U> IF
            SBOX-VERIFIER-S-FUNCTION
            SBOX-VERIFIER-D-FUNCTION-CODE
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN

        R@ _SVW.CURRENT-RECORD @ _SV-FUNCTION-FLAGS@
        R@ _SVW.CURRENT-RECORD @ _SV-FUNCTION-RESERVED@ OR IF
            SBOX-VERIFIER-S-FUNCTION
            SBOX-VERIFIER-D-FUNCTION-FLAGS
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN

        R@ _SVW.CURRENT-RECORD @ _SV-FUNCTION-INSTRUCTION-N@
            R@ _SVW.PREFIX +!
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT

    R@ _SVW.PREFIX @ R@ _SVW.INSTRUCTION-N @ <> IF
        SBOX-VERIFIER-S-FUNCTION
        SBOX-VERIFIER-D-FUNCTION-CODE -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.PREFIX @
    R@ _SVW.FUNCTION-N @ R@ _SVW-FUNCTION-START[] !

    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-ENTRY-NAME$  ( entry-record workspace -- address length )
    >R
    DUP _SV-ENTRY-NAME-OFFSET@ R@ _SVW.NAMES @ +
    SWAP _SV-ENTRY-NAME-U@
    R> DROP ;

: _SV-VALIDATE-ENTRIES  ( workspace -- status )
    >R
    0 R@ _SVW.PREFIX !
    0 R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @ R@ _SVW.ENTRY-N @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SV-ENTRY[]
        R@ _SVW.CURRENT-RECORD !

        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-NAME-OFFSET@
        R@ _SVW.PREFIX @ <> IF
            SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-GEOMETRY
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-NAME-U@
        DUP 1 < SWAP SBOX-ABI-ENTRY-NAME-MAX > OR IF
            SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-NAME
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-NAME-U@
        R@ _SVW.NAME-U @ R@ _SVW.PREFIX @ - U> IF
            SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-GEOMETRY
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ R@ _SV-ENTRY-NAME$
        SBOX-ABI-ENTRY-NAME? 0= IF
            SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-NAME
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-INDEX @ 0> IF
            R@ _SVW.CURRENT-INDEX @ 1-
                R@ _SV-ENTRY[] R@ _SV-ENTRY-NAME$
            R@ _SVW.CURRENT-RECORD @ R@ _SV-ENTRY-NAME$
            COMPARE 0< 0= IF
                SBOX-VERIFIER-S-ENTRY
                SBOX-VERIFIER-D-ENTRY-ORDER
                R@ _SVW.CURRENT-INDEX @ R@
                _SV-FAIL R> DROP EXIT
            THEN
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-FUNCTION@
        DUP R@ _SVW.FUNCTION-N @ U< 0= IF
            DROP SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-FUNCTION
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-FUNCTION !
        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-FLAGS@ IF
            SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-FLAGS
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        \ An entry may carry only a signature its profile enables.
        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-SIGNATURE@
        DUP R@ _SVW.PROFILE @ SBOX-PROFILE-SIGNATURE-ENABLED? 0= AND
        OVER SBOX-ABI-SIGNATURE-VALUE-TO-VALUE U> 0= AND 0= IF
            DROP SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-SIGNATURE
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        SBOX-ABI-SIGNATURE-VALUE-TO-VALUE = IF
            R@ _SVW.CURRENT-FUNCTION @ R@ _SV-FUNCTION[]
            DUP _SV-FUNCTION-PARAMS@ 1 <>
            SWAP _SV-FUNCTION-RESULTS@ 1 <> OR IF
                SBOX-VERIFIER-S-ENTRY
                SBOX-VERIFIER-D-FUNCTION-SIGNATURE
                R@ _SVW.CURRENT-INDEX @ R@
                _SV-FAIL R> DROP EXIT
            THEN
        THEN

        R@ _SVW.CURRENT-RECORD @ _SV-ENTRY-NAME-U@
            R@ _SVW.PREFIX +!
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT

    R@ _SVW.PREFIX @ R@ _SVW.NAME-U @ <> IF
        SBOX-VERIFIER-S-ENTRY
        SBOX-VERIFIER-D-ENTRY-GEOMETRY -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R> DROP SBOX-VERIFIER-S-OK ;

\ =====================================================================
\  Canonical instruction and lexical counted-loop proof
\ =====================================================================

: _SV-FAIL-CURRENT  ( status detail workspace -- status )
    >R
    R@ _SVW.CURRENT-INDEX @ R@ _SV-FAIL
    R> DROP ;

: _SV-CURRENT-LOCAL-INDEX  ( workspace -- index )
    DUP _SVW.CURRENT-INDEX @
    SWAP _SVW.FUNCTION-START @ - ;

: _SV-CURRENT-FUNCTION-U  ( workspace -- count )
    DUP _SVW.FUNCTION-END @
    SWAP _SVW.FUNCTION-START @ - ;

: _SV-NONLITERAL-B-ZERO?  ( workspace -- flag )
    _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-B@ 0= ;

: _SV-VALIDATE-OPERANDS  ( operand-shape workspace -- status )
    >R
    DUP SBOX-MACHINE-OPERAND-NONE = IF
        DROP
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-B@ OR IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-I64 = IF
        DROP
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@ IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-BRANCH = IF
        DROP
        R@ _SV-NONLITERAL-B-ZERO? 0= IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SV-CURRENT-FUNCTION-U U< 0= IF
            SBOX-VERIFIER-S-TARGET
            SBOX-VERIFIER-D-INSTRUCTION-TARGET R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-FUNCTION = IF
        DROP
        R@ _SV-NONLITERAL-B-ZERO? 0= IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SVW.FUNCTION-N @ U< 0= IF
            SBOX-VERIFIER-S-TARGET
            SBOX-VERIFIER-D-INSTRUCTION-TARGET R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-ABORT = IF
        DROP
        R@ _SV-NONLITERAL-B-ZERO? 0= IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        0x0000FFFF U> IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-LOCAL = IF
        DROP
        R@ _SV-NONLITERAL-B-ZERO? 0= IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SVW.FUNCTION-LOCALS @ U< 0= IF
            SBOX-VERIFIER-S-TARGET
            SBOX-VERIFIER-D-INSTRUCTION-TARGET R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-LOOP-EXIT =
    OVER SBOX-MACHINE-OPERAND-LOOP-BODY = OR IF
        DROP
        R@ _SV-NONLITERAL-B-ZERO? 0= IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SV-CURRENT-FUNCTION-U U< 0= IF
            SBOX-VERIFIER-S-TARGET
            SBOX-VERIFIER-D-INSTRUCTION-TARGET R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OPERAND-IMPORT = IF
        DROP
        R@ _SV-NONLITERAL-B-ZERO? 0= IF
            SBOX-VERIFIER-S-FORMAT
            SBOX-VERIFIER-D-INSTRUCTION-OPERANDS R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        DUP R@ _SVW.IMPORT-N @ U< 0= IF
            DROP SBOX-VERIFIER-S-TARGET
            SBOX-VERIFIER-D-INSTRUCTION-TARGET R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        DROP
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN

    DROP SBOX-VERIFIER-S-OPCODE
    SBOX-VERIFIER-D-INSTRUCTION-OPCODE R@
    _SV-FAIL-CURRENT R> DROP ;

: _SV-VALIDATE-CURRENT-INSTRUCTION  ( workspace -- status )
    >R
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-FLAGS@ IF
        SBOX-VERIFIER-S-FORMAT
        SBOX-VERIFIER-D-INSTRUCTION-FLAGS R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN

    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@
    DUP SBOX-ABI-OPCODE-STATUS SBOX-MACHINE-S-OK <> IF
        DROP SBOX-VERIFIER-S-OPCODE
        SBOX-VERIFIER-D-INSTRUCTION-OPCODE R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN
    R@ _SVW.PROFILE @ SBOX-PROFILE-OPCODE-ENABLED?
    DROP 0= IF
        SBOX-VERIFIER-S-OPCODE
        SBOX-VERIFIER-D-INSTRUCTION-OPCODE R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN

    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@
    SBOX-ABI-OPERAND@
    DUP IF
        2DROP SBOX-VERIFIER-S-OPCODE
        SBOX-VERIFIER-D-INSTRUCTION-OPCODE R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN
    DROP R@ _SV-VALIDATE-OPERANDS
    R> DROP ;

: _SV-STORE-CURRENT-SCOPE  ( workspace -- )
    >R
    R@ _SVW.LOOP-DEPTH @ 0= IF
        0
    ELSE
        R@ _SVW.LOOP-DEPTH @ 1- R@ _SVW-LOOP[] @ 1+
    THEN
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-SCOPE[] !
    R> DROP ;

: _SV-VALIDATE-CURRENT-LOOP  ( workspace -- status )
    >R
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@
    DUP SBOX-MACHINE-OP-LOOP-ENTER = IF
        DROP
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SV-CURRENT-LOCAL-INDEX 1+ U> 0= IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-RECIPROCAL R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.LOOP-DEPTH @ R@ _SVW.INSTRUCTION-CAP @ U< 0= IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-NESTING R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.CURRENT-INDEX @
        R@ _SVW.LOOP-DEPTH @ R@ _SVW-LOOP[] !
        1 R@ _SVW.LOOP-DEPTH +!
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OP-LOOP-NEXT =
    OVER SBOX-MACHINE-OP-LOOP-NEXT-BY = OR IF
        DROP
        R@ _SVW.LOOP-DEPTH @ 0= IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-NESTING R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.LOOP-DEPTH @ 1- R@ _SVW-LOOP[] @
        R@ _SVW.PREFIX !
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SVW.PREFIX @ R@ _SVW.FUNCTION-START @ - 1+
        <> IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-RECIPROCAL R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R@ _SVW.PREFIX @ R@ _SV-INSTRUCTION[]
            _SV-INSTRUCTION-A@
        R@ _SV-CURRENT-LOCAL-INDEX 1+ <> IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-RECIPROCAL R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        -1 R@ _SVW.LOOP-DEPTH +!
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OP-LOOP-INDEX = IF
        DROP
        R@ _SVW.LOOP-DEPTH @ 0= IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-INDEX R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    SBOX-MACHINE-OP-RETURN = IF
        R@ _SVW.LOOP-DEPTH @ IF
            SBOX-VERIFIER-S-LOOP
            SBOX-VERIFIER-D-LOOP-RETURN R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
    THEN
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-VALIDATE-FUNCTION-INSTRUCTIONS  ( workspace -- status )
    >R
    0 R@ _SVW.LOOP-DEPTH !
    R@ _SVW.FUNCTION-START @ R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @
        R@ _SVW.FUNCTION-END @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SV-INSTRUCTION[]
        R@ _SVW.CURRENT-RECORD !
        R@ _SV-STORE-CURRENT-SCOPE

        R@ _SV-VALIDATE-CURRENT-INSTRUCTION DUP IF
            R> DROP EXIT
        THEN DROP
        R@ _SV-VALIDATE-CURRENT-LOOP DUP IF
            R> DROP EXIT
        THEN DROP
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT
    R@ _SVW.LOOP-DEPTH @ IF
        SBOX-VERIFIER-S-LOOP
        SBOX-VERIFIER-D-LOOP-NESTING
        R@ _SVW.FUNCTION-END @ 1- R@
        _SV-FAIL R> DROP EXIT
    THEN
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-SCOPE-MATCH?  ( source-index target-index workspace -- flag )
    >R
    R@ _SVW-SCOPE[] @
    SWAP R@ _SVW-SCOPE[] @ =
    R> DROP ;

: _SV-VALIDATE-FUNCTION-SCOPES  ( workspace -- status )
    >R
    R@ _SVW.FUNCTION-START @ R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @
        R@ _SVW.FUNCTION-END @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SV-INSTRUCTION[]
        R@ _SVW.CURRENT-RECORD !
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@

        DUP SBOX-MACHINE-OP-BR =
        OVER SBOX-MACHINE-OP-BR-ZERO = OR
        OVER SBOX-MACHINE-OP-BR-NONZERO = OR IF
            DROP
            R@ _SVW.CURRENT-INDEX @
            R@ _SVW.FUNCTION-START @
            R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@ +
            R@ _SV-SCOPE-MATCH? 0= IF
                SBOX-VERIFIER-S-LOOP
                SBOX-VERIFIER-D-LOOP-SCOPE R@
                _SV-FAIL-CURRENT R> DROP EXIT
            THEN
        ELSE
            DUP SBOX-MACHINE-OP-LOOP-ENTER = IF
                DROP
                R@ _SVW.CURRENT-INDEX @ 1+
                    R@ _SVW-SCOPE[] @
                R@ _SVW.CURRENT-INDEX @ 1+ <> IF
                    SBOX-VERIFIER-S-LOOP
                    SBOX-VERIFIER-D-LOOP-SCOPE R@
                    _SV-FAIL-CURRENT R> DROP EXIT
                THEN
                R@ _SVW.CURRENT-INDEX @ R@ _SVW-SCOPE[] @
                R@ _SVW.FUNCTION-START @
                R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@ +
                    R@ _SVW-SCOPE[] @ <> IF
                    SBOX-VERIFIER-S-LOOP
                    SBOX-VERIFIER-D-LOOP-SCOPE R@
                    _SV-FAIL-CURRENT R> DROP EXIT
                THEN
            ELSE
                DUP SBOX-MACHINE-OP-LOOP-NEXT =
                OVER SBOX-MACHINE-OP-LOOP-NEXT-BY = OR IF
                    DROP
                    R@ _SVW.FUNCTION-START @
                    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@ +
                    R@ _SVW.PREFIX !
                    R@ _SVW.CURRENT-INDEX @ R@ _SVW-SCOPE[] @
                    R@ _SVW.PREFIX @ <> IF
                        SBOX-VERIFIER-S-LOOP
                        SBOX-VERIFIER-D-LOOP-SCOPE R@
                        _SV-FAIL-CURRENT R> DROP EXIT
                    THEN
                    R@ _SVW.CURRENT-INDEX @
                    R@ _SVW.PREFIX @ R@
                    _SV-SCOPE-MATCH? 0= IF
                        SBOX-VERIFIER-S-LOOP
                        SBOX-VERIFIER-D-LOOP-SCOPE R@
                        _SV-FAIL-CURRENT R> DROP EXIT
                    THEN
                    R@ _SVW.PREFIX @ 1- R@ _SVW-SCOPE[] @
                    R@ _SVW.CURRENT-INDEX @ 1+
                        R@ _SVW-SCOPE[] @ <> IF
                        SBOX-VERIFIER-S-LOOP
                        SBOX-VERIFIER-D-LOOP-SCOPE R@
                        _SV-FAIL-CURRENT R> DROP EXIT
                    THEN
                ELSE
                    DROP
                THEN
            THEN
        THEN
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-VALIDATE-INSTRUCTIONS  ( workspace -- status )
    >R
    0 R@ _SVW.CURRENT-FUNCTION !
    BEGIN
        R@ _SVW.CURRENT-FUNCTION @
        R@ _SVW.FUNCTION-N @ <
    WHILE
        R@ _SVW.CURRENT-FUNCTION @
            R@ _SVW-FUNCTION-START[] @
            R@ _SVW.FUNCTION-START !
        R@ _SVW.CURRENT-FUNCTION @ 1+
            R@ _SVW-FUNCTION-START[] @
            R@ _SVW.FUNCTION-END !
        R@ _SVW.CURRENT-FUNCTION @ R@ _SV-FUNCTION[]
            R@ _SVW.CURRENT-RECORD !
        R@ _SVW.CURRENT-RECORD @ _SV-FUNCTION-LOCALS@
            R@ _SVW.FUNCTION-LOCALS !
        R@ _SVW.CURRENT-RECORD @ _SV-FUNCTION-RESULTS@
            R@ _SVW.FUNCTION-RESULTS !

        R@ _SV-VALIDATE-FUNCTION-INSTRUCTIONS DUP IF
            R> DROP EXIT
        THEN DROP
        R@ _SV-VALIDATE-FUNCTION-SCOPES DUP IF
            R> DROP EXIT
        THEN DROP
        1 R@ _SVW.CURRENT-FUNCTION +!
    REPEAT
    R> DROP SBOX-VERIFIER-S-OK ;

\ =====================================================================
\  Function-local CFG and exact operand-height proof
\ =====================================================================

: _SV-APPLY-EFFECT  ( pop push workspace -- status )
    >R
    R@ _SVW.NEXT-HEIGHT !
    R@ _SVW.PREFIX !
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-HEIGHT[] @
    DUP R@ _SVW.PREFIX @ < IF
        DROP SBOX-VERIFIER-S-STACK
        SBOX-VERIFIER-D-STACK-UNDERFLOW R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN
    R@ _SVW.PREFIX @ -
    R@ _SVW.NEXT-HEIGHT @ +
    DUP R@ _SVW.NEXT-HEIGHT !
    R@ _SVW.MAX-STACK @ > IF
        R@ _SVW.NEXT-HEIGHT @ R@ _SVW.MAX-STACK !
    THEN
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-FIXED-EFFECT  ( opcode workspace -- status )
    >R
    DUP SBOX-ABI-POP@
    DUP IF
        >R 2DROP R> DROP
        SBOX-VERIFIER-S-OPCODE
        SBOX-VERIFIER-D-INSTRUCTION-OPCODE R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN
    DROP SWAP
    SBOX-ABI-PUSH@
    DUP IF
        >R 2DROP R> DROP
        SBOX-VERIFIER-S-OPCODE
        SBOX-VERIFIER-D-INSTRUCTION-OPCODE R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN
    DROP R@ _SV-APPLY-EFFECT
    R> DROP ;

: _SV-TRANSFER-CURRENT  ( workspace -- status )
    >R
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@

    DUP SBOX-MACHINE-OP-RETURN = IF
        DROP
        R@ _SVW.CURRENT-INDEX @ R@ _SVW-HEIGHT[] @
        R@ _SVW.FUNCTION-RESULTS @ <> IF
            SBOX-VERIFIER-S-STACK
            SBOX-VERIFIER-D-STACK-RETURN R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OP-CALL = IF
        DROP
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SV-FUNCTION[] DUP _SV-FUNCTION-PARAMS@
        SWAP _SV-FUNCTION-RESULTS@
        R@ _SV-APPLY-EFFECT
        R> DROP EXIT
    THEN
    \ No profile this runtime loads enables an import, so the opcode check
    \ has already refused IMPORT.CALL.
    DUP SBOX-MACHINE-OP-IMPORT-CALL = IF
        DROP SBOX-VERIFIER-S-OPCODE SBOX-VERIFIER-D-INSTRUCTION-OPCODE
        R@ _SV-FAIL-CURRENT R> DROP EXIT
    THEN

    R@ _SV-FIXED-EFFECT
    R> DROP ;

: _SV-MERGE  ( height successor workspace -- status )
    >R
    DUP R@ _SVW-HEIGHT[] @
    DUP -1 = IF
        DROP
        2DUP R@ _SVW-HEIGHT[] !
        DUP
        R@ _SVW.QUEUE-TAIL @ R@ _SVW-QUEUE[] !
        1 R@ _SVW.QUEUE-TAIL +!
        2DROP R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    2 PICK = IF
        2DROP R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    SWAP DROP
    SBOX-VERIFIER-S-STACK
    SBOX-VERIFIER-D-STACK-MERGE ROT R@
    _SV-FAIL R> DROP ;

: _SV-MERGE-LOCAL  ( height local-target workspace -- status )
    >R
    R@ _SVW.FUNCTION-START @ +
    R> _SV-MERGE ;

: _SV-MERGE-FALLTHROUGH  ( height workspace -- status )
    >R
    R@ _SVW.CURRENT-INDEX @ 1+
    DUP R@ _SVW.FUNCTION-END @ U< 0= IF
        DROP DROP
        SBOX-VERIFIER-S-TARGET
        SBOX-VERIFIER-D-INSTRUCTION-TARGET R@
        _SV-FAIL-CURRENT R> DROP EXIT
    THEN
    R> _SV-MERGE ;

: _SV-PROPAGATE-CURRENT  ( workspace -- status )
    >R
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@
    DUP SBOX-MACHINE-OP-RETURN =
    OVER SBOX-MACHINE-OP-ABORT = OR IF
        DROP R> DROP SBOX-VERIFIER-S-OK EXIT
    THEN
    DUP SBOX-MACHINE-OP-BR = IF
        DROP
        R@ _SVW.NEXT-HEIGHT @
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R> _SV-MERGE-LOCAL EXIT
    THEN
    DUP SBOX-MACHINE-OP-BR-ZERO =
    OVER SBOX-MACHINE-OP-BR-NONZERO = OR IF
        DROP
        R@ _SVW.NEXT-HEIGHT @
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SV-MERGE-LOCAL
        DUP IF R> DROP EXIT THEN DROP
        R@ _SVW.NEXT-HEIGHT @
        R> _SV-MERGE-FALLTHROUGH EXIT
    THEN
    DUP SBOX-MACHINE-OP-LOOP-ENTER =
    OVER SBOX-MACHINE-OP-LOOP-NEXT = OR
    OVER SBOX-MACHINE-OP-LOOP-NEXT-BY = OR IF
        DROP
        R@ _SVW.NEXT-HEIGHT @
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
        R@ _SV-MERGE-LOCAL
        DUP IF R> DROP EXIT THEN DROP
        R@ _SVW.NEXT-HEIGHT @
        R> _SV-MERGE-FALLTHROUGH EXIT
    THEN
    DROP
    R@ _SVW.NEXT-HEIGHT @
    R> _SV-MERGE-FALLTHROUGH ;

: _SV-VERIFY-FUNCTION-CFG  ( workspace -- status )
    >R
    0 R@ _SVW.QUEUE-HEAD !
    1 R@ _SVW.QUEUE-TAIL !
    R@ _SVW.FUNCTION-START @ 0 R@ _SVW-QUEUE[] !

    R@ _SVW.CURRENT-FUNCTION @ R@ _SV-FUNCTION[]
    DUP _SV-FUNCTION-PARAMS@
    DUP R@ _SVW.MAX-STACK !
    R@ _SVW.FUNCTION-START @ R@ _SVW-HEIGHT[] !
    _SV-FUNCTION-RESULTS@ R@ _SVW.FUNCTION-RESULTS !

    BEGIN
        R@ _SVW.QUEUE-HEAD @ R@ _SVW.QUEUE-TAIL @ <
    WHILE
        R@ _SVW.QUEUE-HEAD @ R@ _SVW-QUEUE[] @
        R@ _SVW.CURRENT-INDEX !
        1 R@ _SVW.QUEUE-HEAD +!
        R@ _SVW.CURRENT-INDEX @ R@ _SV-INSTRUCTION[]
            R@ _SVW.CURRENT-RECORD !

        R@ _SV-TRANSFER-CURRENT DUP IF
            R> DROP EXIT
        THEN DROP
        R@ _SV-PROPAGATE-CURRENT DUP IF
            R> DROP EXIT
        THEN DROP
    REPEAT

    R@ _SVW.FUNCTION-START @ R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @ R@ _SVW.FUNCTION-END @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SVW-HEIGHT[] @ -1 = IF
            SBOX-VERIFIER-S-UNREACHABLE
            SBOX-VERIFIER-D-UNREACHABLE R@
            _SV-FAIL-CURRENT R> DROP EXIT
        THEN
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT

    R@ _SVW.MAX-STACK @
    R@ _SVW.CURRENT-FUNCTION @ R@ _SVW-FUNCTION-MAX[] !
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-VALIDATE-CFG  ( workspace -- status )
    >R
    0 R@ _SVW.CURRENT-FUNCTION !
    BEGIN
        R@ _SVW.CURRENT-FUNCTION @ R@ _SVW.FUNCTION-N @ <
    WHILE
        R@ _SVW.CURRENT-FUNCTION @
            R@ _SVW-FUNCTION-START[] @
            R@ _SVW.FUNCTION-START !
        R@ _SVW.CURRENT-FUNCTION @ 1+
            R@ _SVW-FUNCTION-START[] @
            R@ _SVW.FUNCTION-END !
        R@ _SV-VERIFY-FUNCTION-CFG DUP IF
            R> DROP EXIT
        THEN DROP
        1 R@ _SVW.CURRENT-FUNCTION +!
    REPEAT
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-TYPED-OPCODE?  ( opcode -- flag )
    DUP SBOX-ABI-OP-V-TYPE >=
    OVER SBOX-ABI-OP-V-BLOB-COPY <= AND
    SWAP
    DUP SBOX-ABI-OP-V-NEW-NULL >=
    SWAP SBOX-ABI-OP-V-NEW-MAP <= AND
    OR ;

: _SV-VALIDATE-ENTRY-SURFACE  ( workspace -- status )
    >R
    0 R@ _SV-ENTRY[] _SV-ENTRY-SIGNATURE@
        R@ _SVW.PREFIX !
    1 R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @ R@ _SVW.ENTRY-N @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SV-ENTRY[]
        _SV-ENTRY-SIGNATURE@
        R@ _SVW.PREFIX @ <> IF
            SBOX-VERIFIER-S-ENTRY
            SBOX-VERIFIER-D-ENTRY-SIGNATURE
            R@ _SVW.CURRENT-INDEX @ R@
            _SV-FAIL R> DROP EXIT
        THEN
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT

    R@ _SVW.PREFIX @ 0= IF
        0 R@ _SVW.CURRENT-INDEX !
        BEGIN
            R@ _SVW.CURRENT-INDEX @
            R@ _SVW.INSTRUCTION-N @ <
        WHILE
            R@ _SVW.CURRENT-INDEX @ R@ _SV-INSTRUCTION[]
            _SV-INSTRUCTION-OPCODE@
            _SV-TYPED-OPCODE? IF
                SBOX-VERIFIER-S-OPCODE
                SBOX-VERIFIER-D-INSTRUCTION-OPCODE
                R@ _SVW.CURRENT-INDEX @ R@
                _SV-FAIL R> DROP EXIT
            THEN
            1 R@ _SVW.CURRENT-INDEX +!
        REPEAT
    THEN

    R> DROP SBOX-VERIFIER-S-OK ;

\ =====================================================================
\  Decoded program
\ =====================================================================
\  Once every proof has passed, each instruction becomes the record the VM
\  executes (plan.f describes it).  Branch and loop targets become absolute
\  instruction indices, a call carries its callee's parameters, results,
\  first instruction, locals and whole fixed cost, and every record carries
\  the exact operand-stack height and lexical loop depth the proofs found
\  before the instruction.  The proofs have admitted every opcode, so a
\  metadata failure here is an internal error.

: _SV-DECODE-FAIL  ( workspace -- status )
    >R SBOX-VERIFIER-S-INTERNAL SBOX-VERIFIER-D-INTERNAL R@
    _SV-FAIL-CURRENT R> DROP ;

: _SV-DECODE-CALL  ( workspace -- status )
    >R
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
    DUP R@ _SV-FUNCTION[]
    SBOX-MACHINE-OP-CALL SBOX-ABI-BASE-COST@ IF
        2DROP DROP R> _SV-DECODE-FAIL EXIT
    THEN
    OVER _SV-FUNCTION-LOCALS@ SBOX-BYTE-CEIL8 IF
        2DROP 2DROP R> _SV-DECODE-FAIL EXIT
    THEN
    +
    >R
    SBOX-MACHINE-OP-CALL
    OVER _SV-FUNCTION-PARAMS@
    2 PICK _SV-FUNCTION-RESULTS@
    R> _SPD-HEAD
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] !
    \ ( callee function-record )
    OVER R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] CELL+ !
    _SV-FUNCTION-LOCALS@
    SWAP R@ _SVW-FUNCTION-START[] @
    SWAP _SPD-CALLEE
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] 2 CELLS + !
    R> DROP SBOX-VERIFIER-S-OK ;

\ A branch or loop operand names an instruction of the current function.
: _SV-DECODE-OPERAND  ( opcode workspace -- operand status )
    >R
    SBOX-ABI-OPERAND@ IF
        DROP 0 R> _SV-DECODE-FAIL EXIT
    THEN
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-A@
    SWAP
    DUP SBOX-MACHINE-OPERAND-BRANCH =
    OVER SBOX-MACHINE-OPERAND-LOOP-EXIT = OR
    SWAP SBOX-MACHINE-OPERAND-LOOP-BODY = OR IF
        R@ _SVW.FUNCTION-START @ +
    THEN
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-DECODE-FIXED  ( opcode workspace -- status )
    >R
    DUP SBOX-ABI-POP@ IF 2DROP R> _SV-DECODE-FAIL EXIT THEN
    OVER SBOX-ABI-PUSH@ IF 2DROP DROP R> _SV-DECODE-FAIL EXIT THEN
    2 PICK SBOX-ABI-BASE-COST@ IF
        2DROP 2DROP R> _SV-DECODE-FAIL EXIT
    THEN
    \ ( opcode pop push cost -- opcode head )
    >R >R >R DUP R> R> R> _SPD-HEAD
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] !
    R@ _SV-DECODE-OPERAND DUP IF NIP R> DROP EXIT THEN DROP
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] CELL+ !
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-B@
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] 2 CELLS + !
    R> DROP SBOX-VERIFIER-S-OK ;

\ DEPTH is the lexical loop depth before the current instruction.
: _SV-DECODE-CURRENT  ( depth workspace -- status )
    >R
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-HEIGHT[] @ SWAP _SPD-PLACE
    R@ _SVW.CURRENT-INDEX @ R@ _SVW-DECODED[] 3 CELLS + !
    R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@
    DUP SBOX-MACHINE-OP-CALL = IF
        DROP R> _SV-DECODE-CALL EXIT
    THEN
    R> _SV-DECODE-FIXED ;

: _SV-DECODE-FUNCTION  ( workspace -- status )
    >R
    0 R@ _SVW.LOOP-DEPTH !
    R@ _SVW.FUNCTION-START @ R@ _SVW.CURRENT-INDEX !
    BEGIN
        R@ _SVW.CURRENT-INDEX @ R@ _SVW.FUNCTION-END @ <
    WHILE
        R@ _SVW.CURRENT-INDEX @ R@ _SV-INSTRUCTION[]
            R@ _SVW.CURRENT-RECORD !
        R@ _SVW.LOOP-DEPTH @ R@ _SV-DECODE-CURRENT
        DUP IF R> DROP EXIT THEN DROP
        R@ _SVW.CURRENT-RECORD @ _SV-INSTRUCTION-OPCODE@
        DUP SBOX-MACHINE-OP-LOOP-ENTER = IF
            1 R@ _SVW.LOOP-DEPTH +!
        THEN
        DUP SBOX-MACHINE-OP-LOOP-NEXT =
        SWAP SBOX-MACHINE-OP-LOOP-NEXT-BY = OR IF
            -1 R@ _SVW.LOOP-DEPTH +!
        THEN
        1 R@ _SVW.CURRENT-INDEX +!
    REPEAT
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-DECODE  ( workspace -- status )
    >R
    0 R@ _SVW.CURRENT-FUNCTION !
    BEGIN
        R@ _SVW.CURRENT-FUNCTION @ R@ _SVW.FUNCTION-N @ <
    WHILE
        R@ _SVW.CURRENT-FUNCTION @
            R@ _SVW-FUNCTION-START[] @
            R@ _SVW.FUNCTION-START !
        R@ _SVW.CURRENT-FUNCTION @ 1+
            R@ _SVW-FUNCTION-START[] @
            R@ _SVW.FUNCTION-END !
        R@ _SV-DECODE-FUNCTION DUP IF
            R> DROP EXIT
        THEN DROP
        1 R@ _SVW.CURRENT-FUNCTION +!
    REPEAT
    R> DROP SBOX-VERIFIER-S-OK ;

\ =====================================================================
\  Final owned-plan publication and public verifier operation
\ =====================================================================

\ The plan keeps the artifact's content digest, computed here once every
\ proof has passed.
: _SV-PUBLISH  ( workspace -- status )
    >R
    R@ _SVW.ARTIFACT @ R@ _SVW.ARTIFACT-U @
    R@ _SVW-DIGEST R@ _SVW-DIGEST-WORK
    SBOX-DIGEST-ARTIFACT IF
        SBOX-VERIFIER-S-INTERNAL SBOX-VERIFIER-D-INTERNAL -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    R@ _SVW.ARTIFACT @
    R@ _SVW.ARTIFACT-U @
    R@ _SVW.LAYOUT
    R@ _SVW.PROFILE @
    R@ _SVW-DIGEST
    0 R@ _SVW-DECODED[]
    R@ _SVW.PLAN @
    R@ _SVW.PLAN-U @
    SBOX-PLAN-PUBLISH-VERIFIED
    DUP IF
        _SV-PLAN>STATUS
        R@ _SVW.PLAN @ R@ _SVW.PLAN-U @ 0 FILL
        SBOX-VERIFIER-D-PLAN-PUBLISH -1 R@
        _SV-FAIL R> DROP EXIT
    THEN
    DROP
    SBOX-VERIFIER-S-OK R@ _SVW.STATUS !
    SBOX-VERIFIER-D-NONE R@ _SVW.DETAIL !
    -1 R@ _SVW.ERROR-INDEX !
    R> DROP SBOX-VERIFIER-S-OK ;

: _SV-VERIFY-INTERNAL  ( workspace -- status )
    DUP _SV-LOAD-ARTIFACT DUP IF NIP EXIT THEN DROP
    DUP _SV-VALIDATE-FUNCTIONS DUP IF NIP EXIT THEN DROP
    DUP _SV-VALIDATE-ENTRIES DUP IF NIP EXIT THEN DROP
    DUP _SV-VALIDATE-INSTRUCTIONS DUP IF NIP EXIT THEN DROP
    DUP _SV-VALIDATE-ENTRY-SURFACE DUP IF NIP EXIT THEN DROP
    DUP _SV-VALIDATE-CFG DUP IF NIP EXIT THEN DROP
    DUP _SV-DECODE DUP IF NIP EXIT THEN DROP
    _SV-PUBLISH ;

: _SV-VERIFY-CONTAINED  ( workspace -- status )
    DUP >R
    ['] _SV-VERIFY-INTERNAL CATCH
    ?DUP IF
        DROP
        DUP _SVW.PLAN @ OVER _SVW.PLAN-U @ 0 FILL
        DROP
        SBOX-VERIFIER-S-INTERNAL
        SBOX-VERIFIER-D-INTERNAL -1 R@
        _SV-FAIL
        R> DROP EXIT
    THEN
    R> DROP ;

\ Public API:
\   SBOX-VERIFY
\     ( artifact artifact-u profile plan plan-u workspace -- status )
\
\ The destination capacity is exact: plan-u must equal
\ SBOX-PLAN-MEASURE(artifact, artifact-u), and the artifact is no larger
\ than the format's ceiling.  This bounds admission and failure scrubbing.
\ The workspace is SBOX-VERIFIER-WORKSPACE-MEASURE bytes for the profile.
: SBOX-VERIFY
  ( artifact artifact-u profile plan plan-u workspace -- status )
    _SV-DUP6 _SV-ADMIT
    DUP IF
        _SV-DROP6>STATUS EXIT
    THEN
    DROP

    \ All four caller spans are now qualified and pairwise disjoint.  The
    \ plan stays wholly zero until the final plan publication operation.
    2 PICK 2 PICK 0 FILL
    _SV-WORKSPACE-INIT
    _SV-VERIFY-CONTAINED ;
