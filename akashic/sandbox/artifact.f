\ =====================================================================
\  artifact.f - Canonical sandbox artifact geometry
\ =====================================================================
\  The one executable module format (docs/sandbox/artifact-format.md).
\  The compiler writes it and the independent verifier admits it.  An
\  artifact is never executable authority: only the plan the verifier
\  seals from it can run.
\
\  An artifact begins with a 256-byte prefix: a 64-byte header that binds
\  the exact 32-byte profile digest, then six 32-byte section-directory
\  records.  The function, import, entry, entry-name, initial-memory and
\  instruction sections follow in that order, each at the next 16-byte
\  boundary with zero bytes between, and the instructions end the
\  artifact.  Every field is little-endian, and nothing in it is a native
\  address, XT or callback.
\
\  This module measures that geometry, writes an artifact's prefix, and
\  inspects a supplied artifact's prefix and placement.  Record policy,
\  padding bytes and the profile match belong to the verifier.
\ =====================================================================

PROVIDED akashic-sbx-artifact

REQUIRE format.f
REQUIRE ../utils/caller-span.f

0 CONSTANT SBOX-ARTIFACT-S-OK
1 CONSTANT SBOX-ARTIFACT-S-INVALID
2 CONSTANT SBOX-ARTIFACT-S-CAPACITY
3 CONSTANT SBOX-ARTIFACT-S-ALIAS

\ Every nonempty span a public operation owns passes the caller-memory
\ boundary before any byte is read or written.  Each refusal is INVALID.
: _SART-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP SBOX-ARTIFACT-S-INVALID EXIT THEN
    DUP 0= IF 2DROP SBOX-ARTIFACT-S-OK EXIT THEN
    OVER 0= IF 2DROP SBOX-ARTIFACT-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP SBOX-ARTIFACT-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS IF
        SBOX-ARTIFACT-S-INVALID
    ELSE
        SBOX-ARTIFACT-S-OK
    THEN ;

\ =====================================================================
\  Fixed geometry
\ =====================================================================

  1 CONSTANT SBOX-ARTIFACT-FORMAT
 64 CONSTANT SBOX-ARTIFACT-HEADER-SIZE
 32 CONSTANT SBOX-ARTIFACT-SECTION-SIZE
  6 CONSTANT SBOX-ARTIFACT-SECTION-N
256 CONSTANT SBOX-ARTIFACT-PREFIX-SIZE
 32 CONSTANT SBOX-ARTIFACT-DIGEST-SIZE

16 CONSTANT SBOX-ARTIFACT-FUNCTION-SIZE
16 CONSTANT SBOX-ARTIFACT-IMPORT-SIZE
16 CONSTANT SBOX-ARTIFACT-ENTRY-SIZE
16 CONSTANT SBOX-ARTIFACT-INSTRUCTION-SIZE

\ Every record is exactly 16 bytes.  These offsets are shared compiler,
\ verifier and VM geometry; they carry no record policy.
\
\ Function:
\   [u32 instruction-n, u16 params, u16 results,
\    u16 locals, u16 flags=0, u32 reserved=0]
 0 CONSTANT SBOX-ARTIFACT-FUNCTION-INSTRUCTION-N-OFFSET
 4 CONSTANT SBOX-ARTIFACT-FUNCTION-PARAMS-OFFSET
 6 CONSTANT SBOX-ARTIFACT-FUNCTION-RESULTS-OFFSET
 8 CONSTANT SBOX-ARTIFACT-FUNCTION-LOCALS-OFFSET
10 CONSTANT SBOX-ARTIFACT-FUNCTION-FLAGS-OFFSET
12 CONSTANT SBOX-ARTIFACT-FUNCTION-RESERVED-OFFSET

\ Import: the profile owns each import's signature and cost.
\   [u32 profile-import-id, u32 signature-id, u32 flags=0, u32 reserved=0]
 0 CONSTANT SBOX-ARTIFACT-IMPORT-ID-OFFSET
 4 CONSTANT SBOX-ARTIFACT-IMPORT-SIGNATURE-ID-OFFSET
 8 CONSTANT SBOX-ARTIFACT-IMPORT-FLAGS-OFFSET
12 CONSTANT SBOX-ARTIFACT-IMPORT-RESERVED-OFFSET

