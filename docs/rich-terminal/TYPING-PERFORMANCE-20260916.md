# Typing latency — September 16, 2026

The working target is individual characters at 5–10 characters/second with
feedback around 100 ms. A bulk text RPC is not evidence for that target.

The current physical baseline is about 2.6 seconds per Pad character. Fresh
ordinary Desktop diagnostics at Akashic `9e42004` and MegaPad `eaa4d3b` sampled
the unchanged 8,192-step semantic owner boundaries. No compiler cache, source
substitution, step-budget change, or scheduler change was used. These runs
composed offscreen and are attribution evidence, not physical acceptance or
unprofiled latency benchmarks.

Artifacts: `local_testing/out/typing-20260916/baseline-skb838w4` (86 s,
298 MiB aggregate peak RSS) and `baseline-d5cta9ku` (call-stack follow-up).
The diagnostic distinguishes intervals whose packed guest phase sequence
changed; those intervals are not assigned to either neighboring phase.
Suspended call stacks are statistical samples, not exact function counters.

| Pad character work | Sampled semantic steps |
| --- | ---: |
| Complete input-to-offer interval | 49.6 million |
| UIDL aggregate phase | 8.7 million |
| Residual glyph planning | 8.2 million |
| Delta comparison/normalization | 7.4 million |
| Engine STEP, inclusive | 12.2 million |

The engine service cost is separate from the named phases above: most of it
falls in the generic OTHER phase. STEP repeatedly scans the complete control
and owner ledgers even when idle with no queue or completion to process.

## Idle service slice

`_RTAPT-IDLE-SERVICE?` proves the engine's existing storage geometry, exact
idle state, empty lifecycle queue, absent active operation, zero transaction
tails, and zero CELL geometry. Only that status-only branch avoids the deep
ledger audit. It does not certify ledger contents or cache a validation result.
Nonidle or incoherent descriptors enter the existing full validator.

RICH-BEGIN, queued lifecycle work, completion reconciliation, explicit
RTAPT-VALID?, and final publication continue using the existing full audits.
Caller changes between polls therefore remain subject to validation before
those banks acquire authority. Readiness results and sticky status behavior
are unchanged.

Focused Python/native execution and structural checks: 62 passed in 1.95 s.
The execution fixture observes storage/audit/PT boundaries explicitly; it tests
the production gate and STEP dispatch, not a whole PT session. Physical typing
and realistic cadence remain to be measured after the performance slices.
