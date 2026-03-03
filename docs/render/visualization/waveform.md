# akashic-waveform — PCM Waveform Visualization

Renders PCM audio buffers as time-domain waveform plots onto a
surface.  Supports configurable view windows, signed-sample to
pixel-Y mapping, grid overlays, peak envelope, zero-crossing lines,
stereo display modes, and antialiased min/max column mode for wide
zoom-outs.

```forth
REQUIRE render/visualization/waveform.f
```

`PROVIDED akashic-waveform` — safe to include multiple times.
Automatically requires `surface.f`, `draw.f`, `audio/pcm.f`, and
`math/fp16.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Color Palette](#color-palette)
- [Configuration Descriptor](#configuration-descriptor)
- [Flag Bits](#flag-bits)
- [Creating & Freeing Configs](#creating--freeing-configs)
- [Drawing](#drawing)
- [View Control](#view-control)
- [Convenience](#convenience)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Surface-targeted** | All rendering writes to an RGBA8888 surface created with `SURF-CREATE`. |
| **FP16 samples** | PCM data is 16-bit half-precision float, as produced by `akashic-syn` engines. |
| **Config descriptor** | A single 120-byte struct holds all display parameters — allocate once, draw many times. |
| **Immediate mode** | Each `WAVE-DRAW` call clears and redraws the entire surface. No retained state between frames. |
| **Zoom & pan** | `WAVE-ZOOM` sets a sub-range of the PCM buffer; `WAVE-AMPLITUDE!` scales the Y axis. |
| **Flag-driven features** | Grid, zero line, envelope, fill mode, and stereo stacking are toggled via bit flags. |
| **Prefix convention** | Public: `WAVE-`. Internal: `_WV-`. |

---

## Color Palette

All colors are 32-bit RGBA8888 constants.

| Constant | Value | Description |
|---|---|---|
| `WAVE-BG` | `0x1A1A2EFF` | Dark navy background |
| `WAVE-GRID` | `0x2D4A7AFF` | Muted blue grid lines |
| `WAVE-ZERO-LINE` | `0x4A90D9FF` | Brighter blue zero line |
| `WAVE-COLOR` | `0x00E676FF` | Green waveform trace |
| `WAVE-COLOR-DIM` | `0x00E67680` | Translucent green (stereo overlay) |
| `WAVE-PEAK` | `0xFF5252FF` | Red peak markers |
| `WAVE-ENVELOPE` | `0xFFD740FF` | Yellow peak envelope |
| `WAVE-TEXT-COLOR` | `0xFFFFFFFF` | White text/labels |
| `WAVE-GRID-MINOR` | `0x3A3A5CFF` | Faint minor grid |

These are defaults stored into each new config.  Override any color
by writing directly to the corresponding config field.

---

## Configuration Descriptor

120 bytes, 15 cells (8 bytes each on Megapad-64).

| Offset | Field | Type | Default | Description |
|---|---|---|---|---|
| 0 | `WC.START` | integer | 0 | Start frame (first visible sample) |
| 8 | `WC.COUNT` | integer | PCM length | Number of frames to display |
| 16 | `WC.AMPSCALE` | FP16 | 1.0 | Amplitude scale factor |
| 24 | `WC.GRIDX` | integer | 0 | Time grid interval in frames; 0 = auto (~8 divisions) |
| 32 | `WC.GRIDY` | integer | 4 | Amplitude grid divisions; 0 = none |
| 40 | `WC.FLAGS` | bitfield | `GRID \| ZERO` | Feature flags (see below) |
| 48 | `WC.BG` | RGBA | `WAVE-BG` | Background color |
| 56 | `WC.FG` | RGBA | `WAVE-COLOR` | Primary waveform color |
| 64 | `WC.FG2` | RGBA | `WAVE-COLOR-DIM` | Secondary channel color |
| 72 | `WC.GRIDCOLOR` | RGBA | `WAVE-GRID` | Grid line color |
| 80 | `WC.ZEROCOLOR` | RGBA | `WAVE-ZERO-LINE` | Zero-crossing line color |
| 88 | `WC.PEAKCOLOR` | RGBA | `WAVE-ENVELOPE` | Peak envelope color |
| 96 | `WC.MARGIN` | integer | 4 | Margin in pixels (all sides) |
| 104 | `WC.PCM` | pointer | — | PCM buffer pointer |
| 112 | `WC.SURF` | pointer | — | Target surface pointer |

---

## Flag Bits

Combine with `OR` and write to `WC.FLAGS`, or use `WAVE-FLAGS!`.

| Constant | Value | Effect |
|---|---|---|
| `WAVE-F-GRID` | 1 | Draw amplitude and time grid lines |
| `WAVE-F-ZERO` | 2 | Draw zero-crossing horizontal line |
| `WAVE-F-ENVELOPE` | 4 | Draw peak envelope overlay |
| `WAVE-F-STEREO-STACK` | 8 | Stereo: stacked top/bottom (else overlaid) |
| `WAVE-F-FILLED` | 16 | Filled waveform area (else line trace) |

---

## Creating & Freeing Configs

### WAVE-CONFIG-CREATE

```forth
WAVE-CONFIG-CREATE  ( pcm surf -- cfg )
```

Allocate a 120-byte config descriptor and initialize it with
sensible defaults.  `pcm` is a PCM buffer (from `akashic-pcm`),
`surf` is the target surface.  The view window defaults to the
full buffer; amplitude scale is 1.0; grid and zero line are
enabled.

```forth
my-pcm my-surf WAVE-CONFIG-CREATE CONSTANT wc
```

### WAVE-CONFIG-FREE

```forth
WAVE-CONFIG-FREE  ( cfg -- )
```

Release the config descriptor.  Does not free the PCM buffer or
surface — the caller owns those.

```forth
wc WAVE-CONFIG-FREE
```

---

## Drawing

### WAVE-DRAW

```forth
WAVE-DRAW  ( cfg -- )
```

Main rendering entry point.  Reads all parameters from the config
descriptor and performs, in order:

1. Clear the surface to `WC.BG`.
2. Draw grid lines (if `WAVE-F-GRID`).
3. Draw zero-crossing line (if `WAVE-F-ZERO`).
4. Draw waveform — filled or line mode depending on `WAVE-F-FILLED`.
5. Draw peak envelope (if `WAVE-F-ENVELOPE`).

**Line mode** (default): when samples-per-pixel ≤ 1 (zoomed in),
draws one pixel per sample connected by vertical lines.  When
zoomed out, scans the sample range for each pixel column and draws
a min/max vertical bar.

**Filled mode** (`WAVE-F-FILLED`): draws a vertical bar from the
zero line to the sample value for each pixel column.

```forth
wc WAVE-DRAW
```

---

## View Control

### WAVE-ZOOM

```forth
WAVE-ZOOM  ( start count cfg -- )
```

Set the visible window.  `start` is the first frame index; `count`
is the number of frames to display.

```forth
0 512 wc WAVE-ZOOM     \ show first 512 frames
256 1024 wc WAVE-ZOOM  \ show frames 256–1279
```

### WAVE-AMPLITUDE!

```forth
WAVE-AMPLITUDE!  ( fp16-scale cfg -- )
```

Set the amplitude scale factor (FP16).  Values > 1.0 amplify the
display; < 1.0 attenuate.

$Y_{\text{pixel}} = \text{mid} - (\text{sample} \times \text{amp} \times \text{half\_height})$

```forth
0x4000 wc WAVE-AMPLITUDE!    \ 2.0× magnification
0x4800 wc WAVE-AMPLITUDE!    \ 8.0× magnification
```

### WAVE-FLAGS!

```forth
WAVE-FLAGS!  ( flags cfg -- )
```

Replace all flags at once.

```forth
WAVE-F-GRID WAVE-F-ZERO OR WAVE-F-FILLED OR
wc WAVE-FLAGS!
```

---

## Convenience

### WAVE-RENDER

```forth
WAVE-RENDER  ( pcm surf -- )
```

One-shot render: creates a default config, draws, and frees the
config.  Ideal for quick previews.

```forth
my-pcm my-surf WAVE-RENDER
```

---

## Internals

| Word | Purpose |
|---|---|
| `_WV-SETUP` | Extract config fields into scratch variables, compute plot area. |
| `_WV-SAMPLE>Y` | Convert FP16 sample to pixel Y coordinate. |
| `_WV-GET-SAMPLE` | Read a frame from PCM, bounds-checked. |
| `_WV-DRAW-BG` | Clear surface to background color. |
| `_WV-DRAW-GRID` | Draw amplitude (horizontal) and time (vertical) grid lines. |
| `_WV-DRAW-ZERO` | Draw zero-crossing horizontal line at vertical center. |
| `_WV-DRAW-WAVE-LINE` | Line-mode waveform renderer (min/max bars when zoomed out). |
| `_WV-DRAW-WAVE-FILLED` | Filled-mode waveform renderer. |
| `_WV-DRAW-ENVELOPE` | Peak envelope overlay (scans blocks of samples). |
| `_WV-CFG`, `_WV-SURF`, ... | Scratch variables (avoid `R@` inside `DO...LOOP`). |

> **Note:** Forth's `R@` inside `DO...LOOP` returns the loop index,
> not a value pushed with `>R`.  All draw loops use `VARIABLE` scratch
> instead of the return stack to hold colors and parameters.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `WAVE-CONFIG-CREATE` | `( pcm surf -- cfg )` | Allocate & init config |
| `WAVE-CONFIG-FREE` | `( cfg -- )` | Free config |
| `WAVE-DRAW` | `( cfg -- )` | Render waveform to surface |
| `WAVE-RENDER` | `( pcm surf -- )` | One-shot render |
| `WAVE-ZOOM` | `( start count cfg -- )` | Set view window |
| `WAVE-AMPLITUDE!` | `( fp16-scale cfg -- )` | Set amplitude scale |
| `WAVE-FLAGS!` | `( flags cfg -- )` | Set feature flags |

---

## Cookbook

### Basic waveform display

```forth
REQUIRE render/visualization/waveform.f

\ Assume PCM buffer and surface already created
my-pcm 320 240 SURF-CREATE 2DUP WAVE-RENDER
\ Surface now contains the waveform image
```

### Customized view with filled mode

```forth
my-pcm my-surf WAVE-CONFIG-CREATE CONSTANT wc

\ Show 1024 samples starting at frame 0, 4x magnification
0 1024 wc WAVE-ZOOM
0x4400 wc WAVE-AMPLITUDE!

\ Enable filled mode + grid + zero + envelope
WAVE-F-GRID WAVE-F-ZERO OR WAVE-F-FILLED OR WAVE-F-ENVELOPE OR
wc WAVE-FLAGS!

\ Custom colors
0x1E1E2EFF wc WC.BG + !              \ darker background
0x66BB6AFF wc WC.FG + !              \ lighter green waveform

wc WAVE-DRAW
wc WAVE-CONFIG-FREE
```

### Zoomed-in detail view

```forth
my-pcm my-surf WAVE-CONFIG-CREATE CONSTANT wc

\ Zoom to 64 samples starting at frame 500
500 64 wc WAVE-ZOOM
0x4000 wc WAVE-AMPLITUDE!   \ 2× scale

wc WAVE-DRAW
wc WAVE-CONFIG-FREE
```
