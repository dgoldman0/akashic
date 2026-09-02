# Rich Desktop full-vertical acceptance — 2026-09-02

Status: successful qualifying evidence for the current rich Desktop vertical
at the local physical presentation boundary.  One cold-source run carried the
ordinary Desk, Pad, Daybook, launcher, and Sound Lab path through the normal
descriptors, UCTX/UIDL draw lifecycle, unified CELL/retained publication,
MegaPad retained model, pygame compositor, `pygame.display.flip()`, an exact
post-flip acknowledgement for each offer, and input subsequently authorized
against that acknowledged offer.  This is the first ledger in this series that
extends the earlier collection-only journey through the ordinary launcher to
Sound Lab's complete current `READOUT`/`METER`/`STATUS` family.

This result is a full vertical for that selected journey and those currently
implemented families.  It is not a claim that every Desk applet or every
planned semantic family is complete, and it is not physical-UART or panel
qualification.

## Exact revisions, invocation, and artifacts

The run used the isolated rich-terminal worktrees at these committed heads:

- Akashic `4b6a4753a4785864d448ae9debb33410faa47dd7`
  (`Match rich acceptance state across retained rebuilds`);
- MegaPad `29bdfd6b6ba6d321425b80e01a652fe28ecb298a`
  (`Use the available Forth predicate for retained clips`).

The artifact and socket names identify those two revisions.  The effective
acceptance settings serialized in the trace were 280 columns by 84 rows, a
900-second overall timeout, 0.75-second scripted action delay, ten-second
post-completion hold, and a requested 4,096-record phase observer.  The run
used the `desktop-apt1` cold-source profile, the timing-correct single-lane
native scheduler, the profile's 320 MiB external-memory allocation, an
18-pixel fitted viewer font, and the following invocation shape:

```text
MEGAPAD_ROOT=<megapad-rich-terminal-vertical> \
python local_testing/akashic_tui.py accept \
  --profile desktop-apt1 \
  --output \
    local_testing/out/desktop-apt1-physical-acceptance-4b6a475-29bdfd6.img \
  --socket /tmp/akashic-tui-acceptance-4b6a475-29bdfd6.sock \
  --artifact-root \
    local_testing/out/desktop-apt1-physical-acceptance-4b6a475-29bdfd6 \
  --phase-profile
```

The generated image is exactly 33,554,432 bytes, with SHA-256
`527000b694e94a0a0fdbaf37914771af5cfecacb990405939b0ad84b3148ed4d`.
The build-time image report recorded 55,736 free MP64FS sectors.  A separate
inspection after the guest run measured 55,725 free sectors; that post-run
value includes runtime filesystem state and must not be substituted for the
build-time capacity measurement.

The ignored artifact directory contains 35 files: `manifest.json`,
`performance-trace.json`, and a complete-composite PNG, retained-only PNG, and
retained-text projection for each of eleven milestones.  Every PNG is 3,080 by
1,764 pixels.  Every milestone reports the same 280x84 logical extent,
generation 1, session `17314815092062621386`, attachment epoch 1, presentation
epoch 0, geometry generation 0, and no clipped retained region.

The two durable raw-file hashes are:

- `manifest.json` (54,130 bytes), SHA-256
  `2f86675e50d397b1f782d5d0b4a174744d28fb974113478b4da3afa2ed35230e`;
- `performance-trace.json` (266,189 bytes), SHA-256
  `9848c73bd76ae0d1c7e994fa53907bdfa0c0123c321cde5f3f56cd007f37ef82`.

All 35 expected files exist and both JSON documents parse.  Each of the eleven
retained-text files independently reproduces its manifest hash.  The
manifest's `pixel_sha256` and `retained_only_sha256` values hash the exact RGBA
surface bytes before PNG encoding; `retained_text_sha256` hashes the UTF-8
projection bytes.

`local_testing/out/` is intentionally ignored.  This checked-in ledger is the
durable record; the hashes bind it to the raw local evidence while that output
is retained.

## Complete offer, stage, and input ledger