\ Entry:
\   [u32 name-off, u16 name-u, u16 flags=0,
\    u32 function-index, u32 signature-id]
 0 CONSTANT SBOX-ARTIFACT-ENTRY-NAME-OFFSET
 4 CONSTANT SBOX-ARTIFACT-ENTRY-NAME-U-OFFSET
 6 CONSTANT SBOX-ARTIFACT-ENTRY-FLAGS-OFFSET
 8 CONSTANT SBOX-ARTIFACT-ENTRY-FUNCTION-INDEX-OFFSET
12 CONSTANT SBOX-ARTIFACT-ENTRY-SIGNATURE-ID-OFFSET

\ Instruction:
\   [u16 opcode, u16 flags=0, u32 operand-a, u64 operand-b]
0 CONSTANT SBOX-ARTIFACT-INSTRUCTION-OPCODE-OFFSET
2 CONSTANT SBOX-ARTIFACT-INSTRUCTION-FLAGS-OFFSET
4 CONSTANT SBOX-ARTIFACT-INSTRUCTION-A-OFFSET
8 CONSTANT SBOX-ARTIFACT-INSTRUCTION-B-OFFSET

\ The format's absolute ceilings.  They bound what a parser or verifier
\ may ever have to hold.  How large a module one host admits is that
\ host's dynamic policy, at or below these.
16777216 CONSTANT SBOX-ARTIFACT-BYTES-MAX
65536    CONSTANT SBOX-ARTIFACT-FUNCTION-MAX
256      CONSTANT SBOX-ARTIFACT-IMPORT-MAX
4096     CONSTANT SBOX-ARTIFACT-ENTRY-MAX
262144   CONSTANT SBOX-ARTIFACT-NAME-BYTES-MAX
8388608  CONSTANT SBOX-ARTIFACT-INITIAL-BYTES-MAX
1048576  CONSTANT SBOX-ARTIFACT-INSTRUCTION-MAX

\ The 64-byte header:
\   +0  8 bytes  ASCII "AKSBX64" and one zero byte
\   +8  u16      format, exactly 1
\   +10 u16      prefix extent, exactly 256
\   +12 u32      flags, exactly zero
\   +16 u64      exact artifact byte extent
\   +24 u64      guest linear-memory bytes
\   +32 32 bytes the exact profile digest
 0 CONSTANT _SART-H-MAGIC
 8 CONSTANT _SART-H-FORMAT
10 CONSTANT _SART-H-EXTENT
12 CONSTANT _SART-H-FLAGS
16 CONSTANT _SART-H-TOTAL
24 CONSTANT _SART-H-MEMORY-U
32 CONSTANT _SART-H-PROFILE

\ One 32-byte section-directory record:
\   [u32 kind, u32 flags=0, u64 offset, u64 bytes,
\    u32 element-count, u32 element-bytes]
\ Sections 0 through 5 are kinds 1 through 6: functions, imports,
\ entries, entry-name bytes, initial-memory bytes and instructions.
 0 CONSTANT _SART-D-KIND
 4 CONSTANT _SART-D-FLAGS
 8 CONSTANT _SART-D-OFFSET
16 CONSTANT _SART-D-BYTES
24 CONSTANT _SART-D-COUNT
28 CONSTANT _SART-D-ELEMENT

: _SART-SECTION  ( artifact section -- record )
    SBOX-ARTIFACT-SECTION-SIZE * + SBOX-ARTIFACT-HEADER-SIZE + ;

\ Entry names and initial memory are bytes; every other section holds
\ 16-byte records.
: _SART-ELEMENT-U  ( section -- element-u )
    DUP 3 = SWAP 4 = OR IF 1 ELSE 16 THEN ;

: _SART-COUNT-MAX  ( section -- maximum )
    CASE
        0 OF SBOX-ARTIFACT-FUNCTION-MAX ENDOF
        1 OF SBOX-ARTIFACT-IMPORT-MAX ENDOF
        2 OF SBOX-ARTIFACT-ENTRY-MAX ENDOF
        3 OF SBOX-ARTIFACT-NAME-BYTES-MAX ENDOF
        4 OF SBOX-ARTIFACT-INITIAL-BYTES-MAX ENDOF
        SBOX-ARTIFACT-INSTRUCTION-MAX SWAP
    ENDCASE ;

