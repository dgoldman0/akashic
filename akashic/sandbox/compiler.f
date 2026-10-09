\ =====================================================================
\  compiler.f - Bounded non-evaluating sandbox frontend
\ =====================================================================
\  Source is tokenized and lowered as inert bytes.  No source byte is ever
\  offered to FIND, EVALUATE, an execution token, an include mechanism, or
\  native Forth compilation.
\
\  All mutable state, fixups, control frames, emitted records, and the complete
\  candidate staging image live in one caller-owned workspace.  The caller's
\  candidate is copied only after parsing, resolution, canonical construction,
\  and an independent geometry inspection all succeed.  Compiler output is
\  still untrusted and never becomes execution authority without the separate
\  verifier.
\ =====================================================================

REQUIRE candidate.f
REQUIRE profile.f
REQUIRE abi.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

PROVIDED akashic-sbx-compiler

\ Public completion status.
0 CONSTANT SBOX-COMPILER-S-OK
1 CONSTANT SBOX-COMPILER-S-INVALID
2 CONSTANT SBOX-COMPILER-S-CAPACITY
3 CONSTANT SBOX-COMPILER-S-ALIAS
4 CONSTANT SBOX-COMPILER-S-SOURCE
5 CONSTANT SBOX-COMPILER-S-PROFILE
6 CONSTANT SBOX-COMPILER-S-INTERNAL

: SBOX-COMPILER-STATUS-VALID?  ( status -- flag )
    DUP SBOX-COMPILER-S-OK >=
    SWAP SBOX-COMPILER-S-INTERNAL <= AND ;

\ Diagnostic codes.  The first failure of a compilation records its code
\ and, where one exists, the offset and length of the source bytes that
\ caused it; otherwise its offset is -1.  See source-language.md.
 0 CONSTANT SBOX-COMPILER-E-NONE
 1 CONSTANT SBOX-COMPILER-E-BYTE
 2 CONSTANT SBOX-COMPILER-E-BACKSLASH
 3 CONSTANT SBOX-COMPILER-E-TOKEN-LENGTH
 4 CONSTANT SBOX-COMPILER-E-END
 5 CONSTANT SBOX-COMPILER-E-EXPECTED-FUNCTION
 6 CONSTANT SBOX-COMPILER-E-EXPECTED-ENTRY
 7 CONSTANT SBOX-COMPILER-E-EXPECTED-PARAMS
 8 CONSTANT SBOX-COMPILER-E-EXPECTED-RESULTS
 9 CONSTANT SBOX-COMPILER-E-EXPECTED-LOCALS
10 CONSTANT SBOX-COMPILER-E-NAME
11 CONSTANT SBOX-COMPILER-E-DUPLICATE
12 CONSTANT SBOX-COMPILER-E-NUMBER
13 CONSTANT SBOX-COMPILER-E-UNKNOWN
14 CONSTANT SBOX-COMPILER-E-UNMATCHED
15 CONSTANT SBOX-COMPILER-E-UNREACHABLE
16 CONSTANT SBOX-COMPILER-E-OPEN-CONTROL
17 CONSTANT SBOX-COMPILER-E-FALLTHROUGH
18 CONSTANT SBOX-COMPILER-E-RETURN-IN-LOOP
19 CONSTANT SBOX-COMPILER-E-LOOP-INDEX
20 CONSTANT SBOX-COMPILER-E-LOCAL-INDEX
21 CONSTANT SBOX-COMPILER-E-UNDEFINED-CALL
22 CONSTANT SBOX-COMPILER-E-ENTRY-ORDER
23 CONSTANT SBOX-COMPILER-E-ENTRY-FUNCTION
24 CONSTANT SBOX-COMPILER-E-SIGNATURE
25 CONSTANT SBOX-COMPILER-E-SIGNATURE-MIX
26 CONSTANT SBOX-COMPILER-E-SCALAR-TYPED
27 CONSTANT SBOX-COMPILER-E-LIMIT
28 CONSTANT SBOX-COMPILER-E-DISABLED
29 CONSTANT SBOX-COMPILER-E-PROFILE
30 CONSTANT SBOX-COMPILER-E-INTERNAL

\ Private tokenizer completion.  It never escapes SBOX-COMPILE.
7 CONSTANT _SCC-S-EOF

\ A token, and so every name, is 1 through 63 bytes.  This is a rule of the
\ language, and the ABI's entry-name limit.
SBOX-ABI-ENTRY-NAME-MAX CONSTANT SBOX-COMPILER-TOKEN-MAX

\ =====================================================================
\  Caller-owned workspace, measured from the profile
\ =====================================================================

\ Diagnostic header.  It holds the last status, the first failure and,
\ after a success, the instruction count.  With the source map it is all a
\ compilation leaves behind, and neither holds a pointer.
0x5342584344494147 CONSTANT _SCC-DIAG-MAGIC  \ "SBXCDIAG"
  0 CONSTANT _SCD-MAGIC
  8 CONSTANT _SCD-STATUS
 16 CONSTANT _SCD-CODE
 24 CONSTANT _SCD-OFFSET
 32 CONSTANT _SCD-LENGTH
 40 CONSTANT _SCD-INSTRUCTION-N
48 CONSTANT SBOX-COMPILER-DIAGNOSTIC-SIZE

\ Scalar operation state follows the header at fixed offsets.
SBOX-COMPILER-DIAGNOSTIC-SIZE CONSTANT _SCW-BASE
_SCW-BASE   0 + CONSTANT _SCW-SOURCE-A
_SCW-BASE   8 + CONSTANT _SCW-SOURCE-U
_SCW-BASE  16 + CONSTANT _SCW-SOURCE-POS
_SCW-BASE  24 + CONSTANT _SCW-TOKEN-A
_SCW-BASE  32 + CONSTANT _SCW-TOKEN-U
_SCW-BASE  40 + CONSTANT _SCW-PROFILE
_SCW-BASE  48 + CONSTANT _SCW-MEMORY-U
_SCW-BASE  56 + CONSTANT _SCW-CANDIDATE
_SCW-BASE  64 + CONSTANT _SCW-CANDIDATE-CAP
_SCW-BASE  72 + CONSTANT _SCW-FUNCTION-N
_SCW-BASE  80 + CONSTANT _SCW-ENTRY-N
_SCW-BASE  88 + CONSTANT _SCW-NAME-U
_SCW-BASE  96 + CONSTANT _SCW-INSTRUCTION-N
_SCW-BASE 104 + CONSTANT _SCW-FIXUP-N
_SCW-BASE 112 + CONSTANT _SCW-CONTROL-N
_SCW-BASE 120 + CONSTANT _SCW-DO-N
_SCW-BASE 128 + CONSTANT _SCW-CURRENT-FUNCTION
_SCW-BASE 136 + CONSTANT _SCW-CURRENT-START
_SCW-BASE 144 + CONSTANT _SCW-CURRENT-LOCALS
_SCW-BASE 152 + CONSTANT _SCW-REACHABLE
_SCW-BASE 160 + CONSTANT _SCW-PROFILE-TAG
_SCW-BASE 168 + CONSTANT _SCW-FUNCTION-LIMIT
_SCW-BASE 176 + CONSTANT _SCW-ENTRY-LIMIT
_SCW-BASE 184 + CONSTANT _SCW-INSTRUCTION-LIMIT
_SCW-BASE 192 + CONSTANT _SCW-NAME-BYTES-LIMIT
_SCW-BASE 200 + CONSTANT _SCW-FIXUP-LIMIT
_SCW-BASE 208 + CONSTANT _SCW-CONTROL-LIMIT
_SCW-BASE 216 + CONSTANT _SCW-STAGE-LIMIT
_SCW-BASE 224 + CONSTANT _SCW-TMP-OPCODE
_SCW-BASE 232 + CONSTANT _SCW-TMP-A
_SCW-BASE 240 + CONSTANT _SCW-TMP-B
_SCW-BASE 248 + CONSTANT _SCW-TMP-X
_SCW-BASE 256 + CONSTANT _SCW-SAVED-A
_SCW-BASE 264 + CONSTANT _SCW-SAVED-B
_SCW-BASE 272 + CONSTANT _SCW-FORM-A
_SCW-BASE 280 + CONSTANT _SCW-FMETA-OFF
_SCW-BASE 288 + CONSTANT _SCW-FNAME-OFF
_SCW-BASE 296 + CONSTANT _SCW-EMETA-OFF
_SCW-BASE 304 + CONSTANT _SCW-NAMES-OFF
_SCW-BASE 312 + CONSTANT _SCW-INSTRUCTIONS-OFF
_SCW-BASE 320 + CONSTANT _SCW-FIXUPS-OFF
_SCW-BASE 328 + CONSTANT _SCW-CONTROL-OFF
_SCW-BASE 336 + CONSTANT _SCW-LAYOUT-OFF
_SCW-BASE 344 + CONSTANT _SCW-STAGE-OFF
_SCW-BASE 352 + CONSTANT _SCW-TOTAL

\ The source map follows the state.  It holds the source span each
\ instruction came from, one cell per instruction with the offset in the
\ high half and the length in the low half.
_SCW-BASE 360 + CONSTANT _SCD-MAP

\ Function metadata: name-u, params, results, locals, instruction-start,
\ instruction-n.  Names occupy a separate slot per function.
48 CONSTANT _SCC-FMETA-SIZE
 0 CONSTANT _SCFM-NAME-U
 8 CONSTANT _SCFM-PARAMS
16 CONSTANT _SCFM-RESULTS
24 CONSTANT _SCFM-LOCALS
32 CONSTANT _SCFM-INSTRUCTION-START
40 CONSTANT _SCFM-INSTRUCTION-N

\ Entry metadata: name offset, name length, resolved function index, signature.
32 CONSTANT _SCC-EMETA-SIZE
 0 CONSTANT _SCEM-NAME-OFF
 8 CONSTANT _SCEM-NAME-U
16 CONSTANT _SCEM-FUNCTION
24 CONSTANT _SCEM-SIGNATURE

\ One source-backed direct-call fixup per call.
24 CONSTANT _SCC-FIXUP-SIZE
 0 CONSTANT _SCFX-INSTRUCTION
 8 CONSTANT _SCFX-NAME-A
16 CONSTANT _SCFX-NAME-U

\ Typed lexical control frame: kind and three kind-specific scalar fields.
32 CONSTANT _SCC-CONTROL-SIZE
 0 CONSTANT _SCCF-KIND
 8 CONSTANT _SCCF-A
16 CONSTANT _SCCF-B
24 CONSTANT _SCCF-C

