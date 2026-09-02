# Desk rich-terminal ecosystem inventory

Status: implementation inventory and execution recommendation, 2026-09-02.
This is not a wire addendum, a capability advertisement, or acceptance
evidence. Exact protocol changes still belong in the APT-1 contracts before
their implementations are enabled.

## 1. Decision and result

The selected local full vertical is accepted at exact committed heads Akashic
`4b6a475` and MegaPad `29bdfd6`. The sequential checked-cold-source X11 journey
physically composed and acknowledged the complete ordinary Desk, exercised
Pad and Daybook, continued through Desk's ordinary launcher, and launched
Sound Lab with its complete generic instrument graph. This closes the former
Desk/Pad/Daybook blocking checkpoint and its selected collection/instrument
extension. It does not qualify external UART delivery, panel scanout,
e-paper refresh, touch, reset/resize, persistence, sustained cadence, or an
unadvertised semantic family.

Do not rerun that full journey after every new semantic element. A later
physical run should be attached to the next coherent end-to-end family or to a
change that invalidates the recorded boundary, not to documentation or an
isolated renderer-neutral refactor.

The inventory does **not** justify replacing the rich-terminal foundation.
These layers remain the right design and are reused:

- the mandatory complete CELL fallback;
- one aggregate projection of the ordinary Desk/UCTX draw lifecycle;
- normal UIDL and mounted-widget discovery;
- the neutral, immutable collection snapshot;
- unified CELL/retained publication and sink-acknowledged revision binding;
- semantic paint claims plus residual `GLYPH_RUN` coverage;
- hidden replacement, acknowledged delta reuse, and physical composition; and
- renderer-owned representation and caller-bounded allocation.

What remains incomplete is the semantic vocabulary above those layers. The
selected profile now advertises `RET_CORE | RET_INSTRUMENT | RET_CONTROLS |
RET_CONTROL_COLLECTIONS`. Menus, residual glyph runs, canonical `TEXT_AREA`,
`TEXT_GRID`, `TABSET`/`TAB`, and the complete `READOUT`/`METER`/`STATUS`
instrument family have ordinary-source-to-physical-view acceptance in the
named journey. Sound Lab supplies the accepted instrument family through one
mounted renderer-neutral `DATA_GRAPHICS` model: exactly eight readouts, two
meters, and three status indicators.

The launcher also closes the generic composition problem for ordinary
foreground overlays: `DRW-OVERLAY` records final-writer provenance, the
aggregate adapter atomically withholds any intersected document's semantic
slices, and residual projection owns both the foreground pixels and hit area
for that draw. This is accepted fallback/occlusion behavior, not a retained
semantic overlay family. Generic fields, actions, item views, semantic
overlays, and rich textual status remain absent. MegaPad's vector, bounded
series/plot/waveform, and immutable RGBA image endpoints remain
terminal-complete but lack the corresponding ordinary Akashic capture and
selected producer path, so their feature bits stay disabled.

The next implementation work should therefore proceed by universal semantic
family across several ordinary consumers, not applet by applet. Lightweight
contract and off-screen checks remain appropriate for each coherent slice.
Broader controls, the remaining data-object families, cadence, and hardware
qualification are separate next gates; none should be described as part of the
already accepted collection/instrument checkpoint.

## 2. Scope

The checked-in `desktop` profile loads the following product set:

- Desk, with Pad, File Explorer, Daybook, Grid, and Agent in the startup
  composition;
- Sound Lab and Streams as enabled, pinned, discoverable built-ins; and
- Agent's ordinary scripted provider.

`desktop-apt1` preserves that applet set and changes only the Desk root/run
wrapper needed for the optional retained path. Sound Lab and Streams do not
consume startup tiles, so a complete initial screen alone does not exercise
their bodies.

Library, Observatory, and Worlds are ordinary descriptor/UIDL applets but are
not members of the current Desktop profile. They are included as adjacent
cross-consumer checks because they expose the same list/detail, plot, readout,
meter, journal, field, and action needs. They must not silently become
prerequisites for loading the current Desktop.

The inventory follows actual composition and drawing, not only authored UIDL.
Every audited extended applet has a normal UIDL shell and a mounted,
directly-painted body. Consequently a UIDL-document-only projector can never
cover the ecosystem. The generic capture boundary must continue through
ordinary mounted widgets and painting, and the custom numeric widget-type IDs
must not become terminal scene kinds.

## 3. Coverage classification

The following terms are used in the rest of this inventory:

- **Qualified end-to-end** means an ordinary source has been captured and
  lowered through Akashic, accepted by MegaPad, physically rendered, and—where
  interactive—routed back with the exact acknowledged revision in the named
  complete journey.
