# Akashic

**A standard library for KDOS / Megapad-64, written entirely in Forth.**

Akashic is roughly 46,000 lines of Forth spread across 100 source files and 16 module directories. It provides a self-contained software stack for building applications on the 64-bit KDOS environment: numeric primitives, audio synthesis, 2D rendering with font rasterization, an HTTP client and server, a document object model, a CSS engine, a reactive UI framework, concurrency primitives, and a Bluesky (AT Protocol) client — all without leaving Forth.

Everything targets the Megapad-64 cell size (8 bytes), uses the KDOS memory model (dictionary, heap, XMEM, and hardware-banked memory), and follows a consistent set of conventions described below.

---

## Architecture at a Glance

The modules form a layered dependency graph. Nothing is circular; higher layers pull in what they need via `REQUIRE` and never touch modules above them.

```
atproto ─────── cbor ──────────────────────────┐
   │                                           │
   ├── net (http, ws, url, headers, base64)    │
   │    │                                      │
   │    └── utils (json, string, toml, yaml,   │
   │              datetime, table)             │
   │                                           │
web (server, router, middleware, template) ─────┤
   │                                           │
liraq (uidl, lel, state-tree, lcf, profile)    │
   │                                           │
   ├── sml (core, tree)                        │
   │                                           │
   ├── dom ─── css (css, bridge) ─── markup    │
   │                                           │
   ├── render ─── font ─── text               │
   │    │                                      │
   │    └── math (fp16, fp32, vec2, mat2d,    │
   │              trig, fft, simd, color, …)   │
   │                                           │
   └── audio (synth, osc, env, fm, fx, …)      │
        │                                      │
        └── math  ─────────────────────────────┘
                                               │
concurrency (channel, event, rwlock, semaphore) ┘
```

