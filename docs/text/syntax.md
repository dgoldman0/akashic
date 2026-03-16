# akashic-syntax — Syntax Highlighting for Text Editors

Line-by-line scanner that fills a byte-indexed token-type map.  The
editor's renderer reads the map to apply colours via a configurable
palette.  Built-in scanners for Forth, Markdown, and plain text.

```forth
REQUIRE text/syntax.f
```

`PROVIDED akashic-syntax` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Token Types](#token-types)
- [Palette](#palette)
- [Scanning](#scanning)
- [Language Selectors](#language-selectors)
- [Forth Scanner Details](#forth-scanner-details)
- [Markdown Scanner Details](#markdown-scanner-details)
- [Plain Scanner](#plain-scanner)
- [Quick Reference](#quick-reference)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Line-by-line** | Each call scans one line — no multi-line state. |
| **Byte-indexed map** | One token-type byte per source byte; editor reads map[i] for colour. |
| **Pluggable** | Language selector is an xt — pass any scanner word. |
| **Configurable palette** | Packed fg\|bg\|attrs per token type; override at runtime. |
| **Prefix convention** | Public: `SYN-`. Internal: `_SYN-`, `_SF-` (Forth), `_SM-` (Markdown). |

---

## Token Types

| Constant | Value | Used by |
|----------|-------|---------|
| `SYN-T-DEFAULT` | 0 | Unmarked text |
| `SYN-T-KEYWORD` | 1 | Forth: `:`, `;`, `IF`, `THEN`, `BEGIN`, etc. |
| `SYN-T-COMMENT` | 2 | Forth: `\ ...`, `( ... )`; Markdown: — |
| `SYN-T-STRING` | 3 | Forth: `." ..."`, `S" ..."` |
| `SYN-T-NUMBER` | 4 | Forth: decimal, `$hex`, `0xHex` |
| `SYN-T-HEADING` | 5 | Markdown: `# ...` lines |
| `SYN-T-BOLD` | 6 | Markdown: `**...**` |
| `SYN-T-LINK` | 7 | Markdown: `[text](url)` |
| `SYN-T-CODE` | 8 | Markdown: `` `...` `` inline code |

---

## Palette

Each token type has a packed colour triple: `fg | (bg << 8) | (attrs << 16)`.

### SYN-PAL-SET

```
( type fg bg attrs -- )
```

Set the palette entry for a token type.

### SYN-PAL-FG / SYN-PAL-BG / SYN-PAL-ATTRS

```
( type -- value )
```

Read individual components from the palette.

### Default Palette (ANSI 16-colour)

| Type | FG | BG | Attrs | Appearance |
|------|----|----|-------|-----------|
| DEFAULT | 7 (white) | 0 (black) | 0 | Normal |
| KEYWORD | 14 (bright cyan) | 0 | 1 (bold) | **Bright cyan** |
| COMMENT | 8 (dark grey) | 0 | 0 | Dark grey |
| STRING | 3 (yellow) | 0 | 0 | Yellow |
| NUMBER | 6 (cyan) | 0 | 0 | Cyan |
| HEADING | 13 (bright magenta) | 0 | 1 | **Bright magenta** |
| BOLD | 15 (bright white) | 0 | 1 | **Bright white** |
| LINK | 12 (bright blue) | 0 | 0 | Bright blue |
| CODE | 2 (green) | 0 | 0 | Green |

---

## Scanning

### SYN-SCAN

```
( addr u map lang-xt -- )
```

Scan a single line (`addr u`) and fill the byte map.  `lang-xt` is
the scanner word's execution token — just calls `EXECUTE`.

```forth
\ Scan a Forth line
line-addr line-len  map-buf  SYN-LANG-FORTH  SYN-SCAN

\ Read token type at byte position 5
map-buf 5 + C@   \ → SYN-T-KEYWORD, etc.
```

The map buffer must be at least `u` bytes.  Each byte `map[i]` holds
the `SYN-T-*` token type for source byte `i`.

---

## Language Selectors

Constants holding the xt of each built-in scanner:

| Constant | Scanner Word | Description |
|----------|-------------|-------------|
| `SYN-LANG-FORTH` | `SYN-SCAN-FORTH` | Forth syntax |
| `SYN-LANG-MD` | `SYN-SCAN-MD` | Markdown syntax |
| `SYN-LANG-PLAIN` | `SYN-SCAN-PLAIN` | No highlighting |

To add a new language, define a word with signature
`( addr u map -- )` and pass its xt to `SYN-SCAN`.

---

## Forth Scanner Details

`SYN-SCAN-FORTH ( addr u map -- )`

1. **Fill** entire map with `SYN-T-DEFAULT`.
2. **Walk** tokens left-to-right:
   - `\` followed by space or at EOL → `SYN-T-COMMENT` to end of line.
   - `(` followed by space → `SYN-T-COMMENT` until `)`.
   - Word ending in `"` → `SYN-T-STRING` for the word + quoted body.
   - Keyword match (case-insensitive) → `SYN-T-KEYWORD`.
   - Number (all digits, or `$`/`0x` hex prefix) → `SYN-T-NUMBER`.

### Keyword List

`:`, `;`, `IF`, `ELSE`, `THEN`, `BEGIN`, `WHILE`, `REPEAT`, `UNTIL`,
`AGAIN`, `DO`, `?DO`, `LOOP`, `+LOOP`, `LEAVE`, `UNLOOP`, `CASE`,
`OF`, `ENDOF`, `ENDCASE`, `CREATE`, `DOES>`, `CONSTANT`, `VARIABLE`,
`VALUE`, `TO`, `EXIT`, `ABORT`, `REQUIRE`, `PROVIDED`, `ALLOT`.

---

## Markdown Scanner Details

`SYN-SCAN-MD ( addr u map -- )`

1. **Fill** entire map with `SYN-T-DEFAULT`.
2. **Heading**: if line starts with `#` → entire line is `SYN-T-HEADING`.
3. **Inline patterns** (left-to-right):
   - `` ` `` ... `` ` `` → `SYN-T-CODE`
   - `**` ... `**` → `SYN-T-BOLD`
   - `[text](url)` → `SYN-T-LINK`

---

## Plain Scanner

`SYN-SCAN-PLAIN ( addr u map -- )`

Fills the entire map with `SYN-T-DEFAULT`.  Used as a fallback for
unknown file types.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `SYN-T-DEFAULT` | `( -- 0 )` | Token: default |
| `SYN-T-KEYWORD` | `( -- 1 )` | Token: keyword |
| `SYN-T-COMMENT` | `( -- 2 )` | Token: comment |
| `SYN-T-STRING` | `( -- 3 )` | Token: string |
| `SYN-T-NUMBER` | `( -- 4 )` | Token: number |
| `SYN-T-HEADING` | `( -- 5 )` | Token: heading |
| `SYN-T-BOLD` | `( -- 6 )` | Token: bold |
| `SYN-T-LINK` | `( -- 7 )` | Token: link |
| `SYN-T-CODE` | `( -- 8 )` | Token: inline code |
| `SYN-SCAN` | `( addr u map xt -- )` | Scan one line |
| `SYN-LANG-FORTH` | `( -- xt )` | Forth scanner xt |
| `SYN-LANG-MD` | `( -- xt )` | Markdown scanner xt |
| `SYN-LANG-PLAIN` | `( -- xt )` | Plain scanner xt |
| `SYN-PAL-SET` | `( type fg bg attrs -- )` | Set palette entry |
| `SYN-PAL-FG` | `( type -- fg )` | Read foreground |
| `SYN-PAL-BG` | `( type -- bg )` | Read background |
| `SYN-PAL-ATTRS` | `( type -- attrs )` | Read attributes |

---

## Dependencies

- `utils/string.f` — `STR-STRI=` (keyword matching), `_STR-LC` (hex prefix check)

## Consumers

- Akashic Pad — maps `FT-LANG-*` → `SYN-LANG-*` and calls `SYN-SCAN` per visible line

## Internal State

Module-level `VARIABLE`s:

- `_SF-A`, `_SF-U`, `_SF-MAP`, `_SF-POS` — Forth scanner state
- `_SM-A`, `_SM-U`, `_SM-MAP`, `_SM-POS` — Markdown scanner state
- `_KW-WA`, `_KW-WU` — keyword matching temporaries

Not reentrant without the `GUARDED` guard section.
