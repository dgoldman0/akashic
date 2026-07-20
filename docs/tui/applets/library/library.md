# Library applet

Status: an intentionally bounded user-experience probe is implemented over the
qualified headless Library owner. It makes the owner useful enough to test real
browsing and document-management flows, but it does not claim completion of
Gate 5. Gate 4's projection and maintenance contracts are independently
implemented and qualified; this probe does not silently turn them into UI or
integration behavior.

The applet is a human lens over the Library domain described in
[`../../../library/library.md`](../../../library/library.md). It is a
single-instance standalone applet, owns only activation-local view state, and
calls the public Library owner API. It does not infer or open `/library` paths,
parse the private store, retain a second authoritative catalog, or import
sibling applet/domain internals.

## Implemented probe

The default Active view presents one bounded corpus page and one local row
selection. The user can:

- reload authoritative state and page forward or backward;
- browse Active, Archived, or All records;
- run the current exact, case-sensitive Library search or clear it;
- list collections, select one, and apply its exact RID as a corpus filter;
- create a managed text document and rename the selected record's title;
- archive an active record or unarchive an archived record; and
- inspect the selected managed document's retained content-revision history,
  then return to the preceding corpus or collection view.

The body, selection, search term, lifecycle filter, collection filter, paging
cursor, and history position are local lens state. Mutation calls copy the
selected summary's stable Library RID and exact domain revision into the
immediate public owner request. Selection itself is never exported as ambient
mutation authority.

This slice intentionally does not make the applet a text editor. Initial
managed content is collected through the applet's bounded prompt flow, while
deep editing through Pad waits for typed Gate 6 interoperation over the
qualified projection owner. History is retained-content inspection only: it
does not restore, compare, or mutate a historical revision.

## Creation and retry

A create first becomes a protected prepared request with its generated
operation key before first-use provisioning begins. Before the request reaches
the mutation API, the applet authoritatively reloads the owner, provisions only
after a fresh `ABSENT` result, and seals the resulting catalog generation. Once
dispatched, `Retry Pending Create` resubmits that same operation key and
byte-identical request, allowing the owner's idempotency contract to return the
original document instead of manufacturing a duplicate. It does not rebuild a
dispatched request from current prompts or treat matching content as identity.
Starting a distinct create uses a new operation key.

The applet reports conflicts, capacity limits, invalid requests, unavailable
history, and blocked/recovery states rather than converting them into an empty
view or optimistic success. Reload is an explicit authoritative refresh; it
does not retry a pending mutation implicitly.

## Development arena identity

The standalone probe provisions and reopens one corpus with a fixed,
source-defined development arena ID. Keeping that value stable makes repeated
boots of this development applet address the same already-provisioned corpus.
It is not a user ID, account ID, configurable library selector,
synchronization identity, or durable migration scheme. Changing it while old
Library storage is present is expected to conflict rather than adopt or
rewrite that corpus. A production identity/provisioning policy must be designed
separately.

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
| Ctrl+Q | Quit the standalone applet |

Active/Archived/All, Collections, Archive/Unarchive, and About are also
available from the menu bar.

## Deliberately deferred

The probe does not implement Pad/projection integration, capture import, VFS
import, export/raw-export UI, provenance/details surfaces, maintenance/repair
UI, revision compare or restore-as-new, destructive tombstones, Desk routing,
Explorer reveal, Streams collection, capabilities, or Practice bindings. It
also does not promise semantic ranking,
normalization, unbounded results, multi-library selection, or multiple
concurrent applet instances.

Those omissions are active boundaries. The purpose of this early applet is to
discover whether the public headless shapes support a coherent user workflow;
any pressure to bypass the owner or duplicate durable state is evidence for a
backend contract change, not permission for a UI-only workaround.
