# Akashic rich-terminal engine and UIDL output contract

Status: normative implementation and current-head qualification contract for
the Phase 3 Akashic rich-terminal mode and its UIDL output integration. The
selected Desk composition advertises `CORE | CONTROLS` and implements one
draw-keyed aggregate projection of every visible attached UCTX: semantic UIDL
menus plus residual `GLYPH_RUN` coverage. Initial or uncertain surfaces use
hidden replacement and reveal; compatible later draws use `RET_DELTA` against
the exact sink-acknowledged target.

A local pygame journey at Akashic `d24540e` with MegaPad `c7045d6` passed the
complete Desk frame, Pad's real semantic File menu activation/open/close path,
a real Pad edit, a real Daybook task insertion and date navigation, and the
ordinary Daybook-to-Pad shared-resource handoff. It qualifies those exact
committed heads, including the eleven optimization commits through `e754ac1`,
at the host presentation API boundary `pygame.display.flip()`. The selected
Desk/Pad/Daybook contractual checkpoint is closed. This is not proof of
physical UART delivery, panel scanout, e-paper refresh, or touch; additional
semantic families remain unadvertised and outside this first acceptance gate.

This document defines the Akashic architecture, storage, ownership, projection,
and lifecycle contract for optional rich-terminal output. It does not define
APT-1 byte encoding. The mirrored `APT-1-WIRE.md`, `APT-1-RETAINED-1.md`, and
ownership ledgers define terminal protocol identity, transactions, reset, and
retirement.

The transactional CELL output path remains independently specified by
`AKASHIC-CELL-BACKEND.md`. Rich-terminal mode adds an optional retained
projection of the same UIDL/UCTX interface already rendered into cells. It does
not create a second application UI model, replace the cell screen, or weaken
ANSI fallback.

## 0. Current implementation status and next qualification

### 0.1 Near-term execution order

The hybrid CELL/retained architecture is fixed: CELL remains the complete
mandatory fallback; retained-only updates are valid when CELL is unchanged;
and complete replacement is reserved for initial construction, reset, resize,
or genuinely uncertain topology. The retained-availability handoff and ordinary
ACK-baselined delta path are implemented. Incremental producer cost is the
active work: unchanged UIDL document slices, acknowledged residual rows, stable
glyph identities, immutable retry totals, compact changed-item plans, bounded
draw-plane borrows, and touched-row CELL admission are now reused rather than
rediscovered.

With the selected display-backed vertical passed at `d24540e`/`c7045d6`, work
proceeds in this order:

1. add bounded, opt-in guest-instruction observation at the existing rich
   pipeline boundaries — implemented and focused-green at Akashic `1893c8f`
   with MegaPad `fb6d58f`;
2. profile real interactions and add a certified unchanged-frame fast path
   only if those measurements justify it;
3. remove uncomposed prototype residue, then add only the renderer-neutral
   text-area/text-grid and window/pane/tab semantics justified by real product
   use;
4. add claim-aware retained-row reuse and terminal-owned damage/cadence policy
   for the intended e-paper sink; and
5. close and measure the physical 115,200-baud UART plus panel baseline before
   selecting compression or a faster negotiated transport.

A CELL-less "pure rich" mode, unrelated semantic families, or broad terminal
expansion must not displace this sequence without new end-to-end evidence.

### 0.2 Guest phase-evidence boundary

`tui/rich-terminal/phase-profile.f` now publishes one private packed 64-bit
diagnostic event. Its low byte is a stable phase ID and its high 56 bits are a
transition sequence. Markers bracket aggregate snapshot acquisition, snapshot
import, control and claim planning, residual planning, reserve/wrap, hybrid
preflight, candidate validation, target packing, delta comparison and
normalization, RTAPT capture, commit precheck, final RTAPT audit, and retained
wire encoding. `OTHER` covers code outside those regions. Every public producer
entry, failure exit, and ACK wait returns to `OTHER`; CELL-only publication is
not charged to retained wire encoding.

The event is neither application state nor a terminal payload. MegaPad knows
only a caller-resolved complete eight-byte span in mapped guest memory and does
not name Akashic phases. Natural alignment is deliberately not required:
MegaPad Forth `VARIABLE` cells follow variable-length dictionary headers, while
the architecture supports 64-bit access at those addresses. The physical
acceptance client resolves `_RTPROF-EVENT` only after validating the first real
retained offer, while that exact offer is withholding its ACK. It then starts
MegaPad's generic observer with the current machine generation and a
caller-selected record bound. The default is 4,096 retained transitions; the
diagnostic host ceiling is 65,536. Reset, a generation mismatch, an invalid
span, or an inactive machine refuses attachment.

The observer samples after each exact guest retirement batch. Each observed
boundary is consequently an instruction interval, not a point: the phase may
have changed anywhere between the prior and current cumulative step count. A
sequence jump truthfully records coalesced transitions without inventing their
phases. Overflow retains the first bounded records and counts later dropped
records and transitions. A read or event error freezes only profiling and
cannot pause or fail the guest.

The first offer's pre-screen status is an ordered lower boundary, not a guest
freeze. While that offer withholds its ACK, unrelated guest work may retire
during the Forth lookup and observer-start RPC. The measurement therefore
begins at the observer's own exact returned step and batch identity and records
the nonnegative attachment lag from the earlier first-offer status. A changed
event sequence across lookup and attachment is likewise expected; the
observer's batch-quiescent initial snapshot owns the measurement identity. If
attachment lands inside a named phase, its in-window residency begins exactly
at the measurement boundary and is labelled as a truncated initial visit.

The measurement ends at the final qualifying offer's status sampled before
that offer was fetched and physically acknowledged; later post-ACK guest work
is excluded even though the observer is stopped afterward. Performance trace
schema v2 keeps the raw observer snapshot beside derived lower/upper residency
bounds. It marks attribution incomplete for coalescing, dropped records,
straddling end intervals, an open terminal phase, an observer error, or an
unproven lifecycle. These are retired guest instructions, not virtual cycles,
RTL clocks, or an emulator CPI model.

The instrumentation and host arithmetic are focused-green. No profiled
physical journey has yet been recorded at these heads, so they do not yet
justify an unchanged-frame fast path. The next sequential acceptance run uses:

```text
python local_testing/akashic_tui.py accept --profile desktop-apt1 \
  --phase-profile --phase-profile-max-events 4096
```

Only the resulting complete raw evidence may decide whether Step 2 in the
execution order should add that fast path or close with no change.

### 0.3 Current-head display-backed qualification

The checked-in APT-1 Desk composition reaches the retained path through
`tui/rich-terminal/uidl-hybrid-adapter.f` and
`tui/rich-terminal/hybrid-screen-producer.f`. The adapter captures a complete,
draw-keyed directory of menu semantics from every visible attached UCTX. The
producer combines those accepted controls with maximal residual glyph spans
from the same completed ordinary draw. The first or structurally uncertain
candidate is built hidden and revealed atomically. A compatible later candidate
is compared only with the exact physically acknowledged target, preserves
stable control and glyph identities, and emits only changed replacements in a
`RET_DELTA`. An ordinary draw that is retained-identical still receives a real
revision through one idempotent replacement fence. Glyph topology growth may
reuse caller-bounded invisible reserve slots; any uncertain provenance,
identity, topology, or capacity falls back to complete hidden replacement.

The earlier `screen-plane.f` one-object-per-cell bootstrap is no longer
composed. A full-screen one-object-per-cell frame is specifically forbidden as
product proof.

Implementation is not acceptance evidence by itself. The recorded
`d24540e`/`c7045d6` pygame journey showed the exact hybrid frame, activated
Pad's real File menu through revision-bound normal input, published its open and
closed states, edited Pad, inserted a Daybook task, navigated to a different
date, and opened the exact shared Daybook source in Pad through the ordinary
capability route. Every next input followed the exact newer post-flip offer
acknowledgement. This rerun qualifies those exact committed heads for the
selected Desk/Pad/Daybook checkpoint. Custom editor, calendar, and Desk areas
remain truthfully visible through residual spans until their own generic
semantic families land.

