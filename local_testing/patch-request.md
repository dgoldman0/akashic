# Tile Engine BIOS Patch Request

**From:** Akashic library team
**Date:** 2026-02-27
**Re:** Missing Forth words for tile engine hardware instructions,
       plus one C++ accelerator bug

---

## Summary

The tile engine has **30 hardware instructions**.  The BIOS exposes
Forth words for 20 of them.  **10 instructions are unreachable from
Forth** without inline assembly.  We also found a bug in the C++
accelerator where integer-mode TFMA silently computes a dot product
instead of element-wise FMA.

We need these for the Akashic render pipeline (tile-accelerated
pixel compositing) and general-purpose integer SIMD.

---

## 1. Missing Forth Words (10 instructions)

### Priority A — Needed now for compositing / DSP

| Proposed Word | Asm Mnemonic | Stack | Description |
|---|---|---|---|
| `TVSHR` | `t.vshr` | `( -- )` | Per-lane vector right shift: `dst[i] = src0[i] >> src1[i]`. Honors TMODE signed (arithmetic) and rounding (bit 6) flags. Essential for fixed-point divide-by-255. |
| `TVSHL` | `t.vshl` | `( -- )` | Per-lane vector left shift: `dst[i] = src0[i] << src1[i]`. |
| `TPACK` | `t.pack` | `( -- )` | Narrow elements to half width (u16→u8, u32→u16, etc.) with optional saturation. For compositing: pack blended u16 results back to u8 pixels. |
| `TUNPACK` | `t.unpack` | `( -- )` | Widen elements to double width (u8→u16, u16→u32, etc.) with sign/zero extension. For compositing: widen u8 pixels to u16 before multiply. |
| `TVSEL` | `t.vsel` | `( -- )` | Per-lane conditional select: `dst[i] = src1[i] != 0 ? src0[i] : dst[i]`. Mask-based blend for coverage skip (zero-coverage lanes). |

### Priority B — Useful, not blocking

| Proposed Word | Asm Mnemonic | Stack | Description |
|---|---|---|---|
| `TVCLZ` | `t.vclz` | `( -- )` | Per-lane count leading zeros. Useful for fixed-point normalization and log2 approximation. |
| `TSHUFFLE` | `t.shuffle` | `( -- )` | Lane permutation: `dst[i] = src0[index[i]]` where index tile = TSRC1. Enables channel deinterleave (RGBA → separate R,G,B,A tiles). |
| `TMOVBANK` | `t.movbank` | `( -- )` | Bank-to-bank tile copy (TSRC0 → TDST). Faster than byte-by-byte TILE-COPY. |
| `TRROT` | `t.rrot` | `( -- )` | Row/column rotate or mirror within tile. Control byte specifies direction and amount. |
| `TLOADC` | `t.loadc` | `( -- )` | Load tile from cursor address (SB/SR/SC/SW registers). |

All follow the existing BIOS pattern: no stack arguments, just fire
the tile instruction.  One line each in bios.asm:

```asm
w_tvshr:   t.vshr   ret.l
w_tvshl:   t.vshl   ret.l
w_tvclz:   t.vclz   ret.l
w_tvsel:   t.vsel   ret.l
w_tpack:   t.pack   ret.l
w_tunpack: t.unpack ret.l
w_tshuffle: t.shuffle ret.l
w_tmovbank: t.movbank ret.l
w_trrot:   t.rrot   ret.l
w_tloadc:  t.loadc  ret.l
```

Plus the standard dictionary header for each (link, count byte,
name string, code pointer).

---

## 2. Bug: C++ Accelerator Integer FMA (mp64_accel.cpp)

**File:** `accel/mp64_accel.cpp`, tile TMUL dispatch

**Symptom:** `TFMA` (`t.fma`, TMUL funct=4) in integer mode silently
computes a DOT product (scalar reduction → ACC) instead of the
correct element-wise `dst[i] = src0[i] * src1[i] + dst[i]`.

Works correctly in FP16 mode (Python fallback handles it).
Breaks in U8/U16/U32/U64 modes (C++ path intercepts funct=4).

**Root cause:** Line ~1291:
```cpp
if (funct == 1 || funct == 4) {  // DOT, DOTACC
```

This groups funct=4 (FMA) with funct=1 (DOT).  FMA is **not** a
reduction — it's element-wise multiply-add into the destination tile.

**Fix:** Change to:
```cpp
if (funct == 1) {  // DOT only
```

And add funct=4 to the Python-fallback set at ~line 1310:
```cpp
if (funct == 2 || funct == 3 || funct == 4 || funct == 5 || funct == 6) {
```

Or implement integer FMA correctly in C++ (matching the Python
`_tile_fma` logic at megapad64.py ~line 2228).

**Impact:** Any Forth code using `TFMA` in integer mode gets wrong
results.  The Python fallback is correct but unreachable when the
C++ accelerator is active.

---

## 3. Nice-to-have: Integer Mode Convenience Words

The BIOS defines `FP16-MODE` and `BF16-MODE` as single-instruction
wrappers.  We defined the integer equivalents in userland Forth
(`U8-MODE`, `I8-MODE`, etc.) using `n TMODE!`, which works but
costs an extra stack push vs. a hardcoded BIOS word.

Not blocking — just noting that if there's room in the BIOS
dictionary, matching convenience words would be welcome:

```asm
; U8-MODE ( -- )
w_u8_mode:  ldi r0, 0x00  csrw 0x14, r0  ret.l
; I8-MODE ( -- )
w_i8_mode:  ldi r0, 0x10  csrw 0x14, r0  ret.l
; U8S-MODE ( -- )  saturating
w_u8s_mode: ldi r0, 0x20  csrw 0x14, r0  ret.l
; (etc. for U16, I16, U32, I32, U64, I64 variants)
```

---

## Context

We're building tile-accelerated pixel compositing for the Akashic
render engine.  The compositing inner loop does per-pixel sRGB
alpha blending.  With U8 mode (64 lanes) we can process 16 RGBA
pixels per tile instruction.  The critical path needs:

1. **TUNPACK** — widen u8 channel bytes to u16 before multiply
2. **TMUL** — channel × coverage (already in BIOS, works)
3. **TVSHR** — divide by 255 via `(x + 128) >> 8` approximation
4. **TPACK** — narrow u16 result back to u8
5. **TVSEL** — skip zero-coverage lanes without branching

Without these, we fall back to the scalar per-pixel path (~30 Forth
words per pixel).  With them, the blend becomes ~5 tile instructions
for 16 pixels.