\ =====================================================================
\  Caller-owned measured layout
\ =====================================================================
\  The six counts follow the self-binding, in section order, and the six
\  section offsets follow them, so section I's count and offset are one
\  cell index apart.

  0 CONSTANT _SAL-MAGIC
  8 CONSTANT _SAL-SELF
 16 CONSTANT _SAL-FUNCTION-N
 24 CONSTANT _SAL-IMPORT-N
 32 CONSTANT _SAL-ENTRY-N
 40 CONSTANT _SAL-NAME-U
 48 CONSTANT _SAL-INITIAL-U
 56 CONSTANT _SAL-INSTRUCTION-N
 64 CONSTANT _SAL-FUNCTION-OFF
 72 CONSTANT _SAL-IMPORT-OFF
 80 CONSTANT _SAL-ENTRY-OFF
 88 CONSTANT _SAL-NAME-OFF
 96 CONSTANT _SAL-INITIAL-OFF
104 CONSTANT _SAL-INSTRUCTION-OFF
112 CONSTANT _SAL-TOTAL
120 CONSTANT _SAL-RESERVED
128 CONSTANT SBOX-ARTIFACT-LAYOUT-SIZE

0x5342584152544C59 CONSTANT _SART-LAYOUT-MAGIC  \ "SBXARTLY"

: _SART-L.MAGIC          ( layout -- address ) _SAL-MAGIC + ;
: _SART-L.SELF           ( layout -- address ) _SAL-SELF + ;
: _SART-L.FUNCTION-N     ( layout -- address ) _SAL-FUNCTION-N + ;
: _SART-L.IMPORT-N       ( layout -- address ) _SAL-IMPORT-N + ;
: _SART-L.ENTRY-N        ( layout -- address ) _SAL-ENTRY-N + ;
: _SART-L.NAME-U         ( layout -- address ) _SAL-NAME-U + ;
: _SART-L.INITIAL-U      ( layout -- address ) _SAL-INITIAL-U + ;
: _SART-L.INSTRUCTION-N  ( layout -- address ) _SAL-INSTRUCTION-N + ;
: _SART-L.FUNCTION-OFF   ( layout -- address ) _SAL-FUNCTION-OFF + ;
: _SART-L.IMPORT-OFF     ( layout -- address ) _SAL-IMPORT-OFF + ;
: _SART-L.ENTRY-OFF      ( layout -- address ) _SAL-ENTRY-OFF + ;
: _SART-L.NAME-OFF       ( layout -- address ) _SAL-NAME-OFF + ;
: _SART-L.INITIAL-OFF    ( layout -- address ) _SAL-INITIAL-OFF + ;
: _SART-L.INSTRUCTION-OFF ( layout -- address ) _SAL-INSTRUCTION-OFF + ;
: _SART-L.TOTAL          ( layout -- address ) _SAL-TOTAL + ;
: _SART-L.RESERVED       ( layout -- address ) _SAL-RESERVED + ;

: _SART-L.COUNT   ( layout section -- address ) 8 * + _SAL-FUNCTION-N + ;
: _SART-L.OFFSET  ( layout section -- address ) 8 * + _SAL-FUNCTION-OFF + ;

: _SART-LAYOUT-STATUS  ( layout -- status )
    DUP 0= IF DROP SBOX-ARTIFACT-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SBOX-ARTIFACT-S-INVALID EXIT THEN
    SBOX-ARTIFACT-LAYOUT-SIZE _SART-SPAN-STATUS ;

: _SART-LIMIT-STATUS  ( value maximum -- status )
    >R
    DUP 0< IF
        DROP R> DROP SBOX-ARTIFACT-S-INVALID EXIT
    THEN
    R> U> IF
        SBOX-ARTIFACT-S-CAPACITY
    ELSE
        SBOX-ARTIFACT-S-OK
    THEN ;

\ The bytes section I occupies, padded to the next 16-byte boundary.
\ Every count is held to its ceiling first, so no size overflows.
: _SART-PADDED-U  ( count section -- bytes )
    _SART-ELEMENT-U * 15 + -16 AND ;

