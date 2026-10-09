\ =====================================================================
\  profile-codec.f - Canonical sandbox profile descriptor loader
\ =====================================================================
\  SBOX-PROFILE-LOAD decodes one canonical descriptor
\  (docs/sandbox/profile-format.md) into a sealed profile.  It checks the
\  byte and line grammar, the exact record order, every field's form and
\  range, ordering, uniqueness, cross-references and counts, and refuses
\  anything noncanonical without normalizing it.  A canonical descriptor
\  that names something this runtime does not implement is refused
\  separately.  Only then does it compute the domain-separated profile
\  digest and write the profile's seal.
\
\  The production pure-computation descriptor is embedded below byte for
\  byte.  It is also the vocabulary this runtime implements: its rules,
\  value tags, signatures, opcode records and outcome codes.  Another
\  descriptor may enable a subset of those signatures and opcodes, but
\  each record it carries must match the implemented one exactly.  A
\  descriptor carries no resource limit; those are the host's policy.
\
\  The caller's workspace keeps the last status and the offset of the
\  record that failed; every load wipes the rest of it before returning.
\ =====================================================================

PROVIDED akashic-sbx-pcodec

REQUIRE profile.f
REQUIRE digest.f

\ =====================================================================
\  Embedded production descriptor
\ =====================================================================

: _SPC-LINE,  ( address length -- )
    0 ?DO DUP I + C@ C, LOOP DROP 10 C, ;

