# One-shot audio output

`audio/output.f` is Akashic's generic boundary for the MegaPad-64 one-shot
audio device at `0xFFFFFF0000000C00`. It is a board driver, not a Sound Lab
special case: any trusted Akashic component running on core 0 can submit
bounded mono or stereo PCM through the same contract.

The device consumes interleaved signed PCM16 little-endian. It always exposes
a deterministic capture capability; an audible host or hardware sink is a
separate optional capability. This distinction keeps tests meaningful on a
headless machine: successful capture proves the exact bytes, rate, channel
count, and frame count presented at the device boundary, while
`AUDIO-OUT-SINK?` says whether this machine can also make them audible.

## Public API

```forth
AUDIO-OUT-PRESENT?       ( -- flag )
AUDIO-OUT-STATUS         ( -- status-bits )
AUDIO-OUT-CAPS           ( -- capability-bits )
AUDIO-OUT-GENERATION     ( -- u32 )
AUDIO-OUT-ERROR          ( -- device-error )
AUDIO-OUT-BUSY?          ( -- flag )
AUDIO-OUT-DONE?          ( -- flag )
AUDIO-OUT-PLAYING?       ( -- flag )
AUDIO-OUT-CAPTURE?       ( -- flag )
AUDIO-OUT-SINK?          ( -- flag )

AUDIO-OUT-SUBMIT-S16     ( addr frames rate chans timeout-ms -- status )
AUDIO-OUT-SUBMIT-FP16    ( buf timeout-ms -- status )
AUDIO-OUT-STOP           ( -- status )
AUDIO-OUT-CLEAR          ( -- status )
```

`AUDIO-OUT-SUBMIT-S16` accepts raw interleaved signed-PCM16 bytes. It copies
the source into driver-owned staging, so the caller may reuse or free its
source after the call returns. `AUDIO-OUT-SUBMIT-FP16` accepts an Akashic PCM
descriptor with 16-bit mono or stereo storage and converts every FP16 sample
through the canonical `PCM-FP16>S16` policy. Both calls are synchronous from
the caller's perspective and are currently restricted to core 0. This is a
deliberate allocator boundary: staging uses KDOS `ALLOCATE`/`FREE`, which are
not worker-core services. Calls from another core return `AUDIO-OUT-S-CORE`
before acquiring the guard, touching MMIO, or allocating. The lock still
matters because independent core-0 tasks may share the device.

Status, capability, generation, and error queries are lock-free snapshots and
may be made from any core.

Rates from 8,000 through 192,000 Hz and one or two channels are accepted. A
single submission is limited to 1 MiB, matching the device capture limit.
Zero-length buffers, unsupported shapes, negative timeouts, and spans above
the limit fail before DMA is armed.

## Driver results

| Constant | Value | Meaning |
|---|---:|---|
| `AUDIO-OUT-S-OK` | 0 | Device accepted and completed the capture |
| `AUDIO-OUT-S-ABSENT` | 1 | Present bit was not observable |
| `AUDIO-OUT-S-INVALID` | 2 | Invalid pointer, shape, rate, or timeout |
| `AUDIO-OUT-S-TOO-LARGE` | 3 | PCM span exceeds 1 MiB |
| `AUDIO-OUT-S-BUSY` | 4 | Driver/device is already owned or an old DMA span remains live |
| `AUDIO-OUT-S-ALLOC` | 5 | Driver staging allocation failed |
| `AUDIO-OUT-S-DEVICE` | 6 | Device rejected or failed the request; inspect `AUDIO-OUT-ERROR` |
| `AUDIO-OUT-S-TIMEOUT` | 7 | Deadline expired and the driver issued `STOP` |
| `AUDIO-OUT-S-UNSUPPORTED` | 8 | Present device lacks deterministic capture |
| `AUDIO-OUT-S-IO` | 9 | A catchable MMIO, allocator, or conversion exception occurred |
| `AUDIO-OUT-S-CORE` | 10 | A mutating call was made from outside core 0 |

Device error values are `AUDIO-OUT-E-NONE`, `-BUSY`, `-FORMAT`, `-CHANNELS`,
`-RATE`, `-FRAMES`, `-CAPACITY`, `-MEMORY`, and `-SINK` (values 0 through 8).
A sink failure does not erase the emulator's deterministic capture, but the
submission still reports `AUDIO-OUT-S-DEVICE` because the requested output
path was not fully successful.

Status bits are `AUDIO-OUT-F-BUSY`, `-DONE`, `-ERROR`, `-PLAYING`, and
`-PRESENT`. Capability bits are `AUDIO-OUT-CAP-CAPTURE` and
`AUDIO-OUT-CAP-SINK`. `AUDIO-OUT-GENERATION` increments for every completed
capture and is preserved by `CLEAR` until board reset.

## Ownership and concurrency

The audio engine and its staging block are shared board resources. A blocking
Akashic guard serializes configuration, submission, and cleanup across core-0
tasks. Guard waiting and completion polling call the scheduler's yielding
primitives; the driver does not keep preemption disabled while it converts a
buffer or waits for completion. This is task-safe serialization, not a claim
that the KDOS allocator is worker-safe.

Staging remains allocated while `STATUS.BUSY` is set. Normal completion and a
device error release it immediately. On timeout, the driver issues `STOP`; a
device that clears `BUSY` has returned ownership and the block is released. If
a future or faulty implementation remains busy or disappears while DMA is
armed, the driver conservatively retains at most 1 MiB rather than returning
potentially live memory to the allocator. A later successful `STOP`, `CLEAR`,
or submission attempt reaps that block once the device reports it idle.

Body execution, reaping, and guard release are separate caught phases. Thus a
catchable conversion, MMIO, or allocator exception is reported as
`AUDIO-OUT-S-IO`, and a cleanup exception cannot skip guard release. Driver
state is cleared before entering `FREE`, preventing a throwing allocator from
leaving a stale pointer available for a later double-free. The in-flight flag
is set before the submit command is written because an MMIO implementation may
begin capture synchronously inside that write.

`timeout-ms` is not a hard wall-clock deadline for the entire call. The same
budget bounds guard acquisition and, after the submit command returns,
completion polling. It cannot preempt the MMIO command write itself. In the
current emulator that command snapshots PCM and invokes an optional host sink
synchronously, so a slow or stuck sink can overrun the requested timeout before
guest code regains control. The timeout remains useful for contention and for
future asynchronous hardware that leaves `BUSY` asserted after command return.

The presence probe catches Forth-representable MMIO faults and otherwise
treats a missing present bit as absence. A target whose hardware bus faults
cannot be surfaced through `CATCH` must provide the platform's normal
unmapped-MMIO zero behavior.

## Register contract

| Offset | Width | Register |
|---:|---:|---|
| `+0x00` | 8 | Command: submit=1, stop=2, clear=3 |
| `+0x01` | 8 | Status bits |
| `+0x02` | 8 | Format (`1` = signed PCM16 little-endian) |
| `+0x03` | 8 | Channels (1 or 2) |
| `+0x04` | 32 | Sample rate in Hz |
| `+0x08` | 64 | DMA source address |
| `+0x10` | 32 | Frame count |
| `+0x14` | 32 | Capture generation |
| `+0x18` | 8 | Device error |
| `+0x19` | 8 | Capability bits |

The emulator snapshots guest PCM before invoking an optional host sink. A
physical implementation should preserve the same ownership and register
semantics while replacing that snapshot path with bounded DMA and an audio
transport such as I2S/codec hardware.
