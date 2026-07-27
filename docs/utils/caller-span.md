# akashic-caller-span — Checked Caller-Managed Memory

`akashic/utils/caller-span.f` provides a protocol-neutral boundary for
qualifying complete caller-managed byte spans:

```forth
REQUIRE utils/caller-span.f

CALLER-SPAN-STATUS         ( address length -- status )
CALLER-SPAN-STATUS-VALID?  ( status -- flag )
```

The module captures the BIOS word of the same name, owns no mutable state,
and does not inspect or mutate the named bytes. It validates every returned
BIOS status. A BIOS exception or undocumented result is normalized to
`CALLER-SPAN-S-PLATFORM`, allowing status-returning libraries to remain
fail-closed without mistaking a platform failure for malformed caller input.

## Statuses

| Constant | Value | Meaning |
|---|---:|---|
| `CALLER-SPAN-S-OK` | 0 | The complete span satisfies the caller-managed physical geometry policy. |
| `CALLER-SPAN-S-RANGE` | 2 | A nonempty span is null, uses a signed-negative cell, wraps, crosses an advertised memory window, or lies outside every advertised window. |
| `CALLER-SPAN-S-PROTECTED` | 3 | A Bank 0 span intersects the static BIOS/private footprint, live stacks, or the result cell. |
| `CALLER-SPAN-S-PLATFORM` | 4 | The BIOS threw or returned a value outside its documented `0`, `2`, and `3` vocabulary. |

`CALLER-SPAN-STATUS-VALID?` accepts exactly these four public values. The gap
at status 1 is intentional: it preserves the architectural BIOS values
without giving an undocumented result a valid Akashic meaning.

## Span policy

Zero length is unconditional OK and ignores the address, including null and
signed-negative addresses. A nonempty span must have nonnegative address and
length cells, must not be null or wrap, and must fit wholly in one physical
window advertised by the platform: Bank 0, external memory, HBW memory, or
VRAM.

Bank 0 is further restricted to `[dict_free, caller-DSP-8)`. The lower bound
excludes the complete static BIOS and private-state footprint. The upper
bound excludes live data and return stacks and reserves the result cell.
External, HBW, and VRAM spans are accepted on geometry alone when their
advertised window is nonempty.

The single boundary is intentionally suitable for both reads and writes. It
answers whether a span denotes ordinary memory that may be caller-managed,
not whether every named byte is physically readable. Consequently it rejects
readable static BIOS storage as PROTECTED instead of providing a looser input
policy.

Success is not an allocator capability. It does not establish who owns the
bytes, whether they are mutable or initialized, how long they remain live, or
whether they overlap another application object. Public APIs must still
validate their own object layouts, capacities, lifetimes, and alias rules
before reading or publishing.

## Mapping into another status vocabulary

Callers should preserve the distinction long enough to map it deliberately:

- RANGE describes invalid physical geometry.
- PROTECTED describes a platform-reserved Bank 0 intersection.
- PLATFORM describes an architectural or BIOS contract failure and should
  normally map to the caller's internal/platform failure, not ordinary
  malformed input.

The utility itself performs no allocation, locking, publication, or cleanup.
