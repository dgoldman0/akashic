# Worlds

Worlds is a deterministic facility-model vertical slice for Desk. It owns one
two-reservoir run and makes the run's revision, branch identity, journal, exact
state digest, and telemetry visible alongside the model. The slice is
session-only: it qualifies owner semantics and applet interaction without
claiming durable world storage or a general simulation engine.

**Provider:** `akashic-tui-worlds`

## Owner contract

`run.f` is independent of TUI state. The caller supplies the run structure,
journal, telemetry, checkpoint, and their capacities. An action must present
the current revision and either commits completely or leaves state, revision,
journal, and digests unchanged. The current actions are fixed-step transfer,
valve setting, checkpoint, and branch creation. Replay reconstructs a run from
its canonical checkpoint and journal and rejects a corrupt record or digest.

The demonstration configuration reserves 64 journal transitions and 65
telemetry samples. That is a declared applet horizon, not a limit embedded in
the owner API. Auto-run uses wall time only to request the same fixed semantic
step that the `S` key requests; elapsed wall time never changes the model
result.

## Analyze handoff

`A` constructs `org.akashic.worlds.telemetry.upper.v1`, a closed canonical
binary projection. Its big-endian header identifies the owner, run, branch,
revision, tick and amount schemas, scale, count, content digest, and source
state digest. Samples are ordered `{tick, upper_amount}` records. Observatory
validates the complete projection and content digest before it publishes a new
active series. That content digest binds the complete provenance header and
supplied source-state digest; Observatory authenticates that claim but cannot
independently reconstruct the complete Worlds state from this projection.

The current typed-IVJSON request seal intentionally has no representation for
`CV-T-BYTES`. Worlds therefore carries the binary projection as canonical
lowercase hex in an owned `CV-T-STRING`. The envelope bound is derived from
the request bus's canonical representation bound, and Observatory rejects odd,
uppercase, or non-hex input before decoding. This is a truthful compatibility
adapter around exact bytes, not a replacement for the eventual neutral
resource contract. A production iteration should decide whether immutable
dataset projections become owner-resolved qualified resources or whether the
seal format gains a native canonical byte representation.

Desk can currently resolve the `dataset.analyze` intent only for an installed,
live handler. Launch Observatory once before using Analyze. Catalog discovery
does not yet install a dormant applet's intents, so Worlds reports that
limitation instead of claiming cold auto-launch.

## Keys

| Key | Action |
|---|---|
| `S` | Commit one fixed semantic step |
| Space | Run or pause fixed-step requests |
| `V`, Left, or Right | Select the next valve setting |
| `C` | Record a canonical checkpoint |
| `B` | Create a new branch from the current revision |
| `R` | Replay and verify the checkpoint and journal |
| `A` | Send an immutable telemetry projection to Observatory |
| Ctrl+Q | Quit standalone Worlds |

## Public words

| Word | Stack | Purpose |
|---|---|---|
| `WRUN-INIT` | `( journal journal-cap telemetry telemetry-cap checkpoint run-id run -- status )` | Initialize one caller-owned run |
| `WRUN-STEP` | `( expected-revision run -- status )` | Commit one fixed transfer |
| `WRUN-VALVE-SET` | `( milliunits expected-revision run -- status )` | Commit a valve revision |
| `WRUN-CHECKPOINT` | `( expected-revision run -- status )` | Capture the replay base |
| `WRUN-BRANCH` | `( branch-id expected-revision run -- status )` | Begin a branch-local revision line |
| `WRUN-REPLAY` | `( destination source -- status )` | Reconstruct and verify a run |
| `WORLD-TELEMETRY-SNAPSHOT` | `( run destination capacity -- bytes status )` | Build the exact analysis projection |
| `WORLDS-ENTRY` | `( desc -- )` | Fill an application descriptor for Desk |
| `WORLDS-RUN` | `( -- )` | Run Worlds in the shared app shell |
