# UIDL hybrid aggregate adapter

`tui/rich-terminal/uidl-hybrid-adapter.f` observes the ordinary completed
UIDL-TUI draw boundary and freezes the renderer-neutral menu forest for every
visible attached UCTX. It does not create an app scene, inspect CELL pixels,
or call an applet-specific API. Pad, Daybook, Desk, and every other applet are
clients of this lower path; none registers a rich-terminal or semantic
provider.

Custom widgets and panels require no adapter. Anything not represented by an
ordinary core UIDL semantic type remains visible through the residual
projection of the completed draw as coalesced `GLYPH_RUN`s. CELL remains the
complete fallback.

## Published ABI 2

Each 80-byte document directory entry identifies one visible document and its
slices in the UMSN menu-record and menu-text banks. A document with no menu
controls contributes no entry. The borrowed 80-byte aggregate snapshot
publishes only:

- the document directory;
- UMSN menu records; and
- UMSN menu text.

`RUHA-INIT` takes caller-provided storage for lifecycle records, capture work,
work text, and A/B directory, menu-record, and menu-text banks. Its checked ABI
is 2 and the adapter is 384 bytes. There are no descriptor/native-collection
banks in this ABI and Desk must not pass or reserve them.

The absence of a native collection bank is deliberate. Optional structured
semantics may be added only after the neutral record/builder layer sits below
both UIDL-TUI and the canonical widget library, and a core widget type supplies
the semantics automatically. It must not be reintroduced as applet-owned
callbacks or provider registration. Until that lower seam exists, collection
capability bit 9 remains off.

## Exact clean reuse and content epoch

A clean document may reuse a prior menu slice only after validating its
caller-owned extents and every copied UMSN record. The adapter copies the prior
record and text slices and rebases only UMSN aggregate-generation cells.

The content epoch is a provenance certificate, not a revision guess or hash.
It carries only when every nonempty document used exact prior-slice reuse, the
document count and complete directory are identical, and the aggregate record
and text byte totals match. Any live recapture takes the ordinary new-epoch
path even if its bytes happen to be equal.

## Bounded selector

`local_testing/test_rich_terminal_uidl_hybrid_adapter.py` is the seconds-scale
structural selector for this ABI. It does not launch Desk, Pad, Daybook, a
renderer, persistence, or a full-core journey.