- **Terminal-complete/Akashic-missing** means the public terminal model and
  view already support the family but the ordinary Akashic capture and return
  route do not.
- **Protocol/model only** means wire and retained state exist but the public
  producer and/or physical view still refuse the family.
- **Ordinary-only** means Akashic already has a renderer-neutral UIDL or widget
  concept, but rich capture and retained protocol semantics are absent.
- **Residual** means the ordinary pixels are still visible through retained
  `GLYPH_RUN` output. Residual is a valid visual layer, but it is not semantic
  control or structured-content coverage.

### 3.1 Current seam matrix

| Family | Ordinary capture | Akashic retained seam | MegaPad PT/model | Physical view and input | Selected policy |
|---|---|---|---|---|---|
| CELL fallback | Complete screen | Unified publication | Complete | Complete ordinary presentation/input | Mandatory |
| Residual `GLYPH_RUN` | Complete draw minus accepted claims | Complete | Complete | Complete draw; no semantic hit target | `CORE` advertised |
| Menu bar/menu/item/separator | Ordinary resolved UIDL menu tree | Complete control planner and resolver | Complete | Complete menu rendering; revision-bound `ACTIVATE` for menu/item | `CONTROLS` advertised and accepted |
| `TEXT_AREA` | Direct UIDL or mounted canonical `TXTA` snapshot | Complete STX1/control path | Complete | Viewport, focus, selection, and caret render; ordinary key/text editing; no item hit | Advertised and accepted in the selected journey |
| `TEXT_GRID` | Canonical `TGRID` widget snapshot | Complete STX1/control path | Complete | Viewport, headers, current/unavailable state render; ordinary keyboard navigation; no item hit | Advertised and accepted in the selected journey |
| `TABSET`/`TAB` | Authored UIDL or mounted canonical `TAB` snapshot from ordinary drawing | Complete root/descendant control, claim, and acknowledged target path | Complete | Complete rendering and `TAB ACTIVATE` hit path | Advertised and accepted in the selected journey |
| Vector/group/polyline | No ordinary generic capture | No public facade/producer | Complete typed PT ABI and retained model | Complete shared-view projection and physical rendering | Terminal-complete; Akashic missing; unadvertised |
| Readout/meter/status instrument | Mounted canonical `DATA_GRAPHICS` snapshot | Complete generic instrument planner, claim, and producer path | Complete typed PT ABI and retained model | Complete physical readout, meter, and status rendering | `INSTRUMENT` advertised; accepted with Sound Lab's 8/2/3 graph |
| Bounded series/plot/waveform | No ordinary generic capture | No public facade/producer | Complete bounded SERIES PT ABI and retained model | Complete plot/waveform rendering from immutable histories | Terminal-complete; Akashic missing; unadvertised |
| Image/resource | No product capture | No public facade/producer | Complete immutable RGBA8 upload and IMAGE PT/model lifecycle | Complete exact-offer delivery and STRETCH/CONTAIN/COVER rendering | Terminal-complete; Akashic missing; unadvertised |
| Display cadence | Draw revisions already exist | Capability/limit plumbing only, appropriately no scene mutation | Host offer/coalescing/ACK scheduler exists | Current interval is zero | Unadvertised |
| Ordinary foreground overlay paint | `DRW-OVERLAY` final-writer provenance | Intersected document semantics are withheld atomically; residual owns pixels and hit area | No overlay kind required for this fallback | Complete residual physical composition; no semantic overlay hit model | Composition fallback accepted; semantic overlay absent |
| Action/toggle/choice/field/item view/semantic overlay/rich status | Ordinary UIDL/widget concepts exist in varying degrees | No retained family | No retained control enum or event model | Residual only | Absent |

The collection feature is atomic at the wire boundary: it includes area, grid,
tabset, and tab. Akashic emits all four from canonical widgets, and the
`4b6a475`/`29bdfd6` journey accepted their ordinary Desk/Pad/Daybook lifecycle
and acknowledged tab activation. This closes the selected collection seam
without adding an applet-specific tab implementation. Direct AREA/GRID item
hits and richer collection roles remain separate future behavior.

### 3.2 Existing ordinary vocabulary is useful but not sufficient

Akashic already names generic widget types for input, list, progress, table,
dialog, tabs, split, scroll, tree, status, toast, canvas, prompt, textarea, and
text grid. Core UIDL similarly names action, input, selector, toggle, range,
collection, table, indicator, media, and canvas, while UIDL chrome names tabs,
tree, status, dialog, toast, toolbar, log, code, and related types.

