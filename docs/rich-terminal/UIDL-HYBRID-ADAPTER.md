# UIDL hybrid aggregate adapter

`tui/rich-terminal/uidl-hybrid-adapter.f` observes the ordinary completed
UIDL-TUI draw boundary and freezes the renderer-neutral menu, canonical
widget-collection, and canonical `DATA_GRAPHICS` models for every visible
attached UCTX. It also consults the ordinary screen's final-writer provenance:
when later foreground paint intersects a document, the adapter withholds all
of that document's semantic slices for the draw so residual output owns both
its pixels and hit area. It does not create an app scene, inspect CELL values,
or call an applet-specific API. Pad, Daybook, Desk, Sound Lab, and every other
applet are clients of this lower path; none registers a rich-terminal or
semantic provider.

Custom widgets and panels require no adapter. Anything not represented by an
ordinary core UIDL semantic type remains eligible for the residual projection
of the completed draw. CELL remains the complete fallback.

## Published ABI 6

Each 160-byte document directory entry identifies one ordinary visible
document. It carries the attachment token, slot identity, absolute surface
geometry, menu exact/topology lineage, and offset/byte pairs into six aggregate
payload banks:

- UMSN menu records;
- UMSN menu text;
- UCSN collection descriptors; and
- UCSN native collection values;
- UDGSN data-graphics descriptors; and
- UDGSN native data-graphics values.

A document contributes an ordinary semantic entry when any menu, collection,
or data-graphics forest is nonempty. A document intrinsically empty in all
three families contributes no entry. A visible document occluded by later
foreground paint instead contributes a directory-only identity with all six
semantic slices zero for that draw. The paired payload of an empty family is
also empty: menu records cannot name menu text without records, and native
bytes cannot appear without their corresponding descriptors.

The borrowed aggregate snapshot is 144 bytes. In addition to generation,
draw-generation, document count, content epoch, directory, menu-record, and
menu-text fields, ABI 6 publishes the used spans of both UCSN and UDGSN
descriptor/native bank pairs. `RUHA-SNAPSHOT-COLLECTION-COUNT@` and
`RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@` derive family counts from their descriptor
extents. The snapshot and all of its spans remain borrowed only until lifecycle
invalidation or the next successful aggregate publication; a downstream
producer must copy them into its own immutable attempt before asynchronous
owner work begins.

The checked adapter ABI is 6 and the adapter is 784 bytes. ABI 6 supersedes the
unreleased earlier aggregates; there is no parallel legacy ABI or adapter.

## One authoritative observation

For a live document capture, RUHA restores that document's authoritative UCTX
once and invokes `UMSN-CAPTURE`, `UCSN-CAPTURE`, and `UDGSN-CAPTURE`
synchronously before switching away. All three generic captures therefore
observe the same ordinary document context at the same completed-draw boundary.
None publishes independently. RUHA appends the document directory entry only
after all three calls succeed and every returned count and byte extent fits its
remaining caller-provided bank.

This is generic UIDL/widget observation, not applet integration. UCSN discovers
direct core textareas and authored tab graphs plus canonical widgets mounted
through the ordinary WDG draw lifecycle. UDGSN discovers canonical
`DATA_GRAPHICS` models through that same lifecycle. RUHA neither knows that a
textarea belongs to Pad nor that an instrument belongs to Sound Lab, and it
offers no applet a registration callback or terminal-facing provider API.

## Explicit caller bounds

`RUHA-INIT` receives all storage explicitly, in caller-bank order:

- lifecycle records;
- UMSN capture work and text work;
- UCSN validation work and capture work;
- A/B document-directory storage;
- A/B UMSN record and text storage;
- A/B UCSN descriptor and native-value storage; and
- A/B UDGSN descriptor and native-value storage; and
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

## Exact clean reuse, overlay refusal, and content epoch

A clean document may reuse a prior whole-document slice only after RUHA
validates its directory extents, every UMSN record and text reference, the
complete UCSN frozen descriptor/native pair, and the complete UDGSN frozen
descriptor/native pair. It then copies all six slices and rebases only the
caller-issued UMSN aggregate-generation cells. A shallow copy, digest, or
descriptor summary is not accepted as proof of prior content. Menu exact and
topology epochs are separately collision-free lineage certificates, so a
recaptured menu state change need not be mistaken for structural identity loss.

Final-writer occlusion is conservative at document granularity. If the
document rectangle intersects later foreground paint, RUHA emits its
directory-only identity with zero semantic slices and leaves the lifecycle
record dirty. A later exposed draw therefore performs a fresh semantic capture
instead of reusing the occluded zero-slice entry. This is generic atomic
fallback and click-through prevention, not a retained overlay family.

The content epoch is a provenance certificate, not a revision guess, digest,
or byte-equality shortcut. It carries only when every nonempty emitted document
arrived through validated prior whole-document reuse, the document count and
complete 160-byte directory are identical, and all six aggregate payload byte
totals match. Any live recapture takes the ordinary new-epoch path even if the
resulting bytes happen to be equal.

## Downstream status

ABI 6 makes the frozen UCSN and UDGSN descriptor/native banks available at the
generic aggregate boundary. The selected producer lowers native text roots plus
TABSET/TAB root/descendant graphs through one generic collection boundary and
lowers canonical `DATA_GRAPHICS` values through the distinct instrument
boundary. STX1 remains exclusive to text roots; tab strings are copied into
caller-owned control text, and only the TABSET root claims the ordinary header
rectangle.

The selected source/profile advertises exactly `RET_CORE | RET_INSTRUMENT |
RET_CONTROLS | RET_CONTROL_COLLECTIONS`. The complete local X11 journey at
Akashic `4b6a475` with MegaPad `29bdfd6` passed the exact composite,
acknowledgement-bound Pad tab activation, final-writer Desk launcher occlusion,
and normal Sound Lab launch with exactly eight `READOUT`, two `METER`, and three
`STATUS` objects. The revision-bound evidence is
`local_testing/evidence/rich-desktop-full-vertical-acceptance-20260902.md`.
That is software/reference-view evidence, not physical UART or panel proof.

## Bounded selector

`local_testing/test_rich_terminal_uidl_hybrid_adapter.py` is the seconds-scale
structural selector for ABI 6. It does not launch Desk, Pad, Daybook, Sound Lab,
a renderer, persistence, or a full-core journey.
