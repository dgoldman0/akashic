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

\ Private tokenizer completion.  It never escapes SBOX-COMPILE.
7 CONSTANT _SCC-S-EOF

\ Permanent frontend bounds.  Semantic table/code maxima are exactly the
\ candidate/profile maxima.  Source has one explicit bounded scan ceiling.
262144 CONSTANT SBOX-COMPILER-SOURCE-MAX
63     CONSTANT SBOX-COMPILER-TOKEN-MAX
64     CONSTANT _SCC-NAME-SLOT-SIZE
SBOX-PROFILE-MAX-LOOP-FRAMES CONSTANT _SCC-CONTROL-MAX

\ =====================================================================
\  Fixed caller-owned workspace
\ =====================================================================

\ Scalar operation state.
  0 CONSTANT _SCW-SOURCE-A
  8 CONSTANT _SCW-SOURCE-U
 16 CONSTANT _SCW-SOURCE-POS
 24 CONSTANT _SCW-TOKEN-A
 32 CONSTANT _SCW-TOKEN-U
 40 CONSTANT _SCW-PROFILE
 48 CONSTANT _SCW-MEMORY-U
 56 CONSTANT _SCW-CANDIDATE
 64 CONSTANT _SCW-CANDIDATE-CAP
 72 CONSTANT _SCW-FUNCTION-N
 80 CONSTANT _SCW-ENTRY-N
 88 CONSTANT _SCW-NAME-U
 96 CONSTANT _SCW-INSTRUCTION-N
104 CONSTANT _SCW-FIXUP-N
112 CONSTANT _SCW-CONTROL-N
120 CONSTANT _SCW-DO-N
128 CONSTANT _SCW-CURRENT-FUNCTION
136 CONSTANT _SCW-CURRENT-START
144 CONSTANT _SCW-CURRENT-LOCALS
152 CONSTANT _SCW-REACHABLE
160 CONSTANT _SCW-PROFILE-TAG
168 CONSTANT _SCW-FUNCTION-LIMIT
176 CONSTANT _SCW-ENTRY-LIMIT
184 CONSTANT _SCW-INSTRUCTION-LIMIT
192 CONSTANT _SCW-LOCAL-LIMIT
200 CONSTANT _SCW-RESULT-LIMIT
208 CONSTANT _SCW-OPERAND-LIMIT
216 CONSTANT _SCW-LOOP-LIMIT
224 CONSTANT _SCW-TMP-OPCODE
232 CONSTANT _SCW-TMP-A
240 CONSTANT _SCW-TMP-B
248 CONSTANT _SCW-TMP-X
256 CONSTANT _SCW-SAVED-A
264 CONSTANT _SCW-SAVED-B
272 CONSTANT _SCC-STATE-SIZE

\ Function metadata: name-u, params, results, locals, instruction-start,
\ instruction-n.  Names occupy a separate fixed 64-byte slot per function.
48 CONSTANT _SCC-FMETA-SIZE
 0 CONSTANT _SCFM-NAME-U
 8 CONSTANT _SCFM-PARAMS
16 CONSTANT _SCFM-RESULTS
24 CONSTANT _SCFM-LOCALS
32 CONSTANT _SCFM-INSTRUCTION-START
40 CONSTANT _SCFM-INSTRUCTION-N

_SCC-STATE-SIZE CONSTANT _SCC-FMETA-OFF
_SCC-FMETA-OFF
SBOX-CANDIDATE-FUNCTION-MAX _SCC-FMETA-SIZE * +
CONSTANT _SCC-FNAME-OFF

\ Entry metadata: name offset, name length, resolved function index, signature.
32 CONSTANT _SCC-EMETA-SIZE
 0 CONSTANT _SCEM-NAME-OFF
 8 CONSTANT _SCEM-NAME-U
16 CONSTANT _SCEM-FUNCTION
24 CONSTANT _SCEM-SIGNATURE

_SCC-FNAME-OFF
SBOX-CANDIDATE-FUNCTION-MAX _SCC-NAME-SLOT-SIZE * +
CONSTANT _SCC-EMETA-OFF
_SCC-EMETA-OFF
SBOX-CANDIDATE-ENTRY-MAX _SCC-EMETA-SIZE * +
CONSTANT _SCC-ENTRY-NAMES-OFF
_SCC-ENTRY-NAMES-OFF SBOX-CANDIDATE-NAME-BYTES-MAX +
CONSTANT _SCC-INSTRUCTIONS-OFF

