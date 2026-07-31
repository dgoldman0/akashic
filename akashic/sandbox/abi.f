\ =====================================================================
\  abi.f - Permanent typed-value ABI metadata over the scalar machine
\ =====================================================================
\  The scalar machine remains independently useful to the compiler,
\  verifier, and low-level executor qualification.  This module adds the
\  closed typed-value instruction surface used by production entry
\  signatures.  It owns opcode numbers and immutable verifier/runtime
\  metadata only; value arenas, schemas, module declarations, host policy,
\  and invocation state live elsewhere.
\
\  Queries accept both scalar-machine and typed-value opcodes.  Scalar rows
\  are delegated unchanged to machine.f, so consumers have one complete
\  metadata boundary without duplicating or replacing the scalar evaluator.
\ =====================================================================

PROVIDED akashic-sbx-abi

REQUIRE machine.f

\ Typed-value opcodes fixed by docs/sandbox/profile-and-abi.md.
0x60 CONSTANT SBOX-ABI-OP-V-TYPE
0x61 CONSTANT SBOX-ABI-OP-V-BOOL-GET
0x62 CONSTANT SBOX-ABI-OP-V-I64-GET
0x63 CONSTANT SBOX-ABI-OP-V-LEN
0x64 CONSTANT SBOX-ABI-OP-V-LIST-GET
0x65 CONSTANT SBOX-ABI-OP-V-MAP-KEY
0x66 CONSTANT SBOX-ABI-OP-V-MAP-VALUE
0x67 CONSTANT SBOX-ABI-OP-V-MAP-FIND
0x68 CONSTANT SBOX-ABI-OP-V-BLOB-COPY

0x70 CONSTANT SBOX-ABI-OP-V-NEW-NULL
0x71 CONSTANT SBOX-ABI-OP-V-NEW-BOOL
0x72 CONSTANT SBOX-ABI-OP-V-NEW-I64
0x73 CONSTANT SBOX-ABI-OP-V-NEW-BYTES
0x74 CONSTANT SBOX-ABI-OP-V-NEW-UTF8
0x75 CONSTANT SBOX-ABI-OP-V-NEW-LIST
0x76 CONSTANT SBOX-ABI-OP-V-NEW-MAP

\ Physical production entry signature.
1 CONSTANT SBOX-ABI-SIGNATURE-VALUE-TO-VALUE

\ Typed dynamic cost kinds occupy the range deliberately left by machine.f.
3 CONSTANT SBOX-ABI-COST-VALUE-FIXED
4 CONSTANT SBOX-ABI-COST-VALUE-LENGTH
5 CONSTANT SBOX-ABI-COST-VALUE-MAP

\ Extra semantic counters.  Instruction units are always charged; these
\ values additionally identify value-operation and copied-byte accounting.
1 CONSTANT SBOX-ABI-EXTRA-VALUE-OP
3 CONSTANT SBOX-ABI-EXTRA-VALUE-COPY
5 CONSTANT SBOX-ABI-EXTRA-VALUE-MAP

\ Expand one fixed-stack-effect typed row.
\ Stack: pop push cost-kind base divisor extra
\     -- operand effect pop push cost-kind base divisor extra status
: _SBOX-ABI-VALUE-META
    >R >R >R >R >R >R
    SBOX-MACHINE-OPERAND-NONE
    SBOX-MACHINE-EFFECT-FIXED
    R> R> R> R> R> R>
    SBOX-MACHINE-S-OK ;

