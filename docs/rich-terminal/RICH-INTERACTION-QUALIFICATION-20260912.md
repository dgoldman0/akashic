# Rich interaction qualification — 2026-09-12

The current checked-source Desktop journey **passed physical acceptance** on
X11 with native simulator execution. It completed Desk, Pad menu/edit/tab
interactions, Daybook task/date/source interactions, the ordinary Sound Lab
continuation, and additional File Explorer View and Daybook Go menu captures.
The final frame restored Sound Lab focus and preserved the exercised app state.

## Qualified result and bindings

Run `physical-menus-ccskb7j5` exited zero after **242.439 s**, with peak aggregate
RSS **438.371 MiB** and no resource/watchdog stop. Its
[manifest](../../local_testing/out/rich-interaction-fixes-20260912/physical-menus-ccskb7j5/evidence/manifest.json)
and [trace](../../local_testing/out/rich-interaction-fixes-20260912/physical-menus-ccskb7j5/evidence/performance-trace.json)
record **34 physical ACKs, 21 accepted inputs, 18 captured milestones and two
CELL fallback gates**. The reference sink boundary was `pygame.display.flip`
with video driver `x11`. Inputs were bound to the exact composed/acknowledged
offer, scope and hit map; manual input RPC count was zero. Both initial and
final acknowledged offers passed the CELL fallback check.

Measured source trees were clean:

- Akashic: `fc66238f9f8b2490e92d6e7fbac2b2cb41ded4d6`.
- MegaPad: `598ca0ca85f8e4802737eb89c4caced067fe0335`.
- Native extension SHA-256:
  `a94e93df6ef1d223c47734c248ac2a061645e800b0f6addeb968297b507ccb38`.
- Physical wrapper SHA-256:
  `9d3959eb7227dc9857fd874d04c81d6831f6f1f8bf1b7315ef15eeb099668fdb`.

The run used ordinary `desktop-apt1` checked stored source, 280×84 geometry,
DejaVuSansMono at 18 px, a 0.75 s action delay and 10 s completion hold. The
900 s watchdog and 3.5 GiB limits were unchanged. No compiled Forth cache or
native exit profiler was enabled; trace timing remains non-normative.

## Changes qualified

The viewer paints menu popups after ordinary content within their region and
blocks pointer input through popup padding or disabled rows. The captured
File Explorer View popup has no duplicate CELL menu underneath, and Daybook's
Go popup paints above its calendar grid. Both were inspected in the final
physical captures and exercised through acknowledged semantic hit targets.

The control delta planner now joins exact identities through sorted,
caller-bounded scratch instead of repeated full searches. The residual planner
reads BACK outside menus and the preserved residue beneath menus, while later
opaque claims exclude cells. Screen damage tracks the accepted projection so
menu removal and unchanged final drawing preserve correct reuse.

Single-byte residual encodings use `C@`/`C!`; multibyte UTF-8 retains `CMOVE`.
The original `COREID`, `TASK-ID` and `CELL+` primitives execute natively with
exact word-identity admission. Glyph-slot growth can use DELTA, and fresh IDs
advance the producer frontier only after physical publication. Provider
owner-ledger validation now accounts for that growth.

Focused checks covered control identity/reordering/duplicate and capacity
rules; paired-plane precedence, bounds, Unicode and cleanup; screen projection
damage; glyph growth and publication/cancellation/frontier behavior; provider
ledger admission; popup painting and hit testing; and native parity, wrap,
stack budgets and shadowed words.
These were coordinated selectors during implementation, followed by the
physical run above. Individual console results are not presented as saved
artifacts where no output file was preserved.

## Matching unprofiled interaction observations

