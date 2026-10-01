# UIDL Status Field Snapshot

**Provider:** `akashic-tui-uidl-status-field-snapshot`
**Prefix:** `USFSN-` (public), `_USFSN-` (private)

`USFSN` freezes ordinary UIDL status slots into a caller-owned descriptor
bank and a separate native `USF` bank.
It does not encode terminal commands or allocate retained object identities.
Status values do not enter the `USCOL` collection or `UDG` graphics families.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `USFSN-CAPTURE` | `( descriptors-a descriptors-u native-a native-u -- count used status )` | Capture one coherent current document |
| `USFSN-DESCRIPTOR-BYTES` | `( -- bytes )` | Return 128 |
| `USFSN-DESCRIPTOR-BANK-BYTES` | `( capacity -- bytes-or-zero )` | Size a descriptor bank without overflow |
| `USFSN-FROZEN-WORK-BYTES` | `( count -- bytes-or-zero )` | Size the offset ledger: eight bytes per descriptor |
| `USFSN-FROZEN-VALIDATE` | `( work-a work-u descriptors-a descriptors-u native-a native-u -- status )` | Validate exact used banks independently of live UIDL |
| `USFSN-STORAGE-DISJOINT?` | `( address bytes -- flag )` | Pure check against snapshot module storage |
| `USFSN-DESCRIPTOR-NATIVE` | `( descriptor native-base -- model bytes )` | Resolve an admitted relative native offset |

The status domain is `USFSN-S-OK=0`, `USFSN-S-CAPACITY=1`,
`USFSN-S-UNAVAILABLE=2`, and `USFSN-S-INVALID=3`.
`USFSN-STATUS-VALID?` recognizes these four values. Empty optional spans use
`0 0`; nonempty banks must be aligned, nonwrapping spans. Descriptor byte
counts must be multiples of `USFSN-DESCRIPTOR-SIZE` (128).

## Descriptor schema

Each field occupies one native eight-byte cell. Descriptors contain no
borrowed element, widget, model, region, or relation pointer.

| Offset | Field | Public accessor |
|---:|---|---|
| 0 | Source kind, `USFSN-SOURCE-UIDL=1` | `USFSN-DESCRIPTOR-SOURCE@` |
| 8 | UIDL pool source index | `USFSN-DESCRIPTOR-SOURCE-INDEX@` |
| 16 | Source generation, always zero | `USFSN-DESCRIPTOR-SOURCE-GENERATION@` |
| 24 | Relation root key, always one | `USFSN-DESCRIPTOR-ROOT-KEY@` |
| 32 | Byte offset relative to the native bank | `USFSN-DESCRIPTOR-NATIVE-OFFSET@` |
| 40 | Screen row | `USFSN-DESCRIPTOR-ROW@` |
| 48 | Screen column | `USFSN-DESCRIPTOR-COLUMN@` |
| 56 | Complete height, always one | `USFSN-DESCRIPTOR-HEIGHT@` |
| 64 | Complete width | `USFSN-DESCRIPTOR-WIDTH@` |
| 72 | Clip row | `USFSN-DESCRIPTOR-CLIP-ROW@` |
| 80 | Clip column | `USFSN-DESCRIPTOR-CLIP-COLUMN@` |
| 88 | Clip height, always one | `USFSN-DESCRIPTOR-CLIP-HEIGHT@` |
| 96 | Clip width | `USFSN-DESCRIPTOR-CLIP-WIDTH@` |
| 104 | Resolved UIDL paint z | `USFSN-DESCRIPTOR-Z@` |
| 112 | Exact native entry bytes | `USFSN-DESCRIPTOR-ENTRY-BYTES@` |
| 120 | Sum of label and value UTF-8 bytes | `USFSN-DESCRIPTOR-UTF8-BYTES@` |

Descriptors are ordered by strictly increasing unsigned source index, one
per status slot. Every field uses generation zero and root key one, the same
identity shape other families give their direct UIDL roots. A native
`USF-KEY@` remains independent of that outer identity.

## Ordinary sources and geometry

A status field is an immediate `LABEL` child of `STATUS`, rendered by the
canonical label renderer, with no children or caller widget replacement.
Its resolved alignment must be left, height one, and width positive. The
ordinary painter and capture share `_UTUI-STATUS-LABEL?` shape and display
eligibility, and the painter draws the slot as one clipped `DRW-TEXT` row.
Capture also verifies the renderer execution token in
`_UTUI-STATUS-LABEL-CANONICAL?`.
Centered and right-aligned labels retain their ordinary label path.

The native value has an empty label, label width zero, severity zero,
and the complete `UIDL-TEXT@` display value. `USF-INIT-DISPLAY` applies the
ordinary text display substitutions without mutating the authored or bound
source. `USF-F-EMPHASIZED` reflects bold; visible admitted slots carry
`USF-F-VISIBLE`. Capture sizes the projected UTF-8 text before copying it.

No application identifier, text heuristic, or app-specific provider is used.

The field must occupy a complete one-row rectangle whose exact region and
document clip equals that rectangle. Partially clipped, hidden, unsupported,
or refused fields are omitted so their CELL paint remains available. A
field's model width must equal its physical field width. Supported fields
are captured once and deep-validated before their descriptors are admitted.

## Storage and frozen lifetime

Capture holds the UIDL-TUI, UIDL, semantic text, expression, and bound-state
observations needed to read coherent values. Both output banks are proved
pairwise disjoint before output writes. They must also avoid module scratch,
UIDL authority, live semantic widgets, their backing models, and region
ancestry, including hidden widgets. The common semantic storage walk protects
co-resident text collections, graphics, and status fields; explicit module
guards cover `USF`, `USCOL`, `UDG`, and graphics formatting storage.
Caller banks must not alias each other or any other live owner's storage.

If capture fails after writing, all descriptor and native bytes touched by
that attempt are cleared, and the result is `( 0 0 status )`. Capacity
refusal is a document-level failure. A root-specific unsupported or invalid
producer is omitted while independent roots can still be captured.

On success, the caller owns the first `count * 128` descriptor bytes and the
first `used` native bytes. They remain valid after source mutation, redraw,
widget detachment, or document teardown, provided the caller preserves these
bytes. Each native entry retains the strict pointer-free `USF` ABI: a
72-byte header, label bytes, value bytes, and zero padding to eight bytes.

Frozen validation consults no live tree or widget. It checks each complete
native model, visible flag, descriptor text size, generation/key shape,
canonical order, width, z, and exact one-row clip. It sorts offsets in the
caller-provided ledger to prove the descriptors cover the entire native bank
exactly once, with no overlap, gap, duplicate ownership, or trailing bytes.
The ledger is cleared after validation; the frozen banks remain read-only.
