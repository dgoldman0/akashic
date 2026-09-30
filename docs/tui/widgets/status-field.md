# Structured status widget

`akashic/tui/widgets/status-field.f` provides
`akashic-tui-status-field`. It is an ordinary noninteractive widget
(`WDG-T-STATUS-FIELD=26`) over one immutable [status model](../status-field-model.md).
The legacy `status.f` / `SBAR-*` interface is unchanged.

```forth
SFIELD-NEW       ( region -- widget )
SFIELD-BIND      ( model bytes widget -- status )
SFIELD-UNBIND    ( widget -- )
SFIELD-INSTANCE@ ( widget -- token|0 )
SFIELD-FREE      ( widget -- )
SFIELD-STATUS-FIELD-MEASURE ( widget -- bytes status )
SFIELD-STATUS-FIELD-CAPTURE ( destination capacity widget -- bytes status )
SFIELD-STORAGE-DISJOINT? ( address bytes -- flag )
SFIELD-STATUS-FIELD-STORAGE-DISJOINT? ( address bytes widget -- flag )
SFIELD-DRAW-SLOT ( address bytes row column width -- )
```

Statuses alias the `USF-S-*` statuses. The 64-byte widget descriptor contains
the standard 40-byte header, borrowed model address at 40, exact model byte
count at 48, and a nonzero allocation-lifetime token at 56. `NEW` owns only
that descriptor. `FREE` leaves the caller's region and model intact.

`BIND` deeply validates the model, requires region height one and exactly
the model width, and refuses overlap with the widget descriptor, region,
or module storage. A failed bind preserves the previous binding. Changing
the region width requires a matching model and rebind; mismatched shape
cannot paint or capture. `UNBIND` keeps the allocation token and prevents
painting and capture. A later allocation receives a new token.

Normal `WDG-DRAW` fills the exact field rectangle, then draws the label at
column zero and the value at the declared split. The slots are independently
clipped one-row `DRW-TEXT` paragraphs, with no inset, wrapping, or width
transfer. A wide grapheme cannot paint across a slot boundary. Widget and
model visibility both apply; hidden fields paint nothing. The widget
inherits background and ordinary text style; info, success, warning and
error use foreground colors 6, 2, 3 and 1. Emphasis adds bold. Foreground and
attributes are restored after drawing. The handler consumes no input and
the widget creates no focus or activation behavior.

`SFIELD-DRAW-SLOT` shares that slot primitive with resolved ordinary UI
paint. It uses the current region and style, adds no offset beyond its row
and column arguments, and restores the caller's clip. A zero-width slot
paints nothing.

Capture copies the validated model to caller-owned aligned storage and
combines widget visibility with the model's visible flag. It preserves the
native stable key, all strings, severity, split, and emphasis. A mounted
relationship's identity is separate from this native key. `MEASURE` or
`CAPTURE` with `(0 0 widget)` returns the exact required bytes. Capture
refuses insufficient capacity, wrapping or misaligned destinations, and
overlap with the model, descriptor, region, or either module's storage
before writing. The storage predicates expose the same ownership rules to
an enclosing capture pipeline.

Focused executable coverage is in `local_testing/test_status_field.py`:
native validation and atomic refusal, display substitution, CELL clipping
and style, visibility, shape mismatch, lifetime tokens, and capture aliases.
