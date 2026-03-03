# Audio, Sound Sources & Sonification — Roadmap (v2)

A general-purpose audio toolkit for KDOS / Megapad-64, covering
synthesis, effects, mixing, analysis, sequencing, I/O, and codecs,
extended by three higher-level layers that go all the way from raw
algorithms to data made audible:

- **Synthesis primitives** (`audio/syn/`) — the raw methods, named by
  technique.  Modal, membrane, resonant filter bank, additive partial,
  sustained oscillator bank, granular.  These are algorithms, not
  instruments.  The same modal engine that produces a bell also produces
  a steel plate, a Tibetan bowl, a glass harmonica, or something with
  no physical referent at all.

- **Sound sources** (`audio/src/`) — the large, rich library of
  algorithmically defined, continuously parameterizable sound objects.
  Divided into families: acoustic instruments, natural/environmental,
  electronic/abstract, industrial/mechanical, tonal drones.  Each
  source is a descriptor whose physical or perceptual parameters can be
  set to any value, modulated by data, rendered live or pre-rendered
  into a cache.  Musical instruments are one family here — not the
  whole thing, not even most of it.

- **Palette system** (`audio/palette/`) — a way to group sound sources
  into a coherent aesthetic identity, register them by semantic role,
  and swap the entire aesthetic without changing the code that uses it.
  What `math/color.f` does for color schemes, palettes do for sound.

- **Sonification** (`audio/sonify/`) — systematic mappings from data
  dimensions to auditory dimensions.  Native auditory forms — not
  visual metaphors translated to sound.  Stream, trigger, pulse,
  texture, ensemble, interval, alert, earcon.  These forms consume a
  palette; the same code produces completely different sound when the
  palette changes.

The system is designed as a standalone peer to `render/` and `math/`,
not tied to any particular UI paradigm.  Games, music tools, media
players, accessibility engines, creative coding, scientific
audification, real-time monitoring — all are first-class use cases.

---

## Table of Contents

