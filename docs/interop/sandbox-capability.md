# Shared sandbox capability

`akashic/interop/sandbox-capability.f` defines component
`org.akashic.sandbox`. Any caller the request bus admits can use it to run
restricted sandbox source and installed modules, under the same facets,
Mandates, policy, review and grants as every other capability. It has five
capabilities:

| Capability | Intent | Effects | What it does |
| --- | --- | --- | --- |
| `org.akashic.sandbox/test` | `sandbox.test` | observe | compiles and verifies source and runs one entry |
| `org.akashic.sandbox/install` | `sandbox.install` | persist | builds source into an exact revision of a named module and keeps it |
| `org.akashic.sandbox/invoke` | `sandbox.invoke` | observe | runs one entry of an installed module revision |
| `org.akashic.sandbox/list` | `sandbox.list` | observe | lists the installed modules, a page at a time |
| `org.akashic.sandbox/authorize` | `sandbox.authorize` | observe | asks the user to let the calling component use a module revision |

An applet reaches a capability by posting its intent, as it reaches any
component; the Agent reaches it through a row of Desk's catalog.

The language is [`../sandbox/source-language.md`](../sandbox/source-language.md).
Every module runs under the pure-computation profile.

## Values and replies

Values cross as JSON text, so a caller that speaks JSON, the Agent first, uses
the capability as it is. Every request field is required, so the tools stay
strict. JSON has no bytes or floats: an input with a float fails with
`json-unsupported`, and a result holding bytes fails at the `result` step.

`test`, `install`, `invoke` and `authorize` reply with three fields, all
present:

| Field | Type | Meaning |
| --- | --- | --- |
| `ok` | boolean | whether the request succeeded |
| `result` | string or null | an entry's result as JSON text; null for `install` and `authorize` |
| `error` | map or null | why the request failed |

The error map holds `step`, `code`, `abort`, `line`, `column`, `length` and
`text`; a field that does not apply is null.

| `step` | When | `code` |
| --- | --- | --- |
| `compile` | the compiler refused the source | an `SBOX-COMPILER-E-` suffix |
| `verify` | the verifier refused the compiled module | an `SBOX-VERIFIER-D-` suffix |
| `input` | the input is not JSON, does not match the entry's input schema, cannot cross into the sandbox, or `memory` exceeds the policy | `json-*`, `schema`, `type`, `utf8`, `key` or `limit` |
| `entry` | the module has no such entry, or JSON cannot carry its values | `entry`, `unknown` or `unsupported` |
| `run` | the run trapped, ran out of a budget, or was cancelled | an `SBOX-VM-TRAP-`, `-EXHAUST-` or `-CANCEL-` suffix |
| `result` | JSON cannot carry the result | `json-*` |
| `output` | the result does not match the entry's output schema | `schema` |
| `module` | the module's name is not one, or the revision is unknown, quarantined or revoked; or the module table refused an install | `name`, `unknown`, `quarantined`, `revoked`, or an `SBOX-MODULE-S-` suffix |
| `entries` | an install's entries are not exactly the module's | `missing`, `unknown` or `duplicate` |
| `input-schema`, `output-schema` | an install's JSON Schema for an entry was refused | `json-*` from the JSON Schema reader, or `type`, `depth`, `open` or `invalid` |
| `access` | the caller may not use the module revision | `not-granted`, `caller`, `practice`, `denied` or `agent` |
| `store` | the module store refused | an `SBOX-STORE-S-` suffix, such as `duplicate`, `revoked`, `recovery` or `io` |

