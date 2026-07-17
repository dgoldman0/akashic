# Library applet placeholder

Status: Gate 1 documentation only. There is no Library applet descriptor,
UIDL, manifest, runtime module, capability, handler, or store in this package.

The future Library applet is the human lens over the Library domain described
in [`../../../library/library.md`](../../../library/library.md). It may browse,
search, preview, organize, archive, import, export, and inspect exact Library
resources after the headless owner is qualified. It does not own the corpus
merely because it presents it, and it does not become a second text editor.
Managed documents open in Pad for deep editing; captures open read-only unless
the user deliberately derives a separate managed document.

UI selection, filters, sort order, preview state, and History position are
local lens state. A future consequential request must name the stable Library
RID and exact expected domain revision (or the sealed create/import
precondition and idempotency key). “Selected row,” “current preview,” and
“latest” are never mutation targets for Agent-visible, scheduled, or routed
operations.

The first standalone UI is intended to expose bounded All, Recent, Archived,
Collections, History, search, create/import, preview/details/provenance,
metadata, revision compare/restore-as-new, archive/unarchive, export, and
exactly confirmed tombstone workflows. Those are target requirements, not
implemented behavior in Gate 1. Streams collection, general Pad semantic tabs,
Explorer origins, and Desk routing wait for their ordered interoperability
gates.