The earlier optimization rerun at `eedcfb9`/`4f074ae` and the
`3404fe9`/`8941782` baseline both used a
280x84 X11 viewer, a 360-second timeout, 0.75-second action delay, zero hold,
and `pygame.display.flip()` acknowledgement. Their traces are explicitly
non-normative, but the guest step and decoded-wire counters show where the
optimization tranche helped:

| Measurement | Baseline | `eedcfb9` | Change |
| --- | ---: | ---: | ---: |
| First-offer guest steps | 3.770B | 4.0865B | +8.4% |
| Post-first-offer guest steps | 948.0M | 715.5M | -24.5% |
| Total guest steps | 4.718B | 4.802B | +1.8% |
| Post-first-offer decoded frames | 1,386 | 221 | -84.1% |
| Post-first-offer decoded bytes | 190,131 | 24,541 | -87.1% |
| Total decoded frames | 2,818 | 1,653 | -41.3% |
| Total decoded bytes | 934,353 | 768,763 | -17.7% |
| Complete offers | 10 | 9 | -1 |
| Acceptance elapsed time | 181.465 s | 180.895 s | -0.3% |

The exact per-offer counters, viewer timing scopes, and derived UART lower
bounds are retained once in the non-normative
[`2026-08-30 optimization-rerun evidence`](../../local_testing/evidence/rich-desktop-optimization-rerun-20260830.md).

The later checkpoint-closing run adds Daybook navigation and the shared-source
handoff, so it is not a like-for-like member of that optimization comparison.
Its exact heads, invocation, milestone hashes, final scope, and boundary are
recorded in the
[`2026-08-30 Daybook-to-Pad acceptance evidence`](../../local_testing/evidence/rich-desktop-daybook-pad-acceptance-20260830.md).

The retained-identical Pad focus/activation-source revision now advances
without republishing the complete forest: total `OBJECT_DEFINE` frames fell
from 2,042 to 1,021 and `CONTROL_DEFINE` frames from 284 to 142.
Post-first-offer work and traffic are therefore materially lower. The first
offer was observed after 316.5M more guest steps, however, so the cold
end-to-end journey is not a compute-speed win and its single-run wall time is
effectively flat. The trace does not separate cold source compilation, initial
projection, and observation lag. The first offer still has 809 draws and
exactly 1,432 decoded frames / 744,222 bytes, so the later observation must not
be attributed to steady-state wire publication without a separate
measurement. Most of the post-first saving is the Pad focus/activation-source
stage itself, which fell from 284.5M to 69.0M guest steps. From the successful
activation-source milestone onward, the remaining journey fell only from
663.5M to 646.5M steps (-2.6%). This aggregate rerun cannot assign an
independent gain to each of the eleven commits.

### 0.4 Timing and usability interpretation

`Guest steps` above are retired MP64 instructions. They are neither the
emulator's deterministic virtual cycles nor clocks of a particular RTL or
silicon implementation. Acceptance elapsed time is host monotonic time for the
scripted journey and includes deliberate action delays, emulation, projection,
composition, acknowledgement, and observation. It is consequently useful for
regression comparison under the same configuration, but is not a prediction of
device response time.

The eight post-first actions retired 69.0--123.0 million instructions,
averaging 89.4 million. At the current 100 MHz target and even a four-clock
simple-instruction floor, that range projects to at least 2.76--4.92 seconds
before longer operations or memory stalls; guest execution would dominate the
corresponding post-first UART lower bounds. As a different arithmetic scenario,
a future 2 GHz MegaPad implementation sustaining 1--2 average CPI would spend
roughly 35--123 ms on that guest work, allowing transport or panel refresh to
become dominant. That CPI is an RTL/ASIC and memory-system target owned by
MegaPad, not a property Akashic can assert and not a reason to make the
instruction-level emulator reproduce pipeline bubbles. The current portable
RTL does not claim it.

Transport and presentation are separate latency terms. The current reference
viewer consumes complete UART batches in process and does not pace 115,200-baud
line time. At 8N1, the current 744,222-byte first offer has a derived no-gap
serialization lower bound of 64.60 seconds at 115,200 baud or 7.442 seconds at
1,000,000 baud. All post-first traffic totals 24,541 bytes: 2.13 seconds or
245 ms respectively, with individual updates at 0--601 ms or 0--69 ms. These
are not measurements and omit replies, scheduling, backpressure, composition,
and display refresh.

The pygame run proves host display-API submission and exact revision-bound
input ordering. It does not measure scanout, optical completion, touch
latency, or e-paper settling. A physical e-paper qualification must acknowledge
only after controller completion and the required settle interval, and should
record effective link throughput, projection and composition p50/p95/max,
offer-to-physical-ACK time, coalesced or superseded revisions, refresh mode,
and panel settle time. Until then the path proves the right safety and
authority semantics, not a claim that the physical product already feels
instantaneous.

A saved or precompiled Forth dictionary can reduce cold source-build time, but
does not reduce the interaction counts above once the same compiled words are
loaded. Steady-state improvement comes from Akashic/software and code-generation
work, MegaPad execution throughput, transport efficiency, and display policy;
those are related but distinct optimization layers.

The intended product producer is one renderer-neutral **hybrid projection**
derived from the ordinary UIDL and draw lifecycle:

1. capture real semantic controls wherever the ordinary UIDL element or
   mounted widget has renderer-independent meaning;
2. resolve which visible pixels those accepted controls claim, respecting
   ordinary clipping and paint order;
3. paint the same ordinary frame through the existing TUI draw boundary; and
4. emit maximal row-local, equal-style residual glyph spans only for visible
   cells not claimed by an accepted semantic control.

Menus, menu items, dialogs, text areas, selection/focus state, and other real
controls must not be flattened to glyphs merely because the horizontal
GLYPH_RUN path exists. Conversely, a custom draw surface does not acquire
invented semantics. Until a generic renderer-neutral snapshot exists for that
widget, its unclaimed final draw output is carried by residual spans. This is
how the existing mounted Pad editor and Daybook calendar remain visible during
the semantic expansion without adding applet-specific scenes or branches.

A semantic claim is exclusive for the selected rich renderer. The semantic
object owns rich representation and rich hit testing inside its final visible
claim; the residual encoder must skip that area. If the terminal lacks the
semantic family, capture refuses it, or admission cannot represent it, the area
remains unclaimed and therefore receives ordinary residual glyph coverage.
The authoritative UIDL/widget state, focus, action dispatch, and CELL fallback
remain unchanged in both cases.

`akashic/tui/rich-terminal/uidl-projector.f`, `uidl-driver.f`, and
`screen-plane.f` are uncomposed prototype residue. Their useful lifecycle and
identity ideas have already been forward-refactored into the live aggregate
adapter, control/claim planners, and hybrid producer. They must not be revived
or installed as parallel product paths. Remove them in a separate cleanup slice
after confirming that no remaining lower-stack diagnostic imports them.

Candidate work is linear and has one validation authority. Construction
produces one canonical key order and one frozen candidate; admission performs
one full validation traversal and records the checked counts, extents, quotas,
and identity correlations consumed by later adapter and publisher stages.
Those stages must not rescan the same complete candidate. When bytes remain in
a caller-owned mutable bank, one final mutation-safety validation immediately
before seal/publication is required. It is the only permitted repeated full
traversal; copying into an immutable engine-owned attempt bank removes the need
for it. Uniqueness and stable-ID reuse use a linear merge over canonical keys,
not prior-item searches, repeated-minimum scans, or other quadratic work.

The detailed hybrid candidate contract is
[UIDL-PROJECTION-CANDIDATE.md](UIDL-PROJECTION-CANDIDATE.md). If a later section
of this document describes the earlier LABEL-only driver or the superseded
per-cell screen bootstrap as the product projection, this section and that
candidate contract take precedence.

## 1. Non-negotiable architecture

UIDL is the sole application-facing UI description. A hosted component owns its
ordinary domain state and uses the existing UIDL element tree, bindings,
subscriptions, semantic widgets, dirtying, layout, focus, and event mechanisms.
The same `UCTX` owns that UI for the complete activation lifetime.

