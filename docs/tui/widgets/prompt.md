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
| `PRM-SET-BOUNDS` | `( row col h w prompt -- )` | Follow a relaid-out status element |
| `PRM-FREE` | `( prompt -- )` | Free prompt-owned allocations |

An active prompt consumes all key events routed to it. Enter deactivates it
and invokes the submit callback; Escape deactivates it and invokes the cancel
callback. Other events are delegated to the embedded input widget.
