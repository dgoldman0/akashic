# Library applet

Library is a Desk applet and corpus owner. Its renderer-free modules are
independently testable, but they are not a standalone Library product.

The executable lens can browse and search active, archived, or all documents;
page forward and backward; preview bounded content; create a managed document;
rename, archive, and unarchive it; browse and filter collections; and inspect
retained content history. An uncertain create remains an exact prepared
request: retry reuses its operation key and bytes instead of manufacturing a
second document.

The applet-owned code is divided by responsibility:

- `model.f` and `document-values.f` define and prepare Library values;
- `index-keys.f` and `persistence-adapter.f` map those meanings onto neutral
  checked pages, ordered indexes, immutable chunked blobs, reclamation, and
  compaction;
- `repository.f` alone selects `/library/*` topology and owns physical
  lifecycle and recovery;
- `query.f` and `service.f` expose semantic keyset pages, commands, exact
  reads, maintenance, and bounded content delivery;
- `projection-adapter.f` provides activation-local resource projections; and
- `controller.f`, `view.f`, and `library.f` own applet state, rendering, input,
  and lifecycle composition.

Documents, collections, and collection membership are indexed populations,
not fixed catalog arrays. Content is chunked and streamable; queries and
compaction use caller-supplied bounded working sets. Multi-index mutations
stage according to actual page/reclamation room and advance the logical
generation once. The prototype has one current layout and no legacy decoder,
compatibility facade, or migration stack.

Pad routing, capture import, destructive tombstoning, restore/compare,
maintenance, and raw export are implemented service capabilities but remain
deferred applet UI work. The source-defined bootstrap identity only reopens
this development corpus; it is not an account, profile, or migration policy.

See the [domain notes](domain.md) and
[applet notes](../../../../docs/tui/applets/library/library.md).
