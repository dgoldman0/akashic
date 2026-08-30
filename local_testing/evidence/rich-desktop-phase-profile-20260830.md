# Rich Desktop guest-phase profile — 2026-08-30

Status: non-normative performance evidence from the already-qualified local
reference-sink Desk/Pad/Daybook journey. The semantic journey passed at the
host presentation-API boundary. This ledger may guide optimization, but it
does not qualify physical UART delivery, panel scanout, e-paper refresh,
touch, RTL cycle counts, or wall time on a future processor.

## Revisions and invocation

The successful run used exact committed heads:

- Akashic `c5f227106231cee181b81a86097b62c228dc3661`;
- MegaPad `6a9f10ea505369a993c13a8225b3e473fbb84980`.

It used the timing-correct single-lane native scheduler, a cold-source
`desktop-apt1` image, the ordinary Desk/Pad/Daybook acceptance route, a
500,000-instruction scheduler batch bound, and a caller-bounded 4,096-record
phase observer:

```text
MEGAPAD_ROOT=<megapad-rich-terminal-vertical> \
python local_testing/akashic_tui.py accept \
  --profile desktop-apt1 \
  --output local_testing/out/desktop-apt1-c5f2271-phase.img \
  --artifact-root \
    local_testing/out/desktop-apt1-phase-profile-c5f2271-6a9f10e \
  --hold-seconds 0 \
  --phase-profile \
  --phase-profile-max-events 4096
```

The command exited zero with `Physical desktop acceptance: PASS` after
204.273 seconds. It completed all twelve offers at 5,024,500,000 retired guest
instructions, 1,787 decoded protocol frames, and 783,434 decoded frame bytes.
The ignored raw artifact directory contained:

- `performance-trace.json`, SHA-256
  `0cc7663646c99a5500465ad185c2c68c4c8be8edac64baa6ec90f1ac76773f2d`;
- `manifest.json`, SHA-256
  `d0ad3dd3aab75e8422fe14e0f9aa246090b4ee0c9823b6a8f32b7b2a83671326`.

`local_testing/out/` is intentionally ignored. These hashes bind this durable
summary to the local raw evidence while that output is retained.

## Observer boundary and integrity

The first real retained offer was observed at 4,088,500,000 instructions and
8,177 batches. That status is only an ordered lower boundary: the guest was not
frozen while the client resolved the Forth event cell and attached the generic
MegaPad observer. The observer's authoritative measurement start was
4,091,500,000 instructions and 8,183 batches, so attachment lag was exactly
3,000,000 instructions and six batches.

The half-open measurement window ended at the final offer's pre-screen status,
5,024,500,000 instructions. Its exact width was therefore 933,000,000 retired
guest instructions. Observer shutdown occurred later at 5,028,500,000, and
that post-window work is excluded.

The observer made 1,875 successful batch-boundary samples. It reported no
read error, dropped record, dropped transition, end straddle, or open terminal
phase. Both ends were `OTHER`, and the marker lifecycle was complete. It
observed 374 sequence transitions, of which 246 occurred between samples and
were therefore coalesced. Attribution is consequently bounded rather than
complete: a missing or zero-length short phase is not evidence that the phase
did no work.

The two preceding integration attempts also passed the complete semantic
acceptance journey but correctly refused phase claims:

1. Akashic `939c76c` with MegaPad `fb6d58f` rejected the ordinary unaligned
   Forth `VARIABLE` cell. MegaPad was corrected to admit any complete eight-byte
   span contained in one mapped memory region, matching the architecture's
   unaligned 64-bit access contract.
2. Akashic `897888b` with MegaPad `6149560` compared the observer start against
   the stale first-offer status. The client was corrected to use the observer's
   returned quiescent counters as the measurement identity and to retain the
   first-offer difference only as attachment lag.

Those attempts are diagnostic hardening history, not performance evidence.

## Bounded phase attribution

