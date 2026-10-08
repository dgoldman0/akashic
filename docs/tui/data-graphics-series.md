# Canonical SERIES and WAVEFORM

`akashic/tui/data-graphics-model.f` extends the ordinary pointer-free UDG graph
with owned bounded histories and waveform objects. The DATA_GRAPHICS widget
paints and captures the same immutable graph. No application, PCM, terminal,
or retained-object pointer is stored in a history.

The aggregate header remains 112 bytes, the builder remains 80 bytes, and the
native ABI field remains 1. This is an additional record feature, not a claim
that earlier ABI 1 consumers support it. Earlier validators reject these kinds
as unsupported. Consumers must validate the complete graph and preserve CELL
fallback when they cannot represent every required record.

## Native records

All fields are native 64-bit cells. Records and their bases are eight-byte
aligned. `UDG-K-SERIES=4` uses the common 24-byte BYTES/KIND/KEY prefix and is
not an object. Its header is `UDG-SERIES-HEADER-SIZE=72`:

| Offset | Field | Contract |
|---:|---|---|
| 0 | Bytes | Exact header plus sample bytes |
| 8 | Kind | SERIES=4 |
| 16 | Key | Nonzero, unique in the complete graph |
| 24 | Capacity | Positive u32 history capacity |
| 32 | Mode | EXPLICIT=0 or UNIFORM=1 |
| 40 | Interval | Positive u64 for UNIFORM; zero for EXPLICIT |
| 48 | Sample count | u32, no greater than capacity |
| 56 | First timestamp | u64 for nonempty UNIFORM; otherwise zero |
| 64 | Reserved | Zero |
| 72 | Samples | Exact owned payload; no trailing storage or padding |

UNIFORM stores `count` signed i64 values. Timestamp `i` is exactly
`first + i * interval`; validation checks multiplication and addition against
UINT64_MAX. EXPLICIT stores `count` pairs of unsigned timestamp and signed
value. Timestamps must strictly increase using unsigned comparison. Empty
histories are valid definitions with no payload. Capacity reserves semantic
history slots; it does not add unused bytes to the native record.

`UDG-K-WAVEFORM=5` has the ordinary 80-byte object prefix, followed by:

| Offset | Field | Contract |
|---:|---|---|
| 80 | Series key | Existing earlier SERIES in this graph |
| 88 | Minimum | Signed i64, strictly less than maximum |
| 96 | Maximum | Signed i64 |
| 104 | Trace color | Packed u32 RGBA |
| 112 | Zero-line color | Packed u32 RGBA |
| 120 | Zero-line value | Signed i64 within the declared range |
| 128 | Flags | Bit 0 draws zero line; other bits zero |
| 136 | Reserved | Zero |

`UDG-WAVEFORM-RECORD-SIZE=144`. Root, object and series keys share the existing
strictly increasing record-key discipline; record keys cannot equal the root
key. A waveform cannot reference an object, missing key, or later series.
The validator checks all record extents before traversal and authenticates
references only against the already validated prefix.

Aggregate RECORD-COUNT includes objects and series, OBJECT-COUNT excludes
series, and SERIES-COUNT counts histories. SAMPLE-SLOTS is the exact checked
sum of declared capacities, including empty histories, bounded by u32.
The correlated validation summary reports these same counts. SERIES and
WAVEFORM add no stored UTF-8 quota.

## Builders and accessors

```forth
UDG-SERIES-RECORD-BYTES ( mode count -- bytes|0 )
UDG-SERIES ( key capacity mode interval first samples-a count builder -- status )
UDG-WAVEFORM
  ( key row col h w z flags series-key min max trace zero-color zero-value waveform-flags builder -- status )
UDG-SERIES-FIND ( validated-graph series-key -- record|0 )
UDG-SERIES-SAMPLE@ ( index validated-series -- timestamp value )
```

