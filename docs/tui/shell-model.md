# Ordinary shell model

`shell-model.f` defines the renderer-neutral state used by Desk's ordinary
CELL divider paint, taskbar paint and taskbar pointer hit testing. It does
not contain terminal IDs, wire encoders, retained scenes or app-name rules.

Desk builds one inactive caller-owned bank before painting. Each bank has a
128-byte header, a bounded array of 168-byte records and a copied text arena.
The header records screen dimensions, component instance ID/generation,
completed-frame epoch, prompt/modal flags, taskbar separator and occupied
extent. Records identify a pane, task or launcher and carry exact screen
CELL bounds, pane content bounds, state, lifecycle identity, copied display
label, copied full title and, for catalog launchers, copied catalog ID.
String fields use bank-relative offsets. No descriptor, slot or catalog
pointer survives publication.

Pane outer rectangles own only the existing right and bottom divider cells.
Content rectangles remain unchanged; there is no new title row. Full-frame
presentation includes only the focused ordinary pane plus visible overlays.
An overlay and a full-screen single pane may have equal outer/content bounds.
The ordinary host supplies `AHOST-PRESENTED?`, which also excludes minimized,
retiring and regionless children. Pane identity includes kind, slot ID and
component instance ID/generation; an overlay's display key is the positive
magnitude of its negative slot ID, while its identity retains the signed ID.

Tasks include live minimized children and exclude overlays. Selected and
minimized states are mutually exclusive. Each ordinary label has an exact,
nonoverlapping slot; separator cells are not hit targets. Title prefixes end
at shared grapheme boundaries and fit the existing ten-cell title allowance.
When the row fills, complete remaining entries are omitted from both paint
and hits. Pinned catalog entries use the same rules. Their ordinary click
resolves the copied catalog ID under the captured catalog generation and
calls the normal catalog-open path, which either restores/focuses the live
app or launches it. Disabled/quarantined entries remain visible and inert.
Legacy pre-catalog TOML pins remain visible but have no launch authority.

Desk reserves two 49,152-byte banks with 140 records each. Its component
registry bounds live instances at 64; two records per child plus 12 pins fit
this record allowance. The text arena remains independently bounded. Any
record or string capacity refusal declines the **whole** model and paints the
complete legacy CELL shell; no partial model is published. Model mutation
rejects invalid, wrapping, null, unaligned or module-scratch-aliasing storage,
corrupt headers and source/destination bank aliases. Sealing rejects further
append/copy operations. Caller-owned memory must actually back admitted spans.

An active prompt owns the bottom row and suppresses the taskbar model and its
hits. A launcher overlay blocks background taskbar input while preserving its
paint. Changes to layout, child lifetime or focus invalidate old taskbar
publication before dispatch. Even a captured task entry must resolve its
exact slot and component instance identity against the live host.

## Shared host observation

| Word | Stack | Purpose |
| --- | --- | --- |
| `AHOST-SHELL-MODEL!` | `( model-or-zero host -- )` | Publish or detach a completed borrowed bank |
| `AHOST-SHELL-MODEL@` | `( host -- model-or-zero )` | Read the current completed model |
| `AHOST-SHELL-OBSERVE!` | `( callback context -- )` | Install synchronous ordinary host observation |
| `AHOST-SHELL-DRAW-COMPLETE` | `( host -- ior )` | Observe after complete shell, children and prompt paint |
| `AHOST-PRESENTED?` | `( slot fullframe host -- flag )` | Match actual host paint visibility |

The observer receives `( model host context -- )` and must copy anything it
keeps before returning. The surrounding application shell calls
`SCR-DRAW-COMPLETE` after the top-level paint returns. Consumers stage the
owned copy here and publish only after the explicit successful
`ASHELL-DRAW-COMPLETE` observer phase. Merely guessing the next screen
generation does not prove that root paint completed.
Observation is independent of the most recently active child UIDL context.
A null model signals resource refusal or detachment; quiesce and shutdown
publish null before instance storage retires. Callback throws are returned as
an `ior` and cannot replace or interrupt the ordinary shell's completed paint.

The shell model remains ordinary application authority. Future retained
publication must copy and validate it, qualify corresponding input targets,
and preserve the existing CELL fallback when a family cannot be admitted.

The independently owned [shell snapshot](shell-snapshot.md) source implements
this deep validation and completed-root transaction without adding a child
UIDL family or changing ordinary presentation.
