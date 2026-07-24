# Neutral two-bank compaction

`akashic/persistence/compaction.f` coordinates a bounded offline rebuild from
one physical data bank into the other. It is neutral infrastructure: the
module does not know which records are live, how indexes are keyed, what an
application-root page contains, or which retention rules a consumer applies.
Those decisions remain in consumer callbacks.

This is the prototype's one current compaction design. It does not introduce a
format-version ladder, a legacy reader, a migration service, or a phase
journal.

## Topology and ownership

The caller owns:

- one shared `PROOT-FILE-SIZE` descriptor with both page/segment banks
  configured;
- one unloaded staging `PSTORE-SIZE` descriptor and one
  `PSTORE-WORK-SIZE` workspace;
- private root A/B paths for that staging store;
- the staging workspace's segment buffer and all ordinary store dependencies;
- one `PCOMPACT-SIZE` immutable configuration descriptor;
- one `PCOMPACT-WORK-SIZE` mutable operation descriptor;
- the bounded staging segment buffer supplied when the work is initialized;
  and
- the step/finalize callbacks and their opaque context.

The staging store's bank-zero and bank-one page/segment descriptors must name
the same VFS and exact physical paths as the corresponding shared banks. Its
root paths must be distinct from both shared root paths. The shared root,
staging store, staging workspace, configuration, work object, staging segment
buffer, and every embedded dependency must satisfy the published non-aliasing
checks.

`PCOMPACT-BEGIN` loads shared authority, records its exact root snapshot,
computes the exact next shared generation, and selects the inactive bank as
the target. It first mirrors the source snapshot into both shared root slots.
Only after that root fence is durable does it reset the staging store's
private roots, select and clear the inactive physical bank, provision it, and
open the staging transaction surface.

The staging descriptor becomes a loaded private store during a build.
Completed operations leave their work in `CLEANED`; the same coordinator,
staging descriptor/workspace, private root pair, and cleaned operation work
may then run the opposite direction. `PCOMPACT-BEGIN` performs the guarded
private-root reset itself. A transaction-active or otherwise busy builder
fails before either private root is removed. Shared readers and writers must
be externally serialized for the complete offline operation; the coordinator
deliberately owns no process-global lock or hidden operation state.

## Configuration and budgets

```forth
PCOMPACT-INIT
\ ( shared-root builder-store builder-work step-xt finalize-xt context
\   byte-budget work-budget step-byte-budget compact -- status )

PCOMPACT-WORK-INIT
\ ( segment-buffer-a segment-buffer-u work -- status )
```

`byte-budget` is the maximum total application bytes the step callback may
report. `work-budget` is the maximum number of successful step calls.
`step-byte-budget` is the maximum allowance passed to one call and cannot
exceed the total byte budget. All three are positive.

The operation exposes inspectors for state, status, source and target banks,
exact next generation, accumulated bytes/work, captured source and target
roots, and cleanup eligibility. Returned root spans are borrowed from the
operation work object.

## Consumer callbacks

The step callback has this ABI:

```forth
( source-root builder-store builder-work byte-allowance context
  -- done? bytes-used status )
```

It copies at most one bounded opaque unit from the immutable source snapshot
into the private staging store. A successful result may report no more than
the supplied allowance or the remaining total byte budget. Only a successful
call advances the byte and work counters. Over-reporting returns
`PERSIST-S-CAPACITY`; a thrown callback returns `PERSIST-S-FAULT`. Neither
case changes shared authority.

The finalize callback has this ABI:

```forth
( exact-next-generation builder-store builder-work context -- status )
```

It writes the target application root for the exact next shared generation.
For generation-bound neutral metadata, a consumer can use
`PBTREE-ROOT-REBASE` and
`RECLAIM-EMPTY-STATE-FOR-GENERATION`. Private staging commits may use any
number of provisional generations; they do not dictate the shared
generation.

## State and publication fence

The ordinary sequence is:

```text
IDLE -> BUILDING -> READY -> FINALIZED
     -> PUBLISHED -> MIRRORED -> CLEANED
```

`PCOMPACT-STEP` remains in `BUILDING` until the callback reports done, then
enters `READY`. `PCOMPACT-FINALIZE` invokes the consumer finalizer, reloads
shared authority, and refuses to continue if the selected source snapshot
changed. It then captures the staging store's validated physical root as the
target.

`PCOMPACT-PUBLISH` publishes that target to the inactive shared root slot at
the exact next generation and selected target bank. A no-effect publication
failure leaves the source authoritative. A maybe-effect result enters
`UNCERTAIN`; recovery must inspect durable roots. A post-durability fault may
return non-OK while the target is already authoritative, following the same
root-outcome contract as ordinary store publication.

`PCOMPACT-MIRROR` writes the selected target snapshot byte-for-byte into the
other root slot without advancing its generation. `PCOMPACT-CLEANUP` reloads
the target, requires both slots to contain the exact target generation and
bank, explicitly protects the currently selected bank, and only then
truncates and syncs the old page and segment files.

`PCOMPACT-ABORT` is available only before publication. It reloads authority
and refuses to clear a bank if that bank is selected. It never reports that
published data was rolled back.

## Crash recovery

`PCOMPACT-RECOVER` is safe on a freshly initialized work object and derives
the result solely from independently checked shared root slots:

- A partial prepublication rebuild selects the source, mirrors it if needed,
  and clears the inactive partial target.
- A crash after target publication but before root mirroring selects the
  target, mirrors that exact snapshot, then clears the old source bank.
- A crash after mirroring but during old-bank truncation revalidates both
  exact root observations and completes old-bank cleanup.

Recovery never clears the selected bank. Equal-generation divergent roots,
unconfigured banks, invalid physical bounds, or an authority change fail
closed. No private staging root or in-memory phase flag is treated as durable
authority.

After a completed cutover, a cold consumer configures both banks and uses
`PSTORE-OPEN-ACTIVE`. That operation performs one checked shared-root load,
adopts the selected configured bank, and opens only the physical files named
by that root.
