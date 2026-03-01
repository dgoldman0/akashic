# akashic-sml-core — SML Parser Core for KDOS / Megapad-64

Element classification, validation, and attribute extraction for
the Sequential Markup Language (SML) — the modality-neutral
document format for 1D user interfaces.

SML uses angle-bracket XML syntax.  This module builds on
`markup/core.f` for low-level tag scanning, attribute parsing, and
entity decoding, adding SML-specific element types, content-model
validation, and convenience accessors.

```forth
REQUIRE sml/core.f
```

`PROVIDED akashic-sml-core` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Error Handling](#error-handling)
- [Element Type Constants](#element-type-constants)
- [Element Name Table & Classification](#element-name-table--classification)
- [Category Predicates](#category-predicates)
- [Attribute Access](#attribute-access)
- [Content Model Validation](#content-model-validation)
- [Element Enumeration](#element-enumeration)
- [Scope Kind Checks](#scope-kind-checks)
- [Val Kind Validation](#val-kind-validation)
- [Pick Choice Count](#pick-choice-count)
- [Document Validation](#document-validation)
- [Child Counting](#child-counting)
- [Tag Body Extraction](#tag-body-extraction)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Markup delegation** | Low-level scanning delegates to `markup/core.f` (`MU-SKIP-TAG`, `MU-GET-TAG-NAME`, `MU-ATTR-FIND`, etc.). No duplicate parsing logic. |
| **Table-driven classification** | The 25 SML elements are stored in a compact counted-string table. `SML-TYPE?` performs a linear scan — fast enough for the small vocabulary. |
| **Streaming validation** | `SML-VALID?` walks the document once, tracking a parent-type stack of up to 16 levels. No tree construction required. |
| **Zero-copy accessors** | All attribute reads return pointers into the original document buffer. |
| **Prefix convention** | Public API uses `SML-` prefix. Internal helpers use `_SML-` or `_SVD-` / `_SCC-` etc. |
| **VARIABLE-based state** | Module-scoped VARIABLEs for validator stack, table pointer, etc. Not re-entrant. |

---

## Dependencies

```forth
REQUIRE ../markup/core.f    \ tag scanner, attrs, entities (853 lines)
REQUIRE ../text/utf8.f      \ UTF-8 codec
```

Also requires `utils/string.f` (via markup/core.f) for `STR-STR=`.

---

## Error Handling

A single `VARIABLE SML-ERR` holds the last error code.  Zero means
no error.  The validator sets this on failure.

| Word | Stack | Description |
|---|---|---|
| `SML-ERR` | `( -- addr )` | Variable holding last error code |
| `SML-FAIL` | `( code -- )` | Store error code into `SML-ERR` |
| `SML-OK?` | `( -- flag )` | TRUE if `SML-ERR` is zero |
| `SML-CLEAR-ERR` | `( -- )` | Reset `SML-ERR` to zero |

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `SML-E-BAD-ROOT` | 1 | Root element is not `<sml>` |
| `SML-E-BAD-ELEMENT` | 2 | Unknown / unrecognised element name |
| `SML-E-BAD-NEST` | 3 | Element appears in wrong parent context |
| `SML-E-MISSING-ATTR` | 4 | Required attribute missing |
| `SML-E-EMPTY-DOC` | 5 | No content found (empty or whitespace-only) |
| `SML-E-TOO-DEEP` | 6 | Nesting exceeds `SML-MAX-DEPTH` (16) |
| `SML-E-DUPLICATE-ID` | 7 | Duplicate `id` attribute detected |
| `SML-E-BAD-KIND` | 8 | Invalid `kind=` attribute value |

```forth
\ Check error after validation
S" <div></div>" SML-VALID?   \ → 0  (false)
SML-ERR @                    \ → 1  (SML-E-BAD-ROOT)
```

---

## Element Type Constants

SML defines 25 elements grouped into 6 categories (SML spec §9),
plus a sentinel for unrecognised names.

| Constant | Value | Elements |
|---|---|---|
| `SML-T-ENVELOPE` | 0 | `sml`, `head` |
| `SML-T-META` | 1 | `title`, `meta`, `link`, `style`, `cue-def` |
| `SML-T-SCOPE` | 2 | `seq`, `ring`, `gate`, `trap` |
| `SML-T-POSITION` | 3 | `item`, `act`, `val`, `pick`, `ind`, `tick`, `alert` |
| `SML-T-STRUCT` | 4 | `announce`, `shortcut`, `hint`, `gap`, `lane` |
| `SML-T-COMPOSE` | 5 | `frag`, `slot` |
| `SML-T-UNKNOWN` | 6 | Not a recognised SML element |

---

## Element Name Table & Classification

The 25 elements are stored in a compact `CREATE` table (`_SML-ELEMS`).
Each entry is: 1 byte name-length, N bytes name (ASCII), 1 byte type.
A zero-length sentinel terminates the table.

### SML-TYPE?

```
SML-TYPE? ( name-a name-u -- type )
```

Classify an element name string into one of the `SML-T-*` constants.
Performs a linear scan of `_SML-ELEMS`.  Returns `SML-T-UNKNOWN` (6)
for names not in the table.

```forth
S" item" SML-TYPE?   \ → 3  (SML-T-POSITION)
S" seq"  SML-TYPE?   \ → 2  (SML-T-SCOPE)
S" div"  SML-TYPE?   \ → 6  (SML-T-UNKNOWN)
```

---

## Category Predicates

Simple type-to-boolean checks:

| Word | Stack | Description |
|---|---|---|
| `SML-ENVELOPE?` | `( type -- flag )` | True for `SML-T-ENVELOPE` |
| `SML-META?` | `( type -- flag )` | True for `SML-T-META` |
| `SML-SCOPE?` | `( type -- flag )` | True for `SML-T-SCOPE` |
| `SML-POSITION?` | `( type -- flag )` | True for `SML-T-POSITION` |
| `SML-STRUCT?` | `( type -- flag )` | True for `SML-T-STRUCT` |
| `SML-COMPOSE?` | `( type -- flag )` | True for `SML-T-COMPOSE` |

### Compound Predicates

| Word | Stack | Description |
|---|---|---|
| `SML-NAVIGABLE?` | `( type -- flag )` | True for scope OR position — elements that participate in cursor navigation |
| `SML-CONTAINER?` | `( type -- flag )` | True for envelope OR scope OR compose — elements that can have children |

```forth
SML-T-SCOPE SML-NAVIGABLE?    \ → -1  (true)
SML-T-META  SML-NAVIGABLE?    \ → 0   (false)
SML-T-COMPOSE SML-CONTAINER?  \ → -1  (true)
SML-T-STRUCT  SML-CONTAINER?  \ → 0   (false)
```

---

## Attribute Access

### SML-ATTR

```
SML-ATTR ( body-a body-u attr-a attr-u -- val-a val-u flag )
```

Read an attribute value from a tag body string.  The body string is
everything between `<` and `>`.  Skips whitespace, handles close-tag
`/` prefix, skips the tag name, then delegates to `MU-ATTR-FIND`.

Returns `( val-a val-u -1 )` on success, `( 0 0 0 )` if not found.

### Convenience Shortcuts

| Word | Stack | Description |
|---|---|---|
| `SML-ATTR-ID` | `( body-a body-u -- val-a val-u flag )` | Read `id` attribute |
| `SML-ATTR-LABEL` | `( body-a body-u -- val-a val-u flag )` | Read `label` attribute |
| `SML-ATTR-KIND` | `( body-a body-u -- val-a val-u flag )` | Read `kind` attribute |

These skip directly to `MU-ATTR-FIND` with the appropriate attribute
name — slightly faster than `SML-ATTR` since they skip the tag-name
skip step (caller should ensure cursor is past the tag name).

```forth
\ Given body: 'seq id="main" label="Main Menu"'
S" seq id=\"main\" label=\"Main Menu\"" S" id" SML-ATTR
\ → addr 4 -1   (value = "main")
```

---

## Content Model Validation

### SML-VALID-CHILD?

```
SML-VALID-CHILD? ( parent-type child-type -- flag )
```

Encodes the SML content model rules (SML spec §9):

| Parent Type | Allowed Child Types |
|---|---|
| **Envelope** | envelope, meta, scope, compose |
| **Scope** | scope, position, struct, compose |
| **Position** | struct, compose |
| **Compose** | scope, position, struct, compose |
| **Meta** | *(leaf — no children)* |
| **Struct** | *(leaf — no children)* |

```forth
SML-T-ENVELOPE SML-T-META SML-VALID-CHILD?      \ → -1  (yes)
SML-T-ENVELOPE SML-T-POSITION SML-VALID-CHILD?  \ → 0   (no)
SML-T-SCOPE SML-T-POSITION SML-VALID-CHILD?     \ → -1  (yes)
SML-T-META SML-T-SCOPE SML-VALID-CHILD?         \ → 0   (leaf)
```

---

## Element Enumeration

### SML-ELEM-COUNT

```
SML-ELEM-COUNT ( -- 25 )
```

Constant: the total number of defined SML elements.

### SML-ELEM-NTH

```
SML-ELEM-NTH ( n -- name-a name-u type )
```

Return the *n*th element's name and type (0-based index).  Returns
`( 0 0 SML-T-UNKNOWN )` if *n* is out of range (< 0 or ≥ 25).

Elements are stored in table order:

| Index | Element | Type |
|---|---|---|
| 0 | sml | ENVELOPE |
| 1 | head | ENVELOPE |
| 2 | title | META |
| 3 | meta | META |
| … | … | … |
| 23 | frag | COMPOSE |
| 24 | slot | COMPOSE |

```forth
0 SML-ELEM-NTH   \ → addr 3 0   (name="sml", type=ENVELOPE)
24 SML-ELEM-NTH  \ → addr 4 5   (name="slot", type=COMPOSE)
25 SML-ELEM-NTH  \ → 0 0 6      (out of range)
```

---

## Scope Kind Checks

The four scope elements have distinct traversal behaviours:

| Word | Stack | Description |
|---|---|---|
| `SML-SEQ?` | `( name-a name-u -- flag )` | True if name is "seq" (linear sequence) |
| `SML-RING?` | `( name-a name-u -- flag )` | True if name is "ring" (circular wrap) |
| `SML-GATE?` | `( name-a name-u -- flag )` | True if name is "gate" (locked until condition) |
| `SML-TRAP?` | `( name-a name-u -- flag )` | True if name is "trap" (sticky until explicit exit) |

```forth
S" ring" SML-RING?  \ → -1  (true)
S" seq"  SML-RING?  \ → 0   (false)
```

---

## Val Kind Validation

### SML-VALID-VAL-KIND?

```
SML-VALID-VAL-KIND? ( str-a str-u -- flag )
```

Validate a `kind=` attribute value for `<val>` elements.  The four
valid kinds are:

| Kind | Description |
|---|---|
| `text` | Text input field |
| `range` | Numeric range / slider |
| `toggle` | Boolean on/off toggle |
| `display` | Read-only display value |

Returns TRUE (-1) if the string matches one of these, FALSE (0)
otherwise.

```forth
S" text"     SML-VALID-VAL-KIND?  \ → -1
S" checkbox" SML-VALID-VAL-KIND?  \ → 0
```

---

## Pick Choice Count

### SML-PICK-COUNT

```
SML-PICK-COUNT ( body-a body-u -- n )
```

Count the number of `|`-separated choices in the `choices=` attribute
of a `<pick>` element.  Reads the `choices` attribute from the tag
body, counts pipe separators, and returns count + 1.

Returns 0 if no `choices=` attribute is found.

```forth
\ body: 'pick choices="A|B|C"'
S" pick choices=\"A|B|C\"" SML-PICK-COUNT  \ → 3
```

---

## Document Validation

### SML-VALID?

```
SML-VALID? ( a u -- flag )
```

Validate an SML document string by streaming through it once.  Checks:

1. **Root element** — must be `<sml>`
2. **Known elements** — all element names must be in the SML vocabulary
3. **Nesting depth** — must not exceed `SML-MAX-DEPTH` (16 levels)
4. **Content model** — each child element must be valid for its parent type

Tracks a parent-type stack (`_SVD-STACK`, 16 bytes) to enforce nesting
rules.  Sets `SML-ERR` on failure with the appropriate error code.

Returns TRUE (-1) if the document is structurally valid, FALSE (0)
otherwise.

```forth
S" <sml><seq><item/></seq></sml>" SML-VALID?  \ → -1  (valid)
S" <div></div>" SML-VALID?                    \ → 0   (bad root)
SML-ERR @                                     \ → 1   (SML-E-BAD-ROOT)
```

### Internal Helpers

| Word | Stack | Description |
|---|---|---|
| `_SML-PUSH-TYPE` | `( type -- ok? )` | Push element type onto validator stack; returns FALSE if depth exceeded |
| `_SML-POP-TYPE` | `( -- )` | Pop one level from validator stack |
| `_SML-PARENT-TYPE` | `( -- type )` | Read current parent type from stack top |

### SML-MAX-DEPTH

```
SML-MAX-DEPTH ( -- 16 )
```

Maximum nesting depth the validator supports.

---

## Child Counting

### SML-COUNT-CHILDREN

```
SML-COUNT-CHILDREN ( a u -- n )
```

Count direct child elements inside a container element.  The cursor
must be at the opening tag of the container.  Uses `MU-INNER` to
enter the container, then iterates siblings counting open/self-closing
tags.  Skips nested content via `MU-SKIP-ELEMENT`.

```forth
S" <seq><item/><item/><item/></seq>" SML-COUNT-CHILDREN  \ → 3
S" <seq></seq>" SML-COUNT-CHILDREN                       \ → 0
```

---

## Tag Body Extraction

### SML-TAG-BODY

```
SML-TAG-BODY ( a u -- body-a body-u name-a name-u )
```

From a cursor at a tag, extract both the tag body (everything between
`<` and `>`) and the tag name in one pass.  Useful for getting
attributes and the element name together.

```forth
S" <item id=\"x\"/>" SML-TAG-BODY
\ → body-a body-u name-a name-u
\ body = "item id=\"x\"/"   name = "item"
```

---

## Quick Reference

| Word | Stack | Brief |
|---|---|---|
| `SML-ERR` | `( -- addr )` | Error variable |
| `SML-FAIL` | `( code -- )` | Set error |
| `SML-OK?` | `( -- flag )` | No error? |
| `SML-CLEAR-ERR` | `( -- )` | Reset error |
| `SML-TYPE?` | `( name-a name-u -- type )` | Classify element name |
| `SML-ENVELOPE?` | `( type -- flag )` | Type = envelope? |
| `SML-META?` | `( type -- flag )` | Type = meta? |
| `SML-SCOPE?` | `( type -- flag )` | Type = scope? |
| `SML-POSITION?` | `( type -- flag )` | Type = position? |
| `SML-STRUCT?` | `( type -- flag )` | Type = struct? |
| `SML-COMPOSE?` | `( type -- flag )` | Type = compose? |
| `SML-NAVIGABLE?` | `( type -- flag )` | Scope or position? |
| `SML-CONTAINER?` | `( type -- flag )` | Envelope, scope, or compose? |
| `SML-ATTR` | `( body-a body-u attr-a attr-u -- val-a val-u flag )` | Read attribute |
| `SML-ATTR-ID` | `( body-a body-u -- val-a val-u flag )` | Read `id` |
| `SML-ATTR-LABEL` | `( body-a body-u -- val-a val-u flag )` | Read `label` |
| `SML-ATTR-KIND` | `( body-a body-u -- val-a val-u flag )` | Read `kind` |
| `SML-VALID-CHILD?` | `( parent child -- flag )` | Content model check |
| `SML-ELEM-COUNT` | `( -- 25 )` | Element count |
| `SML-ELEM-NTH` | `( n -- name-a name-u type )` | Enumerate elements |
| `SML-SEQ?` | `( name-a name-u -- flag )` | Name = "seq"? |
| `SML-RING?` | `( name-a name-u -- flag )` | Name = "ring"? |
| `SML-GATE?` | `( name-a name-u -- flag )` | Name = "gate"? |
| `SML-TRAP?` | `( name-a name-u -- flag )` | Name = "trap"? |
| `SML-VALID-VAL-KIND?` | `( str-a str-u -- flag )` | Valid val kind? |
| `SML-PICK-COUNT` | `( body-a body-u -- n )` | Count pick choices |
| `SML-VALID?` | `( a u -- flag )` | Validate document |
| `SML-COUNT-CHILDREN` | `( a u -- n )` | Count child elements |
| `SML-TAG-BODY` | `( a u -- body-a body-u name-a name-u )` | Extract body + name |

---

## Cookbook

### Validate and Inspect Error

```forth
REQUIRE sml/core.f

: CHECK-DOC  ( a u -- )
    SML-CLEAR-ERR
    SML-VALID? IF
        ." Valid SML document" CR
    ELSE
        ." Invalid: error code " SML-ERR @ . CR
    THEN ;

S" <sml><seq><item/></seq></sml>" CHECK-DOC
\ → Valid SML document

S" <div></div>" CHECK-DOC
\ → Invalid: error code 1
```

### Classify and Count

```forth
REQUIRE sml/core.f

\ Classify an element
S" item" SML-TYPE?   \ → 3  (POSITION)
DUP SML-NAVIGABLE?  \ → -1 (true — position is navigable)

\ Count children in a scope
S" <seq><item/><item/><gap/></seq>" SML-COUNT-CHILDREN  \ → 3
```

### Enumerate All Elements

```forth
REQUIRE sml/core.f

: LIST-ELEMENTS  ( -- )
    SML-ELEM-COUNT 0 DO
        I SML-ELEM-NTH      \ ( name-a name-u type )
        ROT ROT TYPE         \ print name
        SPACE ." type=" .    \ print type
        CR
    LOOP ;

LIST-ELEMENTS
\ sml type=0
\ head type=0
\ title type=1
\ ... etc.
```

### Extract Attributes from a Tag

```forth
REQUIRE sml/core.f

S" <val id=\"vol\" kind=\"range\" label=\"Volume\"/>"
2DUP MU-GET-TAG-BODY  \ get body string
S" kind" SML-ATTR     \ → addr 5 -1   (value = "range")
IF
    SML-VALID-VAL-KIND?  \ → -1  (valid)
THEN
```