The trace contains 19 `offer_observed`, 19 `projection_complete`, and 19
`offer_acknowledged` events.  Every offer ID from 1 through 19 occurs exactly
once in each set.  Its 89 event sequence numbers are contiguous from 0 through
88.  Each offer crossed the same ordering boundary: complete composition,
successful `pygame.display.flip()`, then acknowledgement carrying that exact
offer ID and scope.  All fourteen input RPCs returned `progress`; each input
was sent afterward against its exact acknowledged authorizing offer, scope,
and generation.  The input does not itself cross an acknowledgement boundary.
No trace object carries a non-null error.

The run visited fifteen distinct journey stages: stage 0 and stages 2 through
15.  Stage 1 was correctly bypassed because the initial acknowledged Desk
already showed Pad focused; its semantic File-menu action advanced directly
from stage 0 to stage 2.

In the table below, scope is model/CELL/retained revision.  Steps are the exact
pre-screen guest counter at offer observation.  An action shown on a row was
sent against that same offer only after its post-flip ACK completed.  A
milestone labels the already composed surface for that offer.  The trace may
write its artifact file after the input RPC returns, but it writes the retained
offer/projection and composed surface captured before that input; it does not
recapture a post-input screen under the old offer ID.

| Offer | Stage | Scope | Draws | Guest steps | Milestone or offer-authorized action |
| ---: | ---: | ---: | ---: | ---: | --- |
| 1 | 0 | 4/4/4 | 789 | 4,950,000,000 | record `desk-complete`; activate semantic Pad/File control 2 |
| 2 | 2 | 5/4/5 | 789 | 5,314,500,000 | retained-only intermediate; wait for visible menu |
| 3 | 2 | 6/6/6 | 802 | 5,363,000,000 | record `pad-file-menu-open`; send `Escape` |
| 4 | 3 | 7/7/7 | 789 | 5,584,500,000 | record `pad-file-menu-closed`; send text `~` |
| 5 | 4 | 8/8/8 | 789 | 5,769,500,000 | record `pad-edited`; send `Alt+3` |
| 6 | 5 | 9/9/9 | 790 | 5,950,500,000 | Daybook focused; send `Ctrl+N` |
| 7 | 6 | 10/10/10 | 792 | 6,126,000,000 | task prompt visible; send text `^` |
| 8 | 7 | 11/11/11 | 792 | 6,297,500,000 | entered task visible; send `Enter` |
| 9 | 8 | 12/12/12 | 792 | 6,530,000,000 | record `daybook-task-added`; send `Right` |
| 10 | 9 | 13/13/13 | 778 | 6,724,000,000 | record `daybook-date-advanced`; send `Ctrl+O` |
| 11 | 10 | 14/14/14 | 777 | 6,928,000,000 | record `daybook-source-opened-in-pad`; activate acknowledged Pad tab 1073 |
| 12 | 11 | 15/15/15 | 777 | 7,130,500,000 | record `pad-tab-activated`; send `Alt+H` |
| 13 | 12 | 16/15/16 | 777 | 7,456,000,000 | retained-only launcher transition; wait for visible selection |
| 14 | 12 | 17/17/17 | 813 | 7,530,000,000 | record `desk-launcher-open`; send `End` |
| 15 | 13 | 18/17/18 | 813 | 7,831,500,000 | retained-only selection transition; wait for Streams |
| 16 | 13 | 19/19/19 | 815 | 7,863,500,000 | Streams visibly selected; send `Up` |
| 17 | 14 | 20/20/20 | 813 | 8,026,000,000 | record `soundlab-launch-source`; send `Enter` |
| 18 | 15 | 21/20/21 | 813 | 8,702,500,000 | retained-only launch transition; wait for Sound Lab |
| 19 | 15 | 22/22/22 | 1,016 | 8,962,500,000 | record `soundlab-instruments-live`; journey complete |

Offers 2, 13, 15, and 18 are important evidence rather than disposable
duplicates: model and retained revisions advance while CELL remains at the
prior revision.  The client still composes and acknowledges each exact mixed
scope before accepting a later input source.