Several of these have ordinary TUI render and event paths today. Others are
registered types without a stock mounted implementation. None of that alone
makes them a retained semantic family. The reusable source concept, its
immutable neutral snapshot, capability-aware lowering, endpoint model,
physical representation, hit/intent return, and ordinary action routing all
have to be present before the feature is advertised.

There is no need for a monolithic `FORM` scene. A form is ordinary composition
of fields, selectors, toggles, actions, help/error text, and an optional modal
focus scope.

### 3.3 Current input boundary

Keyboard and text input already traverse the normal viewer-to-guest path.
`TEXT_AREA` and `TEXT_GRID` therefore remain usable with ordinary focus and
keyboard routing. Their retained models publish selection, caret/current
item, and viewport state, but the semantic protocol cannot yet click a text
position, drag a selection, select a grid item, or scroll a collection.

The only retained `CONTROL_EVENT` is revision-bound `ACTIVATE`, valid for
`MENU`, `MENU_ITEM`, and `TAB`. Raw pointer, wheel, and focus messages exist
lower in APT-1, but the shared viewer path currently exposes semantic menu/tab
hits rather than a complete generic pointer/focus route. Plain text input is
exposed; host clipboard/paste intent is not yet carried through the shared
API. Akashic's guest-local clipboard is a different facility.

Any event expansion must preserve the current rule: the terminal reports
intent against an immutable hit map for the exact physically composited and
acknowledged revision; the ordinary application remains authoritative and
revalidates the target before changing state.

## 4. Current Desktop consumers

### 4.1 Desk

Desk has no authored UIDL document. It hosts ordinary child descriptors,
instances, regions, and UCTXs, then directly paints its background, dividers,
taskbar/hotbar, launcher, agent state, and prompt.

Current retained output preserves all of those pixels as residual glyph runs,
while child documents independently contribute menu/area/grid semantics. A
normally opened launcher has also been accepted through the ordinary paint
order: its final-writer overlay provenance suppresses intersected child
semantics for that draw, so the visible launcher and its ordinary keyboard
handling remain coherent residual output. That result does not provide
structured launcher rows or a semantic modal/overlay contract. A
full smart-client experience additionally needs generic view/pane identity and
focus, taskbar/launcher item collections, action availability, prompt field
state, and textual status/notice state. Desk must not receive a terminal
service or a Desk-scene API; this information comes from ordinary host,
collection, field, and action lifecycles.

### 4.2 Pad

Pad's ordinary UIDL shell provides menus and layout. Its mounted canonical
textarea supplies the editor and output `TEXT_AREA` controls, while one
caller-sized canonical `TAB` widget now supplies buffer-tab state and header
mouse selection through the same ordinary panel draw/event lifecycle. The
accepted journey edited the editor, appended Daybook's shared source as a
second tab, activated the original tab against its acknowledged target, and
preserved the resulting semantic text/tab state under stable session/owner
lineage through later complete retained replacement, while retained wire IDs
were free to rebase. The Explorer tree, prompt/dialogs, gutter, and status
remain residual.

The generic targets are the already-defined tab family, hierarchical item
view, field/overlay/action/status families, and the existing textarea. Gutter
line numbers, dividers, and styling may remain residual once the editor's
substantive text, selection, viewport, focus, and edit authority are semantic.
No Pad-specific editor, scene, or protocol kind is needed.

### 4.3 File Explorer

The preview is a canonical `TEXT_AREA`; menus are already semantic. Details
and Preview tabs, the hierarchical Explorer, flat/tabular detail list,
rename/new/goto prompt, dialogs, operation notices, status, and sort/selection
state are residual.

This applet is a strong cross-check for tabs, hierarchical and columnar item
views, fields, modal actions, and status. File paths, selected item identity,
and operation results cannot remain solely decorative glyphs in the completed
semantic target.

### 4.4 Daybook

Daybook's calendar is a real canonical `TGRID` and is already emitted as
`TEXT_GRID`. The accepted journey added a task, navigated the calendar, and
routed Daybook's shared source into Pad while retaining the acknowledged grid
state. Its directly painted agenda contains sectioned events, times,
task checked/done state, notes, selection, and empty state. Prompt, notices,
and status are also residual.

The agenda should use a stable-keyed, sectioned item view with checked/action
state. Calendar navigation can continue through the generic text grid; direct
item intent is an eventual extension of the same revision-bound input model.

### 4.5 Grid

Grid's worksheet is a custom panel despite its name; it is not the canonical
`TGRID` widget. Formula/source text, row and column headers, displayed values,
selected cell, error/cycle state, viewport, prompt, and dialogs are residual.

