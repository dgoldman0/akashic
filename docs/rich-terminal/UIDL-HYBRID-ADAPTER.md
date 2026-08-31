# UIDL hybrid aggregate adapter

`tui/rich-terminal/uidl-hybrid-adapter.f` observes the ordinary completed
UIDL-TUI draw boundary. For every visible attached UCTX it freezes both the
existing renderer-neutral menu forest and any semantic forests exposed by
ordinary UIDL types or canonical reusable widgets. It does not create an app
scene, own terminal objects, inspect CELL pixels, or call an applet-specific
API. Production applets never register these forests; custom applet panels are
covered automatically by completed-draw residual `GLYPH_RUN`s.

## Collection capture

The adapter makes a second `UTUI-RESOLVED-TREE-EACH` observation after menu
capture for a dirty document. Only effectively visible elements carrying a
complete 72-byte resolved record are candidates. An unbound element is an
ordinary zero contribution. A bound element is captured directly into the
inactive caller-owned native bank with `UTUI-SEMANTIC-CAPTURE`.

Every copied semantic entry is presented once to
`USCOL-VALIDATION-WORK-BYTES` and once to `USCOL-ENTRY-VALIDATE`. The latter is
the sole deep family proof for UTF-8, keys, geometry, item ordering, overlap,
and caret state. Its 48-byte summary is written directly into the same
inactive descriptor bank that will be published. Invalid or unsupported
claims in a known ABI-1 collection family fail the entire candidate. An
unknown future family is validated as unsupported and left unclaimed.

Canonical widget snapshots express a collection root relative to their mounted element. A
120-byte descriptor therefore freezes all of the correlation needed to place
and route it later:

| Offset | Meaning |
|---:|---|
| 0 | ordinary UIDL source element index |
| 8 | provider content revision |
| 16 | UIDL-TUI resolved-state generation |
| 24 | native entry offset relative to this document's native slice |
| 32, 40 | mounted element row and column |
| 48, 56 | mounted element height and width |
| 64 | mounted element z |
| 72 | embedded 48-byte validated family summary |

Descriptors are heapsorted in place by `(source-index, root-key)` and then
checked for strict uniqueness. The native records are never moved by this
canonicalization, so a descriptor's document-relative entry offset remains
stable. Multiple roots from one composite widget are ordinary sibling roots
in that ordering.

## Published ABI 3

Each 112-byte document directory entry retains its menu-record and menu-text
slices and adds descriptor and native-snapshot slices. A document is omitted
only when both its menu and collection forests are empty. The borrowed
112-byte aggregate snapshot publishes all four payload banks:

- UMSN menu records;
- UMSN menu text;
- semantic descriptors;
- captured native semantic records.

`RUHA-INIT` takes caller-provided A/B storage for the descriptor and native
banks in addition to the existing directory, menu, and work spans. Descriptor
capacity is exactly the descriptor bank byte length; native capacity is
exactly the native bank byte length. The adapter allocates neither and rejects
overlap, misalignment, odd bank splits, and invalid fixed-record extents.

The ABI-3 adapter itself is 496 bytes. Its two embedded snapshots begin at
`+272` and `+384`, and each snapshot is 112 bytes. There is no ABI-2 alias.

## Exact clean reuse and content epoch

A clean document can reuse a prior slice only after shallow correlation of
its menu records, descriptor ordering, descriptor-to-native family/root/size
identity, and every caller-owned extent. The adapter copies the prior menu,
text, descriptor, and native slices. It rebases only the UMSN aggregate
generation cells. It does not recall the semantic provider and does not repeat
the family deep validator.

The content epoch is a provenance certificate, not a revision guess or hash.
It carries only if every nonempty document used exact prior-slice reuse, the
document count and complete directory are identical, and all four aggregate
payload byte totals match. Any live menu or collection recapture takes the
ordinary new-epoch path even if the resulting bytes happen to be equal.

## Bounded selectors

The seconds-scale structural selector is
`local_testing/test_rich_terminal_uidl_hybrid_adapter.py`. The target sorter
and byte-preservation oracle is
`local_testing/test_rich_terminal_uidl_hybrid_adapter_target.py`. Neither
selector launches Desk, Pad, Daybook, a renderer, persistence, or a full-core
journey.
