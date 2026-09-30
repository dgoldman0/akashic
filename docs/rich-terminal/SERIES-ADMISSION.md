# Complete SERIES and WAVEFORM admission

The SERIES lane publishes one complete, immutable history in a single
replacement candidate. `RTE-SERIES-DEFINE ( series facade -- status )` and
`RTAPT-SERIES-DEFINE ( series engine -- status )` accept an 88-byte descriptor:

| Offset | Native cell |
|---:|---|
| 0, 8, 16 | Owner, generation, independent series ID |
| 24 | Positive u32 history capacity |
| 32, 40 | Mode, uniform interval in microseconds |
| 48 | First uniform timestamp |
| 56, 64 | Borrowed native sample address and exact bytes |
| 72 | Maximum samples per emitted chunk |
| 80 | Reserved zero |

Mode 0 contains exact `<u64 timestamp, i64 value>` pairs with strictly
increasing timestamps; interval and first timestamp are zero. Mode 1 contains
exact signed i64 values and a positive interval; the final timestamp must fit
u64. Display cadence does not constrain the sample interval. An empty history
uses address, byte length, first timestamp and chunk limit all zero, while its
positive capacity still reserves history slots.
Series IDs increase monotonically in their own owner namespace; they do not
consume or alias OBJECT identities.

For a nonempty history, the caller chooses a positive chunk limit within the
negotiated append and payload bounds. Capture emits one SERIES_DEFINE,
one initial SERIES_REPLACE, and ordered SERIES_APPEND chunks. With `N`
samples and chunk limit `q`, the chunk count is `ceil(N/q)`. Every operation
uses a 48-byte owned native header and an 80-byte complete wire frame, plus
the exact sample bytes for sample operations. Thus series copy cost is
`48 * (1 + chunks) + sample_bytes`; wire cost is
`80 * (1 + chunks) + sample_bytes`. Empty histories emit only DEFINE.

All operations, copy bytes, payload sizes, transaction bytes, series slots
and declared history capacities are admitted before capture writes anything.
Each captured sample chunk owns its values and carries an exact backlink to
its earlier same-owner SERIES definition. Publication checks mode, capacity,
ordering and timestamp arithmetic from those owned bytes. Retry uses those
copies; source mutation cannot alter the candidate. Abort leaves the previous
acknowledged owner intact.

The public snapshot operation accepts only REPLACE_START. There is no public
incremental append, eviction or history mutation API in this slice. Changed
samples or series metadata force a complete owner replacement. An unchanged
graph reuses the acknowledged candidate. A graph that cannot fit the negotiated
limits retains its complete CELL rendering; samples are never decimated to
make admission succeed.

The neutral SERIES plan is 48 bytes: owner, generation, surface columns,
surface rows, descriptor address and descriptor bytes. Hybrid plans append
SERIES-PLAN at 144 and the dense sample bank address/bytes at 152/160, making
the wrapper 168 bytes. Its complete source graph and output are disjoint from
each other and validator/provider storage before any scratch write. The
456-byte checked admission record appends series count, final ID, total
capacity, maximum capacity, sample bytes, chunk count, maximum selected chunk
samples, maximum actual chunk bytes, and WAVEFORM count at offsets 384..448.
The provider reads these fixed aggregates without revisiting caller items.

WAVEFORM is instrument kind 4. The instrument descriptor grows to 216 bytes,
adding SERIES-ID at 208; existing kinds require this field to be zero.
WAVEFORM uses the ordinary immutable object geometry, COLOR-A for trace,
COLOR-B for zero line, MINIMUM/MAXIMUM for its signed range, VALUE for the
zero line, and OPTIONS bit 0 to show it. MODE, SCALE, unit and formatted text
are zero. Its exact same-candidate series reference consumes no extra object
or UTF8 quota; the waveform itself consumes one object and one 152-byte frame.

`RTE-F-SERIES` retains its existing capability and INSTRUMENT dependency.
Absent capability rejects concrete capture and emission and lets the producer
omit the complete unsupported graph before claiming any CELL coverage.
`RTE-ADMISSION-STORAGE-DISJOINT? ( a u -- flag )` supplies a pure storage guard
for renderer-neutral planners that validate negotiated limits without a facade.