: SBOX-ABI-METADATA
    ( opcode -- operand effect pop push cost-kind base divisor extra status )
    DUP SBOX-MACHINE-OPCODE-SUPPORTED? IF
        SBOX-MACHINE-METADATA EXIT
    THEN
    CASE
        SBOX-ABI-OP-V-TYPE OF
            1 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-BOOL-GET OF
            1 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-I64-GET OF
            1 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-LEN OF
            1 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-LIST-GET OF
            2 1 SBOX-ABI-COST-VALUE-FIXED 3 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-MAP-KEY OF
            2 1 SBOX-ABI-COST-VALUE-FIXED 3 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-MAP-VALUE OF
            2 1 SBOX-ABI-COST-VALUE-FIXED 3 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-MAP-FIND OF
            3 2 SBOX-ABI-COST-VALUE-MAP 4 8
            SBOX-ABI-EXTRA-VALUE-MAP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-BLOB-COPY OF
            4 0 SBOX-ABI-COST-VALUE-LENGTH 4 8
            SBOX-ABI-EXTRA-VALUE-COPY _SBOX-ABI-VALUE-META EXIT
        ENDOF

        SBOX-ABI-OP-V-NEW-NULL OF
            0 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-NEW-BOOL OF
            1 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-NEW-I64 OF
            1 1 SBOX-ABI-COST-VALUE-FIXED 2 0
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-NEW-BYTES OF
            2 1 SBOX-ABI-COST-VALUE-LENGTH 4 8
            SBOX-ABI-EXTRA-VALUE-COPY _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-NEW-UTF8 OF
            2 1 SBOX-ABI-COST-VALUE-LENGTH 4 8
            SBOX-ABI-EXTRA-VALUE-COPY _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-NEW-LIST OF
            2 1 SBOX-ABI-COST-VALUE-LENGTH 4 1
            SBOX-ABI-EXTRA-VALUE-OP _SBOX-ABI-VALUE-META EXIT
        ENDOF
        SBOX-ABI-OP-V-NEW-MAP OF
            2 1 SBOX-ABI-COST-VALUE-MAP 4 1
            SBOX-ABI-EXTRA-VALUE-MAP _SBOX-ABI-VALUE-META EXIT
        ENDOF
    ENDCASE
    0 0 0 0 0 0 0 0 SBOX-MACHINE-S-UNKNOWN-OPCODE ;

: _SBOX-ABI-DROP8  ( x0 x1 x2 x3 x4 x5 x6 x7 -- )
    2DROP 2DROP 2DROP 2DROP ;

: _SBOX-ABI-FIELD
    ( operand effect pop push kind base divisor extra status field -- value status )
    SWAP >R
    PICK >R
    _SBOX-ABI-DROP8
    R> R> ;

: SBOX-ABI-OPERAND@  ( opcode -- operand status )
    SBOX-ABI-METADATA 7 _SBOX-ABI-FIELD ;

: SBOX-ABI-EFFECT@  ( opcode -- effect status )
    SBOX-ABI-METADATA 6 _SBOX-ABI-FIELD ;

: SBOX-ABI-POP@  ( opcode -- pop status )
    SBOX-ABI-METADATA 5 _SBOX-ABI-FIELD ;

: SBOX-ABI-PUSH@  ( opcode -- push status )
    SBOX-ABI-METADATA 4 _SBOX-ABI-FIELD ;

: SBOX-ABI-COST-KIND@  ( opcode -- cost-kind status )
    SBOX-ABI-METADATA 3 _SBOX-ABI-FIELD ;

: SBOX-ABI-BASE-COST@  ( opcode -- base status )
    SBOX-ABI-METADATA 2 _SBOX-ABI-FIELD ;

: SBOX-ABI-COST-DIVISOR@  ( opcode -- divisor status )
    SBOX-ABI-METADATA 1 _SBOX-ABI-FIELD ;

: SBOX-ABI-EXTRA-CHARGE@  ( opcode -- extra status )
    SBOX-ABI-METADATA 0 _SBOX-ABI-FIELD ;

: SBOX-ABI-OPCODE-STATUS  ( opcode -- status )
    SBOX-ABI-METADATA >R _SBOX-ABI-DROP8 R> ;

: SBOX-ABI-OPCODE-SUPPORTED?  ( opcode -- flag )
    SBOX-ABI-OPCODE-STATUS SBOX-MACHINE-S-OK = ;
