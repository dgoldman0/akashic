# Library applet

Library is a single-instance Desk lens over the applet-owned semantic service.
It owns activation-local view and working state, not a second catalog or
storage implementation. The controller never discovers `/library/*` paths or
uses a selected row as ambient mutation authority.

## Implemented lens

The default Active view presents one bounded semantic page and a local
selection. The user can:

- reload authoritative state and page forward or backward;
- browse Active, Archived, or All documents;
- run exact, case-sensitive title/body/tag search or clear it;
- list collections and filter the corpus by an exact collection RID;
- create a managed text document and rename its title;
- archive or unarchive it; and
- inspect its retained content-revision history.

Selection, search text, filters, keyset continuation, preview offset, and
history position are lens state. A mutation copies the selected summary's
stable RID and exact domain revision into a service request. Pages carry
semantic creation/revision keys rather than persistence cursors, so unrelated
mutations do not invalidate navigation.

Preview is deliberately bounded: the controller reads a prefix into its
activation working set while retaining the complete content size. The service
can deliver larger content by bounded range or stream; this applet is not a
deep editor.

## Creation, reopen, and blocked state

A create becomes a complete prepared request with its generated operation key
before provisioning or dispatch. `Retry Pending Create` resubmits that exact
request. It neither rebuilds a request from changed prompts nor treats equal
content as equal identity.

Initialization opens the existing repository before considering first-use
provisioning. A later applet activation reconstructs its first page, selection,
exact target revision, and preview from durable Library authority. Corrupt or
checksummed-future authority remains visibly blocked and nonwritable; it is not
presented as an empty new corpus. `UNCERTAIN` is an operation/cleanup result or
in-memory compaction state, not a durable cold-open mode. Reload is an explicit
authoritative refresh and never implicitly retries a pending mutation.

The source-defined bootstrap ID makes development activations address the same
prototype corpus. It is not a user, account, synchronization, or migration
identity. The current prototype has one storage layout and no compatibility or
legacy reader.

## Public capability surface

The live `org.akashic.library.applet` component owns five typed capabilities:
status, managed-document create, collection create, exact collection-scoped
document query, and exact collection-scoped document read. They execute over
the same activation-local service and repository as this lens. There is no
headless duplicate Library, capability-only catalog, raw service-pointer
escape, or ambient selected-row authority.

Status does not provision an absent Library. The two creates derive resource
and operation identities independently from the invocation, preserve Library's
logical-generation and domain-revision rules, and distinguish a fresh write
from exact no-effect replay. Query and read verify the supplied collection RID,
current collection revision, existing request seal, and membership inside the
Library owner before publishing a result. They are suitable for a separately
attenuated read-only projection; they are not automatically exposed to an
ordinary Agent facet.

Capability create accepts the complete existing 4 KiB managed-text authoring
window. Capability read materializes up to the existing 65,536-byte Library
content window and returns precise output-capacity failure above it. Larger
Library values remain available through the service's bounded range/stream
interfaces; neither capability bound limits durable corpus population or
removes those service operations.

## Commands

| Key | Action |
| --- | --- |
| Ctrl+R | Reload authoritative Library state |
| Ctrl+F | Search the current corpus scope |
| Ctrl+Shift+F | Clear search and restart at the first page |
| Ctrl+N | Create a managed document |
| Ctrl+Shift+R | Retry the exact pending create request |
| F2 | Rename the selected record's title |
| Ctrl+H | Inspect retained content history for the selected managed document |
| Backspace | Return from History or Collections |
| Page Up / Page Down | Move to the previous or next bounded page |
| Shift+Up / Shift+Down | Scroll the selected item's content preview |
| Ctrl+Q | Quit the executable lens |

Active/Archived/All, Collections, Archive/Unarchive, and About are also
available from the menu bar.

## Deferred UI and integration

The service already owns capture import, tombstones, retained restore/compare,
inspection, mirror repair, coherent raw export, and bounded compaction. The
current lens does not expose those operations. Pad/projection routing, Explorer
reveal, Streams collection, Practice bindings, multi-library selection, and
multiple concurrent applet instances also remain separate work.

Search remains exact and case-sensitive; there is no normalization, semantic
ranking, OCR, embedding search, or unbounded result materialization. Pressure
to bypass the service or duplicate durable state is a backend-contract issue,
not permission for a UI-only workaround.

See [`domain.md`](domain.md) for the ownership, storage, scale, and failure
boundaries.
