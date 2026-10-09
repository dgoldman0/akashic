# Canonical execution-profile descriptor

**Status:** implemented by `akashic/sandbox/profile-codec.f`
**Scope:** immutable machine-readable profile identity, independent validation,
and runtime-binding compatibility

This document defines the exact bytes hashed by an Akashic sandbox artifact's
profile-digest field. The descriptor is declarative trusted configuration. It
says what a module means: its semantic rules, value tags, entry signatures,
opcodes and outcome codes. It contains no handler address, host pointer,
Context, service, authority, publisher assertion, module schema, or resource
limit. How much one compilation, verification or run may use is the host's
dynamic policy (see [`profile-and-abi.md`](profile-and-abi.md) §10), so one
profile serves every host and device.

A runtime profile is built only by loading a descriptor. There is no other way
to construct, edit or reseal one.

The permanent production pure-computation descriptor is checked in as
[`pure-compute.profile`](fixtures/pure-compute.profile). Its complete bytes,
including the final LF, are normative. Its published byte length, raw
SHA3-256, and domain-separated profile digest appear at the end of this
document.

## One clean codec

This is the first deliberately ratified profile codec. The record `codec 1`
classifies these bytes; it is not a compatibility boundary with ITC, a
`v2` runtime, or an excuse to retain a prior profile. There is no prior
sandbox-profile codec.

## Byte and line rules

A descriptor is a nonempty US-ASCII byte string with these exact properties:

- bytes outside `0x0A` and printable `0x20..0x7E` are invalid;
- every record ends in one LF byte (`0x0A`), including the last record;
- CR, TAB, NUL, blank lines, comments, leading/trailing spaces, and duplicate
  spaces are invalid;
- fields are separated by exactly one ASCII SPACE;
- unsigned integers are base-ten ASCII with no sign and no leading zero unless
  the value is exactly `0`;
- signed integers are base-ten ASCII with `-` only for a negative value, no
  leading plus, and no redundant leading zero;
- ordinary identifiers match `[A-Za-z][A-Za-z0-9._-]{0,126}`;
- an opcode semantic identifier matches
  `[A-Z0-9][A-Z0-9.?_-]{0,62}` instead, so normative names such as
  `2DROP` and `I64.ZERO?` are represented exactly;
- the complete descriptor is at most 65,536 bytes and has at most 1,024
  records; and
- all integer conversions and record counts are checked before allocation.

There is one representation for a semantic table. A decoder MUST reject and
must not normalize a noncanonical representation.

## Exact record order

Records occur in these groups and no other order:

1. one `AKASHIC-SANDBOX-PROFILE` magic record;
2. one `codec`, `profile`, `semantics`, `artifact-format`,
   `source-language`, `value-codec`, `cell-bits`, `false`, `true`, and
   `recursion` record, in that order;
3. one or more `rule` records, strictly increasing by rule identifier;
4. `value` records, strictly increasing by numeric tag;
5. `signature` records, strictly increasing by numeric signature ID;
6. zero or more `import` records, strictly increasing by numeric import ID;
7. one or more `opcode` records, strictly increasing by numeric opcode;
8. `result`, `request-detail`, `profile-detail`, `trap-detail`,
   `resource-detail`, `output-detail`, `import-detail`,
   `cancel-detail`, `host-detail`, and `verify-detail` groups in that exact
   order, with numeric codes strictly increasing inside each nonempty group;
9. one `end` record containing the exact counts described below.

The exact fixed records are:

```text
AKASHIC-SANDBOX-PROFILE
codec <u16>
profile <identifier>
semantics <identifier>
artifact-format <u16>
source-language <identifier>
value-codec <identifier>
cell-bits <u16>
false <i64>
true <i64>
recursion <0-or-1>
```

`semantics` names the normative semantic contract implemented by the runtime.
Changing any normative behavior requires changing at least one canonical rule,
table, or semantic-identity field and therefore publishing different
descriptor bytes and a different digest. The identifier is a semantic category,
not a release number.

## Rule, value, signature, and import records

Each semantic rule is one closed identifier:

```text
rule <identifier>
```

The identifiers' normative meanings are fixed by
[`profile-and-abi.md`](profile-and-abi.md). Unknown rules are invalid; a
runtime admits a descriptor only when it implements the complete exact rule
set.