The two semantic pointer actions retain their exact authorizing targets in the
manifest.  Offer 1 targets Pad/File as owner 1, generation 1, control 2, pixel
rectangle `[3,0]-[61,21]`.  Offer 11 targets the original `Untitled*` tab as
owner 1, generation 1, control 1073, pixel rectangle
`[209,21]-[317,63]`.  The open-menu `Escape` input is likewise bound to the
offer-3 popup forest: title control 931 and ordinary File items 938, 939, 941,
942, 943, 945, 946, and 948.

## Eleven physical milestone records

All hashes below are complete 64-digit SHA-256 values.  `Nonblack` counts
non-black pixels produced by the retained compositor alone; `Gap` counts
renderer-owned logical gap cells.

| Milestone | Offer | Draws | Nonblack | Gap | Complete RGBA SHA-256 | Retained-text SHA-256 | Retained-only RGBA SHA-256 |
| --- | ---: | ---: | ---: | ---: | --- | --- | --- |
| `desk-complete` | 1 | 789 | 5,366,482 | 0 | `be6b1699c97a553feec65221739dc38c84e577fe64db032cdf53800a566d9a4b` | `077636d5a5ba16c5dac9e293ce7b32f983275235c12c1514e6f49ae518a9f3b7` | `71c4f361a27cfad539b4dfa2ab6b29ed91510c033f920da6c2050621737435ba` |
| `pad-file-menu-open` | 3 | 802 | 5,365,915 | 169 | `a3fa4709a8601cf011f40b5b6220eb79808445988bd252223aeed3a5945c0264` | `8593eeac68b236cce366858975573a1feb7a3394b1221574de07fcd31f233ac8` | `63715f0a9a871fbc15c0d09ef3bc17a832254d17d4e4c021a043ca02adedc1f0` |
| `pad-file-menu-closed` | 4 | 789 | 5,366,482 | 0 | `be6b1699c97a553feec65221739dc38c84e577fe64db032cdf53800a566d9a4b` | `077636d5a5ba16c5dac9e293ce7b32f983275235c12c1514e6f49ae518a9f3b7` | `71c4f361a27cfad539b4dfa2ab6b29ed91510c033f920da6c2050621737435ba` |
| `pad-edited` | 5 | 789 | 5,366,482 | 0 | `f7b6523757cd1dd506f286c3b982d4a08da25c6da8884025635c09fb931decba` | `7ea738d192590894d61dd8c5f7fbb4a8e897cc7ab75fc5b5703d2b5a8cd34492` | `e9d7011657a6a6c392e9b59b73ac6de6df9995b4dc4edfe726af178d589800d5` |
| `daybook-task-added` | 9 | 792 | 5,366,510 | 0 | `d3cf65fe274ee250bf4c8db69c93f13c2a64aa7c0b423d7acf7c808e4f64472a` | `0a4cf65ec81993da241db3d6754bebc513a986877d929e9d3b6555bc7af00547` | `b239dc63df1d95b313c5c296d9d716588f180d0be22e4b70e4882669dd424c06` |
| `daybook-date-advanced` | 10 | 778 | 5,366,510 | 0 | `04ea7ff4e9543563c2b62a808ae17c1f73456776ab23a633b43a1cf7330fefe7` | `2af8e8271dd6687b4682a8babb53ce2d326cefb310abb5501dd9393dca7ca701` | `84dd5acbaa40994fefbb603f773a71824dfac609a39ef75ab2e347f30e9919a3` |
| `daybook-source-opened-in-pad` | 11 | 777 | 5,366,482 | 0 | `e9d9f30944ea8bf5f0d85467250cc0ee62d1a1cb55805e9ce96768280fda3c22` | `a4f16937fd821063108cb839968c78ff29127fb1c2a6638dafc8403981392657` | `101610a3e4f94b662df1d7c16011bd61cbea1a85a6b5af1b57cb4a420cd1e0d1` |
| `pad-tab-activated` | 12 | 777 | 5,366,482 | 0 | `28e728f90278ea592abe44c2da654faa9a8b06bffa1e5569869e3e49e77bb3b5` | `d0c938a094a0b805cc9eda5d4d9a4980436e68baa06d0e595d96433a47a9458a` | `e9b4bf47331b34de2adeb09b94fd770e433886c69ce03b50143b409ab4ae2bb7` |
| `desk-launcher-open` | 14 | 813 | 5,381,414 | 0 | `2c57fd1dd6d44f7902e24e4ef2baa6df8a66a3d5164cc79227a47660e4238ffa` | `7a519aa447e92858ea178c6e513e8d112a27344792711090600351b8cefb90b4` | `cbab4410a1c91d59e794d706aa660490a606147248d6561ba42667136cee49b5` |
| `soundlab-launch-source` | 17 | 813 | 5,381,451 | 0 | `a80838812dc7a49ccecfc03d4dabbe59dacca8ffc66cc3fed0792e807833893b` | `eb89e55c4e49d39f85d18fd2726c7003d444fe715cdc553a21a805d8e2029bd1` | `c3d0d0d0ccf3ff1ae613f29a99ab90a27ecbfe14db190cfa177a7533f976ba6e` |
| `soundlab-instruments-live` | 19 | 1,016 | 5,359,810 | 0 | `551658233a1dbd5009fda432c9ef0f4e89efa3491c1ab3ff2ed739ceb67e9884` | `07ff6c8a16231fc39ed2318958cb40b85f65083f02cb77b57c5c3f52a9d98b9e` | `e17f0c71314a97a4f1ca127a44ff1626fc211cc8c3291f78216f27eb3f1534be` |

