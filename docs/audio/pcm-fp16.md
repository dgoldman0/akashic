# akashic-audio-pcm-fp16 — FP16 / Signed PCM16 Conversion

Canonical scalar conversion policy for the Akashic synthesis format:
normalized IEEE FP16 samples stored in 16-bit PCM slots.  File codecs and
audio devices can share these words without depending on one another.

```forth
REQUIRE audio/pcm-fp16.f
```

The module declares both the FP16 helper and FP32 arithmetic dependencies it
uses internally; callers do not need to preload another audio module.

## API

```forth
PCM-FP16>S16  ( fp16 -- s16 )
```

Converts normalized FP16 to signed PCM16. Interior samples use the exactly
representable FP16 scale `32768`; explicit endpoint policy maps `+1.0` to
`32767` and `-1.0` to `-32768`. Finite values outside that range saturate. Infinities
also saturate; NaN maps to `0` so an invalid synthesis value cannot become a
full-scale device or file sample.

```forth
PCM-S16>FP16  ( s16 -- fp16 )
```

Converts signed PCM16 to normalized FP16. The input may be sign-extended or
the raw unsigned value returned by `W@`; the word canonicalizes the low 16
bits before conversion. It converts before dividing by `32768`, preserving
the exact `±1` PCM landmarks as FP16 subnormals instead of rounding them to
silence.

These conversions are intentionally scalar and pure. Buffer traversal,
channel layout, and ownership remain the responsibility of `audio/pcm.f`.
