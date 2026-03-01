# Akashic — Deep Narrative Report

> Structured notes across 40 source files and 90 doc files.  
> Intended as raw material for writing a deeply narrative README.

---

## 1. Architecture & Module Map

Akashic is a **comprehensive Forth standard library** for KDOS / Megapad-64, a 64-bit Forth system running on custom hardware with a 512-bit tile engine.  The library is organized into **16 module directories** containing **~80 Forth source files** and accompanied by **90 Markdown documentation files** that mirror the source tree.

### Module Dependency Spine

```
utils/string.f                            ← foundation: every module uses this
    ├── math/fp16.f → fp16-ext.f → trig.f → fft.f → simd.f → stats.f → ...
    ├── markup/core.f → html.f → xml.f
    │       ├── dom/dom.f → css/css.f → css/bridge.f
    │       ├── sml/core.f → sml/tree.f
    │       └── liraq/uidl.f
    ├── net/url.f → uri.f → headers.f → http.f → ws.f
    │       └── atproto/xrpc.f → session.f → repo.f
    ├── web/server.f → router.f → middleware.f → template.f
    ├── audio/pcm.f → osc.f → env.f → synth.f → fm.f → seq.f → ...
    ├── render/surface.f → draw.f → composite.f → layout.f → paint.f → dom2bmp.f
    ├── font/ttf.f → raster.f → cache.f
    ├── text/utf8.f → layout.f
    ├── cbor/cbor.f → dag-cbor.f
    ├── concurrency/event.f → channel.f → rwlock.f → semaphore.f
    └── liraq/state-tree.f → lel.f → uidl.f → lcf.f → profile.f
```

### Loading Convention

Every file uses `REQUIRE path.f` / `PROVIDED module-name` for dependency management.  `REQUIRE` is idempotent — the `PROVIDED` guard prevents double-loading.  Files use relative paths (`REQUIRE ../math/fp16.f`).  No external toolchain is needed; everything is plain Forth source loaded at runtime.

### Layered Internal Organization

Source files are internally organized into numbered layers marked by comment banners:

- **Layer 0** — Constants, error codes, buffer declarations
- **Layer 1** — Low-level primitives (scanning, byte manipulation)
- **Layer 2** — Mid-level helpers (parsing, allocation)
- **Layer 3** — High-level API (public words)
- **Layer 4** — Integration / pipeline words

This pattern is consistent across web, render, dom, css, markup, and font modules.

### Memory Model

KDOS provides four distinct memory regions:

| Region | Typical Size | Used For |
|--------|-------------|----------|
| **Dictionary** | ~256 KiB | Forth word headers, compiled code, VARIABLEs, CREATEd tables |
| **Heap** | ~94 KiB | ALLOCATE/FREE dynamic storage (HTTP buffers, JSON scratch) |
| **XMEM** (extended) | 14+ MiB | Arena-backed DOM, surface pixel buffers, large allocations |
| **HBW** (high-bandwidth) | Special | 64-byte aligned SIMD tile buffers, FFT arrays, math scratch |

Arenas enable O(1) bulk teardown — a single `ARENA-DESTROY` frees an entire DOM document with all its nodes, attributes, and string pool.

---

## 2. Math Library

**26 files.** The math module is the largest in Akashic and forms the arithmetic foundation for audio, render, color, statistics, and AI-adjacent workloads.

### Numeric Tower

| Representation | Width | Role | Files |
|---|---|---|---|
| **FP16** (IEEE 754 half) | 16-bit | Pervasive: audio samples, trig, coordinates, SIMD lanes | `fp16.f`, `fp16-ext.f` |
| **FP32** (software) | 32-bit | Accumulation, regression coefficients, state-tree floats | `fp32.f` |
| **Fixed-point** (16.16) | 32-bit | Round/floor/ceil in LEL, KDOS epoch arithmetic | `fixed.f` |
| **Integer** | 64-bit | DOM layout (pixel coords), channel indices, counters | native |

FP16 is the workhorse — 10-bit mantissa, 5-bit exponent, 1-bit sign.  The library works around its limited precision through careful strategies: FP32 accumulators for sums, on-the-fly twiddle factors in FFT (avoiding error accumulation), and mixed-precision pipelines in regression.

### SIMD — 512-bit Tile Engine (`simd.f`, 554 lines)

The Megapad-64 tile engine is a 512-bit (64-byte) SIMD unit with six element-width modes controlled by the TMODE CSR (`0x14`):

| Mode | Lanes | Use Cases |
|------|------:|-----------|
| U8 / I8 | 64 | Pixel channel math, compositing |
| U16 / I16 | 32 | Audio PCM, FP16 bitwise |
| U32 / I32 | 16 | Intermediate accumulation |
| U64 / I64 | 8 | Large counters |
| FP16 | 32 | Bulk math, DSP, statistics |
| BF16 | 32 | ML-adjacent workloads |

TMODE bits: EW[2:0] for width, [4] signed, [5] saturating, [6] rounding.

**Two API layers:**
- **`TILE-` prefix** (mode-agnostic): caller sets mode, then calls TILE-ADD, TILE-MUL, TILE-DOT, etc.  Raw hardware instructions: TADD, TSUB, TMUL, TWMUL, TFMA, TMAC, TEMIN, TEMAX, TAND, TOR, TXOR, TABS, TSUM, TMIN, TMAX, TSUMSQ, TDOT, TMINIDX, TMAXIDX, TL1, TPOPCNT.
- **`SIMD-` prefix** (FP16 convenience): auto-sets FP16-MODE, provides add/sub/mul/fma/mac/min/max/abs/neg/scale/dot/sum/sumsq/rmin/rmax/argmin/argmax/l1norm/popcnt/clamp/fill/zero/copy/load2d/store2d.

