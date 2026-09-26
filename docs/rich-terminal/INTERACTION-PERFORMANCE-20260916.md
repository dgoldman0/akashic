# Interaction performance follow-up — September 16, 2026

The first implementation removes the blanket full-replacement rule whenever
instruments are present. Akashic commits `aa300ee` and `dacd9ad` retain complete
acknowledged instrument snapshots and allow unrelated control/glyph deltas.
The [implementation notes](INSTRUMENT-REUSE.md) record its bounds, fallback
rules, and 320 passing focused checks. The subsequent
[physical qualification](../../local_testing/evidence/instrument-reuse-20260916.md)
passed: instrument-live menu opening fell from about eight seconds to about
three, with 3–5 KB updates instead of roughly 170 KB. Baseline typing was then
about 2.6 seconds and needed separate attribution; the subsequent typing work
and its current state are in
[TYPING-PERFORMANCE-20260916.md](TYPING-PERFORMANCE-20260916.md).

## Existing main baseline

These observations come from the September 13 unprofiled native physical run,
not from the new implementation. Its trace is
`local_testing/out/rich-main-integration-20260913/physical-menus-i6q4chak/evidence/performance-trace.json`,
SHA-256 `5b598235c9cb75e5a91b7db0a40df41c47c42b7801c81091e6354a513e49271c`.
The [integration ledger](../../local_testing/evidence/rich-main-integration-20260913.md)
binds the source revisions, native binary, and physical presentation boundary.

Latency runs from input RPC start (`elapsed_ns - rpc_duration_ns`) to the ACK
of the next action's authorizing offer. This includes every intervening offer,
not just the first newer frame. Step and byte differences use the latest
status before input and the status preceding that qualifying offer. They are
diagnostic sample boundaries, not an exact exclusive cost of the input word.

| Interaction | Input to qualifying ACK | Semantic steps | Decoded frame bytes | Projection + composition |
| --- | ---: | ---: | ---: | ---: |
| Pad character | 2.448 s | 51,227,073 | 2,797 | 0.146 s |
| Focus Daybook | 2.391 s | 51,399,031 | 3,018 | 0.154 s |
| Open task prompt | 6.404 s | 91,820,396 | 137,595 | 0.336 s |
| Type task character | 2.200 s | 47,286,532 | 1,235 | 0.142 s |
| Submit task | 7.258 s | 102,404,918 | 143,379 | 0.312 s |
| File Explorer View open, instruments live | 7.953 s | 109,573,215 | 170,478 | 0.335 s |
| Daybook Go open, instruments live | 7.957 s | 112,121,133 | 169,114 | 0.363 s |

The manifest confirms eight readouts, two meters, and three status indicators
in one instrument region during the final menu interactions. Each of those
interactions crosses two acknowledged offers and redefines two regions,
1,013 ordinary objects, and 168 controls. This is the concrete target for
unchanged-instrument reuse. The new planner must still take full replacement
if an instrument's actual payload or source identity changes.

Pad typing precedes the instrument launch and already uses object/control
replacement with a small wire update. Projection and composition account for
about six percent of its measured delay. This makes reducing full replacement
a separate problem from the baseline character latency. The remainder is not
fully attributed by this trace: it includes guest execution, host dispatch,
polling, and transport work, not just Forth drawing.

## Next measurement and implementation boundary

The existing ordinary physical journey, including subsequent View/Go menus,
has now passed on the committed changes. Its linked qualification preserves
the physical ACK/input evidence and matching interaction measurements. The
user confirmed standing approval for regular tests with system usage
monitoring; heavyweight runs remain sequential with the existing bounds.

For baseline typing, obtain fresh attribution before changing more simulator
primitives or renderer internals. MegaPad's `simulator/session.py` currently
rejects `start_phase_profile`, `phase_profile`, and `stop_phase_profile` as
unsupported instruction diagnostics. Therefore the physical driver's existing
`--phase-profile` flag cannot qualify native semantic execution. A diagnostic
extension must distinguish semantic steps from retired CPU instructions and
preserve the normal execution/event boundaries.

The August 30 emulator phase report and September 12 native exit profiles
predate several relevant fixes. They identify hypotheses, not current phase
costs; native-prefix timing also does not measure Python fallback time. Keep
fresh phase accounting separate from unprofiled wall-time comparisons.

Task prompt opening/submission still changes the document's rich fallback
topology. Improving the shared prompt lifecycle and representation is the
next application-level slice after these performance seams are measured.
Applet-specific terminal APIs or scenes are not part of that work.
