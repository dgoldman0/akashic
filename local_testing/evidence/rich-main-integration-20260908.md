# Rich-terminal integration to local mains — 2026-09-08

The user authorized merging the measured rich-terminal and native-simulator
state to both mains with recognized limitations. Both integrations were exact
fast-forwards; no conflict resolution, behavior change, cache enablement,
watchdog expansion, or extra simulator optimization was introduced.

## Integrated revisions

| Repository | Previous main | Verified main | Verified tree |
| --- | --- | --- | --- |
| Akashic | `af7dff9a2edf3754620a4440e68e96eae50c7ec8` | `b8110f28efa4fdd846d99e55b23595bb85062da1` | `30e298c009e4fae2068f25e74c36140de26d6b28` |
| MegaPad | `b399bd066d9ecdc87bf445dee6fd8e615255e61d` | `c69ae336c7232249c6969459cd812f3798916131` | `10a62ddbc311d7d50c5412191bd371ff5a562040` |

MegaPad's simulator branch already contained the entire rich vertical and the
older integration branch. The rich vertical was fast-forwarded to the simulator
head, then main to that head. Akashic main was fast-forwarded to its rich
vertical. The commit containing this ledger adds documentation only after the
verified Akashic head. No remote push is part of this local integration.

Both mains were clean during verification. Relative to the measured native
Desktop launch (`2a90108` / `3ea7bdc`), Akashic changes only its testing README
and evidence ledger; MegaPad changes only the bounded benchmark and its native
execution documentation. Production code is identical to that launch.

## Main-checkout verification

`make accel simulator-accel` rebuilt both independent extensions in MegaPad
main. Ignored binaries were not inherited through Git. The native simulator
extension SHA-256 is
`346065313de001316fbf9d5a2d1f334d1e03fdc7ed67de0a0f2c0374f2e50964`,
identical to the measured native Desk launch. The emulator extension SHA-256 is
`ec1d817f4e1fdd8fd025e308bb4945e41644881eb302213df6ef1d7659b4d77e`.

All runtime checks below ran sequentially in the main checkouts at checked-in
budgets, with no workers or concurrent test suites:

| Check | Result |
| --- | --- |
| Native clock, runtime, quantum, CATCH/THROW, memory, source-overlay, session/server and differential selectors | 246 passed, 11.67s |
| `MEGAFORTH_EXECUTOR=native make test-rich-terminal-dual` | 8 passed, 1.93s; both emulator and simulator production-source wire oracles |
| Akashic `local_testing/test_rich_terminal_cell_feed.py`, via MegaPad's `test-simulator` target with native selected | 4 passed, 0.87s |
| `python bench_semantic_cell_feed.py --output ../akashic/local_testing/out/main-integration-20260908/semantic-cell-feed.json` | PASS; default sibling-main selection, sequential Python then native |
| Bounded AudioOut status-byte probe in Python and native | Both reproduce the saved limitation exactly |

The 258 focused tests passed. The benchmark committed identical 560 cells,
revision 2, 4,848 decoded frame bytes and 2,432,950 feed steps. It also checks
frame types, timer state and final diagnostic counters. Feed time was
4.472267632s for Python and 1.746164160s for native (2.561x). Initial PT rows
improved 7.911x. These are kernel intervals on a shared host, not a new Desktop
measurement or a claim of overall simulator superiority.

## Preserved qualification and limitations

The physical launch and exact trace remain documented in
[the native simulator ledger](rich-desktop-native-simulator-checkpoint-20260908.md):

- Native reached the complete rich Desk at 383.163s versus Python's 897.182s.
  It reached real Pad and Daybook interaction milestones with physical ACKs
  preceding revision-authorized input.
- Later native interaction intervals were slower than the accelerated emulator.
  Desk-to-Daybook-task was 213.876s versus the emulator's 91.963s.
- The simulator reached 10 milestones, 18 acknowledged offers and 14 inputs,
  then paused with an MMIO error during the Sound Lab stage. The AudioOut
  presence/status read is a source-supported cause candidate; the exact live
  failing address was not captured. Both main executors reproduce the focused
  address/length/error/stack/three-step result exactly.
- Full simulator acceptance remains incomplete. The acceptance harness also
  did not terminate promptly on this backend error; the diagnosed run was
  interrupted. Native remains optional, with Python the simulator default.

The earlier emulator completed the full physical journey successfully, as
recorded in [its ledger](rich-desktop-emulator-reacceptance-20260908.md).
MegaPad's emulator execution path, assembler, shared terminal/session, BIOS
source, KDOS and system Forth modules are unchanged from that passing revision
`65cf61d`. Akashic's only production-source difference from that emulator pass
is the focused-qualified removal of redundant CELL storage validation.

No new full Desktop journey was run merely because the same source moved to
main. Main retains the existing qualification and its limits; the earlier
emulator pass is not relabeled as a fresh run at these main heads. Acceptance
uses `bios.asm`, assembled with labels for acceleration hooks. The known stale
checked-in `bios.rom` was not exercised by that pass and is not qualified here.
No broad persistence, networking or unrelated feature qualification was added.

## Evidence preservation and cleanup boundary

All 167 files from the rich Akashic worktree's `local_testing/out` were copied
without overwrites into the same relative directory in Akashic main, with
source/destination SHA-256 equality checked. This preserves 332,085,561 bytes
of original raw traces, diagnostics, images and screenshots, including prior
physical runs. Original worktree artifacts remain untouched.

The copy inventory is `local_testing/out/main-integration-20260908/preserved-evidence.json`.
The verification artifacts below are relative to that same integration folder.
The following workspace cleanup pass is read-only: worktrees, branches,
stashes, files and runtime leftovers have not been deleted as part of landing.

| Artifact | SHA-256 |
| --- | --- |
| `akashic-cell-feed.log` | `d4e4557121d462aa56b2b099bfeb3ce0451f08de540bd55ba11fc442ebae69d4` |
| `audio-mmio-probe.json` | `51b69857f6dcbed98a724beb2d55ab41cba148087a18358424664dbac66478e8` |
| `main-revisions.json` | `186ab2290ed8dc782f3875ab2b4a05b05d9422960929ddbcada014476f0c2e08` |
| `native-build.log` | `1445226c62652161cb0fc884082a884f3110dbac4cff56fb2bca86c22fab9fbc` |
| `native-units.log` | `f9dfc63447b01898b2001aaf9a51f96c9bf4147301492b400d8744c97adf521b` |
| `preserved-evidence.json` | `6d4260cecd9f8abaa67520f9bfdcf613a85051a277939b72f6b605f486d0a7b1` |
| `rich-dual.log` | `8024ad514d26cbf97520615602ac6c8e6800a2bf693bd0aafd6348a735ba6a14` |
| `semantic-cell-feed.json` | `420d37d7e0e942a27236ef77c32bdd96bb8f4439b28362eea78dea59d5ed069e` |