The equal hashes for `desk-complete` and `pad-file-menu-closed` are expected:
they prove exact visual restoration after the real popup closes.  The popup is
the only milestone with nonzero renderer-owned gap cells; its 169 cells are
part of the renderer-owned popup treatment, not missing final-Desk content.

## Semantic state and ordinary-app evidence

The initial frame contains the complete 3x2 Desk with Pad, File Explorer,
Daybook, Grid, and Agent, five exact ordinary menu forests, two `TEXT_AREA`
roots, one `TEXT_GRID`, and two `TABSET`s.  The journey then proves all of the
following from separately acknowledged physical frames:

1. Pad's authored File menu opens through its retained semantic hit target and
   closes through ordinary `Escape` input.
2. The `~` text edit advances one compatible Pad `TEXT_AREA` state and changes
   the original tab from `Untitled` to `Untitled*`.
3. Daybook accepts `^` as residual task text in its tile.  The calendar itself
   remains the admitted `TEXT_GRID`; the gate does not incorrectly require the
   residual task glyph to be a grid item.
4. `Right` advances the calendar from 2026-09-02 to 2026-09-03, changes the
   grid position/content state, removes `^` from the selected date's tile, and
   displays `No entries for this day`.
5. Daybook's ordinary `Ctrl+O` handoff focuses the already-live Pad, appends
   and selects `/daybook.md`, and exposes `# Daybook` plus the accepted task in
   one compatible editor root.
6. A semantic pointer activation of `Untitled*` changes selection without
   changing the tab signature graph and restores the exact previously accepted
   Pad collection state containing `~`.
7. Desk's ordinary `Alt+H` launcher appears, navigation reaches `Streams` and
   then `Sound Lab`, and `Enter` launches the real Sound Lab descriptor.
8. The final frame preserves `Untitled*`, `/daybook.md`, the selected original
   Pad tab and `~` edit, plus Daybook's navigated 2026-09-03 state.

The final frame restores six exact menu forests, adding Sound Lab's
`File`/`Signal`/`Render`/`Help`, and restores both ordinary tabsets.  It has two
text areas, one text grid, two tabsets, two retained regions, one instrument
region, and 173 instrument cells.  Sound Lab contributes exactly eight
`READOUT`, two `METER`, and three `STATUS` objects, all within its Desk tile.
The retained-only raster visibly carries the `SOUND LAB` surface, waveform,
`sine`, 440 Hz, 75%, 500 ms, analysis readouts, meters, and status treatment;
the substantive instrument result is not a CELL-only picture.

## Launcher occlusion is real and bounded

The launcher is currently ordinary residual Desk output, not a retained
semantic overlay family.  While it is open, it visibly occludes portions of
the tiled applets.  Consequently the offer-14 and offer-17 milestone
projections expose only three unobscured menu signatures and one unobscured
tabset, rather than the normal five menus and two tabsets.  They still expose
the two Pad text-area roots and Daybook grid state needed for later continuity.