The correct target is a generally useful editable text-grid/table contract
with separate displayed and edit/source values, stable cell keys, header
roles, viewport, availability/error state, and edit/activate intent. It must be
proved with Daybook and other tabular consumers, not designed around Grid
alone.

### 4.6 Agent

Agent's shell menus are semantic; its mounted body directly paints transcript
roles, streaming/error/review state, wrapped messages, review operands,
fingerprints, effects, and approval guidance. Ask and masked Credential modes
share a prompt. Account and settings overlays provide stateful choice rows.

The generic target is a stable-keyed message/detail item view, text field and
masked-field behavior, selectors/toggles/actions, modal focus scope, and rich
status. Approval remains application-authoritative and revision-sensitive;
the renderer must not bypass the existing inspected-through-bottom and operand
revalidation rules.

### 4.7 Sound Lab

Sound Lab directly paints selected parameter rows, a sampled PCM waveform,
landmarks, readiness/playback text, and a numeric prompt. It also mounts one
canonical `DATA_GRAPHICS` model for its analysis instruments. The accepted
ordinary launch produced exactly eight `READOUT`, two `METER`, and three
`STATUS` objects through generic Akashic capture/lowering and MegaPad's
physical renderer. Its validation ranges are genuine domain limits rather
than terminal capacities.

Parameter rows still map to future generic bounded numeric/choice fields and
actions. The PCM trace still maps to the terminal-complete but unselected
bounded series plus waveform family, with polylines for markers where useful;
it remains residual in the accepted profile. Completing that path requires a
universal Akashic object/series producer and ordinary capture, not a Sound Lab
scene or an audio-in-terminal protocol.

### 4.8 Streams

Streams directly paints Timeline, Context, Sources, and Burrows views. Its
cards carry stable content such as author, time, body, reply state, source
kind/endpoint/revision, acquisition state, URI/CID, selection, and viewport.
Search, draft, actor, source creation, and destructive source removal use
prompt flows.

The generic target is tabs/view selection, multi-line item/card views,
structured item fields/badges, checked/enabled state, text field plus editable
`TEXT_AREA`, link/resource identity, async status, and action availability.
These are not Streams-specific terminal objects.

## 5. Adjacent cross-consumer checks

These applets should constrain the universal design without expanding the
current Desktop startup gate:

| Applet | Reusable pressure it adds |
|---|---|
| Library | Pageable list/table, lifecycle badges, master-detail relation, scrollable read-only `TEXT_AREA`, text/multiline fields, and destructive actions |
| Observatory | Readouts/status, read-only `TEXT_GRID`, exact bounded series, and plot; validates the same data-graphics seam as Sound Lab |
| Worlds | Readouts, meters, status, transition journal grid, bounded numeric field, toggle/action state; validates instrument and scalar-control reuse |

The cross-check is important because it prevents a nominally generic family
from merely encoding the first applet's private state. It does not authorize
Library-, Observatory-, or Worlds-specific retained types.

## 6. Universal semantic target

The following are conceptual families. Exact names and wire records must be
specified separately; the inventory deliberately does not freeze enum values.

### 6.1 View/pane metadata

A generic container/view relation should expose a visible child surface's
stable identity, label/role, geometry, z/order, focus, minimized/available
state, and content association. Existing retained regions remain the geometry
and clipping mechanism; this semantic metadata must not duplicate pixels or
turn Desk into a scene provider.

Consumers: Desk tiles/focus, modal focus scopes, master-detail views, and
selected tab content.

### 6.2 Viewport, scroll, and split

Publish generic viewport offset, visible extent, content extent, and applicable
scroll availability alongside the owning area, grid, item view, or pane.
Split containers need stable child association, orientation, current divider
position, genuine minimums where present, and adjustment availability. These
are ordinary layout and navigation semantics, not terminal pixel metrics.

Revision-bound intent must eventually cover line/page/position scrolling and
split adjustment. Raw pointer/wheel/focus can remain a shared fallback path,
but it does not replace semantic viewport state or authorize renderer-local
mutation. Existing `TEXT_AREA`/`TEXT_GRID` viewport publication remains the
model to reuse.

Consumers: every scrollable editor, tree, list, grid, transcript, and preview;
Pad/File Explorer splits; and Desk/app view resizing where the ordinary host
actually permits it.

### 6.3 Tabs

