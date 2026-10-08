# Structured status model

`akashic/tui/status-field-model.f` provides `akashic-tui-status-model`.
It defines a pointer-free, caller-owned status value. The model has no
terminal calls, input target, focus, or enabled state. Its rectangle is
intrinsically one row; the ordinary widget supplies its origin.

The caller chooses a nonzero stable key, a positive u32 width, an explicit
label split from zero through the width, severity `0..4` (neutral, info,
success, warning, error), and flags `USF-F-VISIBLE=1` and
`USF-F-EMPHASIZED=2`. No other flag bits are valid.

ABI 1 stores nine native u64 cells, then the exact label bytes, the exact
value bytes, and zero padding to an eight-byte boundary:

| Offset | Field |
| --- | --- |
| 0 | Exact total bytes |
| 8 | ABI, 1 |
| 16 | Stable key |
| 24 | Width in cells |
| 32 | Label columns |
| 40 | Severity |
| 48 | Flags |
| 56 | Label byte count |
| 64 | Value byte count |
| 72 | Label, then value, then zero padding |

Both strings are independently valid single-line Unicode-scalar UTF-8.
C0, DEL, C1, U+2028 and U+2029 are forbidden. A nonempty label needs a
positive label slot; a nonempty value needs a positive value slot. Both
strings may be empty. An empty label with a zero split represents a whole
value without parsing it. Text may exceed its assigned slot: drawing clips
within that slot and never reallocates its columns.

```forth
USF-BYTES        ( label-bytes value-bytes -- bytes|0 )
USF-INIT         ( key width split severity flags la lu va vu dst cap -- used status )
USF-INIT-DISPLAY ( key width split severity flags la lu va vu dst cap -- used status )
USF-VALIDATE     ( model bytes -- status )
USF-TEXT?        ( address bytes -- flag )
USF-DISPLAY-BYTES ( address bytes -- bytes status )
USF-STORAGE-DISJOINT? ( address bytes -- flag )
```

Statuses are `USF-S-OK=0`, `USF-S-UNSUPPORTED=1`,
`USF-S-CAPACITY=2`, and `USF-S-INVALID=3`. `USF-BYTES` returns zero
for invalid or overflowing lengths. Constructors require an aligned,
nonzero destination and reject wrapping spans, module-storage aliases,
destination overlap with either source string, malformed metadata, and
insufficient capacity before writing any destination byte. Failure returns
zero used bytes. Capacity may exceed the returned extent; bytes beyond that
extent remain unchanged. The two read-only source strings may overlap each
other. Empty strings do not dereference their address.

`USF-INIT` preserves valid strings exactly. `USF-INIT-DISPLAY` constructs a
canonical value from ordinary display text, substituting U+FFFD through
`UTF8-DECODE` and the Cc/Zl/Zp substitution used by ordinary `GR-DECODE` /
CELL drawing. This includes malformed maximal subparts, C0, DEL, C1 and
line separators; other scalars keep their ordinary text semantics.
Its byte measurement and copying agree and leave the
source unchanged. `USF-DISPLAY-BYTES` permits measuring that expansion
without an intermediate text buffer. Neither constructor is a measure-only
call; use the sizing words first.

`USF-BYTES@`, `USF-ABI@`, `USF-KEY@`, `USF-WIDTH@`,
`USF-LABEL-COLS@`, `USF-SEVERITY@`, `USF-FLAGS@`,
`USF-LABEL-BYTES@`, and `USF-VALUE-BYTES@` read the corresponding field
from an already validated model. `USF-LABEL@` and `USF-VALUE@` return
borrowed `(address bytes)` pairs. The named `USF-*-OFFSET` constants and
`USF-HEADER-SIZE=72` describe the same layout.

The model owns no allocation. Keep a bound model immutable until its widget
is rebound or unbound. Build changes into a separate caller buffer before
rebinding. Terminal object/UTF-8 quota accounting belongs to the projection
of this value: one field and the sum of both exact string byte counts.