The gate deliberately checks the launcher's exact visible header, all ordinary
entry labels, and one selected marker at these stages instead of pretending
occluded controls remain actionable.  After `Enter` removes the overlay, offer
19 must independently restore the complete underlying semantic forest and all
previously exercised Pad/Daybook state before the journey can pass.  This
proves correct occlusion handling for the ordinary launcher journey; it does
not qualify a future generic overlay control/event ABI.

## Retained identity and replacement evidence

Control IDs are renderer-local wire identities, not stable application or
widget IDs.  Their valid input authority is the exact acknowledged offer that
exposes them.  A retained DELTA may preserve IDs for objects it replaces in
place; `RET_REPLACE_START` begins a fresh graph and may reassign all IDs.  The
acceptance comparison therefore uses owner/session lineage, root kind and
bounds, tab signatures/order/selection, and collection content/position state
across replacement.  It never requires cross-START `ControlIdentity`
permanence.

The run supplies concrete evidence for both cases:

- Offer 1 uses Pad tabset 143, tab 144, text areas 145/146, secondary tabset
  147 with tabs 148/149, and Daybook grid 150.  The first complete retained
  rebuild rebases the corresponding visible collection graph to 1072--1079 by
  offer 3.
- Offers 10 to 11 are a sparse DELTA.  Decoded counters add one
  `CONTROL_DEFINE`, four `CONTROL_REPLACE`s, and five `OBJECT_REPLACE`s, with
  no new region or wholesale object definitions.  Pad tabset 1072, original
  tab 1073, and editor 1074 happen to remain fixed; only appended tab 2016 is
  new.  The offer-11 to offer-12 activation is also a DELTA and preserves the
  same signature graph while changing selection and editor state.
- The launcher rebuild exposes fresh Pad collection IDs 2106--2111 at offer
  14.  A later launcher rebuild exposes 3007--3012 at offer 17.  The final
  Sound Lab rebuild exposes Pad/secondary tabsets and collections 3980--3988.
  Define bursts at offers 13, 15, and 18 accompany these fresh retained
  graphs.  The semantic state survives each rebase even though no control ID
  is required to do so.

Thus the stable 1072/1073/1074 values are useful DELTA trace evidence only.
They are not elevated into a cross-presentation application identity.  The
offer-11 pointer event is nevertheless exact: it uses control 1073 only after
offer 11 has been composited and acknowledged, and no later offer inherits
that input authority.

## Timing, wire counters, and profiler qualification

The performance trace is schema `akashic-rich-terminal-performance-v2`, uses
`time.monotonic_ns`, records outcome `pass`, and explicitly marks itself
`normative: false`.

- session connection completed in 0.553808759 seconds;
- initial status at 0.919818010 seconds reported 7,500,000 steps, 15 batches,
  guest revision 0, and no rich frame yet;
- offer 1 was observed at 405.213847688 seconds and acknowledged at
  407.091939153 seconds;
- offer 19 was observed at 785.009204111 seconds and acknowledged at
  785.412193716 seconds;
- the manifest was recorded at 788.018539680 seconds;
- acceptance finished after the ten-second hold at 798.018925974 seconds,
  approximately 13 minutes 18.019 seconds;
- first-to-final offer observation took 379.795356423 seconds, and
  first-to-final acknowledgement took 378.320254563 seconds;
- projection durations ranged from 15,730,290 to 53,495,067 ns;
- physical compose durations ranged from 187,819,851 to 315,686,510 ns;
- complete ACK calls ranged from 208,917,753 to 373,048,098 ns.

Final pre-screen/acceptance counters are 8,962,500,000 guest steps, 17,925
batches, guest revision 58, 5,644 decoded retained-protocol frames, 1,396,948
decoded frame bytes, 392 machine publications, 1,399,104 machine-publication
bytes, and zero decoder-buffered bytes.  The roughly 405-second cold-source
time to the first offer is material diagnostic cost, but the run remained
inside its explicit 900-second watchdog.