\ One source-backed direct-call fixup per possible instruction.
24 CONSTANT _SCC-FIXUP-SIZE
 0 CONSTANT _SCFX-INSTRUCTION
 8 CONSTANT _SCFX-NAME-A
16 CONSTANT _SCFX-NAME-U

_SCC-INSTRUCTIONS-OFF
SBOX-CANDIDATE-INSTRUCTION-MAX SBOX-CANDIDATE-INSTRUCTION-SIZE * +
CONSTANT _SCC-FIXUPS-OFF

\ Typed lexical control frame: kind and three kind-specific scalar fields.
32 CONSTANT _SCC-CONTROL-SIZE
 0 CONSTANT _SCCF-KIND
 8 CONSTANT _SCCF-A
16 CONSTANT _SCCF-B
24 CONSTANT _SCCF-C

_SCC-FIXUPS-OFF
SBOX-CANDIDATE-INSTRUCTION-MAX _SCC-FIXUP-SIZE * +
CONSTANT _SCC-CONTROL-OFF
_SCC-CONTROL-OFF _SCC-CONTROL-MAX _SCC-CONTROL-SIZE * +
CONSTANT _SCC-LAYOUT-OFF
_SCC-LAYOUT-OFF SBOX-CANDIDATE-LAYOUT-SIZE +
CONSTANT _SCC-STAGE-OFF

\ Largest possible import-free candidate:
\ header + functions + entries + padded names + instructions.
SBOX-CANDIDATE-HEADER-SIZE
SBOX-CANDIDATE-FUNCTION-MAX SBOX-CANDIDATE-FUNCTION-SIZE * +
SBOX-CANDIDATE-ENTRY-MAX SBOX-CANDIDATE-ENTRY-SIZE * +
SBOX-CANDIDATE-NAME-BYTES-MAX +
SBOX-CANDIDATE-INSTRUCTION-MAX SBOX-CANDIDATE-INSTRUCTION-SIZE * +
CONSTANT _SCC-STAGE-MAX

\ Includes deliberate spare space after the maximum staging image.
262144 CONSTANT SBOX-COMPILER-WORKSPACE-SIZE

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
: _SCW.LOCAL-LIMIT      ( w -- a ) _SCW-LOCAL-LIMIT + ;
: _SCW.RESULT-LIMIT     ( w -- a ) _SCW-RESULT-LIMIT + ;
: _SCW.OPERAND-LIMIT    ( w -- a ) _SCW-OPERAND-LIMIT + ;
: _SCW.LOOP-LIMIT       ( w -- a ) _SCW-LOOP-LIMIT + ;
: _SCW.TMP-OPCODE       ( w -- a ) _SCW-TMP-OPCODE + ;
: _SCW.TMP-A            ( w -- a ) _SCW-TMP-A + ;
: _SCW.TMP-B            ( w -- a ) _SCW-TMP-B + ;
: _SCW.TMP-X            ( w -- a ) _SCW-TMP-X + ;
: _SCW.SAVED-A          ( w -- a ) _SCW-SAVED-A + ;
: _SCW.SAVED-B          ( w -- a ) _SCW-SAVED-B + ;

: _SCC-FMETA  ( index w -- a )
    _SCC-FMETA-OFF + SWAP _SCC-FMETA-SIZE * + ;

: _SCC-FNAME  ( index w -- a )
    _SCC-FNAME-OFF + SWAP _SCC-NAME-SLOT-SIZE * + ;

: _SCC-EMETA  ( index w -- a )
    _SCC-EMETA-OFF + SWAP _SCC-EMETA-SIZE * + ;

: _SCC-ENTRY-NAMES  ( w -- a ) _SCC-ENTRY-NAMES-OFF + ;

: _SCC-INSTRUCTION  ( index w -- a )
    _SCC-INSTRUCTIONS-OFF +
    SWAP SBOX-CANDIDATE-INSTRUCTION-SIZE * + ;

: _SCC-FIXUP  ( index w -- a )
    _SCC-FIXUPS-OFF + SWAP _SCC-FIXUP-SIZE * + ;

: _SCC-CONTROL  ( index w -- a )
    _SCC-CONTROL-OFF + SWAP _SCC-CONTROL-SIZE * + ;

