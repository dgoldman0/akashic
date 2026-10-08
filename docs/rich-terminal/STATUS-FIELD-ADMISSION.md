# Structured status admission

`STATUS_FIELD` is a static retained object, separate from numeric instruments
and interactive controls. `RTE-F-STATUS-FIELDS` and
`RTAPT-F-STATUS-FIELDS` are `0x400`; the APT-1 capability is `0x1000`.
The feature requires CORE alone. A status-only profile may have no glyph-run,
instrument, or control capability. Its minimum outbound payload is 96 bytes;
the minimum retained transaction limit is 296 bytes.

The 176-byte `RTE-STATIC` / `RTAPT-STATIC` descriptor contains 22 cells:
owner, generation, ID, kind, visible, z, region, parent, row, column, height,
width, root height, root width, label columns, severity, emphasized, label
address/length, value address/length, and reserved. The initial kind is
`*-STATIC-STATUS-FIELD = 1`. Parent and reserved are zero. Height is exactly
one, width is positive, and visible/emphasized are canonical `0` or `-1`.
Severity is 0 through 4. A nonempty label requires a positive label split;
a nonempty value requires at least one remaining column.

Label and value are independently valid single-line scalar UTF-8. C0, DEL,
C1, U+2028, and U+2029 are excluded. A scalar cannot cross the label/value
boundary. Hidden status fields retain both strings and consume the same
object and text quotas as visible ones.

`RTE-STATIC-DEFINE` and `RTE-STATIC-REPLACE` dispatch the descriptor through
independent facade callbacks. Provider capture owns 176 fixed bytes plus
`align8(label bytes + value bytes)`; source pointers are not retained. A
status consumes one object, one operation, and exactly the combined UTF-8
bytes. Its retained payload is `96 + text bytes`; the complete frame is
`136 + text bytes`. Publication uses `PT-STATUS-FIELD-DEFINE` or
`PT-STATUS-FIELD-REPLACE`.

The 144-byte static plan mirrors the ordinary CONTROL plan header and has
an independent descriptor bank. It shares the base region with controls and
residual glyphs; a static-only hybrid still defines that base region once.
The hybrid wrapper is 144 bytes, appending static plan and byte-bank fields
at offsets 120, 128, and 136. Static byte banks are dense, in descriptor order,
with each label immediately followed by its value. Empty spans are `0/0`.

The checked admission summary appends static count, raw text,
aligned text, maximum item text, last ID, copy bytes, and operation count at
offsets 320 through 368. Copy bytes equal `176 * count + aligned text`;
operation count equals descriptor count. The later FIELD extension grows the
summary to 384 bytes with FIELD-CONTROLS at offset 376, preserving these
static offsets. Object IDs precede residual glyph
IDs and follow instrument IDs. Last IDs are identity bounds, never quotas.

Neutral preflight proves every fixed source, bank, output, and mutable
scratch span disjoint before writing scratch. It traverses each static
bank once to validate descriptors, exact text coverage, and aggregates.
The provider consumes only that fixed summary; aggregate admission does
not revisit caller items or strings. Concrete capture, copied-record audit,
and replay independently enforce the negotiated feature and owned bounds.
The Desk producer may choose full owner replacement for changed status
content; unchanged status participates in ordinary idle reuse.

The ordinary OBJECT ledger retains aggregate object and text reservations,
not per-object historical strings. Direct STATIC-REPLACE uses that existing
OBJECT target/reservation behavior; PT and the host remain the exact sparse
identity, object-kind, and replacement text-quota authorities. The Desk
publisher uses full owner replacement whenever a status changes, so its
new text total is exact and an aborted candidate preserves the old owner.
No per-static identity ledger is introduced in this slice.