The canonical `TABSET`/`TAB` path is implemented from ordinary widget drawing
through neutral snapshot, Akashic retained materialization, root-only claim
accounting, acknowledged point targeting, and ordinary mouse-event return
routing. Pad is the first accepted ordinary consumer and sizes the widget from
its real buffer domain; the generic source and retained layers contain no Pad
limit or callback. Dirty state is currently truthful in Pad's user-visible
label rather than a new protocol flag.

Identity continuity is layered. Canonical source keys and the semantic tab
signature preserve application meaning. A retained `ControlIdentity`
(`owner_id`, `owner_generation`, `control_id`) is exact only within its
retained target: compatible acknowledged deltas may reuse it, while
`RET_REPLACE_START` may legitimately build a new target with fresh control
IDs. The accepted gate therefore compares the canonical tab graph and content
state across replacement, resolves the original tab in the current
acknowledged offer under stable session/owner lineage, and sends that offer's
exact target. It does not require a wire ID from an earlier retained
incarnation to survive a full replacement.

Consumers: Pad buffers, File Explorer Details/Preview, Streams views, and
Library views. Desk's taskbar remains an item/action collection rather than
being misrepresented as editor tabs.

### 6.4 Action and scalar controls

Expose generic action/button, toggle/check, radio/choice/selector, and bounded
range/value behavior with label, current value/state, enabled/pending,
destructive/default role, help/error text, and ordinary command binding.
Application domain bounds are valid semantic behavior; retained buffer sizes
are not.

Consumers: UIDL actions, Daybook tasks, Agent settings/review, Sound Lab
parameters, Streams source state, and Worlds controls.

### 6.5 Field/input

A one-line field needs stable identity, label, value, placeholder, cursor and
anchor, horizontal viewport, focus, enabled/read-only/masked state,
validation/help, and submit/cancel action association. Multiline editing should
continue to reuse and extend `TEXT_AREA`, rather than creating an app-specific
editor family.

Consumers: Desk and applet prompts, File Explorer rename/goto, Agent Ask and
Credential, Sound Lab numeric edit, Streams search/source fields, Grid edit/goto,
and Library edit flows.

### 6.6 Item view

One structured collection model should support explicit flat-list, tree,
table, card, property-row, section, and journal roles without inferring
structure from indentation. It needs stable item keys, optional parent/depth,
ordered fields/columns, selected/current/checked/expanded/enabled states,
viewport and continuation metadata, and item action associations.

This is a common data shape, not one renderer presentation. A renderer may
choose list, tree, table, cards, or accessible outline presentation according
to the explicit role. It must not invent hierarchy or discard structured
fields.

Consumers: Desk launcher/taskbar, Pad/File Explorer trees, File Explorer
details, Daybook agenda, Agent transcript/review details, Sound Lab properties,
Streams cards, and all three adjacent applets.

### 6.7 Complete text-grid behavior

Keep the existing renderer-neutral `TEXT_GRID` and extend only generally useful
semantics: editable/read-only mode, stable cell key, row/column header roles,
display text versus optional edit/source text, current/selected/error/
unavailable state, viewport, and item edit/activate intent. Do not encode
spreadsheet formulas, dates, files, or world transitions as protocol concepts.

Use `TEXT_GRID` when row/column position and cell navigation are the primary
identity. Use an item view when stable domain entities, hierarchy, fields, and
row actions are primary, even if one renderer presents those fields as a
table. This keeps File Explorer rows and Daybook entries from being flattened
into spreadsheet cells.

Consumers: Daybook calendar, Grid worksheet, Observatory sample tables, and
Worlds journal.

### 6.8 Overlay, notice, and rich status

The accepted launcher establishes renderer-neutral overlay *composition*, not
an overlay scene type. `DRW-OVERLAY` marks ordinary later paint in the screen's
final-writer plane. If it intersects a document, the aggregate adapter omits
that document's semantic slices for the draw and leaves the visible pixels and
hit area to residual projection. When the launcher closes, ordinary document
semantics return on the next completed draw. This prevents click-through and
stale underlay semantics without teaching Desk or the terminal about a
launcher object.

An overlay supplies role, geometry, title/body relation, modality/focus scope,
default/cancel/dismiss actions, and contained ordinary controls. Notice/status
semantics need message identity, severity/role, persistent versus transient
lifecycle, and optional busy/progress state. Those structured semantics remain
future work; the accepted residual launcher does not claim them.

The existing retained `STATUS` object is only a numeric two-state visual
indicator. It is useful for instruments but is not a substitute for textual
application status, validation errors, badges, toasts, or approval state.

Consumers: dialogs and prompts throughout the Desktop, operation results,
Agent auth/review, source acquisition, and readiness/error bands.

### 6.9 Data graphics and instruments

