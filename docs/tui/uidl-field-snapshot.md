# UIDL FIELD snapshot

`akashic-tui-uidl-field-snapshot` freezes genuine mounted `FLD` widgets into
independent caller-owned descriptor and native `UFLD` banks. It exposes no live
widget, region, relation, or model pointers and creates no retained identities.
Authored UIDL text is not inferred to be a typed field.

| API | Stack |
|---|---|
| `UFLSN-CAPTURE` | `( descriptors-a descriptors-u native-a native-u -- count used status )` |
| `UFLSN-DESCRIPTOR-BYTES` | `( -- 128 )` |
| `UFLSN-DESCRIPTOR-BANK-BYTES` | `( capacity -- bytes-or-zero )` |
| `UFLSN-FROZEN-WORK-BYTES` | `( count -- bytes-or-zero )` |
| `UFLSN-FROZEN-VALIDATE` | `( work-a work-u descriptors-a descriptors-u native-a native-u -- status )` |
| `UFLSN-STORAGE-DISJOINT?` | `( address bytes -- flag )` |
| `UFLSN-DESCRIPTOR-NATIVE` | `( descriptor native-base -- model bytes )` |

Statuses are `OK=0`, `CAPACITY=1`, `UNAVAILABLE=2`, `INVALID=3` under `UFLSN-S-`.
Empty optional spans are exactly `0 0`; nonempty spans are aligned,
nonwrapping and disjoint. Descriptor byte lengths are multiples of 128.
Frozen validation needs eight work bytes per descriptor; sizing overflow
returns zero.

Each descriptor consists of sixteen native eight-byte cells:

| Offset | Value | Accessor suffix after `UFLSN-DESCRIPTOR-` |
|---:|---|---|
| 0 | UIDL source kind 1 | `SOURCE@` |
| 8 | UIDL pool source index | `SOURCE-INDEX@` |
| 16 | Positive closed source generation | `SOURCE-GENERATION@` |
| 24 | Closed draw relation root key | `ROOT-KEY@` |
| 32 | Document-local native offset | `NATIVE-OFFSET@` |
| 40,48 | Absolute row,column | `ROW@`, `COLUMN@` |
| 56,64 | Complete height,width | `HEIGHT@`, `WIDTH@` |
| 72,80 | Clip row,column | `CLIP-ROW@`, `CLIP-COLUMN@` |
| 88,96 | Clip height,width | `CLIP-HEIGHT@`, `CLIP-WIDTH@` |
| 104 | Resolved UIDL paint z | `Z@` |
| 112 | Exact native entry byte length | `ENTRY-BYTES@` |
| 120 | Outer-label + TEXT + all choice-label UTF8 bytes | `UTF8-BYTES@` |

Unsigned source index and relation root key order descriptors. The native
`UFLD-KEY@` and positive `UFLD-REVISION@` remain independent application values.
The native model validates typed values, constraints, reserved flags, exact
label/value slots, clean UTF8, choice identity and zero padding. The slot
coordinates are relative to the descriptor root. A root may have several
rows, but its exact document/region clip must equal its complete rectangle.
Partial clips and unsupported, hidden or refused roots retain ordinary CELL
ownership. The ordinary widget supplies the measure and single deep copy;
its VISIBLE/ENABLED composition and selected-state clearing are preserved.

Capture holds the ordinary UIDL-TUI/UIDL observation and semantic binding
observation while resolving closed mounted instances. It rechecks widget
identity, draw relation generation, source geometry and region ancestry.
Every output span is proved disjoint from the other bank, snapshot/model/widget
scratch, UIDL authority and all live semantic widget models, including hidden
ones. A capacity failure clears all output bytes dirtied by that attempt and
returns zero count and used bytes. A root-specific refusal omits that root.

The successful banks remain valid after source edits, unbinding, redraw or
teardown while the caller preserves them. Frozen validation uses no live tree:
it deep-validates each UFLD, exact descriptor summary/geometry, sorted unique
source identity and complete native extent. It heap-sorts offsets in the
caller ledger to prove every native byte belongs to exactly one descriptor,
without gaps, duplicate coverage or trailing data. The ledger is cleared;
input descriptor/native banks remain read-only.

RUHA ABI 8 embeds an optional independent A/B family through `RUHA-INIT`.
It revalidates immutable prior banks before reuse and includes FIELD in
whole-document occlusion, capacity fallback, empty-state and content-epoch
rules. An asynchronous producer must copy the borrowed RUHA snapshot into its
own attempt. Capture itself neither dispatches input nor speculates an edit;
ordinary FLD callbacks remain the application's mutation authority.
