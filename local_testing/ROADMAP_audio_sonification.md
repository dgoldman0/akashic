# Audio & Sonification Library — Roadmap

A general-purpose audio toolkit for KDOS / Megapad-64, covering
synthesis, effects processing, mixing, analysis, sequencing, I/O, and
codec support.  Plus a sonification sub-library that bridges the visual
render pipeline to audio output — data → sound.

The system is designed as a standalone peer to `render/` and `math/`,
not tied to any particular UI paradigm.  Games, music tools, media
players, accessibility engines, creative coding, data sonification —
all are first-class use cases.

The Megapad-64 platform already provides an unusually rich foundation:
lock-aware ring buffers, a tile/SIMD engine with FP16/BF16 modes, a
hardware timer with compare-match IRQ, multicore dispatch with IPI
messaging, 3 MiB of internal high-bandwidth math RAM, external RAM
with free-list allocation, a cooperative+preemptive scheduler, and a
PCM buffer abstraction that mirrors `render/surface.f` for pixels.

---

## Table of Contents

- [Current State — What We Already Have](#current-state--what-we-already-have)
  - [KDOS Built-Ins](#kdos-built-ins)
  - [Akashic Libraries](#akashic-libraries)
  - [What This Gives Us Already](#what-this-gives-us-already)
- [What's Missing](#whats-missing)
- [Architecture Overview](#architecture-overview)
- [Tier 1 — Generation](#tier-1--generation)
  - [1.1 audio/osc.f — Oscillators](#11-audiooscf--oscillators)
  - [1.2 audio/noise.f — Noise Generators](#12-audionoisef--noise-generators)
  - [1.3 audio/env.f — Envelope Generators](#13-audioenvf--envelope-generators)
  - [1.4 audio/lfo.f — Low-Frequency Oscillators](#14-audiolfof--low-frequency-oscillators)
- [Tier 2 — Processing](#tier-2--processing)
  - [2.1 audio/fx.f — Effects Collection](#21-audiofxf--effects-collection)
  - [2.2 audio/mix.f — Mixer](#22-audiomixf--mixer)
  - [2.3 audio/chain.f — Effect Chains](#23-audiochainf--effect-chains)
- [Tier 3 — Analysis](#tier-3--analysis)
  - [3.1 audio/analysis.f — Spectral, Pitch, Onset, Metering](#31-audioanalysisf--spectral-pitch-onset-metering)
- [Tier 4 — Synthesis Engines](#tier-4--synthesis-engines)
  - [4.1 audio/synth.f — Subtractive Voice](#41-audiosynthf--subtractive-voice)
  - [4.2 audio/fm.f — FM Synthesis](#42-audiofmf--fm-synthesis)
  - [4.3 audio/pluck.f — Karplus-Strong](#43-audiopluckf--karplus-strong)
- [Tier 5 — Sequencing & Format](#tier-5--sequencing--format)
  - [5.1 audio/wav.f — WAV/RIFF Codec](#51-audiowavf--wavriff-codec)
  - [5.2 audio/seq.f — Step Sequencer](#52-audioseqf--step-sequencer)
  - [5.3 audio/midi.f — MIDI Protocol](#53-audiomidif--midi-protocol)
- [Tier 6 — I/O & Drivers](#tier-6--io--drivers)
  - [6.1 audio/speaker.f — DAC Output](#61-audiospeakerf--dac-output)
  - [6.2 audio/mic.f — ADC Capture](#62-audiomicf--adc-capture)
- [Tier 7 — Sonification](#tier-7--sonification)
  - [7.1 render/sonification/param-map.f — Parameter Mapping](#71-rendersonificationparam-mapf--parameter-mapping)
  - [7.2 render/sonification/data2tone.f — Data Series → Melody](#72-rendersonificationdata2tonef--data-series--melody)
  - [7.3 render/sonification/earcon.f — Notification Sounds](#73-rendersonificationearconf--notification-sounds)
  - [7.4 render/sonification/scene2audio.f — Scene Graph → Audio](#74-rendersonificationscene2audiof--scene-graph--audio)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Design Decisions](#design-decisions)
- [Testing Strategy](#testing-strategy)

---

## Current State — What We Already Have

### KDOS Built-Ins

The kernel and BIOS provide the entire low-level runtime for audio.
No custom ring buffers, no custom locks, no custom timers needed.

| Facility | Words | Audio Relevance |
|---|---|---|
| **Ring Buffers (§18)** | `RING`, `RING-PUSH`, `RING-POP`, `RING-PEEK`, `RING-FULL?`, `RING-EMPTY?`, `RING-COUNT` — 56-byte descriptor, spinlock-protected, arbitrary element size | Streaming audio pipeline. `2 1024 RING audio-out` = 1024-slot ring of 16-bit samples. Producer/consumer between synth task and DAC ISR. |
| **Tile Engine (MEX)** | `TSUM`, `TADD`, `TSUB`, `TMUL`, `TDOT`, `TMIN`, `TMAX`, `TSUMSQ`, `TABS` — 64-byte SIMD tiles, U8/FP16/BF16 modes, FP32 accumulator | Bulk DSP accelerator. 32 FP16 samples per tile = one tile op processes 32 frames. Mix, gain, convolve, sum-of-squares — all tile-accelerated. |
| **FP16 Buffer Ops** | `F.SUM`, `F.DOT`, `F.SUMSQ`, `F.ADD`, `F.MUL`, `BF.SUM`, `BF.DOT` | Direct SIMD FP16 audio math. Mixing N channels = `F.ADD` per tile. |
| **HBW Math RAM** | `HBW-ALLOT`, `HBW-TALIGN`, `HBW-RESET` — 3 MiB internal BRAM, bump allocator, tile-aligned | Low-latency hot buffers. Delay lines, wavetables, active PCM data. Internal BRAM = no bus contention, zero-wait tile access. |
| **External RAM** | `XMEM-ALLOT`, `XMEM-FREE-BLOCK`, `XBUF` — external HyperRAM/SDRAM, free-list allocator | Cold storage. WAV files, long recordings, instrument patch banks, sample libraries. |
| **Hardware Timer** | `TIMER!`, `TIMER-CTRL!`, `TIMER-ACK` — 32-bit compare-match, auto-reload, IRQ to IVT slot 7 | Sample-accurate timing. Timer ISR at audio rate drains ring buffer to DAC. Proven pattern (scheduler uses same timer for preemption). |
| **ISR / IVT** | `ISR!` (install Forth XT at IVT slot), `EI!` / `DI!` | Interrupt-driven playback. `' audio-isr 7 ISR!` installs the drain callback. |
| **Scheduler (§8)** | `TASK`, `SPAWN`, `BG`, `YIELD`, `PREEMPT-ON/OFF` — cooperative + preemptive, 8 task slots | Background audio thread. Synthesis fills ring while main task does UI or computation. |
| **Multicore (§8.1)** | `CORE-RUN`, `CORE-WAIT`, `BARRIER`, IPI messaging — 4 cores | Dedicated audio core. Core 1 renders audio, Core 0 does UI. Ring buffer bridges cores with spinlock protection already in place. |
| **Spinlocks** | `LOCK` / `UNLOCK` — 8 hardware MMIO spinlocks; spinlock 4 assigned to ring buffers | Already wired into RING-PUSH/POP. Audio uses rings → gets thread-safe streaming for free. |
| **Heap** | `ALLOCATE` / `FREE` / `RESIZE` — first-fit with coalescing | Dynamic descriptors: PCM headers, effect chains, voice pools. |
| **Disk / MP64FS** | `FWRITE`, `FREAD`, `FSEEK`, `OPEN`, DMA disk I/O, named files | Save/load WAV files, instrument patches, sequences to named files. |
| **Data Ports** | NIC frame ingestion, `POLL`, `INGEST` — Python `AudioSource` already exists | External audio input from host. `AudioSource` generates tone/chord/chirp/square via NIC frames. |
| **CRC-32** | Hardware CRC via MMIO | WAV file checksums, bundle integrity. |
| **RTC** | `UPTIME@`, `EPOCH@`, `SEC@`, `MIN@`, `HOUR@` | Timestamping recordings, scheduled playback. |

### Akashic Libraries

| Library | File | Lines | Audio Relevance |
|---|---|---|---|
| akashic-audio-pcm | `audio/pcm.f` | 662 | **Done.** PCM buffer abstraction: alloc, accessors, sample I/O, copy, slice, clone, reverse, resample (nearest-neighbor), mono mix-down, normalize, peak scan. The `surface.f` of audio. |
| akashic-fft | `math/fft.f` | 481 | Radix-2 FFT on FP16 arrays. Magnitude, power spectrum, convolution, cross-correlation. Twiddle factors via `TRIG-SINCOS`. |
| akashic-filter | `math/filter.f` | 500 | FIR, IIR biquad (direct-form-II transposed), 1D convolution, moving average, median, Hamming-windowed sinc lowpass/highpass. |
| akashic-timeseries | `math/timeseries.f` | 724 | SMA, EMA, EWMA, autocorrelation, cumulative sum, rolling std, z-score outliers — usable for onset detection, pitch tracking. |
| akashic-trig | `math/trig.f` | ~200 | `TRIG-SINCOS` — sine/cosine lookup. Directly usable for oscillator sample generation. |
| akashic-interp | `math/interp.f` | ~200 | Linear and cubic interpolation — usable for high-quality resampling. |
| akashic-fp16 | `math/fp16.f` + `fp16-ext.f` | ~600 | FP16 arithmetic, conversions, comparisons. The numeric format for all audio processing. |
| akashic-color | `math/color.f` | 598 | HSL/HSV ↔ RGB. Relevant for param-map.f (mapping data to timbre via spectral analogy). |
| akashic-channel | `concurrency/channel.f` | ~300 | Go-style bounded channels. Alternative to raw ring buffers for command passing. |
| akashic-semaphore | `concurrency/semaphore.f` | ~150 | Counting semaphores. Useful for voice pool management. |
| akashic-event | `concurrency/event.f` | ~150 | Event flags. Trigger-on-beat, sync-to-onset. |
| akashic-rwlock | `concurrency/rwlock.f` | ~150 | Reader-writer lock. Multiple readers of wavetable + single writer for wavetable swap. |

### What This Gives Us Already

```
              PCM buffer (audio/pcm.f)
                   │
 ┌─────────────────┼─────────────────┐
 │ read/write      │ bulk ops        │ analysis
 │ PCM-SAMPLE@/!   │ PCM-COPY        │ PCM-SCAN-PEAK
 │ PCM-FRAME@/!    │ PCM-CLEAR       │ PCM-NORMALIZE
 │                 │ PCM-FILL        │
 │                 │ PCM-REVERSE     │
 │                 │ PCM-RESAMPLE    │
 │                 │ PCM-TO-MONO     │
 │                 │ PCM-CLONE       │
 │                 │ PCM-SLICE       │
 │                 │                 │
 │  tile engine    │ math library    │ streaming
 │  F.ADD F.MUL    │ FFT-FORWARD     │ RING-PUSH
 │  F.SUM F.DOT    │ FFT-INVERSE     │ RING-POP
 │  TSUM TADD      │ FILT-FIR        │ TIMER! ISR!
 │  TMUL TDOT      │ FILT-IIR-BIQUAD │ TASK SPAWN
 │                 │ FILT-LOWPASS     │ CORE-RUN
 │                 │ TS-AUTOCORR      │
 └─────────────────┴─────────────────┘
```

### What's Missing (The Gap)

There are no **sound generators** — the step that creates audio content
(oscillators, noise, envelopes).  There is no **effects pipeline** that
chains processing stages.  There is no **mixer** to combine voices.
There are no **synthesis engines** that compose generators + filters +
envelopes into playable instruments.  There is no **analysis layer**
tuned for audio (windowed FFT, pitch detection, onset detection, VU
metering).  There is no **WAV codec**, no **sequencer**, no **MIDI
support**, no **DAC/ADC driver**, and no **sonification** bridge from
data to sound.

```
    ??? ──► oscillator ──► filter ──► envelope ──► mixer ──► ??? speaker
                                                      ↑
    ??? ──► noise ────────────────────► reverb ────────┘

    data ──► ??? ──► audio parameters ──► sound
```

---

## Architecture Overview

```
audio/
├── pcm.f              PCM buffers (DONE)
├── osc.f              Oscillators (sine, square, saw, tri, pulse, wavetable)
├── noise.f            Noise generators (white, pink, brown)
├── env.f              Envelope generators (ADSR, AR, ramp)
├── lfo.f              Low-frequency oscillators (modulation source)
├── fx.f               Effects (delay, reverb, chorus, distortion, EQ, compressor)
├── mix.f              N-channel mixer (gain, pan, mute, master)
├── chain.f            Serial effect chain (ordered slots, per-slot bypass)
├── analysis.f         Audio analysis (spectrum, pitch, onset, metering)
├── synth.f            Subtractive synthesis voice
├── fm.f               FM synthesis (2-op / 4-op)
├── pluck.f            Karplus-Strong plucked string
├── wav.f              WAV/RIFF read + write
├── seq.f              Step sequencer (BPM, patterns, tracks)
├── midi.f             MIDI byte protocol (parse + generate)
├── speaker.f          DAC output driver (timer ISR + ring drain)
└── mic.f              ADC capture driver (timer ISR + ring fill)

render/sonification/
├── param-map.f        Numeric range → audio parameter mapping
├── data2tone.f        Data series → melodic PCM (scale quantization)
├── earcon.f           Procedural notification sounds
└── scene2audio.f      Scene graph / DOM → audio description
```

Prefix conventions:

| Module | Prefix | Internal |
|---|---|---|
| pcm.f | `PCM-` | `_PCM-` |
| osc.f | `OSC-` | `_OSC-` |
| noise.f | `NOISE-` | `_NOISE-` |
| env.f | `ENV-` | `_ENV-` |
| lfo.f | `LFO-` | `_LFO-` |
| fx.f | `FX-` | `_FX-` |
| mix.f | `MIX-` | `_MIX-` |
| chain.f | `CHAIN-` | `_CHAIN-` |
| analysis.f | `ANA-` | `_ANA-` |
| synth.f | `SYNTH-` | `_SYNTH-` |
| fm.f | `FM-` | `_FM-` |
| pluck.f | `PLUCK-` | `_PLUCK-` |
| wav.f | `WAV-` | `_WAV-` |
| seq.f | `SEQ-` | `_SEQ-` |
| midi.f | `MIDI-` | `_MIDI-` |
| speaker.f | `SPK-` | `_SPK-` |
| mic.f | `MIC-` | `_MIC-` |
| param-map.f | `PMAP-` | `_PMAP-` |
| data2tone.f | `D2T-` | `_D2T-` |
| earcon.f | `EAR-` | `_EAR-` |
| scene2audio.f | `S2A-` | `_S2A-` |

---

## Tier 1 — Generation

Everything that creates audio content.  Each generator writes into a
PCM buffer.  Generators are stateless functions (no hidden globals) —
state lives in the PCM buffer or an explicit descriptor.

### 1.1 audio/osc.f — Oscillators

```
PROVIDED akashic-audio-osc
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-trig          \ TRIG-SINCOS for sine
REQUIRE  akashic-fp16          \ FP16 arithmetic
```

Band-limited oscillators that write FP16 samples into a PCM buffer.
All waveforms are generated at a specified frequency and sample rate.
Phase is tracked per-oscillator descriptor for continuous output
across successive calls.

**Data structure** — oscillator descriptor (6 cells = 48 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | freq | Frequency in Hz (FP16) |
| +8 | phase | Current phase accumulator 0.0–1.0 (FP16) |
| +16 | rate | Sample rate in Hz |
| +24 | shape | Waveform type (0=sine, 1=square, 2=saw, 3=tri, 4=pulse) |
| +32 | duty | Pulse duty cycle 0.0–1.0 (FP16, used when shape=4) |
| +40 | table | Wavetable address or 0 (0 = computed waveform) |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `OSC-CREATE` | `( freq shape rate -- osc )` | Allocate oscillator descriptor |
| `OSC-FREE` | `( osc -- )` | Free descriptor |
| `OSC-FREQ!` | `( freq osc -- )` | Set frequency (Hz, FP16) |
| `OSC-SHAPE!` | `( shape osc -- )` | Set waveform type |
| `OSC-DUTY!` | `( duty osc -- )` | Set pulse duty cycle |
| `OSC-TABLE!` | `( addr osc -- )` | Set wavetable address (0 = analytical) |
| `OSC-RESET` | `( osc -- )` | Reset phase to 0 |
| `OSC-FILL` | `( buf osc -- )` | Fill PCM buffer with oscillator output |
| `OSC-ADD` | `( buf osc -- )` | Add oscillator output to existing buffer (additive mix) |
| `OSC-SAMPLE` | `( osc -- value )` | Generate single sample, advance phase |

**Waveform generation:**

- **Sine:** `TRIG-SINCOS` lookup on phase × 2π. One lookup per sample.
- **Square:** Phase < 0.5 → +1.0, else → −1.0. Anti-aliased via
  polyBLEP correction at transitions.
- **Saw:** Phase × 2.0 − 1.0. PolyBLEP at the discontinuity.
- **Triangle:** 2.0 × |2.0 × phase − 1.0| − 1.0.
- **Pulse:** Phase < duty → +1.0, else → −1.0. PolyBLEP at both
  edges.
- **Wavetable:** Linear interpolation between adjacent samples in a
  user-provided FP16 table. Table size is arbitrary (typically 256 or
  1024 entries).

**Memory policy:** Oscillator descriptors on heap (48 bytes each).
Wavetables in HBW for tile-aligned access, or XMEM for large tables.

**Design notes:**
- PolyBLEP costs ~4 extra FP16 ops per discontinuity per sample.
  Negligible for typical frame sizes.  Can be disabled for sub-audio
  LFO use (where aliasing doesn't matter).
- `OSC-FILL` uses block processing: phase increment computed once,
  then the loop writes N samples.  For wavetable mode, consecutive
  samples often fall in the same tile → good cache behavior.
- Phase accumulator wraps at 1.0 (not 2π) to stay in FP16 safe range.

### 1.2 audio/noise.f — Noise Generators

```
PROVIDED akashic-audio-noise
REQUIRE  akashic-audio-pcm
```

Three noise colors.  Each has a small descriptor holding generator
state.  Uses BIOS `RANDOM` for initial seed.

**Data structure** — noise descriptor (4 cells = 32 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | type | 0=white, 1=pink, 2=brown |
| +8 | state | LFSR state or accumulator (algorithm-dependent) |
| +16 | pink-rows | Pink noise: 16 octave-band registers (packed) |
| +24 | (reserved) | |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `NOISE-CREATE` | `( type -- desc )` | Allocate noise generator (seeds from RANDOM) |
| `NOISE-FREE` | `( desc -- )` | Free descriptor |
| `NOISE-FILL` | `( buf desc -- )` | Fill PCM buffer with noise |
| `NOISE-ADD` | `( buf desc -- )` | Add noise to existing buffer |
| `NOISE-SAMPLE` | `( desc -- value )` | Generate single sample |

**Algorithms:**

- **White:** 16-bit LFSR (maximal-length polynomial, e.g., x^16 + x^14
  + x^13 + x^11 + 1).  Uniform distribution, flat spectrum.
- **Pink:** Voss-McCartney algorithm.  8 octave-band LFSR rows,
  selected by trailing zeros of a running counter.  −3 dB/octave
  roll-off.  16 bytes of state in `pink-rows`.
- **Brown:** Integrated white noise with leaky accumulator.
  `state ← state × 0.98 + white × 0.02`.  −6 dB/octave roll-off.

### 1.3 audio/env.f — Envelope Generators

```
PROVIDED akashic-audio-env
REQUIRE  akashic-fp16
```

Envelope generators produce a time-varying gain curve (FP16 array or
applied directly to a PCM buffer).  Not tied to any synth — usable for
amplitude, filter cutoff, pitch bend, or any parameter that evolves
over time.

**Data structure** — envelope descriptor (10 cells = 80 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | attack | Attack time in frames |
| +8 | decay | Decay time in frames |
| +16 | sustain | Sustain level 0.0–1.0 (FP16) |
| +24 | release | Release time in frames |
| +32 | phase | Current phase (0=idle, 1=attack, 2=decay, 3=sustain, 4=release, 5=done) |
| +40 | position | Current position within phase (frame count) |
| +48 | level | Current output level (FP16) |
| +56 | curve | Curve type (0=linear, 1=exponential) |
| +64 | mode | 0=one-shot, 1=looping (loops A→D→S→release→A…), 2=AR (attack-release only) |
| +72 | rate | Sample rate in Hz (for ms→frames conversion) |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `ENV-CREATE` | `( a d s r rate -- env )` | Create ADSR envelope (a/d/r in ms, s in FP16 0.0–1.0) |
| `ENV-CREATE-AR` | `( a r rate -- env )` | Create AR envelope (attack-release, no sustain) |
| `ENV-FREE` | `( env -- )` | Free descriptor |
| `ENV-GATE-ON` | `( env -- )` | Trigger attack (note-on) |
| `ENV-GATE-OFF` | `( env -- )` | Trigger release (note-off) |
| `ENV-RETRIGGER` | `( env -- )` | Retrigger from current level (legato) |
| `ENV-RESET` | `( env -- )` | Reset to idle |
| `ENV-TICK` | `( env -- level )` | Advance one frame, return current FP16 level |
| `ENV-FILL` | `( buf env -- )` | Fill PCM buffer with envelope curve |
| `ENV-APPLY` | `( buf env -- )` | Multiply PCM buffer by envelope (in-place gain) |
| `ENV-DONE?` | `( env -- flag )` | True if envelope has completed |

**Design notes:**
- Exponential curves use `level ← level × decay_factor` where
  `decay_factor = (target / start) ^ (1 / frames)`.  Precomputed
  at gate-on time and stored in the descriptor.
- `ENV-APPLY` is tile-accelerated: envelope level is broadcast across
  a tile's worth of samples, then `TMUL` multiplies in-place.
  32 samples per tile op.
- `ENV-FILL` writes raw envelope values — useful for applying the
  same curve as pitch modulation, filter sweep, etc.

### 1.4 audio/lfo.f — Low-Frequency Oscillators

```
PROVIDED akashic-audio-lfo
REQUIRE  akashic-audio-osc     \ reuses oscillator shapes
```

A thin wrapper around `osc.f` configured for sub-audio rates.  Outputs
a **control signal** (FP16 buffer), not an audio signal.  Typical rates
0.1–20 Hz.  Used for vibrato, tremolo, filter wobble, auto-pan.

**Data structure** — LFO descriptor (4 cells = 32 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | osc | Pointer to underlying oscillator descriptor |
| +8 | depth | Modulation depth 0.0–1.0 (FP16) |
| +16 | center | Center value (the "DC offset" of modulation, FP16) |
| +24 | mode | 0=free-run, 1=key-sync (resets phase on trigger) |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `LFO-CREATE` | `( freq shape depth center rate -- lfo )` | Create LFO |
| `LFO-FREE` | `( lfo -- )` | Free LFO + underlying oscillator |
| `LFO-FREQ!` | `( freq lfo -- )` | Set LFO rate (Hz, FP16) |
| `LFO-DEPTH!` | `( depth lfo -- )` | Set modulation depth |
| `LFO-SYNC` | `( lfo -- )` | Reset phase (key-sync trigger) |
| `LFO-FILL` | `( buf lfo -- )` | Fill buffer with control signal: center ± depth × osc |
| `LFO-TICK` | `( lfo -- value )` | Single control sample |

---

## Tier 2 — Processing

Audio effects and routing.  Every effect operates PCM-in → PCM-out.
Effects are stateful (delay buffers, filter state) but their state
lives in explicit descriptors, not globals.

### 2.1 audio/fx.f — Effects Collection

```
PROVIDED akashic-audio-fx
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-filter         \ math/filter.f — IIR biquad for EQ
```

A single file containing six effect types.  Each effect has a CREATE
word that allocates its state, a PROCESS word that transforms a PCM
buffer in-place, and a FREE word.

**2.1.1 Delay / Echo**

Uses KDOS `RING` as the delay line.  Delay time in frames, feedback
gain, wet/dry mix.

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | ring | Pointer to KDOS ring buffer (delay line) |
| +8 | delay | Delay time in frames |
| +16 | feedback | Feedback gain 0.0–1.0 (FP16) |
| +24 | wet | Wet/dry mix 0.0–1.0 (FP16) |

| Word | Signature | Description |
|------|-----------|-------------|
| `FX-DELAY-CREATE` | `( delay-ms rate -- desc )` | Create delay effect with RING as delay line |
| `FX-DELAY-FREE` | `( desc -- )` | Free delay + ring |
| `FX-DELAY!` | `( ms desc -- )` | Change delay time |
| `FX-DELAY-PROCESS` | `( buf desc -- )` | Apply delay in-place |

**Implementation:** For each sample: pop from ring → mix with input →
push result to ring → write output.  The ring capacity determines max
delay.  `2 4800 RING` for a 100 ms delay at 48 kHz.

**2.1.2 Reverb (Schroeder)**

Four parallel comb filters + two series allpass filters.  Classic
Schroeder topology.

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | combs | Pointer to array of 4 comb-filter descriptors |
| +8 | allpasses | Pointer to array of 2 allpass descriptors |
| +16 | room | Room size 0.0–1.0 (scales comb times, FP16) |
| +24 | damp | Damping 0.0–1.0 (LP filter in comb feedback, FP16) |
| +32 | wet | Wet/dry mix (FP16) |

Each comb/allpass uses a KDOS `RING` for its delay line.

| Word | Signature | Description |
|------|-----------|-------------|
| `FX-REVERB-CREATE` | `( room damp wet rate -- desc )` | Create Schroeder reverb |
| `FX-REVERB-FREE` | `( desc -- )` | Free reverb + all delay lines |
| `FX-REVERB-PROCESS` | `( buf desc -- )` | Apply reverb in-place |
| `FX-REVERB-ROOM!` | `( room desc -- )` | Adjust room size |
| `FX-REVERB-DAMP!` | `( damp desc -- )` | Adjust damping |

**Comb delay times (at 44100 Hz, Freeverb classic):** 1116, 1188,
1277, 1356 samples.  Scaled by room parameter.  Each comb includes a
one-pole LP filter in the feedback path (damp control).

**Allpass delay times:** 556, 441 samples.  Gain = 0.5.

**Memory:** 4 combs × ~1400 samples × 2 bytes + 2 allpasses × ~560
samples × 2 bytes ≈ 13.4 KiB total.  Fits comfortably in HBW.

**2.1.3 Chorus**

Modulated delay line.  An LFO sweeps the read position of a short
delay.

| Word | Signature | Description |
|------|-----------|-------------|
| `FX-CHORUS-CREATE` | `( depth rate-hz mix rate -- desc )` | Create chorus (LFO modulates a 20–30 ms delay) |
| `FX-CHORUS-FREE` | `( desc -- )` | Free chorus |
| `FX-CHORUS-PROCESS` | `( buf desc -- )` | Apply chorus in-place |

**Implementation:** Delay line + LFO modulating tap position.  Linear
interpolation between delay samples for sub-sample tap position.

**2.1.4 Distortion / Bitcrusher**

Two modes: soft clipping (tanh-like waveshaping) and bitcrusher
(bit-depth reduction + sample-rate reduction).

| Word | Signature | Description |
|------|-----------|-------------|
| `FX-DIST-CREATE` | `( drive mode -- desc )` | Create distortion (0=soft, 1=hard, 2=bitcrush) |
| `FX-DIST-FREE` | `( desc -- )` | Free |
| `FX-DIST-PROCESS` | `( buf desc -- )` | Apply distortion in-place |
| `FX-DIST-DRIVE!` | `( drive desc -- )` | Set drive amount |

- **Soft clip:** `out = x × drive / (1 + |x × drive|)` — smooth
  saturation, no lookup table needed.
- **Hard clip:** `out = CLAMP(x × drive, -1.0, +1.0)`.
- **Bitcrush:** Reduce bit depth by masking lower bits; reduce
  sample rate by holding every Nth sample.

**2.1.5 Parametric EQ**

Wraps `math/filter.f` IIR biquads with audio-friendly parameter
names.  Up to 4 bands.

| Word | Signature | Description |
|------|-----------|-------------|
| `FX-EQ-CREATE` | `( nbands rate -- desc )` | Create parametric EQ (1–4 bands) |
| `FX-EQ-FREE` | `( desc -- )` | Free |
| `FX-EQ-BAND!` | `( freq gain-db Q band# desc -- )` | Configure band (peak, shelf, notch auto-selected by freq) |
| `FX-EQ-PROCESS` | `( buf desc -- )` | Apply EQ in-place (cascaded biquads) |

Each band stores `FILT-IIR-BIQUAD` coefficients (b0, b1, b2, a1, a2)
plus a 2-sample delay state.  Coefficients recomputed on `FX-EQ-BAND!`.

**Band types auto-selected:**
- Freq < 200 Hz → low shelf
- Freq > rate/4 → high shelf
- Otherwise → peaking EQ

**2.1.6 Compressor / Limiter**

Dynamics processor.  RMS or peak envelope detection → gain reduction.

| Word | Signature | Description |
|------|-----------|-------------|
| `FX-COMP-CREATE` | `( thresh ratio attack release rate -- desc )` | Create compressor |
| `FX-COMP-FREE` | `( desc -- )` | Free |
| `FX-COMP-PROCESS` | `( buf desc -- )` | Apply compression in-place |
| `FX-COMP-LIMIT!` | `( desc -- )` | Set ratio to infinity (limiter mode) |

**Envelope follower:** Smoothed RMS level via one-pole LP filter.
`level ← α × |sample| + (1 − α) × level` with separate α for attack
and release.  Gain computed as:
$G = \begin{cases} 1 & \text{if level} < \text{threshold} \\ (\text{threshold}/\text{level})^{1 - 1/\text{ratio}} & \text{otherwise} \end{cases}$

**Tile acceleration:** `F.MUL` for applying computed gain across tile-
width blocks of samples.

### 2.2 audio/mix.f — Mixer

```
PROVIDED akashic-audio-mix
REQUIRE  akashic-audio-pcm
```

N-channel mixer.  Each channel has gain, pan, and mute.  Sums to a
stereo master output buffer.

**Data structure** — mixer descriptor:

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | n-chans | Number of input channels (1–16) |
| +8 | master-gain | Master output gain (FP16) |
| +16 | master-buf | Pointer to output PCM buffer (stereo) |
| +24 | chans | Pointer to channel descriptor array |

**Channel descriptor** (4 cells = 32 bytes per channel):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | gain | Channel gain 0.0–1.0 (FP16) |
| +8 | pan | Pan position −1.0 (left) to +1.0 (right) (FP16) |
| +16 | mute | 0 = active, 1 = muted |
| +24 | buf | Pointer to input PCM buffer for this channel |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `MIX-CREATE` | `( n-chans frames rate -- mix )` | Create mixer with N channels, allocate master buf |
| `MIX-FREE` | `( mix -- )` | Free mixer + master buffer |
| `MIX-GAIN!` | `( gain chan# mix -- )` | Set channel gain |
| `MIX-PAN!` | `( pan chan# mix -- )` | Set channel pan |
| `MIX-MUTE!` | `( flag chan# mix -- )` | Mute/unmute channel |
| `MIX-MASTER-GAIN!` | `( gain mix -- )` | Set master gain |
| `MIX-INPUT!` | `( buf chan# mix -- )` | Assign input buffer to channel |
| `MIX-RENDER` | `( mix -- )` | Sum all active channels → master buffer |
| `MIX-MASTER` | `( mix -- buf )` | Get master output buffer |

**Pan law:** Equal-power panning.
$L = \cos(\pi/4 \times (1 + \text{pan}))$, $R = \sin(\pi/4 \times (1 + \text{pan}))$.
Uses `TRIG-SINCOS`.

**Tile acceleration:** `MIX-RENDER` clears the master buffer, then
for each non-muted channel: scale by gain (tile `F.MUL`), apply pan
gains to compute L/R contributions, tile `F.ADD` into master.

### 2.3 audio/chain.f — Effect Chains

```
PROVIDED akashic-audio-chain
REQUIRE  akashic-audio-pcm
```

An ordered list of effect processing slots.  Each slot holds a
process-XT and a descriptor pointer, plus a bypass flag.  The chain
processes a PCM buffer through each non-bypassed slot in order.

**Data structure** — chain descriptor:

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | n-slots | Number of slots (1–8) |
| +8 | slots | Pointer to slot array |

**Slot** (3 cells = 24 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | process-xt | Execution token of `( buf desc -- )` word |
| +8 | desc | Effect descriptor pointer |
| +16 | bypass | 0 = active, 1 = bypassed |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `CHAIN-CREATE` | `( n-slots -- chain )` | Allocate chain |
| `CHAIN-FREE` | `( chain -- )` | Free chain (does NOT free effects) |
| `CHAIN-SET!` | `( xt desc slot# chain -- )` | Install effect at slot |
| `CHAIN-BYPASS!` | `( flag slot# chain -- )` | Bypass/enable slot |
| `CHAIN-PROCESS` | `( buf chain -- )` | Run buffer through all active slots |
| `CHAIN-CLEAR` | `( chain -- )` | Remove all slots |

**Usage example:**

```forth
3 CHAIN-CREATE CONSTANT my-chain
  ' FX-EQ-PROCESS      my-eq    0 my-chain CHAIN-SET!
  ' FX-COMP-PROCESS    my-comp  1 my-chain CHAIN-SET!
  ' FX-REVERB-PROCESS  my-verb  2 my-chain CHAIN-SET!

  my-buffer my-chain CHAIN-PROCESS     \ EQ → compressor → reverb
  1 1 my-chain CHAIN-BYPASS!           \ bypass compressor
  my-buffer my-chain CHAIN-PROCESS     \ EQ → reverb (comp skipped)
```

---

## Tier 3 — Analysis

### 3.1 audio/analysis.f — Spectral, Pitch, Onset, Metering

```
PROVIDED akashic-audio-analysis
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-fft            \ math/fft.f
REQUIRE  akashic-filter         \ math/filter.f (for pre-filtering)
REQUIRE  akashic-timeseries     \ math/timeseries.f (autocorrelation)
REQUIRE  akashic-fp16
```

Four analysis sections in one file.  All operate on PCM buffers and
return results via the data stack or output buffers.

**3.1.1 Spectral Analysis**

Windowed FFT with overlap-add for STFT.  Bridges `math/fft.f` with
audio-tuned defaults.

| Word | Signature | Description |
|------|-----------|-------------|
| `ANA-WINDOW-HANN` | `( buf -- )` | Apply Hann window to FP16 PCM buffer in-place |
| `ANA-WINDOW-HAMMING` | `( buf -- )` | Apply Hamming window |
| `ANA-WINDOW-BLACKMAN` | `( buf -- )` | Apply Blackman-Harris window |
| `ANA-SPECTRUM` | `( buf -- mag-buf )` | Window → FFT → magnitude. Returns new FP16 buffer (N/2+1 bins) |
| `ANA-POWER` | `( buf -- pow-buf )` | Window → FFT → power spectrum (magnitude²) |
| `ANA-STFT` | `( buf frame-size hop-size -- result n-frames )` | Short-time FFT. Returns array of spectral frames. |
| `ANA-BIN>HZ` | `( bin rate n -- hz )` | Convert FFT bin index to frequency |
| `ANA-HZ>BIN` | `( hz rate n -- bin )` | Convert frequency to nearest bin |

**Window functions:** Precomputed into HBW-resident FP16 buffers on
first use (256 or 512 entries).  `TRIG-SINCOS` for generation.
Applied via tile-accelerated `F.MUL`.

**3.1.2 Pitch Detection**

Monophonic fundamental frequency estimation.  Two methods.

| Word | Signature | Description |
|------|-----------|-------------|
| `ANA-PITCH-AUTO` | `( buf rate -- hz )` | Autocorrelation method. Simple, good for voice. Uses `TS-AUTOCORR`. |
| `ANA-PITCH-YIN` | `( buf rate thresh -- hz )` | YIN algorithm. More accurate for instruments. thresh typically 0.1–0.15. |
| `ANA-NOTE` | `( hz -- midi-note cents )` | Convert Hz to nearest MIDI note number + cents deviation |

**Autocorrelation method:** Compute autocorrelation of the buffer via
`TS-AUTOCORR-N`, find first peak after the initial drop.  Period =
lag at peak.  Hz = rate / period.

**YIN algorithm:** Cumulative mean normalized difference function,
parabolic interpolation at the first dip below threshold.  More
robust than raw autocorrelation for noisy signals.

**3.1.3 Onset / Beat Detection**

Detect note onsets and rhythmic beats via spectral flux.

| Word | Signature | Description |
|------|-----------|-------------|
| `ANA-ONSET-DETECT` | `( buf frame-size hop rate -- onset-buf n )` | Returns buffer of onset frame indices |
| `ANA-SPECTRAL-FLUX` | `( buf frame-size hop -- flux-buf n )` | Compute spectral flux (half-wave rectified difference between consecutive spectra) |
| `ANA-TEMPO` | `( onset-buf n rate -- bpm )` | Estimate tempo from onset times (autocorrelation of onset function) |

**Algorithm:** STFT → magnitude difference between adjacent frames →
half-wave rectify (keep only increases) → adaptive threshold (median
+ constant × MAD) → peaks in flux = onsets.

**3.1.4 Metering**

Real-time level measurement.

| Word | Signature | Description |
|------|-----------|-------------|
| `ANA-RMS` | `( buf -- rms )` | RMS level (FP16). Uses tile-accelerated `F.SUMSQ`. |
| `ANA-PEAK` | `( buf -- peak )` | Peak absolute sample value |
| `ANA-PEAK-HOLD` | `( buf desc -- peak )` | Peak with hold/decay state for VU display |
| `ANA-CREST` | `( buf -- ratio )` | Crest factor = peak / RMS |
| `ANA-DB` | `( level -- db )` | Convert linear level to dB (FP16): $20 \times \log_{10}(\text{level})$ |

**Peak hold:** Descriptor tracks peak value + decay counter.  Peak
rises instantly, decays by a fixed rate per call (e.g., −0.5 dB per
block).  Useful for visual VU meter display.

---

## Tier 4 — Synthesis Engines

Higher-level modules that compose Tier 1 + Tier 2 into playable
instruments.  Each engine is a single-voice module.  Polyphony is
the caller's responsibility (duplicate voices, manage note allocation).

### 4.1 audio/synth.f — Subtractive Voice

```
PROVIDED akashic-audio-synth
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-env
REQUIRE  akashic-filter         \ math/filter.f for resonant LP/HP
```

Classic subtractive architecture: oscillator → filter → amplifier →
output.  One voice per descriptor.

**Data structure** — synth voice descriptor (8 cells = 64 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | osc1 | Primary oscillator descriptor |
| +8 | osc2 | Secondary oscillator (detunable) or 0 |
| +16 | filt-type | Filter type: 0=LP, 1=HP, 2=BP |
| +24 | filt-cutoff | Filter cutoff frequency (FP16) |
| +32 | filt-reso | Filter resonance / Q (FP16) |
| +40 | amp-env | Amplitude envelope descriptor |
| +48 | filt-env | Filter envelope descriptor (modulates cutoff) |
| +56 | work-buf | Pointer to scratch PCM buffer for processing |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SYNTH-CREATE` | `( shape1 shape2 rate frames -- voice )` | Create subtractive voice |
| `SYNTH-FREE` | `( voice -- )` | Free voice + all sub-descriptors |
| `SYNTH-NOTE-ON` | `( freq vel voice -- )` | Trigger note (set osc freq, gate envelopes) |
| `SYNTH-NOTE-OFF` | `( voice -- )` | Release note (gate off envelopes) |
| `SYNTH-RENDER` | `( voice -- buf )` | Render one block: osc → filter → env → output buf |
| `SYNTH-CUTOFF!` | `( freq voice -- )` | Set filter cutoff |
| `SYNTH-RESO!` | `( q voice -- )` | Set filter resonance |
| `SYNTH-DETUNE!` | `( cents voice -- )` | Detune osc2 relative to osc1 |

**Render path:**
1. `OSC-FILL` osc1 → work-buf
2. If osc2: `OSC-ADD` osc2 → work-buf (additive layering)
3. Compute filter cutoff = base_cutoff + filt-env × env-depth
4. `FILT-IIR-BIQUAD` in-place on work-buf
5. `ENV-APPLY` amp-env → work-buf
6. Return work-buf

### 4.2 audio/fm.f — FM Synthesis

```
PROVIDED akashic-audio-fm
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-env
```

2-operator and 4-operator FM.  Each operator is an oscillator + envelope.
Operators can modulate each other's frequency (phase modulation).

**Data structure** — FM voice descriptor:

| Field | Description |
|-------|-------------|
| n-ops | Number of operators (2 or 4) |
| ops[n] | Array of operator descriptors (osc + env + output-level) |
| algorithm | Routing: which ops modulate which (4-op has ~8 classic algorithms) |
| feedback | Self-modulation amount for op1 (FP16) |
| work-buf | Scratch buffer |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `FM-CREATE` | `( n-ops algorithm rate frames -- voice )` | Create FM voice |
| `FM-FREE` | `( voice -- )` | Free |
| `FM-NOTE-ON` | `( freq vel voice -- )` | Trigger (sets carrier freq, modulator at ratio) |
| `FM-NOTE-OFF` | `( voice -- )` | Release |
| `FM-RENDER` | `( voice -- buf )` | Render one block |
| `FM-RATIO!` | `( ratio op# voice -- )` | Set operator frequency ratio |
| `FM-INDEX!` | `( index op# voice -- )` | Set modulation index |
| `FM-ALGO!` | `( algorithm voice -- )` | Set algorithm |

**Algorithms (4-op):**

```
Algo 0: [1]→[2]→[3]→[4]→out              (serial)
Algo 1: [1]→[2]→out, [3]→[4]→out         (two parallel pairs)
Algo 2: [1]→[2]→[3]→out, [4]→out         (3-chain + sine)
Algo 3: [1+2]→[3]→[4]→out                (parallel-mod into serial)
```

For 2-op: op1 modulates op2 (carrier).  Simple, covers most useful FM
timbres (bell, electric piano, bass).

### 4.3 audio/pluck.f — Karplus-Strong

```
PROVIDED akashic-audio-pluck
REQUIRE  akashic-audio-pcm
REQUIRE  akashic-audio-noise    \ initial excitation
REQUIRE  akashic-filter         \ LP filter in feedback loop
```

Plucked-string physical model.  Fill a delay line with noise, then
repeatedly average adjacent samples.  Produces realistic plucked-string
and metallic sounds.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `PLUCK` | `( freq decay buf -- )` | Fill buf with plucked-string sound |
| `PLUCK-CREATE` | `( freq rate -- desc )` | Create persistent pluck state (for re-excitation) |
| `PLUCK-FREE` | `( desc -- )` | Free |
| `PLUCK-EXCITE` | `( desc -- )` | Re-excite (fill delay line with noise) |
| `PLUCK-RENDER` | `( desc -- buf )` | Render one block from current state |

**Implementation:** Delay line length = rate / freq samples.  Uses
KDOS `RING` as the circular delay buffer.  Feedback filter: simple
two-point average `(sample[n] + sample[n-1]) / 2` — automatically
produces the characteristic spectral decay (high frequencies die
faster than low).  `decay` parameter controls a loss factor in the
feedback path.

**Memory:** One ring buffer per pluck voice.  At 44100 Hz, lowest
note A1 (55 Hz) = 802 samples × 2 bytes ≈ 1.6 KiB.

---

## Tier 5 — Sequencing & Format

**Status: ✅ COMPLETE** — wav.f (363 lines), seq.f (352 lines), midi.f (371 lines).  39/39 tests passing.

### 5.1 audio/wav.f — WAV/RIFF Codec

```
PROVIDED akashic-audio-wav
REQUIRE  akashic-audio-pcm
REQUIRE  \ MP64FS file I/O (FWRITE, FREAD, FSEEK from KDOS)
```

Read and write Microsoft WAV files (RIFF container, PCM format chunk).
The BMP of audio — simplest useful container format.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `WAV-WRITE` | `( buf filename-addr filename-len -- ior )` | Write PCM buffer to WAV file on disk |
| `WAV-READ` | `( filename-addr filename-len -- buf ior )` | Read WAV file into new PCM buffer |
| `WAV-WRITE-FD` | `( buf fd -- ior )` | Write to open file descriptor |
| `WAV-READ-FD` | `( fd -- buf ior )` | Read from open file descriptor |
| `WAV-INFO` | `( filename-addr filename-len -- rate bits chans frames ior )` | Read WAV header without loading sample data |

**Format support:**
- PCM format only (format tag = 1).  No compressed formats.
- 8-bit unsigned, 16-bit signed, 32-bit signed.
- Mono and stereo (1–2 channels).
- Sample rates 8000–96000.
- Standard RIFF chunk layout: `RIFF`, `fmt `, `data`.

**WAV header (44 bytes):**

```
Offset  Size  Field
0       4     "RIFF"
4       4     file size - 8
8       4     "WAVE"
12      4     "fmt "
16      4     16 (PCM format chunk size)
20      2     1 (PCM format tag)
22      2     channels
24      4     sample rate
28      4     byte rate (rate × channels × bits/8)
32      2     block align (channels × bits/8)
34      2     bits per sample
36      4     "data"
40      4     data size in bytes
44      ...   sample data
```

### 5.2 audio/seq.f — Step Sequencer

```
PROVIDED akashic-audio-seq
REQUIRE  akashic-audio-pcm
```

A pattern-based step sequencer.  Drives any sound source via a
callback word (execution token).  Tempo-locked to sample-accurate
tick boundaries.

**Data structure** — pattern:

| Field | Description |
|-------|-------------|
| steps | Number of steps (4–64, typically 16) |
| data | Array of step entries: (note, velocity, gate-length) triples |
| loop | 0 = one-shot, 1 = loop |
| swing | Swing amount 0.0–1.0 (delays even steps, FP16) |

**Data structure** — sequencer:

| Field | Description |
|-------|-------------|
| bpm | Tempo in beats per minute |
| tick-frames | Frames per tick (computed from BPM + rate) |
| position | Current step index |
| tick-count | Sub-step frame counter |
| pattern | Pointer to current pattern |
| callback | XT called with `( note velocity gate -- )` per step |
| rate | Sample rate |
| running | 0 = stopped, 1 = playing |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SEQ-CREATE` | `( bpm steps rate -- seq )` | Create sequencer |
| `SEQ-FREE` | `( seq -- )` | Free |
| `SEQ-STEP!` | `( note vel gate step# seq -- )` | Set step data |
| `SEQ-START` | `( seq -- )` | Start playback |
| `SEQ-STOP` | `( seq -- )` | Stop playback |
| `SEQ-TICK` | `( frames seq -- )` | Advance by N frames, fire callback on step boundaries |
| `SEQ-BPM!` | `( bpm seq -- )` | Change tempo |
| `SEQ-SWING!` | `( swing seq -- )` | Set swing |
| `SEQ-CALLBACK!` | `( xt seq -- )` | Set note-trigger callback |
| `SEQ-PATTERN!` | `( pattern seq -- )` | Load pattern |
| `SEQ-POSITION` | `( seq -- step# )` | Current step |

**Timing:** Tick resolution = frames per 16th note =
`rate × 60 / (bpm × 4)`.  At 120 BPM, 44100 Hz: 5512.5 frames per
16th note.  Rounded to integer; cumulative drift tracked and
compensated every bar.

**Swing:** Even-numbered steps delayed by `swing × half-tick-length`.
Swing = 0.0 → straight, swing = 0.67 → triplet feel.

### 5.3 audio/midi.f — MIDI Protocol

```
PROVIDED akashic-audio-midi
```

Parse and generate MIDI byte messages.  Wire protocol only — no
instrument maps, no MIDI file (.mid) reader, no device I/O.  Pure
data format library.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `MIDI-NOTE-ON` | `( chan note vel -- b1 b2 b3 )` | Generate note-on message bytes |
| `MIDI-NOTE-OFF` | `( chan note vel -- b1 b2 b3 )` | Generate note-off message bytes |
| `MIDI-CC` | `( chan cc val -- b1 b2 b3 )` | Generate control change |
| `MIDI-PITCH-BEND` | `( chan bend -- b1 b2 b3 )` | Generate pitch bend (bend: −8192 to +8191) |
| `MIDI-PARSE` | `( byte state -- state' type chan data1 data2 flag )` | Streaming parser with running-status state machine |
| `MIDI-NOTE>HZ` | `( note -- hz )` | MIDI note to frequency (A4 = 440 Hz), FP16 |
| `MIDI-HZ>NOTE` | `( hz -- note cents )` | Frequency to nearest MIDI note + cents |

**Message types (returned by MIDI-PARSE):**
- 0 = note-off, 1 = note-on, 2 = polyphonic aftertouch,
  3 = control change, 4 = program change, 5 = channel aftertouch,
  6 = pitch bend

**Running status:** The parser maintains state across calls.  If a
data byte arrives without a new status byte, the previous status is
reused (standard MIDI running status).  Reduces bandwidth.

**MIDI note → Hz:** $f = 440 \times 2^{(n - 69) / 12}$.  Precomputed
table for notes 0–127 (128 FP16 entries = 256 bytes) for O(1) lookup.

---

## Tier 6 — I/O & Drivers

### 6.1 audio/speaker.f — DAC Output

```
PROVIDED akashic-audio-speaker
REQUIRE  akashic-audio-pcm
\ Uses KDOS: RING, TIMER!, TIMER-CTRL!, ISR!, EI!, DI!
```

Push PCM samples to the speaker DAC via a timer-driven interrupt
service routine.  The speaker hardware is MMIO-mapped (address TBD
by hardware revision — abstracted behind the driver).

**Architecture:**

```
 App task                 Timer ISR (IVT slot 7)
 ────────                 ──────────────────────
 osc → mix → ring ──PUSH──►  ring ──POP──► DAC MMIO
              ▲                              │
              │                              ▼
         RING-FULL? → YIELD             speaker output
```

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `SPK-INIT` | `( rate -- )` | Initialize speaker: create ring buffer, configure timer ISR at sample rate |
| `SPK-START` | `( -- )` | Enable timer, start draining ring to DAC |
| `SPK-STOP` | `( -- )` | Disable timer, silence output |
| `SPK-WRITE` | `( buf -- )` | Push PCM buffer's samples into the ring (blocking: YIELDs if ring full) |
| `SPK-RING` | `( -- ring )` | Access the output ring buffer directly |
| `SPK-RATE` | `( -- rate )` | Current sample rate |
| `SPK-UNDERRUN?` | `( -- flag )` | True if the ISR found the ring empty (gap in output) |
| `SPK-VOLUME!` | `( gain -- )` | Set master output gain (applied in ISR) |

**Timer configuration:** Auto-reload compare-match at
`CPU_CLOCK / sample_rate` cycles.  At 100 MHz CPU, 44100 Hz:
compare = 2267.  `2267 TIMER! 7 TIMER-CTRL!` (enable + auto-reload +
IRQ).

**ISR body (~15 words):**
1. `TIMER-ACK`
2. `SPK-RING RING-EMPTY?` → if empty, write silence to DAC, set
   underrun flag
3. Else: `SPK-RING RING-POP` → apply volume → write to DAC MMIO
4. Return from interrupt

**Ring sizing:** At 44100 Hz with 256-sample blocks, a 2048-sample
ring gives ~46 ms of buffer.  Enough to absorb scheduling jitter.
`2 2048 RING spk-ring`.

**Memory policy:** Ring buffer in HBW for guaranteed low-latency
access from the ISR.

### 6.2 audio/mic.f — ADC Capture

```
PROVIDED akashic-audio-mic
REQUIRE  akashic-audio-pcm
\ Uses KDOS: RING, TIMER!, TIMER-CTRL!, ISR!, EI!, DI!
```

Capture audio from the microphone ADC via timer ISR.  Mirror of
`speaker.f` with the data flow reversed.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `MIC-INIT` | `( rate -- )` | Initialize mic: create ring, configure timer ISR |
| `MIC-START` | `( -- )` | Begin capture |
| `MIC-STOP` | `( -- )` | Stop capture |
| `MIC-READ` | `( buf -- n )` | Pop samples from ring into PCM buffer, return frame count |
| `MIC-RING` | `( -- ring )` | Access the capture ring directly |
| `MIC-OVERRUN?` | `( -- flag )` | True if ISR found ring full (dropped samples) |

**ISR body:** Read ADC MMIO → `RING-PUSH` into mic-ring.  If ring
full, set overrun flag and drop sample.

---

## Tier 7 — Sonification

A sub-library under `render/sonification/` that bridges the visual
render pipeline and data processing to audio output.  Consumers of the
audio library, not part of its core.

### 7.1 render/sonification/param-map.f — Parameter Mapping

```
PROVIDED akashic-sonification-param-map
REQUIRE  akashic-fp16
```

Map a numeric value from one range to an audio parameter in another
range.  The `math/color.f` of audio — converts data space to sound
space.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `PMAP-LINEAR` | `( value in-lo in-hi out-lo out-hi -- mapped )` | Linear mapping |
| `PMAP-LOG` | `( value in-lo in-hi out-lo out-hi -- mapped )` | Logarithmic mapping (better for pitch, frequency) |
| `PMAP-EXP` | `( value in-lo in-hi out-lo out-hi -- mapped )` | Exponential mapping (better for volume, amplitude) |
| `PMAP-CLAMP` | `( value lo hi -- clamped )` | Clamp to range |
| `PMAP-NOTE` | `( value in-lo in-hi lo-note hi-note -- midi-note )` | Map to MIDI note range, quantized to nearest semitone |
| `PMAP-SCALE` | `( midi-note scale -- quantized )` | Quantize MIDI note to nearest note in scale |

**Predefined scales (stored as byte arrays, 1 = note in scale):**

| Word | Scale | Intervals |
|------|-------|-----------|
| `SCALE-CHROMATIC` | Chromatic | All 12 semitones |
| `SCALE-MAJOR` | Major | 0 2 4 5 7 9 11 |
| `SCALE-MINOR` | Natural minor | 0 2 3 5 7 8 10 |
| `SCALE-PENTATONIC` | Major pentatonic | 0 2 4 7 9 |
| `SCALE-BLUES` | Blues | 0 3 5 6 7 10 |
| `SCALE-WHOLE-TONE` | Whole tone | 0 2 4 6 8 10 |

### 7.2 render/sonification/data2tone.f — Data Series → Melody

```
PROVIDED akashic-sonification-data2tone
REQUIRE  akashic-sonification-param-map
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-env
REQUIRE  akashic-audio-pcm
```

Turn a numeric data array into a melodic PCM buffer.  Each data
point becomes one note with pitch proportional to value.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `D2T-SONIFY` | `( data-addr n scale note-ms rate -- buf )` | Convert N FP16 values to a PCM melody |
| `D2T-SONIFY-STEREO` | `( data-addr n scale note-ms rate -- buf )` | Stereo: pan position follows data index (left→right sweep) |
| `D2T-SHAPE!` | `( shape -- )` | Set oscillator waveform for sonification |
| `D2T-RANGE!` | `( lo-note hi-note -- )` | Set MIDI note range (default: 48–84, C3–C6) |
| `D2T-ENV!` | `( attack-ms release-ms -- )` | Set per-note envelope |

**Usage example:**

```forth
\ Sonify a 64-element temperature time series
temp-buffer 64 SCALE-PENTATONIC 100 44100 D2T-SONIFY
\ Returns a PCM buffer of 64 notes × 100 ms = 6.4 seconds
\ Each temperature value → pitch in pentatonic scale
my-chain CHAIN-PROCESS            \ apply reverb
SPK-WRITE                         \ play
```

### 7.3 render/sonification/earcon.f — Notification Sounds

```
PROVIDED akashic-sonification-earcon
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-env
REQUIRE  akashic-audio-pcm
```

Library of short, procedurally-generated notification sounds.  No
samples needed — everything built from oscillators and envelopes at
runtime.  Each earcon is ~50–300 ms.

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `EAR-SUCCESS` | `( rate -- buf )` | Rising two-tone chime (C5→E5), 200 ms |
| `EAR-ERROR` | `( rate -- buf )` | Low buzz (80 Hz square, distorted), 300 ms |
| `EAR-WARNING` | `( rate -- buf )` | Mid-range double beep (A4, A4), 250 ms |
| `EAR-INFO` | `( rate -- buf )` | Soft single ding (C6 sine, fast decay), 150 ms |
| `EAR-CLICK` | `( rate -- buf )` | Brief tick (white noise burst), 10 ms |
| `EAR-SCROLL` | `( rate -- buf )` | Soft tick (filtered noise), 15 ms |
| `EAR-BOUNDARY` | `( rate -- buf )` | Thud (60 Hz sine, heavy envelope), 100 ms |
| `EAR-PROGRESS` | `( n total rate -- buf )` | Rising pitch proportional to n/total |
| `EAR-SELECT` | `( rate -- buf )` | Bright blip (E6→C6 sine glide), 80 ms |
| `EAR-DESELECT` | `( rate -- buf )` | Descending blip (C6→E5), 80 ms |
| `EAR-DELETE` | `( rate -- buf )` | Low sweep down (200→60 Hz saw), 200 ms |
| `EAR-OPEN` | `( rate -- buf )` | Ascending arpeggio (C4 E4 G4), 250 ms |
| `EAR-CLOSE` | `( rate -- buf )` | Descending arpeggio (G4 E4 C4), 250 ms |
| `EAR-TYPE` | `( rate -- buf )` | Mechanical click (noise + 2 kHz sine), 5 ms |
| `EAR-NOTIFY` | `( rate -- buf )` | Gentle two-note chime (G5 C6), 300 ms |

**Design:** Each earcon is a self-contained word that creates a
temporary oscillator + envelope, fills a PCM buffer, frees the
temporaries, and returns the buffer.  Caller owns the returned buffer
and must `PCM-FREE` it when done.

### 7.4 render/sonification/scene2audio.f — Scene Graph → Audio

```
PROVIDED akashic-sonification-scene2audio
REQUIRE  akashic-sonification-param-map
REQUIRE  akashic-audio-osc
REQUIRE  akashic-audio-env
REQUIRE  akashic-audio-mix
REQUIRE  akashic-dom             \ dom/dom.f
```

Walk a DOM tree or box tree and produce an audio description.  The
generic version of what a non-visual browser's audio encoder would
consume.

**Mapping rules:**

| Visual property | Audio parameter | Mapping |
|---|---|---|
| Tree depth | Pitch | Deeper = higher pitch (log scale) |
| Element type | Timbre | Headings = sine, text = triangle, links = saw, lists = square |
| Content length | Note duration | Longer content = longer note (clamped 50–500 ms) |
| Horizontal position | Stereo pan | Left edge = left channel, right edge = right channel |
| Font size / heading level | Volume | Larger = louder |
| Focus / selection | Earcon | `EAR-SELECT` on focus-in, `EAR-DESELECT` on focus-out |

**API:**

| Word | Signature | Description |
|------|-----------|-------------|
| `S2A-WALK` | `( dom-root rate -- buf )` | Walk entire DOM, produce audio |
| `S2A-NODE` | `( node rate -- buf )` | Sonify single node |
| `S2A-ANNOUNCE` | `( node rate -- buf )` | Short earcon for element type |
| `S2A-DESCRIBE` | `( node rate -- buf )` | Full audio description: type + content + position |
| `S2A-DIFF` | `( old-dom new-dom rate -- buf )` | Sonify differences between two DOMs |

---

## Dependency Graph

```
                       pcm.f (DONE)
                      ╱   │    ╲
                    ╱     │      ╲
             osc.f    noise.f   env.f    lfo.f
               │         │       │        │
               │         │       │ ───────┘
               ▼         ▼       ▼
           ┌────────── fx.f ──────────┐
           │      (delay, reverb,     │
           │  chorus, dist, EQ, comp) │
           └──────────────────────────┘
                      │
              ┌───────┼───────┐
              ▼       ▼       ▼
           mix.f   chain.f  analysis.f
              │               │
              ▼               │
    ┌─────────┴────────┐      │
    ▼         ▼        ▼      │
 synth.f   fm.f    pluck.f    │
    │         │        │      │
    ▼         ▼        ▼      ▼
 ┌──────────────────────────────┐
 │     wav.f  seq.f  midi.f    │
 └──────────────────────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
   speaker.f        mic.f
       │
       ▼
 ┌──────────────────────────────────┐
 │  render/sonification/            │
 │  param-map.f  data2tone.f       │
 │  earcon.f     scene2audio.f     │
 └──────────────────────────────────┘

 External dependencies (already exist):
   math/trig.f ──► osc.f
   math/fp16.f ──► osc.f, env.f, lfo.f, fx.f, mix.f, analysis.f
   math/fft.f ──► analysis.f
   math/filter.f ──► fx.f (EQ, reverb LP), synth.f
   math/timeseries.f ──► analysis.f (autocorrelation)
   math/interp.f ──► osc.f (wavetable interp)
   concurrency/* ──► speaker.f, mic.f (optional higher-level sync)
   dom/dom.f ──► scene2audio.f
   KDOS §18 RING ──► fx.f (delay lines), speaker.f, mic.f, pluck.f
   KDOS §8 TASK/TIMER ──► speaker.f, mic.f, seq.f
```

---

## Implementation Order

Phased delivery.  Each phase is independently useful.

### Phase 1 — Sound Generation (osc.f, noise.f, env.f, lfo.f)

The minimum to make sound.  After this phase:

```forth
REQUIRE audio/osc.f
REQUIRE audio/env.f
440 0 44100 OSC-CREATE CONSTANT my-osc      \ 440 Hz sine
10 50 8000 100 44100 ENV-CREATE CONSTANT my-env
44100 16 1 4410 PCM-ALLOC CONSTANT my-buf   \ 100 ms buffer
my-buf my-osc OSC-FILL
my-buf my-env ENV-APPLY
\ my-buf now contains a 100 ms sine with ADSR envelope
```

**Est. ~600 lines Forth.**

### Phase 2 — Effects (fx.f, mix.f, chain.f)

After this phase, multi-voice mixing with effects:

```forth
REQUIRE audio/fx.f
REQUIRE audio/mix.f
REQUIRE audio/chain.f
2 4410 44100 MIX-CREATE CONSTANT my-mix
osc1-buf 0 my-mix MIX-INPUT!
osc2-buf 1 my-mix MIX-INPUT!
my-mix MIX-RENDER
my-mix MIX-MASTER my-chain CHAIN-PROCESS   \ EQ → reverb
```

**Est. ~800 lines Forth.**

### Phase 3 — Analysis (analysis.f)

Essential for interactive audio applications and data sonification:

```forth
REQUIRE audio/analysis.f
my-buf ANA-RMS ANA-DB .          \ "-12.3 dB"
my-buf 44100 ANA-PITCH-AUTO .    \ "440"
my-buf ANA-SPECTRUM              \ windowed FFT magnitude
```

**Est. ~400 lines Forth.**

### Phase 4 — Synthesis Engines (synth.f, fm.f, pluck.f)

Playable instruments:

```forth
REQUIRE audio/synth.f
0 1 44100 4410 SYNTH-CREATE CONSTANT pad
261 127 pad SYNTH-NOTE-ON          \ middle C
pad SYNTH-RENDER SPK-WRITE
```

**Est. ~500 lines Forth.**

### Phase 4b — Voice Management (poly.f, porta.f)

Polyphonic voice manager and monophonic portamento:

```forth
REQUIRE audio/poly.f
REQUIRE audio/porta.f

\ 4-voice polyphonic pad
4 0 0 44100 256 POLY-CREATE CONSTANT my-poly
440 INT>FP16 0x3C00 my-poly POLY-NOTE-ON
523 INT>FP16 0x3C00 my-poly POLY-NOTE-ON
659 INT>FP16 0x3C00 my-poly POLY-NOTE-ON
my-poly POLY-RENDER SPK-WRITE

\ Monophonic lead with glide
my-synth 0x2A66 PORTA-CREATE CONSTANT my-lead
440 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON
my-lead PORTA-RENDER SPK-WRITE
523 INT>FP16 0x3C00 my-lead PORTA-NOTE-ON   \ glides from A4→C5
my-lead PORTA-RENDER SPK-WRITE
```

`poly.f` — Polyphonic voice manager with quietest-steal allocation.
Wraps N identical `synth.f` voices.  Per-voice biquad filter state
save/restore via `SYNTH-SAVE-FILT` / `SYNTH-LOAD-FILT`.  Master
output buffer accumulates all voices.

`porta.f` — Monophonic portamento wrapper for any `synth.f` voice.
Exponential frequency glide between notes.  Snaps to target on
first note; glides on legato re-triggers.

**Est. ~300 lines Forth.**

### Phase 5 — I/O & Codec (speaker.f, mic.f, wav.f)

Real-time audio and file persistence:

```forth
REQUIRE audio/speaker.f
REQUIRE audio/wav.f
44100 SPK-INIT  SPK-START
my-buf SPK-WRITE                   \ play buffer
my-buf S" song.wav" WAV-WRITE      \ save to disk
S" song.wav" WAV-READ SPK-WRITE    \ load and play
```

**Est. ~400 lines Forth.**

### Phase 6 — Sequencing (seq.f, midi.f)

Pattern-based composition:

```forth
REQUIRE audio/seq.f
REQUIRE audio/midi.f
120 16 44100 SEQ-CREATE CONSTANT my-seq
60 100 4  0 my-seq SEQ-STEP!     \ step 0: C4, vel 100, gate 4
64 100 4  4 my-seq SEQ-STEP!     \ step 4: E4
67 100 4  8 my-seq SEQ-STEP!     \ step 8: G4
['] my-note-handler my-seq SEQ-CALLBACK!
my-seq SEQ-START
```

**Est. ~350 lines Forth.**

### Phase 7 — Sonification (param-map.f, data2tone.f, earcon.f, scene2audio.f)

Data → sound bridge:

```forth
REQUIRE render/sonification/earcon.f
REQUIRE render/sonification/data2tone.f
44100 EAR-SUCCESS SPK-WRITE       \ play success chime
sensor-data 64 SCALE-PENTATONIC 100 44100 D2T-SONIFY SPK-WRITE
```

**Est. ~500 lines Forth.**

### Total Estimate

| Phase | Files | Est. Lines |
|---|---|---|
| 0 (done) | pcm.f | 662 |
| 1 Generation | osc.f, noise.f, env.f, lfo.f | ~600 |
| 2 Processing | fx.f, mix.f, chain.f | ~800 |
| 3 Analysis | analysis.f | ~400 |
| 4 Synthesis | synth.f, fm.f, pluck.f | ~500 |
| 4b Voice Mgmt | poly.f, porta.f | ~300 |
| 5 I/O & Codec | speaker.f, mic.f, wav.f | ~400 (wav.f: 363 ✅) |
| 6 Sequencing | seq.f, midi.f | ~350 (seq: 352, midi: 371 ✅) |
| 7 Sonification | param-map.f, data2tone.f, earcon.f, scene2audio.f | ~500 |
| **Total** | **22 files** | **~4,500** |

---

## Design Decisions

### FP16 Throughout

All audio processing uses FP16 (IEEE 754 half-precision).  Rationale:

- Consistency with `math/fft.f`, `math/filter.f`, and the tile engine's
  FP16 mode.  Zero conversion cost between audio and spectral analysis.
- Tile engine processes 32 FP16 samples per 64-byte tile in one op.
  This is the SIMD width of the Megapad-64 — designing around it.
- FP16 range (±65504, 11-bit mantissa) is adequate for audio.
  Dynamic range ≈ 66 dB.  For mixing headroom, `F.SUM` uses FP32
  accumulation internally (the tile engine's ACC register is FP32).
- Where more precision is needed (e.g., phase accumulators, filter
  state), specific variables use 32-bit or 64-bit integers.

### Block-Based Processing

All modules process in blocks (one PCM buffer at a time), not
sample-by-sample.  Typical block = 256 or 512 frames.

- **Cache-friendly:** Consecutive memory access, tile-aligned.
- **Amortizes overhead:** One function call per block, not per sample.
- **Ring buffer friendly:** Push/pop whole blocks, not single samples.
- **Exception:** Karplus-Strong (`pluck.f`) uses per-sample feedback
  internally but exposes a block-level API.

### KDOS Ring Buffers for All Delay Lines

Every delay-based effect (delay, reverb combs, reverb allpasses,
chorus, Karplus-Strong) uses KDOS `RING` as its circular buffer.

- Already lock-protected (spinlock 4) — safe for ISR access.
- Already tested and proven in TCP RX buffers and run queues.
- Element size = 2 bytes (FP16 sample).  `2 N RING` creates an
  N-sample delay line.
- No custom circular buffer code in the audio library at all.

### HBW for Hot Path, XMEM for Cold

| Data | Location | Reason |
|---|---|---|
| Delay line rings | HBW | ISR accesses these at sample rate.  Must be zero-wait. |
| Wavetables | HBW | Tile-aligned for `F.MUL` / interpolation. |
| Active PCM work buffers | HBW | Tile ops read/write these every block. |
| WAV file data | XMEM | Loaded once, then sliced into work buffers. |
| Sample libraries | XMEM | Large, infrequently accessed. |
| MIDI note→Hz table | Dictionary | 256 bytes, read-only, accessed by note-on only. |

### Single-Voice Synth + Voice Management Layer

`synth.f` and `fm.f` are single-voice modules.  `poly.f` provides a
ready-made polyphonic manager with quietest-steal allocation and
per-voice biquad state context switching.  `porta.f` adds monophonic
glide for lead voices.

```forth
\ Polyphonic: 4 sine voices, quietest-steal
4 0 0 44100 256 POLY-CREATE CONSTANT pad
440 INT>FP16 0x3C00 pad POLY-NOTE-ON
pad POLY-RENDER SPK-WRITE
```

For custom allocation policies beyond quietest-steal, use the
single-voice API directly:

```forth
4 CONSTANT MAX-VOICES
CREATE voices  MAX-VOICES CELLS ALLOT
: VOICE-ALLOC  ( -- voice | 0 )   \ find first idle voice
    MAX-VOICES 0 DO
        voices I CELLS + @
        DUP ENV-DONE? IF UNLOOP EXIT THEN DROP
    LOOP 0 ;
```

### Timer ISR Sharing

Speaker and mic both want the timer ISR.  Options:

1. **Single ISR, two jobs:** The ISR pops speaker ring AND pushes mic
   ring in one interrupt.  Works if both run at the same sample rate.
2. **Separate timers:** If the hardware has a second timer (or if
   capture and playback rates differ), use different IVT slots.
3. **Phase 1 default:** Speaker-only.  Mic shares the same ISR when
   full-duplex is needed.

---

## Testing Strategy

### Unit Tests (per module)

Each module gets a `test_<module>.py` in `local_testing/` using the
existing emulator test infrastructure (snapshot boot, Forth evaluation,
memory readback).

| Module | Test Focus |
|---|---|
| osc.f | Waveform shape verification: sine zero-crossings, square duty cycle, saw linearity, wavetable interpolation accuracy |
| noise.f | Statistical properties: white noise mean ≈ 0, pink spectral slope, no DC offset |
| env.f | ADSR timing: attack/decay/release durations in frames, sustain level hold, gate on/off transitions, exponential curve shape |
| lfo.f | Output range = center ± depth, frequency accuracy, key-sync reset |
| fx.f | Delay: echo appears at correct offset.  Reverb: output longer than input.  Distortion: clipping at expected level.  EQ: frequency response spot-checks. Compressor: gain reduction above threshold |
| mix.f | N-channel sum correctness, pan law spot-checks (center = equal L/R), mute silences channel, master gain scales output |
| chain.f | Effects applied in order, bypass skips slot, clear removes all |
| analysis.f | Known-frequency sine → correct pitch.  Known-tempo click track → correct BPM.  RMS of constant signal = expected value |
| synth.f | Note-on produces output, note-off decays to silence, filter cutoff affects spectrum |
| fm.f | Modulation index 0 = pure sine, increasing index adds sidebands |
| pluck.f | Output decays over time, pitch matches requested frequency |
| wav.f | Write → read round-trip: PCM data identical, header fields correct |
| seq.f | Steps fire at correct frame positions, BPM change adjusts timing, swing offsets even steps |
| midi.f | Encode → parse round-trip, running status, note↔Hz conversion accuracy |
| speaker.f | Ring fill → ISR drain → DAC writes (verified via emulator device spy) |
| mic.f | ADC reads → ring fill → user read-back |
| param-map.f | Linear/log/exp mapping spot-checks, scale quantization |
| data2tone.f | Output length = n × note_ms, pitch range within specified bounds |
| earcon.f | Each earcon returns non-silent buffer of expected duration |
| scene2audio.f | DOM with known structure produces audio with expected duration and pitch ordering |

### Integration Tests

| Test | What It Validates |
|---|---|
| Osc → envelope → speaker | Full playback pipeline: generation → shaping → I/O |
| Synth → mixer → effects → speaker | Multi-voice with processing chain |
| WAV read → analysis → data | Load file, extract pitch/tempo |
| Sequencer → FM synth → speaker | Pattern-driven synthesis |
| Data array → data2tone → speaker | Sonification end-to-end |
| DOM → scene2audio → speaker | Render pipeline audio backend |

### Spectral Verification

For waveform and effects tests, compare output FFT magnitude spectrum
against expected shape:

- Pure sine → single peak at fundamental
- Square wave → odd harmonics decaying as 1/n
- Low-pass filter → attenuation above cutoff
- Reverb → extended decay tail in time domain

Use `math/fft.f` directly in test code for spectral checks.

### Performance Benchmarks

- Block processing throughput: frames/second for each module
- ISR latency: cycles per interrupt (must be < timer period)
- Full pipeline: osc + filter + env + mix + reverb + speaker per block
- Tile engine utilization: tile ops per block vs. scalar fallback