The neutral `DATA_GRAPHICS` snapshot, distinct Akashic instrument planner and
producer plane, claim/refusal path, and selected `RET_INSTRUMENT` policy are
complete for `READOUT`, `METER`, and `STATUS`. Sound Lab's normal 8/2/3 graph
provides current product-consumer and physical-view evidence. This does not
qualify every data-graphics family or every potential instrument consumer.

Complete the remaining distinct neutral and public Akashic planes for
group/polyline, bounded series, plot, and waveform. MegaPad already provides
their typed caller-bounded PT operations, retained model, shared-view
projection, and physical rasterization. Resource upload and images likewise
have a complete separate MegaPad lifecycle and must not be crammed into the
Akashic control facade. The selected composition must continue to withhold
each remaining feature bit until ordinary capture, Akashic lowering, refusal,
and product-consumer evidence are complete.

Consumers: Sound Lab plus Observatory for series/plots/readouts, and Worlds for
readouts/meters/status. Only Sound Lab's instrument subset is accepted today.
Image/resource work is deferred because no current Desktop checkpoint has a
substantive image consumer.

### 6.10 Structured resource identity and host integration

URI, path, CID, account, and similar copyable values should be structured item
fields or link/action roles rather than a new scene family for each resource.
Host clipboard/paste, raw pointer/wheel, and focus can be completed as shared
input facilities after their authority and security rules are explicit. They
must not become a shortcut around ordinary widget handling.

## 7. What may remain residual

Residual glyph output is an intentional universal visual fallback. It is
appropriate for backgrounds, borders, dividers, whitespace, decorative
headings, line-number/gutter decoration, shortcut hints, and prose help when
the corresponding content and authority already have semantic representation.

Residual is not sufficient when it is the sole rich representation of:

- editable or selected content;
- list/tree/table/card identity or hierarchy;
- current field values, validation, or masking;
- focus, checked, expanded, pending, disabled, or destructive state;
- application status, review authority, or operation results;
- paths, URIs, CIDs, document/transcript text, or resource identity; or
- a substantive plot, waveform, meter, readout, or journal.

This boundary avoids the opposite failure mode of turning every painted label
or divider into a control. A full rich experience is structured where meaning
or interaction requires it and residual where visual decoration is enough.

## 8. Required architecture rules

1. One ordinary renderer-neutral projection is derived from normal UIDL,
   mounted widget, host, and draw lifecycles. Applets do not discover a
   terminal, publish scenes, or own protocol identities.
2. Directly painted bodies either mount/reuse canonical generic widgets or use
   generic semantic draw-state builders observed at the normal draw boundary.
   No private applet snapshot callback may become a retained provider.
3. Neutral snapshots are immutable, pointer-free, stable-keyed, and bounded by
   caller storage. The selected renderer owns representation, clipping,
   rasterization, retained capacity, and physical presentation.
4. Capability-aware materialization dispatches by generic family rather than
   accumulating `AREA|GRID|next-special-case` predicates throughout the
   producer.
5. Controls, objects, resources, and series have distinct public callback and
   accounting planes. They still join one atomic aggregate frame, claim
   ledger, residual plan, and CELL/retained publication.
6. A family is advertised only when source capture, Akashic lowering, terminal
   codec/model, physical view, refusal behavior, and applicable return routing
   are all complete.
7. Semantic input names a control/item/subkey from the exact physically
   acknowledged model revision. Renderer-neutral source identity and semantic
   state survive reconstruction, but retained wire IDs are incarnation-local
   and may rebase on complete replacement. The application revalidates and
   mutates its ordinary state; the terminal never mutates an authoritative
   copy.
8. CELL remains a complete fallback. A refused semantic family contributes no
   blank claim: its ordinary painted cells stay residual/CELL-visible.
9. No terminal buffer reservation enters UIDL. Genuine content or domain limits
   may be semantic; representation capacity is derived below the renderer-
   neutral boundary from caller-provided bounds.
10. Before a generic contract is frozen, check its shape against at least two
    structurally different consumers in this inventory. Only consumers inside
    the active tranche/gate need implementation at that time; adjacent
    applets are design evidence, not automatic critical-path work. Pad alone
    is never the design oracle.

## 9. Recommended implementation tranches

These are dependency tranches, not full-emulator milestones. The broad
inventory constrains the generic shapes now, but it does not make unrelated
applets or unadvertised families part of the accepted Desk/Pad/Daybook gate.
Tranches A through C are closed at `4b6a475`/`29bdfd6`; D onward describe
future expansion.

### Tranche A: close the current-gate collection seam

