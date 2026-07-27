# akashic-entropy — Generic Checked Hardware Entropy

`math/entropy.f` is Akashic's protocol-neutral boundary for cryptographic
random bytes. It has no AT Protocol, Streams, OAuth-flow, or application
policy, and owns no mutable state.

```forth
REQUIRE akashic/math/entropy.f
```

## API

```forth
ENTROPY-READY?        ( -- flag )
ENTROPY-FILL          ( destination length -- status )
ENTROPY-STATUS-VALID? ( status -- flag )
```

The Akashic words delegate to the checked BIOS entropy contract. The library
does not hardcode a device address, read `RANDOM8`, maintain a second guard,
or recreate hardware health policy in Forth.

`ENTROPY-READY?` returns canonical true only when the platform source is
currently usable. It is diagnostic, not a reservation: callers must still
honor the result of `ENTROPY-FILL`.

`ENTROPY-FILL` returns:

| Status | Meaning |
|---|---|
| `ENTROPY-S-OK` | The complete destination was filled and remained usable through the final check. |
| `ENTROPY-S-UNAVAILABLE` | The source was initially unavailable or a detected post-start loss caused the entire admitted destination to be erased. |
| `ENTROPY-S-RANGE` | A nonempty destination was null, signed, wrapping, unadvertised, or crossed a physical-memory window. |
| `ENTROPY-S-PROTECTED` | A Bank 0 destination intersected the BIOS/private footprint, a live stack, or the returned-status cell. |

An empty request is a successful no-op and ignores its unused address.
Nonempty destinations must fit wholly in one platform-advertised writable
window. Geometry is a protection check rather than allocation ownership; the
caller remains responsible for passing a buffer it owns.

The BIOS requires exact hardware usability before every byte and after the
last byte. Initial unavailability does not publish. A health loss observed
after publication starts wipes the complete admitted destination before
returning `ENTROPY-S-UNAVAILABLE`.

One hardware limitation remains explicit. If usability changes in the narrow
interval after a successful status read but before its following data read,
the architectural bus fault cannot resume the interrupted Forth return chain
to perform cleanup. Akashic deliberately lets that fault propagate instead of
misreporting an ordinary status. Native source transitions caused by a
successful data read are observed by the following status check, including
after the final byte.

The seed register is deliberately outside this API. Supplemental caller
material cannot substitute for a healthy platform entropy source or recover a
latched failure.

## Example

```forth
CREATE key-material 32 ALLOT

key-material 32 ENTROPY-FILL
DUP ENTROPY-S-OK <> IF
    \ No key may be admitted. Handle the returned status.
THEN
DROP
```

Do not replace this boundary with `RANDOM`, `RANDOM8`, timestamps, TIDs,
counters, or caller-provided seeds when generating credentials or keys.
