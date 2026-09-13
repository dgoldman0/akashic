# Rich interaction integration and worktree retirement — September 13, 2026

Both local mains were fast-forwarded to the completed `rich-interaction-fixes`
branches, rebuilt and qualified from their ordinary sibling locations. Their
two worktrees and the enclosing support folder were then removed after a
second full preservation check. Subsequent commits add this integration record
and update MegaPad's checkpoint documentation; production sources are unchanged
from the verification below. This integration issued no remote push commands.

## Integrated sources and rebuilds

| Repository | Previous main | Qualified main |
| --- | --- | --- |
| Akashic | `d78adf00ff1505dcb9b3829e44c16524331ef5e4` | `c0cb3516e7999aee6cd374cf4c283806542010d2` |
| MegaPad | `69d0ba7ba185d13b6bf1fd336d1f3c3e9f601a3a` | `598ca0ca85f8e4802737eb89c4caced067fe0335` |

Both native extensions were rebuilt from C++ sources in MegaPad main, using
`python setup_simulator_accel.py build_ext --inplace --force --parallel 1`
and then `python setup_accel.py build_ext --inplace --force --parallel 1`.
Both completed successfully. Akashic's default sibling lookup resolved
MegaPad main, and both imported extensions came from that checkout:

- `_megaforth_native`: SHA-256
  `a94e93df6ef1d223c47734c248ac2a061645e800b0f6addeb968297b507ccb38`.
- `_mp64_accel`: SHA-256
  `ec1d817f4e1fdd8fd025e308bb4945e41644881eb302213df6ef1d7659b4d77e`.

These match the previously qualified binaries. The ordinary source image for
the new Desktop check was built afresh; no compiled Forth cache was used.

## Sequential checks from main

| Check | Result |
| --- | --- |
| Native executor C++ rebuild | PASS, 8.787 s supervised wall time |
| Emulator C++ rebuild | PASS, 53.688 s supervised wall time |
| MegaPad native parity, popup compositor/input and shared production-source emulator/simulator oracles | 127 passed, 3.32 s |
| Akashic changed regression selectors plus provider control-engine contract | 395 passed, 18.86 s |
| Fresh native physical Desktop journey, including extra ordinary View/Go popups | PASS, 224.407 s supervised wall time |

The 522 focused checks ran without pytest workers. The emulator/simulator
oracles used their checked-in budgets; no step limits were increased.
Builds, selectors and physical acceptance ran sequentially with resource
monitoring. The largest build peaked at 1.58 GiB aggregate RSS; physical
acceptance peaked at 438.512 MiB. The 3.5 GiB memory limits and 900-second
watchdogs were unchanged, and no resource guard fired. Build and focused-test
samples retained at least 14.03 GiB available system memory on the 16-CPU host.

The physical run was
`local_testing/out/rich-main-integration-20260913/physical-menus-i6q4chak/`.
Its manifest records X11 presentation through `pygame.display.flip`, **33
physical ACKs, 21 accepted inputs, 18 captured milestones and two CELL fallback
gates**. It exercised Pad menus, editing and tabs; Daybook task entry, date
advance and source opening; the normal Sound Lab continuation; File Explorer
View and Daybook Go opening/closing; and final Sound Lab focus restoration.
Inputs used the exact acknowledged offer and semantic hit map. Both mains were
clean and unchanged across the run. The final menu captures were visually
inspected: the duplicate CELL popup is absent and Go paints above the calendar.

- Physical manifest SHA-256:
  `4a985c45fc1f7ff7950e6e5bbb476f88b900c6fee7b8d95905520bd2451b0bc3`.
- Performance trace SHA-256:
  `5b598235c9cb75e5a91b7db0a40df41c47c42b7801c81091e6354a513e49271c`.
- Acceptance wrapper SHA-256:
  `9d3959eb7227dc9857fd874d04c81d6831f6f1f8bf1b7315ef15eeb099668fdb`.

This is a fresh functional qualification. The remaining interaction delays
and prior measurements are documented in the
[rich interaction report](../../docs/rich-terminal/RICH-INTERACTION-QUALIFICATION-20260912.md).
The emulator's focused shared-source oracles passed; this round's complete
physical Desktop run used the native simulator.

## Preservation and cleanup

The workspace archive is
`worktree-retirement-archives/2026-09-13-rich-interaction/`.
Its `pre-removal-manifest.json` records every worktree file, repository refs
and stashes, destination paths and fingerprints. Its SHA-256 is
`e763762c375157ec1816037b050bfb8d8ba456bc70d677a28261dd9b5646fac4`.
All **293 files totaling 273,549,493 bytes** outside Git were preserved:

- Akashic's output artifacts were copied into main at the same relative
  `local_testing/out/` paths, keeping the qualification report links usable.
- Other ignored Akashic/MegaPad files, including caches and compiled binaries,
  were copied into `retired-akashic/` and `retired-megapad/` in the archive.
- Every enclosing helper, diagnostic output and disk image was copied into
  `retired-support/`, preserving the original internal directory structure.

The separate September 12 diagnostic and physical evidence archives remain
unchanged under the workspace `local_testing/out/rich-interaction-fixes-20260912/`.
Original absolute worktree paths in raw evidence remain historical bindings;
the retirement inventory gives their current destinations.

Immediately before removal, every source and copied destination was checked
again. Both worktrees were clean and their heads reachable from main. The host
process audit found no working-directory, command-argument, mapping or open-file
reference to the old worktree folder. Both were removed with ordinary
`git worktree remove`, without force, followed by individually verified support
files and empty directories. Only the two main checkouts remain registered.
Branch refs and stashes were retained. Build/test logs, resource samples,
bindings, preservation checks and removal results remain in the archive.
