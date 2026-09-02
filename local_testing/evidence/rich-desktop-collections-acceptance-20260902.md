# Rich Desktop semantic-collections acceptance — 2026-09-02

Status: historical qualifying evidence ledger for the collection-only local
reference-sink slice at Akashic `dd27f34`.  It qualified the canonical
Desk/Pad/Daybook journey for menus, residual glyphs, `TEXT_AREA`, `TEXT_GRID`,
`TABSET`, and `TAB` at the host presentation-API boundary.  It predates and
must not be read as the later full-rich-desktop/Sound Lab vertical.  It does
not qualify physical UART delivery, scanout, e-paper refresh, touch,
reset/resize, persistence, sustained cadence, or unadvertised semantic
families.

## Revisions and invocation

The successful run used exact committed heads from the isolated rich-terminal
worktrees:

- Akashic `dd27f34fd30627aa63fc384d42a785b55a2c71d1`;
- MegaPad `29bdfd6b6ba6d321425b80e01a652fe28ecb298a`.

It used the timing-correct single-lane native scheduler, a checked cold-source
`desktop-apt1` image, 320 MiB of emulated external memory, the canonical 280x84
X11 pygame viewer, an 18-pixel font, a 700-second finite watchdog, a 0.75-second
scripted action delay, and the default ten-second post-completion hold:

```text
MEGAPAD_ROOT=<megapad-rich-terminal-vertical> \
python local_testing/akashic_tui.py accept \
  --profile desktop-apt1 \
  --output \
    local_testing/out/desktop-apt1-physical-acceptance-dd27f34-29bdfd6.img \
  --socket /tmp/akashic-tui-acceptance-dd27f34-29bdfd6.sock \
  --artifact-root \
    local_testing/out/desktop-apt1-physical-acceptance-dd27f34-29bdfd6 \
  --phase-profile
```

The build linked 212 production modules in 33 source chunks and created a
32 MiB MP64FS image with 55,748 free sectors.  The command exited zero with
`Physical desktop acceptance: PASS` after 606.724 seconds.  The ignored raw
output contained:

- `manifest.json`, SHA-256
  `f25463f931a5a90569f36a64ff7203060aa86e0d0756af0dfce1c5635fce1667`;
- `performance-trace.json`, SHA-256
  `b14afd0f66d20bec64fcda700a6fe1f6bd36c198931f37f9655543ba3310de99`;
- the retained text, retained-only raster, and complete-composite raster for
  each of eight recorded milestones.

`local_testing/out/` is intentionally ignored.  This ledger is the durable
summary; the hashes bind it to the raw local evidence while that output is
retained.  Before the physical run, the focused packaging and acceptance suite
passed all 177 tests in 22.22 seconds.  Later harness work tightened semantic
continuity at replacement boundaries; that later correction does not alter
the measurements or collection-only scope recorded here.

## Accepted ordinary journey

All twelve immutable rich offers were completely composed, passed through
`pygame.display.flip()`, and acknowledged with their exact offer ID and scope.
Every one of the ten input actions was authorized by its exact acknowledged
source frame.  The journey used the normal app descriptors, UCTX lifecycle,
Desk tiling/focus/input loop, ordinary widget draws, unified CELL/retained
publisher, MegaPad retained model, and shared physical viewer:

1. display the complete 3x2 Desk with Pad, File Explorer, Daybook, Grid, and
   Agent through the ordinary startup composition;
2. activate Pad's authored semantic File menu from its acknowledged retained
   hit target, then observe its real open and closed frames;
3. type the unique `~` marker into Pad and observe one compatible admitted
   `TEXT_AREA` state advance while the canonical tab becomes `Untitled*`;
4. focus Daybook, create the unique `^` task, and observe it as ordinary
   residual content inside the Daybook tile while the admitted `TEXT_GRID`
   continues to carry the calendar's collection state;
5. navigate Daybook with ordinary `Right` and require the residual task to
   leave the selected date's tile content while the calendar `TEXT_GRID`
   advances its position/content state;
6. send Daybook's ordinary `Ctrl+O`, which posts its shared `/daybook.md`
   resource through Desk and focuses the already-live Pad;
7. observe `/daybook.md` appended and selected in the acknowledged canonical
   Pad tab graph, with the Daybook heading and task in one compatible Pad
   editor root; and