The implementation has three layers. One generic, consumer-neutral Akashic
engine contract owns retained lifecycle for one live enhanced terminal
session. The current `RTAPT` provider implements that contract over APT-1 with
caller-bounded storage and has no knowledge of `AHOST`, `AHS`, CINST, UCTX,
Desk, or any applet. An explicit composition may use that engine outside Desk
and UIDL-TUI without acquiring a second protocol or session implementation.

An immutable caller-owned `RTE` facade is the operation boundary above a
concrete provider. The landed facade exposes neutral status, owner,
transaction, region, GLYPH_RUN definition/replacement and plan preflight,
update-state observation, and storage-disjoint operations plus one opaque
provider context. Genuine semantic control families extend this neutral
boundary as their contracts land; UIDL code must not encode a menu or another
control as a misleading GROUP or GLYPH_RUN. Only the provider bridge names both
vocabularies; generic UIDL code neither names nor loads `RTAPT`.

Above it, UIDL-TUI owns a renderer-neutral optional-projection lifecycle. The
selected aggregate adapter implements that lifecycle's private adapter table
and adapts UIDL semantics for the generic engine facade. Desk and the applet host
express only document visibility, quiesce, and final detach through ordinary
UIDL-TUI words; they neither select the adapter nor name its provider. A
Desk-owned UIDL context, when present, follows the same lifecycle as a child
UCTX; Desk UI code does not author a retained scene manually.

The following are forbidden application interfaces:

* retained-backend or APT discovery through `IEND.SERVICE-XT`;
* applet acquisition of a rich-terminal broker, scope, owner, or lease;
* applet calls that begin, define, update, commit, abort, step, replay, or retire
  a terminal scene;
* applet-visible session, epoch, owner, region, object, resource, series,
  revision, transaction, opcode, frame, or terminal-capacity identities; and
* a handwritten projection controller maintained beside an applet's UIDL.

There is therefore no rich-terminal service identifier and no rich-terminal
endpoint per Desk or per applet. The mode/output backend is an internal
composition capability, not an application-visible object. "Global" in this
contract means only that one internal backend serializes one terminal session.
It is held by the explicit composition and UIDL host, not published as
application authority.

Retained terminal state is a derived output materialization. The UIDL tree,
semantic widget state, and bound application state remain authoritative. The
backend may keep a bounded copied projection recipe, dirty state, mappings, and
wire tombstones so that transport is incremental and reset is replayable. That
cache is not a second application-owned scene and has no independent mutation
API.

"Storage" in this contract means only caller-provided volatile memory for that
derived output cache and its finite wire-owner lifecycle. It is not document or
application persistence, a recovery database, or a second application layer.
Reconstruction after terminal reset, resize, or loss re-derives output from
authoritative UIDL; it never reconstructs application state from terminal data.

### 1.1 Proof boundaries and product value

This contract is deliberately stronger than a conventional ANSI or rich
terminal driver. A conventional interface commonly proves that bytes or draw
commands were accepted by a buffer. That is enough for a synchronous display
whose terminal owns all later consequences; it is not enough for mutable
retained state, reconnect/replay, a slow asynchronous physical panel, or touch
whose meaning depends on exactly what the user could see.

The proof-like records are not interchangeable:

| Boundary | Distinct question it answers |
| --- | --- |
| Session and epoch | Does this message still belong to the current attachment? |
| Admission and credit | Can the complete operation fit without hidden unbounded storage? |
| Transaction and revision | Did one complete logical model change commit atomically? |
| Immutable offer and sink acknowledgement | Did this exact composite cross the selected sink's documented completion boundary? |
| Revision-bound input | Was this action interpreted against the exact image and hit map actually made input-eligible? |

Equivalent mechanisms appear separately in retained graphics, presentation
fences, flow-controlled protocols, and replicated-state systems, but this
end-to-end chain is not baseline terminal-interface industry practice. The
design intentionally spends more engineering effort to preserve authority
across guest, transport, renderer, physical display, and input. Deduplication
should remove repeated assertions or evidence copies; it must not collapse two
records that answer different questions.

That chain enables behavior a stripped-down terminal driver cannot safely
promise: latest-complete-view coalescing while e-paper is busy; touch bound to
the exact completed panel revision; bounded backpressure without guest
reentrancy; deterministic reconnect and replay after loss; renderer-neutral
CELL fallback plus semantic output; and evidence that distinguishes model
commit, host presentation, UART delivery, and physical panel completion.

## 2. Authority and identity

The generic engine is the sole Akashic component allowed to emit retained wire
frames. It owns discovery state, the shared rich-terminal update transaction and
revision domain, resource-upload serialization, wire-owner lifecycle, replay,
and retirement. The APT shell remains the sole owner of the PT session and
terminal input; the engine consumes that session's public ABI and never creates
another UART reader, writer, or service loop.

`RUHA` represents each attached UCTX with one bounded local record containing
the exact host-owned slot address, captured `AHS.ID`, UCTX address, visibility,
resolved region geometry, lifecycle state, and a nonzero private attachment
token. The adapter re-proves that the slot still belongs to its installed host,
retains the captured ID and UCTX, has UIDL, and remains callable before using
that record. Focus, tile position, an `id=` string, a region pointer, or a UIDL
element pointer alone grants no authority.

These document records own no wire scene or object identities. At a completed
draw they contribute copied menu snapshots and directory entries to one
aggregate candidate. The screen-level hybrid producer alone owns the configured
wire owner and generation, root region, and stable control/glyph target banks.
Neither attachment tokens nor UCTX addresses cross the provider boundary.
Wire owner and object identities may rotate after reset without changing the
live UCTX or UIDL element identity.

Terminal reset, replay, resize, or loss of terminal cache must not mutate UIDL,
widget state, application state, documents, media, samples, or any other domain
state. Conversely, retained terminal state is never authoritative input to an
applet.

## 3. Internal status values

The host/backend boundary uses these stable ordinary status values:

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `RTERM-S-OK` | The host operation or projection was accepted. |
| 1 | `RTERM-S-WOULD-BLOCK` | No downstream progress is currently possible; retry from the host loop. |
| 2 | `RTERM-S-UNAVAILABLE` | No usable negotiated retained backend or required semantic family exists. |
| 3 | `RTERM-S-CAPACITY` | Caller-owned capacity cannot store the candidate or a checked limit cannot establish eligibility/admit materialization. |
| 4 | `RTERM-S-STALE` | The UCTX, activation binding, source revision, or terminal materialization is no longer current. |
| 5 | `RTERM-S-INVALID` | An argument, semantic snapshot, storage configuration, state transition, or callback result is invalid. |
| 6 | `RTERM-S-SESSION-LOST` | The enhanced session crossed a structural loss boundary. |
| 7 | `RTERM-S-SOURCE` | A semantic resource or series source failed. |

These statuses do not throw through an applet callback and are not returned to
application rich-terminal code, because no such code exists. Local attachment
and aggregate-capture status leaves application state intact. Only `INVALID`
and `SESSION_LOST` are sticky backend-global failures; `CAPACITY` and `SOURCE`
are bounded projection refusals which preserve complete CELL fallback. A
post-`OPEN` structural loss never makes raw ANSI output safe.

In the APT-1 composition, that first fatal result is also a neutral
publisher fault latch. It survives ordinary scheduler calls so a later call
cannot silently turn a failed output lifecycle back into apparent success.
This persistence is only an in-memory status latch: it owns no UIDL or
application data, and it is cleared only by whole-publisher reconstruction or
final retirement. Synchronized teardown may still poll and settle work that
was already admitted; the latch grants no authority to start new publication
during teardown.

`RTERM-S-WOULD-BLOCK` is transport progress, not local projection-capacity
failure. Already accepted desired state remains accepted while egress is
blocked. `RTERM-S-CAPACITY` and `RTERM-S-SOURCE` refuse the affected aggregate
attempt without changing any UCTX or CELL state. Validation and preflight
refusal are fail-before-owner-mutation; refusal after capture begins cancels the
partial retained transaction and preserves or retires the exact aggregate owner
according to its recorded lifecycle phase.

## 4. Generic engine construction and caller-owned storage