The pure-computation rule set has these exact meanings:

| Rule identifier | Normative meaning |
|---|---|
| `arithmetic.div-signed-truncate-zero` | Signed quotient truncates toward zero and remainder follows that quotient |
| `arithmetic.div-trap-min-neg1` | `INT64_MIN / -1` and its remainder forms trap |
| `arithmetic.div-trap-zero` | Every signed divide/remainder form traps on divisor zero |
| `arithmetic.wrap-add-sub-mul-neg-inc-dec-abs` | Listed integer operations wrap modulo 2^64, including ABS of `INT64_MIN` |
| `boolean.false-zero-true-minus-one` | Canonical flags are exactly `0` and `-1` |
| `branch.function-local-index` | Every branch operand is an instruction index inside its current function |
| `call.direct-table-index` | Every call is a direct function-table index with declared cell signature |
| `determinism.no-clock-random-float` | Guest semantics expose no clock, randomness, or floating point |
| `import.rw-staged-atomic` | Writable import slices use checked nonoverlapping staging and commit only after validated success |
| `instruction.charge-before-effect` | Complete deterministic charge is reserved before guest-visible mutation or dispatch |
| `loop.checked-signed-step` | Counted-loop advance is checked signed addition with the exact positive/negative continuation comparisons |
| `loop.lexical-current-frame-r` | `R` observes only the innermost loop owned by the current call frame |
| `map.find-exact-binary-search` | MAP lookup validates one UTF-8 query and follows the fixed midpoint, termination, absent-value, and charging algorithm |
| `map.raw-utf8-byte-order` | MAP keys are unique and strictly ordered by unsigned raw UTF-8 bytes |
| `memory.fixed-zeroed-readonly-prefix` | Linear memory is fixed, fully initialized, and protects the copied initial-data prefix |
| `result.disjoint-owned-output-transfer` | Structural success seals a disjoint result-owned canonical copy before invocation cleanup |
| `value.canonical-tree-codec` | Host values use the exact `org.akashic.sandbox.value-tree-le` contract |

Value records are:

```text
value <tag:u16> <value-identifier>
```

Signature records are:

```text
signature <id:u32> <signature-identifier> <parameter-count:u16> \
<parameter-kinds> <result-count:u16> <result-kinds>
```

`parameter-kinds` and `result-kinds` are comma-separated machine-kind atoms
with no spaces, or `-` when the corresponding count is zero. The number of
atoms MUST equal the count. Atoms are:

```text
I64
BOOL
VALUE
SLICE.RO
SLICE.RW
OPAQUE.<nonzero-u16-kind>
```

An import record is:

```text
import <id:u32> <import-identifier> <signature-id:u32> \
<cost-rule-id:0..3> <base-instruction-units:u64>
```

The signature and cost-rule semantics are those in
[`profile-and-abi.md`](profile-and-abi.md). An artifact names only the import
and signature IDs; it cannot override the descriptor's cost. Absence from the
descriptor means disabled. The pure-computation descriptor has no import
record.

## Opcode records

Every enabled instruction has exactly one record:

```text
opcode <code:u16> <semantic-identifier> <operand-kind:u8> \
<effect-kind:u8> <pop:u8> <push:u8> <cost-kind:u8> \
<base:u64> <divisor:u32> <extra-charge-kind:u8>
```

The numeric enums are closed:

| Value | Operand kind |
|---:|---|
| `0` | no operand |
| `1` | operand B is an `i64` bit pattern |
| `2` | operand A is a function-local branch target |
| `3` | operand A is a function-table index |
| `4` | low 16 bits of operand A are an abort code |
| `5` | operand A is a local index |
| `6` | operand A is a matching loop-exit target |
| `7` | operand A is a matching loop-body target |
| `8` | operand A is an artifact import index |

| Value | Effect kind |
|---:|---|
| `0` | fixed cell effect given by `pop` and `push` |
| `1` | direct-call effect from the callee record |
| `2` | return effect from the current function record |
| `3` | import effect from the exact descriptor signature |

For effect kinds 1 through 3, `pop` and `push` are zero. Loop-frame effects are
part of the loop semantic IDs and verifier abstract state, not guest-cell
effects.

