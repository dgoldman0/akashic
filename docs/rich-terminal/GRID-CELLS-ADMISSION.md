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
