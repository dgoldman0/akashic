# L8 Library re-homing and decomposition

Landing L8 moves the remaining Library-specific implementation beneath its
Desk applet and divides the two previous monoliths by responsibility. It does
not replace Library, turn it into an independent product, change a user action,
raise a corpus limit, introduce a compatibility layer, or begin the scalable
storage replacement planned for L10-L12.

## Resulting ownership

All Library semantics now live under `akashic/tui/applets/library/`:

- `model.f`, `record-codec.f`, and `store-format.f` own the bounded current
  records and deterministic fixed-store formats;
- `repository.f` alone owns `/library/*`, durable authority, fixed-bank
  transactions, recovery, and activation-local index storage;
- `query.f` owns current corpus and collection query policy;
- `service.f` exposes the existing document, capture, history, collection,
  inspection, repair, and raw-evidence operations;
- `projection-adapter.f` adapts exact Library RIDs to the neutral resource
  owner-pool and resource-contract mechanisms;
- `controller.f` owns activation state and actions, `view.f` owns rendering and
  panel input, and `library.f` is only lifecycle/composition.

The old `akashic/library/` and `docs/library/` packages are deleted. No loader,
facade, alias, duplicate repository, or legacy decoder remains at those paths.
Renderer-free profiles still load the applet-owned model/service modules
directly because that is a testability boundary, not a product identity outside
Desk.

The workspace Desk ecosystem contract now names the realized L7/L8 applet
paths instead of its earlier provisional top-level packages. The retained Gate
0 manifest chains that placement-only reconciliation from the prior contract
hash and records that it changes no production behavior.

## Preserved behavior

The split is token-preserving where responsibility was separated. Every
definition and string from the former `vfs-store.f` occurs exactly once across
`repository.f`, `query.f`, and `service.f`; every definition and string from
the former applet implementation occurs exactly once across `controller.f`,
`view.f`, and `library.f`. The existing public `LIBRARY-VFS-STORE-*` vocabulary
is retained as the current Library service ABI, not as an old-path
compatibility facade.

The Library applet characterization grows from 70 to 162 guest assertions. It
drives the controller paths named by L1 for lifecycle scopes, search and clear,
collection filtering and return, paging and conflicts, authoritative reload,
prepared-create failure and byte-exact retry, rename, history, archive,
unarchive, close, and discard. Direct service/private calls in that fixture are
limited to deterministic owner setup, exact fault injection, and controller
paths whose UI wrapper adds no state transition under test; the fixture does
not claim every callback wrapper. This closes the L1 `library.controller-edges`
prerequisite and promotes `library.applet-surface` to covered without adding or
removing a product feature.

## Temporary L12 seams

This landing exposes, rather than disguises, coupling in the fixed current
backend. Every cross-file private reach is marked `L12-DELETION` in source and
listed exhaustively in `akashic/tui/applets/library/domain.md`:

- repository-private fixed-bank, transaction, locator, validation, and index
  families currently reached by query or service;
- the service owner-span sentinels spanning current model/codec/format/store
  private state;
- five fixed-format offsets used by the repository;
- the projection adapter's current storage-shaped service calls; and
- the controller/view/lifecycle private-state reaches that precede the L9/L12
  host and paged-view boundaries.

They are scaffolding for one current implementation, not parallel authorities.
L12 must delete them with the fixed bank/arena backend after the scalable
repository has complete semantic and fault parity. No migration or format
version stack is required for this unreleased prototype.

## Qualification

The focused qualification consists of the model/codec, store-format,
repository/service, query, projection-owner, and 162-assertion applet profiles;
all Library two-process cold/reopen and efficiency drivers; packaging and
source-boundary checks; both refactor ratchets; and the normal host practical
gate. These use the existing MP64FS/generic-VFS fixtures. Ext4 support is not a
prerequisite, and this landing does not change a storage format, capacity, or
filesystem backend.

The final focused profile results are:

| Profile | Assertions | Guest steps |
| --- | ---: | ---: |
| model/codecs | 336 | 447,185,784 |
| store format | 173 | 309,592,967 |
| repository/service | 400 | 1,696,292,193 |
| managed document | 169 | 1,715,071,819 |
| managed lifecycle | 226 | 2,442,022,009 |
| capture/collection | 153 | 2,082,290,760 |
| query/index | 587 | 2,228,560,732 |
| managed capacity | marker-only pass | 5,164,063,233 |
| projection owner | 723 | 4,118,727,074 |
| maintenance | 221 | 1,851,033,801 |
| applet controller | 162 | 3,164,238,393 |

The managed, lifecycle, query, and projection two-process drivers pass with
only serialized MP64FS evidence crossing the process boundary. The literal
Gate 4 exit also passes clean reopen plus damaged-head, selected-bank,
content-frame, and checksum-valid future-head branches with byte-preserving raw
export. The query efficiency driver passes its empty, one-64-KiB, and 32×4-KiB
shapes and all warm/cold budgets; projection passes every unchanged-call,
8-owner, and 64-lease bound; maintenance passes representative and content-bound
inspect/raw-export budgets. No threshold was changed or retried. The host
practical gate passes 207 tests. The architecture ratchet is
392 modules / 1,311 resolved edges / 78 reviewed unresolved imports / zero
cycles / one pre-existing L9 layer violation / zero placement debt; the
functional ledger is 13 covered, 14 partial, and two prerequisite-only groups.