CREATE _SPC-PURE
S" AKASHIC-SANDBOX-PROFILE" _SPC-LINE,
S" codec 1" _SPC-LINE,
S" profile org.akashic.sandbox.pure-compute" _SPC-LINE,
S" semantics org.akashic.sandbox.semantics.pure-compute" _SPC-LINE,
S" artifact-format 1" _SPC-LINE,
S" source-language org.akashic.sandbox.source" _SPC-LINE,
S" value-codec org.akashic.sandbox.value-tree-le" _SPC-LINE,
S" cell-bits 64" _SPC-LINE,
S" false 0" _SPC-LINE,
S" true -1" _SPC-LINE,
S" recursion 1" _SPC-LINE,
S" rule arithmetic.div-signed-truncate-zero" _SPC-LINE,
S" rule arithmetic.div-trap-min-neg1" _SPC-LINE,
S" rule arithmetic.div-trap-zero" _SPC-LINE,
S" rule arithmetic.wrap-add-sub-mul-neg-inc-dec-abs" _SPC-LINE,
S" rule boolean.false-zero-true-minus-one" _SPC-LINE,
S" rule branch.function-local-index" _SPC-LINE,
S" rule call.direct-table-index" _SPC-LINE,
S" rule determinism.no-clock-random-float" _SPC-LINE,
S" rule import.rw-staged-atomic" _SPC-LINE,
S" rule instruction.charge-before-effect" _SPC-LINE,
S" rule loop.checked-signed-step" _SPC-LINE,
S" rule loop.lexical-current-frame-r" _SPC-LINE,
S" rule map.find-exact-binary-search" _SPC-LINE,
S" rule map.raw-utf8-byte-order" _SPC-LINE,
S" rule memory.fixed-zeroed-readonly-prefix" _SPC-LINE,
S" rule result.disjoint-owned-output-transfer" _SPC-LINE,
S" rule value.canonical-tree-codec" _SPC-LINE,
S" value 0 NULL" _SPC-LINE,
S" value 1 BOOL" _SPC-LINE,
S" value 2 I64" _SPC-LINE,
S" value 3 BYTES" _SPC-LINE,
S" value 4 UTF8" _SPC-LINE,
S" value 5 LIST" _SPC-LINE,
S" value 6 MAP" _SPC-LINE,
S" signature 1 org.akashic.sandbox.signature.value-to-value 1 VALUE 1 VALUE" _SPC-LINE,
S" opcode 0 NOP 0 0 0 0 0 1 0 0" _SPC-LINE,
S" opcode 1 LIT.I64 1 0 0 1 0 1 0 0" _SPC-LINE,
S" opcode 2 BR 2 0 0 0 0 1 0 0" _SPC-LINE,
S" opcode 3 BR.ZERO 2 0 1 0 0 1 0 0" _SPC-LINE,
S" opcode 4 BR.NONZERO 2 0 1 0 0 1 0 0" _SPC-LINE,
S" opcode 5 CALL 3 1 0 0 1 2 8 0" _SPC-LINE,
S" opcode 6 RETURN 0 2 0 0 0 1 0 0" _SPC-LINE,
S" opcode 7 ABORT 4 0 0 0 0 1 0 0" _SPC-LINE,
S" opcode 8 LOCAL.GET 5 0 0 1 0 1 0 0" _SPC-LINE,
S" opcode 9 LOCAL.SET 5 0 1 0 0 1 0 0" _SPC-LINE,
S" opcode 10 LOCAL.TEE 5 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 11 LOOP.ENTER 6 0 2 0 0 2 0 0" _SPC-LINE,
S" opcode 12 LOOP.NEXT 7 0 0 0 0 2 0 0" _SPC-LINE,
S" opcode 13 LOOP.NEXT.BY 7 0 1 0 0 2 0 0" _SPC-LINE,
S" opcode 14 LOOP.INDEX 0 0 0 1 0 1 0 0" _SPC-LINE,
S" opcode 16 DROP 0 0 1 0 0 1 0 0" _SPC-LINE,
S" opcode 17 DUP 0 0 1 2 0 1 0 0" _SPC-LINE,
S" opcode 18 SWAP 0 0 2 2 0 1 0 0" _SPC-LINE,
S" opcode 19 OVER 0 0 2 3 0 1 0 0" _SPC-LINE,
S" opcode 20 ROT 0 0 3 3 0 1 0 0" _SPC-LINE,
S" opcode 21 NIP 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 22 TUCK 0 0 2 3 0 1 0 0" _SPC-LINE,
S" opcode 23 2DROP 0 0 2 0 0 1 0 0" _SPC-LINE,
S" opcode 24 2DUP 0 0 2 4 0 1 0 0" _SPC-LINE,
S" opcode 25 2SWAP 0 0 4 4 0 1 0 0" _SPC-LINE,
S" opcode 26 2OVER 0 0 4 6 0 1 0 0" _SPC-LINE,
S" opcode 32 I64.ADD 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 33 I64.SUB 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 34 I64.MUL 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 35 I64.DIV.S 0 0 2 1 0 2 0 0" _SPC-LINE,
S" opcode 36 I64.REM.S 0 0 2 1 0 2 0 0" _SPC-LINE,
S" opcode 37 I64.DIVMOD.S 0 0 2 2 0 3 0 0" _SPC-LINE,
S" opcode 38 I64.NEG 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 39 I64.ABS 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 40 I64.MIN.S 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 41 I64.MAX.S 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 42 I64.INC 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 43 I64.DEC 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 44 I64.EQ 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 45 I64.NE 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 46 I64.LT.S 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 47 I64.LE.S 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 48 I64.GT.S 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 49 I64.GE.S 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 50 I64.LT.U 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 51 I64.LE.U 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 52 I64.GT.U 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 53 I64.GE.U 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 54 I64.ZERO? 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 55 I64.NEGATIVE? 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 56 I64.POSITIVE? 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 57 I64.AND 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 58 I64.OR 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 59 I64.XOR 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 60 I64.NOT 0 0 1 1 0 1 0 0" _SPC-LINE,
S" opcode 61 I64.SHL 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 62 I64.SHR.U 0 0 2 1 0 1 0 0" _SPC-LINE,
S" opcode 64 MEM.SIZE 0 0 0 1 0 1 0 0" _SPC-LINE,
S" opcode 65 MEM.LOAD8.U 0 0 1 1 0 2 0 0" _SPC-LINE,
S" opcode 66 MEM.STORE8 0 0 2 0 0 2 0 0" _SPC-LINE,
S" opcode 67 MEM.LOAD64 0 0 1 1 0 2 0 0" _SPC-LINE,
S" opcode 68 MEM.STORE64 0 0 2 0 0 2 0 0" _SPC-LINE,
S" opcode 69 MEM.MOVE 0 0 3 0 2 2 8 2" _SPC-LINE,
S" opcode 70 MEM.FILL 0 0 3 0 2 2 8 2" _SPC-LINE,
S" opcode 96 V.TYPE 0 0 1 1 0 2 0 1" _SPC-LINE,
S" opcode 97 V.BOOL.GET 0 0 1 1 0 2 0 1" _SPC-LINE,
S" opcode 98 V.I64.GET 0 0 1 1 0 2 0 1" _SPC-LINE,
S" opcode 99 V.LEN 0 0 1 1 0 2 0 1" _SPC-LINE,
S" opcode 100 V.LIST.GET 0 0 2 1 0 3 0 1" _SPC-LINE,
S" opcode 101 V.MAP.KEY 0 0 2 1 0 3 0 1" _SPC-LINE,
S" opcode 102 V.MAP.VALUE 0 0 2 1 0 3 0 1" _SPC-LINE,
S" opcode 103 V.MAP.FIND 0 0 3 2 3 4 8 1" _SPC-LINE,
S" opcode 104 V.BLOB.COPY 0 0 4 0 2 4 8 3" _SPC-LINE,
S" opcode 112 V.NEW.NULL 0 0 0 1 0 2 0 1" _SPC-LINE,
S" opcode 113 V.NEW.BOOL 0 0 1 1 0 2 0 1" _SPC-LINE,
S" opcode 114 V.NEW.I64 0 0 1 1 0 2 0 1" _SPC-LINE,
S" opcode 115 V.NEW.BYTES 0 0 2 1 2 4 8 3" _SPC-LINE,
S" opcode 116 V.NEW.UTF8 0 0 2 1 2 4 8 3" _SPC-LINE,
S" opcode 117 V.NEW.LIST 0 0 2 1 4 4 8 1" _SPC-LINE,
S" opcode 118 V.NEW.MAP 0 0 2 1 5 4 8 1" _SPC-LINE,
S" result 0 OK" _SPC-LINE,
S" result 1 REQUEST_REJECTED" _SPC-LINE,
S" result 2 PROFILE_MISMATCH" _SPC-LINE,
S" result 3 VERIFICATION_REJECTED" _SPC-LINE,
S" result 4 GUEST_TRAP" _SPC-LINE,
S" result 5 RESOURCE_EXHAUSTED" _SPC-LINE,
S" result 6 OUTPUT_REJECTED" _SPC-LINE,
S" result 7 IMPORT_FAILURE" _SPC-LINE,
S" result 8 CANCELLED" _SPC-LINE,
S" result 9 HOST_FAILURE" _SPC-LINE,
S" request-detail 1 MISSING_DECLARATION_OR_ARTIFACT" _SPC-LINE,
S" request-detail 2 INVALID_DECLARATION" _SPC-LINE,
S" request-detail 3 ENTRY_NOT_EXPOSED" _SPC-LINE,
S" request-detail 4 INPUT_CODEC_INVALID" _SPC-LINE,
S" request-detail 5 INPUT_SCHEMA_MISMATCH" _SPC-LINE,
S" request-detail 6 ACTIVATION_LIMIT_MISMATCH" _SPC-LINE,
S" request-detail 7 IMPORT_BINDING_INVALID" _SPC-LINE,
S" request-detail 8 REQUEST_POLICY_REJECTED" _SPC-LINE,
S" profile-detail 1 UNKNOWN_PROFILE_ID" _SPC-LINE,
S" profile-detail 2 PROFILE_DESCRIPTOR_INVALID" _SPC-LINE,
S" profile-detail 3 ARTIFACT_PROFILE_DIGEST_MISMATCH" _SPC-LINE,
S" profile-detail 4 DECLARATION_PROFILE_MISMATCH" _SPC-LINE,
S" profile-detail 5 VERIFIED_PLAN_PROFILE_MISMATCH" _SPC-LINE,
S" profile-detail 6 RUNTIME_BINDING_PROFILE_MISMATCH" _SPC-LINE,
S" trap-detail 1 BAD_OPCODE" _SPC-LINE,
S" trap-detail 2 BAD_INSTRUCTION_POINTER" _SPC-LINE,
S" trap-detail 3 BAD_BRANCH_TARGET" _SPC-LINE,
S" trap-detail 4 BAD_CALL_TARGET" _SPC-LINE,
S" trap-detail 5 DATA_STACK_UNDERFLOW" _SPC-LINE,
S" trap-detail 6 CALL_STACK_UNDERFLOW" _SPC-LINE,
S" trap-detail 7 BAD_EXIT_SHAPE" _SPC-LINE,
S" trap-detail 8 DIVIDE_BY_ZERO" _SPC-LINE,
S" trap-detail 9 DIVIDE_OVERFLOW" _SPC-LINE,
S" trap-detail 10 SHIFT_RANGE" _SPC-LINE,
S" trap-detail 11 MEMORY_OUT_OF_BOUNDS" _SPC-LINE,
S" trap-detail 12 MEMORY_MISALIGNED" _SPC-LINE,
S" trap-detail 13 MEMORY_READ_ONLY" _SPC-LINE,
S" trap-detail 14 INVALID_VALUE_HANDLE" _SPC-LINE,
S" trap-detail 15 VALUE_TYPE_MISMATCH" _SPC-LINE,
S" trap-detail 16 VALUE_INDEX_RANGE" _SPC-LINE,
S" trap-detail 17 INVALID_UTF8" _SPC-LINE,
S" trap-detail 18 DUPLICATE_MAP_KEY" _SPC-LINE,
S" trap-detail 19 INVALID_RESULT_GRAPH" _SPC-LINE,
S" trap-detail 20 EXPLICIT_ABORT" _SPC-LINE,
S" trap-detail 21 LOCAL_INDEX_RANGE" _SPC-LINE,
S" trap-detail 22 INVALID_LENGTH" _SPC-LINE,
S" trap-detail 23 LOOP_STACK_UNDERFLOW" _SPC-LINE,
S" trap-detail 24 LOOP_ZERO_STEP" _SPC-LINE,
S" trap-detail 25 LOOP_ARITHMETIC_OVERFLOW" _SPC-LINE,
S" trap-detail 26 LOOP_STATE_INVALID" _SPC-LINE,
S" trap-detail 27 MAP_KEY_ORDER" _SPC-LINE,
S" trap-detail 28 SLICE_OVERLAP" _SPC-LINE,
S" resource-detail 1 INSTRUCTION_UNITS" _SPC-LINE,
S" resource-detail 2 VALUE_OPS" _SPC-LINE,
S" resource-detail 3 COPY_BYTES" _SPC-LINE,
S" resource-detail 4 DATA_STACK" _SPC-LINE,
S" resource-detail 5 CALL_FRAMES" _SPC-LINE,
S" resource-detail 6 LOOP_FRAMES" _SPC-LINE,
S" resource-detail 7 OUTPUT_ARENA_NODES" _SPC-LINE,
S" resource-detail 8 OUTPUT_ARENA_BYTES" _SPC-LINE,
S" resource-detail 9 OUTPUT_RESULT_NODES" _SPC-LINE,
S" resource-detail 10 OUTPUT_RESULT_BYTES" _SPC-LINE,
S" resource-detail 11 IMPORT_STAGING_BYTES" _SPC-LINE,
S" output-detail 1 OUTPUT_SCHEMA_MISMATCH" _SPC-LINE,
S" import-detail 1 DENIED" _SPC-LINE,
S" import-detail 2 UNAVAILABLE" _SPC-LINE,
S" import-detail 3 REJECTED" _SPC-LINE,
S" import-detail 4 RESULT_INVALID" _SPC-LINE,
S" cancel-detail 1 CALLER_CANCELLED" _SPC-LINE,
S" cancel-detail 2 CONTEXT_RELEASED" _SPC-LINE,
S" cancel-detail 3 DEADLINE" _SPC-LINE,
S" cancel-detail 4 HOST_SHUTDOWN" _SPC-LINE,
S" cancel-detail 5 ADAPTER_CANCELLED" _SPC-LINE,
S" host-detail 1 PREPARE_ALLOCATION" _SPC-LINE,
S" host-detail 2 INPUT_ADAPTER" _SPC-LINE,
S" host-detail 3 OUTPUT_ADAPTER" _SPC-LINE,
S" host-detail 4 WORKER_FAULT" _SPC-LINE,
S" host-detail 5 INTERNAL_INVARIANT" _SPC-LINE,
S" host-detail 6 IMPORT_ADAPTER_FAULT" _SPC-LINE,
S" host-detail 7 CLEANUP_FAULT" _SPC-LINE,
S" verify-detail 1 MALFORMED_ARTIFACT" _SPC-LINE,
S" verify-detail 2 LENGTH_OR_ARITHMETIC_OVERFLOW" _SPC-LINE,
S" verify-detail 3 INVALID_FUNCTION_OR_ENTRY" _SPC-LINE,
S" verify-detail 4 INVALID_OPCODE_OR_OPERAND" _SPC-LINE,
S" verify-detail 5 INVALID_TRANSFER_TARGET" _SPC-LINE,
S" verify-detail 6 INCONSISTENT_STACK_MERGE" _SPC-LINE,
S" verify-detail 7 INVALID_CALL_SIGNATURE" _SPC-LINE,
S" verify-detail 8 INVALID_LOCAL_INDEX" _SPC-LINE,
S" verify-detail 9 INVALID_LOOP_SHAPE" _SPC-LINE,
S" verify-detail 10 INVALID_IMPORT_DECLARATION" _SPC-LINE,
S" verify-detail 11 FORMAT_LIMIT_EXCEEDED" _SPC-LINE,
S" end 17 7 1 0 80" _SPC-LINE,
HERE _SPC-PURE - CONSTANT _SPC-PURE-U