The live consumer-neutral facade in
`akashic/tui/rich-terminal/engine.f` exposes one immutable provider context
and the operations required by the hybrid producer:

```forth
RTE-FACADE-BYTES
RTE-VALID?
RTE-STORAGE-DISJOINT?
RTE-STATUS@
RTE-UPDATE-STATE@

RTE-LIMITS-BYTES
RTE-LIMITS-VALID?
RTE-LIMITS@

RTE-HYBRID-PLAN-BYTES
RTE-HYBRID-ADMISSION-BYTES
RTE-HYBRID-PREFLIGHT
RTE-CONTROL-PREFLIGHT
RTE-GLYPH-RUN-PREFLIGHT

RTE-OWNER-OPEN
RTE-OWNER-STATE@
RTE-RETAINED-BEGIN
RTE-REGION-DEFINE
RTE-CONTROL-DEFINE
RTE-CONTROL-REPLACE
RTE-CONTROL-DROP
RTE-GLYPH-RUN-DEFINE
RTE-GLYPH-RUN-REPLACE
RTE-RETAINED-SEAL
RTE-RETAINED-CANCEL
RTE-OWNER-DROP
```

The facade owns no storage, transport, host, UCTX, Desk, or application
authority. The APT-1 bridge is the only module that names both `RTE` and
`RTAPT`; generic UIDL capture and the hybrid producer do not depend on
provider opcodes or layouts. Public byte-count words, validators, and
storage-disjoint queries are the ABI authority. Documentation must not freeze
private descriptor offsets or copy an obsolete facade size.

The current neutral object vocabulary is `CONTROL` plus `GLYPH_RUN`.
`CONTROL` represents real menu bars, menus, items, and separators with
renderer-independent state and hierarchy. `GLYPH_RUN` represents unclaimed
ordinary draw output. One hybrid plan binds their exact surface, source
generation, plans, text references, copied text banks, and candidate attempt.
`RTE-HYBRID-PREFLIGHT` validates that complete immutable combination and
returns a checked admission summary; it does not reserve an owner, mutate
provider state, or emit wire.

After successful preflight, the producer opens one aggregate screen owner and
captures a hidden replacement or active delta through the same facade. Initial,
reset, resize, topology-changing, and otherwise uncertain candidates use
replacement and reveal. A compatible candidate begins the retained transaction
in delta mode through `RTE-RETAINED-BEGIN` and uses only control/glyph
replacement operations. Seal or commit failure advances neither CELL nor
retained authority. Exact owner drop or confirmed session destruction is
required before owner storage can be reused.

`RTE-LIMITS@` copies one coherent current-epoch neutral capability snapshot.
The selected Desktop policy currently advertises exactly `CORE | CONTROLS`;
vector, image, instrument, series, and cadence families remain unadvertised.
Limits and caller-supplied spans, rather than a compiled objects-per-applet or
strings-per-control constant, bound owners, objects, operations, text, payload,
and update bytes.

The opt-in composition in `tui/desk-apt1.f` derives all volatile provider,
aggregate-adapter, and hybrid-producer storage from its selected maximum
surface, installed-document capacity, UIDL element capacity, and UIDL string
capacity. It owns one screen owner and one root retained region. Construction
preflights every checked multiplication/addition, alignment, nonwrapping span,
and pairwise storage overlap before publishing live state. Attach, capture,
publication, replay, and teardown then allocate no hidden heap or XMEM storage.

Caller-owned candidate bytes are copied or held behind an exact immutable
attempt correlation. Public entry points perform constant-time descriptor,
phase, generation, and alias checks. A final full validation is permitted only
where a caller-owned mutable bank remains publication authority; an
engine-owned immutable copy instead uses its generation and seal. Refusal
leaves the selected candidate and all admitted storage valid for the precise
retry or fallback path described by the producer.

The former LABEL plan, per-binding materializer, and per-cell producer layouts
were development prototypes and are not part of this contract. Their copied
offset inventories have been removed rather than retained as a second,
contradictory ABI. Git history remains the design-history source.

## 5. UIDL semantic projection contract

This section describes the semantic half of the hybrid candidate, not a
semantic-only scene. Semantic capture and ordinary drawing happen within the
same UCTX revision and normal paint lifecycle. The planner first selects
supported semantic items, then derives their final visible claims, and only
after ordinary painting derives residual glyph spans from unclaimed cells.
Neither half may independently enumerate the application UI.

### 5.1 One semantic tree, multiple output paths

UIDL element semantics are backend-neutral. The existing UIDL-TUI renderer
continues to paint the CELL/ANSI representation. The rich integration adds
an optional projector registry keyed by UIDL element type; it does not replace
the element's CELL render XT or introduce a second document.

Every retained-capable semantic element or widget has:

1. a complete CELL rendering usable on baseline ANSI and CELL-1 terminals;
2. one backend-neutral semantic snapshot contract;
3. an optional retained projector supplied by the rich integration; and
4. the ordinary UIDL binding, subscription, dirty, layout, focus, and event
   behavior appropriate to that element.

Existing semantic elements such as containers, labels, `media`, `canvas`,
`range`, `indicator`, and `status` may gain retained projectors where their
meaning is sufficiently defined. New readout, meter, plot, waveform, image, or
other rich types are added as semantic UIDL elements/widgets, with real CELL
fallbacks. They are not raw aliases for APT opcodes or wire object families.

The semantic registry is not limited to text-like elements or to elements whose
ordinary renderer happens to draw text. Existing high-level chrome such
as menubars, menus, items, dialogs, and text areas is projected as controls once
the corresponding neutral snapshot and terminal capability are real. Mounted
widgets may publish through an equivalent generic widget-semantic hook. A
renderer must never infer a control merely by recognizing glyphs in the final
screen.

There is no generic `<rich-terminal>` or `<apt>` escape hatch, raw scene
element, owner attribute, terminal ID attribute, or transaction element. A
generic canvas does not become an arbitrary retained command stream. A richer
projector is valid only when a semantic element defines enough backend-neutral
meaning for both CELL and retained renderers.

Supported and admitted semantic items own their final visible claim in the
rich plane. Ordinary fallback paint is still produced for CELL, but the hybrid
residual encoder excludes claimed cells so the rich compositor does not render
or hit-test two representations of one control. Unsupported or refused
semantic items make no claim; their normal drawing therefore remains visible
through the residual path.

### 5.2 Stable identity and geometry

Within one attached UCTX, the backend derives stable projection identity from
the element's pool index and an explicit semantic subkey when one element owns
several retained items. `id=` remains the human-facing UIDL identity and must
be unique when supplied, but it is not hashed into wire authority.

An unchanged semantic element retains its private wire identities across value
updates, minimize/restore, tile movement, full-frame transitions, and relayout.
UIDL document teardown ends that identity. A new UCTX never inherits it even if
the new document reuses every `id=` string.

Bounds come from resolved UIDL layout and are copied into the candidate
relative to its root. The selected candidate metadata carries the positive
root height and width used to normalize and validate those bounds. When a
materializer submits that neutral geometry, the RTAPT provider converts it
directly to the retained profile's full `UNORM32` precision; it does not
truncate through an incidental narrower normalized format. Region movement
changes the private owner region. Layout changes may replace derived object
geometry while preserving element and wire identities. Applications do not
maintain parallel coordinates.

### 5.3 Static and dynamic state

The projector classifies semantic snapshots into:

* static definition state: kind, relationships, formatting, style, labels,
  units, axes, immutable vector geometry, and renderer-independent semantic
  bounds;
* layout state: resolved bounds, clipping, stacking, and visibility inherited
  from UIDL layout; and
* dynamic state: current scalar values, status, media revision, series source
  revision/history, and ordinary element visibility.

These revisions are tracked separately. A scalar, status, or sample-only UIDL
update cannot mark an unchanged static definition dirty. Relayout cannot mint
new item identities. Reset invalidates terminal materialization, not the
classification or UCTX identity.

UIDL dirtying is the only ordinary projection trigger. Applets update bound
state or semantic widget state and use the existing `UIDL-DIRTY!` path. They do
not separately notify the retained backend. The projector must still compare
semantic revisions so a conservatively dirtied ancestor cannot cause unchanged
definitions to be retransmitted.