Reductions collapse all lanes into a scalar via the hardware accumulator register (`ACC@`).  Eight scratch tiles (512 bytes in HBW) are available.  Strided 2D load/store enables row-major matrix access.

### FFT (`fft.f`, ~500 lines)

Radix-2 Cooley-Tukey in FP16.  In-place decimation-in-time.  Bit-reversal permutation.  Twiddle factors computed on-the-fly via `TRIG-SINCOS` to avoid FP16 accumulation drift.  Includes a workaround for a TRIG-REDUCE bug with negative angles: `cos(-x) = cos(x)`, `sin(-x) = -sin(x)`.

- `FFT-FORWARD`, `FFT-INVERSE` (+ 1/N scaling)
- `FFT-MAGNITUDE` (√(re² + im²)), `FFT-POWER`
- `FFT-CONVOLVE`, `FFT-CORRELATE` via frequency domain (allocate temp arrays with HBW-ALLOT)

### Bézier Curves (`bezier.f`, ~310 lines)

FP16 quadratic and cubic Bézier primitives.  De Casteljau evaluation.  Flatness tests (L∞ norm, chord deviation).  **Iterative adaptive flattening** using an explicit work stack (256 cells) — this avoids return-stack overflow that would occur with recursive subdivision.  Callback-driven: an XT receives (x0 y0 x1 y1) line segments.

### Color Spaces (`color.f`, ~600 lines)

FP16 color-space conversions: RGB↔HSL (sector-based H), RGB↔HSV, sRGB↔linear gamma (threshold 0.04045, exponent 2.4 via `EXP-POW`).  Luminance via Rec. 709 coefficients (0.2126R + 0.7152G + 0.0722B).  WCAG contrast ratio.  Per-channel LERP.  Alpha premultiply.  Porter-Duff "over" blend.  Pack/unpack RGBA8888 (clamp→×255→round).  FP16 constants are stored as raw hex: `0x2930` = 0.04045, `0x4A76` = 12.92, `0x32CE` = 0.2126.

### Statistics & Regression (`stats.f`, `regression.f`, `advanced-stats.f`, `probability.f`)

OLS linear regression with a **mixed-precision SIMD pipeline**: FP16 input arrays → SIMD deviation → FP32 coefficients.  64-byte context (8 FP32 cells).  Steps: means → deviations → Sxx/Sxy/Syy → slope = Sxy/Sxx → R² = Sxy²/(Sxx·Syy) → SSE = Syy − slope·Sxy.  Batch prediction via SIMD-SAXPY-N.  Residuals, RMSE, MAE, adjusted R².

### Time Series (`timeseries.f`, ~724 lines)

SMA (sliding FP32 sum, O(n)), EMA, EWMA, WMA (linear weights), median filter.  First differences via SIMD-SUB-N, k-th order differences.  Percentage change, log return.  Cumulative sum/min/max.  Detrend via OLS.  Autocorrelation.  Rolling std, drawdown, max drawdown.  Z-score normalization, outlier detection (IQR, z-score threshold).

### Other Math Files

| File | Purpose |
|------|---------|
| `trig.f` | Sin/cos/tan via CORDIC or polynomial approximation |
| `vec2.f` | 2D vector operations (FP16) |
| `mat2d.f` | 2×3 affine transform matrices |
| `exp.f` | Exponential, logarithm, power functions |
| `interp.f` | Linear, cosine, cubic interpolation |
| `filter.f` | DSP biquad filters, low/high/band-pass |
| `sort.f` | Sorting algorithms for FP16 arrays |
| `rect.f` | Axis-aligned rectangle operations |
| `accum.f` | FP32 Kahan-style accumulator |
| `counting.f` | Combinatorics: factorial, binomial, permutation |
| `sha256.f`, `sha512.f` | Cryptographic hash functions |

---

## 3. Audio Synthesis

**16 files.** A complete audio synthesis and sequencing toolkit.

### Signal Path

```
Oscillators (osc.f)           FM Operators (fm.f)
    │ 5 waveforms                 │ 2-op / 4-op
    │ 48-byte descriptors         │ 4 algorithms
    ▼                             ▼
Subtractive Synth (synth.f)   FM Synthesis (fm.f)
    │ Dual oscillator             │ Self-feedback on op1
    │ RBJ biquad filter           │ Per-operator ADSR
    │ Filter envelope (1×–4×)     │
    ▼                             ▼
Effects Chain (fx.f)          Mixer (mix.f)
    │                             │
    ▼                             ▼
PCM Buffers (pcm.f)
    │ FP16 samples
    ▼
WAV Codec (wav.f)  /  MIDI Sequencer (seq.f + midi.f)
```

### Oscillators (`osc.f`, ~230 lines)

Five waveforms: sine, square, sawtooth, triangle, pulse (variable duty cycle).  48-byte descriptors with phase accumulator model.  Phase increment = frequency × 2π / sample_rate.  `OSC-FILL` writes a buffer, `OSC-ADD` mixes in additively.

### Subtractive Synthesizer (`synth.f`, ~330 lines)

Dual oscillator → resonant biquad → amplitude ADSR.  RBJ cookbook Direct Form II Transposed.  Three filter modes: LP, HP, BP.  Filter envelope modulates cutoff: f_c' = f_c × (1 + env_level × 3), giving 1×–4× sweep.  Cent-based detuning for OSC2.  72-byte voice descriptors with save/restore for polyphony.

### FM Synthesis (`fm.f`, ~370 lines)

Two-operator and four-operator FM.  Four algorithms: serial, parallel, 3-chain, parallel-mod.  Per-operator ADSR, self-feedback on operator 1.  Phase modulation formula: effective_phase = carrier_phase + modulator_output × modulation_index.  Sample-by-sample rendering into FP16 PCM buffers.