: SBOX-PROFILE-PURE-DESCRIPTOR  ( -- address length )
    _SPC-PURE _SPC-PURE-U ;

\ Drops the first N bytes of a span.
: _SPC-SKIP  ( address length n -- address' length' )
    TUCK - >R + R> ;

\ The length of an embedded or already checked record, without its LF.
: _SPC-LINE-U  ( address -- length )
    0 BEGIN 2DUP + C@ 10 <> WHILE 1+ REPEAT NIP ;

: _SPC-PREFIX?  ( line-a line-u prefix-a prefix-u -- flag )
    ROT OVER < IF 2DROP DROP 0 EXIT THEN
    TUCK COMPARE 0= ;

\ The offset of the first embedded record that starts with PREFIX.
: _SPC-PURE-FIND  ( prefix-a prefix-u -- offset|-1 )
    0
    BEGIN DUP _SPC-PURE-U < WHILE
        _SPC-PURE OVER + DUP _SPC-LINE-U
        4 PICK 4 PICK _SPC-PREFIX? IF NIP NIP EXIT THEN
        _SPC-PURE OVER + _SPC-LINE-U + 1+
    REPEAT
    DROP 2DROP -1 ;

\ Where each group of the embedded descriptor begins.  It has no import
\ record, so its signatures run up to its opcodes.
S" rule "      _SPC-PURE-FIND CONSTANT _SPC-PURE-RULES
S" value "     _SPC-PURE-FIND CONSTANT _SPC-PURE-VALUES
S" signature " _SPC-PURE-FIND CONSTANT _SPC-PURE-SIGNATURES
S" opcode "    _SPC-PURE-FIND CONSTANT _SPC-PURE-OPCODES
S" result "    _SPC-PURE-FIND CONSTANT _SPC-PURE-OUTCOMES
S" end "       _SPC-PURE-FIND CONSTANT _SPC-PURE-END

\ =====================================================================
\  Record kinds, in their one permitted order
\ =====================================================================

: _SPC-WORD,  ( address length -- )
    DUP C, 0 ?DO DUP I + C@ C, LOOP DROP ;

CREATE _SPC-KEYWORDS
S" AKASHIC-SANDBOX-PROFILE" _SPC-WORD,
S" codec"           _SPC-WORD,   S" profile"         _SPC-WORD,
S" semantics"       _SPC-WORD,   S" artifact-format" _SPC-WORD,
S" source-language" _SPC-WORD,   S" value-codec"     _SPC-WORD,
S" cell-bits"       _SPC-WORD,   S" false"           _SPC-WORD,
S" true"            _SPC-WORD,   S" recursion"       _SPC-WORD,
S" rule"            _SPC-WORD,   S" value"           _SPC-WORD,
S" signature"       _SPC-WORD,   S" import"          _SPC-WORD,
S" opcode"          _SPC-WORD,   S" result"          _SPC-WORD,
S" request-detail"  _SPC-WORD,   S" profile-detail"  _SPC-WORD,
S" trap-detail"     _SPC-WORD,   S" resource-detail" _SPC-WORD,
S" output-detail"   _SPC-WORD,   S" import-detail"   _SPC-WORD,
S" cancel-detail"   _SPC-WORD,   S" host-detail"     _SPC-WORD,
S" verify-detail"   _SPC-WORD,   S" end"             _SPC-WORD,
0 C,

 0 CONSTANT _SPC-P-MAGIC
 1 CONSTANT _SPC-P-CODEC
 2 CONSTANT _SPC-P-PROFILE
 3 CONSTANT _SPC-P-SEMANTICS
 4 CONSTANT _SPC-P-ARTIFACT-FORMAT
 5 CONSTANT _SPC-P-SOURCE-LANGUAGE
 6 CONSTANT _SPC-P-VALUE-CODEC
 7 CONSTANT _SPC-P-CELL-BITS
 8 CONSTANT _SPC-P-FALSE
 9 CONSTANT _SPC-P-TRUE
10 CONSTANT _SPC-P-RECURSION
11 CONSTANT _SPC-P-RULE
12 CONSTANT _SPC-P-VALUE
13 CONSTANT _SPC-P-SIGNATURE
14 CONSTANT _SPC-P-IMPORT
15 CONSTANT _SPC-P-OPCODE
16 CONSTANT _SPC-P-RESULT
26 CONSTANT _SPC-P-END

