# akashic-file-types — File Type Registry

Maps filename extensions to type descriptors carrying metadata useful
for editors, file browsers, and launchers.  Presentation-independent —
no TUI dependencies.  Consumers provide their own icon or colour
mappings keyed by `FT-LANG-*` ids.

```forth
REQUIRE utils/file-types.f
```

`PROVIDED akashic-file-types` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Language IDs](#language-ids)
- [Descriptor Layout](#descriptor-layout)
- [Lookup](#lookup)
- [Accessors](#accessors)
- [Convenience](#convenience)
- [Iteration](#iteration)
- [Handler Registration](#handler-registration)
- [Built-in Types](#built-in-types)
- [Quick Reference](#quick-reference)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Generic** | No TUI, colour, or icon fields — consumers add those. |
| **Static table** | Types compiled at load time in a `CREATE` array. |
| **Case-insensitive** | Extension matching via `STR-STRI=` from `string.f`. |
| **Handler binding** | Each type has a mutable `handler` cell for app-desc pointers. |
| **Prefix convention** | Public: `FT-`. Internal: `_FT-`. |

---

## Language IDs

Presentation-independent integer constants.  The consumer maps these
to syntax scanner xts, palette entries, or icon glyphs.

| Constant | Value | Description |
|----------|-------|-------------|
| `FT-LANG-PLAIN` | 0 | Plain text (default) |
| `FT-LANG-FORTH` | 1 | Forth source |
| `FT-LANG-MARKDOWN` | 2 | Markdown |
| `FT-LANG-TOML` | 3 | TOML config |
| `FT-LANG-YAML` | 4 | YAML config |
| `FT-LANG-JSON` | 5 | JSON data |
| `FT-LANG-C` | 6 | C source / header |
| `FT-LANG-BINARY` | 7 | Binary / opaque |

---

## Descriptor Layout

Each descriptor is 64 bytes (8 cells):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `ext-a` | Extension string address (e.g. `".f"`) |
| +8 | `ext-u` | Extension string length |
| +16 | `name-a` | Display name address (e.g. `"Forth source"`) |
| +24 | `name-u` | Display name length |
| +32 | `lang-id` | `FT-LANG-*` constant |
| +40 | `tab-w` | Default tab width in spaces |
| +48 | `line-end` | Line ending: 0 = LF, 1 = CRLF |
| +56 | `handler` | App-desc pointer (0 = none; set at run time) |

---

## Lookup

### FT-LOOKUP

```
( fn-a fn-u -- desc | 0 )
```

Find the type descriptor matching a filename's extension.  Extracts
the last `.`-delimited suffix via `STR-RINDEX`, then scans the table
with case-insensitive comparison.  Returns the descriptor address, or
`0` if no match.

```forth
S" readme.md" FT-LOOKUP   \ → desc for Markdown
S" Makefile"  FT-LOOKUP   \ → 0 (no extension)
```

---

## Accessors

All accessors take a descriptor address returned by `FT-LOOKUP`.

| Word | Stack | Description |
|------|-------|-------------|
| `FT-EXT` | `( desc -- addr u )` | Extension string (e.g. `".md"`) |
| `FT-NAME` | `( desc -- addr u )` | Display name |
| `FT-LANG-ID` | `( desc -- id )` | Language id constant |
| `FT-TAB-W` | `( desc -- n )` | Default tab width |
| `FT-LINE-END` | `( desc -- 0\|1 )` | Line ending preference |
| `FT-HANDLER` | `( desc -- app-desc \| 0 )` | Registered handler |

```forth
S" main.f" FT-LOOKUP FT-LANG-ID   \ → 1 (FT-LANG-FORTH)
S" main.f" FT-LOOKUP FT-TAB-W     \ → 4
```

---

## Convenience

### FT-LOOKUP-LANG

```
( fn-a fn-u -- lang-id )
```

Shorthand: returns the language id for a filename, or `FT-LANG-PLAIN`
if the extension is unrecognised.

### FT-LOOKUP-TAB

```
( fn-a fn-u -- tab-w )
```

Shorthand: returns the tab width for a filename, defaulting to 4 if
unrecognised.

---

## Iteration

### FT-COUNT

```
( -- n )
```

Number of registered type entries.

### FT-NTH

```
( n -- desc )
```

Descriptor address for the *n*-th entry (0-based).

```forth
FT-COUNT 0 ?DO
    I FT-NTH FT-NAME TYPE CR
LOOP
```

---

## Handler Registration

### FT-SET-HANDLER

```
( app-desc desc -- )
```

Store an app-desc pointer (or other handler token) in the descriptor.
The desk/shell uses this to determine which app opens a file of that
type.

```forth
\ Register Pad as the handler for .f files
my-pad-desc  S" test.f" FT-LOOKUP  FT-SET-HANDLER
```

---

## Built-in Types

| Extension(s) | Display Name | Lang ID | Tab | LF |
|--------------|-------------|---------|-----|----|
| `.f` `.fs` `.fth` `.4th` | Forth source | FORTH | 4 | LF |
| `.md` `.markdown` | Markdown | MARKDOWN | 4 | LF |
| `.txt` | Plain text | PLAIN | 8 | LF |
| `.log` | Log file | PLAIN | 8 | LF |
| `.toml` | TOML config | TOML | 2 | LF |
| `.yaml` `.yml` | YAML config | YAML | 2 | LF |
| `.json` | JSON data | JSON | 2 | LF |
| `.c` `.h` | C source / header | C | 4 | LF |
| `.cfg` `.ini` | Config / INI | PLAIN | 4 | LF |
| `.csv` | CSV data | PLAIN | 4 | LF |

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `FT-LANG-PLAIN` | `( -- 0 )` | Language id: plain text |
| `FT-LANG-FORTH` | `( -- 1 )` | Language id: Forth |
| `FT-LANG-MARKDOWN` | `( -- 2 )` | Language id: Markdown |
| `FT-LANG-TOML` | `( -- 3 )` | Language id: TOML |
| `FT-LANG-YAML` | `( -- 4 )` | Language id: YAML |
| `FT-LANG-JSON` | `( -- 5 )` | Language id: JSON |
| `FT-LANG-C` | `( -- 6 )` | Language id: C |
| `FT-LANG-BINARY` | `( -- 7 )` | Language id: binary |
| `FT-LOOKUP` | `( fn-a fn-u -- desc \| 0 )` | Find type by filename |
| `FT-LOOKUP-LANG` | `( fn-a fn-u -- lang-id )` | Language id or PLAIN |
| `FT-LOOKUP-TAB` | `( fn-a fn-u -- tab-w )` | Tab width or 4 |
| `FT-EXT` | `( desc -- addr u )` | Extension string |
| `FT-NAME` | `( desc -- addr u )` | Display name |
| `FT-LANG-ID` | `( desc -- id )` | Language id |
| `FT-TAB-W` | `( desc -- n )` | Tab width |
| `FT-LINE-END` | `( desc -- 0\|1 )` | Line ending |
| `FT-HANDLER` | `( desc -- ad \| 0 )` | Handler app-desc |
| `FT-SET-HANDLER` | `( ad desc -- )` | Set handler |
| `FT-COUNT` | `( -- n )` | Entry count |
| `FT-NTH` | `( n -- desc )` | Descriptor by index |

---

## Dependencies

- `utils/string.f` — `STR-RINDEX`, `STR-STRI=`

## Consumers

- `tui/applets/desk/desk.f` — file browser / launcher (planned)
- Akashic Pad — maps `FT-LANG-*` → `SYN-LANG-*` for syntax highlighting

## Internal State

Module-level `VARIABLE`s prefixed `_FTL-`:

- `_FTL-FA`, `_FTL-FU` — filename being looked up
- `_FTL-DA`, `_FTL-DU` — extracted extension

Not reentrant without the `GUARDED` guard section.