### 5.4 Semantic resources and series

Image/media and series data belong to their semantic UIDL widget models. Their
snapshot APIs are backend-neutral and usable by CELL renderers, retained
projectors, tests, or future output backends. Application code may populate
those ordinary models; it never implements an APT callback or passes a terminal
descriptor.

A resource snapshot contains semantic format, dimensions, exact byte length,
content digest, monotonically increasing source revision, and a bounded pull
source. The first retained image format is raw row-major sRGB straight-alpha
RGBA8 with no row padding; byte length is checked `width * height * 4`. The
backend calls the source only into its owned staging span, copies or consumes
output before return, and retains no returned byte pointer.

A series snapshot declares semantic sample format, timestamp mode, capacity,
current count, time-axis metadata, monotonically increasing source revision,
and a bounded pull source. The source writes complete records into backend-owned
staging, makes positive progress until the declared count is exhausted, returns
stale without output for an obsolete revision, performs no allocation or
blocking work, and never calls back into UIDL or the backend.

The semantic widget must keep the exact current revision reproducible while its
UCTX is live and that revision remains current. A newer widget revision
supersedes incomplete old work at a transaction-safe boundary. The backend may
pull a source in bounded chunks, but terminal publication of one semantic
history remains atomic under the admitted transaction bounds.

Resource replacement uses a fresh increasing private wire resource ID, uploads
and digest-commits the candidate, atomically replaces surviving references,
then drops the old unreferenced resource. The previous terminal resource remains
authoritative through any failed read, upload, digest, or replacement. Admitted
capacity includes the required old/new overlap.

The backend quiesces every retained source context synchronously before the
host calls arbitrary application shutdown or frees application state. No source
callback is permitted after quiesce succeeds.

## 6. UIDL-TUI projection lifecycle and aggregate adapter

UIDL-TUI's public host-facing lifecycle remains renderer-neutral:

```forth
UTUI-VISIBLE!  ( visible -- )
UTUI-QUIESCE   ( -- status )
UTUI-DETACH    ( -- )
```

Outer composition alone installs and enters the private optional-projection
seam:

```forth
_UTUI-PROJECTION-ADAPTER!
    ( context attach project relayout quiesce detach -- flag )
_UTUI-PROJECTION-ATTACH
    ( document-binding visible -- status )
```

Desk, app-shell, applet-host, and applets neither choose a provider nor receive
terminal authority. Installation is immutable. Attach borrows the exact live
document binding for the synchronous call and stores only a private opaque
token in the active UCTX.

The selected implementation of that seam is
`tui/rich-terminal/uidl-hybrid-adapter.f` (`RUHA`). It owns a
caller-bounded local record for each attached document and double-buffered
aggregate directory, semantic-record, and copied-text banks. It does not open a
terminal owner, inspect the CELL plane, call the `RTE` facade, or publish
retained objects. Those responsibilities belong to the one screen-level hybrid
producer.

### 6.1 Attach and local authority

Composition installs `RUHA` and binds its neutral
`RUHA-AHOST-UIDL-READY` callback through the existing applet-host hook. Attach
validates the exact host, slot identity, UCTX, region, and visibility tuple,
allocates one preconfigured local record, and returns a nonzero generation
token. Reuse, foreign-host tuples, stale slots, mismatched UCTXs, and exhausted
caller capacity fail without changing aggregate or wire state.

The token names only local attachment state. It is not a wire owner, object,
region, or capability. Every visible document in the current Desk contributes
to one aggregate screen candidate and the selected composition owns one wire
owner and one retained root region.

### 6.2 Project and completed-draw aggregation

Project and relayout mark only the corresponding document record dirty. At one
completed ordinary draw boundary, `RUHA-SNAPSHOT-FOR@` assembles every visible
attached document with a nonempty menu forest into the inactive aggregate bank.
Dirty documents are recaptured through the normal UIDL menu snapshot path;
known-empty documents add nothing; unchanged nonempty document slices are
validated and copied from the prior published bank. Capture switches through
each exact UCTX without retaining a borrowed application pointer.

Directory entries preserve attachment token, slot identity, surface geometry,
and exact record/text slices. Publication fills complete snapshot metadata and
changes the active bank selector last. Capture failure leaves the previous bank
available only for private reuse; it cannot be borrowed as the requested newer
draw. The hybrid producer synchronously copies the exact draw-keyed snapshot
into its own attempt before asynchronous owner work begins.

The producer then plans controls and claims per document, unions all accepted
claims, and builds one row-major residual glyph plane from the same completed
CELL draw. Semantic items and residual spans are admitted and published as one
candidate, never as independently advancing producers.

### 6.3 Relayout, visibility, and refusal

`UTUI-VISIBLE!` and relayout update the local document record and invalidate
any aggregate snapshot that no longer describes the current geometry. Hidden
documents contribute neither controls nor claims; their application and CELL
state remain authoritative. Restore recaptures the latest ordinary document at
a later completed draw.

Local capture `CAPACITY`, `UNAVAILABLE`, or `STALE` status does not grant a
partial rectangle or blank reservation. No aggregate candidate is published for
that draw, and complete CELL fallback remains available. Provider admission or
transport refusal occurs later at the screen producer and cannot mutate an
individual UCTX or invent a per-document wire owner.

### 6.4 Pre-shutdown quiesce

Quiesce is host-owned and runs before arbitrary `APP.SHUTDOWN`. It invalidates
the aggregate snapshot, changes the exact local attachment from attached to
quiesced, and makes later project/relayout calls stale. `RUHA` owns no resource
or series callbacks, so this boundary retains no application callback or source
pointer. Repeated quiesce for the exact token is idempotent.

A quiesce refusal prevents application shutdown and preserves the complete host
tuple for retry or quarantine. It never frees UCTX, CINST, region, UIDL, widget,
or slot state speculatively.

### 6.5 Detach and aggregate retirement

Final `UTUI-DETACH` runs after successful quiesce and application shutdown but
before UCTX, CINST, region, or host-slot free. The adapter invalidates the
aggregate and clears the exact local attachment record. Only then may UIDL-TUI
clear the document and the host free its state.

Individual document detach creates no wire tombstone because individual
documents do not own wire scenes. The one aggregate screen owner is rebuilt
from the remaining visible attachments. Final product teardown retires that
owner through the screen producer and provider before the facade, PT session,
or ANSI ownership is released. A failure at either local detach or aggregate
owner retirement preserves the smallest exact retry authority and blocks unsafe
free.

### 6.6 Generic applet-host composition seam

The generic applet host names no rich-terminal engine or wire protocol. An
explicit product composition may configure one neutral `AHOST` callback plus
an opaque, separately owned context:

```forth
AHOST-UIDL-READY!  ( xt context host -- )
\ xt                ( host slot context -- ior )
AHOST-QUIESCE-ALL  ( host -- ior )
```

Desk exposes only the constructor boundary
`DESK-HOST-LIFECYCLE! ( init-xt fini-xt context -- )`; both callbacks use
`( host context -- ior )`. After its generic host and runtime services are
initialized but before launching any child, Desk invokes composition init,
which may install the exact `AHOST-UIDL-READY!` callback pair. Immediately
after `AHOST-DRAIN` succeeds and before freeing any Desk runtime state, it
invokes composition fini so the callback and every borrowed host pointer can
be removed. It does not inspect the context, name an output backend, or
allocate composition storage. A fini refusal hard-gates every later Desk
destructor. Desk claims the init phase before entering the callback, so the
matching fini is also invoked after an init refusal or throw; composition fini
must therefore be safe and idempotent for every partially initialized state.

The host invokes the callback exactly once for a launch after ordinary UIDL
load and initial region assignment have succeeded, while the exact UCTX is
active, and before crossing the application-initialization boundary. A zero
callback is the baseline configuration. The callback may capture the exact
binding and enter UIDL-TUI's private projection attach, but the host neither
allocates adapter state nor learns the callback context's type. A callback
refusal enters normal transactional launch rollback.