: _SPC-PHASE-OF  ( keyword-a keyword-u -- phase|-1 )
    _SPC-KEYWORDS 0
    BEGIN OVER C@ WHILE
        3 PICK 3 PICK 3 PICK COUNT COMPARE 0= IF NIP NIP NIP EXIT THEN
        SWAP COUNT + SWAP 1+
    REPEAT
    2DROP 2DROP -1 ;

\ The fixed records and END occur once.  Every other kind is a group.
: _SPC-SINGLE?  ( phase -- flag )
    DUP _SPC-P-RULE < SWAP _SPC-P-END = OR ;

\ Groups that may be empty.  Rules and opcodes may not.
: _SPC-OPTIONAL?  ( phase -- flag )
    DUP _SPC-P-VALUE _SPC-P-OPCODE WITHIN
    SWAP _SPC-P-RESULT _SPC-P-END WITHIN OR ;

\ The ceilings profile-format.md fixes for every descriptor.
65536 CONSTANT _SPC-DESCRIPTOR-MAX
1024  CONSTANT _SPC-RECORDS-MAX

\ =====================================================================
\  Load workspace
\ =====================================================================

  0 CONSTANT _SPC-STATUS
  8 CONSTANT _SPC-ERROR
 16 CONSTANT _SPC-SCRATCH
 16 CONSTANT _SPC-DESC-A
 24 CONSTANT _SPC-DESC-U
 32 CONSTANT _SPC-PROFILE
 40 CONSTANT _SPC-POS
 48 CONSTANT _SPC-REC-A
 56 CONSTANT _SPC-REC-U
 64 CONSTANT _SPC-RECORDS
 72 CONSTANT _SPC-PHASE
 80 CONSTANT _SPC-KEY
 88 CONSTANT _SPC-PREV-A
 96 CONSTANT _SPC-PREV-U
104 CONSTANT _SPC-UNSUPPORTED
112 CONSTANT _SPC-CURSOR
120 CONSTANT _SPC-OPCODE-80
128 CONSTANT _SPC-RULES-A
144 CONSTANT _SPC-VALUES-A
160 CONSTANT _SPC-SIGS-A
176 CONSTANT _SPC-OPCODES-A
192 CONSTANT _SPC-OUTCOMES-A
208 CONSTANT _SPC-COUNTS
248 CONSTANT _SPC-T
312 CONSTANT _SPC-DIGEST-WORK
_SPC-DIGEST-WORK SBOX-DIGEST-WORKSPACE-SIZE +
    CONSTANT SBOX-PROFILE-LOAD-WORKSPACE-SIZE

: _SPC.STATUS       ( ws -- a ) _SPC-STATUS + ;
: _SPC.ERROR        ( ws -- a ) _SPC-ERROR + ;
: _SPC.DESC-A       ( ws -- a ) _SPC-DESC-A + ;
: _SPC.DESC-U       ( ws -- a ) _SPC-DESC-U + ;
: _SPC.PROFILE      ( ws -- a ) _SPC-PROFILE + ;
: _SPC.POS          ( ws -- a ) _SPC-POS + ;
: _SPC.REC-A        ( ws -- a ) _SPC-REC-A + ;
: _SPC.REC-U        ( ws -- a ) _SPC-REC-U + ;
: _SPC.RECORDS      ( ws -- a ) _SPC-RECORDS + ;
: _SPC.PHASE        ( ws -- a ) _SPC-PHASE + ;
: _SPC.KEY          ( ws -- a ) _SPC-KEY + ;
: _SPC.PREV-A       ( ws -- a ) _SPC-PREV-A + ;
: _SPC.PREV-U       ( ws -- a ) _SPC-PREV-U + ;
: _SPC.UNSUPPORTED  ( ws -- a ) _SPC-UNSUPPORTED + ;
: _SPC.CURSOR       ( ws -- a ) _SPC-CURSOR + ;
: _SPC.OPCODE-80    ( ws -- a ) _SPC-OPCODE-80 + ;
: _SPC.RULES-A      ( ws -- a ) _SPC-RULES-A + ;
: _SPC.VALUES-A     ( ws -- a ) _SPC-VALUES-A + ;
: _SPC.SIGS-A       ( ws -- a ) _SPC-SIGS-A + ;
: _SPC.SIGS-Z       ( ws -- a ) _SPC-SIGS-A 8 + + ;
: _SPC.OPCODES-A    ( ws -- a ) _SPC-OPCODES-A + ;
: _SPC.OUTCOMES-A   ( ws -- a ) _SPC-OUTCOMES-A + ;
: _SPC.COUNTS       ( ws -- a ) _SPC-COUNTS + ;
: _SPC.T            ( index ws -- a ) SWAP 8 * + _SPC-T + ;
: _SPC.DIGEST-WORK  ( ws -- a ) _SPC-DIGEST-WORK + ;

: _SPC-PROFILE@  ( ws -- profile ) _SPC.PROFILE @ ;

: _SPC-REC$  ( ws -- address length )
    DUP _SPC.REC-A @ SWAP _SPC.REC-U @ ;

\ Records the current record as something this runtime does not
\ implement.  The lowest such offset is reported once the whole
\ descriptor has proved canonical.
: _SPC-MARK-AT  ( offset ws -- )
    _SPC.UNSUPPORTED DUP @ DUP 0< IF DROP ! EXIT THEN
    2 PICK > IF ! ELSE 2DROP THEN ;

: _SPC-MARK  ( ws -- )
    DUP _SPC.ERROR @ SWAP _SPC-MARK-AT ;

\ =====================================================================
\  Records and fields
\ =====================================================================

\ Reads the record at POS: checks its bytes, sets REC-A and REC-U, and
\ moves POS past its LF.  ERROR names the record from here on.
: _SPC-NEXT-RECORD  ( ws -- status )
    >R
    R@ _SPC.POS @ R@ _SPC.ERROR !
    R@ _SPC.DESC-A @ R@ _SPC.POS @ + R@ _SPC.REC-A !
    R@ _SPC.DESC-U @ R@ _SPC.POS @ -
    0
    BEGIN
        2DUP > 0= IF
            2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
        THEN
        R@ _SPC.REC-A @ OVER + C@
        DUP 10 <>
    WHILE
        DUP 32 < SWAP 126 > OR IF
            2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
        THEN
        1+
    REPEAT
    DROP NIP
    DUP R@ _SPC.REC-U !
    1+ R@ _SPC.POS +!
    1 R@ _SPC.RECORDS +!
    R> DROP SBOX-PROFILE-S-OK ;

\ No empty record, no leading or trailing space, and no doubled space.
: _SPC-SPACING?  ( ws -- flag )
    _SPC-REC$
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 32 = IF 2DROP 0 EXIT THEN
    2DUP + 1- C@ 32 = IF 2DROP 0 EXIT THEN
    1- 0 ?DO
        DUP I + C@ 32 = OVER I + 1+ C@ 32 = AND IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _SPC-ARITY  ( ws -- fields )
    _SPC-REC$
    1 -ROT 0 ?DO DUP I + C@ 32 = IF SWAP 1+ SWAP THEN LOOP DROP ;

\ The INDEX-th field of the current record.  INDEX is below its arity.
: _SPC-FIELD  ( index ws -- address length )
    _SPC-REC$ OVER + >R
    SWAP 0 ?DO
        BEGIN DUP C@ 32 <> WHILE 1+ REPEAT 1+
    LOOP
    DUP BEGIN DUP R@ < IF DUP C@ 32 <> ELSE 0 THEN WHILE 1+ REPEAT
    OVER - R> DROP ;

