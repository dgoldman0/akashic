# Library domain package placeholder

Gate 1 reserves this directory for the future Library domain. It intentionally
contains no Forth module, store, codec, schema, capability, projection owner,
or runtime initialization.

The provisional later modules are `model.f`, `catalog-store.f`,
`content-store.f`, and `index.f`. Their names are not stable until the focused
Library gate. Corpus identity, revisions, metadata, collections, provenance,
archive/tombstone lifecycle, index policy, imports, and concrete projection
adapters stay in this package. This package must not depend on sibling domains
or applet internals.

See [`../../docs/library/library.md`](../../docs/library/library.md) for the
product and current-boundary contract.
