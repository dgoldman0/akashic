# Rich Desktop Daybook-to-Pad acceptance — 2026-08-30

Status: qualifying evidence ledger for the selected local reference-sink
Desk/Pad/Daybook checkpoint. It records a complete ordinary application
journey at the host presentation-API boundary. It does not qualify physical
UART delivery, scanout, e-paper refresh, or touch.

## Revisions and invocation

The successful run used exact committed heads:

- Akashic `d24540e90091ddde3976a18f07783f183853cacf`;
- MegaPad `c7045d673abe458d8ed80661c86d0063a80407f3`.

It used the timing-correct single-lane native scheduler, a cold-source
`desktop-apt1` image, 128 MiB of emulated external memory, the canonical
280x84 X11 pygame viewer, an 18-pixel font, a 600-second timeout, a
0.75-second scripted action delay, and zero post-completion hold:

```text
MEGAPAD_ROOT=<megapad-rich-terminal-vertical> \
python local_testing/akashic_tui.py accept \
  --profile desktop-apt1 \
  --output local_testing/out/desktop-apt1-d24540e.img \
  --artifact-root local_testing/out/desktop-apt1-physical-acceptance-d24540e \
  --hold-seconds 0
```

The command exited zero with `Physical desktop acceptance: PASS` after
201.331 seconds. The ignored raw output contained:

- `manifest.json`, SHA-256
  `6bd335ed3e3a231c7ec6f1ffb322f5665ef74e1c5d903b2ad48daf44244eeb48`;
- `performance-trace.json`, SHA-256
  `2eb359ea73eecf780f197548246366af65985ec6aaab7c94987f74efa5f12785`;
- the retained-text, retained-only raster, and complete-composite raster for
  each recorded milestone.

`local_testing/out/` is intentionally ignored. This ledger is the durable
summary; hashes bind it to the local raw evidence when that output is retained.

## Accepted journey

Every action below was issued only after the exact newer immutable offer had
been fully composed, passed through `pygame.display.flip()`, and received its
offer-ID/scope acknowledgement. The journey used normal descriptors, UCTX
lifecycle, Desk focus/input dispatch, ordinary applet actions, the unified
CELL/retained publisher, and the selected physical viewer:

1. display the complete 3x2 Desk with canonical Pad and Daybook live;
2. focus Pad and activate its authored semantic File menu through the
   revision-bound retained control hit map;
3. observe the real menu open and close states;
4. type the unique `~` edit into Pad and observe it in the acknowledged frame;
5. focus Daybook, open its normal new-task prompt, type `^`, commit it, and
   observe `^` specifically inside Daybook tile 2;
6. send normal `Right`, then require a newer acknowledged Daybook frame in
   which `^` is absent from tile 2, proving date navigation rather than a
   focus-only transition;
7. send Daybook's ordinary `Ctrl+O` action, which posts its exact shared
   resource reference through Desk's capability bus; and
8. require a newer acknowledged Pad-focused frame containing both
   `# Daybook` and the same unique `^` inside Pad tile 0.

The three shared-resource retained-text hashes were:

| Milestone | Offer | Retained-text SHA-256 |
| --- | ---: | --- |
| Daybook task added | 9 | `2b9176584502fd482c80a24811a8005d6d96404e324f7c5c1de1708a1966416e` |
| Daybook date advanced | 10 | `b209d3326b4d012814f2524c7d88d79acadf1d36016b2d0eb6b104525552d3e6` |
| Daybook source opened in Pad | 12 | `850711f8cfb18c90eafedd14711a5e55e6a914eb546ada236d2f96af3710ef37` |

The final offer had scope revisions 15/15/15 for CELL/model/retained,
800 retained draws, complete-composite pixel SHA-256
`f74d99078b49429c5f4fb3924e71de5597a5027352c398c747b0228bc4b96c10`,
and retained-only pixel SHA-256
`3a339cd52d68db3155e6c47cd3a7a8771e1fe95cb451c8f358dad1ad2925628c`.

## Work and traffic context

The first offer was observed at 4.0865 billion retired guest instructions and
744,222 decoded wire bytes. The complete twelve-offer journey finished at
5.0495 billion instructions and 783,434 bytes. Thus the extended post-first
journey used 963.0 million instructions and 39,212 decoded bytes. These totals
include all work between offers and cannot attribute cost to internal rich
pipeline phases; the next profiling slice adds bounded phase observation for
that purpose.

At 8N1, 115,200 baud, 783,434 bytes have a no-gap serialization floor of
68.01 seconds, of which the post-first 39,212 bytes account for 3.40 seconds.
These are arithmetic projections, not physical-link measurements. The current
viewer receives emulator batches in process, so this run leaves MegaPad's
physical UART baseline and the e-paper controller/settle acknowledgement gate
open.