: _SPC-INDEX  ( address length char -- index )
    SWAP DUP >R 0 ?DO
        OVER I + C@ OVER = IF 2DROP I UNLOOP R> DROP EXIT THEN
    LOOP
    2DROP R> ;

\ The second field of an embedded or already checked record.
: _SPC-SECOND  ( line-a line-u -- field-a field-u )
    2DUP 32 _SPC-INDEX 1+ _SPC-SKIP
    2DUP 32 _SPC-INDEX NIP ;

\ =====================================================================
\  Field forms
\ =====================================================================

0x1999999999999999 CONSTANT _SPC-U64-TENTH
0x7FFFFFFFFFFFFFFF CONSTANT _SPC-I64-MAX

\ Base-ten digits with no sign and no leading zero unless the value is
\ exactly 0, within 64 unsigned bits.
: _SPC-U64  ( address length -- value flag )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    DUP 1 > IF OVER C@ [CHAR] 0 = IF 2DROP 0 0 EXIT THEN THEN
    0 -ROT 0 ?DO
        DUP I + C@ [CHAR] 0 -
        DUP 0 10 WITHIN 0= IF 2DROP DROP 0 0 UNLOOP EXIT THEN
        ROT
        DUP _SPC-U64-TENTH U> IF DROP 2DROP 0 0 UNLOOP EXIT THEN
        DUP _SPC-U64-TENTH = 2 PICK 5 > AND IF
            DROP 2DROP 0 0 UNLOOP EXIT
        THEN
        10 * + SWAP
    LOOP
    DROP -1 ;

: _SPC-UNSIGNED  ( address length max -- value flag )
    >R _SPC-U64 DUP IF DROP DUP R@ U> 0= THEN R> DROP ;

\ A minus sign only for a negative value, and no redundant zero.
: _SPC-I64  ( address length -- value flag )
    DUP 0= IF 2DROP 0 0 EXIT THEN
    OVER C@ [CHAR] - = IF
        1 _SPC-SKIP _SPC-U64 0= IF 0 EXIT THEN
        DUP 0= IF 0 EXIT THEN
        DUP _SPC-I64-MAX 1+ U> IF 0 EXIT THEN
        NEGATE -1 EXIT
    THEN
    _SPC-U64 0= IF 0 EXIT THEN
    DUP _SPC-I64-MAX U> IF 0 EXIT THEN
    -1 ;

: _SPC-FIELD-U  ( index max ws -- value flag )
    >R SWAP R> _SPC-FIELD ROT _SPC-UNSIGNED ;

: _SPC-ALPHA?  ( c -- flag )
    DUP [CHAR] A [CHAR] Z 1+ WITHIN
    SWAP [CHAR] a [CHAR] z 1+ WITHIN OR ;
: _SPC-UPPER?  ( c -- flag )  [CHAR] A [CHAR] Z 1+ WITHIN ;
: _SPC-DIGIT?  ( c -- flag )  [CHAR] 0 [CHAR] 9 1+ WITHIN ;

\ [A-Za-z][A-Za-z0-9._-]{0,126}
: _SPC-IDENT?  ( address length -- flag )
    DUP 1 SBOX-PROFILE-IDENTIFIER-MAX 1+ WITHIN 0= IF 2DROP 0 EXIT THEN
    OVER C@ _SPC-ALPHA? 0= IF 2DROP 0 EXIT THEN
    1 _SPC-SKIP 0 ?DO
        DUP I + C@
        DUP _SPC-ALPHA? OVER _SPC-DIGIT? OR
        OVER [CHAR] . = OR OVER [CHAR] _ = OR SWAP [CHAR] - = OR
        0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ [A-Z0-9][A-Z0-9.?_-]{0,62}
: _SPC-OPNAME?  ( address length -- flag )
    DUP 1 64 WITHIN 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP _SPC-UPPER? SWAP _SPC-DIGIT? OR 0= IF 2DROP 0 EXIT THEN
    1 _SPC-SKIP 0 ?DO
        DUP I + C@
        DUP _SPC-UPPER? OVER _SPC-DIGIT? OR
        OVER [CHAR] . = OR OVER [CHAR] ? = OR
        OVER [CHAR] _ = OR SWAP [CHAR] - = OR
        0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SPC-ATOM?  ( address length -- flag )
    2DUP S" I64"      COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" BOOL"     COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" VALUE"    COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" SLICE.RO" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" SLICE.RW" COMPARE 0= IF 2DROP -1 EXIT THEN
    DUP 7 > 0= IF 2DROP 0 EXIT THEN
    OVER 7 S" OPAQUE." COMPARE IF 2DROP 0 EXIT THEN
    7 _SPC-SKIP 65535 _SPC-UNSIGNED SWAP 0<> AND ;

\ COUNT comma-separated machine kinds, or "-" when COUNT is zero.
: _SPC-KINDS?  ( address length count -- flag )
    DUP 0= IF DROP S" -" COMPARE 0= EXIT THEN
    >R
    BEGIN
        2DUP [CHAR] , _SPC-INDEX
        >R OVER R@ _SPC-ATOM? 0= IF 2DROP R> DROP R> DROP 0 EXIT THEN
        R> R> 1- >R
        2DUP = IF DROP 2DROP R> 0= EXIT THEN
        1+ _SPC-SKIP
        R@ 0= IF 2DROP R> DROP 0 EXIT THEN
    AGAIN ;

\ A group's numeric keys strictly increase.  KEY is -1 at a group's start.
: _SPC-KEY!  ( key ws -- flag )
    2DUP _SPC.KEY @ > IF _SPC.KEY ! -1 ELSE 2DROP 0 THEN ;

\ =====================================================================
\  Fixed records
\ =====================================================================

: _SPC-R-MAGIC  ( ws -- status )
    _SPC-ARITY 1 = IF SBOX-PROFILE-S-OK ELSE SBOX-PROFILE-S-DESCRIPTOR THEN ;

\ One unsigned field no greater than MAX.  Any value but EXPECTED names a
\ codec, format or machine this runtime does not implement.
: _SPC-R-FIXED-U  ( expected max ws -- status )
    >R
    R@ _SPC-ARITY 2 <> IF 2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 SWAP R@ _SPC-FIELD-U 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    <> IF R@ _SPC-MARK THEN
    R> DROP SBOX-PROFILE-S-OK ;

: _SPC-R-FIXED-I  ( expected ws -- status )
    >R
    R@ _SPC-ARITY 2 <> IF DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 R@ _SPC-FIELD _SPC-I64 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    <> IF R@ _SPC-MARK THEN
    R> DROP SBOX-PROFILE-S-OK ;

: _SPC-R-FIXED-ID  ( expected-a expected-u ws -- status )
    >R
    R@ _SPC-ARITY 2 <> IF 2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 R@ _SPC-FIELD 2DUP _SPC-IDENT? 0= IF
        2DROP 2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    COMPARE IF R@ _SPC-MARK THEN
    R> DROP SBOX-PROFILE-S-OK ;

: _SPC-R-PROFILE  ( ws -- status )
    >R
    R@ _SPC-ARITY 2 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 R@ _SPC-FIELD 2DUP _SPC-IDENT? 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    DUP R@ _SPC-PROFILE@ _SBP.ID-U !
    R@ _SPC-PROFILE@ _SBP.ID SWAP MOVE
    R> DROP SBOX-PROFILE-S-OK ;