- [Current State — What We Already Have](#current-state--what-we-already-have)
- [Architecture Overview](#architecture-overview)
- [Tiers 1–6 — Audio Core (existing)](#tiers-16--audio-core-existing)
- [Tier 7 — Synthesis Primitives](#tier-7--synthesis-primitives)
  - [7.1 audio/syn/modal.f — Inharmonic Partial Synthesis](#71-audiosynmodalf--inharmonic-partial-synthesis)
  - [7.2 audio/syn/membrane.f — Membrane + Noise Model](#72-audiosynmembranef--membrane--noise-model)
  - [7.3 audio/syn/resonator.f — Resonant Filter Bank](#73-audiosynresonatorf--resonant-filter-bank)
  - [7.4 audio/syn/additive.f — Harmonic Additive Synthesis](#74-audiosynadditivef--harmonic-additive-synthesis)
  - [7.5 audio/syn/sustained.f — Sustained Oscillator Bank](#75-audiosynsustained--sustained-oscillator-bank)
  - [7.6 audio/syn/granular.f — Granular Synthesis](#76-audiosyngranularf--granular-synthesis)
- [Tier 8 — Sound Sources](#tier-8--sound-sources)
  - [The Source Contract](#the-source-contract)
  - [8.1 audio/src/acoustic.f — Acoustic Instruments](#81-audiosrcacousticf--acoustic-instruments)
  - [8.2 audio/src/natural.f — Natural / Environmental](#82-audiosrcnaturalf--natural--environmental)
  - [8.3 audio/src/electronic.f — Electronic / Abstract](#83-audiosrcelectronicf--electronic--abstract)
  - [8.4 audio/src/industrial.f — Industrial / Mechanical](#84-audiosrcindustrialf--industrial--mechanical)
  - [8.5 audio/src/drones.f — Tonal Drones & Pads](#85-audiosrcdronesf--tonal-drones--pads)
  - [8.6 audio/src/cache.f — Source Render Cache](#86-audiosrccachef--source-render-cache)
- [Tier 9 — Palette System](#tier-9--palette-system)
  - [9.1 audio/palette/palette.f — Palette Definition & Registry](#91-audiopalettepalettef--palette-definition--registry)
  - [9.2 audio/palette/acoustic.f — Acoustic Palette](#92-audiopaletteacousticf--acoustic-palette)
  - [9.3 audio/palette/electronic.f — Electronic Palette](#93-audiopaletteelectronicf--electronic-palette)
  - [9.4 audio/palette/natural.f — Natural Palette](#94-audiopaletttenaturalf--natural-palette)
  - [9.5 audio/palette/industrial.f — Industrial Palette](#95-audiopaletteindustrialf--industrial-palette)
- [Tier 10 — Sonification](#tier-10--sonification)
  - [Why Native Auditory Forms](#why-native-auditory-forms)
  - [10.1 audio/sonify/param-map.f — Dimension Mapping](#101-audiosonifyparam-mapf--dimension-mapping)
  - [10.2 audio/sonify/stream.f — Continuous Data → Evolving Sound](#102-audiosonifystreamf--continuous-data--evolving-sound)
  - [10.3 audio/sonify/trigger.f — Discrete Events → Strikes](#103-audiosonifytriggerf--discrete-events--strikes)
  - [10.4 audio/sonify/pulse.f — Rate Data → Rhythmic Pulse](#104-audiosonifypulsef--rate-data--rhythmic-pulse)
  - [10.5 audio/sonify/texture.f — Aggregates → Ambient Soundscape](#105-audiosonifytexturef--aggregates--ambient-soundscape)
  - [10.6 audio/sonify/ensemble.f — Multi-Variate → Polyphonic Layers](#106-audiosonifyensemblef--multi-variate--polyphonic-layers)
  - [10.7 audio/sonify/interval.f — Relationships → Harmonic Intervals](#107-audiosonifyintervalf--relationships--harmonic-intervals)
  - [10.8 audio/sonify/alert.f — Threshold Monitor → Escalating Cues](#108-audiosonifyalertf--threshold-monitor--escalating-cues)
  - [10.9 audio/sonify/earcon.f — Semantic Audio Tokens](#109-audiosonifyearconf--semantic-audio-tokens)
  - [10.10 audio/sonify/scene.f — Multi-Form Composition](#1010-audiosonifyscenef--multi-form-composition)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Design Decisions](#design-decisions)
- [Testing Strategy](#testing-strategy)

---

## Current State — What We Already Have

### KDOS Built-Ins

| Facility | Words | Audio Relevance |
|---|---|---|
| **Ring Buffers (§18)** | `RING`, `RING-PUSH`, `RING-POP`, `RING-PEEK`, `RING-FULL?`, `RING-EMPTY?`, `RING-COUNT` | Streaming pipeline, delay lines, all circular buffers in effects |
| **Tile Engine (MEX)** | `TSUM`, `TADD`, `TSUB`, `TMUL`, `TDOT`, `TMIN`, `TMAX`, `TSUMSQ`, `TABS` | 32 FP16 samples per op — bulk DSP accelerator |
| **FP16 Buffer Ops** | `F.SUM`, `F.DOT`, `F.SUMSQ`, `F.ADD`, `F.MUL`, `BF.SUM`, `BF.DOT` | SIMD audio arithmetic |
| **HBW Math RAM** | `HBW-ALLOT`, `HBW-TALIGN`, `HBW-RESET` — 3 MiB BRAM | Hot buffers: delay lines, wavetables, active PCM |
| **External RAM** | `XMEM-ALLOT`, `XMEM-FREE-BLOCK`, `XBUF` | Cold storage: WAV files, sample libraries, source cache |
| **Hardware Timer** | `TIMER!`, `TIMER-CTRL!`, `TIMER-ACK` — 32-bit compare-match IRQ | Sample-accurate ISR-driven playback |
| **Scheduler (§8)** | `TASK`, `SPAWN`, `BG`, `YIELD`, `PREEMPT-ON/OFF` | Background audio thread |
| **Multicore (§8.1)** | `CORE-RUN`, `CORE-WAIT`, `BARRIER`, IPI | Dedicated audio core |
| **Heap** | `ALLOCATE` / `FREE` / `RESIZE` | Dynamic descriptors |
| **Disk / MP64FS** | `FWRITE`, `FREAD`, `FSEEK`, `OPEN` | WAV files, patch banks |

### Akashic Libraries (existing)

| Library | File | Lines |
|---|---|---|
| akashic-audio-pcm | `audio/pcm.f` | 662 ✅ |
| akashic-fft | `math/fft.f` | 481 ✅ |
| akashic-filter | `math/filter.f` | 500 ✅ |
| akashic-timeseries | `math/timeseries.f` | 724 ✅ |
| akashic-trig | `math/trig.f` | ~200 ✅ |
| akashic-interp | `math/interp.f` | ~200 ✅ |
| akashic-fp16 | `math/fp16.f` + `fp16-ext.f` | ~600 ✅ |
| akashic-simd | `math/simd.f` + `simd-ext.f` | ~400 ✅ |

### Audio Core (built, Tiers 1–6)

| Module | File | Lines |
|---|---|---|
| PCM buffers | `audio/pcm.f` | ~350 ✅ |
| Oscillators | `audio/osc.f` | ~420 ✅ |
| Envelopes | `audio/env.f` | ~300 ✅ |
| Noise | `audio/noise.f` | ~200 ✅ |
| LFO | `audio/lfo.f` | ~250 ✅ |
| Effects | `audio/fx.f` | ~1100 ✅ |
| Mixer | `audio/mix.f` | ~350 ✅ |
| Effect chain | `audio/chain.f` | ~200 ✅ |
| Subtractive synth | `audio/synth.f` | ~450 ✅ |
| FM synthesis | `audio/fm.f` | ~400 ✅ |
| Karplus-Strong | `audio/pluck.f` | ~200 ✅ |
| Polyphony | `audio/poly.f` | ~250 ✅ |
| Portamento | `audio/porta.f` | ~150 ✅ |
| WAV codec | `audio/wav.f` | 363 ✅ |
| Step sequencer | `audio/seq.f` | 352 ✅ |
| MIDI | `audio/midi.f` | 371 ✅ |
| Wavetable LUT | `audio/wavetable.f` | ~150 ✅ |
| PCM SIMD ops | `audio/pcm-simd.f` | ~200 ✅ |
| FFT reverb | `audio/fft-reverb.f` | ~430 ✅ |

---

## Architecture Overview

```
audio/
├── pcm.f              PCM buffer abstraction (DONE)
├── osc.f / noise.f / env.f / lfo.f       (DONE — Tier 1)
├── fx.f / mix.f / chain.f                (DONE — Tier 2)
├── analysis.f                            (Tier 3)
├── synth.f / fm.f / pluck.f              (DONE — Tier 4)
├── poly.f / porta.f                      (DONE — Tier 4b)
├── wav.f / seq.f / midi.f                (DONE — Tier 5)
├── speaker.f / mic.f                     (Tier 6)
│
├── syn/                       ── Synthesis primitives ── (Tier 7)
│   ├── modal.f        Inharmonic partial synthesis engine
│   ├── membrane.f     Membrane model (tone sweep + noise)
│   ├── resonator.f    Resonant filter bank (noise-excited)
│   ├── additive.f     Harmonic additive synthesis engine
│   ├── sustained.f    Sustained oscillator bank (drones, pads)
│   └── granular.f     Granular synthesis (grain scheduler)
│
├── src/                       ── Sound sources ── (Tier 8)
│   ├── acoustic.f     Acoustic instruments (bell, gong, drum, etc.)
│   ├── natural.f      Natural/environmental (wind, rain, fire, etc.)
│   ├── electronic.f   Electronic/abstract (blip, sweep, crunch, etc.)
│   ├── industrial.f   Industrial/mechanical (click, clank, hiss, etc.)
│   ├── drones.f       Tonal drones and pads
│   └── cache.f        Source render cache (LRU, pitch-shift lookup)
│
├── palette/                   ── Palette system ── (Tier 9)
│   ├── palette.f      Palette definition, registry, selection API
│   ├── acoustic.f     Built-in acoustic palette (bells, wood, etc.)
│   ├── electronic.f   Built-in electronic palette
│   ├── natural.f      Built-in natural palette
│   └── industrial.f   Built-in industrial palette
│
└── sonify/                    ── Data → sound ── (Tier 10)
    ├── param-map.f    Data dimension → auditory dimension
    ├── stream.f       Ordered data → evolving sound
    ├── trigger.f      Discrete events → source strikes
    ├── pulse.f        Rate data → rhythmic pulse
    ├── texture.f      Statistical aggregates → ambient soundscape
    ├── ensemble.f     Multi-variate → polyphonic layers
    ├── interval.f     Value relationships → harmonic intervals
    ├── alert.f        Threshold monitoring → escalating cues
    ├── earcon.f       Semantic audio tokens (palette-driven)
    └── scene.f        Multi-form composition
```

### Prefix Conventions

| Module | Prefix |
|---|---|
| syn/modal.f | `MODAL-` |
| syn/membrane.f | `MEMB-` |
| syn/resonator.f | `RESON-` |
| syn/additive.f | `ADD-` |
| syn/sustained.f | `SUST-` |
| syn/granular.f | `GRAN-` |
| src/acoustic.f | `ACOU-` |
| src/natural.f | `NAT-` |
| src/electronic.f | `ELEC-` |
| src/industrial.f | `INDUS-` |
| src/drones.f | `DRONE-` |
| src/cache.f | `SCACHE-` |
| palette/palette.f | `PAL-` |
| sonify/param-map.f | `PMAP-` |
| sonify/stream.f | `SSTREAM-` |
| sonify/trigger.f | `STRIG-` |
| sonify/pulse.f | `SPULSE-` |
| sonify/texture.f | `STEX-` |
| sonify/ensemble.f | `SENS-` |
| sonify/interval.f | `SINT-` |
| sonify/alert.f | `SALERT-` |
| sonify/earcon.f | `EAR-` |
| sonify/scene.f | `SSCENE-` |

---

## Tiers 1–6 — Audio Core (existing)

(See existing roadmap — all of Tiers 1–6 are built and passing tests.
Tier 3 analysis.f and Tier 6 speaker/mic are the remaining pieces.)

---

## Tier 7 — Synthesis Primitives

The raw methods, named by technique.  Each primitive is a low-level
engine that produces a PCM buffer given a descriptor.  These are not
sound sources.  They don't know what a bell is.  They don't know what
rain is.

The point: a bell uses the modal engine.  So does a steel plate.  So
does a fictional material with partial ratios that don't correspond to
any physical object.  The engine is general.  A sound source (Tier 8)
is a specific set of parameters fed to an engine, plus a physical or
aesthetic interpretation.

Every synthesis primitive follows the same low-level contract:
- A descriptor struct holds all engine state
- `*-CREATE ( ... rate -- desc )` allocates the descriptor
- `*-FREE ( desc -- )` frees it
- `*-RENDER ( buf desc -- )` fills a PCM buffer given current parameters
- Parameters are FP16 fields accessible via setter words

### 7.1 audio/syn/modal.f — Inharmonic Partial Synthesis

```
PROVIDED akashic-syn-modal
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-env
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-fp16
```

The engine behind any struck or plucked sound where the partials
don't follow simple integer multiples.  Metals, glasses, ceramics,
wood slabs, membranes, fictional materials — all live here.

**What it computes:** N sinusoidal partials summed together.  Each
partial has a frequency (expressed as a ratio to a fundamental),
an amplitude, and a decay rate (expressed in seconds for −60 dB).
Higher partials typically decay faster; this ratio controls the
"brightness over time" character of the sound.

The initial excitation can optionally include a brief burst of
band-passed white noise (the "strike transient" — the click at
the top of a bell hit) that blends into the modal decay.

**Descriptor layout** (variable size — base 10 cells + 3 cells per
partial):

| Field | Description |
|-------|-------------|
| n-partials | Number of partials (1–32 typical) |
| fundamental | Base frequency Hz (FP16) |
| brightness | Strike energy in high partials 0.0–1.0 (FP16) |
| damping | Global decay multiplier 0.0–2.0 (FP16) — >1 = slower |
| noise-ms | Strike transient noise duration in ms (0 = none) |
| noise-bw | Strike transient noise bandwidth (FP16) |
| rate | Sample rate Hz |
| partials | Array: [freq-ratio, amp, decay-sec] per partial, FP16 |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `MODAL-CREATE` | `( n-partials rate -- desc )` | Allocate modal descriptor |
| `MODAL-FREE` | `( desc -- )` | Free |
| `MODAL-FUND!` | `( freq desc -- )` | Set fundamental |
| `MODAL-PARTIAL!` | `( ratio amp decay-sec i desc -- )` | Set partial i |
| `MODAL-LOAD-TABLE` | `( table n desc -- )` | Load N partials from a packed FP16 table |
| `MODAL-BRIGHTNESS!` | `( brightness desc -- )` | Set strike energy in high partials |
| `MODAL-DAMPING!` | `( damping desc -- )` | Set global decay multiplier |
| `MODAL-NOISE!` | `( ms bw desc -- )` | Set strike transient noise |
| `MODAL-STRIKE` | `( velocity desc -- buf )` | Render a single strike, return PCM |
| `MODAL-STRIKE-INTO` | `( buf velocity desc -- )` | Render, add into existing buffer |
| `MODAL-DURATION` | `( desc -- ms )` | Estimated audible duration at current damping |

**Built-in partial-ratio tables (constants, dictionary-resident):**

| Name | Ratios (first 6) | Character |
|------|-------------------|-----------|
| `MODAL-TBL-BRONZE` | 1.0 2.0 2.76 5.40 8.93 11.34 | Warm bell, typical bronze |
| `MODAL-TBL-STEEL` | 1.0 2.32 3.18 5.87 9.41 13.02 | Bright, hard, metallic bell |
| `MODAL-TBL-GLASS` | 1.0 2.67 4.18 7.50 12.33 15.80 | Crisp, fast-decaying upper partials |
| `MODAL-TBL-TUBULAR` | 1.0 2.76 5.40 8.93 13.34 18.64 | Tubular chime — spread spectrum |
| `MODAL-TBL-CROTALE` | 1.0 3.0 6.0 10.0 15.0 21.0 | Small tuned disc, nearly harmonic |
| `MODAL-TBL-BOWL` | 1.0 2.63 4.79 7.41 10.49 14.03 | Singing bowl — close spacing |
| `MODAL-TBL-SLAB` | 1.0 1.58 2.42 3.52 4.88 6.49 | Flat stone or wooden slab |
| `MODAL-TBL-ABSTRACT-A` | 1.0 1.41 2.24 3.16 4.47 5.62 | No physical referent |
| `MODAL-TBL-ABSTRACT-B` | 1.0 3.73 7.11 12.2 19.0 27.4 | Spread, bell-like but alien |

Any of these can be scaled, transposed, or morphed.  None of them
mean "this must be a bell" — they're just FP16 ratio arrays.

### 7.2 audio/syn/membrane.f — Membrane + Noise Model

```
PROVIDED akashic-syn-membrane
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-noise
REQUIRE  akashic-audio-env
REQUIRE  akashic-audio-pcm
```

A two-component model: a tonal body (sine sweep — the membrane's
fundamental mode, initially over-excited and relaxing downward) mixed
with a noise component (bandpass-filtered stick/mallet impact and
upper modes).  The balance between tone and noise, the sweep range,
and the noise filter define the character completely.

This engine is neutral.  It doesn't know about drums.  It produces
"a sound with a tonal sweep and a noise burst."  A kick drum,
a war drum, a hand drum, a sci-fi impact, and a deep industrial thump
are all just different parameters.

**Descriptor layout** (12 cells = 96 bytes):

| Field | Description |
|-------|-------------|
| freq-start | Tone sweep start Hz (FP16) |
| freq-end | Tone sweep end Hz (FP16) |
| sweep-ms | Duration of sweep in ms |
| tone-decay-ms | Tonal component decay time |
| tone-amp | Tone amplitude 0.0–1.0 (FP16) |
| noise-color | 0=white, 1=pink — noise source |
| noise-lo | Noise bandpass low Hz (FP16, 0 = lowpass) |
| noise-hi | Noise bandpass high Hz (FP16, 0 = hipass) |
| noise-decay-ms | Noise component decay time |
| noise-amp | Noise amplitude 0.0–1.0 (FP16) |
| rate | Sample rate Hz |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `MEMB-CREATE` | `( rate -- desc )` | Allocate membrane descriptor (all params at defaults) |
| `MEMB-FREE` | `( desc -- )` | Free |
| `MEMB-TONE!` | `( start-hz end-hz sweep-ms decay-ms desc -- )` | Set tonal component |
| `MEMB-NOISE!` | `( lo-hz hi-hz decay-ms desc -- )` | Set noise component bandpass + decay |
| `MEMB-MIX!` | `( tone-amp noise-amp desc -- )` | Set blend |
| `MEMB-STRIKE` | `( velocity desc -- buf )` | Render a strike |
| `MEMB-STRIKE-INTO` | `( buf velocity desc -- )` | Render, add into buffer |

### 7.3 audio/syn/resonator.f — Resonant Filter Bank

```
PROVIDED akashic-syn-resonator
REQUIRE  akashic-audio-noise
REQUIRE  akashic-math-filter
REQUIRE  akashic-audio-pcm
```

White or pink noise pushed through a bank of resonant bandpass
filters.  Sustained sound.  The filters set the spectral character;
the noise provides the excitation.

Makes convincing: wind through structures, breath-driven instruments,
textured drones, cave ambience, steam, electrical hum, alien tones,
swarm sounds.  The character shifts completely based on filter
center frequencies, Q values (sharpness), and whether the noise
is white or pink.

At the limit of many narrow-Q filters: modal-like pitched behavior.
At the limit of one broad filter: colored noise.  The range between
is vast.

**Descriptor layout** (8 cells base + 3 cells per filter pole):

| Field | Description |
|-------|-------------|
| n-poles | Number of filter bands (1–16) |
| noise-color | 0=white, 1=pink, 2=brown |
| excitation | How noise is applied: 0=continuous, 1=pulsed (blowing model) |
| intensity | Excitation intensity 0.0–1.0 (FP16) |
| rate | Sample rate Hz |
| poles | Array: [center-hz, Q, amp] per pole, FP16 |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `RESON-CREATE` | `( n-poles rate -- desc )` | Allocate resonator |
| `RESON-FREE` | `( desc -- )` | Free |
| `RESON-POLE!` | `( center-hz Q amp i desc -- )` | Set filter pole i |
| `RESON-NOISE!` | `( color intensity desc -- )` | Set noise color and level |
| `RESON-EXCITE!` | `( mode desc -- )` | 0=continuous, 1=pulsed |
| `RESON-RENDER` | `( buf desc -- )` | Fill buffer (call repeatedly for continuous output) |
| `RESON-BLOW!` | `( intensity desc -- )` | Modulate excitation intensity live |

### 7.4 audio/syn/additive.f — Harmonic Additive Synthesis

```
PROVIDED akashic-syn-additive
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-math-fft      \ for spectral morphing
```

Like modal, but the partial frequencies are constrained to integer
multiples of a fundamental (harmonic spectrum).  The amplitude
envelope of each harmonic can evolve independently over time,
enabling spectral morphing — the sound changes character while
sustaining.

Where modal is for struck objects (inharmonic, decaying), additive
is for sustained sounds whose spectrum you want to control precisely:
complex tones, evolving pads, voice-like formant synthesis, organ
tones with independent drawbar-like harmonic levels.

**Descriptor layout** (variable — base 8 cells + 3 cells per harmonic):

| Field | Description |
|-------|-------------|
| n-harmonics | Number of harmonics |
| fundamental | Base frequency Hz (FP16) |
| rate | Sample rate Hz |
| harmonics | Array: [amp-start, amp-end, morph-ms] per harmonic |

The morph fields allow each harmonic to independently fade or swell
over `morph-ms` milliseconds, making spectral animation possible.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `ADD-CREATE` | `( n-harmonics rate -- desc )` | Allocate |
| `ADD-FREE` | `( desc -- )` | Free |
| `ADD-FUND!` | `( freq desc -- )` | Set fundamental |
| `ADD-HARMONIC!` | `( amp i desc -- )` | Set harmonic i amplitude immediately |
| `ADD-MORPH!` | `( amp ms i desc -- )` | Set harmonic i to morph to amp over ms |
| `ADD-PRESET-SAW` | `( desc -- )` | Load sawtooth harmonic series (1/n amplitudes) |
| `ADD-PRESET-SQUARE` | `( desc -- )` | Load square wave series (odd harmonics, 1/n) |
| `ADD-PRESET-ORGAN` | `( desc -- )` | Load approximate pipe organ spectrum |
| `ADD-RENDER` | `( buf desc -- )` | Fill buffer, advance morphs |

### 7.5 audio/syn/sustained.f — Sustained Oscillator Bank

```
PROVIDED akashic-syn-sustained
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-noise
REQUIRE  akashic-audio-lfo
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-math-filter
```

A configurable bank of detuned oscillators run through a filter,
with optional noise mix and LFO modulation.  Produces everything from
pure sine drones to thick detuned pads to breathy evolving textures.
Continuous output — call `SUST-RENDER` in a loop.

Not a specific instrument.  A palette of smooth, sustained sounds
controlled by five perceptual dimensions:

| Dimension | Range | Auditory effect |
|-----------|-------|-----------------|
| brightness | 0.0–1.0 | Filter cutoff — dark velvet to bright glass |
| warmth | 0.0–1.0 | Harmonic content — pure sine to rich overtones |
| motion | 0.0–1.0 | LFO depth — static to shimmering/vibrating |
| density | 0.0–1.0 | Oscillator count + detune — thin to thick choir |
| breathiness | 0.0–1.0 | Noise mix — clean to airy to rough |

Any of these can be arrived at by data mapping.  A CO₂ reading can
directly control breathiness.  Temperature can control brightness.
Signal variance can control motion.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SUST-CREATE` | `( freq rate -- desc )` | Allocate bank, all params at neutral |
| `SUST-FREE` | `( desc -- )` | Free |
| `SUST-FREQ!` | `( freq desc -- )` | Set pitch (glides smoothly) |
| `SUST-BRIGHTNESS!` | `( v desc -- )` | Set brightness 0.0–1.0 |
| `SUST-WARMTH!` | `( v desc -- )` | Set warmth 0.0–1.0 |
| `SUST-MOTION!` | `( v desc -- )` | Set LFO depth 0.0–1.0 |
| `SUST-DENSITY!` | `( v desc -- )` | Set oscillator density 0.0–1.0 |
| `SUST-BREATHINESS!` | `( v desc -- )` | Set noise mix 0.0–1.0 |
| `SUST-MORPH` | `( target frames desc -- )` | Smoothly interpolate all params toward target descriptor |
| `SUST-RENDER` | `( buf desc -- )` | Fill buffer — continuous output |

### 7.6 audio/syn/granular.f — Granular Synthesis

```
PROVIDED akashic-syn-granular
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-audio-env
REQUIRE  akashic-audio-noise
```

Granular synthesis: rapid-fire micro-events ("grains") drawn from a
source PCM buffer (or generated from oscillators), each with its own
position, duration, pitch shift, pan, and amplitude envelope.  The
perceptual result is determined by the statistical distribution of
grain parameters — not by any individual grain.

Makes convincing: clouds of sound, swarms, dust, rainfall textures,
smeared melodic lines, stuttering effects, time-stretch without pitch
change, pitch shift without time change, textural evolution.

The density of grain scheduling (grains/second) is the primary
control knob.  Sparse scheduling (1–5/sec) → clearly separated events.
Dense scheduling (50+/sec) → continuous fused texture.

**Descriptor layout** (16 cells = 128 bytes):

| Field | Description |
|-------|-------------|
| source | PCM buffer to draw grains from (or 0 for oscillator grains) |
| density | Grains per second (FP16) |
| grain-ms | Grain duration in ms |
| position | Read position in source 0.0–1.0 (FP16) |
| pos-scatter | Position randomization 0.0–1.0 |
| pitch-shift | Pitch ratio 0.5–2.0 (FP16, 1.0 = unchanged) |
| pitch-scatter | Pitch randomization 0.0–1.0 |
| pan-scatter | Stereo pan randomization 0.0–1.0 |
| amp-scatter | Amplitude randomization 0.0–1.0 |
| envelope | Grain amplitude shape (0=hann, 1=trapezoidal, 2=gaussian) |
| rate | Sample rate Hz |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `GRAN-CREATE` | `( source-buf rate -- desc )` | Allocate granular descriptor |
| `GRAN-FREE` | `( desc -- )` | Free |
| `GRAN-SOURCE!` | `( buf desc -- )` | Swap source buffer |
| `GRAN-DENSITY!` | `( grains/sec desc -- )` | Set grain density |
| `GRAN-GRAIN!` | `( ms desc -- )` | Set grain duration |
| `GRAN-POSITION!` | `( pos-fp16 desc -- )` | Set read position 0.0–1.0 |
| `GRAN-PITCH!` | `( ratio desc -- )` | Set pitch shift |
| `GRAN-SCATTER!` | `( pos pitch pan amp desc -- )` | Set all scatter params |
| `GRAN-RENDER` | `( buf desc -- )` | Schedule and mix grains into buffer |

---

## Tier 8 — Sound Sources

Sound sources are specific, named, parameterizable kinds of sound.
They use Tier 7 synthesis primitives — a source is a set of parameters
plus a physical or aesthetic interpretation plus a name.

The naming and grouping into families matters because it makes palettes
(Tier 9) coherent.  A palette doesn't pick "a modal descriptor with
these partials" — it picks "bronze bell."  The user understands what
that means without being told.

But families don't constrain usage.  Nothing stops you from using a
"thunder" source (from natural.f) in a data sonification of network
packet loss.  Nothing stops you from using an "electronic blip" in a
performance piece alongside "bronze bells."  The families are for
discoverability and palette-building, not for enforcement.

### The Source Contract

Every sound source — regardless of family — implements the same
interface.  Sonification forms and palette machinery only know this
contract, not what's inside.

A **one-shot source** produces a finite PCM buffer from a single
excitation:

```
*-CREATE ( ... rate -- src )      Allocate + configure
*-FREE   ( src -- )               Free all resources
*-STRIKE ( velocity src -- buf )  Render one event, return PCM buf
*-PARAM! ( value param-id src -- ) Set named parameter
*-PARAM@ ( param-id src -- value ) Get named parameter
```

A **continuous source** renders indefinite output in blocks:

```
*-CREATE ( ... rate -- src )
*-FREE   ( src -- )
*-RENDER ( buf src -- )           Fill buffer, maintain state
*-PARAM! ( value param-id src -- )
*-PARAM@ ( param-id src -- value )
```

One-shot sources CAN be converted to continuous by auto-looping or
scheduling restrikes.  The cache (§8.6) works with both.

### 8.1 audio/src/acoustic.f — Acoustic Instruments

```
PROVIDED akashic-src-acoustic
REQUIRE  akashic-syn-modal
REQUIRE  akashic-syn-membrane
REQUIRE  akashic-audio-pluck
REQUIRE  akashic-audio-pcm
```

Struck, plucked, bowed, and blown instruments.  All acoustically
motivated — parameter names reference physical properties of real
instruments.  You know what "damping," "material," and "strike point"
mean without documentation.

All use Tier 7 engines.  All are continuously parameterizable.

**Percussion — struck and ringing:**

| Source | Engine | Physical parameters |
|--------|--------|---------------------|
| `ACOU-BELL` | modal | size, material (bronze/steel/glass/ceramic), strike-hardness, damping |
| `ACOU-GONG` | modal + bloom | size, thickness, strike-position (center/rim), damping |
| `ACOU-CHIME` | modal (tubular profile) | length, wall-thickness, strike-point |
| `ACOU-BOWL` | modal (bowl profile) | diameter, wall-thickness, fill-level (water damping) |
| `ACOU-CROTALE` | modal (crotale profile) | pitch, alloy |
| `ACOU-TRIANGLE` | modal | side-length, gauge, dampable |
| `ACOU-CYMBAL` | modal + noise | diameter, thickness, hammering, choke |
| `ACOU-RIDE` | modal + noise | size, bow/bell/edge strike-position |

**Percussion — membrane:**

| Source | Engine | Physical parameters |
|--------|--------|---------------------|
| `ACOU-KICK` | membrane | head-diameter, tuning, beater-hardness, porting |
| `ACOU-SNARE` | membrane | head-size, snare-tension, strike-position, rimshot |
| `ACOU-TOM` | membrane | diameter, depth, head-tension, resonant-head |
| `ACOU-HIHAT` | membrane (extreme noise) | hh-mass, foot-pressure (open→closed), chick-accent |
| `ACOU-CONGA` | membrane | head-size, slap/open/bass-tone modes |
| `ACOU-FRAME-DRUM` | membrane | diameter, depth, dampening-hand |
| `ACOU-TIMPANI` | membrane + pedal | head-diameter, tuning (pitch-accurate) |

**Plucked strings:**

| Source | Engine | Physical parameters |
|--------|--------|---------------------|
| `ACOU-PLUCK` | Karplus-Strong | string-length→pitch, decay, damping, pick-position |
| `ACOU-HARP-STRING` | Karplus-Strong + body | string-class, pluck-character |
| `ACOU-GUITAR-STRING` | Karplus-Strong | wound vs plain, pick-hardness |

**Blown:**

| Source | Engine | Physical parameters |
|--------|--------|---------------------|
| `ACOU-FLUTE` | resonator (blow-excited) | tube-length→pitch, blow-pressure, embouchure |
| `ACOU-CLARINET` | resonator + reed | tube-length, reed-stiffness, overblowing |

**API (example — bell):**

```forth
ACOU-BELL-SCRATCH CONSTANT P-BELL-SIZE
ACOU-BELL-SCRATCH CONSTANT P-BELL-MATERIAL
ACOU-BELL-SCRATCH CONSTANT P-BELL-STRIKE
ACOU-BELL-SCRATCH CONSTANT P-BELL-DAMPING

( rate -- src )
ACOU-BELL-CREATE

( velocity src -- buf )
ACOU-BELL-STRIKE

( value param-id src -- )
ACOU-BELL-PARAM!
```

All acoustic sources expose their physical parameter IDs as named
constants (`ACOU-*-SCRATCH`... naming convention TBD for param IDs).
The `PARAM!` / `PARAM@` interface is how palettes and sonification
forms modulate sources.

**Gong bloom** — unique to `ACOU-GONG`.  After the initial strike, a
slow spectral redistribution occurs: energy migrates from dominant
modes to neighboring modes, causing the characteristic swell.
Controlled by `bloom-rate` and `bloom-amount` parameters.

### 8.2 audio/src/natural.f — Natural / Environmental

```
PROVIDED akashic-src-natural
REQUIRE  akashic-syn-resonator
REQUIRE  akashic-syn-granular
REQUIRE  akashic-syn-membrane
REQUIRE  akashic-audio-noise
REQUIRE  akashic-audio-pcm
```

Sounds drawn from the physical world, not from music.  No instrument
connotations.  These are the sounds of environments, weather,
materials under stress, and fluid dynamics.

All are algorithmically generated — no recorded samples.  Parameters
correspond to physical quantities of the source phenomenon.

**One-shot events:**

| Source | Engine | Physical parameters |
|--------|--------|---------------------|
| `NAT-THUNDER` | membrane + modal tail | distance (delays onset), intensity, duration |
| `NAT-ROCK-IMPACT` | modal + membrane | mass, hardness, surface-type |
| `NAT-WATER-DRIP` | modal | drop-size, surface-tension, cavity-depth |
| `NAT-CRACK` | noise burst + reson | material (wood/ice/glass), thickness |
| `NAT-CRUNCH` | granular | material-coarseness, pressure, step-area |
| `NAT-GRAVEL-STEP` | granular | stone-size, density, footfall-weight |
| `NAT-BRANCH-SNAP` | modal + noise | diameter, moisture, bend-rate |
| `NAT-SPLASH` | granular + noise | volume, drop-height, surface |

**Continuous textures:**

| Source | Engine | Physical parameters |
|--------|--------|---------------------|
| `NAT-WIND` | resonator | speed (0=still→1=gale), turbulence, obstruction-type |
| `NAT-RAIN` | granular | intensity (drizzle→downpour), surface-type, drop-size |
| `NAT-FIRE` | granular + reson | intensity, fuel-type, crackling-rate |
| `NAT-STREAM` | granular + reson | flow-rate, turbulence, channel-width |
| `NAT-OCEAN` | granular + modal | wave-period, intensity, foam-level |
| `NAT-LEAVES` | granular | wind-speed, leaf-type, density |
| `NAT-INSECTS` | granular (high-density) | species-mix, density, temperature (pitch) |
| `NAT-CROWD` | granular | density, engagement-level, pitch-center |

**Parameter examples (NAT-RAIN):**

- `intensity`: 0.0 = inaudible mist, 0.3 = light shower, 0.7 = downpour, 1.0 = storm
- `surface-type`: 0 = soil, 0.33 = leaves, 0.66 = puddle, 1.0 = tin roof
- `drop-size`: controls grain duration and impact brightness

A data sonification mapping rainfall rate to `NAT-RAIN intensity` is
immediately and intuitively legible with zero explanation needed.

### 8.3 audio/src/electronic.f — Electronic / Abstract

```
PROVIDED akashic-src-electronic
REQUIRE  akashic-syn-sustained
REQUIRE  akashic-syn-additive
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-noise
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-math-filter
```

Sounds that have no acoustic or physical world referent.  Electronic
and synthetic in character.  The vocabulary of modular synthesis,
sound design, and electronic music — but parameterized and
data-drivable.

**One-shot:**

| Source | Engine | Parameters |
|--------|--------|------------|
| `ELEC-BLIP` | osc + env | freq, waveform (0=sine→3=pulse), duration, filter-brightness |
| `ELEC-PING` | osc + env | freq, resonance, decay |
| `ELEC-CLICK` | noise burst + HP | character (clean/dirty), duration |
| `ELEC-POP` | noise + LP env | body-freq, snap, decay |
| `ELEC-SWEEP` | osc + pitch env | start-freq, end-freq, duration, waveform |
| `ELEC-ZAP` | FM + env | carrier, ratio, index, decay |
| `ELEC-CHIME` | additive + env | freq, n-harmonics, harmonic-decay |
| `ELEC-PLUCK` | additive + fast-env | brightness, decay |
| `ELEC-THUMP` | osc sweep + env | sub-freq, sweep-speed, body |
| `ELEC-CRUNCH` | distorted noise | drive, filter-cutoff, duration |

**Continuous:**

| Source | Engine | Parameters |
|--------|--------|------------|
| `ELEC-DRONE` | sustained | freq, brightness, warmth, motion |
| `ELEC-HUM` | additive (60/50 Hz) | freq, harmonic-count, buzz-level |
| `ELEC-STATIC` | filtered noise | bandwidth, center-freq, level |
| `ELEC-PULSE-TRAIN` | osc | freq, duty, filter |
| `ELEC-PAD` | sustained (dense) | freq, density, brightness, breathiness |
| `ELEC-TEXTURE` | granular (synth grains) | density, pitch-scatter, brightness |

### 8.4 audio/src/industrial.f — Industrial / Mechanical

```
PROVIDED akashic-src-industrial
REQUIRE  akashic-syn-resonator
REQUIRE  akashic-syn-membrane
REQUIRE  akashic-syn-modal
REQUIRE  akashic-audio-noise
REQUIRE  akashic-audio-pcm
```

Machines, mechanisms, materials under stress.  The sounds of physical
processes: moving parts, pressure, friction, impact.  No "instrument"
frame — these sound like infrastructure, equipment, and process.

**One-shot:**

| Source | Engine | Parameters |
|--------|--------|------------|
| `INDUS-CLICK` | modal (hard contact) | surface-hardness, contact-area |
| `INDUS-CLANK` | modal (metal impact) | mass, surface, resonance |
| `INDUS-THUD` | membrane | mass, surface-compliance |
| `INDUS-RIVET` | impulse + modal | material, speed |
| `INDUS-BANG` | membrane + modal | pressure, enclosure |
| `INDUS-VALVE` | noise burst + HP | diameter, pressure |
| `INDUS-RELAY` | modal + click | contact-material, actuation-speed |

**Continuous:**

| Source | Engine | Parameters |
|--------|--------|------------|
| `INDUS-MOTOR` | resonator + periodic | rpm, load, number-of-cylinders |
| `INDUS-TURBINE` | resonator + granular | rpm, blade-count, load |
| `INDUS-HVAC` | resonator | flow-rate, duct-resonances |
| `INDUS-HISS` | HP filtered noise | pressure, aperture |
| `INDUS-BUZZ` | resonator (electrical) | freq (50/60 Hz), harmonic-content |
| `INDUS-GRIND` | granular | material-pair, pressure, rpm |
| `INDUS-SERVO` | additive (modulated) | load, speed, torque |

### 8.5 audio/src/drones.f — Tonal Drones & Pads

```
PROVIDED akashic-src-drones
REQUIRE  akashic-syn-sustained
REQUIRE  akashic-syn-additive
REQUIRE  akashic-audio-pcm
```

A focused collection of continuous tonal sounds for use as ambient
layers, backgrounds, tension, or data streams.  Built primarily from
`syn/sustained.f` and `syn/additive.f`.  Distinct from `ELEC-DRONE`
and `ELEC-PAD` in that these are tuned for layering and long-duration
use — lower CPU overhead, smoother parameter response.

| Source | Character |
|--------|-----------|
| `DRONE-PEDAL` | Long, stable, low-register tone — Tibetan overtone bowl feel |
| `DRONE-FIFTH` | Two-tone perfect-fifth drone — open, spacious |
| `DRONE-CLUSTER` | Dense semitone cluster — tension, uncertainty |
| `DRONE-SHIMMER` | Slow spectral modulation — evolving, slightly unsettled |
| `DRONE-ORGAN` | Pipe-organ inspired additive — regal, stable |
| `DRONE-PAD` | Warm detuned oscillator pad — lush, enveloping |
| `DRONE-BREATH` | Breathy, respiratory — animate, alive |

All drones: `DRONE-CREATE ( freq rate -- src )`, `DRONE-RENDER ( buf src -- )`,
plus `DRONE-FREQ!`, `DRONE-*!` setters for their specific parameters.

### 8.6 audio/src/cache.f — Source Render Cache

```
PROVIDED akashic-src-cache
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-fp16
```

Pre-renders sources at a grid of parameter values.  Any source
satisfying the one-shot contract (`*-STRIKE`) can be cached.

**Why:** Modal synthesis costs 15–30 ops per sample per partial.  For
a 12-partial bell at 44100 Hz, that's 7–13 million ops per second for
one voice.  A 500 ms pre-rendered buffer costs the same compute once
then plays back for free — the right trade when parameters don't
change sample-by-sample.

**Architecture:**

A cache is a 2D or 3D grid: `pitch × velocity [× third-param]`.
Each cell holds a PCM buffer pointer or NULL (not yet rendered, or
evicted).  On lookup:

1. Find the nearest grid cell to requested parameter triple.
2. If cell is populated and pitch-exact: return directly.
3. If cell is populated but pitch differs: resample (pitch-shift the
   cached buffer) — cheaper than full re-synthesis.
4. If cell is NULL (miss): invoke `*-STRIKE` once, store, return.
5. Evict LRU cell if XMEM pressure is high.

Hot cells (frequently accessed) promoted to HBW.  Cold cells in XMEM.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SCACHE-CREATE` | `( n-pitches n-vels strike-xt rate -- cache )` | Create cache.  `strike-xt` is `( vel src -- buf )` |
| `SCACHE-FREE` | `( cache -- )` | Free all buffers + descriptor |
| `SCACHE-PRIME` | `( src cache -- )` | Pre-render entire grid now |
| `SCACHE-PRIME-LAZY` | `( src cache -- )` | Mark all cells for lazy render on first use |
| `SCACHE-LOOKUP` | `( freq vel cache -- buf )` | Get buffer (render/resample if needed) |
| `SCACHE-FLUSH` | `( cache -- )` | Evict all cells |
| `SCACHE-STATS` | `( cache -- hits misses evictions )` | Access counters |
| `SCACHE-PITCH-RANGE!` | `( lo-hz hi-hz cache -- )` | Define the pitch grid range |
| `SCACHE-VEL-RANGE!` | `( lo hi cache -- )` | Define the velocity grid range |

```forth
\ Pre-cache bronze bell at 12 pitches × 4 velocities
my-bell
12 4 ['] ACOU-BELL-STRIKE 44100 SCACHE-CREATE CONSTANT bell-cache
220.0 FP16>  880.0 FP16>  bell-cache SCACHE-PITCH-RANGE!
0.2 FP16>    1.0 FP16>    bell-cache SCACHE-VEL-RANGE!
my-bell bell-cache SCACHE-PRIME

\ Instant lookup:
440.0 FP16>  0.7 FP16>  bell-cache SCACHE-LOOKUP  SPK-WRITE
```

---

## Tier 9 — Palette System

A palette is a named, coherent collection of sound sources — one or
more sources registered under each of a standard set of **sonic roles**.
When sonification forms need "the event-marker sound," "the alert
sound," "the background texture," or "the ambient layer," they ask
the palette, not a specific source.

Swap the palette and the entire aesthetic changes.  The sonification
code doesn't change.  The data-to-sound mapping doesn't change.  Only
the sound does.

This is the level at which "I want it to sound industrial" vs "I want
it to sound like a forest" is expressed — not at the sonification form
level, and not at the individual source level.

### Sonic Roles (standard slots every palette fills)

| Role ID | Name | Used for |
|---------|------|----------|
| `PAL-R-MARK` | mark | Discrete data event, neutral significance |
| `PAL-R-MARK-HI` | mark-hi | Significant discrete event |
| `PAL-R-MARK-LO` | mark-lo | Minor / background discrete event |
| `PAL-R-ALERT` | alert | Threshold crossing, requires attention |
| `PAL-R-CRITICAL` | critical | Critical condition, urgent |
| `PAL-R-SUCCESS` | success | Completion, positive outcome |
| `PAL-R-ERROR` | error | Failure, negative outcome |
| `PAL-R-BG-CALM` | bg-calm | Background texture — calm, stable state |
| `PAL-R-BG-ACTIVE` | bg-active | Background texture — active, processing state |
| `PAL-R-BG-TENSE` | bg-tense | Background texture — elevated, tense state |
| `PAL-R-STREAM-1` | stream-1 | Primary continuous data voice |
| `PAL-R-STREAM-2` | stream-2 | Secondary continuous data voice |
| `PAL-R-STREAM-3` | stream-3 | Tertiary continuous data voice |
| `PAL-R-PULSE` | pulse | Rhythmic rate indicator |
| `PAL-R-SELECT` | select | UI selection / focus |
| `PAL-R-ACTION` | action | UI action / click |
| `PAL-R-NOTIFY` | notify | Notification, lower priority than alert |
| `PAL-R-PROGRESS` | progress | Completion progress |

### 9.1 audio/palette/palette.f — Palette Definition & Registry

```
PROVIDED akashic-palette
REQUIRE  akashic-src-cache
REQUIRE  akashic-audio-pcm
```

**Core palette struct** (18 slots, one per role):

Each slot holds:
- A source cache pointer (or 0 if role uses a one-shot source directly)
- A source pointer (for continuous sources)
- Default parameters (volume, pitch offset, etc.)

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `PAL-CREATE` | `( name-addr -- pal )` | Allocate palette |
| `PAL-FREE` | `( pal -- )` | Free palette (does NOT free sources — caller owns them) |
| `PAL-SET-STRIKE` | `( cache role-id pal -- )` | Assign a source cache to a role (one-shot) |
| `PAL-SET-CONT` | `( src role-id pal -- )` | Assign a continuous source to a role |
| `PAL-SET-GAIN` | `( gain role-id pal -- )` | Set default gain for role |
| `PAL-SET-PITCH` | `( semitones role-id pal -- )` | Set pitch offset for role |
| `PAL-STRIKE` | `( velocity role-id pal -- buf )` | Strike the source assigned to role |
| `PAL-RENDER` | `( buf role-id pal -- )` | Render continuous source for role |
| `PAL-ACTIVE!` | `( pal -- )` | Set as global active palette |
| `PAL-ACTIVE@` | `( -- pal )` | Get global active palette |

**Global convenience words (operate on active palette):**

| Word | Signature | Description |
|------|-----------|-------------|
| `PAL-MARK` | `( velocity -- buf )` | Fire mark role |
| `PAL-ALERT` | `( velocity -- buf )` | Fire alert role |
| `PAL-SUCCESS` | `( velocity -- buf )` | Fire success role |
| `PAL-ERROR` | `( velocity -- buf )` | Fire error role |
| `PAL-BG-CALM` | `( buf -- )` | Render background calm |
| `PAL-BG-ACTIVE` | `( buf -- )` | Render background active |
| `PAL-BG-TENSE` | `( buf -- )` | Render background tense |

### 9.2 audio/palette/acoustic.f — Acoustic Palette

```
PROVIDED akashic-palette-acoustic
REQUIRE  akashic-palette
REQUIRE  akashic-src-acoustic
```

The default palette.  Musical acoustic instruments, warm and physical.

| Role | Source | Notes |
|------|--------|-------|
| mark | ACOU-BELL (bronze, medium) | Clean, clear, neutral |
| mark-hi | ACOU-BELL (steel, bright, large) | Commanding |
| mark-lo | ACOU-WOOD (marimba-type) | Soft, warm |
| alert | ACOU-GONG (medium, rim-struck) | Attention-getting, not harsh |
| critical | ACOU-CYMBAL (crash, large) | Urgent, wide-spectrum |
| success | ACOU-CHIME (ascending triple strike) | Bright, positive |
| error | ACOU-KICK + ACOU-RIDE (simultaneous) | Heavy + dissonant shimmer |
| bg-calm | DRONE-PEDAL | Warm, unobtrusive |
| bg-active | DRONE-BREATH | Animate, alive |
| bg-tense | DRONE-CLUSTER | Harmonic tension |
| stream-1 | DRONE-PAD | Smooth continuous voice |
| stream-2 | DRONE-FIFTH | Open second voice |
| pulse | ACOU-WOOD (woodblock-type) | Crisp, rhythmic |
| select | ACOU-CROTALE | Bright, tiny, precise |
| action | ACOU-CLAVES | Clean click |
| notify | ACOU-TRIANGLE | Light, friendly |
| progress | ACOU-BELL (pitch rises with n/total) | |

### 9.3 audio/palette/electronic.f — Electronic Palette

```
PROVIDED akashic-palette-electronic
REQUIRE  akashic-palette
REQUIRE  akashic-src-electronic
```

Synthetic, abstract.  No acoustic references.  Clean and precise.

| Role | Source |
|------|--------|
| mark | ELEC-PING (mid-freq) |
| mark-hi | ELEC-SWEEP (upward) |
| mark-lo | ELEC-CLICK (muted) |
| alert | ELEC-ZAP (bright, fast) |
| critical | ELEC-CRUNCH (distorted burst) |
| success | ELEC-CHIME (ascending) |
| error | ELEC-THUMP + ELEC-STATIC |
| bg-calm | ELEC-DRONE (warm) |
| bg-active | ELEC-TEXTURE (mid-density grain) |
| bg-tense | DRONE-CLUSTER (electronic) |
| pulse | ELEC-CLICK (metronomic) |
| select | ELEC-BLIP (sine, short) |
| action | ELEC-POP |

### 9.4 audio/palette/natural.f — Natural Palette

```
PROVIDED akashic-palette-natural
REQUIRE  akashic-palette
REQUIRE  akashic-src-natural
```

Environmental, physical world.  No instrument language.

| Role | Source |
|------|--------|
| mark | NAT-WATER-DRIP (small) |
| mark-hi | NAT-ROCK-IMPACT (medium) |
| mark-lo | NAT-GRAVEL-STEP (light) |
| alert | NAT-THUNDER (distant) |
| critical | NAT-CRACK + NAT-THUNDER (close) |
| success | NAT-WATER-DRIP (resonant, multiple) |
| error | NAT-BRANCH-SNAP |
| bg-calm | NAT-WIND (gentle) + NAT-INSECTS (low) |
| bg-active | NAT-STREAM (moderate) |
| bg-tense | NAT-WIND (strong) |
| pulse | NAT-WATER-DRIP (steady rate) |
| select | NAT-CRACK (light) |
| action | NAT-CRUNCH (single step) |

### 9.5 audio/palette/industrial.f — Industrial Palette

```
PROVIDED akashic-palette-industrial
REQUIRE  akashic-palette
REQUIRE  akashic-src-industrial
```

Machines, process, infrastructure.  Data as factory floor.

| Role | Source |
|------|--------|
| mark | INDUS-CLICK |
| mark-hi | INDUS-CLANK |
| mark-lo | INDUS-RELAY |
| alert | INDUS-BANG |
| critical | INDUS-VALVE (max pressure) + INDUS-BANG |
| success | INDUS-RELAY (double click) |
| error | INDUS-THUD + INDUS-HISS |
| bg-calm | INDUS-HVAC (low) + INDUS-MOTOR (idle) |
| bg-active | INDUS-MOTOR (mid load) |
| bg-tense | INDUS-TURBINE (high rpm) |
| pulse | INDUS-RELAY (metronomic) |
| select | INDUS-CLICK |
| action | INDUS-VALVE (brief) |

---

## Tier 10 — Sonification

Systematic mappings from data dimensions to auditory dimensions.
These forms are the auditory equivalent of chart types — repeatable,
learnable patterns for making data audible, not just auditory
decoration or aesthetic choice.

Every form takes a **palette** as a parameter.  The form defines how
data maps to auditory dimensions.  The palette defines what sounds are
made.  Neither knows about the other's internals.

### Why Native Auditory Forms

Data visualization works because it maps data to properties the visual
system processes pre-attentively: position, length, area, color,
orientation.  Those are native capabilities of the eye+brain, not
cultural conventions.

Sound has its own native capabilities, entirely separate:

| Auditory dimension | Pre-attentive? | Data-affinity |
|---|---|---|
| **Pitch** | Yes | Ordered magnitude, direction of change |
| **Tempo / rhythm** | Yes | Rate, urgency, periodicity |
| **Loudness** | Yes | Magnitude, proximity |
| **Timbre / source identity** | Yes | Category, type ("bell" vs "drum") |
| **Attack character** | Yes | Discreteness, suddenness |
| **Density** | Yes | Count, concentration, activity |
| **Harmonic tension** | Yes | Agreement vs divergence |
| **Spatial placement** | Yes | Grouping, identity |
| **Register** | Yes | Scale, weight |
| **Decay length** | Yes | Persistence, stability |

These aren't metaphors borrowed from vision.  Pitch going up meaning
"more" works cross-culturally.  Dissonance meaning "something disagrees"
requires no training.  A sudden loud sound meaning "attend now" is
universal and involuntary.

**Places where sound beats vision:**

- **Temporal resolution** — the ear resolves events ~10× finer than
  the eye.  A 10 ms deviation in rhythm is immediately audible;
  invisible on screen.
- **Peripheral monitoring** — sound doesn't require directed attention.
  A pulse form can be monitored while doing other work.  Dashboards
  require you to look at them.
- **Parallel streams** — humans segregate and track 3–5 simultaneous
  auditory streams (cocktail party effect).  Five line charts = spaghetti.
  Five instrument voices = each is individually followable.
- **Ratio perception** — the cochlea perceives frequency ratios directly.
  Hardwired, not learned.

### 10.1 audio/sonify/param-map.f — Dimension Mapping

```
PROVIDED akashic-sonify-param-map
REQUIRE  akashic-fp16
```

Maps a data value from its domain into an auditory dimension using the
perceptually correct transfer function for that dimension.  The
workhorse primitive used by all other forms.

**Core:**

| Word | Signature | Description |
|------|-----------|-------------|
| `PMAP-LINEAR` | `( v in-lo in-hi out-lo out-hi -- mapped )` | Linear |
| `PMAP-LOG` | `( v in-lo in-hi out-lo out-hi -- mapped )` | Log (pitch, frequency) |
| `PMAP-EXP` | `( v in-lo in-hi out-lo out-hi -- mapped )` | Exp (amplitude, loudness) |
| `PMAP-CLAMP` | `( v lo hi -- clamped )` | Clamp |
| `PMAP-INVERT` | `( v in-lo in-hi -- inv )` | Invert within range |

**Dimension-aware (use the correct curve automatically):**

| Word | Signature | Description |
|------|-----------|-------------|
| `PMAP-PITCH` | `( v in-lo in-hi lo-hz hi-hz -- freq )` | Log-frequency |
| `PMAP-NOTE` | `( v in-lo in-hi lo-note hi-note -- note )` | MIDI note number |
| `PMAP-SCALE` | `( note scale -- quantized )` | Snap to scale |
| `PMAP-LOUDNESS` | `( v in-lo in-hi -- amp )` | Perceptually uniform loudness |
| `PMAP-TEMPO` | `( v in-lo in-hi lo-bpm hi-bpm -- bpm )` | Linear |
| `PMAP-DENSITY` | `( v in-lo in-hi lo-hz hi-hz -- events/s )` | Linear event rate |
| `PMAP-TENSION` | `( v in-lo in-hi -- ratio )` | Frequency ratio (consonance model) |
| `PMAP-TIMBRE` | `( v in-lo in-hi -- t )` | 0.0–1.0 instrument parameter |
| `PMAP-PAN` | `( v in-lo in-hi -- pan )` | −1.0 to +1.0 |
| `PMAP-ATTACK` | `( v in-lo in-hi -- ms )` | |
| `PMAP-DECAY` | `( v in-lo in-hi -- ms )` | |

**Scales:**

| Constant | Scale | Semitones |
|----------|-------|-----------|
| `SCALE-CHROMATIC` | All 12 | 0–11 |
| `SCALE-MAJOR` | Major | 0 2 4 5 7 9 11 |
| `SCALE-MINOR` | Natural minor | 0 2 3 5 7 8 10 |
| `SCALE-PENTATONIC` | Major pentatonic | 0 2 4 7 9 |
| `SCALE-BLUES` | Blues | 0 3 5 6 7 10 |
| `SCALE-WHOLE-TONE` | Whole tone | 0 2 4 6 8 10 |
| `SCALE-HARMONICS` | Harmonic series | 0 12 19 24 28 31… |

**Mapping bundles** — group N data→auditory bindings into one reusable
object, analogous to a "scale" object in a plotting library binding
data columns to visual aesthetics:

| Word | Signature | Description |
|------|-----------|-------------|
| `PMAP-BUNDLE-CREATE` | `( n -- bundle )` | Bundle for N dimensions |
| `PMAP-BUNDLE-BIND` | `( map-xt in-lo in-hi out-lo out-hi dim bundle -- )` | Bind a mapping |
| `PMAP-BUNDLE-APPLY` | `( value dim bundle -- mapped )` | Apply mapping for dim |
| `PMAP-BUNDLE-FREE` | `( bundle -- )` | |

### 10.2 audio/sonify/stream.f — Continuous Data → Evolving Sound

```
PROVIDED akashic-sonify-stream
REQUIRE  akashic-sonify-param-map
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
```

The native auditory form for ordered sequential data.  Data becomes
continuously evolving sound — pitch tracks the primary variable,
timbre parameters track secondary variables, loudness tracks a third.

Exploits sound's native multi-channel property: pitch, timbre, and
loudness evolve simultaneously on one voice, encoding 3+ variables that
a line chart could only show with separate lines.

**Use cases:** time series, logs of any scalar value over time,
sequential measurements, any ordered array.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SSTREAM-CREATE` | `( bundle pal rate -- stream )` | Create stream renderer |
| `SSTREAM-FREE` | `( stream -- )` | |
| `SSTREAM-RENDER` | `( data-addr n stream -- buf )` | Render N points |
| `SSTREAM-RENDER-STEREO` | `( data-addr n stream -- buf )` | Pan tracks index (left→right) |
| `SSTREAM-SPEED!` | `( ms stream -- )` | Time per data point |
| `SSTREAM-GLIDE!` | `( flag stream -- )` | Smooth interpolation between points |
| `SSTREAM-SOURCE!` | `( role stream -- )` | Which palette role to use |

```forth
\ Temperature over 200 hours:
\ pitch = temperature (log, 100–500 Hz)
\ brightness = rate of change (slow = dark, fast = bright)
my-bundle  PAL-ACTIVE@  44100  SSTREAM-CREATE CONSTANT s
200 s SSTREAM-SPEED!
temp-data 200 s SSTREAM-RENDER SPK-WRITE
```

### 10.3 audio/sonify/trigger.f — Discrete Events → Strikes

```
PROVIDED akashic-sonify-trigger
REQUIRE  akashic-sonify-param-map
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-audio-mix
```

The native form for event data.  Each event becomes a palette strike.
The sound tells you: **what kind** (which palette role = source identity),
**how significant** (loudness + register), **when** (temporal position).

Humans identify sound sources categorically with near-zero training.
Assign each event type its own palette role and the ear segregates
them automatically — no visual attention needed.

**Use cases:** server logs, transactions, sensor firings, packet
arrivals, any discrete event stream.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `STRIG-CREATE` | `( n-types pal rate -- trig )` | N event types |
| `STRIG-FREE` | `( trig -- )` | |
| `STRIG-ASSIGN` | `( role-id type-id trig -- )` | Map event type → palette role |
| `STRIG-VEL-MAP!` | `( bundle-dim type-id trig -- )` | Data magnitude → velocity |
| `STRIG-PITCH-MAP!` | `( bundle-dim type-id trig -- )` | Data value → pitch |
| `STRIG-FIRE` | `( value type-id trig -- )` | Fire one event |
| `STRIG-FIRE-AT` | `( value type-id time-ms trig -- )` | Fire at time offset |
| `STRIG-RENDER` | `( duration-ms trig -- buf )` | Mix all pending events to PCM |

```forth
3 PAL-ACTIVE@ 44100 STRIG-CREATE CONSTANT srv-trig
PAL-R-MARK      0 srv-trig STRIG-ASSIGN   \ requests = neutral mark
PAL-R-ERROR     1 srv-trig STRIG-ASSIGN   \ errors = error role
PAL-R-MARK-HI   2 srv-trig STRIG-ASSIGN   \ slow reqs = elevated mark

\ On each incoming event:
response-ms  0 srv-trig STRIG-FIRE
```

### 10.4 audio/sonify/pulse.f — Rate Data → Rhythmic Pulse

```
PROVIDED akashic-sonify-pulse
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
```

A rhythmic pulse whose **speed** encodes a quantity.  The Geiger
counter principle, generalized and aestheticized.

**No visual equivalent.**  Dashboards can't show rhythm because vision
isn't intrinsically temporal.  Sound is.  A pulse form can monitor
a rate in the perceptual periphery while the user does other work.
When the rate deviates, it's noticed without any glance at a screen.

**Use cases:** throughput (req/sec, bytes/sec), heartrate, polling
rate, event rate, build progress — any ongoing rate quantity.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SPULSE-CREATE` | `( role-id pal rate -- pulse )` | Create with palette source |
| `SPULSE-FREE` | `( pulse -- )` | |
| `SPULSE-RATE!` | `( events/sec pulse -- )` | Set current rate |
| `SPULSE-INTENSITY!` | `( amp pulse -- )` | Strike intensity |
| `SPULSE-JITTER!` | `( j pulse -- )` | Timing irregularity 0.0–1.0 |
| `SPULSE-RENDER` | `( duration-ms pulse -- buf )` | Render pulse train |
| `SPULSE-RENDER-LIVE` | `( buf pulse -- )` | Continuous block-mode render |

### 10.5 audio/sonify/texture.f — Aggregates → Ambient Soundscape

```
PROVIDED akashic-sonify-texture
REQUIRE  akashic-sonify-param-map
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
```

The native form for statistical / aggregate data.  Encodes
distribution shape as a continuous auditory texture — you hear the
*character* of the data, not individual points.

**No clean visual equivalent.**  A histogram shows shape but requires
focused attention.  A texture is always-on, peripheral.

**Mappings:**

| Statistic | Auditory dimension | Effect |
|---|---|---|
| Mean | Pitch center | Higher mean = higher pitch |
| Variance | Roughness via palette `bg-*` transition | High var = bg-tense; low = bg-calm |
| Skew | Spectral tilt (source timbre param) | Positive skew = brighter |
| Kurtosis | Grain density / attack character | High kurtosis = spiky; normal = round |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `STEX-CREATE` | `( pal rate -- tex )` | |
| `STEX-FREE` | `( tex -- )` | |
| `STEX-UPDATE` | `( mean var skew kurt tex -- )` | Feed distribution stats |
| `STEX-RENDER` | `( duration-ms tex -- buf )` | Render texture |
| `STEX-SENSITIVITY!` | `( s tex -- )` | Responsiveness 0=sluggish, 1=instant |

### 10.6 audio/sonify/ensemble.f — Multi-Variate → Polyphonic Layers

```
PROVIDED akashic-sonify-ensemble
REQUIRE  akashic-sonify-stream
REQUIRE  akashic-audio-mix
REQUIRE  akashic-audio-pcm
```

The native form for multi-variate data.  Each variable gets its own
voice from the palette in a different timbral register.  Correlated
variables move in consonant intervals.  Diverging variables become
dissonant.

Exploits auditory stream segregation.  Humans track 3–5 simultaneous
auditory streams and selectively attend to any one.  Five line charts
= spaghetti.  Five voices = each followable.

**Use cases:** multi-variate time series, correlated metrics,
portfolio components, parallel signal comparison.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SENS-CREATE` | `( n-voices pal rate -- ens )` | |
| `SENS-FREE` | `( ens -- )` | |
| `SENS-VOICE` | `( bundle role-id pan voice-id ens -- )` | Configure voice |
| `SENS-RENDER` | `( data-matrix n-points ens -- buf )` | Render all voices + mix |
| `SENS-RENDER-LIVE` | `( data-row ens -- )` | Feed one time step |

### 10.7 audio/sonify/interval.f — Relationships → Harmonic Intervals

```
PROVIDED akashic-sonify-interval
REQUIRE  akashic-sonify-param-map
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
```

The native form for **relationships and proportions**.  A/B value ratio
maps directly to frequency ratio.  1:1 = unison.  2:1 = octave.
3:2 = fifth.  Irrational = dissonance.  The cochlea does the
proportional math; no visual encoding or legend needed.

**Use cases:** goal vs actual, budget vs spend, before vs after,
any pair where the ratio is what matters.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SINT-CREATE` | `( base-hz pal rate -- intv )` | |
| `SINT-FREE` | `( intv -- )` | |
| `SINT-PAIR` | `( a b intv -- buf )` | Two tones at frequency ratio a:b |
| `SINT-SERIES` | `( a-data b-data n intv -- buf )` | Evolving ratio over N points |

### 10.8 audio/sonify/alert.f — Threshold Monitor → Escalating Cues

```
PROVIDED akashic-sonify-alert
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
```

Always-on threshold monitoring that changes sonic character as zones
are crossed.  No visual attention required.

The palette provides the sound for each zone: `bg-calm`, `bg-active`,
`bg-tense` for background states; `PAL-R-ALERT` and `PAL-R-CRITICAL`
for crossings.

**Zone model:**

| Zone | Palette role used | Perceptual target |
|------|-------------------|-------------------|
| Normal | bg-calm (continuous) | Calm, unobtrusive — safe |
| Caution | bg-active (continuous) | Warming — pay loose attention |
| Warning | bg-tense + alert event | Discomfort — attend soon |
| Critical | bg-tense + critical event (repeated) | Involuntary attention pull |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SALERT-CREATE` | `( pal rate -- alert )` | |
| `SALERT-FREE` | `( alert -- )` | |
| `SALERT-ZONE!` | `( threshold zone-id alert -- )` | Define zone boundary |
| `SALERT-UPDATE` | `( value alert -- )` | Advance state machine |
| `SALERT-RENDER` | `( duration-ms alert -- buf )` | Render zone sound |
| `SALERT-HYSTERESIS!` | `( margin alert -- )` | Dead-band at boundaries |

### 10.9 audio/sonify/earcon.f — Semantic Audio Tokens

```
PROVIDED akashic-sonify-earcon
REQUIRE  akashic-palette
REQUIRE  akashic-audio-pcm
```

Short, semantically meaningful sound events — the interface between
a palette and user-facing semantic signals.  The distinction from raw
palette access: earcons carry a meaning ("success," "error," "notify")
that is stable across palette swaps.  The sound changes; the meaning
doesn't.

Built entirely from palette roles.  `EAR-SUCCESS` fires the palette's
`success` role.  Swap to the industrial palette: success now sounds
like a relay double-click.  Swap to natural: a water drip triplet.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `EAR-SUCCESS` | `( pal -- buf )` | Positive completion |
| `EAR-ERROR` | `( pal -- buf )` | Failure |
| `EAR-WARNING` | `( pal -- buf )` | Elevated concern |
| `EAR-INFO` | `( pal -- buf )` | Neutral notification |
| `EAR-CRITICAL` | `( pal -- buf )` | Urgent, requires immediate action |
| `EAR-CLICK` | `( pal -- buf )` | Momentary action |
| `EAR-SELECT` | `( pal -- buf )` | Item selection / focus |
| `EAR-DESELECT` | `( pal -- buf )` | Focus lost |
| `EAR-NOTIFY` | `( pal -- buf )` | Low-priority notice |
| `EAR-PROGRESS` | `( n total pal -- buf )` | Completion: pitch rises with n/total |
| `EAR-SCROLL` | `( pal -- buf )` | Rapid low-intensity action feedback |
| `EAR-OPEN` | `( pal -- buf )` | Something expanded / opened |
| `EAR-CLOSE` | `( pal -- buf )` | Something collapsed / closed |
| `EAR-DELETE` | `( pal -- buf )` | Destructive action |

**Convenience — operate on active palette:**

```forth
PAL-ACTIVE@ EAR-SUCCESS SPK-WRITE    \ use current palette
```

### 10.10 audio/sonify/scene.f — Multi-Form Composition

```
PROVIDED akashic-sonify-scene
REQUIRE  akashic-audio-mix
REQUIRE  akashic-audio-pcm
```

Combine multiple sonification forms into a single layered output.
The auditory equivalent of a dashboard page with several simultaneous
charts — each form handles different data, all mixed to stereo.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SSCENE-CREATE` | `( n-layers rate -- scene )` | |
| `SSCENE-FREE` | `( scene -- )` | |
| `SSCENE-LAYER` | `( render-xt gain pan layer-id scene -- )` | Assign render XT to layer |
| `SSCENE-RENDER` | `( duration-ms scene -- buf )` | Mix all layers to stereo |
| `SSCENE-MUTE` | `( layer-id scene -- )` | |
| `SSCENE-SOLO` | `( layer-id scene -- )` | |

```forth
\ Server monitor: pulse (req rate) + stream (latency) + trigger (errors)
3 44100 SSCENE-CREATE CONSTANT dash
['] render-req-pulse    0x3800 0x0000  0 dash SSCENE-LAYER  \ center
['] render-latency-stream 0x3400 0xBC00 1 dash SSCENE-LAYER  \ left
['] render-error-trig   0x3C00 0x3C00  2 dash SSCENE-LAYER  \ right
5000 dash SSCENE-RENDER SPK-WRITE
```

---

## Dependency Graph

```
                       pcm.f (DONE)
                      ╱   │    ╲
                    ╱     │      ╲
             osc.f    noise.f   env.f    lfo.f
               │         │       │        │
               └─────────┼───────┘────────┘
                          │
                    ┌─────▼──────┐
                    │  fx.f      │
                    │  mix.f     │
                    │  chain.f   │
                    │  analysis.f│
                    └─────┬──────┘
                          │
             ┌────────────┼────────────┐
             ▼            ▼            ▼
          synth.f      fm.f        pluck.f
             │            │            │
             └────────────┼────────────┘
                          │
                  wav.f  seq.f  midi.f
                  speaker.f  mic.f
                          │
          ┌───────────────┴──────────────┐
          │       audio/syn/              │
          │  modal  membrane  resonator   │
          │  additive  sustained  granular│
          └───────────────┬──────────────┘
                          │
          ┌───────────────┴──────────────┐
          │       audio/src/              │
          │  acoustic  natural            │
          │  electronic  industrial       │
          │  drones  cache                │
          └───────────────┬──────────────┘
                          │
          ┌───────────────┴──────────────┐
          │       audio/palette/          │
          │  palette  acoustic            │
          │  electronic  natural          │
          │  industrial                   │
          └───────────────┬──────────────┘
                          │
          ┌───────────────┴──────────────┐
          │       audio/sonify/           │
          │  param-map  stream  trigger   │
          │  pulse  texture  ensemble     │
          │  interval  alert  earcon      │
          │  scene                        │
          └──────────────────────────────┘
```

---

## Implementation Order

Phased delivery.  Each phase is independently useful.

### Phase 7 — Synthesis Primitives (~800 lines)

| File | ~Lines | Notes |
|------|--------|-------|
| `syn/modal.f` | 250 | Most important — needed by all acoustic sources |
| `syn/membrane.f` | 150 | Needed by drum-family |
| `syn/resonator.f` | 150 | Needed by natural, industrial, wind |
| `syn/additive.f` | 150 | Needed by drones, electronic chimes |
| `syn/sustained.f` | 150 | Needed by drones, stream form |
| `syn/granular.f` | 200 | Needed by natural (rain, fire, crowd) |

### Phase 8 — Sound Sources (~1600 lines)

| File | ~Lines | Priority |
|------|--------|----------|
| `src/acoustic.f` | 450 | High — fills palette/acoustic |
| `src/electronic.f` | 300 | High — fills palette/electronic |
| `src/natural.f` | 350 | Medium |
| `src/industrial.f` | 250 | Medium |
| `src/drones.f` | 150 | High — needed by stream + texture forms |
| `src/cache.f` | 200 | High — needed by all palettes |

Build order: cache.f first (no dependents on it), then acoustic.f
(most commonly needed), then the rest.

### Phase 9 — Palette System (~600 lines)

| File | ~Lines |
|------|--------|
| `palette/palette.f` | 200 |
| `palette/acoustic.f` | 100 |
| `palette/electronic.f` | 100 |
| `palette/natural.f` | 100 |
| `palette/industrial.f` | 100 |

### Phase 10 — Sonification (~1400 lines)

| File | ~Lines |
|------|--------|
| `sonify/param-map.f` | 200 |
| `sonify/stream.f` | 150 |
| `sonify/trigger.f` | 200 |
| `sonify/pulse.f` | 100 |
| `sonify/texture.f` | 200 |
| `sonify/ensemble.f` | 200 |
| `sonify/interval.f` | 100 |
| `sonify/alert.f` | 150 |
| `sonify/earcon.f` | 50 |
| `sonify/scene.f` | 100 |

### Total Estimate

| Phase | Files | ~Lines |
|---|---|---|
| 1–6 (done) | 19 audio core files | ~6,000 ✅ |
| 7 Synthesis Primitives | 6 files | ~800 |
| 8 Sound Sources | 6 files | ~1,600 |
| 9 Palette System | 5 files | ~600 |
| 10 Sonification | 10 files | ~1,400 |
| **New total** | **27 new files** | **~4,400** |
| **Grand total** | **46 files** | **~10,400** |

---

## Design Decisions

### Three Distinct Abstraction Layers Above the Core

The core (Tiers 1–6) provides raw audio building blocks.  Tiers 7–10
form a stack with clear responsibilities:

- **Tier 7 (synthesis primitives):** *How* to make sound.  Algorithms only.
  No names, no aesthetics, no data.
- **Tier 8 (sound sources):** *What* kind of sound.  Named, parameterized,
  grouped into aesthetic families.  No data.
- **Tier 9 (palettes):** *Which* sources compose a coherent aesthetic.
  Semantic role assignment.  No data.
- **Tier 10 (sonification):** *Mapping* from data dimensions to auditory
  dimensions, mediated by a palette.  No sound design.

Each layer can be used independently.  You can use `syn/modal.f`
directly to build a synthesis engine that has nothing to do with
sonification.  You can use `src/acoustic.f` for a game audio system.
You can define a custom palette without using any built-in sources.
The sonification forms work with any palette.

### Source Contract Is the Critical Interface

The `*-STRIKE` / `*-RENDER` + `*-PARAM!` / `*-PARAM@` contract is what
makes everything else palette-agnostic.  Palettes hold pointers to
source descriptors, not source implementations.  Sonification forms
call `PAL-STRIKE` which calls through to whatever source is registered
for that role.  Adding a new source family (e.g., `src/underwater.f`)
requires no changes to palettes or sonification forms — only a new file
and new palette configurations that use it.

### Instruments Are One Family, Not the Frame

`audio/src/acoustic.f` is one of five source families.  It contains
bells, gongs, drums, cymbals, and strings.  It is not the dominant
concept in the system.  `audio/src/natural.f` (rain, wind, fire) is
equally present.  `audio/src/electronic.f` (abstract blips, sweeps,
crunch) is equally present.  The "everything is a musical instrument"
trap is avoided by structural placement, not by intent.

### FP16 Throughout

All audio processing uses FP16.  All source parameters are FP16.
Consistent with `math/fft.f`, `math/filter.f`, and the tile engine.

### Cache Is Opt-In

Live synthesis is always available.  Cache is for when you know
parameters are stable or when compute budget is tight.  The system
never forces pre-rendering.  You choose it, you control the memory
trade-off.

### Palette Swap Does Not Require Any Application Code Change

A properly written sonification client looks like:

```forth
PAL-ACTIVE@ EAR-SUCCESS SPK-WRITE
```

Swapping from acoustic to industrial requires exactly one line:

```forth
PAL-ACOUSTIC PAL-ACTIVE!
\ ... or ...
PAL-INDUSTRIAL PAL-ACTIVE!
```

No other application code changes.

---

## Testing Strategy

### Tier 7 — Synthesis Primitives

| Module | Test Focus |
|---|---|
| modal.f | N partials produced in output, frequencies at correct ratios, higher partials decay faster, brightness scales high-partial energy, damping extends/shortens duration |
| membrane.f | Frequency sweep measurable in first N ms, noise component in specified band, tone/noise blend correct at extremes |
| resonator.f | Output has energy concentrated at pole frequencies, Q controls sharpness, continuous output is steady-state |
| additive.f | Harmonic N is at N × fundamental, morph changes amplitude smoothly over specified time |
| sustained.f | Brightness shifts filter spectrum, motion adds periodic spectral variation, density changes oscillator count, continuous output |
| granular.f | Grain density sets events/sec, scatter randomizes positions, sparse = discrete events, dense = fused texture |

### Tier 8 — Sound Sources

| Module | Test Focus |
|---|---|
| acoustic.f | ACOU-BELL uses MODAL-TBL-BRONZE ratios, strike velocity scales amplitude, size parameter shifts fundamental, different materials produce measurably different spectra |
| acoustic.f | ACOU-KICK has energy below 100 Hz; ACOU-SNARE has noise above 2 kHz; hat is noise-dominant |
| natural.f | NAT-RAIN at intensity 1.0 is louder than 0.1; surface param shifts grain attack character; density increases grain/sec |
| electronic.f | ELEC-SWEEP starts at specified freq, ends at specified freq; ELEC-CRUNCH has distortion artifacts |
| industrial.f | INDUS-MOTOR fundamental = rpm/60; harmonic content matches motor-type |
| cache.f | Prime fills all cells; lookup on exact pitch returns cached buffer; lookup between pitches returns resampled buffer; flush clears all cells; stats track hits/misses |

### Tier 9 — Palette System

| Test | Focus |
|------|-------|
| PAL-SET-STRIKE + PAL-STRIKE | Correct source invoked, velocity passed through |
| PAL-ACTIVE! + PAL-ACTIVE@ | Global palette round-trip |
| PAL-ACOUSTIC loaded | All 18 roles populated |
| Palette swap | Same call produces different spectrum with different palette |

### Tier 10 — Sonification Forms

| Module | Test Focus |
|---|---|
| param-map.f | PMAP-LOG: doubling input does not double output; PMAP-PITCH: output is in Hz range; PMAP-SCALE: output is member of specified scale |
| stream.f | Output length = n × speed-ms; pitch contour monotonically follows monotonic input |
| trigger.f | N events produce N audible strikes; different types produce different spectra |
| pulse.f | Higher rate = more strikes per second, measured by onset detector |
| texture.f | High variance output is measurably noisier; low variance is smoother |
| ensemble.f | N voices produce N distinguishable streams with different spectral centroids |
| interval.f | a=b → single frequency; a=2b → octave relationship |
| alert.f | Crossing threshold changes output; hysteresis prevents rapid toggling |
| earcon.f | All semantic tokens produce non-silent output; palette swap changes spectrum, not duration |
| scene.f | N layers mixed; mute silences one layer while others continue |

### Integration Tests

| Test | Validates |
|------|-----------|
| modal → ACOU-BELL → cache → PAL-ACOUSTIC → EAR-SUCCESS | Full source stack works end-to-end |
| NAT-RAIN → PAL-NATURAL → STEX-UPDATE (variance) → output | Natural texture sonification |
| data array → SSTREAM → PAL-ELECTRONIC → speaker | Electronic stream form |
| 3-variate data → SENS → PAL-ACOUSTIC → mix → speaker | Ensemble, multi-voice |
| threshold crossing → SALERT → PAL-INDUSTRIAL | Industrial alert escalation |
| 3-layer scene (pulse + stream + trigger) → PAL-ACOUSTIC | Full dashboard composition |
| PAL-ACOUSTIC → PAL-INDUSTRIAL swap → same earcon call | Palette swap transparency |
