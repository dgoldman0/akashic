# UIDL hybrid aggregate adapter

`tui/rich-terminal/uidl-hybrid-adapter.f` observes the ordinary completed
UIDL-TUI draw boundary and freezes the renderer-neutral menu and canonical
widget-collection models for every visible attached UCTX. It does not create
an app scene, inspect CELL pixels, or call an applet-specific API. Pad,
Daybook, Desk, and every other applet are clients of this lower path; none
registers a rich-terminal or semantic provider.

Custom widgets and panels require no adapter. Anything not represented by an
ordinary core UIDL semantic type remains eligible for the residual projection
of the completed draw. CELL remains the complete fallback.

## Published ABI 3

Each 112-byte document directory entry identifies one ordinary visible
document. It carries the attachment token, slot identity, absolute surface
geometry, and offset/byte pairs into four aggregate payload banks:

- UMSN menu records;
- UMSN menu text;
- UCSN collection descriptors; and
- UCSN native collection values.

A document contributes an entry when either its menu forest or collection
forest is nonempty. A document empty in both families contributes no entry.
The paired payload of an empty family is also empty: menu records cannot name
menu text without records, and collection native bytes cannot appear without
collection descriptors.

The borrowed aggregate snapshot is also 112 bytes. In addition to generation,
draw-generation, document count, content epoch, directory, menu-record, and
menu-text fields, ABI 3 publishes the used spans of the UCSN descriptor and
native-value banks. `RUHA-SNAPSHOT-COLLECTION-COUNT@` derives the collection
count from the descriptor extent. The snapshot and all of its spans remain
borrowed only until lifecycle invalidation or the next successful aggregate
publication; a downstream producer must copy them into its own immutable
attempt before asynchronous owner work begins.

The checked adapter ABI is 3 and the adapter is 592 bytes. ABI 3 supersedes the
unreleased menu-only ABI; there is no parallel legacy aggregate.

## One authoritative observation

For a live document capture, RUHA restores that document's authoritative UCTX
once and invokes `UMSN-CAPTURE` and `UCSN-CAPTURE` synchronously before
switching away. Both generic captures therefore observe the same ordinary
document context at the same completed-draw boundary. Neither capture
publishes independently. RUHA appends the document directory entry only after
both calls succeed and every returned count and byte extent fits its remaining
caller-provided bank.

This is generic UIDL/widget observation, not applet integration. UCSN discovers
direct core widgets and canonical widgets mounted through the ordinary WDG draw
lifecycle. RUHA neither knows that a textarea belongs to Pad nor offers Pad,
Daybook, Desk, or another applet a registration callback or terminal-facing
provider API.

## Explicit caller bounds

`RUHA-INIT` receives all storage explicitly, in caller-bank order:

- lifecycle records;
- UMSN capture work and text work;
- UCSN validation work and capture work;
- A/B document-directory storage;
- A/B UMSN record and text storage;
- A/B UCSN descriptor and native-value storage; and
- the adapter record.

The constructor validates nonwrapping spans, required alignment and record-size
multiples, exact A/B division, directory capacity against lifecycle-record
capacity, pairwise disjointness of every borrowed range, and disjointness from
the currently active UIDL/widget authority. Each attach must run in the
descriptor's authoritative UCTX and repeats that complete storage proof before
RUHA records the document.

Before any completed-draw bank or lifecycle-record write, RUHA switches through
every attached or quiesced document and proves every caller span—including the
directory, used and inactive payload banks, work banks, lifecycle records, and
adapter—disjoint from that UCTX and its mounted canonical widget storage. The
outer capture restores the original UCTX on success, refusal, or exception.
This prevents capture of one document from corrupting a later document whose
authority happens to alias caller storage.

Each aggregate payload is bounded independently by its caller-provided
half-bank. The Desk product leaf derives descriptor and capture-work capacity
from the native-byte bound and the universal collection-entry header minimum,
so multiple mounted roots under one UIDL source do not encounter a separate
UIDL-element-count ceiling. RUHA does not derive a hidden terminal reservation
from UIDL content and does not add an applet-specific collection-count limit.

## Exact clean reuse and content epoch

A clean document may reuse a prior slice only when it is menu-only. RUHA
validates the prior directory extents and every copied UMSN record, copies the
prior menu record and text slices, and rebases only UMSN aggregate-generation
cells. A document with any UCSN descriptor is recaptured even when the ordinary
lifecycle says it is clean. UCSN does not yet expose a complete public
frozen-bank validator, so a shallow descriptor/native copy or a descriptor
summary is not accepted as proof of exact prior content.

The content epoch is a provenance certificate, not a revision guess, digest,
or byte-equality shortcut. It carries only when every emitted document arrived
through validated prior menu-only reuse, the document count and complete
112-byte directory are identical, and all four aggregate payload byte totals
match. Any live capture, including every collection-bearing document, takes the
ordinary new-epoch path even if the resulting bytes happen to be equal.

## Downstream status

ABI 3 makes the frozen UCSN descriptor/native banks available at the generic
aggregate boundary. The selected producer now lowers both native text families
through one AREA|GRID path, packs their canonical STX1 values, admits their
claims, and publishes them through the generic engine. The selected source and
profile therefore advertise collection capability. That completed source route
is not physical Desk acceptance evidence; the exact composite and
revision-bound ordinary interactions must still cross the physical view sink.

## Bounded selector

`local_testing/test_rich_terminal_uidl_hybrid_adapter.py` is the seconds-scale
structural selector for ABI 3. It does not launch Desk, Pad, Daybook, a
renderer, persistence, or a full-core journey.
