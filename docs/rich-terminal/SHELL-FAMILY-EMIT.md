# Immutable family emission

`akashic/tui/rich-terminal/shell-family-emit.f` provides
`RTE-FAMILY-BATCH-EMIT ( admitted-immutable-batch shell -- status )`.

The caller first obtains successful `RTE-FAMILY-BATCH-PREFLIGHT` for the same
immutable, caller-owned batch and begins a complete retained replacement.
The batch, its catalog, every family plan, item bank, text/sample bank and
glyph reference bank must remain unchanged throughout capture. The helper
does not allocate storage or open, begin, seal, cancel or publish a transaction.

Before writing private scratch, it proves the complete source graph is
disjoint from its module, the neutral family validators, both facades and the
provider's storage. It repeats bounded catalog membership validation before
the first provider call. This check is not a substitute for aggregate semantic
and quota admission.

Every catalog region is defined exactly once. Families then emit in their
supplied admitted order: the CONTROL prefix keeps its hierarchy and IDs,
SERIES precedes instruments that reference it, and ordinary object IDs remain
monotone. The helper never invents or reorders geometry. PANE uses the shell
facade; CONTROL, INSTRUMENT, STATIC and SERIES use their ordinary base-facade
writers. GLYPH-RUN creates a temporary descriptor from the catalog owner,
plan region, exact item fields and dense text reference. The provider owns
the copied representation before the call returns.

On success the caller still owns an open capture. On any non-OK result it
must cancel the whole candidate, even when a prefix was already captured.
There is no implicit retry or legacy fallback after emission begins. Emission
callback throws become `RTE-S-INVALID`; ordinary non-OK statuses are preserved. Temporary
borrowed pointers and the glyph descriptor are cleared on success and failure.
Early authority refusal changes neither borrowed data nor private scratch.

The companion `RTE-FAMILY-EMIT-STORAGE-DISJOINT? ( address bytes -- flag )`
allows composition to exclude the emitter's private storage from its own
banks before construction.