**Closed and physically accepted.** Canonical TAB capture, generic retained
root/descendant lowering, root-only claims, caller-derived control-capacity
sizing, acknowledged target correlation, Desk routing, and Pad's ordinary
consumer are committed and accepted.

- `TABSET`/`TAB` capture, lowering, claims, exact acknowledged-offer return
  correlation, and ordinary action routing use generic tabs with Pad as the
  accepted consumer;
- retained control IDs may remain stable across compatible deltas but may
  legitimately rebase across complete replacement; stable session/owner
  lineage plus source keys and semantic graph/state provide reconstruction
  continuity;
- area, grid, and tab graphs share the generic collection-family boundary;
  and
- File Explorer and Streams/Library remain design checks, not retroactive
  requirements of this accepted tranche.

### Tranche B: finish the universal integration needed by the checkpoint

**Closed and physically accepted.** The selected host derives semantic-control
and instrument contributions to its object and transaction limits from the
same public ABI densities used by Desk and the generic producers. The
acceptance projection reconstructs complete collection and instrument graphs,
binds every input to the exact acknowledged offer, and compares semantic state
under stable session/owner lineage across any legitimate retained-wire ID
rebase.

The selected full-vertical extension also closed two generic integration
seams that did not widen the original collection contract:

- ordinary later foreground paint records final-writer provenance, so an
  intersected document's semantic slices fall back atomically to residual
  pixels and hit ownership; and
- canonical `DATA_GRAPHICS` capture and the distinct instrument planner lower
  the complete `READOUT`/`METER`/`STATUS` family without entering the control
  facade.

New pane/view, item, viewport, action/field, semantic overlay/status,
direct AREA/GRID item-hit, vector, series, image/resource, and adjacent-app
implementation remain outside this tranche. The wider consumer inventory is
design evidence, not a retroactive acceptance requirement.

### Tranche C: combined Desk/Pad/Daybook and Sound Lab checkpoint

**Closed at Akashic `4b6a475` and MegaPad `29bdfd6`.** One sequential
checked-cold-source X11 journey:

1. loaded the complete ordinary startup Desk composition, including its other
   normal startup tiles, without treating those unrelated tiles as semantic
   acceptance targets;
2. physically composed and acknowledged each exact immutable offer before its
   input became eligible;
3. proved Pad's canonical editor and tab graph and Daybook's canonical
   calendar through the selected collection families;
4. performed a real Pad edit and Daybook task/navigation, preserved the
   ordinary Daybook-to-Pad shared-resource route, then activated the original
   Pad tab through the current acknowledged target and restored its edited
   content;
5. opened and navigated Desk's ordinary residual launcher with final-writer
   occlusion, then normally launched Sound Lab;
6. rendered Sound Lab's one generic instrument region with exactly eight
   readouts, two meters, and three status objects while preserving the
   exercised Pad and Daybook semantic state under stable session/owner lineage
   while complete replacement legitimately rebased retained wire IDs; and
7. retained complete CELL fallback without counting CELL-only or
   substantive-residual-only collection/instrument pixels as semantic-family
   evidence.

This pass closes the selected local reference-sink checkpoint. It does not
promote residual launcher content to a semantic overlay family or qualify an
external physical transport or hardware panel.

### Tranche D: expand ordinary controls across the remaining ecosystem

- field/action/semantic-overlay/rich-status: File Explorer, Grid, Agent,
  Streams, and ordinary prompts, informed by Library;
- item views: File Explorer tree/list, Grid where entity rows rather than cells
  apply, Agent transcript/review, Streams cards, and structured Desk launcher
  or taskbar surfaces;
- scalar/property controls: Agent settings and Sound Lab parameters, with
  Worlds as a design cross-check;
- text-grid extensions: Grid, with Observatory and Worlds read-only data as
  design checks; and
- viewport/scroll/split and the corresponding revision-bound intents wherever
  these ordinary consumers expose them.

Applet changes remain ordinary refactors toward shared widgets/builders. They
consume a completed lower seam; they never own that seam. Each feature bit
waits for its complete generic source, lowering, refusal, view, and applicable
return route.

### Tranche E: connect the remaining Akashic data-object planes

MegaPad's caller-bounded typed vector/series/resource operations, transaction
model, exact-offer shared view, and physical rendering are lightweight-green.
The Akashic instrument subset is already connected and accepted; do not
recreate it while adding the remaining families.

- add neutral vector/group/polyline and bounded-series capture plus distinct
  Akashic facade operations;
- map ordinary generic plot/waveform consumers into those planes without
  applet scenes;
- advertise each feature set only after its own complete refusal and product
  evidence exists; and