Each linked slot records an independent retirement phase: `LIVE`, `QUIESCING`,
`QUIESCED`, `SHUTDOWN-CLAIMED`, or `DETACHED`. `AHS.STATE` remains the ordinary
running/minimized/focused state so authority validation sees the original live
tuple through final detach. On the first close attempt the host stores
`QUIESCING` before calling `UTUI-QUIESCE` and, for a child which crossed
application init, invoking its optional `APP.QUIESCE-XT`. Only both barriers
plus the final UCTX save succeeding store `QUIESCED`. A refusal preserves the
linked slot, ID, CINST, UCTX, region, UIDL buffer, projection attachment, and
exact activation tuple. The slot becomes noncallable: focus, input, tick, paint, and
application close callbacks must not reach it, while a later host
quiesce/drain attempt may retry the barrier.

After quiesce succeeds, the host stores `SHUTDOWN-CLAIMED` before activation or
`APP.SHUTDOWN`, so a thrown shutdown callback is never repeated. It then runs
`UTUI-DETACH`, the sole public final detach for both projection and document,
with the exact UCTX restored. `AHS.HAS-UIDL` remains true until that detach
succeeds. A detach refusal preserves every child
resource and returns a not-closed result; it cannot trigger relayout or a drain
spin. Only `DETACHED` authorizes owner-resource release, unlink, callback
notification, and freeing the UIDL buffer, UCTX, region, CINST, and slot.

Aggregate close negotiation treats a slot already past `LIVE` as previously
approved, without invoking application code. The outer lifecycle owner then
retries `AHOST-QUIESCE-ALL` and maps an actual barrier refusal to its own defer
or quarantine state. Any relayout implementation that walks `AHS` directly
must skip noncallable slots completely; in particular it must not activate the
slot, replace or free its retained region, or run ordinary UIDL relayout while
retirement is unresolved.

## 7. Frame projection and atomic publication

UIDL-TUI CELL painting remains the universal path. In the rich composition,
painting a dirty attached UCTX also stages its retained projection. The global
screen flush and internal retained backend then serialize through the one APT
output publisher and the one shared transaction-ID/revision clock.

When one logical UI frame changes both CELL and retained state, the unified
output publisher commits the applicable CELL spans/cursor and retained
operations in one atomic terminal update transaction, delimited on the APT-1
wire by `PRESENT_BEGIN` and `PRESENT_COMMIT`. A failed combined commit cannot
advance the screen front buffer or the retained materialization independently.
A frame with no retained changes remains an ordinary valid CELL transaction; a
retained-only update may use `CELL_NONE` under the wire recovery rules.
When a completed draw is retained-identical but still requires a new physical
revision, the producer uses one idempotent replacement of an acknowledged
retained slot as the nonempty `RET_DELTA` revision fence. It prefers a canonical
invisible glyph slot and falls back to an unchanged control or visible glyph;
only a model with no reusable object may take complete replacement instead.

`PRESENT_BEGIN`, `PRESENT_COMMIT`, and `presentation_epoch` are frozen APT-1
wire names only. There is no protocol object or Akashic architectural layer
called a Presentation; the Akashic concepts here are retained materialization,
transactions, and unified publication.

The backend serializes dependencies before references and preserves static
definition/drop ordering. It may coalesce superseded scalar, visibility, and
complete source revisions before publication. It may not coalesce across owner
generation, reorder around definition/drop, invent series samples, or split an
ordinary semantic update into terminal-visible partial state.

The CELL representation remains complete even when a retained counterpart is
visible. Retained projection may enrich, overlay, or replace physical treatment
inside its owned region according to the renderer contract, but loss or absence
of the optional rich-terminal path leaves a usable UI rather than a blank
reserved area.

## 8. Bounded backend service and cadence

Only the terminal/Desk owner loop advances publication. The selected producer
is entered through the unified publisher callbacks:

```forth
RTHP-STEP
  ( cols rows generation work-budget producer
    -- status more-work? output-needed? )
RTHP-PREPARE
  ( cols rows generation producer -- status )
```

`work-budget` is a positive composition-selected service bound. The producer
returns truthful quiescent, more-work, output-needed, backpressure, or
structural status. It never spins until credit appears, waits for a response,
allocates a resend buffer, recursively pumps Desk, or calls `PT-SERVICE` as a
second session owner.

The service owns the discovery-transition obligation. On `AVAILABLE`, it forces
the exact current screen through the unified publisher and schedules complete
initial aggregate materialization; after reset it schedules the same complete
replay in the new epoch. A terminal `CELL-ONLY` answer leaves local attachments
and application lifecycle intact but never schedules `OWNER_OPEN`.

Fairness applies at protocol-safe boundaries. Once the session-global immutable
resource upload is open, it completes or aborts before another upload,
transaction, or lifecycle request begins. A large image or series cannot
permanently starve current scalar/readout changes in other UCTXs.

Physical display cadence is a renderer policy over committed global revisions,
not an application API. UIDL/widget updates retain their own domain timestamps;
cadence never invents sample timing. Input is delivered only against the exact
sink-completed revision as required by RETAINED-1.

### 8.1 Slow-refresh and e-paper endpoints

The intended physical terminal may be an e-paper display, including a future
touch-capable full-color panel. Such a sink can remain busy far longer than one
guest draw. Protocol parsing, credit, lifecycle settlement, and logical commits
continue while renderer cadence coalesces superseded display opportunities to
the newest immutable complete composite. Coalescing may skip an intermediate
physical image; it may not merge model revisions, acknowledge an image that was
not presented, or make pending controls input-eligible.

The selected renderer owns panel representation and all device-specific
policy: damage planning, partial versus full refresh, ghosting cleanup,
controller waveform selection, color conversion, rasterization, clipping,
buffer allocation within caller-provided bounds, and the final transfer to the
panel. UIDL, Desk, Pad, Daybook, and the generic projection contain none of
those decisions.

For a real e-paper endpoint, display acknowledgement occurs only after the
driver's sink-specific completion boundary, such as the controller's exact
busy-to-ready transition plus any required settling rule. Touch for a revision
is accepted only after that boundary and is resolved against the hit map for
that exact completed composite. While a newer logical composite or panel
refresh is pending, the sink may retain only bounded raw intent or withhold
input. It may normalize that intent only under the RETAINED-1 rule against the
exact completed revision; it must not route a touch against either superseded
or unseen state.

The current pygame acceptance sink acknowledges after `pygame.display.flip()`.
That is useful host presentation-API evidence, but it does not establish panel
scanout, optical update completion, or an e-paper controller completion.
Documentation and
artifacts must name that weaker boundary accurately.

## 9. Composition and host order

Any explicit rich product composition may construct the generic engine and
bind an appropriate consumer adapter. The Desktop APT-1 profile does so from
`tui/desk-apt1.f`, binding the hybrid producer through UIDL-TUI's private
lifecycle seam. This is product composition, not engine ownership by Desk. A
standalone shell or another non-UIDL Akashic consumer may compose the same
engine without loading Desk or UIDL-TUI. The baseline `desktop` profile does
not load the APT-1 engine or construct rich-terminal state.

The deployment boundary is strict. MegaPad owns the optional boot-loaded
`rich-terminal.f`; a rich product profile loads it before any Akashic
rich module. Akashic never source-`REQUIRE`s or copies that module. Its rich
modules consume only the already-loaded public PT ABI. Baseline profiles load
neither the optional PT module nor the Akashic rich modules, so their source
closure, startup, storage, and output behavior remain unaffected.

The Desktop leaf constructs its concrete layers in dependency order: PT
session, neutral `APTSCB`, caller-bounded `RTAPT`, immutable `RTE` facade,
unified `RTAPTSCB` publisher attachment, the draw-keyed `RUHA` aggregate
adapter, the `RTHP` hybrid producer, and finally the `APTAS` shell owner. Desk
sizes aggregate directory, semantic record/text, claim, residual-span, and
frozen-attempt storage from its installed-document and screen bounds. The
producer installs one hybrid `STEP`/`PREPARE` contribution in the existing
publisher seam; it does not create another session or application scene. Setup
and release continue to publish explicit phases so a constructor or destructor
refusal retains the smallest exact retry authority rather than clearing an
uncertain terminal-output lifecycle.

