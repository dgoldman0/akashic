# Shared sandbox capability

`akashic/interop/sandbox-capability.f` defines component
`org.akashic.sandbox`. Any caller the request bus admits can use it to run
restricted sandbox source, under the same facets, Mandates, policy, review and
grants as every other capability. Its one capability so far is
`org.akashic.sandbox/test`.

## `org.akashic.sandbox/test`

A command that only observes. It compiles and verifies a module for the
pure-computation profile, runs one entry on an input, and replies with the
result or with where the module failed. The language is
[`../sandbox/source-language.md`](../sandbox/source-language.md).

Every request field is required:

| Field | Type | Meaning |
| --- | --- | --- |
| `source` | string | restricted source, at most 65,536 bytes |
| `entry` | string | the entry to run, at most 63 bytes |
| `input` | string | the input value as JSON text, `null` for none |
| `memory` | integer | bytes of guest memory, rounded up to whole cells, at most what the host's policy grants |

Every reply field is present:

| Field | Type | Meaning |
| --- | --- | --- |
| `ok` | boolean | whether the entry returned a result |
| `result` | string or null | the result as JSON text |
| `error` | map or null | why there is no result |

The error map holds `step`, `code`, `abort`, `line`, `column`, `length` and
`text`; a field that does not apply is null.

| `step` | When | `code` |
| --- | --- | --- |
| `compile` | the compiler refused the source | an `SBOX-COMPILER-E-` suffix |
| `verify` | the verifier refused the compiled module | an `SBOX-VERIFIER-D-` suffix |
| `input` | the input is not JSON, the sandbox cannot carry it, or `memory` exceeds the policy | `json-*`, `type`, `utf8`, `key` or `limit` |
| `entry` | the module has no such typed entry | `entry` |
| `run` | the run trapped, ran out of a budget, or was cancelled | an `SBOX-VM-TRAP-`, `-EXHAUST-` or `-CANCEL-` suffix |
| `result` | JSON cannot carry the result | `json-*` |

A code is the lowercase suffix of the constant it names, for example
`stack-underflow` for `SBOX-VERIFIER-D-STACK-UNDERFLOW`. Compiler codes are
listed in
[`source-language.md` §10.1](../sandbox/source-language.md#101-diagnostics).

`line` and `column` count from 1, and a column counts bytes. They, `length`
and `text` are set when source bytes caused the failure: a compile failure at
a token, or a verify failure at an instruction, which the compiler's source map
ties back to its form. A run failure has no position yet, because the VM does
not report where it trapped. `abort` is the code of an explicit `ABORT n`.

Build, input and entry failures are answered at once with `CBUS-S-OK`. A run is
accepted with `CBUS-S-ACCEPTED` and completed later through the request bus's
[deferred completion](request-bus.md#deferred-completion). A cancelled request
completes as `CBUS-S-CANCELLED`. A run that cannot start because every run is
in use is refused with `CBUS-S-BUSY`.

Values cross as JSON text, so a caller that speaks JSON, the Agent first, uses
the capability as it is, and every field is required so the tool stays strict.
JSON has no bytes or floats: an input with a float fails with
`json-unsupported`, and a result holding bytes fails at the `result` step.

## Ownership and the host

A run belongs to the request's calling instance, `CBR.CALLER-ID` and
`CBR.CALLER-GEN`. A request without one is refused with `CBUS-S-DENIED`. No
caller can see or cancel another caller's run.

The host drives the instance:

- `SBOX-CAPABILITY-BIND ( parent policy slice-steps allowance-ms capacity
  instance -- status )` binds it to a parent Context and a limit policy that
  bounds every field, with room for `capacity` runs at once. The instance owns
  a job service, the pure-computation profile it loads from the canonical
  descriptor, and one build record per run.
  `slice-steps` and `allowance-ms` pace the runs as `SBOX-JOB-SERVICE-INIT`
  describes. The policy is copied at bind; the parent Context stays borrowed
  until unbind.
- `SBOX-CAPABILITY-TICK ( instance -- status )` runs jobs within the allowance
  and completes every run that was cancelled or has settled.
- `SBOX-CAPABILITY-OWNER-DRAIN ( owner-id owner-generation instance --
  status )` completes a closing caller's runs as cancelled. The host calls it
  before that caller frees its requests.
- `SBOX-CAPABILITY-BUSY? ( instance -- flag )` reports whether a run is under
  way, so the host keeps ticking.
- `SBOX-CAPABILITY-UNBIND ( instance -- status )` completes every run as
  cancelled and frees the binding. Freeing the instance unbinds it too.

The host must not unbind or free the instance from a completion callback.

## Test

```bash
python3 local_testing/akashic_tui.py smoke --profile sandbox-capability-contracts
```

The contracts check the descriptors and that the schemas suit a strict JSON
caller, every code's name, results, compile and verify failures with their
positions, input and entry failures, traps, an explicit abort, budget
exhaustion, cancellation, a full capability, owner drain, unbind, and that
the capability returns every byte it allocates.

```bash
python3 local_testing/akashic_tui.py smoke --profile desktop-sandbox
```

This journey runs Desk with the Agent alone and the product sandbox policy.
The Agent calls the capability through its ordinary tool path: a module with
an unknown word gets its compile error with its line and column, and the fixed
module returns its result. Desk must idle below a tenth of the clock before and
after the runs.
