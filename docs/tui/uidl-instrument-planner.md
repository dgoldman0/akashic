# Frozen UIDL instrument and series planner

`akashic/tui/rich-terminal/uidl-instrument-planner.f` lowers a dense frozen
UDGSN document slice into initial/all-new renderer-neutral RTE plans. It is a
synchronous, allocation-free leaf: it does not call a provider, publish a
transaction, consult an application, or choose an applet-specific limit.

The caller owns the request and every source/output span. Frozen descriptors,
complete native UDG graphs, and optional negotiated limits remain immutable
through the call. On success the caller owns the copied samples and readout
units; no output points into the native source bank. Output plans borrow only
the caller's output banks and remain valid until those banks are reused.

## Request and results

`RUIP-REQUEST-SIZE` is **368 bytes**, aligned to eight bytes. Call
`RUIP-REQUEST-CLEAR` first. The earlier 192-byte request is not a compatible
allocation for this version; its original field offsets remain unchanged.
All fields are native 64-bit cells.

| Offset | Field |
|---:|---|
| 0, 8, 16 | Document attachment, retained owner, retained generation |
| 24, 32 | Surface columns, rows |
| 40, 48 | First region ID, first instrument ID |
| 56, 64 | Frozen UDGSN descriptor address, bytes |
| 72, 80 | Frozen UDG native address, bytes |
| 88, 96 | Instrument plan address, capacity |
| 104, 112 | Instrument region bank address, capacity |
| 120, 128 | Instrument record bank address, capacity |
| 136, 144 | Copied readout unit bank address, capacity |
| 152, 160 | Tentative claim bank address, capacity |
| 168, 176 | Instrument correlation bank address, capacity |
| 184 | Reserved zero |
| 192 | First SERIES ID, independent of instrument IDs |
| 200 | Immutable RTE limits address, or zero |
| 208, 216 | Previously admitted series count, sample-slot count |
| 224, 232 | SERIES plan address, capacity |
| 240, 248 | SERIES record bank address, capacity |
| 256, 264 | Copied sample bank address, capacity |
| 272, 280 | SERIES correlation bank address, capacity |
| 288, 296 | Omitted descriptor ordinal bank address, capacity |
| 304 | Output series count |
| 312 | Output copied sample bytes |
| 320 | Output sample slots, sum of declared capacities |
| 328 | Output last SERIES ID, or zero |
| 336 | Output omitted descriptor count |
| 344, 352, 360 | Output SERIES framed bytes, provider-copy bytes, operations |

The existing setters retain their stack effects:

```forth
RUIP-REQUEST-IDENTITY!  ( attachment owner generation first-region first-instrument q -- )
RUIP-REQUEST-SURFACE!   ( columns rows q -- )
RUIP-REQUEST-SOURCE!    ( descriptors-a descriptors-u native-a native-u q -- )
RUIP-REQUEST-PLAN!      ( plan-a plan-u regions-a regions-u instruments-a instruments-u q -- )
RUIP-REQUEST-AUXILIARY! ( units-a units-u claims-a claims-u correlations-a correlations-u q -- )
```

The SERIES setters are:

```forth
RUIP-REQUEST-SERIES-IDENTITY!  ( first-series limits prefix-series prefix-slots q -- )
RUIP-REQUEST-SERIES-PLAN!      ( plan-a plan-u records-a records-u q -- )
RUIP-REQUEST-SERIES-AUXILIARY! ( samples-a samples-u correlations-a correlations-u omitted-a omitted-u q -- )
```

`RUIP-BUILD` preserves its seven-result stack effect:

```forth
RUIP-BUILD ( q -- regions instruments unit-bytes claims last-region last-instrument status )
```

Statuses are `RUIP-S-OK=0`, `RUIP-S-CAPACITY=1`, and `RUIP-S-INVALID=2`.
Additional results use `RUIP-REQUEST-SERIES-COUNT@`,
`RUIP-REQUEST-SAMPLE-BYTES@`, `RUIP-REQUEST-SAMPLE-SLOTS@`,
`RUIP-REQUEST-LAST-SERIES@`, `RUIP-REQUEST-OMITTED-COUNT@`,
`RUIP-REQUEST-SERIES-WIRE-BYTES@`, `RUIP-REQUEST-SERIES-COPY-BYTES@`, and
`RUIP-REQUEST-SERIES-OPS@`, each `( q -- value )`.

Zero limits retain ordinary READOUT/METER/STATUS planning without SERIES
capability. Their two prefix counters must then be zero. A nonzero limits
pointer must reference a strict complete RTE limits record. The planner never
rewrites negotiated limits to represent a remaining quota. Prefix counts are
added to this call's measured series/slot use during admission.

## Traversal, admission, and omission