8. activate the original `Untitled*` tab through its exact retained hit target
   and observe its exact edited collection state restored.

The principal milestone hashes were:

| Milestone | Offer | Retained-text SHA-256 |
| --- | ---: | --- |
| Desk complete | 1 | `c2c6690b8a6e248180edfd67bc92f045ef4833394f8b4011e5d1688fb351e5c8` |
| Pad edited | 5 | `e1d8cd77d5b296055634a83eb287bf94804660de393dc73d8e2d5f756628917c` |
| Daybook task added | 9 | `99478169a8694e1771c0c0b285aed83d6e77e25724814afa4e24d9e5782c6019` |
| Daybook date advanced | 10 | `b22102bc919da0ba9316d49be9f0b0926323460d90c27cb1675571f099c73037` |
| Daybook source opened in Pad | 11 | `5dda0ea505cd0a6f0faacc5497763f48f13cbdbdd11b5e67ea33a396c2dfc7f2` |
| Original Pad tab activated | 12 | `271318f8bf5909be5c8b573b9d002309903f4f1c415cc2c0c3008710d41b7c4e` |

The final offer retained scope revisions 15/15/15 for CELL/model/retained, 777
draws, complete-composite pixel SHA-256
`fd57fb9883f98e3b8bc244d9a48bffea8c96825730e7ebd73cdbe856390e3e60`,
and retained-only pixel SHA-256
`7be481fe5164ab77e49be7eb3d30d7b2adedc7a4ad4228c394da990889dd6d7a`.

## Identity and delta evidence

The first post-discovery target used Pad TABSET/root control 143, tab 144, and
editor 145.  A second complete publication was required when glyph topology
grew; complete replacement legitimately rebased renderer-local IDs.  From the
next visible frame onward Pad used root 1072, original tab 1073, and editor
1074.

The observed Daybook-to-Pad handoff itself was sparse.  Offer 10 to offer 11
added one `CONTROL_DEFINE`, four `CONTROL_REPLACE`s, and five
`OBJECT_REPLACE`s, with no new region or wholesale object graph.  In that
particular DELTA, root 1072, original tab 1073, and editor 1074 stayed fixed;
only the appended `/daybook.md` tab received new control 2016.  The following
DELTA to offer 12 retained that wire graph, selected tab 1073, and restored the
`~` edit through editor 1074.

Those numbers are observations about this producer execution, not durable
application or widget identities.  `ControlIdentity` is renderer-local and is
valid as an input target only under the exact acknowledged display authority
that exposed it.  A `PRESENT_BEGIN` with `RET_REPLACE_START` begins a fresh
retained graph and may freely rebase every control ID.  Therefore the
acceptance contract does not require cross-START ID permanence.  Cross-offer
continuity is established from renderer-neutral semantics—owner lineage,
root kind and bounds, tab label/shortcut/order and selection, and collection
content/position state.  Exact control IDs remain useful only as trace evidence
inside a confirmed DELTA and as the target exposed by one exact acknowledged
authorizing offer.  Input is sent against that offer; the input itself is not
an acknowledgement event.

## Work and open boundaries

The first offer was observed at 4.9325 billion retired guest instructions and
714,579 decoded wire bytes.  The final offer was observed at 7.0690 billion
instructions and 906,128 bytes.  The post-first journey therefore used 2.1365
billion instructions and 191,549 bytes; the glyph-growth replacement at offer
2 accounts for 137,506 of those bytes.  These are diagnostic emulator and wire
counters, not a product-latency promise.

The optional phase observer covered 2.1335 billion post-attachment
instructions with a complete marker lifecycle, no dropped records or
transitions, and no observer error.  Its attribution is bounded rather than
exact because 216 transitions coalesced between samples.  The largest named
interval totals were delta comparison/normalization at 440--449 million
instructions, UIDL aggregation at 354--374 million, residual planning at
308.5--318.5 million, and RTAPT capture at 209.5--220.5 million.  This profile
is non-normative performance evidence and does not weaken the acceptance.

The physical boundary remains X11 `pygame.display.flip()`.  No byte crossed an
external UART and no controller confirmed panel scanout, e-paper waveform
completion, settling, or touch.  The pass closes the selected local
semantic-collections vertical only.  Generic actions, fields, item views,
overlays/status, data graphics, resources/images, cadence policy, the broader
ecosystem journey, physical transport, and hardware-panel completion remain
separate later work.