: _SCC-LAYOUT  ( w -- a ) _SCC-LAYOUT-OFF + ;
: _SCC-STAGE   ( w -- a ) _SCC-STAGE-OFF + ;

\ Compile-time assertions over immutable geometry.
_SCC-STAGE-OFF _SCC-STAGE-MAX +
SBOX-COMPILER-WORKSPACE-SIZE > [IF]
    ." sandbox compiler workspace geometry mismatch" CR ABORT
[THEN]

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

: _SCC-WORKSPACE-STATUS  ( workspace -- status )
    DUP 0= IF DROP SBOX-COMPILER-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SBOX-COMPILER-S-INVALID EXIT THEN
    SBOX-COMPILER-WORKSPACE-SIZE _SCC-SPAN-STATUS ;

\ Preserve all seven API inputs and append one status.
\ Stack input: source source-u profile memory-u candidate candidate-cap
\              workspace
\ Stack output: the same seven inputs followed by status
: _SCC-BOUNDARY
    DUP _SCC-WORKSPACE-STATUS ?DUP IF EXIT THEN

    6 PICK 6 PICK _SCC-SPAN-STATUS ?DUP IF EXIT THEN
    5 PICK SBOX-COMPILER-SOURCE-MAX U> IF
        SBOX-COMPILER-S-CAPACITY EXIT
    THEN

    4 PICK SBOX-PROFILE-SIZE _SCC-SPAN-STATUS ?DUP IF EXIT THEN
    2 PICK 2 PICK _SCC-SPAN-STATUS ?DUP IF EXIT THEN

    \ source/profile
    6 PICK 6 PICK
    6 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP? IF
        SBOX-COMPILER-S-ALIAS EXIT
    THEN
    \ source/candidate
    6 PICK 6 PICK 4 PICK 4 PICK MSPAN-OVERLAP? IF
        SBOX-COMPILER-S-ALIAS EXIT
    THEN
    \ source/workspace
    6 PICK 6 PICK 2 PICK SBOX-COMPILER-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF SBOX-COMPILER-S-ALIAS EXIT THEN
    \ profile/candidate
    4 PICK SBOX-PROFILE-SIZE 4 PICK 4 PICK
        MSPAN-OVERLAP? IF SBOX-COMPILER-S-ALIAS EXIT THEN
    \ profile/workspace
    4 PICK SBOX-PROFILE-SIZE 2 PICK SBOX-COMPILER-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF SBOX-COMPILER-S-ALIAS EXIT THEN
    \ candidate/workspace
    2 PICK 2 PICK 2 PICK SBOX-COMPILER-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF SBOX-COMPILER-S-ALIAS EXIT THEN

    SBOX-COMPILER-S-OK ;

: _SCC-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP DROP ;

\ =====================================================================
\  ASCII tokenizer and canonical scalar parsing
\ =====================================================================

: _SCC-WHITESPACE?  ( byte -- flag )
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 10 = IF DROP -1 EXIT THEN
    DUP 13 = IF DROP -1 EXIT THEN
    32 = ;

: _SCC-SOURCE-BYTE?  ( byte -- flag )
    DUP _SCC-WHITESPACE? IF DROP -1 EXIT THEN
    33 127 WITHIN ;

: _SCC-SOURCE-BYTES?  ( workspace -- flag )
    >R
    0
    BEGIN DUP R@ _SCW.SOURCE-U @ U< WHILE
        R@ _SCW.SOURCE-A @ OVER + C@ _SCC-SOURCE-BYTE? 0= IF
            DROP R> DROP 0 EXIT
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
            R> DROP SBOX-COMPILER-S-SOURCE EXIT
        THEN
        1 R@ _SCW.SOURCE-POS +!
        1 R@ _SCW.TOKEN-U +!
        R@ _SCW.TOKEN-U @ SBOX-COMPILER-TOKEN-MAX U> IF
            R> DROP SBOX-COMPILER-S-CAPACITY EXIT
        THEN
    REPEAT
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-NEXT-REQUIRED  ( workspace -- status )
    _SCC-NEXT
    DUP _SCC-S-EOF = IF DROP SBOX-COMPILER-S-SOURCE THEN ;

: _SCC-TOKEN=  ( literal-a literal-u workspace -- flag )
    >R
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _SCC-EXPECT  ( literal-a literal-u workspace -- status )
    >R
    R@ _SCC-NEXT-REQUIRED DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _SCC-TOKEN= 0= IF
        SBOX-COMPILER-S-SOURCE
    ELSE
        SBOX-COMPILER-S-OK
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