The phase observer resolved `_RTPROF-EVENT` at guest address 5,147,797.  The
first-offer status boundary was 4,950,000,000 steps and 9,900 batches; the
observer's authoritative start was 4,953,000,000 steps and 9,906 batches, an
exact attachment lag of 3,000,000 steps and six batches.  Its half-open
measurement window ended at the final offer's pre-screen status of
8,962,500,000 steps, for exactly 4,009,500,000 retired steps.  Shutdown
occurred later at 8,968,000,000 steps and 17,936 batches.

All 8,031 sample attempts succeeded.  The observer saw 552 sequence
transitions, retained 228 transition records, and identified 324 transitions
that coalesced between samples.  It dropped zero records and zero transitions,
reported no observer/profile error or straddling terminal transition, ended in
`OTHER`, and reports `lifecycle_complete: true`.

| Phase | Closed observed visits | Lower bound | Upper bound |
| --- | ---: | ---: | ---: |
| Other or unattributed | — | 1,197.5M | 1,376.5M |
| UIDL aggregate | 28 | 568.5M | 596.5M |
| Snapshot import | 14 | 0 | 14.0M |
| Control plan | 14 | 28.0M | 42.0M |
| Claim plan | 13 | 2.0M | 15.0M |
| Residual plan | 14 | 477.0M | 491.0M |
| Reserve/wrap | 2 | 0 | 2.0M |
| Hybrid preflight | 14 | 196.5M | 210.5M |
| Candidate validation | 1 | 0 | 1.0M |
| Target pack | 18 | 6.5M | 24.5M |
| Delta compare/normalize | 11 | 471.5M | 482.5M |
| RTAPT capture | 18 | 684.5M | 702.5M |
| Commit precheck | 1 | 0 | 1.0M |
| RTAPT audit | 18 | 77.0M | 95.0M |
| Wire encode | 13 | 121.5M | 134.5M |

Phase attribution is correctly marked `attribution_complete: false` because
the 324 coalesced transitions prevent exact assignment inside their sampling
intervals.  This is expected and nonblocking for acceptance.  It limits the
table to diagnostic lower/upper bounds and forbids a normative performance
claim; it does not affect the complete offer lifecycle, physical frame
evidence, semantic checks, ACK ordering, or input authorization.

Two other trace observations are benign.  Offer 1 sampled 368 decoder-buffered
bytes and offer 9 sampled 983, representing partial next wire records at those
status instants; later samples and the final counter are zero.  The open-menu
milestone's 169 renderer-owned gap cells are isolated to the popup, while all
ten other milestones report zero.

## Qualified result and remaining boundaries

This run qualifies the selected local vertical through the real ordinary
Desktop journey: cold system-module load, Akashic generic engine and UIDL/TUI
adapter, unified CELL/rich publisher, normal Desk/app descriptors and mounted
widgets, retained transaction/model/view, generic physical compositor,
presentation flip and ACK, two real collection interactions, Daybook-to-Pad
handoff, tab activation, ordinary launcher navigation, and Sound Lab's
complete current instrument family.  No applet-specific physical scene or
direct terminal service was added to Desk, Pad, Daybook, or Sound Lab.

The following remain outside this evidence:

- the boundary is X11 `pygame.display.flip()`, not an external UART,
  controller, scanout, e-paper waveform/settling sensor, or touch device;
- only one cold-source session, geometry, and generation were exercised;
  reset, resize, reconnect, persistence, sustained cadence, and ghosting or
  partial-refresh policy remain separate qualifications;
- Sound Lab was launched and its complete live initial/rendered instrument
  state was proven, but this journey did not mutate a Sound Lab value after
  launch or qualify long-running instrument updates;
- launcher output is still residual and this pass does not define a generic
  retained overlay/action/field/choice/item semantic family;
- other applets and unexercised retained families, including broader
  resource/image, series/plot, and ecosystem journeys, require their own
  focused vertical evidence;
- the guest phase totals and emulator wall time are non-normative diagnostics,
  not processor, transport, or product-latency promises.

Within those explicit boundaries, the full selected rich-Desktop loop is
closed: nineteen exact offers each acknowledged after its presentation flip,
fourteen actions sent against their exact acknowledged authorizing offers,
fifteen observed stages, eleven independently hashed physical milestones,
preserved exercised Pad/Daybook state across retained rebuilds, and a
substantive retained-only Sound Lab final frame all passed without error.