### Sequencer (`seq.f`, ~350 lines)

Pattern-based step sequencer.  64 steps max.  Callback-driven: note-on/note-off/velocity/gate via execution tokens.  Swing support (odd steps delayed).  Sample-accurate tick boundaries.  Loop and one-shot modes.

### Other Audio Files

| File | Purpose |
|------|---------|
| `env.f` | ADSR envelope generator |
| `pcm.f` | PCM buffer primitives (FP16 samples, mono/stereo) |
| `lfo.f` | Low-frequency oscillator for modulation |
| `noise.f` | White/pink noise generators |
| `fx.f` | Audio effects (delay, reverb, chorus, distortion) |
| `mix.f` | Multi-channel mixer |
| `poly.f` | Polyphonic voice allocator |
| `pluck.f` | Karplus-Strong physical string model |
| `porta.f` | Portamento (pitch glide) |
| `chain.f` | Signal chain patching |
| `wav.f` | WAV file encode/decode |
| `midi.f` | MIDI message parsing |

---

## 4. Render Pipeline

**10 files.** A full 2D rendering pipeline from surfaces to compositing to layout to DOM-to-bitmap.

### Pipeline Flow

```
Surface (surface.f)  ←  pixel storage, RGBA8888
    ▼
Draw (draw.f)        ←  line, rect, circle, flood-fill
    ▼
Composite (composite.f) ← Porter-Duff, blend modes
    ▼
Box Model (box.f)    ←  CSS box-tree construction
    ▼
Layout (layout.f)    ←  CSS 2.1 block + inline flow
    ▼
Line Breaking (line.f) ← run-based text splitting
    ▼
Paint (paint.f)      ←  box tree → surface pixels
    ▼
DOM2BMP (dom2bmp.f)  ←  HTML string → BMP file (end-to-end)
```

### Surfaces (`surface.f`, ~568 lines)

RGBA8888 pixel buffers.  80-byte descriptors holding width, height, stride, data pointer, clip rectangle.  XMEM-backed for large canvases.  `SURF-BLIT` (opaque copy), `SURF-BLIT-ALPHA` (alpha-blended copy).  Sub-surface creation for region-of-interest operations.

### Compositing (`composite.f`, ~380 lines)

Full Porter-Duff algebra: over, in, out, atop, xor.  Plus blend modes.  **Integer-only channel math** — the key optimization: `(a × b + 128) >> 8` for fast premultiplied-alpha blending with no floating point.  Bulk scanline operations for row-at-a-time compositing.  Monochrome bitmap blitting for glyph rendering (used by font rasterizer output).

### Layout Engine (`layout.f`, ~750 lines)

CSS 2.1 normal flow: block formatting context and inline formatting context.  All positions and dimensions are **integer pixels**.

Algorithm:
1. Text measurement pre-pass (TTF advance widths via `text/layout.f`)
2. Width resolution: auto → fill containing block; percentage → resolve against parent
3. Classify children: all-inline → inline formatting context; any-block → block context
4. Block children: collapse vertical margins, set Y positions, recurse
5. Inline children: build LINE-RUN arrays, break into lines, align (left/center/right), map back to boxes
6. Height resolution: auto → sum of children

Margin collapsing follows CSS 2.1: both positive → max; both negative → min (most negative); mixed → sum.

### DOM-to-BMP (`dom2bmp.f`, ~130 lines)

End-to-end HTML → BMP pipeline in one word:

```forth
S" <h1>Hello</h1><p>World</p>" 320 240 D2B-RENDER
```

Steps: parse HTML → build DOM → apply CSS → construct box tree → run layout → paint to surface → encode BMP.

### Image Codecs

- `bmp.f` — BMP encoder/decoder
- `qoi.f` — QOI (Quite OK Image) encoder/decoder

---

## 5. Web Server

**6 files.** A complete HTTP web application framework.

### Architecture (6 Layers)

```
Layer 5: Application (user words)
Layer 4: Template Engine (template.f) — {{var}} expansion + HTML DSL
Layer 3: Middleware Pipeline (middleware.f) — FIFO chain, up to 16
Layer 2: Route Dispatch (router.f) — pattern matching with :param capture
Layer 1: Server Core (server.f) — accept loop, parse, dispatch, close
Layer 0: Transport (vectored XT socket ops for testability)
```

### Server (`server.f`, ~250 lines)

Vectored socket operations (`_SRV-XT-OPEN`, `_SRV-XT-RECV`, `_SRV-XT-SEND`, `_SRV-XT-CLOSE`) enable test injection without real sockets.  `SRV-HANDLE` does: recv → parse request → route dispatch → send response → close.  CATCH-based error handling wraps every request cycle.

### Router (`router.f`, ~200 lines)

Linear-scan route table: 64 slots × 40 bytes (method + pattern + handler XT).  Segment-by-segment pattern matching with `:param` capture (up to 8 params).  Convenience words: `ROUTE-GET`, `ROUTE-POST`, `ROUTE-PUT`, `ROUTE-DELETE`.

### Middleware (`middleware.f`, ~170 lines)

FIFO chain, max 16 entries.  Each middleware receives `next-xt` — call it to proceed, or don't to short-circuit.  Recursive chain execution via a vectored forward reference.  Built-in: `MW-LOG` (request logging), `MW-CORS` (CORS headers), `MW-JSON-BODY` (Content-Type: application/json).

### Template Engine (`template.f`, ~230 lines)

Dual approach:
1. **Compositional HTML words** — `<html`, `<body`, `<h1`, `</h1>`, etc. that build HTML into an output buffer
2. **Micro-templates** — `{{name}}` variable expansion (16 vars max, 4KB output buffer)

---

## 6. Network Client