Builders use the existing UDG statuses: OK=0, UNSUPPORTED=1, CAPACITY=2,
INVALID=3. The existing builder latches failures. The new record operations
check fields, source extents, destination capacity, and ownership before
changing graph bytes. A refused operation can update the builder's latched
status but preserves the existing graph. The full source sample span must be
eight-byte aligned and disjoint from the entire destination capacity, builder,
and UDG module storage. Empty input must be `0 0`. Successful SERIES copies
every sample; the caller can immediately free or reuse its projection buffer.

The normal `0 0` measure-only builder computes exact byte requirements without
creating a graph. Field and timestamp checks still run, but reference existence
and aggregate capacity sums require the copied graph and are authenticated
during copy construction and deep validation. Measurement alone is never
authority to bind or publish a model. The completed model must stay alive and
immutable while borrowed by a widget or snapshot consumer.

Every field in the tables has a public `UDG-SERIES-NAME-OFFSET` or
`UDG-WAVEFORM-NAME-OFFSET` constant and an accessor. Series spellings are
`CAPACITY@`, `MODE@`, `INTERVAL@`, `SAMPLE-COUNT@`, `FIRST-TIMESTAMP@`, and
`SAMPLES@` (returns the payload address). Waveform spellings are `SERIES-KEY@`,
`MINIMUM@`, `MAXIMUM@`, `TRACE@`, `ZERO-COLOR@`, `ZERO-VALUE@`, and `FLAGS@`.
Accessors require validated records; SAMPLE@ also requires `index < count`.
No generic plot record is introduced by this extension.

## CELL projection and capture

DATA_GRAPHICS ignores SERIES during object geometry, scratch sizing, and
z-order traversal. WAVEFORM paints its optional zero line beneath sample dots.
Each stored sample maps by its actual timestamp: oldest at the left edge,
newest at the right, and intermediate positions linear in unsigned time. A
single sample is centered. Values map linearly through the declared signed
range and clamp to the object bounds. CELL is a discrete sample projection;
it does not invent intermediate samples or alter the native history.

Integer projection uses exact multiply/divide, including the complete signed
value and unsigned timestamp ranges. Common small products use native division;
wide products retain the exact unsigned division path. Every sample is visited,
with no decimation, width-dependent model rewrite, or sample-sized renderer
allocation. Drawing remains clipped by the widget and inherited draw clip.
Transparent trace/zero-line colors omit that paint. Hidden and disabled state
follow ordinary DATA_GRAPHICS behavior.

`DGRAPH-DATA-GRAPHICS-CAPTURE` copies the complete graph, including all sample
bytes. Existing deep validation, borrowed-storage disjointness, and bounded
destination checks apply. Relation identity remains in the outer snapshot;
native root/series/object keys remain application-owned.

## Sound Lab bounds

At 8 kHz, complete PCM frame histories use UNIFORM interval 125 microseconds
and first timestamp zero. For 16,000 frames the last timestamp is 1,999,875.
The existing `PCM-FP16>S16` conversion supplies signed Q15 values: +1 maps to
32767, -1 to -32768, out-of-range values/infinities saturate, and NaN maps to
silence. The resulting signed value is stored as i64, never as raw FP16 bits.

A standalone history and waveform graph occupies `328 + 8 * count` bytes.
With Sound Lab's existing 1,960-byte instruments, the complete graph occupies
`2176 + 8 * count`: at most 130,176 bytes. Two immutable graph banks therefore
require 260,352 bytes; a separate full projection array requires 128,000 bytes.
These bounds derive from the caller's 16,000-frame PCM capacity; the canonical
model has no Sound Lab limit or hidden sample cap.

Native tests in `test_data_graphics_series.py` and
`test_data_graphics_waveform_widget.py` cover exact extents, timestamps,
references, capacity and aliases, immutable full history, actual PCM conversion,
CELL clipping/geometry, captured sample equality, and the existing instrument
model/widget regression oracles.
