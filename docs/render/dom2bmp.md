# akashic-dom2bmp — End-to-End HTML → BMP Renderer

Glues the full Akashic render pipeline into a single call:
HTML string → DOM tree → box tree → layout → paint → BMP bytes.

```forth
REQUIRE render/dom2bmp.f
```

`PROVIDED akashic-dom2bmp` — safe to include multiple times.
Automatically requires `paint.f` and `bmp.f` (and transitively
`box.f`, `layout.f`, `line.f`, `surface.f`, `draw.f`, `dom.f`,
`css.f`, `markup/`, `text/layout.f`, `utils/string.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Prerequisites](#prerequisites)
- [Public API](#public-api)
  - [DOM2BMP-RENDER](#dom2bmp-render)
  - [DOM2BMP-SIZE](#dom2bmp-size)
- [Pipeline Stages](#pipeline-stages)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Single-call render** | One word (`DOM2BMP-RENDER`) takes HTML text and produces a complete BMP file — no intermediate steps needed by the caller. |
| **No allocation** | Writes directly into a caller-supplied buffer.  Returns 0 if the buffer is too small. |
| **Surface lifecycle** | Creates an XMEM-backed surface internally, paints to it, encodes BMP, then destroys the surface before returning. |
| **White background** | Surface is cleared to `0xFFFFFFFF` (opaque white) before painting. |
| **Prefix convention** | Public: `DOM2BMP-`.  Internal: `_D2B-`. |

---

## Dependencies

```
dom2bmp.f
├── paint.f    (akashic-paint — PAINT-RENDER)
│   ├── box.f      (akashic-box — BOX-BUILD-TREE, BOX-RESOLVE-STYLE)
│   ├── surface.f  (akashic-surface — SURF-CREATE, SURF-CLEAR, SURF-DESTROY)
│   ├── draw.f     (akashic-draw — DRAW-TEXT)
│   └── layout.f   (akashic-layout-engine — LAYO-LAYOUT)
│       ├── line.f        (akashic-line — LINE-BREAK, LINE-ALIGN)
│       └── text/layout.f (akashic-text-layout — LAY-TEXT-WIDTH)
└── bmp.f      (akashic-bmp — BMP-ENCODE, BMP-FILE-SIZE)
```

Transitively loads: `dom.f`, `css.f`, `bridge.f`, `html.f`,
`core.f`, `string.f`, `color.f`, `fp16.f`, etc.

---

## Prerequisites

Before calling `DOM2BMP-RENDER` the caller must set up:

1. **DOM arena** — create an arena and document via `ARENA-NEW` +
   `DOM-DOC-NEW` + `DOM-USE`.
2. **CSS stylesheet** (optional) — call `DOM-SET-STYLESHEET` with
   CSS text for styling beyond defaults.
3. **TTF font** — load a TrueType font into XMEM and parse its
   tables (`TTF-BASE!`, `TTF-PARSE-HEAD`, etc.) so that text
   measurement and rendering have glyph data available.
4. **Output buffer** — allocate at least `DOM2BMP-SIZE` bytes for
   the BMP output.

---

## Public API

### DOM2BMP-RENDER

```forth
DOM2BMP-RENDER  ( html-a html-u vp-w vp-h buf max -- len | 0 )
```

Render an HTML string to a BMP image in a single call.

| Parameter | Description |
|---|---|
| `html-a html-u` | HTML string (address + length) |
| `vp-w` | Viewport width in pixels |
| `vp-h` | Viewport height in pixels |
| `buf` | Output buffer address |
| `max` | Output buffer size in bytes |

**Returns:** BMP byte count on success, or `0` if the buffer was too
small or parsing failed.

**Pipeline executed internally:**

1. `DOM-PARSE-HTML` — parse HTML into DOM tree
2. `BOX-BUILD-TREE` — generate box tree with resolved styles
3. `LAYO-LAYOUT` — compute positions and dimensions
4. `SURF-CREATE` + `SURF-CLEAR` — create and clear surface (white)
5. `PAINT-RENDER` — walk box tree and paint to surface
6. `BMP-ENCODE` — encode surface as 32-bit BMP
7. `SURF-DESTROY` — free the surface

### DOM2BMP-SIZE

```forth
DOM2BMP-SIZE  ( vp-w vp-h -- bytes )
```

Compute the exact BMP file size for a given viewport.  Delegates to
`BMP-FILE-SIZE`.  Use this to determine how large the output buffer
must be.

$$\text{bytes} = 54 + (w \times h \times 4)$$

---

## Pipeline Stages

```
HTML string ─────────────────────────────────────────────────────┐
  │                                                              │
  ▼                                                              │
DOM-PARSE-HTML  → DOM tree (fragment with children)              │
  │                                                              │
  ▼                                                              │
BOX-BUILD-TREE  → box tree (styled, mirroring DOM minus none)    │
  │                                                              │
  ▼                                                              │
LAYO-LAYOUT     → positioned tree (x, y, w, h resolved)         │
  │                                                              │
  ▼                                                              │
SURF-CREATE ──→ PAINT-RENDER ──→ BMP-ENCODE ──→ BMP bytes ──────┘
                                    │
                SURF-DESTROY ◄──────┘
```

---

## Internals

| Variable | Purpose |
|---|---|
| `_D2B-VPW` / `_D2B-VPH` | Viewport dimensions |
| `_D2B-BUF` / `_D2B-MAX` | Output buffer address and maximum size |
| `_D2B-DOM` | DOM root returned by `DOM-PARSE-HTML` |
| `_D2B-BOX` | Box tree root returned by `BOX-BUILD-TREE` |
| `_D2B-SURF` | Surface handle (created and destroyed per call) |

**Note:** The DOM tree and box tree are **not** freed by
`DOM2BMP-RENDER`.  The DOM tree lives in the arena (freed by
`ARENA-DESTROY`).  The box tree should be freed by the caller via
`BOX-FREE-TREE` if needed, or left for arena teardown.

---

## Quick Reference

```
DOM2BMP-RENDER  ( html-a html-u vp-w vp-h buf max -- len | 0 )
DOM2BMP-SIZE    ( vp-w vp-h -- bytes )
```

---

## Cookbook

### Render a simple page

```forth
REQUIRE render/dom2bmp.f

\ Set up arena + document
524288 A-XMEM ARENA-NEW DROP CONSTANT my-arena
my-arena 256 128 DOM-DOC-NEW CONSTANT my-doc

\ Load a font (assumes font file on disk)
OPEN Roboto-Regular.ttf CONSTANT fnt
fnt FSIZE DUP XMEM-ALLOT DUP ROT fnt FREAD DROP
TTF-BASE!
TTF-PARSE-HEAD DROP  TTF-PARSE-MAXP DROP
TTF-PARSE-HHEA DROP  TTF-PARSE-HMTX DROP
TTF-PARSE-LOCA DROP  TTF-PARSE-GLYF DROP
TTF-PARSE-CMAP DROP

\ Render 320×240 viewport
S" <div style='color:red'>Hello, world!</div>"
320 240
320 240 DOM2BMP-SIZE XMEM-ALLOT DUP ROT
DOM2BMP-RENDER
\ Stack: ( bmp-len )
\ The XMEM buffer now contains a valid BMP file.
```

### Render with a stylesheet

```forth
S" h1 { color: blue; font-size: 24px } p { margin: 8px }"
DOM-SET-STYLESHEET

S" <h1>Title</h1><p>Body text</p>"
800 600
800 600 DOM2BMP-SIZE XMEM-ALLOT DUP ROT
DOM2BMP-RENDER
\ Stack: ( bmp-len )
```

### Check buffer size before rendering

```forth
800 600 DOM2BMP-SIZE  ( -- bytes )
.   \ 1920054
\ Ensure your buffer is at least that large.
```
