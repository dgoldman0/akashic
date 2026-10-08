# Sound Lab

Sound Lab is a bounded signal laboratory for Desk. It renders an exact mono
FP16 PCM buffer, runs Akashic's native analysis over that buffer, displays a
compact waveform and frequency landmarks, submits the current render through
the public AudioOut driver, and atomically publishes a standard PCM WAV file at
`/soundlab.wav`.

**Provider:** `akashic-tui-soundlab`

## Current Scope

The first version intentionally qualifies the audio substrate before promising
a music workstation. A signal has four controls:

| Control | Range |
|---|---|
| Waveform | sine, square, saw, triangle, pulse |
| Frequency | 40-2000 Hz |
| Amplitude | 0-100 percent |
| Duration | 100-2000 ms |

All renders are 8 kHz, 16-bit-storage, mono FP16 PCM. The fixed sample rate and
two-second ceiling keep CPU, memory, analysis, and output sizes predictable: a
render contains at most 16,000 frames and its WAV is at most 32,044 bytes.
Changing a control makes the existing render visibly stale. Rendering is
transactional: Sound Lab constructs and analyzes a candidate buffer and only
replaces the prior PCM after every stage succeeds. A failed render keeps the
previous buffer and reports the failure.

The display reports peak amplitude and frame, RMS, DC offset, zero crossings,
clipped samples, autocorrelation pitch estimate, and spectral centroid. The
waveform uses an immutable UDG series containing every rendered PCM frame,
converted through the same `PCM-FP16>S16` policy used by audio and WAV output.
The uniform sample interval is exactly 125 microseconds, beginning at the
render's own zero origin. No frames are dropped before the shared ordinary
waveform projector draws the CELL view. The compact frequency line
marks the pitch estimate (`P`) and centroid (`C`); it is deliberately described
as landmarks rather than a full spectrum plot.

## Playback Boundary

Sound Lab requires `audio/output.f` and submits only the current valid render
with `AUDIO-OUT-SUBMIT-FP16`. It supplies a five-second wait that separately
bounds guard acquisition and post-command device polling. That wait cannot
preempt the current emulator's synchronous PCM snapshot or host callback, so
`soundlab.play` deliberately advertises no hard capability deadline. This is
an explicit boundary for a later agent-tooling pass, not a fictional 12-second
guarantee. Sound Lab contains no private MMIO or host calls.

The device state is always stated explicitly:

- **absent** means no AudioOut device is mapped;
- **deterministic capture only** means playback successfully records exact PCM
  for tests and tooling but produces no audible sound; and
- **audible sink** means the same deterministic capture is also accepted by a
  host audio sink.

Capture-only success is never presented as audible playback. Driver failures
are reported by stable result name, while device failures also preserve the
device-specific error code. The bounded analysis and playback-status summaries
include the current status bits, capture generation, last play result,
last-play generation, and device error. If an audible submission leaves a host
voice active, Sound Lab records its generation and stops it on shutdown only
when that generation is still the one it owns. It adopts a generation even
when host submission reports failure, because a callback can fail after
starting a voice and failed release must not become an orphaned sound.

## Persistence and Ownership

`Save WAV` encodes the current render into caller-owned scratch memory and
publishes `/soundlab.wav` with `VREPL` staged replacement. Interrupted
publication is recovered on activation. Ambiguous or corrupt recovery blocks
later saves instead of overwriting the output. Sound Lab owns that fixed
artifact path by convention; this does not claim general VFS write mediation
against arbitrary trusted code.

A successful render is considered unsaved until WAV publication succeeds.
Closing with an unsaved render asks for confirmation. Shutdown detaches the
panel before releasing regions and frees the PCM, prompt, and WAV scratch
allocations, so close and relaunch create a fresh instance without borrowing
state from the previous activation.

## Keyboard Use

| Key | Action |
|---|---|
| Up / Down | Select a signal control |
| Left / Right | Adjust the selected control |
| Enter or F2 | Edit an exact numeric value; waveform cycles |
| F5, `r`, or Space | Render and analyze |
| `s` or Ctrl+S | Save `/soundlab.wav` |
| `p` | Submit the current valid render to AudioOut |
| Ctrl+Q | Quit standalone Sound Lab |

The direct-TUI panel derives its geometry on every paint. Narrow or short Desk
tiles retain the controls and metrics; larger tiles add the sampled waveform
and frequency landmark line.