: _SCW.SOURCE-A         ( w -- a ) _SCW-SOURCE-A + ;
: _SCW.SOURCE-U         ( w -- a ) _SCW-SOURCE-U + ;
: _SCW.SOURCE-POS       ( w -- a ) _SCW-SOURCE-POS + ;
: _SCW.TOKEN-A          ( w -- a ) _SCW-TOKEN-A + ;
: _SCW.TOKEN-U          ( w -- a ) _SCW-TOKEN-U + ;
: _SCW.PROFILE          ( w -- a ) _SCW-PROFILE + ;
: _SCW.MEMORY-U         ( w -- a ) _SCW-MEMORY-U + ;
: _SCW.CANDIDATE        ( w -- a ) _SCW-CANDIDATE + ;
: _SCW.CANDIDATE-CAP    ( w -- a ) _SCW-CANDIDATE-CAP + ;
: _SCW.FUNCTION-N       ( w -- a ) _SCW-FUNCTION-N + ;
: _SCW.ENTRY-N          ( w -- a ) _SCW-ENTRY-N + ;
: _SCW.NAME-U           ( w -- a ) _SCW-NAME-U + ;
: _SCW.INSTRUCTION-N    ( w -- a ) _SCW-INSTRUCTION-N + ;
: _SCW.FIXUP-N          ( w -- a ) _SCW-FIXUP-N + ;
: _SCW.CONTROL-N        ( w -- a ) _SCW-CONTROL-N + ;
: _SCW.DO-N             ( w -- a ) _SCW-DO-N + ;
: _SCW.CURRENT-FUNCTION ( w -- a ) _SCW-CURRENT-FUNCTION + ;
: _SCW.CURRENT-START    ( w -- a ) _SCW-CURRENT-START + ;
: _SCW.CURRENT-LOCALS   ( w -- a ) _SCW-CURRENT-LOCALS + ;
: _SCW.REACHABLE        ( w -- a ) _SCW-REACHABLE + ;
: _SCW.PROFILE-TAG      ( w -- a ) _SCW-PROFILE-TAG + ;
: _SCW.FUNCTION-LIMIT   ( w -- a ) _SCW-FUNCTION-LIMIT + ;
: _SCW.ENTRY-LIMIT      ( w -- a ) _SCW-ENTRY-LIMIT + ;
: _SCW.INSTRUCTION-LIMIT
    ( w -- a ) _SCW-INSTRUCTION-LIMIT + ;
: _SCW.TMP-OPCODE       ( w -- a ) _SCW-TMP-OPCODE + ;
: _SCW.TMP-A            ( w -- a ) _SCW-TMP-A + ;
: _SCW.TMP-B            ( w -- a ) _SCW-TMP-B + ;
: _SCW.TMP-X            ( w -- a ) _SCW-TMP-X + ;
: _SCW.SAVED-A          ( w -- a ) _SCW-SAVED-A + ;
: _SCW.SAVED-B          ( w -- a ) _SCW-SAVED-B + ;
: _SCW.FORM-A           ( w -- a ) _SCW-FORM-A + ;
: _SCW.NAME-BYTES-LIMIT ( w -- a ) _SCW-NAME-BYTES-LIMIT + ;
: _SCW.FIXUP-LIMIT      ( w -- a ) _SCW-FIXUP-LIMIT + ;
: _SCW.CONTROL-LIMIT    ( w -- a ) _SCW-CONTROL-LIMIT + ;
: _SCW.STAGE-LIMIT      ( w -- a ) _SCW-STAGE-LIMIT + ;
: _SCW.TOTAL            ( w -- a ) _SCW-TOTAL + ;

: _SCD.MAGIC   ( w -- a ) _SCD-MAGIC + ;
: _SCD.STATUS  ( w -- a ) _SCD-STATUS + ;
: _SCD.CODE    ( w -- a ) _SCD-CODE + ;
: _SCD.OFFSET  ( w -- a ) _SCD-OFFSET + ;
: _SCD.LENGTH  ( w -- a ) _SCD-LENGTH + ;
: _SCD.INSTRUCTION-N  ( w -- a ) _SCD-INSTRUCTION-N + ;
: _SCD-MAP-CELL  ( index w -- a ) _SCD-MAP + SWAP 8 * + ;

\ Records the first failure at an explicit source span.
: _SCC-FAIL-AT  ( status code offset length workspace -- status )
    >R
    R@ _SCD.CODE @ IF 2DROP DROP R> DROP EXIT THEN
    R@ _SCD.LENGTH ! R@ _SCD.OFFSET ! R@ _SCD.CODE !
    R> DROP ;

\ Records the first failure at the current token, or at the scan position
\ when no token is current.
: _SCC-FAIL  ( status code workspace -- status )
    >R
    R@ _SCW.TOKEN-A @ ?DUP IF
        R@ _SCW.SOURCE-A @ - R@ _SCW.TOKEN-U @
    ELSE
        R@ _SCW.SOURCE-POS @ 0
    THEN
    R> _SCC-FAIL-AT ;

\ Records the first failure that no source span caused.
: _SCC-FAIL-GLOBAL  ( status code workspace -- status )
    >R -1 0 R> _SCC-FAIL-AT ;

: _SCC-FMETA  ( index w -- a )
    DUP _SCW-FMETA-OFF + @ + SWAP _SCC-FMETA-SIZE * + ;

\ A function's name slot holds the longest name, padded to a cell.
SBOX-COMPILER-TOKEN-MAX 7 + -8 AND CONSTANT _SCC-NAME-SLOT-SIZE

: _SCC-FNAME  ( index w -- a )
    DUP _SCW-FNAME-OFF + @ + SWAP _SCC-NAME-SLOT-SIZE * + ;

: _SCC-EMETA  ( index w -- a )
    DUP _SCW-EMETA-OFF + @ + SWAP _SCC-EMETA-SIZE * + ;

: _SCC-ENTRY-NAMES  ( w -- a ) DUP _SCW-NAMES-OFF + @ + ;

: _SCC-INSTRUCTION  ( index w -- a )
    DUP _SCW-INSTRUCTIONS-OFF + @ +
    SWAP SBOX-CANDIDATE-INSTRUCTION-SIZE * + ;

: _SCC-FIXUP  ( index w -- a )
    DUP _SCW-FIXUPS-OFF + @ + SWAP _SCC-FIXUP-SIZE * + ;

: _SCC-CONTROL  ( index w -- a )
    DUP _SCW-CONTROL-OFF + @ + SWAP _SCC-CONTROL-SIZE * + ;

: _SCC-LAYOUT  ( w -- a ) DUP _SCW-LAYOUT-OFF + @ + ;
: _SCC-STAGE   ( w -- a ) DUP _SCW-STAGE-OFF + @ + ;

\ =====================================================================
\  What one compilation can hold
\ =====================================================================
\  The workspace is sized from the source.  One forward pass counts every
\  run of nonblank bytes, and the runs that spell FUNCTION, ENTRY, CALL, or
\  IF, BEGIN and DO.  Every token is one run and emits at most one
\  instruction; only IF, BEGIN and DO open a control frame; every call is
\  CALL and every declaration is FUNCTION or ENTRY.  So each count bounds a
\  table, and runs inside comments only make the bound looser.  The format's
\  ceilings bound each one too.  A compilation that would exceed a table
\  still fails with LIMIT, so a bound can never overrun the workspace.

: _SCC-WHITESPACE?  ( byte -- flag )
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 10 = IF DROP -1 EXIT THEN
    DUP 13 = IF DROP -1 EXIT THEN
    32 = ;

\ The run of nonblank bytes at ADDRESS, within LENGTH.
: _SCC-RUN-U  ( address length -- run-u )
    DUP >R 0 ?DO
        DUP I + C@ _SCC-WHITESPACE? IF DROP I UNLOOP R> DROP EXIT THEN
    LOOP
    DROP R> ;

\ 1 FUNCTION, 2 ENTRY, 3 CALL, 4 IF, BEGIN or DO, and 0 for any other run.
: _SCC-RUN-KIND  ( address length -- kind )
    2DUP S" FUNCTION" COMPARE 0= IF 2DROP 1 EXIT THEN
    2DUP S" ENTRY" COMPARE 0= IF 2DROP 2 EXIT THEN
    2DUP S" CALL" COMPARE 0= IF 2DROP 3 EXIT THEN
    2DUP S" IF" COMPARE 0= IF 2DROP 4 EXIT THEN
    2DUP S" BEGIN" COMPARE 0= IF 2DROP 4 EXIT THEN
    S" DO" COMPARE 0= IF 4 ELSE 0 THEN ;

\ The counts live on the data stack and the scan position on the return
\ stack, so the pass needs no storage.
: _SCC-SCAN  ( source source-u -- runs functions entries calls opens )
    OVER + >R >R
    0 0 0 0 0
    BEGIN
        BEGIN
            R@ R> R@ SWAP >R < IF R@ C@ _SCC-WHITESPACE? ELSE 0 THEN
        WHILE
            R> 1+ >R
        REPEAT
        R@ R> R@ SWAP >R <
    WHILE
        R@ DUP R> R@ SWAP >R SWAP - 2DUP _SCC-RUN-U NIP
        2DUP _SCC-RUN-KIND SWAP R> + >R NIP
        >R >R >R >R >R 1+ R> R> R> R>
        R> CASE
            1 OF >R >R >R 1+ R> R> R> ENDOF
            2 OF >R >R 1+ R> R> ENDOF
            3 OF >R 1+ R> ENDOF
            4 OF 1+ ENDOF
        ENDCASE
    REPEAT
    R> R> 2DROP ;

\ The capacities one scan gives, each within the format's ceiling.
: _SCC-CAPACITIES
  ( source source-u -- functions entries instructions fixups opens )
    _SCC-SCAN
    >R >R >R
    SBOX-CANDIDATE-FUNCTION-MAX MIN
    R> SBOX-CANDIDATE-ENTRY-MAX MIN
    ROT SBOX-CANDIDATE-INSTRUCTION-MAX MIN
    R> R> ;

: _SCC-NAME-BYTES-CAP  ( entries -- bytes )
    SBOX-COMPILER-TOKEN-MAX * SBOX-CANDIDATE-NAME-BYTES-MAX MIN ;

\ The largest candidate the compilation can write: its functions, entries
\ and instructions, every entry name at the longest name, and no imports
\ or initial bytes, which the compiler never emits.
: _SCC-CANDIDATE-CAP  ( functions entries instructions -- bytes )
    SBOX-CANDIDATE-INSTRUCTION-SIZE *
    SWAP DUP SBOX-CANDIDATE-ENTRY-SIZE * SWAP
    _SCC-NAME-BYTES-CAP 7 + -8 AND + +
    SWAP SBOX-CANDIDATE-FUNCTION-SIZE * +
    SBOX-CANDIDATE-HEADER-SIZE + ;

