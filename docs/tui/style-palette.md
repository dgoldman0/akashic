# akashic/tui/style-palette.f — How Each Text Meaning Looks in CELL

**Prefix:** `SPAL-`  
**Provider:** `akashic-tui-style-palette`  
**Dependencies:** `cell.f`, `text-style.f`

A palette gives each meaning of [text-style](../text/text-style.md) the
foreground colour, an xterm-256 index, and the cell attributes CELL draws it
with. The background stays the one the text is drawn on, and plain text keeps
the drawing style it already has. A meaning never changes a character's cells,
so a palette changes colour and attributes only.

A palette is `SPAL-SIZE` bytes of caller storage, one cell per meaning, or the
shared `SPAL-DEFAULT`, whose colours suit a dark background:

| Meaning | Colour | Attributes |
|---------|-------:|------------|
| keyword | 81 | bold |
| comment | 245 | italic |
| string | 186 | |
| number | 141 | |
| heading | 215 | bold |
| emphasis | 223 | italic |
| strong | 231 | bold |
| code | 114 | |
| link | 75 | underline |
| error | 203 | underline |

An application copies the default with `SPAL-INIT` and changes entries with
`SPAL-SET`. Pad does this from its TOML theme: `keyword-fg`, `comment-fg`,
`string-fg`, `number-fg`, `heading-fg`, `emphasis-fg`, `strong-fg`,
`code-fg`, `link-fg`, and `error-fg` under `[pad.theme]` each set one colour
and keep its attributes.

| Word | Stack | Description |
|------|-------|-------------|
| `SPAL-SIZE` | `( -- bytes )` | Bytes in one palette |
| `SPAL-DEFAULT` | `( -- palette )` | The shared default palette |
| `SPAL-INIT` | `( palette -- )` | Copy the default into a palette |
| `SPAL-SET` | `( fg attrs meaning palette -- )` | Set one meaning's look |
| `SPAL-FG@` | `( meaning palette -- fg )` | One meaning's colour |
| `SPAL-ATTRS@` | `( meaning palette -- attrs )` | One meaning's attributes |

A rich renderer does not use this palette: it draws the same meanings, which
the text area publishes as style runs, through its own theme.