**6 files.** HTTP/1.1 client and WebSocket client.

### HTTP Client (`http.f`, ~600 lines)

Full HTTP/1.1 client with:
- **8-slot DNS cache** — avoids redundant lookups
- **TCP/TLS abstraction** — vectored socket XTs for testing
- **Chunked transfer decoding** — streaming chunk parsing
- **Session headers** — persistent `Authorization: Bearer` for API calls
- **Redirect following** — up to 5 redirects (301/302/307/308)
- `HTTP-GET`, `HTTP-POST`, `HTTP-POST-JSON`

### WebSocket Client (`ws.f`, ~600 lines)

Full RFC 6455 implementation:
- **Inline SHA-1** — for computing `Sec-WebSocket-Accept` during handshake (no separate crypto module needed)
- **Frame encode/decode** — with 4-byte XOR masking (client frames must be masked per spec)
- **Auto-pong** — automatically responds to ping frames
- **Fragment reassembly** — reconstructs fragmented messages
- **Full handshake** — Sec-WebSocket-Key generation and Accept validation

### Other Net Files

| File | Purpose |
|------|---------|
| `url.f` | URL parsing (scheme, host, port, path, query, fragment) |
| `uri.f` | General URI parsing (superset of URL) |
| `headers.f` | HTTP header collection (set/get/iterate, max 32 headers) |
| `base64.f` | Base64 encode/decode |

---

## 7. DOM / CSS / Markup

### DOM (`dom.f`, ~1218 lines)

**Arena-backed Document Object Model.**  Each document lives in a single KDOS arena — `ARENA-DESTROY` frees everything at once (nodes, attributes, strings).

Memory layout per document:
```
┌─────────────────────────────────┐
│  Document Descriptor (80 bytes) │
├─────────────────────────────────┤
│  Node Slab (80 × max-nodes)     │  free-list managed
├─────────────────────────────────┤
│  Attr Slab (24 × max-attrs)     │  free-list managed
├─────────────────────────────────┤
│  String Region (remaining)      │  bump-allocated, refcounted
└─────────────────────────────────┘
```

Node layout: 80 bytes (10 cells): type, flags, parent, first-child, last-child, next-sib, prev-sib, name (string handle), aux (string handle for text content), attrs.  Doubly-linked child lists for O(1) append, prepend, detach.  Five node types: element, text, comment, document, fragment.

Tree operations: `DOM-APPEND`, `DOM-PREPEND`, `DOM-DETACH`, `DOM-INSERT-BEFORE`, `DOM-CHILD-COUNT`.  Attribute records: 24 bytes (name handle + value handle + next pointer).  Case-insensitive string comparison for HTML5 compatibility.

HTML parser: `DOM-PARSE-HTML` builds a DOM tree from HTML text, void-element aware, entity-decoding.  CSS integration via `akashic-css-bridge`.

### CSS (`css.f`, ~1719 lines)

The largest single file in Akashic.  CSS tokenizer and declaration parser:

- **Layer 0**: Character classification, string scanning, comment scanning (`/* ... */`)
- **Layer 1**: Token-level scanning — identifiers (with backslash escapes), balanced `{...}` blocks, balanced `(...)` groups, CSS-SKIP-UNTIL (respects strings, comments, nested blocks)
- **Layer 2**: Declaration parsing — property:value pairs, specificity calculation
- **Layer 3**: Selector matching — compound selectors with type, class, ID, attribute selectors

### CSS Bridge (`bridge.f`, ~200 lines)

Connects DOM and CSS: compound selector matching against DOM nodes, style collection from all matching rules, inline style merging with highest specificity.  `BRIDGE-RESOLVE-STYLE` takes a DOM node and returns the applicable CSS declarations.

### Markup Core (`markup/core.f`, ~854 lines)

Shared XML/HTML parsing infrastructure.  Three-layer architecture:

- **Layer 0 — Scanning**: skip-ws, skip-until/past-ch, name-char?, skip/get-name, skip/get-quoted
- **Layer 1 — Tag classification**: 7 types (text, open, close, self-close, comment, PI, CDATA, DOCTYPE).  `MU-TAG-TYPE` uses multi-byte peek for `<!--`, `<![CDATA[`, `<!DOCTYPE`, `<?`, `</`
- **Layer 2 — Tag scanning**: skip-tag (handles quoted attrs), skip-comment (`-->`), skip-PI (`?>`), skip-CDATA (`]]>`)
- **Layer 3 — Attributes**: `MU-ATTR-NEXT` (iterates name=value pairs), `MU-ATTR-FIND` (searches by name)

### HTML5 Reader (`markup/html.f`, ~629 lines)

HTML5-specific vocabulary built on markup/core.f:
- **Void element table**: 14 entries (area, base, br, col, embed, hr, img, input, link, meta, param, source, track, wbr) — case-insensitive matching
- **Raw text elements**: script/style with special content scanning
- **Navigation**: `HTML-ENTER`, `HTML-TEXT`, `HTML-INNER`, `HTML-CHILD`, `HTML-ATTR`, `HTML-EACH-CHILD`
- **Entity decoding**: ~30 named HTML entities (nbsp, copy, reg, trade, mdash, ndash, lsquo, rsquo, ldquo, rdquo, bull, hellip, euro, rarr, larr, times, divide, para, sect, deg, plusmn, micro, middot, and more)
- **Class matching**: `HTML-CLASS-HAS?` does space-delimited word matching

---

## 8. Font & Text

### TrueType Parser (`font/ttf.f`, ~512 lines)

