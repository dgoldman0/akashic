# Complete SERIES and WAVEFORM publication

The hybrid producer consumes canonical DATA_GRAPHICS snapshots from ordinary
widgets. It copies every admitted SERIES history into its own sample bank and
publishes genuine SERIES records before their WAVEFORM instruments. Uniform
histories preserve each signed 64-bit value, first timestamp and interval;
explicit histories preserve each unsigned timestamp and signed value. No
sample truncation, resampling, decimation, or text-derived graph is used.

## Storage and construction

`RTHP-STORAGE-BYTES` needs no SERIES argument. Its selected
`max-data-graphics-native` bound `N` also derives at most `floor(N / 72)`
SERIES records, a sample bank of `N` bytes, and one 32-byte omitted-graph
rectangle per source graph descriptor. The live bank and each of the two
packed acknowledgement banks reserve 88 bytes per SERIES record, 80 bytes
per provenance correlation, and aligned sample storage. The caller must use
the current storage calculator when allocating the arena.

`RTHP-INIT` takes an explicit positive `first-series` immediately before
`producer`; a fresh owner passes 1. SERIES identities
use an independent namespace and frontier; controls, statics, instruments
and glyphs retain their existing object namespace.

The producer is 4144 bytes. Its hybrid plan is 168 bytes at offset 1592,
its admission record is 456 bytes at offset 1760, and its RUIP request is
368 bytes at offset 2720. SERIES metadata occupies offsets 3912–4072 and
the 48-byte SERIES plan starts at 4080. Packed target headers are 336 bytes;
point-target entries remain 48 bytes. RUHA directory size is obtained from
its public constant, including child-owner provenance.

## Exact admission and fallback

For one history with `n` samples and stride `s` (8 uniform, 16 explicit),
let `b = n*s`. For a nonempty history, the producer selects
`q = min(n, negotiated samples-per-append, floor((payload-limit - 40)/s))`
and `k = ceil(n/q)`. Empty histories have null/zero sample spans and `q=k=0`.
The complete candidate requires:

| Resource | Per history |
| --- | --- |
| SERIES identities | 1 |
| Reserved sample slots | Authored capacity, including unused slots |
| Operations | `1 + k` |
| Provider copied bytes | `48*(1+k) + b` |
| Wire bytes | `80*(1+k) + b` |

History capacity, current count, sample stride, append size, payload bytes,
SERIES count and sample-slot reservations are checked independently. Native
storage capacity does not bound authored future reservations; the owner uses
the composition's explicit negotiated slot limit. Prior admitted document
SERIES counts and reservations are passed to each subsequent leaf planner.
The aggregate preflight remains authoritative for all families' combined
transaction, copy, object, UTF8, region and operation limits.

As a concrete qualification, all 16,000 uniform Sound Lab samples occupy
128,000 sample bytes. With payload 256 and append limit 64, `q=27` and
`k=593`: 594 operations, 156,512 provider bytes and 175,520 wire bytes for the
history. A 125-microsecond sample interval is independent of display cadence.

The leaf planner validates the complete immutable source before admission.
Missing SERIES capability, an unaffordable authored reservation, insufficient
caller storage or an impossible complete graph transaction omits that entire
DATA_GRAPHICS graph before assigning IDs or claims. Later unrelated graphs
may still be admitted. A series-only graph creates no visual region or CELL
claim. An omitted graph's complete rectangle is retained only as a safety
check: overlap with another family's semantic claim refuses the whole rich
candidate because there is no shared final-writer proof.

A final opaque aggregate quota refusal may remove the entire optional
instrument/SERIES family using the existing retry policy; this includes
cross-document total costs that no individual leaf can decide. Its exact
prior claim prefix is restored. If the complete candidate still cannot fit,
the blank/reveal protocol retires the previous rich display before current
CELL drawing is exposed. Invalid source remains invalid rather than becoming
an optional capability refusal.

## Lifetimes and acknowledgements

Packed histories own their records, provenance correlations and samples.
Sample addresses become dense offsets within their packed bank, and empty
histories retain canonical zero spans. Reuse checks exact sample bytes,
record shape, interval, capacity, source attachment, lifecycle and native
relation identity. Reusable records normalize both SERIES identities and
WAVEFORM references to the acknowledged namespace. Changed samples or
provenance require complete owner replacement; this slice does not append
into a live acknowledged history across transactions.

The SERIES frontier advances only after the provider acknowledges the hidden
START. Sealed, publishing, awaiting, stale and cancelled candidates cannot
consume IDs. A subsequent reveal retry preserves the already consumed
frontier. Unchanged cloning retains independent copied sample storage and
acknowledged identities.

`local_testing/test_rich_series_producer.py` loads the full production closure
in the native executor. It covers complete 16,000-sample preservation,
explicit/uniform packing, source destruction after packing, exact reuse and
mutation refusal, empty histories, independent ID acknowledgement fences,
whole-graph capability fallback, and cross-document reservation accounting.

## Desktop qualification

SERIES and WAVEFORM passed the complete Desk journey on 2026-09-30 and are
selected in the rich Desktop profile (`desktop-apt1`). The run used
`local_testing/run_headless_grid_acceptance.py`. It starts Desk through the
real `megapad.main --mode simulator --executor native` entry point, replaces
only the Unix listener with in-process dispatch, and composes into an SDL
dummy sink. It does not cover sockets, a physical display, audio playback or
UART.

After the 52-stage journey and the Grid and FIELD probes, a 13-stage SERIES
probe used only ordinary input. A FIELD ACTIVATE set Sound Lab's duration to
2000 ms and F5 rendered a 16,000-sample history. Every signed 64-bit sample
and timestamp in the acknowledged retained history matched Sound Lab's own
waveform model, read while the guest was paused: uniform 125-microsecond
spacing from 0 to 1,999,875 microseconds, with no decimation or substitute
data. Changing the amplitude through the ordinary exact-value prompt gave a
different complete history, compared the same way. Both prompts were checked
as whole-CELL fallback, and both renders kept the authored waveform bounds.

A Down key then moved Sound Lab's selection to another field. The next
acknowledged frame kept the history identity, the WAVEFORM identity, the
bounds, all 16,000 samples and the source graph unchanged. This stable reuse
relies on FIELD's SELECTED-only CONTROL-REPLACE
([FIELD publication](FIELD-PRODUCER.md)).

That run had the shell off. The combined
[shell run](DESK-SHELL-COMPOSITION.md#desktop-qualification) repeated both
full sample comparisons, but its shell then published every changed draw as
a complete START, so the selection redraw got fresh identities: it proved
the samples were preserved, not reused. Shell DELTAs now keep series
identities, and the runner requires stable reuse with the shell installed
too.

The Desktop profile allows 32,768 samples per history, 65,536 reserved
sample slots in total and 4,096 samples per append. A changed history is
published whole within one candidate transaction; appending to a live
acknowledged history across transactions is not implemented.

From the Akashic checkout, with the paired MegaPad native extensions built:

```sh
python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/series-qualification \
  --require-status-fields --require-fields --require-series
```