Every descriptor is authenticated in canonical order, every native extent is
covered exactly once, and every UDG graph is deeply validated before any
omission or plan output is written. All walks use `UDG-RECORD-COUNT@`;
`UDG-OBJECT-COUNT@` only determines whether a graph needs an instrument region.
SERIES records never enter object geometry, object IDs, or residual claims.

A second pass measures complete graphs in descriptor order. A graph is omitted
whole if its series are unsupported, a declared history exceeds the negotiated
history limit, prefix plus admitted series/slots exceeds the corresponding
quota, the complete initial graph operation/byte lower bound already exceeds
transaction limits, an output bank cannot hold the complete graph, or an ID range would
wrap. Missing instrument support also omits the graph. WAVEFORM requires a
complete 112-byte definition payload; every other instrument's full payload
must also fit. The planner includes the 160-byte update envelope, 104 bytes per
region, and each instrument frame (READOUT 144 plus unit bytes, METER 152,
STATUS 136, WAVEFORM 152), with one operation per region/instrument plus SERIES
operations. These costs accumulate across admitted graphs in this slice.
Prior documents and other families remain the producer's final aggregate
admission responsibility.

Omitted graphs consume no region, instrument, SERIES identity, copied unit,
copied sample, or residual claim. Later unrelated graphs can still be admitted.
The omission output is a packed, increasing sequence of native `u64` descriptor
ordinals, starting at zero. These are not claims. The caller uses the frozen
descriptors' clips to detect residual CELL overlap with other admitted
families. Capacity for `8 * descriptor-count` bytes covers every possible
omission. If an actual omission cannot be recorded, the build returns CAPACITY
and clears every already-authorized output bank.

IDs are independent unsigned nonzero namespaces. An ending ID of UINT64_MAX
is valid; wrapping through zero is refused for the complete graph. Native root,
record, mounted relation, and retained identities are never substituted for
each other. Correlation records remain 80 bytes: attachment/source/index/source
generation/relation root/native root/native record at offsets 0 through 48,
region ID at 56, retained instrument or SERIES ID at 64, and reserved zero at 72.
`RUIP-CORRELATION-SERIES-ID@` reads the SERIES variant. A graph containing only
SERIES has region ID zero in those correlations.

## Exact histories and bounds

SERIES output records use `RTE-SERIES-SIZE=88`; the plan uses
`RTE-SERIES-PLAN-SIZE=48`. Native uniform histories copy their entire signed i64
sample array unchanged. Explicit histories copy every `(u64 timestamp, i64
value)` pair unchanged. Capacity, mode, interval, and first timestamp remain
exact. The UDG validator establishes strictly increasing explicit timestamps,
non-overflowing uniform end timestamps, exact extents, unique keys, and earlier
same-graph SERIES references. WAVEFORM references are translated through that
graph's emitted SERIES correlations.

For a nonempty history, let `n` be sample count, `s` be stride (8 uniform,
16 explicit), and `q` be:

```
min(n, limits.samples_per_append, floor((limits.outbound_payload - 40) / s))
```

The planner requires `q > 0`. It preserves all `n` samples; chunking only bounds
publication frames. There are `ceil(n/q)` append chunks plus one definition.
An empty history has null sample address, zero bytes and `q=0`, and still has
one definition. Exact SERIES-only costs are `80 * operations + sample-bytes`
framed bytes and `48 * operations + sample-bytes` provider-copy bytes. Cadence
limits do not alter sample intervals or fabricate timestamps.

There is no sample cap inside RUIP. Caller capacities derive from the frozen
native bank and negotiated limits. For a native bank of `N` bytes, `floor(N/72)`
is a conservative SERIES-record count bound, and `N` is a conservative sample
copy byte bound. Declared sample capacity is charged as slots even when history
is empty. Output counts and byte aggregates use checked u32 accumulation;
source/output pointer arithmetic is checked for wrapping.

A 16,000-sample uniform history copies exactly 128,000 sample bytes. With a
256-byte payload limit and append limit 64, `q=27`, requiring 593 chunks plus one
definition: 175,520 framed bytes and 156,512 provider-copy bytes. The complete
native graph with one waveform is 128,328 bytes. These values follow from the
source shape; they are not hidden planner allocation constants.

## Storage authority and refusal

Every nonempty span must be nonwrapping; native records, samples, requests,
plans, correlations, and omissions are aligned to eight bytes. Unit strings
may be byte aligned. Empty spans have canonical address zero. Record banks
must have exact stride multiples; sample and omission capacities are multiples
of eight.

The request, source banks, limits, and every mutable bank are pairwise disjoint.
Pure guards reject overlap with RUIP, UDG, and RTE admission/limits scratch
before the first planner scratch store. Source validation begins only after
full range authority is proved. Invalid range/alias input remains untouched.
After range authority is established, failure scrubs all supplied mutable
capacities and clears the added scalar result fields. Immutable source and
limits spans are preserved. Successful builds initialize only their measured
prefixes; unused output capacity is unchanged. Plan pointers must be ignored
when the corresponding reported count is zero.