The name `desk-apt1.f` identifies that opt-in product composition, not a second
Desk implementation or a rich Desk behavior. Both baseline and APT-1 products
load the same `applets/desk/desk.f`; Desk supplies only neutral host-lifecycle
hooks. App descriptors, UCTX, UIDL trees, and Desk layout behavior do not
branch on regular versus rich rendering.

Desk and applets remain ordinary, renderer-neutral UIDL producers. They do not
call the APT-1 adapter, select a terminal renderer, or own the output
materializer. `desk-apt1.f` is the outer product leaf that binds the neutral
UIDL lifecycle callbacks to the APT-1 output adapter; that binding does not add
a rich variant to Desk or any lower-level component.

UIDL-TUI now presents `UTUI-VISIBLE!`, `UTUI-QUIESCE`, and `UTUI-DETACH` to
Desk, app-shell, and applet-host. Those layers contain no adapter or provider
choice. The `_UTUI-PROJECTION-*` attach/install seam is private to outer
composition, where backend choice remains; no compatibility aliases preserve
the former renderer-specific lower-layer surface.
The leaf disarms Desk's pending constructor tuple after each `DESK-RUN`
attempt, including a throw; a quarantined instance keeps its already-copied
tuple, while a later plain Desk constructor cannot resurrect a partial rich
composition after the outer storage was released.

The selected product profile supplies explicit `CORE | CONTROLS` retained
capability and capacities derived from its maximum screen and UIDL bounds. The
`RTE` facade and RTAPT provider admit the exact combined control/glyph plan,
one aggregate owner, one region, its current UTF-8 usage, and complete update
arithmetic before `OWNER_OPEN`. Unsupported feature families remain
unadvertised and their content remains ordinary CELL/residual output.

The unified `RTAPTSCB` bridge admits one immutable, caller-bounded neutral
output producer. `RTHP-STEP` reconciles an already admitted result, captures
the newest complete draw-keyed aggregate, preflights it, opens or retires the
aggregate owner, and schedules hidden START, reveal, or active DELTA work.
`RTHP-PREPARE` correlates and freezes the contribution for the exact
authoritative CELL offer. Once the producer is bound, the bridge invokes it on
each non-`NONE` CELL offer; a persistent `NONE` request is first promoted to a
forced authoritative CELL offer. `STEP` is what schedules that request, and
prepare's draw/generation checks prevent an unrelated flush from manufacturing
retained state.

On the unavailable-to-available discovery edge, the screen adapter forces the
exact current surface through the unified publisher once. Initial
materialization is a hidden complete build followed by reveal. After exact
physical acknowledgement, the producer publishes its immutable target bank as
the sole comparison and input baseline. Compatible later draws emit compact
changed control/glyph replacements; retained-identical draws emit one
idempotent replacement fence. A stale or structurally uncertain target is
cancelled and recaptured through the complete replacement path.

The bridge carries canonical `more-work` and `output-needed` observations,
schedules no recursive service loop, and latches the first fatal neutral
producer or engine result across ordinary scheduling. Reconstruction or final
retirement clears that latch. Synchronized teardown may settle already-admitted
work but cannot use settlement to admit new work. None of these callbacks
executes applet code or stores application state.

Retained discovery is not a hosted-UCTX launch gate. Desk composition,
autostart, local RUHA attachment, ordinary application initialization, and the
first complete UIDL/CELL draw may precede discovery. A final `CELL-ONLY`
answer preserves those lifecycles and opens no retained owner; applets see no
different service table.

The host lifecycle order is:

1. allocate/register the activation, UCTX, and region;
2. load UIDL and perform initial layout;
3. build the immutable exact host-binding descriptor, attach internally, and
   store the returned token only in host-private slot state;
4. run ordinary application initialization and state/widget binding;
5. paint CELL and project retained semantics from the same active UCTX;
6. publish through the shared frame transaction;
7. on geometry change, run UIDL relayout then retained relayout;
8. before `APP.SHUTDOWN`, call `UTUI-QUIESCE`, then the application's declared
   `APP.QUIESCE-XT`, and record retryable retirement, refusing shutdown if
   either callback-detachment barrier is not proven;
9. after all hosted UCTXs are source-free, close the optional terminal owner
   and prove ANSI safety;
10. run application shutdown, then `UTUI-DETACH` while the exact host tuple is
    still live; and
11. free UCTX, activation, region, and host slot.

The top-level shell performs step 8 as a two-part barrier: it first calls
`UTUI-QUIESCE` for its own UIDL document, if present, then invokes the neutral
`APP.QUIESCE-XT ( instance -- ior )` descriptor callback. Desk implements that
callback only by calling `AHOST-QUIESCE-ALL`, which applies the same ordering
to every child. A refusal or throw is a hard pre-terminal close gate. The shell
preserves its descriptor, instance, UIDL, active UCTX,
root region, terminal owner, posted work, and screen state in quarantine and
runs no later destructor. The same quarantine rule applies if terminal close,
application shutdown, or `UTUI-DETACH` fails. A quarantined top-level
lifecycle is not repaired by the retained backend's APT soft reset, an
`ASHELL-RUN` retry, or terminal-owner release, and the shell exposes no
in-process clear API. It requires an externally confirmed attachment hard
reset/drain followed by fresh module or image initialization. The shell never
repeats an arbitrary shutdown callback after claiming it.

The host must save a mutated active UCTX before switching away. Retained
projection cannot depend on unsaved global UIDL pools belonging to some other
active child. It either runs while the exact UCTX is active or reads a validated
saved snapshot through UCTX-owned accessors.

## 10. Reset, replay, and loss

The backend privately tracks session identity and the frozen wire field
`presentation_epoch`; that field name does not introduce a Presentation object
or layer. A successful soft reset invalidates terminal materialization and
private wire identities, not live UCTX attachments.

On an accepted reset boundary, the backend:

1. abandons old-epoch transmission and chunk progress;
2. marks every live region, resource, definition, layout property, and dynamic
   property as not materialized;
3. clears only tombstones whose old retained terminal state is now proven absent;
4. obtains or retains a complete current aggregate snapshot of every visible
   live UCTX; and
5. schedules hidden reconstruction and atomic reveal through a new generation
   of the one aggregate screen owner.

Replay order for the aggregate candidate is region, immutable resources,
series definitions, static groups/objects, layout, current
scalars/status/visibility, current complete series history, then reveal.
Dependencies precede references. A reset during resource or series transfer
restarts that transfer from zero in the new epoch.

Copied static and latest dynamic recipes may be used when their UCTX and source
revisions are still exact. Otherwise the generic projector regenerates them
from the authoritative live UCTX. No retained terminal state or raw frame archive is
authoritative. Hidden UCTXs defer replay until restore; detached UCTXs are
never replayed.

CELL snapshot reconstruction and retained reconstruction are separate dirty
obligations sharing one session epoch. Clearing the CELL snapshot latch cannot
clear retained replay. A structural loss after binary `OPEN` freezes ordinary
publication and follows APT quarantine; it never selects raw ANSI on the same
uncertain attachment.

## 11. Phase boundary and completion

UIDL/UCTX integration is Phase 3, not deferred work. Phase 3 does not ship an
application-facing rich-terminal broker as a bridge and does not require any
applet to maintain terminal-specific output state.

The first complete vertical is the canonical Desk with Pad and Daybook both
launched and live. It uses the same applet descriptors, ordinary UIDL
documents, mounted widgets, application state, Desk tiling/focus/input loop,
and normal TUI draw lifecycle in baseline and rich compositions. Without
applet APT imports, terminal-mode branches, renderer reservations, or direct
scene calls, it must demonstrate:

* complete CELL fallback;
* automatic UCTX attach and exact owner admission;
* one renderer-neutral rich projection derived from the ordinary TUI draw
  lifecycle, covering Desk chrome, UIDL renderers, mounted widgets, and applet
  painting reached through the normal draw boundary;
