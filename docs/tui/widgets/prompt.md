# akashic/tui/widgets/prompt.f - Non-blocking Command Bar

`prompt.f` provides a reusable one-line command bar for TUI applets. It is
designed to overlay a status row without starting a nested event loop, so it
works both in `ASHELL-RUN` and inside Desk child contexts.

The caller owns the text buffer and outer region. The prompt owns and frees
its internal `INP-` widget and child region. Submit and cancel callbacks have
the signature `( prompt -- )`.

| Word | Stack | Description |
|---|---|---|
| `PRM-NEW` | `( rgn buf cap -- prompt )` | Create a hidden prompt |
| `PRM-SHOW` | `( label-a label-u initial-a initial-u prompt -- )` | Set content and activate |
| `PRM-HIDE` | `( prompt -- )` | Deactivate the prompt |
| `PRM-ACTIVE?` | `( prompt -- flag )` | Query active state |
| `PRM-GET-TEXT` | `( prompt -- addr len )` | Borrow the caller-owned input text |
| `PRM-ON-SUBMIT` | `( xt prompt -- )` | Set the Enter callback |
| `PRM-ON-CANCEL` | `( xt prompt -- )` | Set the Escape callback |
| `PRM-COLORS!` | `( fg bg prompt -- )` | Set xterm-256 colors |
| `PRM-MASK!` | `( codepoint prompt -- )` | Set input masking; zero disables it |
| `PRM-WIPE` | `( prompt -- )` | Zero the full caller-owned input buffer |
| `PRM-SET-BOUNDS` | `( row col h w prompt -- )` | Follow a relaid-out status element |
| `PRM-FREE` | `( prompt -- )` | Free prompt-owned allocations |
| `PRM-INSTANCE@` | `( prompt -- instance\|0 )` | The prompt's lifetime identity |
| `PRM-GENUINE?` | `( widget -- flag )` | A live prompt this module made, by its type, draw and handle words, identity, region and input. Pure and unguarded, for UIDL's checks of an overlay |
| `PRM-FIELD-ROOT` | `( prompt -- row col height width )` | The cells its field takes |
| `PRM-FIELD-CAPTURE` | `( dst cap prompt -- bytes status )` | Its TEXT field's UFLD model |

While it is shown, the prompt is also one TEXT field
([field model](../field-model.md)): its label, its input's value (mask
characters when it masks), caret, selection, scroll and placeholder.
`PRM-FIELD-CAPTURE` writes that model at an aligned destination apart from
everything the prompt reads, or with `0 0` only measures it. It lays the
prompt out as its draw does, settling the input's scroll, so a capture taken
before the draw is what the draw shows. A rich renderer shows the field and
names positions in it; the CELL paint stays the complete fallback.

An active prompt consumes all key events routed to it. Enter deactivates it
and invokes the submit callback; Escape deactivates it and invokes the cancel
callback. Other events are delegated to the embedded input widget.

The prompt's revision moves when its input changes, as well as when it
changes itself: it compares the input's revision with the one it last
counted after it passes on an event, after it draws and after its field is
laid out. `PRM-SET-BOUNDS` with the bounds the prompt already has changes
nothing; the applications that call it before each paint draw the prompt
themselves.

For credentials, enable masking before `PRM-SHOW`, synchronously copy the
borrowed text into a credential owner, and call `PRM-WIPE` on submit and cancel.
Masking prevents display disclosure; wiping removes bytes retained by the
caller-owned command buffer.