The local comparator is the earlier unprofiled physical
`simulator-improvements-20260912/native-desktop-final/performance-trace.json`,
with 14 inputs and 20 ACKs. Its clean source heads were Akashic
`fb4e5d9a7b098978ec12c809aa91b9941daa612f` and MegaPad
`08b37d5a5a0c09a301385868416529c239f58760`; native extension SHA-256 was
`9bf4f9e1d48418c237c3b5203474472f3c08053e1da6a5a4aeb2cdd670ea0eb4`.
It is distinct from the later instrumented offscreen diagnostic pair.

Seconds below run from input RPC start, reconstructed as
`input_result.elapsed_ns - rpc_duration_ns`, to the physical ACK that satisfied
the journey state. Where several offers intervene, the first newer ACK is
insufficient. The qualifying offer is the next action's authorizing offer.

| Interaction | Prior physical s | Current physical s |
|---|---:|---:|
| Pad File menu open | 7.730 | 2.813 |
| Pad File menu close | 4.451 | 3.245 |
| Pad character | 3.803 | 2.632 |
| Focus Daybook | 3.467 | 2.634 |
| Open task prompt | 6.791 | 6.198 |
| Type task character | 3.236 | 2.333 |
| Submit task | 8.276 | 7.834 |
| Advance date | 4.141 | 2.825 |
| Open Daybook source in Pad | 4.380 | 5.008 |

First complete Desk ACK was 71.895 s previously and 71.948 s currently. Source
opening currently produced an earlier ACK at 2.399 s, but the requested Pad
state was not complete until 5.008 s; the table retains that distinction.

These are single-run observations under uncontrolled host load. They show
useful improvements for several interactions, not a controlled throughput
estimate or a whole-journey speedup. The current journey adds seven steps after
Sound Lab, so its total elapsed time is not comparable with the earlier
185.862 s canonical run.

The extra File Explorer View popup opened in 9.019 s and closed in 9.992 s;
Daybook Go opened in 9.442 s and closed in 9.222 s. These actions ran with Sound
Lab's instrument workload already live. They cannot be compared directly with
the earlier five-applet Pad/Daybook timings. Modal task opening/submission still
requires full START when document-atomic fallback removes/restores the Daybook
menu/grid forest. That representation change and the later instrument costs
remain separate from the corrected one-run taskbar growth case.

## Failures and preserved evidence

The first physical attempt, `physical-menus-6xl_qq6x`, failed after 95.017 s and
four ACKs: complete Desk, Pad menu open/closed and Pad edit. Daybook focus then
raised guest exception `-3203` at the provider's final owner-ledger gate. The
correction in `fc66238` passed the coordinated focused 78-test selector and the
complete rerun above. The failed attempt remains preserved as a failure.

The older `baseline-pyypcklc` / `fixed-18hu_5nw` offscreen profiles identified
repeated identity comparisons, native guard/cell fallbacks and per-cell copies.
They predate later fixes and include observer overhead. Their exit counts and
exit-sampled native-prefix times are not Python fallback elapsed time or
physical performance evidence. The two incomplete observer/oracle attempts
remain separately recorded in that diagnostic inventory.

Physical raw evidence, all PNG captures, the failed run, prior unprofiled
comparator, wrapper and timing derivation are preserved outside both worktrees,
relative to the workspace root, under
`local_testing/out/rich-interaction-fixes-20260912/physical-evidence`. Only the
three `desktop.img` files were omitted; their hashes are recorded. The verified
archive has 119 members and 15,303,144 bytes:

- `rich-interaction-physical-evidence-20260912.tar.gz`
- SHA-256: `951392ce2acd358e75929dfac2e74639e8b64723a59dddd0d264cf726be33c9a`
- Detached `.tar.gz.sha256` and `.manifest.json` accompany it.

The separate historical diagnostic archive is
`rich-interaction-diagnostic-evidence-20260912.tar.gz`, SHA-256
`2d62c182c6f9e3076e3a82f6f2493ee4b6c9798f2a702e4b892c60bd32fd4119`.
Its four disk images were excluded; diagnostic PNGs, raw traces, bindings and
included/excluded inventories were retained.