: _SPC-R-SEMANTICS  ( ws -- status )
    >R
    R@ _SPC-ARITY 2 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 R@ _SPC-FIELD 2DUP _SPC-IDENT? 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    2DUP S" org.akashic.sandbox.semantics.pure-compute" COMPARE 0= IF
        2DROP
        SBOX-PROFILE-SEMANTICS-PURE R@ _SPC-PROFILE@ _SBP.SEMANTICS !
        R> DROP SBOX-PROFILE-S-OK EXIT
    THEN
    \ Scalar qualification also enables signature zero.
    S" org.akashic.sandbox.semantics.scalar-qualification" COMPARE 0= IF
        SBOX-PROFILE-SEMANTICS-SCALAR-QUALIFICATION
            R@ _SPC-PROFILE@ _SBP.SEMANTICS !
        1 R@ _SPC-PROFILE@ _SBP.SIGNATURES DUP @ ROT OR SWAP !
    ELSE
        R@ _SPC-MARK
    THEN
    R> DROP SBOX-PROFILE-S-OK ;

\ =====================================================================
\  Rule, value, signature and import records
\ =====================================================================

\ Rules strictly increase by unsigned bytes.  The set itself is compared
\ with the implemented one once the descriptor has proved canonical.
: _SPC-R-RULE  ( ws -- status )
    >R
    R@ _SPC-ARITY 2 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 R@ _SPC-FIELD 2DUP _SPC-IDENT? 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC.PREV-U @ IF
        2DUP R@ _SPC.PREV-A @ R@ _SPC.PREV-U @ COMPARE 0> 0= IF
            2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
        THEN
    THEN
    R@ _SPC.PREV-U ! R@ _SPC.PREV-A !
    R> DROP SBOX-PROFILE-S-OK ;

: _SPC-R-VALUE  ( ws -- status )
    >R
    R@ _SPC-ARITY 3 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 65535 R@ _SPC-FIELD-U 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-KEY! 0= IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    2 R@ _SPC-FIELD _SPC-IDENT? 0= IF
        R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R> DROP SBOX-PROFILE-S-OK ;

\ Is LINE one of the embedded records from FROM up to TO?
: _SPC-PURE-HAS?  ( line-a line-u from to -- flag )
    SWAP
    BEGIN 2DUP > WHILE
        _SPC-PURE OVER + DUP _SPC-LINE-U
        5 PICK 5 PICK COMPARE 0= IF 2DROP 2DROP -1 EXIT THEN
        _SPC-PURE OVER + _SPC-LINE-U + 1+
    REPEAT
    2DROP 2DROP 0 ;

: _SPC-R-SIGNATURE  ( ws -- status )
    >R
    R@ _SPC-ARITY 7 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 0xFFFFFFFF R@ _SPC-FIELD-U 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    DUP R@ _SPC-KEY! 0= IF DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    2 R@ _SPC-FIELD _SPC-IDENT? 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    3 65535 R@ _SPC-FIELD-U 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    4 R@ _SPC-FIELD ROT _SPC-KINDS? 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    5 65535 R@ _SPC-FIELD-U 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    6 R@ _SPC-FIELD ROT _SPC-KINDS? 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-REC$ _SPC-PURE-SIGNATURES _SPC-PURE-OPCODES _SPC-PURE-HAS? IF
        1 SWAP LSHIFT
        R@ _SPC-PROFILE@ _SBP.SIGNATURES DUP @ ROT OR SWAP !
    ELSE
        DROP R@ _SPC-MARK
    THEN
    R> DROP SBOX-PROFILE-S-OK ;

\ Is ID the identifier of a signature record already read?
: _SPC-SIGNATURE-LISTED?  ( id ws -- flag )
    >R
    R@ _SPC.SIGS-A @ DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    BEGIN DUP R@ _SPC.SIGS-Z @ < WHILE
        R@ _SPC.DESC-A @ OVER + DUP _SPC-LINE-U _SPC-SECOND
        _SPC-U64 DROP 2 PICK = IF 2DROP R> DROP -1 EXIT THEN
        R@ _SPC.DESC-A @ OVER + _SPC-LINE-U + 1+
    REPEAT
    2DROP R> DROP 0 ;

\ The import grammar is checked in full.  This runtime has no import
\ adapter, so any import is a feature it does not implement.
: _SPC-R-IMPORT  ( ws -- status )
    >R
    R@ _SPC-ARITY 6 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 0xFFFFFFFF R@ _SPC-FIELD-U 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-KEY! 0= IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    2 R@ _SPC-FIELD _SPC-IDENT? 0= IF
        R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    3 0xFFFFFFFF R@ _SPC-FIELD-U 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-SIGNATURE-LISTED? 0= IF
        R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    4 3 R@ _SPC-FIELD-U NIP 0= IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    5 -1 R@ _SPC-FIELD-U NIP 0= IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    R@ _SPC-MARK
    R> DROP SBOX-PROFILE-S-OK ;

\ =====================================================================
\  Opcode records
\ =====================================================================

\ Operand, effect, pop, push, cost kind, base, divisor and extra charge,
\ parsed into T0 through T7.
: _SPC-OPCODE-FIELDS  ( ws -- flag )
    >R
    3 8          R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        0 R@ _SPC.T !
    4 3          R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        1 R@ _SPC.T !
    5 255        R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        2 R@ _SPC.T !
    6 255        R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        3 R@ _SPC.T !
    7 6          R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        4 R@ _SPC.T !
    8 -1         R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        5 R@ _SPC.T !
    9 0xFFFFFFFF R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        6 R@ _SPC.T !
    10 4         R@ _SPC-FIELD-U 0= IF DROP R> DROP 0 EXIT THEN
        7 R@ _SPC.T !
    R> DROP -1 ;

: _SPC-T@  ( index ws -- value ) _SPC.T @ ;

\ The relations between enums that hold for every opcode record.
: _SPC-OPCODE-SHAPE?  ( ws -- flag )
    >R
    5 R@ _SPC-T@ 0= IF R> DROP 0 EXIT THEN
    1 R@ _SPC-T@ IF
        2 R@ _SPC-T@ 3 R@ _SPC-T@ OR IF R> DROP 0 EXIT THEN
    THEN
    4 R@ _SPC-T@ DUP 0= SWAP 6 = OR IF
        6 R@ _SPC-T@ IF R> DROP 0 EXIT THEN
    ELSE
        6 R@ _SPC-T@ 8 <> IF R> DROP 0 EXIT THEN
    THEN
    4 R@ _SPC-T@ 6 = IF
        5 R@ _SPC-T@ 1 = 0 R@ _SPC-T@ 8 = AND 1 R@ _SPC-T@ 3 = AND
        R> DROP EXIT
    THEN
    R> DROP -1 ;

: _SPC-IMPORT-CALL$  ( -- address length )
    S" opcode 80 IMPORT.CALL 8 3 0 0 6 1 0 4" ;

: _SPC-PURE-CODE  ( offset -- code )
    _SPC-PURE + DUP _SPC-LINE-U _SPC-SECOND _SPC-U64 DROP ;

\ The implemented record for CODE.  The cursor walks the embedded
\ opcodes once per descriptor, because both are in code order.
: _SPC-PURE-OPCODE  ( code ws -- line-a line-u | 0 0 )
    >R
    BEGIN
        R@ _SPC.CURSOR @ _SPC-PURE-OUTCOMES < 0= IF
            DROP R> DROP 0 0 EXIT
        THEN
        R@ _SPC.CURSOR @ _SPC-PURE-CODE OVER <
    WHILE
        _SPC-PURE R@ _SPC.CURSOR @ + _SPC-LINE-U 1+ R@ _SPC.CURSOR +!
    REPEAT
    R@ _SPC.CURSOR @ _SPC-PURE-CODE <> IF R> DROP 0 0 EXIT THEN
    _SPC-PURE R@ _SPC.CURSOR @ + DUP _SPC-LINE-U
    R> DROP ;

