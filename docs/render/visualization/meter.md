# akashic-meter — Audio Level Meters & Decorators

Renders VU-style audio level meters and energy bar charts onto
surfaces.  Supports horizontal and vertical orientations, RMS fill
with peak markers, color-graded bars (green → yellow → red),
clipping indicators, tick marks, and stereo paired display.

```forth
REQUIRE render/visualization/meter.f
```

`PROVIDED akashic-meter` — safe to include multiple times.
Automatically requires `surface.f`, `draw.f`, `audio/pcm.f`,
`math/fp16.f`, and `math/fp16-ext.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Color Palette](#color-palette)
- [Level Thresholds](#level-thresholds)
- [Configuration Descriptor](#configuration-descriptor)
- [Flag Bits](#flag-bits)
- [Creating & Freeing Configs](#creating--freeing-configs)
- [Setting Levels](#setting-levels)
- [Drawing](#drawing)
- [Orientation](#orientation)
- [Energy Bar Chart](#energy-bar-chart)
- [Stereo Meters](#stereo-meters)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Surface-targeted** | All rendering writes to an RGBA8888 surface. Meters are positioned at arbitrary $(x, y)$ coordinates on the surface. |
| **FP16 levels** | RMS and peak levels are FP16 values in $[0, 1]$. Values above 1.0 trigger the clip indicator. |
| **Config descriptor** | A 112-byte struct holds geometry, colors, and current levels. |
| **Gradient coloring** | The filled bar is colored green (< 0.5), yellow (0.5–0.85), or red (> 0.85) based on the RMS level. Disable with flag for solid green. |
| **Dual display** | RMS shown as a filled bar; peak shown as a thin marker line — standard VU/PPM meter behavior. |
| **Auto-analysis** | `METER-ANALYZE` scans a PCM buffer and computes RMS + peak automatically. |
| **Prefix convention** | Public: `METER-`. Internal: `_MT-`. |

---

## Color Palette

| Constant | Value | Description |
|---|---|---|
| `METER-BG` | `0x121212FF` | Near-black background |
| `METER-TRACK` | `0x2A2A2AFF` | Dark grey meter track (unfilled area) |
| `METER-GREEN` | `0x4CAF50FF` | Green — low levels |
| `METER-YELLOW` | `0xFFEB3BFF` | Yellow — mid levels |
| `METER-RED` | `0xF44336FF` | Red — high levels |
| `METER-CLIP` | `0xFF1744FF` | Bright red clipping indicator |
| `METER-TEXT` | `0xFFFFFFFF` | White labels |
| `METER-GRID` | `0x666666FF` | Tick mark color |
| `METER-PEAK-MK` | `0x00E676FF` | Green peak marker line |
| `METER-BORDER` | `0x1A1A1AFF` | Border color |

---

## Level Thresholds

The gradient color is selected by comparing the FP16 level against
two thresholds:

| Range | Threshold | Color |
|---|---|---|
| level < 0.5 | `_MT-THRESH-MID` = `0x3800` | `METER-GREEN` |
| 0.5 ≤ level < 0.85 | `_MT-THRESH-HI` = `0x3ACC` | `METER-YELLOW` |
| level ≥ 0.85 | — | `METER-RED` |

When `METER-F-GRADIENT` is cleared, the bar is always `METER-GREEN`.

---

## Configuration Descriptor

112 bytes, 14 cells.

| Offset | Field | Type | Default | Description |
|---|---|---|---|---|
| 0 | `MC.ORIENT` | integer | 0 | Orientation: 0 = horizontal, 1 = vertical |
| 8 | `MC.X` | integer | (arg) | Meter position X on surface |
| 16 | `MC.Y` | integer | (arg) | Meter position Y |
| 24 | `MC.W` | integer | (arg) | Meter width in pixels |
| 32 | `MC.H` | integer | (arg) | Meter height in pixels |
| 40 | `MC.FLAGS` | bitfield | `PEAK\|GRADIENT\|BORDER` | Feature flags |
| 48 | `MC.BG` | RGBA | `METER-BG` | Background color |
| 56 | `MC.TRACK` | RGBA | `METER-TRACK` | Track (unfilled) color |
| 64 | `MC.BORDER` | RGBA | `METER-BORDER` | Border color |
| 72 | `MC.PEAK-MK` | RGBA | `METER-PEAK-MK` | Peak marker color |
| 80 | `MC.SURF` | pointer | — | Target surface pointer |
| 88 | `MC.PCM` | pointer | 0 | PCM buffer (for `METER-ANALYZE`) |
| 96 | `MC.RMS-VAL` | FP16 | 0.0 | Current RMS level |
| 104 | `MC.PEAK-VAL` | FP16 | 0.0 | Current peak level |

---

## Flag Bits

| Constant | Value | Effect |
|---|---|---|
| `METER-F-PEAK` | 1 | Show peak marker line |
| `METER-F-GRADIENT` | 2 | Color gradient (green → yellow → red). When clear, bar is solid green. |
| `METER-F-BORDER` | 4 | Draw 1 px border around the meter |
| `METER-F-TICKS` | 8 | Draw 11 scale tick marks along the edge |
| `METER-F-CLIP` | 16 | Flash red clip indicator when peak ≥ 1.0 |

---

## Creating & Freeing Configs

### METER-CONFIG-CREATE

```forth
METER-CONFIG-CREATE  ( surf x y w h -- cfg )
```

Allocate a 112-byte config and set default colors, flags, and
geometry.  Levels start at zero.  No PCM buffer is attached by
default — assign one to `MC.PCM` if using `METER-ANALYZE`.

```forth
my-surf 10 10 200 20 METER-CONFIG-CREATE CONSTANT mc
```

### METER-CONFIG-FREE

```forth
METER-CONFIG-FREE  ( cfg -- )
```

Free the config descriptor.

```forth
mc METER-CONFIG-FREE
```

---

## Setting Levels

### METER-SET-LEVELS

```forth
METER-SET-LEVELS  ( rms peak cfg -- )
```

Manually set the RMS and peak levels.  Both are FP16 values
typically in $[0, 1]$.

```forth
0x3800 0x3C00 mc METER-SET-LEVELS   \ RMS=0.5, peak=1.0
```

### METER-ANALYZE

```forth
METER-ANALYZE  ( pcm cfg -- )
```

Automatically compute RMS and peak from a PCM buffer and store
them in the config.

- **Peak**: uses `PCM-SCAN-PEAK` and takes `FP16-ABS`.
- **RMS**: iterates all samples, accumulates $\sum s^2$ in FP16,
  divides by $N$, and takes `FP16-SQRT`.

```forth
my-pcm mc METER-ANALYZE
```

> **Note:** FP16 accumulation of $\sum s^2$ may lose precision for
> very long buffers.  For meter display this is acceptable.

---

## Drawing

### METER-DRAW

```forth
METER-DRAW  ( cfg -- )
```

Render a single meter.  Performs, in order:

1. Draw border (if `METER-F-BORDER`): 1 px outline.
2. Fill track (unfilled area) with `MC.TRACK`.
3. Determine fill color from RMS level via the gradient thresholds.
4. Draw the filled bar:
   - **Horizontal**: bar grows left to right proportional to RMS.
   - **Vertical**: bar grows from bottom to top.
5. Draw peak marker line (if `METER-F-PEAK`).
6. Draw tick marks (if `METER-F-TICKS`): 11 evenly-spaced marks.
7. Draw clip indicator (if `METER-F-CLIP` and peak ≥ 1.0): 3 px
   red bar at the high end.

```forth
mc METER-DRAW
```

---

## Orientation

### METER-ORIENT!

```forth
METER-ORIENT!  ( 0|1 cfg -- )
```

Set orientation: 0 = horizontal, 1 = vertical.

```forth
1 mc METER-ORIENT!   \ switch to vertical
```

---

## Energy Bar Chart

### METER-ENERGY-CHART

```forth
METER-ENERGY-CHART  ( rms-array n surf x y w h -- )
```

Draw a bar chart of $N$ energy values.  Each bar is auto-colored
by level using the same gradient thresholds as `METER-DRAW`.

- `rms-array`: address of $N$ consecutive FP16 values (2 bytes each).
- `n`: number of bars (regions).
- `surf x y w h`: target area on the surface.

A dark track is rendered first, then each bar is drawn from the
bottom upward.  Bars are separated by a 2 px gap.

```forth
\ 8-region energy display
energy-data 8 my-surf 10 200 300 40 METER-ENERGY-CHART
```

---

## Stereo Meters

### METER-STEREO-DRAW

```forth
METER-STEREO-DRAW  ( cfg-l cfg-r -- )
```

Draw two meters.  Simply calls `METER-DRAW` on each config in
sequence.  The caller is responsible for positioning the two
configs side by side (or stacked, for vertical orientation).

```forth
mc-left mc-right METER-STEREO-DRAW
```

---

## Internals

| Word | Purpose |
|---|---|
| `_MT-SETUP` | Extract config fields + compute inner area (inside border). |
| `_MT-LEVEL-COLOR` | Map FP16 level to RGBA via gradient thresholds. |
| `_MT-DRAW-BORDER` | 1 px outline rectangle. |
| `_MT-DRAW-TRACK` | Fill inner area with track color. |
| `_MT-DRAW-HBAR` | Horizontal filled bar: width = level × inner width. |
| `_MT-DRAW-VBAR` | Vertical filled bar: height = level × inner height, from bottom. |
| `_MT-DRAW-PEAK-H` | Horizontal peak marker: vertical line at peak position. |
| `_MT-DRAW-PEAK-V` | Vertical peak marker: horizontal line at peak position. |
| `_MT-DRAW-TICKS-H` | 11 horizontal tick marks along bottom edge. |
| `_MT-DRAW-TICKS-V` | 11 vertical tick marks along left edge. |
| `_MT-DRAW-CLIP-H` | 3 px red bar at right edge (horizontal clip indicator). |
| `_MT-DRAW-CLIP-V` | 3 px red bar at top edge (vertical clip indicator). |
| `_MT-EC-*` | Scratch variables for energy chart rendering. |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `METER-CONFIG-CREATE` | `( surf x y w h -- cfg )` | Allocate & init config |
| `METER-CONFIG-FREE` | `( cfg -- )` | Free config |
| `METER-DRAW` | `( cfg -- )` | Render a single meter |
| `METER-SET-LEVELS` | `( rms peak cfg -- )` | Set RMS + peak levels |
| `METER-ANALYZE` | `( pcm cfg -- )` | Auto-compute levels from PCM |
| `METER-ORIENT!` | `( 0\|1 cfg -- )` | Set orientation |
| `METER-ENERGY-CHART` | `( rms-array n surf x y w h -- )` | Energy region bar chart |
| `METER-STEREO-DRAW` | `( cfg-l cfg-r -- )` | Draw paired stereo meters |

---

## Cookbook

### Simple horizontal meter

```forth
REQUIRE render/visualization/meter.f

