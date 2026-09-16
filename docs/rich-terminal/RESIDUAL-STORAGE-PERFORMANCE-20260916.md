# Residual rows and storage proofs — September 16, 2026

Akashic `2e0ada0` and `87abdaa` remove repeated residual reconstruction and
storage-authority traversal from ordinary typing. The sampled first-character
interval falls from 32.819 million to 19.719 million semantic steps, about
40%. The final unprofiled repeat records 0.636 s isolated feedback and a
1.124 s burst median, with all 19 characters preserved. Timing varies across
this shared-host series; the roughly 100 ms target remains unmet.

## Physical typing

The ordinary source-mode Desktop, font, 3080×1764 viewport, keyboard
forwarder, and complete-frame physical ACK remain the same. One isolated
character precedes 18 individual inputs at 5 Hz. Profiling is disabled.
Latency starts at actual dispatch; intended-to-actual scheduling delay is
separate. All runs display `~fluid typing 12345` correctly.

| Run | Isolated feedback | Burst median | Last-character drain |
| --- | ---: | ---: | ---: |
| Earlier previous-code run, `fixed-t8g31h2a` | 0.948 s | 1.578 s | 1.292 s |
| First current-code run, `fixed-gt41yelx` | 1.178 s | 2.166 s | 1.767 s |
| Fresh previous-code run, `baseline-3ccw15y1` | 1.085 s | 1.904 s | 2.732 s |
| Current-code repeat, `fixed-5wtujzev` | 0.636 s | 1.124 s | 1.136 s |

The first current-code result was slower despite much less guest work.
Unchanged composition also rose from the earlier 50–62 ms range to
77–114 ms. A fresh previous/current pair was therefore run sequentially;
those compositions range from 56–93 ms and 47–64 ms respectively. Changing
host conditions prevent a precise causal percentage from these single runs.
The slower result is retained, not discarded. The step reduction is the
stronger attribution evidence; the repeated latency result is encouraging.

The current repeat's first response consists of 522.288 ms to observe the
offer, 50.946 ms of harness evidence/reconstruction/checking, 54.796 ms of
composition, and 7.815 ms of flip/ACK. Offer observation includes guest
execution, host services, transport, and polling; it is not an exclusive
guest timer. Worst input scheduling delay is 333.709 ms, additional to the
reported actual-dispatch latency. This remains a short cadence experiment,
not a sustained typing or fluidity qualification.

All new runs bind clean MegaPad `9bf21e6`; the previous-code run binds
Akashic `409a578`, and both current runs bind `87abdaa`. The previous code
was measured from a temporary detached checkout under `/tmp`, removed after
the comparison. Development remained on the main checkout. Native execution
and the compositor are unchanged during this pass.

The first current run takes 67.190 s overall and peaks at 380.141 MiB;
the fresh previous run takes 65.341 s and 375.023 MiB; the current repeat
takes 60.668 s and 375.441 MiB. All exit 0 without a guard stop.

## Residual damage

The acknowledged residual bank contains holes where semantic widgets paint.
`_RTHP-RD-SCAN-ACTIVE-ROW?` used to treat every such hole as new damage, even
after the exact packed non-menu coverage comparison had proved that those
holes were unchanged. One real Pad character had five damaged rows on entry,
but this scan dirtied and rebuilt 41 rows.

The scan now marks these gaps only when coverage differs. It still validates
run geometry, order, non-overlap, text bounds, and row completeness. Actual
CELL/residue damage and old/current menu rows remain independently marked;
changed coverage retains the conservative reconstruction path. Clean rows
copy the acknowledged payload with the existing text-reference rebasing.

The same real character now rebuilds rows 0, 1, 3, 39, and 42, exactly the
initial combined damage map. Residual planning falls from 8.192 million to
1.434 million sampled steps, about 82.5%. The row fix alone reduces the
sampled total to 25.921 million steps.

## Storage authority

The adapter has twelve mutable buffer spans plus its descriptor. Each used
to trigger a complete current-UCTX storage query, repeatedly validating
mounted relations and traversing the same document. The new implementation
constructs a fresh enclosing interval after checking each span's geometry.
One successful existing authority query proves all contained spans disjoint.
This interval is only queried: its gaps are never read, written, or owned.

