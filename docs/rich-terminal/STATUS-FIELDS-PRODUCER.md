# Structured status publication

`hybrid-screen-producer.f` lowers the ordinary `USF` status fields captured by
`USFSN` and `RUHA` into the engine's static STATUS_FIELD lane. It preserves the
one-row field rectangle, explicit label/value split, authored text, severity
and emphasis. There is no application-name or text-pattern inference. Ordinary
CELL drawing remains the fallback and does not depend on negotiation.

## Composition and bounds

The status-aware constructors add one argument, `max-status-native`, immediately
after `max-data-graphics-native`:

```forth
RTHP-STORAGE-BYTES-STATUS
  ( max-documents max-records max-source-text max-collection-native
    max-data-graphics-native max-status-native max-cols max-rows -- bytes|0 )

RTHP-INIT-STATUS
  ( adapter facade arena-a arena-u max-documents max-records max-source-text
    max-collection-native max-data-graphics-native max-status-native
    max-cols max-rows owner owner-generation region first-object producer
    -- scb-status )
```

The original `RTHP-STORAGE-BYTES` and `RTHP-INIT` signatures remain available and
select zero status capacity. The new bound is an aligned unsigned 32-bit byte
capacity; zero is valid. Each native field needs at least the 72-byte USF header,
so `max-status-native / 72` bounds the descriptor, object and correlation counts.
There is no independent hardcoded field-count limit.

The producer reserves separate status descriptor and native source banks,
176-byte static records, a dense label/value text bank, and 40-byte source
correlations. Each possible object adds one claim, the corresponding residual
planner events, and one frozen projection rectangle. Both immutable target
banks reserve used static records, correlations and text. All capacities enter
the same checked storage calculation and owner/preflight accounting as the
older families. The embedded hybrid/admission records and target headers grow
without overlapping neighboring records.

## Publication and fallback

The source import checks exact aggregate and per-document slices before
copying. A missing STATUS_FIELDS capability or insufficient local status bank
omits the entire status source lane before object IDs, claims or output text
are assigned. The status output follows controls and instruments in the object
namespace; residual glyphs follow status. Status objects share the base content
region. No region or pane geometry changes are introduced here.

Only fully contained one-row fields are published. Hidden or partially clipped
fields keep their ordinary representation. Local capacity refusal rolls back
the complete status claim suffix, then rebuilds residual glyphs. An opaque
provider refusal first retries without status before removing an older
optional family. Every rebuilt family combination also gets its status-free
retry, including the final menu-plus-residual candidate. Invalid source remains
invalid rather than being recategorized as an unsupported optional feature.

Frozen identity order does not establish the final painter of overlapping
semantic roots. Two overlapping status fields therefore fall back together.
An overlap with an already claimed menu, collection or instrument rectangle
refuses that rich candidate entirely: retaining the older claim could hide the
ordinary status pixels. For an active rich owner, the existing empty hidden
START and reveal acknowledgement retire the old rich plane before the complete
CELL frame becomes authoritative. A future shared relative paint ordinal can
support narrower overlap handling; this implementation does not infer it.

## Lifetime and reuse

Packed static strings contain offsets into their own immutable text section,
not borrowed pointers. Each correlation preserves document attachment, source
index, mounted generation, relation root key and native field key. An unchanged
clone needs no status pointer rebasing. A retained DELTA reuses the complete
status lane only when its identities, geometry, roles and exact text match;
normalization then preserves the acknowledged IDs and base region. Any changed
status uses a complete retained replacement.

Fixed-candidate validation checks the exact static admission totals, canonical
empty spans, dense owned text, sequential IDs, field geometry and matching claim
rectangles before emission. STATUS_FIELD remains noninteractive; it adds no
input target or host-side state mutation.

## Executed qualification

The focused producer suite executes production Forth words on both Python and
native simulator backends. Its 54 cases cover authored slots and UTF-8, exact
claims and IDs, capability absence, independent local capacity, malformed source
slices, invalid USF state, clipping and hidden fallback, overlapping roots,
immutable packed text, reuse and normalization, fixed-candidate mutations, and
legacy zero-capacity sizing. The overlap test feeds the real lowering refusal
into the production active-owner blank/reveal state machine with a scripted
provider, and verifies retirement only after acknowledgement.

The existing instrument reuse, glyph growth and blank-frame suites also pass
(168 cases). These bounded tests do not replace the composed Desk run or claim
physical display, UART, audio or socket qualification.
