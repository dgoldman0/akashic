# Acknowledged instrument reuse

Instrument snapshots now own the used region descriptors, instrument records,
source correlations, and unit text alongside the existing control/glyph target.
Both bank capacities include these sections, using the caller's existing
instrument and data-graphics bounds with checked arithmetic. No applet or UIDL
capacity annotation is introduced.

The packed instrument `UNIT-A` field holds an offset into that bank's unit
bytes, including zero for an empty unit. Source spans and unit slices must fit
before the target's validity marker can be published. Source scratch can then
be overwritten without changing the acknowledged payload, and moving a packed
bank requires no instrument pointer rebasing. Promotion still occurs only at
the existing physical acknowledgment boundary.

An unchanged instrument graph can now remain acknowledged while controls or
residual glyphs change. Reuse requires the same canonical source identities
(including mounted source generation), region geometry and clipping, complete
instrument payloads, and unit text. Fresh candidate IDs are normalized to the
acknowledged IDs only after this proof. Delayed publication rechecks the same
payload and exact normalized IDs against the attempt-bound banks.

Glyph append and tombstone repacking account for instruments in the object
namespace and bank storage. Only physical publication advances the object
frontier. The existing certified-unchanged shortcut also retains the packed
instruments while emitting its ordinary control/glyph revision fence.

Changed instrument values, style, geometry, lifecycle, or membership still
require complete replacement. An instrument-only frame without a control or
glyph revision carrier also takes that path. Incremental instrument updates
are outside this slice; no terminal ABI or applet API changes are required.

`local_testing/test_rich_instrument_reuse.py` executes the production packing
and sizing helpers on Python and native semantic backends. It checks copied
bytes, independent text slices, source overwrite, empty families, overflow,
short and misaligned sources, invalid unit pointers, and guarded caller bounds.
It also executes complete production delta planning, header validation,
normalization, delayed binding, glyph growth/shrinkage, unchanged cloning,
and repeated target promotion. Changed payloads and stale attempts refuse
reuse without modifying the acknowledged bank. The provider publication
units check that unchanged instrument objects, regions, and text remain
charged during mixed control/glyph deltas.
It starts no Desktop or viewer and uses the existing 3,000,000-step helper
watchdog. These units are not physical acceptance or Desktop timing evidence.

The sequential focused selector passed 320 checks in 16.42 seconds, covering
this file's executable units plus the producer, control map, glyph growth,
publication frontier, menu damage, and provider glyph publication selectors.
The subsequent [physical Desktop qualification](../../local_testing/evidence/instrument-reuse-20260916.md)
passed with 26 ACKs, 21 inputs, and 18 milestones. Instrument-live View and Go
menu opening changed from about eight seconds to about three in the matched
single-run observations; updates shrank from roughly 170 KB to 3–5 KB. Baseline
typing remains about 2.6 seconds. These are physical trace observations, not
inferences from helper timing or hardware-panel claims.