: _SPC-R-OPCODE  ( ws -- status )
    >R
    R@ _SPC-ARITY 11 <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 65535 R@ _SPC-FIELD-U 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    DUP R@ _SPC-KEY! 0= IF DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    2 R@ _SPC-FIELD _SPC-OPNAME? 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-OPCODE-FIELDS 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-OPCODE-SHAPE? 0= IF
        DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    \ IMPORT.CALL has exactly one form, and only beside imports.
    DUP SBOX-MACHINE-OP-IMPORT-CALL = IF
        DROP R@ _SPC-REC$ _SPC-IMPORT-CALL$ COMPARE IF
            R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
        THEN
        -1 R@ _SPC.OPCODE-80 !
        R> DROP SBOX-PROFILE-S-OK EXIT
    THEN
    DUP R@ _SPC-PURE-OPCODE
    ?DUP IF R@ _SPC-REC$ COMPARE 0= ELSE DROP 0 THEN
    IF
        R@ _SPC-PROFILE@ _SBP-OPCODE-CELL OVER @ OR SWAP !
    ELSE
        DROP R@ _SPC-MARK
    THEN
    R> DROP SBOX-PROFILE-S-OK ;

\ =====================================================================
\  Outcome and end records
\ =====================================================================

\ Detail code zero is reserved for OK and never listed.
: _SPC-R-OUTCOME  ( detail? ws -- status )
    >R
    R@ _SPC-ARITY 3 <> IF DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1 65535 R@ _SPC-FIELD-U 0= IF
        2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    DUP 0= ROT AND IF DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    R@ _SPC-KEY! 0= IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    2 R@ _SPC-FIELD _SPC-IDENT? 0= IF
        R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R> DROP SBOX-PROFILE-S-OK ;

\ The five counts, in COUNTS order, match the records exactly.
: _SPC-R-END  ( ws -- status )
    DUP _SPC-ARITY 6 <> IF DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    5 0 DO
        I 1+ 65535 2 PICK _SPC-FIELD-U 0= IF
            2DROP DROP UNLOOP SBOX-PROFILE-S-DESCRIPTOR EXIT
        THEN
        OVER _SPC.COUNTS I 8 * + @ <> IF
            DROP UNLOOP SBOX-PROFILE-S-DESCRIPTOR EXIT
        THEN
    LOOP
    DROP SBOX-PROFILE-S-OK ;

\ =====================================================================
\  Record order
\ =====================================================================

\ Moves to PHASE.  A fixed record occurs once; a group continues until a
\ later kind begins; and every kind skipped on the way is a group that
\ may be empty.
: _SPC-ENTER  ( phase ws -- status )
    >R
    R@ _SPC.PHASE @
    2DUP = IF
        DROP _SPC-SINGLE? IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
        R> DROP SBOX-PROFILE-S-OK EXIT
    THEN
    2DUP < IF 2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    1+
    BEGIN 2DUP > WHILE
        DUP _SPC-OPTIONAL? 0= IF 2DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
        1+
    REPEAT
    DROP
    DUP R@ _SPC.PHASE !
    -1 R@ _SPC.KEY !
    0 R@ _SPC.PREV-U !
    DUP _SPC-P-OPCODE = IF _SPC-PURE-OPCODES R@ _SPC.CURSOR ! THEN
    DROP R> DROP SBOX-PROFILE-S-OK ;

: _SPC-COUNT@  ( index ws -- count )
    _SPC.COUNTS SWAP 8 * + @ ;

: _SPC-DISPATCH  ( phase ws -- status )
    >R
    CASE
        _SPC-P-MAGIC OF R@ _SPC-R-MAGIC ENDOF
        _SPC-P-CODEC OF 1 65535 R@ _SPC-R-FIXED-U ENDOF
        _SPC-P-PROFILE OF R@ _SPC-R-PROFILE ENDOF
        _SPC-P-SEMANTICS OF R@ _SPC-R-SEMANTICS ENDOF
        _SPC-P-ARTIFACT-FORMAT OF 1 65535 R@ _SPC-R-FIXED-U ENDOF
        _SPC-P-SOURCE-LANGUAGE OF
            S" org.akashic.sandbox.source" R@ _SPC-R-FIXED-ID
        ENDOF
        _SPC-P-VALUE-CODEC OF
            S" org.akashic.sandbox.value-tree-le" R@ _SPC-R-FIXED-ID
        ENDOF
        _SPC-P-CELL-BITS OF 64 65535 R@ _SPC-R-FIXED-U ENDOF
        _SPC-P-FALSE OF 0 R@ _SPC-R-FIXED-I ENDOF
        _SPC-P-TRUE OF -1 R@ _SPC-R-FIXED-I ENDOF
        _SPC-P-RECURSION OF 1 1 R@ _SPC-R-FIXED-U ENDOF
        _SPC-P-RULE OF R@ _SPC-R-RULE ENDOF
        _SPC-P-VALUE OF R@ _SPC-R-VALUE ENDOF
        _SPC-P-SIGNATURE OF R@ _SPC-R-SIGNATURE ENDOF
        _SPC-P-IMPORT OF R@ _SPC-R-IMPORT ENDOF
        _SPC-P-OPCODE OF R@ _SPC-R-OPCODE ENDOF
        _SPC-P-RESULT OF 0 R@ _SPC-R-OUTCOME ENDOF
        _SPC-P-END OF R@ _SPC-R-END ENDOF
        \ Every other kind is a detail group.
        -1 R@ _SPC-R-OUTCOME SWAP
    ENDCASE
    R> DROP ;

\ Widens the span at SPAN (start, then end) to take in the current record.
: _SPC-SPAN+  ( span ws -- )
    >R
    DUP @ 0< IF R@ _SPC.ERROR @ OVER ! THEN
    R@ _SPC.POS @ SWAP 8 + !
    R> DROP ;

: _SPC-TALLY  ( phase ws -- )
    >R
    DUP _SPC-P-RULE _SPC-P-RESULT WITHIN IF
        1 OVER _SPC-P-RULE - 8 * R@ _SPC.COUNTS + +!
    THEN
    DUP _SPC-P-RULE = IF R@ _SPC.RULES-A R@ _SPC-SPAN+ THEN
    DUP _SPC-P-VALUE = IF R@ _SPC.VALUES-A R@ _SPC-SPAN+ THEN
    DUP _SPC-P-SIGNATURE = IF R@ _SPC.SIGS-A R@ _SPC-SPAN+ THEN
    DUP _SPC-P-OPCODE = IF R@ _SPC.OPCODES-A R@ _SPC-SPAN+ THEN
    DUP _SPC-P-RESULT _SPC-P-END WITHIN IF
        R@ _SPC.OUTCOMES-A R@ _SPC-SPAN+
    THEN
    DROP R> DROP ;

: _SPC-STEP  ( ws -- status )
    >R
    R@ _SPC-NEXT-RECORD ?DUP IF R> DROP EXIT THEN
    R@ _SPC.RECORDS @ _SPC-RECORDS-MAX > IF
        R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC-SPACING? 0= IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    0 R@ _SPC-FIELD _SPC-PHASE-OF
    DUP 0< IF DROP R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    DUP R@ _SPC-ENTER ?DUP IF NIP R> DROP EXIT THEN
    DUP R@ _SPC-DISPATCH ?DUP IF NIP R> DROP EXIT THEN
    R@ _SPC-TALLY
    R> DROP SBOX-PROFILE-S-OK ;

