# UIDL hybrid aggregate adapter

`tui/rich-terminal/uidl-hybrid-adapter.f` observes the ordinary completed
UIDL-TUI draw boundary and freezes the renderer-neutral menu, canonical
widget-collection, `DATA_GRAPHICS`, `STATUS_FIELD`, and typed `FIELD` models, and
the dialog each shows, for every visible attached UCTX. It also consults the ordinary screen's final-writer provenance:
when later foreground paint intersects a document, the adapter withholds all
of that document's semantic slices for the draw so residual output owns both
its pixels and hit area. It does not create an app scene, inspect CELL values,
or call an applet-specific API. Pad, Daybook, Desk, Sound Lab, and every other
applet are clients of this lower path; none registers a rich-terminal or
semantic provider.

Custom widgets and panels require no adapter. Anything not represented by an
ordinary core UIDL semantic type remains eligible for the residual projection
of the completed draw. CELL remains the complete fallback.

## Published ABI 11

Each 312-byte document directory entry identifies one ordinary visible
document. It carries the attachment token, slot identity, absolute surface
geometry, menu exact/topology lineage, and offset/byte pairs into twelve
aggregate payload banks:

- UMSN menu records;
- UMSN menu text;
- UCSN collection descriptors; and
- UCSN native collection values;
- UDGSN data-graphics descriptors; and
- UDGSN native data-graphics values;
- USFSN status-field descriptors; and
- USFSN native status-field values;
- UFLSN FIELD descriptors; and
- UFLSN native typed FIELD values;
- UDLSN dialog descriptors; and
- UDLSN native dialog models.

A document contributes an ordinary semantic entry when any menu, collection,
data-graphics forest, status-field list, or typed FIELD list is nonempty, or
it shows a dialog. A document intrinsically empty in all
enabled families contributes no entry. A visible document occluded by later
foreground paint, or one whose content a family refuses, instead contributes a
directory-only identity with all twelve semantic slices zero for that draw. The
paired payload of an empty family is
also empty: menu records cannot name menu text without records, and native
bytes cannot appear without their corresponding descriptors.

The borrowed aggregate snapshot is 240 bytes. In addition to generation,
draw-generation, document count, content epoch, directory, menu-record, and
menu-text fields, ABI 11 publishes the used spans of UCSN, UDGSN, USFSN, UFLSN
and UDLSN descriptor/native bank pairs. `RUHA-SNAPSHOT-COLLECTION-COUNT@`,
`RUHA-SNAPSHOT-DATA-GRAPHICS-COUNT@`, `RUHA-SNAPSHOT-STATUS-FIELDS-COUNT@`,
`RUHA-SNAPSHOT-FIELDS-COUNT@` and `RUHA-SNAPSHOT-DIALOGS-COUNT@` derive family
counts from their descriptor extents. The snapshot and all of its spans remain borrowed only until lifecycle
invalidation or the next successful aggregate publication; a downstream
producer must copy them into its own immutable attempt before asynchronous
owner work begins.

The checked adapter ABI is 11 and the adapter is 1176 bytes. It embeds the
collection and data-graphics builders and two snapshots; following offsets
are derived from each embedded size. Existing directory offsets through menu
topology epoch at 152 stay fixed. Status descriptor offset/bytes are at
160/168 and native offset/bytes at 176/184. Snapshot status descriptor address/
bytes are at 144/152 and native address/bytes at 160/168. FIELD appends directory
descriptor offset/bytes at 192/200 and native offset/bytes at 208/216; snapshot
FIELD descriptor address/bytes are 176/184 and native address/bytes 192/200.
The independent 48-byte FIELD bank family follows. Dialogs append
directory descriptor offset/bytes at 240/248 and native offset/bytes at
256/264; snapshot dialog descriptor address/bytes are 208/216 and native
address/bytes 224/232. Their independent 48-byte bank family moves snapshot
A/B to 656/896.

