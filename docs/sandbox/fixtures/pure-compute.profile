AKASHIC-SANDBOX-PROFILE
codec 1
profile org.akashic.sandbox.pure-compute
semantics org.akashic.sandbox.semantics.pure-compute
artifact-format 1
source-language org.akashic.sandbox.source
value-codec org.akashic.sandbox.value-tree-le
cell-bits 64
false 0
true -1
recursion 1
rule arithmetic.div-signed-truncate-zero
rule arithmetic.div-trap-min-neg1
rule arithmetic.div-trap-zero
rule arithmetic.wrap-add-sub-mul-neg-inc-dec-abs
rule boolean.false-zero-true-minus-one
rule branch.function-local-index
rule call.direct-table-index
rule determinism.no-clock-random-float
rule import.rw-staged-atomic
rule instruction.charge-before-effect
rule loop.checked-signed-step
rule loop.lexical-current-frame-r
rule map.find-exact-binary-search
rule map.raw-utf8-byte-order
rule memory.fixed-zeroed-readonly-prefix
rule result.disjoint-owned-output-transfer
rule value.canonical-tree-codec
value 0 NULL
value 1 BOOL
value 2 I64
value 3 BYTES
value 4 UTF8
value 5 LIST
value 6 MAP
signature 1 org.akashic.sandbox.signature.value-to-value 1 VALUE 1 VALUE
opcode 0 NOP 0 0 0 0 0 1 0 0
opcode 1 LIT.I64 1 0 0 1 0 1 0 0
opcode 2 BR 2 0 0 0 0 1 0 0
opcode 3 BR.ZERO 2 0 1 0 0 1 0 0
opcode 4 BR.NONZERO 2 0 1 0 0 1 0 0
opcode 5 CALL 3 1 0 0 1 2 8 0
opcode 6 RETURN 0 2 0 0 0 1 0 0
opcode 7 ABORT 4 0 0 0 0 1 0 0
opcode 8 LOCAL.GET 5 0 0 1 0 1 0 0
opcode 9 LOCAL.SET 5 0 1 0 0 1 0 0
opcode 10 LOCAL.TEE 5 0 1 1 0 1 0 0
opcode 11 LOOP.ENTER 6 0 2 0 0 2 0 0
opcode 12 LOOP.NEXT 7 0 0 0 0 2 0 0
opcode 13 LOOP.NEXT.BY 7 0 1 0 0 2 0 0
opcode 14 LOOP.INDEX 0 0 0 1 0 1 0 0
opcode 16 DROP 0 0 1 0 0 1 0 0
opcode 17 DUP 0 0 1 2 0 1 0 0
opcode 18 SWAP 0 0 2 2 0 1 0 0
opcode 19 OVER 0 0 2 3 0 1 0 0
opcode 20 ROT 0 0 3 3 0 1 0 0
opcode 21 NIP 0 0 2 1 0 1 0 0
opcode 22 TUCK 0 0 2 3 0 1 0 0
opcode 23 2DROP 0 0 2 0 0 1 0 0
opcode 24 2DUP 0 0 2 4 0 1 0 0
opcode 25 2SWAP 0 0 4 4 0 1 0 0
opcode 26 2OVER 0 0 4 6 0 1 0 0
opcode 32 I64.ADD 0 0 2 1 0 1 0 0
opcode 33 I64.SUB 0 0 2 1 0 1 0 0
opcode 34 I64.MUL 0 0 2 1 0 1 0 0
opcode 35 I64.DIV.S 0 0 2 1 0 2 0 0
opcode 36 I64.REM.S 0 0 2 1 0 2 0 0
opcode 37 I64.DIVMOD.S 0 0 2 2 0 3 0 0
opcode 38 I64.NEG 0 0 1 1 0 1 0 0
opcode 39 I64.ABS 0 0 1 1 0 1 0 0
opcode 40 I64.MIN.S 0 0 2 1 0 1 0 0
opcode 41 I64.MAX.S 0 0 2 1 0 1 0 0
opcode 42 I64.INC 0 0 1 1 0 1 0 0
opcode 43 I64.DEC 0 0 1 1 0 1 0 0
opcode 44 I64.EQ 0 0 2 1 0 1 0 0
opcode 45 I64.NE 0 0 2 1 0 1 0 0
opcode 46 I64.LT.S 0 0 2 1 0 1 0 0
opcode 47 I64.LE.S 0 0 2 1 0 1 0 0
opcode 48 I64.GT.S 0 0 2 1 0 1 0 0
opcode 49 I64.GE.S 0 0 2 1 0 1 0 0
opcode 50 I64.LT.U 0 0 2 1 0 1 0 0
opcode 51 I64.LE.U 0 0 2 1 0 1 0 0
opcode 52 I64.GT.U 0 0 2 1 0 1 0 0
opcode 53 I64.GE.U 0 0 2 1 0 1 0 0
opcode 54 I64.ZERO? 0 0 1 1 0 1 0 0
opcode 55 I64.NEGATIVE? 0 0 1 1 0 1 0 0
opcode 56 I64.POSITIVE? 0 0 1 1 0 1 0 0
opcode 57 I64.AND 0 0 2 1 0 1 0 0
opcode 58 I64.OR 0 0 2 1 0 1 0 0
opcode 59 I64.XOR 0 0 2 1 0 1 0 0
opcode 60 I64.NOT 0 0 1 1 0 1 0 0
opcode 61 I64.SHL 0 0 2 1 0 1 0 0
opcode 62 I64.SHR.U 0 0 2 1 0 1 0 0
opcode 64 MEM.SIZE 0 0 0 1 0 1 0 0
opcode 65 MEM.LOAD8.U 0 0 1 1 0 2 0 0
opcode 66 MEM.STORE8 0 0 2 0 0 2 0 0
opcode 67 MEM.LOAD64 0 0 1 1 0 2 0 0
opcode 68 MEM.STORE64 0 0 2 0 0 2 0 0
opcode 69 MEM.MOVE 0 0 3 0 2 2 8 2
opcode 70 MEM.FILL 0 0 3 0 2 2 8 2
opcode 96 V.TYPE 0 0 1 1 0 2 0 1
opcode 97 V.BOOL.GET 0 0 1 1 0 2 0 1
opcode 98 V.I64.GET 0 0 1 1 0 2 0 1
opcode 99 V.LEN 0 0 1 1 0 2 0 1
opcode 100 V.LIST.GET 0 0 2 1 0 3 0 1
opcode 101 V.MAP.KEY 0 0 2 1 0 3 0 1
opcode 102 V.MAP.VALUE 0 0 2 1 0 3 0 1
opcode 103 V.MAP.FIND 0 0 3 2 3 4 8 1
opcode 104 V.BLOB.COPY 0 0 4 0 2 4 8 3
opcode 112 V.NEW.NULL 0 0 0 1 0 2 0 1
opcode 113 V.NEW.BOOL 0 0 1 1 0 2 0 1
opcode 114 V.NEW.I64 0 0 1 1 0 2 0 1
opcode 115 V.NEW.BYTES 0 0 2 1 2 4 8 3
opcode 116 V.NEW.UTF8 0 0 2 1 2 4 8 3
opcode 117 V.NEW.LIST 0 0 2 1 4 4 8 1
opcode 118 V.NEW.MAP 0 0 2 1 5 4 8 1
admission-limit artifact_bytes 65536
admission-limit code_bytes 49152
admission-limit compiler_control_depth 64
admission-limit compiler_unresolved_references 3072
admission-limit compiler_workspace_bytes 1048576
admission-limit effects 0
admission-limit entries 32
admission-limit function_parameters 16
admission-limit function_results 16
admission-limit functions 256
admission-limit imports 0
admission-limit linear_memory_bytes 262144
admission-limit locals_per_frame 64
admission-limit readonly_data_bytes 16384
admission-limit source_bytes 65536
admission-limit source_token_bytes 63
admission-limit source_tokens 16384
runtime-limit blob_bytes 65536
runtime-limit call_frames 64
runtime-limit cancel_poll_bytes 4096
runtime-limit cancel_poll_instructions 256
runtime-limit copy_bytes 1048576
runtime-limit data_stack_cells 256
runtime-limit guest_log_bytes 0
runtime-limit import_staging_bytes 0
runtime-limit input_value_bytes 131072
runtime-limit input_value_nodes 4096
runtime-limit instruction_units 1000000
runtime-limit list_count 1024
runtime-limit loop_frames 64
runtime-limit map_count 256
runtime-limit outer_deadline_ms 1000
runtime-limit output_arena_bytes 131072
runtime-limit output_arena_nodes 4096
runtime-limit output_result_bytes 131072
runtime-limit output_result_nodes 4096
runtime-limit persistent_write_bytes 0
runtime-limit proposal_bytes 0
runtime-limit proposal_count 0
runtime-limit semantic_reservation_bytes 1048576
runtime-limit value_depth 8
runtime-limit value_ops 16384
result 0 OK
result 1 REQUEST_REJECTED
result 2 PROFILE_MISMATCH
result 3 VERIFICATION_REJECTED
result 4 GUEST_TRAP
result 5 RESOURCE_EXHAUSTED
result 6 OUTPUT_REJECTED
result 7 IMPORT_FAILURE
result 8 CANCELLED
result 9 HOST_FAILURE
request-detail 1 MISSING_DECLARATION_OR_ARTIFACT
request-detail 2 INVALID_DECLARATION
request-detail 3 ENTRY_NOT_EXPOSED
request-detail 4 INPUT_CODEC_INVALID
request-detail 5 INPUT_SCHEMA_MISMATCH
request-detail 6 ACTIVATION_LIMIT_MISMATCH
request-detail 7 IMPORT_BINDING_INVALID
request-detail 8 REQUEST_POLICY_REJECTED
profile-detail 1 UNKNOWN_PROFILE_ID
profile-detail 2 PROFILE_DESCRIPTOR_INVALID
profile-detail 3 ARTIFACT_PROFILE_DIGEST_MISMATCH
profile-detail 4 DECLARATION_PROFILE_MISMATCH
profile-detail 5 VERIFIED_PLAN_PROFILE_MISMATCH
profile-detail 6 RUNTIME_BINDING_PROFILE_MISMATCH
trap-detail 1 BAD_OPCODE
trap-detail 2 BAD_INSTRUCTION_POINTER
trap-detail 3 BAD_BRANCH_TARGET
trap-detail 4 BAD_CALL_TARGET
trap-detail 5 DATA_STACK_UNDERFLOW
trap-detail 6 CALL_STACK_UNDERFLOW
trap-detail 7 BAD_EXIT_SHAPE
trap-detail 8 DIVIDE_BY_ZERO
trap-detail 9 DIVIDE_OVERFLOW
trap-detail 10 SHIFT_RANGE
trap-detail 11 MEMORY_OUT_OF_BOUNDS
trap-detail 12 MEMORY_MISALIGNED
trap-detail 13 MEMORY_READ_ONLY
trap-detail 14 INVALID_VALUE_HANDLE
trap-detail 15 VALUE_TYPE_MISMATCH
trap-detail 16 VALUE_INDEX_RANGE
trap-detail 17 INVALID_UTF8
trap-detail 18 DUPLICATE_MAP_KEY
trap-detail 19 INVALID_RESULT_GRAPH
trap-detail 20 EXPLICIT_ABORT
trap-detail 21 LOCAL_INDEX_RANGE
trap-detail 22 INVALID_LENGTH
trap-detail 23 LOOP_STACK_UNDERFLOW
trap-detail 24 LOOP_ZERO_STEP
trap-detail 25 LOOP_ARITHMETIC_OVERFLOW
trap-detail 26 LOOP_STATE_INVALID
trap-detail 27 MAP_KEY_ORDER
trap-detail 28 SLICE_OVERLAP
resource-detail 1 INSTRUCTION_UNITS
resource-detail 2 VALUE_OPS
resource-detail 3 COPY_BYTES
resource-detail 4 DATA_STACK
resource-detail 5 CALL_FRAMES
resource-detail 6 LOOP_FRAMES
resource-detail 7 OUTPUT_ARENA_NODES
resource-detail 8 OUTPUT_ARENA_BYTES
resource-detail 9 OUTPUT_RESULT_NODES
resource-detail 10 OUTPUT_RESULT_BYTES
resource-detail 11 IMPORT_STAGING_BYTES
output-detail 1 OUTPUT_SCHEMA_MISMATCH
import-detail 1 DENIED
import-detail 2 UNAVAILABLE
import-detail 3 REJECTED
import-detail 4 RESULT_INVALID
cancel-detail 1 CALLER_CANCELLED
cancel-detail 2 CONTEXT_RELEASED
cancel-detail 3 DEADLINE
cancel-detail 4 HOST_SHUTDOWN
cancel-detail 5 ADAPTER_CANCELLED
host-detail 1 PREPARE_ALLOCATION
host-detail 2 INPUT_ADAPTER
host-detail 3 OUTPUT_ADAPTER
host-detail 4 WORKER_FAULT
host-detail 5 INTERNAL_INVARIANT
host-detail 6 IMPORT_ADAPTER_FAULT
host-detail 7 CLEANUP_FAULT
verify-detail 1 MALFORMED_ARTIFACT
verify-detail 2 LENGTH_OR_ARITHMETIC_OVERFLOW
verify-detail 3 INVALID_FUNCTION_OR_ENTRY
verify-detail 4 INVALID_OPCODE_OR_OPERAND
verify-detail 5 INVALID_TRANSFER_TARGET
verify-detail 6 INCONSISTENT_STACK_MERGE
verify-detail 7 INVALID_CALL_SIGNATURE
verify-detail 8 INVALID_LOCAL_INDEX
verify-detail 9 INVALID_LOOP_SHAPE
verify-detail 10 INVALID_IMPORT_DECLARATION
verify-detail 11 PROFILE_LIMIT_EXCEEDED
end 17 7 1 0 80 17 25
