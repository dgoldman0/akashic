# akashic-spectrum — FFT Spectral Display

Renders a frequency-domain spectral plot from a PCM audio buffer.
Computes an in-place FFT, applies Hann windowing and 1/N prescaling
to prevent FP16 overflow, then draws magnitude bars or a line plot
with optional peak-hold markers.

```forth
REQUIRE render/visualization/spectrum.f
```

`PROVIDED akashic-spectrum` — safe to include multiple times.
Automatically requires `surface.f`, `draw.f`, `audio/pcm.f`,
`math/fp16.f`, `math/fp16-ext.f`, and `math/fft.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Color Palette](#color-palette)
- [Configuration Descriptor](#configuration-descriptor)
- [Flag Bits](#flag-bits)
- [Creating & Freeing Configs](#creating--freeing-configs)
- [Drawing](#drawing)
- [Analysis Control](#analysis-control)
- [Convenience](#convenience)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Surface-targeted** | All rendering writes to an RGBA8888 surface. |
| **FP16 throughout** | Samples, FFT, magnitudes, and scaling are all half-precision float. |
| **Config descriptor** | A 128-byte struct owns the FFT working buffers — allocate once, reuse across frames. |
| **Hann windowing** | Parabolic approximation $w(n) \approx n(N-n) \cdot 4/N^2$ reduces spectral leakage without a lookup table. |
| **Overflow-safe** | Window scale computed as $(2/N)^2$ instead of $4/N^2$ to avoid $N^2$ overflow in FP16 (max 65504). Each sample is also prescaled by $1/N$ before the FFT butterfly. |
| **Auto-scale** | After FFT, the ceiling is set to $1.1 \times \max(\text{bins})$ so the tallest bar fills the display. |
| **Peak-hold** | Optional per-bin peak markers with exponential decay ($\times 0.99$ per frame). |
| **Prefix convention** | Public: `SPEC-`. Internal: `_SP-`. |

---

## Color Palette

| Constant | Value | Description |
|---|---|---|
| `SPEC-BG` | `0x0D1117FF` | Very dark background |
| `SPEC-GRID` | `0x21262DFF` | Faint grid lines |
| `SPEC-LINE-COLOR` | `0x58A6FFFF` | Bright blue line mode stroke |
| `SPEC-BAR-LO` | `0x1F6FEBFF` | Bar gradient low (blue) |
| `SPEC-BAR-HI` | `0x56D364FF` | Bar gradient high (green) |
| `SPEC-PEAK-HOLD` | `0xFF7B72FF` | Red-orange peak-hold markers |
| `SPEC-TEXT` | `0xFFFFFFFF` | White text |
| `SPEC-AXIS` | `0x8B949EFF` | Grey axis lines |

---

## Configuration Descriptor

128 bytes, 16 cells.

| Offset | Field | Type | Default | Description |
|---|---|---|---|---|
| 0 | `SC.FFTSIZE` | integer | (arg) | FFT size — must be a power of 2 |
| 8 | `SC.START` | integer | 0 | Start frame for analysis window |
| 16 | `SC.FLAGS` | bitfield | `BARS\|LOG\|GRID\|WINDOW` | Feature flags |
| 24 | `SC.FLOOR` | FP16 | 0.0 | Magnitude floor |
| 32 | `SC.CEIL` | FP16 | 1.0 | Magnitude ceiling (auto-updated each draw) |
| 40 | `SC.BG` | RGBA | `SPEC-BG` | Background color |
| 48 | `SC.BARCOLOR` | RGBA | `SPEC-BAR-LO` | Bar / line color |
| 56 | `SC.PEAKCOLOR` | RGBA | `SPEC-PEAK-HOLD` | Peak marker color |
| 64 | `SC.GRIDCOLOR` | RGBA | `SPEC-GRID` | Grid line color |
| 72 | `SC.MARGIN` | integer | 4 | Margin pixels (all sides) |
| 80 | `SC.PCM` | pointer | — | PCM buffer pointer |
| 88 | `SC.SURF` | pointer | — | Target surface pointer |
| 96 | `SC.REBUF` | pointer | — | Real buffer for FFT (allocated) |
| 104 | `SC.IMBUF` | pointer | — | Imaginary buffer for FFT (allocated) |
| 112 | `SC.MAGBUF` | pointer | — | Magnitude output buffer (allocated) |
| 120 | `SC.PEAKBUF` | pointer | — | Peak-hold buffer (allocated) |

The four working buffers (`REBUF`, `IMBUF`, `MAGBUF`, `PEAKBUF`)
are allocated by `SPEC-CONFIG-CREATE` and freed by
`SPEC-CONFIG-FREE`.  Each is `fftsize × 2` bytes (one FP16 per
bin).

---

## Flag Bits

| Constant | Value | Effect |
|---|---|---|
| `SPEC-F-BARS` | 1 | Bar display mode (else line) |
| `SPEC-F-LOG` | 2 | Logarithmic magnitude scale (else linear) |
| `SPEC-F-PEAK-HOLD` | 4 | Draw peak-hold markers with decay |
| `SPEC-F-GRID` | 8 | Draw grid lines (4 horizontal, 8 vertical) |
| `SPEC-F-WINDOW` | 16 | Apply Hann window before FFT |

---

## Creating & Freeing Configs

### SPEC-CONFIG-CREATE

```forth
SPEC-CONFIG-CREATE  ( pcm surf fftsize -- cfg )
```

Allocate a 128-byte config and four FFT working buffers sized to
`fftsize`.  The peak-hold buffer is zeroed.  Default flags enable
bars, log scale, grid, and windowing.

```forth
my-pcm my-surf 256 SPEC-CONFIG-CREATE CONSTANT sc
```

### SPEC-CONFIG-FREE

```forth
SPEC-CONFIG-FREE  ( cfg -- )
```

Free all four working buffers and the config descriptor.  Does not
free the PCM buffer or surface.

```forth
sc SPEC-CONFIG-FREE
```

---

## Drawing

### SPEC-DRAW

```forth
SPEC-DRAW  ( cfg -- )
```

Main rendering entry point.  Performs, in order:

1. Load PCM samples into the real buffer, applying Hann window
   (if `SPEC-F-WINDOW`) and $1/N$ prescaling.
2. Run the FFT via `FFT-FORWARD` and `FFT-MAGNITUDE`.
3. **Auto-scale**: scan displayable bins (skipping DC), set ceiling
   to $1.1 \times \max$.
4. Update peak-hold buffer (if `SPEC-F-PEAK-HOLD`).
5. Clear surface to `SC.BG` and draw grid.
6. Draw bars or line depending on `SPEC-F-BARS`.
7. Draw peak-hold markers (if enabled).

Only the first $N/2$ bins are displayed (Nyquist symmetry).

**Bar mode**: each bin gets a rectangular bar from the plot bottom
up to the scaled magnitude height, drawn with `SC.BARCOLOR`.

**Line mode**: connects bin magnitudes with `DRAW-LINE` using
`SPEC-LINE-COLOR`.

```forth
sc SPEC-DRAW
```

---

## Analysis Control

### SPEC-WINDOW!

```forth
SPEC-WINDOW!  ( start cfg -- )
```

Set the starting frame for the analysis window.  The FFT reads
`fftsize` frames beginning at `start`.

```forth
512 sc SPEC-WINDOW!   \ analyze starting at frame 512
```

### SPEC-FFT-SIZE@

```forth
SPEC-FFT-SIZE@  ( cfg -- n )
```

Read the FFT size from the config.

```forth
sc SPEC-FFT-SIZE@   \ -- 256
```

---

## Convenience

### SPEC-RENDER

```forth
SPEC-RENDER  ( pcm surf -- )
```

One-shot render: creates a 256-point FFT config, draws, and frees.

```forth
my-pcm my-surf SPEC-RENDER
```

---

## Internals

| Word | Purpose |
|---|---|
| `_SP-SETUP` | Extract config fields into scratch variables, compute plot area. |
| `_SP-LOAD-SAMPLES` | Copy PCM into real buffer with optional Hann window and $1/N$ prescaling. |
| `_SP-COMPUTE-FFT` | Run `FFT-FORWARD` + `FFT-MAGNITUDE`. |
| `_SP-AUTO-SCALE` | Scan bins, set ceiling = $1.1 \times \max$. |
| `_SP-MAG>HEIGHT` | Normalize magnitude to pixel height: $(m - \text{floor}) / (\text{ceil} - \text{floor}) \times H$. |
| `_SP-UPDATE-PEAKS` | Update peak-hold buffer (max with current, decay $\times 0.99$). |
| `_SP-DRAW-BG` | Clear surface. |
| `_SP-DRAW-GRID` | 4 horizontal + 8 vertical grid lines. |
| `_SP-DRAW-BARS` | Bar-mode renderer. |
| `_SP-DRAW-LINE` | Line-mode renderer. |
| `_SP-DRAW-PEAKS` | Peak-hold marker renderer. |
| `_SP-WSCALE` | $4/N^2$ window scale (computed as $(2/N)^2$). |
| `_SP-PRESCALE` | $1/N$ sample prescale. |
| `_SP-ALLOC-CFG` | Scratch variable for config pointer during allocation. |

> **FP16 overflow note:** $N^2$ for $N \geq 256$ exceeds FP16's max
> representable value (65504).  The window scale is therefore computed
> as $(2/N) \times (2/N)$ rather than $4 / (N \times N)$.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `SPEC-CONFIG-CREATE` | `( pcm surf fftsize -- cfg )` | Allocate & init config + buffers |
| `SPEC-CONFIG-FREE` | `( cfg -- )` | Free config + buffers |
| `SPEC-DRAW` | `( cfg -- )` | Run FFT and render spectrum |
| `SPEC-RENDER` | `( pcm surf -- )` | One-shot 256-point render |
| `SPEC-WINDOW!` | `( start cfg -- )` | Set analysis window start |
| `SPEC-FFT-SIZE@` | `( cfg -- n )` | Read FFT size |

---

## Cookbook

### Basic spectrum display

```forth
REQUIRE render/visualization/spectrum.f

my-pcm 320 240 SURF-CREATE 2DUP SPEC-RENDER
\ Surface now contains the spectrum bar chart
```

### Customized 512-point FFT with peak hold

```forth
my-pcm my-surf 512 SPEC-CONFIG-CREATE CONSTANT sc

\ Enable peak hold
sc SC.FLAGS + @  SPEC-F-PEAK-HOLD OR  sc SC.FLAGS + !

\ Custom bar color
0x42A5F5FF sc SC.BARCOLOR + !

\ Analyze from frame 1024
1024 sc SPEC-WINDOW!

sc SPEC-DRAW
sc SPEC-CONFIG-FREE
```

### Sliding-window animation loop

```forth
my-pcm my-surf 256 SPEC-CONFIG-CREATE CONSTANT sc

: ANIMATE-SPECTRUM  ( n-frames -- )
    0 DO
        I 256 * sc SPEC-WINDOW!
        sc SPEC-DRAW
        \ ... display surface or export BMP ...
    LOOP ;

100 ANIMATE-SPECTRUM
sc SPEC-CONFIG-FREE
```
