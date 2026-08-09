# Desk, Library, and Rabbit Burrow checkpoint 2

**Qualified:** 2026-08-09

**Contract:** [`desk-library-burrow-checkpoint0.md`](desk-library-burrow-checkpoint0.md)

**Status:** Desk/Agent control plane independently qualified. Checkpoint 3
begins the Streams Burrow manager, not product composition.

Checkpoint 2 replaces Desk's procedural Agent capability lists with a closed,
Desk-owned policy catalog and carries complete reviewed operands and successful
results through the Agent control plane. It does not add Streams Burrow product
capabilities, compose the final Desk journey, expose Library query/read to
Agent, or claim Rabbit-client completion.

## Landed slices

| Commit | Scope |
| --- | --- |
| `eaeed29` | Trusted 23-row Desk catalog, 24-entry facet geometry, exact access matrix, and `desk.practice-library-burrow` preset |
| `eff2bc2` | Architecture inventory and seam ratchet for the first slice |
| `ebc5736` | Complete canonical review operands and result-bearing `OK`/`NO-EFFECT` across the Agent control plane |
| `d260976` | Final architecture-ratchet refresh for the control-plane slice |

The catalog is policy input rather than discovery or registration authority.
Every selected row still requires the exact trusted built-in descriptor, a
live instance and generation, matching capability effects, the selected exact
Practice preset, and the normal Mandate and capability-bus checks. The full
catalog has 23 rows. `CFACET-MAX-ENTRIES` is 24, so it represents the complete
known policy with one tested spare entry instead of truncating functionality to
the former 16-row implementation ceiling.

The full-Desk preset maxima are now exact:

| Preset | Rows | Tool budget | Added Library/Burrow authority |
| --- | ---: | ---: | --- |
| Chat only | 0 | 0 | none |
| Practice read only | 13 | 4 | `library.status` and `streams.burrow.status` only |
| Practice assist | 20 | 8 | both statuses and the two reviewed Library creates |
| Practice Library Burrow | 23 | 12 | the Assist set plus reviewed Burrow create/start/stop |

Rows whose trusted owner is not live before mandate freezing are omitted.
Library document query/read remain absent from ordinary Agent authority. No
preset gains destructive or external effects. The later focused
Library/Streams composition is expected to contain nine rows, but that product
composition remains Checkpoint 4 evidence rather than a Checkpoint 2 claim.

## Capacity and result semantics

The request and review capacities now have one source of truth:

| Boundary | Capacity | Classification |
| --- | ---: | --- |
| Capability-bus canonical arguments | 65,536 bytes | Existing unchanged `CBR-ARGS-CANONICAL-MAX` |
| Gateway canonical/review arguments | 65,536 bytes | Derived from the CBR ceiling |
| Agent review JSON | 65,536 bytes | Derived from the gateway review ceiling |
| Agent visible review | 262,144 bytes | Exact four-times worst-case `\xHH` expansion |
| Model-context tool call | 65,536 bytes | Complete canonical operand |
| Model-context tool result | 32,768 bytes | Independent existing result boundary |

This does not introduce a second arbitrary 64 KiB limit or raise the bus
ceiling. It removes the smaller review and tool-call buffers that could not
carry valid requests already admitted by the canonical bus contract. Call and
result storage are deliberately split: accepting a complete reviewed operand
does not broaden provider-visible result authority. The large Agent review
scratch uses external storage rather than consuming an equivalent inline image
allocation.

Both `CBUS-S-OK` and `CBUS-S-NO-EFFECT` are result-bearing successes. Gateway
accounting, runtime transcript/model context, Scripted, and OpenAI Responses
retain the typed result and the raw status. `NO-EFFECT` is not rewritten as
`OK`, and it does not authorize a second owner commit or component-instance
touch.

Focused boundaries cover exact-full and one-byte-short canonical review,
schema-wide 25,562-byte Library document-create and 43,758-byte
collection-create operands, exact 65,536-byte model calls, exact 32,768-byte
results plus one-byte-over refusal, and the exact 262,144-byte visible-review
expansion with an adjacent sentinel. Facet tests likewise prove the known
23-row set, the valid 24th entry, and an atomic `CFACET-S-FULL` refusal for the
25th.

## Green evidence

The emulator profiles below ran sequentially with unchanged timing and
checked-in step ceilings.

| Evidence | Result | Measured execution | Free sectors |
| --- | --- | --- | ---: |
| `agent-context` | PASS, 121 assertions | 892,207,867 steps; 28.51 s | 3,072 |
| `agent-control-plane` | PASS, 53 assertions | 1,608,275,704 steps; 42.99 s | 2,144 |
| Library create boundary | PASS, 125 assertions | 4,533,797,656 steps; 117.76 s | 4,420 |
| Host packaging and functional-ledger checks | 72 passed | 4.33 s | n/a |
| Architecture inventory check | PASS | 1.48 s | n/a |
| Architecture ratchet tests | 17 passed | 13.05 s | n/a |

Earlier green regression evidence retained on the current branch is:

| Evidence | Result | Measured execution | Free sectors |
| --- | --- | --- | ---: |
| OpenAI provider | PASS, 190 assertions | 846,486,984 steps; 22.98 s | 2,635 |
| Agent | PASS | 1,368,684,686 steps; 37.01 s | 1,414 |
| L7 Agent actions | PASS, 123 assertions | 2,842,062,656 steps; 67.28 s | 1,186 |

The canonical 4 MiB Desktop build contains 185 modules in 22 chunks and 51
entries. It has 2,188 free sectors, 140 above the unchanged 2,048-sector
reserve.

## Non-evidence and remaining boundary

A two-core `agent-security` attempt is recorded only as non-evidence. With its
unchanged nine-billion-step cap it reached 1,163,500,000 steps and timed out at
900.63 seconds before boot. It produced no pass/fail result and is not cited as
qualification. Future two-core runs should be restricted to concurrency,
race, and locking assertions, or to a separately justified final
qualification where the added cost answers a real multi-core question.

The exact-full durable snapshot path is not claimed. There is no cheap fixture
for persisting that boundary through the real dual-generation store; the
existing 512 KiB VFS fixture would require meaningful enlargement to retain
both generations. Checkpoint 2 does not raise that storage fixture or the
262,144-byte snapshot ceiling merely to manufacture an exact-full persistence
claim. The reviewed control-plane boundary is qualified; exact-full durable
snapshot evidence remains open.

Host storage was not a design constraint: about 3.7 GiB remained free and the
local artifacts occupied about 41 MiB. No functionality, authority, or test
coverage was reduced in response. No emulator timing, checked-in test ceiling,
MP64FS reserve or geometry, MegaPad source, or TLS code changed.

## Exit

Checkpoint 2 establishes the bounded Desk/Practice/Agent authority and review
control plane needed by the slice. Checkpoint 3 starts with the Streams-owned
Burrow manager, lifecycle, retry, cleanup, and visible applet state. Normal
Desk composition and the exact nine-row focused operator facet remain
Checkpoint 4 work under the Checkpoint-0 contract.
