# Observatory

Observatory is an exact-series inspection vertical slice for Desk. It accepts
one immutable Worlds telemetry projection, validates and copies it, computes a
small descriptive profile, and displays source identity, exact extrema,
precision-qualified statistics, a responsive plot, and a deterministic result
digest.

**Provider:** `akashic-tui-observatory`

## Acceptance and ownership

The `observatory.dataset.open` capability is the handler for the
`dataset.analyze` intent. Input is the canonical lowercase-hex request envelope
documented by Worlds. Observatory decodes into a temporary owned buffer and
then validates the projection's version, exact length, schema identifiers,
positive source identifiers, ordered ticks, nonnegative amounts, content
digest, and the provenance fields bound by that digest. The bound source-state
digest is an authenticated Worlds claim; this projection does not contain
enough state for Observatory to recompute it independently. Observatory
profiles a separately allocated candidate series and swaps that candidate into
the active view only after every check succeeds. A refusal preserves the
previous dataset and profile.

This slice consumes a closed Worlds projection rather than pretending to be a
general dataset service. A neutral qualified-locator/resource acquisition
contract, owner routing, durable provenance, and multiple open datasets remain
production work. The closed contract keeps that future change localized at the
capability boundary while exercising current app descriptors, instances,
intents, owned values, request seals, and direct TUI drawing now.

## Numeric contract

Ticks and amounts remain exact 64-bit integers in Observatory-owned storage.
Count, minimum, and maximum are exact. Each amount must round-trip through
FP16 before it is admitted to the current statistics path. Accepted values are
pushed one at a time through the existing online Welford accumulator; mean and
sample standard deviation are displayed as FP16-derived approximations. The
UI states that precision contract instead of presenting them as exact decimal
results. Profiling cycles are diagnostic only and are excluded from the result
digest, so repeated analysis of identical content has identical semantic
output.

## Interaction

`R` reruns the profile from Observatory's owned exact series. The view derives
its plot geometry on each paint, so compact Desk tiles retain source and
profile information while larger regions add the plot. The applet uses direct
drawing because the current canvas mounting path does not yet offer a safe
resize/remount ownership contract.

## Public words

| Word | Stack | Purpose |
|---|---|---|
| `OBS-TS-CONTENT-DIGEST` | `( snapshot destination -- status )` | Recompute the projection content digest |
| `OBSERVATORY-ENTRY` | `( desc -- )` | Fill an application descriptor for Desk |
| `OBSERVATORY-RUN` | `( -- )` | Run Observatory in the shared app shell |

## Slice qualification

`python3 local_testing/test_observatory_worlds_slice.py` exercises the owner
contracts, atomic refusals, branch/replay determinism, corruption detection,
application and capability descriptors, candidate preservation, exact source
identity, request ownership, seal mutation detection, and the direct
Worlds-to-Observatory acceptance path. Presentation APIs are inert adapters in
that focused profile so the test can reach semantic assertions without paying
the complete TUI link closure on every run. The `--full-ui` mode retains the
real presentation closure for a slower linked qualification pass.