`OWNER-ID` is at directory offset 224 and `OWNER-GEN` at 232. `RUHA-DOCUMENT-OWNER-ID@` and
`RUHA-DOCUMENT-OWNER-GENERATION@` expose the nonzero identity tuple read
from the slot's actual `AHS.INST` component instance. Four cells at 272 to
296 hold the screen cells of the document's own overlay when its roots may
lie beneath it, described below, and are zero otherwise
(`RUHA-DOCUMENT-OVERLAY@`). The last cell, at 304, is the document's layer:
1 for an overlay slot's document, which its host paints above every other,
else 0 (`RUHA-DOCUMENT-LAYER@`). The attachment record is 144 bytes and the
snapshot 240 bytes. After the two snapshots the adapter holds the layers the
producer allows, at 1136, the memory source at 1144, the address and bytes of
the block it took from it at 1152 and 1160, and where the copy of the
records lies in that block at 1168. The record's four cells at 96 to 120
hold the screen cells of the overlay the document's last draw painted, or
zero, and its flags say whether that overlay is a dialog or a prompt's
field; its last two hold the count at which its menus were last captured
and the generation of the snapshot whose slice holds them.
The owner tuple describes the source component; it is separate from a
downstream terminal owner's identity and from the signed slot identity.

Attach and each snapshot preflight check the component descriptor ABI, full
descriptor size, nonzero instance ID/generation, and state extent. All mutable
adapter banks must be disjoint from the instance, complete descriptor, and
state. Malformed provenance refuses before any caller bank mutation. Every
published entry, including a directory-only fallback, freezes both values.
Prior slice reuse requires the same attachment token, slot identity, component
ID, and component generation. Replacing a genuine instance in the slot forces
live recapture and fresh menu lineage; stale prior data cannot acquire the new
component's provenance. Existing directory offsets through 216 stay fixed.


## Pictures

Pictures are not part of the snapshot: the copies they ask for follow the
terminal's pixel size and the space the producer has, which change while no
document redraws. `RUHA-PICTURES@ ( descriptors-a descriptors-u ask
draw-generation adapter -- count status )` describes them afresh for one
completed draw. Each visible document that no foreground paint covers, or
that is an overlay, describes its pictures with `UPICSN-CAPTURE` in its own
UCTX, and each descriptor names the document's attachment token. The context
in force before is restored whatever happens. A bank too small answers
CAPACITY with how many descriptors it would take and holds none; another
draw answers STALE.

`RUHA-PICTURE-PULL ( descriptor offset dest-a dest-u adapter -- status )`
copies `dest-u` bytes from `offset` of a described picture's file or copy,
from the document its token names, in that document's context, so a
producer can send a picture a chunk at a time. It answers STALE once the
document is no longer shown that way, the picture no longer shows that file
or copy, or the file could not be read, so a producer stops sending a picture
nothing will show.

`RUHA-PICTURE-FAIL ( document source-index revision reason adapter --
status )` says the rich side could not send picture `revision` at
`source-index` of the document its token names, because of the picture
itself. In that document's context, `UPICSN-FAIL` has the picture's widget
remember the reason, so later captures describe it as failed. It answers
STALE once the document is no longer shown that way or the element shows
another picture.

## Root facts

`RUHA-ROOT-FACTS@ ( facts-a facts-u draw-generation adapter -- count
status )` records what the capture of each root in the snapshot a completed
draw published read, one `URF` record a root
([uidl-root-facts.md](../tui/uidl-root-facts.md)): the newest UIDL revision
among the elements it read, the revisions of its widget and model, and the
geometry it was captured at. Records follow directory order and, within a
document, menus, collections, data graphics, status fields, fields and the
dialog. Each names its document's token and is filled in that document's own
context, as the snapshot was. A bank too small answers CAPACITY with how many
records it would take and holds none; another draw, or one that published no
snapshot, answers STALE. The screen producer keeps the facts beside each bank
it builds, and its DELTA comparison checks against its partner only a control
whose root's facts moved (FRAMES-FOLLOW-CHANGE, part 9a.3b). With the shadow
check on it also judges them: an item the comparison finds new or changed
must belong to a root whose facts moved (part 9a.1).

## Capture into scratch