\ Does the layout hold each count within its ceiling, each section at its
\ one canonical offset, and the exact extent?
: _SART-PLACED?  ( layout -- flag )
    SBOX-ARTIFACT-PREFIX-SIZE
    SBOX-ARTIFACT-SECTION-N 0 DO
        OVER I _SART-L.COUNT @
        DUP 0< SWAP I _SART-COUNT-MAX > OR IF
            2DROP 0 UNLOOP EXIT
        THEN
        OVER I _SART-L.OFFSET @ OVER <> IF 2DROP 0 UNLOOP EXIT THEN
        OVER I _SART-L.COUNT @ I _SART-PADDED-U +
    LOOP
    DUP SBOX-ARTIFACT-BYTES-MAX U> IF 2DROP 0 EXIT THEN
    SWAP _SART-L.TOTAL @ = ;

: SBOX-ARTIFACT-LAYOUT-VALID?  ( layout -- flag )
    DUP _SART-LAYOUT-STATUS IF DROP 0 EXIT THEN
    DUP _SART-L.MAGIC @ _SART-LAYOUT-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SART-L.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SART-L.RESERVED @ IF DROP 0 EXIT THEN
    _SART-PLACED? ;

: _SART-MEASURE-FAIL  ( layout status -- status )
    >R SBOX-ARTIFACT-LAYOUT-SIZE 0 FILL R> ;

\ Places the six sections after the prefix, each at the next 16-byte
\ boundary, and writes the self-bound magic last.
: _SART-PLACE  ( layout -- status )
    SBOX-ARTIFACT-PREFIX-SIZE
    SBOX-ARTIFACT-SECTION-N 0 DO
        OVER I _SART-L.COUNT @ I _SART-COUNT-MAX _SART-LIMIT-STATUS
        ?DUP IF NIP UNLOOP _SART-MEASURE-FAIL EXIT THEN
        2DUP SWAP I _SART-L.OFFSET !
        OVER I _SART-L.COUNT @ I _SART-PADDED-U +
    LOOP
    DUP SBOX-ARTIFACT-BYTES-MAX U> IF
        DROP SBOX-ARTIFACT-S-CAPACITY _SART-MEASURE-FAIL EXIT
    THEN
    OVER _SART-L.TOTAL !
    _SART-LAYOUT-MAGIC OVER _SART-L.MAGIC !
    DROP SBOX-ARTIFACT-S-OK ;

\ Measure writes only the caller-owned layout.  Once that span is
\ admitted, every failure clears it.
\ Stack: function-n import-n entry-n name-u initial-u instruction-n layout
\     -- status
: SBOX-ARTIFACT-MEASURE
    >R
    R@ _SART-LAYOUT-STATUS IF
        2DROP 2DROP 2DROP R> DROP
        SBOX-ARTIFACT-S-INVALID EXIT
    THEN
    R@ SBOX-ARTIFACT-LAYOUT-SIZE 0 FILL
    R@ R@ _SART-L.SELF !
    R@ _SART-L.INSTRUCTION-N !
    R@ _SART-L.INITIAL-U !
    R@ _SART-L.NAME-U !
    R@ _SART-L.ENTRY-N !
    R@ _SART-L.IMPORT-N !
    R@ _SART-L.FUNCTION-N !
    R> _SART-PLACE ;

: _SART-LAYOUT-FIELD@  ( layout offset -- value|0 )
    OVER SBOX-ARTIFACT-LAYOUT-VALID? IF + @ ELSE 2DROP 0 THEN ;

: SBOX-ARTIFACT-LAYOUT-TOTAL@  ( layout -- total|0 )
    _SAL-TOTAL _SART-LAYOUT-FIELD@ ;
: SBOX-ARTIFACT-LAYOUT-FUNCTIONS@  ( layout -- offset|0 )
    _SAL-FUNCTION-OFF _SART-LAYOUT-FIELD@ ;
: SBOX-ARTIFACT-LAYOUT-IMPORTS@  ( layout -- offset|0 )
    _SAL-IMPORT-OFF _SART-LAYOUT-FIELD@ ;
: SBOX-ARTIFACT-LAYOUT-ENTRIES@  ( layout -- offset|0 )
    _SAL-ENTRY-OFF _SART-LAYOUT-FIELD@ ;
: SBOX-ARTIFACT-LAYOUT-NAMES@  ( layout -- offset|0 )
    _SAL-NAME-OFF _SART-LAYOUT-FIELD@ ;