The following totals cover the exact 933.0-million-instruction window. Bounds
come from sampling after exact 500,000-instruction batches; percentages are of
the complete window.

| Phase | Closed observed visits | Lower bound | Upper bound | Window share |
| --- | ---: | ---: | ---: | ---: |
| UIDL aggregate | 10 | 10.5M | 20.5M | 1.1–2.2% |
| Snapshot import | 0 | 0 | 0 | not attributable |
| Control plan | 11 | 26.0M | 37.0M | 2.8–4.0% |
| Claim plan | 11 | 1.5M | 12.5M | 0.2–1.3% |
| Residual plan | 11 | 75.5M | 86.5M | 8.1–9.3% |
| Reserve/wrap | 5 | 0 | 5.0M | 0–0.5% |
| Hybrid preflight | 11 | 159.5M | 170.5M | 17.1–18.3% |
| Candidate validation | 0 | 0 | 0 | not attributable |
| Target pack | 11 | 3.0M | 14.0M | 0.3–1.5% |
| Delta compare/normalize | 11 | 257.0M | 268.0M | 27.5–28.7% |
| RTAPT capture | 9 | 9.0M | 18.0M | 1.0–1.9% |
| Commit precheck | 0 | 0 | 0 | not attributable |
| RTAPT audit | 6 | 0 | 6.0M | 0–0.6% |
| Wire encode | 8 | 0.5M | 8.5M | 0.1–0.9% |

All identified named phases account for 542.5–646.5M instructions, or
58.1–69.3% of the window. The coupled `OTHER`/unattributed complement is
286.5–390.5M. Hybrid preflight plus delta comparison alone accounts for
416.5–438.5M, or 44.6–47.0% of the entire post-first-offer journey.

The zero rows above are deliberately labelled *not attributable*. Sequence
jumps prove that short transitions were hidden inside some sampling intervals;
the trace cannot honestly distinguish their individual costs.

## Certified-unchanged decision

Offers 1 and 2 give a concrete unchanged-representation case. The Pad focus
input advanced CELL, model, and retained scope revisions from 4 to 5 and still
required a real offer, physical composition, and acknowledgement, but both
offers had:

- draw count 809;
- complete pixel SHA-256
  `8a5c819b5030c9ae2f05461f37062f12fc73fc00d8837ce6427b72178cdef1a5`;
- retained-only pixel SHA-256
  `7cde5af67a462b64966f4ff1b18b33c9fcad36c7ba2b134416453f1904b70a0a`;
- retained-text SHA-256
  `5d5463f4f19768d1491bea06e855d4e4af160140f33f6d1da03eda85739a64a6`.

Their exact offer-status gap was 69.5M instructions. The second pass still
spent bounded named work of 43.5–51.5M, including 14.5–15.5M in hybrid
preflight and 24–25M in delta comparison. It added only one machine
publication, five protocol frames, and 384 decoded bytes because the existing
late path correctly reduced the result to a minimal revision fence.

This evidence justifies a conservative certified-unchanged representation
fast path and a measured rerun. It does **not** justify suppressing the logical
offer, revision, transaction, physical composition, or exact ACK lifecycle.
Revision equality is not a usable certificate—the unchanged example advanced
all three revisions. The shortcut must instead prove renderer-neutral source
and CELL equivalence against the exact acknowledged target, reuse only that
target's representation under the new revision, and fall back to the full
candidate path for every changed or ambiguous case.

This is an instruction-count opportunity, not a promised wall-time result.
The same run measured mean host projection time of 13.17 ms and mean host
composition time of 97.56 ms, both far below the emulated guest work between
offers, but a future processor, transport, and panel have different costs.

## Physical scope still open

The manifest's physical boundary is `pygame.display.flip()` on X11. No byte in
this run traversed an external 115,200-baud UART, and no controller confirmed
an e-paper refresh or panel settling interval. Compression, a faster negotiated
transport, partial-refresh cadence, ghosting policy, color waveform choice,
and touch remain open until the physical link and panel baseline is built and
measured.