`RUHA-CAPTURE-FAMILIES ( families token scratch draw-generation adapter --
status )` captures some families of one shown document into the caller's
scratch record, `RUHA-SCRATCH-SIZE` bytes, through the capture words and work
spans the snapshot uses, in the document's own context, and records the
facts of every root it captured. `FAMILIES` is a mask of `RUHA-F-MENUS`,
`RUHA-F-COLLECTIONS`, `RUHA-F-DATA-GRAPHICS`, `RUHA-F-STATUS-FIELDS`,
`RUHA-F-FIELDS` and `RUHA-F-DIALOGS`; a family the adapter was built without
captures nothing, as in the snapshot. The record holds the generation the
menu records take (`RUHA-SC.GENERATION`), one slot a family in bit order
(`RUHA-SC.SLOT`), each naming its descriptor and native spans, or menu
records and text, and receiving the count and bytes used, and the facts
span, which receives the count of records (`RUHA-SC.FACTS`). Nothing is
published: the snapshot, its banks and the documents' records stay as they
are. A family's short span answers CAPACITY with its bit in `RUHA-SC.SHORT`;
a short facts span answers CAPACITY with the records it must hold. A document
not shown, or covered so that the snapshot would leave it to CELL, and a
family that refuses its content, as the snapshot then falls the document
back, answer UNAVAILABLE; another draw answers STALE. The change driver
captures the families of the roots that changed this way
(FRAMES-FOLLOW-CHANGE, part 9a.2).


## One authoritative observation

For a live document capture, RUHA restores that document's authoritative UCTX
once and invokes `UMSN-CAPTURE`, `UCSN-CAPTURE`, `UDGSN-CAPTURE`, and enabled `USFSN-CAPTURE`/`UFLSN-CAPTURE`
synchronously before switching away. All enabled generic captures therefore
observe the same ordinary document context at the same completed-draw boundary.
None publishes independently. RUHA appends the document directory entry only
after all enabled calls succeed and every returned count and byte extent fits
what remains of its bank.

This is generic UIDL/widget observation, not applet integration. UCSN discovers
direct core textareas and authored tab graphs plus canonical widgets mounted
through the ordinary WDG draw lifecycle. UDGSN discovers canonical
`DATA_GRAPHICS` models through that same lifecycle. USFSN observes immediate
left-aligned, one-row labels under core STATUS elements, using the same
canonical display projection as ordinary paint.
The label becomes a whole value with empty label and zero label split; no text
parsing or app identity is involved. Unsupported alignment and partial clips
remain residual. UFLSN observes genuine mounted `FLD` widgets under the same
closed draw-instance lifecycle. It preserves native model keys, revisions, and
relative label/value slots without parsing UIDL labels or application names.
A FIELD root may span multiple rows, but its exact clip must represent its
complete rectangle. RUHA neither knows that a
textarea belongs to Pad nor that an instrument belongs to Sound Lab, and it
offers no applet a registration callback or terminal-facing provider API.

## Storage

`RUHA-INIT ( records-a records-u capacities memory adapter -- status )`
makes the adapter in the caller's 1176 bytes at `adapter`, with `records-u`
bytes of attachment records at `records-a`, one 144-byte record for each
document it can hold. The rest of its storage it takes from the memory
source `memory` (`utils/memory-source.f`) in one block:
both halves, A then B, of each of its thirteen bank spans, its four work
spans, and a copy of the records. The bank spans that grow start from the
`RUHA-CAPACITY-COUNT` capacities at `capacities`, in this order:

- menu records and menu text;
- collection descriptors and native values;
- data-graphics descriptors and native values;
- status-field descriptors and native values;
- field descriptors and native values; and
- dialog native models.

`RUHA-FIRST-CAPACITIES` holds the ones a caller starts from. Each capacity
is whole in its family's record or descriptor size, or in cells for native
bytes and text, and holds at least one record, descriptor or native header.
The other spans follow from these and from the records' count:

- the document directory and the dialog descriptors hold an entry for every
  attachment record, since a document shows at most one dialog;
- the menu capture's work and text work hold one document's elements and
  strings at UIDL's limits;
- the collections' validation ledger, a key cell for each variable child,
  takes as many bytes as their native span, since every child takes at
  least a cell of it; and
- the collections' capture work holds the largest of the collection
  descriptors' work and the status fields' or fields' frozen validation
  work.

The constructor answers INVALID when a span is malformed, the records and
the adapter overlap, either lies over RUHA's own storage or the current
UIDL and widget authority, or a capacity does not fit, and CAPACITY when the
memory source refuses the block. It proves the block apart from that
authority and from the records and the adapter before writing anything; a
proof that fails gives the block back and is a handover anomaly
(`check-mode.f`). `RUHA-FINI ( adapter -- )` gives the block back and clears
the adapter, once nothing will query it or read its snapshots.

