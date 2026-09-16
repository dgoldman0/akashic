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

This storage slice does not yet enable instrument DELTA or unchanged-frame
reuse. Their conservative replacement behavior remains in place until exact
identity comparison, normalization, and delayed publication are implemented.

`local_testing/test_rich_instrument_reuse.py` executes the production packing
and sizing helpers on Python and native semantic backends. It checks copied
bytes, independent text slices, source overwrite, empty families, overflow,
short and misaligned sources, invalid unit pointers, and guarded caller bounds.
It starts no Desktop or viewer and uses the existing 3,000,000-step helper
watchdog. These units are not physical acceptance or Desktop timing evidence.