: SBOX-ARTIFACT-LAYOUT-INITIAL@  ( layout -- offset|0 )
    _SAL-INITIAL-OFF _SART-LAYOUT-FIELD@ ;
: SBOX-ARTIFACT-LAYOUT-INSTRUCTIONS@  ( layout -- offset|0 )
    _SAL-INSTRUCTION-OFF _SART-LAYOUT-FIELD@ ;

\ =====================================================================
\  Writing the prefix
\ =====================================================================

: _SART-MAGIC?  ( artifact -- flag )
    DUP C@ [CHAR] A =
    OVER 1+ C@ [CHAR] K = AND
    OVER 2 + C@ [CHAR] S = AND
    OVER 3 + C@ [CHAR] B = AND
    OVER 4 + C@ [CHAR] X = AND
    OVER 5 + C@ [CHAR] 6 = AND
    OVER 6 + C@ [CHAR] 4 = AND
    SWAP 7 + C@ 0= AND ;

: _SART-WRITE-MAGIC  ( artifact -- )
    [CHAR] A OVER C!
    [CHAR] K OVER 1+ C!
    [CHAR] S OVER 2 + C!
    [CHAR] B OVER 3 + C!
    [CHAR] X OVER 4 + C!
    [CHAR] 6 OVER 5 + C!
    [CHAR] 4 OVER 6 + C!
    0 SWAP 7 + C! ;

\ The six directory records, from the layout.  Their flags stay zero.
: _SART-WRITE-DIRECTORY  ( layout artifact -- )
    SBOX-ARTIFACT-SECTION-N 0 DO
        DUP I _SART-SECTION
        I 1+ OVER _SART-D-KIND + SBOX-BYTE-U32-LE!
        2 PICK I _SART-L.OFFSET @ OVER _SART-D-OFFSET + SBOX-BYTE-U64-LE!
        2 PICK I _SART-L.COUNT @ OVER _SART-D-COUNT + SBOX-BYTE-U32-LE!
        I _SART-ELEMENT-U OVER _SART-D-ELEMENT + SBOX-BYTE-U32-LE!
        2 PICK I _SART-L.COUNT @ I _SART-ELEMENT-U *
            SWAP _SART-D-BYTES + SBOX-BYTE-U64-LE!
    LOOP
    2DROP ;

: _SART-DROP3>STATUS  ( x1 x2 x3 status -- status )
    >R 2DROP DROP R> ;

\ HEADER! zeroes the whole measured artifact, padding included, then
\ writes its prefix: the header with the profile digest, and the six
\ directory records.  The digest, layout and artifact must be disjoint.
: SBOX-ARTIFACT-HEADER!
  ( profile-digest memory-u layout artifact -- status )
    >R
    R@ 0= IF SBOX-ARTIFACT-S-INVALID R> DROP _SART-DROP3>STATUS EXIT THEN
    DUP SBOX-ARTIFACT-LAYOUT-VALID? 0= IF
        SBOX-ARTIFACT-S-INVALID R> DROP _SART-DROP3>STATUS EXIT
    THEN
    R@ OVER _SART-L.TOTAL @ _SART-SPAN-STATUS IF
        SBOX-ARTIFACT-S-INVALID R> DROP _SART-DROP3>STATUS EXIT
    THEN
    R@ OVER _SART-L.TOTAL @ 2 PICK SBOX-ARTIFACT-LAYOUT-SIZE
        MSPAN-OVERLAP? IF
        SBOX-ARTIFACT-S-ALIAS R> DROP _SART-DROP3>STATUS EXIT
    THEN
    2 PICK 0= IF
        SBOX-ARTIFACT-S-INVALID R> DROP _SART-DROP3>STATUS EXIT
    THEN
    2 PICK SBOX-ARTIFACT-DIGEST-SIZE _SART-SPAN-STATUS IF
        SBOX-ARTIFACT-S-INVALID R> DROP _SART-DROP3>STATUS EXIT
    THEN
    2 PICK SBOX-ARTIFACT-DIGEST-SIZE R@ 3 PICK _SART-L.TOTAL @
        MSPAN-OVERLAP? IF
        SBOX-ARTIFACT-S-ALIAS R> DROP _SART-DROP3>STATUS EXIT
    THEN
    \ Guest memory is any whole number of cells.
    OVER DUP 0< SWAP 7 AND OR IF
        SBOX-ARTIFACT-S-INVALID R> DROP _SART-DROP3>STATUS EXIT
    THEN

    R@ OVER _SART-L.TOTAL @ 0 FILL
    R@ _SART-WRITE-MAGIC
    SBOX-ARTIFACT-FORMAT R@ _SART-H-FORMAT + SBOX-BYTE-U16-LE!
    SBOX-ARTIFACT-PREFIX-SIZE R@ _SART-H-EXTENT + SBOX-BYTE-U16-LE!
    DUP _SART-L.TOTAL @ R@ _SART-H-TOTAL + SBOX-BYTE-U64-LE!
    OVER R@ _SART-H-MEMORY-U + SBOX-BYTE-U64-LE!
    2 PICK R@ _SART-H-PROFILE + SBOX-ARTIFACT-DIGEST-SIZE MOVE
    DUP R@ _SART-WRITE-DIRECTORY
    R> DROP SBOX-ARTIFACT-S-OK _SART-DROP3>STATUS ;