: _SCC-LOAD-LIMIT  ( field destination profile -- status )
    >R
    SWAP R@ SBOX-PROFILE-LIMIT@
    DUP IF
        >R 2DROP R> DROP R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN
    DROP SWAP !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-LOAD-PROFILE  ( workspace -- status )
    >R
    R@ _SCW.PROFILE @ SBOX-PROFILE-VALID? 0= IF
        R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN

    R@ _SCW.PROFILE @ SBOX-PROFILE-TAG@
    DUP IF
        2DROP R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN
    DROP R@ _SCW.PROFILE-TAG !

    SBOX-PROFILE-LIMIT-FUNCTIONS
        R@ _SCW.FUNCTION-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-ENTRIES
        R@ _SCW.ENTRY-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-INSTRUCTIONS
        R@ _SCW.INSTRUCTION-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-LOCALS-PER-FRAME
        R@ _SCW.LOCAL-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-RESULT-CELLS
        R@ _SCW.RESULT-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-OPERAND-CELLS
        R@ _SCW.OPERAND-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-LOOP-FRAMES
        R@ _SCW.LOOP-LIMIT R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN
    SBOX-PROFILE-LIMIT-MEMORY-BYTES
        R@ _SCW.TMP-X R@ _SCW.PROFILE @
        _SCC-LOAD-LIMIT ?DUP IF R> DROP EXIT THEN

    R@ _SCW.MEMORY-U @ DUP 0< IF
        DROP R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN
    DUP 7 AND IF
        DROP R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN
    R@ _SCW.TMP-X @ U> IF
        R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN

    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-OPCODE-STATUS  ( opcode workspace -- status )
    >R
    R@ _SCW.PROFILE @ SBOX-PROFILE-OPCODE-ENABLED?
    DUP IF
        2DROP R> DROP SBOX-COMPILER-S-PROFILE EXIT
    THEN
    DROP 0= IF
        R> DROP SBOX-COMPILER-S-PROFILE
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
    R@ _SCW.FIXUP-N @
        SBOX-CANDIDATE-INSTRUCTION-MAX U< 0= IF
        DROP R> DROP SBOX-COMPILER-S-CAPACITY EXIT
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

: _SCC-EMIT  ( opcode operand-a operand-b workspace -- status )
    >R
    2 PICK R@ _SCW.TMP-OPCODE !
    OVER R@ _SCW.TMP-A !
    DUP R@ _SCW.TMP-B !
    2DROP DROP

    R@ _SCW.INSTRUCTION-N @ R@ _SCW.INSTRUCTION-LIMIT @ U< 0= IF
        R> DROP SBOX-COMPILER-S-CAPACITY EXIT
    THEN
    R@ _SCW.INSTRUCTION-N @
        SBOX-CANDIDATE-INSTRUCTION-MAX U< 0= IF
        R> DROP SBOX-COMPILER-S-CAPACITY EXIT
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
    R@ _SCW.CONTROL-N @ _SCC-CONTROL-MAX U< 0= IF
        2DROP 2DROP R> DROP SBOX-COMPILER-S-CAPACITY EXIT
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
    R@ _SCW.DO-N @ R@ _SCW.LOOP-LIMIT @ U< 0= IF
        R> DROP SBOX-COMPILER-S-CAPACITY EXIT
    THEN
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.REACHABLE @ 0= IF
        DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        DROP R> DROP 0 SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-COMPILE-CALL  ( workspace -- status )
    >R
    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.FIXUP-N @
        SBOX-CANDIDATE-INSTRUCTION-MAX U< 0= IF
        R> DROP SBOX-COMPILER-S-CAPACITY EXIT
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
        2DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    SBOX-MACHINE-OP-RETURN R@ _SCC-EMIT0
    ?DUP IF R> DROP EXIT THEN
    0 R@ _SCW.REACHABLE !
    R> DROP SBOX-COMPILER-S-OK ;

: _SCC-COMPILE-R  ( workspace -- status )
    DUP _SCW.DO-N @ 0= IF
        DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
    R> DROP SBOX-COMPILER-S-SOURCE ;

\ =====================================================================
\  Top-level declarations and namespace resolution
\ =====================================================================