At the base sits **math/**, which supplies the numeric types everything else relies on. **audio/** and **render/** both draw heavily from math. **dom/**, **css/**, and **markup/** form a document processing spine. **liraq/** sits on top, consuming DOM, SML, and state-tree to drive reactive user interfaces. **net/** and **web/** provide the networking layers. **atproto/** caps the stack with a full Bluesky client that depends on net, CBOR, and JSON.

**concurrency/** is a standalone pillar — it talks only to KDOS spinlocks and events, and any module that needs inter-task communication pulls it in independently.

---

## Module Guide

### math/ — Numerics, Geometry, DSP, and Cryptography

**26 files · ~9,800 lines**

Megapad-64's tile engine provides hardware FP16 arithmetic (IEEE 754 half-precision, 10-bit mantissa). Akashic builds the rest of the numeric tower on top of it:

- **FP16 and FP16-ext** — core half-float words plus extended operations (square root, reciprocal, comparison chains). This is the default precision for coordinates, colors, and audio samples across the library.
- **FP32** — software-emulated single-precision float for situations that need more mantissa bits. Used by the LEL expression evaluator and some statistics routines.
- **Fixed-point** — 16.16 fixed-point for pixel-exact layout math where half-float rounding is too coarse.
- **Vectors and matrices** — `V2-` 2D vector operations and `M2D-` 2×3 affine matrices, both in FP16. Dot, cross, normalize, rotate, scale, invert.
- **Trigonometry** — `TRIG-SIN`, `TRIG-COS`, `TRIG-SINCOS`, `TRIG-ATAN2` via table lookup and linear interpolation, operating in FP16.
- **Color** — RGBA8888 packing/unpacking, HSL↔RGB conversion, alpha blending in FP16, palette generation. The packed 32-bit format is the currency of the render pipeline.
- **Bézier curves** — quadratic and cubic evaluation, flattening to line segments (used by the font rasterizer's contour walker and general vector drawing).
- **FFT** — radix-2 Cooley-Tukey, in-place decimation-in-time on paired FP16 arrays. Twiddle factors are computed on-the-fly via `TRIG-SINCOS` rather than stored, avoiding accumulation error in 10-bit mantissa. Forward/inverse transforms, magnitude, power spectrum, convolution, and cross-correlation.
- **SIMD** — access to the 512-bit tile engine's six vector modes. Raw lane read/write, horizontal reduce, batched multiply-accumulate, and high-level helpers for bulk FP16 operations.
- **Statistics and regression** — running mean/variance/stddev, Welford's online algorithm, min/max tracking, histograms, linear regression, polynomial fit, time-series moving averages (SMA, EMA, DEMA), and advanced statistics (skewness, kurtosis, percentiles).
- **Probability** — discrete and continuous distributions, random sampling.
- **DSP filters** — biquad coefficients (low-pass, high-pass, band-pass, notch, peaking EQ), shared with the audio synth.
- **Cryptography** — SHA-256 and SHA-512, full message-schedule unrolled implementations used by the AT Protocol module for content hashing, and by the WebSocket handshake for inline SHA-1.
- **Sorting and interpolation** — in-place quicksort, linear/cubic interpolation, search utilities.

### audio/ — Synthesis, Sequencing, and Audio I/O

**16 files · ~6,400 lines**

A complete audio synthesis toolkit built on FP16 PCM buffers. The signal flow follows a classic modular architecture:

**Oscillators** (`osc.f`) generate the raw waveforms — sine, sawtooth, square, and triangle — from a phase accumulator. Each oscillator is a small descriptor (frequency, phase, shape) that writes a block of FP16 samples into a PCM buffer.

**Envelopes** (`env.f`) provide ADSR amplitude shaping. Attack, decay, sustain, and release are specified in FP16 time-per-stage; the envelope multiplies an oscillator's output sample-by-sample.

**Subtractive synthesis** (`synth.f`) wraps one or two oscillators, a resonant biquad filter (low-pass, high-pass, or band-pass using Robert Bristow-Johnson coefficients from math/filter), and two ADSR envelopes (amplitude and filter cutoff modulation) into a 72-byte voice descriptor. The caller creates as many voices as needed for polyphony. `SYNTH-NOTE-ON` sets frequency and velocity; `SYNTH-RENDER` fills a buffer.

**FM synthesis** (`fm.f`) implements 2-operator and 4-operator frequency modulation with configurable modulation indices and operator ratios.

**Effects** (`fx.f`) provide delay, feedback delay, chorus, and reverb. **LFO** (`lfo.f`) is a low-frequency oscillator for parameter modulation. **Noise** (`noise.f`) generates white and pink noise. **Portamento** (`porta.f`) handles pitch glide between notes. **Karplus-Strong** (`pluck.f`) models plucked-string synthesis with a delay line and low-pass filter.

**Mixing** (`mix.f`) sums multiple PCM buffers with per-channel gain and panning. **Signal chains** (`chain.f`) connect generators and effects into a processing graph.

**Polyphony** (`poly.f`) manages note allocation across a pool of voices — note stealing, voice age tracking, release priority.

**Sequencer** (`seq.f`) drives patterns of note-on/note-off events over time, ticked forward by the caller.

**MIDI** (`midi.f`) parses MIDI messages (note on/off, control change, program change, pitch bend) and translates them into sequencer events.

**WAV** (`wav.f`) encodes and decodes RIFF/WAV files, converting between PCM buffers and byte streams for storage or network transmission.

### render/ — Surfaces, Drawing, Layout, and Image Codecs

**10 files · ~5,600 lines**

The render pipeline turns data into pixels. At its core is the **surface** — an RGBA8888 pixel buffer described by an 80-byte descriptor (width, height, stride, data pointer, clip rectangle). All drawing operations write into surfaces.

**Drawing primitives** (`draw.f`) provide filled and outlined rectangles, horizontal and vertical lines, and arbitrary pixel writes — all clip-aware. **Line drawing** (`line.f`) implements Bresenham's algorithm. **Paint** (`paint.f`) adds flood fill.

**Compositing** (`composite.f`, 488 lines) is entirely integer-math — no floating-point in the inner loop. It implements the full Porter-Duff family (source-over, source-in, source-out, source-atop, XOR) plus blend modes (multiply, screen, overlay, darken, lighten). A fast-path bulk scanline operation (`COMP-SCANLINE-OVER`) composites entire rows. Monochrome glyph blitting (`COMP-BLIT-MONO`) is the bridge between the font rasterizer and the surface.

**Box model** (`box.f`) builds a CSS-like box tree from DOM nodes — content, padding, border, and margin rectangles with FP16 dimensions.

**Layout** (`layout.f`) takes a box tree and a viewport size and resolves positions: block flow, inline flow, width/height calculation, margin collapsing — enough of CSS 2.1 to render real documents.

**Image codecs**: BMP (`bmp.f`) handles reading and writing Windows bitmap files with proper row padding. QOI (`qoi.f`) implements the Quite OK Image format — a modern, fast, lossless codec.

**DOM-to-BMP** (`dom2bmp.f`) is the end-to-end glue. Given an HTML string and a viewport size, it parses HTML into a DOM tree, extracts `<style>` tags, builds a box tree, runs layout, paints into a surface (including text via the font pipeline), and encodes the result as a BMP:

```
HTML string → markup parser → DOM tree → CSS style resolution
  → box tree → layout → paint (with font raster) → BMP bytes
```

### font/ — TrueType Parsing, Rasterization, and Caching

**3 files · ~1,400 lines**

**TTF parsing** (`ttf.f`) reads TrueType font files by walking the table directory and extracting the tables the rasterizer needs: `head` (units-per-em, index format), `maxp` (limits), `cmap` (character-to-glyph mapping, format 4 segment arrays), `loca` (glyph offsets), and `glyf` (glyph outlines). Composite glyphs (glyphs built from other glyphs) are supported.

**Rasterization** (`raster.f`, 734 lines) converts glyph outlines to pixels using even-odd scanline fill with configurable N×N supersampling (default 6×6). The contour walker handles TrueType on-curve and off-curve points: consecutive off-curve quadratic Bézier control points generate implied on-curve midpoints per the TrueType spec, then `BZ-QUAD-FLATTEN` from math/bezier breaks curves into line segments. Each output pixel gets 0–255 coverage from the supersampling grid; the caller's alpha blending (via `COMP-BLIT-MONO`) composites the glyph onto the background.

**Glyph cache** (`cache.f`) avoids re-rasterizing the same glyph at the same size. Keyed by glyph index and pixel size, it stores pre-rendered bitmaps and metrics for fast repeated drawing.

### text/ — UTF-8 and Text Layout

**2 files · ~400 lines**

`utf8.f` handles encoding, decoding, and validation of UTF-8 byte sequences — the interchange format for all string data in Akashic. `layout.f` does word-wrap text layout: given a string, a font, and a line width, it produces positioned glyph runs ready for the rasterizer.

### dom/ — Document Object Model

**1 file · ~1,200 lines**

An arena-backed DOM with five node types: element, text, comment, document, and document fragment. Each node is a compact fixed-size descriptor. The arena allocator avoids per-node heap allocation — the entire tree is destroyed in one `ARENA-DESTROY` call.

The DOM supports the usual tree operations (create, append, insert, remove, clone, traverse) plus query methods like `DOM-GET-BY-TAG` and `DOM-GET-BY-ID`. Attribute storage uses a linked list per element. A stylesheet can be attached via `DOM-SET-STYLESHEET` so the CSS bridge can resolve styles during layout.

### css/ — Stylesheet Parsing and Style Resolution

**2 files · ~1,900 lines**

`css.f` is a tokenizer and declaration parser that handles the subset of CSS needed by the render pipeline — properties like `color`, `background-color`, `margin`, `padding`, `border`, `width`, `height`, `font-size`, `display`, and `text-align`. Selector matching covers type selectors, class selectors, ID selectors, descendant combinators, and the universal selector, with full specificity calculation.

`bridge.f` connects the CSS engine to the DOM. Given a DOM tree with an attached stylesheet, it walks every element, matches selectors, resolves cascading and specificity, and attaches computed style values that the box model and layout engine consume.

### markup/ — XML and HTML Parsing

**3 files · ~1,800 lines**

A two-layer parser. `core.f` provides the shared low-level machinery: tag scanning, attribute name/value extraction, entity decoding (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#NNN;`, `&#xHHH;`), and the cursor-based (`addr len`) parse loop.

`xml.f` adds XML-specific rules (self-closing tags, namespaces). `html.f` adds HTML5 specifics — void elements (`<br>`, `<img>`, `<hr>`, `<meta>`, `<input>`, etc.) that don't require closing tags, and the HTML5 named entity set. Both produce DOM trees via the `dom/` module.

### sml/ — Sequential Markup Language

**2 files · ~1,500 lines**

SML is a modality-neutral document format for one-dimensional user interfaces — it describes what content exists and how it's structured, without assuming a screen. A 1D UI is inherently sequential: the user navigates forward or backward through items, optionally grouped by scope containers.

The spec defines 25 element types across six categories: envelopes (`<sml>`, `<head>`), metadata (`<title>`, `<meta>`, `<link>`, `<style>`, `<cue-def>`), scope containers (`<seq>`, `<ring>`, `<gate>`, `<trap>`), positional items (`<item>`, `<act>`, `<val>`, `<pick>`, `<ind>`, `<tick>`, `<alert>`), structural elements (`<announce>`, `<shortcut>`, `<hint>`, `<gap>`, `<lane>`), and inline elements.

`core.f` parses SML documents, classifying elements, validating nesting rules, and checking required attributes. `tree.f` builds the navigable SML tree that the LIRAQ UI framework consumes.

### liraq/ — Reactive UI Framework

**5 files · ~5,000 lines**

LIRAQ is the declarative UI layer. It ties together SML documents, a reactive state tree, an expression evaluator, and a layout configuration system into a framework for building interactive interfaces.

**State tree** (`state-tree.f`) is a hierarchical key-value store with seven value types (string, integer, boolean, null, float, array, object). Nodes are 96-byte descriptors arranged in a tree. Changes are journaled: each mutation records old and new values so listeners can react efficiently. The API supports path-based access (`ST-PATH`), array indexing, and subtree operations.

**LEL** (`lel.f`, 1,639 lines) is the LIRAQ Expression Language — a Pratt parser evaluator for data-binding expressions. LEL is pure, total, and deterministic: every expression produces a value, never an error. Division by zero yields 0, a missing path yields null, and type mismatches silently coerce. It supports arithmetic, comparison, string concatenation, conditional (`?:`), property access, array indexing, and 48 built-in functions. LEL expressions bind UI elements to state tree values; when the state changes, the expressions are re-evaluated and the UI updates.

**UIDL** (`uidl.f`, 982 lines) parses UIDL XML documents into a static-pool element tree. It defines 16 element types and 6 arrangement modes, with an FNV-1a hash table for O(1) element lookup by ID. Each element carries optional `bind=` and `when=` attributes — LEL expressions for data binding and conditional visibility. Collections support `<template>` and `<empty>` children for list rendering.

**LCF** (`lcf.f`) handles layout configuration, and **profile** (`profile.f`) provides performance instrumentation for the UI pipeline.

### concurrency/ — Channels, Locks, and Synchronization

**4 files · ~1,200 lines**

Built on KDOS spinlocks and events, the concurrency module provides four primitives:

**Channels** (`channel.f`, 463 lines) are Go-style bounded CSP channels. Each channel is a 120-byte descriptor embedding a circular buffer, a per-channel spinlock, and two events (not-full, not-empty). Sending blocks when the buffer is full; receiving blocks when it's empty. Two API flavors exist: single-cell (64-bit values) and buffer-based (arbitrary element sizes). `CHAN-SELECT` polls multiple channels and returns the first one with data. Closed-channel semantics follow Go conventions: sends throw, receives on an empty closed channel return 0.

**Events** (`event.f`) provide a blocking/waking mechanism — one task waits on an event, another signals it.

**Reader-writer locks** (`rwlock.f`) allow concurrent readers or exclusive writers, with RAII-style cleanup via `CATCH`.

**Semaphores** (`semaphore.f`) are standard counting semaphores for resource limiting.

### net/ — HTTP Client, WebSocket, and Protocol Utilities

**6 files · ~2,500 lines**

**HTTP client** (`http.f`, 516 lines) implements HTTP/1.1 with an 8-slot DNS cache, chunked transfer-encoding, automatic redirect following, optional bearer-token auth, configurable timeouts, and response parsing. All socket operations are vectored through execution-token variables so tests can substitute mock I/O without real network access.

**WebSocket** (`ws.f`) handles the upgrade handshake (including inline SHA-1 for the `Sec-WebSocket-Accept` header), frame masking, ping/pong, and fragment reassembly for text and binary messages.

**URL and URI** (`url.f`, `uri.f`) parse and decompose URLs and URIs into scheme, host, port, path, query, and fragment components. **Headers** (`headers.f`) manages HTTP header collections. **Base64** (`base64.f`) provides standard Base64 encoding and decoding.

### web/ — HTTP Server

**6 files · ~1,700 lines**

A full HTTP server stack:

**Server** (`server.f`, 330 lines) runs the accept loop — it binds a socket, listens, and for each connection runs the request→dispatch→response lifecycle. All socket operations are vectored via XT variables for testability.

**Request** (`request.f`) parses incoming HTTP requests: method, path, version, headers, and optional body. **Response** (`response.f`) builds HTTP responses: status line, headers, and body content.

**Router** (`router.f`, 244 lines) matches incoming requests against registered routes. Routes are stored in a 64-slot table with method, pattern, and handler execution-token. Pattern matching supports path parameters (`:param` syntax) for dynamic segments.

**Middleware** (`middleware.f`) chains request processors — each middleware word can inspect/modify the request, call the next handler, and post-process the response.

**Template** (`template.f`) is a string-based template engine for generating HTML responses with variable interpolation.

### cbor/ — Binary Serialization

**2 files · ~400 lines**

`cbor.f` implements RFC 8949 CBOR encoding and decoding — integers (positive and negative), byte strings, text strings, arrays, maps, booleans, null, and tags. Decoding is zero-copy where possible, returning pointers into the input buffer.

`dag-cbor.f` extends the base encoder with the DAG-CBOR profile used by the AT Protocol: deterministic map key ordering and CID tag handling for content-addressed data structures.

### atproto/ — Bluesky / AT Protocol Client

**6 files · ~800 lines**

A complete AT Protocol client stack for interacting with Bluesky PDS servers:

**Session** (`session.f`) handles authentication — `SESS-LOGIN` calls `com.atproto.server.createSession` with a handle and app password, stores the returned access and refresh JWTs (512-byte buffers), and installs the bearer token on the HTTP client. `SESS-REFRESH` renews tokens before expiry.

**XRPC** (`xrpc.f`) wraps HTTP for AT Protocol procedure calls — it builds the correct URL, sets content-type headers, and dispatches GET (query) and POST (procedure) XRPC endpoints.

**DID** (`did.f`) validates and parses Decentralized Identifiers. **AT-URI** (`aturi.f`) handles `at://` URI parsing. **TID** (`tid.f`) generates timestamp-based identifiers for records. **Repo** (`repo.f`) provides create/read/update/delete operations against AT Protocol repositories.

### utils/ — Data Formats and Common Utilities

**6 files · ~4,400 lines**

**JSON** (`json.f`) is a full reader and builder. The reader walks a `( addr len )` cursor through JSON text, extracting values by key lookup (`JSON-KEY?`) or array indexing. The builder constructs JSON documents via a stack-based API (`JSON-OBJ-START`, `JSON-KEY`, `JSON-VAL-STR`, `JSON-OBJ-END`).

**String** (`string.f`) provides comparison, searching, trimming, splitting, case conversion, and number↔string conversion utilities — the "standard library" for Forth's native `( addr len )` strings.

**TOML** and **YAML** (`toml.f`, `yaml.f`) parse their respective configuration file formats into key-value pairs the caller can query.

**Datetime** (`datetime.f`) handles date/time parsing, formatting, and arithmetic.

**Table** (`table.f`) is a generic fixed-stride slot allocator used internally by the router, DOM, and other modules that need indexed collections without heap allocation.

---

## Usage

Load any module with a single `REQUIRE` — dependencies resolve automatically:

```forth
REQUIRE akashic/math/vec2.f        \ pulls in fp16.f, fp16-ext.f, trig.f
REQUIRE akashic/audio/synth.f      \ pulls in pcm.f, osc.f, env.f, filter.f, …
REQUIRE akashic/web/server.f       \ pulls in request.f, response.f, router.f, …
```

Every file guards against double-loading with `PROVIDED`:

```forth
\ At the top of vec2.f:
REQUIRE fp16-ext.f
REQUIRE trig.f
PROVIDED akashic-vec2
```

If `akashic-vec2` has already been provided, subsequent `REQUIRE` calls are no-ops.

---

## Conventions

### Naming

Every module claims a unique uppercase prefix. Public API words use the prefix directly; internal helpers add a leading underscore:

| Module | Public prefix | Internal prefix |
|--------|---------------|-----------------|
| vec2 | `V2-` | `_V2-` |
| HTTP client | `HTTP-` | `_HTTP-` |
| Web server | `SRV-` | `_SRV-` |
| Channels | `CHAN-` | `_CHAN-` |
| DOM | `DOM-` | `_DOM-` |
| Synth | `SYNTH-` | `_SY-` |
| FFT | `FFT-` | `_FFT-` |
| Compositing | `COMP-` | `_COMP-` |
| Rasterizer | `RAST-` | `_RST-` |
| SML | `SML-` | `_SML-` |
| UIDL | `UIDL-` | `_UDL-` |
| CBOR | `CBOR-` | `_CBOR-` |
| Session | `SESS-` | `_SES-` |

### Stack Effects

Every word has a stack-effect comment:

```forth
: V2-DOT  ( ax ay bx by -- dot )   …
: COMP-OVER  ( src dst -- result )  …
: CHAN-SEND  ( value channel -- )    …
```

### Error Handling

Modules that can fail follow a uniform pattern:

```forth
VARIABLE HTTP-ERR                   \ error code (0 = OK)
1 CONSTANT HTTP-E-DNS               \ numbered error constants
2 CONSTANT HTTP-E-CONNECT
: HTTP-FAIL       ( code -- )  HTTP-ERR ! ;
: HTTP-OK?        ( -- flag )  HTTP-ERR @ 0= ;
: HTTP-CLEAR-ERR  ( -- )       0 HTTP-ERR ! ;
```

### Descriptor Structs

Complex objects (surfaces, synth voices, channels, DOM nodes) use fixed-size descriptors with field accessor words that compute cell offsets:

```forth
\ Surface descriptor — 80 bytes (10 cells × 8 bytes):
\   +0  width   +8  height   +16 stride   +24 data-ptr   +32 clip-x  …

: S.WIDTH   ( surf -- addr )  ;          \ +0
: S.HEIGHT  ( surf -- addr )  8 + ;      \ +8
: S.DATA    ( surf -- addr )  24 + ;     \ +24
```

### Cursor-Based Parsing

All parsers (JSON, CSS, HTML, XML, URL, CBOR, TOML, YAML) operate on `( addr len )` pairs and advance through input using the standard `/STRING` idiom. No intermediate token lists are built — parsing is single-pass and streaming.

### Vectored I/O

Socket and I/O operations go through execution-token (`XT`) variables. The default XT points to the real KDOS system call; tests can substitute a mock:

```forth
VARIABLE SOCKET-SEND-XT
' REAL-SEND SOCKET-SEND-XT !       \ default: real socket send
' MOCK-SEND SOCKET-SEND-XT !       \ test: substitute mock
```

This pattern is used throughout `net/` and `web/` so the server and HTTP client can be exercised without real network access.

### Internal Layering

Source files are internally organized into numbered layers with comment banners:

```forth
\ =====================================================================
\  Layer 0 — Constants and Variables
\ =====================================================================

\ =====================================================================
\  Layer 1 — Internal Helpers
\ =====================================================================

\ =====================================================================
\  Layer 2 — Public API
\ =====================================================================
```

---

## Documentation

Every source file has a corresponding Markdown document in [docs/](docs/), organized in the same directory structure as `akashic/`. A typical doc file runs 250–400 lines and includes:

- A one-line summary and dependency tree
- A table of design principles
- Memory layout diagrams for descriptor structs
- Word-by-word API reference tables with stack effects and descriptions
- Constants and error code tables
- An internals section explaining non-obvious algorithms
- A cookbook section with usage examples

For example, `docs/audio/synth.md` documents biquad filter coefficient formulas, `docs/render/surface.md` diagrams the 80-byte surface descriptor, and `docs/concurrency/channel.md` walks through the `CHAN-SELECT` algorithm step by step.

---

## Assets

The [assets/fonts/](assets/fonts/) directory ships three freely licensed TrueType fonts used by the font and render pipelines:

| Font | License |
|------|---------|
| Roboto-Regular.ttf | Apache License 2.0 (Google) |
| DejaVuSans.ttf | Bitstream Vera License |
| DejaVuSansMono.ttf | Bitstream Vera License |

See [assets/fonts/README.md](assets/fonts/README.md) for full license details.

---

## Requirements

**KDOS / Megapad-64** with its 64-bit Forth environment. No external toolchain, cross-compiler, or build system is needed — all 100 source files are plain Forth, loaded at runtime via `REQUIRE`.