\ =====================================================================
\  Inspecting a supplied artifact
\ =====================================================================

: _SART-SECTION-VALID?  ( record section -- flag )
    OVER _SART-D-KIND + SBOX-BYTE-U32-LE@ OVER 1+ <> IF
        2DROP 0 EXIT
    THEN
    OVER _SART-D-FLAGS + SBOX-BYTE-U32-LE@ IF 2DROP 0 EXIT THEN
    _SART-ELEMENT-U
    OVER _SART-D-ELEMENT + SBOX-BYTE-U32-LE@ OVER <> IF
        2DROP 0 EXIT
    THEN
    OVER _SART-D-COUNT + SBOX-BYTE-U32-LE@ *
    SWAP _SART-D-BYTES + SBOX-BYTE-U64-LE@ = ;

\ The header's fixed fields: magic, format, prefix extent and flags.
: _SART-HEADER-FIXED?  ( artifact -- flag )
    DUP _SART-MAGIC? 0= IF DROP 0 EXIT THEN
    DUP _SART-H-FORMAT + SBOX-BYTE-U16-LE@
        SBOX-ARTIFACT-FORMAT <> IF DROP 0 EXIT THEN
    DUP _SART-H-EXTENT + SBOX-BYTE-U16-LE@
        SBOX-ARTIFACT-PREFIX-SIZE <> IF DROP 0 EXIT THEN
    _SART-H-FLAGS + SBOX-BYTE-U32-LE@ 0= ;

\ The fixed header fields and every directory record's kind, flags,
\ element size and byte length.
: _SART-PREFIX-VALID?  ( artifact -- flag )
    DUP _SART-HEADER-FIXED? 0= IF DROP 0 EXIT THEN
    SBOX-ARTIFACT-SECTION-N 0 DO
        DUP I _SART-SECTION I _SART-SECTION-VALID? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ Section I's element count, from a prefix already admitted.
: _SART-SECTION-COUNT  ( artifact section -- count )
    _SART-SECTION _SART-D-COUNT + SBOX-BYTE-U32-LE@ ;

\ Measures LAYOUT from the directory's element counts.
: _SART-MEASURE-DIRECTORY  ( artifact layout -- status )
    >R
    SBOX-ARTIFACT-SECTION-N 0 DO
        DUP I _SART-SECTION-COUNT SWAP
    LOOP
    DROP R> SBOX-ARTIFACT-MEASURE ;

: _SART-OFFSETS=  ( artifact layout -- flag )
    SBOX-ARTIFACT-SECTION-N 0 DO
        OVER I _SART-SECTION _SART-D-OFFSET + SBOX-BYTE-U64-LE@
        OVER I _SART-L.OFFSET @ <> IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ INSPECT treats the supplied extent as exact and independently rebuilds