: _SCC-STORE-CURRENT-FMETA  ( value field-offset workspace -- )
    >R
    R@ _SCW.CURRENT-FUNCTION @ R@ _SCC-FMETA
    + !
    R> DROP ;

: _SCC-FUNCTION-CAPACITY?  ( workspace -- flag )
    DUP _SCW.FUNCTION-N @ OVER _SCW.FUNCTION-LIMIT @ U<
    SWAP _SCW.FUNCTION-N @ SBOX-CANDIDATE-FUNCTION-MAX U< AND ;

: _SCC-PARSE-FUNCTION  ( workspace -- status )
    >R
    R@ _SCC-FUNCTION-CAPACITY? 0= IF
        R> DROP SBOX-COMPILER-S-CAPACITY EXIT
    THEN

    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @ R@ _SCC-FIND-FUNCTION
    IF
        DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    DROP

    R@ _SCW.FUNCTION-N @ DUP R@ _SCW.CURRENT-FUNCTION !
    R@ _SCC-STORE-CURRENT-FUNCTION-NAME

    S" PARAMS" R@ _SCC-EXPECT ?DUP IF R> DROP EXIT THEN
    R@ _SCW.OPERAND-LIMIT @ R@ _SCC-READ-U
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP _SCFM-PARAMS R@ _SCC-STORE-CURRENT-FMETA

    S" RESULTS" R@ _SCC-EXPECT ?DUP IF R> DROP EXIT THEN
    R@ _SCW.RESULT-LIMIT @ R@ _SCC-READ-U
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP _SCFM-RESULTS R@ _SCC-STORE-CURRENT-FMETA

    S" LOCALS" R@ _SCC-EXPECT ?DUP IF R> DROP EXIT THEN
    R@ _SCW.LOCAL-LIMIT @ R@ _SCC-READ-U
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
                R> DROP SBOX-COMPILER-S-SOURCE EXIT
            THEN
            R@ _SCW.REACHABLE @ IF
                R> DROP SBOX-COMPILER-S-SOURCE EXIT
            THEN
            R@ _SCW.INSTRUCTION-N @ R@ _SCW.CURRENT-START @ -
                _SCFM-INSTRUCTION-N R@ _SCC-STORE-CURRENT-FMETA
            1 R@ _SCW.FUNCTION-N +!
            R> DROP SBOX-COMPILER-S-OK EXIT
        THEN
        R@ _SCC-COMPILE-CURRENT ?DUP IF R> DROP EXIT THEN
    AGAIN ;

: _SCC-ENTRY-NAME@  ( index workspace -- address length )
    >R
    R@ _SCC-ENTRY-NAMES
    OVER R@ _SCC-EMETA _SCEM-NAME-OFF + @ +
    SWAP R@ _SCC-EMETA _SCEM-NAME-U + @
    R> DROP ;

: _SCC-ENTRY-CAPACITY?  ( workspace -- flag )
    DUP _SCW.ENTRY-N @ OVER _SCW.ENTRY-LIMIT @ U<
    SWAP _SCW.ENTRY-N @ SBOX-CANDIDATE-ENTRY-MAX U< AND ;

: _SCC-CURRENT-ENTRY-INCREASING?  ( workspace -- flag )
    >R
    R@ _SCW.ENTRY-N @ DUP 0= IF
        DROP R> DROP -1 EXIT
    THEN
    1- R@ _SCC-ENTRY-NAME@
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @
    COMPARE 0<
    R> DROP ;

