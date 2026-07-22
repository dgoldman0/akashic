# Refactor Landing L1 functional-preservation baseline

Landing L1 records the current product behavior that the refactor must preserve.
It changes no production Forth behavior. The authoritative ledger is
`local_testing/refactor_functional_baseline.json`; the small host-only validator
is `local_testing/refactor_functional_baseline.py`.

This is not a claim that every existing action already has an end-to-end test.
Each behavior group is marked either:

- `covered`: the named evidence directly gates the complete group at the
  granularity needed by the active plan; or
- `partial`: substantial current evidence exists, but the group also names the
  exact characterization prerequisite that must land before a specified
  touchpoint; or
- `prerequisite`: no current test proves that behavior group, so the ledger
  makes no evidence claim and names the characterization required before use.

A prerequisite is conditional on its `trigger`. For example, L3 may convert
FExplorer's already-qualified transfer scope without first testing unrelated
create/rename/delete faults. If L3 touches those smaller mutations, their named
characterization becomes part of L3 before the production change. Likewise,
SoundLab is not an early proving consumer unless the relevant SoundLab
prerequisite is satisfied.

## Scope and baseline

The ledger covers Library, Streams, Agent, Daybook, Pad, Grid, FExplorer, Desk
and SoundLab. Game and Worlds are explicitly absent. The baseline starts at
`fc291d60ab76239cded3e5654df446d8737f5d0b`, after the reviewed scope
reconciliation.

For the eight UIDL applets, the ratchet records the exact current menus,
actions, shortcuts and element IDs and compares them with the live UIDL. Desk's
global shortcuts are recorded explicitly. Applet-specific direct input outside
UIDL is recorded as a human-readable key-to-action map and anchored to the
normalized handler body, so dropping or remapping a key requires a reviewed
ledger update. Every applet also pins its current component identity, public
lifecycle entry words, exact capability-ID set and named provider identities;
Desk's exact eleven service IDs are parsed from its setup word. The named
Daybook resource service now returns the owner-lent offer containing its exact
RID and owning pool; no extra global-pool service changes that service set.

Those structural checks prevent a move or decomposition from silently dropping
a route, but they are not counted as behavioral execution. A source comment can
therefore never substitute for the exact parsed capability/service set or the
direct-input handler anchor. Each behavior group points separately to exact
emulator profiles, pytest nodes or standalone qualification drivers.

| Applet | Groups | Covered | Partial | Prerequisite-only | Named prerequisites | Evidence references |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Library | 4 | 3 | 1 | 0 | 2 | 19 |
| Streams | 4 | 1 | 3 | 0 | 4 | 23 |
| Agent | 4 | 3 | 1 | 0 | 1 | 23 |
| Daybook | 3 | 2 | 1 | 0 | 1 | 9 |
| Pad | 3 | 2 | 1 | 0 | 2 | 10 |
| Grid | 2 | 0 | 2 | 0 | 2 | 5 |
| FExplorer | 3 | 1 | 2 | 0 | 3 | 8 |
| Desk | 3 | 3 | 0 | 0 | 0 | 14 |
| SoundLab | 3 | 0 | 1 | 2 | 3 | 2 |
| **Total** | **29** | **15** | **12** | **2** | **18** | **113** |

`partial` does not mean the entire behavior group is untested. It means at
least one explicitly listed edge still needs characterization before the
trigger named in the ledger. `prerequisite-only` is intentionally stronger: it
claims no behavioral evidence at all. This avoids both false coverage claims
and a broad test-writing project for code an active landing may never touch.

## Important evidence decisions

- Library's Gate 4 owner, storage, query, projection, maintenance and
  fresh-process evidence is retained. Its source ratchet now pins both the
  projection owner's calls to the canonical RCON descriptor constructors and
  the capability identities owned by that neutral contract module; moving the
  repeated construction mechanics does not weaken the Library surface check.
  L8's expanded 162-assertion applet fixture closes the controller-edge
  prerequisite through the real controller implementation: it covers lifecycle
  scopes, search reset/cancel, collection filtering and return, paging, conflicts,
  authoritative reload, prepared-create failure and byte-exact retry, and
  close/discard behavior. The ledger therefore promotes the existing Library
  applet-surface group to covered without adding or removing a product action.
- Streams live-network profiles are supplemental. Deterministic offline, XIO,
  owner, codec, persistence and Desk journeys are the preservation gate.