Parses TrueType font files in memory:
- **Table directory**: reads head, maxp, hhea, hmtx, loca, glyf, cmap
- **Cmap format 4**: segment mapping for BMP characters (segCount, startCode, endCode, idDelta, idRangeOffset)
- **Simple glyphs**: flag-based coordinate decoding (on-curve/off-curve, repeat flags, delta decoding)
- **Composite glyphs**: component-based glyphs with translation offsets
- **Metrics**: per-glyph advance width, left-side bearing from hmtx; global ascender/descender/lineGap from hhea

### Glyph Rasterizer (`font/raster.f`, ~734 lines)

Three rasterization modes:
1. **Basic even-odd fill**: fast, aliased
2. **N×N supersampled AA**: configurable quality (2×2, 4×4, 8×8)
3. **Analytic fractional coverage**: sub-pixel accuracy

Outline processing: Bézier contour flattening (using `bezier.f`), scanline intersection, fill-rule application.  Gamma correction LUT for perceptually correct AA.

### Glyph Cache (`font/cache.f`)

Caches rasterized glyph bitmaps to avoid re-rasterization.

### Text Layout (`text/layout.f`, ~200 lines)

Scales font units to pixels: pixel_size × font_units / UPEM.  Character width: `TTF-CMAP-LOOKUP` → `TTF-ADVANCE` → scale.  String width by iterating UTF-8 codepoints.  Vertical metrics: ascender, descender, line-height.

Word-wrap line iterator: `LAY-WRAP-WIDTH!` sets wrap width, `LAY-WRAP-INIT` starts, `LAY-WRAP-LINE` yields next line.  Handles hard newlines (0x0A), space-based breaks, forced mid-word breaks (guarantees ≥1 char per line).

### UTF-8 (`text/utf8.f`, ~200 lines)

Full codec: decode (1–4 byte sequences, continuation byte validation, overlong/surrogate/out-of-range checks, U+FFFD replacement on error), encode (1–4 bytes).  `UTF8-LEN` (codepoint count), `UTF8-VALID?`, `UTF8-NTH` (0-based codepoint access).

---

## 9. SML — Sequential Markup Language

**2 files** (`sml/core.f` ~600 lines, `sml/tree.f`).

SML is a **modality-neutral 1D document format** for user interfaces.  Where HTML targets visual 2D layout, SML targets sequential navigation — screen readers, game pad UIs, CLIs, voice interfaces, or any single-dimensional flow.

### Element Vocabulary (25 elements, 6 categories)

| Category | Elements | Role |
|----------|----------|------|
| **Envelope** | `sml`, `head` | Document root and metadata container |
| **Meta** | `title`, `meta`, `link`, `style`, `cue-def` | Document metadata, style, audio cue definitions |
| **Scope** | `seq`, `ring`, `gate`, `trap` | Navigation containers with different traversal rules |
| **Position** | `item`, `act`, `val`, `pick`, `ind`, `tick`, `alert` | Focusable/interactive elements |
| **Struct** | `announce`, `shortcut`, `hint`, `gap`, `lane` | Structural markers and assistant content |
| **Compose** | `frag`, `slot` | Component composition primitives |

### Scope Kinds

The four scope types define how cursor navigation wraps or locks:
- **seq** — linear (cursor stops at ends)
- **ring** — circular (cursor wraps from last to first)
- **gate** — locked until a condition is met (disabled navigation)
- **trap** — sticky (must explicitly exit, e.g., modal dialogs)

### Content Model & Validation

`SML-VALID?` performs streaming validation: walks the document once with a parent-type stack (max depth 16), checking that every element appears in a valid parent context.  The content model validation matrix (`SML-VALID-CHILD?`) defines which element categories can nest where.

### `val` Element Kinds

The `<val>` element supports four input kinds: text, range, toggle, display — validated at parse time via `kind=` attribute checking.

### `pick` Element

`<pick>` presents a set of choices.  The `choices=` attribute uses pipe-separated values, and `SML-PICK-COUNT` counts them.

---

## 10. LIRAQ UI Framework

**5 files.** LIRAQ is a reactive UI framework built atop SML, providing state management, expression-driven data binding, and declarative UI descriptions.

### State Tree (`liraq/state-tree.f`, ~1031 lines)

**Arena-backed hierarchical key-value store.**  The heart of LIRAQ's reactivity.

Structure:
- **96-byte nodes** (12 cells): type, name (addr+len), value cells, parent/child/sibling pointers, child count
- **128-byte descriptor** (16 cells): arena ref, root node, free-list head, node count, string pool pointers, journal pointers
- **7 value types**: string, integer, boolean, null, float (FP32), array, object
- **Dot-separated path navigation**: `ST-NAVIGATE` splits on `.`, descends through objects by name or arrays by index
- **Free-list node allocation**, bump-only string pool

Operations:
- **CRUD**: `ST-SET-PATH-INT/BOOL/STR/FLOAT/NULL`, `ST-GET-PATH`, `ST-DELETE-PATH`
- **Arrays**: `ST-ENSURE-ARRAY`, `ST-ARRAY-APPEND-INT/STR`, `ST-ARRAY-COUNT`, `ST-ARRAY-NTH`, `ST-ARRAY-REMOVE`
- **Protected paths**: underscore prefix (`_scratch`) → `ST-F-PROTECTED` flag
- **Circular journal**: 128 entries × 72 bytes, 4 source tags (DCS, binding, behavior, runtime) — enables undo/audit

### LEL — LIRAQ Expression Language (`liraq/lel.f`, ~1639 lines)

**Pure, total, deterministic formula evaluator** for UIDL data bindings.  This is the second-largest file in Akashic.

Totality guarantee: every expression produces a value.  Division by zero → 0, missing paths → null, type mismatches → coerced or 0/''/false.

