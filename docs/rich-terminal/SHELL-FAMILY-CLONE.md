# Immutable family-batch copies

`tui/rich-terminal/shell-family-clone.f` copies a complete bounded
[region-catalog family graph](REGION-CATALOG.md) into one caller-owned arena.
The returned batch starts at the destination address. Every reachable span,
including strings, canonical control content and full SERIES sample bytes,
is owned by that arena. No source pointer remains in the result.

The helper proves `RTE-FAMILY-BATCH-VALID?` shape and membership. It does not
perform aggregate semantic, identity, feature or transaction-quota admission.
The caller must obtain that admission before publishing the copied batch.
Neither measurement nor copying changes the source graph.

## Public words

| Word | Stack effect | Result |
|---|---|---|
| `RSHFC-MEASURE` | `( batch -- bytes status )` | Exact aligned arena requirement |
| `RSHFC-COPY` | `( batch destination capacity -- used status )` | Complete copied batch, or zero used on refusal |
| `RSHFC-STORAGE-DISJOINT?` | `( a u -- flag )` | Canonical span outside helper, catalog and engine admission scratch |

Statuses are `RSHFC-S-OK` = 0, `RSHFC-S-CAPACITY` = 1 and
`RSHFC-S-INVALID` = 3. Unrepresentable aligned totals are capacity failures.
Malformed source graphs, noncanonical spans, unaligned destinations and
forbidden aliases are invalid. A `(0,0)` destination can be used to obtain a
capacity refusal; measurement is the direct way to obtain the exact size.

Source headers, items, glyph references and sample banks obey the catalog's
alignment rules. Display/content payloads may be byte-aligned. The destination
is eight-byte aligned. Its entire declared capacity must be disjoint from
every source span and all helper/catalog/engine admission storage. Exact used
source spans must also be pairwise disjoint under the catalog contract.

Before any helper scratch write, the fixed source graph and every reachable
span are checked against helper storage. Before any destination write, the
complete graph is validated, all aliases are rejected, the exact size is
computed with overflow checks, and capacity is verified. Refusal leaves the
entire destination unchanged. Success changes exactly `used` bytes and leaves
the capacity tail unchanged. Callers must keep the source immutable throughout
the call; the module uses private synchronous scratch and is not reentrant.
Public calls clear retained scalar scratch before returning, including every
borrowed source/output pointer. Early authority refusals perform no scratch
write.

## Packing and rebasing

The arena packs `RTE-FAMILY-BATCH-SPAN@` order, with each nonempty span starting
on an eight-byte boundary and its trailing padding zeroed:

1. Batch header, catalog header, catalog rows, family vector.
2. For each family: plan header, item bank, exact byte bank, glyph references,
   instrument region copies. Absent spans consume zero bytes and retain null
   pointers.

Thus the exact requirement is the sum of `align8(span-bytes)` across the
catalog's `4 + 5 * family-count` spans. There is no product-specific limit,
implicit allocation or additional caller work bank. Prefix offsets are
recomputed from validated spans; offset lookup is quadratic in the number of
families, while payload copying is linear in the total byte extent.

The helper rewrites batch/catalog/family pointers and each plan's item bank.
It also rewrites instrument region-bank pointers and these item fields:

| Family | Rebased item pointers |
|---|---|
| CONTROL | Label, shortcut, canonical content |
| GLYPH | None; copied references remain byte-bank offsets |
| INSTRUMENT | Unit |
| STATIC | Label, value |
| SERIES | Complete sample bank |
| PANE | Title |

Scalar identity, geometry, provenance, semantic order, region references,
SERIES timestamps/values and all original used lengths are preserved. The
copied graph passes the same catalog validator and can itself be copied.
After success, source storage may be reused or destroyed. The destination
must remain at its address and immutable while borrowed by subsequent
admission/provider work; relocating its raw bytes without rebasing pointers
is not supported. Shell actions and shell correlations are separate sidecar
storage and are not part of this graph.

`local_testing/test_shell_family_clone.py` executes the real native source
closure. It covers all six families, nested pointer ownership, zero padding,
exact sizing, repeated copying, source destruction, empty-series/null spans,
capacity and alias refusal, and untouched destination tails.
