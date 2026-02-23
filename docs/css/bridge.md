# akashic-css-bridge — HTML↔CSS Bridge for KDOS / Megapad-64

Connects `akashic-html` and `akashic-css` for element-level style
computation.  Extracts tag name, id, and class from HTML element
cursors, feeds them into CSS selector matching, and collects matching
declarations into a user-provided buffer.

```forth
REQUIRE bridge.f
```

`PROVIDED akashic-css-bridge` — safe to include multiple times.
Automatically loads `akashic-html` (which loads `akashic-markup-core`)
and `akashic-css`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Element Setup](#element-setup)
- [Selector Matching](#selector-matching)
- [Style Collection](#style-collection)
- [Inline Style Merging](#inline-style-merging)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | All string results point into original HTML/CSS buffers. |
| **No hidden allocations** | Output buffer is user-provided. Internal state uses only `VARIABLE`s. |
| **Automatic extraction** | `CSSB-MATCH-ELEMENT` and `CSSB-GET-STYLES` extract tag/id/class from the HTML cursor automatically — no manual `CSS-MATCH-SET` needed. |
| **Document-order cascade** | `CSSB-GET-STYLES` iterates rules in source order.  Multiple matching rules are concatenated with `; ` separators. |
| **Inline priority** | `CSSB-APPLY-INLINE` appends inline `style=""` after stylesheet rules, giving it highest effective priority (last-wins). |
| **Trimmed output** | Rule bodies are whitespace-trimmed before appending. |

---

## Dependencies

```
bridge.f
├── ../markup/html.f    (akashic-html)
│   └── ../markup/core.f  (akashic-markup-core)
└── css.f               (akashic-css)
```

All dependencies are loaded automatically via `REQUIRE` with relative
paths.

---

## Element Setup

The bridge internally extracts three properties from an HTML element
cursor positioned at an opening tag (`<div id="x" class="y">`):

1. **Tag name** — via `MU-GET-TAG-NAME`
2. **id attribute** — via `HTML-ATTR?` for `"id"`
3. **class attribute** — via `HTML-ATTR?` for `"class"`

These are stored in internal variables and passed to `CSS-MATCH-SET`
from `akashic-css`.  This happens automatically inside
`CSSB-MATCH-ELEMENT`, `CSSB-GET-STYLES`, and `CSSB-APPLY-INLINE`.

You never need to call `_CSSB-SETUP` or `CSS-MATCH-SET` directly when
using the bridge.

---

## Selector Matching

| Word | Stack | Description |
|---|---|---|
| `CSSB-MATCH-ELEMENT` | `( sel-a sel-u html-a html-u -- flag )` | Does any comma-separated selector group match this HTML element?  Extracts tag/id/class, then tests all groups.  Flag = -1 match, 0 no match. |
| `CSSB-MATCH-SELECTOR` | `( sel-a sel-u -- flag )` | Match one selector (no commas) against the element previously set by `_CSSB-SETUP` / `CSS-MATCH-SET`.  Only checks the **last compound selector** — combinators are skipped (no ancestor traversal). |

### Combinator Handling

The bridge does **not** traverse the DOM tree.  When a selector like
`body > div .intro` is tested, only the last compound selector
(`.intro`) is checked against the element.  The ancestor parts
(`body > div`) are skipped.

This is correct for single-element matching (filtering which rules
*could* apply), but a full DOM implementation would need ancestor
traversal for complete accuracy.

### Example

```forth
\ Does "div.active, span" match <div class="active">?
S" div.active, span"
S" <div class=\"active\">"
CSSB-MATCH-ELEMENT .    \ -1

\ Type mismatch:
S" span"
S" <div>"
CSSB-MATCH-ELEMENT .    \ 0

\ Universal selector matches anything:
S" *"
S" <p>"
CSSB-MATCH-ELEMENT .    \ -1
```

---

## Style Collection

| Word | Stack | Description |
|---|---|---|
| `CSSB-GET-STYLES` | `( css-a css-u html-a html-u buf max -- n )` | Collect all matching CSS declarations for an HTML element.  Iterates rules in document order.  For each matching rule, appends its declaration body to `buf`, separated by `; `.  Returns number of bytes written. |

The CSS input should be a complete stylesheet (or section).  Rules are
parsed with `CSS-RULE-NEXT` and selectors are tested with the bridge's
group matcher.  `@`-rules are skipped automatically.

### Example

```forth
CREATE out 1024 ALLOT

S" div { color: red } .active { font-weight: bold }"
S" <div class=\"active\">"
out 1024 CSSB-GET-STYLES    \ ( n )

\ Print result:
out SWAP TYPE CR
\ Output: color: red; font-weight: bold
```

---

## Inline Style Merging

| Word | Stack | Description |
|---|---|---|
| `CSSB-APPLY-INLINE` | `( css-a css-u html-a html-u buf max -- n )` | Like `CSSB-GET-STYLES` but also appends the element's inline `style=""` attribute (if present) after all stylesheet matches.  Returns bytes written. |

Inline styles are appended **last**, giving them the highest effective
priority in a simple last-wins cascade.

### Example

```forth
CREATE out 1024 ALLOT

S" div { color: red }"
S" <div style=\"font-size: 16px\">"
out 1024 CSSB-APPLY-INLINE

out SWAP TYPE CR
\ Output: color: red; font-size: 16px
```

When the element has no `style=""` attribute, `CSSB-APPLY-INLINE`
behaves identically to `CSSB-GET-STYLES`.

When the stylesheet has no matching rules but the element has an inline
style, only the inline style is returned (without a leading `; `).

---

## Quick Reference

### Public API

```
CSSB-MATCH-ELEMENT     ( sa su ha hu -- flag )      full match
CSSB-MATCH-SELECTOR    ( sa su -- flag )             single-group match
CSSB-GET-STYLES        ( ca cu ha hu buf max -- n )  collect styles
CSSB-APPLY-INLINE      ( ca cu ha hu buf max -- n )  styles + inline
```

### Stack Notation

```
sa su    selector string (CSS selector text)
ha hu    HTML element string (positioned at opening tag)
ca cu    CSS stylesheet string
buf      output buffer address
max      output buffer capacity
n        bytes written to buffer
flag     -1 match / 0 no match
```

---

## Internal Words

These are prefixed with `_CSSB-`, `_CBME-`, `_CBMC-`, `_CGS-`, or
`_CAI-` and are not part of the public API.

| Word / Variable | Purpose |
|---|---|
| `_CSSB-SETUP` | `( html-a html-u -- )` Extract tag/id/class and call `CSS-MATCH-SET`. |
| `_CSSB-MATCH-COMPOUND` | `( sel-a sel-u -- sel-a' sel-u' flag )` Match all simple selectors in one compound selector. |
| `_CSSB-MATCH-GROUPS` | `( sel-a sel-u -- flag )` Check all comma-separated groups. |
| `_CSSB-APPEND-SEP` | Append `; ` separator to output buffer if non-empty. |
| `_CSSB-APPEND` | `( src-a src-u -- )` Append string to output buffer with bounds check. |
| `_CSSB-COLLECT` | `( css-a css-u -- )` Iterate rules, match selectors, append bodies. |
| `_CSSB-TA/TL` | Extracted tag name. |
| `_CSSB-IA/IL` | Extracted id value. |
| `_CSSB-CA/CL` | Extracted class value. |
| `_CSSB-ID-LIT` | `"id"` as packed bytes for `HTML-ATTR?`. |
| `_CSSB-CLS-LIT` | `"class"` as byte array for `HTML-ATTR?`. |
| `_CSSB-STY-LIT` | `"style"` as byte array for `HTML-ATTR?`. |
| `_CBME-SA/SL` | Saved selector for `CSSB-MATCH-ELEMENT`. |
| `_CBMC-F` | Compound match result flag. |
| `_CGS-BA/BL/MX` | Output buffer state. |
| `_CGS-CSA/CSL` | Saved CSS source for style collection. |
| `_CGS-SA/SL` | Per-rule selector save. |
| `_CGS-BOA/BOL` | Per-rule body save. |
| `_CAI-HA/HL` | Saved HTML cursor for inline style lookup. |

---

## Cookbook

### Check if an element matches a selector

```forth
S" .card.featured"
S" <div class=\"card featured large\">"
CSSB-MATCH-ELEMENT
IF ." matches!" ELSE ." no match" THEN
```

### Collect styles for rendering

```forth
CREATE style-buf 2048 ALLOT

my-stylesheet
my-element
style-buf 2048 CSSB-GET-STYLES

\ Now parse individual properties from the collected style:
style-buf SWAP
S" color" CSS-DECL-FIND
IF ." color=" TYPE CR ELSE 2DROP THEN
```

### Full pipeline: stylesheet + inline → property lookup

```forth
CREATE buf 2048 ALLOT

my-stylesheet
S" <div style=\"border: 1px solid\" class=\"box\">"
buf 2048 CSSB-APPLY-INLINE

buf SWAP
S" border" CSS-DECL-FIND
IF ." border=" TYPE CR ELSE 2DROP ." no border" CR THEN
```

### Build styles for multiple elements

```forth
CREATE buf 1024 ALLOT

: show-styles  ( css-a css-u html-a html-u -- )
    buf 1024 CSSB-GET-STYLES
    DUP 0= IF DROP ." (none)" CR EXIT THEN
    buf SWAP TYPE CR ;

my-css S" <h1>" show-styles
my-css S" <p class=\"intro\">" show-styles
my-css S" <div id=\"main\">" show-styles
```