: _SCC-PARSE-ENTRY  ( workspace -- status )
    >R
    R@ _SCC-ENTRY-CAPACITY? 0= IF
        R> DROP SBOX-COMPILER-S-CAPACITY EXIT
    THEN
    0 R@ _SCW.TMP-X !
    R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    S" SIGNATURE" R@ _SCC-TOKEN= IF
        R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
        SBOX-ABI-SIGNATURE-VALUE-TO-VALUE R@ _SCC-READ-U
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        DUP 0= IF
            DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
        THEN
        R@ _SCW.TMP-X !
        R@ _SCC-NEXT-REQUIRED ?DUP IF R> DROP EXIT THEN
    THEN
    R@ _SCC-CURRENT-NAME? 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCC-CURRENT-ENTRY-INCREASING? 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.TOKEN-U @
    SBOX-CANDIDATE-NAME-BYTES-MAX R@ _SCW.NAME-U @ -
    U> IF R> DROP SBOX-COMPILER-S-CAPACITY EXIT THEN

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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    R@ _SCW.TOKEN-A @ R@ _SCW.TOKEN-U @ R@ _SCC-FIND-FUNCTION
    0= IF
        DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN
    DUP R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-FUNCTION + !
    DROP

    \ Signature zero remains the explicit internal scalar qualification
    \ form.  A production entry is spelled `ENTRY SIGNATURE 1 ...`; its
    \ function shape is checked here and again by the independent verifier.
    R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-SIGNATURE + @
    ?DUP IF
        SBOX-ABI-SIGNATURE-VALUE-TO-VALUE <> IF
            R> DROP SBOX-COMPILER-S-SOURCE EXIT
        THEN
        R@ _SCW.ENTRY-N @ R@ _SCC-EMETA _SCEM-FUNCTION + @
        R@ _SCC-FMETA
        DUP _SCFM-PARAMS + @ 1 <>
        SWAP _SCFM-RESULTS + @ 1 <> OR IF
            R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R@ _SCC-FIND-FUNCTION
        0= IF
            2DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
        THEN
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
            DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
                DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
    THEN

    BEGIN
        R@ _SCC-PARSE-FUNCTION ?DUP IF R> DROP EXIT THEN
        R@ _SCC-NEXT
        DUP _SCC-S-EOF = IF
            DROP R> DROP SBOX-COMPILER-S-SOURCE EXIT
        THEN
        ?DUP IF R> DROP EXIT THEN
        S" FUNCTION" R@ _SCC-TOKEN=
    WHILE
    REPEAT

    S" ENTRY" R@ _SCC-TOKEN= 0= IF
        R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
            R> DROP SBOX-COMPILER-S-SOURCE EXIT
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
    R@ _SCC-INSTRUCTIONS-OFF +
    R@ _SCC-STAGE
        R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-INSTRUCTIONS@ +
    ROT MOVE
    R> DROP ;

: _SCC-CANDIDATE-STATUS>COMPILER  ( candidate-status -- status )
    DUP SBOX-CANDIDATE-S-CAPACITY = IF
        DROP SBOX-COMPILER-S-CAPACITY EXIT
    THEN
    DROP SBOX-COMPILER-S-INTERNAL ;

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
        _SCC-CANDIDATE-STATUS>COMPILER
        R> DROP 0 SWAP EXIT
    THEN
    DROP

    R@ _SCC-LAYOUT SBOX-CANDIDATE-LAYOUT-TOTAL@
        DUP R@ _SCW.TMP-X !
    DUP _SCC-STAGE-MAX U> IF
        DROP R> DROP 0 SBOX-COMPILER-S-INTERNAL EXIT
    THEN
    R@ _SCW.CANDIDATE-CAP @ U> IF
        R> DROP 0 SBOX-COMPILER-S-CAPACITY EXIT
    THEN

    R@ _SCW.PROFILE-TAG @
    R@ _SCW.MEMORY-U @
    R@ _SCC-LAYOUT
    R@ _SCC-STAGE
    SBOX-CANDIDATE-HEADER!
    DUP IF
        _SCC-CANDIDATE-STATUS>COMPILER
        R> DROP 0 SWAP EXIT
    THEN
    DROP

    R@ _SCC-WRITE-FUNCTIONS
    R@ _SCC-WRITE-ENTRIES
    R@ _SCC-WRITE-BYTES

    R@ _SCC-STAGE R@ _SCW.TMP-X @ R@ _SCC-LAYOUT
        SBOX-CANDIDATE-INSPECT
    DUP IF
        DROP R> DROP 0 SBOX-COMPILER-S-INTERNAL EXIT
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
    R@ _SCC-SOURCE-BYTES? 0= IF
        R> DROP 0 SBOX-COMPILER-S-SOURCE EXIT
    THEN
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
    R@ SBOX-COMPILER-WORKSPACE-SIZE 0 FILL
    R@ _SCW.CANDIDATE-CAP !
    R@ _SCW.CANDIDATE !
    R@ _SCW.MEMORY-U !
    R@ _SCW.PROFILE !
    R@ _SCW.SOURCE-U !
    R@ _SCW.SOURCE-A !

    R@ _SCC-RUN
    R>
    DUP SBOX-COMPILER-WORKSPACE-SIZE 0 FILL
    DROP ;