A native span holds, for each model: `align8(72 + L + V)` bytes for a
status field with label length L and value length V, display projection
expanding each source byte to at most three; `224 + align8(label-bytes)`
for a FIELD, plus `align8(text-bytes) + align8(placeholder-bytes)` for TEXT
or `sum(24 + align8(choice-label-bytes))` for CHOICE, and nothing more for
INTEGER; and `160 + align8(title) + align8(message)` for a dialog, with
`64 + align8(label)` a button. A FIELD descriptor's UTF8 total includes the
outer label, TEXT value and placeholder, and every choice label; formatted
INTEGER digits take no UTF8 quota.

Each attach must run in the descriptor's authoritative UCTX and repeats the
complete storage proof before RUHA records the document. Before any
completed-draw bank or lifecycle-record write, RUHA switches through every
attached or quiesced document and proves every span, the directory, used
and inactive payload banks, work spans, the records' copy, the attachment
records and the adapter, disjoint from that UCTX and its mounted canonical
widget storage. The outer capture restores the original UCTX on success,
refusal, or exception. This prevents capture of one document from corrupting
a later document whose authority happens to alias RUHA's storage.

### Growth

A family answers CAPACITY only when the room RUHA lends it is too small.
That document falls back for the build, as a refused one does (below), and
its family is marked short. Once every document has been captured, a build
that ran short takes a new block whose growable spans of the short families
are twice their size, with the work spans their capacities require. It
copies the snapshot on screen and the records' copy into the new block and
gives the old one back. The snapshot on screen then names its spans where
they now lie, so it stays readable; the producer copies a snapshot when it
takes one, so nothing else names them. The new block is proved apart from
the screen's storage and each attached document's, as the banks are on
every draw; a proof that fails is a handover anomaly, and the old block
stays. The build then starts again from the records as they were before it.

A bank therefore grows to what its snapshots need and up to as much again,
and a document stays on CELL for want of room only when the memory source
refuses. The shadow check's full capture and the full refresh's capture
build the same way. Banks do not shrink. RUHA derives no terminal
reservation from UIDL content and sets no applet-specific collection-count
limit.

## Exact clean reuse, overlay refusal, and content epoch

A clean document may reuse a prior whole-document slice only after RUHA
validates its directory extents, every UMSN record and text reference, the
complete UCSN, UDGSN, USFSN, and UFLSN frozen descriptor/native pairs. It then copies all ten slices and rebases only the
caller-issued UMSN aggregate-generation cells. A shallow copy, digest, or
descriptor summary is not accepted as proof of prior content. Menu exact and
topology epochs are separately collision-free lineage certificates, so a
recaptured menu state change need not be mistaken for structural identity loss.
Reuse is only a shortcut. When the prior slices no longer fit behind the
documents already captured in the same draw, the refused append changes
nothing and the document is captured afresh, where each family falls back
within the space that is left. A document that grew therefore cannot make an
unchanged neighbour refuse the whole aggregate.

Final-writer occlusion is conservative at document granularity. If the
document rectangle intersects later foreground paint, RUHA emits its
directory-only identity with zero semantic slices and leaves the lifecycle
record dirty. A later exposed draw therefore performs a fresh semantic capture
instead of reusing the occluded zero-slice entry. This is generic atomic
fallback and click-through prevention, not a retained overlay family.

One kind of foreground paint is the document's own: the canonical prompt
(`tui/widgets/prompt.f`) an application paints over its status row while it
asks for a line of text. UIDL-TUI's draw observer records the prompt a
document's observed draw paints, by pointer and instance, in the document's
own context. The other is the dialog the document shows
(`tui/widgets/dialog.f`), which its host paints after everything the
document paints. When that draw completes, RUHA copies the overlay's screen
cells into the attachment record (`UTUI-OVERLAY-ROOT@`): the dialog's, as its
last paint laid it out, else the prompt's, and which of the two it is
(`UTUI-OVERLAY-KIND@`). The producer says which layers the renderer can
show above a document (`RUHA-LAYERS! ( flags adapter -- status )`, with
`RUHA-LAYER-FIELDS`, `RUHA-LAYER-DIALOGS` and `RUHA-LAYER-PANES`); the
adapter starts with none. A layer above a document is its own overlay, when
the overlay lies inside the document and the renderer can show its kind, or
a visible overlay slot's document, whose host paints the whole of its
rectangle, when the renderer can show overlay panes. When all the
foreground paint over a document lies inside the layers above it, the
document is captured as usual, every root included, those the layers meet
too: the producer puts those layers above them
([OVERLAY-LAYERS.md](OVERLAY-LAYERS.md)), so they stay semantic beneath,
and the directory entry names the own overlay's cells and the document's
layer, from which the producer checks that the claims above cover them. A
change of setting
closes the borrow gate, so a snapshot captured under the other setting is
not handed out again. The prompt itself becomes the document's overlay
TEXT field: UFLSN appends it after the mounted fields as the bank's last
record, from source `UFLSN-SOURCE-OVERLAY`, index 0, generation 1, the
prompt's instance as root key and paint order 255, and the prompt builds its
UFLD model from its input's state (`PRM-FIELD-CAPTURE`). A dialog becomes
the document's dialog slice: UDLSN captures its UDLG model, written by the
widget as its last paint laid it out (`DLG-MODEL-CAPTURE`). Any other
foreground paint over the document keeps the document-granular rule.