\ Adds COUNT records of SIZE bytes at OFFSET, padded to a cell, and records
\ OFFSET in FIELD of WORKSPACE unless WORKSPACE is 0.  Every count is
\ within the format's ceilings, so no size overflows.
: _SCC-REGION  ( offset count size field workspace|0 -- offset' )
    ?DUP IF + 3 PICK SWAP ! ELSE DROP THEN
    * 7 + -8 AND + ;

: _SCC-LIMIT!  ( value field workspace|0 -- )
    ?DUP IF + ! ELSE 2DROP THEN ;

\ The workspace size for SOURCE.  With a workspace it also records each
\ capacity and where each region starts.  Fixups are one per CALL and
\ control frames one per IF, BEGIN or DO, and neither can outnumber the
\ instructions.
: _SCC-GEOMETRY  ( source source-u workspace|0 -- bytes )
    >R _SCC-CAPACITIES
    2 PICK MIN SWAP 2 PICK MIN SWAP
    \ ( functions entries instructions fixups frames )
    DUP _SCW-CONTROL-LIMIT R@ _SCC-LIMIT!
    OVER _SCW-FIXUP-LIMIT R@ _SCC-LIMIT!
    2 PICK _SCW-INSTRUCTION-LIMIT R@ _SCC-LIMIT!
    3 PICK _SCW-ENTRY-LIMIT R@ _SCC-LIMIT!
    4 PICK _SCW-FUNCTION-LIMIT R@ _SCC-LIMIT!
    3 PICK _SCC-NAME-BYTES-CAP _SCW-NAME-BYTES-LIMIT R@ _SCC-LIMIT!
    4 PICK 4 PICK 4 PICK _SCC-CANDIDATE-CAP
        _SCW-STAGE-LIMIT R@ _SCC-LIMIT!
    _SCD-MAP 3 PICK 8 * +
    5 PICK _SCC-FMETA-SIZE _SCW-FMETA-OFF R@ _SCC-REGION
    5 PICK _SCC-NAME-SLOT-SIZE _SCW-FNAME-OFF R@ _SCC-REGION
    4 PICK _SCC-EMETA-SIZE _SCW-EMETA-OFF R@ _SCC-REGION
    1 5 PICK _SCC-NAME-BYTES-CAP _SCW-NAMES-OFF R@ _SCC-REGION
    3 PICK SBOX-CANDIDATE-INSTRUCTION-SIZE
        _SCW-INSTRUCTIONS-OFF R@ _SCC-REGION
    2 PICK _SCC-FIXUP-SIZE _SCW-FIXUPS-OFF R@ _SCC-REGION
    OVER _SCC-CONTROL-SIZE _SCW-CONTROL-OFF R@ _SCC-REGION
    1 SBOX-CANDIDATE-LAYOUT-SIZE _SCW-LAYOUT-OFF R@ _SCC-REGION
    1 6 PICK 6 PICK 6 PICK _SCC-CANDIDATE-CAP
        _SCW-STAGE-OFF R@ _SCC-REGION
    >R 2DROP 2DROP DROP R> R> DROP ;

: _SCC-SOURCE-STATUS  ( source source-u -- status )
    DUP 0< IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    DUP 0= IF 2DROP SBOX-COMPILER-S-OK EXIT THEN
    OVER 0= IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS IF SBOX-COMPILER-S-INVALID ELSE SBOX-COMPILER-S-OK THEN ;

\ The workspace SBOX-COMPILE needs for SOURCE.
: SBOX-COMPILER-WORKSPACE-MEASURE  ( source source-u -- bytes status )
    2DUP _SCC-SOURCE-STATUS ?DUP IF NIP NIP 0 SWAP EXIT THEN
    0 _SCC-GEOMETRY SBOX-COMPILER-S-OK ;

\ The leading bytes of the workspace a compilation of SOURCE leaves
\ behind: the diagnostic header and the source map, with the state between
\ them already wiped.  Callers scrub them before they reuse or free it.
: SBOX-COMPILER-DIAGNOSTIC-MEASURE  ( source source-u -- bytes status )
    2DUP _SCC-SOURCE-STATUS ?DUP IF NIP NIP 0 SWAP EXIT THEN
    _SCC-CAPACITIES 2DROP NIP NIP 8 * _SCD-MAP + SBOX-COMPILER-S-OK ;

\ The largest candidate SBOX-COMPILE can write for SOURCE.
: SBOX-COMPILER-CANDIDATE-MAX  ( source source-u -- candidate-u status )
    2DUP _SCC-SOURCE-STATUS ?DUP IF NIP NIP 0 SWAP EXIT THEN
    _SCC-CAPACITIES 2DROP _SCC-CANDIDATE-CAP SBOX-COMPILER-S-OK ;


\ =====================================================================
\  Caller-memory admission and exact alias boundary
\ =====================================================================

: _SCC-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    DUP 0= IF 2DROP SBOX-COMPILER-S-OK EXIT THEN
    OVER 0= IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP SBOX-COMPILER-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS IF
        SBOX-COMPILER-S-INVALID
    ELSE
        SBOX-COMPILER-S-OK
    THEN ;

: _SCC-WORKSPACE-STATUS  ( workspace length -- status )
    OVER 0= IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP SBOX-COMPILER-S-INVALID EXIT THEN
    _SCC-SPAN-STATUS ;

\ Preserve all seven API inputs and append one status.  The source comes
\ first, because it measures the workspace.
\ Stack input: source source-u profile memory-u candidate candidate-cap
\              workspace
\ Stack output: the same seven inputs followed by status
: _SCC-BOUNDARY
    6 PICK 6 PICK SBOX-COMPILER-WORKSPACE-MEASURE ?DUP IF NIP EXIT THEN
    >R
    DUP R@ _SCC-WORKSPACE-STATUS ?DUP IF R> DROP EXIT THEN
    \ Guest memory is any whole number of cells; how much a run may have is
    \ the host's policy.
    3 PICK DUP 0< SWAP 7 AND OR IF R> DROP SBOX-COMPILER-S-INVALID EXIT THEN
    4 PICK SBOX-PROFILE-SIZE _SCC-SPAN-STATUS ?DUP IF R> DROP EXIT THEN
    2 PICK 2 PICK _SCC-SPAN-STATUS ?DUP IF R> DROP EXIT THEN

    \ source/profile
    6 PICK 6 PICK
    6 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? IF
        R> DROP SBOX-COMPILER-S-ALIAS EXIT
    THEN
    \ source/candidate
    6 PICK 6 PICK 4 PICK 4 PICK MSPAN-OVERLAP? IF
        R> DROP SBOX-COMPILER-S-ALIAS EXIT
    THEN
    \ source/workspace
    6 PICK 6 PICK 2 PICK R@
        MSPAN-OVERLAP? IF R> DROP SBOX-COMPILER-S-ALIAS EXIT THEN
    \ profile/candidate
    4 PICK SBOX-PROFILE-SIZE 4 PICK 4 PICK
        MSPAN-OVERLAP? IF R> DROP SBOX-COMPILER-S-ALIAS EXIT THEN
    \ profile/workspace
    4 PICK SBOX-PROFILE-SIZE 2 PICK R@
        MSPAN-OVERLAP? IF R> DROP SBOX-COMPILER-S-ALIAS EXIT THEN
    \ candidate/workspace
    2 PICK 2 PICK 2 PICK R@
        MSPAN-OVERLAP? IF R> DROP SBOX-COMPILER-S-ALIAS EXIT THEN

    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP DROP ;

\ =====================================================================
\  ASCII tokenizer and canonical scalar parsing
\ =====================================================================

: _SCC-SOURCE-BYTE?  ( byte -- flag )
    DUP _SCC-WHITESPACE? IF DROP -1 EXIT THEN
    33 127 WITHIN ;

\ The offset of the first byte the language does not admit, or -1.
: _SCC-BAD-BYTE  ( workspace -- offset|-1 )
    >R
    0
    BEGIN DUP R@ _SCW.SOURCE-U @ U< WHILE
        R@ _SCW.SOURCE-A @ OVER + C@ _SCC-SOURCE-BYTE? 0= IF
            R> DROP EXIT
        THEN
        1+
    REPEAT
    DROP R> DROP -1 ;

: _SCC-SKIP-COMMENT  ( workspace -- )
    >R
    1 R@ _SCW.SOURCE-POS +!
    BEGIN
        R@ _SCW.SOURCE-POS @ R@ _SCW.SOURCE-U @ U<
    WHILE
        R@ _SCW.SOURCE-A @ R@ _SCW.SOURCE-POS @ + C@
        DUP 10 = SWAP 13 = OR IF R> DROP EXIT THEN
        1 R@ _SCW.SOURCE-POS +!
    REPEAT
    R> DROP ;

: _SCC-SKIP-IGNORED  ( workspace -- status )
    >R
    BEGIN
        R@ _SCW.SOURCE-POS @ R@ _SCW.SOURCE-U @ U< 0= IF
            R> DROP _SCC-S-EOF EXIT
        THEN
        R@ _SCW.SOURCE-A @ R@ _SCW.SOURCE-POS @ + C@
        DUP _SCC-WHITESPACE? IF
            DROP 1 R@ _SCW.SOURCE-POS +!
        ELSE
            [CHAR] \ = IF
                R@ _SCC-SKIP-COMMENT
            ELSE
                R> DROP SBOX-COMPILER-S-OK EXIT
            THEN
        THEN
    AGAIN ;

: _SCC-NEXT  ( workspace -- status )
    >R
    0 R@ _SCW.TOKEN-A !
    0 R@ _SCW.TOKEN-U !
    R@ _SCC-SKIP-IGNORED DUP IF R> DROP EXIT THEN DROP

    R@ _SCW.SOURCE-A @ R@ _SCW.SOURCE-POS @ +
        R@ _SCW.TOKEN-A !
    BEGIN
        R@ _SCW.SOURCE-POS @ R@ _SCW.SOURCE-U @ U<
    WHILE
        R@ _SCW.SOURCE-A @ R@ _SCW.SOURCE-POS @ + C@
        DUP _SCC-WHITESPACE? IF
            DROP R> DROP SBOX-COMPILER-S-OK EXIT
        THEN
        [CHAR] \ = IF
            SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-BACKSLASH
            R@ _SCW.TOKEN-A @ R@ _SCW.SOURCE-A @ - R@ _SCW.TOKEN-U @ +
            1 R> _SCC-FAIL-AT EXIT
        THEN
        1 R@ _SCW.SOURCE-POS +!
        1 R@ _SCW.TOKEN-U +!
        R@ _SCW.TOKEN-U @ SBOX-COMPILER-TOKEN-MAX U> IF
            SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-TOKEN-LENGTH
            R> _SCC-FAIL EXIT
        THEN
    REPEAT
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-NEXT-REQUIRED  ( workspace -- status )
    DUP >R _SCC-NEXT
    DUP _SCC-S-EOF = IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-END R@ _SCC-FAIL
    THEN
    R> DROP ;

: _SCC-TOKEN=  ( literal-a literal-u workspace -- flag )
    >R
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _SCC-EXPECT  ( literal-a literal-u code workspace -- status )
    >R
    R@ _SCC-NEXT-REQUIRED DUP IF
        >R 2DROP DROP R> R> DROP EXIT
    THEN
    DROP
    -ROT R@ _SCC-TOKEN= IF
        DROP SBOX-COMPILER-S-OK
    ELSE
        SBOX-COMPILER-S-SOURCE SWAP R@ _SCC-FAIL
    THEN
    R> DROP ;

: _SCC-LOWER?  ( byte -- flag ) [CHAR] a [CHAR] z 1+ WITHIN ;
: _SCC-DIGIT?  ( byte -- flag ) [CHAR] 0 [CHAR] 9 1+ WITHIN ;

: _SCC-NAME-REST?  ( byte -- flag )
    DUP _SCC-LOWER? IF DROP -1 EXIT THEN
    DUP _SCC-DIGIT? IF DROP -1 EXIT THEN
    DUP [CHAR] . = IF DROP -1 EXIT THEN
    DUP [CHAR] _ = IF DROP -1 EXIT THEN
    DUP [CHAR] - = IF DROP -1 EXIT THEN
    DROP 0 ;

: _SCC-NAME?  ( address length -- flag )
    DUP 1 < OVER SBOX-COMPILER-TOKEN-MAX > OR IF
        2DROP 0 EXIT
    THEN
    OVER C@ _SCC-LOWER? 0= IF 2DROP 0 EXIT THEN
    1
    BEGIN DUP 2 PICK U< WHILE
        2 PICK OVER + C@ _SCC-NAME-REST? 0= IF
            DROP 2DROP 0 EXIT
        THEN
        1+
    REPEAT
    DROP 2DROP -1 ;

\ Unsigned division by ten for a full 64-bit cell.
: _SCC-U/10  ( u -- quotient remainder )
    DUP >R 0xCCCCCCCCCCCCCCCD UM* NIP 3 RSHIFT
    DUP 10 * R> SWAP - ;

: _SCC-UACCUMULATE  ( value digit maximum -- next flag )
    _SCC-U/10                         ( value digit quotient remainder )
    3 PICK 2 PICK U> IF
        2DROP 2DROP 0 0 EXIT
    THEN
    3 PICK 2 PICK = IF
        2 PICK OVER U> IF
            2DROP 2DROP 0 0 EXIT
        THEN
    THEN
    2DROP SWAP 10 * + -1 ;

: _SCC-NEXT-BYTE  ( address length value -- address' length' value )
    >R 1- SWAP 1+ SWAP R> ;

: _SCC-PARSE-U  ( address length maximum -- value flag )
    >R
    DUP 0= IF 2DROP R> DROP 0 0 EXIT THEN
    OVER C@ [CHAR] 0 = IF
        DUP 1 = IF
            2DROP R> DROP 0 -1
        ELSE
            2DROP R> DROP 0 0
        THEN
        EXIT
    THEN

    0
    BEGIN OVER WHILE
        2 PICK C@
        DUP _SCC-DIGIT? 0= IF
            DROP DROP 2DROP R> DROP 0 0 EXIT
        THEN
        [CHAR] 0 -
        R@ _SCC-UACCUMULATE 0= IF
            DROP 2DROP R> DROP 0 0 EXIT
        THEN
        _SCC-NEXT-BYTE
    REPEAT
    NIP NIP
    R> DROP -1 ;

: _SCC-PARSE-I64  ( address length -- bits flag )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    OVER C@ [CHAR] - = IF
        DUP 1 = IF 2DROP 0 0 EXIT THEN
        1- SWAP 1+ SWAP
        OVER C@ [CHAR] 0 = IF 2DROP 0 0 EXIT THEN
        0x8000000000000000 _SCC-PARSE-U
        DUP 0= IF EXIT THEN
        >R INVERT 1+ R>
    ELSE
        0x7FFFFFFFFFFFFFFF _SCC-PARSE-U
    THEN ;

: _SCC-CURRENT-U  ( maximum workspace -- value flag )
    >R
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    ROT _SCC-PARSE-U
    R> DROP ;

: _SCC-CURRENT-I64  ( workspace -- bits flag )
    DUP _SCW.TOKEN-A @ SWAP _SCW.TOKEN-U @ _SCC-PARSE-I64 ;

: _SCC-CURRENT-NAME?  ( workspace -- flag )
    DUP _SCW.TOKEN-A @ SWAP _SCW.TOKEN-U @ _SCC-NAME? ;

\ =====================================================================
\  Exact profile projection
\ =====================================================================

\ The profile gives the candidate's profile field.
: _SCC-LOAD-PROFILE-SPAN  ( workspace -- status )
    >R
    R@ _SCW.PROFILE @ SBOX-PROFILE-VALID? 0= IF
        R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN
    R@ _SCW.PROFILE @ SBOX-CANDIDATE-PROFILE-TAG R@ _SCW.PROFILE-TAG !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-LOAD-PROFILE  ( workspace -- status )
    DUP _SCC-LOAD-PROFILE-SPAN ?DUP IF
        SBOX-COMPILER-E-PROFILE ROT _SCC-FAIL-GLOBAL EXIT
    THEN
    DROP SBOX-COMPILER-S-OK ;

: _SCC-OPCODE-STATUS  ( opcode workspace -- status )
    >R
    R@ _SCW.PROFILE @ SBOX-PROFILE-OPCODE-ENABLED?
    DUP IF
        2DROP SBOX-COMPILER-S-PROFILE SBOX-COMPILER-E-PROFILE
        R> _SCC-FAIL-GLOBAL EXIT
    THEN
    DROP 0= IF
        SBOX-COMPILER-S-PROFILE SBOX-COMPILER-E-DISABLED R> _SCC-FAIL
    ELSE
        R> DROP SBOX-COMPILER-S-OK
    THEN ;

\ =====================================================================
\  Function namespace, records, and direct-call fixups
\ =====================================================================

: _SCC-FUNCTION-NAME@  ( index workspace -- address length )
    >R
    DUP R@ _SCC-FNAME
    SWAP R@ _SCC-FMETA _SCFM-NAME-U + @
    R> DROP ;

: _SCC-FUNCTION-NAME=  ( address length index workspace -- flag )
    >R
    R@ _SCC-FUNCTION-NAME@
    2SWAP COMPARE 0=
    R> DROP ;

: _SCC-FIND-FUNCTION  ( address length workspace -- index flag )
    >R
    0
    BEGIN DUP R@ _SCW.FUNCTION-N @ U< WHILE
        2 PICK 2 PICK 2 PICK R@ _SCC-FUNCTION-NAME= IF
            >R 2DROP R> -1 R> DROP EXIT
        THEN
        1+
    REPEAT
    DROP 2DROP R> DROP 0 0 ;

: _SCC-STORE-CURRENT-FUNCTION-NAME  ( index workspace -- )
    >R
    DUP R@ _SCC-FMETA
    R@ _SCW.TOKEN-U @ SWAP _SCFM-NAME-U + !
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    ROT R@ _SCC-FNAME SWAP MOVE
    R> DROP ;

: _SCC-ADD-FIXUP  ( instruction-index workspace -- status )
    >R
    R@ _SCW.FIXUP-N @ R@ _SCW.FIXUP-LIMIT @ U< 0= IF
        DROP SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.FIXUP-N @ R@ _SCC-FIXUP >R
    R@ _SCFX-INSTRUCTION + !
    R>
    R@ _SCW.TOKEN-A @ OVER _SCFX-NAME-A + !
    R@ _SCW.TOKEN-U @ OVER _SCFX-NAME-U + !
    DROP
    1 R@ _SCW.FIXUP-N +!
    R> DROP
    SBOX-COMPILER-S-OK ;

\ =====================================================================
\  Canonical instruction emission and typed lexical control stack
\ =====================================================================

: _SCC-CURRENT-LOCAL-INDEX  ( workspace -- index )
    DUP _SCW.INSTRUCTION-N @
    SWAP _SCW.CURRENT-START @ - ;

\ Maps an instruction to its form: from the form's first token through the
\ current token.
: _SCC-RECORD-SPAN  ( instruction-index workspace -- )
    >R
    R@ _SCW.FORM-A @ R@ _SCW.SOURCE-A @ - 32 LSHIFT
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @ + R@ _SCW.FORM-A @ - OR
    SWAP R@ _SCD-MAP-CELL !
    R> DROP ;

: _SCC-EMIT  ( opcode operand-a operand-b workspace -- status )
    >R
    2 PICK R@ _SCW.TMP-OPCODE !
    OVER R@ _SCW.TMP-A !
    DUP R@ _SCW.TMP-B !
    2DROP DROP

    R@ _SCW.INSTRUCTION-N @ R@ _SCW.INSTRUCTION-LIMIT @ U< 0= IF
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.TMP-OPCODE @ R@ _SCC-OPCODE-STATUS
    ?DUP IF R> DROP EXIT THEN

    R@ _SCW.INSTRUCTION-N @ R@ _SCC-INSTRUCTION
    DUP SBOX-CANDIDATE-INSTRUCTION-SIZE 0 FILL
    R@ _SCW.TMP-OPCODE @
        OVER SBOX-CANDIDATE-INSTRUCTION-OPCODE-OFFSET +
        SBOX-CANDIDATE-U16-LE!
    R@ _SCW.TMP-A @
        OVER SBOX-CANDIDATE-INSTRUCTION-A-OFFSET +
        SBOX-CANDIDATE-U32-LE!
    R@ _SCW.TMP-B @
        SWAP SBOX-CANDIDATE-INSTRUCTION-B-OFFSET +
        SBOX-CANDIDATE-U64-LE!
    R@ _SCW.INSTRUCTION-N @ R@ _SCC-RECORD-SPAN
    1 R@ _SCW.INSTRUCTION-N +!
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-PATCH-A  ( instruction-index target workspace -- )
    >R
    SWAP R@ _SCC-INSTRUCTION
    SBOX-CANDIDATE-INSTRUCTION-A-OFFSET +
    SBOX-CANDIDATE-U32-LE!
    R> DROP ;

1 CONSTANT _SCC-CONTROL-IF
2 CONSTANT _SCC-CONTROL-IF-ELSE
3 CONSTANT _SCC-CONTROL-BEGIN
4 CONSTANT _SCC-CONTROL-WHILE
5 CONSTANT _SCC-CONTROL-DO

: _SCC-CONTROL-TOP  ( workspace -- frame|0 )
    DUP _SCW.CONTROL-N @ DUP 0= IF 2DROP 0 EXIT THEN
    1- SWAP _SCC-CONTROL ;

: _SCC-PUSH-CONTROL  ( kind a b c workspace -- status )
    >R
    R@ _SCW.CONTROL-N @ R@ _SCW.CONTROL-LIMIT @ U< 0= IF
        2DROP 2DROP SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.CONTROL-N @ R@ _SCC-CONTROL >R
    R@ _SCC-CONTROL-SIZE 0 FILL
    R@ _SCCF-C + !
    R@ _SCCF-B + !
    R@ _SCCF-A + !
    R> _SCCF-KIND + !
    1 R@ _SCW.CONTROL-N +!
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-POP-CONTROL  ( workspace -- )
    -1 SWAP _SCW.CONTROL-N +! ;

: _SCC-TOP-KIND?  ( kind workspace -- flag )
    _SCC-CONTROL-TOP
    DUP 0= IF 2DROP 0 EXIT THEN
    _SCCF-KIND + @ = ;

\ =====================================================================
\  Closed source mnemonic table
\ =====================================================================

: _SCC-MATCH?  ( a1 u1 a2 u2 -- flag ) COMPARE 0= ;

: _SCC-SIMPLE-OPCODE  ( token-a token-u -- opcode flag )
    2DUP S" NOP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-NOP -1 EXIT
    THEN
    2DUP S" DROP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-DROP -1 EXIT
    THEN
    2DUP S" DUP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-DUP -1 EXIT
    THEN
    2DUP S" SWAP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-SWAP -1 EXIT
    THEN
    2DUP S" OVER" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-OVER -1 EXIT
    THEN
    2DUP S" ROT" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-ROT -1 EXIT
    THEN
    2DUP S" NIP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-NIP -1 EXIT
    THEN
    2DUP S" TUCK" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-TUCK -1 EXIT
    THEN
    2DUP S" 2DROP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-2DROP -1 EXIT
    THEN
    2DUP S" 2DUP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-2DUP -1 EXIT
    THEN
    2DUP S" 2SWAP" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-2SWAP -1 EXIT
    THEN
    2DUP S" 2OVER" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-2OVER -1 EXIT
    THEN

    2DUP S" I64.ADD" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-ADD -1 EXIT
    THEN
    2DUP S" I64.SUB" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-SUB -1 EXIT
    THEN
    2DUP S" I64.MUL" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-MUL -1 EXIT
    THEN
    2DUP S" I64.DIV.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-DIV-S -1 EXIT
    THEN
    2DUP S" I64.REM.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-REM-S -1 EXIT
    THEN
    2DUP S" I64.DIVMOD.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-DIVMOD-S -1 EXIT
    THEN
    2DUP S" I64.NEG" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-NEG -1 EXIT
    THEN
    2DUP S" I64.ABS" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-ABS -1 EXIT
    THEN
    2DUP S" I64.MIN.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-MIN-S -1 EXIT
    THEN
    2DUP S" I64.MAX.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-MAX-S -1 EXIT
    THEN
    2DUP S" I64.INC" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-INC -1 EXIT
    THEN
    2DUP S" I64.DEC" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-DEC -1 EXIT
    THEN
    2DUP S" I64.EQ" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-EQ -1 EXIT
    THEN
    2DUP S" I64.NE" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-NE -1 EXIT
    THEN
    2DUP S" I64.LT.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-LT-S -1 EXIT
    THEN
    2DUP S" I64.LE.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-LE-S -1 EXIT
    THEN
    2DUP S" I64.GT.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-GT-S -1 EXIT
    THEN
    2DUP S" I64.GE.S" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-GE-S -1 EXIT
    THEN
    2DUP S" I64.LT.U" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-LT-U -1 EXIT
    THEN
    2DUP S" I64.LE.U" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-LE-U -1 EXIT
    THEN
    2DUP S" I64.GT.U" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-GT-U -1 EXIT
    THEN
    2DUP S" I64.GE.U" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-GE-U -1 EXIT
    THEN
    2DUP S" I64.ZERO?" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-ZERO? -1 EXIT
    THEN
    2DUP S" I64.NEGATIVE?" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-NEGATIVE? -1 EXIT
    THEN
    2DUP S" I64.POSITIVE?" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-POSITIVE? -1 EXIT
    THEN
    2DUP S" I64.AND" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-AND -1 EXIT
    THEN
    2DUP S" I64.OR" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-OR -1 EXIT
    THEN
    2DUP S" I64.XOR" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-XOR -1 EXIT
    THEN
    2DUP S" I64.NOT" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-NOT -1 EXIT
    THEN
    2DUP S" I64.SHL" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-SHL -1 EXIT
    THEN
    2DUP S" I64.SHR.U" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-I64-SHR-U -1 EXIT
    THEN

    2DUP S" MEM.SIZE" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-SIZE -1 EXIT
    THEN
    2DUP S" MEM.LOAD8.U" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-LOAD8-U -1 EXIT
    THEN
    2DUP S" MEM.STORE8" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-STORE8 -1 EXIT
    THEN
    2DUP S" MEM.LOAD64" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-LOAD64 -1 EXIT
    THEN
    2DUP S" MEM.STORE64" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-STORE64 -1 EXIT
    THEN
    2DUP S" MEM.MOVE" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-MOVE -1 EXIT
    THEN
    2DUP S" MEM.FILL" _SCC-MATCH? IF
        2DROP SBOX-MACHINE-OP-MEM-FILL -1 EXIT
    THEN

    2DUP S" V.TYPE" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-TYPE -1 EXIT
    THEN
    2DUP S" V.BOOL.GET" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-BOOL-GET -1 EXIT
    THEN
    2DUP S" V.I64.GET" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-I64-GET -1 EXIT
    THEN
    2DUP S" V.LEN" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-LEN -1 EXIT
    THEN
    2DUP S" V.LIST.GET" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-LIST-GET -1 EXIT
    THEN
    2DUP S" V.MAP.KEY" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-MAP-KEY -1 EXIT
    THEN
    2DUP S" V.MAP.VALUE" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-MAP-VALUE -1 EXIT
    THEN
    2DUP S" V.MAP.FIND" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-MAP-FIND -1 EXIT
    THEN
    2DUP S" V.BLOB.COPY" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-BLOB-COPY -1 EXIT
    THEN
    2DUP S" V.NEW.NULL" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-NULL -1 EXIT
    THEN
    2DUP S" V.NEW.BOOL" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-BOOL -1 EXIT
    THEN
    2DUP S" V.NEW.I64" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-I64 -1 EXIT
    THEN
    2DUP S" V.NEW.BYTES" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-BYTES -1 EXIT
    THEN
    2DUP S" V.NEW.UTF8" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-UTF8 -1 EXIT
    THEN
    2DUP S" V.NEW.LIST" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-LIST -1 EXIT
    THEN
    2DUP S" V.NEW.MAP" _SCC-MATCH? IF
        2DROP SBOX-ABI-OP-V-NEW-MAP -1 EXIT
    THEN

    2DROP 0 0 ;

\ =====================================================================
\  Structured lowering
\ =====================================================================

: _SCC-EMIT0  ( opcode workspace -- status )
    >R 0 0 R> _SCC-EMIT ;

: _SCC-EMIT-A  ( opcode operand-a workspace -- status )
    >R 0 R> _SCC-EMIT ;

: _SCC-EMIT-B  ( opcode operand-b workspace -- status )
    >R 0 SWAP R> _SCC-EMIT ;

: _SCC-OPEN-IF  ( workspace -- status )
    >R
    R@ _SCW.INSTRUCTION-N @ R@ _SCW.TMP-X !
    SBOX-MACHINE-OP-BR-ZERO 0 R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    _SCC-CONTROL-IF R@ _SCW.TMP-X @ 0 0 R@
        _SCC-PUSH-CONTROL
    R> DROP ;

: _SCC-OPEN-BEGIN  ( workspace -- status )
    >R
    _SCC-CONTROL-BEGIN R@ _SCC-CURRENT-LOCAL-INDEX 0 0 R@
        _SCC-PUSH-CONTROL
    R> DROP ;

: _SCC-OPEN-DO  ( workspace -- status )
    >R
    R@ _SCW.INSTRUCTION-N @ R@ _SCW.TMP-X !
    SBOX-MACHINE-OP-LOOP-ENTER 0 R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    _SCC-CONTROL-DO
        R@ _SCW.TMP-X @
        R@ _SCC-CURRENT-LOCAL-INDEX
        0 R@ _SCC-PUSH-CONTROL
    ?DUP IF R> DROP EXIT THEN
    1 R@ _SCW.DO-N +!
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-ELSE  ( workspace -- status )
    >R
    _SCC-CONTROL-IF R@ _SCC-TOP-KIND? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-CONTROL-TOP _SCCF-A + @ R@ _SCW.SAVED-A !
    R@ _SCW.REACHABLE @ R@ _SCW.SAVED-B !

    R@ _SCW.REACHABLE @ IF
        R@ _SCW.INSTRUCTION-N @ R@ _SCW.TMP-X !
        SBOX-MACHINE-OP-BR 0 R@ _SCC-EMIT-A
        ?DUP IF R> DROP EXIT THEN
    ELSE
        -1 R@ _SCW.TMP-X !
    THEN

    R@ _SCW.SAVED-A @ R@ _SCC-CURRENT-LOCAL-INDEX R@ _SCC-PATCH-A
    R@ _SCC-CONTROL-TOP
    _SCC-CONTROL-IF-ELSE OVER _SCCF-KIND + !
    R@ _SCW.TMP-X @ OVER _SCCF-B + !
    R@ _SCW.SAVED-B @ SWAP _SCCF-C + !
    -1 R@ _SCW.REACHABLE !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-THEN  ( workspace -- status )
    >R
    R@ _SCC-CONTROL-TOP DUP 0= IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    DUP _SCCF-KIND + @ DUP _SCC-CONTROL-IF = IF
        DROP
        _SCCF-A + @
        R@ _SCC-CURRENT-LOCAL-INDEX R@ _SCC-PATCH-A
        -1 R@ _SCW.REACHABLE !
        R@ _SCC-POP-CONTROL
        R> DROP SBOX-COMPILER-S-OK EXIT
    THEN
    _SCC-CONTROL-IF-ELSE <> IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN

    DUP _SCCF-B + @ DUP 0< IF
        DROP
    ELSE
        R@ _SCC-CURRENT-LOCAL-INDEX R@ _SCC-PATCH-A
    THEN
    _SCCF-C + @
    R@ _SCW.REACHABLE @ OR
    R@ _SCW.REACHABLE !
    R@ _SCC-POP-CONTROL
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-WHILE  ( workspace -- status )
    >R
    _SCC-CONTROL-BEGIN R@ _SCC-TOP-KIND? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNREACHABLE R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.INSTRUCTION-N @ R@ _SCW.TMP-X !
    SBOX-MACHINE-OP-BR-ZERO 0 R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    R@ _SCC-CONTROL-TOP
    _SCC-CONTROL-WHILE OVER _SCCF-KIND + !
    R@ _SCW.TMP-X @ SWAP _SCCF-B + !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-UNTIL  ( workspace -- status )
    >R
    _SCC-CONTROL-BEGIN R@ _SCC-TOP-KIND? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNREACHABLE R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-CONTROL-TOP _SCCF-A + @
    SBOX-MACHINE-OP-BR-ZERO SWAP R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    -1 R@ _SCW.REACHABLE !
    R@ _SCC-POP-CONTROL
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-AGAIN  ( workspace -- status )
    >R
    _SCC-CONTROL-BEGIN R@ _SCC-TOP-KIND? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNREACHABLE R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-CONTROL-TOP _SCCF-A + @
    SBOX-MACHINE-OP-BR SWAP R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    0 R@ _SCW.REACHABLE !
    R@ _SCC-POP-CONTROL
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-REPEAT  ( workspace -- status )
    >R
    _SCC-CONTROL-WHILE R@ _SCC-TOP-KIND? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNREACHABLE R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-CONTROL-TOP DUP _SCCF-A + @ R@ _SCW.SAVED-A !
    _SCCF-B + @ R@ _SCW.SAVED-B !
    SBOX-MACHINE-OP-BR R@ _SCW.SAVED-A @ R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    R@ _SCW.SAVED-B @ R@ _SCC-CURRENT-LOCAL-INDEX R@ _SCC-PATCH-A
    -1 R@ _SCW.REACHABLE !
    R@ _SCC-POP-CONTROL
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-CLOSE-DO  ( opcode workspace -- status )
    >R
    _SCC-CONTROL-DO R@ _SCC-TOP-KIND? 0= IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNMATCHED R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNREACHABLE R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-CONTROL-TOP DUP _SCCF-A + @ R@ _SCW.SAVED-A !
    _SCCF-B + @ R@ _SCW.SAVED-B !
    R@ _SCW.SAVED-B @ R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    R@ _SCW.SAVED-A @ R@ _SCC-CURRENT-LOCAL-INDEX R@ _SCC-PATCH-A
    -1 R@ _SCW.DO-N +!
    -1 R@ _SCW.REACHABLE !
    R@ _SCC-POP-CONTROL
    R> DROP SBOX-COMPILER-S-OK ;

\ =====================================================================
\  Simple forms and current-token dispatcher
\ =====================================================================

: _SCC-READ-U  ( maximum workspace -- value status )
    >R
    R@ _SCC-NEXT-REQUIRED DUP IF
        >R DROP R> R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ _SCC-CURRENT-U 0= IF
        DROP 0 SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-NUMBER R> _SCC-FAIL EXIT
    THEN
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-COMPILE-CALL  ( workspace -- status )
    >R
    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-NAME R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.FIXUP-N @ R@ _SCW.FIXUP-LIMIT @ U< 0= IF
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.INSTRUCTION-N @ R@ _SCW.TMP-X !
    SBOX-MACHINE-OP-CALL 0 R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    R@ _SCW.TMP-X @ R@ _SCC-ADD-FIXUP
    R> DROP ;

: _SCC-COMPILE-LOCAL  ( opcode workspace -- status )
    >R
    0xFFFFFFFF R@ _SCC-READ-U
    DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    DUP R@ _SCW.CURRENT-LOCALS @ U< 0= IF
        2DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-LOCAL-INDEX R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-EMIT-A
    R> DROP ;

: _SCC-COMPILE-ABORT  ( workspace -- status )
    >R
    65535 R@ _SCC-READ-U
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP
    SBOX-MACHINE-OP-ABORT SWAP R@ _SCC-EMIT-A
    ?DUP IF R> DROP EXIT THEN
    0 R@ _SCW.REACHABLE !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-COMPILE-RETURN  ( workspace -- status )
    >R
    R@ _SCW.DO-N @ IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-RETURN-IN-LOOP R> _SCC-FAIL EXIT
    THEN
    SBOX-MACHINE-OP-RETURN R@ _SCC-EMIT0
    ?DUP IF R> DROP EXIT THEN
    0 R@ _SCW.REACHABLE !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-COMPILE-R  ( workspace -- status )
    DUP _SCW.DO-N @ 0= IF
        >R SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-LOOP-INDEX R> _SCC-FAIL EXIT
    THEN
    SBOX-MACHINE-OP-LOOP-INDEX SWAP _SCC-EMIT0 ;

: _SCC-COMPILE-CURRENT  ( workspace -- status )
    >R
    S" ELSE" R@ _SCC-TOKEN= IF
        R@ _SCC-CLOSE-ELSE R> DROP EXIT
    THEN
    S" THEN" R@ _SCC-TOKEN= IF
        R@ _SCC-CLOSE-THEN R> DROP EXIT
    THEN
    S" WHILE" R@ _SCC-TOKEN= IF
        R@ _SCC-CLOSE-WHILE R> DROP EXIT
    THEN
    S" UNTIL" R@ _SCC-TOKEN= IF
        R@ _SCC-CLOSE-UNTIL R> DROP EXIT
    THEN
    S" AGAIN" R@ _SCC-TOKEN= IF
        R@ _SCC-CLOSE-AGAIN R> DROP EXIT
    THEN
    S" REPEAT" R@ _SCC-TOKEN= IF
        R@ _SCC-CLOSE-REPEAT R> DROP EXIT
    THEN
    S" LOOP" R@ _SCC-TOKEN= IF
        SBOX-MACHINE-OP-LOOP-NEXT R@ _SCC-CLOSE-DO
        R> DROP EXIT
    THEN
    S" +LOOP" R@ _SCC-TOKEN= IF
        SBOX-MACHINE-OP-LOOP-NEXT-BY R@ _SCC-CLOSE-DO
        R> DROP EXIT
    THEN

    R@ _SCW.REACHABLE @ 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNREACHABLE R> _SCC-FAIL EXIT
    THEN

    S" IF" R@ _SCC-TOKEN= IF
        R@ _SCC-OPEN-IF R> DROP EXIT
    THEN
    S" BEGIN" R@ _SCC-TOKEN= IF
        R@ _SCC-OPEN-BEGIN R> DROP EXIT
    THEN
    S" DO" R@ _SCC-TOKEN= IF
        R@ _SCC-OPEN-DO R> DROP EXIT
    THEN
    S" CALL" R@ _SCC-TOKEN= IF
        R@ _SCC-COMPILE-CALL R> DROP EXIT
    THEN
    S" RETURN" R@ _SCC-TOKEN= IF
        R@ _SCC-COMPILE-RETURN R> DROP EXIT
    THEN
    S" ABORT" R@ _SCC-TOKEN= IF
        R@ _SCC-COMPILE-ABORT R> DROP EXIT
    THEN
    S" LOCAL.GET" R@ _SCC-TOKEN= IF
        SBOX-MACHINE-OP-LOCAL-GET R@ _SCC-COMPILE-LOCAL
        R> DROP EXIT
    THEN
    S" LOCAL.SET" R@ _SCC-TOKEN= IF
        SBOX-MACHINE-OP-LOCAL-SET R@ _SCC-COMPILE-LOCAL
        R> DROP EXIT
    THEN
    S" LOCAL.TEE" R@ _SCC-TOKEN= IF
        SBOX-MACHINE-OP-LOCAL-TEE R@ _SCC-COMPILE-LOCAL
        R> DROP EXIT
    THEN
    S" R" R@ _SCC-TOKEN= IF
        R@ _SCC-COMPILE-R R> DROP EXIT
    THEN

    R@ _SCC-CURRENT-I64 IF
        SBOX-MACHINE-OP-LIT-I64 SWAP R@ _SCC-EMIT-B
        R> DROP EXIT
    THEN
    DROP

    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @ _SCC-SIMPLE-OPCODE
    IF
        R@ _SCC-EMIT0 R> DROP EXIT
    THEN
    DROP
    \ A token that starts like a number is a malformed number.
    R@ _SCW.TOKEN-A @ C@ DUP _SCC-DIGIT? SWAP [CHAR] - = OR
    IF SBOX-COMPILER-E-NUMBER ELSE SBOX-COMPILER-E-UNKNOWN THEN
    SBOX-COMPILER-S-SOURCE SWAP R> _SCC-FAIL ;

\ =====================================================================
\  Top-level declarations and namespace resolution
\ =====================================================================

: _SCC-STORE-CURRENT-FMETA  ( value field-offset workspace -- )
    >R
    R@ _SCW.CURRENT-FUNCTION @ R@ _SCC-FMETA
    + !
    R> DROP ;

\ The format holds parameter, result and local counts in 16 bits.  How
\ many cells a run may use is the host's policy.
65535 CONSTANT _SCC-COUNT-MAX

: _SCC-FUNCTION-CAPACITY?  ( workspace -- flag )
    DUP _SCW.FUNCTION-N @ SWAP _SCW.FUNCTION-LIMIT @ U< ;

: _SCC-PARSE-FUNCTION  ( workspace -- status )
    >R
    R@ _SCC-FUNCTION-CAPACITY? 0= IF
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT
    THEN

    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-NAME R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @ R@ _SCC-FIND-FUNCTION
    IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-DUPLICATE R> _SCC-FAIL EXIT
    THEN
    DROP

    R@ _SCW.FUNCTION-N @ DUP R@ _SCW.CURRENT-FUNCTION !
    R@ _SCC-STORE-CURRENT-FUNCTION-NAME

    S" PARAMS" SBOX-COMPILER-E-EXPECTED-PARAMS R@ _SCC-EXPECT ?DUP IF R> DROP EXIT THEN
    _SCC-COUNT-MAX R@ _SCC-READ-U
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP _SCFM-PARAMS R@ _SCC-STORE-CURRENT-FMETA

    S" RESULTS" SBOX-COMPILER-E-EXPECTED-RESULTS R@ _SCC-EXPECT ?DUP IF R> DROP EXIT THEN
    _SCC-COUNT-MAX R@ _SCC-READ-U
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP _SCFM-RESULTS R@ _SCC-STORE-CURRENT-FMETA

    S" LOCALS" SBOX-COMPILER-E-EXPECTED-LOCALS R@ _SCC-EXPECT ?DUP IF R> DROP EXIT THEN
    _SCC-COUNT-MAX R@ _SCC-READ-U
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP
    DUP R@ _SCW.CURRENT-LOCALS !
    _SCFM-LOCALS R@ _SCC-STORE-CURRENT-FMETA

    R@ _SCW.INSTRUCTION-N @ DUP R@ _SCW.CURRENT-START !
    _SCFM-INSTRUCTION-START R@ _SCC-STORE-CURRENT-FMETA
    0 R@ _SCW.CONTROL-N !
    0 R@ _SCW.DO-N !
    -1 R@ _SCW.REACHABLE !

    BEGIN
        R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
        S" END" R@ _SCC-TOKEN= IF
            R@ _SCW.CONTROL-N @ R@ _SCW.DO-N @ OR IF
                SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-OPEN-CONTROL
                R> _SCC-FAIL EXIT
            THEN
            R@ _SCW.REACHABLE @ IF
                SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-FALLTHROUGH
                R> _SCC-FAIL EXIT
            THEN
            R@ _SCW.INSTRUCTION-N @ R@ _SCW.CURRENT-START @ -
                _SCFM-INSTRUCTION-N R@ _SCC-STORE-CURRENT-FMETA
            1 R@ _SCW.FUNCTION-N +!
            R> DROP SBOX-COMPILER-S-OK EXIT
        THEN
        R@ _SCW.TOKEN-A @ R@ _SCW.FORM-A !
        R@ _SCC-COMPILE-CURRENT ?DUP IF R> DROP EXIT THEN
    AGAIN ;

: _SCC-ENTRY-NAME@  ( index workspace -- address length )
    >R
    R@ _SCC-ENTRY-NAMES
    OVER R@ _SCC-EMETA _SCEM-NAME-OFF + @ +
    SWAP R@ _SCC-EMETA _SCEM-NAME-U + @
    R> DROP ;

: _SCC-ENTRY-CAPACITY?  ( workspace -- flag )
    DUP _SCW.ENTRY-N @ SWAP _SCW.ENTRY-LIMIT @ U< ;

: _SCC-CURRENT-ENTRY-INCREASING?  ( workspace -- flag )
    >R
    R@ _SCW.ENTRY-N @ DUP 0= IF
        DROP R> DROP -1 EXIT
    THEN
    1- R@ _SCC-ENTRY-NAME@
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    COMPARE 0<
    R> DROP ;

\ Does the target profile enable the signature in TMP-X?
: _SCC-SIGNATURE-ENABLED?  ( workspace -- flag )
    DUP _SCW.TMP-X @ SWAP _SCW.PROFILE @
    SBOX-PROFILE-SIGNATURE-ENABLED? 0= AND ;

: _SCC-PARSE-ENTRY  ( workspace -- status )
    >R
    R@ _SCC-ENTRY-CAPACITY? 0= IF
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT
    THEN
    0 R@ _SCW.TMP-X !
    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    S" SIGNATURE" R@ _SCC-TOKEN= IF
        SBOX-ABI-SIGNATURE-VALUE-TO-VALUE R@ _SCC-READ-U
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        DUP 0= IF
            DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-SIGNATURE
            R> _SCC-FAIL EXIT
        THEN
        R@ _SCW.TMP-X !
    THEN
    \ The profile names the signatures an entry may have.  An omitted
    \ signature is zero, which only scalar qualification enables; the span
    \ is the number, or the entry name in its place.
    R@ _SCC-SIGNATURE-ENABLED? 0= IF
        SBOX-COMPILER-S-PROFILE SBOX-COMPILER-E-SIGNATURE R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.TMP-X @ IF
        R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-NAME R> _SCC-FAIL EXIT
    THEN
    R@ _SCC-CURRENT-ENTRY-INCREASING? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-ENTRY-ORDER R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.TOKEN-U @
    R@ _SCW.NAME-BYTES-LIMIT @ R@ _SCW.NAME-U @ -
    U> IF SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT R> _SCC-FAIL EXIT THEN

    R@ _SCW.TMP-X @
    R@ _SCW.ENTRY-N @ R@ _SCC-EMETA
    DUP >R _SCEM-SIGNATURE + !
    R>
    R@ _SCW.NAME-U @ OVER _SCEM-NAME-OFF + !
    R@ _SCW.TOKEN-U @ OVER _SCEM-NAME-U + !
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    R@ _SCC-ENTRY-NAMES R@ _SCW.NAME-U @ +
    SWAP MOVE
    DROP

    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-NAME R> _SCC-FAIL EXIT
    THEN
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @ R@ _SCC-FIND-FUNCTION
    0= IF
        DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-ENTRY-FUNCTION
        R> _SCC-FAIL EXIT
    THEN
    DUP R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-FUNCTION + !
    DROP

    \ Signature zero is the scalar qualification form, taking the function's
    \ own cells.  A production entry is spelled `ENTRY SIGNATURE 1 ...`; its
    \ function shape is checked here and again by the independent verifier.
    R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-SIGNATURE + @
    ?DUP IF
        SBOX-ABI-SIGNATURE-VALUE-TO-VALUE <> IF
            SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-SIGNATURE R> _SCC-FAIL EXIT
        THEN
        R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-FUNCTION + @
        R@ _SCC-FMETA
        DUP _SCFM-PARAMS + @ 1 <>
        SWAP _SCFM-RESULTS + @ 1 <> OR IF
            SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-SIGNATURE R> _SCC-FAIL EXIT
        THEN
    THEN

    \ TOKEN-U now names the function, so recover the entry length from metadata.
    R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-NAME-U + @
        R@ _SCW.NAME-U +!
    1 R@ _SCW.ENTRY-N +!
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-RESOLVE-FIXUPS  ( workspace -- status )
    >R
    0
    BEGIN DUP R@ _SCW.FIXUP-N @ U< WHILE
        DUP R@ _SCC-FIXUP
        DUP _SCFX-INSTRUCTION + @ R@ _SCW.TMP-A !
        DUP _SCFX-NAME-A + @
        SWAP _SCFX-NAME-U + @
        2DUP R@ _SCC-FIND-FUNCTION
        0= IF
            \ ( index name-a name-u index' )
            DROP SWAP R@ _SCW.SOURCE-A @ - SWAP >R >R
            DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-UNDEFINED-CALL
            R> R> R> _SCC-FAIL-AT EXIT
        THEN
        NIP NIP
        R@ _SCW.TMP-A @ SWAP R@ _SCC-PATCH-A
        1+
    REPEAT
    DROP R> DROP SBOX-COMPILER-S-OK ;

: _SCC-TYPED-OPCODE?  ( opcode -- flag )
    DUP SBOX-ABI-OP-V-TYPE >=
    OVER SBOX-ABI-OP-V-BLOB-COPY <= AND
    SWAP
    DUP SBOX-ABI-OP-V-NEW-NULL >=
    SWAP SBOX-ABI-OP-V-NEW-MAP <= AND
    OR ;

: _SCC-VALIDATE-ENTRY-SURFACE  ( workspace -- status )
    >R
    R@ _SCW.ENTRY-N @ 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-EXPECTED-ENTRY
        R> _SCC-FAIL-GLOBAL EXIT
    THEN

    \ Signature zero exists only for scalar qualification.  Production
    \ candidates currently expose one physical ABI across all entries; this
    \ avoids giving a scalar entry an indirect route to typed instructions.
    0 R@ _SCC-EMETA _SCEM-SIGNATURE + @
        R@ _SCW.TMP-X !
    1
    BEGIN DUP R@ _SCW.ENTRY-N @ U< WHILE
        DUP R@ _SCC-EMETA _SCEM-SIGNATURE + @
        R@ _SCW.TMP-X @ <> IF
            DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-SIGNATURE-MIX
            R> _SCC-FAIL-GLOBAL EXIT
        THEN
        1+
    REPEAT
    DROP

    R@ _SCW.TMP-X @ 0= IF
        0
        BEGIN DUP R@ _SCW.INSTRUCTION-N @ U< WHILE
            DUP R@ _SCC-INSTRUCTION
            SBOX-CANDIDATE-INSTRUCTION-OPCODE-OFFSET +
            SBOX-CANDIDATE-U16-LE@
            _SCC-TYPED-OPCODE? IF
                DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-SCALAR-TYPED
                R> _SCC-FAIL-GLOBAL EXIT
            THEN
            1+
        REPEAT
        DROP
    THEN

    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-PARSE-SOURCE  ( workspace -- status )
    >R
    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    S" FUNCTION" R@ _SCC-TOKEN= 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-EXPECTED-FUNCTION
        R> _SCC-FAIL EXIT
    THEN

    BEGIN
        R@ _SCC-PARSE-FUNCTION ?DUP IF R> DROP EXIT THEN
        R@ _SCC-NEXT
        DUP _SCC-S-EOF = IF
            DROP SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-EXPECTED-ENTRY
            R> _SCC-FAIL EXIT
        THEN
        ?DUP IF R> DROP EXIT THEN
        S" FUNCTION" R@ _SCC-TOKEN=
    WHILE
    REPEAT

    S" ENTRY" R@ _SCC-TOKEN= 0= IF
        SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-EXPECTED-ENTRY
        R> _SCC-FAIL EXIT
    THEN
    BEGIN
        R@ _SCC-PARSE-ENTRY ?DUP IF R> DROP EXIT THEN
        R@ _SCC-NEXT
        DUP _SCC-S-EOF = IF
            DROP
            R@ _SCC-RESOLVE-FIXUPS ?DUP IF
                R> DROP EXIT
            THEN
            R@ _SCC-VALIDATE-ENTRY-SURFACE
            R> DROP EXIT
        THEN
        ?DUP IF R> DROP EXIT THEN
        S" ENTRY" R@ _SCC-TOKEN= 0= IF
            SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-EXPECTED-ENTRY
            R> _SCC-FAIL EXIT
        THEN
    AGAIN ;

\ =====================================================================
\  Canonical candidate staging and final publication
\ =====================================================================

: _SCC-WRITE-FUNCTIONS  ( workspace -- )
    >R
    0
    BEGIN DUP R@ _SCW.FUNCTION-N @ U< WHILE
        DUP R@ _SCC-FMETA R@ _SCW.TMP-A !
        R@ _SCC-STAGE
        R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-FUNCTIONS@ +
        OVER SBOX-CANDIDATE-FUNCTION-SIZE * +
        R@ _SCW.TMP-B !

        R@ _SCW.TMP-A @ _SCFM-INSTRUCTION-N + @
        R@ _SCW.TMP-B @
            SBOX-CANDIDATE-FUNCTION-INSTRUCTION-N-OFFSET +
            SBOX-CANDIDATE-U32-LE!
        R@ _SCW.TMP-A @ _SCFM-PARAMS + @
        R@ _SCW.TMP-B @ SBOX-CANDIDATE-FUNCTION-PARAMS-OFFSET +
            SBOX-CANDIDATE-U16-LE!
        R@ _SCW.TMP-A @ _SCFM-RESULTS + @
        R@ _SCW.TMP-B @ SBOX-CANDIDATE-FUNCTION-RESULTS-OFFSET +
            SBOX-CANDIDATE-U16-LE!
        R@ _SCW.TMP-A @ _SCFM-LOCALS + @
        R@ _SCW.TMP-B @ SBOX-CANDIDATE-FUNCTION-LOCALS-OFFSET +
            SBOX-CANDIDATE-U16-LE!
        1+
    REPEAT
    DROP R> DROP ;

: _SCC-WRITE-ENTRIES  ( workspace -- )
    >R
    0
    BEGIN DUP R@ _SCW.ENTRY-N @ U< WHILE
        DUP R@ _SCC-EMETA R@ _SCW.TMP-A !
        R@ _SCC-STAGE
        R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-ENTRIES@ +
        OVER SBOX-CANDIDATE-ENTRY-SIZE * +
        R@ _SCW.TMP-B !

        R@ _SCW.TMP-A @ _SCEM-NAME-OFF + @
        R@ _SCW.TMP-B @ SBOX-CANDIDATE-ENTRY-NAME-OFFSET +
            SBOX-CANDIDATE-U32-LE!
        R@ _SCW.TMP-A @ _SCEM-NAME-U + @
        R@ _SCW.TMP-B @ SBOX-CANDIDATE-ENTRY-NAME-U-OFFSET +
            SBOX-CANDIDATE-U16-LE!
        R@ _SCW.TMP-A @ _SCEM-FUNCTION + @
        R@ _SCW.TMP-B @
            SBOX-CANDIDATE-ENTRY-FUNCTION-INDEX-OFFSET +
            SBOX-CANDIDATE-U32-LE!
        R@ _SCW.TMP-A @ _SCEM-SIGNATURE + @
        R@ _SCW.TMP-B @
            SBOX-CANDIDATE-ENTRY-SIGNATURE-ID-OFFSET +
            SBOX-CANDIDATE-U32-LE!
        1+
    REPEAT
    DROP R> DROP ;

: _SCC-WRITE-BYTES  ( workspace -- )
    >R
    R@ _SCC-ENTRY-NAMES
    R@ _SCC-STAGE R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-NAMES@ +
    R@ _SCW.NAME-U @ MOVE

    0 R@ _SCW.INSTRUCTION-N @
        SBOX-CANDIDATE-INSTRUCTION-SIZE
        SBOX-BYTE-LENGTH* DUP IF
        2DROP DROP R> DROP EXIT
    THEN
    DROP NIP
    0 R@ _SCC-INSTRUCTION
    R@ _SCC-STAGE
        R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-INSTRUCTIONS@ +
    ROT MOVE
    R> DROP ;

: _SCC-CANDIDATE-STATUS>COMPILER  ( candidate-status workspace -- status )
    >R
    SBOX-CANDIDATE-S-CAPACITY = IF
        SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT
    ELSE
        SBOX-COMPILER-S-INTERNAL SBOX-COMPILER-E-INTERNAL
    THEN
    R> _SCC-FAIL-GLOBAL ;

: _SCC-BUILD-CANDIDATE  ( workspace -- written status )
    >R
    R@ _SCW.FUNCTION-N @
    0
    R@ _SCW.ENTRY-N @
    R@ _SCW.NAME-U @
    0
    R@ _SCW.INSTRUCTION-N @
    R@ _SCC-LAYOUT
    SBOX-CANDIDATE-MEASURE
    DUP IF
        R@ _SCC-CANDIDATE-STATUS>COMPILER
        R> DROP 0 SWAP EXIT
    THEN
    DROP

    R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-TOTAL@
        DUP R@ _SCW.TMP-X !
    DUP R@ _SCW.STAGE-LIMIT @ U> IF
        DROP 0 SBOX-COMPILER-S-INTERNAL SBOX-COMPILER-E-INTERNAL
        R> _SCC-FAIL-GLOBAL EXIT
    THEN
    R@ _SCW.CANDIDATE-CAP @ U> IF
        0 SBOX-COMPILER-S-CAPACITY SBOX-COMPILER-E-LIMIT
        R> _SCC-FAIL-GLOBAL EXIT
    THEN

    R@ _SCW.PROFILE-TAG @
    R@ _SCW.MEMORY-U @
    R@ _SCC-LAYOUT
    R@ _SCC-STAGE
    SBOX-CANDIDATE-HEADER!
    DUP IF
        R@ _SCC-CANDIDATE-STATUS>COMPILER
        R> DROP 0 SWAP EXIT
    THEN
    DROP

    R@ _SCC-WRITE-FUNCTIONS
    R@ _SCC-WRITE-ENTRIES
    R@ _SCC-WRITE-BYTES

    R@ _SCC-STAGE R@ _SCW.TMP-X @ R@ _SCC-LAYOUT
        SBOX-CANDIDATE-INSPECT
    DUP IF
        DROP 0 SBOX-COMPILER-S-INTERNAL SBOX-COMPILER-E-INTERNAL
        R> _SCC-FAIL-GLOBAL EXIT
    THEN
    DROP

    R@ _SCC-STAGE
    R@ _SCW.CANDIDATE @
    R@ _SCW.TMP-X @ MOVE
    R@ _SCW.TMP-X @ SBOX-COMPILER-S-OK
    R> DROP ;

\ =====================================================================
\  Public compilation boundary
\ =====================================================================

: _SCC-RUN  ( workspace -- written status )
    >R
    R@ _SCC-LOAD-PROFILE DUP IF
        R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ _SCC-BAD-BYTE DUP 0< 0= IF
        >R 0 SBOX-COMPILER-S-SOURCE SBOX-COMPILER-E-BYTE R> 1 R> _SCC-FAIL-AT
        EXIT
    THEN
    DROP
    R@ _SCC-PARSE-SOURCE DUP IF
        R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ _SCC-BUILD-CANDIDATE
    R> DROP ;

\ SBOX-COMPILE stages every byte in workspace and copies exactly WRITTEN bytes
\ to CANDIDATE only on success.  All admitted spans must remain mapped and
\ quiescent for the synchronous call.
\ Stack: source source-u profile memory-u candidate candidate-cap workspace
\     -- written status
: SBOX-COMPILE
    _SCC-BOUNDARY
    DUP IF
        >R _SCC-DROP7 0 R> EXIT
    THEN
    DROP

    >R
    5 PICK 5 PICK 0 _SCC-GEOMETRY R@ SWAP 0 FILL
    5 PICK 5 PICK R@ _SCC-GEOMETRY R@ _SCW.TOTAL !
    _SCC-DIAG-MAGIC R@ _SCD.MAGIC !
    -1 R@ _SCD.OFFSET !
    R@ _SCW.CANDIDATE-CAP !
    R@ _SCW.CANDIDATE !
    R@ _SCW.MEMORY-U !
    R@ _SCW.PROFILE !
    R@ _SCW.SOURCE-U !
    R@ _SCW.SOURCE-A !

    R@ _SCC-RUN
    R@ _SCW.INSTRUCTION-LIMIT @ 8 *
    OVER IF
        \ Every failure names a code; none left unnamed is internal.  A
        \ failed compilation keeps no source map.
        R@ _SCD.CODE @ 0= IF
            SBOX-COMPILER-E-INTERNAL R@ _SCD.CODE !
        THEN
        R@ _SCD-MAP + OVER 0 FILL
    ELSE
        R@ _SCW.INSTRUCTION-N @ R@ _SCD.INSTRUCTION-N !
    THEN
    OVER R@ _SCD.STATUS !
    \ Only the header and the source map remain.
    _SCD-MAP + R@ _SCW.TOTAL @ OVER - SWAP R@ + SWAP 0 FILL
    R@ _SCW-BASE + _SCD-MAP _SCW-BASE - 0 FILL
    R> DROP ;

\ The diagnostics a compilation left in its workspace.
: _SCC-DIAG?  ( workspace -- flag )
    DUP SBOX-COMPILER-DIAGNOSTIC-SIZE _SCC-WORKSPACE-STATUS IF DROP 0 EXIT THEN
    _SCD.MAGIC @ _SCC-DIAG-MAGIC = ;

: SBOX-COMPILER-LAST-STATUS@  ( workspace -- last-status status )
    DUP _SCC-DIAG? 0= IF DROP 0 SBOX-COMPILER-S-INVALID EXIT THEN
    _SCD.STATUS @ SBOX-COMPILER-S-OK ;

\ CODE is SBOX-COMPILER-E-NONE after a success.  OFFSET is -1 when no
\ source bytes caused the failure.
: SBOX-COMPILER-ERROR@  ( workspace -- code offset length status )
    DUP _SCC-DIAG? 0= IF DROP 0 -1 0 SBOX-COMPILER-S-INVALID EXIT THEN
    DUP _SCD.CODE @ OVER _SCD.OFFSET @ ROT _SCD.LENGTH @
    SBOX-COMPILER-S-OK ;

\ The source span the instruction at INDEX came from, after a successful
\ compilation.  INDEX counts instructions across the whole candidate, as
\ the verifier's error index does.
: SBOX-COMPILER-SOURCE-SPAN@  ( index workspace -- offset length status )
    DUP _SCC-DIAG? 0= IF 2DROP -1 0 SBOX-COMPILER-S-INVALID EXIT THEN
    2DUP _SCD.INSTRUCTION-N @ U< 0= IF
        2DROP -1 0 SBOX-COMPILER-S-INVALID EXIT
    THEN
    _SCD-MAP-CELL DUP 8 _SCC-SPAN-STATUS IF
        DROP -1 0 SBOX-COMPILER-S-INVALID EXIT
    THEN
    @ DUP 32 RSHIFT SWAP 0xFFFFFFFF AND
    SBOX-COMPILER-S-OK ;