The waveform retains its existing rectangle: row 11, column 2, width
`max(panel_width - 4, 4)` and height
`min(max(panel_height - 17, 3), 12)`, shown when panel height is at least 18.
Its signed sample range is -32768..32767, with a zero line at zero. The title
and unrendered hint remain ordinary text; rendered trace and zero-line CELL
painting belong to the shared data-graphics widget. The complete graph has
13 metric objects, plus one waveform object and one series when shown.
Two caller-owned graph banks each reserve at most 130,176 bytes. A separate
128,000-byte caller-owned conversion scratch is reused during rebuilding
and is never bound or captured. The exact maximum is 388,352 bytes for the
two graph banks and sample scratch; the smaller builder, summary and widget
state are additional. Graphs are copied and rebound only after successful
construction, so no allocation is added to the render-to-view transition.

The four parameter rows are ordinary `FLD-*` widgets backed by immutable
`UFLD` models. Their rows remain 3..6, labels start at column 2, and the value
slot starts at `max(width - 16, 18)` with width
`max(width - value_column - 2, 1)`. INTEGER values remain right aligned;
the waveform is a CHOICE with its label left aligned inside that same slot.
The selected and normal colors are unchanged. When that value slot does not
fit, label and value take half the panel each: the value slot starts at
`width / 2 + 1` with width `width - value_column - 1`. A panel too narrow even
for that, under five columns, shows no settings.

A value-slot click requests the existing exact numeric prompt or cycles the
waveform; the label itself is not an activation target. Wheel and ordinary
typed adjustment events use the same application mutation path as Left/Right.
One signed 64-bit adjustment is handled once: integer fields clamp without
overflow and waveform steps wrap across the five declared OSC choices. The
application still owns every edit and validation message. Selection changes
preserve content revision; parameter changes invalidate the prior render and
advance the field content revision. Models are rebuilt in the inactive one
of two caller-owned banks before rebinding. Before each input dispatch, dirty
models are refreshed, so a full-count adjustment carrying an older content
revision is refused even when two inputs arrive before a repaint. No terminal
API is used by the applet.

## Agent Capabilities

Sound Lab exposes owner-side capabilities because the current audio and VFS
libraries are deliberately non-reentrant. Effects remain explicit so Agent's
normal approval policy can distinguish observation, mutation, persistence, and
external device use.

| Capability | Effect | Purpose |
|---|---|---|
| `soundlab.shape.set` | mutate | Select a canonical lowercase waveform name |
| `soundlab.frequency.set` | mutate | Set frequency in Hz |
| `soundlab.amplitude.set` | mutate | Set amplitude percent |
| `soundlab.duration.set` | mutate | Set duration in milliseconds |
| `soundlab.render` | mutate | Render current settings and return analysis |
| `soundlab.analysis` | observe | Read settings, render state, metrics, and boundaries |
| `soundlab.wav.save` | persist | Atomically publish the current WAV |
| `soundlab.output` | observe | Return `vfs:/soundlab.wav` as a resource |
| `soundlab.playback.status` | observe | Read device mode, status, generation, and last result |
| `soundlab.play` | external | Submit the current valid render to AudioOut |

Parameter setters do not implicitly render. This makes a multi-step agent
workflow predictable: configure the desired values, invoke `soundlab.render`,
inspect `soundlab.analysis`, and only then request `soundlab.play` or
`soundlab.wav.save`. `soundlab.playback.status` remains an observe-only,
idempotent resource; `soundlab.play` carries only the `external` effect so Desk
can apply its approval policy independently of mutation and persistence. The
analysis result is bounded line-oriented text, making it useful to both Agent
and deterministic test harnesses without transferring the binary PCM through
the capability bus.

## Public Words

| Word | Stack | Purpose |
|---|---|---|
| `SOUNDLAB-ENTRY` | `( desc -- )` | Fill an application descriptor for Desk |
| `SOUNDLAB-RUN` | `( -- )` | Run Sound Lab in the shared app shell |

## Qualification Direction

Sound Lab is the UI consumer for the audio-library qualification work. Its
contract should be exercised with canonical silence, impulse, sine, oscillator
continuity, native-versus-host analysis, AudioOut capture, and WAV round-trip
fixtures. A later full spectrum view should use a public bounded spectrum API
rather than reach into the analyzer's private FFT scratch arrays.