A code is the lowercase suffix of the constant it names, for example
`stack-underflow` for `SBOX-VERIFIER-D-STACK-UNDERFLOW`. Compiler codes are
listed in
[`source-language.md` §10.1](../sandbox/source-language.md#101-diagnostics).

`line` and `column` count from 1, and a column counts bytes. They, `length`
and `text` are set when source bytes caused the failure: a compile failure at
a token, or a verify failure at an instruction, which the compiler's source map
ties back to its form. A run failure has no position yet, because the VM does
not report where it trapped. Without a position, `text` names what failed when
there is one thing to name: the module for `module`, and the entry for
`entry`, `entries`, `input-schema` and `output-schema`. `abort` is the code of
an explicit `ABORT n`.

What fails before a run is answered at once with `CBUS-S-OK`. A run is
accepted with `CBUS-S-ACCEPTED` and completed later through the request bus's
[deferred completion](request-bus.md#deferred-completion), and so is a request
that waits for the user. A cancelled request completes as `CBUS-S-CANCELLED`.
A request that cannot start because every run is in use is refused with
`CBUS-S-BUSY`.

## `org.akashic.sandbox/test`

Compiles and verifies source, runs one entry on an input, and replies with the
result or with where the module failed.

| Field | Type | Meaning |
| --- | --- | --- |
| `source` | string | restricted source, at most 65,536 bytes |
| `entry` | string | the entry to run, at most 63 bytes |
| `input` | string | the input value as JSON text, `null` for none |
| `memory` | integer | bytes of guest memory, rounded up to whole cells, at most what the host's policy grants |

## Installed modules

A module has a name, spelled as an entry name is, and every revision of it is
exact: there is no "latest". Each entry carries a schema its input must match
and one its result must match. Installed modules live in the binding's module
table, which the [module store](../sandbox/module-store.md) fills and keeps
across restarts; without storage, the module capabilities fail and the list is
empty.

### `org.akashic.sandbox/install`

| Field | Type | Meaning |
| --- | --- | --- |
| `module` | string | the module's name, at most 63 bytes |
| `revision` | integer | the revision, at least 1 |
| `source` | string | restricted source, at most 65,536 bytes |
| `memory` | integer | bytes of guest memory for every run, as for `test` |
| `entries` | list | one `{name, input, output}` for each of the module's entries, at most 64 |

`input` and `output` are JSON Schema text in the form the JSON Schema reader
takes ([`schema-bytes.md`](schema-bytes.md#json-form)). Whatever it reads is
closed and can be carried by JSON, so every installed entry can be invoked.

The capability builds the source, then writes the module's
[declaration](../sandbox/declaration-format.md): the module and revision, the
artifact's entries in their order with their signatures, and their schemas.
The declaration's digest is the install's operation key, so the same install
again changes nothing and replies `ok`. Other content for an installed
revision fails with `store`/`duplicate`, and a revoked or removed revision can
never be installed again (`store`/`revoked`).

Installing persists, so the bus asks for approval: the Agent's install is a
reviewed commit, and any other caller needs the host's approval.

### `org.akashic.sandbox/invoke`

| Field | Type | Meaning |
| --- | --- | --- |
| `module` | string | the module's name |
| `revision` | integer | the exact revision |
| `entry` | string | the entry to run |
| `input` | string | the input value as JSON text |

The Agent may invoke any installed module, under its own review and Mandate.
Every other component needs a grant for that exact revision in the Practice of
the binding's parent Context; the Agent's requests name Desk as their caller,
so a grant can never stand for them. Before anything runs, the capability:

1. finds the revision, verifying a module loaded from storage on its first
   use; a damaged one is quarantined then;
2. checks the caller's access;
3. finds the entry and checks that JSON can carry both of its schemas, which
   matters for a module another installer declared, for example with bytes;
4. decodes the input and checks it against the entry's input schema.

The run is limited by the host's policy, narrowed by any limits the module's
declaration asks for. It pins the module, so the module cannot be removed
under it; revoking it stops new runs only. The result must match the entry's
output schema.

### `org.akashic.sandbox/list`

The request has one field, `first`, the index to start from. The reply is
`{modules, next}`: at most eight modules from `first`, in the module table's
order, and the `first` of the following page, or null after the last. Each
module is a map:

| Field | Type | Meaning |
| --- | --- | --- |
| `module` | string or null | the name; null when the store lost the module's declaration |
| `revision` | integer | the revision |
| `state` | string | `installed`, `quarantined` or `revoked` |
| `entries` | list or null | `{name, input, output}` for each entry, the schemas as JSON Schema text; null when JSON cannot describe them |

The schemas are written as the JSON Schema writer writes them, which may
differ from the text an install gave: an integer's bounds, for example, are
always written out.

### `org.akashic.sandbox/authorize`

| Field | Type | Meaning |
| --- | --- | --- |
| `module` | string | the module's name |
| `revision` | integer | the exact revision |

The calling component asks to use a module revision in the binding's
Practice. If it already holds the grant, the reply is `ok` at once. Otherwise
the request waits until the host has asked the user. When the user allows it,
the grant is recorded first and the reply is `ok`; a refusal fails with
`access`/`denied`. The request itself only observes: the grant is the user's
act, made through the host. The Agent cannot ask (`access`/`agent`).

## Ownership and the host

A run belongs to the request's calling instance, `CBR.CALLER-ID` and
`CBR.CALLER-GEN`. A request without one is refused with `CBUS-S-DENIED`. No
caller can see or cancel another caller's run.

The host drives the instance:

- `SBOX-CAPABILITY-BIND ( parent policy slice-steps allowance-ms workers
  capacity instance -- status )` binds it to a parent Context and a limit
  policy that bounds every field, with room for `capacity` runs at once. The
  instance owns a job service, the pure-computation profile it loads from the
  canonical descriptor, and one build record per run.
  `slice-steps`, `allowance-ms` and the `workers` core mask pace the runs as
  `SBOX-JOB-SERVICE-INIT` describes: with workers, every job runs on one of
  those cores while the host's core runs none. The policy is copied at bind;
  the parent Context stays borrowed until unbind.
- `SBOX-CAPABILITY-MODULES ( registry vfs catalog catalog-u pack pack-u
  instance -- status )` gives a bound instance installed modules. The
  registry names the components that ask for them, and the module store keeps
  them in the catalog and pack files at those absolute paths of the VFS, in
  one directory. The instance opens the store at once and owns it and its
  module table until unbind. A store in recovery opens and serves what it
  could read.
- `SBOX-CAPABILITY-STORE@` and `SBOX-CAPABILITY-MODULES@ ( instance --
  store|owner|0 )` give the module store and module table, through which the
  host shows modules and grants and revokes or removes them.
- `SBOX-CAPABILITY-ASK ( instance -- ask|0 )` gives the first request waiting
  for the user, `SBOX-CAPABILITY-ASK@ ( ask -- grantee grantee-u module
  module-u revision )` what it asks for, and `SBOX-CAPABILITY-ASK-ID@ ( ask
  -- id )` its identity, which no other request of the binding shares, even
  one that later takes the same run. `SBOX-CAPABILITY-ASKING? ( ask id
  instance -- flag )` says whether it still waits, and
  `SBOX-CAPABILITY-ANSWER ( allow ask id instance -- status )` answers it and
  completes the request, refusing a request that no longer waits as `id`; with
  `allow`, `SBOX-CAPABILITY-S-STORE` says the store refused the grant.
- `SBOX-CAPABILITY-PRACTICE ( instance -- rid|0 )` gives the Practice the
  binding's grants are for.
- `SBOX-CAPABILITY-TICK ( instance -- status )` runs jobs within the allowance,
  or with workers lends them out and takes back what they finished, and
  completes every run that was cancelled or has settled.
- `SBOX-CAPABILITY-POLL ( instance -- worked? )` takes back the jobs workers
  finished, lends waiting ones and completes the runs that settled. It runs
  no job on the host's core and returns at once while there are no workers or
  no run is under way, so a host may call it on every pass of its loop; a
  worker that finishes wakes that loop with an IPI.
- `SBOX-CAPABILITY-OWNER-DRAIN ( owner-id owner-generation instance --
  status )` completes a closing caller's runs and requests as cancelled. The
  host calls it before that caller frees its requests.
- `SBOX-CAPABILITY-BUSY? ( instance -- flag )` reports whether a run is under
  way, so the host keeps ticking. A request waiting for the user does not
  count.
- `SBOX-CAPABILITY-UNBIND ( instance -- status )` completes every run and
  waiting request as cancelled, closes the module store and frees the
  binding. Freeing the instance unbinds it too.

The host must not unbind or free the instance from a completion callback.

## Test

```bash
python3 local_testing/akashic_tui.py smoke --profile sandbox-capability-contracts
```

The contracts check the descriptors and that every schema suits a strict JSON
caller, every code's name, results, compile and verify failures with their
positions, input and entry failures, traps, an explicit abort, budget
exhaustion, cancellation, a full capability, owner drain and unbind. On a RAM
filesystem they then check:

- module requests without storage;
- installs and each refusal: a bad name, missing, unknown and duplicate
  entries, unreadable and open schemas, a compile failure, too much memory,
  a repeat, other content for an installed revision, and a second revision;
- a module with a bytes entry, installed as another installer could;
- listing two pages, the schemas' text, and entries JSON cannot describe;
- invoking: a result, unknown modules, revisions and entries, an input that is
  not JSON or does not match, a result that does not match, and an entry JSON
  cannot carry;
- a test applet refused, asking, refused by the user, cancelling, allowed and
  then served, and never asked twice; an answer only for the request asked,
  even when a later request takes its run; a grant for one revision only; the
  Agent never asking;
- revocation, then a restart that keeps the modules and the grant, verifies a
  module on its first use, quarantines a damaged one, and still refuses the
  revoked revision;

and that the capability returns every byte it allocates.

```bash
python3 local_testing/akashic_tui.py smoke --profile desktop-sandbox
```

This journey runs Desk with the Agent alone and the product sandbox policy.
The Agent calls the capability through its ordinary tool path: a module with
an unknown word gets its compile error with its line and column, and the fixed
module returns its result. Desk must idle below a tenth of the clock before and
after the runs.

```bash
python3 local_testing/akashic_tui.py smoke --profile desktop-sandbox-modules
```

The narrow sandbox journey runs Desk, the Agent, and Probe, a small applet
standing in for a second consumer. The Agent installs a module after the user
approves its review, which writes the store's two files, invokes it, and is
refused a wrong input and an unknown entry. Probe is refused, asks, is
allowed through Desk's access prompt, and is served; the inspector withdraws
its grant, which refuses it again, and revokes the module, which refuses the
Agent. Desk must idle below a tenth of the clock afterwards. A restart is not
part of this journey, since the harness boots once; the contracts above cover
it.