Architecture:
- **Lexer**: 26 token types, character-by-character scanning, string literals with `''` escaping, number scanning (integer + float with FP32 construction)
- **Parser**: Pratt parser (top-down operator precedence) with 7 precedence levels, replacing the original recursive-descent parser via the `_XT-EXPR` forward-reference variable
- **Evaluator**: fused with the parser — each parse rule immediately evaluates, pushing results onto a 48-entry × 3-cell value stack
- **Mutual recursion**: `_XT-EXPR` and `_XT-SKIP` are VARIABLE-held execution tokens, resolved at runtime to allow forward references between expression and skip parsers
- **Extension hook**: `_XT-DISPATCH-EXT` allows registering additional built-in functions after core compilation

**48 built-in functions across 6 categories:**
- **Arithmetic** (13): add, sub, mul, div, mod, neg, abs, round, floor, ceil, min, max, clamp
- **Comparison** (7): eq, neq, gt, gte, lt, lte, not
- **Logic** (4): if, and, or, coalesce — all short-circuit (skip unevaluated branches)
- **String** (13): concat (variadic), length, upper, lower, trim, substring, contains, starts-with, ends-with, replace, split, join, format
- **Array** (5): at, first, last, includes, reverse
- **Type** (6): to-string, to-number, to-boolean, is-null, type-of, literal

**Infix operators** (Pratt parser, 7 precedence levels):
```
? :  (ternary, lowest)  <  or  <  and  <  == !=  <  > >= < <=  <  + -  <  * / %  <  not - (prefix, highest)
```

**State tree integration**: bare identifiers resolve as dot-separated paths against the state tree.  `_item` and `_index` are special context variables for collection template iteration.

**Type coercion**: automatic float promotion (either operand float → FP32 result), truthy/falsy semantics (null/0/0.0/''/false are falsy), string↔number↔boolean conversions.

**Computed values**: `_ST-LEL-COMPUTE` links LEL evaluation to the state tree's `_ST-COMPUTE-XT` for reactive computed properties.

### UIDL — Universal Interface Description Language (`liraq/uidl.f`, ~982 lines)

**Declarative semantic UI format.**  Parses UIDL XML documents into a static-pool element tree.

Pool sizes:
- 256 elements × 128 bytes = 32 KiB
- 512 attributes × 40 bytes = 20 KiB
- String pool: 12 KiB

16 semantic element types: region, group, separator, meta, label, media, symbol, canvas, action, input, selector, toggle, range, collection, table, indicator.  Plus 4 pseudo-types: uidl (root), template, empty, rep.

6 arrangement modes: dock, flex, stack, flow, grid, none.

**FNV-1a ID hash table**: 256 slots with linear probing for O(1) element lookup by ID.

**Data binding**: `bind=` attribute with LEL expression (leading `=` stripped).  `when=` for conditional visibility.  Two-way binding flag for interactive elements (input, selector, toggle, range).

**Collection rendering**: `<collection>` with `<template>`, `<empty>`, and `<rep>` pseudo-elements.  Template rendering iterates state-tree arrays, setting `_item`/`_index` context for LEL.

### Other LIRAQ Files

| File | Purpose |
|------|---------|
| `lcf.f` | Layout Configuration — maps UIDL arrangement modes to layout parameters |
| `profile.f` | Performance profiling instrumentation |

---

## 11. Concurrency

**4 files.** Go-style CSP concurrency primitives built on KDOS hardware spinlocks.

### Events (`concurrency/event.f`)

The foundation primitive.  32-byte descriptors with signaled/reset state.  `EVENT-WAIT` blocks until signaled; `EVENT-SIGNAL` wakes all waiters; `EVENT-RESET` clears the signal.  Built on KDOS hardware spinlocks (numbered 0–7).

### Channels (`concurrency/channel.f`, ~350 lines)

**Go-style bounded channels.**  120-byte fixed header + inline circular data buffer.

```forth
6 1 CELLS 8 CHANNEL work-queue   \ 6 slots, cell-sized elements, spinlock #8
```

Features:
- Per-channel hardware spinlock for the critical section
- Two embedded events: not-full, not-empty
- **Blocking**: `CHAN-SEND` / `CHAN-RECV` (wait on events)
- **Non-blocking**: `CHAN-TRY-SEND` / `CHAN-TRY-RECV` (return flag)
- **Buffer-based**: `CHAN-SEND-BUF` / `CHAN-RECV-BUF` for arbitrary element sizes (via CMOVE)
- **Select**: `CHAN-SELECT` polls N channels round-robin, returns (channel-index value) or (-1 0) if all closed+empty
- **Close**: `CHAN-CLOSE` wakes all blocked waiters; send on closed channel THROWs -1; recv on closed empty channel returns 0

### Reader-Writer Locks (`concurrency/rwlock.f`, ~220 lines)

88-byte descriptors with embedded read-event and write-event.

```forth
0 RWLOCK my-lock   \ uses hardware spinlock #0
```

- Multiple concurrent readers OR one exclusive writer
- `READ-LOCK` / `READ-UNLOCK`: if last reader, pulses write-event
- `WRITE-LOCK` / `WRITE-UNLOCK`: pulses both events
- **RAII**: `WITH-READ` / `WITH-WRITE` using CATCH for exception safety — guarantees unlock even on THROW

### Semaphores (`concurrency/semaphore.f`)

Counting semaphore with wait/signal semantics.

---

## 12. CBOR & AT Protocol

### CBOR (`cbor/cbor.f`, ~350 lines)

RFC 8949 subset.  No floating-point support (integers, strings, arrays, maps, booleans, tags only).

**Encoder**: stateful output buffer (`CBOR-RESET`), big-endian emit helpers (1/2/4/8 bytes), automatic argument size selection (0/1/2/4/8 extra bytes based on value).
- `CBOR-UINT`, `CBOR-NINT`, `CBOR-BSTR`, `CBOR-TSTR`, `CBOR-ARRAY`, `CBOR-MAP`, `CBOR-TAG`, `CBOR-TRUE`, `CBOR-FALSE`, `CBOR-NULL`