- Agent retains offline, scripted, OpenAI and Codex providers, all access
  presets, authentication/device/settings behavior and durable transcript
  semantics. L7's `agent-provider-ui-commands` profile closes the provider
  action prerequisite by driving the real Clear, Reconnect and Refresh Models
  callbacks through parsed UIDL state, pinning rendered idle/running/loading/
  error text, exact success/failure toasts, dirtying and one provider callback
  per action. The same fixture proves atomic access-profile replacement and
  exact Desk-policy rejection after malformed construction or later tampering.
- Daybook and Pad retain the current semantic shared-document journey while L6
  replaces its transport plumbing with the retained, protocol-neutral resource
  session.
- Daybook's L5 capability edge is characterized in `daybook-contracts`:
  direct agenda dispatch returns the exact serialized model, while forced task
  capture persistence failure clears the result and restores the model, dirty
  state, discard state and allocator balance. The L6 prerequisite is also
  closed: a forced post-commit binding-advance failure proves one authoritative
  revision is recoverable without duplicating the mutation.
- Agent and Pad retain their active-close and dirty-close/Save-All
  prerequisites. L9 moves the generic host side of the descriptor callback
  boundary and replaces Pad's raw widget-header access with the public
  equivalent, but does not change applet ownership or the uncovered
  close/Save-All/menu routes. Their existing active-run, storage, and Desk
  journeys are not mislabeled as direct coverage of the missing close
  branches.
- Grid and FExplorer already have strong evaluator/storage and verified-transfer
  evidence. Their prerequisites remain limited to controller or handler edges
  that those tests do not execute. L9 leaves Grid's callback and input
  implementation intact, so generic host mocks are not presented as proof of
  Grid's dirty-close branches.
- SoundLab's happy path is real, but capability, output-fault, unsaved-close and
  AudioOut-ownership claims are not. L9 deliberately leaves its applet-specific
  lifecycle and raw widget header alone for the later MediaLab rebuild; neither
  a generic host fixture nor the happy-path audio smoke closes those gaps.
- L9 closes Desk's three host-specific prerequisites with two focused drivers.
  `test_desk_host_characterization.py` covers transactional launch rollback,
  tiling, focus/minimize/restore, full-frame state, and child UIDL-context
  isolation. The Desk profile in `test_applet_close.py` covers close decisions,
  callback context, activation-entry failure, shutdown-fault containment,
  all-child negotiation, and draining. The ledger names those executable
  contracts without itself claiming a particular guest run result. Both host
  drivers require exact heap and XMEM restoration at their failure, drain, and
  close gates; no allocator-loss tolerance remains.

The legacy `local_testing/test_desk.py` is not evidence because it imports the
removed `local_testing/emu` package. `test_app_compositor.py` targets a deleted
module. `test_applet_close.py` now exposes separate shell and fully linked Desk
profiles, while `test_desk_host_characterization.py` owns the complementary
launch/layout fixture. Run results are recorded by the L9 landing qualification,
not inferred from a driver's presence in this ledger.

## Commands

Validate the complete ledger without MegaPad, an emulator image or any ext4
backend:

```bash
python3 local_testing/refactor_functional_baseline.py --check
python3 -m pytest -q local_testing/test_refactor_functional_baseline.py
```

The broader host qualification used for the L1 landing is:

```bash
python3 local_testing/refactor_inventory.py --check
python3 -m pytest -q \
  local_testing/test_refactor_inventory.py \
  local_testing/test_refactor_functional_baseline.py \
  local_testing/test_akashic_tui_packaging.py \
  local_testing/test_desk_gate0_baseline.py
```

The focused L9 host qualification runs the generic host, Desk launch/layout,
and shell/Desk close contracts as real linked guest images:

```bash
python3 local_testing/test_applet_host.py
python3 local_testing/test_desk_host_characterization.py
python3 local_testing/test_applet_close.py --profile all
```

These profiles use the composed MP64FS-backed abstract VFS and do not require
ext4.

## Update rule

A production landing identifies the ledger behavior IDs it touches. It runs the
existing evidence before and after the change and satisfies any prerequisite
whose trigger applies. A prerequisite may be removed only when its replacement
test is named in the behavior's evidence. Changing a menu, action, shortcut,
public word, capability, provider, service ID, intentional status or journey is
product work and requires separate approval; an internal move is not such
approval.

The JSON is reviewed policy, not generated output. Update it only to record
newly landed evidence, a separately approved behavior change, or a deliberate
change in active landing scope.