* dynamic bound-state updates without retransmitting unchanged definitions;
* stable element/object identities across relayout and minimize/restore;
* atomic CELL plus retained publication where both change;
* physical display of every nonempty plane in the selected immutable composite
  before its revision becomes input-eligible;
* reset reconstruction from live UCTX semantics;
* allocation-free detach and exact owner retirement before UCTX free;
* a visible Pad editor whose real edit and caret/state change are supplied by
  the rich path; and
* a visible Daybook month/agenda whose real navigation or selection change is
  supplied by the rich path, followed by the ordinary Daybook-to-Pad shared
  resource route.

Focused generic semantic/draw fixtures may qualify bounded implementation
slices while the backend is being built, but no fixture is the vertical.
Closure uses unchanged production applet sources rather than a handwritten
projection. Pad and Daybook are acceptance applications, not protocol object
types: no particular applet is built into the architecture or protocol.

Image/resource lifecycle remains part of Phase 3 closure when the composition
advertises that semantic family. A stock image can qualify codec mechanics but
cannot replace the generic UIDL media lifecycle, fallback, reset, and detach
journey.

### 11.1 Desk, Pad, and Daybook acceptance checkpoint

The blocking cross-repository path is the real product composition:

```text
Desk + ordinary UIDL renderers + mounted-widget/app draw state
  -> renderer-neutral candidate and stable identities
  -> RTE/RTAPT materializer
  -> unified CELL/retained publisher
  -> MegaPad PT wire and retained model
  -> immutable composite
  -> production compositor/view sink pixels
```

The current product path is the aggregate hybrid producer: ordinary UIDL menu
controls plus unclaimed residual glyph spans, admitted under one screen owner
and published through the unified CELL/retained transaction. The per-cell
screen and LABEL-only experiments are uncomposed residue and provide no current
acceptance authority.

The recorded `d24540e`/`c7045d6` pygame journey reached the complete Desk,
semantic Pad File menu, Pad edit, Daybook task, date-navigation, and
Daybook-to-Pad shared-source milestones through that product path. The task's
unique marker was required inside Daybook tile 2, absent from that tile after
normal `Right` navigation, and present with the Daybook heading inside Pad
tile 0 after Daybook's ordinary `Ctrl+O` action. This qualifies those exact
committed heads, including the eleven Akashic optimization commits through
`e754ac1`, for the selected checkpoint.

Acceptance requires the complete visible Desk frame, both applets live through
their normal descriptors, at least one real Pad edit and one real Daybook
navigation or selection, and the normal shared-resource handoff from Daybook to
Pad. Every substantive Desk/editor/calendar plane selected for rich output must
survive owner admission, publication, the immutable offer boundary, and
physical composition. The displayed revision and revision-bound input advance
only after every nonempty selected plane has crossed the selected sink's exact
completion boundary and been acknowledged.

CELL remains complete and authoritative fallback. It covers terminal
unavailability or a refused aggregate attempt, but a frame whose substantive
Desk, editor, or calendar pixels came only from CELL does not qualify the rich
path. A byte transcript, active retained model, promoted composite, one
control, or
applet-specific scene likewise does not complete the checkpoint.

The renderer-neutral boundary may expose semantic text, layout, state, and
generic draw operations. Physical font choice, pixel geometry, clipping,
alpha, rasterization, buffering, and composition remain MegaPad work. A true
cross-renderer content maximum may be generic UIDL behavior; a retained text
reservation is not and must be derived below UIDL from current content and
caller-provided bounds.

This checkpoint does not weaken the capability contract. The checked-in
production policy advertises exactly `CORE | CONTROLS`, and the terminal model
and renderer must implement that complete advertised menu-control family.
`VECTOR`, `IMAGE`, `INSTRUMENT`, `SERIES`, and `CADENCE` remain unadvertised
until their complete families exist end to end. A focused control fixture is
lower-stack development evidence, not a substitute for the Desk/Pad/Daybook
journey.

### 11.2 Qualification gate around vertical closure

Before the selected vertical closed, each bounded implementation slice was
qualified only with seconds-scale structural tests, byte-oracle tests, focused
state-machine units, and deterministic off-screen compositor units appropriate
to that slice. No single-control or applet-specific selector defined the
vertical; the explicitly authorized canonical Pygame journey at
`d24540e`/`c7045d6` supplied the missing end-to-end evidence.

That pass lifts only the selected Desk/Pad/Daybook checkpoint. It does not
silently qualify physical UART delivery, a hardware panel, reset/resize,
persistence, sustained cadence, unrelated semantic families, or a renderer
matrix. Those remain separate, sequential gates. New performance and semantic
slices still begin with focused seconds-scale evidence and receive coherent
progress commits before any resource-heavy rerun justified by that slice.

## 12. Current conformance cases

The deduplicated lightweight contract suite must prove:

1. baseline Desktop constructs no retained backend, while `desktop-apt1` owns
   exactly one internal PT session, one aggregate screen owner, and no
   application-visible terminal service;
2. negative discovery preserves complete CELL/ANSI behavior and opens no wire
   owner, while the unavailable-to-available edge forces the exact current
   surface through the unified publisher once;
3. multiple live UCTXs receive distinct generation-checked local attachment
   tokens and enter one draw-keyed aggregate directory without receiving
   distinct wire scenes;
4. unregistered, unlinked, reused, detached, foreign-host, mismatched slot/UCTX,
   or stale-token authority is rejected before aggregate or wire mutation;
5. every configuration multiplication, addition, alignment, span, and overlap
   failure occurs before caller storage changes, while exact negotiated-limit
   refusal opens no owner;
6. canonical menu snapshots become parent-first neutral controls, accepted
   paint claims are exclusive, and every remaining visible cell belongs to one
   maximal residual glyph span with neither a coverage gap nor duplicate rich
   representation;
7. the checked-in product advertises exactly `CORE | CONTROLS`, and unsupported
   families contribute no misleading object or blank reserved area;
8. initial/reset/uncertain candidates remain hidden until complete reveal and
   exact sink acknowledgement; control input before that acknowledgement or
   against another revision is rejected;
9. compatible later draws compare only with the physically acknowledged target,
   preserve stable control/glyph identity, and emit only the compact changed
   `RET_DELTA` plan; uncertain provenance or topology takes complete
   replacement;
10. a retained-identical completed draw emits exactly one idempotent replacement
    fence rather than an empty delta or complete redefinition;
11. screen writes union conservative TOUCHED rows, DELTA admission derives a
    distinct exact DAMAGE plan, refusal retains both maps and cached totals, and
    accepted front advancement alone copies DAMAGE rows and retires TOUCHED;
12. unchanged UIDL document slices and acknowledged residual rows are reused
    only under their exact draw, generation, attachment, screen-front, claim,
    and immutable-plan correlations; malformed correlation falls back to
    ordinary recapture;
13. CELL and retained state in a mixed update advance atomically or neither
    does, and downstream backpressure causes no spin, loss, reordering, hidden
    allocation, or input-authority drift;
14. phase markers preserve the Forth stack, remain private to the generic rich
    pipeline, return to `OTHER` before every exit and wait, and the opt-in host
    observer preserves raw bounded intervals while refusing stale generations,
    malformed events, or falsely exact attribution;
15. reset or resize invalidates old targets, publishes complete CELL fallback,
    reconstructs derived output from current UCTX state, and acknowledges the
    new complete composite before input resumes;
16. quiesce makes every local attachment noncallable before application
    shutdown, final detach scrubs all host pointers before state free, and final
    product teardown retires the one aggregate owner or preserves its exact
    retry authority; and
17. no production applet imports APT/rich-terminal modules, discovers a retained
    service, stores a terminal scope, or issues a scene operation.

The recorded pygame journey at Akashic `d24540e` with MegaPad `c7045d6`
provides current cross-layer evidence, including the optimization tranche
through `e754ac1`, for the Desk, semantic Pad File, Pad edit, Daybook task and
navigation, and ordinary Daybook-to-Pad shared-resource milestones. Reset,
sustained cadence, physical UART delivery, and hardware-panel completion remain
sequential qualification work. They may not justify larger hidden capacities,
weakened teardown, or an application-specific rich-terminal path.