Interleaved widget storage can reject the enclosing interval even when every
actual span is safe. Such layouts retain the exact thirteen individual
queries. Invalid span geometry and an enclosing length that cannot fit a
signed cell also take the exact path. No proof survives the call or crosses
a context change, and complete source-state validation remains in the query.
The change adds no public layout, ABI version, capacity, or cached authority.

Inclusive storage-check samples fall from 6.423 million to 0.541 million
steps. This overlaps phase attribution and must not be added to the totals.
Focused execution tests show one authority traversal for clustered buffers
and fourteen for valid interleaved layouts, including the rejected enclosure.

## Diagnostic attribution

All three diagnostics use the same row observer and unchanged 8,192-step
owner boundaries, with native counters frozen when sampling stops. Sampling
runs from the first real keyboard send through observation of its complete
offer. Signal delivery and boundary sampling make these approximate work
attributions. Observer-enabled wall times are not physical latency results.

| Guest phase | Before, million steps | Row fix | Both fixes |
| --- | ---: | ---: | ---: |
| Entire sampled interval | 32.819 | 25.921 | 19.719 |
| Residual planning | 8.192 | 1.434 | 1.434 |
| UIDL aggregate | 7.299 | 7.299 | 3.728 |
| Delta comparison/normalization | 7.414 | 7.414 | 7.406 |
| Hybrid preflight | 2.916 | 2.925 | 2.925 |
| Other | 4.776 | 4.620 | 2.007 |

Other small phases and phase transitions account for the balance. The final
profile executes 19,715,270 of 19,719,018 steps natively, about 99.98%.
Boundary count drops from 4,006 to 2,407. Final sampled C++ run time is
262.035 ms and settlement is 37.063 ms. Inclusive native dispatch is
342.749 ms, guest dispatch 389.906 ms, data/return snapshots 86.017 ms, and
host terminal service 83.949 ms. These method timers overlap; do not sum them.

Delta comparison now accounts for about 38% of sampled work. Its control
join includes 2.130 million steps in index sorting; glyph compatibility and
ID normalization contribute further repeated traversal. Final hybrid
preflight contributes about 15%, including 2.179 million inclusive steps in
glyph validation. Those are the next measured guest candidates. Native
execution and host suspension bookkeeping remain material simulator costs.

## Validation

The row slice passes 143 focused checks in 5.52 s. Coverage includes leading,
internal, trailing, and wholly claimed row gaps, changed coverage, retained
damage, malformed runs, payload equality, reference rebasing, and guards.
The storage slice passes 70 checks in 1.94 s, including production helpers on
Python/native, every span's actual overlap, invalid/wrapping ranges,
interleaved authority, fresh mutation observation, seeded interval oracles,
and enclosing DO-loop return-stack balance. The earlier unrelated stale
contract-heading assertion remains deferred; this pass does not rerun it.

The full ordinary physical Desktop journey at the final clean heads passes
18 milestones, 21 interactions, 26 post-flip ACKs, and both complete CELL
fallback gates. Milestone and input sequences equal `physical-menus-bjjn1z7v`.
Pad, Daybook, menu and app interactions, and restoration remain accepted.
There are zero manual input RPCs; the sink is `pygame.display.flip` on X11.
Artifact `physical-menus-shyfa8mg` takes 123.010 s and peaks at 441.895 MiB,
with exit 0 and no guard stop. This is functional evidence, not a controlled
full-journey performance comparison.

All tests run sequentially under the existing limits. Resource glances during
final qualification remain above 9 GiB available system memory. Physical runs use
source mode, native execution, a 900 s watchdog, and a 3.5 GiB aggregate RSS
guard. The native extension remains
`b6f7c92fcf51b34a7e8cf8ed2cd0536e9bc0741c494b2b936fb71ae3803616e7`.
Raw diagnostics are `baseline-sr2nwhqm`, `fixed-1rsqlg1c`, and
`fixed-39y7_4ck` beneath `local_testing/out/typing-20260916/`.

`local_testing/evidence/residual-storage-20260916.json` preserves every
unprofiled trial above, source/binary/font bindings, physical event times,
Desktop evidence, diagnostic aggregates, row samples, and raw-profile hashes.
The final diagnostic directory retains the row observer, harness, report
aggregator, and analysis script. Commands and artifact details are in
`local_testing/evidence/typing-20260916.md`.