A family refusal falls back the same way, one document at a time. When the
menu, collection, data-graphics, status-field, typed FIELD, or dialog capture of a document reports `CAPACITY`,
`UNAVAILABLE`, or `INVALID`, that document contributes the directory-only
zero-slice identity, its record stays dirty so the next draw captures it
again, and nothing of it is staged. Its ordinary cells take the residual path
while every other document keeps its rich content. A family short of room
then has its spans grown and the build made again (Growth, above). The family failure status is cleared after choosing this document fallback;
a failed directory append still rejects the aggregate. The refused capture
published nothing, so it does not count as a live recapture: the content
epoch compares its zero-slice entry exactly as it compares a covered one.
Within the collection and data-graphics families, a root that its own widget
cannot publish is left out alone, so its document keeps its other roots.
RUHA's own bank checks, and a family result that breaks its contract, still
refuse the whole aggregate.

The content epoch is a provenance certificate, not a revision guess, digest,
or byte-equality shortcut. It carries only when every nonempty emitted document
arrived through validated prior whole-document reuse, the document count and
complete 312-byte directory are identical, and all twelve aggregate payload
byte totals match. Any live recapture takes the ordinary new-epoch path even if the
resulting bytes happen to be equal.

## Downstream status

ABI 11 makes the frozen UCSN, UDGSN, USFSN, UFLSN, and UDLSN descriptor/native banks available at the
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
structural and executed reuse selector for ABI 11.
`local_testing/test_rich_adapter_provenance.py` loads the actual full AHOST,
CINST, app-shell and UIDL dependency closure. It verifies replacement-instance
and generation-only recapture, frozen tuple corruption, directory-only fallback,
and invalid or aliased instance authority refusing before published-bank mutation.
`local_testing/test_uidl_status_field_snapshot.py` executes direct/mounted capture,
geometry, frozen corruption rejection, lifecycle changes, and shared display
projection. `local_testing/test_rich_terminal_status_adapter.py` executes the real
adapter constructor, status/collection capture and reuse, ordinary updates,
foreground occlusion, directory-only capacity fallback, and dirty retry in the
admitted native Forth runtime. These focused selectors do not launch Desk, Pad,
Daybook, Sound Lab, a renderer, persistence, or a full-core journey.


The status-field path never casts static fields as collection controls or
DATA_GRAPHICS instruments. Deep frozen validation proves exact native extent,
canonical text and padding, source relation identities, sorted nonduplicate
descriptors, one-row geometry, and fully represented clips before prior reuse.
Every caller span is proved against the status model, widget, snapshot scratch,
and mounted authority as well as the older families. Snapshot publication still
selects the inactive bank only after all families and context restoration succeed.
The executed selector covers canonical absent banks, complete A/B shape, copied
status slices, last-bank exhaustion without mutation, and all 20 protected spans.

`local_testing/test_uidl_field_snapshot.py` executes all three FIELD types,
exact multirow slots and revisions, copy independence, corrupt frozen metadata,
full clipping, live alias refusals, capacity rollback and mounted lifetimes.
`local_testing/test_rich_terminal_field_adapter.py` executes FIELD plus STATUS
and collections in one aggregate through reuse, revision replacement, overlay
fallback and short-bank dirty retry. FIELD banks retain their own model,
widget and snapshot storage proofs and are never cast as USCOL or UDG entries.