- prove series/plot/waveform reuse with Sound Lab and Observatory, and extend
  already-implemented instruments to Worlds/Observatory only when those
  ordinary consumers enter a selected profile.

Akashic image/resource production remains deferred until a real selected
consumer requires it; MegaPad's immutable RGBA8 upload and IMAGE endpoint do
not by themselves qualify an Akashic product path.

### Tranche F: one later ecosystem journey

After a coherent set of the later ecosystem seams is lightweight-green, run
one additional sequential physical Desktop journey that:

1. loads the complete startup Desk with Pad, File Explorer, Daybook, Grid, and
   Agent through their normal descriptors and ordinary draw lifecycle;
2. proves the newly selected Desk pane/item/field/action or semantic-overlay
   behavior rather than re-counting the accepted residual launcher;
3. proves the newly selected File Explorer, Daybook agenda, Grid, Agent, or
   Streams semantics through ordinary application state and input;
4. retains Sound Lab's accepted instrument graph and, only if the series
   tranche is selected, proves its waveform through the new generic series
   path;
5. requires every tested interaction to follow complete physical composition
   and exact selected-sink acknowledgement of its source revision;
6. retains complete CELL fallback without counting a residual-only future
   target as semantic-family evidence.

This later journey qualifies only the additional named families and consumers;
it does not retroactively invalidate or broaden the earlier acceptance.
Reset/resize, persistence, sustained cadence, renderer matrices, production
memory right-sizing, external UART transport, and hardware panel/touch
completion remain separate gates under their own contracts. The current
320 MiB qualification envelope is measured test headroom for the selected
checked-cold-source composition, not a content cap or a claim that production
retained-memory sizing is closed.

## 10. Validation policy between physical checkpoints

Permitted checks remain sequential, lightweight, and seconds-scale:

- neutral snapshot builder/validator and byte-oracle tests;
- capability/refusal and claim-ledger structural tests;
- pure lowering and semantic-continuity/wire-ID-rebase units;
- revision-bound event state-machine tests;
- deterministic off-screen control/object renderer units; and
- focused ordinary-widget routing tests for current-tranche consumers, with
  other inventoried consumers used as design checks rather than forced live
  dependencies.

The closed Tranche-C journey need not be replayed between lightweight slices.
Run another full physical journey only when a coherent later family reaches
its named checkpoint, or when a product/protocol change invalidates the
accepted boundary, and keep it under its ordinary sequential resource gate.
Cold source-load qualification, exact-full-core runs, Desktop smoke, broad
integration, persistence, sustained cadence, live viewers, renderer matrices,
external transport, and hardware-panel work remain separately scoped checks;
the `4b6a475`/`29bdfd6` X11 pass must not be cited as evidence for them.

## 11. Source map

Primary current-path sources:

- `akashic/tui/rich-terminal/engine.f`
- `akashic/tui/rich-terminal/engine-apt1.f`
- `akashic/tui/rich-terminal/uidl-control-planner.f`
- `akashic/tui/rich-terminal/uidl-instrument-planner.f`
- `akashic/tui/rich-terminal/hybrid-screen-producer.f`
- `akashic/tui/rich-terminal/uidl-semantic-content-stx1.f`
- `akashic/tui/uidl-menu-snapshot.f`
- `akashic/tui/uidl-collection-snapshot.f`
- `akashic/tui/uidl-data-graphics-snapshot.f`
- `akashic/tui/semantic-collections.f`
- `akashic/tui/data-graphics-model.f`
- `akashic/tui/draw.f`
- `akashic/tui/uidl-tui.f`
- `akashic/tui/widget.f`
- `docs/rich-terminal/APT-1-RETAINED-1.md`
- `local_testing/akashic_tui.py`

Current-profile consumers:

- `akashic/tui/applets/desk/desk.f`
- `akashic/tui/applets/pad/`
- `akashic/tui/applets/fexplorer/`
- `akashic/tui/applets/daybook/`
- `akashic/tui/applets/grid/`
- `akashic/tui/applets/agent/`
- `akashic/tui/applets/soundlab/`
- `akashic/tui/applets/streams/`

Adjacent cross-checks:

- `akashic/tui/applets/library/`
- `akashic/tui/applets/observatory/`
- `akashic/tui/applets/worlds/`

MegaPad seam sources are the paired worktree's `rich-terminal.f` and
`rich_terminal/retained_scene.py`, `rich_terminal/retained_wire.py`,
`rich_terminal/retained_view.py`, `rich_terminal/pygame_view.py`, and
`rich_terminal/display_cadence.py`.
