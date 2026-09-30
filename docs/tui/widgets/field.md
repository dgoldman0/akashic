# Typed field widget

`akashic/tui/widgets/field.f` provides `akashic-tui-field` and the ordinary
`WDG-T-FIELD=27` widget. It borrows an immutable [UFLD model](../field-model.md)
and leaves all edits, selection changes, and replacement values to its UI
owner. It contains no terminal transport.

```forth
FLD-NEW          ( region -- widget )
FLD-BIND         ( model bytes widget -- status )
FLD-UNBIND       ( widget -- )
FLD-MODEL@       ( widget -- model bytes )
FLD-INSTANCE@    ( widget -- token|0 )
FLD-FREE         ( widget -- )
FLD-ON-ACTIVATE  ( xt widget -- )        \ callback: ( widget -- )
FLD-ON-ADJUST    ( xt widget -- )        \ callback: ( signed-count widget -- )
FLD-ACTIVATE     ( widget -- consumed? )
FLD-ADJUST       ( signed-count widget -- consumed? )
FLD-STYLE!       ( fg bg attributes widget -- )
FLD-SELECTED-STYLE! ( fg bg attributes widget -- )
FLD-VALUE-CONTAINS? ( screen-row screen-column widget -- flag )
FLD-FIELD-MEASURE ( widget -- bytes status )
FLD-FIELD-CAPTURE ( destination capacity widget -- bytes status )
FLD-STORAGE-DISJOINT? ( address bytes -- flag )
FLD-FIELD-STORAGE-DISJOINT? ( address bytes widget -- flag )
```

`FLD-S-*` statuses alias the model statuses. The descriptor is 96 bytes:
standard header 0..39, model address 40, exact model bytes 48, nonzero
allocation-lifetime token 56, activate callback 64, adjust callback 72,
normal style 80, and selected style 88. A style packs foreground, background,
and attributes into successive eight-bit fields. Styles belong to ordinary
widget presentation and are absent from the semantic model.

Binding checks the complete model and requires its root width and height to
equal the widget's region. Model storage must be disjoint from the descriptor,
region and module storage. Refusal preserves the previous binding. The caller
must keep a bound model immutable; changes are built in a separate buffer and
then rebound. Unbinding preserves the instance token. Freeing releases only
the descriptor, leaving the caller's model and region intact.

CELL drawing fills the exact root rectangle. It clips the outer label and
value independently to their declared slots, adding no inset or geometry.
The label, CHOICE label and TEXT value are left aligned; INTEGER uses ordinary
signed decimal text and right alignment. Formatting includes the signed
64-bit minimum. Single-line text is vertically centered within each slot.
A partial wide grapheme becomes space within its own slot. Model and widget
visibility both apply. Effective selection chooses the selected style;
disabled fields use the normal style with dim, matching captured state.
The caller's drawing style is restored afterward.

Ordinary keyboard Enter/F2 requests activation and Left/Right requests one
negative/positive adjustment step. A mouse press activates only within the
value rectangle. Wheel up/down requests positive/negative steps there. The
normal mouse event `KEY-MOUSE-FIELD-ADJUST=512` carries one full signed count
through `KEY-MOUSE-FIELD-ADJUSTMENT` and a required nonzero content revision
through `KEY-MOUSE-FIELD-REVISION`; the sender owns both sidebands for the
duration of one dispatch. The expected revision must equal the currently
bound model revision. The owner must refresh a dirty binding before dispatch,
so an edit makes queued intents for the prior revision stale. Ordinary keyboard
and wheel events need no revision sideband. A full count is never expanded
into repeated wheel events.
Zero adjustments, hidden/disabled/read-only fields, missing callbacks, and
adjustments to TEXT consume no input. A callback receives an intent and does
not imply any mutation by the widget.

Capture copies the same model used by CELL, preserving its native key,
content revision, explicit geometry, constraints and strings. Widget
visibility/enablement compose with model state; selection is cleared if
either is absent. Read-only state remains descriptive. `(0 0 widget)` measures
without copying. Capture rejects capacity, alignment, wrapping and ownership
aliases before any destination write. The captured model is pointer-free and
does not contain callbacks, styles or the widget allocation token.

Executable coverage is in `local_testing/test_field_widget.py`; model and
arbitrary signed adjustment arithmetic are tested in
`local_testing/test_field_model.py`.
