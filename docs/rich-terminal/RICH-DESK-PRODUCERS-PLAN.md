# Rich Desk producers

Implementation branch: `feature/rich-desk-producers`, based on merged Akashic
main `ff36b90` (2026-09-30). Paired MegaPad branch:
`feature/flowing-rich-terminal`, qualified at `8dfca6c`. The numeric/FP work
already on main remains part of this baseline.

## Scope and invariants

Publish the semantic state needed by the flowing terminal appearance while
preserving Desk's pane geometry, application behavior, and complete CELL
drawing. MegaPad supplies negotiated PANE, STATUS_FIELD, TASKBAR/TASK/LAUNCHER,
FIELD, and typed TEXT_GRID contracts; WAVEFORM and bounded series already
exist. Appearance remains the host's choice.

Ordinary shared widgets and host state own the meaning. Applets use normal
widget/model APIs and never gain terminal writers or retained scenes.
Capture follows the completed draw lifecycle, copies borrowed state into the
existing immutable attempt, produces exact paint claims, and leaves all
unclaimed content to the residual glyph producer. Unsupported or refused
families preserve the complete ordinary display and existing supported rich
families. No text patterns or app names supply missing roles.

Input remains bound to the acknowledged generation, frame and content
revision. The ordinary application handles edits, selection, focus, restore,
launch, clamp/wrap and redraw. New capabilities are selected only after the
whole producer and return path have passed paired checks. Source and storage
limits remain caller-derived and are included in the existing admission pass.

## Implementation order

1. Mirror the paired APT contract and qualify the new main baseline. Extend
   neutral/provider capability translation only with the family that uses it.
2. Add NUMBER, FORMULA and ERROR to the existing USCOL/TGRID model, preserve
   STX1 and whole-cell input, then migrate Grid's data/header area to the
   canonical widget. Keep its formula row and exact header/data widths.
3. Add canonical structured status state and STATUS_FIELD publication through
   shared capture/lowering. Existing unstructured status APIs keep working;
   an authored whole value can use an empty label without parsing its text.
4. Add a canonical typed field model/widget and FIELD publication. Migrate
   Sound Lab's four parameter rows, with their existing value slots and exact
   edit prompts. Carry signed ADJUST intent through ordinary events with
   overflow-safe application clamping and choice wrapping.
5. Extract ordinary shell chrome/taskbar state, observe it at the top-level
   host draw boundary, and publish TASK/LAUNCHER entries. Use the same bounded
   slots for CELL drawing, hit testing and retained activation. Preserve the
   existing launcher overlay's ITEM_VIEW.
6. Publish real pane/content-region bindings. Extend the current aggregate
   publisher to assign actual controls and residual content to per-pane
   regions, with explicit clips, chrome below content, truthful slot identity
   and existing divider geometry. Preserve modal/foreground fallback and
   full-frame/minimized presentation. No title row is added.
7. Extend the canonical data-graphics model, facade and producer with bounded
   series/WAVEFORM, then bind Sound Lab's rendered PCM through that model.
   CELL drawing and retained samples share the same owned source; transport
   chunks and sample reservations obey negotiated bounds.
8. Select the completed capabilities in the paired Desk profile, run a fresh
   native-simulator journey, inspect the actual rendered offer, and record
   object coverage, input evidence, timings and remaining qualifications.

Each coherent slice gets an informative local commit and focused execution
before the next integration step. The complete Desktop journey is reserved
for a coherent vertical change, not repeated after every helper edit.

## Integration risks to cover

- The current aggregate puts controls and residual glyphs in one full-screen
  region. Pane publication requires real region ownership and corresponding
  changes to preflight, frozen plans, delta identity, emission and clips.
- Desk has no UIDL root. Shell widgets must not be attributed to the last
  child UCTX; use shared host observation at the completed draw boundary.
- Current taskbar state markers change entry widths. A changed slot layout
  rebuilds the subtree under stable lifecycle rules; state replacement alone
  cannot change bounds. Prompt/launcher overlays must suppress covered hits.
- FIELD target coordinates must land within the published value slot and use
  its exact FDC1 revision. Arbitrary signed counts must not become a loop of
  individual wheel events. CHOICE/TEXT and INTEGER use their specified
  alignment inside unchanged slots.
- Optional-family refusal must leave ordinary content available and avoid
  claiming cells for objects that will not be emitted.
- Captured labels, models and PCM must outlive asynchronous publication through
  owned copies. Reuse applies only when the existing identity/content proofs
  establish unchanged data; no draw-time host inference is permitted.

## Verification

Use the paired MegaPad Make supervisor for Python tests, with an absolute
Akashic test path, `MEGAPAD_ROOT` pointing to the paired checkout, and a
separate runtime namespace. Native libraries are already built there.
Meaningful checks execute ordinary widget/model code and the actual Forth
producer; host decoders and the compositor provide independent wire/geometry
oracles. Keep the architecture and application-boundary ratchets in scope.

For each family cover canonical publication, capability absence, malformed
or over-capacity refusal, unchanged CELL output or explicitly documented
typed styling, geometry and clipping, owner/generation invalidation, and
applicable acknowledged input. New model bounds need exact quota/accounting
tests. Test Python/native simulator parity and retain emulator source checks
where they cover target-Forth behavior.

Final Desk acceptance must identify the actual producer objects and exercise
their returned intents. A headless run documents its in-process/SDL limits;
it does not claim physical display, audio, UART or socket qualification.
Local changes remain isolated from both repository mains and the other
active MegaPad worktree. Remote publication is a separate action.
