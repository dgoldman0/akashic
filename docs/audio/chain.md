# akashic-audio-chain — Effect-Chain Routing for KDOS / Megapad-64

An ordered list of processing slots that run a PCM buffer through a
series of audio effects.  Each slot holds an execution token for a
`( buf desc -- )` effect-process word, a descriptor pointer, and a
bypass flag.

```forth
REQUIRE audio/chain.f
```

`PROVIDED akashic-audio-chain` — safe to include multiple times.
Depends on `akashic-audio-pcm`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation & Destruction](#creation--destruction)
- [Slot Management](#slot-management)
- [Processing](#processing)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Slot array** | Up to 8 slots per chain.  Each slot is 24 bytes (xt + desc + bypass). |
| **Serial processing** | `CHAIN-PROCESS` iterates slots in order.  Each effect modifies the buffer in-place before the next slot sees it. |
| **Bypass** | Any slot can be bypassed without removing it, allowing real-time A/B comparisons. |
| **Effect-agnostic** | The chain doesn't know about specific effect types — any word with `( buf desc -- )` can be installed. |
| **Variable-based scratch** | Internal `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `CHAIN-`.  Internal: `_CH-`.  Fields: `CH.xxx`. |

---

## Memory Layout

### Chain Descriptor (2 cells = 16 bytes)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     n-slots   — maximum number of slots (integer)
+8      8     slots     — pointer to slot array
```

### Slot (3 cells = 24 bytes each)

```
Offset  Size  Field
──────  ────  ──────────
+0      8     process-xt — execution token for ( buf desc -- ), or 0
+8      8     desc       — effect descriptor pointer
+16     8     bypass     — 0 = active, 1 = bypassed
```

---

## Creation & Destruction

### CHAIN-CREATE

```forth
CHAIN-CREATE  ( n-slots -- chain )
```

Allocates a chain with `n-slots` effect slots (clamped to 1–8).
All slots are initially empty (xt = 0).

### CHAIN-FREE

```forth
CHAIN-FREE  ( chain -- )
```

Frees the chain descriptor and slot array.  Does **not** free the
individual effect descriptors that were installed — the caller owns
those.

---

## Slot Management

### CHAIN-SET!

```forth
CHAIN-SET!  ( xt desc slot# chain -- )
```

Installs an effect at the given slot number (0-indexed).  The `xt`
must be the execution token of a `( buf desc -- )` word.  The slot
is automatically marked active (bypass = 0).

### CHAIN-BYPASS!

```forth
CHAIN-BYPASS!  ( flag slot# chain -- )
```

Sets the bypass flag for a slot:
- `1` = bypassed (skipped during `CHAIN-PROCESS`)
- `0` = active (processed normally)

### CHAIN-CLEAR

```forth
CHAIN-CLEAR  ( chain -- )
```

Removes all effects from the chain.  Resets every slot to empty
(xt = 0, desc = 0, bypass = 0).

### CHAIN-N

```forth
CHAIN-N  ( chain -- n )
```

Returns the maximum number of slots in the chain.

---

## Processing

### CHAIN-PROCESS

```forth
CHAIN-PROCESS  ( buf chain -- )
```

Runs the PCM buffer through all active slots in order (slot 0 first,
then slot 1, etc.).  For each slot:

1. If `xt` = 0, skip (empty slot).
2. If `bypass` ≠ 0, skip (bypassed slot).
3. Otherwise, execute `buf desc xt EXECUTE`.

The buffer is modified in-place by each effect, so slot N sees the
output of slot N-1.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `CHAIN-CREATE` | `( n -- chain )` | Create chain with n slots |
| `CHAIN-FREE` | `( chain -- )` | Free chain (not effects) |
| `CHAIN-SET!` | `( xt desc slot# chain -- )` | Install effect |
| `CHAIN-BYPASS!` | `( flag slot# chain -- )` | Bypass/enable slot |
| `CHAIN-PROCESS` | `( buf chain -- )` | Run buffer through chain |
| `CHAIN-CLEAR` | `( chain -- )` | Remove all effects |
| `CHAIN-N` | `( chain -- n )` | Get slot count |

---

## Cookbook

### Basic: Single Distortion Effect

```forth
\ Create a 100-frame buffer, generate a tone, apply hard-clip distortion
100 44100 16 1 PCM-ALLOC  CONSTANT mybuf
0x5140 0 44100 OSC-CREATE  CONSTANT myosc  \ 440 Hz sine
mybuf myosc OSC-FILL

0x4000 1 FX-DIST-CREATE  CONSTANT mydist  \ hard clip, drive=2.0
1 CHAIN-CREATE  CONSTANT mychain
['] FX-DIST-PROCESS mydist 0 mychain CHAIN-SET!

mybuf mychain CHAIN-PROCESS   \ mybuf now has clipped audio
```

### Two Effects in Series

```forth
\ Delay → soft-clip distortion
10 44100 FX-DELAY-CREATE  CONSTANT mydelay
0x3C00 0 FX-DIST-CREATE   CONSTANT mydist   \ soft clip, drive=1

2 CHAIN-CREATE  CONSTANT mychain
['] FX-DELAY-PROCESS mydelay 0 mychain CHAIN-SET!
['] FX-DIST-PROCESS  mydist  1 mychain CHAIN-SET!

mybuf mychain CHAIN-PROCESS
```

### Toggle Bypass

```forth
\ Bypass slot 0 (delay)
1 0 mychain CHAIN-BYPASS!
mybuf mychain CHAIN-PROCESS   \ only distortion runs

\ Re-enable slot 0
0 0 mychain CHAIN-BYPASS!
```