**Decoder**: cursor-based (CBOR-PARSE sets input), `CBOR-TYPE` peeks major type, `CBOR-NEXT-*` consumes items.  Strings return pointers into the input buffer (**zero-copy**).  `CBOR-SKIP` recursively skips nested structures.

### DAG-CBOR (`cbor/dag-cbor.f`, ~150 lines)

DAG-CBOR for AT Protocol / IPLD (InterPlanetary Linked Data):
- `DCBOR-CID` encodes CID links as `tag(42) + byte-string with 0x00 identity multibase prefix`
- **Canonical key ordering validation**: shorter keys first, then lexicographic
- `DCBOR-SORT-MAP` validates key order on decoded maps (no duplicates allowed)

### AT Protocol Stack (6 files)

A complete Bluesky / AT Protocol client:

| File | Purpose |
|------|---------|
| `session.f` (~130 lines) | JWT session management: `SESS-LOGIN` (createSession), `SESS-REFRESH` (refreshSession), bearer token setting |
| `xrpc.f` (~180 lines) | XRPC client: URL builder (`https://<host>/xrpc/<nsid>`), query parameters, cursor pagination (128-byte cursor buffer) |
| `repo.f` (~200 lines) | Repository CRUD: `REPO-GET`, `REPO-CREATE`, `REPO-PUT`, `REPO-DELETE` — manual JSON building via ASCII char codes (34 for `"`) since KDOS lacks `S\"` |
| `aturi.f` | AT URI parser + builder: `at://authority/collection/rkey` |
| `did.f` | DID validation (did:plc: and did:web:) |
| `tid.f` | TID generation (base32-sort encoded 64-bit timestamps) |

Token storage: accessJwt (512B), refreshJwt (512B), DID (128B).  Default PDS host: `bsky.social`.

---

## 13. Utilities

**6 files.** Foundational data formats and string handling.

| File | Purpose |
|------|---------|
| `string.f` | String utilities: comparison (STR-STR=), case conversion, trimming, searching, starts/ends-with |
| `json.f` | JSON reader/builder: streaming token parser with path extraction |
| `toml.f` | TOML parser: key-value tables, sections |
| `yaml.f` | YAML parser: basic subset |
| `datetime.f` | Date/time operations: epoch conversion, formatting |
| `table.f` | Generic key-value table data structure |

`string.f` is the most-depended-upon file in the entire library — virtually every module requires it.  JSON is critical for AT Protocol and web APIs.

---

## 14. Cross-Cutting Patterns

### Naming Convention

- **`PREFIX-`** for public API words: `SRV-` (server), `HTTP-` (HTTP client), `ST-` (state tree), `SIMD-` (SIMD), `SML-` (SML), etc.
- **`_PREFIX-`** for internal helpers: `_SRV-`, `_HTTP-`, `_ST-`, `_LEL-`, etc.
- Constants: `PREFIX-CONST-NAME` (e.g., `SYNTH-FILT-LP`, `SML-T-SCOPE`)
- Queries: `PREFIX-THING?` (e.g., `SML-SCOPE?`, `DID-VALID?`)
- Field accessors: computed cell offsets (e.g., `N.TYPE`, `N.FLAGS`, `SN.FCHILD`)

### Vectored I/O (Testability)

Socket and I/O operations go through **execution-token (XT) VARIABLEs**, allowing test injection:

```forth
VARIABLE _SRV-XT-OPEN    ' TCP-OPEN  _SRV-XT-OPEN !   \ production
VARIABLE _SRV-XT-RECV    ' TCP-RECV  _SRV-XT-RECV !
\ For testing:
' MOCK-OPEN _SRV-XT-OPEN !
' MOCK-RECV _SRV-XT-RECV !
```

This pattern appears in: `web/server.f`, `net/http.f`, `net/ws.f`.

### Forward References (Mutual Recursion)

Since Forth requires definition before use, mutual recursion is achieved via VARIABLE-held XTs:

```forth
VARIABLE _XT-EXPR   \ forward reference to expression parser
: _LEL-FUNCALL ... _XT-EXPR @ EXECUTE ... ;
: _LEL-EXPR-IMPL ... _LEL-FUNCALL ... ;
' _LEL-EXPR-IMPL _XT-EXPR !   \ wire it up
```

Used in: LEL (expr ↔ skip ↔ funcall), CSS parser, SML validator.

### Cursor-Based Parsing

All parsers operate on `( addr len )` pairs, advancing through input with the standard `/STRING` idiom:

```forth
1 /STRING   \ advance by 1 byte: ( addr+1 len-1 )
```

This zero-copy approach means parsed values are pointers into the original input buffer.  Used everywhere: markup, CSS, HTTP, JSON, TOML, YAML, URL, URI, base64.

### Error Handling Patterns

1. **`VARIABLE XXX-ERR`** with numeric codes: readable via `XXX-ERR @`, clearable via `XXX-CLEAR-ERR` or `0 XXX-ERR !`
2. **`ABORT"`** for fatal conditions: `ABORT" DOM node pool exhausted"`
3. **`THROW`/`CATCH`** for recoverable errors: web server wraps each request in CATCH, rwlocks use CATCH for RAII cleanup
4. **Return-code words**: `XXX-OK?` (flag), `XXX-FAIL` (store code)

### Descriptor Structs

Complex objects use fixed-size descriptors with field accessor words computing cell offsets (8 bytes per cell on 64-bit KDOS):

```forth
: N.TYPE       ;          \ +0
: N.FLAGS      8 + ;      \ +8
: N.PARENT    16 + ;      \ +16
```

