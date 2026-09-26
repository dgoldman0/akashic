# Viewer composition — September 26, 2026

Every physical Desktop frame redrew all 23,520 CELL cells, then painted the
rich plane over them glyph by glyph, each glyph under its own clip. Two
MegaPad changes halve that work with identical pixels and hit maps. A third
stops the product viewer redrawing a window that has not changed. These are
host-side changes, so they make the simulated Desktop more comfortable
without affecting the device.

## What changed

- MegaPad `18b8f20` adds two composition fast paths:
  - `opaque_cell_coverage` marks each cell whose whole box lies inside the
    opaque background fill of a GLYPH_RUN, using the painter's own clip
    rules. `VirtualTerminal.render` skips those cells unless the glyph
    overhangs the cell. Translucent fills and other draw kinds never count.
    On real Desktop frames, opaque glyph runs repaint 87.5% of the cells.
  - Undecorated glyph runs blit every glyph in one batch, each cropped to
    its own slot exactly as the per-slot path crops it. Underlined and
    struck runs keep the per-slot path.
- MegaPad `adc29af` makes the viewer recompose only when something it draws
  changes (a new offer, the screen revision, hover or press, a visible
  cursor's blink, the window) and flip only when the frame or status line
  changes. A pending offer always draws, because only a flip may
  acknowledge it. Input still uses the hit map staged with each
  acknowledged offer.
- MegaPad `16660cb` documents both.

## Measurements

The paired off-screen benchmark composes MegaPad's two real Desktop
fixtures 16 times each, alternating the fast and reference paths, and checks
pixels and hit maps on every trial. Host load averages were 11 to 13, so the
absolute times are high; the ratios are the measure of record.

| Fixture | Whole frame | CELL pass | Rich layer |
| --- | ---: | ---: | ---: |
| Ready Desktop | 109.1 → 52.5 ms | 54.5 → 16.0 ms | 54.4 → 31.3 ms |
| Typed Desktop | 110.4 → 53.7 ms | 54.6 → 15.7 ms | 54.9 → 31.9 ms |

That is about 52% less per frame. An earlier run of the same comparison
measured 64–78 ms before and 37–39 ms after.

In two physical typing runs, viewer composition had a median of 52–54 ms per
frame. Earlier runs at similar load, with the old compositor, took 107–115 ms.

The idle-viewer test runs the real viewer loop for 0.6 s against an
unchanging session: it composes and flips once, where the old loop did so 19
times.

## Qualification

- The canonical 22-stage physical Desktop journey passes at MegaPad
  `adc29af`: 18 milestones, 21 revision-bound inputs, 27 physical
  acknowledgements and both CELL fallback checks. All 18 milestone
  screenshots, including open menus, popups and Sound Lab instruments, are
  pixel-identical to the previous journey's.
- The typing runs' milestone screenshots match the earlier runs on the same
  Akashic code exactly.
- MegaPad's new replay test composes two real Desktop offers, plus six
  synthetic planes over three random CELL grids each, with the fast paths
  and with both disabled. Every RGBA pixel and the full hit map must match.
  The synthetic planes cover partial rows, translucent fills, REVERSE,
  region clips, offset regions, uneven slots and every glyph attribute.
  Counting translucent fills as coverage fails seven of those cases. The
  viewer and compositor selectors pass 184 tests.

## Evidence

`local_testing/evidence/viewer-composition-20260926.json` holds the
benchmark medians and pixel digests, the journey and typing summaries,
bindings and hashes. Artifacts are in `local_testing/out/lever3-20260926/`,
which is ignored.
