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
Desk's exact eleven service IDs are parsed from its setup word.

Those structural checks prevent a move or decomposition from silently dropping
a route, but they are not counted as behavioral execution. A source comment can
therefore never substitute for the exact parsed capability/service set or the
direct-input handler anchor. Each behavior group points separately to exact
emulator profiles, pytest nodes or standalone qualification drivers.

| Applet | Groups | Covered | Partial | Prerequisite-only | Named prerequisites | Evidence references |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Library | 4 | 2 | 2 | 0 | 3 | 19 |
| Streams | 4 | 1 | 3 | 0 | 4 | 23 |
| Agent | 4 | 2 | 2 | 0 | 2 | 22 |
| Daybook | 3 | 1 | 2 | 0 | 2 | 9 |
| Pad | 3 | 2 | 1 | 0 | 2 | 10 |
| Grid | 2 | 0 | 2 | 0 | 2 | 5 |
| FExplorer | 3 | 1 | 2 | 0 | 3 | 8 |
| Desk | 3 | 1 | 2 | 0 | 3 | 11 |
| SoundLab | 3 | 0 | 1 | 2 | 3 | 2 |
| **Total** | **29** | **10** | **17** | **2** | **24** | **109** |

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
- Streams live-network profiles are supplemental. Deterministic offline, XIO,
  owner, codec, persistence and Desk journeys are the preservation gate.
- Agent retains offline, scripted, OpenAI and Codex providers, all access
  presets, authentication/device/settings behavior and durable transcript
  semantics.
- Daybook and Pad retain the current semantic shared-document journey even
  though L6 will replace its implementation with the canonical resource
  session.
- Daybook's L5 capability edge is now characterized in `daybook-contracts`:
  direct agenda dispatch returns the exact serialized model, while forced task
  capture persistence failure clears the result and restores the model, dirty
  state, discard state and allocator balance. Its remaining binding-advance
  failure prerequisite belongs to L6.
- Grid and FExplorer already have strong evaluator/storage and verified-transfer
  evidence. Their prerequisites are limited to controller or handler edges that
  those tests do not execute.
- SoundLab's happy path is real, but capability, output-fault, unsaved-close and
  AudioOut-ownership claims are not. The ledger prevents selecting it as an
  early consumer without first adding the relevant evidence.
- Desk's visible smoke journeys are retained, but they do not prove every host
  state transition. Transactional launch rollback and child close/context/fault
  characterization are hard prerequisites before L9.

The legacy `local_testing/test_desk.py` is not evidence because it imports the
removed `local_testing/emu` package. `test_app_compositor.py` targets a deleted
module. The Desk-specific suffix in `test_applet_close.py` is currently dormant;
only its app-shell prefix runs, so the dormant cases are described as an L9
prerequisite rather than cited as passing coverage.

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