my-surf 10 10 200 20 METER-CONFIG-CREATE CONSTANT mc
0x3666 0x3900 mc METER-SET-LEVELS   \ RMS ≈ 0.4, peak ≈ 0.6
mc METER-DRAW
mc METER-CONFIG-FREE
```

### Vertical meter with ticks and clip detection

```forth
my-surf 280 10 20 200 METER-CONFIG-CREATE CONSTANT mc

1 mc METER-ORIENT!

\ Enable all features
METER-F-PEAK METER-F-GRADIENT OR
METER-F-BORDER OR METER-F-TICKS OR METER-F-CLIP OR
mc MC.FLAGS + !

\ Hot signal
0x3C00 0x4000 mc METER-SET-LEVELS   \ RMS=1.0, peak=2.0
mc METER-DRAW
mc METER-CONFIG-FREE
```

### Auto-analysis from PCM

```forth
my-surf 10 10 200 20 METER-CONFIG-CREATE CONSTANT mc
my-pcm mc MC.PCM + !     \ attach PCM buffer
my-pcm mc METER-ANALYZE  \ scan for RMS + peak
mc METER-DRAW
mc METER-CONFIG-FREE
```

### Stereo pair

```forth
my-surf 10 10 200 16 METER-CONFIG-CREATE CONSTANT mc-l
my-surf 10 30 200 16 METER-CONFIG-CREATE CONSTANT mc-r

\ Set levels from external analysis
rms-l peak-l mc-l METER-SET-LEVELS
rms-r peak-r mc-r METER-SET-LEVELS

mc-l mc-r METER-STEREO-DRAW

mc-l METER-CONFIG-FREE
mc-r METER-CONFIG-FREE
```

### Energy bar chart (8 frequency regions)

```forth
\ Assume energy-data is an array of 8 FP16 RMS values
energy-data 8 my-surf 10 200 300 40 METER-ENERGY-CHART
```