\ =====================================================================
\  Whole-descriptor checks
\ =====================================================================

\ The descriptor's records in SPAN equal the embedded records from FROM
\ up to TO.  An empty span equals only an empty embedded group.
: _SPC-SAME-SPAN?  ( span from to ws -- flag )
    >R
    OVER - >R _SPC-PURE + R>
    ROT DUP @ DUP 0< IF
        2DROP NIP 0= R> DROP EXIT
    THEN
    SWAP 8 + @ OVER -
    SWAP R> _SPC.DESC-A @ + SWAP
    COMPARE 0= ;

\ Marks SPAN unsupported unless it is exactly the implemented group.  An
\ empty span is reported at FALLBACK.
: _SPC-IMPLEMENTED  ( span from to fallback ws -- )
    >R >R
    2 PICK -ROT
    R> R@ SWAP >R
    _SPC-SAME-SPAN? IF DROP R> DROP R> DROP EXIT THEN
    @ DUP 0< IF DROP R@ THEN
    R> DROP R@ _SPC-MARK-AT
    R> DROP ;

\ Runs once the end record has been read.  The rule, value and outcome
\ groups must be exactly the implemented ones.
: _SPC-FINISH  ( ws -- status )
    >R
    R@ _SPC.PHASE @ _SPC-P-END <> IF R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT THEN
    \ Imports and IMPORT.CALL come together or not at all.
    3 R@ _SPC-COUNT@ 0<> R@ _SPC.OPCODE-80 @ 0<> <> IF
        R@ _SPC.OPCODES-A @ R@ _SPC.ERROR !
        R> DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    R@ _SPC.RULES-A _SPC-PURE-RULES _SPC-PURE-VALUES
        R@ _SPC.RULES-A @ R@ _SPC-IMPLEMENTED
    R@ _SPC.VALUES-A _SPC-PURE-VALUES _SPC-PURE-SIGNATURES
        R@ _SPC.RULES-A 8 + @ R@ _SPC-IMPLEMENTED
    R@ _SPC.OUTCOMES-A _SPC-PURE-OUTCOMES _SPC-PURE-END
        R@ _SPC.ERROR @ R@ _SPC-IMPLEMENTED
    R@ _SPC.UNSUPPORTED @ DUP 0< IF DROP R> DROP SBOX-PROFILE-S-OK EXIT THEN
    R@ _SPC.ERROR !
    R> DROP SBOX-PROFILE-S-UNSUPPORTED ;

\ =====================================================================
\  Public loader
\ =====================================================================

: _SPC-SPAN-STATUS  ( address length -- status )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP SBOX-PROFILE-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _SBOX-PROFILE-CALLER>STATUS ;

: _SPC-WORKSPACE-STATUS  ( workspace -- status )
    DUP 0= IF DROP SBOX-PROFILE-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SBOX-PROFILE-S-INVALID EXIT THEN
    SBOX-PROFILE-LOAD-WORKSPACE-SIZE _SPC-SPAN-STATUS ;

\ Wipes everything but the status and the failing offset.
: _SPC-SCRUB  ( ws -- )
    _SPC-SCRATCH + SBOX-PROFILE-LOAD-WORKSPACE-SIZE _SPC-SCRATCH - 0 FILL ;

: _SPC-FAIL  ( status ws -- status )
    >R
    R@ _SPC-PROFILE@ SBOX-PROFILE-SIZE 0 FILL
    DUP R@ _SPC.STATUS !
    R@ _SPC-SCRUB
    R> DROP ;

\ Decodes DESCRIPTOR into PROFILE.  Arguments that cannot be admitted
\ leave the profile and the workspace untouched.  Once they are admitted
\ the profile is cleared first and sealed only after every check and the
\ digest succeed, so a failure leaves it invalid.
: SBOX-PROFILE-LOAD  ( descriptor descriptor-u profile workspace -- status )
    DUP _SPC-WORKSPACE-STATUS ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    OVER _SBOX-PROFILE-SPAN-STATUS ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    2 PICK 1 _SPC-DESCRIPTOR-MAX 1+ WITHIN 0= IF
        2DROP 2DROP SBOX-PROFILE-S-DESCRIPTOR EXIT
    THEN
    3 PICK 0= IF 2DROP 2DROP SBOX-PROFILE-S-INVALID EXIT THEN
    3 PICK 3 PICK _SPC-SPAN-STATUS ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    3 PICK 3 PICK 3 PICK SBOX-PROFILE-SIZE MSPAN-OVERLAP?
    4 PICK 4 PICK 3 PICK SBOX-PROFILE-LOAD-WORKSPACE-SIZE MSPAN-OVERLAP? OR
    2 PICK SBOX-PROFILE-SIZE 3 PICK SBOX-PROFILE-LOAD-WORKSPACE-SIZE
        MSPAN-OVERLAP? OR
    IF 2DROP 2DROP SBOX-PROFILE-S-ALIAS EXIT THEN

    >R
    DUP SBOX-PROFILE-SIZE 0 FILL
    R@ SBOX-PROFILE-LOAD-WORKSPACE-SIZE 0 FILL
    R@ _SPC.PROFILE !
    R@ _SPC.DESC-U ! R@ _SPC.DESC-A !
    -1 R@ _SPC.ERROR !
    -1 R@ _SPC.PHASE !
    -1 R@ _SPC.KEY !
    -1 R@ _SPC.UNSUPPORTED !
    -1 R@ _SPC.RULES-A !
    -1 R@ _SPC.VALUES-A !
    -1 R@ _SPC.SIGS-A !
    -1 R@ _SPC.OPCODES-A !
    -1 R@ _SPC.OUTCOMES-A !

    BEGIN R@ _SPC.POS @ R@ _SPC.DESC-U @ < WHILE
        R@ _SPC-STEP ?DUP IF R> _SPC-FAIL EXIT THEN
    REPEAT
    R@ _SPC-FINISH ?DUP IF R> _SPC-FAIL EXIT THEN

    R@ _SPC.DESC-A @ R@ _SPC.DESC-U @
    R@ _SPC-PROFILE@ _SBP.DIGEST R@ _SPC.DIGEST-WORK
    SBOX-DIGEST-PROFILE IF SBOX-PROFILE-S-FAULT R> _SPC-FAIL EXIT THEN

    R@ _SPC-PROFILE@ _SBP-SEAL
    -1 R@ _SPC.ERROR !
    SBOX-PROFILE-S-OK R@ _SPC.STATUS !
    R@ _SPC-SCRUB
    R> DROP SBOX-PROFILE-S-OK ;

\ The last admitted load's status, and the byte offset of the record it
\ failed at, or -1.
: SBOX-PROFILE-LOAD-ERROR@  ( workspace -- load-status offset status )
    DUP _SPC-WORKSPACE-STATUS ?DUP IF NIP 0 -1 ROT EXIT THEN
    DUP _SPC.STATUS @ SWAP _SPC.ERROR @ SBOX-PROFILE-S-OK ;

\ Loads the embedded production pure-computation profile.
: SBOX-PROFILE-PURE-INIT  ( profile workspace -- status )
    >R >R SBOX-PROFILE-PURE-DESCRIPTOR R> R> SBOX-PROFILE-LOAD ;
