# Typed grid-cell admission

`RTE-F-GRID-CELLS` and `RTAPT-F-GRID-CELLS` are neutral/provider feature
`0x2000`. The APT bridge explicitly maps retained wire bit `0x8000` into that
feature. Both negotiated-limit validators require CONTROL_COLLECTIONS, whose
existing dependency requires CONTROLS. Intermediate feature bits remain
reserved. No capability, CONTROL, admission, operation or owned-copy record
changes size.

NUMBER, FORMULA and ERROR remain STX1 version 1 roles 4, 5 and 6. Their
existing text and item reservations remain unchanged. The ordinary model and
terminal retain canonical content-validation authority.

The hybrid producer omits a typed grid when the negotiated feature is absent
before making its residual-cell claim. Its ordinary CELL drawing therefore
remains available alongside supported rich menus and collections.

The provider independently checks each concrete CONTROL at three boundaries:

- Direct DEFINE/REPLACE admission, before copying or updating owner ledgers.
- Publication audit of the owned copy, before applying its quota aggregates.
- Replay, before passing arguments to the PT writer.

These checks use `STX1R-ROLES?`, a read-only, stack-only walker. It validates
the STX1 envelope, bounds each variable item header and text/style tail,
requires exact exhaustion of the supplied span, and recognizes roles 1–6.
It does not repeat geometry, key, state, selection, or UTF-8 validation.
Typed roles in TEXT_AREA are invalid; valid typed TEXT_GRID without the
feature is unsupported. Neither case silently becomes CONTENT.

Copied-content admission first proves that its declared label, shortcut and
content lengths fit the owned copy extent. The walker uses no mutable scratch,
so borrowed bytes cannot alias a hidden role-scan workspace.

CONTROL and HYBRID preflight remain aggregate-only. Their unchanged summaries
do not distinguish plain and typed STX1, and give the provider no authority
to visit the caller's items. Feature refusal belongs to producer selection
and the concrete publication boundaries above.

## Desktop qualification

GRID_CELLS passed the complete Desk journey on 2026-09-30 and is selected in
the rich Desktop profile (`desktop-apt1`). The run used
`local_testing/run_headless_grid_acceptance.py`. It starts Desk through the
real `megapad.main --mode simulator --executor native` entry point, replaces
only the Unix listener with in-process dispatch, and composes into an SDL
dummy sink. It does not cover sockets, a physical display, audio or UART.

After the 52-stage journey, the runner finds Grid's one TEXT_GRID by its
typed roles, picks a NUMBER cell other than the selected one, and sends PLACE
through the acknowledged hit map with that root's exact content revision. The
run passed when an acknowledged frame showed that cell as the primary
selection, set through Grid's ordinary selection path; inspection of the
image showed the highlight inside the cell. The combined
[shell run](DESK-SHELL-COMPOSITION.md#desktop-qualification) repeated this
probe.

The run found two Grid defects, both fixed. Grid's panel guard read packed
pointer coordinates in the wrong order before its bounds check, so it dropped
a typed event in the lower-left pane. Grid's status update left a cell
pointer on the stack. `local_testing/test_grid_text_grid.py` covers both
through the real panel and TGRID handlers and checks that the data and return
stacks end empty.

The acceptance helper sends PLACE to TEXT_AREA and TEXT_GRID roots, and
EXTEND and FOLLOW to TEXT_AREA roots only. The Grid probe has its own
20-second response deadline as well as the full-run deadline.

From the Akashic checkout, with the paired MegaPad native extensions built:

```sh
python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/grid-qualification
```

The Grid probe always runs; the other family probes need their flags.
