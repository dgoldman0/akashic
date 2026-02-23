# akashic-css — CSS Vocabulary for KDOS / Megapad-64

A complete CSS reader, selector matcher, value parser, and builder
library for KDOS Forth.  Parses stylesheets, matches selectors against
element properties, computes specificity, expands shorthand values, and
constructs valid CSS text — all using zero-copy `(addr len)` cursor
pairs.

```forth
REQUIRE css.f
```

`PROVIDED akashic-css` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Cursor Model](#cursor-model)
- [Error Handling](#error-handling)
- [Layer 0 — Scanning Primitives](#layer-0--scanning-primitives)
- [Layer 1 — Declaration Parsing](#layer-1--declaration-parsing)
- [Layer 2 — Rule Iteration](#layer-2--rule-iteration)
- [Layer 3 — Selector Parsing](#layer-3--selector-parsing)
  - [Selector Type Constants](#selector-type-constants)
  - [Combinator Type Constants](#combinator-type-constants)
- [Layer 4 — Selector Matching](#layer-4--selector-matching)
- [Layer 5 — Specificity & Cascade](#layer-5--specificity--cascade)
- [Layer 6 — Value Parsing](#layer-6--value-parsing)
- [Layer 7 — Shorthand Expansion](#layer-7--shorthand-expansion)
- [Layer 8 — @-Rule Parsing](#layer-8--rule-parsing)
- [Layer 9 — Builder](#layer-9--builder)
- [Layer 10 — Named Colors](#layer-10--named-colors)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Zero-copy** | Reader words return pointers into the original CSS buffer — no intermediate copies. |
| **No hidden allocations** | All buffers (builder output) are user-provided.  The library allocates only internal `VARIABLE`s. |
| **Composable cursors** | Every parsing word takes `(addr len)` and returns `(addr' len')`, so words chain naturally. |
| **Depth-aware** | Block/paren skipping tracks nesting depth.  Rule parsing handles nested `@media` blocks. |
| **Configurable errors** | Abort-on-error or soft-fail with flag checking — changeable at runtime via `CSS-ABORT-ON-ERROR`. |
| **Standalone matching** | Selector matching (`CSS-MATCH-SET` / `CSS-MATCH-SIMPLE`) needs only plain string properties — no dependency on `akashic-html`. |
| **Full tokenisation** | Selector parsing recognises all CSS3 simple selector types: type, universal, class, ID, attribute, pseudo-class, pseudo-element. |

---

## Cursor Model

A **cursor** is a standard Forth string pair `( addr len )` pointing
somewhere into a CSS text buffer.  `addr` is the byte address of the
current position, `len` is the number of remaining bytes.

```
CSS text in memory:
  addr ──► div.active { color: red }
           ↑ cursor starts here

After CSS-RULE-NEXT:
  cursor ──►               (past closing '}')
  sel    ──► div.active    (selector substring)
  body   ──► color: red    (body substring)
```

Navigation words advance the cursor and return substrings pointing into
the original buffer.  Nothing is copied.

---

## Error Handling

| Word | Stack | Description |
|---|---|---|
| `CSS-ERR` | `( -- addr )` | Variable: last error code (0 = no error). |
| `CSS-ABORT-ON-ERROR` | `( -- addr )` | Variable: if non-zero, `CSS-FAIL` calls `ABORT`. Default -1. |
| `CSS-FAIL` | `( err-code -- )` | Set `CSS-ERR` and optionally abort. |
| `CSS-OK?` | `( -- flag )` | Return -1 if no error, 0 otherwise. |
| `CSS-CLEAR-ERR` | `( -- )` | Reset `CSS-ERR` to 0. |

Error codes:

| Constant | Value | Meaning |
|---|---|---|
| `CSS-E-NOT-FOUND` | 1 | Item not found |
| `CSS-E-MALFORMED` | 2 | Malformed input |
| `CSS-E-UNTERMINATED` | 3 | Unterminated string/block |
| `CSS-E-UNEXPECTED` | 4 | Unexpected character |
| `CSS-E-OVERFLOW` | 5 | Numeric overflow |

---

## Layer 0 — Scanning Primitives

Low-level scanning: whitespace, comments, strings, identifiers, blocks.

| Word | Stack | Description |
|---|---|---|
| `CSS-SKIP-WS` | `( a u -- a' u' )` | Skip whitespace **and** comments. |
| `CSS-SKIP-COMMENT` | `( a u -- a' u' )` | Skip one `/* ... */` comment. |
| `CSS-SKIP-STRING` | `( a u -- a' u' )` | Skip a quoted string (`"..."` or `'...'`), handling backslash escapes. |
| `CSS-SKIP-IDENT` | `( a u -- a' u' )` | Skip an identifier (CSS name characters). |
| `CSS-GET-IDENT` | `( a u -- a' u' name-a name-u )` | Extract an identifier: advance cursor and return the name. |
| `CSS-SKIP-BLOCK` | `( a u -- a' u' )` | Skip a balanced `{ ... }` block (depth-aware, handles nested blocks, strings, comments). |
| `CSS-SKIP-PARENS` | `( a u -- a' u' )` | Skip a balanced `( ... )` group. |
| `CSS-SKIP-UNTIL` | `( a u char -- a' u' )` | Skip until a specific byte is found (handles strings). |

Helpers (prefixed `_CSS-`):

| Word | Stack | Description |
|---|---|---|
| `_CSS-WS?` | `( c -- flag )` | Is character whitespace? (space, tab, CR, LF, FF) |
| `_CSS-IDENT-CHAR?` | `( c -- flag )` | Is character valid inside an identifier? |
| `_CSS-IDENT-START?` | `( c -- flag )` | Can character start an identifier? |
| `_CSS-TOLOWER` | `( c -- c' )` | ASCII lowercase. |
| `_CSS-STRI=` | `( s1 l1 s2 l2 -- flag )` | Case-insensitive string compare. |
| `_CSS-STR=` | `( s1 l1 s2 l2 -- flag )` | Exact string compare. |
| `_CSS-TRIM-END` | `( a u -- a u' )` | Trim trailing whitespace. |

---

## Layer 1 — Declaration Parsing

Parse `property: value` pairs inside a rule body.

| Word | Stack | Description |
|---|---|---|
| `CSS-DECL-NEXT` | `( a u -- a' u' prop-a prop-u val-a val-u flag )` | Parse next declaration.  Returns property name and value.  Handles `!important`, semicolons, nested blocks.  Flag = -1 found, 0 end. |
| `CSS-DECL-FIND` | `( a u prop-a prop-u -- val-a val-u flag )` | Find a specific property by name (case-insensitive).  Returns its value. |
| `CSS-DECL-HAS?` | `( a u prop-a prop-u -- flag )` | Does this declaration block contain the named property? |
| `CSS-IMPORTANT?` | `( val-a val-u -- flag )` | Does the value end with `!important`? |
| `CSS-STRIP-IMPORTANT` | `( val-a val-u -- val-a' val-u' )` | Remove trailing `!important` from a value string. |

### Example

```forth
\ Parse declarations from a rule body:
S" color: red; margin: 0 auto; font-size: 16px"
BEGIN
    CSS-DECL-NEXT
WHILE
    ." prop: " 2SWAP TYPE ."  val: " TYPE CR
REPEAT
2DROP 2DROP 2DROP
\ Output:
\   prop: color  val: red
\   prop: margin  val: 0 auto
\   prop: font-size  val: 16px
```

---

## Layer 2 — Rule Iteration

Iterate top-level rules in a stylesheet.

| Word | Stack | Description |
|---|---|---|
| `CSS-RULE-NEXT` | `( a u -- a' u' sel-a sel-u body-a body-u flag )` | Get next rule.  Returns selector string (trimmed) and body (inside `{ }`).  Skips `@`-rules automatically.  Flag = -1 found, 0 end. |
| `CSS-AT-RULE?` | `( a u -- flag )` | Does cursor point at an `@`-rule? |
| `CSS-AT-RULE-NAME` | `( a u -- a' u' name-a name-u )` | Extract the `@`-rule keyword (e.g. `media`, `import`). |
| `CSS-SKIP-AT-RULE` | `( a u -- a' u' )` | Skip past one `@`-rule (handles both block and non-block forms). |

### Example

```forth
\ Iterate all rules in a stylesheet:
my-css
BEGIN
    CSS-RULE-NEXT
WHILE
    ." sel: " 2SWAP TYPE CR
    ."   => " TYPE CR
REPEAT
2DROP 2DROP 2DROP
```

---

## Layer 3 — Selector Parsing

Tokenise CSS selectors into simple selectors, combinators, and
comma-separated groups.

### Selector Type Constants

| Constant | Value | Example |
|---|---|---|
| `CSS-S-TYPE` | 1 | `div`, `span` |
| `CSS-S-UNIVERSAL` | 2 | `*` |
| `CSS-S-CLASS` | 3 | `.active` |
| `CSS-S-ID` | 4 | `#main` |
| `CSS-S-ATTR` | 5 | `[href]`, `[type="text"]` |
| `CSS-S-PSEUDO-C` | 6 | `:hover`, `:nth-child(2)` |
| `CSS-S-PSEUDO-E` | 7 | `::before`, `::after` |

### Combinator Type Constants

| Constant | Value | CSS |
|---|---|---|
| `CSS-C-DESCENDANT` | 0 | whitespace |
| `CSS-C-CHILD` | 1 | `>` |
| `CSS-C-ADJACENT` | 2 | `+` |
| `CSS-C-GENERAL` | 3 | `~` |

### Words

| Word | Stack | Description |
|---|---|---|
| `CSS-SEL-NEXT-SIMPLE` | `( a u -- a' u' type name-a name-u flag )` | Parse one simple selector component.  Returns type constant, name string, flag.  Does NOT skip leading whitespace. |
| `CSS-SEL-COMBINATOR` | `( a u -- a' u' comb-type flag )` | Parse combinator between compound selectors.  Call after `CSS-SEL-NEXT-SIMPLE` returns flag=0.  Flag=0 means end of selector (comma or brace). |
| `CSS-SEL-GROUP-NEXT` | `( a u -- a' u' sel-a sel-u flag )` | Iterate comma-separated selector groups.  Returns one trimmed selector at a time. |

### Example

```forth
\ Tokenise "div.active > span":
S" div.active > span"
BEGIN
    CSS-SEL-NEXT-SIMPLE
    IF
        ." type=" ROT . ."  name=" TYPE CR
    ELSE
        2DROP DROP
        CSS-SEL-COMBINATOR
        IF
            ." combinator type=" . CR
        ELSE
            DROP ." end" CR  EXIT
        THEN
    THEN
AGAIN
```

---

## Layer 4 — Selector Matching

Match a simple selector against element properties.  Element state is
set once with `CSS-MATCH-SET`, then each simple selector is tested
with `CSS-MATCH-SIMPLE`.

| Word | Stack | Description |
|---|---|---|
| `CSS-MATCH-SET` | `( tag-a tag-u id-a id-u cls-a cls-u -- )` | Configure element state for matching.  `tag` = tag name, `id` = element id (0 0 if none), `cls` = space-separated class list (0 0 if none). |
| `CSS-MATCH-SIMPLE` | `( type sel-a sel-u -- flag )` | Match one simple selector (from `CSS-SEL-NEXT-SIMPLE`) against the current element. |
| `CSS-MATCH-TYPE` | `( sel-a sel-u tag-a tag-u -- flag )` | Standalone type match (case-insensitive). |
| `CSS-MATCH-ID` | `( sel-a sel-u id-a id-u -- flag )` | Standalone ID match (exact). |
| `CSS-MATCH-CLASS` | `( class-a class-u classes-a classes-u -- flag )` | Does the space-separated class list contain this class? |

### Example

```forth
\ Set up element: <div id="main" class="active featured">
S" div"  S" main"  S" active featured"  CSS-MATCH-SET

\ Check individual selectors:
CSS-S-TYPE    S" div"      CSS-MATCH-SIMPLE .   \ -1
CSS-S-CLASS   S" active"   CSS-MATCH-SIMPLE .   \ -1
CSS-S-CLASS   S" hidden"   CSS-MATCH-SIMPLE .   \ 0
CSS-S-ID      S" main"     CSS-MATCH-SIMPLE .   \ -1
```

---

## Layer 5 — Specificity & Cascade

Compute and compare CSS specificity triples `(a, b, c)`.

| Word | Stack | Description |
|---|---|---|
| `CSS-SPECIFICITY` | `( sel-a sel-u -- a b c )` | Calculate specificity for a selector.  `a` = ID count, `b` = class/attr/pseudo-class count, `c` = type/pseudo-element count. |
| `CSS-SPEC-COMPARE` | `( a1 b1 c1 a2 b2 c2 -- n )` | Compare two specificities.  Returns 1 if first is higher, -1 if lower, 0 if equal. |
| `CSS-SPEC-PACK` | `( a b c -- spec )` | Pack specificity triple into a single cell: `a*10000 + b*100 + c`. |

### Example

```forth
\ Compare specificity of selectors:
S" #main .active"  CSS-SPECIFICITY   \ 1 1 0
S" div.foo.bar"    CSS-SPECIFICITY   \ 0 2 1
CSS-SPEC-COMPARE .                   \ 1 (first is higher)
```

---

## Layer 6 — Value Parsing

Parse CSS values: integers, numbers, units, hex colours, and
multi-value lists.

| Word | Stack | Description |
|---|---|---|
| `CSS-PARSE-INT` | `( a u -- a' u' n flag )` | Parse a signed integer.  Flag = -1 ok, 0 no digits. |
| `CSS-PARSE-NUMBER` | `( a u -- a' u' int frac frac-digits flag )` | Parse a CSS number (integer + optional fractional part).  Returns integer part, fractional part (as int), number of frac digits, and flag. |
| `CSS-SKIP-NUMBER` | `( a u -- a' u' )` | Skip past a number token. |
| `CSS-PARSE-UNIT` | `( a u -- a' u' unit-a unit-u )` | Parse a CSS unit identifier (e.g. `px`, `em`, `%`). |
| `CSS-PARSE-HEX-COLOR` | `( a u -- a' u' r g b flag )` | Parse `#RGB`, `#RRGGBB`, `#RGBA`, `#RRGGBBAA`.  Returns red, green, blue (0–255). |
| `CSS-SKIP-VALUE` | `( a u -- a' u' )` | Skip one CSS value token (handles strings, blocks, functions, etc.). |
| `CSS-NEXT-VALUE` | `( a u -- a' u' val-a val-u flag )` | Extract next whitespace-separated value token.  Returns its substring. |

### Example

```forth
\ Parse "16px":
S" 16px"
CSS-PARSE-INT    \ ( a' u' 16 -1 )
DROP
CSS-PARSE-UNIT   \ ( a'' u'' "px" 2 )
."  = " 2SWAP . ." in " TYPE CR
\ Output:  = 16 in px

\ Parse hex colour:
S" #ff8040"
CSS-PARSE-HEX-COLOR    \ ( a' u' 255 128 64 -1 )
IF
    ." RGB=" ROT . SWAP . . CR
ELSE 2DROP 2DROP THEN
```

---

## Layer 7 — Shorthand Expansion

Expand CSS shorthand values like `margin`, `padding`, `border-width`
that accept 1–4 values in top-right-bottom-left order.

| Word | Stack | Description |
|---|---|---|
| `CSS-EXPAND-TRBL` | `( val-a val-u -- t-a t-u r-a r-u b-a b-u l-a l-u n )` | Expand a 1–4 value shorthand into top, right, bottom, left components.  `n` = number of values provided. |

Expansion rules (per CSS spec):

| Input values | Top | Right | Bottom | Left |
|---|---|---|---|---|
| 1 value | v | v | v | v |
| 2 values | v1 | v2 | v1 | v2 |
| 3 values | v1 | v2 | v3 | v2 |
| 4 values | v1 | v2 | v3 | v4 |

### Example

```forth
S" 10px 20px"
CSS-EXPAND-TRBL   \ ( t r b l 2 )
." n=" . CR
." top=" 2SWAP TYPE CR       \ 10px
." right=" 2SWAP TYPE CR     \ 20px
." bottom=" 2SWAP TYPE CR    \ 10px
." left=" 2SWAP TYPE CR      \ 20px
```

---

## Layer 8 — @-Rule Parsing

Parse specific CSS at-rules.

| Word | Stack | Description |
|---|---|---|
| `CSS-MEDIA-QUERY` | `( a u -- cond-a cond-u body-a body-u flag )` | Parse `@media`.  Returns condition string and body.  Flag = -1 found, 0 not a media rule. |
| `CSS-IMPORT-URL` | `( a u -- url-a url-u flag )` | Parse `@import`.  Extracts the URL from `url(...)` or `"..."`.  Flag = -1 found, 0 not an import. |
| `CSS-KEYFRAMES` | `( a u -- name-a name-u body-a body-u flag )` | Parse `@keyframes`.  Returns animation name and body. |

### Example

```forth
S" @media (max-width: 768px) { .sidebar { display: none } }"
CSS-MEDIA-QUERY
IF
    ." condition: " 2SWAP TYPE CR   \ (max-width: 768px)
    ." body: " TYPE CR              \ .sidebar { display: none }
ELSE
    2DROP 2DROP ." not media" CR
THEN
```

---

## Layer 9 — Builder

Construct CSS text programmatically into a user-provided buffer.

| Word | Stack | Description |
|---|---|---|
| `CSS-SET-OUTPUT` | `( addr max -- )` | Set builder output buffer and maximum size. |
| `CSS-OUTPUT-RESET` | `( -- )` | Reset builder position to 0. |
| `CSS-OUTPUT-RESULT` | `( -- addr len )` | Return the built CSS string so far. |
| `CSS-RULE-START` | `( sel-a sel-u -- )` | Emit `selector { `. |
| `CSS-RULE-END` | `( -- )` | Emit ` }\n`. |
| `CSS-PROP!` | `( prop-a prop-u val-a val-u -- )` | Emit `property: value; `. |
| `CSS-COMMENT!` | `( txt-a txt-u -- )` | Emit `/* text */`. |
| `CSS-MEDIA-START` | `( query-a query-u -- )` | Emit `@media query { `. |
| `CSS-MEDIA-END` | `( -- )` | Emit `}\n`. |
| `CSS-IMPORT!` | `( url-a url-u -- )` | Emit `@import url("...");\n`. |

### Example

```forth
CREATE buf 1024 ALLOT
buf 1024 CSS-SET-OUTPUT

S" .card"  CSS-RULE-START
  S" color"   S" red"   CSS-PROP!
  S" margin"  S" 0"     CSS-PROP!
CSS-RULE-END

CSS-OUTPUT-RESULT TYPE
\ Output: .card { color: red; margin: 0; }
```

---

## Layer 10 — Named Colors

Look up CSS named colours by name.

| Word | Stack | Description |
|---|---|---|
| `CSS-COLOR-FIND` | `( name-a name-u -- r g b flag )` | Find a named CSS colour.  Returns RGB components (0–255) and flag.  Case-insensitive.  Covers all 148 CSS named colours. |

### Example

```forth
S" cornflowerblue"  CSS-COLOR-FIND
IF
    ." R=" ROT . ." G=" SWAP . ." B=" . CR
    \ R=100 G=149 B=237
ELSE
    2DROP ." unknown colour" CR
THEN
```

---

## Quick Reference

### Constants

```
CSS-E-NOT-FOUND        1              error: not found
CSS-E-MALFORMED        2              error: malformed
CSS-E-UNTERMINATED     3              error: unterminated
CSS-E-UNEXPECTED       4              error: unexpected
CSS-E-OVERFLOW         5              error: overflow

CSS-S-TYPE             1              selector: type
CSS-S-UNIVERSAL        2              selector: universal *
CSS-S-CLASS            3              selector: .class
CSS-S-ID               4              selector: #id
CSS-S-ATTR             5              selector: [attr]
CSS-S-PSEUDO-C         6              selector: :pseudo-class
CSS-S-PSEUDO-E         7              selector: ::pseudo-element

CSS-C-DESCENDANT       0              combinator: whitespace
CSS-C-CHILD            1              combinator: >
CSS-C-ADJACENT         2              combinator: +
CSS-C-GENERAL          3              combinator: ~
```

### Layer 0 — Scanning

```
CSS-SKIP-WS            ( a u -- a' u' )
CSS-SKIP-COMMENT       ( a u -- a' u' )
CSS-SKIP-STRING        ( a u -- a' u' )
CSS-SKIP-IDENT         ( a u -- a' u' )
CSS-GET-IDENT          ( a u -- a' u' name-a name-u )
CSS-SKIP-BLOCK         ( a u -- a' u' )
CSS-SKIP-PARENS        ( a u -- a' u' )
CSS-SKIP-UNTIL         ( a u c -- a' u' )
```

### Layer 1 — Declarations

```
CSS-DECL-NEXT          ( a u -- a' u' pa pu va vu flag )
CSS-DECL-FIND          ( a u pa pu -- va vu flag )
CSS-DECL-HAS?          ( a u pa pu -- flag )
CSS-IMPORTANT?         ( va vu -- flag )
CSS-STRIP-IMPORTANT    ( va vu -- va' vu' )
```

### Layer 2 — Rules

```
CSS-RULE-NEXT          ( a u -- a' u' sa su ba bu flag )
CSS-AT-RULE?           ( a u -- flag )
CSS-AT-RULE-NAME       ( a u -- a' u' na nu )
CSS-SKIP-AT-RULE       ( a u -- a' u' )
```

### Layer 3 — Selectors

```
CSS-SEL-NEXT-SIMPLE    ( a u -- a' u' type na nu flag )
CSS-SEL-COMBINATOR     ( a u -- a' u' comb flag )
CSS-SEL-GROUP-NEXT     ( a u -- a' u' sa su flag )
```

### Layer 4 — Matching

```
CSS-MATCH-SET          ( ta tu ia iu ca cu -- )
CSS-MATCH-SIMPLE       ( type sa su -- flag )
CSS-MATCH-TYPE         ( sa su ta tu -- flag )
CSS-MATCH-ID           ( sa su ia iu -- flag )
CSS-MATCH-CLASS        ( ca cu csa csu -- flag )
```

### Layer 5 — Specificity

```
CSS-SPECIFICITY        ( sa su -- a b c )
CSS-SPEC-COMPARE       ( a1 b1 c1 a2 b2 c2 -- n )
CSS-SPEC-PACK          ( a b c -- spec )
```

### Layer 6 — Values

```
CSS-PARSE-INT          ( a u -- a' u' n flag )
CSS-PARSE-NUMBER       ( a u -- a' u' int frac fd flag )
CSS-SKIP-NUMBER        ( a u -- a' u' )
CSS-PARSE-UNIT         ( a u -- a' u' ua uu )
CSS-PARSE-HEX-COLOR    ( a u -- a' u' r g b flag )
CSS-SKIP-VALUE         ( a u -- a' u' )
CSS-NEXT-VALUE         ( a u -- a' u' va vu flag )
```

### Layer 7 — Shorthand

```
CSS-EXPAND-TRBL        ( va vu -- ta tu ra ru ba bu la lu n )
```

### Layer 8 — @-Rules

```
CSS-MEDIA-QUERY        ( a u -- ca cu ba bu flag )
CSS-IMPORT-URL         ( a u -- ua uu flag )
CSS-KEYFRAMES          ( a u -- na nu ba bu flag )
```

### Layer 9 — Builder

```
CSS-SET-OUTPUT         ( addr max -- )
CSS-OUTPUT-RESET       ( -- )
CSS-OUTPUT-RESULT      ( -- addr len )
CSS-RULE-START         ( sa su -- )
CSS-RULE-END           ( -- )
CSS-PROP!              ( pa pu va vu -- )
CSS-COMMENT!           ( ta tu -- )
CSS-MEDIA-START        ( qa qu -- )
CSS-MEDIA-END          ( -- )
CSS-IMPORT!            ( ua uu -- )
```

### Layer 10 — Colors

```
CSS-COLOR-FIND         ( na nu -- r g b flag )
```

---

## Internal Words

These are prefixed with `_CSS-`, `_CDN-`, `_CDF-`, `_CRN-`, etc. and
are not part of the public API.

| Word / Variable | Purpose |
|---|---|
| `_CSS-WS?`, `_CSS-IDENT-CHAR?`, `_CSS-IDENT-START?` | Character class checks. |
| `_CSS-TOLOWER` | ASCII lowercase helper. |
| `_CSS-STR=`, `_CSS-STRI=` | String comparison (exact / case-insensitive). |
| `_CSS-TRIM-END` | Trim trailing whitespace. |
| `_CSS-DIGIT?` | Decimal digit check. |
| `_CSS-HEX-DIGIT`, `_CSS-HEX-PAIR` | Hex parsing helpers. |
| `_CSS-EXTRACT-BODY` | Extract `{ body }` from cursor. |
| `_CSS-IS-URL-FUNC?` | Check for `url(` prefix. |
| `_CSS-STRING-CONTENT` | Strip quotes from a string token. |
| `_CSC-A`, `_CSW-A` | State for comment/whitespace skipping. |
| `_CSB-D`, `_CSP-D` | Depth counters for block/paren skipping. |
| `_CDN-PA/PL/VA/VL` | State for `CSS-DECL-NEXT`. |
| `_CDF-SA/SL` | State for `CSS-DECL-FIND`. |
| `_CIP-A` | State for `CSS-IMPORTANT?`. |
| `_CSAR-A` | State for `CSS-SKIP-AT-RULE`. |
| `_CRN-SA/SL/BA/BL/D` | State for `CSS-RULE-NEXT`. |
| `_CSNS-A` | State for `CSS-SEL-NEXT-SIMPLE`. |
| `_CSGN-A` | State for `CSS-SEL-GROUP-NEXT`. |
| `_CMC-CA/CL/TA` | State for `CSS-MATCH-CLASS`. |
| `_CMS-TA/TL/IA/IL/CA/CL` | Match state for `CSS-MATCH-SET`. |
| `_CSP-A/B/C` | State for `CSS-SPECIFICITY`. |
| `_SPC-A2/B2/C2` | State for `CSS-SPEC-COMPARE`. |
| `_CPI-N/NEG` | State for `CSS-PARSE-INT`. |
| `_CPN-INT/FRAC/FD/NEG/OK` | State for `CSS-PARSE-NUMBER`. |
| `_CPU-A` | State for `CSS-PARSE-UNIT`. |
| `_CHC-A/R/G/B` | State for `CSS-PARSE-HEX-COLOR`. |
| `_CNV-A` | State for `CSS-NEXT-VALUE`. |
| `_CET-TA/TL/RA/RL/BA/BL/LA/LL/N` | State for `CSS-EXPAND-TRBL`. |
| `_CEB-A/BA/BL` | State for `_CSS-EXTRACT-BODY`. |
| `_CMQ-CA/CL/BA/BL` | State for `CSS-MEDIA-QUERY`. |
| `_CIU-A` | State for `CSS-IMPORT-URL`. |
| `_CKF-NA/NL/BA/BL` | State for `CSS-KEYFRAMES`. |
| `_CB-BUF/MAX/POS` | Builder buffer state. |
| `_CSS-EMIT`, `_CSS-TYPE` | Builder output primitives. |
| `_CSS-COLOR-TABLE` | 148-entry packed colour table (4 bytes each). |
| `_CCF-P` | State for `CSS-COLOR-FIND`. |

---

## Cookbook

### Find a property value

```forth
S" color: red; margin: 0 auto; font-size: 16px"
S" margin"  CSS-DECL-FIND
IF TYPE ELSE 2DROP ." not found" THEN
\ Output: 0 auto
```

### Check !important

```forth
S" 16px !important"
DUP CSS-IMPORTANT? IF
    ." important! value=" CSS-STRIP-IMPORTANT TYPE
ELSE
    ." normal value=" TYPE
THEN
```

### Expand margin shorthand

```forth
S" 10px 20px 30px"
CSS-EXPAND-TRBL
." n=" . CR
." L=" TYPE CR  ." B=" TYPE CR
." R=" TYPE CR  ." T=" TYPE CR
```

### Match selector against element properties

```forth
\ Element: <span class="highlight active">
S" span"  S" "  S" highlight active"  CSS-MATCH-SET

\ Test: span.highlight
S" span.highlight"
BEGIN
    CSS-SEL-NEXT-SIMPLE
WHILE
    CSS-MATCH-SIMPLE 0= IF ." mismatch" CR THEN
REPEAT
2DROP DROP
." compound matched" CR
```

### Build a media query

```forth
CREATE buf 2048 ALLOT
buf 2048 CSS-SET-OUTPUT

S" (max-width: 768px)"  CSS-MEDIA-START
  S" .sidebar"  CSS-RULE-START
    S" display"  S" none"  CSS-PROP!
  CSS-RULE-END
CSS-MEDIA-END

CSS-OUTPUT-RESULT TYPE
```