| Value | Cost kind |
|---:|---|
| `0` | exactly `base` |
| `1` | `base + ceil(callee-local-count / divisor)` |
| `2` | `base + ceil(runtime-length / divisor)` |
| `3` | MAP search: `base + ceil(query bytes / divisor) + compared entries + ceil(compared stored-key bytes / divisor)` |
| `4` | LIST construction: `base + count` |
| `5` | MAP construction: `base + 2*count + ceil(total key bytes / divisor)` |
| `6` | import dispatch: `base + referenced import base + referenced import dynamic rule` |

`divisor` is zero for cost kinds 0 and 6 and is exactly 8 for kinds 1 through
5. For kind 6, `base` is exactly 1, operand kind is 8, effect kind is 3, and
the referenced import supplies dynamic rule 0 through 3. Every calculation
uses checked unsigned arithmetic.

| Value | Extra charge kind |
|---:|---|
| `0` | no extra counter |
| `1` | one `value_ops` unit |
| `2` | runtime length in `copy_bytes` |
| `3` | one `value_ops` unit and runtime length in `copy_bytes` |
| `4` | for import dispatch, twice the checked sum of all `SLICE.RW` lengths in `copy_bytes` |

An absent opcode is disabled. In particular, the generic shared executor
implements opcode 80 (`IMPORT.CALL`), but the pure-computation descriptor does
not contain it and its verifier rejects it.

A descriptor with any import record MUST contain exactly:

```text
opcode 80 IMPORT.CALL 8 3 0 0 6 1 0 4
```

A descriptor with no import record MUST omit opcode 80. These are
cross-validation rules, not implicit records.

## Outcome records

Outcome records all have:

```text
<group> <code:u16> <identifier>
```

Numeric codes and identifiers are part of the profile identity. Detail code
zero is reserved for `OK` and is not listed in a detail group.

The terminal record is:

```text
end <rule-count:u16> <value-count:u16> <signature-count:u16> \
<import-count:u16> <opcode-count:u16>
```

The physical record counts MUST match exactly. No record follows `end`.

## Validation and sealing

`SBOX-PROFILE-LOAD ( descriptor descriptor-u profile workspace -- status )`:

1. validates the caller spans and the absolute ceilings;
2. validates the byte/line grammar without normalization;
3. checks exact group order, field arity, enums, ranges, sorting, uniqueness,
   cross-references, counts, positive instruction costs, and required fields;
4. requires what the descriptor names to be implemented locally;
5. computes the domain-separated profile digest;
6. constructs an immutable declarative table in the caller's profile; and
7. writes its seal last.

Failure publishes no partially usable profile. A noncanonical descriptor is
`SBOX-PROFILE-S-DESCRIPTOR`. A canonical one that names something this runtime
does not implement is `SBOX-PROFILE-S-UNSUPPORTED`. When both apply, the
invalid descriptor is reported. `SBOX-PROFILE-LOAD-ERROR@` returns the byte
offset of the record that failed: the first invalid record, or the earliest
unsupported one.

The runtime's vocabulary is the embedded production descriptor itself. A
loaded descriptor's rule, value and outcome groups must equal the embedded
ones exactly. Its signature and opcode records must each equal the embedded
record of the same number, so a descriptor may enable a subset of them. This
runtime has no import adapter, so any import record is unsupported.
`SBOX-PROFILE-PURE-INIT` loads the embedded descriptor. A sealed descriptor contains no
native handler. A separately sealed runtime binding must match its exact
profile digest, import IDs, signatures, and costs as specified in
[`profile-and-abi.md`](profile-and-abi.md).

## Digest calculation

The raw descriptor digest is:

```text
SHA3-256(exact descriptor bytes)
```

The artifact-facing profile digest is:

```text
SHA3-256(
  ASCII("akashic.sandbox.profile") ||
  0x00 ||
  exact descriptor bytes
)
```

The pure-computation fixture values below are normative and are checked by
`test_sandbox_digest.py` and `test_sandbox_profile_codec.py`:

```text
descriptor bytes: 6899
raw SHA3-256: a40084a0350f5f92d42473f46c1836dfaef8550163d9b67d1d3126addb3a8a88
profile SHA3-256: 6a53f8973d7f99694b242a315234f66e28c04da6e15e61e47f490025f7473b22
```