This is Akashic's "struct" idiom — no special struct syntax, just offset arithmetic.

### VARIABLE-Based State

Most modules use module-scoped VARIABLEs for scratch state rather than complex stack gymnastics.  Trade-off: not re-entrant, but simpler code.  Multi-document support (DOM) uses a "current document" pattern (`DOM-USE` / `DOM-DOC`).

### Memory Allocation Hierarchy

1. **Static pools** — UIDL (256 elems × 128B), string pools with bump allocation
2. **Free-list slabs** — DOM nodes (80B), DOM attrs (24B), state-tree nodes (96B)
3. **Arena bulk allocate** — ARENA-ALLOT for contiguous regions, ARENA-DESTROY for O(1) teardown
4. **Heap** — ALLOCATE/FREE for dynamic buffers (HTTP response bodies)
5. **XMEM** — Extended memory for large pixel buffers (surfaces)
6. **HBW** — High-bandwidth math RAM for 64-byte aligned SIMD tiles

---

## 15. Notable Numbers

### Descriptor Sizes

| Object | Bytes | Cells | Module |
|--------|------:|------:|--------|
| DOM Node | 80 | 10 | dom.f |
| DOM Attribute | 24 | 3 | dom.f |
| DOM Document | 80 | 10 | dom.f |
| State-tree Node | 96 | 12 | state-tree.f |
| State-tree Descriptor | 128 | 16 | state-tree.f |
| State-tree Journal Entry | 72 | 9 | state-tree.f |
| UIDL Element | 128 | 16 | uidl.f |
| UIDL Attribute | 40 | 5 | uidl.f |
| Oscillator | 48 | 6 | osc.f |
| Synth Voice | 72 | 9 | synth.f |
| Surface | 80 | 10 | surface.f |
| Channel Header | 120 | 15 | channel.f |
| RWLock | 88 | 11 | rwlock.f |
| Event | 32 | 4 | event.f |
| Route Entry | 40 | 5 | router.f |
| Regression Context | 64 | 8 | regression.f |
| SIMD Tile | 64 | n/a | simd.f (512-bit) |

### Pool & Buffer Limits

| Pool | Capacity | Module |
|------|----------|--------|
| UIDL elements | 256 | uidl.f |
| UIDL attributes | 512 | uidl.f |
| UIDL string pool | 12 KiB | uidl.f |
| UIDL ID hash table | 256 slots | uidl.f |
| Route table | 64 routes | router.f |
| Middleware chain | 16 entries | middleware.f |
| Template variables | 16 vars | template.f |
| Template output buffer | 4 KiB | template.f |
| DNS cache | 8 slots | http.f |
| HTTP redirect limit | 5 | http.f |
| HTTP headers | 32 per collection | headers.f |
| Route :param captures | 8 parameters | router.f |
| LEL value stack | 48 entries × 3 cells | lel.f |
| LEL scratch buffer | shared with state-tree | lel.f |
| XRPC URL buffer | 512 bytes | xrpc.f |
| XRPC cursor buffer | 128 bytes | xrpc.f |
| JWT access token | 512 bytes | session.f |
| JWT refresh token | 512 bytes | session.f |
| DID buffer | 128 bytes | session.f |
| State-tree journal | 128 entries | state-tree.f |
| SML validator depth | 16 levels | sml/core.f |
| Bézier work stack | 256 cells | bezier.f |
| SIMD scratch tiles | 8 × 64 bytes (HBW) | simd.f |
| Sequencer steps | 64 max | seq.f |
| HTML void elements | 14 entries | html.f |
| HTML named entities | ~30 entries | html.f |
| SML elements | 25 (6 categories) | sml/core.f |

### File Size Extremes

| Rank | File | Lines | Subject |
|------|------|------:|---------|
| 1 | `css/css.f` | 1,719 | CSS tokenizer + parser |
| 2 | `liraq/lel.f` | 1,639 | LEL expression evaluator |
| 3 | `dom/dom.f` | 1,218 | Document Object Model |
| 4 | `liraq/state-tree.f` | 1,031 | Reactive state tree |
| 5 | `liraq/uidl.f` | 982 | UIDL declarative UI parser |
| 6 | `markup/core.f` | 854 | Markup scanning core |
| 7 | `render/layout.f` | 750 | CSS layout engine |
| 8 | `math/timeseries.f` | 724 | Time series analysis |
| 9 | `font/raster.f` | 734 | Glyph rasterizer |
| 10 | `markup/html.f` | 629 | HTML5 reader |

### Module File Counts

| Module | Files | Total Focus |
|--------|------:|-------------|
| math/ | 26 | Arithmetic, SIMD, crypto, statistics, DSP |
| audio/ | 16 | Synthesis, sequencing, effects, codecs |
| render/ | 10 | 2D graphics, layout, compositing |
| net/ | 6 | HTTP client, WebSocket, URL/URI |
| web/ | 6 | HTTP server, routing, templates |
| atproto/ | 6 | Bluesky / AT Protocol |
| utils/ | 6 | JSON, strings, TOML, YAML, datetime, tables |
| liraq/ | 5 | UI framework (state, expressions, UIDL) |
| concurrency/ | 4 | Channels, events, locks, semaphores |
| markup/ | 3 | XML/HTML parsing |
| font/ | 3 | TrueType, rasterizer, cache |
| text/ | 2 | UTF-8, text layout |
| sml/ | 2 | Sequential Markup Language |
| cbor/ | 2 | CBOR / DAG-CBOR |
| dom/ | 1 | Document Object Model |
| css/ | 2 | CSS parser + bridge |
| **Total** | **~100** | |

---

*Report generated from source reading of 40+ Forth files and 90 documentation files in the Akashic repository.*