\ the layout from the directory.  It validates the prefix and placement,
\ not record policy.  It does not touch LAYOUT until both spans are
\ admitted and disjoint; any later failure clears it.
: SBOX-ARTIFACT-INSPECT  ( artifact artifact-u layout -- status )
    >R
    R@ _SART-LAYOUT-STATUS IF
        2DROP R> DROP SBOX-ARTIFACT-S-INVALID EXIT
    THEN
    DUP 0< IF 2DROP R> DROP SBOX-ARTIFACT-S-INVALID EXIT THEN
    OVER 0= IF 2DROP R> DROP SBOX-ARTIFACT-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP R> DROP SBOX-ARTIFACT-S-INVALID EXIT
    THEN
    2DUP _SART-SPAN-STATUS IF
        2DROP R> DROP SBOX-ARTIFACT-S-INVALID EXIT
    THEN
    2DUP R@ SBOX-ARTIFACT-LAYOUT-SIZE MSPAN-OVERLAP? IF
        2DROP R> DROP SBOX-ARTIFACT-S-ALIAS EXIT
    THEN
    DUP SBOX-ARTIFACT-PREFIX-SIZE < IF
        2DROP R> SBOX-ARTIFACT-S-CAPACITY _SART-MEASURE-FAIL EXIT
    THEN
    OVER _SART-PREFIX-VALID? 0= IF
        2DROP R> SBOX-ARTIFACT-S-INVALID _SART-MEASURE-FAIL EXIT
    THEN
    OVER _SART-H-TOTAL + SBOX-BYTE-U64-LE@ OVER <> IF
        2DROP R> SBOX-ARTIFACT-S-INVALID _SART-MEASURE-FAIL EXIT
    THEN
    OVER _SART-H-MEMORY-U + SBOX-BYTE-U64-LE@ 0< IF
        2DROP R> SBOX-ARTIFACT-S-INVALID _SART-MEASURE-FAIL EXIT
    THEN
    OVER R@ _SART-MEASURE-DIRECTORY
    ?DUP IF >R 2DROP R> R> DROP EXIT THEN
    OVER R@ _SART-OFFSETS= 0= IF
        2DROP R> SBOX-ARTIFACT-S-INVALID _SART-MEASURE-FAIL EXIT
    THEN
    R@ _SART-L.TOTAL @ OVER <> IF
        2DROP R> SBOX-ARTIFACT-S-INVALID _SART-MEASURE-FAIL EXIT
    THEN
    2DROP R> DROP SBOX-ARTIFACT-S-OK ;

\ =====================================================================
\  Prefix queries
\ =====================================================================
\  Each admits the 256-byte prefix span and reads one field.  They are
\  meaningful only for an artifact INSPECT has admitted.

: _SART-PREFIX-ADMIT?  ( artifact -- artifact flag )
    DUP SBOX-ARTIFACT-PREFIX-SIZE _SART-SPAN-STATUS 0= ;

: SBOX-ARTIFACT-TOTAL@  ( artifact -- total|0 )
    _SART-PREFIX-ADMIT? IF
        _SART-H-TOTAL + SBOX-BYTE-U64-LE@
    ELSE DROP 0 THEN ;

: SBOX-ARTIFACT-MEMORY-U@  ( artifact -- memory-u|0 )
    _SART-PREFIX-ADMIT? IF
        _SART-H-MEMORY-U + SBOX-BYTE-U64-LE@
    ELSE DROP 0 THEN ;

\ The 32 profile-digest bytes inside the artifact.
: SBOX-ARTIFACT-PROFILE-DIGEST@  ( artifact -- digest|0 )
    _SART-PREFIX-ADMIT? IF _SART-H-PROFILE + ELSE DROP 0 THEN ;

: _SART-COUNT@  ( artifact section -- count|0 )
    SWAP _SART-PREFIX-ADMIT? IF
        SWAP _SART-SECTION-COUNT
    ELSE
        2DROP 0
    THEN ;

: SBOX-ARTIFACT-FUNCTION-N@     ( artifact -- count|0 ) 0 _SART-COUNT@ ;
: SBOX-ARTIFACT-IMPORT-N@       ( artifact -- count|0 ) 1 _SART-COUNT@ ;
: SBOX-ARTIFACT-ENTRY-N@        ( artifact -- count|0 ) 2 _SART-COUNT@ ;
: SBOX-ARTIFACT-NAME-U@         ( artifact -- length|0 ) 3 _SART-COUNT@ ;
: SBOX-ARTIFACT-INITIAL-U@      ( artifact -- length|0 ) 4 _SART-COUNT@ ;
: SBOX-ARTIFACT-INSTRUCTION-N@  ( artifact -- count|0 ) 5 _SART-COUNT@ ;
